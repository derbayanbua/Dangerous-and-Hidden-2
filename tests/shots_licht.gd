extends "res://tests/shots_graphics.gd"
## 0.10.1 Lampenlicht Vorher/Nachher (FENSTER). Eine Stufe je Lauf:
##   tools\godot.cmd -- --mission=a2_erkundung --autoplay=shots_licht --lamp_boost=0   (vorher)
##   tools\godot.cmd -- --mission=a2_erkundung --autoplay=shots_licht                  (nachher)
## Optional --q=<Grafikstufe> (Standard 2), --n=<Zahl Lampenbilder> (6).
## Kamera 4 m neben den stärksten Lampen (gebacken + Echtzeit, Positionen aus extra.json, unabhängig vom Schalter) →
## test_output/licht/<mission>_<vorher|nachher>_<i>.png; ARCTIC2 zusätzlich Gitterraum (_gitter.png) + <..>.txt.

var _cam: Camera3D
var _lines: PackedStringArray = []


func _ready() -> void:
	Game.cli["levels"] = String(Game.cli.get("q", "2"))
	if not Game.cli.has("level_sec"):
		Game.cli["level_sec"] = "900"
	super._ready()


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/licht"))
	var stage := "vorher" if String(Game.cli.get("lamp_boost", "1")) == "0" else "nachher"
	var mid := String(Game.cli.get("mission", "m"))
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 400.0
	m.add_child(_cam)
	_cam.current = true
	var rt: LsRuntime = m.get("runtime")
	if rt and rt.extras:
		_lines.append("Lampen: %s stats %s" % [str(rt.extras.lamp_stats), str(rt.extras.stats)])
	var lamps := _lamp_positions(m)
	var space := m.get_world_3d().direct_space_state
	var n := int(Game.cli.get("n", "6"))
	var k := 0
	var used: Array[Vector3] = []
	for lp in lamps:
		if k >= n:
			break
		var p: Vector3 = lp
		var dup := false
		for u in used:
			if u.distance_to(p) < 8.0:
				dup = true
		if dup:
			continue
		var eye := Vector3.INF
		for a in 8:
			var d := Vector3(cos(a * PI / 4.0), 0, sin(a * PI / 4.0))
			var cand := p + d * 4.0 + Vector3(0, -0.6, 0)
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, -0.6, 0), cand, 1))
			if r.is_empty():
				eye = cand
				break
		if eye == Vector3.INF:
			continue
		used.append(p)
		_cam.global_position = eye
		_cam.look_at(p + Vector3(0, -1.6, 0))
		await frames(20)
		await _snap_l("%s_%s_%d" % [mid, stage, k])
		_lines.append("%d: Lampe %s Kamera %s" % [k, str(p), str(eye)])
		k += 1
	var lvl: OrigLevel = m.get("orig")
	if lvl:
		for mi in lvl.root.find_children("*", "MeshInstance3D", true, false):
			if String(mi.get_path()).contains("m_bmmriz"):
				var b: AABB = mi.global_transform * mi.get_aabb()
				_cam.global_position = b.get_center() + Vector3(3.0, 2.2, 3.0)
				_cam.look_at(b.get_center())
				await frames(20)
				await _snap_l("%s_%s_gitter" % [mid, stage])
				break
	var f := FileAccess.open("res://test_output/licht/%s_%s.txt" % [mid, stage], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
	check(k > 0, "Lampenbilder aufgenommen", str(k))
	_finish()


func _lamp_positions(m) -> Array:
	var ex = LsRuntime._read_json(String(m.get("orig").mission_dir) + "/extra.json") if m.get("orig") else {}
	var arr: Array = []
	if typeof(ex) == TYPE_DICTIONARY:
		for l in ex.get("lights", []):
			var t := String(l.get("type", ""))
			if (t == "point" or t == "spot") and float(l.get("range", 0)) >= 3.0 and float(l.get("power", 0)) >= 0.1:
				arr.append([float(l["power"]) * float(l["range"]), Vector3(l["world_pos"][0], l["world_pos"][1], l["world_pos"][2])])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	return arr.map(func(e): return e[1])


func _snap_l(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/licht/%s.png" % name)
