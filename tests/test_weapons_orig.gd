extends "res://tests/test_systems.gd"
## Original-Waffenwerte und -Animationen: Magazine gegen items.sav, Kamera (camera3RD/cameraFPV, gamecam.set),
## Zoom über Kimme/Korn und Zielfernrohr (items.sav Verhalten 5), Nachladen (anim.sav, Dauer = Nachladezeit, FPV),
## Granatwurf (Loslassen zum Auslösezeitpunkt), Erste Hilfe mit Taste H (Verbandskasten in der Hand),
## Panzerfaust nachladen (Vorgabe Auftraggeber).
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_weapons_orig


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
	for mm in m.squad.members:
		if mm != s:
			mm.global_position = s.global_position + Vector3(30, 0, 30)

	# --- 1. Magazine gegen items.sav (orig_cache/items.json: Munition je Magazin) ---
	var f := FileAccess.open(OrigLevel.cache_root() + "/items.json", FileAccess.READ)
	var items: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	var mags := {}
	for wp in items.get("weapons", []):
		mags[int(wp["id"])] = int(wp["magazine"])
	var bad: Array = []
	for k in WeaponDB.ORIG_IDS:
		var wd := WeaponDB.get_weapon(WeaponDB.ORIG_IDS[k])
		if mags.has(int(k)) and wd.magazine_size != int(mags[int(k)]):
			bad.append("%s %d≠%d" % [wd.id, wd.magazine_size, mags[int(k)]])
	check(not mags.is_empty() and bad.is_empty(), "Magazingrößen = items.sav", str(bad))
	check(WeaponDB.get_weapon(&"thompson").magazine_size == 20 and int(mags.get(20, 0)) == 20,
		"Thompson: 20 Schuss (items.sav „AMMO Thompson“)")
	var o13 := WeaponDB.from_orig(13)
	check(o13 != null and o13.magazine_size == 5, "K98 mit Zielfernrohr (o_13): 5 Schuss")

	# --- Original-Figur an den Spieler (en01) ---
	var fig := OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb")
	check(fig != null, "Original-Figur en01 geladen")
	if fig == null:
		_finish()
		return
	s.model.attach_orig(fig)
	place(s, 0, 20, 0.0)
	s.look_pitch = 0.0
	await seconds(0.5)

	# --- 2. Kamera 3. Person: Drehpunkt camera3RD, Abstand 3,0 m auf der Blickachse ---
	var rig: CameraRig = m.rig
	rig.mode = CameraRig.Mode.THIRD
	await seconds(1.0)
	var piv := s.model.camera_point(false)
	var cam := rig.camera.global_position
	var fwd := -rig.camera.global_basis.z
	var off := piv - cam
	check(absf(piv.y - s.global_position.y - 1.85) < 0.05, "Drehpunkt camera3RD stehend 1,85 m", "%.2f" % (piv.y - s.global_position.y))
	check(absf(off.length() - CameraRig.CAM3_DIST) < 0.15 and off.normalized().dot(fwd) > 0.995,
		"Kamera 3,0 m hinter dem Drehpunkt auf der Blickachse (kein Schulterversatz)", "%.2f m, dot %.3f" % [off.length(), off.normalized().dot(fwd)])
	s.stance_request = Soldier.Stance.CROUCH
	await seconds(1.2)
	var piv_c := s.model.camera_point(false)
	check(absf(piv_c.y - s.global_position.y - 1.33) < 0.08, "Hocken: Drehpunkt 1,33 m", "%.2f" % (piv_c.y - s.global_position.y))
	s.stance_request = Soldier.Stance.PRONE
	await seconds(1.6)
	var piv_p := s.model.camera_point(false)
	check(absf(piv_p.y - s.global_position.y - 0.50) < 0.08, "Liegen: Drehpunkt 0,50 m", "%.2f" % (piv_p.y - s.global_position.y))
	s.stance_request = Soldier.Stance.STAND
	await seconds(1.6)
	check(is_equal_approx(rig.pitch_limit(), deg_to_rad(70.0)), "3. Person: Nickwinkel ±70° (gamecam.set)")
	# 1. Person am Auge (cameraFPV), FPV-Modell sichtbar
	rig.toggle_mode()
	await seconds(0.5)
	var eye := s.model.camera_point(true)
	check(rig.fpv_active and rig.camera.global_position.distance_to(eye) < 0.05 and absf(eye.y - s.global_position.y - 1.62) < 0.05,
		"1. Person am Dummy cameraFPV (1,62 m)", "%.2f" % (eye.y - s.global_position.y))
	check(is_instance_valid(rig._vm_weapon) and rig._vm_anim != null, "FPV-Modell (Hände + Waffe) mit Animationen")
	check(not s.model.visible, "1. Person: eigene Figur ausgeblendet (kein Kopf-/Kragen-Clipping)")
	# Uniformwechsel (Figur ge01a, deutsch) in der 1. Person: Anker/Waffe/Sichtbarkeit am neuen Modell
	var old_fig := s.model.orig_figure
	var fig2 := OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb")
	s.put_on_uniform(Color(0.36, 0.38, 0.33), "stahlhelm", fig2)
	await seconds(0.6)
	var eye2 := s.model.camera_point(true)
	check(not is_instance_valid(old_fig) and s.model.orig_figure == fig2 and fig2.is_inside_tree(),
		"Uniformwechsel: alte Figur entfernt, neue Figur aktiv")
	check(s.model._hand != null and fig2.is_ancestor_of(s.model._hand) and s.model._weapon_mesh != null
		and s.model._weapon_mesh.get_parent() == s.model._hand, "Uniformwechsel: Waffe am hw1 der neuen Figur")
	check(rig.fpv_active and not s.model.visible and rig.camera.global_position.distance_to(eye2) < 0.05
		and absf(eye2.y - s.global_position.y - 1.6) < 0.1, "Uniformwechsel: Ego-Kamera am cameraFPV der neuen Figur",
		"%.2f m" % (eye2.y - s.global_position.y))
	Input.action_press("aim")
	await seconds(0.8)
	var ray_ok := rig.zoomed() and rig._vm_hold and rig.camera.global_position.distance_to(s.model.camera_point(true)) < 0.05
	Input.action_release("aim")
	await seconds(0.6)
	check(ray_ok, "Uniformwechsel: Zielen über Kimme/Korn in der Ego-Ansicht")
	rig.toggle_mode()
	await seconds(0.5)
	check(s.model.visible and absf(s.model.camera_point(false).y - s.global_position.y - 1.85) < 0.15,
		"Uniformwechsel: 3. Person sichtbar, Drehpunkt camera3RD der neuen Figur")

	# --- 3. Zielen: Kimme/Korn (K98: 48°) und Zielfernrohr (K98 Optik: 17°, Overlay k98) ---
	s.equip(["kar98k", "colt", "m24", "panzerfaust", "knife"])
	await seconds(0.6)
	Input.action_press("aim")
	await seconds(0.8)
	var want := OrigWeapons.vfov(48.0)
	check(rig.zoomed() and rig.fpv_active and absf(rig.camera.fov - want) < 0.5, "Zielen K98: 1. Person, FOV 48° (4:3 horizontal)",
		"%.1f / %.1f" % [rig.camera.fov, want])
	check(rig._vm_hold and rig.optic_overlay() == -1, "Kimme/Korn: Zielhaltung der FPV-Waffe, kein Overlay")
	Input.action_release("aim")
	await seconds(0.8)
	check(not rig.fpv_active and absf(rig.camera.fov - rig.base_fov()) < 0.5, "Zielen beendet: 3. Person, Grund-FOV 65°")
	# Pistole (Vorgabe Auftraggeber): Zoom 48°, Visierlinie auf die Bildmitte gelegt
	s.select_slot(WeaponData.Slot.SIDEARM)
	await seconds(1.5)
	Input.action_press("aim")
	await seconds(1.2)
	var pz_ok := rig.zoomed() and rig.fpv_active and absf(rig.camera.fov - want) < 0.5
	var fixed: bool = rig._vm_fix != Vector3.INF
	var top := Vector3.INF
	if fixed:
		top = rig._measure_sight() - rig._vm_weapon.position    # nötiger Zusatzversatz nach der Korrektur ≈ 0
	Input.action_release("aim")
	await seconds(0.8)
	check(pz_ok and fixed and top.is_finite() and Vector2(top.x, top.y).length() < 0.01,
		"Pistole: Zoom 48° in der Ego-Ansicht, Visierlinie auf der Bildmitte", str(top))
	s.equip(["o_13", "colt", "m24", "panzerfaust", "knife"])
	await seconds(0.6)
	Input.action_press("aim")
	await seconds(0.8)
	check(rig.optic_overlay() == 1 and absf(rig.camera.fov - OrigWeapons.vfov(17.0)) < 0.5 and m.hud._optic.visible,
		"Zielfernrohr K98: Overlay „k98“, FOV 17°", "%d %.1f" % [rig.optic_overlay(), rig.camera.fov])
	# Scharfschützenschuss: Ego-Waffe unter dem Overlay ausgeblendet, kein Wechsel 1./3. Person (Schuss, Repetieren,
	# Nachladen des letzten Schusses), Kamera bleibt am Auge
	var sw := s.current_weapon()
	sw.in_mag = 2
	var flips := 0
	var vm_seen := 0
	var cam_jump := 0.0
	var last_fpv := rig.fpv_active
	for shot_i in 2:
		sw.cooldown = 0.0
		Input.action_press("fire")
		await frames(2)
		Input.action_release("fire")
		for f_i in 50:
			await frames(1)
			if rig.fpv_active != last_fpv:
				flips += 1
				last_fpv = rig.fpv_active
			if rig.optic_overlay() >= 0 and rig._viewmodel.visible:
				vm_seen += 1
			var eye_p := s.model.camera_point(true)
			cam_jump = maxf(cam_jump, rig.camera.global_position.distance_to(eye_p))
		await seconds(1.2)
	s.reload()
	for f_i in 120:
		await frames(1)
		if rig.fpv_active != last_fpv:
			flips += 1
			last_fpv = rig.fpv_active
	await seconds(sw.data.reload_time)
	check(flips == 0 and rig.fpv_active and vm_seen == 0 and cam_jump < 0.05,
		"Scharfschützenschuss: Ego-Waffe unter dem Zielfernrohr unsichtbar, kein 1./3.-Person-Wechsel (Schuss, Repetieren, Nachladen)",
		"Wechsel %d, Waffe sichtbar %d Bilder, Kamera %.3f m" % [flips, vm_seen, cam_jump])
	await seconds(1.0)
	check(rig.optic_overlay() == 1, "Nach dem Nachladen wieder im Zielfernrohr", str(rig.optic_overlay()))
	Input.action_release("aim")
	await seconds(0.6)

	# --- 4. Nachladen: Original-Animation, Dauer = Nachladezeit (3. und 1. Person) ---
	s.equip(["thompson", "colt", "m24", "panzerfaust", "knife"])
	await seconds(1.0)
	var w := s.current_weapon()
	w.in_mag = 3
	s.reload()
	await frames(2)
	var hp: AnimationPlayer = s.model._hold_anim
	var clip := s.model.action_clip()
	check(clip == "h_preTSAs66" and hp.current_animation == clip, "Thompson stehend: Nachladeclip (preTSAs66)", clip)
	var speed := hp.get_playing_speed()
	var length := hp.get_animation(clip).length if clip != "" else 0.0
	check(absf(length / maxf(speed, 0.001) - w.data.reload_time) < 0.05, "Nachladeanimation dauert die Nachladezeit",
		"%.2f s / %.2f s" % [length / maxf(speed, 0.001), w.data.reload_time])
	rig.toggle_mode()
	s.reload()      # läuft bereits
	await frames(2)
	rig.toggle_mode()
	await seconds(w.data.reload_time + 0.3)
	check(w.in_mag == 20 and s.model.action_clip() == "", "Nachladen fertig: 20 Schuss, Haltung zurück", str(w.in_mag))
	rig.toggle_mode()       # 1. Person: FPV-Nachladen
	await seconds(0.4)
	w.in_mag = 2
	s.reload()
	await frames(2)
	var va: AnimationPlayer = rig._vm_anim
	check(va != null and va.current_animation == "FPVThomRel" and absf(va.get_animation("FPVThomRel").length / va.get_playing_speed() - w.data.reload_time) < 0.05,
		"1. Person: FPV-Nachladen (#FPVThomRel) synchron", va.current_animation if va else "-")
	await seconds(w.data.reload_time + 0.3)
	rig.toggle_mode()
	await seconds(0.3)

	# --- 5. Granatwurf: Animation, Granate verlässt die Hand erst zum Auslösezeitpunkt ---
	var n0 := get_tree().root.find_children("*", "Grenade", true, false).size()
	var g0 := s.weapons[2].total_ammo()
	await tap("grenade")
	check(s.is_throwing() and s.model.action_clip() == "h_hodHSTv" and s.weapons[2].total_ammo() == g0 - 1,
		"G: Wurfanimation (hodHSTv) beginnt", s.model.action_clip())
	check(get_tree().root.find_children("*", "Grenade", true, false).size() == n0, "Granate noch in der Hand")
	var rel := float(OrigWeapons.clip_info("h_hodHSTv").get("release", 0.0))
	await seconds(rel + 0.15)
	check(not s.is_throwing() and get_tree().root.find_children("*", "Grenade", true, false).size() == n0 + 1,
		"Granate verlässt die Hand nach %.2f s" % rel)
	place(s, 0, 50, 0.0)       # Abstand zur Explosion
	await seconds(5.0)

	# --- 6. Erste Hilfe mit Taste H: Verbandskasten in der Hand, Original-Animation ---
	check(InputSetup.binding_text("medkit") == "H" and InputSetup.binding_text("order_follow") == "U",
		"Tastenbelegung: Erste Hilfe H, Folgen U", "%s / %s" % [InputSetup.binding_text("medkit"), InputSetup.binding_text("order_follow")])
	s.health = s.max_health * 0.5
	s.medkits = 1
	var hk := InputEventKey.new()
	hk.physical_keycode = KEY_H
	hk.pressed = true
	Input.parse_input_event(hk)
	Input.flush_buffered_events()
	await frames(3)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_H
	up.pressed = false
	Input.parse_input_event(up)
	await frames(10)
	var prop := s.model.prop()
	check(s.heal_time_left > 0.0 and prop != null and prop.get_parent() == s.model._hand and s.model.full_clip() == "medic_self",
		"H: Verband (Selbstversorgung), Verbandskasten l_medkit in der Hand, Animation !medik", s.model.full_clip())
	await seconds(Soldier.HEAL_DURATION + 0.3)
	check(s.health > s.max_health * 0.5 and s.medkits == 0 and s.model.prop() == null and s.model.full_clip() == "",
		"Verband fertig: geheilt, Kasten weg", "%.0f HP" % s.health)

	# --- 7. Panzerfaust nachladen mit Raketen-Munition (Vorgabe Auftraggeber) ---
	check(WeaponDB.LAUNCHER_AMMO.get(38, -1) == WeaponDB.PANZERFAUST_AMMO and SAS.ammo_of(38) == WeaponDB.PANZERFAUST_AMMO
		and SAS.weapon_of_ammo(WeaponDB.PANZERFAUST_AMMO) == 38 and SAS.item_kind(WeaponDB.PANZERFAUST_AMMO) == "ammo",
		"Panzerfaust-Rakete: eigener Munitionsgegenstand (Inventar/Lager)", SAS.item_label(WeaponDB.PANZERFAUST_AMMO))
	var inv := SAS.new_inventory()
	inv["shoulder"] = 38
	SAS.add_item(inv, WeaponDB.PANZERFAUST_AMMO, 2)
	check(int(SAS.to_loadout(inv)["launcher_shots"]) == 3, "Inventar: Panzerfaust + 2 Raketen = 3 Schuss")
	var st := SAS.mission_storage({"equipment_screen": "equipment_new_storage",
		"storage_items_campaign": [{"item": 38, "count": 1}]}, [])
	check(SAS.count_of({"items": st}, WeaponDB.PANZERFAUST_AMMO) == 2, "Lager: Raketen zur Panzerfaust")
	s.apply_selection("slot:3")
	await seconds(0.5)
	var pf := s.current_weapon()
	pf.in_mag = 1
	pf.reserve = 1
	check(pf.data.id == &"panzerfaust", "Panzerfaust gewählt")
	pf.in_mag = 0                       # Schuss (Weapon.trigger verbraucht die Ladung)
	s._fire_rocket(pf, s.eye_position(), s.aim_direction())
	await seconds(1.0)
	check(s.weapons[WeaponData.Slot.LAUNCHER] == pf, "Leere Panzerfaust bleibt (nachladbar)")
	check(s.reload() and s.model.action_clip() == "h_bazRELst", "Panzerfaust nachladen: Bazooka-Nachladeanimation (3. Person)", s.model.action_clip())
	await seconds(pf.data.reload_time + 0.3)
	check(pf.in_mag == 1 and pf.reserve == 0, "Panzerfaust mit Rakete nachgeladen (Vorrat verbraucht)")
	rig.toggle_mode()
	await seconds(0.5)
	pf.in_mag = 0
	pf.reserve = 1
	s.reload()
	await frames(3)
	var pva: AnimationPlayer = rig._vm_anim
	check(pva != null and pva.current_animation == "FPVBazReload", "1. Person: Panzerfaust-Nachladen (Bazooka-FPV-Clip)",
		pva.current_animation if pva else "-")
	await seconds(pf.data.reload_time + 0.3)
	rig.toggle_mode()
	pf.in_mag = 0
	pf.reserve = 0
	s._fire_rocket(pf, s.eye_position(), s.aim_direction())
	await seconds(1.0)
	check(s.weapons[WeaponData.Slot.LAUNCHER] == pf and not s.reload(), "Ohne Rakete: Rohr bleibt, kein Nachladen")
	await _hud_panel(m, s)
	await _hands_and_fire(m, s)
	await _fpv_extras(m, s)
	await _camera_modes(m, s)
	_finish()


## Bildschleifen (HUD aktualisiert in _process; frames() zählt Physiktakte)
func _pframes(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## --- 8. HUD rechts unten (tabl02, hd2.exe 0x4A9530): Symbol Hand/Schulter = Waffenbilder (wi_*), Munition ---
func _hud_panel(m: Mission, s: Soldier) -> void:
	var oh: OrigHud = m.hud.orig_hud
	check(oh != null, "Original-HUD aktiv")
	if oh == null:
		return
	s.equip(["enfield", "colt", "no36", "panzerfaust", "knife"])
	s.select_slot(WeaponData.Slot.PRIMARY)
	await frames(3)
	var w := s.current_weapon()
	check(oh.icon_of("i_hands").get_file() == "wi_br-enflmk4.png" and oh.icon_of("i_shoulder").get_file() == "wi_ge-panzfau60.png",
		"Hand: Waffenbild Enfield (wi_*), Schulter: Panzerfaust (nicht Munitionssymbole ii_*-m)",
		"%s / %s" % [oh.icon_of("i_hands"), oh.icon_of("i_shoulder")])
	var mags := int(ceil(float(w.reserve) / w.data.magazine_size))
	check(oh.ammo_labels["hands"].text == "%d/%d" % [w.in_mag, mags], "Munition Hand „Schuss/Magazine“ (%%d/%%d)",
		"%s (Reserve %d)" % [oh.ammo_labels["hands"].text, w.reserve])
	check(oh.ammo_labels["name"].text == SAS.item_label(OrigHud.weapon_item(w, s.team)) and oh.ammo_labels["grenades"].text == str(s.weapons[2].total_ammo()),
		"Name der Handwaffe (Originaltext) und Granatenzahl", "%s / %s" % [oh.ammo_labels["name"].text, oh.ammo_labels["grenades"].text])
	check(oh.ammo_labels["shoulder"].text == "%d/%d" % [s.weapons[3].in_mag, s.weapons[3].reserve], "Schulterwaffe: Rakete/Raketen",
		oh.ammo_labels["shoulder"].text)
	# sofort nach einem Schuss
	w.in_mag -= 1
	await _pframes(2)
	check(oh.ammo_labels["hands"].text.begins_with("%d/" % w.in_mag), "Munition sofort aktualisiert (Schuss)", oh.ammo_labels["hands"].text)
	# Wechsel auf Pistole: Hand = Colt, Schulter = Gewehr
	s.select_slot(WeaponData.Slot.SIDEARM)
	await _pframes(2)
	var pw := s.current_weapon()
	check(oh.icon_of("i_hands").get_file() == "wi_us-clt1911.png" and oh.icon_of("i_shoulder").get_file() == "wi_br-enflmk4.png"
		and oh.ammo_labels["hands"].text == "%d/%d" % [pw.in_mag, int(ceil(float(pw.reserve) / pw.data.magazine_size))],
		"Waffenwechsel Pistole: sofort Colt in der Hand, Gewehr auf der Schulter", "%s %s %s" % [oh.icon_of("i_hands"), oh.icon_of("i_shoulder"), oh.ammo_labels["hands"].text])
	# Granate: 1 in der Hand / übrige
	s.select_slot(WeaponData.Slot.GRENADE)
	await _pframes(2)
	var gn := s.weapons[2].total_ammo()
	check(oh.icon_of("i_hands").get_file() == "wi_br-gren-no36.png" and oh.ammo_labels["hands"].text == "1/%d" % (gn - 1),
		"Granate: Symbol No.36, „1/übrige“", "%s %s" % [oh.icon_of("i_hands"), oh.ammo_labels["hands"].text])
	# Panzerfaust: Rakete im Rohr / Raketen-Munition
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await _pframes(2)
	var lw := s.current_weapon()
	lw.in_mag = 1
	lw.reserve = 2
	await _pframes(2)
	check(oh.icon_of("i_hands").get_file() == "wi_ge-panzfau60.png" and oh.ammo_labels["hands"].text == "1/2"
		and oh.icon_of("i_shoulder").get_file() == "wi_br-enflmk4.png", "Panzerfaust: Rakete im Rohr / Panzerfaust-Raketen",
		oh.ammo_labels["hands"].text)
	# Aufheben: Reserve steigt -> sofort sichtbar
	lw.reserve = 4
	await _pframes(2)
	check(oh.ammo_labels["hands"].text == "1/4", "Aufgenommene Raketen sofort angezeigt", oh.ammo_labels["hands"].text)
	# Messer: Symbol, keine Munitionszahl; Verbandskasten als Hilfsmittel
	s.select_slot(WeaponData.Slot.MELEE)
	await _pframes(2)
	check(oh.icon_of("i_hands").get_file() == "wi_br-knife.png" and oh.ammo_labels["hands"].text == "", "Messer: Symbol ohne Munition",
		oh.icon_of("i_hands"))
	s.medkits = 3
	s.apply_selection("medkit")
	await _pframes(2)
	check(s.tool != "medkit" or (oh.icon_of("i_hands").get_file() == "ii_aid.png" and oh.ammo_labels["hands"].text == "1/2"),
		"Verbandskasten in der Hand: Symbol ii_aid, „1/2“", "%s %s %s" % [s.tool, oh.icon_of("i_hands"), oh.ammo_labels["hands"].text])
	s.select_slot(WeaponData.Slot.PRIMARY)
	await seconds(0.6)


## --- 9. Linke Hand am Griff (IK), Raketenwerfer auf der Schulter, Feuerclips + Rückstoß (3. Person) ---
func _hands_and_fire(m: Mission, _s0: Soldier) -> void:
	var rig: CameraRig = m.rig
	if rig.mode != CameraRig.Mode.THIRD:
		rig.toggle_mode()
	# Kamerad ohne KI (Absichten direkt gesetzt, keine Zoom-Ansicht des Spielers)
	var s: Soldier = m.squad.members[1]
	var br: Node = m.squad.brain_of(s)
	if br:
		br.process_mode = Node.PROCESS_MODE_DISABLED
	s.model.attach_orig(OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb"))
	place(s, 3, 20, 0.0)
	s.move_input = Vector3.ZERO
	s.look_pitch = 0.0
	s.equip(["enfield", "colt", "no36", "bazooka", "knife"])
	await seconds(0.8)
	var res := []
	for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
		s.stance_request = st
		await seconds(1.6)
		var calm := s.model.left_hand_error()
		s.aiming = true
		await seconds(0.8)
		var aim := s.model.left_hand_error()
		s.aiming = false
		await seconds(0.5)
		res.append([st, snappedf(calm, 0.001), snappedf(aim, 0.001)])
	s.stance_request = Soldier.Stance.STAND
	var ok := true
	for r in res:
		ok = ok and r[1] >= 0.0 and r[1] < 0.02 and r[2] >= 0.0 and r[2] < 0.02
	check(ok, "Linke Hand am Griff LW (IK) stehend/hockend/liegend, Ruhe + Anschlag (< 2 cm)", str(res))
	await seconds(1.6)
	# Raketenwerfer im Anschlag: Rohr über dem Griff auf Schulterhöhe (nicht vor der Brust)
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await seconds(1.2)
	s.aiming = true
	await seconds(1.2)
	var wm: Node3D = s.model._weapon_mesh
	var hand: Node3D = s.model._hand
	var tube := (wm.find_child("LW", true, false) as Node3D).global_position
	var sk: Skeleton3D = s.model.orig_figure.find_children("*", "Skeleton3D", true, false)[0]
	var shoulder := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("h"))).origin
	var up_w := wm.global_basis.y
	check(tube.y > hand.global_position.y and up_w.y > 0.5 and tube.y > shoulder.y - 0.05,
		"Bazooka im Anschlag auf der Schulter (Rohr über dem Griff, Schulterhöhe)",
		"Rohr %.2f Griff %.2f Schulter %.2f up.y %.2f" % [tube.y - s.global_position.y, hand.global_position.y - s.global_position.y,
		shoulder.y - s.global_position.y, up_w.y])
	var barrel := -wm.global_basis.z
	check(barrel.dot(s.aim_direction()) > 0.97, "Bazooka zielt in Blickrichtung", "%.3f" % barrel.dot(s.aim_direction()))
	check(s.model.left_hand_error() >= 0.0 and s.model.left_hand_error() < 0.02, "Bazooka: linke Hand am vorderen Griff",
		"%.3f" % s.model.left_hand_error())
	s.aiming = false
	await seconds(0.8)
	# Feuerclip (anim.sav +0x3A0) beim Schuss in der 3. Person, Rückstoß
	s.select_slot(WeaponData.Slot.PRIMARY)
	await seconds(1.2)
	var w := s.current_weapon()
	w.in_mag = 5
	w.cooldown = 0.0
	s.trigger = true
	await frames(3)
	s.trigger = false
	await frames(2)
	check(s.model.fire_clip() == "h_puf" and s.model._hold_anim.current_animation == "h_puf" and s.model.recoil > 0.3,
		"Schuss 3. Person: Feuerclip !_puf (Gewehr stehend) + Rückstoß", "%s %.2f" % [s.model.fire_clip(), s.model.recoil])
	await seconds(1.2)
	check(s.model.fire_clip() == "" and s.model._hold_clip == OrigWeapons.hold_clip("rifle", "calm", 0),
		"Nach dem Feuerclip zurück in die Haltung", s.model._hold_clip)
	# Pistole: eigener Feuerclip
	s.select_slot(WeaponData.Slot.SIDEARM)
	await seconds(1.2)
	var pw := s.current_weapon()
	await seconds(1.0)
	pw.cooldown = 0.0
	var pm := pw.in_mag
	s.trigger = true
	await frames(3)
	s.trigger = false
	await frames(2)
	check(s.model.fire_clip() == "h_pufPst", "Pistole: Feuerclip !pufPst",
		"%s, Schuss %d->%d, Aktion %s" % [s.model.fire_clip(), pm, pw.in_mag, s.model.action_clip()])
	s.select_slot(WeaponData.Slot.PRIMARY)
	await seconds(1.2)
	place(s, 30, 30, 0.0)
	if br:
		br.process_mode = Node.PROCESS_MODE_INHERIT


## --- 10. Ego-Ansicht: Hände nach Uniform, keine Wanddurchdringung, Panzerfaust-Nachladen mit Abstand ---
func _fpv_extras(m: Mission, s: Soldier) -> void:
	var rig: CameraRig = m.rig
	rig.toggle_mode()
	await seconds(0.6)
	var fig_name := String(s.model.orig_figure.get_meta("figure_model", ""))
	var want := OrigWeapons.fpv_hands_for(fig_name)
	var hands_mi: MeshInstance3D = null
	for mi in rig._vm_weapon.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			hands_mi = mi
	check(want != "" and hands_mi != null and String(hands_mi.get_meta("fpv_hands", OrigWeapons.FPV_HANDS_DEFAULT)) == want,
		"Ego-Hände passend zur Uniform (%s -> %s)" % [fig_name, want], str(hands_mi.get_meta("fpv_hands", "") if hands_mi else "-"))
	check(rig.vm_no_clip_count > 0, "Ego-Waffe mit verkleinerter Clip-Tiefe (ragt nicht durch Wände)", str(rig.vm_no_clip_count))
	# Panzerfaust-Nachladen: Hände bleiben vom Auge entfernt
	s.equip(["enfield", "colt", "no36", "panzerfaust", "knife"])
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await seconds(2.6)
	var pf := s.current_weapon()
	pf.in_mag = 0
	pf.reserve = 1
	s.reload()
	var near := 99.0
	var t := 0.0
	while t < pf.data.reload_time:
		await frames(2)
		t += 2.0 / 60.0
		near = minf(near, _hands_dist(rig))
	check(near > 0.22, "Panzerfaust-Nachladen (1. Person): Hände ≥ 22 cm vor dem Auge", "%.3f m" % near)
	await seconds(0.5)
	rig.toggle_mode()
	await seconds(0.4)


## Kleinster Abstand der FPV-Handknochen zur Kamera (m, im Kameraraum).
func _hands_dist(rig: CameraRig) -> float:
	var d := 99.0
	if not is_instance_valid(rig._vm_weapon):
		return d
	for skn in rig._vm_weapon.find_children("*", "Skeleton3D", true, false):
		var sk := skn as Skeleton3D
		for bn in ["Bip01 L Hand", "Bip01 R Hand", "Bip01 L Forearm", "Bip01 R Forearm"]:
			var b := sk.find_bone(bn)
			if b < 0:
				continue
			var p := rig.camera.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(b)).origin
			d = minf(d, p.length())
	return d


## --- 11. Kameramodi gamecam.set: Innenraum (Sektor) und Wasser ---
func _camera_modes(m: Mission, s: Soldier) -> void:
	var rig: CameraRig = m.rig
	if rig.mode != CameraRig.Mode.THIRD:
		rig.toggle_mode()
	place(s, 0, 20, 0.0)
	await seconds(1.0)
	check(rig.cam_mode == 1 and absf(rig._dist - 3.0) < 0.1, "Draußen: Modus 1 (3,0 m)", "%d %.2f" % [rig.cam_mode, rig._dist])
	# künstlicher Innensektor mit Dach über dem Spieler
	var roof := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(8, 0.2, 8)
	cs.shape = bx
	roof.add_child(cs)
	m.add_child(roof)
	roof.global_position = s.global_position + Vector3.UP * 3.2
	rig.sector_boxes = [["sector test", AABB(s.global_position + Vector3(-4, -0.5, -4), Vector3(8, 4, 8))]]
	await seconds(0.8)
	check(rig.interior and rig.cam_mode == 3 and absf(rig._dist - 1.5) < 0.1 and is_equal_approx(rig.pitch_limit(), deg_to_rad(80.0)),
		"Innenraum: Modus 3 (1,5 m, ±80°)", "%d %.2f" % [rig.cam_mode, rig._dist])
	# Schwimmen (Soldier.swimming setzt die Physik je Bild aus dem Wasserspiegel; hier direkt geprüft)
	s.swimming = true
	rig._select_cam_mode()
	var m6 := rig.cam_mode
	s.swimming = false
	roof.queue_free()
	rig.sector_boxes = []
	s.swimming = true
	rig._select_cam_mode()
	var m5 := rig.cam_mode
	var lim5 := rig.pitch_limit()
	s.swimming = false
	await seconds(0.8)
	check(m6 == 6 and m5 == 5 and is_equal_approx(lim5, deg_to_rad(85.0)) and rig.cam_mode == 1,
		"Wasser: Modus 5 draußen / 6 drinnen (±85°), danach wieder Modus 1", "%d %d %d" % [m6, m5, rig.cam_mode])
	rig.sector_boxes = null