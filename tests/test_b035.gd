extends "res://tests/test_gameplay.gd"
## B-035: Darstellungsbefehle aus Skripten – Leuchtturmlicht (Glows, Lichtkegel, Umhängung), Lightmaps (Stufen,
## Gruppen), Gesichtstexturen, HUMAN_SetOptimized (belegt wirkungslos), FRM_SetTarget, Wetter-Rest, Texturverschiebung,
## Wolken, Dekoration, stummer Bericht.
##   tools\godot.cmd --headless -- --mission=no1_leuchtturm --autoplay=test_b035


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
	check(rt != null, "Mission NORMANDY mit Skriptlaufzeit geladen")
	if rt == null:
		_finish()
		return
	if rt.in_cutscene:
		rt.end_cutscene()
	await frames(3)
	await _lighthouse_tests(rt)
	_lightmap_tests(rt)
	_face_tests(rt, m)
	_optimized_tests(rt, m)
	await _target_tests(rt, m)
	_weather_tests(rt, m)
	await _shift_cloud_deco_tests(rt, m)
	_report_tests(rt)
	_finish()


func _vm(rt, m) -> LsVM:
	return LsVM.new(LsCompiler.new(), m.squad.leader(), rt)


func _lighthouse_tests(rt) -> void:
	var o: OrigLevel = rt.orig
	var svet: Node3D = rt.find_frame("m_maj_svet01")
	var vol: Node3D = rt.find_frame("majak_volum01")
	var f1: Node3D = rt.find_frame("vol_majak01")
	var f2: Node3D = rt.find_frame("vol_majak02")
	check(svet != null and vol != null and f1 != null and f2 != null, "Leuchtturm-Frames gefunden (Licht, Kegel, 2 Glows)")
	if svet == null or vol == null or f1 == null:
		return
	check(vol.get_parent() == svet and f1.get_parent() == svet and f2.get_parent() == svet,
		"scene2.bin-Umhängung: Kegel und Glows hängen am Leuchtturmlicht (drehen mit)")
	var spr := f1.find_children("*", "Sprite3D", true, false)
	var lights := f1.find_children("*", "OmniLight3D", true, false)
	check(spr.size() == 1 and (spr[0] as Sprite3D).texture != null, "Glow vol_majak01: Sprite mit Originaltextur 2E_FLR1")
	check(lights.size() == 1, "Glow vol_majak01: Licht")
	var vmi := vol as MeshInstance3D
	var vm0 := vmi.get_active_material(0) as StandardMaterial3D if vmi else null
	check(vm0 != null and vm0.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and vm0.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"Lichtkegel majak_volum01 additiv und selbstleuchtend")
	# Anfangszustand aus x_n1_majak.scr: Kegel/Glows aus
	check(not vol.visible and not f1.visible and not f2.visible, "Vor dem Ziel: Licht aus (FRM_SetOn false im Skript)")
	var svm: LsVM = rt.vm_of.get(svet)
	check(svm != null, "Skript X_N1_majak.scr am Leuchtturmlicht")
	if svm == null:
		return
	var b0 := svet.global_transform.basis
	var vb0 := vol.global_transform.basis
	svm.signal_received(1)                   # wie x_n1_objective1: SendSignal(majak, 1)
	await frames(30)
	check(vol.visible and f1.visible and f2.visible, "Signal 1: Lichtkegel und Glows an")
	var d_svet := b0.x.angle_to(svet.global_transform.basis.x)
	var d_vol := vb0.y.angle_to(vol.global_transform.basis.y)
	check(d_svet > 0.01 and d_vol > 0.01, "Leuchtturmlicht dreht (FRM_RotateY), Kegel dreht mit", "%.3f / %.3f" % [d_svet, d_vol])
	await frames(5)


func _lightmap_tests(rt) -> void:
	var o: OrigLevel = rt.orig
	check(not o.lightmaps.is_empty(), "lightmaps.json geladen")
	var f := o.lightmap_factor("m_maj_dv01", 1)
	check(absf(f - 68.24 / 65.54) < 0.02, "Tür m_maj_dv01: Stufe 1 = Satz 2 relativ zu Satz 1", "%.3f" % f)
	var door: Node3D = rt.find_frame("m_maj_dv01")
	var vm := LsVM.new(LsCompiler.new(), door, rt)
	vm.vars["D"] = door
	rt.call_api(vm, "FRM_SETLIGHTMAP", [["var", "D"], ["num", 1]])
	check(o.lightmap_level("m_maj_dv01") == 1 and not rt.stubbed.has("FRM_SETLIGHTMAP"), "FRM_SetLightmap setzt Stufe (nicht stumm)")
	var mi: MeshInstance3D = door if door is MeshInstance3D else null
	if mi == null and door:
		var ms := door.find_children("*", "MeshInstance3D", true, false)
		mi = ms[0] if not ms.is_empty() else null
	if mi:
		var mat := mi.get_active_material(0) as BaseMaterial3D
		var base: Color = mat.get_meta("lm_base", Color.WHITE)
		check(absf(mat.albedo_color.r - base.r * f) < 0.01, "Albedo der Tür um den Lightmapfaktor angepasst")
	# Gruppe (CZECH1-Form „nadrazi11“, hier mit Testdaten am Tür-Frame: 60 → 20 = Licht aus)
	o.lightmaps["groups"]["testgruppe"] = ["m_maj_dv01"]
	o.lightmaps["levels"]["m_maj_dv01"] = {"1": 60.0, "2": 20.0}
	rt.call_api(vm, "FRM_SETGROUPLIGHTMAP", [["str", "testgruppe"], ["num", 1]])
	check(absf(o.lightmap_factor("m_maj_dv01", 1) - 1.0 / 3.0) < 0.01 and o.lightmap_level("m_maj_dv01") == 1,
		"FRM_SetGroupLightmap: alle Mitglieder der Gruppe auf Stufe 1 (dunkler)")
	if mi:
		var mat2 := mi.get_active_material(0) as BaseMaterial3D
		var base2: Color = mat2.get_meta("lm_base", Color.WHITE)
		check(absf(mat2.albedo_color.r - base2.r / 3.0) < 0.01, "Gruppenstufe abgedunkelt")
	rt.call_api(vm, "FRM_SETGROUPLIGHTMAP", [["str", "testgruppe"], ["num", 0]])
	if mi:
		var mat3 := mi.get_active_material(0) as BaseMaterial3D
		check(absf(mat3.albedo_color.r - (mat3.get_meta("lm_base") as Color).r) < 0.01, "Stufe 0 = Ausgangshelligkeit")
	# echte CZECH1-Daten (falls vorhanden): Licht aus = dunkler
	var cz := FileAccess.open(OrigLevel.cache_path("CZECH1") + "/lightmaps.json", FileAccess.READ)
	if cz:
		var d = JSON.parse_string(cz.get_as_text())
		var lv = d["levels"].get("Object30", {})
		check(float(lv.get("2", 99)) < float(lv.get("1", 0)), "CZECH1 nadrazi11: Stufe 1 (Licht aus) dunkler als Stufe 0",
			str(lv))
		check(d["levels"].has("la_zasten_.Rectangle01"), "CZECH1: Mitglied mit unvollständigen Sätzen aufgenommen (Median)")
		check((d["groups"].get("nadrazi11", []) as Array).has("la_zasten_.Rectangle01"), "CZECH1 Gruppe nadrazi11 aus 0xB810")


func _face_tests(rt, m) -> void:
	check(SoldierModel.face_material_name("E_F019.BMP") and SoldierModel.face_material_name("e_f0w1.bmp")
		and not SoldierModel.face_material_name("E_GE_LLFR.BMP"), "Gesichtsmaterial erkannt (E_Fnnn)")
	check(SoldierModel.load_face("e_f054") != null and SoldierModel.load_face("e_f073.bmp") != null,
		"Skript-Gesichter im Cache (fmt_faces.py)")
	# Figur mit Gesichtsmaterial: ein Gegner (Originalfigur ge*/it*/…) oder ein Truppmitglied
	var target: Soldier = null
	for s in m.get_tree().get_nodes_in_group("soldiers"):
		var so := s as Soldier
		if so and so.model and is_instance_valid(so.model.orig_figure) and so.model.face_surfaces() >= 0:
			for mi in so.model.orig_figure.find_children("*", "MeshInstance3D", true, false):
				var mm := mi as MeshInstance3D
				for i in (mm.mesh.get_surface_count() if mm.mesh else 0):
					var mat := mm.get_active_material(i)
					if mat and SoldierModel.face_material_name(String(mat.get_meta("face_base", mat.resource_name))):
						target = so
			if target:
				break
	check(target != null, "Figur mit Gesichtsmaterial gefunden")
	if target == null:
		return
	var vm := _vm(rt, m)
	vm.vars["A"] = target
	var before: int = rt.face_switches
	rt.call_api(vm, "FRM_SWITCHFACETEXTURE", [["var", "A"], ["str", "e_f054"]])
	check(rt.face_switches == before + 1 and not rt.stubbed.has("FRM_SWITCHFACETEXTURE"), "FRM_SwitchFaceTexture wirkt (nicht stumm)")
	var ok := false
	for mi in target.model.orig_figure.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		for i in (mm.mesh.get_surface_count() if mm.mesh else 0):
			var mat := mm.get_surface_override_material(i) as BaseMaterial3D
			if mat and mat.has_meta("face_base"):
				ok = mat.albedo_texture == SoldierModel.load_face("e_f054")
	check(ok and target.model.face_texture == "e_f054", "Gesichtsmaterial trägt e_f054")
	rt.call_api(vm, "FRM_SWITCHFACETEXTURE", [["var", "A"], ["str", "gibt_es_nicht"]])
	check(rt.face_missing.has("gibt_es_nicht") and target.model.face_texture == "e_f054", "fehlende Textur: Gesicht bleibt, Diagnose")


func _optimized_tests(rt, m) -> void:
	var vm := _vm(rt, m)
	rt.call_api(vm, "HUMAN_SETOPTIMIZED", [["num", 1]])
	check(rt.noop_calls.has("HUMAN_SETOPTIMIZED") and not rt.stubbed.has("HUMAN_SETOPTIMIZED"),
		"HUMAN_SetOptimized belegt wirkungslos (0x5AF5C0), nicht stumm")


func _target_tests(rt, m) -> void:
	var root: Node3D = m.dynamic_root
	var hand := Node3D.new()
	var gun := Node3D.new()
	var tgt := Node3D.new()
	for n in [hand, gun, tgt]:
		root.add_child(n)
	hand.global_position = Vector3(0, 60, 0)
	tgt.global_position = Vector3(5, 60, 0)
	var vm := _vm(rt, m)
	vm.vars["G"] = gun
	vm.vars["H"] = hand
	vm.vars["T"] = tgt
	rt.call_api(vm, "FRM_TELEPORTNEARFRAME", [["var", "G"], ["var", "H"]])
	rt.call_api(vm, "FRM_SETTARGET", [["var", "G"], ["var", "T"], ["num", 1]])
	hand.global_position = Vector3(0, 61, 0)
	await frames(3)
	var fwd := -gun.global_transform.basis.z
	var want := (tgt.global_position - gun.global_position).normalized()
	check(gun.global_position.distance_to(hand.global_position) < 0.01, "FRM_SetTarget: Waffe folgt der Hand")
	check(fwd.dot(want) > 0.99, "FRM_SetTarget: Waffe zeigt auf das Ziel")
	rt.call_api(vm, "FRM_SETTARGET", [["var", "G"], ["var", "T"], ["num", 0]])
	hand.global_position = Vector3(0, 63, 0)
	await frames(2)
	check(not rt.aim_links.has(gun) and gun.global_position.y < 62.0, "FRM_SetTarget(false) löst die Verknüpfung")
	check(not rt.stubbed.has("FRM_SETTARGET"), "FRM_SetTarget nicht stumm")
	for n in [hand, gun, tgt]:
		n.queue_free()


func _weather_tests(rt, m) -> void:
	var vm := _vm(rt, m)
	rt.call_api(vm, "WEATHER_SETCOLOROUT", [["num", 56], ["num", 57], ["num", 63], ["num", 0]])
	rt.call_api(vm, "WEATHER_SETSPACE", [["num", 15], ["num", 15]])
	rt.call_api(vm, "WEATHER_SETDIR", [["num", 10], ["num", -100], ["num", -70]])
	rt.call_api(vm, "WEATHER_SETMODE", [["num", 1]])
	rt.call_api(vm, "WEATHER_SETON", [["num", 1]])
	var p: GPUParticles3D = rt._snow
	check(p != null, "Niederschlag erzeugt")
	if p == null:
		return
	var pm := p.process_material as ParticleProcessMaterial
	check(pm.direction.distance_to(Vector3(10, -100, 70).normalized()) < 0.01, "WEATHER_SetDir: Fallrichtung (z gespiegelt)")
	check(absf(pm.emission_box_extents.x - 15.0) < 0.01, "WEATHER_SetSpace: Volumen 15 m")
	check(pm.color_ramp != null, "WEATHER_SetColorOut: Farbverlauf zur Endfarbe")
	for c in ["WEATHER_SETDIR", "WEATHER_SETSPACE", "WEATHER_SETCOLOROUT"]:
		check(not rt.stubbed.has(c), c + " nicht stumm")
	rt.call_api(vm, "WEATHER_SETON", [["num", 0]])


func _shift_cloud_deco_tests(rt, m) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.material = StandardMaterial3D.new()
	m.dynamic_root.add_child(mi)
	var vm := _vm(rt, m)
	vm.vars["R"] = mi
	rt.call_api(vm, "FRM_SETSHIFTING", [["var", "R"], ["num", 1], ["num", 0]])
	await frames(10)
	var o1: float = rt.shift_offset(mi)
	check(o1 > 0.0 and not rt.stubbed.has("FRM_SETSHIFTING"), "FRM_SetShifting verschiebt die Textur", "%.3f" % o1)
	rt.call_api(vm, "FRM_SETSHIFTING", [["var", "R"], ["num", 0], ["num", 1]])
	await frames(5)
	check(absf(rt.shift_offset(mi) - o1) < 0.05 and not rt._shifting.has(mi), "FRM_SetShifting(false) hält an")
	mi.queue_free()
	rt.call_api(vm, "CSC_RUNCLOUDER", [["num", 1]])
	check(rt._clouder != null and rt._clouder.visible and not rt.stubbed.has("CSC_RUNCLOUDER"), "CSC_RunClouder: Wolkenschatten an")
	rt.call_api(vm, "CSC_RUNCLOUDER", [["num", 0]])
	check(rt._clouder == null or not rt._clouder.visible, "CSC_RunClouder(false): aus")
	rt.call_api(vm, "DECORATOR_SETON", [["num", 0]])
	var vis := 0
	for g in rt.orig.grass_nodes:
		if is_instance_valid(g) and g.visible:
			vis += 1
	check(vis == 0 and not rt.stubbed.has("DECORATOR_SETON"), "DECORATOR_SetOn(false): Bewuchs aus")
	rt.call_api(vm, "DECORATOR_SETON", [["num", 1]])
	rt.orig.apply_grass_setting()


func _report_tests(rt) -> void:
	var p := "res://test_output/b035_silent_probe.txt"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	rt.write_silent_report(p, "no1_leuchtturm")
	var txt := FileAccess.get_file_as_string(p)
	check(txt.contains("wirkungslos\tHUMAN_SETOPTIMIZED"), "Bericht: SetOptimized unter „wirkungslos“ mit Beleg")
	check(not txt.contains("B-035"), "Bericht: keine stummen B-035-Befehle mehr", txt.substr(0, 300))
