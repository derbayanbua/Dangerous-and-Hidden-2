extends Node
## Echte Godot-Kontrollbilder, keine Konzeptgrafik.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	# Grafikprüfung unabhängig vom asynchronen Recast-Bake.
	for i in 8:
		await get_tree().process_frame
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.far = 2200.0
	cam.current = true
	var shots: Array = [
		["overview", Vector3(475, 520, 490)*m.layout_scale(), Vector3(0, 0, 15)*m.layout_scale(), 45.0],
		["plan", Vector3(0, 850, 20)*m.layout_scale(), Vector3(0, 0, 20)*m.layout_scale(), 65.0],
		["courtyard", m.pixel([479,923], 3.0), m.pixel([371,842], 3.2), 72.0],
		["rows", m.pixel([1018,800], 2.5), m.pixel([818,652], 3.0), 75.0],
		["meadow", m.pixel([590,727], 2.0), m.pixel([757,335], 4.0), 75.0]
	]
	if Game.current_mission_id == "bavaria_occupation":
		var zone: Vector3 = m.mp_zones()[4].xf.origin
		shots.append(["occupation_zone", zone + Vector3(8, 2.5, 9), zone + Vector3(-4, 2, 0), 65.0])
	var antennas := get_tree().get_nodes_in_group("bavaria_roof_antennas")
	if not antennas.is_empty():
		var antenna: Node3D = antennas[0]
		var mount := m.static_root.get_node(String(antenna.get_meta("mounted_on"))) as Node3D
		var visual := mount.get_node("CompleteBuildingVisual") as MeshInstance3D
		for i in 3:
			await get_tree().physics_frame
		shots.append(["antenna_ground",_ground_view(m,mount,visual.get_aabb(),1.0),
			antenna.global_position + Vector3.UP * 3.0,65.0])
		shots.append(["antenna_detail",antenna.global_position + mount.global_basis * Vector3(14,5,18),
			antenna.global_position + Vector3.UP * 4.5,60.0])
		var stand: Vector3 = m.scene_details.antenna_stand
		if stand != Vector3.ZERO:
			# 11/2026: Steigleiter und Plattform am Antennenturm
			shots.append(["antenna_ladder", stand + mount.global_basis * Vector3(7, -1.9, 5), stand + Vector3.UP * 0.3, 60.0])
			shots.append(["antenna_platform_view", stand + Vector3.UP * 1.65, stand + mount.global_basis * Vector3(12, -2.0, 10), 70.0])
	if Game.cli.has("sight_views"):
		shots.clear()
		for view in m.layout.sight_views:
			var camera_position: Vector3 = m.pixel(view.position,1.7)
			var target_position: Vector3 = m.pixel(view.target,1.7)
			# Die Markierung 4 liegt im Layout auf der Krone, nicht am tatsächlichen Kamerastand.
			# Baum frei neben dem Feldweg: Kamera 8 m vor dem Stamm statt im Laub.
			if int(view.number)==3:
				var trunk: Vector3 = m.pixel(m.layout.sniper_tree.pixel,1.7)
				var away := (camera_position-trunk)
				away.y = 0.0
				camera_position = trunk+away.normalized()*8.0
				target_position = m.pixel(m.layout.sniper_tree.pixel,2.6)
			if int(view.number)==4:
				camera_position = m.pixel(m.layout.sniper_tree.pixel,1.7)+Vector3(2.8,0,-2.5)
				target_position = m.pixel(m.layout.sniper_tree.pixel,2.1)
			shots.append(["reference_"+str(int(view.number)),camera_position,target_position,55.0])
		var tree: Vector3 = m.pixel(m.layout.sniper_tree.pixel)
		shots.append(["tree_exterior",tree+Vector3(10,1.7,7),tree+Vector3.UP*2.8,60.0])
		var greenhouse: Vector3 = m.pixel([666,902])
		shots.append(["garden_detail",greenhouse+Vector3(11,1.7,16),greenhouse+Vector3.UP*1.7,65.0])
		var house: Node3D = m.static_root.get_node("haus_18_shed")
		shots.append(["tower_side",m.scene_details.tower_base+house.global_basis*Vector3(12,1.7,15),
			m.scene_details.tower_base+Vector3.UP*7.0,65.0])
		shots.append(["tree_stand",m.scene_details.tree_stand+Vector3.UP*1.7,
			m.scene_details.tree_stand+Vector3.UP*1.7+Vector3(-0.817,0,-0.576)*35,75.0])
		shots.append(["tower_roof",m.scene_details.tower_base+Vector3.UP*7.5,
			m.scene_details.tower_base+Vector3.UP*7.5+m.scene_details.south*100,75.0])
		shots.append(["south_panorama",m.pixel([600,900],1.7),m.pixel([600,900],2.6)+m.scene_details.south*200,75.0])
	if Game.cli.has("border_views"):
		shots.clear()
		for view in [["south",Vector3(0.817,0,0.576)],["north",Vector3(-0.817,0,-0.576)],
			["east",Vector3(0.576,0,-0.817)],["west",Vector3(-0.576,0,0.817)]]:
			var eye: Vector3 = m.scene_details.tower_base+Vector3.UP*7.5
			shots.append(["horizon_"+view[0],eye,eye+view[1]*100,65.0])
		for edge in m.boundary.size():
			var a: Vector2 = m.boundary[edge]
			var b: Vector2 = m.boundary[(edge+1)%m.boundary.size()]
			var mid := (a+b)*0.5
			var inward := -mid.normalized()
			var eye := Vector3(mid.x,1.7,mid.y)+Vector3(inward.x,0,inward.y)*16.0
			shots.append(["border_"+str(edge),eye,Vector3(mid.x,2.0,mid.y),65.0])
	if Game.cli.has("building_audit"):
		shots.clear()
		for building in get_tree().get_nodes_in_group("bavaria_buildings"):
			if Game.cli.has("building_prefix") and not String(building.name).begins_with(String(Game.cli["building_prefix"])):
				continue
			var visual: MeshInstance3D = building.get_node("CompleteBuildingVisual")
			var box := visual.get_aabb()
			for side in [-1.0,1.0]:
				var local_view := box.get_center() + Vector3(box.size.x * 0.8 * side, box.size.y + 10, box.size.z * 0.85 * side)
				shots.append(["building_" + String(building.name) + ("_front" if side > 0 else "_back"),
					building.to_global(local_view), building.to_global(box.get_center()), 65.0,
					maxf(box.size.x,box.size.z) * 1.5])
	if Game.cli.has("ground_audit"):
		shots.clear()
		for i in 3:
			await get_tree().physics_frame
		for building in get_tree().get_nodes_in_group("bavaria_buildings"):
			if Game.cli.has("building_prefix") and not String(building.name).begins_with(String(Game.cli["building_prefix"])):
				continue
			var visual: MeshInstance3D = building.get_node("CompleteBuildingVisual")
			var box := visual.get_aabb()
			for side in [-1.0,1.0]:
				var camera_pos := _ground_view(m, building, box, side)
				var target: Vector3 = building.to_global(Vector3(0, 2.4, side * box.size.z * 0.5))
				shots.append(["ground_" + String(building.name) + ("_front" if side > 0 else "_back"), camera_pos, target, 75.0])
			# Innenansicht aus 1,70 m Höhe, knapp hinter dem südlichen Eingang bzw. der Ruinenbresche.
			shots.append(["ground_" + String(building.name) + "_inside",
				building.to_global(Vector3(0, 1.7, box.size.z * 0.5 - 2.5)),
				building.to_global(Vector3(0, 1.7, -box.size.z * 0.4)), 75.0])
	if Game.cli.has("window_audit"):
		shots.clear()
		for building in get_tree().get_nodes_in_group("bavaria_buildings"):
			if Game.cli.has("building_prefix") and not String(building.name).begins_with(String(Game.cli["building_prefix"])):
				continue
			var windows: Array = building.get_meta("shooting_windows", [])
			for index in windows.size():
				var window: Vector3 = windows[index]
				var side := signf(window.z)
				shots.append(["window_" + String(building.name) + "_" + str(index + 1),
					building.to_global(Vector3(window.x,1.7,window.z - side * 1.4)),
					building.to_global(Vector3(window.x,1.7,window.z + side * 8.0)),75.0])
	for shot in shots:
		if Game.cli.has("shots") and not Array(String(Game.cli["shots"]).split(",")).has(String(shot[0])):
			continue
		# Draufsichten zur Layout-Abnahme ohne kilometerlange atmosphärische Sichtstrecke.
		m.env.fog_enabled = shot[0] not in ["plan", "overview"]
		m.env.volumetric_fog_enabled = shot[0] not in ["plan", "overview"] and Settings.quality >= 2
		var building_audit := String(shot[0]).begins_with("building_")
		var audit := building_audit or String(shot[0]).begins_with("ground_")
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL if shot[0] == "plan" or building_audit else Camera3D.PROJECTION_PERSPECTIVE
		cam.size = float(shot[4]) if shot.size() > 4 else 650*m.layout_scale()
		cam.position = shot[1]
		cam.look_at(shot[2], Vector3.FORWARD if shot[0] == "plan" else Vector3.UP)
		cam.fov = shot[3]
		cam.reset_physics_interpolation()
		for i in (1 if audit else 4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://test_output/bavaria_" + String(shot[0]) + ".png"
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	get_tree().quit()

func _ground_view(m: Mission, building: Node3D, box: AABB, side: float) -> Vector3:
	# Nur tatsächlich betretbare Bodenpunkte: keine Luftansicht und keine Kamera im Nachbarhaus.
	var space := m.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	for distance in [maxf(8.0,box.size.x*0.65), 12.0, 6.0, 3.5, 1.5]:
		for fraction in [0.0, -0.3, 0.3, -0.45, 0.45, -0.8, 0.8, -1.2, 1.2]:
			var pos := building.to_global(Vector3(box.size.x * fraction, 1.7, side * (box.size.z * 0.5 + distance)))
			if not m.inside_map(pos):
				continue
			var inside_building := false
			for footprint in m.building_footprints:
				if Geometry2D.is_point_in_polygon(Vector2(pos.x,pos.z), footprint):
					inside_building = true
					break
			if inside_building:
				continue
			var ground_query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos - Vector3.UP * 2.0, 1)
			var ground := space.intersect_ray(ground_query)
			if ground.is_empty() or absf(ground.position.y) > 0.2:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis(),pos)
			query.collision_mask = 1 | 16
			var target := building.to_global(Vector3(0,2.4,side * box.size.z * 0.5))
			var view_ray := PhysicsRayQueryParameters3D.create(pos,target,1)
			var view_hit := space.intersect_ray(view_ray)
			var clear_view := view_hit.is_empty() or building.is_ancestor_of(view_hit.collider)
			if space.intersect_shape(query).is_empty() and clear_view:
				print("GROUND CAMERA ",building.name," height=",pos.y)
				return pos
	push_error("Keine freie Bodenkamera gefunden: " + building.name)
	return building.to_global(Vector3(0,1.7,side*(box.size.z*0.5+3.5)))
