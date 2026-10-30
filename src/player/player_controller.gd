class_name PlayerController
extends Node
## Übersetzt Eingaben in Absichten des aktiven Soldaten und Squad-Befehle.

var squad: SquadManager
var rig: CameraRig
var mission: Node
var active: Soldier
var input_enabled := true
var interact_target: Interactable
var command_menu: CommandMenu
## Ingame-Inventar (Original T2847, Taste I; Durchsuchen öffnet es mit zweitem Inventar)
var inventory: IngameInventory

var _crouch_toggle := false

## Vereinfachte Auswahl (Vorgabe Auftraggeber, statt Original-Inventar bzw. 3 Tasten vor/zurück/wählen):
## Mausrad blättert durch Waffen und Ausrüstung (im Fahrzeug: Sitzplätze), Linksklick wählt,
## Rechtsklick oder 3 s ohne Eingabe bricht ab. Granaten direkt mit G.
const SELECTION_TIMEOUT := 3.0
var selection_open := false
var selection_index := 0
var _selection_timer := 0.0
var _suppress_fire := false
var _mouse_idle := 0.0      ## s seit der letzten Mausbewegung (Fahrzeug-Verfolgerkamera)


func selection_items() -> Array:
	if not is_instance_valid(active):
		return []
	if active.vehicle != null:
		var v: Vehicle = active.vehicle
		var out: Array = []
		for i in mini(v.seats.size(), v.occupants.size()):
			var occ = v.occupants[i]
			var who := "" if not is_instance_valid(occ) else (" (du)" if occ == active else " – %s" % occ.soldier_name)
			out.append({"key": "seat:%d" % i, "label": v.seat_name(i) + who, "count": -1,
				"enabled": not is_instance_valid(occ) or occ == active})
		return out
	return active.selection_entries()


func _current_key() -> String:
	if active.vehicle != null:
		return "seat:%d" % active.seat_index
	return active.selected_key()


func step_selection(dir: int) -> void:
	var items := selection_items()
	if items.is_empty():
		return
	if not selection_open:
		selection_open = true
		selection_index = 0
		for i in items.size():
			if items[i]["key"] == _current_key():
				selection_index = i
	selection_index = posmod(selection_index + dir, items.size())
	_selection_timer = SELECTION_TIMEOUT
	_show_selection(items)


func confirm_selection() -> void:
	var items := selection_items()
	if selection_open and selection_index < items.size():
		var it: Dictionary = items[selection_index]
		var key := String(it["key"])
		if key.begins_with("seat:"):
			if it.get("enabled", true) and active.vehicle != null:
				if (active.vehicle as Vehicle).switch_seat(active, int(key.substr(5))):
					Events.say("%s: %s" % [active.soldier_name, (active.vehicle as Vehicle).seat_name(active.seat_index)], 1.5)
		else:
			active.apply_selection(key)
			Events.say("%s: %s" % [active.soldier_name, String(it["label"])], 1.5)
	close_selection()
	_suppress_fire = true       # der Bestätigungsklick feuert nicht


func close_selection() -> void:
	selection_open = false
	var hud = mission.get("hud") if mission else null
	if hud and hud.has_method("hide_selection"):
		hud.hide_selection()


func _show_selection(items: Array) -> void:
	var hud = mission.get("hud") if mission else null
	if hud and hud.has_method("show_selection"):
		hud.show_selection("Sitzplatz" if active.vehicle != null else "Ausrüstung", items, selection_index)


func _process(delta: float) -> void:
	if selection_open:
		_selection_timer -= delta
		if _selection_timer <= 0.0 or not is_instance_valid(active) or not active.alive:
			close_selection()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Original-Befehlsmenü (Ziffernblock 0 = an alle, 1–6 = an Soldat n; nur Einzelspieler)
	command_menu = CommandMenu.new()
	command_menu.name = "CommandMenu"
	command_menu.controller = self
	add_child(command_menu)
	inventory = IngameInventory.new()
	inventory.name = "IngameInventory"
	add_child(inventory)
	Events.soldier_died.connect(_on_soldier_died)


## Leichen ohne eigene Durchsuchen-Aktion (Mehrspieler-Spieler, Trupp) werden durchsuchbar (Original: Aktion
## „Durchsuchen“ an jeder Leiche, Fall 7 des Aktionsmenüs hd2.exe 0x4B2830)
func _on_soldier_died(s: Node, _attacker: Node) -> void:
	if not s is Soldier or not is_instance_valid(s):
		return
	# Durchsuchen-Punkt nach der Todesanimation an die liegende Figur (der Körper fällt vom Ursprung weg)
	get_tree().create_timer(2.5, false).timeout.connect(_place_search_point.bind(s))
	for c in s.get_children():
		if c is Pickups.Loot:
			return
	FieldInventory.add_search_spot(s as Soldier)


func _place_search_point(s: Soldier) -> void:
	if not is_instance_valid(s) or s.alive:
		return
	var box := AABB()
	var first := true
	for n in s.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := vi.global_transform * vi.get_aabb()
		if b.size.length() > 6.0:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var c := box.get_center()
	for ch in s.get_children():
		if ch is Pickups.Loot or ch is FieldInventory.SearchSpot:
			(ch as Node3D).global_position = Vector3(c.x, s.global_position.y, c.z)


## Benutzen an einem Durchsuchen-Ziel: Original-Inventar mit zweitem Inventar statt automatischer Übernahme
## (Leiche: Pickups.Loot, Gefangener: EnemyBrain.CaptureAction im Schritt „Suchen“, Leichen-/Ablagestellen)
func _open_search(it: Interactable) -> bool:
	if it is FieldInventory.SearchSpot or it is FieldInventory.Pile:
		it.interact(active)
		return true
	if it is Pickups.Loot:
		var loot := it as Pickups.Loot
		if not is_instance_valid(loot.corpse) or loot.corpse.alive or loot.looted:
			return false
		loot.looted = true
		FieldInventory.add_search_spot(loot.corpse)
		return inventory.open_for(active, loot.corpse)
	if it is EnemyBrain.CaptureAction:
		var ca := it as EnemyBrain.CaptureAction
		if ca.brain == null or not ca.brain.captured or ca.searched or not ca.brain.soldier.alive:
			return false
		ca.searched = true
		return inventory.open_for(active, ca.brain.soldier)
	return false


func set_active(s: Soldier) -> void:
	active = s
	rig.set_target(s)


## Ein Menü liegt über dem Spiel (Pausenmenü/SPIELER-SETUP, Spawnzonen-Karte, Chat, taktische Karte): keine
## Spieleingaben, Maus bleibt frei (Mehrspieler läuft dabei weiter)
func ui_blocking() -> bool:
	if inventory and inventory.is_open():
		return true
	if mission == null:
		return false
	var pm = mission.get_node_or_null("PauseMenu")
	if pm and pm.has_method("is_open") and pm.is_open():
		return true
	var mh = mission.get_node_or_null("MpHud")
	if mh and ((mh.has_method("zone_map_open") and mh.zone_map_open()) or Net.chat_focus):
		return true
	var tm = mission.get("tactical_map")
	return tm != null and bool(tm.get("is_open"))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_instance_valid(active):
		return
	if ui_blocking():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()      # Klicks ins Menü feuern nicht und fangen die Maus nicht
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity * 0.01
		# Zoom/Fernglas: Empfindlichkeit im Verhältnis des aktuellen Sichtfelds
		sens *= clampf(rig.camera.fov / maxf(rig.base_fov(), 1.0), 0.05, 1.0)
		active.look_yaw -= event.relative.x * sens
		var dy: float = event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		# Nickwinkel-Grenze der Original-Kamera (gamecam.set: 3. Person ±70°, 1. Person/Zoom ±80°)
		var lim := rig.pitch_limit()
		active.look_pitch = clampf(active.look_pitch - dy, -lim, lim)
		_mouse_idle = 0.0
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	# Auswahl offen: Linksklick bestätigt, Rechtsklick bricht ab
	if selection_open:
		if event.is_action_pressed("fire"):
			confirm_selection()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("aim"):
			close_selection()
			_suppress_fire = true
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("inventory"):
		# Original T2847: eigenes Inventar ein/aus (Fahrzeug/Tod: nicht)
		if active.alive and active.vehicle == null:
			close_selection()
			inventory.open_for(active)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drop_item"):
		# Original T2827 GEGENST. FALLENL.: Gegenstand in den Händen fällt zu Boden
		var hand := int(FieldInventory.view(active)["hands"])
		if hand >= 0 and active.vehicle == null:
			var r := FieldInventory.request(active, active, "hands", hand, active, "drop")
			if r != "":
				Events.say(r, 1.5)
		return
	if event.is_action_pressed("camera_toggle"):
		if Net.third_person_allowed():
			rig.toggle_mode()
		else:
			Events.say("%s: NEIN" % Net.tx(2373, "3.PERS.-ANSICHT ERLAUBEN"), 2.0)
	elif event.is_action_pressed("stance_crouch"):
		active.stance_request = Soldier.Stance.STAND if active.stance_request == Soldier.Stance.CROUCH else Soldier.Stance.CROUCH
	elif event.is_action_pressed("stance_prone"):
		active.stance_request = Soldier.Stance.CROUCH if active.stance_request == Soldier.Stance.PRONE else Soldier.Stance.PRONE
	elif event.is_action_pressed("stance_stand"):
		active.jump_or_climb()
	elif event.is_action_pressed("jump"):
		active.jump_only()                     # B-015: Original SPRINGEN (getrennt von KLETTERN)
	elif event.is_action_pressed("climb"):
		if not active.climb_only():
			Events.say("Hier kann man nicht klettern.", 1.2)
	elif event.is_action_pressed("speed_up"):
		_step_gait(1)
	elif event.is_action_pressed("speed_down"):
		_step_gait(-1)
	elif event.is_action_pressed("interface_mode"):
		# B-015 INTERFACE-MODUS [P]: Spielanzeige ein/aus (Meldungen und Menüs bleiben)
		var h = mission.get("hud") if mission else null
		if h is CanvasItem or h is CanvasLayer:
			h.visible = not h.visible
	elif event.is_action_pressed("action_menu"):
		if command_menu and not Net.is_online:
			command_menu.open_action_menu()
	elif event.is_action_pressed("reload"):
		active.reload()
	elif event.is_action_pressed("weapon_1"):
		active.select_slot(0)
	elif event.is_action_pressed("weapon_2"):
		active.select_slot(1)
	elif event.is_action_pressed("weapon_3"):
		active.select_slot(WeaponData.Slot.LAUNCHER)
	elif event.is_action_pressed("grenade"):
		if not active.quick_grenade():
			Events.say("Keine Granate.", 1.2)
	elif event.is_action_pressed("weapon_next"):
		step_selection(1)
	elif event.is_action_pressed("weapon_prev"):
		step_selection(-1)
	elif event.is_action_pressed("binoculars"):
		active.toggle_binoculars()
	elif event.is_action_pressed("medkit"):
		if active.medkits <= 0:
			Events.say("Kein Verbandskasten mehr.", 1.5)
		elif not active.start_heal(get_tree().get_nodes_in_group("team_%d" % active.team)):
			Events.say("Niemand in Reichweite ist verwundet.", 1.5)
	elif event.is_action_pressed("fire_mode"):
		var w := active.current_weapon()
		if w and w.toggle_fire_mode():
			Events.say("Feuermodus: %s" % w.fire_mode_text(), 1.5)
	elif event.is_action_pressed("interact"):
		if active.vehicle != null:
			# Aussteigen: Fahrer lässt alle aussteigen
			var v: Vehicle = active.vehicle
			if active.seat_index == 0:
				v.leave_all()
			else:
				v.leave(active)
			Events.say("Ausgestiegen.", 1.5)
		elif interact_target and is_instance_valid(interact_target):
			if _open_search(interact_target):
				return                                     # Durchsuchen: Inventar mit zweitem Inventar
			FieldInventory.view(active)                    # Inventarreihenfolge vor dem Aufnehmen festhalten (neu = hinten)
			interact_target.interact(active)
			if Net.is_online:
				Net.used_interactable(interact_target)     # Türen, Schalter … auch bei den anderen
	elif event.is_action_pressed("soldier_1"):
		squad.set_active(0)
	elif event.is_action_pressed("soldier_2"):
		squad.set_active(1)
	elif event.is_action_pressed("soldier_3"):
		squad.set_active(2)
	elif event.is_action_pressed("soldier_4"):
		squad.set_active(3)
	elif event.is_action_pressed("soldier_next"):
		squad.cycle_active()
	elif _select_key(event) >= 0:
		_on_select_soldier(_select_key(event))
	elif _equip_key(event) >= 0:
		_on_equip(_equip_key(event))
	elif event.is_action_pressed("order_move"):
		var p := rig.crosshair_point(150.0)
		squad.order_all(SquadBrain.Order.MOVE, p)
		Events.say("Befehl: Dorthin bewegen (%d m)" % int(active.global_position.distance_to(p)), 2.0)
	elif event.is_action_pressed("order_grenade"):
		var gp := rig.crosshair_point(60.0)
		var thrower := squad.order_grenade(gp)
		if thrower:
			Events.say("Befehl: %s, Granate dorthin (%d m)" % [thrower.soldier_name, int(thrower.global_position.distance_to(gp))], 2.0)
		else:
			Events.say("Niemand im Trupp hat noch Granaten.", 2.0)
	elif event.is_action_pressed("order_follow"):
		squad.order_all(SquadBrain.Order.FOLLOW)
		Events.say("Befehl: Mir folgen", 2.0)
	elif event.is_action_pressed("order_hold"):
		squad.order_all(SquadBrain.Order.HOLD)
		Events.say("Befehl: Position halten", 2.0)
	elif event.is_action_pressed("order_roe"):
		var r := squad.toggle_roe()
		Events.say("Befehl: %s" % ("Feuer frei" if r == SquadBrain.ROE.FIRE_AT_WILL else "Feuer halten"), 2.0)
	elif event.is_action_pressed("order_formation"):
		Events.say("Formation: %s" % squad.cycle_formation(), 2.0)
	elif event.is_action_pressed("order_stance"):
		var st := active.stance
		for m in squad.members:
			var b := squad.brain_of(m)
			if b and m != active:
				b.stance_override = st if b.stance_override != st else -1
		Events.say("Befehl: Haltung %s" % ["Stehen", "Hocken", "Liegen"][st], 2.0)


## B-015: Grundgangart des gesteuerten Soldaten (Original GESCHW. ERHÖHEN/VERRING.). Standard Laufschritt (Vorgabe
## Auftraggeber); langsamer = Gehen, dann Schleichen. Stufen wie Soldier.SPEEDS.
const GAIT_STEPS := [Soldier.MoveMode.SNEAK, Soldier.MoveMode.WALK, Soldier.MoveMode.JOG]
const GAIT_NAMES := ["Schleichen", "Gehen", "Laufschritt"]
var gait: int = Soldier.MoveMode.JOG


func _step_gait(dir: int) -> void:
	var i := clampi(GAIT_STEPS.find(gait) + dir, 0, GAIT_STEPS.size() - 1)
	gait = GAIT_STEPS[i]
	Events.say("Gangart: %s" % GAIT_NAMES[i], 1.2)


## „SOLDAT n WÄHLEN“ (F1–F4, Entscheid Auftraggeber 24.10.2026), zusammengeführt mit dem Soldatenwechsel:
## einmal = Kamerad markieren/entmarkieren (grau in der Truppleiste), zweimal innerhalb DOUBLE_TAP = übernehmen.
## Eigener (gesteuerter) Soldat: Taste wirkt nicht. Mehrspieler (nur ein Soldat): keine Wirkung.
const DOUBLE_TAP := 0.4
var _last_select := -1
var _last_select_t := -10.0
var _last_select_f := -1000


func _on_select_soldier(i: int) -> void:
	if Net.is_online or i >= squad.members.size():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var frame := Engine.get_process_frames()
	var s := squad.members[i]
	# Rest 0.9.5 [E]: Abstand in Echtzeit, aber je Bild höchstens 1/30 s gezählt – ruckelt das Spiel (Last, Laden), zählen
	# langsame Bilder nicht als „lange gewartet“ (test_commands_orig F3 unter Last 15/17)
	var gap := minf(now - _last_select_t, float(frame - _last_select_f) / 30.0)
	if i == _last_select and gap <= DOUBLE_TAP:
		_last_select = -1
		if squad.set_active(i):              # entfernt auch die Markierung des Übernommenen
			Events.say("Übernommen: %s" % s.soldier_name, 1.5)
		return
	_last_select = i
	_last_select_t = now
	_last_select_f = frame
	if squad.toggle_select(i):
		Events.say("%s %s" % [s.soldier_name, "markiert" if squad.is_selected(s) else "nicht mehr markiert"], 1.5)


## Ausrüstungstasten 4–8 (equip_4…8): Teamplatz-unabhängige Auswahl wie in der Mausrad-Liste.
var EQUIP_KEYS := {4: "slot:%d" % WeaponData.Slot.MELEE, 5: "slot:%d" % WeaponData.Slot.GRENADE, 6: "explosive",
	7: "mine", 8: "medkit"}


func _equip_key(event: InputEvent) -> int:
	for n in EQUIP_KEYS:
		if event.is_action_pressed("equip_%d" % n):
			return n
	return -1


func _on_equip(n: int) -> void:
	if active.vehicle != null:
		return
	var key: String = EQUIP_KEYS[n]
	for it in active.selection_entries():
		if String(it["key"]) == key:
			active.apply_selection(key)
			Events.say("%s: %s" % [active.soldier_name, String(it["label"])], 1.5)
			return
	Events.say("Nicht vorhanden.", 1.2)


## Teamplatz (0–3) einer Markiertaste „select_soldier_1…4“, sonst −1.
func _select_key(event: InputEvent) -> int:
	for i in 4:
		if event.is_action_pressed("select_soldier_%d" % (i + 1)):
			return i
	return -1


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(active) or not active.alive:
		return
	if not input_enabled or ui_blocking():
		active.move_input = Vector3.ZERO
		active.trigger = false
		active.aiming = false
		_suppress_fire = true          # nach dem Schließen erst nach Loslassen der Taste wieder feuern
		return
	if _suppress_fire and not Input.is_action_pressed("fire"):
		_suppress_fire = false
	var fire_ok := not _suppress_fire and not selection_open
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if active.vehicle != null:
		var v: Vehicle = active.vehicle
		if active.seat_index == 0:
			v.throttle = -iv.y
			v.steer_input = -iv.x
			v.handbrake = Input.is_action_pressed("stance_stand") or Input.is_action_pressed("handbrake")   # B-015 HANDBREMSE
			# Kleinst-U-Boot (OrigSubmarine): Leertaste auftauchen, Hocken-Taste tauchen
			v.vertical_input = (1.0 if Input.is_action_pressed("stance_stand") else 0.0) - (1.0 if Input.is_action_pressed("stance_crouch") else 0.0)
			# Verfolgerkamera richtet sich ohne Mausbewegung hinter dem fahrenden Fahrzeug aus
			_mouse_idle += _delta
			if _mouse_idle > 1.2 and v.speed_kmh() > 6.0:
				var k := clampf(_delta * 2.2, 0.0, 1.0)
				active.look_yaw = lerp_angle(active.look_yaw, v.chase_yaw(), k)
				active.look_pitch = lerpf(active.look_pitch, -0.2, k)
		active.aiming = Input.is_action_pressed("aim") and active.seat_index > 0
		active.trigger = active.seat_index > 0 and Input.is_action_pressed("fire") and fire_ok
		active.aim_point = rig.crosshair_point()
		active.has_aim_point = true
		interact_target = null
		return
	var basis := Basis(Vector3.UP, active.look_yaw)
	active.move_input = basis * Vector3(iv.x, 0, iv.y)
	# Moderne Steuerung: immer Laufschritt, Shift = Sprint; leise = geduckt/liegend
	# B-015: GESCHW. ERHÖHEN/VERRING. stellt die Grundgangart um (Standard Laufschritt bleibt, Shift sprintet immer)
	active.move_mode = Soldier.MoveMode.RUN if Input.is_action_pressed("run") else gait
	# Automatisierte Tests simulieren Eingaben ohne Mausfang
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.cli.has("autoplay")
	active.trigger = captured and Input.is_action_pressed("fire") and fire_ok
	active.aiming = captured and Input.is_action_pressed("aim")
	var l := 0.0
	if Input.is_action_pressed("lean_left"):
		l -= 1.0
	if Input.is_action_pressed("lean_right"):
		l += 1.0
	active.lean = l if active.stance != Soldier.Stance.PRONE else 0.0
	active.aim_point = rig.crosshair_point()
	active.has_aim_point = true
	# Rückstoß auf die Blickrichtung anwenden
	var r := active.consume_recoil()
	if r != Vector2.ZERO:
		active.look_pitch = clampf(active.look_pitch + deg_to_rad(r.x), -rig.pitch_limit(), rig.pitch_limit())
		active.look_yaw += deg_to_rad(r.y)
	_update_interact_target()


func _update_interact_target() -> void:
	# Rest 0.9.5 [E]: Blickrichtung gewichten statt nur „nächstes Objekt“. Vorher gewann alles unter 0,9 m unabhängig von der
	# Richtung (africa1: vor HL_DV14 nahm die Benutzen-Taste die 1 m entfernte, seitliche Außentür HL_DV11). Wertung =
	# Abstand + 1 m je rad Abweichung im Blickkegel (±25°), außerhalb 2 m je rad. Hinter dem
	# Spieler (> 90°) nur noch in Berührungsnähe (< 0,6 m).
	var best: Interactable = null
	var best_s := INF
	var fwd := active.forward()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.can_interact(active):
			continue
		var to := it.global_position - active.global_position
		to.y = 0
		var d := to.length()
		if d >= INTERACT_RANGE:
			continue
		var a := fwd.angle_to(to) if d > 0.05 else 0.0
		if a >= 1.0 and not (d < 0.9 and a < PI * 0.5) and d >= 0.6:
			continue
		var s := interact_score(d, a)
		if s < best_s:
			best_s = s
			best = it
	interact_target = best


const INTERACT_RANGE := 2.4
const INTERACT_CONE := 0.44     ## ±25°: Blickkegel

## Zielwertung Benutzen-Taste (kleiner = besser): Abstand [m] + Winkelstrafe 2 m/rad (im Blickkegel halbiert).
static func interact_score(d: float, a: float) -> float:
	return d + a + maxf(a - INTERACT_CONE, 0.0)     # stetig: 1 m/rad im Kegel, außerhalb 2 m/rad
