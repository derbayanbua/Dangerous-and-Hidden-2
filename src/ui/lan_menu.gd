class_name LanMenu
extends Control
## „MEHRSPIELER-SPIEL – LAN“: Server erstellen (Karte, Spieltyp, Limits, Passwort) oder einem Server aus der
## LAN-Liste (UDP-Broadcast) bzw. per IP beitreten. Netzwerk: Godot-ENet (Net), kein DirectPlay.

signal back_requested

var _list: ItemList
var _status: Label
var _name_edit: LineEdit
var _map: OptionButton
var _mode: OptionButton
var _maxp: SpinBox
var _time: SpinBox
var _score: SpinBox
var _respawn: SpinBox
var _pw: LineEdit
var _cls: OptionButton
var _bots: SpinBox
var _ff: CheckBox
var _rounds: SpinBox
var _warm: SpinBox
var _allow_resp: CheckBox
var _balance: CheckBox
var _third: CheckBox
var _protect: SpinBox
var _inverse: SpinBox
var _falling: CheckBox
var _vehicles: CheckBox
var _names: CheckBox               ## Ergänzung: Namen über Spielern erlauben (shownames)
var _hits: CheckBox                ## Ergänzung: Trefferanzeige erlauben (hitindicator)
var _killcam: CheckBox             ## Ergänzung: Kill-Cam (killcam; Standard nur Deathmatch)
var _hurts: CheckBox               ## Ergänzung: Treffer-Richtungsanzeige beim Getroffenen (hurtindicator)
var _port: SpinBox
var _voice: OptionButton
var _maplist_mode: OptionButton
var _map_choice: ItemList
var _inet: CheckBox
var _ded: CheckBox
var _admin_login: LineEdit
var _admin_pass: LineEdit
var _max_ping: SpinBox
var _max_freq: SpinBox
var _max_idle: SpinBox
var _autorestart: CheckBox
## Internet-Variante (Hauptmenü „MEHRSPIELER-SPIEL – INTERNET“, T2116/2321): Favoriten statt LAN-Liste,
## Server standardmäßig als Internet-Server (UPnP). Ersatz für GameSpy: kein Masterserver.
var internet := false
var _last_mode := -1
var _ded_pid := 0


## Original-MP-Karten haben genau einen Spielstil (mpmaplist.txt); Arena-Karten: Deathmatch/Team-Deathmatch
func _sync_mode() -> void:
	var id := String(_map.get_item_metadata(_map.selected)) if _map.item_count > 0 else ""
	var fixed = Game.MISSIONS.get(id, {}).get("mp_mode")
	for i in _mode.item_count:
		_mode.set_item_disabled(i, fixed != null and i != int(fixed) or fixed == null and i > 1)
	if fixed != null:
		_mode.select(int(fixed))
	elif _mode.selected > 1:
		_mode.select(0)
	if _mode.selected != _last_mode:
		_apply_style_defaults()
	else:
		_fill_map_choice()


## Original (ServerLauncher 1070 „Change style? Settings will be reset to default.“): Stilwechsel setzt die Regeln
## auf die Standardwerte des Stils (re_notes_multiplayer §2.2)
func _apply_style_defaults() -> void:
	_last_mode = _mode.selected
	var d := Net.style_defaults(_mode.selected)
	_maxp.value = d["max_players"]
	_score.value = d["score_limit"]
	_time.value = d["time_limit_min"]
	_rounds.value = d["round_count"]
	_warm.value = d["warmup_s"]
	_respawn.value = maxi(int(d["respawn_s"]), 5)          # Menübereich 5–99
	_allow_resp.button_pressed = d["allow_respawn"]
	_ff.button_pressed = d["friendly_fire"]
	_balance.button_pressed = d["team_balance"]
	_third.button_pressed = d["third_person"]
	_protect.value = d["spawn_protect_s"]
	_inverse.value = d["inverse_damage"]
	_falling.button_pressed = d["falling_damage"]
	_vehicles.button_pressed = d["allow_vehicles"]
	_names.button_pressed = d["show_names"]
	_hits.button_pressed = d["hit_indicator"]
	_hurts.button_pressed = d["hurt_indicator"]
	_killcam.button_pressed = d["kill_cam"]
	_fill_map_choice()


## Karten des gewählten Stils; IN REIHENFOLGE = alle ab der gewählten Karte, BENUTZERDEFINIERT 1–4 = gespeicherte
## Auswahl (user://mp_maplists.json, Mehrfachauswahl in der Liste)
const MAPLIST_PATH := "user://mp_maplists.json"


func _style_maps() -> Array:
	var out: Array = []
	var m := _mode.selected
	for id in Game.MP_MAPS:
		var st = Game.MISSIONS[id].get("mp_mode")
		if (st == null and m <= Net.Mode.TEAM_DEATHMATCH) or (st != null and int(st) == m):
			out.append(id)
	return out


func _fill_map_choice() -> void:
	if _map_choice == null:
		return
	_map_choice.clear()
	var custom := _maplist_mode.selected > 0
	var saved: Array = _load_maplists().get(str(_maplist_mode.selected), [])
	for id in _style_maps():
		var i := _map_choice.add_item(String(Game.MISSIONS[id]["title"]))
		_map_choice.set_item_metadata(i, id)
		if (custom and saved.has(id)) or not custom:
			_map_choice.select(i, false)
	for i in _map_choice.item_count:
		_map_choice.set_item_selectable(i, custom)


func _load_maplists() -> Dictionary:
	var d = LsRuntime._read_json(ProjectSettings.globalize_path(MAPLIST_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _save_map_choice() -> void:
	if _maplist_mode.selected <= 0:
		return
	var d := _load_maplists()
	d[str(_maplist_mode.selected)] = map_rotation()
	var f := FileAccess.open(MAPLIST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


## Kartenrotation: gewählte Karte zuerst, dann die Liste in Reihenfolge
func map_rotation() -> Array:
	var cur := String(_map.get_item_metadata(_map.selected)) if _map.item_count > 0 else ""
	var out: Array = []
	if _maplist_mode.selected == 0:
		var all := _style_maps()
		var k := maxi(all.find(cur), 0)
		for j in all.size():
			out.append(all[(k + j) % all.size()])
	else:
		for i in _map_choice.get_selected_items():
			out.append(String(_map_choice.get_item_metadata(i)))
	if not out.has(cur):
		out.push_front(cur)
	return out


func _check(g: GridContainer, label: String, val: bool) -> CheckBox:
	_label(g, label)
	var c := CheckBox.new()
	c.button_pressed = val
	g.add_child(c)
	return c
var _ip: LineEdit
var _join_pw: LineEdit


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.04, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	UIKit.title(SAS.text(2321, "MEHRSPIELER-SPIEL - INTERNET") if internet else SAS.text(2320, "MEHRSPIELER-SPIEL - LAN"), 28, v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# --- links: Server erstellen ---
	# Beide Spalten teilen die Breite (passt ab 1280 px Basisbreite, 4:3 bis 21:9)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 460
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	cols.add_child(left)
	_head("SERVER ERSTELLEN", left)
	# Server-Regeln wie im Original-Servermenü (T2351–2382, Bereiche 0x629EE0) in einer Bildlaufliste
	var scroll := ScrollContainer.new()
	scroll.name = "ServerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	_name_edit = _line(g, SAS.text(2352, "Hostname"), "%s – Server" % Net.local_name)
	_map = _option(g, "Karte")
	for id in Game.MP_MAPS:
		_map.add_item(String(Game.MISSIONS[id]["title"]))
		_map.set_item_metadata(_map.item_count - 1, id)
	_mode = _option(g, SAS.text(2353, "Stil auswählen:").trim_suffix(":"))
	for i in Net.MODE_NAMES.size():
		_mode.add_item(Net.MODE_NAMES[i], i)
	# Standard = erste Original-MP-Karte (lokale eigene Karten stehen vorne in der Liste)
	for i in _map.item_count:
		var mm: Dictionary = Game.MISSIONS[String(_map.get_item_metadata(i))]
		if mm.get("mp_mode") != null and String(mm.get("orig", "")) != "":
			_map.select(i)
			break
	_map.item_selected.connect(func(_i): _sync_mode())
	_mode.item_selected.connect(func(_i): _apply_style_defaults())
	_cls = _option(g, "Klasse")
	for i in Net.CLASS_NAMES.size():
		_cls.add_item(Net.CLASS_NAMES[i], i)
	_cls.select(2)
	# Wertebereiche wie im Original-Servermenü (docs/re_notes_multiplayer.md §2.1), Standards je Stil §2.2
	_maxp = _spin(g, SAS.text(2364, "MAXIMALE SPIELERZAHL"), 2, 32, 32)
	_score = _spin(g, SAS.text(2365, "PUNKTELIMIT") + " (0 = aus)", 0, 999, 20)
	_time = _spin(g, SAS.text(2366, "RUNDENZEIT-LIMIT") + " [min] (0 = aus)", 0, 99, 0)
	_rounds = _spin(g, SAS.text(2367, "RUNDENZAHL"), 1, 999, 3)
	_warm = _spin(g, SAS.text(2368, "VORBEREITUNGSZEIT [s]"), 0, 99, 10)
	_respawn = _spin(g, SAS.text(2369, "RESPAWN-ZEIT [s]"), 5, 99, 5)
	_allow_resp = _check(g, SAS.text(2370, "RESPAWN ERLAUBEN"), true)
	_ff = _check(g, SAS.text(2371, "FRIENDLY FIRE"), false)
	_balance = _check(g, SAS.text(2372, "AUTO. TEAMAUSGLEICH"), false)
	_third = _check(g, SAS.text(2373, "3.PERS.-ANSICHT ERLAUBEN"), false)
	_protect = _spin(g, SAS.text(2376, "SPAWN-SCHUTZ") + " [s]", 0, 15, 5)
	_inverse = _spin(g, SAS.text(2377, "UMGEKEHRTER SCHADEN") + " [%]", 0, 999, 100)
	_falling = _check(g, SAS.text(2363, "VERLETZUNG BEIM FALLEN"), true)
	_vehicles = _check(g, "FAHRZEUGE ERLAUBEN", true)
	_bots = _spin(g, "KI-Soldaten je Team", 0, 16, 0)
	_pw = _line(g, SAS.text(2374, "PASSWORT") + " (optional)", "")
	_port = _spin(g, SAS.text(2378, "PORT"), Net.PORT_MIN, Net.PORT_MAX, Net.PORT)
	_admin_login = _line(g, "Admin-Login (ServerLauncher)", "admin")
	_admin_pass = _line(g, "Admin-Passwort", "")
	# ServerLauncher „Advanced“ (T2036–2040 Launcher): 0 = „No limit“
	_max_ping = _spin(g, "MAX. PING [ms] (0 = keine Grenze)", 0, 9999, 0)
	_max_freq = _spin(g, "MAX. FREQUENZ [Hz] (0 = keine Grenze)", 0, 100, 0)
	_max_idle = _spin(g, "MAX. INAKTIVITÄT [s] (0 = keine Grenze)", 0, 3600, 0)
	_autorestart = _check(g, "AUTORESTART (dedizierter Server)", false)
	# Ergänzungen (unter den Original-Feldern, damit deren Lage im Formular gleich bleibt)
	_names = _check(g, "NAMEN ÜBER SPIELERN ERLAUBEN", true)
	_hits = _check(g, "TREFFERANZEIGE SCHÜTZE ERLAUBEN", true)
	_hits.tooltip_text = "Hitmarker, Treffermeldung und Treffergeräusch für den Schützen (hitindicator)"
	_hurts = _check(g, "TREFFER-RICHTUNG GETROFFENER", true)
	_hurts.tooltip_text = "Roter Richtungsbogen beim Getroffenen (hurtindicator)"
	_killcam = _check(g, "KILL-CAM", true)
	_voice = _option(g, SAS.text(2375, "Codec für Voice-Chat"))
	for c in Net.VOICE_CODECS:
		_voice.add_item(SAS.text(2880 + int(c), "Codec %d" % c), int(c))
	_maplist_mode = _option(g, SAS.text(20206, "KARTENAUSWAHL"))
	for i in 5:
		_maplist_mode.add_item(SAS.text(20200 + i, "Liste %d" % i), i)
	_maplist_mode.item_selected.connect(func(_i): _fill_map_choice())
	_label(g, SAS.text(2380, "Server-Typ:"))
	var srv := VBoxContainer.new()
	g.add_child(srv)
	_inet = CheckBox.new()
	_inet.name = "InternetServer"
	_inet.text = SAS.text(2381, "INTERNET-SERVER")
	_inet.button_pressed = internet
	srv.add_child(_inet)
	_ded = CheckBox.new()
	_ded.name = "DedicatedServer"
	_ded.text = SAS.text(2382, "DEDIZIERTER SERVER")
	srv.add_child(_ded)
	_map_choice = ItemList.new()
	_map_choice.name = "MapChoice"
	_map_choice.select_mode = ItemList.SELECT_MULTI
	_map_choice.custom_minimum_size = Vector2(0, 120)
	_map_choice.tooltip_text = SAS.text(2354, "Liste der verfügbaren Karten:")
	_map_choice.multi_selected.connect(func(_i, _s): _save_map_choice())
	left.add_child(_map_choice)
	_sync_mode()
	var host_b := UIKit.button("Server starten", _host, left)
	host_b.name = "HostButton"
	UIKit.button(SAS.text(2551, "SPIELER-SETUP"), open_player_setup, left).name = "PlayerSetupButton"
	# --- rechts: Serverliste ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# Spalten wie im Original (HOSTNAME, KARTE, ART, PING, SPIELER – T2302–2306)
	_head("SERVER IM LAN    (%s · %s · %s · %s · %s)" % [SAS.text(2302, "HOSTNAME"), SAS.text(2303, "KARTE"), SAS.text(2304, "ART"),
		SAS.text(2305, "PING"), SAS.text(2306, "SPIELER")] if not internet else SAS.text(20100, "FAVORITEN"), right)
	_list = ItemList.new()
	_list.name = "ServerList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i): _join_listed(i))
	right.add_child(_list)
	var row := HFlowContainer.new()
	right.add_child(row)
	UIKit.button("Beitreten", func():
		var sel := _list.get_selected_items()
		if not sel.is_empty():
			_join_listed(sel[0]), row)
	UIKit.button(SAS.text(20102, "ZU FAVORITEN HINZUFÜGEN"), func():
		var sel := _list.get_selected_items()
		var addr := _ip.text.strip_edges()
		if not sel.is_empty() and not internet:
			var s: Dictionary = _list.get_item_metadata(sel[0])
			addr = "%s:%d" % [s.get("ip", ""), int(s.get("port", Net.PORT))]
		Net.add_favorite(addr)
		_refresh(), row).name = "AddFavorite"
	if internet:
		UIKit.button(SAS.text(20103, "AUS FAVORITEN LÖSCHEN"), func():
			for i in _list.get_selected_items():
				Net.remove_favorite(String(_list.get_item_metadata(i).get("key", "")))
			_refresh(), row).name = "RemoveFavorite"
	# Original-Knöpfe SERVER-FILTER (T2309, server filters.4ds) und SPIEL-INFO (T2312, gameinfo.4ds)
	var row2 := HFlowContainer.new()
	right.add_child(row2)
	UIKit.button(SAS.text(2309, "SERVER-FILTER"), open_filter, row2).name = "FilterButton"
	UIKit.button(SAS.text(2312, "SPIEL-INFO"), open_game_info, row2).name = "GameInfoButton"
	# Original-Knöpfe LISTE NEU EINLESEN (T2325) / LISTE AKTUALISIEREN (T2327), während des Laufs HALT (2326/2328)
	_reread_btn = UIKit.button(SAS.text(2325, "LISTE NEU EINLESEN"), _on_reread, row2)
	_reread_btn.name = "RereadButton"
	_update_btn = UIKit.button(SAS.text(2327, "LISTE AKTUALISIEREN"), _on_update, row2)
	_update_btn.name = "UpdateButton"
	Net.scan_changed.connect(_scan_buttons)
	_filter_label = Label.new()
	_filter_label.name = "FilterInfo"
	_filter_label.add_theme_font_size_override("font_size", 12)
	row2.add_child(_filter_label)
	var g2 := GridContainer.new()
	g2.columns = 2
	right.add_child(g2)
	_ip = _line(g2, SAS.text(2308, "SERVER-IP EINGEBEN") + " (IP/Name[:Port])", "127.0.0.1")
	_ip.name = "IpEdit"
	_join_pw = _line(g2, "Passwort", "")
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.button("Per IP beitreten", func(): _do_join(_ip.text.strip_edges(), Net.PORT), right)
	# Knöpfe der rechten Spalte schmaler (UIKit 320 px) – Zeilen brechen bei Bedarf um
	for r in [row, row2]:
		for b in r.get_children():
			if b is Button:
				b.custom_minimum_size.x = 250
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.clip_text = true
	if internet:
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Ohne GameSpy: Internet-Server geben Port %d/%d (UDP) per UPnP frei und melden ihre öffentliche IP; " % [Net.PORT, Net.PORT + 1] \
			+ "Beitritt per IP oder Hostname, Favoriten werden abgefragt (Ping)."
		hint.add_theme_font_size_override("font_size", 12)
		right.add_child(hint)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 200
	_status.add_theme_color_override("font_color", UIKit.ACCENT)
	v.add_child(_status)
	UIKit.button("Zurück", func():
		Net.stop_browse()
		Net.browsing_favorites = false
		back_requested.emit(), v)
	Net.servers_updated.connect(_refresh)
	Net.status_changed.connect(func(t): if is_instance_valid(_status): _status.text = t)
	Net.browsing_favorites = internet
	if internet:
		pass
	elif not Net.start_browse():
		_status.text = Net.last_error
	elif Net.last_error != "":
		_status.text = Net.last_error
	_refresh()


var player_setup: PlayerSetupScreen
var _reread_btn: Button
var _update_btn: Button


func _on_reread() -> void:
	if Net.scan_kind == "reread":
		Net.halt_scan()
	else:
		Net.reread_list()
	_refresh()


func _on_update() -> void:
	if Net.scan_kind == "update":
		Net.halt_scan()
	else:
		Net.update_list()


func _scan_buttons() -> void:
	if is_instance_valid(_reread_btn):
		_reread_btn.text = SAS.text(2326, "HALT") if Net.scan_kind == "reread" else SAS.text(2325, "LISTE NEU EINLESEN")
	if is_instance_valid(_update_btn):
		_update_btn.text = SAS.text(2328, "HALT") if Net.scan_kind == "update" else SAS.text(2327, "LISTE AKTUALISIEREN")


## Original „SPIELER-SETUP“ (player screen.4ds): Seite, Klasse/Vorlage, Ausrüstung, Chat. Karte = gewählter
## Server aus der Liste bzw. die Karte des eigenen Servers; AKZEPTIEREN übernimmt die Klasse (Net.local_class).
func open_player_setup() -> void:
	var map: String = String(_map.get_item_metadata(_map.selected)) if _map.item_count > 0 else ""
	for i in _list.get_selected_items():
		var m := String(_list.get_item_metadata(i).get("map", ""))
		if Game.MISSIONS.has(m):
			map = m
	player_setup = PlayerSetupScreen.new()
	player_setup.name = "PlayerSetup"
	add_child(player_setup)
	player_setup.accepted.connect(func():
		_cls.select(clampi(Net.local_class, 0, _cls.item_count - 1))
		_close_player_setup())
	player_setup.back_requested.connect(_close_player_setup)
	player_setup.open(map, int(_respawn.value))


func _close_player_setup() -> void:
	if is_instance_valid(player_setup):
		player_setup.queue_free()
	player_setup = null


func _head(t: String, parent: Node) -> void:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.add_theme_color_override("font_color", UIKit.ACCENT)
	parent.add_child(l)


## Formular-Beschriftung: feste Breite mit Zeilenumbruch, damit lange Texte das Menü nicht verbreitern
func _label(g: Control, label: String) -> Label:
	var l := Label.new()
	l.text = label
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = LABEL_W
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)
	return l


const LABEL_W := 230
const FIELD_W := 230


func _line(g: GridContainer, label: String, val: String) -> LineEdit:
	_label(g, label)
	var e := LineEdit.new()
	e.text = val
	e.custom_minimum_size.x = FIELD_W
	g.add_child(e)
	return e


func _option(g: GridContainer, label: String) -> OptionButton:
	_label(g, label)
	var o := OptionButton.new()
	o.custom_minimum_size.x = FIELD_W
	o.fit_to_longest_item = false
	o.clip_text = true
	g.add_child(o)
	return o


func _spin(g: GridContainer, label: String, lo: int, hi: int, val: int) -> SpinBox:
	_label(g, label)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	g.add_child(s)
	return s


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	# Auswahl über die Aktualisierung (jede Sekunde per Broadcast) hinweg behalten
	var sel_key := ""
	for i in _list.get_selected_items():
		sel_key = String(_list.get_item_metadata(i).get("key", ""))
	_list.clear()
	var src := {}
	if internet:
		for a in Net.favorites:
			var info: Dictionary = Net.fav_info.get(a, {})
			var d := info.duplicate()
			d["ip"] = String(a).get_slice(":", 0)
			d["port"] = int(String(a).get_slice(":", 1)) if String(a).contains(":") else Net.PORT
			if info.is_empty():
				d["name"] = String(a)
				d["offline"] = true
			src[a] = d
	else:
		src = Net.servers
	var hidden := 0
	for k in src:
		var s: Dictionary = src[k]
		if not Net.filter_pass(s):
			hidden += 1             # SERVER-FILTER (Original 0x638590)
			continue
		var nb := int(s.get("bots", 0))
		var txt := ""
		if bool(s.get("offline", false)):
			txt = "%s   –   (keine Antwort)" % s["name"]
		else:
			txt = "%s   –   %s   –   %s   %s   %d/%d%s%s%s%s   (%s:%d)" % [s.get("name", "?"), s.get("map_title", s.get("map", "")),
				Net.MODE_NAMES[clampi(int(s.get("mode", 0)), 0, 3)], "%d ms" % int(s["ping"]) if int(s.get("ping", -1)) >= 0 else "– ms",
				int(s.get("players", 0)), int(s.get("max", 8)), " +%d KI" % nb if nb > 0 else "", "  🔒" if s.get("pw", false) else "",
				"  [DED]" if s.get("ded", false) else "", "  [VOICE]" if int(s.get("voice", 0)) > 0 else "", s.get("ip", ""),
				int(s.get("port", Net.PORT))]
		var i := _list.add_item(txt)
		var meta := s.duplicate()
		meta["key"] = k
		_list.set_item_metadata(i, meta)
		if k == sel_key:
			_list.select(i)
	if is_instance_valid(_filter_label):
		_filter_label.text = "  Filter: %d ausgeblendet" % hidden if hidden > 0 else ""


var _filter_label: Label
var filter_screen: ServerFilterScreen
var info_screen: GameInfoScreen


## SERVER-FILTER (Original-Bildschirm server filters.4ds über dem Menü)
func open_filter() -> void:
	filter_screen = ServerFilterScreen.new()
	filter_screen.name = "ServerFilter"
	add_child(filter_screen)
	filter_screen.closed.connect(_close_filter)
	filter_screen.open()


func _close_filter(_accepted: bool) -> void:
	if is_instance_valid(filter_screen):
		filter_screen.queue_free()
	filter_screen = null
	_refresh()


## SPIEL-INFO zum markierten Server (gameinfo.4ds); SPIEL BEITRETEN tritt bei
func open_game_info() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		_status.text = "%s: zuerst einen Server markieren." % SAS.text(2312, "SPIEL-INFO")
		return
	info_screen = GameInfoScreen.new()
	info_screen.name = "GameInfo"
	add_child(info_screen)
	info_screen.closed.connect(_close_info)
	info_screen.join_requested.connect(_info_join)
	info_screen.open(_list.get_item_metadata(sel[0]))


func _close_info() -> void:
	if is_instance_valid(info_screen):
		info_screen.queue_free()
	info_screen = null


func _info_join(s: Dictionary) -> void:
	_close_info()
	_do_join(String(s.get("ip", "")), int(s.get("port", Net.PORT)))


func server_settings() -> Dictionary:
	return {"name": _name_edit.text.strip_edges(), "map": String(_map.get_item_metadata(_map.selected)),
		"mode": _mode.get_selected_id(), "max_players": int(_maxp.value), "time_limit_min": int(_time.value),
		"score_limit": int(_score.value), "respawn_s": int(_respawn.value), "password": _pw.text, "port": int(_port.value),
		"friendly_fire": _ff.button_pressed, "bots_per_team": int(_bots.value), "round_count": int(_rounds.value),
		"warmup_s": int(_warm.value), "allow_respawn": _allow_resp.button_pressed, "team_balance": _balance.button_pressed,
		"third_person": _third.button_pressed, "spawn_protect_s": int(_protect.value), "inverse_damage": int(_inverse.value),
		"falling_damage": _falling.button_pressed, "allow_vehicles": _vehicles.button_pressed,
		"show_names": _names.button_pressed, "hit_indicator": _hits.button_pressed, "hurt_indicator": _hurts.button_pressed, "kill_cam": _killcam.button_pressed,
		"voice_codec": _voice.get_selected_id(), "map_list": map_rotation(), "internet": _inet.button_pressed,
		"dedicated": _ded.button_pressed, "admin_login": _admin_login.text.strip_edges(), "admin_pass": _admin_pass.text,
		"max_ping": int(_max_ping.value), "max_freq": int(_max_freq.value), "max_inactivity": int(_max_idle.value),
		"autorestart": _autorestart.button_pressed}


## Konfigurationsdatei im Original-ServerLauncher-Stil (Konsolenzeilen) für den dedizierten Server
static func config_text(c: Dictionary) -> String:
	var lines: PackedStringArray = ["// Dangerous Hidden 2 – dedizierter Server (Schlüsselwörter wie HD2DS)",
		"sessionname \"%s\"" % String(c.get("name", "")),
		"style %s" % ["deathmatch", "teamdeathmatch", "occupation", "objectives"][clampi(int(c.get("mode", 0)), 0, 3)]]
	for m in c.get("map_list", [c.get("map", "")]):
		lines.append("mapname %s" % m)
	lines.append("domain %s" % ("internet" if bool(c.get("internet", false)) else "local"))
	lines.append("dedicated 1")
	lines.append("port %d" % int(c.get("port", Net.PORT)))
	if String(c.get("password", "")) != "":
		lines.append("password \"%s\"" % String(c["password"]))
	for k in Net.RULE_KEYS:
		if c.has(k):
			var v = c[k]
			lines.append("%s %d" % [Net.RULE_KEYS[k], (1 if v else 0) if v is bool else int(v)])
	lines.append("voicechat %d" % int(c.get("voice_codec", 0)))
	if String(c.get("admin_pass", "")) != "":
		lines.append("adminlogin %s" % String(c.get("admin_login", "admin")))
		lines.append("adminpass %s" % String(c["admin_pass"]))
	lines.append("server")
	return "\n".join(lines) + "\n"


func _host() -> void:
	Net.local_class = _cls.selected
	var cfg := server_settings()
	if bool(cfg["dedicated"]):
		_start_dedicated(cfg)
		return
	Net.stop_browse()
	Net.browsing_favorites = false
	if not Net.host(cfg):
		_status.text = Net.last_error
		if not internet:
			Net.start_browse()


## DEDIZIERTER SERVER (T2382): eigener, kopfloser Prozess mit Konfigurationsdatei; danach Beitritt als Spieler
func _start_dedicated(cfg: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://dedicated"))
	var path := ProjectSettings.globalize_path("user://dedicated/%s.cfg" % String(cfg["name"]).validate_filename())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "Konfiguration nicht schreibbar: " + path
		return
	f.store_string(config_text(cfg))
	f.close()
	var args: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--dedicated=" + path])
	_ded_pid = OS.create_process(OS.get_executable_path(), args)
	if _ded_pid <= 0:
		_status.text = "Dedizierter Server konnte nicht gestartet werden."
		return
	_status.text = "Dedizierter Server gestartet (Prozess %d, Port %d, Konfiguration %s) – Beitritt …" % [_ded_pid, int(cfg["port"]), path]
	_ded_join.call_deferred(int(cfg["port"]), String(cfg.get("password", "")))


func _ded_join(port: int, pw: String) -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree() or Net.is_online:
		return
	_join_pw.text = pw
	_do_join("127.0.0.1", port)


func _join_listed(i: int) -> void:
	var s: Dictionary = _list.get_item_metadata(i)
	_do_join(String(s.get("ip", "")), int(s.get("port", Net.PORT)))


func _do_join(ip: String, port: int) -> void:
	if ip == "":
		return
	Net.local_class = _cls.selected
	Net.stop_browse()
	Net.browsing_favorites = false
	if not Net.join(ip, port, _join_pw.text):
		_status.text = Net.last_error
		Net.browsing_favorites = internet
		if not internet:
			Net.start_browse()
