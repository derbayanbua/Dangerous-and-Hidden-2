# B-044: Stillstandsmessung über mehrere Originalmissionen (je Mission ein Godot-Lauf unter der Test-Sperre).
# Aufruf: powershell -File tools\b044_measure.ps1 -Tag vorher [-Ids a1_blizzard,af1_spaghetti_airport,...]
# Ergebnis: test_output\b044_<id>_<tag>.txt je Mission + test_output\b044_summe_<tag>.txt (Zeilen B044_SUMME).
param([string]$Tag = "messung", [string[]]$Ids = @(), [string]$Extra = "")
$proj = Split-Path $PSScriptRoot -Parent
$Ids = @($Ids | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Ids.Count -eq 0) {
  $Ids = @("a1_blizzard", "af1_spaghetti_airport", "bu1_ameisenhuegel", "no1_leuchtturm", "cz1_eintrittsgeld", "al1_waldgeister")
}
$sum = @()
foreach ($id in $Ids) {
  $log = "$proj\test_output\b044_${id}_$Tag.log"
  & powershell -NoProfile -File "$proj\tools\run_locked.ps1" -Name "b044" -Log $log -TimeoutSec 1500 `
    -GodotArgs "--headless -- --mission=$id --autoplay=probe_b044_stuck --tag=$Tag --test_timeout=1400 $Extra" | Out-Null
  $line = Select-String -Path $log -Pattern "^B044_SUMME" -ErrorAction SilentlyContinue | Select-Object -Last 1
  $sum += if ($line) { "$id`t$($line.Line)" } else { "$id`tKEIN ERGEBNIS" }
}
$sum | Out-File -Encoding utf8 "$proj\test_output\b044_summe_$Tag.txt"
$sum
