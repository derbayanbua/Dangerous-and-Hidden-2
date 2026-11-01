extends "res://tests/test_gameplay.gd"
## B-035 Fensterbilder (nicht headless): Leuchtturm vor/nach dem Einschalten, Lichtkegel in Drehung.
##   tools\godot.cmd -- --mission=no1_leuchtturm --autoplay=shots_b035   → test_output/b035/*.png


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/b035"))
	get_viewport().get_texture().get_image().save_png("res://test_output/b035/%s.png" % name)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime"):
			break
		await get_tree().process_frame
	await frames(10)
	var m := mission()
	var rt = m.runtime
	if rt.in_cutscene:
		rt.end_cutscene()
	var svet: Node3D = rt.find_frame("m_maj_svet01")
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.global_position = svet.global_position + Vector3(60, -10, 60)
	cam.look_at(svet.global_position)
	cam.current = true
	cam.far = 2000.0
	await frames(20)
	await _shot("leuchtturm_aus")
	(rt.vm_of.get(svet) as LsVM).signal_received(1)
	for i in 4:
		await get_tree().create_timer(2.5).timeout
		await _shot("leuchtturm_an_%d" % i)
	_finish()
