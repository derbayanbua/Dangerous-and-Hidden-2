extends "res://tests/test_gameplay.gd"
## Filme vor dem Einsatz überspringen bzw. regulär beenden – in jeder Spielart muss danach der Folgebildschirm
## (Einsatzbesprechung) sichtbar sein: Kampagne, Einzelgänger, Blutbad, Einzelmission, Einzelmission-Blutbad.
## Ablauf wie ein Spieler: Hauptmenü → EINZELSPIELER → Spielart → Mission wählen → START → Filme → Briefing.
##   tools\godot.cmd --headless -- --autoplay=test_movie_skip --profiles_dir=user://test_movie_skip --noimport


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


func click() -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = Vector2(20, 20)
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


func movie(menu: Node) -> Node:
	return menu.find_child("MoviePlayer", true, false)


## Briefing sichtbar, kein Filmabspieler mehr, Menübühne ausgeblendet
func briefing_shown(menu: Node) -> bool:
	var br = menu.get("_brief_root")
	return br != null and is_instance_valid(br) and (br as Control).is_visible_in_tree() and movie(menu) == null


func run_case(menu: Node, label: String, button: String, how: String) -> void:
	menu.show_menu("singleplayer")
	await frames(2)
	var b := menu.find_child(button.validate_node_name(), true, false) as Button
	check(b != null and not b.disabled, "%s: Spielart wählbar" % label)
	if b == null:
		return
	b.pressed.emit()
	await frames(2)
	menu._select_mission("a1_blizzard")
	await frames(1)
	var start: Button = menu.get("_start_btn")
	check(start != null and not start.disabled, "%s: START nach Missionswahl frei" % label)
	start.pressed.emit()
	await frames(5)
	var mp := movie(menu)
	check(mp != null and String(mp.get("current")) == "IntroArctic", "%s: Kampagnen-Intro läuft" % label,
		String(mp.get("current")) if mp else "kein Film")
	match how:
		"esc":
			await key(KEY_ESCAPE)
			await frames(3)
			check(movie(menu) != null and String(movie(menu).get("current")) == "BriefArctic1a", "%s: Esc → Briefing-Video" % label)
			await key(KEY_ESCAPE)
		"click":
			await click()
			await frames(3)
			await click()
		"space":
			await key(KEY_SPACE)
			await frames(3)
			await key(KEY_ENTER)
		"end":
			# regulärer Ablauf: Filme enden von selbst (Ende des Videos simuliert)
			for i in 2:
				var m2 := movie(menu)
				if m2:
					(m2.get("_vp") as VideoStreamPlayer).finished.emit()
				await frames(3)
	for i in 30:
		await frames(1)
		if briefing_shown(menu):
			break
	check(briefing_shown(menu), "%s (%s): Einsatzbesprechung sichtbar, Film freigegeben" % [label, how],
		"Film %s, Briefing %s" % [movie(menu) != null, menu.get("_brief_root") != null])
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s: Mauszeiger sichtbar" % label)
	# zurück ins Menü
	var br = menu.get("_brief_root")
	if br:
		(br as Node).queue_free()
		menu.set("_brief_root", null)
		menu.stage.visible = true
	await frames(2)


func _run() -> void:
	await frames(10)
	var menu := get_tree().current_scene
	Game.create_profile("FilmSkip", 2)
	check(Game.movie_path("IntroArctic") != "" and Game.movie_path("BriefArctic1a") != "", "Filme konvertiert vorhanden")
	await run_case(menu, "BLUTBAD", "carnage", "esc")
	await run_case(menu, "BLUTBAD", "carnage", "click")
	await run_case(menu, "BLUTBAD", "carnage", "end")
	await run_case(menu, "KAMPAGNE", "bcampaign", "esc")
	await run_case(menu, "KAMPAGNE", "bcampaign", "space")
	await run_case(menu, "KAMPAGNE", "bcampaign", "end")
	await run_case(menu, "EINZELGÄNGER", "blone wolf", "esc")
	await run_case(menu, "EINZELGÄNGER", "blone wolf", "end")
	# Einzelmissionen: Arctic 1A in der Kampagne freigeschaltet (Standard)
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	await run_case(menu, "EINZELMISSION", "bsingle mission", "esc")
	await run_case(menu, "EINZELMISSION-BLUTBAD", "bsingle mission- carnage", "click")
	await run_case(menu, "EINZELMISSION-BLUTBAD", "bsingle mission- carnage", "end")
	# Einsatz-Intro (Skript-Zwischensequenz) überspringen: Bild darf nicht schwarz bleiben
	for m in [[Game.MODE_CARNAGE, "BLUTBAD"], [Game.MODE_CAMPAIGN, "KAMPAGNE"], [Game.MODE_LONE_WOLF, "EINZELGÄNGER"]]:
		await mission_intro_skip(int(m[0]), String(m[1]))
	Game.delete_profile("FilmSkip")
	_finish()


func mission_intro_skip(mode: int, label: String) -> void:
	Game.set_game_mode(mode)
	Game.start_mission("a1_blizzard")
	var ms: Node = null
	for i in 4000:
		await get_tree().process_frame
		ms = Game.current_mission()
		if ms and ms.get("runtime") != null and ms.runtime.in_cutscene:
			break
	var rt = ms.get("runtime") if ms else null
	check(rt != null and rt.in_cutscene, "%s: Einsatz-Intro (Zwischensequenz) läuft" % label)
	if rt == null:
		return
	await seconds(1.5)
	await key(KEY_SPACE)
	var a_max := 0.0
	for i in 240:
		await frames(1)
	var fade: ColorRect = rt._fade
	check(not rt.in_cutscene and fade.color.a < 0.05, "%s: nach dem Überspringen kein schwarzer Bildschirm" % label,
		"Sequenz %s, Blende %.2f" % [rt.in_cutscene, fade.color.a])
	check(ms.rig.camera.current and ms.controller.input_enabled, "%s: Spielkamera und Steuerung zurück" % label)
	Game.return_to_menu()
	for i in 60:
		await get_tree().process_frame
