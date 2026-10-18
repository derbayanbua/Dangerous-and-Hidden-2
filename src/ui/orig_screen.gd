class_name OrigScreen
extends Control
## Basis für Bildschirme, die originalgetreu aus einem Menümodell (4DS) aufgebaut werden:
## 1024×768-Bühne (Letterbox, Ränder mit dem abgedunkelten Hintergrund), Hintergrund-Kachelbild und alle
## Elemente als Original-Dreiecke mit Original-UVs (Atlanten X_NMNBTN/X_NMNBTW, X_SQUARE, MM_RED …).
## Daten: orig_cache/ui/menu/layout/<menü>.json (tools/_menu_export.py, Feld „tris“ = px @1024×768 + UV).
## Ohne Layoutdatei bleiben die Elemente unsichtbar; Texte/Knöpfe erscheinen dann an Ersatzpositionen.

const REF := Vector2(1024, 768)
const INK := Color(0.17, 0.13, 0.08)
const INK_HOVER := Color(0.45, 0.08, 0.04)
const INK_DISABLED := Color(0.17, 0.13, 0.08, 0.35)
const INK_RED := Color(0.62, 0.08, 0.04)

var stage: Control
var layout_name := ""
var frames := {}                 ## Frame-Name -> Layout-Eintrag
var _menu_dir := ""
var _wide_bg: TextureRect
var _overlay := false
var _click: AudioStreamPlayer
static var _tex_cache := {}
static var _layout_cache := {}


## Zeichnet Dreiecke eines oder mehrerer Original-Frames (absolute Bühnenkoordinaten).
class TrisView extends Control:
	var tris: Array = []
	var shift := Vector2.ZERO
	var overrides := {}          ## Texturname (groß) -> Texture2D; null = nicht zeichnen
	var squeeze := Vector2.ONE   ## Füllgrad (Balken): Skalierung um squeeze_origin
	var squeeze_origin := Vector2.ZERO
	var owner_screen: OrigScreen

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = OrigScreen.REF

	func _draw() -> void:
		for t in tris:
			var tn := String(t[0]).to_upper()
			if tn == "":
				continue
			var tex: Texture2D = overrides[tn] if overrides.has(tn) else owner_screen.tex_named(tn)
			if tex == null:
				continue
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for v in t[1]:
				var p := Vector2(float(v[0]), float(v[1]))
				p = squeeze_origin + (p - squeeze_origin) * squeeze + shift
				pts.append(p)
				uvs.append(Vector2(float(v[2]), float(v[3])))
			draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)


## overlay = true: Menü über dem laufenden Bild (Pausemenü im Einsatz) – ohne schwarzen/abgedunkelten Rand
func setup_stage(overlay := false) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay = overlay
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45) if overlay else Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_wide_bg = TextureRect.new()
	_wide_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wide_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wide_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wide_bg.modulate = Color(0.45, 0.45, 0.45)
	_wide_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wide_bg.visible = not overlay
	add_child(_wide_bg)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = REF
	stage.clip_contents = true
	add_child(stage)
	_menu_dir = OrigLevel.cache_root() + "/ui/menu"
	_click = AudioStreamPlayer.new()
	_click.bus = "Master"
	if FileAccess.file_exists(_menu_dir + "/audio/button.wav"):
		_click.stream = AudioStreamWAV.load_from_file(_menu_dir + "/audio/button.wav")
	add_child(_click)
	resized.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_instance_valid(stage):
		return
	var k := minf(size.x / REF.x, size.y / REF.y)
	if k <= 0.0:
		return
	stage.scale = Vector2(k, k)
	stage.position = (size - REF * k) * 0.5


## Bühne leeren und Menümodell laden (Hintergrund wird gezeichnet)
func begin(menu: String) -> void:
	for c in stage.get_children():
		stage.remove_child(c)
		c.queue_free()
	layout_name = menu
	frames = load_layout(menu)
	var tx := tex_file("backgrounds/%s.png" % menu)
	_wide_bg.texture = tx
	if tx:
		var tr := TextureRect.new()
		tr.texture = tx
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = REF
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(tr)
	elif _overlay:
		pass                     # Menümodell ohne Hintergrundkacheln (main ingame, Dialoge) über dem Spielbild
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.72, 0.68, 0.58)
		cr.size = REF
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(cr)


static func load_layout(menu: String) -> Dictionary:
	if _layout_cache.has(menu):
		return _layout_cache[menu]
	var out := {}
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/ui/menu/layout/%s.json" % menu)
	if typeof(d) == TYPE_DICTIONARY:
		for f in d.get("frames", []):
			if not out.has(String(f["name"])):
				out[String(f["name"])] = f
	_layout_cache[menu] = out
	return out


func has_layout() -> bool:
	return not frames.is_empty()


func fr(name: String) -> Dictionary:
	return frames.get(name, {})


## Bildschirmrechteck eines Frames (px @1024×768)
func rect(name: String, fallback := Rect2(0, 0, 0, 0)) -> Rect2:
	var r: Array = fr(name).get("rect_px", [])
	if r.size() == 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	return fallback


func tex_file(rel: String) -> Texture2D:
	var path: String = rel if rel.begins_with("/") or rel.contains(":") else _menu_dir + "/" + rel
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tx: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			tx = ImageTexture.create_from_image(img)
	_tex_cache[path] = tx
	return tx


## Originaltexturname („X_NMNBTN.BMP“) -> exportiertes PNG
func tex_named(name: String) -> Texture2D:
	return tex_file("textures/%s.png" % name.to_lower().get_basename())


## Frame(s) zeichnen; shift verschiebt (z. B. Vorlage an eine andere Zeile), overrides tauscht Texturen
func draw_frames(names: Array, parent: Control = null, shift := Vector2.ZERO, overrides := {}) -> TrisView:
	return draw_from(frames, names, parent, shift, overrides)


## wie draw_frames, aber aus einem anderen Menümodell (Dialoge: confirm, selection screen)
func draw_from(lay: Dictionary, names: Array, parent: Control = null, shift := Vector2.ZERO, overrides := {}) -> TrisView:
	var v := TrisView.new()
	v.owner_screen = self
	v.shift = shift
	v.overrides = overrides
	for n in names:
		v.tris.append_array(lay.get(String(n), {}).get("tris", []))
	(parent if parent else stage).add_child(v)
	return v


static func rect_in(lay: Dictionary, name: String, fallback := Rect2(0, 0, 0, 0)) -> Rect2:
	var r: Array = lay.get(name, {}).get("rect_px", [])
	if r.size() == 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	return fallback


func draw_frame(name: String, shift := Vector2.ZERO, overrides := {}, parent: Control = null) -> TrisView:
	return draw_frames([name], parent, shift, overrides)


## Füllbalken (Frame hlcpct*): Länge = frac, waagrecht von links bzw. senkrecht von unten
func bar(name: String, frac: float, vertical := false, overrides := {}) -> TrisView:
	var v := draw_frame(name, Vector2.ZERO, overrides)
	var r := rect(name)
	frac = clampf(frac, 0.0, 1.0)
	if vertical:
		v.squeeze = Vector2(1.0, frac)
		v.squeeze_origin = Vector2(r.position.x, r.end.y)
	else:
		v.squeeze = Vector2(frac, 1.0)
		v.squeeze_origin = r.position
	return v


func label(r: Rect2, txt: String, font_size := 15, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT,
		valign := VERTICAL_ALIGNMENT_CENTER, wrap := false) -> Label:
	var l := Label.new()
	l.position = r.position
	l.size = r.size
	l.text = txt
	l.horizontal_alignment = align
	l.vertical_alignment = valign
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if not wrap else TextServer.OVERRUN_NO_TRIMMING
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	# einzeilige Texte verkleinern statt abschneiden (Originalfelder sind knapp bemessen)
	var fs := font_size
	var font := l.get_theme_font("font")
	if not wrap and font and r.size.x > 0.0:
		while fs > 9 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 2.0:
			fs -= 1
	l.add_theme_font_size_override("font_size", fs)
	return l


## Text in einen Text-Frame (text_*) des Modells
func text_at(frame: String, txt: String, font_size := 15, align := HORIZONTAL_ALIGNMENT_LEFT, color := INK,
		wrap := false, fallback := Rect2(0, 0, 10, 10)) -> Label:
	var l := label(rect(frame, fallback), txt, font_size, color, align,
		VERTICAL_ALIGNMENT_TOP if wrap else VERTICAL_ALIGNMENT_CENTER, wrap)
	l.name = frame.validate_node_name()
	return l


## Titel (text_screen, rechtsbündig) und Versionszeile wie im Hauptmenü
func title(text_id: int, fallback: String, frame := "text_screen") -> void:
	text_at(frame, SAS.text(text_id, fallback), 24, HORIZONTAL_ALIGNMENT_RIGHT, INK, false,
		Rect2(584.7, 44.0, 354.5, 43.0)).name = "Title"
	text_at("text_h&dversion", "Dangerous and Hidden 2 (unofficial) · v%s" % ProjectSettings.get_setting("application/config/version"),
		14, HORIZONTAL_ALIGNMENT_LEFT, INK, false, Rect2(71.2, 61.6, 414.1, 23.1))


## Kind-Frames eines Knopf-Dummys: [normal, aktiv]
static func button_parts(lay: Dictionary, dummy: String) -> Array:
	var normal := ""
	var active := ""
	for n in lay:
		var f: Dictionary = lay[n]
		if f.get("parent") == null or str(f["parent"]) != dummy or not f.has("tris"):
			continue
		if (n.begins_with("normal") or n.begins_with("emptynormal") or n.begins_with("allnormal")) and normal == "":
			normal = n
		elif n.begins_with("activ") and active == "":
			active = n
	return [normal, active]


## Original-Knopf: Normal-/Hover-Grafik aus dem Modell (Hover-Quad an die Normalposition verschoben)
func orig_button(dummy: String, txt: String, cb: Callable, enabled := true, node_name := "", font_size := 17,
		fallback := Rect2(525.4, 669.0, 414.0, 35.8)) -> Button:
	return button_from(frames, dummy, txt, cb, enabled, node_name, font_size, fallback)


func button_from(lay: Dictionary, dummy: String, txt: String, cb: Callable, enabled := true, node_name := "",
		font_size := 17, fallback := Rect2(525.4, 669.0, 414.0, 35.8), shift := Vector2.ZERO, parent: Control = null) -> Button:
	var holder: Control = parent if parent else stage
	var parts := button_parts(lay, dummy)
	var r: Rect2 = rect_in(lay, parts[0], fallback) if parts[0] != "" else fallback
	r.position += shift
	var nv: TrisView = null
	var hv: TrisView = null
	if parts[0] != "":
		nv = draw_from(lay, [parts[0]], holder, shift)
	if parts[1] != "":
		hv = draw_from(lay, [parts[1]], holder, r.position - rect_in(lay, parts[1]).position)
		hv.visible = false
	var b := Button.new()
	b.name = (node_name if node_name != "" else dummy).validate_node_name()
	b.position = r.position
	b.size = r.size
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK_HOVER)
	b.add_theme_color_override("font_pressed_color", INK_HOVER)
	b.add_theme_color_override("font_disabled_color", INK_DISABLED)
	b.disabled = not enabled
	if hv:
		b.mouse_entered.connect(func(): if not b.disabled: hv.visible = true)
		b.mouse_exited.connect(func(): hv.visible = false)
	if not enabled and nv:
		nv.modulate = Color(1, 1, 1, 0.55)
	b.pressed.connect(func():
		click_sound()
		cb.call())
	holder.add_child(b)
	return b


## Original-Rückfrage (MODELS\confirm.4ds, um den Bildschirmmittelpunkt): buttons = [[Text, Callable], …]
## (1 Knopf = „bok“, 2 Knöpfe = „byes?“/„bno?“). Schließt sich beim Klick selbst.
func dialog(msg: String, buttons: Array) -> Control:
	var lay := load_layout("confirm")
	var center := REF * 0.5
	var ov := Control.new()
	ov.name = "Dialog"
	ov.size = REF
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(ov)
	draw_from(lay, ["shadow01", "confirm"], ov, center)
	var tr := rect_in(lay, "text", Rect2(-143, -67, 285, 130))
	tr.position += center
	var l := Label.new()
	l.position = tr.position
	l.size = tr.size
	l.text = msg
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", INK)
	ov.add_child(l)
	var dummies: Array = ["bok"] if buttons.size() == 1 else ["byes?", "bno?"]
	for i in mini(buttons.size(), dummies.size()):
		var cb: Callable = buttons[i][1]
		button_from(lay, dummies[i], String(buttons[i][0]), func():
			ov.queue_free()
			cb.call(), true, "Dialog%d" % i, 16, Rect2(-60 + 130 * i, 64, 123, 33), center, ov)
	return ov


## Unsichtbare Klickfläche (Porträts, Ausrüstungsplätze, Lagerzeilen); cb(double_click: bool).
## on_release: erst beim Loslassen auslösen (Ziehen und Ablegen: das Drücken baut den Bildschirm nicht neu auf)
func hit(r: Rect2, cb: Callable, node_name := "", on_release := false) -> Control:
	var c := Control.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	if node_name != "":
		c.name = node_name.validate_node_name()
		c.set_meta("hit", node_name)      # eindeutige Kennung auch bei automatisch umbenannten Knoten
	if on_release:
		c.gui_input.connect(_hit_release.bind(c, cb))
	else:
		c.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				cb.call(ev.double_click))
	stage.add_child(c)
	return c


func _hit_release(ev: InputEvent, c: Control, cb: Callable) -> void:
	if not (ev is InputEventMouseButton) or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mb := ev as InputEventMouseButton
	if mb.pressed:
		c.set_meta("_down", true)
		c.set_meta("_dbl", mb.double_click)
	elif bool(c.get_meta("_down", false)):
		c.set_meta("_down", false)
		cb.call(bool(c.get_meta("_dbl", false)))


## Bild in ein Rechteck (Porträt, Gegenstandssymbol)
func picture(r: Rect2, tx: Texture2D, parent: Control = null) -> TextureRect:
	var t := TextureRect.new()
	t.position = r.position
	t.size = r.size
	t.texture = tx
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else stage).add_child(t)
	return t


## Werteleisten (panel02): Wert, Beschriftung, Leisten-Nr. Teamauswahl (col 2) bzw. Inventar/Mehrspieler
## (col 3), Wert-Text; Beschriftungen = Texte 2670–2676 (Reihenfolge laut hd2.exe 0x693030)
const STAT_ROWS := [["shooting", "text_shooting", "00", "07", "text_shooting01"],
	["strength", "text_strenght", "01", "08", "text_strenght01"], ["health", "text_health", "02", "09", "text_health01"],
	["endurance", "text_endurance", "03", "03", "text_endurance01"], ["stealth", "text_stealth", "04", "04", "text_stealth01"],
	["first_aid", "text_first aid", "05", "05", "text_first aid01"], ["lockpick", "text_lockpick", "06", "06", "text_lockpick01"]]


func stat_rows(stats: Dictionary, col: int) -> void:
	for i in STAT_ROWS.size():
		var row: Array = STAT_ROWS[i]
		# schmale Felder (Mehrspieler-Bildschirm) tragen die Kürzel 2680–2686
		var short := rect(row[1], Rect2(0, 0, 100, 10)).size.x < 60.0
		text_at(row[1], SAS.text((2680 if short else 2670) + i, String(row[0])), 13)
		var v := float(stats.get(row[0], 0.0))
		draw_frame("hlcpctcr" + row[col])
		# Füllgrad: Werte 0–100; Gesundheit (Originalwerte 515–645) bezogen auf 1000 = Annahme [P]
		bar("hlcpct" + row[col], v / (1000.0 if row[0] == "health" else 100.0))
		text_at(row[4], "%d" % roundi(v), 13, HORIZONTAL_ALIGNMENT_RIGHT)


## Original-Klickklang „Menu Button“; zentral über OrigAudio.play_ui, sobald vorhanden
func click_sound() -> void:
	var oa := get_node_or_null("/root/OrigAudio")
	if oa and oa.has_method("play_ui"):
		oa.call("play_ui", "button")
		return
	if _click and _click.stream:
		_click.play()
