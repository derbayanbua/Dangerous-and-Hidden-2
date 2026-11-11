class_name Gore
extends RefCounted
## B-037 Blutstufe „EXTRA GORE“ (Settings.blood_level = 3) – BEWUSSTE ABWEICHUNG vom Original ([D],
## Option, Standard aus). Das Original kennt keine Abtrennung (nur Todesclips, Blut-Decals; CLAUDE.md „Bluteffekte“).
##
## Ablauf (alle Werte [D]):
## - `decide` (nur wo Schaden gerechnet wird: Einzelspieler/Server) bestimmt beim Tod eine Bitmaske aus Trefferzone,
##   Schaden und Waffe des letzten Treffers (Ballistik-Metas `_gore_w`, `_rd_hit`, Soldier-Metas `_gore_zone`, `_rd_amount`)
##   bzw. Abstand/Stärke einer Explosion (`Ragdoll._recent`). Kopf nur bei Kopftreffern mit Gewehrpatrone/MG/Scharfschütze
##   oder Kanone, Glieder nur bei starken Treffern, Explosionen nach Abstand mehrere Teile. Die Maske wird unabhängig von der
##   eigenen Blutstufe bestimmt (MP: der Server meldet sie in `Net._killed`/`_corpse_pose`, alle sehen dasselbe).
## - `apply` (nur bei Stufe EXTRA GORE sichtbar): Teil an der Figur über einen eigenen SkeletonModifier3D (`GoreMask`,
##   nach Animation/IK/Ragdoll) auf Skalierung ~0 gesetzt (Kinder folgen), loses Teil = RigidBody3D mit einer Kopie des
##   Figurenskeletts, in der nur der abgetrennte Teilbaum sichtbar ist (gleiches Skin-Mesh → passender Meshausschnitt),
##   Impuls aus Schuss-/Explosionsrichtung. Stumpf: dunkle Kappe, Kleidungsblut, kurzer Strahl und Spritzer (blood_fx);
##   loses Teil: Strahl am Schnitt + Tropfspur. Kopf ab → Helm fällt (Helmet.knock_off, nur Einzelspieler/Server).
## - Ragdoll: abgetrennte Körper (und Teilbaum) ohne Kollision, Masse klein; Maske bleibt hinter dem Simulator.
## - Grenzen: höchstens MAX_PIECES lose Teile (ältestes verschwindet), Einfrieren nach FREEZE_S, Entfernen nach LIFE_S.
## - Spielstand: Soldier.serialize()["gore"] = Maske → beim Laden nur Stümpfe (keine losen Teile).

const BONES := ["f", "h", "l", "i", "m", "o", "s", "p", "t"]   ## Bit 0..8: Kopf, Oberarm h/l, Unterarm i/m, Oberschenkel o/s, Unterschenkel p/t
const CHILD := {"h": "i", "l": "m", "o": "p", "s": "t"}
const ARMS := ["h", "l", "i", "m"]
const LEGS := ["o", "s", "p", "t"]
const ALL_MASK := (1 << 9) - 1
const MAX_PIECES := 12
const FREEZE_S := 6.0
const LIFE_S := 45.0
const RECENT_MS := 600
## Wahrscheinlichkeiten [D]
const P_HEAD := 0.45            ## Kopftreffer Gewehrpatrone
const P_HEAD_SNIPER := 0.65     ## Repetierer (Scharfschütze) / MG
const P_LIMB := 0.3             ## starker Gliedtreffer (Gewehr/MG)
const P_CANNON := 0.9           ## Kanone/20 mm

static var _pieces: Array = []
static var stats := {"decided": 0, "applied": 0, "pieces": 0, "stumps": 0, "removed": 0, "helmets": 0}
static var rng := RandomNumberGenerator.new()
static var force_roll := -1.0   ## Tests: fester Zufallswert (0..1), < 0 = Zufall


static func enabled() -> bool:
	return Settings.blood and Settings.blood_level >= Settings.BLOOD_GORE


static func bit(bone: String) -> int:
	var i := BONES.find(bone)
	return 1 << i if i >= 0 else 0


## Netzwert prüfen: nur bekannte Bits; ganzer Arm/ganzes Bein schließt das Unterteil ein (Unterteil-Bit entfällt)
static func sanitize_mask(m: int) -> int:
	m &= ALL_MASK
	for up in CHILD:
		if m & bit(up):
			m &= ~bit(CHILD[up])
	return m


static func mask_bones(m: int) -> Array:
	var out := []
	for i in BONES.size():
		if m & (1 << i):
			out.append(BONES[i])
	return out


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else rng.randf()


# --- Entscheidung (Einzelspieler/Server) ------------------------------------------------------------------------

static func decide(s: Node3D, _direction := Vector3.ZERO) -> int:
	if s == null or not is_instance_valid(s):
		return 0
	stats["decided"] += 1
	var now := Time.get_ticks_msec()
	var amount := float(s.get_meta("_rd_amount", 0.0))
	var fresh := now - int(s.get_meta("_gore_ms", 0)) <= RECENT_MS
	var zone := String(s.get_meta("_gore_zone", "")) if fresh else ""
	var bullet := now - int(s.get_meta("_rd_hit_ms", -100000)) <= RECENT_MS
	var w = (s.get_meta("_gore_w") if s.has_meta("_gore_w") else null) if bullet else null
	if String(s.get_meta("death_kind", "")) == "throat":
		return 0
	# Explosion in Reichweite (Effects.explosion → Ragdoll._recent): Stärke nach Abstand
	var k := 0.0
	var center := s.global_position + Vector3.UP * 0.9
	for e in Ragdoll._recent:
		if now - int(e[2]) > RECENT_MS:
			continue
		var r := maxf(float(e[1]), 0.5)
		k = maxf(k, 1.0 - (e[0] as Vector3).distance_to(center) / r)
	if k <= 0.0 and not bullet and fresh and amount >= 60.0:
		k = clampf(amount / 200.0, 0.0, 1.0)      # Explosionsschaden ohne aufgezeichnete Explosion (z. B. Artillerie)
	if k > 0.15 and not bullet:
		return explosion_mask(k)
	if zone == "" or not (w is WeaponData):
		return 0
	var wd := w as WeaponData
	var cannon := wd.damage >= 90.0 or wd.caliber.begins_with("20")
	var rifle := wd.muzzle_velocity >= 650.0 or wd.damage >= 55.0
	var sniper := wd.action == WeaponData.Action.BOLT
	var mg := wd.is_automatic() and rifle
	var bone := ""
	var hp = s.get_meta("_rd_hit", [])
	if hp is Array and (hp as Array).size() >= 2:
		bone = String(hp[1])
	match zone:
		"head":
			if not (rifle or cannon):
				return 0
			var p := P_CANNON if cannon else (P_HEAD_SNIPER if (sniper or mg) else P_HEAD)
			return bit("f") if _roll() < p else 0
		"arm", "leg":
			if not (rifle or cannon):
				return 0
			var p := P_CANNON if cannon else P_LIMB * clampf(amount / 12.0, 0.6, 1.4)
			if _roll() >= p:
				return 0
			var pool: Array = ARMS if zone == "arm" else LEGS
			if not (bone in pool):
				bone = pool[rng.randi() % pool.size()]
			if CHILD.has(bone) and rng.randf() >= 0.5:
				bone = CHILD[bone]          # Oberteil getroffen: halb ganzes Glied, halb Unterteil
			return bit(bone)
		_:
			if cannon and _roll() < 0.5:
				return explosion_mask(0.5)
	return 0


## Explosion: k = 1 − Abstand/Radius (0..1) → Anzahl und Art der Teile
static func explosion_mask(k: float) -> int:
	var n := 0
	if k > 0.75:
		n = rng.randi_range(2, 4)
	elif k > 0.45:
		n = rng.randi_range(1, 2)
	elif _roll() < 0.3:
		n = 1
	var cand: Array = []
	if k > 0.45:
		cand = ["h", "l", "o", "s", "i", "m", "p", "t"]
	else:
		cand = ["i", "m", "p", "t"]
	if k > 0.7 and _roll() < 0.5:
		cand.push_front("f")
		n += 1
	var m := 0
	for j in n:
		if cand.is_empty():
			break
		var idx := 0 if cand[0] == "f" else rng.randi() % cand.size()
		m |= bit(cand[idx])
		cand.remove_at(idx)
	return sanitize_mask(m)


# --- Darstellung --------------------------------------------------------------------------------------------------

static func skeleton_of(s: Node) -> Skeleton3D:
	var model = s.get("model") if s else null
	if model == null or not is_instance_valid(model):
		return null
	var rd = model.get("ragdoll")
	if rd != null and is_instance_valid(rd) and is_instance_valid(rd.sk):
		return rd.sk
	for sk in (model as Node).find_children("*", "Skeleton3D", true, false):
		if (sk as Skeleton3D).find_bone("f") >= 0 and (sk as Skeleton3D).find_bone("c") >= 0:
			return sk
	return null


static func mask_node(sk: Skeleton3D) -> GoreMask:
	for c in sk.get_children():
		if c is GoreMask:
			return c
	return null


static func mask_node_of(s: Node) -> GoreMask:
	var sk := skeleton_of(s)
	return mask_node(sk) if sk else null


## Maske anwenden. fx = frischer Tod (lose Teile, Blut, Helm); false = Spielstand/Spät-Beitritt (nur Stümpfe)
static func apply(s: Node3D, m: int, direction: Vector3, fx: bool) -> void:
	m = sanitize_mask(m)
	if m == 0 or not enabled() or s == null or not is_instance_valid(s) or not s.is_inside_tree():
		return
	var sk := skeleton_of(s)
	if sk == null:
		return
	var g := mask_node(sk)
	if g == null:
		g = GoreMask.new()
		g.name = "GoreMask"
		g.set_meta("gore", true)
		sk.add_child(g)
	sk.move_child(g, -1)              # nach Animation/IK/Ragdoll-Simulator
	sk.force_update_all_bone_transforms()
	var dir := direction.normalized() if direction.length() > 0.01 else -s.global_basis.z
	stats["applied"] += 1
	for bn in mask_bones(m):
		var b := sk.find_bone(bn)
		if b < 0 or g.bones.has(b):
			continue
		if fx:
			_spawn_piece(s, sk, b, dir)
		_stump(s, sk, b, fx, dir)
		g.bones.append(b)
		_ragdoll_part_off(s, bn)
		if bn == "f" and fx and (not Net.is_online or Net.is_authority()) and s is Soldier:
			stats["helmets"] += 1
			Helmet.knock_off(s as Soldier, dir + Vector3.UP * 0.5)
	for b in g.bones:
		sk.set_bone_pose_scale(b, Vector3.ONE * GoreMask.TINY)


## Von Ragdoll._build gerufen: Maske hinter den neuen Simulator, abgetrennte Körper entschärfen
static func after_ragdoll_build(r: Ragdoll) -> void:
	if r == null or not is_instance_valid(r.sk):
		return
	var g := mask_node(r.sk)
	if g == null:
		return
	r.sk.move_child(g, -1)
	for b in g.bones:
		_ragdoll_part_off(r.soldier, r.sk.get_bone_name(b))


static func _ragdoll_part_off(s: Node, bn: String) -> void:
	var model = s.get("model") if s else null
	var rd = model.get("ragdoll") if model else null
	if rd == null or not is_instance_valid(rd):
		return
	for name in [bn, CHILD.get(bn, "")]:
		var pb: PhysicalBone3D = rd.bodies.get(name)
		if pb != null:
			pb.collision_layer = 0
			pb.collision_mask = 0
			pb.mass = 0.2


static func _in_subtree(sk: Skeleton3D, i: int, root: int) -> bool:
	while i >= 0:
		if i == root:
			return true
		i = sk.get_bone_parent(i)
	return false


static func _bone_world(sk: Skeleton3D, b: int) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(b)


## Stumpf: dunkle Kappe am Elterngelenk (verdeckt die Schnittkante), Kleidungsblut, Strahl, Spritzer
static func _stump(s: Node3D, sk: Skeleton3D, b: int, fx: bool, dir: Vector3) -> void:
	var p := sk.get_bone_parent(b)
	if p < 0:
		return
	stats["stumps"] += 1
	var joint := _bone_world(sk, b).origin
	var pj := _bone_world(sk, p).origin
	var out := (joint - pj).normalized() if joint.distance_to(pj) > 0.01 else Vector3.UP
	var nm := "GoreStump_" + sk.get_bone_name(p).validate_node_name()
	var ba := sk.get_node_or_null(nm) as BoneAttachment3D
	if ba == null:
		ba = BoneAttachment3D.new()
		ba.name = nm
		sk.add_child(ba)
		ba.bone_name = sk.get_bone_name(p)
	var head := sk.get_bone_name(b) == "f"
	var r := 0.075 if head else 0.055
	var cap := MeshInstance3D.new()
	cap.name = "GoreCap"
	cap.mesh = _cap_mesh(r)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ba.add_child(cap)
	cap.global_position = joint
	_cut_face(ba, joint, out, r, head)        # B-045: Schnittfläche mit Fleischrand und Knochen
	var bfx = Effects.blood_fx
	if bfx == null:
		return
	bfx.wound(s, joint.lerp(pj, 0.25), out, 0.3)
	if fx:
		bfx._jet(ba, joint, (out + Vector3.UP * 0.2).normalized(), randf_range(2.0, 3.2) if head else randf_range(1.4, 2.4))
		bfx.stump_pool(s, ba, 1.7 if head else 1.3)   # B-045: großer Blutverlust am Stumpf
		var parent: Node3D = Effects._parent()
		if parent:
			bfx._spray(parent, joint, (out + dir * 0.5).normalized(), 1.5, 35.0)
			bfx._floor_splat(joint + dir * 0.4, randf_range(0.4, 0.7), "x_blood04", 3.0)


## B-045 [D]: Schnittfläche an Stumpf bzw. losem Teil: flache Fleischscheibe (dunkelrot, feucht glänzend), darin der
## Knochenquerschnitt (elfenbein) leicht herausstehend. axis = Richtung aus dem Schnitt heraus.
static func _cut_face(parent: Node3D, at: Vector3, axis: Vector3, r: float, head: bool) -> void:
	var up := axis.normalized() if axis.length() > 0.01 else Vector3.UP
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var basis := Basis(x, up, x.cross(up)).orthonormalized()
	var flesh := MeshInstance3D.new()
	flesh.name = "GoreFlesh" if parent is BoneAttachment3D else "GoreCut"
	flesh.mesh = _disc_mesh(r * 0.95, 0.025, Color(0.45, 0.05, 0.04), 0.25)
	flesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flesh)
	flesh.global_transform = Transform3D(basis, at + up * 0.012)
	var bone := MeshInstance3D.new()
	bone.name = "GoreBone"
	# Halswirbel bzw. Röhrenknochen; ragt 2–3 cm aus der Schnittfläche
	bone.mesh = _disc_mesh(0.016 if head else 0.014, 0.055 if head else 0.045, Color(0.86, 0.8, 0.68), 0.6)
	bone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bone)
	bone.global_transform = Transform3D(basis, at + up * (0.02 if head else 0.016))


static var _disc_cache := {}


static func _disc_mesh(r: float, h: float, col: Color, rough: float) -> CylinderMesh:
	var key := "%.3f_%.3f_%s" % [r, h, col.to_html()]
	if _disc_cache.has(key):
		return _disc_cache[key]
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.05
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	cm.material = mat
	_disc_cache[key] = cm
	return cm


static var _cap_cache := {}


static func _cap_mesh(r: float) -> SphereMesh:
	if _cap_cache.has(r):
		return _cap_cache[r]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.6
	sm.radial_segments = 10
	sm.rings = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.03, 0.02)
	mat.roughness = 0.35
	sm.material = mat
	_cap_cache[r] = sm
	return sm


## Loses Teil: RigidBody3D mit Skelettkopie (nur Teilbaum sichtbar) und den Skin-Meshes der Figur
static func _spawn_piece(s: Node3D, sk: Skeleton3D, b: int, dir: Vector3) -> RigidBody3D:
	var parent: Node3D = Effects._parent()
	if parent == null:
		parent = s.get_parent() as Node3D
	if parent == null:
		return null
	var bg := sk.get_bone_global_pose(b)
	var world := (sk.global_transform * bg).orthonormalized()
	var rb := RigidBody3D.new()
	rb.name = "GorePiece_" + sk.get_bone_name(b)
	rb.collision_layer = Ragdoll.LAYER
	rb.collision_mask = Ragdoll.MASK
	rb.continuous_cd = true
	var bn := sk.get_bone_name(b)
	rb.mass = float(Ragdoll.BONES.get(bn, {}).get("mass", 3.0)) + (float(Ragdoll.BONES.get(CHILD.get(bn, ""), {}).get("mass", 0.0)) if CHILD.has(bn) else 0.0)
	rb.linear_damp = 0.2
	rb.angular_damp = 1.2
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.1
	rb.physics_material_override = pm
	parent.add_child(rb)
	rb.global_transform = world
	# Kollisionsform: Trefferzonen-Kiste des Knochens (wie Ragdoll), ganzes Glied + Kiste des Unterteils
	var boxes := {}
	for z in SoldierModel.orig_zone_table():
		boxes[String(z["bone"])] = [Vector3(z["min"][0], z["min"][1], z["min"][2]), Vector3(z["max"][0], z["max"][1], z["max"][2])]
	var shapes := [bn]
	if CHILD.has(bn):
		shapes.append(CHILD[bn])
	for sn in shapes:
		var bi := sk.find_bone(sn)
		if bi < 0:
			continue
		var box: Array = boxes.get(sn, [Vector3(-0.06, 0, -0.06), Vector3(0.06, 0.25, 0.06)])
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = ((box[1] as Vector3) - (box[0] as Vector3)).max(Vector3(0.05, 0.05, 0.05))
		cs.shape = sh
		var rel := world.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(bi)).orthonormalized()
		cs.transform = rel * Transform3D(Basis(), ((box[0] as Vector3) + (box[1] as Vector3)) * 0.5)
		rb.add_child(cs)
	# Skelettkopie: abgetrennter Knochen wird Wurzel (Pose = globale Pose), alle anderen außerhalb des Teilbaums ~0
	var skel := Skeleton3D.new()
	skel.name = "PieceSkeleton"
	var n := sk.get_bone_count()
	for i in n:
		skel.add_bone(sk.get_bone_name(i))
	for i in n:
		skel.set_bone_rest(i, sk.get_bone_rest(i))
		if i != b and sk.get_bone_parent(i) >= 0:
			skel.set_bone_parent(i, sk.get_bone_parent(i))
	rb.add_child(skel)
	skel.global_transform = sk.global_transform
	for i in n:
		if i == b:
			skel.set_bone_pose_position(i, bg.origin)
			skel.set_bone_pose_rotation(i, bg.basis.get_rotation_quaternion())
			skel.set_bone_pose_scale(i, bg.basis.get_scale())
		else:
			skel.set_bone_pose_position(i, sk.get_bone_pose_position(i))
			skel.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i))
			skel.set_bone_pose_scale(i, sk.get_bone_pose_scale(i) if _in_subtree(sk, i, b) else Vector3.ONE * GoreMask.TINY)
	var model: Node = s.get("model")
	if model:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var src := mi as MeshInstance3D
			if src.skin == null or src.mesh == null or src.get_node_or_null(src.skeleton) != sk:
				continue
			var dup := MeshInstance3D.new()
			dup.mesh = src.mesh
			dup.skin = src.skin
			dup.material_override = src.material_override
			for si in src.get_surface_override_material_count():
				dup.set_surface_override_material(si, src.get_surface_override_material(si))
			dup.layers = src.layers
			skel.add_child(dup)
			dup.skeleton = NodePath("..")
			dup.transform = sk.global_transform.affine_inverse() * src.global_transform
	skel.force_update_all_bone_transforms()
	# Impuls aus Schuss-/Explosionsrichtung [D]
	var v := dir * rng.randf_range(2.5, 5.0) + Vector3.UP * rng.randf_range(1.5, 3.5)
	var rv = s.get_meta("_rd_vel", Vector3.ZERO)
	if rv is Vector3:
		v += rv
	rb.linear_velocity = v
	rb.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	_register(rb)
	stats["pieces"] += 1
	# Blut am Schnitt des losen Teils + Tropfspur
	var bfx = Effects.blood_fx
	var p := sk.get_bone_parent(b)
	var back := (_bone_world(sk, p).origin - world.origin).normalized() if p >= 0 else Vector3.UP
	_cut_face(rb, world.origin, back, 0.07 if bn == "f" else 0.05, bn == "f")   # B-045: Schnittfläche am Teil
	if bfx != null:
		bfx._jet(rb, world.origin, back, rng.randf_range(0.8, 1.4))
	var tree := rb.get_tree()
	for k in 8:
		tree.create_timer(0.18 * (k + 1), false).timeout.connect(_drip.bind(rb))
	tree.create_timer(FREEZE_S, false).timeout.connect(_freeze.bind(rb))
	tree.create_timer(LIFE_S, false).timeout.connect(_remove.bind(rb))
	return rb


# Parameter untypisiert: gebundene, inzwischen freigegebene Teile ergaben sonst „Cannot convert argument 1 from Object
# to Object“ bei jedem Zeitgeber (abschluss_099)
static func _drip(rb) -> void:
	if not is_instance_valid(rb) or rb.freeze or Effects.blood_fx == null:
		return
	Effects.blood_fx._floor_splat(rb.global_position, rng.randf_range(0.12, 0.28), "x_blood0%d" % rng.randi_range(1, 3), 2.5)


static func _freeze(rb) -> void:
	if is_instance_valid(rb):
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true


static func _remove(rb) -> void:
	_pieces.erase(rb)
	if is_instance_valid(rb):
		stats["removed"] += 1
		rb.queue_free()


static func _register(rb: RigidBody3D) -> void:
	_pieces = _pieces.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	_pieces.append(rb)
	while _pieces.size() > MAX_PIECES:
		_remove(_pieces[0])


static func piece_count() -> int:
	_pieces = _pieces.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	return _pieces.size()


static func pieces() -> Array:
	piece_count()
	return _pieces


## Blendet Knochen (samt Kindern) nach Animation/IK/Ragdoll aus: Skalierung ~0
class GoreMask extends SkeletonModifier3D:
	const TINY := 0.0001
	var bones := PackedInt32Array()

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in bones:
			sk.set_bone_pose_scale(b, Vector3.ONE * TINY)
