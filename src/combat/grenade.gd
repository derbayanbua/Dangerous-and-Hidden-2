class_name Grenade
extends RigidBody3D
## Splittergranate mit Zeitzünder. Schaden nur bei freier Sichtlinie
## zwischen Explosionspunkt und Trefferzone (Deckung schützt).

var data: WeaponData
var thrower: Node
var team := 0
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	mass = 0.6
	continuous_cd = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.25
	physics_material_override.friction = 0.8
	angular_damp = 2.0
	# Ovale Granaten rollen kaum: nach dem ersten Aufprall stark bremsen
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_first_contact, CONNECT_ONE_SHOT)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.05
	cs.shape = s
	add_child(cs)
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.12
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.color if data else Color(0.3, 0.33, 0.2)
	mi.material_override = mat
	add_child(mi)


func _on_first_contact(_body: Node) -> void:
	linear_damp = 3.5
	angular_damp = 10.0


func _physics_process(delta: float) -> void:
	_t += delta
	if data and _t >= data.fuse_time:
		explode()


func explode() -> void:
	var pos := global_position
	var radius := data.blast_radius
	Effects.explosion(pos, radius)
	Events.emit_noise(pos, data.noise_radius, thrower if is_instance_valid(thrower) else null, team, &"explosion")
	var space := get_world_3d().direct_space_state
	for s in get_tree().get_nodes_in_group("soldiers"):
		var sol := s as Soldier
		if sol == null or not sol.alive:
			continue
		var target := sol.global_position + Vector3.UP * 0.5
		var dist := pos.distance_to(target)
		if dist > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.15, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue   # Deckung
		var falloff := 1.0 - dist / radius
		var dmg := data.damage * falloff * falloff
		var zone := &"torso"
		if sol.stance == Soldier.Stance.PRONE:
			dmg *= 0.6   # liegend weniger Splitterfläche
		sol.apply_hit(dmg, zone, thrower if is_instance_valid(thrower) else null, (target - pos).normalized())
	# Fahrzeuge und Hunde (on_bullet_hit) nehmen Explosionsschaden ohne Deckungsprüfung
	for n in get_tree().get_nodes_in_group("vehicles") + get_tree().get_nodes_in_group("dogs"):
		var n3 := n as Node3D
		var dv := pos.distance_to(n3.global_position + Vector3.UP * 0.5)
		if dv < radius + 1.5:
			var f := 1.0 - minf(dv / (radius + 1.5), 1.0)
			n3.on_bullet_hit(data.damage * 2.5 * f, thrower if is_instance_valid(thrower) else null)
	queue_free()
