extends Node
## Eigene Flugzeug-Vorschau und spätere Deckungs-/Bodenaufnahmen.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.hud.visible = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.far = 2000
	var shots: Array = []
	if Game.cli.has("asset_preview"):
		var light := DirectionalLight3D.new()
		m.add_child(light)
		light.rotation_degrees = Vector3(-45,-25,0)
		light.light_energy = 1.4
		for pair in [["arctic2/models/la_a1_letadlo01",0],["arctic2/models/m_a1_letadlo01",1],["africa2/models/cutletadlo_af2",2],["africa2/models/la_spitfire",3]]:
			var n := OrigLevel.parse_glb(OrigLevel.cache_root()+"/"+String(pair[0])+".glb")
			m.add_child(n)
			var bounds: AABB = m._templates.mesh_bounds(n,Transform3D.IDENTITY)
			print("AIRCRAFT ",pair[0]," bounds=",bounds)
			n.position += Vector3(2000+int(pair[1])*80,0,2000)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var center := Vector3(2000+int(pair[1])*80,bounds.size.y*0.4,2000)
			shots.append([String(pair[0]).get_file(),center+Vector3(1,0.6,1).normalized()*bounds.size.length()*0.95,center])
	else:
		if get_tree().get_nodes_in_group("bavaria_aircraft_wrecks").is_empty():
			load("res://src/maps/bavaria/meadow_cover.gd").new().build(m)
		for n in get_tree().get_nodes_in_group("bavaria_aircraft_wrecks"):
			var bounds: AABB = n.get_meta("bounds")
			var center: Vector3 = n.to_global(bounds.get_center())
			shots.append([String(n.name),center+Vector3(1,0.6,1).normalized()*bounds.size.length(),center])
			shots.append([String(n.name)+"_ground",n.to_global(Vector3(bounds.end.x+3,1.7,bounds.end.z+4)),center])
	for shot in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		cam.fov = 60
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_aircraft_"+shot[0]+".png")
		print("SHOT ",shot[0])
	get_tree().quit()
