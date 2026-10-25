extends "res://tests/test_gameplay.gd"
## B-013 Kontrollbilder Himmel/Wolken/Explosionen je Grafikstufe (FENSTER, nicht headless) + grobe Bildrate.
## Je Klimazone eine Mission wählen, z. B.:
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_graphics      (gemäßigt, Dämmerung)
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_graphics        (Schnee)
##   tools\godot.cmd -- --mission=af1_spaghetti_airport --autoplay=shots_graphics   (Wüste)
##   tools\godot.cmd -- --mission=bu1_ameisenhuegel --autoplay=shots_graphics  (Dschungel)
## Optional --levels=0,2,4 (Standard), --fps_sec=3.
## → test_output/graphics/<mission>_q<stufe>_{sky,horizon,expl_0.1,expl_0.5,expl_2}.png, graphics_fps_<mission>.txt


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/graphics"))
	var mid := String(Game.cli.get("mission", "mission"))
	get_viewport().get_texture().get_image().save_png("res://test_output/graphics/%s_%s.png" % [mid, name])
	print("Bild: graphics/%s_%s.png" % [mid, name])


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
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	var keep_q: int = Settings.quality
	var levels: Array = []
	for t in String(Game.cli.get("levels", "0,2,4")).split(","):
		levels.append(int(t))
	var fps_sec := float(Game.cli.get("fps_sec", "3"))
	var report: PackedStringArray = ["Mission %s, Klima %s" % [Game.cli.get("mission", "?"),
		m.sky_fx.climate if m.sky_fx else "-"]]
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	for q in levels:
		Settings.quality = q
		Settings.apply()
		await seconds(2.0)
		s.look_pitch = deg_to_rad(35.0)
		await seconds(0.8)
		await _shot("q%d_sky" % q)
		s.look_pitch = deg_to_rad(4.0)
		await seconds(0.8)
		await _shot("q%d_horizon" % q)
		# Bildrate ohne Explosion
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await seconds(fps_sec)
		var fps := float(Engine.get_frames_drawn() - f0) / maxf((Time.get_ticks_msec() - t0) / 1000.0, 0.001)
		Effects.explosion(s.global_position + fwd * 14.0, 5.0)
		await seconds(0.1)
		await _shot("q%d_expl_0.1" % q)
		f0 = Engine.get_frames_drawn()
		t0 = Time.get_ticks_msec()
		await seconds(0.4)
		await _shot("q%d_expl_0.5" % q)
		await seconds(1.5)
		var fps_ex := float(Engine.get_frames_drawn() - f0) / maxf((Time.get_ticks_msec() - t0) / 1000.0, 0.001)
		await _shot("q%d_expl_2" % q)
		report.append("%-9s  Bildrate ruhig %.1f  mit Explosion %.1f" % [Settings.QUALITY_NAMES[q], fps, fps_ex])
		await seconds(6.0)
	var f := FileAccess.open("res://test_output/graphics_fps_%s.txt" % Game.cli.get("mission", "x"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")
	print("\n".join(report))
	Settings.quality = keep_q
	Settings.apply()
	check(true, "Kontrollbilder erzeugt")
	_finish()
