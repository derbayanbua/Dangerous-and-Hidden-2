extends "res://tests/test_systems.gd"
## Soldatenanimationen aus TABLES\anim.sav (BodyAnim, orig_cache/characters/human_anims.json) und schnelleres Messer:
## Clip je Zustand (Ruhe/Bewegung je Haltung und Richtung, Haltungswechsel, Lehnen, Springen, Klettern, Leiter,
## Schwimmen, Treffer, Tode je Richtung, Ergeben, Gefangener, Benutzen), Abspieltempo gegen Fußgleiten,
## Messer: Zeit bis Treffer und Stichfolge kürzer als vorher, Treffer im Nahbereich, von hinten tödlich.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_animations


func _clip(s: Soldier) -> String:
	return s.model._orig_clip


func _in_list(c: String, st: int, d: String) -> bool:
	for m in 6:
		if BodyAnim.move_clip(st, d, m) == c:
			return true
	return false


func _freeze(e: Soldier) -> void:
	var b := e.get_node_or_null("EnemyBrain")
	if b:
		b.enabled = false
		b.set_physics_process(false)
		b.set_process(false)
	var p := e.get_node_or_null("Perception")
	if p:
		p.set_physics_process(false)


## Soldat manuell treiben (ohne eigene Physik): Zustandsfelder setzen und update_anim aufrufen.
func _drive(s: Soldier, secs: float) -> void:
	for i in int(secs * 60.0):
		s.model.update_anim(1.0 / 60.0, s.stance, Vector2(s.velocity.x, s.velocity.z).length(), s.look_pitch, s.aiming, s.lean)
		await get_tree().physics_frame


## B-004: Tätigkeiten (HUMAN_ACTIVITY_* → anim.sav-Satz), Sitzen/Schneidersitz, Fahrzeuginsassen, Tode im Sitzen.
func _test_b004(e: Soldier, t: Dictionary) -> void:
	var body: BodyAnim = e.model.body
	var anim: AnimationPlayer = e.model._orig_anim
	var hold: AnimationPlayer = e.model._hold_anim
	var act: Dictionary = t.get("activity", {})
	check(act.has(str(0x19)) and act.has(str(0x3B)) and act.has(str(0x41)) and act.has(str(0x36)),
		"Tätigkeitssätze aus anim.sav (Karten 0x19, Gruß 0x3B, Fernglas 0x41, Hitze 0x36)", str(act.keys()))
	var miss: Array = []
	for id in act:
		for en in act[id]:
			if en is Dictionary:
				var pl: AnimationPlayer = anim if String(en["layer"]) == "full" else hold
				if pl == null or not pl.has_animation(String(en["clip"])):
					miss.append(String(en["clip"]))
	check(miss.is_empty(), "Alle Tätigkeitsclips in der Figur (Ganzkörper m_*, Oberkörper h_*)", str(miss))
	var sitk: Array = []
	for k in ["sit_down", "sit", "sit_up", "turk_down", "turk", "turk_up", "drive", "passenger", "motorbike",
			"death_sit1", "death_turk"]:
		if not anim.has_animation(BodyAnim.full(k)):
			sitk.append(k)
	check(sitk.is_empty(), "Sitz-/Insassenclips (!sednuti/!sedim1/!zeseduR, #sedamturek…, !ridic/!spol/!namotorce)", str(sitk))
	# Skript-API: Zuordnung Funktion -> Tätigkeits-ID (hd2.exe 0x421C00)
	place(e, 6, 20, 0.0)
	e.velocity = Vector3.ZERO
	var eb = e.get_node_or_null("EnemyBrain")
	if eb:
		eb.state = EnemyBrain.State.GUARD     # Tätigkeiten nur ohne Alarm (Kampf/Suche bricht ab)
	await seconds(0.5)
	check(not BodyAnim._alarmed(e), "Prüffigur ohne Alarm (Wache)")
	var rt := LsRuntime.new()
	var vm := LsVM.new(LsCompiler.new(), e, rt)
	var r = rt.call_api(vm, "HUMAN_ACTIVITY_SALUTE", [["num", 1]])
	await frames(3)
	check(body.activity_id == 0x3B and anim.current_animation == BodyAnim.activity_clip(0x3B, 0)["clip"]
		and r is Dictionary and absf(float(r.get("wait", 0.0)) - anim.get_animation(anim.current_animation).length) < 0.05,
		"HUMAN_ACTIVITY_Salute(1): „!salutovani“ (Satz 0x3B), Skript wartet die Cliplänge", "%s %s" % [anim.current_animation, str(r)])
	check(not e.model._weapon_mesh.visible, "Tätigkeit: Waffe weg (Hände frei)")
	rt.call_api(vm, "HUMAN_ACTIVITY_HOT", [])
	await frames(3)
	check(body.act_upper == BodyAnim.activity_clip(0x36, 0)["clip"] and e.model._hold_clip == body.act_upper
		and body.state == "idle", "HUMAN_ACTIVITY_Hot: Oberkörper „(teplous“ über der Ruhe", "%s / %s" % [e.model._hold_clip, body.state])
	r = rt.call_api(vm, "HUMAN_ACTIVITY_COLD", [])
	check(r == null and body.activity_id == -1, "HUMAN_ACTIVITY_Cold: Satz 0x35 ohne Clip -> nichts, kein Warten")
	r = rt.call_api(vm, "HUMAN_ACTIVITY_SMOKE", [["num", 1]])
	check(r == null and body.activity_id == -1, "HUMAN_ACTIVITY_Smoke: ohne Wirkung wie hd2.exe 1.12 (0x423354)")
	rt.call_api(vm, "HUMAN_ACTIVITY_CARD", [["num", 2]])
	await frames(2)
	check(body.activity_id == 0x1A and body.oneshot == "m_hrejkarty", "HUMAN_ACTIVITY_Card(2): „(hrejkarty“", body.oneshot)
	rt.call_api(vm, "HUMAN_ACTIVITY_CARD", [["num", 0]])
	check(body.activity_id == -1 and body.oneshot == "", "HUMAN_ACTIVITY_Card(0): Tätigkeit beendet")
	r = rt.call_api(vm, "HUMAN_ACTIVITY_BINOCULARS", [])
	await frames(2)
	check(r == null and body.activity_id == 0x41 and body.oneshot == "m_dalekohled", "HUMAN_ACTIVITY_Binoculars: „%dalekohled“ ohne Warten",
		body.oneshot)
	rt.call_api(vm, "HUMAN_ACTIVITY_BINOCULARSEND", [])
	check(body.activity_id == -1, "HUMAN_ACTIVITY_BinocularsEnd beendet")
	rt.call_api(vm, "HUMAN_ACTIVITY_DRINKBOTTLE", [["num", 0]])
	await frames(2)
	check(body.activity_id == 0x1C and e.model._hold_clip == "h_pitiFL", "HUMAN_ACTIVITY_DrinkBottle ohne Flasche: „(pitiFL“",
		e.model._hold_clip)
	e.move_input = Vector3(0, 0, -1)
	await seconds(0.5)
	e.move_input = Vector3.ZERO
	check(body.activity_id == -1, "Tätigkeit endet bei Bewegung")
	await seconds(0.3)
	# Sitzen / Schneidersitz
	rt.call_api(vm, "HUMAN_ACTIVITY_TURK", [])
	await frames(2)
	check(body.seated == "turk" and body.oneshot == BodyAnim.full("turk_down"), "HUMAN_ACTIVITY_Turk: hinsetzen „#sedamturek“",
		body.oneshot)
	await seconds(anim.get_animation(BodyAnim.full("turk_down")).length + 0.4)
	check(body.state == "turk" and anim.current_animation == BodyAnim.full("turk"), "Schneidersitz „#sedimturek“ (Schleife)",
		anim.current_animation)
	check(body.death_clip(0, Vector3(0, 0, 1), "torso", "") == BodyAnim.full("death_turk"), "Tod im Schneidersitz: „!smrttur2“")
	rt.call_api(vm, "HUMAN_SETMODE_STAND", [])
	await frames(2)
	check(body.seated == "" and body.oneshot == BodyAnim.full("turk_up"), "HUMAN_SETMODE_Stand: aufstehen „#vstavamtur“", body.oneshot)
	await seconds(anim.get_animation(BodyAnim.full("turk_up")).length + 0.3)
	check(body.sit_down("sit") and body.seated == "sit", "Sitzen (HUMAN_ACTIVITY_Sit): „!sednuti“")
	await seconds(anim.get_animation(BodyAnim.full("sit_down")).length + 0.4)
	check(body.state == "sit" and anim.current_animation == BodyAnim.full("sit") and not e.model._weapon_mesh.visible,
		"Sitzen „!sedim1“ (Schleife), Waffe weg", anim.current_animation)
	check(body.death_clip(0, Vector3(0, 0, 1), "torso", "") in [BodyAnim.full("death_sit1"), BodyAnim.full("death_sit2")],
		"Tod im Sitzen: „!smrtsed1/2“")
	e.move_input = Vector3(0, 0, -1)
	await seconds(0.5)
	e.move_input = Vector3.ZERO
	check(body.seated == "", "Sitzen endet bei Bewegung")
	rt.free()
	await seconds(0.5)
	# Fahrzeuginsassen: Sitzflags SEAT<Ziffern> (la_jeepw: SEAT00 „SEAT0“ Fahrer, SEAT01 „SEAT15“ Mitfahrer)
	var jeep := ""
	for p in DirAccess.get_directories_at(OrigLevel.cache_root()):
		var cand := OrigLevel.cache_root() + "/" + p + "/models/la_jeepw.glb"
		if FileAccess.file_exists(cand):
			jeep = cand
			break
	var fl := BodyAnim.seat_flags(jeep)
	check(int(fl.get(0, 0)) == 1 and int(fl.get(1, 0)) == ((1 << 1) | (1 << 5)), "Sitzflags la_jeepw: SEAT0 / SEAT15", str(fl))
	check(BodyAnim.seat_kind(int(fl.get(0, 0))) == "drive" and BodyAnim.seat_kind(int(fl.get(1, 0))) == "passenger"
		and BodyAnim.seat_kind(1 | (1 << 7)) == "motorbike" and BodyAnim.seat_kind((1 << 1) | (1 << 8)) == ""
		and BodyAnim.seat_kind(1 | (1 << 4)) == "", "Sitzhaltung: Fahrer !ridic, Mitfahrer !spol, Motorrad !namotorce, Bordwaffe/Panzer unverändert")
	var veh: Vehicle = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is Vehicle and not v.armored and v.seats.size() >= 2:
			veh = v
			break
	if veh == null:
		check(true, "Kein Fahrzeug in der Prüfmission (Insassen nur über Sitzflags geprüft)")
		return
	var fd := BodyAnim.seat_kind(int(BodyAnim.seat_flags(veh.model_path).get(0, 0)))
	if veh.board(e, true):
		await seconds(0.6)
		check(fd == "" or (body.state == "vehicle" and anim.current_animation == BodyAnim.full(fd)),
			"Fahrer im Fahrzeug: Sitzclip", "%s %s" % [fd, anim.current_animation])
		veh.leave(e)
		await seconds(0.5)
		check(body.seat == "" and body.state != "vehicle", "Nach dem Aussteigen: normale Haltung")


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	isolate_enemies([])
	var t := BodyAnim.table()
	check(not (t.get("clips", {}) as Dictionary).is_empty() and (t.get("move", {}) as Dictionary).size() == 3,
		"Zuordnung human_anims.json geladen (3 Haltungen × 8 Richtungen × 6 Gangarten)", "%d Clips" % (t.get("clips", {}) as Dictionary).size())
	var c: PlayerController = m.controller
	var s: Soldier = m.squad.leader()
	c.set_active(s)
	for mm in m.squad.members:
		if mm != s:
			mm.global_position = s.global_position + Vector3(40, 0, 40)
	var fig := OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb")
	check(fig != null, "Original-Figur en01 (alliiert) geladen")
	if fig == null:
		_finish()
		return
	s.model.attach_orig(fig)
	# Prüffigur: deutscher Gegner ge01a ohne KI
	var e: Soldier = enemy("e_north") if enemy("e_north") else m.enemies[0]
	reset_enemy(e, 6, 20, 0.0)
	_freeze(e)
	var fig2 := OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb")
	e.model.attach_orig(fig2)
	e.max_health = 100000.0
	e.health = 100000.0
	var anim: AnimationPlayer = e.model._orig_anim
	check(anim != null and e.model.body != null, "BodyAnim an der Figur")
	var missing: Array = []
	for k in (t.get("full", {}) as Dictionary):
		if not anim.has_animation(String(t["full"][k])):
			missing.append(k)
	check(missing.is_empty(), "Alle Ganzkörperclips in der Figur vorhanden", str(missing))
	await seconds(0.6)

	# --- Ruhe je Haltung ---
	e.move_input = Vector3.ZERO
	await seconds(0.5)
	check(_clip(e) == BodyAnim.full("idle_zb"), "Ruhe stehend: !staticZB", _clip(e))
	e.stance_request = Soldier.Stance.CROUCH
	await frames(3)
	check(e.model.body.oneshot == BodyAnim.full("st_dr"), "Haltungswechsel stehen→hocken: !st-dr3", e.model.body.oneshot)
	await seconds(1.0)
	check(_clip(e) == BodyAnim.full("crouch_zb"), "Ruhe hockend: !drepZB1", _clip(e))
	e.stance_request = Soldier.Stance.PRONE
	await frames(3)
	check(e.model.body.oneshot == BodyAnim.full("dr_le"), "Haltungswechsel hocken→liegen: !dr-leR", e.model.body.oneshot)
	await seconds(1.6)
	check(_clip(e) == BodyAnim.full("prone_zb"), "Ruhe liegend: !lehZB", _clip(e))
	e.stance_request = Soldier.Stance.STAND
	await frames(3)
	check(e.model.body.oneshot == BodyAnim.full("le_st"), "Haltungswechsel liegen→stehen: !le-st3", e.model.body.oneshot)
	await seconds(1.6)

	# --- Bewegung je Haltung/Richtung, Tempo gegen Fußgleiten ---
	var dirs := {"fwd": Vector3(0, 0, -1), "back": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0),
		"fl": Vector3(-1, 0, -1).normalized(), "br": Vector3(1, 0, 1).normalized()}
	var slide_ok := true
	var slide_info := ""
	for st in [0, 1, 2]:
		e.stance_request = st
		await seconds(1.4)
		for d in dirs:
			place(e, 6, 20, 0.0)
			e.move_mode = Soldier.MoveMode.WALK
			e.move_input = dirs[d]
			await seconds(0.7)
			var cl := _clip(e)
			var sp := e.current_speed()
			check(e.model.body.state == "move" and _in_list(cl, st, d),
				"Bewegung Haltung %d Richtung %s: Original-Clip" % [st, d], "%s %.2f m/s" % [cl, sp])
			var nat := BodyAnim.natural_speed(cl)
			var rate: float = anim.speed_scale
			# Fußgleiten: Restfehler zwischen Clip-Tempo × natürlicher Geschwindigkeit und tatsächlicher Geschwindigkeit
			var err := absf(rate * nat - sp) / maxf(sp, 0.05)
			if err > 0.25:
				slide_ok = false
				slide_info += "%d/%s %.0f%% " % [st, d, err * 100.0]
		e.move_input = Vector3.ZERO
	check(slide_ok, "Abspieltempo passt zur Laufgeschwindigkeit (Fußgleiten ≤ 25 %)", slide_info)
	e.stance_request = Soldier.Stance.STAND
	await seconds(1.6)
	# Gangarten stehend: Schleichen/Gehen/Laufschritt/Sprint je eigener Clip
	var mode_clips := {}
	for mmode in [Soldier.MoveMode.SNEAK, Soldier.MoveMode.WALK, Soldier.MoveMode.JOG, Soldier.MoveMode.RUN]:
		place(e, 6, 20, 0.0)
		e.move_mode = mmode
		e.move_input = Vector3(0, 0, -1)
		await seconds(0.8)
		mode_clips[mmode] = _clip(e)
	e.move_input = Vector3.ZERO
	check(mode_clips[Soldier.MoveMode.SNEAK] == BodyAnim.move_clip(0, "fwd", 0) and mode_clips[Soldier.MoveMode.WALK] == BodyAnim.move_clip(0, "fwd", 1)
		and mode_clips[Soldier.MoveMode.JOG] == BodyAnim.move_clip(0, "fwd", 2) and mode_clips[Soldier.MoveMode.RUN] == BodyAnim.move_clip(0, "fwd", 5),
		"Schleichen/Gehen/Laufschritt/Sprint: langsam/normal/schnell/Sprint", str(mode_clips.values()))
	# Verwundet: Hinken (mrzak)
	e.health = e.max_health * 0.2
	e.model.body.last_health = -1.0
	place(e, 6, 20, 0.0)
	e.move_mode = Soldier.MoveMode.WALK
	e.move_input = Vector3(0, 0, -1)
	await seconds(0.8)
	check(_clip(e) == BodyAnim.move_clip(0, "fwd", 3), "Verwundet: Hinken „(mrzakZB“", _clip(e))
	e.move_input = Vector3.ZERO
	e.health = e.max_health
	await seconds(0.5)

	# --- Lehnen (Standbild im Original-Lehnclip) ---
	e.lean = -1.0
	await seconds(0.6)
	check(e.model.body.state == "lean" and _clip(e) == BodyAnim.full("lean_l0"), "Lehnen links: !vykouk_LZB", _clip(e))
	e.lean = 1.0
	await seconds(0.6)
	check(_clip(e) == BodyAnim.full("lean_r0"), "Lehnen rechts: !vykouk_PZB", _clip(e))
	e.lean = 0.0
	await seconds(0.4)

	# --- Springen / Landen ---
	place(e, 6, 20, 0.0)
	await seconds(0.2)
	e.jump_or_climb()
	var saw_jump := false
	var saw_land := false
	for i in 120:
		await frames(1)
		saw_jump = saw_jump or e.model.body.state == "jump"
		saw_land = saw_land or e.model.body.oneshot_kind == "land"
	check(saw_jump, "Sprung: !jump")
	# Klettern über ein Hindernis (Weg wie try_climb) und Leiter (senkrechter Weg)
	var p0 := e.global_position
	e.start_path_climb(p0, p0 + Vector3(0, 1.05, -0.3), p0 + Vector3(0, 0.9, -0.9), 0.7)
	await frames(4)
	check(e.model.body.oneshot_kind == "climb" and e.model.body.oneshot == BodyAnim.full("step_up"),
		"Klettern (≈ 0,9 m): !nakroc4a", e.model.body.oneshot)
	await seconds(1.0)
	place(e, 6, 20, 0.0)
	await seconds(0.3)
	p0 = e.global_position
	e.start_path_climb(p0, p0 + Vector3(0, 2.0, 0), p0 + Vector3(0, 3.2, -0.4), 3.0)
	await frames(6)
	check(e.model.body.state == "ladder" and _clip(e) == BodyAnim.full("ladder_up") and not e.model._weapon_mesh.visible,
		"Leiter hinauf: #LEZUP2da, Waffe weg", _clip(e))
	await seconds(3.2)
	place(e, 6, 20, 0.0)
	await seconds(0.5)
	check(e.model._weapon_mesh.visible, "Nach der Leiter: Waffe wieder in der Hand")

	# --- Schwimmen (Zustand manuell, m01 hat kein Wasser) ---
	e.set_physics_process(false)
	e.swimming = true
	e.velocity = Vector3(0, 0, -1.2)
	await _drive(e, 0.5)
	check(e.model.body.state == "swim" and _clip(e) == BodyAnim.full("swim"), "Schwimmen: !plavani3", _clip(e))
	e.velocity = Vector3.ZERO
	await _drive(e, 0.4)
	check(_clip(e) == BodyAnim.full("swim_idle"), "Wassertreten: !plavST", _clip(e))
	e.swimming = false
	e.set_physics_process(true)
	await seconds(0.4)

	# --- Treffer je Zone ---
	place(e, 6, 20, 0.0)
	await seconds(0.4)
	e.apply_hit(5.0, &"head", s, Vector3(0, 0, 1))
	await frames(2)
	check(e.model.body.oneshot == BodyAnim.full("hit_head0"), "Treffer Kopf stehend: )zhlava4", e.model.body.oneshot)
	await seconds(1.2)
	e.apply_hit(5.0, &"leg", s, Vector3(0, 0, 1))
	await frames(2)
	check(e.model.body.oneshot in [BodyAnim.full("hit_legl0"), BodyAnim.full("hit_legr0")], "Treffer Bein: )znoha*", e.model.body.oneshot)
	await seconds(1.2)

	# --- Ergeben / Gefangener ---
	e.set_meta("hands_up", true)
	await seconds(1.5)
	check(e.model.body.state == "surrender" and e.model._hold_clip == BodyAnim.upper("surrender0") and not e.model._weapon_mesh.visible,
		"Ergeben: Hände hoch !zajatecST, Waffe weg", e.model._hold_clip)
	e.set_meta("captured", true)
	e.stance_request = Soldier.Stance.CROUCH
	await seconds(1.2)
	check(e.model.body.state == "captive" and e.model._hold_clip == BodyAnim.upper("surrender1"), "Gefangener kniet: !zajatecDR", e.model._hold_clip)
	e.remove_meta("captured")
	e.remove_meta("hands_up")
	e.stance_request = Soldier.Stance.STAND
	await seconds(1.4)

	# --- Benutzen (Tür) ---
	var door: Node = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Door:
			door = n
			break
	if door:
		place(e, 6, 20, 0.0)
		await seconds(0.3)
		door.interact(e)
		await frames(3)
		check(e.model.body.oneshot_kind == "use" and e.model.body.oneshot == BodyAnim.full("door_st"), "Tür benutzen: !dvereST02",
			e.model.body.oneshot)
		await seconds(1.0)
	else:
		check(false, "Tür für den Benutzen-Test gefunden")

	# --- Tode je Richtung ---
	var deaths := {}
	var cases := [["vorn", Vector3(0, 0, 1), ["death_b1", "death_b2", "death_b3", "death_b4"]],
		["hinten", Vector3(0, 0, -1), ["death_f1", "death_f2", "death_f3", "death_f4", "death_f5"]],
		["links", Vector3(1, 0, 0), ["death_r"]], ["rechts", Vector3(-1, 0, 0), ["death_l"]]]
	for cs in cases:
		var dc: String = e.model.body.death_clip(0, cs[1], "torso", "")
		var ok := false
		for k in cs[2]:
			ok = ok or dc == BodyAnim.full(k)
		deaths[cs[0]] = ok
	check(deaths.values().all(func(v): return v), "Todesclip je Richtung (von vorn → rückwärts, hinten → vorwärts, Seite)", str(deaths))
	check(e.model.body.death_clip(1, Vector3(0, 0, -1), "torso", "") in [BodyAnim.full("death_c1"), BodyAnim.full("death_c2"),
		BodyAnim.full("death_c3"), BodyAnim.full("death_c4")], "Tod hockend: #-death*")
	check(e.model.body.death_clip(2, Vector3(0, 0, 1), "torso", "").begins_with("m_deathleh"), "Tod liegend: #deathleh*")

	await _test_b004(e, t)

	# --- Messer: schneller, Treffer im Nahbereich, von hinten tödlich ---
	s.equip(["", "", "", "", "knife"])
	s.apply_selection("slot:4")
	await seconds(0.6)
	# vorher: Treffer sofort, aber feste Sperre 60/rpm = 0,75 s; Original-Tempo (0,9) träfe nach Ereignis „t“/0,9
	var knife := WeaponDB.get_weapon(&"knife")
	var cd_before := 60.0 / maxf(knife.rpm, 1.0)
	var t_orig := BodyAnim.event_time(BodyAnim.upper("knife_st"), "t") / 0.9
	var e2: Soldier = m.enemies[1] if m.enemies[0] == e else m.enemies[0]
	reset_enemy(e2, 3, 22, 0.0)
	_freeze(e2)
	e2.max_health = 100000.0
	e2.health = 100000.0
	e2.look_yaw = PI                          # schaut dem Spieler entgegen (Stich von vorn)
	place(s, 3, 23.1, 0.0)
	await seconds(0.5)
	var hp0 := e2.health
	await hold("fire", 0.05)
	await seconds(0.5)
	var lg: Dictionary = s.knife_log[-1] if not s.knife_log.is_empty() else {}
	var dt := (float(lg.get("hit_ms", -1)) - float(lg.get("start_ms", 0))) / 1000.0
	check(e2.health < hp0, "Messer von vorn trifft im Nahbereich (1,1 m)", "%.0f → %.0f" % [hp0, e2.health])
	check(lg.get("clip", "") == BodyAnim.upper("knife_st") and dt > 0.0 and dt < t_orig,
		"Messer: Original-Clip „(bodnuti“, Zeit bis Treffer kürzer als im Original-Tempo", "%.2f s < %.2f s" % [dt, t_orig])
	check(Soldier.KNIFE_RECOVER + dt < cd_before, "Messer: Stichfolge schneller als vorher", "%.2f s < %.2f s" % [Soldier.KNIFE_RECOVER + dt, cd_before])
	# Klick während der Erholung wird gemerkt
	var n0 := s.knife_log.size()
	await hold("fire", 0.05)
	await frames(2)
	await hold("fire", 0.05)
	await seconds(0.9)
	check(s.knife_log.size() >= n0 + 2, "Messer: zweiter Klick während der Erholung wird ausgeführt", "%d Stiche" % (s.knife_log.size() - n0))
	# seitlich ganz nah (0,7 m) trifft ebenfalls
	place(e2, 3.7, 23.0, PI)
	place(s, 3, 23.0, 0.0)
	await seconds(0.3)
	hp0 = e2.health
	await hold("fire", 0.05)
	await seconds(0.5)
	check(e2.health < hp0, "Messer: ganz nah seitlich trifft", "%.2f m" % Vector2(e2.global_position.x - s.global_position.x, e2.global_position.z - s.global_position.z).length())
	# von hinten tödlich, Opfer mit Kehlschnitt-Tod
	e2.max_health = 100.0
	e2.health = 100.0
	place(e2, 3, 22, 0.0)                      # Blick nach Norden, Spieler dahinter
	place(s, 3, 23.0, 0.0)
	await seconds(0.6)
	await hold("fire", 0.05)
	await seconds(0.6)
	lg = s.knife_log[-1] if not s.knife_log.is_empty() else {}
	check(not e2.alive and lg.get("behind", false), "Messer von hinten tödlich")
	check(lg.get("clip", "") == BodyAnim.full("knife_back_st"), "Messer von hinten: Original „!podrezSTa“", str(lg.get("clip", "")))
	check(e2.model.death_clip_name == BodyAnim.full("death_throat") or e2.model.orig_figure == null,
		"Opfer: Kehlschnitt-Tod „!smrtpodrez“ (mit Original-Figur)", e2.model.death_clip_name)
	_finish()
