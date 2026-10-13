@echo off
rem Startet die installierte Godot-4.7.1-Konsole mit diesem Projekt.
rem Beispiele:
rem   tools\godot.cmd --headless --import            (Import/Parse-Check)
rem   tools\godot.cmd                                 (Spiel starten)
rem   tools\godot.cmd --editor                        (Editor)
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe"
if defined GODOT_BIN set "GODOT=%GODOT_BIN%"
"%GODOT%" --path "%~dp0.." %*
