extends "res://tests/screenshots.gd"
## Kontrollbilder Mission 3:  tools\godot.cmd -- --mission=m03_sandsturm --autoplay=screenshots_m03


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 600:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	var hale := m.squad.leader()
	for e in m.enemies:
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
	await frames(60)
	await shot("m3_01_start")
	hale.global_position = m.lb.ground(45, 20, 0.2)
	hale.look_yaw = deg_to_rad(70)
	await frames(40)
	await shot("m3_02_oasis")
	hale.put_on_uniform(m.enemy_uniform, "stahlhelm")
	hale.global_position = Vector3(20, 1.2, 14)
	hale.look_yaw = deg_to_rad(-60)
	hale.look_pitch = -0.1
	await frames(40)
	await shot("m3_03_disguised_flak")
	get_tree().quit()
