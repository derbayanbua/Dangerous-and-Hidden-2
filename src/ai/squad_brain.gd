class_name SquadBrain
extends AIBrain
## KI eines nicht direkt gesteuerten Teammitglieds.
## Befehle (Original: Squad-Signale FORMATION_*, Befehlsmenü "command*"):
##   FOLLOW  – Formationsplatz relativ zum Anführer einnehmen
##   HOLD    – Position halten
##   MOVE    – zu einem Punkt bewegen, dort halten
## Feuerregel: FIRE_AT_WILL (selbstständig feuern) / HOLD_FIRE (nur bei Beschuss).

enum Order { FOLLOW, HOLD, MOVE }
enum ROE { FIRE_AT_WILL, HOLD_FIRE }

const ORDER_NAMES := ["Folgen", "Halten", "Bewegen"]

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


func setup(s: Soldier) -> void:
	super.setup(s)
	reaction_time = 0.5
	accuracy_skill = 0.6
	hold_pos = s.global_position
	perception.target_detected.connect(_on_detected)
	s.damaged.connect(func(_a, _z): _under_fire = 4.0)


func set_order(o: int, pos := Vector3.ZERO) -> void:
	order = o
	_cover = Vector3.INF
	match o:
		Order.HOLD:
			hold_pos = soldier.global_position
			hold_yaw = soldier.look_yaw
			stop_moving()
		Order.MOVE:
			hold_pos = pos
			move_to(pos, Soldier.MoveMode.RUN)
		Order.FOLLOW:
			pass


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive or soldier.is_player_controlled:
		return
	_under_fire = maxf(_under_fire - delta, 0.0)
	_report_cooldown = maxf(_report_cooldown - delta, 0.0)
	perception.forget_dead()
	var leader := squad.leader() if squad else null

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
		if tv and (roe == ROE.FIRE_AT_WILL or _under_fire > 0.0) and soldier.seat_index > 0:
			engage(tv, delta)
		else:
			cease_fire()
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
	var may_fire := roe == ROE.FIRE_AT_WILL or _under_fire > 0.0
	if t and may_fire:
		_target = t
		_no_target_time = 0.0
		# Unter Beschuss oder bei nahem Feind: Deckung in der Nähe suchen
		# (nicht während eines Bewegungsbefehls)
		if order != Order.MOVE and not _cover.is_finite() \
				and (_under_fire > 0.0 or distance_to(t.global_position) < 45.0):
			var anchor := soldier.global_position
			_cover = find_cover(t.global_position + Vector3.UP * 1.5, 5.0 if order == Order.HOLD else 8.0, 0.0)
			if _cover.is_finite() and anchor.distance_to(_cover) > 1.0:
				move_to(_cover, Soldier.MoveMode.RUN)
			else:
				_cover = anchor
		if has_move_target() and order != Order.MOVE and _cover.is_finite() and not arrived(1.0):
			pass   # läuft in Deckung, feuert dabei
		elif order != Order.MOVE or arrived(1.5):
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
				var slot := squad.formation_slot(soldier, leader)
				var d := distance_to(slot)
				if d > 1.5:
					var mode := Soldier.MoveMode.RUN if d > 8.0 else leader.move_mode
					# Anführer schleicht (geduckt/liegend) -> Kameraden schleichen mit
					if (leader.move_mode == Soldier.MoveMode.SNEAK or leader.stance != Soldier.Stance.STAND) and d < 15.0:
						mode = Soldier.MoveMode.SNEAK
					move_to(slot, mode)
				elif not has_move_target():
					# in Blickrichtung des Anführers sichern
					soldier.look_yaw = rotate_toward(soldier.look_yaw, leader.look_yaw + squad.slot_watch_offset(soldier), delta * 3.0)
		Order.HOLD:
			if distance_to(hold_pos) > 1.5:
				move_to(hold_pos, Soldier.MoveMode.RUN)
			elif not has_move_target():
				soldier.look_yaw = rotate_toward(soldier.look_yaw, hold_yaw, delta * 3.0)
		Order.MOVE:
			if not has_move_target() and distance_to(hold_pos) > 1.5:
				move_to(hold_pos, Soldier.MoveMode.RUN)
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)
	update_movement(delta, true)


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


func order_name() -> String:
	return ORDER_NAMES[order]


func serialize() -> Dictionary:
	return {"order": order, "roe": roe, "hold": [hold_pos.x, hold_pos.y, hold_pos.z], "stance": stance_override}


func deserialize(d: Dictionary) -> void:
	order = int(d.get("order", Order.FOLLOW))
	roe = int(d.get("roe", ROE.FIRE_AT_WILL))
	stance_override = int(d.get("stance", -1))
	var h: Array = d.get("hold", [0, 0, 0])
	hold_pos = Vector3(h[0], h[1], h[2])
