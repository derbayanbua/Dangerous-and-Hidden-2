class_name Grenade
extends RigidBody3D
## Splittergranate mit Zeitzünder. Schaden nur bei freier Sichtlinie
## zwischen Explosionspunkt und Trefferzone (Deckung schützt).

var data: WeaponData
var thrower: Node
var team := 0
var _t := 0.0
var impact := false        ## Rakete (Raketenwerfer): Aufschlagzünder, kaum Fallkurve


func _ready() -> void:
	if impact:
		gravity_scale = 0.15
	collision_layer = 0
	collision_mask = 1 | (1 << 1) if impact else 1     # Rakete trifft auch Figuren/Fahrzeuge
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
	if impact:
		explode.call_deferred()
		return
	linear_damp = 3.5
	angular_damp = 10.0


func _physics_process(delta: float) -> void:
	_t += delta
	if impact:
		if _t > 8.0:
			explode()      # Selbstzerlegung nach maximaler Flugzeit
		return
	if data and _t >= data.fuse_time:
		explode()


var _exploded := false


func explode() -> void:
	if _exploded:
		return
	_exploded = true
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
	OrigInteractive.damage_objects(get_tree(), pos, radius, data.damage, thrower if is_instance_valid(thrower) else null)
	queue_free()
