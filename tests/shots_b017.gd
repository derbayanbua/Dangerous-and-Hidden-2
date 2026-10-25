extends "res://tests/test_gameplay.gd"
## B-017 Kontrollbilder (FENSTER, nicht headless): Türflügel zu/offen, Zaunfeld vor/nach dem Schneiden, Schnee am Haupteingang.
##   tools\godot.cmd --resolution 1280x720 -- --mission=af1_spaghetti_airport --autoplay=shots_b017
##   tools\godot.cmd --resolution 1280x720 -- --mission=no2_schwerttaenzer --autoplay=shots_b017
##   tools\godot.cmd --resolution 1280x720 -- --mission=a1_blizzard --autoplay=shots_b017
## → test_output/b017_<mission>_*.png  (Sammelaufruf: tools\shots_b017.ps1)

var _m: Mission
var _cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_finish)
	_run.call_deferred()


func _shot(tag: String, from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var p := "res://test_output/b017_%s_%s.png" % [Game.current_mission_id, tag]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(p))
	print("SHOT ", p)


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	_m = mission()
	var rt = _m.get("runtime")
	if rt:
		rt.auto_skip = true
		for i in 300:
			await get_tree().process_frame
			if rt.in_cutscene:
				rt.end_cutscene()
		rt.process_mode = Node.PROCESS_MODE_DISABLED
	isolate_enemies([])
	for h in [_m.get("hud")]:
		if h is CanvasItem or h is CanvasLayer:
			h.visible = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_m.add_child(_cam)
	_cam.current = true
	var it: OrigInteractive = _m.get("interactive")
	for k in it.controls:
		var c = it.controls[k]
		if c is OrigInteractive.OrigDoor and c.static_leaf:
			var box := OrigInteractive.world_aabb(c.frame)
			var ctr := box.get_center()
			var n: Vector3 = c.leaf_normal
			await _shot("%s_zu" % c.frame.name, ctr - n * 3.0 + Vector3.UP * 0.3, ctr)
			c.set_open(true)
			await get_tree().create_timer(2.0).timeout
			await _shot("%s_offen" % c.frame.name, ctr - n * 3.0 + Vector3.UP * 0.3, ctr)
	var shown := 0
	for k in it.controls:
		var f = it.controls[k]
		if f is OrigInteractive.OrigFence and shown < 2:
			shown += 1
			var p: Vector3 = f.global_position
			await _shot("%s_ganz" % k, p + Vector3(3.5, 1.0, 3.5), p)
			f.set_cut(true)
			await _shot("%s_geschnitten" % k, p + Vector3(3.5, 1.0, 3.5), p)
	if Game.current_mission_id == "a1_blizzard":
		await _shot("haupteingang_links", Vector3(64, 7, -16), Vector3(64, 4, -4))
	_finish()
