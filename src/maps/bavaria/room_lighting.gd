extends Node3D
## Jede vorhandene Raumfläche erhält eine sichtbare historische Leuchte und echtes Licht.
var mission: Mission
var initialized := false
var fixtures: Array[Node3D] = []
var coverage: Array[Dictionary] = []

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	while not mission.nav_ready:
		await get_tree().physics_frame
	var houses := {}
	for room in get_tree().get_nodes_in_group("bavaria_furnished_rooms"):
		var id: String = room.get_meta("house")
		var rect: Rect2 = room.get_meta("room_rect")
		var floor_y: float = room.get_meta("floor_height")
		_add_lamp(room,rect.get_center(),floor_y,id,String(room.name))
		houses[id] = true
	var buildings := get_tree().get_nodes_in_group("bavaria_buildings")
	buildings.append_array(get_tree().get_nodes_in_group("bavaria_aux_houses"))
	for house in buildings:
		var size: Vector2 = house.get_meta("footprint_size",Vector2.ZERO)
		if size==Vector2.ZERO:
			var box: AABB = house.get_node("CompleteBuildingVisual").get_aabb()
			size = Vector2(box.size.x,box.size.z)
		if houses.has(String(house.name)):
			# Flure sind im Einrichtungsregister bisher nicht als Zimmer geführt.
			for side in [-1.0,1.0]:
				_add_lamp(house,Vector2(0,size.y*0.25*side),0.06,String(house.name),"Flur_"+str(side))
			# Zusammenhängender zugänglicher OG-Flur bzw. geschlossener Dachraum.
			_add_lamp(house,Vector2(0,0),3.18,String(house.name),"ObergeschossFlur" if house.is_in_group("bavaria_stair_houses") else "Dachraum")
			if house.is_in_group("bavaria_stair_houses"):
				_add_lamp(house,Vector2(size.x*0.30,size.y*0.29),3.18,String(house.name),"Treppenpodest")
		else:
			var point := Vector2.ZERO
			if house.is_in_group("bavaria_ruins"):
				point = Vector2(-size.x*0.30,-size.y*0.25)
			_add_lamp(house,point,0.06,String(house.name),"Innenraum")
	initialized = true
	print("BAVARIA LIGHTS: ",fixtures.size()," sichtbare Raumleuchten mit Licht")

func _add_lamp(parent: Node3D,point: Vector2,floor_y: float,house: String,room: String) -> void:
	var base := parent.to_global(Vector3(point.x,floor_y,point.y))
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base+Vector3.UP*0.4,base+Vector3.UP*14.0,1))
	var ceiling_y := float(hit.position.y) if not hit.is_empty() else base.y+2.9
	if hit.is_empty():
		# Kulissenhäuser haben absichtlich keine Physikkollision; hier trägt das sichtbare Dach.
		var visual := parent.get_node_or_null("CompleteBuildingVisual") as MeshInstance3D
		if visual:
			ceiling_y = (visual.global_transform*visual.get_aabb()).end.y-0.08
	var lamp_y := minf(base.y+2.42,ceiling_y-0.30)
	lamp_y = maxf(lamp_y,base.y+1.2)
	var holder := Node3D.new()
	holder.name = "Leuchte_"+house+"_"+room
	add_child(holder)
	holder.global_position = Vector3(base.x,lamp_y,base.z)
	holder.add_to_group("bavaria_room_fixtures")
	holder.set_meta("house",house)
	holder.set_meta("room",room)
	# Dunkler Blechschirm, warme Glühlampe, dünnes Kabel bis zur echten Decke.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.15,0.14,0.10)
	steel.metallic = 0.35
	steel.roughness = 0.65
	var cord_height := maxf(0.04,ceiling_y-lamp_y-0.10)
	_cylinder(holder,0.008,0.008,cord_height,Vector3.UP*(0.10+cord_height*0.5),steel)
	_cylinder(holder,0.07,0.20,0.11,Vector3.UP*0.09,steel)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0,0.73,0.38)
	glow.emission_enabled = true
	glow.emission = Color(1.0,0.57,0.20)
	glow.emission_energy_multiplier = 2.0
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	bulb.mesh = sphere
	bulb.material_override = glow
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.visibility_range_end = 32.0
	holder.add_child(bulb)
	var light := OmniLight3D.new()
	light.name = "Raumlicht"
	light.light_color = Color(1.0,0.73,0.43)
	light.light_energy = 1.6
	light.omni_range = 4.2
	light.omni_attenuation = 0.8
	light.shadow_enabled = true
	light.shadow_bias = 0.035
	light.distance_fade_enabled = true
	light.distance_fade_begin = 18.0
	light.distance_fade_length = 8.0
	light.position.y = -0.10
	holder.add_child(light)
	light.add_to_group("bavaria_room_lights")
	fixtures.append(holder)
	coverage.append({"house":house,"room":room,"floor":base.y,"fixture":holder,"light":light})

func _cylinder(parent: Node3D,top: float,bottom: float,height: float,pos: Vector3,mat: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = pos
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 32.0
	parent.add_child(visual)
