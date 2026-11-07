extends "res://tests/shots_graphics.gd"
## B-041/B-042 Vorher/Nachher-Bilder Sichtweite + Messung (FENSTER, nicht headless). Eine Stufe je Lauf:
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_b041 --tag=arktis --b041=0          (vorher)
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_b041 --tag=arktis --view_mode=0     (CLASSIC)
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_b041 --tag=arktis --view_mode=1     (NEU)
## Optional --q=<Grafikstufe> (Standard 2), --target=<Knotenname> (z. B. Sniper_4 in no2_schwerttaenzer: Bilder aus
## Spielerposition und aus 45 m Abstand auf das Ziel), --fps_sec=4.
## → test_output/b041_<tag>_<stufe>_{0,90,180,270,hoch[,ziel,ziel_nah]}.png, b041_<tag>_<stufe>.txt (FPS/Speicher/Nebel)

var _cam: Camera3D
var _lines: PackedStringArray = []


func _ready() -> void:
	Game.cli["levels"] = String(Game.cli.get("q", "2"))
	if not Game.cli.has("level_sec"):
		Game.cli["level_sec"] = "900"      # Gesamtlimit = Laden 240 s + 900 s
	super._ready()


func _stage() -> String:
	if String(Game.cli.get("b041", "1")) == "0":
		return "vorher"
	return "neu" if String(Game.cli.get("view_mode", "0")) == "1" else "classic"


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
	_level_deadline = Time.get_ticks_msec() + 100000000
	await _wait_player_control(m)
	var q := int(Game.cli.get("q", "2"))
	if Settings.quality != q:
		Settings.quality = q
		Settings.apply()
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var s: Soldier = m.squad.leader()
	var tag := String(Game.cli.get("tag", String(Game.cli.get("mission", "m"))))
	var stage := _stage()
	var vc := get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	if vc:
		_cam.fov = vc.fov
		_cam.far = vc.far
		_cam.near = vc.near
	m.add_child(_cam)
	_cam.current = true
	var env: Environment = m.env
	var vd = preload("res://src/world/view_distance.gd")
	_lines.append("Mission %s, Stufe %s, Grafikstufe %d, Texturen %s" % [Game.cli.get("mission", "?"), stage, Settings.quality,
		str(Settings.texture_suffixes())])
	_lines.append("Sichtweite: %s" % str(vd.current))
	_lines.append("Nebel an=%s Modus=%d Beginn=%.1f Ende=%.1f Dichte=%.4f Farbe=%s Volumennebel=%s Kamera-far=%.0f" % [
		env.fog_enabled, env.fog_mode, env.fog_depth_begin, env.fog_depth_end, env.fog_density, env.fog_light_color,
		env.volumetric_fog_enabled, _cam.far])
	_lines.append("PerfTuning: %s" % str(PerfTuning.last))
	_lines.append("HQ-Texturen: %s" % str(OrigLevel.hq_stats))
	var eye := s.global_position + Vector3(0, 1.7, 0)
	var base_yaw := s.look_yaw if "look_yaw" in s else 0.0
	# Messung: Blick wie der Spieler, 0,5 s Einschwingen, dann fps_sec mitteln
	_cam.global_position = eye
	_cam.global_basis = Basis.from_euler(Vector3(deg_to_rad(-2.0), base_yaw, 0))
	await seconds(1.0)
	var fs := float(Game.cli.get("fps_sec", "4"))
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_frames_drawn()
	await seconds(fs)
	var fps := float(Engine.get_frames_drawn() - f0) / (float(Time.get_ticks_usec() - t0) / 1e6)
	_lines.append("MESSUNG fps=%.2f statisch=%.0f MB video=%.0f MB objekte=%d drawcalls=%d prim=%d" % [fps,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	for deg in [0, 90, 180, 270]:
		_cam.global_position = eye
		_cam.global_basis = Basis.from_euler(Vector3(deg_to_rad(-2.0), base_yaw + deg_to_rad(deg), 0))
		await seconds(0.6)
		await _snap("%s_%s_%d" % [tag, stage, deg])
	# erhöht (25 m) Richtung Kartenmitte
	var c := _level_center(m)
	_cam.global_position = eye + Vector3(0, 25, 0)
	_look(c if c.distance_to(eye) > 30.0 else eye + Vector3(0, 0, -100))
	await seconds(0.6)
	await _snap("%s_%s_hoch" % [tag, stage])
	if Game.cli.has("target"):
		var tn := String(Game.cli["target"])
		var t: Node3D = m.find_child(tn, true, false) as Node3D
		_lines.append("Ziel %s: %s" % [tn, str(t.global_position) if t else "nicht gefunden"])
		if t:
			var tp := t.global_position + Vector3(0, 1.2, 0)
			_cam.global_position = eye
			_look(tp)
			_cam.fov = 30.0
			await seconds(0.6)
			await _snap("%s_%s_ziel" % [tag, stage])
			_lines.append("Abstand Spieler–Ziel %.1f m" % eye.distance_to(tp))
			var away := (eye - tp)
			away.y = 0
			_cam.global_position = tp + away.normalized() * 45.0 + Vector3(0, 1.0, 0)
			_look(tp)
			await seconds(0.6)
			await _snap("%s_%s_ziel_nah" % [tag, stage])
	var f := FileAccess.open("res://test_output/b041_%s_%s.txt" % [tag, stage], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
	print("\n".join(_lines))
	check(true, "B-041-Bilder erzeugt")
	_finish()


func _look(p: Vector3) -> void:
	if _cam.global_position.distance_to(p) > 0.1:
		_cam.look_at(p, Vector3.UP)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/b041_%s.png" % name)
	_lines.append("Bild test_output/b041_%s.png" % name)


func _level_center(m) -> Vector3:
	var root: Node = m.orig.root if m.get("orig") != null and m.orig.get("root") != null else m.static_root
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = n.global_transform * n.get_aabb()
		if b.size.length() > 3000.0:
			continue
		box = b if first else box.merge(b)
		first = false
	return box.get_center()
