extends RefCounted
## Abgesenkte, begehbare Schützengräben und zusätzliche Felddeckung auf der großen Wiese („Feld“).
## Zickzack-Gräben 1,30 m tief, 1,60 m breit, Holzverschalung, Schützenauftritt (Fire step) und
## Sandsack-Brustwehr zur Feindseite, Stufenrampen an beiden Enden. Der Spielboden erhält echte
## Aussparungen (bavaria._ground mit Löchern), daher Navmesh, Kollision und Ballistik ohne Sonderfälle.
## Balance: Graben West schützt nach Norden (Südteam), Graben Ost nach Süden (Nordteam).
## Welt-Koordinaten (x, z) in Metern; geprüft gegen Spawns, Zone C (Wiese), Flak, Wege und Flugzeugwracks.

const DEPTH := 1.30
const HALF_W := 0.80
const STEP_TOP := -0.85      # Schützenauftritt: 0,45 m über Grabensohle, Augenhöhe ≈ 0,7 m über Gelände
const PARAPET_H := 0.45
const RAMP_LEN := 3.6
const RAMP_STEPS := 8

const TRENCHES := [
	{"id": "Graben_West", "points": [Vector2(-42, -24), Vector2(-38, -20), Vector2(-34, -24), Vector2(-30, -20)], "parapet": -1.0},
	{"id": "Graben_Ost", "points": [Vector2(-8, -2), Vector2(-12, -5), Vector2(-9, -9), Vector2(-13, -12)], "parapet": 1.0},
]

## Weitere Deckungen: [Art, Position, Drehung]
const COVERS := [
	["sandbag_nest", Vector2(-30, -8), 0.3], ["sandbag_nest", Vector2(-16, -30), 2.2], ["sandbag_nest", Vector2(-6, -32), -0.6],
	["hay", Vector2(-40, -32), 0.0], ["hay", Vector2(-28, 4), 0.8], ["haystack", Vector2(-18, 6), 0.0],
	["berm", Vector2(-20, -12), 0.4], ["berm", Vector2(-36, -12), -0.2],
	["wagon", Vector2(-42, -36), 0.9], ["woodpile", Vector2(-4, -14), 1.4],
	["crater", Vector2(-24, -28), 0.0], ["crater", Vector2(-33, -30), 0.0], ["crater", Vector2(-14, -20), 0.0], ["crater", Vector2(-38, 6), 0.0],
]

static func full_polyline(points: Array) -> PackedVector2Array:
	var p := PackedVector2Array(points)
	var a := p[0] + (p[0] - p[1]).normalized() * RAMP_LEN
	var b := p[p.size() - 1] + (p[p.size() - 1] - p[p.size() - 2]).normalized() * RAMP_LEN
	p.insert(0, a)
	p.append(b)
	return p

static func hole_polygons() -> Array:
	var out: Array = []
	for t in TRENCHES:
		for poly in Geometry2D.offset_polyline(full_polyline(t.points), HALF_W, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT):
			out.append(poly)
	return out

static func build(m) -> void:
	var lb: LevelBuilder = m.lb
	if not lb._mats.has("trench_mud"):
		var mud := StandardMaterial3D.new()
		mud.albedo_color = Color(0.30, 0.24, 0.17)
		mud.roughness = 1.0
		mud.uv1_triplanar = true
		mud.uv1_world_triplanar = true
		var src: StandardMaterial3D = lb.mat("earth")
		if src.albedo_texture:
			mud.albedo_texture = src.albedo_texture
			mud.albedo_color = Color(0.72, 0.62, 0.52)
			mud.uv1_scale = src.uv1_scale
		lb._mats["trench_mud"] = mud
	var plank := "h16_wood" if lb._mats.has("h16_wood") else "wood"
	for t in TRENCHES:
		var root := Node3D.new()
		root.name = String(t.id)
		m.static_root.add_child(root)
		root.add_to_group("bavaria_trenches")
		var line := full_polyline(t.points)
		var polys := Geometry2D.offset_polyline(line, HALF_W, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)
		var poly: PackedVector2Array = polys[0]
		# Grabensohle
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tri := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tri.size(), 3):
			var a := poly[tri[i]]
			var b := poly[tri[i + 1]]
			var c := poly[tri[i + 2]]
			if (b - a).cross(c - a) < 0:
				var tmp := b
				b = c
				c = tmp
			for q in [a, b, c]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q.x, -DEPTH, q.y))
		var floor_mi := MeshInstance3D.new()
		floor_mi.name = "Grabensohle"
		floor_mi.mesh = st.commit()
		floor_mi.material_override = lb.mat("trench_mud")
		root.add_child(floor_mi)
		floor_mi.create_trimesh_collision()
		# Verschalung an allen Kanten, außer den Rampenausgängen (Butt-Enden)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var mid := (a + b) * 0.5
			if mid.distance_to(line[0]) < HALF_W + 0.05 or mid.distance_to(line[line.size() - 1]) < HALF_W + 0.05:
				continue
			var dir := (b - a)
			var len := dir.length()
			if len < 0.05:
				continue
			var nrm := Vector2(-dir.y, dir.x).normalized()
			if not Geometry2D.is_point_in_polygon(mid + nrm * 0.1, poly):
				nrm = -nrm
			var c := mid + nrm * 0.06
			lb.box(Vector3(c.x, -DEPTH - 0.05, c.y), Vector3(len + 0.02, DEPTH + 0.05, 0.12), plank, atan2(-dir.y, dir.x), true, root)
			# Pfosten alle 1,5 m
			var posts := int(len / 1.5)
			for k in posts:
				var pp := a + dir * ((k + 0.5) / posts) + nrm * 0.14
				lb.box(Vector3(pp.x, -DEPTH, pp.y), Vector3(0.1, DEPTH + 0.05, 0.1), "darkwood", 0, false, root)
		# Stufenrampen an beiden Enden
		for end in [[line[0], line[1]], [line[line.size() - 1], line[line.size() - 2]]]:
			var top: Vector2 = end[0]
			var inner: Vector2 = end[1]
			var d := (inner - top).normalized()
			var yaw := atan2(-d.y, d.x)
			var run := RAMP_LEN / RAMP_STEPS
			for s in RAMP_STEPS:
				var hgt := DEPTH - (s + 1) * DEPTH / (RAMP_STEPS + 1)
				var pc := top + d * (s + 0.5) * run
				lb.box(Vector3(pc.x, -DEPTH - 0.02, pc.y), Vector3(run + 0.02, hgt + 0.02, HALF_W * 2 - 0.26), "trench_mud", yaw, true, root)
		# Schützenauftritt + Brustwehr auf der Feindseite je Hauptsegment
		var side_sign: float = t.parapet
		var ledges: Array = []
		var pts: Array = t.points
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var dir: Vector2 = (b - a)
			var u := dir.normalized()
			var nrm := Vector2(-u.y, u.x)
			if signf(nrm.y) != side_sign:
				nrm = -nrm
			var yaw := atan2(-u.y, u.x)
			var seg_len := dir.length() - 0.9
			var mid := (a + b) * 0.5
			var lc := mid + nrm * (HALF_W - 0.12 - 0.15)
			lb.box(Vector3(lc.x, -DEPTH, lc.y), Vector3(seg_len, STEP_TOP + DEPTH, 0.30), "trench_mud", yaw, true, root)
			var pc := mid + nrm * (HALF_W + 0.38)
			var bag := lb.box(Vector3(pc.x, 0, pc.y), Vector3(dir.length() - 0.6, PARAPET_H, 0.62), "sandbag", yaw, true, root)
			bag.add_to_group("bavaria_trench_parapets")
			ledges.append({"stand": Vector3(lc.x, STEP_TOP, lc.y), "out": Vector3(nrm.x, 0, nrm.y)})
		root.set_meta("polyline", line)
		root.set_meta("hole", poly)
		root.set_meta("floor_y", -DEPTH)
		root.set_meta("ledges", ledges)
		root.set_meta("floor_points", (pts as Array).map(func(p): return Vector3(p.x, -DEPTH, p.y)))
		root.set_meta("exits", [Vector3(line[0].x, 0, line[0].y), Vector3(line[line.size() - 1].x, 0, line[line.size() - 1].y)])

## Prüfen, ob eine Deckung an p (Radius r) Spawns, Zonen, Flak, Wege, Wracks, Gräben und Häuser freihält.
static func _cover_block(m, p: Vector2, r: float) -> String:
	# Sichtachsen der Aussichtspunkte frei halten
	if preload("res://src/maps/bavaria/scene_match.gd").sight_distance(m, p) < r + 2.0:
		return "Sichtachse"
	if not m.inside_map(Vector3(p.x, 0, p.y)):
		return "Grenze"
	for s in m.layout["spawns"]:
		var sp: Vector3 = m.pixel(s["pixel"])
		if Vector2(sp.x, sp.z).distance_to(p) < (r + 6.0 if r > 0.0 else 2.5):
			return "Spawn"
	for z in m.layout.get("occupation_zones", []):
		var zp: Vector3 = m.pixel(z["pixel"])
		if Vector2(zp.x, zp.z).distance_to(p) < float(z["radius"]) + r + 5.5:
			return "Zone"
	var flak: Vector3 = m.pixel([690, 490])
	if Vector2(flak.x, flak.z).distance_to(p) < (r + 7.0 if r > 0.0 else 3.5):
		return "Flak"
	for road in m.layout["paths"]:
		var points: Array = road["points"]
		for i in points.size() - 1:
			var a: Vector3 = m.pixel(points[i])
			var b: Vector3 = m.pixel(points[i + 1])
			if Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p) < float(road["width"]) * 0.5 + r + 1.2:
				return "Weg " + String(road["id"])
	var polys: Array = m.building_footprints.duplicate()
	if m.meadow_cover:
		polys.append_array(m.meadow_cover.footprints)
	for f in polys:
		if Geometry2D.is_point_in_polygon(p, f):
			return "Grundriss"
		for i in f.size():
			if Geometry2D.get_closest_point_to_segment(p, f[i], f[(i + 1) % f.size()]).distance_to(p) < r + 1.5:
				return "Grundrissnähe"
	for item in m._placed:
		if Vector2(item.pos.x, item.pos.z).distance_to(p) < float(item.radius) + r:
			return "Deko %s r%.1f" % [item.pos, float(item.radius)]
	return ""

static func build_cover(m) -> int:
	var lb: LevelBuilder = m.lb
	var placed := 0
	if not lb._mats.has("trench_hay"):
		var hay := StandardMaterial3D.new()
		hay.albedo_color = Color(0.74, 0.62, 0.34)
		hay.roughness = 1.0
		lb._mats["trench_hay"] = hay
	for c in COVERS:
		var kind: String = c[0]
		var p: Vector2 = c[1]
		var yaw: float = c[2]
		var radius: float = {"sandbag_nest": 2.0, "hay": 1.6, "haystack": 2.2, "berm": 2.2, "wagon": 2.6, "woodpile": 2.2, "crater": 0.0}[kind]
		# Nominalposition, sonst Spiralsuche bis 11 m (Schutzabstände haben Vorrang vor der Wunschposition).
		var found := false
		for ring in [0.0, 2.0, 3.5, 5.0, 7.0, 9.0, 11.0]:
			for k in (1 if ring == 0.0 else 10):
				var q: Vector2 = p + Vector2.from_angle(k * TAU / 10.0) * ring
				if _cover_block(m, q, radius) == "":
					p = q
					found = true
					break
			if found:
				break
		if not found:
			# Ersatzplatz: freiester Punkt der Wiese (2-m-Raster), nächster zur Wunschposition
			var meadow: PackedVector2Array = m.polygon(m.layout["meadow"])
			var bb := Rect2(meadow[0], Vector2.ZERO)
			for q in meadow:
				bb = bb.expand(q)
			var best := INF
			var gx := bb.position.x
			while gx < bb.end.x:
				var gz := bb.position.y
				while gz < bb.end.y:
					var q := Vector2(gx, gz)
					if Geometry2D.is_point_in_polygon(q, meadow) and q.distance_to(c[1]) < best and _cover_block(m, q, radius) == "":
						best = q.distance_to(c[1])
						p = q
						found = true
					gz += 2.0
				gx += 2.0
			if found:
				print("BAVARIA FELD: Deckung ", kind, " auf Ersatzplatz ", p, " (%.1f m von Wunschposition)" % best)
		if not found:
			print("BAVARIA FELD: Deckung ", kind, " bei ", c[1], " ausgelassen: ", _cover_block(m, c[1], radius))
			continue
		var n := Node3D.new()
		n.name = "Feld_" + kind + "_" + str(placed)
		m.static_root.add_child(n)
		n.position = Vector3(p.x, 0, p.y)
		n.rotation.y = yaw
		n.add_to_group("bavaria_decorations")
		n.add_to_group("bavaria_field_cover")
		n.set_meta("cover_kind", kind)
		match kind:
			"sandbag_nest":
				# Hufeisenförmiges MG-Nest, 0,95 m hoch, offen nach hinten
				lb.box(Vector3(0, 0, -1.2), Vector3(2.6, 0.95, 0.6), "sandbag", 0, true, n)
				for s in [-1.0, 1.0]:
					lb.box(Vector3(s * 1.0, 0, -0.35), Vector3(0.6, 0.95, 1.2), "sandbag", 0, true, n)
			"hay":
				for k in 3:
					var cyl := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.6
					cm.bottom_radius = 0.6
					cm.height = 1.2
					cyl.mesh = cm
					cyl.material_override = lb.mat("trench_hay")
					n.add_child(cyl)
					cyl.position = Vector3(-1.3 + k * 1.3, 0.6, 0)
					cyl.rotation.z = PI * 0.5 if k != 1 else 0.0
				lb.box(Vector3(0, 0, 0), Vector3(3.8, 1.15, 1.1), "trench_hay", 0, true, n).get_child(1).visible = false
			"haystack":
				var cone := MeshInstance3D.new()
				var cm2 := CylinderMesh.new()
				cm2.top_radius = 0.15
				cm2.bottom_radius = 1.9
				cm2.height = 3.2
				cone.mesh = cm2
				cone.material_override = lb.mat("trench_hay")
				n.add_child(cone)
				cone.position.y = 1.6
				lb.box(Vector3(0, 0, 0), Vector3(2.4, 2.2, 2.4), "trench_hay", 0, true, n).get_child(1).visible = false
				lb.box(Vector3(0, 0, 0), Vector3(0.12, 4.0, 0.12), "darkwood", 0, false, n)
			"berm":
				var b := lb.box(Vector3(0, -0.3, 0), Vector3(5.0, 1.15, 1.6), "earth", 0, true, n)
				b.rotation.x = 0.0
				lb.box(Vector3(0, 0.5, 0), Vector3(4.2, 0.4, 1.0), "earth", 0, false, n)
			"wagon":
				# Umgestürzter Leiterwagen: Bretterkasten auf der Seite, Räder, Deichsel
				lb.box(Vector3(0, 0, 0), Vector3(3.4, 1.1, 0.18), "h16_wood" if lb._mats.has("h16_wood") else "wood", 0, true, n)
				lb.box(Vector3(0, 0, 0.5), Vector3(3.4, 0.12, 1.0), "darkwood", 0, false, n)
				lb.box(Vector3(0, 0.98, 0.5), Vector3(3.4, 0.12, 1.0), "darkwood", 0, false, n)
				for x in [-1.25, 1.25]:
					var wheel := MeshInstance3D.new()
					var wm := CylinderMesh.new()
					wm.top_radius = 0.45
					wm.bottom_radius = 0.45
					wm.height = 0.08
					wheel.mesh = wm
					wheel.material_override = lb.mat("darkwood")
					n.add_child(wheel)
					wheel.position = Vector3(x, 0.55, -0.25)
					wheel.rotation.x = PI * 0.5
				var pole := lb.box(Vector3(2.6, 0.0, 0.6), Vector3(1.8, 0.08, 0.08), "darkwood", 0.3, false, n)
				pole.rotation.z = 0.0
			"woodpile":
				var wp: Node3D = m._templates.prop("ja_drevo", Vector3(p.x, 0, p.y), yaw, 0.8, true)
				if wp:
					wp.add_to_group("bavaria_decorations")
			"crater":
				# Flacher Granattrichter: dunkler Erdkreis + Ringwall (nur optisch, keine Stolperkante)
				var disk := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = 1.6
				dm.bottom_radius = 1.2
				dm.height = 0.04
				disk.mesh = dm
				disk.material_override = lb.mat("trench_mud")
				disk.position.y = 0.022
				n.add_child(disk)
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 1.4
				tm.outer_radius = 2.0
				ring.mesh = tm
				ring.material_override = lb.mat("trench_mud")
				ring.scale = Vector3(1, 0.35, 1)
				ring.position.y = 0.0
				n.add_child(ring)
		m._placed.append({"pos": Vector3(p.x, 0, p.y), "radius": radius})
		placed += 1
	return placed
