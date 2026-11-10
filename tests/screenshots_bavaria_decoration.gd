extends Node
## Kontrollbilder direkt aus Godot; --asset_preview=1 zeigt Cache-Kandidaten vor Platzierung.
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
		var files := ["normandy2_mp_zone/models/la_citr_vrak01", "normandy2_mp_zone/models/la_hakl_vrak01", "normandy2_mp_zone/models/la_tiger_vrak01", "czech6_mp_zone/models/la_agreg01", "czech6_mp_zone/models/la_filtry01"]
		var light := DirectionalLight3D.new()
		m.add_child(light)
		light.rotation_degrees = Vector3(-45,-25,0)
		light.light_energy = 1.4
		for i in files.size():
			var n := OrigLevel.parse_glb(OrigLevel.cache_root()+"/"+files[i]+".glb")
			m.add_child(n)
			var bounds: AABB = m._templates.mesh_bounds(n,Transform3D.IDENTITY)
			print("ASSET ",files[i]," bounds ",bounds)
			n.position += Vector3(2000+i*60,0,2000)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var center := Vector3(2000+i*60,bounds.size.y*0.4,2000)
			var distance := maxf(bounds.size.length()*0.85,3.0)
			shots.append([files[i].get_file(),center+Vector3(0.8,0.5,1).normalized()*distance,center])
	else:
		for n in get_tree().get_nodes_in_group("bavaria_war_groups"):
			var size: Vector3 = n.get_meta("bounds_size",Vector3(5,2,5))
			var center: Vector3 = n.global_position+Vector3.UP*0.8
			shots.append([String(n.name),center+Vector3(1,0.55,1).normalized()*maxf(size.length()*1.2,8),center])
			shots.append([String(n.name)+"_ground",n.to_global(Vector3(size.x*0.5+3,1.7,size.z*0.5+4)),center])
	if Game.cli.has("decor_filter"):
		shots = shots.filter(func(shot): return String(shot[0]).contains(String(Game.cli.decor_filter)))
	for shot in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		cam.fov = 60
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_decor_"+shot[0]+".png")
		print("SHOT ",shot[0])
	get_tree().quit()
