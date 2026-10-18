extends Node
## Lade- und Bildratenmessung (Fenster, nicht kopflos – sonst rendert nichts):
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=perf_probe [--perf_s=10] [--perf_tag=vorher]
## Misst: Ladezeit bis zur fertigen Mission (Start → Mission bereit → erstes Bild → Navigationsnetz), Aufschlüsselung
## (scene.glb, Modelle, Figuren je einzeln nachgeladen), danach perf_s Sekunden Bildrate bei langsam drehender Kamera
## (Mittel/1-%-Tief), Draw Calls, Objekte, Primitive, Prozess-/Physikzeit. Ergebnis: PERF-Zeilen auf stdout und
## test_output/perf.txt (angehängt). Beachtet die Test-Sperre nicht selbst (Aufrufer legt sie an).

var t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _run() -> void:
	var m = null
	while true:
		await get_tree().process_frame
		m = Game.current_mission()
		if m and m.get("squad") and m.is_node_ready():
			break
		if Time.get_ticks_msec() - t0 > 600000:
			_out(["FEHLER: Mission nicht geladen"])
			get_tree().quit(1)
			return
	var t_ready := Time.get_ticks_msec() - t0
	await RenderingServer.frame_post_draw
	var t_first := Time.get_ticks_msec() - t0
	var nav_t0 := Time.get_ticks_msec()
	while not bool(m.get("nav_ready")) and Time.get_ticks_msec() - nav_t0 < 120000:
		await get_tree().process_frame
	var t_nav := Time.get_ticks_msec() - t0
	var lines: PackedStringArray = []
	var tag := String(Game.cli.get("perf_tag", ""))
	var mid := Game.current_mission_id
	lines.append("PERF %s %s  Ladezeit: Mission bereit %.2f s, erstes Bild %.2f s, Navigationsnetz %.2f s" % [mid, tag,
		t_ready / 1000.0, t_first / 1000.0, t_nav / 1000.0])
	var ml = get_node_or_null("/root/MissionLoader")
	if ml and ml.has_method("timing_text"):
		lines.append("PERF %s %s  Lader: %s" % [mid, tag, ml.timing_text()])
	# --- Bildrate: Kamera dreht 360° in perf_s Sekunden ---
	var dur := float(Game.cli.get("perf_s", "10"))
	await get_tree().create_timer(3.0).timeout
	var lead: Soldier = m.squad.leader() if m.squad else null
	var frames := 0
	var times: PackedFloat32Array = []
	var dc := 0.0
	var obj := 0.0
	var prim := 0.0
	var proc := 0.0
	var phys := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while float(Time.get_ticks_usec() - start) < dur * 1e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		frames += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if is_instance_valid(lead):
			lead.look_yaw = TAU * float(now - start) / (dur * 1e6)
	var total_s := float(Time.get_ticks_usec() - start) / 1e6
	var sorted_t := times.duplicate()
	sorted_t.sort()
	var p99: float = sorted_t[int(sorted_t.size() * 0.99)] if not sorted_t.is_empty() else 0.0
	var n := maxf(frames, 1)
	lines.append("PERF %s %s  FPS: Mittel %.1f, 1%%-Tief %.1f (%d Bilder in %.1f s, Fenster %s)" % [mid, tag, frames / total_s,
		1000.0 / maxf(p99, 0.001), frames, total_s, str(get_viewport().get_visible_rect().size)])
	lines.append("PERF %s %s  je Bild: Draw Calls %.0f, Objekte %.0f, Primitive %.0f, Prozess %.2f ms, Physik %.2f ms" % [mid, tag,
		dc / n, obj / n, prim / n, proc / n, phys / n])
	var ais: int = (m.enemies as Array).size() if m.get("enemies") != null else 0
	lines.append("PERF %s %s  Szene: Knoten %d, Gegner/KI %d, Lichter %d, Sichtweiten %s" % [mid, tag, get_tree().get_node_count(), ais,
		m.find_children("*", "Light3D", true, false).size(), str(PerfTuning.last)])
	# zweites Laden derselben Karte (neue MP-Runde / ERNEUT VERSUCHEN): Zwischenspeicher
	if String(Game.cli.get("perf_reload", "1")) == "1":
		var r0 := Time.get_ticks_msec()
		Game.start_mission(mid)
		while true:
			await get_tree().process_frame
			var m2 = Game.current_mission()
			if m2 and m2 != m and m2.get("squad") and m2.is_node_ready():
				break
			if Time.get_ticks_msec() - r0 > 600000:
				break
		lines.append("PERF %s %s  Neu laden (gleiche Karte): Mission bereit %.2f s" % [mid, tag, (Time.get_ticks_msec() - r0) / 1000.0])
		var ml2 = get_node_or_null("/root/MissionLoader")
		if ml2 and ml2.has_method("timing_text") and MissionLoader.enabled():
			lines.append("PERF %s %s  Lader: %s" % [mid, tag, ml2.timing_text()])
	_out(lines)
	get_tree().quit(0)


func _out(lines: PackedStringArray) -> void:
	for l in lines:
		print(l)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var p := ProjectSettings.globalize_path("res://test_output/perf.txt")
	var f: FileAccess = null
	if FileAccess.file_exists(p):
		f = FileAccess.open(p, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string("%s\n" % "\n".join(lines))
		f.close()
