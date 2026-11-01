# Rauchtest aller Original-Missionsteile: Level/Akteure/Skripte/Ziele + Liste nicht umgesetzter Skriptbefehle.
# Aufruf: powershell -File tools\smoke_orig.ps1 [-Ids a4_eisberg,af1_spaghetti_airport] [-TimeoutSec 900]
# B-025: Test-Sperre (tools\test_lock.ps1, ein Slot je Mission), Zeitlimit je Mission (nur eigener Prozessbaum wird beendet),
# bestanden nur mit Exit 0 und ERGEBNIS-Zeile ohne Fehlschläge.
param([string[]]$Ids = @(), [int]$TimeoutSec = 900)
$proj = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\test_lock.ps1"
Set-Location $proj
New-Item -ItemType Directory -Force "$proj\test_output" | Out-Null
$Ids = @($Ids | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File übergibt "a,b" als einen String
if ($Ids.Count -eq 0) {
  $Ids = @("a1_blizzard", "a2_erkundung", "a3_rendezvous", "a4_eisberg", "af1_spaghetti_airport", "af2_flugschau", "af3_gaeste", "af4_karawane", "af5_whiskey_bar",
    "af6_raubvoegel", "nw1_dampfleitung", "bu1_ameisenhuegel", "bu2_bergkoenig", "al1_waldgeister", "al2_makler",
    "no1_leuchtturm", "no2_schwerttaenzer", "cz1_eintrittsgeld", "cz2_maulwurf", "cz3_geschaeft", "cz4_volksfest",
    "cz5_trink_aus", "cz6_abrechnung", "training")
}
$rows = @()
Remove-Item "$proj\test_output\ls_silent.txt" -ErrorAction SilentlyContinue   # B-028: Bericht stummer Befehle neu
foreach ($id in $Ids) {
  $log = "$proj\test_output\smoke_$id.log"
  $slots = Get-TestSlots -Proj $proj -Name "smoke_orig" -Count 1
  try { $r = Invoke-GodotSuite -Proj $proj -GodotArgs "--headless -- --mission=$id --autoplay=test_orig_part" -Log $log -TimeoutSec $TimeoutSec -Slots $slots }
  finally { Release-TestSlots -Slots $slots -Name "smoke_orig" }
  $res = Read-SuiteResult -Log $log -Code $r.code -TimedOut $r.timeout
  $lines = @(Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue)
  $fails = ($lines | Where-Object { $_ -match '^FAIL|SCRIPT ERROR' } | Select-Object -First 4) -join " | "
  $unimpl = ($lines | Where-Object { $_ -match '^UNIMPL' } | Select-Object -Last 1)
  "{0,-24} Exit {1,-3} {2,5}s {3}  {4}" -f $id, $r.code, $r.seconds, $res.summary, $fails
  if (-not $res.ok) { "    -> FEHLER: $($res.reason)" }
  if ($unimpl) { "    $unimpl" }
  $stumm = ($lines | Where-Object { $_ -match '^STUMM' } | Select-Object -Last 1)
  if ($stumm) { "    $stumm" }
  $rows += [pscustomobject]@{ Mission = $id; Ergebnis = $(if ($res.ok) { "OK" } else { "FEHLER ($($res.reason))" });
    Dauer = "{0}:{1:00}" -f [int][math]::Floor($r.seconds / 60), ($r.seconds % 60); Fehler = $res.fails }
}
""
$rows | Format-Table -AutoSize | Out-String -Width 200
$failed = @($rows | Where-Object { $_.Ergebnis -ne "OK" }).Count
if ($failed -gt 0) { "FEHLGESCHLAGEN: $failed von $($rows.Count) Mission(en)"; exit 1 } else { "ALLE $($rows.Count) MISSIONEN BESTANDEN"; exit 0 }
