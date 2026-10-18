class_name MpHud
extends CanvasLayer
## Mehrspieler-HUD (nur online, von Net.mission_ready an die Mission gehängt):
##  - Rundenanzeige: Aufwärmen (T7402) mit Restzeit, Rundenzeit, Runde n/m, lebende Spieler je Team,
##    nächste Welle (Besetzung), Siegzähler; Zielliste der HD2-Aufgaben (Original HUD `mpobjectives`)
##  - eigener Zustand: „AUF RESPAWN WARTEN“ (T7405) mit Countdown, „Respawn-Schutz“ (T20313), Zuschauer (T20311/20312)
##  - Chat: „ALLE INFORMIEREN“ (T2853, Taste T) / „TEAM INFORMIEREN“ (T2854, Taste Y), Konsole (T2852, Taste ^)
##  - Abstimmung (HUD „voting“, T8930–8932): Anzeige, F1 = zustimmen
##  - Zuschauerkamera: Spieler folgen (LMT/RMT wechselt) oder frei (Leertaste umschalten, WASD + Maus)
##  - Spawnzonen-Karte (T2525/2528, Taste M bzw. Pausenmenü): eigene Zone anklicken = Spawnzone festlegen
##  - Voice-Chat-Anzeige (eigenes Sprechen / wer spricht)

const CHAT_LINES := 6
const CHAT_SHOW_S := 10.0

var _top: Label
var _state: Label
var _obj: Label
var _vote: Label
var _chat: Label
var _voice: Label
var _line: LineEdit
var _input_kind := ""              ## "all", "team", "console"
var _zone_panel: Control
var _spec_cam: Camera3D
var spectating := false
var spec_free := false
var spec_target_id := 0
var _spec_yaw := 0.0
var _spec_pitch := -0.3
var _chat_t := 0.0
var _last_chat_n := 0
var feedback                       ## MpFeedback (src/ui/mp_feedback.gd)
var kill_cam                       ## KillCam (src/ui/kill_cam.gd)


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_top = _label(root, "Top", Control.PRESET_CENTER_TOP, Vector2(-300, 8), Vector2(600, 60), HORIZONTAL_ALIGNMENT_CENTER, 16)
	_state = _label(root, "State", Control.PRESET_CENTER, Vector2(-300, 60), Vector2(600, 80), HORIZONTAL_ALIGNMENT_CENTER, 22)
	_obj = _label(root, "Objectives", Control.PRESET_TOP_RIGHT, Vector2(-420, 80), Vector2(410, 260), HORIZONTAL_ALIGNMENT_RIGHT, 13)
	_vote = _label(root, "Vote", Control.PRESET_CENTER_TOP, Vector2(-300, 70), Vector2(600, 40), HORIZONTAL_ALIGNMENT_CENTER, 15)
	_vote.add_theme_color_override("font_color", UIKit.ACCENT)
	_chat = _label(root, "Chat", Control.PRESET_BOTTOM_LEFT, Vector2(12, -330), Vector2(620, 150), HORIZONTAL_ALIGNMENT_LEFT, 14)
	_chat.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_voice = _label(root, "Voice", Control.PRESET_TOP_LEFT, Vector2(12, 120), Vector2(300, 24), HORIZONTAL_ALIGNMENT_LEFT, 13)
	_line = LineEdit.new()
	_line.name = "ChatInput"
	_line.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_line.position = Vector2(12, -172)
	_line.size = Vector2(620, 30)
	_line.max_length = Net.CHAT_MAX
	_line.visible = false
	_line.text_submitted.connect(_submit)
	root.add_child(_line)
	Net.chat_received.connect(func(_n, _t, _team): _chat_t = CHAT_SHOW_S)
	_build_graphics(root)
	feedback = preload("res://src/ui/mp_feedback.gd").new()          # Trefferanzeige, Richtungsanzeige, Kill-Feed, Namen (src/ui/mp_feedback.gd)
	feedback.name = "Feedback"
	root.add_child(feedback)
	root.move_child(feedback, 0)
	kill_cam = preload("res://src/ui/kill_cam.gd").new()           # Kill-Cam nach dem eigenen Tod (src/ui/kill_cam.gd)
	kill_cam.name = "KillCam"
	root.add_child(kill_cam)
	root.resized.connect(_layout_graphics)
	_layout_graphics.call_deferred()


# --- Original-HUD-Grafiken (gameinterface.4ds, orig_cache/ui/hud/crops; hd2.exe 0x4AE7C0/0x4AD8F0/0x4AED20) -------
## Elemente im 4:3-Rahmen auf voller Fensterhöhe (wie OrigHud): Punktetafel mp_scoretable oben rechts (Hintergrund +
## Wappen mpaxis_score links / mpallied_score rechts, dazwischen Teampunkte und Zeit), Zielliste mpobjectives links
## (je Aufgabe Symbol mpneutral_objNN offen bzw. mpallied/mpaxis_objNN erfüllt für das begünstigte Team, daneben der
## Aufgabentext), VIP-Marke mp_vip an der Truppleiste, Abstimmungsband „voting“ unten. Rechtecke = hud_spec.json.
const HUD_RECTS := {
	"mp_scoretable": [0.81118, -0.00365, 1.00001, 0.08536, "right"],
	"mpaxis_score": [0.82089, 0.00838, 0.86033, 0.04302, "right"],
	"mpallied_score": [0.95085, 0.00838, 0.9903, 0.04302, "right"],
	"mp_vip": [0.15946, 0.89648, 0.18924, 0.93549, "center"],
	"voting": [0.0, 0.76261, 1.0, 0.88721, "center"],
	# Teamwappen in der Truppleiste (tabl01, Gruppe squad_bar = mittig; OrigHud blendet sie aus)
	"mpaxis": [0.03859, 0.90668, 0.07804, 0.94132, "center"],
	"mpallied": [0.03859, 0.90668, 0.07804, 0.94132, "center"],
}
const OBJ_RECT := [0.00651, 0.15564, 0.0303, 0.17653]     ## erste Zeile mpobjectives; weitere im Abstand OBJ_STEP
const OBJ_STEP := 0.026
const OBJ_MAX := 16
var gfx := {}                    ## Name -> Control (Tests: gfx.has("mp_scoretable") = Originalgrafik geladen)
var _obj_icons: Array[TextureRect] = []
var _obj_labels: Array[Label] = []
var _score_label: Label
var _vote_band: ColorRect
static var _crop_cache := {}


static func crop(name: String) -> Texture2D:
	if _crop_cache.has(name):
		return _crop_cache[name]
	var p := OrigLevel.cache_root() + "/ui/hud/crops/%s.png" % name
	var tx: Texture2D = null
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img:
			tx = ImageTexture.create_from_image(img)
	_crop_cache[name] = tx
	return tx


func _tex_rect(parent: Control, nm: String, tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.name = nm
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _build_graphics(root: Control) -> void:
	if crop("mp_scoretable") == null:
		return                   # ohne Originaldaten: nur Textanzeige
	_vote_band = ColorRect.new()
	_vote_band.name = "VotingBand"
	_vote_band.color = Color(0.05, 0.05, 0.04, 0.55)
	_vote_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vote_band.visible = false
	root.add_child(_vote_band)
	root.move_child(_vote_band, 0)
	gfx["voting"] = _vote_band
	for nm in ["mp_scoretable", "mpaxis_score", "mpallied_score", "mp_vip", "mpaxis", "mpallied"]:
		gfx[nm] = _tex_rect(root, "Gfx_" + nm, crop(nm))
	_score_label = Label.new()
	_score_label.name = "ScoreText"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_color_override("font_color", Color(0.12, 0.1, 0.07))
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_score_label)
	for i in OBJ_MAX:
		_obj_icons.append(_tex_rect(root, "ObjIcon%02d" % i, null))
		var l := Label.new()
		l.name = "ObjText%02d" % i
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
		_obj_labels.append(l)
	_obj.visible = false          # Textliste wird durch die Originalsymbole + Texte ersetzt


## Bildschirmrechteck im 4:3-Rahmen (Anker links/mitte/rechts wie OrigHud)
func hud_rect(r: Array, anchor: String) -> Rect2:
	var sz := (get_node("Root") as Control).size
	var fw := sz.y * 4.0 / 3.0
	var x0 := (sz.x - fw) * 0.5
	if anchor == "right":
		x0 = sz.x - fw
	elif anchor == "left":
		x0 = 0.0
	return Rect2(x0 + float(r[0]) * fw, float(r[1]) * sz.y, (float(r[2]) - float(r[0])) * fw, (float(r[3]) - float(r[1])) * sz.y)


func _layout_graphics() -> void:
	if gfx.is_empty():
		return
	for nm in gfx:
		var r: Array = HUD_RECTS[nm]
		var rr := hud_rect(r, String(r[4]))
		if nm == "voting":
			rr = Rect2(0, rr.position.y, (get_node("Root") as Control).size.x, rr.size.y)
		(gfx[nm] as Control).position = rr.position
		(gfx[nm] as Control).size = rr.size
	var st := hud_rect(HUD_RECTS["mp_scoretable"], "right")
	var ax := hud_rect(HUD_RECTS["mpaxis_score"], "right")
	var al := hud_rect(HUD_RECTS["mpallied_score"], "right")
	_score_label.position = Vector2(ax.end.x, st.position.y)
	_score_label.size = Vector2(al.position.x - ax.end.x, st.size.y)
	_score_label.add_theme_font_size_override("font_size", maxi(int(st.size.y * 0.24), 10))
	for i in OBJ_MAX:
		var rr := hud_rect([OBJ_RECT[0], OBJ_RECT[1] + i * OBJ_STEP, OBJ_RECT[2], OBJ_RECT[3] + i * OBJ_STEP], "left")
		_obj_icons[i].position = rr.position
		_obj_icons[i].size = rr.size
		_obj_labels[i].position = Vector2(rr.end.x + 6, rr.position.y - 2)
		_obj_labels[i].size = Vector2(rr.size.x * 18.0, rr.size.y + 4)
		_obj_labels[i].add_theme_font_size_override("font_size", maxi(int(rr.size.y * 0.8), 10))


func _update_graphics() -> void:
	if gfx.is_empty():
		return
	var tm := Net.team_mode()
	for nm in ["mp_scoretable", "mpaxis_score", "mpallied_score"]:
		(gfx[nm] as Control).visible = tm
	_score_label.visible = tm
	if tm:
		var hi: Dictionary = Net.hud_info
		var t := "%d : %d" % [int(Net.team_score[Soldier.TEAM_AXIS]), int(Net.team_score[Soldier.TEAM_ALLIED])]
		var tl := float(hi.get("tl", 0.0))
		var secs: float = float(hi.get("t", 0.0))
		if int(hi.get("st", 0)) == Net.State.WARMUP:
			secs = float(hi.get("wl", 0.0))
		elif tl > 0.0:
			secs = tl - float(hi.get("t", 0.0))
		_score_label.text = "%s\n%s" % [t, _mmss(secs)]
	var me: Soldier = Net._soldiers.get(Net.my_id())
	(gfx["mp_vip"] as Control).visible = is_instance_valid(me) and me.alive and me.has_meta("vip")
	var alive_team := is_instance_valid(me) and me.alive and tm
	(gfx["mpaxis"] as Control).visible = alive_team and me.team == Soldier.TEAM_AXIS
	(gfx["mpallied"] as Control).visible = alive_team and me.team == Soldier.TEAM_ALLIED
	_vote_band.visible = _vote.visible
	var objs: Array = []
	var m = Game.current_mission()
	if Net.mode() == Net.Mode.OBJECTIVES and m != null and m.has_method("mp_objectives"):
		objs = m.mp_objectives()
	var axis := int(Net.players.get(Net.my_id(), {}).get("team", 0)) == Soldier.TEAM_AXIS
	for i in OBJ_MAX:
		var show := i < objs.size()
		_obj_icons[i].visible = show
		_obj_labels[i].visible = show
		if not show:
			continue
		var o: Dictionary = objs[i]
		var done := Net.obj_done.has(int(o["index"]))
		var side := "neutral"
		if done:
			side = "axis" if int(o["team"]) == Soldier.TEAM_AXIS else "allied"
		_obj_icons[i].texture = crop("mp%s_obj%02d" % [side, i])
		_obj_labels[i].text = String(o["axis_text"] if axis else o["allied_text"])
		_obj_labels[i].modulate = Color(0.75, 0.95, 0.7) if done else Color.WHITE


func _label(parent: Control, nm: String, preset: int, pos: Vector2, sz: Vector2, align: int, fs: int) -> Label:
	var l := Label.new()
	l.name = nm
	l.set_anchors_preset(preset)
	l.position += pos
	l.size = sz
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func _mmss(s: float) -> String:
	var t := maxi(int(ceil(s)), 0)
	return "%d:%02d" % [t / 60, t % 60]


# --- Anzeige -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not Net.is_online:
		return
	var hi: Dictionary = Net.hud_info
	_top.text = top_text()
	_state.text = state_text()
	_obj.text = objectives_text()
	var v: Dictionary = hi.get("vote", {})
	_vote.visible = not v.is_empty()
	if _vote.visible:
		_vote.text = "%s: %s   –   Ja %d / %d   (F1 = zustimmen, %d s)" % [Net.tx(8930, "Abstimmung gestartet"),
			String(v.get("text", "")), int(v.get("yes", 0)), int(v.get("need", 1)), int(v.get("left", 0))]
	_chat_t -= delta
	_chat.visible = _chat_t > 0.0 or _line.visible
	_chat.text = chat_text()
	var vc := Net.voice
	var vt := ""
	if vc and vc.talking:
		vt = "● VOICE"
	elif vc and vc.frames_received > 0 and vc.last_speaker != "" and Time.get_ticks_msec() - _voice_rx_ms < 600:
		vt = "%s ◄)" % vc.last_speaker
	if vc and vc.frames_received != _voice_rx_n:
		_voice_rx_n = vc.frames_received
		_voice_rx_ms = Time.get_ticks_msec()
	_voice.text = vt
	_update_graphics()
	_update_spectator(delta)
	if _zone_panel and _zone_panel.visible:
		_zone_panel.queue_redraw()


var _voice_rx_n := 0
var _voice_rx_ms := 0


func top_text() -> String:
	var hi: Dictionary = Net.hud_info
	var parts: PackedStringArray = []
	var st := int(hi.get("st", 0))
	if st == Net.State.WARMUP:
		parts.append("%s  %s" % [Net.tx(7402, "AUFWÄRMEN"), _mmss(float(hi.get("wl", 0.0)))])
	else:
		var tl := float(hi.get("tl", 0.0))
		if tl > 0.0:
			parts.append("%s %s" % [Net.tx(2366, "RUNDENZEIT-LIMIT").capitalize(), _mmss(tl - float(hi.get("t", 0.0)))])
		else:
			parts.append(_mmss(float(hi.get("t", 0.0))))
	parts.append("Runde %d/%d" % [int(hi.get("rn", 1)), int(hi.get("rc", 1))])
	if Net.team_mode():
		var al: Array = hi.get("alive", [0, 0])
		parts.append("Alliierte %d  –  Achse %d" % [int(al[0]), int(al[1])])
		parts.append("%d : %d" % [int(Net.team_score[0]), int(Net.team_score[1])])
	var wave := float(hi.get("wave", -1.0))
	if wave >= 0.0 and st != Net.State.WARMUP:
		parts.append("Nächste Welle %d s" % int(ceil(wave)))
	return "   |   ".join(parts)


func state_text() -> String:
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var p: Dictionary = Net.players.get(Net.my_id(), {})
	if bool(p.get("spectator", false)):
		var who := ""
		if spectating and not spec_free and Net.players.has(spec_target_id):
			who = "\n%s" % Net.players[spec_target_id]["name"]
		return "ZUSCHAUER%s\n(LMT/RMT: Spieler wechseln, Leertaste: freie Kamera)" % who
	if is_instance_valid(me) and me.alive:
		var out := ""
		if me.has_meta("protect_until") and Time.get_ticks_msec() < int(me.get_meta("protect_until")):
			out = Net.tx(20313, "Respawn-Schutz")
		if me.has_meta("vip"):
			out += ("\n" if out != "" else "") + "VIP"
		return out
	if Net.match_over:
		return ""
	if Net.respawn_ready():
		return Net.tx(7406, "FEUER DRÜCKEN FÜR RESPAWN")
	if Net.respawn_at > 0:
		return "%s  %d" % [Net.tx(7405, "AUF RESPAWN WARTEN"), maxi(int(ceil((Net.respawn_at - Time.get_ticks_msec()) / 1000.0)), 0)]
	if Net.respawn_at < 0:
		return "%s  %d" % [Net.tx(7405, "AUF RESPAWN WARTEN"), int(ceil(float(Net.hud_info.get("wave", 0.0))))]
	return ""


func objectives_text() -> String:
	if Net.mode() != Net.Mode.OBJECTIVES:
		return ""
	var m = Game.current_mission()
	if m == null or not m.has_method("mp_objectives"):
		return ""
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var axis := int(Net.players.get(Net.my_id(), {}).get("team", 0)) == Soldier.TEAM_AXIS or (is_instance_valid(me) and me.team == Soldier.TEAM_AXIS)
	var lines: PackedStringArray = []
	for o in m.mp_objectives():
		var done := Net.obj_done.has(int(o["index"]))
		lines.append("%s %s" % ["✔" if done else "○", String(o["axis_text"] if axis else o["allied_text"])])
	return "\n".join(lines)


func chat_text() -> String:
	var lines: PackedStringArray = []
	var entries: Array = Net.chat_log
	for i in range(maxi(entries.size() - CHAT_LINES, 0), entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%s%s: %s" % ["(Team) " if bool(e.get("team", false)) else "", String(e["name"]), String(e["text"])])
	return "\n".join(lines)


# --- Eingabe -----------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not Net.is_online:
		return
	var m0 = Game.current_mission()
	var pm = m0.get_node_or_null("PauseMenu") if m0 else null
	if pm and pm.is_open():
		return                          # Pausenmenü/SPIELER-SETUP offen: Eingaben gehören dem Menü
	if _line.visible:
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_input()
			get_viewport().set_input_as_handled()
		return
	if kill_cam and kill_cam.active and (event.is_action_pressed("fire") or event.is_action_pressed("stance_stand")):
		kill_cam.skip()                 # Kill-Cam überspringen (→ Respawn bzw. „FEUER DRÜCKEN FÜR RESPAWN“)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat_all"):
		open_input("all")
	elif event.is_action_pressed("chat_team"):
		open_input("team")
	elif event.is_action_pressed("console"):
		open_input("console")
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F1 \
			and not (Net.hud_info.get("vote", {}) as Dictionary).is_empty():
		Net.console_command("voteyes")
	elif event.is_action_pressed("tactical_map") and _has_zones():
		toggle_zone_map()
	elif event.is_action_pressed("fire") and Net.respawn_ready():
		Net.request_respawn()          # „FEUER DRÜCKEN FÜR RESPAWN“ (T7406)
	else:
		if spectating:
			_spectator_input(event)
		return
	get_viewport().set_input_as_handled()


func open_input(kind: String) -> void:
	_input_kind = kind
	_line.placeholder_text = {"all": Net.tx(2853, "ALLE INFORMIEREN"), "team": Net.tx(2854, "TEAM INFORMIEREN"),
		"console": Net.tx(2852, "KONSOLE") + " (help)"}[kind]
	_line.text = ""
	_line.visible = true
	_line.grab_focus()
	_chat_t = CHAT_SHOW_S
	Net.chat_focus = true
	_set_controls(false)


func close_input() -> void:
	_line.visible = false
	_line.release_focus()
	Net.chat_focus = false
	_set_controls(true)


func _submit(text: String) -> void:
	var kind := _input_kind
	close_input()
	if text.strip_edges() == "":
		return
	if kind == "console":
		Net.console_command(text)
	else:
		Net.send_chat(text, kind == "team")


func _set_controls(on: bool) -> void:
	var m = Game.current_mission()
	if m and m.get("controller"):
		m.controller.input_enabled = on


# --- Zuschauer (Original 0x69AAB0: zwischen lebenden Teamkameraden umschalten; freie Kamera als Ergänzung) ----

func _update_spectator(delta: float) -> void:
	var p: Dictionary = Net.players.get(Net.my_id(), {})
	var want := bool(p.get("spectator", false)) and Game.current_mission() != null
	if want != spectating:
		_set_spectating(want)
	if not spectating:
		return
	if spec_free:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if not _line.visible else Vector2.ZERO
		var b := Basis.from_euler(Vector3(_spec_pitch, _spec_yaw, 0))
		_spec_cam.global_position += b * Vector3(iv.x, 0, iv.y) * 12.0 * delta
		_spec_cam.global_basis = b
		return
	var t: Soldier = Net._soldiers.get(spec_target_id)
	if not is_instance_valid(t) or not t.alive:
		cycle_target(1)
		t = Net._soldiers.get(spec_target_id)
	if is_instance_valid(t):
		var fw := t.forward()
		var eye := t.global_position + Vector3.UP * 1.7
		_spec_cam.global_position = _spec_cam.global_position.lerp(eye - fw * 3.2 + Vector3.UP * 0.6, clampf(delta * 6.0, 0.0, 1.0))
		_spec_cam.look_at(eye + fw * 4.0, Vector3.UP)


func _set_spectating(on: bool) -> void:
	spectating = on
	var m = Game.current_mission()
	if on:
		if _spec_cam == null:
			_spec_cam = Camera3D.new()
			_spec_cam.name = "SpectatorCam"
			_spec_cam.far = 1200.0
			m.add_child(_spec_cam)
		var sp: Array = m.mp_spawns() if m and m.has_method("mp_spawns") else []
		_spec_cam.global_position = (sp[0]["pos"] as Vector3) + Vector3.UP * 3.0 if not sp.is_empty() else Vector3(0, 5, 0)
		_spec_cam.current = true
		cycle_target(1)
	elif _spec_cam:
		_spec_cam.current = false
		if m and m.get("rig") and m.rig.camera:
			m.rig.camera.current = true


## Nächster/vorheriger lebender Spieler (Team-Stile: nur das eigene Team, wie im Original)
func cycle_target(dir: int) -> void:
	var team := int(Net.players.get(Net.my_id(), {}).get("team", -1))
	var ids: Array = []
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if is_instance_valid(s) and s.alive and (not Net.team_mode() or s.team == team):
			ids.append(int(id))
	if ids.is_empty():
		for id in Net._soldiers:
			if is_instance_valid(Net._soldiers[id]) and Net._soldiers[id].alive:
				ids.append(int(id))
	if ids.is_empty():
		spec_target_id = 0
		return
	ids.sort()
	var i := ids.find(spec_target_id)
	spec_target_id = ids[posmod(i + dir, ids.size())] if i >= 0 else ids[0]


func _spectator_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		spec_free = false
		cycle_target(1)
	elif event.is_action_pressed("aim"):
		spec_free = false
		cycle_target(-1)
	elif event.is_action_pressed("stance_stand"):
		spec_free = not spec_free
		if spec_free:
			_spec_yaw = _spec_cam.global_rotation.y
			_spec_pitch = _spec_cam.global_rotation.x
	elif event is InputEventMouseMotion and spec_free:
		var sens := Settings.mouse_sensitivity * 0.01
		_spec_yaw -= event.relative.x * sens
		_spec_pitch = clampf(_spec_pitch - event.relative.y * sens, -1.4, 1.4)


# --- Spawnzonen-Karte (Besetzung / HD2-Aufgaben) ----------------------------------------------------------

func _has_zones() -> bool:
	var m = Game.current_mission()
	return Net.mode() in [Net.Mode.OCCUPATION, Net.Mode.OBJECTIVES] and m != null and m.has_method("mp_zones") \
		and not (m.mp_zones() as Array).is_empty()


func toggle_zone_map() -> void:
	if _zone_panel == null:
		_zone_panel = ZoneMap.new()
		_zone_panel.name = "ZoneMap"
		get_node("Root").add_child(_zone_panel)
		_zone_panel.visible = false
	_zone_panel.visible = not _zone_panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _zone_panel.visible else Input.MOUSE_MODE_CAPTURED
	_set_controls(not _zone_panel.visible)


func zone_map_open() -> bool:
	return _zone_panel != null and _zone_panel.visible


## Karte der Spawnzonen (T2525/2528). Mit Originaldaten wie im Original: MISSIONS\<m>\map.4ds (tools/fmt_mp_screens.py →
## orig_cache/<m>/map_layout.json): Kartenbild 'mapa' (MAPA_*), je Zone 'zoneN' die Besitzerfläche 'alliedN'/'axisN'
## (neutral ohne), 'zone_disabledN' auf nicht wählbaren Zonen, Auswahlmarke 'selectzone' auf der gewählten Zone.
## Zuordnung über den Zonennamen (mp.json „zoneN“). Ohne Layout: eigene Draufsicht (Kreise, Farbe = Besitzer).
class ZoneMap extends Control:
	var _rects := {}        ## Zonenindex -> Rect2 (anklickbar)
	var _polys := {}        ## Zonenindex -> Array[PackedVector2Array] (Dreiecke der Zonenfläche, Klickprüfung)
	var _lay := {}          ## Frame-Name -> Layout-Eintrag
	var _lay_loaded := false
	var orig_map := false   ## Originalkarte gezeichnet (Tests)
	static var _tex := {}

	func _ready() -> void:
		# Mittig über Anker + Offsets (position = (-300, -290) lag relativ zur linken oberen Ecke → halb außerhalb)
		set_anchors_preset(Control.PRESET_CENTER)
		offset_left = -300
		offset_top = -290
		offset_right = 300
		offset_bottom = 290
		mouse_filter = Control.MOUSE_FILTER_STOP

	static func _texture(name: String) -> Texture2D:
		var key := name.to_lower().get_basename()
		if _tex.has(key):
			return _tex[key]
		var p := OrigLevel.cache_root() + "/ui/menu/textures/%s.png" % key
		var t: Texture2D = null
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				t = ImageTexture.create_from_image(img)
		_tex[key] = t
		return t

	func _layout() -> Dictionary:
		if _lay_loaded:
			return _lay
		_lay_loaded = true
		var m = Game.current_mission()
		var orig = m.get("orig") if m else null
		if orig == null:
			return _lay
		var d = LsRuntime._read_json(String(orig.mission_dir) + "/map_layout.json")
		if typeof(d) == TYPE_DICTIONARY:
			for f in d.get("frames", []):
				_lay[String(f["name"])] = f
		return _lay

	static func _r(f: Dictionary) -> Rect2:
		var r: Array = f.get("rect_px", [0, 0, 0, 0])
		return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))

	## Dreiecke eines Frames zeichnen; xf: Kartenpunkt (px) -> Panel; shift in Karten-px
	func _tris(f: Dictionary, xf: Transform2D, shift := Vector2.ZERO, out: Array = []) -> void:
		for t in f.get("tris", []):
			var tx := _texture(String(t[0]))
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for v in t[1]:
				pts.append(xf * (Vector2(float(v[0]), float(v[1])) + shift))
				uvs.append(Vector2(float(v[2]), float(v[3])))
			out.append(pts)
			if tx:
				draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tx)

	func _draw_orig(zs: Array) -> bool:
		var lay := _layout()
		if not lay.has("mapa"):
			return false
		orig_map = true
		var area := Rect2(16, 40, size.x - 32, size.y - 76)
		var b := _r(lay["mapa"])
		var sc := minf(area.size.x / maxf(b.size.x, 1.0), area.size.y / maxf(b.size.y, 1.0))
		var ofs := area.position + (area.size - b.size * sc) * 0.5 - b.position * sc
		var xf := Transform2D(0.0, Vector2(sc, sc), 0.0, ofs)
		_tris(lay["mapa"], xf)
		var my_team := int(Net.players.get(Net.my_id(), {}).get("team", -1))
		var chosen := int(Net.players.get(Net.my_id(), {}).get("zone", -1))
		_rects.clear()
		_polys.clear()
		var centers := {}
		for i in zs.size():
			var num := String(zs[i]["name"]).trim_prefix("zone")
			var own: int = int(Net.zone_owner[i]) if i < Net.zone_owner.size() else int(zs[i]["owner"])
			var shape: Dictionary = lay.get("allied" + num, lay.get("axis" + num, {}))
			var polys: Array = []
			if own == Soldier.TEAM_ALLIED and lay.has("allied" + num):
				_tris(lay["allied" + num], xf, Vector2.ZERO, polys)
			elif own == Soldier.TEAM_AXIS and lay.has("axis" + num):
				_tris(lay["axis" + num], xf, Vector2.ZERO, polys)
			elif not shape.is_empty():
				for t in shape.get("tris", []):      # neutral: nur die Fläche zur Klickprüfung
					var pts := PackedVector2Array()
					for v in t[1]:
						pts.append(xf * Vector2(float(v[0]), float(v[1])))
					polys.append(pts)
			var dis: Dictionary = lay.get("zone_disabled" + num, {})
			var c: Vector2 = xf * _r(dis).get_center() if not dis.is_empty() else (xf * _r(shape).get_center() if not shape.is_empty() else Vector2.INF)
			centers[i] = c
			var selectable := own == my_team and not (zs[i]["slots"] as Array).is_empty()
			if selectable and not polys.is_empty():
				_polys[i] = polys
				var rr: Rect2 = Rect2(xf * _r(shape).position, _r(shape).size * sc) if not shape.is_empty() else Rect2(c - Vector2(12, 12), Vector2(24, 24))
				_rects[i] = rr
			elif not dis.is_empty():
				_tris(dis, xf)                          # nicht wählbar (Original zone_disabled)
		if chosen >= 0 and centers.has(chosen) and lay.has("selectzone") and centers[chosen] != Vector2.INF:
			var sel: Dictionary = lay["selectzone"]
			_tris(sel, xf, xf.affine_inverse() * centers[chosen] - _r(sel).get_center())
		return true

	## Punkt innerhalb der Zone i (Mitte des ersten Dreiecks) – für Tests/Tastatur
	func zone_point(i: int) -> Vector2:
		if _polys.has(i) and not (_polys[i] as Array).is_empty():
			var t: PackedVector2Array = _polys[i][0]
			return (t[0] + t[1] + t[2]) / 3.0
		return (_rects[i] as Rect2).get_center() if _rects.has(i) else Vector2.INF

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.05, 0.92))
		var font := get_theme_default_font()
		draw_string(font, Vector2(14, 24), "%s   (%s)" % [Net.tx(2525, "KARTE DER SPAWN-ZONEN:"), Net.tx(2528, "SPAWN-ZONE FESTLEGEN")],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.ACCENT)
		var m = Game.current_mission()
		if m == null or not m.has_method("mp_zones"):
			return
		if _draw_orig(m.mp_zones()):
			draw_string(font, Vector2(14, size.y - 12), "Eigene Zone anklicken  –  M schließt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(0.85, 0.8, 0.7))
			return
		var zs: Array = m.mp_zones()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for z in zs:
			var o: Vector3 = (z["xf"] as Transform3D).origin
			lo = lo.min(Vector2(o.x, o.z))
			hi = hi.max(Vector2(o.x, o.z))
		var area := Rect2(30, 44, size.x - 60, size.y - 90)
		var span := (hi - lo).max(Vector2(1, 1))
		var sc := minf(area.size.x / span.x, area.size.y / span.y)
		var my_team := int(Net.players.get(Net.my_id(), {}).get("team", -1))
		var chosen := int(Net.players.get(Net.my_id(), {}).get("zone", -1))
		_rects.clear()
		for i in zs.size():
			var o: Vector3 = (zs[i]["xf"] as Transform3D).origin
			var p := area.position + (Vector2(o.x, o.z) - lo) * sc + (area.size - span * sc) * 0.5
			var own := int(Net.zone_owner[i]) if i < Net.zone_owner.size() else int(zs[i]["owner"])
			var col := Color(0.3, 0.45, 0.85) if own == Soldier.TEAM_ALLIED else (Color(0.8, 0.25, 0.2) if own == Soldier.TEAM_AXIS else Color(0.6, 0.6, 0.6))
			var r := 16.0 if (zs[i]["slots"] as Array).size() > 0 else 9.0
			draw_circle(p, r, col)
			if i == chosen:
				draw_arc(p, r + 5, 0, TAU, 24, Color.WHITE, 3)
			if own == my_team and not (zs[i]["slots"] as Array).is_empty():
				draw_arc(p, r + 2, 0, TAU, 24, UIKit.ACCENT, 2)
				_rects[i] = Rect2(p - Vector2(r, r), Vector2(r, r) * 2)
			draw_string(font, p + Vector2(-40, r + 16), String(zs[i]["text"]).substr(0, 18), HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color.WHITE)
		draw_string(font, Vector2(14, size.y - 14), "Eigene Zone anklicken  –  M schließt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.8, 0.7))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in _polys:
				for t in _polys[i]:
					if Geometry2D.point_is_inside_triangle(event.position, t[0], t[1], t[2]):
						Net.request_zone(int(i))
						queue_redraw()
						accept_event()
						return
			for i in _rects:
				if not _polys.has(i) and (_rects[i] as Rect2).has_point(event.position):
					Net.request_zone(int(i))
					queue_redraw()
					accept_event()
					return
