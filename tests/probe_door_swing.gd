extends Node
## Prüfwerkzeug Drehsinn Originaltüren: für jede Drehtür der Karte den Flügel um +/−open_amount (lokal um axis_gltf)
## drehen und zählen, ob der geöffnete Flügel in statische Geometrie ragt (Kasten des Flügels, 6 cm geschrumpft).
##   tools\godot.cmd --headless -- --autoplay=probe_door_swing --maps=mp_normandy2_mp_zone,mp_arena_a1_blizzard
## Ausgabe: SWING <karte> <tür> st=<Startzustand> plus=<Treffer> minus=<Treffer> heur=<bisheriger Drehsinn>

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _hits(m: Mission, d: OrigInteractive.OrigDoor, sign: float) -> int:
	d.frame.transform = d.base * Transform3D(Basis(d.axis, sign * d.open_amount), Vector3.ZERO)
	var own: Array[RID] = []
	for b in d.frame.find_children("*", "CollisionObject3D", true, false):
		own.append((b as CollisionObject3D).get_rid())
	var n := 0
	for mi in d.frame.find_children("*", "MeshInstance3D", true, false) + ([d.frame] if d.frame is MeshInstance3D else []):
		var me := mi as MeshInstance3D
		if me.mesh == null:
			continue
		var bb := me.get_aabb()
		var box := BoxShape3D.new()
		box.size = (bb.size - Vector3(0.12, 0.3, 0.12)).max(Vector3(0.01, 0.01, 0.01))
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = me.global_transform * Transform3D(Basis(), bb.get_center())
		q.collision_mask = 1
		q.exclude = own
		for r in m.get_world_3d().direct_space_state.intersect_shape(q, 8):
			var c: Node = r["collider"]
			if c and not String(c.get_path()).contains("/Dynamic/"):
				n += 1
	return n


func _run() -> void:
	var maps := String(Game.cli.get("maps", "mp_normandy2_mp_zone")).split(",")
	var port := Net.PORT + 61
	for map in maps:
		Net.host({"name": "Swing", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": port, "max_players": 2,
			"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0, "password": "", "allow_vehicles": false})
		port += 1
		await _wait(func():
			var mm = Game.current_mission()
			return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 400.0)
		var m: Mission = Game.current_mission()
		await get_tree().create_timer(1.0).timeout
		var it: OrigInteractive = m.get("interactive")
		var tot := {"plus": 0, "minus": 0, "n": 0}
		for k in it.controls:
			var d = it.controls[k]
			if not (d is OrigInteractive.OrigDoor) or d.slide:
				continue
			var keep: Transform3D = d.frame.transform
			var hp := _hits(m, d, 1.0)
			await get_tree().physics_frame
			var hm := _hits(m, d, -1.0)
			d.frame.transform = keep
			tot.n += 1
			tot.plus += int(hp > 0)
			tot.minus += int(hm > 0)
			print("SWING %s %s st=%d plus=%d minus=%d heur=%+.0f" % [map, k, int(d.p.get("initial_state", 0)), hp, hm, d.sgn])
		print("SWINGSUM %s Türen=%d mit Kollision: plus=%d minus=%d" % [map, tot.n, tot.plus, tot.minus])
		Net.leave(false)
		await get_tree().create_timer(2.0).timeout
	get_tree().quit(0)
