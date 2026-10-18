extends Node
## Mehrspieler-Client zu test_tools_mines --phase=mp (zweiter Prozess): beitreten, Mine des Hosts in dessen Hand
## sehen, gelegte Mine beschießen; die Detonation kommt vom Server (eigene Treffer zählen auf dem Client nicht).
## Ergebnisse nach user://tools_mines_client_result.txt.

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
	Net.join("127.0.0.1", 11038, "")
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
	me.set_meta("protect_until", 0)
	await get_tree().create_timer(1.0).timeout
	Net.send_chat("bereit")
	# Host wählt die Mine: Netzfigur hat die Mine in der Hand
	var host_tool := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await get_tree().create_timer(0.1).timeout
		var h: Soldier = Net._soldiers.get(1)
		if is_instance_valid(h) and h.tool == "mine" and h.model and h.model.prop_name() != "":
			host_tool = true
			var wm: Node3D = h.model._weapon_mesh
			check(not (is_instance_valid(wm) and wm.visible), "Netzfigur des Hosts: Waffe weggesteckt")
			check(OrigWeapons.available() == false or h.model.prop_name() == "w_antiman",
				"Netzfigur des Hosts: Original-Mine w_antiman in der Hand", h.model.prop_name())
			break
	check(host_tool, "Netzfigur des Hosts zeigt das gewählte Hilfsmittel (Mine)")
	# gelegte Mine abwarten
	var mine: PlacedCharge = null
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000 and mine == null:
		await get_tree().create_timer(0.1).timeout
		var lst := get_tree().get_nodes_in_group("placed_charges")
		if not lst.is_empty():
			mine = lst[0]
	check(mine != null, "Mine des Hosts liegt auch beim Client")
	if mine == null:
		_done()
		return
	# 9 m entfernt hinstellen und auf die Mine schießen, bis sie detoniert
	var w := me.current_weapon()
	var booms0 := PlacedCharge.remote_booms
	var shots := 0
	t0 = Time.get_ticks_msec()
	var k := 0
	while Time.get_ticks_msec() - t0 < 90000 and is_instance_valid(mine) and not mine.is_done():
		# Schussposition mit freier Sicht auf die Mine (Gelände der Arena ist hügelig): Richtungen durchprobieren
		var ang := k * PI / 4.0
		k += 1
		var off := Vector3(-cos(ang), 0.0, sin(ang)) * 8.0
		var at := mine.global_position + off
		me.stance_request = Soldier.Stance.CROUCH      # Annäherungszünder: geduckt erst bei Berührung
		var gq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at + Vector3.DOWN * 6.0, 1, me.exclude_rids())
		var gh := me.get_world_3d().direct_space_state.intersect_ray(gq)
		if not gh.is_empty():
			at.y = (gh.position as Vector3).y
		me.global_position = at + Vector3.UP * 0.3
		me.velocity = Vector3.ZERO
		me.look_yaw = atan2(off.x, off.z)
		await get_tree().create_timer(1.5).timeout
		if not is_instance_valid(mine) or mine.is_done():
			break
		var q := PhysicsRayQueryParameters3D.create(me.eye_position(), mine.hit_area.global_position + Vector3.UP * 0.07, 1,
			me.exclude_rids())
		if not me.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue                  # Gelände dazwischen: nächste Richtung
		if not is_instance_valid(mine) or mine.is_done():
			break
		if w:
			w.in_mag = maxi(w.in_mag, 3)
			me.extra_spread = -1000.0
			me.has_aim_point = true
			me.aim_point = mine.hit_area.global_position + Vector3.UP * 0.07
			me._fire_shot(w)
			me.has_aim_point = false
			me.extra_spread = 0.0
			shots += 1
		await get_tree().create_timer(1.5).timeout
	check(shots >= 1, "Client schießt auf die Mine", "%d Schüsse" % shots)
	check(not is_instance_valid(mine) or mine.is_done(), "Client: Mine detoniert und entfernt")
	check(PlacedCharge.remote_booms > booms0, "Client: Detonation vom Server gemeldet (Server-Auswertung)",
		"%d → %d" % [booms0, PlacedCharge.remote_booms])
	# zweite Mine des Hosts entschärfen
	var mine_b: PlacedCharge = null
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and mine_b == null:
		await get_tree().create_timer(0.1).timeout
		for n in get_tree().get_nodes_in_group("placed_charges"):
			if not (n as PlacedCharge).is_done():
				mine_b = n
	check(mine_b != null, "Zweite Mine des Hosts liegt beim Client")
	if mine_b == null:
		_done()
		return
	await get_tree().create_timer(0.5).timeout
	me.stance_request = Soldier.Stance.CROUCH
	me.global_position = mine_b.global_position + Vector3(-1.0, 0.3, 0.0)
	me.velocity = Vector3.ZERO
	me.look_yaw = -PI * 0.5
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(mine_b) or not is_instance_valid(me):
		check(false, "Zweite Mine/eigener Soldat nach dem Heranschleichen noch vorhanden")
		_done()
		return
	var mines0 := me.mines
	var d0 := PlacedCharge.remote_defuses
	var spot := mine_b.defuse_spot
	check(spot.persistent_id.begins_with("charge_") and spot.can_interact(me), "Entschärfen möglich", spot.persistent_id)
	spot.interact(me)
	Net.used_interactable(spot)
	check(spot.busy() and me.work_left > 0.0, "Client: Entschärfen läuft (Fortschritt)")
	var wr: WeakRef = weakref(mine_b)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and wr.get_ref() != null and not (wr.get_ref() as PlacedCharge).is_done():
		await get_tree().create_timer(0.1).timeout
	check(wr.get_ref() == null or (wr.get_ref() as PlacedCharge).is_done(), "Client: Mine entschärft und entfernt")
	check(PlacedCharge.remote_defuses == d0 + 1 and me.mines == mines0,
		"Client: Entschärfung vom Server gemeldet, Mine ersatzlos entfernt", "%d/%d" % [me.mines, mines0])
	check(me.alive, "Client: keine Explosion beim Entschärfen")
	_done()


var _quitting := false


func _done() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://tools_mines_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	var t0 := Time.get_ticks_msec()
	while Net.is_online and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(0.5).timeout
	Net.leave(false)
	get_tree().quit()
