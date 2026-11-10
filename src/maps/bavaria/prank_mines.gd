extends Node3D
## Zehn harmlose, einmalig pro Runde auslösende Rauch-/Geräuschminen.
const SOUND := preload("res://assets/maps/bavaria/audio/fart2.mp3")
const COUNT := 10
const TRIGGER_RADIUS := 0.55
var mission: Mission
var mines: Array[Node3D] = []
var spent: Array[bool] = []
var effect_count := 0
var initialized := false
var _elapsed := 0.0

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	while not mission.nav_ready:
		await get_tree().physics_frame
	# Sechs Laufwege sowie vier betretbare Gebäude; identische statische Suche auf allen Peers.
	var anchors: Array[Vector3] = []
	for road in mission.layout.paths:
		if anchors.size() == 6:
			break
		anchors.append(mission.pixel(road.points[0]).lerp(mission.pixel(road.points[1]),0.48))
	for id in ["haus_16","haus_18_shed","woodland_shed","reihe_38_0"]:
		var house := mission.static_root.get_node(id) as Node3D
		anchors.append(house.to_global(Vector3(0,0,1.0)))
	for index in anchors.size():
		var point := _find_floor(anchors[index])
		if not is_finite(point.x):
			push_error("Bavaria: Kein sicherer Minenplatz für Index %d" % index)
			continue
		var mine := MeshInstance3D.new()
		mine.name = "Rauchmine_%02d" % (index+1)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.075
		mesh.bottom_radius = 0.085
		mesh.height = 0.025
		mesh.radial_segments = 12
		mine.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.19,0.18,0.12)
		material.roughness = 1.0
		mine.material_override = material
		add_child(mine)
		mine.global_position = point+Vector3.UP*0.014
		mine.add_to_group("bavaria_prank_mines")
		mines.append(mine)
		spent.append(false)
	initialized = true
	if Net.is_online and not multiplayer.is_server():
		request_state.rpc_id(1)

func _find_floor(anchor: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.8
	for radius in [0.0,0.7,1.4,2.1,2.8]:
		for step in 12:
			var angle := float(step)*TAU/12.0
			var pos := anchor+Vector3(cos(angle)*radius,0,sin(angle)*radius)
			if not mission.inside_map(pos):
				continue
			var safe := true
			for spawn in mission.mp_spawns():
				if Vector2(pos.x-spawn.pos.x,pos.z-spawn.pos.z).length()<3.0:
					safe = false
			for mine in mines:
				if mine.global_position.distance_to(pos)<3.0:
					safe = false
			if not safe:
				continue
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos+Vector3.UP*0.7,pos-Vector3.UP*0.5,1))
			if hit.is_empty() or hit.normal.y<0.9:
				continue
			var floor_pos: Vector3 = hit.position
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = floor_pos+Vector3.UP*0.94
			query.collision_mask = 1
			if space.intersect_shape(query,1).is_empty():
				return floor_pos
	return Vector3(INF,INF,INF)

func _physics_process(delta: float) -> void:
	if not initialized or (Net.is_online and not multiplayer.is_server()):
		return
	_elapsed += delta
	if _elapsed<0.1:
		return
	_elapsed = 0.0
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if not soldier is Soldier or not soldier.alive or soldier.vehicle != null or soldier.is_climbing():
			continue
		for index in mines.size():
			var offset: Vector3 = soldier.global_position-mines[index].global_position
			if not spent[index] and absf(offset.y)<0.4 and Vector2(offset.x,offset.z).length()<TRIGGER_RADIUS:
				if Net.is_online:
					trigger.rpc(index)
				else:
					trigger(index)

@rpc("authority","call_local","reliable")
func trigger(index: int) -> void:
	if index<0 or index>=mines.size() or spent[index]:
		return
	spent[index] = true
	mines[index].visible = false
	effect_count += 1
	var effect := Node3D.new()
	effect.name = "KurzeRauchschwade"
	add_child(effect)
	effect.global_position = mines[index].global_position
	effect.add_to_group("bavaria_prank_effects")
	var audio := AudioStreamPlayer3D.new()
	audio.stream = SOUND
	audio.volume_db = -5.0
	audio.unit_size = 4.0
	audio.max_distance = 25.0
	effect.add_child(audio)
	audio.play()
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 10
	smoke.lifetime = 1.15
	smoke.explosiveness = 0.7
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.12
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.8
	smoke.gravity = Vector3(0.12,0.05,-0.08)
	smoke.scale_amount_min = 0.25
	smoke.scale_amount_max = 0.55
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	smoke.mesh = mesh
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.65,0.65,0.6,0.18))
	gradient.set_color(1,Color(0.65,0.65,0.6,0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5)
	texture.fill_to = Vector2(0.5,1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.material_override = mat
	var fade := Gradient.new()
	fade.set_color(0,Color(1,1,1,0))
	fade.add_point(0.15,Color.WHITE)
	fade.set_color(fade.get_point_count()-1,Color(1,1,1,0))
	smoke.color_ramp = fade
	effect.add_child(smoke)
	smoke.emitting = true
	get_tree().create_timer(maxf(SOUND.get_length()+0.2,2.1)).timeout.connect(effect.queue_free)

@rpc("any_peer","call_remote","reliable")
func request_state() -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		while not initialized:
			await get_tree().physics_frame
		if multiplayer.get_peers().has(peer):
			sync_state.rpc_id(peer,spent)

@rpc("authority","call_remote","reliable")
func sync_state(state: Array) -> void:
	for index in mini(state.size(),mines.size()):
		if state[index]:
			spent[index] = true
			mines[index].visible = false
