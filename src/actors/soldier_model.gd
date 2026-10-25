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
	_soldier = soldier
	# Original-Feuerclips (anim.sav +0x3A0 „puf*“) und Rückstoß bei jedem Schuss
	if soldier and soldier.has_signal("shot_fired") and not soldier.is_connected("shot_fired", _on_shot_fired):
		soldier.connect("shot_fired", _on_shot_fired)
	# Original-Trefferclips je Zone (BodyAnim.on_hit)
	if soldier and soldier.has_signal("damaged") and not soldier.is_connected("damaged", _on_damaged):
		soldier.connect("damaged", _on_damaged)
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


## Waffe in der Hand. Mit Original-Figur: Original-Weltmodell (OrigWeapons) am Hand-Dummy hw1 wie im
## Original (Lauf entlang +X von hw1, Griff RW auf hw1), folgt damit Animation und Haltung; ohne Modell im
## Cache derselbe Ort mit dem Platzhalter. Ohne Original-Figur: Platzhalter am WeaponSocket der Puppe.
func set_weapon(data: WeaponData) -> void:
	_weapon_data = data
	call_deferred("refresh_back_weapon")     # B-018: Rückenwaffe folgt dem Waffenwechsel
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	_muzzle = null
	_lw = null
	_fire_left = 0.0
	if data == null:
		return
	if is_instance_valid(_soldier) and _soldier.get("mounted") != null:
		return       # an der Waffenstellung: die Waffe ist das Stellungsmodell (OrigEmplacement), nichts in der Hand
	if orig_figure and is_instance_valid(_hand):
		# Original: auch die Granate liegt in der Hand (Haltesatz "hand", !drzgran1)
		_weapon_mesh = OrigWeapons.instance(data, _team())
		if _weapon_mesh == null:
			if data.slot == WeaponData.Slot.GRENADE:
				return
			_weapon_mesh = build_weapon_mesh(data, false)
		_weapon_mesh.transform = OrigWeapons.hand_transform()
		_hand.add_child(_weapon_mesh)
		if _weapon_mesh.has_meta("muzzle"):
			_muzzle = _weapon_mesh.get_meta("muzzle")
		_lw = _weapon_mesh.find_child("LW", true, false) as Node3D
		_roll = 0.0
	else:
		if data.slot == WeaponData.Slot.GRENADE:
			return
		_weapon_mesh = build_weapon_mesh(data, false)
		weapon_socket.add_child(_weapon_mesh)
	_weapon_mesh.visible = _weapon_visible and not is_instance_valid(_prop)


var _weapon_visible := true

## In der 1. Person wird die Körperwaffe durch das Viewmodel ersetzt.
func set_weapon_visible(v: bool) -> void:
	_weapon_visible = v
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.visible = v and not is_instance_valid(_prop)
	if is_instance_valid(_prop):
		_prop.visible = v


## Mündung der gehaltenen Waffe (Original: Dummy flash/blsdum), sonst Schätzung über den Sockel.
func muzzle_point(dir: Vector3, length: float) -> Vector3:
	if is_instance_valid(_muzzle) and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return weapon_socket.global_position + dir * length * 0.8


func _team() -> int:
	if is_instance_valid(_soldier) and "team" in _soldier:
		return int(_soldier.get("team"))
	return -1


## Waffenmodell, Lauf nach -Z, Griff im Ursprung: Original-Weltmodell aus dem Cache (prefer_orig), sonst
## PLATZHALTER (Schaft, Lauf, Magazin, Visier).
static func build_weapon_mesh(data: WeaponData, prefer_orig := true, team := -1) -> Node3D:
	if prefer_orig:
		var o := OrigWeapons.instance(data, team)
		if o:
			return o
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
	_anim_stance = stance
	_update_orig(speed)
	_update_hold(delta, speed, aim_pitch, aiming)


## Original-Figur (skinned glTF mit Animationen idle/walk/run/sprint/death) statt der
## Platzhalter-Gliederpuppe anzeigen. Die Puppe bleibt unsichtbar bestehen: ihre
## Trefferzonen und der Waffensockel folgen weiter der Haltung.
var orig_figure: Node3D
var _orig_anim: AnimationPlayer
var _orig_clip := ""
var _soldier: Node
var _weapon_data: WeaponData
var _muzzle: Node3D
var _hand: Node3D                  ## Dummy hw1 der Original-Figur (Waffe der rechten Hand)
var _hold_anim: AnimationPlayer    ## Oberkörper-Schicht: Waffenhaltung (Clips h_*, TABLES\anim.sav)
var _hold_clip := ""
var _aim_mod: WeaponAimModifier
var _aim_w := 0.0
var _fig_yaw := 0.0
const LeftHandIK := preload("res://src/actors/left_hand_ik.gd")
var _ik: SkeletonModifier3D        ## LeftHandIK: linke Hand an LW der Waffe
var _ik_w := 0.0
var _lw: Node3D                    ## Waffen-Dummy LW (Griff der linken Hand)
## Raketenwerfer im Anschlag: Drehung um die Rohrachse (rad). Die Original-Anschlaghaltungen !bazPOHst/!bazPOHdr
## legen die Y-Achse von hw1 nach unten; mit SetDir((1,0,0), 0) läge das Rohr dann unter der Hand vor der Brust.
## Vorgabe Auftraggeber: Rohr auf der Schulter -> im Anschlag um 180° gedreht (Griff unten, Rohr über der Hand).
var _roll := 0.0
## Feuerclip (anim.sav +0x3A0 „puf*“) läuft noch so lange (s); währenddessen Anschlag auch ohne Zielen
var _fire_left := 0.0
var _fire_clip := ""
var recoil := 0.0                  ## Rückstoß 0..1 (klingt ab), hebt den Lauf über WeaponAimModifier.kick


func attach_orig(figure: Node3D) -> void:
	if figure == null:
		return
	if is_instance_valid(orig_figure):
		_detach_orig()      # Figurwechsel (Uniform): alte Figur samt Hand-Dummy, Waffe, Schichten vollständig lösen
	for mi in root_pivot.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	orig_figure = figure
	if not figure.has_meta("figure_model"):
		figure.set_meta("figure_model", String(figure.name).to_lower())   # vor add_child (Name kann umbenannt werden)
	add_child(figure)
	_orig_anim = figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _orig_anim:
		for clip in ["idle", "walk", "run", "sprint", "crouch", "prone", "medic", "medic_self"]:
			if _orig_anim.has_animation(clip):
				_orig_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play_orig("idle", 1.0)
		_read_camera_points()
		body = BodyAnim.new()       # Ganzkörperclips aus anim.sav (Bewegung, Haltungswechsel, Treffer, Tode …)
		body.setup(_orig_anim)
	_hand = figure.find_child("hw1", true, false) as Node3D
	_setup_hold(figure)
	_build_orig_hitboxes(figure)
	refresh_helmet()
	set_weapon(_weapon_data)   # Waffe vom Platzhaltersockel an die Hand der Figur umhängen
	var sks := figure.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty() and _orig_anim:
		ragdoll = Ragdoll.attach(self, _soldier as Node3D, sks[0] as Skeleton3D, _orig_anim)   # B-016, Körper erst beim Tod


## --- Trefferzonen der Original-Figur (docs/re_notes_weapons.md §10a) ---------------------------------------
## Original: 10 Kisten aus MODELS\humanzones.4ds, je an das gleichnamige Gelenk gebunden (hd2.exe 0x455670 übernimmt
## die Weltmatrix des Gelenks): c Körper, f Kopf, h/i/l/m Arme, s/t/o/p Beine (orig_cache/humanzones.json,
## tools/fmt_humanzones.py). Sie folgen damit jeder Animation (Haltungen, Zielen, Stellung, Fahrzeug, Tod) und den
## IK-Anpassungen. Die Zonen der Platzhalterpuppe werden dann abgeschaltet (sonst Treffer „in der Luft“).
static var _zone_table: Array = []
var orig_zones: Array[Hitbox] = []


static func orig_zone_table() -> Array:
	if _zone_table.is_empty():
		var f := FileAccess.open(OrigLevel.cache_root() + "/humanzones.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if typeof(j) == TYPE_DICTIONARY:
				_zone_table = j.get("zones", [])
	return _zone_table


func _build_orig_hitboxes(figure: Node3D) -> void:
	orig_zones.clear()
	var sks := figure.find_children("*", "Skeleton3D", true, false)
	var table := orig_zone_table()
	if sks.is_empty() or table.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	for z in table:
		var bone := String(z["bone"])
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		var ba := BoneAttachment3D.new()
		ba.name = "Zone_" + bone
		sk.add_child(ba)
		ba.bone_name = bone
		var mn := Vector3(z["min"][0], z["min"][1], z["min"][2])
		var mx := Vector3(z["max"][0], z["max"][1], z["max"][2])
		var box := BoxShape3D.new()
		box.size = mx - mn
		var hb := Hitbox.create(_soldier, StringName(z["zone"]), 1.0, box)
		hb.name = "Hitbox_%s_%s" % [z["zone"], bone]
		hb.set_meta("bone", bone)
		(hb.get_child(0) as Node3D).position = (mn + mx) * 0.5
		ba.add_child(hb)
		orig_zones.append(hb)
	_set_puppet_hitboxes(orig_zones.size() < table.size())


## --- Kopfgegenstand (B-014, Helmet) ------------------------------------------------------------------------
## Helmmodell aus items.sav (Kopf-Platz) am Kopfgelenk „f“ der Original-Figur, dazu eine eigene Trefferfläche
## (Zone „helmet“, Kiste des Helmmodells) – der Strahltest des Originals prüft das Helmmodell vor den Gelenkzonen.
var helmet_item := -1
var _helmet_mount: BoneAttachment3D
var _helmet_vis: Node3D
var _helmet_box: Hitbox


func refresh_helmet() -> void:
	if not is_instance_valid(orig_figure) or _soldier == null:
		return
	Helmet.ensure_default(_soldier)
	var want := Helmet.head_item(_soldier)
	if want == helmet_item and (want < 0 or is_instance_valid(_helmet_vis)):
		return
	if is_instance_valid(_helmet_vis):
		_helmet_vis.queue_free()
	if is_instance_valid(_helmet_box):
		_helmet_box.get_parent().remove_child(_helmet_box)
		_helmet_box.queue_free()
	_helmet_vis = null
	_helmet_box = null
	helmet_item = want
	if want < 0:
		return
	var sks := orig_figure.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var bi := sk.find_bone(Helmet.HEAD_BONE)
	if bi < 0:
		return
	var vis := Helmet.model_of(want)
	if vis == null:
		return
	if not is_instance_valid(_helmet_mount):
		_helmet_mount = BoneAttachment3D.new()
		_helmet_mount.name = "HelmetMount"
		sk.add_child(_helmet_mount)
		_helmet_mount.bone_name = Helmet.HEAD_BONE
	# B-018 [B]: hd2.exe 0x7D1B60 Fall 1 (Kopf-Platz) hängt das Modell an das Kopfgelenk (+0x7C), SetDir(0,0,1) =
	# keine Drehung gegenüber dem Gelenk, SetPos = fester Vektor 0x98AFB0 (Helmet.MOUNT_POS). Die Wurzel des Helmmodells
	# (Knoten mit der Figurraum-Lage 1,73 m) sitzt damit genau dort; vorher Figurraum − Ruhelage (≈ 2,7 cm zu weit
	# hinten, Seitenversatz aus dem Modell statt 1,67 cm).
	vis.name = "Helmet"
	_helmet_mount.add_child(vis)
	vis.transform = Helmet.mount_transform(vis)
	_helmet_vis = vis
	var bb := Helmet.bounds(vis)
	if bb.size.length() > 0.01:
		# Original: Strahltest gegen das Helmmodell (Schale + Rand). Kiste = obere Teil der Hüllkiste ab
		# Helm.BOX_FROM der Höhe, damit Schüsse ins Gesicht unter dem Rand die Kopfzone treffen [P]
		var cut := bb.size.y * Helmet.BOX_FROM
		var hbb := AABB(bb.position + Vector3(0, cut, 0), bb.size - Vector3(0, cut, 0))
		var box := BoxShape3D.new()
		box.size = hbb.size
		var hb := Hitbox.create(_soldier, Helmet.ZONE, 1.0, box)
		hb.name = "Hitbox_helmet"
		hb.set_meta("bone", Helmet.HEAD_BONE)
		(hb.get_child(0) as Node3D).position = hbb.get_center()
		vis.add_child(hb)
		_helmet_box = hb


## Weltlage des Helms (Abflug), sonst Kopfhöhe
func helmet_transform() -> Transform3D:
	if is_instance_valid(_helmet_vis):
		var bb := Helmet.bounds(_helmet_vis)
		return _helmet_vis.global_transform.translated_local(bb.get_center())
	return global_transform.translated_local(Vector3(0, 1.75, 0))


## Hat die Figur eine eigene Helm-Trefferfläche? (sonst Näherung obere Kopfhälfte in Ballistics)
func has_helmet_box() -> bool:
	return is_instance_valid(_helmet_box)


## --- Waffe auf dem Rücken (B-018) --------------------------------------------------------------------------------
## Original [B] hd2.exe 0x7D1B60 Fall 0x10: Waffenmodell der Rücken-/Schulterwaffe an das Brustgelenk (+0x78 = „d“,
## Figur-Dummy „Dummy25“ liegt genau auf DAT_0098AFC0), SetDir(0,1,0) (Lauf nach oben), SetPos(0x98AFC0); danach
## Lage = SetPos + Drehung·(−„backlink“ des Waffenmodells) + (0,0275; 0; 0,09). Die anschließende Zusatzdrehung für
## Waffenart ≠ 4 (Schrägstellung, −0,01/−0,08) ist nicht vollständig dekodiert und fehlt [P]. Waffen ohne „backlink“
## (Pistolen, Messer …) werden wie im Original nicht auf dem Rücken gezeigt. LS3D → Nachbau: z gespiegelt.
const BACK_POS := Vector3(0.175592, 0.180547, 0.133315)
const BACK_ADD := Vector3(0.0275, 0.0, -0.09)
var _back_mount: BoneAttachment3D
var _back_vis: Node3D
var _back_key := ""


func refresh_back_weapon() -> void:
	if not is_instance_valid(orig_figure) or _soldier == null or not (_soldier is Soldier):
		return
	var s := _soldier as Soldier
	var w: Weapon = OrigHud.shoulder_weapon(s)
	var model := String(OrigWeapons.info(w.data, _team()).get("model", "")) if w else ""
	if model == _back_key and (model == "" or is_instance_valid(_back_vis)):
		return
	if is_instance_valid(_back_vis):
		_back_vis.queue_free()
	_back_vis = null
	_back_key = model
	if model == "":
		return
	var n := OrigWeapons.world_model(model)
	if n == null:
		return
	var bl := n.find_child("backlink", true, false) as Node3D
	if bl == null:
		n.free()
		return
	var sks := orig_figure.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty() or (sks[0] as Skeleton3D).find_bone("d") < 0:
		n.free()
		return
	if not is_instance_valid(_back_mount):
		_back_mount = BoneAttachment3D.new()
		_back_mount.name = "BackMount"
		sks[0].add_child(_back_mount)
		_back_mount.bone_name = "d"
	n.name = "BackWeapon"
	var rot := Basis(Vector3.RIGHT, PI * 0.5)        # Dummy25: +90° um X → Lauf (−Z) zeigt nach oben
	var link := OrigWeapons._rel(n, bl).origin
	n.transform = Transform3D(rot, BACK_POS + rot * (-link) + BACK_ADD)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_back_mount.add_child(n)
	_back_vis = n


## RID der eigenen Helmfläche (Ausschluss im Strahltest des Schützen, B-018)
func helmet_rid() -> RID:
	return _helmet_box.get_rid() if is_instance_valid(_helmet_box) else RID()


func _set_puppet_hitboxes(on: bool) -> void:
	for h in root_pivot.find_children("*", "Hitbox", true, false):
		(h as Hitbox).collision_layer = Hitbox.LAYER if on else 0


## Trefferzonen sichtbar machen (Prüfbilder): halbtransparente Kisten je Zone
const ZONE_COLORS := {&"torso": Color(1, 0.8, 0, 0.35), &"head": Color(1, 0, 0, 0.45), &"arm": Color(0, 0.6, 1, 0.4), &"leg": Color(0, 1, 0.3, 0.4)}


func show_zones(on: bool) -> void:
	var list: Array = []
	if orig_zones.is_empty():
		list.append_array(root_pivot.find_children("*", "Hitbox", true, false))
	else:
		list.append_array(orig_zones)
	if is_instance_valid(_helmet_box):
		list.append(_helmet_box)
	for h in list:
		var hb := h as Hitbox
		if not is_instance_valid(hb):
			continue
		var old := hb.get_node_or_null("ZoneDebug")
		if old:
			old.queue_free()
		if not on:
			continue
		var cs := hb.get_child(0) as CollisionShape3D
		var mi := MeshInstance3D.new()
		mi.name = "ZoneDebug"
		if cs.shape is BoxShape3D:
			var bm := BoxMesh.new()
			bm.size = (cs.shape as BoxShape3D).size
			mi.mesh = bm
		elif cs.shape is SphereShape3D:
			var sm := SphereMesh.new()
			sm.radius = (cs.shape as SphereShape3D).radius
			sm.height = sm.radius * 2.0
			mi.mesh = sm
		else:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ZONE_COLORS.get(hb.zone, Color(1, 1, 1, 0.3))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		mi.position = cs.position
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hb.add_child(mi)


## Alte Original-Figur entfernen: Kamerapunkte, Hand-Dummy hw1 (Waffenbefestigung), Haltungsschicht und
## Anschlag-Modifier gehören zur Figur und werden mit ihr verworfen; set_weapon hängt die Waffe danach neu an.
func _detach_orig() -> void:
	set_prop("")
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	_muzzle = null
	if is_instance_valid(ragdoll):
		ragdoll.cancel()
		ragdoll.queue_free()
	ragdoll = null
	remove_child(orig_figure)
	orig_figure.queue_free()
	orig_figure = null
	orig_zones.clear()
	_helmet_mount = null
	_helmet_vis = null
	_helmet_box = null
	helmet_item = -1
	_set_puppet_hitboxes(true)
	_orig_anim = null
	body = null
	_hold_anim = null
	_aim_mod = null
	_ik = null
	_ik_w = 0.0
	_lw = null
	_roll = 0.0
	_fire_left = 0.0
	_fire_clip = ""
	_hand = null
	_orig_clip = ""
	_hold_clip = ""
	_act_clip = ""
	_act_left = 0.0
	_full_clip = ""
	_aim_w = 0.0
	_fig_yaw = 0.0
	cam_points = CAM_POINTS_DEFAULT.duplicate(true)


## Kamerapunkte des Originals: Dummys "camera3RD" (Drehpunkt der 3.-Person-Kamera) und "cameraFPV" (Auge) im
## Figurenmodell (hd2.exe 0x79CE7F: Mensch +0x62F8/+0x62FC; Kameramodul 0x46C370 hängt die Spielkamera daran).
## Ihre Lage je Haltung kommt aus den Bewegungsanimationen (walk/crouch/prone, export_characters.py);
## die Ruheanimation enthält keine Spur -> feste Werte je Haltung statt der Live-Knoten (kein Einbrechen beim
## Überblenden). Fallback = Werte der Figur en01.
const CAM_POINTS_DEFAULT := {"camera3RD": [Vector3(0, 1.85, -0.04), Vector3(0, 1.329, -0.08), Vector3(0, 0.503, -0.70)],
	"cameraFPV": [Vector3(0, 1.62, -0.032), Vector3(0, 0.988, -0.107), Vector3(0, 0.315, -0.602)]}
var cam_points: Dictionary = CAM_POINTS_DEFAULT.duplicate(true)


func _read_camera_points() -> void:
	var clips := ["walk", "crouch", "prone"]
	for dummy in cam_points:
		var node := orig_figure.find_child(dummy, true, false) as Node3D
		if node == null:
			continue
		var path := String(orig_figure.get_path_to(node))
		for st in 3:
			if not _orig_anim.has_animation(clips[st]):
				continue
			var a := _orig_anim.get_animation(clips[st])
			for ti in a.get_track_count():
				if a.track_get_type(ti) == Animation.TYPE_POSITION_3D and String(a.track_get_path(ti)).ends_with(dummy):
					var p: Vector3 = a.position_track_interpolate(ti, 0.0)
					(cam_points[dummy] as Array)[st] = p
		if path != "":
			node.position = (cam_points[dummy] as Array)[0]


## Kamerapunkt (Weltlage) für die aktuelle (überblendete) Haltung. fpv: Auge, sonst Drehpunkt der 3.-Person-Kamera.
func camera_point(fpv: bool) -> Vector3:
	# Waffenstellung: Kamerapunkte des Stellungsmodells (CAMERAFPV am Rohr; OrigEmplacement.camera_point)
	var mnt = _soldier.get("mounted") if is_instance_valid(_soldier) else null
	if is_instance_valid(mnt) and mnt.has_method("camera_point"):
		var cp: Vector3 = mnt.camera_point(fpv)
		if cp.is_finite():
			return cp
	var pts: Array = cam_points["cameraFPV" if fpv else "camera3RD"]
	var sb := _stance_blend / maxf(_stance_blend.x + _stance_blend.y + _stance_blend.z, 0.001)
	var local: Vector3 = pts[0] * sb.x + pts[1] * sb.y + pts[2] * sb.z
	return global_transform * local


## --- Aktionen der Oberkörperschicht (Nachladen, Wurf, Ziehen) und Ganzkörperaktionen (Verband) ---
var _act_clip := ""
var _act_left := 0.0
var _full_clip := ""
var full_seek := -1.0     ## ≥ 0: Ganzkörperclip steht auf dieser Zeit (s) statt abzuspielen (Waffenstellung)
var _prop: Node3D


## Clip der Haltungsschicht einmal abspielen; Dauer duration (Tempo angepasst), danach wieder die Haltung.
func play_action(clip: String, duration: float = -1.0, blend: float = 0.15) -> bool:
	if _hold_anim == null or clip == "" or not _hold_anim.has_animation(clip) or _dead:
		return false
	var length := _hold_anim.get_animation(clip).length
	_act_clip = clip
	_act_left = duration if duration > 0.0 else length
	_hold_anim.play(clip, blend, length / maxf(_act_left, 0.05))
	return true


func stop_action() -> void:
	if _act_clip != "":
		_act_clip = ""
		_act_left = 0.0
		_hold_clip = ""


func action_clip() -> String:
	return _act_clip


## Ganzkörperaktion auf dem Haupt-Player (z. B. "medic"), "" beendet sie.
func play_full(clip: String) -> void:
	_full_clip = clip if _orig_anim and _orig_anim.has_animation(clip) else ""


func full_clip() -> String:
	return _full_clip


## Gegenstand in der Hand statt der Waffe (Original-Weltmodell, z. B. Verbandskasten l_medkit), "" = Waffe.
func set_prop(model_name: String) -> void:
	if is_instance_valid(_prop):
		_prop.queue_free()
	_prop = null
	_prop_name = model_name
	if model_name != "":
		_prop = prop_instance(model_name)
		_prop.name = "Prop"
		if orig_figure and is_instance_valid(_hand):
			_hand.add_child(_prop)
			# Modelle mit Griff-Dummy RW (Mine w_antiman, Fernglas …) wie Waffen an hw1 ausrichten
			if _prop.has_meta("grip"):
				_prop.transform = OrigWeapons.hand_transform() * (_prop.get_meta("grip") as Transform3D)
		else:
			weapon_socket.add_child(_prop)
		_prop.visible = _weapon_visible
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.visible = _weapon_visible and _prop == null


var _prop_name := ""


## Name des Gegenstands in der Hand ("" = Waffe; Tests).
func prop_name() -> String:
	return _prop_name if is_instance_valid(_prop) else ""


## Gegenstand für die Hand: Original-Weltmodell (Meta "grip" = Ausrichtung, wenn ein Griff-Dummy RW vorhanden ist),
## ohne Cache ein schlichter PLATZHALTER ("placeholder:<hilfsmittel>"), damit die Waffe trotzdem weggesteckt ist.
static func prop_instance(model_name: String) -> Node3D:
	var n: Node3D = null
	if not model_name.begins_with("placeholder:"):
		n = OrigWeapons.world_model(model_name)
	if n == null:
		n = Node3D.new()
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		var kind := model_name.trim_prefix("placeholder:")
		b.size = Vector3(0.16, 0.08, 0.16) if kind == "mine" else Vector3(0.18, 0.1, 0.12)
		mi.mesh = b
		mi.material_override = _smat(Color(0.32, 0.33, 0.27) if kind == "mine" else Color(0.55, 0.22, 0.16), 0.2, 0.7)
		n.add_child(mi)
		n.set_meta("placeholder", true)
		return n
	var rw := n.find_child("RW", true, false) as Node3D
	if rw:
		var root := Node3D.new()
		root.add_child(n)
		n.position = -OrigWeapons._rel(n, rw).origin
		root.set_meta("grip", Transform3D.IDENTITY)
		return root
	return n


func prop() -> Node3D:
	return _prop


## Haltungs-Schicht: zweiter AnimationPlayer mit nur den h_*-Clips (enthalten nur Oberkörperspuren,
## export_characters.py); läuft nach dem Haupt-Player und überschreibt Arme/hw1. Dazu der Anschlag-Modifier.
func _setup_hold(figure: Node3D) -> void:
	if _orig_anim == null or _hand == null:
		return
	var src := _orig_anim.get_animation_library("")
	var lib := AnimationLibrary.new()
	var loops := {}
	for hs in (OrigWeapons.table().get("hold_sets", {}) as Dictionary).values():
		for mode in ["calm", "aim"]:
			for c in (hs as Dictionary).get(mode, []):
				loops[String(c)] = true
	for an in src.get_animation_list():
		if String(an).begins_with("h_"):
			var a := src.get_animation(an)
			# Haltungen in Schleife, Aktionen (Nachladen, Wurf, Ziehen …) einmalig
			a.loop_mode = Animation.LOOP_LINEAR if loops.is_empty() or loops.has(String(an)) else Animation.LOOP_NONE
			lib.add_animation(an, a)
	if lib.get_animation_list().is_empty():
		return
	_hold_anim = AnimationPlayer.new()
	_hold_anim.name = "HoldPlayer"
	_hold_anim.deterministic = false
	_orig_anim.get_parent().add_child(_hold_anim)
	_hold_anim.root_node = _hold_anim.get_path_to(_orig_anim.get_node(_orig_anim.root_node))
	_hold_anim.add_animation_library("", lib)
	var sk := figure.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		_aim_mod = WeaponAimModifier.new()
		_aim_mod.name = "WeaponAim"
		(sk[0] as Skeleton3D).add_child(_aim_mod)
		_aim_mod.setup(sk[0] as Skeleton3D, _hand)
		var hw2 := figure.find_child("hw2", true, false) as Node3D
		if hw2:
			_ik = LeftHandIK.new()
			_ik.name = "LeftHandIK"
			(sk[0] as Skeleton3D).add_child(_ik)       # nach WeaponAim: IK sieht den gedrehten Oberkörper
			_ik.call("setup", sk[0] as Skeleton3D, _hand, hw2)


## Haltung je Waffenklasse (Ruhe/Anschlag × Stehen/Hocken/Liegen) und beim Zielen Lauf in Blickrichtung.
func _update_hold(delta: float, speed: float, aim_pitch: float, aiming: bool) -> void:
	if _hold_anim == null:
		return
	if _full_clip != "":
		# Ganzkörperaktion (Verband): Haltungsschicht und Anschlag aus
		if _hold_anim.is_playing():
			_hold_anim.stop()
		_hold_clip = ""
		_act_clip = ""
		_aim_w = 0.0
		if _aim_mod:
			_aim_mod.weight = 0.0
		_update_ik(delta, false, "")
		return
	# Ganzkörperclips mit eigenen Armen (Leiter, Schwimmen, Klettern, Benutzen …): Haltungsschicht aus; Waffe weg,
	# solange beide Hände gebraucht werden (Leiter, Schwimmen) bzw. die Hände erhoben sind (Ergeben/Gefangener)
	var bstate: String = body.state if body else ""
	var hide_w := body != null and body.weapon_hidden()
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.visible = _weapon_visible and not hide_w and not is_instance_valid(_prop)
	if body and body.arms_free():
		if _hold_anim.is_playing():
			_hold_anim.stop()
		_hold_clip = ""
		_act_clip = ""
		_aim_w = 0.0
		if _aim_mod:
			_aim_mod.weight = 0.0
		_update_ik(delta, false, "")
		return
	if bstate in ["surrender", "captive"] or (body and body.act_upper != ""):
		# Hände hoch (anim.sav „!zajatecST/DR/LE“) bzw. Oberkörper-Tätigkeit (HUMAN_ACTIVITY_*, BodyAnim.start_activity):
		# Oberkörperclip bis zum letzten Bild, dann stehen lassen
		var hc: String = body.act_upper if body.act_upper != "" else \
				BodyAnim.upper("surrender%d" % (1 if bstate == "captive" else clampi(_anim_stance, 0, 2)))
		if _hold_anim.has_animation(hc):
			if _hold_clip != hc:
				_hold_clip = hc
				_act_clip = ""
				_hold_anim.speed_scale = 1.0
				_hold_anim.play(hc, 0.25, 1.0)
			elif _hold_anim.current_animation_position >= _hold_anim.get_animation(hc).length - 0.06:
				_hold_anim.speed_scale = 0.0
		_aim_w = 0.0
		if _aim_mod:
			_aim_mod.weight = 0.0
		_update_ik(delta, false, "")
		return
	if _hold_anim.speed_scale != 1.0:
		_hold_anim.speed_scale = 1.0
	recoil = move_toward(recoil, 0.0, delta * 7.0)
	if _act_clip != "":
		_act_left -= delta
		_fire_left = 0.0
		if _act_left <= 0.0 or _dead:
			stop_action()
		else:
			_aim_w = move_toward(_aim_w, 0.0, delta * 8.0)
			if _aim_mod:
				_aim_mod.weight = _aim_w
			_update_ik(delta, false, OrigWeapons.hold_set(_weapon_data, _team()) if _weapon_data else "")
			return
	var clip := ""
	var hset := ""
	_fire_left = maxf(_fire_left - delta, 0.0)
	var firing := _fire_left > 0.0 and _fire_clip != ""
	var holding_prop := is_instance_valid(_prop)
	if (holding_prop or (_weapon_data != null and is_instance_valid(_weapon_mesh))) and not _dead:
		var st := 0
		if _stance_blend.z > 0.5:
			st = 2
		elif _stance_blend.y > 0.5:
			st = 1
		# Hilfsmittel in der Hand (Verband, Mine, Sprengstoff, Fernglas): Original-Haltesatz „hand“ wie Granate
		hset = "hand" if holding_prop else OrigWeapons.hold_set(_weapon_data, _team())
		clip = OrigWeapons.hold_clip(hset, "aim" if aiming else "calm", st)
		if firing:
			clip = _fire_clip
	if clip != "" and _hold_anim.has_animation(clip):
		if clip != _hold_clip or not _hold_anim.is_playing():
			_hold_clip = clip
			_hold_anim.play(clip, 0.05 if firing else 0.2, 1.0)
	elif _hold_anim.is_playing() or _hold_clip != "":
		_hold_clip = ""
		_hold_anim.stop()
	var aim_on := (aiming or firing) and _hold_clip != "" and hset != "hand" and not _dead
	_aim_w = move_toward(_aim_w, 1.0 if aim_on else 0.0, delta * (12.0 if firing else 5.0))
	# Raketenwerfer: im Anschlag Rohr auf die Schulter (180° um die Rohrachse, siehe _roll)
	var roll_to: float = PI if hset == "bazooka" and aim_on else 0.0
	_roll = move_toward(_roll, roll_to, delta * PI * 5.0)
	if is_instance_valid(_weapon_mesh) and _weapon_mesh.get_parent() == _hand:
		_weapon_mesh.transform = OrigWeapons.hand_transform() * Transform3D(Basis(Vector3(0, 0, 1), _roll), Vector3.ZERO)
	_update_ik(delta, not _dead, hset)
	if _aim_mod == null:
		return
	_aim_mod.weight = _aim_w
	_aim_mod.kick = recoil * _kick_angle
	_aim_mod.want_dir = global_basis * Vector3(0.0, sin(aim_pitch), -cos(aim_pitch))
	# Im Stand/Hocken dreht sich die ganze Figur in den Anschlag (Original-Haltungen zeigen schräg links);
	# in Bewegung und liegend gleicht nur der Oberkörper aus.
	var k := clampf(delta * 6.0, 0.0, 1.0)
	if aim_on and speed < 0.3 and _stance_blend.z < 0.5:
		_fig_yaw = clampf(_fig_yaw + _aim_mod.yaw_error * k, -1.3, 1.3)
	else:
		_fig_yaw = lerp_angle(_fig_yaw, 0.0, k)
	orig_figure.rotation.y = _fig_yaw


## Linke-Hand-IK: bei Zweihandwaffen (MP, Gewehr, MG, Raketenwerfer) in Ruhe-, Anschlag- und Feuerhaltung;
## nicht bei Pistole/Granate/Messer und während Aktionen (Nachladen, Ziehen, Wurf – dort führt die Animation).
func _update_ik(delta: float, allowed: bool, hset: String) -> void:
	if _ik == null:
		return
	var on := allowed and hset in ["smg", "rifle", "mg", "bazooka"] and is_instance_valid(_lw) \
		and is_instance_valid(_weapon_mesh) and not is_instance_valid(_prop)
	_ik_w = move_toward(_ik_w, 1.0 if on else 0.0, delta * 6.0)
	_ik.set("weight", _ik_w)
	if is_instance_valid(_lw) and is_instance_valid(_weapon_mesh):
		_ik.set("lw_in_hw1", _weapon_mesh.transform * OrigWeapons._rel(_weapon_mesh, _lw))


## Abstand linke Hand (hw2) – Waffengriff LW nach der IK (m), -1 = IK inaktiv (Tests).
func left_hand_error() -> float:
	return float(_ik.get("last_error")) if _ik else -1.0


var _kick_angle := deg_to_rad(3.0)


## Schuss: Original-Feuerclip der Haltungsschicht (anim.sav +0x3A0) und Rückstoß des Oberkörpers.
func _on_shot_fired(w: Weapon) -> void:
	if w == null or _dead or w.data.action == WeaponData.Action.MELEE or w.data.slot == WeaponData.Slot.GRENADE:
		return
	recoil = 1.0
	_kick_angle = deg_to_rad(clampf(w.data.recoil_pitch * 2.0, 1.5, 8.0))
	if _hold_anim == null or _act_clip != "" or _full_clip != "":
		return
	var st := 0
	if _stance_blend.z > 0.5:
		st = 2
	elif _stance_blend.y > 0.5:
		st = 1
	var clip := OrigWeapons.action_clip(w.data, _team(), "fire", st)
	if clip == "" or not _hold_anim.has_animation(clip):
		return
	_fire_clip = clip
	var a := _hold_anim.get_animation(clip)
	_fire_left = clampf(a.length, 0.25, 1.0)
	_hold_clip = clip
	_hold_anim.play(clip, 0.05, 1.0)
	_hold_anim.seek(0.0, true)


## Laufender Feuerclip ("" = keiner; Tests).
func fire_clip() -> String:
	return _fire_clip if _fire_left > 0.0 else ""


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
	if _full_clip != "":
		_play_orig(_full_clip, 1.0)
		if full_seek >= 0.0 and _orig_anim and _orig_anim.current_animation == _full_clip:
			# Bedienhaltung an Waffenstellungen: Bild nach Schwenk (OrigEmplacement). Player manuell, damit der kurze
			# Clip zwischen zwei Abgleichen nicht weiterläuft/umläuft; die Überblendung schreitet mit dt fort.
			_orig_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var dt := get_physics_process_delta_time()
			_orig_anim.seek(maxf(full_seek - dt, 0.0), false)
			_orig_anim.advance(dt)
		return
	# Original-Ganzkörperclips aus anim.sav (BodyAnim): Bewegung je Haltung/Richtung/Gangart, Übergänge, Lehnen,
	# Springen/Klettern/Leiter, Schwimmen, Treffer, Ergeben/Gefangener, Benutzen
	if body and _orig_anim and not BodyAnim.table().get("clips", {}).is_empty():
		var r := body.update(get_physics_process_delta_time(), _soldier, _anim_stance, speed, _lean, global_basis)
		# Schwimmclips liegen mit der Wurzel 0,14 m unter dem Ursprung (Ursprung = Wasserlinie); der Soldat schwimmt
		# mit dem Ursprung 1,4 m unter der Oberfläche (Soldier._update_swim) -> Figur so weit anheben
		# Insassen: Ursprung der Sitzclips (!ridic/!spol/!namotorce) = Sitz-Frame SEATnn [P]; Soldier setzt seinen
		# Ursprung 0,55 m unter den Sitz (Soldier._physics_process) -> Figur wieder auf den Sitz heben
		var lift := 1.4 if body.state == "swim" else (0.55 if body.state == "vehicle" else 0.0)
		if not is_equal_approx(orig_figure.position.y, lift):
			orig_figure.position.y = move_toward(orig_figure.position.y, lift, get_physics_process_delta_time() * 4.0)
		var c := String(r.get("clip", ""))
		if c != "" and _orig_anim.has_animation(c):
			if r.has("seek"):
				_orig_seek(c, float(r["seek"]), float(r.get("blend", 0.15)))
				return
			_orig_manual(false)
			if r.get("keep", false):
				_orig_clip = c          # Einmalaktion: BodyAnim hat den Clip mit eigenem Tempo gestartet
				_orig_anim.speed_scale = 1.0
				return
			_orig_anim.speed_scale = float(r.get("rate", 1.0))
			if _orig_clip != c:
				_orig_clip = c
				_orig_anim.play(c, float(r.get("blend", 0.2)))
			return
	_orig_manual(false)
	# Ohne Zuordnungstabelle (alter Cache): Hocken/Liegen als Haltungsclips (!drepZB / !leziN)
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


## --- Ganzkörperclips (BodyAnim) ---------------------------------------------------------------------------
var body: BodyAnim
var _anim_stance := 0
var _last_hit_zone := ""
var death_clip_name := ""     ## gewählter Todesclip (Tests/Kontrollbilder)


## Haupt-Player manuell/automatisch weiterschalten (Standbilder: Lehnen, Waffenstellung).
func _orig_manual(on: bool) -> void:
	if _orig_anim == null:
		return
	var want := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if on else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if _orig_anim.callback_mode_process != want:
		_orig_anim.callback_mode_process = want


## Standbild eines Ganzkörperclips (z. B. Lehnen bis zum Scheitelbild); Überblendung schreitet mit dt fort.
func _orig_seek(c: String, t: float, blend: float) -> void:
	_orig_manual(true)
	_orig_anim.speed_scale = 1.0
	if _orig_clip != c or _orig_anim.current_animation != c:
		_orig_clip = c
		_orig_anim.play(c, blend)
	var dt := get_physics_process_delta_time()
	_orig_anim.seek(maxf(t - dt, 0.0), false)
	_orig_anim.advance(dt)


## Treffer an der Figur (Soldier.damaged): Original-Trefferclip je Zone, Richtung aus der Lage des Angreifers.
func _on_damaged(amount: float, zone: StringName) -> void:
	_last_hit_zone = String(zone)
	if body == null or _dead or amount < 1.0 or not is_instance_valid(_soldier):
		return
	var from := Vector3.ZERO
	var att = _soldier.get("last_attacker")
	if att is Node3D and is_instance_valid(att):
		from = global_basis.inverse() * ((att as Node3D).global_position - global_position).normalized()
	var vel: Vector3 = _soldier.get("velocity") if _soldier is CharacterBody3D else Vector3.ZERO
	body.on_hit(_anim_stance, zone, from, Vector2(vel.x, vel.z).length())


## Ganzkörper-Einmalaktion (Benutzen, Tür, Aufheben, Sprengstoff, Messer von hinten …) über BodyAnim.full-Schlüssel.
func play_body(key: String, duration: float = -1.0, arms: bool = true, kind: String = "use") -> bool:
	if body == null or _dead:
		return false
	var c := BodyAnim.full(key)
	if not body.play_oneshot(c, duration, arms, kind):
		return false
	_orig_manual(false)
	_orig_clip = c
	_orig_anim.speed_scale = 1.0
	return true


## Hände hoch (EnemyBrain.surrender); die Haltungsschicht liest außerdem die Meta „hands_up“/„captured“.
var hands_up := false


func set_hands_up(on: bool) -> void:
	hands_up = on


func play_death(direction: Vector3) -> void:
	if _dead:
		return
	if orig_figure:
		var dc := ""
		if body:
			var fd := direction
			fd.y = 0.0
			var ld: Vector3 = global_basis.inverse() * fd.normalized() if fd.length() > 0.05 else Vector3.ZERO
			var kind: String = String(_soldier.get_meta("death_kind", "")) if is_instance_valid(_soldier) else ""
			var zone := _last_hit_zone
			if zone == "" and is_instance_valid(_soldier):
				zone = String(_soldier.get_meta("last_zone", ""))
			dc = body.death_clip(_anim_stance, ld, zone, kind)
			body.stop_oneshot()
		_orig_manual(false)
		if dc != "":
			death_clip_name = dc
			_orig_anim.speed_scale = 1.0
			_orig_clip = dc
			_orig_anim.play(dc, 0.15)
		else:
			death_clip_name = "death"
			_play_orig("death", 1.0)
	_stop_hold()
	_dead = true
	_begin_ragdoll(direction, death_clip_name)
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


## --- B-016 Ragdoll (src/actors/ragdoll.gd) -------------------------------------------------------------------
var ragdoll: Ragdoll


## Übergabe vom Todesclip an die Physik. Treffer-Daten legt Soldier.apply_hit/die bzw. Ballistics als Metas ab:
## „_rd_hit“ [Weltpunkt, Knochen], „_rd_amount“ Schaden, „last_zone“, „_rd_vel“ Fahrzeuggeschwindigkeit.
func _begin_ragdoll(direction: Vector3, clip: String) -> void:
	if not is_instance_valid(ragdoll) or not Ragdoll.wanted(ragdoll.sk) or not is_instance_valid(_soldier):
		return
	var s := _soldier
	var hit := {"dir": direction, "amount": float(s.get_meta("_rd_amount", 30.0)),
		"clip": clip, "zone": _last_hit_zone if _last_hit_zone != "" else String(s.get_meta("last_zone", "")), "vel": s.get_meta("_rd_vel", Vector3.ZERO)}
	var hp = s.get_meta("_rd_hit", [])
	if hp is Array and (hp as Array).size() >= 2 and Time.get_ticks_msec() - int(s.get_meta("_rd_hit_ms", 0)) < 500:
		hit["pos"] = hp[0]
		hit["bone"] = String(hp[1])
	var delay := Ragdoll.START_DELAY
	# Explosion (in den letzten 0,6 s in Reichweite): sofort, Impuls kommt aus Ragdoll._recent
	var now := Time.get_ticks_msec()
	for e in Ragdoll._recent:
		if now - int(e[2]) <= 600 and (e[0] as Vector3).distance_to(global_position) <= float(e[1]) * Ragdoll.EXPL_RANGE_K:
			hit["explosive"] = true
			delay = 0.0
	# Tod im Sitzen: Anfang des Original-Clips „!smrtsed1/2“ bzw. „!smrttur2“ (Zusammensacken), dann Physik
	if body and String(body.get("seated")) in ["sit", "turk"]:
		delay = 0.45
	# MG-Stellung (Bediener steigt beim Tod ab, Figur gleitet zurück) / aus dem Fahrzeug gefallen: sofort aus der Bedienhaltung
	if s.get("mounted") != null or s.has_meta("_rd_vel"):
		delay = 0.0
	if String(s.get_meta("death_kind", "")) == "throat" and _orig_anim and _orig_anim.has_animation(clip):
		delay = _orig_anim.get_animation(clip).length * 0.7    # Kehlschnitt: Original-Clip trägt den Ablauf
	ragdoll.begin(hit, delay)


## Endpose der Leiche (leer, solange keine vorliegt)
func corpse_pose() -> PackedFloat32Array:
	if is_instance_valid(ragdoll) and ragdoll.is_frozen():
		return ragdoll.frozen_pose
	return PackedFloat32Array()


## Endpose übernehmen (Netz, Spielstand, Spät-Beitritt); false ohne passendes Skelett
func apply_corpse_pose(pose: PackedFloat32Array, set_origin := true) -> bool:
	if not is_instance_valid(ragdoll):
		return false
	return ragdoll.apply_pose(pose, set_origin)


## Tod: Haltungsschicht und Anschlag aus; die Waffe bleibt an der Hand und folgt der Todesanimation.
func _stop_hold() -> void:
	if _hold_anim:
		_hold_anim.stop()
	_hold_clip = ""
	_act_clip = ""
	_full_clip = ""
	set_prop("")
	_aim_w = 0.0
	if _aim_mod:
		_aim_mod.weight = 0.0
	_fire_left = 0.0
	_ik_w = 0.0
	if _ik:
		_ik.set("weight", 0.0)
	if orig_figure:
		orig_figure.rotation.y = 0.0
		_fig_yaw = 0.0


func set_dead_instant() -> void:
	var dc: String = body.death_clip(_anim_stance, Vector3(0, 0, 1), "", "") if body else ""
	if dc == "":
		dc = "death"
	if orig_figure and _orig_anim and _orig_anim.has_animation(dc):
		_orig_manual(false)
		_play_orig(dc, 1.0)
		_orig_anim.seek(_orig_anim.get_animation(dc).length, true)
	_stop_hold()
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
