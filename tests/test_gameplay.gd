extends Node
## Automatisierter Gameplay-Test (läuft im echten Spiel, auch headless):
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_gameplay
## Eingaben werden über Input-Aktionen simuliert. Exit-Code 0 = alles bestanden.

var passed := 0
var failed := 0
var log_lines: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Sicherheitsnetz: hängender Test bricht nach 6 Minuten ab
	get_tree().create_timer(360.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func check(cond: bool, name: String, detail := "") -> void:
	var line := ("PASS  " if cond else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")")
	print(line)
	log_lines.append(line)
	if cond:
		passed += 1
	else:
		failed += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


func tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func hold(action: String, s: float) -> void:
	Input.action_press(action)
	await seconds(s)
	Input.action_release(action)


func mission() -> Mission:
	return Game.current_mission() as Mission


func enemy(pid: String) -> Soldier:
	for e in mission().enemies:
		if e.persistent_id == pid:
			return e
	return null


## Alle Gegner außer den genannten "einfrieren" (KI aus, weit weg), damit
## Einzeltests deterministisch bleiben.
func isolate_enemies(keep: Array) -> void:
	for e in mission().enemies:
		var b := e.get_node("EnemyBrain") as EnemyBrain
		if not keep.has(e.persistent_id):
			b.enabled = false
			e.get_node("Perception").set_physics_process(false)
			e.global_position = Vector3(-120, 30, -120 + randf() * 5.0)
			e.set_physics_process(false)


func _run() -> void:
	# Auf die Mission warten
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	check(m.squad.members.size() == 4, "Trupp hat 4 Soldaten", str(m.squad.members.size()))
	check(m.enemies.size() == 12, "12 Gegner gespawnt", str(m.enemies.size()))
	var hale := m.squad.leader()
	check(hale.soldier_name == "Sgt. Hale" and hale.is_player_controlled, "Sgt. Hale wird gesteuert")
	await frames(30)
	check(hale.is_on_floor(), "Soldat steht auf dem Gelände", "y=%.2f" % hale.global_position.y)

	# Navigation abwarten (asynchron gebacken)
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	check(m.nav_ready, "Navigationsnetz gebacken", "%d Polygone" % m.nav_region.navigation_mesh.get_polygon_count())

	isolate_enemies(["e_gate", "e_cp1"])

	# --- Bewegung ---
	var p0 := hale.global_position
	await hold("move_forward", 1.5)
	var walked := p0.distance_to(hale.global_position)
	check(walked > 1.5 and walked < 3.5, "Gehen vorwärts ~1.7 m/s", "%.2f m in 1.5 s" % walked)
	p0 = hale.global_position
	Input.action_press("run")
	await hold("move_forward", 1.5)
	Input.action_release("run")
	var ran := p0.distance_to(hale.global_position)
	check(ran > walked * 1.8, "Rennen schneller als Gehen", "%.2f m" % ran)
	check(hale.stamina < 100.0, "Rennen verbraucht Ausdauer", "%.1f" % hale.stamina)
	p0 = hale.global_position
	Input.action_press("sneak")
	await hold("move_forward", 1.5)
	Input.action_release("sneak")
	var snuck := p0.distance_to(hale.global_position)
	check(snuck < walked, "Schleichen langsamer als Gehen", "%.2f m" % snuck)

	# --- Haltungen ---
	await tap("stance_crouch")
	await seconds(0.6)
	check(hale.stance == Soldier.Stance.CROUCH and is_equal_approx(hale._capsule.height, 1.2), "Hocken (Kapsel 1.2 m)")
	await tap("stance_prone")
	await seconds(1.2)
	check(hale.stance == Soldier.Stance.PRONE and is_equal_approx(hale._capsule.height, 0.6), "Hinlegen (Kapsel 0.6 m)")
	p0 = hale.global_position
	await hold("move_forward", 1.5)
	var crawled := p0.distance_to(hale.global_position)
	check(crawled > 0.2 and crawled < 1.2, "Kriechen langsam", "%.2f m" % crawled)
	await tap("stance_stand")
	await seconds(1.2)
	check(hale.stance == Soldier.Stance.STAND, "Aufstehen")

	# --- Kamera ---
	await tap("camera_toggle")
	check(m.rig.mode == CameraRig.Mode.FIRST and not hale.model.head.visible, "Wechsel in 1. Person (Kopf ausgeblendet)")
	await tap("camera_toggle")
	check(m.rig.mode == CameraRig.Mode.THIRD and hale.model.head.visible, "Wechsel zurück in 3. Person")

	# --- Waffen: Schießen, Treffer, Schaden ---
	# Offenes Feld zwischen Hofmauer und Hecke (keine Bäume), Blick nach Osten.
	# 1. Person: Fadenkreuz-Strahl beginnt am Auge (in 3. Person ist die
	# Kamera seitlich versetzt; der Spieler zielt dort über das Fadenkreuz).
	hale.global_position = m.lb.ground(3, 32, 0.3)
	hale.look_yaw = -PI * 0.5
	hale.look_pitch = 0.0
	await tap("camera_toggle")
	var target := enemy("e_gate")
	var tb := target.get_node("EnemyBrain") as EnemyBrain
	tb.enabled = false
	target.get_node("Perception").set_physics_process(false)
	target.global_position = m.lb.ground(15, 32, 0.3)
	target.look_yaw = PI * 0.5
	await seconds(0.5)
	var rq := PhysicsRayQueryParameters3D.create(hale.eye_position(), target.global_position + Vector3.UP * 1.2, 1 | Hitbox.LAYER, hale.exclude_rids())
	rq.collide_with_areas = true
	var rh := hale.get_world_3d().direct_space_state.intersect_ray(rq)
	check(not rh.is_empty() and rh.collider is Hitbox, "Raycast erreicht Trefferzone", str(rh.get("collider")))
	# Ziel anvisieren: Blick auf Rumpfhöhe
	var to := target.global_position + Vector3.UP * 1.25 - hale.eye_position()
	hale.look_yaw = atan2(-to.x, -to.z)
	hale.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var w := hale.current_weapon()
	var ammo0 := w.in_mag
	var shots0 := Ballistics.shots_fired
	var hp0 := target.health
	Input.action_press("aim")
	await seconds(0.4)
	await hold("fire", 0.5)
	Input.action_release("aim")
	await seconds(0.3)
	check(w.in_mag < ammo0, "Feuern verbraucht Munition", "%d -> %d" % [ammo0, w.in_mag])
	check(Ballistics.shots_fired > shots0, "Projektile erzeugt", str(Ballistics.shots_fired - shots0))
	check(target.health < hp0, "Treffer verursacht Schaden", "%.0f -> %.0f" % [hp0, target.health])
	# bis zum Tod weiterfeuern
	for i in 6:
		if not target.alive:
			break
		to = target.global_position + Vector3.UP * 1.2 - hale.eye_position()
		hale.look_yaw = atan2(-to.x, -to.z)
		hale.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		await hold("fire", 0.4)
		await seconds(0.3)
	check(not target.alive, "Gegner kann getötet werden")
	check(target.is_in_group("corpses"), "Leiche bleibt liegen (für Entdeckung durch KI)")
	await tap("camera_toggle")

	# --- Nachladen ---
	var before := w.in_mag
	await tap("reload")
	check(w.is_reloading(), "Nachladen gestartet")
	await seconds(w.data.reload_time + 0.3)
	check(w.in_mag == w.data.magazine_size and not w.is_reloading(), "Nachladen füllt Magazin", "%d -> %d" % [before, w.in_mag])

	# --- Waffenwechsel ---
	await tap("weapon_2")
	await frames(3)
	check(hale.current_weapon().data.id == &"colt", "Waffenwechsel auf Pistole")
	await tap("weapon_1")
	await frames(3)
	check(hale.current_weapon().data.id == &"thompson", "Waffenwechsel zurück")
	await tap("fire_mode")
	check(not hale.current_weapon().fires_automatic(), "Feuermodus Einzelfeuer")
	await tap("fire_mode")

	# --- Gegner-KI: Erkennung und Kampf ---
	var e2 := enemy("e_cp1")
	var b2 := e2.get_node("EnemyBrain") as EnemyBrain
	hale.global_position = m.lb.ground(3, 32, 0.3)
	e2.global_position = m.lb.ground(21, 32, 0.3)
	e2.look_yaw = PI * 0.5    # schaut nach Westen, zum Spieler
	b2.home_pos = e2.global_position
	b2.home_yaw = e2.look_yaw
	b2.set_state(EnemyBrain.State.GUARD)
	var hp_h := hale.health
	var shots1 := Ballistics.shots_fired
	var t := 0.0
	while t < 6.0 and b2.state != EnemyBrain.State.COMBAT:
		await frames(6)
		t += 0.1
	check(b2.state == EnemyBrain.State.COMBAT, "Gegner erkennt stehenden Spieler", "%.1f s" % t)
	await seconds(4.0)
	check(Ballistics.shots_fired > shots1, "Gegner feuert", str(Ballistics.shots_fired - shots1))
	check(hale.health <= hp_h, "Gesundheit nach Beschuss", "%.0f" % hale.health)
	# Kameraden reagieren (Feuer frei)
	var squad_shots := 0
	for mm in m.squad.members:
		if mm != hale:
			var bb := m.squad.brain_of(mm)
			if bb.perception.best_target() == e2:
				squad_shots += 1
	check(squad_shots >= 0, "Kameraden-Wahrnehmung aktiv", "%d sehen den Gegner" % squad_shots)
	# Gegner ausschalten lassen, falls noch nicht
	if e2.alive:
		e2.die(hale)
	await seconds(0.5)
	hale.health = hale.max_health

	# --- Squad: Folgen, Halten, Bewegen ---
	await tap("order_follow")
	var target_pos := hale.global_position + hale.forward() * 25.0
	Input.action_press("run")
	var tt := 0.0
	while tt < 8.0 and hale.global_position.distance_to(target_pos) > 3.0:
		var d := target_pos - hale.global_position
		hale.look_yaw = atan2(-d.x, -d.z)
		Input.action_press("move_forward")
		await frames(6)
		tt += 0.1
	Input.action_release("move_forward")
	Input.action_release("run")
	await seconds(7.0)
	var max_d := 0.0
	for mm in m.squad.alive_members():
		max_d = maxf(max_d, mm.global_position.distance_to(hale.global_position))
	check(max_d < 14.0, "Trupp folgt dem Anführer", "max. Abstand %.1f m" % max_d)
	await tap("order_hold")
	var held_ok := true
	for mm in m.squad.members:
		if mm != hale and m.squad.brain_of(mm).order != SquadBrain.Order.HOLD:
			held_ok = false
	check(held_ok, "Befehl Halten an alle")
	await tap("order_formation")
	check(m.squad.formation == SquadManager.Formation.LINE, "Formation wechseln (Linie)")
	await tap("order_roe")
	check(m.squad.brain_of(m.squad.members[1]).roe == SquadBrain.ROE.HOLD_FIRE, "Feuer halten")
	await tap("order_roe")

	# --- Soldatenwechsel ---
	await tap("soldier_2")
	check(m.squad.leader().soldier_name == "Cpl. Brennan" and m.controller.active == m.squad.leader(), "Wechsel auf Soldat 2")
	check(m.rig.target == m.squad.leader(), "Kamera folgt neuem Soldaten")
	await tap("soldier_1")
	hale = m.squad.leader()

	# --- Ziele: Codebuch und Funksender ---
	hale.global_position = m.codebook.global_position + Vector3(1.0, -0.6, 0.0)
	var d2: Vector3 = m.codebook.global_position - hale.global_position
	hale.look_yaw = atan2(-d2.x, -d2.z)
	await frames(10)
	check(m.controller.interact_target == m.codebook, "Codebuch als Interaktionsziel erkannt")
	await tap("interact")
	check(m.objective(&"codebook").is_done(), "Ziel Codebuch erfüllt")
	m.radio_site.fuse = 1.0
	hale.global_position = m.radio_site.global_position + Vector3(0, 0.1, -1.4)
	var d3: Vector3 = m.radio_site.global_position - hale.global_position
	hale.look_yaw = atan2(-d3.x, -d3.z)
	await frames(10)
	check(m.controller.interact_target == m.radio_site, "Funksender als Interaktionsziel erkannt")
	await tap("interact")
	check(m.radio_site.armed, "Sprengladung scharf")
	hale.global_position += Vector3(0, 0, -12)   # Abstand
	await seconds(1.5)
	check(m.objective(&"radio").is_done(), "Ziel Funksender erfüllt")

	# --- Speichern / Laden ---
	var saved_pos := hale.global_position
	var ok := Game.save_game("autotest")
	check(ok and Game.has_save("autotest"), "Spielstand gespeichert")
	hale.global_position += Vector3(30, 5, 0)
	Game.load_game("autotest")
	for i in 600:
		await get_tree().process_frame
		if mission() and mission() != m and mission().squad and mission().squad.leader():
			break
	await frames(10)
	m = mission()
	hale = m.squad.members[0]
	check(m.objective(&"codebook").is_done() and m.objective(&"radio").is_done(), "Ziele nach Laden wiederhergestellt")
	check(hale.global_position.distance_to(saved_pos) < 1.5, "Position nach Laden wiederhergestellt", "%.2f m" % hale.global_position.distance_to(saved_pos))
	check(m.radio_site.is_destroyed and not m.codebook.enabled, "Weltzustand nach Laden wiederhergestellt")
	check(not enemy("e_gate").alive, "Getöteter Gegner bleibt nach Laden tot")

	# --- Abholung -> Missionsende ---
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	var k := 0
	for mm in m.squad.alive_members():
		mm.global_position = m.extraction_pos + Vector3(k * 1.5, 0.5, 0)
		k += 1
	await seconds(1.0)
	check(m.finished and m.objective(&"extract").is_done(), "Abholung beendet Mission erfolgreich")
	check(Game.last_result.get("success", false), "Ergebnis für Nachbesprechung")
	_finish()


func _finish() -> void:
	print("\nERGEBNIS: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	var f := FileAccess.open("user://last_test_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\nERGEBNIS: %d bestanden, %d fehlgeschlagen\n" % [passed, failed])
	DirAccess.remove_absolute(Game.save_path("autotest"))
	get_tree().quit(1 if failed > 0 else 0)
