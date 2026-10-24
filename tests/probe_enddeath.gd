extends "res://tests/test_gameplay.gd"
## System-Agent A: OnDeath nach EndScript (hd2.exe 0x41D920). NORMANDY2: Scharfschützen 2/3/5 beenden ihr Skript bei
## Alarm (EndScript), ihr OnDeath meldet Signal 1 → Ziel 1.  --mission=no2_schwerttaenzer --autoplay=probe_enddeath


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	var rt := m.runtime
	rt.auto_skip = true
	await seconds(2.0)
	var ok_end := 0
	for nm in ["Sniper_2", "Sniper_3", "Sniper_5"]:
		var s = rt.find_frame(nm)
		var vm = rt.vm_of.get(s)
		if vm == null:
			continue
		vm.fire("ONALARM")
		for i in 30:
			await get_tree().process_frame
		if vm.terminated:
			ok_end += 1
	check(ok_end == 3, "Alarm → EndScript bei allen 3 Scharfschützen", str(ok_end))
	var vm2 = rt.vm_of.get(rt.find_frame("Sniper_2"))
	check(vm2 != null and not vm2.fire("ONUSE"), "nach EndScript bleibt OnUse wirkungslos")
	for nm in ["Sniper_2", "Sniper_3", "Sniper_5"]:
		var s2 = rt.find_frame(nm)
		if s2 is Soldier and s2.alive:
			s2.die(null)
		await seconds(0.5)
	await seconds(2.0)
	var o: Objective = m.objective(m.orig_objectives.get(1, &""))
	check(o != null and o.state == Objective.State.DONE, "Ziel 1 „Scharfschützen“ erfüllt", str(o.state if o else -1))
	_finish()
