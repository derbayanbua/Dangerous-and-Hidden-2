extends Node
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.fov = 70
	var gun: Node3D = m.field_emplacement.frame
	var shots: Array = [
		["flak_ground",gun.to_global(Vector3(5,1.7,6)),gun.global_position+Vector3.UP*1.3],
		["flak_front",gun.to_global(Vector3(-4,1.7,-6)),gun.global_position+Vector3.UP*1.2],
		["field_overview",m.pixel([625,750],21),m.pixel([665,425],0)]
	]
	for house in get_tree().get_nodes_in_group("bavaria_stair_houses"):
		shots.append([String(house.name)+"_stairs",house.to_global(Vector3(1.7,1.7,2.5)),house.to_global(Vector3(4.1,1.8,-0.8))])
		shots.append([String(house.name)+"_landing",house.to_global(Vector3(4.85,4.88,2.9)),house.to_global(Vector3(3.4,2.4,-1.3))])
	for shot in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		cam.reset_physics_interpolation()
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://test_output/bavaria_field_"+str(shot[0])+".png"
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ",path)
	get_tree().quit()
