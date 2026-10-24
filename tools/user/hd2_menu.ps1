# Dangerous and Hidden 2 – Werkzeuge für Spieler (Windows PowerShell 5.1)
# Erzeugt aus der EIGENEN Installation von Hidden & Dangerous 2 die Spieldaten (orig_cache), konvertiert die Filme
# und skaliert Texturen hoch. Die Original-Installation wird nur gelesen. Alles Benötigte landet im Ordner
# 'werkzeuge\' neben dem Spiel; systemweite Installationen (winget) nur nach ausdrücklicher Rückfrage.
#
# Interaktiv:        Doppelklick auf HD2-Werkzeuge.cmd
# Nicht-interaktiv:  powershell -ExecutionPolicy Bypass -File tools\user\hd2_menu.ps1 -Aktion <Aktion> [Optionen]
#   Aktionen: Suchen, Pruefen, Einrichten, Export, Filme, Hochskalieren, Installieren, Wiederherstellen, Status, Starten
#   -Orig <Ordner>        Original-Installation (sonst gespeicherte Einstellung bzw. automatische Suche)
#   -Ziel <Ordner>        Ausgabe orig_cache (Standard: orig_cache neben dem Spiel)
#   -Werkzeuge <Ordner>   Werkzeugordner (Standard: werkzeuge\ neben dem Spiel)
#   -Python <python.exe>  vorhandenes Python mit installierten Paketen verwenden
#   -Missionen A,B        nur diese Missionen/Kartenordner exportieren (Export)
#   -Schritte A,B         nur diese Schrittgruppen: Tabellen, Missionen, Mehrspieler, Allgemein (Export)
#   -Neu                  bereits erledigte Schritte erneut ausführen (Export, Filme)
#   -Stufe hd|4k          Hochskalieren: Stufe (Standard hd)
#   -Geraet cpu|cuda      Hochskalieren: Rechengerät (Standard cpu)
#   -Ordner <Ordner>      Hochskalieren/Installieren: nur diesen Texturordner bearbeiten
#   -Threads <n>          Hochskalieren: CPU-Threads begrenzen
#   -Ja                   alle Rückfragen mit Ja beantworten (Downloads/Installationen!)
param(
  [ValidateSet("", "Menue", "Suchen", "Pruefen", "Einrichten", "Export", "Filme", "Hochskalieren", "Installieren",
               "Wiederherstellen", "Status", "Starten")]
  [string]$Aktion = "",
  [string]$Orig = "", [string]$Ziel = "", [string]$Werkzeuge = "", [string]$Python = "",
  [string[]]$Missionen = @(), [string[]]$Schritte = @(), [switch]$Neu,
  [ValidateSet("hd", "4k")][string]$Stufe = "hd", [ValidateSet("cpu", "cuda")][string]$Geraet = "cpu",
  [string]$Ordner = "", [int]$Threads = 0, [switch]$Ja
)
# "Continue": Meldungen externer Programme auf stderr (pip, torch, ffmpeg) sollen PS 5.1 nicht abbrechen;
# Fehler werden über Exitcodes bzw. -ErrorAction Stop an den kritischen Stellen erkannt.
$ErrorActionPreference = "Continue"
# powershell -File übergibt "A,B" als eine Zeichenkette – Listen hier selbst trennen
$Missionen = @($Missionen | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })
$Schritte = @($Schritte | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = "Dangerous and Hidden 2 – Werkzeuge" } catch { }

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

# --- Ausgabe-Helfer -----------------------------------------------------------------------------------------------
function Say([string]$t, [string]$c = "Gray") { Write-Host $t -ForegroundColor $c }
function Ok([string]$t) { Say "  [OK]     $t" Green }
function Warn([string]$t) { Say "  [HINWEIS] $t" Yellow }
function Err([string]$t) { Say "  [FEHLER] $t" Red }
function Title([string]$t) { Say ""; Say "== $t ==" Cyan }
function Log([string]$t) {
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $t" | Out-File -Append -Encoding utf8 (Join-Path $LogDir "werkzeuge.log")
}
function Ask([string]$frage, [bool]$standard = $false) {
  if ($Ja) { Say "  $frage -> Ja (-Ja)"; return $true }
  if (-not $Interaktiv) { Say "  $frage -> Nein (nicht-interaktiv, -Ja zum Bestätigen)"; return $false }
  $s = if ($standard) { "[J/n]" } else { "[j/N]" }
  $a = Read-Host "  $frage $s"
  if (-not $a) { return $standard }
  return $a.Trim().ToLower().StartsWith("j") -or $a.Trim().ToLower().StartsWith("y")
}
function Pause-Menu { if ($Interaktiv) { [void](Read-Host "`n  Weiter mit Eingabetaste") } }
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
  $c = @{ Orig = ""; Ziel = ""; Python = "" }
  if (Test-Path $ConfigFile) {
    try {
      $j = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in @("Orig", "Ziel", "Python")) { if ($j.$k) { $c[$k] = [string]$j.$k } }
    } catch { Warn "Einstellungen nicht lesbar ($ConfigFile) – werden neu angelegt." }
  }
  return $c
}
function Save-Config {
  New-Item -ItemType Directory -Force $Werkzeuge | Out-Null
  $o = @{ Orig = $Cfg.Orig; Python = $Cfg.Python }
  if ($Cfg.Ziel -ne (Join-Path $Root "orig_cache")) { $o.Ziel = $Cfg.Ziel }   # Standardziel nicht festschreiben (Ordner verschiebbar)
  ($o | ConvertTo-Json) | Set-Content -Encoding UTF8 $ConfigFile
}
$Cfg = Load-Config
if ($Orig) { $Cfg.Orig = $Orig }
if ($Ziel) { $Cfg.Ziel = $Ziel }
if ($Python) { $Cfg.Python = $Python }
if (-not $Cfg.Ziel) { $Cfg.Ziel = Join-Path $Root "orig_cache" }

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
      Add-Cand (Join-Path $d $sub) "Standardpfad"
    }
    foreach ($gog in @("GOG Games", "Program Files (x86)\GOG Galaxy\Games")) {
      Get-ChildItem (Join-Path $d $gog) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "Hidden.*Dangerous.*2" } |
        ForEach-Object { Add-Cand $_.FullName "GOG-Ordner" }
    }
  }
  Add-Cand (Join-Path (Split-Path $Root -Parent) "HD2_orig") "Arbeitsordner"
  return $found
}

function Test-Installation([string]$p, [switch]$Quiet) {
  $res = [pscustomobject]@{ Ok = $false; Fehlt = @(); Warnungen = @(); Version = "" }
  if (-not $p -or -not (Test-Path $p)) { $res.Fehlt = @("Ordner"); if (-not $Quiet) { Err "Ordner nicht gefunden: $p" }; return $res }
  foreach ($f in $REQUIRED) { if (-not (Test-Path (Join-Path $p $f))) { $res.Fehlt += $f } }
  foreach ($f in $OPTIONAL) { if (-not (Test-Path (Join-Path $p $f))) { $res.Warnungen += "optional fehlt: $f" } }
  $exe = Join-Path $p "hd2.exe"
  if (Test-Path $exe) {
    $len = (Get-Item $exe).Length
    if ($len -eq $DEV_EXE_SIZE) { $res.Version = "Original-CD-Version mit Patch (wie Entwicklungsstand)" }
    else { $res.Version = "abweichende hd2.exe ($len Byte)"; $res.Warnungen += "Andere Spielversion als beim Entwickeln – einzelne Daten können fehlen oder abweichen." }
  }
  if ($p -match "(?i)courage|sabre|steamapps|gog") {
    $res.Warnungen += "Vermutlich 'Courage Under Fire' / 'Sabre Squadron' (Steam/GOG). Entwickelt wurde mit der Original-CD-Version – Export wird versucht, Abweichungen sind möglich."
  }
  if (-not (Test-Path (Join-Path $p "patch.dta"))) { $res.Warnungen += "patch.dta fehlt – ohne offiziellen Patch fehlen Mehrspielerkarten/neuere Daten." }
  $res.Ok = $res.Fehlt.Count -eq 0
  if (-not $Quiet) {
    Say "  Ordner:  $p"
    if ($res.Version) { Say "  Version: $($res.Version)" }
    if ($res.Ok) { Ok "Alle benötigten Dateien vorhanden." } else { Err "Es fehlen: $($res.Fehlt -join ', ')" }
    foreach ($w in $res.Warnungen) { Warn $w }
  }
  return $res
}

function Action-Suchen {
  Title "Original-Installation suchen"
  Say "  Suche in Registry, GOG, Steam und üblichen Ordnern …"
  $list = @(Find-Installations)
  if ($Orig) { $list = @([pscustomobject]@{ Pfad = $Orig; Quelle = "Parameter" }) + $list }
  for ($i = 0; $i -lt $list.Count; $i++) { Say ("  {0}) {1}   ({2})" -f ($i + 1), $list[$i].Pfad, $list[$i].Quelle) }
  if ($list.Count -eq 0) { Warn "Keine Installation automatisch gefunden." }
  $wahl = $null
  if ($Interaktiv) {
    $a = Read-Host "  Nummer wählen oder Pfad eingeben (Ordner mit hd2.exe), leer = abbrechen"
    if (-not $a) { return }
    if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $list.Count) { $wahl = $list[[int]$a - 1].Pfad } else { $wahl = $a.Trim('"', ' ') }
  } elseif ($list.Count -gt 0) { $wahl = $list[0].Pfad }
  if (-not $wahl) { Err "Keine Installation angegeben (-Orig <Ordner>)."; return }
  $r = Test-Installation $wahl
  if ($r.Ok) { $Cfg.Orig = $wahl; Save-Config; Ok "Gespeichert als Original-Installation." }
}

function Require-Orig {
  if (-not $Cfg.Orig) {
    $c = @(Find-Installations)
    if ($c.Count -gt 0) { $Cfg.Orig = $c[0].Pfad; Say "  Original-Installation gefunden: $($Cfg.Orig)" }
  }
  if (-not $Cfg.Orig) { Err "Keine Original-Installation gewählt – Menüpunkt 1 (oder -Orig <Ordner>)."; return $false }
  $r = Test-Installation $Cfg.Orig -Quiet
  if (-not $r.Ok) { Err "Installation unvollständig ($($Cfg.Orig)): es fehlen $($r.Fehlt -join ', ')"; return $false }
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
  Say "  Lade $url …"
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
  Move-Item -Force $tmp $dst
}
function Install-Requirements([string]$py, [string]$file, [string[]]$extra = @()) {
  Say "  Installiere Pakete aus $(Split-Path $file -Leaf) (nur in $Werkzeuge) …"
  & $py -m pip install --disable-pip-version-check --no-warn-script-location -r $file @extra
  if ($LASTEXITCODE -ne 0) { throw "pip-Installation fehlgeschlagen ($file). Internetverbindung prüfen und erneut versuchen." }
}
function Setup-Python {
  $py = Get-Py
  if ($py -and (Test-PyModules $py "numpy, PIL, pefile")) { Ok "Python-Umgebung bereit: $py"; return $py }
  if (-not $py) {
    Say "  Für den Export wird Python 3.10–3.13 benötigt. Es wird eine eigene Umgebung in $Werkzeuge angelegt."
    $sys = Find-SystemPython
    if ($sys) {
      Say "  Gefunden: Python $($sys.V) ($($sys.Exe))."
      if (Ask "Damit eine isolierte Umgebung (venv) in werkzeuge\pyenv anlegen?" $true) {
        & $sys.Exe @($sys.Pre) -m venv (Join-Path $Werkzeuge "pyenv")
        if ($LASTEXITCODE -ne 0) { throw "venv konnte nicht angelegt werden." }
        $py = Join-Path $Werkzeuge "pyenv\Scripts\python.exe"
      }
    }
    if (-not $py) {
      Say "  Möglichkeiten:"
      Say "    a) Python $PY_EMBED_VER (Embeddable, ca. 11 MB) von python.org nur nach werkzeuge\python laden – keine Systemänderung"
      Say "    b) Python 3.13 per winget für den aktuellen Benutzer installieren (Systemänderung)"
      $w = if ($Ja) { "a" } elseif ($Interaktiv) { Read-Host "  Auswahl a/b (leer = abbrechen)" } else { "" }
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
        if ($LASTEXITCODE -ne 0) { throw "pip konnte nicht eingerichtet werden." }
        $py = Join-Path $dir "python.exe"
      } elseif ($w -eq "b") {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget ist nicht verfügbar – bitte Variante a wählen." }
        if (-not (Ask "Python 3.13 jetzt per winget installieren (Benutzerinstallation, ca. 30 MB)?")) { return $null }
        winget install --id Python.Python.3.13 --scope user --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        $sys = Find-SystemPython
        if (-not $sys) { throw "Python nach der Installation nicht gefunden – Fenster neu öffnen und erneut versuchen." }
        & $sys.Exe @($sys.Pre) -m venv (Join-Path $Werkzeuge "pyenv")
        $py = Join-Path $Werkzeuge "pyenv\Scripts\python.exe"
      } else { Warn "Abgebrochen – ohne Python ist kein Export möglich."; return $null }
    }
  }
  Install-Requirements $py (Join-Path $PSScriptRoot "requirements.txt")
  if (-not (Test-PyModules $py "numpy, PIL, pefile")) { throw "Pakete fehlen nach der Installation." }
  $Cfg.Python = $py; Save-Config
  Ok "Python-Umgebung bereit: $py"
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
  Say "  ffmpeg (für die Filme) fehlt. Möglichkeiten: per winget installieren (Gyan.FFmpeg, ca. 100 MB, Benutzerinstallation)"
  Say "  oder selbst eine ffmpeg.exe nach $Werkzeuge\ffmpeg\bin\ kopieren."
  if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask "ffmpeg jetzt per winget installieren?")) {
    winget install --id Gyan.FFmpeg --scope user --accept-package-agreements --accept-source-agreements
    $f = Find-Ffmpeg
    if ($f) { Ok "ffmpeg: $f" } else { Err "ffmpeg nach der Installation nicht gefunden – Fenster neu öffnen." }
  }
  return $f
}

function Action-Einrichten {
  Title "Werkzeuge einrichten"
  Say "  Zielordner: $Werkzeuge"
  New-Item -ItemType Directory -Force $Werkzeuge | Out-Null
  if (-not (Test-Path (Join-Path $Pipeline "convert_mission.py"))) { Err "Konverter fehlen ($Pipeline). Das Paket ist unvollständig."; return }
  Ok "Konverter: $Pipeline"
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
    @{ K = "mp"; T = "Mehrspielerkarten (Regeln/Zonen)"; S = "fmt_mp.py"; A = @() },
    @{ K = "vehicle_dm"; T = "Fahrzeug-Schadensmodelle"; S = "fmt_vehicle_dm.py"; A = @("--all") },
    @{ K = "weapons"; T = "Waffen"; S = "export_weapons.py"; A = @() },
    @{ K = "hands"; T = "Ego-Hände"; S = "export_weapons.py"; A = @("--hands") },
    @{ K = "anims"; T = "Skriptanimationen"; S = "fmt_i3d.py"; A = @() },
    @{ K = "dmodels"; T = "Zerstörbare Objekte"; S = "fmt_dmodels.py"; A = @() },
    @{ K = "commands"; T = "Befehlsmenü + Sprachausgabe"; S = "fmt_commands.py"; A = @() },
    @{ K = "sounds"; T = "Klänge und Musik"; S = "fmt_sounds.py"; A = @() },
    @{ K = "blood"; T = "Bluttexturen"; S = "fmt_blood.py"; A = @($Cfg.Orig, $c) },
    @{ K = "humanzones"; T = "Trefferzonen"; S = "fmt_humanzones.py"; A = @() },
    @{ K = "gamedata"; T = "Missionsdatenbank"; S = "fmt_gamedata.py"; A = @() },
    @{ K = "roster"; T = "Soldaten und Ausrüstung"; S = "fmt_roster.py"; A = @() },
    @{ K = "hud"; T = "HUD"; S = "export_hud.py"; A = @() },
    @{ K = "menu"; T = "Menüs"; S = "_menu_export.py"; A = @() },
    @{ K = "menu_inv"; T = "Inventar-Bildschirm"; S = "_menu_export_ingame_inv.py"; A = @() },
    @{ K = "menu_spec"; T = "Menü-Texte/Ablauf"; S = "_menu_spec.py"; A = @() })
  if (Test-Path (Join-Path $Cfg.Orig "PlayersProfiles")) {
    $s += @{ K = "profiles"; T = "Spielerprofile (Übernahme)"; S = "fmt_profile.py"; A = @((Join-Path $Cfg.Orig "PlayersProfiles"), "$c\profiles_import.json") }
  }
  return $s
}

function Action-Export {
  Title "Spieldaten exportieren"
  if (-not (Require-Orig)) { return }
  $script:Py = Get-Py
  if (-not $script:Py -or -not (Test-PyModules $script:Py "numpy, PIL, pefile")) {
    Warn "Python-Umgebung fehlt oder ist unvollständig."
    if (Ask "Jetzt einrichten (Menüpunkt 2)?" $true) { try { $script:Py = Setup-Python } catch { Err $_.Exception.Message; return } }
    if (-not $script:Py) { return }
  }
  New-Item -ItemType Directory -Force $Cfg.Ziel, $LogDir | Out-Null
  $script:ExportLog = Join-Path $LogDir ("export_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
  $script:State = New-Object 'System.Collections.Generic.HashSet[string]'
  if ((Test-Path (State-File)) -and -not $Neu) { Get-Content (State-File) -Encoding UTF8 | ForEach-Object { [void]$script:State.Add($_) } }
  elseif ($Neu) { Remove-Item (State-File) -ErrorAction SilentlyContinue }
  $env:DH2_ORIG = $Cfg.Orig
  $env:DH2_CACHE = $Cfg.Ziel
  $env:DH2_WAV_TABLES = Join-Path $Werkzeuge "wav_tables.json"
  $env:PYTHONIOENCODING = "utf-8"
  Say "  Quelle (nur lesen): $($Cfg.Orig)"
  Say "  Ziel:               $($Cfg.Ziel)"
  Say "  Protokoll:          $script:ExportLog"
  Say "  Bereits erledigte Schritte werden übersprungen (-Neu bzw. Menü: neu = alles wiederholen). Abbruch jederzeit mit Strg+C."
  Log "Export gestartet: $($Cfg.Orig) -> $($Cfg.Ziel)"

  $gruppen = if ($Schritte.Count) { $Schritte } else { @("Tabellen", "Missionen", "Mehrspieler", "Allgemein") }
  $miss = @(); $mp = @()
  if ($Missionen.Count) {
    foreach ($m in $Missionen) { $u = $m.ToUpper(); if ($MULTI -contains $u) { $mp += $u } else { $miss += $u } }
  } else { $miss = $CAMPAIGN; $mp = $MULTI }
  if ($gruppen -notcontains "Missionen") { $miss = @() }
  if ($gruppen -notcontains "Mehrspieler") { $mp = @() }
  $jobs = New-Object System.Collections.Generic.List[object]
  if ($gruppen -contains "Tabellen") { $jobs.Add(@{ K = "wavtables"; T = "Audiotabellen"; Steps = @(@{ S = "read_wav_tables.py"; A = @() }) }) }
  foreach ($m in ($miss + $mp)) { $jobs.Add(@{ K = "mission:$m"; T = "Mission $m"; Steps = (Mission-Steps $m); M = $m }) }
  if ($gruppen -contains "Allgemein") { foreach ($g in General-Steps) { $jobs.Add(@{ K = "global:$($g.K)"; T = $g.T; Steps = @($g) }) } }

  $fehler = @(); $i = 0; $t0 = Get-Date
  foreach ($j in $jobs) {
    $i++
    $pct = [int](100 * ($i - 1) / [Math]::Max(1, $jobs.Count))
    Write-Progress -Activity "Spieldaten exportieren" -Status ("[{0}/{1}] {2}" -f $i, $jobs.Count, $j.T) -PercentComplete $pct
    if (State-Has $j.K) { Say ("  [{0,3}/{1}] {2,-34} bereits erledigt" -f $i, $jobs.Count, $j.T) DarkGray; continue }
    $ts = Get-Date; $ok = $true; $bad = @()
    foreach ($st in $j.Steps) {
      if (-not (Run-Py $j.T $st.S $st.A)) { $ok = $false; $bad += $st.S }
    }
    # Mission gilt als exportiert, wenn das Level selbst (scene.glb) entstanden ist; Teilfehler werden gemeldet
    if ($j.M) { $okLevel = Test-Path (Join-Path $Cfg.Ziel "$($j.M.ToLower())\scene.glb") } else { $okLevel = $ok }
    $dt = [int]((Get-Date) - $ts).TotalSeconds
    if ($ok) { Say ("  [{0,3}/{1}] {2,-34} OK ({3} s)" -f $i, $jobs.Count, $j.T, $dt) Green; State-Add $j.K }
    elseif ($okLevel) { Say ("  [{0,3}/{1}] {2,-34} teilweise ({3})" -f $i, $jobs.Count, $j.T, ($bad -join ', ')) Yellow; State-Add $j.K; $fehler += "$($j.T): $($bad -join ', ')" }
    else { Say ("  [{0,3}/{1}] {2,-34} FEHLER ({3})" -f $i, $jobs.Count, $j.T, ($bad -join ', ')) Red; $fehler += "$($j.T): $($bad -join ', ')" }
  }
  Write-Progress -Activity "Spieldaten exportieren" -Completed
  $dauer = [int]((Get-Date) - $t0).TotalMinutes
  Say ""
  if ($fehler.Count) {
    Warn "$($fehler.Count) Schritt(e) mit Fehlern (Einzelheiten im Protokoll $script:ExportLog):"
    $fehler | ForEach-Object { Say "     - $_" Yellow }
    Say "  Ein erneuter Start wiederholt nur die fehlgeschlagenen Schritte."
  } else { Ok "Export abgeschlossen ($dauer min)." }
  Log "Export beendet, Fehler: $($fehler.Count)"
}

# ==================================================================================================================
# 4) Filme
# ==================================================================================================================
function Action-Filme {
  Title "Filme konvertieren (Bink -> Ogg Theora)"
  if (-not (Require-Orig)) { return }
  $src = Join-Path $Cfg.Orig "Gamemovie"
  if (-not (Test-Path $src)) { Err "Kein Ordner Gamemovie in der Installation."; return }
  $ff = Find-Ffmpeg
  if (-not $ff) { $ff = Setup-Ffmpeg }
  if (-not $ff) { Err "ffmpeg fehlt – Menüpunkt 2."; return }
  $out = Join-Path $Cfg.Ziel "movies"
  New-Item -ItemType Directory -Force $out, $LogDir | Out-Null
  $log = Join-Path $LogDir "filme.log"
  $files = @(Get-ChildItem $src -Filter *.bik)
  Say "  $($files.Count) Filme, Ziel $out (fertige werden übersprungen)."
  $n = 0; $i = 0; $err = 0
  foreach ($f in $files) {
    $i++
    $dst = Join-Path $out ($f.BaseName + ".ogv")
    if ((Test-Path $dst) -and -not $Neu) { continue }
    Write-Progress -Activity "Filme konvertieren" -Status "[$i/$($files.Count)] $($f.Name)" -PercentComplete (100 * ($i - 1) / $files.Count)
    $tmp = "$dst.tmp.ogv"
    & $ff -hide_banner -loglevel error -y -i $f.FullName -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 $tmp 2>> $log
    if ($LASTEXITCODE -eq 0) { Move-Item -Force $tmp $dst; $n++; Say "  OK      $($f.Name)" Green }
    else { Remove-Item $tmp -ErrorAction SilentlyContinue; $err++; Say "  FEHLER  $($f.Name) (siehe $log)" Red }
  }
  Write-Progress -Activity "Filme konvertieren" -Completed
  Ok "$n Filme konvertiert, $err Fehler."
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
      if ($LASTEXITCODE -ne 0) { Warn "torch ist installiert, aber ohne nutzbare CUDA-GPU – es wird die CPU verwendet."; $script:Geraet = "cpu" }
    }
    return $true
  }
  Say "  Für das Hochskalieren werden PyTorch und spandrel benötigt (nur in $Werkzeuge):"
  Say "    CPU-Fassung ca. 250 MB Download – läuft auf jedem PC."
  Say "    GPU-Fassung (NVIDIA/CUDA) ca. 3 GB Download – vielfach schneller."
  $idx = "https://download.pytorch.org/whl/cpu"
  if ($Geraet -eq "cuda") { $idx = "https://download.pytorch.org/whl/cu128" }
  if (-not (Ask "PyTorch ($Geraet) jetzt installieren?")) { return $false }
  & $py -m pip install --disable-pip-version-check --no-warn-script-location torch torchvision --index-url $idx
  if ($LASTEXITCODE -ne 0) { Err "PyTorch-Installation fehlgeschlagen."; return $false }
  Install-Requirements $py (Join-Path $PSScriptRoot "requirements-upscale.txt")
  return (Test-PyModules $py "torch, spandrel")
}
function Setup-Models {
  $dir = Join-Path $Werkzeuge "sr_models"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $missing = @($MODELS | Where-Object { -not (Test-Path (Join-Path $dir $_.Name)) })
  if ($missing.Count) {
    $mb = 0; foreach ($m in $missing) { $mb += $m.MB }
    Say "  KI-Modelle (Real-ESRGAN, BSD-3-Lizenz) fehlen: $(($missing | ForEach-Object { $_.Name }) -join ', ') – zusammen ca. $mb MB von github.com."
    if (-not (Ask "Herunterladen?")) { return $false }
    foreach ($m in $missing) {
      $dst = Join-Path $dir $m.Name
      Download $m.Url $dst
      $h = (Get-FileHash $dst -Algorithm SHA256).Hash
      if ($h -ne $m.Sha) { Remove-Item $dst; Err "Prüfsumme von $($m.Name) stimmt nicht – Datei verworfen."; return $false }
      Ok "$($m.Name) geprüft."
    }
  }
  $env:DH2_SR_MODELS = $dir
  return $true
}
function Action-Hochskalieren {
  Title "Texturen hochskalieren ($($Stufe.ToUpper()), $Geraet)"
  $py = Get-Py
  if (-not $py) { Err "Python fehlt – zuerst Menüpunkt 2."; return }
  $folders = @(Texture-Folders)
  if (-not $folders.Count) { Err "Keine exportierten Texturen gefunden – zuerst Menüpunkt 3."; return }
  $total = 0; $open = 0
  foreach ($f in $folders) {
    $n = @(Get-ChildItem $f -Filter *.png -File).Count
    $d = $f.TrimEnd('\') + "_$Stufe"
    $done = if (Test-Path $d) { @(Get-ChildItem $d -Filter *.png -File).Count } else { 0 }
    $total += $n; $open += [Math]::Max(0, $n - $done)
    Say ("  {0,-60} {1,5} Texturen, {2,5} fertig" -f $f, $n, $done)
  }
  $sek = if ($Geraet -eq "cuda") { 1.5 } else { if ($Stufe -eq "hd") { 15 } else { 12 } }
  $min = [Math]::Ceiling($open * $sek / 60)
  $std = if ($min -lt 120) { "$min Minuten" } else { "$([Math]::Round($min / 60, 1)) Stunden" }
  $gb = if ($Stufe -eq "hd") { [Math]::Round($total * 0.6 / 1000, 2) } else { [Math]::Round($total * 1.8 / 1000, 2) }
  Say "  Offen: $open Texturen. Geschätzte Dauer ca. $std ($Geraet), Platzbedarf ca. $gb GB."
  if ($Stufe -eq "4k") { Say "  Hinweis: 4K baut auf HD auf (fehlende HD-Texturen werden dabei mit erzeugt)." }
  Say "  Der Lauf ist jederzeit abbrechbar (Strg+C) und setzt beim nächsten Start fort."
  if ($open -eq 0) { Ok "Nichts zu tun." ; return }
  if (-not (Ask "Starten?" $true)) { return }
  if ($Interaktiv -and -not $PSBoundParameters.ContainsKey("Geraet")) {
    $g = Read-Host "  Rechengerät: 1 = CPU (Standard), 2 = NVIDIA-GPU (CUDA)"
    if ($g -eq "2") { $script:Geraet = "cuda" }
  }
  if (-not (Setup-Upscale $py)) { return }
  if (-not (Setup-Models)) { return }
  $env:DH2_SR_DEVICE = $Geraet
  if ($Threads -gt 0) { $env:DH2_SR_THREADS = "$Threads" }
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  $log = Join-Path $LogDir "hochskalieren.log"
  $sp = Join-Path $Pipeline "upscale_textures.py"
  foreach ($f in $folders) {
    $passes = if ($Stufe -eq "4k") { @("hd", "--4k") } else { @("hd") }
    foreach ($pass in $passes) {
      $extra = @(); if ($pass -ne "hd") { $extra = @($pass) }
      Say "  -> $f $($extra -join ' ')"
      "== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $f $($extra -join ' ')" | Out-File -Append -Encoding utf8 $log
      & $py -I $sp $f @extra 2>&1 | ForEach-Object {
        $line = "$_"; $line | Out-File -Append -Encoding utf8 $log
        if ($line -match '^\[(\d+)/(\d+)\]') { Write-Progress -Activity "Hochskalieren $(Split-Path $f -Leaf)" -Status $line -PercentComplete (100 * [int]$Matches[1] / [int]$Matches[2]) }
        elseif ($line -match 'FERTIG|Texturen|offen') { Say "     $line" }
      }
      if ($LASTEXITCODE -ne 0) { Err "Abbruch bei $f (siehe $log)"; return }
    }
  }
  Write-Progress -Activity "Hochskalieren" -Completed
  Ok "Fertig. Das Spiel verwendet automatisch die beste vorhandene Stufe (textures_4k vor textures_hd)."
}
function Action-Installieren([switch]$Zurueck) {
  $py = Get-Py
  if (-not $py) { Err "Python fehlt – zuerst Menüpunkt 2."; return }
  $base = if ($Ordner) { $Ordner } else { Join-Path $Cfg.Ziel "textures" }
  $sp = Join-Path $Pipeline "upscale_textures.py"
  if ($Zurueck) {
    Title "Original-Texturen wiederherstellen"
    if (-not (Test-Path "$base`_sd")) { Warn "Keine Sicherung ($base`_sd) vorhanden – es ist nichts installiert."; return }
    & $py -I $sp $base --restore
  } else {
    Title "HD-Texturen fest installieren"
    Say "  Normalerweise nicht nötig: das Spiel nutzt textures_hd/textures_4k automatisch."
    Say "  Installieren kopiert die HD-Fassung über $base (Originale werden vorher nach $base`_sd gesichert)."
    if (-not (Test-Path "$base`_hd")) { Err "Keine HD-Texturen vorhanden – zuerst hochskalieren."; return }
    if (-not (Ask "Fortfahren?")) { return }
    & $py -I $sp $base --install
  }
  if ($LASTEXITCODE -eq 0) { Ok "Erledigt." } else { Err "Fehlgeschlagen." }
}

# ==================================================================================================================
# 6) Status
# ==================================================================================================================
function Action-Status {
  Title "Status"
  if ($Cfg.Orig) { [void](Test-Installation $Cfg.Orig) } else { Warn "Keine Original-Installation gewählt (Menüpunkt 1)." }
  Say ""
  if (Test-Path (Join-Path $Pipeline "convert_mission.py")) { Ok "Konverter: $Pipeline ($(@(Get-ChildItem $Pipeline -Filter *.py).Count) Skripte)" } else { Err "Konverter fehlen: $Pipeline" }
  $py = Get-Py
  if ($py) {
    if (Test-PyModules $py "numpy, PIL, pefile") { Ok "Python (Export): $py" } else { Warn "Python vorhanden, Pakete fehlen: $py" }
    if (Test-PyModules $py "torch, spandrel") { Ok "Hochskalieren: PyTorch vorhanden" } else { Say "  [--]     Hochskalieren: PyTorch nicht installiert" DarkGray }
  } else { Warn "Python-Umgebung fehlt (Menüpunkt 2)." }
  $ff = Find-Ffmpeg
  if ($ff) { Ok "ffmpeg: $ff" } else { Say "  [--]     ffmpeg nicht gefunden (nur für Filme)" DarkGray }
  $md = Join-Path $Werkzeuge "sr_models"
  $mods = @($MODELS | Where-Object { Test-Path (Join-Path $md $_.Name) }).Count
  Say "  KI-Modelle: $mods/$($MODELS.Count)"
  Say ""
  $c = $Cfg.Ziel
  Say "  Spieldaten: $c"
  if (-not (Test-Path $c)) { Warn "Noch nicht exportiert (Menüpunkt 3)."; return }
  $camp = @($CAMPAIGN | Where-Object { Test-Path (Join-Path $c "$($_.ToLower())\scene.glb") })
  $mpd = @($MULTI | Where-Object { Test-Path (Join-Path $c "$($_.ToLower())\scene.glb") })
  $line = { param($name, $ok, $info) if ($ok) { Ok ("{0,-22} {1}" -f $name, $info) } else { Warn ("{0,-22} {1}" -f $name, $info) } }
  & $line "Kampagnenmissionen" ($camp.Count -eq $CAMPAIGN.Count) "$($camp.Count)/$($CAMPAIGN.Count)"
  if ($camp.Count -lt $CAMPAIGN.Count) { Say "       fehlen: $((@($CAMPAIGN | Where-Object { $camp -notcontains $_ })) -join ', ')" DarkYellow }
  & $line "Mehrspielerkarten" ($mpd.Count -eq $MULTI.Count) "$($mpd.Count)/$($MULTI.Count)"
  foreach ($x in @(@("Texturen", "textures"), @("Figuren", "characters"), @("Waffen", "weapons"), @("Klänge", "sounds"),
                  @("Musik", "music"), @("Menüs/HUD", "ui"), @("Animationen", "anims"), @("Filme", "movies"),
                  @("HD-Texturen", "textures_hd"), @("4K-Texturen", "textures_4k"))) {
    $s = Dir-Stats (Join-Path $c $x[1])
    & $line $x[0] ($s.N -gt 0) ("{0,6} Dateien  {1}" -f $s.N, (Fmt-Size $s.B))
  }
  foreach ($f in @("texts_german.json", "items.json", "sounds.json", "commands.json", "mp_maps.json", "missions_db.json", "roster.json")) {
    & $line $f (Test-Path (Join-Path $c $f)) ""
  }
  if ($Cfg.Orig -and (Test-Path (Join-Path $Cfg.Orig "Gamemovie"))) {
    $b = @(Get-ChildItem (Join-Path $Cfg.Orig "Gamemovie") -Filter *.bik).Count
    $o = (Dir-Stats (Join-Path $c "movies") "*.ogv").N
    Say "  Filme: $o von $b konvertiert"
  }
  $all = Dir-Stats $c
  Say "  Gesamt: $($all.N) Dateien, $(Fmt-Size $all.B)"
}

# ==================================================================================================================
# 7) Spiel starten
# ==================================================================================================================
function Action-Starten {
  $exe = @((Join-Path $Root "DangerousHidden2.exe"), (Join-Path $Root "build\DangerousHidden2.exe")) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $exe) { Err "DangerousHidden2.exe nicht gefunden (erwartet in $Root)."; return }
  if (-not (Test-Path (Join-Path $Cfg.Ziel "textures"))) { Warn "Es wurden noch keine Spieldaten exportiert – Originalinhalte fehlen dann." }
  Say "  Starte $exe …"
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
}

# ==================================================================================================================
# Menü
# ==================================================================================================================
function Run-Action([string]$a) {
  try {
    switch ($a) {
      "Suchen" { Action-Suchen }
      "Pruefen" { Title "Installation prüfen"; if ($Cfg.Orig) { [void](Test-Installation $Cfg.Orig) } else { Action-Suchen } }
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
  Say "   DANGEROUS AND HIDDEN 2  –  Werkzeuge (inoffizielles Fanprojekt)" Cyan
  Say "=================================================================" Cyan
  Say "   Original-Installation: $(if ($Cfg.Orig) { $Cfg.Orig } else { '(noch nicht gewählt)' })"
  Say "   Spieldaten-Ziel:       $($Cfg.Ziel)"
  Say ""
  Say "   1) Original-Installation suchen / wählen / prüfen"
  Say "   2) Werkzeuge einrichten (Python, Pakete, ffmpeg)"
  Say "   3) Spieldaten exportieren (fortsetzbar)"
  Say "   4) Filme konvertieren"
  Say "   5) Texturen hochskalieren / installieren"
  Say "   6) Prüfen / Status"
  Say "   7) Spiel starten"
  Say "   0) Beenden"
  Say ""
  $w = Read-Host "   Auswahl"
  switch ($w) {
    "1" { [void](Run-Action "Suchen") }
    "2" { [void](Run-Action "Einrichten") }
    "3" {
      $Neu = $false
      $a = Read-Host "  a) alles exportieren (Standard)  b) nur bestimmte Missionen  n) alles neu"
      if ($a -eq "b") { $Missionen = @((Read-Host "  Missionen (z. B. ARCTIC1,TUTORIAL)") -split '[,; ]+' | Where-Object { $_ }) ; $Schritte = @("Tabellen", "Missionen", "Mehrspieler") }
      elseif ($a -eq "n") { $Neu = $true; $Missionen = @(); $Schritte = @() }
      else { $Missionen = @(); $Schritte = @() }
      [void](Run-Action "Export")
      $Neu = $false
    }
    "4" { [void](Run-Action "Filme") }
    "5" {
      Say "   a) HD (4-fach, max. 2048 px) erzeugen"
      Say "   b) 4K (zusätzlich, max. 4096 px) erzeugen"
      Say "   c) HD fest installieren   d) Originale wiederherstellen"
      $a = Read-Host "   Auswahl"
      switch ($a) {
        "a" { $Stufe = "hd"; [void](Run-Action "Hochskalieren") }
        "b" { $Stufe = "4k"; [void](Run-Action "Hochskalieren") }
        "c" { [void](Run-Action "Installieren") }
        "d" { [void](Run-Action "Wiederherstellen") }
      }
    }
    "6" { [void](Run-Action "Status") }
    "7" { [void](Run-Action "Starten") }
    "0" { exit 0 }
    default { continue }
  }
  Pause-Menu
}
