extends "res://tests/test_gameplay.gd"
## Mehrspieler LAN (Server-Seite): startet einen Server (Arena auf der Arctic-1A-Karte) und einen zweiten,
## kopflosen Spielprozess als Client (tests/test_net_client.gd), der den Server per LAN-Suche findet,
## beitritt und läuft. Prüft Beitritt, Positionsabgleich, Server-Treffer → Tod/Punkte, Wiedereinstieg und
## übernimmt die Prüfergebnisse des Clients.
##   tools\godot.cmd --headless -- --autoplay=test_net

const RESULT := "user://net_client_result.txt"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(5)
	Net.local_name = "Host"
	# Server über das LAN-Menü erstellen (wie ein Spieler)
	var menu := get_tree().current_scene
	menu.open_lan()
	await frames(3)
	var lm: LanMenu = menu.lan_menu
	check(lm != null and lm._map.item_count >= 20, "LAN-Menü mit Kartenliste (Arena-Karten)", str(lm._map.item_count) if lm else "-")
	var idx := 0
	for i in lm._map.item_count:
		if lm._map.get_item_metadata(i) == "mp_arena_a1_blizzard":
			idx = i
	lm._map.select(idx)
	lm._mode.select(0)
	lm._time.value = 0
	lm._score.value = 0
	lm._respawn.value = 5          # Original-Menübereich 5–99
	lm._warm.value = 0             # ohne Aufwärmphase (eigene Prüfung in test_mp_features)
	lm._name_edit.text = "Testserver"
	for i in lm._voice.item_count:
		if lm._voice.get_item_id(i) == 7:
			lm._voice.select(i)          # Voice-Chat „CODEC - 64.0 Kbps“ (T2887)
	Net.local_name = "Host"          # open_lan() übernimmt sonst den Profilnamen
	lm._host()
	var ok := Net.is_online
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
	var clog := ProjectSettings.globalize_path("res://test_output/net_client.log")
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog, ] + _project_args() + ["--",
		"--autoplay=test_net_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:       # Client startet und lädt die Karte (unter Last mehrere Minuten)
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
	Net.send_chat("Hallo Gast")
	var chat := func() -> bool: return Net.chat_log.any(func(e): return String(e["name"]) == "Gast" and String(e["text"]) == "Hallo Host")
	var vt0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - vt0 < 120000 and not (chat.call() and Net.voice.frames_received > 0):
		await get_tree().create_timer(0.25).timeout
	check(chat.call(), "Chat des Clients beim Server angekommen")
	check(Net.voice.frames_received > 0 and Net.voice.last_speaker == "Gast" and Net.voice.last_level > 0.3,
		"Voice-Chat: Sprachpaket des Clients (μ-law 64 kbps) empfangen", "%d / %.2f" % [Net.voice.frames_received, Net.voice.last_level])
	# Bewegung: an das Ereignis gekoppelt (Client läuft, bis er getroffen wird) statt fester Wartezeit
	var p0 := puppet.global_position
	var moved := func() -> bool: return is_instance_valid(puppet) and puppet.global_position.distance_to(p0) > 1.0
	check(await _wait(moved, 120.0), "Bewegung des Clients kommt an",
		"%.1f m" % puppet.global_position.distance_to(p0))
	# Netzfigur auf dem Server: Original-Trefferzonen an den Gelenken der Figur (humanzones.4ds, re_notes_weapons §10a)
	if is_instance_valid(puppet) and puppet.model and puppet.model.orig_figure:
		var zn: Array = puppet.model.orig_zones
		var active := zn.filter(func(h): return is_instance_valid(h) and h.collision_layer != 0).size()
		check(zn.size() == 10 and active == 10, "Netzfigur: 10 Trefferzonen an den Gelenken der Original-Figur", "%d/%d" % [active, zn.size()])
	# Server-Treffer: Host tötet den Client
	puppet.set_meta("protect_until", 0)
	puppet.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
	await frames(5)
	check(not puppet.alive and int(Net.players[1]["kills"]) == 1 and int(Net.players[cid]["deaths"]) == 1,
		"Treffer auf dem Server: Tod, Frag und Tod gezählt", str(Net.players))
	# Wiedereinstieg: nach 5 s „FEUER DRÜCKEN FÜR RESPAWN“, ohne Feuer automatisch nach weiteren 3 s (Client drückt nicht)
	var t_kill := Time.get_ticks_msec()
	var resp := func() -> bool:
		var s2: Soldier = Net._soldiers.get(cid)
		return is_instance_valid(s2) and s2.alive and s2 != puppet
	check(await _wait(resp, 120.0), "Wiedereinstieg (Respawn-Zeit 5 s + 3 s ohne Feuertaste)")
	check(Time.get_ticks_msec() - t_kill >= 7500, "Automatischer Wiedereinstieg erst nach Respawn-Zeit + 3 s (Original)",
		"%d ms" % (Time.get_ticks_msec() - t_kill))
	check(Net.board_text().contains("Host") and Net.board_text().contains("Gast"), "Punktetabelle")
	# Fahrzeug-Abgleich: der Host fährt (Fahrphysik), der Client erhält Sitz und Lage (kinematisch geglättet)
	var car := net_test_car(m)
	await get_tree().create_timer(1.0).timeout
	var drv: Soldier = Net._soldiers.get(1)
	check(is_instance_valid(drv) and car.board(drv, true) and drv.seat_index == 0, "Host steigt als Fahrer ins Testfahrzeug")
	var c0 := car.global_position
	Input.action_press("move_forward")
	Input.action_press("move_left")
	# Ergebnisse des Clients abwarten (der Host fährt währenddessen im Kreis)
	t0 = Time.get_ticks_msec()
	var maxd := 0.0
	while Time.get_ticks_msec() - t0 < 240000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
		maxd = maxf(maxd, car.global_position.distance_to(c0))
	Input.action_release("move_forward")
	Input.action_release("move_left")
	check(maxd > 3.0, "Host fährt das Testfahrzeug", "max. %.1f m vom Start" % maxd)
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)            # Client wartet darauf (Verbindung beendet) und beendet sich dann selbst
	_finish()


## Testfahrzeug an derselben Stelle auf Server und Client (gleicher Knotenpfad für Net._veh/_seat)
static func net_test_car(m: Node) -> Vehicle:
	var sp: Array = m.mp_spawns()
	var p: Vector3 = sp[0]["pos"]
	return (m as Mission).spawn_vehicle(p + Vector3(4.0, 0.6, 4.0), 0.0, "net_test_car")


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _wait_mission() -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:          # Hintergrundladen: an das Ereignis gekoppelt, nicht an Bildzahlen
		await get_tree().process_frame
		var m := Game.current_mission()
		if m and m.squad and m.is_node_ready():
			return m
	return null


## Exportierter Build (Spieltest): kein Projektpfad – die EXE startet sich selbst; im Editor-Binary: --path
func _project_args() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	if OS.has_feature("template"):
		return []
	return ["--path", ProjectSettings.globalize_path("res://")]
