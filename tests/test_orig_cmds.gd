extends "res://tests/test_gameplay.gd"
## AP-5 (B-033): Whenever-Takt (SetWheneverTime, hd2.exe 0x4167B0), CheckpointJoin/Separate (Wegpunktkanten) inkl.
## Spielstand, SetupTacticalMode (Taktikkarte gesperrt), HINT_ClearAll/FRM_SetTarget ohne Fehler.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_orig_cmds

const SRC_TIMED := """
Integer x;
Integer y;
Whenever W ( x == 1 ) { y = y + 1; }
SetWheneverTime(W, 1000);
Label L:
Delay(100000);
goto L;
"""

const SRC_PLAIN := """
Integer x;
Integer y;
Whenever P ( x == 1 ) { y = y + 1; }
Label L:
Delay(100000);
goto L;
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


## Tickt die VM in 100-ms-Schritten, bis y ≥ ziel (oder Höchstzeit); liefert die vergangene Zeit in s (−1 = nie)
func _until(vm: LsVM, ziel: int, max_s: float) -> float:
	var t := 0.0
	while t < max_s:
		vm.tick(0.1)
		t += 0.1
		if int(vm.vars.get("Y", vm.vars.get("y", 0))) >= ziel:
			return t
	return -1.0


func _y(vm: LsVM) -> int:
	return int(vm.vars.get("Y", vm.vars.get("y", 0)))


func _set_x(vm: LsVM, v: int) -> void:
	vm.vars["X" if vm.vars.has("X") else "x"] = v


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime"):
			break
		await get_tree().process_frame
	await frames(5)
	var m := mission()
	var rt = m.get("runtime") if m else null
	check(rt != null, "Mission a1 mit Skriptlaufzeit geladen")
	if rt == null:
		_finish()
		return
	_whenever_tests(rt)
	_checkpoint_tests(rt)
	_misc_tests(rt, m)
	_b033_tests(rt, m)
	_finish()


## B-033-Rest (docs/status/b026_b033.md): Grundkanten check2.bin, Führerweg über Skriptkanten, IgnoreCircumvention,
## FRM_SoundAdjustDoppler, __SetupAutoLogging
func _b033_tests(rt, m) -> void:
	var cp: LsCheckpoints = rt.get("checkpoints")
	rt._drive_load()
	check(cp.base_pos.size() > 1000 and cp.node_of("swamp_1") >= 0 and cp.node_of("Rebel_Joinn1") >= 0,
		"Grundkanten (check2.bin Abschnitt 1) geladen, Namen auflösbar", "%d Knoten" % cp.base_pos.size())
	var a := cp.node_of("swamp_1")
	var b := cp.node_of("Rebel_Joinn1")
	cp.clear()
	var r0: Dictionary = cp.route_nodes(a, b)
	check(r0.is_empty() or not bool(r0["script_edge"]), "Ohne Skriptkante: Weg nur über Grundkanten",
		"%d Knoten" % (r0.get("nodes", []) as Array).size())
	var vm := LsVM.new(LsCompiler.new(), null, rt)
	rt.call_api(vm, "CHECKPOINTJOIN", [["str", "swamp_1"], ["str", "Rebel_Joinn1"]])
	var r1: Dictionary = cp.route_nodes(a, b)
	check(not r1.is_empty() and bool(r1["script_edge"]) and (r1["nodes"] as Array).size() == 2,
		"Skriptkante verkürzt den Weg im Gesamtnetz", str(r1))
	var wa: Node3D = rt.waypoints.get("SWAMP_1")
	var wb: Node3D = rt.waypoints.get("REBEL_JOINN1")
	if wa and wb:
		var route: Array = rt.checkpoint_route(wa.global_position, wb)
		check(route.size() >= 1 and (route[route.size() - 1] as Vector3).is_equal_approx(wb.global_position),
			"checkpoint_route endet am Ziel-Wegpunkt", str(route.size()))
	# Weg ohne Skriptkante bleibt direkt (Navmesh)
	cp.clear()
	cp.join("swamp_3", "swamp_4")
	if wa and wb:
		check(rt.checkpoint_route(wa.global_position, wb).size() == 1, "Ohne genutzte Skriptkante direkter Weg (Navmesh)")
	cp.clear()
	# EnemyBrain.script_route: Zwischenpunkte nacheinander
	var es: Soldier = null
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_AXIS):
		if n is Soldier and n.alive and n.get_node_or_null("EnemyBrain"):
			es = n
			break
	check(es != null, "Gegner mit EnemyBrain für B-033-Prüfungen")
	if es:
		var eb: EnemyBrain = es.get_node("EnemyBrain")
		var p0 := es.global_position
		eb.script_route([p0 + Vector3(0.3, 0, 0), p0 + Vector3(0.5, 0, 0)])
		check(eb._script_route.size() == 1, "script_route merkt die restlichen Punkte")
		var done := false
		for i in 3:
			done = eb.script_move_done()
		check(eb._script_route.is_empty(), "Erreichter Zwischenpunkt → nächster Punkt", "done=%s" % done)
		eb.stop_moving()
		var vme := LsVM.new(LsCompiler.new(), es, rt)
		rt.call_api(vme, "HUMAN_SETIGNORECIRCUMVENTIONFLAG", [["num", 1]])
		check(eb.ignore_circumvention, "HUMAN_SetIgnoreCircumventionFlag(true) setzt das Gehirn-Flag")
		var st: Dictionary = rt.save_state()
		check((st.get("ignore_circumvention", []) as Array).size() >= 1, "Flag im Spielstand der Laufzeit")
		rt.call_api(vme, "HUMAN_SETIGNORECIRCUMVENTIONFLAG", [["num", 0]])
		check(not eb.ignore_circumvention, "…(false) löscht es")
		rt.load_state(st)
		check(eb.ignore_circumvention, "Flag nach load_state wiederhergestellt")
		eb.ignore_circumvention = false
	var dc: int = rt.doppler_calls
	rt.call_api(vm, "FRM_SOUNDADJUSTDOPPLER", [["str", "gibtsnicht"], ["num", 1], ["num", 100], ["num", 1]])
	rt.call_api(vm, "__SETUPAUTOLOGGING", [])
	check(rt.doppler_calls == dc + 1 and rt.noop_calls.has("__SETUPAUTOLOGGING"), "Doppler umgesetzt, AutoLogging belegt wirkungslos")
	check(not rt.stubbed.has("HUMAN_SETIGNORECIRCUMVENTIONFLAG") and not rt.stubbed.has("FRM_SOUNDADJUSTDOPPLER")
		and not rt.stubbed.has("__SETUPAUTOLOGGING"), "Keine stummen B-033-Befehle mehr", str(rt.stubbed.keys()))


func _whenever_tests(rt) -> void:
	var c := LsCompiler.compile(SRC_TIMED, "ap5_timed")
	check(c.ok(), "Testskript (Whenever mit SetWheneverTime) kompiliert", str(c.errors))
	var vm := LsVM.new(c, null, rt)
	vm.tick(0.0)   # Skriptanfang: Deklarationen, SetWheneverTime, Delay(100 s)
	var wn: String = c.whenevers.keys()[0]
	check(int(vm.whenever_interval_ms.get(wn, -1)) == 1000, "SetWheneverTime trägt die Periode 1000 ms ein",
		str(vm.whenever_interval_ms))
	check(vm.wait > 50.0, "Hauptablauf wartet im Delay")
	_set_x(vm, 1)
	var t := _until(vm, 1, 5.0)
	# Raster 500 ms (Akku > 500), elapsed 500/1000/1500 → erst bei > 1000 geprüft ⇒ 1,6 s
	check(t >= 1.0 and t <= 2.1, "Whenever mit Periode 1000 feuert frühestens nach 1000 ms", "%.1f s" % t)
	# Delay (Rest ≈ 98,4 s) abgebrochen; der Ablauf läuft hinter dem Whenever-Block weiter und startet ein NEUES Delay(100 s)
	check(vm.wait > 99.5, "Auslösen bricht das laufende Delay ab (Ablauf danach neu)", "wait=%.1f" % vm.wait)
	check(not bool(vm.whenever_active.get(wn, true)), "Whenever hat sich beim Auslösen selbst deaktiviert")
	_until(vm, 99, 5.0)
	check(_y(vm) == 1, "Ohne SetWhenever kein zweites Auslösen (5 s, Bedingung wahr)", "y=%d" % _y(vm))
	vm._call("SETWHENEVER", [["var", wn], ["num", 1]])
	var t2 := _until(vm, 2, 5.0)
	check(t2 > 0.0 and t2 <= 2.1, "SetWhenever(…, 1) aktiviert erneut → feuert wieder", "%.1f s" % t2)

	# Spielstand: Periode/verstrichene Zeit/Akku überstehen save/load; Takt läuft danach gleich weiter
	vm._call("SETWHENEVER", [["var", wn], ["num", 1]])
	_set_x(vm, 0)
	for i in 7:
		vm.tick(0.1)   # Akku/elapsed in einen Zwischenstand bringen
	var enc := func(v): return v
	var st: Dictionary = JSON.parse_string(JSON.stringify(vm.save_state(enc)))
	var vm2 := LsVM.new(c, null, rt)
	vm2.load_state(st, enc)
	check(int(vm2.whenever_interval_ms.get(wn, -1)) == 1000 and vm2.whenever_tick_ms == vm.whenever_tick_ms
		and is_equal_approx(float(vm2.whenever_elapsed_ms.get(wn, 0.0)), float(vm.whenever_elapsed_ms.get(wn, 0.0))),
		"Whenever-Takt im Spielstand (Periode, Akku, verstrichene Zeit)",
		"tick %d/%d elapsed %s/%s" % [vm.whenever_tick_ms, vm2.whenever_tick_ms, vm.whenever_elapsed_ms, vm2.whenever_elapsed_ms])
	_set_x(vm, 1)
	_set_x(vm2, 1)
	var y0 := _y(vm)
	var y02 := _y(vm2)
	var ta := _until(vm, y0 + 1, 5.0)
	var tb := _until(vm2, y02 + 1, 5.0)
	check(ta > 0.0 and absf(ta - tb) < 0.05, "Nach dem Laden feuert die Whenever im gleichen Takt", "%.1f / %.1f s" % [ta, tb])

	# Bisheriges Verhalten ohne SetWheneverTime: Prüfung jeden Tick [E]
	var c2 := LsCompiler.compile(SRC_PLAIN, "ap5_plain")
	var vp := LsVM.new(c2, null, rt)
	vp.tick(0.0)
	_set_x(vp, 1)
	vp.tick(0.016)
	check(_y(vp) == 1, "Whenever ohne SetWheneverTime prüft weiter jeden Tick (Standardperiode [E])")

	# DisableWhenevers sperrt auch die getaktete Prüfung
	var vd := LsVM.new(c, null, rt)
	vd.tick(0.0)
	vd.whenevers_disabled = true
	_set_x(vd, 1)
	check(_until(vd, 1, 3.0) < 0.0, "DisableWhenevers sperrt die getaktete Prüfung")


func _checkpoint_tests(rt) -> void:
	var cp = rt.get("checkpoints")
	check(cp is LsCheckpoints, "LsRuntime.checkpoints angelegt")
	if not (cp is LsCheckpoints):
		return
	cp.clear()
	var vm := LsVM.new(LsCompiler.new(), null, rt)
	rt.call_api(vm, "CHECKPOINTJOIN", [["str", "swamp_1"], ["str", "swamp_2"]])
	rt.call_api(vm, "CHECKPOINTJOIN", [["str", "swamp_3"], ["str", "swamp_4"]])
	rt.call_api(vm, "CHECKPOINTJOIN", [["str", "swamp_2"], ["str", "swamp_3"]])
	check(cp.has_edge("SWAMP_2", "swamp_1") and cp.edges.size() == 3, "CheckpointJoin legt ungerichtete Kanten an", str(cp.edges))
	rt.call_api(vm, "CHECKPOINTJOIN", [["str", "swamp_1"], ["str", "gibt_es_nicht"]])
	check(cp.edges.size() == 3, "Join mit unbekanntem Checkpoint wird verworfen")
	check(cp.path("swamp_1", "swamp_4") == ["SWAMP_1", "SWAMP_2", "SWAMP_3", "SWAMP_4"], "Kantenfolge swamp_1 → swamp_4",
		str(cp.path("swamp_1", "swamp_4")))
	var st: Dictionary = JSON.parse_string(JSON.stringify(rt.save_state()))
	check(st.has("checkpoints") and (st["checkpoints"]["edges"] as Array).size() == 3, "Checkpoint-Kanten im Spielstand der Laufzeit")
	rt.call_api(vm, "CHECKPOINTSEPARATE", [["str", "swamp_3"], ["str", "swamp_2"]])
	check(not cp.has_edge("swamp_2", "swamp_3") and cp.path("swamp_1", "swamp_4").is_empty(),
		"CheckpointSeparate entfernt die Kante (beliebige Richtung)")
	var back := LsCheckpoints.new()
	back.load_state(st["checkpoints"])
	check(back.edges.size() == 3 and back.has_edge("swamp_3", "swamp_2"), "Kanten nach dem Laden wiederhergestellt")
	cp.load_state(st["checkpoints"])
	check(cp.path("swamp_1", "swamp_4").size() == 4, "Laufzeit-Kanten per load_state zurückgesetzt")
	cp.clear()


func _misc_tests(rt, m) -> void:
	var vm := LsVM.new(LsCompiler.new(), null, rt)
	var tm = m.get("tactical_map")
	rt.call_api(vm, "SETUPTACTICALMODE", [["num", 0]])
	check(tm != null and bool(tm.locked), "SetupTacticalMode(False) sperrt die Taktikkarte")
	if tm:
		tm.open()
		check(not bool(tm.is_open), "Gesperrte Taktikkarte öffnet nicht")
	rt.call_api(vm, "SETUPTACTICALMODE", [["num", 1]])
	check(tm != null and not bool(tm.locked), "SetupTacticalMode(True) gibt sie frei")
	rt.call_api(vm, "HINT_CLEARALL", [])
	rt.call_api(vm, "FRM_SETTARGET", [["str", "x"], ["str", "y"], ["num", 1]])
	check(not rt.unimplemented.has("HINT_CLEARALL") and not rt.unimplemented.has("FRM_SETTARGET")
		and not rt.unimplemented.has("CHECKPOINTJOIN"), "HINT_ClearAll/FRM_SetTarget/Checkpoint* bekannt")
