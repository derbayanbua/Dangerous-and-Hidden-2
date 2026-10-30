extends "res://tests/test_systems.gd"
## Original-Befehlsmenü (Ziffernblock 0 = an alle, 1–6 = an Soldat n): Struktur/Texte wie hd2.exe-Tabelle,
## Bedienung (Ziffern, 0 = zurück/abbrechen, Mausrad + Linksklick), Ausgrauen, Befehle an die Trupp-KI,
## leise Varianten, Formation, Taktik-Plan, Aktion (Tür, Erste Hilfe), Sprachausgabe.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_commands


## Eingaben werden erst im nächsten Hauptschleifen-Durchlauf verteilt (nicht je Physikschritt) →
## nach jedem Ereignis auf Prozess-Frames warten.
func idle(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await idle()


func key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k as Key
	ev.keycode = k as Key
	ev.pressed = true
	await send(ev)
	var up := InputEventKey.new()
	up.physical_keycode = k as Key
	up.keycode = k as Key
	up.pressed = false
	await send(up)


func mouse(button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button as MouseButton
	ev.pressed = true
	await send(ev)
	var up := InputEventMouseButton.new()
	up.button_index = button as MouseButton
	up.pressed = false
	await send(up)


func act(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	await send(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	await send(up)


## Menü öffnen (an alle bzw. Teamplatz n) und Ziffern nacheinander drücken
func cmd(open_action: String, digits: Array) -> void:
	await act(open_action)
	for d in digits:
		await key(KEY_0 + int(d))


func voice_has(cm: CommandMenu, s: Soldier, event: int, id: int) -> bool:
	return cm.voice_ids(s, event).has(id)


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	isolate_enemies([])
	var c: PlayerController = m.controller
	var cm: CommandMenu = c.command_menu
	var sq := m.squad
	var lead := sq.leader()
	c.set_active(lead)
	place(lead, 0, 22, 0.0)
	var mates: Array[Soldier] = []
	for mm in sq.members:
		if mm != lead:
			mates.append(mm)
			place(mm, -3.0 + mates.size() * 2.0, 25, 0.0)
			sq.brain_of(mm).set_order(SquadBrain.Order.HOLD)
	await seconds(0.5)
	check(cm != null, "Befehlsmenü vorhanden")

	# --- Tastenbelegung wie Original (Standard: Ziffernblock 0 / 1–6) ---
	var kp_ok := true
	var acts := ["command_all", "command_1", "command_2", "command_3", "command_4", "command_5", "command_6"]
	for i in acts.size():
		var evs := InputMap.action_get_events(acts[i])
		kp_ok = kp_ok and evs.size() > 0 and evs[0] is InputEventKey and (evs[0] as InputEventKey).physical_keycode == KEY_KP_0 + i
	check(kp_ok, "Tasten: Befehl an alle = Ziffernblock 0, Befehl an 1–6 = Ziffernblock 1–6")

	# --- Hauptmenü: Struktur wie hd2.exe 0x83B610 ---
	await act("command_all")
	check(cm.is_open and cm.menu_id == CommandMenu.MAIN and cm.target_index == -1, "Ziffernblock 0 öffnet das Befehlsmenü (an alle)")
	var ids: Array = cm.entries.map(func(e): return e[0])
	check(ids == [7200, 7201, 7202, 7203, 7204, 7205, 7206, 7207, -1, 7274], "Hauptmenü: Bewegung … Taktik-Modus, 0. Abbrechen", str(ids))
	var cache := OrigLevel.cache_root()
	if FileAccess.file_exists(cache + "/texts_german.json"):
		check(cm.title() == "Befehle – Alle Soldaten" and cm.lines()[0] == "1. Bewegung" and cm.lines()[9] == "0. Abbrechen",
			"Originaltexte: Titel und „1. Bewegung“ … „0. Abbrechen“", "%s | %s" % [cm.title(), cm.lines()[0]])
	if FileAccess.file_exists(cache + "/commands.json"):
		var j = LsRuntime._read_json(cache + "/commands.json")
		var same := true
		for mid in CommandMenu.MENUS:
			if mid == 53 or mid == 56:
				continue
			var rows: Array = []
			for e2 in j["menus_sp"][str(mid)]:
				rows.append([int(e2[0]), int(e2[1])])
			same = same and str(rows) == str(CommandMenu.MENUS[mid])
		check(same, "Menütabellen identisch mit hd2.exe (orig_cache/commands.json)")
	check(cm.entries[7][1] == CommandMenu.A_GREY, "Taktik-Modus ausgegraut (kein Taktik-Plan)")
	check((cm.context == null) == (cm.entries[2][1] == CommandMenu.A_GREY and cm.entries[5][1] == CommandMenu.A_GREY),
		"Aktion/Stille Aktion nur mit Ziel unter dem Fadenkreuz")
	# Ziffer 1 → Untermenü Bewegung, 0 → zurück, 0 → schließen
	var slot0 := lead.current_slot
	await key(KEY_1)
	check(cm.menu_id == 51 and cm.entries[0][0] == 7210 and cm.entries[9][0] == 7275, "1 öffnet „Bewegung“ (… 0. Vorherige Befehle)")
	check(lead.current_slot == slot0, "Ziffern im Menü wechseln keine Waffe")
	await key(KEY_0)
	check(cm.is_open and cm.menu_id == CommandMenu.MAIN, "0 = Vorherige Befehle")
	await key(KEY_0)
	check(not cm.is_open, "0 im Hauptmenü = Abbrechen")

	# --- Bewegung ---
	await cmd("command_all", [1, 1])
	var all_follow := true
	for mm in mates:
		all_follow = all_follow and sq.brain_of(mm).order == SquadBrain.Order.FOLLOW and not sq.brain_of(mm).quiet
	check(not cm.is_open and cm.last_command == 0 and all_follow, "Bewegung › Folgt mir: alle folgen, Menü schließt")
	if FileAccess.file_exists(cache + "/commands.json"):
		check(cm.last_speech.size() == 2 and cm.last_speech[0] == lead and voice_has(cm, lead, 0, cm.last_speech[1])
			and FileAccess.file_exists(cache + "/sounds/%08d.wav" % cm.last_speech[1]),
			"Sprachausgabe „Folgt mir“ (Originalaufnahme)", str(cm.last_speech))
	await seconds(1.5)
	if FileAccess.file_exists(cache + "/commands.json"):
		var who: Soldier = cm.last_speech[0]
		check(who != lead and (voice_has(cm, who, CommandMenu.EV_ACK, cm.last_speech[1])), "Kamerad bestätigt („Klar doch!“ …)")
	await cmd("command_all", [1, 4])
	check(sq.brain_of(mates[0]).order == SquadBrain.Order.HOLD and not sq.brain_of(mates[0]).strict_hold, "Stehen bleiben")
	await cmd("command_all", [1, 5])
	check(sq.brain_of(mates[0]).order == SquadBrain.Order.HOLD and sq.brain_of(mates[0]).strict_hold, "Position halten")
	var goal: Vector3 = m.lb.ground(12, 14, 0.0)
	cm.point_override = goal
	var d0 := mates[0].global_position.distance_to(goal)
	await cmd("command_all", [1, 3])
	await seconds(3.0)
	var b0 := sq.brain_of(mates[0])
	check(b0.order == SquadBrain.Order.MOVE and b0.hold_pos.distance_to(goal) < 2.0 and mates[0].global_position.distance_to(goal) < d0 - 3.0,
		"Bewegung › Dorthin (Fadenkreuzpunkt)", "%.1f → %.1f m" % [d0, mates[0].global_position.distance_to(goal)])
	await cmd("command_all", [1, 2])
	var adv := lead.global_position + lead.forward() * CommandMenu.ADVANCE_DIST
	check(b0.order == SquadBrain.Order.MOVE and Vector2(b0.hold_pos.x - adv.x, b0.hold_pos.z - adv.z).length() < 2.0,
		"Bewegung › Vorwärts (vor den Anführer)", "%s vs %s, order %d, cmd %d" % [b0.hold_pos, adv, b0.order, cm.last_command])
	await cmd("command_all", [1, 6])
	check(b0.order == SquadBrain.Order.COVER, "Bewegung › In Deckung")
	# leise Variante
	await cmd("command_all", [4, 1])
	check(cm.last_command == 1 and b0.order == SquadBrain.Order.FOLLOW and b0.quiet, "Schl. Beweg. › Folgt mir (leise, schleichend)")
	if FileAccess.file_exists(cache + "/commands.json"):
		check(voice_has(cm, lead, 1, cm.last_order_voice) and cm.text(cm.last_order_voice).ends_with("(s)"),
			"Leiser Befehl: geflüsterte Aufnahme („(s)“)", str(cm.last_order_voice))
	place(lead, 0, 22, 0.0)
	for i in mates.size():
		place(mates[i], -3.0 + i * 3.0, 25, 0.0)
		sq.brain_of(mates[i]).set_order(SquadBrain.Order.HOLD)
	await seconds(0.3)

	# --- Angriff: Feuerregeln ---
	await cmd("command_all", [2, 1])
	check(b0.roe == SquadBrain.ROE.FIRE_AT_WILL, "Angriff › Nach Belieben feuern")
	await cmd("command_all", [2, 2])
	check(b0.roe == SquadBrain.ROE.HOLD_FIRE, "Angriff › Feuer einstellen")
	await cmd("command_all", [2, 3])
	check(b0.roe == SquadBrain.ROE.ON_MY_LEAD, "Angriff › Auf mein Kommando feuern")
	# Auf mein Kommando: Kamerad sieht den Gegner, schießt erst nach dem Anführer
	place(lead, 10, 27, 0.0)          # Anführer außerhalb der Schusslinie
	var e := m.enemies[0]
	var eb := reset_enemy(e, -1, 8, PI)
	eb.enabled = false
	var shot_t := mates.map(func(x): return x.last_shot_time)
	await seconds(3.0)
	var seen := (mates[0].get_node("Perception") as Perception).best_target() == e
	var quiet_ok := true
	for i in mates.size():
		quiet_ok = quiet_ok and mates[i].last_shot_time == shot_t[i]
	check(seen and quiet_ok, "Auf mein Kommando: Gegner erkannt, aber kein Schuss ohne Anführer")
	lead.look_yaw = -PI * 0.5         # Anführer schießt (nach Osten in die Luft, weg vom Trupp)
	lead.look_pitch = 0.6
	lead.has_aim_point = false
	var lead_t := lead.last_shot_time
	await hold("fire", 0.2)
	await seconds(2.5)
	var fired := false
	for i in mates.size():
		fired = fired or mates[i].last_shot_time != shot_t[i]
	check(lead.last_shot_time != lead_t and fired, "Auf mein Kommando: Kameraden feuern nach dem Anführer")
	e.global_position = Vector3(-120, 30, -110)
	e.set_physics_process(false)
	e.get_node("Perception").set_physics_process(false)
	for mm in mates:
		(mm.get_node("Perception") as Perception).awareness.clear()
	await cmd("command_all", [2, 2])
	await seconds(1.0)
	# Deckungsfeuer auf einen Punkt
	lead.look_pitch = 0.0
	lead.look_yaw = 0.0
	cm.point_override = m.lb.ground(-15, 0, 1.0)
	var sup_t := mates.map(func(x): return x.last_shot_time)
	await cmd("command_all", [2, 4])
	await seconds(3.0)
	var sup := false
	for i in mates.size():
		sup = sup or mates[i].last_shot_time != sup_t[i]
	check(sup and b0.suppress_time > 0.0, "Angriff › Deckungsfeuer auf den Fadenkreuzpunkt",
		"cmd %d, t %.1f, letzte Schüsse %.1f s, Waffe %s" % [cm.last_command, b0.suppress_time, mates[0].seconds_since_shot(),
		mates[0].current_weapon().data.id if mates[0].current_weapon() else &"-"])
	await seconds(4.0)
	check(b0.suppress_time <= 0.0, "Deckungsfeuer endet nach %d s" % int(CommandMenu.SUPPRESS_TIME))
	# Granate werfen
	cm.point_override = m.lb.ground(0, 8, 0.0)
	var g_before := 0
	for mm in mates:
		g_before += mm.weapons[WeaponData.Slot.GRENADE].total_ammo() if mm.weapons.size() > 2 and mm.weapons[2] else 0
	await cmd("command_all", [2, 5])
	await seconds(4.0)
	var g_after := 0
	for mm in mates:
		g_after += mm.weapons[WeaponData.Slot.GRENADE].total_ammo() if mm.weapons.size() > 2 and mm.weapons[2] else 0
	check(g_after == g_before - 1, "Angriff › Granate werfen (ein Kamerad wirft)", "%d → %d" % [g_before, g_after])
	await seconds(3.0)
	# Raketenwerfer einsetzen
	cm.point_override = m.lb.ground(0, -10, 0.5)
	var r_before := 0
	for mm in mates:
		var lw: Weapon = mm.weapons[WeaponData.Slot.LAUNCHER] if mm.weapons.size() > WeaponData.Slot.LAUNCHER else null
		r_before += lw.total_ammo() if lw else 0
	await cmd("command_all", [2, 6])
	await seconds(5.0)
	var r_after := 0
	var back := true
	for mm in mates:
		var lw2: Weapon = mm.weapons[WeaponData.Slot.LAUNCHER] if mm.weapons.size() > WeaponData.Slot.LAUNCHER else null
		r_after += lw2.total_ammo() if lw2 else 0
		back = back and mm.current_slot != WeaponData.Slot.LAUNCHER
	check(r_before > 0 and r_after == r_before - 1 and back, "Angriff › Raketenwerfer einsetzen (ein Schuss, zurück zur Hauptwaffe)",
		"%d → %d" % [r_before, r_after])

	# --- Formation ---
	sq.set_formation(SquadManager.Formation.COLUMN)
	sq.spacing = 3.0
	await cmd("command_all", [7])
	check(cm.menu_id == 57 and cm.entries[2][1] == CommandMenu.A_GREY and cm.entries[0][1] == 23, "Formation: aktuelle (Kolonne) ausgegraut")
	await key(KEY_1)
	check(sq.formation == SquadManager.Formation.WEDGE, "Formation › Pfeil-Formation")
	await cmd("command_all", [7, 2])
	check(sq.formation == SquadManager.Formation.LINE, "Formation › Linie bilden")
	# B-019: Abstand in Stufen 0…7 × 0,75 m + 1,5 m (hd2.exe 0x4563F0); 3,0 m = Stufe 2
	await cmd("command_all", [7, 4])
	check(is_equal_approx(sq.spacing, 2.25) and sq.spacing_level == 1, "Formation › Enge Formation (eine Stufe, 0,75 m)", str(sq.spacing))
	await cmd("command_all", [7, 5])
	await cmd("command_all", [7, 5])
	check(is_equal_approx(sq.spacing, 3.75), "Formation › Formation ausweiten (Stufe 3 = 3,75 m)", str(sq.spacing))
	sq.spacing = SquadManager.SPACING_MIN
	await cmd("command_all", [7])
	check(cm.entries[3][1] == CommandMenu.A_GREY and cm.entries[4][1] == 25, "Enge Formation ausgegraut bei kleinstem Abstand")
	await key(KEY_0)
	sq.spacing_level = SquadManager.SPACING_LEVELS
	await key(KEY_7)
	check(cm.entries[4][1] == CommandMenu.A_GREY and cm.entries[3][1] == 24 and is_equal_approx(sq.spacing, 6.75),
		"Formation ausweiten ausgegraut bei größtem Abstand (6,75 m)")
	await key(KEY_0)
	await key(KEY_0)
	sq.spacing = 3.0
	await cmd("command_all", [7, 6])
	check(b0.order == SquadBrain.Order.FOLLOW, "Formation › Neu sammeln (alle folgen)")
	var all_alive := true
	for mm in sq.members:
		all_alive = all_alive and mm.alive
	check(all_alive and sq.leader() == lead, "Trupp unversehrt (kein Eigenbeschuss durch Befehle)")

	# --- Befehl an einen Soldaten (Ziffernblock 2 = Teamplatz 2) ---
	var two := sq.members[1]
	await act("command_2")
	check(cm.is_open and cm.target_index == 1 and cm.title().ends_with(two.soldier_name), "Ziffernblock 2: Befehl an Soldat 2", cm.title())
	check(cm.entries[6][1] == CommandMenu.A_GREY and cm.entries[7][1] == CommandMenu.A_GREY, "Einzelner Soldat: Formation/Taktik ausgegraut")
	await key(KEY_1)
	await key(KEY_5)
	check(sq.brain_of(two).order == SquadBrain.Order.HOLD and sq.brain_of(sq.members[2]).order == SquadBrain.Order.FOLLOW,
		"Befehl wirkt nur auf Soldat 2")

	# --- Taktik-Modus (Plan aus der taktischen Karte) ---
	var far: Vector3 = m.lb.ground(-20, 0, 0.0)
	sq.order_one(two, SquadBrain.Order.MOVE, far)
	await act("command_all")
	check(cm.entries[7][1] == 58, "Taktik-Modus wählbar, sobald ein Soldat einen Plan hat")
	await key(KEY_0)
	await act("command_2")
	var only_tac: bool = cm.entries[7][1] == 58
	for g in [0, 1, 3, 4, 6]:
		only_tac = only_tac and cm.entries[g][1] == CommandMenu.A_GREY
	check(only_tac, "Soldat mit Plan: nur Taktik-Modus wählbar")
	await key(KEY_8)
	check(cm.menu_id == 58 and cm.entries[2][0] == 7262, "Taktik-Modus: Signal 1, Signal 2, Halten, Weiter, Befehl aufheben, Zurück in Formation")
	await key(KEY_3)
	var tb := sq.brain_of(two)
	check(tb.plan_paused, "Taktik › Halten")
	var pp := two.global_position
	await seconds(1.0)
	check(two.global_position.distance_to(pp) < 0.6, "Plan angehalten (Soldat steht)")
	await cmd("command_2", [8, 4])
	check(not tb.plan_paused and tb.order == SquadBrain.Order.MOVE, "Taktik › Weiter")
	await cmd("command_2", [8, 6])
	check(tb.order == SquadBrain.Order.FOLLOW and not sq.has_plan(two), "Taktik › Zurück in Formation")

	# --- Aktion: Tür öffnen / leise schließen ---
	var door: Door = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Door and not n.is_open:
			door = n
			break
	check(door != null, "Tür gefunden")
	if door:
		var mate := sq.members[2]
		mate.global_position = door.global_position + door.global_basis.z * 3.0 + Vector3.UP * 0.3
		sq.brain_of(mate).set_order(SquadBrain.Order.HOLD)
		cm.context_override = door
		await cmd("command_3", [3])
		# B-019: Original 0x4BF670 Fall 6 – unverschlossene Tür: Öffnen, Schließen, Hineing. & räumen, Granate in den Raum,
		# Abschließen (nur mit Schlüssel); offen/zu ist keine Bedingung
		var door_ids: Array = cm.entries.slice(0, 5).map(func(e): return e[0])
		check(cm.menu_id == 53 and door_ids == [7023, 7041, 7040, 7037, 7019] and cm.entries[0][1] == CommandMenu.ACT_OPEN
			and cm.entries[1][1] == CommandMenu.ACT_CLOSE and cm.entries[2][1] == CommandMenu.ACT_CLEAR
			and cm.entries[4][1] == CommandMenu.A_GREY, "Aktion (Tür): Einträge wie Original, Abschließen ohne Schlüssel grau", str(door_ids))
		check(cm.target_line() != "" and cm.target_line() != cm.text(7276), "Aktion: zweite Zeile = Name des Ziels", cm.target_line())
		await key(KEY_1)
		for i in 600:
			if door.is_open:
				break
			await frames(1)
		check(door.is_open, "Aktion › Öffnen: Kamerad geht hin und öffnet die Tür")
		await seconds(1.0)
		# B-012: Stille Aktion/Stiller Angriff nur mit Schalldämpferwaffe (Vorgabe Auftraggeber)
		var keep_w: Array = [mate.weapons[0], mate.weapons[1]]
		mate.weapons[0] = Weapon.new(WeaponDB.get_weapon(&"kar98k"))
		mate.weapons[1] = null
		await act("command_3")
		check(cm.entries[4][1] == CommandMenu.A_GREY and cm.entries[5][1] == CommandMenu.A_GREY and cm.entries[3][1] == 54,
			"Ohne Schalldämpfer: Stiller Angriff/Stille Aktion ausgegraut, Schl. Beweg. wählbar")
		await key(KEY_6)
		check(cm.is_open and cm.menu_id == CommandMenu.MAIN, "Taste 6 auf ausgegrauter Stille Aktion wirkungslos")
		await key(KEY_0)
		mate.weapons[0] = Weapon.new(WeaponDB.get_weapon(&"mp40_sd"))
		await act("command_3")
		check(cm.entries[4][1] == 55 and cm.entries[5][1] == 56, "Mit Schalldämpferwaffe (MP 40 SD): leise Menüs wählbar")
		await key(KEY_0)
		await cmd("command_3", [6])
		mate.weapons[0] = keep_w[0]
		mate.weapons[1] = keep_w[1]
		check(cm.menu_id == 56 and cm.entries[1][1] == CommandMenu.ACT_CLOSE, "Stille Aktion (Tür offen): Schließen wählbar")
		await key(KEY_2)
		for i in 300:
			if not door.is_open:
				break
			await frames(1)
		check(not door.is_open and sq.brain_of(mate).quiet, "Stille Aktion › Schließen (leise)")
		cm.context_override = null
	# --- Aktion: Erste Hilfe für einen verwundeten Kameraden ---
	var medic := sq.members[3]
	var hurt := sq.members[2]
	place(hurt, 5, 24, 0.0)
	place(medic, 8, 24, 0.0)
	sq.brain_of(hurt).set_order(SquadBrain.Order.HOLD)
	sq.brain_of(medic).set_order(SquadBrain.Order.HOLD)
	hurt.health = hurt.max_health * 0.4
	hurt.medkits = 0                 # keine Selbstversorgung
	medic.medkits = maxi(medic.medkits, 1)
	var hp0 := hurt.health
	cm.context_override = hurt
	await cmd("command_4", [3])
	check(cm.entries[0][0] == 7034 and cm.entries[0][1] == CommandMenu.ACT_HEAL, "Aktion (verwundeter Kamerad): Erste Hilfe")
	await key(KEY_1)
	await seconds(7.0)
	check(hurt.health > hp0, "Aktion › Erste Hilfe: Kamerad versorgt", "%.0f → %.0f" % [hp0, hurt.health])
	cm.context_override = null

	# --- B-012: Einzelauswahl „SOLDAT n WÄHLEN“ mit echten Tasten (vorläufig 5–8, Original 1–4) ---
	c.set_active(lead)
	sq.clear_selection()
	var s2 := sq.members[1]
	var s3 := sq.members[2]
	for mm in [s2, s3, sq.members[3]]:
		sq.brain_of(mm).clear_tasks()
		sq.brain_of(mm).set_order(SquadBrain.Order.HOLD)
	var slot_before := lead.current_slot
	var fk := InputMap.action_get_events("select_soldier_2")
	check(fk.size() > 0 and (fk[0] as InputEventKey).physical_keycode == KEY_F2, "Soldat 2 wählen = F2 (Entscheid Auftraggeber)")
	await key(KEY_F2)
	check(sq.is_selected(s2) and not sq.is_selected(s3) and lead.current_slot == slot_before and sq.leader() == lead,
		"F2 einmal: Soldat 2 markiert (kein Wechsel)")
	await seconds(0.5)
	await key(KEY_F1)
	check(not sq.is_selected(lead) and sq.leader() == lead, "Anführer selbst ist nicht markierbar")
	await seconds(0.5)
	var hud: OrigHud = null
	for n in get_tree().root.find_children("*", "", true, false):
		if n is OrigHud:
			hud = n
			break
	check(hud != null or not FileAccess.file_exists(OrigLevel.cache_root() + "/ui/hud/hud_spec.json"), "Original-HUD vorhanden")
	if hud and hud.elements.has("select01"):
		await idle(2)
		var sel_el: Control = hud.elements["select01"]["node"]
		var sel_el2: Control = hud.elements["select02"]["node"] if hud.elements.has("select02") else null
		check(sel_el.visible and (sel_el2 == null or not sel_el2.visible), "Truppleiste: markierter Soldat grau hinterlegt (select01)")
	await cmd("command_all", [1, 1])
	check(sq.brain_of(s2).order == SquadBrain.Order.FOLLOW and sq.brain_of(s3).order == SquadBrain.Order.HOLD,
		"Befehl an alle wirkt nur auf die Markierten")
	await key(KEY_F3)
	await seconds(0.5)
	await act("order_hold")
	check(sq.brain_of(s2).order == SquadBrain.Order.HOLD and sq.brain_of(s3).order == SquadBrain.Order.HOLD
		and sq.brain_of(sq.members[3]).order == SquadBrain.Order.HOLD, "Direkttaste (J) an zwei Markierte")
	await act("order_follow")
	check(sq.brain_of(sq.members[3]).order == SquadBrain.Order.HOLD and sq.brain_of(s3).order == SquadBrain.Order.FOLLOW,
		"Unmarkierter Soldat 4 bleibt bei Befehl an die Auswahl")
	await key(KEY_F2)
	await seconds(0.5)
	await key(KEY_F3)
	await seconds(0.5)
	check(sq.selected.is_empty(), "Erneutes Drücken hebt die Markierung auf")
	await act("order_follow")
	check(sq.brain_of(sq.members[3]).order == SquadBrain.Order.FOLLOW, "Ohne Markierung: Befehl an alle")
	var w1 := InputMap.action_get_events("weapon_1")
	check(w1.size() > 0 and (w1[0] as InputEventKey).physical_keycode == KEY_1, "Belegung 1 = Waffe 1 unverändert")
	# F2 zweimal schnell = Soldat 2 übernehmen, danach zurück auf Soldat 1
	await key(KEY_F2)
	await key(KEY_F2)
	check(sq.leader() == s2 and c.active == s2 and not sq.is_selected(s2), "F2 zweimal: Soldat 2 übernommen (Markierung weg)")
	await key(KEY_F1)
	await key(KEY_F1)
	check(sq.leader() == lead, "F1 zweimal: zurück auf Soldat 1")

	# --- Mausrad + Linksklick ---
	var shots0 := Ballistics.shots_fired
	await act("command_all")
	var h0 := cm.highlight
	await mouse(MOUSE_BUTTON_WHEEL_DOWN)
	check(cm.highlight > h0, "Mausrad markiert den nächsten wählbaren Eintrag", "%d → %d" % [h0, cm.highlight])
	var expect: int = cm.entries[cm.highlight][1]
	await mouse(MOUSE_BUTTON_LEFT)
	check(cm.menu_id == expect, "Linksklick öffnet den markierten Eintrag")
	await frames(5)
	check(Ballistics.shots_fired == shots0, "Klick im Menü feuert nicht")
	await key(KEY_0)
	await key(KEY_0)
	check(not cm.is_open, "Menü geschlossen")

	await _b019(m, c, cm, sq, lead)
	await _persistence(m, c, cm, sq, lead)
	_finish()


## B-019: Formation nach den Originaltabellen, Aktionsmenü am Menschen, Darstellung im Original-Frame „rollmenu“.
func _b019(m: Mission, c: PlayerController, cm: CommandMenu, sq: SquadManager, lead: Soldier) -> void:
	c.set_active(lead)
	sq.clear_selection()
	place(lead, 0, 22, 0.0)
	lead.look_yaw = 0.0
	# Formation Pfeil, Stufe 3 (Start wie Original 0x5A91A0/0x456440): Platz 1 links hinten, Platz 2 rechts hinten
	sq.set_formation(SquadManager.Formation.WEDGE)
	sq.spacing_level = 3
	var f := sq._followers(lead)
	var p1 := sq._raw_slot(1, lead) - lead.global_position
	var p2 := sq._raw_slot(2, lead) - lead.global_position
	check(f.size() >= 2 and p1.distance_to(Vector3(-3.75, 0, 3.75)) < 0.01 and p2.distance_to(Vector3(3.75, 0, 3.75)) < 0.01,
		"Pfeil-Formation: Plätze (−1,−1)/(1,−1) × 3,75 m wie hd2.exe 0x8AB1D0", "%s %s" % [p1, p2])
	sq.set_formation(SquadManager.Formation.COLUMN)
	var c3 := sq._raw_slot(3, lead) - lead.global_position
	check(c3.distance_to(Vector3(0, 0, 11.25)) < 0.01, "Kolonne: Platz 3 genau 3 × 3,75 m hinter dem Anführer", str(c3))
	sq.set_formation(SquadManager.Formation.LINE)
	var l2 := sq._raw_slot(2, lead) - lead.global_position
	check(l2.distance_to(Vector3(-7.5, 0, 0)) < 0.01, "Linie: Platz 2 = 2 × 3,75 m links neben dem Anführer", str(l2))
	sq.spacing_level = 0
	sq.set_formation(SquadManager.Formation.WEDGE)
	var slots := sq.formation_slots(lead)
	var min_d := INF
	var pts: Array = slots.values() + [lead.global_position]
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_d = minf(min_d, Vector2(pts[i].x - pts[j].x, pts[i].z - pts[j].z).length())
	check(min_d >= SquadManager.SEPARATION - 0.01, "Trennung: Zielplätze mindestens 1,2 m auseinander (0x598550)", "%.2f m" % min_d)
	sq.spacing_level = 3
	check(absf(sq.slot_watch_offset(f[0]) - atan2(0.5, 1.0)) < 0.01, "Pfeil: Platz 1 sichert nach links vorn (Platzrichtung)")
	# Aktionsmenü an einem Gegner: Töten / Leise töten / Gefangennehmen (nur ergeben)
	var e := m.enemies[1] if m.enemies.size() > 1 else m.enemies[0]
	var eb := reset_enemy(e, 4, 30, PI)
	eb.enabled = false
	cm.context_override = e
	await cmd("command_all", [3])
	var ids: Array = cm.entries.slice(0, 3).map(func(x): return x[0])
	check(cm.menu_id == 53 and ids == [7045, 7046, 7038] and cm.entries[2][1] == CommandMenu.A_GREY,
		"Aktion (Gegner): Töten, Leise töten, Gefangennehmen grau (ergibt sich nicht)", str(ids))
	check(cm.target_line() == e.soldier_name, "Aktion: Zeile 2 = Name des Gegners")
	await key(KEY_0)
	await key(KEY_0)
	# B-015: Original AKTIONSMENÜ (Taste ') öffnet „Befehl an alle“ direkt im Untermenü Aktion
	await tap("action_menu")
	check(cm.is_open and cm.menu_id == 53 and cm.entries[0][0] == 7045, "B-015 AKTIONSMENÜ: direkt im Untermenü Aktion",
		"offen %s Menü %d" % [cm.is_open, cm.menu_id])
	await key(KEY_0)
	await key(KEY_0)
	eb.surrendered = true
	var mate := sq.members[1]
	place(mate, 4, 26, 0.0)
	sq.brain_of(mate).clear_tasks()
	sq.brain_of(mate).set_order(SquadBrain.Order.HOLD)
	await cmd("command_2", [3])
	check(cm.entries[2][1] == CommandMenu.ACT_CAPTURE, "Gegner ergibt sich: Gefangennehmen wählbar")
	await key(KEY_3)
	for i in 600:
		if eb.captured:
			break
		await frames(1)
	check(eb.captured, "Aktion › Gefangennehmen: Kamerad geht hin und nimmt gefangen")
	await cmd("command_2", [3])
	ids = cm.entries.slice(0, 4).map(func(x): return x[0])
	check(ids == [7045, 7043, 7044, 7050] and cm.entries[2][1] == CommandMenu.ACT_UNIFORM,
		"Aktion (Gefangener): Töten, Suchen & Mun. sammeln, Uniform benutzen, Gegenstände nehmen", str(ids))
	await key(KEY_0)
	await key(KEY_0)
	# Befehl an genau den Soldaten unter dem Fadenkreuz: kein Ziel (0x4C10F0 Fall 3)
	cm.context_override = mate
	await act("command_2")
	check(cm.context == null and cm.entries[2][1] == CommandMenu.A_GREY, "Soldat ist kein Aktionsziel für sich selbst")
	await key(KEY_0)
	cm.context_override = null
	e.global_position = Vector3(-120, 30, -110)
	e.set_physics_process(false)
	# Darstellung: Original-Frame „rollmenu“ links über der Truppleiste
	await act("command_all")
	var r := cm.menu_rect()
	var vs := cm.get_viewport().get_visible_rect().size
	check(cm._panel != null and cm._panel.visible and absf(r.position.y / vs.y - 0.60292) < 0.01 and r.position.x < 1.0
		and absf(r.size.y / vs.y - 0.284) < 0.01, "Menü im Original-Frame „rollmenu“ (x 0–0,226, y 0,603–0,887)", str(r))
	if FileAccess.file_exists(OrigLevel.cache_root() + "/ui/hud/textures/x_mo2.png"):
		check(cm.rollmenu_tex != null, "Hintergrund = Originaltextur x_mo2 (gameinterface.4ds)")
	if OrigFonts.available():
		# B-003: Originalschrift und Stilfarben (hd2.exe 0x641E30: 0x33 schwarz, 0x34 schwarz Alpha 0x60, 0x35 rot)
		var live := cm._box.get_children().filter(func(c): return not c.is_queued_for_deletion())
		var it0: Label = live[2] if live.size() > 2 else null      # Titel, Zielzeile, dann Eintrag 1
		var col := it0.get_theme_color("font_color") if it0 else Color.WHITE
		check(cm.orig_font and it0 != null and it0.get_theme_font("font") is FontFile
			and (col.is_equal_approx(Color.BLACK) or col.is_equal_approx(Color(1, 0, 0)) or absf(col.a - 0x60 / 255.0) < 0.01),
			"Befehlsmenü in Originalschrift/-farbe (Stile 0x2F–0x35)", str(col))
	await key(KEY_0)
	# Taktik-Plan: Befehl „an alle“ erreicht nur Soldaten ohne Plan (0x456020)
	var two := sq.members[1]
	var three := sq.members[2]
	sq.brain_of(three).set_order(SquadBrain.Order.HOLD)
	sq.order_one(two, SquadBrain.Order.MOVE, m.lb.ground(-20, 0, 0.0))
	await cmd("command_all", [1, 1])
	check(sq.has_plan(two) and sq.brain_of(three).order == SquadBrain.Order.FOLLOW, "Folgt mir (an alle) übergeht Soldaten mit Taktik-Plan")
	await cmd("command_2", [8, 6])


## Befehle bleiben bestehen (Fehlerbericht 23.10.2026 „die folgen immer nur“): echte Tasten, 20 s Spielzeit, der
## Anführer läuft dabei weg. Original: Halt/Position halten löschen das Folge-Flag (hd2.exe 0x535C00 → 0x537E50 →
## 0x5377F0(0)); Soldatenwechsel lässt die Folger des abgegebenen Soldaten stehen (0x53BC50 → 0x4593E0).
func _persistence(m: Mission, c: PlayerController, cm: CommandMenu, sq: SquadManager, lead: Soldier) -> void:
	cm.point_override = Vector3.INF
	cm.context_override = null
	c.set_active(lead)
	place(lead, 0, 22, 0.0)
	var mates: Array[Soldier] = []
	for mm in sq.alive_members():
		if mm != lead:
			mates.append(mm)
			place(mm, -3.0 + mates.size() * 2.0, 25, 0.0)
			sq.brain_of(mm).clear_tasks()
	await cmd("command_all", [1, 1])          # Folgt mir
	await seconds(1.0)
	# Halt (Bewegung › Stehen bleiben) – Anführer läuft 6 s davon, nach 20 s stehen alle noch
	await cmd("command_all", [1, 4])
	var p0 := {}
	for mm in mates:
		p0[mm] = mm.global_position
	var lp0 := lead.global_position
	Input.action_press("move_forward")
	await seconds(6.0)
	Input.action_release("move_forward")
	await seconds(14.0)
	var held := true
	var info := []
	for mm in mates:
		var d: float = mm.global_position.distance_to(p0[mm])
		info.append("%s %d %.1f m" % [mm.soldier_name, sq.brain_of(mm).order, d])
		held = held and sq.brain_of(mm).order == SquadBrain.Order.HOLD and d < 1.5
	check(held and lead.global_position.distance_to(lp0) > 4.0,
		"Halt bleibt nach 20 s bestehen (Anführer läuft weg, Trupp folgt nicht)",
		"Anführer %.1f m; %s" % [lead.global_position.distance_to(lp0), ", ".join(info)])
	# Dorthin (Fadenkreuzpunkt) – erreicht das Ziel und bleibt dort, auch wenn der Anführer weiterläuft
	var goal: Vector3 = m.lb.ground(12, 14, 0.0)
	cm.point_override = goal
	await cmd("command_all", [1, 3])
	cm.point_override = Vector3.INF
	place(lead, 10, 5, PI)
	Input.action_press("move_forward")
	await seconds(5.0)
	Input.action_release("move_forward")
	await seconds(15.0)
	var there := true
	info = []
	for mm in mates:
		var d2: float = Vector2(mm.global_position.x - goal.x, mm.global_position.z - goal.z).length()
		info.append("%s %d %.1f m" % [mm.soldier_name, sq.brain_of(mm).order, d2])
		there = there and sq.brain_of(mm).order == SquadBrain.Order.MOVE and d2 < 3.5
	check(there, "Dorthin: nach 20 s am Ziel, Befehl besteht (kein Folgen)", ", ".join(info))
	# Position halten an einen einzelnen Soldaten (Ziffernblock 2), die übrigen folgen
	var two := sq.members[1]
	await cmd("command_all", [1, 1])
	await cmd("command_2", [1, 5])
	var p2 := two.global_position
	Input.action_press("move_back")
	await seconds(5.0)
	Input.action_release("move_back")
	await seconds(15.0)
	var others_follow := true
	for mm in mates:
		if mm != two:
			others_follow = others_follow and sq.brain_of(mm).order == SquadBrain.Order.FOLLOW
	check(sq.brain_of(two).order == SquadBrain.Order.HOLD and sq.brain_of(two).strict_hold and two.global_position.distance_to(p2) < 1.5
		and others_follow, "Einzelbefehl „Position halten“ bleibt 20 s, die anderen folgen weiter",
		"%.1f m" % two.global_position.distance_to(p2))
	# Soldatenwechsel: abgegebener Soldat und seine Folger bleiben stehen (Original 0x4593E0)
	var p3 := {}
	for mm in sq.alive_members():
		p3[mm] = mm.global_position
	await tap("soldier_3")
	var nl := sq.leader()
	check(nl == sq.members[2] and c.active == nl, "Wechsel auf Soldat 3")
	Input.action_press("move_forward")
	await seconds(5.0)
	Input.action_release("move_forward")
	await seconds(15.0)
	var stay := true
	info = []
	for mm in sq.alive_members():
		if mm == nl:
			continue
		var d3: float = mm.global_position.distance_to(p3[mm])
		info.append("%s %d %.1f m" % [mm.soldier_name, sq.brain_of(mm).order, d3])
		stay = stay and sq.brain_of(mm).order == SquadBrain.Order.HOLD and d3 < 1.5
	check(stay, "Soldatenwechsel: niemand fällt auf Folgen zurück (20 s)", ", ".join(info))
	await cmd("command_all", [1, 1])
	await seconds(4.0)
	var fol := true
	for mm in sq.alive_members():
		if mm != nl:
			fol = fol and sq.brain_of(mm).order == SquadBrain.Order.FOLLOW and mm.global_position.distance_to(nl.global_position) < 16.0
	check(fol, "„Folgt mir“ bindet den Trupp an den neuen Soldaten")
	await tap("soldier_1")
