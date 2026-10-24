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
	# Original-Grafikseite: 7 Schalter (2418–2424) + Detailstufe (2414–2417)
	var old_detail := {}
	for k in ["shadows", "morphing", "decals", "blood", "grass", "dynamic_lights", "high_models", "quality"]:
		old_detail[k] = Settings.get(k)
	var labels := []
	for l in get_tree().root.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	var all_found := true
	for tid in range(2418, 2425):
		if not labels.has(menu.text(tid)):
			all_found = false
	check(all_found, "Grafikseite: alle 7 Original-Schalter (SCHATTEN … MODELLE MIT HOHER AUFLÖSUNG)")
	Settings.set_detail_preset(0)
	menu.show_menu("options")
	await frames(2)
	check(btn("bdetail").text == menu.text(2414) and not Settings.shadows and not Settings.grass,
		"Detailstufe NIEDRIG setzt die Schalter", btn("bdetail").text)
	btn("bdetail").pressed.emit()
	await frames(2)
	check(Settings.detail_level() == 1 and not Settings.shadows and Settings.morphing and Settings.blood and not Settings.grass, "Detailstufe MITTEL (Original-Tabelle)", btn("bdetail").text)
	btn("bdetail").pressed.emit()
	await frames(2)
	check(Settings.detail_level() == 2 and Settings.grass and Settings.high_models, "Detailstufe HOCH", btn("bdetail").text)
	Settings.blood = false
	menu.show_menu("options")
	await frames(2)
	check(btn("bdetail").text == menu.text(2417), "Einzelschalter geändert -> „%s“" % menu.text(2417), btn("bdetail").text)
	btn("bdisplay").pressed.emit()
	await frames(2)
	check(menu.options_page == "display", "Unterseite Anzeige & Setup erreichbar")
	# Optionen aus dem Original-Setup (setup.exe)
	var old_setup := [Settings.vsync_mode, Settings.aa_mode, Settings.texture_quality, Settings.max_fps, Settings.anisotropy]
	btn("baa").pressed.emit()
	await frames(2)
	check(Settings.aa_mode == (old_setup[1] + 1) % 6, "Kantenglättung umschaltbar (Original „Fullscene-Antialiasing“)",
		Settings.AA_NAMES[Settings.aa_mode])
	btn("bvsync").pressed.emit()
	await frames(2)
	check(Settings.vsync_mode == (old_setup[0] + 1) % 4, "VSync-Modus inkl. Dreifachpuffer (Original „Triple-Buffering“)",
		Settings.VSYNC_NAMES[Settings.vsync_mode])
	btn("bfps").pressed.emit()
	await frames(2)
	check(Settings.max_fps != old_setup[3] and Engine.max_fps == Settings.max_fps, "Bildratenbegrenzung wirkt", str(Engine.max_fps))
	btn("btex").pressed.emit()
	await frames(2)
	check(Settings.texture_quality == (old_setup[2] + 1) % 3, "Texturqualität umschaltbar (Original „Text.-Qual.“)",
		Settings.TEXTURE_NAMES[Settings.texture_quality])
	Settings.vsync_mode = old_setup[0]
	Settings.aa_mode = old_setup[1]
	Settings.texture_quality = old_setup[2]
	Settings.max_fps = old_setup[3]
	Settings.anisotropy = old_setup[4]
	Settings.apply()
	menu.options_page = "graphics"
	for k in old_detail:
		Settings.set(k, old_detail[k])
	btn("bgame setup").pressed.emit()
	await frames(2)
	Settings.subtitles = false
	check(not Settings.subtitles, "Untertitel abschaltbar")
	btn("bsound setup").pressed.emit()
	await frames(2)
	var sliders := get_tree().root.find_children("*", "HSlider", true, false)
	check(sliders.size() == 4, "Sound-Seite: Original-Regler Sound, Musik + Ergänzung Effekte, Sprache", str(sliders.size()))
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
	check(menu.KEY_CATEGORIES.size() == 5 and menu.text(menu.KEY_CATEGORIES[4][0]) == menu.text(2456),
		"Tastenbelegung: 5 Original-Kategorien (inkl. %s)" % menu.text(2456))
	btn("bdefault2").pressed.emit()
	await frames(2)
	check(InputSetup.binding_text("move_forward").contains("Up") or InputSetup.binding_text("move_forward").contains("Oben")
		or InputSetup.binding_text("move_forward").contains("↑"), "„%s“ (Pfeiltasten)" % menu.text(2459), InputSetup.binding_text("move_forward"))
	btn("bdefault1").pressed.emit()
	await frames(2)
	check(InputSetup.binding_text("reload") == before and InputSetup.binding_text("move_forward") == "W",
		"„%s“ stellt die Standardbelegung her" % menu.text(2457))
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

	# --- Mehrspieler „SPIELER-SETUP“ (player screen.4ds) ---
	var old_cls := Net.local_class
	var ps := PlayerSetupScreen.new()
	get_tree().root.add_child(ps)
	ps.open(String(Game.MP_MAPS[0]) if not Game.MP_MAPS.is_empty() else "")
	await frames(2)
	check(ps.has_layout() and ps.find_child("Accept", true, false) != null and ps.class_label(1) != "",
		"SPIELER-SETUP: Originallayout, Klassenliste aus mp.json", ps.class_label(1))
	ps.cls = 1
	ps.accept()
	check(Net.local_class == 1, "AKZEPTIEREN übernimmt die Klasse (Net.local_class)")
	Net.local_class = old_cls
	ps.queue_free()
	await _check_credits(menu)
	_finish()


## MITWIRKENDE: Original-Rolltext aus orig_cache (credits.txt, Parser wie hd2.exe 0x689340) + Nachbau-Abschnitt
func _check_credits(menu: Node) -> void:
	var sample := "; Kommentar\n1\t\"<SPEED>55\"\n10\t\"<SM>TITEL\"\n11\t\"<ES>\"\n20\t\"<TICZ>NAME Č\"\n30\t\"<EL>\"\n" \
		+ "40\t\"<SMCZ><C_1>A<C_2>B<C_3>C\"\n9990\n"
	var p: Dictionary = menu.parse_credits(sample)
	var ls: Array = p["lines"]
	check(float(p["speed"]) == 55.0 and ls.size() == 5 and ls[0]["text"] == "TITEL" and ls[2]["text"] == "NAME Č"
		and ls[2]["style"] == "TICZ" and ls[4].get("cols", []) == ["A", "B", "C"],
		"Mitwirkende: Parser (Zeilennummer/Anführungszeichen entfernt, Stile, <SPEED>, drei Spalten)", str(p))
	var reb: Array = menu.rebuild_credits()
	var reb_txt := " ".join(reb.map(func(e): return String(e["text"])))
	check(reb_txt.contains("Dangerous and Hidden 2 (unofficial)") and reb_txt.contains("neu erstellt mit Claude Opus")
		and reb_txt.contains("Inoffizieller Fan-Nachbau"), "Mitwirkende: Abschnitt inoffizieller Nachbau (Claude Opus)", reb_txt)
	var path: String = menu._menu_dir + "/credits.txt"
	var have_orig := FileAccess.file_exists(path)
	var orig_lines: Array = []
	if have_orig:
		orig_lines = menu.parse_credits(FileAccess.get_file_as_string(path))["lines"]
	var clean := true
	for e in orig_lines:
		var t := String(e["text"])
		clean = clean and not t.contains("<") and not t.begins_with("1\t") and not t.ends_with("\"")
	check(not have_orig or (orig_lines.size() > 500 and clean), "Mitwirkende: Originalliste aus orig_cache vollständig gelesen",
		"%s: %d Zeilen" % [path, orig_lines.size()])
	menu.show_menu("main_menu")
	await frames(2)
	menu._show_credits()
	await frames(3)
	var content: Control = menu.credits_content
	check(content != null and content.get_child_count() > (400 if have_orig else 5) and menu.credits_height > 768.0,
		"Mitwirkende: Rolltext aufgebaut", "%d Zeilen, Höhe %.0f" % [content.get_child_count() if content else 0, menu.credits_height])
	var y0: float = content.position.y if content else 0.0
	await get_tree().create_timer(0.5).timeout
	check(content != null and is_instance_valid(content) and content.position.y < y0, "Mitwirkende: Text rollt nach oben")
	menu._close_credits()
	await frames(2)
	check(not is_instance_valid(menu._credits_root), "Mitwirkende: Abbruch kehrt ins Hauptmenü zurück")
