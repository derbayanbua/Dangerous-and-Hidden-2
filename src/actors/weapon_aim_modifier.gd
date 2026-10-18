class_name WeaponAimModifier
extends SkeletonModifier3D
## Richtet beim Zielen den Oberkörper (Knochen "b") der Original-Figur so aus, dass der Lauf der Waffe in
## der Hand (hw1, Lauf = +X von hw1) in die gewünschte Richtung zeigt (Blickrichtung inkl. Nickwinkel).
## Die Anschlag-Haltungen des Originals (z. B. !!zbp04a) zeigen relativ zur Figur schräg nach links; die
## gemessene Gierabweichung (yaw_error) nutzt SoldierModel, um die Figur im Stand einzudrehen
## (Anschlag mit vorgestellter linker Schulter). [P] Original-Aimsystem nicht dekodiert.

var hand: Node3D                  ## Dummy hw1 (Kind der BoneAttachment3D "j")
var want_dir := Vector3.ZERO      ## gewünschte Laufrichtung (Welt); ZERO = keine Korrektur
var weight := 0.0                 ## 0..1 (weich ein-/ausblenden)
var yaw_error := 0.0              ## Gierwinkel (rad, um Welt-Y) zwischen Lauf und Wunsch vor der Korrektur
var max_yaw := deg_to_rad(80.0)
var kick := 0.0                   ## Rückstoß (rad): hebt den Lauf nach dem Ausrichten (SoldierModel.recoil)
var _spine := -1
var _hand_bone := -1


func setup(sk: Skeleton3D, hw1: Node3D) -> void:
	hand = hw1
	_spine = sk.find_bone("b")
	_hand_bone = sk.find_bone("j")


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or hand == null or _spine < 0 or _hand_bone < 0 or weight <= 0.001 or want_dir == Vector3.ZERO:
		yaw_error = 0.0
		return
	var hand_g: Transform3D = sk.global_transform * sk.get_bone_global_pose(_hand_bone) * hand.transform
	var cur := hand_g.basis.x.normalized()
	var want := want_dir.normalized()
	var ch := Vector2(cur.x, cur.z)
	var wh := Vector2(want.x, want.z)
	var yaw := 0.0
	if ch.length() > 0.05 and wh.length() > 0.05:
		# Drehung um +Y um yaw bildet (x, z) auf (x cos + z sin, -x sin + z cos) ab = 2D-Drehung um -yaw
		yaw = -ch.angle_to(wh)
	yaw_error = yaw
	yaw = clampf(yaw, -max_yaw, max_yaw)
	var qy := Quaternion(Vector3.UP, yaw)
	var cur2 := qy * cur
	var qp := Quaternion(cur2, want) if cur2.cross(want).length() > 0.0001 else Quaternion.IDENTITY
	var q := Quaternion.IDENTITY.slerp(qp * qy, clampf(weight, 0.0, 1.0))
	if absf(kick) > 0.0001:
		var axis := want.cross(Vector3.UP)
		if axis.length() > 0.01:
			q = Quaternion(axis.normalized(), kick * clampf(weight, 0.0, 1.0)) * q
	# Weltdrehung q um den Knochenursprung -> lokale Knochendrehung
	var sq := sk.global_basis.orthonormalized().get_rotation_quaternion()
	var qs := sq.inverse() * q * sq
	var parent := sk.get_bone_parent(_spine)
	var pq := Quaternion.IDENTITY
	if parent >= 0:
		pq = sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	var local := sk.get_bone_pose_rotation(_spine)
	sk.set_bone_pose_rotation(_spine, ((pq.inverse() * qs * pq) * local).normalized())
