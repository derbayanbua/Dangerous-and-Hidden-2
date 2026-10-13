extends "res://tests/test_gameplay.gd"
## Interaktive Originalakteure (interactive.json) in Arctic 1A: Türen, Leitern, Schalter, Zerstörbares, Kiste.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_interactive


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.interactive != null, "Interaktive Originalakteure eingerichtet")
	if m == null or m.interactive == null:
		_finish()
		return
	var it := m.interactive
	isolate_enemies([])
	check(it.stats.doors >= 6 and it.stats.ladders >= 6 and it.stats.destructibles >= 4 and it.stats.crates >= 1
		and it.stats.switches >= 1, "Türen, Leitern, Schalter, Zerstörbares, Kiste aus interactive.json", str(it.stats))
	var s: Soldier = m.squad.leader()

	# --- Tür ---
	var door: OrigInteractive.OrigDoor = it.controls.get("M_DV_ST")
	check(door != null and door.state == 0, "Tür m_dv_st geschlossen (Originalzustand)")
	if door:
		var before := door.frame.global_transform
		door.interact(s)
		await seconds(2.0)
		check(door.state == 1 and int(door.frame.get_meta("actor_state")) == 1, "Tür öffnet (Zustand 1, _ACTOR_GetState)")
		check(not door.frame.global_transform.is_equal_approx(before), "Türflügel hat sich bewegt (Drehung um die Originalachse)")
		var vm := LsVM.new(LsCompiler.new(), door.frame, m.runtime)
		m.runtime.call_api(vm, "SETACTORSTATE", [["str", "m_dv_st"], ["num", 0]])
		await seconds(2.0)
		check(door.state == 0, "SetActorState(Tür, 0) schließt")
		m.runtime.call_api(vm, "DOOR_LOCK", [["str", "m_dv_st"], ["num", 1]])
		door.interact(s)
		check(door.locked and door._pick_left > 0.0, "Verschlossen: Schloss knacken startet (Dauer aus Fertigkeit)")
		await seconds(door._pick_left + 0.5)
		check(not door.locked, "Schloss geknackt", str(s.training))
		check(float(s.training.get("locks", 0.0)) >= 1.0, "Training: Schlösser")

	# --- Leiter ---
	var ladder: OrigInteractive.OrigLadder = null
	for n in get_tree().get_nodes_in_group("ladders"):
		if not n.at_top:
			ladder = n
			break
	check(ladder != null, "Leiter vorhanden")
	if ladder:
		s.global_position = ladder.bottom + Vector3(0, 0.1, 0)
		await frames(3)
		var y0 := s.global_position.y
		ladder.climb(s)
		check(s.is_climbing(), "Leiter: Klettern beginnt")
		await seconds((ladder.top.y - ladder.bottom.y) / 1.2 + 1.5)
		check(s.global_position.y > y0 + (ladder.top.y - ladder.bottom.y) * 0.7, "Leiter hinaufgeklettert",
			"%.1f -> %.1f (oben %.1f)" % [y0, s.global_position.y, ladder.top.y])

	# --- Zerstörbares (Treibstofftanks, Skript R_arc1A_cisterna6: OnDeath -> SaveGameValue(106, 1)) ---
	var tank: OrigInteractive.OrigDestructible = it.controls.get("M_NADRZ_6")
	check(tank != null, "Treibstofftank m_nadrz_6")
	if tank:
		OrigInteractive.damage_objects(get_tree(), tank.global_position, 6.0, 300.0)
		await seconds(1.0)
		check(tank.destroyed and not tank.frame.visible, "Explosion zerstört den Tank")
		check(m.runtime.game_values.get(106) == 1, "Originalskript OnDeath ausgelöst (SaveGameValue 106)", str(m.runtime.game_values))

	# --- Munitionskiste ---
	var crate: OrigInteractive.OrigCrate = null
	for k in it.controls:
		if it.controls[k] is OrigInteractive.OrigCrate:
			crate = it.controls[k]
	if crate:
		var w := s.weapons[0] if s.weapons[0] != null else s.weapons[1]
		w.reserve = 0
		crate.interact(s)
		check(w.reserve > 0, "Munitionskiste füllt auf", str(w.reserve))

	# --- Schalter ---
	var sw: OrigInteractive.OrigSwitch = null
	for k in it.controls:
		if it.controls[k] is OrigInteractive.OrigSwitch:
			sw = it.controls[k]
	if sw:
		var st0 := sw.state
		sw.interact(s)
		check(sw.state != st0 and int(sw.frame.get_meta("actor_state")) == sw.state, "Schalter wechselt den Zustand (1↔2)")
	_finish()
