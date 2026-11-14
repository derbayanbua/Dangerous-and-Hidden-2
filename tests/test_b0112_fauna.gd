extends "res://tests/test_gameplay.gd"
## B-053 / 0.11.2 Kosmetische Originalakteure (src/orig/orig_fauna.gd): Uhren (Typ 27), Vogelschwärme (Typ 29),
## Fische (Typ 32). Prüft, was die jeweilige Mission enthält; Luftangriff (Typ 36) prüft test_af_air.
##   tools\godot.cmd --headless -- --mission=af5_whiskey_bar --autoplay=test_b0112_fauna     (Uhren)
##   tools\godot.cmd --headless -- --mission=al1_waldgeister --autoplay=test_b0112_fauna     (Vögel)
##   tools\godot.cmd --headless -- --mission=nw1_dampfleitung --autoplay=test_b0112_fauna    (Fische)
##   tools\godot.cmd --headless -- --mission=no1_leuchtturm --autoplay=test_b0112_fauna      (Vögel + Fische)
## Fenster: --shots=1 → test_output/b0112_<mission>_<typ>.png

const EXPECT := {"africa5": [7, 0, 0], "alps1": [0, 9, 0], "norway": [0, 0, 16], "normandy": [0, 5, 19]}


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.get("fauna") != null, "Originalmission mit Fauna geladen")
	if m == null or m.get("fauna") == null:
		_finish()
		return
	for mem in m.squad.members:
		if is_instance_valid(mem):
			mem.max_health = 100000.0
			mem.health = mem.max_health
	var fa = m.fauna
	var key := String(m.orig.mission_dir).get_file().to_lower()
	print("FAUNA ", key, " ", fa.stats)
	if EXPECT.has(key):
		var ex: Array = EXPECT[key]
		check(fa.clocks.size() == ex[0], "%s: %d Uhren" % [key, ex[0]], str(fa.clocks.size()))
		check(fa.fowls.size() == ex[1], "%s: %d Vogelschwärme" % [key, ex[1]], str(fa.fowls.size()))
		check(fa.fishes.size() == ex[2], "%s: %d Fischschwärme" % [key, ex[2]], str(fa.fishes.size()))
	check((fa.stats.missing as Array).is_empty(), "alle Fauna-Modelle/Uhren vorhanden", str(fa.stats.missing))
	var shots := String(Game.cli.get("shots", "0")) == "1"

	# --- Uhren ---
	if not fa.clocks.is_empty():
		var c = fa.clocks[0]
		check(c.hands.has("hour") and c.hands.has("min") and c.hands.has("sec"), "Uhr hat Zeiger hour/min/sec", str(c.hands.keys()))
		var before := {}
		for h in c.hands:
			before[h] = (c.hands[h][0] as Node3D).basis
		var j0: int = c.jumps
		c.step(0.4)
		var still := true
		for h in c.hands:
			still = still and (c.hands[h][0] as Node3D).basis.is_equal_approx(before[h])
		check(still or c.jumps > j0, "kein Zeigersprung innerhalb einer Sekunde")
		c.step(1.0)
		check(c.jumps > j0, "Sprung nach > 1 s", "jumps %d" % c.jumps)
		var sec_moved := not (c.hands["sec"][0] as Node3D).basis.is_equal_approx(before["sec"]) if c.hands.has("sec") else false
		check(sec_moved, "Sekundenzeiger bewegt sich")
		c.step(600.0)
		var min_moved := not (c.hands["min"][0] as Node3D).basis.is_equal_approx(before["min"])
		check(min_moved, "Minutenzeiger nach 10 min gedreht")
		check(absf(c.angle("min") + c.elapsed * 0.0017453294) < 1e-4, "Minutenrate 0,1°/s [B]")
		var st: Dictionary = fa.save_state()
		var el: float = c.elapsed
		c.elapsed = 0.0
		fa.load_state(st)
		check(absf(c.elapsed - el) < 1e-3, "Uhr-Laufzeit im Spielstand")
		if shots:
			await _shot_at(c.root, "clock", key, 0.6)

	# --- Vögel ---
	if not fa.fowls.is_empty():
		var f = fa.fowls[0]
		fa.cam_override = f.global_position + Vector3(500, 500, 0)
		var lead = m.squad.leader()
		# Trupp weit weg, damit nur der Test auslöst
		var all_far := true
		for s in get_tree().get_nodes_in_group("soldiers"):
			if s is Node3D and f.near((s as Node3D).global_position):
				all_far = false
		if all_far:
			await _wait(1.3)
			check(not f.flown, "Vogelschwarm bleibt ohne Annäherung sitzen")
		if shots and f.mode == 2:
			await _shot_at(f, "birds_sitting", key, f.radius * 3.0 + 3.0)
		var noises: Array = []
		var cb := func(p: Vector3, _r: float, src: Node, _t: int, kind: StringName) -> void:
			if kind == &"birds":
				noises.append([p, src])
		Events.noise_emitted.connect(cb)
		fa.cam_override = f.global_position + Vector3(0.5, 0.3, 0)
		await _wait(1.3)
		Events.noise_emitted.disconnect(cb)
		check(noises.size() == 1 and noises[0][1] == f and (noises[0][0] as Vector3).distance_to(f.global_position) < 0.01,
			"KI-Laermmeldung beim Auffliegen (Art 0xB, Schwarmort) [B]", str(noises.size()))
		check(f.noise_sent, "Laermmeldung offline gesendet")
		check(f.sound_played, "Vogelklang Kat. 11 gespielt [E]")
		check(f.flown, "Vogelschwarm fliegt bei Annäherung auf (Prüfung 1×/s)")
		check(f.birds.size() > 0, "Vögel vorhanden (Modus %d)" % f.mode, str(f.birds.size()))
		if f.birds.size() > 0:
			var b: Node3D = f.birds[0][0]
			var y0 := b.global_position.y
			await _wait(1.0)
			check(b.global_position.y > y0 + 1.0, "Vogel steigt auf", "%.2f -> %.2f" % [y0, b.global_position.y])
			var v: Vector3 = f.birds[0][1]
			check(v.length() >= 4.9 and v.length() <= 7.1, "Vogeltempo 5–7 m/s [B]", "%.2f" % v.length())
			if shots:
				fa.cam_override = null
				await _shot_at(b, "birds_flying", key, 6.0)
		# Schuss scheucht einen weiteren Schwarm auf
		if fa.fowls.size() > 1:
			var f2 = fa.fowls[1]
			fa.cam_override = f2.global_position + Vector3(900, 900, 0)
			Events.noise_emitted.emit(f2.global_position, 60.0, lead, 1, &"shot")
			check(f2.flown, "Schuss in Auslösedistanz scheucht auf [P]")
		# Menschenfilter +0x19C == 1 [B]: Gegner scheuchen nicht auf, Spielertrupp schon
		if fa.fowls.size() > 2:
			var f3 = fa.fowls[2]
			var foe: Node3D = null
			for s in get_tree().get_nodes_in_group("soldiers"):
				if s is Node3D and s.get("alive") != false and WeaponDB.orig_side(s) == 2:
					foe = s
					break
			fa.cam_override = f3.global_position + Vector3(900, 900, 0)
			if foe and not f3.flown:
				f3.global_position = foe.global_position + Vector3(0, 0.5, 0)
				var lead_far: bool = not f3.near(lead.global_position)
				await _wait(1.3)
				if lead_far:
					check(not f3.flown, "Gegner in Auslösedistanz scheucht nicht auf (Seite 2) [B]")
			if not f3.flown:
				f3.global_position = lead.global_position + Vector3(0, 0.5, 0)
				await _wait(1.3)
				check(f3.flown, "Spielertrupp (Seite 1) scheucht auf [B]")
		fa.cam_override = null

	# --- Fische ---
	if not fa.fishes.is_empty():
		var s = fa.fishes[0]
		fa.cam_override = s.global_position + Vector3(s.radius + 40.0, 0, 0)
		await _wait(0.3)
		check(not s.active, "Fische inaktiv außerhalb Radius + 15 m")
		var st0: int = s.steps
		await _wait(0.5)
		check(s.steps == st0, "inaktive Fische werden nicht gerechnet")
		fa.cam_override = s.global_position + Vector3(s.radius + 10.0, 0, 0)
		await _wait(0.3)
		check(s.active, "Fische aktiv innerhalb Radius + 15 m")
		check(s.mm != null and s.mm.visible, "Fisch-MultiMesh sichtbar", str(s.mm))
		var c0: Vector3 = s.center
		await _wait(2.0)
		check(s.center.distance_to(c0) > 0.05, "Schwarm bewegt sich", "%.3f" % s.center.distance_to(c0))
		check(s.speed <= s.max_speed + 1e-4, "Tempo ≤ Höchstgeschwindigkeit [B]", "%.2f" % s.speed)
		check(s.center.length() <= s.radius + 0.01, "Schwarm bleibt im Radius", "%.2f" % s.center.length())
		# Weltkollision [E]: Wand direkt vor der Schwarmmitte -> Richtung wird gespiegelt
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(20, 20, 0.2)
		cs.shape = bx
		wall.add_child(cs)
		wall.collision_layer = 1
		m.add_child(wall)
		var gdir: Vector3 = (s.global_transform.basis * s.dir).normalized()
		var gc: Vector3 = s.to_global(s.center)
		wall.global_transform = Transform3D(Basis.looking_at(gdir, Vector3.UP if absf(gdir.y) < 0.99 else Vector3.RIGHT),
			gc + gdir * 0.6)
		s.state = 0
		s.speed = maxf(s.speed, s.max_speed * 0.5)
		var wb0: int = s.world_bounces
		await _wait(0.5)
		check(s.world_bounces > wb0, "Fischschwarm prallt an Weltkollision ab [E]", "%d" % s.world_bounces)
		check((s.to_global(s.center) - gc).dot(gdir) < 0.6, "Schwarm durchquert die Wand nicht")
		wall.queue_free()
		if shots:
			fa.cam_override = null
			await _shot_at(s, "fish", key, 4.0)
		fa.cam_override = null
	_finish()


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot_at(target: Node3D, tag: String, key: String, dist: float) -> void:
	var cam := Camera3D.new()
	target.get_tree().current_scene.add_child(cam)
	var p := target.global_position
	cam.global_position = p + Vector3(dist, dist * 0.35, dist * 0.2)
	cam.look_at(p, Vector3.UP)
	cam.current = true
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	img.save_png("res://test_output/b0112_%s_%s.png" % [key, tag])
	cam.queue_free()
