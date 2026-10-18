class_name LoadingScreen
extends OrigScreen
## Original-Ladebildschirm je Karte (MISSIONS\<m>\loader.4ds → orig_cache/<m>/loader_layout.json, tools/fmt_mp_screens.py):
##  Einzelspieler: Missionsbild „screen“ (LOADER_*), Titel, Briefing-Text, Textzeile, Ladebalken „loadbar“ (LOADINGBAR.BMP)
##  Mehrspieler:   MP_screen (X_NMN01–12), Kartenbild „mapa“ (MAPA_*), Flaggen, Kartenname/Spielstil, Teams mit
##                 Spielerlisten, Aufgaben (HD2-Aufgaben), Fortschrittszeile T8904 „Mission wird geladen“, Ladebalken
## Ohne Layout: schlichter dunkler Bildschirm mit Titel und Balken. Fortschritt setzt MissionLoader.

var mission_id := ""
var progress := 0.0
var _bar: TrisView
var _bar_rect := Rect2(312, 690, 400, 12)
var _bar_fill: ColorRect
var _status: Label


func open(id: String) -> void:
	mission_id = id
	setup_stage()
	var e: Dictionary = Game.MISSIONS.get(id, {})
	var folder := Game.orig_folder(id).to_lower()
	frames = {}
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/loader_layout.json") if folder != "" else null
	if typeof(d) == TYPE_DICTIONARY:
		for f in d.get("frames", []):
			frames[String(f["name"])] = f
	var title_txt := String(e.get("title", id))
	if frames.has("MP_screen"):
		_build_mp(e, title_txt)
	elif frames.has("screen"):
		_build_sp(e, title_txt)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.06, 0.05)
		bg.size = REF
		stage.add_child(bg)
		var img_path := String(e.get("map_image", ""))
		if img_path != "" and ResourceLoader.exists(img_path):
			# Eigene Karten ohne Original-loader.4ds (Registerschlüssel map_image): Kartenbild, Titel, Spielstil, Kurzbeschreibung
			var tr := TextureRect.new()
			tr.name = "MapImage"
			tr.texture = load(img_path)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.position = Vector2(337, 40)
			tr.size = Vector2(350, 350)
			stage.add_child(tr)
			label(Rect2(112, 404, 800, 44), title_txt, 30, Color(0.85, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER).name = "Title"
			var fixed = e.get("mp_mode")
			if Net.is_online or fixed != null:
				var md: int = int(Net.settings.get("mode", fixed if fixed != null else 0)) if Net.is_online else int(fixed)
				label(Rect2(112, 450, 800, 26), ServerFilterScreen.style_name(md), 17, Color(0.75, 0.7, 0.6),
					HORIZONTAL_ALIGNMENT_CENTER).name = "Style"
			label(Rect2(162, 486, 700, 180), String(e.get("briefing", "")), 14, Color(0.8, 0.76, 0.66),
				HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, true).name = "Briefing"
		else:
			label(Rect2(112, 300, 800, 60), title_txt, 30, Color(0.85, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER).name = "Title"
	if frames.has("loadbar"):
		_bar_rect = rect("loadbar", _bar_rect)
	if frames.has("loadbar"):
		_bar = draw_frame("loadbar")
	else:
		_bar_fill = ColorRect.new()
		_bar_fill.color = Color(0.1, 0.09, 0.07)
		stage.add_child(_bar_fill)
		_bar_fill.position = _bar_rect.position
		_bar_fill.size = Vector2(0, _bar_rect.size.y)
	_status = label(Rect2(_bar_rect.position.x, _bar_rect.end.y + 4, _bar_rect.size.x, 22),
		SAS.text(8904, "Mission wird geladen"), 14, INK if frames.has("MP_screen") else Color(0.9, 0.85, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER)
	_status.name = "Status"
	if frames.has("MP_progress"):
		_status.position = rect("MP_progress").position
		_status.size = rect("MP_progress").size + Vector2(260, 0)
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	set_progress(0.0)


func _build_sp(e: Dictionary, title_txt: String) -> void:
	draw_frame("screen")
	text_at("title", title_txt, 24, HORIZONTAL_ALIGNMENT_CENTER, INK)
	var brief := String(e.get("briefing", ""))
	if brief != "":
		text_at("briefing", brief, 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
	text_at("textbar", SAS.text(8904, "Mission wird geladen"), 15, HORIZONTAL_ALIGNMENT_CENTER, INK)


func _build_mp(e: Dictionary, title_txt: String) -> void:
	draw_frames(["MP_screen", "cara", "table04", "mapa", "vlajka axis", "vlajka allied"])
	text_at("text_h&dversion", "Dangerous and Hidden 2 (unofficial) · v%s" % ProjectSettings.get_setting("application/config/version"), 14)
	text_at("MP_text_screen", String(Net.settings.get("name", SAS.text(2301, "Mehrspieler-Spielmenü"))), 22, HORIZONTAL_ALIGNMENT_RIGHT)
	text_at("MP_title", title_txt.get_slice(" (", 0), 26, HORIZONTAL_ALIGNMENT_CENTER)
	var fixed = e.get("mp_mode")
	var mode := int(Net.settings.get("mode", fixed if fixed != null else 0))
	text_at("MP_designated", ServerFilterScreen.style_name(mode), 15, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("MP_map survey", SAS.text(2303, "KARTE"), 14)
	# Teams: links Alliierte (Flagge X_FLGALL), rechts Achse – Namen und Spielerlisten aus Net.players
	text_at("MP_team allied2", "Alliierte", 15, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("MP_team allied1", "Achsenmächte", 15, HORIZONTAL_ALIGNMENT_CENTER)
	var allied: PackedStringArray = []
	var axis: PackedStringArray = []
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var t := int(p.get("team", -1))
		var nm := String(p.get("name", "?"))
		if t == Soldier.TEAM_AXIS or (t != Soldier.TEAM_ALLIED and axis.size() < allied.size()):
			axis.append(nm)          # Deathmatch (eigene Seiten): abwechselnd auf beide Listen
		else:
			allied.append(nm)
	text_at("MP_list1", "\n".join(allied), 13, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
	text_at("MP_list2", "\n".join(axis), 13, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
	if frames.has("MP_objective1"):
		var al: PackedStringArray = []
		var ax: PackedStringArray = []
		for o in _objectives(String(e.get("orig", ""))):
			al.append("○ " + String(o.get("allied_text", "")))
			ax.append("○ " + String(o.get("axis_text", "")))
		text_at("MP_objective1", "\n".join(al), 12, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
		text_at("MP_objective2", "\n".join(ax), 12, HORIZONTAL_ALIGNMENT_LEFT, INK, true)


static func _objectives(folder: String) -> Array:
	var d = LsRuntime._read_json(OrigLevel.cache_path(folder) + "/mp.json")
	if typeof(d) != TYPE_DICTIONARY or (d.get("game_styles", []) as Array).is_empty():
		return []
	return d["game_styles"][0].get("objectives", [])


## Fortschritt 0…1 (Balken „loadbar“ wächst von links wie im Original), optional neue Statuszeile
func set_progress(frac: float, text := "") -> void:
	progress = clampf(frac, 0.0, 1.0)
	if is_instance_valid(_bar):
		_bar.squeeze = Vector2(progress, 1.0)
		_bar.squeeze_origin = _bar_rect.position
		_bar.queue_redraw()
	elif is_instance_valid(_bar_fill):
		_bar_fill.size = Vector2(_bar_rect.size.x * progress, _bar_rect.size.y)
	if is_instance_valid(_status):
		_status.text = "%s  %d %%" % [text if text != "" else SAS.text(8904, "Mission wird geladen"), roundi(progress * 100.0)]
