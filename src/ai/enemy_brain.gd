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

# --- Alarmarten (Original SetAlarmType(Maske, an/aus) / _GetAlarmType). Bedeutung der 10 Bits laut
# Originalskriptkommentar (BURMA2 bu2_08.scr, CZECH6 c5_r*.scr) [B]:
const AL_NEAR_SHOT := 1       ## nahe Schüsse
const AL_SHOT := 2            ## Schüsse
const AL_STEPS := 4           ## Schritte
const AL_SOUND := 8           ## Geräusche (OnUse: Türen, Schalter)
const AL_EXPLOSION := 16
const AL_SEE := 32            ## Feind gesehen
const AL_HURT := 64           ## verwundet
const AL_DEATHCRY := 128      ## Todesschrei eines Kameraden
const AL_FRIENDLY := 256      ## Beschuss durch die eigene Seite
const AL_CORPSE := 512        ## Leiche gesehen
var alarm_mask := 1023        ## SetAlarmType: welche Alarmarten OnAlarm auslösen
var events_enabled := true    ## HUMAN_SetEvents(false): keine KI-Ereignisse an das Skript (z. B. schlafende Posten)
var last_alarm_type := 0      ## _GetAlarmType: Art des Alarms, der zuletzt OnAlarm ausgelöst hat
var alarm_pos := Vector3.INF  ## Ort des letzten Alarmreizes (HUMAN_MoveToAlarm)
var _stimulus := AL_SEE
var _script_alarm_t := 0.0
## Skriptgesteuerte (Zombie-)Akteure: OnAlarmDone, wenn so lange kein neuer Alarmreiz kam (ANNAHME, Dauer nicht belegt)
const SCRIPT_ALARM_HOLD := 25.0

# --- Moral / Ergeben / Gefangennahme (hd2.exe, docs/re_notes_ai_surrender.md) ---
## Moral aus actors.bin (+0xF8, Standard 80). Ab Anfangsmoral ≥ 90 gerät der Soldat nie in Panik (Flag 1),
## ab ≥ 75 kämpft er in Panik bewaffnet weiter (Flag 2) [B 0x547A81, 0x5487DF, 0x54B955].
var morale := 80.0
var morale_initial := 80.0
var surrendered := false      ## Hände hoch (0x5A6450: KI vtable +0x100, Byte +0x2C1)
var captured := false         ## gefangen genommen (Flag 0x4000000, 0x5A6380)
var uniform_taken := false    ## Uniform abgegeben (Byte +0x1A5)
## Abstand, unter dem ein bedrängter Soldat sich ergibt statt zu fliehen: 15 m [B 0x80F620]
const SURRENDER_DIST := 15.0
var _surrender_check := 0.0
var _surrender_delay := -1.0   ## Original: Hände hoch nach 300 ms (Zustand 0x2000002, Zähler 0x12C)
var _captor: Soldier
var capture_action: Node      ## EnemyBrain.CaptureAction (Interactable am Soldaten)
var _mount_target: Node       ## Waffenstellung, die die KI besetzen will
var _mount_check := 0.0
var look_around := 0          ## HUMAN_LookAround(n), 0 = aus
var _look_around_t := 0.0
var _look_around_base := 0.0


func set_look_around(n: int) -> void:
	look_around = maxi(n, 0)
	_look_around_t = 0.0
	_look_around_base = soldier.look_yaw
	script_look_at = Vector3.INF


func script_move(pos: Vector3) -> void:
	_script_target = pos
	script_look_at = Vector3.INF
	move_to(pos, script_move_mode)


func script_move_done() -> bool:
	return not has_move_target() or arrived(1.2)


## HUMAN_IllFire(Ziel, ms): ms lang auf ein Ziel (Akteur oder Frame) feuern, z. B. Zielscheiben (ALPS1), Hinrichtung
## (ARCTIC3 Killer); blockiert das Skript für die Dauer
var _ill_fire_t := 0.0
var _ill_target: Node3D


func script_ill_fire(t: Node3D, seconds: float) -> void:
	_ill_target = t
	_ill_fire_t = maxf(seconds, 0.1)
	stop_moving()


func ill_fire_done() -> bool:
	return _ill_fire_t <= 0.0


func _ill_fire_tick(delta: float) -> void:
	_ill_fire_t -= delta
	soldier.move_input = Vector3.ZERO
	if not is_instance_valid(_ill_target) or _ill_fire_t <= 0.0:
		_ill_fire_t = 0.0
		cease_fire()
		return
	var p := _ill_target.global_position + (Vector3.UP * 1.2 if _ill_target is Soldier else Vector3.ZERO)
	look_at_point(p, delta, 8.0)
	soldier.aim_point = p
	soldier.has_aim_point = true
	soldier.aiming = true
	var w := soldier.current_weapon()
	if w == null:
		return
	if w.in_mag == 0 and not w.is_reloading():
		soldier.reload()
	_handle_bursts(w, facing_error(p) < 0.15, delta, distance_to(p))


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
	elif look_around > 0 and not has_move_target():
		# HUMAN_LookAround(n): Umsehen um die aktuelle Blickrichtung (Weite nach n – ANNAHME, Stufen nicht belegt)
		_look_around_t += delta
		soldier.look_yaw = _look_around_base + sin(_look_around_t * 0.6) * minf(0.25 * look_around, 1.2)
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
	s.died.connect(func(_x): OrigAudio.set_combat(self, false))
	Events.soldier_died.connect(_on_any_death)
	state = State.PATROL if patrol_points.size() > 1 else State.GUARD
	if s.team == Soldier.TEAM_AXIS and not Net.is_online:
		var ca := CaptureAction.new()
		ca.name = "CaptureAction"
		ca.brain = self
		s.add_child(ca)
		capture_action = ca


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive:
		return
	if surrendered or captured:
		_surrender_tick(delta)
		return
	if suspended:
		return
	_surrender_check -= delta
	if _surrender_check <= 0.0:
		_surrender_check = 0.25
		_check_surrender()
		if surrendered:
			return
	if _script_alarm_t > 0.0:
		_script_alarm_t -= delta
		if _script_alarm_t <= 0.0 and _alarm_notified and script_control:
			_alarm_notified = false
			_notify_script("ONALARMDONE")
	if _ill_fire_t > 0.0:
		_ill_fire_tick(delta)
		return
	if soldier.mounted != null or (soldier.vehicle != null and soldier.seat_index > 0 \
			and soldier.vehicle.has_method("seat_weapon") and soldier.vehicle.seat_weapon(soldier.seat_index) != null):
		_mounted_tick(delta)
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
	if s == State.COMBAT:
		_script_alarm(_stimulus, target.global_position if is_instance_valid(target) else soldier.global_position)
	elif (s == State.GUARD or s == State.PATROL) and _alarm_notified:
		_alarm_notified = false
		_notify_script("ONALARMDONE")
	# Original-Missionsmusik: Action, solange mindestens ein Gegner im Kampf ist (hd2.exe 0x5832F0 -> 0x69E920)
	OrigAudio.set_combat(self, s == State.COMBAT)
	# Gegner-Rufe (speech.set Sätze „Enemy G #1–#4“, deutsche Aufnahmen 9000xxxx); Zuordnung der Ereignisse
	# zu den KI-Zuständen nach den Satznamen (speech.txt) – Auslösezeitpunkte = Annahme
	if soldier and soldier.alive:
		if s == State.INVESTIGATE and state != State.COMBAT:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_SUSPICIOUS, 4.0)
		elif (s == State.GUARD or s == State.PATROL) and state == State.INVESTIGATE:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_NOTHING, 4.0)
		elif (s == State.GUARD or s == State.PATROL) and state == State.SEARCH:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_CANCEL, 4.0)
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
	if _try_autonomous_mount(delta):
		return
	# Panik (Moral < 20) ohne Standhaftigkeit und Feind ≥ 15 m: Flucht (Original-Zustand 0x4000002) [B]; Fluchtweg 25 m [E]
	if morale < 20.0 and morale_initial < 90.0 and not (is_armed() and morale_initial >= 75.0) \
			and is_instance_valid(target) and target.alive and distance_to(target.global_position) >= SURRENDER_DIST:
		if not has_move_target() or arrived(1.5):
			var away := soldier.global_position - target.global_position
			away.y = 0.0
			move_to(soldier.global_position + away.normalized() * 25.0, Soldier.MoveMode.RUN)
		cease_fire()
		return
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
	# Kampfrufe: „Get Him! / He's Here!“ (Ereignis 119) bei Sicht, unbewaffnet „I Don't Have A Gun“ (114);
	# Abstand 8–14 s je Sprecher = Annahme
	if visible and _state_time > 2.0:
		var armed := soldier.current_weapon() != null and soldier.current_weapon().data.action != WeaponData.Action.MELEE
		OrigAudio.speak_event(soldier, OrigAudio.EV_E_ATTACK if armed else OrigAudio.EV_E_NO_WEAPON, randf_range(8.0, 14.0))

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

## Alarmreiz an das Originalskript: OnAlarm nur, wenn die Art per SetAlarmType erlaubt ist; _GetAlarmType
## liefert danach diese Art, HUMAN_MoveToAlarm läuft zum Ort des Reizes.
func _script_alarm(type: int, pos: Vector3) -> void:
	if surrendered or captured:
		return
	alarm_pos = pos
	if not script_alarm_enabled or not events_enabled or (alarm_mask & type) == 0:
		return
	_script_alarm_t = SCRIPT_ALARM_HOLD
	if _alarm_notified:
		return
	last_alarm_type = type
	_alarm_notified = true
	if Game.cli.has("debug_alarm"):
		print("ALARM %s Art %d bei %s" % [soldier.name, type, pos])
		print_stack()
	_notify_script("ONALARM")


func _on_detected(t: Soldier) -> void:
	if not soldier.alive or suspended or surrendered or captured:
		return
	if script_control:
		# Zombie-Modus: das Skript entscheidet (OnAlarm), die KI greift nicht selbst ein
		target = t
		_script_alarm(AL_SEE, t.global_position)
		return
	target = t
	_stimulus = AL_SEE
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


## Geräuschart -> Original-Alarmart (Zuordnung nach den Kommentar-Bezeichnungen; „alert“ = Zuruf eines
## Kameraden mit Feindsicht -> 32 und Schüsse unter 15 m -> 1 sind ANNAHMEN)
func _alarm_type_of(kind: StringName, pos: Vector3, source: Node) -> int:
	match kind:
		&"gunshot", &"impact":
			if source is Soldier and (source as Soldier).team == soldier.team:
				return 0
			return AL_NEAR_SHOT if distance_to(pos) < 15.0 else AL_SHOT
		&"explosion":
			return AL_EXPLOSION
		&"step", &"climb", &"engine":
			return AL_STEPS
		&"door", &"voice", &"melee", &"bark":
			return AL_SOUND
		&"alert":
			return AL_SEE
	return 0


func _on_heard(pos: Vector3, kind: StringName, source: Node) -> void:
	if not soldier.alive or state == State.COMBAT or suspended or surrendered or captured:
		return
	var at := _alarm_type_of(kind, pos, source)
	if at != 0 and (at != AL_STEPS or (source is Soldier and (source as Soldier).team != soldier.team)):
		_stimulus = at
		if script_control:
			investigate_pos = pos
			_script_alarm(at, pos)
		else:
			alarm_pos = pos
	if script_control:
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
	if surrendered or captured:
		return
	_stimulus = AL_CORPSE
	if script_control:
		_script_alarm(AL_CORPSE, c.global_position)
		return
	alarm_pos = c.global_position
	if state == State.COMBAT:
		return
	_corpse_to_check = c
	investigate_pos = c.global_position
	alert_level = 1.0
	set_state(State.INVESTIGATE)


func _on_damaged(amount: float, _zone: StringName) -> void:
	if not soldier.alive:
		return
	var a := soldier.last_attacker as Soldier
	# Moral sinkt mit Verwundungen (ANNAHME: −0,25 je Schadenspunkt, Originalformel nicht belegt)
	morale = maxf(morale - amount * 0.25, 0.0)
	if surrendered and not captured:
		# Original: Beschuss eines Ergebenen (Ereignis 0x40000010/15) -> Flucht bzw. Gegenwehr [P 0x54B820]
		_end_surrender(a)
		return
	if captured:
		return
	if a and is_instance_valid(a):
		var same := a.team == soldier.team
		_stimulus = AL_FRIENDLY if same else AL_HURT
		if script_control:
			_script_alarm(_stimulus, a.global_position)
		if same:
			return
		perception.awareness[a] = 1.0
		perception.last_known[a] = a.global_position
		_on_detected(a)


func _on_alarm(pos: Vector3, _by: Node) -> void:
	if not soldier.alive or state == State.COMBAT or surrendered or captured:
		return
	if script_control:
		_script_alarm(AL_SHOT, pos)
		_notify_script("ONGLOBALALARM")
		return
	_notify_script("ONGLOBALALARM")
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
	OrigAudio.speak_event(soldier, OrigAudio.EV_E_SEE, 3.0)    # „I See Him / Enemy!“ (speech.set 121)
	Events.emit_noise(soldier.global_position, 35.0, soldier, soldier.team, &"alert")
	# Feindkontakt im Gefecht löst nach kurzer Zeit den Gesamtalarm aus
	get_tree().create_timer(6.0, false).timeout.connect(_alarm_if_still_fighting)


## Gegner hat sein Ziel getötet: Ruf „I Got Him / He's Dead“ (speech.set Ereignis 118)
func _on_any_death(s: Node, attacker: Node) -> void:
	if attacker == soldier and s != soldier and soldier.alive:
		OrigAudio.speak_event(soldier, OrigAudio.EV_E_KILLED, 3.0)
	# Todesschrei eines Kameraden in Hörweite (Alarmart 128); Moral sinkt (ANNAHME −15 je Kamerad in 30 m)
	if s is Soldier and s != soldier and soldier.alive and (s as Soldier).team == soldier.team:
		var d := distance_to((s as Soldier).global_position)
		if d < 30.0:
			morale = maxf(morale - 15.0, 0.0)
		if d < perception.hear_range * 0.5 and not surrendered and not captured:
			_stimulus = AL_DEATHCRY
			if script_control:
				_script_alarm(AL_DEATHCRY, (s as Soldier).global_position)


func _alarm_if_still_fighting() -> void:
	if soldier.alive and state == State.COMBAT:
		_raise_alarm("Feindkontakt")


func _raise_alarm(_reason: String) -> void:
	var m := Game.current_mission()
	if m and m.has_method("raise_alarm"):
		m.raise_alarm(soldier.global_position, soldier)


func state_name() -> String:
	if captured:
		return "Gefangen"
	if surrendered:
		return "Ergeben"
	return STATE_NAMES[state]


# --- Ergeben / Gefangennahme ------------------------------------------------------
# Original (hd2.exe, docs/re_notes_ai.md §1): Panik bei Moral < 20 (außer Anfangsmoral ≥ 90) oder ohne Waffe
# [B 0x5487DF]; in Panik mit sichtbarem Feind: bewaffnet und Anfangsmoral ≥ 75 -> weiterkämpfen, sonst Feind unter 15 m
# -> ergeben (Hände hoch nach 300 ms), sonst fliehen [B 0x54B955–0x54B9D6]. Gefangennehmen (T7038) nur bei Ergebenen,
# „Uniform benutzen“ (T7044) nur bei lebenden Gefangenen – an Leichen ist der Eintrag grau [B 0x4BF670 Fall 3].
# ANNAHME (Auslöser im Spiel): Wird ein ahnungsloser Soldat (nicht im Kampf) aus höchstens 15 m mit einer Schusswaffe
# anvisiert, sinkt seine Moral schlagartig um 70 (Überraschung) – er gerät in Panik und ergibt sich.

## Spieler-/Truppsoldat, der diesen Soldaten aus höchstens 15 m mit einer Schusswaffe anvisiert (Sichtlinie)
func _threat_aiming() -> Soldier:
	var chest := soldier.global_position + Vector3.UP * 1.1
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_ALLIED):
		var t := n as Soldier
		if t == null or not t.alive or t.vehicle != null or t.disguised:
			continue
		var d := t.global_position.distance_to(soldier.global_position)
		if d > SURRENDER_DIST:
			continue
		var w := t.current_weapon()
		if w == null or w.data.action in [WeaponData.Action.MELEE, WeaponData.Action.THROWN]:
			continue
		if not t.aiming:
			continue
		var to := chest - t.eye_position()
		if t.aim_direction().angle_to(to) > deg_to_rad(maxf(10.0, rad_to_deg(atan2(0.6, maxf(d, 0.5))))):
			continue
		var q := PhysicsRayQueryParameters3D.create(t.eye_position(), chest, 1)
		if not soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		return t
	return null


func is_armed() -> bool:
	for w in soldier.weapons:
		if w and w.data.action not in [WeaponData.Action.MELEE, WeaponData.Action.THROWN] and w.total_ammo() > 0:
			return true
	return false


func _check_surrender() -> void:
	if soldier.team != Soldier.TEAM_AXIS or soldier.vehicle != null or soldier.mounted != null or Net.is_online:
		return
	if _surrender_delay >= 0.0:
		return
	var t := _threat_aiming()
	if t == null:
		# Original ohne Zielen: in Panik (Moral < 20 bzw. unbewaffnet) und erkannter Feind unter 15 m -> ergeben
		if ((morale < 20.0 and morale_initial < 90.0) or not is_armed()) and not (is_armed() and morale_initial >= 75.0):
			var v := perception.best_target()
			if v and v.team == Soldier.TEAM_ALLIED and distance_to(v.global_position) < SURRENDER_DIST:
				t = v
		if t == null:
			return
	var surprised := script_control or state in [State.GUARD, State.PATROL, State.INVESTIGATE]
	var m := morale - (70.0 if surprised else 0.0)
	var panic := (m < 20.0 and morale_initial < 90.0) or not is_armed()
	if not panic:
		return
	if is_armed() and morale_initial >= 75.0 and not surprised:
		return     # Original: bewaffnet und standhaft -> kämpft weiter (Zustand 0x8000001)
	_captor = t
	_surrender_delay = 0.3
	cease_fire()
	stop_moving()


## Zustand „ergeben“/„gefangen“: steht mit erhobenen Händen (gefangen: kniet) und tut nichts
func _surrender_tick(delta: float) -> void:
	soldier.trigger = false
	soldier.aiming = false
	soldier.move_input = Vector3.ZERO
	_move_target = Vector3.INF
	soldier.stance_request = Soldier.Stance.CROUCH if captured else Soldier.Stance.STAND
	if is_instance_valid(_captor) and not captured:
		look_at_point(_captor.eye_position(), delta, 3.0)


func _process(delta: float) -> void:
	if _surrender_delay < 0.0 or soldier == null:
		return
	_surrender_delay -= delta
	if _surrender_delay < 0.0 and soldier.alive and not surrendered:
		surrender(_captor)


## Hände hoch: kein Ziel mehr für die KI des Trupps (neutral), Skript ruht bis zum Tod
func surrender(by: Soldier = null) -> void:
	if surrendered or not soldier.alive:
		return
	surrendered = true
	_surrender_delay = -1.0
	_captor = by
	cease_fire()
	stop_moving()
	OrigAudio.set_combat(self, false)
	soldier.set_meta("hands_up", true)
	if soldier.model and soldier.model.has_method("set_hands_up"):
		soldier.model.set_hands_up(true)
	_set_team(Soldier.TEAM_NEUTRAL)
	var vm = runtime.vm_for(soldier) if runtime and is_instance_valid(runtime) else null
	if vm:
		vm.paused = true
	# Ruf beim Ergeben: Satz „I Don't Have A Gun“ (speech.set Ereignis 114) – Zuordnung ANNAHME
	OrigAudio.speak_event(soldier, OrigAudio.EV_E_NO_WEAPON, 3.0)
	if by and by.is_player_controlled:
		Events.say("%s ergibt sich." % soldier.soldier_name, 2.5)


func _set_team(t: int) -> void:
	soldier.remove_from_group("team_%d" % soldier.team)
	soldier.team = t
	soldier.add_to_group("team_%d" % t)


## Ergebener wird beschossen: bewaffnet -> Gegenwehr, sonst Flucht (Original 0x54B820: 0x8000001 bzw. 0x4000002)
func _end_surrender(attacker: Soldier) -> void:
	surrendered = false
	soldier.remove_meta("hands_up")
	if soldier.model and soldier.model.has_method("set_hands_up"):
		soldier.model.set_hands_up(false)
	_set_team(Soldier.TEAM_AXIS)
	morale_initial = minf(morale_initial, 74.0)    # kein zweites Ergeben aus Standhaftigkeit
	var vm = runtime.vm_for(soldier) if runtime and is_instance_valid(runtime) else null
	if vm:
		vm.paused = false
	script_control = false
	if attacker and is_armed():
		_on_detected(attacker)
	elif attacker:
		var away := soldier.global_position - attacker.global_position
		away.y = 0.0
		set_state(State.SEARCH)
		move_to(soldier.global_position + away.normalized() * 30.0, Soldier.MoveMode.RUN)


## Gefangennehmen (Original T7038): Waffen abgeben, niederknien; danach Durchsuchen und Uniform möglich
func capture(by: Soldier) -> void:
	if not surrendered or captured or not soldier.alive:
		return
	captured = true
	_captor = by
	soldier.set_meta("captured", true)
	# abgegebene Waffen (Original: Waffe wird fallengelassen) – Munition bleibt beim Durchsuchen erhältlich
	for i in soldier.weapons.size():
		var w := soldier.weapons[i]
		if w and w.data.action != WeaponData.Action.MELEE:
			soldier.set_meta("surrendered_weapons", soldier.get_meta("surrendered_weapons", []) + [w])
			soldier.weapons[i] = null
	soldier._on_weapon_switched()
	Events.say("%s ist gefangen." % soldier.soldier_name, 2.5)
	# Gefangener zählt für Skripte als ausgeschaltet (_ACTOR_GetState 0) -> auch OnDeath (Zähler wie CZECH3
	# „dummy_reinforcement“ brauchen sonst jeden Toten). ANNAHME: Original-Ereignis bei Gefangennahme nicht dekodiert.
	if runtime and is_instance_valid(runtime) and not soldier.has_meta("death_notified"):
		soldier.set_meta("death_notified", true)
		runtime.notify(soldier, "ONDEATH")


## Leicheninhalt/Taschen eines Gefangenen übernehmen (wie Pickups.Loot)
func search(by: Soldier) -> String:
	var total := 0
	for cw in soldier.get_meta("surrendered_weapons", []):
		var w0 := cw as Weapon
		if w0 == null or w0.data.slot == WeaponData.Slot.GRENADE:
			continue
		for w in by.weapons:
			if w and w.data.caliber == w0.data.caliber and w0.total_ammo() > 0:
				var got := w.add_ammo(w0.total_ammo())
				w0.reserve = maxi(w0.reserve - got, 0)
				total += got
	var taken: Array[String] = []
	for oid in soldier.get_meta("orig_loot", []):
		taken.append(OrigInteractive.give_item(by, int(oid)))
	soldier.set_meta("orig_loot", [])
	var parts: Array[String] = []
	if total > 0:
		parts.append("%d Schuss" % total)
	parts.append_array(taken)
	return ", ".join(parts) if not parts.is_empty() else "nichts Brauchbares"


## Uniform eines Gefangenen anziehen (Original T7044, nur lebende Gefangene); Uniform zählt als Gegenstand
func give_uniform(to: Soldier) -> bool:
	if not captured or uniform_taken or not soldier.alive or to.disguised:
		return false
	uniform_taken = true
	# Original-Figur der Uniform (Modell des Gefangenen, z. B. ge01a) übergeben: Soldier tauscht nur die Figur
	var fig: Node3D = null
	var m := Game.current_mission()
	if soldier.has_meta("orig_model") and m and m.get("orig") != null:
		fig = m.orig.character_instance(String(soldier.get_meta("orig_model")))
	to.put_on_uniform(soldier.uniform_color, soldier.helmet_style, fig)
	to.set_meta("uniform_figure", String(soldier.get_meta("orig_model", "")))
	if soldier.has_meta("orig_uniform"):
		var inv: Array = to.get_meta("orig_items", [])
		inv.append(int(soldier.get_meta("orig_uniform")))
		to.set_meta("orig_items", inv)
	return true


## Benutzen am Gegner: Gefangennehmen -> Durchsuchen -> Uniform benutzen
class CaptureAction extends Interactable:
	var brain: EnemyBrain
	var searched := false

	func _ready() -> void:
		super._ready()
		enabled = false

	func _physics_process(_d: float) -> void:
		var s := brain.soldier
		if s == null:
			return
		global_position = s.global_position + Vector3.UP * 0.9
		enabled = s.alive and (brain.surrendered or brain.captured)
		if brain.captured:
			prompt = OrigInteractive.text(7044, "Uniform benutzen") if searched else OrigInteractive.text(7043, "Suchen & Mun. sammeln")
		else:
			prompt = OrigInteractive.text(7038, "Gefangennehmen")

	func can_interact(s: Soldier) -> bool:
		var live := brain.soldier != null and brain.soldier.alive and (brain.surrendered or brain.captured)
		if not live or s.team != Soldier.TEAM_ALLIED or s.vehicle != null:
			return false
		if brain.captured and searched:
			return not brain.uniform_taken and not s.disguised
		return true

	func interact(s: Soldier) -> void:
		if not can_interact(s):
			return
		if not brain.captured:
			brain.capture(s)
		elif not searched:
			searched = true
			Events.say("Durchsucht: %s" % brain.search(s), 2.5)
		elif brain.give_uniform(s):
			Events.say("%s trägt jetzt eine feindliche Uniform. Nicht schießen, Abstand halten!" % s.soldier_name, 4.0)
		super.interact(s)


# --- Waffenstellungen / Bordwaffen ----------------------------------------------------

## Besetzte Stellung bzw. Waffensitz im Fahrzeug: nicht bewegen, sichtbare Feinde bekämpfen (Zombie-Modus: nur zielen)
func _mounted_tick(delta: float) -> void:
	_script_tick_stance_only()
	perception.forget_dead()
	var t := perception.best_target()
	if t == null and is_instance_valid(target) and target.alive and perception.awareness.get(target, 0.0) >= 1.0 \
			and perception.visible_now.get(target, false):
		t = target
	if t and not script_control:
		if state != State.COMBAT:
			target = t
			_stimulus = AL_SEE
			set_state(State.COMBAT)
		target = t
		engage(t, delta)
	else:
		cease_fire()
		if script_look_at.is_finite():
			look_at_point(script_look_at + Vector3.UP * 1.5, delta, 2.0)


func _script_tick_stance_only() -> void:
	soldier.move_input = Vector3.ZERO
	_move_target = Vector3.INF


## ANNAHME: Ein Gegner, dessen Ausgangsposition höchstens 3 m neben einer freien Waffenstellung liegt (vom Leveldesign
## als Bedienung platziert), besetzt sie, sobald er kämpft. Skriptgesteuert: HUMAN_BoardVehicle(Stellung, 1, 0).
func _try_autonomous_mount(delta: float) -> bool:
	_mount_check -= delta
	if _mount_check > 0.0 or soldier.mounted != null or soldier.vehicle != null or Net.is_online:
		return false
	_mount_check = 1.0
	if _mount_target == null:
		for n in get_tree().get_nodes_in_group("emplacements"):
			if n.has_method("can_ai_mount") and n.can_ai_mount(soldier) and (n as Node3D).global_position.distance_to(home_pos) < 3.0:
				_mount_target = n
				break
	if _mount_target == null or not is_instance_valid(_mount_target) or not _mount_target.can_ai_mount(soldier):
		_mount_target = null
		return false
	var spot: Vector3 = _mount_target.gunner_spot()
	if distance_to(spot) < 2.5:
		stop_moving()
		_mount_target.mount(soldier)
		_mount_target = null
		return true
	move_to(spot, Soldier.MoveMode.RUN)
	return true


func serialize() -> Dictionary:
	return {"state": state, "alert": alert_level, "patrol_index": patrol_index, "morale": morale,
		"surrendered": surrendered, "captured": captured, "uniform_taken": uniform_taken}


func deserialize(d: Dictionary) -> void:
	alert_level = d.get("alert", 0.0)
	morale = float(d.get("morale", morale))
	uniform_taken = bool(d.get("uniform_taken", false))
	if bool(d.get("surrendered", false)) or bool(d.get("captured", false)):
		surrender(null)
		if bool(d.get("captured", false)):
			captured = true
			soldier.set_meta("captured", true)
			for i in soldier.weapons.size():
				if soldier.weapons[i] and soldier.weapons[i].data.action != WeaponData.Action.MELEE:
					soldier.weapons[i] = null
		return
	patrol_index = int(d.get("patrol_index", 0)) % maxi(patrol_points.size(), 1)
	var s := int(d.get("state", state))
	# Kampf-/Suchzustände werden nach dem Laden als Suche fortgesetzt
	if s == State.COMBAT or s == State.INVESTIGATE:
		s = State.SEARCH
		investigate_pos = soldier.global_position
	set_state(s)
