extends "res://tests/test_gameplay.gd"
## B-028: Original-Partikeltabelle (O-007), Ende der Zwischensequenz aus Kameraanimation/Skriptende (O-008),
## Zerstörungsanimation + Fässer (O-009), stumme Befehle zählend gemeldet (O-006).
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_b028
## (ARCTIC2: Fässer la_bar03_1/2 = Typ 25, Partikel 64 „vybuch barel“, Animation la_bar03A.i3d; Kamera #cama2b1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime"):
			break
		await get_tree().process_frame
	await frames(5)
	var m := mission()
	var rt = m.get("runtime") if m else null
	check(rt != null, "Mission mit Skriptlaufzeit geladen")
	if rt == null:
		_finish()
		return
	# laufende Intro-Sequenz beenden, damit die eigenen Sequenzen sauber starten
	if rt.in_cutscene:
		rt.end_cutscene()
	await frames(3)
	_particle_tests(rt, m)
	await _cutscene_tests(rt, m)
	await _destruction_tests(rt, m)
	_silent_tests(rt)
	_finish()


func _particle_tests(rt, m) -> void:
	var t: Array = OrigParticles.table()
	check(t.size() >= 121, "Partikeltabelle effects.def geladen (%d Einträge)" % t.size())
	var d64 := OrigParticles.definition(64)
	check(String(d64.get("name", "")).contains("barel") and int(d64.get("blend", 0)) == 2,
		"Eintrag 64 = Fassexplosion, additiv", str(d64.get("name", "")))
	check(String(OrigParticles.definition(114).get("name", "")).contains("fire works")
		and String(OrigParticles.definition(108).get("name", "")).contains("jeep"),
		"Index = Nummer im Namen (114 Feuerwerk, 108 Jeep-Staub)")
	check(OrigParticles.kind_of(46) == "fire" and OrigParticles.kind_of(10) == "smoke" and OrigParticles.kind_of(64) == "explosion"
		and OrigParticles.kind_of(3) == "sparks" and OrigParticles.kind_of(7) == "water",
		"Arten je Typ: Feuer/Rauch/Explosion/Funken/Wasser")
	var n: Node3D = OrigParticles.spawn(64, Vector3(0, 50, 0), m.dynamic_root)
	var gps := n.get_children().filter(func(c): return c is GPUParticles3D)
	check(gps.size() == (d64.get("emitters", []) as Array).size() and gps.size() == 3, "Fassexplosion: ein Partikelsystem je Emitter (3)")
	check((gps[0] as GPUParticles3D).one_shot and not OrigParticles.is_continuous(64), "Explosion = Stoß (einmalig)")
	var mat := (gps[0] as GPUParticles3D).draw_pass_1.surface_get_material(0) as StandardMaterial3D
	check(mat and mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and mat.albedo_texture != null,
		"additive Mischung + Originaltextur d_explos01")
	var c := OrigParticles.spawn(10, Vector3(0, 50, 0), m.dynamic_root)
	var g10 := c.get_child(0) as GPUParticles3D
	check(OrigParticles.is_continuous(10) and not g10.one_shot and absf(g10.lifetime - 5.0) < 0.01,
		"Zigarettenrauch: Dauerausstoß, Lebensdauer 5000 ms")
	n.queue_free()
	c.queue_free()
	# Skriptbefehle
	var vm := LsVM.new(LsCompiler.new(), m.squad.leader(), rt)
	var before: int = OrigParticles.created.size()
	vm.vars["F"] = m.squad.leader()
	rt.call_api(vm, "FRM_CREATEPARTICLE", [["num", 53], ["var", "F"]])
	check(OrigParticles.created.size() == before + 1 and int(OrigParticles.created[-1][0]) == 53,
		"FRM_CreateParticle(53) erzeugt Originaleffekt „vybuch cisterna“")
	vm.vars["PI"] = 0
	rt.call_api(vm, "FRM_CREATEINDEXEDPARTICLE", [["num", 23], ["var", "F"], ["var", "PI"]])
	var idx := int(vm.vars.get("PI", 0))
	var node = rt._indexed_particles.get(idx)
	check(idx > 0 and is_instance_valid(node) and int(node.get_meta("particle_id", -1)) == 23, "FRM_CreateIndexedParticle(23) Rauchgranate rot")
	rt.call_api(vm, "FRM_FINISHINDEXEDPARTICLE", [["num", idx]])
	check(not rt._indexed_particles.has(idx), "FRM_FinishIndexedParticle beendet den Effekt")


func _cutscene_tests(rt, m) -> void:
	# Missionsskripte (ARCTIC2-Intro setzt weiter Kameraanimationen/CSC_EndCutscene) für diesen Teil anhalten
	var was_paused := {}
	for v in rt.vms:
		was_paused[v] = v.paused
		v.paused = true
	for tr in rt.anim._tracks.duplicate():
		if tr["camera"]:
			rt.anim._tracks.erase(tr)
	rt.auto_skip = false
	var cam_name := "#cama2b1"
	var len_s: float = rt.anim.anim_length(cam_name)
	check(len_s > 1.0 and len_s < 10.0, "Länge der Kameraanimation aus ls_anim (%.2f s)" % len_s)
	# 1) Sequenz ohne CSC_EndCutscene mit Kameraanimation → Ende ≈ Länge + 0,5 s statt 90 s
	var caller := LsVM.new(LsCompiler.new(), null, rt)
	caller.ended = true
	var cam := Node3D.new()
	m.dynamic_root.add_child(cam)
	rt.run_cutscene(901, caller)
	rt.anim.set_camera_animation(cam, cam_name)
	# Spielzeit messen (headless/WARP: Bildzeit ≠ Wanduhr)
	var dt := await _game_wait(rt, 40.0)
	check(not rt.in_cutscene and rt.cutscene_end_reason == "camera" and dt >= len_s * 0.8 and dt < len_s + 5.0,
		"Sequenz endet mit der Kameraanimation (%.1f s, Grund %s)" % [dt, rt.cutscene_end_reason])
	# 2) ohne Kamera: wartendes Skript hält die Sequenz offen, CSC_EndCutscene beendet sie
	var waiter := LsVM.new(LsCompiler.new(), null, rt)
	waiter.wait = 1000.0
	rt.run_cutscene(902, waiter)
	await get_tree().create_timer(4.0).timeout
	check(rt.in_cutscene, "wartendes Sequenzskript hält die Zwischensequenz offen")
	rt.call_api(waiter, "CSC_ENDCUTSCENE", [])
	check(not rt.in_cutscene and rt.cutscene_end_reason == "script", "CSC_EndCutscene bleibt maßgeblich")
	# 3) ohne Kamera, Skripte fertig → Ende nach 3 s Untätigkeit
	var done := LsVM.new(LsCompiler.new(), null, rt)
	done.ended = true
	rt.run_cutscene(903, done)
	dt = await _game_wait(rt, 40.0)
	check(not rt.in_cutscene and rt.cutscene_end_reason == "scripts_idle" and dt < 10.0,
		"Sequenz ohne Kamera endet nach Skriptende (%.1f s)" % dt)
	check(rt.CUTSCENE_FALLBACK_S == 90.0, "90 s nur noch als Rückfall")
	cam.queue_free()
	rt.auto_skip = true
	for v in was_paused:
		v.paused = was_paused[v]


## wartet (Spielzeit) bis die Sequenz endet oder max_s vergangen ist; liefert die vergangene Spielzeit
func _game_wait(rt, max_s: float) -> float:
	var t := 0.0
	while rt.in_cutscene and t < max_s:
		await get_tree().process_frame
		t += get_process_delta_time()
	return t


func _destruction_tests(rt, m) -> void:
	var ia = m.get("interactive")
	check(ia != null, "OrigInteractive vorhanden")
	if ia == null:
		return
	print("interaktiv: ", ia.stats)
	var b1 = ia.controls.get("LA_BAR03_1")
	check(b1 != null and b1.get("frame") != null, "Fass la_bar03_1 (Typ 25) angelegt")
	if b1 == null:
		return
	var frame: Node3D = b1.frame
	var before: int = OrigParticles.created.size()
	b1.destroy()
	await frames(3)
	check(b1.destroyed and int(frame.get_meta("actor_state", 1)) == 0, "Fass zerstört, Zustand 0")
	check(b1.animated and frame.visible and rt.anim.is_playing(frame),
		"Zerstörungsanimation la_bar03A.i3d läuft, Objekt bleibt als Trümmer sichtbar")
	var made := OrigParticles.created.slice(before)
	check(made.any(func(x): return int(x[0]) == 64), "Partikel 64 „vybuch barel“ aus den Akteurdaten")
	var bodies := frame.find_children("*", "StaticBody3D", true, false)
	check(bodies.all(func(b): return (b as StaticBody3D).collision_layer == 0), "Kollision des zerstörten Fasses aus")
	# Explosion: Splitter gegen einen Soldaten in 2 m Abstand
	var s: Soldier = m.squad.leader()
	var hp0 := s.health
	var b2 = ia.controls.get("LA_BAR03_2")
	if b2:
		s.global_position = b2.global_position + Vector3(2.0, 0.2, 0.0)
		await frames(2)
		s.health = 1000.0     # Einzelkämpfer (Commando1) darf nicht sterben – sonst endet die Mission
		hp0 = s.health
		b2.destroy()
		await get_tree().create_timer(0.4).timeout
		check(s.health < hp0, "Fassexplosion verletzt Soldaten in 2 m (%.0f → %.0f)" % [hp0, s.health])
		s.health = 100.0
	# Spielstand: zerstört → Endlage der Animation, sichtbar
	var x = b1.serialize()
	check(bool(x.get("destroyed", false)), "Zerstörung im Spielstand")
	var t := 0.0
	while is_instance_valid(rt) and rt.anim.is_playing(frame) and t < 15.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	check(is_instance_valid(rt) and not rt.anim.is_playing(frame), "Zerstörungsanimation endet (88 Bilder, %.1f s)" % t)


func _silent_tests(rt) -> void:
	var vm := LsVM.new(LsCompiler.new(), null, rt)
	# Seit B-033 sind Doppler und Umgehungs-Flag umgesetzt (keine echten stummen Befehle mehr) → beide weder stumm noch
	# „nicht umgesetzt“; die Zählung/den Bericht prüft ein künstlicher stummer Eintrag (Abschluss 0.9.8, Testerwartung veraltet).
	rt.call_api(vm, "FRM_SOUNDADJUSTDOPPLER", [["num", 0], ["num", 1]])
	rt.call_api(vm, "HUMAN_SETIGNORECIRCUMVENTIONFLAG", [["num", 1]])
	rt._stub("TEST_STUMM", "B-028")
	rt._stub("TEST_STUMM", "B-028")
	check(rt.stubbed.has("TEST_STUMM") and int(rt.stubbed["TEST_STUMM"]["count"]) >= 2
		and rt.stubbed["TEST_STUMM"]["owner"] == "B-028", "stummer Befehl gezählt (B-028)")
	check(not rt.unimplemented.has("FRM_SOUNDADJUSTDOPPLER") and not rt.unimplemented.has("HUMAN_SETIGNORECIRCUMVENTIONFLAG")
		and not rt.stubbed.has("FRM_SOUNDADJUSTDOPPLER"), "Doppler/Umgehungs-Flag umgesetzt (B-033), stumm ≠ nicht umgesetzt")
	var p := "res://test_output/ls_silent_b028.txt"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	rt.write_silent_report(p, "test_b028")
	var txt := FileAccess.get_file_as_string(p)
	check(txt.contains("stumm\tTEST_STUMM") and txt.contains("stumm:"), "Bericht ls_silent geschrieben")
	rt.stubbed.erase("TEST_STUMM")
