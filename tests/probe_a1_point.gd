extends "res://tests/test_gameplay.gd"
## Diagnose: was liegt über/unter einem Punkt (Ebene 1)?  --mission=a1_blizzard --autoplay=probe_a1_point --p=x,y,z


func _run() -> void:
	for i in 2400:
		if mission() and mission().orig:
			break
		await get_tree().process_frame
	await frames(5)
	var c := String(Game.cli.get("p", "9.6,-2.1,-132")).split(",")
	var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
	var space := get_tree().root.get_world_3d().direct_space_state
	for dir in [Vector3.UP, Vector3.DOWN]:
		var from := p
		for k in 6:
			var q := PhysicsRayQueryParameters3D.create(from, p + dir * 30.0, 1)
			q.hit_back_faces = true
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			var n: Node = h.collider
			print("PROBE %s %.2f m: %s/%s/%s n=%s" % ["hoch" if dir == Vector3.UP else "runter", p.distance_to(h.position),
				n.get_parent().get_parent().name, n.get_parent().name, n.name, h.normal])
			from = h.position + dir * 0.01
	check(true, "Probe")
	_finish()
