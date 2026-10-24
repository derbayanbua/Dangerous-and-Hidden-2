# Konvertiert die Original-Filme (HD2_orig\Gamemovie\*.bik, Bink) lokal nach orig_cache\movies\<Name>.ogv
# (Theora/Vorbis – von Godot direkt abspielbar). Benötigt ffmpeg (mit Bink-Decoder, Standard in ffmpeg-Builds):
#   powershell -File tools\convert_movies.ps1 [-Ffmpeg C:\pfad\ffmpeg.exe] [-Force]
# Es wird nichts heruntergeladen; fehlt ffmpeg, bricht das Skript mit einem Hinweis ab. Die Originaldateien werden
# nur gelesen, die Ausgabe bleibt im lokalen Cache (nicht im Repository, nicht im Export).
param([string]$Ffmpeg = "", [string]$Orig = "", [string]$Ziel = "", [switch]$Force)
$proj = Split-Path $PSScriptRoot -Parent
if (-not $Orig) { $Orig = if ($env:DH2_ORIG) { $env:DH2_ORIG } else { Join-Path (Split-Path $proj -Parent) "HD2_orig" } }
$out = if ($Ziel) { Join-Path $Ziel "movies" } else { Join-Path $proj "orig_cache\movies" }
if (-not $Ffmpeg) {
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($cmd) { $Ffmpeg = $cmd.Source }
  elseif (Test-Path (Join-Path (Split-Path $proj -Parent) "tools\ffmpeg\bin\ffmpeg.exe")) { $Ffmpeg = Join-Path (Split-Path $proj -Parent) "tools\ffmpeg\bin\ffmpeg.exe" }
}
if (-not $Ffmpeg -or -not (Test-Path $Ffmpeg)) {
  Write-Host "ffmpeg nicht gefunden. Bitte ffmpeg installieren (z. B. winget install Gyan.FFmpeg) oder -Ffmpeg angeben."
  exit 2
}
New-Item -ItemType Directory -Force $out | Out-Null
$n = 0
foreach ($f in Get-ChildItem (Join-Path $Orig "Gamemovie") -Filter *.bik) {
  $dst = Join-Path $out ($f.BaseName + ".ogv")
  if ((Test-Path $dst) -and -not $Force) { continue }
  # Video Theora (Qualität 7), Ton Vorbis; Originalauflösung bleibt erhalten
  & $Ffmpeg -hide_banner -loglevel error -y -i $f.FullName -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 $dst
  if ($LASTEXITCODE -eq 0) { $n++; Write-Host "OK  $($f.Name)" } else { Write-Host "FEHLER  $($f.Name)" }
}
Write-Host "$n Filme konvertiert nach $out"
