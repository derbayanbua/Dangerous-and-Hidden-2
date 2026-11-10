extends "res://tests/test_gameplay.gd"
## Gap-Analyse (Alpen/Burma/Normandie): Originalskripte laufen lassen und Skriptfahrten beobachten.
##   --mission=<id> --autoplay=probe_gap_drive --veh=Sherman[,Hakl] --goals=Sherman01,Sherman18[,...]
##     [--sig=SKRIPT:n@s;SKRIPT:n@s]  Signal n an die VM des Skripts nach s Sekunden
##     [--vms=skript,skript]           VM-Zustand (pc/Warten/Ende) alle 10 s und am Ende
##     [--dur=300] [--speed=2] [--at=x,y,z]  Trupp dorthin (unverwundbar, ruht)
## Ausgabe: GAPDRV-Zeilen (Lage, Fahrer, Stillstand > 8 s während der Fahrt), GAPGOAL je Zielknoten (kleinster Abstand),
## GAPVM je VM (hängt = wartet seit > 60 s auf denselben blockierenden Befehl).


func _vm(rt, nm: String):
	for v in rt.vms:
		if String(v.name).to_lower() == nm.to_lower() or String(v.name).to_lower().get_file().get_basename() == nm.to_lower():
			return v
	return null


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	if m == null or m.runtime == null:
		check(false, "Originalmission")
		_finish()
		return
	var rt = m.runtime
	rt.auto_skip = true
	await frames(60)
	var at := String(Game.cli.get("at", ""))
	for s in m.squad.members:
		s.max_health = 1.0e6      # Trupp IMMER unverwundbar
		s.health = s.max_health
		if at != "":
			var c := at.split(",")
			s.global_position = Vector3(float(c[0]), float(c[1]), float(c[2])) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		s.process_mode = Node.PROCESS_MODE_DISABLED
	# fix_0103: --godlike=Name,… macht zusätzlich diese Figuren unverwundbar (z. B. BU2_Allied02, der die Sherman-Kette signalisiert)
	var gl := String(Game.cli.get("godlike", "")).to_lower().split(",", false)
	if not gl.is_empty():
		for n in get_tree().get_nodes_in_group("soldiers") if get_tree().has_group("soldiers") else m.find_children("*", "Soldier", true, false):
			if n is Soldier and gl.has(String(n.name).to_lower()):
				n.max_health = 1.0e6
				n.health = n.max_health
				print("GAPDRV unverwundbar: ", n.name)
	Engine.time_scale = float(Game.cli.get("speed", "2"))
	var vehs := {}
	var want := String(Game.cli.get("veh", "")).to_lower().split(",", false)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if want.is_empty() or want.has(String(v.name).to_lower()):
			vehs[String(v.name)] = v
	print("GAPDRV Fahrzeuge: ", vehs.keys())
	var goals := {}
	for g in String(Game.cli.get("goals", "")).split(",", false):
		var gi: int = rt._drive_name(g)
		goals[g] = {"node": gi, "pos": rt._drive_astar.get_point_position(gi) if gi >= 0 else Vector3.INF, "best": INF, "veh": ""}
		if gi < 0:
			print("GAPGOAL %s: Name nicht im Fahrnetz" % g)
	var sigs: Array = []
	for e in String(Game.cli.get("sig", "")).split(";", false):
		var a := e.split("@")
		var b := a[0].split(":")
		sigs.append({"vm": b[0], "n": int(b[1]), "t": float(a[1]) if a.size() > 1 else 0.0, "done": false})
	var vmnames := String(Game.cli.get("vms", "")).split(",", false)
	var dur := float(Game.cli.get("dur", "300"))
	var last := {}
	var still := {}
	var travelled := {}
	var vmwait := {}
	var t := 0.0
	var step := 1.0
	while t < dur and is_instance_valid(m) and not m.finished:
		await get_tree().create_timer(step, false).timeout
		t += step
		if in_cutscene_safe(rt):
			rt.end_cutscene()
		for sg in sigs:
			if not sg.done and t >= sg.t:
				var vm = _vm(rt, sg.vm)
				print("GAPSIG t=%.0f %s <- %d %s" % [t, sg.vm, sg.n, "ok" if vm else "VM fehlt"])
				if vm:
					vm.signal_received(sg.n)
				sg.done = true
		for vn in vehs:
			var v = vehs[vn]
			if not is_instance_valid(v):
				continue
			var p: Vector3 = v.global_position
			var drv = v.driver()
			var moved: float = p.distance_to(last.get(vn, p))
			travelled[vn] = float(travelled.get(vn, 0.0)) + moved
			last[vn] = p
			var driving: bool = not v.drive_done()
			still[vn] = float(still.get(vn, 0.0)) + step if driving and moved < 0.3 else 0.0
			if still[vn] == 8.0:
				print("GAPDRV STILL %s t=%.0f pos=%s Fahrer=%s" % [vn, t, p, drv.name if drv else "-"])
			if int(t) % 10 == 0:
				print("GAPDRV %s t=%.0f pos=(%.1f,%.1f,%.1f) fährt=%s Fahrer=%s wrack=%s weg=%.0f" % [vn, t, p.x, p.y, p.z, driving,
					drv.name if drv else "-", v.get("wrecked"), travelled[vn]])
			for g in goals:
				if goals[g].node >= 0:
					var d: float = p.distance_to(goals[g].pos)
					if d < goals[g].best:
						goals[g].best = d
						goals[g].veh = vn
		for nm in vmnames:
			var vm = _vm(rt, nm)
			if vm == null:
				continue
			var key: String = "%d" % vm.block_pc if vm.wait_until.is_valid() else ""
			if key != "" and vmwait.get(nm, ["", 0.0])[0] == key:
				vmwait[nm] = [key, vmwait[nm][1] + step]
			else:
				vmwait[nm] = [key, 0.0]
			if int(t) % 10 == 0:
				print("GAPVM %s t=%.0f pc=%d wartet=%s seit=%.0f ende=%s signale=%s" % [nm, t, vm.pc, key != "", vmwait[nm][1], vm.ended, vm.signals.keys()])
	Engine.time_scale = 1.0
	# fix_0103: --strict=1 → jedes Ziel ist eine Prüfung (Abstand < --goal_r, Standard 6 m), dazu --max_still=<s>
	var strict := String(Game.cli.get("strict", "0")) == "1"
	var goal_r := float(Game.cli.get("goal_r", "6"))
	for g in goals:
		var ok: bool = goals[g].best < goal_r
		print("GAPGOAL %s kleinster Abstand %.1f m (%s) %s" % [g, goals[g].best, goals[g].veh, "ERREICHT" if ok else "NICHT ERREICHT"])
		if strict:
			check(ok, "Ziel %s erreicht (%.1f m < %.1f m)" % [g, goals[g].best, goal_r])
	if strict:
		for vn in vehs:
			if is_instance_valid(vehs[vn]) and vehs[vn].get("slope_glides") != null:
				print("GAPDRV %s Hang-Nachführungen %d" % [vn, vehs[vn].slope_glides])
	for nm in vmnames:
		var w = vmwait.get(nm, ["", 0.0])
		print("GAPVM_END %s %s" % [nm, ("HÄNGT seit %.0f s" % w[1]) if w[1] > 60.0 else "ok"])
	print("GAPEND t=%.0f beendet=%s grund=%s" % [t, not is_instance_valid(m) or m.finished, Game.last_result.get("reason", "")])
	check(true, "Sonde")
	_finish()


func in_cutscene_safe(rt) -> bool:
	return is_instance_valid(rt) and rt.in_cutscene
