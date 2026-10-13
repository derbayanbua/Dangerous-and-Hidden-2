# Spieltest-Build: Windows-Export + lokaler Original-Cache (mit KI-HD-Texturen) daneben.
# Aufruf: powershell -File tools\build_playtest.ps1
# Ergebnis: build\playtest\DangerousHidden2.exe + build\playtest\orig_cache\ (NUR lokal verwenden:
# enthält aus der eigenen HD2-Installation erzeugte, urheberrechtlich geschützte Daten – nicht weitergeben,
# nicht committen; build/ ist per .gitignore ausgeschlossen).
$ErrorActionPreference = "Continue"
$proj = Split-Path $PSScriptRoot -Parent
$out = "$proj\build\playtest"
New-Item -ItemType Directory -Force $out | Out-Null
Set-Location $proj

cmd /c "`"$proj\tools\godot.cmd`" --headless --import > `"$proj\test_output\import.log`" 2>&1"
cmd /c "`"$proj\tools\godot.cmd`" --headless --export-release `"Windows Desktop`" `"$out\DangerousHidden2.exe`" > `"$proj\test_output\export.log`" 2>&1"
if (-not (Test-Path "$out\DangerousHidden2.exe")) { throw "Export fehlgeschlagen (test_output\export.log)" }

# Cache kopieren; *_hd/*_4k-Ordner nicht doppelt, stattdessen beste Fassung an die Originalstelle
$src = "$proj\orig_cache"
$dst = "$out\orig_cache"
robocopy $src $dst /MIR /XD textures_hd textures_4k textures_sd backgrounds_hd backgrounds_4k /NFL /NDL /NJH /NJS /NP | Out-Null
$pairs = @(
  @("textures", "textures"),
  @("ui\menu\textures", "ui\menu\textures"),
  @("ui\menu\backgrounds", "ui\menu\backgrounds"),
  @("ui\hud\textures", "ui\hud\textures")
)
$n = 0
foreach ($p in $pairs) {
  foreach ($suffix in @("_hd", "_4k")) {     # 4K überschreibt HD, falls vorhanden
    $hd = "$src\$($p[0])$suffix"
    if (Test-Path $hd) {
      Get-ChildItem $hd -Filter *.png | ForEach-Object {
        Copy-Item $_.FullName "$dst\$($p[1])\$($_.Name)" -Force
        $n++
      }
    }
  }
}
"HD-Texturen übernommen: $n"

@"
DANGEROUS HIDDEN 2 – Spieltest-Build (Original-Mission 1: Arctic 1A/1B/1C)

Start: DangerousHidden2.exe (Vollbild in Desktop-Auflösung; Optionen -> Einstellungen -> Grafik)
Menü: EINZELSPIELER-SPIEL -> KAMPAGNE -> Arctic 1A -> START -> Einsatz beginnen

Steuerung (Standard, im Spiel unter Einstellungen -> Steuerung änderbar):
  WASD bewegen (immer Laufschritt) · Shift sprinten · C hocken (= schleichen) · Z hinlegen
  Leertaste springen / klettern (vor Hindernis) / aufstehen · Q/E lehnen
  Maus links feuern · Maus rechts zielen · R nachladen · 1–3 Waffen · 4 Fernglas · 5 Verband
  F benutzen · V Kamera 1./3. Person · F1–F4 / Tab Soldat wechseln
  G/H/J/K/L/N/T Truppbefehle · M taktische Karte · O Ziele · F5/F9 Schnellspeichern/-laden · Esc Menü

Hinweis: Der Ordner orig_cache enthält aus der eigenen Hidden-&-Dangerous-2-Installation erzeugte
Daten (Level, Modelle, Texturen, Sprache, Musik). Nur zum eigenen Spieltest – nicht weitergeben.
"@ | Out-File -Encoding utf8 "$out\SPIELTEST_LIESMICH.txt"
"Spieltest-Build: $out"
