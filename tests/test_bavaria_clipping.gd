extends Node
## Automatische Clipping-Prüfung für Bavaria.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_clipping [--clip_list=1]
## Prüft mit echten Weltkoordinaten nach dem Kartenaufbau:
##  1. Vegetation (Bäume, Laub, Gras-MultiMesh) mit Fuß im Inneren eines Gebäudegrundrisses
##  2. Fremdobjekte, die eine Außenwand durchstoßen (beidseitig > 15 cm über die Wandebene)
##  3. Schwebende Außenobjekte (Unterkante > 12 cm ohne Auflage darunter)
##  4. Baumkronen, die tief in ein Gebäudevolumen (Wand/Dach) ragen
##  5. Haus 16: Geschosse, Keller, Treppen und Dach nach Plan
var failed := 0
var passed := 0
var m: Mission
var houses: Array = []   # {node, xf_inv, w, d, h, ruin}
var report: PackedStringArray = []

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		check(false, "Karte nach 300 s nicht bereit")
		_finish())

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame
	_collect_houses()
	check(houses.size() >= 30, "Gebäudevolumen erfasst: %d" % houses.size())
	_check_vegetation()
	_check_wall_penetration()
	_check_floating()
	_check_crowns()
	_check_house16()
	_check_trenches()
	await _check_furniture()
	_check_og_windows()
	_check_street_lamps()
	await _check_house_walk()
	var f := FileAccess.open("res://test_output/bavaria_clipping_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")
	_finish()

func _finish() -> void:
	print("ERGEBNIS test_bavaria_clipping: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _collect_houses() -> void:
	for b in get_tree().get_nodes_in_group("bavaria_buildings") + get_tree().get_nodes_in_group("bavaria_reference_extensions"):
		var n := b as Node3D
		var size: Vector2
		if n.has_meta("footprint_size"):
			size = n.get_meta("footprint_size")
		elif n.has_meta("reference_dimensions"):
			size = Vector2(n.get_meta("reference_dimensions")) * float(m.layout.meters_per_reference_pixel)
		else:
			continue
		var h := 0.0
		for vis in n.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (n.global_transform.affine_inverse() * vis.global_transform) * vis.get_aabb()
			h = maxf(h, a.end.y)
		houses.append({"node": n, "inv": n.global_transform.affine_inverse(), "w": size.x, "d": size.y, "h": h,
			"ruin": n.is_in_group("bavaria_ruins"), "name": String(n.name)})

func _house_at(p: Vector3, shrink := 0.2) -> Dictionary:
	for h in houses:
		var l: Vector3 = h.inv * p
		if absf(l.x) < h.w * 0.5 - shrink and absf(l.z) < h.d * 0.5 - shrink:
			return h
	return {}

func _is_building_part(n: Node) -> bool:
	var p := n
	while p:
		if p.is_in_group("bavaria_buildings") or p.is_in_group("bavaria_reference_extensions") or p.is_in_group("bavaria_furnished_rooms"):
			return true
		p = p.get_parent()
	return false

func _check_vegetation() -> void:
	var bad := 0
	for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots") + get_tree().get_nodes_in_group("bavaria_ground_foliage"):
		var r := root as Node3D
		if not r.visible:
			continue
		var foot: Vector3 = r.get_meta("ground_contact_point", r.global_position)
		var h := _house_at(foot, 0.15)
		if not h.is_empty() and not h.ruin:
			bad += 1
			report.append("VEG_IN_HOUSE %s in %s bei %s" % [r.name, h.name, foot])
	# Gras/Blumen als MultiMesh-Instanzen (Wiese, Säume, Wegränder).
	var grass_bad := 0
	var grass_total := 0
	for mmi in m.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.is_in_group("bavaria_tree_batches") or _is_building_part(mmi) or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in count:
			var p: Vector3 = mmi.global_transform * mm.get_instance_transform(i).origin
			if not m.inside_map(p):
				continue
			grass_total += 1
			var h := _house_at(p, 0.1)
			if not h.is_empty() and not h.ruin:
				grass_bad += 1
				if grass_bad <= 40:
					report.append("GRASS_IN_HOUSE %s[%d] in %s bei %s" % [mmi.name, i, h.name, p])
	check(bad == 0, "Keine Bäume/Laubgruppen im Inneren intakter Gebäude (%d)" % bad)
	check(grass_bad == 0, "Keine Gras-/Blumeninstanzen durch Hausböden (%d von %d)" % [grass_bad, grass_total])

func _world_aabb(vi: VisualInstance3D) -> AABB:
	return vi.global_transform * vi.get_aabb()

func _check_wall_penetration() -> void:
	var bad := 0
	var seen := {}
	for vi in m.find_children("*", "MeshInstance3D", true, false):
		if not vi.is_visible_in_tree() or _is_building_part(vi) or vi.mesh == null:
			continue
		var top := _top_object(vi)
		if seen.has(top) or top.is_in_group("bavaria_towers"):
			continue   # Antennenturm: Wandanker sind gewollt am Putz verschraubt
		var a := _world_aabb(vi)
		if a.size.x > 30 or a.size.z > 30 or a.size.y < 0.05:
			continue   # Boden, Wege, Himmel
		if not m.inside_map(a.get_center()):
			continue
		for h in houses:
			if h.ruin:
				continue
			# Objekt-Ecken in Hauskoordinaten
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in 8:
				# Echte (gedrehte) Meshbox statt weltachsparalleler Hülle
				var c: Vector3 = h.inv * (vi.global_transform * vi.get_aabb().get_endpoint(i))
				lo = lo.min(c)
				hi = hi.max(c)
			if lo.y > h.h or hi.y < 0.05:
				continue
			var hw: float = h.w * 0.5
			var hd: float = h.d * 0.5
			if hi.x < -hw or lo.x > hw or hi.z < -hd or lo.z > hd:
				continue
			# Durchstoßtiefe beidseitig der nächstgelegenen Wandebene
			var pen := 0.0
			for plane in [[lo.x, hi.x, -hw, lo.z, hi.z, hd], [lo.x, hi.x, hw, lo.z, hi.z, hd], [lo.z, hi.z, -hd, lo.x, hi.x, hw], [lo.z, hi.z, hd, lo.x, hi.x, hw]]:
				var a0: float = plane[0]
				var a1: float = plane[1]
				var wp: float = plane[2]
				if a0 < wp and a1 > wp and plane[4] > -plane[5] and plane[3] < plane[5]:
					pen = maxf(pen, minf(wp - a0, a1 - wp))
			if pen > 0.15:
				bad += 1
				seen[top] = true
				var info: Array = []
				for c in top.find_children("*", "MeshInstance3D", true, false).slice(0, 3):
					info.append("%s:%s" % [c.name, c.mesh.resource_name if c.mesh else ""])
				report.append("WALL_CLIP %s (%.2f m) in %s, AABB %s groups=%s meta=%s parts=%s xf=%s shapes=%s" % [m.get_path_to(top), pen, h.name, a, top.get_groups(), top.get_meta_list(), info,
					top.global_transform if top is Node3D else "", top.find_children("*", "CollisionShape3D", true, false).map(func(s): return s.shape)])
				break
	check(bad == 0, "Keine Fremdobjekte durch Außenwände intakter Gebäude (%d)" % bad)

func _top_object(n: Node) -> Node:
	var p := n
	while p.get_parent() and p.get_parent() != m.static_root and p.get_parent() != m.dynamic_root and p.get_parent() != m:
		p = p.get_parent()
	return p

func _check_floating() -> void:
	var space := m.get_world_3d().direct_space_state
	var bad := 0
	var seen := {}
	for g in ["bavaria_decorations", "bavaria_ground_beams", "bavaria_roof_supports"]:
		for n in get_tree().get_nodes_in_group(g):
			if seen.has(n) or not (n is Node3D) or not n.is_visible_in_tree():
				continue
			seen[n] = true
			var a := AABB()
			var found := false
			for vi in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
				var b := _world_aabb(vi)
				a = a.merge(b) if found else b
				found = true
			if not found or not m.inside_map(a.get_center()):
				continue
			if a.position.y < 0.12:
				continue
			# Auflage direkt unter der Unterkante suchen (Boden, Tisch, Stapel, Plattform)
			var supported := false
			for off in [Vector3.ZERO, Vector3(a.size.x * 0.3, 0, 0), Vector3(-a.size.x * 0.3, 0, 0), Vector3(0, 0, a.size.z * 0.3), Vector3(0, 0, -a.size.z * 0.3)]:
				var from: Vector3 = Vector3(a.get_center().x, a.position.y + 0.03, a.get_center().z) + off
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.2, 1)
				if not space.intersect_ray(q).is_empty():
					supported = true
					break
			if not supported:
				bad += 1
				report.append("FLOATING %s Unterkante %.2f m" % [m.get_path_to(n), a.position.y])
	check(bad == 0, "Keine schwebenden Außenobjekte ohne Auflage (%d)" % bad)

func _check_crowns() -> void:
	var bad := 0
	for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
		var r := root as Node3D
		if not r.visible or not m.inside_map(r.global_position):
			continue
		var foot: Vector3 = r.get_meta("ground_contact_point", r.global_position)
		for h in houses:
			if h.ruin:
				continue
			var l: Vector3 = h.inv * foot
			# Stamm näher als 1,2 m an einer Außenwand → Krone/Stamm schneidet sichtbar die Fassade/Traufe
			var dx: float = absf(l.x) - h.w * 0.5
			var dz: float = absf(l.z) - h.d * 0.5
			var dist := Vector2(maxf(dx, 0), maxf(dz, 0)).length() if (dx > 0 or dz > 0) else -minf(-dx, -dz)
			if dist < 1.2:
				bad += 1
				report.append("TRUNK_AT_WALL %s %.2f m von %s" % [r.name, dist, h.name])
	check(bad == 0, "Baumstämme mindestens 1,2 m von intakten Fassaden (%d)" % bad)

func _check_trenches() -> void:
	var trenches := get_tree().get_nodes_in_group("bavaria_trenches")
	check(trenches.size() == 2, "Zwei Schützengräben auf dem Feld (%d)" % trenches.size())
	var space := m.get_world_3d().direct_space_state
	var nav_map := m.get_world_3d().navigation_map
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	for t in trenches:
		var hole: PackedVector2Array = t.get_meta("hole")
		var fps: Array = t.get_meta("floor_points")
		var probe_points: Array = []
		for i in fps.size() - 1:
			probe_points.append((fps[i] + fps[i + 1]) * 0.5)   # Segmentmitten (Enden = Rampenfuß)
		probe_points.append_array(fps.slice(1, fps.size() - 1))
		for p in probe_points:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 1.0, 1))
			check(not hit.is_empty() and absf(hit.position.y - p.y) < 0.08, "%s: Grabensohle trägt bei %s (kein Durchfallen)" % [t.name, p])
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = capsule
			q.collision_mask = 1 | 16
			q.transform = Transform3D(Basis(), p + Vector3.UP * 0.9)
			check(space.intersect_shape(q).is_empty(), "%s: Soldatenkapsel steht frei im Graben bei %s" % [t.name, p])
		# Ein- und Ausstieg über beide Rampen, Navmesh durchgehend
		var exits: Array = t.get_meta("exits")
		var line: PackedVector2Array = t.get_meta("polyline")
		var deep: Vector3 = t.get_meta("floor_points")[1]
		for e in exits:
			var out_dir := (Vector2(e.x, e.z) - (line[1] if Vector2(e.x, e.z).distance_to(line[0]) < 0.1 else line[line.size() - 2])).normalized()
			var outside := Vector3(e.x + out_dir.x * 2.5, 0.05, e.z + out_dir.y * 2.5)
			var a := NavigationServer3D.map_get_path(nav_map, outside, deep, true)
			var b := NavigationServer3D.map_get_path(nav_map, deep, outside, true)
			check(a.size() > 1 and a[a.size() - 1].distance_to(deep) < 0.6 and b.size() > 1 and b[b.size() - 1].distance_to(outside) < 0.8,
				"%s: Einstieg und Ausstieg über Rampe bei %s (Navmesh)" % [t.name, e])
		# Aus dem Graben über die Brustwehr schießen (Augen-/Mündungshöhe auf dem Schützenauftritt)
		for ledge in t.get_meta("ledges"):
			var muzzle: Vector3 = ledge.stand + Vector3.UP * 1.40
			var target: Vector3 = muzzle + ledge.out * 25.0 + Vector3.UP * 0.2
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, target, 1))
			var free_dist: float = muzzle.distance_to(hit.position) if not hit.is_empty() else 25.0
			check(free_dist > 3.0, "%s: Schussfeld über die Brustwehr frei (%.1f m)" % [t.name, free_dist])
			var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(ledge.stand + Vector3.UP * 0.3, ledge.stand + Vector3.UP * 0.3 + ledge.out * 3.0, 1))
			check(not low.is_empty(), "%s: Brustwehr/Grabenwand deckt geduckten Schützen" % t.name)
		# Keine Gras-/Vegetationsinstanz schwebt über dem Grabenloch
		var floating := 0
		for mmi in m.find_children("*", "MultiMeshInstance3D", true, false):
			if mmi.multimesh == null:
				continue
			var mm: MultiMesh = mmi.multimesh
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for i in count:
				var p: Vector3 = mmi.global_transform * mm.get_instance_transform(i).origin
				if p.y > -1.0 and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), hole):
					floating += 1
		check(floating == 0, "%s: keine Vegetation über dem Grabenloch (%d)" % [t.name, floating])
	var covers := get_tree().get_nodes_in_group("bavaria_field_cover")
	check(covers.size() >= 8, "Zusätzliche Felddeckungen gesetzt (%d)" % covers.size())
	var kinds := {}
	for c in covers:
		kinds[c.get_meta("cover_kind")] = int(kinds.get(c.get_meta("cover_kind"), 0)) + 1
	check(int(kinds.get("berm", 0)) >= 2 and int(kinds.get("sandbag_nest", 0)) >= 3, "Erdwälle (%d) und Sandsacknester (%d) vollständig" % [kinds.get("berm", 0), kinds.get("sandbag_nest", 0)])
	var sb: StandardMaterial3D = m.lb.mat("sandbag")
	if ResourceLoader.exists("res://assets/maps/bavaria/facade/sandbag_albedo.png"):
		check(sb.albedo_texture != null and sb.normal_enabled and sb.normal_texture != null and sb.roughness_texture != null,
			"Sandsack-Material mit Sackmuster (Albedo/Normal/Rauheit)")
	else:
		check(sb != null, "Sandsack-Material ohne optionale Texturen (Ersatzmaterial)")
	report.append("FIELD covers=%s" % [covers.map(func(c): return "%s@%s" % [c.get_meta("cover_kind"), c.global_position])])

func _check_house16() -> void:
	var h: Node3D = m.static_root.get_node_or_null("haus_16")
	check(h != null, "Haus 16 vorhanden")
	if h == null:
		return
	check(h.get_meta("plan_storeys", []) == ["Keller", "EG", "OG", "Dach"], "Haus 16: Geschosse nach Schnitt (Keller/EG/OG/Dach)")
	var levels: Dictionary = h.get_meta("plan_levels", {})
	check(absf(float(levels.get("og_floor", 0)) - 3.18) < 0.05 and absf(float(levels.get("cellar_floor", 0)) + 2.40) < 0.05
		and absf(float(levels.get("cellar_clear", 0)) - 2.10) < 0.05, "Haus 16: Höhenkoten (Keller −2,40 m / lichte Höhe 2,10 m, OG +3,18 m)")
	check(absf(float(h.get_meta("roof_slope", 0.0)) - 0.431) < 0.01, "Haus 16: Dachneigung nach Schnitt (24,7°)")
	var cp: Array = h.get_meta("cellar_path", [])
	if cp.size() == 2:
		var nav_map := m.get_world_3d().navigation_map
		var path := NavigationServer3D.map_get_path(nav_map, cp[0], cp[1], true)
		var ok := path.size() > 1 and path[path.size() - 1].distance_to(cp[1]) < 0.6
		check(ok, "Haus 16: Keller per Navmesh über den Kellerhals erreichbar (%d Punkte)" % path.size())
	else:
		check(false, "Haus 16: Kellerweg-Metadaten")
	var space := m.get_world_3d().direct_space_state
	# Kellerboden und OG-Boden physisch vorhanden
	for probe in h.get_meta("plan_probes", []):
		var p: Vector3 = h.global_transform * Vector3(probe.point)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.8, 1)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and absf(hit.position.y - p.y) < 0.12, "Haus 16: begehbarer Boden %s (%s)" % [probe.name, "%.2f" % (hit.position.y if not hit.is_empty() else -99.0)])
	# Kellereinrichtung vollständig im Keller (unter EG-Platte, innerhalb der Wände)
	var cellar_bad := 0
	var cellar_n := 0
	for item in get_tree().get_nodes_in_group("bavaria_house16_cellar"):
		for vi in ([item] if item is MeshInstance3D else []) + item.find_children("*", "MeshInstance3D", true, false):
			cellar_n += 1
			for i in 8:
				var c: Vector3 = h.to_local(vi.global_transform * vi.get_aabb().get_endpoint(i))
				var size: Vector2 = h.get_meta("footprint_size")
				if c.y > -0.30 + 0.01 or c.y < -2.42 or absf(c.x) > size.x * 0.5 - 0.14 or absf(c.z) > size.y * 0.5 - 0.14:
					cellar_bad += 1
					report.append("CELLAR_CLIP %s %s" % [m.get_path_to(vi), c])
					break
	check(cellar_n > 10 and cellar_bad == 0, "Haus 16: Kellereinrichtung (%d Teile) ohne Durchdringung (%d)" % [cellar_n, cellar_bad])
	# Alle Plan-Räume per Navmesh von der Straße (vor der Haustür) erreichbar
	var nav_map2 := m.get_world_3d().navigation_map
	var start: Vector3 = h.to_global(Vector3(0, 0.05, float(h.get_meta("footprint_size").y) * 0.5 + 2.0))
	for room_name in h.get_meta("plan_room_points", {}):
		var target: Vector3 = h.to_global(h.get_meta("plan_room_points")[room_name])
		var p2 := NavigationServer3D.map_get_path(nav_map2, start, target, true)
		check(p2.size() > 1 and p2[p2.size() - 1].distance_to(target) < 0.7, "Haus 16: Raum %s erreichbar" % room_name)
	var rooms16 := get_tree().get_nodes_in_group("bavaria_furnished_rooms").filter(func(r): return r.get_meta("house") == "haus_16")
	check(rooms16.size() >= 8, "Haus 16: eingerichtete Plan-Räume (%d)" % rooms16.size())
	report.append("HOUSE16 rooms=%s" % [rooms16.map(func(r): return "%s:%d" % [r.name, r.get_child_count()])])
	report.append("HOUSE16 storeys=%s levels=%s" % [h.get_meta("plan_storeys", []), levels])

# --- 11/2026: Innenraum-Einrichtung (Bodenkontakt, Wände, Türen, Fenster, Überlappung, Ausrichtung) ---
const WALL_MOUNTED := ["GerahmtesLandschaftsbild"]
const ON_TOP := ["Krug", "Topf", "Glasflasche", "Emailletopf", "Vorratsflasche"]

func _furn_box(f: Node3D, inv: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in f.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var a: AABB = mi.get_aabb()
		for i in 8:
			var c: Vector3 = xf * a.get_endpoint(i)
			if first:
				out = AABB(c, Vector3.ZERO)
				first = false
			else:
				out = out.expand(c)
	return out

func _rect_hits(a: AABB, r: Rect2) -> bool:
	return Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(-0.03).intersects(r)

func _check_furniture() -> void:
	var space := m.get_world_3d().direct_space_state
	var items: Array = get_tree().get_nodes_in_group("bavaria_furniture")
	var own: Array[RID] = []
	for f in items:
		for b in (f as Node).find_children("*", "CollisionObject3D", true, false):
			own.append((b as CollisionObject3D).get_rid())
		if f is CollisionObject3D:
			own.append((f as CollisionObject3D).get_rid())
	var boxes := {}
	for f in items:
		var room := (f as Node).get_parent() as Node3D
		if room == null or not room.has_meta("room_rect"):
			continue
		var holder := room.get_parent() as Node3D
		boxes[f] = {"box": _furn_box(f, holder.global_transform.affine_inverse()), "room": room, "holder": holder}
	var bad := {"boden": 0, "wand": 0, "tuer": 0, "fenster": 0, "ueberlappung": 0, "ausrichtung": 0}
	for f in boxes:
		var e: Dictionary = boxes[f]
		var a: AABB = e.box
		var room: Node3D = e.room
		var holder: Node3D = e.holder
		var house := m.static_root.get_node_or_null(String(room.get_meta("house"))) as Node3D
		var fy := float(room.get_meta("floor_height", 0.06))
		var kind := String(f.get_meta("furniture_type", f.name))
		var wall := kind in WALL_MOUNTED or String(f.name).begins_with("Wandregal")
		var tag := "%s/%s/%s" % [room.get_meta("house"), room.name, f.name]
		# Bodenkontakt bzw. Auflage
		if not wall:
			var ok := a.position.y > fy - 0.05 and a.position.y < fy + 0.08
			if kind in ON_TOP or not ok:
				for g in boxes:
					if g == f or boxes[g].room != room:
						continue
					var b: AABB = boxes[g].box
					var c := a.get_center()
					if c.x > b.position.x and c.x < b.end.x and c.z > b.position.z and c.z < b.end.z and absf(a.position.y - b.end.y) < 0.08:
						ok = true
			if not ok:
				bad["boden"] += 1
				report.append("FURN_FLOOR %s unten %.3f (Boden %.2f)" % [tag, a.position.y, fy])
		# Ausrichtung: aufrecht, Drehung in 90°-Schritten
		var bas: Basis = (f as Node3D).global_basis.orthonormalized()
		var hb: Basis = holder.global_basis.orthonormalized()
		var rel := hb.inverse() * bas
		var yaw := atan2(rel.x.z, rel.x.x)
		var q := fposmod(yaw + 0.01, PI * 0.5)
		if rel.y.dot(Vector3.UP) < 0.995 or q > 0.05:
			bad["ausrichtung"] += 1
			report.append("FURN_ROT %s yaw %.1f°" % [tag, rad_to_deg(yaw)])
		# Wände/Decken des Hauses (echte Kollision), Möbel selbst ausgenommen
		var sh := BoxShape3D.new()
		sh.size = Vector3(maxf(a.size.x - 0.10, 0.02), maxf(a.size.y - 0.14, 0.02), maxf(a.size.z - 0.10, 0.02))
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = sh
		qp.transform = Transform3D(holder.global_basis, holder.global_transform * (a.get_center() + Vector3(0, 0.02, 0)))
		qp.collision_mask = 1
		qp.exclude = own
		for hit in space.intersect_shape(qp, 8):
			var col: Node = hit.collider
			if col == null:
				continue
			var p := col
			var part := false
			while p:
				if p == house or String(p.name).begins_with("CeilingCollision_") or p.is_in_group("bavaria_buildings"):
					part = true
					break
				p = p.get_parent()
			if part:
				bad["wand"] += 1
				report.append("FURN_WALL %s schneidet %s" % [tag, m.get_path_to(col)])
				break
		if house == null or wall or a.position.y > fy + 1.6:
			continue
		var hs: Vector2 = house.get_meta("footprint_size", Vector2.ZERO)
		var cor := float(house.get_meta("corridor_half_width", 1.0))
		# Türdurchgänge Flur ↔ Zimmer (Standardhäuser) und Haustüren
		var passes: Array = []
		if not house.has_meta("plan_rooms"):
			for dz in ([0.0] if hs.y < 6.4 else [-hs.y / 3.0, 0.0, hs.y / 3.0]):
				for sx in [-1.0, 1.0]:
					passes.append(Rect2(sx * cor - 0.55, dz - 0.9, 1.1, 1.8))
		for entry in house.get_meta("entry_points", []):
			var pt: Vector3 = entry.point
			var inw: Vector3 = pt - entry.normal * 1.2
			passes.append(Rect2(Vector2(pt.x, pt.z), Vector2.ZERO).expand(Vector2(inw.x, inw.z)).grow(0.6))
		for r in passes:
			if _rect_hits(a, r) and fy < 1.0:
				bad["tuer"] += 1
				report.append("FURN_DOOR %s in Durchgang %s" % [tag, r])
				break
		# Vor Fensterplätzen (EG): nichts über der Brüstung im Schussfeld
		if fy < 1.0 and a.end.y > fy + 0.95:
			for wnd in house.get_meta("shooting_windows", []):
				var r := Rect2(wnd.x - 0.5, (wnd.z - signf(wnd.z) * 0.7) if wnd.z > 0 else wnd.z, 1.0, 0.7)
				if _rect_hits(a, r):
					bad["fenster"] += 1
					report.append("FURN_WINDOW %s vor Fenster %s" % [tag, wnd])
					break
	# Überlappung großer Möbel untereinander (je Raum)
	var keys: Array = boxes.keys()
	for i in keys.size():
		var f: Node = keys[i]
		if not f.get_meta("large", false):
			continue
		for j in range(i + 1, keys.size()):
			var g: Node = keys[j]
			if not g.get_meta("large", false) or boxes[g].room != boxes[f].room:
				continue
			var a: AABB = boxes[f].box.grow(-0.03)
			var b: AABB = boxes[g].box.grow(-0.03)
			if a.intersects(b):
				bad["ueberlappung"] += 1
				report.append("FURN_OVERLAP %s/%s ↔ %s" % [boxes[f].room.name, f.name, g.name])
	report.append("FURN_TOTAL %d Objekte, Fehler %s" % [boxes.size(), bad])
	check(boxes.size() > 200, "Einrichtung erfasst (%d Objekte)" % boxes.size())
	for k in bad:
		check(int(bad[k]) == 0, "Einrichtung ohne Fehler: %s (%d)" % [k, bad[k]])

# --- 11/2026: Obergeschossfenster an allen intakten Wohnhäusern ---
func _check_og_windows() -> void:
	var missing: PackedStringArray = []
	var n := 0
	for b in get_tree().get_nodes_in_group("bavaria_buildings"):
		if b.is_in_group("bavaria_ruins") or String(b.get_meta("building_kind", "")) != "house":
			continue
		n += 1
		var wins: Array = b.get_meta("og_windows", [])
		var vis := b.get_node_or_null("CompleteBuildingVisual") as MeshInstance3D
		var glass := false
		if vis and vis.mesh:
			for s in vis.mesh.get_surface_count():
				var mat := vis.mesh.surface_get_material(s) as StandardMaterial3D
				if mat and (mat.has_meta("bavaria_og_glass") or mat.has_meta("bavaria_og_clear_glass")):
					glass = true
		if wins.size() < 2 or not glass:
			missing.append("%s(%d,%s)" % [b.name, wins.size(), glass])
	report.append("OG_WINDOWS %d Häuser, fehlend: %s" % [n, missing])
	check(n >= 12 and missing.is_empty(), "Sichtbare OG-Fenster an allen %d intakten Wohnhäusern %s" % [n, missing])

# --- Laternen: Mast frei von Gebäuden/Deko/Bäumen, Leuchtenkopf ragt in keine Wand, Boden trägt ---
func _check_street_lamps() -> void:
	var space := m.get_world_3d().direct_space_state
	var bad: PackedStringArray = []
	var lamps: Array = get_tree().get_nodes_in_group("bavaria_street_lamps")
	for l in lamps:
		var lamp := l as Node3D
		var kind := String(lamp.get_meta("kind"))
		if kind == "pole":
			var pos := lamp.global_position
			var query := PhysicsShapeQueryParameters3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.2
			cyl.height = 3.3
			query.shape = cyl
			query.transform = Transform3D(Basis(), pos + Vector3.UP * 1.85)
			query.collision_mask = 1 | 16
			query.exclude = [(lamp as CollisionObject3D).get_rid()]
			for hit in space.intersect_shape(query, 4):
				bad.append("%s↔%s" % [lamp.name, hit.collider.name])
			if _house_at(pos, -0.4).size() > 0:
				bad.append("%s im Gebäude" % lamp.name)
			var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 0.5, 1, [(lamp as CollisionObject3D).get_rid()]))
			if ground.is_empty() or absf(float(ground.position.y) - pos.y) > 0.08:
				bad.append("%s ohne Bodenkontakt" % lamp.name)
			var head: Vector3 = lamp.to_global(lamp.get_meta("head"))
			if not space.intersect_point(_point_query(head), 1).is_empty():
				bad.append("%s Leuchtenkopf in Geometrie" % lamp.name)
		else:
			# Wandleuchte: Halter an der Wand, Schirm frei davor
			var shade := lamp.to_global(Vector3(0, -0.05, 0.28))
			if not space.intersect_point(_point_query(shade), 1).is_empty():
				bad.append("%s Schirm in Wand" % lamp.name)
			var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(lamp.to_global(Vector3(0, 0, 0.1)), lamp.to_global(Vector3(0, 0, -0.5)), 1))
			if wall.is_empty():
				bad.append("%s ohne Wand dahinter" % lamp.name)
	report.append("STREET_LAMPS %d, Fehler: %s" % [lamps.size(), bad])
	check(lamps.size() >= 24 and bad.is_empty(), "Laternen/Wandleuchten ohne Clipping (%d): %s" % [lamps.size(), bad])

func _point_query(p: Vector3) -> PhysicsPointQueryParameters3D:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = 1
	return q

# --- 11/2026: Rundgang um alle intakten Gebäude (Augenhöhe, Kamera) ---
func _check_house_walk() -> void:
	var space := m.get_world_3d().direct_space_state
	var cam_gap := 0
	var protrude := 0
	var samples := 0
	for h in houses:
		if h.ruin:
			continue
		var node: Node3D = h.node
		var doors: Array = []
		for e in node.get_meta("entry_points", []):
			doors.append(e.point)
		for side in 4:
			var along := float(h.w if side < 2 else h.d)
			var k := 0.6
			while k < along - 0.6:
				var t := k - along * 0.5
				k += 1.0
				var wall_p: Vector3
				var out_n: Vector3
				match side:
					0: wall_p = Vector3(t, 0, h.d * 0.5); out_n = Vector3(0, 0, 1)
					1: wall_p = Vector3(t, 0, -h.d * 0.5); out_n = Vector3(0, 0, -1)
					2: wall_p = Vector3(h.w * 0.5, 0, t); out_n = Vector3(1, 0, 0)
					_: wall_p = Vector3(-h.w * 0.5, 0, t); out_n = Vector3(-1, 0, 0)
				var near_door := false
				for dp in doors:
					if (dp as Vector3).distance_to(wall_p) < 1.0:
						near_door = true
				var stand: Vector3 = node.to_global(wall_p + out_n * 0.7)
				if not m.inside_map(stand) or not _house_at(stand, -0.05).is_empty():
					continue   # Nachbarhaus/angebaut oder außerhalb
				samples += 1
				# Kamera: Wandkollision über/unter den Öffnungen (Federarm prallt ab, statt durchzuschauen)
				var kind := String(node.get_meta("building_kind", "house"))
				var gap_w := minf(4.0, maxf(0.4, float(h.w) - 0.6))
				var open_gate := kind != "house" and side < 2 and absf(t) < gap_w * 0.5 + 0.3
				for y in ([2.4, 4.6] if near_door else [0.5, 2.4, 4.6]):
					if y > float(h.h) - 0.6:
						continue
					if open_gate and y < minf(float(h.h) - 0.3, 3.2):
						continue   # offenes Scheunen-/Schuppentor (gewollte Öffnung)
					var og_open := false
					for ow in node.get_meta("og_open_windows", []):
						var ov: Vector3 = ow
						if (side < 2) and absf(ov.x - wall_p.x) < 0.6 and absf(ov.z - wall_p.z) < 0.5 and y > ov.y and y < ov.y + 1.4:
							og_open = true
					if og_open:
						continue   # echtes OG-Fenster (Glas, Bewegungssperre Ebene 5) – gewollte Sicht-/Schussöffnung
					var from: Vector3 = node.to_global(wall_p + out_n * 0.7 + Vector3.UP * y)
					var to: Vector3 = node.to_global(wall_p - out_n * 0.6 + Vector3.UP * y)
					var rq := PhysicsRayQueryParameters3D.create(from, to, 1)
					var hit := space.intersect_ray(rq)
					if hit.is_empty():
						cam_gap += 1
						if cam_gap <= 30:
							report.append("CAM_NO_WALL %s Seite %d bei %.1f m, Höhe %.1f" % [h.name, side, t, y])
				# Herausragende Bauteile im Gehbereich (Kopfhöhe 0,3–1,9 m) 0,7 m vor der Wand
				var cap := CapsuleShape3D.new()
				cap.radius = 0.28
				cap.height = 1.6
				var qp := PhysicsShapeQueryParameters3D.new()
				qp.shape = cap
				qp.transform = Transform3D(Basis(), stand + Vector3.UP * 1.1)
				qp.collision_mask = 1
				for hit in space.intersect_shape(qp, 4):
					var col: Node = hit.collider
					var p := col
					while p and p != node:
						p = p.get_parent()
					if p == node:
						protrude += 1
						if protrude <= 30:
							report.append("PROTRUDE %s Seite %d bei %.1f m: %s" % [h.name, side, t, col.name])
						break
		await get_tree().process_frame
	report.append("WALK %d Standpunkte, Kamera-Lücken %d, herausragend %d" % [samples, cam_gap, protrude])
	check(samples > 150, "Rundgang um alle intakten Gebäude (%d Standpunkte)" % samples)
	check(cam_gap == 0, "Kamera-/Wandkollision geschlossen an allen Fassaden (%d Lücken)" % cam_gap)
	check(protrude == 0, "Keine herausragenden Gebäudeteile im Gehbereich (%d)" % protrude)