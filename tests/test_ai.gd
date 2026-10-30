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
	var st0 := me.stance
	me.stance = Soldier.Stance.PRONE
	var vp := per.orig_visibility_distance(me)
	me.stance = Soldier.Stance.STAND
	var vs := per.orig_visibility_distance(me)
	me.stance = st0
	check(vs > vp and vp <= 50.0 + 0.01 and vs <= 100.0 + 0.01 or me.seconds_since_shot() < 8.0,
		"Sichtbarkeitsweite liegend ≤ 50 m < stehend ≤ 100 m (× Licht)", "liegend %.1f, stehend %.1f" % [vp, vs])

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
