@echo off
chcp 65001 >nul
title GR Formela - konto agenta
echo.
echo  GR FORMELA - konto agenta (logowanie do bazy)
echo  Wpisz haslo agenta z aplikacji (zakladka Dostep - Komputer w oborze).
echo  Haslo zapisze sie zaszyfrowane - odczyta je tylko ten uzytkownik Windows.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gr_formela_sync.ps1" -SetAccount
if errorlevel 4 goto zle
if errorlevel 2 goto brak_netu
if errorlevel 1 goto zle
echo.
echo  ==========================================================
echo   GOTOWE. Konto agenta dziala. Mozesz zamknac to okno.
echo  ==========================================================
echo.
pause
exit /b 0
:zle
echo.
echo  NIE UDALO SIE: zle haslo albo agent zablokowany w zakladce Dostep.
echo  Sprawdz haslo i uruchom USTAW_KONTO.bat jeszcze raz.
pause
exit /b 1
:brak_netu
echo.
echo  BRAK INTERNETU - nie moge sprawdzic konta. Sprawdz siec.
pause
exit /b 1
