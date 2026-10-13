extends "res://tests/test_gameplay.gd"
## Weltgegenstände, Leicheninhalt, Skript-Semantik aus der Erfüllbarkeitsanalyse (docs/completability.md):
## AFRICA1 Dokumente (Gegenstand 252, ITEM_Teleport, _IsInInventory), _EnemyInRange von Dummies, HUMAN_Kill aus
## Objektskripten; CZECH5 Akteure unter Nicht-Sektor-Eltern.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_items


func _wait_mission(prev: Node = null) -> Node:
	for i in 3000:
		await get_tree().process_frame
		var m := mission()
		if m and m != prev and m.squad and m.squad.leader():
			return m
	return null


func _run() -> void:
	var m = await _wait_mission()
	check(m != null and m.interactive != null, "AFRICA1 geladen")
	if m == null:
		_finish()
		return
	var it: OrigInteractive = m.interactive
	check(it.stats.world_items >= 30, "Frei liegende Gegenstände aus items.dat", str(it.stats.world_items))
	await seconds(2.5)       # af1_documents_assigner: Delay(1000), dann ITEM_Teleport auf dummy_doc1..5
	var doc: Node3D = m.runtime.find_frame("item_slozka3")
	check(doc is OrigInteractive.OrigWorldItem and doc.item == 252, "Dokumente „item_slozka3“ (Gegenstand 252) als Frame")
	if doc:
		var near := 99999.0
		for k in range(1, 6):
			var dd: Node3D = m.runtime.find_frame("dummy_doc%d" % k)
			if dd:
				near = minf(near, dd.global_position.distance_to(doc.global_position))
		check(near < 0.5, "Originalskript legt die Dokumente an einen der Ablageorte (ITEM_Teleport)", "%.2f m" % near)
		var s: Soldier = m.squad.leader()
		var vm := LsVM.new(LsCompiler.new(), doc, m.runtime)
		check(int(m.runtime.call_api(vm, "_ITEMINRANGE", [["num", 252], ["num", 2]])) == 1, "_ItemInRange(252, 2) am Fundort")
		doc.interact(s)
		check(s.get_meta("orig_items", []).has(252) and not doc.visible, "Dokumente aufgehoben (Originalinventar)")
		check(int(m.runtime.call_api(vm, "_ISININVENTORY", [["num", 252]])) == 1, "_IsInInventory(252) = 1")
	# _EnemyInRange von einem Dummy: zählt Achsensoldaten, nicht den eigenen Trupp
	var lead: Soldier = m.squad.leader()
	var probe := Node3D.new()
	m.dynamic_root.add_child(probe)
	probe.global_position = lead.global_position
	var vm2 := LsVM.new(LsCompiler.new(), probe, m.runtime)
	var axis_near := false
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(probe.global_position) <= 5.0:
			axis_near = true
	check(int(m.runtime.call_api(vm2, "_ENEMYINRANGE", [["num", 5]])) == (1 if axis_near else 0),
		"_EnemyInRange vom Dummy zählt den eigenen Trupp nicht")
	# HUMAN_Kill aus einem Objektskript tötet den Akteur (AFRICA1 af1_odletletadla: Adjutant)
	var victim: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive:
			victim = e
			break
	if victim:
		m.runtime.register_actor("__test_victim", victim)
		m.runtime.call_api(vm2, "HUMAN_KILL", [["str", "__test_victim"]])
		check(not victim.alive, "HUMAN_Kill aus Objektskript")
	# Leicheninhalt: Originalgegenstände übernehmen
	var carrier: Soldier = null
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and not e.get_meta("orig_loot", []).is_empty():
			carrier = e
			break
	if carrier:
		var ids: Array = carrier.get_meta("orig_loot").duplicate()
		carrier.die(null)
		await frames(2)
		var loot: Pickups.Loot = null
		for c in carrier.get_children():
			if c is Pickups.Loot:
				loot = c
		if loot:
			loot.interact(lead)
			check(lead.get_meta("orig_items", []).has(ids[0]), "Leiche durchsucht: Originalgegenstand übernommen", str(ids))

	# CZECH5: GE_8 unter „Yelbld143“ steht auf seinem Gebäude (Wegpunkte Ge8_x liegen bei y≈31)
	Game.start_mission("cz5_trink_aus")
	var m5 = await _wait_mission(m)
	check(m5 != null, "CZECH5 geladen")
	if m5:
		var ge8: Node3D = m5.runtime.find_frame("GE_8")
		var wp: Node3D = m5.runtime.find_frame("Ge8_1")
		check(ge8 != null and ge8.global_position.y > 15.0, "Akteur unter Nicht-Sektor-Eltern in Weltlage",
			"%s (Wegpunkt %s)" % [str(ge8.global_position) if ge8 else "-", str(wp.global_position) if wp else "-"])
		# Fahrzeugnetz (check2.bin Abschnitt 2): Tiger-Spur A21 … A43 aus ge_11.scr
		var rt: LsRuntime = m5.runtime
		var a21 := rt._drive_name("A21")
		var a43 := rt._drive_name("a43")
		check(a21 >= 0 and a43 >= 0, "HUMAN_Drive-Ziele „A21“/„A43“ im Fahrzeugnetz (ohne Groß-/Kleinschreibung)")
		if a21 >= 0 and a43 >= 0:
			var route := rt._drive_route(rt._drive_astar.get_point_position(a21), a43)
			check(route.size() >= 2, "Route über das Fahrzeugnetz", "%d Punkte" % route.size())
	_finish()
