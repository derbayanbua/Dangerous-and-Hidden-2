# Rauchtest aller Original-Missionsteile: Level/Akteure/Skripte/Ziele + Liste nicht umgesetzter Skriptbefehle.
# Aufruf: powershell -File tools\smoke_orig.ps1 [-Ids a4_eisberg,af1_spaghetti_airport]
param([string[]]$Ids = @())
$proj = Split-Path $PSScriptRoot -Parent
Set-Location $proj
if ($Ids.Count -eq 0) {
  $Ids = @("a1_blizzard", "a2_erkundung", "a3_rendezvous", "a4_eisberg", "af1_spaghetti_airport", "af2_flugschau", "af3_gaeste", "af4_karawane", "af5_whiskey_bar",
    "af6_raubvoegel", "nw1_dampfleitung", "bu1_ameisenhuegel", "bu2_bergkoenig", "al1_waldgeister", "al2_makler",
    "no1_leuchtturm", "no2_schwerttaenzer", "cz1_eintrittsgeld", "cz2_maulwurf", "cz3_geschaeft", "cz4_volksfest",
    "cz5_trink_aus", "cz6_abrechnung", "training")
}
$sum = @()
foreach ($id in $Ids) {
  $log = "$proj\test_output\smoke_$id.log"
  cmd /c "`"$proj\tools\godot.cmd`" --headless -- --mission=$id --autoplay=test_orig_part > `"$log`" 2>&1"
  $code = $LASTEXITCODE
  $res = (Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^ERGEBNIS' } | Select-Object -Last 1)
  $fails = (Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^FAIL|SCRIPT ERROR' } | Select-Object -First 4) -join " | "
  $unimpl = (Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^UNIMPL' } | Select-Object -Last 1)
  $line = "{0,-24} Exit {1,-3} {2}  {3}" -f $id, $code, $res, $fails
  $line
  if ($unimpl) { "    $unimpl" }
  $sum += $line
}
