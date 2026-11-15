@echo off
chcp 65001 >nul
title GR Formela - instalacja agenta
set "DST=%USERPROFILE%\GRFormela"
echo.
echo  GR FORMELA - agent: Infodex -^> aplikacja (Firebase)
echo  Agent TYLKO CZYTA baze Infodexu, niczego w niej nie zmienia.
echo.
if not exist "%DST%" mkdir "%DST%"
copy /Y "%~dp0gr_formela_sync.ps1" "%DST%\gr_formela_sync.ps1" >nul
if errorlevel 1 goto blad_kopia
if exist "%USERPROFILE%\GRFormela\gr_formela_konto.xml" goto konto_ok
echo  [0/2] Konto agenta - wpisz haslo agenta z aplikacji (zakladka Dostep).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DST%\gr_formela_sync.ps1" -SetAccount
if errorlevel 4 goto brak_konta
if errorlevel 2 goto brak_netu
:konto_ok
echo.
echo  [1/2] Wysylam dane z Infodexu do aplikacji (za pierwszym razem cala historia).
echo        Moze potrwac kilka minut. Nie zamykaj okna...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DST%\gr_formela_sync.ps1"
if errorlevel 4 goto brak_konta
if errorlevel 2 goto brak_netu
if errorlevel 1 goto blad_sync
echo.
echo  [2/2] Ustawiam codzienne wysylanie o 06:00 i 17:00...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DST%\gr_formela_sync.ps1" -InstallTask
if errorlevel 1 goto blad_task
echo.
echo  ==========================================================
echo   GOTOWE. Dane sa juz w aplikacji.
echo   Od dzis agent wysyla dane sam, codziennie o 06:00 i 17:00.
echo   Jesli komputer bedzie wtedy wylaczony - wysle po wlaczeniu.
echo   Mozesz zamknac to okno.
echo  ==========================================================
echo.
pause
exit /b 0

:blad_kopia
echo  BLAD: nie udalo sie skopiowac pliku. Rozpakuj ZIP przed uruchomieniem.
pause
exit /b 1
:brak_konta
echo.
echo  BRAK KONTA AGENTA albo zle haslo - baza nie przyjela danych.
echo  Uruchom USTAW_KONTO.bat i wpisz haslo agenta z aplikacji
echo  (zakladka Dostep). Szczegoly w gr_formela_sync.log.
pause
exit /b 1
:brak_netu
echo.
echo  BRAK INTERNETU - komputer nie laczy sie z Firebase.
echo  Sprawdz siec. Awaryjnie: EKSPORT_do_pliku.bat i pendrive.
pause
exit /b 1
:blad_sync
echo.
echo  BLAD wysylania - zrob zdjecie tego okna i wyslij.
pause
exit /b 1
:blad_task
echo.
echo  Dane wyslane, ale NIE udalo sie ustawic codziennego uruchamiania.
echo  Zrob zdjecie tego okna i wyslij.
pause
exit /b 1
