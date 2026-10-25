extends "res://tests/test_gameplay.gd"
## Arctic 1: Durchfallen und Durch-Wände-Schauen (Fehlermeldung Auftraggeber 24.10.2026).
##  1. Fall-Raster: alle 3 m ein Strahl gegen die ORIGINAL-Kollisionsflächen (tree.klz → surface.bin, SurfaceMap) und
##     gegen die Spielphysik (Ebene 1). Wo das Original eine begehbare Fläche hat, muss die Physik dort einen Boden haben
##     (±0,5 m). Wasserflächen ausgenommen.
##  2. Bewegungsprobe: Soldat an Rasterpunkten absetzen, 2 s in eine Richtung laufen → darf nicht unter die
##     Original-Bodenfläche fallen.
##  3. Kamera-Wand-Proben: Soldat mit dem Rücken an Wänden (stehend, hockend, lehnend, 1. Person); zwischen Figur,
##     Kamera-Drehpunkt und Kamera darf keine sichtbare Levelgeometrie liegen (eigene Sichtkörper auf Ebene 20,
##     beidseitig), die Kamera nicht in Geometrie stecken.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_a1_collision [--step=3] [--probes=150]
##       [--cam_probes=120]   Bericht test_output/a1_collision_report.txt

const VIS_LAYER := 1 << 19     ## sichtbare, feste Levelgeometrie (Testkörper)
const DIAG_LAYER := 1 << 18    ## übrige Meshes (versteckt, Laub/Alpha, Wasser) – nur Diagnose
var report: Array[String] = []
var nvis := 0
var sm: SurfaceMap


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().orig:
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and m.orig != null, "Arctic 1 mit Originallevel geladen")
	sm = SurfaceMap.load_file(m.orig.mission_dir + "/surface.bin")
	check(sm != null and sm.count > 1000, "Original-Kollisionsflächen (surface.bin)", str(sm.count if sm else 0))
	if sm == null:
		_finish()
		return
	print("Kollision: ", m.orig.stats)
	# Skripte, Gegner, Kameraden, Fahrzeuge anhalten (sonst beendet das Missionsskript den Einsatz während der Proben)
	var lead: Soldier = m.squad.leader()
	var far := Vector3(5000, -900, 5000)
	for so in get_tree().get_nodes_in_group("soldiers"):
		if so == lead:
			continue
		for c in so.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
		(so as Node3D).global_position = far
		so.process_mode = Node.PROCESS_MODE_DISABLED
		far.x += 3.0
	if m.get("runtime") != null and is_instance_valid(m.get("runtime")):
		(m.get("runtime") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for n in m.dynamic_root.get_children():
		if n is VehicleBody3D or n is RigidBody3D:
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await frames(10)
	nvis = _add_visual_bodies(m)
	await frames(3)
	_fall_grid(m)
	_write()
	if not Game.cli.has("skip_move"):
		await _move_probe(m)
		_write()
	await _camera_probes(m)
	_write()
	_finish()


func _write() -> void:
	var f := FileAccess.open("res://test_output/a1_collision_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")


## Testsoldat: unverwundbar (Sturzschaden beim Durchfallen tötet sonst den Anführer)
func _probe_soldier(m: Mission) -> Soldier:
	var s: Soldier = m.squad.leader()
	s.max_health = 1e9
	s.health = 1e9
	return s


# --- 1. Fall-Raster ------------------------------------------------------------------------------------------

## Begehbare Original-Flächen (|n.y| > 0,5) unter (x, z): Höhen absteigend
func klz_floors(x: float, z: float) -> Array:
	var out: Array = []
	var lst: PackedInt32Array = sm.grid.get(Vector2i(int(floor(x / SurfaceMap.CELL)), int(floor(z / SurfaceMap.CELL))), PackedInt32Array())
	for k in lst:
		var n := sm.normals[k]
		if absf(n.y) < 0.5:
			continue
		var a := sm.tris[k * 3]
		if not SurfaceMap._inside_xz(x, z, a, sm.tris[k * 3 + 1], sm.tris[k * 3 + 2]):
			continue
		out.append(a.y - (n.x * (x - a.x) + n.z * (z - a.z)) / n.y)
	out.sort()
	out.reverse()
	return out


func _bounds() -> AABB:
	var b := AABB()
	var first := true
	for key in sm.grid:
		var p := Vector3(key.x * SurfaceMap.CELL, 0, key.y * SurfaceMap.CELL)
		if first:
			b = AABB(p, Vector3.ZERO)
			first = false
		else:
			b = b.expand(p)
	return b


func _in_water(m: Mission, p: Vector3) -> bool:
	for w in m.orig.water:
		var wb: AABB = w
		if p.x >= wb.position.x and p.x <= wb.end.x and p.z >= wb.position.z and p.z <= wb.end.z and p.y <= wb.end.y + 0.3:
			return true
	return false


func _ray(from: Vector3, to: Vector3, mask := 1, back := true) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.hit_back_faces = back
	q.collide_with_areas = false
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)


var floor_pts: Array[Vector3] = []


func _fall_grid(m: Mission) -> void:
	var step := float(Game.cli.get("step", "3"))
	var b := _bounds()
	var tested := 0
	var holes: Array[Vector3] = []
	var x := b.position.x
	while x <= b.end.x:
		var z := b.position.z
		while z <= b.end.z:
			var fl := klz_floors(x, z)
			for y in fl:
				var p := Vector3(x, y, z)
				if _in_water(m, p):
					continue
				tested += 1
				# Physikboden höchstens 0,5 m über/unter der Originalfläche (von 0,5 m darüber senkrecht nach unten)
				var h := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.5)
				if h.is_empty():
					holes.append(p)
				elif fl[0] == y and absf(float(y) - h.position.y) < 0.6:
					floor_pts.append(Vector3(x, h.position.y, z))
			z += step
		x += step
	report.append("## Fall-Raster (%.0f m, Bereich %s)" % [step, b])
	report.append("geprüfte Originalflächen-Punkte: %d, ohne Physikboden: %d" % [tested, holes.size()])
	var by_mesh := {}
	for hp in holes:
		var who := "kein Mesh"
		for mask in [VIS_LAYER, DIAG_LAYER]:
			var h := _ray(hp + Vector3.UP * 0.5, hp + Vector3.DOWN * 0.5, mask)
			if not h.is_empty():
				var bd := h.collider as StaticBody3D
				var csn: Node = bd.shape_owner_get_owner(bd.shape_find_owner(int(h.shape)))
				var mi: Node = csn.get_meta("mesh")
				var obj := mi.get_parent()
				var flags: String = "sichtbar" if mask == VIS_LAYER else ("versteckt" if not (mi as Node3D).is_visible_in_tree() else "Alpha/Wasser")
				who = "%s/%s [%s]" % [obj.name, mi.name, flags]
				break
		by_mesh[who] = int(by_mesh.get(who, 0)) + 1
		if by_mesh[who] <= 3:
			report.append("  Loch %.1f %.2f %.1f  %s" % [hp.x, hp.y, hp.z, who])
	report.append("## Löcher je Mesh")
	var keys := by_mesh.keys()
	keys.sort_custom(func(ka, kb): return by_mesh[ka] > by_mesh[kb])
	for k in keys:
		report.append("  %4d  %s" % [by_mesh[k], k])
	check(tested > 1000, "Fall-Raster: Originalflächen geprüft", str(tested))
	check(holes.is_empty(), "Fall-Raster: überall, wo das Original Boden hat, gibt es Physikboden",
		"%d Löcher (Bericht a1_collision_report.txt)" % holes.size())


# --- 2. Bewegungsprobe -----------------------------------------------------------------------------------------

## Spielbereich: Hülle der Grenzwände BORDER.Border_* (scene2.bin versteckt, tree.klz-Flächen) – außerhalb liegt nur
## Kulissengelände, das man im Original nicht betreten kann (Startpunkte dort ergeben falsche „Stürze“ über den Rand).
func _play_area(m: Mission) -> AABB:
	var b: Node3D = m.orig.nodes.get("BORDER")
	var out := AABB()
	if b == null:
		return out
	var first := true
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out.grow(-1.0) if not first else out


func _move_probe(m: Mission) -> void:
	var s: Soldier = _probe_soldier(m)
	var n := int(Game.cli.get("probes", "150"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var fell: Array[String] = []
	var edge: Array[String] = []
	var done := 0
	if floor_pts.is_empty():
		check(false, "Bewegungsprobe: Startpunkte")
		return
	var play := _play_area(m)
	report.append("Spielbereich (Hülle der versteckten Original-Grenze BORDER): %s" % play)
	for i in n * 4:
		if done >= n:
			break
		var p := floor_pts[rng.randi_range(0, floor_pts.size() - 1)]
		if play.size != Vector3.ZERO and not (p.x > play.position.x and p.x < play.end.x and p.z > play.position.z and p.z < play.end.z):
			continue
		# Kopffreiheit (sonst steckt der Soldat in einer Decke)
		if not _ray(p + Vector3.UP * 0.1, p + Vector3.UP * 1.9).is_empty():
			continue
		var ang := rng.randf() * TAU
		var dir := Vector3(sin(ang), 0, cos(ang))
		s.health = 1e9
		s.global_position = p + Vector3.UP * 0.05
		s.velocity = Vector3.ZERO
		s.look_yaw = atan2(-dir.x, -dir.z)
		s.move_input = dir
		var lowest := p.y
		for k in 120:
			await get_tree().physics_frame
			lowest = minf(lowest, s.global_position.y)
		s.move_input = Vector3.ZERO
		done += 1
		var q := s.global_position
		var fl := klz_floors(q.x, q.z)
		# unter die Karte = unter der untersten Originalfläche an dieser Stelle, oder kein Boden mehr (Sturz ins Leere);
		# außerhalb der Klz-Flächen auf sichtbarem Gelände gelandet = Kartenrand verlassen (gesondert berichtet)
		var void_fall := _ray(q + Vector3.UP * 0.5, q + Vector3.DOWN * 60.0).is_empty()
		if _in_water(m, q):
			pass
		elif void_fall or (not fl.is_empty() and q.y < float(fl[-1]) - 1.0):
			fell.append("Start %s Richtung %.0f° -> %s (Originalboden %s)" % [p, rad_to_deg(ang), q, fl])
		elif fl.is_empty() and q.y < p.y - 3.0:
			edge.append("Start %s Richtung %.0f° -> %s (keine Originalfläche, Physikboden vorhanden)" % [p, rad_to_deg(ang), q])
	report.append("## Bewegungsprobe: %d Läufe, %d unter die Karte, %d über den Rand der Originalflächen" % [done, fell.size(),
		edge.size()])
	for l in fell:
		report.append("  unter Karte: " + l)
	for l in edge:
		report.append("  Rand: " + l)
	check(done > 40, "Bewegungsprobe: Läufe", str(done))
	check(fell.is_empty(), "Bewegungsprobe: niemand fällt unter die Originalböden", "%d gefallen" % fell.size())


# --- 3. Kamera an Wänden -----------------------------------------------------------------------------------------

func _add_visual_bodies(m: Mission) -> int:
	# zwei Körper mit vielen Formen (je Mesh ein eigener Körper sprengt Jolts Körpergrenze 10240)
	var c := 0
	var bodies := {}
	for layer in [VIS_LAYER, DIAG_LAYER]:
		var body := StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		m.add_child(body)
		bodies[layer] = body
	for mi in m.orig.root.find_children("*", "MeshInstance3D", true, false):
		var v := mi as MeshInstance3D
		if v.mesh == null or OrigLevel._in_backdrop(v) or not OrigLevel._has_area(v.mesh):
			continue
		var solid: bool = v.is_visible_in_tree() and not m.orig._is_foliage(v) and not OrigLevel._is_water(v)
		var cs := CollisionShape3D.new()
		var sh := v.mesh.create_trimesh_shape()
		sh.backface_collision = true
		cs.shape = sh
		cs.set_meta("mesh", v)
		(bodies[VIS_LAYER if solid else DIAG_LAYER] as StaticBody3D).add_child(cs)
		cs.global_transform = v.global_transform
		if solid:
			c += 1
	return c


func _camera_probes(m: Mission) -> void:
	var nb := nvis
	var s: Soldier = _probe_soldier(m)
	var rig: CameraRig = m.rig
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var want := int(Game.cli.get("cam_probes", "60"))
	var cases: Array = []
	var tries := 0
	var nmiss := 0
	var nflat := 0
	var nback := 0
	while cases.size() < want and tries < 300000 and not floor_pts.is_empty():
		tries += 1
		var p := floor_pts[rng.randi_range(0, floor_pts.size() - 1)]
		var a := rng.randf() * TAU
		var d := Vector3(sin(a), 0, cos(a))
		var h := _ray(p + Vector3.UP * 1.4, p + Vector3.UP * 1.4 + d * 12.0, VIS_LAYER)
		if h.is_empty():
			nmiss += 1
			continue
		if absf(h.normal.y) > 0.3:
			nflat += 1
			continue
		var nrm: Vector3 = h.normal
		if nrm.dot(d) > 0.0:
			nback += 1
			continue      # Rückseite getroffen (Punkt steckt in einem Körper)
		cases.append([p, Vector3(nrm.x, 0, nrm.z).normalized(), h.position])
	var poses := [["stehend", Soldier.Stance.STAND, 0.0, false], ["hockend", Soldier.Stance.CROUCH, 0.0, false],
		["lehnt links", Soldier.Stance.STAND, -1.0, false], ["lehnt rechts", Soldier.Stance.STAND, 1.0, false],
		["1. Person", Soldier.Stance.STAND, 0.0, true]]
	var bad: Array[String] = []
	var total := 0
	var bad_by := {}
	for c in cases:
		var wall_n: Vector3 = c[1]
		var hp: Vector3 = c[2]
		var foot := Vector3(hp.x, c[0].y, hp.z) + wall_n * 0.42
		var fh := _ray(foot + Vector3.UP * 1.0, foot + Vector3.DOWN * 1.0)
		if fh.is_empty():
			continue
		foot.y = fh.position.y
		for pose in poses:
			for facing in ["Rücken zur Wand", "seitlich"]:
				var fwd: Vector3 = wall_n if facing == "Rücken zur Wand" else wall_n.cross(Vector3.UP)
				s.global_position = foot + Vector3.UP * 0.05
				s.velocity = Vector3.ZERO
				s.move_input = Vector3.ZERO
				s.stance_request = pose[1]
				s.lean = pose[2]
				s.look_yaw = atan2(-fwd.x, -fwd.z)
				s.look_pitch = -0.15
				if (rig.mode == CameraRig.Mode.FIRST) != pose[3]:
					rig.toggle_mode()
				for k in 40:
					await get_tree().physics_frame
				await get_tree().process_frame
				await get_tree().process_frame
				total += 1
				var cam := rig.camera.global_position
				var body: Vector3 = s.global_position + Vector3.UP * (0.5 if pose[1] == Soldier.Stance.STAND else 0.35)
				var piv: Vector3 = rig._pivot.global_position
				var why := ""
				if not _ray(body, piv, VIS_LAYER).is_empty():
					why = "Drehpunkt hinter Geometrie"
				elif not _ray(piv, cam, VIS_LAYER).is_empty():
					why = "Kamera hinter Geometrie"
				else:
					# Nahebene: die 4 Ecken der Nahebene dürfen nicht hinter Geometrie liegen
					var cb := rig.camera.global_transform.basis
					var hh := tan(deg_to_rad(rig.camera.fov) * 0.5) * rig.camera.near
					var ww := hh * 16.0 / 9.0
					for sx in [-1.0, 1.0]:
						for sy in [-1.0, 1.0]:
							var corner: Vector3 = cam + cb * Vector3(sx * ww, sy * hh, -rig.camera.near)
							if why == "" and not _ray(piv, corner + (corner - piv).normalized() * 0.01, VIS_LAYER).is_empty():
								why = "Nahebene schneidet Geometrie"
				if why != "":
					var key := "%s/%s" % [pose[0], facing]
					bad_by[key] = int(bad_by.get(key, 0)) + 1
					bad.append("%s, %s, %s: Fuß %s Wand-n %s Kamera %s Abstand %.2f" % [why, pose[0], facing, foot, wall_n, cam,
						cam.distance_to(piv)])
	s.lean = 0.0
	s.stance_request = Soldier.Stance.STAND
	if rig.mode == CameraRig.Mode.FIRST:
		rig.toggle_mode()
	report.append("## Kamera-Wand-Proben: %d Sichtkörper, %d Wandstellen, %d Proben, %d mit Blick durch Geometrie" % [nb, cases.size(),
		total, bad.size()])
	report.append("  Suche: %d Versuche, %d ohne Treffer, %d flach, %d Rückseite, %d Startpunkte" % [tries, nmiss, nflat, nback,
		floor_pts.size()])
	report.append("  je Haltung: %s" % bad_by)
	for l in bad.slice(0, 300):
		report.append("  " + l)
	check(cases.size() >= want / 2, "Kamera-Wand-Proben: Wandstellen gefunden", str(cases.size()))
	check(bad.is_empty(), "Kamera blickt an Wänden nicht durch Geometrie", "%d von %d (%s)" % [bad.size(), total, bad_by])
