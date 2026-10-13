extends "res://tests/screenshots.gd"
## Kontrollbilder Mission 2:  tools\godot.cmd -- --mission=m02_nordlicht --autoplay=screenshots_m02


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
	await shot("m2_01_start")
	# Waldrand, Blick auf das Lager mit Suchscheinwerfern
	hale.global_position = m.lb.ground(-50, 30, 0.2)
	hale.look_yaw = deg_to_rad(-40)
	await frames(60)
	await shot("m2_02_depot")
	# Im Lager zwischen Kaserne und Wachgebäude
	hale.global_position = Vector3(12, 1.2, 6)
	hale.look_yaw = deg_to_rad(-70)
	await frames(30)
	await shot("m2_03_inside")
	# Tanklager, 1. Person
	m.rig.toggle_mode()
	hale.global_position = Vector3(-6, 1.2, -26)
	hale.look_yaw = deg_to_rad(70)
	await shot("m2_04_tanks_fpv")
	get_tree().quit()
