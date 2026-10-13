extends "res://tests/test_gameplay.gd"
## Fahrzeuge: Einsteigen, Mitfahrer, Fahren, Lenken, Motorgeräusch, Aussteigen,
## Zerstörung.   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_vehicles


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	isolate_enemies([])
	var vs := get_tree().get_nodes_in_group("vehicles")
	check(vs.size() == 1, "Kübelwagen vorhanden")
	var v: Vehicle = vs[0]
	await seconds(2.0)
	var y0 := v.global_position.y
	await seconds(1.0)
	check(absf(v.global_position.y - y0) < 0.05 and v.linear_velocity.length() < 0.3, "Fahrzeug steht ruhig auf den Rädern", "y=%.2f" % v.global_position.y)

	# Einsteigen als Fahrer
	var hale := m.squad.leader()
	var entry: Interactable = v._entry
	hale.global_position = entry.global_position + v.global_basis.x * -0.6 + Vector3.UP * 0.3
	var d := entry.global_position - hale.global_position
	hale.look_yaw = atan2(-d.x, -d.z)
	await frames(10)
	check(m.controller.interact_target == entry, "Einstieg als Interaktion", str(m.controller.interact_target))
	await tap("interact")
	check(hale.vehicle == v and hale.seat_index == 0 and v.driver() == hale, "Spieler sitzt am Steuer")

	# Kamerad mit Folgebefehl steigt zu
	var kow: Soldier = m.squad.members[3]
	m.squad.brain_of(kow).set_order(SquadBrain.Order.FOLLOW)
	kow.global_position = v.global_position + v.global_basis.x * 2.5 + Vector3.UP * 0.3
	await seconds(1.5)
	check(kow.vehicle == v and kow.seat_index > 0, "Kamerad steigt als Mitfahrer zu", "Sitz %d" % kow.seat_index)

	# Fahren
	var p0 := v.global_position
	var yaw0 := v.global_rotation.y
	await hold("move_forward", 3.0)
	var moved := p0.distance_to(v.global_position)
	check(moved > 5.0, "Fahrzeug fährt", "%.1f m in 3 s" % moved)
	check((v.global_position - p0).dot(v.global_basis.z) > 0.0, "Fahrtrichtung = Motorhaube voran (+Z)")
	check(hale.global_position.distance_to(v.seat_transform(0).origin) < 1.0, "Fahrer bewegt sich mit dem Fahrzeug")
	check(kow.global_position.distance_to(v.seat_transform(kow.seat_index).origin) < 1.0, "Mitfahrer bewegt sich mit")
	yaw0 = v.global_rotation.y
	Input.action_press("move_left")
	await hold("move_forward", 0.7)
	Input.action_release("move_left")
	var turned := angle_difference(yaw0, v.global_rotation.y)
	# positiver Yaw = Drehung nach links (gegen den Uhrzeigersinn von oben)
	check(turned > 0.15, "Lenken links dreht nach links", "%.0f°" % rad_to_deg(turned))
	# Bremsen (Handbremse = Leertaste)
	Input.action_press("stance_stand")
	await seconds(2.5)
	Input.action_release("stance_stand")
	check(v.speed_kmh() < 5.0, "Handbremse bringt das Fahrzeug zum Stehen", "%.1f km/h" % v.speed_kmh())

	# Motorgeräusch alarmiert Gegner in Hörweite
	var listener := enemy("e_road")
	var lb2 := listener.get_node("EnemyBrain") as EnemyBrain
	listener.set_physics_process(true)
	listener.get_node("Perception").set_physics_process(true)
	lb2.enabled = true
	listener.global_position = v.global_position + v.global_basis.z * 30.0 + Vector3.UP * 2.0
	lb2.home_pos = listener.global_position
	lb2.set_state(EnemyBrain.State.GUARD)
	await seconds(0.5)
	await hold("move_forward", 1.5)
	check(lb2.state != EnemyBrain.State.GUARD, "Motorgeräusch weckt Gegner", EnemyBrain.STATE_NAMES[lb2.state])
	lb2.enabled = false
	listener.die(null)
	Input.action_press("stance_stand")
	await seconds(2.0)
	Input.action_release("stance_stand")

	# Aussteigen: Fahrer lässt alle aussteigen, Kamerad folgt wieder zu Fuß
	await tap("interact")
	await seconds(1.0)
	check(hale.vehicle == null and v.driver() == null, "Spieler steigt aus")
	check(kow.vehicle == null, "Mitfahrer steigt mit aus")
	check(hale.is_on_floor(), "Ausgestiegener steht auf dem Boden")

	# Zerstörung
	v.on_bullet_hit(1000.0, null)
	await frames(5)
	check(v.wrecked and not entry.can_interact(hale), "Zerschossenes Fahrzeug ist Wrack")
	_finish()
