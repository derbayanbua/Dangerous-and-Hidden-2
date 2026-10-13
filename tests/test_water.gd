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
