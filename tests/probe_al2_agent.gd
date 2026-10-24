extends "res://tests/test_gameplay.gd"
## Sonde ALPS2 (Agent Burma/Alpen): Spieler neben Agentin Salter (AL2_agent) setzen und Skriptzustand ausgeben.
##   tools\godot.cmd --headless -- --mission=al2_makler --autoplay=probe_al2_agent --ls_print


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	var rt := m.runtime
	rt.auto_skip = true
	await seconds(1.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(2.0)
	var ag: Node3D = rt.find_frame("AL2_Agent")
	var vm: LsVM = rt.vm_for(ag) if ag else null
	print("PROBE agent=", ag, " typ=", ag.get_class() if ag else "-", " pos=", ag.global_position if ag else Vector3.ZERO,
		" vm=", vm.name if vm else "-")
	if vm:
		print("PROBE vm terminated=%s ended=%s paused=%s atomic=%s pc=%d whenever=%s disabled=%s" % [vm.terminated, vm.ended,
			vm.paused, vm.atomic, vm.pc, vm.whenever_active, vm.whenevers_disabled])
	for nm in ["AL2_agent", "AL2_01", "AL2_36", "AL2_05", "AL2_09", "AL2_10", "al2_11", "AL2_33", "AL2_34", "AL2_32"]:
		var s: Node3D = rt.find_frame(nm)
		if s:
			var hit := s.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
				s.global_position + Vector3.UP * 1.0, s.global_position + Vector3.DOWN * 3.0, 1))
			print("PROBE akteur %s pos=%s boden=%s alive=%s" % [nm, s.global_position, hit.get("position", "keiner"),
				s.alive if s is Soldier else "-"])
	if Game.cli.has("stair"):
		await _stair(m, rt, ag as Soldier)
		_finish()
		return
	var lead := m.squad.leader()
	print("PROBE lead=", lead.name, " pos=", lead.global_position, " team=", m.squad.members.size())
	for i in 6:
		lead.global_position = ag.global_position + Vector3(1.0, 0.3, 0.0)
		lead.velocity = Vector3.ZERO
		await seconds(1.0)
		if rt.in_cutscene:
			rt.end_cutscene()
		print("PROBE t=%d lead=%s agent=%s dist=%.2f whenever=%s ended=%s pc=%d wait=%.2f" % [i, lead.global_position,
			ag.global_position, lead.global_position.distance_to(ag.global_position), vm.whenever_active, vm.ended, vm.pc, vm.wait])
	# Begleiten: Spieler 2 m hinter der Agentin, Lage/Ziel der Skriptbewegung je Sekunde
	var last := ag.global_position
	for i in int(Game.cli.get("follow", "0")):
		var dir: Vector3 = ag.global_position - last
		var behind: Vector3 = ag.global_position - dir.normalized() * 2.0 if dir.length() > 0.05 else ag.global_position + Vector3(1.0, 0, 0)
		last = ag.global_position
		lead.global_position = behind + Vector3(0, 0.3, 0)
		lead.velocity = Vector3.ZERO
		await seconds(1.0)
		if rt.in_cutscene:
			rt.end_cutscene()
		var eb: EnemyBrain = ag.get_node_or_null("EnemyBrain")
		var na: NavigationAgent3D = eb.get("agent") if eb else null
		print("PROBE f=%d agent=%s pc=%d wait_until=%s ziel=%s nav_fertig=%s naechster=%s" % [i, ag.global_position, vm.pc,
			vm.wait_until.is_valid(), eb.get("_script_target") if eb else "-",
			na.is_navigation_finished() if na else "-", na.get_next_path_position() if na else "-"])
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		print("PROBE Ziel %d state=%d %s" % [idx, o.state if o else -1, o.text if o else ""])
	_finish()


## Treppe al2_agx_01 → al2_agx_02: Navigationspfad und Bewegung der Agentin (nach dem Navmesh-Bake)
func _stair(m: OrigMission, rt: LsRuntime, ag: Soldier) -> void:
	var t0 := Time.get_ticks_msec()
	while not m.nav_ready and Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
	print("PROBE nav_ready=", m.nav_ready)
	var a: Vector3 = rt.find_frame("al2_agx_01").global_position
	var b: Vector3 = rt.find_frame("al2_agx_02").global_position
	var w1: Vector3 = rt.find_frame("way1").global_position
	var map := ag.get_world_3d().navigation_map
	var pa := NavigationServer3D.map_get_closest_point(map, a)
	var pb := NavigationServer3D.map_get_closest_point(map, b)
	var path := NavigationServer3D.map_get_path(map, pa, pb, true)
	print("PROBE agx01=%s naechst=%s agx02=%s naechst=%s way1=%s" % [a, pa, b, pb, w1])
	if path.size() > 0:
		print("PROBE pfad %d Punkte, Ende=%s, Rest zu agx02=%.2f" % [path.size(), path[path.size() - 1],
			path[path.size() - 1].distance_to(b)])
	for p in path:
		print("PROBE  p ", p)
	var lead := m.squad.leader()
	rt.vm_for(ag).terminated = true     # eigenes Skript ruht, nur die Bewegung wird geprüft
	ag.global_position = a + Vector3.UP * 0.3
	var eb: EnemyBrain = ag.get_node("EnemyBrain")
	eb.suspended = false
	eb.script_move(b)
	for i in 40:
		lead.global_position = ag.global_position + Vector3(1.5, 0.3, 0)
		await seconds(1.0)
		print("PROBE s=%d agent=%s fertig=%s naechster=%s" % [i, ag.global_position, eb.script_move_done(),
			eb.agent.get_next_path_position()])
		var cols := []
		for ci in (ag as Soldier).get_slide_collision_count():
			var cc := (ag as Soldier).get_slide_collision(ci)
			cols.append("%s n=%s" % [cc.get_collider().name if cc.get_collider() else "-", cc.get_normal()])
		print("PROBE   mv=%s vel=%s stance=%d mode=%d kollision=%s phys=%s climb=%.2f mounted=%s puppet=%s veh=%s alive=%s" % [
			(ag as Soldier).move_input, (ag as Soldier).velocity, (ag as Soldier).stance, (ag as Soldier).move_mode, cols,
			ag.is_physics_processing(), float(ag.get("_climb_t")), ag.get("mounted"), ag.get("net_puppet"), ag.get("vehicle"),
			ag.get("alive")])
		if i == 4:
			var so := ag as Soldier
			var fw := so.move_input.normalized()
			var sp := so.get_world_3d().direct_space_state
			for hh in [0.05, 0.2, 0.35, 0.5, 0.9, 1.5]:
				var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(so.global_position + Vector3.UP * hh,
					so.global_position + Vector3.UP * hh + fw * 1.0, 1, [so.get_rid()]))
				print("PROBE   strahl h=%.2f -> %s" % [hh, "frei" if r.is_empty() else "%s %s n=%s" % [r.collider.name,
					r.position, r.normal]])
			for dd in [0.3, 0.6, 1.0]:
				var p0: Vector3 = so.global_position + fw * dd
				var rd := sp.intersect_ray(PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 1.0, p0 + Vector3.DOWN * 1.0, 1,
					[so.get_rid()]))
				print("PROBE   boden +%.1f m: %s" % [dd, rd.get("position", "keiner")])
			var kc := KinematicCollision3D.new()
			print("PROBE   test_move vor: ", so.test_move(so.global_transform, fw * 0.3, kc), " n=", kc.get_normal(),
				" p=", kc.get_position(), " c=", kc.get_collider())
		print("PROBE   wasser=%s swimming=%s heal=%.1f fern=%s" % [(ag as Soldier).water_level(), ag.get("swimming"),
			float(ag.get("heal_time_left")), ag.get("using_binoculars")])
		if eb.script_move_done():
			break
	print("PROBE Abstand way1=%.2f" % ag.global_position.distance_to(w1))
