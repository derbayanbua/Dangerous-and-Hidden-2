extends "res://tests/menu_shots.gd"
## Kontrollbilder: Teamauswahl und Ausrüstung vor Kampagneneinsätzen, Mehrspieler-LAN-Menü
##   tools\godot.cmd -- --autoplay=menu_shots_sas --profiles_dir=user://test_shots --noimport


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	Game.create_profile("Kamera", 2)
	var menu := get_tree().current_scene
	menu.show_menu("main_menu")
	for id in ["a1_blizzard", "af1_spaghetti_airport"]:
		menu._show_briefing(id)
		await shot("sas_%s_0_briefing" % id)
		menu._open_sas_screen(id)
		var sas: SasScreen = menu.sas_screen
		await shot("sas_%s_1_start" % id)
		if sas.has_method("show_team"):
			sas.show_team()
			await shot("sas_%s_2_team" % id)
			sas.info_page = true
			sas.show_team()
			await shot("sas_%s_2b_team_info" % id)
			sas.info_page = false
			sas.auto_select()
		sas.show_equipment()
		await shot("sas_%s_3_ausruestung" % id)
		if id == "a1_blizzard":
			sas.category = 1
			sas.sel_store = 21
			sas.show_equipment()
			await shot("sas_%s_3b_lager_mittlere" % id)
			sas.dropdown = "filter"
			sas.show_equipment()
			await shot("sas_%s_3c_klassifizierung" % id)
			sas.dropdown = "type"
			sas.show_equipment()
			await shot("sas_%s_3d_soldatentyp" % id)
			sas.dropdown = ""
			sas.status_page = true
			sas.show_equipment()
			await shot("sas_%s_3e_status" % id)
			sas.status_page = false
			sas.show_equipment()
			sas.dialog(SAS.text(9521, "?"), [[SAS.text(2001, "JA"), func(): pass], [SAS.text(2008, "ANNULLIEREN"), func(): pass]])
			await shot("sas_%s_3f_rueckfrage" % id)
			sas.show_equipment()
			sas._select_active_dialog()
			await shot("sas_%s_3g_aktiver_soldat" % id)
		sas.queue_free()
		menu.sas_screen = null
	menu.show_menu("main_menu")
	menu.open_lan()
	await shot("mp_lan_menu")
	var lm = menu.lan_menu
	lm.open_player_setup()
	await shot("mp_player_setup")
	var ps: PlayerSetupScreen = lm.player_setup
	ps.team_pref = Soldier.TEAM_AXIS
	ps.cls = 1
	ps.sel_item = 4
	ps.build()
	await shot("mp_player_setup_achse")
	ps.dropdown = "class"
	ps.build()
	await shot("mp_player_setup_klassen")
	get_tree().quit()
