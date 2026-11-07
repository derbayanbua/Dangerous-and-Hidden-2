extends "res://tests/test_gameplay.gd"
## B-044: Stillstand der Einzelspieler-Gegner (Wegfolge, Fortschrittswächter, erreichbare Flucht-/Such-/Automatenpunkte).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_b044
## Messwerkzeug über mehrere Missionen: tools\b044_measure.ps1 (Sonde probe_b044_stuck).


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	m.finished = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for i in 1800:
		if m.nav_ready:
			break
		await get_tree().process_frame
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health
	var w := rt.actors.get("WALKER_GUARD_1") as Soldier
	var b := w.get_node("EnemyBrain") as EnemyBrain
	var vm = rt.vm_for(w)
	if vm:
		vm.paused = true
	b.suspended = false
	b.script_control = false
	b.perception.set_physics_process(false)     # keine Ablenkung durch Wahrnehmung
	await frames(2)
	check(EnemyBrain.b044_switch() and b.b044_fix() and b.path_follow_fix, "B-044-Korrektur aktiv (Originalmission offline)")

	# 1) erreichbare Punkte
	var fwd := w.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var goal := Vector3.INF
	for k in 12:
		var p := b.reachable_point(w.global_position + fwd.rotated(Vector3.UP, k * TAU / 12.0) * 15.0)
		if p.is_finite() and b.distance_to(p) > 10.0:
			goal = p
			break
	check(goal.is_finite(), "Erreichbarer Punkt 15 m entfernt gefunden", str(goal))
	check(not b.reachable_point(w.global_position + Vector3(900, 0, 900)).is_finite(), "Punkt außerhalb der Karte = unerreichbar")

	# 2) Laufen bis ans Ziel ohne Abbruch
	b.home_pos = w.global_position
	b.set_state(EnemyBrain.State.GUARD)
	b.stationary = false
	var t0 := 0.0
	var start := w.global_position
	b.home_pos = goal          # Wache läuft zum Posten
	while t0 < 30.0 and w.global_position.distance_to(goal) > 1.6:
		await seconds(0.5)
		t0 += 0.5
	check(w.global_position.distance_to(goal) <= 1.6, "Wache erreicht den Posten (%.0f m)" % start.distance_to(goal),
		"%.1f s, Rest %.1f m, Abbrüche %d" % [t0, w.global_position.distance_to(goal), b.progress_aborts])

	# 3) Fortschrittswächter: Laufziel hinter einer Wand, die nicht im Netz ist → Abbruch statt Dauerlauf
	var dir := (start - w.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var wall := _test_block(w.global_position + dir * 1.2, Vector3(8.0, 3.0, 0.6), atan2(dir.x, dir.z))
	b.set_state(EnemyBrain.State.SEARCH)
	b.investigate_pos = start
	b._search_limit = 999.0
	b.move_to(start, Soldier.MoveMode.WALK)
	var t1 := 0.0
	var ab0 := b.progress_aborts
	while t1 < 20.0 and b._move_target.is_finite() and b._move_target.distance_to(start) < 0.5:
		await seconds(0.5)
		t1 += 0.5
	check(t1 < 20.0, "Blockiertes Laufziel wird aufgegeben bzw. neu gewählt (≤ 20 s)", "%.1f s, Abbrüche %d→%d" % [t1, ab0, b.progress_aborts])
	wall.queue_free()

	# 4) Suchpunkt bei unerreichbarem Suchort: Ersatzpunkt im Leinengebiet/um sich
	b.investigate_pos = w.global_position + Vector3(900, 0, 900)
	var sp := b._search_point()
	check(sp.is_finite() and b.distance_to(sp) > 2.5, "Suchpunkt trotz unerreichbarem Suchort", str(sp))

	# 5) Fluchtpunkt erreichbar und vom Feind weg
	var fp := b._flee_point(fwd)
	check(fp.is_finite() and b.distance_to(fp) > 5.0 and b.reachable_point(fp).is_finite(), "Fluchtpunkt erreichbar", str(fp))

	# 6) Kampfautomat: unerreichbare Position wird verworfen
	var fsm := OrigCombatFsm.new(b)
	check(not fsm._reach(w.global_position + Vector3(900, 0, 900)).is_finite() and fsm._reach(goal).is_finite(),
		"Automat: nur erreichbare Positionen")

	# 7) Untersuchen außerhalb der Leine: kein 25-s-Stillstand, Umsehen und Zustandswechsel
	b.ai_mode = EnemyBrain.Mode.DEFENSIVE
	b.sniper_enabled = false
	b.stop_moving()
	# Soldat steht schon am Leinenrand (Posten hinter ihm), Reiz weit davor
	b.home_pos = w.global_position - fwd * (b.leash_radius() - 0.5)
	b.investigate_pos = w.global_position + fwd * 40.0
	b.alert_level = 0.0
	b.set_state(EnemyBrain.State.INVESTIGATE)
	var t2 := 0.0
	while t2 < 24.0 and b.state == EnemyBrain.State.INVESTIGATE:
		await seconds(0.5)
		t2 += 0.5
	check(b.state != EnemyBrain.State.INVESTIGATE and t2 <= 10.0, "Untersuchen am Leinenrand endet nach Umsehen (≤ 10 s statt 25-s-Zeitlimit)",
		"%.1f s, Leine %.0f m" % [t2, b.leash_radius()])

	# 8) B-036c: HUMAN_Move nach HUMAN_SETAIMODE_Defensive (script_control = false) – Wache läuft den Skriptweg
	b.set_state(EnemyBrain.State.GUARD)
	b.home_pos = w.global_position
	b.script_control = false
	var sgoal := b.reachable_point(w.global_position + fwd * 10.0)
	if not sgoal.is_finite():
		sgoal = goal
	b.script_move(sgoal)
	await frames(3)
	check(not b.script_move_done(), "Skriptweg ohne script_control bleibt aktiv (Wache bricht ihn nicht ab)")
	var t3 := 0.0
	while t3 < 30.0 and not b.script_move_done():
		await seconds(0.5)
		t3 += 0.5
	check(b.distance_to(sgoal) <= 1.6, "Skriptweg ohne script_control erreicht (B-036c)", "%.1f s, Rest %.1f m" % [t3, b.distance_to(sgoal)])
	check(b.home_pos.distance_to(w.global_position) < 0.5, "Posten = erreichte Stelle nach Skriptweg")

	# 9) B-036c: Schusslinienprüfung der Trupp-KI
	var sq := m.squad.members
	if sq.size() >= 2:
		var s0 := sq[0] as Soldier
		var s1 := sq[1] as Soldier
		var sb := s0.get_node_or_null("SquadBrain") as AIBrain
		if sb == null:
			for c in s0.get_children():
				if c is SquadBrain:
					sb = c
		check(sb != null and sb.check_fire_line, "Trupp-KI prüft die Schusslinie")
		if sb:
			var aim := s0.eye_position() + s0.aim_direction() * 12.0
			s1.global_position = s0.global_position + s0.aim_direction() * 5.0
			await frames(2)
			sb._fl_t = -10.0
			check(sb.friend_in_fire_line(aim), "Kamerad 5 m in der Schusslinie → kein Feuer")
			s1.global_position = s0.global_position + s0.aim_direction() * 5.0 + s0.aim_direction().cross(Vector3.UP).normalized() * 2.0
			await frames(2)
			sb._fl_t = -10.0
			check(not sb.friend_in_fire_line(aim), "Kamerad 2 m seitlich → Feuer frei")
	_finish()
