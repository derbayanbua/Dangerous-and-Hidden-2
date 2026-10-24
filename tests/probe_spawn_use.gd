extends "res://tests/test_gameplay.gd"
## System-Agent A: Spielerstart-OnUse/Intro-Prüfung (headless). Gibt je Kommando das zugewiesene Skript, Fahrzeug,
## Skriptanimationen und Startakteure aus.  --mission=<id> --autoplay=probe_spawn_use [--want_vehicle=1]


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.runtime != null, "Mission geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	var rt := m.runtime
	rt.auto_skip = true
	var spawns := 0
	for v in rt.vms:
		if is_instance_valid(v.me) and v.me.has_meta("spawn_of"):
			spawns += 1
			print("STARTAKTEUR ", v.me.name, " Skript ", v.name)
	check(spawns > 0, "Startakteure mit eigenem Skript", str(spawns))
	for i in 240:
		await get_tree().process_frame
		if rt.in_cutscene:
			rt.end_cutscene()
	var in_veh := 0
	for s in m.squad.members:
		var vm = rt.vm_of.get(s)
		print("KOMMANDO ", s.name, " Skript=", vm.name if vm else "-", " Fahrzeug=", s.vehicle.name if s.vehicle else "-",
			" born_use=", s.has_meta("born_use"))
		if s.vehicle:
			in_veh += 1
	print("ANIMATIONEN ", rt.anim.played)
	if Game.cli.has("want_vehicle"):
		check(in_veh == m.squad.members.size(), "alle Kommandos im Fahrzeug", "%d/%d" % [in_veh, m.squad.members.size()])
	if Game.cli.has("want_script"):
		var ok := 0
		for s in m.squad.members:
			var vm2 = rt.vm_of.get(s)
			if vm2 and String(vm2.name).to_lower().contains(String(Game.cli["want_script"]).to_lower()):
				ok += 1
		check(ok > 0, "Kommando-Skript zugewiesen (%s)" % Game.cli["want_script"], "%d" % ok)
	if Game.cli.has("want_anim"):
		var found := false
		for a in rt.anim.played:
			if String(a[1]).to_lower().contains(String(Game.cli["want_anim"]).to_lower()):
				found = true
		check(found, "Skriptanimation gespielt (%s)" % Game.cli["want_anim"])
	print("UNIMPL ", JSON.stringify(rt.unimplemented.keys()))
	_finish()
