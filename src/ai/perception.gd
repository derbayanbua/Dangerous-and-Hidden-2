class_name Perception
extends Node
## Sinneskomponente eines Soldaten (Kind-Node).
## Sehen: Sichtkegel + Reichweite + Sichtlinien-Raycast. Erkennung wächst
## pro Ziel graduell (Haltung, Bewegung, Entfernung, Peripherie) — Grundlage
## für Schleichen. Hören: Events.noise_emitted innerhalb Radius * Hörfaktor.
## Belegte Originalparameter: HUMAN_SETSIGHTRANGE (meist 25–80 m),
## HUMAN_SETHEARRANGE (meist 50–80 m), bei Alarm Sichtweite 300 m.

signal target_detected(target: Soldier)      ## Erkennung erreicht 1.0
signal suspicious(position: Vector3)          ## Erkennung > 0.35 oder Geräusch
signal heard(position: Vector3, kind: StringName, source: Node)
signal corpse_seen(corpse: Soldier)

@export var sight_range := 55.0
@export var hear_range := 60.0    ## skaliert Geräuschradien (60 = Referenz)
@export var fov_deg := 130.0
@export var detection_speed := 1.0

var soldier: Soldier
var awareness := {}               ## Soldier -> 0..1
var visible_now := {}             ## Soldier -> bool (aktueller Tick)
var last_known := {}              ## Soldier -> Vector3
var known_corpses := {}           ## Soldier -> true
var _tick := 0.0
const TICK := 0.15


func _ready() -> void:
	soldier = get_parent() as Soldier
	_tick = randf() * TICK   # Last verteilen
	Events.noise_emitted.connect(_on_noise)


func _physics_process(delta: float) -> void:
	if soldier == null or not soldier.alive:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_refresh_light()
	_update_sight(TICK)


func enemy_team() -> int:
	if soldier.team == Soldier.TEAM_NEUTRAL:
		return -1     # neutrale Figuren suchen keine Ziele
	return Soldier.TEAM_AXIS if soldier.team == Soldier.TEAM_ALLIED else Soldier.TEAM_ALLIED


## Mögliche Gegner: Einzelspieler die andere Seite; Mehrspieler-KI (Deathmatch: jeder für sich) alle
## Soldaten anderer Teams außer Neutralen. Erkannt werden sie trotzdem nur über Sicht/Gehör (kein „Aimbot“).
func enemy_candidates() -> Array:
	if Net.is_online:
		var out: Array = []
		for n in get_tree().get_nodes_in_group("soldiers"):
			var t := n as Soldier
			if t and t != soldier and t.team != soldier.team and t.team != Soldier.TEAM_NEUTRAL:
				out.append(t)
		return out
	return get_tree().get_nodes_in_group("team_%d" % enemy_team())


func _update_sight(dt: float) -> void:
	var eye := soldier.eye_position()
	var fwd := soldier.aim_direction()
	var space := soldier.get_world_3d().direct_space_state
	var half_fov := deg_to_rad(fov_deg * 0.5)
	for node in enemy_candidates():
		var t := node as Soldier
		if t == null or not t.alive:
			continue
		var tpos := t.global_position + Vector3.UP * (1.2 if t.stance == Soldier.Stance.STAND else (0.8 if t.stance == Soldier.Stance.CROUCH else 0.3))
		var to := tpos - eye
		var dist := to.length()
		var seen := false
		if dist < sight_range:
			var ang := fwd.angle_to(to)
			# Nahbereich: auch knapp hinter dem Sichtfeld wird Bewegung bemerkt
			if ang < half_fov or (dist < 4.0 and t.is_moving() and t.move_mode == Soldier.MoveMode.RUN):
				seen = _line_of_sight(space, eye, tpos, t)
				if seen:
					var gain := _visibility(t, dist, ang, half_fov) * detection_speed * dt
					awareness[t] = minf(awareness.get(t, 0.0) + gain, 1.0)
					last_known[t] = t.global_position
		visible_now[t] = seen
		if not seen:
			awareness[t] = maxf(awareness.get(t, 0.0) - dt * 0.08, 0.0)
		var a: float = awareness.get(t, 0.0)
		if seen and a >= 1.0:
			target_detected.emit(t)
		elif seen and a > 0.35:
			suspicious.emit(t.global_position)
	# Gefallene Kameraden entdecken (Original: Reaktion auf tote Kameraden)
	for node in get_tree().get_nodes_in_group("corpses"):
		var c := node as Soldier
		if c == null or c.team != soldier.team or known_corpses.has(c):
			continue
		var cp := c.global_position + Vector3.UP * 0.3
		var to := cp - eye
		if to.length() < sight_range * 0.6 and fwd.angle_to(to) < half_fov and _line_of_sight(space, eye, cp, null):
			known_corpses[c] = true
			corpse_seen.emit(c)


## Sichtbarkeitsfaktor pro Sekunde: 1.0 ≈ Erkennung in ~1 s.
func _visibility(t: Soldier, dist: float, ang: float, half_fov: float) -> float:
	var stance_k := [1.0, 0.55, 0.25][t.stance] as float
	var move_k := 0.6
	if t.is_moving():
		move_k = 1.6 if t.move_mode == Soldier.MoveMode.RUN else (0.8 if t.move_mode == Soldier.MoveMode.SNEAK or t.stance != Soldier.Stance.STAND else 1.1)
	if t.trigger and t.current_weapon() and t.current_weapon().cooldown > 0.0:
		move_k = 2.0   # Mündungsfeuer
	var dist_k := clampf(1.0 - dist / sight_range, 0.0, 1.0)
	dist_k = 0.15 + 2.6 * dist_k * dist_k
	var periph := 1.0 if ang < half_fov * 0.4 else 0.45
	# Tarnung: in Feinduniform auf Distanz unauffällig; aus der Nähe oder nach
	# eigenem Schuss fällt sie auf (Original: Mission_SetUniformDisguise)
	if t.disguised and t.seconds_since_shot() > 6.0:
		if dist > 8.0:
			return 0.0
		var odd := 1.0 if (t.stance == Soldier.Stance.PRONE or t.move_mode == Soldier.MoveMode.RUN) else 0.35
		periph *= odd
	var light: float = _mission.light_at(t.global_position + Vector3.UP) if _mission else 1.0
	return stance_k * move_k * dist_k * periph * 1.4 * light * Soldier.skill_k(t.skill_stealth, 1.3, 0.6)


var _mission: Node


func _refresh_light() -> void:
	if not is_instance_valid(_mission):
		var m := Game.current_mission()
		_mission = m if m and m.has_method("light_at") else null


func _line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, target: Soldier) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var ex: Array[RID] = [soldier.get_rid()]
	if soldier.vehicle is CollisionObject3D:
		ex.append((soldier.vehicle as CollisionObject3D).get_rid())   # Besatzung sieht nicht gegen die eigene Wanne
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return false
	# Optionale Kartenvegetation verdeckt Sicht, ohne Ballistik auf Welt-Layer 1 zu blockieren.
	var mission := Game.current_mission()
	return not (mission != null and mission.has_method("foliage_blocks_sight") and mission.foliage_blocks_sight(from,to))


func _on_noise(pos: Vector3, radius: float, source: Node, team: int, kind: StringName) -> void:
	if soldier == null or not soldier.alive or source == soldier:
		return
	if team == soldier.team and kind != &"alert" and kind != &"explosion" and kind != &"gunshot":
		return   # eigene Schritte/Einschläge ignorieren
	var eff := radius * (hear_range / 60.0)
	var d := soldier.global_position.distance_to(pos)
	if d > eff:
		return
	heard.emit(pos, kind, source)
	if team != soldier.team and kind != &"alert":
		if source is Soldier and d < eff * 0.5 and kind == &"gunshot":
			# Nahe Schüsse geben die Richtung des Schützen preis
			last_known[source] = (source as Soldier).global_position
			awareness[source] = maxf(awareness.get(source, 0.0), 0.6)
		suspicious.emit(pos)


func max_awareness() -> float:
	var m := 0.0
	for k in awareness:
		if is_instance_valid(k) and k.alive:
			m = maxf(m, awareness[k])
	return m


## Bestes aktuell sichtbares und erkanntes Ziel.
func best_target() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for t in visible_now:
		if not is_instance_valid(t) or not t.alive or not visible_now[t]:
			continue
		if awareness.get(t, 0.0) < 1.0:
			continue
		var d := soldier.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func forget_dead() -> void:
	for k in awareness.keys():
		if not is_instance_valid(k) or not k.alive:
			awareness.erase(k)
			visible_now.erase(k)
			last_known.erase(k)
