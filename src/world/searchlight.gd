class_name Searchlight
extends Node3D
## Schwenkender Suchscheinwerfer. Ziele im Lichtkegel (mit Sichtlinie) gelten
## als hell beleuchtet (Mission.light_at). Bei Alarm richtet er sich auf den
## Alarmort. Ein Treffer zerstört ihn (Geräusch, Licht aus).

@export var sweep_center := 0.0      ## Grund-Yaw (Rad)
@export var sweep_width := 1.0       ## Halbwinkel des Schwenks (Rad)
@export var sweep_speed := 0.35
@export var pitch := -0.18
@export var reach := 70.0
@export var cone_deg := 9.0
@export var persistent_id := ""

var destroyed := false
var _t := 0.0
var _light: SpotLight3D
var _head: Node3D
var _focus := Vector3.INF


func _ready() -> void:
	add_to_group("searchlights")
	add_to_group("persistent")
	_head = Node3D.new()
	add_child(_head)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.6, 0.8)
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.25
	cm.height = 0.7
	mi.mesh = cm
	mi.rotation.x = PI * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.2)
	m.metallic = 0.5
	mi.material_override = m
	body.add_child(mi)
	_head.add_child(body)
	_light = SpotLight3D.new()
	_light.light_color = Color(1.0, 0.97, 0.88)
	_light.light_energy = 14.0
	_light.spot_range = reach
	_light.spot_angle = cone_deg
	_light.spot_attenuation = 0.4
	_light.shadow_enabled = true
	_light.position = Vector3(0, 0, -0.45)
	_head.add_child(_light)
	Events.alarm_raised.connect(_on_alarm)


func _on_alarm(pos: Vector3, _by: Node) -> void:
	_focus = pos


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_t += delta
	if _focus.is_finite():
		var to := _focus - global_position
		var yaw := atan2(-to.x, -to.z)
		_head.global_rotation.y = rotate_toward(_head.global_rotation.y, yaw, delta * 0.8)
		_head.rotation.x = move_toward(_head.rotation.x, atan2(to.y, Vector2(to.x, to.z).length()), delta)
	else:
		_head.rotation.y = sweep_center + sin(_t * sweep_speed) * sweep_width - rotation.y
		_head.rotation.x = pitch


func illuminates(pos: Vector3) -> bool:
	if destroyed:
		return false
	var origin := _light.global_position
	var to := pos - origin
	var d := to.length()
	if d > reach or d < 0.5:
		return false
	var dir := -_light.global_basis.z
	if dir.angle_to(to) > deg_to_rad(cone_deg):
		return false
	var q := PhysicsRayQueryParameters3D.create(origin, pos, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.position.distance_to(pos) < 0.6


func on_bullet_hit(_damage: float, shooter: Node) -> void:
	if destroyed:
		return
	destroyed = true
	_light.visible = false
	Effects.impact(_light.global_position, Vector3.UP)
	Effects.play(&"click", global_position, 6.0, 0.5, 80.0)
	var team := (shooter as Soldier).team if shooter is Soldier else 0
	Events.emit_noise(global_position, 30.0, shooter, team, &"impact")
	Events.say("Suchscheinwerfer ausgeschaltet.", 2.5)


func serialize() -> Dictionary:
	return {"destroyed": destroyed}


func deserialize(d: Dictionary) -> void:
	if d.get("destroyed", false):
		destroyed = true
		_light.visible = false
