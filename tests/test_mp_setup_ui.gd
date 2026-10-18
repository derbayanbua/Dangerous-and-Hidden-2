extends "res://tests/lan_ui_base.gd"
## SPIELER-SETUP während einer laufenden Runde (zwei Prozesse, Vorgabe Auftraggeber 16.10.2026):
## Server (kopflos, dieser Prozess) + Client im FENSTER 1280×720 (tests/test_mp_setup_ui_client.gd), der über echte
## Eingabeereignisse (Input.parse_input_event: Esc, Mausklicks an Bildschirmpositionen) Pausenmenü → SPIELER-SETUP →
## Seite/Klasse/Figur → AKZEPTIEREN bedient. Geprüft: kein Schuss fällt, Maus bleibt frei, Auswahl kommt beim
## Server an; Kontrollbilder test_output/mp_setup_ingame_*.png.
##   tools\godot.cmd --headless -- --autoplay=test_mp_setup_ui --profiles_dir=user://test_mp_setup --noimport

const RESULT := "user://mp_setup_ui_result.txt"
const SPORT := 11081


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(10)
	Net.local_name = "Host"
	var ok := Net.host({"name": "Setup-UI", "map": "mp_arctic2_mp", "mode": Net.Mode.DEATHMATCH, "max_players": 8,
		"time_limit_min": 0, "score_limit": 0, "respawn_s": 5, "port": SPORT, "warmup_s": 0, "bots_per_team": 0})
	check(ok, "Server gestartet", Net.last_error)
	var loaded := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(1)
	check(await wait_for(loaded, 400.0), "Karte geladen")
	var exe := OS.get_executable_path()
	var args: Array = ["--resolution", "1280x720", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_setup_ui_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--", "--autoplay=test_mp_setup_ui_client", "--profiles_dir=user://test_mp_setup_client", "--noimport",
		"--setup_port=%d" % SPORT]
	var pid := OS.create_process(exe, args)
	check(pid > 0, "Client-Prozess (Fenster) gestartet")
	var cid := [0]
	var joined := func() -> bool:
		for k in Net.players:
			if int(k) > 1 and Net._soldiers.has(k):
				cid[0] = int(k)
				return true
		return false
	check(await wait_for(joined, 600.0), "Client beigetreten")
	# Auswahl des Clients (Klasse MG-Schütze) kommt beim Server an
	var chosen := func() -> bool: return cid[0] != 0 and Net.players.has(cid[0]) and int(Net.players[cid[0]].get("cls", -1)) == 0
	check(await wait_for(chosen, 600.0), "Server: Klasse aus dem SPIELER-SETUP im Spiel übernommen")
	# Einzel-Ausrüstung: vom Server geprüft und gespeichert; Wiedereinstieg rüstet genau damit aus
	var has_lo := func() -> bool: return cid[0] != 0 and Net.players.has(cid[0]) and not (Net.players[cid[0]].get("loadout", {}) as Dictionary).is_empty()
	check(await wait_for(has_lo, 300.0), "Server: Einzel-Ausrüstung geprüft und übernommen")
	if has_lo.call():
		var lo: Dictionary = Net.players[cid[0]]["loadout"]
		check(Net.loadout_error(cid[0], lo) == "", "Server: Prüfung (Lager der Karte, Traglast, Plätze) bestanden")
		# Server-Prüfung lehnt Unerlaubtes ab (Gegenstand der Gegenseite / überladen)
		var bad := lo.duplicate(true)
		SAS.add_item(bad, 26, 1)          # MP 44 (Achse) – nicht im Lager der Alliierten bzw. außerhalb des Lagers
		var bad2 := lo.duplicate(true)
		SAS.add_item(bad2, 54, 60)
		check(Net.loadout_error(cid[0], bad) != "" and Net.loadout_error(cid[0], bad2) != "", "Server: unerlaubte/überladene Ausrüstung abgelehnt",
			"%s | %s" % [Net.loadout_error(cid[0], bad), Net.loadout_error(cid[0], bad2)])
		await get_tree().create_timer(20.0).timeout     # Client schließt erst Setup/Pausenmenü (Prüfungen dort)
		var old: Soldier = Net._soldiers.get(cid[0])
		var again := func() -> bool:
			var s2 = Net._soldiers.get(cid[0])
			return is_instance_valid(s2) and s2 != old and s2.alive
		if is_instance_valid(old):
			old.set_meta("protect_until", 0)
			old.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
		check(await wait_for(again, 120.0), "Server: Client wieder eingestiegen")
		if again.call():
			var s3: Soldier = Net._soldiers[cid[0]]
			var want: Array = SAS.to_loadout(lo)["items"]
			var got: Array = s3.get_meta("orig_items", [])
			var same := want.size() == got.size()
			for x in want:
				if want.count(x) != got.count(x):
					same = false
			check(s3.has_meta("mp_loadout") and same, "Server: Soldat genau mit der gewählten Ausrüstung", "%s / %s" % [str(want), str(got)])
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)
	if OS.is_process_running(pid):
		await get_tree().create_timer(5.0).timeout
		if OS.is_process_running(pid):
			OS.kill(pid)
	_finish()
