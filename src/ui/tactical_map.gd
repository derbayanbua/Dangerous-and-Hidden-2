extends CanvasLayer
## Taktische Karte (Taste M). Original: Kartenkamera mit Zoomstufen
## (TMcamera1x…16x) und 3D-Befehlseingabe (3Dcommand) bei angehaltenem Spiel.
## - Spiel pausiert, Draufsicht über dem aktiven Soldaten (orthografisch)
## - Linksklick auf Soldat: auswählen (Shift: mehrere)
## - Linksklick ins Gelände: ausgewählte Soldaten dorthin (Befehl "Bewegen")
## - Rechtsklick: Auswahl aufheben · Mausrad: Zoom · WASD: verschieben
## - H folgen, J halten (für Auswahl bzw. alle) · M/Esc: schließen

const ZOOMS := [25.0, 50.0, 100.0, 200.0]

var mission: Mission
var is_open := false
var selected: Array[Soldier] = []
var _cam: Camera3D
var _overlay: Control
var _zoom_i := 1
var _center := Vector3.ZERO
var _help: Label


func setup(m: Mission) -> void:
	mission = m
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.far = 600.0
	m.add_child(_cam)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_overlay.visible = false
	add_child(_overlay)
	_help = Label.new()
	_help.text = "TAKTISCHE KARTE (Pause)  ·  LMT Soldat wählen / Ziel setzen  ·  Shift mehrere  ·  RMT Auswahl aufheben  ·  Rad Zoom  ·  WASD verschieben  ·  H folgen  ·  J halten  ·  M schließen"
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_help.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_help.position = Vector2(16, 140)
	_overlay.add_child(_help)


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_online:
		return       # Mehrspieler: keine pausierende Taktikkarte
	if event.is_action_pressed("tactical_map"):
		if is_open:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_i = maxi(_zoom_i - 1, 0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
			MOUSE_BUTTON_LEFT:
				_click(event.position, event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				selected.clear()
		_update_camera()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("order_follow"):
		_order(SquadBrain.Order.FOLLOW)
	elif event.is_action_pressed("order_hold"):
		_order(SquadBrain.Order.HOLD)


func open() -> void:
	is_open = true
	_center = mission.controller.active.global_position if mission.controller.active else Vector3.ZERO
	_update_camera()
	if _cam.environment == null and mission.env:
		# Kartenansicht ohne Dunst/Nebel, etwas heller und kontrastreicher
		var e: Environment = mission.env.duplicate()
		e.fog_enabled = false
		e.volumetric_fog_enabled = false
		e.adjustment_contrast = 1.2
		e.adjustment_saturation = 1.1
		_cam.environment = e
	_cam.current = true
	_overlay.visible = true
	mission.hud.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	_overlay.visible = false
	mission.hud.visible = true
	mission.rig.camera.current = true
	get_tree().paused = false
	if not Game.cli.has("autoplay"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_camera() -> void:
	_cam.size = ZOOMS[_zoom_i]
	_cam.global_position = _center + Vector3(0, 250, 0)
	_cam.global_rotation = Vector3(-PI * 0.5, 0, 0)   # Norden oben
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_open:
		return
	var pan := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): pan.z -= 1
	if Input.is_physical_key_pressed(KEY_S): pan.z += 1
	if Input.is_physical_key_pressed(KEY_A): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D): pan.x += 1
	if pan != Vector3.ZERO:
		_center += pan.normalized() * ZOOMS[_zoom_i] * delta
		_update_camera()
	_overlay.queue_redraw()


## Bodenpunkt unter einer Bildschirmposition.
func ground_at(screen: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0, 1)
	var hit := mission.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _click(screen: Vector2, additive: bool) -> void:
	# Nächstgelegenen Soldatenmarker im Klickradius suchen
	var hit: Soldier = null
	var best := 14.0
	for m in mission.squad.members:
		if not m.alive:
			continue
		var d := _cam.unproject_position(m.global_position).distance_to(screen)
		if d < best:
			best = d
			hit = m
	if hit:
		if not additive:
			selected.clear()
		if hit == mission.squad.leader():
			Events.say("%s wird direkt gesteuert." % hit.soldier_name, 2.0)
		elif selected.has(hit):
			selected.erase(hit)
		else:
			selected.append(hit)
		return
	if selected.is_empty():
		return
	var p := ground_at(screen)
	if not p.is_finite():
		return
	var i := 0
	for s in selected:
		var off := Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * (1.5 if i > 0 else 0.0)
		mission.squad.order_one(s, SquadBrain.Order.MOVE, p + off)
		i += 1
	Events.say("Befehl: %d Soldat(en) bewegen" % selected.size(), 2.0)


func _order(o: int) -> void:
	var targets := selected if not selected.is_empty() else mission.squad.alive_members()
	for s in targets:
		mission.squad.order_one(s, o)
	Events.say("Befehl: %s" % SquadBrain.ORDER_NAMES[o], 2.0)


## Bekannte Gegner = von irgendeinem Trupp-Mitglied aktuell gesehen oder erkannt.
func known_enemies() -> Array[Soldier]:
	var r: Array[Soldier] = []
	for e in mission.enemies:
		if not e.alive:
			continue
		for m in mission.squad.alive_members():
			var per: Perception = m.get_node("Perception")
			if per.visible_now.get(e, false) or per.awareness.get(e, 0.0) >= 1.0:
				r.append(e)
				break
	return r


func _draw_overlay() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	# Ziele
	var m01 := mission
	var marks := []
	if "radio_site" in m01 and m01.radio_site:
		marks.append([m01.radio_site.global_position, "Funksender", m01.objective(&"radio").is_done()])
	if "codebook" in m01 and m01.codebook:
		marks.append([m01.codebook.global_position, "Codebuch", m01.objective(&"codebook").is_done()])
	marks.append([mission.extraction_pos, "Abholpunkt", false])
	for mk in marks:
		var sp := _cam.unproject_position(mk[0])
		var col := Color(0.6, 0.9, 0.5) if mk[2] else Color(1.0, 0.85, 0.3)
		_overlay.draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), col, false, 2.0)
		_overlay.draw_string(font, sp + Vector2(10, 5), mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	# Gegner (nur bekannte)
	for e in known_enemies():
		var sp := _cam.unproject_position(e.global_position)
		_overlay.draw_circle(sp, 6.0, Color(0.9, 0.2, 0.15))
		var f := e.forward()
		_overlay.draw_line(sp, sp + Vector2(f.x, f.z) * 14.0, Color(0.9, 0.2, 0.15), 2.0)
	# Trupp
	for i in mission.squad.members.size():
		var s := mission.squad.members[i]
		var sp := _cam.unproject_position(s.global_position)
		if not s.alive:
			_overlay.draw_string(font, sp, "✝", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.6, 0.6, 0.6))
			continue
		var b := mission.squad.brain_of(s)
		var col := Color(0.4, 0.75, 1.0)
		if s == mission.squad.leader():
			col = Color(1.0, 0.95, 0.5)
		_overlay.draw_circle(sp, 8.0, col)
		if selected.has(s):
			_overlay.draw_arc(sp, 13.0, 0, TAU, 24, Color.WHITE, 2.0)
		var f := s.forward()
		_overlay.draw_line(sp, sp + Vector2(f.x, f.z) * 16.0, col, 2.0)
		_overlay.draw_string(font, sp + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		if b and s != mission.squad.leader() and b.order != SquadBrain.Order.FOLLOW:
			var tp := _cam.unproject_position(b.hold_pos)
			_overlay.draw_dashed_line(sp, tp, col, 1.5, 6.0)
			_overlay.draw_circle(tp, 3.0, col)
	_overlay.draw_string(font, Vector2(16, 120), "Maßstab: %d m Bildhöhe" % int(ZOOMS[_zoom_i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7))
