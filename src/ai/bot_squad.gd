class_name BotSquad
extends RefCounted
## Trupp-Taktik der Mehrspieler-KI-Soldaten (Server): Mindestabstände, getrennte Deckungen (belegte Punkte je
## Team), Formation mit Abstand (5–15 m) bzw. Kolonne auf der Spur des Führers in engen Bereichen.
## Nur BotBrain verwendet diese Klasse.

const MIN_SPACING := 5.0         ## Mindestabstand zwischen KI-Soldaten eines Teams (Ziel-/Deckungspunkte)
const SEPARATION_R := 3.5        ## darunter weichen sich laufende/stehende KI-Soldaten aus
## Formation (lokal, +Z = hinter dem Führer): Keil mit 7 m Seitenabstand, Schlussmann 12 m dahinter
const SLOT_OFFSETS := [Vector3(0, 0, 0), Vector3(-7, 0, 6), Vector3(7, 0, 6), Vector3(0, 0, 12)]

static var _claims := {}         ## instance_id -> [team, Vector3]
static var _mate_frame := -1
static var _mates := {}          ## team -> Array[Soldier] (je Physikschritt neu)


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func claim(b: Node, p: Vector3) -> void:
	_claims[b.get_instance_id()] = [b.soldier.team, p]


static func release(b: Node) -> void:
	_claims.erase(b.get_instance_id())


static func claim_of(b: Node) -> Vector3:
	var c = _claims.get(b.get_instance_id())
	return c[1] if c != null else Vector3.INF


## Lebende Soldaten eines Teams (Spieler und KI), je Physikschritt zwischengespeichert
static func team_soldiers(tree: SceneTree, team: int) -> Array:
	var f := Engine.get_physics_frames()
	if f != _mate_frame:
		_mate_frame = f
		_mates.clear()
		for n in tree.get_nodes_in_group("soldiers"):
			var s := n as Soldier
			if s and s.alive:
				if not _mates.has(s.team):
					_mates[s.team] = []
				_mates[s.team].append(s)
	# Zwischenspeicher je Physikbild: bis zum nächsten Bild entfernte Soldaten (Rundenwechsel, Net.leave) auslassen
	return (_mates.get(team, []) as Array).filter(func(s): return is_instance_valid(s))


## Liegt p näher als d an einem Kameraden oder an einem von einem anderen Kameraden belegten Punkt?
static func too_close(b: Node, p: Vector3, d := MIN_SPACING) -> bool:
	var me: Soldier = b.soldier
	for t in team_soldiers(b.get_tree(), me.team):
		if t != me and flat(t.global_position, p) < d and absf(t.global_position.y - p.y) < 3.0:
			return true
	var my := b.get_instance_id()
	var stale: Array = []
	for k in _claims:
		if k == my:
			continue
		if not is_instance_id_valid(k):
			stale.append(k)
			continue
		var c: Array = _claims[k]
		if int(c[0]) == me.team and flat(c[1], p) < d and absf((c[1] as Vector3).y - p.y) < 3.0:
			return true
	for k in stale:
		_claims.erase(k)
	return false


## Nächstgelegener Netzpunkt um p, der den Mindestabstand zu Kameraden einhält (sonst p)
static func spread_point(b: Node, p: Vector3, d := MIN_SPACING, max_r := 12.0) -> Vector3:
	if not too_close(b, p, d):
		return p
	var s: Soldier = b.soldier
	var space := s.get_world_3d().direct_space_state
	var a0 := randf() * TAU
	var r := d
	while r <= max_r:
		for i in 8:
			var a := a0 + TAU * float(i) / 8.0
			var c := BotNav.closest(s, p + Vector3(cos(a), 0, sin(a)) * r)
			if absf(c.y - p.y) > 2.5 or too_close(b, c, d):
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, c + Vector3.UP * 1.0, 1)
			if space.intersect_ray(q).is_empty():
				return c
		r += 2.5
	return p


## Ausweichrichtung (waagerecht, Länge 0..~1) weg von zu nahen Kameraden
static func separation(b: Node, radius := SEPARATION_R) -> Vector3:
	var me: Soldier = b.soldier
	var out := Vector3.ZERO
	for t in team_soldiers(b.get_tree(), me.team):
		if t == me:
			continue
		var d: Vector3 = me.global_position - t.global_position
		d.y = 0.0
		var l: float = d.length()
		if l < radius and absf(t.global_position.y - me.global_position.y) < 2.5:
			if l < 0.05:
				d = Vector3(randf() - 0.5, 0, randf() - 0.5)
				l = 0.05
			out += d.normalized() * (radius - l) / radius
	return out.limit_length(1.0)


## Abstand zum nächsten Kameraden (waagerecht)
static func nearest_mate(b: Node) -> float:
	if not is_instance_valid(b) or not is_instance_valid(b.soldier):
		return INF
	var me: Soldier = b.soldier
	var best := INF
	for t in team_soldiers(b.get_tree(), me.team):
		if t != me:
			best = minf(best, flat(t.global_position, me.global_position))
	return best
