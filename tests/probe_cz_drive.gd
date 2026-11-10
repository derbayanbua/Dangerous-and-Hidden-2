extends "res://tests/test_gameplay.gd"
## Gap-Analyse Tschechien (09.11.2026): eine Skriptfahrt beobachten (auch Rückwärtsfahrten, HUMAN_Drive mit kmh < 0).
##   tools\run_locked.ps1 -Name gapcz -Log test_output\czdrive_<tag>.log -GodotArgs "--headless -- --mission=<id>
##     --autoplay=probe_cz_drive --veh=<Fahrzeug> [--script=<Skriptname> --signal=<n>] [--secs=150]"
## Trupp unverwundbar und weit weg (Kartenrand, damit keine Alarme die Fahrt abbrechen). Alle 2 s: Lage, Vorwärtskomponente
## der Geschwindigkeit (negativ = rückwärts), aktueller blockierender Befehl des Fahrers. Zeilen DRIVE_*.

var _t := 0.0


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	var rt: LsRuntime = m.runtime
	rt.auto_skip = true
	await seconds(2.0)
	for s in m.squad.members:
		s.max_health = 1.0e6
		s.health = s.max_health
	for e in m.enemies:
		var per: Perception = e.get_node_or_null("Perception")
		if per:
			per.sight_range = 0.01
			per.hear_range = 0.0
	var veh: Node3D = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if String(v.name).to_lower() == String(Game.cli.get("veh", "")).to_lower():
			veh = v
	if veh == null:
		print("DRIVE_FEHLER Fahrzeug fehlt")
		_finish()
		return
	# --tp=x,y,z: Trupp dorthin (Navmesh-nächster Punkt), z. B. um _PlayerInRange-Auslöser zu wecken
	if Game.cli.has("tp"):
		var c := String(Game.cli["tp"]).split(",")
		var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
		p = NavigationServer3D.map_get_closest_point(m.get_viewport().world_3d.navigation_map, p)
		var i := 0
		for s in m.squad.members:
			s.global_position = p + Vector3(i * 1.2, 0.3, 0)
			s.velocity = Vector3.ZERO
			i += 1
		print("DRIVE_TP %s" % str(p))
	if Game.cli.has("script"):
		for vm in rt.vms:
			if vm.name.get_basename() == String(Game.cli["script"]):
				vm.signal_received(int(Game.cli.get("signal", "1")))
				print("DRIVE_SIGNAL %s %s" % [vm.name, Game.cli.get("signal", "1")])
	var secs := float(Game.cli.get("secs", "150"))
	var start := veh.global_position
	var min_fwd := 0.0
	var rev_dist := 0.0
	var last := start
	while _t < secs:
		await seconds(2.0)
		_t += 2.0
		var lv: Vector3 = veh.linear_velocity if "linear_velocity" in veh else Vector3.ZERO
		var fwd := lv.dot(veh.global_basis.z)
		min_fwd = minf(min_fwd, fwd)
		if fwd < -0.3:
			rev_dist += veh.global_position.distance_to(last)
		last = veh.global_position
		var drv = veh.driver() if veh.has_method("driver") else null
		var op := ""
		if drv:
			var vm: LsVM = rt.vm_for(drv)
			if vm and vm.wait_until.is_valid() and vm.code and vm.block_pc >= 0 and vm.block_pc < vm.code.ops.size():
				op = str(vm.code.ops[vm.block_pc]).left(80)
		print("DRIVE t=%.0f pos=%s fwd=%.2f fahrer=%s op=%s" % [_t, str(veh.global_position.round()), fwd, drv.name if drv else "-", op])
	print("DRIVE_SUMME veh=%s strecke=%.1f rueckwaerts_m=%.1f min_vorwaerts=%.2f end=%s" % [veh.name, start.distance_to(veh.global_position), rev_dist, min_fwd, str(veh.global_position.round())])
	check(true, "Fahrt beobachtet")
	_finish()
