extends "res://tests/test_gameplay.gd"
## System-Agent A: zerstörbare Skriptobjekte (TUTORIAL-Zielscheiben).  --mission=training --autoplay=probe_breakable


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	var rt := m.runtime
	rt.auto_skip = true
	await seconds(1.0)
	var t: Node3D = rt.find_frame("m_tut_panak_1")
	check(t != null, "Zielscheibe m_tut_panak_1 vorhanden")
	var br = t.get_meta("script_breakable") if t and t.has_meta("script_breakable") else null
	check(br != null and br.hp > 0.0, "zerstörbar über dmodels.json (HP)", str(br.hp if br else -1))
	var area_ok := false
	if t:
		for c in t.find_children("*", "Area3D", true, false):
			if c.has_meta("hit_proxy") and c.get_meta("hit_proxy") == br:
				area_ok = true
	check(area_ok, "Trefferfläche mit hit_proxy")
	# echter Schuss vom Anführer auf die Scheibe
	var lead: Soldier = m.squad.leader()
	var c: Vector3 = OrigInteractive.world_aabb(t).get_center()
	for a3 in t.find_children("*", "Area3D", true, false):
		if a3.get_meta("hit_proxy", null) == br:
			c = a3.global_position          # Mitte der Trefferfläche
	lead.global_position = c + Vector3(0, -0.6, 6.0)
	await seconds(0.3)
	var w = lead.current_weapon()
	var from := c + Vector3(0, 0, 3.0)
	if w:
		var ex: Array[RID] = []
		Ballistics.fire(lead, from, (c - from).normalized(), w.data, ex, lead.team)
	print("AABB ", OrigInteractive.world_aabb(t), " c=", c, " from=", from)
	for a2 in t.find_children("*", "Area3D", true, false):
		print("AREA ", a2.name, " pos=", a2.global_position, " layer=", a2.collision_layer, " in_tree=", a2.is_inside_tree(),
			" shape=", (a2.get_child(0) as CollisionShape3D).shape.size if a2.get_child_count() > 0 else "-", " sichtbar=", t.is_visible_in_tree())
	var rq := PhysicsRayQueryParameters3D.create(from, c + (c - from).normalized() * 2.0, Ballistics.MASK)
	rq.collide_with_areas = true
	var rh := m.get_world_3d().direct_space_state.intersect_ray(rq)
	print("STRAHL ", rh.get("collider"), " ", (rh.get("collider") as Node).get_parent().name if rh.get("collider") else "", " ", rh.get("position"))
	for k in 5:
		for i in 30:
			await get_tree().process_frame
		print("SCHUSS %d hp=%.1f zerstört=%s" % [k, br.hp, br.destroyed])
		if br.destroyed:
			break
		if w:
			var ex2: Array[RID] = []
			Ballistics.fire(lead, from, (c - from).normalized(), w.data, ex2, lead.team)
	check(br != null and br.destroyed, "Geschoss zerstört die Zielscheibe → OnDeath", "Waffe %s" % (w.data.id if w else "-"))
	check(t != null and int(t.get_meta("actor_state", 1)) == 0, "Zustand 0 nach Zerstörung")
	_finish()
