extends RefCounted
## Szenendetails Bavaria:
## - Sichtachsen der Aussichtspunkte freiräumen (lose Requisiten aus dem Vordergrund)
## - Gartenseite: Gitterzaun mit offenem Gartentor im Vordergrund
## - Hofseite: Hecke links und gestapelte Steinplatten
## - Garten: Holz-Gartenhaus mit Satteldach
## - Häuserzeile: Reihenhäuser mit Kaminen und Holzbalkonen (Kulisse, ohne Kollision)
## - Haus 18 mit Holzverschalung im OG und Balkon
## Alles nur, wenn Spawns, Zonen, Wege, Grundrisse und Gräben frei bleiben (sonst Meldung, kein Einbau).

const SIGHT_VIEWS := [1, 6]
const SIGHT_FROM := 2.0
const SIGHT_TO := 22.0
const SIGHT_HALF := 2.0

static func view(m, n: int) -> Dictionary:
	for v in m.layout.sight_views:
		if int(v.number) == n:
			var a: Vector3 = m.pixel(v.position)
			var b: Vector3 = m.pixel(v.target)
			return {"from": Vector2(a.x, a.z), "dir": Vector2(b.x - a.x, b.z - a.z).normalized()}
	return {}

## Abstand eines Punktes zur Sichtachse (nur Abschnitt SIGHT_FROM..SIGHT_TO), sonst INF
static func sight_distance(m, p: Vector2) -> float:
	var best := INF
	for n in SIGHT_VIEWS:
		var v := view(m, n)
		if v.is_empty():
			continue
		var rel: Vector2 = p - v.from
		var along: float = rel.dot(v.dir)
		if along < SIGHT_FROM or along > SIGHT_TO:
			continue
		best = minf(best, absf(rel.cross(v.dir)))
	return best

static func _area_free(m, p: Vector2, r: float) -> String:
	if not m.inside_map(Vector3(p.x, 0, p.y)):
		return "Grenze"
	for s in m.layout["spawns"]:
		var sp: Vector3 = m.pixel(s["pixel"])
		if Vector2(sp.x, sp.z).distance_to(p) < r + 3.0:
			return "Spawn"
	for z in m.layout.get("occupation_zones", []):
		var zp: Vector3 = m.pixel(z["pixel"])
		if Vector2(zp.x, zp.z).distance_to(p) < float(z["radius"]) + r + 2.0:
			return "Zone"
	for road in m.layout["paths"]:
		var pts: Array = road["points"]
		for i in pts.size() - 1:
			var a: Vector3 = m.pixel(pts[i])
			var b: Vector3 = m.pixel(pts[i + 1])
			if Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p) < float(road["width"]) * 0.5 + r + 0.6:
				return "Weg " + String(road["id"])
	for f in m.building_footprints:
		if Geometry2D.is_point_in_polygon(p, f):
			return "Grundriss"
		for i in f.size():
			if Geometry2D.get_closest_point_to_segment(p, f[i], f[(i + 1) % f.size()]).distance_to(p) < r + 0.8:
				return "Grundrissnähe"
	return ""

## Nach allen Streu-Requisiten: Sichtachsen 1 und 6 freiräumen.
static func clear_sightlines(m) -> void:
	var removed := 0
	for c in m.static_root.get_children():
		if not (c is Node3D) or not String(c.name).begins_with("Original_") or c.is_in_group("bavaria_furniture") or c.is_in_group("bavaria_all_tree_roots"):
			continue
		var gp: Vector3 = c.global_position
		if sight_distance(m, Vector2(gp.x, gp.z)) < SIGHT_HALF:
			c.free()
			removed += 1
	print("BAVARIA SZENE: Sichtachsen: %d Requisiten entfernt" % removed)

## Vor Deko/Wald/Requisiten: neue Szenenobjekte bauen und als belegt eintragen.
static func build(m) -> void:
	var lb: LevelBuilder = m.lb
	var report: Array = []
	# --- Punkt 6: Gitterzaun mit offenem Gartentor quer vor Standpunkt 6
	var v6 := view(m, 6)
	if not v6.is_empty():
		var center: Vector2 = v6.from + v6.dir * 4.5
		var side: Vector2 = Vector2(-v6.dir.y, v6.dir.x)
		var why := ""
		for k in [-3.5, -1.5, 1.5, 3.5]:
			var q: Vector2 = center + side * k
			var w := _area_free(m, q, 0.3)
			if w != "":
				why = w
		if why == "":
			var fence := Node3D.new()
			fence.name = "Garten_Gitterzaun"
			m.static_root.add_child(fence)
			fence.add_to_group("bavaria_decorations")
			fence.add_to_group("bavaria_scene_match")
			var yaw := atan2(-side.y, side.x)
			for k in [-4.0, -2.0, -0.7, 0.7, 2.0, 4.0]:
				var q: Vector2 = center + side * k
				lb.cylinder(Vector3(q.x, 0, q.y), 0.04, 1.3, "old_steel", true, fence)
			for seg in [[-4.0, -0.7], [0.7, 4.0]]:
				var mid: Vector2 = center + side * ((seg[0] + seg[1]) * 0.5)
				var length: float = seg[1] - seg[0]
				for y in [0.08, 1.2]:
					lb.box(Vector3(mid.x, y, mid.y), Vector3(length, 0.035, 0.035), "old_steel", yaw, false, fence)
				# Maschendraht: dünne, durchschussfreie Kulisse (keine Weltkollision), dazu niedrige Bewegungssperre
				for i in int(length / 0.15):
					var t: float = seg[0] + (i + 0.5) * 0.15
					var q: Vector2 = center + side * t
					lb.box(Vector3(q.x, 0.08, q.y), Vector3(0.012, 1.12, 0.012), "old_steel", yaw, false, fence)
				var block := lb.box(Vector3(mid.x, 0, mid.y), Vector3(length, 1.25, 0.06), "old_steel", yaw, true, fence)
				block.get_child(1).visible = false
				(block as StaticBody3D).collision_layer = 16   # Ebene 5: sperrt Bewegung, nicht Sicht/Schüsse (wie Zäune)
			# offenes Tor (1,2 m Durchgang), Flügel um 70° aufgeschwenkt
			var hinge: Vector2 = center + side * 0.7
			var gate := lb.box(Vector3(hinge.x, 0.08, hinge.y), Vector3(1.3, 1.1, 0.03), "old_steel", yaw + 1.2, false, fence)
			gate.name = "OffenesTor"
			m._placed.append({"pos": Vector3(center.x, 0, center.y), "radius": 4.5})
			report.append("Gartenseite: Gitterzaun mit offenem Tor bei " + str(center))
		else:
			report.append("Gartenseite: Gitterzaun ausgelassen (" + why + ")")
	# --- Hofseite: Hecke links und Steinplattenstapel
	var v2 := view(m, 2)
	if not v2.is_empty():
		var left: Vector2 = Vector2(v2.dir.y, -v2.dir.x)
		var slab: Vector2 = v2.from + v2.dir * 2.6 + left * 1.4
		var w2 := _area_free(m, slab, 0.9)
		if w2 == "":
			var stack := Node3D.new()
			stack.name = "Hof_Steinplatten"
			m.static_root.add_child(stack)
			stack.add_to_group("bavaria_decorations")
			stack.add_to_group("bavaria_scene_match")
			for i in 9:
				var jitter := Vector3(sin(i * 1.7) * 0.06, 0, cos(i * 2.3) * 0.06)
				lb.box(Vector3(slab.x, i * 0.07, slab.y) + jitter, Vector3(1.0, 0.065, 0.62), "stone", 0.3 + sin(i) * 0.08, i == 0, stack)
			m._placed.append({"pos": Vector3(slab.x, 0, slab.y), "radius": 1.2})
			report.append("Hofseite: Steinplattenstapel bei " + str(slab))
		else:
			report.append("Hofseite: Steinplatten ausgelassen (" + w2 + ")")
		var h_a: Vector2 = v2.from + v2.dir * 1.0 + left * 2.6
		var h_b: Vector2 = v2.from + v2.dir * 8.0 + left * 2.6
		var ok := true
		var why2 := ""
		for t in [0.0, 0.33, 0.66, 1.0]:
			var w := _area_free(m, h_a.lerp(h_b, t), 0.6)
			if w != "":
				ok = false
				why2 = w
		if ok:
			lb.line_wall(h_a, h_b, 1.9, 0.9, "hedge")
			m.building_footprints.append(Geometry2D.offset_polyline(PackedVector2Array([h_a, h_b]), 0.5)[0])
			report.append("Hofseite: Hecke %s → %s" % [h_a, h_b])
		else:
			report.append("Hofseite: Hecke ausgelassen (" + why2 + ")")
	# --- Holz-Gartenhaus mit Satteldach nahe dem langen Gewächshaus
	var gh: Vector3 = m.pixel([666, 902])
	var hut_pos := Vector2(gh.x, gh.z)
	var placed_hut := false
	for off in [Vector2(11, 0), Vector2(-11, 0), Vector2(0, 7), Vector2(0, -7), Vector2(12, 6), Vector2(-12, -6)]:
		var q: Vector2 = hut_pos + off
		if _area_free(m, q, 2.6) == "" and sight_distance(m, q) > 3.0:
			_hut(m, Vector3(q.x, 0, q.y), -0.03)
			report.append("Gartenhaus bei " + str(q))
			placed_hut = true
			break
	if not placed_hut:
		report.append("Gartenhaus ausgelassen (kein freier Platz)")
	# --- Punkt 4/7: Fassaden (Kulisse, ohne Kollision)
	var balconies := 0
	for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		var id := String(house.name)
		if not house.has_meta("footprint_size"):
			continue
		var size: Vector2 = house.get_meta("footprint_size")
		if id.begins_with("reihe_") and not house.is_in_group("bavaria_ruins"):
			var hh := 6.2
			var ridge := hh + tan(0.37) * (size.y * 0.5 + 0.4)
			lb.box(Vector3(size.x * 0.22, hh, -size.y * 0.12), Vector3(0.48, ridge - hh + 0.7, 0.48), "brick", 0, false, house)
			lb.box(Vector3(size.x * 0.22, ridge + 0.7, -size.y * 0.12), Vector3(0.6, 0.08, 0.6), "stone", 0, false, house)
			_balcony(lb, house, size, 3.05, 1.0)
			m._templates.merge_building_visuals(house)   # eine gemeinsame Gebäudehülle (Sichtweite/Material)
			balconies += 1
		elif id == "haus_18":
			var mat := "h16_wood" if lb._mats.has("h16_wood") else "wood"
			for s in [-1.0, 1.0]:
				lb.box(Vector3(0, 3.15, s * (size.y * 0.5 + 0.16)), Vector3(size.x - 0.1, 3.3, 0.03), mat, 0, false, house)
			_balcony(lb, house, size, 3.15, 1.2)
			m._templates.merge_building_visuals(house)
			report.append("Haus 18: Holzverschalung OG und Balkon")
	report.append("Reihenhäuser: %d Einheiten mit Kamin und Holzbalkon" % balconies)
	for line in report:
		print("BAVARIA SZENE: ", line)
	m.set_meta("scene_match_report", report)

static func _balcony(lb: LevelBuilder, house: Node3D, size: Vector2, y: float, depth: float) -> void:
	var mat := "h16_wood" if lb._mats.has("h16_wood") else "wood"
	var z := size.y * 0.5 + 0.15 + depth * 0.5
	var bw := size.x - 0.8
	var b := Node3D.new()
	b.name = "Holzbalkon"
	house.add_child(b)
	b.add_to_group("bavaria_scene_match")
	lb.box(Vector3(0, y - 0.14, z), Vector3(bw, 0.14, depth), "darkwood", 0, false, b)
	lb.box(Vector3(0, y, z + depth * 0.5 - 0.03), Vector3(bw, 0.9, 0.04), mat, 0, false, b)
	for sx in [-1.0, 1.0]:
		lb.box(Vector3(sx * (bw * 0.5 - 0.02), y, z), Vector3(0.04, 0.9, depth), mat, 0, false, b)
	for x in [-bw * 0.5 + 0.1, 0.0, bw * 0.5 - 0.1]:
		lb.box(Vector3(x, y - 0.55, z - depth * 0.25), Vector3(0.1, 0.41, depth * 0.5), "darkwood", 0, false, b)   # Konsolen

static func _hut(m, pos: Vector3, yaw: float) -> void:
	var lb: LevelBuilder = m.lb
	var mat := "h16_wood" if lb._mats.has("h16_wood") else "wood"
	var hut := Node3D.new()
	hut.name = "Gartenhaus"
	m.static_root.add_child(hut)
	hut.position = pos
	hut.rotation.y = yaw
	hut.add_to_group("bavaria_decorations")
	hut.add_to_group("bavaria_scene_match")
	var w := 3.6
	var d := 2.8
	var h := 2.2
	for s in [-1.0, 1.0]:
		lb.box(Vector3(0, 0, s * d * 0.5), Vector3(w, h, 0.1), mat, 0, true, hut)
	lb.box(Vector3(-w * 0.5, 0, 0), Vector3(0.1, h, d), mat, 0, true, hut)
	lb.box(Vector3(w * 0.5, 0, -0.6), Vector3(0.1, h, d - 1.2), mat, 0, true, hut)   # Tür offen
	lb.box(Vector3(w * 0.5, 1.95, 0.6), Vector3(0.1, 0.25, 1.2), mat, 0, false, hut)
	for s in [-1.0, 1.0]:
		var r := lb.box(Vector3(0, h + 0.38, s * d * 0.27), Vector3(w + 0.5, 0.08, d * 0.62), "h16_roof" if lb._mats.has("h16_roof") else "roof", 0, false, hut)
		r.rotation.x = s * 0.5
	var gable_h := 0.75
	for sx in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(d, gable_h, 0.1)
		g.mesh = pm
		g.material_override = lb.mat(mat)
		g.rotation.y = PI * 0.5
		g.position = Vector3(sx * w * 0.5, h + gable_h * 0.5, 0)
		hut.add_child(g)
	m.building_footprints.append(PackedVector2Array([
		Vector2(pos.x - 2.0, pos.z - 1.6), Vector2(pos.x + 2.0, pos.z - 1.6), Vector2(pos.x + 2.0, pos.z + 1.6), Vector2(pos.x - 2.0, pos.z + 1.6)]))
