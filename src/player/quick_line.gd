extends CanvasLayer
## Eingabezeile im Einzelspieler (Taste der Konsole). Online übernimmt MpHud die Taste.

const _CF := preload("res://src/combat/combat_flags.gd")
const _R_OK := "ok"
const _R_UNKNOWN := "unknown command"
const _R_PARAMS := "invalid parameters"
const _R_NUMBER := "a number required"
const _R_VALUE := "invalid value"

## Gegenstandskürzel → Originalnummer (hd2.exe-Tabelle 0x8442B0)
const ITEM_ALIASES := {
	"PARABELLUM": 0, "ENFIELD": 1, "COLT": 2, "TAISHO": 3, "TOKAREV": 5, "K98": 4, "LEE": 6, "DELISLE": 7,
	"MOSIN": 8, "GARAND": 10, "CARBINE": 11, "ARISAKA": 12, "SPRINGFIELD": 14, "K98OPT": 13, "SPRINGFIELDOPT": 15,
	"ARISAKAOPT": 16, "LEEOPT": 17, "MP40": 18, "ZB26": 19, "THOMPSON": 20, "STENGUN": 21, "STENGUNSIL": 22,
	"SHOTGUN": 23, "SPAGIN": 24, "PPS": 25, "MP44": 26, "BAR": 28, "BRENGUN": 29, "DEGTYAREV": 31,
	"PANZERFAUST": 38, "BAZOOKA": 39, "MEDIKITBIG": 53, "MEDIKIT": 54, "BINOCULARS": 99, "CAMERA": 229,
	"KNIFEGER": 56, "KNIFESAS": 57, "WIRECUTTER": 59, "GRENADE36": 60, "GRENADE69": 62, "GRENADEGER": 61,
	"GRENADEJAP": 63, "CLUMMYBOMB": 66, "EXPLOSIVESBAG": 67, "DYNAMITE": 68, "MINE": 70, "TANKMINE": 71,
	"MAGNETICMINE": 251, "BACKPACKRUS": 95, "BACKPACKGER": 97, "BACKPACKGB1": 101, "BACKPACKGB2": 222,
	"BACKPACKGB3": 228, "AQUALUNG": 231}

## Befehlswörter als Kurzprüfsumme → Kennung
const _WORDS := {
	"9d1896b8d4d32f28": "a", "d1a4be19b3cfc283": "b", "21b50593bf31eacb": "c", "e82b524496c5627a": "d",
	"599f8341fe3e0fd2": "e", "2bda9b4dfbabfdb1": "f", "439c0a5960c90627": "g", "7935f82b4b65c181": "h",
	"a0b967fc60136d2e": "i", "690d4f4c61d713cc": "i", "5c16250fd4bb6980": "j"}

var controller: Node
var _line: LineEdit


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_line = LineEdit.new()
	_line.visible = false
	_line.anchor_left = 0.02
	_line.anchor_right = 0.6
	_line.anchor_top = 0.04
	_line.offset_bottom = 30
	_line.text_submitted.connect(_on_submit)
	add_child(_line)
	_CF.reset()


func _exit_tree() -> void:
	_CF.reset()


func is_open() -> bool:
	return _line != null and _line.visible


func _input(event: InputEvent) -> void:
	if Net.is_online:
		return
	if is_open():
		if event is InputEventKey and event.pressed and ((event as InputEventKey).keycode == KEY_ESCAPE \
				or event.is_action_pressed("console")):
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("console") and not get_tree().paused:
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_line.text = ""
	_line.visible = true
	_line.grab_focus()
	if controller:
		controller.input_enabled = false


func _close() -> void:
	_line.visible = false
	_line.release_focus()
	if controller:
		controller.input_enabled = true


func _on_submit(text: String) -> void:
	_close()
	var r := run(text)
	if r != "":
		Events.say(r, 2.0)


## Führt eine Zeile aus; Rückgabe = Antworttext wie im Original (leer bei leerer Zeile)
func run(text: String) -> String:
	if Net.is_online:
		return ""
	var t := text.strip_edges()
	if t == "":
		return ""
	var sp := t.find(" ")
	var word := (t if sp < 0 else t.substr(0, sp)).to_lower()
	var arg := "" if sp < 0 else t.substr(sp + 1).strip_edges()
	if word == "pos":
		var line := Net.position_report(_active(), Game.current_mission_id)
		print(line)
		return line
	if word == "help":
		return "Console keywords: help, pos"
	var k := String(_WORDS.get(word.sha256_text().substr(0, 16), ""))
	match k:
		"a":
			return _flag("one_hit", arg)
		"b":
			return _flag("steady", arg)
		"c":
			return _hud(arg)
		"d":
			if not arg.is_valid_int():
				return _R_NUMBER
			_CF.keep_mag = int(arg) > 0
			return _R_OK
		"e":
			for m in _members():
				if m.alive:
					m.health = m.max_health
			return _R_OK
		"f":
			var a := _active()
			if a and a.alive:
				a.apply_hit(a.health + 1.0, &"body", null, Vector3.ZERO)
			return _R_OK
		"g":
			return _give(arg)
		"h":
			return _R_OK if arg.is_valid_int() else _R_NUMBER
		"i":
			if arg != "":
				Events.say(arg.trim_prefix("\"").trim_suffix("\""), 3.0)
			return ""
		"j":
			if not arg.is_valid_int():
				return _R_NUMBER
			Settings.mouse_sensitivity = clampf(int(arg), 1, 100) * 0.0024
			return _R_OK
	return _R_UNKNOWN


func _flag(name: String, arg: String) -> String:
	var cur := _CF.one_hit if name == "one_hit" else _CF.steady
	if arg == "":
		return "%d" % int(cur)
	if arg != "0" and arg != "1":
		return _R_VALUE
	if name == "one_hit":
		_CF.one_hit = arg == "1"
	else:
		_CF.steady = arg == "1"
	return _R_OK


func _hud(arg: String) -> String:
	var h: Variant = controller.mission.get("hud") if controller and controller.mission else null
	if arg == "":
		return "%d" % (0 if h == null or h.visible else 1)
	if arg != "0" and arg != "1":
		return _R_VALUE
	if h is CanvasItem or h is CanvasLayer:
		h.visible = arg == "0"
	return _R_OK


func _give(arg: String) -> String:
	var nm := arg.trim_prefix("\"").trim_suffix("\"").strip_edges().to_upper()
	if not ITEM_ALIASES.has(nm):
		return _R_OK
	var s := _active()
	if s == null or not s.alive:
		return _R_OK
	var id := int(ITEM_ALIASES[nm])
	OrigInteractive.give_item(s, id)
	var ammo := SAS.ammo_of(id)
	if ammo >= 0:
		for i in 6:
			OrigInteractive.give_item(s, ammo)
	return _R_OK


func _active() -> Soldier:
	return controller.active if controller and is_instance_valid(controller.active) else null


func _members() -> Array:
	if controller and controller.squad:
		return controller.squad.members
	return []
