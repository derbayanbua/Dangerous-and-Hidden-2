extends "res://tests/test_gameplay.gd"
## Original-Abläufe CZECH4–6 einzeln geprüft (Agent Tschechien-2), mit den Spielwegen statt Zielsetzen:
##   tools\godot.cmd --headless -- --mission=cz4_volksfest --autoplay=test_cz2_parts
##   (ebenso cz5_trink_aus, cz6_abrechnung). Der Trupp ist unverwundbar; Gegner werden über Soldier.apply_hit getötet.
## CZECH4 (CZ4_OD.scr): Fässer la_bar_1..3 (Typ 25, OnDeath → MakeExplosion → Kettenexplosion → dummy_secondary →
##   Ziel 2), Wertsachen (dummy_treasure _PlayerInRange(3) → Ziel 3), alle 49 Gegner tot → Ziel 1, Ziel 4, Sieg.
## CZECH5 (dummy_launcher/ge_11/dummy_pd): Spieler < 120 m → Sequenz 1 → Tiger-Kolonne fährt (HUMAN_Drive); erreicht
##   sie den Ausgang (dummy_pd 25 m) → Sequenz 2 → Signal 16 → Ziel 2 „Niemand darf entkommen“ gescheitert.
## CZECH6 (C5_objective/C5_dokumenty/C5_player_teleporter): Hauptmann C5_G38 töten → Signal 1, Leiche durchsuchen →
##   Dokumente (252) → Ziel 1; Teleporter: Deutsche tot, Trupp an teleportplayer0..3, Russen R01–R20 aktiv;
##   Sendeanlage (1cable_ok, OnUse) → Ziel 4; alle Russen tot → Ziel 2 (+5), Sieg.

var m: OrigMission
var rt: LsRuntime
var god := true
var stealth := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	if m == null or not is_instance_valid(m):
		return
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive:
			continue
		if god and m.squad.members.has(s):
			s.health = s.max_health
		elif stealth and s.team == Soldier.TEAM_AXIS:
			var per: Perception = s.get_node_or_null("Perception")
			if per:
				per.sight_range = 0.01
				per.hear_range = 0.0
				per.awareness.clear()


func lead() -> Soldier:
	return m.squad.leader()


func obj_state(i: int) -> int:
	var o := m.objective(StringName("o%d" % i))
	return o.state if o else -1


func teleport(p: Vector3) -> void:
	var k := 0
	for s in m.squad.members:
		if s.alive and s.vehicle == null:
			s.global_position = p + Vector3((k % 2) * 1.0, 0.3, (k / 2) * 1.0)
			s.velocity = Vector3.ZERO
			k += 1


func kill(s: Soldier) -> void:
	if s and s.alive:
		s.apply_hit(5000.0, &"head", lead(), Vector3.FORWARD)


func wait_until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		await seconds(0.5)
		t += 0.5
		if is_instance_valid(rt) and rt.in_cutscene and not Game.cli.has("noskip"):
			rt.end_cutscene()
	return cond.call()


func axis_alive() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team == Soldier.TEAM_AXIS and not m.squad.members.has(s):
			out.append(s)
	return out


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission() as OrigMission
	check(m != null and m.runtime != null, "Originalteil geladen", Game.current_mission_id)
	if m == null or m.runtime == null:
		_finish()
		return
	rt = m.runtime
	rt.auto_skip = not Game.cli.has("noskip")    # --noskip: Zwischensequenzen laufen wie ohne Abbruch
	for s in m.squad.members:
		s.max_health = 100000.0
		s.health = s.max_health
		var sb = m.squad.brain_of(s)
		if sb:
			sb.roe = SquadBrain.ROE.HOLD_FIRE
	Engine.time_scale = float(Game.cli.get("speed", "2"))
	await seconds(1.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(3.0)
	match Game.current_mission_id:
		"cz4_volksfest":
			await _cz4()
		"cz5_trink_aus":
			await _cz5()
		"cz6_abrechnung":
			await _cz6()
	_finish()


# --- CZECH4 ---------------------------------------------------------------------------------------------------
func _cz4() -> void:
	check(obj_state(1) == Objective.State.ACTIVE, "CZ4: Ziel 1 „Töten Sie die Gegner“ aktiv")
	var bars: Array = []
	for n in get_tree().get_nodes_in_group("destructibles"):
		if n is OrigInteractive.OrigDestructible and String(n.frame.name).to_lower().begins_with("la_bar_"):
			bars.append(n)
	check(bars.size() == 3, "CZ4: drei Treibstofffässer (Typ 25)", str(bars.size()))
	if bars.size() > 0:
		# eine Granate No. 36 (1999/10 m) am ersten Fass – derselbe Weg wie Grenade.explode
		OrigInteractive.damage_objects(get_tree(), (bars[0] as Node3D).global_position, 10.0, 199.9, lead())
	var all_bars := func() -> bool: return bars.all(func(b): return b.destroyed)
	check(await wait_until(all_bars, 10.0), "CZ4: Fässer zerstört (Kettenexplosion über OnDeath → MakeExplosion)",
		"%d/3" % bars.filter(func(b): return b.destroyed).size())
	check(await wait_until(func(): return obj_state(2) == Objective.State.DONE, 10.0), "CZ4: Zusatzziel 2 Fässer erfüllt",
		"Zustand %d, Werte 21/22/23 = %s/%s/%s" % [obj_state(2), rt.game_values.get(21, "-") if "game_values" in rt else "?",
		rt.game_values.get(22, "-") if "game_values" in rt else "?", rt.game_values.get(23, "-") if "game_values" in rt else "?"])
	var tr := rt.find_frame("dummy_treasure")
	check(tr != null, "CZ4: dummy_treasure vorhanden")
	if tr:
		teleport(tr.global_position)
		check(await wait_until(func(): return obj_state(3) == Objective.State.DONE, 10.0), "CZ4: Zusatzziel 3 Wertsachen erfüllt",
			"Zustand %d" % obj_state(3))
	var n0 := axis_alive().size()
	print("CZ4 Gegner lebend: ", n0)
	for e in axis_alive():
		kill(e)
		await seconds(0.1)
	check(await wait_until(func(): return m.finished or not is_instance_valid(m), 60.0), "CZ4: Einsatz endet nach dem Tod aller Gegner")
	var r: Dictionary = Game.last_result
	check(bool(r.get("success", false)), "CZ4: Erfolg", str(r.get("reason", "")))
	for o in r.get("objectives", []):
		print("  Ziel ", o)


# --- CZECH5 ---------------------------------------------------------------------------------------------------
func _cz5() -> void:
	stealth = true          # Kolonne darf nicht alarmiert werden (ge_11 OnAlarm → EndScript)
	check(obj_state(1) == Objective.State.ACTIVE and obj_state(2) == Objective.State.ACTIVE, "CZ5: Ziele 1/2 aktiv")
	var tiger := rt.find_frame("La_TigerEv_1")
	check(tiger is Vehicle, "CZ5: Tiger la_TigerEv_1 als Fahrzeug", str(tiger))
	var launcher := rt.find_frame("dummy_launcher")
	var pd := rt.find_frame("dummy_pd")
	check(launcher != null and pd != null, "CZ5: dummy_launcher / dummy_pd vorhanden")
	if not (tiger is Vehicle) or launcher == null or pd == null:
		return
	var p0 := tiger.global_position
	print("CZ5 Tiger Start ", p0, " launcher ", launcher.global_position, " pd ", pd.global_position, " Abstand ",
		tiger.global_position.distance_to(pd.global_position))
	await seconds(10.0)
	check(tiger.global_position.distance_to(p0) < 3.0, "CZ5: Kolonne wartet, solange kein Spieler < 120 m",
		"%.1f m" % tiger.global_position.distance_to(p0))
	# Spieler 100 m vom dummy_launcher (im Original: Anmarsch von der Startposition)
	var dir := (lead().global_position - launcher.global_position)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var near := launcher.global_position + dir * 100.0
	near.y = lead().global_position.y
	print("CZ5 Spieler-Abstand zum Launcher vorher ", lead().global_position.distance_to(launcher.global_position))
	if lead().global_position.distance_to(launcher.global_position) > 115.0:
		teleport(near)
	var moved := func() -> bool: return tiger.global_position.distance_to(p0) > 15.0
	check(await wait_until(moved, 60.0), "CZ5: Tiger fährt los (Sequenz 1, HUMAN_Drive)", "%.1f m" % tiger.global_position.distance_to(p0))
	var t := 0.0
	while t < 420.0 and is_instance_valid(m) and not m.finished:
		await seconds(5.0)
		t += 5.0
		if is_instance_valid(rt) and rt.in_cutscene and not Game.cli.has("noskip"):
			rt.end_cutscene()
		if int(t) % 30 == 0:
			print("CZ5 t=%.0f Tiger %s Abstand pd %.1f" % [t, tiger.global_position, tiger.global_position.distance_to(pd.global_position)])
			var opel := rt.find_frame("La_OpelE_5")
			var ge11 := rt.find_frame("GE_11") as Soldier
			print("CZ5   Opel %s  GE_11 lebt=%s Fahrzeug=%s  Tiger Fahrer=%s v=%.2f" % [opel.global_position if opel else "-",
				ge11.alive if ge11 else "-", ge11.vehicle.name if ge11 and ge11.vehicle else "-",
				(tiger as Vehicle).driver().name if (tiger as Vehicle).has_method("driver") and (tiger as Vehicle).driver() else "?",
				(tiger as Vehicle).linear_velocity.length()])
	var r: Dictionary = Game.last_result
	check(is_instance_valid(m) == false or m.finished, "CZ5: Kolonne entkommt → Einsatz endet", "t=%.0f s" % t)
	check(not bool(r.get("success", true)), "CZ5: Einsatz gescheitert (Ziel 2 „Niemand darf entkommen“)", str(r.get("reason", "")))


# --- CZECH6 ---------------------------------------------------------------------------------------------------
func _cz6() -> void:
	check(obj_state(1) == Objective.State.ACTIVE, "CZ6: Ziel 1 „Erwerben Sie die Dokumente“ aktiv")
	var g38 := rt.find_frame("C5_G38") as Soldier
	check(g38 != null and g38.alive, "CZ6: Hauptmann C5_G38")
	var r01 := rt.find_frame("C5_R01") as Soldier
	check(r01 != null, "CZ6: Russe C5_R01", "Team %d" % (r01.team if r01 else -1))
	if g38 == null:
		return
	print("CZ6 G38 Gegenstände ", g38.get_meta("orig_loot", []))
	# Sendeanlage zuerst (vor dem Teleport erreichbar)
	var sw: OrigInteractive.OrigSwitch = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is OrigInteractive.OrigSwitch and String(n.frame.name).to_lower() == "1cable_ok":
			sw = n
	check(sw != null, "CZ6: Sendeanlage 1cable_ok (Schalter)")
	if sw:
		teleport(sw.global_position + Vector3(1.0, 0, 0))
		await seconds(0.5)
		sw.interact(lead())
		check(await wait_until(func(): return obj_state(4) == Objective.State.DONE, 10.0), "CZ6: Zusatzziel 4 Sendeanlage erfüllt",
			"Zustand %d" % obj_state(4))
	# Tiger vor den Dokumenten: C5_player_teleporter sprengt la_panther_ (MakeExplosion 10000/5 m)
	var tiger := rt.find_frame("la_panther_")
	if tiger is Vehicle:
		var entry: Interactable = null
		for c in tiger.find_children("*", "Interactable", true, false):
			entry = c
			break
		teleport(tiger.global_position + Vector3(2.5, 0, 0))
		await seconds(0.5)
		if entry:
			entry.interact(lead())
	check(await wait_until(func(): return obj_state(3) == Objective.State.DONE, 10.0),
		"CZ6: Zusatzziel 3 Tiger erobert (Einsteigen → OnUse)", "Zustand %d" % obj_state(3))
	if lead().vehicle:
		(lead().vehicle as Vehicle).leave(lead())
	await seconds(1.0)
	teleport(g38.global_position + Vector3(2.0, 0, 0))
	await seconds(0.5)
	kill(g38)
	await seconds(2.0)
	var loot: Pickups.Loot = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Pickups.Loot and n.corpse == g38:
			loot = n
	check(loot != null, "CZ6: Leiche des Hauptmanns durchsuchbar")
	if loot:
		loot.interact(lead())
	check(OrigInteractive.has_item(lead(), 252), "CZ6: Dokumente (252) im Inventar")
	check(await wait_until(func(): return obj_state(1) == Objective.State.DONE, 15.0), "CZ6: Ziel 1 erfüllt", "Zustand %d" % obj_state(1))
	var tp0 := rt.find_frame("teleportplayer0")
	var tele := func() -> bool: return tp0 != null and lead().global_position.distance_to(tp0.global_position) < 6.0
	check(await wait_until(tele, 15.0), "CZ6: Trupp an teleportplayer0 (C5_player_teleporter)",
		"%.1f m" % (lead().global_position.distance_to(tp0.global_position) if tp0 else -1.0))
	var g22 := rt.find_frame("C5_G22") as Soldier
	check(g22 == null or not g22.alive, "CZ6: Deutsche G22… vom Teleporter getötet")
	check(obj_state(2) == Objective.State.ACTIVE, "CZ6: Ziel 2 „Russische Angriffe abwehren“ aktiv", "Zustand %d" % obj_state(2))
	var rus: Array = []
	for i in range(1, 21):
		var r := rt.find_frame("C5_R%02d" % i) as Soldier
		if r:
			rus.append(r)
	check(rus.size() == 20, "CZ6: 20 Russen", str(rus.size()))
	await seconds(8.0)
	var moving := 0
	for r in rus:
		if r.alive and r.velocity.length() > 0.3:
			moving += 1
	print("CZ6 Russen in Bewegung: ", moving, " Teams: ", rus.map(func(r): return r.team))
	for r in rus:
		kill(r)
		await seconds(0.1)
	check(await wait_until(func(): return obj_state(2) == Objective.State.DONE, 30.0), "CZ6: Ziel 2 erfüllt (C5_RU_deadcounter)",
		"Zustand %d" % obj_state(2))
	check(await wait_until(func(): return not is_instance_valid(m) or m.finished, 30.0), "CZ6: Einsatz endet")
	var res: Dictionary = Game.last_result
	check(bool(res.get("success", false)), "CZ6: Erfolg", str(res.get("reason", "")))
	for o in res.get("objectives", []):
		print("  Ziel ", o)
