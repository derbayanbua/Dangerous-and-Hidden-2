@echo off
rem Finaler Spieltest-Build zum Kopieren auf andere PCs (EXE + Originaldaten, LAN-faehig).
rem Optionen: -Zip (zusaetzlich ZIP), -Verify (Pruefung mit der fertigen EXE), -NoHD (ohne KI-Texturen), -Out <Ordner>
rem Beispiel: release.cmd -Verify -Zip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_release.ps1" %*
pause
