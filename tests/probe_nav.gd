extends "res://tests/test_mp_nav.gd"
## Fehlersuche Navigationsnetz an einer Stelle (B-010):
##   tools\godot.cmd --headless -- --autoplay=probe_nav --maps=<id> --at=x,y,z[;x,y,z…] [--r=12]
## Gibt je Punkt den nächsten Netzpunkt, die Kollisionsflächen senkrecht darüber/darunter (Name, Höhe) und die
## Netzpolygone im Umkreis (Höhenstufen) aus; Bild test_output/navprobe_<karte>_<i>.png (Polygone je Insel gefärbt,
## Kollisionsquerschnitt in 1 m Höhe über dem Punkt rot).


func _test_map(id: String) -> void:
	var old := Game.current_mission()
	Game.start_mission(id)
	var m: Mission = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
		var cm := Game.current_mission() as Mission
		if cm and cm != old and is_instance_valid(cm) and cm.is_node_ready():
			m = cm
			break
	if m == null:
		return
	while not m.nav_ready and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
	await frames(5 + int(Game.cli.get("wait", "0")))
	var nav_map := m.nav_region.get_navigation_map()
	var r := float(Game.cli.get("r", "12"))
	var i := 0
	for s in String(Game.cli.get("at", "")).split(";", false):
		var c := s.split(",")
		var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var cp := NavigationServer3D.map_get_closest_point(nav_map, p)
		print("PROBE %s %s: nächster Netzpunkt %s (Abstand %.2f)" % [id, _v(p), _v(cp), cp.distance_to(p)])
		var space := m.get_world_3d().direct_space_state
		var from := p + Vector3.UP * 15.0
		var excl: Array[RID] = []
		for k in 12:
			var q := PhysicsRayQueryParameters3D.create(from, p + Vector3.DOWN * 15.0, 1 | (1 << 4))
			q.exclude = excl
			q.hit_back_faces = true
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			var col: Object = h.collider
			print("   Fläche y=%.2f  %s  Normale %s" % [h.position.y, (col as Node).get_path() if col is Node else str(col), _v(h.normal)])
			excl.append(h.rid)
		_draw_zoom(m, id, i, p, r, nav_map)
		i += 1
	if Game.cli.has("linkcheck"):
		var ok := 0
		var bad: Array = []
		for l in NavigationServer3D.map_get_links(nav_map):
			var s0 := NavigationServer3D.link_get_start_position(l)
			var e0 := NavigationServer3D.link_get_end_position(l)
			var p1 := NavigationServer3D.map_get_path(nav_map, s0, e0, true)
			if p1.size() > 0 and p1[p1.size() - 1].distance_to(e0) < 0.5:
				ok += 1
			elif bad.size() < 8:
				bad.append("%s -> %s endet %s" % [_v(s0), _v(e0), _v(p1[p1.size() - 1]) if p1.size() > 0 else "-"])
		print("LINKCHECK %d/%d Links begehbar" % [ok, NavigationServer3D.map_get_links(nav_map).size()])
		for b in bad:
			print("   ", b)
	if Game.cli.has("path"):
		var pp := String(Game.cli["path"]).split(";")
		var a := pp[0].split_floats(",")
		var b := pp[1].split_floats(",")
		var pth := NavigationServer3D.map_get_path(nav_map, Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]), true)
		print("PATH ", pth)
		for l in NavigationServer3D.map_get_links(nav_map):
			var s0 := NavigationServer3D.link_get_start_position(l)
			var e0 := NavigationServer3D.link_get_end_position(l)
			if s0.distance_to(Vector3(a[0], a[1], a[2])) < 8.0 or e0.distance_to(Vector3(a[0], a[1], a[2])) < 8.0:
				print("   Link %s -> %s an %s, bidi %s, Ebenen %d, aktiv %s" % [s0, e0, NavigationServer3D.link_get_map(l),
					NavigationServer3D.link_is_bidirectional(l), NavigationServer3D.link_get_navigation_layers(l),
					NavigationServer3D.link_get_enabled(l)])
				var p1 := NavigationServer3D.map_get_path(nav_map, s0 + Vector3(0.5, 0, 0.5), e0, true)
				print("     Pfad über den Link: ", p1)
		print("Links in der Karte: ", NavigationServer3D.map_get_links(nav_map).size(), ", Verbindungsradius ",
			NavigationServer3D.map_get_link_connection_radius(nav_map), ", Kantenrand ", NavigationServer3D.map_get_edge_connection_margin(nav_map))
	rows.append("| %s | probe |" % id)


var _isl := {}          # [Region, Polygon] -> Insel
var _isl_ready := false


func _island_of(r: NavigationRegion3D, pi: int) -> int:
	if not _isl_ready:
		_isl_ready = true
		var weld := {}
		var uf: Array = []
		var vpoly := {}
		var idx := 0
		var keys: Array = []
		for n in r.get_parent().find_children("*", "NavigationRegion3D", true, false) + [r]:
			var nm := (n as NavigationRegion3D).navigation_mesh
			if nm == null or _isl.has([n, 0]):
				continue
			var vs := nm.get_vertices()
			for p in nm.get_polygon_count():
				uf.append(idx)
				_isl[[n, p]] = idx
				for k in nm.get_polygon(p):
					var key := Vector3i(((n as Node3D).global_transform * vs[k] * 10.0).round())
					if vpoly.has(key):
						Mission._uf_union(uf, vpoly[key], idx)
					else:
						vpoly[key] = idx
				idx += 1
		for k in _isl:
			_isl[k] = Mission._uf_find(uf, _isl[k])
	return int(_isl.get([r, pi], -1))


func _draw_zoom(m: Mission, id: String, idx: int, c: Vector3, r: float, nav_map: RID) -> void:
	var size := 800
	var sc := size / (2.0 * r)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.08))
	var levels := {}
	for n in m.find_children("*", "NavigationRegion3D", true, false):
		var nm := (n as NavigationRegion3D).navigation_mesh
		if nm == null:
			continue
		var vs := nm.get_vertices()
		for pi in nm.get_polygon_count():
			var poly := nm.get_polygon(pi)
			var pts2: PackedVector2Array = []
			var yy := 0.0
			var near := false
			for k in poly:
				pts2.append(Vector2((vs[k].x - c.x + r) * sc, (vs[k].z - c.z + r) * sc))
				yy += vs[k].y
				if absf(vs[k].x - c.x) < r and absf(vs[k].z - c.z) < r:
					near = true
			if not near:
				continue
			yy /= poly.size()
			if absf(yy - c.y) > 8.0:
				continue
			levels[snappedf(yy, 0.5)] = int(levels.get(snappedf(yy, 0.5), 0)) + 1
			# Farbe nach Erreichbarkeit vom Prüfpunkt (grün = erreichbar, sonst nach Höhe blau/gelb)
			var mid := Vector3.ZERO
			for k in poly:
				mid += vs[k]
			mid /= poly.size()
			var col: Color
			if Game.cli.has("islands"):
				# Insel (verschweißte Eckpunkte) als Zufallsfarbe, Helligkeit nach Höhe
				var isl := _island_of(n as NavigationRegion3D, pi)
				var rng := RandomNumberGenerator.new()
				rng.seed = isl * 7919 + 13
				col = Color.from_hsv(rng.randf(), 0.6, 0.45 + 0.5 * clampf((yy - c.y + 4.0) / 8.0, 0.0, 1.0))
			else:
				var src := c
				if Game.cli.has("from"):
					var f := String(Game.cli["from"]).split_floats(",")
					src = Vector3(f[0], f[1], f[2])
				var cp := NavigationServer3D.map_get_closest_point(nav_map, src)
				var ok := _reachable(nav_map, cp, NavigationServer3D.map_get_closest_point(nav_map, mid))
				var t := clampf((yy - c.y + 4.0) / 8.0, 0.0, 1.0)
				col = Color(0.2, 0.4 + 0.5 * t, 0.2) if ok else Color(0.3 + 0.6 * t, 0.3 + 0.5 * t, 0.8 - 0.5 * t)
			_fill_poly(img, pts2, col)
	# Kollisionsquerschnitt (Ray-Raster in Hüfthöhe)
	var space := m.get_world_3d().direct_space_state
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0 / sc, 0.1, 2.0 / sc)
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = bx
	sq.collision_mask = 1 | (1 << 4)
	for gx in range(0, size, 4):
		for gz in range(0, size, 4):
			var w := Vector3(c.x - r + gx / sc, c.y + 1.0, c.z - r + gz / sc)
			sq.transform = Transform3D(Basis(), w)
			if not space.intersect_shape(sq, 1).is_empty():
				img.set_pixel(gx, gz, Color.RED)
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			img.set_pixel(size / 2 + dx, size / 2 + dz, Color.WHITE)
	img.save_png(ProjectSettings.globalize_path("res://test_output/navprobe_%s_%d.png" % [id, idx]))
	print("   Netzhöhen im Umkreis: ", levels)
