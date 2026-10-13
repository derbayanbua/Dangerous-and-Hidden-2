extends "res://tests/test_gameplay.gd"
## Rauchtest für Original-Missionsteile (1B, 1C, …): Level, Akteure, Skripte, Ziele.
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_orig_part [--commandos=1]


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
	check(m.orig != null and m.orig.stats.meshes > 300, "Original-Level", "%d Meshes, %d Instanzen" % [
		m.orig.stats.meshes, m.orig.stats.instances])
	var want := int(Game.cli.get("commandos", "4"))
	check(m.squad.members.size() == want, "Kommandos laut Original", str(m.squad.members.size()))
	var rt := m.runtime
	check(rt != null and rt.vms.size() > 50, "Originalskripte laufen", "%d VMs" % (rt.vms.size() if rt else 0))
	check(rt.waypoints.size() > 50, "KI-Wegpunkte", str(rt.waypoints.size()))
	var enemies := 0
	for a in rt.actors.values():
		if a is Soldier and (a as Soldier).team == Soldier.TEAM_AXIS:
			enemies += 1
	check(enemies > 5, "Gegner aus actors.bin", str(enemies))
	rt.auto_skip = true
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(8.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(2.0)
	var active := 0
	for o in m.objectives:
		if o.state != Objective.State.INACTIVE:
			active += 1
	check(active >= 1, "Skript aktiviert Missionsziele", "%d von %d aktiv" % [active, m.objectives.size()])
	for o in m.objectives:
		print("  Ziel ", o.id, " ", o.state, " ", o.text)
	check(not m.finished, "Mission läuft", str(Game.last_result.get("reason", "")))
	print("Befehle: ", rt.calls.size(), " verschiedene; nicht umgesetzt: ", rt.unimplemented)
	_finish()
