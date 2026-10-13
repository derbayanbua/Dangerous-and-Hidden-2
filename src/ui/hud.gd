extends CanvasLayer
## Spielanzeige. Elemente nach Vorbild der im Original belegten HUD-Teile
## (healthbar, staminabar, visibility, AImode, command, ammo, team members).

const C_TEXT := Color(0.92, 0.88, 0.76)
const C_DIM := Color(0.92, 0.88, 0.76, 0.55)
const C_BG := Color(0.06, 0.07, 0.05, 0.6)
const C_HEALTH := Color(0.62, 0.16, 0.12)
const C_STAMINA := Color(0.75, 0.68, 0.32)
const C_ALERT := Color(0.9, 0.3, 0.15)

var mission: Mission
var _root: Control
var _team_box: VBoxContainer
var _team_rows: Array = []
var _weapon_label: Label
var _ammo_label: Label
var _mode_label: Label
var _stance_label: Label
var _stamina_bar: ProgressBar
var _health_bar: ProgressBar
var _vis_bar: ProgressBar
var _vis_label: Label
var _msg_box: VBoxContainer
var _obj_panel: PanelContainer
var _obj_label: Label
var _prompt: Label
var _crosshair: Control
var _compass: Label
var _alarm_label: Label
var _center_label: Label
var _font_size := 16
var _binoc_mask: TextureRect
var orig_hud: OrigHud


## Schwarze Maske mit zwei überlappenden Kreisen (Fernglas-Optik).
func _make_binocular_mask() -> Texture2D:
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.47
	var c1 := Vector2(w * 0.36, h * 0.5)
	var c2 := Vector2(w * 0.64, h * 0.5)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(p.distance_to(c1), p.distance_to(c2))
			var a := clampf((d - r) / 6.0 + 1.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)


func setup(m: Mission) -> void:
	mission = m
	layer = 5
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_team_panel()
	_build_weapon_panel()
	_build_status_panel()
	_build_messages()
	_build_objectives()
	_build_crosshair()
	_prompt = _label("", 18, C_TEXT)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-200, 60)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)
	_compass = _label("", 18, C_TEXT)
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-150, 10)
	_compass.size = Vector2(300, 30)
	_compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_compass)
	_alarm_label = _label("ALARM", 22, C_ALERT)
	_alarm_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alarm_label.position = Vector2(-60, 40)
	_alarm_label.size = Vector2(120, 30)
	_alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alarm_label.visible = false
	_root.add_child(_alarm_label)
	_center_label = _label("", 34, C_TEXT)
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.position = Vector2(-400, -120)
	_center_label.size = Vector2(800, 60)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_center_label)
	_binoc_mask = TextureRect.new()
	_binoc_mask.texture = _make_binocular_mask()
	_binoc_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_binoc_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_binoc_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_binoc_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_binoc_mask.visible = false
	_root.add_child(_binoc_mask)
	_root.move_child(_binoc_mask, 0)
	# Original-HUD (gameinterface.4ds) ersetzt Trupp-, Waffen-, Status-Panel und Textkompass
	if OrigHud.available():
		orig_hud = OrigHud.new()
		_root.add_child(orig_hud)
		_root.move_child(orig_hud, 1)
		orig_hud.setup(mission)
		for n: Control in [_team_box.get_parent(), _weapon_label.get_parent().get_parent(),
				_stance_label.get_parent().get_parent(), _compass]:
			n.visible = false
		_msg_box.position.y = -230    # über der Truppleiste
	Events.message.connect(_on_message)
	Events.mission_finished.connect(_on_finished)
	Events.objective_updated.connect(func(_id): _refresh_objectives())
	_refresh_objectives()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override("fill", fg)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build_team_panel() -> void:
	var p := _panel()
	p.position = Vector2(12, 12)
	_root.add_child(p)
	_team_box = VBoxContainer.new()
	p.add_child(_team_box)
	for i in mission.squad.members.size():
		var row := HBoxContainer.new()
		var key := _label("F%d" % (i + 1), 14, C_DIM)
		key.custom_minimum_size.x = 28
		var name_l := _label("", 15, C_TEXT)
		name_l.custom_minimum_size.x = 130
		var hb := _bar(C_HEALTH, 70, 8)
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var info := _label("", 13, C_DIM)
		info.custom_minimum_size.x = 150
		row.add_child(key)
		row.add_child(name_l)
		row.add_child(hb)
		row.add_child(info)
		_team_box.add_child(row)
		_team_rows.append([name_l, hb, info, key])


func _build_weapon_panel() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.position = Vector2(-12, -12)
	_root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	_weapon_label = _label("", 18, C_TEXT)
	_ammo_label = _label("", 30, C_TEXT)
	_mode_label = _label("", 14, C_DIM)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_weapon_label)
	v.add_child(_ammo_label)
	v.add_child(_mode_label)


func _build_status_panel() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.position = Vector2(12, -12)
	_root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	_stance_label = _label("", 18, C_TEXT)
	v.add_child(_stance_label)
	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	g.add_child(_label("Gesundheit", 13, C_DIM))
	_health_bar = _bar(C_HEALTH, 160, 10)
	g.add_child(_health_bar)
	g.add_child(_label("Ausdauer", 13, C_DIM))
	_stamina_bar = _bar(C_STAMINA, 160, 10)
	g.add_child(_stamina_bar)
	_vis_label = _label("Entdeckung", 13, C_DIM)
	g.add_child(_vis_label)
	_vis_bar = _bar(C_ALERT, 160, 10)
	g.add_child(_vis_bar)


func _build_messages() -> void:
	_msg_box = VBoxContainer.new()
	_msg_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_msg_box.position = Vector2(-350, -150)
	_msg_box.size = Vector2(700, 120)
	_msg_box.alignment = BoxContainer.ALIGNMENT_END
	_msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_msg_box)


func _build_objectives() -> void:
	_obj_panel = _panel()
	_obj_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_obj_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_obj_panel.position = Vector2(-12, 12)
	_root.add_child(_obj_panel)
	_obj_label = _label("", 15, C_TEXT)
	_obj_panel.add_child(_obj_label)


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_root.add_child(_crosshair)


func _draw_crosshair() -> void:
	var s := mission.controller.active if mission and mission.controller else null
	if s == null or not s.alive:
		return
	var cam := mission.rig.camera
	var spread := s.current_spread()
	var vp_h := get_viewport().get_visible_rect().size.y
	# Streuwinkel in Pixel umrechnen
	var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(cam.fov * 0.5)) * vp_h * 0.5
	px = clampf(px, 3.0, 200.0)
	var col := Color(1, 1, 1, 0.8)
	var l := 8.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_crosshair.draw_line(d * px, d * (px + l), col, 2.0)
	_crosshair.draw_circle(Vector2.ZERO, 1.5, col)


func _process(_delta: float) -> void:
	if mission == null:
		return
	var s := mission.controller.active
	_update_team()
	if s == null:
		return
	var w := s.current_weapon()
	if w:
		_weapon_label.text = w.data.display_name
		if w.data.slot == WeaponData.Slot.GRENADE:
			_ammo_label.text = "%d" % w.total_ammo()
		else:
			_ammo_label.text = "%d / %d" % [w.in_mag, w.reserve]
		_mode_label.text = "NACHLADEN…" if w.is_reloading() else w.fire_mode_text()
		_mode_label.text += "  ·  Verband: %d" % s.medkits
	else:
		_weapon_label.text = "unbewaffnet"
		_ammo_label.text = ""
		_mode_label.text = ""
	var stance_txt: String = ["Stehend", "Hockend", "Liegend"][s.stance]
	var move_txt: String = ["Gehen", "Sprint", "Schleichen", "Laufen"][s.move_mode]
	var cam_txt := "1. Person" if mission.rig.mode == CameraRig.Mode.FIRST else "3. Person"
	if s.using_binoculars:
		cam_txt = "Fernglas"
	if s.disguised:
		cam_txt += " · GETARNT" if s.seconds_since_shot() > 6.0 else " · TARNUNG AUFGEFLOGEN"
	_stance_label.text = "%s · %s · %s" % [s.soldier_name, stance_txt, move_txt] + "   [%s]" % cam_txt
	if s.vehicle != null:
		var v: Vehicle = s.vehicle
		_stance_label.text = "%s · %s (%s) · %d km/h · Zustand %d %%" % [s.soldier_name, v.vehicle_name,
			"Fahrer" if s.seat_index == 0 else "Mitfahrer", int(v.speed_kmh()), int(100.0 * v.health / v.max_health)]
	_health_bar.value = s.health
	_stamina_bar.value = s.stamina
	# Entdeckungsanzeige: höchste Aufmerksamkeit eines Gegners auf den Spieler
	var vis := 0.0
	for e in mission.enemies:
		if e.alive:
			var per: Perception = e.get_node("Perception")
			vis = maxf(vis, per.awareness.get(s, 0.0))
	_vis_bar.value = vis * 100.0
	_vis_label.text = "ENTDECKT" if vis >= 1.0 else "Entdeckung"
	var deg := int(round(fposmod(rad_to_deg(-s.look_yaw), 360.0)))
	var dirs := ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
	_compass.text = "%s  %03d°" % [dirs[int(round(deg / 45.0)) % 8], deg]
	_alarm_label.visible = mission.alarm_raised
	var it := mission.controller.interact_target
	_prompt.text = "[%s] %s" % [InputSetup.binding_text("interact"), it.prompt] if it else ""
	if s.heal_time_left > 0.0:
		_prompt.text = "Verband wird angelegt … %.1f s" % s.heal_time_left
	elif s.vehicle != null:
		_prompt.text = "[%s] Aussteigen" % InputSetup.binding_text("interact")
	_binoc_mask.visible = s.using_binoculars
	_crosshair.visible = not s.using_binoculars
	_crosshair.queue_redraw()


func _update_team() -> void:
	var sq := mission.squad
	for i in _team_rows.size():
		var m := sq.members[i]
		var row: Array = _team_rows[i]
		var b := sq.brain_of(m)
		row[0].text = m.soldier_name
		row[1].value = m.health
		var active := i == sq.active_index
		row[0].add_theme_color_override("font_color", C_ALERT if not m.alive else (Color(1, 0.95, 0.6) if active else C_TEXT))
		if not m.alive:
			row[2].text = "gefallen"
		elif active:
			row[2].text = "◄ gesteuert"
		else:
			var roe := "Feuer frei" if b.roe == SquadBrain.ROE.FIRE_AT_WILL else "Feuer halten"
			row[2].text = "%s · %s" % [b.order_name(), roe]


func _refresh_objectives() -> void:
	var lines := ["MISSIONSZIELE"]
	for o in mission.objectives:
		if o.state == Objective.State.INACTIVE:
			continue
		var mark := "[ ]"
		if o.state == Objective.State.DONE:
			mark = "[x]"
		elif o.state == Objective.State.FAILED:
			mark = "[-]"
		lines.append("%s %s%s" % [mark, o.text, " (optional)" if o.optional else ""])
	lines.append("Formation: %s" % SquadManager.FORMATION_NAMES[mission.squad.formation])
	_obj_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("objectives"):
		_obj_panel.visible = not _obj_panel.visible
	if event.is_action_pressed("order_formation"):
		_refresh_objectives.call_deferred()


func _on_message(text: String, seconds: float) -> void:
	var l := _label(text, 17, C_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_box.add_child(l)
	while _msg_box.get_child_count() > 5:
		_msg_box.get_child(0).free()
	# Tween gehört dem Label und endet mit ihm (kein hängender Callback)
	var tw := l.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _on_finished(success: bool, reason: String) -> void:
	_center_label.text = ("AUFTRAG ERFÜLLT" if success else "AUFTRAG GESCHEITERT") + "\n" + reason
	_center_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.6) if success else C_ALERT)
