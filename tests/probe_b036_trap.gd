extends "res://tests/test_gameplay.gd"
## B-036 Sonde: Kommt ein Soldat von einer Stelle mit Spielereingaben wieder weg? (Fallen-/Blockerprüfung)
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=probe_b036_trap --at=-127,16.7,142
## Setzt den aktiven Soldaten (Sonde, nicht Löser) an die Stelle, meldet den Boden-Collider darunter, das Navmesh und
## versucht 16 Laufrichtungen je 4 s mit Leertaste. Ausgabe TRAP-Zeilen.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader() and mission().nav_ready:
			break
		await get_tree().process_frame
	var m = mission()
	if m.get("runtime") and m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	await seconds(2.0)
	# --frames=<Teilname>: Frames mit Lage/AABB und Kollisionskörpern auflisten (z. B. versteckte Treppenrampen)
	if Game.cli.has("frames"):
		var pat := String(Game.cli["frames"]).to_lower()
		for n in m.find_children("*", "Node3D", true, false):
			if not String(n.name).to_lower().contains(pat):
				continue
			var bodies := n.find_children("*", "CollisionObject3D", true, false)
			var aabb := AABB()
			for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
				var b: AABB = mi.global_transform * mi.get_aabb()
				aabb = b if aabb.size == Vector3.ZERO else aabb.merge(b)
			print("TRAP Frame %s pos %s AABB %s..%s Körper %d sichtbar %s" % [n.name, n.global_position,
				aabb.position, aabb.end, bodies.size(), n.is_visible_in_tree()])
	# --profile=x,y,z,dx,dz,n: Bodenhöhen in n Schritten (dx, dz) ab x,z (Strahl von y+2 nach unten), mit Collider
	if Game.cli.has("profile"):
		var pr := String(Game.cli["profile"]).split(",")
		var sp2: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
		for i in int(pr[5]):
			var px := float(pr[0]) + float(pr[3]) * i
			var pz := float(pr[2]) + float(pr[4]) * i
			var rq := PhysicsRayQueryParameters3D.create(Vector3(px, float(pr[1]) + 1.2, pz), Vector3(px, float(pr[1]) - 3.0, pz))
			var h := sp2.intersect_ray(rq)
			print("TRAP Profil (%.2f, %.2f): %s" % [px, pz, ("y %.3f %s n %s" % [h.position.y, (h.collider as Node).get_parent().name, h.normal]) if h else "-"])
	# --rays=x,y,z: waagerechte Strahlen in 16 Richtungen auf Knie-/Brust-/Kopfhöhe mit Treffer-Collider
	if Game.cli.has("rays"):
		var r := String(Game.cli["rays"]).split(",")
		var o := Vector3(float(r[0]), float(r[1]), float(r[2]))
		var sp: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
		for i in 16:
			var yaw := float(i) * TAU / 16.0
			var dir := Vector3(-sin(yaw), 0, -cos(yaw))
			var line := "TRAP Ray %3d°:" % int(rad_to_deg(yaw))
			for hgt in [0.3, 1.0, 1.7]:
				var rq := PhysicsRayQueryParameters3D.create(o + Vector3(0, hgt, 0), o + Vector3(0, hgt, 0) + dir * 4.0)
				rq.collision_mask = 1 | 16
				var h := sp.intersect_ray(rq)
				line += "  h%.1f %s" % [hgt, ("%.2f m %s" % [o.distance_to(h.position) , (h.collider as Node).get_parent().name]) if h else "frei"]
			print(line)
	# --walk=x,y,z|x,y,z|…: ab --at nacheinander auf die Punkte zulaufen (wie Löser _walk_ramp), Lage alle 0,25 s
	if Game.cli.has("walk"):
		var a0 := String(Game.cli.get("at", "0,0,0")).split(",")
		var sw: Soldier = m.squad.leader()
		await seconds(float(Game.cli.get("walkwait", "25")))   # Spielereingabe greift erst nach dem Missionsstart
		sw.global_position = Vector3(float(a0[0]), float(a0[1]), float(a0[2]))
		await seconds(1.0)
		for ptxt in String(Game.cli["walk"]).split("/"):
			var pp := ptxt.split(",")
			var goal := Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			var tt := 0.0
			while tt < 6.0:
				var d := goal - sw.global_position
				d.y = 0.0
				if d.length() < 0.35:
					break
				sw.look_yaw = atan2(-d.x, -d.z)
				Input.action_press("move_forward")
				if Game.cli.get("walkjump", "0") == "1" and int(tt * 10) % 10 == 0:
					sw.jump_or_climb()
				await get_tree().physics_frame
				tt += get_physics_process_delta_time()
				if fmod(tt, 0.25) < get_physics_process_delta_time():
					print("TRAP Walk → %s: bei %s v %s Boden %s" % [goal, sw.global_position, sw.velocity, sw.is_on_floor()])
			Input.action_release("move_forward")
			print("TRAP Walk Ende Ziel %s bei %s" % [goal, sw.global_position])
	var a := String(Game.cli.get("at", "-127,16.7,142")).split(",")
	var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var s: Soldier = m.squad.leader()
	var space := s.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 2, 0), at + Vector3(0, -30, 0))
	q.exclude = [s.get_rid()]
	var hits := []
	for k in 6:
		var h := space.intersect_ray(q)
		if h.is_empty():
			break
		var c: Object = h["collider"]
		hits.append("%s y=%.2f (%s)" % [c.get_path() if c is Node else str(c), h["position"].y,
			c.get_class()])
		var ex: Array[RID] = q.exclude
		ex.append(h["rid"])
		q.exclude = ex
	print("TRAP Boden unter ", at, ": ", " | ".join(hits))
	# Hindernisse rundum in Brusthöhe (1,2 m) bis 2,5 m und Benutzbares in der Nähe
	for i in 8:
		var yaw0 := TAU * i / 8.0
		var dir := Basis(Vector3.UP, yaw0) * Vector3(0, 0, -1)
		var rq := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.2, 0), at + Vector3(0, 1.2, 0) + dir * 2.5)
		rq.exclude = [s.get_rid()]
		var rh := space.intersect_ray(rq)
		print("TRAP Strahl %3d°: %s" % [int(rad_to_deg(yaw0)), "frei" if rh.is_empty() else "%s in %.2f m (Ebene %d)" % [
			(rh["collider"] as Node).get_path() if rh["collider"] is Node else str(rh["collider"]),
			(rh["position"] as Vector3).distance_to(at + Vector3(0, 1.2, 0)),
			(rh["collider"] as CollisionObject3D).collision_layer if rh["collider"] is CollisionObject3D else -1]])
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Node3D).global_position.distance_to(at) < 6.0:
			print("TRAP Benutzbar %s (%s) bei %s, offen=%s, gesperrt=%s, can_interact=%s, enabled=%s, floor_y=%s, Soldat y=%.2f" % [
				n.name, n.get_class(), (n as Node3D).global_position, n.get("is_open"), n.get("locked"),
				(n as Interactable).can_interact(s), n.get("enabled"), n.get("floor_y"), s.global_position.y])
	var map: RID = s.get_world_3d().navigation_map
	print("TRAP Navmesh nächster Punkt: ", NavigationServer3D.map_get_closest_point(map, at))
	var escaped := 0
	for i in 16:
		s.global_position = at
		s.velocity = Vector3.ZERO
		await frames(3)
		var yaw := TAU * i / 16.0
		s.look_yaw = yaw
		var t := 0.0
		var best := 0.0
		while t < 4.0:
			s.look_yaw = yaw
			Input.action_press("move_forward")      # wie ein Spieler (PlayerController setzt move_input)
			if int(t * 10) % 10 == 0:
				s.jump_or_climb()
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			best = maxf(best, Vector2(s.global_position.x - at.x, s.global_position.z - at.z).length())
		Input.action_release("move_forward")
		var ok := best > 5.0 or s.global_position.y < at.y - 2.5
		if ok:
			escaped += 1
		print("TRAP Richtung %3d°: Ende %s, weitester Abstand %.1f m, %s" % [int(rad_to_deg(yaw)), s.global_position,
			best, "frei" if ok else "gefangen"])
	print("TRAP Ergebnis: %d/16 Richtungen führen hinaus" % escaped)
	check(true, "Sonde gelaufen")
	_finish()
