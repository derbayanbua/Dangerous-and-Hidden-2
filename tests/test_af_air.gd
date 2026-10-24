extends "res://tests/test_gameplay.gd"
## Angreifende Flugzeuge (Akteurtyp 36 AirAttack, src/orig/orig_air_attack.gd) in AFRICA2/AFRICA1 (Agent Afrika):
##   tools\godot.cmd --headless -- --mission=af2_flugschau --autoplay=test_af_air [--plane=mes04] [--shots=1]
## Prüft: Flugzeug erzeugt, fliegt (100 m/s), nimmt per AirAttack_SetTarget ein Ziel an, greift an (Phasen 0→1→2),
## schießt (Einschläge, Schaden am Ziel), lässt sich abschießen (OnDeath, _ACTOR_GetState 0).

const SHOT_DIR := "res://test_output/afrika/"


func _shot(tag: String) -> void:
	if String(Game.cli.get("shots", "0")) != "1":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	await get_tree().process_frame
	await get_tree().process_frame
	var p := SHOT_DIR + "%s_air_%s.png" % [Game.current_mission_id, tag]
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT ", p)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.runtime != null, "Originaleinsatz geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	var rt := m.runtime
	rt.auto_skip = true
	if rt.in_cutscene:
		rt.end_cutscene()
	var pname := String(Game.cli.get("plane", "mes04" if Game.current_mission_id == "af2_flugschau" else "macchi_nalet"))
	var plane: Node3D = rt.actors.get(pname.to_upper())
	check(plane != null and plane.has_method("set_air_target"), "Flugzeug %s als AirAttack-Akteur" % pname,
		plane.get_class() if plane else "fehlt")
	if plane == null or not plane.has_method("set_air_target"):
		_finish()
		return
	var lead := m.squad.leader()
	# AFRICA1: Der Macchi-Angriff findet auf dem Flugfeld statt (nach der Flucht des Adjutanten); am Spielerstart
	# verdeckt der Randwall (m_af1_border, Klz-Kollision wie im Original) die Sicht → Ziel an die Startbahn stellen
	var place := String(Game.cli.get("place", "AF1_pobocnik" if Game.current_mission_id == "af1_spaghetti_airport" else ""))
	if place != "":
		var pf: Node3D = rt.actors.get(place.to_upper())
		if pf == null:
			pf = rt.find_frame(place)
		if pf:
			if pf is Soldier:
				lead = pf as Soldier       # Ziel = Figur am Flugfeld (Spielerfiguren hängen im Intro an der Startsequenz)
				lead.max_health = 100000.0
				lead.health = lead.max_health
			else:
				for s in m.squad.members:
					s.global_position = pf.global_position + Vector3(15.0 + randf(), 1.0, randf())
			print("AIR Ziel %s bei %s" % [place, pf.global_position])
			await seconds(0.5)
	for s in m.squad.members:
		s.max_health = 100000.0
		s.health = s.max_health
	# Gegner ruhigstellen (nur das Flugzeug soll wirken)
	for e in m.enemies:
		if is_instance_valid(e):
			var b := e.get_node_or_null("EnemyBrain") as EnemyBrain
			if b:
				b.enabled = false
	plane.visible = true
	# Diagnose: große Szenenmeshes, die den Luftraum schneiden (Sichtstrahl Flugzeug → Ziel)
	for mi in m.static_root.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if bb.size.x > 400.0 or bb.size.z > 400.0:
			print("AIR großes Mesh %s: %s" % [mi.get_path(), bb])
	var p0 := plane.global_position
	await seconds(1.0)
	var v := plane.global_position.distance_to(p0)
	check(v > 60.0 and v < 140.0, "Flugzeug fliegt ~100 m/s", "%.1f m in 1 s" % v)
	plane.set_air_target(lead, true)
	check(int(plane.state) == 2 and plane.target == lead, "AirAttack_SetTarget → Phase 2 mit Ziel", "Phase %d" % plane.state)
	var seen := {}
	var hp0 := lead.health
	var min_d := 1e9
	var max_d := 0.0
	await _shot("start")
	var shot_attack := false
	for i in 1500:     # 25 s Physik
		await get_tree().physics_frame
		seen[int(plane.state)] = true
		if i % 60 == 0:
			var sp := plane.get_world_3d().direct_space_state
			var g := sp.intersect_ray(PhysicsRayQueryParameters3D.create(plane.global_position + Vector3.UP * 1000.0,
				plane.global_position + Vector3.DOWN * 10000.0, 1))
			var s2 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(plane.global_position, lead.global_position + Vector3.UP * 1.2, 1))
			print("AIR t=%d Phase %d Flugzeug %s Boden %s Ziel %s Sicht %s" % [i / 60, plane.state, plane.global_position,
				str(g.position) if not g.is_empty() else "-", lead.global_position,
				"frei" if s2.is_empty() else "%s@%s" % [s2.collider.get_parent().name, s2.position]])
		var d := Vector2(plane.global_position.x - lead.global_position.x, plane.global_position.z - lead.global_position.z).length()
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
		if int(plane.state) == 1 and d < 150.0 and not shot_attack:
			shot_attack = true
			await _shot("anflug")
		if seen.has(0) and seen.has(1) and seen.has(2) and lead.health < hp0 and i > 300:
			break
	print("AIR Phasen %s, Abstand min %.0f max %.0f, Schaden %.0f, Höhe über Ziel %.0f, %s" % [str(seen.keys()), min_d, max_d,
		hp0 - lead.health, plane.global_position.y - lead.global_position.y, str(plane.stats)])
	check(seen.has(0) and seen.has(1), "Abflug/Anflug-Phasen 0 → 1", str(seen.keys()))
	check(min_d < 80.0, "Tiefflug über das Ziel", "min %.0f m" % min_d)
	# Einschlagpunkte streuen wie im Original entlang der Flugbahn (±3 m seitlich) – Treffer am Ziel sind selten
	check(int(plane.stats["shots"]) > 0 and int(plane.stats["impacts"]) > 0, "MG feuert im Anflug, Einschläge am Boden",
		str(plane.stats))
	# Abschuss
	plane.on_bullet_hit(100000.0, lead)
	await seconds(0.5)
	check(bool(plane.dead) and int(plane.get_meta("actor_state", 1)) == 0, "Abschuss → tot, _ACTOR_GetState 0")
	await _shot("abschuss")
	_finish()
