# Release: Tests -> Pipeline-Skripte uebernehmen -> Version setzen -> Commit, Tag, Push nach GitHub.
# Aufruf: powershell -File tools\release.ps1 -Version 0.2.0 -Message "Kurzbeschreibung" [-SkipTests]
# Vorgabe des Auftraggebers: JEDER Release wird nach GitHub committet
# (Repo derbayanbua/Dangerous-Hidden-2-, Deploy-Key D:\Workspace_D\.ssh_hd2\id_rsa_hd2, nicht im Repo).
# Originaldaten (orig_cache, Screenshots, Builds) sind per .gitignore ausgeschlossen.
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$Message,
  [switch]$SkipTests
)
$ErrorActionPreference = "Continue"   # Git schreibt Fortschritt nach stderr; geprüft wird $LASTEXITCODE
$proj = Split-Path $PSScriptRoot -Parent
$tools = "D:\Workspace_D\tools"
Set-Location $proj

if (-not $SkipTests) {
  powershell -ExecutionPolicy Bypass -File "$proj\tools\run_tests.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Tests fehlgeschlagen - kein Release." }
}

# Konverter-/RE-Skripte (eigener Code) ins Repo; keine Spieldaten (wav_tables.json stammt aus rw_data.dll)
$pipe = "$proj\pipeline"
New-Item -ItemType Directory -Force $pipe | Out-Null
Get-ChildItem $tools -File -Filter *.py | Where-Object { -not $_.Name.StartsWith("_") } | ForEach-Object { Copy-Item $_.FullName $pipe -Force }   # _*.py = Analyse-Hilfen

# Version in project.godot
$pg = [IO.File]::ReadAllText("$proj\project.godot")
$pg = [regex]::Replace($pg, 'config/version="[^"]*"', "config/version=""$Version""")
[IO.File]::WriteAllText("$proj\project.godot", $pg, (New-Object Text.UTF8Encoding $false))

git add -A
if ($LASTEXITCODE -ne 0) { throw "git add fehlgeschlagen" }
git commit -m "Release v${Version}: $Message" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
if ($LASTEXITCODE -ne 0) { throw "git commit fehlgeschlagen" }
git tag -a "v$Version" -m "Release v${Version}: $Message"
git push origin HEAD --follow-tags
if ($LASTEXITCODE -ne 0) { throw "git push fehlgeschlagen" }
"Release v$Version nach GitHub uebertragen."
