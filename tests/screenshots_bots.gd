extends "res://tests/test_bots.gd"
## Kontrollbilder einer KI-Runde (Fenster, nicht headless): Draufsicht mit Debug-Ansicht (Pfade, Ziele, Stellungen,
## Zonen) und Schrägansicht eines Trupps.
##   tools\godot.cmd -- --autoplay=screenshots_bots [--shot_map=mp_burma1_mp_zone] [--shot_mode=2] [--shot_s=45]
## → test_output/bots_<karte>_top*.png, bots_<karte>_squad.png

const OUT := "res://test_output/"


func _run() -> void:
	await frames(5)
	var map := String(Game.cli.get("shot_map", "mp_burma1_mp_zone"))
	var mode := int(Game.cli.get("shot_mode", str(Net.Mode.OCCUPATION)))
	var m = await _host(map, mode, 4)
	if m == null:
		check(false, "Karte geladen")
		_finish()
		return
	_host_off()
	BotDebug.toggle("on")
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.far = 4000.0
	var dur := float(Game.cli.get("shot_s", "45"))
	for k in 3:
		await seconds(dur / 3.0)
		_top(cam, m)
		await frames(3)
		await RenderingServer.frame_post_draw
		_save("bots_%s_top%d" % [map, k])
	# Schrägansicht hinter dem ersten lebenden Gruppenführer
	for s in _bots():
		var b := _brain(s)
		if s.alive and b and b.is_leader() and b.state != EnemyBrain.State.COMBAT:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 60.0
			var back: Vector3 = s.global_position - s.forward() * 18.0 + Vector3.UP * 14.0
			cam.look_at_from_position(back, s.global_position + s.forward() * 10.0, Vector3.UP)
			cam.make_current()
			await frames(3)
			await RenderingServer.frame_post_draw
			_save("bots_%s_squad" % map)
			break
	check(true, "Aufnahmen erstellt")
	await _leave()
	_finish()


## Draufsicht über alle lebenden KI-Soldaten und Zonen (orthogonal)
func _top(cam: Camera3D, m: Node) -> void:
	var pts: Array = []
	for s in _bots():
		if s.alive:
			pts.append(s.global_position)
	if m.has_method("mp_zones"):
		for z in m.mp_zones():
			pts.append((z["xf"] as Transform3D).origin)
	if pts.is_empty():
		return
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var c := (lo + hi) * 0.5
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := get_viewport().get_visible_rect().size
	cam.size = maxf(hi.z - lo.z, (hi.x - lo.x) * vp.y / maxf(vp.x, 1.0)) + 30.0
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(c.x, hi.y + 150.0, c.z))
	cam.make_current()


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("BILD ", name)
