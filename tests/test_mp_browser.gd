extends "res://tests/lan_ui_base.gd"
## 0.11.1: Internet-Serverbrowser (multiplayer menu.4ds) mit Ersatz-Masterliste (MasterLink.mock_servers):
## Liste, Ausrufezeichen bei nicht-rankeden Servern, Warnung vor dem Beitritt, Statuszeile ohne Master;
## danach SPIELER-SETUP vor dem Spawn (Host: kein Soldat bis AKZEPTIEREN).
##   tools\godot.cmd --headless -- --autoplay=test_mp_browser --profiles_dir=user://test_mp_browser --noimport --setup_gate=1
## Kontrollbild (Fenster): zusätzlich --shots=1 → test_output/b0111_menu_browser.png


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func shot(n: String) -> void:
	if not " ".join(OS.get_cmdline_user_args()).contains("--shots=1"):
		return
	await frames(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/b0111_menu_%s.png" % n))


func _run() -> void:
	var menu := await menu_with_profile("Browser")
	# --- ohne Master: Hinweis, Favoriten/IP bleiben nutzbar ---
	MasterLink.force_mock = true
	MasterLink.mock_servers = []
	MasterLink.mock_offline = true
	var real = get_tree().root.get_node_or_null("Master")
	check(real == null or (real.has_method("connect_master") and real.has_signal("servers_updated") and real.has_signal("status_changed")),
		"Master-Modul: Schnittstelle connect_master/servers_updated/status_changed")
	Game.profile["online_consent"] = true
	menu.open_lan(true)
	await frames(6)
	var lm: LanMenu = menu.lan_menu
	var br: ServerBrowserScreen = lm.browser if lm else null
	check(br != null and br.visible and br.has_layout(), "Internet: Serverbrowser nach Original-Modell offen")
	if br == null:
		_finish()
		return
	var unreachable := func() -> bool: return br.status_text.contains(tr(MasterLink.UNREACHABLE))
	check(await wait_for(unreachable, 5.0),
		"Ohne Master: Hinweis in der Statuszeile", br.status_text)
	for n in ["JoinButton", "CreateButton", "UpdateButton", "RereadButton", "FavoritesButton", "FilterButton",
			"GameInfoButton", "FavAddRemove", "EnterIpButton", "BackButton", "HeadName", "HeadPing"]:
		check(br.find_child(n, true, false) != null, "Browser-Knopf " + n)
	check((br.find_child("EnterIpButton", true, false) as Button).text == SAS.text(2308, "SERVER-IP EINGEBEN"), "Originaltext T2308")
	# --- Mock-Liste ---
	MasterLink.mock_servers = [
		{"name": "Offiziell", "host": "10.0.0.1", "port": 11001, "map": "x", "mode": 0, "players": 3, "max_players": 16,
			"ping": 40, "version": "0.11", "password": false, "dedicated": true, "ranked": true, "verify": true},
		{"name": "Eigenbau", "host": "10.0.0.2", "port": 11005, "map": "y", "mode": 2, "players": 0, "max_players": 8,
			"ping": 90, "version": "0.11", "password": true, "dedicated": false, "ranked": false, "verify": false}]
	br.reconnect()
	await frames(4)
	check(br.entries.size() == 2, "Liste aus der Masterquelle: 2 Server", str(br.entries.size()))
	check(br.find_child("RowName0", true, false) != null and br.find_child("RowName1", true, false) != null, "Zeilen gezeichnet")
	var ex_i := -1
	for i in br.entries.size():
		if not bool(br.entries[i].get("ranked", true)):
			ex_i = i
	check(ex_i >= 0 and br.find_child("Unranked%d" % ex_i, true, false) != null, "Nicht-rankeder Server mit Ausrufezeichen")
	check(br.find_child("Unranked%d" % (1 - ex_i), true, false) == null, "Rankeder Server ohne Ausrufezeichen")
	check(br.status_text.begins_with(tr("Serverliste geladen")), "Statuszeile: geladen", br.status_text)
	await shot("browser")
	await _readme_shot(br)
	# Sortieren nach Ping
	br._sort("ping")
	check(int(br.entries[0]["ping"]) <= int(br.entries[1]["ping"]), "Sortierung nach PING")
	# Filter: ohne Passwort blendet den Eigenbau aus
	Net.server_filter["no_password"] = true
	br.build()
	check(br.entries.size() == 1 and br.hidden_count == 1, "SERVER-FILTER wirkt auf die Masterliste", "%d/%d %s" % [br.entries.size(), br.hidden_count, str(Net.server_filter)])
	Net.server_filter["no_password"] = false
	br.build()
	# Warnung vor dem Beitritt
	for i in br.entries.size():
		if not bool(br.entries[i].get("ranked", true)):
			br.selected = i
	br.join_selected()
	await frames(2)
	var dlg := br.find_child("UnrankedDialog", true, false)
	check(dlg != null, "Nicht-rankeder Server: Rückfrage vor dem Beitritt")
	var lbl_ok := false
	if dlg:
		for l in dlg.find_children("*", "Label", true, false):
			if (l as Label).text == tr(ServerBrowserScreen.UNRANKED_WARNING):
				lbl_ok = true
	check(lbl_ok, "Warnung „%s“" % tr(ServerBrowserScreen.UNRANKED_WARNING))
	await shot("browser_warning")
	var no: Button = dlg.find_child("Dialog1", true, false) if dlg else null
	if no:
		no.pressed.emit()
	await frames(2)
	check(not Net.is_online, "ZURÜCK in der Rückfrage: kein Beitritt")
	# Übersetzung der neuen Texte
	var tr_ok := true
	for lang in ["en", "fr", "it", "es", "cs"]:
		var tro := TranslationServer.get_translation_object(lang)
		if tro == null or tro.get_message(ServerBrowserScreen.UNRANKED_WARNING) == "":
			tr_ok = false
	check(tr_ok, "Warnung in allen Sprachen übersetzt")
	# SERVER ERSTELLEN → Original-Bildschirm create server.4ds, ZURÜCK → Browser
	(br.find_child("CreateButton", true, false) as Button).pressed.emit()
	await frames(2)
	var cs: CreateServerScreen = lm.create_screen
	check(cs != null and cs.is_visible_in_tree() and cs.has_layout() and not br.visible, "SERVER ERSTELLEN: Original-Bildschirm offen, Browser aus")
	if cs == null:
		_finish()
		return
	await _check_create(lm, cs)
	await shot("create_server")
	(cs.find_child("CreateBack", true, false) as Button).pressed.emit()
	await frames(2)
	check(lm.create_screen == null and br.visible, "ZURÜCK: wieder im Serverbrowser")
	(br.find_child("CreateButton", true, false) as Button).pressed.emit()
	await frames(2)
	cs = lm.create_screen

	# --- SPIELER-SETUP vor dem Spawn (Host) ---
	check(Net.setup_gate_on(), "Setup-Sperre aktiv (--setup_gate=1)")
	lm._ded.button_pressed = false
	lm._inet.button_pressed = false
	var hb: Button = cs.find_child("HostButton", true, false) if cs else null
	check(hb != null and hb.text == SAS.text(2357, "START"), "START (T2357) startet den Server")
	if hb:
		hb.pressed.emit()
	else:
		lm._host()
	var loaded := func() -> bool: return Game.current_mission() != null and Net.is_online
	check(await wait_for(loaded, 300.0), "Server gestartet, Karte geladen")
	await frames(30)
	check(Net.in_setup(1) and Net.setup_pending, "Host gilt als „im Setup“")
	check(not is_instance_valid(Net._soldiers.get(1)), "Kein Spawn vor AKZEPTIEREN")
	var setup_open := func() -> bool:
		var ps = get_tree().root.find_child("PlayerSetup", true, false)
		return ps != null and ps.is_visible_in_tree()
	check(await wait_for(setup_open, 20.0), "SPIELER-SETUP öffnet automatisch")
	await shot("setup_after_join")
	var ps = get_tree().root.find_child("PlayerSetup", true, false)
	if ps:
		ps.accepted.emit()
	var spawned := func() -> bool:
		var s = Net._soldiers.get(1)
		return is_instance_valid(s) and s.alive
	check(await wait_for(spawned, 20.0), "Nach AKZEPTIEREN gespawnt")
	check(not Net.in_setup(1) and not Net.setup_pending, "Setup-Status aufgehoben")
	# Bots sind nie „im Setup“
	var bots_ok := true
	for id in Net.players:
		if bool(Net.players[id].get("bot", false)) and Net.in_setup(id):
			bots_ok = false
	check(bots_ok, "Bots ohne Setup")
	Net.leave()
	await frames(10)
	_finish()


## SERVER ERSTELLEN: Originaltexte, alle Regeln aus Net.RULE_KEYS bedienbar, Stil/Karten/Ja-Nein/Zahlen wirken aufs Formular
func _check_create(lm: LanMenu, cs: CreateServerScreen) -> void:
	check((cs.find_child("Title", true, false) as Label).text == SAS.text(2351, "SERVER ERSTELLEN"), "Titel T2351")
	check(cs.find_child("InternetLabel", true, false) != null and cs.find_child("Internet_yes", true, false) != null
		and cs.find_child("Dedicated_no", true, false) != null, "Server-Typ INTERNET/DEDIZIERT mit Ja/Nein")
	# jede Regel hat eine Formularzeile (server_settings) und eine Zeile im Bildschirm (Coop-Regeln nur bei KOOPERATIV)
	var cfg := lm.server_settings()
	var missing: Array = []
	for k in Net.RULE_KEYS:
		if not cfg.has(k):
			missing.append(k)
	check(missing.is_empty(), "Alle Regeln aus Net.RULE_KEYS im Formular", str(missing))
	var widgets := {}
	for r in cs.rows:
		if r["w"] != null:
			widgets[r["w"]] = true
	var need := [lm._maxp, lm._score, lm._time, lm._rounds, lm._warm, lm._respawn, lm._allow_resp, lm._ff, lm._balance,
		lm._third, lm._protect, lm._inverse, lm._falling, lm._vehicles, lm._bots, lm._names, lm._hits, lm._hurts,
		lm._killcam, lm._support, lm._support_min, lm._support_bots, lm._max_ping, lm._max_freq, lm._max_idle,
		lm._autorestart, lm._flood, lm._precise, lm._pw, lm._port, lm._cls]
	check(need.all(func(w): return widgets.has(w)), "Regelzeilen für alle Regeln (ohne Coop)")
	check(String(cs.rows[0]["label"]) == SAS.text(2364, "MAXIMALE SPIELERZAHL"), "Original-Felder zuerst (T2364)")
	# Klassen übersetzt, Standard Sturmsoldat
	check(lm._cls.item_count == MpClasses.COUNT and lm._cls.selected == MpClasses.DEFAULT
		and lm._cls.get_item_text(0) == tr(MpClasses.NAMES[0]), "Klassenauswahl: 7 Klassen (tr), Standard Sturmsoldat")
	# Zahl eintippen
	var e: LineEdit = cs.find_child("Rule_maxp", true, false)
	if e:
		e.text = "12"
		e.text_submitted.emit("12")
	check(int(lm._maxp.value) == 12, "Zahl eingeben: MAXIMALE SPIELERZAHL = 12", str(lm._maxp.value))
	# Ja/Nein
	var ff0 := lm._ff.button_pressed
	cs.show_rule("ff")
	await frames(1)
	_hit(cs, "Rule_ff_" + ("no" if ff0 else "yes"))
	await frames(1)
	check(lm._ff.button_pressed != ff0, "Ja/Nein-Kästchen schaltet FRIENDLY FIRE")
	_hit(cs, "Internet_yes")
	await frames(1)
	check(lm._inet.button_pressed, "INTERNET-SERVER: Ja")
	# Ergänzungen unten (Bildlauf) erreichbar
	cs.show_rule("cls")
	await frames(1)
	_hit(cs, "Rule_cls")
	await frames(1)
	check(lm._cls.selected == (MpClasses.DEFAULT + 1) % MpClasses.COUNT and cs.find_child("Rule_clsValue", true, false) != null,
		"Klasse in der Regelliste wählbar")
	lm._cls.select(MpClasses.DEFAULT)
	# Stil mit Pfeilen: BESETZUNG → nur Karten dieses Stils, Startkarte passt
	cs.set_style(Net.Mode.OCCUPATION)
	await frames(1)
	var occ: Array = lm._style_maps()
	check(lm._mode.selected == Net.Mode.OCCUPATION and occ.has(cs.current_map()), "Stil BESETZUNG: Startkarte aus der Stil-Liste",
		cs.current_map())
	# Kartenauswahl BENUTZERDEFINIERT 1: Karte hinzufügen/entfernen
	_hit(cs, "PresetOpen")
	await frames(1)
	_hit(cs, "Preset1")
	await frames(1)
	check(lm._maplist_mode.selected == 1, "Kartenauswahl-Vorlage BENUTZERDEFINIERT 1")
	if occ.size() > 1:
		_hit(cs, "Map1")
		await frames(1)
		(cs.find_child("MapAdd", true, false) as Button).pressed.emit()
		await frames(1)
		check(lm.map_rotation().has(String(occ[1])), "HINZUFÜGEN: Karte in der Rotation", str(lm.map_rotation()))
	cs.set_style(Net.Mode.COOP)
	await frames(1)
	var coop_ok := lm._mode.selected == Net.Mode.COOP and cs.rows.any(func(r): return r["w"] == lm._coop_diff) \
		and cs.rows.any(func(r): return r["w"] == lm._spawn_start)
	check(coop_ok, "Stil KOOPERATIV: Coop-Regeln (T20210–20214) in der Liste")
	cs.set_style(Net.Mode.DEATHMATCH)
	lm._maplist_mode.select(0)
	lm._fill_map_choice()
	cs.scroll = 0
	cs.build()
	await frames(1)


func _hit(root: Node, nm: String) -> void:
	var c: Control = root.find_child(nm, true, false)
	if c == null:
		check(false, "Klickfläche " + nm)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)

## README-Bild (Fenster, --shots=1 --readme=1): Serverbrowser mit erfundener Liste, ohne echte Serverdaten/IPs und ohne
## eigene Karten (nur Original-MP-Karten) → test_output/readme/07_mehrspieler_raw.png (tools/readme_png.py quantisiert)
func _readme_shot(br: ServerBrowserScreen) -> void:
	var args := " ".join(OS.get_cmdline_user_args())
	if not args.contains("--shots=1") or not args.contains("--readme=1"):
		return
	var keep: Array = MasterLink.mock_servers
	var maps: Array = []
	for id in Game.MP_MAPS:
		var mm: Dictionary = Game.MISSIONS[id]
		if mm.get("mp_mode") != null and String(mm.get("orig", "")) != "" and not bool(mm.get("test_map", false)):
			maps.append(id)
	var names := ["Normandie-Veteranen", "Wüstenfüchse 24/7", "Abendrunde Ost", "Alpenjäger [DE]", "Nordmeer-Runde",
		"Feierabendrunde", "Testserver Eigenbau", "Dschungelkämpfer", "Pazifik-Stammtisch"]
	var list: Array = []
	for i in names.size():
		var id := String(maps[(i * 3) % maps.size()]) if not maps.is_empty() else "x"
		list.append({"name": names[i], "host": "192.0.2.%d" % (10 + i), "port": 11001, "map": id,
			"map_title": String(Game.MISSIONS.get(id, {}).get("title", id)), "mode": int(Game.MISSIONS.get(id, {}).get("mp_mode", 0)),
			"players": [12, 7, 3, 16, 9, 2, 0, 5, 11][i], "max_players": [16, 16, 6, 24, 16, 8, 8, 12, 16][i],
			"ping": [38, 52, 61, 74, 88, 95, 120, 143, 171][i], "version": "0.11", "password": i == 5,
			"dedicated": i % 2 == 0, "voice": 6 if i % 3 == 0 else 0, "ranked": i != 6, "verify": i != 6})
	MasterLink.mock_servers = list
	MasterLink.mock_offline = false
	br.reconnect()
	await frames(4)
	br.selected = 1
	br.build()
	await frames(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/readme"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/readme/07_mehrspieler_raw.png"))
	MasterLink.mock_servers = keep
	MasterLink.mock_offline = true
	br.selected = -1
	br._on_master_list(keep)
	await frames(2)