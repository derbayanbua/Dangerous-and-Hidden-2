extends "res://tests/test_gameplay.gd"
## Original-Mehrspielerstile (docs/re_notes_multiplayer.md) auf Original-MP-Karten, nur Server:
## Deathmatch (AFRICA1_MP), Besetzung (BURMA1_MP_ZONE), HD2-Aufgaben (ARCTIC1_OBJ).
##   tools\godot.cmd --headless -- --autoplay=test_mp_modes


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1800.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _host(map: String, m: int, extra := {}) -> Node:
	var cfg := {"name": "Test", "map": map, "mode": m, "max_players": 8, "time_limit_min": 0, "score_limit": 0,
		"respawn_s": 5, "password": "", "port": Net.PORT + 10, "friendly_fire": false, "warmup_s": 0}
	cfg.merge(extra, true)
	Net.local_name = "Host"
	Net.local_class = 2     # Gewehrschütze
	if not Net.host(cfg):
		return null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		var mm := Game.current_mission()
		if mm and Net._soldiers.has(1):
			return mm
	return null


func _run() -> void:
	await frames(5)
	check(Game.MP_MAPS.has("mp_africa1_mp") and Game.MP_MAPS.has("mp_burma1_mp_zone") and Game.MP_MAPS.has("mp_arctic1_obj"),
		"Original-MP-Karten registriert (%d Karten inkl. Arena)" % Game.MP_MAPS.size())
	check(int(Game.MISSIONS["mp_burma1_mp_zone"].get("mp_mode", -1)) == Net.Mode.OCCUPATION, "Spielstil je Karte aus mpmaplist.txt")

	# --- Deathmatch ---
	var m = await _host("mp_africa1_mp", Net.Mode.DEATHMATCH)
	check(m != null and m.mp_spawns().size() == 32, "AFRICA1_MP: 32 Original-Spawnpunkte", str(m.mp_spawns().size()) if m else "-")
	if m:
		var s: Soldier = Net._soldiers[1]
		check(s.weapons[0] != null and s.has_meta("mp_class"), "Original-Klasse (Gewehrschütze)",
			"%s / %s" % [s.weapons[0].data.display_name if s.weapons[0] else "-", s.get_meta("mp_class", "-")])
		check(s.has_meta("protect_until"), "Spawnschutz gesetzt")
		s.apply_hit(50.0, &"torso", null, Vector3.FORWARD)
		check(is_equal_approx(s.health, s.max_health), "Kein Schaden während des Spawnschutzes")
		s.set_meta("protect_until", 0)
		s.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
		await frames(3)
		check(int(Net.players[1]["score"]) == Net.PTS_SUICIDE, "Selbsttötung −1", str(Net.players[1]["score"]))
	Net.leave(false)
	await frames(10)

	# --- Besetzung ---
	m = await _host("mp_burma1_mp_zone", Net.Mode.OCCUPATION, {"respawn_s": 5})
	check(m != null and m.mp_zones().size() == 6, "BURMA1_MP_ZONE: 6 Zonen", str(m.mp_zones().size()) if m else "-")
	if m:
		await seconds(1.0)
		var zs: Array = m.mp_zones()
		var s2: Soldier = Net._soldiers[1]
		s2.set_meta("protect_until", 0)
		var team := s2.team
		var own_zone := -1
		for i in zs.size():
			if Net.zone_contains(zs[i], s2.global_position) or (zs[i]["slots"] as Array).any(func(p): return (p["pos"] as Vector3).distance_to(s2.global_position) < 2.0):
				own_zone = i
		check(own_zone >= 0 and Net.zone_owner[own_zone] == team, "Spawn an einer eigenen Zone", str(own_zone))
		# feindliche Zone einnehmen (FRONTLINE beachten: Nachbarzone)
		var target := -1
		for i in zs.size():
			if Net.zone_owner[i] != team and Net.zone_owner[i] != -1 and Net._attackable(m, i, team) and zs[i]["capturable"]:
				target = i
				break
		check(target >= 0, "Angreifbare gegnerische Zone gefunden")
		if target >= 0:
			var cap: float = zs[target]["capture_time"]
			var score0 := int(Net.players[1]["score"])
			var ts0: float = Net.team_score[team]
			for i in int((cap * 1.15 + Net.ZONE_START_DELAY_S) * 60.0):     # Einnahme erst nach 5 s Rundenzeit
				s2.global_position = (zs[target]["xf"] as Transform3D).origin + Vector3.UP * 0.5
				s2.velocity = Vector3.ZERO
				await get_tree().physics_frame
				if Net.zone_owner[target] == team:
					break
			check(Net.zone_owner[target] == team, "Zone eingenommen (Einnahmezeit %d s, halb neutral, halb Besitz)" % int(cap))
			check(int(Net.players[1]["score"]) - score0 == Net.ZONE_NEUTRALIZE_PTS + Net.ZONE_CAPTURE_PTS,
				"Punkte: +2 neutralisiert, +5 eingenommen", str(int(Net.players[1]["score"]) - score0))
			check(Net.team_score[team] > ts0, "Team erhält Punkte je gehaltener Zone", "%.3f" % (Net.team_score[team] - ts0))
	Net.leave(false)
	await frames(10)

	# --- HD2-Aufgaben ---
	m = await _host("mp_arctic1_obj", Net.Mode.OBJECTIVES)
	check(m != null and m.mp_objectives().size() == 5, "ARCTIC1_OBJ: 5 Aufgaben (Bomben)", str(m.mp_objectives().size()) if m else "-")
	if m:
		check(m.runtime.vms.size() >= 6, "Original-MP-Skripte laufen", "%d" % m.runtime.vms.size())
		var o: Dictionary = m.mp_objectives()[0]
		var ts1: float = Net.team_score[o["team"]]
		m.set_orig_objective(int(o["index"]), 1)
		await frames(3)
		check(Net.obj_done.has(int(o["index"])) and is_equal_approx(Net.team_score[o["team"]] - ts1, float(o["value"])),
			"Aufgabe erfüllt: %d Punkte für die begünstigte Seite" % int(o["value"]))
		var s3: Soldier = Net._soldiers[1]
		s3.set_meta("protect_until", 0)
		s3.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
		await seconds(7.0)
		var again: Soldier = Net._soldiers.get(1)
		check(again == s3 and not again.alive, "HD2-Aufgaben: kein Wiedereinstieg (Original)")
	Net.leave(false)
	_finish()
