extends "res://tests/test_gameplay.gd"
## System-Agent A (Skript-VM): Skriptanimationen (*.i3d, ls_anim.gd) und Einsatzgebiet-Grenze (mission_area.gd).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_script_systems


var _msgs: Array = []


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.runtime != null, "Original-Mission mit Skriptlaufzeit", Game.current_mission_id)
	if m == null:
		_finish()
		return
	var rt := m.runtime
	rt.auto_skip = true
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(0.5)
	Events.message.connect(func(t, _s): _msgs.append(String(t)))

	# --- Skriptanimationen ---
	var lead: Soldier = m.squad.leader()
	var dup: Node3D = rt._duplicate_human(lead, "_TEST_dup")
	check(dup != null, "CSC_DuplicateHuman erzeugt Darsteller")
	var sks := dup.find_children("*", "Skeleton3D", true, false) if dup else []
	check(not sks.is_empty(), "Darsteller hat Skelett", str(sks.size()))
	if dup and not sks.is_empty():
		var sk := sks[0] as Skeleton3D
		var bi := sk.find_bone("c")
		var before := sk.get_bone_pose_rotation(bi) if bi >= 0 else Quaternion()
		var ok: bool = rt.anim.set_animation(dup, "%%sasSED1.i3d", 1)
		check(ok, "FRM_SetAnimation lädt %%sasSED1.i3d (MODELS\\%sasSED1.5DS)")
		await seconds(1.0)
		var after := sk.get_bone_pose_rotation(bi) if bi >= 0 else Quaternion()
		var d: Dictionary = rt.anim.load_anim("%sasSED1")
		var ckey = null
		for o in d.get("objects", []):
			if String(o["name"]) == "c":
				ckey = rt.anim._sample(o["rot"], float(rt.anim._tracks[0]["t"]) * 25.0, 4)
		check(bi >= 0 and not before.is_equal_approx(after), "Knochen c bewegt sich", "%s -> %s" % [before, after])
		check(ckey != null and (ckey as Quaternion).angle_to(after) < 0.05, "Knochenlage = 5DS-Schlüssel (25 Bilder/s)",
			"Abweichung %.3f rad" % ((ckey as Quaternion).angle_to(after) if ckey != null else -1.0))
		rt.anim.set_animation(dup, "", 1)
		check(not rt.anim.is_playing(dup), "leerer Name leert den Kanal")
	# HUMAN_SetAnim an einer lebenden Wache (Spielanimation ruht, Schleife)
	var guard: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and Vector2(e.velocity.x, e.velocity.z).length() < 0.1:
			guard = e
			break
	if guard:
		var gb := guard.get_node_or_null("EnemyBrain")
		if gb:
			gb.suspended = true
		var gsk := guard.find_children("*", "Skeleton3D", true, false)
		var ok2: bool = rt.anim.set_animation(guard, "%%lenin", 100, true, true)
		check(ok2, "HUMAN_SetAnim lädt %%lenin")
		await seconds(1.2)
		var tr2 = null
		for t in rt.anim._tracks:
			if t["target"] == guard:
				tr2 = t
		check(tr2 != null, "HUMAN_SetAnim läuft an stehender Wache", guard.name)
		if tr2 and not gsk.is_empty():
			var sk2 := gsk[0] as Skeleton3D
			var bi2 := sk2.find_bone("c")
			var want = null
			for o in tr2["data"]["objects"]:
				if String(o["name"]) == "c":
					want = rt.anim._sample(o["rot"], float(tr2["t"]) * 25.0, 4)
			var got := sk2.get_bone_pose_rotation(bi2)
			check(want != null and (want as Quaternion).angle_to(got) < 0.1, "Wache: Knochenlage = 5DS (Spielanimation ruht)",
				"Abweichung %.3f" % ((want as Quaternion).angle_to(got) if want != null else -1.0))
		rt.anim.set_animation(guard, "", 100)
		if gb:
			gb.suspended = false
	# Objektanimation (Unterframe nach Name) und Kameraanimation (Weltlage)
	var cam := Node3D.new()
	cam.name = "TestCam"
	m.add_child(cam)
	check(rt.anim.set_camera_animation(cam, "#CamAf2a1"), "CSC_SetCameraAnimation lädt #CamAf2a1")
	var cd: Dictionary = rt.anim.load_anim("#CamAf2a1")
	var o0: Dictionary = cd["objects"][0]
	var p0: Vector3 = rt.anim._sample(o0["pos"], 0.0, 3)
	check(cam.global_position.distance_to(p0) < 0.01, "Kameraframe in Weltlage des Animationsobjekts", str(cam.global_position))
	var t_start := Time.get_ticks_msec()
	for i in 3000:
		await get_tree().process_frame
		if not rt.anim.is_playing(cam):
			break
	print("Kameraanimation Echtzeit %.2f s" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	await seconds(0.3)
	var pl: Vector3 = rt.anim._sample(o0["pos"], float(cd["last_frame"]), 3)
	check(cam.global_position.distance_to(pl) < 0.05, "Kamera nach 190 Bildern (7,6 s) am Ende und hält", str(cam.global_position))
	var box := Node3D.new()
	box.name = "TestJeep"
	m.add_child(box)
	var body := Node3D.new()
	body.name = "BODY"
	box.add_child(body)
	rt.anim.set_animation(box, "#Af2Jeep.I3D", 1)
	await seconds(0.5)
	check(body.position.length() > 100.0, "Unterframe BODY folgt #Af2Jeep (lokale Lage)", str(body.position))
	rt.anim.reset_animation(box, 1)
	check(body.position.length() < 0.01, "FRM_ResetAnimation stellt die Ruhelage her", str(body.position))

	# --- Einsatzgebiet-Grenze ---
	var ar = rt.area
	check(ar != null and ar.faces.size() > 0, "Grenzdreiecke geladen (area.json)", str(ar.faces.size() if ar else 0))
	if ar:
		check(ar.team_flags() == 0, "Start im Einsatzgebiet (keine Grenzbits)", "0x%x" % ar.team_flags())
		var warn = null
		var out = null
		for fc in ar.faces:
			if int(fc[0]) == ar.WARN and warn == null:
				warn = fc
			if int(fc[0]) & ar.OUT and out == null:
				out = fc
		check(warn != null and out != null, "Warn- und Außenzone vorhanden")
		for s in m.squad.members:
			if s != lead:
				s.set_physics_process(false)
		if warn:
			var c: Vector3 = (warn[1] + warn[2] + warn[3]) / 3.0
			check(ar.flags_at(c + Vector3.UP * 0.05) == ar.WARN, "flags_at liefert 0x4000 im Warndreieck")
			lead.global_position = c + Vector3.UP * 0.1
			lead.velocity = Vector3.ZERO
			_msgs.clear()
			await seconds(1.0)
			check(int(ar.flags) & ar.WARN, "Team in Warnzone erkannt", "0x%x" % int(ar.flags))
			check(_msgs.has(rt.text(7407)), "Meldung T7407", str(_msgs))
			check(not m.finished, "Warnzone beendet die Mission nicht")
		if out:
			var t7408: String = rt.text(7408)
			var c2: Vector3 = (out[1] + out[2] + out[3]) / 3.0
			lead.global_position = c2 + Vector3.UP * 0.1
			lead.velocity = Vector3.ZERO
			for i in 40:
				await seconds(0.1)
				if not is_instance_valid(m) or m.finished:
					break
			var r: Dictionary = Game.last_result
			check(not bool(r.get("success", true)) and String(r.get("reason", "")) == t7408,
				"Außenzone → Mission gescheitert mit T7408", str(r.get("reason", "?")))
	_finish()
