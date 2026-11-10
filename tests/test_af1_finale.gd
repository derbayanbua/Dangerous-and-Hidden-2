extends "res://tests/test_gameplay.gd"
## AFRICA1 Finale (docs/status/af1_finale.md): Verstärkung (af1_posily_detector → AF1_posila_01..10 + Panzer panzer01 mit
## Besatzung AF1_tank01_01..03) erscheint, wenn die Gegnerzahl unter fin_soldiers fällt; Panzer fährt aus seiner Grube
## (HUMAN_Drive tank01_01/02); alle Gegner tot → Ziel 3, mit Dokumenten (Signal 5/6 an AF1_obj) → Fluchtziel, Sammeln am
## Opel/Jeep → Mission erfolgreich. Trupp unverwundbar.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_af1_finale

const REINF := ["AF1_posila_01", "AF1_posila_02", "AF1_posila_03", "AF1_posila_04", "AF1_posila_05", "AF1_posila_06",
	"AF1_posila_07", "AF1_posila_08", "AF1_posila_09", "AF1_posila_10", "AF1_tank01_01", "AF1_tank01_02", "AF1_tank01_03"]


## af1_finale2: Endpunkte der Wellensoldaten (letztes HUMAN_Move in af1_posily_NN.scr)
const END_FRAME := {"AF1_posila_01": "AF1_p01_end", "AF1_posila_02": "AF1_p02_end", "AF1_posila_03": "AF1_p03_end",
	"AF1_posila_04": "AF1_p04_end", "AF1_posila_05": "AF1_p05_end", "AF1_posila_06": "AF1_p06_end",
	"AF1_posila_07": "AF1_p07_end", "AF1_posila_08": "AF1_p08_end", "AF1_posila_09": "AF1_posily_09en",
	"AF1_posila_10": "AF1_posily_10en"}

var _trace: Soldier = null       ## Diagnose: Zustandswechsel eines Wellensoldaten (--trace=AF1_posila_NN)
var _trace_last := ""
var _mon: Array = []           ## überwachte Körper (Fahrzeuge + RigidBody3D)
var _mon_prev := {}             ## id → [pos, vel, y0]
var _flung: Array = []          ## Meldungen „hochgeschleudert“
var _vmax := {}                 ## id → [Name, max |Δv| je Bild, max Steigen m/s, max Höhe über Start]


func _physics_process(d: float) -> void:
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS:
			s.max_health = maxf(s.max_health, 100000.0)
			s.health = s.max_health
	if _trace and is_instance_valid(_trace):
		var br := _brain(_trace)
		var sig := "%s|%s|%s" % [br.get("state"), br.get("_script_target"), br.get("_move_target")]
		if sig != _trace_last:
			_trace_last = sig
			print("AF1TRACE %.2f %s %s pos %s" % [Time.get_ticks_msec() / 1000.0, _trace.name, sig, _trace.global_position])
	for b in _mon:
		if not is_instance_valid(b) or not b.is_inside_tree():
			continue
		var p: Vector3 = b.global_position
		if b is Soldier and (not b.alive or b.vehicle != null):
			_mon_prev.erase(b.get_instance_id())
			continue
		var v: Vector3 = (b as RigidBody3D).linear_velocity if b is RigidBody3D else (b as CharacterBody3D).velocity
		var id: int = b.get_instance_id()
		if _mon_prev.has(id):
			var pr: Array = _mon_prev[id]
			var dv := (v - (pr[1] as Vector3)).length()
			var rise := (p.y - (pr[0] as Vector3).y) / maxf(d, 0.001)
			var up := p.y - float(pr[2])
			var r: Array = _vmax.get(id, [String(b.name), 0.0, 0.0, 0.0])
			r[1] = maxf(r[1], dv)
			r[2] = maxf(r[2], rise)
			r[3] = maxf(r[3], up)
			_vmax[id] = r
			# hochgeschleudert: Geschwindigkeitssprung > 12 m/s in einem Bild, Steigen > 6 m/s oder > 4 m über Start
			# (Höhe über Start nur für lose Körper – Fahrzeuge fahren bergauf)
			# Soldaten: nur Geschwindigkeitssprung (Stufensteigen versetzt die Lage ohne Geschwindigkeit)
			var bad := (dv > 12.0 or v.y > 6.0) if b is Soldier \
				else (dv > 12.0 or rise > 6.0 or (up > 4.0 and not b is Vehicle))
			if bad and _flung.size() < 20:
				_flung.append("%s dv %.1f steigen %.1f hoehe +%.1f" % [b.name, dv, rise, up])
			_mon_prev[id] = [p, v, pr[2]]
		else:
			_mon_prev[id] = [p, v, p.y]


## Truppsoldat versetzen (sitzt er noch im Start-Jeep la_Jeepsas_01, erst aussteigen – sonst bleibt er am Sitz)
func _put(s: Soldier, at: Vector3) -> void:
	if s.vehicle is Vehicle:
		(s.vehicle as Vehicle).leave(s)
	s.global_position = at
	s.velocity = Vector3.ZERO


func _brain(s: Soldier) -> Node:
	for c in s.get_children():
		if c is EnemyBrain:
			return c
	return null


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
	if Game.cli.has("trace"):
		_trace = _enemy(m, String(Game.cli["trace"]))
		var tvm: LsVM = m.runtime.vm_for(_trace) if _trace else null
		if tvm:
			tvm.trace = true
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
	# af1_finale2: Trupp wie im Spiel am Flugplatz (Spielerbereich): Fahrnetzknoten 50–90 m vor dem Ende der Panzerroute,
	# möglichst nahe den Wellen-Endpunkten AF1_p0N_end → Verstärkung und Panzer treffen auf den Trupp
	m.runtime._drive_load()
	var gi0: int = m.runtime._drive_name("tank01_02")
	var tgoal: Vector3 = m.runtime._drive_astar.get_point_position(gi0) if gi0 >= 0 else Vector3.INF
	var pend = m.runtime.find_frame("AF1_p02_end")
	var area := Vector3.INF
	if tgoal.is_finite() and pend:
		var best := INF
		for pid in m.runtime._drive_astar.get_point_ids():
			var pp: Vector3 = m.runtime._drive_astar.get_point_position(pid)
			var dg := Vector2(pp.x - tgoal.x, pp.z - tgoal.z).length()
			if dg < 50.0 or dg > 90.0:
				continue
			var sc: float = pp.distance_to(pend.global_position)
			if sc < best:
				best = sc
				area = pp
	if area.is_finite():
		var k := 0
		for s in m.squad.members:
			if is_instance_valid(s) and s.alive:
				var at: Vector3 = area + Vector3(2.0 * (k % 2), 0.0, 2.0 * (k / 2))
				var hit := m.get_world_3d().direct_space_state.intersect_ray(
					PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1))
				_put(s, (hit["position"] as Vector3) + Vector3.UP * 0.2 if not hit.is_empty() else at + Vector3.UP)
				k += 1
	print("AF1FIN Trupp im Spielerbereich %s" % area)
	check(area.is_finite(), "Spielerbereich am Flugplatz gefunden (Fahrnetzknoten vor dem Routenende)", str(area))
	# Todesursachen der Verstärkung (Panzer/BMW überrollt eigene Leute = Fehlerbild „Teil fliegt umher“)
	var deaths := {}
	for nm in REINF:
		var e := _enemy(m, nm)
		if e:
			e.died.connect(func(by): deaths[nm] = String(by.name) if by is Node else "-")
	# af1_finale2: Fahrzeuge und lose Starrkörper überwachen (Hochschleudern)
	for n in m.find_children("*", "RigidBody3D", true, false):
		_mon.append(n)
	for nm in REINF:
		var e := _enemy(m, nm)
		if e:
			_mon.append(e)
	print("AF1FIN ueberwacht %d Koerper" % _mon.size())
	for wn in ["AF1_posily_0101", "AF1_posily_0201", "AF1_posily_0102", "AF1_posily_0202", "AF1_posily_0103", "AF1_posily_0203", "AF1_p01_end", "AF1_p02_end", "AF1_p03_end"]:
		var wf = m.runtime.find_frame(wn)
		print("AF1FIN WP %s %s" % [wn, wf.global_position if wf else "-"])
	# Ziel der Panzerfahrt: letzter Knoten der Route tank01_02 im Fahrzeugnetz
	m.runtime._drive_load()
	var gi: int = m.runtime._drive_name("tank01_02")
	var tank_goal: Vector3 = m.runtime._drive_astar.get_point_position(gi) if gi >= 0 else Vector3.INF
	var leader: Soldier = m.squad.leader()
	print("AF1FIN Panzerziel %s (Abstand Start %.1f m), Fuehrer %s" % [tank_goal, tank_p0.distance_to(tank_goal) if gi >= 0 else -1.0, leader.global_position])
	# Detektor 2-s-Takt; Panzersignal nach ≈ 23 s, Panzer wartet 7 s, dann HUMAN_Drive (bis zum Ende der Route)
	var moved_tank := 0.0
	var moved := {}
	var tank_goal_d := INF
	var tank_player_d := INF
	var t_still := 0.0
	var tank_last := tank_p0
	var max_still := 0.0
	var arrived := {}
	var combat := {}
	var drove := false
	var expl0: int = Effects.explosion_count
	for i in 400:
		await seconds(0.5)
		if i % 4 == 0:
			# neu entstandene Starrkörper (Helme, Trümmer, Deckel, Gore-Teile) mit überwachen
			for n in m.get_tree().root.find_children("*", "RigidBody3D", true, false):
				if not n in _mon:
					_mon.append(n)
					print("AF1FIN neuer Koerper %s bei %s (Panzer %s)" % [n.get_path(), n.global_position, tank.global_position if tank else Vector3.ZERO])
		for nm in watch:
			var e := _enemy(m, nm)
			if e and e.global_position.distance_to(watch[nm]) > 3.0:
				moved[nm] = true
		for nm in END_FRAME:
			var e := _enemy(m, nm)
			if e == null or not e.alive:
				continue
			var f = m.runtime.find_frame(END_FRAME[nm])
			if f and e.global_position.distance_to(f.global_position) < 3.0:
				arrived[nm] = true
			var br := _brain(e)
			if br and br.get("state") == EnemyBrain.State.COMBAT:
				combat[nm] = true
		if tank:
			var tp: Vector3 = tank.global_position
			moved_tank = maxf(moved_tank, tp.distance_to(tank_p0))
			if tank_goal.is_finite():
				tank_goal_d = minf(tank_goal_d, Vector2(tp.x - tank_goal.x, tp.z - tank_goal.z).length())
			for s in m.squad.members:
				if is_instance_valid(s) and s.alive:
					tank_player_d = minf(tank_player_d, tp.distance_to(s.global_position))
			# Stillstand während einer laufenden Skriptfahrt messen
			if tank.script_driving and not tank.drive_done():
				drove = true
				if tp.distance_to(tank_last) < 0.3:
					t_still += 0.5
					max_still = maxf(max_still, t_still)
				else:
					t_still = 0.0
			else:
				t_still = 0.0
			tank_last = tp
			if i % 10 == 0:
				var bmw = m.runtime.find_frame("la_BmwR_")
				var p2 := _enemy(m, "AF1_posila_02")
				var b2 := _brain(p2) if p2 else null
				if bmw:
					print("AF1FIN   BMWPROC pp %s cp %s tree %s pm %s parent %s" % [bmw.is_physics_processing(), bmw.can_process(),
						bmw.is_inside_tree(), bmw.process_mode, bmw.get_parent().get_path() if bmw.get_parent() else "-"])
				print("AF1FIN   BMW %s | posila_02 %s v %.1f state %s" % [bmw.global_position if bmw else Vector3.ZERO,
					p2.global_position if p2 else Vector3.ZERO, p2.velocity.length() if p2 else 0.0, str(b2.get("state")) if b2 else "-"])
				if b2:
					var tg: Vector3 = b2.get("_script_target")
					var path := PackedVector3Array()
					if tg.is_finite():
						path = NavigationServer3D.map_get_path(p2.get_world_3d().navigation_map, p2.global_position, tg, true)
					print("AF1FIN   p02 st %s mt %s hmt %s sc %s mi %s path %d end %s" % [tg, b2.get("_move_target"),
						b2.has_move_target(), b2.get("script_control"), p2.move_input, path.size(), path[path.size() - 1] if path.size() > 0 else "-"])
				print("AF1FIN t=%.0f Panzer %s v %.1f Ziel %.1f Spieler %.1f fahrt %s" % [i * 0.5, tp, tank.linear_velocity.length(), tank_goal_d, tank_player_d, str(tank.script_driving and not tank.drive_done())])
		var engaged := {}
		engaged.merge(arrived)
		engaged.merge(combat)
		for nm in deaths:
			if nm in END_FRAME:
				engaged[nm] = true
		if drove and tank and tank.drive_done() and (engaged.size() >= 10 or i > 280):
			break
	var bmw2 = m.runtime.find_frame("la_BmwR_")
	if bmw2 is Vehicle:
		print("AF1FIN BMW Ende sd %s goal %s rest %d fahrer %s done %s freeze %s sleep %s" % [bmw2.script_driving, bmw2.get("_drive_goal"),
			(bmw2.get("_drive_path") as Array).size(), bmw2.driver().name if bmw2.driver() else "-", bmw2.drive_done(), bmw2.freeze, bmw2.sleeping])
	print("AF1FIN Wellen angekommen %s, Kampf %s, Explosionen %d" % [arrived.keys(), combat.keys(), Effects.explosion_count - expl0])
	for d in m.get_tree().get_nodes_in_group("destructibles"):
		if d.get("destroyed") == true:
			print("AF1FIN zerstoert %s bei %s" % [d.get_path(), (d as Node3D).global_position])
	for e in m.enemies:
		if is_instance_valid(e) and String(e.name) in END_FRAME:
			var f = m.runtime.find_frame(END_FRAME[String(e.name)])
			var bb := _brain(e)
			var vm: LsVM = m.runtime.vm_for(e)
			if vm:
				print("AF1FIN   VM %s pc %d ended %s term %s block %d wartet %s paused %s" % [e.name, vm.pc, vm.ended, vm.terminated,
					vm.block_pc, vm.wait_until.is_valid(), vm.paused])
				if vm.code and vm.pc > 0 and vm.pc <= vm.code.ops.size():
					print("AF1FIN     op %s" % str(vm.code.ops[vm.pc - 1]))
			print("AF1FIN %s alive %s pos %s ende %.1f m fuehrer %.1f m state %s st %s sc %s fz %s" % [e.name, e.alive, e.global_position,
				e.global_position.distance_to(f.global_position) if f else -1.0, e.global_position.distance_to(leader.global_position),
				str(bb.get("state")) if bb else "-", str(bb.get("_script_target")) if bb else "-", str(bb.get("script_control")) if bb else "-",
				str(e.vehicle.name) if e.vehicle else "-"])
	check(moved.size() == watch.size(), "Verstärkungswellen 1–3 setzen sich in Bewegung (SendSignal 1)", str(moved.keys()))
	check(moved_tank > 30.0, "Panzer fährt aus der Grube los (HUMAN_Drive tank01_01/02)", "%.1f m" % moved_tank)
	check(tank_goal_d < 10.0 or tank_player_d < 60.0, "Panzer fährt die ganze Strecke (Ende tank01_02) bzw. bis in Spielernähe",
		"Rest %.1f m, Spieler %.1f m" % [tank_goal_d, tank_player_d])
	check(max_still < 8.0, "Panzer bleibt während der Skriptfahrt nicht stehen (≤ 8 s Stillstand)", "%.1f s" % max_still)
	var worst := ""
	for id in _vmax:
		var r: Array = _vmax[id]
		if r[1] > 4.0 or r[2] > 2.0:
			worst += "%s dv %.1f steigen %.1f; " % r.slice(0, 3)
	print("AF1FIN Spruenge: %s" % worst)
	check(_flung.is_empty(), "kein Fahrzeug/Objekt hochgeschleudert (Δv ≤ 12 m/s je Bild, Steigen ≤ 6 m/s, lose ≤ 4 m)", str(_flung))
	var reached := {}
	for nm in arrived:
		reached[nm] = true
	for nm in combat:
		reached[nm] = true
	for nm in deaths:
		for s in m.squad.members:
			if is_instance_valid(s) and String(s.name) == String(deaths[nm]) and nm in END_FRAME:
				reached[nm] = true      # im Gefecht vom Trupp erschossen = am Spielerbereich angekommen
	check(reached.size() >= 8, "Wellensoldaten erreichen ihre Stellung am Spielerbereich bzw. greifen an",
		"%d/10 %s" % [reached.size(), str(reached.keys())])
	var friendly := []
	for nm in deaths:
		var by := _enemy(m, String(deaths[nm]))
		if deaths[nm] == nm:
			continue        # eigene Granate/Sturz (KI-Thema, nicht Fahrzeug) – nur im Protokoll
		if deaths[nm] == "-" or by != null or String(deaths[nm]).begins_with("panzer") or String(deaths[nm]).begins_with("la_"):
			friendly.append("%s←%s" % [nm, deaths[nm]])
	print("AF1FIN Tode Verstaerkung %s" % deaths)
	check(friendly.is_empty(), "keine Verstärkung von eigenen Fahrzeugen/Kameraden überrollt oder getötet", str(friendly))
	_mon.clear()
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
				_put(s, opel.global_position + Vector3(3.0 + k, 0.5, 3.0))
				k += 1
	for i in 60:
		await seconds(0.5)
		if m.finished:
			break
	if opel:
		var near := []
		for s in m.squad.members:
			if is_instance_valid(s):
				near.append("%s %.1f m alive %s fz %s" % [s.name, s.global_position.distance_to(opel.global_position), s.alive, s.vehicle])
		var ovm: LsVM = m.runtime.vm_for(m.runtime.find_frame("AF1_opelflak"))
		print("AF1FIN Opel-Sammeln %s | VM %s" % [near, ("pc %d ended %s term %s wh %s" % [ovm.pc, ovm.ended, ovm.terminated, ovm.whenever_active]) if ovm else "-"])
	var ost := []
	for o in m.objectives:
		ost.append("%s=%s" % [o.id, o.state])
	check(m.finished and Game.last_result.get("success", false), "Mission AFRICA1 erfolgreich abgeschlossen",
		"%s | Opel Wrack %s | Ziele %s" % [str(Game.last_result.get("reason", "")), str(opel.get("wrecked")) if opel else "-", str(ost)])
	_finish()
