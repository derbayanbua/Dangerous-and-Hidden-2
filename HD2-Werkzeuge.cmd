@echo off
rem Dangerous and Hidden 2 - Werkzeuge / Tools: Spieldaten aus der eigenen HD2-Installation exportieren,
rem Filme konvertieren, Texturen hochskalieren. Einfach doppelklicken. / Export game data from your own
rem HD2 installation, convert movies, upscale textures. Just double-click. Optional: -Sprache de|en
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\user\hd2_menu.ps1" %*
if errorlevel 1 (
  echo.
  echo Fehler - siehe Meldungen oben. / Error - see messages above.
  pause
)
