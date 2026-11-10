extends "res://tests/test_gameplay.gd"
## Gap-Analyse Afrika (docs/gap/README_afrika.md): skriptgesteuerte Panzerfahrten AFRICA2/4/5 prüfen.
## Je Fall: Fahrer sitzt im Panzer (HUMAN_BoardVehicle), Auslöser wie im Originalskript (Signal bzw. OnAlarm),
## dann Weg des Panzers, Stillstand, Ende der Skriptfahrt. Trupp unverwundbar.
##   tools\godot.cmd --headless -- --mission=af2_flugschau --autoplay=probe_af_tanks [--wait=90]
##   Missionen: af2_flugschau (AF2_tank1_01), af4_karawane (AF3b_tank01_01/AF3b_tank02_01), af5_whiskey_bar (AF4_tank2/3_driver)

const CASES := {
	"af2_flugschau": [["AF2_tank1_01", "alarm"]],
	"af4_karawane": [["AF3b_tank01_01", "sig1"], ["AF3b_tank02_01", "sig1"]],
	"af5_whiskey_bar": [["AF4_tank2_driver", "alarm"], ["AF4_tank3_driver", "alarm"]],
}


func _physics_process(_d: float) -> void:
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS:
			s.max_health = maxf(s.max_health, 100000.0)
			s.health = s.max_health


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m = mission()
	if m == null or m.get("runtime") == null:
		check(false, "Mission geladen")
		_finish()
		return
	for i in 600:
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
		await frames(5)
		if not m.runtime.in_cutscene and i > 60:
			break
	await seconds(2.0)
	var mid := String(Game.cli.get("mission", ""))
	var wait := float(Game.cli.get("wait", "90"))
	var only := String(Game.cli.get("case", ""))
	for c in CASES.get(mid, []):
		if not is_instance_valid(m):
			check(false, "Mission läuft noch vor %s" % c[0])
			break
		if only != "" and String(c[0]) != only:
			continue
		await _case(m, String(c[0]), String(c[1]), wait)
	_finish()


func _case(m, drv_name: String, how: String, wait: float) -> void:
	var drv = m.runtime.find_frame(drv_name)
	check(drv is Soldier, "%s vorhanden" % drv_name, str(drv))
	if not drv is Soldier:
		return
	var veh = null
	for i in 70:      # Einsteigen kann einen Fußweg brauchen (HUMAN_BoardVehicle aus > 12 m)
		veh = (drv as Soldier).vehicle
		if veh is Vehicle or not (drv as Soldier).alive:
			break
		await seconds(1.0)
	check(veh is Vehicle, "%s sitzt im Fahrzeug (HUMAN_BoardVehicle)" % drv_name, "%s pos %s" % [veh, (drv as Soldier).global_position])
	if not veh is Vehicle:
		return
	var p0: Vector3 = veh.global_position
	# Trupp an einen Fahrnetzknoten 50–80 m vom Panzer stellen (DriveNearPlayer sucht Knoten ≤ 20 m um den Spieler;
	# _PlayerInRange(200) weckt den AF2-Fahrer)
	var fwd: Vector3 = veh.global_basis.z
	fwd.y = 0.0
	var at: Vector3 = p0 + fwd.normalized() * 60.0
	m.runtime._drive_load()
	var best := INF
	for pid in m.runtime._drive_astar.get_point_ids():
		var pp: Vector3 = m.runtime._drive_astar.get_point_position(pid)
		var dd := Vector2(pp.x - p0.x, pp.z - p0.z).length()
		if dd >= 50.0 and dd <= 80.0 and absf(dd - 60.0) < best:
			best = absf(dd - 60.0)
			at = pp
	var hit = m.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, 1))
	if not hit.is_empty():
		at = hit["position"] + Vector3.UP * 0.3
	var k := 0
	for s in m.squad.members:
		if is_instance_valid(s) and s.alive:
			if s.vehicle is Vehicle:
				(s.vehicle as Vehicle).leave(s)
			s.global_position = at + Vector3(2.0 * (k % 2), 0.0, 2.0 * (k / 2))
			s.velocity = Vector3.ZERO
			k += 1
	await seconds(3.0)
	var vm: LsVM = m.runtime.vm_for(drv)
	if vm:
		vm.trace = Game.cli.has("trace")
		if how == "sig1":
			vm.signal_received(1)
		else:
			vm.fire("ONALARM")
	print("AFTANK %s %s start %s veh %s trupp %s" % [drv_name, how, p0, veh.name, at])
	var moved := 0.0
	var stand := 0.0
	var max_stand := 0.0
	var last: Vector3 = p0
	var started := false
	var t := 0.0
	var done_at := -1.0
	while t < wait:
		await seconds(1.0)
		t += 1.0
		if not is_instance_valid(m) or not is_instance_valid(veh):
			print("AFTANK %s Mission/Fahrzeug beendet nach %d s" % [drv_name, int(t)])
			break
		var p: Vector3 = veh.global_position
		var step := Vector2(p.x - last.x, p.z - last.z).length()
		moved += step
		last = p
		if veh.script_driving:
			started = true
			if step < 0.3:
				stand += 1.0
				max_stand = maxf(max_stand, stand)
			else:
				stand = 0.0
		if started and done_at < 0.0 and veh.drive_done():
			done_at = t
		if int(t) % 10 == 0:
			print("AFTANK %s t %d pos %s weg %.1f fahrt %s fertig %s abstand_trupp %.1f" % [drv_name, int(t), p, moved,
				veh.script_driving, veh.drive_done(), Vector2(p.x - at.x, p.z - at.z).length()])
	var pe: Vector3 = veh.global_position if is_instance_valid(veh) else p0
	print("AFTANK_RES %s weg %.1f netto %.1f max_stillstand %.0f s fertig_nach %s abstand_trupp %.1f wrack %s" % [drv_name,
		moved, Vector2(pe.x - p0.x, pe.z - p0.z).length(), max_stand, done_at, Vector2(pe.x - at.x, pe.z - at.z).length(),
		veh.wrecked if is_instance_valid(veh) else "-"])
	check(moved > 10.0, "%s Panzer fährt (> 10 m)" % drv_name, "%.1f m" % moved)
	check(max_stand <= 10.0, "%s kein Stillstand > 10 s während der Skriptfahrt" % drv_name, "%.0f s" % max_stand)
