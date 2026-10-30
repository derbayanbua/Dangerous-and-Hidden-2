extends "res://tests/test_gameplay.gd"
## Treppen in allen Karten begehbar (Spieler und KI):
##  1. Treppen aus der sichtbaren Levelgeometrie finden: Folgen waagerechter Trittflächen mit gleichmäßiger
##     Stufenhöhe (0,07–0,35 m), mindestens 4 Tritte, Kopfraum für einen stehenden Soldaten.
##  2. Je Treppe ein Soldat (alle gleichzeitig): hinauf (Trittmitten als Wegpunkte), wieder hinunter
##     (ohne Sprung/Fall: kein Flug > 0,35 s, keine Fallgeschwindigkeit < −4,5 m/s).
##  3. KI: Pfad im Navigationsnetz vom Fuß zur obersten Stufe; Soldat folgt dem KI-Pfad hinauf.
## Ergebnis je Karte: test_output/stairs_report<tag>.txt (Tabelle).
##   tools\godot.cmd --headless -- --autoplay=test_stairs [--maps=all|campaign|mp|practice|<id>,…]
##       [--max_stairs=8] [--tag=_a]

const MIN_TREADS := 4
const RISE_MIN := 0.07
const RISE_MAX := 0.35
const MAP_TIMEOUT_S := 660.0

var max_stairs := 8
var rows: Array[String] = []
var report_path := ""
var _map_deadline := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _map_list() -> Array:
	var sel := String(Game.cli.get("maps", "all"))
	var campaign: Array = ["a1_blizzard", "a2_erkundung", "a3_rendezvous"]
	for e in Game.ORIG_CAMPAIGN:
		campaign.append(e[0])
	var mp: Array = []
	for id in Game.MP_MAPS:
		if not String(id).begins_with("mp_arena_"):
			mp.append(id)
	var practice: Array = [Game.ORIG_TRAINING[0], "m01_funkfeuer", "m02_nordlicht", "m03_sandsturm"]
	match sel:
		"all":
			return campaign + practice + mp
		"campaign":
			return campaign
		"mp":
			return mp
		"practice":
			return practice
	return Array(sel.split(",", false))


func _run() -> void:
	max_stairs = int(Game.cli.get("max_stairs", "8"))
	report_path = ProjectSettings.globalize_path("res://test_output/stairs_report%s.txt" % String(Game.cli.get("tag", "")))
	var maps := _map_list()
	get_tree().create_timer(MAP_TIMEOUT_S * maps.size() + 120.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	rows.append("| Karte | Ordner | Treppen | geprüft | hinauf | hinunter | KI-Pfad | KI folgt | Stufenhöhe | Hinweise |")
	rows.append("|---|---|---|---|---|---|---|---|---|---|")
	_write_report()
	for id in maps:
		await _test_map(String(id))
		_write_report()
	_finish()


func _write_report() -> void:
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(rows) + "\n")


# --- Karte laden ------------------------------------------------------------------------------------

func _test_map(id: String) -> void:
	if not Game.MISSIONS.has(id):
		check(false, "%s: Karte unbekannt" % id)
		rows.append("| %s | – | – | – | – | – | – | – | – | unbekannt |" % id)
		return
	var folder := String(Game.MISSIONS[id].get("orig", ""))
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
		check(false, "%s: Karte geladen" % id)
		rows.append("| %s | %s | – | – | – | – | – | – | – | Laden fehlgeschlagen |" % [id, folder])
		return
	var load_s := (Time.get_ticks_msec() - t0) / 1000.0
	if folder == "" and m.get("orig_mission") != null:
		folder = String(m.get("orig_mission"))
	if folder == "":
		folder = "eigen (prozedural)"
	await frames(10)
	_freeze_world(m)
	while not m.nav_ready:      # große Karten (NORWAY: Kachelbake + Inselbrücken ≈ 3 min) – zeitbasiert warten
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 480000:
			break
	var nav_s := (Time.get_ticks_msec() - t0) / 1000.0 - load_s
	var ts0 := Time.get_ticks_msec()
	var stairs := find_stairs(m.static_root, m.get_world_3d().direct_space_state)
	print("STAIRS %s: %d Treppen gefunden (%.1f s), geladen %.0f s, Navmesh %.0f s" % [id, stairs.size(),
		(Time.get_ticks_msec() - ts0) / 1000.0, load_s, nav_s])
	if m.get("orig") != null:
		print("   Kollision: ", m.get("orig").stats)
	for s in stairs:
		print("   Treppe %s: %d Tritte, Höhe %.2f m, Stufe %.2f m, %s → %s" % [s.name, s.treads.size(), s.height, s.rise,
			_v(s.bottom), _v(s.top)])
	if stairs.is_empty():
		rows.append("| %s | %s | 0 | – | – | – | – | – | – | keine Treppen in der Levelgeometrie |" % [id, folder])
		check(true, "%s: keine Treppen" % id)
		return
	var sel := _select(stairs)
	var res := await _walk_all(m, sel)
	var n := sel.size()
	var rises: Array = sel.map(func(s): return s.rise)
	rises.sort()
	var notes: Array[String] = []
	for r in res:
		if not (r.up and r.down and r.nav and r.nav_walk):
			notes.append("%s:%s%s%s%s" % [r.name, "" if r.up else " hinauf✗", "" if r.down else " hinunter✗",
				"" if r.nav else " Pfad✗(" + r.nav_note + ")", "" if r.nav_walk else " KI✗"])
	var c_up := res.filter(func(r): return r.up).size()
	var c_dn := res.filter(func(r): return r.down).size()
	var c_nav := res.filter(func(r): return r.nav).size()
	var c_nw := res.filter(func(r): return r.nav_walk).size()
	rows.append("| %s | %s | %d | %d | %d/%d | %d/%d | %d/%d | %d/%d | %.2f–%.2f m | %s |" % [id, folder, stairs.size(), n,
		c_up, n, c_dn, n, c_nav, n, c_nw, n, rises[0], rises[-1], "; ".join(notes) if not notes.is_empty() else "–"])
	check(c_up == n, "%s: Soldat steigt alle %d Treppen hinauf" % [id, n], "%d/%d" % [c_up, n])
	check(c_dn == n, "%s: Soldat steigt alle Treppen hinunter (ohne Sprung/Fall)" % id, "%d/%d" % [c_dn, n])
	check(c_nav == n, "%s: KI-Pfad zur obersten Stufe" % id, "%d/%d" % [c_nav, n])
	check(c_nw == n, "%s: Soldat folgt dem KI-Pfad hinauf" % id, "%d/%d" % [c_nw, n])


## Gegner, Trupp, Skripte und Fahrzeuge anhalten, damit nur die Testsoldaten laufen.
func _freeze_world(m: Mission) -> void:
	var far := Vector3(5000, -900, 5000)
	for s in get_tree().get_nodes_in_group("soldiers"):
		_park(s, far)
		far.x += 3.0
	if m.get("runtime") != null and is_instance_valid(m.get("runtime")):
		(m.get("runtime") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n in m.dynamic_root.get_children():
		if n is VehicleBody3D or n is RigidBody3D:
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED


func _park(s: Node, at: Vector3) -> void:
	for c in s.get_children():
		c.process_mode = Node.PROCESS_MODE_DISABLED
	(s as Node3D).global_position = at
	s.process_mode = Node.PROCESS_MODE_DISABLED


# --- Treppen finden ------------------------------------------------------------------------------------

class Stair:
	var name := ""
	var treads: Array = []       ## Trittmittelpunkte (Welt), aufsteigend
	var bottom := Vector3.ZERO   ## Standpunkt vor der ersten Stufe
	var top := Vector3.ZERO      ## oberster Tritt
	var height := 0.0
	var rise := 0.0              ## mittlere Stufenhöhe


## Waagerechte Flächen (|n.y| > 0,985) der sichtbaren Levelgeometrie zu Trittflächen zusammenfassen
## (gemeinsame Eckpunkte, 2 cm Raster) und Ketten mit gleichmäßiger Steigung suchen.
func find_stairs(root: Node, space: PhysicsDirectSpaceState3D) -> Array:
	var uf := {}                     # Vector3i -> Vector3i (Union-Find der Eckpunkte)
	var tris: Array = []             # [Schlüssel a, Fläche, Schwerpunkt, Ecken a, b, c]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.get_aabb().size.y > 30.0:
			continue
		var xf: Transform3D = mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size() - 2, 3):
			var a: Vector3 = xf * f[i]
			var b: Vector3 = xf * f[i + 1]
			var c: Vector3 = xf * f[i + 2]
			var n := (b - a).cross(c - a)
			var ln := n.length()
			if ln < 1e-5 or absf(n.y) < 0.985 * ln:
				continue
			var ka := Vector3i((a * 50.0).round())
			var kb := Vector3i((b * 50.0).round())
			var kc := Vector3i((c * 50.0).round())
			_union(uf, ka, kb)
			_union(uf, ka, kc)
			tris.append([ka, ln * 0.5, (a + b + c) / 3.0, a, b, c])
	var patches := {}                # Wurzel -> {area, sum, lo, hi, y}
	for t in tris:
		var r: Vector3i = _find(uf, t[0])
		var p: Dictionary = patches.get(r, {})
		if p.is_empty():
			p = {"area": 0.0, "sum": Vector3.ZERO, "lo": Vector2(INF, INF), "hi": Vector2(-INF, -INF), "y": (t[3] as Vector3).y}
			patches[r] = p
		p.area += t[1]
		p.sum += t[2] * t[1]
		for k in [3, 4, 5]:
			var v: Vector3 = t[k]
			p.lo = Vector2(minf(p.lo.x, v.x), minf(p.lo.y, v.z))
			p.hi = Vector2(maxf(p.hi.x, v.x), maxf(p.hi.y, v.z))
	# Trittflächen: mindestens 0,06 m², 0,12–3 m tief, höchstens 10 m lang
	var tread: Array = []
	for r in patches:
		var p: Dictionary = patches[r]
		var ext: Vector2 = p.hi - p.lo
		if p.area < 0.06 or minf(ext.x, ext.y) < 0.12 or minf(ext.x, ext.y) > 3.0 or maxf(ext.x, ext.y) > 10.0:
			continue
		p.c = p.sum / p.area
		tread.append(p)
	tread.sort_custom(func(x, y): return x.y < y.y)
	# Raster für Nachbarsuche (1 m)
	var grid := {}
	for i in tread.size():
		var k := Vector2i(floori(tread[i].c.x), floori(tread[i].c.z))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(i)
	var preds: Array = []
	preds.resize(tread.size())
	for i in tread.size():
		var pi: Dictionary = tread[i]
		var lst: Array = []
		var k0 := Vector2i(floori(pi.c.x), floori(pi.c.z))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for j in grid.get(k0 + Vector2i(dx, dz), []):
					var pj: Dictionary = tread[j]
					var dy: float = pi.y - pj.y
					if dy < RISE_MIN or dy > RISE_MAX:
						continue
					var hd := Vector2(pi.c.x - pj.c.x, pi.c.z - pj.c.z).length()
					if hd < 0.12 or hd > 1.6:
						continue
					# Flächen grenzen aneinander (Rechtecke um 0,1 m erweitert)
					if pi.lo.x > pj.hi.x + 0.1 or pj.lo.x > pi.hi.x + 0.1 or pi.lo.y > pj.hi.y + 0.1 or pj.lo.y > pi.hi.y + 0.1:
						continue
					lst.append(j)
		preds[i] = lst
	if Game.cli.has("stairs_debug"):      # --stairs_debug=x,z: Trittflächen im Umkreis von 4 m ausgeben
		var xz := String(Game.cli["stairs_debug"]).split_floats(",")
		for i in tread.size():
			var p: Dictionary = tread[i]
			if Vector2(p.c.x - xz[0], p.c.z - xz[1]).length() < 4.0:
				print("   DBG Tritt %d y %.2f c %s A %.2f ext %s ok %s Vorgänger %s" % [i, p.y, _v(p.c), p.area,
					str(p.hi - p.lo), _free(space, p.c), str(preds[i])])
	var used := {}
	var out: Array = []
	for round_i in 80:
		# längste Kette (aufsteigend) ohne bereits vergebene Tritte, gleichmäßige Stufenhöhe
		var best: Array = []
		var prev: Array = []
		best.resize(tread.size())
		prev.resize(tread.size())
		var top_i := -1
		for i in tread.size():
			best[i] = 0 if used.has(i) else 1
			prev[i] = -1
			if used.has(i):
				continue
			for j in preds[i]:
				if used.has(j) or best[j] + 1 <= best[i]:
					continue
				# Stufen einer Treppe: ähnliche Trittfläche (Möbel/Kisten-Stapel ausschließen)
				var ar: float = tread[i].area / tread[j].area
				if ar < 0.4 or ar > 2.5:
					continue
				if prev[j] >= 0:
					var r1: float = tread[i].y - tread[j].y
					var r0: float = tread[j].y - tread[prev[j]].y
					if absf(r1 - r0) > 0.06:
						continue
					# gleichbleibende Laufrichtung (Wendeltreppen: kleine Drehung je Stufe)
					var v1: Vector3 = tread[i].c - tread[j].c
					var v0: Vector3 = tread[j].c - tread[prev[j]].c
					if absf(Vector2(v1.x, v1.z).angle_to(Vector2(v0.x, v0.z))) > deg_to_rad(60.0):
						continue
				best[i] = best[j] + 1
				prev[i] = j
			if top_i < 0 or best[i] > best[top_i]:
				top_i = i
		if top_i < 0 or best[top_i] < MIN_TREADS:
			break
		var chain: Array = []
		var i2 := top_i
		while i2 >= 0:
			chain.push_front(i2)
			used[i2] = true
			i2 = prev[i2]
		var st := _make_stair(chain.map(func(ix): return tread[ix].c), space)
		if st:
			st.name = "T%d" % (out.size() + 1)
			out.append(st)
	return out


func _make_stair(pts: Array, space: PhysicsDirectSpaceState3D) -> Stair:
	# Kopfraum: stehender Soldat (Kapsel r 0,25, 1,7 m) auf jedem Tritt; Enden ohne Kopfraum (Türsturz, Decke über
	# dem Austritt) abschneiden, Lücken in der Mitte verwerfen
	while pts.size() > 0 and not _free(space, pts[-1]):
		pts.pop_back()
	while pts.size() > 0 and not _free(space, pts[0]):
		pts.pop_front()
	if pts.size() < MIN_TREADS:
		return null
	for p in pts:
		if not _free(space, p):
			return null
	var h: float = pts[-1].y - pts[0].y
	if h < 0.45:
		return null
	var st := Stair.new()
	st.treads = pts
	st.height = h
	st.rise = h / (pts.size() - 1)
	st.top = pts[-1]
	var d0: Vector3 = pts[1] - pts[0]
	d0.y = 0.0
	d0 = d0.normalized()
	# Standpunkt vor der ersten Stufe: Boden eine Stufe tiefer, 0,6 m vor dem ersten Tritt
	st.bottom = pts[0]
	var probe: Vector3 = pts[0] - d0 * 0.6
	var q := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.1, probe + Vector3.DOWN * 0.6, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and pts[0].y - hit.position.y < RISE_MAX + 0.05 and _free(space, hit.position):
		st.bottom = hit.position
	return st


func _free(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.6
	params.shape = cap
	# Unterkante 0,42 m über dem Tritt: Treppen mit echter Stufenkollision (CZECH1/4 nach dem B-010-Ersatzkörperfix) –
	# die nächste Setzstufe (bis 0,3 m) darf nicht schon als fehlender Kopfraum zählen
	params.transform = Transform3D(Basis(), p + Vector3(0, 0.42 + 0.8, 0))
	params.collision_mask = 1
	return space.intersect_shape(params, 1).is_empty()


func _find(uf: Dictionary, k: Vector3i) -> Vector3i:
	var r := k
	while uf.has(r) and uf[r] != r:
		r = uf[r]
	var c := k
	while uf.has(c) and uf[c] != r:
		var nx: Vector3i = uf[c]
		uf[c] = r
		c = nx
	return r


func _union(uf: Dictionary, a: Vector3i, b: Vector3i) -> void:
	if not uf.has(a):
		uf[a] = a
	if not uf.has(b):
		uf[b] = b
	var ra := _find(uf, a)
	var rb := _find(uf, b)
	if ra != rb:
		uf[rb] = ra


## Höchstens max_stairs Treppen: die höchsten, räumlich verteilt (≥ 6 m Abstand)
func _select(stairs: Array) -> Array:
	var s2 := stairs.duplicate()
	s2.sort_custom(func(a, b): return a.height > b.height)
	var out: Array = []
	for s in s2:
		var far := true
		for o in out:
			if o.bottom.distance_to(s.bottom) < 6.0:
				far = false
		if far:
			out.append(s)
		if out.size() >= max_stairs:
			break
	return out


# --- Begehung ----------------------------------------------------------------------------------------

class Walker:
	var st: Stair
	var s: Soldier
	var pts: Array = []
	var idx := 0
	var frames := 0
	var limit := 0
	var done := false
	var ok := false
	var air := 0.0
	var max_air := 0.0
	var min_vy := 0.0
	var nav := false        ## KI-Phase: wie AIBrain (Zwischenpunkt 0,45 m, Festhängen → Klettern bzw. Punkt überspringen)
	var best := INF
	var stall := 0


func _walk_all(m: Mission, sel: Array) -> Array:
	var res: Array = []
	var walkers: Array = []
	for i in sel.size():
		var st: Stair = sel[i]
		var d0: Vector3 = st.treads[1] - st.treads[0]
		var s := m.spawn_soldier(st.bottom + Vector3.UP * 0.05, atan2(-d0.x, -d0.z), Soldier.TEAM_ALLIED, "Treppe %d" % i,
			["", "", ""], Color(0.4, 0.4, 0.3), "brodie", "stair_%d" % i)
		s.move_mode = Soldier.MoveMode.JOG
		var w := Walker.new()
		w.st = st
		w.s = s
		walkers.append(w)
		res.append({"name": st.name, "up": false, "down": false, "nav": false, "nav_walk": false, "nav_note": ""})
	await frames(20)
	# 1. hinauf über die Trittmitten
	for w in walkers:
		var pts: Array = w.st.treads.slice(1)
		_start(w, pts)
	await _drive(walkers)
	for i in walkers.size():
		var w: Walker = walkers[i]
		res[i].up = _at(w.s, w.st.top)
		if not res[i].up:
			print("   %s hinauf ✗: Soldat bei %s (Ziel %s)" % [w.st.name, _v(w.s.global_position), _v(w.st.top)])
	if Game.cli.has("stairs_shots") and DisplayServer.get_name() != "headless":
		await _shots(m, walkers)
	# 2. wieder hinunter (Sprung/Fall erkennen)
	for i in walkers.size():
		var w: Walker = walkers[i]
		if not res[i].up:
			w.s.global_position = w.st.top + Vector3.UP * 0.05
			w.s.velocity = Vector3.ZERO
		var pts: Array = w.st.treads.slice(0, w.st.treads.size() - 1)
		pts.reverse()
		pts.append(w.st.bottom)
		_start(w, pts)
	await frames(2)
	await _drive(walkers)
	for i in walkers.size():
		var w: Walker = walkers[i]
		res[i].down = _at(w.s, w.st.bottom) and w.max_air < 0.35 and w.min_vy > -4.5
		if not res[i].down:
			print("   %s hinunter ✗: bei %s (Ziel %s), Flugzeit %.2f s, vy min %.1f" % [w.st.name, _v(w.s.global_position),
				_v(w.st.bottom), w.max_air, w.min_vy])
	# 3. KI: Pfad im Navigationsnetz und Begehung entlang des Pfades
	var nav_map := m.nav_region.get_navigation_map()
	for i in walkers.size():
		var w: Walker = walkers[i]
		w.s.global_position = w.st.bottom + Vector3.UP * 0.05
		w.s.velocity = Vector3.ZERO
		var a := NavigationServer3D.map_get_closest_point(nav_map, w.st.bottom)
		var b := NavigationServer3D.map_get_closest_point(nav_map, w.st.top)
		var path := NavigationServer3D.map_get_path(nav_map, a, b, true)
		# Ende auf der Höhe der obersten Stufe (Netz endet ggf. bis 1,2 m vor einer Wand am Austritt)
		# Netz liegt auf der Ersatzrampe, die oben bis ~0,4 m über der sichtbaren Stufe enden kann (+ Zellhöhe)
		var end_ok := path.size() > 0 and _near(path[path.size() - 1], w.st.top, 1.2, 0.7)
		var start_ok := _near(a, w.st.bottom, 0.8, 0.5)
		res[i].nav = m.nav_ready and start_ok and end_ok
		if not res[i].nav:
			res[i].nav_note = "kein Netz" if not m.nav_ready else ("Fuß %s" % _v(a) if not start_ok else "Ende %s" % (_v(path[path.size() - 1]) if path.size() > 0 else "-"))
			print("   %s KI-Pfad ✗: %s (Fuß %s, oben %s)" % [w.st.name, res[i].nav_note, _v(w.st.bottom), _v(w.st.top)])
		var pts: Array = Array(path).slice(1) if res[i].nav else []
		if pts.is_empty():
			w.done = true
		else:
			_start(w, pts)
			w.nav = true
			w.limit += 300   # Klettern/Umwege über Navigationsverbindungen
	await frames(2)
	await _drive(walkers)
	for i in walkers.size():
		var w: Walker = walkers[i]
		# Netzhöhe weicht um bis zu eine Zellhöhe ab → Höhe gegen die oberste Stufe prüfen
		res[i].nav_walk = res[i].nav and _near(w.s.global_position, w.pts[-1], 0.6, 0.8) \
			and absf(w.s.global_position.y - w.st.top.y) < 0.35
		if res[i].nav and not res[i].nav_walk:
			print("   %s KI folgt ✗: bei %s (Pfadende %s)" % [w.st.name, _v(w.s.global_position), _v(w.pts[-1])])
	for w in walkers:
		w.s.queue_free()
	await frames(2)
	return res


## Kontrollbilder (Fenster): Soldat oben angekommen, Blick vom Fuß der Treppe → test_output/stairs_<Karte>_<T>.png
func _shots(m: Mission, walkers: Array) -> void:
	var cam := Camera3D.new()
	cam.fov = 70.0
	m.add_child(cam)
	cam.make_current()
	if m.hud:
		m.hud.visible = false
	var space := m.get_world_3d().direct_space_state
	for w: Walker in walkers:
		# 3.-Person-Blick von hinten-oben (Richtung der letzten Stufen), Kamera vor Wänden einziehen
		var d: Vector3 = w.st.treads[-1] - w.st.treads[maxi(w.st.treads.size() - 4, 0)]
		d.y = 0.0
		d = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
		var head := w.s.global_position + Vector3.UP * 1.6
		var want := head - d * 3.0 + Vector3.UP * 1.4
		var q := PhysicsRayQueryParameters3D.create(head, want, 1)
		var hit := space.intersect_ray(q)
		cam.global_position = want if hit.is_empty() else head.lerp(hit.position, 0.85)
		cam.look_at(w.s.global_position + Vector3.UP * 0.8, Vector3.UP)
		await frames(8)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://test_output/stairs_%s_%s.png" % [Game.current_mission_id, w.st.name]))
		if Game.cli.has("stairs_navshots"):
			# Draufsicht mit eingeblendetem Navigationsnetz (Fehlersuche)
			NavigationServer3D.set_debug_enabled(true)
			var mid: Vector3 = (w.st.bottom + w.st.top) * 0.5
			cam.global_position = mid + Vector3(0.01, 7.0, 2.5)
			cam.look_at(mid, Vector3.UP)
			await frames(8)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(
				"res://test_output/stairs_%s_%s_nav.png" % [Game.current_mission_id, w.st.name]))
			NavigationServer3D.set_debug_enabled(false)
	cam.queue_free()
	if m.hud:
		m.hud.visible = true
	if m.rig and m.rig.camera:
		m.rig.camera.make_current()


func _start(w: Walker, pts: Array) -> void:
	w.pts = pts
	w.idx = 0
	w.frames = 0
	w.limit = 150 + 70 * pts.size()
	w.done = false
	w.air = 0.0
	w.max_air = 0.0
	w.min_vy = 0.0
	w.nav = false
	w.best = INF
	w.stall = 0


func _drive(walkers: Array) -> void:
	var active := true
	while active:
		active = false
		for w: Walker in walkers:
			if w.done:
				continue
			active = true
			w.frames += 1
			var s := w.s
			if s.is_on_floor():
				w.air = 0.0
			else:
				w.air += 1.0 / 60.0
				w.max_air = maxf(w.max_air, w.air)
			w.min_vy = minf(w.min_vy, s.velocity.y)
			var target: Vector3 = w.pts[w.idx]
			var d := target - s.global_position
			d.y = 0.0
			var last := w.idx == w.pts.size() - 1
			if d.length() < (0.2 if last else (0.45 if w.nav else 0.3)):
				w.idx += 1
				w.best = INF
				w.stall = 0
				if w.idx >= w.pts.size():
					w.done = true
					s.move_input = Vector3.ZERO
					continue
				target = w.pts[w.idx]
				d = target - s.global_position
				d.y = 0.0
			if w.frames > w.limit:
				w.done = true
				s.move_input = Vector3.ZERO
				continue
			if Game.cli.has("stairs_trace") and w.frames % 15 == 0 and String(Game.cli["stairs_trace"]) == w.st.name:
				var c := s.get_last_slide_collision()
				print("   TRACE %s f%d pos %s floor %s vel %s ziel %d %s Kontakt %s" % [w.st.name, w.frames, _v(s.global_position),
					s.is_on_floor(), _v(s.velocity), w.idx, _v(target), (_v(c.get_normal()) + " " + str(c.get_collider())) if c else "-"])
			if w.nav:
				# wie AIBrain: kein Fortschritt 0,75 s → Kletterstelle (Ziel ≥ 0,4 m höher) bzw. Wegpunkt überspringen
				if d.length() < w.best - 0.05:
					w.best = d.length()
					w.stall = 0
				else:
					w.stall += 1
				if w.stall > 45:
					w.stall = 0
					w.best = INF
					s.look_yaw = atan2(-d.normalized().x, -d.normalized().z)
					if target.y - s.global_position.y > 0.4 and s.try_climb():
						pass
					elif not last:
						w.idx += 1
						continue
			var dir := d.normalized()
			s.move_input = dir * (clampf(d.length() / 0.6, 0.35, 1.0) if last else 1.0)
			s.look_yaw = atan2(-dir.x, -dir.z)
		await get_tree().physics_frame
	await frames(20)


func _at(s: Soldier, p: Vector3) -> bool:
	return _near(s.global_position, p, 0.6, 0.3)


func _near(a: Vector3, b: Vector3, horiz: float, vert: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < horiz and absf(a.y - b.y) < vert


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
