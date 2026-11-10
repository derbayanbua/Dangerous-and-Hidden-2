extends "res://tests/test_gameplay.gd"
## AF1-Verteidiger (0.10.3): Gehör → Alarm (Suche + OnAlarm), kein Herabstufen auf „Untersucht“ unter Dauerfeuer;
## Zombie (0x400) kämpft selbst bei Sicht.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_af1_defenders


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
	await seconds(2.0)
	var c: Soldier = m.squad.leader()
	for sm in m.squad.members:
		sm.max_health = 1.0e9
		sm.health = sm.max_health
		var sb = sm.get_node_or_null("SquadBrain")
		if sb:
			sb.set("fire_at_will", false)
	var defender: EnemyBrain = null
	var zombie: EnemyBrain = null
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive or s.team == c.team:
			continue
		var eb := s.get_node_or_null("EnemyBrain") as EnemyBrain
		if eb == null or eb.suspended:
			continue
		if defender == null and not eb.script_control and not eb.stationary and eb.state == EnemyBrain.State.GUARD:
			defender = eb
		if zombie == null and eb.script_control and eb.zombie_mode:
			zombie = eb
	check(defender != null, "ruhiger defensiver Verteidiger gefunden", str(defender.soldier.name) if defender else "")
	check(zombie != null, "nicht ruhender Zombie gefunden", str(zombie.soldier.name) if zombie else "")
	# Führer außer Sicht weit weg (nur Geräusche), Dauerfeuer 30 m neben dem Verteidiger
	c.global_position = Vector3(0, -500, 0)
	if defender:
		var src := defender.soldier.global_position + Vector3(30, 0, 0)
		var states := {}
		for k in 20:
			Events.emit_noise(src, 120.0, c, c.team, &"gunshot")
			await seconds(0.3)
			states[defender.state_name()] = true
		check(defender.state == EnemyBrain.State.SEARCH, "Dauerfeuer: Verteidiger bleibt alarmiert (Suche)", str(states))
		check(not states.has("Untersucht"), "kein Herabstufen auf Untersucht", str(states))
		check(defender.last_alarm_type == EnemyBrain.AL_SHOT or defender.last_alarm_type == EnemyBrain.AL_NEAR_SHOT \
			or not defender.script_alarm_enabled or (defender.alarm_mask & EnemyBrain.AL_SHOT) == 0,
			"OnAlarm (Art Schuss) an das Skript", "Art %d" % defender.last_alarm_type)
	if zombie:
		var zs := zombie.soldier
		var fwd := zs.aim_direction()
		fwd.y = 0.0
		c.global_position = zs.global_position + fwd.normalized() * 12.0
		c.last_shot_time = Time.get_ticks_msec() / 1000.0
		zombie.perception.awareness[c] = 1.0
		zombie.perception.last_known[c] = c.global_position
		zombie._on_detected(c)
		await seconds(1.5)
		check(zombie.state == EnemyBrain.State.COMBAT, "Zombie bei Sicht im Kampf", zombie.state_name())
		check(zombie.orig_fsm != null, "Zombie läuft über den Kampfautomaten (nicht nur Skript)")
		check(zombie.leash_radius() <= 25.0, "Zombie-Leine ≤ 25 m", "%.1f" % zombie.leash_radius())
	_finish()
