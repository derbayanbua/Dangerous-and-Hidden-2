extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m: Mission
	while m==null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	var camera := Camera3D.new()
	m.add_child(camera)
	camera.current = true
	camera.fov = 68
	var index := 0
	if Game.cli.has("all_tree_contacts"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/tree_contacts"))
		for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
			if not root.visible:
				continue
			var current := index
			index += 1
			if Game.cli.has("tree_indices") and not Array(String(Game.cli.tree_indices).split(",")).has(str(current)):
				continue
			if current%maxi(int(Game.cli.get("tree_stride",1)),1)!=0:
				continue
			var foot: Vector3 = root.get_meta("ground_contact_point",root.global_position)
			foot.y = root.get_meta("ground_floor_y")
			var toward_center := Vector3(-foot.x,0,-foot.z).normalized()*3.0
			camera.global_position = foot+(Vector3(1.5,1.2,2) if m.inside_map(foot) else toward_center+Vector3.UP*1.2)
			camera.look_at(foot+Vector3.UP*0.45)
			await _save(camera,"tree_contacts/tree_%03d"%current)
	var saved := {}
	for room in get_tree().get_nodes_in_group("bavaria_furnished_rooms"):
		var house: String = room.get_meta("house")
		if house not in ["haus_16","haus_18_shed","reihe_38_0"]:
			continue
		var floor_y: float = room.get_meta("floor_height")
		var key := house+str(floor_y)
		if saved.has(key):
			continue
		saved[key] = true
		var rect: Rect2 = room.get_meta("room_rect")
		var center := rect.get_center()
		var side := signf(center.x)
		camera.global_position = room.to_global(Vector3(rect.end.x-0.35 if side<0 else rect.position.x+0.35,floor_y+1.7,center.y+minf(rect.size.y*0.25,0.5)))
		camera.look_at(room.to_global(Vector3(center.x,floor_y+2.1,center.y)))
		await _save(camera,"light_"+house+"_"+String(room.name))
	# Außenansichten bleiben unter der tatsächlichen Spielbeleuchtung.
	var tree: Vector3 = m.pixel(m.layout.sniper_tree.pixel)
	camera.global_position = tree+Vector3(9,1.7,7)
	camera.look_at(tree+Vector3.UP*2.4)
	await _save(camera,"tree_sniper_grounded")
	var border := get_tree().get_nodes_in_group("bavaria_boundary_screen")[0]
	for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
		if root.is_ancestor_of(border) or not border.is_ancestor_of(root):
			continue
		camera.global_position = root.global_position+Vector3(3,1.7,4)
		camera.look_at(root.global_position+Vector3.UP*1.1)
		await _save(camera,"tree_border_grounded")
		break
	get_tree().quit()
func _save(camera: Camera3D,id: String) -> void:
	camera.reset_physics_interpolation()
	for i in (1 if id.begins_with("tree_contacts/") else 3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/"+id+".png")
	print("SHOT ",id)
