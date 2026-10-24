extends "res://tests/test_gameplay.gd"
## Zug (CZECH1 „lokotka“, Akteurtyp 14) und Kleinst-U-Boot (NORWAY sub_1, Akteurtyp 20) nach Original
## (docs/re_notes_ai.md §5). Aufruf je Mission:
##   tools\godot.cmd --headless -- --mission=cz1_eintrittsgeld --autoplay=test_orig_vehicles
##   tools\godot.cmd --headless -- --mission=nw1_dampfleitung --autoplay=test_orig_vehicles
## Fenster mit --shots=1: Kontrollbilder test_output/orig_vehicle_*.png


func shot(name: String, cam_pos: Vector3, look: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or not Game.cli.has("shots"):
		return
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.global_position = cam_pos
	cam.look_at(look)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	img.save_png(ProjectSettings.globalize_path("res://test_output/orig_vehicle_%s.png" % name))
	print("BILD test_output/orig_vehicle_%s.png" % name)
	cam.queue_free()


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.runtime != null, "Mission geladen")
	if m == null:
		_finish()
		return
	var rt: LsRuntime = m.runtime
	rt.auto_skip = true
	await seconds(1.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	if String(m.orig_mission).to_upper() == "CZECH1":
		await _train(m, rt)
	else:
		await _submarine(m, rt)
	_finish()


func _train(m, rt: LsRuntime) -> void:
	var loco := rt.find_frame("lokotka")
	var train: Node = null
	for n in m.dynamic_root.get_children():
		if String(n.name).begins_with("Train_"):
			train = n
	check(loco != null and train != null, "Lok und Zug-Steuerung (Akteurtyp 14)")
	if train == null:
		return
	var ps: Array = train.params
	check(ps.size() == 7 and is_equal_approx(float(ps[0]["length"]), 12.7) and is_equal_approx(float(ps[1]["length"]), 7.5)
		and is_equal_approx(float(ps[6]["length"]), 9.5) and is_equal_approx(float(ps[3]["gap"]), 3.0),
		"Zugparameter: Lok 12,7 / Tender 7,5 / Wagen 10 / letzter 9,5, Abstand 3", str(ps.map(func(p): return [p["name"], p["length"]])))
	check(train.cars.size() == 6, "6 Wagen gefunden (Tender + 5 Wagen)", str(train.cars.size()))
	var start: Array = train.cars.map(func(c): return (c["node"] as Node3D).global_position)
	# Lok fährt die Originalspur „vlak1“ (wie Skript vlak.scr: FRM_WatchTrack(vlak, "vlak1"))
	var dur: float = rt.extras.watch_track(loco, "vlak1")
	check(dur > 5.0, "Spur vlak1 vorhanden", "%.0f s" % dur)
	await seconds(8.0)
	var moved := 0
	for i in train.cars.size():
		if (train.cars[i]["node"] as Node3D).global_position.distance_to(start[i]) > 5.0:
			moved += 1
	check(moved == train.cars.size(), "Alle Wagen fahren mit", "%d/%d" % [moved, train.cars.size()])
	var prev: Vector3 = loco.global_position
	var ok := true
	var info := []
	for i in train.cars.size():
		var p := (train.cars[i]["node"] as Node3D).global_position
		var want: float = float(train.cars[i]["dist"]) - (float(train.cars[i - 1]["dist"]) if i > 0 else 0.0)
		var have := Vector2(p.x - prev.x, p.z - prev.z).length()
		info.append("%.1f/%.1f" % [have, want])
		if absf(have - want) > 1.0:
			ok = false
		prev = p
	check(ok, "Wagenabstände bleiben erhalten (±1 m)", ", ".join(info))
	var lp := loco.global_position
	await shot("zug", lp + Vector3(25, 12, 25), lp + (prev - lp) * 0.5)


func _submarine(m, rt: LsRuntime) -> void:
	var sub = rt.find_frame("sub_1")
	check(sub is Vehicle and sub.has_method("_blocked"), "Kleinst-U-Boot sub_1 als fahrbares Fahrzeug (Akteurtyp 20)", str(sub))
	if not (sub is Vehicle and sub.has_method("_blocked")):
		return
	var s = sub
	check(s.seats.size() == 2, "Sitze SEAT00/SEAT01 aus dem Modell", str(s.seats.size()))
	check(is_equal_approx(s.max_height, -1.0), "Höchsthöhe aus Akteurparameter (−1,0)", str(s.max_height))
	var hale: Soldier = m.squad.leader()
	hale.global_position = s.global_position + s.global_basis.x * 2.0
	check(s.board(hale, true), "Spieler steigt als Fahrer ein")
	check(hale.vehicle == s and not hale.model.visible, "Besatzung im Rumpf (unsichtbar)")
	await shot("uboot", s.global_position + Vector3(8, 4, 8), s.global_position)
	var p0: Vector3 = s.global_position
	# Eingaben wie der Spieler (PlayerController setzt throttle/steer_input/vertical_input je Physikschritt)
	Input.action_press("move_forward")
	# Gas 2 s: v = 2 m/s (1 m/s²), Weg ≈ 2 m
	var t := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check(absf(s.speed - 2.0) < 0.15, "Beschleunigung 1 m/s² (Original 0x5E1D90)", "v = %.2f m/s" % s.speed)
	var moved: float = Vector2(s.global_position.x - p0.x, s.global_position.z - p0.z).length()
	check(moved > 1.0 or s.speed < 0.1, "Boot fährt vorwärts", "%.2f m" % moved)
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check(s.speed <= 6.0001 and s.speed > 5.5, "Höchstgeschwindigkeit 6 m/s", "%.2f" % s.speed)
	# Ruder links: Gierwinkel ändert sich (dt·r·v·0,2)
	var yaw0: float = s.global_rotation.y
	Input.action_press("move_left")
	t = 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_left")
	Input.action_release("move_forward")
	check(absf(angle_difference(yaw0, s.global_rotation.y)) > 0.05 and s.rudder <= 0.5, "Ruder dreht das Boot (r ≤ 0,5)",
		"%.1f°, r = %.2f" % [rad_to_deg(angle_difference(yaw0, s.global_rotation.y)), s.rudder])
	# Ohne Gas: Fahrt baut 1 m/s² ab
	var v0: float = s.speed
	t = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check(v0 < 0.01 or absf((v0 - s.speed) - minf(v0, 1.0)) < 0.1, "Ohne Gas: Abbau 1 m/s²", "%.2f → %.2f" % [v0, s.speed])
	# Auftauchen: nie über die Höchsthöhe
	t = 0.0
	var top := -INF
	while t < 15.0:
		Input.action_press("stance_stand")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, s.global_position.y)
	Input.action_release("stance_stand")
	check(top <= s.max_height + 0.001, "Auftauchen begrenzt auf +0xD8 (−1,0)", "höchste Lage %.2f" % top)
	check(absf(s.climb) <= 1.0001, "Steig-/Sinkgeschwindigkeit ≤ 1 m/s", "%.2f" % s.climb)
	s.leave(hale)
	check(hale.vehicle == null and hale.model.visible, "Aussteigen")
