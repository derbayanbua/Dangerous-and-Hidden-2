class_name SoldierModel
extends Node3D
## PLATZHALTER-MODELL: prozedural aus Primitiven aufgebaute Gliederpuppe
## mit Uniformfarben, Helm und Waffe. Prozedurale Animation für Gehen,
## Hocken, Liegen, Zielen, Lehnen und Tod. Trefferzonen (Hitbox) hängen an
## den Körperteilen und folgen dadurch Haltung und Animation.
## Ersetzbar durch ein geriggtes Modell mit identischer Schnittstelle
## (set_pose / update_anim / play_death / weapon_socket).

var uniform_color := Color(0.42, 0.38, 0.26)
var helmet_style := "brodie"   ## brodie / stahlhelm / cap
var skin_color := Color(0.85, 0.68, 0.55)

var root_pivot: Node3D   ## ganze Figur (für Liegen/Tod)
var pelvis: Node3D
var torso: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var weapon_socket: Node3D
var _weapon_mesh: Node3D

var _phase := 0.0
var _stance_blend := Vector3(1, 0, 0)   ## Gewichte stand/crouch/prone
var _dead := false
var _lean := 0.0


func build(soldier: Node, color: Color, helmet: String) -> void:
	uniform_color = color
	helmet_style = helmet
	var cloth := _mat(uniform_color)
	var dark := _mat(uniform_color.darkened(0.35))
	var boots := _mat(Color(0.12, 0.09, 0.07))
	var skin := _mat(skin_color)
	var webbing := _mat(uniform_color.lightened(0.25))

	root_pivot = Node3D.new()
	root_pivot.name = "Root"
	add_child(root_pivot)
	pelvis = _node("Pelvis", root_pivot, Vector3(0, 0.95, 0))
	_box(pelvis, Vector3(0.34, 0.2, 0.22), Vector3(0, 0, 0), dark)

	torso = _node("Torso", pelvis, Vector3(0, 0.08, 0))
	_box(torso, Vector3(0.4, 0.52, 0.24), Vector3(0, 0.27, 0), cloth)
	_box(torso, Vector3(0.42, 0.06, 0.26), Vector3(0, 0.05, 0), webbing)        # Koppel
	_box(torso, Vector3(0.3, 0.2, 0.12), Vector3(0, 0.3, 0.17), webbing)        # Rucksack/Tornister
	torso.add_child(Hitbox.create(soldier, &"torso", 1.0, _box_shape(Vector3(0.42, 0.6, 0.28), Vector3(0, 0.27, 0))))

	head = _node("Head", torso, Vector3(0, 0.6, 0))
	_sphere(head, 0.12, Vector3(0, 0.11, 0), skin)
	_add_helmet(head)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.14
	var hhb := Hitbox.create(soldier, &"head", 4.0, head_shape)
	hhb.position = Vector3(0, 0.12, 0)
	head.add_child(hhb)

	arm_l = _node("ArmL", torso, Vector3(-0.25, 0.48, 0))
	arm_r = _node("ArmR", torso, Vector3(0.25, 0.48, 0))
	for arm in [arm_l, arm_r]:
		_box(arm, Vector3(0.11, 0.55, 0.11), Vector3(0, -0.25, 0), cloth)
		_box(arm, Vector3(0.09, 0.09, 0.09), Vector3(0, -0.55, 0), skin)
		arm.add_child(Hitbox.create(soldier, &"arm", 0.5, _box_shape(Vector3(0.13, 0.6, 0.13), Vector3(0, -0.27, 0))))

	leg_l = _node("LegL", pelvis, Vector3(-0.1, -0.05, 0))
	leg_r = _node("LegR", pelvis, Vector3(0.1, -0.05, 0))
	knee_l = _node("KneeL", leg_l, Vector3(0, -0.44, 0))
	knee_r = _node("KneeR", leg_r, Vector3(0, -0.44, 0))
	for leg in [leg_l, leg_r]:
		_box(leg, Vector3(0.15, 0.46, 0.16), Vector3(0, -0.22, 0), cloth)
		leg.add_child(Hitbox.create(soldier, &"leg", 0.6, _box_shape(Vector3(0.17, 0.46, 0.18), Vector3(0, -0.22, 0))))
	for knee in [knee_l, knee_r]:
		_box(knee, Vector3(0.13, 0.42, 0.14), Vector3(0, -0.2, 0), dark)
		_box(knee, Vector3(0.13, 0.1, 0.26), Vector3(0, -0.43, 0.05), boots)
		knee.add_child(Hitbox.create(soldier, &"leg", 0.6, _box_shape(Vector3(0.15, 0.46, 0.18), Vector3(0, -0.22, 0))))

	weapon_socket = _node("WeaponSocket", torso, Vector3(0.12, 0.38, -0.32))


func _add_helmet(h: Node3D) -> void:
	var m: Material
	match helmet_style:
		"stahlhelm":
			m = _mat(Color(0.3, 0.32, 0.3))
			var s := _sphere(h, 0.15, Vector3(0, 0.16, 0), m)
			s.scale = Vector3(1.0, 0.75, 1.05)
			var brim := _cyl(h, 0.17, 0.05, Vector3(0, 0.08, 0.01), m)
			brim.scale = Vector3(1.0, 1.0, 1.05)
		"cap":
			m = _mat(uniform_color.darkened(0.2))
			_cyl(h, 0.13, 0.08, Vector3(0, 0.23, 0), m)
			_box(h, Vector3(0.18, 0.02, 0.1), Vector3(0, 0.2, -0.13), _mat(Color(0.1, 0.1, 0.1)))
		_:
			m = _mat(Color(0.33, 0.33, 0.24))
			_cyl(h, 0.2, 0.025, Vector3(0, 0.18, 0), m)          # flache Krempe (Brodie)
			var dome := _sphere(h, 0.12, Vector3(0, 0.2, 0), m)
			dome.scale = Vector3(1.0, 0.55, 1.0)


func set_weapon(data: WeaponData) -> void:
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	if data == null or data.slot == WeaponData.Slot.GRENADE:
		return
	_weapon_mesh = build_weapon_mesh(data)
	weapon_socket.add_child(_weapon_mesh)
	_weapon_mesh.visible = _weapon_visible


var _weapon_visible := true

## In der 1. Person wird die Körperwaffe durch das Viewmodel ersetzt.
func set_weapon_visible(v: bool) -> void:
	_weapon_visible = v
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.visible = v


## PLATZHALTER-Waffenmodell (Schaft, Lauf, Magazin, Visier), Lauf zeigt nach -Z.
static func build_weapon_mesh(data: WeaponData) -> Node3D:
	var root := Node3D.new()
	var metal := _smat(Color(0.1, 0.1, 0.11), 0.5, 0.45)
	var wood := _smat(data.color, 0.0, 0.8)
	var L := data.model_length
	var parts := [
		[Vector3(0.05, 0.08, L * 0.55), Vector3(0, 0, -L * 0.1), wood],          # Schaft/Gehäuse
		[Vector3(0.025, 0.025, L * 0.5), Vector3(0, 0.03, -L * 0.5), metal],      # Lauf
		[Vector3(0.012, 0.03, 0.012), Vector3(0, 0.06, -L * 0.72), metal],        # Korn
		[Vector3(0.03, 0.02, 0.02), Vector3(0, 0.055, -L * 0.05), metal],         # Kimme
	]
	if data.magazine_size >= 20:
		parts.append([Vector3(0.03, 0.18, 0.04), Vector3(0, -0.1, -L * 0.25), metal])
	for p in parts:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		mi.mesh = b
		mi.position = p[1]
		mi.material_override = p[2]
		root.add_child(mi)
	return root


static func _smat(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var key := "w" + c.to_html() + str(metallic)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	_mat_cache[key] = m
	return m


# --- Animation ---------------------------------------------------------------

## stance: 0 stehen, 1 hocken, 2 liegen. speed in m/s, aim_pitch in Rad.
func update_anim(delta: float, stance: int, speed: float, aim_pitch: float, aiming: bool, lean: float) -> void:
	if _dead:
		return
	var target := Vector3(1, 0, 0)
	if stance == 1:
		target = Vector3(0, 1, 0)
	elif stance == 2:
		target = Vector3(0, 0, 1)
	_stance_blend = _stance_blend.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	var sb := _stance_blend
	_lean = lerpf(_lean, lean, clampf(delta * 8.0, 0.0, 1.0))

	var stride := 1.4 if stance != 2 else 0.6
	_phase = fmod(_phase + delta * speed / stride * TAU, TAU)
	var amp := clampf(speed / 3.0, 0.0, 1.0) * 0.7
	var swing := sin(_phase) * amp

	# Becken-Höhe und Ganzkörper-Neigung (Liegen)
	pelvis.position.y = 0.95 * sb.x + 0.55 * sb.y + 0.16 * sb.z
	pelvis.position.z = 0.0 * sb.x + 0.05 * sb.y + 0.45 * sb.z
	pelvis.rotation.x = -PI * 0.5 * sb.z
	pelvis.position.y += absf(cos(_phase)) * amp * 0.05 * sb.x
	# Oberkörper folgt teilweise der Zielrichtung
	var pitch_follow := aim_pitch * (0.45 * (sb.x + sb.y)) + aim_pitch * 0.2 * sb.z
	# Positive X-Rotation kippt +Y nach vorne-oben (siehe CLAUDE.md, Modellkonventionen)
	torso.rotation.x = pitch_follow - 0.2 * sb.y + 0.3 * sb.z
	torso.rotation.z = -_lean * 0.35
	head.rotation.x = aim_pitch * 0.5 + PI * 0.4 * sb.z
	# Beine: Hüfte positiv = Oberschenkel nach vorn, Knie negativ = Unterschenkel nach hinten
	var crouch_hip := 1.3
	var crouch_knee := -2.0
	leg_l.rotation.x = swing * (sb.x + sb.y * 0.5) + crouch_hip * sb.y + swing * 0.4 * sb.z
	leg_r.rotation.x = -swing * (sb.x + sb.y * 0.5) + crouch_hip * 0.25 * sb.y - swing * 0.4 * sb.z
	knee_l.rotation.x = -maxf(-swing, 0.0) * 1.2 * sb.x + crouch_knee * sb.y
	# Rechtes Knie im Kniestand am Boden: Unterschenkel liegt flach nach hinten
	knee_r.rotation.x = -maxf(swing, 0.0) * 1.2 * sb.x - 1.55 * sb.y
	# Arme halten die Waffe
	# positive X-Rotation hebt den (nach -Y hängenden) Arm nach vorn
	var hold := 1.35 if aiming else 1.0
	arm_r.rotation = Vector3(hold, 0.0, -0.1)
	arm_l.rotation = Vector3(hold + 0.15, 0.0, 0.55)
	weapon_socket.rotation.x = 0.0 if aiming else 0.25
	weapon_socket.position = Vector3(0.12 if aiming else 0.16, 0.38 if aiming else 0.3, -0.32)
	_update_orig(speed)


## Original-Figur (skinned glTF mit Animationen idle/walk/run/sprint/death) statt der
## Platzhalter-Gliederpuppe anzeigen. Die Puppe bleibt unsichtbar bestehen: ihre
## Trefferzonen und der Waffensockel folgen weiter der Haltung.
var orig_figure: Node3D
var _orig_anim: AnimationPlayer
var _orig_clip := ""


func attach_orig(figure: Node3D) -> void:
	if figure == null:
		return
	for mi in root_pivot.find_children("*", "MeshInstance3D", true, false):
		if not weapon_socket.is_ancestor_of(mi):
			(mi as MeshInstance3D).visible = false
	orig_figure = figure
	add_child(figure)
	_orig_anim = figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _orig_anim:
		for clip in ["idle", "walk", "run", "sprint", "crouch", "prone"]:
			if _orig_anim.has_animation(clip):
				_orig_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play_orig("idle", 1.0)


func _play_orig(clip: String, speed: float) -> void:
	if _orig_anim == null or not _orig_anim.has_animation(clip):
		return
	_orig_anim.speed_scale = speed
	if _orig_clip != clip:
		_orig_clip = clip
		_orig_anim.play(clip, 0.2)


func _update_orig(speed: float) -> void:
	if orig_figure == null:
		return
	# Hocken/Liegen: Original-Haltungsclips (!drepZB / !leziN); Fortbewegung darin ohne eigenen Clip
	if _stance_blend.z > 0.5 and _orig_anim and _orig_anim.has_animation("prone"):
		_play_orig("prone", 1.0)
	elif _stance_blend.y > 0.5 and _orig_anim and _orig_anim.has_animation("crouch"):
		_play_orig("crouch", 1.0)
	elif speed > 4.6:
		_play_orig("sprint", speed / 6.0)
	elif speed > 2.4:
		_play_orig("run", speed / 4.5)
	elif speed > 0.2:
		_play_orig("walk", maxf(speed / 1.6, 0.4))
	else:
		_play_orig("idle", 1.0)


func play_death(direction: Vector3) -> void:
	if _dead:
		return
	if orig_figure:
		_play_orig("death", 1.0)
	_dead = true
	var fall_dir := direction
	fall_dir.y = 0
	if fall_dir.length() < 0.1:
		fall_dir = -global_basis.z
	var local := global_basis.inverse() * fall_dir.normalized()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var side := 1.0 if local.z > 0.0 else -1.0   # nach hinten (+z) oder vorne fallen
	tw.tween_property(root_pivot, "rotation:x", PI * 0.5 * side, 0.55)
	tw.tween_property(root_pivot, "position:y", 0.12, 0.55)
	tw.tween_property(pelvis, "position:y", 0.0, 0.4)
	tw.tween_property(pelvis, "rotation:x", 0.0, 0.4)
	tw.tween_property(leg_l, "rotation:x", 0.15, 0.4)
	tw.tween_property(leg_r, "rotation:x", -0.2, 0.4)
	tw.tween_property(knee_l, "rotation:x", 0.2, 0.4)
	tw.tween_property(knee_r, "rotation:x", 0.1, 0.4)
	tw.tween_property(torso, "rotation:x", 0.0, 0.4)
	tw.tween_property(arm_l, "rotation", Vector3(-2.6, 0, -0.6), 0.5)
	tw.tween_property(arm_r, "rotation", Vector3(-0.4, 0, 0.8), 0.5)


func set_dead_instant() -> void:
	if orig_figure and _orig_anim and _orig_anim.has_animation("death"):
		_play_orig("death", 1.0)
		_orig_anim.seek(_orig_anim.get_animation("death").length, true)
	_dead = true
	root_pivot.rotation.x = PI * 0.5
	root_pivot.position.y = 0.12
	pelvis.position.y = 0.0
	pelvis.rotation.x = 0.0
	torso.rotation.x = 0.0


# --- Hilfen ------------------------------------------------------------------

static var _mat_cache := {}

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mat_cache[key] = m
	return m


func _node(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	return node


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box_shape(size: Vector3, offset: Vector3) -> Shape3D:
	# Offset wird über ein Zwischen-Shape nicht unterstützt; daher verschieben
	# wir die Hitbox-Form über ein ConvexPolygonShape mit versetzten Punkten.
	var pts := PackedVector3Array()
	var h := size * 0.5
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				pts.append(offset + Vector3(h.x * sx, h.y * sy, h.z * sz))
	var cs := ConvexPolygonShape3D.new()
	cs.points = pts
	return cs
