class_name BotNav
extends RefCounted
## Wegfindung der Mehrspieler-KI-Soldaten (Server): Route über das Navigationsnetz mit Zwischenpunkten an
## Deckungen statt über freie Fläche, Erreichbarkeitsprüfung des Ziels, Erkennen von Festhängen und
## gestufte Abhilfe (klettern/springen → seitlich ausweichen → neu planen → Ziel aufgeben → aufs Netz setzen).
## Nur BotBrain verwendet diese Klasse; Einzelspieler-KI unverändert.

const WP_REACH := 2.2            ## Zwischenpunkt gilt als erreicht (waagerecht)
const COVER_SEG := 14.0          ## alle ~14 m Wegstrecke eine Deckung in der Nähe suchen
const COVER_DETOUR := 6.0        ## höchstens so weit neben dem Weg
const PROGRESS_DIST := 1.5       ## Fortschritt = so weit bewegt

var waypoints := PackedVector3Array()
var wp_i := 0
var dest := Vector3.INF          ## Ziel der aktuellen Route
var reachable := true            ## Ziel liegt (nahezu) am Ende des Netzpfads
var path_len := 0.0
var cover_points := 0
var plans := 0
var planned_on_nav := false     ## Route wurde mit fertigem Navigationsnetz geplant

# --- Festhängen ---
var prog_t := 0.0                ## s ohne Fortschritt bei gewünschter Bewegung
var stuck_max := 0.0             ## größter Wert von prog_t (Test/Debug)
var stuck_events := 0
var nudges := 0
var side_pos := Vector3.INF      ## Ausweichpunkt (seitlich)
var side_t := 0.0
var _prog_pos := Vector3.INF
var _stage := 0


# --- Netz-Hilfen (statisch) -----------------------------------------------------------------------

static func map_of(n: Node3D) -> RID:
	return n.get_world_3d().navigation_map


static func nav_ready(n: Node3D) -> bool:
	var m := map_of(n)
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) <= 0:
		return false
	# Missionsnetz wird asynchron gebacken: vorher liefert die Karte (0,0,0) als „nächsten Punkt“
	var mi = Game.current_mission()
	return mi == null or mi.get("nav_ready") != false


static func closest(n: Node3D, p: Vector3) -> Vector3:
	if not nav_ready(n):
		return p
	var c := NavigationServer3D.map_get_closest_point(map_of(n), p)
	if c == Vector3.ZERO and p.length() > 3.0:
		return p                 # keine Netzfläche (Abfrage fehlgeschlagen)
	return c


static func path(n: Node3D, a: Vector3, b: Vector3) -> PackedVector3Array:
	if not nav_ready(n):
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map_of(n), a, b, true)


static func length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func ends_near(pts: PackedVector3Array, b: Vector3, h := 2.5, v := 2.5) -> bool:
	return pts.size() > 0 and flat(pts[pts.size() - 1], b) < h and absf(pts[pts.size() - 1].y - b.y) < v


## Punkt liegt auf dem Netz (nächster Netzpunkt waagerecht/senkrecht nah)
static func on_nav(n: Node3D, p: Vector3, h := 1.0, v := 1.6) -> bool:
	var c := closest(n, p)
	return flat(c, p) < h and absf(c.y - p.y) < v


## Weglänge über das Netz (INF, wenn das Ziel nicht erreichbar ist)
static func path_cost(n: Node3D, a: Vector3, b: Vector3) -> float:
	var pts := path(n, a, b)
	if pts.size() < 2:
		return a.distance_to(b) if a.distance_to(b) < 3.0 else INF
	return length(pts) if ends_near(pts, b, 3.0, 3.0) else INF


## Deckungswert eines Bodenpunkts: Hindernisse ringsum in Hüfthöhe (verdeckt/geschützt) und – falls bekannt –
## vom Bedrohungspunkt aus verdeckt (+3)
static func cover_score(space: PhysicsDirectSpaceState3D, p: Vector3, threat: Vector3) -> float:
	var s := 0.0
	var o := p + Vector3.UP * 0.9
	for i in 6:
		var a := TAU * float(i) / 6.0
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0, sin(a)) * 3.0, 1)
		if not space.intersect_ray(q).is_empty():
			s += 1.0
	if threat.is_finite():
		var q2 := PhysicsRayQueryParameters3D.create(threat, o, 1)
		if not space.intersect_ray(q2).is_empty():
			s += 3.0
	return s


# --- Route ------------------------------------------------------------------------------------------

## Route zum Ziel planen. use_cover: Zwischenpunkte an Deckungen nahe dem Weg (nur wenn der Umweg gering ist).
## Rückgabe: Ziel erreichbar (sonst führt die Route zum nächsten erreichbaren Punkt).
func plan(s: Soldier, to: Vector3, threat: Vector3, use_cover: bool) -> bool:
	plans += 1
	planned_on_nav = nav_ready(s)
	waypoints = PackedVector3Array()
	wp_i = 0
	dest = to
	cover_points = 0
	side_t = 0.0
	var from := s.global_position
	var pts := path(s, from, to)
	if pts.size() < 2:
		path_len = from.distance_to(to)
		reachable = path_len < 3.0 or not nav_ready(s)
		waypoints.append(to)
		return reachable
	reachable = ends_near(pts, to)
	path_len = length(pts)
	if use_cover and path_len > COVER_SEG * 1.6:
		var space := s.get_world_3d().direct_space_state
		var acc := 0.0
		var next_at := COVER_SEG
		var last_wp := from
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var seg := a.distance_to(b)
			while acc + seg >= next_at and next_at < path_len - 10.0:
				var p := a.lerp(b, (next_at - acc) / maxf(seg, 0.001))
				var c := _cover_near(s, space, p, threat)
				if c.is_finite() and c.distance_to(last_wp) > 7.0:
					waypoints.append(c)
					last_wp = c
					cover_points += 1
				next_at += COVER_SEG
			acc += seg
	waypoints.append(pts[pts.size() - 1] if not reachable else to)
	return reachable


## Deckung in der Nähe eines Wegpunkts: besser gedeckt als der Wegpunkt selbst, auf derselben Seite von Wänden
func _cover_near(s: Soldier, space: PhysicsDirectSpaceState3D, p: Vector3, threat: Vector3) -> Vector3:
	var base := cover_score(space, p, threat)
	var best := Vector3.INF
	var best_s := maxf(base + 1.0, 2.0)
	var a0 := randf() * TAU
	for i in 6:
		var a := a0 + TAU * float(i) / 6.0
		var c := closest(s, p + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, COVER_DETOUR))
		if absf(c.y - p.y) > 2.0 or flat(c, p) > COVER_DETOUR + 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, c + Vector3.UP * 1.0, 1)
		if not space.intersect_ray(q).is_empty():
			continue           # hinter einer Wand: kein kurzer Umweg
		var sc := cover_score(space, c, threat)
		if sc >= best_s:
			best_s = sc
			best = c
	return best


## Aktueller Steuerpunkt: Ausweichpunkt oder nächster nicht erreichter Zwischenpunkt
func steer(s: Soldier) -> Vector3:
	if side_t > 0.0 and side_pos.is_finite():
		return side_pos
	while wp_i < waypoints.size() - 1 and flat(s.global_position, waypoints[wp_i]) < WP_REACH:
		wp_i += 1
	if wp_i < waypoints.size():
		return waypoints[wp_i]
	return dest


## Steuerpunkt ist eine Deckung auf dem Weg (nicht das Endziel)
func at_cover_waypoint(s: Soldier) -> bool:
	return wp_i < waypoints.size() - 1 and flat(s.global_position, waypoints[wp_i]) < WP_REACH + 0.5


func remaining(s: Soldier) -> float:
	if waypoints.is_empty():
		return INF
	var l := s.global_position.distance_to(waypoints[mini(wp_i, waypoints.size() - 1)])
	for i in range(wp_i + 1, waypoints.size()):
		l += waypoints[i - 1].distance_to(waypoints[i])
	return l


func clear() -> void:
	waypoints = PackedVector3Array()
	wp_i = 0
	dest = Vector3.INF


# --- Festhängen -------------------------------------------------------------------------------------

## Je Physikschritt. Rückgabe = Maßnahme: 0 keine, 1 springen/klettern, 2 seitlich ausweichen,
## 3 neu planen, 4 Ziel aufgeben, 5 aufs Netz setzen
func track(s: Soldier, delta: float, wants_move: bool) -> int:
	var p := s.global_position
	if side_t > 0.0:
		side_t -= delta
	if not _prog_pos.is_finite() or p.distance_to(_prog_pos) > PROGRESS_DIST or not wants_move:
		_prog_pos = p
		prog_t = 0.0
		_stage = 0
		return 0
	prog_t += delta
	stuck_max = maxf(stuck_max, prog_t)
	var act := 0
	if _stage == 0 and prog_t > 2.0:
		act = 1
	elif _stage == 1 and prog_t > 4.0:
		act = 2
	elif _stage == 2 and prog_t > 7.0:
		act = 3
	elif _stage == 3 and prog_t > 9.5:
		act = 2
	elif _stage == 4 and prog_t > 12.5:
		act = 4
	elif _stage == 5 and prog_t > 15.5:
		act = 5
	if act != 0:
		_stage += 1
		stuck_events += 1
	return act


## Seitlich ausweichen: Netzpunkt 3–6 m quer zur Wunschrichtung, 2 s lang direkt ansteuern
func sidestep(s: Soldier, toward: Vector3) -> void:
	var d := toward - s.global_position
	d.y = 0.0
	if d.length() < 0.1:
		d = s.forward()
	var perp: Vector3 = Vector3(-d.z, 0, d.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	for k in 2:
		var c := closest(s, s.global_position + perp * randf_range(3.0, 6.0) - d.normalized() * 1.0)
		if flat(c, s.global_position) > 1.2:
			side_pos = c
			side_t = 2.0
			return
		perp = -perp
	side_pos = closest(s, s.global_position - d.normalized() * 3.0)
	side_t = 2.0


## Letzte Abhilfe nach > 15 s ohne Fortschritt: Soldat liegt neben dem Netz (z. B. in einer Kollisionslücke
## eingeklemmt) → auf den nächsten Netzpunkt setzen; auf dem Netz → 1 m Richtung Weg versetzen, falls dort frei.
## Bewusste Notlösung (wie Unstuck-Hilfen anderer Spiele), nur KI-Soldaten.
func nudge(s: Soldier, toward: Vector3) -> bool:
	var p := s.global_position
	var c := closest(s, p)
	var target := Vector3.INF
	if flat(c, p) > 0.8 or absf(c.y - p.y) > 1.5:
		target = c
	else:
		var pts: PackedVector3Array = path(s, p, toward if toward.is_finite() else p)
		if pts.size() >= 2:
			var d := pts[1] - p
			d.y = 0.0
			target = closest(s, p + d.normalized() * minf(1.2, d.length()))
	if not target.is_finite() or not s.has_method("_fits") or not s._fits(target + Vector3.UP * 0.05):
		return false
	s.global_position = target + Vector3.UP * 0.05
	s.velocity = Vector3.ZERO
	nudges += 1
	_prog_pos = Vector3.INF
	return true
