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
# 0.11.5: -Platform Linux = Preset "Linux Public" (x86_64, separate .pck, gleiche Filter wie "Windows Public",
#   im Worktree aus dem Windows-Preset abgeleitet/abgeglichen), Build-Schluessel wie Windows, Startskripte .sh (LF),
#   Archiv DangerousHidden2_v<Version>_linux_public.tar.gz (Ausfuehrungsrechte per mtree) statt ZIP.
#   -Worktree <Ordner> = vorhandenen Stand statt Tag-Worktree nutzen (nur Probe-Export, nichts wird entfernt).
param([string]$Tag = "", [string]$Out = "", [switch]$KeepWorktree, [switch]$NoZip,
      [ValidateSet("Windows", "Linux")][string]$Platform = "Windows", [string]$Worktree = "")
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$godot = "$proj\tools\godot.cmd"
. "$PSScriptRoot\test_lock.ps1"
$isLinux = ($Platform -eq "Linux")
$preset = if ($isLinux) { "Linux Public" } else { "Windows Public" }
$bin = if ($isLinux) { "DangerousHidden2.x86_64" } else { "DangerousHidden2.exe" }
$suffix = if ($isLinux) { "_linux_public" } else { "_public" }

if ($Worktree) {
  $wt = (Resolve-Path $Worktree).Path; $KeepWorktree = $true
  $pg0 = [IO.File]::ReadAllText("$wt\project.godot")
  if ($pg0 -match 'config/version="([^"]*)"') { $version = $Matches[1] } else { $version = "0.0.0" }
  if (-not $Tag) { $Tag = "v$version" }
} else {
  if (-not $Tag) { throw "-Tag fehlt." }
  git -C $proj rev-parse -q --verify "refs/tags/$Tag" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Tag $Tag nicht gefunden." }
  $version = $Tag.TrimStart("v")
  $wt = Join-Path (Split-Path $proj -Parent) ("dh2_public_" + ($Tag -replace '[^0-9A-Za-z]', '_'))
}
if (-not $Out) { $Out = "$proj\build\public\DangerousHidden2_v${version}${suffix}" }
"== Öffentliches Paket $Tag -> $Out (Worktree $wt)"

# 1) Worktree
if (-not $Worktree) {
  if (Test-Path $wt) { git -C $proj worktree remove --force $wt 2>$null; if (Test-Path $wt) { throw "Worktree $wt existiert noch – bitte prüfen." } }
  git -C $proj worktree add --detach $wt $Tag
  if ($LASTEXITCODE -ne 0) { throw "git worktree add fehlgeschlagen." }
}

try {
  # 2) Preset absichern
  $pf = "$wt\export_presets.cfg"
  $cfg0 = [IO.File]::ReadAllText($pf)
  $cfg = $cfg0 -replace 'binary_format/embed_pck=true', 'binary_format/embed_pck=false'
  if ($isLinux) {
    # Filter immer aus "Windows Public" uebernehmen (eine Quelle fuer Ausschluesse); fehlt das Preset (aeltere Tags), anlegen
    $wm = [regex]::Match($cfg, '(?ms)^\[preset\.(\d+)\]\s*\r?\nname="Windows Public".*?^include_filter="([^"]*)"\s*\r?\n^exclude_filter="([^"]*)"')
    if (-not $wm.Success) { throw "Preset 'Windows Public' fehlt in $pf." }
    $inc = $wm.Groups[2].Value; $exc = $wm.Groups[3].Value
    $lm = [regex]::Match($cfg, '(?ms)^\[preset\.(\d+)\]\s*\r?\nname="Linux Public"')
    if ($lm.Success) {
      $n = $lm.Groups[1].Value
      $cfg = [regex]::Replace($cfg, "(?ms)(^\[preset\.$n\]\s*\r?\nname=`"Linux Public`".*?^include_filter=`")[^`"]*(`"\s*\r?\n^exclude_filter=`")[^`"]*(`")",
        { param($m) $m.Groups[1].Value + $inc + $m.Groups[2].Value + $exc + $m.Groups[3].Value })
    } else {
      $ids = @([regex]::Matches($cfg, '(?m)^\[preset\.(\d+)\]') | ForEach-Object { [int]$_.Groups[1].Value })
      $n = ($ids | Measure-Object -Maximum).Maximum + 1
      $cfg = $cfg.TrimEnd() + "`n`n[preset.$n]`n`nname=`"Linux Public`"`nplatform=`"Linux`"`nrunnable=false`nadvanced_options=false`ndedicated_server=false`ncustom_features=`"`"`nexport_filter=`"all_resources`"`ninclude_filter=`"$inc`"`nexclude_filter=`"$exc`"`nexport_path=`"build/linux_public/DangerousHidden2.x86_64`"`npatches=PackedStringArray()`nencryption_include_filters=`"`"`nencryption_exclude_filters=`"`"`nseed=0`nencrypt_pck=false`nencrypt_directory=false`nscript_export_mode=2`n`n[preset.$n.options]`n`ncustom_template/debug=`"`"`ncustom_template/release=`"`"`ndebug/export_console_wrapper=1`nbinary_format/embed_pck=false`ntexture_format/s3tc_bptc=true`ntexture_format/etc2_astc=false`nbinary_format/architecture=`"x86_64`"`nssh_remote_deploy/enabled=false`n"
      "   Preset 'Linux Public' im Worktree angelegt (preset.$n)"
    }
  }
  if ($cfg -ne $cfg0) { [IO.File]::WriteAllText($pf, $cfg, (New-Object Text.UTF8Encoding $false)) }
  $pg = [IO.File]::ReadAllText("$wt\project.godot")
  if ($pg -match 'config/version="([^"]*)"' -and $Matches[1] -ne $version) { "   Hinweis: project.godot im Tag = $($Matches[1]), Tag = $version" ; $version = $Matches[1] }

  # 3) Import + Export unter der Sperre
  New-Item -ItemType Directory -Force "$proj\test_output", $Out | Out-Null
  Remove-Item "$Out\$bin", "$Out\DangerousHidden2.pck" -ErrorAction SilentlyContinue
  $slots = Get-TestSlots -Proj $proj -Name "build_public" -Count 2
  try {
    "-- Import"
    cmd /c "`"$godot`" --headless --path `"$wt`" --import > `"$proj\test_output\public_import.log`" 2>&1"
    "-- Export"
    . "$PSScriptRoot\build_key.ps1"
    Add-BuildKey -Root $wt | Out-Host
    try {
      cmd /c "`"$godot`" --headless --path `"$wt`" --export-release `"$preset`" `"$Out\$bin`" > `"$proj\test_output\public_export.log`" 2>&1"
    } finally { Remove-BuildKey -Root $wt | Out-Host }
  } finally { Release-TestSlots -Slots $slots -Name "build_public" }
  if (Test-Path "$wt\build_key\client_key.pem") { throw "Build-Schluessel liegt nach dem Export noch im Worktree." }
  foreach ($f in @($bin, "DangerousHidden2.pck")) {
    if (-not (Test-Path "$Out\$f") -or (Get-Item "$Out\$f").Length -eq 0) { throw "Export fehlgeschlagen: $f fehlt (test_output\public_export.log)." }
  }

  # 4) Private Stichwörter in EXE und PCK (ASCII und UTF-16LE, ohne Groß/Klein)
  $wortdatei = "$proj\.git\info\private_words"
  $woerter = @()
  if (Test-Path $wortdatei) { $woerter = @(Get-Content $wortdatei -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if (-not $woerter) { Write-Warning "Keine private_words – Stichwortprüfung übersprungen." }
  $treffer = @()
  foreach ($f in @($bin, "DangerousHidden2.pck")) {
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
  "   Stichwortprüfung $bin + PCK: ok ($($woerter.Count) Wörter)"

  # 5) Beilagen
  [IO.File]::WriteAllText("$Out\version.txt", $version, (New-Object Text.UTF8Encoding $false))
  if ($isLinux) {
    # Nur ASCII-Ergaenzung; Linux-Beilagen in eigener Funktion (gemeinsame Teile: Lizenzen, pipeline, tools\user)
    if (-not (Test-Path "$wt\THIRD_PARTY_LICENSES.txt")) { throw "THIRD_PARTY_LICENSES.txt fehlt im Tag-Stand" }
    Copy-Item "$wt\THIRD_PARTY_LICENSES.txt" $Out -Force
    New-Item -ItemType Directory -Force "$Out\tools\user", "$Out\pipeline" | Out-Null
    Copy-Item "$wt\tools\user\*" "$Out\tools\user" -Force -Recurse
    Get-ChildItem "$wt\pipeline" -File -Filter *.py | ForEach-Object { Copy-Item $_.FullName "$Out\pipeline" -Force }
    . "$PSScriptRoot\build_public_linux.ps1"
    Write-LinuxExtras -Out $Out -Version $version
    if (-not $NoZip) {
      $tgz = "$Out.tar.gz"
      Remove-Item $tgz -ErrorAction SilentlyContinue
      New-LinuxTarball -Dir $Out -Archive $tgz -ExecNames @($bin, "DangerousHidden2.sh", "DedicatedServer.sh")
      "   $tgz ($([math]::Round((Get-Item $tgz).Length / 1MB, 1)) MB)"
    }
    "== Fertig: $Out"
    return
  }
  Copy-Item "$wt\HD2-Werkzeuge.cmd" $Out -Force
  # 0.10.8: Lizenzhinweise der Fremdquellen gehören ins Paket (Pflicht)
  if (-not (Test-Path "$wt\THIRD_PARTY_LICENSES.txt")) { throw "THIRD_PARTY_LICENSES.txt fehlt im Tag-Stand" }
  Copy-Item "$wt\THIRD_PARTY_LICENSES.txt" $Out -Force
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
  Einmal exportierte bzw. hochskalierte Originaldaten (Ordner orig_cache\ und werkzeuge\) können bei jedem
  neuen Release weiterverwendet werden – nur EXE, PCK und version.txt ersetzen.
  Meldung "Versionskonflikt" beim Start = EXE und .pck stammen aus verschiedenen Paketen.

LAN MIT ZWEI PCS
  1. Den kompletten Ordner (EXE + .pck + orig_cache) auf beide PCs kopieren.
  2. Auf beiden PCs einmal Firewall_freigeben.cmd als Administrator ausführen (Netzwerkprofil "Privat").
  3. PC 1: MEHRSPIELER-SPIEL – LAN -> Server erstellen -> "Server starten".
  4. PC 2: MEHRSPIELER-SPIEL – LAN -> Server in der Liste -> "Beitreten" (sonst IP eintragen).
  Voraussetzung: Windows 10/11, 64 Bit, Grafikkarte mit DirectX 12.
"@
  [IO.File]::WriteAllText("$Out\SPIELTEST_LIESMICH.txt", $liesmich, (New-Object Text.UTF8Encoding $true))
  $readme = @"
DANGEROUS AND HIDDEN 2 (unofficial remake) – playtest build v$version

CONTENTS
  DangerousHidden2.exe   Program
  DangerousHidden2.pck   Game data of the remake (belongs to the EXE – always use both from the same package)
  version.txt            Version marker; at start-up the game checks that .pck and EXE match
  HD2-Werkzeuge.cmd      Tools menu: find the original installation, export game data, start the game
                         (language: menu item "Sprache / Language" or HD2-Werkzeuge.cmd -Sprache en)
  Firewall_freigeben.cmd LAN firewall rule (run once as administrator)

CREATE THE GAME DATA YOURSELF (requires your own installation of Hidden & Dangerous 2)
  1. Double-click HD2-Werkzeuge.cmd.
  2. 1) Find original installation, 2) Set up tools, 3) Export game data (-> orig_cache\).
  3. Optional 4) Movies, 5) Upscale textures. 6) Status, 7) Start game.
  The generated data comes from your own game – do not distribute it.

UPDATE
  New version: replace EXE, .pck and version.txt together; orig_cache\ stays.
  Original data that has been exported or upscaled once (folders orig_cache\ and werkzeuge\) can be reused
  with every new release – only replace EXE, PCK and version.txt.
  Message "version conflict" at start-up = EXE and .pck come from different packages.

LAN WITH TWO PCS
  1. Copy the complete folder (EXE + .pck + orig_cache) to both PCs.
  2. On both PCs run Firewall_freigeben.cmd once as administrator (network profile "Private").
  3. PC 1: MULTIPLAYER – LAN -> create server -> "Start server".
  4. PC 2: MULTIPLAYER – LAN -> server in the list -> "Join" (or enter the IP).
  Requirements: Windows 10/11, 64-bit, graphics card with DirectX 12.
"@
  [IO.File]::WriteAllText("$Out\README_EN.txt", $readme, (New-Object Text.UTF8Encoding $true))

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
