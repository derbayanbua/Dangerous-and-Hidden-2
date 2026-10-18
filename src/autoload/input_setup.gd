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
	"stance_crouch": ["Hocken / Schleichen", KEY_C],
	"stance_prone": ["Hinlegen / Kriechen", KEY_Z],
	"stance_stand": ["Springen / Klettern / Aufstehen", KEY_SPACE],
	"lean_left": ["Lehnen links", KEY_Q],
	"lean_right": ["Lehnen rechts", KEY_E],
	"fire": ["Feuern", "mouse:1"],
	"aim": ["Zielen", "mouse:2"],
	"reload": ["Nachladen", KEY_R],
	"weapon_1": ["Waffe 1 (Primär)", KEY_1],
	"weapon_2": ["Waffe 2 (Pistole)", KEY_2],
	"weapon_3": ["Waffe 3 (Raketenwerfer)", KEY_3],
	"grenade": ["Granate werfen", KEY_G],
	"binoculars": ["Fernglas", KEY_4],
	# Erste Hilfe: Schnelltaste H (Vorgabe Auftraggeber; das Original hat keine Taste, nur das Inventar –
	# Options.bin „profile“: H unbelegt). „Folgen“ (eigene Direkttaste, kein Original) deshalb auf U.
	"medkit": ["Erste Hilfe (Verbandskasten)", KEY_H],
	"weapon_next": ["Auswahl weiter (Waffen / Sitzplatz)", "mouse:5"],
	"weapon_prev": ["Auswahl zurück (Waffen / Sitzplatz)", "mouse:4"],
	"fire_mode": ["Feuermodus", KEY_B],
	"interact": ["Benutzen", KEY_F],
	"camera_toggle": ["Kamera 1./3. Person", KEY_V],
	"soldier_1": ["Soldat 1", KEY_F1],
	"soldier_2": ["Soldat 2", KEY_F2],
	"soldier_3": ["Soldat 3", KEY_F3],
	"soldier_4": ["Soldat 4", KEY_F4],
	"soldier_next": ["Nächster Soldat", KEY_TAB],
	"order_move": ["Befehl: Dorthin bewegen", KEY_X],
	"order_follow": ["Befehl: Folgen", KEY_U],
	"order_hold": ["Befehl: Position halten", KEY_J],
	"order_roe": ["Befehl: Feuer frei / Feuer halten", KEY_K],
	"order_formation": ["Befehl: Formation wechseln", KEY_L],
	"order_stance": ["Befehl: Haltung wie Anführer", KEY_N],
	"order_grenade": ["Befehl: Granate dorthin werfen", KEY_T],
	# Original-Befehlsmenü (Kategorie BEFEHLE, Texte 2866–2872, Standardbelegung Ziffernblock 0–6)
	"command_all": ["Befehl an alle", KEY_KP_0],
	"command_1": ["Befehl an 1", KEY_KP_1],
	"command_2": ["Befehl an 2", KEY_KP_2],
	"command_3": ["Befehl an 3", KEY_KP_3],
	"command_4": ["Befehl an 4", KEY_KP_4],
	"command_5": ["Befehl an 5", KEY_KP_5],
	"command_6": ["Befehl an 6", KEY_KP_6],
	"objectives": ["Missionsziele", KEY_O],
	# Original-Standardbelegung (Options.bin „profile“): INVENTAR T2847 = I, GEGENST. FALLENL. T2827 = Rücktaste
	"inventory": ["Inventar", KEY_I],
	"drop_item": ["Gegenstand fallenlassen", KEY_BACKSPACE],
	"tactical_map": ["Taktische Karte (Pause)", KEY_M],
	"quicksave": ["Schnellspeichern", KEY_F5],
	"quickload": ["Schnellladen", KEY_F9],
	"pause": ["Pause / Menü", KEY_ESCAPE],
	# Mehrspieler (Original-Standardbelegung aus Options.bin: KONSOLE ^, ALLE INFORMIEREN T, TEAM INFORMIEREN Y)
	"console": ["Konsole", KEY_QUOTELEFT],
	"chat_all": ["Alle informieren (Chat)", KEY_T],
	"chat_team": ["Team informieren (Chat)", KEY_Y],
	"voice_talk": ["Voice-Chat sprechen (halten)", KEY_CAPSLOCK],
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


## Original „STANDARD-EINSTELLUNGEN 2“: alternative Belegung (Pfeiltasten, Strg hocken, Ende liegen)
const PRESET_2 := {
	"move_forward": KEY_UP, "move_back": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT,
	"run": KEY_SHIFT, "stance_crouch": KEY_CTRL, "stance_prone": KEY_END, "stance_stand": KEY_SPACE,
	"lean_left": KEY_DELETE, "lean_right": KEY_PAGEDOWN, "reload": KEY_INSERT, "interact": KEY_ENTER,
}


func apply_preset(n: int) -> void:
	reset_defaults()
	if n == 2:
		for action: String in PRESET_2:
			InputMap.action_erase_events(action)
			_add_event(action, PRESET_2[action])
		save_bindings()


func reset_defaults() -> void:
	for action: String in ACTIONS:
		InputMap.action_erase_events(action)
		_add_event(action, ACTIONS[action][1])
	save_bindings()


## Tastenbelegung gehört wie im Original zum Profil (Options.bin) -> <Profil>/options.cfg
func bindings_path() -> String:
	return Settings.profile_path if Settings.profile_path != "" else PATH


func save_bindings() -> void:
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return   # Tests verändern die Tastenbelegung nicht
	var cfg := ConfigFile.new()
	cfg.load(bindings_path())
	for action: String in ACTIONS:
		var evs := InputMap.action_get_events(action)
		if evs.size() > 0:
			cfg.set_value("keys", action, spec_from_event(evs[0]))
	cfg.set_value("meta", "keys_version", KEYS_VERSION)
	cfg.save(bindings_path())


func load_bindings() -> void:
	# erst Standard, dann die gespeicherte Belegung (Profilwechsel übernimmt nichts vom vorherigen Profil)
	for action: String in ACTIONS:
		InputMap.action_erase_events(action)
		_add_event(action, ACTIONS[action][1])
	var cfg := ConfigFile.new()
	if cfg.load(bindings_path()) != OK or not cfg.has_section("keys"):
		return
	# Belegungsstand 2 (14.10.2026): Erste Hilfe 5 -> H, Folgen H -> U; gespeicherte alte Standards umstellen
	var migrate := int(cfg.get_value("meta", "keys_version", 1)) < KEYS_VERSION
	for action: String in cfg.get_section_keys("keys"):
		if not ACTIONS.has(action):
			continue
		var spec = cfg.get_value("keys", action)
		if migrate and OLD_DEFAULTS.has(action) and spec is int and int(spec) == int(OLD_DEFAULTS[action]):
			continue
		var ev := _event_from_spec(spec)
		if ev:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, ev)


const KEYS_VERSION := 2
const OLD_DEFAULTS := {"medkit": KEY_5, "order_follow": KEY_H}
