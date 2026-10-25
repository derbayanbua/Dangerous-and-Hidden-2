extends "res://tests/test_gameplay.gd"
## Navigationsnetz aller Mehrspielerkarten: vollständig (Netz vorhanden, alle Spawnpunkte, Zonen-Mittelpunkte und
## Zonen-Spawnplätze liegen auf dem Netz) und zusammenhängend (KI-Pfad von einem Bezugspunkt zu jedem dieser Punkte).
##   tools\godot.cmd --headless -- --autoplay=test_mp_nav [--maps=mp|<id>,…] [--tag=_x]
## Bericht: test_output/mp_nav_report<tag>.txt

const SNAP_H := 1.5      ## Punkt gilt als „auf dem Netz“, wenn der nächste Netzpunkt so nah liegt (waagerecht)
const SNAP_V := 1.2
const REACH := 1.5       ## Pfadende so nah am Ziel = erreichbar

var rows: Array[String] = []
var report_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _maps() -> Array:
	var sel := String(Game.cli.get("maps", "mp"))
	var campaign: Array = ["a1_blizzard", "a2_erkundung", "a3_rendezvous"]
	for e in Game.ORIG_CAMPAIGN:
		campaign.append(e[0])
	var out: Array = []
	for id in Game.MP_MAPS:
		if not String(id).begins_with("mp_arena_"):
			out.append(id)
	match sel:
		"mp":
			return out
		"campaign":
			return campaign
		"all":
			return campaign + out
	return Array(sel.split(",", false))


func _run() -> void:
	report_path = ProjectSettings.globalize_path("res://test_output/mp_nav_report%s.txt" % String(Game.cli.get("tag", "")))
	var maps := _maps()
	get_tree().create_timer(300.0 * maps.size() + 60.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	rows.append("| Karte | Polygone | Punkte | auf dem Netz | erreichbar | Hinweise |")
	rows.append("|---|---|---|---|---|---|")
	for id in maps:
		await _test_map(String(id))
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(rows) + "\n")
	_finish()


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
		check(false, "%s: geladen" % id)
		rows.append("| %s | – | – | – | – | Laden fehlgeschlagen |" % id)
		return
	while is_instance_valid(m) and not m.nav_ready and Time.get_ticks_msec() - t0 < 600000:
		await get_tree().process_frame
	if not is_instance_valid(m):
		check(false, "%s: Mission bleibt geladen" % id)
		rows.append("| %s | – | – | – | – | Mission vorzeitig entladen |" % id)
		return
	await frames(5)
	var nav_map := m.nav_region.get_navigation_map()
	var polys := 0
	for n in m.find_children("*", "NavigationRegion3D", true, false):
		var nr := n as NavigationRegion3D
		if nr.navigation_mesh:
			polys += nr.navigation_mesh.get_polygon_count()
	# Prüfpunkte: Spawnpunkte, Zonen-Mittelpunkte und Zonen-Spawnplätze (mp_arena)
	var pts: Array = []
	var spawns: Array = m.get("_spawn_points") if m.get("_spawn_points") != null else []
	var zones: Array = m.get("_zones") if m.get("_zones") != null else []
	for sp in spawns:
		pts.append(["Spawn", _ground(m, sp.pos as Vector3)])
	for z in zones:
		pts.append(["Zone " + String(z.name), _ground(m, (z.xf as Transform3D).origin)])
		for s in z.get("slots", []):
			pts.append(["Platz " + String(z.name), _ground(m, s.pos as Vector3)])
	if pts.is_empty() and m.get("squad") != null:
		await _skip_intro(m)
	if pts.is_empty():
		# Kampagnenkarte: Startlage aller Soldaten (Trupp, Gegner, NPC) außer in Fahrzeugen/Stellungen
		for s in get_tree().get_nodes_in_group("soldiers"):
			var so := s as Soldier
			if so == null or not so.is_inside_tree() or so.vehicle != null:
				continue
			if so.mounted != null or not so.alive:
				continue
			var q := PhysicsRayQueryParameters3D.create(so.global_position + Vector3.UP, so.global_position + Vector3.DOWN * 30.0, 1)
			if m.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				print("   (übersprungen: %s ohne Boden bei %s – versteckt/fällt)" % [so.name, _v(so.global_position)])
				continue
			pts.append(["%s %s" % ["Trupp" if so.team == 0 else "Soldat", so.name], _ground(m, so.global_position)])
	var on := 0
	var reach := 0
	var notes: Array[String] = []
	var snapped: Array = []
	for p in pts:
		var c := NavigationServer3D.map_get_closest_point(nav_map, p[1])
		var ok := _near(c, p[1], SNAP_H, SNAP_V)
		snapped.append(c if ok else Vector3.INF)
		if ok:
			on += 1
		elif notes.size() < 6:
			notes.append("%s %s nicht auf dem Netz (nächster %s)" % [p[0], _v(p[1]), _v(c)])
	# Bezugspunkt: Punkt, von dem aus die meisten anderen erreichbar sind (erste Zone bzw. erster Spawn als Start)
	var best := -1
	var best_n := -1
	var step := maxi(snapped.size() / 12, 1)
	for i in range(0, snapped.size(), step):
		if not snapped[i].is_finite():
			continue
		var n := 0
		for j in snapped.size():
			if snapped[j].is_finite() and _reachable(nav_map, snapped[i], snapped[j]):
				n += 1
		if n > best_n:
			best_n = n
			best = i
	if best >= 0:
		for j in snapped.size():
			if snapped[j].is_finite():
				if _reachable(nav_map, snapped[best], snapped[j]):
					reach += 1
				elif notes.size() < 10:
					var pth := NavigationServer3D.map_get_path(nav_map, snapped[best], snapped[j], true)
					notes.append("%s %s nicht erreichbar (von %s, Pfad endet %s)" % [pts[j][0], _v(pts[j][1]),
						_v(snapped[best]), _v(pth[pth.size() - 1]) if pth.size() > 0 else "-"])
	var n_pts := pts.size()
	if Game.cli.has("nav_png"):
		_draw_png(m, id, pts, snapped, best, nav_map)
	print("MPNAV %s: %d Polygone, %d Punkte, %d auf dem Netz, %d erreichbar" % [id, polys, n_pts, on, reach])
	for nt in notes:
		print("   ", nt)
	rows.append("| %s | %d | %d | %d/%d | %d/%d | %s |" % [id, polys, n_pts, on, n_pts, reach, n_pts,
		"; ".join(notes) if not notes.is_empty() else "–"])
	check(polys > 0, "%s: Navigationsnetz vorhanden" % id, str(polys))
	check(on == n_pts, "%s: alle Spawns/Zonen auf dem Netz" % id, "%d/%d" % [on, n_pts])
	check(reach == n_pts, "%s: Netz zusammenhängend (alle Punkte erreichbar)" % id, "%d/%d" % [reach, n_pts])


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


## Kampagne: Zwischensequenz wie ein Spieler überspringen und Landung abwarten (ARCTIC1 beginnt mit dem Absprung),
## damit die Trupp-Lage der tatsächliche Spielbeginn ist (wie test_commands_orig).
func _skip_intro(m: Mission) -> void:
	for i in 600:
		var rt0 = m.get("runtime")
		if (rt0 and bool(rt0.get("in_cutscene"))) or m.elapsed > 12.0:
			break
		await frames(1)
	await seconds(1.5)
	for i in 60:
		var rt = m.get("runtime")
		if (m.controller == null or m.controller.input_enabled) and not (rt and bool(rt.get("in_cutscene"))):
			break
		await key(KEY_SPACE)
		await seconds(0.5)
	var calm := 0.0
	for i in 60:
		var ok := true
		for s in m.squad.members:
			ok = ok and (not s.alive or (s.is_on_floor() and absf(s.velocity.y) < 0.5))
		calm = calm + 0.5 if ok else 0.0
		if calm >= 2.0:
			break
		await seconds(0.5)


## Draufsicht des Netzes (Fehlersuche): Polygone grau (heller = höher), Punkte grün = erreichbar, rot = nicht,
## Bezugspunkt blau → test_output/mpnav_<karte>.png
func _draw_png(m: Mission, id: String, pts: Array, snapped: Array, best: int, nav_map: RID) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ylo := INF
	var yhi := -INF
	var meshes: Array = []
	for n in m.find_children("*", "NavigationRegion3D", true, false):
		var nm := (n as NavigationRegion3D).navigation_mesh
		if nm == null:
			continue
		meshes.append(nm)
		for v in nm.get_vertices():
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
			ylo = minf(ylo, v.y)
			yhi = maxf(yhi, v.y)
	if meshes.is_empty():
		return
	var size := 1400
	var sc: float = (size - 20) / maxf(hi.x - lo.x, hi.y - lo.y)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.08))
	for nm in meshes:
		var vs: PackedVector3Array = nm.get_vertices()
		for pi in nm.get_polygon_count():
			var poly: PackedInt32Array = nm.get_polygon(pi)
			var pts2: PackedVector2Array = []
			var yy := 0.0
			for k in poly:
				pts2.append(Vector2(10 + (vs[k].x - lo.x) * sc, 10 + (vs[k].z - lo.y) * sc))
				yy += vs[k].y
			yy /= poly.size()
			var shade := 0.25 + 0.6 * clampf((yy - ylo) / maxf(yhi - ylo, 1.0), 0.0, 1.0)
			_fill_poly(img, pts2, Color(shade, shade, shade))
	for i in pts.size():
		var p: Vector3 = pts[i][1]
		var c := Color.RED
		if i == best:
			c = Color.DODGER_BLUE
		elif snapped[i].is_finite() and best >= 0 and _reachable(nav_map, snapped[best], snapped[i]):
			c = Color.GREEN
		var q := Vector2i(int(10 + (p.x - lo.x) * sc), int(10 + (p.z - lo.y) * sc))
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var r := q + Vector2i(dx, dy)
				if r.x >= 0 and r.y >= 0 and r.x < size and r.y < size:
					img.set_pixelv(r, c)
	img.save_png(ProjectSettings.globalize_path("res://test_output/mpnav_%s.png" % id))
	print("   Bild test_output/mpnav_%s.png (Maßstab %.2f px/m, Ursprung %s)" % [id, sc, str(lo)])


static func _fill_poly(img: Image, p: PackedVector2Array, c: Color) -> void:
	var y0 := int(floor(p[0].y))
	var y1 := y0
	for v in p:
		y0 = mini(y0, int(floor(v.y)))
		y1 = maxi(y1, int(ceil(v.y)))
	for y in range(maxi(y0, 0), mini(y1 + 1, img.get_height())):
		var xs: Array = []
		for k in p.size():
			var a := p[k]
			var b := p[(k + 1) % p.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(maxi(int(xs[k]), 0), mini(int(xs[k + 1]) + 1, img.get_width())):
				img.set_pixel(x, y, c)


func _reachable(nav_map: RID, a: Vector3, b: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav_map, a, b, true)
	return path.size() > 0 and _near(path[path.size() - 1], b, REACH, 1.0)


## Zonenmittelpunkt kann in der Luft liegen (Kugelzone): Boden darunter
func _ground(m: Mission, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 30.0, 1)
	var hit := m.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func _near(a: Vector3, b: Vector3, h: float, v: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < h and absf(a.y - b.y) < v


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
