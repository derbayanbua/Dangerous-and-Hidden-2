extends "res://tests/test_gameplay.gd"
## 0.10.1 Verbündeten-KI (docs/AI_AUDIT_ALLY.md): Operation Schwerttänzer (NORMANDY2), amerikanische Verbündete Ally_1–5.
##   tools\godot.cmd --headless -- --mission=no2_schwerttaenzer --autoplay=test_ally_no2
## Prüft: Verbündete sind bewaffnet (items.dat), neutral (Fraktion 2 nach hd2.exe 0x5A8820), HUMAN_IllFire/HUMAN_Attack auf
## einen Deutschen = Feuern von der Stellung (keine Bewegung, Skriptsteuerung bleibt, Haltung bleibt), Gegner-Attack auf den
## Verbündeten hält ebenfalls die Stellung. Trupp unverwundbar.


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	m.finished = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for i in 1800:
		if m.nav_ready:
			break
		await get_tree().process_frame
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health

	# 0) Seite 4 (ARCTIC1 „Rebel“): Fraktion Spielerseite, Gegnerziel, nicht im Trupp (--mission=a1_blizzard)
	var reb := rt.actors.get("REBEL") as Soldier
	if reb:
		check(reb.team == Soldier.TEAM_ALLIED, "Rebel (Seite 4) = Spielerseite")
		check(not m.squad.members.has(reb), "Rebel nicht im Trupp (Zählung _PlayerInRange/alle überleben)")
		var axis := get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_AXIS)
		var cand: Array = []
		if not axis.is_empty():
			cand = (axis[0].get_node("Perception") as Perception).enemy_candidates()
		check(cand.has(reb), "Gegner führen Rebel als mögliches Ziel")
		check(reb.get_node("EnemyBrain") is AllyBrain, "Rebel skriptgesteuert (AllyBrain)")
		_finish()
		return

	# 1) Bewaffnung und Fraktion aller Verbündeten
	var allies: Array = []
	for n in ["Ally_1", "Ally_2", "Ally_3", "Ally_4", "Ally_5"]:
		var a := rt.actors.get(String(n).to_upper()) as Soldier
		check(a != null, "%s vorhanden" % n)
		if a == null:
			continue
		allies.append(a)
		check(a.team == Soldier.TEAM_NEUTRAL, "%s neutral (Seite 3)" % n)
		check(a.current_weapon() != null, "%s bewaffnet" % n,
			a.current_weapon().data.id if a.current_weapon() else "keine Waffe")
		check(a.get_node("EnemyBrain") is AllyBrain, "%s mit AllyBrain" % n)
	if allies.is_empty():
		_finish()
		return
	var ally := allies[0] as Soldier
	ally.max_health = 100000.0
	ally.health = ally.max_health
	var ab := ally.get_node("EnemyBrain") as EnemyBrain

	# Ziel: nächster lebender Deutscher
	var ger: Soldier
	var best := INF
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_AXIS):
		var g := n as Soldier
		if g and g.alive and g.global_position.distance_to(ally.global_position) < best:
			best = g.global_position.distance_to(ally.global_position)
			ger = g
	check(ger != null, "Deutscher als Ziel gefunden", "%.0f m" % best)
	if ger == null:
		_finish()
		return
	ger.max_health = 100000.0      # Ziel lebt über die ganze Probe
	ger.health = ger.max_health
	var gb := ger.get_node("EnemyBrain") as EnemyBrain

	# Skripte beider Figuren anhalten (Probe ohne Originalablauf)
	for f in [ally, ger]:
		var vm = rt.vm_for(f)
		if vm:
			vm.paused = true
	ab.suspended = false
	gb.suspended = false
	ab.script_control = true
	ally.stance_request = Soldier.Stance.CROUCH      # HUMAN_SETMODE_Crouch: Stellung
	await seconds(1.0)

	# 2) HUMAN_Attack(Deutscher, 3000) → feuert von der Stellung
	var w := ally.current_weapon()
	var shots0 := w.reserve + w.in_mag if w else 0
	var pos0 := ally.global_position
	ab.script_attack_order(ger, 3.0, false)
	var fired := false
	var t := 0.0
	var maxd := 0.0
	while t < 4.0 and not ab.attack_done():
		await seconds(0.1)
		t += 0.1
		maxd = maxf(maxd, ally.global_position.distance_to(pos0))
		if w and w.reserve + w.in_mag < shots0:
			fired = true
	check(ab.attack_done(), "HUMAN_Attack meldet Ende (Skript läuft weiter)", "%.1f s" % t)
	check(fired, "Verbündeter feuert auf den Deutschen")
	check(maxd < 0.6, "Verbündeter hält die Stellung", "%.2f m bewegt" % maxd)
	check(ab.script_control, "Skriptsteuerung bleibt (kein freier Kampfautomat)")
	check(ab.state != EnemyBrain.State.COMBAT, "kein Kampfzustand der eigenen KI")
	await seconds(2.0)
	check(ally.global_position.distance_to(pos0) < 0.6, "nach dem Angriff weiter in Stellung")

	# 3) HUMAN_IllFire auf einen Frame (Deckungsfeuer)
	shots0 = w.reserve + w.in_mag if w else 0
	var dummy := Node3D.new()
	m.add_child(dummy)
	dummy.global_position = ger.global_position + Vector3(2, 0, 0)
	ab.script_attack_order(dummy, 1.5, true)
	t = 0.0
	while t < 3.0 and not ab.attack_done():
		await seconds(0.1)
		t += 0.1
	check(w != null and w.reserve + w.in_mag < shots0, "HUMAN_IllFire: Deckungsfeuer auf den Frame")
	check(ally.global_position.distance_to(pos0) < 0.6, "IllFire ohne Positionswechsel")

	# 4) Tod des Ziels beendet den Angriff
	ger.max_health = 50.0
	ab.script_attack_order(ger, 20.0, false)
	await seconds(0.3)
	ger.die(null)
	await seconds(0.3)
	check(ab.attack_done(), "Angriff endet mit dem Tod des Ziels")

	# 4b) Funker-Geste HUMAN_SetAnim("%%Radek2a") (r_n2_ally1_end.scr): Originalclip orig_cache/anims/%radek2a.hda
	check(rt.anim.set_animation(ally, "%%Radek2a", 100, false, true), "Geste %%Radek2a abspielbar")

	# 5) Gegner-Attack auf den Verbündeten (r_n2_blue_7 OnSignal(1)) → Gegner feuert, Verbündeter neutral
	var g2: Soldier
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_AXIS):
		var g := n as Soldier
		if g and g.alive:
			g2 = g
			break
	if g2:
		var vm2 = rt.vm_for(g2)
		if vm2:
			vm2.paused = true
		var gb2 := g2.get_node("EnemyBrain") as EnemyBrain
		gb2.suspended = false
		gb2.script_control = true
		var gp := g2.global_position
		gb2.script_attack_order(ally, 1.0, false)
		check(gb2.script_control, "Gegner-Attack auf Neutralen bleibt Skriptfeuer (Original: Erwiderung per Signal)")
		await seconds(1.5)
		check(g2.global_position.distance_to(gp) < 0.6, "Gegner hält beim Erwidern die Stellung")
	_finish()
