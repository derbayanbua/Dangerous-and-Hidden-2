extends Node
## B-022 Serverautorität (Client-Seite, von test_net_authority als zweiter Prozess gestartet): erst legitim spielen,
## dann als manipulierter Client unzulässige RPCs direkt an den Server senden. Ergebnisse nach
## user://net_authority_client_result.txt.

var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	var ip := ""
	if Net.start_browse():
		for i in 100:
			await get_tree().create_timer(0.1).timeout
			if not Net.servers.is_empty():
				ip = String(Net.servers.values()[0]["ip"])
				break
	Net.stop_browse()
	Net.join(ip if ip != "" else "127.0.0.1", Net.PORT, "")
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		m = Game.current_mission()
		if m and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1):
			break
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(is_instance_valid(me) and me.alive, "Eigener Soldat vom Server erzeugt")
	if not is_instance_valid(me):
		_done()
		return
	await get_tree().create_timer(2.0).timeout
	# --- legitim: laufen und mit der eigenen Waffe in Blickrichtung schießen ---
	Input.action_press("move_forward")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("move_forward")
	var w := me.current_weapon()
	for i in 3:
		if w and w.in_mag > 0:
			me._fire_shot(w)
			w.in_mag -= 1
		await get_tree().create_timer(0.5).timeout
	check(Net.pos_fixes == 0, "Legitimes Laufen: keine Rücksetzung durch den Server", str(Net.pos_fixes))
	Net.send_chat("LEGIT_DONE")
	# auf das Fahrzeug des Hosts warten
	var host: Soldier = Net._soldiers.get(1)
	var car: Vehicle = load("res://tests/test_net.gd").net_test_car(m)
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 120000 and not (is_instance_valid(host) and host.vehicle == car):
		await get_tree().create_timer(0.2).timeout
	check(is_instance_valid(host) and host.vehicle == car, "Host sitzt am Steuer (Sitzabgleich über den Server)")
	var cpath := String(car.get_path())
	var eye := me.eye_position()
	var look := me.aim_direction()
	var own := String(w.data.id) if w else ""
	# F-001: fremdes Fahrzeug lenken
	for i in 5:
		Net._veh.rpc_id(1, cpath, Transform3D(Basis(), car.global_position + Vector3(0, 30, 0)), Vector3.ZERO)
		await get_tree().create_timer(0.05).timeout
	# F-002/F-006: unbekannte Waffen-ID, fremde Waffe, Startpunkt, Richtung, Kadenz
	Net._act.rpc_id(1, "shot", eye, look, "gibtsnicht")
	Net._act.rpc_id(1, "grenade", eye, look * 10.0, "gibtsnicht")
	var foreign := ""
	for id in WeaponDB.all_ids():
		var owned := false
		for ww in me.weapons:
			if ww and String(ww.data.id) == String(id):
				owned = true
		if not owned and WeaponDB.get_weapon(StringName(id)) != null:
			foreign = String(id)
			break
	Net._act.rpc_id(1, "shot", eye, look, foreign)
	await get_tree().create_timer(0.6).timeout
	Net._act.rpc_id(1, "shot", eye + Vector3(40, 0, 0), look, own)
	await get_tree().create_timer(0.6).timeout
	Net._act.rpc_id(1, "shot", eye, -look, own)
	await get_tree().create_timer(0.6).timeout
	for i in 40:
		Net._act.rpc_id(1, "shot", eye, look, own)
	# F-004: Benutzen aus der Ferne
	var far: Node3D = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Node3D and (n as Node3D).global_position.distance_to(me.global_position) > 20.0 \
				and n.get("persistent_id") != null and String(n.get("persistent_id")) != "":
			far = n
			break
	if far:
		Net._use.rpc_id(1, String(far.get("persistent_id")))
	else:
		Net.send_chat("USE_SKIP")
	# F-005: ungültiger und belegter Sitz
	Net._seat.rpc_id(1, cpath, 99)
	await get_tree().create_timer(0.3).timeout
	Net._seat.rpc_id(1, cpath, 0)
	await get_tree().create_timer(0.5).timeout
	check(me.vehicle == null, "F-005 Server setzt den Sitzwunsch zurück (nicht eingestiegen)")
	# F-003: Teleport (Lage wird verworfen, Server setzt zurück); F-009: negativer Waffenplatz
	var p_before := me.global_position
	Net._st.rpc_id(1, me.global_position + Vector3(200, 0, 200), Vector3.ZERO, me.look_yaw, me.look_pitch, 0, -1, false)
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 10000 and Net.pos_fixes == 0:
		await get_tree().create_timer(0.1).timeout
	check(Net.pos_fixes > 0, "F-003 Server meldet Rücksetzung der Lage", str(Net.pos_fixes))
	check(me.global_position.distance_to(p_before) < 10.0, "F-003 eigene Figur bleibt an der Serverlage")
	# F-007: zweite Anmeldung
	Net._register.rpc_id(1, "Doppelt", "", Net.PROTOCOL, 77, -1)
	await get_tree().create_timer(1.0).timeout
	check(Net.is_online, "Verbindung bleibt nach verworfenen RPCs bestehen")
	await _b023(me, ip if ip != "" else "127.0.0.1")
	check(Net.is_online, "B-023: Verbindung bleibt nach allen Negativfällen bestehen")
	Net.send_chat("MANIP_DONE")
	_done()


## B-023 (M-001…M-006, M-028): weitere Manipulationen des Clients
func _b023(me: Soldier, ip: String) -> void:
	# M-001: Inventaranfrage mit gefälschtem eigenem Munitionsstand
	var fake := {"w": [], "med": 99}
	for i in me.weapons.size():
		if me.weapons[i]:
			fake["w"].append([i, String(me.weapons[i].data.id), 999, 999])
	var key := FieldInventory.key_of(me)
	Net._inv_req.rpc_id(1, {"src": key, "from": "x", "id": -1, "dst": key, "to": "y", "me": fake})
	await get_tree().create_timer(0.5).timeout
	# M-002: _client_ready erneut (Respawn/Heilung/Teleport erzwingen)
	Net._client_ready.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	# M-004: Admin-Login durchprobieren (Konsole, 1,1 s Abstand → unter der Flood-Grenze) → Sperre nach 3 Fehlversuchen
	for i in 4:
		Net.console_command("adminlogin admin falsch%d" % i)
		await get_tree().create_timer(1.1).timeout
	var locked := false
	for e in Net.chat_log:
		if String(e["text"]).contains("Too many failed logins"):
			locked = true
	check(locked, "M-004 Admin-Login nach 3 Fehlversuchen gesperrt (Antwort beim Client)")
	await get_tree().create_timer(3.5).timeout
	# M-004: „/“-Befehle unterliegen dem Flood-Schutz
	for i in 7:
		Net.send_chat("/listplayers")
	var tw := Time.get_ticks_msec()
	var flood := false
	while Time.get_ticks_msec() - tw < 5000 and not flood:
		await get_tree().create_timer(0.2).timeout
		for e in Net.chat_log:
			if String(e["text"]).contains("Nachricht nicht gesendet"):
				flood = true
	check(flood, "M-004 Flood-Schutz greift auch für „/“-Befehle")
	# M-006: Voice – Übergröße und Paketflut
	var big := PackedByteArray()
	big.resize(1000)
	Net.voice._vf.rpc_id(1, big)
	var ok := PackedByteArray()
	ok.resize(320)
	for i in 80:
		Net.voice._vf.rpc_id(1, ok)
	# M-005: Serverabfrage – kleine (ungepolsterte) Anfragen in Flut, Antwortgröße ≤ 3 × Anfrage
	var port := int(Net.settings.get("port", Net.PORT)) + 1
	var u := PacketPeerUDP.new()
	u.bind(0)
	u.set_dest_address(ip, port)
	var small := (Net.QUERY_TAG + " 1|x").to_utf8_buffer()
	for i in 20:
		u.put_packet(small)
	var got := 0
	var max_sz := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().create_timer(0.1).timeout
		while u.get_available_packet_count() > 0:
			var b := u.get_packet()
			got += 1
			max_sz = maxi(max_sz, b.size())
	check(got >= 1 and got <= int(Net.QUERY_BURST) + 2, "M-005 Abfrage-Flut je IP begrenzt", "%d von 20 beantwortet" % got)
	check(max_sz <= small.size() * Net.QUERY_AMP, "M-005 Antwort ≤ %d × Anfrage (kein Verstärker)" % Net.QUERY_AMP,
		"%d Byte auf %d Byte" % [max_sz, small.size()])
	await get_tree().create_timer(2.5).timeout
	var padded := (Net.QUERY_TAG + " 2|x" + " ".repeat(Net.QUERY_PAD)).to_utf8_buffer()
	u.put_packet(padded)
	var full := {}
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and full.is_empty():
		await get_tree().create_timer(0.1).timeout
		while u.get_available_packet_count() > 0:
			var d = JSON.parse_string(u.get_packet().get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY:
				full = d
	check(full.has("plist") and full.has("rules"), "M-005 aufgefüllte Abfrage (eigener Client) bekommt die volle Info", str(full.keys()))
	u.close()
	# M-003: zweite ENet-Verbindung ohne Anmeldung: RPC wird verworfen, Peer nach 10 s getrennt
	var mp2 := SceneMultiplayer.new()
	mp2.root_path = NodePath("/root")
	var p2 := ENetMultiplayerPeer.new()
	p2.create_client(ip, int(Net.settings.get("port", Net.PORT)))
	mp2.multiplayer_peer = p2
	var connected := false
	var sent := false
	var dropped := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
		mp2.poll()
		var stt := p2.get_connection_status()
		if stt == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			if not sent:
				sent = true
				mp2.rpc(1, Net, &"_client_ready", [])
				mp2.rpc(1, Net, &"_chat_req", ["GAST_OHNE_ANMELDUNG", false])
		elif connected and stt == MultiplayerPeer.CONNECTION_DISCONNECTED:
			dropped = true
			break
	check(connected, "M-003 zweite Verbindung (ohne Anmeldung) aufgebaut")
	check(dropped, "M-003 Peer ohne Anmeldung vom Server getrennt (≤ 10 s)")
	if p2.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		p2.close()
	# Flood-Stummschaltung ablaufen lassen, damit MANIP_DONE ankommt
	await get_tree().create_timer(maxf(0.0, 11.0 - (Time.get_ticks_msec() - tw) / 1000.0)).timeout


var _quitting := false


func _done() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://net_authority_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	var t0 := Time.get_ticks_msec()
	while Net.is_online and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(0.5).timeout
	Net.leave(false)
	get_tree().quit()
