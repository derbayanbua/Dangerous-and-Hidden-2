extends Node
## Bavaria – Integrationsaufnahmen (Fenster, nicht kopflos):
##   Kartenbild erzeugen:  tools\godot.cmd -- --mission=bavaria --autoplay=screenshots_bavaria_integration --render_map=1
##                         → assets/ui/mp_maps/bavaria.png (Draufsicht, Weltausschnitt = Bavaria.mp_map_rect())
##   Kontrollbilder:       tools\godot.cmd -- --autoplay=screenshots_bavaria_integration
##                         → test_output/bavaria_int_{overview,zone,bots,zonemap,loading}.png (Besetzung, Host + Bots)

const OUT := "res://test_output/bavaria_int_%s.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _wait_mission() -> Mission:
	var m: Mission = null
	while m == null or not m.is_node_ready():
		await get_tree().process_frame
		m = Game.current_mission()
	return m


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", OUT % name, " ", img.get_size())


func _run() -> void:
	if Game.cli.has("render_map"):
		await _render_map()
		get_tree().quit(0)
		return
	Net.local_name = "Integration"
	Net.local_team = 0
	Net.host({"name": "Bavaria Integration", "map": "bavaria_occupation", "mode": Net.Mode.OCCUPATION,
		"port": Net.PORT + 44, "max_players": 12, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0,
		"respawn_s": 5, "bots_per_team": 3, "password": "", "allow_vehicles": false})
	var m = await _wait_mission()
	var t0 := Time.get_ticks_msec()
	while not m.nav_ready and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	# Bots bewegen sich eine Weile (Zonenvorstoß), danach Aufnahmen
	await get_tree().create_timer(25.0).timeout
	var me: Soldier = Net._soldiers.get(1)
	if is_instance_valid(me):
		me.set_meta("protect_until", Time.get_ticks_msec() + 600000)
	m.controller.input_enabled = false
	var cam := Camera3D.new()
	cam.far = 2200.0
	m.add_child(cam)
	cam.current = true
	var hud = m.get_node_or_null("MpHud")
	if hud:
		hud.visible = false
	if m.get("hud"):
		m.hud.visible = false
	var c: Vector2 = (m.mp_map_rect() as Rect2).get_center()
	cam.fov = 55.0
	cam.global_position = Vector3(c.x + 70, 85, c.y + 70)
	cam.look_at(Vector3(c.x, 0, c.y))
	await _save("overview")
	var z: Vector3 = (m.mp_zones()[2]["xf"] as Transform3D).origin
	cam.fov = 65.0
	cam.global_position = z + Vector3(9, 3.0, 10)
	cam.look_at(z + Vector3(-3, 1.5, 0))
	await _save("zone")
	# Bots: Kamera hinter den ersten lebenden KI-Soldaten, Blick in Laufrichtung
	var bot: Soldier = null
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]) and Net._soldiers[id].alive:
			bot = Net._soldiers[id]
			break
	if bot:
		var fw := bot.forward()
		cam.global_position = bot.global_position - fw * 7.0 + Vector3.UP * 3.0
		cam.look_at(bot.global_position + fw * 6.0 + Vector3.UP * 1.0)
		await _save("bots")
	var lines: PackedStringArray = []
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if is_instance_valid(s):
			lines.append("%d team %d alive %s pos %s" % [int(id), s.team, str(s.alive), str(s.global_position.snapped(Vector3.ONE * 0.1))])
	print("SOLDATEN\n", "\n".join(lines))
	print("ZONEN ", Net.zone_owner)
	if hud:
		hud.visible = true
		hud.toggle_zone_map()
		await _save("zonemap")
		print("ZONEMAP panel ", hud._zone_panel.get_global_rect())
		hud.toggle_zone_map()
		hud.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var ls := LoadingScreen.new()
	layer.add_child(ls)
	ls.open("bavaria_occupation")
	ls.set_progress(0.6)
	await _save("loading")
	layer.queue_free()
	Net.leave(false)
	get_tree().quit(0)


func _render_map() -> void:
	var m = await _wait_mission()
	for i in 10:
		await get_tree().process_frame
	m.controller.input_enabled = false
	if m.get("hud"):
		m.hud.visible = false
	for s in m.actors_root.get_children():
		if s is Node3D:
			s.visible = false
	var r: Rect2 = m.mp_map_rect()
	get_window().size = Vector2i(1024, 1024)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = r.size.y
	cam.near = 1.0
	cam.far = 400.0
	m.add_child(cam)
	cam.global_position = Vector3(r.get_center().x, 160.0, r.get_center().y)
	# Bild oben = −Z (wie die Spawnzonen-Karte: x nach rechts, z nach unten)
	cam.look_at(Vector3(r.get_center().x, 0.0, r.get_center().y), Vector3.FORWARD)
	cam.current = true
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	if side != 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/mp_maps"))
	var p := ProjectSettings.globalize_path("res://assets/ui/mp_maps/bavaria.png")
	img.save_png(p)
	img.save_png(ProjectSettings.globalize_path(OUT % "map_render"))
	print("KARTENBILD ", p, " ", img.get_size(), " Welt ", r)
