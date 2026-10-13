class_name CameraRig
extends Node3D
## Kamera für den aktiven Soldaten. Original belegt zwei Modi
## (Strings "cameraFPV" / "camera3RD" in hd2.exe):
##  - 3. Person: Schulterkamera mit Kollisionsschutz (SpringArm3D)
##  - 1. Person: Augenposition, eigener Kopf ausgeblendet
## Zielen (RMT) verengt das Sichtfeld auf WeaponData.aim_fov.

enum Mode { THIRD, FIRST }

var mode: int = Mode.THIRD
var target: Soldier
var camera: Camera3D
var _arm: SpringArm3D
var _pivot: Node3D
var _fov := 70.0
var _shoulder := 0.5
var _arm_len := 2.6
var _lift := 0.12


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.15
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	_arm.shape = sph
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 1200.0
	_arm.add_child(camera)
	camera.current = true
	_fov = Settings.fov
	camera.fov = _fov
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	camera.add_child(_viewmodel)


func set_target(s: Soldier) -> void:
	if is_instance_valid(target):
		if target.model:
			target.model.head.visible = true
			target.model.set_weapon_visible(true)
		if target.weapon_changed.is_connected(_on_weapon_changed):
			target.weapon_changed.disconnect(_on_weapon_changed)
			target.shot_fired.disconnect(_on_shot)
	target = s
	if is_instance_valid(target):
		_arm.clear_excluded_objects()
		_arm.add_excluded_object(target.get_rid())
		target.weapon_changed.connect(_on_weapon_changed)
		target.shot_fired.connect(_on_shot)
		_on_weapon_changed(target.current_weapon())
		_apply_head_visibility()


func toggle_mode() -> void:
	mode = Mode.FIRST if mode == Mode.THIRD else Mode.THIRD
	_apply_head_visibility()


var _binoc_last := false
var _model_last: Node3D


func _apply_head_visibility() -> void:
	var valid := is_instance_valid(target) and target.alive
	var binoc := valid and target.using_binoculars
	var fpv := (mode == Mode.FIRST or binoc) and valid
	if is_instance_valid(target) and target.model:
		target.model.head.visible = not fpv
		target.model.set_weapon_visible(not fpv)
	_viewmodel.visible = fpv and not binoc


# --- Viewmodel (1. Person) ----------------------------------------------------

var _viewmodel: Node3D
var _vm_weapon: Node3D
var _vm_kick := 0.0
var _vm_bob := 0.0
const VM_HIP := Vector3(0.17, -0.2, -0.42)
const VM_AIM := Vector3(0.0, -0.085, -0.3)   ## Kimme/Korn auf der Blickachse


func _on_weapon_changed(w: Weapon) -> void:
	if is_instance_valid(_vm_weapon):
		_vm_weapon.queue_free()
	_vm_weapon = null
	if w == null or w.data.slot == WeaponData.Slot.GRENADE:
		return
	_vm_weapon = SoldierModel.build_weapon_mesh(w.data)
	# Hände (PLATZHALTER)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.8, 0.63, 0.5)
	for p in [Vector3(0.0, -0.06, 0.02), Vector3(0.0, -0.05, -w.data.model_length * 0.38)]:
		var h := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 0.1)
		h.mesh = b
		h.material_override = skin
		h.position = p
		_vm_weapon.add_child(h)
	for mi in _vm_weapon.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewmodel.add_child(_vm_weapon)


func _on_shot(_w: Weapon) -> void:
	_vm_kick = 1.0


func _update_viewmodel(delta: float) -> void:
	if _viewmodel.visible and not target.alive:
		_apply_head_visibility()
	if not _viewmodel.visible or not is_instance_valid(_vm_weapon):
		return
	var w := target.current_weapon()
	var aim := target.aiming and w != null and not w.is_reloading()
	var base := VM_AIM if aim else VM_HIP
	_vm_bob += delta * target.current_speed() * 3.2
	var bob := Vector3(sin(_vm_bob) * 0.012, absf(cos(_vm_bob)) * 0.01, 0.0) * (0.3 if aim else 1.0)
	var reload_drop := Vector3(0, -0.12, 0.05) if w and w.is_reloading() else Vector3.ZERO
	var kick := Vector3(0, 0.01, 0.06) * _vm_kick
	var want := base + bob + reload_drop + kick
	_vm_weapon.position = _vm_weapon.position.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
	_vm_weapon.rotation.x = _vm_kick * 0.08 + (0.5 if w and w.is_reloading() else 0.0) * 0.6
	_vm_kick = maxf(_vm_kick - delta * 9.0, 0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var w := target.current_weapon()
	var want_fov := Settings.fov
	if target.aiming and w:
		want_fov = w.data.aim_fov * (0.85 if mode == Mode.FIRST else 1.0)
	var binoc := target.using_binoculars
	if binoc:
		want_fov = 12.0   # 6x-Fernglas (Original: ii_binoc)
	if binoc != _binoc_last or target.model != _model_last:
		_binoc_last = binoc
		_model_last = target.model   # Modell kann sich ändern (Uniformwechsel)
		_apply_head_visibility()
	_fov = lerpf(_fov, want_fov, clampf(delta * 10.0, 0.0, 1.0))
	camera.fov = _fov

	var eye := target.eye_position()
	var yaw := target.look_yaw
	var pitch := target.look_pitch
	if mode == Mode.FIRST or target.using_binoculars:
		_pivot.global_position = eye
		_pivot.global_rotation = Vector3(pitch, yaw, -target.lean * 0.12)
		_arm.spring_length = 0.0
		_arm.position = Vector3.ZERO
		_update_viewmodel(delta)
	else:
		var aim := target.aiming
		var want_shoulder := 0.42 if aim else 0.55
		var want_len := 1.3 if aim else 2.7
		var lift := 0.12
		if target.vehicle != null:
			_arm.add_excluded_object(target.vehicle.get_rid())
			want_len = 6.5        # Verfolgerkamera hinter dem Fahrzeug
			want_shoulder = 0.0
			lift = 1.4
		elif target.stance == Soldier.Stance.PRONE:
			want_len = 2.4 if aim else 3.4
			lift = 0.95   # liegend: Kamera höher/weiter, sonst verdecken die Beine das Bild
		_shoulder = lerpf(_shoulder, want_shoulder + target.lean * 0.3, clampf(delta * 8.0, 0.0, 1.0))
		_arm_len = lerpf(_arm_len, want_len, clampf(delta * 8.0, 0.0, 1.0))
		_lift = lerpf(_lift, lift, clampf(delta * 6.0, 0.0, 1.0))
		_pivot.global_position = eye + Vector3.UP * _lift
		_pivot.global_rotation = Vector3(pitch, yaw, 0.0)
		_arm.position = Vector3(_shoulder, 0.0, 0.0)
		_arm.spring_length = _arm_len


## Weltpunkt unter dem Fadenkreuz (Bildschirmmitte).
func crosshair_point(max_dist := 800.0) -> Vector3:
	var dir := -camera.global_basis.z
	var from := camera.global_position
	# In 3. Person erst ab Höhe des Soldaten prüfen (nichts zwischen Kamera und Figur treffen)
	if is_instance_valid(target) and mode == Mode.THIRD:
		from += dir * maxf((target.eye_position() - from).dot(dir), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, 1 | Hitbox.LAYER)
	q.collide_with_areas = true
	if is_instance_valid(target):
		q.exclude = target.exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from + dir * max_dist
	return hit.position
