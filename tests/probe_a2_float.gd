extends "res://tests/test_gameplay.gd"
## Sonde ARCTIC2: frei schwebende Meshes (Unterkante > 0,5 m über dem Boden darunter, keine Wand/Decke in 0,35 m).
##   tools\run_locked.ps1 -Name a2float -Log test_output\probe_a2_float.log -GodotArgs "--headless -- --mission=a2_erkundung --autoplay=probe_a2_float"
## Ergebnis test_output/probe_a2_float.txt (Pfad, Herkunft, Größe, Abstand zum Boden).

var _out: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_out.append(s)


func _run() -> void:
	for i in 3600:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime") and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	var me: Soldier = m.squad.leader()
	me.max_health = 1e9
	me.health = 1e9
	me.set_meta("protect_until", 1e12)
	isolate_enemies([])
	await seconds(2.0)
	var space := m.get_viewport().world_3d.direct_space_state
	var n_float := 0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var v := mi as MeshInstance3D
		if not v.is_visible_in_tree() or v.mesh == null:
			continue
		var b := v.global_transform * v.get_aabb()
		if b.size.length() < 0.3 or b.size.length() > 12.0 or b.position.y > 2.0:
			continue
		var c := b.get_center()
		var bot := Vector3(c.x, b.position.y, c.z)
		var q := PhysicsRayQueryParameters3D.create(bot + Vector3.UP * 0.05, bot + Vector3.DOWN * 20.0, 1)
		var h := space.intersect_ray(q)
		var gap: float = (bot.y - h.position.y) if not h.is_empty() else 20.0
		if gap < 0.5:
			continue
		# angebunden? Wand seitlich oder Decke über der Oberkante
		var attached := false
		var top := Vector3(c.x, b.end.y, c.z)
		var probes := [[top - Vector3.UP * 0.05, top + Vector3.UP * 0.35]]
		var hx := b.size.x * 0.5 + 0.35
		var hz := b.size.z * 0.5 + 0.35
		for d in [Vector3(hx, 0, 0), Vector3(-hx, 0, 0), Vector3(0, 0, hz), Vector3(0, 0, -hz)]:
			probes.append([c, c + d])
		for p in probes:
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p[0], p[1], 1))
			if not r.is_empty():
				attached = true
				break
		if attached:
			continue
		n_float += 1
		var src := "static" if m.static_root and m.static_root.is_ancestor_of(v) else "dyn"
		_log("SCHWEBT %s [%s] mitte=%s groesse=%s abstand=%.2f" % [str(v.get_path()).replace("/root/MissionHost/Mission/", ""),
			src, c.snapped(Vector3.ONE * 0.1), b.size.snapped(Vector3.ONE * 0.1), gap])
	_log("A2FLOAT_SUMME %d" % n_float)
	var f := FileAccess.open("res://test_output/probe_a2_float.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out))
	check(true, "Sonde fertig", str(n_float))
	_finish()
