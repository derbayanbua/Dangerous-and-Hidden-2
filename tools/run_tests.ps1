# Führt alle automatisierten Tests headless aus und fasst zusammen.
# Aufruf: powershell -File tools\run_tests.ps1 [-Exe build\DangerousHidden2.exe]
param([string]$Exe = "")
$proj = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force "$proj\test_output" | Out-Null
$suites = @(
  @{ name = "check_scripts"; args = "--headless -- --autoplay=check_scripts" },
  @{ name = "test_gameplay"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_gameplay" },
  @{ name = "test_systems";  args = "--headless -- --mission=m01_funkfeuer --autoplay=test_systems" },
  @{ name = "test_m02";      args = "--headless -- --mission=m02_nordlicht --autoplay=test_m02" },
  @{ name = "test_m03";      args = "--headless -- --mission=m03_sandsturm --autoplay=test_m03" },
  @{ name = "test_campaign"; args = "--headless -- --autoplay=test_campaign" },
  @{ name = "test_menu";     args = "--headless -- --autoplay=test_menu --profiles_dir=user://test_profiles --noimport" },
  @{ name = "test_profile_import"; args = "--headless -- --autoplay=test_profile_import --profiles_dir=user://test_import" },
  @{ name = "test_vehicles"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_vehicles" },
  @{ name = "test_ls_compiler"; args = "--headless -- --autoplay=test_ls_compiler --scripts=res://orig_cache" },
  @{ name = "test_a1";       args = "--headless -- --mission=a1_blizzard --autoplay=test_a1" },
  @{ name = "test_a2";       args = "--headless -- --mission=a2_erkundung --autoplay=test_orig_part --commandos=1" },
  @{ name = "test_a3";       args = "--headless -- --mission=a3_rendezvous --autoplay=test_orig_part --commandos=4" },
  @{ name = "test_sas";      args = "--headless -- --autoplay=test_sas" },
  @{ name = "test_interactive"; args = "--headless -- --mission=a1_blizzard --autoplay=test_interactive" },
  @{ name = "test_af6";      args = "--headless -- --mission=af6_raubvoegel --autoplay=test_af6" },
  @{ name = "test_items";    args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_items" },
  @{ name = "test_water";    args = "--headless -- --mission=nw1_dampfleitung --autoplay=test_water" },
  @{ name = "test_controls"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_controls" }
)
$failed = 0
if (-not $Exe) {
  # Import aktualisiert u. a. die globale class_name-Registrierung neuer Skripte
  cmd /c "`"$proj\tools\godot.cmd`" --headless --import > `"$proj\test_output\import.log`" 2>&1"
}
foreach ($s in $suites) {
  $log = "$proj\test_output\$($s.name).log"
  if ($Exe) { cmd /c "`"$Exe`" $($s.args) > `"$log`" 2>&1" }
  else { cmd /c "`"$proj\tools\godot.cmd`" $($s.args) > `"$log`" 2>&1" }
  $code = $LASTEXITCODE
  $summary = (Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^ERGEBNIS' } | Select-Object -Last 1)
  "{0,-15} Exit {1}  {2}" -f $s.name, $code, $summary
  Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^FAIL|SCRIPT ERROR' } | ForEach-Object { "    $_" }
  if ($code -ne 0) { $failed++ }
}
if ($failed -gt 0) { "FEHLGESCHLAGEN: $failed Suite(s)"; exit 1 } else { "ALLE TESTS BESTANDEN"; exit 0 }
