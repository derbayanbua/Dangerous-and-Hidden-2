extends "res://tests/test_gameplay.gd"
## Kontrollbilder Bluteffekte (FENSTER, nicht headless):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_blood --profiles_dir=user://test_blut
## → test_output/blood_spray.png, blood_jet.png, blood_wall.png, blood_pool_start.png, blood_pool_grown.png,
##   blood_original.png


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/blood_%s.png" % name)
	print("Bild: blood_%s.png" % name)


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader() and mission().enemies.size() >= 3:
			break
		await get_tree().process_frame
	var m := mission()
	var es: Array = m.enemies.slice(0, 3)
	var ids: Array = []
	for e in es:
		ids.append(e.persistent_id)
	isolate_enemies(ids)
	var s: Soldier = m.squad.leader()
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	var side := fwd.cross(Vector3.UP)
	for i in es.size():
		var e: Soldier = es[i]
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
		e.global_position = s.global_position + fwd * 5.0 + side * (float(i) - 1.0) * 2.5
	var e0: Soldier = es[0]
	_test_block(e0.global_position + fwd * 1.6 - Vector3.UP * 0.5, Vector3(3.0, 3.0, 0.3), s.look_yaw)
	Settings.blood_level = 2
	await seconds(1.0)
	var head: Vector3 = e0.global_position + Vector3.UP * 1.55
	Effects.blood(head, -fwd, fwd, &"head", e0)
	await seconds(0.12)
	await _shot("spray")
	await seconds(0.4)
	await _shot("jet")
	await seconds(1.5)
	await _shot("wall")
	e0.die(s, fwd)
	await seconds(1.4)
	await _shot("pool_start")
	await seconds(8.0)
	await _shot("pool_grown")
	Settings.blood_level = 1
	var e1: Soldier = es[1]
	Effects.blood(e1.global_position + Vector3.UP * 1.3, -fwd, fwd, &"torso", e1)
	await seconds(0.12)
	await _shot("original")
	Settings.blood_level = 2
	_finish()
