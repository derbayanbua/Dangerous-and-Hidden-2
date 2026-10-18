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
	await cmd("command_all", [7, 4])
	check(is_equal_approx(sq.spacing, 2.0), "Formation › Enge Formation", str(sq.spacing))
	await cmd("command_all", [7, 5])
	await cmd("command_all", [7, 5])
	check(is_equal_approx(sq.spacing, 4.0), "Formation › Formation ausweiten", str(sq.spacing))
	sq.spacing = SquadManager.SPACING_MIN
	await cmd("command_all", [7])
	check(cm.entries[3][1] == CommandMenu.A_GREY, "Enge Formation ausgegraut bei kleinstem Abstand")
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
		check(cm.menu_id == 53 and cm.entries[0][0] == 7023 and cm.entries[0][1] == CommandMenu.ACT_OPEN
			and cm.entries[1][1] == CommandMenu.A_GREY, "Aktion (Tür zu): Öffnen wählbar, Schließen ausgegraut")
		await key(KEY_1)
		for i in 600:
			if door.is_open:
				break
			await frames(1)
		check(door.is_open, "Aktion › Öffnen: Kamerad geht hin und öffnet die Tür")
		await seconds(1.0)
		await cmd("command_3", [6])
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
	_finish()
