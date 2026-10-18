class_name Vehicle
extends VehicleBody3D
## Fahrzeug (Original belegt: HUMAN_Drive, HUMAN_BoardVehicle, tables\tyres.bin).
## Fahrphysik: VehicleDrive (vehicle_drive.gd, eigenes Raycast-Fahrwerk – bewusst modern statt Original, Vorgabe
## Auftraggeber); Kennwerte aus orig_cache/<m>/vehicles.json (drive_data). Sitze: 0 = Fahrer, 1..n Mitfahrer.
## Insassen bleiben Soldaten mit aktiven Trefferzonen (sie können beschossen
## werden); Mitfahrer dürfen feuern. Laufender Motor ist weit hörbar.
## Übungseinsätze: Kübelwagen aus Grundkörpern (PLATZHALTER-MODELL).
## Originalmodelle (docs/re_notes_ai.md §3): Sitze = Frames SEAT00..SEATnn (00 Fahrer), Waffensitze mit HORTnn
## (Drehung um die Hochachse = Turm/Lafette), VERTnn (Höhenrichtung), BARRELnn_xx (Rohr), SHDUM (Mündung). Waffen
## der Sitze aus der Munition im items.dat-Inventar des Fahrzeugs (z. B. Tiger: 213 -> KwK 40, 211 -> Tank MG 34):
## Kanone an den Sitz mit Hauptvisier (CAMERAFPVMain), Maschinengewehre an die übrigen Waffensitze [O]. Panzer
## (Kanone vorhanden) sind gepanzert: Handwaffen wirkungslos, Besatzung unsichtbar und nur über das Fahrzeug
## verwundbar [E]. Turmdrehung 25°/s, Höhenrichtung −10°…+20° [E – Originalwerte nicht dekodiert].

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

## Fahrphysik (vehicle_drive.gd). drive_data = Eintrag aus orig_cache/<m>/vehicles.json, drive_model = Modellname
## für die Typbestimmung (Pkw/Lkw/Krad/Halbkette/Kette); beides vor add_child setzen.
var drive: VehicleDrive
var drive_data: Dictionary = {}
var drive_model := ""
var _net_xf := Transform3D()
var _net_vel := Vector3.ZERO
var _net_t := -1.0               ## Zeit seit der letzten Netz-Lage (Fahrer auf einem anderen Rechner); −1 = aus
var _runover_t := 0.0
var _crash_t := 0.0

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

## Original-Fahrzeugklänge (Dateinamen aus dem actors.bin-Parameterblock, z. B. kubel_on/_of/_0.._4/_r,
## tr_gear*, carcrx*). Übungseinsätze: Kübelwagen-Satz (Ersatz). Zuordnung Datei -> Zustand über die
## Namensendungen; Drehzahlstufen nach Geschwindigkeit und Tonhöhe sind Annahmen (Block nicht dekodiert).
const DEFAULT_SOUNDS := ["kubel_on.wav", "kubel_of.wav", "bad_car.wav", "kubel_1.wav", "kubel_2.wav",
	"kubel_3.wav", "kubel_4.wav", "kubel_r.wav", "kubel_0.wav", "carcrx1_a.wav"]
var sound_files: Array = []
var _snd := {}                    ## on, off, bad, idle, levels[], reverse, crash[]
var _engine: AudioStreamPlayer3D
var _engine_file := ""
var _engine_on := false
var _bad_for: Node = null

## Original-Fahrzeuge: Munition aus dem items.dat-Inventar (Bordwaffen), Panzerung, Waffensitze
var ammo_items: Array = []
var armored := false
var turrets := {}                 ## Sitz -> Dictionary (hort, vert, muzzle, axis, base_h, base_v, yaw, pitch, weapon …)
var _saved_weapons := {}          ## Soldat -> [Waffen, Platz]
const TURRET_SPEED := 0.436       ## rad/s (25°/s) [E]
const PITCH_MIN := -0.17          ## −10° [E]
const PITCH_MAX := 0.35           ## +20° [E]
signal hit(damage: float, by: Node)   ## Treffer (Originalskript OnHit)


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("persistent")
	collision_layer = 1
	# nur Welt: Soldaten blockieren das Fahrzeug nicht wie eine Wand, sie werden erfasst/abgedrängt (_check_runover)
	collision_mask = 1
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
	_setup_orig_seats()


# --- Originalsitze und Bordwaffen ----------------------------------------------------

func _setup_orig_seats() -> void:
	if custom_visual == null:
		return
	var found := {}
	for n in custom_visual.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_upper()
		if nm.begins_with("SEAT") and nm.length() == 6 and nm.substr(4).is_valid_int():
			found[int(nm.substr(4))] = n
	if found.is_empty():
		return
	var keys: Array = found.keys()
	keys.sort()
	for s in seats:
		s.queue_free()
	seats.clear()
	for k in keys:
		seats.append(found[k])       # Index = Originalsitz (HUMAN_BoardVehicle(Fahrzeug, 1, Sitz))
	occupants = []
	occupants.resize(seats.size())
	# Bordwaffen aus der Munition
	var cannons: Array = []
	var guns: Array = []
	var counts := {}
	for a in ammo_items:
		counts[int(a)] = int(counts.get(int(a), 0)) + 1
	for a in counts:
		var wd := OrigInteractive.heavy_weapon(OrigInteractive.weapon_for_ammo(int(a)))
		if wd == null:
			continue
		var w := Weapon.new(wd, false)
		w.in_mag = wd.magazine_size
		w.reserve = wd.magazine_size * maxi(int(counts[a]) - 1, 0)
		if wd.action == WeaponData.Action.ROCKET and wd.shot_interval() >= 1.0:
			cannons.append(w)
		else:
			guns.append(w)
	armored = not cannons.is_empty()
	var main_seat := -1
	for i in seats.size():
		var t := _turret_of(seats[i])
		if t.is_empty():
			continue
		turrets[i] = t
		if seats[i].find_child("CAMERAFPVMain", true, false) != null:
			main_seat = i
	if main_seat < 0 and not cannons.is_empty() and not turrets.is_empty():
		main_seat = turrets.keys().max()
	var gi := 0
	for i in turrets:
		if i == main_seat and not cannons.is_empty():
			turrets[i]["weapon"] = cannons[0]
		elif not guns.is_empty():
			turrets[i]["weapon"] = guns[gi % guns.size()]
			gi += 1
		elif not cannons.is_empty():
			turrets[i]["weapon"] = cannons[0]


func _turret_of(seat: Node3D) -> Dictionary:
	var hort: Node3D = null
	var vert: Node3D = null
	var barrel: Node3D = null
	var muzzle: Node3D = null
	for n in seat.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_upper()
		if hort == null and nm.begins_with("HORT"):
			hort = n
		elif vert == null and nm.begins_with("VERT"):
			vert = n
		elif barrel == null and nm.begins_with("BARREL"):
			barrel = n
		elif muzzle == null and nm.begins_with("SHDUM"):
			muzzle = n
	if hort == null and vert == null:
		return {}
	var pivot: Node3D = vert if vert else hort
	var axis := Vector3.FORWARD
	if barrel and barrel.position.length() > 0.05 and barrel.get_parent() == pivot:
		axis = barrel.position.normalized()
	return {"hort": hort, "vert": vert, "barrel": barrel, "muzzle": muzzle, "axis": axis,
		"base_h": hort.transform if hort else Transform3D(), "base_v": vert.transform if vert else Transform3D(),
		"yaw": 0.0, "pitch": 0.0, "weapon": null, "ysign": 0.0, "psign": 0.0}


## Weltrichtung des Rohrs eines Waffensitzes
func turret_dir(idx: int) -> Vector3:
	var t: Dictionary = turrets.get(idx, {})
	if t.is_empty():
		return global_basis.z
	var pivot: Node3D = t["vert"] if t["vert"] else t["hort"]
	return (pivot.global_basis * (t["axis"] as Vector3)).normalized()


func muzzle_point(idx: int) -> Vector3:
	var t: Dictionary = turrets.get(idx, {})
	if t.is_empty():
		return seats[idx].global_position
	if t["muzzle"]:
		return (t["muzzle"] as Node3D).global_position
	if t["barrel"]:
		return (t["barrel"] as Node3D).global_position + turret_dir(idx) * 1.0
	return (t["vert"] if t["vert"] else t["hort"]).global_position + turret_dir(idx) * 1.0


static func _yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _apply_turret(t: Dictionary) -> void:
	if t["hort"]:
		var bh: Transform3D = t["base_h"]
		(t["hort"] as Node3D).transform = Transform3D(Basis(Vector3.UP, t["yaw"]) * bh.basis, bh.origin)
	if t["vert"]:
		var bv: Transform3D = t["base_v"]
		var pitch_axis := Vector3.RIGHT
		(t["vert"] as Node3D).transform = Transform3D(bv.basis * Basis(pitch_axis, t["pitch"]), bv.origin) if t["hort"] \
			else Transform3D(Basis(Vector3.UP, t["yaw"]) * bv.basis * Basis(pitch_axis, t["pitch"]), bv.origin)


## Turm folgt der Blickrichtung des Schützen (begrenzte Drehgeschwindigkeit); der Blick des Schützen wird auf die
## tatsächliche Rohrrichtung zurückgesetzt, damit Schuss und Rohr übereinstimmen
func _update_turrets(delta: float) -> void:
	for i in turrets:
		var t: Dictionary = turrets[i]
		var o = occupants[i] if i < occupants.size() else null
		if not is_instance_valid(o) or not (o as Soldier).alive:
			continue
		var s := o as Soldier
		# Drehsinn einmalig numerisch bestimmen (Modelle können gespiegelt sein)
		if t["ysign"] == 0.0:
			var y0 := _yaw_of(turret_dir(i))
			t["yaw"] = 0.1
			_apply_turret(t)
			t["ysign"] = signf(angle_difference(y0, _yaw_of(turret_dir(i)))) if not is_zero_approx(angle_difference(y0, _yaw_of(turret_dir(i)))) else 1.0
			t["yaw"] = 0.0
			var p0 := turret_dir(i).y
			t["pitch"] = 0.1
			_apply_turret(t)
			t["psign"] = 1.0 if turret_dir(i).y >= p0 else -1.0
			t["pitch"] = 0.0
			_apply_turret(t)
		var cur := turret_dir(i)
		var dyaw := angle_difference(_yaw_of(cur), s.look_yaw)
		t["yaw"] = float(t["yaw"]) + clampf(dyaw, -TURRET_SPEED * delta, TURRET_SPEED * delta) * float(t["ysign"])
		var dp := s.look_pitch - asin(clampf(cur.y, -1.0, 1.0))
		var ps := float(t["psign"])
		var rel := float(t["pitch"]) * ps + clampf(dp, -TURRET_SPEED * delta, TURRET_SPEED * delta)
		t["pitch"] = clampf(rel, PITCH_MIN, PITCH_MAX) * ps
		_apply_turret(t)
		var nd := turret_dir(i)
		s.look_yaw = _yaw_of(nd)
		s.look_pitch = asin(clampf(nd.y, -1.0, 1.0))
		s.has_aim_point = false


## Waffensitz besetzen: Bordwaffe in die Hand (wie Waffenstellungen), im Panzer Besatzung verbergen
func _arm_seat(s: Soldier, idx: int) -> void:
	var t: Dictionary = turrets.get(idx, {})
	if not t.is_empty() and t.get("weapon") != null:
		_saved_weapons[s] = [s.weapons.duplicate(), s.current_slot]
		var arr: Array[Weapon] = [t["weapon"], null, null, null, null]
		s.weapons = arr
		s.current_slot = 0
		s._on_weapon_switched()
		var d := turret_dir(idx)
		s.look_yaw = _yaw_of(d)
		s.look_pitch = asin(clampf(d.y, -1.0, 1.0))
	if armored:
		_hide_crew(s, true)


func _disarm_seat(s: Soldier) -> void:
	if _saved_weapons.has(s):
		var sv: Array = _saved_weapons[s]
		_saved_weapons.erase(s)
		var arr: Array[Weapon] = []
		for x in sv[0]:
			arr.append(x)
		s.weapons = arr
		s.current_slot = int(sv[1])
		s._on_weapon_switched()
	_hide_crew(s, false)


func _hide_crew(s: Soldier, hide: bool) -> void:
	if s.model:
		s.model.visible = not hide
	for hb in s.find_children("*", "Hitbox", true, false):
		(hb as Hitbox).collision_layer = 0 if hide or not s.alive else Hitbox.LAYER
	if s.model and not s.model.orig_zones.is_empty() and not hide:
		s.model._set_puppet_hitboxes(false)     # Original-Figur: nur die Gelenkzonen (humanzones) treffen


func seat_weapon(idx: int) -> Weapon:
	return turrets.get(idx, {}).get("weapon")


func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	if custom_visual:
		add_child(custom_visual)
		# Kollision trägt allein der Fahrzeugkörper (Box); eingebettete Körper des Modells würden eigene Geschosse abfangen
		for co in custom_visual.find_children("*", "CollisionObject3D", true, false):
			(co as CollisionObject3D).collision_layer = 0
			(co as CollisionObject3D).collision_mask = 0
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


## Fahrwerk: Räder aus dem Originalmodell (DWHLnn/DWHRnn) bzw. Platzhalter-Räder, Kennwerte aus drive_data
func _build_wheels() -> void:
	drive = VehicleDrive.new()
	var box_c := Vector3.ZERO
	for c in get_children():
		if c is CollisionShape3D:
			box_c = (c as CollisionShape3D).position
			break
	var model := drive_model if drive_model != "" else vehicle_name
	drive.setup(self, drive_data, model, custom_visual, _size, Vector3(box_c.x, 0.0, box_c.z))
	drive.impact_cb = _on_impact
	can_sleep = true


## Physik je Schritt (Federn, Reifen, Motor) – nur wenn der Körper simuliert wird (nicht eingefroren)
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if drive:
		drive.integrate(state)


## Harter Stoß (Δv je Physikschritt): Schaden, Aufprallklang; Panzer nehmen kaum Schaden
func _on_impact(dv: float, other: Object) -> void:
	if wrecked or _crash_t > 0.0:
		return
	_crash_t = 0.4
	var crash: Array = _snd.get("crash", [])
	if not crash.is_empty():
		OrigAudio.play_file(String(crash[randi() % crash.size()]), global_position, 5.0, 90.0, clampf(dv / 12.0, 0.3, 1.0), self)
	var dmg := pow(maxf(dv - 5.0, 0.0), 1.5) * 4.0 * (0.1 if armored or drive.kind == VehicleDrive.Kind.TANK else 1.0)
	if dmg > 0.0:
		health -= dmg
		hit.emit(dmg, other if other is Node else null)
		if health <= 0.0:
			explode(driver())
	for o in occupants:
		if is_instance_valid(o) and dv > 9.0:
			(o as Soldier).apply_hit((dv - 9.0) * 6.0, &"torso", null, Vector3.UP)


## Fußgänger vor dem fahrenden Fahrzeug: ab ~12 km/h überfahren (Schaden), sonst seitlich abgedrängt
func _check_runover(delta: float) -> void:
	_runover_t -= delta
	if _runover_t > 0.0 or linear_velocity.length() < 1.0 or freeze:
		return
	_runover_t = 0.1
	var cs: CollisionShape3D = null
	for c in get_children():
		if c is CollisionShape3D:
			cs = c
			break
	if cs == null:
		return
	var box := BoxShape3D.new()
	box.size = _size + Vector3(0.5, 0.4, 1.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = global_transform * cs.transform
	q.collision_mask = 1 << 1
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var s := r.get("collider") as Soldier
		if s == null or not s.alive or s.vehicle != null:
			continue
		var away := s.global_position - global_position
		away.y = 0.0
		var rel := linear_velocity.dot(away.normalized()) if away.length() > 0.01 else linear_velocity.length()
		if rel > 3.5:
			var by: Node = driver()
			s.apply_hit((rel - 3.0) * 14.0, &"torso", by, linear_velocity.normalized())
		var side := global_basis.x * (1.0 if to_local(s.global_position).x >= 0.0 else -1.0)
		s.global_position += side * clampf(rel, 0.5, 3.0) * 0.1


## Lage vom Fahrer-Rechner (Net._veh): Fahrzeug folgt kinematisch, Physik ruht solange
func net_apply(xf: Transform3D, vel: Vector3) -> void:
	_net_xf = xf
	_net_vel = vel
	_net_t = 0.0


func _net_follow(delta: float) -> bool:
	if _net_t < 0.0:
		return false
	_net_t += delta
	if _net_t > 0.6:
		_net_t = -1.0
		freeze = false           # kein Fahrer mehr gemeldet: Physik übernimmt wieder
		return false
	if not freeze:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	var goal := Transform3D(_net_xf.basis, _net_xf.origin + _net_vel * minf(_net_t, 0.25))
	global_transform = global_transform.interpolate_with(goal, clampf(delta * 12.0, 0.0, 1.0)) \
		if global_position.distance_to(goal.origin) < 4.0 else goal
	linear_velocity = _net_vel
	if drive:
		drive.speed = _net_vel.dot(global_basis.z)
	return true


## Verfolgerkamera: Drehpunkt über der Fahrzeugmitte, Abstand nach Fahrzeuggröße
func chase_pivot() -> Vector3:
	var c := Vector3.ZERO
	for ch in get_children():
		if ch is CollisionShape3D:
			c = (ch as CollisionShape3D).position
			break
	return global_transform * Vector3(c.x, 0.6 + _size.y + 0.9, c.z)


func chase_distance() -> float:
	return clampf(_size.z * 1.25 + 2.5, 5.5, 12.0)


## Blickrichtung (Soldaten-Yaw) entlang der Fahrzeugfront
func chase_yaw() -> float:
	var f := global_basis.z
	return atan2(-f.x, -f.z)


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


func board(s: Soldier, prefer_driver := false, seat := -1) -> bool:
	if wrecked or s.vehicle != null or not s.alive:
		return false
	if not Net.vehicles_allowed():
		return false        # Mehrspieler-Regel „Fahrzeuge erlauben“ (allowvehicles) aus
	var idx := -1
	if seat >= 0 and seat < occupants.size() and not is_instance_valid(occupants[seat]):
		idx = seat          # Original HUMAN_BoardVehicle(Fahrzeug, 1, Sitz)
	elif prefer_driver and driver() == null:
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
	_arm_seat(s, idx)
	return true


func leave(s: Soldier) -> void:
	var idx := occupants.find(s)
	if idx < 0:
		return
	occupants[idx] = null
	_disarm_seat(s)
	var lp := to_local(seats[idx].global_position)
	var side := -1.0 if lp.x < 0 else 1.0
	var half := maxf(_size.x * 0.5 + 0.8, 1.6)
	var out := global_transform * Vector3(side * half, 0.4, lp.z)
	s.exit_vehicle(out)


## Platz im Fahrzeug wechseln (vereinfachte Steuerung: Mausrad wählt, Linksklick bestätigt)
func switch_seat(s: Soldier, idx: int) -> bool:
	var cur := occupants.find(s)
	if cur < 0 or idx < 0 or idx >= occupants.size() or idx >= seats.size() or idx == cur:
		return false
	if is_instance_valid(occupants[idx]):
		return false
	occupants[cur] = null
	_disarm_seat(s)
	occupants[idx] = s
	s.seat_index = idx
	_arm_seat(s, idx)
	if cur == 0:
		throttle = 0.0
		steer_input = 0.0
	return true


func seat_name(idx: int) -> String:
	var w := seat_weapon(idx)
	if w:
		return w.data.display_name
	return "Fahrer" if idx == 0 else ("Beifahrer" if idx == 1 else "Rücksitz %d" % (idx - 1))


func leave_all() -> void:
	for o in occupants.duplicate():
		if is_instance_valid(o):
			leave(o)


func seat_transform(idx: int) -> Transform3D:
	if idx < 0 or idx >= seats.size():
		return global_transform
	# Panzer-Waffensitz: Schütze (unsichtbar) sitzt an der Mündung, damit Schüsse aus dem Rohr kommen
	if armored and turrets.has(idx) and turrets[idx].get("weapon") != null:
		var d := turret_dir(idx)
		return Transform3D(seats[idx].global_basis, muzzle_point(idx) + d * 0.6 + Vector3.DOWN * 0.5)
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


## HUMAN_Drive: zum Punkt fahren (km/h). Kinematisch, damit die Skriptfahrt verlässlich ist.
func drive_to(goal: Vector3, kmh: float) -> void:
	drive_path([goal], kmh)


## Fahrt über eine Punktfolge (Original-Fahrzeugnetz aus check2.bin, docs/re_notes_drive.md):
## Geschwindigkeit kmh × 0,28 m/s, negative kmh = rückwärts; fertig bei < 2 m am letzten Punkt
## oder wenn die Fahrt 5 s lang nicht vorankommt
var _drive_path: Array = []
var _drive_reverse := false
var _stuck_t := 0.0
var _best_dist := INF


var _recover_t := 0.0


## Skriptfahrt fährt physikalisch (VehicleDrive.ai_control: Zielpunkt mit Vorausschau, Kurven-/Zielbremsung);
## Festhängen: nach 2,5 s ohne Annäherung kurze Rückwärts-Ausweichphase (Original 3 s-Phase [P]), nach 5 s wird der
## Routenpunkt übersprungen, beim letzten endet die Fahrt (Original FUN_00578790).
func drive_path(points: Array, kmh: float) -> void:
	if fuel <= 0.0 or wrecked or points.is_empty():
		return
	script_driving = true
	freeze = false
	sleeping = false
	_drive_path = points.duplicate()
	_drive_goal = _drive_path.pop_front()
	_drive_reverse = kmh < 0.0
	_drive_speed = maxf(absf(kmh) * 0.28, 1.5)
	_stuck_t = 0.0
	_best_dist = INF
	_recover_t = 0.0


func drive_done() -> bool:
	return not script_driving or not _drive_goal.is_finite() or wrecked


func stop_drive() -> void:
	_drive_goal = Vector3.INF
	_drive_path.clear()
	_drive_speed = 0.0


func _script_drive(delta: float) -> void:
	if not _drive_goal.is_finite() or driver() == null:
		drive.release_controls(true)
		return
	var dirsign := -1.0 if _drive_reverse else 1.0
	var to := _drive_goal - global_position
	to.y = 0.0
	var rest := to.length()
	# Punkt erreicht (< 2 m, Zwischenpunkte großzügiger) oder knapp überfahren (Original: Skalarprodukt ≥ 0)
	var heading := global_basis.z * dirsign
	heading.y = 0.0
	var passed := rest < 5.0 and to.dot(heading) < 0.0 and not _drive_path.is_empty()
	if rest < (2.0 if _drive_path.is_empty() else 3.5) or passed:
		_next_drive_point()
		return
	# festgefahren: Ausweichphase, nach 5 s ohne Annäherung Punkt überspringen (letzter Punkt: Fahrt beendet)
	if rest < _best_dist - 0.2:
		_best_dist = rest
		_stuck_t = 0.0
	else:
		_stuck_t += delta
		if _stuck_t > 5.0:
			_next_drive_point()
			return
		if _stuck_t > 2.5 and _recover_t <= 0.0 and absf(drive.speed) < 0.4:
			_recover_t = 1.6
	# Vorausschaupunkt auf der Route (glatte Kurven statt Zickzack über die Netzknoten)
	var look := clampf(4.0 + absf(drive.speed) * 0.7, 4.0, 16.0)
	var target := _drive_goal
	var want := _drive_speed
	if not _drive_path.is_empty():
		var nxt: Vector3 = _drive_path[0]
		var seg := nxt - _drive_goal
		seg.y = 0.0
		if rest < look and seg.length() > 0.1:
			target = _drive_goal + seg.normalized() * minf(look - rest, seg.length())
		# Kurve am nächsten Punkt: rechtzeitig auf Kurvengeschwindigkeit bremsen
		var bend := to.normalized().angle_to(seg.normalized()) if seg.length() > 0.1 else 0.0
		var v_corner := lerpf(_drive_speed, 3.5, clampf((bend - 0.3) / 1.2, 0.0, 1.0))
		want = minf(want, sqrt(v_corner * v_corner + 2.0 * 2.5 * maxf(rest - 3.0, 0.0)))
	else:
		want = minf(want, sqrt(2.0 * 2.5 * maxf(rest - 1.2, 0.0)) + 0.6)
	# Hindernis voraus (Gebäude, Fahrzeuge, Soldaten): anhalten statt durchfahren
	var space := get_world_3d().direct_space_state
	var stop_d := _size.z * 0.5 + 1.5 + drive.speed * drive.speed / 6.0
	var from := global_position + global_basis.y * 1.2
	var ahead := PhysicsRayQueryParameters3D.create(from, from + heading.normalized() * stop_d, 1 | (1 << 1), [get_rid()])
	var ah := space.intersect_ray(ahead)
	if not ah.is_empty() and (ah["normal"] as Vector3).y < 0.6 and _recover_t <= 0.0:
		want = 0.0
	if _recover_t > 0.0:
		_recover_t -= delta
		var back := global_position - heading.normalized() * 6.0 + global_basis.x * signf(to_local(_drive_goal).x) * -4.0
		drive.ai_control(back, -2.5 * dirsign, delta)
	else:
		drive.ai_control(target, want * dirsign, delta)
	sleeping = false
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.5
		Events.emit_noise(global_position, 60.0, driver(), driver().team, &"engine")


func _next_drive_point() -> void:
	_drive_goal = _drive_path.pop_front() if not _drive_path.is_empty() else Vector3.INF
	_best_dist = INF
	_stuck_t = 0.0
	_recover_t = 0.0
	if not _drive_goal.is_finite():
		drive.release_controls(true)


func _physics_process(delta: float) -> void:
	_update_engine_sound()
	if not turrets.is_empty() and not wrecked:
		_update_turrets(delta)
	_crash_t = maxf(_crash_t - delta, 0.0)
	if drive:
		drive.update_visuals()
	if _net_follow(delta):
		return
	if wrecked:
		drive.release_controls(true)
		return
	_check_runover(delta)
	var d := driver()
	if d != null and d.alive and d.is_player_controlled:
		script_driving = false          # Spieler übernimmt auch ein skriptgefahrenes Fahrzeug
	if script_driving:
		_script_drive(delta)
		return
	if d == null or not d.alive:
		drive.release_controls(true)
		return
	if not d.is_player_controlled:
		throttle = 0.0
		steer_input = 0.0
	elif freeze:
		freeze = false          # Spieler übernimmt ein bisher geparktes Fahrzeug
	if fuel <= 0.0:
		throttle = 0.0
	if d.is_player_controlled:
		drive.set_player_input(throttle, steer_input, handbrake)
	else:
		drive.release_controls(true)    # KI am Steuer ohne Skriptfahrt: steht mit Feststellbremse
	if absf(throttle) > 0.01 or absf(steer_input) > 0.01:
		sleeping = false
	# Motorgeräusch für das Gehör der Gegner
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.5
		Events.emit_noise(global_position, 45.0 + absf(throttle) * 35.0, d, d.team, &"engine")


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


# --- Klang (Original-Fahrzeugklänge) -------------------------------------------------

func _classify_sounds() -> void:
	var files: Array = sound_files if not sound_files.is_empty() else DEFAULT_SOUNDS
	var levels: Array = []
	var crash: Array = []
	_snd = {"on": "", "off": "", "bad": "", "idle": "", "reverse": "", "levels": levels, "crash": crash}
	for f in files:
		var n := String(f).to_lower().get_basename()
		if n.begins_with("carcrx"):
			crash.append(f)
		elif n.begins_with("bad_"):
			_snd["bad"] = f
		elif n.ends_with("_on"):
			_snd["on"] = f
		elif n.ends_with("_of") or n.ends_with("_off"):
			_snd["off"] = f
		elif n.ends_with("_0"):
			_snd["idle"] = f
		elif n.ends_with("_r"):
			_snd["reverse"] = f
		elif n.length() > 2 and n[n.length() - 2] == "_" and n[n.length() - 1] in ["1", "2", "3", "4"] \
				and not levels.has(f):
			levels.append(f)
	levels.sort()


## Motorklang: Start/Abstellen, Leerlauf (_0), Fahrstufen (_1.._4 nach Geschwindigkeit), rückwärts (_r)
func _update_engine_sound() -> void:
	if _snd.is_empty():
		_classify_sounds()
	var d := driver()
	var running := d != null and d.alive and fuel > 0.0 and not wrecked
	# ohne Treibstoff (Car_SetFuel 0): Anlasser springt nicht an (bad_*.wav), einmal je Einstieg
	if d != null and fuel <= 0.0 and not wrecked and d != _bad_for:
		_bad_for = d
		OrigAudio.play_file(String(_snd["bad"]), global_position, 5.0, 80.0, 1.0, self)
	elif d == null:
		_bad_for = null
	if running and not _engine_on:
		_engine_on = true
		OrigAudio.play_file(String(_snd["on"]), global_position, 5.0, 80.0, 1.0, self)
	elif not running and _engine_on:
		_engine_on = false
		if is_instance_valid(_engine):
			_engine.queue_free()
		_engine = null
		_engine_file = ""
		if not wrecked:
			OrigAudio.play_file(String(_snd["off"]), global_position, 5.0, 80.0, 1.0, self)
	if not _engine_on:
		return
	# Drehzahl der Fahrphysik (VehicleDrive.rpm) wählt die Original-Stufe (_1.._4) und die Tonhöhe darin [E]
	var v: float = drive.speed if drive else linear_velocity.dot(global_basis.z)
	var want := String(_snd["idle"])
	var levels: Array = _snd["levels"]
	var frac := 0.0
	var rf := 0.0
	if drive:
		rf = clampf((drive.rpm - drive.rpm_idle) / maxf(drive.rpm_max - drive.rpm_idle, 1.0), 0.0, 1.05)
	if v < -0.5 and String(_snd["reverse"]) != "":
		want = String(_snd["reverse"])
		frac = rf
	elif (absf(v) > 0.8 or rf > 0.25) and not levels.is_empty():
		var x := rf * levels.size()
		var li := clampi(int(x), 0, levels.size() - 1)
		var cur_li := levels.find(_engine_file)
		if cur_li >= 0 and absf(x - (cur_li + 0.5)) < 0.62:
			li = cur_li           # Hysterese gegen Flattern an Stufengrenzen
		want = String(levels[li])
		frac = clampf(x - li, 0.0, 1.0)
	if want != _engine_file:
		if is_instance_valid(_engine):
			_engine.queue_free()
		_engine = OrigAudio.play_file(want, global_position, 5.0, 80.0, 1.0, self, true)
		_engine_file = want
	if is_instance_valid(_engine):
		_engine.pitch_scale = 0.88 + 0.3 * frac


# --- Schaden -----------------------------------------------------------------

func on_bullet_hit(damage: float, shooter: Node) -> void:
	if wrecked:
		return
	hit.emit(damage, shooter)
	if armored:
		return          # Panzer: Handwaffen wirkungslos [E]
	health -= damage
	if health <= 0.0:
		explode(shooter)


## Explosionen (Granaten, Raketen, Kanonen, Sprengladungen; OrigInteractive.damage_objects)
func on_explosion(damage: float, by: Node) -> void:
	if wrecked:
		return
	hit.emit(damage, by)
	health -= damage * 2.5
	if health <= 0.0:
		explode(by)


func explode(by: Node = null) -> void:
	if wrecked:
		return
	wrecked = true
	health = 0.0
	# Original Kat. 6 „Cars1 Heavy“ (18, Lastwagen/Halbkette/Panzer), „Cars2 Middle“ (19), „Cars3 Light“ (20,
	# Krad); Zuordnung zur Fahrzeugklasse nach Klangsatz = Annahme
	var cls := OrigAudio.EXP_CAR_MIDDLE
	var sf := " ".join(sound_files)
	if sf.contains("blitz") or sf.contains("bedf") or sf.contains("half") or sf.contains("hakl") or sf.contains("krupp") \
			or sf.contains("tiger") or sf.contains("sher") or sf.contains("puma"):
		cls = OrigAudio.EXP_CAR_HEAVY
	elif sf.contains("bmw"):
		cls = OrigAudio.EXP_CAR_LIGHT
	Effects.explosion(global_position + Vector3.UP, 6.0, [OrigAudio.CAT_EXPLOSION, cls])
	Events.emit_noise(global_position, 300.0, by, 1, &"explosion")
	for o in occupants.duplicate():
		if is_instance_valid(o):
			leave(o)
			o.apply_hit(120.0 if not armored else 400.0, &"torso", by, Vector3.UP)
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
