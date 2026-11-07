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
var skip_reaction := false      ## AP-48b: OrigCombatFsm feuert ohne zweite Reaktionssperre (nur Blickfehler)
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
## Steht der Soldat abseits des Navigationsnetzes (z. B. ARCTIC1-Landeplatz: Netz 18 m tiefer), zeigt der Pfad
## senkrecht nach unten und der Soldat tritt auf der Stelle → direkt aufs Ziel laufen (nur Trupp-KI, SquadBrain).
var direct_when_off_mesh := false
const OFF_MESH_DIST := 2.0
const STUCK_SPEED := 0.25        ## m/s: darunter gilt der Soldat als festgefahren [E]
var _off_mesh := false
var _off_check := 0.0
var _detour := 0.0
var _detour_sign := 1.0
## B-033 HUMAN_SetIgnoreCircumventionFlag (hd2.exe Gehirn +0x11C [B]). 0x562E30 überspringt bei gesetztem Byte die Umgehung:
## 0x5626B0 sucht im Pfad (+0xF4) den zusammenhängenden Abschnitt mit Punktflag 0x200, 0x562700 sammelt die Hindernisse darauf,
## 0x561740/0x562900 schneiden den Pfad (x/z) mit deren Umkreis, 0x561C70 fügt Umgehungspunkte ein [B]. Mit Flag bleibt der
## Pfad unverändert: kein seitliches Ausweichen, kein Durchlaufen. Einen Abbruch sieht diese Stelle nicht vor; der Soldat
## wartet daher vor einem stehenden Menschen bis 10 s [E], an festen Hindernissen bleibt der Abbruch nach 2,5 s [E].
var ignore_circumvention := false
var _human_tries := 0
var _climb_retry := 0.0
var _climb_dir := Vector3.ZERO
## B-044 [E]: Wegfolge-Korrektur (nur EnemyBrain schaltet sie ein). NavigationAgent3D schaltet den nächsten Pfadpunkt erst
## weiter, wenn der 3D-Abstand < path_desired_distance ist; liegt der Fußpunkt des Soldaten 0,3–0,6 m über/unter der
## Netzfläche, wird das nie erreicht → der Soldat kreist mit Laufabsicht um den Punkt (gemessen: v 0,1–0,8 m/s, Abstand
## zum Punkt konstant 0,6–0,7 m, Festhäng-Erkennung greift nicht, HUMAN_Move wartet bis zum Zeitlimit).
## Abhilfe: Lenkpunkt = erster Pfadpunkt ab dem aktuellen Index mit waagrechtem Abstand ≥ STEER_SKIP (ohne Sprung über
## Höhenwechsel > 0,8 m = Leiter/Kletterstelle), dazu Fortschrittswächter: kommt der Soldat dem Laufziel PROGRESS_S lang
## nicht um PROGRESS_MIN näher, neuer Pfad, beim zweiten Mal Abbruch (wie die bisherige Festhäng-Erkennung).
var path_follow_fix := false
const STEER_SKIP := 0.45
const PROGRESS_S := 6.0
const PROGRESS_MIN := 0.5
var _prog_best := INF
var _prog_t := 0.0
var _prog_repaths := 0
var progress_aborts := 0          ## Zähler (Test/Messung)


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
	agent.link_reached.connect(_on_link_reached)


## Navigationsverbindung erreicht: Leiter (Mission.ladder_links, Meta „ladder“/„ladder_top“) → hinauf-/hinunterklettern
## wie der Spieler per Benutzen (OrigLadder.climb); der Pfad geht danach am anderen Ende weiter.
func _on_link_reached(details: Dictionary) -> void:
	var link = details.get("owner")
	if not (link is NavigationLink3D) or soldier == null or soldier.is_climbing():
		return
	if link.has_meta("climb"):
		# Kletterstelle (Mission._bridge_islands): hinauf wie der Spieler per Sprungtaste (Soldier.try_climb), hinunter
		# einfach weiterlaufen (Absprung ≤ CLIMB_MAX)
		var to: Vector3 = details.get("link_exit_position", link.end_position)
		var from: Vector3 = details.get("link_entry_position", soldier.global_position)
		if to.y - from.y > Soldier.STEP_HEIGHT:
			var d := to - soldier.global_position
			d.y = 0.0
			if d.length() > 0.05:
				soldier.look_yaw = atan2(-d.x, -d.z)
			soldier.stance_request = Soldier.Stance.STAND
			if not soldier.try_climb():
				_climb_retry = 1.5
				_climb_dir = d.normalized()
		return
	if not link.has_meta("ladder"):
		return
	var bottom = link.get_meta("ladder")
	var top = link.get_meta("ladder_top", null)
	if not is_instance_valid(bottom):
		return
	var at: Vector3 = details.get("link_entry_position", soldier.global_position)
	var use = bottom
	if top != null and is_instance_valid(top) and at.distance_to(top.global_position) < at.distance_to(bottom.global_position):
		use = top
	if use.can_interact(soldier):
		use.climb(soldier)


# --- Bewegung ----------------------------------------------------------------

func move_to(pos: Vector3, mode: int = Soldier.MoveMode.WALK) -> void:
	soldier.move_mode = mode
	if _move_target.is_finite() and _move_target.distance_to(pos) < 0.5 and _repath > 0.0:
		return
	if not _move_target.is_finite() or _move_target.distance_to(pos) > 1.0:
		_prog_best = INF
		_prog_t = 0.0
		_prog_repaths = 0
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
	if path_follow_fix:
		next = _steer_point(next)
		if _progress_check(delta):
			return
	var dir := next - soldier.global_position
	dir.y = 0
	if direct_when_off_mesh:
		_off_check -= delta
		if _off_check <= 0.0 and NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0:
			_off_check = 0.5
			var cp := NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), soldier.global_position)
			_off_mesh = cp.distance_to(soldier.global_position) > OFF_MESH_DIST
	var direct := direct_when_off_mesh and _off_mesh
	if _climb_retry > 0.0:
		# Kletterstelle: an die Wand herantreten und erneut hinaufklettern (try_climb braucht ≤ 1 m Abstand)
		_climb_retry -= delta
		if _climb_dir.length() > 0.1:
			soldier.look_yaw = atan2(-_climb_dir.x, -_climb_dir.z)
			soldier.move_input = _climb_dir
		if not soldier.is_climbing() and soldier.try_climb():
			_climb_retry = 0.0
		return
	if dir.length() < 0.05 or direct:
		# kein Pfad (z. B. Navigationsnetz noch nicht fertig): direkt laufen
		dir = _move_target - soldier.global_position
		dir.y = 0
	dir = dir.normalized()
	if _detour > 0.0:
		# festgefahren (abseits des Netzes oder an einem stehenden Menschen): seitlich vorbei (Ersatz, kein Originalverhalten)
		_detour -= delta
		dir = dir.rotated(Vector3.UP, 1.2 * _detour_sign)
	soldier.move_input = dir
	_open_doors_ahead(delta, dir)
	if face_move and dir.length() > 0.1:
		_turn_towards_dir(dir, delta, 6.0)
	# Feststecken erkennen
	# Feststecken = praktisch kein Fortschritt (< 0,25 m/s). Vorher 0,05 m je Bild bei 60 Hz = 3 m/s: jedes Gehen
	# (1,7 m/s) und jeder Hang galt als „fest“, nach 2,5 s brach die Bewegung ab (ALPS2 Agentin auf der Außentreppe).
	if soldier.global_position.distance_to(_last_pos) < STUCK_SPEED * delta:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = soldier.global_position
	if ignore_circumvention:
		_detour = 0.0
	elif direct and _stuck_time > 1.5:
		# Hindernis ohne Netz: hinübersteigen versuchen, sonst abwechselnd links/rechts ausweichen
		_stuck_time = 0.0
		soldier.jump_or_climb()
		_detour_sign = -_detour_sign
		_detour = 1.5
		return
	if _stuck_time > 1.0 and not ignore_circumvention:
		var blocker := _blocked_by_human()
		if blocker:
			# ein stehender Mensch versperrt den Weg (ALPS2: AL2_20 auf dem schmalen Treppenabsatz): erst seitlich
			# ausweichen, nach zwei Versuchen kurz durch ihn hindurch (Kollisionsausnahme 3 s) [E, Ersatz]
			_stuck_time = 0.0
			_human_tries += 1
			if _human_tries > 2 and not blocker.is_player_controlled:
				_human_tries = 0
				soldier.add_collision_exception_with(blocker)
				soldier.get_tree().create_timer(3.0, false).timeout.connect(_end_pass_through.bind(soldier, blocker))
			else:
				_detour_sign = -_detour_sign
				_detour = 1.0
			return
	if _stuck_time > 2.5 and not (ignore_circumvention and _stuck_time < 10.0 and _blocked_by_human() != null):
		_stuck_time = 0.0
		stop_moving()


## B-044: Lenkpunkt mit waagrechtem Abstand (siehe path_follow_fix).
func _steer_point(next: Vector3) -> Vector3:
	var path := agent.get_current_navigation_path()
	var i := agent.get_current_navigation_path_index()
	if i < 0 or i >= path.size():
		return next
	var p := soldier.global_position
	while i + 1 < path.size() and Vector2(path[i].x - p.x, path[i].z - p.z).length() < STEER_SKIP \
			and absf(path[i + 1].y - path[i].y) < 0.8:
		i += 1
	return path[i]


## B-044: Fortschrittswächter; true = Bewegung abgebrochen.
func _progress_check(delta: float) -> bool:
	if soldier.is_climbing() or _climb_retry > 0.0:
		_prog_t = 0.0
		return false
	var d := Vector2(_move_target.x - soldier.global_position.x, _move_target.z - soldier.global_position.z).length()
	if d < _prog_best - PROGRESS_MIN:
		_prog_best = d
		_prog_t = 0.0
		return false
	_prog_t += delta
	if _prog_t < PROGRESS_S:
		return false
	if ignore_circumvention and _blocked_by_human() != null and _prog_t < 10.0:
		return false
	_prog_t = 0.0
	_prog_best = d
	if _prog_repaths < 1:
		_prog_repaths += 1
		agent.target_position = _move_target + Vector3(0.01, 0.0, 0.0)    # neuen Pfad ab der aktuellen Lage erzwingen
		_detour_sign = -_detour_sign
		_detour = 1.0
		return false
	progress_aborts += 1
	stop_moving()
	return true


func _end_pass_through(s: Soldier, other: Soldier) -> void:
	if is_instance_valid(s) and is_instance_valid(other):
		s.remove_collision_exception_with(other)


func _blocked_by_human() -> Soldier:
	for i in soldier.get_slide_collision_count():
		var o := soldier.get_slide_collision(i).get_collider()
		if o is Soldier:
			return o as Soldier
	var kc := KinematicCollision3D.new()
	var fw := Vector3(soldier.move_input.x, 0.0, soldier.move_input.z)
	if fw.length() > 0.1 and soldier.test_move(soldier.global_transform, fw.normalized() * 0.3, kc) and kc.get_collider() is Soldier:
		return kc.get_collider() as Soldier
	return null


var _door_check := 0.0

## Geschlossene Türen in Laufrichtung öffnen (Navmesh enthält Türen nicht).
func _open_doors_ahead(delta: float, dir: Vector3) -> void:
	_door_check -= delta
	if _door_check > 0.0:
		return
	_door_check = 0.3
	for n in soldier.get_tree().get_nodes_in_group("interactables"):
		var door := n as Node3D
		if not (n is Door or n is OrigInteractive.OrigDoor) or n.is_open:
			continue
		var to := door.global_position - soldier.global_position
		to.y = 0.0
		if to.length() < 1.8 and (to.length() < 0.7 or to.normalized().dot(dir) > 0.3):
			if n is OrigInteractive.OrigDoor:
				n.ai_open(soldier)
			else:
				n.interact(soldier)


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
	var can_shoot := (skip_reaction or _track_time >= reaction_time) and facing_error(aim_p) < 0.12
	if can_shoot and check_fire_line and friend_in_fire_line(aim_p):
		can_shoot = false
	_handle_bursts(w, can_shoot, delta, dist)
	return true


## B-036c: Schusslinienprüfung gegen eigene Leute. Original [B Daten]: Spielerereignis „FRIEND_IN_FIRE_LINE(_S)“
## (Namentabelle hd2.exe 0x83CDDC, Eintrag bei 0x83CF98) mit eigenen Sprachsätzen „Friendly In Line Of Fire“
## (speech.txt 91300177 …) – die Trupp-KI hält also das Feuer, wenn ein Kamerad in der Schusslinie steht, und meldet
## es. Geometrie (Abstand zur Linie, Prüfhöhen, Takt) im Original nicht dekodiert [E]: lebender Soldat derselben Seite
## mit Körperachse (0,3/0,9/1,5 m) < FIRE_LINE_R zur Linie Auge → Zielpunkt, zwischen 0,6 m und Zielabstand − 0,8 m.
const FIRE_LINE_R := 0.55
const EV_FRIEND_IN_FIRE_LINE := 112      ## Ereignisnummer analog EV_FRIENDLY_FIRE 102 (+10 Einträge) [P]
var check_fire_line := false     ## SquadBrain schaltet ein (Ereignis „Plr event“ = Spielerseite)
var fire_line_blocks := 0                ## Zähler (Test/Messung)
var _fl_t := 0.0
var _fl_blocked := false


func friend_in_fire_line(aim_p: Vector3) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _fl_t < 0.15:
		return _fl_blocked
	_fl_t = now
	_fl_blocked = false
	var a := soldier.eye_position()
	var ab := aim_p - a
	var dl := ab.length()
	if dl < 1.0:
		return false
	var dir := ab / dl
	for n in soldier.get_tree().get_nodes_in_group("team_%d" % soldier.team):
		var f := n as Soldier
		if f == null or f == soldier or not f.alive:
			continue
		var fp := f.global_position
		if (fp - a).length() > dl + 1.0:
			continue
		for h: float in [0.3, 0.9, 1.5]:
			var p := fp + Vector3.UP * h
			var t := (p - a).dot(dir)
			if t < 0.6 or t > dl - 0.8:
				continue
			if (a + dir * t).distance_to(p) < FIRE_LINE_R:
				_fl_blocked = true
				fire_line_blocks += 1
				OrigAudio.speak_event(soldier, EV_FRIEND_IN_FIRE_LINE, 8.0)
				return true
	return false


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
	for i in [WeaponData.Slot.PRIMARY, WeaponData.Slot.SIDEARM]:
		var w: Weapon = soldier.weapons[i] if i < soldier.weapons.size() else null
		if w and w.total_ammo() > 0:
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
