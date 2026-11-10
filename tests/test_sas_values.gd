extends "res://tests/test_gameplay.gd"
## 0.10.6: Wirken die SAS-Kaderwerte im Spiel? Je Wert zwei Soldaten (niedrig/hoch) über Game.apply_sas, messbare
## Wirkung vergleichen; dazu Erste-Hilfe-Kit am Kameraden (Fadenkreuz, Reichweite 2 m) im Einzelspieler.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_sas_values


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	isolate_enemies([])
	var camp_saved: Dictionary = Game.campaign.duplicate(true)
	var st := Game.sas_states()
	var lo_stats := {"health": 300.0, "strength": 15.0, "endurance": 10.0, "morale": 20.0, "shooting": 10.0,
		"stealth": 10.0, "first_aid": 10.0, "lockpick": 10.0}
	var hi_stats := {"health": 700.0, "strength": 45.0, "endurance": 95.0, "morale": 95.0, "shooting": 95.0,
		"stealth": 95.0, "first_aid": 95.0, "lockpick": 95.0}
	st["0"]["stats"] = lo_stats.duplicate()
	st["1"]["stats"] = hi_stats.duplicate()
	var base: Vector3 = m.squad.leader().global_position + Vector3(4, 0, 0)
	var lo: Soldier = m.spawn_squad_member(base, 0.0, "Niedrig", ["garand", "colt"], "sas_0")
	Game.apply_sas(lo, "sas_0")
	var hi: Soldier = m.spawn_squad_member(base + Vector3(3, 0, 0), 0.0, "Hoch", ["garand", "colt"], "sas_1")
	Game.apply_sas(hi, "sas_1")
	await frames(3)

	# Übernahme auf die Figur (Missionsstart wie spawn_roster)
	check(is_equal_approx(lo.skill_shooting, 10.0) and is_equal_approx(hi.skill_stealth, 95.0)
		and is_equal_approx(hi.skill_endurance, 95.0) and is_equal_approx(lo.skill_first_aid, 10.0)
		and is_equal_approx(float(hi.get_meta("lockpick")), 95.0) and int(lo.get_meta("sas")) == 0,
		"Übernahme: Schießen/Tarnung/Ausdauer/Erste Hilfe/Schlösser auf die Figur")
	# Gesundheit: HumanStore-zotti × 0,1 wie Gegner
	check(is_equal_approx(lo.max_health, 30.0) and is_equal_approx(hi.max_health, 70.0) and is_equal_approx(hi.health, 70.0),
		"Gesundheit: 300 → 30 LP, 700 → 70 LP", "%.1f / %.1f" % [lo.max_health, hi.max_health])
	# Spielstand: Werte überstehen Speichern/Laden (Figur neu gespawnt + apply_sas, dann deserialize)
	var sd := hi.serialize()
	hi.deserialize(sd)
	check(is_equal_approx(hi.skill_shooting, 95.0) and is_equal_approx(hi.max_health, 70.0), "Laden: Kaderwerte bleiben erhalten")

	# Schießen → Streuung
	for s in [lo, hi]:
		s.select_slot(0)
		s.aiming = true
		s.stamina = 100.0
		s.velocity = Vector3.ZERO
	await frames(2)
	var sp_lo := lo.current_spread()
	var sp_hi := hi.current_spread()
	check(sp_lo > 0.0 and sp_hi < sp_lo * 0.6, "Schießen: hoher Wert streut deutlich weniger", "%.3f° / %.3f°" % [sp_lo, sp_hi])

	# Tarnung → Erkennungszeit (Sichtbarkeit je Sekunde, 1/vis ≈ Sekunden bis Erkennung)
	var per: Perception = m.squad.leader().get_node("Perception")
	var v_lo := per._visibility(lo, 20.0, 0.0, 1.0)
	var v_hi := per._visibility(hi, 20.0, 0.0, 1.0)
	check(v_hi > 0.0 and v_lo > v_hi * 1.8, "Tarnung: hoher Wert wird später erkannt",
		"Erkennung %.2f s / %.2f s" % [1.0 / maxf(v_lo, 0.001), 1.0 / maxf(v_hi, 0.001)])

	# Ausdauer → Sprintverbrauch
	check(hi.sprint_cost() < lo.sprint_cost() * 0.6, "Ausdauer: hoher Wert verbraucht beim Rennen weniger",
		"%.1f / %.1f je s" % [lo.sprint_cost(), hi.sprint_cost()])

	# Schlösser → Dauer Schlossknacken
	var lp_lo := OrigInteractive.lockpick_seconds(lo)
	var lp_hi := OrigInteractive.lockpick_seconds(hi)
	check(lp_hi < lp_lo - 3.0, "Schlösser: hoher Wert knackt schneller", "%.1f s / %.1f s" % [lp_lo, lp_hi])

	# Kraft → Traglast/Überladung (Ingame-Inventar und Ausrüstung nutzen FieldInventory.strength)
	var inv := SAS.new_inventory()
	inv["back"] = 100
	SAS.add_item(inv, 29)          # Bren 10,1 kg
	check(is_equal_approx(FieldInventory.strength(lo), 15.0) and is_equal_approx(FieldInventory.strength(hi), 45.0)
		and not SAS.can_add(inv, FieldInventory.strength(lo), 29) and SAS.can_add(inv, FieldInventory.strength(hi), 29),
		"Kraft: zweites Bren (20,2 kg) überlädt Kraft 15, nicht Kraft 45")

	# Erste Hilfe → Verbandswirkung
	lo.medkits = 2
	hi.medkits = 2
	var pat: Soldier = m.squad.members[0] if m.squad.members[0] != lo and m.squad.members[0] != hi else m.squad.members[1]
	pat.health = 5.0
	var a_lo := lo.apply_bandage(pat)
	pat.health = 5.0
	var a_hi := hi.apply_bandage(pat)
	check(a_hi > a_lo * 1.5 and lo.medkits == 1 and hi.medkits == 1, "Erste Hilfe: hoher Wert heilt mehr je Verband",
		"+%.1f / +%.1f" % [a_lo, a_hi])

	# Moral: Kaderwert ohne Wirkung auf eigene Figuren (Original-Wirkung nicht belegt) – nur dokumentiert
	check(float(Game.sas_states()["1"]["stats"]["morale"]) == 95.0, "Moral: Kaderwert gespeichert (keine Spielwirkung, s. Status)")

	# --- 0.10.6: Erste-Hilfe-Kit in der Hand, Kamerad am Fadenkreuz anklicken ---
	var c: PlayerController = m.controller
	c.set_active(hi)
	hi.look_yaw = 0.0
	pat.global_position = hi.global_position + Vector3(0, 0, -1.5)    # Blickrichtung yaw 0 = −z
	pat.health = 10.0
	hi.health = hi.max_health
	await frames(2)
	hi.apply_selection("medkit")
	check(hi.tool == "medkit", "Erste-Hilfe-Kit in der Hand")
	check(hi.aimed_comrade(2.0) == pat, "Kamerad am Fadenkreuz in Reichweite erkannt")
	hi.use_tool()
	check(hi.heal_target == pat and hi.heal_time_left > 0.0, "Linksklick: Verband am Kameraden beginnt (Fortschritt/Animation)")
	await seconds(Soldier.HEAL_DURATION + 0.6)
	check(pat.health > 10.0 + hi.bandage_amount() - 1.0 and hi.medkits == 0, "Verband wirkt am Kameraden nach Erste-Hilfe-Wert",
		"%.1f LP" % pat.health)
	# außer Reichweite: niemand wird versorgt
	hi.medkits = 1
	hi.apply_selection("medkit")
	pat.global_position = hi.global_position + Vector3(0, 0, -3.5)
	pat.health = 10.0
	await frames(2)
	check(hi.aimed_comrade(2.0) == null, "Kamerad 3,5 m entfernt: außer Reichweite")
	hi.use_tool()
	check(hi.heal_time_left <= 0.0, "Kein Verband außer Reichweite (selbst unverletzt)")
	# Tod während des Verbands → Kasten weg, auch in der Ego-Ansicht nach dem Soldatenwechsel
	var rig := get_tree().root.find_children("*", "CameraRig", true, false)
	var cam: CameraRig = rig[0] if not rig.is_empty() else null
	if cam:
		cam.set_target(hi)
	hi.medkits = 1
	hi.health = 10.0
	check(hi.start_heal([]) and hi.heal_time_left > 0.0, "Selbstverband beginnt")
	await frames(2)
	hi.die()
	await frames(2)
	check(hi.heal_time_left <= 0.0, "Tod beim Verband: Verband abgebrochen")
	if cam:
		cam.set_target(pat)
		await frames(2)
		check(not is_instance_valid(cam._vm_prop), "Soldatenwechsel: Ego-Ansicht ohne Verbandskasten")

	Game.campaign = camp_saved
	_finish()
