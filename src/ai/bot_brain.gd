class_name BotBrain
extends EnemyBrain
## Mehrspieler-KI-Soldat (läuft nur auf dem Server, Net). Nutzt die Einzelspieler-Gegner-KI (EnemyBrain:
## schrittweise Erkennung über Sicht/Gehör inkl. Tarnung, Deckung, Herausschauen, Granaten) und ergänzt:
##  - feste Rollen (Waffen): Sturmsoldat (schweres MG), Sanitäter (versorgt Verwundete), Panzerabwehr
##    (Raketenwerfer), Scharfschütze, Schleicher (Schalldämpfer, Messer von hinten)
##  - Persönlichkeiten (BotTraits, nach Rolle und tatsächlicher Waffe): Camper, Flankierer, Deckungsfeuer,
##    Scharfschütze, Schütze
##  - Wegfindung (BotNav): Route über das Netz mit Zwischenpunkten an Deckungen, Erreichbarkeit, gestufte
##    Abhilfe bei Festhängen, keine Pendelbewegungen (feste Zielgewichtung + Hysterese)
##  - Zielwahl (BotGoals): Zonen angreifen/verteidigen/halten (FRONTLINE beachtet), Aufgabenobjekte benutzen bzw.
##    verteidigen, Gegner suchen
##  - Trupp (BotSquad, bis 4): Führer wählt das Ziel, Mitglieder in Formation mit 5–15 m Abstand bzw. als Kolonne,
##    getrennte Deckungen, Sprünge unter Feindbedrohung (ein Element sichert, das andere rückt vor), Feuer und
##    Bewegung (Deckungsfeuer hält nieder, Flankierer rückt vor und wirft Granaten), Rückzug bei Verwundung/
##    Unterzahl, Sanitäter versorgt
## Kein „Aimbot“: Reaktionszeit, Streuung und Erkennung wie bei den Einzelspieler-Gegnern.

enum Role { ASSAULT, MEDIC, AT, SNIPER, SNEAKER }
const ROLE_NAMES := ["Sturmsoldat", "Sanitäter", "Panzerabwehr", "Scharfschütze", "Schleicher"]
const ZONE_KINDS := ["attack_zone", "defend_zone", "hold_zone"]
const CONTACT_MEMORY := 25.0     ## s: so lange gilt eine gemeldete Feindlage als Bedrohung für den Trupp

var role: int = Role.ASSAULT
var persona: int = BotTraits.Trait.RIFLEMAN
var group: Array = []            ## BotBrains der Gruppe, erstes lebendes Mitglied = Führer
var slot := 0                    ## Platz in der Formation
var goal := Vector3.INF
var goal_kind := ""              ## attack_zone, defend_zone, hold_zone, use_obj, defend_obj, hunt, test
var goal_zone := -1
var goal_obj := -1
var goal_cost := 0.0
var goal_reachable := true
var goal_log: Array = []         ## je Ziel {kind, zone, obj, set_t, reach_t, dist}
var hold_pos := Vector3.INF      ## Halteplatz/Stellung am Ziel
var test_goal := Vector3.INF     ## Tests: festes Ziel des Führers
var nav := BotNav.new()
# --- Gruppendaten (gepflegt beim Führer) ---
var contact_pos := Vector3.INF
var contact_t := -1000.0
var suppress_until := -1000.0    ## Deckungsfeuer läuft bis (Spielzeit)
var trail := PackedVector3Array()
var bound_phase := 0
var _bound_t := 0.0
# --- Statistik (Tests/Debug) ---
var bursts := 0
var burst_log: Array = []        ## [Spielzeit, Schuss] je Feuerstoß
var relocations := 0
var grenades_thrown := 0
var flank_count := 0
var retreats := 0
var uses := 0
# --- intern ---
var _goal_t := 0.0
var _check_t := 0.0
var _holding := false
var _use_t := 0.0
var _used := {}
var _slot_t := 0.0
var _slot_pos := Vector3.INF
var _hold_t := 0.0
var _spot := Vector3.INF
var _spot_t := 0.0
var _shots_here := 0
var _shots_limit := 2
var _bursts_here := 0
var _sb_left := 0
var _pos_t := 0.0
var _relocating := false
var _retreat_t := 0.0
var _retreat_cd := 0.0
var _hit_t := -1000.0
var _seen_t := -1000.0
var _flanks := 0
var _blacklist := {}             ## Zielschlüssel -> gesperrt bis (Spielzeit)
var _travel_t := -1000.0
var _plan_t := -1000.0


func setup(s: Soldier) -> void:
	super.setup(s)
	patrol_points = PackedVector3Array()
	state = State.GUARD
	persona = BotTraits.pick(role, s)
	match persona:
		BotTraits.Trait.FLANKER:
			ai_mode = Mode.AGGRESSIVE
		BotTraits.Trait.RIFLEMAN:
			ai_mode = Mode.AGGRESSIVE if role == Role.ASSAULT else Mode.DEFENSIVE
		_:
			ai_mode = Mode.DEFENSIVE
	if persona == BotTraits.Trait.SNIPER or role == Role.SNIPER:
		perception.sight_range = 150.0
		_base_sight = 150.0
	elif persona == BotTraits.Trait.CAMPER:
		perception.sight_range = 90.0
		_base_sight = 90.0
	if role == Role.SNEAKER:
		s.skill_stealth = maxf(s.skill_stealth, 80.0)
	var w: Weapon = s.weapons[WeaponData.Slot.PRIMARY] if not s.weapons.is_empty() else null
	if w and persona == BotTraits.Trait.SUPPORT and w.data.can_toggle_auto:
		w.auto_mode = true                   # MG im Dauerfeuer (Feuerstöße steuert die KI)
	s.shot_fired.connect(_on_shot)
	_shots_limit = randi_range(1, 2)
	if Game.cli.has("bot_debug"):
		BotDebug.enabled = true
	if BotDebug.enabled:
		_debug_ensure.call_deferred()


func _exit_tree() -> void:
	BotSquad.release(self)


func _debug_ensure() -> void:
	BotDebug.ensure()


static func now() -> float:
	return BotGoals.now()


func leader() -> BotBrain:
	for b in group:
		if is_instance_valid(b) and b.soldier and b.soldier.alive:
			return b
	return self


func is_leader() -> bool:
	return leader() == self


func _group_alive() -> int:
	var n := 0
	for b in group:
		if is_instance_valid(b) and b.soldier and b.soldier.alive:
			n += 1
	return maxi(n, 1)


func _group_has(p: int) -> bool:
	for b in group:
		if is_instance_valid(b) and b != self and b.soldier and b.soldier.alive and b.persona == p:
			return true
	return false


## Feindlage melden (Gruppe): Bedrohungsrichtung für Sprünge/Deckungsroute
func _note_contact(p: Vector3) -> void:
	var l := leader()
	l.contact_pos = p
	l.contact_t = now()


func _group_threat() -> Vector3:
	var l := leader()
	return l.contact_pos if now() - l.contact_t < CONTACT_MEMORY else Vector3.INF


func _goal_key() -> String:
	return "%s:%d:%d" % [goal_kind, goal_zone, goal_obj]


func _on_shot(_w) -> void:
	_shots_here += 1


# --- Physik: Bewegung mit Abstand, Festhängen ------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not enabled or soldier == null or not soldier.alive or suspended:
		return
	if soldier.vehicle != null or soldier.mounted != null:
		return
	var wants := has_move_target() and not soldier.is_climbing() and soldier.heal_time_left <= 0.0
	match nav.track(soldier, delta, wants):
		1:
			soldier.jump_or_climb()
		2:
			nav.sidestep(soldier, _move_target if _move_target.is_finite() else goal)
		3:
			_repath = 0.0
			if _move_target.is_finite():
				agent.target_position = _move_target
			if is_leader() and state != State.COMBAT and goal.is_finite():
				nav.plan(soldier, goal, Vector3.INF, false)
		4:
			_give_up()
		5:
			nav.nudge(soldier, _move_target)


## Wie AIBrain.update_movement, aber: Ausweichen zu nahen Kameraden (kein Aufeinanderkleben), Ausweichpunkt bei
## Festhängen, kein Abbruch des Ziels nach 2,5 s Stillstand (das übernimmt BotNav gestuft)
func update_movement(delta: float, face_move := true) -> void:
	_repath -= delta
	if not _move_target.is_finite():
		var sep0 := BotSquad.separation(self, 1.8)
		soldier.move_input = sep0 * 0.6 if sep0.length() > 0.05 else Vector3.ZERO
		return
	if arrived(agent.target_desired_distance):
		stop_moving()
		return
	var dir := Vector3.ZERO
	if nav.side_t > 0.0 and nav.side_pos.is_finite():
		dir = nav.side_pos - soldier.global_position
	else:
		dir = agent.get_next_path_position() - soldier.global_position
		dir.y = 0.0
		if dir.length() < 0.05:
			dir = _move_target - soldier.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var mv := dir + BotSquad.separation(self) * 0.7
	mv.y = 0.0
	soldier.move_input = mv.normalized() if mv.length() > 0.1 else dir
	_open_doors_ahead(delta, dir)
	if face_move and dir.length() > 0.1:
		_turn_towards_dir(dir, delta, 6.0)


## Festhängen nicht behebbar: Ziel (Führer) bzw. Platz (Mitglied) bzw. Deckung (Gefecht) aufgeben
func _give_up() -> void:
	if state == State.COMBAT:
		_cover_pos = Vector3.INF
		stop_moving()
	elif is_leader() and goal.is_finite() and not _holding:
		_blacklist[_goal_key()] = now() + 45.0
		_reselect_goal(true)
	else:
		_slot_pos = Vector3.INF
		_slot_t = 0.0
		hold_pos = Vector3.INF
		_spot = Vector3.INF
		stop_moving()


# --- Deckungssuche mit getrennten Deckungen (überschreibt AIBrain für BotBrain) ---------------------

func find_cover_around(center: Vector3, threat_eye: Vector3, max_radius: float) -> Vector3:
	var space := soldier.get_world_3d().direct_space_state
	var origin := soldier.global_position
	var best := Vector3.INF
	var best_score := -INF
	for i in COVER_SAMPLES:
		var ang := TAU * float(i) / COVER_SAMPLES + randf() * 0.3
		var p := BotNav.closest(soldier, center + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, max_radius))
		if BotSquad.too_close(self, p, 4.0):
			continue                 # nicht in die Deckung eines Kameraden
		var q := PhysicsRayQueryParameters3D.create(threat_eye, p + Vector3.UP * 0.9, 1)
		if space.intersect_ray(q).is_empty():
			continue
		var score := -origin.distance_to(p) * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.55, threat_eye, 1)
		if space.intersect_ray(q2).is_empty():
			score += 6.0
		score -= absf(p.distance_to(threat_eye) - 25.0) * 0.1
		if score > best_score:
			best_score = score
			best = p
	if best.is_finite():
		BotSquad.claim(self, best)
	return best


# --- außerhalb des Gefechts: Ziel ansteuern / dem Führer folgen ------------------------------------

func _guard(delta: float) -> void:
	_advance(delta)


func _patrol(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	soldier.trigger = false
	soldier.aiming = false
	if role == Role.MEDIC and _medic(delta):
		return
	var lead := leader()
	if lead == self:
		_lead_tick(delta)
	else:
		_member_tick(delta, lead)


func _lead_tick(delta: float) -> void:
	_record_trail()
	_goal_t -= delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.5
		var valid := _goal_valid()
		if not goal.is_finite() or not valid or _goal_t <= 0.0:
			_reselect_goal(not valid or not goal.is_finite())
	if not goal.is_finite():
		stop_moving()
		soldier.look_yaw += sin(_state_time * 0.5) * delta * 0.8
		return
	if at_goal():
		_mark_reached()
	if _holding and soldier.global_position.distance_to(goal) > 110.0:
		_holding = false             # weit abgedrängt: zurück zum Ziel
	if _holding:
		_hold(delta)
	else:
		_travel(delta)


func _travel(delta: float) -> void:
	var threat := _group_threat()
	# neu planen: neues Ziel, Rückkehr aus Gefecht/Untersuchen (sonst Rückweg zu passierten Zwischenpunkten =
	# Pendeln) oder alle 25 s (Bedrohungslage für die Deckungsroute)
	if nav.waypoints.is_empty() or nav.dest.distance_to(goal) > 1.0 or now() - _travel_t > 1.0 or now() - _plan_t > 25.0 \
			or (not nav.planned_on_nav and BotNav.nav_ready(soldier)):
		goal_reachable = nav.plan(soldier, goal, threat, true)
		_plan_t = now()
	_travel_t = now()
	var tgt := nav.steer(soldier)
	if not nav.reachable and nav.wp_i >= nav.waypoints.size() - 1 and BotNav.flat(soldier.global_position, tgt) < 2.5:
		# Ziel über das Netz nicht erreichbar: nächster Punkt erreicht → anderes Ziel
		_blacklist[_goal_key()] = now() + 45.0
		_reselect_goal(true)
		return
	if _bounding_hold(delta, threat):
		return
	soldier.stance_request = Soldier.Stance.STAND
	var mode: int = Soldier.MoveMode.JOG
	if threat.is_finite() and soldier.stamina > 40.0:
		mode = Soldier.MoveMode.RUN          # unter Bedrohung: Sprung von Deckung zu Deckung
	move_to(tgt, mode)


## Unter Feindbedrohung in Sprüngen vorrücken: ein Element (gerade/ungerade Plätze) sichert, das andere läuft
func _bounding_hold(delta: float, threat: Vector3) -> bool:
	if not threat.is_finite() or _group_alive() < 2:
		return false
	var lead := leader()
	if lead == self:
		_bound_t -= delta
		if _bound_t <= 0.0:
			_bound_t = 6.0
			bound_phase = 1 - bound_phase
	if slot % 2 == lead.bound_phase:
		return false
	stop_moving()
	soldier.stance_request = Soldier.Stance.CROUCH
	soldier.aiming = true
	look_at_point(threat + Vector3.UP * 1.2, delta, 3.0)
	return true


func _member_tick(delta: float, lead: BotBrain) -> void:
	_sync_goal(lead)
	# Mitglied gilt als angekommen: selbst im Ziel oder der Führer hält dort und der Trupp ist heran (≤ 25 m)
	if goal.is_finite() and (at_goal() or (lead._holding and soldier.global_position.distance_to(goal) < 25.0)):
		_mark_reached()
	if goal.is_finite() and (lead._holding or _holding) and soldier.global_position.distance_to(goal) < 110.0:
		_holding = true
		_hold(delta)
		return
	if _bounding_hold(delta, _group_threat()):
		return
	_slot_t -= delta
	if _slot_t <= 0.0 or not _slot_pos.is_finite():
		_slot_t = 1.5
		_slot_pos = _formation_point(lead)
	var d := distance_to(_slot_pos)
	if d > 3.5 or (has_move_target() and d > 1.2):
		soldier.stance_request = Soldier.Stance.STAND
		move_to(_slot_pos, Soldier.MoveMode.RUN if d > 30.0 and soldier.stamina > 40.0 else Soldier.MoveMode.JOG)
	else:
		stop_moving()
		soldier.look_yaw = rotate_toward(soldier.look_yaw, lead.soldier.look_yaw + (float(slot) - 1.5) * 0.6, delta * 2.0)


## Ziel des Führers übernehmen (Mitglieder; wird beim Führerwechsel nahtlos fortgesetzt)
func _sync_goal(lead: BotBrain) -> void:
	if lead.goal_kind == goal_kind and lead.goal_zone == goal_zone and lead.goal_obj == goal_obj \
			and (not lead.goal.is_finite() or lead.goal.distance_to(goal) < 1.0):
		return
	goal = lead.goal
	goal_kind = lead.goal_kind
	goal_zone = lead.goal_zone
	goal_obj = lead.goal_obj
	_holding = false
	hold_pos = Vector3.INF
	_spot = Vector3.INF
	if goal.is_finite():
		goal_log.append({"kind": goal_kind, "zone": goal_zone, "obj": goal_obj, "set_t": now(), "reach_t": -1.0,
			"dist": soldier.global_position.distance_to(goal)})


## Formationsplatz: Keil mit 7 m Seitenabstand hinter dem Führer (Laufrichtung); wo das nicht passt (Gasse, Gebäude,
## anderes Stockwerk) Kolonne auf der Spur des Führers; immer mit Mindestabstand zu Kameraden
func _formation_point(lead: BotBrain) -> Vector3:
	var ls := lead.soldier
	var v := Vector3(ls.velocity.x, 0, ls.velocity.z)
	var yaw: float = atan2(-v.x, -v.z) if v.length() > 0.5 else ls.look_yaw
	var off: Vector3 = BotSquad.SLOT_OFFSETS[slot % BotSquad.SLOT_OFFSETS.size()]
	if persona == BotTraits.Trait.SNIPER:
		off = off * 1.6 + Vector3(0, 0, 6)
	var want := ls.global_position + Basis(Vector3.UP, yaw) * off
	var q := BotNav.closest(soldier, want)
	var ok := BotNav.flat(q, want) < 2.5 and absf(q.y - ls.global_position.y) < 4.0 \
		and BotNav.path_cost(soldier, ls.global_position, q) < off.length() * 1.8 + 3.0
	if not ok:
		q = BotNav.closest(soldier, lead.trail_point(6.0 * float(maxi(slot, 1))))
	q = BotSquad.spread_point(self, q, BotSquad.MIN_SPACING, 10.0)
	BotSquad.claim(self, q)
	return q


func _record_trail() -> void:
	var p := soldier.global_position
	if trail.is_empty() or BotNav.flat(trail[trail.size() - 1], p) > 2.0:
		trail.append(p)
		if trail.size() > 40:
			trail.remove_at(0)


## Punkt auf der zurückgelegten Spur, back Meter hinter dem Führer
func trail_point(back: float) -> Vector3:
	var acc := 0.0
	var prev := soldier.global_position
	for i in range(trail.size() - 1, -1, -1):
		acc += prev.distance_to(trail[i])
		prev = trail[i]
		if acc >= back:
			return trail[i]
	return trail[0] if not trail.is_empty() else soldier.global_position


# --- Ziel ------------------------------------------------------------------------------------------

func at_goal() -> bool:
	if not goal.is_finite():
		return false
	var p := soldier.global_position
	if goal_kind in ZONE_KINDS:
		var m = Game.current_mission()
		if m and m.has_method("mp_zones") and goal_zone >= 0 and goal_zone < m.mp_zones().size():
			return BotGoals.in_zone(m.mp_zones()[goal_zone], p) or BotNav.flat(p, goal) < 2.5
	return BotNav.flat(p, goal) < 2.5 and absf(p.y - goal.y) < 2.5


func _mark_reached() -> void:
	_holding = true
	if not goal_log.is_empty() and float(goal_log[goal_log.size() - 1]["reach_t"]) < 0.0:
		goal_log[goal_log.size() - 1]["reach_t"] = now()


func _goal_valid() -> bool:
	if test_goal.is_finite():
		return goal.is_finite() and goal.distance_to(test_goal) < 0.5
	var m = Game.current_mission()
	if m == null or not goal.is_finite():
		return false
	match goal_kind:
		"attack_zone":
			return goal_zone < Net.zone_owner.size() and int(Net.zone_owner[goal_zone]) != soldier.team \
				and Net._attackable(m, goal_zone, soldier.team)
		"defend_zone":
			return goal_zone < Net.zone_owner.size() and int(Net.zone_owner[goal_zone]) == soldier.team \
				and (not _holding or BotGoals.zone_threatened(self, m, goal_zone))
		"hold_zone":
			return goal_zone < Net.zone_owner.size() and int(Net.zone_owner[goal_zone]) == soldier.team
		"use_obj", "defend_obj":
			return not Net.obj_done.has(goal_obj)
		"hunt":
			return not _holding
	return true


func _reselect_goal(force: bool) -> void:
	_goal_t = 12.0
	if test_goal.is_finite():
		if not goal.is_finite() or goal.distance_to(test_goal) > 0.5:
			_set_goal({"pos": test_goal, "kind": "test", "zone": -1, "obj": -1, "cost": 0.0, "key": "test:-1:-1"})
		return
	var r := BotGoals.choose(self)
	var best: Dictionary = r.get("best", {})
	if best.is_empty():
		goal = Vector3.INF
		goal_kind = ""
		return
	var cur: Dictionary = r.get("current", {})
	# Hysterese: beim bisherigen Ziel bleiben, solange kein deutlich besseres existiert (kein Pendeln)
	if not force and not cur.is_empty() and (best["key"] == cur["key"] or float(best["cost"]) > float(cur["cost"]) - 40.0):
		goal_cost = float(cur["cost"])
		if (cur["pos"] as Vector3).distance_to(goal) > 1.0:
			goal = cur["pos"]          # Zielpunkt präzisiert (z. B. erst nach fertigem Navigationsnetz auf dem Netz)
			nav.clear()
		return
	_set_goal(best)


func _set_goal(g: Dictionary) -> void:
	var pos: Vector3 = g["pos"]
	var changed: bool = String(g["key"]) != _goal_key() or not goal.is_finite() or pos.distance_to(goal) > 1.0
	goal = pos
	goal_kind = String(g["kind"])
	goal_zone = int(g["zone"])
	goal_obj = int(g["obj"])
	goal_cost = float(g["cost"])
	goal_reachable = bool(g.get("reachable", true))
	if changed:
		goal_log.append({"kind": goal_kind, "zone": goal_zone, "obj": goal_obj, "set_t": now(), "reach_t": -1.0,
			"dist": soldier.global_position.distance_to(goal)})
		_holding = false
		hold_pos = Vector3.INF
		_spot = Vector3.INF
		nav.clear()


# --- am Ziel: halten, Stellung, Aufgabe ------------------------------------------------------------

func _hold(delta: float) -> void:
	var lead_user := goal_kind == "use_obj" and is_leader() and _objective_pending()
	if lead_user:
		# Führer benutzt das Aufgabenobjekt (z. B. Sprengsatz anbringen: 3 s am Objekt bleiben)
		if distance_to(goal) > 1.0:
			soldier.stance_request = Soldier.Stance.STAND
			move_to(goal, Soldier.MoveMode.JOG)
		else:
			stop_moving()
			soldier.stance_request = Soldier.Stance.CROUCH
		_use_objective(delta, false)
		return
	match persona:
		BotTraits.Trait.CAMPER:
			_camp(delta, 8.0, 28.0, false)
		BotTraits.Trait.SNIPER:
			_camp(delta, 30.0, 70.0, true)
		_:
			_hold_in_area(delta)
	if goal_kind == "use_obj":
		_use_objective(delta, false)
	elif goal_kind == "defend_obj":
		_defend_objective(delta)


func _objective_pending() -> bool:
	if Net.obj_done.has(goal_obj):
		return false
	var it: Interactable = BotGoals.objective_interactable(get_tree(), goal) if goal.is_finite() else null
	if it is OrigInteractive.OrigExplosive:
		return _expl_wanted(it as OrigInteractive.OrigExplosive, false)
	return true


func _hold_in_area(delta: float) -> void:
	var m = Game.current_mission()
	var z: Dictionary = {}
	var center := goal
	var rmin := 2.0
	var rmax := 10.0
	if goal_kind in ZONE_KINDS and m and m.has_method("mp_zones") and goal_zone >= 0 and goal_zone < m.mp_zones().size():
		z = m.mp_zones()[goal_zone]
		rmin = 0.0
		rmax = minf(BotGoals.zone_radius(z) * 0.8, 14.0)
	elif goal_kind in ["defend_obj", "use_obj"]:
		rmin = 6.0
		rmax = 14.0
		var it := BotGoals.objective_interactable(get_tree(), goal)
		if it is OrigInteractive.OrigExplosive and (it as OrigInteractive.OrigExplosive).state == 1:
			rmin = (it as OrigInteractive.OrigExplosive).radius + 3.0        # Ladung scharf: Abstand halten
			rmax = rmin + 6.0
	elif goal_kind == "hunt":
		stop_moving()
		soldier.look_yaw += delta * 0.9
		_goal_t = minf(_goal_t, 3.0)       # kurz umsehen, dann weitersuchen
		return
	_hold_t -= delta
	if not hold_pos.is_finite() or _hold_t <= 0.0 or (rmin > 3.0 and BotNav.flat(hold_pos, center) < rmin - 0.5):
		_hold_t = randf_range(20.0, 35.0)
		var threat := _group_threat()
		if not threat.is_finite() and m:
			threat = BotGoals.threat_dir_point(self, m, center)
		var h := BotGoals.hold_spot(self, center, z, rmin, rmax, threat)
		if not h.is_finite():
			h = BotSquad.spread_point(self, BotNav.closest(soldier, center), BotSquad.MIN_SPACING, 10.0)
		hold_pos = h
		BotSquad.claim(self, hold_pos)
	if distance_to(hold_pos) > 1.2:
		soldier.stance_request = Soldier.Stance.STAND
		move_to(hold_pos, Soldier.MoveMode.JOG)
	else:
		stop_moving()
		soldier.stance_request = Soldier.Stance.CROUCH
		var face := _group_threat()
		if not face.is_finite() and m:
			face = BotGoals.threat_dir_point(self, m, center)
		if face.is_finite():
			var to := face - soldier.global_position
			soldier.look_yaw = rotate_toward(soldier.look_yaw, atan2(-to.x, -to.z) + sin(_state_time * 0.4) * 0.6, delta * 1.5)
		else:
			soldier.look_yaw += sin(_state_time * 0.5) * delta * 0.8


## Camper/Scharfschütze: verdeckte Stellung mit Sichtlinie auf Zone/Objekt (Zufahrten), lange halten, wechseln
func _camp(delta: float, rmin: float, rmax: float, high: bool) -> void:
	var m = Game.current_mission()
	var center := goal
	_spot_t -= delta
	if not _spot.is_finite() or _spot_t <= 0.0:
		var threat: Vector3 = BotGoals.threat_dir_point(self, m, center) if m else Vector3.INF
		var s := BotGoals.overwatch_spot(self, center, rmin, rmax, high, _spot, threat)
		if not s.is_finite():
			_spot_t = 8.0
			_hold_in_area(delta)
			return
		if _spot.is_finite():
			relocations += 1
		_spot = s
		_spot_t = randf_range(60.0, 120.0) if persona == BotTraits.Trait.CAMPER else randf_range(45.0, 90.0)
		hold_pos = s
		BotSquad.claim(self, s)
	var d := distance_to(_spot)
	if d > 1.2:
		var near := d < 18.0 and persona == BotTraits.Trait.CAMPER
		soldier.stance_request = Soldier.Stance.CROUCH if near else Soldier.Stance.STAND
		move_to(_spot, Soldier.MoveMode.SNEAK if near else Soldier.MoveMode.JOG)
	else:
		stop_moving()
		soldier.stance_request = Soldier.Stance.CROUCH
		var to := center - soldier.global_position
		soldier.look_yaw = rotate_toward(soldier.look_yaw, atan2(-to.x, -to.z) + sin(_state_time * 0.3) * 0.5, delta * 1.5)


## Am Ziel: Aufgabe erfüllen (Sprengsatz anbringen, Schalter, Funkgerät, Gegenstand …); keine Türen/Leitern/Kisten
func _use_objective(delta: float, defend: bool) -> void:
	_use_t -= delta
	if _use_t > 0.0:
		return
	_use_t = 1.5
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not BotGoals.usable_kind(it) or it.global_position.distance_to(soldier.global_position) > 3.0:
			continue
		if not it.can_interact(soldier):
			continue
		if it is OrigInteractive.OrigExplosive:
			var ex := it as OrigInteractive.OrigExplosive
			if not _expl_wanted(ex, defend):
				continue
			if ex.state == 0:
				BotGoals.armed_by[ex.get_instance_id()] = soldier.team
			else:
				BotGoals.armed_by.erase(ex.get_instance_id())
		elif defend:
			continue
		elif float(_used.get(it.get_instance_id(), -100.0)) > now() - 30.0:
			continue               # Schalter nicht gleich wieder umlegen
		it.interact(soldier)
		Net.used_interactable_by(soldier, it)
		_used[it.get_instance_id()] = now()
		uses += 1
		return


## Sprengplatz benutzen? Angreifer: anbringen (frei) bzw. fremde/von Anfang an scharfe Ladung entschärfen;
## Verteidiger: nur vom Gegner angebrachte Ladungen entschärfen
func _expl_wanted(ex: OrigInteractive.OrigExplosive, defend: bool) -> bool:
	var by := int(BotGoals.armed_by.get(ex.get_instance_id(), -1))
	if defend:
		return ex.state == 1 and by != -1 and by != soldier.team
	return ex.state == 0 or (ex.state == 1 and by != soldier.team)


## Verteidiger: scharfe gegnerische Ladung am Aufgabenobjekt entschärfen (nächster Verteidiger geht hin)
func _defend_objective(delta: float) -> void:
	var it := BotGoals.objective_interactable(get_tree(), goal)
	if not (it is OrigInteractive.OrigExplosive) or not _expl_wanted(it as OrigInteractive.OrigExplosive, true):
		return
	var nearest := true
	for b in group:
		if is_instance_valid(b) and b != self and b.soldier.alive and b.distance_to(it.global_position) < distance_to(it.global_position):
			nearest = false
	if not nearest:
		return
	if distance_to(goal) > 1.0:
		move_to(goal, Soldier.MoveMode.RUN)
	else:
		stop_moving()
		_use_objective(delta, true)


## Sanitäter: verwundete Teamkameraden (Spieler und KI) in der Nähe versorgen
func _medic(_delta: float) -> bool:
	if soldier.medkits <= 0 or soldier.heal_time_left > 0.0:
		return soldier.heal_time_left > 0.0
	var best: Soldier = null
	var bd := 30.0
	for t in BotSquad.team_soldiers(get_tree(), soldier.team):
		if t != soldier and t.health < t.max_health * 0.6:
			var d := distance_to(t.global_position)
			if d < bd:
				bd = d
				best = t
	if best == null:
		return false
	if bd > 1.6:
		move_to(best.global_position, Soldier.MoveMode.RUN if soldier.stamina > 40.0 else Soldier.MoveMode.JOG)
		return true
	stop_moving()
	soldier.look_yaw = atan2(-(best.global_position.x - soldier.global_position.x), -(best.global_position.z - soldier.global_position.z))
	soldier.start_heal([best])
	return true


# --- Untersuchen/Suchen: kurz, danach zurück zum Spielziel -------------------------------------------

func _investigate(delta: float) -> void:
	soldier.aiming = true
	if _state_time < 1.0:
		stop_moving()
		look_at_point(investigate_pos + Vector3.UP, delta, 3.0)
		return
	var d := distance_to(investigate_pos)
	if _state_time < 8.0 and d > 4.0 and d < 35.0:
		soldier.stance_request = Soldier.Stance.STAND
		move_to(investigate_pos, Soldier.MoveMode.WALK)
		return
	if _state_time < 10.0:
		stop_moving()
		soldier.look_yaw += delta * 1.2
		return
	set_state(State.GUARD)


func _search(delta: float) -> void:
	soldier.aiming = true
	if _state_time > 14.0:
		set_state(State.GUARD)
		return
	if _state_time < 10.0 and distance_to(investigate_pos) > 4.0:
		move_to(investigate_pos, Soldier.MoveMode.JOG)
	else:
		stop_moving()
		soldier.look_yaw += delta * 1.2


# --- Gefecht ---------------------------------------------------------------------------------------

func _combat(delta: float) -> void:
	_choose_weapon()
	perception.forget_dead()
	var visible := perception.best_target()
	if visible:
		target = visible
		_no_los_time = 0.0
		_seen_t = now()
	else:
		_no_los_time += delta
	if target == null or not is_instance_valid(target) or not target.alive:
		target = null
		cease_fire()
		set_state(State.GUARD)
		return
	var tpos: Vector3 = perception.last_known.get(target, target.global_position)
	if visible:
		_note_contact(tpos)
	_pos_t += delta
	if _retreat_tick(delta, visible, tpos):
		return
	if role == Role.MEDIC and not visible and _medic(delta):
		return
	match persona:
		BotTraits.Trait.SUPPORT:
			_combat_support(delta, visible, tpos)
		BotTraits.Trait.FLANKER:
			_combat_flanker(delta, visible, tpos)
		BotTraits.Trait.SNIPER:
			_combat_sniper(delta, visible, tpos)
		BotTraits.Trait.CAMPER:
			_combat_camper(delta, visible, tpos)
		_:
			super._combat(delta)


## In Deckung gehen (falls noch keine); true = in Deckung angekommen
func _cover_step(delta: float, visible: Soldier, tpos: Vector3, radius: float, bias: float) -> bool:
	var threat_eye := tpos + Vector3.UP * 1.5
	if not _cover_pos.is_finite() and _state_time > 0.2:
		var c := find_cover(threat_eye, radius, bias)
		_cover_pos = c if c.is_finite() else soldier.global_position
		if c.is_finite():
			move_to(c, Soldier.MoveMode.RUN)
	var in_cover := _cover_pos.is_finite() and distance_to(_cover_pos) < 1.5
	if not in_cover and has_move_target():
		_move_in_combat(delta, visible, move_fire_range)
		return false
	if not in_cover:
		_cover_pos = soldier.global_position
	stop_moving()
	return true


## Unterwegs im Gefecht: bei Sicht in Reichweite im Laufschritt aus der Hüfte feuern, sonst rennen
func _move_in_combat(delta: float, visible: Soldier, fire_range: float) -> void:
	_pos_t = 0.0
	soldier.stance_request = Soldier.Stance.STAND
	if visible and distance_to(visible.global_position) < fire_range:
		soldier.move_mode = Soldier.MoveMode.JOG
		engage(visible, delta)
		soldier.aiming = false
	else:
		soldier.move_mode = Soldier.MoveMode.RUN if soldier.stamina > 20.0 else Soldier.MoveMode.JOG
		cease_fire()
		_turn_towards_dir((agent.get_next_path_position() - soldier.global_position).normalized(), delta, 8.0)


## Herausschauen und Feuern im Wechsel mit Abducken (wie EnemyBrain)
func _peek_fire(delta: float, visible: Soldier, tpos: Vector3) -> void:
	var threat_eye := tpos + Vector3.UP * 1.5
	_peek_timer -= delta
	if _peek_timer <= 0.0:
		_peeking = not _peeking
		_peek_timer = randf_range(1.8, 3.5) if _peeking else randf_range(1.0, 2.2)
	if _peeking or not visible:
		soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
		if visible:
			engage(visible, delta)
		else:
			cease_fire()
			look_at_point(threat_eye, delta, 4.0)
	else:
		soldier.stance_request = Soldier.Stance.CROUCH
		cease_fire()
		var w := soldier.current_weapon()
		if w and w.in_mag < w.data.magazine_size * 0.4:
			soldier.reload()


## Deckung seitlich versetzt (Stellungswechsel), INF wenn keine
func _lateral_cover(tpos: Vector3, rmin: float, rmax: float) -> Vector3:
	var to_t := tpos - soldier.global_position
	to_t.y = 0.0
	var first: float = -1.0 if randf() < 0.5 else 1.0
	for side: float in [first, -first]:
		var perp := Vector3(-to_t.z, 0, to_t.x).normalized() * side
		var c := find_cover_around(soldier.global_position + perp * randf_range(rmin, rmax), tpos + Vector3.UP * 1.5, 4.0)
		if c.is_finite() and BotNav.flat(c, soldier.global_position) > 3.5:
			return c
	return Vector3.INF


func _group_contact_age() -> float:
	return now() - leader().contact_t


## Deckungsfeuer (MG): bleibt in Deckung, Feuerstöße auf den Feind bzw. dessen letzte bekannte Lage
## (Niederhalten), Stellungswechsel nach einigen Feuerstößen
func _combat_support(delta: float, visible: Soldier, tpos: Vector3) -> void:
	if not _cover_step(delta, visible, tpos, 9.0, 0.0):
		return
	var threat_eye := tpos + Vector3.UP * 1.5
	if _bursts_here >= 3 + (slot % 2) or (_pos_t > 16.0 and _bursts_here >= 1):
		_bursts_here = 0
		_pos_t = 0.0
		var c := _lateral_cover(tpos, 5.0, 12.0)
		if c.is_finite():
			_cover_pos = c
			relocations += 1
			cease_fire()
			move_to(c, Soldier.MoveMode.RUN)
			return
	if visible:
		soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
		engage(visible, delta)
	elif minf(now() - _seen_t, _group_contact_age()) < 15.0:
		if not _suppress(delta, tpos):
			cease_fire()
			look_at_point(threat_eye, delta, 4.0)
	else:
		cease_fire()
		look_at_point(threat_eye, delta, 3.0)
		if _no_los_time > 12.0:
			set_state(State.GUARD)


## Niederhalten der letzten bekannten Feindlage (volle Streuung, Feuerstöße); false = nicht möglich
func _suppress(delta: float, tpos: Vector3) -> bool:
	var d := distance_to(tpos)
	var w := soldier.current_weapon()
	if d > 90.0 or d < 4.0 or w == null or w.data.action in [WeaponData.Action.THROWN, WeaponData.Action.ROCKET, WeaponData.Action.MELEE]:
		return false
	if w.in_mag == 0:
		soldier.trigger = false
		if not w.is_reloading():
			soldier.reload()
		return true
	var aim := tpos + Vector3.UP * 1.0
	soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(aim + Vector3.UP * 0.5) else Soldier.Stance.STAND
	look_at_point(aim, delta, 3.0)
	soldier.aim_point = aim
	soldier.has_aim_point = true
	soldier.aiming = true
	soldier.extra_spread = 2.5 + d / 40.0
	_handle_bursts(w, facing_error(aim) < 0.15, delta, d)
	return true


## Feuerstöße: Deckungsfeuer-MG 5–10 Schuss, 1–2 s Pause (Niederhalten); sonst wie AIBrain
func _handle_bursts(w: Weapon, can_shoot: bool, delta: float, dist: float) -> void:
	if persona != BotTraits.Trait.SUPPORT or not w.fires_automatic():
		super._handle_bursts(w, can_shoot, delta, dist)
		return
	burst_pause = maxf(burst_pause - delta, 0.0)
	if w.in_mag > _burst_start_mag:
		_burst_start_mag = w.in_mag            # nachgeladen
	if _sb_left > 0 and (not can_shoot or w.in_mag == 0):
		_end_burst()
	if not can_shoot or burst_pause > 0.0 or w.in_mag == 0:
		soldier.trigger = false
		return
	if _sb_left <= 0:
		_sb_left = randi_range(5, 10)
		_burst_start_mag = w.in_mag
		bursts += 1
		burst_log.append([now(), 0])
		leader().suppress_until = now() + 3.0
	soldier.trigger = true
	var fired := _burst_start_mag - w.in_mag
	burst_log[burst_log.size() - 1][1] = fired
	if fired >= _sb_left:
		_end_burst()


func _end_burst() -> void:
	_sb_left = 0
	soldier.trigger = false
	burst_pause = randf_range(1.0, 2.0)
	_bursts_here += 1
	leader().suppress_until = now() + burst_pause + 1.0


## Flankierer: kurz aus Deckung, dann seitlich über Deckung vorrücken – bevorzugt während Deckungsfeuer läuft;
## Granaten in Deckungen/Räume, wenn der Gegner nicht zu sehen ist
func _combat_flanker(delta: float, visible: Soldier, tpos: Vector3) -> void:
	var threat_eye := tpos + Vector3.UP * 1.5
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	_engaged_time += delta
	var tdist := distance_to(tpos)
	if not visible and _no_los_time > 1.5 and _grenade_cd <= 0.0 and tdist > 7.0 and tdist < 30.0 \
			and (not has_move_target() or not _flanked):
		_grenade_cd = randf_range(8.0, 12.0)
		if throw_grenade_at(tpos):
			grenades_thrown += 1
			stop_moving()
			return
	if _flanked:
		if has_move_target() and _cover_pos.is_finite() and distance_to(_cover_pos) > 1.5:
			_move_in_combat(delta, visible, 20.0)
			return
		stop_moving()
		_peek_fire(delta, visible, tpos)
		if _no_los_time > 8.0 and _pos_t > 6.0 and _flanks < 3:
			_flanked = false                  # dort nichts zu sehen: erneut vorrücken
			_engaged_time = 2.0
		return
	if not _cover_step(delta, visible, tpos, 8.0, 0.3):
		return
	_peek_fire(delta, visible, tpos)
	var suppressed := now() < leader().suppress_until
	if _engaged_time > 2.5 and (suppressed or not _group_has(BotTraits.Trait.SUPPORT) or _engaged_time > 9.0):
		var f := _find_wide_flank(tpos, threat_eye)
		if f.is_finite():
			_flanked = true
			_flanks += 1
			flank_count += 1
			flank_origin = soldier.global_position
			flank_target = f
			_cover_pos = f
			_pos_t = 0.0
			move_to(f, Soldier.MoveMode.RUN)
			return
		_engaged_time = 0.0


## Flanke: Deckung 11–22 m seitlich der Achse zum Gegner und etwas näher, erreichbar ohne großen Umweg
func _find_wide_flank(tpos: Vector3, threat_eye: Vector3) -> Vector3:
	var to_t := tpos - soldier.global_position
	to_t.y = 0.0
	var dist := to_t.length()
	if dist < 1.0:
		return Vector3.INF
	var first: float = -1.0 if randf() < 0.5 else 1.0
	for lateral: float in [16.0, 11.0, 22.0]:
		for side: float in [first, -first]:
			var perp := Vector3(-to_t.z, 0, to_t.x).normalized() * side
			var center := soldier.global_position + perp * lateral + to_t.normalized() * clampf(dist * 0.4, 4.0, 18.0)
			var c := find_cover_around(center, threat_eye, 7.0)
			if c.is_finite() and absf((c - soldier.global_position).dot(perp)) > 7.0 \
					and BotNav.path_cost(soldier, soldier.global_position, c) < lateral * 3.0:
				return c
	return _find_flank(tpos, threat_eye)


## Scharfschütze: auf Distanz aus verdeckter Stellung, nach 1–2 Schüssen Stellungswechsel; zu nah → wie Schütze
func _combat_sniper(delta: float, visible: Soldier, tpos: Vector3) -> void:
	var d := distance_to(tpos)
	if d < 20.0 and not _relocating:
		if _cover_step(delta, visible, tpos, 10.0, -0.5):
			_peek_fire(delta, visible, tpos)
		return
	if _relocating:
		if has_move_target() and distance_to(_spot) > 1.5:
			_move_in_combat(delta, null, 0.0)
			return
		_relocating = false
		_shots_here = 0
	stop_moving()
	var threat_eye := tpos + Vector3.UP * 1.5
	soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
	if visible:
		engage(visible, delta)
	else:
		cease_fire()
		look_at_point(threat_eye, delta, 3.0)
	if _shots_here >= _shots_limit and not soldier.trigger:
		_shots_here = 0
		_shots_limit = randi_range(1, 2)
		var s := BotGoals.overwatch_spot(self, tpos, clampf(d * 0.8, 25.0, 60.0), clampf(d * 1.2, 40.0, 90.0), true,
			soldier.global_position, tpos)
		if not s.is_finite():
			s = _lateral_cover(tpos, 8.0, 16.0)
		if s.is_finite():
			_spot = s
			hold_pos = s
			_relocating = true
			relocations += 1
			cease_fire()
			BotSquad.claim(self, s)
			move_to(s, Soldier.MoveMode.RUN)
	if _no_los_time > 15.0:
		set_state(State.GUARD)


## Camper: bleibt verdeckt in Stellung; entdeckt (getroffen, Feind sehr nah, mehrere Schüsse) → neue Stellung
func _combat_camper(delta: float, visible: Soldier, tpos: Vector3) -> void:
	var threat_eye := tpos + Vector3.UP * 1.5
	if _relocating:
		if has_move_target() and distance_to(_spot) > 1.5:
			_move_in_combat(delta, visible, 12.0)
			return
		_relocating = false
	var discovered := now() - _hit_t < 2.0 or (visible != null and distance_to(visible.global_position) < 10.0) or _shots_here >= 5
	if discovered:
		_shots_here = 0
		var center: Vector3 = goal if goal.is_finite() else tpos
		var s := BotGoals.overwatch_spot(self, center, 8.0, 30.0, false, soldier.global_position, tpos)
		if not s.is_finite():
			s = find_cover(threat_eye, 14.0, -0.4)
		if s.is_finite():
			_spot = s
			hold_pos = s
			_spot_t = randf_range(60.0, 120.0)
			_relocating = true
			relocations += 1
			cease_fire()
			move_to(s, Soldier.MoveMode.RUN)
			return
	stop_moving()
	soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
	if visible:
		engage(visible, delta)
	else:
		cease_fire()
		look_at_point(threat_eye, delta, 3.0)
	if _no_los_time > 10.0:
		set_state(State.GUARD)


func _visible_enemies() -> int:
	var n := 0
	for t in perception.visible_now:
		if is_instance_valid(t) and t.alive and perception.visible_now[t] and float(perception.awareness.get(t, 0.0)) >= 1.0:
			n += 1
	return n


## Rückzug bei schwerer Verwundung oder deutlicher Unterzahl: Deckung abseits der Bedrohung, dort verbinden
func _retreat_tick(delta: float, visible: Soldier, tpos: Vector3) -> bool:
	_retreat_cd = maxf(_retreat_cd - delta, 0.0)
	if _retreat_t > 0.0:
		_retreat_t -= delta
		if has_move_target() and _cover_pos.is_finite() and distance_to(_cover_pos) > 1.5:
			_move_in_combat(delta, visible, 15.0)
			return true
		stop_moving()
		if soldier.health < soldier.max_health * 0.6 and soldier.medkits > 0 and soldier.heal_time_left <= 0.0 and visible == null:
			soldier.start_heal([soldier])
		if soldier.heal_time_left > 0.0:
			cease_fire()
			soldier.stance_request = Soldier.Stance.CROUCH
		else:
			_peek_fire(delta, visible, tpos)
		return true
	if _retreat_cd > 0.0:
		return false
	var hurt := soldier.health < soldier.max_health * 0.35
	var outnumbered := _visible_enemies() >= _group_alive() + 2
	if not (hurt or outnumbered):
		return false
	var away := soldier.global_position - tpos
	away.y = 0.0
	if away.length() < 0.1:
		away = -soldier.forward()
	var center := soldier.global_position + away.normalized() * 14.0
	var c := find_cover_around(center, tpos + Vector3.UP * 1.5, 10.0)
	if not c.is_finite():
		c = BotNav.closest(soldier, center)
	_cover_pos = c
	_retreat_t = randf_range(8.0, 12.0)
	_retreat_cd = 25.0
	retreats += 1
	move_to(c, Soldier.MoveMode.RUN)
	return true


## Rollenwaffe: Panzerabwehr nimmt gegen Fahrzeuge bzw. auf Abstand den Raketenwerfer,
## Schleicher nimmt hinter einem ahnungslosen Gegner das Messer
func _choose_weapon() -> void:
	if target == null or not is_instance_valid(target):
		return
	var d := distance_to(target.global_position)
	match role:
		Role.AT:
			var l: Weapon = soldier.weapons[WeaponData.Slot.LAUNCHER]
			var want := l != null and l.total_ammo() > 0 and (target.vehicle != null or d > 18.0)
			soldier.select_slot(WeaponData.Slot.LAUNCHER if want else WeaponData.Slot.PRIMARY)
		Role.SNEAKER:
			var behind := target.forward().dot((target.global_position - soldier.global_position).normalized()) > 0.3
			var k: Weapon = soldier.weapons[WeaponData.Slot.MELEE]
			if k and d < 1.6 and behind:
				soldier.select_slot(WeaponData.Slot.MELEE)
				soldier.trigger = true
			elif soldier.current_slot == WeaponData.Slot.MELEE:
				soldier.select_slot(WeaponData.Slot.PRIMARY)


# --- Reize: Gruppe informieren, aber das Spielziel nicht wegen jedes Geräuschs aufgeben ----------------

func _on_detected(t: Soldier) -> void:
	var was := state
	super._on_detected(t)
	if not soldier.alive or t == null:
		return
	_seen_t = now()
	_note_contact(t.global_position)
	if was != State.COMBAT:
		for b in group:
			if is_instance_valid(b) and b != self and b.soldier.alive and b.state != State.COMBAT:
				b.support(t, soldier.global_position)


## Kamerad meldet Feind: Lage bekannt (nicht gesehen). In der Nähe → kampfbereit (Persönlichkeit entscheidet:
## Deckungsfeuer hält nieder, Flankierer rückt seitlich vor …), sonst Weg zum Ziel unter Bedrohung fortsetzen
func support(t: Soldier, from: Vector3) -> void:
	perception.last_known[t] = t.global_position
	perception.awareness[t] = maxf(perception.awareness.get(t, 0.0), 0.5)
	_note_contact(t.global_position)
	if distance_to(t.global_position) < 80.0 and distance_to(from) < 60.0:
		target = t
		investigate_pos = t.global_position
		set_state(State.COMBAT)


func _on_damaged(amount: float, zone: StringName) -> void:
	_hit_t = now()
	super._on_damaged(amount, zone)


func _on_heard(pos: Vector3, kind: StringName, source: Node) -> void:
	if not soldier.alive or state == State.COMBAT:
		return
	var enemy := source is Soldier and (source as Soldier).team != soldier.team
	if (kind in [&"gunshot", &"impact"] and enemy) or kind == &"explosion":
		_note_contact(pos)
		if distance_to(pos) < 30.0 and state in [State.GUARD, State.PATROL]:
			investigate_pos = pos
			set_state(State.INVESTIGATE)
	elif kind in [&"step", &"climb", &"door"] and enemy and distance_to(pos) < 15.0 and state in [State.GUARD, State.PATROL]:
		investigate_pos = pos
		set_state(State.INVESTIGATE)


func _on_suspicious(pos: Vector3) -> void:
	if state in [State.GUARD, State.PATROL] and soldier.alive:
		investigate_pos = pos
		set_state(State.INVESTIGATE)


func _on_alarm(_pos: Vector3, _by: Node) -> void:
	pass        # kein globaler Missionsalarm im Mehrspieler


func _raise_alarm(_reason: String) -> void:
	pass
