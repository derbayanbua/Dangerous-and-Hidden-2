extends "res://tests/shots_graphics.gd"
## README-Bilder (FENSTER, nicht headless): Landschaft in mehreren Blickrichtungen, Explosion, Befehlsmenü.
##   tools\godot.cmd -- --mission=<m> --autoplay=shots_readme [--level=3]
## → test_output/readme/<mission>_{view0,view90,view180,view270,expl_a,expl_b,cmd}.png


func _rshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/readme"))
	var mid := String(Game.cli.get("mission", "mission"))
	get_viewport().get_texture().get_image().save_png("res://test_output/readme/%s_%s.png" % [mid, name])
	print("Bild: readme/%s_%s.png" % [mid, name])


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if m == null:
		check(false, "Mission geladen")
		_finish()
		return
	await _wait_player_control(m)
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	Settings.quality = int(Game.cli.get("level", "3"))
	Settings.apply()
	await seconds(3.0)
	var yaw0 := s.look_yaw
	for d in [0, 90, 180, 270]:
		s.look_yaw = yaw0 + deg_to_rad(float(d))
		s.look_pitch = deg_to_rad(-3.0)
		await seconds(1.5)
		await _rshot("view%d" % d)
	s.look_yaw = yaw0
	await seconds(1.5)
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	Effects.explosion(s.global_position + fwd * 22.0, 8.0)
	await seconds(0.2)
	await _rshot("expl_a")
	await seconds(0.4)
	await _rshot("expl_b")
	await seconds(4.0)
	var cm = m.controller.command_menu if m.controller else null
	if cm:
		cm.open_for(-1)
		await frames(3)
		await _rshot("cmd")
		cm.press_digit(1)
		await frames(3)
		await _rshot("cmd_bewegung")
		cm.close()
	check(true, "README-Bilder erzeugt")
	_finish()
