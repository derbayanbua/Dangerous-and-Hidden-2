extends Node
## Mehrspieler-Client für test_inventory (zweiter Prozess): tritt dem Server bei, durchsucht eine vom Server
## erzeugte Bot-Leiche über das Ingame-Inventar (zwei Inventare) und nimmt Waffe und Munition. Die Aktion geht
## als Anfrage an den Server (Net._inv_req), der Stand kommt zurück (Net._inv_state). Ergebnisse nach
## user://inv_client_result.txt (liest test_inventory).

var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	Net.join("127.0.0.1", int(Game.cli.get("port", Net.PORT)), "")
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
	var corpse: Soldier = null
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and corpse == null:
		await get_tree().create_timer(0.2).timeout
		for id in Net._soldiers:
			var s: Soldier = Net._soldiers[id]
			if int(id) < 0 and is_instance_valid(s) and not s.alive:
				corpse = s
	check(corpse != null, "Bot-Leiche beim Client (Tod vom Server)")
	if corpse == null:
		_done()
		return
	# der Server legt die Bot-Leiche neben den Client; nur bei zu großem Abstand heranrücken
	var d0 := me.global_position.distance_to(corpse.global_position)
	print("INV-CLIENT: Abstand zur Leiche %.1f m" % d0)
	if d0 > 2.2:
		me.global_position = corpse.global_position + Vector3(0.8, 0.3, 0.0)
		me.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(me) or not me.alive:
		me = Net._soldiers.get(Net.my_id())
		print("INV-CLIENT: eigener Soldat ersetzt/gestorben")
	check(is_instance_valid(me) and me.alive, "Eigener Soldat lebt vor dem Durchsuchen")
	if not is_instance_valid(me) or not me.alive:
		_done()
		return
	var spot := corpse.get_node_or_null("SearchSpot") as Interactable
	check(spot != null and spot.can_interact(me), "Leiche durchsuchbar (Suchen & Mun. sammeln T7043)")
	var ui: IngameInventory = m.controller.inventory
	# echte Benutzen-Taste F (Ereignis über den Viewport), Blick auf die Leiche
	for i in 20:
		var to := corpse.global_position + Vector3.UP * 0.4 - me.eye_position()
		me.look_yaw = atan2(-to.x, -to.z)
		await get_tree().physics_frame
	var it = m.controller.interact_target
	check(it is FieldInventory.SearchSpot, "Leiche ist Benutzen-Ziel", str(it.get("prompt")) if it else "kein Ziel")
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		ev.keycode = KEY_F
		ev.pressed = down
		get_viewport().push_input(ev)
		for k in 3:
			await get_tree().physics_frame
	check(ui.is_open() and ui.other == corpse, "Taste F öffnet die Ansicht mit zwei Inventaren")
	if not ui.is_open():
		FieldInventory.open_search(me, corpse)     # Ersatz, damit die übrigen Prüfungen laufen
	var bw := int(FieldInventory.view(corpse)["hands"])
	check(bw >= 0, "Waffe der Leiche sichtbar", str(bw))
	ui.move_item("other", "hands", bw, "own", "hands")
	var got := func() -> bool: return _me_has(bw)
	check(await _wait(got, 60.0), "Waffe aus der Leiche in der Hand (vom Server bestätigt)")
	check(int(FieldInventory.view(corpse)["hands"]) != bw, "Leiche beim Client ohne die Waffe (Server-Stand)")
	var am := SAS.ammo_of(bw)
	var n: int = SAS.count_of(FieldInventory.view(corpse), am) if am >= 0 and is_instance_valid(corpse) else 0
	if n > 0 and _me_has(bw):
		var r0: int = _me().current_weapon().reserve
		ui.move_item("other", "items", am, "own", "items")
		var ammo := func() -> bool: return _me_has(bw) and _me().current_weapon().reserve > r0
		check(await _wait(ammo, 60.0), "Munition aus der Leiche übernommen (Server)", "%d Magazine" % n)
		check(is_instance_valid(corpse) and SAS.count_of(FieldInventory.view(corpse), am) == 0, "Leiche ohne Magazine (Server-Stand)")
	ui.close()
	check(not ui.is_open(), "Inventar geschlossen")
	_done()


func _me() -> Soldier:
	return Net._soldiers.get(Net.my_id())


func _me_has(item: int) -> bool:
	var s := _me()
	return is_instance_valid(s) and s.current_weapon() != null and OrigHud.weapon_item(s.current_weapon(), s.team) == item


var _quitting := false


func _done() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://inv_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	var t0 := Time.get_ticks_msec()
	while Net.is_online and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(0.5).timeout
	Net.leave(false)
	get_tree().quit()
