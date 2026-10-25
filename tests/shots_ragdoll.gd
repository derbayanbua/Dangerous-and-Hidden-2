extends "res://tests/test_gameplay.gd"
## Kontrollbilder Ragdoll B-016 (FENSTER, nicht headless):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_ragdoll
## → test_output/ragdoll/*.png: Schuss (Übergang Clip → Physik, Ruhe), Sturz von einer Kante, Explosion (Flug, Ruhe),
##   geweckte Leiche, Vergleich Option aus (Original-Todesclip), Trefferzonen an der Leiche.

var _cam: Camera3D
var _tpl: Node3D


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/ragdoll"))
	get_viewport().get_texture().get_image().save_png("res://test_output/ragdoll/%s.png" % name)
	print("Bild: ragdoll/%s.png" % name)


func _look(target: Vector3, from_dir: Vector3, dist := 4.0, height := 1.6) -> void:
	_cam.global_position = target + from_dir.normalized() * dist + Vector3.UP * height
	_cam.look_at(target + Vector3.UP * 0.4, Vector3.UP)


func _ground(p: Vector3) -> Vector3:
	var h := mission().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.z), Vector3(p.x, -80.0, p.z), 1))
	return h.position if not h.is_empty() else p


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader() and mission().enemies.size() >= 5:
			break
		await get_tree().process_frame
	var m := mission()
	var es: Array = m.enemies.slice(0, 5)
	var ids: Array = []
	for e in es:
		ids.append(e.persistent_id)
	isolate_enemies(ids)
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	s.look_yaw = 0.0
	s.global_position = _ground(Vector3(0, 0, 30))
	for mb in m.squad.members:
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
			mb.global_position += Vector3(0, 0, 80)
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	_tpl = OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb")
	for i in es.size():
		var e: Soldier = es[i]
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
		e.global_position = _ground(s.global_position + fwd * 8.0 + side * (float(i) - 2.0) * 6.0) + Vector3.UP * 0.05
		e.look_yaw = PI
		if _tpl:
			e.model.attach_orig(_tpl.duplicate())
	_cam = Camera3D.new()
	_cam.fov = 60.0
	m.add_child(_cam)
	_cam.current = true
	await seconds(1.0)

	# 1) Schuss von vorn: Clipanfang, Physik, Ruhe
	var e0: Soldier = es[0]
	_look(e0.global_position, side, 4.5)
	e0.health = 1.0
	var tgt := e0.global_position + Vector3.UP * 1.25
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await seconds(0.08)
	await _shot("shot_0_clip")
	await seconds(0.25)
	await _shot("shot_1_fall")
	await seconds(0.5)
	await _shot("shot_2_fall")
	await _wait_frozen(e0)
	await _shot("shot_3_rest")
	_look(e0.global_position, -fwd + side * 0.3, 3.0, 2.5)
	await _shot("shot_4_rest_top")
	e0.model.show_zones(true)
	await _shot("shot_5_zones")
	e0.model.show_zones(false)

	# 2) Kante: Gegner steht auf einem 1,2 m hohen Block und fällt beim Treffer hinunter
	var e1: Soldier = es[1]
	var blk_pos := e1.global_position
	_test_block(blk_pos - Vector3.UP * 0.05, Vector3(2.0, 1.2, 2.0), 0.0)
	e1.global_position = blk_pos + Vector3.UP * 1.25 + fwd * 0.8
	await seconds(0.6)
	_look(e1.global_position, side, 5.0, 0.8)
	e1.health = 1.0
	tgt = e1.global_position + Vector3.UP * 1.25
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await seconds(0.5)
	await _shot("edge_1_fall")
	await _wait_frozen(e1)
	await _shot("edge_2_rest")

	# 3) Explosion
	var e2: Soldier = es[2]
	_look(e2.global_position, side, 7.0, 2.0)
	var boom := e2.global_position - fwd * 1.5 + Vector3.UP * 0.2
	Effects.explosion(boom, 5.0)
	e2.apply_hit(500.0, &"torso", s, (e2.global_position - boom).normalized())
	await seconds(0.25)
	await _shot("expl_1_flight")
	await seconds(0.4)
	await _shot("expl_2_flight")
	await _wait_frozen(e2)
	await _shot("expl_3_rest")

	# 4) Explosion weckt die ruhende Leiche aus 1)
	_look(e0.global_position, side, 6.0, 2.0)
	Effects.explosion(e0.global_position + side * 1.2, 4.0)
	await seconds(0.3)
	await _shot("wake_1")
	await _wait_frozen(e0)
	await _shot("wake_2_rest")

	# 5) Option aus: Original-Todesclip
	Settings.ragdoll = false
	var e3: Soldier = es[3]
	_look(e3.global_position, side, 4.5)
	e3.die(s, fwd)
	await seconds(2.5)
	await _shot("option_off_clip")
	Settings.ragdoll = true
	if _tpl:
		_tpl.free()
	_finish()


func _wait_frozen(e: Soldier) -> void:
	var rd: Ragdoll = e.model.ragdoll
	var t := 0.0
	while rd and not rd.is_frozen() and t < 12.0:
		await seconds(0.2)
		t += 0.2
