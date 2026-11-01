class_name OrigCombatFsm
extends RefCounted
## AP-3 (B-021-Rest): Kampf-/Suchautomat der Mensch-KI nach hd2.exe 0x549AE0. Nur Originalmissionen offline
## (EnemyBrain._orig_rules); MP-Bots und Übungseinsätze nutzen weiter die eigene Kampflogik von EnemyBrain.
## Belege: docs/GAP_REA_2026-10-31.md §3 und Nachtrag AP-7 H/I; re_notes_ai §6.6.
##
## Rahmen im Original [B]: Zustand [+0xF0]+8, Zeitgeber [+0xF0]+0x10 (ms, zählt herunter), Zähler +0xC, Ziel +0x148,
## Posten +0x180, Bewegungsobjekt +0x12C (Gangcode +0x54). Im Nachbau steuert der Automat nur Absichten über das
## EnemyBrain (move_to, stance_request, engage …) – wie Spieler und übrige KI.

## Zustände (Nummern = Original) [B Übergänge, P Bedeutung]
const S_OPEN := 0          ## Eröffnen
const S_LOST := 2          ## Ziel verloren / Rückkehr vorbereiten
const S_APPROACH := 3      ## Anmarsch auf den Spieler
const S_AIM := 4           ## Anvisieren
const S_FIRE := 5          ## Feuern
const S_CHOOSE := 6        ## Positionswechsel wählen
const S_MOVE := 7          ## Laufen zur Position
const S_EVAL := 8          ## Bewerten
const S_ADVANCE := 9       ## Nachrücken
const S_ADV_ARRIVED := 10  ## Nachrücken angekommen
const S_CLOSE := 11        ## Nahanlauf
const S_REST := 12         ## Ruhe am Posten
const S_HOME := 13         ## Heimweg
const S_SEARCH_ARRIVED := 14
const S_SEARCH := 15
const NAMES := {0: "Eröffnen", 2: "Verloren", 3: "Anmarsch", 4: "Anvisieren", 5: "Feuern", 6: "Wechsel wählen",
	7: "Laufen", 8: "Bewerten", 9: "Nachrücken", 10: "Nachgerückt", 11: "Nahanlauf", 12: "Ruhe", 13: "Heimweg",
	14: "Suchpunkt erreicht", 15: "Suche"}

## Schwellen [B]
const APPROACH_MIN := 20.0       ## Zustand 0: Anmarsch zum Spieler erst ab 20 m
const CLOSE_DIST := 6.0          ## Zustand 7/9: unter 6 m Aktion 7 bzw. direktes Anschleichen
const REPORT_DIST := 30.0        ## Zustand 4: Ziel < 30 m → nur an den eigenen Sensor melden (0x5582C0)
## Feuerpause Zustand 5 in ms [B]: aggressiv (0x100) rand·600 + 200, sonst rand·2000 + 500
const FIRE_AGGR := Vector2(200.0, 600.0)
const FIRE_DEF := Vector2(500.0, 2000.0)
## Fortsetzung Nachrücken [B]: Zustand 10 → 60 % weiter, Zustand 11 → 80 % weiter, sonst zurück zum Posten
const CONT_ADVANCE := 0.6
const CONT_CLOSE := 0.8
## Deckungswahl [B]: Flanke 0x553EB0 Raster/Umkreis 5 m um das Ziel; Nachrücken 0x5541F0 Ring 10–20 m, cos > 0,5
const FLANK_GRID := 5.0
const ADV_MIN := 10.0
const ADV_MAX := 20.0
const ADV_COS := 0.5
## Zeiten ohne Beleg [E]: Zustand 2 (Zufallszeit vor dem Heimweg), Zustand 12 (Ruhe), Wiederholsperre Aktion 7 (+0x108)
const LOST_MS := Vector2(1000.0, 2000.0)
const REST_MS := Vector2(2000.0, 3000.0)
const ACTION7_LOCK_MS := 1500.0
## Zustand 7: abbrechen, wenn der Weg nicht vorankommt (Original: Bit 28 „Pfad läuft“ fällt weg) [E Zeit]
const MOVE_ABORT_S := 12.0

var brain: EnemyBrain
var rng := RandomNumberGenerator.new()
var state := S_OPEN
var timer_ms := 0.0
var counter := 0
var target: Soldier
var target_pos := Vector3.INF
var move_point := Vector3.INF
var finished := false            ## Zustand 12 abgelaufen: Flag +0x144 |= 4 („Suche beendet“)
var face_move := true            ## Körper in Laufrichtung drehen (EnemyBrain.update_movement)
var history: Array[int] = []     ## Zustandsfolge (Test/Debug)
var last_pause_ms := 0.0         ## zuletzt gezogene Feuerpause (Test)
var action7_count := 0           ## Aktion-7-Aufträge (Test)
var _action7_lock := 0.0
var _state_s := 0.0
var _stance := Soldier.Stance.STAND
var _mode: int = Soldier.MoveMode.JOG


func _init(b: EnemyBrain = null) -> void:
	brain = b
	rng.randomize()


## Kampfauftrag (Ziel gesehen/gemeldet bzw. HUMAN_Attack, GAP_REA AP-7 D).
func start(t: Soldier) -> void:
	target = t
	finished = false
	history.clear()
	if t != null:
		target_pos = t.global_position
		_enter(S_OPEN)
	else:
		_enter(S_SEARCH)


## Suche ohne Ziel, aber mit Suchpunkt (Zustand 15, 0x5AC2B0).
func start_search(p: Vector3) -> void:
	target = null
	target_pos = p
	finished = false
	history.clear()
	_enter(S_SEARCH)


func is_active() -> bool:
	return not finished


func state_name() -> String:
	return NAMES.get(state, str(state))


func aggressive() -> bool:
	return brain != null and brain.ai_mode == EnemyBrain.Mode.AGGRESSIVE


static func fire_pause_ms(aggr: bool, r: RandomNumberGenerator) -> float:
	var k := FIRE_AGGR if aggr else FIRE_DEF
	return r.randf() * k.y + k.x


func _enter(s: int, t_ms := 0.0) -> void:
	state = s
	timer_ms = t_ms
	_state_s = 0.0
	history.append(s)
	if Game.cli.has("debug_fsm") and brain and brain.soldier:
		print("FSM %s -> %d %s (%.0f ms)" % [brain.soldier.name, s, state_name(), t_ms])


func _target_ok() -> bool:
	return is_instance_valid(target) and target.alive and target.team != brain.soldier.team \
		and target.team != Soldier.TEAM_NEUTRAL


## 0x553CE0 „Ziel ist der Spieler-Akteur“ [B]; im Nachbau: vom Spieler gesteuerter Soldat.
func _target_is_player() -> bool:
	return _target_ok() and target.is_player_controlled


func _visible() -> bool:
	return _target_ok() and brain.perception.visible_now.get(target, false) \
		and brain.perception.awareness.get(target, 0.0) >= 1.0


func _dist() -> float:
	return brain.distance_to(target_pos)


## Ein Physikschritt. Gibt false zurück, wenn der Automat beendet ist (Zustand 12 abgelaufen).
func tick(delta: float) -> bool:
	if finished or brain == null:
		return false
	var s := brain.soldier
	if _target_ok():
		if _visible():
			target_pos = target.global_position
			brain.perception.last_known[target] = target_pos
		else:
			target_pos = brain.perception.last_known.get(target, target_pos)
	timer_ms -= delta * 1000.0
	_action7_lock = maxf(_action7_lock - delta * 1000.0, 0.0)
	_state_s += delta
	s.stance_request = _stance
	match state:
		S_OPEN: _st_open()
		S_APPROACH: _st_approach(delta)
		S_AIM: _st_aim(delta)
		S_FIRE: _st_fire(delta)
		S_CHOOSE: _st_choose()
		S_MOVE: _st_move(delta)
		S_EVAL: _st_eval()
		S_ADVANCE: _st_advance()
		S_ADV_ARRIVED: _st_adv_arrived()
		S_CLOSE: _st_close(delta)
		S_LOST: _st_lost()
		S_HOME: _st_home()
		S_REST: _st_rest(delta)
		S_SEARCH: _st_search()
		S_SEARCH_ARRIVED: _st_search_arrived()
		_: _enter(S_LOST, _rand_ms(LOST_MS))
	s.stance_request = _stance
	return not finished


func _rand_ms(r: Vector2) -> float:
	return rng.randf_range(r.x, r.y)


func _aim_only(delta: float) -> void:
	## 0x55D2E0/0x55D630 Ziel anvisieren: Blick und Anschlag, ohne Schuss
	var p := target_pos + Vector3.UP * 1.3
	brain.look_at_point(p, delta, 6.0)
	brain.soldier.aim_point = p
	brain.soldier.has_aim_point = true
	brain.soldier.aiming = true
	brain.soldier.trigger = false


# --- Zustände ---------------------------------------------------------------------------

func _st_open() -> void:
	if not _target_ok():
		_enter(S_LOST, _rand_ms(LOST_MS))
		return
	# Ziel = Spieler und ≥ 20 m und Weg zum Ziel (0x557540) → hingehen, 3; sonst Bewegung 2 (halten) → 4 [B]
	# AP-6: Scharfschütze (HUMAN_SetSniper) verlässt den Posten nicht → kein Anmarsch [P]
	if _target_is_player() and _dist() >= APPROACH_MIN and not brain.sniper_enabled and has_path(brain, target_pos):
		_go(target_pos, Soldier.Stance.STAND, Soldier.MoveMode.JOG)
		_enter(S_APPROACH)
	else:
		brain.stop_moving()
		_enter(S_AIM)


func _st_approach(_delta: float) -> void:
	if not _target_ok():
		_enter(S_LOST, _rand_ms(LOST_MS))
		return
	face_move = true
	if not brain.has_move_target() or brain.arrived(1.5) or _dist() < APPROACH_MIN * 0.5:
		brain.stop_moving()
		counter = 0
		_enter(S_FIRE, fire_pause_ms(aggressive(), rng))
		last_pause_ms = timer_ms


func _st_aim(delta: float) -> void:
	if not _target_ok():
		_enter(S_LOST, _rand_ms(LOST_MS))
		return
	brain.stop_moving()
	_aim_only(delta)
	# Ziel < 30 m → 0x5582C0 meldet es dem eigenen Sensor (keine Rundmeldung, B-031) [B]
	if _dist() < REPORT_DIST:
		brain.perception.awareness[target] = 1.0
		brain.perception.last_known[target] = target_pos
	_enter(S_FIRE, fire_pause_ms(aggressive(), rng))
	last_pause_ms = timer_ms


func _st_fire(delta: float) -> void:
	brain.stop_moving()
	if _visible():
		brain.engage(target, delta)
	elif _target_ok():
		brain.soldier.trigger = false
		_aim_only(delta)
	if timer_ms <= 0.0:
		brain.soldier.trigger = false
		_enter(S_CHOOSE)


func _st_choose() -> void:
	brain.soldier.trigger = false
	var p := Vector3.INF
	if _target_ok():
		if aggressive():
			p = pick_flank_point(brain, target_pos, brain.soldier.global_position, rng)
		else:
			p = pick_leash_point(brain, target_pos, rng)
	if p.is_finite() and brain._in_leash(p):
		move_point = p
		_gait(true)
		_go(p, _stance, _mode)
		_enter(S_MOVE)
	else:
		brain.stop_moving()
		_enter(S_LOST, _rand_ms(LOST_MS))


func _st_move(delta: float) -> void:
	_gait(false)
	brain.soldier.move_mode = _mode
	var close := _target_ok() and _dist() < CLOSE_DIST
	if close:
		# Aktion 7 (0x570980 Modus 7): Blick/Anschlag auf die Zielposition, Wiederholsperre +0x108 [B Teil, AP-7 H]
		if _action7_lock <= 0.0:
			_action7_lock = ACTION7_LOCK_MS
			action7_count += 1
		_aim_only(delta)
		face_move = false
	else:
		face_move = true
	if not brain.has_move_target() or brain.arrived(1.2) or _state_s > MOVE_ABORT_S:
		brain.stop_moving()
		if _target_ok():
			_aim_only(delta)
		_enter(S_EVAL)


func _st_eval() -> void:
	# Ziel lebt und Modus 0x100: Zeitgeber 0 → 9; sonst neues Ziel (0x5AE310) → 5, keins → 2 [B]
	if _target_ok() and aggressive():
		_enter(S_ADVANCE, 0.0)
		return
	var t := brain.perception.best_target()
	if t == null and _visible():
		t = target
	if t != null:
		target = t
		brain.target = t
		target_pos = t.global_position
		_enter(S_FIRE, fire_pause_ms(aggressive(), rng))
		last_pause_ms = timer_ms
	else:
		_enter(S_LOST, _rand_ms(LOST_MS))


func _st_advance() -> void:
	if not _target_ok():
		_enter(S_LOST, _rand_ms(LOST_MS))
		return
	if _dist() >= CLOSE_DIST:
		# 0x5541F0 → Wegpunkt hockend/laufend (Gang 0x2008, Haltung 1) → 10; keiner → 2 [B]
		var p := pick_advance_point(brain, brain.soldier.global_position, target_pos, rng)
		if p.is_finite() and brain._in_leash(p):
			move_point = p
			_go(p, Soldier.Stance.CROUCH, Soldier.MoveMode.RUN)
			_enter(S_ADV_ARRIVED)
		else:
			_enter(S_LOST, _rand_ms(LOST_MS))
	elif not brain._in_leash(target_pos):
		_enter(S_LOST, _rand_ms(LOST_MS))    # Ziel außerhalb der Leine (z. B. Scharfschütze, AP-6) [E]
	else:
		# unter 6 m: geduckt schleichend (0x1008) direkt zum Ziel → 11 [B Gang; P Haltung]
		move_point = target_pos
		_go(target_pos, Soldier.Stance.CROUCH, Soldier.MoveMode.SNEAK)
		_enter(S_CLOSE)


func _st_adv_arrived() -> void:
	if brain.has_move_target() and not brain.arrived(1.2) and _state_s < MOVE_ABORT_S:
		face_move = true
		return
	brain.stop_moving()
	if _target_ok() and rng.randf() < CONT_ADVANCE:
		_enter(S_ADVANCE)
	else:
		_enter(S_LOST, _rand_ms(LOST_MS))


func _st_close(delta: float) -> void:
	if _target_ok():
		_aim_only(delta)
		brain.move_to(target_pos, Soldier.MoveMode.SNEAK)
	if brain.has_move_target() and not brain.arrived(1.5) and _state_s < MOVE_ABORT_S:
		face_move = false
		return
	brain.stop_moving()
	if _target_ok() and rng.randf() < CONT_CLOSE:
		_enter(S_ADVANCE)
	else:
		_enter(S_LOST, _rand_ms(LOST_MS))


func _st_lost() -> void:
	# Ziel freigeben, Haltung 3 (außer Flag 0x400000 „Haltung nicht ändern“) [B]; Haltung 3 = hocken [P]
	brain.stop_moving()
	brain.cease_fire()
	_stance = Soldier.Stance.CROUCH
	if timer_ms > 0.0:
		return
	# Bewegung 4, Haltung 1, Gang 0x2008, zurück zum Posten +0x180 → 13 [B]
	_go(brain.home_pos, Soldier.Stance.CROUCH, Soldier.MoveMode.RUN)
	_enter(S_HOME)


func _st_home() -> void:
	if brain.has_move_target() and not brain.arrived(1.5) and _state_s < 60.0:
		face_move = true
		return
	brain.stop_moving()
	_stance = Soldier.Stance.STAND
	_enter(S_REST, _rand_ms(REST_MS))


func _st_rest(_delta: float) -> void:
	brain.stop_moving()
	_stance = Soldier.Stance.STAND
	if timer_ms <= 0.0:
		finished = true


func _st_search() -> void:
	# Kein Ziel, aber Suchpunkt (0x5AC2B0): näheren Wegpunkt wählen, Gang 0x4010 (Gehen) → 14 [B]; Wegpunkt = Navmesh [E]
	if not target_pos.is_finite():
		_enter(S_LOST, _rand_ms(LOST_MS))
		return
	_go(target_pos, Soldier.Stance.STAND, Soldier.MoveMode.WALK)
	_enter(S_SEARCH_ARRIVED)


func _st_search_arrived() -> void:
	if brain.has_move_target() and not brain.arrived(1.5) and _state_s < 30.0:
		face_move = true
		return
	brain.stop_moving()
	var t := brain.perception.best_target()
	if t != null:
		target = t
		brain.target = t
		target_pos = t.global_position
		_enter(S_AIM)
	else:
		_enter(S_LOST, _rand_ms(LOST_MS))


func _go(p: Vector3, stance: int, mode: int) -> void:
	_stance = stance
	_mode = mode
	brain.soldier.stance_request = stance
	brain.move_to(p, mode)


## Gangwahl Zustand 6/7 [B, GAP_REA §3; Zuordnung Gangcode → MoveMode P]:
##  nicht aggressiv: 0x5547B0, Haltung 1 (hocken), Bewegung 2;
##  aggressiv: Ziel Spieler und d > rand·20 + 60 → Fernmodus 0x554800 (Sprint 0x10008, AP-7 I);
##             sonst d ≤ (1 + rand)·20 → hocken, Gang 0x2008; sonst Bewegung 4 + 0x5547B0 (aufrecht laufen 0x4008).
## Die Bit-0x10000-Variante in Zustand 7 (Gaußschwelle) ist nicht nachgebaut [offen].
func _gait(choose: bool) -> void:
	if not choose:
		return
	var d := _dist() if target_pos.is_finite() else 0.0
	if not aggressive():
		_stance = Soldier.Stance.CROUCH
		_mode = Soldier.MoveMode.RUN
	elif _target_is_player() and d > rng.randf() * 20.0 + 60.0:
		_stance = Soldier.Stance.STAND
		_mode = Soldier.MoveMode.RUN
	elif d <= (1.0 + rng.randf()) * 20.0:
		_stance = Soldier.Stance.CROUCH
		_mode = Soldier.MoveMode.RUN
	else:
		_stance = Soldier.Stance.STAND
		_mode = Soldier.MoveMode.JOG


# --- Deckungswahl (statisch, testbar) ----------------------------------------------------

## Weg zum Ziel vorhanden (0x557540) – Navmesh-Pfad endet nahe am Ziel.
static func has_path(b: AIBrain, to: Vector3) -> bool:
	var map := b.agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return true    # Netz noch nicht fertig: wie bisher direkt laufen
	var path := NavigationServer3D.map_get_path(map, b.soldier.global_position, to, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(to) < 3.0


static func _snap(b: AIBrain, p: Vector3) -> Vector3:
	var map := b.agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var q := NavigationServer3D.map_get_closest_point(map, p)
	var dx := Vector2(q.x - p.x, q.z - p.z).length()
	return q if dx < 1.5 and absf(q.y - p.y) < 4.0 else Vector3.INF


static func _sees(b: AIBrain, from_feet: Vector3, to_feet: Vector3) -> bool:
	var space := b.soldier.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from_feet + Vector3.UP * 1.5, to_feet + Vector3.UP * 1.2, 1)
	return space.intersect_ray(q).is_empty()


## 0x553EB0 (aggressiv) [B]: nächster Wegpunkt zum Ziel im Umkreis 5 m und seine Nachbarn in 5 m; behalten nur Punkte mit
## (Punkt − Ziel)·(eigene Lage − Ziel) < 0 (abgewandte Seite = Flanke/Rücken), daraus zufällig.
## Nachbau: Wegpunkt = Navmesh-Rasterpunkt im 5-m-Raster um das Ziel (Mitte ≤ 5 m, Nachbarn je 5 m → ≤ 10 m) [E Quelle],
## zusätzlich Sichtprüfung Punkt → Ziel [E]. INF, wenn keiner passt.
static func pick_flank_point(b: AIBrain, tpos: Vector3, self_pos: Vector3, r: RandomNumberGenerator) -> Vector3:
	var to_self := self_pos - tpos
	to_self.y = 0.0
	var out: Array[Vector3] = []
	for i in range(-2, 3):
		for j in range(-2, 3):
			if i == 0 and j == 0:
				continue
			var off := Vector3(i * FLANK_GRID, 0.0, j * FLANK_GRID)
			if off.length() > 2.0 * FLANK_GRID + 0.01:
				continue
			var p := _snap(b, tpos + off)
			if not p.is_finite():
				continue
			var d := p - tpos
			d.y = 0.0
			if d.dot(to_self) >= 0.0 or d.length() < 1.0:
				continue
			if _sees(b, p, tpos):
				out.append(p)
	if out.is_empty():
		return Vector3.INF
	return out[r.randi() % out.size()]


## 0x5541F0 (Nachrücken) [B]: Wegpunkte im Umkreis 20 m um sich selbst mit Abstand ≥ 10 m und Richtungskosinus > 0,5 zum
## Ziel (±60°), daraus zufällig. Nachbau: Navmesh-Stichproben im Ring [E Quelle]; Punkte mit Sicht auf das Ziel bevorzugt [E].
static func pick_advance_point(b: AIBrain, self_pos: Vector3, tpos: Vector3, r: RandomNumberGenerator) -> Vector3:
	var dir := tpos - self_pos
	dir.y = 0.0
	if dir.length() < 0.01:
		return Vector3.INF
	dir = dir.normalized()
	var seen: Array[Vector3] = []
	var other: Array[Vector3] = []
	for k in 20:
		var a := r.randf_range(-PI / 3.0, PI / 3.0)
		var rad := r.randf_range(ADV_MIN, ADV_MAX)
		var p := _snap(b, self_pos + dir.rotated(Vector3.UP, a) * rad)
		if not p.is_finite():
			continue
		var d := p - self_pos
		d.y = 0.0
		var l2 := d.length_squared()
		if l2 < ADV_MIN * ADV_MIN or l2 > ADV_MAX * ADV_MAX or d.normalized().dot(dir) <= ADV_COS:
			continue
		if _sees(b, p, tpos):
			seen.append(p)
		else:
			other.append(p)
	var pool := seen if not seen.is_empty() else other
	if pool.is_empty():
		return Vector3.INF
	return pool[r.randi() % pool.size()]


## Nicht aggressiv: 0x557D10 = Wegpunktsuche im Leinengebiet (+0x168 bzw. +0x158) [B Ablauf]. Nachbau: vorhandene
## Deckungssuche (verdeckt hockend, Herausschauen möglich) innerhalb der Leine [E Kriterium].
static func pick_leash_point(b: EnemyBrain, tpos: Vector3, _r: RandomNumberGenerator) -> Vector3:
	var p := b.find_cover(tpos + Vector3.UP * 1.5, 9.0, 0.0)
	return p if p.is_finite() and b._in_leash(p) else Vector3.INF
