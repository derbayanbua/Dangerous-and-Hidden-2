extends "res://tests/test_gameplay.gd"
## Mehrspieler LAN (Server-Seite): startet einen Server (Arena auf der Arctic-1A-Karte) und einen zweiten,
## kopflosen Spielprozess als Client (tests/test_net_client.gd), der den Server per LAN-Suche findet,
## beitritt und läuft. Prüft Beitritt, Positionsabgleich, Server-Treffer → Tod/Punkte, Wiedereinstieg und
## übernimmt die Prüfergebnisse des Clients.
##   tools\godot.cmd --headless -- --autoplay=test_net

const RESULT := "user://net_client_result.txt"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(5)
	Net.local_name = "Host"
	var ok := Net.host({"name": "Testserver", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.DEATHMATCH,
		"max_players": 4, "time_limit_min": 0, "score_limit": 0, "respawn_s": 2, "password": "", "port": Net.PORT})
	check(ok and Net.is_online and multiplayer.is_server(), "Server gestartet (ENet, Port %d)" % Net.PORT, Net.last_error)
	var m := await _wait_mission()
	check(m != null and m.has_method("mp_spawns") and m.mp_spawns().size() >= 2, "Arena-Karte geladen, Spawnpunkte",
		str(m.mp_spawns().size()) if m else "-")
	await frames(30)
	var me: Soldier = Net._soldiers.get(1)
	check(is_instance_valid(me) and me.alive and m.squad.leader() == me, "Eigener Soldat des Servers erzeugt und gesteuert")
	check(m.enemies.is_empty(), "Keine KI-Gegner im Mehrspieler")
	# zweiten Prozess als Client starten
	var exe := OS.get_executable_path()
	var pid := OS.create_process(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--autoplay=test_net_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200000:       # Client startet und lädt die Karte (bis ~3 min)
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			if id != 1 and is_instance_valid(Net._soldiers[id]):
				cid = id
		if cid != 0:
			break
	check(cid != 0 and Net.players.size() == 2, "Client beigetreten und Soldat erzeugt", str(Net.players))
	if cid == 0:
		_finish()
		return
	var puppet: Soldier = Net._soldiers[cid]
	check(puppet.net_puppet, "Client-Soldat ist auf dem Server eine Netzfigur")
	var p0 := puppet.global_position
	await seconds(3.0)
	check(puppet.global_position.distance_to(p0) > 1.0, "Bewegung des Clients kommt an",
		"%.1f m" % puppet.global_position.distance_to(p0))
	# Server-Treffer: Host tötet den Client
	puppet.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
	await frames(5)
	check(not puppet.alive and int(Net.players[1]["kills"]) == 1 and int(Net.players[cid]["deaths"]) == 1,
		"Treffer auf dem Server: Tod, Frag und Tod gezählt", str(Net.players))
	await seconds(3.5)
	var again: Soldier = Net._soldiers.get(cid)
	check(is_instance_valid(again) and again.alive and again != puppet, "Wiedereinstieg nach 2 s")
	check(Net.board_text().contains("Host") and Net.board_text().contains("Gast"), "Punktetabelle")
	# Ergebnisse des Clients abwarten
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)
	_finish()


func _wait_mission() -> Node:
	for i in 3000:
		await get_tree().process_frame
		var m := Game.current_mission()
		if m and m.squad:
			return m
	return null
