extends "res://tests/test_gameplay.gd"
## Hauptmenü nach dem Original: Profil-Logik, Schwierigkeitsgrad, Einstellungsseiten, Tastenbelegung.
##   tools\godot.cmd --headless -- --autoplay=test_menu --profiles_dir=user://test_profiles
## (echte Profildateien im Testordner; settings.cfg/Tastenbelegung werden im Testmodus nicht geschrieben)


func btn(name_part: String) -> Button:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if String(b.name).contains(name_part.validate_node_name()) or (b as Button).text == name_part:
			return b
	return null


func _run() -> void:
	await frames(10)
	var menu := get_tree().current_scene
	# --- ohne Profil: wie im Original nur "PROFIL ERSTELLEN" und "ENDE" ---
	check(not Game.has_profile(), "Start ohne Profil")
	var b2 := btn("bchange profile")
	check(b2 != null and b2.text == menu.text(2117) and not b2.disabled, "Knopf 2 heißt „%s“" % menu.text(2117), b2.text if b2 else "-")
	check(btn("bsingleplayer").disabled and btn("boptions").disabled, "Ohne Profil: Einzelspieler/Einstellungen gesperrt")
	check(not btn("bexit").disabled, "ENDE bleibt wählbar")
	# Profil anlegen über den Dialog
	b2.pressed.emit()
	await frames(3)
	var le := get_tree().root.find_child("NameEdit", true, false) as LineEdit
	check(le != null, "Namensdialog öffnet sich")
	if le:
		le.text = "Alpha"
		le.text_submitted.emit("Alpha")
	await frames(3)
	check(Game.has_profile() and Game.profile_name == "Alpha", "Profil „Alpha“ angelegt und aktiv")
	check(FileAccess.file_exists(Game.profile_dir() + "/profile.json") and DirAccess.dir_exists_absolute(Game.profile_dir() + "/saves"),
		"Profilordner mit profile.json und saves/ angelegt", ProjectSettings.globalize_path(Game.profile_dir()))
	check(menu.current_menu == "change_profile", "Profilbildschirm angezeigt")
	check(btn("profile_Alpha") != null, "Profil in der Liste")
	# Schwierigkeitsgrad
	btn("beasy-war never was so fun!").pressed.emit()
	await frames(2)
	check(Game.difficulty() == 1, "Schwierigkeit „%s“ gesetzt" % menu.text(2157))
	var info: String = menu._profile_info()
	check(info.contains(menu.text(2165)) and info.contains(menu.text(2157)), "Profilinfo nennt Schwierigkeitsgrad")
	# Umbenennen
	btn("brename profile").pressed.emit()
	await frames(3)
	le = get_tree().root.find_child("NameEdit", true, false) as LineEdit
	if le:
		le.text = "Bravo"
		le.text_submitted.emit("Bravo")
	await frames(3)
	check(Game.profile_name == "Bravo" and Game.profile.get("name") == "Bravo", "Profil umbenannt")
	check(DirAccess.dir_exists_absolute(Game.profile_dir("Bravo")) and not DirAccess.dir_exists_absolute(Game.profile_dir("Alpha")),
		"Profilordner umbenannt")
	# zweites Profil, wechseln, Kampagnenfortschritt getrennt
	Game.campaign["completed"] = ["a1_blizzard"]
	Game.save_campaign()
	Game.create_profile("Charlie", 3)
	check(Game.profile_name == "Charlie" and Game.campaign.get("completed", []).is_empty(), "Neues Profil mit eigener Kampagne")
	check(Game.select_profile("Bravo") and Game.campaign.get("completed", []).has("a1_blizzard") and Game.difficulty() == 1,
		"Profilwechsel lädt Kampagne und Schwierigkeit des Profils")
	check(Game.list_profiles().size() == 2, "Profil-Liste: 2 Profile", str(Game.list_profiles()))
	# Hauptmenü mit Profil
	menu.show_menu("main_menu")
	await frames(2)
	check(not btn("bsingleplayer").disabled and not btn("boptions").disabled, "Mit Profil: Menüpunkte frei")
	check(btn("bchange profile").text == menu.text(2106), "Knopf 2 heißt jetzt „%s“" % menu.text(2106))

	# --- Einstellungen: alle Seiten, Werte wirken ---
	var old := [Settings.subtitles, Settings.crosshair, Settings.gamma, Settings.music_volume, Settings.quality]
	btn("boptions").pressed.emit()
	await frames(2)
	check(menu.current_menu == "options", "Einstellungen geöffnet (Grafik)")
	for page in ["bsound setup", "bcontrols", "bgame setup", "bvideo setup"]:
		btn(page).pressed.emit()
		await frames(2)
	check(menu.options_page == "graphics", "Alle Einstellungsseiten aufrufbar")
	var q0 := Settings.quality
	for b in get_tree().root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("GRAFIK-DETAILS"):
			(b as Button).pressed.emit()
			break
	await frames(2)
	check(Settings.quality == (q0 + 1) % 4, "Grafikdetails umschaltbar", "%d -> %d" % [q0, Settings.quality])
	btn("bgame setup").pressed.emit()
	await frames(2)
	Settings.subtitles = false
	check(not Settings.subtitles, "Untertitel abschaltbar")
	btn("bsound setup").pressed.emit()
	await frames(2)
	var sliders := get_tree().root.find_children("*", "HSlider", true, false)
	check(sliders.size() == 2, "Sound-Seite: 2 Regler (Sound, Musik)", str(sliders.size()))
	if sliders.size() == 2:
		(sliders[1] as HSlider).value = 0.25
		await frames(1)
		check(is_equal_approx(Settings.music_volume, 0.25) and AudioServer.get_bus_index("Music") >= 0,
			"Musik-Lautstärke wirkt auf Bus „Music“", "%.2f" % Settings.music_volume)
	# Tastenbelegung
	btn("bcontrols").pressed.emit()
	await frames(2)
	btn("bkeys").pressed.emit()
	await frames(2)
	check(menu.options_page == "keys" and btn("key_move_forward") != null, "Tastenbelegung (Bewegung) angezeigt")
	var before: String = InputSetup.binding_text("reload")
	menu._keys_category = 1
	menu.show_menu("options")
	await frames(2)
	btn("key_reload").pressed.emit()
	await frames(2)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_P
	ev.pressed = true
	menu._input(ev)
	await frames(2)
	check(InputSetup.binding_text("reload") != before and InputSetup.binding_text("reload").contains("P"),
		"Taste neu belegt (Nachladen -> P)", InputSetup.binding_text("reload"))
	InputSetup.reset_defaults()
	InputSetup.save_bindings()
	check(InputSetup.binding_text("reload") == before, "Standardbelegung wiederhergestellt")
	# Einstellungen zurücksetzen (Test soll nichts dauerhaft verstellen)
	Settings.subtitles = old[0]
	Settings.crosshair = old[1]
	Settings.gamma = old[2]
	Settings.music_volume = old[3]
	Settings.quality = old[4]
	Settings.save_settings()

	# --- Profil löschen mit Sicherheitsabfrage ---
	menu.show_menu("change_profile")
	await frames(2)
	btn("bdelete profile").pressed.emit()
	await frames(2)
	var yes := btn("dlg_" + menu.text(2001))
	check(yes != null, "Sicherheitsabfrage „%s“" % menu.text(2004))
	if yes:
		yes.pressed.emit()
	await frames(2)
	check(Game.profile_name == "Charlie" and not DirAccess.dir_exists_absolute(Game.profile_dir("Bravo")),
		"Profil gelöscht (Ordner entfernt), verbleibendes Profil aktiv", Game.profile_name)
	Game.delete_profile("Charlie")
	check(not Game.has_profile(), "Letztes Profil gelöscht -> kein aktuelles Profil")
	_finish()
