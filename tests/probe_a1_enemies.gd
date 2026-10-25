extends "res://tests/test_gameplay.gd"
## B-020 Bestandsaufnahme: alle Gegner/neutralen Figuren/Hunde in a1_blizzard (ARCTIC1).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=probe_a1_enemies [--probe_secs=40] [--react=1]
## Je Akteur: Seite, Modus (Zombie/Suspend/Zustand), Lage am Start und nach N s, Bodenabstand (Durchfallen),
## Skript-VM (wartet/beendet). --react=1: setzt nacheinander einen Kommando 12 m vor jeden Gegner (Sicht) und prüft,
## ob er binnen 6 s reagiert (Erkennung/Alarm/Kampf). Ergebnis zusätzlich nach test_output/a1_enemies.txt.

var _lines: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> String:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 300.0, 1))
	return "-" if hit.is_empty() else "%.2f" % (p.y - (hit.position as Vector3).y)


func _desc(rt: LsRuntime, nm: String, n: Node, space: PhysicsDirectSpaceState3D) -> String:
	var vm = rt.vm_for(n) if rt.has_method("vm_for") else null
	var vms := "-"
	if vm:
		vms = "fertig" if (vm.ended or vm.terminated) else ("pausiert" if vm.get("paused") else "läuft")
	if n is Soldier:
		var s := n as Soldier
		var b := s.get_node_or_null("EnemyBrain") as EnemyBrain
		var st := "-"
		if b:
			st = "%s zombie=%s susp=%s alarm=%s ziel=%s" % [b.state_name(), b.script_control, b.suspended, b._alarm_notified,
				"ja" if b.has_move_target() else "nein"]
		return "%-22s team=%d alive=%s pos=%s boden=%s %s vm=%s" % [nm, s.team, s.alive, s.global_position.snapped(Vector3.ONE * 0.1),
			_ground(space, s.global_position), st, vms]
	if n is Dog:
		var d := n as Dog
		return "%-22s HUND alive=%s pos=%s boden=%s susp=%s alarm=%s lie=%s owner=%s vm=%s" % [nm, d.alive,
			d.global_position.snapped(Vector3.ONE * 0.1), _ground(space, d.global_position), d.suspended, d.alarmed, d.lying,
			d.owner_frame.name if is_instance_valid(d.owner_frame) else "-", vms]
	return ""


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
	await seconds(1.0)
	var space := m.get_viewport().world_3d.direct_space_state
	var names: Array = []
	for k in rt.actors:
		var n = rt.actors[k]
		if (n is Soldier and not m.squad.members.has(n)) or n is Dog:
			if not names.has(k):
				names.append(k)
	names.sort()
	var start := {}
	_log("== START (%d Akteure)" % names.size())
	for k in names:
		var n: Node3D = rt.actors[k]
		start[k] = n.global_position
		_log(_desc(rt, k, n, space))
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health
	var secs := float(Game.cli.get("probe_secs", "40"))
	await seconds(secs)
	_log("== NACH %.0f s" % secs)
	var fell: Array = []
	for k in names:
		var n: Node3D = rt.actors[k]
		if not is_instance_valid(n):
			_log("%-22s ENTFERNT" % k)
			continue
		var moved: float = n.global_position.distance_to(start[k])
		_log(_desc(rt, k, n, space) + " bewegt=%.1f" % moved)
		if n.global_position.y < (start[k] as Vector3).y - 5.0:
			fell.append(k)
	check(fell.is_empty(), "Kein Akteur fällt durch die Welt", str(fell))
	if Game.cli.get("approach", "1") == "1":
		# Spieler 70 m entfernt (Whenever _PlayerInRange(110) hebt HUMAN_Suspend auf), 25 s beobachten: Patrouillen
		# laufen, niemand fällt durch die Welt
		_log("== ANNÄHERUNG (Kommando 70 m entfernt, 25 s)")
		var c0: Soldier = m.squad.members[0]
		var groups := [Vector3(-20, 0, -80), Vector3(40, 0, -30), Vector3(-150, 0, 80), Vector3(-190, 0, 0), Vector3(20, 0, -130),
			Vector3(110, 0, 8), Vector3(190, 0, 0)]
		for g in groups:
			var hp := Vector3(g.x, 200, g.z + 70.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(hp, hp + Vector3.DOWN * 400.0, 1))
			c0.global_position = (hit.position as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else Vector3(g.x, 10, g.z + 70)
			c0.velocity = Vector3.ZERO
			for k in names:
				var n0 = rt.actors.get(k)
				if is_instance_valid(n0):
					start[k] = (n0 as Node3D).global_position
			await seconds(25.0)
			for k in names:
				var n1 = rt.actors.get(k)
				if not is_instance_valid(n1) or (n1 as Node3D).global_position.distance_to(g) > 60.0:
					continue
				var mv: float = (n1 as Node3D).global_position.distance_to(start[k])
				_log("  @%s %s bewegt=%.1f" % [g, _desc(rt, k, n1, space), mv])
				if (n1 as Node3D).global_position.y < (start[k] as Vector3).y - 5.0 and not fell.has(k):
					fell.append(k)
		check(fell.is_empty(), "Annäherung: kein Akteur fällt durch die Welt", str(fell))
	if Game.cli.get("react", "0") == "1":
		_log("== REAKTION (Kommando 12 m vor dem Gegner, 6 s)")
		var c: Soldier = m.squad.members[0]
		var dead: Array = []
		for k in names:
			var s := rt.actors.get(k) as Soldier
			if not is_instance_valid(s) or not s.alive or s.team != Soldier.TEAM_AXIS:
				continue
			var b := s.get_node("EnemyBrain") as EnemyBrain
			var fwd := s.aim_direction()
			fwd.y = 0
			c.global_position = s.global_position + fwd.normalized() * 12.0 + Vector3.UP * 0.5
			c.velocity = Vector3.ZERO
			var a0: float = b.perception.awareness.get(c, 0.0)
			await seconds(6.0)
			if not is_instance_valid(s) or not is_instance_valid(b):
				_log("%-22s entfernt" % k)
				continue
			var reacted: bool = b.state == EnemyBrain.State.COMBAT or b._alarm_notified or b.perception.awareness.get(c, 0.0) >= 1.0
			_log("%-22s reagiert=%s aw=%.2f->%.2f zustand=%s zombie=%s susp=%s" % [k, reacted, a0,
				b.perception.awareness.get(c, 0.0), b.state_name(), b.script_control, b.suspended])
			if not reacted:
				dead.append(k)
			c.health = c.max_health
		_log("Nicht reagiert: %s" % str(dead))
	var f := FileAccess.open("res://test_output/a1_enemies.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
	_finish()
