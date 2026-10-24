extends "res://tests/test_gameplay.gd"
## System-Agent A: Bodenprofil der Außentreppe ALPS2 al2_agx_01 → al2_agx_02 (Senkrechtstrahlen alle 0,2 m, Kollider).
##   --mission=al2_makler --autoplay=probe_al2_stair_profile


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	var rt := m.runtime
	rt.auto_skip = true
	await seconds(1.0)
	var a: Vector3 = rt.find_frame("al2_agx_01").global_position
	var b: Vector3 = rt.find_frame("al2_agx_02").global_position
	var space := m.get_world_3d().direct_space_state
	var n := int(a.distance_to(b) / 0.2)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var hits := []
		var top := p + Vector3.UP * 6.0
		var excl: Array[RID] = []
		for k in 4:
			var q := PhysicsRayQueryParameters3D.create(top, p + Vector3.DOWN * 4.0, 1 | 16)
			q.exclude = excl
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			var c: Object = h.collider
			hits.append("%.2f %s/%s" % [h.position.y, (c as Node).get_parent().name if c is Node else "?", (c as Node).name if c is Node else "?"])
			excl.append(h.rid)
		print("PROFIL z=%.2f x=%.2f : %s" % [p.z, p.x, " | ".join(hits)])
	# Kapselprobe an der Hängestelle (probe_stair.log: Agentin bleibt bei (-14.97, 5.00, -11.40) stehen)
	var ag: Node3D = rt.find_frame("AL2_agent")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	for dz in [0.0, 0.3, 0.6, 0.9]:
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = cap
		qp.collision_mask = 0xFFFFFFFF & ~2
		qp.transform = Transform3D(Basis(), Vector3(-14.97 - 0.03 * dz, 5.0 + 0.1 * dz / 0.19 + 0.95, -11.40 + dz))
		var res := space.intersect_shape(qp, 16)
		var names := []
		for r in res:
			var co: Node = r.collider
			names.append("%s/%s L%d" % [co.get_parent().name, co.name, (co as CollisionObject3D).collision_layer if co is CollisionObject3D else -1])
		print("KAPSEL dz=%.1f : %s" % [dz, ", ".join(names)])
	if ag is CharacterBody3D:
		print("AGENT floor_max_angle=%.1f° max_slides=%d safe_margin=%.3f" % [rad_to_deg((ag as CharacterBody3D).floor_max_angle), (ag as CharacterBody3D).max_slides, (ag as CharacterBody3D).safe_margin])
	_finish()
