# Finaler Spieltest-Build zum Kopieren auf andere PCs (auch zwei PCs im LAN).
# Aufruf: release.cmd  bzw.  powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 [-Out <Ordner>] [-Zip] [-Verify] [-NoHD]
#   -Out     Zielordner (Standard: build\release\DangerousHidden2_v<Version>)
#   -Zip     zusätzlich ein ZIP daneben erzeugen (dauert bei ~5 GB einige Minuten)
#   -Verify  danach mit der fertigen EXE prüfen: Gameplay-Test und LAN-Test mit zwei Prozessen
#   -NoHD    ohne KI-Texturen (textures_hd/textures_4k) – kleiner, dann nur Originaltexturen
# Ergebnis: <Ordner>\DangerousHidden2.exe + DangerousHidden2.pck (Spieldaten, B-038) + version.txt, <Ordner>\orig_cache\ (aus der eigenen
# HD2-Installation erzeugte Originaldaten – nur für den eigenen Gebrauch, nicht weitergeben),
# Firewall_freigeben.cmd, SPIELTEST_LIESMICH.txt.
param([string]$Out = "", [switch]$Zip, [switch]$Verify, [switch]$NoHD)
$ErrorActionPreference = "Stop"
# Abbrüche immer in die Ausgabe (Erfolgsstrom) schreiben: bei Umleitung nur von stdout (> datei) ging die Fehlermeldung
# sonst verloren und das Protokoll endete kommentarlos (Exit 1).
trap {
  "!! ABBRUCH: $($_.Exception.Message)"
  "   $($_.InvocationInfo.PositionMessage)"
  exit 1
}
$proj = Split-Path $PSScriptRoot -Parent
Set-Location $proj
$godot = "$proj\tools\godot.cmd"

$pg = Get-Content "$proj\project.godot" -Raw
$version = if ($pg -match 'config/version="([^"]*)"') { $Matches[1] } else { "0.0.0" }
if (-not $Out) { $Out = "$proj\build\release\DangerousHidden2_v$version" }
"== Dangerous and Hidden 2 – Release-Build v$version -> $Out"

# 0) Alte Release-Builds unter build\release entfernen (vor jedem Release). Verzeichnisverweise (z. B. orig_cache als
#    Junction auf den Projektcache) werden nur als Verweis gelöscht – nie deren Ziel.
function Remove-ReleaseDir([string]$dir) {
  Get-ChildItem -LiteralPath $dir -Recurse -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object { if (Test-Path -LiteralPath $_.FullName) { [IO.Directory]::Delete($_.FullName, $false) } }
  if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    [IO.Directory]::Delete($dir, $false)
  } else {
    Remove-Item -LiteralPath $dir -Recurse -Force
  }
}
$relRoot = "$proj\build\release"
if (Test-Path $relRoot) {
  $old = @(Get-ChildItem -LiteralPath $relRoot -Force)
  if ($old) {
    "-- Alte Release-Builds entfernen: $($old.Name -join ', ')"
    foreach ($o in $old) {
      if ($o.PSIsContainer) { Remove-ReleaseDir $o.FullName } else { Remove-Item -LiteralPath $o.FullName -Force }
    }
  }
}
if (-not (Test-Path "$proj\orig_cache\textures")) { throw "orig_cache fehlt nach dem Aufräumen – Abbruch (Verweis-Löschung prüfen)." }

if (-not (Test-Path "$proj\orig_cache\textures")) { throw "orig_cache fehlt – erst die Originaldaten konvertieren (tools\convert_all.ps1)." }
# Fehlerhafte Sammelordner (z. B. „arctic1,arctic2,…“ aus einem als ein String übergebenen Missions-Array) nicht mitspiegeln
$bad = @(Get-ChildItem -LiteralPath "$proj\orig_cache" -Directory | Where-Object { $_.Name -match '[,;]' })
if ($bad) { throw "orig_cache enthält fehlerhafte Ordner: $($bad.Name -join ' | ') – mit rd /s /q `"\\?\<Pfad>`" löschen." }

# 1) Import + Skriptprüfung (unter der Test-Sperre der Agenten)
$lock = "$proj\test_output\.godot_lock"
New-Item -ItemType Directory -Force "$proj\test_output" | Out-Null
# Slot 1 belegt (lange Löserläufe) -> freien zweiten Slot nehmen
if ((Test-Path $lock) -and -not (Test-Path "$proj\test_output\.godot_lock2")) { $lock = "$proj\test_output\.godot_lock2" }
while ((Test-Path $lock) -and ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 20) {
  "   warte auf Test-Sperre ($(Get-Content $lock)) …"; Start-Sleep 30
}
"release-build" | Set-Content $lock
try {
  "-- Import"
  cmd /c "`"$godot`" --headless --import > `"$proj\test_output\release_import.log`" 2>&1"
  "-- Skriptprüfung"
  cmd /c "`"$godot`" --headless -- --autoplay=check_scripts > `"$proj\test_output\release_check.log`" 2>&1"
  $res = Select-String -Path "$proj\test_output\release_check.log" -Pattern "^ERGEBNIS" | Select-Object -Last 1
  "   $($res.Line)"
  if ($LASTEXITCODE -ne 0) { throw "Skriptprüfung fehlgeschlagen (test_output\release_check.log) – kein Build." }

  # 2) Export (B-038: EXE + separate DangerousHidden2.pck, embed_pck=false im Preset)
  New-Item -ItemType Directory -Force $Out | Out-Null
  Remove-Item "$Out\DangerousHidden2.exe", "$Out\DangerousHidden2.pck", "$Out\version.txt" -ErrorAction SilentlyContinue
  "-- Export"
  . "$PSScriptRoot\build_key.ps1"
  Add-BuildKey -Root $proj | Out-Host
  try {
    cmd /c "`"$godot`" --headless --export-release `"Windows Desktop`" `"$Out\DangerousHidden2.exe`" > `"$proj\test_output\release_export.log`" 2>&1"
  } finally { Remove-BuildKey -Root $proj | Out-Host }
  foreach ($f in @("DangerousHidden2.exe", "DangerousHidden2.pck")) {
    if (-not (Test-Path "$Out\$f") -or (Get-Item "$Out\$f").Length -eq 0) { throw "Export fehlgeschlagen: $f fehlt (test_output\release_export.log)." }
  }
  # Versionsmarke für die Startprüfung (Game._check_pck_version) und das Nutzer-Werkzeug
  [IO.File]::WriteAllText("$Out\version.txt", $version, (New-Object Text.UTF8Encoding $false))
  "   EXE + PCK ($([math]::Round((Get-Item "$Out\DangerousHidden2.pck").Length / 1MB, 1)) MB), version.txt = $version"
} finally { Remove-Item $lock -ErrorAction SilentlyContinue }

# 3) Originaldaten (orig_cache) spiegeln – nur Änderungen werden kopiert
"-- Originaldaten kopieren"
# Missionsordner (arctic1 …) werden vom Spiel gebraucht und daher mitkopiert; nur textures_sd entfällt
$xd = @("$proj\orig_cache\textures_sd")
if ($NoHD) { $xd += @("$proj\orig_cache\textures_hd", "$proj\orig_cache\textures_4k") }
$rc = @("$proj\orig_cache", "$Out\orig_cache", "/MIR", "/MT:8", "/R:1", "/W:1", "/NFL", "/NDL", "/NP", "/NJH", "/XF", "*.tmp", "*.part", "/XD") + $xd
& robocopy @rc | Select-Object -Last 6
if ($LASTEXITCODE -ge 8) { throw "Kopieren der Originaldaten fehlgeschlagen (robocopy $LASTEXITCODE)." }
"   robocopy $LASTEXITCODE (0–7 = ok)"
$global:LASTEXITCODE = 0   # robocopy 1–7 ist Erfolg und darf nicht als Exit-Code des Skripts durchschlagen

# 4) Firewall-Freigabe für LAN (muss auf jedem Ziel-PC einmal als Administrator laufen)
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

# 4b) Nutzer-Werkzeug: Menü + Konverter (eigener Code, keine Originaldaten) + Paketlisten, damit Spieler die
#     Spieldaten selbst aus ihrer Installation erzeugen und Texturen hochskalieren können
"-- Nutzer-Werkzeug (HD2-Werkzeuge.cmd, pipeline, tools\user)"
Copy-Item "$proj\HD2-Werkzeuge.cmd" $Out -Force
# 0.10.8: Lizenzhinweise der Fremdquellen gehören ins Paket (Pflicht)
if (-not (Test-Path "$proj\THIRD_PARTY_LICENSES.txt")) { throw "THIRD_PARTY_LICENSES.txt fehlt" }
Copy-Item "$proj\THIRD_PARTY_LICENSES.txt" $Out -Force
New-Item -ItemType Directory -Force "$Out\tools\user", "$Out\pipeline" | Out-Null
Copy-Item "$proj\tools\user\*" "$Out\tools\user" -Force
Get-ChildItem "$proj\pipeline" -File -Filter *.py | ForEach-Object { Copy-Item $_.FullName "$Out\pipeline" -Force }
foreach ($f in @("wav_tables.json")) { Remove-Item "$Out\pipeline\$f" -ErrorAction SilentlyContinue }   # aus rw_data.dll – nie mitliefern
# 5) Lies-mich (aus build\playtest übernehmen, falls vorhanden; Version ersetzen)
$readme = "$proj\build\playtest\SPIELTEST_LIESMICH.txt"
$selbst = @"

SPIELDATEN SELBST ERZEUGEN (eigene Installation von Hidden & Dangerous 2 nötig)
  1. HD2-Werkzeuge.cmd doppelklicken.
  2. 1) Original-Installation suchen  -> Ordner mit hd2.exe wählen (wird nur gelesen).
  3. 2) Werkzeuge einrichten          -> Python-Umgebung in werkzeuge\ (fragt vor jedem Download).
  4. 3) Spieldaten exportieren        -> erzeugt orig_cache\ neben der EXE (fortsetzbar, Protokoll in
                                         werkzeuge\protokolle\).
  5. 4) Filme konvertieren (optional, ffmpeg) und 5) Texturen hochskalieren (optional, HD/4K,
     CPU oder NVIDIA-GPU; dauert lange, jederzeit fortsetzbar).
  6. 6) Status prüfen, 7) Spiel starten.
  Entwickelt mit der Original-CD-Version; "Courage Under Fire"/"Sabre Squadron" können abweichen.
  Die erzeugten Daten stammen aus dem eigenen Spiel – nicht weitergeben.
"@
$lan = @"

LAN MIT ZWEI PCS
  1. Den kompletten Ordner (DangerousHidden2.exe + DangerousHidden2.pck + version.txt + orig_cache)
     auf beide PCs kopieren. EXE und .pck gehören zusammen – nie einzeln austauschen.
  2. Auf beiden PCs einmal Firewall_freigeben.cmd als Administrator ausführen
     (Netzwerk in Windows als "Privat" eingestellt).
  3. PC 1: MEHRSPIELER-SPIEL – LAN -> Server erstellen -> "Server starten".
  4. PC 2: MEHRSPIELER-SPIEL – LAN -> Server erscheint in der Liste -> "Beitreten"
     (falls nicht: IP von PC 1 eintragen -> "Per IP beitreten").
  Voraussetzung: Windows 10/11, 64 Bit, Grafikkarte mit DirectX 12.
"@
if (Test-Path $readme) {
  $t = [IO.File]::ReadAllText($readme, [Text.Encoding]::UTF8) -replace "Spieltest-Build v[0-9.]+", "Spieltest-Build v$version"
  if ($t -notmatch "LAN MIT ZWEI PCS") { $t += $lan }
  if ($t -notmatch "SPIELDATEN SELBST ERZEUGEN") { $t += $selbst }
  [IO.File]::WriteAllText("$Out\SPIELTEST_LIESMICH.txt", $t, (New-Object Text.UTF8Encoding $true))
} else {
  [IO.File]::WriteAllText("$Out\SPIELTEST_LIESMICH.txt", "DANGEROUS AND HIDDEN 2 (unofficial) – Spieltest-Build v$version`r`n" + $lan + $selbst, (New-Object Text.UTF8Encoding $true))
}

# 6) Optional: Prüfung mit der fertigen EXE (startet sich für den LAN-Test selbst als Client)
if ($Verify) {
  "-- Prüfung mit der fertigen EXE"
  Push-Location $Out
  foreach ($s in @(@{n = "test_gameplay"; a = "--headless -- --mission=m01_funkfeuer --autoplay=test_gameplay"},
                   @{n = "test_lan_e2e";  a = "--headless -- --autoplay=test_lan_e2e --profiles_dir=user://test_lan_host --noimport"})) {
    cmd /c ".\DangerousHidden2.exe $($s.a) > `"$proj\test_output\release_$($s.n).log`" 2>&1"
    $r = Select-String -Path "$proj\test_output\release_$($s.n).log" -Pattern "^ERGEBNIS" | Select-Object -Last 1
    "   {0,-14} Exit {1}  {2}" -f $s.n, $LASTEXITCODE, $r.Line
  }
  Pop-Location
  Remove-Item -Recurse "$Out\test_output" -ErrorAction SilentlyContinue
}

# 7) Optional: ZIP
if ($Zip) {
  "-- ZIP erstellen"
  $zipPath = "$Out.zip"
  Remove-Item $zipPath -ErrorAction SilentlyContinue
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($Out, $zipPath, [IO.Compression.CompressionLevel]::Fastest, $true)
  "   $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1GB, 2)) GB)"
}

$size = (Get-ChildItem $Out -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
"== Fertig: $Out ($([math]::Round($size / 1GB, 2)) GB). Den ganzen Ordner auf den Ziel-PC kopieren und DangerousHidden2.exe starten."
exit 0
