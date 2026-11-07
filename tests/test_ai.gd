extends "res://tests/test_gameplay.gd"
## B-020: Einzelspieler-KI nach dem Original in ARCTIC1 (a1_blizzard).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_ai
## Prüft: ruhende Akteure (HUMAN_Suspend) bleiben stehen, Patrouille startet bei Spielernähe (Whenever _PlayerInRange),
## Übergabe Zombie → Defensiv nach OnAlarm (Kampf statt Wache), Aktionsradius/Suchdauer/Moduswechsel aus hd2.exe,
## Hund mit Originalanimationen (folgt, greift an, beißt < 2,1 m, stirbt), niemand fällt durch die Welt.


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for i in 1200:
		if m.nav_ready:
			break
		await get_tree().process_frame
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health
	var c: Soldier = m.squad.members[0]
	var space := m.get_viewport().world_3d.direct_space_state
	if String(Game.cli.get("phase", "")) == "fsm":
		await _run_fsm(m, rt, c, space)
		_finish()
		return
	if String(Game.cli.get("phase", "")) == "ap6":
		await _run_ap6(m, rt, c, space)
		_finish()
		return
	var start := {}
	for k in rt.actors:
		var n = rt.actors[k]
		if (n is Soldier and not m.squad.members.has(n)) or n is Dog:
			start[k] = (n as Node3D).global_position

	# 1) Ruhender Akteur bewegt sich nicht (Kanisternik lief früher mit eingefrorener Laufabsicht aus der Karte)
	var kan := rt.actors.get("KANISTERNIK") as Soldier
	var kb := kan.get_node("EnemyBrain") as EnemyBrain
	var k0 := kan.global_position
	await seconds(6.0)
	check(kb.suspended and kan.global_position.distance_to(k0) < 0.5 and kan.move_input == Vector3.ZERO,
		"HUMAN_Suspend: Kanisternik bleibt stehen", "susp=%s bewegt %.1f m" % [kb.suspended, kan.global_position.distance_to(k0)])

	# 2) Aktionsradius/Modus (hd2.exe 0x547AD0/0x547AF0/0x5484B0)
	var w1 := rt.actors.get("WALKER_GUARD_1") as Soldier
	var b1 := w1.get_node("EnemyBrain") as EnemyBrain
	var sight := float(w1.get_meta("orig_params", {}).get("sight_range", 0))
	check(b1.ai_mode == EnemyBrain.Mode.DEFENSIVE and is_equal_approx(b1.leash_radius(), minf(sight * 0.5, 50.0)),
		"Defensiv: Aktionsradius min(Sicht/2, 50) m", "%.1f m bei Sicht %.0f" % [b1.leash_radius(), sight])
	b1.ai_mode = EnemyBrain.Mode.AGGRESSIVE
	check(b1.leash_radius() == INF, "Aggressiv: Aktionsradius unbegrenzt")
	var h0 := w1.health
	w1.health = w1.max_health * 0.45
	b1._on_damaged(0.0, &"torso")
	check(b1.ai_mode == EnemyBrain.Mode.DEFENSIVE, "Aggressiv → defensiv unter 50 % Gesundheit (0x5484B0)")
	w1.health = h0
	check(not b1._in_leash(b1.home_pos + Vector3(60, 0, 0)) and b1._leash_clamp(b1.home_pos + Vector3(60, 0, 0)).distance_to(b1.home_pos) <= b1.leash_radius() + 0.01,
		"Defensiv: Ziele außerhalb des Radius werden auf den Radius zurückgeholt")
	# B-021: Zombie = Modus 0x400 (Opcode 0xCF): min(Sicht/3; 25) m
	b1.zombie_mode = true
	check(is_equal_approx(b1.leash_radius(), minf(sight / 3.0, 25.0)), "Zombie (0x400): Aktionsradius min(Sicht/3, 25) m",
		"%.1f m" % b1.leash_radius())
	b1.zombie_mode = false
	# B-021: Wahrnehmungsformel 0x5A59E0 (Sichtbarkeitsweite) und Kegel ±50° (0x570280)
	var per := w1.get_node("Perception") as Perception
	var me := (get_tree().get_nodes_in_group("team_0")[0]) as Soldier
	await get_tree().physics_frame
	check(per.orig_formula, "Originalformel aktiv (Originalmission offline)")
	# AP-7: Grundwert nach Waffenhaltung (50 weg / 70 bereit / 100 Anschlag), nicht nach Körperhaltung
	var am0 := me.aiming
	me.aiming = false
	var vr := per.orig_visibility_distance(me)
	me.aiming = true
	var va := per.orig_visibility_distance(me)
	me.aiming = am0
	check(va > vr and vr <= 70.0 + 0.01 and va <= 100.0 + 0.01 or me.seconds_since_shot() < 8.0,
		"Sichtbarkeitsweite bereit ≤ 70 m < Anschlag ≤ 100 m (× Licht)", "bereit %.1f, Anschlag %.1f" % [vr, va])

	# 3) Spielernähe hebt HUMAN_Suspend auf, Patrouille (r_arc1a_walker1.scr) läuft
	var gp := w1.global_position + Vector3(0, 0, 80)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(gp + Vector3.UP * 200, gp + Vector3.DOWN * 200, 1))
	c.global_position = (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else gp
	c.velocity = Vector3.ZERO
	c.stance_request = Soldier.Stance.PRONE
	var wp0 := w1.global_position
	await seconds(14.0)
	check(not b1.suspended, "Whenever _PlayerInRange(110): Wache wird aktiv", "susp=%s" % b1.suspended)
	check(w1.global_position.distance_to(wp0) > 2.0 or b1._alarm_notified, "Walker 1 patrouilliert (HUMAN_Move walker1_*)",
		"bewegt %.1f m, Zombie=%s, Alarm=%s" % [w1.global_position.distance_to(wp0), b1.script_control, b1._alarm_notified])

	# 4) Übergabe nach OnAlarm: Zombie → Defensiv + EndScript; die KI kämpft (vorher: blieb in „Wache“)
	var fwd := w1.aim_direction()
	fwd.y = 0.0
	var tp := w1.global_position + fwd.normalized() * 14.0
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 20, tp + Vector3.DOWN * 40, 1))
	c.global_position = (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else tp
	c.stance_request = Soldier.Stance.STAND
	var engaged := false
	for i in 40:
		await seconds(0.25)
		if not w1.alive or (b1.state == EnemyBrain.State.COMBAT and not b1.script_control):
			engaged = true
			break
	check(engaged, "Nach OnAlarm übernimmt die eigene KI (Kampf)", "Zustand %s, Zombie %s, Alarm %s, aw %.2f" % [
		b1.state_name(), b1.script_control, b1._alarm_notified, b1.perception.awareness.get(c, 0.0)])

	# 5) Hund (PES_00, Besitzer walker_guard_4): Originalanimationen, Angriff, Biss, Tod
	var dog := rt.actors.get("PES_00") as Dog
	check(dog != null and dog._anim != null and dog._anim.has_animation("run") and dog._anim.has_animation("attack"),
		"Hund mit Originalanimationen (dog_anim.sav → characters/(pes.glb)")
	if dog and dog.alive:
		var dp := dog.global_position + Vector3(4, 0, 0)
		c.global_position = dp + Vector3.UP * 0.3
		c.velocity = Vector3.ZERO
		dog.raise(c)
		var hp0 := c.health
		var saw_attack := false
		var saw_run := false
		for i in 60:
			await seconds(0.1)
			saw_attack = saw_attack or dog._cur_anim == "attack"
			saw_run = saw_run or dog._cur_anim in ["run", "walk"]
		check(saw_attack and c.health < hp0, "Hund greift an: Angriffsclip und Biss", "Clip %s, Schaden %.1f" % [dog._cur_anim, hp0 - c.health])
		check(dog.BITE_RANGE == 2.1, "Bissreichweite 2,1 m (0x5C49A0)")
		dog.apply_hit(100000.0, &"torso", c, Vector3.ZERO)
		await seconds(0.3)
		check(not dog.alive and dog._cur_anim.begins_with("death"), "Hund stirbt mit Todesclip", dog._cur_anim)

	# 6) Niemand fällt durch die Welt
	var fell: Array = []
	for k in start:
		var n = rt.actors.get(k)
		if is_instance_valid(n) and (n as Node3D).global_position.y < (start[k] as Vector3).y - 5.0:
			fell.append("%s %.1f→%.1f" % [k, (start[k] as Vector3).y, (n as Node3D).global_position.y])
	check(fell.is_empty(), "Kein Akteur fällt durch die Welt", str(fell))
	_finish()


## AP-6 (--phase=ap6): Uniformtarnung (Tarnwert), HUMAN_Attack als Kampfauftrag, HUMAN_SetSniper als Leine am Posten.
func _run_ap6(m, rt: LsRuntime, c: Soldier, space: PhysicsDirectSpaceState3D) -> void:
	var w1 := rt.actors.get("WALKER_GUARD_1") as Soldier
	var b1 := w1.get_node("EnemyBrain") as EnemyBrain
	var per := w1.get_node("Perception") as Perception
	var vm = rt.vm_for(w1)
	if vm:
		vm.paused = true
	b1.suspended = false
	b1.script_control = false
	await get_tree().physics_frame
	check(per.orig_formula, "Originalregeln aktiv")

	# 1) Formel [B]: −1 je Beobachter, +0,5 bei Feindkleidung, 0 bei Leiche/eigener Kleidung
	check(is_equal_approx(OrigDisguise.step(100.0, 0, true, false), 100.0), "Tarnwert bleibt bei 100 (Obergrenze)")
	check(is_equal_approx(OrigDisguise.step(50.0, 1, true, false), 49.5), "Ein Beobachter: netto −0,5 je Update")
	check(is_equal_approx(OrigDisguise.step(50.0, 3, true, false), 47.5), "Drei Beobachter: netto −2,5 je Update")
	check(OrigDisguise.step(80.0, 0, false, false) == 0.0, "Eigene Kleidung → 0")
	check(OrigDisguise.step(80.0, 0, true, true) == 0.0, "Leiche tragen → 0")
	check(OrigDisguise.step(0.4, 1, true, false) == 0.0, "Untergrenze 0")

	# 2) Anziehen → 100; Spieler vor der Wache: wahrgenommen, aber kein Ziel, Wert sinkt; bei 0 erkannt
	for sm in m.squad.members:
		if sm != c:
			sm.global_position += Vector3(0, 0, 400)     # andere Kameraden aus dem Blick
	# Nur WALKER_GUARD_1 beobachtet: andere Gegner (Patrouillen, die zufällig in Sicht laufen) blind schalten, sonst
	# zählt die Messung 2+ Beobachter (Abschluss 0.9.8: 2,5 s statt ≈ 6 s gemessen = zweiter Beobachter, kein Formelfehler)
	var _blinded: Array = []
	for node in get_tree().get_nodes_in_group("soldiers"):
		var o := node as Soldier
		if o and o != w1 and o.team != c.team:
			var op: Perception = o.get_node_or_null("Perception")
			if op and op.is_physics_processing():
				op.set_physics_process(false)
				op.disguise_seen.clear()
				op.visible_now.clear()
				_blinded.append(op)
	c.put_on_uniform(Color(0.36, 0.38, 0.33), "cap")
	check(c.disguised and c.disguise_value == 100.0, "Anziehen: Tarnwert sofort 100")
	var fwd := w1.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var tp := w1.global_position + fwd * 12.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 20, tp + Vector3.DOWN * 40, 1))
	c.global_position = (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else tp
	c.velocity = Vector3.ZERO
	per.awareness.erase(c)
	b1.calm_down()
	await seconds(1.0)
	check(per.disguise_seen.get(c, false) and not per.visible_now.get(c, false) and b1.state != EnemyBrain.State.COMBAT,
		"Getarnt: wahrgenommen, aber nicht als Feind erkannt", "seen=%s vis=%s state=%d wert=%.1f" % [per.disguise_seen.get(c, false), per.visible_now.get(c, false), b1.state, c.disguise_value])
	check(c.disguise_value < 100.0 and c.disguise_value > 70.0, "Tarnwert sinkt unter Beobachtung", "%.1f" % c.disguise_value)
	var t_end := 0.0
	while c.disguise_value > 0.0 and t_end < 15.0:
		await seconds(0.25)
		t_end += 0.25
	check(c.disguise_value <= 0.0 and t_end > 4.0 and t_end < 10.0, "Ein Beobachter: Tarnung nach ≈ 6–7 s aufgebraucht (30 Hz)", "%.2f s" % t_end)
	await seconds(0.6)
	check(per.awareness.get(c, 0.0) >= 1.0, "Bei Tarnwert 0 enttarnt und erkannt")
	for op in _blinded:
		if is_instance_valid(op):
			op.set_physics_process(true)
	c.disguised = false
	c.disguise_value = 0.0

	# 3) HUMAN_SetSniper(true, 5): Leine 5 m um die Postenlage, kein Anmarsch
	b1.calm_down()
	b1.set_sniper(true, 5.0)
	check(b1.leash_radius() == 5.0 and b1.home_pos.distance_to(w1.global_position) < 0.01, "SetSniper: Leine = Argument 2 m um die Postenlage")
	var post := w1.global_position
	var far := w1.global_position + fwd * 35.0
	var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(far + Vector3.UP * 20, far + Vector3.DOWN * 40, 1))
	c.global_position = (hit2.position as Vector3) + Vector3.UP * 0.3 if not hit2.is_empty() else far
	b1.script_attack(c)
	var maxd := 0.0
	for i in 40:
		await seconds(0.25)
		maxd = maxf(maxd, Vector2(w1.global_position.x - post.x, w1.global_position.z - post.z).length())
	check(maxd <= 5.0 + 1.5, "Scharfschütze verlässt den Posten nicht (≤ 5 m)", "max %.1f m" % maxd)
	b1.set_sniper(false, 5.0)
	check(b1.leash_radius() != 5.0, "SetSniper(false): Leine wieder nach KI-Modus")

	# 4) HUMAN_Attack(Ziel, ms): Kampfauftrag mit Rückmeldung nach Ablauf
	b1.calm_down()
	b1.script_attack_order(c, 1.5, false)
	await get_tree().physics_frame
	check(b1.state == EnemyBrain.State.COMBAT and b1.target == c and not b1.attack_done(), "HUMAN_Attack: Kampfauftrag auf das Ziel")
	await seconds(0.5)
	check(b1.orig_fsm != null, "HUMAN_Attack: Kampfautomat läuft", "fsm=%s" % b1.orig_fsm)
	await seconds(1.5)
	check(b1.attack_done(), "HUMAN_Attack: Rückmeldung nach Ablauf der Dauer")
	b1.script_attack_order(c, 0.6, true)
	check(b1._ill_fire_t > 0.0 and not b1.attack_done(), "HUMAN_IllFire: gezieltes Feuern (blockiert)")
	await seconds(1.0)
	check(b1.attack_done(), "HUMAN_IllFire: Rückmeldung nach Ablauf")
	check(not rt.stubbed.has("HUMAN_ATTACK") and not rt.stubbed.has("HUMAN_SETSNIPER"), "Attack/SetSniper nicht stumm")


## AP-3 (--phase=fsm): Kampfautomat 0x549AE0, Deckungswahl 0x553EB0/0x5541F0, Wahrnehmung AP-7 (feste Zufallssamen).
func _run_fsm(m, rt: LsRuntime, c: Soldier, space: PhysicsDirectSpaceState3D) -> void:
	var w1 := rt.actors.get("WALKER_GUARD_1") as Soldier
	var b1 := w1.get_node("EnemyBrain") as EnemyBrain
	var per := w1.get_node("Perception") as Perception
	var vm = rt.vm_for(w1)
	if vm:
		vm.paused = true
	b1.suspended = false
	b1.script_control = false
	await get_tree().physics_frame
	check(b1._orig_rules() and per.orig_formula, "Originalregeln aktiv (Originalmission offline)")

	# 1) Feuerpausen Zustand 5 [B]: aggressiv rand·600+200, sonst rand·2000+500 ms
	var r := RandomNumberGenerator.new()
	r.seed = 4711
	var lo_a := INF
	var hi_a := -INF
	var lo_d := INF
	var hi_d := -INF
	for i in 400:
		var a := OrigCombatFsm.fire_pause_ms(true, r)
		var d := OrigCombatFsm.fire_pause_ms(false, r)
		lo_a = minf(lo_a, a); hi_a = maxf(hi_a, a); lo_d = minf(lo_d, d); hi_d = maxf(hi_d, d)
	check(lo_a >= 200.0 and hi_a <= 800.0 and hi_a - lo_a > 500.0, "Feuerpause aggressiv 200–800 ms", "%.0f–%.0f" % [lo_a, hi_a])
	check(lo_d >= 500.0 and hi_d <= 2500.0 and hi_d - lo_d > 1700.0, "Feuerpause sonst 500–2500 ms", "%.0f–%.0f" % [lo_d, hi_d])

	# Spieler 14 m vor die Wache (wie Teil 4 der Grundphase)
	var fwd := w1.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var tp := w1.global_position + fwd * 14.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 20, tp + Vector3.DOWN * 40, 1))
	c.global_position = (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else tp
	c.velocity = Vector3.ZERO
	c.stance_request = Soldier.Stance.STAND
	await seconds(0.5)

	# 2) Flankenpunkt 0x553EB0: 5-m-Raster um das Ziel, nur abgewandte Seite, Navmesh + Sicht
	var ok_f := 0
	var bad_f := ""
	for i in 12:
		var p := OrigCombatFsm.pick_flank_point(b1, c.global_position, w1.global_position, r)
		if not p.is_finite():
			continue
		var dp := p - c.global_position
		var ds := w1.global_position - c.global_position
		dp.y = 0.0; ds.y = 0.0
		if dp.dot(ds) >= 0.0 and dp.length() <= 10.0 + 1.6:
			ok_f += 1
		else:
			bad_f += " %s" % p
	check(ok_f >= 6 and bad_f == "", "AP-48a: Flankenpunkt auf der eigenen Seite des Ziels im 5-m-Raster (0x553EB0)", "%d/12 gültig%s" % [ok_f, bad_f])

	# 3) Nachrückpunkt 0x5541F0: 10–20 m von sich, ±60° zum Ziel
	var far := w1.global_position + fwd * 40.0
	var ok_a := 0
	var bad_a := ""
	for i in 12:
		var p := OrigCombatFsm.pick_advance_point(b1, w1.global_position, far, r)
		if not p.is_finite():
			continue
		var d := p - w1.global_position
		d.y = 0.0
		if d.length() >= 10.0 - 0.01 and d.length() <= 20.0 + 0.01 and d.normalized().dot(fwd) > 0.5:
			ok_a += 1
		else:
			bad_a += " %.1f m/cos %.2f" % [d.length(), d.normalized().dot(fwd)]
	check(ok_a >= 6 and bad_a == "", "Nachrückpunkt 10–20 m, ±60° (0x5541F0)", "%d/12 gültig%s" % [ok_a, bad_a])

	# 4) AP-7 Sichtbarkeitsweite: Waffenhaltung 50/70/100, Gangfaktoren (Verhältnisse, Licht kürzt sich)
	var am0 := c.aiming
	var tool0 := c.tool
	c.aiming = true
	var v_aim := per.orig_visibility_distance(c)
	c.aiming = false
	var v_ready := per.orig_visibility_distance(c)
	c.tool = "binoculars"
	var v_away := per.orig_visibility_distance(c)
	c.tool = tool0
	c.aiming = am0
	if c.seconds_since_shot() >= 8.0 and v_ready > 0.0:
		check(is_equal_approx(v_aim / v_ready, 100.0 / 70.0) and is_equal_approx(v_away / v_ready, 50.0 / 70.0),
			"Grundwert nach Waffenhaltung 50/70/100 m", "weg %.1f bereit %.1f Anschlag %.1f" % [v_away, v_ready, v_aim])
	var mm0 := c.move_mode
	var st0 := c.stance
	c.move_mode = Soldier.MoveMode.RUN
	var g_sprint := Perception.orig_gait_factor(c)
	c.move_mode = Soldier.MoveMode.JOG
	var g_run := Perception.orig_gait_factor(c)
	c.move_mode = Soldier.MoveMode.WALK
	var g_walk := Perception.orig_gait_factor(c)
	c.stance = Soldier.Stance.CROUCH
	var g_crouch := Perception.orig_gait_factor(c)
	c.move_mode = Soldier.MoveMode.SNEAK
	var g_sneak := Perception.orig_gait_factor(c)
	c.move_mode = mm0
	c.stance = st0
	check(g_sprint == 1.8 and g_run == 1.6 and g_walk == 1.6 and g_crouch == 1.3 and g_sneak == 1.05,
		"Gangfaktoren Sprint 1,8 / Laufen 1,6 / geduckt 1,3 / Schleichen 1,05",
		"%.2f %.2f %.2f %.2f %.2f" % [g_sprint, g_run, g_walk, g_crouch, g_sneak])

	# 5) Sofortige Erkennung (keine Rampe): ein Wahrnehmungstakt genügt
	per.awareness.erase(c)
	b1.state = EnemyBrain.State.GUARD
	b1.look_at_point(c.global_position + Vector3.UP * 1.2, 1.0, 100.0)
	var instant := false
	var t0 := Time.get_ticks_msec()
	for i in 30:
		await get_tree().physics_frame
		if per.awareness.get(c, 0.0) >= 1.0:
			instant = true
			break
	var reach := minf(per.sight_range, per.orig_visibility_distance(c))
	check(instant or w1.global_position.distance_to(c.global_position) > reach,
		"Sofortige Erkennung im Kegel und in Reichweite (0x570280)",
		"aw %.2f nach %d ms, Abstand %.1f, Reichweite %.1f" % [per.awareness.get(c, 0.0), Time.get_ticks_msec() - t0,
			w1.global_position.distance_to(c.global_position), reach])

	# 6) Zustandsfolge 0 → 4 → 5 → 6 → 7 → 8 (aggressiv, Ziel = Spieler < 20 m)
	b1.ai_mode = EnemyBrain.Mode.AGGRESSIVE
	b1.target = c
	b1.state = EnemyBrain.State.GUARD
	b1.set_state(EnemyBrain.State.COMBAT)
	var fsm := OrigCombatFsm.new(b1)
	fsm.rng.seed = 20261031
	b1.orig_fsm = fsm
	fsm.start(c)
	var want := [0, 4, 5, 6, 7, 8]
	for i in 160:
		await seconds(0.25)
		if fsm.history.size() >= want.size() or b1.orig_fsm != fsm:
			break
	var head := fsm.history.slice(0, want.size())
	check(head == want, "Zustandsfolge 0→4→5→6→7→8", "Folge %s" % str(fsm.history))
	check(fsm.history.size() > 2 and fsm.history[2] == OrigCombatFsm.S_FIRE, "Feuerzustand nach Anvisieren erreicht")
	check(fsm.last_pause_ms >= 0.0 and fsm.last_pause_ms <= 800.0, "Gezogene Feuerpause aggressiv ≤ 800 ms", "%.0f ms" % fsm.last_pause_ms)
	if fsm.history.size() > 4 and fsm.history[4] == OrigCombatFsm.S_MOVE:
		check(fsm.move_point.is_finite(), "Zustand 7 läuft zu einem Flankenpunkt", str(fsm.move_point))
	# Nach 8 (aggressiv) → 9 Nachrücken
	for i in 80:
		await seconds(0.25)
		if fsm.history.has(OrigCombatFsm.S_ADVANCE) or b1.orig_fsm != fsm:
			break
	check(fsm.history.has(OrigCombatFsm.S_ADVANCE), "Aggressiv: Bewerten → Nachrücken (Zustand 9)", str(fsm.history))
	# Nachrücken endet in 10/11 → 9 (60/80 %) oder 2 → 13 → 12 (zurück zum Posten)
	var tails_ok := true
	for i in range(1, fsm.history.size()):
		var a: int = fsm.history[i - 1]
		var b: int = fsm.history[i]
		if a == OrigCombatFsm.S_ADV_ARRIVED and not (b in [OrigCombatFsm.S_ADVANCE, OrigCombatFsm.S_LOST]):
			tails_ok = false
		if a == OrigCombatFsm.S_CLOSE and not (b in [OrigCombatFsm.S_ADVANCE, OrigCombatFsm.S_LOST]):
			tails_ok = false
		if a == OrigCombatFsm.S_LOST and b != OrigCombatFsm.S_HOME:
			tails_ok = false
		if a == OrigCombatFsm.S_HOME and b != OrigCombatFsm.S_REST:
			tails_ok = false
	check(tails_ok, "Übergänge 10/11 → 9 oder 2, 2 → 13 → 12", str(fsm.history))
	# Statistik der Fortsetzung (60 %/80 %) mit festem Samen über die Zufallsquelle des Automaten
	var rs := RandomNumberGenerator.new()
	rs.seed = 99
	var n60 := 0
	for i in 2000:
		if rs.randf() < OrigCombatFsm.CONT_ADVANCE:
			n60 += 1
	check(absf(n60 / 2000.0 - 0.6) < 0.04 and OrigCombatFsm.CONT_CLOSE == 0.8, "Fortsetzung Nachrücken 60 %/80 %",
		"%.3f" % (n60 / 2000.0))
	# AP-48b: Feuern nicht nur in Zustand 5, sondern auch beim Anvisieren/Laufen (0x58C330 in 3/4/5/7)
	check(fsm.shots_allowed > 0, "AP-48b: Gegner feuert im Automaten", "Feuerbilder je Zustand %s" % str(fsm.fire_states))
	var moving_fire := 0
	for st in [OrigCombatFsm.S_APPROACH, OrigCombatFsm.S_AIM, OrigCombatFsm.S_MOVE, OrigCombatFsm.S_EVAL]:
		moving_fire += int(fsm.fire_states.get(st, 0))
	check(moving_fire > 0, "AP-48b: Feuer außerhalb von Zustand 5 (Anvisieren/Laufen/Bewerten)", str(fsm.fire_states))
	# AP-48c: Gaußgang Zustand 7 (0x549AE0) – Sprint wird nahe am Ziel zu hockend laufen, sehr nah zu geduckt schleichen
	var rg := RandomNumberGenerator.new()
	rg.seed = 5
	var g_far := OrigCombatFsm.gait_step(Soldier.Stance.STAND, Soldier.MoveMode.RUN, 400.0, rg)
	var g_mid := OrigCombatFsm.gait_step(Soldier.Stance.STAND, Soldier.MoveMode.RUN, 60.0, rg)
	var g_near := OrigCombatFsm.gait_step(Soldier.Stance.CROUCH, Soldier.MoveMode.RUN, 16.0, rg)
	check(g_far == Vector2i(Soldier.Stance.STAND, Soldier.MoveMode.RUN) and g_mid == Vector2i(Soldier.Stance.CROUCH, Soldier.MoveMode.RUN)
		and g_near == Vector2i(Soldier.Stance.CROUCH, Soldier.MoveMode.SNEAK), "AP-48c: Gaußgang Sprint → hockend → schleichen",
		"%s %s %s" % [g_far, g_mid, g_near])
	check(OrigCombatFsm.LOST_MS == Vector2(15000, 25000) and OrigCombatFsm.EVAL_MS == Vector2(1500, 3500)
		and OrigCombatFsm.REST_MS == Vector2(2000, 5000), "AP-48c: Zeitgeber aus 0x549AE0 (2: 15–25 s, 8: 1,5–3,5 s, 12: 2–5 s)")
	var b_rt := b1.reaction_time
	check(not b1.skip_reaction, "AP-48b: Reaktionssperre nur während des Automatenschusses ausgesetzt", "rt %.2f" % b_rt)
	check(OrigCombatFsm.APPROACH_MIN == 20.0 and OrigCombatFsm.CLOSE_DIST == 6.0 and OrigCombatFsm.REPORT_DIST == 30.0,
		"Schwellen 20 m / 6 m / 30 m")

	# 7) Defensiv: Zustand 8 ohne sichtbares Ziel → 2 → Heimweg; MP-/Übungs-KI unberührt (Regel nur mit LsRuntime offline)
	var d1 := OrigCombatFsm.new(b1)
	d1.rng.seed = 7
	b1.ai_mode = EnemyBrain.Mode.DEFENSIVE
	check(not d1.aggressive(), "Defensiv: Automat nicht aggressiv")
	b1.runtime = null
	check(not b1._orig_rules(), "Ohne LsRuntime (Übungseinsatz/MP): eigene Kampflogik")
	b1.runtime = rt
	# AP-48f: Stellungsposten über den Automaten, ohne Ortswechsel
	b1.ai_mode = EnemyBrain.Mode.AGGRESSIVE
	b1.stationary = true
	var p0 := w1.global_position
	var sf := OrigCombatFsm.new(b1)
	sf.rng.seed = 11
	b1.orig_fsm = sf
	b1.target = c
	b1.set_state(EnemyBrain.State.COMBAT)
	sf.start(c)
	for i in 24:
		await seconds(0.25)
	var moved := w1.global_position.distance_to(p0)
	check(sf.hold_post() and not sf.history.has(OrigCombatFsm.S_MOVE) and not sf.history.has(OrigCombatFsm.S_APPROACH)
		and moved < 0.6, "AP-48f: Stellungsposten bleibt am Platz (Automat ohne 3/7)", "Folge %s, %.2f m" % [str(sf.history.slice(0, 12)), moved])
	check(sf.history.has(OrigCombatFsm.S_FIRE), "AP-48f: Stellungsposten erreicht Feuerzustand", str(sf.history.slice(0, 12)))
	b1.stationary = false
	b1.orig_fsm = null
	# AP-48d: Fußwegenetz als Quelle der Flankenpunkte (falls in a1 geladen)
	var net := OrigCombatFsm.walk_net(b1)
	if net:
		var fp := OrigCombatFsm.pick_flank_point(b1, c.global_position, w1.global_position, r)
		var on_node := false
		for q in net.base_pos:
			if fp.is_finite() and (q as Vector3).distance_to(fp) < 0.01:
				on_node = true
				break
		check(not fp.is_finite() or on_node or net.nearest_node(c.global_position, OrigCombatFsm.FLANK_GRID) < 0,
			"AP-48d: Flankenpunkt = Knoten des Fußwegenetzes", str(fp))
	print("FSM-Folge: %s, Aktion7 %d" % [str(fsm.history), fsm.action7_count])
