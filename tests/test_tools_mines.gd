extends "res://tests/test_systems.gd"
## Hilfsmittel in der Hand und beschießbare Minen (Vorgabe Auftraggeber 17.10.2026).
##   Einzelspieler: tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_tools_mines
##     Auswahl Verband/Mine/Sprengstoff/Fernglas → Waffe weg, Original-Modell in der Hand (3. und 1. Person),
##     zurück zur Waffe mit Zieh-Animation; Mine beschießen → Explosion + Schaden; Kettenreaktion.
##   Mehrspieler (zwei Prozesse): tools\godot.cmd --headless -- --autoplay=test_tools_mines --phase=mp
##     Host legt eine Mine (Netzfigur zeigt die Mine in der Hand), der Client schießt darauf → der Server
##     wertet aus, Explosion und Entfernen bei beiden, Schaden beim Host.
##   Kontrollbilder (Fenster): tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=test_tools_mines --phase=shots
##     → test_output/tools_*.png

const RESULT := "user://tools_mines_client_result.txt"
const MP_PORT := 11038


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	var phase := String(Game.cli.get("phase", "sp"))
	if phase == "mp":
		await _run_mp()
		return
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	isolate_enemies([])
	var c: PlayerController = m.controller
	var s: Soldier = m.squad.leader()
	c.set_active(s)
	if OrigWeapons.available() and not is_instance_valid(s.model.orig_figure):
		var fig := OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb")
		if fig:
			s.model.attach_orig(fig)
			s.model_changed.emit(s.model)
	s.medkits = 3
	s.mines = 6
	s.explosives = 3
	s.has_binoculars = true
	place(s, 10, 30, 0.0)
	await seconds(0.5)
	if phase == "shots":
		await _shots(m, s)
		return
	await _hand_items(m, s)
	await _mine_shot(m, s)
	await _defuse(m, s)
	_finish()


# --- 3. Entschärfen ----------------------------------------------------------------------------------

func _defuse(m: Mission, s: Soldier) -> void:
	var e: Soldier = null
	for x in m.enemies:
		if x.alive:
			e = x
			break
	if e == null:
		e = m.enemies[0]
	var base := Vector3(-30, 0, 40)
	place(s, base.x - 6.0, base.z, -PI * 0.5)
	await seconds(0.3)
	var mine := _spawn_charge(e, "mine", base)        # gegnerische Mine
	await seconds(3.3)                                 # scharf
	check(mine._armed, "Gegnerische Mine scharf")
	# geduckt heranschleichen (1,0 m): löst nicht aus (nur Berührung)
	s.stance_request = Soldier.Stance.CROUCH
	await seconds(0.6)
	var c: PlayerController = m.controller
	var start := mission().lb.ground(base.x - 1.0, base.z, 0.3)
	s.global_position = start
	s.look_yaw = -PI * 0.5                             # Blick nach +X auf die Mine
	s.velocity = Vector3.ZERO
	await seconds(0.4)
	check(is_instance_valid(mine) and not mine.is_done(), "Geduckt 1 m vor der Mine: kein Auslösen (nur Berührung)")
	c._update_interact_target()
	check(c.interact_target == mine.defuse_spot, "Benutzen-Ziel: Mine entschärfen", str(c.interact_target.prompt if c.interact_target else "-"))
	var mines0 := s.mines
	await tap("interact")
	check(mine.defuse_spot.busy() and s.work_left > 0.0 and s.work_label != "", "Entschärfen läuft mit Fortschritt",
		"%s %.1f" % [s.work_label, s.work_left])
	await seconds(2.0)
	check(is_instance_valid(mine) and not mine.is_done() and s.work_left > 0.0 and s.work_left < PlacedCharge.DEFUSE_TIME - 1.5,
		"Nach 2 s: Mine liegt noch, Fortschritt", "%.1f s" % s.work_left)
	await seconds(2.4)
	check(not is_instance_valid(mine) or mine.is_queued_for_deletion(), "Nach 4 s: Mine entschärft und entfernt")
	check(s.alive and s.health >= s.max_health - 0.5 and s.mines == mines0 and s.work_left <= 0.0,
		"Kein Schaden, Mine ersatzlos entfernt (Original: kein Gegenstand)", "mines %d → %d" % [mines0, s.mines])
	# Abbruch durch Bewegung
	var mine2 := _spawn_charge(e, "mine", base + Vector3(0, 0, 6))
	await seconds(3.3)
	s.global_position = mission().lb.ground(base.x - 1.0, base.z + 6.0, 0.3)
	s.velocity = Vector3.ZERO
	await seconds(0.3)
	mine2.defuse_spot.interact(s)
	await seconds(1.0)
	s.global_position += Vector3(-1.2, 0, 0)
	await seconds(0.3)
	check(is_instance_valid(mine2) and not mine2.is_done() and not mine2.defuse_spot.busy() and s.work_left <= 0.0,
		"Bewegung bricht das Entschärfen ab, Mine bleibt scharf")
	# Abbruch durch Treffer
	s.global_position = mission().lb.ground(base.x - 1.0, base.z + 6.0, 0.3)
	s.velocity = Vector3.ZERO
	await seconds(0.3)
	mine2.defuse_spot.interact(s)
	await seconds(0.5)
	s.apply_hit(5.0, &"arm", e, Vector3.FORWARD)
	await seconds(0.2)
	check(is_instance_valid(mine2) and not mine2.defuse_spot.busy(), "Treffer bricht das Entschärfen ab")
	# Stehend in 1,5 m: Annäherungszünder löst aus
	s.health = 1000.0                   # überlebt die Testexplosion
	s.stance_request = Soldier.Stance.STAND
	s.global_position = mission().lb.ground(base.x + 8.0, base.z + 6.0, 0.3)
	await seconds(0.8)
	s.global_position = mission().lb.ground(base.x - 1.5, base.z + 6.0, 0.3)
	await seconds(0.3)
	check(not is_instance_valid(mine2) or mine2.is_done(), "Stehend in 1,5 m: Mine löst aus (Annäherungszünder)")
	s.health = s.max_health


# --- 1. Hilfsmittel in der Hand ----------------------------------------------------------------------

func _weapon_visible(s: Soldier) -> bool:
	return is_instance_valid(s.model._weapon_mesh) and s.model._weapon_mesh.visible


func _hand_items(m: Mission, s: Soldier) -> void:
	var rig: CameraRig = m.rig
	if rig.mode != CameraRig.Mode.THIRD:
		rig.toggle_mode()
	s.apply_selection("slot:0")
	await seconds(0.8)
	check(_weapon_visible(s) and s.model.prop_name() == "", "Ausgangslage: Primärwaffe in der Hand")
	var want := {"medkit": "l_medkit", "mine": "w_antiman", "explosive": "w_explosive"}
	for key in ["medkit", "mine", "explosive"]:
		s.apply_selection(key)
		await frames(6)
		var pn := s.model.prop_name()
		var model_ok: bool = pn == want[key] if OrigWeapons.available() else pn.begins_with("placeholder:")
		check(s.tool == key and not _weapon_visible(s) and s.model.prop() != null and s.model.prop().visible and model_ok,
			"3. Person: %s gewählt → Waffe weggesteckt, Modell %s in der Hand" % [key, want[key]],
			"tool=%s prop=%s waffe=%s" % [s.tool, pn, _weapon_visible(s)])
		check(s.model._hold_clip == "" or s.model._hold_clip == OrigWeapons.hold_clip("hand", "calm", 0),
			"%s: Haltung „hand“ statt Waffenhaltung" % key, s.model._hold_clip)
		# 1. Person
		rig.toggle_mode()
		await frames(8)
		var vi := rig.viewmodel_info()
		var fpv_ok: bool = vi["key"] == "w_antimanfpv" if key == "mine" and OrigWeapons.available() else vi["tool"] == key
		check(rig.fpv_active and vi["visible"] and fpv_ok and not _weapon_visible(s),
			"1. Person: %s als Ego-Modell (Mine: Original-FPV w_antimanfpv)" % key, str(vi))
		rig.toggle_mode()
		await frames(4)
	# zurück zur Waffe: Ziehen
	var wkey := OrigWeapons.fpv_key(s.weapons[0].data, s.team)
	s.apply_selection("slot:0")
	await frames(3)
	var drawing := s.model.action_clip() != "" or not OrigWeapons.available() or s.model._hold_anim == null
	check(s.tool == "" and _weapon_visible(s) and s.model.prop_name() == "" and drawing,
		"Zurück zur Primärwaffe: Modell weg, Waffe wieder sichtbar, Zieh-Animation", s.model.action_clip())
	rig.toggle_mode()
	await frames(6)
	var vi2 := rig.viewmodel_info()
	check(vi2["tool"] == "" and (vi2["key"] == wkey or wkey == ""), "1. Person: wieder die Waffe als Ego-Modell", str(vi2))
	rig.toggle_mode()
	await frames(3)
	# Fernglas: 3. Person in der Hand, Benutzen schaltet zurück
	s.apply_selection("binoculars")
	await frames(6)
	check(s.using_binoculars and not _weapon_visible(s)
		and (s.model.prop_name() == "w_binocul" or not OrigWeapons.available()), "Fernglas gewählt: Fernglas statt Waffe", s.model.prop_name())
	s.use_tool()
	await frames(6)
	check(s.tool == "" and not s.using_binoculars and _weapon_visible(s), "Fernglas absetzen → wieder die Waffe")
	# Verband benutzen: Modell bleibt in der Hand bis zum letzten Verband, dann zurück zur Waffe
	var mate: Soldier = m.squad.members[1]
	s.medkits = 1
	s.apply_selection("medkit")
	mate.global_position = s.global_position + Vector3(0.8, 0, 0)
	mate.health = mate.max_health * 0.5
	await frames(3)
	s.use_tool()
	await seconds(0.5)
	check(s.heal_time_left > 0.0 and s.model.prop_name() != "" and not _weapon_visible(s), "Verbinden: Verbandskasten in der Hand")
	await seconds(3.2)
	check(s.medkits == 0 and s.tool == "" and _weapon_visible(s) and s.model.prop_name() == "",
		"Letzter Verband verbraucht → zurück zur Waffe", "tool=%s med=%d" % [s.tool, s.medkits])
	# Sprengstoff legen: Rest bleibt in der Hand, letzter → Waffe
	s.explosives = 2
	s.apply_selection("explosive")
	await frames(3)
	s.use_tool()
	await frames(4)
	check(s.tool == "explosive" and s.explosives == 1 and not _weapon_visible(s), "Ladung gelegt, weitere bleibt in der Hand")
	s.use_tool()
	await frames(4)
	check(s.tool == "" and s.explosives == 0 and _weapon_visible(s), "Letzte Ladung gelegt → zurück zur Waffe")
	for ch in get_tree().get_nodes_in_group("placed_charges"):
		ch.queue_free()               # Zeitzünder nicht abwarten
	await frames(3)


# --- 2. Minen beschießen, Schaden, Kettenreaktion ----------------------------------------------------

func _spawn_charge(s: Soldier, kind: String, at: Vector3) -> PlacedCharge:
	var c := PlacedCharge.new()
	c.kind = kind
	c.owner_soldier = s
	c.team = s.team
	s.get_parent().add_child(c)
	c.global_position = mission().lb.ground(at.x, at.z, 0.0) + Vector3.UP * 0.05
	return c


func _shoot_at(s: Soldier, target: Vector3) -> void:
	s.apply_selection("slot:0")
	await seconds(0.7)
	var w := s.current_weapon()
	w.in_mag = maxi(w.in_mag, 3)
	s.extra_spread = -1000.0              # ohne Streuung (Testschuss)
	s.has_aim_point = true
	s.aim_point = target
	s._fire_shot(w)
	s.has_aim_point = false
	s.extra_spread = 0.0


func _mine_shot(m: Mission, s: Soldier) -> void:
	s.mines = 3
	place(s, 10, 30, 0.0)
	await seconds(0.3)
	s.apply_selection("mine")
	await frames(3)
	s.use_tool()
	await frames(3)
	var mines := get_tree().get_nodes_in_group("placed_charges")
	check(mines.size() == 1 and (mines[0] as PlacedCharge).kind == "mine", "Mine gelegt")
	if mines.is_empty():
		return
	var mine: PlacedCharge = mines[0]
	check(mine.hit_area != null and mine.hit_area.collision_layer == Hitbox.LAYER and mine.is_in_group("destructibles"),
		"Mine: Trefferfläche auf Ebene 3 (Geschosse), Gruppe destructibles (Explosionen)")
	# Gegner 2,5 m neben der Mine (außerhalb des Annäherungszünders 1,8 m)
	var e: Soldier = m.enemies[0]
	reset_enemy(e, 0, 0, 0.0)
	(e.get_node("EnemyBrain") as EnemyBrain).enabled = false
	e.get_node("Perception").set_physics_process(false)
	e.global_position = mine.global_position + Vector3(2.5, 0.05, 0.0)
	e.health = e.max_health
	var hp0 := e.health
	# Schütze 9 m entfernt
	s.global_position = mine.global_position + Vector3(-9.0, 0.3, 0.0)
	s.look_yaw = -PI * 0.5
	await seconds(0.6)
	var pos := mine.global_position
	var hits0 := Ballistics.shots_fired
	await _shoot_at(s, mine.hit_area.global_position + Vector3.UP * 0.07)
	await seconds(0.5)
	check(Ballistics.shots_fired > hits0 and (not is_instance_valid(mine) or mine.is_queued_for_deletion()),
		"Schuss auf die Mine → Detonation")
	var dmg_expect := WeaponDB.explosion_damage(PlacedCharge.MINE_STRENGTH, PlacedCharge.MINE_RADIUS,
		(pos + Vector3.UP * 0.2).distance_to(e.global_position + Vector3.UP * 0.5))
	check(not e.alive or e.health < hp0 - 1.0, "Gegner 2,5 m daneben erhält Explosionsschaden (Original-Formel)",
		"HP %.0f → %.0f, erwartet ≈ −%.0f" % [hp0, e.health, dmg_expect])
	check(s.alive and s.health >= s.max_health - 0.5, "Schütze in 9 m bleibt unverletzt")
	# Kettenreaktion: Mine A ← Schuss, Mine B 3 m daneben, Ladung C 3 m weiter, Mine D 15 m entfernt bleibt liegen
	place(s, -10, 30, 0.0)
	await seconds(0.3)
	var base := Vector3(-10, 0, 25)
	var a := _spawn_charge(s, "mine", base)
	var b := _spawn_charge(s, "mine", base + Vector3(3, 0, 0))
	var cc := _spawn_charge(s, "explosive", base + Vector3(6, 0, 0))
	var d := _spawn_charge(s, "mine", base + Vector3(21, 0, 0))
	await frames(3)
	s.global_position = mission().lb.ground(base.x - 9.0, base.z, 0.3)
	await seconds(0.5)
	await _shoot_at(s, a.hit_area.global_position + Vector3.UP * 0.07)
	await seconds(1.2)
	var gone := func(x) -> bool: return not is_instance_valid(x) or (x as Node).is_queued_for_deletion()
	check(gone.call(a), "Kette: beschossene Mine explodiert")
	check(gone.call(b) and gone.call(cc), "Kettenreaktion: Nachbarmine (3 m) und Sprengladung (6 m) gehen mit hoch")
	check(not gone.call(d), "Mine in 21 m Entfernung bleibt liegen")
	# Granate neben Mine D → Explosion in der Nähe löst sie aus
	var g := Grenade.new()
	g.data = WeaponDB.get_weapon(&"no36")
	g.thrower = s
	g.team = s.team
	s.get_parent().add_child(g)
	g.global_position = d.global_position + Vector3(1.0, 0.3, 0.0)
	g.explode()
	await seconds(0.6)
	check(gone.call(d), "Granatexplosion daneben bringt die Mine zur Detonation")


# --- Kontrollbilder (Fenster) ------------------------------------------------------------------------

func _snap(name: String) -> void:
	await frames(20)
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://test_output/tools_%s.png" % name)
	print("SHOT ", name)


func _shots(m: Mission, s: Soldier) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var rig: CameraRig = m.rig
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if cl.name != "OrigHud" and cl.name != "Hud":
			(cl as CanvasLayer).visible = false
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.far = 500.0
	cam.fov = 40.0
	m.controller.input_enabled = false          # Maus im Fenster dreht den Soldaten sonst
	for key in ["medkit", "mine", "explosive"]:
		s.apply_selection(key)
		s.look_yaw = 0.0
		s.look_pitch = 0.0
		await seconds(1.0)
		# 3. Person: Kamera schräg vorn rechts auf Hand-/Brusthöhe
		var fwd := s.forward()
		var right := Vector3(cos(s.look_yaw), 0, -sin(s.look_yaw))
		cam.global_position = s.global_position + fwd * 1.9 + right * 0.9 + Vector3.UP * 1.45
		cam.look_at(s.global_position + Vector3.UP * 1.1 + right * 0.15)
		cam.current = true
		await _snap("%s_3p" % key)
		cam.global_position = s.global_position - fwd * 1.9 + right * 0.9 + Vector3.UP * 1.45
		cam.look_at(s.global_position + Vector3.UP * 1.1 + right * 0.15)
		await _snap("%s_3p_b" % key)
		cam.current = false
		rig.camera.current = true
		if rig.mode != CameraRig.Mode.FIRST:
			rig.toggle_mode()
		await seconds(1.0)
		await _snap("%s_1p" % key)
		rig.toggle_mode()
		await seconds(0.3)
	# Entschärfen mit Fortschrittsanzeige (Spielkamera 3. Person, HUD sichtbar)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = true
	s.apply_selection("slot:0")
	s.stance_request = Soldier.Stance.CROUCH
	await seconds(0.8)
	var em := _spawn_charge(m.enemies[0], "mine", s.global_position + s.forward() * 1.0)
	await seconds(3.3)
	cam.current = false
	rig.camera.current = true
	em.defuse_spot.interact(s)
	await seconds(1.8)
	await _snap("defuse_progress")
	await seconds(2.6)
	s.stance_request = Soldier.Stance.STAND
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if cl.name != "OrigHud" and cl.name != "Hud":
			(cl as CanvasLayer).visible = false
	await seconds(0.8)
	# Mine legen und beschießen: Explosion festhalten
	s.apply_selection("mine")
	await frames(3)
	s.use_tool()
	await frames(3)
	var mine: PlacedCharge = get_tree().get_nodes_in_group("placed_charges")[0]
	s.global_position = mine.global_position + Vector3(-8.0, 0.3, 0.0)
	s.look_yaw = -PI * 0.5
	cam.global_position = mine.global_position + Vector3(-3.5, 1.6, 4.5)
	cam.look_at(mine.global_position + Vector3.UP * 0.2)
	cam.current = true
	await _snap("mine_placed")
	cam.global_position = mine.global_position + Vector3(-9.0, 4.0, 12.0)
	cam.look_at(mine.global_position + Vector3.UP * 1.5)
	cam.fov = 60.0
	await _shoot_at(s, mine.hit_area.global_position + Vector3.UP * 0.07)
	var t_shot := Time.get_ticks_msec()
	var n := 0
	for ms in [40, 120, 300, 700, 1500]:
		while Time.get_ticks_msec() - t_shot < ms:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		n += 1
		img.save_png("res://test_output/tools_mine_explosion%d.png" % n)
		print("SHOT mine_explosion%d" % n)
	check(true, "Kontrollbilder erzeugt")
	_finish()


# --- Mehrspieler (Server-Seite, zweiter Prozess = test_tools_mines_client) ---------------------------

func _run_mp() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(5)
	Net.local_name = "Host"
	var ok := Net.host({"name": "Minen", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.DEATHMATCH, "max_players": 4,
		"time_limit_min": 0, "score_limit": 0, "respawn_s": 5, "password": "", "port": MP_PORT,
		"friendly_fire": true, "bots_per_team": 0})
	check(Net.is_online and multiplayer.is_server(), "Server gestartet", str(ok) + " " + Net.last_error)
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
		m = Game.current_mission()
		if m and m.squad and m.is_node_ready():
			break
	await frames(30)
	var me: Soldier = Net._soldiers.get(1)
	check(is_instance_valid(me) and me.alive, "Soldat des Servers erzeugt")
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/tools_mines_client.log")
	var proj: Array = [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog] + proj + ["--",
		"--autoplay=test_tools_mines_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000 and cid == 0:
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			if id != 1 and is_instance_valid(Net._soldiers[id]):
				cid = id
	check(cid != 0, "Client beigetreten")
	# Client meldet per Chat, dass seine Karte geladen ist (Aktionen davor kämen nicht an)
	var ready := func() -> bool: return Net.chat_log.any(func(e): return String(e["text"]) == "bereit")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000 and not ready.call():
		await get_tree().create_timer(0.25).timeout
	check(ready.call(), "Client hat die Karte geladen")
	await get_tree().create_timer(1.0).timeout
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:          # Rundenstart setzt den Host-Soldaten ggf. neu
		me = Net._soldiers.get(1)
		if is_instance_valid(me) and me.alive and not me.is_queued_for_deletion():
			break
		await get_tree().create_timer(0.25).timeout
	if cid == 0 or not is_instance_valid(me):
		check(false, "Host-Soldat nach dem Beitritt vorhanden")
		_finish()
		return
	me.max_health = 1000.0
	me.health = 1000.0
	me.set_meta("protect_until", 0)
	me.mines = 2
	me.apply_selection("mine")
	await get_tree().create_timer(1.0).timeout
	check(me.model.prop_name() != "" and not _weapon_visible(me), "Host: Mine in der Hand")
	me.use_tool()
	await frames(3)
	var mines := get_tree().get_nodes_in_group("placed_charges")
	check(mines.size() == 1, "Host: Mine gelegt")
	if mines.is_empty():
		_finish()
		return
	var mine: PlacedCharge = mines[0]
	# Host 4 m neben die Mine (Schaden), Mine für den Client markieren (Position kommt über die Aktion „mine“)
	me.global_position = mine.global_position + Vector3(0.0, 0.3, 4.0)
	var hp0 := me.health
	# warten, bis die Mine durch den Beschuss des Clients detoniert (Server wertet aus)
	var wr: WeakRef = weakref(mine)
	var gone := func() -> bool:
		var mm = wr.get_ref()
		return mm == null or (mm as PlacedCharge).is_queued_for_deletion() or (mm as PlacedCharge).is_done()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not gone.call():
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(me):
			me.global_position = mine.global_position + Vector3(0.0, 0.3, 4.0) if is_instance_valid(mine) else me.global_position
	check(gone.call() and PlacedCharge.defused_count == 0, "Server: Schuss des Clients bringt die Mine zur Detonation")
	await frames(10)
	check(is_instance_valid(me) and me.health < hp0 - 1.0, "Server: Host in 4 m erhält Explosionsschaden",
		"%.0f → %.0f" % [hp0, me.health if is_instance_valid(me) else -1.0])
	# Entschärfen: Host legt eine zweite Mine, der Client entschärft sie (Server entscheidet)
	await get_tree().create_timer(2.0).timeout
	me = Net._soldiers.get(1)
	me.mines = maxi(me.mines, 1)
	me.apply_selection("mine")
	await frames(3)
	me.use_tool()
	await frames(3)
	var lst2 := get_tree().get_nodes_in_group("placed_charges")
	check(lst2.size() == 1, "Host: zweite Mine gelegt")
	if not lst2.is_empty():
		var mine_b: PlacedCharge = lst2[0]
		var wrb: WeakRef = weakref(mine_b)
		me.global_position = mine_b.global_position + Vector3(0.0, 0.3, 4.0)
		var hp1 := me.health
		var def0 := PlacedCharge.defused_count
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 240000 and wrb.get_ref() != null and not (wrb.get_ref() as PlacedCharge).is_done():
			await get_tree().create_timer(0.1).timeout
		check(PlacedCharge.defused_count == def0 + 1, "Server: Client hat die Mine entschärft (serverseitig)")
		await frames(5)
		check(is_instance_valid(me) and absf(me.health - hp1) < 0.5, "Server: keine Explosion beim Entschärfen")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)
	_finish()
