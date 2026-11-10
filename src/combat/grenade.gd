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


## Raketen-/Granatgeschoss (Aufschlagzünder) trifft ein Fahrzeug: Original hd2.exe 0x449290 – Direkttreffer
## Damage(7, Explosionsstärke) am Treffpunkt, danach Explosion mit 0,1 × Stärke; Aufschlag in der Welt: 0,5 × Stärke
## (Faktor im Nachbau nur für Fahrzeug-Schadensmodelle, docs/re_notes_ai.md §4) [B]
var _veh_factor := 1.0


## Direkttreffer-Stärke (0x449290 vor Damage(7)): im Einzelspieler (0x982100 & 7 == 7) auf Schwierigkeit 1 (0x6B6700)
## und Schütze Seite 1 (Spielertrupp, Mensch +0x19C) × 4, sonst × 1 [B]. Bedingung „Geschoss +0x68 ≠ 0“ (Raketenmodell)
## gilt im Nachbau für alle Aufschlaggeschosse [P].
static func direct_hit_factor(by: Node, single_player: bool, difficulty: int) -> float:
	if single_player and difficulty == 1 and WeaponDB.orig_side(by) == 1:
		return 4.0
	return 1.0
var _last_vel := Vector3.ZERO


func _on_first_contact(body: Node) -> void:
	if impact:
		var v: Node = body
		for i in 3:
			if v == null or v is Vehicle:
				break
			v = v.get_parent()
		if v is Vehicle:
			_veh_factor = 0.1
			var dir := _last_vel.normalized() if _last_vel.length() > 0.1 else -global_basis.z
			var by: Node = thrower if is_instance_valid(thrower) else null
			(v as Vehicle).projectile_hit(7, (data.damage if data else 0.0) * direct_hit_factor(by, not Net.is_online,
				Game.difficulty()), global_position, dir, by)
		elif not (body is Soldier):
			_veh_factor = 0.5
		explode.call_deferred()
		return
	linear_damp = 3.5
	angular_damp = 10.0
	# Aufprall: Original Kat. 5/12 „Grenade default“ (Dateien fehlen in der Installation), im Wasser 5/1
	if _in_water(global_position):
		OrigAudio.play_group(OrigAudio.CAT_FALL, OrigAudio.FALL_GRENADE_WATER, global_position)
	else:
		OrigAudio.play_group(OrigAudio.CAT_FALL, 12, global_position)


func _in_water(p: Vector3) -> bool:
	var m := Game.current_mission()
	if m == null or not m.has_method("water_level_at"):
		return false
	var lvl: float = m.water_level_at(p)
	return not is_nan(lvl) and p.y < lvl + 0.3


func _physics_process(delta: float) -> void:
	_t += delta
	if impact:
		_last_vel = linear_velocity
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
	# Original Kat. 6/0 „Explosion Grenade“, im Wasser 6/1 „Explosion Water“ (Raketen: ebenfalls 6/0 = Annahme)
	Effects.explosion(pos, radius, [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_WATER if _in_water(pos) else OrigAudio.EXP_GRENADE])
	Events.emit_noise(pos, data.noise_radius, thrower if is_instance_valid(thrower) else null, team, &"explosion")
	var space := get_world_3d().direct_space_state
	Net.hit_source = String(data.id) if data else ""     # Integration Kill-Feed: Waffe der Explosion (nicht Hand des Werfers)
	# Original hd2.exe 0x6DE780: linear (1 − d/r) · Stärke, Zone Körper, keine Haltungsminderung (G-021: WeaponDB.apply_blast)
	var by: Node = thrower if is_instance_valid(thrower) else null
	WeaponDB.apply_blast(get_tree(), space, pos, radius, data.damage, by, 0.15, false)
	Net.hit_source = ""
	# Fahrzeuge und Hunde (on_bullet_hit) nehmen Explosionsschaden ohne Deckungsprüfung
	OrigInteractive.damage_objects(get_tree(), pos, radius, data.damage, by, _veh_factor)
	queue_free()
