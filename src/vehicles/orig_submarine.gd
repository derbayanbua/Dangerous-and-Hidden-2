class_name OrigSubmarine
extends Vehicle
## Kleinst-U-Boot (Akteurtyp 20 „Submarine“, Modell la_minipon; NORWAY sub_1/sub_2, NORMANDY Miniponorka1/2) wie im
## Original (docs/re_notes_ai.md §5, hd2.exe, Klasse vtable 0x812650):
##   Sitze aus dem Modell: SEAT00 Fahrer (T7100), SEAT01 Mitfahrer (T7105).
##   Eingaben (0x5E1D90, je Bild, dt in s): Fahrt v += dt·Gas (Gas ±1), ohne Gas Abbau 1 m/s² bis 0, v ∈ [−6, 6] m/s;
##   Tauchen w += dt·Eingabe, ohne Eingabe Abbau 1 m/s² bis 0, w ∈ [−1, 1] m/s; Ruder r += dt·Lenkung·0,1,
##   ohne Lenkung Abbau 0,5/s bis 0, r ∈ [−0,5, 0,5] [B].
##   Bewegung (0x5E15E0): Lage += Vorwärts(waagrecht)·v·dt, Gier += dt·r·v·0,2 rad, Höhe += w·dt, höchstens bis zur
##   Höhe des Akteurparameters +0xD8 (NORWAY −1,0, NORMANDY −6,8; Standard 100) [B]; Kollision (0x5E1090): bei Treffer
##   bleibt das Boot stehen und das Ruder dreht vom Hindernis weg (±dt·v·0,1) [B Ablauf, P Seitenwahl].
## Kein Schadensmodell (keine Car-Klasse) → unzerstörbar [P]; Besatzung sitzt im Rumpf (unsichtbar).
## Steuerung im Nachbau: W/S Fahrt, A/D Ruder, Leertaste auftauchen, Hocken-Taste tauchen (Belegung [D]).

const V_MAX := 6.0              ## 0x810D94 / 0x81273C [B]
const ACC := 1.0                ## dt · Gas [B]
const W_MAX := 1.0              ## 0x80F524 [B]
const R_MAX := 0.5              ## 0x80F518 / 0x810184 [B]
const R_GAIN := 0.1             ## 0x80F550 [B]
const R_DECAY := 0.5            ## 0x80F518 [B]
const YAW_GAIN := 0.2           ## 0x80F540 [B]

var max_height := 100.0         ## Akteurparameter +0xD8 (Standard 0x42C80000 = 100) [B]
var speed := 0.0                ## +0xF4
var rudder := 0.0               ## +0xF8
var climb := 0.0                ## +0xFC


func _ready() -> void:
	super._ready()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	armored = true              # Besatzung im Rumpf unsichtbar (Vehicle._arm_seat)
	gravity_scale = 0.0


## Kein Radfahrwerk: das Boot bewegt sich kinematisch nach den Originalformeln
func _build_wheels() -> void:
	drive = null


func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	pass


## Motorklänge des Boots (+0xDC/+0xE0/+0xE4/+0xE8/+0xEC, 0x5DF600) noch nicht zugeordnet: still statt Kübelwagen-Satz
func _update_engine_sound() -> void:
	pass


func seat_name(idx: int) -> String:
	return OrigInteractive.text(7100, "Fahrer") if idx == 0 else OrigInteractive.text(7105, "Mitfahrer")


func seat_transform(idx: int) -> Transform3D:
	if idx < 0 or idx >= seats.size():
		return global_transform
	return seats[idx].global_transform


func on_bullet_hit(damage: float, shooter: Node) -> void:
	hit.emit(damage, shooter)


func on_explosion(damage: float, by: Node) -> void:
	hit.emit(damage, by)


func projectile_hit(_kind: int, damage: float, _at: Vector3, _dir: Vector3, by: Node) -> void:
	hit.emit(damage, by)


func explosion_at(_pos: Vector3, _radius: float, strength: float, by: Node) -> bool:
	hit.emit(strength, by)
	return true


## Zielhülle frei? Rumpfbox (85 %, leicht angehoben, damit Grundberührung nicht blockiert) gegen die Welt (Ebene 1)
func _blocked(dest: Transform3D) -> bool:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var cs := c as CollisionShape3D
			var box := BoxShape3D.new()
			var sz := (cs.shape as BoxShape3D).size
			box.size = sz * 0.85
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = dest * cs.transform * Transform3D(Basis(), Vector3.UP * sz.y * 0.1)
			q.collision_mask = 1
			q.exclude = [get_rid()]
			return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	return false


## Eingaben → Fahrt/Ruder/Tauchen (Original 0x5E1D90)
func _controls(delta: float, gas: float, steer: float, dive: float) -> void:
	if is_zero_approx(gas):
		speed = move_toward(speed, 0.0, delta * ACC)
	else:
		speed = clampf(speed + delta * gas * ACC, -V_MAX, V_MAX)
	if is_zero_approx(dive):
		climb = move_toward(climb, 0.0, delta * ACC)
	else:
		climb = clampf(climb + delta * dive, -W_MAX, W_MAX)
	if is_zero_approx(steer):
		rudder = move_toward(rudder, 0.0, delta * R_DECAY)
	else:
		rudder += delta * steer * R_GAIN
	rudder = clampf(rudder, -R_MAX, R_MAX)


func _physics_process(delta: float) -> void:
	_update_engine_sound()
	if _net_follow(delta):
		return
	var d := driver()
	var gas := 0.0
	var steer := 0.0
	var dive := 0.0
	if d != null and d.alive and d.is_player_controlled:
		gas = throttle
		steer = steer_input
		dive = vertical_input
	_controls(delta, gas, steer, dive)
	if is_zero_approx(speed) and is_zero_approx(climb):
		linear_velocity = Vector3.ZERO
		return
	# Bewegung (0x5E15E0): waagrechte Vorwärtsrichtung des Rumpfs (lokal +Z wie alle Fahrzeuge des Nachbaus)
	var fwd := global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var yaw := delta * rudder * speed * YAW_GAIN
	var step := fwd * speed * delta
	var new_y := minf(global_position.y + climb * delta, max_height)
	step.y = new_y - global_position.y
	if not _blocked(Transform3D(global_basis, global_position + step)):
		global_position += step
		if not is_zero_approx(yaw):
			global_rotate(Vector3.UP, yaw)
	else:
		# Hindernis: stehen bleiben, Ruder vom Hindernis wegdrehen (Original addiert/subtrahiert dt·v·0,1)
		rudder = clampf(rudder + delta * absf(speed) * R_GAIN * (1.0 if rudder >= 0.0 else -1.0), -R_MAX, R_MAX)
		speed = move_toward(speed, 0.0, delta * ACC)
	linear_velocity = step / maxf(delta, 0.0001)
	if d:
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 0.5
			Events.emit_noise(global_position, 30.0, d, d.team, &"engine")
