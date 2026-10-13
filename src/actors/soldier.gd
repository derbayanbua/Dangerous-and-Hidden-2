class_name Soldier
extends CharacterBody3D
## Spielfigur (Spieler, Teammitglied oder Gegner).
## Gesteuert wird ausschließlich über "Absichten" (move_input, move_mode,
## stance_request, look_yaw/look_pitch, trigger, aim_point ...). Dieselbe
## Schnittstelle nutzen PlayerController, SquadBrain und EnemyBrain.
##
## Belegte Original-Mechaniken (docs/RE_FINDINGS.md): Haltungen Stand/Crouch/Lie
## (HUMAN_SETMODE_*), Gangarten Walk/Run, Ausdauer (staminabar), Gesundheit
## (healthbar), Seh-/Hörreichweite (HUMAN_SETSIGHTRANGE/SETHEARRANGE),
## getrennte Schadenszonen ("Unknow damage zone").

signal died(soldier: Soldier)
signal damaged(amount: float, zone: StringName)
signal weapon_changed(weapon: Weapon)
signal stance_changed(stance: int)
signal shot_fired(weapon: Weapon)

enum Stance { STAND, CROUCH, PRONE }
## WALK/SNEAK: KI und Originalskripte (Patrouille, HUMAN_SETMODE_*); JOG: Normaltempo des
## Spielers (moderne Steuerung: immer Laufschritt, Shift = Sprint/RUN, leise nur geduckt/liegend)
enum MoveMode { WALK, RUN, SNEAK, JOG }

const TEAM_ALLIED := 0
const TEAM_AXIS := 1

## Geschwindigkeiten m/s [Stance][MoveMode] (Designwerte)
const SPEEDS := [
	[1.7, 5.4, 0.95, 3.3],   # stehen: gehen, sprinten, schleichen, normal
	[1.1, 2.3, 0.7, 1.3],    # hocken (normal = leises Schleichen)
	[0.45, 0.75, 0.35, 0.6], # liegen (kriechen)
]
const EYE_HEIGHT := [1.62, 1.05, 0.32]
const CAPSULE_HEIGHT := [1.8, 1.2, 0.6]
const STANCE_TIME := [0.0, 0.35, 0.9]   ## Wechselzeit in Haltung X hinein
## Schrittgeräusch-Radius in m [Stance][MoveMode]
const STEP_NOISE := [[7.0, 20.0, 2.5, 11.0], [4.0, 9.0, 1.5, 2.5], [1.5, 2.5, 1.0, 1.2]]
const JUMP_VELOCITY := 4.2
## Klettern/Überspringen beim Sprung vor einem Hindernis (Höhe über den Füßen, m)
const CLIMB_MIN := 0.45
const CLIMB_MAX := 2.3

@export var soldier_name := "Soldat"
@export var team := TEAM_ALLIED
@export var max_health := 100.0
@export var uniform_color := Color(0.42, 0.38, 0.26)
@export var helmet_style := "brodie"
@export var persistent_id := ""         ## für Spielstände

# --- Zustand ---
var health := 100.0
var stamina := 100.0
var stance: int = Stance.STAND
var alive := true
var weapons: Array[Weapon] = []        ## Index = WeaponData.Slot
var current_slot := 0
var grenade_cooldown := 0.0

# --- Absichten (werden pro Frame vom Controller gesetzt) ---
var move_input := Vector3.ZERO      ## Weltrichtung, Länge 0..1
var move_mode: int = MoveMode.WALK
var stance_request: int = Stance.STAND
var look_yaw := 0.0                 ## Rad, Körperausrichtung
var look_pitch := 0.0               ## Rad, Zielneigung (+ = hoch)
var trigger := false
var aiming := false
var lean := 0.0                     ## -1 links .. 1 rechts
var aim_point := Vector3.ZERO       ## Weltpunkt, auf den die Waffe zielt
var has_aim_point := false
var extra_spread := 0.0             ## Zusatzstreuung (Grad), z. B. KI-Fehler
var is_player_controlled := false

# --- intern ---
var model: SoldierModel
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _stance_lock := 0.0
var _recoil := Vector2.ZERO          ## (pitch, yaw) Grad, wird vom Controller verbraucht
var _step_accum := 0.0
var _hitbox_rids: Array[RID] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var last_attacker: Node = null
var vehicle: Node = null            ## Fahrzeug, in dem der Soldat sitzt
var seat_index := -1

## Ausrüstung (Original-Inventar: ii_aid/ii_aidbig, ii_binoc)
var medkits := 1
var has_binoculars := true
var using_binoculars := false
var heal_time_left := 0.0           ## > 0: legt gerade einen Verband an
var heal_target: Soldier
const HEAL_DURATION := 3.0
const HEAL_AMOUNT := 45.0


## Verband anlegen: Kamerad vor sich (≤ 2 m, verletzt) oder sich selbst.
func start_heal(candidates: Array) -> bool:
	if medkits <= 0 or heal_time_left > 0.0 or vehicle != null:
		return false
	var best: Soldier = null
	for c in candidates:
		var s := c as Soldier
		if s == null or s == self or not s.alive or s.health >= s.max_health - 1.0:
			continue
		if s.global_position.distance_to(global_position) < 2.0:
			best = s
			break
	if best == null and health < max_health - 1.0:
		best = self
	if best == null:
		return false
	heal_target = best
	heal_time_left = HEAL_DURATION
	using_binoculars = false
	return true


func _update_heal(delta: float) -> void:
	if heal_time_left <= 0.0:
		return
	trigger = false
	move_input = Vector3.ZERO
	heal_time_left -= delta
	if not is_instance_valid(heal_target) or not heal_target.alive:
		heal_time_left = 0.0
		return
	if heal_time_left <= 0.0:
		heal_time_left = 0.0
		medkits -= 1
		heal_target.heal(HEAL_AMOUNT)
		Events.say("%s versorgt %s (+%d)." % [soldier_name, "sich selbst" if heal_target == self else heal_target.soldier_name, int(HEAL_AMOUNT)], 2.5)


## Tarnung (Original: Mission_SetUniformDisguise). Gegner erkennen einen
## getarnten Soldaten auf Distanz nicht, solange er nicht kürzlich geschossen hat.
var disguised := false
var last_shot_time := -100.0


func put_on_uniform(color: Color, helmet: String) -> void:
	disguised = true
	uniform_color = color
	helmet_style = helmet
	var old := model
	model = SoldierModel.new()
	model.name = "Model"
	add_child(model)
	model.build(self, color, helmet)
	if old:
		old.queue_free()
	_hitbox_rids.clear()
	for hb in model.find_children("*", "Hitbox", true, false):
		_hitbox_rids.append((hb as Hitbox).get_rid())
	_on_weapon_switched()


func seconds_since_shot() -> float:
	return Time.get_ticks_msec() / 1000.0 - last_shot_time


func toggle_binoculars() -> void:
	if not has_binoculars or vehicle != null and seat_index == 0:
		return
	using_binoculars = not using_binoculars
	trigger = false
	aiming = false


func enter_vehicle(v: Node, seat: int) -> void:
	vehicle = v
	seat_index = seat
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	stance = Stance.CROUCH        # sitzend ≈ hockend (Sichtbarkeit, Trefferfläche)
	stance_request = Stance.CROUCH
	_apply_capsule(Stance.CROUCH)


func exit_vehicle(at: Vector3) -> void:
	vehicle = null
	seat_index = -1
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1) | (1 << 4)
	global_position = at
	velocity = Vector3.ZERO


func _ready() -> void:
	add_to_group("soldiers")
	add_to_group("team_%d" % team)
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1) | (1 << 4)   # Welt, Figuren, Zäune
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	health = max_health
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.3
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	add_child(_shape)
	_apply_capsule(Stance.STAND)
	model = SoldierModel.new()
	model.name = "Model"
	add_child(model)
	model.build(self, uniform_color, helmet_style)
	for hb in find_children("*", "Hitbox", true, false):
		_hitbox_rids.append((hb as Hitbox).get_rid())
	look_yaw = rotation.y
	rotation = Vector3.ZERO
	if not weapons.is_empty():
		_on_weapon_switched()


## Ausrüstung vor oder nach _ready festlegen. ids: Primär, Seitenwaffe, Granate.
func equip(ids: Array) -> void:
	weapons.clear()
	for id in ids:
		weapons.append(Weapon.new(WeaponDB.get_weapon(StringName(id))) if id != "" else null)
	current_slot = 0
	while current_slot < weapons.size() and weapons[current_slot] == null:
		current_slot += 1
	if is_node_ready():
		_on_weapon_switched()


func current_weapon() -> Weapon:
	if current_slot < weapons.size():
		return weapons[current_slot]
	return null


func exclude_rids() -> Array[RID]:
	var r: Array[RID] = _hitbox_rids.duplicate()
	r.append(get_rid())
	return r


func eye_position() -> Vector3:
	var right := Vector3(cos(look_yaw), 0, -sin(look_yaw))
	var h: float = model.head.global_position.y + 0.1 if model else global_position.y + EYE_HEIGHT[stance]
	var p := global_position
	p.y = h
	return p + right * lean * 0.35


func aim_direction() -> Vector3:
	return Vector3(
		-sin(look_yaw) * cos(look_pitch),
		sin(look_pitch),
		-cos(look_yaw) * cos(look_pitch)).normalized()


func forward() -> Vector3:
	return Vector3(-sin(look_yaw), 0, -cos(look_yaw))


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.3


func current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Physik / Bewegung -------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= _gravity * delta
			move_and_slide()
		return
	if vehicle != null:
		# im Fahrzeug: Position folgt dem Sitz, Waffen (Mitfahrer) bleiben nutzbar
		if not is_instance_valid(vehicle):
			exit_vehicle(global_position)
		else:
			var t: Transform3D = vehicle.seat_transform(seat_index)
			global_position = t.origin - Vector3.UP * 0.55
			if seat_index == 0:
				trigger = false   # Fahrer schießt nicht
			_update_weapon(delta)
			# Körper in Fahrtrichtung (Fahrzeug vorne = +Z, Soldat vorne = -Z);
			# Mitfahrer, die zielen, drehen sich zum Ziel
			rotation.y = look_yaw if (aiming and seat_index > 0) else vehicle.global_rotation.y + PI
			model.update_anim(delta, Stance.CROUCH, 0.0, look_pitch, aiming, 0.0)
			return
	_update_heal(delta)
	if using_binoculars:
		trigger = false
		aiming = false
	_update_stance(delta)
	_update_movement(delta)
	_update_weapon(delta)
	rotation.y = look_yaw
	model.update_anim(delta, stance, current_speed(), look_pitch, aiming, lean)


func _update_stance(delta: float) -> void:
	_stance_lock = maxf(_stance_lock - delta, 0.0)
	if stance_request == stance or _stance_lock > 0.0:
		return
	if stance_request < stance and not _has_headroom(stance_request):
		stance_request = stance
		return
	var from := stance
	stance = stance_request
	_stance_lock = maxf(STANCE_TIME[stance], STANCE_TIME[from] * 0.8)
	_apply_capsule(stance)
	stance_changed.emit(stance)


func _apply_capsule(s: int) -> void:
	var h: float = CAPSULE_HEIGHT[s]
	_capsule.height = h
	_capsule.radius = 0.3
	_shape.position = Vector3(0, h * 0.5, 0)


func _has_headroom(s: int) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = CAPSULE_HEIGHT[s]
	params.shape = cap
	params.transform = Transform3D(Basis(), global_position + Vector3(0, cap.height * 0.5 + 0.05, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func stance_transitioning() -> bool:
	return _stance_lock > 0.0


func _update_movement(delta: float) -> void:
	var mode := move_mode
	if mode == MoveMode.RUN and (stamina < 5.0 or aiming or stance != Stance.STAND):
		mode = MoveMode.JOG if is_player_controlled else MoveMode.WALK
	if _climb_t > 0.0:
		_update_climb(delta)
		return
	var wish := move_input.limit_length(1.0)
	var speed: float = SPEEDS[stance][mode]
	if aiming:
		speed *= 0.6
	if health < max_health * 0.35:
		speed *= 0.75   # verletzt
	if stance_transitioning() and stance == Stance.PRONE:
		speed = 0.0
	var target := wish * speed
	var accel := 10.0 if is_on_floor() else 2.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * maxf(speed, 1.0))
	velocity.z = move_toward(velocity.z, target.z, accel * delta * maxf(speed, 1.0))
	if is_on_floor() and _jump_request:
		velocity.y = JUMP_VELOCITY
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	_jump_request = false
	move_and_slide()

	# Ausdauer: Rennen kostet, Gewicht der Ausrüstung erhöht den Verbrauch.
	var moving := current_speed() > 0.3
	if moving and mode == MoveMode.RUN and stance == Stance.STAND:
		stamina = maxf(stamina - (10.0 + _carried_weight() * 0.4) * delta, 0.0)
	else:
		stamina = minf(stamina + (12.0 if not moving else 6.0) * delta, 100.0)

	# Schrittgeräusche für die Gehör-KI
	if moving and is_on_floor():
		_step_accum += current_speed() * delta
		if _step_accum > 1.6:
			_step_accum = 0.0
			var r: float = STEP_NOISE[stance][mode]
			Events.emit_noise(global_position, r, self, team, &"step")
			if r > 3.0:
				Effects.play(&"step", global_position, -18.0 if mode != MoveMode.RUN else -10.0, 1.0, 30.0)


# --- Springen / Klettern (moderne Steuerung: Sprungtaste vor Hindernis = klettern) ---
var _jump_request := false
var _climb_t := 0.0
var _climb_dur := 0.0
var _climb_from := Vector3.ZERO
var _climb_mid := Vector3.ZERO
var _climb_to := Vector3.ZERO


func is_climbing() -> bool:
	return _climb_t > 0.0


## Sprungtaste: aus Hocke/Liegen aufstehen; stehend vor einem Hindernis hinaufklettern bzw.
## darüber steigen, sonst springen.
func jump_or_climb() -> void:
	if stance != Stance.STAND:
		stance_request = Stance.STAND
		return
	if _climb_t > 0.0 or not is_on_floor() or vehicle != null:
		return
	if not try_climb():
		_jump_request = true


func try_climb() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := forward()
	fwd.y = 0.0
	if fwd.length() < 0.1:
		return false
	fwd = fwd.normalized()
	var feet := global_position
	var ex: Array[RID] = exclude_rids()
	# 1. Hindernis vor dem Soldaten (Knie- oder Brusthöhe)
	var hit := {}
	for h in [0.5, 1.2, 1.9]:
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * h, feet + Vector3.UP * h + fwd * 1.0, 1, ex)
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return false
	var wall: Vector3 = hit.position
	wall.y = feet.y
	# 2. Oberkante direkt hinter der Vorderseite
	var top := _ray_down(space, wall + fwd * 0.12, feet.y + CLIMB_MAX + 0.4, feet.y + 0.2, ex)
	if not top.is_finite():
		return false
	var h_top := top.y - feet.y
	if h_top < CLIMB_MIN or h_top > CLIMB_MAX:
		return false
	# 3a. Dünnes Hindernis (Zaun, Mauer): dahinter landen
	var beyond := _ray_down(space, wall + fwd * 0.9, top.y + 0.5, feet.y - 1.5, ex)
	var on_top := _ray_down(space, wall + fwd * 0.45, top.y + 0.5, top.y - 0.25, ex)
	var dest := Vector3.INF
	if on_top.is_finite() and _fits(on_top):
		dest = on_top                                   # breite Kante: hinaufklettern
	elif beyond.is_finite() and h_top <= 1.4 and _fits(beyond):
		dest = beyond                                   # über Zaun/Mauer steigen
	if not dest.is_finite():
		return false
	_climb_from = feet
	_climb_mid = Vector3(feet.x, top.y + 0.15, feet.z) + fwd * 0.25
	_climb_to = dest + Vector3.UP * 0.02
	_climb_dur = 0.35 + h_top * 0.35
	_climb_t = _climb_dur
	velocity = Vector3.ZERO
	Events.emit_noise(global_position, 6.0, self, team, &"climb")
	return true


func _ray_down(space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float, to_y: float, ex: Array[RID]) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.z), Vector3(at.x, to_y, at.z), 1, ex)
	var r := space.intersect_ray(q)
	return r.position if not r.is_empty() else Vector3.INF


func _fits(at: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = CAPSULE_HEIGHT[Stance.STAND] - 0.1
	params.shape = cap
	params.transform = Transform3D(Basis(), at + Vector3(0, cap.height * 0.5 + 0.08, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _update_climb(delta: float) -> void:
	_climb_t = maxf(_climb_t - delta, 0.0)
	var k := 1.0 - _climb_t / _climb_dur
	# erst hoch (60 %), dann nach vorn auf/über die Kante
	if k < 0.6:
		global_position = _climb_from.lerp(_climb_mid, k / 0.6)
	else:
		global_position = _climb_mid.lerp(_climb_to, (k - 0.6) / 0.4)
	velocity = Vector3.ZERO


func _carried_weight() -> float:
	var w := 0.0
	for wpn in weapons:
		if wpn:
			w += wpn.data.weight
	return w


# --- Waffen ------------------------------------------------------------------

func _update_weapon(delta: float) -> void:
	grenade_cooldown = maxf(grenade_cooldown - delta, 0.0)
	for w in weapons:
		if w:
			w.tick(delta)
	var w := current_weapon()
	if w == null:
		return
	var can_fire := not stance_transitioning() and not (move_mode == MoveMode.RUN and is_moving() and not aiming)
	if w.data.slot == WeaponData.Slot.GRENADE:
		if trigger and can_fire and grenade_cooldown <= 0.0 and w.total_ammo() > 0:
			throw_grenade(w)
		return
	if w.trigger(trigger and can_fire):
		_fire_shot(w)


func _fire_shot(w: Weapon) -> void:
	var origin := eye_position()
	var dir := aim_direction()
	if has_aim_point:
		var to := aim_point - origin
		if to.length() > 1.0:
			dir = to.normalized()
	var spread_deg := current_spread()
	dir = _apply_spread(dir, spread_deg)
	Ballistics.fire(self, origin, dir, w.data, exclude_rids(), team)
	var muzzle := origin + dir * 0.9
	if model and model.weapon_socket:
		muzzle = model.weapon_socket.global_position + dir * w.data.model_length * 0.8
	Effects.muzzle_flash(muzzle, dir)
	Effects.play(Effects.weapon_sound(w.data), muzzle, 0.0, 1.0, w.data.noise_radius * 2.0)
	Events.emit_noise(global_position, w.data.noise_radius, self, team, &"gunshot")
	# Rückstoß: liegend mit Zweibein (Bren) / aufgelegt deutlich weniger
	var k := 1.0
	if stance == Stance.CROUCH:
		k = 0.8
	elif stance == Stance.PRONE:
		k = 0.55
	_recoil += Vector2(w.data.recoil_pitch * k, randf_range(-1.0, 1.0) * w.data.recoil_yaw * k)
	last_shot_time = Time.get_ticks_msec() / 1000.0
	shot_fired.emit(w)
	if w.data.action == WeaponData.Action.BOLT:
		get_tree().create_timer(0.35, false).timeout.connect(_bolt_sound)


func _bolt_sound() -> void:
	if alive:
		Effects.play(&"bolt", global_position, -12.0, 1.0, 20.0)


## Aktuelle Streuung (Halbwinkel in Grad) aus Waffe, Haltung, Bewegung, Ausdauer.
func current_spread() -> float:
	var w := current_weapon()
	if w == null:
		return 0.0
	var base := w.data.spread_aim if aiming else w.data.spread_hip
	var stance_k := [1.0, 0.75, 0.5][stance] as float
	var move_k := clampf(current_speed() / 2.0, 0.0, 1.0) * w.data.spread_move_add
	var fatigue := (1.0 - stamina / 100.0) * (0.6 if aiming else 0.3)
	return base * stance_k + move_k + w.bloom * (0.6 if aiming else 1.0) + fatigue + extra_spread


static func _apply_spread(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return dir
	# Gleichverteilung in der Kreisscheibe des Streukegels
	var r := deg_to_rad(spread_deg) * sqrt(randf())
	var a := randf() * TAU
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	return (dir + right * tan(r) * cos(a) + up2 * tan(r) * sin(a)).normalized()


## Vom Controller abgeholter Rückstoß (Grad), danach zurückgesetzt.
func consume_recoil() -> Vector2:
	var r := _recoil
	_recoil = Vector2.ZERO
	return r


func reload() -> bool:
	var w := current_weapon()
	if w and w.start_reload():
		Effects.play(&"bolt", global_position, -14.0, 0.7, 15.0)
		return true
	return false


func select_slot(slot: int) -> bool:
	if slot < 0 or slot >= weapons.size() or weapons[slot] == null or slot == current_slot:
		return false
	if slot == WeaponData.Slot.GRENADE and weapons[slot].total_ammo() <= 0:
		return false
	var w := current_weapon()
	if w:
		w.cancel_reload()
	current_slot = slot
	_on_weapon_switched()
	return true


func cycle_weapon(dir: int) -> void:
	for i in range(1, weapons.size() + 1):
		var s := posmod(current_slot + dir * i, weapons.size())
		if select_slot(s):
			return


func _on_weapon_switched() -> void:
	var w := current_weapon()
	if model:
		model.set_weapon(w.data if w else null)
	if w:
		w.cooldown = maxf(w.cooldown, 0.5)  # Waffe ziehen
	weapon_changed.emit(w)


## override_velocity: von der KI berechnete Abwurfgeschwindigkeit (sonst Blickrichtung).
func throw_grenade(w: Weapon, override_velocity := Vector3.INF) -> void:
	if w.in_mag <= 0:
		if w.reserve <= 0:
			return
		w.reserve -= 1
		w.in_mag = 1
	w.in_mag -= 1
	grenade_cooldown = 1.2
	var g := Grenade.new()
	g.data = w.data
	g.thrower = self
	g.team = team
	get_parent().add_child(g)
	var origin := eye_position() + aim_direction() * 0.5
	g.global_position = origin
	var dir := aim_direction()
	dir.y += 0.25
	g.linear_velocity = dir.normalized() * w.data.throw_speed * (0.7 if stance == Stance.PRONE else 1.0)
	if override_velocity.is_finite():
		g.linear_velocity = override_velocity
	g.add_collision_exception_with(self)
	if w.total_ammo() <= 0 and current_slot == WeaponData.Slot.GRENADE:
		cycle_weapon(-1)


# --- Schaden -----------------------------------------------------------------

func apply_hit(amount: float, zone: StringName, attacker: Node, direction: Vector3) -> void:
	if not alive:
		return
	# Liegend sind Beine/Arme kleinere Ziele; Helm reduziert Kopfschaden leicht.
	if zone == &"head" and helmet_style != "cap":
		amount *= 0.85
	health -= amount
	last_attacker = attacker
	damaged.emit(amount, zone)
	Events.soldier_damaged.emit(self, amount, zone, attacker)
	if health <= 0.0:
		die(attacker, direction)


func heal(amount: float) -> void:
	if alive:
		health = minf(health + amount, max_health)


func die(attacker: Node = null, direction := Vector3.ZERO) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	trigger = false
	move_input = Vector3.ZERO
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.leave(self)       # Gefallene fallen aus dem Fahrzeug
	collision_layer = 0          # Leichen blockieren keine Bewegung
	_apply_capsule(Stance.PRONE)
	for hb in find_children("*", "Hitbox", true, false):
		(hb as Hitbox).collision_layer = 0
	remove_from_group("team_%d" % team)
	add_to_group("corpses")
	model.play_death(direction)
	died.emit(self)
	Events.soldier_died.emit(self, attacker)


# --- Spielstand --------------------------------------------------------------

func serialize() -> Dictionary:
	var ws := []
	for w in weapons:
		ws.append(w.serialize() if w else null)
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": look_yaw, "health": health, "stamina": stamina, "stance": stance,
		"alive": alive, "slot": current_slot, "weapons": ws, "medkits": medkits,
		"disguised": disguised, "uniform": uniform_color.to_html(), "helmet": helmet_style,
	}


func deserialize(d: Dictionary) -> void:
	var p: Array = d["pos"]
	global_position = Vector3(p[0], p[1], p[2])
	look_yaw = d["yaw"]
	health = d["health"]
	stamina = d.get("stamina", 100.0)
	medkits = int(d.get("medkits", medkits))
	if d.get("disguised", false):
		put_on_uniform(Color.html(d.get("uniform", "5a5e54")), d.get("helmet", "stahlhelm"))
	weapons.clear()
	for wd in d["weapons"]:
		weapons.append(Weapon.deserialize(wd) if wd != null else null)
	current_slot = int(d.get("slot", 0))
	_on_weapon_switched()
	stance = int(d.get("stance", 0))
	stance_request = stance
	_apply_capsule(stance)
	if not d.get("alive", true):
		alive = false
		collision_layer = 0
		for hb in find_children("*", "Hitbox", true, false):
			(hb as Hitbox).collision_layer = 0
		remove_from_group("team_%d" % team)
		add_to_group("corpses")
		model.set_dead_instant()
