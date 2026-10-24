extends "res://tests/test_gameplay.gd"
## Kampagnenabschluss wie im Original: nach Czech6 (SPEICHERN UND FORTSETZEN → Game.continue_campaign) die Videoknoten
## der Kampagne Czech aus Gamedata00.gdt („Outro2.bik“, „credits.bik“): Outro2 (Film ohne Tonspur) mit Musikgruppe 37
## „Credits“, danach der Mitwirkenden-Rolltext (credits.bik ist nicht installiert; hd2.exe 0x688100 erkennt den Namen
## „credits“ und zeigt den Rolltext), danach Missionsliste mit Menümusik.
##   tools\godot.cmd --headless -- --autoplay=test_campaign_end --profiles_dir=user://test_campaign_end --noimport


func movie(menu: Node) -> Node:
	return menu.find_child("MoviePlayer", true, false)


func credits_music(menu: Node) -> bool:
	var mu: AudioStreamPlayer = menu.get("_music")
	return mu != null and mu.playing and mu.stream != null and mu.stream.has_meta("credits")


func _run() -> void:
	await frames(10)
	Game.create_profile("KampagnenEnde", 2)
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	check(Game.CAMPAIGN_ORDER.back() == "cz6_abrechnung", "Czech6 ist der letzte Kampagnenteil", str(Game.CAMPAIGN_ORDER.back()))
	var after: Array = Game._videos_after("cz6_abrechnung")
	check(after == ["Outro2", "credits"], "Videoknoten nach Czech6 (Gamedata00.gdt)", str(after))
	check(Game._videos_after("cz5_trink_aus").is_empty() or not Game._videos_after("cz5_trink_aus").has("Outro2"),
		"nach Czech5 kein Abspann", str(Game._videos_after("cz5_trink_aus")))
	check(Game.movie_path("Outro2") != "", "Outro2 konvertiert vorhanden")
	Game.current_mission_id = "cz6_abrechnung"
	Game.continue_campaign()
	var menu: Node = null
	var mp: Node = null
	for i in 600:
		await get_tree().process_frame
		menu = get_tree().current_scene
		if menu and menu.has_method("show_menu"):
			mp = movie(menu)
			if mp and String(mp.get("current")) != "":
				break
	check(mp != null and String(mp.get("current")) == "Outro2", "Outro2 läuft nach Czech6",
		String(mp.get("current")) if mp else "kein Film")
	await frames(5)
	check(credits_music(menu), "Outro2: Musikgruppe 37 (credits.ogg) läuft (0x688259)")
	check(String(menu.get("current_menu")) == "campaign", "Missionsliste der Kampagne darunter", String(menu.get("current_menu")))
	# Film endet regulär
	if mp:
		(mp.get("_vp") as VideoStreamPlayer).finished.emit()
	await frames(5)
	check(movie(menu) == null, "Filmabspieler beendet")
	var cr = menu.get("_credits_root")
	check(cr != null and is_instance_valid(cr), "Mitwirkenden-Rolltext nach Outro2 (Videoknoten credits.bik)")
	check(menu.get("credits_content") != null and float(menu.get("credits_height")) > 768.0, "Rolltext aufgebaut",
		"Höhe %.0f" % float(menu.get("credits_height")))
	check(credits_music(menu), "Credits-Musik läuft im Rolltext weiter (nicht neu gestartet)")
	# Abbruch per Esc wie im Menü MITWIRKENDE
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await frames(3)
	cr = menu.get("_credits_root")
	check(cr == null or not is_instance_valid(cr), "Rolltext per Esc beendet")
	check(not credits_music(menu) and (menu.get("_music") as AudioStreamPlayer).playing, "danach Menümusik")
	check(movie(menu) == null and String(menu.get("current_menu")) == "campaign", "zurück in der Missionsliste")
	# Menü FILME: Outro2 spielt ebenfalls mit Credits-Musik (Namensprüfung im Filmobjekt), ohne Rolltext
	menu._play_videos(["Outro2"], Callable())
	await frames(5)
	check(movie(menu) != null and credits_music(menu), "FILME Outro2: Credits-Musik")
	movie(menu).call("skip")
	await frames(5)
	check(menu.get("_credits_root") == null or not is_instance_valid(menu.get("_credits_root")), "FILME Outro2: kein Rolltext")
	Game.delete_profile("KampagnenEnde")
	_finish()
