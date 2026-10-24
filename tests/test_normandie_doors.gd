extends "res://tests/test_gameplay.gd"
## Türen auf dem Level von „Operation Overlord - Schwerttänzer“ (NORMANDY2; MP-Karte Normandy2 = NORMANDY2_MP_ZONE,
## Arena = mp_arena_no2_schwerttaenzer): alle Original-Türen (scene2.bin Typ 6, interactive.json) per echter
## Benutzen-Taste öffnen/schließen, Durchgang offen frei / zu blockiert, richtige Tür im mehrstöckigen Haus H38;
## Mehrspieler zweiprozessig (tests/test_normandie_doors_client.gd): Spät-Beitritt übernimmt Türzustände, Server-
## und Client-Benutzung (inkl. Doppeltür) kommen beim anderen an.
##   tools\godot.cmd --headless -- --autoplay=test_normandie_doors [--map=mp_normandy2_mp_zone] [--mp=0]
##   Kontrollbilder (Fenster): tools\godot.cmd -- --autoplay=test_normandie_doors --shots=1 --mp=0 --resolution 1280x720
##   → test_output/normandie_door_<tür>_{zu,offen}.png

const RESULT := "user://normandie_doors_client.txt"
const SHOT_DOORS := ["H38_92", "H38_154", "H38_75", "m_banka_45", "m_banka_100", "m_banka_197", "H_door_01"]
## Flügel in scene.4ds schon in offener Lage gespeichert (Startzustand offen; Ecken liegen außerhalb der Zarge H38_91/153)
const STORED_OPEN := ["H38_92", "H38_154"]

var _m: Mission
var _me: Soldier
var _cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	if Game.cli.has("shots"):
		timeout_s *= 6.0          # Fenster auf der VM (WARP): Physik läuft deutlich langsamer als Echtzeit
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


## Standplatz vor einer (geschlossenen) Tür: Seite mit Boden auf Türhöhe (Treppenhausseite kann tiefer liegen).
## Rückgabe [Standpunkt, Normale Stand→Tür, Türmitte, Unterkante]
static func stand_for(m: Mission, d: OrigInteractive.OrigDoor) -> Array:
	var keep: float = d.amount
	d.amount = 0.0
	d._apply()
	var box := OrigInteractive.world_aabb(d.frame)
	d.amount = d.open_amount
	d._apply()
	var open_c := OrigInteractive.world_aabb(d.frame).get_center()
	d.amount = keep
	d._apply()
	var n := Vector3.RIGHT if box.size.x < box.size.z else Vector3.BACK     # dünnste waagrechte Achse = Flügelnormale
	var base_p := Vector3(box.get_center().x, box.position.y + 0.05, box.get_center().z)
	var stand := base_p - n * 1.35
	# zuerst die Seite, zu der der Flügel NICHT aufschwenkt (sonst hält ihn der Soldat auf – wie im Original)
	var away := -1.0 if (open_c - box.get_center()).dot(n) > 0.0 else 1.0
	for sd: float in [away, -away]:
		var cand: Vector3 = base_p + n * sd * 1.35
		var fq := PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 1.0, cand + Vector3.DOWN * 0.4, 1)
		var fh := m.get_world_3d().direct_space_state.intersect_ray(fq)
		if not fh.is_empty() and absf(float(fh["position"].y) - box.position.y) < 0.25:
			stand = cand
			n = -n * sd
			break
	return [stand, n, box.get_center(), box.position.y]


static func face(s: Soldier, n: Vector3) -> void:
	s.look_yaw = atan2(n.x, n.z) + PI        # forward = (−sin, 0, −cos) = n
	s.look_pitch = 0.0


## Strahl quer durch die Türöffnung auf 1 m über der Unterkante: true = blockiert
func _blocked(d: OrigInteractive.OrigDoor) -> bool:
	var n: Vector3 = d.get_meta("normal")
	var c: Vector3 = d.get_meta("closed_center")
	var p := Vector3(c.x, float(d.get_meta("closed_bottom")) + 1.0, c.z)
	var q := PhysicsRayQueryParameters3D.create(p - n * 0.3, p + n * 0.3, 1)
	q.exclude = _me.exclude_rids()
	q.hit_back_faces = true
	var hit := _m.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and d.is_open:
		print("DOORHIT %s: %s" % [d.name, (hit["collider"] as Node).get_path()])
	if hit.is_empty() and not d.is_open:
		print("DOORMISS %s: Strahl %s -> %s, Flügel %s, Körper %s" % [d.name, p - n * 0.3, p + n * 0.3,
			OrigInteractive.world_aabb(d.frame), d._own_rids().size()])
	return not hit.is_empty()


func _shot(d: OrigInteractive.OrigDoor, tag: String) -> void:
	if not Game.cli.has("shots"):
		return
	var n: Vector3 = d.get_meta("normal")
	var c: Vector3 = d.get_meta("closed_center")
	var side := n.cross(Vector3.UP).normalized()
	_cam.global_position = c - n * 2.6 + side * 0.9 + Vector3.UP * 0.55
	_cam.look_at(c + n * 0.8, Vector3.UP)
	_me.visible = false
	var rig = _m.get("rig")
	if rig is Node3D:
		rig.visible = false          # Ego-Waffe der Kamera nicht im Bild
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://test_output/normandie_door_%s_%s.png" % [String(d.persistent_id).trim_prefix("odoor_"), tag]
	img.save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)
	_me.visible = true
	if rig is Node3D:
		rig.visible = true


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(5)
	var sp := Game.cli.has("mission")          # Einzelspieler: --mission=no2_schwerttaenzer
	if sp:
		check(await _wait(func():
			var mm = Game.current_mission()
			return mm != null and mm.is_node_ready() and mm.squad and mm.squad.leader(), 400.0), "Einsatz %s geladen" % Game.cli["mission"])
		_m = Game.current_mission()
		isolate_enemies([])
		_me = _m.squad.leader()
		# übrige Figuren (Verbündete in der Bank, KI-Kameraden) anhalten: sie öffnen sonst selbst Türen
		for n in _m.find_children("*", "CharacterBody3D", true, false):
			if n is Soldier and n != _me:
				n.process_mode = Node.PROCESS_MODE_DISABLED
				(n as Soldier).global_position = Vector3(-120, 40, -120)
		for s in _m.squad.members:
			s.set_meta("protect_until", 1e12)
	else:
		var map := String(Game.cli.get("map", "mp_normandy2_mp_zone"))
		Net.local_name = "Achse"
		Net.local_team = Soldier.TEAM_AXIS
		var mode: int = Net.Mode.TEAM_DEATHMATCH if map.begins_with("mp_arena") else Net.Mode.OCCUPATION
		Net.host({"name": "Tueren", "map": map, "mode": mode, "port": Net.PORT,
			"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0,
			"password": "", "allow_vehicles": false})
		check(await _wait(func():
			var mm = Game.current_mission()
			return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 400.0), "Karte %s geladen" % map)
		_m = Game.current_mission()
		_me = Net._soldiers.get(1)
	await seconds(1.0)
	var it: OrigInteractive = _m.get("interactive")
	check(it != null and it.stats.doors >= 18 and it.stats.missing == 0, "Alle Original-Türen eingerichtet", str(it.stats) if it else "-")
	if Game.cli.has("shots"):
		_cam = Camera3D.new()
		_cam.fov = 70.0
		_m.add_child(_cam)
		_cam.current = true
		for h in [_m.get("hud"), _m.get_node_or_null("MpHud")]:
			if h is CanvasItem or h is CanvasLayer:
				h.visible = false
	var doors: Array = []
	for k in it.controls:
		if it.controls[k] is OrigInteractive.OrigDoor:
			doors.append(it.controls[k])
	var pc: PlayerController = _m.controller
	for d: OrigInteractive.OrigDoor in doors:
		var nm := String(d.persistent_id).trim_prefix("odoor_")
		if d.is_open:                      # Originalzustand offen (z. B. H38_92): erst schließen
			d.set_open(false)
			await _wait(func(): return d.state == 0, 6.0)
		var st := stand_for(_m, d)
		d.set_meta("normal", st[1])
		d.set_meta("closed_center", st[2])
		d.set_meta("closed_bottom", st[3])
		_me.global_position = st[0]
		_me.velocity = Vector3.ZERO
		face(_me, st[1])
		await frames(4)
		var closed_block := _blocked(d)
		var closed_info := "Betrag %.2f Zustand %d Soldat %s" % [d.amount, d.state, _me.global_position]
		if nm in SHOT_DOORS:
			await _shot(d, "zu")
		pc._update_interact_target()
		var target_ok := pc.interact_target == d
		var tgt_name := String(pc.interact_target.name) if pc.interact_target else "-"
		await tap("interact")
		var opened := await _wait(func(): return d.state == 1, 6.0)
		var full := opened
		# Schwenkt der Flügel gegen ein Hindernis (Original: Schritt zurück, 200 ms warten), bleibt er „öffnet“ stehen –
		# als geöffnet zählt ≥ 1 rad (57°) und freier Durchgang
		opened = opened or d.amount >= minf(d.open_amount, 1.0) - 0.01
		if not full:
			var a0: float = d.amount
			d.amount = minf(a0 + 0.1, d.open_amount)
			d._apply()
			var obs: Array = d._overlaps(d._ignore).map(func(r):
				var o := instance_from_id(PhysicsServer3D.body_get_object_instance_id(r))
				return String(o.get_path()) if o is Node else str(r))
			d.amount = a0
			d._apply()
			print("DOORSTUCK %s Betrag %.2f/%.2f Hindernisse %s Soldat %s" % [nm, a0, d.open_amount, obs, _me.global_position])
		await frames(3)
		var open_free := not _blocked(d)
		if nm in SHOT_DOORS:
			await _shot(d, "offen")
		pc._update_interact_target()
		await tap("interact")
		var closed := await _wait(func(): return d.state == 0, 6.0)
		await frames(3)
		check(target_ok and opened and closed, "Tür %s: Benutzen öffnet und schließt" % nm,
			"Ziel=%s Zustand=%d Pos=%s" % [tgt_name, d.state, st[2]])
		if nm in STORED_OPEN:
			# in scene.4ds bereits geöffnet gespeichert (Startzustand offen): Ausgangslage liegt nicht in der Zarge –
			# Durchgangsstrahl dort sinnlos; geprüft wird die Drehung um open_amount
			check(d.frame.transform.is_equal_approx(d.base), "Tür %s (offen gespeichert): Benutzen dreht hin und zurück" % nm)
		else:
			check(open_free and closed_block, "Tür %s: zu blockiert, offen frei" % nm, "zu blockiert=%s offen frei=%s (%s)" % [closed_block, open_free, closed_info])
	# Doppeltür: beide Flügel gehen gemeinsam auf und wieder zu – auch beim zweiten Benutzen über den anderen Flügel
	var d45: OrigInteractive.OrigDoor = it.controls.get("M_BANKA_45")
	var d46: OrigInteractive.OrigDoor = it.controls.get("M_BANKA_46")
	if d45 and d46:
		d46.interact(_me)
		check(await _wait(func(): return d45.state == 1 and d46.state == 1, 6.0), "Doppeltür m_banka_45/46: zweiter Flügel öffnet mit")
		d46.interact(_me)
		check(await _wait(func(): return d45.state == 0 and d46.state == 0, 6.0), "Doppeltür: beide schließen wieder (Partner bleibt verknüpft)")
	if not sp and String(Game.cli.get("mp", "1")) != "0":
		await _mp_phase(it)
	if not sp:
		Net.leave(false)
	_finish()


## Zwei Prozesse: Spät-Beitritt (Türzustand vor dem Beitritt geändert), Server benutzt Doppeltür, Client benutzt H38_89
func _mp_phase(it: OrigInteractive) -> void:
	var hd: OrigInteractive.OrigDoor = it.controls.get("H_DOOR_01")       # Original offen → vor dem Beitritt schließen
	hd.set_open(false)
	await _wait(func(): return hd.state == 0, 6.0)
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/normandie_doors_client.log")
	var args := ["--headless", "--log-file", clog]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, args + ["--", "--autoplay=test_normandie_doors_client"])
	check(pid > 0, "Client-Prozess gestartet")
	var joined := await _wait(func(): return Net._ready_peers.size() > 0 and Net._soldiers.size() >= 2, 500.0)
	check(joined, "Client beigetreten")
	if not joined:
		return
	await get_tree().create_timer(3.0).timeout
	# Server benutzt die Doppeltür (Benutzen-Taste wie ein Spieler)
	var d45: OrigInteractive.OrigDoor = it.controls.get("M_BANKA_45")
	var st := stand_for(_m, d45)
	_me.global_position = st[0]
	face(_me, st[1])
	await frames(4)
	_m.controller._update_interact_target()
	await tap("interact")
	check(await _wait(func(): return d45.state == 1, 6.0), "Server: Doppeltür m_banka_45 per Benutzen offen")
	# Client benutzt H38_89 (öffnen, dann schließen) – beim Server ankommen
	var d89: OrigInteractive.OrigDoor = it.controls.get("H38_89")
	check(await _wait(func(): return d89.state == 1, 240.0), "Client öffnet H38_89 → beim Server offen")
	check(await _wait(func(): return d89.state == 0, 120.0), "Client schließt H38_89 → beim Server zu")
	check(await _wait(func(): return FileAccess.file_exists(RESULT), 120.0), "Client-Ergebnisse empfangen")
	for line in FileAccess.get_file_as_string(RESULT).split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
