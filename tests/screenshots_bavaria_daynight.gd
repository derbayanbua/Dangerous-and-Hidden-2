extends Node
## Kontrollbilder Tageszyklus (Fenster): --mission=bavaria --autoplay=screenshots_bavaria_daynight
## → test_output/bavaria_daynight/{tag,daemmerung,nacht}_*.png, OG-Blick nach draußen, Laternen nachts.
const DIR := "res://test_output/bavaria_daynight/"
var m: Mission
var camera: Camera3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	while m == null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	camera = Camera3D.new()
	m.add_child(camera)
	camera.current = true
	camera.fov = 70
	camera.far = preload("res://src/world/view_distance.gd").camera_far()   # Kartenkamera-far (Bavaria ≤ 800 m)
	if "--waldrand=1" in OS.get_cmdline_user_args():
		# Doppelter Waldrand: erhöhter Blick von innen über Randsaum + äußeren Gürtel
		m.day_night.set_hour(12.0, 0.0)
		var a: Vector2 = m.boundary[0]
		var b: Vector2 = m.boundary[1]
		var c := Vector2.ZERO
		for q in m.boundary:
			c += q
		c /= m.boundary.size()
		var mid := a.lerp(b, 0.5)
		var out := (mid - c).normalized()
		var eye := mid - out * 10.0
		camera.global_position = Vector3(eye.x, 14.0, eye.y)
		camera.look_at(Vector3(mid.x + out.x * 18.0, 2.0, mid.y + out.y * 18.0))
		await _save("waldrand_dicht")
		get_tree().quit()
		return
	var h16 := m.static_root.get_node("haus_16") as Node3D
	var og: Array = h16.get_meta("og_shooting_windows", [])
	var road: Array = m.layout["paths"][0]["points"]
	var r0: Vector3 = m.pixel(road[0])
	var r1: Vector3 = m.pixel(road[1])
	var poles: Array = m.street_lamps.lamps.filter(func(l): return l.get_meta("kind") == "pole")
	for phase in [["tag", 12.0], ["daemmerung", 19.35], ["nacht", 0.5]]:
		m.day_night.set_hour(phase[1], 0.0)
		var tag: String = phase[0]
		# Dorfweg auf Augenhöhe
		camera.global_position = r0.lerp(r1, 0.15) + Vector3.UP * 1.7
		camera.look_at(r0.lerp(r1, 0.6) + Vector3.UP * 1.5)
		await _save(tag + "_dorfweg")
		# Fernkulisse je Himmelsrichtung (vom Antennenturm-Stand, über die Randkulisse hinweg)
		var s: Vector3 = m.scene_details.south
		var dirs := {"sued": s, "nord": -s, "ost": Vector3(s.z, 0, -s.x), "west": Vector3(-s.z, 0, s.x)}
		# erhöhter freier Blickpunkt über der Wiese (wie ein Beobachter auf dem Aststand/Dach)
		var stand: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"]) + Vector3.UP * 7.0
		for dname in dirs:
			if tag == "nacht" and dname != "sued":
				continue
			camera.global_position = stand + Vector3.UP * 1.7
			camera.look_at(camera.global_position + dirs[dname] * 10.0 + Vector3.UP * 0.6)
			await _save(tag + "_fernsicht_" + dname)
		# OG Haus 16: Blick von innen nach draußen
		if not og.is_empty():
			var w: Vector3 = og[0]
			var side := signf(w.z)
			camera.global_position = h16.to_global(Vector3(w.x + 0.25, w.y + 1.6, w.z - side * 2.2))
			camera.look_at(h16.to_global(Vector3(w.x, w.y + 1.35, w.z + side * 6.0)))
			await _save(tag + "_og_haus16_blick_nach_draussen")
			# von außen hinein
			camera.global_position = h16.to_global(Vector3(w.x - 1.5, w.y + 2.0, w.z + side * 5.0))
			camera.look_at(h16.to_global(Vector3(w.x, w.y + 1.6, w.z)))
			await _save(tag + "_og_haus16_von_aussen")
		# Laterne
		if not poles.is_empty():
			var p: Node3D = poles[0]
			camera.global_position = p.to_global(Vector3(3.5, 1.7, -5.0))
			camera.look_at(p.to_global(Vector3(0, 2.4, -0.4)))
			await _save(tag + "_laterne")
	# Nacht: Laternenreihe von weiter weg
	m.day_night.set_hour(23.0, 0.0)
	camera.global_position = r0.lerp(r1, 0.05) + Vector3.UP * 2.2
	camera.look_at(r1 + Vector3.UP * 1.0)
	await _save("nacht_laternenreihe")
	get_tree().quit()

func _save(id: String) -> void:
	camera.reset_physics_interpolation()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var sfx := String(Game.cli.get("suffix", ""))   # z. B. --suffix=_opt (Vergleichsbilder neben dem alten Stand)
	get_viewport().get_texture().get_image().save_png(DIR + id + sfx + ".png")
	print("BILD ", DIR + id + sfx + ".png")
