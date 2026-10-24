# Erfüllbarkeit aller 24 Original-Kampagnenteile (tests/test_orig_complete.gd) – je Mission ein Godot-Lauf.
# Aufruf: powershell -File tools\run_completability.ps1 [-Only af1_spaghetti_airport,cz1_eintrittsgeld] [-Speed 2] [-TableOnly]
# Ergebnis: test_output\completability_<id>.log und Tabelle test_output\completability.txt (aus allen vorhandenen Logs)
# Beachtet die Test-Sperre test_output\.godot_lock (fremde Sperre < 20 min -> warten) und lässt zwischen zwei
# Missionen 20 s Zeit, damit andere Läufe die Sperre bekommen.
param([string[]]$Only = @(), [string]$Speed = "2", [int]$TimeoutSec = 1500, [string]$LockName = "completability",
  [switch]$TableOnly, [string]$Strategy = "kampf", [string]$Extra = "")
# -Strategy leise: Löser tötet erst in Runde 3 (Log completability_<id>_leise.log); die Tabelle nimmt je Mission
# das bessere Ergebnis beider Strategien.
$proj = Split-Path $PSScriptRoot -Parent
$out = "$proj\test_output"
New-Item -ItemType Directory -Force $out | Out-Null
$all = @("training", "a1_blizzard", "a2_erkundung", "a3_rendezvous", "a4_eisberg", "af1_spaghetti_airport", "af2_flugschau",
  "af3_gaeste", "af4_karawane", "af5_whiskey_bar", "af6_raubvoegel", "nw1_dampfleitung", "bu1_ameisenhuegel", "bu2_bergkoenig",
  "al1_waldgeister", "al2_makler", "no1_leuchtturm", "no2_schwerttaenzer", "cz1_eintrittsgeld", "cz2_maulwurf",
  "cz3_geschaeft", "cz4_volksfest", "cz5_trink_aus", "cz6_abrechnung")
$ids = if ($Only.Count -gt 0) { $Only } else { $all }
$lock = "$out\.godot_lock"
if (-not $TableOnly) {
  $first = $true
  foreach ($id in $ids) {
    if (-not $first) { Start-Sleep -Seconds 20 }
    $first = $false
    while ($true) {
      if (Test-Path $lock) {
        $age = ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes
        $who = (Get-Content $lock -ErrorAction SilentlyContinue) -join ""
        if ($age -lt 20 -and $who -ne $LockName) { Start-Sleep -Seconds 5; continue }
      }
      Set-Content -Path $lock -Value $LockName
      Start-Sleep -Milliseconds 300
      if (((Get-Content $lock -ErrorAction SilentlyContinue) -join "") -eq $LockName) { break }
    }
    $suffix = if ($Strategy -ne "kampf") { "_$Strategy" } else { "" }
    $log = "$out\completability_$id$suffix.log"
    # AFRICA6 ist ein Bordschützen-Einsatz mit eigener Flugmechanik: Erfüllbarkeit über test_af6
    $script = if ($id -eq "af6_raubvoegel") { "test_af6" } else { "test_orig_complete" }
    $args2 = "--headless -- --mission=$id --autoplay=$script --speed=$Speed --strategy=$Strategy $Extra"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$proj\tools\godot.cmd`" $args2 > `"$log`" 2>&1`"" -WorkingDirectory $proj -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { taskkill /PID $p.Id /T /F | Out-Null; "TIMEOUT" | Add-Content $log }
    if (((Get-Content $lock -ErrorAction SilentlyContinue) -join "") -eq $LockName) { Remove-Item $lock -Force }
    $l = Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^ERFUELLBAR\|' } | Select-Object -Last 1
    "{0,-24} {1}" -f $id, $l
  }
}
# Tabelle aus allen vorhandenen Logs
$rows = @()
foreach ($id in $all) {
  $log = "$out\completability_$id.log"
  if (-not (Test-Path $log)) { continue }
  $txt = Get-Content $log -Encoding UTF8
  $line = $txt | Where-Object { $_ -match '^ERFUELLBAR\|' } | Select-Object -Last 1
  $alt = "$out\completability_${id}_leise.log"
  if ((-not $line -or $line.Split("|")[3] -ne "1") -and (Test-Path $alt)) {
    $t2 = Get-Content $alt -Encoding UTF8
    $l2 = $t2 | Where-Object { $_ -match '^ERFUELLBAR\|' } | Select-Object -Last 1
    if ($l2 -and $l2.Split("|")[3] -eq "1") { $txt = $t2; $line = $l2 }
  }
  $errs = ($txt | Where-Object { $_ -match 'SCRIPT ERROR' } | Select-Object -Unique | Measure-Object).Count
  if ($id -eq "af6_raubvoegel") {
    $ok = ($txt | Where-Object { $_ -match '^ERGEBNIS' } | Select-Object -Last 1)
    $succ = if ($ok -match ' 0 fehlgeschlagen') { 1 } else { 0 }
    $line = "ERFUELLBAR|$id|AFRICA6|$succ|-|[]|test_af6: $ok||"
  }
  if (-not $line) { $line = "ERFUELLBAR|$id|?|0|?|?|kein Ergebnis (Absturz/Zeitlimit)||" }
  $f = $line.Split("|")
  $obj = ($txt | Where-Object { $_ -match '^\s+ZIEL ' }) -join "`n"
  $rows += [pscustomobject]@{ id = $f[1]; folder = $f[2]; success = $f[3]; req = $f[4]; unimpl = $f[5]; reason = $f[6]; notes = $f[7]; errors = $errs; objectives = $obj }
}
$md = @("| Mission | Ordner | Erfolg (Löser) | Pflichtziele erfüllt | Skriptfehler | Nicht umgesetzte Befehle | Ende / Hinweis |", "|---|---|---|---|---|---|---|")
foreach ($r in $rows) { $md += "| $($r.id) | $($r.folder) | $(if ($r.success -eq '1') { 'ja' } else { 'nein' }) | $($r.req) | $($r.errors) | $($r.unimpl) | $($r.reason) $($r.notes) |" }
$md += ""
foreach ($r in $rows) { $md += "### $($r.id)"; $md += $r.objectives }
$md | Set-Content -Path "$out\completability.txt" -Encoding UTF8
"Tabelle: $out\completability.txt"
