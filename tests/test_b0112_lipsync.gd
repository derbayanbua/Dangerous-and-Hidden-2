extends "res://tests/test_systems.gd"
## B-052 / 0.11.2: Gesichtsanimation zu Sprachaufnahmen (LipSync).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_b0112_lipsync


func _pick_id() -> String:
	var idx_path := OrigLevel.cache_root() + "/dabing/index.json"
	if not FileAccess.file_exists(idx_path):
		return ""
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
	var frames: Dictionary = idx.get("frames", {})
	for id in frames:
		if int(frames[id]) >= 100 and FileAccess.file_exists(OrigLevel.cache_root() + "/sounds/%s.wav" % id):
			return id
	return ""


func _w(mi: MeshInstance3D, nm: String) -> float:
	var i := mi.find_blend_shape_by_name(nm)
	return mi.get_blend_shape_value(i) if i >= 0 else -1.0


func _run() -> void:
	for i in 900:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	var lead: Soldier = m.squad.leader()
	m.controller.set_active(lead)

	# Formel (hd2.exe 0x71EE00): je Kanal Summe der Ziele 1..n = 1 bei Ziel 0 = 0
	var wf := LipSync.weights_of(PackedFloat32Array([0.3, 0.6, 0.2, 0.7, 0.9, 0.4]))
	var s0: float = wf["m0_1"] + wf["m0_2"] + wf["m0_3"] + wf["m0_4"]
	var s1: float = wf["m1_1"] + wf["m1_2"] + wf["m1_3"]
	var s2: float = wf["m2_1"] + wf["m2_2"] + wf["m2_3"]
	check(is_equal_approx(s0, 1.0) and is_equal_approx(s1, 1.0) and is_equal_approx(s2, 1.0), "Gewichte je Kanal = 1",
		"%.3f %.3f %.3f" % [s0, s1, s2])

	var id := _pick_id()
	check(id != "", "Gesichtsdaten + Aufnahme im Cache", id)
	var d := LipSync.load_data(id)
	check(d.size() >= 8 and d.size() == 8 + 8 * d.decode_u32(0) and d.decode_u32(4) == 1, "Datei geladen (Kopf/Größe)",
		"%d Bilder" % (d.decode_u32(0) if d.size() >= 8 else 0))
	var ms := LipSync.face_meshes(lead)
	check(not ms.is_empty(), "Figur hat Morph-Blendshapes", str(ms.size()))
	if id == "" or ms.is_empty():
		_finish()
		return
	var mi: MeshInstance3D = ms[0][0]

	var p := OrigAudio.play_file(id + ".wav", lead.global_position, 3.0, 50.0, 1.0, lead, false, &"Voice", false)
	check(p != null, "Aufnahme spielt")
	var ls := LipSync.start(lead, id + ".wav", p)
	check(ls != null, "Treiber gestartet")
	var seen := {}
	var maxw := 0.0
	for i in 90:
		await get_tree().process_frame
		var a := _w(mi, "m0_1") + _w(mi, "m0_2")
		seen[snappedf(a, 0.01)] = true
		maxw = maxf(maxw, a)
	check(seen.size() >= 4 and maxw > 0.05, "Mundgewichte ändern sich während des Satzes",
		"%d Werte, max %.2f" % [seen.size(), maxw])
	check(is_instance_valid(ls) and ls.updates > 0, "Gewichte gesetzt (Kameranähe)")

	# Ende: Klang aus -> 200 ms Schließen -> Mund zu, Treiber weg
	p.stop()
	for i in 60:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	check(not is_instance_valid(ls) or ls.is_queued_for_deletion(), "Treiber nach Ende beendet")
	check(_w(mi, "m0_1") < 0.001 and _w(mi, "m0_2") < 0.001, "Mund nach Ende zu",
		"%.3f %.3f" % [_w(mi, "m0_1"), _w(mi, "m0_2")])

	# Fehlende Daten / Figur ohne Morph -> nichts, kein Fehler
	check(LipSync.start(lead, "12345678.wav", p) == null, "Fehlende Datei -> kein Treiber")
	check(LipSync.start(lead, "abc.wav", p) == null, "Ungültiger Name -> kein Treiber")
	var bare := Node3D.new()
	m.add_child(bare)
	check(LipSync.start(bare, id + ".wav", p) == null, "Figur ohne Blendshapes -> kein Treiber")
	bare.queue_free()
	check(OrigAudio.speak_event(null, 0) == 0.0, "speak_event ohne Sprecher fehlerfrei")
	_finish()
