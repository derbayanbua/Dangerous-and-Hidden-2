extends "res://tests/shots_graphics.gd"
## B-050 / AP-50a – Original-Himmel kamerafest (src/world/sky_backdrop.gd). FENSTER (Bilder), mehrere Missionen in EINEM Lauf:
##   tools\godot.cmd -- --autoplay=test_b050 [--missions=af1_spaghetti_airport,nw1_dampfleitung,bu1_ameisenhuegel,no2_schwerttaenzer]
##   [--q=2] [--shots=0]   (--shots=0: nur Prüfungen, auch headless)
## Prüft je Mission: Backdrop-Meshes vorhanden (Burma: keine) und alle mit Himmels-Shader (Tiefe an der Fernebene, ohne
## Nebel), keine Sichtweiten-Ausblendung/Zusammenfassung, keine Kollision, sky_fx ohne Rauschwolken/Wolkenschatten bei
## Backdrop; Bildlage unabhängig von der Kameraposition (Backdrop wandert mit). Bilder je Mission:
##   test_output/b050/<tag>_vorher_<blick>.png   (Stand fix_af1_ferne: Backdrop aus, Rauschwolken)
##   test_output/b050/<tag>_classic_<blick>.png / <tag>_neu_<blick>.png   (Original-Himmel, Sichtweite CLASSIC / NEU)
## Trupp unverwundbar, Gegner angehalten.

const SkyBackdrop := preload("res://src/world/sky_backdrop.gd")
const SkyPhoto := preload("res://src/world/sky_hdri.gd")
const DEFAULT_MISSIONS := "af1_spaghetti_airport,a1_blizzard,nw1_dampfleitung,bu1_ameisenhuegel,no2_schwerttaenzer"
const NO_BACKDROP := ["bu1_ameisenhuegel"]
var _cam: Camera3D
var _lines: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var n := String(Game.cli.get("missions", DEFAULT_MISSIONS)).split(",").size()
	var total := 420.0 * n + 120.0
	get_tree().create_timer(total, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs", "%.0f s" % total)
		_write_report()
		_finish())
	_run.call_deferred()


func _run() -> void:
	var shots := String(Game.cli.get("shots", "1")) != "0" and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/b050"))
	var first := true
	for mid in String(Game.cli.get("missions", DEFAULT_MISSIONS)).split(","):
		var old := mission()
		if not (first and Game.cli.get("mission", "") == mid):
			Game.cli["mission"] = mid
			Game.start_mission(mid)
		first = false
		var m: Mission = null
		for i in 6000:
			var c := mission()
			if c != null and c != old and is_instance_valid(c) and c.squad and c.squad.leader():
				m = c
				break
			await get_tree().process_frame
		if m == null:
			check(false, "%s geladen" % mid)
			continue
		_level_deadline = Time.get_ticks_msec() + 100000000
		await _wait_player_control(m)
		await _mission_checks(m, mid, shots)
	_write_report()
	_finish()


func _mission_checks(m: Mission, mid: String, shots: bool) -> void:
	var q := int(Game.cli.get("q", "2"))
	if Settings.quality != q:
		Settings.quality = q
		Settings.apply()
	for s in m.squad.members:            # Vorgabe: keine Läufe ohne Unverwundbarkeit
		s.max_health = 100000.0
		s.health = s.max_health
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var meshes: Array = get_tree().get_nodes_in_group(SkyBackdrop.GROUP).filter(func(x): return m.is_ancestor_of(x))
	var want := not NO_BACKDROP.has(mid)
	check((meshes.size() > 0) == want, "%s: Original-Himmel %s" % [mid, "vorhanden" if want else "fehlt wie im Original"],
		"%d Meshes" % meshes.size())
	var bad := 0
	var ranged := 0
	var bodies := 0
	for mi in meshes:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var mat = (mi as MeshInstance3D).get_surface_override_material(s)
			if not (mat is ShaderMaterial) or not String((mat as ShaderMaterial).shader.code).contains("fog_disabled"):
				bad += 1
		if (mi as GeometryInstance3D).visibility_range_end > 0.0:
			ranged += 1
		for c in (mi as Node).get_children():
			if c is CollisionObject3D and (c as CollisionObject3D).collision_layer != 0:
				bodies += 1
	if want:
		check(bad == 0, "%s: alle Himmelsflächen mit kamerafestem Shader" % mid, "%d ohne" % bad)
		check(ranged == 0, "%s: Himmel ohne Sichtweiten-Ausblendung" % mid, "%d" % ranged)
		check(bodies == 0, "%s: Himmel ohne Kollision" % mid, "%d" % bodies)
	var fx = m.sky_fx
	var special: bool = bool(fx.stats.get("backdrop", false)) or bool(fx.stats.get("photo", false))
	if want or fx.photo != null:
		check(special and fx.shadow_decal == null and not (m.env.sky.sky_material is ShaderMaterial),
			"%s: sky_fx ohne Rauschwolken/Wolkenschatten (Original-/Fotohimmel)" % mid, str(fx.stats))
	else:
		check(not special, "%s: prozeduraler Himmel (kein Backdrop, kein Foto)" % mid)
	if fx.photo != null:
		check(m.env.sky.sky_material is PanoramaSkyMaterial, "%s: Fotohimmel aktiv" % mid, str(SkyPhoto.stats))
	_lines.append("%s: Backdrop-Meshes %d, Statistik %s, Foto %s, Sichtweite %s" % [mid, meshes.size(),
		str(SkyBackdrop.stats), str(fx.stats), str(preload("res://src/world/view_distance.gd").current)])
	if not shots:
		return
	var s0: Soldier = m.squad.leader()
	var vc := get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	if vc:
		_cam.fov = vc.fov
		_cam.near = vc.near
	m.add_child(_cam)
	_cam.current = true
	var eye := s0.global_position + Vector3(0, 1.7, 0)
	var yaw: float = s0.look_yaw if "look_yaw" in s0 else 0.0
	var tag := mid.get_slice("_", 0)
	var photo = fx.photo
	# vorher: Stand fix_af1_ferne (Backdrop aus, Rauschwolken)
	fx.photo = null
	for mi in meshes:
		mi.visible = false
	fx.apply()
	await _views(m, eye, yaw, "%s_vorher" % tag)
	# Original-Himmel (Option --sky=orig)
	for mi in meshes:
		mi.visible = true
	fx.apply()
	if want:
		await _views(m, eye, yaw, "%s_orig" % tag)
	fx.photo = photo
	for mode in [["classic", "0"], ["neu", "1"]]:
		Game.cli["view_mode"] = mode[1]
		m._on_view_settings()
		fx.apply()
		await seconds(0.5)
		await _views(m, eye, yaw, "%s_%s" % [tag, mode[0]])
	Game.cli.erase("view_mode")
	m._on_view_settings()
	fx.apply()
	_cam.queue_free()


func _views(m: Mission, eye: Vector3, yaw: float, prefix: String) -> void:
	_cam.far = maxf(get_viewport().get_camera_3d().far if get_viewport().get_camera_3d() else 1200.0, 100.0)
	_cam.far = preload("res://src/world/view_distance.gd").camera_far()
	# freie Sicht: 15 m über dem Trupp (über Dächern/Felsen), Horizont (+4°) in zwei Richtungen und Himmel (+40°)
	for v in [["0", 0.0, 4.0], ["180", 180.0, 4.0], ["himmel", 90.0, 40.0]]:
		_cam.global_position = eye + Vector3(0, 15, 0)
		_cam.global_basis = Basis.from_euler(Vector3(deg_to_rad(float(v[2])), yaw + deg_to_rad(float(v[1])), 0))
		await seconds(0.6)
		await RenderingServer.frame_post_draw
		var p := "res://test_output/b050/%s_%s.png" % [prefix, v[0]]
		get_viewport().get_texture().get_image().save_png(p)
		_lines.append("Bild " + p.trim_prefix("res://"))


func _write_report() -> void:
	var f := FileAccess.open("res://test_output/b050/b050_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
	print("\n".join(_lines))
