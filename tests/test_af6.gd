extends "res://tests/test_gameplay.gd"
## AFRICA6 „Raubvögel“ (Bordschützen in der Ju 88): Flugbahn, Sitze, Jäger, Schadensmodell, Sieg per Originalskript.
##   tools\godot.cmd --headless -- --mission=af6_raubvoegel --autoplay=test_af6


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.get("ju88") != null, "Ju 88 (Akteur Typ 34) gefunden")
	if m == null or m.ju88 == null:
		_finish()
		return
	check(m._path.size() > 5000 and absf(m._path.back()[0] - 199.84) < 0.2, "Original-Flugbahn #aircraftA1..6 (≈200 s)",
		"%d Keys, Ende %.2f s" % [m._path.size(), m._path.back()[0] if not m._path.is_empty() else 0.0])
	# Intro-Sequenz (cutletadlo_af5: Ju 88 während der Sequenz ausgeblendet) wie per Leertaste überspringen
	var skipped := false
	for i in 900:
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
			skipped = true
		if skipped and m.ju88.visible and not m.runtime.in_cutscene:
			break
		await frames(5)
	check(skipped, "Intro-Sequenz (CSC_RunCutscene(2)) gestartet und übersprungen")
	await seconds(0.5)
	check(m.ju88.visible, "Originalskript schaltet die Ju 88 nach der Sequenz ein (FRM_SetON)")
	check(m.fighters.size() >= 5 and m.fighters.size() <= 7, "SetActorState(ju88, n): %d Jäger" % m.fighters.size())
	check(is_equal_approx(m.damage_mult, 0.4 + 0.2 * Game.difficulty()) , "SetupJunkers88(40+20·Schwierigkeit, 100)", str(m.damage_mult))
	var s: Soldier = m.squad.leader()
	check(s.mounted == m.ju88 and s.current_weapon() != null and s.current_weapon().data.display_name.begins_with("MG"),
		"Spieler an Sitz 1 mit Original-MG", s.current_weapon().data.display_name if s.current_weapon() else "-")
	var p0: Vector3 = m.ju88.global_position
	var t0: float = m.flight_t
	await seconds(1.0)
	var v: float = m.ju88.global_position.distance_to(p0) / maxf(m.flight_t - t0, 0.01)
	check(v > 20.0 and v < 90.0, "Ju 88 fliegt (%.0f m/s; Original im Mittel 41,5)" % v)
	check(s.global_position.distance_to(m.ju88.global_position) < 6.0, "Schütze fliegt mit")
	# Jäger abschießen (Treffer über die Ballistik-Schnittstelle)
	m.flight_t = 20.0
	await frames(3)
	var f = m.fighters[0]
	var hits := 0
	while not f.down and hits < 200:
		f.on_bullet_hit(72.5, s)        # MG 81: Originalschaden 725 → 72,5
		hits += 1
	check(f.down and hits >= 8, "Jäger nach %d MG-Treffern abgeschossen" % hits)
	# Schaden an der Ju 88 nur in Feuerfenstern
	var hp0: float = m.ju88_health
	var win: Dictionary = {}
	for ff in m.fighters:
		if not ff.down and not ff.windows.is_empty():
			win = ff.windows[0]
			break
	if not win.is_empty():
		m.flight_t = float(win["start_s"]) + 0.05
		await seconds(0.8)
		var nf := 0
		for ff in m.fighters:
			if is_instance_valid(ff) and ff.firing(m.flight_t):
				nf += 1
		check(m.ju88_health < hp0, "Jäger im Feuerfenster beschädigt die Ju 88", "%.0f -> %.0f, t=%.2f, Fenster %s, feuernd %d, sichtbar %s" % [
			hp0, m.ju88_health, m.flight_t, str(win), nf, m.ju88.visible])
	# Sieg: Ju 88 erreicht den Dummy AF5_obj (< 500 m, Original ≈ 173,6 s)
	m.ju88_health = 5000.0
	m.flight_t = 172.0
	for i in 400:
		await frames(5)
		if m.finished:
			break
	check(m.finished and Game.last_result.get("success", false), "Schlucht durchflogen: Mission erfolgreich (Originalskript)",
		str(Game.last_result.get("reason", "")) + " t=%.1f" % m.flight_t)
	_finish()
