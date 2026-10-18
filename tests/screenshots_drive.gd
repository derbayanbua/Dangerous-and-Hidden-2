extends "res://tests/test_vehicles.gd"
## Kontrollbilder der Fahrphysik (Fenster nötig): Verfolgerkamera, Federung/Neigung, Räder, Kettenfahrzeug.
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots_drive  → test_output/shot_drive_*.png

const OUT := "res://test_output/"


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "shot_drive_%s.png" % name)
	print("SHOT drive_", name)


## Kamera auf den Fahrer des Fahrzeugs (Verfolgerkamera wie beim Spieler)
func _follow(v: Vehicle) -> void:
	var m := mission()
	m.controller.input_enabled = false
	m.controller.rig.set_target(_drv)
	_drv.look_yaw = v.chase_yaw()
	_drv.look_pitch = -0.2


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	isolate_enemies([])
	_drv = m.squad.members[2]
	m.squad.brain_of(_drv).set_order(SquadBrain.Order.HOLD)
	# 1) Übungseinsatz-Kübelwagen im Gelände
	var k: Vehicle = get_tree().get_nodes_in_group("vehicles")[0]
	await seconds(1.0)
	await _board(k)
	_follow(k)
	await _shot("01_stand")
	k.throttle = 1.0
	await seconds(2.5)
	_drv.look_yaw = k.chase_yaw()
	await _shot("02_gelaende_fahrt")
	k.steer_input = 1.0
	await seconds(1.0)
	_drv.look_yaw = lerp_angle(_drv.look_yaw, k.chase_yaw(), 0.7)
	await _shot("03_gelaende_kurve")
	k.steer_input = 0.0
	k.throttle = 0.0
	await _unboard(k)
	# 2) Originalmodelle auf der Teststrecke
	_test_block(Vector3(0, TRACK_Y - 1.0, 0), Vector3(500, 1, 1400), 0.0)
	var n := 4
	for ty in TYPES:
		if not (String(ty[0]) in ["Opel Blitz", "BMW R75 mit Beiwagen", "Tiger", "Halbkette Sd.Kfz. 251"]):
			continue
		var veh := _spawn_car(ty[0], _orig_data(ty[1], ty[2]), ty[1], ty[3], Vector3(0, TRACK_Y, -600))
		if veh == null:
			continue
		await _board(veh)
		veh.drive.surface_override = 48
		_follow(veh)
		veh.throttle = 1.0
		await seconds(4.0)
		_drv.look_yaw = veh.chase_yaw()
		await _shot("%02d_%s_fahrt" % [n, String(ty[3]).replace(" ", "_")])
		veh.steer_input = 1.0
		await seconds(1.2)
		_drv.look_yaw = lerp_angle(_drv.look_yaw, veh.chase_yaw(), 0.6)
		await _shot("%02d_%s_kurve" % [n, String(ty[3]).replace(" ", "_")])
		veh.steer_input = 0.0
		veh.throttle = 0.0
		await _unboard(veh)
		veh.queue_free()
		n += 1
		await seconds(0.5)
	for l in _levels:
		(l as OrigLevel).release()
	_finish()
