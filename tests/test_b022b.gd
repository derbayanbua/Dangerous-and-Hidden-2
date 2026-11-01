extends "res://tests/test_gameplay.gd"
## B-022 Teil b (F-011 … F-018): Profil-Testbasis, Profilordner-Kollision, kaputte Spielstände, atomares
## Speichern, Tastenbelegung zurücksetzen, T-Doppelbelegung, VSync-Migration, Gammakurve.
##   tools\godot.cmd --headless -- --autoplay=test_b022b --profiles_dir=user://test_b022b --noimport


func _run() -> void:
	await frames(5)
	_profiles_base()
	_profile_collision()
	_broken_saves()
	_atomic_save()
	_keys_reset()
	_t_key()
	_vsync_migration()
	_gamma()
	_bak_fallback()
	_save_versions()
	_settings_sanitize()
	_finish()


func _good_save(marker: String, version := 3) -> String:
	var d := {"mission": "m01_funkfeuer", "mode": 0, "single": false, "title": marker,
		"state": {"squad": {}, "enemies": {}, "interactables": {}, "objectives": {}, "marker": marker}}
	if version > 0:
		d["version"] = version
	return JSON.stringify(d)


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## B-027 / M-021: .bak-/.tmp-Rückfall beim Laden
func _bak_fallback() -> void:
	DirAccess.make_dir_recursive_absolute(Game.save_dir())
	var slot := "bak_test"
	var p := Game.save_path(slot)
	Game.delete_save(slot)
	Game.write_file_atomic(p, _good_save("A"))
	Game.write_file_atomic(p, _good_save("B"))
	var r := Game.read_save(slot)
	check(r["source"] == "main" and r["data"]["state"]["marker"] == "B", "M-021: intakte Hauptdatei gewinnt", str(r["source"]))
	# Hauptdatei beschädigt → .bak, Hauptdatei repariert
	_put(p, "{ kaputt")
	r = Game.read_save(slot)
	check(r["error"] == "" and r["source"] == "bak" and r["data"]["state"]["marker"] == "A", "M-021: beschädigte Hauptdatei → .bak",
		"%s %s" % [r["source"], r["error"]])
	check(JSON.parse_string(FileAccess.get_file_as_string(p)) is Dictionary, "M-021: Hauptdatei aus .bak repariert")
	# Abbruch zwischen remove(path) und rename(tmp → path): nur .bak + .tmp vorhanden
	Game.delete_save(slot)
	_put(p + ".bak", _good_save("ALT"))
	_put(p + ".tmp", _good_save("NEU"))
	check(not FileAccess.file_exists(p) and Game.has_save(slot), "M-021: Abbruch mitten im Speichern – has_save erkennt Rückfalldateien")
	var listed := false
	for s in Game.list_saves():
		listed = listed or s["slot"] == slot
	check(listed, "M-021: Abbruch mitten im Speichern – Slot weiter in list_saves")
	r = Game.read_save(slot, false)
	check(r["source"] == "bak" and r["data"]["state"]["marker"] == "ALT", "M-021: Abbruch → .bak geladen", str(r["source"]))
	check(not FileAccess.file_exists(p), "M-021: repair=false schreibt nichts")
	# .bak kaputt → .tmp (vollständig geschrieben und zurückgelesen)
	_put(p + ".bak", "x")
	r = Game.read_save(slot)
	check(r["source"] == "tmp" and r["data"]["state"]["marker"] == "NEU" and FileAccess.file_exists(p), "M-021: .bak kaputt → .tmp, repariert",
		str(r["source"]))
	# alles kaputt → sauberer Fehler, kein Laden
	_put(p, "x")
	_put(p + ".bak", "y")
	_put(p + ".tmp", "z")
	var scene := get_tree().current_scene
	check(not Game.load_game(slot) and Game.last_load_error != "" and Game.pending_load.is_empty()
		and get_tree().current_scene == scene, "M-021: alle Dateien kaputt → sauber abgewiesen", Game.last_load_error)
	Game.delete_save(slot)
	check(not Game.has_save(slot) and not FileAccess.file_exists(p + ".tmp") and not FileAccess.file_exists(p + ".bak"),
		"M-021: delete_save entfernt auch .bak/.tmp")


## B-027 / M-022: Versionsnummer, Migration, Inhaltsprüfung
func _save_versions() -> void:
	check(Game.SAVE_VERSION == 3, "M-022: SAVE_VERSION 3", str(Game.SAVE_VERSION))
	# v1 (ohne Versionsfeld, ohne Hauptlisten) → migriert, fremder Schlüssel (AP-1 Skriptzustand) bleibt
	var d1 := {"mission": "m01_funkfeuer", "state": {"orig_script": {"pc": 7}}}
	check(Game.validate_save_data(d1) == "" and int(d1["version"]) == 3 and int(d1["migrated_from"]) == 1
		and d1["state"]["squad"] is Dictionary and d1["mode"] == 0 and d1["single"] == false, "M-022: v1 → v3 migriert", str(d1))
	check(d1["state"].get("orig_script", {}).get("pc") == 7, "M-022: fremder state-Schlüssel bleibt erhalten")
	var d2 := {"version": 2, "mission": "m01_funkfeuer", "state": {"squad": {}}}
	check(Game.validate_save_data(d2) == "" and int(d2["version"]) == 3 and d2["state"].has("objectives"), "M-022: v2 → v3 migriert")
	var d3: Dictionary = JSON.parse_string(_good_save("C"))
	check(Game.validate_save_data(d3) == "" and not d3.has("migrated_from"), "M-022: v3 unverändert")
	# neuere Version sauber ablehnen – auch wenn eine ältere .bak existiert
	var why := Game.validate_save_data(JSON.parse_string(_good_save("X", 99)))
	check(why.begins_with("neuere Spielstandversion"), "M-022: v99 abgelehnt", why)
	var slot := "ver_test"
	var p := Game.save_path(slot)
	Game.delete_save(slot)
	_put(p, _good_save("ZUKUNFT", 99))
	_put(p + ".bak", _good_save("ALT"))
	check(not Game.load_game(slot) and Game.last_load_error.begins_with("neuere") and Game.pending_load.is_empty()
		and FileAccess.get_file_as_string(p).contains("ZUKUNFT"), "M-022: neuere Version nicht durch .bak überschrieben", Game.last_load_error)
	Game.delete_save(slot)
	check(Game.validate_save_data({"version": 0, "mission": "m01_funkfeuer", "state": {}}) != "", "M-022: Version 0 abgelehnt")
	# Inhalt von state
	var bad := {
		"squad_entry": {"squad": {"s1": 5}},
		"enemies_type": {"enemies": [1]},
		"brain": {"enemies": {"e1": {"brain": "x"}}},
		"objective": {"objectives": {"o1": "fertig"}},
		"alarm": {"alarm": "ja"},
		"active": {"active": "eins"},
		"stats": {"stats": 3},
	}
	for k in bad:
		var st: Dictionary = {"squad": {}, "enemies": {}, "interactables": {}, "objectives": {}}
		st.merge(bad[k], true)
		var e := Game.validate_save_data({"version": 3, "mission": "m01_funkfeuer", "state": st})
		check(e != "", "M-022: state-Fehler %s erkannt" % k, e)
	var miss := Game.validate_save_data({"version": 3, "mission": "m01_funkfeuer", "state": {"squad": {}}})
	check(miss.contains("fehlt"), "M-022: v3 ohne Pflichtliste abgelehnt", miss)


## B-027 / M-024: kaputte settings.cfg-Werte typgeprüft und geklemmt
const _SET_KEYS := ["resolution", "fullscreen", "quality", "render_scale", "fov", "mouse_sensitivity", "invert_y",
	"master_volume", "music_volume", "sfx_volume", "speech_volume", "gamma", "shadows", "blood", "blood_level",
	"vsync_mode", "max_fps", "aa_mode", "texture_quality", "anisotropy", "voice_volume", "connection_type", "language"]

func _settings_sanitize() -> void:
	var snap := {}
	for k in _SET_KEYS:
		snap[k] = Settings.get(k)
	var c := ConfigFile.new()
	c.set_value("display", "resolution", Vector2i(-5, 3))
	c.set_value("display", "fullscreen", "ja")
	c.set_value("graphics", "quality", 99)
	c.set_value("graphics", "render_scale", 7.0)
	c.set_value("graphics", "fov", "weit")
	c.set_value("graphics", "gamma", -2)
	c.set_value("graphics", "blood_level", 9)
	c.set_value("audio", "master_volume", 5.0)
	c.set_value("audio", "music_volume", -1)
	c.set_value("audio", "sfx_volume", "laut")
	c.set_value("setup", "vsync_mode", "an")
	c.set_value("setup", "texture_quality", -3)
	c.set_value("setup", "aa_mode", 3.0)
	c.set_value("setup", "anisotropy", 42)
	c.set_value("setup", "max_fps", -60)
	c.set_value("setup", "language", "klingonisch")
	c.set_value("multiplayer", "connection_type", 17)
	c.set_value("multiplayer", "voice_volume", 3)
	Settings.fov = 70.0
	Settings.fullscreen = true
	Settings.sfx_volume = 0.9
	Settings.vsync_mode = 1
	Settings.load_from_config(c)
	check(Settings.resolution == Vector2i.ZERO, "M-024: unsinnige Auflösung → Desktop", str(Settings.resolution))
	check(Settings.fullscreen == true and Settings.fov == 70.0 and is_equal_approx(Settings.sfx_volume, 0.9),
		"M-024: falscher Typ → Wert bleibt", "%s %s %s" % [Settings.fullscreen, Settings.fov, Settings.sfx_volume])
	check(Settings.quality == Settings.QUALITY_NAMES.size() - 1 and Settings.blood_level == 2 and Settings.texture_quality == 0
		and Settings.anisotropy == 4 and Settings.aa_mode == 3 and Settings.vsync_mode == 1 and Settings.connection_type == 4,
		"M-024: Menüindizes geklemmt", "q%d b%d t%d a%d aa%d v%d c%d" % [Settings.quality, Settings.blood_level,
		Settings.texture_quality, Settings.anisotropy, Settings.aa_mode, Settings.vsync_mode, Settings.connection_type])
	check(Settings.master_volume == 1.0 and Settings.music_volume == 0.0 and Settings.voice_volume == 1.0,
		"M-024: Lautstärken 0…1")
	check(Settings.render_scale == 1.0 and is_equal_approx(Settings.gamma, 0.6) and Settings.max_fps == 0,
		"M-024: Renderskalierung/Gamma/Bildrate geklemmt")
	check(Settings.language == "german", "M-024: unbekannte Sprache → Deutsch", Settings.language)
	# Optionsseiten mit ungeklemmten Werten (direkt gesetzt) dürfen nicht abstürzen
	var mm = load("res://src/ui/main_menu.gd")
	check(mm._pick(Settings.VSYNC_NAMES, 9) == "DREIFACHPUFFER" and mm._pick(Settings.BLOOD_NAMES, -4) == "AUS",
		"M-024: Menü klemmt Listenindizes")
	for k in _SET_KEYS:
		Settings.set(k, snap[k])


func _profiles_base() -> void:
	check(Game.profiles_dir == "user://test_b022b", "F-011: Testordner user://test_b022b angenommen", Game.profiles_dir)
	for ok in ["user://test_ui_flow", "user://test_profiles", "user://test_x/unter"]:
		check(Game.is_test_profiles_dir(ok), "F-011: erlaubt %s" % ok)
	for bad in ["user://profiles", "user://", "user://test", "user://blut", "user://test_a/../profiles",
			"C:/Users", "res://test_x", "user:///test_x", "user://test_a\\..\\x", "D:/Workspace_D"]:
		check(not Game.is_test_profiles_dir(bad), "F-011: abgelehnt %s" % bad)


func _profile_collision() -> void:
	# Altbestand: Ordner, dessen bereinigter Name auch zu einem neuen Profil passen würde
	var legacy := Game.profiles_dir + "/B_"
	DirAccess.make_dir_recursive_absolute(legacy + "/saves")
	var lf := FileAccess.open(legacy + "/profile.json", FileAccess.WRITE)
	lf.store_string(JSON.stringify({"name": "B?", "difficulty": 3, "marker": "alt"}))
	lf.close()
	check(Game.create_profile("A?", 2), "F-012: Profil „A?“ angelegt")
	check(Game.create_profile("A*", 3), "F-012: Profil „A*“ angelegt (gleicher bereinigter Name)")
	var da := Game.profile_dir("A?")
	var db := Game.profile_dir("A*")
	check(da != db, "F-012: getrennte Ordner", "%s | %s" % [da, db])
	check(Game.create_profile("B*", 2), "F-012: Profil „B*“ neben Altordner B_")
	check(Game.profile_dir("B*") != legacy and Game.profile_dir("B?") == legacy, "F-012: Altordner bleibt bei „B?“",
		Game.profile_dir("B*"))
	var lp = JSON.parse_string(FileAccess.get_file_as_string(legacy + "/profile.json"))
	check(typeof(lp) == TYPE_DICTIONARY and lp.get("marker") == "alt", "F-012: Altprofil nicht überschrieben")
	var all := Game.list_profiles()
	check(all.has("A?") and all.has("A*") and all.has("B?") and all.has("B*"), "F-012: alle vier Profile gelistet", str(all))
	check(Game.select_profile("A?") and Game.difficulty() == 2, "F-012: „A?“ lädt eigene Daten")
	check(Game.select_profile("A*") and Game.difficulty() == 3, "F-012: „A*“ lädt eigene Daten")
	check(Game.select_profile("B?") and Game.difficulty() == 3, "F-012: Altprofil „B?“ weiter ladbar")
	check(Game.rename_profile("A*", "A/") and Game.profile_dir("A/") != da, "F-012: Umbenennen kollidiert nicht",
		Game.profile_dir("A/"))
	check(Game.select_profile("A?") and Game.difficulty() == 2, "F-012: „A?“ nach Umbenennen unverändert")


func _broken_saves() -> void:
	DirAccess.make_dir_recursive_absolute(Game.save_dir())
	var cases := {
		"b_text": "kein json {",
		"b_array": "[1, 2, 3]",
		"b_nostate": JSON.stringify({"mission": "m01_funkfeuer"}),
		"b_statetype": JSON.stringify({"mission": "m01_funkfeuer", "state": "x"}),
		"b_mission": JSON.stringify({"mission": 5, "state": {}}),
		"b_unknown": JSON.stringify({"mission": "gibt_es_nicht", "state": {}}),
		"b_mode": JSON.stringify({"mission": "m01_funkfeuer", "state": {}, "mode": "x"}),
		"b_diary": JSON.stringify({"mission": "m01_funkfeuer", "state": {"_diary": 3}}),
		"b_cut": JSON.stringify({"mission": "m01_funkfeuer", "state": {"a": 1}}).substr(0, 30),
	}
	var scene := get_tree().current_scene
	for slot in cases:
		var f := FileAccess.open(Game.save_path(slot), FileAccess.WRITE)
		f.store_string(cases[slot])
		f.close()
		var ok := Game.load_game(slot)
		check(not ok and Game.last_load_error != "" and Game.pending_load.is_empty(),
			"F-013: %s sauber abgewiesen" % slot, Game.last_load_error)
		check(FileAccess.file_exists(Game.save_path(slot)), "F-013: %s bleibt unangetastet" % slot)
		Game.delete_save(slot)
	check(get_tree().current_scene == scene, "F-013: kein Szenenwechsel bei kaputten Spielständen")
	check(Game.validate_save_data({"mission": "m01_funkfeuer", "state": {}, "mode": 0, "single": false}) == "",
		"F-013: gültige Struktur angenommen")


func _atomic_save() -> void:
	var p := Game.profiles_dir + "/atomic.json"
	for s in [p, p + ".bak", p + ".tmp"]:
		DirAccess.remove_absolute(s)
	check(Game.write_file_atomic(p, "eins") == OK and FileAccess.get_file_as_string(p) == "eins", "F-014: erstes Schreiben")
	check(not FileAccess.file_exists(p + ".bak") and not FileAccess.file_exists(p + ".tmp"), "F-014: ohne Altstand keine .bak/.tmp")
	check(Game.write_file_atomic(p, "zwei") == OK and FileAccess.get_file_as_string(p) == "zwei", "F-014: Ersetzen einer vorhandenen Datei (Windows-rename)")
	check(FileAccess.get_file_as_string(p + ".bak") == "eins", "F-014: .bak enthält den alten Stand")
	check(not FileAccess.file_exists(p + ".tmp"), "F-014: keine .tmp übrig")
	# liegengebliebene .tmp (abgebrochener Lauf) stört nicht
	var t := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	t.store_string("halb")
	t.close()
	check(Game.write_file_atomic(p, "drei") == OK and FileAccess.get_file_as_string(p) == "drei"
		and FileAccess.get_file_as_string(p + ".bak") == "zwei", "F-014: Schreiben über liegengebliebene .tmp")
	# Ziel nicht schreibbar (Ordner fehlt) → Fehler, nichts angelegt
	check(Game.write_file_atomic(Game.profiles_dir + "/fehlt/x.json", "y") != OK, "F-014: Fehler wird gemeldet")


func _keys_reset() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "veraltete_aktion", KEY_P)
	cfg.set_value("graphics", "gamma", 1.2)
	# soldier_1 frei belegen und speichern
	InputMap.action_erase_events("soldier_1")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_P
	InputMap.action_add_event("soldier_1", k)
	InputSetup.write_keys(cfg)
	check(cfg.get_value("keys", "soldier_1") == KEY_P, "F-015: freie Belegung gespeichert")
	check(not cfg.has_section_key("keys", "veraltete_aktion"), "F-015: veraltete Aktion entfernt")
	check(cfg.get_value("graphics", "gamma") == 1.2, "F-015: andere Sektionen bleiben")
	# Standard wiederherstellen → speichern → „Neustart“ (laden)
	InputSetup.read_keys(null)
	InputSetup.write_keys(cfg)
	check(String(cfg.get_value("keys", "soldier_1")) == InputSetup.UNBOUND, "F-015: unbelegt gespeichert",
		str(cfg.get_value("keys", "soldier_1")))
	var path := Game.profiles_dir + "/keys_test.cfg"
	cfg.save(path)
	var cfg2 := ConfigFile.new()
	cfg2.load(path)
	InputSetup.read_keys(cfg2)
	check(InputMap.action_get_events("soldier_1").is_empty(), "F-015: zurückgesetzte Belegung kommt nach Neustart nicht wieder")
	check(InputSetup.binding_text("select_soldier_1") == OS.get_keycode_string(KEY_F1)
		and InputSetup.binding_text("fire_mode") == "MMT" and InputSetup.binding_text("binoculars") == "B"
		and InputSetup.binding_text("equip_8") == "8", "F-015: Vorgaben F1–F4/1–8/B/MMT unverändert")
	# B-015: neue Aktionen werden vollständig geschrieben; ältere Datei (Stand 3, ohne neue Schlüssel) → Standard
	check(cfg.has_section_key("keys", "tac_zoom_in") and String(cfg.get_value("keys", "jump")) == InputSetup.UNBOUND
		and cfg.get_value("keys", "game_info") == KEY_COMMA and int(cfg.get_value("meta", "keys_version")) == InputSetup.KEYS_VERSION,
		"B-015: neue Aktionen im Neuaufbau der Sektion keys")
	var old := ConfigFile.new()
	old.set_value("meta", "keys_version", 3)
	old.set_value("keys", "reload", KEY_P)
	InputSetup.read_keys(old)
	check(InputSetup.binding_text("game_info") == OS.get_keycode_string(KEY_COMMA) and InputSetup.binding_text("reload") == "P"
		and InputMap.action_get_events("speed_up").is_empty(), "B-015: alte Belegung behält eigene Tasten, neue Aktionen mit Standard")
	InputSetup.read_keys(null)


func _t_key() -> void:
	check(InputSetup.binding_text("order_grenade") == "T" and InputSetup.binding_text("chat_all") == "T",
		"F-016: T = order_grenade (Einzelspieler) und chat_all (Original, Mehrspieler)")
	var src := FileAccess.get_file_as_string("res://src/ui/mp_hud.gd")
	check(src.contains("if not Net.is_online:") and src.contains("open_input(\"all\")"),
		"F-016: chat_all nur online (MpHud._input verbraucht das Ereignis)")
	check(not Net.is_online, "F-016: offline geht T an den Granatbefehl")


func _vsync_migration() -> void:
	var c1 := ConfigFile.new()
	c1.set_value("display", "vsync", false)
	check(Settings.migrate_vsync(c1, 1) == 0 and not c1.has_section_key("display", "vsync")
		and c1.get_value("setup", "vsync_mode") == 0, "F-017: Altfeld vsync=false → vsync_mode 0, Altfeld entfernt")
	var c2 := ConfigFile.new()
	c2.set_value("display", "vsync", false)
	c2.set_value("setup", "vsync_mode", 2)
	check(Settings.migrate_vsync(c2, 1) == 2 and not c2.has_section_key("display", "vsync"),
		"F-017: vorhandener vsync_mode gewinnt")
	var c3 := ConfigFile.new()
	check(Settings.migrate_vsync(c3, 3) == 3, "F-017: ohne Einträge bleibt der Standard")
	check(Settings.migrate_vsync(c1, 1) == 0, "F-017: Migration einmalig (zweiter Lauf ändert nichts)")
	var old := Settings.vsync_mode
	Settings.vsync_mode = 2
	check(Settings.vsync, "F-017: vsync folgt vsync_mode")
	Settings.vsync = true
	check(Settings.vsync_mode == 2, "F-017: vsync=true behält adaptiv")
	Settings.vsync = false
	check(Settings.vsync_mode == 0, "F-017: vsync=false → AUS")
	Settings.vsync = true
	check(Settings.vsync_mode == 1, "F-017: vsync=true → AN")
	Settings.vsync_mode = old


func _gamma() -> void:
	check(absf(Settings.gamma_curve(0.5, 2.0) - sqrt(0.5)) < 1e-4, "F-018: Gammakurve 0,5^(1/2)")
	check(Settings.gamma_curve(0.0, 1.6) == 0.0 and absf(Settings.gamma_curve(1.0, 0.6) - 1.0) < 1e-6,
		"F-018: Schwarz/Weiß bleiben fest")
	var old := Settings.gamma
	Settings.gamma = 1.5
	var env := Environment.new()
	Settings.apply_to_world(env, null)
	var lut := env.adjustment_color_correction as ImageTexture
	check(env.adjustment_brightness == 1.0 and lut != null, "F-018: Helligkeit neutral, LUT gesetzt")
	if lut:
		var v := lut.get_image().get_pixel(128, 0).r
		check(absf(v - Settings.gamma_curve(128.0 / 255.0, 1.5)) < 0.01, "F-018: LUT = Gammakurve", str(v))
	Settings.gamma = old
	Settings.apply_to_world(env, null)
