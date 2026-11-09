# Führt alle automatisierten Tests headless aus und fasst zusammen (B-025).
# Aufruf: powershell -File tools\run_tests.ps1 [-Exe build\DangerousHidden2.exe] [-Full] [-Only test_a1,test_sas] [-Exclude test_mp_coop] [-TimeoutSec 900]
#  - Test-Sperre test_output\.godot_lock/.godot_lock2 (tools\test_lock.ps1): je Suite ein Slot, Mehrspieler-Suiten (mp) beide.
#    Es läuft immer nur eine Suite gleichzeitig.
#  - Zeitlimit je Suite (Standard 900 s, Eintrag `timeout`): bei Hänger wird nur der eigene Prozessbaum beendet, Suite = Fehler.
#  - Bestanden nur mit Exit 0 UND `ERGEBNIS`-Zeile mit 0 Fehlschlägen.
#  - -Full nimmt zusätzlich die langen Suiten (Gruppe "full": Treppen aller Karten, MP-Navigation, Kollision, Löser) auf.
param([string]$Exe = "", [switch]$Full, [string[]]$Only = @(), [string[]]$Exclude = @(), [int]$TimeoutSec = 900)
$proj = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\test_lock.ps1"
New-Item -ItemType Directory -Force "$proj\test_output" | Out-Null
$suites = @(
  @{ name = "check_scripts"; args = "--headless -- --autoplay=check_scripts" },
  @{ name = "test_gameplay"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_gameplay" },
  @{ name = "test_graphics"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_graphics" },
  @{ name = "test_systems";  args = "--headless -- --mission=m01_funkfeuer --autoplay=test_systems" },
  @{ name = "test_m02";      args = "--headless -- --mission=m02_nordlicht --autoplay=test_m02" },
  @{ name = "test_m03";      args = "--headless -- --mission=m03_sandsturm --autoplay=test_m03" },
  @{ name = "test_campaign"; args = "--headless -- --autoplay=test_campaign" },
  @{ name = "test_campaign_end"; args = "--headless -- --autoplay=test_campaign_end --profiles_dir=user://test_campaign_end --noimport" },
  @{ name = "test_menu";     args = "--headless -- --autoplay=test_menu --profiles_dir=user://test_profiles --noimport" },
  @{ name = "test_profile_import"; args = "--headless -- --autoplay=test_profile_import --profiles_dir=user://test_import" },
  @{ name = "test_vehicles"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_vehicles" },
  # O-018: Mindestzahl Originalskripte (alle Missionen im Cache)
  @{ name = "test_ls_compiler"; args = "--headless -- --autoplay=test_ls_compiler --scripts=res://orig_cache --min_scripts=2000" },   # 30.10.2026: 3040 gefunden
  @{ name = "test_a1";       args = "--headless -- --mission=a1_blizzard --autoplay=test_a1" },
  @{ name = "test_audio";    args = "--headless -- --mission=a1_blizzard --autoplay=test_audio" },
  @{ name = "test_ai";       args = "--headless -- --mission=a1_blizzard --autoplay=test_ai" },
  @{ name = "test_ai_fsm";   args = "--headless -- --mission=a1_blizzard --autoplay=test_ai --phase=fsm" },
  @{ name = "test_ai_ap6";   args = "--headless -- --mission=a1_blizzard --autoplay=test_ai --phase=ap6" },
  @{ name = "test_b044";     args = "--headless -- --mission=a1_blizzard --autoplay=test_b044" },   # B-044 Gegner-Stillstand
  @{ name = "test_ally_no2"; args = "--headless -- --mission=no2_schwerttaenzer --autoplay=test_ally_no2" },   # 0.10.1 Verbündete Schwerttänzer
  @{ name = "test_ally_a1";  args = "--headless -- --mission=a1_blizzard --autoplay=test_ally_no2" },   # 0.10.1 Seite 4 (Rebel)
  @{ name = "test_orig_save"; args = "--headless -- --mission=a1_blizzard --autoplay=test_orig_save" },
  @{ name = "test_orig_save_a2"; args = "--headless -- --mission=a2_erkundung --autoplay=test_orig_save --phase=a2" },
  @{ name = "test_orig_cmds"; args = "--headless -- --mission=a1_blizzard --autoplay=test_orig_cmds" },
  @{ name = "test_b028";     args = "--headless -- --mission=a2_erkundung --autoplay=test_b028" },   # B-028 Partikel/Sequenzende/Fässer/stumm
  @{ name = "test_b035";     args = "--headless -- --mission=no1_leuchtturm --autoplay=test_b035" },   # B-035 Leuchtturm/Lightmaps/Gesichter/Wetter
  @{ name = "test_difficulty"; args = "--headless -- --mission=a1_blizzard --autoplay=test_difficulty" },
  @{ name = "test_alarm_orig"; args = "--headless -- --mission=a2_erkundung --autoplay=test_alarm_orig" },
  @{ name = "test_script_systems"; args = "--headless -- --mission=a1_blizzard --autoplay=test_script_systems" },
  @{ name = "test_commands_orig"; args = "--headless -- --mission=a1_blizzard --autoplay=test_commands_orig" },
  @{ name = "test_sp_weapons"; args = "--headless -- --mission=a1_blizzard --autoplay=test_sp_weapons" },
  @{ name = "test_aim_ballistics"; args = "--headless -- --mission=a1_blizzard --autoplay=test_aim_ballistics" },   # 0.10.1 Visier/Ballistik/Muendungsfeuer/Atem
  @{ name = "test_a2";       args = "--headless -- --mission=a2_erkundung --autoplay=test_orig_part --commandos=1" },
  @{ name = "test_a2_interaktiv"; args = "--headless -- --mission=a2_erkundung --autoplay=test_a2" },
  @{ name = "test_a3";       args = "--headless -- --mission=a3_rendezvous --autoplay=test_orig_part --commandos=4" },
  @{ name = "test_sas";      args = "--headless -- --autoplay=test_sas" },
  @{ name = "test_ui_flow";  args = "--headless -- --autoplay=test_ui_flow --profiles_dir=user://test_ui_flow --noimport" },
  @{ name = "test_language"; args = "--headless -- --autoplay=test_language --profiles_dir=user://test_language --noimport" },
  @{ name = "test_b022b";    args = "--headless -- --autoplay=test_b022b --profiles_dir=user://test_b022b --noimport" },
  @{ name = "test_tactical"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_tactical" },
  @{ name = "test_movies";   args = "--headless -- --autoplay=test_movies --profiles_dir=user://test_movies --noimport" },
  @{ name = "test_movie_skip"; args = "--headless -- --autoplay=test_movie_skip --profiles_dir=user://test_movie_skip --noimport" },
  @{ name = "test_interactive"; args = "--headless -- --mission=a1_blizzard --autoplay=test_interactive" },
  # Zweiprozessig: startet den Client (test_normandie_doors_client) selbst
  @{ name = "test_normandie_doors"; args = "--headless -- --autoplay=test_normandie_doors"; mp = $true },
  # B-017: Türflügel/Zäune/Wasser/Zielmarker (echte Benutzen-/Vorwärtstaste)
  @{ name = "test_b017_af1"; args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_b017 --phase=doors" },
  @{ name = "test_b017_no2"; args = "--headless -- --mission=no2_schwerttaenzer --autoplay=test_b017 --phase=doors" },
  @{ name = "test_b017_arctic"; args = "--headless -- --mission=a1_blizzard --autoplay=test_b017 --phase=arctic" },
  @{ name = "test_arctic2_licht"; args = "--headless -- --mission=a2_erkundung --autoplay=test_arctic2_licht" },
  @{ name = "test_b017_mp"; args = "--headless -- --autoplay=test_b017 --phase=mp_markers"; mp = $true },
  @{ name = "test_no2_final"; args = "--headless -- --mission=no2_schwerttaenzer --autoplay=test_no2_final --test_timeout=900"; timeout = 1200 },
  @{ name = "test_af6";     args = "--headless -- --mission=af6_raubvoegel --autoplay=test_af6" },
  @{ name = "test_af1_finale"; args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_af1_finale" },
  @{ name = "test_af_air";   args = "--headless -- --mission=af2_flugschau --autoplay=test_af_air" },
  @{ name = "test_items";    args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_items" },
  @{ name = "test_vehicle_types"; args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_vehicle_types"; timeout = 2400 },
  @{ name = "test_tank";     args = "--headless -- --mission=af1_spaghetti_airport --autoplay=test_tank" },
  @{ name = "test_water";    args = "--headless -- --mission=nw1_dampfleitung --autoplay=test_water" },
  @{ name = "test_orig_vehicles_cz1"; args = "--headless -- --mission=cz1_eintrittsgeld --autoplay=test_orig_vehicles" },
  @{ name = "test_orig_vehicles_nw1"; args = "--headless -- --mission=nw1_dampfleitung --autoplay=test_orig_vehicles" },
  @{ name = "test_cz2_parts"; args = "--headless -- --mission=cz4_volksfest --autoplay=test_cz2_parts" },
  @{ name = "test_controls"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_controls" },
  @{ name = "test_commands"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_commands" },
  @{ name = "test_follow_spacing"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_follow_spacing" },
  @{ name = "test_surrender"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_surrender" },
  @{ name = "test_blood";    args = "--headless -- --mission=m01_funkfeuer --autoplay=test_blood --profiles_dir=user://test_blut" },
  @{ name = "test_weapons_orig"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_weapons_orig" },
  @{ name = "test_animations"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_animations" },
  @{ name = "test_ragdoll";  args = "--headless -- --mission=m01_funkfeuer --autoplay=test_ragdoll" },
  @{ name = "test_b045";     args = "--headless -- --mission=m01_funkfeuer --autoplay=test_b045" },
  @{ name = "test_b041";     args = "--headless -- --mission=a2_erkundung --autoplay=test_b041 --phase=classic" },
  @{ name = "test_b041_neu"; args = "--headless -- --mission=a2_erkundung --autoplay=test_b041 --phase=neu --view_mode=1" },
  @{ name = "probe_normandy3"; args = "-- --autoplay=probe_normandy3 --resolution 1280x720"; timeout = 1700; mp = $true },
  @{ name = "test_b050";     args = "--headless -- --autoplay=test_b050 --shots=0 --missions=af1_spaghetti_airport,bu1_ameisenhuegel --profiles_dir=user://test_b050"; timeout = 1500 },
  @{ name = "test_tools_mines"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_tools_mines" },
  @{ name = "test_tools_mines_mp"; args = "--headless -- --autoplay=test_tools_mines --phase=mp"; mp = $true },
  # test_inventory: sp + mp (zweiprozessig mit test_inventory_client)
  @{ name = "test_inventory"; args = "--headless -- --mission=m01_funkfeuer --autoplay=test_inventory --phase=all"; mp = $true },
  @{ name = "test_net";      args = "--headless -- --autoplay=test_net"; mp = $true },
  @{ name = "test_mp_modes"; args = "--headless -- --autoplay=test_mp_modes"; mp = $true },
  # B-009, MP-Bots zurückgestellt ([D] 24.10.2026): test_bots vorerst nicht Teil der Gesamtsuite
  # 06.11.2026 (abschluss_099): im -Full-Lauf wieder dabei – BotGoals/BotBrain-Kartenhinweise prüfen
@{ name = "test_bots";     args = "--headless -- --autoplay=test_bots"; mp = $true; group = "full"; timeout = 2400 },   # nav-Phase über alle MP-Karten > 15 min
  @{ name = "test_lan_e2e";  args = "--headless -- --autoplay=test_lan_e2e --profiles_dir=user://test_lan_host --noimport"; mp = $true },
  @{ name = "test_mp_features"; args = "--headless -- --autoplay=test_mp_features --profiles_dir=user://test_mp_features --noimport"; mp = $true },
  @{ name = "test_mp_weapons"; args = "--headless -- --autoplay=test_mp_weapons --phase=all"; mp = $true },
  @{ name = "test_dedicated"; args = "--headless -- --autoplay=test_dedicated --profiles_dir=user://test_ded --noimport"; mp = $true },
  @{ name = "test_mp_setup_ui"; args = "--headless -- --autoplay=test_mp_setup_ui --profiles_dir=user://test_mp_setup --noimport"; mp = $true },
  @{ name = "test_mp_feedback"; args = "--headless -- --autoplay=test_mp_feedback"; mp = $true },
  @{ name = "test_support_strike"; args = "--headless -- --autoplay=test_support_strike"; mp = $true },
  @{ name = "test_net_authority"; args = "--headless -- --autoplay=test_net_authority"; mp = $true },
  # B-029: Coop-Stil (zweiprozessig mit test_mp_coop_client)
  @{ name = "test_mp_coop"; args = "--headless -- --autoplay=test_mp_coop"; mp = $true },
  # --- Gruppe "full" (nur mit -Full): lange Läufe ---
  @{ name = "test_stairs";   args = "--headless -- --autoplay=test_stairs --maps=all"; group = "full"; timeout = 3600 },
  @{ name = "test_mp_nav";   args = "--headless -- --autoplay=test_mp_nav --maps=mp"; group = "full"; timeout = 3600 },
  @{ name = "test_a1_collision"; args = "--headless -- --mission=a1_blizzard --autoplay=test_a1_collision"; group = "full"; timeout = 2400 },
  @{ name = "test_orig_complete_a1"; args = "--headless -- --mission=a1_blizzard --autoplay=test_orig_complete"; group = "full"; timeout = 3600 }
)
# Lokale Zusatzinhalte (Ordner local/, nicht im Repository) können eigene Suiten anhängen: $suites += @{ ... }
if (Test-Path "$proj\local\local_tests.ps1") { . "$proj\local\local_tests.ps1" }
# Zweiprozessige Suiten ohne mp-Kennzeichen (z. B. aus local_tests.ps1) am Namen erkennen
foreach ($s in $suites) {
  if (-not $s.ContainsKey("mp")) { $s.mp = ($s.name -match '(^test_net|_mp|mp_|lan_|dedicated|integration)') }
}
if (-not $Full) { $suites = @($suites | Where-Object { $_.group -ne "full" }) }
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File übergibt "a,b" als einen String
if ($Only.Count -gt 0) { $suites = @($suites | Where-Object { $Only -contains $_.name }) }
$Exclude = @($Exclude | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -Exclude test_mp_coop: Suiten auslassen
if ($Exclude.Count -gt 0) { $suites = @($suites | Where-Object { $Exclude -notcontains $_.name }) }

$lockName = "run_tests"
if (-not $Exe) {
  # Import aktualisiert u. a. die globale class_name-Registrierung neuer Skripte (auch unter der Sperre)
  $slots = Get-TestSlots -Proj $proj -Name $lockName -Count 1
  try { Invoke-GodotSuite -Proj $proj -GodotArgs "--headless --import" -Log "$proj\test_output\import.log" -TimeoutSec 1800 -Slots $slots | Out-Null }
  finally { Release-TestSlots -Slots $slots -Name $lockName }
}

$rows = @()
foreach ($s in $suites) {
  $log = "$proj\test_output\$($s.name).log"
  $limit = if ($s.timeout) { [int]$s.timeout } else { $TimeoutSec }
  $slots = Get-TestSlots -Proj $proj -Name $lockName -Count ($(if ($s.mp) { 2 } else { 1 }))
  try { $r = Invoke-GodotSuite -Proj $proj -GodotArgs $s.args -Log $log -TimeoutSec $limit -Slots $slots -Exe $Exe }
  finally { Release-TestSlots -Slots $slots -Name $lockName }
  $res = Read-SuiteResult -Log $log -Code $r.code -TimedOut $r.timeout
  "{0,-24} Exit {1,-3} {2,5}s  {3}" -f $s.name, $r.code, $r.seconds, $res.summary
  if (-not $res.ok) { "    -> FEHLER: $($res.reason)" }
  Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^FAIL|SCRIPT ERROR' } |
    Select-Object -First 10 | ForEach-Object { "    $_" }
  $rows += [pscustomobject]@{ Suite = $s.name; Ergebnis = $(if ($res.ok) { "OK" } else { "FEHLER ($($res.reason))" });
    Dauer = "{0}:{1:00}" -f [int][math]::Floor($r.seconds / 60), ($r.seconds % 60); Fehler = $res.fails }
}
""
"ZUSAMMENFASSUNG"
$rows | Format-Table -AutoSize | Out-String -Width 200
$rows | Export-Csv "$proj\test_output\run_tests_summary.csv" -NoTypeInformation -Encoding UTF8
$failed = @($rows | Where-Object { $_.Ergebnis -ne "OK" }).Count
if ($failed -gt 0) { "FEHLGESCHLAGEN: $failed von $($rows.Count) Suite(s)"; exit 1 } else { "ALLE $($rows.Count) TESTS BESTANDEN"; exit 0 }
