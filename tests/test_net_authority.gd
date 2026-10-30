extends "res://tests/test_net.gd"
## B-022 F-001–F-009 Serverautorität (Server-Seite): Server mit Arena-Karte, zweiter kopfloser Prozess
## (tests/test_net_authority_client.gd) spielt erst legitim (Laufen, Schießen) und schickt dann manipulierte RPCs
## (fremdes Fahrzeug lenken, Schüsse mit unbekannter/fremder Waffe, von weit weg, zu schnell, Benutzen aus der
## Ferne, ungültiger/belegter Sitz, Teleport, negativer Waffenplatz, zweite Anmeldung). Der Server muss jede
## Manipulation verwerfen (Net.rejects) und darf legitimes Spiel nicht verwerfen.
##   tools\godot.cmd --headless -- --autoplay=test_net_authority

const RESULT_A := "user://net_authority_client_result.txt"


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_A))
	await frames(5)
	Net.local_name = "Host"
	var menu := get_tree().current_scene
	menu.open_lan()
	await frames(3)
	var lm: LanMenu = menu.lan_menu
	var idx := 0
	for i in lm._map.item_count:
		if lm._map.get_item_metadata(i) == "mp_arena_a1_blizzard":
			idx = i
	lm._map.select(idx)
	lm._mode.select(0)
	lm._time.value = 0
	lm._score.value = 0
	lm._respawn.value = 5
	lm._warm.value = 0
	lm._name_edit.text = "Autoritaet"
	Net.local_name = "Host"
	lm._host()
	check(Net.is_online and multiplayer.is_server(), "Server gestartet", Net.last_error)
	var m := await _wait_mission()
	check(m != null, "Arena-Karte geladen")
	if m == null:
		_finish()
		return
	await frames(30)
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/net_authority_client.log")
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog, ] + _project_args() + ["--",
		"--autoplay=test_net_authority_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			if id != 1 and is_instance_valid(Net._soldiers[id]):
				cid = id
		if cid != 0:
			break
	check(cid != 0, "Client beigetreten")
	if cid == 0:
		_finish()
		return
	var puppet: Soldier = Net._soldiers[cid]
	puppet.set_meta("protect_until", 0)
	var me: Soldier = Net._soldiers.get(1)
	me.set_meta("protect_until", 1 << 62)     # Host bleibt am Leben (manipulierte Schüsse)
	# Phase 1: legitimes Spiel des Clients (Laufen, Schießen) – nichts darf verworfen werden
	var p0 := puppet.global_position
	check(await _wait(func(): return _chat("LEGIT_DONE"), 300.0), "Client meldet: legitimes Spiel beendet")
	var legit: Array = Net.rejects.filter(func(r): return int(r["peer"]) == cid)
	check(legit.is_empty(), "Legitimes Laufen/Schießen: kein RPC verworfen", str(legit))
	# (Laufweite hängt vom Hindernis vor dem Spawn ab; entscheidend: Lage kommt an, keine Rücksetzung)
	check(is_instance_valid(puppet) and puppet.net_target.distance_to(p0) > 0.5, "Legitime Bewegung kommt an",
		"%.1f m" % (puppet.net_target.distance_to(p0) if is_instance_valid(puppet) else -1.0))
	check(int(puppet.get_meta("ammo_debt", 0)) == 0, "Legitime Schüsse: Server-Munitionsstand mitgeführt")
	# Host fährt das Testfahrzeug (Client darf es nicht lenken und nicht auf den Fahrersitz)
	var car := net_test_car(m)
	await get_tree().create_timer(1.0).timeout
	check(car.board(me, true) and me.seat_index == 0, "Host sitzt am Steuer")
	await get_tree().create_timer(1.0).timeout
	Net.send_chat("CAR_READY")
	var car_xf := car.global_transform
	var host_hp := me.health
	var slot0 := puppet.current_slot
	var pp0 := puppet.global_position
	check(await _wait(func(): return _chat("MANIP_DONE"), 300.0), "Client meldet: Manipulationen gesendet")
	await get_tree().create_timer(1.0).timeout
	var kinds := {}
	for r in Net.rejects:
		if int(r["peer"]) == cid:
			kinds[String(r["kind"])] = int(kinds.get(String(r["kind"]), 0)) + 1
	var whys := " | ".join(Net.rejects.filter(func(r): return int(r["peer"]) == cid).map(func(r): return "%s: %s" % [r["kind"], r["why"]]))
	print("NET-AUTH Verworfen: ", whys)
	var has_why := func(kind: String, part: String) -> bool:
		return Net.rejects.any(func(r): return int(r["peer"]) == cid and String(r["kind"]) == kind and String(r["why"]).contains(part))
	check(kinds.has("veh"), "F-001 Fahrzeuglage vom Nicht-Fahrer verworfen", str(kinds))
	check(car.global_transform.origin.distance_to(car_xf.origin) < 5.0, "F-001 Fahrzeug nicht vom Client versetzt",
		"%.1f m" % car.global_transform.origin.distance_to(car_xf.origin))
	check(has_why.call("shot", "unbekannte Waffe"), "F-002/F-006 Schuss mit unbekannter Waffen-ID verworfen (kein Absturz)")
	check(has_why.call("shot", "nicht im Besitz"), "F-002 Schuss mit fremder Waffe verworfen")
	check(has_why.call("shot", "Ursprung"), "F-002 Schuss mit falschem Startpunkt verworfen")
	check(has_why.call("shot", "neben dem Blick"), "F-002 Schuss entgegen der Blickrichtung verworfen")
	check(has_why.call("shot", "Feuerrate"), "F-002 Schnellfeuer über der Kadenz verworfen")
	check(has_why.call("shot", "keine Munition") or has_why.call("shot", "Feuerrate"), "F-002 Munition/Kadenz begrenzt")
	check(has_why.call("grenade", "unbekannte Waffe"), "F-006 Granate mit ungültiger ID verworfen")
	check(absf(me.health - host_hp) < 0.1, "Host durch manipulierte Schüsse nicht verletzt", "%.1f" % (me.health - host_hp))
	check(has_why.call("use", "außer Reichweite") or _chat("USE_SKIP"), "F-004 Benutzen aus der Ferne verworfen",
		"übersprungen (kein Objekt > 6 m)" if _chat("USE_SKIP") else "")
	check(has_why.call("seat", "ungültig"), "F-005 Sitzindex außerhalb verworfen")
	check(has_why.call("seat", "belegt"), "F-005 belegter Fahrersitz verworfen")
	check(car.driver() == me, "F-005 Host bleibt Fahrer")
	check(has_why.call("move", "waagrecht"), "F-003 Teleport verworfen")
	check(is_instance_valid(puppet) and puppet.net_target.distance_to(pp0) < 30.0, "F-003 Serverlage nicht teleportiert",
		"%.1f m" % puppet.net_target.distance_to(pp0) if is_instance_valid(puppet) else "-")
	check(is_instance_valid(puppet) and puppet.current_slot == slot0 and puppet.current_slot >= 0, "F-009 negativer Waffenplatz ignoriert")
	check(has_why.call("register", "doppelte"), "F-007 doppelte Anmeldung verworfen")
	check(Net.players.size() == 2 and String(Net.players[cid]["name"]) == "Gast", "F-007 Spielerdaten unverändert", str(Net.players.get(cid)))
	# Ergebnisse des Clients
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not FileAccess.file_exists(RESULT_A):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT_A) if FileAccess.file_exists(RESULT_A) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	car.leave(me)
	Net.leave(false)
	_finish()


func _chat(text: String) -> bool:
	return Net.chat_log.any(func(e): return String(e["name"]) == "Gast" and String(e["text"]) == text)
