extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m: Mission
	while m==null:
		await get_tree().process_frame
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.far = 2200
	var house: Node3D = m.static_root.get_node("woodland_shed")
	var size: Vector2 = house.get_meta("footprint_size")
	var gun: OrigInteractive.OrigEmplacement = m.woodland_emplacement.gun
	var shots := [
	 ["wiese",m.pixel([600,675],1.7),m.pixel([620,600],0.3)],
	 ["fahrweg",m.pixel([530,890],1.7),m.pixel([550,896],0.25)],
	 ["holzhaus",house.to_global(Vector3(0,1.7,size.y*0.5+10)),house.to_global(Vector3(0,1.7,0))],
	 ["mg42_innen",gun.gunner_spot()+gun.frame.global_basis.z*0.6+Vector3.UP*1.55,gun.shot_origin()+(-gun.frame.global_basis.z)*8],
	 ["mg42_bock",house.to_global(Vector3(-size.x*0.5+3,1.55,0.85)),house.to_global(Vector3(-size.x*0.5+0.45,1.2,0))],
	 ["mg42_luke",house.to_global(Vector3(-size.x*0.5-3,1.7,4)),house.to_global(Vector3(-size.x*0.5+0.2,1.4,0))]
	]
	for shot in shots:
		cam.position = shot[1]
		cam.look_at(shot[2],Vector3.UP)
		cam.fov = 70
		cam.reset_physics_interpolation()
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "res://test_output/bavaria_ground_"+String(shot[0])+".png"
		get_viewport().get_texture().get_image().save_png(file)
		print("SHOT ",file)
	get_tree().quit()
