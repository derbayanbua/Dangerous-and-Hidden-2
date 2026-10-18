extends SkeletonModifier3D
## Bedienhaltung an Waffenstellungen (OrigInteractive.OrigEmplacement): Oberkörper folgt der Höhenrichtung,
## beide Hände an die Griff-Dummys des Stellungsmodells (RWS rechte Hand, LWS linke Hand; Kinder des Rohrs
## BARREL bzw. VERT, folgen damit Schwenken, Neigen und Rückstoß). Grundhaltung = Original-Clip aus
## TABLES\anim.sav ((mg42_stand, (mg42crouch, (mg42lie, (w97_*, (flaksed); docs/re_notes_weapons.md §11.
## Zwei-Knochen-IK wie LeftHandIK (Pol = Ellbogen der Animation); die Original-Routine ist nicht dekodiert [P].

var grip_r: Node3D               ## Griff rechte Hand (RWS)
var grip_l: Node3D               ## Griff linke Hand (LWS)
var hand_r: Node3D               ## hw1 (Kind der BoneAttachment3D „j“)
var hand_l: Node3D               ## hw2 (Kind der BoneAttachment3D „n“)
var pitch := 0.0                 ## Höhenrichtung der Waffe (rad, + = hoch) → Oberkörper neigt mit
var weight := 1.0
var max_reach := 0.9             ## weiter entfernte Griffe (Haltung passt nicht) → Hand bleibt in der Animation
var err_r := -1.0                ## Abstand Hand–Griff nach der IK (m, Tests), -1 = inaktiv
var err_l := -1.0
var lean := 0.0                  ## Vorbeuge der Wirbelsäule (rad, − = nach vorn/unten), Tests
var lean_target := 0.0
var _spine := -1
var _chest := -1
var _neck := -1
var _r := [-1, -1, -1]
var _l := [-1, -1, -1]


func setup(sk: Skeleton3D, hw1: Node3D, hw2: Node3D, gr: Node3D, gl: Node3D) -> void:
	hand_r = hw1
	hand_l = hw2
	grip_r = gr
	grip_l = gl
	_spine = sk.find_bone("b")
	_chest = sk.find_bone("d")
	_neck = sk.find_bone("e")
	_r = [sk.find_bone("h"), sk.find_bone("i"), sk.find_bone("j")]
	_l = [sk.find_bone("l"), sk.find_bone("m"), sk.find_bone("n")]


func _process_modification_with_delta(delta: float) -> void:
	err_r = -1.0
	err_l = -1.0
	var sk := get_skeleton()
	if sk == null or weight <= 0.001:
		return
	var w := clampf(weight, 0.0, 1.0)
	var inv := sk.global_transform.affine_inverse()
	# Rohr hoch → Kolben/Griffe tiefer: Wirbelsäule (Knochen b) so weit vorbeugen, bis beide Arme die Griffe
	# erreichen (kleinster Winkel, 0,05-rad-Schritte), geglättet; Rohr tief → aufrichten. Kopf blickt mit der Waffe.
	var want := _solve_lean(sk, inv) * w
	lean_target = want
	lean = move_toward(lean, want, maxf(delta, 0.016) * 2.5)
	_bend(sk, _spine, lean)
	_bend(sk, _chest, pitch * 0.15 * w)
	_bend(sk, _neck, pitch * 0.5 * w - lean)
	if is_instance_valid(grip_r) and is_instance_valid(hand_r):
		err_r = _arm(sk, _r, hand_r, inv * grip_r.global_position, w)
	if is_instance_valid(grip_l) and is_instance_valid(hand_l):
		err_l = _arm(sk, _l, hand_l, inv * grip_l.global_position, w)


## Kleinste Vorbeuge/Aufrichtung von b, bei der beide Schultern ihre Griffe erreichen (Armlänge × 0,97)
func _solve_lean(sk: Skeleton3D, inv: Transform3D) -> float:
	if _spine < 0 or not is_instance_valid(grip_r) or not is_instance_valid(grip_l):
		return 0.0
	var r0 := sk.get_bone_pose_rotation(_spine)
	var gr := inv * grip_r.global_position
	var gl := inv * grip_l.global_position
	var best := 0.0
	var best_over := INF
	for i in 29:
		var a: float = 0.05 * float((i + 1) >> 1) * (-1.0 if i % 2 == 1 else 1.0)
		sk.set_bone_pose_rotation(_spine, r0)
		_bend(sk, _spine, a)
		var over := maxf(_overreach(sk, _r, hand_r, gr), _overreach(sk, _l, hand_l, gl))
		if over <= 0.0:
			best = a
			break
		if over < best_over - 0.005:
			best_over = over
			best = a
	sk.set_bone_pose_rotation(_spine, r0)
	return best


## Wie weit der Griff außerhalb der Armreichweite liegt (m, ≤ 0 = erreichbar)
static func _overreach(sk: Skeleton3D, chain: Array, hand: Node3D, target_pt: Vector3) -> float:
	var up: int = chain[0]
	var fo: int = chain[1]
	var wr: int = chain[2]
	if up < 0 or fo < 0 or wr < 0 or not is_instance_valid(hand):
		return 0.0
	var a := sk.get_bone_global_pose(up).origin
	var reach := a.distance_to(sk.get_bone_global_pose(fo).origin) + sk.get_bone_global_pose(fo).origin.distance_to(sk.get_bone_global_pose(wr).origin) \
		+ hand.transform.origin.length()
	return a.distance_to(target_pt) - reach * 0.97


## Knochen um die Querachse der Figur (Skelett +X) drehen
static func _bend(sk: Skeleton3D, bone: int, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.0001:
		return
	var g := sk.get_bone_global_pose(bone).basis.orthonormalized().get_rotation_quaternion()
	var ng := Quaternion(Vector3.RIGHT, angle) * g
	var parent := sk.get_bone_parent(bone)
	var pq := Quaternion.IDENTITY
	if parent >= 0:
		pq = sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, (pq.inverse() * ng).normalized())


## Zwei-Knochen-IK Oberarm–Unterarm–Hand, so dass der Hand-Dummy auf target (Skelettraum) liegt
static func _arm(sk: Skeleton3D, chain: Array, hand: Node3D, target_pt: Vector3, w: float) -> float:
	var up: int = chain[0]
	var fo: int = chain[1]
	var wr: int = chain[2]
	if up < 0 or fo < 0 or wr < 0:
		return -1.0
	var pu := sk.get_bone_global_pose(up)
	var pf := sk.get_bone_global_pose(fo)
	var pw := sk.get_bone_global_pose(wr)
	var off: Vector3 = hand.transform.origin
	if (pw * off).distance_to(target_pt) > 0.9:
		return (pw * off).distance_to(target_pt)
	var a_pos := pu.origin
	var b_pos := pf.origin
	var c_pos := pw.origin
	var wb := pw.basis.orthonormalized()
	var target := target_pt - wb * off
	var la := a_pos.distance_to(b_pos)
	var lb := b_pos.distance_to(c_pos)
	var to_t := target - a_pos
	if to_t.length() < 0.0001 or la < 0.001 or lb < 0.001:
		return -1.0
	var d := clampf(to_t.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := to_t.normalized()
	var bend := (b_pos - a_pos) - dir * (b_pos - a_pos).dot(dir)
	if bend.length() < 0.0001:
		bend = dir.cross(Vector3.UP).cross(dir)
	bend = bend.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var new_b := a_pos + dir * (cos_a * la) + bend * (sqrt(1.0 - cos_a * cos_a) * la)
	var new_c := a_pos + dir * d
	var q1 := _arc(b_pos - a_pos, new_b - a_pos)
	var q2 := _arc(q1 * (c_pos - b_pos), new_c - new_b)
	var ub := pu.basis.orthonormalized().get_rotation_quaternion()
	var fb := pf.basis.orthonormalized().get_rotation_quaternion()
	var hb := wb.get_rotation_quaternion()
	var new_ub := q1 * ub
	var new_fb := q2 * q1 * fb
	var parent := sk.get_bone_parent(up)
	var pq := Quaternion.IDENTITY
	if parent >= 0:
		pq = sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	sk.set_bone_pose_rotation(up, sk.get_bone_pose_rotation(up).slerp((pq.inverse() * new_ub).normalized(), w))
	sk.set_bone_pose_rotation(fo, sk.get_bone_pose_rotation(fo).slerp((new_ub.inverse() * new_fb).normalized(), w))
	sk.set_bone_pose_rotation(wr, sk.get_bone_pose_rotation(wr).slerp((new_fb.inverse() * hb).normalized(), w))
	return (sk.get_bone_global_pose(wr) * off).distance_to(target_pt)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	if f.cross(t).length() < 0.00001:
		return Quaternion.IDENTITY
	return Quaternion(f, t)
