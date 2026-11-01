extends "res://tests/test_gameplay.gd"
## Diagnose fix_no2_panzer: Lage der Panzer, Boden darunter, Körper an einem Sperrpunkt.
##   --mission=no2_schwerttaenzer --autoplay=probe_no2_tanks [--p=x,y,z;x,y,z] [--r=2.5]


func _desc(n: Node) -> String:
	var s := String(n.get_path())
	var parts := s.split("/")
	s = "/".join(parts.slice(maxi(parts.size() - 4, 0)))
	var metas := []
	for k in n.get_meta_list():
		metas.append("%s=%s" % [k, str(n.get_meta(k)).left(40)])
	if n is CollisionObject3D:
		metas.append("layer=%d" % (n as CollisionObject3D).collision_layer)
		for c in n.get_children():
			if c is CollisionShape3D:
				metas.append("shape=%s" % (c as CollisionShape3D).shape.get_class())
	return "%s [%s] %s" % [s, n.get_class(), " ".join(metas)]


## --drive=1: beide Panzer mit Fahrer besetzen und ihre Original-Fahrspuren abfahren (wie die Fahrerskripte)
func _drive_test() -> void:
	var rt = mission().get("runtime")
	var plan := {"la_sherman": ["Amik_tank_driver", ["AmiiTank_1", "AmiiTank_2", "AmiiTank_3", "AmiiTank_4", "AmiiTank_5",
		"AmiiTank_6", "AmiiTank_7", "AmiTank_End"], [14, 14, 14, 14, 12, 12, 18, 18]],
		"La_tigerEv": ["GerTank_driver", ["GerTank1", "GerTank2", "GerTank3"], [10, 14, 16]]}
	for s in mission().squad.members:
		s.max_health = 100000.0      # wie der Löser: Trupp überlebt, Mission läuft weiter
		s.health = s.max_health
		s.process_mode = Node.PROCESS_MODE_DISABLED   # bleibt stehen (sonst „Einsatzgebiet verlassen“ → Mission endet)
	var vehs := {}
	for v in get_tree().get_nodes_in_group("vehicles"):
		vehs[String(v.name)] = v
	Engine.time_scale = float(Game.cli.get("speed", "2"))
	print("PROBE vehicle_passable: %d Körper" % get_tree().get_nodes_in_group(&"vehicle_passable").size())
	for vn in plan:
		var veh: Vehicle = vehs.get(vn)
		var drv: Soldier = null
		for s in get_tree().get_nodes_in_group("soldiers"):
			if String(s.name) == plan[vn][0]:
				drv = s
		if veh == null or drv == null:
			print("PROBE DRIVE %s: Fahrzeug/Fahrer fehlt" % vn)
			continue
		if drv.vehicle != veh:
			veh.board(drv, true, 0)
		var t0 := Time.get_ticks_msec()
		for i in plan[vn][1].size():
			var wp: String = plan[vn][1][i]
			var gi: int = rt._drive_name(wp)
			veh.drive_path(rt._drive_route(veh.global_position, gi), float(plan[vn][2][i]))
			var t1 := Time.get_ticks_msec()
			var last := veh.global_position
			var stuck := 0.0
			while not veh.drive_done() and Time.get_ticks_msec() - t1 < 120000:
				await get_tree().create_timer(1.0).timeout
				if not is_instance_valid(veh):
					print("PROBE DRIVE %s: Fahrzeug freigegeben (Mission beendet?)" % vn)
					check(false, "%s besteht" % vn)
					Engine.time_scale = 1.0
					return
				var moved := veh.global_position.distance_to(last)
				last = veh.global_position
				stuck = stuck + 1.0 if moved < 0.3 else 0.0
			var goal: Vector3 = rt._drive_astar.get_point_position(gi)
			var ok := veh.global_position.distance_to(goal) < 6.0
			print("PROBE DRIVE %s %s -> %s: pos %s Ziel %s Abstand %.1f %s (%.0f s)" % [vn, i, wp, veh.global_position, goal,
				veh.global_position.distance_to(goal), "OK" if ok else "VERFEHLT", (Time.get_ticks_msec() - t1) / 1000.0])
			check(ok and veh.global_position.y > -5.0, "%s erreicht %s" % [vn, wp])
	Engine.time_scale = 1.0


func _run() -> void:
	for i in 2400:
		if mission() and mission().orig:
			break
		await get_tree().process_frame
	await frames(30)
	if Game.cli.has("drive"):
		await frames(120)
		await _drive_test()
		_finish()
		return
	var space := get_tree().root.get_world_3d().direct_space_state
	for v in get_tree().get_nodes_in_group("vehicles"):
		var vb := v as Node3D
		print("PROBE Fzg %s pos %s rot %s parent %s" % [vb.name, vb.global_position, vb.global_rotation_degrees, vb.get_parent().name])
		for off in [Vector3.ZERO, Vector3(2, 0, 3), Vector3(-2, 0, -3)]:
			var p: Vector3 = vb.global_position + off
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 30.0, 1, [(vb as CollisionObject3D).get_rid()])
			q.hit_back_faces = true
			var h := space.intersect_ray(q)
			print("PROBE   Boden unter %s: %s" % [p, ("%s n=%s %s" % [h.position, h.normal, _desc(h.collider)]) if not h.is_empty() else "NICHTS"])
	var pts := String(Game.cli.get("p", "57.0,0.8,66.2;63.5,0.5,-15.7")).split(";")
	var r := float(Game.cli.get("r", "2.5"))
	for ps in pts:
		var c := ps.split(",")
		var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var sh := SphereShape3D.new()
		sh.radius = r
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = sh
		sq.transform = Transform3D(Basis(), p)
		sq.collision_mask = 1 | (1 << 4)
		var seen := {}
		for res in space.intersect_shape(sq, 32):
			var n: Node = res["collider"]
			if seen.has(n):
				continue
			seen[n] = true
			print("PROBE Körper bei %s: %s" % [p, _desc(n)])
	# Sichtbare Meshes über den Punkten (xz im AABB) mit Kollisionsstatus
	for ps in pts:
		var c := ps.split(",")
		var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
		for mi in mission().find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_inside_tree():
				continue
			var bb: AABB = m.global_transform * m.get_aabb()
			if p.x < bb.position.x or p.x > bb.end.x or p.z < bb.position.z or p.z > bb.end.z or bb.position.y > p.y + 3.0 or bb.end.y < p.y - 3.0:
				continue
			var cols := []
			for co in m.find_children("*", "CollisionObject3D", true, false):
				cols.append("%s(l%d)" % [co.name, (co as CollisionObject3D).collision_layer])
			print("PROBE Mesh bei %s: %s vis=%s aabb=%s cols=%s par=%s" % [p, _desc(m), m.is_visible_in_tree(), bb, cols, m.get_parent().name])
	# Sherman an die Sperrstelle (Blick −X) setzen und Rumpf-Überschneidungen melden
	for v in get_tree().get_nodes_in_group("vehicles"):
		if String(v.name) != "la_sherman":
			continue
		var vb := v as RigidBody3D
		vb.freeze = true
		vb.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(58.35, -0.47, 66.26))
		await frames(3)
		for ch in vb.get_children():
			if ch is CollisionShape3D:
				var hq := PhysicsShapeQueryParameters3D.new()
				hq.shape = (ch as CollisionShape3D).shape
				hq.transform = vb.global_transform * (ch as CollisionShape3D).transform
				hq.collision_mask = 1 | (1 << 4)
				hq.exclude = [vb.get_rid()]
				for res in space.intersect_shape(hq, 16):
					var hb: Node = res["collider"]
					var hm := hb.get_parent() as MeshInstance3D
					print("PROBE Sherman-Rumpf %s trifft %s passable=%s aabb=%s" % [ch.name, _desc(hb), hb.is_in_group(&"vehicle_passable"),
						(hm.global_transform * hm.get_aabb()) if hm else "-"])
				for res in space.collide_shape(hq, 8):
					print("PROBE   Kontakt %s" % res)
	check(true, "Probe")
	_finish()
