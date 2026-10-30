class_name OrigFonts
extends RefCounted
## Original-Bitmapschriften und Textstile (B-003). Daten: orig_cache/ui/fonts (D:\Workspace_D\tools\fmt_fonts.py).
## [B] Schriften Text\Fonts\<ANSI|CE>\SetN\{BIG,SMALL}.tga/.tbl, weiße Glyphen (Farbe kommt vom Stil);
## Satzwahl hd2.exe 0x63DCA7 (Bildbreite ≥ 1024 → Set3, ≥ 800 → Set2, sonst Set1);
## Textstile hd2.exe 0x641E30: Schrift, Farbe ARGB, Höhe = Anteil der Bildhöhe, Lage x/y im Rechteck, Ausrichtung
## (1 links/oben, 2 Mitte, 3 rechts/unten). Ohne Cache liefern alle Funktionen null bzw. {} (eigene Schriften bleiben).

## Stilnummern (Belege: re_notes_hud §3a, re_notes_commands §8)
const ST_MENU_TITLE := 0x2F        ## Befehlsmenü Zeile 1 „Befehle“
const ST_MENU_TITLE_SUB := 0x30    ## „Befehle - “ + Untermenü
const ST_MENU_TARGET := 0x31       ## Zeile 2 Ziel/Soldat (schwarz, Alpha 0x60)
const ST_MENU_NUMBER := 0x32       ## „%d. “
const ST_MENU_ITEM := 0x33         ## Eintrag normal
const ST_MENU_GREY := 0x34         ## Eintrag nicht wählbar (schwarz, Alpha 0x60)
const ST_MENU_MARKED := 0x35       ## Eintrag markiert (rot)
const ST_HUD_NAME := 0x36          ## tabl02 Zeile 0 Name
const ST_HUD_HANDS := 0x37         ## tabl02 Zeile 1 Hand „%d/%d“
const ST_HUD_SHOULDER := 0x38      ## tabl02 Zeile 2 Schulter „%d/%d“
const ST_HUD_GRENADES := 0x39      ## tabl02 Zeile 3 Granaten „%d“

static var _data = null
static var _fonts := {}


static func _dir() -> String:
	return OrigLevel.cache_root() + "/ui/fonts"


static func available() -> bool:
	return FileAccess.file_exists(_dir() + "/fonts.json")


static func _load_data() -> Dictionary:
	if _data == null:
		_data = {}
		if available():
			var j = JSON.parse_string(FileAccess.get_file_as_string(_dir() + "/fonts.json"))
			if typeof(j) == TYPE_DICTIONARY:
				_data = j
	return _data


## Satz nach Bildbreite wie das Original; Zeichensatz CE für Tschechisch, sonst ANSI.
static func set_for_width(width: float) -> String:
	if width >= 1024.0:
		return "set3"
	if width >= 800.0:
		return "set2"
	return "set1"


## Schrift „BIG“/„SMALL“ als FontFile (gecacht), null ohne Cache.
static func font(kind: String, width: float = 1280.0) -> Font:
	var group := "ce" if String(Settings.get("language")) == "czech" else "ansi"
	var key := "%s_%s_%s" % [group, set_for_width(width), kind.to_lower()]
	if _fonts.has(key):
		return _fonts[key]
	var f: FontFile = null
	var path := _dir() + "/" + key + ".fnt"
	if FileAccess.file_exists(path):
		f = FontFile.new()
		if f.load_bitmap_font(path) != OK:
			f = null
	_fonts[key] = f
	return f


## Stil (Dictionary aus fonts.json) oder {}.
static func style(id: int) -> Dictionary:
	var st: Array = _load_data().get("styles", [])
	return st[id] if id >= 0 and id < st.size() and st[id] is Dictionary else {}


static func style_color(id: int, fallback := Color.BLACK) -> Color:
	var a = style(id).get("argb")
	if not (a is String) or (a as String).length() != 8:
		return fallback
	var v := (a as String).hex_to_int()
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, (v >> 24) & 0xFF)


## Schriftgröße in Pixeln (Stilhöhe × Bildhöhe), mindestens min_px.
static func style_px(id: int, screen_h: float, min_px := 8) -> int:
	return maxi(min_px, int(round(float(style(id).get("height", 0.02)) * screen_h)))


## Label nach Stil einrichten: Originalschrift, -farbe und -größe (Bildhöhe screen_h). true = Originalschrift aktiv.
static func apply(l: Control, id: int, screen_h: float, screen_w: float = 1280.0) -> bool:
	var st := style(id)
	if st.is_empty():
		return false
	var f := font(String(st.get("font", "SMALL")), screen_w)
	if f == null:
		return false
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", style_px(id, screen_h))
	l.add_theme_color_override("font_color", style_color(id))
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return true
