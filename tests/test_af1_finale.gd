extends "res://tests/test_gameplay.gd"
## AFRICA1 Finale (docs/status/af1_finale.md): Verstärkung (af1_posily_detector → AF1_posila_01..10 + Panzer panzer01 mit
## Besatzung AF1_tank01_01..03) erscheint, wenn die Gegnerzahl unter fin_soldiers fällt; Panzer fährt aus seiner Grube
## (HUMAN_Drive tank01_01/02); alle Gegner tot → Ziel 3, mit Dokumenten (Signal 5/6 an AF1_obj) → Fluchtziel, Sammeln am
## Opel/Jeep → Mission erfolgreich. Trupp unverwundbar.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_af1_finale

const REINF := ["AF1_posila_01", "AF1_posila_02", "AF1_posila_03", "AF1_posila_04", "AF1_posila_05", "AF1_posila_06",
	"AF1_posila_07", "AF1_posila_08", "AF1_posila_09", "AF1_posila_10", "AF1_tank01_01", "AF1_tank01_02", "AF1_tank01_03"]


func _physics_process(_d: float) -> void:
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS:
			s.max_health = maxf(s.max_health, 100000.0)
			s.health = s.max_health


func _enemy(m, nm: String) -> Soldier:
	for e in m.enemies:
		if is_instance_valid(e) and String(e.name) == nm:
			return e
	return null


func _alive_count(m) -> int:
	return m.enemies.filter(func(e): return is_instance_valid(e) and e.alive and not e.has_meta("hands_up")).size()


func _signal(m, frame: String, n: int) -> void:
	var vm: LsVM = m.runtime.vm_for(m.runtime.find_frame(frame))
	if vm:
		vm.signal_received(n)


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.runtime != null, "AFRICA1 geladen")
	if m == null:
		_finish()
		return
	for i in 600:
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
		await frames(5)
		if not m.runtime.in_cutscene and i > 60:
			break
	await seconds(2.0)
	var tank = m.runtime.find_frame("panzer01")
	check(tank is Vehicle, "Panzer panzer01 als Fahrzeug vorhanden", str(tank))
	var missing := []
	for nm in REINF:
		if _enemy(m, nm) == null:
			missing.append(nm)
	check(missing.is_empty(), "alle 13 Verstärkungssoldaten als Gegner angelegt", str(missing))
	var crew := 0
	for nm in ["AF1_tank01_01", "AF1_tank01_02", "AF1_tank01_03"]:
		var c := _enemy(m, nm)
		if c and c.vehicle == tank:
			crew += 1
	check(crew == 3, "Panzerbesatzung sitzt im Panzer (HUMAN_BoardVehicle)", "%d/3" % crew)
	var n0 := _alive_count(m)
	var tank_p0: Vector3 = tank.global_position if tank else Vector3.ZERO
	var watch := {}
	for nm in ["AF1_posila_01", "AF1_posila_04", "AF1_posila_07"]:
		var e := _enemy(m, nm)
		if e:
			watch[nm] = e.global_position
	print("AF1FIN Start: Gegner %d, Panzer %s" % [n0, str(tank_p0)])
	# Gegner außerhalb der Verstärkung töten, bis der Detektor (Zahl < Start − 11..12) auslöst
	var killed := 0
	for e in m.enemies.duplicate():
		if killed >= 14:
			break
		if not is_instance_valid(e) or not e.alive or String(e.name) in REINF or String(e.name) == "AF1_pobocnik" \
				or String(e.name).begins_with("AF1_cge"):
			continue
		e.die(m.squad.leader())
		killed += 1
		await frames(2)
	print("AF1FIN getötet %d, Gegner jetzt %d" % [killed, _alive_count(m)])
	# Detektor 2-s-Takt; Panzersignal nach ≈ 23 s, Panzer wartet 7 s, dann HUMAN_Drive
	var moved_tank := 0.0
	var moved := {}
	for i in 200:
		await seconds(0.5)
		for nm in watch:
			var e := _enemy(m, nm)
			if e and e.global_position.distance_to(watch[nm]) > 3.0:
				moved[nm] = true
		if tank:
			moved_tank = maxf(moved_tank, tank.global_position.distance_to(tank_p0))
		if moved.size() == watch.size() and moved_tank > 30.0:
			break
	check(moved.size() == watch.size(), "Verstärkungswellen 1–3 setzen sich in Bewegung (SendSignal 1)", str(moved.keys()))
	check(moved_tank > 30.0, "Panzer fährt aus der Grube los (HUMAN_Drive tank01_01/02)", "%.1f m" % moved_tank)
	# Rest töten (Verstärkung, Panzerbesatzung, Pobocnik)
	for e in m.enemies.duplicate():
		if is_instance_valid(e) and e.alive:
			e.die(m.squad.leader())
			await frames(1)
	await seconds(4.0)
	check(_alive_count(m) == 0, "alle Gegner tot (_GetCountOfCarnageEnemies == 0)")
	var o3 = m.objective(m.orig_objectives.get(3, &""))
	check(o3 != null and o3.state == Objective.State.DONE, "Ziel 3 „alle Gegner ausschalten“ erfüllt (af1_obj Whenever alldead)",
		str(o3.state) if o3 else "-")
	# Dokumente: Gespräch (af1_21 → Signal 5) + Dokumente gefunden (af1_documents → Signal 6) – nicht Teil dieses Fehlers
	_signal(m, "AF1_obj", 5)
	await seconds(0.5)
	_signal(m, "AF1_obj", 6)
	await seconds(4.0)
	var opel = m.runtime.find_frame("la_OpelFuj")
	check(opel != null, "Fluchtfahrzeug la_OpelFuj vorhanden")
	if opel:
		var k := 0
		for s in m.squad.members:
			if is_instance_valid(s) and s.alive:
				s.global_position = opel.global_position + Vector3(3.0 + k, 0.5, 3.0)
				k += 1
	for i in 60:
		await seconds(0.5)
		if m.finished:
			break
	check(m.finished and Game.last_result.get("success", false), "Mission AFRICA1 erfolgreich abgeschlossen",
		str(Game.last_result.get("reason", "")))
	_finish()
