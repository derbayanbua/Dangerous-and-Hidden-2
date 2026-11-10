extends "res://tests/test_gameplay.gd"
## fix_0103 (Release 0.10.3): Einsatzgebiet verlassen und automatisches Nachladen.
##   --mission=m01_funkfeuer --autoplay=test_fix0103 --area_guard=1 [--phase=all|reload|area]
##   --mission=af1_spaghetti_airport --autoplay=test_fix0103 --area_guard=1 --phase=border
## Trupp immer unverwundbar. Fahrten (BURMA2/NORMANDY2) prüft probe_gap_drive --strict=1.


func _run() -> void:
	for i in 6000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if m == null:
		check(false, "Mission geladen")
		_finish()
		return
	for s in m.squad.members:
		s.max_health = 1.0e6      # Trupp IMMER unverwundbar
		s.health = s.max_health
	var ph := String(Game.cli.get("phase", "all"))
	if m is OrigMission and (m as OrigMission).runtime:
		(m as OrigMission).runtime.auto_skip = true
		for i in 600:
			if not (m as OrigMission).runtime.in_cutscene and m.controller.input_enabled:
				break
			if (m as OrigMission).runtime.in_cutscene:
				(m as OrigMission).runtime.end_cutscene()
			await frames(10)
	await frames(30)
	if ph in ["all", "reload"]:
		await _reload(m)
	if ph in ["all", "area", "border"]:
		await _area(m, ph == "border")
	_finish()


func _reload(m: Mission) -> void:
	var s: Soldier = m.controller.active
	var w := s.current_weapon()
	check(w != null, "Waffe in der Hand")
	if w == null:
		return
	await frames(int(maxf(w.reload_left, 0.0) * 60.0) + 10)
	w.in_mag = 0
	w.reserve = w.data.magazine_size * 2
	var res0 := w.reserve
	await frames(5)
	check(w.is_reloading(), "Leeres Magazin + Reserve → lädt automatisch nach")
	await frames(int(w.reload_left * 60.0) + 30)
	check(w.in_mag > 0 and w.reserve < res0, "Nachladen abgeschlossen", "mag %d res %d" % [w.in_mag, w.reserve])
	# ohne Reserve kein Nachladen
	w.in_mag = 0
	w.reserve = 0
	await frames(10)
	check(not w.is_reloading(), "Leer ohne Reserve → kein Nachladen")
	w.reserve = w.data.magazine_size
	await frames(int(w.data.reload_empty_time * 60.0) + 30)


func _area(m: Mission, border: bool) -> void:
	var g = m.area_guard
	check(g != null, "Grenzwächter aktiv (Einzelspieler, --area_guard=1)")
	if g == null:
		return
	await frames(30)
	var s: Soldier = m.controller.active
	var home := s.global_position
	print("AREA Modus %s Strecken %d Start %s" % [g.mode, g.segments.size(), home])
	check(g.mode == ("border" if border else "map"), "Grenzart %s" % ("Border-Flächen" if border else "Kartengrenze"), g.mode)
	check(g.is_inside(home), "Startpunkt im Einsatzgebiet")
	var far: Vector3
	if border:
		var r: Rect2 = g.seg_rect
		far = Vector3(r.end.x + 40.0, home.y, r.get_center().y)
		# Stichprobe: Rasterpunkte nahe der Kartenmitte innen, weit außen außen
		check(not g.is_inside(Vector3(r.position.x - 30.0, 0, r.get_center().y)), "Punkt westlich außerhalb der Grenze = außen")
	else:
		var b: AABB = g.map_box
		far = Vector3(b.end.x + 30.0, home.y, b.get_center().z)
	check(not g.is_inside(far), "Zielpunkt außerhalb = außen", str(far))
	# kurz hinaus und wieder zurück: Countdown erscheint und verschwindet, keine Niederlage
	s.process_mode = Node.PROCESS_MODE_DISABLED
	s.global_position = far
	await seconds(1.0)
	check(g.outside and g._label.visible, "Warnung mit Countdown sichtbar", g._label.text)
	check(g._label.text.contains("10") or g._label.text.contains("9"), "Countdown zählt ab 10 s", g._label.text)
	s.global_position = home
	await seconds(1.0)
	check(not g.outside and not g._label.visible and not m.finished, "Zurück im Gebiet → Warnung weg, Mission läuft")
	# hinaus und draußen bleiben → nach 10 s gescheitert
	s.global_position = far
	await seconds(6.0)
	check(not m.finished, "Nach 6 s draußen noch nicht gescheitert")
	await seconds(5.5)
	check(m.finished and not bool(Game.last_result.get("success", true)), "Nach 10 s draußen: Mission gescheitert",
		String(Game.last_result.get("reason", "")))
