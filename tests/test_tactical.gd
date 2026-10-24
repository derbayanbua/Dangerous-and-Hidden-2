extends "res://tests/test_gameplay.gd"
## Taktische Karte (Original-Knopfleiste, mehrere Wegpunkte, Signale, Haltung) und Original-Pausemenü mit
## Spielstandliste/Speicherbegrenzung.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_tactical


func place(s: Soldier, x: float, z: float, yaw: float) -> void:
	s.global_position = mission().lb.ground(x, z, 0.3)
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	isolate_enemies([])
	var hale := m.squad.leader()
	place(hale, 0, 30, 0.0)
	var ash: Soldier = m.squad.members[2]
	place(ash, 4, 32, 0.0)
	for s in m.squad.members:
		m.squad.brain_of(s).roe = SquadBrain.ROE.HOLD_FIRE
	await seconds(0.5)

	# --- Taktische Karte: Original-Knopfleiste ---
	var tm = m.tactical_map
	await tap("tactical_map")
	check(tm.is_open and get_tree().paused, "Karte offen, Spiel angehalten")
	var names := ["regroup", "wait01", "wait02", "stay", "kneel", "lie", "sprint", "run", "walk", "slow", "aggresive",
		"defensive", "passive", "delete", "deleteall", "TMcamera", "realtime", "options"]
	var all_btn := true
	for n in names:
		all_btn = all_btn and tm.find_child("TM_" + n, true, false) != null
	check(all_btn, "Knopfleiste: 18 Originalknöpfe (Haltung, Gangart, Stimmung, Signale, Löschen, Kamera, Echtzeit)")
	var tb := tm.find_child("TM_kneel", true, false) as TextureButton
	check(tb != null and tb.texture_normal != null and tb.tooltip_text == SAS.text(7424, "DUCKEN"),
		"Originalsymbol I_KNEEL und Text 7424", tb.tooltip_text if tb else "-")
	check((tm.find_child("text_pose", true, false) as Label).text == SAS.text(7320, "Haltung"), "Gruppenbeschriftung T7320")
	var z0: int = tm._zoom_i
	tm.press_button("TMcamera")
	check(tm._zoom_i == (z0 + 1) % 5, "Kamerastufe 1×–16× umschaltbar")
	tm.press_button("realtime")
	check(not get_tree().paused, "Echtzeit: Spiel läuft bei offener Karte")
	tm.press_button("realtime")
	check(get_tree().paused, "Echtzeit aus: wieder angehalten")
	# Plan: zwei Wegpunkte, der erste geduckt mit Warten auf Signal 1
	await get_tree().process_frame
	tm._click(tm._cam.unproject_position(ash.global_position), false)
	check(tm.selected.has(ash), "Soldat ausgewählt")
	tm.press_button("kneel")
	var wp1 := m.lb.ground(8, 26)
	var wp2 := m.lb.ground(2, 22)
	tm.add_waypoint(ash, wp1, 1)
	tm.press_button("stay")
	tm.press_button("stay")       # wieder „Haltung des Anführers“
	tm.add_waypoint(ash, wp2)
	check((tm.plans.get(ash, []) as Array).size() == 2, "Zwei Wegpunkte im Plan des Soldaten")
	var ab := m.squad.brain_of(ash)
	check(ab.order == SquadBrain.Order.MOVE and ab.plan and ab.hold_pos.distance_to(wp1) < 0.5 and ab.stance_override == Soldier.Stance.CROUCH,
		"Erster Wegpunkt sofort als Bewegungsbefehl (geduckt)")
	# Wegpunkt markieren und Gangart ändern
	tm._click(tm._cam.unproject_position(wp2), false)
	tm.press_button("walk")
	check(String(tm.plans[ash][1]["gait"]) == "walk", "Markierter Wegpunkt: Gangart GEHEN gesetzt")
	await tap("tactical_map")
	check(not tm.is_open and not get_tree().paused, "Karte geschlossen")
	var p0 := ash.global_position
	for i in 1800:
		await frames(1)
		if tm.waiting.has(ash):
			break
	check(tm.waiting.get(ash, 0) == 1 and ash.global_position.distance_to(wp1) < 2.5, "Wartet am Signal-Wegpunkt 1",
		"%.1f m, bewegt %.1f m, Auftrag %d plan %s, Haltung %d, Modus %d" % [ash.global_position.distance_to(wp1),
		ash.global_position.distance_to(p0), ab.order, ab.plan, ash.stance, ash.move_mode])
	await seconds(1.0)
	check(ash.stance == Soldier.Stance.CROUCH, "Haltung am Wegpunkt: geduckt")
	check(ash.global_position.distance_to(wp1) < 2.5, "Bleibt ohne Signal stehen")
	check(tm.send_signal(2) == 0 and tm.send_signal(1) == 1, "Signal 2 lässt ihn warten, Signal 1 gibt ihn frei")
	check(ab.quiet and ab.hold_pos.distance_to(wp2) < 0.5, "Zweiter Wegpunkt: GEHEN (leise)")
	for i in 1800:
		await frames(1)
		if not tm.plans.has(ash):
			break
	check(not tm.plans.has(ash) and ab.order == SquadBrain.Order.HOLD and ash.global_position.distance_to(wp2) < 3.0,
		"Planende: Soldat hält am letzten Wegpunkt", "%.1f m" % ash.global_position.distance_to(wp2))
	# Fehlerbericht 23.10.2026: Kartenbefehl bleibt bestehen, auch wenn der Anführer wegläuft (20 s, kein Folgen)
	var pa := ash.global_position
	var hp0 := hale.global_position
	Input.action_press("move_back")
	await seconds(6.0)
	Input.action_release("move_back")
	await seconds(14.0)
	check(ab.order == SquadBrain.Order.HOLD and ash.global_position.distance_to(pa) < 1.5 and hale.global_position.distance_to(hp0) > 8.0,
		"Planende: nach 20 s hält er noch am Wegpunkt (Anführer läuft weg)",
		"%.1f m, Anführer %.1f m" % [ash.global_position.distance_to(pa), hale.global_position.distance_to(hp0)])
	place(hale, 0, 30, 0.0)
	# Löschen
	tm.add_waypoint(ash, wp1)
	tm.selected.clear()
	tm.selected.append(ash)
	tm.press_button("deleteall")
	check(not tm.plans.has(ash) and ab.order == SquadBrain.Order.HOLD, "ALLE LÖSCHEN verwirft den Plan")

	# --- HUD-Lücken (GAP Abschnitt 4): Zeitzünder-Liste, Waffensymbole aller Originalwaffen ---
	var oh = get_tree().root.find_child("OrigHud", true, false)
	if oh:
		var pc := PlacedCharge.new()
		pc.kind = "explosive"
		m.add_child(pc)
		pc.global_position = m.lb.ground(-40, 60)
		await seconds(0.8)
		check(oh.timers_shown.size() >= 1 and float(oh.timers_shown[0][1]) < PlacedCharge.FUSE,
			"Zeitzünder-Liste (timer-explosive): Ladung mit Restzeit", str(oh.timers_shown))
		pc.queue_free()
		# Verwundungs-Overlay „injury“ mit AnimHit-Videotextur bei Treffern am aktiven Soldaten
		if Game.movie_path("AnimHit1") != "":
			for i in 20:
				hale.damaged.emit(1.0, &"torso")
				await frames(1)
				if oh.injury.visible:
					break
			check(oh.injury.visible and String(oh.injury_film).begins_with("AnimHit"), "Treffer: Verwundungs-Overlay (AnimHit-Film)",
				String(oh.injury_film))
			var amax := 0.0
			for i in 30:
				await frames(1)
				amax = maxf(amax, oh.injury_alpha)
			check(amax > 0.45 and amax <= 0.5001, "Overlay blendet auf 0,5 ein (Original +4/s)", "%.2f" % amax)
			await seconds(1.6)
			check(not oh.injury.visible, "Overlay blendet in 1 s aus (−0,5/s)")
		var dl := WeaponDB.from_orig(7)
		# Symbol über den Originalgegenstand (OrigHud seit dem Waffenbild-Feld 0x4A9530: weapon_item → items.sav „icon“)
		var dl_icon: String = oh._item_icon_file(OrigHud.weapon_item(Weapon.new(dl, false))) if dl else ""
		check(dl != null and dl_icon != "", "Waffensymbol auch für De Lisle (aus items.sav-Symbol)", dl_icon if dl else "-")
	else:
		check(false, "OrigHud vorhanden (Originaldaten-Cache)")

	# --- Original-Pausemenü (main ingame.4ds) mit Spielstandliste ---
	await tap("pause")
	await frames(2)
	var pm := m.get_node("PauseMenu")
	var ids := {"Continue": 2511, "Restart": 2515, "Save": 2512, "Load": 2513, "Options": 2514, "MainMenu": 2516}
	var all_ok := true
	for n in ids:
		var b := pm.find_child(n, true, false) as Button
		all_ok = all_ok and b != null and b.text == SAS.text(ids[n], "?")
	check(all_ok and get_tree().paused, "Pausemenü: Originalknöpfe 2511/2515/2512/2513/2514/2516")
	var used0 := Game.saves_used
	pm.open_saves("save")
	await frames(2)
	check(pm.find_child("SaveNew", true, false) != null and pm.find_child("SavesHeader", true, false) != null,
		"SPEICHERN: Spielstandliste mit „Neuer Spielstand“ und freien Plätzen (T9526)")
	pm._saves_action()
	await frames(2)
	check(Game.saves_used == used0 + 1 and Game.saves_left() == Game.SAVES_PER_MISSION_HARD - Game.saves_used,
		"Gespeichert; Speicherplätze je Einsatz gezählt (Schwer: 3)", "%d genutzt" % Game.saves_used)
	var listed := Game.list_saves().filter(func(e): return String(e["mission"]) == Game.current_mission_id)
	check(not listed.is_empty() and String(listed[0]["slot"]).begins_with(Game.mode_prefix()), "Spielstandliste enthält den Stand (Modus-Präfix)",
		String(listed[0]["slot"]) if not listed.is_empty() else "-")
	Game.saves_used = Game.SAVES_PER_MISSION_HARD
	check(Game.can_save() != "" and not Game.save_game("autotest_full"), "Keine freien Plätze: Speichern abgelehnt (T9526)")
	Game.saves_used = used0 + 1
	await tap("pause")
	pm.open()
	await frames(2)
	pm.open_saves("load")
	await frames(2)
	var row: Node = null
	for c in pm.find_children("SaveRow_*", "Button", true, false):
		row = c
		break
	check(row != null, "LADEN: Spielstände in der Liste")
	for e in listed:
		Game.delete_save(String(e["slot"]))
	pm.close()
	_finish()
