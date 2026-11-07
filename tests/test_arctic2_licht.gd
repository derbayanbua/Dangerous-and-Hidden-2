extends "res://tests/test_gameplay.gd"
## 0.10.1 ARCTIC2 Gitterböden + Lampenlicht (Status docs/status/arctic2_licht.md)
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_arctic2_licht
##   Nachtkarte nur Licht: --mission=nw1_dampfleitung --autoplay=test_arctic2_licht --phase=licht
## Gitter: alle Kisten-/Volumen-Gitter (Meta klz_grate) haben Kollision, Strahl von oben trifft das Gitter, ein Soldat
## steht 2 s auf einem m_bmmriz-Gitter ohne durchzufallen. Licht: gebackene Lampen als echte Lichter, Obergrenze,
## Energie > alter Stand, Schatten höchstens SHADOW_MAX.

var _m: Mission


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _run() -> void:
	await frames(5)
	check(await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and mm.squad and mm.squad.leader(), 500.0), "Einsatz geladen")
	_m = Game.current_mission()
	for s in _m.squad.members:
		s.set_meta("protect_until", 1e12)
	var rt: LsRuntime = _m.get("runtime")
	if rt:
		rt.auto_skip = true
		for i in 120:
			await get_tree().process_frame
			if rt.in_cutscene:
				rt.end_cutscene()
	if String(Game.cli.get("phase", "all")) != "licht":
		await _grates()
	_lights(rt)
	_finish()


func _grates() -> void:
	var lvl: OrigLevel = _m.get("orig")
	check(lvl != null, "OrigLevel vorhanden")
	if lvl == null:
		return
	check(int(lvl.stats.get("grates", 0)) > 0, "Gitterflächen erkannt", "grates=%s" % lvl.stats.get("grates", 0))
	var grates: Array = []
	for mi in lvl.root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("klz_grate"):
			grates.append(mi)
	var bm: Array = grates.filter(func(g): return String(g.get_path()).contains("m_bmmriz"))
	var names := {}
	for g in grates:
		var k := String(g.get_parent().name).rstrip("0123456789_")
		names[k] = int(names.get(k, 0)) + 1
	print("GITTER: ", names)
	# alle waagrechten Alpha-Gitterplatten der m_bmmriz-Stege müssen fest sein (senkrechte = Geländer, egal)
	var flat_all := 0
	var flat_ok := 0
	for mi in lvl.root.find_children("m_bmriz01*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.size.y <= 0.35:
			flat_all += 1
			if mi.has_meta("klz_grate"):
				flat_ok += 1
	print("GITTERPLATTEN waagrecht: %d, fest: %d, m_bmriz01 gesamt: %d" % [flat_all, flat_ok,
		lvl.root.find_children("m_bmriz01*", "MeshInstance3D", true, false).size()])
	check(flat_all > 0 and flat_ok == flat_all, "ARCTIC2 waagrechte m_bmmriz-Gitterplatten fest", "%d/%d" % [flat_ok, flat_all])
	# Gitterraum p1s17: Gitterplatten ohne Klz-Link über dem Becken
	var room := ["P1MRIZ06", "P1BAZ49", "P1BAZ50", "P1BAZ52", "P1BAZ130"]
	var room_ok := 0
	for nm in room:
		var nn := lvl.root.find_child(nm, true, false)
		var ms: Array = [nn] if nn is MeshInstance3D else (nn.find_children("*", "MeshInstance3D", true, false) if nn else [])
		for mi in ms:
			for c in mi.get_children():
				if c is StaticBody3D:
					room_ok += 1
					break
			break
	check(room_ok == room.size(), "Gitterraum p1s17: alle Gitterplatten mit Kollision", "%d/%d" % [room_ok, room.size()])
	var p49 := lvl.root.find_child("P1BAZ49", true, false)
	if p49 is MeshInstance3D:
		bm.push_front(p49)
	var space := _m.get_world_3d().direct_space_state
	var hit_ok := 0
	var with_body := 0
	for g in bm:
		for c in g.get_children():
			if c is StaticBody3D:
				with_body += 1
				break
		var b: AABB = g.global_transform * g.get_aabb()
		if b.size.y > 0.35:
			hit_ok += 1          # senkrechtes Gitter: Strahl von oben nicht aussagekräftig
			continue
		var c3 := b.get_center()
		var q := PhysicsRayQueryParameters3D.create(Vector3(c3.x, b.end.y + 0.6, c3.z), Vector3(c3.x, b.position.y - 0.6, c3.z), 1)
		var r := space.intersect_ray(q)
		if not r.is_empty() and r.position.y >= b.position.y - 0.1:
			hit_ok += 1
	check(with_body == bm.size(), "jedes Gitter hat einen Kollisionskörper", "%d/%d" % [with_body, bm.size()])
	check(hit_ok >= bm.size() * 0.8, "Strahl von oben trifft das Gitter", "%d/%d" % [hit_ok, bm.size()])
	# Soldat auf das erste waagrechte Gitter stellen
	var me := _m.squad.leader()
	var target: MeshInstance3D = null
	for g in bm:
		var b: AABB = g.global_transform * g.get_aabb()
		if b.size.y <= 0.35 and b.size.x >= 0.6 and b.size.z >= 0.6:
			target = g
			break
	check(target != null, "waagrechtes Gitter gefunden")
	if target == null:
		return
	var tb: AABB = target.global_transform * target.get_aabb()
	var top := tb.end.y
	me.global_position = Vector3(tb.get_center().x, top + 0.3, tb.get_center().z)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	var dy := me.global_position.y - top
	check(dy > -0.25 and me.is_on_floor(), "Soldat steht auf dem Gitter",
		"%s Fuß %.2f, Gitteroberkante %.2f, Boden %s" % [target.get_parent().name, me.global_position.y, top, me.is_on_floor()])
	# kurzer Lauf über das Gitter
	var dir := Vector3(1, 0, 0) if tb.size.x >= tb.size.z else Vector3(0, 0, 1)
	me.move_input = dir
	await get_tree().create_timer(0.6).timeout
	me.move_input = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	check(me.global_position.y > top - 2.0, "nach dem Laufen nicht durchgefallen", "y=%.2f" % me.global_position.y)


func _lights(rt: LsRuntime) -> void:
	check(rt != null and rt.extras != null, "OrigExtras vorhanden")
	if rt == null or rt.extras == null:
		return
	var ex: OrigExtras = rt.extras
	var ls: Dictionary = ex.lamp_stats
	print("LAMPEN: ", ls, " stats=", ex.stats)
	check(int(ls.baked) > 0, "gebackene Lampenlichter als echte Lichter", str(ls))
	check(int(ls.baked) <= OrigExtras.BAKED_MAX, "Obergrenze gebackener Lichter")
	check(int(ls.shadowed) <= OrigExtras.SHADOW_MAX, "Schatten sparsam", str(ls.shadowed))
	check(OrigExtras.lamp_energy(0.1) > 0.1 * OrigExtras.POINT_ENERGY * 3.0, "schwache Originallampe deutlich heller")
	var n := 0
	var bad := 0
	for l in _m.dynamic_root.find_children("baked_*", "Light3D", true, false):
		n += 1
		var r: float = l.omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
		if r > OrigExtras.BAKED_RANGE_MAX + 0.01 or l.shadow_enabled and not (l is SpotLight3D):
			bad += 1
	check(n == int(ls.baked) and bad == 0, "Lichtknoten mit begrenzter Reichweite", "%d Knoten, %d fehlerhaft" % [n, bad])
