@echo off
chcp 65001 >nul
title GR Formela - zapis do pliku (awaryjnie, bez internetu)
echo.
echo  GR FORMELA - AWARYJNIE: zapis danych z Infodexu do pliku
echo  Uzyj tylko, gdy nie ma internetu. Agent TYLKO CZYTA baze Infodexu.
echo  Cala historia - moze potrwac 2-4 minuty. Nie zamykaj okna.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gr_formela_sync.ps1" -Export -Full
if errorlevel 1 goto blad
echo.
echo  ==========================================================
echo   GOTOWE. Plik  infodex_export.json  jest na PULPICIE.
echo   Skopiuj go na pendrive i wczytaj w aplikacji:
echo   Ustawienia - Dane z Infodexu - Wczytaj plik z Infodexu
echo  ==========================================================
echo.
pause
exit /b 0
:blad
echo.
echo  BLAD - zrob zdjecie tego okna i wyslij.
pause
exit /b 1
