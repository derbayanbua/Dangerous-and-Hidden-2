extends Control
## Optionen: Anzeige, Grafik, Steuerung, Tastenbelegung. Wird sowohl vom
## Hauptmenü als auch vom Pausemenü als Overlay geöffnet.

signal closed

var _rebind_action := ""
var _rebind_button: Button
var _key_buttons := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := UIKit.centered_panel(self, 760)
	UIKit.title("OPTIONEN", 28, v)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(720, 470)
	v.add_child(tabs)
	tabs.add_child(_display_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_keys_tab())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	UIKit.button("Übernehmen und schließen", _close, row)


func _grid(tab_name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = tab_name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	return g


func _add_label(g: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size.x = 260
	g.add_child(l)


func _display_tab() -> Control:
	var g := _grid("Anzeige & Grafik")
	_add_label(g, "Auflösung")
	var res := OptionButton.new()
	for i in Settings.RESOLUTIONS.size():
		var r: Vector2i = Settings.RESOLUTIONS[i]
		res.add_item(Settings.resolution_name(r), i)
		if r == Settings.resolution:
			res.select(i)
	res.item_selected.connect(func(i): Settings.resolution = Settings.RESOLUTIONS[i])
	g.add_child(res)
	_add_label(g, "Vollbild")
	g.add_child(_check(Settings.fullscreen, func(on): Settings.fullscreen = on))
	_add_label(g, "VSync")
	g.add_child(_check(Settings.vsync, func(on): Settings.vsync = on))
	_add_label(g, "Grafikqualität")
	var q := OptionButton.new()
	for i in Settings.QUALITY_NAMES.size():
		q.add_item(Settings.QUALITY_NAMES[i], i)
	q.select(Settings.quality)
	q.item_selected.connect(func(i): Settings.quality = i)
	g.add_child(q)
	_add_label(g, "Renderauflösung (FSR)")
	g.add_child(_slider(0.5, 1.0, 0.05, Settings.render_scale, func(v): Settings.render_scale = v, "%d %%", 100.0))
	_add_label(g, "Sichtfeld (FOV)")
	g.add_child(_slider(55, 95, 1, Settings.fov, func(v): Settings.fov = v, "%d°"))
	_add_label(g, "Lautstärke")
	g.add_child(_slider(0, 1, 0.05, Settings.master_volume, func(v): Settings.master_volume = v, "%d %%", 100.0))
	return g


func _controls_tab() -> Control:
	var g := _grid("Maus")
	_add_label(g, "Mausempfindlichkeit")
	g.add_child(_slider(0.02, 0.4, 0.01, Settings.mouse_sensitivity, func(v): Settings.mouse_sensitivity = v, "%.2f"))
	_add_label(g, "Maus invertieren")
	g.add_child(_check(Settings.invert_y, func(on): Settings.invert_y = on))
	return g


func _keys_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Tastenbelegung"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	for action: String in InputSetup.ACTIONS:
		_add_label(g, InputSetup.display_name(action))
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 32)
		b.text = InputSetup.binding_text(action)
		b.pressed.connect(_start_rebind.bind(action, b))
		g.add_child(b)
		_key_buttons[action] = b
	UIKit.button("Standardbelegung", func():
		InputSetup.reset_defaults()
		for a in _key_buttons:
			_key_buttons[a].text = InputSetup.binding_text(a), v)
	return scroll


func _check(on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = on
	c.toggled.connect(cb)
	return c


func _slider(mn: float, mx: float, step: float, val: float, cb: Callable, fmt: String, mul := 1.0) -> Control:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size.x = 260
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = fmt % (val * mul)
	s.value_changed.connect(func(v):
		cb.call(v)
		l.text = fmt % (v * mul))
	h.add_child(s)
	h.add_child(l)
	return h


func _start_rebind(action: String, b: Button) -> void:
	_rebind_action = action
	_rebind_button = b
	b.text = "Taste drücken…"


func _input(event: InputEvent) -> void:
	if _rebind_action == "":
		return
	var ok: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if not ok:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and _rebind_action != "pause":
		_rebind_button.text = InputSetup.binding_text(_rebind_action)
	else:
		InputSetup.rebind(_rebind_action, event)
		_rebind_button.text = InputSetup.binding_text(_rebind_action)
	_rebind_action = ""


func _close() -> void:
	Settings.save_settings()
	Settings.apply()
	closed.emit()
	queue_free()
