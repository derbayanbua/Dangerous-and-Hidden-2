extends Node
## Kontrollbilder (Fenster, nicht kopflos) für MP-Figuren und MP-Rückmeldungen (Karte wie test_mp_feedback):
##   tools\godot.cmd -- --autoplay=shots_mp_feedback --resolution 1280x720
##   → test_output/mp_fig_{figures,axis,allied,lineup}.png, mp_feedback_hud.png, mp_killcam.png
## Host = Achse mit MP-Figur aus dem SPIELER-SETUP, je Team 2 KI (erste = lokaler Held, falls vorhanden).

const OUT := "res://test_output/%s.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_quit_fail)
	_run.call_deferred()


func _quit_fail() -> void:
	get_tree().quit(1)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", OUT % name, " ", img.get_size())


func _wait(cond: Callable, s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until and not cond.call():
		await get_tree().create_timer(0.1).timeout


func _mission_ready() -> bool:
	var m = Game.current_mission()
	return m != null and m.is_node_ready() and Net._soldiers.has(1) and m.nav_ready and _count_bots() >= 4


func _count_bots() -> int:
	var n := 0
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]) and Net._soldiers[id].alive:
			n += 1
	return n


static func _open_spot(m: Mission, start: Vector3, me: Soldier) -> Vector3:
	# Kandidaten: Zonenmitten (offene Plätze der Karte), dann Raster um den Start; Sichtprüfung inkl. Zäune
	var cands: Array = []
	if m.has_method("mp_zones"):
		for z in m.mp_zones():
			var o: Vector3 = (z["xf"] as Transform3D).origin
			cands.append(Vector3(o.x, start.y, o.z))
	cands.sort_custom(func(a, b): return a.distance_to(start) < b.distance_to(start))
	for gx in range(-12, 13):
		for gz in range(-12, 13):
			cands.append(start + Vector3(gx * 5.0, 0.0, gz * 5.0))
	var best := start
	var best_free := -1
	for p in cands:
		if m.has_method("inside_map") and not m.inside_map(p):
			continue
		var free := _free_rays(m, p, me)
		if free > best_free:
			best_free = free
			best = p
		if free >= 24:
			return p
	return best


static func _free_rays(m: Mission, p: Vector3, me: Soldier) -> int:
	var space := m.get_world_3d().direct_space_state
	var n := 0
	for i in 12:
		var r := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 12.0) * 10.0
		for h in [0.4, 1.4]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * h, p + Vector3.UP * h + r, 1 | LevelBuilder.FENCE_LAYER)
			q.exclude = me.exclude_rids()
			if space.intersect_ray(q).is_empty() and not (m.has_method("foliage_blocks_sight") and m.foliage_blocks_sight(p + Vector3.UP * h, p + Vector3.UP * h + r)):
				n += 1
	return n


## Physik/Animation nachziehen lassen (auch bei sehr niedriger Bildrate im Fenster)
func _settle(s: float = 1.5) -> void:
	await get_tree().create_timer(s).timeout
	for i in 15:
		await get_tree().process_frame


func _place(s: Soldier, pos: Vector3, face: Vector3) -> void:
	var br := s.get_node_or_null("EnemyBrain")
	if br:
		br.process_mode = Node.PROCESS_MODE_DISABLED
	s.move_input = Vector3.ZERO
	s.trigger = false
	s.velocity = Vector3.ZERO
	s.global_position = pos
	var d := (face - pos)
	s.look_yaw = atan2(-d.x, -d.z)
	s.look_pitch = 0.0
	s.set_meta("protect_until", 0)


func _run() -> void:
	Settings.show_fps = true
	Net.local_name = "Spieler Achse"
	Net.local_team = Soldier.TEAM_AXIS
	Net.local_figure = "mp:35"
	Net.host({"name": "Shots", "map": load("res://tests/test_mp_feedback.gd")._map(), "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + 48,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 30, "bots_per_team": 2,
		"password": "", "allow_vehicles": false, "kill_cam": true})
	await _wait(_mission_ready, 400.0)
	var m: Mission = Game.current_mission()
	await get_tree().create_timer(2.0).timeout
	var me: Soldier = Net._soldiers.get(1)
	m.controller.input_enabled = false
	var axis: Array = []
	var allied: Array = []
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(s):
			(axis if s.team == Soldier.TEAM_AXIS else allied).append(s)
	# freien Platz nahe dem Host suchen (12 Strahlen à 12 m frei, innerhalb der Grenze)
	var base := _open_spot(m, me.global_position, me)
	var dir := Vector3.FORWARD
	var side := dir.cross(Vector3.UP).normalized()
	var cam := Camera3D.new()
	cam.fov = 50.0
	m.add_child(cam)
	cam.current = true
	var hud = m.get_node_or_null("MpHud")
	hud.visible = false
	if m.get("hud"):
		m.hud.visible = false
	# 1) Achsen-Spieler (Host, MP-Figur) und Alliierter (KI ohne Heldenstatus) nebeneinander
	if m.rig.mode == CameraRig.Mode.FIRST:
		m.rig.toggle_mode()              # eigene Figur sichtbar (1. Person blendet sie aus)
	var c0 := base + dir * 6.0
	_place(me, c0 - side * 1.2, c0 - dir * 5.0 - side * 1.2)
	var al2: Soldier = allied[allied.size() - 1]
	_place(al2, c0 + side * 1.2, c0 - dir * 5.0 + side * 1.2)
	for i in axis.size():
		_place(axis[i], base + dir * 30.0 + side * (8.0 + i * 2.0), base)
	_place(allied[0], base + dir * 30.0 - side * 8.0, base)
	await _settle()
	cam.global_position = c0 - dir * 4.2 + Vector3.UP * 1.3
	cam.look_at(c0 + Vector3.UP * 0.95, Vector3.UP)
	await _save("mp_fig_figures")
	cam.global_position = me.global_position - dir * 2.2 + Vector3.UP * 1.3
	cam.look_at(me.global_position + Vector3.UP * 1.0, Vector3.UP)
	await _save("mp_fig_axis")
	cam.global_position = al2.global_position - dir * 2.2 + Vector3.UP * 1.3
	cam.look_at(al2.global_position + Vector3.UP * 1.0, Vector3.UP)
	await _save("mp_fig_allied")
	# 2) Aufstellung aller Figuren: Achse (Spieler, Held/KI) links, Alliierte (Held/KI) rechts
	var row: Array = [me] + axis + allied
	for i in row.size():
		_place(row[i], c0 + side * (float(i) - (row.size() - 1) * 0.5) * 1.3, c0 - dir * 6.0)
	await _settle()
	cam.fov = 60.0
	cam.global_position = c0 - dir * 6.0 + Vector3.UP * 1.4
	cam.look_at(c0 + Vector3.UP * 0.9, Vector3.UP)
	await _save("mp_fig_lineup")
	if m.rig.mode != CameraRig.Mode.FIRST:
		m.rig.toggle_mode()
	# 3) HUD: Gegner (Alliierter) angevisiert, Teamkamerad (Achse) seitlich, Kill-Feed, Hitmarker, Richtungsanzeige
	hud.visible = true
	if m.get("hud"):
		m.hud.visible = true
	_place(me, base, base + dir * 10.0)
	var foe: Soldier = allied[0]
	_place(foe, base + dir * 11.0, base)
	_place(axis[0], base + dir * 7.0 + side * 3.5, base)
	_place(al2, base + dir * 18.0 - side * 4.0, base)
	await _settle()
	var eye := me.eye_position()
	cam.fov = 70.0
	cam.global_position = eye
	cam.look_at(foe.eye_position() - Vector3.UP * 0.4, Vector3.UP)
	al2.apply_hit(500.0, &"head", me, dir)                  # Kill-Feed: Kopfschuss
	await get_tree().create_timer(0.3).timeout
	axis[1].apply_hit(500.0, &"torso", al2 if is_instance_valid(al2) and al2.alive else allied[0], dir)
	await get_tree().create_timer(0.3).timeout
	me.apply_hit(5.0, &"torso", foe, -dir)                   # Richtungsanzeige (Treffer vom Gegner vorn)
	foe.apply_hit(10.0, &"head", me, dir)                    # Hitmarker Kopf + Meldung
	# Bildrate im Fenster unter Last 1–4 FPS: Anzeigezeiten für das Standbild festhalten (nur Aufnahme)
	var now := Time.get_ticks_msec()
	hud.feedback.hit_ms = now + 1500
	for h in hud.feedback._hurts:
		h["ms"] = now + 1500
	for e in Net.kill_feed:
		e["ms"] = now
	await _save("mp_feedback_hud")
	# 4) Kill-Cam: Host wird vom Gegner getötet
	cam.current = false
	m.rig.camera.current = true
	await get_tree().create_timer(0.5).timeout
	foe.set_meta("protect_until", 0)
	me.set_meta("protect_until", 0)
	me.apply_hit(500.0, &"torso", foe, -dir)
	await get_tree().process_frame
	# niedrige Bildrate: Kamerafahrt als abgeschlossen setzen (Kill-Cam verfolgt dann den Schützen), nur Aufnahme
	hud.kill_cam.started_ms = Time.get_ticks_msec() - 900
	await get_tree().process_frame
	print("KILLCAM aktiv=%s Schütze=%d" % [hud.kill_cam.active, hud.kill_cam.killer_id])
	await _save("mp_killcam")
	Net.leave(false)
	get_tree().quit(0)
