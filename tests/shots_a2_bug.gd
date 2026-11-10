extends "res://tests/test_gameplay.gd"
## Kontrollbilder Arktis-2-Meldung „schwebendes Gitter mit Kiste“ (Fenster):
##   tools\godot.cmd -- --mission=a2_erkundung --autoplay=shots_a2_bug --tag=vorher|nachher
## Freie Kamera auf k_vozic03/04 (Kranwagen unter P1JER109) und die Kranplatten P1JER78/79 → test_output/a2_bug_<tag>_*.png

const VIEWS := [
	["vozic04", Vector3(-1.5, -4.2, -59.5), Vector3(-4.9, -6.8, -57.1)],
	["vozic03", Vector3(2.5, -4.6, -50.5), Vector3(-0.7, -6.9, -47.8)],
	["kran", Vector3(6.0, -4.0, -56.0), Vector3(1.5, -6.6, -48.5)],
]


func _run() -> void:
	for i in 3600:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime") and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	var me: Soldier = m.squad.leader()
	me.max_health = 1e9
	me.health = 1e9
	me.set_meta("protect_until", 1e12)
	isolate_enemies([])
	var hud := m.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 200.0
	m.add_child(cam)
	cam.current = true
	var tag := String(Game.cli.get("tag", "x"))
	for i in 20:   # Intro kann verzögert starten → wiederholt überspringen
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
		await seconds(0.5)
	var views: Array = VIEWS
	# --views=name:x,y,z:tx,ty,tz;…  (Kamera, Blickziel) überschreibt die festen Ansichten
	var cli_views := String(Game.cli.get("views", ""))
	if cli_views != "":
		views = []
		for part in cli_views.split(";", false):
			var f := part.split(":")
			if f.size() == 3:
				var a := f[1].split_floats(",")
				var b := f[2].split_floats(",")
				views.append([f[0], Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2])])
	for v in views:
		me.global_position = v[1] + Vector3(0, -1.6, 0)
		for k in 40:
			if m.runtime.in_cutscene:
				m.runtime.end_cutscene()
			cam.current = true
			cam.global_position = v[1]
			cam.look_at(v[2], Vector3.UP)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://test_output/a2_bug_%s_%s.png" % [tag, v[0]])
		check(true, "Bild " + v[0])
	_finish()
