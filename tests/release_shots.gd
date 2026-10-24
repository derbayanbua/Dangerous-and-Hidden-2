extends "res://tests/test_gameplay.gd"
## Werbebilder für Releases (FENSTER, 1920×1080):
##   tools\godot.cmd --resolution 1920x1080 -- --autoplay=release_shots --phase=menu|lan
##   tools\godot.cmd --resolution 1920x1080 -- --mission=a1_blizzard --autoplay=release_shots --phase=ingame|kampf
## → test_output/release_raw/<phase>_<nn>.png (Auswahl von Hand)

const RAW := "res://test_output/release_raw/"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RAW + name + ".png")
	print("Bild: ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RAW))
	var phase: String = Game.cli.get("phase", "menu")
	if phase == "menu" or phase == "lan":
		await get_tree().create_timer(4.0).timeout
		var menu := get_tree().current_scene
		for i in 600:
			menu = get_tree().current_scene
			if menu and menu.has_method("show_menu"):
				break
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		if phase == "menu":
			await _shot("menu_01")
			await get_tree().create_timer(2.0).timeout
			await _shot("menu_02")
		else:
			menu.open_lan()
			await get_tree().create_timer(2.0).timeout
			var lm = menu.lan_menu
			if Game.cli.has("orig_only") and lm:
				# Werbebild: neutraler Hostname, Original-Karte, deren Stil keine lokalen Karten listet
				lm._name_edit.text = "HD2 – Server"
				for i in lm._map.item_count:
					var mm: Dictionary = Game.MISSIONS[String(lm._map.get_item_metadata(i))]
					if mm.get("mp_mode") == null or String(mm.get("orig", "")) == "":
						continue
					lm._map.select(i)
					lm._map.item_selected.emit(i)
					var clean := true
					for id in lm._style_maps():
						if String(Game.MISSIONS[id].get("orig", "")) == "":
							clean = false
					if clean:
						break
				await get_tree().create_timer(1.0).timeout
			await _shot(String(Game.cli.get("shot_name", "lan_01")))
		get_tree().quit()
		return
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.ls_runtime
	for i in 40:
		if rt and rt.in_cutscene:
			rt.end_cutscene()
		await seconds(0.5)
	var s: Soldier = m.squad.leader()
	for i in 60:
		if s.is_on_floor():
			break
		await seconds(0.5)
	print("Boden: ", s.is_on_floor(), " Lage ", s.global_position)
	if phase == "ingame":
		for i in 6:
			await seconds(2.0)
			await _shot("ingame_%02d" % i)
		# Eigene Kamera: Trupp von vorn schräg oben
		var cam := Camera3D.new()
		m.add_child(cam)
		var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
		var side := fwd.cross(Vector3.UP)
		var views := [[fwd * 6.0 + side * 3.0 + Vector3.UP * 2.0], [fwd * 9.0 - side * 4.0 + Vector3.UP * 3.5],
			[-fwd * 5.0 + side * 2.5 + Vector3.UP * 2.2]]
		var n := 0
		for v in views:
			cam.global_position = s.global_position + v[0]
			cam.look_at(s.global_position + Vector3.UP * 1.0 - fwd * 1.5)
			cam.current = true
			await seconds(1.0)
			await _shot("ingame_cam_%02d" % n)
			n += 1
	else:
		var es: Array = []
		for e in m.enemies:
			if is_instance_valid(e) and e.health > 0.0:
				es.append(e)
			if es.size() >= 3:
				break
		var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
		var side := fwd.cross(Vector3.UP)
		var ids: Array = []
		for e in es:
			ids.append(e.persistent_id)
		isolate_enemies(ids)
		# Gegner hinter den Trupp (offenes Feld wie in ingame_cam_00), Anführer dreht sich zu ihnen
		for i in es.size():
			var e: Soldier = es[i]
			var p: Vector3 = s.global_position - fwd * (16.0 + i * 3.0) + side * (float(i) - 1.0) * 4.0
			e.global_position = p + Vector3.UP * 1.0
			e.set_physics_process(true)
		s.look_yaw += PI
		var cam := Camera3D.new()
		m.add_child(cam)
		Settings.blood_level = 2
		await seconds(1.0)
		Input.action_press("fire")
		var mid: Vector3 = s.global_position - fwd * 8.0
		for i in 16:
			await seconds(0.25)
			cam.global_position = s.global_position + fwd * 5.0 + side * (3.0 + i * 0.1) + Vector3.UP * 2.0
			cam.look_at(mid + Vector3.UP * 1.0)
			cam.current = true
			await _shot("kampf_%02d" % i)
		Input.action_release("fire")
		var e0: Soldier = es[0] if es.size() > 0 else null
		if e0 and is_instance_valid(e0):
			Effects.blood(e0.global_position + Vector3.UP * 1.4, -fwd, fwd, &"torso", e0)
			await seconds(0.12)
			await _shot("kampf_blut")
	get_tree().quit()
