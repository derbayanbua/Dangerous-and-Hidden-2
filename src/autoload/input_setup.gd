extends Node
## Definiert alle Eingabeaktionen mit Standardbelegung und lädt/speichert
## Benutzerbelegungen (Sektion "keys" in user://settings.cfg).
## Die Aktionen werden zur Laufzeit registriert, damit Belegungen ohne
## Editor geändert und zurückgesetzt werden können.

const PATH := "user://settings.cfg"

## Aktion -> [Anzeigename, Standard-Event]
## Standard-Event: int = Keycode, "mouse:N" = Maustaste N
var ACTIONS := {
	"move_forward": ["Vorwärts", KEY_W],
	"move_back": ["Rückwärts", KEY_S],
	"move_left": ["Links", KEY_A],
	"move_right": ["Rechts", KEY_D],
	"run": ["Sprinten (halten)", KEY_SHIFT],
	"stance_crouch": ["Hocken", KEY_C],
	"stance_prone": ["Hinlegen", KEY_Z],
	"stance_stand": ["Springen / Klettern / Aufstehen", KEY_SPACE],
	"lean_left": ["Lehnen links", KEY_Q],
	"lean_right": ["Lehnen rechts", KEY_E],
	"fire": ["Feuern", "mouse:1"],
	"aim": ["Zielen", "mouse:2"],
	"reload": ["Nachladen", KEY_R],
	"weapon_1": ["Waffe 1 (Primär)", KEY_1],
	"weapon_2": ["Waffe 2 (Pistole)", KEY_2],
	"weapon_3": ["Waffe 3 (Granate)", KEY_3],
	"binoculars": ["Fernglas", KEY_4],
	"medkit": ["Verbandskasten benutzen", KEY_5],
	"weapon_next": ["Nächste Waffe", "mouse:5"],
	"weapon_prev": ["Vorherige Waffe", "mouse:4"],
	"fire_mode": ["Feuermodus", KEY_B],
	"interact": ["Benutzen", KEY_F],
	"camera_toggle": ["Kamera 1./3. Person", KEY_V],
	"soldier_1": ["Soldat 1", KEY_F1],
	"soldier_2": ["Soldat 2", KEY_F2],
	"soldier_3": ["Soldat 3", KEY_F3],
	"soldier_4": ["Soldat 4", KEY_F4],
	"soldier_next": ["Nächster Soldat", KEY_TAB],
	"order_move": ["Befehl: Dorthin bewegen", KEY_G],
	"order_follow": ["Befehl: Folgen", KEY_H],
	"order_hold": ["Befehl: Position halten", KEY_J],
	"order_roe": ["Befehl: Feuer frei / Feuer halten", KEY_K],
	"order_formation": ["Befehl: Formation wechseln", KEY_L],
	"order_stance": ["Befehl: Haltung wie Anführer", KEY_N],
	"order_grenade": ["Befehl: Granate dorthin werfen", KEY_T],
	"objectives": ["Missionsziele", KEY_O],
	"tactical_map": ["Taktische Karte (Pause)", KEY_M],
	"quicksave": ["Schnellspeichern", KEY_F5],
	"quickload": ["Schnellladen", KEY_F9],
	"pause": ["Pause / Menü", KEY_ESCAPE],
}


func _ready() -> void:
	# Q/E sind Lehnen. Interact auf F wie in vielen Taktik-Shootern.
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.2)
		_add_event(action, ACTIONS[action][1])
	load_bindings()


func _add_event(action: String, spec) -> void:
	var ev := _event_from_spec(spec)
	if ev:
		InputMap.action_add_event(action, ev)


func _event_from_spec(spec) -> InputEvent:
	if spec is int:
		var k := InputEventKey.new()
		k.physical_keycode = spec
		return k
	if spec is String and spec.begins_with("mouse:"):
		var m := InputEventMouseButton.new()
		m.button_index = int(spec.substr(6))
		return m
	return null


func spec_from_event(ev: InputEvent):
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return code
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return null


func display_name(action: String) -> String:
	return ACTIONS[action][0] if ACTIONS.has(action) else action


## Lesbarer Name der aktuellen Belegung, z. B. "F" oder "Maus 1".
func binding_text(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "LMT"
				MOUSE_BUTTON_RIGHT: return "RMT"
				MOUSE_BUTTON_MIDDLE: return "MMT"
				MOUSE_BUTTON_WHEEL_UP: return "Rad hoch"
				MOUSE_BUTTON_WHEEL_DOWN: return "Rad runter"
				_: return "Maus %d" % ev.button_index
	return "—"


func rebind(action: String, ev: InputEvent) -> void:
	var spec = spec_from_event(ev)
	if spec == null:
		return
	InputMap.action_erase_events(action)
	_add_event(action, spec)
	save_bindings()


func reset_defaults() -> void:
	for action: String in ACTIONS:
		InputMap.action_erase_events(action)
		_add_event(action, ACTIONS[action][1])
	save_bindings()


func save_bindings() -> void:
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return   # Tests verändern die Tastenbelegung nicht
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for action: String in ACTIONS:
		var evs := InputMap.action_get_events(action)
		if evs.size() > 0:
			cfg.set_value("keys", action, spec_from_event(evs[0]))
	cfg.save(PATH)


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section("keys"):
		return
	for action: String in cfg.get_section_keys("keys"):
		if not ACTIONS.has(action):
			continue
		var ev := _event_from_spec(cfg.get_value("keys", action))
		if ev:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, ev)
