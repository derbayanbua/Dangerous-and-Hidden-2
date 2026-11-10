# Öffentliches Paket (B-038): EXE + separate .pck aus einem Release-Tag, ohne lokale/private Inhalte.
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\build_public.ps1 -Tag v0.9.6 [-Out <Ordner>] [-KeepWorktree] [-NoZip]
# Ablauf:
#   1) git worktree aus dem Tag (D:\Workspace_D\dh2_public_<tag>, detached) – lokale/ignorierte Inhalte fehlen dort
#   2) Preset "Windows Public" im Worktree auf embed_pck=false erzwingen (ältere Tags hatten true)
#   3) Import + Export --export-release "Windows Public" (unter der Test-Sperre, beide Slots)
#   4) Prüfung: EXE und PCK vorhanden; keine privaten Stichwörter (.git\info\private_words) in EXE **und** PCK
#      (Treffer in Godots Sprachnamenliste werden ignoriert)
#   5) version.txt, Firewall_freigeben.cmd, SPIELTEST_LIESMICH.txt, HD2-Werkzeuge.cmd, pipeline\*.py, tools\user
#   6) ZIP build\public\DangerousHidden2_v<Version>_public.zip
# Kein Commit, kein Push, kein Upload.
param([Parameter(Mandatory = $true)][string]$Tag, [string]$Out = "", [switch]$KeepWorktree, [switch]$NoZip)
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$godot = "$proj\tools\godot.cmd"
. "$PSScriptRoot\test_lock.ps1"

git -C $proj rev-parse -q --verify "refs/tags/$Tag" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Tag $Tag nicht gefunden." }
$version = $Tag.TrimStart("v")
if (-not $Out) { $Out = "$proj\build\public\DangerousHidden2_v${version}_public" }
$wt = Join-Path (Split-Path $proj -Parent) ("dh2_public_" + ($Tag -replace '[^0-9A-Za-z]', '_'))
"== Öffentliches Paket $Tag -> $Out (Worktree $wt)"

# 1) Worktree
if (Test-Path $wt) { git -C $proj worktree remove --force $wt 2>$null; if (Test-Path $wt) { throw "Worktree $wt existiert noch – bitte prüfen." } }
git -C $proj worktree add --detach $wt $Tag
if ($LASTEXITCODE -ne 0) { throw "git worktree add fehlgeschlagen." }

try {
  # 2) Preset absichern
  $pf = "$wt\export_presets.cfg"
  $cfg = [IO.File]::ReadAllText($pf)
  $cfg = $cfg -replace 'binary_format/embed_pck=true', 'binary_format/embed_pck=false'
  [IO.File]::WriteAllText($pf, $cfg, (New-Object Text.UTF8Encoding $false))
  $pg = [IO.File]::ReadAllText("$wt\project.godot")
  if ($pg -match 'config/version="([^"]*)"' -and $Matches[1] -ne $version) { "   Hinweis: project.godot im Tag = $($Matches[1]), Tag = $version" ; $version = $Matches[1] }

  # 3) Import + Export unter der Sperre
  New-Item -ItemType Directory -Force "$proj\test_output", $Out | Out-Null
  Remove-Item "$Out\DangerousHidden2.exe", "$Out\DangerousHidden2.pck" -ErrorAction SilentlyContinue
  $slots = Get-TestSlots -Proj $proj -Name "build_public" -Count 2
  try {
    "-- Import"
    cmd /c "`"$godot`" --headless --path `"$wt`" --import > `"$proj\test_output\public_import.log`" 2>&1"
    "-- Export"
    cmd /c "`"$godot`" --headless --path `"$wt`" --export-release `"Windows Public`" `"$Out\DangerousHidden2.exe`" > `"$proj\test_output\public_export.log`" 2>&1"
  } finally { Release-TestSlots -Slots $slots -Name "build_public" }
  foreach ($f in @("DangerousHidden2.exe", "DangerousHidden2.pck")) {
    if (-not (Test-Path "$Out\$f") -or (Get-Item "$Out\$f").Length -eq 0) { throw "Export fehlgeschlagen: $f fehlt (test_output\public_export.log)." }
  }

  # 4) Private Stichwörter in EXE und PCK (ASCII und UTF-16LE, ohne Groß/Klein)
  $wortdatei = "$proj\.git\info\private_words"
  $woerter = @()
  if (Test-Path $wortdatei) { $woerter = @(Get-Content $wortdatei -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if (-not $woerter) { Write-Warning "Keine private_words – Stichwortprüfung übersprungen." }
  $treffer = @()
  foreach ($f in @("DangerousHidden2.exe", "DangerousHidden2.pck")) {
    $bytes = [IO.File]::ReadAllBytes("$Out\$f")
    $txt = [Text.Encoding]::GetEncoding(28591).GetString($bytes)          # 1:1 Byte → Zeichen
    $u16 = [Text.Encoding]::Unicode.GetString($bytes)
    foreach ($w in $woerter) {
      $re = [regex]::new([regex]::Escape($w), "IgnoreCase")
      foreach ($hay in @($txt, $u16)) {
        foreach ($m in $re.Matches($hay)) {
          $a = [Math]::Max(0, $m.Index - 3); $ctx = $hay.Substring($a, [Math]::Min(16, $hay.Length - $a))
          if ($ctx -match ('(?i)' + [regex]::Escape($w) + 'n')) { continue }                    # Godot-Sprachliste
          $treffer += "${f}: '$w' bei $($m.Index)"
        }
      }
    }
  }
  if ($treffer) { throw "Private Stichwörter im Paket – Abbruch:`n  " + (($treffer | Select-Object -First 20) -join "`n  ") }
  "   Stichwortprüfung EXE + PCK: ok ($($woerter.Count) Wörter)"

  # 5) Beilagen
  [IO.File]::WriteAllText("$Out\version.txt", $version, (New-Object Text.UTF8Encoding $false))
  Copy-Item "$wt\HD2-Werkzeuge.cmd" $Out -Force
  New-Item -ItemType Directory -Force "$Out\tools\user", "$Out\pipeline" | Out-Null
  Copy-Item "$wt\tools\user\*" "$Out\tools\user" -Force -Recurse
  Get-ChildItem "$wt\pipeline" -File -Filter *.py | ForEach-Object { Copy-Item $_.FullName "$Out\pipeline" -Force }
  @"
@echo off
rem Freigabe fuer Mehrspieler im LAN: Spielport UDP 11001, Serverabfrage UDP 11002, LAN-Suche UDP 27101.
rem Rechtsklick -> "Als Administrator ausfuehren".
set EXE=%~dp0DangerousHidden2.exe
netsh advfirewall firewall delete rule name="Dangerous and Hidden 2" >nul 2>&1
netsh advfirewall firewall add rule name="Dangerous and Hidden 2" dir=in action=allow program="%EXE%" enable=yes profile=private,domain
netsh advfirewall firewall add rule name="Dangerous and Hidden 2" dir=in action=allow protocol=UDP localport=11001,11002,27101 enable=yes profile=private,domain
echo.
echo Freigabe eingerichtet (Netzwerkprofil "Privat" bzw. "Domaene").
pause
"@ | Set-Content -Encoding ASCII "$Out\Firewall_freigeben.cmd"
# 4c) 0.10.3: Startverknuepfung fuer das Konfigurationsmenue des dedizierten Servers (ServerLauncher-Ersatz,
#     Konfigurationen in ServerConfigs\*.cfg neben der EXE; Server = eigener kopfloser Prozess)
[IO.File]::WriteAllText("$Out\DedicatedServer.cmd", "@echo off`r`nrem Dedizierter Server: Konfigurationsmenue (ServerConfigs\*.cfg), Start/Stopp, Status und Konsole.`r`nrem Ohne Menue direkt: DangerousHidden2.exe --headless -- --dedicated=ServerConfigs\Default.cfg`r`nstart `"`" `"%~dp0DangerousHidden2.exe`" -- --server_config`r`n", (New-Object Text.ASCIIEncoding))
  $liesmich = @"
DANGEROUS AND HIDDEN 2 (inoffizieller Nachbau) – Spieltest-Build v$version

INHALT
  DangerousHidden2.exe   Programm
  DangerousHidden2.pck   Spieldaten des Nachbaus (gehört zur EXE – beide immer aus demselben Paket verwenden)
  version.txt            Versionsmarke; beim Start wird geprüft, ob .pck und EXE zusammenpassen
  HD2-Werkzeuge.cmd      Menü: Original-Installation suchen, Spieldaten exportieren, Spiel starten
  Firewall_freigeben.cmd LAN-Freigabe (einmal als Administrator)

SPIELDATEN SELBST ERZEUGEN (eigene Installation von Hidden & Dangerous 2 nötig)
  1. HD2-Werkzeuge.cmd doppelklicken.
  2. 1) Original-Installation suchen, 2) Werkzeuge einrichten, 3) Spieldaten exportieren (-> orig_cache\).
  3. Optional 4) Filme, 5) Texturen hochskalieren. 6) Status, 7) Spiel starten.
  Die erzeugten Daten stammen aus dem eigenen Spiel – nicht weitergeben.

UPDATE
  Neue Version: EXE, .pck und version.txt gemeinsam ersetzen; orig_cache\ bleibt.
  Meldung "Versionskonflikt" beim Start = EXE und .pck stammen aus verschiedenen Paketen.

LAN MIT ZWEI PCS
  1. Den kompletten Ordner (EXE + .pck + orig_cache) auf beide PCs kopieren.
  2. Auf beiden PCs einmal Firewall_freigeben.cmd als Administrator ausführen (Netzwerkprofil "Privat").
  3. PC 1: MEHRSPIELER-SPIEL – LAN -> Server erstellen -> "Server starten".
  4. PC 2: MEHRSPIELER-SPIEL – LAN -> Server in der Liste -> "Beitreten" (sonst IP eintragen).
  Voraussetzung: Windows 10/11, 64 Bit, Grafikkarte mit DirectX 12.
"@
  [IO.File]::WriteAllText("$Out\SPIELTEST_LIESMICH.txt", $liesmich, (New-Object Text.UTF8Encoding $true))

  # 6) ZIP
  if (-not $NoZip) {
    $zipPath = "$Out.zip"
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($Out, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
    "   $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB)"
  }
} finally {
  if (-not $KeepWorktree) { git -C $proj worktree remove --force $wt 2>$null }
}
"== Fertig: $Out"
