class_name DedicatedServerScreen
extends Control
## Konfigurationsmenü des dedizierten Servers (0.10.3) nach dem Vorbild des Original-ServerLaunchers (HD2DS):
## links Konfigurationsliste (NEU/LÖSCHEN/DUPLIZIEREN, SERVER STARTEN), rechts Reiter. Aufteilung wie die Dialoge
## des Originals (Belege docs/status/dedicated_ui.md): ALLGEMEIN (Sitzungsname, Spielstil, Domäne, verfügbare/
## gespielte Karten mit -> <- AUF AB), REGELN (Spieler, Limits, Schalter, Respawn/Schutz/Aufwärmen/Schaden),
## ERWEITERT (Passwort, Port, Max-Grenzen, Autorestart, Admin, Voice), KOOPERATIV (Schwierigkeit, Leben, Team-Leben),
## ERGÄNZUNGEN (Regeln ohne Launcher-Feld) und SERVER (Status, Log, Konsole, Stoppen).
## Konfigurationen = Konsolenzeilen (LanMenu.config_text) in <exe>/ServerConfigs/*.cfg (Original „ServerConfigs\\“,
## „Default.cfg“); Start: eigener kopfloser Prozess `<exe> --headless -- --dedicated=<cfg>` mit Pipe als Konsole.
## Eigenständig: `DangerousHidden2.exe -- --server_config` (DedicatedServer.cmd) – ohne Hauptmenü/Intro/Mission.

signal back_requested

const CONFIG_DIR := "ServerConfigs"
const DEFAULT_NAME := "Default"
const STYLE_WORDS := ["deathmatch", "teamdeathmatch", "occupation", "objectives", "cooperative"]
## Regel → Beschriftung (Übersetzung über locale/ui_texts.csv)
const RULE_LABELS := {
	"max_players": "MAX. SPIELER", "score_limit": "PUNKTELIMIT (0 = aus)", "time_limit_min": "RUNDENZEIT [min] (0 = aus)",
	"round_count": "RUNDENZAHL", "warmup_s": "AUFWÄRMEN [s]", "respawn_s": "RESPAWN-ZEIT [s]", "allow_respawn": "RESPAWN ERLAUBEN",
	"friendly_fire": "FRIENDLY FIRE", "team_balance": "AUTO. TEAMAUSGLEICH", "third_person": "3. PERSON ERLAUBEN",
	"spawn_protect_s": "SPAWN-SCHUTZ [s]", "inverse_damage": "UMGEKEHRTER SCHADEN [%]", "falling_damage": "FALLSCHADEN",
	"flood_protect": "FLOOD-SCHUTZ", "allow_vehicles": "FAHRZEUGE ERLAUBEN", "bots_per_team": "KI-SOLDATEN JE TEAM",
	"max_ping": "MAX. PING [ms] (0 = aus)", "max_freq": "MAX. FREQUENZ [Hz] (0 = aus)",
	"max_inactivity": "MAX. INAKTIVITÄT [s] (0 = aus)", "autorestart": "AUTORESTART",
	"show_names": "NAMEN ÜBER SPIELERN", "hit_indicator": "TREFFERANZEIGE SCHÜTZE", "hurt_indicator": "TREFFER-RICHTUNG",
	"kill_cam": "KILL-CAM", "support_strike": "FUNK-SCHLAG (0–3)", "support_interval_min": "FUNK ALLE [min]",
	"support_bots": "KI NUTZT FUNK", "coop_difficulty": "SCHWIERIGKEIT (1–4)", "coop_lives": "LEBEN (-1 = ∞)",
	"allow_crosshair": "FADENKREUZ ZULASSEN", "spawn_on_start": "SPAWN BEIM START", "team_lives": "TEAM-LEBEN",
	"precise_aim": "PRÄZISES ZIELEN",
}
## Reiter wie die Original-Dialoge; nicht genannte Regeln landen unter ERGÄNZUNGEN
const TAB_RULES := {
	"REGELN": ["max_players", "score_limit", "time_limit_min", "round_count", "friendly_fire", "team_balance", "third_person",
		"falling_damage", "allow_respawn", "allow_vehicles", "allow_crosshair", "respawn_s", "spawn_protect_s", "warmup_s",
		"inverse_damage"],
	"ERWEITERT": ["max_ping", "max_freq", "max_inactivity", "autorestart"],
	"KOOPERATIV": ["coop_difficulty", "coop_lives", "team_lives", "spawn_on_start"],
}

var standalone := false            ## über --server_config gestartet (Beenden statt Zurück)
var configs_dir := ""              ## Ordner der .cfg (Standard: neben der EXE, im Editor user://ServerConfigs)
var current_name := DEFAULT_NAME

var tabs: TabContainer
var config_list: ItemList
var name_edit: LineEdit            ## Name für NEU/DUPLIZIEREN
var session_edit: LineEdit
var style_option: OptionButton
var internet_check: CheckBox
var avail_list: ItemList
var play_list: ItemList
var password_edit: LineEdit
var port_spin: SpinBox
var admin_login_edit: LineEdit
var admin_pass_edit: LineEdit
var voice_option: OptionButton
var rule_controls := {}            ## Regel-Schlüssel -> SpinBox/CheckBox
var status_label: Label
var server_label: Label
var log_view: TextEdit
var console_edit: LineEdit
var start_button: Button
var stop_button: Button

var server_pid := 0
var server_port := 0
var server_info := {}              ## letzte Antwort der Serverabfrage (Port+1)
var log_text := ""
var _stdio: FileAccess
var _stderr: FileAccess
var _qsock: PacketPeerUDP
var _q_t := 0.0
var _stop_deadline := 0


func _ready() -> void:
	tree_exiting.connect(func(): stop_server(true))


func config_dir() -> String:
	if configs_dir != "":
		return configs_dir
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("user://" + CONFIG_DIR)
	return OS.get_executable_path().get_base_dir().path_join(CONFIG_DIR)


func config_path(cname: String) -> String:
	return config_dir().path_join(cname.validate_filename() + ".cfg")


# --- Aufbau ---------------------------------------------------------------------------------------------------

func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	UIKit.title(tr("DEDIZIERTER SERVER – KONFIGURATION"), 22, v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# --- links: Konfigurationen (Original: Liste, New config/Delete/Duplicate, Start Server) ---
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	cols.add_child(left)
	_head(tr("KONFIGURATIONEN"), left)
	config_list = ItemList.new()
	config_list.name = "ConfigList"
	config_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	config_list.item_selected.connect(func(i): load_config(config_list.get_item_text(i)))
	left.add_child(config_list)
	name_edit = LineEdit.new()
	name_edit.name = "ConfigName"
	name_edit.placeholder_text = tr("Name der Konfiguration")
	left.add_child(name_edit)
	_small_button(tr("NEUE KONFIG"), func(): new_config(name_edit.text), left, "NewConfig")
	_small_button(tr("DUPLIZIEREN"), func(): duplicate_config(name_edit.text), left, "DuplicateConfig")
	_small_button(tr("LÖSCHEN"), func(): delete_config(current_name), left, "DeleteConfig")
	_small_button(tr("SPEICHERN"), func(): save_config(current_name), left, "SaveConfig")
	start_button = _small_button(tr("SERVER STARTEN"), func(): start_server(), left, "StartServer")
	stop_button = _small_button(tr("SERVER STOPPEN"), func(): stop_server(), left, "StopServer")
	_small_button(tr("BEENDEN") if standalone else tr("ZURÜCK"), _on_back, left, "Back")
	# --- rechts: Reiter ---
	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(tabs)
	_build_general()
	var placed := {}
	for tab_name in TAB_RULES:
		var g := _tab_grid(tr(tab_name))
		if tab_name == "ERWEITERT":
			password_edit = _line(g, tr("PASSWORT"), "")
			port_spin = _spin(g, tr("PORT"), Net.PORT_MIN, Net.PORT_MAX, Net.PORT)
		for k in TAB_RULES[tab_name]:
			_rule_control(g, k)
			placed[k] = true
		if tab_name == "ERWEITERT":
			admin_login_edit = _line(g, tr("ADMIN-LOGIN"), "admin")
			admin_pass_edit = _line(g, tr("ADMIN-PASSWORT"), "")
			_label(g, tr("VOICE-CHAT"))
			voice_option = OptionButton.new()
			for c in Net.VOICE_CODECS:
				voice_option.add_item(SAS.text(2880 + int(c), "Codec %d" % c), int(c))
			g.add_child(voice_option)
	var gx := _tab_grid(tr("ERGÄNZUNGEN"))
	for k in Net.RULE_KEYS:
		if not placed.has(k):
			_rule_control(gx, k)
	_build_server_tab()
	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UIKit.ACCENT)
	v.add_child(status_label)
	refresh_config_list()
	if FileAccess.file_exists(config_path(DEFAULT_NAME)):
		load_config(DEFAULT_NAME)
	else:
		_apply_style_defaults()
		save_config(DEFAULT_NAME)
	_update_buttons()


func _build_general() -> void:
	var page := VBoxContainer.new()
	page.name = tr("ALLGEMEIN")
	tabs.add_child(page)
	var g := GridContainer.new()
	g.columns = 2
	page.add_child(g)
	session_edit = _line(g, tr("SITZUNGSNAME"), tx(2025, "H&D 2 SERVER"))
	_label(g, tr("SPIELSTIL"))
	style_option = OptionButton.new()
	style_option.name = "Style"
	for i in Net.MODE_NAMES.size():
		style_option.add_item(Net.MODE_NAMES[i], i)
	# Original 1070: Stilwechsel setzt die Regeln auf die Standards des Stils zurück
	style_option.item_selected.connect(func(_i): _apply_style_defaults())
	g.add_child(style_option)
	_label(g, tr("DOMÄNE"))
	internet_check = CheckBox.new()
	internet_check.text = tr("INTERNET (sonst LAN)")
	g.add_child(internet_check)
	var maps := HBoxContainer.new()
	maps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(maps)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_child(lv)
	_head(tr("VERFÜGBARE KARTEN"), lv)
	avail_list = ItemList.new()
	avail_list.name = "AvailableMaps"
	avail_list.select_mode = ItemList.SELECT_MULTI
	avail_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail_list.item_activated.connect(func(_i): add_selected_maps())
	lv.add_child(avail_list)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	maps.add_child(mid)
	_tiny_button("->", add_selected_maps, mid, "AddMap")
	_tiny_button("<-", remove_selected_maps, mid, "RemoveMap")
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_child(rv)
	_head(tr("GESPIELTE KARTEN"), rv)
	play_list = ItemList.new()
	play_list.name = "PlayMaps"
	play_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_list.item_activated.connect(func(_i): remove_selected_maps())
	rv.add_child(play_list)
	var ud := HBoxContainer.new()
	rv.add_child(ud)
	_tiny_button(tr("AUF"), func(): move_selected_map(-1), ud, "MapUp")
	_tiny_button(tr("AB"), func(): move_selected_map(1), ud, "MapDown")


func _build_server_tab() -> void:
	var page := VBoxContainer.new()
	page.name = tr("SERVER")
	tabs.add_child(page)
	server_label = Label.new()
	server_label.name = "ServerStatus"
	server_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(server_label)
	log_view = TextEdit.new()
	log_view.name = "Log"
	log_view.editable = false
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("font_size", 12)
	page.add_child(log_view)
	var row := HBoxContainer.new()
	page.add_child(row)
	console_edit = LineEdit.new()
	console_edit.name = "Console"
	console_edit.placeholder_text = tr("Konsolenbefehl (help, listplayers, nextmap, say …)")
	console_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_edit.text_submitted.connect(func(t): send_console(t); console_edit.clear())
	row.add_child(console_edit)
	_tiny_button(tr("SENDEN"), func(): send_console(console_edit.text); console_edit.clear(), row, "SendConsole")


static func tx(id: int, fb: String) -> String:
	return SAS.text(id, fb).strip_edges()


func _tab_grid(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	return g


func _rule_control(g: GridContainer, key: String) -> void:
	_label(g, tr(String(RULE_LABELS.get(key, Net.RULE_KEYS[key]))))
	var c: Control
	if Net.RULE_RANGE.has(key):
		var r: Array = Net.RULE_RANGE[key]
		var s := SpinBox.new()
		s.min_value = int(r[0])
		s.max_value = int(r[1])
		c = s
	else:
		c = CheckBox.new()
	c.name = "Rule_" + key
	c.tooltip_text = String(Net.RULE_KEYS[key])        # Konsolen-/Config-Schlüsselwort
	g.add_child(c)
	rule_controls[key] = c


func _head(t: String, parent: Node) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", UIKit.ACCENT)
	parent.add_child(l)


func _label(g: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size.x = 260
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(l)


func _line(g: GridContainer, label: String, val: String) -> LineEdit:
	_label(g, label)
	var e := LineEdit.new()
	e.text = val
	e.custom_minimum_size.x = 220
	g.add_child(e)
	return e


func _spin(g: GridContainer, label: String, lo: int, hi: int, val: int) -> SpinBox:
	_label(g, label)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	g.add_child(s)
	return s


func _small_button(t: String, cb: Callable, parent: Node, nm: String) -> Button:
	var b := UIKit.button(t, cb, parent)
	b.name = nm
	b.custom_minimum_size = Vector2(240, 34)
	return b


func _tiny_button(t: String, cb: Callable, parent: Node, nm: String) -> Button:
	var b := Button.new()
	b.text = t
	b.name = nm
	b.custom_minimum_size = Vector2(56, 30)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_back() -> void:
	stop_server()
	if standalone:
		get_tree().quit()
	else:
		back_requested.emit()


# --- Karten ---------------------------------------------------------------------------------------------------

## Karten des Stils im Kartenwähler: nur Original-MP-Karten (fester Stil, Originaldaten). Arena-Karten (Kampagnen-
## karten ohne festen Stil) und eigene/lokale Karten (ohne `orig`) werden nicht angeboten (Folgeauftrag). TDM nutzt
## die Deathmatch-Karten (Net.resolve_map). Coop hat ohne Arena-Karten keine Auswahl (Original: Coop nicht im HD2DS).
static func style_maps(m: int) -> Array:
	var out: Array = []
	for id in Game.MP_MAPS:
		var e: Dictionary = Game.MISSIONS.get(id, {})
		var st = e.get("mp_mode")
		if st == null or String(e.get("orig", "")) == "":
			continue
		if int(st) == m or (m == Net.Mode.TEAM_DEATHMATCH and int(st) == Net.Mode.DEATHMATCH):
			out.append(id)
	return out


func _map_title(id: String) -> String:
	return "%s  (%s)" % [String(Game.MISSIONS.get(id, {}).get("title", id)), id]


func _fill_avail() -> void:
	avail_list.clear()
	for id in style_maps(style_option.selected):
		var i := avail_list.add_item(_map_title(id))
		avail_list.set_item_metadata(i, id)


func play_maps() -> Array:
	var out: Array = []
	for i in play_list.item_count:
		out.append(String(play_list.get_item_metadata(i)))
	return out


func set_play_maps(ids: Array) -> void:
	play_list.clear()
	for id in ids:
		var i := play_list.add_item(_map_title(String(id)))
		play_list.set_item_metadata(i, String(id))


func add_selected_maps() -> void:
	var ids := play_maps()
	for i in avail_list.get_selected_items():
		var id := String(avail_list.get_item_metadata(i))
		if not ids.has(id):
			ids.append(id)
	set_play_maps(ids)


func remove_selected_maps() -> void:
	var ids := play_maps()
	var sel := play_list.get_selected_items()
	for j in range(sel.size() - 1, -1, -1):
		ids.remove_at(sel[j])
	set_play_maps(ids)


func move_selected_map(d: int) -> void:
	var sel := play_list.get_selected_items()
	if sel.is_empty():
		return
	var i: int = sel[0]
	var j := i + d
	var ids := play_maps()
	if j < 0 or j >= ids.size():
		return
	var t = ids[i]
	ids[i] = ids[j]
	ids[j] = t
	set_play_maps(ids)
	play_list.select(j)


# --- Werte ↔ Formular ------------------------------------------------------------------------------------------

func _apply_style_defaults() -> void:
	var d := Net.style_defaults(style_option.selected)
	for k in rule_controls:
		_set_rule_value(k, d.get(k, 0))
	_fill_avail()
	var keep: Array = []
	var allowed := style_maps(style_option.selected)
	for id in play_maps():
		if allowed.has(id):
			keep.append(id)
	if keep.is_empty() and not allowed.is_empty():
		keep = [allowed[0]]
	set_play_maps(keep)
	if allowed.is_empty() and status_label:
		status_label.text = tr("Für diesen Spielstil gibt es im Kartenwähler noch keine Karten.")


func _set_rule_value(k: String, v: Variant) -> void:
	var c: Control = rule_controls.get(k)
	if c is SpinBox:
		(c as SpinBox).value = int(v)
	elif c is CheckBox:
		(c as CheckBox).button_pressed = bool(v)


## Formular → Einstellungen (Schlüssel wie Net.host/LanMenu.server_settings)
func settings() -> Dictionary:
	var ml := play_maps()
	var c := {"name": session_edit.text.strip_edges(), "mode": style_option.selected, "map_list": ml,
		"map": ml[0] if not ml.is_empty() else "", "internet": internet_check.button_pressed, "dedicated": true,
		"port": int(port_spin.value), "password": password_edit.text, "admin_login": admin_login_edit.text.strip_edges(),
		"admin_pass": admin_pass_edit.text, "voice_codec": voice_option.get_selected_id()}
	for k in rule_controls:
		var ctl: Control = rule_controls[k]
		c[k] = int((ctl as SpinBox).value) if ctl is SpinBox else (ctl as CheckBox).button_pressed
	return c


## Einstellungen → Formular
func apply_settings(c: Dictionary) -> void:
	var m := clampi(int(c.get("mode", 0)), 0, Net.MODE_NAMES.size() - 1)
	style_option.select(m)
	var d := Net.style_defaults(m)
	for k in rule_controls:
		_set_rule_value(k, c.get(k, d.get(k, 0)))
	session_edit.text = String(c.get("name", tx(2025, "H&D 2 SERVER")))
	internet_check.button_pressed = bool(c.get("internet", false))
	port_spin.value = int(c.get("port", Net.PORT))
	password_edit.text = String(c.get("password", ""))
	admin_login_edit.text = String(c.get("admin_login", "admin"))
	admin_pass_edit.text = String(c.get("admin_pass", ""))
	var vi := voice_option.get_item_index(int(c.get("voice_codec", 0)))
	voice_option.select(maxi(vi, 0))
	_fill_avail()
	set_play_maps(c.get("map_list", []))


## Konfigurationsdatei (Konsolenzeilen im ServerLauncher-Stil) lesen – ohne den Zustand von Net zu verändern
static func parse_config(text: String) -> Dictionary:
	var c := {"map_list": []}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("//") or line.begins_with("#") or line.begins_with(";"):
			continue
		var sp := line.find(" ")
		var kw := (line if sp < 0 else line.substr(0, sp)).to_lower()
		var arg := "" if sp < 0 else line.substr(sp + 1).strip_edges()
		if arg.length() >= 2 and arg.begins_with("\"") and arg.ends_with("\""):
			arg = arg.substr(1, arg.length() - 2)
		match kw:
			"sessionname":
				c["name"] = arg
			"style":
				if STYLE_WORDS.has(arg.to_lower()):
					c["mode"] = STYLE_WORDS.find(arg.to_lower())
			"deathmatch", "teamdeathmatch", "occupation", "objectives", "cooperative":
				c["mode"] = STYLE_WORDS.find(kw)
			"mapname":
				if not (c["map_list"] as Array).has(arg):
					(c["map_list"] as Array).append(arg)
			"domain":
				c["internet"] = arg == "internet"
			"port":
				c["port"] = int(arg)
			"password":
				c["password"] = arg
			"adminlogin":
				c["admin_login"] = arg
			"adminpass":
				c["admin_pass"] = arg
			"voicechat":
				c["voice_codec"] = int(arg) if arg.is_valid_int() else maxi(Net.voice_codec_from(arg), 0)
			_:
				for k in Net.RULE_KEYS:
					if Net.RULE_KEYS[k] == kw:
						if Net.RULE_RANGE.has(k):
							var r: Array = Net.RULE_RANGE[k]
							c[k] = clampi(int(arg), int(r[0]), int(r[1]))
						else:
							c[k] = arg.to_lower() in ["1", "true", "yes", "on"]
	if not (c["map_list"] as Array).is_empty():
		c["map"] = c["map_list"][0]
	return c


# --- Konfigurationen --------------------------------------------------------------------------------------------

func refresh_config_list() -> void:
	config_list.clear()
	DirAccess.make_dir_recursive_absolute(config_dir())
	var names: Array = []
	for f in DirAccess.get_files_at(config_dir()):
		if f.get_extension().to_lower() == "cfg":
			names.append(f.get_basename())
	names.sort()
	for n in names:
		var i := config_list.add_item(n)
		if n == current_name:
			config_list.select(i)


func save_config(cname: String) -> bool:
	cname = cname.strip_edges()
	if cname == "":
		cname = current_name
	DirAccess.make_dir_recursive_absolute(config_dir())
	var f := FileAccess.open(config_path(cname), FileAccess.WRITE)
	if f == null:
		_status(tr("Konfiguration nicht schreibbar:") + " " + config_path(cname))
		return false
	f.store_string(LanMenu.config_text(settings()))
	f.close()
	current_name = cname
	refresh_config_list()
	_status(tr("Gespeichert:") + " " + config_path(cname))
	return true


func load_config(cname: String) -> bool:
	var p := config_path(cname)
	if not FileAccess.file_exists(p):
		_status(tr("Konfiguration nicht gefunden:") + " " + p)
		return false
	apply_settings(parse_config(FileAccess.get_file_as_string(p)))
	current_name = cname
	refresh_config_list()
	_status(tr("Geladen:") + " " + p)
	return true


func new_config(cname: String) -> void:
	cname = cname.strip_edges()
	if cname == "" or FileAccess.file_exists(config_path(cname)):
		_status(tr("Bitte einen neuen, noch nicht vergebenen Namen eingeben."))
		return
	style_option.select(0)
	session_edit.text = tx(2025, "H&D 2 SERVER")
	_apply_style_defaults()
	save_config(cname)


func duplicate_config(cname: String) -> void:
	cname = cname.strip_edges()
	if cname == "" or FileAccess.file_exists(config_path(cname)):
		_status(tr("Bitte einen neuen, noch nicht vergebenen Namen eingeben."))
		return
	save_config(cname)


func delete_config(cname: String) -> void:
	var p := config_path(cname)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	current_name = DEFAULT_NAME
	refresh_config_list()
	if FileAccess.file_exists(config_path(DEFAULT_NAME)):
		load_config(DEFAULT_NAME)
	_status(tr("Gelöscht:") + " " + p)


func _status(t: String) -> void:
	if status_label:
		status_label.text = t


# --- Serverprozess ----------------------------------------------------------------------------------------------

func is_running() -> bool:
	return server_pid > 0 and OS.is_process_running(server_pid)


## Konfiguration speichern und den kopflosen Server als eigenen Prozess starten (Pipe = Server-Konsole)
func start_server() -> bool:
	if is_running():
		_status(tr("Der Server läuft bereits."))
		return false
	if play_maps().is_empty():
		_status(tr("Keine Karte in der Liste der gespielten Karten."))
		return false
	if not save_config(current_name):
		return false
	var path := config_path(current_name)
	var args: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--dedicated=" + path])
	var r := OS.execute_with_pipe(OS.get_executable_path(), args, false)
	server_pid = int(r.get("pid", 0))
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	if server_pid <= 0:
		_status(tr("Dedizierter Server konnte nicht gestartet werden."))
		return false
	server_port = int(port_spin.value)
	server_info = {}
	_stop_deadline = 0
	_q_t = 1.0
	_append_log("== %s %d, Port %d, %s\n" % [tr("Server gestartet, Prozess"), server_pid, server_port, path])
	_status(tr("Server gestartet, Prozess") + " %d" % server_pid)
	tabs.current_tab = tabs.get_tab_count() - 1
	_update_buttons()
	return true


## „quit“ an die Server-Konsole; reagiert der Prozess nicht, wird nach 15 s nur dieser eigene Prozess beendet
func stop_server(immediate := false) -> void:
	if server_pid <= 0:
		return
	if is_running():
		send_console("quit")
		if immediate:
			OS.delay_msec(300)
			if OS.is_process_running(server_pid):
				OS.kill(server_pid)
			_closed()
			return
		_stop_deadline = Time.get_ticks_msec() + 15000
		_status(tr("Server wird beendet …"))
	else:
		_closed()


func _closed() -> void:
	if server_pid > 0:
		_append_log("== %s %d\n" % [tr("Server beendet, Prozess"), server_pid])
	server_pid = 0
	server_info = {}
	_stdio = null
	_stderr = null
	_stop_deadline = 0
	_update_buttons()


func send_console(line: String) -> void:
	line = line.strip_edges()
	if line == "" or _stdio == null or not is_running():
		return
	_stdio.store_string(line + "\n")
	_stdio.flush()


func _append_log(s: String) -> void:
	log_text += s
	if log_text.length() > 60000:
		log_text = log_text.substr(log_text.length() - 40000)
	if log_view:
		log_view.text = log_text
		log_view.scroll_vertical = log_view.get_line_count()


func _update_buttons() -> void:
	if start_button:
		start_button.disabled = is_running()
	if stop_button:
		stop_button.disabled = not is_running()
	if server_label:
		if not is_running():
			server_label.text = tr("Server läuft nicht.")
		elif server_info.is_empty():
			server_label.text = tr("Server läuft (Prozess %d), wartet auf Antwort …") % server_pid
		else:
			server_label.text = tr("Server läuft: %s – Karte %s – Spieler %d/%d (+%d KI) – Port %d") % [
				String(server_info.get("name", "")), String(server_info.get("map_title", server_info.get("map", ""))),
				int(server_info.get("players", 0)), int(server_info.get("max", 0)), int(server_info.get("bots", 0)), server_port]


func _process(delta: float) -> void:
	if server_pid <= 0:
		return
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 32:
			var b: PackedByteArray = (pipe as FileAccess).get_buffer(4096)
			if b.is_empty():
				break
			_append_log(b.get_string_from_utf8())
	if not is_running():
		_closed()
		return
	if _stop_deadline > 0 and Time.get_ticks_msec() > _stop_deadline:
		OS.kill(server_pid)        # nur der selbst gestartete Prozess
		_closed()
		return
	_q_t -= delta
	if _q_t <= 0.0:
		_q_t = 2.0
		_query()
	_poll_query()


## Serverabfrage auf Port+1 (wie Net.query_server, eigener Socket – Net bleibt unberührt)
func _query() -> void:
	if _qsock == null:
		_qsock = PacketPeerUDP.new()
		_qsock.bind(0)
	_qsock.set_dest_address("127.0.0.1", server_port + 1)
	var q := "%s %d|127.0.0.1:%d" % [Net.QUERY_TAG, Time.get_ticks_msec(), server_port]
	_qsock.put_packet((q + " ".repeat(maxi(0, Net.QUERY_PAD - q.length()))).to_utf8_buffer())


func _poll_query() -> void:
	if _qsock == null:
		return
	var changed := false
	while _qsock.get_available_packet_count() > 0:
		var d = JSON.parse_string(_qsock.get_packet().get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY and String(d.get("tag", "")).begins_with("DH2-LAN"):
			server_info = d
			changed = true
	if changed:
		_update_buttons()
