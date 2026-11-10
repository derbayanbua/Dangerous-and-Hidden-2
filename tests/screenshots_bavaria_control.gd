extends Node
## Bodenaufnahmen mit physisch freier Kamera und freiem Blick auf Gewächshausdach.
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m=Game.current_mission()
	while m==null or not m.nav_ready:
		await get_tree().create_timer(.1).timeout
		m=Game.current_mission()
	m.controller.input_enabled=false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible=false
	var cam:=Camera3D.new()
	m.add_child(cam)
	cam.current=true
	cam.fov=65
	var space=m.get_world_3d().direct_space_state
	var ball:=SphereShape3D.new()
	ball.radius=.25
	var count:=0
	for greenhouse in get_tree().get_nodes_in_group("bavaria_greenhouses"):
		var found:=false
		var target: Vector3=greenhouse.global_position+Vector3.UP*2.5
		for radius in [4.0,5.5,7.0]:
			for degrees in [45,135,225,315,0,90,180,270]:
				var angle:=deg_to_rad(float(degrees))
				var eye: Vector3=greenhouse.global_position+Vector3(cos(angle)*radius,1.7,sin(angle)*radius)
				var query:=PhysicsShapeQueryParameters3D.new()
				query.shape=ball
				query.transform.origin=eye
				query.collision_mask=1
				if not m.inside_map(eye) or not space.intersect_shape(query,1).is_empty():continue
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1)).is_empty():continue
				cam.global_position=eye
				cam.look_at(target)
				cam.reset_physics_interpolation()
				for i in 4:await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var path: String="res://test_output/bavaria_control_greenhouse_%d.png"%count
				get_viewport().get_texture().get_image().save_png(path)
				print("CONTROL_SHOT ",path," eye ",eye," target ",target)
				found=true
				break
			if found:break
		if not found:push_error("Keine freie Gewächshauskamera")
		count+=1
	get_tree().quit()
