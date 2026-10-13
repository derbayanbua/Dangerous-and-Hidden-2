extends "res://tests/test_gameplay.gd"
## Mission 2 "Nordlicht": Nacht/Licht, Suchscheinwerfer, Zaun, Gefangenen-
## befreiung und Eskorte, Ziele, Speichern/Laden der Begleitperson, Abholung.
##   tools\godot.cmd --headless -- --mission=m02_nordlicht --autoplay=test_m02


func place(s: Soldier, p: Vector3, yaw: float) -> void:
	s.global_position = p + Vector3.UP * 0.3
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and Game.current_mission_id == "m02_nordlicht", "Mission 2 geladen")
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	check(m.nav_ready, "Navigationsnetz Mission 2")
	check(m.enemies.size() == 14, "14 Gegner", str(m.enemies.size()))
	var hale := m.squad.leader()
	isolate_enemies([])
	for mm in m.squad.members:
		if mm != hale:
			m.squad.brain_of(mm).roe = SquadBrain.ROE.HOLD_FIRE

	# --- Licht: Nacht dunkel, Laterne hell ---
	var dark: float = m.light_at(m.lb.ground(-80, 60, 1.0))
	var lamp: float = m.light_at(Vector3(0, 2.0, 15))
	check(dark <= 0.55 and lamp > 1.0, "Nacht dunkel, Laterne erhellt", "dunkel %.2f, Laterne %.2f" % [dark, lamp])

	# --- Suchscheinwerfer beleuchtet Kegel und kann ausgeschossen werden ---
	var sls := get_tree().get_nodes_in_group("searchlights")
	check(sls.size() == 2, "Zwei Suchscheinwerfer")
	var sl: Searchlight = sls[0]
	await frames(5)
	var dir := -sl._light.global_basis.z
	var lit_point := sl._light.global_position + dir * 25.0
	lit_point.y = m.lb.height_at(lit_point.x, lit_point.z) + 1.0
	# auf Boden projizieren entlang des Strahls
	var q := PhysicsRayQueryParameters3D.create(sl._light.global_position, sl._light.global_position + dir * 70.0, 1)
	var hit := m.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		lit_point = hit.position + Vector3.UP * 0.5
	check(sl.illuminates(lit_point) and m.light_at(lit_point) > 1.0, "Lichtkegel erhellt Ziel", "%.2f" % m.light_at(lit_point))
	sl.on_bullet_hit(40.0, hale)
	check(sl.destroyed and not sl.illuminates(lit_point), "Scheinwerfer ausgeschossen")

	# --- Zaun blockiert Bewegung, nicht Sicht ---
	place(hale, m.lb.ground(-44, -10), -PI * 0.5)   # außen, Blick nach Osten auf den Zaun
	await seconds(0.3)
	var x0 := hale.global_position.x
	await hold("move_forward", 2.0)
	check(hale.global_position.x < -42.2, "Stacheldraht blockiert", "x=%.2f" % hale.global_position.x)
	var rq := PhysicsRayQueryParameters3D.create(hale.eye_position(), hale.eye_position() + Vector3(6, 0, 0), 1)
	check(m.get_world_3d().direct_space_state.intersect_ray(rq).is_empty(), "Zaun blockiert keine Sicht")
	# Lücke im Westzaun (bei z = -20)
	place(hale, m.lb.ground(-45, -20), -PI * 0.5)
	await hold("move_forward", 3.0)
	check(hale.global_position.x > -41.5, "Durch die Zaunlücke ins Lager", "x=%.2f" % hale.global_position.x)
	var _unused := x0

	# --- Gefangenen befreien ---
	var pr: Soldier = m.prisoner
	check(not pr.is_in_group("team_0"), "Gefesselter Gefangener ist kein Ziel für Gegner")
	place(hale, Vector3(27.5, 1.0, 0.5), -PI * 0.5)
	await frames(10)
	check(m.controller.interact_target is Interactable and m.controller.interact_target.prompt == "Gefangenen befreien", "Befreien als Interaktion")
	await tap("interact")
	await frames(5)
	check(m.prisoner_brain.released and pr.is_in_group("team_0"), "Gefangener befreit")
	check(m.objective(&"prisoner").is_done(), "Ziel Befreiung erfüllt")
	# folgt dem Anführer
	place(hale, m.lb.ground(10, -12), PI)
	await seconds(8.0)   # muss Tür öffnen und das Gebäude verlassen
	check(pr.global_position.distance_to(hale.global_position) < 8.0, "Gefangener folgt", "%.1f m" % pr.global_position.distance_to(hale.global_position))

	# --- Tanklager sprengen ---
	for site in [m.depot_a, m.depot_b]:
		site.fuse = 0.5
		place(hale, site.global_position + Vector3(0, 0, 1.4), 0.0)
		await frames(10)
		await tap("interact")
		place(hale, site.global_position + Vector3(0, 0, 25.0), 0.0)
		await seconds(1.2)
	check(m.objective(&"depot_a").is_done() and m.objective(&"depot_b").is_done(), "Beide Tanklager gesprengt")

	# --- Speichern/Laden mit Begleitperson ---
	var ppos := pr.global_position
	Game.save_game("autotest_m02")
	Game.load_game("autotest_m02")
	for i in 600:
		await get_tree().process_frame
		if mission() and mission() != m and mission().squad and mission().squad.leader():
			break
	await frames(10)
	m = mission()
	check(m.prisoner_brain.released and m.prisoner.global_position.distance_to(ppos) < 1.5, "Begleitperson nach Laden befreit und am Ort")
	check(m.objective(&"depot_a").is_done() and m.objective(&"prisoner").is_done(), "Ziele Mission 2 nach Laden")
	var sl2: Searchlight = get_tree().get_nodes_in_group("searchlights")[0]
	check(sl2.destroyed, "Zerstörter Scheinwerfer bleibt nach Laden aus")

	# --- Abholung: ohne Gefangenen kein Ende, mit Gefangenem Erfolg ---
	isolate_enemies([])
	var k := 0
	for mm in m.squad.alive_members():
		mm.global_position = m.extraction_pos + Vector3(k * 1.2, 0.5, 0)
		k += 1
	m.prisoner.global_position = m.extraction_pos + Vector3(0, 0.5, 30)
	m.prisoner_brain.enabled = false
	await seconds(1.0)
	check(not m.finished, "Ohne Gefangenen keine Abholung")
	m.prisoner.global_position = m.extraction_pos + Vector3(-1.5, 0.5, 0)
	await seconds(1.0)
	check(m.finished and Game.last_result.get("success", false), "Abholung mit Gefangenem: Erfolg")
	DirAccess.remove_absolute(Game.save_path("autotest_m02"))
	_finish()
