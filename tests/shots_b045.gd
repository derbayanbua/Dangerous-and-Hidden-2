extends "res://tests/test_gameplay.gd"
## B-045 Vorher/Nachher-Bilder (FENSTER, nicht headless):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_b045 --tag=nachher
##   Vorher-Stand (Ragdoll ohne B-045-Vorwärtskinematik): zusätzlich --ragdoll_fk=0 --tag=vorher
## → test_output/b045_<tag>_*.png: Leichen nach Kopfschuss/Explosion/Sturz/MG-Salve (Figuren ge01a/en01),
##   Wunden Gewehr (Eintritt/Austritt), Lache, EXTRA GORE (Kopf/Arm ab, Stumpf).

var _cam: Camera3D
var _tag := "nachher"
var _tpls := {}


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var p := "res://test_output/b045_%s_%s.png" % [_tag, name]
	get_viewport().get_texture().get_image().save_png(p)
	print("Bild: ", p)


func _look(target: Vector3, from_dir: Vector3, dist := 3.0, height := 1.4) -> void:
	_cam.global_position = target + from_dir.normalized() * dist + Vector3.UP * height
	_cam.look_at(target + Vector3.UP * 0.3, Vector3.UP)


func _ground(p: Vector3) -> Vector3:
	var h := mission().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.z), Vector3(p.x, -80.0, p.z), 1))
	return h.position if not h.is_empty() else p


func _zone(e: Soldier, bone: String) -> Node3D:
	for hb in e.find_children("Hitbox_*", "Hitbox", true, false):
		if String(hb.get_meta("bone", "")) == bone and (hb as Hitbox).zone != Helmet.ZONE:
			return hb
	return null


func _spawn(m: Mission, pos: Vector3, mn: String, nm: String) -> Soldier:
	var e: Soldier = m.spawn_soldier(_ground(pos) + Vector3.UP * 0.05, PI, Soldier.TEAM_AXIS, nm, ["mp40"],
		Color(0.36, 0.38, 0.33), "stahlhelm", nm)
	e.model.attach_orig((_tpls[mn] as Node3D).duplicate())
	if e.has_node("EnemyBrain"):
		e.get_node("EnemyBrain").enabled = false
	if e.has_node("Perception"):
		e.get_node("Perception").set_physics_process(false)
	e.max_health = 100.0
	e.health = 100.0
	return e


func _corpse_center(e: Soldier) -> Vector3:
	var rd: Ragdoll = e.model.ragdoll
	return rd.pelvis_position() if rd else e.global_position


func _wait_frozen(e: Soldier) -> void:
	var rd: Ragdoll = e.model.ragdoll
	var t := 0.0
	while rd and not rd.is_frozen() and t < 12.0:
		await seconds(0.2)
		t += 0.2


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	isolate_enemies([])
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	s.look_yaw = 0.0
	s.global_position = _ground(Vector3(0, 0, 30))
	for mb in m.squad.members:
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
			mb.global_position += Vector3(0, 0, 80)
	for mn in ["ge01a", "en01"]:
		_tpls[mn] = OrigWeapons._load(OrigLevel.cache_root() + "/characters/%s.glb" % mn)
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	m.add_child(_cam)
	_cam.current = true
	Settings.ragdoll = true
	Settings.blood_level = 2
	var base := s.global_position + fwd * 9.0
	var kar := WeaponDB.get_weapon(&"kar98k")

	# 1) Kopfschuss (ge01a) und MG-Salve (en01)
	var e0 := _spawn(m, base - side * 3.0, "ge01a", "b045s_kopf")
	var e1 := _spawn(m, base + side * 3.0, "en01", "b045s_mg")
	await seconds(1.0)
	e0.health = 1.0
	var zf := _zone(e0, "f")
	var tgt: Vector3 = zf.global_position if zf else e0.global_position + Vector3.UP * 1.6
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, kar, [] as Array[RID], s.team)
	e1.health = 60.0
	for k in 6:
		var zc := _zone(e1, "c")
		var t2: Vector3 = zc.global_position if zc else e1.global_position + Vector3.UP * 1.2
		Ballistics.fire(s, t2 + Vector3(randf_range(-0.1, 0.1), randf_range(-0.15, 0.15), 0) - fwd * 6.0, fwd,
			WeaponDB.get_weapon(&"bren"), [] as Array[RID], s.team)
		await seconds(0.1)
	_look(_corpse_center(e0), side + fwd * 0.2, 3.0, 1.0)
	await seconds(0.35)
	await _shot("kopfschuss_flug")
	await _wait_frozen(e0)
	await _wait_frozen(e1)
	_look(_corpse_center(e0), side * 0.6 - fwd, 2.6, 1.8)
	await _shot("kopfschuss_leiche")
	_look(_corpse_center(e1), -side * 0.6 - fwd, 2.6, 1.8)
	await _shot("mg_salve_leiche")

	# 2) Explosion (ge01a) und Sturz von 3 m (en01)
	var b2 := base - side * 16.0
	var e2 := _spawn(m, b2 - side * 4.0, "ge01a", "b045s_expl")
	var e3 := _spawn(m, b2 + side * 4.0, "en01", "b045s_sturz")
	await seconds(0.8)
	var feet := e3.global_position
	_test_block(feet - Vector3.UP * 0.05, Vector3(2.0, 3.0, 2.0), 0.0)
	e3.global_position = feet + Vector3.UP * 3.05 + fwd * 0.8
	await seconds(0.8)
	var boom := e2.global_position - fwd * 1.2 + Vector3.UP * 0.3
	Effects.explosion(boom, 5.0)
	e2.apply_hit(500.0, &"torso", s, (e2.global_position - boom).normalized())
	e3.health = 1.0
	tgt = e3.global_position + Vector3.UP * 1.2
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, kar, [] as Array[RID], s.team)
	_look(_corpse_center(e2), -fwd - side * 0.3, 7.0, 1.5)
	await seconds(0.3)
	await _shot("explosion_flug")
	await _wait_frozen(e2)
	await _wait_frozen(e3)
	_look(_corpse_center(e2), -fwd - side * 0.4, 3.0, 2.0)
	await _shot("explosion_leiche")
	_look(_corpse_center(e3), -fwd + side * 0.3, 3.0, 1.8)
	await _shot("sturz_leiche")

	# 3) Wunden: Gewehrtreffer Rumpf (Eintritt vorn, Austritt hinten), lebend stehend
	var b3 := base + side * 12.0
	var e4 := _spawn(m, b3, "ge01a", "b045s_wunde")
	e4.max_health = 400.0
	e4.health = 400.0
	await seconds(0.8)
	var zc4 := _zone(e4, "c")
	tgt = zc4.global_position if zc4 else e4.global_position + Vector3.UP * 1.2
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, kar, [] as Array[RID], s.team)
	await seconds(0.25)
	_look(e4.global_position + Vector3.UP * 0.9, -fwd, 1.8, 0.5)
	await _shot("wunde_eintritt")
	_look(e4.global_position + Vector3.UP * 0.9, fwd, 1.8, 0.5)
	await _shot("wunde_austritt")

	# 4) EXTRA GORE: Kopf ab (ge01a), Explosion nah (en01)
	Settings.blood_level = Settings.BLOOD_GORE
	Gore.force_roll = 0.0
	var b4 := base + side * 12.0 + fwd * 8.0
	var e5 := _spawn(m, b4 - side * 3.0, "ge01a", "b045s_gore_kopf")
	var e6 := _spawn(m, b4 + side * 3.0, "en01", "b045s_gore_expl")
	await seconds(0.8)
	e5.health = 1.0
	zf = _zone(e5, "f")
	tgt = zf.global_position if zf else e5.global_position + Vector3.UP * 1.6
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, kar, [] as Array[RID], s.team)
	boom = e6.global_position + Vector3.UP * 0.5 - fwd * 0.6
	Effects.explosion(boom, 6.0)
	e6.apply_hit(500.0, &"torso", s, fwd)
	_look(_corpse_center(e5), side, 3.0, 1.0)
	await seconds(0.3)
	await _shot("gore_kopf_flug")
	await _wait_frozen(e5)
	await _wait_frozen(e6)
	await seconds(3.0)
	_look(_corpse_center(e5), side * 0.5 - fwd, 2.2, 1.5)
	await _shot("gore_kopf_leiche")
	_look(_corpse_center(e6), -side * 0.5 - fwd, 3.2, 2.2)
	await _shot("gore_explosion_leiche")
	Gore.force_roll = -1.0
	Settings.blood_level = 2
	for t in _tpls.values():
		if t:
			(t as Node3D).free()
	_finish()
