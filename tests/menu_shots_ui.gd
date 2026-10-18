extends "res://tests/menu_shots.gd"
## Kontrollbilder (Fenster): Nachbesprechung/Tagebuch, FILME, Spielmodi, Inventar-Beschreibung/Vorlagen,
## MP-Figurwahl mit Helden, Pausemenü mit Spielstandliste, taktische Karte mit Plänen.
##   tools\godot.cmd -- --autoplay=menu_shots_ui --profiles_dir=user://test_shots_ui --noimport


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	Game.create_profile("Kamera", 3)
	var menu := get_tree().current_scene
	menu.show_menu("main_menu")
	await shot("ui_01_hauptmenue")
	menu.show_menu("cinematics")
	var intro := menu.find_child("film_Intro", true, false) as Button
	if intro:
		intro.pressed.emit()
	await shot("ui_02_filme")
	menu.show_menu("singleplayer")
	await shot("ui_03_einzelspieler")
	menu._open_mode(Game.MODE_LONE_WOLF, false)
	await shot("ui_04_einzelgaenger")
	menu._open_mode(Game.MODE_CARNAGE, true)
	await shot("ui_05_einzelmission_blutbad")
	menu.show_menu("singleplayer")
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	# Inventar: Beschreibung und eigene Vorlagen
	menu._open_sas_screen("a1_blizzard")
	var sas: SasScreen = menu.sas_screen
	sas.show_equipment()
	sas.save_user_preset(0)
	sas.dropdown = "type"
	sas.show_equipment()
	await shot("ui_06_inventar_vorlagen")
	sas.dropdown = ""
	sas.show_equipment()
	await get_tree().process_frame
	sas.show_description(21, Vector2(640, 260))
	await shot("ui_07_inventar_beschreibung")
	sas.queue_free()
	menu.sas_screen = null
	# MP-Figurwahl
	menu.show_menu("main_menu")
	menu.open_lan()
	var lm = menu.lan_menu
	lm.open_player_setup()
	var ps: PlayerSetupScreen = lm.player_setup
	# Helden nur mit lokaler Datei (nicht im Repository)
	if not Net.hero_of("axis").is_empty():
		ps._pick_figure(false, "hero:axis")
		await shot("ui_08_spieler_setup_held_achse")
	if not Net.hero_of("allied").is_empty():
		ps._pick_figure(false, "hero:allied")
		await shot("ui_09_spieler_setup_held_alliierte")
	ps._scroll_figures(1)
	ps._pick_figure(false, "mp:31")
	await shot("ui_10_spieler_setup_mp_figur")
	lm.queue_free()
	# Nachbesprechung mit Soldatenpanels, Orden, Tagebuch
	Game.prepare_sas("a1_blizzard", true)
	Game.current_mission_id = "a1_blizzard"
	var team: Array = Game.sas_team()
	var members: Array = []
	for i in team.size():
		var s := Soldier.new()
		s.persistent_id = "sas_%d" % int(team[i])
		s.training = {"kills": 30.0 - i * 8.0, "unseen_kills": 20.0 - i * 6.0, "sprint_s": 120.0, "sneak_s": 90.0, "heals": 2.0}
		s.alive = i != 2
		members.append(s)
	Game.last_result = {"success": true, "reason": "", "time": 812.0, "stats": {"kills": 23},
		"objectives": [[SAS.text(6001, "Ziel 1"), 1, false], [SAS.text(6002, "Ziel 2"), 1, false], [SAS.text(6003, "Ziel 3"), 2, true]],
		"mission": "a1_blizzard"}
	Game.add_diary_text(21)
	Game.add_diary_text(4501)
	Game.last_result["sas"] = Game.finish_sas(members, true)
	Game.last_result["fallen"] = []
	for s in members:
		s.free()
	get_tree().change_scene_to_file("res://scenes/debrief.tscn")
	for i in 10:
		await get_tree().process_frame
	var deb := get_tree().current_scene
	await shot("ui_11_nachbesprechung")
	var best := 0
	var ms: Array = Game.last_result["sas"]["members"]
	for i in ms.size():
		if int(ms[i]["new_medal"]) >= 0:
			best = i
			break
	deb.member_i = best
	deb.show_debrief()
	await shot("ui_12_nachbesprechung_orden")
	deb.member_i = 2
	deb.show_debrief()
	await shot("ui_13_nachbesprechung_gefallen")
	deb.save_and_continue()
	await shot("ui_14_speichern_rueckfrage")
	deb.show_diary()
	await shot("ui_15_tagebuch")
	Game.discard_debrief()
	# Einsatz: Pausemenü, Spielstandliste, taktische Karte
	Game.start_mission("m01_funkfeuer")
	var m: Mission = null
	for i in 3000:
		await get_tree().process_frame
		m = Game.current_mission() as Mission
		if m and m.squad and m.squad.leader() and m.nav_ready:
			break
	for i in 60:
		await get_tree().process_frame
	var pm := m.get_node("PauseMenu")
	pm.open()
	await shot("ui_16_pausemenue")
	pm.open_saves("save")
	await shot("ui_17_speichern_liste")
	pm._saves_action()
	pm.open()
	pm.open_saves("load")
	await shot("ui_18_laden_liste")
	pm.close()
	var tm = m.tactical_map
	tm.open()
	var a: Soldier = m.squad.members[1]
	var b: Soldier = m.squad.members[2]
	tm.selected.append(a)
	tm.press_button("kneel")
	tm.add_waypoint(a, a.global_position + Vector3(10, 0, -6), 1)
	tm.press_button("kneel")
	tm.press_button("walk")
	tm.add_waypoint(a, a.global_position + Vector3(18, 0, 2))
	tm.press_button("run")
	tm.add_waypoint(b, b.global_position + Vector3(-12, 0, -10))
	tm.add_waypoint(b, b.global_position + Vector3(-20, 0, 4), 2)
	tm.sel_wp = [a, 1]
	tm._update_camera()
	await shot("ui_19_taktische_karte")
	tm.press_button("options")
	await shot("ui_20_taktische_karte_hilfe")
	tm.close()
	for e in Game.list_saves():
		Game.delete_save(String(e["slot"]))
	get_tree().quit()
