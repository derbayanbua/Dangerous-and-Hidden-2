# B-035 Fensterbilder (Leuchtturmlicht NORMANDY). Vorbereitet, läuft im Fenster (nicht headless), beachtet die Test-Sperre.
# Aufruf: powershell -File tools\b035_fenster.ps1   → test_output\b035\leuchtturm_*.png
$proj = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\test_lock.ps1"
$slots = Get-TestSlots -Proj $proj -Name "b035_fenster" -Count 1
try {
  Invoke-GodotSuite -Proj $proj -GodotArgs "-- --mission=no1_leuchtturm --autoplay=shots_b035" -Log "$proj\test_output\shots_b035.log" -TimeoutSec 900 -Slots $slots | Out-Null
} finally { Release-TestSlots -Slots $slots -Name "b035_fenster" }
Get-ChildItem "$proj\test_output\b035" -ErrorAction SilentlyContinue | Select-Object Name, Length
