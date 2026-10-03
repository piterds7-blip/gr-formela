/* =====================================================================
   INFODEX – diagnostyka bazy (TYLKO ODCZYT – nic nie zmienia w bazie)
   Jak użyć:
   1. SSMS -> połącz z .\SQLPOLANES -> wybierz bazę infodexDb
   2. Plik -> Otwórz -> ten plik (albo wklej całość do "Nowe zapytanie")
   3. F5 (Wykonaj)
   4. Na dole pojawi się kilka tabel wyników (1..9).
      Dla każdej: klik prawym w wyniki -> "Zapisz wyniki jako..." -> CSV
      i nazwij plik numerem, np. 1_liczby.csv, 2_eventtype.csv ...
      (albo zrób zrzuty ekranu, jeśli tak szybciej)
   ===================================================================== */

USE infodexDb;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- nie blokuje pracy Infodexa

/* 1. Co jest wypełnione: liczba wierszy i zakres dat */
SELECT 'Cows' AS tabela, COUNT(*) AS wiersze, NULL AS od, NULL AS do_ FROM Cows
UNION ALL SELECT 'Heifers', COUNT(*), NULL, NULL FROM Heifers
UNION ALL SELECT 'MilkingHistory (doje)', COUNT(*), CAST(MIN(Time) AS date), CAST(MAX(Time) AS date) FROM MilkingHistory
UNION ALL SELECT 'ReportsShort (dzienne)', COUNT(*), MIN(Day), MAX(Day) FROM ReportsShort
UNION ALL SELECT 'ReportsLong (dzienne)', COUNT(*), MIN(Day), MAX(Day) FROM ReportsLong
UNION ALL SELECT 'Lactation', COUNT(*), MIN(Date), MAX(Date) FROM Lactation
UNION ALL SELECT 'Events (zdarzenia)', COUNT(*), CAST(MIN(Date) AS date), CAST(MAX(Date) AS date) FROM Events
UNION ALL SELECT 'FeedingHistory (stacje)', COUNT(*), CAST(MIN(Time) AS date), CAST(MAX(Time) AS date) FROM FeedingHistory
UNION ALL SELECT 'WeightingHistory (waga)', COUNT(*), CAST(MIN(Date) AS date), CAST(MAX(Date) AS date) FROM WeightingHistory
UNION ALL SELECT 'Measurements (pomiary)', COUNT(*), MIN(Date), MAX(Date) FROM Measurements
UNION ALL SELECT 'Measurements z tluszczem>0', COUNT(*), MIN(Date), MAX(Date) FROM Measurements WHERE Fat > 0
UNION ALL SELECT 'HeatFeedData (przezuwanie)', COUNT(*), MIN(Date), MAX(Date) FROM HeatFeedData
UNION ALL SELECT 'ActivitySteps (aktywnosc)', COUNT(*), CAST(MIN(Date) AS date), CAST(MAX(Date) AS date) FROM ActivitySteps
UNION ALL SELECT 'SiloHistory (silosy)', COUNT(*), CAST(MIN(Date) AS date), CAST(MAX(Date) AS date) FROM SiloHistory
UNION ALL SELECT 'CurrentAlerts', COUNT(*), MIN(Date), MAX(Date) FROM CurrentAlerts;

/* 2. Słownik typów zdarzeń (wycielenie, inseminacja, test ciążowy ...) */
SELECT * FROM EventType ORDER BY Id;

/* 3. Grupy w Infodexie */
SELECT g.*, (SELECT COUNT(*) FROM Cows c WHERE c.CowGroup = g.Id) AS krow_w_grupie
FROM CowGroups g ORDER BY g.Id;

/* 4. Krowy – przykładowe 30 (numer, responder, kolczyk, grupa, cykl życia) */
SELECT TOP 30 c.Id, c.Name, c.Tag, c.PassportNumber, c.CowGroup, c.LifeCycle,
       c.BirthDate, c.FeedingType, c.ParlourFeedingType, c.PedometerTag,
       l.CycleState, l.CalvingCount, l.InsemCount, l.LactationDay
FROM Cows c LEFT JOIN LifeCycles l ON l.CowId = c.Id
ORDER BY c.Id;

/* 5. Rozkład wartości kodów cyklu życia (do rozszyfrowania) */
SELECT 'Cows.LifeCycle' AS pole, LifeCycle AS wartosc, COUNT(*) AS ile FROM Cows GROUP BY LifeCycle
UNION ALL
SELECT 'LifeCycles.CycleState', CycleState, COUNT(*) FROM LifeCycles GROUP BY CycleState
ORDER BY pole, wartosc;

/* 6. Zdarzenia z ostatnich 120 dni z nazwą typu */
SELECT TOP 200 e.Id, e.CowId, e.Date, e.EventType, t.EventName, e.Comment, e.EventFlag
FROM Events e LEFT JOIN EventType t ON t.Id = e.EventType
WHERE e.Date >= DATEADD(day, -120, GETDATE())
ORDER BY e.Date DESC;

/* 7. Dzienne podsumowania – ostatnie 7 dni (mleko, pasza, dzień laktacji) */
SELECT TOP 300 * FROM ReportsShort
WHERE Day >= DATEADD(day, -7, CAST(GETDATE() AS date))
ORDER BY Day DESC, CowId;

/* 8. Pojedyncze doje – ostatnie 2 dni (czy hala zapisuje litry per krowa) */
SELECT TOP 300 CowId, Time, MilkYeld, MilkingLength, MilkingIndex, StandNumber
FROM MilkingHistory
WHERE Time >= DATEADD(day, -2, GETDATE())
ORDER BY Time DESC;

/* 9. Ustawienia programu (kalendarz, powiadomienia, czasy dojów) */
SELECT * FROM Parameters ORDER BY Name;
