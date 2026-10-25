# B-020 Fensterlauf (NICHT headless; vorbereitet, in der Sitzung nicht ausgefuehrt):
# Kontrollbilder Hund/Wachen ARCTIC1 -> test_output\b020_*.png
# Aufruf: powershell -File tools\b020_fenster.ps1
$proj = Split-Path $PSScriptRoot -Parent
& powershell -File "$proj\tools\run_locked.ps1" -Name b020_fenster -TimeoutSec 1200 -Log "$proj\test_output\b020_fenster.log" `
  -GodotArgs "-- --mission=a1_blizzard --autoplay=shots_a1_ai"
