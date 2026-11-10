extends Node
## Echte Innenraum-/Bodenaufnahmen; Asset-Vorschau dient der historischen Auswahl.
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
	cam.far = 1600
	var shots: Array = []
	if Game.cli.has("asset_preview"):
		var light := DirectionalLight3D.new()
		m.add_child(light)
		light.rotation_degrees = Vector3(-45,-25,0)
		light.light_energy = 1.4
		var models := ["e_ktable","e_chair","k_c2_bigbed","e_kacbnt","e_shelvs","e_wcase","e_armch2","k_g_kamna","e_gstove","ja_vobraz07","e_kicpot","e_flaska1","e_repbox","e_mcase","e_hanger","e_matrce","e_covrlt"]
		for i in models.size():
			var n := OrigLevel.parse_glb(OrigLevel.cache_root()+"/czech3/models/"+String(models[i])+".glb")
			m.add_child(n)
			var bounds: AABB = m._templates.mesh_bounds(n,Transform3D.IDENTITY)
			print("FURNITURE ",models[i]," bounds=",bounds)
			n.position += Vector3(2000+i*60,0,2000)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var center := Vector3(2000+i*60,bounds.size.y*0.4,2000)
			shots.append([models[i],center+Vector3(0.8,0.5,1).normalized()*maxf(bounds.size.length()*1.15,0.5),center])
	else:
		if get_tree().get_nodes_in_group("bavaria_furnished_rooms").is_empty():
			load("res://src/maps/bavaria/interior_decoration.gd").new().build(m)
			m._templates.release()
		for room in get_tree().get_nodes_in_group("bavaria_furnished_rooms"):
			if Game.cli.has("interior_representative") and not String(room.get_meta("house")) in ["haus_16","reihe_38_0","haus_2"]:
				continue
			if Game.cli.has("interior_house") and String(room.get_meta("house"))!=String(Game.cli.interior_house):
				continue
			var rect: Rect2 = room.get_meta("room_rect")
			var height := float(room.get_meta("floor_height"))
			var side := signf(rect.get_center().x)
			var eye := Vector3(rect.end.x-0.40 if side<0 else rect.position.x+0.40,height+1.7,rect.get_center().y+0.65)
			var target := Vector3(rect.position.x+0.65 if side<0 else rect.end.x-0.65,height+1.1,rect.get_center().y-0.25)
			shots.append([String(room.get_meta("house"))+"_"+String(room.name),room.to_global(eye),room.to_global(target)])
	if Game.cli.has("shot_filter"):
		shots = shots.filter(func(shot):return String(shot[0]).contains(String(Game.cli.shot_filter)))
	for shot in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		cam.fov = 78 if not Game.cli.has("asset_preview") else 60
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_interior_"+shot[0]+".png")
		print("SHOT ",shot[0])
	get_tree().quit()
