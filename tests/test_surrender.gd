extends "res://tests/test_gameplay.gd"
## Ergeben, Gefangennahme, Uniform nur von Gefangenen (Vorgabe Auftraggeber; Original hd2.exe 0x4BF670/0x54B8F0,
## docs/re_notes_ai.md §1). Leichen: Durchsuchen/Munition ja, Uniform nein.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_surrender


func place(s: Soldier, x: float, z: float, yaw: float) -> void:
	s.global_position = mission().lb.ground(x, z, 0.3)
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func reset_enemy(e: Soldier, x: float, z: float, yaw: float) -> EnemyBrain:
	var b := e.get_node("EnemyBrain") as EnemyBrain
	place(e, x, z, yaw)
	e.set_physics_process(true)
	e.get_node("Perception").set_physics_process(true)
	(e.get_node("Perception") as Perception).awareness.clear()
	b.enabled = true
	b.patrol_points = PackedVector3Array()
	b.home_pos = e.global_position
	b.home_yaw = yaw
	b.stop_moving()
	b.set_state(EnemyBrain.State.GUARD)
	return b


## Leader zielt mit der Waffe auf die Brust des Gegners
func aim_at(s: Soldier, t: Soldier) -> void:
	var to := (t.global_position + Vector3.UP * 1.1) - s.eye_position()
	s.look_yaw = atan2(-to.x, -to.z)
	s.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	isolate_enemies([])
	var hale := m.squad.leader()
	for mm in m.squad.members:
		if mm != hale:
			var sb := m.squad.brain_of(mm)
			sb.roe = SquadBrain.ROE.HOLD_FIRE
			sb.set_order(SquadBrain.Order.HOLD)
			place(mm, -100 + m.squad.members.find(mm) * 2.0, 100, 0.0)
			sb.hold_pos = mm.global_position
	hale.select_slot(WeaponData.Slot.PRIMARY)

	# --- 1. Leiche: durchsuchen ja, Uniform nein ---
	var dead := m.enemies[0]
	reset_enemy(dead, 6, 20, 0.0)
	place(hale, 5, 21, 0.0)
	dead.die(hale)
	await frames(3)
	var loot: Pickups.Loot = null
	for c in dead.get_children():
		if c is Pickups.Loot:
			loot = c
	check(loot != null and loot.can_interact(hale), "Leiche durchsuchbar")
	loot.interact(hale)
	check(loot.looted, "Leiche durchsucht (Munition/Gegenstände)")
	check(not loot.can_interact(hale), "Leiche: keine Uniform anbietbar (nur von Gefangenen)")
	loot.interact(hale)
	check(not hale.disguised, "Uniform eines Toten kann nicht angezogen werden")

	# --- 2. Moral < 20 (Original-Akteurwert, z. B. CZECH1 Ge_7 = 5): sieht den Feind unter 15 m -> ergibt sich ---
	# Original: Moral bleibt im Einsatz konstant (re_notes_ai §1); Panik nur bei Moral < 20 oder ohne Waffe [B]
	var e := m.enemies[1]
	var b := reset_enemy(e, 10, 20, -PI * 0.5)      # blickt nach Osten zum Spieler
	b.morale = 5.0
	b.morale_initial = 5.0
	check(b.capture_action != null, "Gegner hat die Aktion „Gefangennehmen“")
	place(hale, 18, 20, PI * 0.5)
	var per: Perception = e.get_node("Perception")
	per.awareness[hale] = 1.0
	per.last_known[hale] = hale.global_position
	b.target = hale
	var t := 0.0
	while t < 3.0 and not b.surrendered:
		per.awareness[hale] = 1.0
		await frames(6)
		t += 0.1
	check(b.surrendered and e.has_meta("hands_up"), "Moral 5 + gesehener Feind (8 m): ergibt sich", "%.1f s" % t)
	check(e.team == Soldier.TEAM_NEUTRAL, "Ergebener ist kein Ziel mehr für die Trupp-KI (neutral)")
	check(t >= 0.3, "Hände hoch nach Original-Verzögerung (300 ms)", "%.1f s" % t)
	await seconds(1.0)
	check(b.surrendered and not e.trigger and e.alive, "Ergebener bleibt stehen und schießt nicht")
	var ca: Interactable = b.capture_action
	await frames(2)
	check(ca.can_interact(hale) and ca.prompt == OrigInteractive.text(7038, "Gefangennehmen"),
		"Aktion „Gefangennehmen“ (T7038) verfügbar", ca.prompt)
	ca.interact(hale)
	await frames(2)
	check(b.captured and e.weapons.all(func(w): return w == null or w.data.action == WeaponData.Action.MELEE),
		"Gefangen genommen: Waffen abgegeben")
	await seconds(0.6)
	check(e.stance == Soldier.Stance.CROUCH, "Gefangener kniet")
	check(ca.prompt == OrigInteractive.text(7043, "Suchen & Mun. sammeln"), "Danach: Durchsuchen (T7043)", ca.prompt)
	ca.interact(hale)
	await frames(2)
	check(ca.prompt == OrigInteractive.text(7044, "Uniform benutzen") and ca.can_interact(hale), "Danach: Uniform benutzen (T7044)", ca.prompt)
	e.set_meta("orig_uniform", 129)
	ca.interact(hale)
	await frames(3)
	check(hale.disguised, "Uniform vom Gefangenen angezogen (Tarnung)")
	check(hale.get_meta("orig_items", []).has(129), "Uniform zählt als Originalgegenstand (_IsInInventory)")
	check(b.uniform_taken and not ca.can_interact(m.squad.members[1]), "Uniform nur einmal vergeben")

	# --- 3. Moral 80 (Standard), bewaffnet: Anvisieren aus 8 m bewirkt nichts (keine Moraländerung im Original) ---
	hale.disguised = false
	var e2 := m.enemies[2]
	var b2 := reset_enemy(e2, 10, 26, -PI * 0.5)
	b2.morale = 80.0
	b2.morale_initial = 80.0
	b2.enabled = false        # nicht zurückschießen lassen, nur Ergeben-Prüfung
	var per2: Perception = e2.get_node("Perception")
	per2.awareness[hale] = 1.0
	per2.last_known[hale] = hale.global_position
	place(hale, 18, 26, PI * 0.5)
	Input.action_press("aim")
	for i in 20:
		aim_at(hale, e2)
		per2.awareness[hale] = 1.0
		await frames(3)
		b2._check_surrender()
	Input.action_release("aim")
	check(not b2.surrendered and b2._surrender_delay < 0.0, "Moral 80, bewaffnet: ergibt sich nicht (auch nicht angezielt)")
	b2.morale = 80.0
	check(is_equal_approx(b2.morale, 80.0), "Moral bleibt konstant")
	# Unbewaffnet: Panik (0x54B730) -> ergibt sich bei Feind unter 15 m
	for i in e2.weapons.size():
		if e2.weapons[i] and e2.weapons[i].data.action != WeaponData.Action.MELEE:
			e2.weapons[i] = null
	e2._on_weapon_switched()
	for i in 10:
		per2.awareness[hale] = 1.0
		b2._check_surrender()
		await frames(3)
	await frames(30)
	check(b2.surrendered, "Unbewaffneter Gegner (Moral 80) ergibt sich bei Feind unter 15 m")
	# Anfangsmoral ≥ 90 (Flag 1, z. B. „Sehr schwer“): Moral 100 → nie Panik
	var e3 := m.enemies[3]
	var b3 := reset_enemy(e3, 12, 30, -PI * 0.5)
	b3.morale = 100.0
	b3.morale_initial = 100.0
	b3.enabled = false
	var per3: Perception = e3.get_node("Perception")
	place(hale, 20, 30, PI * 0.5)
	for i in 20:
		per3.awareness[hale] = 1.0
		per3.last_known[hale] = hale.global_position
		b3._check_surrender()
		await frames(3)
	await frames(30)
	check(not b3.surrendered, "Anfangsmoral ≥ 90 (Flag 1): keine Panik, kein Ergeben")
	# --- 4. Beschuss eines Ergebenen: bewaffnet -> Gegenwehr ---
	var e4 := m.enemies[4]
	var b4 := reset_enemy(e4, 14, 34, PI * 0.5)
	b4.surrender(hale)
	check(b4.surrendered and e4.team == Soldier.TEAM_NEUTRAL, "surrender(): Hände hoch")
	e4.apply_hit(5.0, &"torso", hale, Vector3.ZERO)
	await frames(3)
	check(not b4.surrendered and e4.team == Soldier.TEAM_AXIS and b4.state == EnemyBrain.State.COMBAT,
		"Beschossener Ergebener wehrt sich (Original 0x54B820)", "Zustand %s" % b4.state_name())
	b4.enabled = false

	# --- 5. Töten Wehrloser kostet Erfahrung (Original 0x5A0BE0) ---
	hale.training.erase("prisoner_kills")
	e.die(hale)
	await frames(2)
	check(float(hale.training.get("prisoner_kills", 0.0)) >= 1.0, "Getöteter Gefangener wird gezählt")
	check(SAS.experience_gain({"prisoner_kills": 1.0}, true, true) == -1000 and SAS.experience_gain({"defenseless_kills": 1.0}, true, true) == -500,
		"Erfahrung: Gefangener −1000, Ergebener −500")
	# Gefangene zählen nicht als lebende Gegner (Original-Ziele „alle Gegner ausschalten“)
	check(e2.has_meta("hands_up"), "Ergebener markiert (zählt nicht bei _GetNumLiveEnemies)")
	_finish()
