extends "res://tests/test_gameplay.gd"
## B-028 Kontrollbilder der Original-Partikeleffekte (FENSTER, nicht headless):
##   tools\godot.cmd -- --mission=a2_erkundung --autoplay=shots_b028_particles [--ids=10,23,40,46,53,64,3,7]
## → test_output/b028/particle_<id>.png (je Effekt 0,4 s und 1,5 s nach dem Start)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func(): _finish())
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt = m.get("runtime")
	if rt and rt.in_cutscene:
		rt.end_cutscene()
	await frames(10)
	var ids := [10, 23, 40, 46, 53, 64, 3, 7, 108, 114]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = Array(a.substr(6).split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/b028"))
	var s: Soldier = m.squad.leader()
	var cam: Camera3D = get_viewport().get_camera_3d()
	for id in ids:
		var pos := s.global_position - s.global_basis.z * 6.0 + Vector3.UP * 0.5
		var n := OrigParticles.spawn(id, pos, m.dynamic_root)
		if cam:
			cam.look_at(pos + Vector3.UP, Vector3.UP)
		for t in [0.4, 1.5]:
			await get_tree().create_timer(t if t < 1.0 else t - 0.4).timeout
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://test_output/b028/particle_%d_%02d.png" % [id, int(t * 10)]))
		n.queue_free()
		await frames(5)
	check(true, "Partikelbilder geschrieben (%d Effekte)" % ids.size())
	_finish()
