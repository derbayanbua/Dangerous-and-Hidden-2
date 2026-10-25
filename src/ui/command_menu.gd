class_name CommandMenu
extends CanvasLayer
## Original-Soldaten-Befehlsmenü (Einzelspieler). Öffnen wie im Original mit „BEFEHL AN ALLE“ (Ziffernblock 0)
## bzw. „BEFEHL AN 1…6“ (Ziffernblock 1–6, Befehl an den Soldaten auf Teamplatz 1…6).
## Struktur, Reihenfolge, Texte und Aktionscodes aus hd2.exe: Einzelspieler-Tabelle 0x83B610 (Auswahl 0x4BF442),
## Aufbau/Ausgrauen 0x4BFFE0, Kontext-Untermenü „Aktion“ 0x4BF670, Anzeige 0x4C0370, Eingabe 0x4C0760,
## Ausführung 0x4C0600/0x4C0990. Sprachausgabe: TABLES\speech.set (Sprachsatz je Teamplatz „English #1…4“).
## Bedienung wie im Original: Ziffer 1–9 = Eintrag 1–9, 0 = „Abbrechen“ bzw. „Vorherige Befehle“; Mausrad
## markiert (ausgegraute Einträge werden übersprungen), Linksklick führt den markierten Eintrag aus.
## Nach einem Befehl schließt sich das Menü. Belege und Annahmen: docs/re_notes_commands.md

const MAIN := 50
const A_CANCEL := 70           ## „Abbrechen“ (schließt)
const A_BACK := 71             ## „Vorherige Befehle“ (zurück ins Hauptmenü)
const A_GREY := 72             ## ausgegraut (Original 0x48)

## Menü-ID -> 10 Einträge [Text-ID, Aktion] (hd2.exe 0x83B610 ff., Einzelspieler; −1 = leere Zeile).
## Aktionen 51…59 öffnen das Untermenü gleicher ID, 0…34 sind Befehlscodes (ungerade = leise Variante).
const MENUS := {
	50: [[7200, 51], [7201, 52], [7202, 53], [7203, 54], [7204, 55], [7205, 56], [7206, 57], [7207, 58], [-1, -1], [7274, 70]],
	51: [[7210, 0], [7211, 4], [7215, 10], [7212, 2], [7213, 6], [7214, 8], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	52: [[7232, 16], [7231, 14], [7230, 12], [7233, 18], [7234, 19], [7235, 20], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	53: [[-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	54: [[7220, 1], [7221, 5], [7225, 11], [7222, 3], [7223, 7], [7224, 9], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	55: [[7242, 17], [7241, 15], [7240, 13], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	56: [[-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	57: [[7250, 23], [7251, 21], [7252, 22], [7253, 24], [7254, 25], [7255, 26], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
	58: [[7260, 27], [7261, 28], [7262, 29], [7263, 30], [7264, 31], [7265, 32], [-1, -1], [-1, -1], [-1, -1], [7275, 71]],
}
const QUIET_MENUS := [54, 55, 56]   ## Schl. Beweg., Stiller Angriff, Stille Aktion

## Untermenü „Aktion“: Aktion = 100 + Original-Aktionsnummer (Bauer 0x4BF640 addiert 0x64; 0x32 → ausgegraut).
## Vollständige Tabelle nach Akteurtyp des Ziels: hd2.exe 0x4BF670 (B-019, re_notes_commands.md §4).
const ACT_LOCK := 100         ## 7019 Abschließen (Schlüssel)
const ACT_UNLOCK := 101       ## 7020 Aufschließen (Schlüssel)
const ACT_DISARM := 102       ## 7021 Entschärfen (Mine, Typ 2)
const ACT_USE := 103          ## 7022 Benutzen
const ACT_PLANT := 104        ## 7047 Sprengstoff anbringen
const ACT_STOP := 105         ## 7024 Beenden
const ACT_AMMO := 106         ## 7053 Munition nehmen / 7025 Nehmen
const ACT_PICK := 114         ## 7033 Schloss aufbrechen
const ACT_HEAL := 115         ## 7034 Erste Hilfe
const ACT_CUTTER := 116       ## 7035 Benutze Drahtschneider
const ACT_GREN_ROOM := 118    ## 7037 Granate in den Raum
const ACT_CAPTURE := 119      ## 7038 Gefangennehmen
const ACT_CLEAR := 121        ## 7040 Hineing. & räumen
const ACT_DESTROY := 122      ## 7042 Zerstören
const ACT_SEARCH := 123       ## 7043 Suchen & Mun. sammeln
const ACT_UNIFORM := 124      ## 7044 Uniform benutzen
const ACT_KILL := 125         ## 7045 Töten
const ACT_SILENT_KILL := 126  ## 7046 Leise töten
const ACT_OPEN := 127         ## 7023 Öffnen
const ACT_CLOSE := 128        ## 7041 Schließen
const ACT_ITEMS := 133        ## 7050 Gegenstände nehmen
const ACT_ITEM_USE := 134     ## Gegenstand am Objekt benutzen (Typ 23, Text aus dem Akteur)
const ACT_DEFUSE := 138       ## 7021 Entschärfen (Sprengplatz, Typ 22)
const ACT_PHOTO := 103        ## 7018 Foto machen = Aktion 3 (wie Benutzen)
const ITEM_CAMERA := 229      ## Fotoapparat (0x4BF670 Fall 0xF: Gegenstand 0xE5)
const ITEM_CUTTER := -1       ## Drahtschneider: Gegenstand im Original über 0x5A7ED0 geprüft [P]

## Befehlscode -> Sprach-Ereignis in speech.set (Zuordnung über die Satznamen, s. re_notes_commands.md)
const SPEECH_EVENT := {
	0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 0x7D, 11: 0x7E,
	12: 10, 13: 11, 14: 12, 15: 13, 16: 14, 17: 15, 18: 16, 19: 18, 20: 20,
	21: 22, 22: 24, 23: 26, 24: 28, 25: 30, 26: 32, 27: 34, 28: 36, 29: 38, 30: 40, 31: 42, 32: 44,
	ACT_USE: 0x34, ACT_PLANT: 0x36, ACT_AMMO: 0x3A, ACT_PICK: 0x40, ACT_HEAL: 0x42,
	ACT_OPEN: 0x58, ACT_CLOSE: 0x5A, ACT_DEFUSE: 0x32, ACT_DISARM: 0x32, ACT_UNLOCK: 0x30,
	ACT_SEARCH: 0x3A, ACT_ITEMS: 0x3A,
}
const EV_ACK := 0x7F          ## „Klar doch!“ / „Verlass dich auf mich!“ / „O. K.!“ (leise +1)
const EV_NEGATIVE := 0x68     ## „Negativ“ / „Das kann ich nicht“ … (leise +1)

## Annahmen (nicht aus dem Original belegt)
const ADVANCE_DIST := 15.0    ## „Vorwärts“: so weit vor den Anführer
const SUPPRESS_TIME := 6.0    ## „Deckungsfeuer“: Dauer
const SHOUT_RADIUS := 25.0    ## Hörweite eines gerufenen Befehls
const WHISPER_RADIUS := 4.0   ## Hörweite eines geflüsterten Befehls
const GRENADE_RANGE := 40.0   ## Original 0x4C09F1: Zielpunkt höchstens 40 m (0x42200000)
const POINT_RANGE := 150.0    ## „Dorthin“/„Deckungsfeuer“/„Raketenwerfer“: Fadenkreuzpunkt (Original: Sichtweite)

## Eigene Ersatzbeschriftungen, falls orig_cache/texts_german.json fehlt
const FALLBACK := {
	7200: "Bewegung", 7201: "Angriff", 7202: "Aktion", 7203: "Leise Bewegung", 7204: "Leiser Angriff",
	7205: "Leise Aktion", 7206: "Formation", 7207: "Taktik", 7210: "Mir nach", 7211: "Vorrücken", 7212: "Halt",
	7213: "Stellung halten", 7214: "Deckung", 7215: "Dorthin", 7220: "Mir nach", 7221: "Vorrücken", 7222: "Halt",
	7223: "Stellung halten", 7224: "Deckung", 7225: "Dorthin", 7230: "Feuer auf Befehl", 7231: "Feuer halten",
	7232: "Feuer frei", 7233: "Feuerschutz", 7234: "Granate", 7235: "Panzerabwehrwaffe", 7240: "Feuer auf Befehl",
	7241: "Feuer halten", 7242: "Feuer frei", 7250: "Keil", 7251: "Linie", 7252: "Reihe", 7253: "Enger",
	7254: "Weiter auseinander", 7255: "Sammeln", 7260: "Zeichen 1", 7261: "Zeichen 2", 7262: "Anhalten",
	7263: "Fortsetzen", 7264: "Plan löschen", 7265: "Zurück zur Formation", 7270: "Befehle", 7271: "Befehle - ",
	7274: "Schließen", 7275: "Zurück", 7276: "Ganzer Trupp", 7018: "Fotografieren", 7021: "Entschärfen",
	7022: "Benutzen", 7023: "Öffnen", 7033: "Schloss knacken", 7034: "Verband anlegen", 7037: "Granate hinein",
	7040: "Raum säubern", 7041: "Schließen", 7047: "Ladung anbringen", 7053: "Munition",
	7019: "Abschließen", 7020: "Aufschließen", 7024: "Beenden", 7025: "Nehmen", 7035: "Drahtschere",
	7038: "Gefangen nehmen", 7042: "Zerstören", 7043: "Durchsuchen", 7044: "Uniform", 7045: "Töten",
	7046: "Leise töten", 7050: "Gegenstände",
}

static var _texts := {}
static var _voices := {}
static var _loaded := false

var controller: PlayerController
var is_open := false
var menu_id := MAIN
var target_index := -1               ## −1 = alle, sonst Teamplatz (0-basiert)
var highlight := -1
var entries: Array = []              ## aktuelle 10 Einträge [Text-ID, Aktion] (nach Ausgrauen/Kontext)
var context: Node3D = null           ## Ziel des Untermenüs „Aktion“
var context_override: Node3D = null  ## Tests: Ziel statt Fadenkreuz
var point_override := Vector3.INF    ## Tests: Zielpunkt statt Fadenkreuz
var last_command := -1
var last_speech: Array = []          ## [Soldat, Sound-ID] des zuletzt gesprochenen Satzes
var last_order_voice := -1           ## Sound-ID der letzten Befehlsansage des Anführers
var _panel: PanelContainer
var _box: VBoxContainer


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_texts = Settings.orig_texts()   # B-007: gewählte Sprachfassung (gemeinsame Instanz)
	var c = LsRuntime._read_json(OrigLevel.cache_root() + "/commands.json")
	if typeof(c) == TYPE_DICTIONARY:
		_voices = c.get("voices", {})


static func text(id: int) -> String:
	_load()
	var s := String(_texts.get(str(id), ""))
	return s if s != "" else String(FALLBACK.get(id, ""))


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_load()


func _squad() -> SquadManager:
	return controller.squad if controller else null


# --- Öffnen / Schließen -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Net.is_online or controller == null or not controller.input_enabled:
		return
	if event.is_action_pressed("command_all"):
		open_for(-1)
	else:
		for i in 6:
			if event.is_action_pressed("command_%d" % (i + 1)):
				open_for(i)
				break


## Menü für alle (−1) bzw. den Soldaten auf Teamplatz i öffnen (Hauptmenü).
func open_for(i: int) -> bool:
	var sq := _squad()
	if sq == null or not is_instance_valid(controller.active) or not controller.active.alive:
		return false
	if i >= 0:
		if i >= sq.members.size() or not sq.members[i].alive or sq.members[i] == sq.leader():
			return false
	elif sq.alive_members().size() < 2:
		return false
	controller.close_selection()
	target_index = i
	menu_id = MAIN
	is_open = true
	_rebuild()
	get_viewport().set_input_as_handled()
	return true


func close() -> void:
	is_open = false
	if _panel:
		_panel.visible = false


func _process(_delta: float) -> void:
	if is_open:
		if controller == null or not is_instance_valid(controller.active) or not controller.active.alive:
			close()
			return
		controller._suppress_fire = true     # Klicks im Menü feuern nicht


# --- Eingabe (wie Original 0x4C0760) -------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_0 and k <= KEY_9:
			press_digit(k - KEY_0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				step(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				step(1)
			MOUSE_BUTTON_LEFT:
				confirm()
			_:
				return
		get_viewport().set_input_as_handled()


## Ziffer 1–9 = Eintrag 1–9, 0 = zehnter Eintrag (Abbrechen / Vorherige Befehle).
func press_digit(d: int) -> void:
	var idx: int = 9 if d == 0 else d - 1
	if _selectable(idx):
		highlight = idx
		activate(idx)


func step(dir: int) -> void:
	var i := highlight
	for _k in 10:
		i += dir
		if i < 0 or i > 9:
			return            # Original: am Rand stehen bleiben
		if _selectable(i):
			highlight = i
			_redraw()
			return


func confirm() -> void:
	if highlight >= 0 and _selectable(highlight):
		activate(highlight)


func _selectable(i: int) -> bool:
	if i < 0 or i >= entries.size():
		return false
	var a: int = entries[i][1]
	return a != -1 and a != A_GREY


func activate(i: int) -> void:
	var a: int = entries[i][1]
	if a >= 51 and a <= 59:
		menu_id = a
		_rebuild()
	elif a == A_CANCEL:
		close()
	elif a == A_BACK:
		menu_id = MAIN
		_rebuild()
	elif a >= 0 and a != A_GREY:
		execute(a, menu_id in QUIET_MENUS)
		close()


# --- Aufbau und Ausgrauen (Original 0x4BFFE0) ----------------------------------

func recipients() -> Array[Soldier]:
	var sq := _squad()
	var r: Array[Soldier] = []
	if sq == null:
		return r
	if target_index >= 0:
		if target_index < sq.members.size() and sq.members[target_index].alive and sq.members[target_index] != sq.leader():
			r.append(sq.members[target_index])
		return r
	return sq.order_recipients()    # markierte Kameraden (Einzelauswahl 1–4), sonst alle


func _rebuild() -> void:
	entries = []
	for e in MENUS.get(menu_id, MENUS[MAIN]):
		entries.append([int(e[0]), int(e[1])])
	var sq := _squad()
	var rec := recipients()
	match menu_id:
		MAIN:
			context = find_context()
			# 0x4C10F0 Fall 3: ein Mensch ist kein Ziel für sich selbst (Befehl an genau diesen Soldaten)
			if context is Soldier and target_index >= 0 and rec.has(context as Soldier):
				context = null
			if context == null:
				_grey(2)
				_grey(5)
			# Vorgabe Auftraggeber (B-012, nicht aus 0x4BFFE0 belegt): „Stiller Angriff“/„Stille Aktion“ nur, wenn
			# mindestens ein Empfänger eine Schalldämpferwaffe (Primär oder Pistole) trägt.
			var quiet_ok := false
			for s in rec:
				if has_silenced(s):
					quiet_ok = true
			if not quiet_ok:
				_grey(4)
				_grey(5)
			var plans := 0
			for s in rec:
				if sq.has_plan(s):
					plans += 1
			if target_index >= 0:
				if plans > 0:
					for g in [0, 1, 2, 3, 4, 5, 6, 8]:
						_grey(g)
				else:
					for g in [6, 7, 8]:
						_grey(g)
			else:
				if rec.size() > 0 and plans == rec.size():
					for g in [0, 1, 2, 3, 4, 5, 6, 8]:
						_grey(g)
				elif plans == 0:
					_grey(7)
				_grey(8)
				if controller.active.vehicle != null:
					_grey(6)          # Original: Formationstyp 13 [P] – im Fahrzeug keine Formation
		53, 56:
			_fill_actions()
		57:
			match sq.formation:
				SquadManager.Formation.WEDGE: _grey(0)
				SquadManager.Formation.LINE: _grey(1)
				SquadManager.Formation.COLUMN: _grey(2)
			# 0x4BFFE0 Fall 0x39: kleinste Stufe → „Enge Formation“ grau, sonst größte → „Formation ausweiten“ grau
			if sq.at_min_spacing():
				_grey(3)
			elif sq.at_max_spacing():
				_grey(4)
	highlight = -1
	for i in 10:
		if _selectable(i):
			highlight = i
			break
	_redraw()


func _grey(i: int) -> void:
	if entries[i][0] != -1:
		entries[i][1] = A_GREY


func _put(i: int, txt: int, action: int, enabled := true) -> void:
	entries[i] = [txt, action if enabled else A_GREY]


## Untermenü „Aktion“ nach dem Ziel unter dem Fadenkreuz (Original-Bauer 0x4BF670, Einträge/Plätze/Bedingungen wie dort;
## „an einen“ prüft Gegenstände beim Empfänger 0x5A78F0, „an alle“ im ganzen Trupp 0x45E9A0).
func _fill_actions() -> void:
	var ctx := context
	var lead := controller.active
	if not is_instance_valid(ctx):
		return
	var single := target_index >= 0
	if ctx is Soldier:
		var s := ctx as Soldier
		var eb := _enemy_brain(s)
		if not s.alive:
			# Fall 3, Leiche: Nehmen (Tragen – im Nachbau nicht vorhanden, ausgegraut [D]), Suchen & Mun. sammeln,
			# Uniform benutzen grau (Original), Gegenstände nehmen
			_put(0, 7025, ACT_AMMO, false)
			_put(1, 7043, ACT_SEARCH, _loot_of(s) != null)
			_put(2, 7044, ACT_UNIFORM, false)
			_put(3, 7050, ACT_ITEMS, _loot_of(s) != null)
		elif eb and eb.captured:
			# 0x5A6380 = gefangen: Töten, Suchen, Uniform (grau nach Abgabe +0x1A5), Gegenstände nehmen
			_put(0, 7045, ACT_KILL)
			_put(1, 7043, ACT_SEARCH)
			_put(2, 7044, ACT_UNIFORM, not eb.uniform_taken)
			_put(3, 7050, ACT_ITEMS)
		elif s.team != lead.team:
			# Gegner: Töten, Leise töten, Gefangennehmen nur wenn er sich ergibt (0x5A6450)
			_put(0, 7045, ACT_KILL)
			_put(1, 7046, ACT_SILENT_KILL)
			_put(2, 7038, ACT_CAPTURE, eb != null and eb.surrendered)
		else:
			# Kamerad: Erste Hilfe (Verbandskasten beim Empfänger bzw. im Trupp), Gegenstände nehmen
			var med := false
			for r in recipients():
				if r != s and r.medkits > 0:
					med = true
			_put(0, 7034, ACT_HEAL, med)
			_put(1, 7050, ACT_ITEMS)
	elif ctx is Dog:
		_put(0, 7045, ACT_KILL)                        # Fall 0x1E
	elif ctx is Door or ctx is OrigInteractive.OrigDoor:
		var locked: bool = ctx.get("locked") == true
		var key: int = int(ctx.get("key_item")) if ctx is OrigInteractive.OrigDoor else -1
		if not locked:
			# Fall 6, offen/zu ist im Original keine Bedingung
			_put(0, 7023, ACT_OPEN)
			_put(1, 7041, ACT_CLOSE)
			_put(2, 7040, ACT_CLEAR)
			_put(3, 7037, ACT_GREN_ROOM, _any_rec(func(r): return _has_grenade(r)))
			_put(4, 7019, ACT_LOCK, key >= 0 and not bool(ctx.get("is_open")) and _any_rec(func(r): return OrigInteractive.has_item(r, key)))
		else:
			_put(0, 7023, ACT_OPEN, false)
			_put(1, 7041, ACT_CLOSE, false)
			_put(2, 7040, ACT_CLEAR, false)
			_put(3, 7037, ACT_GREN_ROOM, false)
			_put(4, 7033, ACT_PICK, bool(ctx.get("lockpickable")))
			_put(5, 7020, ACT_UNLOCK, key >= 0 and _any_rec(func(r): return OrigInteractive.has_item(r, key)))
	elif ctx is OrigInteractive.OrigExplosive:
		# Fall 0x16: Zustand 0 frei → Anbringen (mit Gegenstand), 1 platziert → Entschärfen, sonst beide grau
		var st := int(ctx.get("state"))
		var e := ctx as OrigInteractive.OrigExplosive
		_put(0, 7047, ACT_PLANT, st == 0 and _any_rec(func(r): return e.host.allowed(r, e.required_item)))
		_put(1, 7021, ACT_DEFUSE, st == 1)
	elif ctx is PlacedCharge.DefuseSpot:
		_put(0, 7021, ACT_DISARM, (ctx as Interactable).enabled)   # Fall 2 (Mine): Entschärfen
		_put(1, 7042, ACT_DESTROY)
	elif ctx is OrigInteractive.OrigCrate or ctx is Pickups.AmmoCrate:
		_put(0, 7053, ACT_AMMO, _any_rec(func(r): return (ctx as Interactable).can_interact(r)))   # Fall 9
	elif ctx is OrigInteractive.OrigPlace:
		var pl := ctx as OrigInteractive.OrigPlace
		if pl.consume:
			_put(0, 7051, ACT_USE, pl.state == 0 and _any_rec(func(r): return pl.host.allowed(r, pl.item)))
		else:
			_put(0, 7018, ACT_PHOTO, pl.state == 0 and _any_rec(func(r): return pl.host.allowed(r, ITEM_CAMERA)))   # Fall 0xF
	elif ctx is OrigInteractive.OrigWorldItem or ctx is Pickups.Item:
		_put(0, 7025, ACT_AMMO, (ctx as Interactable).enabled)     # Fall 0xB: Nehmen
	elif ctx is OrigInteractive.OrigDestructible:
		_put(0, 7042, ACT_DESTROY, not bool(ctx.get("destroyed")))  # Fall 0x19
	elif ctx is Interactable:
		_put(0, 7022, ACT_USE, _any_rec(func(r): return (ctx as Interactable).can_interact(r)))   # Fall 7/8/0xD/0x1C


## Trifft die Bedingung auf einen Empfänger zu („an einen“: der Soldat, „an alle“: irgendwer im Trupp)?
func _any_rec(f: Callable) -> bool:
	for r in recipients():
		if f.call(r):
			return true
	return false


func _enemy_brain(s: Soldier) -> EnemyBrain:
	for c in s.get_children():
		if c is EnemyBrain:
			return c
	return null


## Durchsuchbare Leiche (Pickups.Loot am Toten)
func _loot_of(s: Soldier) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Pickups.Loot and (n as Pickups.Loot).corpse == s and (n as Interactable).can_interact(s if s.alive else controller.active):
			return n
	return null


## Ziel für „Aktion“ (Original 0x4C10F0: Akteurtypen 2/6/7/8/9/0xB/0xD/0xF/0x14–0x17/0x1C/0x1E/0x23 immer, Menschen außer dem
## Empfänger selbst, Fahrzeuge/Zerstörbares je nach Zustand): Objekt bzw. Mensch/Hund am Fadenkreuzpunkt (≤ 60 m).
func find_context() -> Node3D:
	if is_instance_valid(context_override):
		return context_override
	if controller.rig == null:
		return null
	var p := controller.rig.crosshair_point(60.0)
	var best: Node3D = null
	var best_d := 2.0
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.enabled or not it.is_visible_in_tree():
			continue
		if it is Pickups.Loot or it is EnemyBrain.CaptureAction:
			continue        # gehören zum Menschen (unten)
		var d := it.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = it
	for n in get_tree().get_nodes_in_group("destructibles"):
		if n is OrigInteractive.OrigDestructible and not bool(n.get("destroyed")):
			var dd := (n as Node3D).global_position.distance_to(p)
			if dd < best_d:
				best_d = dd
				best = n
	# Menschen (lebend oder tot) und Hunde: Abstand des Punkts zur Körperachse; Mensch geht vor (Fangradius 1 m)
	var body_best := 1.0
	var body: Node3D = null
	for n in get_tree().get_nodes_in_group("soldiers") + get_tree().get_nodes_in_group("dogs"):
		var b := n as Node3D
		if b == null or b == controller.active or not b.is_visible_in_tree():
			continue
		var feet := b.global_position
		var top := feet + Vector3.UP * (1.7 if (b is Soldier and (b as Soldier).alive) else 0.5)
		var dist := Geometry3D.get_closest_point_to_segment(p, feet, top).distance_to(p)
		if dist < body_best:
			body_best = dist
			body = b
	if body:
		return body
	return best


func _point(range_m: float) -> Vector3:
	if point_override.is_finite():
		return point_override
	return controller.rig.crosshair_point(range_m)


# --- Ausführung (Original 0x4C0990 → Befehlsnachricht an die Soldaten-KI) --------

func execute(code: int, quiet: bool) -> void:
	var sq := _squad()
	var lead := controller.active
	var rec := recipients()
	# Original 0x456020: Befehle 0…20 und 26 gehen nur an Empfänger ohne Taktik-Plan (0x5A5F00 = 0),
	# Taktik-Befehle 27…32 nur an Empfänger mit Plan; Formation 21…25 gilt für das Team.
	if code <= 20 or code == 26:
		var free: Array[Soldier] = []
		for s in rec:
			if not sq.has_plan(s):
				free.append(s)
		rec = free
	last_command = code
	var ok := not rec.is_empty()
	var responder: Soldier = rec[0] if not rec.is_empty() else null
	match code:
		0, 1:
			for s in rec:
				sq.brain_of(s).clear_tasks()
				sq.brain_of(s).set_order(SquadBrain.Order.FOLLOW, Vector3.ZERO, quiet)
		2, 3, 6, 7:
			for s in rec:
				var b := sq.brain_of(s)
				b.clear_tasks()
				b.set_order(SquadBrain.Order.HOLD, Vector3.ZERO, quiet)
				b.strict_hold = code >= 6
		4, 5:
			_move_fanned(rec, lead.global_position + lead.forward() * ADVANCE_DIST, quiet)
		8, 9:
			for s in rec:
				sq.brain_of(s).clear_tasks()
				sq.brain_of(s).set_order(SquadBrain.Order.COVER, Vector3.ZERO, quiet)
		10, 11:
			_move_fanned(rec, _point(POINT_RANGE), quiet)
		12, 13, 14, 15, 16, 17:
			var roe := SquadBrain.ROE.ON_MY_LEAD
			if code >= 16:
				roe = SquadBrain.ROE.FIRE_AT_WILL
			elif code >= 14:
				roe = SquadBrain.ROE.HOLD_FIRE
			for s in rec:
				sq.brain_of(s).roe = roe
		18:
			var sp := _point(POINT_RANGE)
			for s in rec:
				var b2 := sq.brain_of(s)
				b2.clear_tasks()
				b2.suppress_point = sp
				b2.suppress_time = SUPPRESS_TIME
		19:
			var gp := _point(GRENADE_RANGE)
			responder = null
			if target_index >= 0:
				if not rec.is_empty() and _has_grenade(rec[0]):
					sq.brain_of(rec[0]).grenade_target = gp
					responder = rec[0]
			else:
				responder = sq.order_grenade(gp)
			ok = responder != null
			if not ok and not rec.is_empty():
				responder = rec[0]
		20:
			var lp := _point(POINT_RANGE)
			var shooter: Soldier = null
			var best := INF
			for s in rec:
				var w: Weapon = s.weapons[WeaponData.Slot.LAUNCHER] if s.weapons.size() > WeaponData.Slot.LAUNCHER else null
				if w and w.total_ammo() > 0 and s.global_position.distance_to(lp) < best:
					best = s.global_position.distance_to(lp)
					shooter = s
			ok = shooter != null and sq.brain_of(shooter).start_launcher(lp)
			if ok:
				responder = shooter
		21:
			sq.set_formation(SquadManager.Formation.LINE)
		22:
			sq.set_formation(SquadManager.Formation.COLUMN)
		23:
			sq.set_formation(SquadManager.Formation.WEDGE)
		24:
			ok = sq.change_spacing(-SquadManager.SPACING_STEP)
		25:
			ok = sq.change_spacing(SquadManager.SPACING_STEP)
		26:
			for s in rec:
				sq.brain_of(s).clear_tasks()
				sq.brain_of(s).set_order(SquadBrain.Order.FOLLOW)
		27, 28:
			# Signal 1/2: an Signal-Wegpunkten der taktischen Karte wartende Soldaten laufen weiter
			var tm = Game.current_mission().get("tactical_map") if Game.current_mission() else null
			if tm and tm.has_method("send_signal"):
				tm.send_signal(1 if code == 27 else 2)
		29, 30:
			for s in rec:
				if sq.has_plan(s):
					sq.brain_of(s).plan_paused = code == 29
					if code == 29:
						sq.brain_of(s).stop_moving()
		31:
			for s in rec:
				if sq.has_plan(s):
					sq.brain_of(s).set_order(SquadBrain.Order.HOLD)
		32:
			for s in rec:
				sq.brain_of(s).clear_tasks()
				sq.brain_of(s).set_order(SquadBrain.Order.FOLLOW)
		_:
			if code >= 100:
				responder = _start_action(code, rec, quiet)
				ok = responder != null
	sq.orders_changed.emit()
	Events.squad_order_issued.emit(text(_label_of(code)))
	# Ansage des Anführers (laut gerufen bzw. geflüstert) und Antwort des Empfängers
	var ev: int = SPEECH_EVENT.get(code, -1)
	if ev >= 0 and code >= 100 and quiet:
		ev += 1
	var said := speak(lead, ev, text(_label_of(code)))
	last_order_voice = int(last_speech[1]) if last_speech.size() == 2 and last_speech[0] == lead else -1
	Events.emit_noise(lead.global_position, WHISPER_RADIUS if quiet else SHOUT_RADIUS, lead, lead.team, &"voice")
	if responder:
		var reply: int = (EV_ACK if ok else EV_NEGATIVE) + (1 if quiet else 0)
		var delay: float = 0.6 + (said if said > 0.0 else 0.8)
		get_tree().create_timer(delay, false).timeout.connect(func():
			if is_instance_valid(responder) and responder.alive:
				speak(responder, reply, "Verstanden." if ok else "Negativ."))


func _label_of(code: int) -> int:
	for m in MENUS:
		for e in MENUS[m]:
			if int(e[1]) == code and int(e[0]) > 0:
				return int(e[0])
	for e in entries:
		if int(e[1]) == code:
			return int(e[0])
	return -1


## Trägt der Soldat eine Schalldämpferwaffe (De Lisle, Sten Mk II S, Welrod, K98k/MP 40 SD …)?
## Merkmal: Klangklasse „silenced_*“ bzw. Original-Geräuschweite < 20 m (wie BotTraits).
static func has_silenced(s: Soldier) -> bool:
	if s == null:
		return false
	for slot in [WeaponData.Slot.PRIMARY, WeaponData.Slot.SIDEARM]:
		var w: Weapon = s.weapons[slot] if s.weapons.size() > slot else null
		if w and w.data and (String(w.data.sound).begins_with("silenced") or w.data.noise_radius < 20.0):
			return true
	return false


func _has_grenade(s: Soldier) -> bool:
	if s.weapons.size() <= WeaponData.Slot.GRENADE:
		return false
	var g := s.weapons[WeaponData.Slot.GRENADE]
	return g != null and g.total_ammo() > 0


func _move_fanned(rec: Array[Soldier], p: Vector3, quiet: bool) -> void:
	var sq := _squad()
	var i := 0
	for s in rec:
		var ang := TAU * i / 4.0
		var b := sq.brain_of(s)
		b.clear_tasks()
		b.set_order(SquadBrain.Order.MOVE, p + Vector3(cos(ang), 0, sin(ang)) * (1.5 if i > 0 else 0.0), quiet)
		i += 1


## Aktion: Befehl an einen Soldaten bzw. (an alle) an den nächststehenden Empfänger.
func _start_action(code: int, rec: Array[Soldier], quiet: bool) -> Soldier:
	if not is_instance_valid(context) or rec.is_empty():
		return null
	var who: Soldier = null
	var best := INF
	for s in rec:
		if s == context:
			continue
		# nur wer die Aktion auch ausführen kann (Verbandskasten, Granate, Schlüssel)
		if code == ACT_HEAL and s.medkits <= 0:
			continue
		if code == ACT_GREN_ROOM and not _has_grenade(s):
			continue
		if (code == ACT_LOCK or code == ACT_UNLOCK) and not OrigInteractive.has_item(s, int(context.get("key_item"))):
			continue
		var d := s.global_position.distance_to(context.global_position)
		if d < best:
			best = d
			who = s
	if who == null:
		return null
	var b := _squad().brain_of(who)
	b.clear_tasks()
	if b.order == SquadBrain.Order.FOLLOW:
		b.set_order(SquadBrain.Order.HOLD, Vector3.ZERO, quiet)    # danach dort bleiben [E]
	b.quiet = quiet
	b.action_target = context
	b.action_kind = ACTION_KIND.get(code, "use")
	if code == ACT_DESTROY:
		# Zerstören: Feuer auf das Ziel (Ersatz [E]; Original-Ausführung nicht disassembliert)
		b.action_target = null
		b.action_kind = ""
		b.suppress_point = context.global_position
		b.suppress_time = SUPPRESS_TIME
	return who


## Befehlscode der Aktion -> Ausführungsart in SquadBrain._do_action
const ACTION_KIND := {
	ACT_HEAL: "heal", ACT_OPEN: "open", ACT_CLOSE: "close", ACT_LOCK: "lock", ACT_UNLOCK: "unlock",
	ACT_PICK: "use", ACT_PLANT: "use", ACT_DEFUSE: "use", ACT_DISARM: "use", ACT_AMMO: "use", ACT_USE: "use",
	ACT_CAPTURE: "capture", ACT_SEARCH: "search", ACT_UNIFORM: "uniform", ACT_ITEMS: "items",
	ACT_KILL: "kill", ACT_SILENT_KILL: "silent_kill", ACT_GREN_ROOM: "grenade_room", ACT_CLEAR: "clear_room",
	ACT_CUTTER: "use", ACT_ITEM_USE: "use",
}


# --- Sprachausgabe ---------------------------------------------------------------

## Satz-IDs (deutsche Aufnahmen 9000xxxx) des Soldaten für ein Sprach-Ereignis.
func voice_ids(s: Soldier, event: int) -> Array:
	var sq := _squad()
	var slot: int = maxi(sq.members.find(s), 0) % 4 if sq else 0
	var vs: Dictionary = _voices.get("English #%d" % (slot + 1), {})
	var out: Array = []
	for v in vs.get(str(event), []):
		out.append(int(v))
	return out


## Satz sprechen (Aufnahme am Sprecher, Untertitel). Rückgabe: Dauer in s (0 ohne Aufnahme).
func speak(s: Soldier, event: int, fallback_text: String) -> float:
	var ids: Array = voice_ids(s, event) if event >= 0 else []
	var line := fallback_text
	last_speech = []
	var dur := 0.0
	if not ids.is_empty():
		var id := int(ids[randi() % ids.size()])
		last_speech = [s, id]
		var t := text(id)
		if t != "":
			line = t
		var path := OrigLevel.cache_root() + "/sounds/%08d.wav" % id
		if FileAccess.file_exists(path):
			var stream := AudioStreamWAV.load_from_file(path)
			if stream:
				dur = stream.get_length()
				var p := AudioStreamPlayer3D.new()
				p.stream = stream
				p.unit_size = 6.0
				p.max_distance = 60.0
				p.bus = &"Voice"
				s.add_child(p)
				p.finished.connect(p.queue_free)
				p.play()
	if line != "":
		Events.say("%s: \"%s\"" % [s.soldier_name, line.trim_suffix(" (s)")], 2.5)
	return dur


# --- Anzeige (Original 0x4C0370: Titel, „N. Text“, ausgegraut/markiert) ----------

## Kopfzeile (Stil 0x2F/0x30): Hauptmenü „Befehle“ (7270), Untermenü „Befehle - “ (7271) + Name des Untermenüs.
func header() -> String:
	if menu_id != MAIN:
		var parent := -1
		for e in MENUS[MAIN]:
			if int(e[1]) == menu_id:
				parent = int(e[0])
		return text(7271) + text(parent)
	return text(7270)


## Zweite Zeile (Stil 0x31): Aktion/Stille Aktion = Name des Ziels (Akteur vtable +4), sonst Soldatenname bzw.
## „Alle Soldaten“ (7276) – 0x4C0370.
func target_line() -> String:
	if (menu_id == 53 or menu_id == 56) and is_instance_valid(context):
		return _context_name(context)
	if target_index >= 0 and target_index < _squad().members.size():
		return _squad().members[target_index].soldier_name
	return text(7276)


func _context_name(n: Node) -> String:
	if n is Soldier:
		return (n as Soldier).soldier_name
	for key in ["label"]:
		var v = n.get(key)
		if v is String and v != "":
			return v
	if n is Interactable:
		var pr := String((n as Interactable).prompt)
		return pr.get_slice(":", 0) if pr != "" else String(n.name)
	return String(n.name)


func title() -> String:
	if menu_id != MAIN:
		return header()
	return "%s – %s" % [header(), target_line()]


func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for i in 10:
		var t: int = entries[i][0]
		out.append("" if t == -1 else "%d. %s" % [(i + 1) % 10, text(t)])
	return out


## Original-Frame „rollmenu“ (gameinterface.4ds, hud_spec: Rechteck x 0,000–0,226 / y 0,603–0,887 im 4:3-Bild,
## Textur x_mo2, Formate „%d. “/„0. “ – hd2.exe 0x4C0370). Breitbild wie die Truppleiste am linken Rand (B-014).
## Schrift: Projekt-Schrift (die Original-Bitmapschriften Text\Fonts werden nicht konvertiert); Farben der Stile
## 0x33 normal / 0x35 markiert / 0x34 ausgegraut sind nicht dekodiert [E].
const ROLLMENU_RECT := [0.00001, 0.60292, 0.22584, 0.88692]   ## Fallback, wenn hud_spec fehlt
var rollmenu_rect: Array = ROLLMENU_RECT
var rollmenu_tex: Texture2D = null
var _bg: TextureRect


func _load_rollmenu() -> void:
	var dir := OrigLevel.cache_root() + "/ui/hud"
	var spec = LsRuntime._read_json(dir + "/hud_spec.json")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	for e in spec.get("elements", []):
		if String(e.get("name", "")) == "rollmenu":
			if e.get("rect") is Array:
				rollmenu_rect = e["rect"]
			var tf := String(e.get("texture", ""))
			if tf != "" and FileAccess.file_exists(dir + "/" + tf):
				var img := Image.load_from_file(dir + "/" + tf)
				if img:
					rollmenu_tex = ImageTexture.create_from_image(img)
			break


## Bildschirmrechteck des Menüs (4:3-Rahmen auf voller Höhe, links verankert).
func menu_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var fw := vs.y * 4.0 / 3.0
	var r := rollmenu_rect
	return Rect2(r[0] * fw, r[1] * vs.y, (r[2] - r[0]) * fw, (r[3] - r[1]) * vs.y)


func _redraw() -> void:
	if _panel == null:
		_load_rollmenu()
		_panel = PanelContainer.new()
		_panel.name = "RollMenu"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.05, 0.0 if rollmenu_tex else 0.72)
		sb.set_content_margin_all(6)
		_panel.add_theme_stylebox_override("panel", sb)
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		_bg = TextureRect.new()
		_bg.name = "RollMenuTexture"
		_bg.texture = rollmenu_tex
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_SCALE
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.show_behind_parent = true
		_panel.add_child(_bg)
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 0)
		_panel.add_child(_box)
	var mr := menu_rect()
	_panel.position = mr.position
	_panel.size = mr.size
	_panel.custom_minimum_size = mr.size
	var fs := maxi(9, int(mr.size.y / 17.0))
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(_mk_label(header(), fs + 1, Color(0.95, 0.9, 0.7)))
	var tl := _mk_label(target_line(), fs, Color(0.85, 0.8, 0.62))
	tl.name = "TargetLine"
	_box.add_child(tl)
	var ls := lines()
	for i in 10:
		var a: int = entries[i][1]
		var col := Color(0.92, 0.88, 0.76)
		if a == A_GREY:
			col = Color(0.55, 0.55, 0.55)
		elif i == highlight:
			col = Color(1.0, 0.85, 0.35)
		var l := _mk_label(ls[i], fs, col)
		l.name = "Item%d" % i
		_box.add_child(l)
	_panel.visible = is_open


func _mk_label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l
