extends "res://tests/shots_graphics.gd"
## Fernsicht-Sonde (FENSTER, fix_af1_ferne): eigene Kamera springt an mehrere Punkte und fotografiert in 8 Richtungen.
##   tools\godot.cmd -- --mission=af1_spaghetti_airport --autoplay=probe_far_view [--levels=0,2,4] [--tag=vorher]
##   [--points=x,y,z;x,y,z]  (Standard: Spielerstart + 4 Punkte im Kartenrechteck auf 15 m Höhe)
##   [--dirs=8] [--pitch=2]
## → test_output/far/<mission>_<tag>_q<stufe>_p<n>_<grad>.png, Bericht far_<mission>_<tag>.txt
## Für jede Aufnahme: Strahl in Blickrichtung, getroffener Körper und Entfernung; dazu große Level-Meshes ohne Textur.

var _cam: Camera3D
var _lines: PackedStringArray = []


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if m == null:
		check(false, "Mission geladen")
		_finish()
		return
	await _wait_player_control(m)
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	var tag := String(Game.cli.get("tag", "probe"))
	var mid := String(Game.cli.get("mission", "mission"))
	var pts: Array = []
	if Game.cli.has("points"):
		for p in String(Game.cli["points"]).split(";"):
			var c := p.split(",")
			pts.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
	else:
		pts.append(s.global_position + Vector3(0, 1.7, 0))
		var box := _level_box(m)
		_lines.append("Level-AABB %s" % str(box))
		var c := box.get_center()
		for d in [Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, -0.3)]:
			var xz := c + Vector3(box.size.x * d.x, 0, box.size.z * d.z)
			var hit: Variant = _ray(Vector3(xz.x, box.end.y + 50, xz.z), Vector3(xz.x, box.position.y - 50, xz.z))
			if hit:                              # ohne Boden (außerhalb des Geländes) kein Messpunkt
				pts.append(Vector3(xz.x, hit.position.y + 15.0, xz.z))
	_cam = Camera3D.new()
	var vc := get_viewport().get_camera_3d()
	if vc:
		_cam.fov = vc.fov
		_cam.far = vc.far
		_cam.near = vc.near
		_cam.environment = vc.environment
		_cam.attributes = vc.attributes
		_lines.append("Spielkamera far %.0f near %.2f fov %.1f" % [vc.far, vc.near, vc.fov])
	m.add_child(_cam)
	_cam.current = true
	var env: Environment = get_viewport().world_3d.environment
	if env:
		_lines.append("Nebel %s Dichte %.4f Farbe %s, Hintergrund %d" % [env.fog_enabled, env.fog_density, env.fog_light_color,
			env.background_mode])
	_list_suspects(m)
	var dirs := int(Game.cli.get("dirs", "8"))
	var pitch := deg_to_rad(float(Game.cli.get("pitch", "2")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/far"))
	for q in String(Game.cli.get("levels", "0,2,4")).split(","):
		Settings.quality = int(q)
		Settings.apply()
		await seconds(1.5)
		for pi in pts.size():
			for di in dirs:
				var yaw := TAU * di / dirs
				_cam.global_position = pts[pi]
				_cam.global_basis = Basis.from_euler(Vector3(-pitch, yaw, 0))
				if m.get("sky_fx") and m.sky_fx:
					pass
				await seconds(0.35)
				await RenderingServer.frame_post_draw
				var fn := "%s_%s_q%s_p%d_%03d" % [mid, tag, q, pi, int(rad_to_deg(yaw))]
				get_viewport().get_texture().get_image().save_png("res://test_output/far/%s.png" % fn)
				var fwd := -_cam.global_basis.z
				var hit: Variant = _ray(_cam.global_position, _cam.global_position + fwd * 3000.0)
				_lines.append("%s pos %s  Strahl: %s" % [fn, str(pts[pi].snapped(Vector3.ONE * 0.1)),
					("%s @ %.0f m" % [String((hit.collider as Node).get_path()).get_slice("/", -1) if hit.collider else "?",
					_cam.global_position.distance_to(hit.position)]) if hit else "nichts"])
	var f := FileAccess.open("res://test_output/far_%s_%s_q%s.txt" % [mid, tag, String(Game.cli.get("levels", "0,2,4")).replace(",", "")],
		FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
	print("\n".join(_lines))
	check(true, "Fernsicht-Bilder erzeugt")
	_finish()


func _ray(a: Vector3, b: Vector3):
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return r if not r.is_empty() else null


func _level_box(m) -> AABB:
	var box := AABB()
	var first := true
	var root: Node = m.orig.root if m.get("orig") != null and m.orig.get("root") != null else m.static_root
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = n.global_transform * n.get_aabb()
		if b.size.length() > 3000.0:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


## Große Meshes (> 25 m) und alle Meshes mit Flächen ohne Albedo-Textur, nach Größe.
func _list_suspects(m) -> void:
	var root: Node = m.orig.root if m.get("orig") != null and m.orig.get("root") != null else m.static_root
	var rows: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		var s := maxf(b.size.x, maxf(b.size.y, b.size.z))
		var notex := 0
		var info := []
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			var t := ""
			if mat is BaseMaterial3D:
				t = "tex" if (mat as BaseMaterial3D).albedo_texture else "NOTEX %s" % (mat as BaseMaterial3D).albedo_color
				if (mat as BaseMaterial3D).albedo_texture == null:
					notex += 1
			elif mat == null:
				t = "NOMAT"
				notex += 1
			else:
				t = mat.get_class()
			info.append(t)
		if s > 25.0 or notex > 0:
			rows.append([s, "%6.0f m vis %5.0f %s %s %s" % [s, mi.visibility_range_end, "SICHTBAR" if mi.is_visible_in_tree() else "versteckt",
				String(root.get_path_to(mi)), ",".join(info)]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	_lines.append("Verdächtige Meshes (%d):" % rows.size())
	for r in rows.slice(0, 120):
		_lines.append("  " + r[1])
