class_name ServerBrowserScreen
extends OrigScreen
## 0.11.1: Original-Serverbrowser „MEHRSPIELER-SPIEL – INTERNET“ nach MODELS\multiplayer menu.4ds (Serverliste
## table00 mit Spalten HOSTNAME/KARTE/ART/PING/SPIELER T2302–2306, Zeilenvorlage sever00 mit Symbolen Passwort/
## dediziert/Voice, Knöpfe SPIEL BEITRETEN 2310, SERVER ERSTELLEN 2311, SPIEL-INFO 2312, ZURÜCK 2313, SERVER-IP
## EINGEBEN 2308, SERVER-FILTER 2309, LISTE NEU EINLESEN/AKTUALISIEREN 2325/2327, FAVORITEN/GESAMTLISTE 20100/20101,
## ZU FAVORITEN HINZUFÜGEN/AUS FAVORITEN LÖSCHEN 20102/20103, Statuszeile text_online).
## Daten: Masterserver über MasterLink (echtes Modul /root/Master oder Ersatz); Favoriten/Filter/Spiel-Info und
## Beitritt über das LanMenu (Eltern). Nicht-rankede Server (ranked = false): „!“ in der Zeile und Rückfrage vor dem
## Beitritt. Das GameSpy-Logo des Modells wird nicht gezeichnet (kein GameSpy).

signal create_requested
signal back_requested

const ROW_Y0 := 221.0
const ROW_H := 32.6
const ROWS := 11
## Spalten [x0, x1] nach den Kopf-Knöpfen bhost name/bmap/bstyle/bping/bplayers/max
const COLS := {"name": [196.0, 434.0], "map": [436.0, 580.0], "style": [582.0, 729.0], "ping": [731.0, 803.0],
	"players": [806.0, 926.0]}
const UNRANKED_WARNING := "Möglicherweise kein Original-Server – keine Ränge"

var lan: Node                      ## LanMenu (Favoriten, Filter, Spiel-Info, Beitritt)
var master: Node
var entries: Array = []            ## aktuell angezeigte Einträge (Net-Feldnamen, sortiert/gefiltert)
var master_list: Array = []        ## letzte Master-Liste (Net-Feldnamen)
var favorites_view := false
var selected := -1
var scroll := 0
var sort_key := ""
var status_text := ""
var hidden_count := 0
var _ip_panel: Control


func open(lan_menu: Node) -> void:
	lan = lan_menu
	setup_stage()
	master = MasterLink.source(get_tree())
	if master.has_signal("servers_updated") and not master.servers_updated.is_connected(_on_master_list):
		master.servers_updated.connect(_on_master_list)
	if master.has_signal("status_changed") and not master.status_changed.is_connected(_on_master_status):
		master.status_changed.connect(_on_master_status)
	if not Net.servers_updated.is_connected(_on_fav_update):
		Net.servers_updated.connect(_on_fav_update)
	build()
	# Ablauf: nach der Zustimmung sofort verbinden und die Liste laden
	master.call("connect_master")


func _exit_tree() -> void:
	if master and is_instance_valid(master):
		if master.servers_updated.is_connected(_on_master_list):
			master.servers_updated.disconnect(_on_master_list)
		if master.status_changed.is_connected(_on_master_status):
			master.status_changed.disconnect(_on_master_status)
	if Net.servers_updated.is_connected(_on_fav_update):
		Net.servers_updated.disconnect(_on_fav_update)


func _on_master_list(list: Array) -> void:
	master_list = list.map(func(e): return MasterLink.to_net(e))
	status_text = tr("Serverliste geladen") + ": %d" % master_list.size()
	if not favorites_view:
		build()


## Master: status_changed(state, text) – state off/no_build/connecting/online/offline
func _on_master_status(state, text = null) -> void:
	var st := str(state)
	match st:
		"off", "no_build", "offline":
			status_text = tr(MasterLink.UNREACHABLE)
		"connecting":
			status_text = tr("Verbinde mit dem Masterserver …")
		"online":
			status_text = tr("Serverliste geladen") + ": %d" % master_list.size()
		_:
			status_text = str(text) if text != null else st
	if is_instance_valid(stage) and stage.get_node_or_null("text_online"):
		(stage.get_node("text_online") as Label).text = _status_line()


func _on_fav_update() -> void:
	if favorites_view:
		build()


func _status_line() -> String:
	var s := status_text
	if hidden_count > 0:
		s += ("   " if s != "" else "") + "Filter: %d" % hidden_count
	return s


## Quelle der Liste: Master-Server oder Favoriten (mit Abfrage-Antworten aus Net.fav_info)
func source_list() -> Array:
	if not favorites_view:
		return master_list
	var out: Array = []
	for a in Net.favorites:
		var info: Dictionary = Net.fav_info.get(a, {})
		var d := info.duplicate()
		d["ip"] = String(a).get_slice(":", 0)
		d["port"] = int(String(a).get_slice(":", 1)) if String(a).contains(":") else Net.PORT
		d["key"] = a
		if info.is_empty():
			d["name"] = String(a)
			d["offline"] = true
		out.append(d)
	return out


func _refresh_entries() -> void:
	entries = []
	hidden_count = 0
	for s in source_list():
		if Net.filter_pass(s):
			entries.append(s)
		else:
			hidden_count += 1
	if sort_key != "":
		entries.sort_custom(func(a, b): return _sort_val(a) < _sort_val(b))
	selected = clampi(selected, -1, entries.size() - 1)
	scroll = clampi(scroll, 0, maxi(entries.size() - ROWS, 0))


func _sort_val(s: Dictionary):
	match sort_key:
		"ping":
			var p := int(s.get("ping", -1))
			return p if p >= 0 else 99999
		"players":
			return -int(s.get("players", 0))
		"style":
			return int(s.get("mode", 0))
		"map":
			return String(s.get("map_title", s.get("map", ""))).to_lower()
	return String(s.get("name", "")).to_lower()


func build() -> void:
	_refresh_entries()
	begin("multiplayer menu")
	title(2321, "MEHRSPIELER-SPIEL - INTERNET")
	draw_frames(["table00"])
	# Spaltenköpfe (Klick = sortieren)
	orig_button("bhost name", SAS.text(2302, "HOSTNAME"), _sort.bind("name"), true, "HeadName", 14)
	orig_button("bmap", SAS.text(2303, "KARTE"), _sort.bind("map"), true, "HeadMap", 14)
	orig_button("bstyle", SAS.text(2304, "ART"), _sort.bind("style"), true, "HeadStyle", 14)
	orig_button("bping", SAS.text(2305, "PING"), _sort.bind("ping"), true, "HeadPing", 14)
	orig_button("bplayers/max", SAS.text(2306, "SPIELER"), _sort.bind("players"), true, "HeadPlayers", 14)
	# Bildlaufleiste
	draw_frames(["sliderbase"])
	var n := entries.size()
	if n > ROWS:
		var base := rect("sliderbase", Rect2(81.5, 262.1, 33.2, 290.8))
		var h := maxf(18.5, base.size.y * ROWS / n)
		var y := base.position.y + (base.size.y - h) * scroll / maxf(n - ROWS, 1)
		draw_frame("normal09", Vector2(0, y - rect("normal09", Rect2(81.5, 283.2, 33.2, 18.5)).position.y))
	orig_button("barrow up", "", func(): _scroll(-1), scroll > 0, "ScrollUp")
	orig_button("barrow down", "", func(): _scroll(1), scroll < n - ROWS, "ScrollDown")
	var list := Control.new()
	list.name = "ServerRows"
	list.size = REF
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(list)
	for k in mini(ROWS, n - scroll):
		_row(k, scroll + k)
	# Knöpfe
	var sel_ok := selected >= 0
	orig_button("bjoin game", SAS.text(2310, "SPIEL BEITRETEN"), join_selected, sel_ok, "JoinButton")
	orig_button("bcreate server", SAS.text(2311, "SERVER ERSTELLEN"), func(): create_requested.emit(), true, "CreateButton")
	orig_button("brefresh list", SAS.text(2327, "LISTE AKTUALISIEREN"), refresh, true, "UpdateButton", 15)
	orig_button("brestore list", SAS.text(2325, "LISTE NEU EINLESEN"), reconnect, true, "RereadButton", 15)
	orig_button("bfavorites", SAS.text(20101 if favorites_view else 20100, "GESAMTLISTE" if favorites_view else "FAVORITEN"),
		toggle_favorites, true, "FavoritesButton", 15)
	orig_button("bserver filters", SAS.text(2309, "SERVER-FILTER"), func(): lan.call("open_filter"), true, "FilterButton", 15)
	orig_button("bview game info", SAS.text(2312, "SPIEL-INFO"), _info, sel_ok, "GameInfoButton", 15)
	orig_button("badd/remove", SAS.text(20103 if favorites_view else 20102,
		"AUS FAVORITEN LÖSCHEN" if favorites_view else "ZU FAVORITEN HINZUFÜGEN"), _fav_add_remove, sel_ok, "FavAddRemove", 13)
	orig_button("benter server ip", SAS.text(2308, "SERVER-IP EINGEBEN"), open_ip_entry, true, "EnterIpButton", 15)
	orig_button("bback", SAS.text(2313, "ZURÜCK"), func(): back_requested.emit(), true, "BackButton")
	var st := text_at("text_online", _status_line(), 14, HORIZONTAL_ALIGNMENT_LEFT, INK, false, Rect2(73, 606.3, 865.4, 25))
	st.name = "text_online"


func _row(k: int, i: int) -> void:
	var s: Dictionary = entries[i]
	var y := ROW_Y0 + k * ROW_H
	var dy := y - ROW_Y0
	var parent: Control = stage.get_node("ServerRows")
	if i == selected:
		draw_frame("normal10", Vector2(0, dy), {}, parent)
	# Symbole wie Original (Passwort, dediziert, Voice) in der Zeilenvorlage
	if bool(s.get("pw", false)):
		draw_frame("xpassword", Vector2(0, dy), {}, parent)
	if bool(s.get("ded", false)):
		draw_frame("xdedicated", Vector2(0, dy), {}, parent)
	if int(s.get("voice", 0)) > 0:
		draw_frame("xvoice", Vector2(0, dy), {}, parent)
	var off := bool(s.get("offline", false))
	var name_txt := String(s.get("name", "?"))
	var ranked := bool(s.get("ranked", true))
	var x0: float = COLS["name"][0]
	if not ranked and not favorites_view:
		var ex := label(Rect2(x0, y, 14, ROW_H), "!", 17, INK_RED, HORIZONTAL_ALIGNMENT_CENTER)
		ex.name = "Unranked%d" % i
		x0 += 15.0
	label(Rect2(x0, y, COLS["name"][1] - x0, ROW_H), name_txt, 14).name = "RowName%d" % i
	if not off:
		_cell("map", y, String(s.get("map_title", s.get("map", ""))))
		_cell("style", y, Net.MODE_NAMES[clampi(int(s.get("mode", 0)), 0, Net.MODE_NAMES.size() - 1)])
		_cell("ping", y, str(int(s["ping"])) if int(s.get("ping", -1)) >= 0 else "–", HORIZONTAL_ALIGNMENT_RIGHT)
		_cell("players", y, "%d/%d" % [int(s.get("players", 0)), int(s.get("max", 8))], HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_cell("map", y, "–")
	hit(Rect2(117.7, y, 809, ROW_H), func(dbl: bool = false):
		selected = i
		if dbl:
			join_selected()
		else:
			build(), "Row%d" % i)


func _cell(col: String, y: float, txt: String, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	label(Rect2(COLS[col][0], y, COLS[col][1] - COLS[col][0], ROW_H), txt, 14, INK, align)


func _sort(key: String) -> void:
	sort_key = "" if sort_key == key else key
	build()


func _scroll(d: int) -> void:
	scroll = clampi(scroll + d, 0, maxi(entries.size() - ROWS, 0))
	build()


func refresh() -> void:
	if favorites_view:
		Net.update_list()
	else:
		master.call("refresh_servers", Net.server_filter)


func reconnect() -> void:
	if favorites_view:
		Net.reread_list()
	else:
		master.call("connect_master")


func toggle_favorites() -> void:
	favorites_view = not favorites_view
	Net.browsing_favorites = favorites_view
	selected = -1
	scroll = 0
	if favorites_view:
		Net.update_list()
	build()


func selected_entry() -> Dictionary:
	return entries[selected] if selected >= 0 and selected < entries.size() else {}


func _fav_add_remove() -> void:
	var s := selected_entry()
	if s.is_empty():
		return
	if favorites_view:
		Net.remove_favorite(String(s.get("key", "")))
		selected = -1
	else:
		Net.add_favorite("%s:%d" % [String(s.get("ip", "")), int(s.get("port", Net.PORT))])
	build()


func _info() -> void:
	var s := selected_entry()
	if not s.is_empty():
		lan.call("open_game_info_for", s)


## SPIEL BEITRETEN: nicht-rankede Server erst nach Rückfrage
func join_selected() -> void:
	var s := selected_entry()
	if s.is_empty():
		return
	request_join(s)


func request_join(s: Dictionary) -> void:
	if not bool(s.get("ranked", true)) and not favorites_view:
		dialog(tr(UNRANKED_WARNING), [[SAS.text(2310, "SPIEL BEITRETEN"), func(): _join(s)],
			[SAS.text(2313, "ZURÜCK"), func(): pass]]).name = "UnrankedDialog"
		return
	_join(s)


func _join(s: Dictionary) -> void:
	lan.call("join_server", String(s.get("ip", "")), int(s.get("port", Net.PORT)))


## SERVER-IP EINGEBEN: kleine Eingabe (IP/Name[:Port] + Passwort) über dem Bildschirm
func open_ip_entry() -> void:
	if is_instance_valid(_ip_panel):
		_ip_panel.queue_free()
	var p := Control.new()
	p.name = "IpEntry"
	p.size = REF
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(p)
	_ip_panel = p
	var lay := load_layout("password")
	var center := REF * 0.5
	if not lay.is_empty():
		draw_from(lay, ["shadow01", "confirm"], p, center)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.72, 0.68, 0.58)
		bg.position = center - Vector2(180, 90)
		bg.size = Vector2(360, 180)
		p.add_child(bg)
	var t := Label.new()
	t.text = SAS.text(2308, "SERVER-IP EINGEBEN")
	t.position = center + Vector2(-170, -80)
	t.size = Vector2(340, 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", INK)
	p.add_child(t)
	var ip := LineEdit.new()
	ip.name = "IpEdit"
	ip.text = String(lan.get("_ip").text) if lan.get("_ip") else ""
	ip.position = center + Vector2(-150, -48)
	ip.size = Vector2(300, 30)
	p.add_child(ip)
	var pw := LineEdit.new()
	pw.name = "PwEdit"
	pw.secret = true
	pw.placeholder_text = tr("Passwort")
	pw.position = center + Vector2(-150, -10)
	pw.size = Vector2(300, 30)
	p.add_child(pw)
	var ok := Button.new()
	ok.name = "IpJoin"
	ok.text = SAS.text(2310, "SPIEL BEITRETEN")
	ok.position = center + Vector2(-150, 34)
	ok.size = Vector2(145, 32)
	ok.pressed.connect(func():
		var addr := ip.text.strip_edges()
		if lan.get("_join_pw"):
			lan.get("_join_pw").text = pw.text
		if lan.get("_ip"):
			lan.get("_ip").text = addr
		p.queue_free()
		lan.call("join_server", addr, Net.PORT))
	p.add_child(ok)
	var cancel := Button.new()
	cancel.name = "IpCancel"
	cancel.text = SAS.text(2313, "ZURÜCK")
	cancel.position = center + Vector2(5, 34)
	cancel.size = Vector2(145, 32)
	cancel.pressed.connect(func(): p.queue_free())
	p.add_child(cancel)
	for b in [ok, cancel]:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_font_size_override("font_size", 15)
