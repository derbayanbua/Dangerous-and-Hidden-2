class_name BotGoals
extends RefCounted
## Zielwahl der Mehrspieler-KI-Soldaten (Server, je Gruppenführer):
##  BESETZUNG   – nächste angreifbare Zone (FRONTLINE: nur Nachbarzonen, Net._attackable) nach Weglänge über das
##                Netz, Gruppen verteilen sich auf verschiedene Zonen; eigene bedrohte Zone verteidigen (Einnahme
##                läuft oder Feind in der Nähe gemeldet); sonst frontnächste eigene Zone halten
##  HD2-AUFGABEN – eigene Aufgaben: Aufgabenobjekt aufsuchen und benutzen (Sprengsatz anbringen, Schalter, Funk …);
##                gegnerische Aufgaben: Objekt verteidigen (scharfe Ladungen entschärfen)
##  DEATHMATCH  – Gegner suchen (bekannte Feindlage, sonst ferne Spawnbereiche)
## Dazu Stellungssuche: Halteplatz in der Zone (Deckung, Abstand), Camper-/Scharfschützenstellung mit Sichtlinie.
## Zielpunkte liegen immer auf dem Navigationsnetz; unerreichbare Ziele werden gemieden (Sperrliste je Bot).

static var _zone_pts := {}       ## "<mission>:<zone>" -> Netzpunkt in der Zone
static var armed_by := {}         ## Sprengplatz (instance_id) -> Team, das die Ladung angebracht hat
static var _obj_pts := {}        ## "<mission>:<aufgabe>" -> [Netzpunkt, Interactable]


## Spielzeit in s (Physikschritte, unabhängig von Rechnerlast)
static func now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## feste, je Bot und Ziel verschiedene Zufallsgewichtung (kein Pendeln durch neue Zufallswerte)
static func _bias(b: Node, key: String) -> float:
	return float(absi(hash(String(b.soldier.soldier_name) + key)) % 25)


static func ground(s: Node3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 40.0, 1)
	var hit := s.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


static func in_zone(z: Dictionary, p: Vector3) -> bool:
	return Net.zone_contains(z, p + Vector3.UP * 0.5)


static func zone_radius(z: Dictionary) -> float:
	if String(z.get("shape", "sphere")) == "box":
		var sc: Vector3 = z["scale"]
		return maxf(minf(sc.x, sc.z) * 0.5, 2.0)
	return maxf(float(z.get("radius", 5.0)), 2.0)


## Netzpunkt innerhalb der Zone (Mittelpunkt kann in der Luft liegen → Boden, Spawnplätze, Ring)
static func zone_point(b: Node, m: Node, i: int) -> Vector3:
	var key := "%d:%d" % [m.get_instance_id(), i]
	if _zone_pts.has(key):
		return _zone_pts[key]
	var s: Soldier = b.soldier
	var z: Dictionary = m.mp_zones()[i]
	var c: Vector3 = (z["xf"] as Transform3D).origin
	var r := zone_radius(z)
	var cands: Array = [ground(s, c)]
	for sl in z.get("slots", []):
		cands.append(sl["pos"])
	for rr: float in [0.45, 0.8]:
		for k in 8:
			var a := TAU * float(k) / 8.0
			cands.append(ground(s, c + Vector3(cos(a), 0, sin(a)) * r * rr))
	# erster Netzpunkt in der Zone, der vom Bot aus über das Netz erreichbar ist (Dach/abgetrennte Fläche meiden)
	var best := Vector3.INF
	var first := Vector3.INF
	for p in cands:
		var q := BotNav.closest(s, p)
		if not in_zone(z, q) or BotNav.flat(q, p) > 2.5:
			continue
		if not first.is_finite():
			first = q
		if not BotNav.nav_ready(s) or BotNav.path_cost(s, s.global_position, q) < INF:
			best = q
			break
	if not best.is_finite():
		best = first
	if not best.is_finite():
		best = BotNav.closest(s, ground(s, c))
	if BotNav.nav_ready(s):
		_zone_pts[key] = best
	return best


## Interaktives Aufgabenobjekt nahe einem Aufgabenpunkt (Sprengplatz, Schalter, Funkgerät, Gegenstand …)
static func objective_interactable(tree: SceneTree, p: Vector3) -> Interactable:
	var best: Interactable = null
	var bd := 6.0
	for n in tree.get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not usable_kind(it):
			continue
		var d := it.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = it
	return best


## Für Aufgaben nutzbare Objektarten (keine Leitern, Türen, Kisten, Leichen, Waffenstellungen)
static func usable_kind(it: Interactable) -> bool:
	return not (it is OrigInteractive.OrigLadder or it is OrigInteractive.OrigDoor or it is Door or it is Pickups.Loot
		or it is OrigInteractive.OrigCrate or it is OrigInteractive.OrigEmplacement)


## [Netzpunkt zum Benutzen, Interactable oder null]
static func objective_target(b: Node, m: Node, idx: int, p: Vector3) -> Array:
	var key := "%d:%d" % [m.get_instance_id(), idx]
	if _obj_pts.has(key) and (_obj_pts[key][1] == null or is_instance_valid(_obj_pts[key][1])):
		return _obj_pts[key]
	var s: Soldier = b.soldier
	var it := _named_interactable(b.get_tree(), String(_obj_frames.get(idx, "")))
	if it == null:
		it = objective_interactable(b.get_tree(), p)
	var at: Vector3 = it.global_position if it else p
	var q := BotNav.closest(s, at)
	if BotNav.flat(q, at) > 2.2 or absf(q.y - at.y) > 2.4:
		var bd := INF
		for k in 8:
			var a := TAU * float(k) / 8.0
			var c := BotNav.closest(s, at + Vector3(cos(a), 0, sin(a)) * 1.4)
			var d := c.distance_to(at)
			if d < bd:
				bd = d
				q = c
	var r := [q, it]
	if BotNav.nav_ready(s):
		_obj_pts[key] = r
	return r


static func _brains(b: Node) -> Array:
	var out: Array = []
	for t in BotSquad.team_soldiers(b.get_tree(), b.soldier.team):
		var o := (t as Node).get_node_or_null("EnemyBrain")
		if o is BotBrain:
			out.append(o)
	return out


## Wie viele andere Gruppen des Teams haben dieses Ziel?
static func _others_on(b: Node, zone: int, obj: int) -> int:
	var n := 0
	var my_lead: Node = b.leader()
	for o in _brains(b):
		if o == b or o.leader() == my_lead or not o.is_leader():
			continue
		if (zone >= 0 and o.goal_zone == zone) or (obj >= 0 and o.goal_obj == obj):
			n += 1
	return n


## Eigene Zone bedroht: Einnahme durch den Gegner läuft (Zonenanzeige) oder die Gruppe kennt Feinde in der Nähe
static func zone_threatened(b: Node, m: Node, i: int) -> bool:
	var team: int = b.soldier.team
	if Net.zone_attacker.size() > i and int(Net.zone_attacker[i]) not in [-1, team] \
			and Net.zone_progress.size() > i and float(Net.zone_progress[i]) > 0.0:
		return true
	var z: Dictionary = m.mp_zones()[i]
	var c: Vector3 = (z["xf"] as Transform3D).origin
	var r := zone_radius(z) + 15.0
	for o in b.group:
		if not is_instance_valid(o) or not o.soldier or not o.soldier.alive:
			continue
		for t in o.perception.last_known:
			if is_instance_valid(t) and t.alive and float(o.perception.awareness.get(t, 0.0)) > 0.3 \
					and BotNav.flat(o.perception.last_known[t], c) < r:
				return true
	return false


static func _cand(pos: Vector3, kind: String, zone: int, obj: int, cost: float) -> Dictionary:
	return {"pos": pos, "kind": kind, "zone": zone, "obj": obj, "cost": cost, "key": "%s:%d:%d" % [kind, zone, obj]}


## Ziele bewerten. Rückgabe {"best": Kandidat, "current": Bewertung des aktuellen Ziels (oder leer)}
static func choose(b: Node) -> Dictionary:
	var m = Game.current_mission()
	if m == null:
		return {}
	var s: Soldier = b.soldier
	var team := s.team
	var cands: Array = []
	var md := Net.mode()
	if md == Net.Mode.OCCUPATION and m.has_method("mp_zones"):
		cands = _occupation(b, m, team)
	elif md == Net.Mode.OBJECTIVES:
		cands = _objectives(b, m, team)
	if cands.is_empty():
		var h := hunt_point(b, m)
		if h.is_finite():
			cands.append(_cand(h, "hunt", -1, -1, s.global_position.distance_to(h)))
	# Weglänge über das Netz für die besten Kandidaten (Luftlinie täuscht bei Mauern/Gebäuden)
	cands.sort_custom(func(x, y): return float(x["cost"]) < float(y["cost"]))
	var t := now()
	for k in mini(cands.size(), 4):
		var c: Dictionary = cands[k]
		var straight := s.global_position.distance_to(c["pos"])
		var pc := BotNav.path_cost(s, s.global_position, c["pos"])
		c["cost"] = float(c["cost"]) - straight + (pc if pc < INF else straight + 250.0)
		c["reachable"] = pc < INF
	var best: Dictionary = {}
	var cur: Dictionary = {}
	for c in cands:
		if float(b._blacklist.get(c["key"], -1.0)) > t:
			continue
		if best.is_empty() or float(c["cost"]) < float(best["cost"]):
			best = c
		if c["kind"] == b.goal_kind and int(c["zone"]) == b.goal_zone and int(c["obj"]) == b.goal_obj:
			cur = c
	if best.is_empty() and not cands.is_empty():
		# alle Spielziele zurzeit unerreichbar (gesperrt): Gegner suchen statt stehen zu bleiben
		var h2 := hunt_point(b, m)
		if h2.is_finite():
			best = _cand(h2, "hunt", -1, -1, s.global_position.distance_to(h2))
	return {"best": best, "current": cur}


static func _occupation(b: Node, m: Node, team: int) -> Array:
	var out: Array = []
	var zs: Array = m.mp_zones()
	var s: Soldier = b.soldier
	var n := mini(zs.size(), Net.zone_owner.size())
	for i in n:
		var z: Dictionary = zs[i]
		if not z["capturable"]:
			continue
		var owner := int(Net.zone_owner[i])
		var p := zone_point(b, m, i)
		var d := s.global_position.distance_to(p)
		if owner != team and Net._attackable(m, i, team):
			var cost := d + _bias(b, "z%d" % i) + 70.0 * _others_on(b, i, -1)
			if Net.zone_attacker.size() > i and int(Net.zone_attacker[i]) == team:
				cost -= 25.0          # Einnahme läuft bereits: unterstützen
			out.append(_cand(p, "attack_zone", i, -1, cost))
		elif owner == team and zone_threatened(b, m, i) and d < 180.0:
			out.append(_cand(p, "defend_zone", i, -1, d - 90.0 + 50.0 * _others_on(b, i, -1)))
	if out.is_empty():
		# alles eingenommen bzw. nichts angreifbar: eigene Zone an der Front halten (Gruppen verteilt)
		for i in n:
			if int(Net.zone_owner[i]) == team and zs[i]["capturable"]:
				var p := zone_point(b, m, i)
				out.append(_cand(p, "hold_zone", i, -1, Net._front_dist(zs, i, team) + 0.3 * s.global_position.distance_to(p)
					+ 60.0 * _others_on(b, i, -1) + _bias(b, "h%d" % i)))
	return out


static func _objectives(b: Node, m: Node, team: int) -> Array:
	var out: Array = []
	if not m.has_method("mp_objective_points"):
		return out
	var pts := objective_points(m)
	var s: Soldier = b.soldier
	for o in m.mp_objectives():
		var idx := int(o["index"])
		if Net.obj_done.has(idx) or not pts.has(idx):
			continue
		var tg := objective_target(b, m, idx, pts[idx])
		var p: Vector3 = tg[0]
		var d := s.global_position.distance_to(p)
		if int(o["team"]) == team:
			out.append(_cand(p, "use_obj", -1, idx, d + _bias(b, "o%d" % idx) + 60.0 * _others_on(b, -1, idx)))
		else:
			out.append(_cand(p, "defend_obj", -1, idx, d + 30.0 + _bias(b, "o%d" % idx) + 60.0 * _others_on(b, -1, idx)))
	return out


## Lage je Aufgabe: wie mp_arena.mp_objective_points, aber Mittelpunkt der sichtbaren Geometrie des Objekt-Frames
## (Frame-Ursprung liegt bei manchen Karten im Weltursprung, z. B. ARCTIC1_OBJ)
static func objective_points(m: Node) -> Dictionary:
	var mp = m.get("mp")
	var rt = m.get("runtime")
	if typeof(mp) != TYPE_DICTIONARY or rt == null:
		return m.mp_objective_points()
	var out := {}
	var facts: Dictionary = mp.get("scripts", {}).get("facts", {})
	var assign: Dictionary = {}
	for k in mp.get("scripts", {}).get("assignments", {}):
		assign.merge(mp["scripts"]["assignments"][k])
	for frame in assign:
		# Organisations-/Steuerskripte (z. B. „dummy_obj_organizer“) liegen nicht am Aufgabenort
		if String(frame).to_lower().contains("organizer"):
			continue
		var f: Dictionary = facts.get(String(assign[frame]).to_lower(), {})
		for st in f.get("set_objective_status", []):
			if int(st[1]) != 1:
				continue
			var node: Node3D = rt.find_frame(String(frame))
			if node == null or not node.is_inside_tree():
				continue
			var bb := OrigInteractive.world_aabb(node)
			out[int(st[0])] = bb.get_center() if bb.size.length() > 0.01 else node.global_position
			_obj_frames[int(st[0])] = String(frame)
	return out


static var _obj_frames := {}     ## Aufgabe -> Frame-Name des meldenden Objekts


## Ziffern am Namensende (z. B. „dummy_exp_02“ → 2, „Explosive_expl_1“ → 1), -1 wenn keine
static func _trailing_num(s: String) -> int:
	var re := RegEx.new()
	re.compile("(\\d+)\\D*$")
	var r := re.search(s)
	return int(r.get_string(1)) if r else -1


## Zum Aufgaben-Frame gehöriges Objekt über den Namen (Platzhalter „dummy_exp_02“ meldet Sprengplatz „expl_02“)
static func _named_interactable(tree: SceneTree, frame: String) -> Interactable:
	var num := _trailing_num(frame)
	if num < 0:
		return null
	var stem := frame.to_lower().replace("dummy", "")
	var letters := ""
	for ch in stem:
		if ch >= "a" and ch <= "z":
			letters += ch
	if letters.length() < 3:
		return null
	for n in tree.get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it and usable_kind(it) and _trailing_num(String(it.name)) == num and String(it.name).to_lower().contains(letters.substr(0, 3)):
			return it
	return null


## Deathmatch/ohne Ziel: Gegner suchen (bekannte Feindlage, sonst ferner Spawnbereich)
static func hunt_point(b: Node, m: Node) -> Vector3:
	var s: Soldier = b.soldier
	for t in b.perception.last_known:
		if is_instance_valid(t) and t.alive and float(b.perception.awareness.get(t, 0.0)) > 0.3:
			return BotNav.closest(s, b.perception.last_known[t])
	var sp: Array = m.mp_spawns() if m.has_method("mp_spawns") else []
	if sp.is_empty():
		return Vector3.INF
	var far: Array = sp.filter(func(p): return (p["pos"] as Vector3).distance_to(s.global_position) > 25.0)
	var pick: Array = far if not far.is_empty() else sp
	return BotNav.closest(s, pick[randi() % pick.size()]["pos"])


# --- Stellungen -------------------------------------------------------------------------------------

## Halteplatz nahe center (in der Zone z, falls angegeben): gedeckt gegen threat, Abstand zu Kameraden, erreichbar
static func hold_spot(b: Node, center: Vector3, z: Dictionary, rmin: float, rmax: float, threat: Vector3) -> Vector3:
	var s: Soldier = b.soldier
	var space := s.get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_s := -INF
	var teye: Vector3 = threat + Vector3.UP * 1.5 if threat.is_finite() else Vector3.INF
	for k in 12:
		var a := randf() * TAU
		var q := BotNav.closest(s, center + Vector3(cos(a), 0, sin(a)) * randf_range(rmin, rmax))
		if absf(q.y - center.y) > 4.0 or (not z.is_empty() and not in_zone(z, q)):
			continue
		if BotSquad.too_close(b, q, BotSquad.MIN_SPACING + 1.0):
			continue
		var sc := BotNav.cover_score(space, q, teye) - q.distance_to(s.global_position) * 0.03
		if sc > best_s:
			best_s = sc
			best = q
	if best.is_finite() and BotNav.path_cost(s, center, best) > (rmax + 4.0) * 3.0:
		return Vector3.INF          # anderes Stockwerk / hinter Mauer ohne Durchgang
	return best


## Camper-/Scharfschützenstellung: rmin–rmax um look_at, freie Sicht von dort (hockend) auf look_at, verdeckt
## (Hindernisse ringsum bzw. gegen threat), auf Wunsch erhöht; nicht näher als 12 m an avoid (Stellungswechsel).
static func overwatch_spot(b: Node, look_at: Vector3, rmin: float, rmax: float, prefer_high: bool,
		avoid: Vector3, threat: Vector3) -> Vector3:
	var s: Soldier = b.soldier
	var space := s.get_world_3d().direct_space_state
	var scored: Array = []
	var mid := (rmin + rmax) * 0.5
	var teye: Vector3 = threat + Vector3.UP * 1.5 if threat.is_finite() else Vector3.INF
	for k in 16:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		var yoff: float = randf_range(0.0, 8.0) if prefer_high and k % 2 == 0 else 0.0
		var q := BotNav.closest(s, ground(s, look_at + Vector3(cos(a), 0, sin(a)) * r) + Vector3.UP * yoff)
		var dist := BotNav.flat(q, look_at)
		if dist < rmin * 0.7 or dist > rmax * 1.3:
			continue
		if avoid.is_finite() and BotNav.flat(q, avoid) < 12.0:
			continue
		if BotSquad.too_close(b, q, BotSquad.MIN_SPACING + 2.0):
			continue
		var eye := q + Vector3.UP * 1.0
		var los := PhysicsRayQueryParameters3D.create(eye, look_at + Vector3.UP * 1.0, 1)
		var hit := space.intersect_ray(los)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(look_at) > 2.5:
			continue
		var sc := BotNav.cover_score(space, q, teye)
		if prefer_high:
			sc += clampf(q.y - look_at.y, 0.0, 8.0) * 0.6
		sc -= absf(dist - mid) * 0.04
		scored.append([sc, q])
	scored.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	for k in mini(scored.size(), 3):
		if BotNav.path_cost(s, s.global_position, scored[k][1]) < INF:
			return scored[k][1]
	return Vector3.INF


## Bedrohungsrichtung einer Zone: nächstgelegene nicht eigene Zone bzw. gegnerischer Spawnbereich
static func threat_dir_point(b: Node, m: Node, center: Vector3) -> Vector3:
	var team: int = b.soldier.team
	var best := Vector3.INF
	var bd := INF
	if m.has_method("mp_zones") and Net.mode() == Net.Mode.OCCUPATION:
		var zs: Array = m.mp_zones()
		for i in mini(zs.size(), Net.zone_owner.size()):
			if int(Net.zone_owner[i]) != team:
				var c: Vector3 = (zs[i]["xf"] as Transform3D).origin
				var d := c.distance_to(center)
				if d > 5.0 and d < bd:
					bd = d
					best = c
	if not best.is_finite() and m.has_method("mp_spawns"):
		for sp in m.mp_spawns():
			if int(sp.get("team", -1)) not in [-1, team]:
				var d := (sp["pos"] as Vector3).distance_to(center)
				if d > 5.0 and d < bd:
					bd = d
					best = sp["pos"]
	return best
