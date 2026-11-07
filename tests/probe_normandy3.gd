extends Node
## 0.10.1 Sonde Normandy 3 (Fenster): Wasser, Tag/Nacht, MP-Sichtweite, Rauch-Bildrate vorher/nachher in EINEM Lauf.
##   tools\godot.cmd -- --autoplay=probe_normandy3 [--phase=all|shots|perf] [--q=2] --resolution 1280x720
## Hostet mp_normandy3_mp lokal (ohne Bots), Spieler unverwundbar. Bilder test_output/normandy3/*.png,
## Messwerte test_output/normandy3/probe.txt (PROBE-Zeilen auch auf stdout).
## Rauchmessung: Kamera fest, Grundlinie 4 s, dann je Variante (alt = ExplosionFx.legacy, neu) 8 Explosionen in 2 s
## (6 Granaten r 5 m, 2 Fahrzeug r 8 m) in 18–35 m, Bildrate 12 s ab der ersten Explosion; dazwischen Rauch abklingen.

const ExplosionFx := preload("res://src/combat/explosion_fx.gd")
const OUT := "res://test_output/normandy3/"
var lines: PackedStringArray = []
var cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		_log("FEHLER Zeitlimit")
		_finish(1))
	_run.call_deferred()


func _log(s: String) -> void:
	print("PROBE ", s)
	lines.append(s)


var n_ok := 0
var n_fail := 0


func check(cond: bool, what: String) -> void:
	if cond:
		n_ok += 1
		_log("OK %s" % what)
	else:
		n_fail += 1
		print("FAIL ", what)
		lines.append("FAIL " + what)


func _finish(code: int) -> void:
	var res := "ERGEBNIS probe_normandy3: %d bestanden, %d fehlgeschlagen" % [n_ok, n_fail + (1 if code != 0 else 0)]
	print(res)
	lines.append(res)
	if n_fail > 0:
		code = 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open(OUT + "probe.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	Net.leave(false)
	get_tree().quit(code)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	_log("BILD %s%s.png" % [OUT, name])


func _wait(cond: Callable, s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until and not cond.call():
		await get_tree().create_timer(0.1).timeout


func _fps(dur: float) -> Array:
	var times: PackedFloat32Array = []
	var start := Time.get_ticks_usec()
	var last := start
	while float(Time.get_ticks_usec() - start) < dur * 1e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	var total := float(Time.get_ticks_usec() - start) / 1e6
	var st := times.duplicate()
	st.sort()
	var p99: float = st[int(st.size() * 0.99)] if not st.is_empty() else 0.0
	return [times.size() / total, 1000.0 / maxf(p99, 0.001)]


func _run() -> void:
	var phase := String(Game.cli.get("phase", "all"))
	var q := int(Game.cli.get("q", "2"))
	if Settings.quality != q:
		Settings.quality = q
		Settings.apply()
	Net.local_name = "Sonde"
	Net.local_team = Soldier.TEAM_ALLIED
	Net.host({"name": "Probe", "map": "mp_normandy3_mp", "mode": Net.Mode.OCCUPATION, "port": Net.PORT + 57,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0,
		"password": "", "allow_vehicles": false})
	await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 600.0)
	var m: Mission = Game.current_mission()
	if m == null or not Net._soldiers.has(1):
		_log("FEHLER Karte nicht geladen")
		_finish(1)
		return
	var me: Soldier = Net._soldiers.get(1)
	me.max_health = 100000.0      # Vorgabe: nur mit Unverwundbarkeit
	me.health = me.max_health
	await get_tree().create_timer(3.0).timeout
	var vd = preload("res://src/world/view_distance.gd")
	_log("Sichtweite %s" % str(vd.current))
	var wfx = preload("res://src/world/water_fx.gd")
	_log("Wasser %s" % str(wfx.stats))
	var dn = m.get("day_night")
	_log("TagNacht %s" % (str(dn.stats) if dn else "fehlt"))
	_log("Wasser-Film-Spieler übrig: %d" % m.find_children("MovieTexture_*", "VideoStreamPlayer", true, false).size())
	check(float(vd.current.get("fog_end", 0.0)) > 80.0 * 1.3, "MP-Nebel weiter (Ende %s m)" % str(vd.current.get("fog_end")))
	check(int(wfx.stats.get("meshes", 0)) > 0, "Wasser-Shader auf voda")
	check(dn != null and bool(dn.stats.get("active", false)), "Tag/Nacht aktiv, Himmel %s" % (str(dn.stats.get("skies")) if dn else "-"))
	check(m.sky_fx.env.sky.sky_material is ShaderMaterial, "Tag/Nacht-Himmelsmaterial gesetzt")
	m.controller.input_enabled = false
	for h in [m.get("hud"), m.get_node_or_null("MpHud")]:
		if h:
			h.visible = false
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = vd.camera_far()
	m.add_child(cam)
	cam.current = true
	# Wasserfläche suchen
	var water_c := Vector3.ZERO
	var water_ok := false
	var mat = wfx.stats.get("material")
	if mat:
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_override == mat:
				var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				water_c = bb.get_center()
				water_ok = true
				_log("Wasser-AABB %s" % str(bb))
				break
	if phase in ["all", "shots"]:
		if water_ok:
			for v in [["wasser_nah", Vector3(14, 4, 10)], ["wasser_flach", Vector3(-25, 2.0, 6)], ["wasser_oben", Vector3(4, 14, 4)]]:
				cam.global_position = water_c + v[1]
				cam.look_at(water_c, Vector3.UP)
				await get_tree().create_timer(0.6).timeout
				await _save(v[0])
			# Wasser hinter dem Nebelende: entlang des Flusses (AABB-Längsachse z)
			cam.global_position = water_c + Vector3(0, 3.0, 95.0)
			cam.look_at(water_c + Vector3(0, 0, -110.0), Vector3.UP)
			await get_tree().create_timer(0.6).timeout
			await _save("wasser_fern")
		var eye := me.global_position + Vector3(0, 6, 0)
		if dn:
			for h in [5.5, 7.0, 9.0, 12.0, 17.5, 19.0, 20.0, 23.0]:
				dn.t = h / 24.0 * dn.day_len
				dn._update_sun()
				dn._update_sky()
				for dir in [["ost", Vector3(1, 0.12, 0)], ["west", Vector3(-1, 0.12, 0)]]:
					cam.global_position = eye
					cam.look_at(eye + dir[1], Vector3.UP)
					await get_tree().create_timer(1.2).timeout
					await _save("tag_%04.1f_%s" % [h, dir[0]])
				_log("Stunde %.1f: Sonne %.1f° Energie %.2f Gewichte %s Nebel %s" % [h, dn.stats.get("elev", 0.0),
					dn.stats.get("energy", 0.0), str(dn.stats.get("weights")), str(dn.stats.get("fog"))])
			dn.t = 12.0 / 24.0 * dn.day_len
			dn._update_sun()
			dn._update_sky()
	if phase in ["all", "perf"]:
		var base := me.global_position + Vector3(0, 1.7, 0)
		cam.global_position = base
		var fwd := Vector3(0, 0, -1)
		cam.look_at(base + fwd, Vector3.UP)
		await get_tree().create_timer(2.0).timeout
		var b: Array = await _fps(4.0)
		_log("FPS Grundlinie: Mittel %.1f, 1%%-Tief %.1f" % [b[0], b[1]])
		for variant in ["alt", "neu"]:
			ExplosionFx.legacy = variant == "alt"
			var t0 := Time.get_ticks_msec()
			var spawner := func():
				for i in 8:
					var d := 18.0 + float(i % 4) * 5.0
					var side := (float(i) - 3.5) * 3.5
					var p := base + fwd * d + Vector3(side, -1.7, 0)
					Effects.explosion(p, 8.0 if i >= 6 else 5.0, [], &"vehicle" if i >= 6 else &"")
					await get_tree().create_timer(0.25).timeout
			spawner.call()
			var peak := [0]
			get_tree().create_timer(2.5).timeout.connect(func():
				for gp in m.find_children("Smoke", "GPUParticles3D", true, false):
					peak[0] += (gp as GPUParticles3D).amount)
			var r: Array = await _fps(12.0)
			_log("Rauchpartikel nach 2,5 s (%s): %d" % [variant, peak[0]])
			var parts := 0
			for gp in m.find_children("Smoke", "GPUParticles3D", true, false):
				parts += (gp as GPUParticles3D).amount
			if variant == "neu":
				check(parts > 0, "neuer Rauch erzeugt (%d Partikel)" % parts)
			_log("FPS Rauch %s: Mittel %.1f, 1%%-Tief %.1f (Grundlinie %.1f), Rauchpartikel aktiv %d, %d ms" % [
				variant, r[0], r[1], b[0], parts, Time.get_ticks_msec() - t0])
			await get_tree().create_timer(4.0).timeout
			for i in 4:
				Effects.explosion(base + fwd * (18.0 + 4.0 * i) + Vector3((i - 1.5) * 4.0, -1.7, 0), 5.0, [])
			await get_tree().create_timer(2.0).timeout
			await _save("rauch_" + variant)
			await get_tree().create_timer(7.0).timeout
		ExplosionFx.legacy = false
	_finish(0)
