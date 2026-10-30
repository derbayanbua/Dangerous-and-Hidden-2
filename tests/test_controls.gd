extends "res://tests/test_systems.gd"
## Vereinfachte Steuerung: Mausrad-Auswahl (Waffen/Ausrüstung), Linksklick wählt, G = Granate,
## Raketenwerfer, Messer, Sprengstoff, Mine, Erste Hilfe; im Fahrzeug Sitzplatz per Mausrad/Linksklick.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_controls


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	isolate_enemies([])
	var c: PlayerController = m.controller
	var s: Soldier = m.squad.leader()
	c.set_active(s)
	var keys: Array = s.selection_entries().map(func(e): return e["key"])
	check(keys.has("slot:0") and keys.has("slot:3") and keys.has("slot:1") and keys.has("slot:4") and keys.has("slot:2")
		and keys.has("explosive") and keys.has("mine") and keys.has("medkit") and keys.has("binoculars"),
		"Ausrüstung: Primär, Raketenwerfer, Pistole, Messer, Granate, Sprengstoff, Mine, Erste Hilfe, Fernglas", str(keys))
	# Direkttasten 1–8 (Entscheid Auftraggeber 24.10.2026), Fernglas B, Feuermodus mittlere Maustaste, F1–F4 Soldat wählen
	var kc := func(a: String) -> int:
		var ev := InputMap.action_get_events(a)
		return (ev[0] as InputEventKey).physical_keycode if ev.size() > 0 and ev[0] is InputEventKey else -1
	var fm := InputMap.action_get_events("fire_mode")
	check(kc.call("weapon_1") == KEY_1 and kc.call("weapon_2") == KEY_2 and kc.call("weapon_3") == KEY_3
		and kc.call("equip_4") == KEY_4 and kc.call("equip_5") == KEY_5 and kc.call("equip_6") == KEY_6
		and kc.call("equip_7") == KEY_7 and kc.call("equip_8") == KEY_8 and kc.call("binoculars") == KEY_B
		and kc.call("select_soldier_1") == KEY_F1 and kc.call("select_soldier_4") == KEY_F4
		and fm.size() > 0 and fm[0] is InputEventMouseButton and (fm[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE,
		"Belegung: 1–8 Waffen/Ausrüstung, B Fernglas, MMT Feuermodus, F1–F4 Soldat wählen")
	await tap("equip_4")
	check(s.current_slot == WeaponData.Slot.MELEE, "Taste 4: Messer")
	await tap("equip_6")
	check(s.tool == "explosive", "Taste 6: Sprengstoff in der Hand", s.tool)
	await tap("weapon_1")
	await seconds(0.8)
	check(s.tool == "" and s.current_slot == WeaponData.Slot.PRIMARY, "Taste 1: zurück zur Primärwaffe")
	await tap("binoculars")
	check(s.using_binoculars, "B: Fernglas")
	await tap("binoculars")
	await seconds(0.5)
	# B-015: übrige Original-Aktionen – alle im Optionsmenü, Verbesserungen unverändert, Funktionen angebunden
	var listed := {}
	for cat in load("res://src/ui/main_menu.gd").KEY_CATEGORIES:
		for a in cat[1]:
			listed[a] = true
	var missing := InputSetup.ACTIONS.keys().filter(func(a): return not listed.has(a))
	check(missing.is_empty(), "B-015: jede Aktion steht auf einer Belegungsseite", str(missing))
	check(kc.call("run") == KEY_SHIFT and kc.call("stance_stand") == KEY_SPACE and kc.call("grenade") == KEY_G
		and kc.call("medkit") == KEY_H and kc.call("order_move") == KEY_X and kc.call("order_follow") == KEY_U
		and kc.call("order_grenade") == KEY_T and kc.call("camera_toggle") == KEY_V and kc.call("stance_crouch") == KEY_C
		and InputMap.action_get_events("speed_up").is_empty() and InputMap.action_get_events("jump").is_empty()
		and InputMap.action_get_events("climb").is_empty() and kc.call("action_menu") == KEY_APOSTROPHE
		and kc.call("game_info") == KEY_COMMA and kc.call("pause_game") == KEY_P and kc.call("handbrake") == KEY_ALT,
		"B-015: Verbesserungen bleiben, Original-Aktionen frei bzw. unbelegt")
	# Kollisionsprüfung: keine Spielaktion teilt eine Taste mit einer anderen Spielaktion, außer T (F-016)
	var seen := {}
	var clash := []
	for a: String in InputSetup.ACTIONS:
		if InputSetup.is_tactical(a) or a in ["chat_all", "chat_team", "console", "voice_talk", "show_players"]:
			continue
		var k: int = kc.call(a)
		if k < 0:
			continue
		if seen.has(k):
			clash.append("%s/%s" % [seen[k], a])
		seen[k] = a
	check(clash.is_empty(), "B-015: keine doppelte Taste im Spielkontext", str(clash))
	check(c.gait == Soldier.MoveMode.JOG, "Standard-Gangart Laufschritt")
	await tap("speed_down")
	check(c.gait == Soldier.MoveMode.WALK, "GESCHW. VERRING.: Gehen")
	await tap("speed_down")
	await tap("speed_down")
	check(c.gait == Soldier.MoveMode.SNEAK, "GESCHW. VERRING.: Schleichen (Endstufe)")
	await tap("speed_up")
	await tap("speed_up")
	check(c.gait == Soldier.MoveMode.JOG, "GESCHW. ERHÖHEN: zurück zum Laufschritt")
	var y0 := s.global_position.y
	await tap("jump")
	await seconds(0.25)
	check(s.global_position.y > y0 + 0.1, "SPRINGEN als eigene Aktion", "%.2f" % (s.global_position.y - y0))
	await seconds(1.0)
	await tap("interface_mode")
	check(not m.hud.visible, "INTERFACE-MODUS blendet die Anzeige aus")
	await tap("interface_mode")
	check(m.hud.visible, "INTERFACE-MODUS blendet die Anzeige wieder ein")
	var tm = m.get("tactical_map")
	if tm:
		await tap("map")
		check(tm.is_open, "KARTE öffnet die Karte")
		var z0: int = tm._zoom_i
		await tap("tac_zoom_out")
		await tap("tac_prone")
		var g0: int = s.weapons[2].total_ammo() if s.weapons.size() > 2 and s.weapons[2] else -1
		await tap("tac_regroup")
		check(tm._zoom_i == maxi(z0 - 1, 0) and tm.cur_stance == Soldier.Stance.PRONE and tm.is_open,
			"Taktik-Tasten: Wegzoomen, Liegen", "zoom %d→%d Haltung %d" % [z0, tm._zoom_i, tm.cur_stance])
		check(g0 < 0 or s.weapons[2].total_ammo() == g0, "Taktik-Taste G wirft bei offener Karte keine Granate")
		await tap("tac_prone")
		await tap("map")
		check(not tm.is_open, "KARTE schließt die Karte")
		await seconds(0.3)
	# Mausrad öffnet die Auswahl, Linksklick wählt (ohne zu feuern)
	await tap("weapon_next")
	check(c.selection_open and m.hud.selection_visible(), "Mausrad öffnet die Auswahlliste")
	var items := c.selection_items()
	check(items[c.selection_index]["key"] == "slot:3", "Nächster Eintrag nach der Primärwaffe: Raketenwerfer",
		str(items[c.selection_index]))
	var shots0 := Ballistics.shots_fired
	await tap("fire")
	await frames(5)
	check(not c.selection_open and s.current_slot == WeaponData.Slot.LAUNCHER and s.current_weapon().data.id == &"bazooka",
		"Linksklick wählt den Raketenwerfer")
	check(Ballistics.shots_fired == shots0 and s.current_weapon().in_mag == 1, "Bestätigungsklick feuert nicht")
	# Raketenwerfer: Gegner im Ziel
	var e := enemy("e_north")
	var b := reset_enemy(e, 15, 20, PI * 0.5)
	b.enabled = false
	e.get_node("Perception").set_physics_process(false)
	place(s, 3, 20, -PI * 0.5)
	await seconds(1.0)
	s.has_aim_point = false
	s.look_pitch = 0.0
	s.look_yaw = atan2(-(e.global_position.x - s.global_position.x), -(e.global_position.z - s.global_position.z))
	await seconds(0.6)
	var ammo0 := s.current_weapon().total_ammo()
	await hold("fire", 0.1)
	var rockets := get_tree().root.find_children("*", "Grenade", true, false)
	check(s.current_weapon().total_ammo() == ammo0 - 1 and not rockets.is_empty() and rockets[0].impact,
		"Linksklick feuert eine Rakete (Aufschlagzünder)")
	await seconds(4.5)    # Nachladen (Bazooka 4 s)
	# gezielter Schuss auf den Gegner (Kamera-Fadenkreuz ist im 64×64-Testfenster nicht repräsentativ)
	var origin := s.eye_position()
	var dir := (e.global_position + Vector3.UP * 1.0 - origin).normalized()
	s._fire_rocket(s.current_weapon(), origin, dir)
	await seconds(1.5)
	check(not e.alive, "Rakete trifft und tötet den Gegner", "HP %.0f" % e.health)
	# Rechtsklick bricht die Auswahl ab
	await tap("weapon_prev")
	check(c.selection_open, "Mausrad zurück öffnet die Auswahl")
	await tap("aim")
	check(not c.selection_open and s.current_slot == WeaponData.Slot.LAUNCHER, "Rechtsklick bricht ab, Auswahl unverändert")
	# Messer: Gegner von hinten
	c.selection_open = false
	s.apply_selection("slot:4")
	check(s.current_weapon().data.id == &"knife", "Messer gewählt")
	var e2 := enemy("e_south") if enemy("e_south") else m.enemies[1]
	reset_enemy(e2, 3, 22, PI)          # blickt nach Süden? Spieler steht hinter ihm
	(e2.get_node("EnemyBrain") as EnemyBrain).enabled = false
	e2.get_node("Perception").set_physics_process(false)
	e2.look_yaw = 0.0                   # Blick nach Norden (−Z)
	place(s, 3, 23.0, 0.0)              # 1 m südlich, Blick nach Norden auf seinen Rücken
	await seconds(0.8)
	await hold("fire", 0.1)
	await seconds(0.5)
	check(not e2.alive, "Messer von hinten tödlich")
	# G: Granate werfen ohne Waffenwechsel
	var g0 := s.weapons[2].total_ammo()
	await tap("grenade")
	check(s.weapons[2].total_ammo() == g0 - 1 and s.current_slot == WeaponData.Slot.MELEE, "G wirft eine Granate, Waffe bleibt")
	await seconds(5.0)
	# Sprengstoff legen (Linksklick), explodiert nach 10 s
	s.apply_selection("explosive")
	var ex0 := s.explosives
	place(s, -20, 20, 0.0)
	await seconds(0.3)
	await hold("fire", 0.1)
	check(s.explosives == ex0 - 1 and get_tree().get_nodes_in_group("soldiers").size() > 0, "Sprengladung gelegt")
	var charges := m.find_children("*", "PlacedCharge", true, false)
	check(charges.size() == 1, "Ladung liegt in der Welt")
	place(s, -20, 45, 0.0)      # Abstand halten
	await seconds(10.5)
	check(m.find_children("*", "PlacedCharge", true, false).is_empty(), "Ladung nach 10 s explodiert")
	# Mine: löst bei einem Gegner aus
	s.apply_selection("mine")
	place(s, 10, 30, 0.0)
	await seconds(0.3)
	await hold("fire", 0.1)
	var mine: PlacedCharge = m.find_children("*", "PlacedCharge", true, false)[0] if not m.find_children("*", "PlacedCharge", true, false).is_empty() else null
	check(mine != null and mine.kind == "mine", "Mine gelegt")
	place(s, 10, 50, 0.0)
	await seconds(3.5)
	var e3: Soldier = null
	for x in m.enemies:
		if x.alive:
			e3 = x
			break
	if mine and e3:
		reset_enemy(e3, 10, 29.3, 0.0)
		(e3.get_node("EnemyBrain") as EnemyBrain).enabled = false
		e3.global_position = mine.global_position + Vector3(0.6, 0.3, 0.0)
		await seconds(1.0)
		check(not is_instance_valid(mine) or mine.is_queued_for_deletion(), "Mine löst bei Gegner aus")
	# Erste Hilfe über die Auswahl
	var mate: Soldier = m.squad.members[1]
	mate.global_position = s.global_position + Vector3(0.8, 0, 0)
	mate.health = mate.max_health * 0.5
	s.apply_selection("medkit")
	var mk := s.medkits
	await hold("fire", 0.1)
	await seconds(3.5)
	check(s.medkits == mk - 1 and mate.health > mate.max_health * 0.5, "Erste Hilfe per Linksklick")
	# Fahrzeug: Sitzplatz wechseln
	var v: Vehicle = get_tree().get_nodes_in_group("vehicles")[0]
	s.apply_selection("slot:0")
	s.global_position = v.global_position + Vector3(2, 0.5, 0)
	await frames(5)
	v.board(s, true)
	check(s.vehicle == v and s.seat_index == 0, "Als Fahrer eingestiegen")
	await tap("weapon_next")
	var it2: Dictionary = c.selection_items()[c.selection_index]
	check(c.selection_open and String(it2["key"]).begins_with("seat:"), "Mausrad im Fahrzeug: Sitzplätze", str(it2))
	await tap("fire")
	await frames(5)
	check(s.seat_index == 1 and v.occupants[1] == s and v.driver() == null, "Linksklick wechselt auf den Beifahrersitz")
	v.leave_all()
	_finish()
