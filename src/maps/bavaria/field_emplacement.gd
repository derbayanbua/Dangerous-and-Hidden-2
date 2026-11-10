extends RefCounted
## Vorhandene Flak-38-Interaktion/Waffe, ausschließlich diese Karte.
var m: Mission
var gun: OrigInteractive.OrigEmplacement
var frame: Node3D

class FieldFlak extends OrigInteractive.OrigEmplacement:
	var operator_offset := Vector3(0,0.1,2.8)
	var exit_spot := Vector3.ZERO
	var traverse: Node3D
	var elevation: Node3D
	var traverse_rest := Vector3.ZERO
	var elevation_rest := Vector3.ZERO
	var base_yaw := 0.0
	var last_operator := 0
	var pending_operator := 0

	@rpc("authority","call_remote","reliable")
	func sync_operator(id: int) -> void:
		if id == 0:
			pending_operator = 0
			if gunner:
				dismount()
			return
		var s: Soldier = Net._soldiers.get(id)
		if not is_instance_valid(s):
			pending_operator = id
			return
		pending_operator = 0
		if gunner != s:
			if gunner:
				dismount()
			mount(s)

	func serialize() -> Dictionary:
		var state := super.serialize()
		state["operator"] = int(gunner.get_meta("net_peer",0)) if is_instance_valid(gunner) else 0
		return state

	func deserialize(state: Dictionary) -> void:
		super.deserialize(state)
		sync_operator(int(state.get("operator",0)))

	func shot_origin() -> Vector3:
		return muzzle.global_position if is_instance_valid(muzzle) else gunner.eye_position()+gunner.aim_direction()*3.0

	func shot_exclusions() -> Array[RID]:
		var out: Array[RID] = []
		for body in frame.find_children("*","CollisionObject3D",true,false):
			out.append(body.get_rid())
		return out

	func gunner_spot() -> Vector3:
		return frame.to_global(operator_offset)

	func can_interact(s: Soldier) -> bool:
		return super.can_interact(s) and s.alive

	func interact(s: Soldier) -> void:
		# Der vorhandene Net._use-Vertrag liefert den Versuch an den Host.
		# Nur der Host vergibt den Sitz; Clients warten auf sync_operator.
		if Net.is_online and not multiplayer.is_server():
			return
		if can_interact(s):
			super.interact(s)

	func mount(s: Soldier) -> void:
		if not can_interact(s):
			return
		exit_spot = s.global_position
		super.mount(s)
		s.global_position = gunner_spot()

	func dismount() -> void:
		var s := gunner
		super.dismount()
		if is_instance_valid(s):
			s.global_position = exit_spot
			s.velocity = Vector3.ZERO

	func _physics_process(delta: float) -> void:
		super._physics_process(delta)
		if Net.is_online:
			if multiplayer.is_server():
				var operator := int(gunner.get_meta("net_peer",0)) if is_instance_valid(gunner) else 0
				if operator != last_operator:
					last_operator = operator
					sync_operator.rpc(operator)
			elif pending_operator != 0:
				sync_operator(pending_operator)
		if is_instance_valid(gunner) and gunner.alive:
			# Originalmodell bietet getrennte Horizontal-/Vertikalachsen.
			gunner.look_pitch = clampf(gunner.look_pitch,-0.17,1.40)
			if traverse:
				traverse.rotation.y = traverse_rest.y + wrapf(gunner.look_yaw-base_yaw,-PI,PI)
			if elevation:
				elevation.rotation.x = elevation_rest.x + gunner.look_pitch

func build(mission: Mission) -> void:
	m = mission
	frame = Node3D.new()
	frame.name = "WiesenFlak38"
	m.static_root.add_child(frame)
	frame.position = m.pixel([690,490])
	frame.rotation.y = -1.0
	var model := OrigLevel.parse_glb(OrigLevel.cache_root()+"/arctic4/models/la_flak4x38.glb")
	if model == null:
		push_error("Bavaria: vorhandenes Flakmodell fehlt")
		return
	frame.add_child(model)
	# Die Vorlage stammt aus einer Winterkarte: matte dunkle Feldlackierung für Bayern.
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(i)
			if original is StandardMaterial3D:
				var paint := original.duplicate() as StandardMaterial3D
				paint.albedo_color *= Color(0.30,0.34,0.25)
				paint.metallic = 0.15
				paint.roughness = 0.88
				mesh.set_surface_override_material(i,paint)
	var bounds: AABB = m._templates.mesh_bounds(model,Transform3D.IDENTITY)
	model.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	m._templates._mesh_colliders(model)
	gun = FieldFlak.new()
	gun.name = "WiesenFlak_Bedienung"
	m.dynamic_root.add_child(gun)
	gun.init(null,frame,{"name":"bavaria_wiesen_flak38","inventory":[209,209,209,209,209,209]},WeaponDB.get_weapon(&"flak38"),0)
	gun.traverse = model.find_child("HORT00",true,false)
	gun.elevation = model.find_child("VERT00",true,false)
	if gun.traverse:
		gun.traverse_rest = gun.traverse.rotation
	if gun.elevation:
		gun.elevation_rest = gun.elevation.rotation
	gun.base_yaw = frame.rotation.y
	gun.muzzle = model.find_child("SHDUM00",true,false)
	gun.global_position = gun.gunner_spot()+Vector3.UP*0.5
	gun.add_to_group("bavaria_field_flak")
	frame.set_meta("source","arctic4/models/la_flak4x38")
	frame.set_meta("bounds_size",bounds.size)
	m._placed.append({"pos":frame.position,"radius":6.0})
	m._templates.reused_models += 1
	print("BAVARIA FLAK bounds=",bounds.size," operator=",gun.gunner_spot())
