extends "res://tests/test_gameplay.gd"
## B-002 „Teil 1B spielbar“: interaktive Originalakteure in ARCTIC2 wirksam.
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_a2
## Sprengplätze BUM1–5 (Typ 22), Schalter/Alarm (13), Munitionskiste (9), Fässer la_bar03 (25),
## Fotoplatz (15) mit Gegenstand 229 „Fotoaparat“. Erfüllbarkeit 4/4: tools\run_completability.ps1 -Only a2_erkundung.


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.interactive != null, "ARCTIC2 mit OrigInteractive geladen")
	if m == null or m.interactive == null:
		_finish()
		return
	if m.runtime.in_cutscene:
		m.runtime.auto_skip = true
		m.runtime.end_cutscene()
	var it := m.interactive
	var c: Dictionary = it.controls
	print("STATS ", it.stats)
	var bums := 0
	for n in ["BUM1", "BUM2", "BUM3", "BUM4", "BUM5"]:
		if c.get(n) is OrigInteractive.OrigExplosive:
			bums += 1
	check(bums == 5, "Sprengplätze BUM1–5 (Typ 22)", str(bums))
	check(it.stats.switches >= 10, "Schalter/Alarm/Aufzug (Typ 13)", str(it.stats.switches))
	check(c.get("AMMOCRATE") is OrigInteractive.OrigCrate, "Munitionskiste (Typ 9)")
	check(c.get("LA_BAR03_1") is OrigInteractive.OrigDestructible and c.get("LA_BAR03_2") is OrigInteractive.OrigDestructible,
		"Fässer la_bar03 (Typ 25)")
	check(c.get("FOTOPLACEBOX") is OrigInteractive.OrigPlace and (c["FOTOPLACEBOX"] as OrigInteractive.OrigPlace).item == 229,
		"Fotoplatz benötigt Gegenstand 229")
	var s: Soldier = m.squad.leader()
	check(it.anyone_has(229), "Fotoapparat 229 im Trupp-Inventar", str(s.get_meta("orig_items", [])))
	# Original: Dynamit (68) liegt frei in der Anlage (items.dat ohne Besitzer) und muss aufgehoben werden
	var dyn := 0
	var dyn_item: OrigInteractive.OrigWorldItem = null
	for n in get_tree().get_nodes_in_group("world_items"):
		if n is OrigInteractive.OrigWorldItem and (n as OrigInteractive.OrigWorldItem).item == 68:
			dyn += 1
			if dyn_item == null:
				dyn_item = n
	check(dyn >= 5, "Dynamit 68 liegt frei (für 5 Sprengplätze)", str(dyn))
	if dyn_item and dyn_item.can_interact(s):
		dyn_item.interact(s)
	check(it.anyone_has(68), "Dynamit aufgehoben", str(s.get_meta("orig_items", [])))
	check(it.stats.missing == 0, "alle interaktiven Frames gefunden", str(it.stats.missing))

	# Wirkung: Kiste gibt Munition
	var crate := c["AMMOCRATE"] as OrigInteractive.OrigCrate
	check(crate.can_interact(s), "Munitionskiste benutzbar")
	crate.interact(s)
	check(int(crate.taken.get(s.persistent_id, 0)) == 1, "Munitionskiste: Entnahme gezählt")

	# Schalter schaltet Zustand (Kind-Frames 1/2/3) und meldet OnUse
	var sw: OrigInteractive.OrigSwitch = null
	for v in c.values():
		if v is OrigInteractive.OrigSwitch and not (v as OrigInteractive.OrigSwitch).radio:
			sw = v
			break
	if sw:
		var st0 := sw.state
		sw.interact(s)
		check(sw.state != st0 and int(sw.frame.get_meta("actor_state", 0)) == sw.state, "Schalter wechselt Zustand",
			"%d -> %d" % [st0, sw.state])

	# Fass zerstörbar (Explosion)
	var bar := c["LA_BAR03_1"] as OrigInteractive.OrigDestructible
	bar.on_explosion(bar.health, s)
	check(bar.destroyed and int(bar.frame.get_meta("actor_state", 1)) == 0, "Fass durch Explosion zerstört")

	# Sprengplatz: Ladung anbringen (3 s am Platz) -> Zustand 1, Countdown
	var bum := c["BUM1"] as OrigInteractive.OrigExplosive
	# Zu Beginn versteckt (Zustand 3); das Originalskript gibt die Plätze erst mit Ziel 3 frei (SetActorState 0)
	check(bum.state == 3 and not bum.frame.visible, "BUM1 zu Beginn per Skript versteckt", str(bum.state))
	# fix_a2_marker: Zielmarker schon für den versteckten Platz (Abweichung), Freigabe wie im Original über
	# r_arc1b_dynamit_1.scr: Whenever Near (_PlayerInRange(5)) -> SetActorState(BUM1, 0) am Skriptframe dummy_bomba_1
	var hud = m.hud
	var om: ObjectiveMarkers = hud.objective_markers if hud and "objective_markers" in hud else null
	check(om != null, "Zielmarker-Ebene vorhanden")
	if om:
		om._collect()
		check(not om.targets.any(func(t): return t["kind"] == "explosive"), "versteckte Sprengplätze nicht markiert",
			str(om.targets.size()))
		Settings.objective_markers = false
		om._collect()
		check(om.targets.is_empty(), "Zielmarker abschaltbar (Optionen)")
		Settings.objective_markers = true
		var f3 := FileAccess.open(m.runtime.orig.mission_dir + "/scripts/r_arc1b_objective3.scr", FileAccess.READ)
		var idx: Array = ObjectiveMarkers.script_objective_targets(f3.get_as_text()) if f3 else []
		check(idx.has(4) and not idx.has(1), "Skript-Zielort: Rückkehr (Ziel 4) aus Whenever _PlayerInRange", str(idx))
	var dvm: LsVM = null
	for vm in m.runtime.vms:
		if vm.name.to_lower().find("dynamit_1") >= 0:
			dvm = vm
	check(dvm != null and dvm.me != null, "Skript r_arc1b_dynamit_1 am Frame", dvm.me.name if dvm else "-")
	if dvm and dvm.me:
		s.global_position = dvm.me.global_position + Vector3(0.5, 0.0, 0.0)
		for i in 40:
			await seconds(0.1)
			s.global_position = dvm.me.global_position + Vector3(0.5, 0.0, 0.0)
			if bum.state == 0:
				break
	check(bum.state == 0, "BUM1 vom Originalskript freigegeben (Spieler in Reichweite)", str(bum.state))
	if bum.state != 0:
		bum.set_actor_state(0)
	var off: Node3D = null
	for ch in bum.frame.find_children("*", "Node3D", true, false):
		if String(ch.name).to_lower().begins_with("explosive_off"):
			off = ch
	check(bum.frame.is_visible_in_tree() and off != null and off.is_visible_in_tree(),
		"BUM1-Markierung explosive_off sichtbar", "frame=%s off=%s" % [bum.frame.is_visible_in_tree(), off.is_visible_in_tree() if off else null])
	s.global_position = bum.global_position + Vector3(0.5, 0.0, 0.0)
	if om:
		om._collect()
		check(om.targets.any(func(t): return t["kind"] == "explosive" and (t["pos"] as Vector3).distance_to(bum.global_position) < 1.0)
			and om.targets.size() <= 4, "Zielmarker für freigegebenen BUM1 (max. 4)", str(om.targets.size()))
	check(bum.can_interact(s), "BUM1 anbringbar", "enabled=%s state=%d work=%.1f" % [bum.enabled, bum.state, bum._work])
	bum.interact(s)
	for i in 12:
		await seconds(0.5)
		s.global_position = bum.global_position + Vector3(0.5, 0.0, 0.0)
		if bum.state == 1:
			break
	check(bum.state == 1 and int(bum.frame.get_meta("actor_state", 0)) == 1, "BUM1: Ladung angebracht (Skriptzustand 1)",
		str(bum.state))
	# Zeitzünder-Liste (gameinterface.4ds timer-explosive00–09): sichtbar und zählt herunter
	var oh: OrigHud = hud.orig_hud if hud and "orig_hud" in hud else null
	check(oh != null, "Original-HUD vorhanden")
	if oh:
		await seconds(0.6)
		var t0: float = float(oh.timers_shown[0][1]) if oh.timers_shown.size() > 0 else -1.0
		var lab := oh.get_node_or_null("TimerText00") as Label
		check(t0 > 290.0 and oh.elements.has("timer-explosive00") and (oh.elements["timer-explosive00"]["node"] as Control).visible
			and lab != null and lab.visible and lab.text.find(":") > 0, "Zeitzünder-Liste zeigt BUM1 (300 s)",
			"%s / %s" % [str(oh.timers_shown), lab.text if lab else "-"])
		await seconds(1.5)
		var t1: float = float(oh.timers_shown[0][1]) if oh.timers_shown.size() > 0 else -1.0
		check(t1 > 0.0 and t1 < t0 - 1.0, "Zeitzünder zählt herunter", "%.1f -> %.1f" % [t0, t1])

	# Fotoplatz
	var foto := c["FOTOPLACEBOX"] as OrigInteractive.OrigPlace
	check(foto.can_interact(s), "Fotoplatz benutzbar")
	foto.interact(s)
	check(foto.state == 1, "Foto gemacht (Zustand 1)")
	_finish()
