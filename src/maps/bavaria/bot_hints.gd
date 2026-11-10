extends RefCounted
## KI-Hinweispunkte dieser Karte. Die allgemeine Bot-KI fragt sie über diese optionalen Missionsmethoden ab:
##   bot_hints(center, radius) / bot_hint_stance(pos) / bot_route_via(from, to).
## Hinweisarten:
##   trench  – Schützenauftritt, stehend
##   cover   – hinter Felddeckung/Wrack, hockend
##   window  – Fensterplatz im EG, stehend
##   house   – Haus 16 EG/OG/Keller, hockend
##   high    – Dach-/Baumstand, hockend
##   emplacement – Platz an Flak/MG42 mit Schlüssel "emplacement"
## Alle Punkte werden beim Erzeugen ans Navigationsnetz geheftet; Punkte ohne Netz fallen weg.
## Wegfolgen (bot_route_via): Gräben von Rampe zu Rampe, Gartenflanken entlang der Grundstücksmauern.

const FieldTrenches := preload("res://src/maps/bavaria/field_trenches.gd")
const STAND := 0     # Soldier.Stance.STAND
const CROUCH := 1    # Soldier.Stance.CROUCH
## Grundstücksmauern (Referenzpixel, wie bavaria._build_gardens): Flankenwege entlang beider Seiten
const GARDEN_WALLS := [ [[370,555],[567,752]], [[613,785],[764,634]], [[539,898],[658,1013]], [[677,1113],[825,964]],
	[[267,827],[358,917]], [[759,654],[690,727]], [[856,829],[784,900]] ]

var hints: Array[Dictionary] = []
var routes: Array = []           ## je Eintrag Array[Vector3] (Netzpunkte in Reihenfolge)
var on_nav := false              ## mit fertigem Netz erzeugt (sonst später erneut)
var dropped := 0


func build(m) -> void:
	hints.clear()
	routes.clear()
	dropped = 0
	on_nav = bool(m.get("nav_ready"))
	var nav_map: RID = m.get_world_3d().navigation_map
	var raw: Array[Dictionary] = []
	# Gräben: je Abschnitt Punkte auf beiden Seiten nahe der Wand; der höhere ist der Schützenauftritt
	for t in FieldTrenches.TRENCHES:
		var pts: Array = t.points
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var nrm := Vector2(-(b - a).y, (b - a).x).normalized()
			for f in [0.3, 0.7]:
				var c := a.lerp(b, f)
				for sgn in [-1.0, 1.0]:
					var q: Vector2 = c + nrm * sgn * 0.45
					raw.append({"pos": Vector3(q.x, FieldTrenches.STEP_TOP, q.y), "kind": "trench", "stance": STAND})
		var line := FieldTrenches.full_polyline(t.points)
		var seq: Array = []
		for p in line:
			seq.append(Vector3(p.x, -FieldTrenches.DEPTH, p.y))
		routes.append(seq)
	for c in FieldTrenches.COVERS:
		if String(c[0]) == "crater":
			continue
		var p: Vector2 = c[1]
		var r := 2.2 if String(c[0]) in ["sandbag_nest", "wagon", "haystack"] else 1.6
		for k in 4:
			var a := TAU * float(k) / 4.0 + float(c[2])
			raw.append({"pos": Vector3(p.x + cos(a) * r, 0.0, p.y + sin(a) * r), "kind": "cover", "stance": CROUCH})
	for g in ["bavaria_aircraft_wrecks", "bavaria_field_cover"]:
		for n in m.get_tree().get_nodes_in_group(g):
			if n is Node3D:
				var o: Vector3 = (n as Node3D).global_position
				for k in 6:
					var a := TAU * float(k) / 6.0
					raw.append({"pos": o + Vector3(cos(a), 0, sin(a)) * 3.0, "kind": "cover", "stance": CROUCH})
	for h in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		var house := h as Node3D
		if house == null:
			continue
		for w in house.get_meta("shooting_windows", []):
			var wl: Vector3 = w
			raw.append({"pos": house.to_global(Vector3(wl.x, 0.1, wl.z - signf(wl.z) * 0.7)), "kind": "window", "stance": STAND})
		if String(house.name) == "haus_16":
			for lp in [Vector3(-2.5, 0.1, 2.0), Vector3(2.5, 0.1, 2.0), Vector3(-2.5, 3.3, 1.5), Vector3(2.5, 3.3, -1.5),
					Vector3(-1.0, -2.3, 1.0)]:
				raw.append({"pos": house.to_global(lp), "kind": "house", "stance": CROUCH})
	var pd = m.get("scene_details")
	if pd:
		for key in ["tree_stand", "antenna_stand"]:   # kein Dachsteg (11/2026); Antennenplattform per Steigleiter = erhöhter Posten
			var v = pd.get(key)
			if v is Vector3 and v != Vector3.ZERO:
				raw.append({"pos": v, "kind": "high", "stance": CROUCH, "high": true, "raw": key == "antenna_stand"})   # Plattform liegt nicht im Navmesh (Leiter)
	# Waffenstellungen der Karte (Flak auf der Wiese, MG42 im Holzhaus)
	for holder in [m.get("field_emplacement"), m.get("woodland_emplacement")]:
		if holder and is_instance_valid(holder.get("gun")):
			var gun = holder.gun
			raw.append({"pos": gun.gunner_spot(), "kind": "emplacement", "stance": STAND, "emplacement": gun, "raw": true})
	# ans Netz heften
	for h in raw:
		if h.get("raw", false) or not on_nav:
			hints.append(h)
			continue
		var p: Vector3 = h.pos
		var q := NavigationServer3D.map_get_closest_point(nav_map, p)
		if Vector2(q.x - p.x, q.z - p.z).length() > 1.2 or absf(q.y - p.y) > 1.5:
			dropped += 1
			continue
		h.pos = q
		hints.append(h)
	# Gartenflanken: beidseits der Mauern je ein Weg (Anfang → Ende), 1,6 m Abstand
	for pair in GARDEN_WALLS:
		var a: Vector3 = m.pixel(pair[0])
		var b: Vector3 = m.pixel(pair[1])
		var side := Vector3(-(b - a).z, 0, (b - a).x).normalized()
		for sgn in [-1.0, 1.0]:
			routes.append([a + side * sgn * 1.6, a.lerp(b, 0.5) + side * sgn * 1.6, b + side * sgn * 1.6])
	if on_nav:
		var ok: Array = []
		for seq in routes:
			var out: Array = []
			for p in seq:
				var q := NavigationServer3D.map_get_closest_point(nav_map, p)
				if Vector2(q.x - p.x, q.z - p.z).length() <= 1.5:
					out.append(q)
			if out.size() >= 2:
				ok.append(out)
		routes = ok


func near(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for h in hints:
		var p: Vector3 = h.pos
		if Vector2(p.x - center.x, p.z - center.z).length_squared() <= r2:
			out.append(h)
	return out


func stance_at(pos: Vector3) -> int:
	for h in hints:
		var p: Vector3 = h.pos
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 1.5 and absf(p.y - pos.y) < 1.6:
			return int(h.stance)
	return -1


## Wegfolgen, die ungefähr zwischen from und to liegen (Umweg-Ellipse), Richtung passend gedreht, höchstens 4
func route_via(from: Vector3, to: Vector3) -> Array:
	var direct := Vector2(to.x - from.x, to.z - from.z).length()
	if direct < 30.0:
		return []
	var scored: Array = []
	for seq in routes:
		var s: Array = seq
		var a: Vector3 = s[0]
		var b: Vector3 = s[s.size() - 1]
		if _flat(from, b) < _flat(from, a):
			s = s.duplicate()
			s.reverse()
			a = s[0]
			b = s[s.size() - 1]
		var detour := _flat(from, a) + _flat(a, b) + _flat(b, to)
		if detour <= direct * 1.4 + 10.0 and _flat(a, b) > 8.0:
			scored.append([detour, s])
	scored.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var out: Array = []
	for k in mini(scored.size(), 4):
		out.append(scored[k][1])
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
