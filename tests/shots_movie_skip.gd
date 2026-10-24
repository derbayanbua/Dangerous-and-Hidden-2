extends "res://tests/menu_shots.gd"
## Kontrollbilder (Fenster): Blutbad-Kampagne starten, Kampagnen-Intro und Briefing-Video per Taste/Klick
## überspringen → Einsatzbesprechung muss sichtbar sein.
##   tools\godot.cmd -- --autoplay=shots_movie_skip --profiles_dir=user://test_shots_skip --noimport


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func click_at(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	Game.create_profile("Skip", 2)
	var menu := get_tree().current_scene
	for mode in [["carnage", "esc"], ["carnage", "click"], ["bcampaign", "esc"], ["blone wolf", "click"]]:
		menu.show_menu("singleplayer")
		await get_tree().process_frame
		(menu.find_child(String(mode[0]).validate_node_name(), true, false) as Button).pressed.emit()
		await get_tree().process_frame
		menu._select_mission("a1_blizzard")
		(menu.get("_start_btn") as Button).pressed.emit()
		await get_tree().create_timer(2.5).timeout
		await shot("skip_%s_%s_0_intro" % [mode[0].replace(" ", "_"), mode[1]])
		for k in 2:
			if mode[1] == "esc":
				await key(KEY_ESCAPE)
			else:
				await click_at(get_viewport().get_visible_rect().size * 0.5)
			await get_tree().create_timer(1.5).timeout
			await shot("skip_%s_%s_%d" % [mode[0].replace(" ", "_"), mode[1], k + 1])
		print("SKIP %s %s: Film=%s Briefing=%s" % [mode[0], mode[1], menu.find_child("MoviePlayer", true, false) != null,
			menu.get("_brief_root") != null])
		var br = menu.get("_brief_root")
		if br:
			(br as Node).queue_free()
			menu.set("_brief_root", null)
			menu.stage.visible = true
	# Einsatz-Intro (Zwischensequenz) der Blutbad-Kampagne überspringen
	Game.set_game_mode(Game.MODE_CARNAGE)
	Game.start_mission("a1_blizzard")
	var ms: Node = null
	for i in 20000:
		await get_tree().process_frame
		ms = Game.current_mission()
		if ms and ms.get("runtime") != null and ms.runtime.in_cutscene:
			break
	await get_tree().create_timer(4.0).timeout
	await shot("skip_mission_intro_0_sequenz")
	await key(KEY_SPACE)
	await get_tree().create_timer(4.0).timeout
	await shot("skip_mission_intro_1_danach")
	print("SKIP Einsatz-Intro: Sequenz=%s Blende=%.2f" % [ms.runtime.in_cutscene, ms.runtime._fade.color.a])
	Game.delete_profile("Skip")
	get_tree().quit()
