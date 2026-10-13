class_name AIBrain
extends Node
## Gemeinsame Basis für KI-Steuerung (Gegner und Kameraden).
## Setzt ausschließlich die Absichten des Soldaten (wie der Spieler).
## Bietet: Navigation (NavigationAgent3D), Zielen mit Reaktionszeit und
## Treffergenauigkeit, Feuerstöße, Deckungssuche.

const COVER_SAMPLES := 16

var soldier: Soldier
var perception: Perception
var agent: NavigationAgent3D
var enabled := true

## Kampf-Parameter
var reaction_time := 0.6        ## s bis zum ersten Schuss nach Zielerfassung
var accuracy_skill := 0.5       ## 0..1, verringert die KI-Zusatzstreuung
var burst_left := 0
var burst_pause := 0.0
var _burst_start_mag := 0
var _track_time := 0.0          ## wie lange das aktuelle Ziel verfolgt wird
var _aim_target: Soldier
var _move_target := Vector3.INF
var _repath := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO


func setup(s: Soldier) -> void:
	soldier = s
	perception = s.get_node_or_null("Perception")
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.radius = 0.35
	agent.height = 1.8
	agent.path_max_distance = 3.0
	s.add_child(agent)


# --- Bewegung ----------------------------------------------------------------

func move_to(pos: Vector3, mode: int = Soldier.MoveMode.WALK) -> void:
	soldier.move_mode = mode
	if _move_target.is_finite() and _move_target.distance_to(pos) < 0.5 and _repath > 0.0:
		return
	_move_target = pos
	agent.target_position = pos
	_repath = 0.5


func stop_moving() -> void:
	_move_target = Vector3.INF
	soldier.move_input = Vector3.ZERO


func has_move_target() -> bool:
	return _move_target.is_finite()


func arrived(tolerance := 1.0) -> bool:
	if not _move_target.is_finite():
		return true
	var a := soldier.global_position
	var b := _move_target
	a.y = 0
	b.y = 0
	return a.distance_to(b) <= tolerance


## Pro Physikschritt aufrufen. face_move = Körper in Laufrichtung drehen.
func update_movement(delta: float, face_move := true) -> void:
	_repath -= delta
	if not _move_target.is_finite():
		soldier.move_input = Vector3.ZERO
		return
	if arrived(agent.target_desired_distance):
		stop_moving()
		return
	var next := agent.get_next_path_position()
	var dir := next - soldier.global_position
	dir.y = 0
	if dir.length() < 0.05:
		# kein Pfad (z. B. Navigationsnetz noch nicht fertig): direkt laufen
		dir = _move_target - soldier.global_position
		dir.y = 0
	dir = dir.normalized()
	soldier.move_input = dir
	_open_doors_ahead(delta, dir)
	if face_move and dir.length() > 0.1:
		_turn_towards_dir(dir, delta, 6.0)
	# Feststecken erkennen
	if soldier.global_position.distance_to(_last_pos) < 0.05 * delta * 60.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = soldier.global_position
	if _stuck_time > 2.5:
		_stuck_time = 0.0
		stop_moving()


var _door_check := 0.0

## Geschlossene Türen in Laufrichtung öffnen (Navmesh enthält Türen nicht).
func _open_doors_ahead(delta: float, dir: Vector3) -> void:
	_door_check -= delta
	if _door_check > 0.0:
		return
	_door_check = 0.3
	for n in soldier.get_tree().get_nodes_in_group("interactables"):
		var door := n as Door
		if door == null or door.is_open:
			continue
		var to := door.global_position - soldier.global_position
		to.y = 0.0
		if to.length() < 1.8 and (to.length() < 0.7 or to.normalized().dot(dir) > 0.3):
			door.interact(soldier)


func _turn_towards_dir(dir: Vector3, delta: float, speed: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	soldier.look_yaw = rotate_toward(soldier.look_yaw, want, speed * delta)


func look_at_point(p: Vector3, delta: float, speed := 5.0) -> void:
	var to := p - soldier.eye_position()
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	soldier.look_yaw = rotate_toward(soldier.look_yaw, want_yaw, speed * delta)
	soldier.look_pitch = move_toward(soldier.look_pitch, want_pitch, speed * delta)


func facing_error(p: Vector3) -> float:
	var to := p - soldier.eye_position()
	return absf(angle_difference(soldier.look_yaw, atan2(-to.x, -to.z)))


# --- Kampf -------------------------------------------------------------------

## Ziel anvisieren und schießen. Gibt false zurück, wenn kein Schuss möglich.
func engage(target: Soldier, delta: float) -> bool:
	if target == null or not target.alive:
		soldier.trigger = false
		soldier.aiming = false
		return false
	if target != _aim_target:
		_aim_target = target
		_track_time = 0.0
	_track_time += delta
	var aim_p := target.global_position + Vector3.UP * (1.3 if target.stance == Soldier.Stance.STAND else (0.85 if target.stance == Soldier.Stance.CROUCH else 0.25))
	look_at_point(aim_p, delta, 7.0)
	soldier.aim_point = aim_p
	soldier.has_aim_point = true
	soldier.aiming = true
	var w := soldier.current_weapon()
	if w == null:
		return false
	if w.in_mag == 0:
		soldier.trigger = false
		if not w.is_reloading():
			if not soldier.reload():
				_switch_to_any_loaded()
		return true
	# Zusatzstreuung der KI: sinkt mit Verfolgungsdauer und Können,
	# steigt mit Zielbewegung und Entfernung.
	var dist := soldier.global_position.distance_to(target.global_position)
	var err := (1.0 - accuracy_skill) * 3.0 * clampf(1.5 - _track_time * 0.5, 0.25, 1.5)
	if target.is_moving():
		err += 1.0
	if target.stance == Soldier.Stance.PRONE:
		err += 0.5
	err += dist / 80.0
	soldier.extra_spread = err
	var can_shoot := _track_time >= reaction_time and facing_error(aim_p) < 0.12
	_handle_bursts(w, can_shoot, delta, dist)
	return true


func _handle_bursts(w: Weapon, can_shoot: bool, delta: float, dist: float) -> void:
	burst_pause = maxf(burst_pause - delta, 0.0)
	if not can_shoot or burst_pause > 0.0:
		soldier.trigger = false
		return
	if w.fires_automatic():
		if burst_left <= 0:
			burst_left = randi_range(3, 7) if dist < 25.0 else randi_range(2, 4)
			_burst_start_mag = w.in_mag
		soldier.trigger = true
		if _burst_start_mag - w.in_mag >= burst_left:
			burst_left = 0
			soldier.trigger = false
			burst_pause = randf_range(0.35, 0.9)
	else:
		# Einzelfeuer: Abzug pro Schuss loslassen
		if soldier.trigger:
			soldier.trigger = false
			burst_pause = randf_range(0.25, 0.6) + (0.6 if w.data.action == WeaponData.Action.BOLT else 0.0)
		elif w.cooldown <= 0.0:
			soldier.trigger = true


## Wirft eine Granate ballistisch (flacher Bogen) auf target. false, wenn
## keine Granate vorhanden oder außer Reichweite.
func throw_grenade_at(target: Vector3) -> bool:
	if soldier.weapons.size() <= WeaponData.Slot.GRENADE:
		return false
	var w := soldier.weapons[WeaponData.Slot.GRENADE]
	if w == null or w.total_ammo() <= 0 or soldier.grenade_cooldown > 0.0:
		return false
	var origin := soldier.eye_position()
	var to := target - origin
	var h := to.y
	var flat := Vector2(to.x, to.z)
	var d := flat.length()
	var v := w.data.throw_speed
	var g := Ballistics.GRAVITY
	var disc := v * v * v * v - g * (g * d * d + 2.0 * h * v * v)
	if disc < 0.0 or d < 4.0:
		return false
	var angle := atan((v * v - sqrt(disc)) / (g * d))
	var hdir := flat.normalized()
	var vel := Vector3(hdir.x * cos(angle), sin(angle), hdir.y * cos(angle)) * v
	soldier.look_yaw = atan2(-to.x, -to.z)
	soldier.throw_grenade(w, vel)
	if soldier.team == Soldier.TEAM_AXIS:
		# Warnruf, für den Spieler nur in Hörweite sichtbar
		var m := Game.current_mission()
		var p: Soldier = m.controller.active if m and m.controller else null
		if p and p.global_position.distance_to(soldier.global_position) < 35.0:
			Events.say("Ruf: \"Handgranate!\"", 2.0)
	return true


func cease_fire() -> void:
	soldier.trigger = false
	soldier.aiming = false
	soldier.has_aim_point = false
	soldier.extra_spread = 0.0
	_aim_target = null


func _switch_to_any_loaded() -> void:
	for i in soldier.weapons.size():
		var w := soldier.weapons[i]
		if w and i != WeaponData.Slot.GRENADE and w.total_ammo() > 0:
			soldier.select_slot(i)
			return


# --- Deckung -----------------------------------------------------------------

## Sucht einen Punkt in Reichweite, der aus Sicht von threat_eye im Hocken
## verdeckt ist, aber stehend/hockend Sicht erlaubt (zum Herausschauen).
## bias_toward: 0 = nahe der eigenen Position, 1 = Richtung Bedrohung.
func find_cover(threat_eye: Vector3, max_radius := 12.0, bias_toward := 0.0) -> Vector3:
	var origin := soldier.global_position
	var to_threat := (threat_eye - origin)
	to_threat.y = 0
	var center := origin + to_threat.normalized() * minf(to_threat.length() * 0.4, max_radius * 0.6) * bias_toward
	return find_cover_around(center, threat_eye, max_radius)


## Deckungssuche um einen frei wählbaren Mittelpunkt (z. B. Flankenposition).
func find_cover_around(center: Vector3, threat_eye: Vector3, max_radius: float) -> Vector3:
	var space := soldier.get_world_3d().direct_space_state
	var origin := soldier.global_position
	var map := agent.get_navigation_map()
	var best := Vector3.INF
	var best_score := -INF
	for i in COVER_SAMPLES:
		var ang := TAU * float(i) / COVER_SAMPLES + randf() * 0.3
		var r := randf_range(2.0, max_radius)
		var p := center + Vector3(cos(ang), 0, sin(ang)) * r
		if map.is_valid():
			p = NavigationServer3D.map_get_closest_point(map, p)
		var low := p + Vector3.UP * 0.9
		var q := PhysicsRayQueryParameters3D.create(threat_eye, low, 1)
		var hidden_low := not space.intersect_ray(q).is_empty()
		if not hidden_low:
			continue
		var score := -origin.distance_to(p) * 0.5
		# Deckung, die das Herausschauen erlaubt, bevorzugen
		var high := p + Vector3.UP * 1.55
		var q2 := PhysicsRayQueryParameters3D.create(high, threat_eye, 1)
		if space.intersect_ray(q2).is_empty():
			score += 6.0
		score -= absf(p.distance_to(threat_eye) - 25.0) * 0.1
		if score > best_score:
			best_score = score
			best = p
	return best


func distance_to(p: Vector3) -> float:
	return soldier.global_position.distance_to(p)
