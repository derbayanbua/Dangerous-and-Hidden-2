class_name CreateServerScreen
extends OrigScreen
## 0.11.1: Original-Bildschirm „SERVER ERSTELLEN“ nach MODELS\create server.4ds (orig_cache/ui/menu/layout/
## create server.json): links Hostname (bhostname), Stil mit Pfeilen (style), Kartenauswahl-Vorlage (maplist preset
## mit Klappliste), verfügbare Karten (table01, bmap_A = hinzufügen) und Kartenrotation (table03, bmap_B = entfernen);
## rechts Server-Typ INTERNET-SERVER/DEDIZIERTER SERVER (Ja/Nein-Kästchen), Server-Regeln (table02 mit den
## Zeilenvorlagen combo_tmpl/yes_no_tmpl/binput/bshort00 und Bildlauf scroll01), Codec für Voice-Chat (Pfeile),
## START/ZURÜCK. Texte = Originaltexte (T2351–2382, 20200–20214).
## Datenmodell bleibt das LanMenu-Formular (Felder, server_settings, Kartenrotation): dieser Bildschirm liest und
## setzt dessen Steuerelemente. Regel-Reihenfolge: Original-Felder zuerst, darunter (Bildlauf) die Ergänzungen
## (Klasse, KI-Soldaten, Fahrzeuge, Rückmeldungen, Funk, Präzises Zielen, Flood-Schutz, Launcher-Grenzen, Admin).
## Coop-Regeln (T20210–20214) erscheinen nur beim Stil KOOPERATIV.

signal back_requested

const ROW_Y0 := 258.9
const ROW_H := 35.0
const ROW_FH := 32.6
const ROWS := 8
const MAP_Y0 := 353.0
const MAP_H := 23.0
const MAP_ROWS := 13
## Ja/Nein-Kästchen: Verschiebung der „voll“-Vorlagen (Atlasbereich rechts außerhalb) auf die Kästchen
const YN_TMPL := {"no": ["no_empty21", "no_full22"], "yes": ["yes_empty21", "yes_full22"]}

var lan: Node
var rows: Array = []
var scroll := 0
var map_scroll := 0
var rot_scroll := 0
var rot_sel := -1
var preset_open := false
var status := ""
var _building := false


func open(lan_menu: Node) -> void:
	lan = lan_menu
	setup_stage()
	build()


func build() -> void:
	_building = true
	rows = _rule_rows()
	scroll = clampi(scroll, 0, maxi(rows.size() - ROWS, 0))
	begin("create server")
	draw_frames(["player screen"])
	title(2351, "SERVER ERSTELLEN")
	_left_side()
	_right_side()
	orig_button("bstart", SAS.text(2357, "START"), _start, true, "HostButton")
	orig_button("bback", SAS.text(2358, "ZURÜCK"), func(): back_requested.emit(), true, "CreateBack")
	var st := label(Rect2(70, 712, 870, 22), status, 13, INK_RED)
	st.name = "CreateStatus"
	if preset_open:
		_preset_list()
	_building = false


# ---------------------------------------------------------------- links: Name, Stil, Karten

func _left_side() -> void:
	text_at("text_hostname and style", SAS.text(2352, "Hostname") + " / " + SAS.text(2353, "Stil auswählen:").trim_suffix(":"), 13)
	draw_frames(["normal14"])
	var hn := _edit(rect("normal14", Rect2(70, 145, 414, 33)).grow_individual(-8, -2, -8, -2), lan._name_edit.text, "HostnameEdit")
	hn.max_length = 40
	hn.text_changed.connect(func(t: String): lan._name_edit.text = t)
	# Stil mit Pfeilen
	draw_frames(["style"])
	var m: int = lan._mode.selected
	label(rect("style", Rect2(107, 182, 337, 33)), Net.MODE_NAMES[m], 15, INK, HORIZONTAL_ALIGNMENT_CENTER).name = "StyleText"
	var styles := styles_available()
	var k := styles.find(m)
	orig_button("barrow up0", "", func(): set_style(styles[(k - 1 + styles.size()) % styles.size()]), styles.size() > 1, "StyleLeft")
	orig_button("barrow down0", "", func(): set_style(styles[(k + 1) % styles.size()]), styles.size() > 1, "StyleRight")
	# Kartenauswahl-Vorlage (IN REIHENFOLGE / BENUTZERDEFINIERT 1–4)
	text_at("text_maplist preset", SAS.text(20206, "KARTENAUSWAHL"), 13)
	draw_frames(["maplist preset"])
	text_at("header", lan._maplist_mode.get_item_text(lan._maplist_mode.selected), 14).name = "PresetText"
	hit(rect("header"), func(_d: bool): _toggle_preset(), "PresetOpen")
	orig_button("cbdown01", "", _toggle_preset, true, "PresetArrow")
	# verfügbare Karten (Stil) und Rotation
	text_at("text_available maps checklist", SAS.text(2354, "Liste der verfügbaren Karten:"), 12)
	text_at("text_maplist", SAS.text(20205, "PERS. KARTENAUSWAHL"), 12)
	draw_frames(["table01", "table03"])
	var custom: bool = lan._maplist_mode.selected > 0
	orig_button("bmap_A", tr("HINZUFÜGEN"), _add_map, custom, "MapAdd", 13)
	orig_button("bmap_B", tr("ENTFERNEN"), _remove_map, custom and rot_sel >= 0, "MapRemove", 13)
	var maps: Array = lan._style_maps()
	map_scroll = clampi(map_scroll, 0, maxi(maps.size() - MAP_ROWS, 0))
	_scrollbar(["scroll00", "sliderbase"], "normal07", "barrow up", "barrow down", maps.size(), MAP_ROWS, map_scroll,
		_scroll_maps, "Maps")
	var cur := current_map()
	for r in mini(MAP_ROWS, maps.size() - map_scroll):
		var i: int = map_scroll + r
		var id := String(maps[i])
		var y := MAP_Y0 + r * MAP_H
		var on := id == cur
		label(Rect2(119, y, 152, MAP_H), String(Game.MISSIONS[id]["title"]), 12, INK_RED if on else INK).name = "MapText%d" % i
		hit(Rect2(117, y, 155, MAP_H), func(dbl: bool):
			select_map(id)
			if dbl and custom:
				_add_map(), "Map%d" % i)
	var rot: Array = lan.map_rotation()
	rot_sel = clampi(rot_sel, -1, rot.size() - 1)
	rot_scroll = clampi(rot_scroll, 0, maxi(rot.size() - MAP_ROWS, 0))
	_scrollbar(["scroll13", "sliderbase03"], "normal36", "barrow up09", "barrow down04", rot.size(), MAP_ROWS, rot_scroll,
		_scroll_rot, "Rot")
	for r in mini(MAP_ROWS, rot.size() - rot_scroll):
		var i: int = rot_scroll + r
		var y := MAP_Y0 + r * MAP_H
		label(Rect2(328, y, 150, MAP_H), "%d. %s" % [i + 1, String(Game.MISSIONS[String(rot[i])]["title"])], 12,
			INK_RED if i == rot_sel else INK).name = "RotText%d" % i
		hit(Rect2(326, y, 154, MAP_H), _pick_rot.bind(i), "Rot%d" % i)


## Bildlaufleiste einer Liste (Rahmen, Schieber, Pfeile)
func _scrollbar(base: Array, thumb: String, up: String, down: String, n: int, vis: int, pos: int, cb: Callable, tag: String) -> void:
	draw_frames(base)
	if n > vis:
		var b := rect(base[1])
		var t := rect(thumb)
		var h := maxf(t.size.y, b.size.y * vis / n)
		var y := b.position.y + (b.size.y - h) * pos / maxf(n - vis, 1)
		draw_frame(thumb, Vector2(0, y - t.position.y))
	orig_button(up, "", cb.bind(-1), pos > 0, tag + "Up")
	orig_button(down, "", cb.bind(1), pos < n - vis, tag + "Down")


func _toggle_preset() -> void:
	preset_open = not preset_open
	build()


func _preset_list() -> void:
	var ov := Control.new()
	ov.name = "PresetList"
	ov.size = REF
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(ov)
	draw_frames(["shadow01", "listbox"], ov)
	var r0 := rect("text00d", Rect2(73.8, 286.2, 324.7, 207))
	for i in lan._maplist_mode.item_count:
		var r := Rect2(r0.position.x, r0.position.y + i * 24.0, r0.size.x, 24.0)
		label(r, lan._maplist_mode.get_item_text(i), 14, INK_RED if i == lan._maplist_mode.selected else INK).name = "PresetText%d" % i
		hit(r, func(_d: bool):
			lan._maplist_mode.select(i)
			lan._fill_map_choice()
			preset_open = false
			rot_sel = -1
			build(), "Preset%d" % i)


func current_map() -> String:
	return String(lan._map.get_item_metadata(lan._map.selected)) if lan._map.item_count > 0 else ""


## Stile, für die es Karten gibt (Original-MP-Karten haben einen festen Stil, Arena-Karten DM/TDM, Coop = SP-Karten)
func styles_available() -> Array:
	var out: Array = []
	for m in Net.MODE_NAMES.size():
		if not lan._style_maps(m).is_empty():
			out.append(m)
	return out


## Stil wählen: passt die Startkarte nicht zum Stil, wird die erste Karte des Stils gewählt; Stilwechsel setzt die
## Regeln auf die Standardwerte des Stils (Original ServerLauncher T1070)
func set_style(m: int) -> void:
	lan._mode.select(m)
	var maps: Array = lan._style_maps(m)
	if not maps.has(current_map()) and not maps.is_empty():
		select_map(String(maps[0]), false)
	lan._sync_mode()
	if lan._mode.selected != m:
		lan._mode.select(m)
		lan._apply_style_defaults()
	map_scroll = 0
	rot_sel = -1
	build()


func select_map(id: String, rebuild := true) -> void:
	for i in lan._map.item_count:
		if String(lan._map.get_item_metadata(i)) == id:
			var mode: int = lan._mode.selected
			lan._map.select(i)
			lan._sync_mode()
			# Arena-Karte im Stil Team-DM/Coop: Stil behalten, wenn die Karte ihn erlaubt
			if lan._mode.selected != mode and lan._style_maps(mode).has(id):
				lan._mode.select(mode)
				lan._apply_style_defaults()
			break
	if rebuild:
		build()


func _add_map() -> void:
	if lan._maplist_mode.selected <= 0:
		return
	var cur := current_map()
	for i in lan._map_choice.item_count:
		if String(lan._map_choice.get_item_metadata(i)) == cur:
			lan._map_choice.select(i, false)
	lan._save_map_choice()
	build()


func _remove_map() -> void:
	var rot: Array = lan.map_rotation()
	if lan._maplist_mode.selected <= 0 or rot_sel < 0 or rot_sel >= rot.size():
		return
	var id := String(rot[rot_sel])
	for i in lan._map_choice.item_count:
		if String(lan._map_choice.get_item_metadata(i)) == id:
			lan._map_choice.deselect(i)
	lan._save_map_choice()
	# die Startkarte steht immer vorne in der Rotation: entfernt man sie, wird die nächste Karte Startkarte
	if id == current_map():
		var rest: Array = lan.map_rotation().filter(func(x): return x != id)
		if not rest.is_empty():
			select_map(String(rest[0]), false)
	rot_sel = -1
	build()


# ---------------------------------------------------------------- rechts: Server-Typ, Regeln, Voice

func _right_side() -> void:
	text_at("text_server type", SAS.text(2380, "Server-Typ:"), 13)
	_yes_no_line("internet server", SAS.text(2381, "INTERNET-SERVER"), lan._inet, "18", "Internet")
	_yes_no_line("dedicated server", SAS.text(2382, "DEDIZIERTER SERVER"), lan._ded, "19", "Dedicated")
	text_at("text_server options", SAS.text(2355, "Server-Regeln:"), 13)
	draw_frames(["table02"])
	_scrollbar(["scroll01", "sliderbase01"], "normal32", "barrow up01", "barrow down2", rows.size(), ROWS, scroll,
		_scroll_rules, "Rules")
	for k in mini(ROWS, rows.size() - scroll):
		_rule_row(k, rows[scroll + k])
	text_at("text_voice chat", SAS.text(2375, "Codec für Voice-Chat"), 13)
	draw_frames(["voice chat"])
	var v: OptionButton = lan._voice
	label(rect("voice chat", Rect2(562, 576, 337, 33)), v.get_item_text(v.selected), 15, INK, HORIZONTAL_ALIGNMENT_CENTER).name = "VoiceText"
	orig_button("barrow up00", "", _voice.bind(-1), v.item_count > 1, "VoiceLeft")
	orig_button("barrow down1", "", _voice.bind(1), v.item_count > 1, "VoiceRight")


## Server-Typ-Zeile: Textfeld + Nein/Ja-Kästchen (Vorlagen *_empty/*_full mit Nummer suffix)
func _yes_no_line(frame: String, txt: String, cb: CheckBox, suf: String, tag: String) -> void:
	draw_frames([frame])
	var r := rect(frame, Rect2(525, 145, 341, 33))
	label(Rect2(r.position.x + 8, r.position.y, r.size.x - 12, r.size.y), txt, 14).name = tag + "Label"
	_yn_boxes({"no": ["no_empty" + suf, "no_full" + suf], "yes": ["yes_empty" + suf, "yes_full" + suf]}, 0.0, cb, tag)


func _yn_boxes(tmpl: Dictionary, dy: float, cb: CheckBox, tag: String) -> void:
	for key in ["no", "yes"]:
		var empty: String = tmpl[key][0]
		var full: String = tmpl[key][1]
		var on: bool = cb.button_pressed == (key == "yes")
		var er := rect(empty)
		if on:
			draw_frame(full, Vector2(er.position.x - rect(full).position.x, dy))
		else:
			draw_frame(empty, Vector2(0, dy))
		var hr := Rect2(er.position + Vector2(0, dy), er.size)
		hit(hr, func(_d: bool):
			cb.button_pressed = key == "yes"
			build(), "%s_%s" % [tag, key])


func _rule_row(k: int, row: Dictionary) -> void:
	var dy := k * ROW_H
	var y := ROW_Y0 + dy
	var nm := "Rule_" + String(row["id"])
	match String(row["kind"]):
		"sep":
			label(Rect2(582, y, 345, ROW_FH), String(row["label"]), 13, INK_RED).name = nm
		"num":
			draw_frames(["text00", "normal02"], null, Vector2(0, dy))
			label(Rect2(584, y, 270, ROW_FH), String(row["label"]), 13).name = nm + "Label"
			var sb: SpinBox = row["w"]
			var e := _edit(Rect2(861, y, 58, ROW_FH), str(int(sb.value)), nm)
			e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var commit := func(_t = null):
				if _building or not is_instance_valid(e):
					return
				var s := e.text.strip_edges()
				if s.is_valid_int():
					sb.value = int(s)
				e.text = str(int(sb.value))
			e.text_submitted.connect(commit)
			e.focus_exited.connect(commit)
		"text":
			draw_frames(["text08", "normal31"], null, Vector2(0, dy))
			label(Rect2(584, y, 166, ROW_FH), String(row["label"]), 13).name = nm + "Label"
			var le: LineEdit = row["w"]
			var e2 := _edit(Rect2(760, y, 164, ROW_FH), le.text, nm)
			e2.secret = bool(row.get("secret", false))
			e2.text_changed.connect(func(t: String): le.text = t)
		"yn":
			draw_frames(["text12"], null, Vector2(0, dy))
			label(Rect2(584, y, 270, ROW_FH), String(row["label"]), 13).name = nm + "Label"
			_yn_boxes(YN_TMPL, dy, row["w"], nm)
		"combo":
			draw_frames(["text18", "game difficulty", "normaldown01d01"], null, Vector2(0, dy))
			label(Rect2(584, y, 166, ROW_FH), String(row["label"]), 13).name = nm + "Label"
			var ob: OptionButton = row["w"]
			var hr := rect("header01", Rect2(765.7, 258.2, 119.8, 33.2))
			label(Rect2(hr.position.x, y, hr.size.x, ROW_FH), ob.get_item_text(ob.selected) if ob.selected >= 0 else "", 13).name = nm + "Value"
			hit(Rect2(757, y, 170, ROW_FH), func(_d: bool):
				_cycle(ob, 1)
				if row.has("after"):
					(row["after"] as Callable).call()
				build(), nm)
		"action":
			draw_frames(["text08", "normal31"], null, Vector2(0, dy))
			label(Rect2(584, y, 166, ROW_FH), String(row["label"]), 13).name = nm + "Label"
			button_from(frames, "binput", "»", row["cb"], true, nm, 15, Rect2(757, 258.9, 170, 32.6), Vector2(0, dy))


## nächster wählbarer Eintrag einer Auswahlliste (gesperrte Einträge übersprungen)
func _cycle(ob: OptionButton, d: int) -> void:
	var n := ob.item_count
	var i := ob.selected
	for _k in n:
		i = (i + d + n) % n
		if not ob.is_item_disabled(i):
			ob.select(i)
			ob.item_selected.emit(i)
			return


func _edit(r: Rect2, txt: String, nm: String) -> LineEdit:
	var e := LineEdit.new()
	e.name = nm
	e.position = r.position
	e.size = r.size
	e.text = txt
	e.flat = true
	for st in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_font_size_override("font_size", 15)
	stage.add_child(e)
	return e


func _rule_rows() -> Array:
	var L = lan
	var r: Array = []
	# Original-Felder (Reihenfolge der Original-Texte T2363–2378)
	r.append(_row("num", "maxp", SAS.text(2364, "MAXIMALE SPIELERZAHL"), L._maxp))
	r.append(_row("num", "score", SAS.text(2365, "PUNKTELIMIT"), L._score))
	r.append(_row("num", "time", SAS.text(2366, "RUNDENZEIT-LIMIT") + " [min]", L._time))
	r.append(_row("num", "rounds", SAS.text(2367, "RUNDENZAHL"), L._rounds))
	r.append(_row("num", "warm", SAS.text(2368, "VORBEREITUNGSZEIT [s]"), L._warm))
	r.append(_row("num", "respawn", SAS.text(2369, "RESPAWN-ZEIT [s]"), L._respawn))
	r.append(_row("yn", "allow_resp", SAS.text(2370, "RESPAWN ERLAUBEN"), L._allow_resp))
	r.append(_row("yn", "ff", SAS.text(2371, "FRIENDLY FIRE"), L._ff))
	r.append(_row("yn", "balance", SAS.text(2372, "AUTO. TEAMAUSGLEICH"), L._balance))
	r.append(_row("yn", "third", SAS.text(2373, "3.PERS.-ANSICHT ERLAUBEN"), L._third))
	r.append(_row("text", "pw", SAS.text(2374, "PASSWORT"), L._pw))
	r.append(_row("num", "protect", SAS.text(2376, "SPAWN-SCHUTZ") + " [s]", L._protect))
	r.append(_row("num", "inverse", SAS.text(2377, "UMGEKEHRTER SCHADEN") + " [%]", L._inverse))
	r.append(_row("yn", "falling", SAS.text(2363, "VERLETZUNG BEIM FALLEN"), L._falling))
	r.append(_row("num", "port", SAS.text(2378, "PORT"), L._port))
	if int(L._mode.selected) == Net.Mode.COOP:
		r.append(_row("combo", "coop_diff", SAS.text(20210, "SCHWIERIGKEITSGRAD"), L._coop_diff))
		r.append(_row("yn", "team_lives", SAS.text(20211, "TEAM-LEBEN"), L._team_lives))
		r.append(_row("yn", "crosshair", SAS.text(20212, "FADENKREUZ ZULASSEN"), L._crosshair))
		r.append(_row("num", "coop_lives", SAS.text(20213, "RESPAWN-ANZAHL") + " (-1 = ∞)", L._coop_lives))
		r.append(_row("yn", "spawn_start", SAS.text(20214, "RESPAWN BEIM NEUSTART"), L._spawn_start))
	# Ergänzungen (moderne Felder, unter den Original-Feldern)
	r.append(_row("sep", "extra", tr("WEITERE EINSTELLUNGEN"), null))
	r.append(_row("combo", "cls", tr("Klasse"), L._cls))
	r.append(_row("num", "bots", tr("KI-Soldaten je Team"), L._bots))
	r.append(_row("yn", "vehicles", tr("FAHRZEUGE ERLAUBEN"), L._vehicles))
	r.append(_row("yn", "names", tr("NAMEN ÜBER SPIELERN ERLAUBEN"), L._names))
	r.append(_row("yn", "hits", tr("TREFFERANZEIGE SCHÜTZE ERLAUBEN"), L._hits))
	r.append(_row("yn", "hurts", tr("TREFFER-RICHTUNG GETROFFENER"), L._hurts))
	r.append(_row("yn", "killcam", tr("KILL-CAM"), L._killcam))
	r.append(_row("combo", "support", tr("FUNK-SCHLAG"), L._support))
	r.append(_row("num", "support_min", tr("FUNK ALLE [min]"), L._support_min))
	r.append(_row("yn", "support_bots", tr("KI NUTZT FUNK"), L._support_bots))
	r.append(_row("yn", "precise", tr("PRÄZISES ZIELEN"), L._precise))
	r.append(_row("yn", "flood", tr("FLOOD-SCHUTZ"), L._flood))
	r.append(_row("num", "max_ping", tr("MAX. PING [ms]"), L._max_ping))
	r.append(_row("num", "max_freq", tr("MAX. FREQUENZ [Hz]"), L._max_freq))
	r.append(_row("num", "max_idle", tr("MAX. INAKTIVITÄT [s]"), L._max_idle))
	r.append(_row("yn", "autorestart", tr("AUTORESTART"), L._autorestart))
	r.append(_row("text", "admin_login", tr("Admin-Login"), L._admin_login))
	var ap := _row("text", "admin_pass", tr("Admin-Passwort"), L._admin_pass)
	ap["secret"] = true
	r.append(ap)
	var dc := _row("action", "ded_cfg", tr("DEDIZIERTER SERVER"), null)
	dc["cb"] = func(): L.open_dedicated_config()
	r.append(dc)
	var ps := _row("action", "player_setup", SAS.text(2551, "SPIELER-SETUP"), null)
	ps["cb"] = func():
		L.open_player_setup()
		if is_instance_valid(L.player_setup):
			L.player_setup.tree_exited.connect(func(): if is_instance_valid(self): build())
	r.append(ps)
	return r


func _row(kind: String, id: String, txt: String, w) -> Dictionary:
	return {"kind": kind, "id": id, "label": txt, "w": w}


## Regelzeile per Kennung sichtbar machen (Bildlauf), für Tests und Tastatur
func show_rule(id: String) -> void:
	for i in rows.size():
		if String(rows[i]["id"]) == id:
			scroll = clampi(i - ROWS / 2, 0, maxi(rows.size() - ROWS, 0))
			build()
			return


func _start() -> void:
	status = ""
	lan._host()
	if not Net.is_online and is_instance_valid(self) and is_inside_tree():
		status = lan.status_text()
		build()


func _scroll_maps(d: int) -> void:
	map_scroll += d
	build()


func _scroll_rot(d: int) -> void:
	rot_scroll += d
	build()


func _scroll_rules(d: int) -> void:
	scroll += d
	build()


func _pick_rot(_dbl: bool, i: int) -> void:
	rot_sel = i
	build()


func _voice(d: int) -> void:
	_cycle(lan._voice, d)
	build()