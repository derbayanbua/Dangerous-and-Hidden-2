extends "res://tests/menu_shots.gd"
## Kontrollbilder (Fenster): MITWIRKENDE (Nachbau-Abschnitt, Original-Rolltext mit Spalten) und Munitions-Reihenfolge
## im Inventar-Bildschirm (Lager + Taschen/Rucksack).
##   tools\godot.cmd -- --autoplay=menu_shots_credits --profiles_dir=user://test_shots_credits --noimport
## -> test_output/menu_credits_*.png, menu_ammo_*.png


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	Game.create_profile("Kamera", 2)
	var menu := get_tree().current_scene
	menu.show_menu("main_menu")
	# --- Mitwirkende ---
	menu._show_credits()
	var c: Control = menu.credits_content
	c.process_mode = Node.PROCESS_MODE_DISABLED  # Rollen anhalten (gebundener Tween pausiert) für feste Bildpositionen
	c.position.y = 120.0                       # Nachbau-Abschnitt vollständig im Bild
	await shot("credits_1_nachbau")
	c.position.y = -760.0                      # Übergang zu den Original-Mitwirkenden (Lead-Namen)
	await shot("credits_2_original")
	var y := _first_column_y(c)
	if y >= 0.0:
		c.position.y = 300.0 - y               # dreispaltiger Abschnitt
		await shot("credits_3_spalten")
	c.position.y = 768.0 - 40.0                # tatsächlicher Start: Text läuft von unten herein
	await shot("credits_0_start")
	menu._close_credits()
	# --- Munition unter der Waffe (Inventar-Auswahl) ---
	menu._show_briefing("a1_blizzard")
	menu._open_sas_screen("a1_blizzard")
	var sas: SasScreen = menu.sas_screen
	if sas.has_method("show_team"):
		sas.auto_select()
	Game.campaign["storage"] = [[187, 4], [190, 9], [22, 1], [21, 2], [20, 1], [189, 6], [18, 1], [216, 3], [37, 1],
		[172, 6], [7, 1], [2, 2], [174, 8], [4, 1], [9, 3]]
	sas.focus_idx = Game.sas_team()[0]
	var inv := Game.sas_inventory(sas.focus_idx)
	inv["hands"] = 21
	inv["items"] = [[172, 2], [9, 1], [187, 1], [2, 1], [190, 3]]
	for cat in [0, 1, 2, 5]:
		sas.category = cat
		sas.store_ofs = 0
		sas.show_equipment()
		await shot("ammo_lager_kat%d" % cat)
	get_tree().quit()


func _first_column_y(c: Control) -> float:
	for l in c.get_children():
		if l is Label and (l as Label).size.x < 300.0:
			return (l as Label).position.y
	return -1.0
