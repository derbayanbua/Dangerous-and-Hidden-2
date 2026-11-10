extends "res://tests/test_gameplay.gd"
## Wasser, Schwimmen, Tauchen (NORWAY: Magnetminen an der Tirpitz unter Wasser, Tauchgerät = Gegenstand 231).
##   tools\godot.cmd --headless -- --mission=nw1_dampfleitung --autoplay=test_water


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.orig != null and m.orig.water.size() > 0, "Wasserflächen erkannt (QuadPatch/MORE)",
		str(m.orig.water.size()) if m and m.orig else "-")
	if m == null or m.orig.water.is_empty():
		_finish()
		return
	_water_look(m)
	isolate_enemies([])
	var s: Soldier = m.squad.leader()
	# Minenplatz unter Wasser
	var place: OrigInteractive.OrigExplosive = null
	for k in m.interactive.controls:
		var c = m.interactive.controls[k]
		if c is OrigInteractive.OrigExplosive and c.required_item == 251:
			place = c
			break
	check(place != null, "Magnetminen-Platz (Gegenstand 251)")
	if place == null:
		_finish()
		return
	var lvl: float = m.water_level_at(place.global_position)
	check(not is_nan(lvl) and place.global_position.y < lvl - 2.0, "Minenplatz liegt unter dem Wasserspiegel",
		"Platz y %.1f, Wasser %.1f" % [place.global_position.y, lvl])
	# ohne Tauchgerät: Luft wird knapp
	s.set_meta("orig_items", s.get_meta("orig_items", []).filter(func(x): return int(x) != 231))
	s.global_position = place.global_position + Vector3(1.0, -0.5, 0.0)
	s.velocity = Vector3.ZERO
	s.air = Soldier.AIR_MAX
	await seconds(1.5)
	check(s.swimming, "Soldat schwimmt/taucht")
	check(s.air < Soldier.AIR_MAX - 0.5, "Ohne Tauchgerät sinkt die Luft", "%.1f" % s.air)
	check(s.global_position.y > place.global_position.y - 0.4, "Auftrieb ohne Eingabe")
	# mit Tauchgerät (akvalung 231): Luft bleibt, Mine anbringen (3 s)
	var inv: Array = s.get_meta("orig_items", [])
	inv.append(231)
	inv.append(251)
	s.set_meta("orig_items", inv)
	s.global_position = place.global_position + Vector3(1.0, -0.3, 0.0)
	s.air = Soldier.AIR_MAX
	s.look_pitch = -0.6
	s.move_input = Vector3.ZERO
	var mines_before: int = s.get_meta("orig_items").count(251)
	place.interact(s)
	for i in 60:
		s.global_position = place.global_position + Vector3(1.0, -0.3, 0.0)    # Taucher hält die Position
		await seconds(0.1)
		if place.state == 1:
			break
	check(place.state == 1, "Magnetmine unter Wasser angebracht (Zustand 1)", str(place.state))
	check(is_equal_approx(s.air, Soldier.AIR_MAX), "Mit Tauchgerät keine Atemnot")
	check(s.get_meta("orig_items", []).count(251) == mines_before - 1, "Mine aus dem Inventar verbraucht")
	_finish()


## 0.10.8: Wasseroptik je Klimazone, Qualitätsstufen, Rückfall „Original-Wasser“
func _water_look(m) -> void:
	var fx = load("res://src/world/water_fx.gd")
	var st: Dictionary = fx.stats
	var with_mat := 0
	for mi in m.orig.water_meshes:
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_override is ShaderMaterial:
			with_mat += 1
	check(int(st.get("meshes", 0)) > 0 and with_mat == m.orig.water_meshes.size() and st.get("zone") == "norway",
		"Neues Wasser: Material auf allen Wasserflächen, Stil Norwegen", "%s / %d von %d" % [str(st.get("zone")), with_mat, m.orig.water_meshes.size()])
	check(m.orig.water.size() > 0, "Wasserbereiche (Schwimmen) unverändert erkannt")
	var zones := {"arctic1": "arctic", "normandy3_mp": "normandy", "burma2": "burma", "norway": "norway",
		"africa5": "africa", "czech2": "czech", "alps1_mp_zone": "alps"}
	var ok := true
	var seen := {}
	for f in zones:
		var z: String = fx.zone_of(f)
		var p: Dictionary = fx.params_for(f, 2)
		ok = ok and z == zones[f] and p.has("shallow_color")
		seen[str(p["shallow_color"])] = true
	check(ok and seen.size() == zones.size(), "Klimazonen: eigener Stil je Zone", str(seen.size()))
	var q0: Dictionary = fx.params_for("normandy", 0)
	var q4: Dictionary = fx.params_for("normandy", 4)
	check(int(q0["wave_count"]) < int(q4["wave_count"]) and float(q0["foam_amount"]) == 0.0 and float(q4["foam_amount"]) > 0.0,
		"Grafikstufe: Niedrig weniger Wellen/kein Schaum, 4K Ultra voll")
	var keep: int = Settings.water_mode
	Settings.water_mode = 1
	var n_off: int = fx.apply(m, m.orig)
	check(n_off == 0 and not fx.enabled(), "Option ORIGINAL-Wasser: kein neues Material")
	Settings.water_mode = keep
	fx.apply(m, m.orig)
