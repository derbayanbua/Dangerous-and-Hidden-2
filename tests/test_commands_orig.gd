extends "res://tests/test_gameplay.gd"
## Truppbefehle in einer Original-Kampagnenmission mit echten Spielereingaben (Fehlerbericht 23.10.2026
## „Soldaten-Befehle funktionieren im Single Player nicht, die folgen immer nur“): Befehlsmenü (Ziffernblock), taktische
## Karte per Mausklick, Soldatenwechsel; jeder Befehl muss nach 20 s Spielzeit noch bestehen.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_commands_orig
##   Fenster mit Kontrollbildern: tools\godot.cmd -- --mission=a1_blizzard --autoplay=test_commands_orig --shots=1
##     → test_output/sp_befehle_*.png

var _shots := false


## Originalmission mit 7 × 20 s Spielzeit: längeres Sicherheitsnetz als die 6 min der Basis (Laden unter Last bis 90 s)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(720.0, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k as Key
	ev.keycode = k as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	for i in 3:
		await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in 3:
		await get_tree().process_frame


## pos in Bildschirmkoordinaten der Oberfläche → Fensterkoordinaten (wie echte Mausereignisse)
func click(view_pos: Vector2) -> void:
	var pos: Vector2 = get_viewport().get_final_transform() * view_pos
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	for i in 3:
		await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in 3:
		await get_tree().process_frame


func menu(open_key: int, digits: Array) -> void:
	await key(open_key)
	for d in digits:
		await key(KEY_0 + int(d))


func shot(name: String) -> void:
	if not _shots:
		return
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://test_output/sp_befehle_%s.png" % name))
	print("BILD test_output/sp_befehle_%s.png" % name)


## Spieler läuft s Sekunden in eine Richtung (echte Bewegungstaste)
func walk(action: String, s: float) -> void:
	Input.action_press(action)
	await seconds(s)
	Input.action_release(action)


func moved(p0: Dictionary, s: Soldier) -> float:
	return s.global_position.distance_to(p0[s])


func _run() -> void:
	_shots = Game.cli.has("shots")
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen (%s)" % Game.current_mission_id)
	for i in 3000:
		if m.nav_ready:
			break
		await frames(1)
	# Zwischensequenzen wie ein Spieler mit der Leertaste überspringen (wie test_movie_skip: erst warten, bis die
	# Einsatz-Intro wirklich läuft – im Fenster startet sie später als ohne Fenster)
	for i in 600:
		var rt0 = m.get("runtime")
		if (rt0 and bool(rt0.get("in_cutscene"))) or m.elapsed > 12.0:
			break
		await frames(1)
	await seconds(1.5)
	for i in 60:
		var rt = m.get("runtime")
		if m.controller.input_enabled and not (rt and bool(rt.get("in_cutscene"))):
			break
		await key(KEY_SPACE)
		await seconds(0.5)
	for j in 2:
		await seconds(2.0)
		for i in 20:
			var rt2 = m.get("runtime")
			if not (rt2 and bool(rt2.get("in_cutscene"))):
				break
			await key(KEY_SPACE)
			await seconds(0.5)
	check(m.controller.input_enabled, "Steuerung frei (Zwischensequenz übersprungen)")
	# Landung abwarten (ARCTIC1 beginnt mit dem Absprung): alle Soldaten am Boden und ruhig
	var calm := 0.0
	for i in 120:
		var ok := true
		for s in m.squad.members:
			ok = ok and s.is_on_floor() and absf(s.velocity.y) < 0.5
		calm = calm + 0.5 if ok else 0.0
		if calm >= 3.0:
			break
		await seconds(0.5)
	for e in m.enemies:          # Gegner ruhen, damit kein Gefecht die Befehle überlagert
		var eb = e.get_node_or_null("EnemyBrain")
		if eb:
			eb.enabled = false
		e.set_physics_process(false)
		var per := e.get_node_or_null("Perception")
		if per:
			per.set_physics_process(false)
	var sq := m.squad
	var lead := sq.leader()
	var mates: Array[Soldier] = []
	for s in sq.alive_members():
		if s != lead:
			mates.append(s)
	check(mates.size() >= 2, "Trupp mit Kameraden", str(mates.size()))
	if mates.size() < 2:
		_finish()
		return
	# Testvorbereitung: Anführer neben den ersten Kameraden (feste, freie Ausgangslage für die Laufwege der Befehle;
	# vom eigenen Landeplatz aus reichten die Laufwege nicht). Früher nur nötig, weil er nach dem Intro im Flugzeug hing.
	if true:
		lead.global_position = mates[0].global_position + Vector3(2.0, 0.5, 0.0)
		lead.velocity = Vector3.ZERO
		await seconds(1.0)

	# --- Folgen (Grundzustand) ---
	await menu(KEY_KP_0, [1, 1])
	var p0 := {}
	for s in mates:
		p0[s] = s.global_position
	await walk("move_forward", 6.0)
	await seconds(3.0)
	var fol := true
	var info := []
	for s in mates:
		info.append("%s %.1f m" % [s.soldier_name, moved(p0, s)])
		fol = fol and sq.brain_of(s).order == SquadBrain.Order.FOLLOW and moved(p0, s) > 5.0
	check(fol, "Bewegung › Folgt mir: Kameraden laufen mit", ", ".join(info))

	# --- Halt: 20 s, Anführer läuft weg ---
	await menu(KEY_KP_0, [1])
	await shot("menue_bewegung")
	await key(KEY_4)
	for s in mates:
		p0[s] = s.global_position
	await walk("move_forward", 8.0)
	await seconds(12.0)
	var held := true
	info = []
	for s in mates:
		info.append("%s %d %.1f m" % [s.soldier_name, sq.brain_of(s).order, moved(p0, s)])
		held = held and sq.brain_of(s).order == SquadBrain.Order.HOLD and moved(p0, s) < 1.5
	check(held and lead.global_position.distance_to(mates[0].global_position) > 10.0,
		"Bewegung › Stehen bleiben: nach 20 s stehen alle noch (kein Folgen)", ", ".join(info))
	await shot("halt_20s")

	# --- Dorthin: Fadenkreuzpunkt, Ziel erreicht, Befehl besteht ---
	lead.look_pitch = -0.3
	await seconds(0.3)
	var goal: Vector3 = m.controller.rig.crosshair_point(150.0)
	var far0 := mates[0].global_position.distance_to(goal)
	await menu(KEY_KP_0, [1, 3])
	lead.look_pitch = 0.0
	await walk("move_back", 4.0)
	await seconds(16.0)
	var there := true
	info = []
	for s in mates:
		var d := Vector2(s.global_position.x - goal.x, s.global_position.z - goal.z).length()
		info.append("%s %d %.1f m" % [s.soldier_name, sq.brain_of(s).order, d])
		there = there and sq.brain_of(s).order == SquadBrain.Order.MOVE and d < 4.0
	check(there and far0 > 8.0, "Bewegung › Dorthin: nach 20 s am Fadenkreuzpunkt, Befehl besteht",
		"Start %.1f m; %s" % [far0, ", ".join(info)])

	# --- Feuer einstellen / Feuer frei (Angriff) ---
	await menu(KEY_KP_0, [2, 2])
	var hf := true
	for s in mates:
		hf = hf and sq.brain_of(s).roe == SquadBrain.ROE.HOLD_FIRE
	await seconds(20.0)
	for s in mates:
		hf = hf and sq.brain_of(s).roe == SquadBrain.ROE.HOLD_FIRE
	check(hf, "Angriff › Feuer einstellen bleibt 20 s bestehen")
	await menu(KEY_KP_0, [2, 1])
	check(sq.brain_of(mates[0]).roe == SquadBrain.ROE.FIRE_AT_WILL, "Angriff › Nach Belieben feuern")

	# --- Einzelbefehl: Ziffernblock 2 = Soldat auf Teamplatz 2 hält Position, die anderen folgen ---
	var two := sq.members[1]
	await menu(KEY_KP_0, [1, 1])
	await menu(KEY_KP_2, [1, 5])
	var p2 := two.global_position
	for s in mates:
		p0[s] = s.global_position
	await walk("move_forward", 6.0)
	await seconds(14.0)
	var others := true
	for s in mates:
		if s != two:
			others = others and sq.brain_of(s).order == SquadBrain.Order.FOLLOW and s.global_position.distance_to(lead.global_position) < 12.0
	check(sq.brain_of(two).order == SquadBrain.Order.HOLD and two.global_position.distance_to(p2) < 1.5 and others,
		"Einzelbefehl an Soldat 2 (Position halten) bleibt 20 s, die anderen folgen",
		"%s %.1f m; andere: %s" % [two.soldier_name, two.global_position.distance_to(p2), str(mates.filter(func(x): return x != two).map(func(x): return "%s %d %.1f" % [x.soldier_name, sq.brain_of(x).order, moved(p0, x)]))])

	# --- Haltung über die taktische Karte, Wegpunkt per Mausklick (echte Klicks) ---
	var tm = m.tactical_map
	var walker: Soldier = mates[mates.size() - 1] if mates[mates.size() - 1] != two else mates[0]
	await key(KEY_M)
	check(tm.is_open, "Taktische Karte offen (M)")
	await get_tree().process_frame
	await click(tm._cam.unproject_position(walker.global_position))
	check(tm.selected.has(walker), "Karte: Soldat per Klick gewählt", "Bild %s, Marker %s" % [get_viewport().get_visible_rect().size, tm._cam.unproject_position(walker.global_position)])
	tm.press_button("kneel")
	var wp: Vector3 = walker.global_position + Vector3(8.0, 0.0, -6.0)
	var sp: Vector2 = tm._cam.unproject_position(wp)
	await click(sp)
	var plan_ok: bool = tm.plans.has(walker) and sq.brain_of(walker).order == SquadBrain.Order.MOVE
	var wp_real: Vector3 = tm.plans[walker][0]["pos"] if plan_ok else wp
	check(plan_ok, "Karte: Wegpunkt per Klick gesetzt (geduckt)")
	await shot("taktische_karte")
	tm.press_button("kneel")
	await key(KEY_M)
	check(not tm.is_open, "Karte geschlossen")
	await walk("move_back", 5.0)
	await seconds(15.0)
	var dw := Vector2(walker.global_position.x - wp_real.x, walker.global_position.z - wp_real.z).length()
	check(dw < 3.0 and sq.brain_of(walker).order == SquadBrain.Order.HOLD and walker.stance == Soldier.Stance.CROUCH,
		"Karte: Wegpunkt erreicht, nach 20 s hält er dort geduckt (kein Folgen)",
		"%.1f m, Befehl %d, Haltung %d" % [dw, sq.brain_of(walker).order, walker.stance])

	# --- Soldatenwechsel (F3): abgegebener Soldat und seine Folger bleiben stehen (hd2.exe 0x4593E0) ---
	await menu(KEY_KP_0, [1, 1])
	await seconds(2.0)
	# B-003: erst wechseln, wenn die Folger ihren Platz erreicht haben (bis 10 s) – vorher lief z. B. der Kartenläufer
	# noch zu seinem Platz und die Strecke bis zum Wechsel zählte fälschlich als „Ausweichen“
	for i in 20:
		var busy := false
		for s in sq.alive_members():
			if s != sq.leader() and Vector2(s.velocity.x, s.velocity.z).length() > 0.3:
				busy = true
		if not busy:
			break
		await seconds(0.5)
	# B-012 (Entscheid Auftraggeber): F3 einmal = markieren, zweimal kurz hintereinander = übernehmen
	await key(KEY_F3)
	await key(KEY_F3)
	var nl := sq.leader()
	# Bezug = Lage im Augenblick des Wechsels (hd2.exe 0x4593E0: die Folger bleiben, wo sie gerade sind)
	var p3 := {}
	for s in sq.alive_members():
		p3[s] = s.global_position
	check(nl == sq.members[2] and m.controller.active == nl, "Soldatenwechsel F3 (2× drücken)", nl.soldier_name)
	await walk("move_forward", 6.0)
	await seconds(14.0)
	var stay := true
	info = []
	for s in sq.alive_members():
		if s == nl:
			continue
		# Diagnose: Versatz bis zum Haltepunkt (vor/bei dem Wechsel) und vom Haltepunkt (danach)
		var hb := sq.brain_of(s)
		info.append("%s %d %.1f m (Halt %.1f/%.1f)" % [s.soldier_name, hb.order, moved(p3, s),
			Vector2(hb.hold_pos.x - p3[s].x, hb.hold_pos.z - p3[s].z).length(), hb.distance_to(hb.hold_pos)])
		stay = stay and sq.brain_of(s).order != SquadBrain.Order.FOLLOW and moved(p3, s) < 1.5
	check(stay, "Soldatenwechsel: niemand fällt auf Folgen zurück (20 s)", ", ".join(info))
	await shot("wechsel_20s")
	await menu(KEY_KP_0, [1, 1])
	await seconds(6.0)
	var fol2 := true
	for s in sq.alive_members():
		if s != nl:
			fol2 = fol2 and sq.brain_of(s).order == SquadBrain.Order.FOLLOW
	check(fol2, "„Folgt mir“ bindet den Trupp an den neuen Soldaten")
	_finish()
