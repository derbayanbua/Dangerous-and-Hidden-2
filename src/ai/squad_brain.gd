class_name SquadBrain
extends AIBrain
## KI eines nicht direkt gesteuerten Teammitglieds.
## Befehle (Original: Squad-Signale FORMATION_*, Befehlsmenü "command*"):
##   FOLLOW  – Formationsplatz relativ zum Anführer einnehmen
##   HOLD    – Position halten
##   MOVE    – zu einem Punkt bewegen, dort halten
##   COVER   – in der Nähe Deckung suchen und dort halten (Befehlsmenü „In Deckung“)
## Feuerregel: FIRE_AT_WILL (selbstständig feuern) / HOLD_FIRE (nur bei Beschuss) /
##   ON_MY_LEAD (Original „Auf mein Komm. feuern“: erst feuern, wenn der Anführer schießt).
## Befehlsmenü (src/ui/command_menu.gd, docs/re_notes_commands.md): zusätzlich leise Ausführung (quiet),
## Deckungsfeuer, Raketenwerfer-Ziel, Aktion an einem Objekt, Taktik-Plan anhalten/fortsetzen.

enum Order { FOLLOW, HOLD, MOVE, COVER }
enum ROE { FIRE_AT_WILL, HOLD_FIRE, ON_MY_LEAD }

const ORDER_NAMES := ["Folgen", "Halten", "Bewegen", "Deckung"]

var squad: SquadManager
var order: int = Order.FOLLOW
var roe: int = ROE.FIRE_AT_WILL
var hold_pos := Vector3.ZERO
var hold_yaw := 0.0
var stance_override := -1        ## -1 = Haltung des Anführers übernehmen
var _target: Soldier
var _under_fire := 0.0
var _report_cooldown := 0.0
var grenade_target := Vector3.INF   ## Granatbefehl (wird ausgeführt, sobald in Reichweite)
var _cover := Vector3.INF        ## gewählte Deckung im laufenden Gefecht
var _no_target_time := 0.0
var quiet := false               ## leiser Befehl (Schl. Bewegung/Stiller Angriff): schleichend ausführen
var strict_hold := false         ## „Position halten“: Platz nicht für Deckung verlassen
var plan := false                ## Bewegungsbefehl aus der taktischen Karte (Original: Taktik-Plan)
var plan_paused := false         ## Taktik-Befehl „Halten“ (bis „Weiter“)
var suppress_point := Vector3.INF   ## Deckungsfeuer auf diesen Punkt
var suppress_time := 0.0
var launcher_target := Vector3.INF  ## Raketenwerfer auf diesen Punkt einsetzen
var _launch_time := 0.0
var _launch_ammo := 0
var action_target: Node3D = null    ## Aktion (Öffnen/Benutzen/Erste Hilfe …) an diesem Objekt
var action_kind := ""


func setup(s: Soldier) -> void:
	super.setup(s)
	reaction_time = 0.5
	accuracy_skill = 0.6
	direct_when_off_mesh = true     # Befehle auch abseits des Navigationsnetzes ausführen (Ersatz, kein Originalverhalten)
	hold_pos = s.global_position
	perception.target_detected.connect(_on_detected)
	s.damaged.connect(func(_a, _z): _under_fire = 4.0)
	Events.soldier_died.connect(_on_any_death)


func set_order(o: int, pos := Vector3.ZERO, quiet_mode := false) -> void:
	order = o
	_cover = Vector3.INF
	quiet = quiet_mode
	strict_hold = false
	plan = false
	plan_paused = false
	match o:
		Order.HOLD:
			hold_pos = soldier.global_position
			hold_yaw = soldier.look_yaw
			stop_moving()
		Order.MOVE:
			hold_pos = pos
			move_to(pos, _move_mode())
		Order.COVER:
			var threat := threat_point()
			var c := find_cover(threat, 10.0, 0.0)
			hold_pos = c if c.is_finite() else soldier.global_position
			var to := threat - hold_pos
			hold_yaw = atan2(-to.x, -to.z)
			move_to(hold_pos, _move_mode())
		Order.FOLLOW:
			pass


func _move_mode() -> int:
	return Soldier.MoveMode.SNEAK if quiet else Soldier.MoveMode.RUN


## Vermutete Feindrichtung: bekanntes Ziel, sonst Blickrichtung des Anführers (30 m).
func threat_point() -> Vector3:
	var t: Soldier = perception.best_target() if perception else null
	if t:
		return t.global_position + Vector3.UP * 1.5
	var lead: Soldier = squad.leader() if squad else null
	var ref: Soldier = lead if lead and lead != soldier else soldier
	return ref.eye_position() + ref.forward() * 30.0


## Feuern erlaubt? (Feuerregel, Beschuss, „Auf mein Kommando“ = Anführer hat gerade geschossen)
func _may_fire(_leader: Soldier) -> bool:
	if roe == ROE.FIRE_AT_WILL or _under_fire > 0.0:
		return true
	return roe == ROE.ON_MY_LEAD and _lead_fire_window > 0.0


## „Auf mein Kommando“: Schuss des Anführers erkennen (Spielzeit-Fenster 3 s nach seinem letzten Schuss, Annahme)
var _lead_fire_window := 0.0
var _lead_last_shot := -100.0
var _lead_ref: Soldier = null


func _track_leader_fire(leader: Soldier, delta: float) -> void:
	_lead_fire_window = maxf(_lead_fire_window - delta, 0.0)
	if leader != _lead_ref:
		_lead_ref = leader
		_lead_last_shot = leader.last_shot_time if leader else -100.0
	elif leader and leader.last_shot_time != _lead_last_shot:
		_lead_last_shot = leader.last_shot_time
		_lead_fire_window = 3.0


## Aufgaben aus dem Befehlsmenü abbrechen (Neu sammeln, neuer Befehl).
func clear_tasks() -> void:
	grenade_target = Vector3.INF
	suppress_time = 0.0
	suppress_point = Vector3.INF
	launcher_target = Vector3.INF
	action_target = null
	action_kind = ""
	_kill_time = 0.0


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive or soldier.is_player_controlled:
		return
	_under_fire = maxf(_under_fire - delta, 0.0)
	_report_cooldown = maxf(_report_cooldown - delta, 0.0)
	perception.forget_dead()
	var leader := squad.leader() if squad else null
	_track_leader_fire(leader, delta)

	# Haltung: Befehl oder wie der Anführer
	var want_stance := stance_override
	if want_stance < 0 and leader:
		want_stance = leader.stance
	if want_stance < 0:
		want_stance = Soldier.Stance.STAND

	# Fahrzeug: mit dem Anführer ein- und aussteigen (Original: HUMAN_BoardVehicle)
	if leader and order == Order.FOLLOW:
		if leader.vehicle != null and soldier.vehicle == null:
			var v: Vehicle = leader.vehicle
			if distance_to(v.global_position) < 3.5:
				if not v.board(soldier):
					set_order(Order.HOLD)   # kein Platz mehr: zurückbleiben
					Events.say("%s: \"Kein Platz – ich halte hier.\"" % soldier.soldier_name, 2.0)
			elif distance_to(v.global_position) < 40.0:
				move_to(v.global_position, Soldier.MoveMode.RUN)
				update_movement(delta, true)
				return
		elif leader.vehicle == null and soldier.vehicle != null:
			soldier.vehicle.leave(soldier)
	if soldier.vehicle != null:
		# Mitfahrer: nicht laufen, aber auf Feinde feuern (Feuerregel beachten)
		var tv := perception.best_target()
		if tv and _may_fire(leader) and soldier.seat_index > 0:
			engage(tv, delta)
		else:
			cease_fire()
		return

	# Befehlsmenü-Aufgaben: Raketenwerfer, Deckungsfeuer, Aktion an einem Objekt
	if launcher_target.is_finite():
		_do_launcher(delta)
		return
	if suppress_time > 0.0:
		_do_suppress(delta)
		return
	if action_target != null and _do_action(delta):
		return

	# Granatbefehl hat Vorrang: in Wurfweite gehen, dann werfen
	if grenade_target.is_finite():
		var gd := distance_to(grenade_target)
		if gd > 26.0:
			var dir := (grenade_target - soldier.global_position).normalized()
			move_to(grenade_target - dir * 22.0, Soldier.MoveMode.RUN)
			update_movement(delta, true)
			return
		stop_moving()
		soldier.stance_request = mini(soldier.stance_request, Soldier.Stance.CROUCH)
		if throw_grenade_at(grenade_target):
			Events.say("%s: \"Granate!\"" % soldier.soldier_name, 2.0)
			grenade_target = Vector3.INF
		elif soldier.grenade_cooldown <= 0.0:
			Events.say("%s: \"Kein Wurf möglich!\"" % soldier.soldier_name, 2.0)
			grenade_target = Vector3.INF
		return

	# Feindkontakt
	var t := perception.best_target()
	var may_fire := _may_fire(leader)
	if t and may_fire:
		_target = t
		_no_target_time = 0.0
		# Unter Beschuss oder bei nahem Feind: Deckung in der Nähe suchen
		# (nicht während eines Bewegungsbefehls, nicht bei „Position halten“/„In Deckung“)
		if order != Order.MOVE and order != Order.COVER and not strict_hold and not _cover.is_finite() \
				and (_under_fire > 0.0 or distance_to(t.global_position) < 45.0):
			var anchor := soldier.global_position
			_cover = find_cover(t.global_position + Vector3.UP * 1.5, 5.0 if order == Order.HOLD else 8.0, 0.0)
			if _cover.is_finite() and anchor.distance_to(_cover) > 1.0:
				move_to(_cover, Soldier.MoveMode.RUN)
			else:
				_cover = anchor
		if has_move_target() and order != Order.MOVE and _cover.is_finite() and not arrived(1.0):
			pass   # läuft in Deckung, feuert dabei
		elif (order != Order.MOVE and order != Order.COVER) or arrived(1.5) or plan_paused:
			stop_moving()
		soldier.stance_request = maxi(want_stance, Soldier.Stance.CROUCH) if want_stance != Soldier.Stance.PRONE else Soldier.Stance.PRONE
		engage(t, delta)
		update_movement(delta, false)
		return
	_target = null
	_no_target_time += delta
	if _no_target_time > 6.0:
		_cover = Vector3.INF   # Gefecht vorbei: Deckung freigeben
	cease_fire()
	soldier.stance_request = want_stance
	if order == Order.COVER and stance_override < 0:
		soldier.stance_request = maxi(want_stance, Soldier.Stance.CROUCH)
	_reload_if_needed()
	# Selbstversorgung außerhalb des Gefechts
	if soldier.health < soldier.max_health * 0.5 and soldier.medkits > 0 and soldier.heal_time_left <= 0.0 \
			and _no_target_time > 3.0:
		stop_moving()
		soldier.start_heal([])
	if soldier.heal_time_left > 0.0:
		return

	match order:
		Order.FOLLOW:
			if leader:
				_follow(leader, delta)
		Order.HOLD, Order.COVER:
			if distance_to(hold_pos) > 1.5:
				move_to(hold_pos, _move_mode())
			elif not has_move_target():
				soldier.look_yaw = rotate_toward(soldier.look_yaw, hold_yaw, delta * 3.0)
		Order.MOVE:
			if plan_paused:
				stop_moving()
			elif not has_move_target() and distance_to(hold_pos) > 1.5:
				move_to(hold_pos, _move_mode())
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)
	update_movement(delta, true)
	if order == Order.FOLLOW:
		_keep_apart(delta)


## Folgen (B-019): Formationsplatz nach den Originaltabellen (SquadManager.formation_slots: Abstand, Trennung 1,2 m,
## Heften an den Boden). Zusätzlich [E, Vorgabe „keine Klumpen“]: lebende Kameraden näher als SEPARATION schieben
## sich auseinander; wer festhängt (kein Fortschritt zum Platz), folgt erst der Spur des Anführers, dann seitlich
## versetzt, zuletzt kurz ohne Kollision mit Kameraden.
const FOLLOW_TOL := 1.5            ## Platz erreicht [E]
const TRAIL_STEP := 1.0            ## Spurpunkt des Anführers alle 1 m [E]
const STUCK_FOLLOW := 2.5          ## s ohne Fortschritt → Lösen [E]
var _trail: Array[Vector3] = []
var _follow_best := INF
var _follow_stuck := 0.0
var _unstick_stage := 0
var _unstick_time := 0.0
var _unstick_target := Vector3.INF
var follow_unsticks := 0           ## Zähler für Tests


func _record_trail(leader: Soldier) -> void:
	var p := leader.global_position
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(p) >= TRAIL_STEP:
		_trail.append(p)
		if _trail.size() > 60:
			_trail.remove_at(0)


func _follow(leader: Soldier, delta: float) -> void:
	_record_trail(leader)
	var slot := squad.formation_slot(soldier, leader)
	var d := distance_to(slot)
	# Lösen aus einer Blockade: Ersatzziel ansteuern, bis Zeit um oder erreicht
	if _unstick_time > 0.0:
		_unstick_time -= delta
		var wall_follow := _unstick_stage == 2 or _unstick_stage == 3
		# Umgehen (Wand entlang): sobald der Weg zum Platz frei ist, direkt hin
		if wall_follow and _unstick_time < UNSTICK_TIME - 0.4 and _clear_path(soldier.global_position, slot):
			_unstick_time = 0.0
		elif _unstick_target.is_finite() and _unstick_time > 0.0:
			if distance_to(_unstick_target) <= 1.0 and wall_follow:
				_unstick_target = _free_step(slot, false)    # weiter in dieselbe Richtung (Bonus letzte Richtung)
			if distance_to(_unstick_target) > 1.0:
				move_to(_unstick_target, Soldier.MoveMode.RUN)
				return
		_unstick_time = 0.0
		_unstick_target = Vector3.INF
	if d > FOLLOW_TOL:
		var mode := Soldier.MoveMode.RUN if d > 8.0 else leader.move_mode
		# Anführer schleicht (geduckt/liegend) bzw. leiser Befehl -> Kameraden schleichen mit
		if (quiet or leader.move_mode == Soldier.MoveMode.SNEAK or leader.stance != Soldier.Stance.STAND) and d < 15.0:
			mode = Soldier.MoveMode.SNEAK
		move_to(slot, mode)
		# Fortschritt zum Platz messen (der Platz wandert mit dem Anführer → Abstand statt Weg)
		if d < _follow_best - 0.3:
			_follow_best = d
			_follow_stuck = 0.0
			_unstick_stage = 0
		else:
			# nur „fest“, wenn er sich selbst kaum bewegt (läuft er dem davonlaufenden Platz hinterher, ist alles gut)
			var v := Vector2(soldier.velocity.x, soldier.velocity.z).length()
			_follow_stuck += delta if v < 0.6 else -delta
			_follow_stuck = maxf(_follow_stuck, 0.0)
			_follow_best = minf(_follow_best + delta * 0.2, d)   # langsam vergessen
		if _follow_stuck > STUCK_FOLLOW:
			_unstick(leader, slot)
	else:
		_follow_best = d
		_follow_stuck = 0.0
		_unstick_stage = 0
		if has_move_target() and arrived(FOLLOW_TOL):
			stop_moving()
		if not has_move_target():
			# auf dem Platz: in die Platzrichtung (Pfeil fächert auf) sichern
			soldier.look_yaw = rotate_toward(soldier.look_yaw, leader.look_yaw + squad.slot_watch_offset(soldier), delta * 3.0)


## Stufenweise lösen: 1 Spur des Anführers, 2 seitlich versetzter Platz, 3 kurz ohne Kollision mit Kameraden.
func _unstick(leader: Soldier, slot: Vector3) -> void:
	_follow_stuck = 0.0
	_follow_best = distance_to(slot)     # erst echter Fortschritt zum Platz setzt die Stufe zurück
	_unstick_stage += 1
	follow_unsticks += 1
	match _unstick_stage:
		1:
			# letzter Spurpunkt, der deutlich näher am Anführer liegt als ich
			_unstick_target = leader.global_position
			for k in range(_trail.size() - 1, -1, -1):
				if _trail[k].distance_to(soldier.global_position) > 2.0 and _trail[k].distance_to(leader.global_position) < 12.0:
					_unstick_target = _trail[k]
					break
		2, 3:
			# freie Richtung suchen (8 Strahlen in Brusthöhe), die am wenigsten vom Platz wegführt
			_unstick_target = _free_step(slot, _unstick_stage == 3)
			if _unstick_stage == 3:
				soldier.jump_or_climb()
		_:
			_unstick_stage = 0
			_unstick_target = slot
			for m in squad.members:
				if m != soldier and m.alive:
					soldier.add_collision_exception_with(m)
					soldier.get_tree().create_timer(2.0, false).timeout.connect(_end_pass_through.bind(soldier, m))
	_unstick_time = UNSTICK_TIME if _unstick_stage != 1 else 3.0


const UNSTICK_TIME := 6.0          ## s je Lösungsversuch [E]

## Ist der Weg (Kapselbreite: drei Strahlen in Hüfthöhe) von a nach b frei von Weltgeometrie?
func _clear_path(a: Vector3, b: Vector3) -> bool:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.1:
		return true
	var side := dir.normalized().cross(Vector3.UP) * 0.28
	var space := soldier.get_world_3d().direct_space_state
	for off in [Vector3.ZERO, side, -side]:
		var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.9 + off, b + Vector3.UP * 0.9 + off, 1 | 16)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


var _last_free_dir := Vector3.ZERO

## Ausweichpunkt: unter 12 Richtungen die freie (≥ 2,5 m bis zum Hindernis), die dem Platz am nächsten zeigt; mit
## `second` die zweitbeste (anderer Umweg). Die zuletzt genommene Richtung wird bevorzugt beibehalten (Wand entlang).
func _free_step(slot: Vector3, second: bool) -> Vector3:
	var space := soldier.get_world_3d().direct_space_state
	var from := soldier.global_position + Vector3.UP * 1.0
	var want := slot - soldier.global_position
	want.y = 0.0
	want = want.normalized() if want.length() > 0.01 else Vector3.FORWARD
	var cands: Array = []
	for k in 12:
		var dir := want.rotated(Vector3.UP, TAU * k / 12.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0, 1 | 2 | 16)
		q.exclude = [soldier.get_rid()]
		var hit := space.intersect_ray(q)
		var free := 4.0 if hit.is_empty() else from.distance_to(hit["position"])
		if free < 2.5:
			continue
		var score := dir.dot(want) + (0.6 if dir.dot(_last_free_dir) > 0.8 else 0.0)
		cands.append([score, dir, free])
	if cands.is_empty():
		return soldier.global_position - want * 2.0
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var pick: Array = cands[1] if second and cands.size() > 1 else cands[0]
	_last_free_dir = pick[1]
	return soldier.global_position + (pick[1] as Vector3) * minf(float(pick[2]) - 0.6, 3.5)


## Abstand zu Kameraden halten (keine Klumpen): näher als SEPARATION → seitlich wegschieben.
func _keep_apart(_delta: float) -> void:
	var push := Vector3.ZERO
	var lead := squad.leader()
	var order_list: Array = squad._followers(lead) if lead else []
	var my_i := order_list.find(soldier)
	for m in squad.members:
		if m == soldier or not m.alive or m.vehicle != null:
			continue
		# Vorrang nach Platz: Anführer und kleinere Platznummer haben Vorrang, nur der Nachrangige weicht aus
		# (sonst schieben sich zwei Kameraden in einer Engstelle gegenseitig an die Wand)
		if m != lead and order_list.find(m) > my_i:
			continue
		var dv := soldier.global_position - m.global_position
		dv.y = 0.0
		var l := dv.length()
		if l < SquadManager.SEPARATION and absf(soldier.global_position.y - m.global_position.y) < 1.5:
			push += (dv / maxf(l, 0.05) if l > 0.01 else Vector3(1, 0, 0).rotated(Vector3.UP, soldier.look_yaw)) \
				* (SquadManager.SEPARATION - l)
	if push.length() > 0.05:
		if not has_move_target():
			soldier.move_mode = Soldier.MoveMode.WALK
		var mi := soldier.move_input + push.normalized() * minf(push.length() * 1.5, 1.0)
		mi.y = 0.0
		soldier.move_input = mi.normalized() if mi.length() > 1.0 else mi


## „Raketenwerfer einsetzen“: Werfer nehmen, auf den Punkt richten, einen Schuss abgeben, zurück zur Hauptwaffe.
func _do_launcher(delta: float) -> void:
	var w: Weapon = soldier.weapons[WeaponData.Slot.LAUNCHER] if soldier.weapons.size() > WeaponData.Slot.LAUNCHER else null
	_launch_time += delta
	if w == null or (w.total_ammo() <= 0 and _launch_ammo <= 0) or _launch_time > 10.0:
		_end_launcher()
		return
	stop_moving()
	update_movement(delta, false)
	if soldier.current_slot != WeaponData.Slot.LAUNCHER:
		soldier.select_slot(WeaponData.Slot.LAUNCHER)
		_launch_ammo = w.total_ammo()
	if w.total_ammo() < _launch_ammo:
		_end_launcher()          # Schuss ist raus
		return
	look_at_point(launcher_target, delta, 5.0)
	soldier.aim_point = launcher_target
	soldier.has_aim_point = true
	soldier.aiming = true
	soldier.extra_spread = 0.0
	if w.in_mag == 0:
		soldier.trigger = false
		if not w.is_reloading():
			soldier.reload()
		return
	soldier.trigger = _launch_time > 0.8 and facing_error(launcher_target) < 0.06 and not soldier.trigger


func _end_launcher() -> void:
	launcher_target = Vector3.INF
	_launch_time = 0.0
	_launch_ammo = 0
	soldier.trigger = false
	if soldier.current_slot == WeaponData.Slot.LAUNCHER:
		if not soldier.select_slot(WeaponData.Slot.PRIMARY):
			soldier.select_slot(WeaponData.Slot.SIDEARM)


func start_launcher(p: Vector3) -> bool:
	var w: Weapon = soldier.weapons[WeaponData.Slot.LAUNCHER] if soldier.weapons.size() > WeaponData.Slot.LAUNCHER else null
	if w == null or w.total_ammo() <= 0:
		return false
	launcher_target = p
	_launch_time = 0.0
	_launch_ammo = w.total_ammo()
	return true


## „Deckungsfeuer“: einige Sekunden Feuerstöße auf den befohlenen Punkt.
func _do_suppress(delta: float) -> void:
	suppress_time -= delta
	stop_moving()
	update_movement(delta, false)
	var w := soldier.current_weapon()
	if w == null or w.data.slot == WeaponData.Slot.GRENADE or w.data.slot == WeaponData.Slot.LAUNCHER \
			or w.data.slot == WeaponData.Slot.MELEE:
		_switch_to_any_loaded()
		w = soldier.current_weapon()
	if suppress_time <= 0.0 or w == null:
		suppress_time = 0.0
		cease_fire()
		return
	look_at_point(suppress_point, delta, 6.0)
	soldier.aim_point = suppress_point
	soldier.has_aim_point = true
	soldier.aiming = true
	soldier.extra_spread = 1.5
	if w.in_mag == 0:
		soldier.trigger = false
		if not w.is_reloading():
			soldier.reload()
		return
	_handle_bursts(w, facing_error(suppress_point) < 0.12, delta, distance_to(suppress_point))


## Aktion an einem Objekt: hingehen (leise bei stillem Befehl), dann benutzen bzw. Erste Hilfe leisten.
## Rückgabe false = nichts mehr zu tun (normales Verhalten fortsetzen).
func _do_action(delta: float) -> bool:
	if not is_instance_valid(action_target):
		action_target = null
		return false
	var p := action_target.global_position
	if action_kind == "kill":
		return _do_kill(delta)
	if action_kind == "grenade_room":
		# Granate durch die Tür in den Raum: Punkt 3 m hinter der Tür (vom Werfer aus) [E]
		var away := p - soldier.global_position
		away.y = 0.0
		grenade_target = p + away.normalized() * 3.0
		if action_target is OrigInteractive.OrigDoor:
			(action_target as OrigInteractive.OrigDoor).ai_open(soldier)
		action_target = null
		action_kind = ""
		return false
	var flat := p - soldier.global_position
	flat.y = 0.0
	var reach := 1.5 if action_kind == "heal" else (1.0 if action_kind == "silent_kill" else 1.6)
	if flat.length() > reach:
		var mode := _move_mode()
		if action_kind == "silent_kill":
			mode = Soldier.MoveMode.SNEAK if flat.length() < 8.0 else mode
		move_to(p, mode)
		update_movement(delta, true)
		return true
	stop_moving()
	update_movement(delta, false)
	var target := action_target
	var kind := action_kind
	action_target = null
	action_kind = ""
	match kind:
		"heal":
			soldier.start_heal([target])
		"open", "close":
			var want_open := kind == "open"
			if target is Interactable and bool(target.get("is_open")) != want_open:
				(target as Interactable).interact(soldier)
		"lock":
			if target is OrigInteractive.OrigDoor:
				(target as OrigInteractive.OrigDoor).set_locked(true)
		"unlock":
			if target is OrigInteractive.OrigDoor and bool(target.get("locked")):
				(target as OrigInteractive.OrigDoor).interact(soldier)
		"clear_room":
			# Hineingehen & räumen: Tür öffnen, 3 m hinein, Feuer frei [E]
			if target is OrigInteractive.OrigDoor:
				(target as OrigInteractive.OrigDoor).ai_open(soldier)
			elif target is Interactable and not bool(target.get("is_open")):
				(target as Interactable).interact(soldier)
			var into := target.global_position - soldier.global_position
			into.y = 0.0
			roe = ROE.FIRE_AT_WILL
			set_order(Order.MOVE, target.global_position + into.normalized() * 3.0, quiet)
		"capture", "search", "uniform":
			var eb := _enemy_brain_of(target)
			if eb:
				match kind:
					"capture":
						eb.capture(soldier)
					"search":
						if eb.capture_action:
							eb.capture_action.set("searched", true)
						Events.say("Durchsucht: %s" % eb.search(soldier), 2.5)
					"uniform":
						eb.give_uniform(soldier)
			elif kind == "search" and target is Soldier:
				_loot(target as Soldier)
		"items":
			if target is Soldier and not (target as Soldier).alive:
				_loot(target as Soldier)
			elif target is Soldier:
				# Gegenstände eines Lebenden (Kamerad/Gefangener): Originalgegenstände übernehmen [E]
				var inv: Array = soldier.get_meta("orig_items", [])
				for it in (target as Soldier).get_meta("orig_items", []):
					inv.append(it)
				(target as Soldier).set_meta("orig_items", [])
				soldier.set_meta("orig_items", inv)
		"silent_kill":
			var t := target as Node3D
			if t is Soldier and (t as Soldier).alive:
				look_at_point((t as Soldier).global_position + Vector3.UP, 1.0, 50.0)
				if soldier.weapons.size() > WeaponData.Slot.MELEE and soldier.weapons[WeaponData.Slot.MELEE] != null:
					soldier.select_slot(WeaponData.Slot.MELEE)
					soldier.trigger = true
					get_tree().create_timer(0.3, false).timeout.connect(func(): if is_instance_valid(soldier): soldier.trigger = false)
				else:
					action_target = t
					action_kind = "kill"
		_:
			if target is Interactable and (target as Interactable).can_interact(soldier):
				(target as Interactable).interact(soldier)
	return true


var _kill_time := 0.0

## „Töten“: in Schussweite mit Sichtlinie gehen, dann bekämpfen, bis das Ziel tot ist (max. 20 s) [E].
func _do_kill(delta: float) -> bool:
	var t := action_target as Node3D
	var alive := t != null and ((t is Soldier and (t as Soldier).alive) or (t is Dog and bool(t.get("alive"))))
	_kill_time += delta
	if not alive or _kill_time > 20.0:
		action_target = null
		action_kind = ""
		_kill_time = 0.0
		cease_fire()
		return false
	if t is Soldier:
		var ts := t as Soldier
		if distance_to(ts.global_position) > 30.0 or not _clear_line(soldier.eye_position(), ts.global_position + Vector3.UP * 1.0):
			move_to(ts.global_position, _move_mode())
			update_movement(delta, true)
			return true
		stop_moving()
		update_movement(delta, false)
		engage(ts, delta)
	else:
		suppress_point = t.global_position + Vector3.UP * 0.4
		suppress_time = 2.0
	return true


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _enemy_brain_of(n: Node) -> EnemyBrain:
	if n == null:
		return null
	for c in n.get_children():
		if c is EnemyBrain:
			return c
	return null


func _loot(corpse: Soldier) -> void:
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Pickups.Loot and (n as Pickups.Loot).corpse == corpse and (n as Interactable).can_interact(soldier):
			(n as Interactable).interact(soldier)
			return


func _reload_if_needed() -> void:
	var w := soldier.current_weapon()
	if w and w.data.slot != WeaponData.Slot.GRENADE and w.in_mag < w.data.magazine_size * 0.5:
		soldier.reload()


func _on_detected(t: Soldier) -> void:
	if _report_cooldown > 0.0 or soldier.is_player_controlled:
		return
	_report_cooldown = 8.0
	var dir := t.global_position - soldier.global_position
	var bearing := int(round(fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0) / 10.0)) * 10
	Events.say("%s: Feind gesichtet, %d°, %d m!" % [soldier.soldier_name, bearing, int(dir.length())], 3.0)
	# Originalaufnahme „Enemy Sighted / There They Are“ (speech.set English #Teamplatz, Ereignis 92)
	OrigAudio.speak_event(soldier, OrigAudio.EV_ENEMY_SIGHTED, 3.0)


## Kamerad hat einen Gegner getötet: „Enemy Killed / He's Dead“ (speech.set Ereignis 106)
func _on_any_death(s: Node, attacker: Node) -> void:
	if attacker == soldier and s != soldier and soldier.alive and not soldier.is_player_controlled \
			and s is Soldier and (s as Soldier).team != soldier.team:
		OrigAudio.speak_event(soldier, OrigAudio.EV_ENEMY_KILLED, 3.0)


func order_name() -> String:
	return ORDER_NAMES[order]


func serialize() -> Dictionary:
	return {"order": order, "roe": roe, "hold": [hold_pos.x, hold_pos.y, hold_pos.z], "stance": stance_override,
		"quiet": quiet, "strict": strict_hold, "plan": plan, "paused": plan_paused}


func deserialize(d: Dictionary) -> void:
	order = int(d.get("order", Order.FOLLOW))
	roe = int(d.get("roe", ROE.FIRE_AT_WILL))
	quiet = bool(d.get("quiet", false))
	strict_hold = bool(d.get("strict", false))
	plan = bool(d.get("plan", false))
	plan_paused = bool(d.get("paused", false))
	stance_override = int(d.get("stance", -1))
	var h: Array = d.get("hold", [0, 0, 0])
	hold_pos = Vector3(h[0], h[1], h[2])
