extends "res://tests/test_gameplay.gd"
## B-026 / AP-4: Schwierigkeitsgrad → Gegnerwerte wie hd2.exe 0x5A8990 (nur Gegner, Einzelspieler-Originalmissionen).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_difficulty


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.runtime != null, "a1_blizzard geladen")
	if m == null:
		_finish()
		return
	# --- Tabelle (reine Funktion) ---
	var base := {"health": 200, "strength": 80, "endurance": 70, "morale": 80, "shooting": 64, "skill5_unknown": 80,
		"stealth": 50, "first_aid": 30, "lockpick": 20, "sight_range": 35, "hear_range": 45}
	var soll_tab := {
		1: {"health": 140.0, "strength": 80, "endurance": 70, "morale": 72.0, "shooting": 44.8, "skill5_unknown": 56.0,
			"stealth": 35.0, "first_aid": 21.0, "lockpick": 14.0},
		2: {"health": 170.0, "strength": 80, "endurance": 70, "morale": 76.0, "shooting": 54.4, "skill5_unknown": 68.0,
			"stealth": 42.5, "first_aid": 25.5, "lockpick": 17.0},
		3: {"health": 200, "strength": 80, "endurance": 70, "morale": 80, "shooting": 64, "skill5_unknown": 80,
			"stealth": 50, "first_aid": 30, "lockpick": 20},
		4: {"health": 200, "strength": 80, "endurance": 100, "morale": 100, "shooting": 100, "skill5_unknown": 100,
			"stealth": 100, "first_aid": 100, "lockpick": 100},
	}
	for st in [1, 2, 3, 4]:
		var p := OrigMission._apply_difficulty(base, st)
		var bad := []
		for k in soll_tab[st]:
			if not is_equal_approx(float(p[k]), float(soll_tab[st][k])):
				bad.append("%s=%s (soll %s)" % [k, p[k], soll_tab[st][k]])
		check(bad.is_empty(), "0x5A8990 Stufe %d: Werte nach Tabelle" % st, str(bad))
		check(p["sight_range"] == 35 and p["hear_range"] == 45, "Stufe %d: Sicht/Gehör (Index 9–11) unverändert" % st)
	check(base["health"] == 200 and base["morale"] == 80, "Grundwerte werden nicht verändert (Kopie)")

	# --- Wirkung im Spiel: Gegner, Verbündete, Trupp ---
	var rt := m.runtime
	var gg := rt.actors.get("GATE_GUARD") as Soldier
	var rebel := rt.actors.get("REBEL") as Soldier
	var hale := m.squad.leader()
	var hale_hp := hale.max_health
	var p0: Dictionary = gg.get_meta("orig_params_base", {})
	check(not p0.is_empty(), "Torwache: Grundwerte aus actors.bin", str(p0.get("health")))
	var reb_hp := -1.0
	for st in [1, 2, 3, 4]:
		Game.profile["difficulty"] = st
		m._apply_orig_params(gg, "Gate_Guard")
		m._apply_orig_params(rebel, "Rebel")
		var ex: Dictionary = soll_tab[st]
		var k_hp := float(p0["health"]) * (float(ex["health"]) / 200.0)
		var gb := gg.get_node("EnemyBrain") as EnemyBrain
		var morale_soll: float = 100.0 if st == 4 else float(p0["morale"]) * {1: 0.9, 2: 0.95, 3: 1.0}[st]
		var shoot_soll: float = 100.0 if st == 4 else float(p0["shooting"]) * {1: 0.7, 2: 0.85, 3: 1.0}[st]
		check(is_equal_approx(gg.max_health, k_hp * OrigMission.HP_SCALE), "Stufe %d: Torwache Gesundheit" % st,
			"%.2f (soll %.2f)" % [gg.max_health, k_hp * OrigMission.HP_SCALE])
		check(is_equal_approx(gb.morale, morale_soll), "Stufe %d: Torwache Moral" % st, "%.1f (soll %.1f)" % [gb.morale, morale_soll])
		check(is_equal_approx(gb.accuracy_skill, clampf(shoot_soll / 100.0 * 0.7, 0.1, 0.9)), "Stufe %d: Torwache Treffsicherheit" % st,
			"%.3f (Schießen %.1f)" % [gb.accuracy_skill, shoot_soll])
		var rb := rebel.get_node("EnemyBrain") as EnemyBrain
		if reb_hp < 0.0:
			reb_hp = rebel.max_health
		check(is_equal_approx(rebel.max_health, reb_hp) and is_equal_approx(rb.morale, float(rebel.get_meta("orig_params_base", {}).get("morale", 80))),
			"Stufe %d: Sygurd (verbündet) unverändert" % st, "%.1f HP" % rebel.max_health)
		check(is_equal_approx(hale.max_health, hale_hp), "Stufe %d: Trupp unverändert" % st)
	check((gg.get_node("EnemyBrain") as EnemyBrain).morale >= 90.0, "Sehr schwer: Moral 100 → keine Panik (≥ 90)")
	Game.profile["difficulty"] = 3
	_finish()
