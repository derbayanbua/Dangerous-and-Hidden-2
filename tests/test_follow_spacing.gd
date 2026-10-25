extends "res://tests/test_systems.gd"
## B-019: Folgen mit Abstand. Formation nach den Originaltabellen (hd2.exe 0x8AB1D0, Stufe 3 = 3,75 m), Trennung 1,2 m,
## keine Klumpen, kein Hintereinanderlaufen auf einem Punkt, festhängende Kameraden lösen sich.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_follow_spacing


func _pair_min(list: Array) -> float:
	var md := INF
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Vector3 = list[i].global_position
			var b: Vector3 = list[j].global_position
			md = minf(md, Vector2(a.x - b.x, a.z - b.z).length())
	return md


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	for i in 1500:
		if m.nav_ready:
			break
		await frames(1)
	isolate_enemies([])
	var c: PlayerController = m.controller
	var sq := m.squad
	var lead := sq.leader()
	c.set_active(lead)
	check(sq.formation == SquadManager.Formation.WEDGE and is_equal_approx(sq.spacing, 3.75),
		"Startformation wie Original: Pfeil, Stufe 3 = 3,75 m", "%d %.2f" % [sq.formation, sq.spacing])
	var mates: Array[Soldier] = []
	for mm in sq.members:
		if mm != lead:
			mates.append(mm)
	# --- 1. Klumpen auflösen: alle Kameraden auf (fast) einem Punkt ---
	place(lead, -12, 18, -PI * 0.5)        # blickt nach Osten (Ebnungszone z ≈ 20, x −25…25)
	for i in mates.size():
		mates[i].global_position = m.lb.ground(-18.0 + i * 0.25, 18.0 + i * 0.1, 0.3)
		mates[i].velocity = Vector3.ZERO
		sq.brain_of(mates[i]).clear_tasks()
		sq.brain_of(mates[i]).set_order(SquadBrain.Order.FOLLOW)
	var all: Array = [lead] + mates
	var d_start := _pair_min(mates)
	await seconds(4.0)
	var d_after := _pair_min(all)
	check(d_start < 0.6 and d_after >= 1.0, "Klumpen löst sich: Mindestabstand nach 4 s ≥ 1,0 m", "%.2f → %.2f m" % [d_start, d_after])
	var near_slot := true
	var info := []
	for mm in mates:
		var dd := mm.global_position.distance_to(sq.formation_slot(mm, lead))
		info.append("%s %.1f" % [mm.soldier_name, dd])
		near_slot = near_slot and dd < 2.5
	check(near_slot, "Kameraden stehen auf ihren Formationsplätzen", ", ".join(info))

	# --- 2. Anführer läuft 30 m (Pfeil): alle folgen, Abstand bleibt ---
	var start := {}
	for mm in mates:
		start[mm] = mm.global_position
	var min_seen := INF
	var close_time := 0.0
	Input.action_press("move_forward")
	for k in 420:                          # 7 s ≈ 23 m
		await frames(1)
		var md := _pair_min(all)
		min_seen = minf(min_seen, md)
		if md < 0.8:
			close_time += 1.0 / 60.0
	Input.action_release("move_forward")
	await seconds(3.0)
	var moved := true
	var at_slot := true
	info = []
	for mm in mates:
		var mv: float = mm.global_position.distance_to(start[mm])
		var ds := mm.global_position.distance_to(sq.formation_slot(mm, lead))
		info.append("%s %.0f m/%.1f" % [mm.soldier_name, mv, ds])
		moved = moved and mv > 12.0
		at_slot = at_slot and ds < 3.0
	check(moved and at_slot, "Folgen: alle laufen mit und erreichen ihre Plätze (Pfeil)", ", ".join(info))
	check(close_time < 1.0 and min_seen > 0.5, "Unterwegs keine Klumpen (Abstand < 0,8 m höchstens kurz)",
		"min %.2f m, %.1f s zu nah" % [min_seen, close_time])

	# --- 3. Kolonne: Abstände 3,75 m hintereinander, nicht auf einem Punkt ---
	sq.set_formation(SquadManager.Formation.COLUMN)
	lead.look_yaw = PI * 0.5               # nach Westen zurück
	Input.action_press("move_forward")
	await seconds(5.0)
	Input.action_release("move_forward")
	await seconds(8.0)
	var gaps := []
	var col_ok := true
	var prev: Soldier = lead
	for mm in sq._followers(lead):
		var g := Vector2(mm.global_position.x - prev.global_position.x, mm.global_position.z - prev.global_position.z).length()
		gaps.append("%.1f" % g)
		col_ok = col_ok and g > 2.0 and g < 6.0
		prev = mm
	check(col_ok and _pair_min(all) >= 1.0, "Kolonne: Abstand je ≈ 3,75 m (2–6 m), keiner auf einem Punkt", " ".join(gaps))

	# --- 4. Festhängen: Hindernis zwischen Kamerad und Platz → löst sich ---
	sq.set_formation(SquadManager.Formation.WEDGE)
	place(lead, 10, 20, 0.0)
	var stuck := mates[0]
	var sb := sq.brain_of(stuck)
	sb.clear_tasks()
	sb.set_order(SquadBrain.Order.FOLLOW)
	sb.follow_unsticks = 0
	stuck.global_position = m.lb.ground(10, 34, 0.3)
	stuck.velocity = Vector3.ZERO
	# Wand (6 m, wie ein abgestelltes Fahrzeug – nicht im Navigationsnetz) direkt zwischen Kamerad und Platz
	var walls: Array = [
		_test_block(m.lb.ground(7.0, 31.5, 0.0), Vector3(6.0, 2.5, 0.5), 0.0),
	]
	var reached := false
	for k in 25 * 60:
		await frames(1)
		if stuck.global_position.distance_to(sq.formation_slot(stuck, lead)) < 3.0:
			reached = true
			break
		if k % 120 == 0:
			print("  [stuck] t=%.0f pos=%s slot=%s stage=%d ut=%s v=%.2f" % [k / 60.0, stuck.global_position, sq.formation_slot(stuck, lead),
				sb._unstick_stage, sb._unstick_target, Vector2(stuck.velocity.x, stuck.velocity.z).length()])
	check(reached, "Blockierter Kamerad löst sich und erreicht seinen Platz (≤ 25 s)",
		"Lösungsversuche %d, Rest %.1f m" % [sb.follow_unsticks, stuck.global_position.distance_to(sq.formation_slot(stuck, lead))])
	for w in walls:
		(w as Node).queue_free()

	# --- 5. Zwei Kameraden blockieren sich gegenseitig in einem 1-m-Durchgang → beide kommen durch ---
	# Kolonne nach Norden: alle Plätze liegen auf x = 0 genau hinter der Lücke → beide müssen gleichzeitig hindurch
	sq.set_formation(SquadManager.Formation.COLUMN)
	place(lead, 0, 4, 0.0)
	for mm in mates:
		if mm != mates[1] and mm != mates[2]:
			sq.brain_of(mm).set_order(SquadBrain.Order.HOLD)
	var a := mates[1]
	var b := mates[2] if mates.size() > 2 else mates[0]
	for s in [a, b]:
		sq.brain_of(s).clear_tasks()
		sq.brain_of(s).set_order(SquadBrain.Order.FOLLOW)
	a.global_position = m.lb.ground(-0.3, 26, 0.3)
	b.global_position = m.lb.ground(0.3, 26.4, 0.3)
	var gate: Array = [
		_test_block(m.lb.ground(-3.0, 22, 0.0), Vector3(5.0, 2.5, 0.4), 0.0),
		_test_block(m.lb.ground(3.0, 22, 0.0), Vector3(5.0, 2.5, 0.4), 0.0),
	]
	var through := false
	for k in 25 * 60:
		await frames(1)
		if a.global_position.z < 21.0 and b.global_position.z < 21.0:
			through = true
			break
		if k % 180 == 0:
			print("  [gate] t=%.0f a=%s b=%s" % [k / 60.0, a.global_position, b.global_position])
	check(through, "Engstelle: beide Kameraden kommen durch (kein dauerhaftes Gegenseitig-Blockieren)",
		"z %.1f / %.1f" % [a.global_position.z, b.global_position.z])
	for w in gate:
		(w as Node).queue_free()
	_finish()
