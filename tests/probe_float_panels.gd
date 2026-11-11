extends "res://tests/test_gameplay.gd"
## Sonde: frei schwebende dünne Flächen (Gitter/Glas/Rahmen) – weder an einer Wand (≤ 0,3 m hinter der Fläche) noch
## in einer Öffnung eingespannt (Weltkollision an ≥ 2 Rändern) noch auf dem Boden.
##   tools\godot.cmd --headless -- --mission=<m> --autoplay=probe_float_panels
## Ergebnis test_output/float_panels_<mission>.txt

var _out: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_out.append(s)


func _alpha(mi: MeshInstance3D) -> bool:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as BaseMaterial3D
		if mat and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


func _run() -> void:
	for i in 4800:
		if mission() and mission().squad and mission().squad.leader() and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.get("runtime") and m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	await seconds(2.0)
	var space := m.get_viewport().world_3d.direct_space_state
	var n := 0
	for x in m.find_children("*", "MeshInstance3D", true, false):
		var mi := x as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.get_parent() is Soldier:
			continue
		var la := mi.get_aabb()
		var dims := [la.size.x, la.size.y, la.size.z]
		var k := dims.find(dims.min())
		var big := 0
		for d in dims:
			if d > 0.5:
				big += 1
		if dims[k] > 0.12 or big < 2 or la.size.length() > 8.0:
			continue
		var gb := mi.global_basis
		var nrm: Vector3 = gb[k].normalized()
		var ax := [gb[(k + 1) % 3], gb[(k + 2) % 3]]
		var hs := [dims[(k + 1) % 3] * 0.5, dims[(k + 2) % 3] * 0.5]
		var c := mi.global_transform * la.get_center()
		if absf(nrm.y) > 0.8:
			continue     # liegende Fläche (Boden/Decke/Rost)
		var ex: Array[RID] = []
		for b in mi.find_children("*", "CollisionObject3D", true, false):
			ex.append((b as CollisionObject3D).get_rid())
		var hit := func(a: Vector3, b: Vector3) -> bool:
			var q := PhysicsRayQueryParameters3D.create(a, b, 1)
			q.exclude = ex
			q.hit_back_faces = true
			return not space.intersect_ray(q).is_empty()
		var mounted := false
		for s in [1.0, -1.0]:
			for o in [Vector3.ZERO, ax[0].normalized() * hs[0] * 0.6, -ax[0].normalized() * hs[0] * 0.6]:
				if hit.call(c + o, c + o + nrm * s * 0.3):
					mounted = true
		var edges := 0
		for i2 in 2:
			for s in [1.0, -1.0]:
				var e: Vector3 = c + ax[i2].normalized() * hs[i2] * s * 0.9
				if hit.call(e, e + ax[i2].normalized() * s * 0.3):
					edges += 1
		if mounted or edges >= 2:
			continue
		n += 1
		_log("SCHWEBT %s par=%s alpha=%s c=%s size=%s normal=%s edges=%d" % [mi.name, mi.get_parent().name, _alpha(mi),
			c, la.size, nrm, edges])
	_log("ANZAHL %d" % n)
	var f := FileAccess.open("res://test_output/float_panels_%s.txt" % Game.current_mission_id, FileAccess.WRITE)
	f.store_string("\n".join(_out))
	f.close()
	_finish()
