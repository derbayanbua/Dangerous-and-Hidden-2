# Rest 0.9.5 Fensterlauf (NICHT headless; vorbereitet, in der Sitzung nicht ausgefuehrt):
# 1) Ragdoll-Endlagen (gestraffte Gelenkgrenzen) -> test_output\ragdoll\*.png
# 2) ARCTIC1 Zaun: Benutzen-Taste + Truppmenue-Drahtschere + Lauf durch die Luecke (test_b017 arctic im Fenster, zum Ansehen)
# Aufruf: powershell -File tools\rest095_fenster.ps1 [-Only ragdoll|fence]
param([string]$Only = "")
$proj = Split-Path $PSScriptRoot -Parent
if ($Only -eq "" -or $Only -eq "ragdoll") {
  & powershell -File "$proj\tools\run_locked.ps1" -Name rest095_fenster -TimeoutSec 1200 -Log "$proj\test_output\rest095_ragdoll_fenster.log" `
    -GodotArgs "-- --mission=m01_funkfeuer --autoplay=shots_ragdoll"
}
if ($Only -eq "" -or $Only -eq "fence") {
  & powershell -File "$proj\tools\run_locked.ps1" -Name rest095_fenster -TimeoutSec 1200 -Log "$proj\test_output\rest095_fence_fenster.log" `
    -GodotArgs "-- --mission=a1_blizzard --autoplay=test_b017 --phase=arctic"
}
