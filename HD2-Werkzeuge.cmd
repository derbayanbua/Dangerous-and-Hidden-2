@echo off
rem Dangerous and Hidden 2 - Werkzeuge: Spieldaten aus der eigenen HD2-Installation exportieren,
rem Filme konvertieren, Texturen hochskalieren. Einfach doppelklicken.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\user\hd2_menu.ps1" %*
if errorlevel 1 pause
