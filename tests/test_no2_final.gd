extends "res://tests/test_gameplay.gd"
## B-049: Operation Schwerttänzer (NORMANDY2) – Schlussskript und End-Zwischensequenz wie im Original.
##   tools\godot.cmd --headless -- --mission=no2_schwerttaenzer --autoplay=test_no2_final [--speed=2]
## Ablauf (Originalskripte, keine Abkürzung der Kette): Ziel 2 (Kontakt) und Ziel 1 (Scharfschützen) per Signal an
## „objectives“, Signal 5 (Verteidigung, Ally1–5 → R_N2_AllyN_End), dann alle Gegner ausschalten → r_n2_obj4 schickt
## Signal 1 an die Sherman-Besatzung → r_n2_amik_tank_driver fährt AmiiTank_1…7 → Dummy_CamerasEnd (Fake-Cutscene
## #CAMNO2_1/2: K1 3,5 s, K2 2,5 s, K1 3,5 s, K2 10 s, dann Spielkamera) → AmiTank_End → Dummy_End_Killer → OBJ 4 →
## Ziele 4, 7, 3 → Missionsende. Trupp und Verbündete unverwundbar.

var m: OrigMission
var rt: LsRuntime
var gt := 0.0                       ## Spielzeit (skaliert)
var cam_log: Array = []             ## [t, name]
var _cam_last := ""
var ev := {}                        ## Ereignis → Spielzeit
var obj_t := {}                     ## Zielindex → Spielzeit erfüllt
var tank: Vehicle
var wp_pos := {}
var wp_reached := {}
var hud_hidden_in_fake := true
var input_locked_in_fake := true
var _fake_seen := false


func _physics_process(d: float) -> void:
	if m == null or not is_instance_valid(m) or not is_instance_valid(rt):
		return
	gt += d
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS:
			s.health = s.max_health
	# Kamera-Zeitleiste
	var cur := get_viewport().get_camera_3d()
	var nm := "?"
	if m.rig and cur == m.rig.camera:
		nm = "spieler"
	elif cur == rt._cut_cam:
		nm = String(rt._cam_frame.name) if is_instance_valid(rt._cam_frame) else "cut"
	if nm != _cam_last:
		_cam_last = nm
		cam_log.append([gt, nm])
		print("KAMERA %.2f s: %s" % [gt, nm])
	if rt.fake_cutscene:
		if not _fake_seen:
			_fake_seen = true
			ev["fake_on"] = gt
		if m.hud and m.hud.visible:
			hud_hidden_in_fake = false
		if m.controller and m.controller.input_enabled:
			input_locked_in_fake = false
	elif _fake_seen and not ev.has("fake_off"):
		ev["fake_off"] = gt
		ev["input_after"] = m.controller.input_enabled if m.controller else false
		ev["hud_after"] = m.hud.visible if m.hud else true
	# Fahrt
	if is_instance_valid(tank):
		for wp in wp_pos:
			if not wp_reached.has(wp) and tank.global_position.distance_to(wp_pos[wp]) < 8.0:
				wp_reached[wp] = gt
				print("PANZER %.1f s bei %s" % [gt, wp])
	# Signale der Endskripte
	for vm in rt.vms:
		var key := ""
		if String(vm.name).to_lower() == "r_n2_camerasend.scr":
			key = "cameras_signal"
		elif String(vm.name).to_lower() == "r_n2_end_killer.scr":
			key = "killer_signal"
		if key != "" and not ev.has(key) and (vm.signals.has(1) or not vm.events.is_empty() or vm.wait > 0.0):
			ev[key] = gt
			var tp := tank.global_position if is_instance_valid(tank) else Vector3.INF
			ev[key + "_pos"] = tp
			print("SIGNAL %s bei %.1f s, Panzer bei %s" % [key, gt, tp])
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o and o.state == Objective.State.DONE and not obj_t.has(idx):
			obj_t[idx] = gt
			print("ZIEL %d erfüllt bei %.1f s" % [idx, gt])


func _signal(frame_name: String, n: int) -> void:
	var f := rt.find_frame(frame_name)
	var vm: LsVM = rt.vm_for(f) if f else null
	if vm:
		vm.signal_received(n)
	else:
		print("WARNUNG kein Skript an ", frame_name)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission() as OrigMission
	if m == null or m.runtime == null:
		check(false, "Mission no2_schwerttaenzer geladen")
		_finish()
		return
	rt = m.runtime
	rt.auto_skip = true
	if rt.in_cutscene:
		rt.end_cutscene()
	Events.mission_finished.connect(func(ok, why):
		ev["finished"] = gt
		ev["success"] = ok
		print("MISSIONSENDE %.1f s: %s (%s)" % [gt, ok, why]))
	for s in m.squad.members:
		s.max_health = 100000.0
		s.health = s.max_health
		s.process_mode = Node.PROCESS_MODE_DISABLED     # bleibt am Start (kein „Einsatzgebiet verlassen“)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if String(v.name).to_lower() == "la_sherman":
			tank = v
	for wp in ["AmiiTank_6", "AmiiTank_7", "AmiTank_End"]:
		var gi: int = rt._drive_name(wp)
		if gi >= 0:
			wp_pos[wp] = rt._drive_astar.get_point_position(gi)
	check(tank != null and wp_pos.size() == 3, "Sherman und Fahrziele AmiiTank_6/7, AmiTank_End vorhanden")
	Engine.time_scale = float(Game.cli.get("speed", "2"))
	await get_tree().create_timer(2.0, false).timeout
	_signal("objectives", 2)
	for e in m.enemies:
		if is_instance_valid(e) and e.alive:
			e.die(null)
	await get_tree().create_timer(2.0, false).timeout
	if not obj_t.has(1):
		_signal("objectives", 1)
	_signal("objectives", 5)
	# r_n2_obj4: > 8 tote Blue → Signal 1 an die Panzerbesatzung; Rückfall nur falls die Zählung nicht auslöst
	await get_tree().create_timer(6.0, false).timeout
	var drv := rt.find_frame("Amik_tank_driver") as Soldier
	if drv and drv.vehicle == null:
		print("HINWEIS r_n2_obj4 hat die Besatzung nicht geschickt – Signal 1 direkt")
		for n in ["Amik_tank_driver", "Amik_tank_MG", "Amik_tank_LG", "Amik_tank_4"]:
			_signal(n, 1)
	var limit := gt + 400.0
	while gt < limit and not ev.has("finished"):
		await get_tree().create_timer(1.0, false).timeout
	Engine.time_scale = 1.0
	_evaluate()
	_finish()


func _evaluate() -> void:
	print("EREIGNISSE ", ev)
	print("ZIELE ", obj_t)
	print("KAMERAS ", cam_log)
	check(ev.has("cameras_signal"), "Dummy_CamerasEnd erhält Signal 1")
	if ev.has("cameras_signal_pos") and wp_pos.has("AmiiTank_7"):
		var dd: float = (ev["cameras_signal_pos"] as Vector3).distance_to(wp_pos["AmiiTank_7"])
		check(dd < 10.0, "Signal an CamerasEnd erst bei AmiiTank_7", "Abstand %.1f m" % dd)
	if ev.has("killer_signal_pos") and wp_pos.has("AmiTank_End"):
		var dk: float = (ev["killer_signal_pos"] as Vector3).distance_to(wp_pos["AmiTank_End"])
		check(dk < 10.0, "Signal an End_Killer erst bei AmiTank_End", "Abstand %.1f m" % dk)
	# Kamerafolge K1 3,5 / K2 2,5 / K1 3,5 / K2 10 s, dann Spielkamera
	var seq: Array = []
	for i in cam_log.size():
		var nm: String = cam_log[i][1]
		if nm.to_lower().begins_with("kamera"):
			var t_end: float = cam_log[i + 1][0] if i + 1 < cam_log.size() else gt
			seq.append([nm.to_lower(), t_end - float(cam_log[i][0]), cam_log[i + 1][1] if i + 1 < cam_log.size() else ""])
	print("KAMERAFOLGE ", seq)
	var want := [["kamera1", 3.5], ["kamera2", 2.5], ["kamera1", 3.5], ["kamera2", 10.0]]
	var ok := seq.size() == 4
	if ok:
		for i in 4:
			if seq[i][0] != want[i][0] or absf(float(seq[i][1]) - float(want[i][1])) > 0.6:
				ok = false
	check(ok, "Endsequenz: Kamera1/Kamera2 im Original-Takt 3,5/2,5/3,5/10 s", str(seq))
	check(seq.size() > 0 and String(seq[-1][2]) == "spieler", "danach wieder Spielkamera")
	if ev.has("cameras_signal") and ev.has("fake_on"):
		var dl: float = float(ev["fake_on"]) - float(ev["cameras_signal"])
		check(absf(dl - 3.3) < 0.6, "Fake-Cutscene beginnt 3,3 s nach dem Signal (Delay 3000 + 300)", "%.2f s" % dl)
	check(_fake_seen and hud_hidden_in_fake and input_locked_in_fake, "während der Endsequenz HUD aus, Eingabe gesperrt")
	# (nach Missionsende sperrt finish() die Steuerung selbst – daher Zustand beim Ende der Fake-Cutscene)
	check(ev.has("fake_off") and bool(ev.get("input_after", false)) and bool(ev.get("hud_after", false)),
		"Fake-Cutscene beendet, Steuerung und HUD zurück")
	check(obj_t.has(4) and ev.has("killer_signal") and float(obj_t[4]) >= float(ev["killer_signal"]),
		"Ziel 4 erst nach End_Killer erfüllt")
	check(obj_t.has(3) and obj_t.has(4) and float(obj_t[3]) - float(obj_t[4]) > 9.0,
		"Ziel 3 ≈ 10 s nach Ziel 4 (OnSignal(4)-Ablauf)", str(obj_t))
	check(bool(ev.get("success", false)), "Mission erfolgreich beendet")
	if ev.has("finished"):
		check(not ev.has("fake_off") or float(ev["finished"]) >= float(ev["fake_off"]), "Missionsende nicht vor Ende der Endsequenz")
		check(obj_t.has(3) and float(ev["finished"]) >= float(obj_t[3]) + 2.5, "Missionsende ≈ 3 s nach Ziel 3 (3-s-Regel, Taktabweichung Timer/Physik)")
		check(wp_reached.has("AmiiTank_7"), "Sherman hat AmiiTank_7 vor dem Ende erreicht", str(wp_reached))
