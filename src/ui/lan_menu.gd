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
	UIKit.title("MEHRSPIELER-SPIEL – LAN", 28, v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# --- links: Server erstellen ---
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 460
	cols.add_child(left)
	_head("SERVER ERSTELLEN", left)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	left.add_child(g)
	_name_edit = _line(g, "Servername", "%s – Server" % Net.local_name)
	_map = _option(g, "Karte")
	for id in Game.MP_MAPS:
		_map.add_item(String(Game.MISSIONS[id]["title"]))
		_map.set_item_metadata(_map.item_count - 1, id)
	_mode = _option(g, "Spieltyp")
	for i in 2:      # Besetzung folgt mit den Original-MP-Daten
		_mode.add_item(Net.MODE_NAMES[i], i)
	_maxp = _spin(g, "Spieler (max.)", 2, 16, 8)
	_time = _spin(g, "Zeitlimit (min, 0 = aus)", 0, 60, 10)
	_score = _spin(g, "Punktelimit (0 = aus)", 0, 200, 20)
	_respawn = _spin(g, "Wiedereinstieg (s)", 1, 60, 5)
	_pw = _line(g, "Passwort (optional)", "")
	var host_b := UIKit.button("Server starten", _host, left)
	host_b.name = "HostButton"
	# --- rechts: Serverliste ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_head("SERVER IM LAN", right)
	_list = ItemList.new()
	_list.name = "ServerList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i): _join_listed(i))
	right.add_child(_list)
	var row := HBoxContainer.new()
	right.add_child(row)
	UIKit.button("Beitreten", func():
		var sel := _list.get_selected_items()
		if not sel.is_empty():
			_join_listed(sel[0]), row)
	var g2 := GridContainer.new()
	g2.columns = 2
	right.add_child(g2)
	_ip = _line(g2, "IP-Adresse", "127.0.0.1")
	_join_pw = _line(g2, "Passwort", "")
	UIKit.button("Per IP beitreten", func(): _do_join(_ip.text.strip_edges(), Net.PORT), right)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", UIKit.ACCENT)
	v.add_child(_status)
	UIKit.button("Zurück", func():
		Net.stop_browse()
		back_requested.emit(), v)
	Net.servers_updated.connect(_refresh)
	Net.status_changed.connect(func(t): if is_instance_valid(_status): _status.text = t)
	if not Net.start_browse():
		_status.text = Net.last_error
	elif Net.last_error != "":
		_status.text = Net.last_error
	_refresh()


func _head(t: String, parent: Node) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", UIKit.ACCENT)
	parent.add_child(l)


func _line(g: GridContainer, label: String, val: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var e := LineEdit.new()
	e.text = val
	e.custom_minimum_size.x = 230
	g.add_child(e)
	return e


func _option(g: GridContainer, label: String) -> OptionButton:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var o := OptionButton.new()
	o.custom_minimum_size.x = 230
	g.add_child(o)
	return o


func _spin(g: GridContainer, label: String, lo: int, hi: int, val: int) -> SpinBox:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	g.add_child(s)
	return s


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	_list.clear()
	for k in Net.servers:
		var s: Dictionary = Net.servers[k]
		var i := _list.add_item("%s   –   %s   –   %s   %d/%d%s   (%s)" % [s.get("name", "?"), s.get("map_title", s.get("map", "")),
			Net.MODE_NAMES[clampi(int(s.get("mode", 0)), 0, 2)], int(s.get("players", 0)), int(s.get("max", 8)),
			"  🔒" if s.get("pw", false) else "", s.get("ip", "")])
		_list.set_item_metadata(i, s)


func server_settings() -> Dictionary:
	return {"name": _name_edit.text.strip_edges(), "map": String(_map.get_item_metadata(_map.selected)),
		"mode": _mode.get_selected_id(), "max_players": int(_maxp.value), "time_limit_min": int(_time.value),
		"score_limit": int(_score.value), "respawn_s": int(_respawn.value), "password": _pw.text, "port": Net.PORT}


func _host() -> void:
	Net.stop_browse()
	if not Net.host(server_settings()):
		_status.text = Net.last_error
		Net.start_browse()


func _join_listed(i: int) -> void:
	var s: Dictionary = _list.get_item_metadata(i)
	_do_join(String(s.get("ip", "")), int(s.get("port", Net.PORT)))


func _do_join(ip: String, port: int) -> void:
	if ip == "":
		return
	Net.stop_browse()
	if not Net.join(ip, port, _join_pw.text):
		_status.text = Net.last_error
		Net.start_browse()
