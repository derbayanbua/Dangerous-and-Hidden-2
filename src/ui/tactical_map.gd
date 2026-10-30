extends CanvasLayer
## Taktische Karte (Taste M) nach dem Original (gameinterface.4ds, Gruppe „tactical_map“: Knopfleiste, Marker;
## Texte 7300–7343, 7420–7449; docs/re_notes_hud.md §3):
## - Draufsicht über dem aktiven Soldaten (orthografisch), Kamerastufen 1×–16× (TMcamera1x…16x, Mausrad)
## - Spiel angehalten; Knopf „Echtzeit“ (realtime) lässt das Spiel bei offener Karte weiterlaufen
## - Linksklick auf Soldat: auswählen (Shift: mehrere); Linksklick ins Gelände: Wegpunkt an den Plan der
##   ausgewählten Soldaten anhängen (mehrere Wegpunkte je Soldat); Klick auf einen Wegpunkt markiert ihn
## - Knopfleiste: NEU SAMMELN (regroup) · SIGNAL 1/2 (wait01/02: Wegpunkt wartet auf Signal) · Haltung STEHEN/
##   DUCKEN/LIEGEN · Gangart SPRINTEN/LAUFEN/GEHEN/LANGSAM · Stimmung AGGRESSIV/DEFENSIV/PASSIV · LÖSCHEN/ALLE LÖSCHEN
##   · Kamera-Stufe · Echtzeit · Optionen (Tastenhilfe). Haltung/Gangart/Stimmung gelten für neue Wegpunkte und für
##   den markierten Wegpunkt.
## - Marker wie im Original: Verbündete (x_we, aktiver Soldat x_wesel), bekannte Feinde (x_enm), Zivilisten/NPC
##   (x_civ), Ziele (x_object)
## Ausführung: Die Soldaten laufen ihre Wegpunkte der Reihe nach ab (SquadBrain MOVE + plan), Haltung als
## stance_override, GEHEN/LANGSAM = leise (Schleichen), Stimmung → Feuerregel (aggressiv = Feuer frei, defensiv =
## nur bei Beschuss/auf Kommando, passiv = Feuer halten – Zuordnung [P]); an Signal-Wegpunkten warten sie, bis
## Signal 1/2 kommt (Befehlsmenü „Taktik-Modus“ bzw. send_signal). Letzter Wegpunkt: Halten.
## Folgen/Halten (Tasten order_follow/order_hold) für Auswahl bzw. alle · M/Esc schließen.

const ZOOMS := [200.0, 100.0, 50.0, 25.0, 12.5]       ## 1×, 2×, 4×, 8×, 16× (Bildhöhe in m)
const ZOOM_ICONS := ["TMcamera1x", "TMcamera2x", "TMcamera4x", "TMcamera8x", "TMcamera16x"]
const STANCE_BTN := {"stay": 0, "kneel": 1, "lie": 2}   ## Soldier.Stance
const GAITS := ["sprint", "run", "walk", "slow"]
const MINDS := ["aggresive", "defensive", "passive"]
## Knopf -> Tooltip-Text (Originaltexte)
const TIPS := {"regroup": [7420, "NEU SAMMELN"], "wait01": [7421, "SIGNAL 1"], "wait02": [7422, "SIGNAL 2"],
	"stay": [7423, "STEHEN"], "kneel": [7424, "DUCKEN"], "lie": [7425, "LIEGEN"], "sprint": [7426, "SPRINTEN"],
	"run": [7427, "LAUFEN"], "walk": [7428, "GEHEN"], "slow": [7429, "LANGSAM"], "aggresive": [7432, "AGGRESSIV"],
	"defensive": [7431, "DEFENSIV"], "passive": [7430, "PASSIV"], "delete": [7433, "LÖSCHEN"],
	"deleteall": [7434, "ALLE LÖSCHEN"], "TMcamera": [7436, "KAMERA-BEWEGUNG"], "realtime": [0, "ECHTZEIT"],
	"options": [7435, "OPTIONEN"]}
## Beschriftungen der Gruppen (hd2.exe 0x4B579E ff.: 7300 Neu sammeln … 7360)
const CAPTIONS := {"text_regroup": [7300, "Neu sammeln"], "text_signals": [7310, "Signale"], "text_pose": [7320, "Haltung"],
	"text_movement": [7330, "Bewegung"], "text_mind": [7340, "Stimmung"], "text_delete": [7350, "Löschen"],
	"text_cameramotion": [7436, "Kamera"], "text_options": [7360, "Optionen"]}
const BUTTONS := ["regroup", "wait01", "wait02", "stay", "kneel", "lie", "sprint", "run", "walk", "slow", "aggresive",
	"defensive", "passive", "delete", "deleteall", "TMcamera", "realtime", "options"]

var mission: Mission
var is_open := false
var selected: Array[Soldier] = []
var realtime := false
var plans := {}                   ## Soldier -> Array[Dictionary] Wegpunkte {pos, stance, gait, mind, signal}
var waiting := {}                 ## Soldier -> Signalnummer, an der er gerade wartet
var cur_stance := -1              ## -1 = Haltung des Anführers
var cur_gait := "run"
var cur_mind := ""
var sel_wp := []                  ## [Soldier, Index] markierter Wegpunkt
var _cam: Camera3D
var _overlay: Control
var _bar: Control
var _zoom_i := 2
var _center := Vector3.ZERO
var _help: Label
var _buttons := {}                ## Knopfname -> TextureButton
var _hud_dir := ""
var _spec := {}
var _tex := {}
var _input_was := true


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
	_hud_dir = OrigLevel.cache_root() + "/ui/hud"
	var spec = LsRuntime._read_json(_hud_dir + "/hud_spec.json")
	if typeof(spec) == TYPE_DICTIONARY:
		for e in spec.get("elements", []):
			if String(e.get("group", "")) == "tactical_map":
				_spec[String(e["name"])] = e
	_bar = Control.new()
	_bar.name = "TacticalBar"
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_bar)
	_help = Label.new()
	_help.name = "TacticalHelp"
	_help.text = ("TAKTISCHE KARTE · LMT Soldat wählen / Wegpunkt setzen (mehrere je Soldat) · Shift mehrere · RMT Auswahl aufheben" +
		" · Rad Kamera 1×–16× · WASD verschieben · %s folgen · %s halten · M schließen") % [
		InputSetup.binding_text("order_follow"), InputSetup.binding_text("order_hold")]
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_help.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_help.position = Vector2(16, 12)
	_help.visible = false
	_overlay.add_child(_help)
	_build_bar()
	_overlay.resized.connect(_layout_bar)


# --- Knopfleiste (Originalsymbole aus gameinterface.4ds) ------------------------------------------------

func _load_tex(file: String) -> Texture2D:
	if file == "":
		return null
	if _tex.has(file):
		return _tex[file]
	var p := _hud_dir + "/" + file
	var t: Texture2D = null
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img:
			t = ImageTexture.create_from_image(img)
	_tex[file] = t
	return t


func _build_bar() -> void:
	var band := ColorRect.new()
	band.name = "Band"
	band.color = Color(0.03, 0.03, 0.02, 0.82)
	band.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_child(band)
	for nm in BUTTONS:
		var b := TextureButton.new()
		b.name = "TM_" + nm
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.texture_normal = _load_tex(String(_spec.get(nm, {}).get("texture", "")))
		b.texture_pressed = _load_tex(String(_spec.get("~" + nm, {}).get("texture", "")))
		b.toggle_mode = nm in STANCE_BTN or nm in GAITS or nm in MINDS or nm == "realtime"
		var tip: Array = TIPS.get(nm, [0, nm])
		b.tooltip_text = SAS.text(int(tip[0]), String(tip[1])) if int(tip[0]) > 0 else String(tip[1])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(press_button.bind(nm))
		if b.texture_normal == null:
			# ohne Originalsymbole: Textknopf
			var l := Label.new()
			l.text = String(tip[1]).substr(0, 4)
			l.add_theme_font_size_override("font_size", 10)
			l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
			b.add_child(l)
		_bar.add_child(b)
		_buttons[nm] = b
	var zoom := TextureRect.new()
	zoom.name = "TM_zoom"
	zoom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(zoom)
	for cap in CAPTIONS:
		var l := Label.new()
		l.name = cap
		var c: Array = CAPTIONS[cap]
		l.text = SAS.text(int(c[0]), String(c[1]))
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.86, 0.82, 0.7))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(l)


## Rechteck eines Originalelements (x 0..1, y 0..1 im 4:3-Rahmen auf voller Höhe, mittig)
func _rect_of(nm: String, fallback: Array) -> Rect2:
	var r = _spec.get(nm, {}).get("rect", fallback)
	if not (r is Array) or (r as Array).size() != 4:
		r = fallback
	var h := _overlay.size.y
	var fw := h * 4.0 / 3.0
	var x0 := (_overlay.size.x - fw) * 0.5
	return Rect2(x0 + float(r[0]) * fw, float(r[1]) * h, (float(r[2]) - float(r[0])) * fw, (float(r[3]) - float(r[1])) * h)


func _layout_bar() -> void:
	if _overlay.size.y <= 0.0:
		return
	var band := _bar.get_node("Band") as ColorRect
	var top := _rect_of("text_pose", [0.017, 0.816, 0.084, 0.836]).position.y - 4.0
	var bottom := _rect_of("stay", [0.017, 0.836, 0.048, 0.877]).end.y + 6.0
	band.position = Vector2(0, top)
	band.size = Vector2(_overlay.size.x, bottom - top)
	var i := 0
	for nm in BUTTONS:
		var fb := [0.02 + 0.05 * i, 0.836, 0.051 + 0.05 * i, 0.877]
		var r := _rect_of(nm, fb)
		var b: Control = _buttons[nm]
		b.position = r.position
		b.size = r.size
		i += 1
	var z := _bar.get_node("TM_zoom") as TextureRect
	var zr := _rect_of("TMcamera1x", [0.838, 0.836, 0.869, 0.877])
	z.position = zr.position
	z.size = zr.size
	for cap in CAPTIONS:
		var l := _bar.get_node(cap) as Label
		var cr := _rect_of(cap, [0.0, 0.816, 0.1, 0.836])
		l.position = cr.position
		l.size = cr.size
	_help.position = Vector2(16, 12)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(_overlay.size.x - 32.0, 0)
	_help.size = Vector2(_overlay.size.x - 32.0, 0)


func _sync_buttons() -> void:
	for nm in STANCE_BTN:
		(_buttons[nm] as TextureButton).set_pressed_no_signal(cur_stance == int(STANCE_BTN[nm]))
	for g in GAITS:
		(_buttons[g] as TextureButton).set_pressed_no_signal(cur_gait == g)
	for md in MINDS:
		(_buttons[md] as TextureButton).set_pressed_no_signal(cur_mind == md)
	(_buttons["realtime"] as TextureButton).set_pressed_no_signal(realtime)
	var z := _bar.get_node("TM_zoom") as TextureRect
	z.texture = _load_tex(String(_spec.get(ZOOM_ICONS[_zoom_i], {}).get("texture", "")))


## Knopf der Leiste (auch für Tests)
func press_button(nm: String) -> void:
	var wp := _selected_wp()
	match nm:
		"regroup":
			for s in _targets():
				clear_plan(s)
				mission.squad.order_one(s, SquadBrain.Order.FOLLOW)
			Events.say(SAS.text(7420, "NEU SAMMELN"), 2.0)
		"wait01", "wait02":
			var n: int = 1 if nm == "wait01" else 2
			if not wp.is_empty():
				wp["signal"] = 0 if int(wp.get("signal", 0)) == n else n
			else:
				for s in selected:
					var p: Array = plans.get(s, [])
					if not p.is_empty():
						p.back()["signal"] = n
		"stay", "kneel", "lie":
			cur_stance = -1 if cur_stance == int(STANCE_BTN[nm]) else int(STANCE_BTN[nm])
			if not wp.is_empty():
				wp["stance"] = cur_stance
		"sprint", "run", "walk", "slow":
			cur_gait = nm
			if not wp.is_empty():
				wp["gait"] = nm
		"aggresive", "defensive", "passive":
			cur_mind = "" if cur_mind == nm else nm
			if not wp.is_empty():
				wp["mind"] = cur_mind
		"delete":
			if not wp.is_empty():
				_delete_wp(sel_wp[0], int(sel_wp[1]))
			else:
				for s in selected:
					var p: Array = plans.get(s, [])
					if not p.is_empty():
						_delete_wp(s, p.size() - 1)
		"deleteall":
			for s in _targets():
				if plans.has(s):
					clear_plan(s)
					mission.squad.order_one(s, SquadBrain.Order.HOLD)
		"TMcamera":
			_zoom_i = (_zoom_i + 1) % ZOOMS.size()
			_update_camera()
		"realtime":
			realtime = not realtime
			if is_open:
				get_tree().paused = not realtime
		"options":
			_help.visible = not _help.visible
	_sync_buttons()
	_overlay.queue_redraw()


func _targets() -> Array[Soldier]:
	return selected if not selected.is_empty() else mission.squad.alive_members()


# --- Öffnen / Eingaben -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Net.is_online:
		return       # Mehrspieler: keine pausierende Taktikkarte
	if event.is_action_pressed("tactical_map") or event.is_action_pressed("map"):   # B-015: KARTE öffnet dieselbe Karte
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
				_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_i = maxi(_zoom_i - 1, 0)
			MOUSE_BUTTON_LEFT:
				_click(event.position, event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				selected.clear()
				sel_wp = []
		_update_camera()
		_sync_buttons()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("order_follow"):
		_order(SquadBrain.Order.FOLLOW)
	elif event.is_action_pressed("order_hold"):
		_order(SquadBrain.Order.HOLD)
	elif tac_key(event):
		get_viewport().set_input_as_handled()


## B-015: Original-Tasten des Taktik-Modus (Options.bin „profile“, Texte 7420–7449) → Knöpfe der Leiste bzw. Kamera.
## Drehen/Neigen (7443–7447) entfällt: die Karte ist eine genordete Draufsicht (docs/status/backlog_b015.md).
const TAC_BUTTONS := {"tac_regroup": "regroup", "tac_signal_1": "wait01", "tac_signal_2": "wait02", "tac_stand": "stay",
	"tac_crouch": "kneel", "tac_prone": "lie", "tac_sprint": "sprint", "tac_run": "run", "tac_walk": "walk",
	"tac_slow": "slow", "tac_passive": "passive", "tac_defensive": "defensive", "tac_aggressive": "aggresive",
	"tac_delete": "delete", "tac_delete_all": "deleteall", "tac_options": "options", "tac_camera_move": "TMcamera"}
const TAC_PAN := {"tac_cam_forward": Vector3(0, 0, -1), "tac_cam_backward": Vector3(0, 0, 1),
	"tac_cam_left": Vector3(-1, 0, 0), "tac_cam_right": Vector3(1, 0, 0)}


func tac_key(event: InputEvent) -> bool:
	for a: String in TAC_BUTTONS:
		if event.is_action_pressed(a):
			press_button(TAC_BUTTONS[a])
			return true
	if event.is_action_pressed("tac_zoom_in") or event.is_action_pressed("tac_cam_down"):
		_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
	elif event.is_action_pressed("tac_zoom_out") or event.is_action_pressed("tac_cam_up"):
		_zoom_i = maxi(_zoom_i - 1, 0)
	else:
		return false
	_update_camera()
	_sync_buttons()
	return true


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
	_layout_bar()
	_sync_buttons()
	mission.hud.visible = false
	_input_was = mission.controller.input_enabled
	mission.controller.input_enabled = false
	get_tree().paused = not realtime
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	_overlay.visible = false
	mission.hud.visible = true
	mission.rig.camera.current = true
	mission.controller.input_enabled = _input_was
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
	for a: String in TAC_PAN:
		if Input.is_action_pressed(a):
			pan += TAC_PAN[a]
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
		sel_wp = []
		if not additive:
			selected.clear()
		if hit == mission.squad.leader():
			Events.say("%s wird direkt gesteuert." % hit.soldier_name, 2.0)
		elif selected.has(hit):
			selected.erase(hit)
		else:
			selected.append(hit)
		return
	# Wegpunkt anklicken (markieren)
	for s in plans:
		var p: Array = plans[s]
		for i in p.size():
			if _cam.unproject_position(p[i]["pos"]).distance_to(screen) < 9.0:
				sel_wp = [s, i]
				cur_stance = int(p[i].get("stance", -1))
				cur_gait = String(p[i].get("gait", "run"))
				cur_mind = String(p[i].get("mind", ""))
				return
	if selected.is_empty():
		return
	var pos := ground_at(screen)
	if not pos.is_finite():
		return
	sel_wp = []
	var i := 0
	for s in selected:
		var off := Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * (1.5 if i > 0 else 0.0)
		add_waypoint(s, pos + off)
		i += 1
	Events.say("Plan: %d Soldat(en), Wegpunkt gesetzt" % selected.size(), 2.0)


func _order(o: int) -> void:
	var targets := _targets()
	for s in targets:
		clear_plan(s)
		mission.squad.order_one(s, o)
	Events.say("Befehl: %s" % SquadBrain.ORDER_NAMES[o], 2.0)


# --- Pläne (mehrere Wegpunkte je Soldat) -------------------------------------------------------------

## Wegpunkt mit den aktuellen Einstellungen anhängen; der erste wird sofort als Bewegungsbefehl ausgegeben.
func add_waypoint(s: Soldier, pos: Vector3, signal_n := 0) -> void:
	if s == null or not s.alive or s == mission.squad.leader():
		return
	if not plans.has(s):
		plans[s] = []
	var p: Array = plans[s]
	p.append({"pos": pos, "stance": cur_stance, "gait": cur_gait, "mind": cur_mind, "signal": signal_n})
	if p.size() == 1:
		_issue(s)


func clear_plan(s: Soldier) -> void:
	plans.erase(s)
	waiting.erase(s)
	var b := mission.squad.brain_of(s)
	if b:
		b.stance_override = -1
		b.quiet = false


func _delete_wp(s: Soldier, i: int) -> void:
	var p: Array = plans.get(s, [])
	if i < 0 or i >= p.size():
		return
	p.remove_at(i)
	sel_wp = []
	if p.is_empty():
		clear_plan(s)
		mission.squad.order_one(s, SquadBrain.Order.HOLD)
	elif i == 0:
		waiting.erase(s)
		_issue(s)


func _selected_wp() -> Dictionary:
	if sel_wp.size() != 2 or not plans.has(sel_wp[0]):
		return {}
	var p: Array = plans[sel_wp[0]]
	return p[int(sel_wp[1])] if int(sel_wp[1]) < p.size() else {}


## Nächsten Wegpunkt als Bewegungsbefehl (Haltung, Gangart, Stimmung) ausgeben
func _issue(s: Soldier) -> void:
	var p: Array = plans.get(s, [])
	if p.is_empty():
		return
	var wp: Dictionary = p[0]
	var leise := String(wp.get("gait", "run")) in ["walk", "slow"]
	mission.squad.order_one(s, SquadBrain.Order.MOVE, wp["pos"])
	var b := mission.squad.brain_of(s)
	if b == null:
		return
	b.stance_override = int(wp.get("stance", -1))
	match String(wp.get("mind", "")):
		"aggresive":
			b.roe = SquadBrain.ROE.FIRE_AT_WILL
		"defensive":
			b.roe = SquadBrain.ROE.ON_MY_LEAD
		"passive":
			b.roe = SquadBrain.ROE.HOLD_FIRE
	if leise:
		b.quiet = true
		b.move_to(wp["pos"], Soldier.MoveMode.SNEAK)


## Signal 1/2 (Befehlsmenü „Taktik-Modus“ T7260/7261 bzw. Kartenknopf): wartende Soldaten laufen weiter
func send_signal(n: int) -> int:
	var released := 0
	for s in waiting.keys():
		if int(waiting[s]) == n:
			waiting.erase(s)
			_advance(s)
			released += 1
	return released


func _advance(s: Soldier) -> void:
	var p: Array = plans.get(s, [])
	if not p.is_empty():
		p.remove_at(0)
	if p.is_empty():
		var b := mission.squad.brain_of(s)
		plans.erase(s)
		mission.squad.order_one(s, SquadBrain.Order.HOLD)       # Planende: Position halten
		if b:
			b.quiet = false
	else:
		_issue(s)


func _physics_process(_delta: float) -> void:
	if mission == null or get_tree().paused:
		return
	for s in plans.keys():
		if not is_instance_valid(s) or not s.alive:
			plans.erase(s)
			waiting.erase(s)
			continue
		var b := mission.squad.brain_of(s)
		if b == null or s == mission.squad.leader():
			continue
		if not b.plan or b.order != SquadBrain.Order.MOVE:
			# Befehl aufgehoben (Befehlsmenü, Folgen, Halten …): Plan verwerfen
			plans.erase(s)
			waiting.erase(s)
			continue
		if waiting.has(s):
			continue
		var wp: Dictionary = plans[s][0]
		var flat := Vector2(s.global_position.x - wp["pos"].x, s.global_position.z - wp["pos"].z)
		if flat.length() < 1.6:
			var sig := int(wp.get("signal", 0))
			if sig > 0:
				waiting[s] = sig
			else:
				_advance(s)


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


func _marker(sp: Vector2, nm: String, col: Color, rad := 7.0) -> void:
	var tx := _load_tex(String(_spec.get(nm, {}).get("texture", "")))
	if tx:
		_overlay.draw_texture_rect(tx, Rect2(sp - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false)
	else:
		_overlay.draw_circle(sp, rad, col)


func _draw_overlay() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	# Ziele (x_object)
	var m01 := mission
	var marks := []
	if "radio_site" in m01 and m01.radio_site:
		marks.append([m01.radio_site.global_position, "Funksender", m01.objective(&"radio").is_done()])
	if "codebook" in m01 and m01.codebook:
		marks.append([m01.codebook.global_position, "Codebuch", m01.objective(&"codebook").is_done()])
	if mission.extraction_pos.is_finite() and mission.extraction_pos != Vector3.ZERO:
		marks.append([mission.extraction_pos, "Abholpunkt", false])
	for mk in marks:
		var sp := _cam.unproject_position(mk[0])
		var col := Color(0.6, 0.9, 0.5) if mk[2] else Color(1.0, 0.85, 0.3)
		_marker(sp, "objective", col, 9.0)
		_overlay.draw_string(font, sp + Vector2(11, 5), mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	# Gegner (nur bekannte) bzw. Zivilisten/NPC
	for e in known_enemies():
		var sp := _cam.unproject_position(e.global_position)
		_marker(sp, "civil" if e.team != Soldier.TEAM_AXIS else "enemy", Color(0.9, 0.2, 0.15))
		var f := e.forward()
		_overlay.draw_line(sp, sp + Vector2(f.x, f.z) * 14.0, Color(0.9, 0.2, 0.15), 2.0)
	# Pläne: Wegpunktketten
	for s in plans:
		if not is_instance_valid(s):
			continue
		var p: Array = plans[s]
		var prev := _cam.unproject_position(s.global_position)
		for i in p.size():
			var wp: Dictionary = p[i]
			var sp := _cam.unproject_position(wp["pos"])
			var col: Color = Color(1.0, 0.6, 0.2) if waiting.has(s) and i == 0 else Color(0.55, 0.85, 1.0)
			_overlay.draw_dashed_line(prev, sp, col, 1.5, 6.0)
			_overlay.draw_circle(sp, 4.0, col)
			if sel_wp.size() == 2 and sel_wp[0] == s and int(sel_wp[1]) == i:
				_overlay.draw_arc(sp, 8.0, 0, TAU, 16, Color.WHITE, 2.0)
			var tag := ""
			var st := int(wp.get("stance", -1))
			if st >= 0:
				tag += ["S", "D", "L"][st]
			tag += String({"sprint": "»", "run": "", "walk": "g", "slow": "~"}.get(String(wp.get("gait", "run")), ""))
			if int(wp.get("signal", 0)) > 0:
				tag += " ⚑%d" % int(wp["signal"])
			if tag != "":
				_overlay.draw_string(font, sp + Vector2(6, -6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
			prev = sp
	# Trupp (x_we, aktiver Soldat x_wesel)
	for i in mission.squad.members.size():
		var s := mission.squad.members[i]
		var sp := _cam.unproject_position(s.global_position)
		if not s.alive:
			_overlay.draw_string(font, sp, "✝", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.6, 0.6, 0.6))
			continue
		var col := Color(0.4, 0.75, 1.0)
		if s == mission.squad.leader():
			col = Color(1.0, 0.95, 0.5)
		_marker(sp, "allied_active" if s == mission.squad.leader() else "allied", col, 8.0)
		if selected.has(s):
			_overlay.draw_arc(sp, 13.0, 0, TAU, 24, Color.WHITE, 2.0)
		var f := s.forward()
		_overlay.draw_line(sp, sp + Vector2(f.x, f.z) * 16.0, col, 2.0)
		_overlay.draw_string(font, sp + Vector2(9, -8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		var b := mission.squad.brain_of(s)
		if b and s != mission.squad.leader() and b.order != SquadBrain.Order.FOLLOW and not plans.has(s):
			var tp := _cam.unproject_position(b.hold_pos)
			_overlay.draw_dashed_line(sp, tp, col, 1.5, 6.0)
			_overlay.draw_circle(tp, 3.0, col)
	var info_y: float = (_help.position.y + _help.get_combined_minimum_size().y + 20.0) if _help.visible else 30.0
	_overlay.draw_string(font, Vector2(16, info_y), "Kamera %s · %d m Bildhöhe%s" % [["1×", "2×", "4×", "8×", "16×"][_zoom_i],
		int(ZOOMS[_zoom_i]), " · ECHTZEIT" if realtime else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7))
