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
	var gen0 := int(Net._gen.get(cid, 0))
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
	await _b023_checks(cid, puppet, gen0, has_why)
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


## B-023 / M-028: Negativfälle M-001…M-008 (Client-Manipulationen aus test_net_authority_client + Serverbefehle direkt)
func _b023_checks(cid: int, puppet: Soldier, gen0: int, has_why: Callable) -> void:
	# M-001
	check(has_why.call("inv_req", "ignoriert"), "M-001 Client-Munitionsstand in _inv_req verworfen")
	var pumped := false
	if is_instance_valid(puppet):
		for w in puppet.weapons:
			if w and (w.in_mag >= 999 or w.reserve >= 999):
				pumped = true
	check(not pumped, "M-001 Server-Munition nicht vom Client aufgefüllt")
	check(is_instance_valid(puppet) and puppet.medkits < 99, "M-001 Verbandskästen nicht übernommen")
	# M-002
	check(has_why.call("client_ready", "wiederholt"), "M-002 wiederholtes _client_ready verworfen")
	check(int(Net._gen.get(cid, 0)) == gen0 and Net._soldiers.get(cid) == puppet, "M-002 kein Neu-Spawn (Generation unverändert)",
		"%d -> %d" % [gen0, int(Net._gen.get(cid, 0))])
	# M-003 (zweite Verbindung des Client-Prozesses ohne Anmeldung)
	var guest := func(kind: String, part: String) -> bool:
		return Net.rejects.any(func(r): return int(r["peer"]) != cid and int(r["peer"]) > 1 and String(r["kind"]) == kind \
			and String(r["why"]).contains(part))
	check(guest.call("client_ready", "nicht angemeldet"), "M-003 _client_ready ohne Anmeldung verworfen")
	check(guest.call("chat", "nicht angemeldet"), "M-003 Chat ohne Anmeldung verworfen")
	check(guest.call("peer", "getrennt"), "M-003 Peer ohne Anmeldung nach Zeitlimit getrennt")
	check(not _chat_any("GAST_OHNE_ANMELDUNG"), "M-003 Chat des Gastes nicht verteilt")
	check(Net.players.size() == 2, "M-003 kein Spieler für den Gast angelegt", str(Net.players.keys()))
	# M-004
	check(has_why.call("adminlogin", "falsches Passwort"), "M-004 Fehlversuche protokolliert (NET-AUTH)")
	check(has_why.call("adminlogin", "gesperrt"), "M-004 Admin-Login nach Fehlversuchen gesperrt")
	check(not bool(Net.players[cid].get("admin", false)), "M-004 kein Admin-Recht erlangt")
	# M-006
	check(has_why.call("voice", "Größe") or has_why.call("voice", "Voice am Server aus"), "M-006 übergroßes Sprachpaket verworfen")
	check(has_why.call("voice", "Rate") or has_why.call("voice", "Voice am Server aus"), "M-006 Sprachpaket-Flut gedrosselt",
		"verworfen %d" % Net.voice.dropped)
	# M-005 (Serverseite)
	check(Net.query_dropped > 0, "M-005 Abfrage-Flut serverseitig verworfen", str(Net.query_dropped))
	check(Net.query_reply("x", 13).size() <= 39, "M-005 Antwort auf 13-Byte-Anfrage ≤ 39 Byte")
	check(Net.query_reply("q".repeat(500), 2000).size() <= 6000 and String(JSON.parse_string(
		Net.query_reply("q".repeat(500), 2000).get_string_from_utf8()).get("qid", "")).length() <= Net.QUERY_QID_MAX, "M-005 qid gekürzt")
	# M-007/M-008: Admin aus dem Netz (Recht testweise gesetzt): exec nur im Konfigurationsordner, Rekursion begrenzt, kein quit
	var dir := ProjectSettings.globalize_path("user://test_b023_exec")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("self.cfg"), FileAccess.WRITE)
	f.store_string("exec self.cfg\n")
	f.close()
	Net.exec_dir_override = dir
	Net.players[cid]["admin"] = true
	var r1 := Net.server_command("exec ../../project.godot", cid)
	check(r1.contains("only file names") and has_why.call("exec", "unzulässiger Pfad"), "M-007 exec mit Pfad/„..“ abgelehnt", r1)
	var r2 := Net.server_command("exec " + ProjectSettings.globalize_path("res://project.godot"), cid)
	check(r2.contains("only file names"), "M-007 exec mit absolutem Pfad abgelehnt", r2.substr(0, 80))
	var r3 := Net.server_command("exec self.cfg", cid)
	check(has_why.call("exec", "Verschachtelung") and Net._exec_depth == 0, "M-007 rekursives exec begrenzt (kein Absturz)", r3.substr(0, 80))
	var r4 := Net.server_command("quit", cid)
	check(r4.contains("only allowed") and Net.is_online, "M-008 quit eines Netz-Admins abgelehnt", r4)
	var r5 := Net.server_command("quit", 1)
	check(r5.contains("only allowed") and Net.is_online, "M-008 quit auf nicht dediziertem Host abgelehnt", r5)
	Net.players[cid]["admin"] = false
	Net.exec_dir_override = ""
	# Bots/Host weiter im Spiel
	check(Net.is_online and Game.current_mission() != null, "Server läuft nach allen Negativfällen weiter")


func _chat_any(text: String) -> bool:
	return Net.chat_log.any(func(e): return String(e["text"]) == text)


func _chat(text: String) -> bool:
	return Net.chat_log.any(func(e): return String(e["name"]) == "Gast" and String(e["text"]) == text)
