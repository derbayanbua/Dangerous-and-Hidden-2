extends "res://tests/test_gameplay.gd"
## Rauchtest für Original-Missionsteile: Level, Akteure, Skripte, Ziele, nicht umgesetzte Skriptbefehle.
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_orig_part [--commandos=1]
## Endet die Mission vorzeitig (z. B. Ziel durch Originalskript als gescheitert gemeldet), werden Grund
## und Zielstände aus Game.last_result ausgegeben.


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null, "Original-Missionsteil geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	var level_parts: int = m.orig.stats.meshes + m.orig.stats.instances if m.orig else 0
	check(m.orig != null and level_parts > 200, "Original-Level", "%d Meshes, %d Instanzen" % [
		m.orig.stats.meshes, m.orig.stats.instances])
	var want := int(Game.cli.get("commandos", "0"))   # 0 = Anzahl laut actors.bin (commando1..4)
	if want == 0:
		for a in m.orig.actors:
			# Spielerstarts: Akteurtyp 10 bzw. „Spawnsingle*“ ohne Definition (NORMANDY, Start aus den Mini-U-Booten)
			if int(a.get("actor_type", -1)) == 10 or String(a.get("name", "")).to_lower().begins_with("spawnsingle"):
				want += 1
		want = clampi(want, 1, 4)
	check(m.squad.members.size() == want, "Kommandos laut Original", "%d von %d" % [m.squad.members.size(), want])
	var rt := m.runtime
	# AFRICA6 ist ein Bordschützen-Einsatz: im Original 13 Skripte, keine Bodengegner/Wegpunkte (Jäger: test_af6)
	var flight := Game.current_mission_id == "af6_raubvoegel"
	check(rt != null and rt.vms.size() > (10 if flight else 50), "Originalskripte laufen", "%d VMs" % (rt.vms.size() if rt else 0))
	check(rt.waypoints.size() > 50 or flight, "KI-Wegpunkte", str(rt.waypoints.size()))
	var enemies := 0
	for a in rt.actors.values():
		if a is Soldier and (a as Soldier).team == Soldier.TEAM_AXIS:
			enemies += 1
	check(enemies > 0 or flight or Game.current_mission_id == "training", "Gegner aus actors.bin", str(enemies))
	var mid := Game.current_mission_id
	rt.auto_skip = true
	if rt.in_cutscene:
		rt.end_cutscene()
	var watch: Node3D = rt.actors.get(String(Game.cli.get("watch", "")).to_upper())
	for i in 20:
		await seconds(0.5)
		if not is_instance_valid(m):
			break
		if is_instance_valid(watch) and watch is Soldier:
			var ws := watch as Soldier
			print("WATCH t=%.1f alive=%s hp=%.0f/%.0f pos=%s team=%d angreifer=%s" % [i * 0.5, ws.alive, ws.health, ws.max_health,
				ws.global_position, ws.team, ws.last_attacker.name if is_instance_valid(ws.last_attacker) else "-"])
		if is_instance_valid(rt) and rt.in_cutscene:
			rt.end_cutscene()
	if not is_instance_valid(m):
		var r: Dictionary = Game.last_result
		print("VORZEITIGES ENDE ", mid, ": ", r.get("reason", "?"), " Erfolg=", r.get("success", false))
		for o in r.get("objectives", []):
			print("  Ziel ", o)
		check(false, "Mission läuft nach dem Start weiter", "Ende: %s" % r.get("reason", "?"))
		print("UNIMPL ", mid, " ?")
		_finish()
		return
	var active := 0
	for o in m.objectives:
		if o.state != Objective.State.INACTIVE:
			active += 1
	check(active >= 1, "Skript aktiviert Missionsziele", "%d von %d aktiv" % [active, m.objectives.size()])
	for o in m.objectives:
		print("  Ziel ", o.id, " ", o.state, " ", o.optional, " ", o.text)
	check(not m.finished, "Mission läuft", str(Game.last_result.get("reason", "")))
	print("Befehle: ", rt.calls.size(), " verschiedene; nicht umgesetzt: ", rt.unimplemented)
	print("UNIMPL ", mid, " ", JSON.stringify(rt.unimplemented.keys()))
	_finish()
