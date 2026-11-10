extends "res://tests/lan_ui_base.gd"
## 0.10.3: Konfigurationsmenü des dedizierten Servers (src/ui/dedicated_server_screen.gd):
## Knopf im Mehrspieler-Menü, Reiter/Felder für alle Net.RULE_KEYS, Kartenwähler ohne Arena-/eigene Karten,
## cfg speichern/laden (Rundlauf), Server per Menü als eigener kopfloser Prozess starten, Abfrage auf Port+1
## beantwortet, Konsole über die Pipe, Stoppen; eigenständiges Fenster (--server_config).
##   tools\godot.cmd --headless -- --autoplay=test_dedicated_ui --profiles_dir=user://test_ded_ui --noimport

const DPORT := 11071


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		if _scr and _scr.server_pid > 0 and OS.is_process_running(_scr.server_pid):
			OS.kill(_scr.server_pid)
		_finish())
	_run.call_deferred()


var _scr: DedicatedServerScreen


func _cfg_dir() -> String:
	var d := ProjectSettings.globalize_path("res://test_output/ded_ui_cfgs")
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	return d


func _run() -> void:
	await frames(20)
	var dir := _cfg_dir()
	# --- Knopf im Mehrspieler-Menü ---
	var lan := LanMenu.new()
	lan.name = "LanMenuTest"
	get_tree().root.add_child(lan)
	lan.open()
	await frames(3)
	var btn := lan.find_child("DedicatedConfigButton", true, false) as Button
	check(btn != null and btn.text != "", "Mehrspieler-Menü: Knopf DEDIZIERTER SERVER", btn.text if btn else "")
	var grid_ok := btn != null and lan.find_child("ServerScroll", true, false) != null
	check(grid_ok, "Knopf unter dem Formular (Originalfelder unverändert)")
	if btn:
		btn.pressed.emit()
		await frames(3)
	check(lan.dedicated_screen != null and lan.dedicated_screen.is_inside_tree(), "Knopf öffnet das Konfigurationsmenü")
	if lan.dedicated_screen:
		lan.dedicated_screen.back_requested.emit()
		await frames(2)
	Net.stop_browse()
	lan.queue_free()
	await frames(2)
	# --- Menü mit Testordner ---
	_scr = DedicatedServerScreen.new()
	_scr.configs_dir = dir
	get_tree().root.add_child(_scr)
	_scr.open()
	await frames(3)
	check(_scr.tabs.get_tab_count() == 6, "Reiter ALLGEMEIN/REGELN/ERWEITERT/KOOPERATIV/ERGÄNZUNGEN/SERVER", str(_scr.tabs.get_tab_count()))
	check(FileAccess.file_exists(dir.path_join("Default.cfg")), "Default.cfg angelegt (wie ServerLauncher)")
	var all_rules := true
	for k in Net.RULE_KEYS:
		if not _scr.rule_controls.has(k):
			all_rules = false
			print("fehlt: ", k)
	check(all_rules, "Feld für jede Regel aus Net.RULE_KEYS (%d)" % Net.RULE_KEYS.size())
	# --- Kartenwähler: keine Arena-/eigenen Karten ---
	var arena_free := true
	for m in Net.MODE_NAMES.size():
		_scr.style_option.select(m)
		_scr._apply_style_defaults()
		for i in _scr.avail_list.item_count:
			var e: Dictionary = Game.MISSIONS.get(String(_scr.avail_list.get_item_metadata(i)), {})
			if e.get("mp_mode") == null or String(e.get("orig", "")) == "":
				arena_free = false
	check(arena_free, "Kartenwähler ohne Arena- und eigene Karten (alle Stile)")
	_scr.style_option.select(0)
	_scr._apply_style_defaults()
	var dm := DedicatedServerScreen.style_maps(0)
	check(dm.size() >= 2, "Deathmatch-Karten verfügbar", str(dm.size()))
	check(int((_scr.rule_controls["respawn_s"] as SpinBox).value) == int(Net.style_defaults(0)["respawn_s"]), "Stil-Standards übernommen")
	# --- Werte setzen (über die Steuerelemente) ---
	_scr.session_edit.text = "UI-Test"
	_scr.port_spin.value = DPORT
	_scr.password_edit.text = ""
	_scr.admin_login_edit.text = "chef"
	_scr.admin_pass_edit.text = "geheim"
	_scr.internet_check.button_pressed = false
	_scr.set_play_maps([])
	_scr.avail_list.select(1)
	_scr.add_selected_maps()
	_scr.avail_list.deselect_all()
	_scr.avail_list.select(0)
	_scr.add_selected_maps()
	_scr.play_list.select(1)
	_scr.move_selected_map(-1)            # Reihenfolge: dm[0], dm[1]
	check(_scr.play_maps() == [dm[0], dm[1]], "Kartenliste -> / AUF", str(_scr.play_maps()))
	var setv := {"bots_per_team": 1, "warmup_s": 0, "max_players": 10, "score_limit": 0, "time_limit_min": 0,
		"friendly_fire": true, "kill_cam": false, "precise_aim": true, "coop_lives": 7, "max_ping": 500, "support_strike": 2,
		"flood_protect": false, "inverse_damage": 50}
	for k in setv:
		_scr._set_rule_value(k, setv[k])
	var want := _scr.settings()
	check(_scr.save_config("ui_test"), "cfg gespeichert")
	var path := dir.path_join("ui_test.cfg")
	var txt := FileAccess.get_file_as_string(path)
	check(txt.contains("sessionname \"UI-Test\"") and txt.contains("bots 1") and txt.contains("port %d" % DPORT)
		and txt.contains("mapname " + dm[0]) and txt.strip_edges().ends_with("server"), "cfg im Konsolenformat (HD2DS)", path)
	var all_keys := true
	for k in Net.RULE_KEYS:
		if not txt.contains("\n%s " % Net.RULE_KEYS[k]):
			all_keys = false
	check(all_keys, "Alle Regel-Schlüsselwörter in der cfg")
	# --- Rundlauf: anderes Formular, dann laden ---
	_scr.new_config("andere")
	check(_scr.current_name == "andere" and _scr.session_edit.text != "UI-Test", "Neue Konfiguration setzt das Formular zurück")
	check(_scr.config_list.item_count >= 3, "Konfigurationsliste (Default, andere, ui_test)", str(_scr.config_list.item_count))
	check(_scr.load_config("ui_test"), "cfg geladen")
	var got := _scr.settings()
	var diff: PackedStringArray = []
	for k in want:
		if str(want[k]) != str(got.get(k)):
			diff.append("%s: %s != %s" % [k, str(want[k]), str(got.get(k))])
	check(diff.is_empty(), "Rundlauf speichern → laden identisch", ", ".join(diff))
	var parsed := DedicatedServerScreen.parse_config(LanMenu.config_text(want))
	var pdiff: PackedStringArray = []
	for k in Net.RULE_KEYS:
		if str(parsed.get(k)) != str(want[k]):
			pdiff.append(k)
	check(pdiff.is_empty(), "parse_config(config_text) für alle Regeln", ", ".join(pdiff))
	_scr.duplicate_config("kopie")
	check(FileAccess.get_file_as_string(dir.path_join("kopie.cfg")) == txt, "DUPLIZIEREN kopiert die Werte")
	_scr.delete_config("kopie")
	check(not FileAccess.file_exists(dir.path_join("kopie.cfg")), "LÖSCHEN entfernt die cfg")
	check(_scr.load_config("ui_test"), "ui_test wieder geladen")
	# --- Server per Menü starten ---
	check(_scr.start_server(), "SERVER STARTEN: Prozess gestartet", str(_scr.server_pid))
	var pid := _scr.server_pid
	check(_scr.start_button.disabled and not _scr.stop_button.disabled, "Knöpfe: Starten gesperrt, Stoppen frei")
	var answered := func() -> bool: return String(_scr.server_info.get("name", "")) == "UI-Test" and int(_scr.server_info.get("bots", 0)) >= 2
	check(await wait_for(answered, 400.0), "Abfrage Port+1 beantwortet (Name, KI)", str(_scr.server_info))
	check(bool(_scr.server_info.get("ded", false)) and String(_scr.server_info.get("map", "")) == dm[0]
		and int(_scr.server_info.get("max", 0)) == 10, "Status: dediziert, erste Karte, Spielerzahl aus der cfg", str(_scr.server_info))
	check(_scr.server_label.text.contains("UI-Test"), "Statusanzeige zeigt den Server", _scr.server_label.text)
	_scr.send_console("pointlimit")
	var cons := func() -> bool: return _scr.log_text.contains("pointlimit = 0")
	check(await wait_for(cons, 60.0), "Konsole über die Pipe: Antwort im Log", _scr.log_text.substr(maxi(0, _scr.log_text.length() - 300)))
	_scr.send_console("bots")
	var bots := func() -> bool: return _scr.log_text.contains("bots = 1")
	check(await wait_for(bots, 60.0), "Regeln aus der cfg aktiv (bots = 1)")
	# --- Stoppen ---
	_scr.stop_server()
	var gone := func() -> bool: return _scr.server_pid == 0 and not OS.is_process_running(pid)
	check(await wait_for(gone, 40.0), "SERVER STOPPEN: Prozess beendet")
	check(not _scr.start_button.disabled, "Starten wieder frei")
	if OS.is_process_running(pid):
		OS.kill(pid)                 # nur der selbst gestartete Prozess
	_scr.queue_free()
	await frames(2)
	# --- eigenständiges Fenster (--server_config) ---
	Game.cli["server_config"] = dir
	Game._open_server_config()
	await frames(3)
	var cur := get_tree().current_scene
	check(cur is DedicatedServerScreen and (cur as DedicatedServerScreen).standalone, "--server_config: Konfigurationsmenü als Szene")
	check(cur is DedicatedServerScreen and (cur as DedicatedServerScreen).config_list.item_count >= 3, "--server_config: Konfigurationen aus dem Ordner")
	check(Game.current_mission() == null, "--server_config: keine Mission geladen")
	Game.cli.erase("server_config")
	_finish()
