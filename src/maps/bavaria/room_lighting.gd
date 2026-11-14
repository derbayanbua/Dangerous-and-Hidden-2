extends Node3D
## Jede vorhandene Raumfläche erhält eine sichtbare historische Leuchte und echtes Licht.
## Raumliste aus dem Bau (`room_inventory`): eingerichtete Zimmer (inkl. Bad/WC), Flure, Obergeschoss/Dachraum,
## Treppenpodest, Keller Haus 16, Anbauten, Scheunen/Schuppen/Holzhaus, Ruinen und Kulissenhäuser.
## Tageszyklus (day_night.gd): `set_level(f)` – 0 = aus (Tag), 1 = volle Leistung (Nacht), dazwischen gedimmt.
var mission: Mission
var initialized := false
var fixtures: Array[Node3D] = []
var coverage: Array[Dictionary] = []
var room_inventory: Array[Dictionary] = []
var level := 1.0
const ENERGY := 1.6
var _steel: StandardMaterial3D
var _glow: StandardMaterial3D

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	while not mission.nav_ready:
		await get_tree().physics_frame
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.15,0.14,0.10)
	_steel.metallic = 0.35
	_steel.roughness = 0.65
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0,0.73,0.38)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0,0.57,0.20)
	_glow.emission_energy_multiplier = 2.0
	room_inventory = collect_rooms()
	for r in room_inventory:
		_add_lamp(r.parent,r.point,r.floor,r.house,r.room,r.get("shadow",true))
	initialized = true
	set_level(level)
	print("BAVARIA LIGHTS: ",fixtures.size()," sichtbare Raumleuchten mit Licht für ",room_inventory.size()," Räume")

## Raumliste aus dem tatsächlichen Bau (Gruppen/Metadaten der Gebäude), unabhängig von den Leuchten.
func collect_rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var houses := {}
	for room in get_tree().get_nodes_in_group("bavaria_furnished_rooms"):
		var id: String = room.get_meta("house")
		var rect: Rect2 = room.get_meta("room_rect")
		out.append({"parent":room,"point":rect.get_center(),"floor":float(room.get_meta("floor_height")),"house":id,
			"room":String(room.name),"rect":rect})
		houses[id] = true
	var buildings := get_tree().get_nodes_in_group("bavaria_buildings")
	buildings.append_array(get_tree().get_nodes_in_group("bavaria_reference_extensions"))
	buildings.append_array(get_tree().get_nodes_in_group("bavaria_aux_houses"))
	for house in buildings:
		var size: Vector2 = house.get_meta("footprint_size",Vector2.ZERO)
		if size==Vector2.ZERO:
			var visual := house.get_node_or_null("CompleteBuildingVisual") as MeshInstance3D
			if visual == null:
				continue
			var box: AABB = visual.get_aabb()
			size = Vector2(box.size.x,box.size.z)
		var id := String(house.name)
		var aux: bool = house.is_in_group("bavaria_aux_houses")
		if houses.has(id):
			# Flure sind im Einrichtungsregister nicht als Zimmer geführt.
			for side in [-1.0,1.0]:
				out.append({"parent":house,"point":Vector2(0,size.y*0.25*side),"floor":0.06,"house":id,"room":"Flur_"+str(side)})
			# Zusammenhängender zugänglicher OG-Flur bzw. geschlossener Dachraum.
			out.append({"parent":house,"point":Vector2(0,0),"floor":3.18,"house":id,
				"room":"ObergeschossFlur" if house.is_in_group("bavaria_stair_houses") else "Dachraum"})
			if house.is_in_group("bavaria_stair_houses"):
				out.append({"parent":house,"point":Vector2(size.x*0.30,size.y*0.29),"floor":3.18,"house":id,"room":"Treppenpodest"})
			var levels: Dictionary = house.get_meta("plan_levels",{})
			if levels.has("cellar_floor"):
				for p in [Vector2(-2.5,2.4),Vector2(3.0,-2.4)]:
					out.append({"parent":house,"point":p,"floor":float(levels.cellar_floor),"house":id,
						"room":"Keller_"+("West" if p.x<0 else "Ost")})
		else:
			var point := Vector2.ZERO
			if house.is_in_group("bavaria_ruins"):
				point = Vector2(-size.x*0.30,-size.y*0.25)
			var kind := "Anbau" if house.is_in_group("bavaria_reference_extensions") else ("Kulisse" if aux else "Innenraum")
			# Kulissenhäuser außerhalb der Grenze: Licht ohne Schatten (niemand darin, nur Fensterschein).
			out.append({"parent":house,"point":point,"floor":0.06,"house":id,"room":kind,"shadow":not aux})
	return out

func _add_lamp(parent: Node3D,point: Vector2,floor_y: float,house: String,room: String,shadow := true) -> void:
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
	holder.set_meta("floor_y",base.y)
	# Dunkler Blechschirm, warme Glühlampe, dünnes Kabel bis zur echten Decke.
	var cord_height := maxf(0.04,ceiling_y-lamp_y-0.10)
	_cylinder(holder,0.008,0.008,cord_height,Vector3.UP*(0.10+cord_height*0.5),_steel)
	_cylinder(holder,0.07,0.20,0.11,Vector3.UP*0.09,_steel)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	bulb.mesh = sphere
	bulb.material_override = _glow
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.visibility_range_end = 32.0
	holder.add_child(bulb)
	var light := OmniLight3D.new()
	light.name = "Raumlicht"
	light.light_color = Color(1.0,0.73,0.43)
	light.light_energy = ENERGY
	light.omni_range = 4.2
	light.omni_attenuation = 0.8
	# Schatten nur in begehbaren Räumen; Entfernungsausblendung 18–26 m.
	light.shadow_enabled = shadow
	light.shadow_bias = 0.035
	light.distance_fade_enabled = true
	light.distance_fade_begin = 18.0
	light.distance_fade_length = 8.0
	light.position.y = -0.10
	holder.add_child(light)
	light.add_to_group("bavaria_room_lights")
	fixtures.append(holder)
	coverage.append({"house":house,"room":room,"floor":base.y,"fixture":holder,"light":light})

## 0 = aus, 1 = an; dazwischen gedimmt. Ausgeschaltete Lichter werden unsichtbar (kein Renderaufwand).
func set_level(f: float) -> void:
	level = clampf(f,0.0,1.0)
	if not initialized:
		return
	for c in coverage:
		var light: OmniLight3D = c.light
		light.light_energy = ENERGY*level
		light.visible = level>0.02
	if _glow:
		_glow.emission_energy_multiplier = 0.15+1.85*level
		_glow.albedo_color = Color(1.0,0.73,0.38).lerp(Color(0.80,0.78,0.72),1.0-level)

func lights_on() -> int:
	var n := 0
	for c in coverage:
		if (c.light as OmniLight3D).visible and (c.light as OmniLight3D).light_energy>0.05:
			n += 1
	return n

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
