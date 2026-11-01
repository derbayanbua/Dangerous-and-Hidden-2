extends "res://tests/test_gameplay.gd"
## B-031 / AP-2: Alarmweitergabe nach dem Original (keine kartenweite Kaskade, GAP_REA_2026-10-31 §2).
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_alarm_orig
## Prüft in einer Originalmission (offline): Alarm bleibt beim Auslöser; andere Gegner erfahren davon nur über ihr
## eigenes Gehör (Zuruf in Hörweite) – kein Events.alarm_raised, keine Rundmeldung. Leiser Schuss in 40 m weckt niemanden.
## HUMAN_SetAlarm (Skript) alarmiert den Skriptakteur (OnAlarm bei gesetztem Bit).

var _global_alarms := 0


func _ground(p: Vector3) -> Vector3:
	var space := mission().get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 200, p + Vector3.DOWN * 200, 1))
	return (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else p


func _prep(s: Soldier, p: Vector3, hear: float) -> EnemyBrain:
	var b := s.get_node("EnemyBrain") as EnemyBrain
	var per := s.get_node("Perception") as Perception
	s.global_position = _ground(p)
	s.velocity = Vector3.ZERO
	s.set_physics_process(true)
	per.set_physics_process(true)
	per.awareness.clear()
	per.sight_range = 0.5          # blind: nur das Gehör zählt
	per.hear_range = hear
	b.enabled = true
	b.script_control = false
	b.suspended = false
	b.patrol_points = PackedVector3Array()
	b.home_pos = s.global_position
	b.stop_moving()
	b.set_state(EnemyBrain.State.GUARD)
	b.alert_level = 0.0
	b._call_cooldown = 0.0
	return b


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
	Events.alarm_raised.connect(func(_p, _b): _global_alarms += 1)
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health
	check(m.orig_alarm_rules(), "Originalregel aktiv (Originalmission offline)")

	var pool: Array[Soldier] = []
	for e in m.enemies:
		if e.alive and e.get_node_or_null("EnemyBrain"):
			pool.append(e)
	check(pool.size() >= 4, "mindestens 4 Gegner", str(pool.size()))
	if pool.size() < 4:
		_finish()
		return
	isolate_enemies([])
	var A := pool[0]
	var B := pool[1]
	var C := pool[2]
	var D := pool[3]
	var base := m.squad.leader().global_position + Vector3(0, 0, 150)
	var ba := _prep(A, base, 40.0)
	var bb := _prep(B, base + Vector3(60, 0, 0), 40.0)
	var bc := _prep(C, base + Vector3(-20, 0, 0), 40.0)
	await seconds(0.5)

	# 1) Leiser Schuss (Schalldämpfer, Radius 15) in 40 m: über Hörweite·Radius/60 hinaus → niemand reagiert
	var shot_pos := A.global_position + Vector3(0, 0, 40)
	Events.emit_noise(shot_pos, 15.0, m.squad.leader(), m.squad.leader().team, &"gunshot")
	await seconds(1.0)
	check(ba.state == EnemyBrain.State.GUARD and bb.state == EnemyBrain.State.GUARD and bc.state == EnemyBrain.State.GUARD,
		"Schuss mit Schalldämpfer in 40 m weckt niemanden",
		"%s/%s/%s" % [ba.state_name(), bb.state_name(), bc.state_name()])

	# 2) Leichenfund bei A: nur A alarmiert, Zuruf in Hörweite → C (20 m) sucht, B (60 m > Hörweite 40) bleibt ruhig
	ba._raise_alarm("Leiche gefunden")
	await seconds(1.0)
	check(_global_alarms == 0, "keine kartenweite Rundmeldung (Events.alarm_raised)", str(_global_alarms))
	check(ba.state == EnemyBrain.State.SEARCH and ba.alert_level >= 1.0, "Finder ist alarmiert und sucht", ba.state_name())
	check(bc.state == EnemyBrain.State.SEARCH, "Gegner in Hörweite hört den Zuruf", bc.state_name())
	check(bb.state == EnemyBrain.State.GUARD and bb.alert_level < 0.5, "Gegner in 60 m (außer Hörweite) bleibt ruhig", bb.state_name())
	check(m.stats.get("alarm", false), "Alarm in der Statistik vermerkt")

	# 3) Gehörter Schuss alarmiert den Hörer selbst
	_prep(B, base + Vector3(60, 0, 0), 40.0)
	Events.emit_noise(B.global_position + Vector3(0, 0, 10), 300.0, m.squad.leader(), m.squad.leader().team, &"gunshot")
	await seconds(1.0)
	check(bb.state != EnemyBrain.State.GUARD and bb.alert_level >= 1.0, "gehörter Schuss alarmiert den Hörer", bb.state_name())

	# 4) Skript-Alarm (HUMAN_SetAlarm → mission.raise_alarm): Skriptakteur bekommt OnAlarm (Bit gesetzt), keine Rundmeldung
	var bd := _prep(D, base + Vector3(0, 0, 200), 40.0)
	bd.script_control = true
	bd.script_alarm_enabled = true
	bd.events_enabled = true
	bd.alarm_mask = 0x3FF
	bd._alarm_notified = false
	bd._stimulus = 0
	m.raise_alarm(D.global_position, D)
	await frames(2)
	check(bd._alarm_notified and bd.last_alarm_type == EnemyBrain.AL_SHOT, "HUMAN_SetAlarm: Skriptakteur erhält OnAlarm",
		"notified=%s Art %d" % [bd._alarm_notified, bd.last_alarm_type])
	check(_global_alarms == 0, "Skript-Alarm bleibt lokal", str(_global_alarms))
	_finish()
