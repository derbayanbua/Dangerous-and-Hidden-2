# B-017 Kontrollbilder (Fensterlaeufe, nacheinander; Test-Sperre beachten). Ergebnis: test_output\b017_*.png
$proj = Split-Path $PSScriptRoot -Parent
foreach ($m in @("af1_spaghetti_airport", "no2_schwerttaenzer", "a1_blizzard")) {
  & "$proj\tools\godot.cmd" --resolution 1280x720 -- "--mission=$m" --autoplay=shots_b017
}
