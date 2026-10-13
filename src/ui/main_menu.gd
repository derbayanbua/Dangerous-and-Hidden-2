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
	2021: "KEIN GESPEICHERTER SPIELSTAND", 2117: "PROFIL ERSTELLEN", 2001: "JA", 2004: "SIND SIE SICHER?",
	2008: "ANNULLIEREN", 2013: "OK", 2030: "MINIMUM", 2031: "NORMAL", 2032: "MAXIMUM",
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
var _start_btn: Button          ## START in der Missionsliste (Membervariable: Lambdas fangen Werte beim Erzeugen)
var selected_mission := ""
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
	for suffix: String in Settings.texture_suffixes():
		if suffix == "":
			break
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
	# sofort aushängen: sonst tragen neue gleichnamige Knöpfe automatisch umbenannte Namen
	for c in stage.get_children():
		stage.remove_child(c)
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
		"change_profile":
			_profile_menu()


func _main_menu() -> void:
	_background("main_menu")
	if not spec.get("menus", {}).has("main_menu"):
		_label(Rect2(584.7, 44.0, 354.5, 43.0), text(2101), 24, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	# Infoblock rechts: Datum/Zeit, Profil, letzter Spielstand
	var info := [
		["text_date00", text(2102)], ["text_date01", Time.get_datetime_string_from_system(false, true)],
		["text_profile00", text(2103)], ["text_profile01", Game.profile_name if Game.has_profile() else text(2020)],
		["text_last save00", text(2104)], ["text_last save01", _last_save_text()]]
	var y := 129.3
	for pair in info:
		var it := _item("main_menu", pair[0])
		var bold: bool = pair[0].ends_with("01")
		_label(_rect_of(it, Rect2(541.3, y, 394.7, 18.0)), pair[1], 15 if bold else 13, TEXT_COLOR)
		y += 30.0
	var prof := Game.has_profile()
	var has_save := prof and Game.has_save("quick")
	# Original (Show-Handler 0x627520): ohne Profil heißt Knopf 2 "PROFIL ERSTELLEN", die übrigen sind gesperrt
	var entries := [
		["bresume game", 2105, func(): Game.load_game("quick"), has_save],
		["bchange profile", 2106 if prof else 2117, _open_profiles, true],
		["bsingleplayer", 2107, func(): show_menu("singleplayer"), prof],
		["bmultiplayerlan", 2115, func(): pass, false],
		["bmultiplayernet", 2116, func(): pass, false],
		["bcinematics", 2109, func(): pass, false],
		["boptions", 2110, func(): show_menu("options"), prof],
		["bcredits", 2111, _show_credits, prof],
		["bexit", 2112, func(): get_tree().quit(), true],
	]
	for i in entries.size():
		var e: Array = entries[i]
		_button("main_menu", e[0], text(e[1]), _std_rect(i), e[2], e[3])


func _last_save_text() -> String:
	if not Game.has_save("quick"):
		return text(2021)
	var path := ProjectSettings.globalize_path(Game.save_path("quick"))
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
	selected_mission = ""
	_start_btn = null
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
			selected_mission = id
			for c in stage.get_children():
				if c is Button and c.toggle_mode and c != b:
					(c as Button).button_pressed = false
			desc.text = Game.briefing_text(id).substr(0, 900)
			if is_instance_valid(_start_btn):
				_start_btn.disabled = false)
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.double_click and not b.disabled:
				selected_mission = id
				_show_briefing(id))
		stage.add_child(b)
		y += 34.0
		n += 1
	_start_btn = _button("single_mission", "bload mission", text(2357), Rect2(525.4, 629.6, 201.8, 35.8),
		_start_selected, true)
	_start_btn.disabled = true
	_button("single_mission", "bload lastsave", text(2105), Rect2(737.7, 629.6, 201.7, 35.8),
		func(): Game.load_game("quick"), Game.has_save("quick"))
	_button("single_mission", "bexit", text(2256), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func(): show_menu("singleplayer"))
	if Game.alive_roster().is_empty():
		desc.text = "Der gesamte Kader ist gefallen. Kampagne beendet."
		_button("single_mission", "bexit01", "NEUE KAMPAGNE", Rect2(BTN_X, 580.0, BTN_W, BTN_H), func():
			Game.new_campaign()
			show_menu("campaign"))


func _start_selected() -> void:
	if selected_mission != "":
		_show_briefing(selected_mission)


func _open_profiles() -> void:
	show_menu("change_profile")
	if not Game.has_profile():
		_name_dialog(text(2152), "", func(n: String):
			if Game.create_profile(n, 2):
				show_menu("change_profile")
			else:
				Events.say("Name ungültig oder schon vergeben.", 2.0))


# --- Einstellungen (Original options.4ds: Seiten links, Auswahl rechts) -------------

var options_page := "graphics"
var _keys_category := 0
var _waiting_action := ""


func _options_menu() -> void:
	_background("options")
	_label(_rect_of(_item("options", "text_date00"), Rect2(525.4, 109.5, 354.6, 18.0)), text(2402), 14, TEXT_COLOR)
	_label(_rect_of(_item("options", "text_date01"), Rect2(525.4, 127.5, 354.6, 35.8)),
		Game.profile_name if Game.has_profile() else text(2020), 16, TEXT_COLOR)
	_button("options", "bvideo setup", text(2405), _std_rect(0, 199.5, 43.8), _opt_page.bind("graphics"))
	_button("options", "bsound setup", text(2406), _std_rect(1, 199.5, 43.8), _opt_page.bind("sound"))
	_button("options", "bcontrols", text(2407), _std_rect(2, 199.5, 43.8), _opt_page.bind("controls"))
	_button("options", "bgame setup", text(2408), _std_rect(3, 199.5, 43.8), _opt_page.bind("game"))
	_button("options", "bmultiplayer setup", text(2409), _std_rect(4, 199.5, 43.8), func(): pass, false)
	_button("options", "bback", text(2410), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func():
		Settings.save_settings()
		show_menu("main_menu"))
	match options_page:
		"graphics":
			_page_graphics()
		"sound":
			_page_sound()
		"controls":
			_page_controls()
		"keys":
			_page_keys()
		"display":
			_page_display()
		"game":
			_page_game()


func _opt_page(page: String) -> void:
	options_page = page
	show_menu("options")


func _changed() -> void:
	Settings.apply()
	Settings.save_settings()


## Ja/Nein-Zeile wie im Original (Text links, Felder "nein"/"ja" rechts)
func _yesno(y: float, label: String, value: bool, cb: Callable, enabled := true) -> void:
	_label(Rect2(67, y, 337, 33), label, 15, TEXT_COLOR if enabled else TEXT_DISABLED)
	for pair in [[410.0, false], [446.0, true]]:
		var b := Button.new()
		b.position = Vector2(pair[0], y)
		b.size = Vector2(33, 33)
		b.text = "✕" if value == pair[1] and enabled else ""
		b.tooltip_text = text(2001) if pair[1] else "NEIN"
		b.disabled = not enabled
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", TEXT_HOVER)
		b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.86, 0.82, 0.7, 0.9) if st != "hover" else Color(0.93, 0.89, 0.77)
			sb.border_color = Color(0.22, 0.18, 0.12, 1.0 if enabled else 0.4)
			sb.set_border_width_all(2)
			b.add_theme_stylebox_override(st, sb)
		var v: bool = pair[1]
		b.pressed.connect(func():
			_click.play()
			cb.call(v)
			_changed()
			show_menu("options"))
		stage.add_child(b)


## Schieberegler wie im Original (Leiste 336×33, darunter "minimum normal maximum")
func _slider(y: float, value: float, lo: float, hi: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.position = Vector2(105, y)
	s.size = Vector2(336, 33)
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.3, 0.25, 0.18, 0.75)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.12, 0.07, 0.85)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(func(v: float):
		cb.call(v)
		_changed())
	stage.add_child(s)
	_label(Rect2(105, y + 34, 112, 18), text(2030), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	_label(Rect2(217, y + 34, 112, 18), text(2031), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_label(Rect2(329, y + 34, 112, 18), text(2032), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	return s


## Auswahlknopf über die volle Zeilenbreite (z. B. Grafikdetails, Auflösung)
func _cycle(r: Rect2, label: String, cb: Callable, enabled := true, node_name := "") -> Button:
	var b := Button.new()
	if node_name != "":
		b.name = node_name
	b.position = r.position
	b.size = r.size
	b.text = label
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", TEXT_HOVER)
	b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	var it := {"normal": {"texture": "X_NMNBTN.BMP", "uv_rect": [0.001, 0.0011, 0.8059, 0.2814]},
		"hover": {"texture": "X_NMNBTN.BMP", "uv_rect": [0.0011, 0.2824, 0.8059, 0.5591]}}
	b.add_theme_stylebox_override("normal", _atlas_style(it, "normal"))
	b.add_theme_stylebox_override("hover", _atlas_style(it, "hover"))
	b.add_theme_stylebox_override("pressed", _atlas_style(it, "hover"))
	b.add_theme_stylebox_override("disabled", _atlas_style(it, "normal"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_click.play()
		cb.call()
		_changed()
		show_menu("options"))
	stage.add_child(b)
	return b


func _page_graphics() -> void:
	# Original options.4ds „graphics setup“ (Zuordnung Frame -> Text aus hd2.exe 0x61dbc0 ff.)
	_label(Rect2(67, 149, 383, 18), text(2411), 16, TEXT_COLOR)
	_label(Rect2(67, 179, 383, 18), text(2412), 14, TEXT_COLOR)
	_slider(201, Settings.gamma, 0.6, 1.6, func(v: float): Settings.gamma = v)
	var disp := _cycle(Rect2(105, 283, 336, 33), "ANZEIGE: AUFLÖSUNG, VOLLBILD …", func(): options_page = "display")
	disp.name = "bdisplay"
	disp.tooltip_text = "Moderne Ergänzung (nicht im Original)"
	var lvl := Settings.detail_level()
	var det := _cycle(Rect2(105, 333, 336, 32), text(2414 + lvl), func():
		Settings.set_detail_preset((mini(Settings.detail_level(), 2) + 1) % 3))
	det.name = "bdetail"
	_label(Rect2(67, 390, 337, 18), text(2430), 14, TEXT_COLOR)
	# Reihenfolge wie im Original: GD00..GD06 = Frames nextdetail, shadows, mirrors, morphing,
	# dynamic lightning, light glow, use high models
	var rows := [
		[408, 2418, "shadows"], [451, 2419, "morphing"], [495, 2420, "decals"], [539, 2421, "blood"],
		[583, 2422, "grass"], [626, 2423, "dynamic_lights"], [670, 2424, "high_models"]]
	for r in rows:
		var key: String = r[2]
		_yesno(r[0], text(r[1]), Settings.get(key), func(v: bool): Settings.set(key, v))
		if key == "morphing":
			for k in [1, 2]:
				(stage.get_child(stage.get_child_count() - k) as Control).tooltip_text = "Gesichtsanimation – im Nachbau noch ohne Wirkung"


## Anzeige & Setup: Optionen aus dem Original-Setup (setup.exe), soweit heute sinnvoll, plus moderne Ergänzungen
func _page_display() -> void:
	_label(Rect2(67, 140, 412, 18), "Anzeige & Setup (aus dem Original-Setup):", 16, TEXT_COLOR)
	_label(Rect2(67, 160, 412, 18), "Grafikkarte: " + RenderingServer.get_video_adapter_name(), 12, TEXT_COLOR)
	var y := 184.0
	var ri := Settings.RESOLUTIONS.find(Settings.resolution)
	_cycle(Rect2(67, y, 412, 32), "AUFLÖSUNG: " + Settings.resolution_name(Settings.resolution), func():
		Settings.resolution = Settings.RESOLUTIONS[(maxi(ri, 0) + 1) % Settings.RESOLUTIONS.size()])
	y += 38
	_yesno(y, "VOLLBILD", Settings.fullscreen, func(v: bool): Settings.fullscreen = v)
	y += 38
	_cycle(Rect2(67, y, 412, 32), "VSYNC: " + Settings.VSYNC_NAMES[Settings.vsync_mode], func():
		Settings.vsync_mode = (Settings.vsync_mode + 1) % 4, true, "bvsync")
	y += 38
	var fi := Settings.FPS_STEPS.find(Settings.max_fps)
	_cycle(Rect2(67, y, 412, 32), "BILDRATE: " + ("UNBEGRENZT" if Settings.max_fps == 0 else "MAX. %d" % Settings.max_fps), func():
		Settings.max_fps = Settings.FPS_STEPS[(maxi(fi, 0) + 1) % Settings.FPS_STEPS.size()], true, "bfps")
	y += 38
	_cycle(Rect2(67, y, 412, 32), "KANTENGLÄTTUNG: " + Settings.AA_NAMES[Settings.aa_mode], func():
		Settings.aa_mode = (Settings.aa_mode + 1) % Settings.AA_NAMES.size(), true, "baa")
	y += 38
	_cycle(Rect2(67, y, 412, 32), "TEXTUREN: " + Settings.TEXTURE_NAMES[Settings.texture_quality], func():
		Settings.texture_quality = (Settings.texture_quality + 1) % 3, true, "btex")
	y += 38
	_cycle(Rect2(67, y, 412, 32), "ANISOTROPE FILTERUNG: " + Settings.ANISO_NAMES[Settings.anisotropy], func():
		Settings.anisotropy = (Settings.anisotropy + 1) % 5, true, "baniso")
	y += 38
	var scales := [1.0, 0.85, 0.7, 0.5]
	var si := scales.find(snappedf(Settings.render_scale, 0.05))
	_cycle(Rect2(67, y, 412, 32), "3D-RENDERSKALIERUNG: %d %%" % int(Settings.render_scale * 100.0), func():
		Settings.render_scale = scales[(maxi(si, 0) + 1) % scales.size()])
	y += 38
	var fovs := [60.0, 70.0, 80.0, 90.0, 100.0]
	var fo := fovs.find(Settings.fov)
	_cycle(Rect2(67, y, 412, 32), "SICHTFELD: %d°" % int(Settings.fov), func():
		Settings.fov = fovs[(maxi(fo, 0) + 1) % fovs.size()])
	y += 38
	_yesno(y, "BEI INAKTIVEM FENSTER PAUSIEREN", Settings.pause_unfocused, func(v: bool): Settings.pause_unfocused = v)
	y += 38
	_yesno(y, "ZUSATZEFFEKTE (SSIL, SDFGI)", Settings.quality >= 3, func(v: bool): Settings.quality = 3 if v else 2)
	_cycle(Rect2(67, 670, 412, 33), text(2410), func(): options_page = "graphics")
	_label(Rect2(67, 638, 412, 26), "Texturänderung wirkt beim nächsten Laden einer Mission.", 11, TEXT_COLOR)


func _page_sound() -> void:
	_label(Rect2(67, 149, 383, 18), text(2425), 16, TEXT_COLOR)
	_label(Rect2(67, 179, 337, 18), text(2426), 14, TEXT_COLOR)
	_slider(201, Settings.master_volume, 0.0, 1.0, func(v: float): Settings.master_volume = v)
	_label(Rect2(67, 267, 337, 18), text(2428), 14, TEXT_COLOR)
	_slider(288, Settings.music_volume, 0.0, 1.0, func(v: float): Settings.music_volume = v)


func _page_controls() -> void:
	_label(Rect2(67, 149, 383, 18), text(2441), 16, TEXT_COLOR)
	var kb := _cycle(Rect2(105, 201, 336, 33), text(2442), func(): options_page = "keys")
	kb.name = "bkeys"
	_label(Rect2(67, 267, 383, 18), text(2443), 14, TEXT_COLOR)
	_yesno(289, text(2444), Settings.invert_y, func(v: bool): Settings.invert_y = v)
	_label(Rect2(67, 355, 383, 18), text(2445), 14, TEXT_COLOR)
	_slider(376, Settings.mouse_sensitivity, 0.03, 0.4, func(v: float): Settings.mouse_sensitivity = v)
	_label(Rect2(67, 556, 383, 18), text(2447), 14, TEXT_DISABLED)
	var cal := _cycle(Rect2(105, 580, 336, 33), text(2448), func(): pass, false)
	cal.tooltip_text = "Joystick/Gamepad wird noch nicht unterstützt"
	_yesno(626, text(2449), false, func(_v): pass, false)
	_yesno(671, text(2450), false, func(_v): pass, false)


const KEY_CATEGORIES := [
	[2452, ["move_forward", "move_back", "move_left", "move_right", "run", "stance_stand", "stance_crouch",
		"stance_prone", "lean_left", "lean_right"]],
	[2453, ["fire", "aim", "reload", "fire_mode", "weapon_1", "weapon_2", "weapon_3", "weapon_next", "weapon_prev"]],
	[2454, ["interact", "binoculars", "medkit", "camera_toggle", "objectives", "quicksave", "quickload", "pause"]],
	[2455, ["order_move", "order_follow", "order_hold", "order_roe", "order_formation", "order_stance", "order_grenade"]],
	[2456, ["tactical_map", "soldier_1", "soldier_2", "soldier_3", "soldier_4", "soldier_next"]],
]


func _page_keys() -> void:
	_label(Rect2(67, 179, 383, 18), text(2451), 14, TEXT_COLOR)
	var cat: Array = KEY_CATEGORIES[_keys_category]
	_cycle(Rect2(105, 201, 336, 33), text(cat[0]), func(): _keys_category = (_keys_category + 1) % KEY_CATEGORIES.size())
	var y := 244.0
	for action: String in cat[1]:
		var b := Button.new()
		b.name = ("key_" + action).validate_node_name()
		b.position = Vector2(70, y)
		b.size = Vector2(406, 29)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var waiting := _waiting_action == action
		b.text = "%s:   %s" % [InputSetup.display_name(action), "… Taste drücken …" if waiting else InputSetup.binding_text(action)]
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", TEXT_HOVER if waiting else TEXT_COLOR)
		b.add_theme_color_override("font_hover_color", TEXT_HOVER)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.55, 0.47, 0.33, 0.3) if st == "hover" or waiting else Color(0, 0, 0, 0)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			_waiting_action = action
			show_menu("options"))
		stage.add_child(b)
		y += 30.0
	var d1 := _cycle(Rect2(67, 626, 204, 33), text(2457), func(): InputSetup.apply_preset(1))
	d1.name = "bdefault1"
	d1.add_theme_font_size_override("font_size", 12)
	var d2 := _cycle(Rect2(275, 626, 204, 33), text(2459), func(): InputSetup.apply_preset(2))
	d2.name = "bdefault2"
	d2.add_theme_font_size_override("font_size", 12)
	_cycle(Rect2(67, 670, 412, 33), text(2458), func():
		_waiting_action = ""
		options_page = "controls")


func _input(event: InputEvent) -> void:
	# Tastenbelegung: nächste Taste/Maustaste für die gewählte Aktion übernehmen
	if _waiting_action == "" or current_menu != "options":
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
		else:
			InputSetup.rebind(_waiting_action, event)
			InputSetup.save_bindings()
			_waiting_action = ""
		get_viewport().set_input_as_handled()
		show_menu.call_deferred("options")


func _page_game() -> void:
	_label(Rect2(67, 149, 383, 18), text(2461), 16, TEXT_COLOR)
	_yesno(201, text(2462), Settings.subtitles, func(v: bool): Settings.subtitles = v)
	# v1.12: der frühere Punkt "Kindersicherung" heißt "FADENKREUZ ZULASSEN" (Text 20212)
	_yesno(289, text(20212) if texts.has("20212") else "FADENKREUZ ZULASSEN", Settings.crosshair,
		func(v: bool): Settings.crosshair = v)


# --- Profile (Original change_profile.4ds) ---------------------------------------

func _profile_menu() -> void:
	_background("change_profile")
	var prof := Game.has_profile()
	_label(_rect_of(_item("change_profile", "text_current profile and save"), Rect2(71.2, 114.5, 414.1, 23.2)),
		text(2191), 14, TEXT_COLOR)
	_label(Rect2(80, 140, 400, 34), Game.profile_name if prof else text(2020), 18, TEXT_COLOR)
	_label(_rect_of(_item("change_profile", "text_date and time"), Rect2(256.0, 177.1, 229.3, 23.2)),
		_last_save_text() if prof else "", 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(_rect_of(_item("change_profile", "text_list of profiles"), Rect2(71.2, 232.8, 414.1, 23.2)),
		text(2192), 14, TEXT_COLOR)
	var y := 268.0
	for n in Game.list_profiles():
		var b := Button.new()
		b.name = ("profile_" + n).validate_node_name()
		b.text = n
		b.position = Vector2(125, y)
		b.size = Vector2(346, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		var cur := n == Game.profile_name
		b.add_theme_color_override("font_color", TEXT_HOVER if cur else TEXT_COLOR)
		b.add_theme_color_override("font_hover_color", TEXT_HOVER)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.55, 0.47, 0.33, 0.35) if cur or st == "hover" else Color(0, 0, 0, 0)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			_click.play()
			Game.select_profile(n)
			show_menu("change_profile"))
		stage.add_child(b)
		y += 31.0
		if y > 660.0:
			break
	# rechts: Schwierigkeitsgrad + Profilinfo + Verwaltung
	_label(_rect_of(_item("change_profile", "text_difficulty"), Rect2(525.4, 114.5, 414.0, 23.2)), text(2193), 14, TEXT_COLOR)
	var diff_ids := ["beasy-war never was so fun!", "bnormal-loosing illusions!", "bhard-cannon fodder!",
		"bvery hard-hidden and dangerous"]
	for i in 4:
		var d := i + 1
		var b := _button("change_profile", diff_ids[i], text(Game.DIFFICULTY_TEXT[d]),
			Rect2(BTN_X, 137.7 + i * 39.4, BTN_W, BTN_H), _set_difficulty.bind(d), prof)
		if prof and Game.difficulty() == d:
			b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
			b.add_theme_color_override("font_color", TEXT_HOVER)
	var info := _label(_rect_of(_item("change_profile", "text01"), Rect2(525.4, 304.1, 414.0, 228.4)),
		_profile_info(), 13, TEXT_COLOR)
	info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_button("change_profile", "bcreate profile", text(2152), Rect2(BTN_X, 550.7, BTN_W, BTN_H), _create_profile_dialog)
	_button("change_profile", "brename profile", text(2154), Rect2(BTN_X, 590.2, BTN_W, BTN_H), _rename_profile_dialog, prof)
	_button("change_profile", "bdelete profile", text(2155), Rect2(BTN_X, 629.6, BTN_W, BTN_H), _delete_profile_dialog, prof)
	_button("change_profile", "bback", text(2156), Rect2(BTN_X, 669.0, BTN_W, BTN_H), func(): show_menu("main_menu"))


func _set_difficulty(d: int) -> void:
	Game.set_difficulty(d)
	show_menu("change_profile")


func _create_profile_dialog() -> void:
	_name_dialog(text(2152), "", func(n: String):
		if Game.create_profile(n, 2):
			show_menu("change_profile")
		else:
			Events.say("Name ungültig oder schon vergeben.", 2.0))


func _rename_profile_dialog() -> void:
	_name_dialog(text(2154), Game.profile_name, func(n: String):
		Game.rename_profile(Game.profile_name, n)
		show_menu("change_profile"))


func _delete_profile_dialog() -> void:
	_confirm(text(2004), func():
		Game.delete_profile(Game.profile_name)
		show_menu("change_profile"))


func _profile_info() -> String:
	if not Game.has_profile():
		return text(2020)
	var p := Game.profile
	var secs := int(float(p.get("playtime", 0.0)))
	var lines: PackedStringArray = [
		text(2163),
		"%s %s" % [text(2164), _last_save_text()],
		"%s %s" % [text(2165), text(Game.DIFFICULTY_TEXT[Game.difficulty()])],
		"%s %d:%02d:%02d" % [text(2166), secs / 3600, (secs / 60) % 60, secs % 60],
		"%s %d" % [text(2168), int(p.get("enemies_killed", 0))],
		"%s %d" % [text(2169), int(p.get("shots", 0))],
		"Abgeschlossene Einsätze: %d" % Game.campaign.get("completed", []).size(),
	]
	if p.has("imported_from"):
		lines.append("Übernommen aus: " + String(p["imported_from"]))
	if p.has("orig_last_save"):
		lines.append("Original-Spielstand: " + String(p["orig_last_save"]))
	return "\n".join(lines)


## Eingabedialog (Profilname) auf Papier-Optik
func _name_dialog(title: String, preset: String, on_ok: Callable) -> void:
	var dlg := _dialog_box(title)
	var le := LineEdit.new()
	le.name = "NameEdit"
	le.text = preset
	le.max_length = 24
	le.position = Vector2(30, 70)
	le.size = Vector2(340, 36)
	le.add_theme_font_size_override("font_size", 18)
	dlg.add_child(le)
	le.grab_focus.call_deferred()
	var ok := func():
		var n := le.text.strip_edges()
		dlg.get_parent().queue_free()
		if n != "":
			on_ok.call(n)
	le.text_submitted.connect(func(_t): ok.call())
	_dialog_button(dlg, text(2013), Vector2(30, 126), ok)
	_dialog_button(dlg, text(2008), Vector2(210, 126), func(): dlg.get_parent().queue_free())


func _confirm(question: String, on_yes: Callable) -> void:
	var dlg := _dialog_box(question)
	_dialog_button(dlg, text(2001), Vector2(30, 126), func():
		dlg.get_parent().queue_free()
		on_yes.call())
	_dialog_button(dlg, text(2008), Vector2(210, 126), func(): dlg.get_parent().queue_free())


func _dialog_box(title: String) -> Panel:
	var shade := ColorRect.new()
	shade.name = "Dialog"
	shade.color = Color(0, 0, 0, 0.45)
	shade.size = REF
	stage.add_child(shade)
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.82, 0.77, 0.64)
	sb.border_color = Color(0.25, 0.2, 0.14)
	sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(312, 290)
	p.size = Vector2(400, 190)
	shade.add_child(p)
	var l := Label.new()
	l.text = title
	l.position = Vector2(20, 18)
	l.size = Vector2(360, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	p.add_child(l)
	return p


func _dialog_button(dlg: Panel, label: String, pos: Vector2, cb: Callable) -> void:
	var it := {"normal": {"texture": "X_NMNBTN.BMP", "uv_rect": [0.001, 0.0011, 0.2041, 0.2814]},
		"hover": {"texture": "X_NMNBTN.BMP", "uv_rect": [0.0011, 0.2824, 0.2041, 0.5591]}}
	var b := Button.new()
	b.name = ("dlg_" + label).validate_node_name()
	b.text = label
	b.position = pos
	b.size = Vector2(160, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", TEXT_HOVER)
	b.add_theme_stylebox_override("normal", _atlas_style(it, "normal"))
	b.add_theme_stylebox_override("hover", _atlas_style(it, "hover"))
	b.add_theme_stylebox_override("pressed", _atlas_style(it, "hover"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_click.play()
		cb.call())
	dlg.add_child(b)


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
	_music.bus = &"Music"
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
	var sas := Game.uses_sas(id)
	if sas:
		_build_sas_summary(v, id)
	else:
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
	if sas:
		UIKit.button("Team und Ausrüstung", func(): _open_sas_screen(id), row).name = "TeamButton"
	else:
		UIKit.button("Einsatz beginnen", func(): Game.start_mission(id), row)


var sas_screen: SasScreen


## Original-Ablauf: Briefing -> (Teamauswahl, wo vorgesehen) -> Inventar-Auswahl -> Einsatz
func _open_sas_screen(id: String) -> void:
	if _brief_root:
		_brief_root.visible = false
	sas_screen = SasScreen.new()
	sas_screen.name = "SasScreen"
	add_child(sas_screen)
	sas_screen.back_requested.connect(func():
		sas_screen.queue_free()
		sas_screen = null
		if _brief_root:
			_brief_root.visible = true)
	sas_screen.start_requested.connect(func(): Game.start_mission(id))
	sas_screen.open(id)


func _build_sas_summary(parent: Control, id: String) -> void:
	Game.prepare_sas(id)
	var mode := Game.sas_team_mode(id)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 16)
	var st := Game.sas_states()
	var names: Array = Game.sas_team().map(func(i): return SAS.short_name(i, int(st[str(i)]["rank"])))
	l.text = "%s %s\n%s" % [SAS.text(2706, "Team:"), ", ".join(names),
		{"select": SAS.text(2651, "AUSWAHL DER TEAM-MITGLIEDER"), "refill": SAS.text(2652, "TEAM WIEDER AUFFÜLLEN")}.get(mode,
		"Das Team bleibt für diesen Einsatz zusammen.")]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 760
	parent.add_child(l)


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
