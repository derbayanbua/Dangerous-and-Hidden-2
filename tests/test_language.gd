extends "res://tests/test_gameplay.gd"
## B-007 Weitere Sprachen: Sprachwahl im Optionsmenü, Originaltexte je Sprache (orig_cache/texts_<sprache>.json aus
## D:\Workspace_D\tools\convert_mission.py --texts), eigene Oberflächentexte über Godot-Übersetzungen
## (locale/ui_texts.csv), Missionsziele und _IsLanguageVersion in der gewählten Sprache.
##   tools\godot.cmd --headless -- --autoplay=test_language --profiles_dir=user://test_language --noimport
## Ohne Originaltexte (frischer Klon ohne orig_cache) werden nur die eigenen Übersetzungen geprüft.


func _json(lang: String) -> Dictionary:
	var f := FileAccess.open(Settings.texts_path(lang), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _label_with(root: Node, txt: String) -> Label:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text == txt:
			return l
	return null


func _run() -> void:
	await frames(10)
	var menu := get_tree().current_scene
	var de := _json("german")
	var en := _json("english")
	var have_orig := not de.is_empty() and not en.is_empty()

	# --- verfügbare Sprachen ---
	var avail := Settings.available_languages()
	check(avail.has("german"), "Deutsch immer verfügbar", str(avail))
	check(not avail.has("japan"), "Japanisch nicht angeboten (Installation nur TEXTY_DD)")
	if have_orig:
		check(avail.has("english") and avail.size() >= 2, "Mindestens Deutsch/Englisch aus der Installation", str(avail))
		for l in Settings.LANGUAGES:
			check(avail.has(l[0]) == FileAccess.file_exists(Settings.texts_path(l[0])) or l[0] == "german",
				"Sprache %s angeboten ⇔ texts-Datei vorhanden" % l[0])

	# --- Umschalten Deutsch → Englisch: Originaltexte, Locale, eigene Texte ---
	Settings.set_language("german")
	var d := Settings.orig_texts()
	check(TranslationServer.get_locale().begins_with("de"), "Deutsch: Locale de", TranslationServer.get_locale())
	check(tr("FPS ANZEIGEN") == "FPS ANZEIGEN", "Deutsch: eigene Texte unverändert")
	if have_orig:
		check(String(d.get("2462", "")) == String(de["2462"]), "Deutsch: Originaltext 2462", String(d.get("2462", "")))
	var changed := [0]
	Settings.language_changed.connect(func(): changed[0] += 1)
	Settings.set_language("english" if avail.has("english") else "german")
	check(changed[0] == 1, "Signal language_changed")
	check(is_same(d, Settings.orig_texts()), "Originaltexte: dieselbe Instanz (Halter sehen die Umschaltung)")
	if have_orig:
		check(Settings.language == "english", "Sprache englisch gesetzt")
		check(String(d.get("2462", "")) == String(en["2462"]) and String(en["2462"]) != String(de["2462"]),
			"Englisch: Originaltext 2462 aus texts_english.json", String(d.get("2462", "")))
		check(TranslationServer.get_locale().begins_with("en"), "Englisch: Locale en", TranslationServer.get_locale())
		check(tr("FPS ANZEIGEN") == "SHOW FPS" and tr("SPRACHE:") == "LANGUAGE:", "Englisch: eigene Texte übersetzt",
			tr("FPS ANZEIGEN"))
		check(SAS.text(2462) == String(en["2462"]), "SAS.text liefert die gewählte Sprache")
		var k := int(Game.MISSIONS["a1_blizzard"].get("k", 0))
		check(String(Game.MISSIONS["a1_blizzard"]["title"]) == String(en[str(4501 + 10 * k)]),
			"Missionstitel neu angemeldet (englisch)", String(Game.MISSIONS["a1_blizzard"]["title"]))
		check(Game.briefing_text("a1_blizzard").contains(String(en[str(4501 + 10 * k)])), "Briefingtext englisch")

	# --- Optionsmenü: Seite SPIEL mit Sprachwahl ---
	if menu and menu.has_method("show_menu"):
		menu.options_page = "game"
		menu.show_menu("options")
		await frames(2)
		var bl := menu.find_child("blanguage", true, false) as Button
		check(bl != null, "Optionen SPIEL: Knopf SPRACHE vorhanden")
		if bl and have_orig:
			check(bl.text == "LANGUAGE: English (UK)", "Knopf zeigt englische Beschriftung", bl.text)
			check(_label_with(menu, String(en["2462"])) != null, "Menü: Originaltext UNTERTITEL englisch", String(en["2462"]))
			var fps := _label_with(menu, "FPS ANZEIGEN")
			check(fps != null and fps.atr(fps.text) == "SHOW FPS", "Menü: eigener Text automatisch übersetzt")
			var nxt := avail[(avail.find("english") + 1) % avail.size()]
			bl.pressed.emit()
			await frames(2)
			check(Settings.language == nxt, "Klick auf SPRACHE schaltet weiter", "%s → %s" % [nxt, Settings.language])
			var bl2 := menu.find_child("blanguage", true, false) as Button
			check(bl2 != null and bl2.text.ends_with(Settings.language_name()), "Menü neu aufgebaut", bl2.text if bl2 else "")
		if avail.has("czech"):
			Settings.set_language("czech")
			menu.show_menu("options")
			await frames(2)
			var cz := _json("czech")
			check(String(Settings.orig_texts().get("2462", "")) == String(cz["2462"]) and String(cz["2462"]).contains("TITUL"),
				"Tschechisch (cp1250): Originaltext", String(cz["2462"]))
			check(tr("SPRACHE:") == "JAZYK:", "Tschechisch: eigene Texte übersetzt")
			var lb := menu.find_child("blanguage", true, false) as Button
			check(lb != null and lb.text == "JAZYK: Čeština", "Tschechisch: Sprachknopf", lb.text if lb else "")

	# --- Missionsziele und _IsLanguageVersion in der Mission ---
	if have_orig and DirAccess.dir_exists_absolute(OrigLevel.cache_root() + "/arctic1"):
		Settings.set_language("english")
		Game.start_mission("a1_blizzard")
		var m: Mission = null
		for i in 6000:
			await get_tree().process_frame
			m = Game.current_mission() as Mission
			if m and m.objectives.size() > 0 and m.find_child("LsRuntime", true, false):
				break
		check(m != null and m.objectives.size() > 0, "Mission a1_blizzard geladen (englisch)")
		if m and m.objectives.size() > 0:
			var all_en := true
			var any_diff := false
			for o in m.objectives:
				var key := ""
				for kk in en:
					if String(en[kk]) == o.text:
						key = String(kk)
						break
				if key == "":
					all_en = false
				elif String(de.get(key, "")) != o.text:
					any_diff = true
			check(all_en and any_diff, "Missionsziele in englischer Originalfassung", m.objectives[0].text)
			var rt = m.find_child("LsRuntime", true, false)
			var vm := LsVM.new(LsCompiler.new(), null, rt)
			check(int(rt.call_api(vm, "_ISLANGUAGEVERSION", [["str", "English"]])) == 1
				and int(rt.call_api(vm, "_ISLANGUAGEVERSION", [["str", "German"]])) == 0,
				"_IsLanguageVersion(\"English\") = 1, (\"German\") = 0")
			Settings.set_language("german")
			check(int(rt.call_api(vm, "_ISLANGUAGEVERSION", [["str", "German"]])) == 1, "_IsLanguageVersion folgt der Umschaltung")
			check(OrigAudio.speech_file(1001) == OrigAudio.german_file(1001), "Sprachausgabe deutsch")
			Settings.set_language("english")
			var sf := OrigAudio.speech_file(91157001)
			check(sf == OrigAudio.german_file(91157001) or FileAccess.file_exists(OrigLevel.cache_root() + "/sounds/" + sf),
				"Sprachausgabe englisch nur falls vorhanden, sonst deutsch", sf)
	Settings.set_language("german")
	_finish()
