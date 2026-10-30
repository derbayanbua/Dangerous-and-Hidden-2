extends CanvasLayer
## Pausemenü im Einsatz (Esc) 1:1 nach MODELS\main ingame.4ds (Builder hd2.exe 0x6806E3–0x680AF1):
##   Einzelspieler: button00 FORTSETZEN (2511) · button01 MISSION NEU STARTEN (2515) · button02 SPEICHERN (2512) ·
##                  button03 LADEN (2513) · button04 OPTIONEN (2514) · button05 ZURÜCK ZUM HAUPTMENÜ (2516);
##                  button06 (oben) = ÜBERSPRINGEN UND FORTSETZEN (2523) nur während Zwischensequenzen.
##   Mehrspieler:   2517 FORTSETZEN · 2518 SPEICHERN (gesperrt) · 2519 LADEN (gesperrt) · 2520 OPTIONEN ·
##                  2521 SPIELER-SETUP · 2522 ZURÜCK ZUM HAUPTMENÜ; button06 = SPAWN-ZONE FESTLEGEN (2507, Ergänzung).
## SPEICHERN/LADEN öffnen die Spielstandliste (Rahmen MODELS\ingame_info.4ds): Speicherbegrenzung je Einsatz nach
## Schwierigkeitsgrad (Game.saves_left: Schwer 3 Plätze, Sehr schwer keiner – T9526/T6599). Die Gestaltung der Liste
## selbst ist im Original nicht belegt (Annahme: Spiel-Info-Rahmen, Einträge Modus – Mission – Datum).
## F5/F9 = Schnellspeichern/-laden in den Modus-Slot „<Präfix>_quick“ (Original *_quick.sav).

var _root: Control
var _open := false
var _zone_btn: Button
var _setup_btn: Button
var player_setup: Control
var screen: OrigScreen
var page := "main"               ## "main" / "saves"
var saves_mode := "load"         ## Spielstandliste: "load" / "save"
var sel_slot := ""               ## markierter Spielstand ("" = neuer Spielstand beim Speichern)


func open_player_setup() -> void:
	if is_instance_valid(player_setup):
		return
	var ps = load("res://src/ui/player_setup_screen.gd").new()
	ps.name = "PlayerSetup"
	_root.add_child(ps)
	player_setup = ps
	ps.accepted.connect(_close_player_setup)
	ps.back_requested.connect(_close_player_setup)
	ps.open(String(Net.settings.get("map", Game.current_mission_id)), int(Net.rule("respawn_s")))


func _close_player_setup() -> void:
	if is_instance_valid(player_setup):
		player_setup.queue_free()
	player_setup = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.theme()
	_root.visible = false
	add_child(_root)
	screen = OrigScreen.new()
	screen.name = "IngameMenu"
	_root.add_child(screen)
	screen.setup_stage(true)
	_build()


func _t(id: int, fb: String) -> String:
	return SAS.text(id, fb)


func _build() -> void:
	page = "main"
	screen.begin("main ingame")
	if screen.has_layout():
		screen.draw_frames(["shadow03", "obr", "Object01"])
		screen.text_at("text_h&dversion", "Dangerous and Hidden 2 (unofficial) · v%s" % ProjectSettings.get_setting("application/config/version"),
			13, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var p := ColorRect.new()
		p.color = Color(0.72, 0.68, 0.58)
		p.position = Vector2(292, 85)
		p.size = Vector2(440, 532)
		screen.stage.add_child(p)
	var mp := Net.is_online
	var m := Game.current_mission()
	# Knopf oben: Mehrspieler SPAWN-ZONE FESTLEGEN (Ergänzung, sonst Original-Leerplatz)
	var hud = m.get_node_or_null("MpHud") if m else null
	var zones: bool = mp and hud != null and hud.has_method("_has_zones") and hud._has_zones()
	_zone_btn = _btn("button06", Net.tx(2507, "SPAWN-ZONE FESTLEGEN").strip_edges(), _spawn_zone, true, "SpawnZoneButton", 6) if zones else null
	_btn("button00", _t(2517 if mp else 2511, "FORTSETZEN"), close, true, "Continue", 0)
	if mp:
		_btn("button01", _t(2518, "SPEICHERN"), func(): pass, false, "Save", 1)
		_btn("button02", _t(2519, "LADEN"), func(): pass, false, "Load", 2)
		_btn("button03", _t(2520, "OPTIONEN"), _options, true, "Options", 3)
		_setup_btn = _btn("button04", _t(2521, "SPIELER-SETUP"), open_player_setup, not Net.dedicated, "PlayerSetupButton", 4)
		_btn("button05", _t(2522, "ZURÜCK ZUM HAUPTMENÜ"), Game.return_to_menu, true, "MainMenu", 5)
	else:
		_btn("button01", _t(2515, "MISSION NEU STARTEN"), _restart, true, "Restart", 1)
		_btn("button02", _t(2512, "SPEICHERN"), open_saves.bind("save"), Game.can_save() == "" or Game.difficulty() < 4, "Save", 2)
		_btn("button03", _t(2513, "LADEN"), open_saves.bind("load"), not Game.list_saves().is_empty(), "Load", 3)
		_btn("button04", _t(2514, "OPTIONEN"), _options, true, "Options", 4)
		_btn("button05", _t(2516, "ZURÜCK ZUM HAUPTMENÜ"), Game.return_to_menu, true, "MainMenu", 5)
		_setup_btn = null


## Knopf des Modells (button0N mit normal/actived); Ersatzlage, falls der Cache fehlt
func _btn(dummy: String, txt: String, cb: Callable, enabled: bool, node_name: String, row: int) -> Button:
	var y: float = [341.8, 381.7, 422.3, 463.5, 503.1, 543.5, 300.3][row]
	return screen.orig_button(dummy, txt, cb, enabled, node_name, 16, Rect2(330.1, y, 363.8, 35.8))


func _spawn_zone() -> void:
	close()
	var hud = Game.current_mission().get_node_or_null("MpHud") if Game.current_mission() else null
	if hud:
		hud.toggle_zone_map()


func _restart() -> void:
	screen.dialog(_t(2004, "SIND SIE SICHER?"), [[_t(2001, "JA"), func(): Game.start_mission(Game.current_mission_id)],
		[_t(2008, "ANNULLIEREN"), func(): pass]])


# --- Spielstandliste (SPEICHERN / LADEN) -------------------------------------------------------------

func open_saves(mode: String) -> void:
	page = "saves"
	saves_mode = mode
	sel_slot = ""
	if mode == "save":
		var why := Game.can_save()
		if why != "":
			screen.dialog(why, [[_t(2013, "OK"), func(): pass]])
			return
	_build_saves()


## Einträge: Laden = alle Spielstände des Profils; Speichern = Spielstände dieses Einsatzes (Überschreiben) +
## „NEUER SPIELSTAND“
func save_entries() -> Array:
	var all := Game.list_saves()
	if saves_mode == "load":
		return all
	return all.filter(func(e): return String(e["mission"]) == Game.current_mission_id and not String(e["slot"]).ends_with("_quick"))


func _build_saves() -> void:
	screen.begin("main ingame")
	var lay := OrigScreen.load_layout("ingame_info")
	screen.draw_from(lay, ["game_info"])
	var hr := OrigScreen.rect_in(lay, "header", Rect2(81, 117, 865, 28))
	var head := _t(2512 if saves_mode == "save" else 2513, "SPEICHERN")
	var left := Game.saves_left()
	if saves_mode == "save" and left >= 0:
		head += "   –   " + _t(9526, "Es sind %d Speicherplätze frei").replace("%d", str(left))
	screen.label(hr, head, 18, OrigScreen.INK).name = "SavesHeader"
	var tr := OrigScreen.rect_in(lay, "text", Rect2(81, 166, 865, 479))
	var rows := save_entries()
	var y := tr.position.y
	if saves_mode == "save":
		_row(Rect2(tr.position.x, y, tr.size.x, 26), "— " + ("NEUER SPIELSTAND") + " —", "", "SaveNew")
		y += 28.0
	for e in rows:
		if y + 26.0 > tr.end.y - 50.0:
			break
		var txt := "%s  –  %s  –  %s" % [String(e["mode_title"]), String(e["title"]), String(e["timestamp"]).replace("T", " ")]
		_row(Rect2(tr.position.x, y, tr.size.x, 26), txt, String(e["slot"]), "SaveRow_" + String(e["slot"]))
		y += 28.0
	if rows.is_empty() and saves_mode == "load":
		screen.label(Rect2(tr.position.x, y, tr.size.x, 26), _t(2021, "KEIN GESPEICHERTER SPIELSTAND"), 15)
	var main_lay := screen.frames
	var bx := tr.position.x
	var act := _t(2512 if saves_mode == "save" else 2513, "SPEICHERN")
	var shift_a := Vector2(bx - 330.1, tr.end.y - 40.0 - 341.8)
	var shift_b := Vector2(tr.end.x - 363.8 - 330.1, tr.end.y - 40.0 - 341.8)
	screen.button_from(main_lay, "button00", act, _saves_action, saves_mode == "save" or sel_slot != "", "SavesAction", 16,
		Rect2(330.1, 341.8, 363.8, 35.8), shift_a)
	screen.button_from(main_lay, "button01", _t(2506, "ZURÜCK"), _build, true, "SavesBack", 16, Rect2(330.1, 381.7, 363.8, 35.8),
		shift_b - Vector2(0, 381.7 - 341.8))


func _row(r: Rect2, txt: String, slot: String, node_name: String) -> void:
	var b := Button.new()
	b.name = node_name.validate_node_name()
	b.position = r.position
	b.size = r.size
	b.text = txt
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	var cur := slot == sel_slot
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", OrigScreen.INK_RED if cur else OrigScreen.INK)
	b.add_theme_color_override("font_hover_color", OrigScreen.INK_HOVER)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.55, 0.47, 0.33, 0.35) if cur or st == "hover" else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(_pick_row.bind(slot))
	screen.stage.add_child(b)


func _pick_row(slot: String) -> void:
	screen.click_sound()
	sel_slot = slot
	_build_saves()


func _saves_action() -> void:
	if saves_mode == "load":
		if sel_slot != "":
			get_tree().paused = false
			Game.load_game(sel_slot)
		return
	if sel_slot == "":
		_do_save(Game.new_save_slot())
	else:
		screen.dialog(_t(2004, "SIND SIE SICHER?"), [[_t(2001, "JA"), _do_save.bind(sel_slot)], [_t(2008, "ANNULLIEREN"), func(): pass]])


func _do_save(slot: String) -> void:
	if Game.save_game(slot):
		close()
	else:
		screen.dialog(Game.can_save(), [[_t(2013, "OK"), func(): pass]])


# --- Öffnen/Schließen ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("pause_game"):   # B-015: Original PAUSE (P)
		if _open and is_instance_valid(player_setup):
			_close_player_setup()           # Esc schließt zuerst das SPIELER-SETUP (Menü bleibt offen)
		elif _open and page == "saves":
			_build()
		elif _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif Net.is_online:
		return
	elif event.is_action_pressed("quicksave") and not _open:
		Game.save_game(Game.mode_prefix() + "_quick")
	elif event.is_action_pressed("quickload"):
		var q := Game.mode_prefix() + "_quick"
		Game.load_game(q if Game.has_save(q) else "quick")


func is_open() -> bool:
	return _open


func open() -> void:
	var m := Game.current_mission()
	if m and (m.finished or (m.tactical_map and m.tactical_map.is_open)):
		return
	_open = true
	_root.visible = true
	# Mehrspieler: das Spiel läuft weiter (nur Menü, keine Pause; Speichern/Laden/Neustart gesperrt)
	get_tree().paused = not Net.is_online
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_close_player_setup()
	_open = false
	_root.visible = false
	page = "main"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _options() -> void:
	var o = load("res://src/ui/options_menu.gd").new()
	_root.add_child(o)
