# Dangerous and Hidden 2 – Werkzeuge für Spieler (Windows PowerShell 5.1)
# Erzeugt aus der EIGENEN Installation von Hidden & Dangerous 2 die Spieldaten (orig_cache), konvertiert die Filme
# und skaliert Texturen hoch. Die Original-Installation wird nur gelesen. Alles Benötigte landet im Ordner
# 'werkzeuge\' neben dem Spiel; systemweite Installationen (winget) nur nach ausdrücklicher Rückfrage.
# Tools for players: export game data from your OWN Hidden & Dangerous 2 installation (read-only), convert movies,
# upscale textures. Language: -Sprache de|en (alias -Language), otherwise saved setting, otherwise Windows UI language.
#
# Interaktiv:        Doppelklick auf HD2-Werkzeuge.cmd
# Nicht-interaktiv:  powershell -ExecutionPolicy Bypass -File tools\user\hd2_menu.ps1 -Aktion <Aktion> [Optionen]
#   Aktionen: Suchen, Pruefen, Einrichten, Export, Filme, Hochskalieren, Installieren, Wiederherstellen, Status, Starten
#   -Sprache de|en        Sprache der Ausgaben (wird gespeichert)
#   -Orig <Ordner>        Original-Installation (sonst gespeicherte Einstellung bzw. automatische Suche)
#   -Ziel <Ordner>        Ausgabe orig_cache (Standard: orig_cache neben dem Spiel)
#   -Werkzeuge <Ordner>   Werkzeugordner (Standard: werkzeuge\ neben dem Spiel)
#   -Python <python.exe>  vorhandenes Python mit installierten Paketen verwenden
#   -Missionen A,B        nur diese Missionen/Kartenordner exportieren (Export)
#   -Schritte A,B         nur diese Schrittgruppen: Tabellen, Missionen, Mehrspieler, Allgemein (Export)
#   -Neu                  bereits erledigte Schritte erneut ausführen (Export, Filme)
#   -Probelauf            Export: nur die offenen Schritte auflisten, nichts ausführen
#   Export-Status je Schritt in <Ziel>\.dh2_export_status.txt: fehlgeschlagene Schritte wiederholt der nächste Lauf
#   -Stufe hd|4k          Hochskalieren: Stufe (Standard hd)
#   -Geraet cpu|cuda      Hochskalieren: Rechengerät (Standard cpu)
#   -Ordner <Ordner>      Hochskalieren/Installieren: nur diesen Texturordner bearbeiten
#   -Threads <n>          Hochskalieren: CPU-Threads begrenzen
#   -Ja                   alle Rückfragen mit Ja beantworten (Downloads/Installationen!)
param(
  [Alias("Action")]
  [ValidateSet("", "Menue", "Suchen", "Pruefen", "Einrichten", "Export", "Filme", "Hochskalieren", "Installieren",
               "Wiederherstellen", "Status", "Starten")]
  [string]$Aktion = "",
  [Alias("Source")][string]$Orig = "", [Alias("Target")][string]$Ziel = "", [Alias("Tools")][string]$Werkzeuge = "", [string]$Python = "",
  [Alias("Missions")][string[]]$Missionen = @(), [Alias("Steps")][string[]]$Schritte = @(), [Alias("Redo")][switch]$Neu,
  [Alias("Level")][ValidateSet("hd", "4k")][string]$Stufe = "hd", [Alias("Device")][ValidateSet("cpu", "cuda")][string]$Geraet = "cpu",
  [Alias("Folder")][string]$Ordner = "", [int]$Threads = 0, [Alias("Yes")][switch]$Ja, [Alias("DryRun")][switch]$Probelauf,
  [Alias("Language")][ValidateSet("", "de", "en")][string]$Sprache = ""
)
# "Continue": Meldungen externer Programme auf stderr (pip, torch, ffmpeg) sollen PS 5.1 nicht abbrechen;
# Fehler werden über Exitcodes bzw. -ErrorAction Stop an den kritischen Stellen erkannt.
$ErrorActionPreference = "Continue"
# powershell -File übergibt "A,B" als eine Zeichenkette – Listen hier selbst trennen
$Missionen = @($Missionen | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })
$Schritte = @($Schritte | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# --- Sprache: Parameter > gespeicherte Einstellung > Windows-Oberflächensprache ------------------------------------
$script:Lang = "en"
try { if ((Get-UICulture).TwoLetterISOLanguageName -eq "de") { $script:Lang = "de" } } catch { }
function L([string]$de, [string]$en) { if ($script:Lang -eq "de") { $de } else { $en } }

# --- Pfade ---------------------------------------------------------------------------------------------------------
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent          # Spiel- bzw. Projektordner
$Pipeline = if ($env:DH2_PIPELINE) { $env:DH2_PIPELINE } else { Join-Path $Root "pipeline" }
if (-not $Werkzeuge) { $Werkzeuge = Join-Path $Root "werkzeuge" }
$ConfigFile = Join-Path $Werkzeuge "einstellungen.json"
$LogDir = Join-Path $Werkzeuge "protokolle"
$Interaktiv = -not $Aktion -or $Aktion -eq "Menue"

$CAMPAIGN = @("ARCTIC1", "ARCTIC2", "ARCTIC3", "ARCTIC4", "AFRICA1", "AFRICA2", "AFRICA3", "AFRICA4", "AFRICA5", "AFRICA6",
  "NORWAY", "BURMA1", "BURMA2", "ALPS1", "ALPS2", "NORMANDY", "NORMANDY2", "CZECH1", "CZECH2", "CZECH3", "CZECH4", "CZECH5",
  "CZECH6", "TUTORIAL")
$MULTI = @("ARCTIC1_MP", "ARCTIC1_OBJ", "ARCTIC2_MP", "ARCTIC3_OBJ", "ARCTIC4_MP_ZONE", "AFRICA1_MP", "AFRICA1_OBJ",
  "AFRICA2_MP_ZONE", "AFRICA3_MP", "AFRICA3_OBJ", "AFRICA4_OBJ", "AFRICA5_MP", "AFRICA5_MP_ZONE", "AFRIKA5_MP",
  "ALPS1_MP_ZONE", "ARDENS1_OBJ", "BURMA1_MP", "BURMA1_MP_ZONE", "BURMA1_OBJ", "BURMA2_OBJ", "CZECH1_OBJ",
  "CZECH2_MP_ZONE", "CZECH2_OBJ", "CZECH3_MP", "CZECH3_OBJ", "CZECH4_MP_ZONE", "CZECH5_MP_ZONE", "CZECH6_MP_ZONE",
  "LONDON_MP", "NORMANDY_MP", "NORMANDY2_MP_ZONE", "NORMANDY2B_MP_ZONE", "NORMANDY3_MP", "NORMANDY3_MP_ZONE")
# Pflichtdateien der Installation (Archive werden nur gelesen)
$REQUIRED = @("hd2.exe", "rw_data.dll", "Maps.dta", "Missions.dta", "MODELS.DTA", "Sounds.dta", "Scripts.dta", "others.DTA")
$OPTIONAL = @("patch.dta", "mpmaplist.txt", "Maps_C.dta", "Gamemovie", "PlayersProfiles")
$DEV_EXE_SIZE = 6889472     # hd2.exe der Original-CD-Version mit Patch, mit der entwickelt wurde
# KI-Modelle (Real-ESRGAN, BSD-3-Clause) – Größe und Prüfsumme
$MODELS = @(
  @{ Name = "RealESRGAN_x4plus.pth"; MB = 64; Sha = "4FA0D38905F75AC06EB49A7951B426670021BE3018265FD191D2125DF9D682F1"
     Url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" },
  @{ Name = "realesr-general-x4v3.pth"; MB = 5; Sha = "8DC7EDB9AC80CCDC30C3A5DCA6616509367F05FBC184AD95B731F05BECE96292"
     Url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth" })
$PY_EMBED_VER = "3.12.10"
$PY_MODS = "numpy, PIL, pefile, capstone"   # capstone: fmt_fonts.py (B-024/O-003)

# --- Ausgabe-Helfer -----------------------------------------------------------------------------------------------
function Say([string]$t, [string]$c = "Gray") { Write-Host $t -ForegroundColor $c }
function Ok([string]$t) { Say "  [OK]     $t" Green }
function Warn([string]$t) { Say (L "  [HINWEIS] $t" "  [NOTE]   $t") Yellow }
function Err([string]$t) { Say (L "  [FEHLER] $t" "  [ERROR]  $t") Red }
function Title([string]$t) { Say ""; Say "== $t ==" Cyan }
function Log([string]$t) {
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $t" | Out-File -Append -Encoding utf8 (Join-Path $LogDir "werkzeuge.log")
}
function Ask([string]$frage, [bool]$standard = $false) {
  if ($Ja) { Say (L "  $frage -> Ja (-Ja)" "  $frage -> Yes (-Ja)"); return $true }
  if (-not $Interaktiv) { Say (L "  $frage -> Nein (nicht-interaktiv, -Ja zum Bestätigen)" "  $frage -> No (non-interactive, use -Ja to confirm)"); return $false }
  $s = if ($standard) { L "[J/n]" "[Y/n]" } else { L "[j/N]" "[y/N]" }
  $a = Read-Host "  $frage $s"
  if (-not $a) { return $standard }
  $a = $a.Trim().ToLower()
  return $a.StartsWith("j") -or $a.StartsWith("y")
}
function Pause-Menu { if ($Interaktiv) { [void](Read-Host (L "`n  Weiter mit Eingabetaste" "`n  Press Enter to continue")) } }
function Fmt-Size([double]$b) {
  if ($b -ge 1GB) { "{0:N1} GB" -f ($b / 1GB) } elseif ($b -ge 1MB) { "{0:N0} MB" -f ($b / 1MB) } else { "{0:N0} KB" -f ($b / 1KB) }
}
function Dir-Stats([string]$p, [string]$filter = "*") {
  if (-not (Test-Path $p)) { return @{ N = 0; B = 0 } }
  $m = Get-ChildItem $p -Recurse -File -Filter $filter -ErrorAction SilentlyContinue | Measure-Object Length -Sum
  return @{ N = [int]$m.Count; B = [double]$m.Sum }
}

# --- Einstellungen ------------------------------------------------------------------------------------------------
function Load-Config {
  $c = @{ Orig = ""; Ziel = ""; Python = ""; Sprache = "" }
  if (Test-Path $ConfigFile) {
    try {
      $j = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in @("Orig", "Ziel", "Python", "Sprache")) { if ($j.$k) { $c[$k] = [string]$j.$k } }
    } catch { Warn (L "Einstellungen nicht lesbar ($ConfigFile) – werden neu angelegt." "Settings not readable ($ConfigFile) – will be recreated.") }
  }
  return $c
}
function Save-Config {
  New-Item -ItemType Directory -Force $Werkzeuge | Out-Null
  $o = @{ Orig = $Cfg.Orig; Python = $Cfg.Python }
  if ($Cfg.Sprache) { $o.Sprache = $Cfg.Sprache }
  if ($Cfg.Ziel -ne (Join-Path $Root "orig_cache")) { $o.Ziel = $Cfg.Ziel }   # Standardziel nicht festschreiben (Ordner verschiebbar)
  ($o | ConvertTo-Json) | Set-Content -Encoding UTF8 $ConfigFile
}
$Cfg = Load-Config
if ($Cfg.Sprache -in @("de", "en")) { $script:Lang = $Cfg.Sprache }
if ($Sprache) { $script:Lang = $Sprache; if ($Cfg.Sprache -ne $Sprache) { $Cfg.Sprache = $Sprache; $script:SaveLang = $true } }
if ($Orig) { $Cfg.Orig = $Orig }
if ($Ziel) { $Cfg.Ziel = $Ziel }
if ($Python) { $Cfg.Python = $Python }
if (-not $Cfg.Ziel) { $Cfg.Ziel = Join-Path $Root "orig_cache" }
# Explizit gewählte Sprache nur im Menü speichern (nicht-interaktive Aktionen wie Status verändern nichts)
if ($script:SaveLang -and $Interaktiv) { try { Save-Config } catch { } }
try { $Host.UI.RawUI.WindowTitle = (L "Dangerous and Hidden 2 – Werkzeuge" "Dangerous and Hidden 2 – Tools") } catch { }

# ==================================================================================================================
# 1) Original-Installation suchen / prüfen
# ==================================================================================================================
function Find-Installations {
  $found = New-Object System.Collections.Generic.List[object]
  function Add-Cand($p, $src) {
    if (-not $p) { return }
    $p = $p.TrimEnd('\', '"')
    if ((Test-Path (Join-Path $p "hd2.exe")) -and -not ($found | Where-Object { $_.Pfad -eq $p })) {
      $found.Add([pscustomobject]@{ Pfad = $p; Quelle = $src })
    }
  }
  foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Illusion Softworks\Hidden & Dangerous 2",
                   "HKLM:\SOFTWARE\Illusion Softworks\Hidden & Dangerous 2",
                   "HKCU:\SOFTWARE\Illusion Softworks\Hidden & Dangerous 2")) {
    try { $r = Get-ItemProperty $k -ErrorAction Stop; Add-Cand $r.idir "Registry"; if ($r.PathEXE) { Add-Cand (Split-Path $r.PathEXE) "Registry" } } catch { }
  }
  foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games", "HKLM:\SOFTWARE\GOG.com\Games")) {
    try {
      Get-ChildItem $k -ErrorAction Stop | ForEach-Object {
        $g = Get-ItemProperty $_.PSPath
        if ("$($g.gameName)$($g.GAMENAME)" -match "Hidden.*Dangerous 2") { Add-Cand $g.path "GOG" }
      }
    } catch { }
  }
  try {
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) { $libs += (Select-String $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }) }
    foreach ($l in $libs) {
      Get-ChildItem (Join-Path $l "steamapps\common") -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Hidden.*Dangerous.*2" } | ForEach-Object { Add-Cand $_.FullName "Steam" }
    }
  } catch { }
  foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null }).Root) {
    foreach ($sub in @("Program Files (x86)\Illusion Softworks\Hidden & Dangerous 2", "Program Files\Illusion Softworks\Hidden & Dangerous 2",
                       "Program Files (x86)\Take2\Hidden & Dangerous 2", "Spiele\Hidden & Dangerous 2", "Games\Hidden & Dangerous 2")) {
      Add-Cand (Join-Path $d $sub) (L "Standardpfad" "default path")
    }
    foreach ($gog in @("GOG Games", "Program Files (x86)\GOG Galaxy\Games")) {
      Get-ChildItem (Join-Path $d $gog) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "Hidden.*Dangerous.*2" } |
        ForEach-Object { Add-Cand $_.FullName (L "GOG-Ordner" "GOG folder") }
    }
  }
  Add-Cand (Join-Path (Split-Path $Root -Parent) "HD2_orig") (L "Arbeitsordner" "work folder")
  return $found
}

function Get-Edition([string]$p) {
  # liest nur die Archivverzeichnisse; ohne Python/Skript keine Aussage (dann keine Warnung)
  $py = Get-Py
  $sp = Join-Path $Pipeline "hd2_edition.py"
  if (-not $py -or -not (Test-Path $sp)) { return $null }
  try {
    $env:PYTHONIOENCODING = "utf-8"
    $out = & $py -I $sp $p 2>$null | Select-Object -Last 1
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | ConvertFrom-Json) }
  } catch { }
  return $null
}

function Test-Installation([string]$p, [switch]$Quiet) {
  $res = [pscustomobject]@{ Ok = $false; Fehlt = @(); Warnungen = @(); Version = "" }
  if (-not $p -or -not (Test-Path $p)) { $res.Fehlt = @((L "Ordner" "folder")); if (-not $Quiet) { Err (L "Ordner nicht gefunden: $p" "Folder not found: $p") }; return $res }
  foreach ($f in $REQUIRED) { if (-not (Test-Path (Join-Path $p $f))) { $res.Fehlt += $f } }
  foreach ($f in $OPTIONAL) { if (-not (Test-Path (Join-Path $p $f))) { $res.Warnungen += (L "optional fehlt: $f" "optional, missing: $f") } }
  $exe = Join-Path $p "hd2.exe"
  if (Test-Path $exe) {
    $len = (Get-Item $exe).Length
    if ($len -eq $DEV_EXE_SIZE) { $res.Version = L "Original-CD-Version mit Patch (wie Entwicklungsstand)" "original CD version with patch (as used for development)" }
    else {
      $res.Version = L "abweichende hd2.exe ($len Byte)" "different hd2.exe ($len bytes)"
      $res.Warnungen += (L "Andere hd2.exe als beim Entwickeln (z. B. Steam/GOG oder anderer Patch) – einzelne Daten können abweichen." "Different hd2.exe than used for development (e.g. Steam/GOG or another patch) – some data may differ.")
    }
  }
  # B-024/O-004: Courage Under Fire / Sabre Squadron am Inhalt erkennen (zusätzliche Missionsordner in den
  # Archiven, hd2_edition.py), nicht am Pfad – Steam/GOG-Installationen des Grundspiels bekommen keine Warnung.
  $ed = Get-Edition $p
  if ($ed -and $ed.edition -eq "cuf") {
    $x = @($ed.extra_missions) -join ', '
    $res.Warnungen += (L "Erweiterung erkannt ('Courage Under Fire' / 'Sabre Squadron', zusätzliche Missionen: $x). Entwickelt wurde mit dem Grundspiel – der Export übernimmt dessen Missionen, Abweichungen sind möglich." "Expansion detected ('Courage Under Fire' / 'Sabre Squadron', additional missions: $x). Development used the base game – the export takes its missions, differences are possible.")
  }
  if (-not (Test-Path (Join-Path $p "patch.dta"))) { $res.Warnungen += (L "patch.dta fehlt – ohne offiziellen Patch fehlen Mehrspielerkarten/neuere Daten." "patch.dta missing – without the official patch multiplayer maps/newer data are missing.") }
  $res.Ok = $res.Fehlt.Count -eq 0
  if (-not $Quiet) {
    Say (L "  Ordner:  $p" "  Folder:  $p")
    if ($res.Version) { Say "  Version: $($res.Version)" }
    if ($res.Ok) { Ok (L "Alle benötigten Dateien vorhanden." "All required files present.") } else { Err (L "Es fehlen: $($res.Fehlt -join ', ')" "Missing: $($res.Fehlt -join ', ')") }
    foreach ($w in $res.Warnungen) { Warn $w }
  }
  return $res
}

function Action-Suchen {
  Title (L "Original-Installation suchen" "Find original installation")
  Say (L "  Suche in Registry, GOG, Steam und üblichen Ordnern …" "  Searching registry, GOG, Steam and common folders …")
  $list = @(Find-Installations)
  if ($Orig) { $list = @([pscustomobject]@{ Pfad = $Orig; Quelle = "Parameter" }) + $list }
  for ($i = 0; $i -lt $list.Count; $i++) { Say ("  {0}) {1}   ({2})" -f ($i + 1), $list[$i].Pfad, $list[$i].Quelle) }
  if ($list.Count -eq 0) { Warn (L "Keine Installation automatisch gefunden." "No installation found automatically.") }
  $wahl = $null
  if ($Interaktiv) {
    $a = Read-Host (L "  Nummer wählen oder Pfad eingeben (Ordner mit hd2.exe), leer = abbrechen" "  Choose a number or enter a path (folder containing hd2.exe), empty = cancel")
    if (-not $a) { return }
    if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $list.Count) { $wahl = $list[[int]$a - 1].Pfad } else { $wahl = $a.Trim('"', ' ') }
  } elseif ($list.Count -gt 0) { $wahl = $list[0].Pfad }
  if (-not $wahl) { Err (L "Keine Installation angegeben (-Orig <Ordner>)." "No installation given (-Orig <folder>)."); return }
  $r = Test-Installation $wahl
  if ($r.Ok) { $Cfg.Orig = $wahl; Save-Config; Ok (L "Gespeichert als Original-Installation." "Saved as original installation.") }
}

function Require-Orig {
  if (-not $Cfg.Orig) {
    $c = @(Find-Installations)
    if ($c.Count -gt 0) { $Cfg.Orig = $c[0].Pfad; Say (L "  Original-Installation gefunden: $($Cfg.Orig)" "  Original installation found: $($Cfg.Orig)") }
  }
  if (-not $Cfg.Orig) { Err (L "Keine Original-Installation gewählt – Menüpunkt 1 (oder -Orig <Ordner>)." "No original installation selected – menu item 1 (or -Orig <folder>)."); return $false }
  $r = Test-Installation $Cfg.Orig -Quiet
  if (-not $r.Ok) { Err (L "Installation unvollständig ($($Cfg.Orig)): es fehlen $($r.Fehlt -join ', ')" "Installation incomplete ($($Cfg.Orig)): missing $($r.Fehlt -join ', ')"); return $false }
  return $true
}

# ==================================================================================================================
# 2) Werkzeuge einrichten (Python-Umgebung, Pakete, ffmpeg)
# ==================================================================================================================
function Get-PyVersion([string]$exe, [string[]]$pre = @()) {
  try { $v = & $exe @pre -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>$null; if ($LASTEXITCODE -eq 0) { return [string]$v } } catch { }
  return $null
}
function Get-Py {
  $cands = @()
  if ($Cfg.Python) { $cands += $Cfg.Python }
  $cands += @((Join-Path $Werkzeuge "pyenv\Scripts\python.exe"), (Join-Path $Werkzeuge "python\python.exe"))
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}
function Test-PyModules([string]$py, [string]$mods) {
  & $py -I -c "import $mods" 2>$null | Out-Null
  return $LASTEXITCODE -eq 0
}
function Find-SystemPython {
  foreach ($v in @("3.13", "3.12", "3.11", "3.10")) {
    $pl = Get-Command py -ErrorAction SilentlyContinue
    if ($pl) { $x = Get-PyVersion $pl.Source @("-$v"); if ($x -eq $v) { return @{ Exe = $pl.Source; Pre = @("-$v"); V = $v } } }
  }
  $p = Get-Command python -ErrorAction SilentlyContinue
  if ($p -and $p.Source -notmatch "WindowsApps") {
    $x = Get-PyVersion $p.Source
    if ($x -and [version]$x -ge [version]"3.10" -and [version]$x -lt [version]"3.14") { return @{ Exe = $p.Source; Pre = @(); V = $x } }
  }
  return $null
}
function Download([string]$url, [string]$dst) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $tmp = "$dst.part"
  Say (L "  Lade $url …" "  Downloading $url …")
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
  Move-Item -Force $tmp $dst
}
function Install-Requirements([string]$py, [string]$file, [string[]]$extra = @()) {
  $n = Split-Path $file -Leaf
  Say (L "  Installiere Pakete aus $n (nur in $Werkzeuge) …" "  Installing packages from $n (only into $Werkzeuge) …")
  & $py -m pip install --disable-pip-version-check --no-warn-script-location -r $file @extra
  if ($LASTEXITCODE -ne 0) { throw (L "pip-Installation fehlgeschlagen ($file). Internetverbindung prüfen und erneut versuchen." "pip installation failed ($file). Check the internet connection and try again.") }
}
function Setup-Python {
  $py = Get-Py
  if ($py -and (Test-PyModules $py $PY_MODS)) { Ok (L "Python-Umgebung bereit: $py" "Python environment ready: $py"); return $py }
  if (-not $py) {
    Say (L "  Für den Export wird Python 3.10–3.13 benötigt. Es wird eine eigene Umgebung in $Werkzeuge angelegt." "  The export needs Python 3.10–3.13. A separate environment will be created in $Werkzeuge.")
    $sys = Find-SystemPython
    if ($sys) {
      Say (L "  Gefunden: Python $($sys.V) ($($sys.Exe))." "  Found: Python $($sys.V) ($($sys.Exe)).")
      if (Ask (L "Damit eine isolierte Umgebung (venv) in werkzeuge\pyenv anlegen?" "Create an isolated environment (venv) in werkzeuge\pyenv with it?") $true) {
        & $sys.Exe @($sys.Pre) -m venv (Join-Path $Werkzeuge "pyenv")
        if ($LASTEXITCODE -ne 0) { throw (L "venv konnte nicht angelegt werden." "venv could not be created.") }
        $py = Join-Path $Werkzeuge "pyenv\Scripts\python.exe"
      }
    }
    if (-not $py) {
      Say (L "  Möglichkeiten:" "  Options:")
      Say (L "    a) Python $PY_EMBED_VER (Embeddable, ca. 11 MB) von python.org nur nach werkzeuge\python laden – keine Systemänderung" "    a) download Python $PY_EMBED_VER (embeddable, approx. 11 MB) from python.org into werkzeuge\python only – no system change")
      Say (L "    b) Python 3.13 per winget für den aktuellen Benutzer installieren (Systemänderung)" "    b) install Python 3.13 via winget for the current user (system change)")
      $w = if ($Ja) { "a" } elseif ($Interaktiv) { Read-Host (L "  Auswahl a/b (leer = abbrechen)" "  Choice a/b (empty = cancel)") } else { "" }
      if ($w -eq "a") {
        $dir = Join-Path $Werkzeuge "python"
        New-Item -ItemType Directory -Force $dir | Out-Null
        $zip = Join-Path $Werkzeuge "python-embed.zip"
        Download "https://www.python.org/ftp/python/$PY_EMBED_VER/python-$PY_EMBED_VER-embed-amd64.zip" $zip
        Expand-Archive -Force $zip $dir -ErrorAction Stop; Remove-Item $zip
        $pth = Get-ChildItem $dir -Filter "python*._pth" | Select-Object -First 1
        (Get-Content $pth.FullName) -replace '^#\s*import site', 'import site' | Set-Content -Encoding ASCII $pth.FullName
        Download "https://bootstrap.pypa.io/get-pip.py" (Join-Path $Werkzeuge "get-pip.py")
        & (Join-Path $dir "python.exe") (Join-Path $Werkzeuge "get-pip.py") --no-warn-script-location
        if ($LASTEXITCODE -ne 0) { throw (L "pip konnte nicht eingerichtet werden." "pip could not be set up.") }
        $py = Join-Path $dir "python.exe"
      } elseif ($w -eq "b") {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw (L "winget ist nicht verfügbar – bitte Variante a wählen." "winget is not available – please choose option a.") }
        if (-not (Ask (L "Python 3.13 jetzt per winget installieren (Benutzerinstallation, ca. 30 MB)?" "Install Python 3.13 via winget now (user installation, approx. 30 MB)?"))) { return $null }
        winget install --id Python.Python.3.13 --scope user --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        $sys = Find-SystemPython
        if (-not $sys) { throw (L "Python nach der Installation nicht gefunden – Fenster neu öffnen und erneut versuchen." "Python not found after installation – reopen the window and try again.") }
        & $sys.Exe @($sys.Pre) -m venv (Join-Path $Werkzeuge "pyenv")
        $py = Join-Path $Werkzeuge "pyenv\Scripts\python.exe"
      } else { Warn (L "Abgebrochen – ohne Python ist kein Export möglich." "Cancelled – no export possible without Python."); return $null }
    }
  }
  Install-Requirements $py (Join-Path $PSScriptRoot "requirements.txt")
  if (-not (Test-PyModules $py $PY_MODS)) { throw (L "Pakete fehlen nach der Installation." "Packages missing after installation.") }
  $Cfg.Python = $py; Save-Config
  Ok (L "Python-Umgebung bereit: $py" "Python environment ready: $py")
  return $py
}

function Find-Ffmpeg {
  foreach ($c in @((Join-Path $Werkzeuge "ffmpeg\bin\ffmpeg.exe"), (Join-Path $Werkzeuge "ffmpeg.exe"))) { if (Test-Path $c) { return $c } }
  $g = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($g) { return $g.Source }
  $wg = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
  if (Test-Path $wg) {
    $f = Get-ChildItem $wg -Directory -Filter "Gyan.FFmpeg*" -ErrorAction SilentlyContinue | ForEach-Object {
      Get-ChildItem $_.FullName -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($f) { return $f.FullName }
  }
  return $null
}
function Setup-Ffmpeg {
  $f = Find-Ffmpeg
  if ($f) { Ok "ffmpeg: $f"; return $f }
  Say (L "  ffmpeg (für die Filme) fehlt. Möglichkeiten: per winget installieren (Gyan.FFmpeg, ca. 100 MB, Benutzerinstallation)" "  ffmpeg (for the movies) is missing. Options: install via winget (Gyan.FFmpeg, approx. 100 MB, user installation)")
  Say (L "  oder selbst eine ffmpeg.exe nach $Werkzeuge\ffmpeg\bin\ kopieren." "  or copy an ffmpeg.exe to $Werkzeuge\ffmpeg\bin\ yourself.")
  if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask (L "ffmpeg jetzt per winget installieren?" "Install ffmpeg via winget now?"))) {
    winget install --id Gyan.FFmpeg --scope user --accept-package-agreements --accept-source-agreements
    $f = Find-Ffmpeg
    if ($f) { Ok "ffmpeg: $f" } else { Err (L "ffmpeg nach der Installation nicht gefunden – Fenster neu öffnen." "ffmpeg not found after installation – reopen the window.") }
  }
  return $f
}

function Action-Einrichten {
  Title (L "Werkzeuge einrichten" "Set up tools")
  Say (L "  Zielordner: $Werkzeuge" "  Target folder: $Werkzeuge")
  New-Item -ItemType Directory -Force $Werkzeuge | Out-Null
  if (-not (Test-Path (Join-Path $Pipeline "convert_mission.py"))) { Err (L "Konverter fehlen ($Pipeline). Das Paket ist unvollständig." "Converters missing ($Pipeline). The package is incomplete."); return }
  Ok (L "Konverter: $Pipeline" "Converters: $Pipeline")
  try { [void](Setup-Python) } catch { Err $_.Exception.Message; Log "Einrichten Python: $($_.Exception.Message)" }
  [void](Setup-Ffmpeg)
}

# ==================================================================================================================
# 3) Spieldaten exportieren
# ==================================================================================================================
$script:Py = $null
$script:State = $null
$script:ExportLog = $null
function State-File { Join-Path $Cfg.Ziel ".dh2_export_status.txt" }
function State-Has([string]$k) { return $script:State.Contains($k) }
function State-Add([string]$k) { [void]$script:State.Add($k); Add-Content -Encoding UTF8 (State-File) $k }

function Run-Py([string]$label, [string]$script, [string[]]$argv = @()) {
  $sp = Join-Path $Pipeline $script
  if (-not (Test-Path $sp)) { "!! $script fehlt" | Out-File -Append -Encoding utf8 $script:ExportLog; return $false }
  "---- $label :: $script $($argv -join ' ')  $(Get-Date -Format HH:mm:ss)" | Out-File -Append -Encoding utf8 $script:ExportLog
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $al = @("-I", "`"$sp`"")
  foreach ($x in $argv) { if ($x) { $al += "`"$x`"" } }
  $p = Start-Process -FilePath $script:Py -ArgumentList $al -WorkingDirectory $Pipeline -NoNewWindow -PassThru `
        -RedirectStandardOutput $o -RedirectStandardError $e
  $null = $p.Handle                     # ohne gecachtes Handle liefert ExitCode unter PS 5.1 $null
  try { $p.PriorityClass = "BelowNormal" } catch { }
  $p.WaitForExit()
  Get-Content $o, $e -Encoding UTF8 -ErrorAction SilentlyContinue | Out-File -Append -Encoding utf8 $script:ExportLog
  $code = $p.ExitCode
  Remove-Item $o, $e -ErrorAction SilentlyContinue
  if ($code -ne 0) { "!! Exit $code" | Out-File -Append -Encoding utf8 $script:ExportLog }
  return $code -eq 0
}

function Mission-Steps([string]$m) {
  $l = $m.ToLower(); $c = $Cfg.Ziel
  $s = @(
    @{ S = "convert_mission.py"; A = @($m) },
    @{ S = "fmt_mission_extra.py"; A = @($m, "$c\$l\extra.json") },
    @{ S = "extract_mission_audio.py"; A = @($m) },
    @{ S = "export_characters.py"; A = @($m) },
    @{ S = "fmt_actors_items.py"; A = @($m, "$c\$l\actor_params.json") },
    @{ S = "fmt_interactive.py"; A = @($m) },
    @{ S = "fmt_drive.py"; A = @($m) },
    @{ S = "fmt_vehicles.py"; A = @($m) },
    @{ S = "fmt_vehicle_dm.py"; A = @($m) },
    @{ S = "fmt_klz.py"; A = @($m) },
    @{ S = "fmt_meshplayer.py"; A = @($m) },
    @{ S = "fmt_mp_screens.py"; A = @($m) })
  if ($m -eq "AFRICA6") { $s += @{ S = "fmt_ju88.py"; A = @() } }
  return $s
}
function General-Steps {
  $c = $Cfg.Ziel
  $s = @(
    @{ K = "mp"; T = (L "Mehrspielerkarten (Regeln/Zonen)" "Multiplayer maps (rules/zones)"); S = "fmt_mp.py"; A = @() },
    @{ K = "vehicle_dm"; T = (L "Fahrzeug-Schadensmodelle" "Vehicle damage models"); S = "fmt_vehicle_dm.py"; A = @("--all") },
    @{ K = "weapons"; T = (L "Waffen" "Weapons"); S = "export_weapons.py"; A = @() },
    @{ K = "hands"; T = (L "Ego-Hände" "First-person hands"); S = "export_weapons.py"; A = @("--hands") },
    @{ K = "anims"; T = (L "Skriptanimationen" "Script animations"); S = "fmt_i3d.py"; A = @() },
    @{ K = "dmodels"; T = (L "Zerstörbare Objekte" "Destructible objects"); S = "fmt_dmodels.py"; A = @() },
    @{ K = "commands"; T = (L "Befehlsmenü + Sprachausgabe" "Command menu + speech"); S = "fmt_commands.py"; A = @() },
    @{ K = "sounds"; T = (L "Klänge und Musik" "Sounds and music"); S = "fmt_sounds.py"; A = @() },
    @{ K = "dabing"; T = (L "Gesichtsdaten der Sprache" "Lip-sync face data"); S = "fmt_dabing.py"; A = @() },   # B-052
    @{ K = "characters_morph"; T = (L "Alle Figuren mit Gesichtsanimation" "All characters with facial animation"); S = "export_characters.py"; A = @("--all") },   # B-052, nach den Missionen
    @{ K = "blood"; T = (L "Bluttexturen" "Blood textures"); S = "fmt_blood.py"; A = @($Cfg.Orig, $c) },
    @{ K = "humanzones"; T = (L "Trefferzonen" "Hit zones"); S = "fmt_humanzones.py"; A = @() },
    @{ K = "gamedata"; T = (L "Missionsdatenbank" "Mission database"); S = "fmt_gamedata.py"; A = @() },
    @{ K = "roster"; T = (L "Soldaten und Ausrüstung" "Soldiers and equipment"); S = "fmt_roster.py"; A = @() },
    @{ K = "hud"; T = "HUD"; S = "export_hud.py"; A = @() },
    @{ K = "menu"; T = (L "Menüs" "Menus"); S = "_menu_export.py"; A = @() },
    @{ K = "menu_inv"; T = (L "Inventar-Bildschirm" "Inventory screen"); S = "_menu_export_ingame_inv.py"; A = @() },
    @{ K = "menu_spec"; T = (L "Menü-Texte/Ablauf" "Menu texts/flow"); S = "_menu_spec.py"; A = @() },
    @{ K = "fonts"; T = (L "Originalschriften" "Original fonts"); S = "fmt_fonts.py"; A = @($Cfg.Orig, "$c\ui\fonts") })   # B-024/O-003
  if (Test-Path (Join-Path $Cfg.Orig "PlayersProfiles")) {
    $s += @{ K = "profiles"; T = (L "Spielerprofile (Übernahme)" "Player profiles (import)"); S = "fmt_profile.py"; A = @((Join-Path $Cfg.Orig "PlayersProfiles"), "$c\profiles_import.json") }
  }
  return $s
}

function Action-Export {
  Title (L "Spieldaten exportieren" "Export game data")
  if (-not (Require-Orig)) { return }
  $script:Py = Get-Py
  if (-not $script:Py -or -not (Test-PyModules $script:Py $PY_MODS)) {
    Warn (L "Python-Umgebung fehlt oder ist unvollständig." "Python environment missing or incomplete.")
    if (Ask (L "Jetzt einrichten (Menüpunkt 2)?" "Set it up now (menu item 2)?") $true) { try { $script:Py = Setup-Python } catch { Err $_.Exception.Message; return } }
    if (-not $script:Py) { return }
  }
  # Die Original-Installation wird nie beschrieben: Ziel darf nicht in ihr liegen
  $oFull = [IO.Path]::GetFullPath($Cfg.Orig).TrimEnd('\') + '\'
  $zFull = [IO.Path]::GetFullPath($Cfg.Ziel).TrimEnd('\') + '\'
  if ($zFull.StartsWith($oFull, [StringComparison]::OrdinalIgnoreCase)) { Err (L "Ziel liegt in der Original-Installation ($($Cfg.Ziel)) – bitte einen anderen Ordner wählen (-Ziel)." "Target is inside the original installation ($($Cfg.Ziel)) – please choose another folder (-Ziel)."); return }
  New-Item -ItemType Directory -Force $Cfg.Ziel, $LogDir | Out-Null
  $script:ExportLog = Join-Path $LogDir ("export_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
  $script:State = New-Object 'System.Collections.Generic.HashSet[string]'
  if ((Test-Path (State-File)) -and -not $Neu) { Get-Content (State-File) -Encoding UTF8 | ForEach-Object { [void]$script:State.Add($_) } }
  elseif ($Neu) { Remove-Item (State-File) -ErrorAction SilentlyContinue }
  $env:DH2_ORIG = $Cfg.Orig
  $env:DH2_CACHE = $Cfg.Ziel
  $env:DH2_WAV_TABLES = Join-Path $Werkzeuge "wav_tables.json"
  $env:PYTHONIOENCODING = "utf-8"
  $env:PYTHONUTF8 = "1"        # O-024: Pfade mit Umlauten/Leerzeichen
  Say (L "  Quelle (nur lesen): $($Cfg.Orig)" "  Source (read-only): $($Cfg.Orig)")
  Say (L "  Ziel:               $($Cfg.Ziel)" "  Target:             $($Cfg.Ziel)")
  Say (L "  Protokoll:          $script:ExportLog" "  Log:                $script:ExportLog")
  Say (L "  Bereits erledigte Schritte werden übersprungen (-Neu bzw. Menü: neu = alles wiederholen). Abbruch jederzeit mit Strg+C." "  Steps already done are skipped (-Neu or menu: n = redo everything). Cancel any time with Ctrl+C.")
  Log "Export gestartet: $($Cfg.Orig) -> $($Cfg.Ziel)"

  $gruppen = if ($Schritte.Count) { $Schritte } else { @("Tabellen", "Missionen", "Mehrspieler", "Allgemein") }
  $miss = @(); $mp = @()
  if ($Missionen.Count) {
    foreach ($m in $Missionen) { $u = $m.ToUpper(); if ($MULTI -contains $u) { $mp += $u } else { $miss += $u } }
  } else { $miss = $CAMPAIGN; $mp = $MULTI }
  if ($gruppen -notcontains "Missionen") { $miss = @() }
  if ($gruppen -notcontains "Mehrspieler") { $mp = @() }
  $jobs = New-Object System.Collections.Generic.List[object]
  if ($gruppen -contains "Tabellen") { $jobs.Add(@{ K = "wavtables"; T = (L "Audiotabellen" "Audio tables"); Steps = @(@{ S = "read_wav_tables.py"; A = @() }) }) }
  foreach ($m in ($miss + $mp)) { $jobs.Add(@{ K = "mission:$m"; T = (L "Mission $m" "Mission $m"); Steps = (Mission-Steps $m); M = $m }) }
  if ($gruppen -contains "Allgemein") { foreach ($g in General-Steps) { $jobs.Add(@{ K = "global:$($g.K)"; T = $g.T; Steps = @($g) }) } }

  # O-023: fehlende Konverter vorab melden (statt nur "!! fehlt" im Protokoll)
  $fehlt = @($jobs | ForEach-Object { $_.Steps } | ForEach-Object { $_.S } | Sort-Object -Unique | Where-Object { -not (Test-Path (Join-Path $Pipeline $_)) })
  if ($fehlt.Count) { Warn (L "Konverter fehlen in ${Pipeline}: $($fehlt -join ', ') – diese Schritte scheitern und werden beim nächsten Lauf wiederholt." "Converters missing in ${Pipeline}: $($fehlt -join ', ') – these steps fail and are retried on the next run.") }
  if ($Probelauf) {
    Say (L "  PROBELAUF – es wird nichts ausgeführt. Offene Schritte:" "  DRY RUN – nothing is executed. Open steps:")
    foreach ($j in $jobs) {
      if (State-Has $j.K) { continue }
      $n = 0
      foreach ($st in $j.Steps) { $n++; if (-not (State-Has "$($j.K)#$($n):$($st.S)")) { Say ("    {0,-28} {1} {2}" -f $j.T, $st.S, (($st.A | ForEach-Object { "`"$_`"" }) -join ' ')) DarkGray } }
    }
    return
  }
  $act = L "Spieldaten exportieren" "Exporting game data"
  $fehler = @(); $i = 0; $t0 = Get-Date
  foreach ($j in $jobs) {
    $i++
    $pct = [int](100 * ($i - 1) / [Math]::Max(1, $jobs.Count))
    Write-Progress -Activity $act -Status ("[{0}/{1}] {2}" -f $i, $jobs.Count, $j.T) -PercentComplete $pct
    if (State-Has $j.K) { Say ("  [{0,3}/{1}] {2,-34} {3}" -f $i, $jobs.Count, $j.T, (L "bereits erledigt" "already done")) DarkGray; continue }
    $ts = Get-Date; $ok = $true; $bad = @(); $n = 0
    foreach ($st in $j.Steps) {
      # B-024/O-001: Status je Schritt ("<job>#<nr>:<skript>"); erfolgreiche Schritte werden beim nächsten Lauf
      # übersprungen, fehlgeschlagene wiederholt. Der Job selbst gilt erst als erledigt, wenn ALLE Schritte liefen.
      $n++; $sk = "$($j.K)#$($n):$($st.S)"
      if (State-Has $sk) { continue }
      if (Run-Py $j.T $st.S $st.A) { State-Add $sk } else { $ok = $false; $bad += $st.S }
    }
    if ($j.M) { $okLevel = Test-Path (Join-Path $Cfg.Ziel "$($j.M.ToLower())\scene.glb") } else { $okLevel = $ok }
    $dt = [int]((Get-Date) - $ts).TotalSeconds
    if ($ok) { Say ("  [{0,3}/{1}] {2,-34} OK ({3} s)" -f $i, $jobs.Count, $j.T, $dt) Green; State-Add $j.K }
    elseif ($okLevel) { Say ("  [{0,3}/{1}] {2,-34} {4} ({3})" -f $i, $jobs.Count, $j.T, ($bad -join ', '), (L "teilweise" "partial")) Yellow; $fehler += "$($j.T): $($bad -join ', ')" }
    else { Say ("  [{0,3}/{1}] {2,-34} {4} ({3})" -f $i, $jobs.Count, $j.T, ($bad -join ', '), (L "FEHLER" "ERROR")) Red; $fehler += "$($j.T): $($bad -join ', ')" }
  }
  Write-Progress -Activity $act -Completed
  $dauer = [int]((Get-Date) - $t0).TotalMinutes
  Say ""
  if ($fehler.Count) {
    Warn (L "$($fehler.Count) Schritt(e) mit Fehlern (Einzelheiten im Protokoll $script:ExportLog):" "$($fehler.Count) step(s) with errors (details in log $script:ExportLog):")
    $fehler | ForEach-Object { Say "     - $_" Yellow }
    Say (L "  Ein erneuter Start wiederholt nur die fehlgeschlagenen Schritte." "  Running again repeats only the failed steps.")
  } else { Ok (L "Export abgeschlossen ($dauer min)." "Export finished ($dauer min).") }
  Log "Export beendet, Fehler: $($fehler.Count)"
}

# ==================================================================================================================
# 4) Filme
# ==================================================================================================================
function Action-Filme {
  Title (L "Filme konvertieren (Bink -> Ogg Theora)" "Convert movies (Bink -> Ogg Theora)")
  if (-not (Require-Orig)) { return }
  $src = Join-Path $Cfg.Orig "Gamemovie"
  if (-not (Test-Path $src)) { Err (L "Kein Ordner Gamemovie in der Installation." "No Gamemovie folder in the installation."); return }
  $ff = Find-Ffmpeg
  if (-not $ff) { $ff = Setup-Ffmpeg }
  if (-not $ff) { Err (L "ffmpeg fehlt – Menüpunkt 2." "ffmpeg missing – menu item 2."); return }
  $out = Join-Path $Cfg.Ziel "movies"
  New-Item -ItemType Directory -Force $out, $LogDir | Out-Null
  $log = Join-Path $LogDir "filme.log"
  $files = @(Get-ChildItem $src -Filter *.bik)
  Say (L "  $($files.Count) Filme, Ziel $out (fertige werden übersprungen)." "  $($files.Count) movies, target $out (finished ones are skipped).")
  $act = L "Filme konvertieren" "Converting movies"
  $n = 0; $i = 0; $err = 0
  foreach ($f in $files) {
    $i++
    $dst = Join-Path $out ($f.BaseName + ".ogv")
    if ((Test-Path $dst) -and -not $Neu) { continue }
    Write-Progress -Activity $act -Status "[$i/$($files.Count)] $($f.Name)" -PercentComplete (100 * ($i - 1) / $files.Count)
    $tmp = "$dst.tmp.ogv"
    & $ff -hide_banner -loglevel error -y -i $f.FullName -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 $tmp 2>> $log
    if ($LASTEXITCODE -eq 0) { Move-Item -Force $tmp $dst; $n++; Say "  OK      $($f.Name)" Green }
    else { Remove-Item $tmp -ErrorAction SilentlyContinue; $err++; Say (L "  FEHLER  $($f.Name) (siehe $log)" "  ERROR   $($f.Name) (see $log)") Red }
  }
  Write-Progress -Activity $act -Completed
  Ok (L "$n Filme konvertiert, $err Fehler." "$n movies converted, $err errors.")
}

# ==================================================================================================================
# 5) Texturen hochskalieren
# ==================================================================================================================
function Texture-Folders {
  if ($Ordner) { return @($Ordner) }
  return @("textures", "ui\menu\textures", "ui\menu\backgrounds", "ui\hud\textures") | ForEach-Object { Join-Path $Cfg.Ziel $_ } | Where-Object { Test-Path $_ }
}
function Setup-Upscale([string]$py) {
  if (Test-PyModules $py "torch, spandrel") {
    if ($Geraet -eq "cuda") {
      & $py -I -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>$null
      if ($LASTEXITCODE -ne 0) { Warn (L "torch ist installiert, aber ohne nutzbare CUDA-GPU – es wird die CPU verwendet." "torch is installed but no usable CUDA GPU – using the CPU."); $script:Geraet = "cpu" }
    }
    return $true
  }
  Say (L "  Für das Hochskalieren werden PyTorch und spandrel benötigt (nur in $Werkzeuge):" "  Upscaling needs PyTorch and spandrel (only in $Werkzeuge):")
  Say (L "    CPU-Fassung ca. 250 MB Download – läuft auf jedem PC." "    CPU version approx. 250 MB download – runs on every PC.")
  Say (L "    GPU-Fassung (NVIDIA/CUDA) ca. 3 GB Download – vielfach schneller." "    GPU version (NVIDIA/CUDA) approx. 3 GB download – many times faster.")
  $idx = "https://download.pytorch.org/whl/cpu"
  if ($Geraet -eq "cuda") { $idx = "https://download.pytorch.org/whl/cu128" }
  if (-not (Ask (L "PyTorch ($Geraet) jetzt installieren?" "Install PyTorch ($Geraet) now?"))) { return $false }
  & $py -m pip install --disable-pip-version-check --no-warn-script-location torch torchvision --index-url $idx
  if ($LASTEXITCODE -ne 0) { Err (L "PyTorch-Installation fehlgeschlagen." "PyTorch installation failed."); return $false }
  Install-Requirements $py (Join-Path $PSScriptRoot "requirements-upscale.txt")
  return (Test-PyModules $py "torch, spandrel")
}
function Setup-Models {
  $dir = Join-Path $Werkzeuge "sr_models"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $missing = @($MODELS | Where-Object { -not (Test-Path (Join-Path $dir $_.Name)) })
  if ($missing.Count) {
    $mb = 0; foreach ($m in $missing) { $mb += $m.MB }
    $names = ($missing | ForEach-Object { $_.Name }) -join ', '
    Say (L "  KI-Modelle (Real-ESRGAN, BSD-3-Lizenz) fehlen: $names – zusammen ca. $mb MB von github.com." "  AI models (Real-ESRGAN, BSD-3 licence) missing: $names – together approx. $mb MB from github.com.")
    if (-not (Ask (L "Herunterladen?" "Download?"))) { return $false }
    foreach ($m in $missing) {
      $dst = Join-Path $dir $m.Name
      Download $m.Url $dst
      $h = (Get-FileHash $dst -Algorithm SHA256).Hash
      if ($h -ne $m.Sha) { Remove-Item $dst; Err (L "Prüfsumme von $($m.Name) stimmt nicht – Datei verworfen." "Checksum of $($m.Name) does not match – file discarded."); return $false }
      Ok (L "$($m.Name) geprüft." "$($m.Name) verified.")
    }
  }
  $env:DH2_SR_MODELS = $dir
  return $true
}
function Action-Hochskalieren {
  Title (L "Texturen hochskalieren ($($Stufe.ToUpper()), $Geraet)" "Upscale textures ($($Stufe.ToUpper()), $Geraet)")
  $py = Get-Py
  if (-not $py) { Err (L "Python fehlt – zuerst Menüpunkt 2." "Python missing – run menu item 2 first."); return }
  $folders = @(Texture-Folders)
  if (-not $folders.Count) { Err (L "Keine exportierten Texturen gefunden – zuerst Menüpunkt 3." "No exported textures found – run menu item 3 first."); return }
  $total = 0; $open = 0
  foreach ($f in $folders) {
    $n = @(Get-ChildItem $f -Filter *.png -File).Count
    $d = $f.TrimEnd('\') + "_$Stufe"
    $done = if (Test-Path $d) { @(Get-ChildItem $d -Filter *.png -File).Count } else { 0 }
    $total += $n; $open += [Math]::Max(0, $n - $done)
    Say ("  {0,-60} {1,5} {3}, {2,5} {4}" -f $f, $n, $done, (L "Texturen" "textures"), (L "fertig" "done"))
  }
  $sek = if ($Geraet -eq "cuda") { 1.5 } else { if ($Stufe -eq "hd") { 15 } else { 12 } }
  $min = [Math]::Ceiling($open * $sek / 60)
  $std = if ($min -lt 120) { L "$min Minuten" "$min minutes" } else { $h = [Math]::Round($min / 60, 1); L "$h Stunden" "$h hours" }
  $gb = if ($Stufe -eq "hd") { [Math]::Round($total * 0.6 / 1000, 2) } else { [Math]::Round($total * 1.8 / 1000, 2) }
  Say (L "  Offen: $open Texturen. Geschätzte Dauer ca. $std ($Geraet), Platzbedarf ca. $gb GB." "  Open: $open textures. Estimated time approx. $std ($Geraet), disk space approx. $gb GB.")
  if ($Stufe -eq "4k") { Say (L "  Hinweis: 4K baut auf HD auf (fehlende HD-Texturen werden dabei mit erzeugt)." "  Note: 4K builds on HD (missing HD textures are created as well).") }
  Say (L "  Der Lauf ist jederzeit abbrechbar (Strg+C) und setzt beim nächsten Start fort." "  The run can be cancelled any time (Ctrl+C) and resumes on the next start.")
  if ($open -eq 0) { Ok (L "Nichts zu tun." "Nothing to do.") ; return }
  if (-not (Ask (L "Starten?" "Start?") $true)) { return }
  if ($Interaktiv -and -not $PSBoundParameters.ContainsKey("Geraet")) {
    $g = Read-Host (L "  Rechengerät: 1 = CPU (Standard), 2 = NVIDIA-GPU (CUDA)" "  Device: 1 = CPU (default), 2 = NVIDIA GPU (CUDA)")
    if ($g -eq "2") { $script:Geraet = "cuda" }
  }
  if (-not (Setup-Upscale $py)) { return }
  if (-not (Setup-Models)) { return }
  $env:DH2_SR_DEVICE = $Geraet
  if ($Threads -gt 0) { $env:DH2_SR_THREADS = "$Threads" }
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  $log = Join-Path $LogDir "hochskalieren.log"
  $sp = Join-Path $Pipeline "upscale_textures.py"
  $act = L "Hochskalieren" "Upscaling"
  foreach ($f in $folders) {
    $passes = if ($Stufe -eq "4k") { @("hd", "--4k") } else { @("hd") }
    foreach ($pass in $passes) {
      $extra = @(); if ($pass -ne "hd") { $extra = @($pass) }
      Say "  -> $f $($extra -join ' ')"
      "== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $f $($extra -join ' ')" | Out-File -Append -Encoding utf8 $log
      & $py -I $sp $f @extra 2>&1 | ForEach-Object {
        $line = "$_"; $line | Out-File -Append -Encoding utf8 $log
        if ($line -match '^\[(\d+)/(\d+)\]') { Write-Progress -Activity "$act $(Split-Path $f -Leaf)" -Status $line -PercentComplete (100 * [int]$Matches[1] / [int]$Matches[2]) }
        elseif ($line -match 'FERTIG|Texturen|offen') { Say "     $line" }
      }
      if ($LASTEXITCODE -ne 0) { Err (L "Abbruch bei $f (siehe $log)" "Aborted at $f (see $log)"); return }
    }
  }
  Write-Progress -Activity $act -Completed
  Ok (L "Fertig. Das Spiel verwendet automatisch die beste vorhandene Stufe (textures_4k vor textures_hd)." "Done. The game automatically uses the best available level (textures_4k before textures_hd).")
}
function Action-Installieren([switch]$Zurueck) {
  $py = Get-Py
  if (-not $py) { Err (L "Python fehlt – zuerst Menüpunkt 2." "Python missing – run menu item 2 first."); return }
  $base = if ($Ordner) { $Ordner } else { Join-Path $Cfg.Ziel "textures" }
  $sp = Join-Path $Pipeline "upscale_textures.py"
  if ($Zurueck) {
    Title (L "Original-Texturen wiederherstellen" "Restore original textures")
    if (-not (Test-Path "$base`_sd")) { Warn (L "Keine Sicherung ($base`_sd) vorhanden – es ist nichts installiert." "No backup ($base`_sd) present – nothing is installed."); return }
    & $py -I $sp $base --restore
  } else {
    Title (L "HD-Texturen fest installieren" "Install HD textures permanently")
    Say (L "  Normalerweise nicht nötig: das Spiel nutzt textures_hd/textures_4k automatisch." "  Usually not needed: the game uses textures_hd/textures_4k automatically.")
    Say (L "  Installieren kopiert die HD-Fassung über $base (Originale werden vorher nach $base`_sd gesichert)." "  Installing copies the HD version over $base (originals are backed up to $base`_sd first).")
    if (-not (Test-Path "$base`_hd")) { Err (L "Keine HD-Texturen vorhanden – zuerst hochskalieren." "No HD textures present – upscale first."); return }
    if (-not (Ask (L "Fortfahren?" "Continue?"))) { return }
    & $py -I $sp $base --install
  }
  if ($LASTEXITCODE -eq 0) { Ok (L "Erledigt." "Done.") } else { Err (L "Fehlgeschlagen." "Failed.") }
}

# ==================================================================================================================
# 6) Status (nur lesen)
# ==================================================================================================================
function Action-Status {
  Title "Status"
  if ($Cfg.Orig) { [void](Test-Installation $Cfg.Orig) } else { Warn (L "Keine Original-Installation gewählt (Menüpunkt 1)." "No original installation selected (menu item 1).") }
  Say ""
  if (Test-Path (Join-Path $Pipeline "convert_mission.py")) {
    $nc = @(Get-ChildItem $Pipeline -Filter *.py).Count
    Ok (L "Konverter: $Pipeline ($nc Skripte)" "Converters: $Pipeline ($nc scripts)")
  } else { Err (L "Konverter fehlen: $Pipeline" "Converters missing: $Pipeline") }
  $py = Get-Py
  if ($py) {
    if (Test-PyModules $py $PY_MODS) { Ok "Python (Export): $py" } else { Warn (L "Python vorhanden, Pakete fehlen: $py" "Python present, packages missing: $py") }
    if (Test-PyModules $py "torch, spandrel") { Ok (L "Hochskalieren: PyTorch vorhanden" "Upscaling: PyTorch present") } else { Say (L "  [--]     Hochskalieren: PyTorch nicht installiert" "  [--]     Upscaling: PyTorch not installed") DarkGray }
  } else { Warn (L "Python-Umgebung fehlt (Menüpunkt 2)." "Python environment missing (menu item 2).") }
  $ff = Find-Ffmpeg
  if ($ff) { Ok "ffmpeg: $ff" } else { Say (L "  [--]     ffmpeg nicht gefunden (nur für Filme)" "  [--]     ffmpeg not found (only needed for movies)") DarkGray }
  $md = Join-Path $Werkzeuge "sr_models"
  $mods = @($MODELS | Where-Object { Test-Path (Join-Path $md $_.Name) }).Count
  Say (L "  KI-Modelle: $mods/$($MODELS.Count)" "  AI models: $mods/$($MODELS.Count)")
  Say ""
  $c = $Cfg.Ziel
  Say (L "  Spieldaten: $c" "  Game data: $c")
  if (-not (Test-Path $c)) { Warn (L "Noch nicht exportiert (Menüpunkt 3)." "Not exported yet (menu item 3)."); return }
  $camp = @($CAMPAIGN | Where-Object { Test-Path (Join-Path $c "$($_.ToLower())\scene.glb") })
  $mpd = @($MULTI | Where-Object { Test-Path (Join-Path $c "$($_.ToLower())\scene.glb") })
  $line = { param($name, $ok, $info) if ($ok) { Ok ("{0,-22} {1}" -f $name, $info) } else { Warn ("{0,-22} {1}" -f $name, $info) } }
  & $line (L "Kampagnenmissionen" "Campaign missions") ($camp.Count -eq $CAMPAIGN.Count) "$($camp.Count)/$($CAMPAIGN.Count)"
  if ($camp.Count -lt $CAMPAIGN.Count) { Say ("       {0}: {1}" -f (L "fehlen" "missing"), ((@($CAMPAIGN | Where-Object { $camp -notcontains $_ })) -join ', ')) DarkYellow }
  & $line (L "Mehrspielerkarten" "Multiplayer maps") ($mpd.Count -eq $MULTI.Count) "$($mpd.Count)/$($MULTI.Count)"
  foreach ($x in @(@((L "Texturen" "Textures"), "textures"), @((L "Figuren" "Characters"), "characters"), @((L "Waffen" "Weapons"), "weapons"),
                  @((L "Klänge" "Sounds"), "sounds"), @((L "Musik" "Music"), "music"), @((L "Menüs/HUD" "Menus/HUD"), "ui"),
                  @((L "Animationen" "Animations"), "anims"), @((L "Filme" "Movies"), "movies"),
                  @((L "HD-Texturen" "HD textures"), "textures_hd"), @((L "4K-Texturen" "4K textures"), "textures_4k"))) {
    $s = Dir-Stats (Join-Path $c $x[1])
    & $line $x[0] ($s.N -gt 0) ("{0,6} {2}  {1}" -f $s.N, (Fmt-Size $s.B), (L "Dateien" "files"))
  }
  # B-024/O-002: jede Sprachinstallation – mindestens eine texts_<sprache>.json
  $tx = @(Get-ChildItem $c -Filter "texts_*.json" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName.Substring(6) })
  & $line (L "Originaltexte" "Original texts") ($tx.Count -gt 0) ($(if ($tx.Count) { $tx -join ', ' } else { L "keine texts_*.json" "no texts_*.json" }))
  & $line (L "Originalschriften" "Original fonts") (Test-Path (Join-Path $c "ui\fonts\fonts.json")) "ui\fonts\fonts.json"
  foreach ($f in @("items.json", "sounds.json", "commands.json", "mp_maps.json", "missions_db.json", "roster.json")) {
    & $line $f (Test-Path (Join-Path $c $f)) ""
  }
  if ($Cfg.Orig -and (Test-Path (Join-Path $Cfg.Orig "Gamemovie"))) {
    $b = @(Get-ChildItem (Join-Path $Cfg.Orig "Gamemovie") -Filter *.bik).Count
    $o = (Dir-Stats (Join-Path $c "movies") "*.ogv").N
    Say (L "  Filme: $o von $b konvertiert" "  Movies: $o of $b converted")
  }
  $all = Dir-Stats $c
  Say (L "  Gesamt: $($all.N) Dateien, $(Fmt-Size $all.B)" "  Total: $($all.N) files, $(Fmt-Size $all.B)")
}

# ==================================================================================================================
# 7) Spiel starten
# ==================================================================================================================
function Action-Starten {
  $exe = @((Join-Path $Root "DangerousHidden2.exe"), (Join-Path $Root "build\DangerousHidden2.exe")) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $exe) { Err (L "DangerousHidden2.exe nicht gefunden (erwartet in $Root)." "DangerousHidden2.exe not found (expected in $Root)."); return }
  # B-038: Spieldaten liegen als DangerousHidden2.pck neben der EXE (ältere Pakete: in der EXE eingebettet)
  $dir = Split-Path $exe
  $pck = Join-Path $dir "DangerousHidden2.pck"
  $ver = Join-Path $dir "version.txt"
  if (-not (Test-Path $pck)) {
    if (Test-Path $ver) { Err (L "DangerousHidden2.pck fehlt neben der EXE ($dir) – EXE und .pck aus demselben Paket kopieren." "DangerousHidden2.pck missing next to the EXE ($dir) – copy EXE and .pck from the same package."); return }
    Warn (L "Keine DangerousHidden2.pck gefunden – nur ältere Pakete mit eingebetteten Spieldaten starten so." "No DangerousHidden2.pck found – only older packages with embedded game data start this way.")
  } elseif (Test-Path $ver) {
    $v = (Get-Content $ver -TotalCount 1).Trim()
    Say (L "  Version $v (EXE + .pck; das Spiel prüft beim Start, ob beide zusammenpassen)." "  Version $v (EXE + .pck; the game checks at start-up that both match).")
  }
  if (-not (Test-Path (Join-Path $Cfg.Ziel "textures"))) { Warn (L "Es wurden noch keine Spieldaten exportiert – Originalinhalte fehlen dann." "No game data has been exported yet – original content will be missing.") }
  Say (L "  Starte $exe …" "  Starting $exe …")
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
}

# ==================================================================================================================
# Menü
# ==================================================================================================================
function Run-Action([string]$a) {
  try {
    switch ($a) {
      "Suchen" { Action-Suchen }
      "Pruefen" { Title (L "Installation prüfen" "Check installation"); if ($Cfg.Orig) { [void](Test-Installation $Cfg.Orig) } else { Action-Suchen } }
      "Einrichten" { Action-Einrichten }
      "Export" { Action-Export }
      "Filme" { Action-Filme }
      "Hochskalieren" { Action-Hochskalieren }
      "Installieren" { Action-Installieren }
      "Wiederherstellen" { Action-Installieren -Zurueck }
      "Status" { Action-Status }
      "Starten" { Action-Starten }
    }
    return $true
  } catch {
    Err $_.Exception.Message
    Log "$a fehlgeschlagen: $($_.Exception.Message)"
    return $false
  }
}

if (-not $Interaktiv) {
  $ok = Run-Action $Aktion
  if ($ok) { exit 0 } else { exit 1 }
}

while ($true) {
  Clear-Host
  Say "=================================================================" Cyan
  Say (L "   DANGEROUS AND HIDDEN 2  –  Werkzeuge (inoffizielles Fanprojekt)" "   DANGEROUS AND HIDDEN 2  –  Tools (unofficial fan project)") Cyan
  Say "=================================================================" Cyan
  Say (L "   Original-Installation: $(if ($Cfg.Orig) { $Cfg.Orig } else { '(noch nicht gewählt)' })" "   Original installation: $(if ($Cfg.Orig) { $Cfg.Orig } else { '(not selected yet)' })")
  Say (L "   Spieldaten-Ziel:       $($Cfg.Ziel)" "   Game data target:      $($Cfg.Ziel)")
  Say ""
  Say (L "   1) Original-Installation suchen / wählen / prüfen" "   1) Find / select / check original installation")
  Say (L "   2) Werkzeuge einrichten (Python, Pakete, ffmpeg)" "   2) Set up tools (Python, packages, ffmpeg)")
  Say (L "   3) Spieldaten exportieren (fortsetzbar)" "   3) Export game data (resumable)")
  Say (L "   4) Filme konvertieren" "   4) Convert movies")
  Say (L "   5) Texturen hochskalieren / installieren" "   5) Upscale / install textures")
  Say (L "   6) Prüfen / Status" "   6) Check / status")
  Say (L "   7) Spiel starten" "   7) Start game")
  Say "   8) Sprache / Language ($($script:Lang))"
  Say (L "   0) Beenden" "   0) Exit")
  Say ""
  $w = Read-Host (L "   Auswahl" "   Choice")
  switch ($w) {
    "1" { [void](Run-Action "Suchen") }
    "2" { [void](Run-Action "Einrichten") }
    "3" {
      $Neu = $false
      $a = Read-Host (L "  a) alles exportieren (Standard)  b) nur bestimmte Missionen  n) alles neu" "  a) export everything (default)  b) only certain missions  n) redo everything")
      if ($a -eq "b") { $Missionen = @((Read-Host (L "  Missionen (z. B. ARCTIC1,TUTORIAL)" "  Missions (e.g. ARCTIC1,TUTORIAL)")) -split '[,; ]+' | Where-Object { $_ }) ; $Schritte = @("Tabellen", "Missionen", "Mehrspieler") }
      elseif ($a -eq "n") { $Neu = $true; $Missionen = @(); $Schritte = @() }
      else { $Missionen = @(); $Schritte = @() }
      [void](Run-Action "Export")
      $Neu = $false
    }
    "4" { [void](Run-Action "Filme") }
    "5" {
      Say (L "   a) HD (4-fach, max. 2048 px) erzeugen" "   a) create HD (4x, max. 2048 px)")
      Say (L "   b) 4K (zusätzlich, max. 4096 px) erzeugen" "   b) create 4K (additionally, max. 4096 px)")
      Say (L "   c) HD fest installieren   d) Originale wiederherstellen" "   c) install HD permanently   d) restore originals")
      $a = Read-Host (L "   Auswahl" "   Choice")
      switch ($a) {
        "a" { $Stufe = "hd"; [void](Run-Action "Hochskalieren") }
        "b" { $Stufe = "4k"; [void](Run-Action "Hochskalieren") }
        "c" { [void](Run-Action "Installieren") }
        "d" { [void](Run-Action "Wiederherstellen") }
      }
    }
    "6" { [void](Run-Action "Status") }
    "7" { [void](Run-Action "Starten") }
    "8" {
      $script:Lang = if ($script:Lang -eq "de") { "en" } else { "de" }
      $Cfg.Sprache = $script:Lang
      try { Save-Config } catch { }
      try { $Host.UI.RawUI.WindowTitle = (L "Dangerous and Hidden 2 – Werkzeuge" "Dangerous and Hidden 2 – Tools") } catch { }
      continue
    }
    "0" { exit 0 }
    default { continue }
  }
  Pause-Menu
}
