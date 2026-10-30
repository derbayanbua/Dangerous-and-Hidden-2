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
	Net.send_chat("MANIP_DONE")
	_done()


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
