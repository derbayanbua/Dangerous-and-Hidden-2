extends Node
## Client zu test_normandie_doors (zweiter Prozess): Beitritt, Türzustände des Servers übernommen (Spät-Beitritt),
## Server-Benutzung der Doppeltür kommt an, eigene Benutzung von H38_89 per Benutzen-Taste. Ergebnis nach
## user://normandie_doors_client.txt.

const T := preload("res://tests/test_normandie_doors.gd")
var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	print(lines[lines.size() - 1])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _tap(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		for i in 2:
			await get_tree().physics_frame


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	Net.join("127.0.0.1", Net.PORT, "")
	var ok := await _wait(func():
		var m = Game.current_mission()
		return m != null and m.is_node_ready() and Net._soldiers.has(Net.my_id()), 500.0)
	check(ok, "Beigetreten, Karte geladen")
	if not ok:
		_done()
		return
	var m: Mission = Game.current_mission()
	var it: OrigInteractive = m.get("interactive")
	var hd: OrigInteractive.OrigDoor = it.controls.get("H_DOOR_01")
	check(await _wait(func(): return hd.state == 0, 30.0), "Spät-Beitritt: H_door_01 wie beim Server zu (Original offen)", str(hd.state))
	var d45: OrigInteractive.OrigDoor = it.controls.get("M_BANKA_45")
	var d46: OrigInteractive.OrigDoor = it.controls.get("M_BANKA_46")
	check(await _wait(func(): return d45.state == 1 and d46.state == 1, 240.0), "Server öffnet Doppeltür → beide Flügel beim Client offen",
		"%d/%d" % [d45.state, d46.state])
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var d89: OrigInteractive.OrigDoor = it.controls.get("H38_89")
	var st := T.stand_for(m, d89)
	me.global_position = st[0]
	me.velocity = Vector3.ZERO
	T.face(me, st[1])
	for i in 6:
		await get_tree().physics_frame
	m.controller._update_interact_target()
	check(m.controller.interact_target == d89, "Client: H38_89 als Benutzen-Ziel",
		String(m.controller.interact_target.name) if m.controller.interact_target else "-")
	await _tap("interact")
	check(await _wait(func(): return d89.state == 1, 10.0), "Client öffnet H38_89 (Benutzen)")
	await get_tree().create_timer(4.0).timeout          # Server sieht die Tür offen
	m.controller._update_interact_target()
	await _tap("interact")
	check(await _wait(func(): return d89.state == 0, 10.0), "Client schließt H38_89")
	await get_tree().create_timer(4.0).timeout
	_done()


func _done() -> void:
	var f := FileAccess.open(T.RESULT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0)
