extends SkeletonModifier3D
## Linke Hand an die Waffe (Original: Zweihandmodus, hd2.exe 0x7B96C0/0x7B9750 mit Arm-IK 0x7A4140/0x7C02F0;
## docs/re_notes_weapons.md §3): Zwei-Knochen-IK der linken Armkette l (Oberarm) – m (Unterarm) – n (Hand), so dass
## der Hand-Dummy hw2 auf dem Waffen-Dummy LW (Griff der linken Hand) liegt. Die Handdrehung aus der Animation
## bleibt erhalten, die Ellbogenebene folgt der Animation (Pol = bisheriger Ellbogen). Läuft nach dem
## Anschlag-Modifier (WeaponAimModifier), damit der gedrehte Oberkörper berücksichtigt ist.
## Ausführung im Original nicht dekodiert [P]: analytische Lösung statt der Originalroutine.

var hand_r: Node3D              ## hw1 (rechte Hand, trägt die Waffe; Kind der BoneAttachment3D "j")
var hand_l: Node3D              ## hw2 (linke Hand, Kind der BoneAttachment3D "n")
var lw_in_hw1 := Transform3D.IDENTITY   ## Lage des Waffen-Dummys LW im Raum von hw1 (SoldierModel setzt sie je Bild)
var weight := 0.0               ## 0..1
var max_reach := 0.45           ## größerer Abstand hw2–LW: Haltung ist einhändig gemeint -> keine IK
var last_error := -1.0          ## Abstand hw2–LW nach der IK (m, Tests), -1 = inaktiv
var last_before := -1.0         ## Abstand vor der IK (m, Tests)
var _upper := -1
var _fore := -1
var _wrist := -1
var _r_hand := -1


func setup(sk: Skeleton3D, hw1: Node3D, hw2: Node3D) -> void:
	hand_r = hw1
	hand_l = hw2
	_upper = sk.find_bone("l")
	_fore = sk.find_bone("m")
	_wrist = sk.find_bone("n")
	_r_hand = sk.find_bone("j")


func _process_modification_with_delta(_delta: float) -> void:
	last_error = -1.0
	last_before = -1.0
	var sk := get_skeleton()
	if sk == null or hand_r == null or hand_l == null or weight <= 0.001 or _upper < 0 or _fore < 0 or _wrist < 0 or _r_hand < 0:
		return
	# alles im Skelettraum
	var lw: Vector3 = (sk.get_bone_global_pose(_r_hand) * hand_r.transform * lw_in_hw1).origin
	var pu := sk.get_bone_global_pose(_upper)
	var pf := sk.get_bone_global_pose(_fore)
	var pw := sk.get_bone_global_pose(_wrist)
	var hw2_off: Vector3 = hand_l.transform.origin
	var cur_hw2: Vector3 = pw * hw2_off
	last_before = cur_hw2.distance_to(lw)
	if last_before > max_reach:
		return
	var a_pos := pu.origin
	var b_pos := pf.origin
	var c_pos := pw.origin
	var wb := pw.basis.orthonormalized()
	var target := lw - wb * hw2_off          # Handgelenk so, dass hw2 auf LW liegt (Handdrehung unverändert)
	var la := a_pos.distance_to(b_pos)
	var lb := b_pos.distance_to(c_pos)
	var to_t := target - a_pos
	var d := clampf(to_t.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	if to_t.length() < 0.0001 or la < 0.001 or lb < 0.001:
		return
	var dir := to_t.normalized()
	# Ellbogen-Pol: bisherige Ellbogenlage senkrecht zur Zielachse
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
	var parent := sk.get_bone_parent(_upper)
	var pq := Quaternion.IDENTITY
	if parent >= 0:
		pq = sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	var w := clampf(weight, 0.0, 1.0)
	var lu := (pq.inverse() * new_ub).normalized()
	var lf := (new_ub.inverse() * new_fb).normalized()
	var lh := (new_fb.inverse() * hb).normalized()
	sk.set_bone_pose_rotation(_upper, sk.get_bone_pose_rotation(_upper).slerp(lu, w))
	sk.set_bone_pose_rotation(_fore, sk.get_bone_pose_rotation(_fore).slerp(lf, w))
	sk.set_bone_pose_rotation(_wrist, sk.get_bone_pose_rotation(_wrist).slerp(lh, w))
	last_error = (sk.get_bone_global_pose(_wrist) * hw2_off).distance_to(lw)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	if f.cross(t).length() < 0.00001:
		return Quaternion.IDENTITY
	return Quaternion(f, t)
