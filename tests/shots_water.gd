extends "res://tests/test_gameplay.gd"
## 0.10.8 Kontrollbilder Wasser (FENSTER): je Karte Blick schräg/von oben auf die größte Wasserfläche und ihr Ufer,
## grobe Bildrate NEU vs. ORIGINAL (Originalmaterial wieder eingesetzt) am selben Blickpunkt.
##   tools\godot.cmd -- --mission=<m> --autoplay=shots_water [--tag=]  → test_output/water/<m>_*.png, water_fps_<m>.txt


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader() and mission().get("orig") != null:
			break
		await get_tree().process_frame
	var m = mission()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/water"))
	var mid := String(Game.cli.get("mission", "x"))
	var meshes: Array = m.orig.water_meshes if m and m.orig else []
	check(not meshes.is_empty(), "Wasserflächen vorhanden", str(meshes.size()))
	if meshes.is_empty():
		_finish()
		return
	isolate_enemies([])
	var ql := int(Game.cli.get("level", "2"))
	if Settings.quality != ql:
		Settings.quality = ql
		if Settings.has_method("apply"):
			Settings.apply()
		Settings.changed.emit()
	await seconds(3.0)
	# größte Fläche
	var best: MeshInstance3D = null
	var area := 0.0
	for mi in meshes:
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if b.size.x * b.size.z > area:
			area = b.size.x * b.size.z
			best = mi
	var box: AABB = best.global_transform * best.get_aabb()
	var cam := Camera3D.new()
	cam.far = 3000.0
	m.add_child(cam)
	cam.make_current()
	var hud := m.get("hud") as CanvasItem
	if hud:
		hud.visible = false
	var c := box.get_center()
	c.y = box.end.y
	var half := minf(minf(box.size.x, box.size.z) * 0.5, 60.0)
	# Ufer: Kante der Fläche in +x-Richtung (bei großen Meeren Nähe zum Spieler)
	var leader: Soldier = m.squad.leader()
	var shore := Vector3(clampf(leader.global_position.x, box.position.x, box.end.x), c.y,
		clampf(leader.global_position.z, box.position.z, box.end.z))
	var views := {
		"schraeg": [shore + Vector3(0, 12, 0) + (shore - c).normalized() * 18.0, shore + (c - shore).normalized() * 25.0],
		"oben": [c + Vector3(0.5, half * 0.8 + 8.0, 0.5), c],
		"nah": [shore + Vector3(2, 3, 2), shore + (c - shore).normalized() * 12.0],
	}
	var fps_lines: PackedStringArray = []
	for v in views:
		var from: Vector3 = views[v][0]
		var to: Vector3 = views[v][1]
		cam.global_position = from
		if from.distance_to(to) > 0.01:
			cam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
		await seconds(2.0)
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://test_output/water/%s_%s.png" % [mid, v])
		if v == "schraeg":
			fps_lines.append("NEU: %.1f fps" % await _fps(3.0))
			var saved := {}
			for mi in meshes:
				saved[mi] = mi.material_override
				mi.material_override = mi.get_meta("water_orig_override", null)
			await seconds(1.0)
			fps_lines.append("ORIGINAL: %.1f fps" % await _fps(3.0))
			get_viewport().get_texture().get_image().save_png("res://test_output/water/%s_%s_original.png" % [mid, v])
			for mi in meshes:
				mi.material_override = saved[mi]
	var f := FileAccess.open("res://test_output/water/water_fps_%s.txt" % mid, FileAccess.WRITE)
	f.store_string("%s Stufe %d Flaechen %d\n%s\n" % [mid, Settings.quality, meshes.size(), "\n".join(fps_lines)])
	print("WASSERFPS ", mid, " ", " | ".join(fps_lines))
	check(true, "Bilder geschrieben")
	_finish()


func _fps(dur: float) -> float:
	var t0 := Time.get_ticks_usec()
	var n := 0
	while Time.get_ticks_usec() - t0 < int(dur * 1e6):
		await get_tree().process_frame
		n += 1
	return n / ((Time.get_ticks_usec() - t0) / 1e6)
