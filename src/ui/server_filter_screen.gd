class_name ServerFilterScreen
extends OrigScreen
## Original „SERVER-FILTER“ (T2309) nach MODELS\server filters.4ds (hd2.exe 0x638590): Gesuchte Art (T2554, Pfeile
## durch ALLE ARTEN/DEATHMATCH/…, T2890–2893), MAXIMALER PING (T2555, 0 = beliebig), Kästchen-Paare Nein/Ja
## (✗/✓ aus X_NMNBTN) für NUR PASSENDE (T2560 = antwortende Server), NUR DEDIZIERTE, NUR NICHT-LEERE,
## NUR NICHT-VOLLE, OHNE PASSWORTE, Selbe Version (T2579); AKZEPTIEREN (T2556) übernimmt in Net.server_filter
## (gespeichert in user://mp_filter.json), ZURÜCK (T2557) verwirft.

signal closed(accepted: bool)

## [Zeilen-Frame, Filterschlüssel, Text-ID, Ersatztext, Nummer der Kästchen-Frames]
const ROWS := [["responding only", "responding", 2560, "NUR PASSENDE", "01"],
	["dedicated only", "dedicated", 2561, "NUR DEDIZIERTE", "02"],
	["that are not empty", "not_empty", 2562, "NUR NICHT-LEERE", "03"],
	["that are not full", "not_full", 2563, "NUR NICHT-VOLLE", "04"],
	["without password", "no_password", 2564, "OHNE PASSWORTE", "05"],
	["current version", "same_version", 2579, "Selbe Version", "06"]]
## Auswahl der Art: −1 alle, sonst Net.Mode (Team-Deathmatch = Ergänzung für Arena-Karten)
const STYLES := [-1, 0, 1, 2, 3]

var flt := {}
var _ping_edit: LineEdit


func open() -> void:
	flt = Net.server_filter.duplicate()
	setup_stage()
	build()


static func style_name(st: int) -> String:
	if st < 0:
		return SAS.text(2890, "ALLE ARTEN")
	if st == Net.Mode.TEAM_DEATHMATCH:
		return Net.MODE_NAMES[1]
	return SAS.text({0: 2891, 2: 2892, 3: 2893}.get(st, 2894), Net.MODE_NAMES[clampi(st, 0, 3)])


func build() -> void:
	var ping_txt: String = _ping_edit.text if is_instance_valid(_ping_edit) else str(int(flt.get("max_ping", 0)))
	begin("server filters")
	title(2309, "SERVER-FILTER")
	text_at("text_scan style", SAS.text(2554, "Gesuchte Art:"), 15)
	text_at("text_show servers", SAS.text(2553, "SUCHE SERVER MIT"), 15)
	draw_frame("scan style")
	label(rect("scan style", Rect2(107, 155, 337, 33)), style_name(int(flt.get("style", -1))), 15, INK,
		HORIZONTAL_ALIGNMENT_CENTER).name = "StyleText"
	orig_button("barrow up01", "", _style.bind(-1), true, "StyleLeft")
	orig_button("barrow down02", "", _style.bind(1), true, "StyleRight")
	# MAXIMALER PING: Beschriftung + Eingabefeld (bshort00 = text00 + normal02)
	draw_frames(["text00", "normal02"])
	label(rect("text00", Rect2(525, 155, 298, 33)).grow_individual(-8, 0, 0, 0), SAS.text(2555, "MAXIMALER PING"), 15)
	_ping_edit = LineEdit.new()
	_ping_edit.name = "MaxPing"
	var pr := rect("normal02", Rect2(836, 155, 103, 33))
	_ping_edit.position = pr.position + Vector2(6, 3)
	_ping_edit.size = pr.size - Vector2(12, 6)
	_ping_edit.flat = true
	_ping_edit.max_length = 4
	_ping_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_edit.text = ping_txt
	_ping_edit.add_theme_color_override("font_color", INK)
	_ping_edit.add_theme_font_size_override("font_size", 15)
	stage.add_child(_ping_edit)
	for row in ROWS:
		_row(row)
	orig_button("baccept", SAS.text(2556, "AKZEPTIEREN"), accept, true, "FilterAccept")
	orig_button("bback", SAS.text(2557, "ZURÜCK"), func(): closed.emit(false), true, "FilterBack")


## Zeile mit Nein-/Ja-Kästchen (no_empty = links, yes_empty = rechts); gesetzt: ✓ im Ja-Kästchen, sonst ✗ im Nein-Kästchen
func _row(row: Array) -> void:
	var on := bool(flt.get(row[1], false))
	var n: String = row[4]
	draw_frame(row[0])
	var r := rect(row[0], Rect2(525, 200, 341, 33))
	label(Rect2(r.position + Vector2(10, 0), Vector2(r.size.x - 14, r.size.y)), SAS.text(int(row[2]), String(row[3])), 15).name = \
		"Row_" + String(row[1])
	var yes_r := rect("yes_empty" + n)
	var no_r := rect("no_empty" + n)
	draw_frame("no_empty" + n if on else "no_full" + n, Vector2.ZERO if on else no_r.position - rect("no_full" + n).position)
	draw_frame("yes_full" + n if on else "yes_empty" + n, yes_r.position - rect("yes_full" + n).position if on else Vector2.ZERO)
	var key: String = row[1]
	hit(yes_r, func(_d: bool): _set_flag(key, true), "Yes_" + key)
	hit(no_r, func(_d: bool): _set_flag(key, false), "No_" + key)


func _set_flag(key: String, v: bool) -> void:
	click_sound()
	flt[key] = v
	build()


func _style(d: int) -> void:
	var i := STYLES.find(int(flt.get("style", -1)))
	flt["style"] = STYLES[posmod(i + d, STYLES.size())]
	build()


func accept() -> void:
	flt["max_ping"] = clampi(int(_ping_edit.text) if _ping_edit.text.is_valid_int() else 0, 0, 9999)
	Net.server_filter = flt.duplicate()
	Net.save_filter()
	closed.emit(true)
