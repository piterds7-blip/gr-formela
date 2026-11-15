# =====================================================================
#  GR FORMELA - agent synchronizacji Infodex -> Firebase
#  TYLKO ODCZYTUJE baze Infodexu. Niczego w Infodexie nie zmienia.
#  Uruchamiany dwa razy na dobe (06:00 i 17:00) przez Harmonogram zadan Windows.
#  Log: gr_formela_sync.log (w tym samym folderze)
# =====================================================================
param(
  [switch]$Full,        # wyslij cala historie (pierwsze uruchomienie robi to samo)
  [switch]$DryRun,      # nic nie wysylaj, zapisz JSON do folderu "dryrun"
  [int]$Days = 10,      # ile ostatnich dni odswiezac przy zwyklym uruchomieniu
  [switch]$Export,      # NIE wysylaj do Firebase - zapisz plik (do wczytania w aplikacji)
  [string]$OutFile = '', # sciezka pliku eksportu (domyslnie Pulpit\infodex_export.json)
  [switch]$InstallTask, # ustaw codzienne uruchamianie o 06:00 i 17:00 (Harmonogram zadan)
  [switch]$SetAccount   # wpisz konto agenta (e-mail i haslo) - haslo zapisywane zaszyfrowane przez Windows
)

$ErrorActionPreference = 'Stop'
$AGENT_VERSION = '1.6.0'

# ---- KONFIGURACJA (jedna farma = jeden plik) -------------------------
$PROJECT   = 'gr-formela-po-app'
$API_KEY   = 'AIzaSyAc-bIk_42l-U-xJBWZ6wGKbu18zeum1KE'
$FARM      = 'formela'
$SQLCONN   = 'Server=.\SQLPOLANES;Database=infodexDb;Integrated Security=True;Application Name=GRFormelaSync;Connect Timeout=30'
$START     = '2025-04-01'   # od kiedy historia przy pelnej synchronizacji
$HEAT_KEY  = 'DbId'         # kolumna w Cows/Heifers, ktorej odpowiada HeatFeedData.CowDbId
# ----------------------------------------------------------------------

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
# konto agenta: plik w profilu uzytkownika Windows; haslo zaszyfrowane (DPAPI) - odczyta je tylko ten uzytkownik na tym komputerze
$acctDir = Join-Path $env:USERPROFILE 'GRFormela'
$acctF   = Join-Path $acctDir 'gr_formela_konto.xml'
$log   = Join-Path $here 'gr_formela_sync.log'
$state = Join-Path $here 'gr_formela_sync.state'
$inv   = [Globalization.CultureInfo]::InvariantCulture

function Log([string]$m) {
  $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $m
  Write-Host $line
  try {
    if ((Test-Path $log) -and ((Get-Item $log).Length -gt 2MB)) { Move-Item $log ($log + '.old') -Force }
    Add-Content -Path $log -Value $line -Encoding UTF8
  } catch {}
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---------------- SQL (tylko SELECT) ----------------------------------
function Q([string]$sql) {
  $cn = New-Object System.Data.SqlClient.SqlConnection $SQLCONN
  $cn.Open()
  try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; ' + $sql
    $cmd.CommandTimeout = 600
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable
    [void]$da.Fill($t)
    return ,$t
  } finally { $cn.Close() }
}

function N($v) { if ($null -eq $v -or $v -is [DBNull]) { $null } else { $v } }
function R1($v) { $v = N $v; if ($null -eq $v) { $null } else { [math]::Round([double]$v, 1) } }
function I($v)  { $v = N $v; if ($null -eq $v) { $null } else { [long]$v } }
function S($v)  { $v = N $v; if ($null -eq $v) { $null } else { ([string]$v).Trim() } }

# słownik bez pustych wartosci
function M([hashtable]$h) {
  $o = @{}
  foreach ($k in $h.Keys) {
    $v = $h[$k]
    if ($null -eq $v) { continue }
    if ($v -is [string] -and $v.Length -eq 0) { continue }
    $o[$k] = $v
  }
  return $o
}

# ---------------- Firestore REST --------------------------------------
function FV($v) {
  if ($null -eq $v -or $v -is [DBNull]) { return @{ nullValue = $null } }
  if ($v -is [bool]) { return @{ booleanValue = $v } }
  if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) { return @{ integerValue = [string]$v } }
  if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { return @{ doubleValue = [double]$v } }
  if ($v -is [datetime]) { return @{ stringValue = $v.ToString('yyyy-MM-dd HH:mm', $inv) } }
  if ($v -is [System.Collections.IDictionary]) {
    $f = @{}
    foreach ($k in $v.Keys) { $f[[string]$k] = FV $v[$k] }
    return @{ mapValue = @{ fields = $f } }
  }
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
    $a = New-Object System.Collections.ArrayList
    foreach ($x in $v) { [void]$a.Add((FV $x)) }
    return @{ arrayValue = @{ values = $a.ToArray() } }
  }
  return @{ stringValue = [string]$v }
}

# ---------------- logowanie agenta (Firebase Authentication) ----------
# Baza przyjmuje dane tylko od zalogowanego agenta dodanego w aplikacji (zakladka Dostep, rola: agent).
$script:tok = $null; $script:tokAt = [datetime]::MinValue
function Get-IdToken {
  if ($script:tok -and ((Get-Date) - $script:tokAt).TotalMinutes -lt 45) { return $script:tok }
  if (-not (Test-Path $acctF)) { throw 'KONTO: brak konta agenta na tym komputerze. Uruchom USTAW_KONTO.bat.' }
  $cred = Import-Clixml $acctF
  $body = @{ email = $cred.UserName; password = $cred.GetNetworkCredential().Password; returnSecureToken = $true } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$API_KEY" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
  } catch {
    $msg = $_.Exception.Message
    try { $msg = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
    if ($msg -match 'INVALID_PASSWORD|EMAIL_NOT_FOUND|INVALID_LOGIN_CREDENTIALS|INVALID_EMAIL|USER_DISABLED') { throw 'KONTO: zle haslo agenta (albo konto usuniete w zakladce Dostep). Uruchom USTAW_KONTO.bat.' }
    throw "Logowanie agenta nie powiodlo sie: $msg"
  }
  $script:tok = $r.idToken; $script:tokAt = Get-Date
  return $script:tok
}
# konto agenta = skrot hasla (tak samo jak w aplikacji): wpisuje sie tylko haslo nadane w zakladce "Dostep"
function PwEmail([string]$pw) {
  $sha = [Security.Cryptography.SHA256]::Create()
  $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('grformela|' + $pw))
  return 'u' + ((($h | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 32)) + '@grformela.app'
}
function Set-Account {
  Write-Host ''
  Write-Host ' Wpisz haslo agenta z aplikacji (zakladka Dostep -> Komputer w oborze).'
  Write-Host ' Haslo nie bedzie widoczne podczas wpisywania. Zapisze sie zaszyfrowane na tym komputerze.'
  Write-Host ''
  $pw = Read-Host ' Haslo agenta' -AsSecureString
  if ($pw.Length -eq 0) { Log 'BLAD: nie podano hasla.'; return $false }
  $plain = (New-Object System.Management.Automation.PSCredential('x', $pw)).GetNetworkCredential().Password.Trim()
  $em = PwEmail $plain
  if (-not (Test-Path $acctDir)) { New-Item -ItemType Directory $acctDir | Out-Null }
  $old = $null; if (Test-Path $acctF) { $old = Get-Content $acctF -Raw }
  (New-Object System.Management.Automation.PSCredential($em, (ConvertTo-SecureString $plain -AsPlainText -Force))) | Export-Clixml $acctF
  $plain = $null
  $script:tok = $null
  try { [void](Get-IdToken); Log 'Konto agenta zapisane i sprawdzone.'; return $true }
  catch {
    Log ('BLAD: ' + $_.Exception.Message)
    if ($old) { Set-Content -Path $acctF -Value $old -NoNewline } else { Remove-Item $acctF -Force }
    return $false
  }
}

$script:dryN = 0
$BASE = "projects/$PROJECT/databases/(default)/documents"

function Commit($docs, [int]$chunk = 25) {
  $sent = 0
  for ($i = 0; $i -lt $docs.Count; $i += $chunk) {
    $last = [math]::Min($i + $chunk - 1, $docs.Count - 1)
    $writes = New-Object System.Collections.ArrayList
    foreach ($d in $docs[$i..$last]) {
      $f = @{}
      foreach ($k in $d.data.Keys) { $f[[string]$k] = FV $d.data[$k] }
      [void]$writes.Add(@{ update = @{ name = "$BASE/$($d.path)"; fields = $f } })
    }
    $body = @{ writes = $writes.ToArray() } | ConvertTo-Json -Depth 40 -Compress
    if ($DryRun) {
      $dd = Join-Path $here 'dryrun'
      if (-not (Test-Path $dd)) { New-Item -ItemType Directory $dd | Out-Null }
      $script:dryN++
      [IO.File]::WriteAllText((Join-Path $dd ("commit_{0:D4}.json" -f $script:dryN)), $body, (New-Object Text.UTF8Encoding $false))
    } else {
      $uri = "https://firestore.googleapis.com/v1/${BASE}:commit?key=$API_KEY"
      $bytes = [Text.Encoding]::UTF8.GetBytes($body)
      $ok = $false
      for ($try = 1; $try -le 3 -and -not $ok; $try++) {
        try {
          Invoke-RestMethod -UseBasicParsing -Method Post -Uri $uri -Headers @{ Authorization = 'Bearer ' + (Get-IdToken) } -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 120 | Out-Null
          $ok = $true
        } catch {
          $msg = $_.Exception.Message
          if ($msg -like 'KONTO:*') { throw }
          try { $msg += ' | ' + (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
          if ($msg -match 'PERMISSION_DENIED|\(403\)') { throw 'KONTO: baza odrzucila dane agenta (brak uprawnien). Sprawdz w aplikacji, zakladka Dostep, czy agent nie jest zablokowany.' }
          if ($msg -match '\(401\)') { $script:tok = $null }
          if ($try -ge 3) { throw "Firebase odrzucil zapis: $msg" }
          Start-Sleep -Seconds (5 * $try)
        }
      }
    }
    $sent += ($last - $i + 1)
  }
  return $sent
}

# ---------------- dane -------------------------------------------------
function Sum12([string]$prefix) {
  (0..11 | ForEach-Object { "ISNULL(h.$prefix$_,0)" }) -join '+'
}
function Cnt12([string]$prefix) {
  (0..11 | ForEach-Object { "(CASE WHEN h.$prefix$_ IS NULL THEN 0 ELSE 1 END)" }) -join '+'
}

function Get-Herd {
  $cows = Q @"
SELECT c.Id, c.DbId, c.PassportNumber, c.Tag, c.PedometerTag, c.CowGroup, c.LifeCycle,
       c.BirthDate, c.FeedingType, c.DoNotBreed,
       l.CycleState, l.CalvingCount, l.InsemCount, l.InsemSuccessful, l.LactationDay
FROM Cows c LEFT JOIN LifeCycles l ON l.CowId = c.Id
"@
  $hf = Q 'SELECT Id, DbId, PassportNumber, Tag, PedometerTag, CowGroup, BirthDate, HeiferMoveDate FROM Heifers'
  $gr = Q 'SELECT Id, Name FROM CowGroups'

  $c = @{}
  foreach ($r in $cows.Rows) {
    $c[[string]$r.Id] = M @{
      ear = S $r.PassportNumber; rfid = S $r.Tag; ped = S $r.PedometerTag; dbid = I $r.DbId
      grp = I $r.CowGroup; state = I $r.CycleState; lc = I $r.LifeCycle
      dim = I $r.LactationDay; calv = I $r.CalvingCount; ins = I $r.InsemCount; insOk = I $r.InsemSuccessful
      birth = $(if (N $r.BirthDate) { ([datetime]$r.BirthDate).ToString('yyyy-MM-dd', $inv) } else { $null })
      feedType = I $r.FeedingType; noBreed = $(if ($null -ne (N $r.DoNotBreed)) { [bool]$r.DoNotBreed } else { $null })
    }
  }
  $h = @{}
  foreach ($r in $hf.Rows) {
    $h[[string]$r.Id] = M @{
      ear = S $r.PassportNumber; rfid = S $r.Tag; ped = S $r.PedometerTag; dbid = I $r.DbId; grp = I $r.CowGroup
      birth = $(if (N $r.BirthDate) { ([datetime]$r.BirthDate).ToString('yyyy-MM-dd', $inv) } else { $null })
    }
  }
  $g = @{}
  foreach ($r in $gr.Rows) { $g[[string]$r.Id] = S $r.Name }
  return @{ cows = $c; heifers = $h; groups = $g; heatKey = $HEAT_KEY }
}

function Get-Events {
  $t = Q 'SELECT Id, CowId, Date, EventType FROM Events ORDER BY Date'
  Log ("  zdarzenia: {0}" -f $t.Rows.Count)
  # szczegoly (wynik ciazy, cielieta) - jedno zapytanie; gdy sie nie uda, jedziemy dalej bez nich
  $det = @{}
  try {
    $dt = Q 'SELECT CowId, Date, EventType, Result, CalfsCount, Sex, BullName FROM EventsDetails'
    foreach ($r in $dt.Rows) {
      $k = '{0}|{1}|{2}' -f $r.CowId, ([datetime]$r.Date).ToString('yyyyMMddHHmmss', $inv), $r.EventType
      if (-not $det.ContainsKey($k)) { $det[$k] = $r }
    }
    Log ("  szczegoly zdarzen: {0}" -f $dt.Rows.Count)
  } catch { Log ("  (pomijam szczegoly zdarzen: " + $_.Exception.Message + ")") }
  $list = New-Object System.Collections.ArrayList
  foreach ($r in $t.Rows) {
    $k = '{0}|{1}|{2}' -f $r.CowId, ([datetime]$r.Date).ToString('yyyyMMddHHmmss', $inv), $r.EventType
    $x = $det[$k]
    $res = $null; $n = $null; $sx = $null; $bull = $null
    if ($x) { $res = I $x.Result; $n = I $x.CalfsCount; $sx = I $x.Sex; $bull = S $x.BullName; if ($bull -eq '---') { $bull = $null } }
    [void]$list.Add((M @{
      i = I $r.Id; c = I $r.CowId; t = I $r.EventType
      d = ([datetime]$r.Date).ToString('yyyy-MM-dd HH:mm', $inv)
      r = $res; n = $n; s = $sx; b = $bull
    }))
  }
  return ,$list
}

function Get-Days([string]$from, $herd) {
  $dmap = @{}
  function Slot($d, $cow) {
    if (-not $dmap.ContainsKey($d)) { $dmap[$d] = @{} }
    if (-not $dmap[$d].ContainsKey($cow)) { $dmap[$d][$cow] = @{} }
    return $dmap[$d][$cow]
  }

  # mapa: numer techniczny (DbId) -> numer krowy w Infodexie (Id)
  $dbmap = @{}
  foreach ($k in $herd.cows.Keys)    { $v = $herd.cows[$k].dbid;    if ($null -ne $v) { $dbmap[[string]$v] = $k } }
  foreach ($k in $herd.heifers.Keys) { $v = $herd.heifers[$k].dbid; if ($null -ne $v) { $dbmap[[string]$v] = $k } }

  # mleko, pasza ze stacji, dzien laktacji (bez zlaczen - proste odczyty)
  $t = Q "SELECT CONVERT(char(10), Day, 23) AS d, CowId, MilkSum, Milk1, Milk2, YieldSum, LactationDay FROM ReportsLong WHERE Day >= '$from'"
  foreach ($r in $t.Rows) {
    $x = Slot $r.d ([string]$r.CowId)
    $m = M @{ m = R1 $r.MilkSum; m1 = R1 $r.Milk1; m2 = R1 $r.Milk2; f = I $r.YieldSum; dim = I $r.LactationDay }
    foreach ($k in $m.Keys) { $x[$k] = $m[$k] }
  }
  Log ("  mleko OK ({0} wierszy)" -f $t.Rows.Count)

  $t = Q "SELECT CONVERT(char(10), Day, 23) AS d, CowId, CowGroup FROM ReportsShort WHERE Day >= '$from'"
  foreach ($r in $t.Rows) {
    $g = I $r.CowGroup
    if ($null -ne $g) { $x = Slot $r.d ([string]$r.CowId); $x['g'] = $g }
  }
  Log ("  grupy OK ({0} wierszy)" -f $t.Rows.Count)

  # lezenie / przezuwanie / jedzenie (obroze)
  $t = Q @"
SELECT CONVERT(char(10), h.Date, 23) AS d, h.CowDbId AS dbid,
  $(Sum12 'RestTime') AS lie, $(Cnt12 'RestTime') AS nlie,
  $(Sum12 'RumTime')  AS rum, $(Cnt12 'RumTime')  AS nrum,
  $(Sum12 'EatTime')  AS eat
FROM HeatFeedData h
WHERE h.Date >= '$from'
"@
  $miss = 0
  foreach ($r in $t.Rows) {
    $cow = $dbmap[[string]$r.dbid]
    if (-not $cow) { $miss++; continue }
    $x = Slot $r.d ([string]$cow)
    $m = M @{ lie = I $r.lie; nl = I $r.nlie; rum = I $r.rum; nr = I $r.nrum; eat = I $r.eat }
    foreach ($k in $m.Keys) { $x[$k] = $m[$k] }
  }
  Log ("  obroze OK ({0} wierszy, nieprzypisane: {1})" -f $t.Rows.Count, $miss)

  # kroki (aktywnosc) - suma na dobe
  $t = Q @"
SELECT CONVERT(char(10), Date, 23) AS d, CowDbid AS dbid, SUM(Steps) AS st, COUNT(Steps) AS ns
FROM ActivitySteps
WHERE Date >= '$from' AND Steps IS NOT NULL
GROUP BY CONVERT(char(10), Date, 23), CowDbid
"@
  $miss = 0
  foreach ($r in $t.Rows) {
    $cow = $dbmap[[string]$r.dbid]
    if (-not $cow) { $miss++; continue }
    $x = Slot $r.d ([string]$cow)
    $m = M @{ st = I $r.st; ns = I $r.ns }
    foreach ($k in $m.Keys) { $x[$k] = $m[$k] }
  }
  Log ("  kroki OK ({0} wierszy, nieprzypisane: {1})" -f $t.Rows.Count, $miss)

  # kroki co 2 godziny z ostatnich 10 dni (wykrywanie rui w ciagu dnia): sa = 12 wartosci, 00:00 ... 22:00
  $from10 = (Get-Date).AddDays(-10).ToString('yyyy-MM-dd', $inv)
  if ($from10 -lt $from) { $from10 = $from }
  $t = Q @"
SELECT CONVERT(char(10), Date, 23) AS d, DATEPART(hour, Date) AS h, CowDbid AS dbid, Steps AS st
FROM ActivitySteps
WHERE Date >= '$from10' AND Steps IS NOT NULL
"@
  foreach ($r in $t.Rows) {
    $cow = $dbmap[[string]$r.dbid]
    if (-not $cow) { continue }
    $x = Slot $r.d ([string]$cow)
    if (-not $x.ContainsKey('sa')) { $x['sa'] = New-Object object[] 12 }
    $i = [int][math]::Floor([int]$r.h / 2)
    if ($i -ge 0 -and $i -lt 12) { $x['sa'][$i] = I $r.st }
  }
  Log ("  kroki co 2 h OK ({0} wierszy)" -f $t.Rows.Count)
  return $dmap
}


# ---------------- plan dawek ze stacji (male tabele, wysylane w calosci) ------------
function TableCsv([string]$name, [int]$max = 30000) {
  $t = Q "SELECT TOP $max * FROM [$name]"
  $cols = @($t.Columns | ForEach-Object { $_.ColumnName })
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append(($cols -join ','))
  foreach ($r in $t.Rows) {
    [void]$sb.Append("`n")
    $vals = foreach ($c in $cols) {
      $v = $r[$c]
      if ($null -eq $v -or $v -is [DBNull]) { '' }
      elseif ($v -is [bool]) { if ($v) { '1' } else { '0' } }
      elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm', $inv) }
      elseif ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { ([double]$v).ToString('R', $inv) }
      else { ([string]$v) -replace '[,\r\n]', ' ' }
    }
    [void]$sb.Append(($vals -join ','))
  }
  return @{ csv = $sb.ToString(); n = $t.Rows.Count }
}
function Get-Feed {
  $out = @{}
  foreach ($nm in 'FeedingNew','FeedingDayPoints','FeedingInstructions','FeedingPatterns','FeedingMinDoses','FeedingDays','FeedingDoses') {
    try { $x = TableCsv $nm; $out[$nm] = $x.csv; Log ("  {0}: {1} wierszy" -f $nm, $x.n) }
    catch { Log ("  (pomijam {0}: {1})" -f $nm, $_.Exception.Message) }
  }
  $total = 0; foreach ($k in @($out.Keys)) { $total += $out[$k].Length }
  foreach ($k in 'FeedingDoses','FeedingDays','FeedingMinDoses','FeedingPatterns') {
    if ($total -gt 900000 -and $out.ContainsKey($k)) { $total -= $out[$k].Length; $out.Remove($k); Log "  (pomijam $k - za duzo danych)" }
  }
  # stacje (g na obrot silnika), kalibracje, dostawy paszy
  $cnt = @{}
  try { $x = TableCsv 'FeedingStations' 20; $out['FeedingStations'] = $x.csv } catch { Log ("  (pomijam FeedingStations: {0})" -f $_.Exception.Message) }
  foreach ($p in @(@('CalibrationHistory','Date'), @('SiloHistory','Date'))) {
    try {
      $t = Q ("SELECT COUNT(*) AS n FROM [{0}]" -f $p[0]); $n = [int]$t.Rows[0].n
      $x = TableCsv2 ("SELECT TOP 20 * FROM [{0}] ORDER BY [{1}] DESC" -f $p[0], $p[1])
      $out[$p[0]] = $x.csv; $cnt[$p[0]] = $n
      Log ("  {0}: {1} wierszy" -f $p[0], $n)
    } catch { Log ("  (pomijam {0}: {1})" -f $p[0], $_.Exception.Message) }
  }
  # wybrane ustawienia programu Infodex
  $par = @{}
  try {
    $t = Q "SELECT Name, Val FROM Parameters WHERE Name LIKE 'Feeding[_]%' OR Name LIKE 'MilkTable[_]%' OR Name IN ('DryOffBeforeCalving','Colstrum','ColostrumDoNotMilk','MovingUneatenFeed','MovingUneatenFeedLimit','DoNotFeedDryOffs','DoNotFeedOnEmptySilo','MaxFeedDoseRise','MaxFeedDoseFall','FeedFallPercentageAlert','ForageLimitEnabled','ForageLimitSum','ShowNotEatingCowsAlarms','AlertsCowsNotEatingToday','Alerts_CalibrationReminders','HeatPeriod','CalvingAfterInsemination','Heat_ActPeakToInseminationStartHrs','Heat_ActPeakToInseminationEndHrs','InfodexVersion','Milking_MilkingStart_1','Milking_MilkingStart_2','Milking_MilkingStart_3')"
    foreach ($r in $t.Rows) { $v = S $r.Val; if ($null -ne $v -and $v.Length -le 200) { $par[(S $r.Name)] = $v } }
    Log ("  ustawienia Infodexu: {0}" -f $par.Count)
  } catch { Log ("  (pomijam Parameters: {0})" -f $_.Exception.Message) }
  return @{ tables = $out; params = $par; counts = $cnt }
}
function TableCsv2([string]$sql) {
  $t = Q $sql
  $cols = @($t.Columns | ForEach-Object { $_.ColumnName })
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append(($cols -join ','))
  foreach ($r in $t.Rows) {
    [void]$sb.Append("`n")
    $vals = foreach ($c in $cols) {
      $v = $r[$c]
      if ($null -eq $v -or $v -is [DBNull]) { '' }
      elseif ($v -is [bool]) { if ($v) { '1' } else { '0' } }
      elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm', $inv) }
      elseif ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { ([double]$v).ToString('R', $inv) }
      else { ([string]$v) -replace '[,\r\n]', ' ' }
    }
    [void]$sb.Append(($vals -join ','))
  }
  return @{ csv = $sb.ToString(); n = $t.Rows.Count }
}

# ---------------- internet i harmonogram -------------------------------
function Test-Net {
  try { Invoke-WebRequest -UseBasicParsing -Uri 'https://firestore.googleapis.com/' -TimeoutSec 20 | Out-Null; return $true }
  catch { if ($_.Exception.Response) { return $true }; Log ('  ' + $_.Exception.Message); return $false }
}
function Install-Task {
  $ps1 = Join-Path $here 'gr_formela_sync.ps1'
  $vbs = Join-Path $here 'run_hidden.vbs'
  $q = [char]34
  $line = 'CreateObject(' + $q + 'WScript.Shell' + $q + ').Run ' + $q + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' + $q + $q + $ps1 + $q + $q + $q + ', 0, False'
  [IO.File]::WriteAllText($vbs, $line, [Text.Encoding]::Default)
  $ok = $false
  try {
    $a = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ($q + $vbs + $q)
    $t = @((New-ScheduledTaskTrigger -Daily -At '06:00'), (New-ScheduledTaskTrigger -Daily -At '17:00'))
    $st = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName 'GR Formela sync' -Action $a -Trigger $t -Settings $st -Description 'GR Formela: odczyt Infodexu i wysylka do aplikacji (06:00 i 17:00)' -Force | Out-Null
    try { & schtasks.exe /Delete /F /TN 'GR Formela sync 17' 2>$null | Out-Null } catch {}
    $ok = $true
    Log 'Harmonogram: codziennie 06:00 i 17:00 (gdy komputer byl wtedy wylaczony - uruchomi sie po wlaczeniu).'
  } catch { Log ('  (Register-ScheduledTask: ' + $_.Exception.Message + ' - probuje schtasks)') }
  if (-not $ok) {
    try {
      & schtasks.exe /Create /F /SC DAILY /ST 06:00 /TN 'GR Formela sync' /TR ('wscript.exe ' + $q + $vbs + $q) | Out-Null
      $e1 = $LASTEXITCODE
      & schtasks.exe /Create /F /SC DAILY /ST 17:00 /TN 'GR Formela sync 17' /TR ('wscript.exe ' + $q + $vbs + $q) | Out-Null
      if ($e1 -eq 0 -and $LASTEXITCODE -eq 0) { $ok = $true; Log 'Harmonogram (schtasks): codziennie 06:00 i 17:00.' }
    } catch { Log ('  (schtasks: ' + $_.Exception.Message + ')') }
  }
  return $ok
}

# ---------------- wlasny zapis JSON (szybki, bez ograniczen ConvertTo-Json) ------
function JStr([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    $c = [int]$ch
    if     ($ch -eq '"')  { [void]$sb.Append('\"') }
    elseif ($ch -eq '\')  { [void]$sb.Append('\\') }
    elseif ($c -lt 32)    { [void]$sb.AppendFormat('\u{0:x4}', $c) }
    else                  { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
# --- dziennik zmian stada: numer/kolczyk/responder (hodowcy nie prowadza "Ubylych" - numer i responder przechodza na nowa krowe)
function Update-HerdLog($herd) {
  $snapF = Join-Path $here 'gr_formela_herd.json'
  $logF  = Join-Path $here 'gr_formela_herdlog.json'
  $baseF = Join-Path $here 'gr_formela_herd_base.json'
  $today = (Get-Date).ToString('yyyy-MM-dd', $inv)
  $cur = @{}
  foreach ($k in $herd.cows.Keys) { $c = $herd.cows[$k]; $cur[[string]$k] = @{ ear = [string]$c.ear; rfid = [string]$c.rfid; dbid = [string]$c.dbid } }
  $prev = $null; $d0 = $null
  $src = $null; if (Test-Path $snapF) { $src = $snapF } elseif (Test-Path $baseF) { $src = $baseF }
  if ($src) {
    try {
      $j = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json
      $d0 = [string]$j.d; $prev = @{}
      foreach ($p in $j.cows.PSObject.Properties) { $prev[$p.Name] = @{ ear = [string]$p.Value.ear; rfid = [string]$p.Value.rfid; dbid = [string]$p.Value.dbid } }
    } catch { Log ("  (nie odczytano poprzedniego stanu stada: {0})" -f $_.Exception.Message); $prev = $null }
  }
  $hl = New-Object System.Collections.ArrayList
  if (Test-Path $logF) {
    try { $lj = Get-Content $logF -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($x in @($lj)) { $h = @{}; foreach ($p in $x.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }; [void]$hl.Add($h) } } catch { }
  }
  $nNew = 0
  if ($prev) {
    $byEar = @{}; $byRfid = @{}
    foreach ($id in $prev.Keys) { $e = $prev[$id].ear; if ($e) { $byEar[$e] = $id }; $r = $prev[$id].rfid; if ($r) { $byRfid[$r] = $prev[$id].ear } }
    foreach ($id in $cur.Keys) {
      $c = $cur[$id]; $p = $prev[$id]
      if ($p -and $p.ear -and $c.ear -and $p.ear -ne $c.ear) { [void]$hl.Add(@{ t = 'ear'; id = $id; old = $p.ear; new = $c.ear; d = $today; d0 = $d0 }); $nNew++ }
      if ($c.ear -and $byEar.ContainsKey($c.ear) -and $byEar[$c.ear] -ne $id) { [void]$hl.Add(@{ t = 'renum'; ear = $c.ear; from = $byEar[$c.ear]; to = $id; d = $today; d0 = $d0 }); $nNew++ }
      elseif (-not $p) { [void]$hl.Add(@{ t = 'new'; id = $id; ear = $c.ear; d = $today; d0 = $d0 }); $nNew++ }
      if ($c.rfid -and $c.ear -and $byRfid.ContainsKey($c.rfid) -and $byRfid[$c.rfid] -and $byRfid[$c.rfid] -ne $c.ear) { [void]$hl.Add(@{ t = 'rfid'; rfid = $c.rfid; from = $byRfid[$c.rfid]; to = $c.ear; d = $today; d0 = $d0 }); $nNew++ }
    }
    foreach ($id in $prev.Keys) { if (-not $cur.ContainsKey($id)) { [void]$hl.Add(@{ t = 'gone'; id = $id; ear = $prev[$id].ear; d = $today; d0 = $d0 }); $nNew++ } }
  }
  while ($hl.Count -gt 500) { $hl.RemoveAt(0) }
  Log ("  zmiany w stadzie Infodexu: {0} nowych (od {1})" -f $nNew, $(if ($d0) { $d0 } else { 'pierwszego uruchomienia' }))
  if (-not $DryRun) {
    $sb1 = New-Object System.Text.StringBuilder; WJ @{ d = $today; cows = $cur } $sb1
    [IO.File]::WriteAllText($snapF, $sb1.ToString(), (New-Object Text.UTF8Encoding $false))
    $sb2 = New-Object System.Text.StringBuilder; WJ @($hl) $sb2
    [IO.File]::WriteAllText($logF, $sb2.ToString(), (New-Object Text.UTF8Encoding $false))
  }
  return ,$hl
}
function WJ($v, [System.Text.StringBuilder]$sb) {
  if ($null -eq $v -or $v -is [DBNull]) { [void]$sb.Append('null'); return }
  if ($v -is [bool])     { [void]$sb.Append($(if ($v) { 'true' } else { 'false' })); return }
  if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { [void]$sb.Append(([double]$v).ToString('R', $inv)); return }
  if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) { [void]$sb.Append([string]$v); return }
  if ($v -is [string])   { [void]$sb.Append((JStr $v)); return }
  if ($v -is [System.Collections.IDictionary]) {
    [void]$sb.Append('{'); $first = $true
    foreach ($k in $v.Keys) {
      if (-not $first) { [void]$sb.Append(',') }; $first = $false
      [void]$sb.Append((JStr ([string]$k))); [void]$sb.Append(':'); WJ $v[$k] $sb
    }
    [void]$sb.Append('}'); return
  }
  if ($v -is [System.Collections.IEnumerable]) {
    [void]$sb.Append('['); $first = $true
    foreach ($x in $v) { if (-not $first) { [void]$sb.Append(',') }; $first = $false; WJ $x $sb }
    [void]$sb.Append(']'); return
  }
  [void]$sb.Append((JStr ([string]$v)))
}

# ---------------- przebieg ---------------------------------------------
if ($env:GRF_TEST) { return }
if ($InstallTask) {
  if (Install-Task) { exit 0 } else { Log 'BLAD: nie udalo sie ustawic harmonogramu.'; exit 3 }
}
if ($SetAccount) {
  if (-not (Test-Net)) { Log 'BRAK INTERNETU: nie moge sprawdzic konta.'; exit 2 }
  if (Set-Account) { exit 0 } else { exit 4 }
}
try {
  $daysGiven = $PSBoundParameters.ContainsKey('Days')
  $doFull = if ($Export) { [bool]$Full } else { $Full -or (-not $daysGiven -and -not (Test-Path $state)) }
  if (-not $Export -and -not $DryRun) {
    Log 'Sprawdzam internet...'
    if (-not (Test-Net)) {
      Log 'BRAK INTERNETU: komputer nie laczy sie z Firebase. Sprawdz siec albo uzyj EKSPORT_do_pliku.bat (pendrive).'
      exit 2
    }
    try { [void](Get-IdToken); Log 'Logowanie agenta OK.' }
    catch { Log ('BLAD: ' + $_.Exception.Message); exit 4 }
  }
  $from = if ($doFull) { $START } else { (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd', $inv) }
  Log "Start v$AGENT_VERSION  tryb=$(if($doFull){'PELNY'}else{'zwykly'})  od=$from  $(if($DryRun){'[DRYRUN]'})"

  Log 'Czytam stado...'
  $herd   = Get-Herd
  Log 'Czytam zdarzenia...'
  $events = Get-Events
  Log 'Czytam mleko, obroze i aktywnosc (to trwa najdluzej)...'
  $dmap   = Get-Days $from $herd
  Log 'Czytam plan dawek stacji paszowej...'
  $feed   = Get-Feed
  Log 'Sprawdzam zmiany numerow i kolczykow w stadzie...'
  $hlog   = Update-HerdLog $herd
  Log ("Odczyt OK: krowy={0} jalowki={1} zdarzenia={2} dni={3}" -f $herd.cows.Count, $herd.heifers.Count, $events.Count, $dmap.Count)


  if ($Export) {
    $nowE = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $inv)
    $dd = @{}
    foreach ($d in ($dmap.Keys | Sort-Object)) { $dd[$d] = @{ date = $d; c = $dmap[$d]; at = $nowE } }
    $first = (Q "SELECT CONVERT(char(10), MIN(Day), 23) AS d FROM ReportsLong").Rows[0].d
    $sorted = @($dmap.Keys | Sort-Object)
    $metaE = @{ at = $nowE; agent = $AGENT_VERSION; host = $env:COMPUTERNAME; mode = $(if($doFull){'full'}else{'inc'}); days = $sorted.Count }
    if (N $first) { $metaE.first = [string]$first }
    if ($sorted.Count) { $metaE.last = $sorted[-1] }
    $exp = [ordered]@{
      app = 'grformela-infodex'; ver = $AGENT_VERSION; exported = $nowE; meta = $metaE
      herd = @{ at = $nowE; cows = $herd.cows; heifers = $herd.heifers; groups = $herd.groups; heatKey = $herd.heatKey }
      events = @{ at = $nowE; list = $events }
      feed = @{ at = $nowE; tables = $feed.tables; params = $feed.params; counts = $feed.counts }
      herdlog = @{ at = $nowE; list = @($hlog) }
      days = $dd
    }
    $sbx = New-Object System.Text.StringBuilder 4000000
    WJ $exp $sbx
    if (-not $OutFile) { $OutFile = Join-Path ([Environment]::GetFolderPath('Desktop')) 'infodex_export.json' }
    [IO.File]::WriteAllText($OutFile, $sbx.ToString(), (New-Object Text.UTF8Encoding $false))
    $mb = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
    Log "ZAPISANO PLIK: $OutFile  ($mb MB, dni: $($sorted.Count)). KONIEC OK"
    exit 0
  }

  $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $inv)
  $docs = New-Object System.Collections.ArrayList
  foreach ($d in ($dmap.Keys | Sort-Object)) {
    [void]$docs.Add(@{ path = "farms/$FARM/ix_days/$d"; data = @{ date = $d; c = $dmap[$d]; at = $now } })
  }
  [void]$docs.Add(@{ path = "farms/$FARM/ix/herd";   data = @{ at = $now; cows = $herd.cows; heifers = $herd.heifers; groups = $herd.groups; heatKey = $herd.heatKey } })
  [void]$docs.Add(@{ path = "farms/$FARM/ix/events"; data = @{ at = $now; list = $events } })
  [void]$docs.Add(@{ path = "farms/$FARM/ix/herdlog"; data = @{ at = $now; list = @($hlog) } })
  [void]$docs.Add(@{ path = "farms/$FARM/ix/feed";   data = @{ at = $now; tables = $feed.tables; params = $feed.params; counts = $feed.counts } })

  $n = Commit $docs

  $allDays = @($dmap.Keys | Sort-Object)
  $meta = @{ at = $now; agent = $AGENT_VERSION; host = $env:COMPUTERNAME; mode = $(if($doFull){'full'}else{'inc'}); days = $allDays.Count }
  $first = (Q "SELECT CONVERT(char(10), MIN(Day), 23) AS d FROM ReportsLong").Rows[0].d
  if (N $first) { $meta.first = [string]$first }
  if ($allDays.Count) { $meta.last = $allDays[-1] }
  [void](Commit @(@{ path = "farms/$FARM/ix/meta"; data = $meta }))

  if (-not $DryRun) { Set-Content -Path $state -Value $now -Encoding UTF8 }
  Log "Wyslano dokumentow: $($n + 1). KONIEC OK"
  exit 0
} catch {
  Log ("BLAD: " + $_.Exception.Message)
  if ($_.Exception.Message -like 'KONTO:*') { exit 4 }
  exit 1
}
