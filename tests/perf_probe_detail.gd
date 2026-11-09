extends Node
## Skriptzeit-Messung je Verdächtigem (fix_performance, 31.10.2026). Fenster, nicht kopflos:
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=perf_probe_detail [--perf_tag=neu] [--perf_s=6]
## Feste Kamera (Blick des Führers bleibt), Grafikstufe 2 erzwungen. Zwei Messarten:
##  1. Direktaufruf: je Kategorie die Prozessfunktionen aller passenden Knoten N-mal aufrufen und mit
##     Time.get_ticks_usec messen (µs je Bild bzw. je Takt) – unabhängig vom WARP-Rendering.
##  2. Ein/Aus: Kategorie abschalten (set_process/set_physics_process false), Monitorwerte Prozess/Physik/Bild
##     gegen die Grundmessung vergleichen.
## Ergebnis: test_output/perf_detail.txt (angehängt). Beachtet die Test-Sperre nicht selbst.

const CATS := {
	"perception": ["src/ai/perception.gd"],
	"ai_brains": ["src/ai/enemy_brain.gd", "src/ai/squad_brain.gd", "src/ai/ai_brain.gd", "src/ai/escort_brain.gd", "src/actors/dog.gd"],
	"soldier": ["src/actors/soldier.gd"],
	"hud": ["src/ui/orig_hud.gd", "src/ui/hud.gd", "src/ui/command_menu.gd"],
	"objective_markers": ["src/ui/objective_markers.gd"],
	"blood": ["src/combat/blood_fx.gd"],
	"effects": ["src/combat/effects.gd"],
	"sky": ["src/world/sky_fx.gd"],
	"ls_runtime": ["src/orig/ls_runtime.gd"],
	"ls_anim": ["src/orig/ls_anim.gd"],
	"ragdoll": ["src/actors/ragdoll.gd"],
	"interactive": ["src/orig/orig_interactive.gd"],
	"charges": ["src/combat/placed_charge.gd", "src/world/charge_site.gd"],
	"mission": ["src/mission/mission.gd", "src/missions/orig_mission.gd", "src/orig/mission_area.gd", "src/orig/orig_extras.gd"],
	"player": ["src/player/player_controller.gd", "src/player/camera_rig.gd"],
	"audio": ["src/audio/orig_audio.gd"],
	"ballistics": ["src/combat/ballistics.gd"],
	"net": ["src/autoload/net.gd"],
}

var t0 := 0
var lines: PackedStringArray = []
var tag := ""
var mid := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	if Settings.get("quality") != null:
		Settings.quality = int(Game.cli.get("perf_quality", "2"))   # B-039: Stufe wählbar (0–4)
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
	var nav_t0 := Time.get_ticks_msec()
	while not bool(m.get("nav_ready")) and Time.get_ticks_msec() - nav_t0 < 120000:
		await get_tree().process_frame
	tag = String(Game.cli.get("perf_tag", ""))
	mid = Game.current_mission_id
	var load_ms := Time.get_ticks_msec() - t0
	if Settings.quality != int(Game.cli.get("perf_quality", "2")):
		Settings.quality = int(Game.cli.get("perf_quality", "2"))
	# perf_gross: Trupp unverwundbar (wie test_orig_complete)
	if m.squad:
		for s in m.squad.members:
			if is_instance_valid(s):
				s.max_health = 100000.0
				s.health = 100000.0
	# Intro/Zwischensequenz abwarten, dann ruhig stellen
	await get_tree().create_timer(float(Game.cli.get("perf_wait", "8"))).timeout
	var dur := float(Game.cli.get("perf_s", "6"))
	var nodes := _collect()
	var ais: int = (m.enemies as Array).size() if m.get("enemies") != null else 0
	lines.append("DETAIL %s %s  Qualitaet %s, Knoten %d, Gegner %d, Soldaten %d, Leichen %d, Fenster %s" % [mid, tag,
		str(Settings.get("quality")), get_tree().get_node_count(), ais, get_tree().get_nodes_in_group("soldiers").size(),
		get_tree().get_nodes_in_group("corpses").size(), str(get_viewport().get_visible_rect().size)])
	lines.append(_scene_counts(m, load_ms))
	# LsVM-Takt getrennt (LsRuntime._physics_process ohne Rotationen/Formationen)
	var rt = m.get("runtime")
	if rt == null:
		for n in nodes.get("ls_runtime", []):
			rt = n
	if rt != null and rt.get("vms") != null:
		var us := 0
		var live := 0
		for vm in rt.vms:
			if not vm.terminated and not (vm.ended and vm.events.is_empty() and vm.code.whenevers.is_empty()):
				live += 1
		for r in 20:
			var a := Time.get_ticks_usec()
			for vm in rt.vms:
				vm.tick(1.0 / 60.0)
			us += Time.get_ticks_usec() - a
			await get_tree().physics_frame
		lines.append("DETAIL %s %s  direkt ls_vm_tick         VMs %3d (aktiv %d)  je Takt %.3f ms" % [mid, tag, rt.vms.size(), live,
			float(us) / 20.0 / 1000.0])
	# --- 1. Direktaufruf ---
	for cat in CATS:
		var arr: Array = nodes.get(cat, [])
		if arr.is_empty():
			lines.append("DETAIL %s %s  direkt %-18s (keine Knoten)" % [mid, tag, cat])
			continue
		var reps := 20
		var us_p := 0
		var us_ph := 0
		for r in reps:
			var a := Time.get_ticks_usec()
			for n in arr:
				if is_instance_valid(n) and n.has_method("_process") and n.is_processing():
					n._process(1.0 / 60.0)
			var b := Time.get_ticks_usec()
			for n in arr:
				if not is_instance_valid(n) or not n.has_method("_physics_process") or not n.is_physics_processing():
					continue
				if cat == "perception":
					if n.get("soldier") != null and n.soldier.alive:
						n._update_sight(0.15)   # Takt direkt (sonst nur Zählerabzug)
				elif cat == "soldier" or cat == "ballistics":
					continue   # Bewegung/Projektile nicht doppelt simulieren (nur Ein/Aus)
				else:
					n._physics_process(1.0 / 60.0)
			var c := Time.get_ticks_usec()
			us_p += b - a
			us_ph += c - b
			await get_tree().process_frame
		var extra := ""
		if cat == "perception":
			extra = "  (je Takt 0,15 s ≙ %.3f ms/Bild bei 60 Hz Physik)" % (float(us_ph) / reps / 1000.0 / 9.0)
		lines.append("DETAIL %s %s  direkt %-18s Knoten %3d  _process %.3f ms  _physics %.3f ms%s" % [mid, tag, cat, arr.size(),
			float(us_p) / reps / 1000.0, float(us_ph) / reps / 1000.0, extra])
	# --- 1a. perf_gross: Soldat aufgeschlüsselt (Animation vs. move_and_slide), je Bild über alle Soldaten ---
	var us_anim := 0
	var us_slide := 0
	var us_near := 0
	var n_near := 0
	var camp: Vector3 = get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else Vector3.ZERO
	for r in 10:
		for s in nodes.get("soldier", []):
			if not is_instance_valid(s) or not s.alive or s.vehicle != null or s.net_puppet:
				continue
			var a := Time.get_ticks_usec()
			s.model.update_anim(0.0, s.stance, s.current_speed(), s.look_pitch, s.aiming, s.lean)
			var b := Time.get_ticks_usec()
			var v: Vector3 = s.velocity
			s.velocity = Vector3.ZERO
			s.move_and_slide()
			s.velocity = v
			var c := Time.get_ticks_usec()
			us_anim += b - a
			us_slide += c - b
			if r == 0 and s.global_position.distance_to(camp) < 60.0:
				n_near += 1
		await get_tree().process_frame
	var lodn := [0, 0, 0]
	var lod_cost := 0.0
	var per := float(us_anim) / 10000.0 / maxf(nodes.get("soldier", []).size(), 1)
	for s in nodes.get("soldier", []):
		if is_instance_valid(s) and s.alive and s.has_method("_anim_lod_interval"):
			var k: int = 1 if s.is_player_controlled else s._anim_lod_interval()
			lodn[[1, 2, 4].find(k)] += 1
			lod_cost += per / k
	lines.append("DETAIL %s %s  anim_lod Takt 1/2/4: %d/%d/%d  update_anim effektiv %.3f ms je Physikbild" % [mid, tag,
		lodn[0], lodn[1], lodn[2], lod_cost])
	lines.append("DETAIL %s %s  soldat update_anim %.3f ms  move_and_slide %.3f ms  (je Bild, alle; < 60 m: %d)" % [mid, tag,
		float(us_anim) / 10000.0, float(us_slide) / 10000.0, n_near])
	# --- 1b. HUD aufgeschlüsselt (OrigHud-Teilfunktionen, je 20×) ---
	for h in nodes.get("hud", []):
		if not is_instance_valid(h):
			continue
		var sname: String = h.get_script().resource_path.get_file()
		var act = m.controller.active if m.get("controller") else null
		var parts := {"_process (gesamt)": func(): h._process(1.0 / 60.0)}
		if sname == "orig_hud.gd":
			parts["_update_injury"] = func(): h._update_injury(act, 1.0 / 60.0)
			parts["_update_sectors"] = func(): h._update_sectors(1.0 / 60.0)
			parts["_update_progress"] = func(): h._update_progress(act)
			parts["_update_action_icon"] = func(): h._update_action_icon(act)
			parts["_update_cross_name"] = func(): h._update_cross_name(act)
			parts["_update_timers"] = func(): h._update_timers()
			parts["_update_tacho"] = func(): h._update_tacho(act)
			parts["_update_compass_dots"] = func(): h._update_compass_dots(act, 1.0 / 60.0)
			parts["_update_weapon_panel"] = func(): h._update_weapon_panel(act)
			parts["_update_squad_bar"] = func(): h._update_squad_bar(act)
			parts["_update_state_icons x6"] = func():
				for i in 6:
					h._update_state_icons(i, m.squad.members[i] if i < m.squad.members.size() else null, m.squad.members.find(act) == i)
		for k in parts:
			if not h.has_method("_process"):
				break
			if k != "_process (gesamt)" and not h.has_method(String(k).split(" ")[0]):
				continue
			var a := Time.get_ticks_usec()
			for r in 20:
				(parts[k] as Callable).call()
			lines.append("DETAIL %s %s  hud %-14s %-24s %.3f ms" % [mid, tag, sname, k, float(Time.get_ticks_usec() - a) / 20.0 / 1000.0])
	# --- 2. Ein/Aus ---
	var base := await _measure(dur)
	lines.append(_fmt("Grundmessung", base))
	if String(Game.cli.get("perf_onoff", "1")) == "0":
		_out(lines)
		get_tree().quit(0)
		return
	var onoff_cats: Array = ["perception", "ai_brains", "hud", "objective_markers", "blood", "effects", "sky", "ls_runtime", "interactive", "charges", "mission", "audio"]
	if Game.cli.has("perf_cats"):   # perf_gross: Auswahl, z. B. soldier,ls_anim
		onoff_cats = Array(String(Game.cli["perf_cats"]).split(","))
	for cat in onoff_cats:
		var arr: Array = nodes.get(cat, [])
		if arr.is_empty():
			continue
		var saved := []
		for n in arr:
			if is_instance_valid(n):
				saved.append([n, n.is_processing(), n.is_physics_processing()])
				n.set_process(false)
				n.set_physics_process(false)
		var r := await _measure(dur)
		for s in saved:
			if is_instance_valid(s[0]):
				s[0].set_process(s[1])
				s[0].set_physics_process(s[2])
		lines.append(_fmt("ohne " + cat, r, base))
	var base2 := await _measure(dur)
	lines.append(_fmt("Grundmessung 2", base2))
	_out(lines)
	get_tree().quit(0)


func _collect() -> Dictionary:
	var out := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var s: Script = n.get_script()
		if s == null:
			continue
		var p := s.resource_path
		for cat in CATS:
			for f in CATS[cat]:
				if p.ends_with(f) or (p.begins_with("res://" + String(f)) ):
					out[cat] = out.get(cat, []) + [n]
	return out


## B-039: GPU-Zählwerte ohne Renderer (kopflos) aus dem Szenenbaum + Render-Monitore (nur im Fenster ≠ 0) + Speicher.
## sichtbar = Geometrie im Baum sichtbar und Kamera innerhalb visibility_range_end (0 = unbegrenzt).
func _scene_counts(m: Node, load_ms: int) -> String:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	var geo := 0
	var vis := 0
	var surf := 0
	var shadow := 0
	var mm_inst := 0
	var parts := 0
	var lights := 0
	var shadow_lights := 0
	for n in m.find_children("*", "VisualInstance3D", true, false):
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			if g is GPUParticles3D:
				var gp := g as GPUParticles3D
				if gp.is_visible_in_tree() and gp.emitting:
					parts += int(gp.amount * gp.amount_ratio)
				continue
			if g is CPUParticles3D:
				if (g as CPUParticles3D).is_visible_in_tree() and (g as CPUParticles3D).emitting:
					parts += (g as CPUParticles3D).amount
				continue
			geo += 1
			if not g.is_visible_in_tree() or g.has_meta("b039_merged"):
				continue
			var d := g.global_position.distance_to(cp)
			if g.visibility_range_end > 0.0 and d > g.visibility_range_end:
				continue
			vis += 1
			var sc := 1
			if g is MeshInstance3D and (g as MeshInstance3D).mesh:
				sc = (g as MeshInstance3D).mesh.get_surface_count()
			elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
				var mm := (g as MultiMeshInstance3D).multimesh
				mm_inst += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				sc = mm.mesh.get_surface_count() if mm.mesh else 1
			surf += sc
			if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow += sc
		elif n is Light3D and (n as Light3D).is_visible_in_tree():
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadow_lights += 1
	return ("DETAIL %s %s  ZAEHLER Q%d Laden %.1f s | Geometrie %d, sichtbar %d, Oberflaechen %d (≈DC), Schattenwerfer-Oberfl. %d, " +
		"MultiMesh-Inst %d, Partikel %d, Lichter %d (Schatten %d) | Render: DC %d, Objekte %d, Primitive %d | " +
		"RAM statisch %.0f MB, Video %.0f MB, Textur %.0f MB, Puffer %.0f MB, Knoten %d") % [mid, tag, Settings.quality,
		load_ms / 1000.0, geo, vis, surf, shadow, mm_inst, parts, lights, shadow_lights,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		get_tree().get_node_count()]


func _measure(dur: float) -> Dictionary:
	await get_tree().create_timer(0.5).timeout
	var frames := 0
	var proc := 0.0
	var phys := 0.0
	var dc := 0.0
	var start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) < dur * 1e6:
		await get_tree().process_frame
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var total := float(Time.get_ticks_usec() - start) / 1000.0
	var n := maxf(frames, 1)
	return {"frame": total / n, "proc": proc / n, "phys": phys / n, "dc": dc / n, "fps": frames / (total / 1000.0)}


func _fmt(name: String, r: Dictionary, base := {}) -> String:
	var s := "DETAIL %s %s  %-22s Bild %.2f ms (%.1f fps)  Prozess %.3f ms  Physik %.3f ms  DC %.0f" % [mid, tag, name, r.frame,
		r.fps, r.proc, r.phys, r.dc]
	if not base.is_empty():
		s += "   Δ Prozess %+.3f  Δ Physik %+.3f" % [r.proc - base.proc, r.phys - base.phys]
	return s


func _out(ls: PackedStringArray) -> void:
	for l in ls:
		print(l)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var p := ProjectSettings.globalize_path("res://test_output/perf_detail.txt")
	var f: FileAccess = FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string("%s\n" % "\n".join(ls))
		f.close()
