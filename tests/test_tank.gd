extends "res://tests/test_gameplay.gd"
## Panzer und Waffenstellungen nach Original (docs/re_notes_ai.md §3): AFRICA1 Panzer III „panzer01“ mit Besatzung
## (Originalskripte af1_tank01_01..03: HUMAN_BoardVehicle(panzer01, 1, Sitz)), Turm/Kanone/MG aus Modell und Munition,
## Panzerung, KI an MG-Stellung (HUMAN_BoardVehicle(Stellung, 1, 0)), Alarmarten.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_tank


var _shells: Array = []


func _on_node_added(n: Node) -> void:
	if n is Grenade:
		_shells.append(n)
		n.tree_exiting.connect(_on_shell_gone.bind(n))
		(n as RigidBody3D).body_entered.connect(_on_shell_hit)


func _on_shell_hit(b: Node) -> void:
	print("GESCHOSS TRIFFT %s (%s) Pfad %s" % [b.name, b.get_class(), b.get_path()])


func _on_shell_gone(n: Node3D) -> void:
	print("GESCHOSS ENDE bei %s (Geschw. %s)" % [n.global_position, (n as RigidBody3D).linear_velocity])


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
	check(tank.armored and is_equal_approx(tank.max_health, 3000.0), "Gepanzert (Kanone an Bord), 3000 Strukturpunkte")
	check(tank.seats.size() >= 3, "Sitze aus dem Originalmodell (SEAT00…)", str(tank.seats.size()))
	var cannon_seat := -1
	var mg_seat := -1
	for i in tank.turrets:
		var w: Weapon = tank.turrets[i].get("weapon")
		if w and w.data.action == WeaponData.Action.ROCKET:
			cannon_seat = i
		elif w:
			mg_seat = i
	check(cannon_seat >= 0, "Kanone an einem Turmsitz (HORT/VERT, Munition AMMO Panzer)",
		tank.turrets[cannon_seat]["weapon"].data.display_name if cannon_seat >= 0 else "-")
	check(mg_seat >= 0, "Maschinengewehr an einem Waffensitz (Tank MG 34)",
		tank.turrets[mg_seat]["weapon"].data.display_name if mg_seat >= 0 else "-")
	# Besatzung laut Originalskript
	var crew := 0
	for o in tank.occupants:
		if is_instance_valid(o) and (o as Soldier).team == Soldier.TEAM_AXIS:
			crew += 1
	check(crew >= 2, "Besatzung eingestiegen (HUMAN_BoardVehicle mit Sitznummer)", "%d Mann" % crew)
	var gunner = tank.occupants[cannon_seat] if cannon_seat >= 0 else null
	check(is_instance_valid(gunner) and not (gunner as Soldier).model.visible, "Besatzung im Panzer unsichtbar")
	# Panzerung: Kugeln wirkungslos, Explosionen wirken
	var hp0: float = tank.health
	tank.on_bullet_hit(80.0, null)
	check(is_equal_approx(tank.health, hp0), "Handwaffen gegen Panzer wirkungslos")
	tank.on_explosion(100.0, null)
	check(tank.health < hp0, "Explosion beschädigt den Panzer", "%.0f -> %.0f" % [hp0, tank.health])
	tank.health = tank.max_health

	# Spieler übernimmt die Kanone: Besatzung raus, Spieler an den Turmsitz
	for o in tank.occupants.duplicate():
		if is_instance_valid(o):
			tank.leave(o)
			(o as Soldier).die(null)
	var hale: Soldier = m.squad.leader()
	var own_weapons := hale.weapons.duplicate()
	hale.global_position = tank.global_position + tank.global_basis.x * 3.0
	check(tank.board(hale, false, cannon_seat), "Spieler besetzt den Kanonensitz")
	check(hale.current_weapon() and hale.current_weapon().data.action == WeaponData.Action.ROCKET, "Kanone in der Hand des Schützen")
	var d0 := tank.turret_dir(cannon_seat)
	var yaw0 := atan2(-d0.x, -d0.z)
	# Blick wie per Maus Richtung Ziel drehen (der Turm folgt mit begrenzter Geschwindigkeit)
	for i in 60:
		hale.look_yaw = rotate_toward(hale.look_yaw, yaw0 + 1.2, 0.2)
		await frames(1)
	var d1 := tank.turret_dir(cannon_seat)
	var turned := absf(angle_difference(yaw0, atan2(-d1.x, -d1.z)))
	check(turned > 0.2 and turned < 0.8, "Turm dreht mit begrenzter Geschwindigkeit (25°/s)", "%.0f° in 1 s" % rad_to_deg(turned))
	for i in 240:
		hale.look_yaw = rotate_toward(hale.look_yaw, yaw0 + 1.2, 0.2)
		await frames(1)
	var d2 := tank.turret_dir(cannon_seat)
	check(absf(angle_difference(atan2(-d2.x, -d2.z), yaw0 + 1.2)) < 0.1, "Turm erreicht die Blickrichtung",
		"%.0f°" % rad_to_deg(angle_difference(atan2(-d2.x, -d2.z), yaw0 + 1.2)))
	# Schuss mit der Kanone: Ziel 25 m vor dem Rohr
	var target: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e != gunner:
			target = e
			break
	var mp := tank.muzzle_point(cannon_seat)
	var dir := tank.turret_dir(cannon_seat)
	dir.y = 0.0
	target.get_node("EnemyBrain").enabled = false
	# freie Schussbahn: Ziel vor das erste Hindernis in Rohrrichtung stellen
	var q := PhysicsRayQueryParameters3D.create(mp, mp + dir.normalized() * 20.0, 1 | 2, [tank.get_rid()])
	var hit := tank.get_world_3d().direct_space_state.intersect_ray(q)
	# 6 m: vor dem abgestellten Motorrad la_BmwR_ (AFRICA1), das die Granate sonst zuerst trifft
	var tdist := 6.0 if hit.is_empty() else clampf(mp.distance_to(hit.position) - 1.5, 4.0, 6.0)
	target.global_position = mp + dir.normalized() * tdist + Vector3.DOWN * 1.0
	target.set_physics_process(true)
	var hp_t := target.health
	await seconds(0.5)
	for i in 90:
		var tp := target.global_position + Vector3.UP * 0.9 - tank.muzzle_point(cannon_seat)
		hale.look_yaw = rotate_toward(hale.look_yaw, atan2(-tp.x, -tp.z), 0.2)
		hale.look_pitch = move_toward(hale.look_pitch, atan2(tp.y, Vector2(tp.x, tp.z).length()), 0.05)
		await frames(1)
	var ammo0: int = hale.current_weapon().total_ammo()
	var shells := _shells
	get_tree().node_added.connect(_on_node_added)
	print("KANONE Mündung %s Rohr %s Blick %s Ziel %s Augen %s" % [tank.muzzle_point(cannon_seat), tank.turret_dir(cannon_seat),
		hale.aim_direction(), target.global_position, hale.eye_position()])
	Input.action_press("fire")
	await frames(4)
	Input.action_release("fire")
	for i in 40:
		await frames(1)
		for sh in shells:
			if is_instance_valid(sh):
				print("GESCHOSS t=%d pos %s v %s" % [i, sh.global_position, sh.linear_velocity])
	print("PANZER nach Schuss %.0f" % tank.health)
	await seconds(1.0)
	check(hale.current_weapon().total_ammo() == ammo0 - 1, "Kanone feuert (Munition −1)")
	check(not target.alive or target.health < hp_t, "Granate trifft das Ziel vor dem Rohr", "%.0f -> %.0f" % [hp_t, target.health])
	check(tank.health > tank.max_health * 0.9, "Eigene Granate beschädigt den Panzer nicht")
	tank.leave(hale)
	var restored := hale.weapons.size() == own_weapons.size()
	for i in own_weapons.size():
		restored = restored and hale.weapons[i] == own_weapons[i]
	check(restored and hale.model.visible, "Aussteigen: eigene Waffen zurück, sichtbar")

	# KI besetzt MG-Stellung per Originalbefehl
	var empl = m.interactive.controls.get("W_MG42CROUCH_01")
	check(empl != null, "MG-Stellung w_mg42Crouch_01 (Typ 21)")
	var gun: Soldier = null
	# Das Originalskript af1_12 besetzt die Stellung ggf. schon selbst: dann diesen Schützen freigeben
	if empl and is_instance_valid(empl.gunner):
		var g0: Soldier = empl.gunner
		empl.dismount()
		g0.global_position += Vector3(30, 0, 0)
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e != target and e.vehicle == null and e.mounted == null:
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
		# Ziel vor der Stellung: KI feuert
		hale.global_position = empl.gunner_spot() - empl.frame.global_basis.z.normalized() * 18.0 + Vector3.UP * 0.5
		var per: Perception = gun.get_node("Perception")
		per.sight_range = 80.0
		per.awareness[hale] = 1.0
		per.last_known[hale] = hale.global_position
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
		rt.call_api(vm, "HUMAN_BOARDVEHICLE", [["str", ""], ["num", 1], ["num", 0]])
		check(gun.mounted == null and empl.gunner == null and (gun.current_weapon() == null or gun.current_weapon().data != empl.data),
			"Verlassen der Stellung (leerer Name)", "mounted %s" % gun.mounted)

	# Alarmarten: SetAlarmType-Maske und _GetAlarmType
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

	# Uniform vom Gefangenen: Original-Figur der Uniform wird übernommen (Figurtausch)
	var pr: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e.vehicle == null and e.mounted == null and e.has_meta("orig_model"):
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
	_finish()
