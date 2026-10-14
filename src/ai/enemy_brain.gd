class_name EnemyBrain
extends AIBrain
## Gegner-KI. Zustände nach dem Vorbild der Original-Skript-API
## (HUMAN_SETMODE_Guard, Patrouillen über Wegpunkte, HUMAN_Investigate,
## HUMAN_LookAround, OnAlarm/HUMAN_MoveToAlarm, KI-Modi Aggressive/Defensive).
##
##  GUARD/PATROL --(Verdacht)--> INVESTIGATE --(Erkennung)--> COMBAT
##        ^                            |                         |
##        +-------- (nichts) ----- SEARCH <---- (Ziel verloren) -+

enum State { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH }
enum Mode { AGGRESSIVE, DEFENSIVE }

const STATE_NAMES := ["Wache", "Patrouille", "Untersucht", "Kampf", "Sucht"]

var state: int = State.GUARD
var ai_mode: int = Mode.DEFENSIVE
var stationary := false           ## verlässt den Posten nie (z. B. Wachturm, MG-Nest)
var patrol_points: PackedVector3Array = []
var patrol_index := 0
var patrol_wait := 0.0
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var alert_level := 0.0            ## 0 ruhig .. 1 alarmiert (bleibt erhöht)
var target: Soldier
var investigate_pos := Vector3.ZERO
var search_time := 0.0
var _state_time := 0.0
var _cover_pos := Vector3.INF
var _peek_timer := 0.0
var _peeking := true
var _no_los_time := 0.0
var _look_timer := 0.0
var _shout_cooldown := 0.0
var _base_sight := 55.0
var _corpse_to_check: Soldier
var _grenade_cd := 1.0
var _engaged_time := 0.0
var _flanked := false
var _flank_retry := 0.0           ## s bis zum nächsten Flankenversuch, wenn keine Flanke gefunden wurde
var flank_target := Vector3.INF   ## zuletzt gewählte Flankenposition (Debug/Test)
## Feuern in der Bewegung (auf dem Weg in Deckung/zur Flanke) bis zu dieser Entfernung.
## Treffsicherheit sinkt dabei über die Bewegungsstreuung des Soldaten (Soldier.current_spread).
var move_fire_range := 35.0

# --- Steuerung durch Original-Skripte (LsRuntime) ---
var runtime: Node                 ## LsRuntime, falls die Mission Originalskripte nutzt
var script_control := false       ## HUMAN_SETAIMODE_Zombie: nur Skript, keine eigene Taktik
var suspended := false            ## HUMAN_Suspend(true)
var script_alarm_enabled := true  ## SetAlarmType(…, true/false)
var script_stance := -1
var script_move_mode: int = Soldier.MoveMode.WALK
var script_look_at := Vector3.INF
var _script_target := Vector3.INF
var _alarm_notified := false
## HUMAN_SetWaitForPlayer: beim Führen anhalten, wenn der Spieler zurückbleibt
var wait_for_player := false
var wait_stop_dist := 12.0
var wait_resume_dist := 8.0
var _waiting_player := false


func script_move(pos: Vector3) -> void:
	_script_target = pos
	script_look_at = Vector3.INF
	move_to(pos, script_move_mode)


func script_move_done() -> bool:
	return not has_move_target() or arrived(1.2)


func script_attack(t: Soldier) -> void:
	script_control = false
	target = t
	perception.awareness[t] = 1.0
	perception.last_known[t] = t.global_position
	set_state(State.COMBAT)


func calm_down() -> void:
	alert_level = 0.0
	set_state(_calm_state())


func _notify_script(key: String) -> void:
	if runtime and is_instance_valid(runtime):
		runtime.notify(soldier, key)


func _script_tick(delta: float) -> void:
	if script_stance >= 0:
		soldier.stance_request = script_stance
	if script_look_at.is_finite() and not has_move_target():
		look_at_point(script_look_at + Vector3.UP * 1.5, delta, 4.0)
	soldier.move_mode = script_move_mode
	if wait_for_player and has_move_target():
		var nearest := INF
		for p in get_tree().get_nodes_in_group("team_0"):
			var ps := p as Soldier
			if ps and ps != soldier and ps.alive and ps.is_player_controlled:
				nearest = minf(nearest, distance_to(ps.global_position))
		if nearest > wait_stop_dist:
			_waiting_player = true
		elif nearest < wait_resume_dist:
			_waiting_player = false
		if _waiting_player:
			soldier.move_input = Vector3.ZERO
			return
	update_movement(delta, true)
var flank_origin := Vector3.INF   ## Position bei der Flankenentscheidung


func setup(s: Soldier) -> void:
	super.setup(s)
	home_pos = s.global_position
	home_yaw = s.look_yaw
	_base_sight = perception.sight_range
	perception.target_detected.connect(_on_detected)
	perception.suspicious.connect(_on_suspicious)
	perception.heard.connect(_on_heard)
	perception.corpse_seen.connect(_on_corpse)
	Events.alarm_raised.connect(_on_alarm)
	s.damaged.connect(_on_damaged)
	state = State.PATROL if patrol_points.size() > 1 else State.GUARD


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive or suspended:
		return
	if script_control:
		_script_tick(delta)
		return
	_state_time += delta
	_shout_cooldown = maxf(_shout_cooldown - delta, 0.0)
	match state:
		State.GUARD: _guard(delta)
		State.PATROL: _patrol(delta)
		State.INVESTIGATE: _investigate(delta)
		State.COMBAT: _combat(delta)
		State.SEARCH: _search(delta)
	if stationary and state != State.GUARD:
		stop_moving()
	update_movement(delta, state != State.COMBAT)


func set_state(s: int) -> void:
	if s == state:
		return
	# Original-Skriptereignisse: OnAlarm beim Eintritt in den Kampf, OnAlarmDone bei Beruhigung
	if s == State.COMBAT and not _alarm_notified and script_alarm_enabled:
		_alarm_notified = true
		_notify_script("ONALARM")
	elif (s == State.GUARD or s == State.PATROL) and _alarm_notified:
		_alarm_notified = false
		_notify_script("ONALARMDONE")
	state = s
	_state_time = 0.0
	_cover_pos = Vector3.INF
	_engaged_time = 0.0
	_flanked = false
	_flank_retry = 0.0
	if s != State.COMBAT:
		cease_fire()


# --- Zustände ----------------------------------------------------------------

func _guard(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	if distance_to(home_pos) > 1.5:
		move_to(home_pos, Soldier.MoveMode.WALK)
		return
	stop_moving()
	# langsames Umsehen um die Grundrichtung (HUMAN_LookAround)
	var sweep := sin(_state_time * 0.35) * 0.6 * (1.0 + alert_level)
	soldier.look_yaw = rotate_toward(soldier.look_yaw, home_yaw + sweep, delta * 1.2)
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)


func _patrol(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	if patrol_points.is_empty():
		set_state(State.GUARD)
		return
	if patrol_wait > 0.0:
		patrol_wait -= delta
		soldier.look_yaw += sin(_state_time * 0.8) * delta * 0.5
		return
	var p := patrol_points[patrol_index]
	if distance_to(p) < 1.2 or not has_move_target():
		if distance_to(p) < 1.2:
			patrol_index = (patrol_index + 1) % patrol_points.size()
			patrol_wait = randf_range(1.5, 4.0)
			return
		move_to(p, Soldier.MoveMode.WALK)
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)


func _investigate(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	soldier.aiming = true
	if _state_time < 1.2:
		# erst hinsehen (Reaktion), dann vorsichtig hingehen
		stop_moving()
		look_at_point(investigate_pos + Vector3.UP, delta, 3.0)
		return
	if distance_to(investigate_pos) > 2.0:
		move_to(investigate_pos, Soldier.MoveMode.WALK)
	else:
		stop_moving()
		if _corpse_to_check and is_instance_valid(_corpse_to_check):
			_raise_alarm("Leiche gefunden")
			_corpse_to_check = null
		_look_timer += delta
		soldier.look_yaw += delta * 1.2
		if _look_timer > 5.0:
			_look_timer = 0.0
			set_state(State.SEARCH if alert_level > 0.5 else _calm_state())
	if _state_time > 25.0:
		set_state(_calm_state())


## Sucht eine Deckung seitlich versetzt zur Achse Gegner–Ziel (beide Seiten, zufällige Reihenfolge,
## wachsender Suchradius, je Kombination mehrere Stichprobenrunden). INF, wenn keine echte Flanke
## (mindestens 5 m seitlich) gefunden wurde.
func _find_flank(tpos: Vector3, threat_eye: Vector3) -> Vector3:
	var to_t := tpos - soldier.global_position
	to_t.y = 0.0
	var first := -1.0 if randf() < 0.5 else 1.0
	for radius: float in [8.0, 12.0, 16.0]:
		for side: float in [first, -first]:
			var perp := Vector3(-to_t.z, 0, to_t.x).normalized() * side
			var center := soldier.global_position + perp * 12.0 + to_t.normalized() * minf(to_t.length() * 0.3, 8.0)
			for _round in 2:
				var c := find_cover_around(center, threat_eye, radius)
				if c.is_finite() and absf((c - soldier.global_position).dot(perp)) > 5.0:
					return c
	return Vector3.INF


func _combat(delta: float) -> void:
	perception.forget_dead()
	var visible := perception.best_target()
	if visible:
		target = visible
		_no_los_time = 0.0
	else:
		_no_los_time += delta
	if target == null or not target.alive:
		target = null
		set_state(State.SEARCH)
		return
	var tpos: Vector3 = perception.last_known.get(target, target.global_position)
	var threat_eye := tpos + Vector3.UP * 1.5

	# Granate: Ziel hält sich hinter Deckung auf (Original: ATTACK_THROW_GRENADE).
	# Vor der Deckungslogik, damit auch auf dem Weg in Deckung geworfen wird.
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	var tdist := distance_to(tpos)
	if _no_los_time > 2.0 and _grenade_cd <= 0.0 and tdist > 8.0 and tdist < 32.0 and not stationary:
		_grenade_cd = randf_range(12.0, 20.0)
		if throw_grenade_at(tpos):
			stop_moving()
			_cover_pos = Vector3.INF   # danach neue Deckung wählen
			return

	if stationary:
		_cover_pos = soldier.global_position
	# Deckung suchen (einmalig bzw. wenn Deckung verloren)
	if _cover_pos == Vector3.INF and _state_time > 0.2:
		var bias := 0.6 if ai_mode == Mode.AGGRESSIVE else 0.0
		_cover_pos = find_cover(threat_eye, 14.0 if ai_mode == Mode.AGGRESSIVE else 9.0, bias)
		if _cover_pos.is_finite():
			move_to(_cover_pos, Soldier.MoveMode.RUN)
		else:
			_cover_pos = soldier.global_position   # keine Deckung: vor Ort hinknien
	var in_cover := _cover_pos.is_finite() and distance_to(_cover_pos) < 1.5
	if not in_cover and has_move_target():
		# auf dem Weg in Deckung bzw. zur Flanke: im Laufen weiterfeuern (Niederhalten),
		# solange das Ziel sichtbar und in Reichweite ist
		soldier.stance_request = Soldier.Stance.STAND
		if visible and distance_to(target.global_position) < move_fire_range:
			# aus der Hüfte im Laufschritt: Zielen würde das Rennen auf Gehen ×0,6 bremsen
			# (Soldier._update_movement), Sprinten erlaubt kein Feuern -> JOG, ungenauer (spread_hip)
			soldier.move_mode = Soldier.MoveMode.JOG
			engage(target, delta)
			soldier.aiming = false
		else:
			soldier.move_mode = Soldier.MoveMode.RUN
			cease_fire()
			_turn_towards_dir((agent.get_next_path_position() - soldier.global_position).normalized(), delta, 8.0)
		return
	stop_moving()

	# Flankieren (nur aggressiv): nach längerem Feuergefecht seitlich versetzt
	# neue Deckung suchen, um das Ziel aus einem anderen Winkel zu fassen
	_engaged_time += delta
	_flank_retry = maxf(_flank_retry - delta, 0.0)
	if ai_mode == Mode.AGGRESSIVE and not stationary and not _flanked and _engaged_time > 8.0 and _flank_retry <= 0.0:
		var flank := _find_flank(tpos, threat_eye)
		if flank.is_finite():
			_flanked = true
			_cover_pos = flank
			flank_target = flank
			flank_origin = soldier.global_position
			move_to(flank, Soldier.MoveMode.RUN)
			return
		# keine Flanke gefunden: nicht aufgeben, nach kurzer Zeit erneut suchen
		# (Stichproben sind zufällig, Lage/Ziel können sich ändern)
		_flank_retry = 2.0

	# Herausschauen und Feuern im Wechsel mit Abducken
	_peek_timer -= delta
	if _peek_timer <= 0.0:
		_peeking = not _peeking
		_peek_timer = randf_range(1.8, 3.5) if _peeking else randf_range(1.0, 2.2)
	if _peeking or not visible:
		soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
		if visible:
			engage(target, delta)
		else:
			cease_fire()
			look_at_point(threat_eye, delta, 4.0)
	else:
		soldier.stance_request = Soldier.Stance.CROUCH
		cease_fire()
		var w := soldier.current_weapon()
		if w and w.in_mag < w.data.magazine_size * 0.4:
			soldier.reload()

	# Ziel länger nicht sichtbar
	if _no_los_time > 6.0:
		if ai_mode == Mode.AGGRESSIVE:
			investigate_pos = tpos
			set_state(State.SEARCH)
		elif _no_los_time > 14.0:
			set_state(State.SEARCH)


func _search(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	soldier.aiming = true
	search_time += delta
	if not has_move_target() or arrived(1.5):
		_look_timer += delta
		soldier.look_yaw += delta * 1.5
		if _look_timer > 3.0:
			_look_timer = 0.0
			# zufälliger Punkt um die letzte bekannte Position (HUMAN_MoveRandomRadius)
			var p := investigate_pos + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			move_to(p, Soldier.MoveMode.WALK)
	if _state_time > 40.0:
		search_time = 0.0
		set_state(_calm_state())


func _calm_state() -> int:
	return State.PATROL if patrol_points.size() > 1 else State.GUARD


func _crouch_has_los(threat_eye: Vector3) -> bool:
	var from := soldier.global_position + Vector3.UP * 1.05
	var q := PhysicsRayQueryParameters3D.create(from, threat_eye, 1)
	return soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Reaktionen --------------------------------------------------------------

func _on_detected(t: Soldier) -> void:
	if not soldier.alive or suspended:
		return
	if script_control:
		# Zombie-Modus: das Skript entscheidet (OnAlarm), die KI greift nicht selbst ein
		target = t
		if not _alarm_notified and script_alarm_enabled:
			_alarm_notified = true
			_notify_script("ONALARM")
		return
	target = t
	if state != State.COMBAT:
		set_state(State.COMBAT)
		alert_level = 1.0
		perception.sight_range = maxf(_base_sight, 120.0)
		_shout(t.global_position)


func _on_suspicious(pos: Vector3) -> void:
	if state == State.COMBAT or not soldier.alive or suspended or script_control:
		return
	investigate_pos = pos
	alert_level = maxf(alert_level, 0.4)
	if state != State.INVESTIGATE:
		set_state(State.INVESTIGATE)


func _on_heard(pos: Vector3, kind: StringName, source: Node) -> void:
	if not soldier.alive or state == State.COMBAT or suspended:
		return
	if script_control:
		if (kind == &"gunshot" or kind == &"explosion" or kind == &"alert") and not _alarm_notified and script_alarm_enabled:
			_alarm_notified = true
			investigate_pos = pos
			_notify_script("ONALARM")
		return
	if kind == &"alert":
		# Kamerad meldet Feindkontakt: dorthin, kampfbereit
		investigate_pos = pos
		alert_level = 1.0
		set_state(State.SEARCH)
		move_to(pos, Soldier.MoveMode.RUN)
	elif kind == &"gunshot" or kind == &"explosion" or kind == &"impact":
		alert_level = 1.0
		investigate_pos = pos
		set_state(State.SEARCH)
		move_to(pos, Soldier.MoveMode.RUN)


func _on_corpse(c: Soldier) -> void:
	if state == State.COMBAT:
		return
	_corpse_to_check = c
	investigate_pos = c.global_position
	alert_level = 1.0
	set_state(State.INVESTIGATE)


func _on_damaged(_amount: float, _zone: StringName) -> void:
	if not soldier.alive:
		return
	var a := soldier.last_attacker as Soldier
	if a and is_instance_valid(a):
		perception.awareness[a] = 1.0
		perception.last_known[a] = a.global_position
		_on_detected(a)


func _on_alarm(pos: Vector3, _by: Node) -> void:
	if not soldier.alive or state == State.COMBAT:
		return
	if script_control:
		if not _alarm_notified and script_alarm_enabled:
			_alarm_notified = true
			_notify_script("ONALARM")
		return
	# Original: OnAlarm -> Sichtweite 300, rennen
	alert_level = 1.0
	perception.sight_range = maxf(_base_sight, 150.0)
	investigate_pos = pos
	set_state(State.SEARCH)
	move_to(pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), Soldier.MoveMode.RUN)


func _shout(pos: Vector3) -> void:
	if _shout_cooldown > 0.0:
		return
	_shout_cooldown = 6.0
	Events.emit_noise(soldier.global_position, 35.0, soldier, soldier.team, &"alert")
	# Feindkontakt im Gefecht löst nach kurzer Zeit den Gesamtalarm aus
	get_tree().create_timer(6.0, false).timeout.connect(_alarm_if_still_fighting)


func _alarm_if_still_fighting() -> void:
	if soldier.alive and state == State.COMBAT:
		_raise_alarm("Feindkontakt")


func _raise_alarm(_reason: String) -> void:
	var m := Game.current_mission()
	if m and m.has_method("raise_alarm"):
		m.raise_alarm(soldier.global_position, soldier)


func state_name() -> String:
	return STATE_NAMES[state]


func serialize() -> Dictionary:
	return {"state": state, "alert": alert_level, "patrol_index": patrol_index}


func deserialize(d: Dictionary) -> void:
	alert_level = d.get("alert", 0.0)
	patrol_index = int(d.get("patrol_index", 0)) % maxi(patrol_points.size(), 1)
	var s := int(d.get("state", state))
	# Kampf-/Suchzustände werden nach dem Laden als Suche fortgesetzt
	if s == State.COMBAT or s == State.INVESTIGATE:
		s = State.SEARCH
		investigate_pos = soldier.global_position
	set_state(s)
