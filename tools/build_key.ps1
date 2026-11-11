# Build-Client-Schluessel (0.11 Masterserver) nur fuer offizielle Exporte einspeisen und danach wieder entfernen.
# Reines ASCII: PowerShell 5.1 liest Skripte ohne BOM als ANSI.
# Wird von build_release.ps1 / build_public.ps1 per Dot-Sourcing genutzt:
#   . "$PSScriptRoot\build_key.ps1"; Add-BuildKey -Root <Projekt/Worktree>; try { Export } finally { Remove-BuildKey -Root <...> }
# Quelle: $env:DH2_BUILD_KEY oder D:\Workspace_D\dh2_build_keys\client-*.key (ausserhalb des Repos).
# Ziel: <Root>\build_key\client_key.pem (gitignored, im Preset per include_filter "build_key/*").
# Der Inhalt wird nie ausgegeben oder protokolliert. Ohne Schluessel: Warnung, Build = "kein offizieller Build".

function Get-BuildKeySource {
  if ($env:DH2_BUILD_KEY -and (Test-Path $env:DH2_BUILD_KEY)) { return $env:DH2_BUILD_KEY }
  $d = "D:\Workspace_D\dh2_build_keys"
  if (Test-Path $d) {
    $k = Get-ChildItem $d -Filter "client-*.key" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($k) { return $k.FullName }
  }
  return $null
}

function Add-BuildKey([Parameter(Mandatory = $true)][string]$Root) {
  $src = Get-BuildKeySource
  if (-not $src) { Write-Warning "Kein Build-Schluessel gefunden - Export ohne Masterserver-Zugang."; return $false }
  $dir = Join-Path $Root "build_key"
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item $src (Join-Path $dir "client_key.pem") -Force
  # Preset muss den Ordner aufnehmen (aeltere Tags: im Worktree nachtragen)
  $preset = Join-Path $Root "export_presets.cfg"
  if (Test-Path $preset) {
    $t = [IO.File]::ReadAllText($preset)
    $n = [regex]::Replace($t, '(?m)^include_filter="(?![^"]*build_key/\*)([^"]*)"', { param($m) 'include_filter="' + $(if ($m.Groups[1].Value) { $m.Groups[1].Value + ', ' } else { '' }) + 'build_key/*"' })
    if ($n -ne $t) { [IO.File]::WriteAllText($preset, $n, (New-Object Text.UTF8Encoding $false)) }
  }
  "   Build-Schluessel eingespeist (kid $([IO.Path]::GetFileNameWithoutExtension($src) -replace '^client-',''))"
  return $true
}

function Remove-BuildKey([Parameter(Mandatory = $true)][string]$Root) {
  $f = Join-Path $Root "build_key\client_key.pem"
  if (Test-Path $f) {
    # ueberschreiben, dann loeschen
    $len = (Get-Item $f).Length
    [IO.File]::WriteAllBytes($f, (New-Object byte[] $len))
    Remove-Item $f -Force
  }
  $imp = Join-Path $Root ".godot\imported"
  Get-ChildItem $imp -Filter "client_key.pem*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  "   Build-Schluessel entfernt"
}
