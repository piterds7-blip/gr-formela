@echo off
chcp 65001 >nul
title GR Formela - wysylka calej historii z Infodexu
echo.
echo  GR FORMELA - wysylka CALEJ historii z Infodexu do aplikacji
echo  Agent TYLKO CZYTA baze Infodexu, niczego w niej nie zmienia.
echo  Moze potrwac kilka minut. Nie zamykaj okna.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gr_formela_sync.ps1" -Full
if errorlevel 4 goto brak_konta
if errorlevel 2 goto brak_netu
if errorlevel 1 goto blad
echo.
echo  ==========================================================
echo   GOTOWE. Dane sa w aplikacji - otworz ja na laptopie
echo   albo telefonie (moze byc potrzebne odswiezenie strony).
echo  ==========================================================
echo.
pause
exit /b 0
:brak_konta
echo.
echo  BRAK KONTA AGENTA albo zle haslo - baza nie przyjela danych.
echo  Uruchom USTAW_KONTO.bat i wpisz e-mail oraz haslo konta agenta
echo  (zalozone przez wlasciciela w Firebase). Szczegoly w gr_formela_sync.log.
pause
exit /b 1
:brak_netu
echo.
echo  BRAK INTERNETU - komputer nie laczy sie z Firebase.
echo  Awaryjnie uzyj EKSPORT_do_pliku.bat (plik na pendrive).
pause
exit /b 1
:blad
echo.
echo  BLAD - zrob zdjecie tego okna i wyslij.
pause
exit /b 1
