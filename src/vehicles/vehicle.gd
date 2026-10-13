class_name Vehicle
extends VehicleBody3D
## Fahrzeug (Original belegt: HUMAN_Drive, HUMAN_BoardVehicle, tables\tyres.bin).
## Physik über VehicleBody3D/VehicleWheel3D. Sitze: 0 = Fahrer, 1..n Mitfahrer.
## Insassen bleiben Soldaten mit aktiven Trefferzonen (sie können beschossen
## werden); Mitfahrer dürfen feuern. Laufender Motor ist weit hörbar.
## PLATZHALTER-MODELL: Kübelwagen aus Grundkörpern.

signal destroyed_vehicle

@export var vehicle_name := "Kübelwagen"
@export var persistent_id := ""
@export var max_health := 400.0
@export var max_engine_force := 2200.0
@export var max_brake := 40.0
@export var max_steer := 0.55

var health := 400.0
var seats: Array[Node3D] = []
var occupants: Array = [null, null, null, null]
var wrecked := false
## Eingaben (vom PlayerController gesetzt, wenn der Spieler fährt)
var throttle := 0.0
var steer_input := 0.0
var handbrake := false

var _noise_t := 0.0
var _entry: Interactable

## Originalmodell statt Platzhalter-K?belwagen (vor add_child setzen). Das Modell muss
## entlang lokal +Z ausgerichtet sein; Kollisionsbox und Radstand folgen seiner Gr??e.
var custom_visual: Node3D
var _size := Vector3(1.6, 0.7, 3.7)
## Skriptgesteuertes Fahren (Original HUMAN_Drive): kinematisch entlang Zielpunkten,
## am Boden ausgerichtet. fuel = Car_SetFuel (0 = Motor springt nicht an).
var fuel := 100.0
var script_driving := false
var _drive_goal := Vector3.INF
var _drive_speed := 0.0


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("persistent")
	collision_layer = 1
	collision_mask = 1 | (1 << 1)
	mass = 900.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0)
	health = max_health
	_build_body()
	_build_wheels()
	# VehicleBody3D fährt entlang lokal +Z: vorne = +Z (Fahrer links vorn)
	for p in [Vector3(0.38, 0.75, 0.15), Vector3(-0.38, 0.75, 0.15), Vector3(0.38, 0.8, -0.85), Vector3(-0.38, 0.8, -0.85)]:
		var s := Node3D.new()
		s.position = p
		add_child(s)
		seats.append(s)
	_entry = VehicleEntry.new()
	_entry.vehicle = self
	add_child(_entry)
	_entry.position = Vector3(1.3, 0, 0)


func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	if custom_visual:
		add_child(custom_visual)
		var box := _visual_aabb(custom_visual)
		_size = Vector3(maxf(box.size.x, 1.0), maxf(box.size.y - 0.6, 0.6), maxf(box.size.z, 2.0))
		bs.size = _size
		cs.shape = bs
		cs.position = Vector3(box.get_center().x, 0.6 + _size.y * 0.5, box.get_center().z)
		add_child(cs)
		return
	bs.size = _size
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.36, 0.35, 0.28)
	paint.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.11)
	var parts := [
		[Vector3(1.55, 0.45, 3.6), Vector3(0, 0.62, 0), paint],     # Wanne
		[Vector3(1.4, 0.25, 1.1), Vector3(0, 0.95, 1.2), paint],    # Motorhaube
		[Vector3(1.4, 0.4, 0.05), Vector3(0, 1.2, 0.62), dark],     # Windschutzrahmen
		[Vector3(0.5, 0.15, 0.5), Vector3(0.38, 0.85, 0.15), dark],    # Sitze
		[Vector3(0.5, 0.15, 0.5), Vector3(-0.38, 0.85, 0.15), dark],
		[Vector3(1.3, 0.15, 0.6), Vector3(0, 0.9, -0.85), dark],
		[Vector3(0.05, 0.3, 0.05), Vector3(0.35, 1.05, 0.45), dark],   # Lenkrad-Säule
		[Vector3(0.5, 0.35, 0.3), Vector3(0, 0.9, -1.75), dark],    # Reserverad (hinten)
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		mi.mesh = b
		mi.position = p[1]
		mi.material_override = p[2]
		add_child(mi)


func _build_wheels() -> void:
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.08, 0.08, 0.08)
	var hx := _size.x * 0.5 - 0.05
	var hz := _size.z * 0.5 - 0.6
	for p in [Vector3(-hx, 0.4, -hz), Vector3(hx, 0.4, -hz), Vector3(-hx, 0.4, hz), Vector3(hx, 0.4, hz)]:
		var w := VehicleWheel3D.new()
		w.position = p
		w.wheel_radius = 0.38
		w.wheel_rest_length = 0.18
		w.suspension_travel = 0.22
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 9000.0
		w.damping_compression = 1.9
		w.damping_relaxation = 2.4
		w.wheel_friction_slip = 2.4
		w.wheel_roll_influence = 0.15
		w.use_as_steering = p.z > 0.0     # Vorderräder (+Z)
		w.use_as_traction = p.z < 0.0     # Hinterradantrieb wie beim Kübelwagen
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.38
		c.bottom_radius = 0.38
		c.height = 0.22
		c.radial_segments = 14
		mi.mesh = c
		mi.rotation.z = PI * 0.5
		mi.material_override = tire
		mi.visible = custom_visual == null     # Originalmodell bringt eigene R?der mit
		w.add_child(mi)
		add_child(w)


# --- Insassen ----------------------------------------------------------------

func driver() -> Soldier:
	var d = occupants[0]
	return d if is_instance_valid(d) else null


func free_seat() -> int:
	for i in occupants.size():
		if not is_instance_valid(occupants[i]):
			occupants[i] = null
			return i
	return -1


func board(s: Soldier, prefer_driver := false) -> bool:
	if wrecked or s.vehicle != null or not s.alive:
		return false
	var idx := -1
	if prefer_driver and driver() == null:
		idx = 0
	else:
		idx = free_seat()
		if idx == 0 and not prefer_driver:
			# Fahrersitz für den Spieler freihalten, wenn Mitfahrer einsteigen
			for i in range(1, occupants.size()):
				if occupants[i] == null:
					idx = i
					break
	if idx < 0:
		return false
	occupants[idx] = s
	s.enter_vehicle(self, idx)
	return true


func leave(s: Soldier) -> void:
	var idx := occupants.find(s)
	if idx < 0:
		return
	occupants[idx] = null
	var side := -1.0 if seats[idx].position.x < 0 else 1.0
	var out := global_transform * Vector3(side * 1.6, 0.4, seats[idx].position.z)
	s.exit_vehicle(out)


func leave_all() -> void:
	for o in occupants.duplicate():
		if is_instance_valid(o):
			leave(o)


func seat_transform(idx: int) -> Transform3D:
	return seats[idx].global_transform


# --- Fahren ------------------------------------------------------------------

func _visual_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var b: AABB = (global_transform.affine_inverse() * vi.global_transform) * vi.get_aabb() if is_inside_tree() \
			else (n.transform * vi.transform) * vi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.8, 0, -1.8), Vector3(1.6, 1.4, 3.6))


## HUMAN_Drive: zum Punkt fahren (km/h). Kinematisch, damit die Skriptfahrt verl?sslich ist.
func drive_to(goal: Vector3, kmh: float) -> void:
	if fuel <= 0.0 or wrecked:
		return
	script_driving = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_drive_goal = goal
	_drive_speed = maxf(kmh, 5.0) / 3.6


func drive_done() -> bool:
	return not script_driving or not _drive_goal.is_finite() or wrecked


func stop_drive() -> void:
	_drive_goal = Vector3.INF
	_drive_speed = 0.0


func _script_drive(delta: float) -> void:
	if not _drive_goal.is_finite() or driver() == null:
		return
	var to := _drive_goal - global_position
	to.y = 0.0
	if to.length() < 2.0:
		_drive_goal = Vector3.INF
		return
	var yaw := atan2(to.x, to.z)
	global_rotation.y = lerp_angle(global_rotation.y, yaw, clampf(delta * 1.5, 0.0, 1.0))
	var fwd := global_basis.z
	fwd.y = 0.0
	var step := fwd.normalized() * minf(_drive_speed * delta, to.length())
	var space := get_world_3d().direct_space_state
	# Hindernis voraus (Geb?ude, Soldaten): anhalten statt durchfahren
	var ahead := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0,
		global_position + Vector3.UP * 1.0 + fwd.normalized() * (_size.z * 0.5 + 1.0), 1 | (1 << 1), [get_rid()])
	if not space.intersect_ray(ahead).is_empty():
		return
	var np := global_position + step
	var down := PhysicsRayQueryParameters3D.create(np + Vector3.UP * 3.0, np + Vector3.DOWN * 6.0, 1, [get_rid()])
	var hit := space.intersect_ray(down)
	if not hit.is_empty():
		np.y = hit.position.y
	global_position = np
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.5
		Events.emit_noise(global_position, 60.0, driver(), driver().team, &"engine")


func _physics_process(delta: float) -> void:
	if wrecked:
		engine_force = 0.0
		brake = max_brake
		return
	if script_driving:
		_script_drive(delta)
		return
	var d := driver()
	if d == null or not d.alive:
		engine_force = 0.0
		brake = max_brake * 0.5
		steering = 0.0
		return
	if not d.is_player_controlled:
		throttle = 0.0
		steer_input = 0.0
	elif freeze:
		freeze = false          # Spieler übernimmt ein bisher geparktes/skriptgefahrenes Fahrzeug
	if fuel <= 0.0:
		throttle = 0.0
	var speed := linear_velocity.dot(global_basis.z)   # vorne = +Z
	if throttle < 0.0 and speed > 1.0:
		engine_force = 0.0
		brake = max_brake * -throttle   # rückwärts drücken = bremsen
	else:
		engine_force = max_engine_force * throttle * (1.0 if absf(speed) < 22.0 else 0.0)
		brake = max_brake if handbrake else 0.0
	steering = move_toward(steering, steer_input * max_steer, delta * 2.0)
	# Motorgeräusch für das Gehör der Gegner
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.5
		Events.emit_noise(global_position, 45.0 + absf(throttle) * 35.0, d, d.team, &"engine")
		Effects.play(&"step", global_position, -8.0, 0.35, 60.0)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


# --- Schaden -----------------------------------------------------------------

func on_bullet_hit(damage: float, shooter: Node) -> void:
	if wrecked:
		return
	health -= damage
	if health <= 0.0:
		explode(shooter)


func explode(by: Node = null) -> void:
	if wrecked:
		return
	wrecked = true
	health = 0.0
	Effects.explosion(global_position + Vector3.UP, 6.0)
	Events.emit_noise(global_position, 300.0, by, 1, &"explosion")
	for o in occupants.duplicate():
		if is_instance_valid(o):
			leave(o)
			o.apply_hit(120.0, &"torso", by, Vector3.UP)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.07, 0.06)
		(mi as MeshInstance3D).material_override = m
	destroyed_vehicle.emit()


func serialize() -> Dictionary:
	var p := global_position
	return {"pos": [p.x, p.y, p.z], "yaw": global_rotation.y, "health": health, "wrecked": wrecked}


func deserialize(d: Dictionary) -> void:
	var p: Array = d["pos"]
	global_position = Vector3(p[0], p[1] + 0.2, p[2])
	global_rotation = Vector3(0, d.get("yaw", 0.0), 0)
	linear_velocity = Vector3.ZERO
	health = d.get("health", max_health)
	if d.get("wrecked", false):
		wrecked = false
		explode()


## Einstiegspunkt (Taste "Benutzen").
class VehicleEntry extends Interactable:
	var vehicle: Vehicle

	func _ready() -> void:
		super._ready()
		prompt = "Einsteigen (Fahrer)"

	func can_interact(s: Soldier) -> bool:
		return vehicle and not vehicle.wrecked and s.vehicle == null

	func interact(s: Soldier) -> void:
		if not can_interact(s):
			return
		if vehicle.board(s, true):
			Events.say("%s fährt den %s." % [s.soldier_name, vehicle.vehicle_name], 2.0)
		super.interact(s)
