extends "res://tests/test_gameplay.gd"
## Mission 3 "Sandsturm": Tarnung (Uniform erbeuten, Wirkung auf Distanz,
## Auffliegen aus der Nähe und nach Schuss), Flak-Ziele, Pläne, Sammelpunkt.
##   tools\godot.cmd --headless -- --mission=m03_sandsturm --autoplay=test_m03


func place(s: Soldier, x: float, z: float, yaw: float) -> void:
	s.global_position = mission().lb.ground(x, z, 0.3)
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func watcher(pid: String, x: float, z: float, yaw: float) -> EnemyBrain:
	var e := enemy(pid)
	var b := e.get_node("EnemyBrain") as EnemyBrain
	place(e, x, z, yaw)
	e.set_physics_process(true)
	var per: Perception = e.get_node("Perception")
	per.set_physics_process(true)
	per.awareness.clear()
	per.sight_range = 70.0
	b.enabled = true
	b.patrol_points = PackedVector3Array()
	b.stationary = true
	b.home_pos = e.global_position
	b.home_yaw = yaw
	b.set_state(EnemyBrain.State.GUARD)
	return b


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and Game.current_mission_id == "m03_sandsturm", "Mission 3 geladen")
	for i in 1500:
		if m.nav_ready:
			break
		await frames(1)
	check(m.nav_ready, "Navigationsnetz Mission 3")
	check(m.enemies.size() == 15, "15 Gegner", str(m.enemies.size()))
	check(m.flak_sites.size() == 3 and get_tree().get_nodes_in_group("vehicles").size() == 2, "3 Flak-Stellungen, 2 Kübelwagen")
	isolate_enemies([])
	var hale := m.squad.leader()
	for mm in m.squad.members:
		if mm != hale:
			var b := m.squad.brain_of(mm)
			b.roe = SquadBrain.ROE.HOLD_FIRE
			b.set_order(SquadBrain.Order.HOLD)
			mm.global_position = Vector3(120, 30, 120)
			b.hold_pos = mm.global_position
			mm.set_physics_process(false)

	# --- Uniform vom Vorposten erbeuten ---
	var post := enemy("s_outpost")
	place(post, -20, 28, 0.0)
	post.set_physics_process(true)
	post.die(null)
	await seconds(1.0)
	place(hale, -19.3, 28, PI * 0.5)
	await frames(10)
	var loot := m.controller.interact_target as Pickups.Loot
	check(loot != null, "Gefallener Vorposten durchsuchbar")
	await tap("interact")
	check(loot != null and loot.prompt == "Uniform anziehen" and m.controller.interact_target == loot, "Nach dem Durchsuchen: Uniform anziehen angeboten")
	await tap("interact")
	check(hale.disguised and hale.uniform_color.is_equal_approx(m.enemy_uniform), "Uniform angezogen (Khaki)")

	# --- Tarnung wirkt auf Distanz bei Tageslicht ---
	place(hale, -25, 28, -PI * 0.5)
	var wb := watcher("s_south", 0, 28, PI * 0.5)    # 25 m, blickt direkt auf Hale
	await seconds(5.0)
	var per: Perception = wb.soldier.get_node("Perception")
	check(wb.state != EnemyBrain.State.COMBAT and per.awareness.get(hale, 0.0) < 0.2, "Getarnt auf 25 m bei Tag: nicht erkannt", "Erkennung %.2f" % per.awareness.get(hale, 0.0))
	# Gegenprobe: ein ungetarnter Kamerad wird am gleichen Ort erkannt
	var kow: Soldier = m.squad.members[3]
	kow.set_physics_process(true)
	place(kow, -25, 30, -PI * 0.5)
	var t := 0.0
	while t < 4.0 and per.awareness.get(kow, 0.0) < 1.0:
		await frames(6)
		t += 0.1
	check(per.awareness.get(kow, 0.0) >= 1.0, "Ungetarnter Kamerad am selben Ort erkannt", "%.1f s" % t)
	kow.global_position = Vector3(120, 30, 120)
	kow.set_physics_process(false)
	wb.set_state(EnemyBrain.State.GUARD)
	per.awareness.clear()
	await seconds(0.5)

	# --- Aus der Nähe fliegt die Tarnung auf ---
	place(hale, -5, 28, -PI * 0.5)    # 5 m
	t = 0.0
	while t < 8.0 and per.awareness.get(hale, 0.0) < 1.0:
		await frames(6)
		t += 0.1
	check(per.awareness.get(hale, 0.0) >= 1.0, "Getarnt aus 5 m erkannt", "%.1f s" % t)
	wb.set_state(EnemyBrain.State.GUARD)
	per.awareness.clear()

	# --- Nach eigenem Schuss fliegt die Tarnung auf ---
	place(hale, -25, 28, -PI * 0.5)
	await seconds(0.5)
	hale.look_pitch = deg_to_rad(40)
	await hold("fire", 0.15)
	t = 0.0
	while t < 4.0 and per.awareness.get(hale, 0.0) < 1.0:
		await frames(6)
		t += 0.1
	check(per.awareness.get(hale, 0.0) >= 1.0, "Nach Schuss getarnt auf 25 m erkannt", "%.1f s" % t)
	wb.enabled = false
	wb.soldier.die(null)

	# --- Ziele: drei Flak, Pläne ---
	for site in m.flak_sites:
		site.fuse = 0.4
		hale.global_position = site.global_position + Vector3(0, 0.3, 1.3)
		var d: Vector3 = site.global_position - hale.global_position
		hale.look_yaw = atan2(-d.x, -d.z)
		await frames(10)
		await tap("interact")
		hale.global_position += Vector3(0, 0, 25)
		await seconds(1.0)
	var flak_done := 0
	for i in 3:
		if m.objective(StringName("flak_%d" % i)).is_done():
			flak_done += 1
	check(flak_done == 3, "Alle drei Flak gesprengt", "%d/3" % flak_done)
	hale.global_position = m.plans.global_position + Vector3(1.0, -0.6, 0)
	var dp: Vector3 = m.plans.global_position - hale.global_position
	hale.look_yaw = atan2(-dp.x, -dp.z)
	await frames(10)
	await tap("interact")
	check(m.objective(&"plans").is_done(), "Lagepläne gesichert")

	# --- Sammelpunkt ---
	var k := 0
	for mm in m.squad.alive_members():
		mm.set_physics_process(true)
		mm.global_position = m.extraction_pos + Vector3(k * 1.3, 0.5, 0)
		k += 1
	await seconds(1.0)
	check(m.finished and Game.last_result.get("success", false), "Sammelpunkt erreicht: Mission 3 erfolgreich")
	_finish()
