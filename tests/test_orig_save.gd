extends "res://tests/test_gameplay.gd"
## B-030 / AP-1: Skriptzustand der Originalmissionen im Spielstand (LS-VM, Variablen, Signale, Whenever, SaveGameValues,
## Zwischensequenz, Akteure). Speichern und Laden an mehreren Stellen, danach Ziele/Skripte/Akteure konsistent.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_orig_save
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_orig_save --phase=a2
## a1 hinterlässt den Spielstand „orig_save_a1_final“ (nach Alarm) für den Löser:
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_orig_complete --from_save=orig_save_a1_final

const SLOTS := ["orig_save_cut", "orig_save_guide0", "orig_save_guide1", "orig_save_alarm", "orig_save_old", "orig_save_a2"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2400.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait_mission(old: Node) -> OrigMission:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm != old and mm.squad and mm.squad.leader():
			break
		await get_tree().process_frame
	await frames(5)
	return mission() as OrigMission


## Speichern und sofort laden; liefert die neue Mission
func _save_load(slot: String) -> OrigMission:
	var old := mission()
	Game.saves_used = 0
	var ok := Game.save_game(slot)
	check(ok and Game.has_save(slot), "Spielstand '%s' gespeichert" % slot)
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path(slot)))
	var ov = data["state"]["extra"].get("orig_vm") if data is Dictionary else null
	check(ov is Dictionary and int(ov.get("version", 0)) == LsRuntime.SAVE_VERSION and (ov["vms"] as Array).size() >= 50,
		"Spielstand enthält Skriptzustand (orig_vm v%d)" % LsRuntime.SAVE_VERSION, "%d VMs" % ((ov["vms"] as Array).size() if ov is Dictionary else 0))
	Game.load_game(slot)
	return await _wait_mission(old)


## Kennzeichen je VM (Objekt + Skript) → Ablaufstelle/Endezustand/Signale/Whenever
func _snapshot(rt: LsRuntime) -> Dictionary:
	var out := {}
	for v in rt.save_state()["vms"]:
		var st: Dictionary = v["state"]
		var key := JSON.stringify(v["owner"]) + "|" + String(st["script"])
		out[key] = {"pos": int(st["block_pc"]) if st["blocking"] else int(st["pc"]), "term": st["terminated"],
			"ended": st["ended"], "sig": str(st["signals"]), "wa": JSON.stringify(st["whenever_active"]),
			"wi": JSON.stringify(st["whenever_interval_ms"])}
	return out


func _compare(a: Dictionary, b: Dictionary, label: String) -> void:
	var same := 0
	var diffs: Array = []
	for k in a:
		if b.has(k) and JSON.stringify(a[k]) == JSON.stringify(b[k]):
			same += 1
		elif diffs.size() < 6:
			diffs.append("%s: %s -> %s" % [k, a[k], b.get(k, "-")])
	var missing := a.keys().filter(func(k): return not b.has(k)).size()
	var term_a := a.values().filter(func(x): return x["term"]).size()
	var term_b := b.values().filter(func(x): return x["term"]).size()
	check(missing == 0 and a.size() == b.size(), label + ": dieselben Skripte (Objekt + Datei)", "%d/%d, fehlend %d" % [a.size(), b.size(), missing])
	check(same >= int(a.size() * 0.9), label + ": Ablaufstellen/Signale/Whenever übernommen (≥ 90 %)",
		"%d von %d gleich; %s" % [same, a.size(), str(diffs)])
	check(term_a == term_b, label + ": beendete Skripte gleich", "%d/%d" % [term_a, term_b])


func _objectives(m: Mission) -> String:
	var s := ""
	for o in m.objectives:
		s += "%s:%d " % [o.id, o.state]
	return s


func _gv(rt: LsRuntime) -> String:
	var keys := rt.game_values.keys()
	keys.sort()
	var s := ""
	for k in keys:
		s += "%s=%s " % [k, rt.game_values[k]]
	return s


func _alive(m: Mission) -> Array:
	var out := []
	for e in m.enemies:
		if e.alive:
			out.append(e.persistent_id)
	out.sort()
	return out


func _run() -> void:
	var m := await _wait_mission(null)
	check(m != null and m.runtime != null, "Originalmission geladen", Game.current_mission_id)
	if m == null or m.runtime == null:
		_finish()
		return
	if String(Game.cli.get("phase", "a1")) == "a2":
		await _phase_a2(m)
	else:
		await _phase_a1(m)
	for s in SLOTS:
		Game.delete_save(s)
	_finish()


func _phase_a1(m: OrigMission) -> void:
	var rt := m.runtime
	# --- 1. während der Intro-Zwischensequenz ---
	await seconds(2.0)
	check(rt.in_cutscene and rt.cutscene_id == 1, "Intro-Zwischensequenz läuft (Speichern währenddessen)")
	rt.game_values[223] = 4           # SaveGameValue-Kette a1→a3 (Bereich 101–223): Rundweg mit Ganzzahl
	var vms0 := rt.vms.size()
	m = await _save_load("orig_save_cut")
	rt = m.runtime
	await seconds(1.0)
	check(not rt.in_cutscene and m.controller.input_enabled, "Nach dem Laden: Zwischensequenz übersprungen, Steuerung frei")
	check(rt.vms.size() == vms0, "Gleiche Zahl Skripte nach dem Laden", "%d/%d" % [rt.vms.size(), vms0])
	check(rt.game_values.get(223) is int and int(rt.game_values.get(223)) == 4, "SaveGameValue 223 = 4 (Ganzzahl) erhalten", _gv(rt))
	await seconds(4.0)
	check(not rt.in_cutscene, "Intro startet nach dem Laden nicht erneut")
	var active := m.objectives.filter(func(o): return o.state != Objective.State.INACTIVE).size()
	check(active >= 1, "Ziele nach Intro-Ladestand aktiv", _objectives(m))

	# --- 2. vor dem Führer ---
	isolate_enemies([])
	await seconds(1.0)
	var snap := _snapshot(rt)
	var obj := _objectives(m)
	var gv := _gv(rt)
	var rebel := rt.actors.get("REBEL") as Soldier
	var rpos := rebel.global_position
	m = await _save_load("orig_save_guide0")
	rt = m.runtime
	_compare(snap, _snapshot(rt), "Vor dem Führer")
	check(_objectives(m) == obj, "Vor dem Führer: Ziele gleich", _objectives(m))
	check(_gv(rt) == gv, "Vor dem Führer: SaveGameValues gleich", _gv(rt))
	rebel = rt.actors.get("REBEL") as Soldier
	check(rebel.global_position.distance_to(rpos) < 1.5, "Sygurd am gespeicherten Ort", "%.2f m" % rebel.global_position.distance_to(rpos))

	# --- 3. Führer läuft (blockierender HUMAN_Move im Skript) ---
	var said: Array[String] = []
	Events.message.connect(func(t, _s): said.append(t))
	isolate_enemies([])
	var hale := m.squad.leader()
	rpos = rebel.global_position
	hale.global_position = rpos + Vector3(0, 1.0, 25)
	await seconds(6.0)
	hale.global_position = rebel.global_position + Vector3(0, 1.0, 3.5)
	await seconds(12.0)
	var greet := rt.text(1990214)
	check(said.has(greet), "Sygurd begrüßt den Trupp", greet)
	for i in 30:
		if rebel.global_position.distance_to(rpos) > 3.0:
			break
		await seconds(0.5)
	check(rebel.global_position.distance_to(rpos) > 3.0, "Sygurd führt los", "%.1f m" % rebel.global_position.distance_to(rpos))
	var rvm := rt.vm_for(rebel)
	var rstate := rvm.save_state(rt.save_value) if rvm else {}
	snap = _snapshot(rt)
	obj = _objectives(m)
	var guide_pos := rebel.global_position
	m = await _save_load("orig_save_guide1")
	rt = m.runtime
	_compare(snap, _snapshot(rt), "Während der Führung")
	check(_objectives(m) == obj, "Während der Führung: Ziele gleich", _objectives(m))
	rebel = rt.actors.get("REBEL") as Soldier
	rvm = rt.vm_for(rebel)
	check(rvm != null and rvm.name == String(rstate.get("script", "")) and not rvm.terminated,
		"Sygurds Skript fortgesetzt (nicht neu gestartet)", "%s pc %s/%s" % [rvm.name if rvm else "-", rstate.get("pc"), rvm.pc if rvm else -1])
	check(rebel.global_position.distance_to(guide_pos) < 1.5, "Sygurd an der Führungsstelle", "%.2f m" % rebel.global_position.distance_to(guide_pos))
	said.clear()
	isolate_enemies([])
	hale = m.squad.leader()
	var p_after := rebel.global_position
	for i in 40:
		hale.global_position = rebel.global_position + Vector3(0, 1.0, 3.0)
		await seconds(0.5)
		if rebel.global_position.distance_to(p_after) > 3.0:
			break
	check(rebel.global_position.distance_to(p_after) > 3.0, "Führer läuft nach dem Laden weiter", "%.1f m" % rebel.global_position.distance_to(p_after))
	check(not said.has(greet), "Begrüßung wird nach dem Laden nicht wiederholt")

	# --- 4. nach Alarm, mit Gefallenen und zerstörtem LKW (Zusatzziel 5) ---
	var truck := rt.actors.get("AUTI_BAD") as Vehicle
	if truck:
		truck.explode()
	var victims: Array = []
	for e in m.enemies:
		if e.alive and victims.size() < 3:
			e.die()
			victims.append(e.persistent_id)
	m.raise_alarm(m.squad.leader().global_position, m.squad.leader())
	await seconds(4.0)
	var o5 := m.objective(&"o5")
	check(o5 != null and o5.state == Objective.State.DONE, "LKW zerstört → Zusatzziel 5", _objectives(m))
	snap = _snapshot(rt)
	obj = _objectives(m)
	gv = _gv(rt)
	var alive := _alive(m)
	m = await _save_load("orig_save_alarm")
	rt = m.runtime
	_compare(snap, _snapshot(rt), "Nach Alarm")
	check(m.alarm_raised, "Alarmzustand erhalten")
	check(_objectives(m) == obj, "Nach Alarm: Ziele gleich (Ziel 5 bleibt erfüllt)", _objectives(m))
	check(_gv(rt) == gv, "Nach Alarm: SaveGameValues gleich", _gv(rt))
	check(_alive(m) == alive, "Nach Alarm: dieselben Gegner leben", "%d" % alive.size())
	var truck2 := rt.actors.get("AUTI_BAD") as Vehicle
	check(truck2 == null or truck2.wrecked, "LKW bleibt zerstört")
	await seconds(5.0)
	check(not m.finished, "Mission läuft nach dem Laden weiter", str(Game.last_result.get("reason", "")))
	check(m.objective(&"o5").state == Objective.State.DONE, "Ziel 5 nicht zurückgesetzt/erneut ausgelöst")
	# Spielstand für den Löser (Erfüllbarkeit ab hier)
	Game.saves_used = 0
	check(Game.save_game("orig_save_a1_final"), "Spielstand für den Löser: orig_save_a1_final")

	# --- 5. älterer Spielstand ohne Skriptzustand ---
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path("orig_save_guide0")))
	(data["state"]["extra"] as Dictionary).erase("orig_vm")
	(data["state"]["extra"] as Dictionary).erase("orig_vm_version")
	var f := FileAccess.open(Game.save_path("orig_save_old"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var hints: Array[String] = []
	Events.message.connect(func(t, _s): hints.append(t))
	var old := mission()
	check(Game.load_game("orig_save_old"), "Älterer Spielstand wird angenommen")
	m = await _wait_mission(old)
	check(m != null and m.runtime != null and m.runtime.vms.size() >= 100, "Älterer Spielstand lädt (Skripte starten neu)")
	check(hints.any(func(t): return String(t).contains("älterer Spielstand")), "Hinweis auf fehlenden Skriptzustand", str(hints.slice(0, 4)))


func _phase_a2(m: OrigMission) -> void:
	var rt := m.runtime
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(4.0)
	rt.game_values[51] = 3
	isolate_enemies([])
	await seconds(1.0)
	var snap := _snapshot(rt)
	var obj := _objectives(m)
	var gv := _gv(rt)
	var alive := _alive(m)
	var charges := {}
	for n in get_tree().get_nodes_in_group("persistent"):
		if "persistent_id" in n and n.persistent_id != "":
			charges[n.persistent_id] = JSON.stringify(n.serialize())
	m = await _save_load("orig_save_a2")
	rt = m.runtime
	_compare(snap, _snapshot(rt), "a2")
	check(_objectives(m) == obj, "a2: Ziele gleich", _objectives(m))
	check(_gv(rt) == gv and int(rt.game_values.get(51, 0)) == 3, "a2: SaveGameValues gleich (51 = 3)", _gv(rt))
	check(_alive(m) == alive, "a2: dieselben Gegner leben")
	var same := 0
	for n in get_tree().get_nodes_in_group("persistent"):
		if "persistent_id" in n and charges.has(n.persistent_id):
			var a = JSON.parse_string(charges[n.persistent_id])
			var b = JSON.parse_string(JSON.stringify(n.serialize()))
			if (a is Dictionary and b is Dictionary and a.get("state") == b.get("state")) or charges[n.persistent_id] == JSON.stringify(n.serialize()):
				same += 1
	check(same >= int(charges.size() * 0.9), "a2: Zustand der Originalakteure (Sprengplätze/Türen) erhalten", "%d/%d" % [same, charges.size()])
	await seconds(5.0)
	check(not m.finished, "a2: Mission läuft nach dem Laden weiter", str(Game.last_result.get("reason", "")))
