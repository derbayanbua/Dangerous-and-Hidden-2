class_name LevelBuilder
extends RefCounted
## Prozeduraler Weltbaukasten. Statische Geometrie wird unter `static_root`
## erzeugt (Kind der NavigationRegion3D -> fließt in das Navigationsnetz ein).
## Bewegliche Teile (Türen) und Interaktionen unter `dynamic_root`.
## PLATZHALTER-GRAFIK: Primitive mit prozeduralen Materialien.

var static_root: Node3D
var dynamic_root: Node3D
var size := 260.0
var res := 2.0                       ## Terrain-Rasterweite in m
var noise := FastNoiseLite.new()
var flatten_zones: Array = []        ## [Vector3 center, radius, height]
var roads: Array = []                ## Array[PackedVector2Array] (x,z)
var road_width := 4.0
## Geländefarben (Missionen überschreiben, z. B. Schnee)
var color_ground := Color(0.3, 0.38, 0.17)
var color_ground2 := Color(0.38, 0.4, 0.2)
var color_road := Color(0.36, 0.3, 0.21)
var color_foliage := Color(0.2, 0.32, 0.13)

var _mats := {}


func _init(static_parent: Node3D, dynamic_parent: Node3D, seed_value := 1944) -> void:
	static_root = static_parent
	dynamic_root = dynamic_parent
	noise.seed = seed_value
	noise.frequency = 0.012
	noise.fractal_octaves = 4


# --- Materialien ---------------------------------------------------------------

func mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	var tex_color := Color.WHITE
	var noise_amt := 0.15
	match name:
		"plaster": tex_color = Color(0.78, 0.74, 0.64); noise_amt = 0.12
		"stone": tex_color = Color(0.52, 0.5, 0.46); noise_amt = 0.25
		"wood": tex_color = Color(0.38, 0.27, 0.17); noise_amt = 0.2
		"darkwood": tex_color = Color(0.22, 0.16, 0.1); noise_amt = 0.2
		"roof": tex_color = Color(0.36, 0.2, 0.15); noise_amt = 0.2
		"slate": tex_color = Color(0.25, 0.27, 0.3); noise_amt = 0.15
		"sandbag": tex_color = Color(0.55, 0.5, 0.36); noise_amt = 0.2
		"hedge": tex_color = Color(0.17, 0.27, 0.11); noise_amt = 0.35
		"foliage": tex_color = color_foliage; noise_amt = 0.35
		"snow": tex_color = Color(0.86, 0.88, 0.92); noise_amt = 0.08
		"sandstone": tex_color = Color(0.8, 0.68, 0.5); noise_amt = 0.18
		"concrete": tex_color = Color(0.55, 0.55, 0.53); noise_amt = 0.15
		"tank": tex_color = Color(0.32, 0.34, 0.3); noise_amt = 0.1; m.metallic = 0.5; m.roughness = 0.6
		"bark": tex_color = Color(0.25, 0.2, 0.15); noise_amt = 0.3
		"metal": tex_color = Color(0.3, 0.31, 0.3); noise_amt = 0.1; m.metallic = 0.6; m.roughness = 0.5
		"hay": tex_color = Color(0.72, 0.62, 0.33); noise_amt = 0.3
		"water":
			m.albedo_color = Color(0.12, 0.2, 0.22, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.3
			_mats[name] = m
			return m
		"radio": tex_color = Color(0.2, 0.22, 0.18); noise_amt = 0.05; m.metallic = 0.4
	m.albedo_color = tex_color
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	nt.noise = fn
	var g := Gradient.new()
	g.set_color(0, Color(1.0 - noise_amt, 1.0 - noise_amt, 1.0 - noise_amt))
	g.set_color(1, Color(1.0, 1.0, 1.0))
	nt.color_ramp = g
	m.albedo_texture = nt
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_mats[name] = m
	return m


# --- Terrain -----------------------------------------------------------------

var height_scale := 1.0   ## Relief (Wüstendünen > 1)


func height_at(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 4.0 * height_scale
	h += noise.get_noise_2d(x * 0.3 + 100.0, z * 0.3) * 6.0 * height_scale
	for fz in flatten_zones:
		var c: Vector3 = fz[0]
		var r: float = fz[1]
		var d := Vector2(x - c.x, z - c.z).length()
		if d < r * 1.6:
			var t := clampf((d - r) / (r * 0.6), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			h = lerpf(c.y, h, t)
	# Straßen leicht eingeebnet
	var rd := _road_distance(x, z)
	if rd < road_width * 2.0:
		var hs := h
		h = lerpf(hs * 0.85, hs, clampf(rd / (road_width * 2.0), 0.0, 1.0))
	return h


func _road_distance(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for r in roads:
		var pts: PackedVector2Array = r
		for i in pts.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


func build_terrain() -> void:
	var n := int(size / res) + 1
	var half := size * 0.5
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = height_at(-half + ix * res, -half + iz * res)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass := color_ground
	var grass2 := color_ground2
	var dirt := color_road
	for iz in n:
		for ix in n:
			var x := -half + ix * res
			var z := -half + iz * res
			var h := heights[iz * n + ix]
			var rd := _road_distance(x, z)
			var c := grass.lerp(grass2, clampf(noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5, 0.0, 1.0))
			if rd < road_width * 0.6:
				c = dirt
			elif rd < road_width:
				c = c.lerp(dirt, 1.0 - (rd - road_width * 0.6) / (road_width * 0.4))
			st.set_color(c)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, h, z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + n)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	nt.noise = fn
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.75, 0.75))
	g.set_color(1, Color(1.1, 1.1, 1.1))
	nt.color_ramp = g
	m.albedo_texture = nt
	mi.material_override = m
	static_root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	static_root.add_child(body)


# --- Grundbausteine ------------------------------------------------------------

## Quader mit Kollision. pos = Mittelpunkt der Unterseite.
func box(pos: Vector3, sz: Vector3, material: String, yaw := 0.0, collide := true, parent: Node3D = null) -> Node3D:
	var p := parent if parent else static_root
	var body: Node3D
	if collide:
		body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position.y = sz.y * 0.5
		body.add_child(cs)
	else:
		body = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat(material)
	mi.position.y = sz.y * 0.5
	body.add_child(mi)
	p.add_child(body)
	body.position = pos
	body.rotation.y = yaw
	return body


func cylinder(pos: Vector3, radius: float, height: float, material: String, collide := true, parent: Node3D = null) -> Node3D:
	var p := parent if parent else static_root
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	if collide:
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = radius
		c.height = height
		cs.shape = c
		cs.position.y = height * 0.5
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat(material)
	mi.position.y = height * 0.5
	body.add_child(mi)
	p.add_child(body)
	body.position = pos
	return body


## Gelände-Höhe an (x, z) als Vector3.
func ground(x: float, z: float, y_off := 0.0) -> Vector3:
	return Vector3(x, height_at(x, z) + y_off, z)


# --- Gebäude ---------------------------------------------------------------------

## Rechteckiges Gebäude. doors: Array von [Seite, Versatz] mit Seite in
## "n","s","e","w" (Versatz entlang der Wand, 0 = Mitte). Erzeugt Türen.
## Gibt das Wurzel-Node zurück (Kindknoten in lokalen Koordinaten).
func building(center: Vector3, w: float, d: float, h: float, wall_mat: String, roof_mat: String,
		doors: Array, windows := true, yaw := 0.0, open_doorways: Array = [], flat_roof := false, minimum_windows := 0, window_clearance := 1.6) -> Node3D:
	var root := Node3D.new()
	root.name = "Building"
	static_root.add_child(root)
	root.position = center
	root.rotation.y = yaw
	var t := 0.3
	# Boden
	box(Vector3(0, -0.3, 0), Vector3(w, 0.35, d), "darkwood", 0.0, true, root)
	var sides := {
		"n": [Vector3(0, 0, -d * 0.5), w, 0.0],
		"s": [Vector3(0, 0, d * 0.5), w, 0.0],
		"e": [Vector3(w * 0.5, 0, 0), d, PI * 0.5],
		"w": [Vector3(-w * 0.5, 0, 0), d, PI * 0.5],
	}
	for side in sides:
		var info: Array = sides[side]
		var gaps: Array = []
		for dr in doors:
			if dr[0] == side:
				# 1.4 m: muss nach Navmesh-Erosion (Agentenradius 0.4) passierbar bleiben
				gaps.append([float(dr[1]), 1.4, 0.0, 2.2, true])
		for od in open_doorways:
			if od[0] == side:
				gaps.append([float(od[1]), float(od[2]), 0.0, minf(h - 0.3, 3.2), false])
		if windows:
			var length: float = info[1]
			var count := maxi(int(length / 4.0), minimum_windows)
			for k in count:
				var off := -length * 0.5 + (k + 0.5) * length / count
				var clash := false
				for gp in gaps:
					if absf(gp[0] - off) < window_clearance:
						clash = true
				if not clash:
					gaps.append([off, 1.0, 1.0, 1.9, false])
		_wall(root, info[0], info[1], h, t, info[2], gaps, wall_mat)
		for gp in gaps:
			if gp[4]:
				var door := Door.new()
				door.width = 1.35
				var local_pos: Vector3 = info[0] + Basis(Vector3.UP, info[2]) * Vector3(gp[0], 0, 0)
				dynamic_root.add_child(door)
				door.global_position = root.to_global(local_pos)
				door.global_rotation.y = yaw + info[2]
	if flat_roof:
		# Flachdach mit Brüstung (Lehmbauweise)
		box(Vector3(0, h, 0), Vector3(w + 0.3, 0.25, d + 0.3), roof_mat, 0.0, true, root)
		for s in [-1.0, 1.0]:
			box(Vector3(0, h + 0.25, s * (d * 0.5 + 0.05)), Vector3(w + 0.3, 0.45, 0.2), wall_mat, 0.0, true, root)
			box(Vector3(s * (w * 0.5 + 0.05), h + 0.25, 0), Vector3(0.2, 0.45, d + 0.3), wall_mat, 0.0, true, root)
		return root
	# Dach (Satteldach aus zwei geneigten Platten)
	var roof_y := h
	var slope := 0.55
	var half_d := d * 0.5 + 0.4
	var plate_len := half_d / cos(slope)
	for s in [-1.0, 1.0]:
		var plate := box(Vector3(0, 0, 0), Vector3(w + 0.8, 0.15, plate_len), roof_mat, 0.0, true, root)
		plate.position = Vector3(0, roof_y + tan(slope) * half_d * 0.5 - 0.1, s * half_d * 0.5)
		plate.rotation.x = slope * s
	# Giebel
	for s in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(d, tan(slope) * d * 0.5, t)
		gable.mesh = pm
		gable.material_override = mat(wall_mat)
		gable.rotation.y = PI * 0.5
		gable.position = Vector3(s * w * 0.5, roof_y + pm.size.y * 0.5, 0)
		root.add_child(gable)
	return root


## Wand mit Öffnungen. gaps: [Versatz, Breite, Unterkante, Oberkante, istTür]
func _wall(parent: Node3D, center: Vector3, length: float, h: float, t: float, yaw: float, gaps: Array, material: String) -> void:
	var wall := Node3D.new()
	parent.add_child(wall)
	wall.position = center
	wall.rotation.y = yaw
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var x := -length * 0.5
	for gp in gaps:
		var g0: float = gp[0] - gp[1] * 0.5
		var g1: float = gp[0] + gp[1] * 0.5
		if g0 > x:
			box(Vector3((x + g0) * 0.5, 0, 0), Vector3(g0 - x, h, t), material, 0.0, true, wall)
		# unter/über der Öffnung
		if gp[2] > 0.0:
			box(Vector3(gp[0], 0, 0), Vector3(gp[1], gp[2], t), material, 0.0, true, wall)
		if gp[3] < h:
			box(Vector3(gp[0], gp[3], 0), Vector3(gp[1], h - gp[3], t), material, 0.0, true, wall)
		x = g1
	if x < length * 0.5:
		box(Vector3((x + length * 0.5) * 0.5, 0, 0), Vector3(length * 0.5 - x, h, t), material, 0.0, true, wall)


## Gerade Mauer/Hecke von a nach b (x,z), Höhe h. gaps in Metern entlang der Linie.
func line_wall(a: Vector2, b: Vector2, h: float, thickness: float, material: String, gaps: Array = []) -> void:
	var dir := b - a
	var length := dir.length()
	var yaw := atan2(-dir.y, dir.x)
	var segs: Array = []
	var x := 0.0
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for gp in sorted:
		var g0: float = gp[0] - gp[1] * 0.5
		if g0 > x:
			segs.append([x, g0])
		x = gp[0] + gp[1] * 0.5
	if x < length:
		segs.append([x, length])
	# lange Segmente teilen, damit sie dem Gelände folgen
	for s in segs:
		var s0: float = s[0]
		var s1: float = s[1]
		var parts := maxi(int((s1 - s0) / 6.0), 1)
		for k in parts:
			var p0 := s0 + (s1 - s0) * k / parts
			var p1 := s0 + (s1 - s0) * (k + 1) / parts
			var mid := a + dir.normalized() * ((p0 + p1) * 0.5)
			var gy := minf(height_at(a.x + dir.normalized().x * p0, a.y + dir.normalized().y * p0),
				height_at(a.x + dir.normalized().x * p1, a.y + dir.normalized().y * p1))
			box(Vector3(mid.x, gy - 0.4, mid.y), Vector3(p1 - p0 + 0.05, h + 0.4, thickness), material, yaw)


const FENCE_LAYER := 1 << 4   ## Physik-Layer 5: blockiert Bewegung, nicht Sicht/Kugeln

## Stacheldrahtzaun von a nach b mit Lücken [Versatz, Breite].
func fence(a: Vector2, b: Vector2, gaps: Array = [], h := 1.8) -> void:
	var dir := b - a
	var length := dir.length()
	var n := dir / length
	var yaw := atan2(-n.y, n.x)
	var x := 0.0
	var segs: Array = []
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for gp in sorted:
		if gp[0] - gp[1] * 0.5 > x:
			segs.append([x, gp[0] - gp[1] * 0.5])
		x = gp[0] + gp[1] * 0.5
	if x < length:
		segs.append([x, length])
	for s in segs:
		var parts := maxi(int((s[1] - s[0]) / 4.0), 1)
		for k in parts:
			var p0: float = s[0] + (s[1] - s[0]) * k / parts
			var p1: float = s[0] + (s[1] - s[0]) * (k + 1) / parts
			var mid := a + n * ((p0 + p1) * 0.5)
			var g := ground(mid.x, mid.y, -0.2)
			var body := StaticBody3D.new()
			body.collision_layer = FENCE_LAYER
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(p1 - p0, h, 0.15)
			cs.shape = bs
			cs.position.y = h * 0.5
			body.add_child(cs)
			for wy in [0.3, 0.8, 1.3, h - 0.1]:
				var wire := MeshInstance3D.new()
				var wm := BoxMesh.new()
				wm.size = Vector3(p1 - p0, 0.02, 0.02)
				wire.mesh = wm
				wire.material_override = mat("metal")
				wire.position.y = wy
				body.add_child(wire)
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.1, h + 0.2, 0.1)
			post.mesh = pm
			post.material_override = mat("darkwood")
			post.position = Vector3(-(p1 - p0) * 0.5, (h + 0.2) * 0.5, 0)
			body.add_child(post)
			static_root.add_child(body)
			body.position = g
			body.rotation.y = yaw


func tree(x: float, z: float, scale := 1.0, conifer := false) -> void:
	var g := ground(x, z, -0.2)
	var trunk_h := 4.0 * scale
	cylinder(g, 0.22 * scale, trunk_h + 0.2, "bark")
	var crown := MeshInstance3D.new()
	if conifer:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 2.2 * scale
		c.height = 7.0 * scale
		c.radial_segments = 8
		crown.mesh = c
		crown.position = g + Vector3(0, trunk_h * 0.5 + c.height * 0.5, 0)
	else:
		var s := SphereMesh.new()
		s.radius = 2.6 * scale
		s.height = 4.4 * scale
		s.radial_segments = 10
		s.rings = 6
		crown.mesh = s
		crown.position = g + Vector3(0, trunk_h + 1.2 * scale, 0)
	crown.material_override = mat("foliage")
	static_root.add_child(crown)


## Dattelpalme: schlanker, leicht geneigter Stamm, Wedel aus flachen Kegeln.
func palm(x: float, z: float, scale := 1.0, lean := 0.15) -> void:
	var g := ground(x, z, -0.2)
	var h := 7.0 * scale
	var trunk := cylinder(g, 0.2 * scale, h, "bark")
	trunk.rotation.z = lean
	var top := g + Vector3(-sin(lean) * h, cos(lean) * h, 0)
	for i in 7:
		var frond := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.5 * scale
		c.height = 3.2 * scale
		c.radial_segments = 4
		frond.mesh = c
		frond.material_override = mat("foliage")
		static_root.add_child(frond)
		frond.position = top
		frond.rotation = Vector3(0, TAU * i / 7.0, 1.9)
		frond.scale = Vector3(1, 1, 0.25)


func sandbags(center: Vector3, length: float, yaw: float) -> void:
	box(center, Vector3(length, 0.95, 0.6), "sandbag", yaw)


func crate(pos: Vector3, s := 1.0, yaw := 0.0) -> void:
	box(pos, Vector3(s, s, s), "wood", yaw)
