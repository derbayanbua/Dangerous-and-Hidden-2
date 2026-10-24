extends "res://tests/test_gameplay.gd"
## Panzer und Waffenstellungen nach Original (docs/re_notes_ai.md §3/§4): AFRICA1 Panzer III „panzer01“ mit Besatzung
## (Originalskripte af1_tank01_01..03: HUMAN_BoardVehicle(panzer01, 1, Sitz)), Turm/Kanone/MG mit den Rohr-Parametern
## des Modells (BARRELnn_00: itemid, hs/vs, up/down/left/right; hd2.exe 0x4C1AD0/0x4C2580), Schadensmodell
## DMla_Panzer IIIAf.4ds (D_ZONE HP/matid, EXPL_D; 0x4E1A20), KI-Richtschütze, KI an MG-Stellung, Alarmarten.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_tank [--shots=1 (Fenster)]


var _shells: Array = []


func _on_node_added(n: Node) -> void:
	if n is Grenade:
		_shells.append(n)


func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not Game.cli.has("shots"):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	img.save_png(ProjectSettings.globalize_path("res://test_output/tank_%s.png" % name))
	print("BILD test_output/tank_%s.png" % name)


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.runtime != null, "AFRICA1 geladen")
	if m == null:
		_finish()
		return
	var rt: LsRuntime = m.runtime
	rt.auto_skip = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	var tank := rt.find_frame("panzer01") as Vehicle
	check(tank != null, "Panzer III (Akteur panzer01) als Fahrzeug")
	if tank == null:
		_finish()
		return
	var hale: Soldier = m.squad.leader()

	# --- Schadensmodell DMla_Panzer IIIAf.4ds ---
	var dm := tank.damage_model
	check(dm != null and dm.zones.size() == 12 and dm.expls.size() == 2,
		"Schadensmodell geladen (12 D_ZONE, 2 EXPL_D)", "%s Zonen" % (str(dm.zones.size()) if dm else "-"))
	if dm:
		var hp_sum := 0
		var mats := {}
		for z in dm.zones:
			hp_sum += int(z["hp0"])
			mats[int(z["matid"])] = true
		check(hp_sum == 14600 and mats.has(16) and mats.has(17) and mats.has(15), "Zonen-HP/Material aus dem Modell",
			"Summe %d, matid %s" % [hp_sum, str(mats.keys())])
		check(is_equal_approx(VehicleDamage.armor_of(16), 1750.0) and is_equal_approx(VehicleDamage.armor_of(17), 3500.0),
			"Panzerung aus hdmaterials.def (+0x28): matid16 1750, matid17 3500")
	# --- Turm/Rohr-Parameter und Waffen aus BARRELnn_00 ---
	check(tank.seats.size() >= 3, "Sitze aus dem Originalmodell (SEAT00…)", str(tank.seats.size()))
	var cannon_seat := -1
	var mg_seat := -1
	for i in tank.turrets:
		var w: Weapon = tank.turrets[i].get("weapon")
		if w and w.data.action == WeaponData.Action.ROCKET:
			cannon_seat = i
		elif w:
			mg_seat = i
	check(cannon_seat == 2 and mg_seat == 1, "Kanone an SEAT02, MG an SEAT01 (BARREL02_00/BARREL01_00)", "%d/%d" % [cannon_seat, mg_seat])
	if cannon_seat < 0 or mg_seat < 0:
		_finish()
		return
	var tc: Dictionary = tank.turrets[cannon_seat]
	var tm: Dictionary = tank.turrets[mg_seat]
	var wc: Weapon = tc["weapon"]
	check(int(tc.get("itemid", -1)) == 51 and wc.data.display_name.contains("KwK"), "Kanone = itemid 51 (KwK 36)", wc.data.display_name)
	check(is_equal_approx(wc.data.damage, 325.0) and is_equal_approx(wc.data.blast_radius, 6.0) and is_equal_approx(wc.data.muzzle_velocity, 250.0),
		"KwK 36: Stärke 3250 zotti, Radius 6 m, v0 250 (items.sav)", "%.0f / %.1f / %.0f" % [wc.data.damage, wc.data.blast_radius, wc.data.muzzle_velocity])
	check(int(tm.get("itemid", -1)) == 48, "Bug-MG = itemid 48 (TANK MG34)", (tm["weapon"] as Weapon).data.display_name)
	check(is_equal_approx(rad_to_deg(tc["hs"]), 95.0) and is_equal_approx(rad_to_deg(tc["vs"]), 20.0)
		and is_equal_approx(rad_to_deg(tc["up"]), 15.0) and is_equal_approx(rad_to_deg(tc["down"]), 10.0)
		and tc["left"] >= Vehicle.NO_LIMIT, "Kanone: hs 95°/s, vs 20°/s, +15°/−10°, Seite frei (BARREL02_00)")
	check(is_equal_approx(rad_to_deg(tm["hs"]), 160.0) and is_equal_approx(rad_to_deg(tm["left"]), 30.0)
		and is_equal_approx(rad_to_deg(tm["right"]), 30.0), "Bug-MG: hs 160°/s, ±30° (BARREL01_00)")
	# Besatzung laut Originalskript
	var crew := 0
	for o in tank.occupants:
		if is_instance_valid(o) and (o as Soldier).team == Soldier.TEAM_AXIS:
			crew += 1
	check(crew >= 2, "Besatzung eingestiegen (HUMAN_BoardVehicle mit Sitznummer)", "%d Mann" % crew)
	var gunner = tank.occupants[cannon_seat]
	check(is_instance_valid(gunner) and not (gunner as Soldier).model.visible, "Besatzung im Panzer unsichtbar")

	# --- KI-Richtschütze bekämpft einen sichtbaren Gegner mit der Kanone ---
	if is_instance_valid(gunner):
		var gs := gunner as Soldier
		var gb := gs.get_node("EnemyBrain") as EnemyBrain
		gb.enabled = true
		gb.suspended = false
		gb.script_control = false
		gs.set_physics_process(true)
		var fwd := tank.turret_dir(cannon_seat)
		fwd.y = 0.0
		# Ziel vor dem ersten Hindernis in Rohrrichtung, auf den Boden gestellt
		var mz := tank.muzzle_point(cannon_seat)
		var fq := PhysicsRayQueryParameters3D.create(mz, mz + fwd.normalized() * 22.0, 1, [tank.get_rid()])
		var fh := tank.get_world_3d().direct_space_state.intersect_ray(fq)
		var fdist := 22.0 if fh.is_empty() else clampf(mz.distance_to(fh.position) - 1.5, 6.0, 22.0)
		var gp := mz + fwd.normalized() * fdist
		var gq := PhysicsRayQueryParameters3D.create(gp + Vector3.UP * 3.0, gp + Vector3.DOWN * 10.0, 1, [tank.get_rid()])
		var gh := tank.get_world_3d().direct_space_state.intersect_ray(gq)
		hale.global_position = (gh.position as Vector3) + Vector3.UP * 0.1 if not gh.is_empty() else gp
		hale.velocity = Vector3.ZERO
		hale.max_health = 99999.0
		hale.health = 99999.0
		var per: Perception = gs.get_node("Perception")
		per.sight_range = 80.0
		per.awareness[hale] = 1.0
		per.last_known[hale] = hale.global_position
		var ai_shots := [0]
		gs.shot_fired.connect(func(_w): ai_shots[0] += 1)
		for i in 90:
			await frames(6)
			if ai_shots[0] >= 1:
				break
		check(ai_shots[0] >= 1, "KI-Richtschütze feuert die Kanone auf den Gegner", "%d Schuss" % ai_shots[0])
		await shot("ki_feuert")
		gb.enabled = false

	# --- Handwaffen gegen Panzerung (Schaden 48,8 = K98 488 zotti < Panzerung 1750): Zone unverändert ---
	if dm:
		var z0: Node3D = dm.zones[0]["node"]
		var at := z0.global_position + tank.global_basis.y * 0.3
		var dir := -tank.global_basis.z
		var hp_before: Array = dm.zones.map(func(z): return int(z["hp"]))
		for i in 5:
			tank.projectile_hit(1, 48.8, at, dir, hale)
		check(dm.zones.map(func(z): return int(z["hp"])) == hp_before and not tank.wrecked, "Gewehrtreffer: Panzerung hält (Rest ≤ 0)")
		# Explosion einer Handgranate (1999 zotti) in 4 m Abstand: (1 − 4/10)·1999 = 1199 < 1750 → kein Schaden
		tank.explosion_at(tank.global_position + tank.global_basis.x * (tank._size.x * 0.5 + 4.0) + Vector3.UP, 10.0, 199.9, hale)
		check(dm.zones.map(func(z): return int(z["hp"])) == hp_before, "Granate in 4 m: unter der Panzerung, kein Schaden")

	# --- Spieler übernimmt die Kanone: Besatzung raus, Spieler an den Turmsitz ---
	var crew_list: Array = []
	for o in tank.occupants.duplicate():
		if is_instance_valid(o):
			crew_list.append(o)
			tank.leave(o)
			(o as Soldier).global_position += Vector3(40, 0, 0)
			(o as Soldier).get_node("EnemyBrain").enabled = false
	var own_weapons := hale.weapons.duplicate()
	hale.max_health = 100.0
	hale.health = 100.0
	hale.global_position = tank.global_position + tank.global_basis.x * 3.0
	check(tank.board(hale, false, cannon_seat), "Spieler besetzt den Kanonensitz")
	check(hale.current_weapon() and hale.current_weapon().data.action == WeaponData.Action.ROCKET, "Kanone in der Hand des Schützen")
	var d0 := tank.turret_dir(cannon_seat)
	var yaw0 := atan2(-d0.x, -d0.z)
	# Blick per Maus weit nach links: der Turm folgt mit hs = 95°/s (0,5 s Physik ≈ 47,5°)
	for i in 30:
		var cd := tank.turret_dir(cannon_seat)
		hale.look_yaw = atan2(-cd.x, -cd.z) + 1.0       # Maus immer weiter links: Turm dreht mit voller Geschwindigkeit
		await get_tree().physics_frame
	var d1 := tank.turret_dir(cannon_seat)
	var turned := absf(angle_difference(yaw0, atan2(-d1.x, -d1.z)))
	var phys_dt := 30.0 / float(Engine.physics_ticks_per_second)
	check(absf(turned - deg_to_rad(95.0) * phys_dt) < 0.06, "Turm dreht mit Original-Geschwindigkeit (95°/s)",
		"%.1f° in %.2f s Physik (Soll %.1f°)" % [rad_to_deg(turned), phys_dt, 95.0 * phys_dt])
	# Höhe: Blick steil nach oben → höchstens +15°
	for i in 90:
		hale.look_pitch = 1.0
		await get_tree().physics_frame
	var pitch_up := asin(tank.turret_dir(cannon_seat).y)
	check(absf(rad_to_deg(pitch_up) - 15.0) < 2.5, "Kanone hebt höchstens +15° (up15)", "%.1f°" % rad_to_deg(pitch_up))
	await shot("kanone_hoch")
	for i in 90:
		hale.look_pitch = 0.0
		await get_tree().physics_frame
	# Schuss mit der Kanone: Ziel vor dem Rohr
	var target: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and not crew_list.has(e):
			target = e
			break
	var mp := tank.muzzle_point(cannon_seat)
	var dir2 := tank.turret_dir(cannon_seat)
	dir2.y = 0.0
	target.get_node("EnemyBrain").enabled = false
	var q := PhysicsRayQueryParameters3D.create(mp, mp + dir2.normalized() * 20.0, 1 | 2, [tank.get_rid()])
	var hit := tank.get_world_3d().direct_space_state.intersect_ray(q)
	var tdist := 8.0 if hit.is_empty() else clampf(mp.distance_to(hit.position) - 1.5, 4.0, 8.0)
	target.global_position = mp + dir2.normalized() * tdist + Vector3.DOWN * 1.0
	target.set_physics_process(true)
	var hp_t := target.health
	await seconds(0.5)
	for i in 90:
		var tp := target.global_position + Vector3.UP * 0.9 - tank.muzzle_point(cannon_seat)
		hale.look_yaw = rotate_toward(hale.look_yaw, atan2(-tp.x, -tp.z), 0.2)
		hale.look_pitch = move_toward(hale.look_pitch, atan2(tp.y, Vector2(tp.x, tp.z).length()), 0.05)
		await frames(1)
	var ammo0: int = hale.current_weapon().total_ammo()
	var integ0 := dm.integrity() if dm else 1.0
	Input.action_press("fire")
	await frames(4)
	Input.action_release("fire")
	await seconds(1.5)
	check(hale.current_weapon().total_ammo() == ammo0 - 1, "Kanone feuert (Munition −1)")
	check(not target.alive or target.health < hp_t, "Granate trifft das Ziel vor dem Rohr", "%.0f -> %.0f" % [hp_t, target.health])
	check(not tank.wrecked and (dm == null or is_equal_approx(dm.integrity(), integ0)), "Eigene Granate beschädigt den Panzer nicht")
	await shot("kanone")
	tank.leave(hale)
	var restored := hale.weapons.size() == own_weapons.size()
	for i in own_weapons.size():
		restored = restored and hale.weapons[i] == own_weapons[i]
	check(restored and hale.model.visible, "Aussteigen: eigene Waffen zurück, sichtbar")

	# --- Bug-MG: Seitengrenze ±30° ---
	hale.global_position = tank.global_position + tank.global_basis.x * 3.0
	if tank.board(hale, false, mg_seat):
		var dm0 := tank.turret_dir(mg_seat)
		var my0 := atan2(-dm0.x, -dm0.z)
		for i in 120:
			hale.look_yaw = my0 + 1.5
			await get_tree().physics_frame
		var dm1 := tank.turret_dir(mg_seat)
		var side := absf(angle_difference(my0, atan2(-dm1.x, -dm1.z)))
		check(absf(rad_to_deg(side) - 30.0) < 3.0, "Bug-MG schwenkt höchstens 30° zur Seite", "%.1f°" % rad_to_deg(side))
		tank.leave(hale)

	# --- KI besetzt MG-Stellung per Originalbefehl ---
	var empl = m.interactive.controls.get("W_MG42CROUCH_01")
	check(empl != null, "MG-Stellung w_mg42Crouch_01 (Typ 21)")
	var gun: Soldier = null
	if empl and is_instance_valid(empl.gunner):
		var g0: Soldier = empl.gunner
		empl.dismount()
		g0.global_position += Vector3(30, 0, 0)
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e != target and e.vehicle == null and e.mounted == null and not crew_list.has(e):
			gun = e
			break
	if empl and gun:
		gun.global_position = empl.gunner_spot() + Vector3(5.0, 0.3, 0.0)
		gun.set_physics_process(true)
		var gb := gun.get_node("EnemyBrain") as EnemyBrain
		gb.enabled = true
		gb.suspended = false
		var vm := LsVM.new(LsCompiler.new(), gun, rt)
		var res = rt.call_api(vm, "HUMAN_BOARDVEHICLE", [["str", "w_mg42Crouch_01"], ["num", 1], ["num", 0]])
		for i in 80:
			await frames(6)
			if gun.mounted != null:
				break
			if res is Dictionary and (res["wait_until"] as Callable).call():
				break
		check(gun.mounted == empl and gun.current_weapon() and gun.current_weapon().data == empl.data,
			"KI besetzt die MG-Stellung (HUMAN_BoardVehicle(Stellung, 1, 0))", "%s, Abstand %.1f m, Zustand %s, Skript %s" % [
			empl.data.display_name, gun.global_position.distance_to(empl.gunner_spot()), gb.state_name(), gb.script_control])
		check(empl.data.display_name.contains("MG"), "Stellungswaffe über die Munition (216 → MG 42)", empl.data.display_name)
		hale.global_position = empl.gunner_spot() - empl.frame.global_basis.z.normalized() * 18.0 + Vector3.UP * 0.5
		var per2: Perception = gun.get_node("Perception")
		per2.sight_range = 80.0
		per2.awareness[hale] = 1.0
		per2.last_known[hale] = hale.global_position
		gb.script_control = false
		var shots := [0]
		gun.shot_fired.connect(func(_w): shots[0] += 1)
		hale.max_health = 99999.0
		hale.health = 99999.0
		for i in 40:
			await frames(6)
			if shots[0] >= 3:
				break
		check(shots[0] >= 3, "KI feuert mit dem Stellungs-MG", "%d Schüsse" % shots[0])
		check(gun.mounted == empl, "Schütze bleibt an der Stellung")
		await shot("stellung_ki")
		rt.call_api(vm, "HUMAN_BOARDVEHICLE", [["str", ""], ["num", 1], ["num", 0]])
		check(gun.mounted == null and empl.gunner == null and (gun.current_weapon() == null or gun.current_weapon().data != empl.data),
			"Verlassen der Stellung (leerer Name)", "mounted %s" % gun.mounted)

	# --- Alarmarten: SetAlarmType-Maske und _GetAlarmType ---
	var g2: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e != gun and e.vehicle == null and rt.vm_for(e) != null:
			g2 = e
			break
	if g2:
		var b2 := g2.get_node("EnemyBrain") as EnemyBrain
		var vm2 := LsVM.new(LsCompiler.new(), g2, rt)
		rt.call_api(vm2, "SETALARMTYPE", [["num", 1023], ["num", 0]])
		rt.call_api(vm2, "SETALARMTYPE", [["num", 16], ["num", 1]])
		check(b2.alarm_mask == 16, "SetAlarmType: Maske gesetzt/gelöscht", str(b2.alarm_mask))
		b2._alarm_notified = false
		b2.script_alarm_enabled = true
		b2.events_enabled = true
		b2._script_alarm(EnemyBrain.AL_SEE, hale.global_position)
		check(not b2._alarm_notified, "Gesperrte Alarmart (32 gesehen) löst kein OnAlarm aus")
		b2._script_alarm(EnemyBrain.AL_EXPLOSION, hale.global_position)
		check(b2._alarm_notified and int(rt.call_api(vm2, "_GETALARMTYPE", [])) == 16, "Erlaubte Alarmart: OnAlarm, _GetAlarmType = 16")
		var r = rt.call_api(vm2, "HUMAN_MOVETOALARM", [])
		check(r is Dictionary and b2._script_target.distance_to(hale.global_position) < 0.1, "HUMAN_MoveToAlarm läuft zum Alarmort")

	# --- Uniform vom Gefangenen: Original-Figur der Uniform wird übernommen (Figurtausch) ---
	var pr: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e.vehicle == null and e.mounted == null and e.has_meta("orig_model") and not crew_list.has(e):
			pr = e
			break
	if pr:
		var pb := pr.get_node("EnemyBrain") as EnemyBrain
		var fig0: Node3D = hale.model.orig_figure
		hale.global_position = pr.global_position + Vector3(1.0, 0.3, 0.0)
		pb.surrender(hale)
		for i in 3:
			if pb.capture_action.can_interact(hale):
				pb.capture_action.interact(hale)
		await frames(3)
		check(hale.disguised and hale.get_meta("uniform_figure", "") == String(pr.get_meta("orig_model")),
			"Uniform vom Gefangenen: Figur der Uniform übernommen", String(pr.get_meta("orig_model")))
		check(is_instance_valid(hale.model.orig_figure) and hale.model.orig_figure != fig0, "Original-Figur getauscht (sichtbar)")

	# --- Zerstörung über das Schadensmodell: Panzerfaust-Direkttreffer (Art 7, 2900 zotti) ---
	if dm:
		# Besatzung wieder einsteigen lassen (Fahrer + Richtschütze)
		var c0: Soldier = null
		for o in crew_list:
			if is_instance_valid(o) and (o as Soldier).alive:
				c0 = o
				break
		if c0:
			tank.board(c0, false, cannon_seat)
		var deaths := [0]
		tank.destroyed_vehicle.connect(func(): deaths[0] += 1)
		# Ziel: Zone D_ZONE00 (HP 800, matid16 → Rest 2900 − 1750 = 1150 > 800 → zerstört)
		var zi := -1
		for i in dm.zones.size():
			if String(dm.zones[i]["name"]) == "D_ZONE00":
				zi = i
		var zn: Node3D = dm.zones[zi]["node"] if zi >= 0 else null
		var aabb_c := zn.global_transform * ((zn as MeshInstance3D).get_aabb().get_center()) if zn is MeshInstance3D else tank.global_position
		var from := aabb_c + Vector3.UP * 4.0
		var picked := dm.pick_zone(7, aabb_c, from)
		print("TREFFER Zone %s (gewollt %s)" % [dm.zones[picked]["name"] if picked >= 0 else "-", "D_ZONE00"])
		var hp_z := int(dm.zones[picked]["hp"]) if picked >= 0 else 0
		var arm := VehicleDamage.armor_of(int(dm.zones[picked]["matid"])) if picked >= 0 else 0.0
		tank.projectile_hit(7, 290.0, aabb_c, (aabb_c - from).normalized(), hale)
		await frames(3)
		var expect_wreck := hp_z - (2900.0 - arm) < 0.0
		check(picked >= 0, "Strahltest trifft eine Schadenszone", String(dm.zones[picked]["name"]) if picked >= 0 else "-")
		if expect_wreck:
			check(tank.wrecked and deaths[0] == 1, "Zone durchschlagen (Art 7): Panzer sofort zerstört (0x4E1FE0)",
				"HP %d − Rest %.0f" % [hp_z, 2900.0 - arm])
		else:
			check(not tank.wrecked and int(dm.zones[picked]["hp"]) == int(floor(hp_z - (2900.0 - arm))),
				"Zone verliert HP um Schaden − Panzerung", "%d → %d" % [hp_z, int(dm.zones[picked]["hp"])])
			for i in 4:
				if not tank.wrecked:
					tank.projectile_hit(7, 290.0, aabb_c, (aabb_c - from).normalized(), hale)
			await frames(3)
			check(tank.wrecked and deaths[0] == 1, "Weitere Treffer: Zone < 0 → Panzer zerstört", "HP %d" % int(dm.zones[picked]["hp"]))
		check(c0 == null or not c0.alive, "Besatzung beim Zerstören getötet (Damage(5, −1))")
		await seconds(0.5)
		await shot("wrack")
	_finish()
