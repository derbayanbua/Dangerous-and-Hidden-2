class_name UIKit
extends RefCounted
## Gemeinsamer Stil für Menüs (militärisch-zurückhaltend, gut lesbar).

const BG := Color(0.08, 0.09, 0.07, 0.92)
const ACCENT := Color(0.78, 0.7, 0.45)
const TEXT := Color(0.92, 0.88, 0.76)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.16, 0.17, 0.13)
	btn.border_color = Color(0.35, 0.33, 0.24)
	btn.set_border_width_all(1)
	btn.set_content_margin_all(10)
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.26, 0.26, 0.18)
	hov.border_color = ACCENT
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Color(0.34, 0.31, 0.2)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hov)
		t.set_stylebox("pressed", cls, prs)
		t.set_stylebox("focus", cls, hov)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1, 0.95, 0.75))
	t.set_color("font_color", "Label", TEXT)
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.set_content_margin_all(24)
	panel.border_color = Color(0.3, 0.28, 0.2)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t


static func button(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func title(text: String, size: int, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


## Zentrierter Panel-Container mit VBox; gibt die VBox zurück.
static func centered_panel(parent: Control, min_width := 420.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size.x = min_width
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v
