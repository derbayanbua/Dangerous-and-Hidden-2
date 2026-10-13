extends Control
## Hauptmenü nach dem Original (MODELS\main_menu.4ds, singleplayer.4ds, options.4ds, single mission 2.4ds;
## Rekonstruktion: orig_cache/ui/menu/menu_spec.json, docs/re_notes_menu.md).
## 1024×768-Bühne wie im Original, skaliert mit Letterbox. Texte aus den Originaltexten (Text\german),
## Hintergründe/Buttons aus den Originaltexturen (nur lokal im orig_cache). Noch nicht umgesetzte
## Menüpunkte (Profile, Mehrspieler, Filme, Einzelgänger, Blutbad) sind ausgegraut.
## Ohne Original-Cache: gleiches Menü mit schlichtem Ersatzlayout.

const REF := Vector2(1024, 768)
const BTN_X := 525.4
const BTN_W := 414.0
const BTN_H := 35.8
const TEXT_COLOR := Color(0.17, 0.13, 0.08)
const TEXT_HOVER := Color(0.45, 0.08, 0.04)
const TEXT_DISABLED := Color(0.17, 0.13, 0.08, 0.35)

## Fallback-Struktur (Text-ID, Ersatztext) falls menu_spec.json fehlt
const FALLBACK_TEXTS := {
	2101: "HAUPTMENÜ", 2105: "WEITER SPIELEN", 2106: "PROFIL ÄNDERN", 2107: "EINZELSPIELER-SPIEL",
	2115: "MEHRSPIELER-SPIEL - LAN", 2116: "MEHRSPIELER-SPIEL - INTERNET", 2109: "FILME", 2110: "EINSTELLUNGEN",
	2111: "MITWIRKENDE", 2112: "ENDE", 2201: "EINZELSPIELER-SPIEL", 2202: "KAMPAGNE", 2203: "EINZELGÄNGER",
	2204: "BLUTBAD", 2205: "EINZELMISSION", 2206: "EINZELMISSION - BLUTBAD", 2208: "ZURÜCK",
	2251: "EINZELMISSION", 2256: "ZURÜCK", 2258: "Missions-Liste:", 2357: "START",
	2401: "EINSTELLUNGEN", 2405: "GRAFIK-EINSTELLUNGEN", 2406: "SOUND-EINSTELLUNGEN",
	2407: "STEUERUNGS-EINSTELLUNGEN", 2408: "SPIEL-EINSTELLUNGEN", 2409: "MEHRSPIELER-SPIEL-EINSTELLUNGEN",
	2410: "ZURÜCK", 2102: "Datum und Zeit aktuell:", 2103: "Aktuelles Profil",
	2104: "Datum und Zeit des letzten gespeicherten Spielstandes:", 2020: "KEIN AKTUELLES PROFIL",
	2021: "KEIN GESPEICHERTER SPIELSTAND",
}

var spec := {}
var texts := {}
var stage: Control
var _menu_dir := ""
var _tex_cache := {}
var _music: AudioStreamPlayer
var _click: AudioStreamPlayer
var _brief_root: Control
var _desc_label: Label
var _side_image: TextureRect
var _credits_root: Control
var current_menu := ""
var _wide_bg: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Breitbild/Hochformat: Ränder mit dem (abgedunkelten) Original-Hintergrund füllen statt schwarzer Balken
	_wide_bg = TextureRect.new()
	_wide_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wide_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wide_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wide_bg.modulate = Color(0.45, 0.45, 0.45)
	_wide_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wide_bg)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = REF
	stage.clip_contents = true
	add_child(stage)
	resized.connect(_fit)
	_menu_dir = OrigLevel.cache_root() + "/ui/menu"
	var s = LsRuntime._read_json(_menu_dir + "/menu_spec.json")
	spec = s if typeof(s) == TYPE_DICTIONARY else {}
	var t = LsRuntime._read_json(OrigLevel.cache_root() + "/texts_german.json")
	texts = t if typeof(t) == TYPE_DICTIONARY else {}
	_setup_audio()
	_fit.call_deferred()
	show_menu("main_menu")


func _fit() -> void:
	var k := minf(size.x / REF.x, size.y / REF.y)
	stage.scale = Vector2(k, k)
	stage.position = (size - REF * k) * 0.5


func text(id: int) -> String:
	if texts.has(str(id)):
		return String(texts[str(id)])
	return FALLBACK_TEXTS.get(id, "#%d" % id)


# --- Bausteine ---------------------------------------------------------------

func _tex(file: String) -> Texture2D:
	if _tex_cache.has(file):
		return _tex_cache[file]
	# beste verfügbare Fassung: KI-4K, KI-HD, Original (tools/upscale_textures.py -> <ordner>_4k/_hd)
	var path := _menu_dir + "/" + file
	for suffix: String in ["_4k", "_hd"]:
		var alt := _menu_dir + "/" + file.get_base_dir() + suffix + "/" + file.get_file()
		if file.get_base_dir() != "" and FileAccess.file_exists(alt):
			path = alt
			break
	var tx: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			tx = ImageTexture.create_from_image(img)
	_tex_cache[file] = tx
	return tx


func _items(menu: String) -> Array:
	return spec.get("menus", {}).get(menu, {}).get("items", [])


func _item(menu: String, id: String) -> Dictionary:
	for it in _items(menu):
		if it.get("id", "") == id:
			return it
	return {}


func _rect_of(it: Dictionary, fallback: Rect2) -> Rect2:
	var r: Array = it.get("rect_px_1024x768", [])
	if r.size() == 4:
		return Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])
	return fallback


func _clear() -> void:
	for c in stage.get_children():
		c.queue_free()
	_desc_label = null
	_side_image = null


func _background(menu: String) -> void:
	var file: String = spec.get("menus", {}).get(menu, {}).get("background", "")
	var tx := _tex(file) if file != "" else null
	_wide_bg.texture = tx
	if tx:
		var tr := TextureRect.new()
		tr.texture = tx
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = REF
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.72, 0.68, 0.58)
		cr.size = REF
		stage.add_child(cr)
	# Titel (Frame text_screen) und Versionszeile (text_h&dversion)
	var title_id := int(spec.get("menus", {}).get(menu, {}).get("title_text_id", 0))
	if title_id:
		_label(Rect2(584.7, 44.0, 354.5, 43.0), text(title_id), 24, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(Rect2(71.2, 61.6, 414.1, 23.1), "Dangerous Hidden 2 · v%s" % ProjectSettings.get_setting("application/config/version"),
		14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)


func _label(r: Rect2, txt: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = r.position
	l.size = r.size
	l.text = txt
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = true
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


func _atlas_style(it: Dictionary, key: String) -> StyleBox:
	var part: Dictionary = it.get(key, {})
	var tx := _tex(String(part.get("texture", "")).to_lower().get_basename() + ".png") if part.has("texture") else null
	if tx == null:
		tx = _tex("textures/" + String(part.get("texture", "")).to_lower().get_basename() + ".png") if part.has("texture") else null
	if tx == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.62, 0.57, 0.46) if key == "normal" else Color(0.78, 0.72, 0.58)
		flat.border_color = Color(0.3, 0.26, 0.2)
		flat.set_border_width_all(2)
		return flat
	var uv: Array = part.get("uv_rect", [0, 0, 1, 1])
	var at := AtlasTexture.new()
	at.atlas = tx
	var ts := tx.get_size()
	at.region = Rect2(uv[0] * ts.x, uv[1] * ts.y, (uv[2] - uv[0]) * ts.x, (uv[3] - uv[1]) * ts.y)
	var sb := StyleBoxTexture.new()
	sb.texture = at
	return sb


## Original-Button: Normal-/Hover-Grafik aus dem X_NMNBTN-Atlas, Originaltext.
func _button(menu: String, id: String, label: String, fallback_rect: Rect2, cb: Callable, enabled := true,
		desc_id := 0, side_image := "") -> Button:
	var it := _item(menu, id)
	var r := _rect_of(it, fallback_rect)
	var b := Button.new()
	b.name = id.validate_node_name()
	b.position = r.position
	b.size = r.size
	b.text = label
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", TEXT_HOVER)
	b.add_theme_color_override("font_focus_color", TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", TEXT_HOVER)
	b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	var normal := _atlas_style(it, "normal")
	var hover := _atlas_style(it, "hover") if it.has("hover") else normal
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	b.disabled = not enabled
	if not enabled:
		b.tooltip_text = "Noch nicht umgesetzt"
		b.modulate = Color(1, 1, 1, 0.75)
	b.pressed.connect(func():
		_click.play()
		cb.call())
	if desc_id or side_image != "":
		b.mouse_entered.connect(_on_hover.bind(desc_id, side_image))
	stage.add_child(b)
	return b


func _std_rect(i: int, top := 353.6, step := 39.4) -> Rect2:
	return Rect2(BTN_X, top + i * step, BTN_W, BTN_H)


func _on_hover(desc_id: int, img: String) -> void:
	if _desc_label and desc_id:
		_desc_label.text = text(2210) + "\n\n" + text(desc_id)
	if _side_image and img != "":
		var tx := _tex("textures/" + img)
		if tx:
			_side_image.texture = tx


# --- Menüs -------------------------------------------------------------------

func show_menu(menu: String) -> void:
	current_menu = menu
	_clear()
	match menu:
		"main_menu":
			_main_menu()
		"singleplayer":
			_singleplayer()
		"campaign":
			_mission_list("campaign")
		"single_mission":
			_mission_list("single")
		"options":
			_options_menu()


func _main_menu() -> void:
	_background("main_menu")
	if not spec.get("menus", {}).has("main_menu"):
		_label(Rect2(584.7, 44.0, 354.5, 43.0), text(2101), 24, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	# Infoblock rechts: Datum/Zeit, Profil, letzter Spielstand
	var info := [
		["text_date00", text(2102)], ["text_date01", Time.get_datetime_string_from_system(false, true)],
		["text_profile00", text(2103)], ["text_profile01", text(2020)],
		["text_last save00", text(2104)], ["text_last save01", _last_save_text()]]
	var y := 129.3
	for pair in info:
		var it := _item("main_menu", pair[0])
		var bold: bool = pair[0].ends_with("01")
		_label(_rect_of(it, Rect2(541.3, y, 394.7, 18.0)), pair[1], 15 if bold else 13, TEXT_COLOR)
		y += 30.0
	var has_save := Game.has_save("quick")
	var entries := [
		["bresume game", 2105, func(): Game.load_game("quick"), has_save],
		["bchange profile", 2106, func(): pass, false],
		["bsingleplayer", 2107, func(): show_menu("singleplayer"), true],
		["bmultiplayerlan", 2115, func(): pass, false],
		["bmultiplayernet", 2116, func(): pass, false],
		["bcinematics", 2109, func(): pass, false],
		["boptions", 2110, func(): show_menu("options"), true],
		["bcredits", 2111, _show_credits, true],
		["bexit", 2112, func(): get_tree().quit(), true],
	]
	for i in entries.size():
		var e: Array = entries[i]
		_button("main_menu", e[0], text(e[1]), _std_rect(i), e[2], e[3])


func _last_save_text() -> String:
	if not Game.has_save("quick"):
		return text(2021)
	var path := ProjectSettings.globalize_path("%s/quick.json" % Game.SAVE_DIR)
	var mt := FileAccess.get_modified_time(path)
	return Time.get_datetime_string_from_unix_time(mt, true) if mt > 0 else "Schnellspeicherstand"


func _singleplayer() -> void:
	_background("singleplayer")
	# Bild links oben wechselt bei Hover (Original X_SI_*), Beschreibungsfeld links unten
	_side_image = TextureRect.new()
	_side_image.position = Vector2.ZERO          # Original: Frame "single side", 512×512 px oben links
	_side_image.size = Vector2(512, 512)
	_side_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_side_image)
	_desc_label = _label(_rect_of(_item("singleplayer", "text00"), Rect2(67.9, 478.2, 416.1, 230.7)), text(2210), 14, TEXT_COLOR)
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label(_rect_of(_item("singleplayer", "text_HD2original"), Rect2(525.4, 96.4, 414.0, 39.0)), text(20400) if texts.has("20400") else "H&D2 Original",
		18, TEXT_COLOR)
	var any_campaign := Game.alive_roster().size() > 0
	# Unveränderte Original-Belegung (ohne Sabre-Squadron-Datadisk): 5 Spielarten + Zurück
	_button("singleplayer", "bcampaign", text(2202), _std_rect(0, 139.0, 43.8), func(): show_menu("campaign"), any_campaign, 2211, "x_si_cmp.png")
	_button("singleplayer", "blone wolf", text(2203), _std_rect(1, 139.0, 43.8), func(): pass, false, 2212, "x_si_lnw.png")
	_button("singleplayer", "carnage", text(2204), _std_rect(2, 139.0, 43.8), func(): pass, false, 2213, "x_si_crn.png")
	_button("singleplayer", "bsingle mission", text(2205), Rect2(BTN_X, 478.2, BTN_W, BTN_H), func(): show_menu("single_mission"), true, 2214, "x_si_sim.png")
	_button("singleplayer", "bsingle mission- carnage", text(2206), Rect2(BTN_X, 522.0, BTN_W, BTN_H), func(): pass, false, 2215, "x_si_sic.png")
	_button("singleplayer", "bback", text(2208), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func(): show_menu("main_menu"))
	_on_hover(2211, "x_si_cmp.png")


## Kampagne (Originalteile) bzw. Einzelmission (freigeschaltete Teile + eigene Übungseinsätze).
func _mission_list(kind: String) -> void:
	_background("single_mission")
	_label(Rect2(584.7, 44.0, 354.5, 43.0), text(2202) if kind == "campaign" else text(2251), 24, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(_rect_of(_item("single_mission", "text_list of profiles"), Rect2(70.1, 102.5, 414.0, 23.2)), text(2258), 15, TEXT_COLOR)
	var desc := _label(_rect_of(_item("single_mission", "text00"), Rect2(525.4, 370.3, 414.0, 240.6)), "", 13, TEXT_COLOR)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var ids: Array = []
	if kind == "campaign":
		ids = Game.CAMPAIGN_ORDER.duplicate()
	else:
		for id in Game.CAMPAIGN_ORDER:
			if Game.is_unlocked(id):
				ids.append(id)
		ids.append_array(Game.PRACTICE_MISSIONS)
	var selected := [""]
	var start_b: Button
	var y := 132.0
	var n := 1
	for id in ids:
		var unlocked := Game.is_unlocked(id)
		var done: bool = Game.campaign.get("completed", []).has(id)
		var title: String = Game.MISSIONS[id]["title"]
		if Game.PRACTICE_MISSIONS.has(id):
			title = "Übung: " + title
		var label := "%d. %s%s" % [n, title, "  ✓" if done else ""] if unlocked else "%d. — gesperrt —" % n
		var b := Button.new()
		b.text = label
		b.position = Vector2(72, y)
		b.size = Vector2(410, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.disabled = not unlocked or Game.alive_roster().is_empty()
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", TEXT_COLOR)
		b.add_theme_color_override("font_pressed_color", TEXT_HOVER)
		b.add_theme_color_override("font_hover_color", TEXT_HOVER)
		b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.55, 0.47, 0.33, 0.35) if st == "pressed" else Color(0, 0, 0, 0)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			_click.play()
			selected[0] = id
			for c in stage.get_children():
				if c is Button and c.toggle_mode and c != b:
					(c as Button).button_pressed = false
			desc.text = Game.briefing_text(id).substr(0, 900)
			if start_b:
				start_b.disabled = false)
		stage.add_child(b)
		y += 34.0
		n += 1
	start_b = _button("single_mission", "bload mission", text(2357), Rect2(525.4, 629.6, 201.8, 35.8),
		func(): if selected[0] != "": _show_briefing(selected[0]), true)
	start_b.disabled = true
	_button("single_mission", "bload lastsave", text(2105), Rect2(737.7, 629.6, 201.7, 35.8),
		func(): Game.load_game("quick"), Game.has_save("quick"))
	_button("single_mission", "bexit", text(2256), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func(): show_menu("singleplayer"))
	if Game.alive_roster().is_empty():
		desc.text = "Der gesamte Kader ist gefallen. Kampagne beendet."
		_button("single_mission", "bexit01", "NEUE KAMPAGNE", Rect2(BTN_X, 580.0, BTN_W, BTN_H), func():
			Game.new_campaign()
			show_menu("campaign"))


func _options_menu() -> void:
	_background("options")
	var opts := func(): add_child(load("res://src/ui/options_menu.gd").new())
	_button("options", "bvideo setup", text(2405), _std_rect(0, 199.5, 43.8), opts)
	_button("options", "bsound setup", text(2406), _std_rect(1, 199.5, 43.8), opts)
	_button("options", "bcontrols", text(2407), _std_rect(2, 199.5, 43.8), opts)
	_button("options", "bgame setup", text(2408), _std_rect(3, 199.5, 43.8), func():
		Game.new_campaign()
		Events.say("Neue Kampagne angelegt.", 2.0)
		show_menu("options"))
	_button("options", "bmultiplayer setup", text(2409), _std_rect(4, 199.5, 43.8), func(): pass, false)
	_button("options", "bback", text(2410), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func(): show_menu("main_menu"))
	_label(Rect2(525.4, 430.0, 414.0, 200.0),
		"„Spiel-Einstellungen“ setzt die Kampagne zurück (neue Kampagne).", 13, TEXT_COLOR)


# --- Mitwirkende (Original: Text\german\Subtitles\credits.txt + credits.ogg) ----

func _show_credits() -> void:
	_credits_root = Control.new()
	_credits_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_credits_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits_root.add_child(bg)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lbl.add_theme_font_size_override("font_size", 18)
	var f := FileAccess.open(_menu_dir + "/credits.txt", FileAccess.READ)
	var lines: PackedStringArray = []
	lines.append("DANGEROUS HIDDEN 2 – Nachbau mit Godot " + Engine.get_version_info()["string"])
	lines.append("")
	lines.append("Originalspiel: Hidden & Dangerous 2")
	lines.append("")
	if f:
		for raw in f.get_as_text().split("\n"):
			var l := raw.strip_edges()
			if l.begins_with(";") or l.begins_with("<SPEED>"):
				continue
			for code in ["<TI>", "<NACZ>", "<SM>", "<ES>"]:
				l = l.replace(code, "")
			lines.append("" if l.begins_with("<EL>") else l)
	lbl.text = "\n".join(lines)
	_credits_root.add_child(lbl)
	lbl.position.y = size.y
	var dur := maxf(lines.size() * 0.45, 20.0)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", -lines.size() * 26.0, dur)
	tw.finished.connect(_close_credits)
	var st := _load_ogg("credits.ogg")
	if st:
		_music.stream = st
		_music.play()


func _close_credits() -> void:
	if is_instance_valid(_credits_root):
		_credits_root.queue_free()
	_play_menu_music()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_credits_root) and (event.is_action_pressed("pause") or event is InputEventMouseButton and event.pressed):
		_close_credits()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and _brief_root == null and current_menu != "main_menu":
		show_menu("main_menu")
		get_viewport().set_input_as_handled()


# --- Audio -------------------------------------------------------------------

func _load_ogg(file: String) -> AudioStream:
	var p := _menu_dir + "/audio/" + file
	return AudioStreamOggVorbis.load_from_file(p) if FileAccess.file_exists(p) else null


func _setup_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)
	_click = AudioStreamPlayer.new()
	var cp := _menu_dir + "/audio/button.wav"
	if FileAccess.file_exists(cp):
		_click.stream = AudioStreamWAV.load_from_file(cp)
	add_child(_click)
	_play_menu_music()


## Original: Musikgruppe 0 „Main Menu“, zufällig main menu.ogg / main menu 2.ogg (50:50)
func _play_menu_music() -> void:
	var st := _load_ogg("main menu.ogg" if randf() < 0.5 else "main menu 2.ogg")
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	if st:
		_music.stream = st
		_music.play()


# --- Einsatzbesprechung + Ausrüstung (eigene Ergänzung, Original: Ausrüstungsbildschirm) ---

func _show_briefing(id: String) -> void:
	stage.visible = false
	_brief_root = Control.new()
	_brief_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_brief_root)
	var v := UIKit.centered_panel(_brief_root, 820)
	UIKit.title("EINSATZBESPRECHUNG — %s" % Game.MISSIONS[id]["title"].to_upper(), 26, v)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = false
	txt.text = Game.briefing_text(id)
	txt.custom_minimum_size = Vector2(760, 190)
	txt.fit_content = false   # feste Höhe, scrollt bei langen Briefings
	txt.scroll_active = true
	v.add_child(txt)
	v.add_child(HSeparator.new())
	_build_loadout(v)
	v.add_child(HSeparator.new())
	var keys := Label.new()
	keys.add_theme_font_size_override("font_size", 14)
	keys.text = _controls_summary()
	v.add_child(keys)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	UIKit.button("Zurück", func():
		_brief_root.queue_free()
		_brief_root = null
		stage.visible = true, row)
	UIKit.button("Einsatz beginnen", func(): Game.start_mission(id), row)


## Ausrüstung je Soldat: Primärwaffe und Granaten (Seitenwaffe fest: Colt).
func _build_loadout(parent: Control) -> void:
	var title := Label.new()
	title.text = "AUSRÜSTUNG"
	title.add_theme_color_override("font_color", UIKit.ACCENT)
	parent.add_child(title)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	parent.add_child(g)
	var fallen_names: Array[String] = []
	for x in Game.ROSTER + Game.RESERVE:
		if Game.is_fallen(x["pid"]):
			fallen_names.append(x["name"])
	if not fallen_names.is_empty():
		var fl := Label.new()
		fl.text = "Gefallen: " + ", ".join(fallen_names) + " — Ersatz aus der Reserve rückt nach."
		fl.add_theme_color_override("font_color", Color(0.75, 0.45, 0.38))
		parent.add_child(fl)
	for r in Game.alive_roster():
		var pid: String = r["pid"]
		var lo: Array = Game.loadout_for(pid).duplicate()
		var name_l := Label.new()
		name_l.text = r["name"] + ("  (Ersatz)" if Game.RESERVE.has(r) else "")
		name_l.custom_minimum_size.x = 180
		g.add_child(name_l)
		var prim := OptionButton.new()
		prim.custom_minimum_size.x = 300
		for i in Game.ALLIED_PRIMARIES.size():
			var wd := WeaponDB.get_weapon(StringName(Game.ALLIED_PRIMARIES[i]))
			prim.add_item("%s  (%s, %d Schuss)" % [wd.display_name, wd.caliber, wd.magazine_size], i)
			if Game.ALLIED_PRIMARIES[i] == lo[0]:
				prim.select(i)
		g.add_child(prim)
		var gren := CheckBox.new()
		gren.text = "Granaten"
		gren.button_pressed = lo[2] != ""
		g.add_child(gren)
		var update := func(_x = null):
			Game.loadouts[pid] = [Game.ALLIED_PRIMARIES[prim.selected], "colt", "no36" if gren.button_pressed else ""]
		prim.item_selected.connect(update)
		gren.toggled.connect(update)
		update.call()


func _controls_summary() -> String:
	var k := func(a): return InputSetup.binding_text(a)
	return ("Bewegen %s%s%s%s · Sprinten %s · Schleichen = Hocken %s / Liegen %s · Springen/Klettern %s · Lehnen %s/%s\n" +
		"Feuern %s · Zielen %s · Nachladen %s · Waffen 1–3 · Benutzen %s · Kamera %s\n" +
		"Soldat wählen F1–F4 · Befehle: Bewegen %s · Folgen %s · Halten %s · Feuer frei/halten %s · Formation %s · Haltung %s\n" +
		"Taktische Karte %s · Ziele %s · Schnellspeichern %s · Schnellladen %s") % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"),
		k.call("run"), k.call("stance_crouch"), k.call("stance_prone"), k.call("stance_stand"),
		k.call("lean_left"), k.call("lean_right"), k.call("fire"), k.call("aim"), k.call("reload"),
		k.call("interact"), k.call("camera_toggle"), k.call("order_move"), k.call("order_follow"),
		k.call("order_hold"), k.call("order_roe"), k.call("order_formation"), k.call("order_stance"),
		k.call("tactical_map"), k.call("objectives"), k.call("quicksave"), k.call("quickload")]
