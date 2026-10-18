extends "res://tests/test_gameplay.gd"
## Systemtests: Schleichen, Gehör, Alarm, Leichenfund, Granate, Tür,
## Munitionskiste, Durchsuchen, Lehnen, Missionsfehlschlag.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_systems


func place(s: Soldier, x: float, z: float, yaw: float) -> void:
	s.global_position = mission().lb.ground(x, z, 0.3)
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func reset_enemy(e: Soldier, x: float, z: float, yaw: float) -> EnemyBrain:
	var b := e.get_node("EnemyBrain") as EnemyBrain
	place(e, x, z, yaw)
	e.set_physics_process(true)
	e.get_node("Perception").set_physics_process(true)
	(e.get_node("Perception") as Perception).awareness.clear()
	b.enabled = true
	b.patrol_points = PackedVector3Array()
	b.home_pos = e.global_position
	b.home_yaw = yaw
	b.stop_moving()
	b.set_state(EnemyBrain.State.GUARD)
	return b


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
	# Trupp ruhigstellen: Kameraden halten Feuer und stehen abseits
	var hale := m.squad.leader()
	for mm in m.squad.members:
		if mm != hale:
			var b := m.squad.brain_of(mm)
			b.roe = SquadBrain.ROE.HOLD_FIRE
			b.set_order(SquadBrain.Order.HOLD)
			place(mm, -100 + m.squad.members.find(mm) * 2.0, 100, 0.0)
			b.hold_pos = mm.global_position

	# --- Schleichen: liegend und still auf 30 m bleibt unentdeckt ---
	place(hale, 3, 32, -PI * 0.5)
	hale.stance_request = Soldier.Stance.PRONE
	await seconds(1.5)
	var e1 := enemy("e_cp1")
	var b1 := reset_enemy(e1, 33, 32, PI * 0.5)
	var per1: Perception = e1.get_node("Perception")
	await seconds(3.0)
	var aw_prone: float = per1.awareness.get(hale, 0.0)
	check(b1.state != EnemyBrain.State.COMBAT and aw_prone < 1.0, "Liegend/still auf 30 m: nicht entdeckt", "Erkennung %.2f" % aw_prone)
	hale.stance_request = Soldier.Stance.STAND
	await seconds(1.0)
	var t := 0.0
	while t < 5.0 and b1.state != EnemyBrain.State.COMBAT:
		await frames(6)
		t += 0.1
	check(b1.state == EnemyBrain.State.COMBAT, "Stehend auf 30 m: entdeckt", "%.1f s" % t)
	# HUD-Erkennungsanzeige folgt der Wahrnehmung
	check(per1.max_awareness() >= 1.0, "Erkennungswert erreicht 1.0")
	e1.die(hale)
	await seconds(0.3)

	# --- Gehör: Schuss hinter dem Rücken eines Postens ---
	var e2 := enemy("e_road")
	var b2 := reset_enemy(e2, 23, 32, -PI * 0.5)   # schaut nach Osten (weg vom Spieler)
	await seconds(0.5)
	var w := hale.current_weapon()
	hale.look_pitch = deg_to_rad(30)   # in die Luft
	hale.trigger = true
	await frames(2)
	hale.trigger = false
	Events.emit_noise(hale.global_position, w.data.noise_radius, hale, hale.team, &"gunshot")
	await seconds(0.5)
	check(b2.state != EnemyBrain.State.GUARD, "Posten hört Schuss und reagiert", EnemyBrain.STATE_NAMES[b2.state])
	e2.die(hale)

	# --- Leichenfund ---
	var e3 := enemy("e_yard")
	var b3 := reset_enemy(e3, 3, 45.0, 0.0)  # zunächst weit weg
	var corpse := enemy("e_cp1")
	place(corpse, 60, 70, 0.0)
	place(hale, -60, 80, 0.0)
	await seconds(0.5)
	place(e3, 60, 82, 0.0)        # schaut nach Norden auf die Leiche (12 m)
	b3.home_pos = e3.global_position
	b3.home_yaw = 0.0
	(e3.get_node("Perception") as Perception).known_corpses.clear()
	t = 0.0
	while t < 4.0 and b3.state != EnemyBrain.State.INVESTIGATE:
		await frames(6)
		t += 0.1
	check(b3.state == EnemyBrain.State.INVESTIGATE, "Gegner entdeckt Leiche und untersucht", "%.1f s" % t)
	t = 0.0
	while t < 20.0 and not m.alarm_raised:
		await frames(6)
		t += 0.1
	check(m.alarm_raised, "Leichenfund löst Alarm aus", "%.1f s" % t)
	check(m.objective(&"stealth").state == Objective.State.FAILED, "Optionalziel 'Kein Alarm' verfehlt")
	var searching := 0
	for e in m.enemies:
		var eb := e.get_node("EnemyBrain") as EnemyBrain
		if e.alive and eb.enabled and eb.state == EnemyBrain.State.SEARCH:
			searching += 1
	check(searching >= 1, "Alarm versetzt Gegner in Suche", "%d suchen" % searching)
	isolate_enemies([])

	# --- Granate ---
	var e4 := enemy("e_north")
	var b4 := reset_enemy(e4, 13, 32, PI * 0.5)
	b4.enabled = false
	e4.get_node("Perception").set_physics_process(false)
	e4.health = e4.max_health
	place(hale, 3, 32, -PI * 0.5)
	hale.stance_request = Soldier.Stance.STAND
	await seconds(1.0)
	var g0 := hale.weapons[2].total_ammo()
	var slot0 := hale.current_slot
	hale.look_pitch = deg_to_rad(-10)   # flacher Wurf: landet nach ~12 m
	await tap("grenade")                # Taste G: sofort werfen, ohne Waffenwechsel
	check(hale.weapons[2].total_ammo() == g0 - 1 and hale.current_slot == slot0, "Granate mit G geworfen (Waffe bleibt)",
		"%d -> %d" % [g0, hale.weapons[2].total_ammo()])
	await seconds(5.0)
	check(e4.health < e4.max_health, "Granate verursacht Splitterschaden", "%.0f" % e4.health)
	await tap("weapon_1")

	# --- Tür ---
	var door: Door = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Door:
			door = n
			break
	check(door != null, "Türen vorhanden")
	if door:
		var n := -door.global_basis.z   # vor der Tür stehen
		hale.global_position = door.global_position + n * 1.0 + Vector3.UP * 0.2
		var dd := door.global_position - hale.global_position
		hale.look_yaw = atan2(-dd.x, -dd.z)
		await frames(10)
		var it := m.controller.interact_target
		check(it == door, "Tür als Interaktionsziel", str(it))
		await tap("interact")
		await seconds(0.8)
		check(door.is_open, "Tür öffnet")
		await tap("interact")
		await seconds(0.8)
		check(not door.is_open, "Tür schließt")

	# --- Munitionskiste ---
	var crate: Pickups.AmmoCrate = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Pickups.AmmoCrate:
			crate = n
	hale.weapons[0].reserve = 0
	hale.global_position = crate.global_position + Vector3(0, 0.2, 1.2)
	hale.look_yaw = 0.0
	await frames(10)
	await tap("interact")
	check(hale.weapons[0].reserve > 0, "Munitionskiste füllt Reserve auf", str(hale.weapons[0].reserve))

	# --- Leiche durchsuchen (MP 40 -> Sten, beide 9 mm) ---
	await tap("soldier_4")
	var kow := m.squad.leader()
	check(kow.soldier_name == "Pte. Kowalski", "Wechsel auf Kowalski (Sten)")
	var dead := enemy("e_hq")    # MP 40
	place(dead, 20, 60, 0.0)
	dead.die(null)
	await seconds(1.0)
	kow.weapons[0].reserve = 10
	kow.global_position = dead.global_position + Vector3(0.6, 0.2, 0)
	kow.look_yaw = PI * 0.5
	await frames(10)
	check(m.controller.interact_target is Pickups.Loot, "Leiche als Interaktionsziel")
	await tap("interact")
	# Original: Durchsuchen öffnet das Inventar mit zweitem Inventar (Gegenstände per Maus nehmen, test_inventory)
	var invui: IngameInventory = m.controller.inventory
	check(invui.is_open() and invui.other == dead, "Leiche durchsuchen öffnet das Inventar (zwei Inventare)")
	var mp40mag: int = SAS.ammo_of(OrigHud.weapon_item(dead.weapons[0], dead.team)) if dead.weapons[0] else -1
	if mp40mag >= 0:
		invui.move_item("other", "items", mp40mag, "own", "items")
	check(mp40mag >= 0 and SAS.count_of(FieldInventory.view(kow), mp40mag) > 0, "MP-40-Magazine aus der Leiche übernommen")
	invui.close()

	# --- Lehnen ---
	var eye0 := kow.eye_position()
	Input.action_press("lean_left")
	await frames(10)
	var eye1 := kow.eye_position()
	Input.action_release("lean_left")
	check(kow.lean < 0.0 and eye0.distance_to(eye1) > 0.2, "Lehnen verschiebt Augpunkt", "%.2f m" % eye0.distance_to(eye1))

	# --- Taktische Karte: Pause, Auswahl per Klick, Einzelbefehl ---
	await tap("soldier_1")
	hale = m.squad.leader()
	place(hale, 3, 32, 0.0)
	var ash: Soldier = m.squad.members[2]
	place(ash, 6, 34, 0.0)
	await seconds(0.5)
	var tm = m.tactical_map
	await tap("tactical_map")
	check(tm.is_open and get_tree().paused, "Taktische Karte öffnet und pausiert")
	await get_tree().process_frame
	var sp: Vector2 = tm._cam.unproject_position(ash.global_position)
	tm._click(sp, false)
	check(tm.selected.has(ash), "Soldat per Klick auf der Karte ausgewählt",
		"alive=%s sp=%s vp=%s cam=%s" % [ash.alive, sp, get_viewport().get_visible_rect().size, tm._cam.global_position])
	var goal := m.lb.ground(6, 20)
	tm._click(tm._cam.unproject_position(goal), false)
	var ab := m.squad.brain_of(ash)
	check(ab.order == SquadBrain.Order.MOVE and ab.hold_pos.distance_to(goal) < 2.0, "Bewegungsbefehl per Kartenklick", "%.1f m" % ab.hold_pos.distance_to(goal))
	var ash_pos := ash.global_position
	await get_tree().process_frame
	await get_tree().process_frame
	check(ash.global_position.distance_to(ash_pos) < 0.01, "Während der Karte steht die Zeit still")
	await tap("tactical_map")
	check(not tm.is_open and not get_tree().paused, "Karte schließen setzt Spiel fort")
	await seconds(8.0)
	check(ash.global_position.distance_to(goal) < 3.0, "Soldat führt Kartenbefehl aus", "%.1f m vom Ziel" % ash.global_position.distance_to(goal))

	# --- Kamerad sucht unter Beschuss Deckung ---
	isolate_enemies([])
	place(hale, -2, 36, 0.0)
	var ab2 := m.squad.brain_of(ash)
	place(ash, 8, 32, -PI * 0.5)
	ab2.set_order(SquadBrain.Order.HOLD)
	ab2.roe = SquadBrain.ROE.FIRE_AT_WILL
	# einzige Deckung: Kistenstapel 3 m östlich (Richtung Feind)
	m.lb.box(m.lb.ground(11.5, 32, -0.1), Vector3(1.2, 1.3, 2.4), "wood")
	var shooter := enemy("e_perim")
	var sb := reset_enemy(shooter, 38, 32, PI * 0.5)
	sb.stationary = true
	await seconds(0.2)
	var start_ash := ash.global_position
	ash.apply_hit(5.0, &"arm", shooter, Vector3.LEFT)   # Beschuss auslösen
	t = 0.0
	while t < 8.0 and not (ab2._cover.is_finite() and ash.global_position.distance_to(ab2._cover) < 1.2 and ab2._cover.distance_to(start_ash) > 1.0):
		await frames(6)
		t += 0.1
	check(ab2._cover.is_finite() and ab2._cover.distance_to(start_ash) > 1.0, "Kamerad wählt Deckungsposition", "%s" % ab2._cover)
	var low := ash.global_position + Vector3.UP * 0.9
	var rq2 := PhysicsRayQueryParameters3D.create(shooter.eye_position(), low, 1)
	var blocked := not ash.get_world_3d().direct_space_state.intersect_ray(rq2).is_empty()
	check(blocked, "Kamerad hockend gegen Schützen gedeckt", "%.1f s, Abstand Start %.1f m" % [t, ash.global_position.distance_to(start_ash)])
	sb.enabled = false
	shooter.die(null)

	# --- Gegner wirft Granate auf Ziel hinter Deckung ---
	isolate_enemies([])
	ab2.roe = SquadBrain.ROE.HOLD_FIRE
	place(ash, -100, 100, 0.0)
	ab2.hold_pos = ash.global_position
	hale.max_health = 100000.0
	hale.health = hale.max_health
	# ebene Fläche südlich des Gehöfts (Ebnungszone), Kiste als Deckung
	m.lb.box(m.lb.ground(-10, 20, -0.1), Vector3(1.2, 1.4, 2.6), "wood")
	place(hale, -11.4, 20, -PI * 0.5)         # hinter der Kiste (West-Seite)
	hale.stance_request = Soldier.Stance.CROUCH
	await seconds(1.0)
	var gren := enemy("e_cp2")                 # aggressiv, trägt Stielhandgranaten
	var gb := reset_enemy(gren, 6, 20, PI * 0.5)
	var g_before := gren.weapons[2].total_ammo()
	(gren.get_node("Perception") as Perception).last_known[hale] = hale.global_position
	gb.target = hale
	gb.set_state(EnemyBrain.State.COMBAT)
	t = 0.0
	while t < 15.0 and gren.weapons[2].total_ammo() == g_before:
		await frames(6)
		t += 0.1
	check(gren.weapons[2].total_ammo() < g_before, "Gegner wirft Granate auf gedecktes Ziel", "%.1f s" % t)
	await seconds(5.0)
	gb.enabled = false
	gren.die(null)

	# --- Aggressiver Gegner flankiert ---
	place(hale, -20, 22, -PI * 0.5)
	hale.stance_request = Soldier.Stance.STAND
	await seconds(1.0)
	var fl := enemy("e_yard")                  # aggressiv
	var fb := reset_enemy(fl, 8, 22, PI * 0.5)
	fb.ai_mode = EnemyBrain.Mode.AGGRESSIVE
	fl.weapons[2] = null                       # keine Granate, um nur das Flankieren zu prüfen
	var fl_start := fl.global_position
	t = 0.0
	while t < 16.0 and not fb.flank_target.is_finite():
		await frames(6)
		t += 0.1
	check(fb.flank_target.is_finite(), "Aggressiver Gegner wählt Flankenposition", "%.1f s" % t)
	if fb.flank_target.is_finite():
		var to_h := (hale.global_position - fb.flank_origin)
		to_h.y = 0
		var lateral := absf((fb.flank_target - fb.flank_origin).dot(Vector3(-to_h.z, 0, to_h.x).normalized()))
		check(lateral > 4.0, "Flankenposition seitlich versetzt", "%.1f m seitlich" % lateral)
		await seconds(5.0)
		check(fl.global_position.distance_to(fl_start) > 4.0, "Gegner bewegt sich zur Flanke", "%.1f m" % fl.global_position.distance_to(fl_start))
	fb.enabled = false
	fl.die(null)
	hale.max_health = 100.0
	hale.health = 100.0

	# --- Granatbefehl an Kameraden ---
	isolate_enemies([])
	var kowa: Soldier = m.squad.members[3]
	var kb := m.squad.brain_of(kowa)
	place(hale, -22, 22, -PI * 0.5)
	place(kowa, -16, 22, -PI * 0.5)
	kb.set_order(SquadBrain.Order.HOLD)
	for mm in m.squad.members:   # nur Kowalski trägt Granaten
		if mm.weapons.size() > 2:
			mm.weapons[2] = null
	kowa.weapons[2] = Weapon.new(WeaponDB.get_weapon(&"no36"))
	var dummy := enemy("e_north")
	var db := reset_enemy(dummy, 3, 22, PI * 0.5)
	db.enabled = false
	dummy.get_node("Perception").set_physics_process(false)
	dummy.health = dummy.max_health
	await seconds(0.5)
	var kg0 := kowa.weapons[2].total_ammo()
	var thrower := m.squad.order_grenade(dummy.global_position)
	check(thrower == kowa, "Granatbefehl an Kamerad mit Granate", thrower.soldier_name if thrower else "-")
	await seconds(1.0)
	check(kowa.weapons[2].total_ammo() == kg0 - 1, "Kamerad wirft befohlene Granate", "%d -> %d" % [kg0, kowa.weapons[2].total_ammo()])
	await seconds(5.0)
	check(dummy.health < dummy.max_health, "Befohlene Granate trifft das Ziel", "%.0f" % dummy.health)
	dummy.die(null)

	# --- Verbandskasten: selbst, Kamerad, KI-Selbstversorgung ---
	await tap("soldier_1")
	hale = m.squad.leader()
	place(hale, -22, 22, -PI * 0.5)
	hale.health = 40.0
	hale.medkits = 2
	await tap("medkit")
	check(hale.heal_time_left > 0.0 and hale.heal_target == hale, "Verband anlegen (selbst) gestartet")
	await seconds(3.3)
	check(is_equal_approx(hale.health, 85.0) and hale.medkits == 1, "Verband heilt +45", "%.0f HP, %d übrig" % [hale.health, hale.medkits])
	kowa.global_position = hale.global_position + hale.forward() * 1.2
	kb.set_order(SquadBrain.Order.HOLD)
	kowa.health = 30.0
	await frames(5)
	await tap("medkit")
	check(hale.heal_target == kowa, "Verband für verwundeten Kameraden vor einem")
	await seconds(3.3)
	check(kowa.health > 30.0, "Kamerad versorgt", "%.0f HP" % kowa.health)
	var ash3: Soldier = m.squad.members[2]
	var ab3 := m.squad.brain_of(ash3)
	place(ash3, -26, 26, 0.0)
	ab3.set_order(SquadBrain.Order.HOLD)
	ash3.health = 30.0
	ash3.medkits = 1
	await seconds(8.0)
	check(ash3.health > 30.0 and ash3.medkits == 0, "KI-Kamerad versorgt sich selbst", "%.0f HP" % ash3.health)

	# --- Fernglas ---
	place(hale, -22, 22, -PI * 0.5)
	await tap("binoculars")
	await seconds(0.6)
	check(hale.using_binoculars and m.rig.camera.fov < 16.0, "Fernglas: Zoom aktiv", "FOV %.1f" % m.rig.camera.fov)
	var ammo_b := hale.current_weapon().in_mag
	await hold("fire", 0.4)
	check(hale.current_weapon().in_mag == ammo_b, "Mit Fernglas wird nicht geschossen")
	await tap("binoculars")
	await seconds(0.6)
	check(not hale.using_binoculars and m.rig.camera.fov > 50.0, "Fernglas abgesetzt")

	# --- Missionsfehlschlag: ganzer Trupp fällt ---
	for mm in m.squad.members:
		mm.die(null)
	await seconds(0.5)
	check(m.finished and not Game.last_result.get("success", true), "Tod des Trupps beendet Mission als gescheitert")
	_finish()
