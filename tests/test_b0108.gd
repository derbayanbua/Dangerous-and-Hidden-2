extends "res://tests/test_gameplay.gd"
## 0.10.8 Missionsdaten: Versorgungskisten (Startbit +0x120, Bestand +0x12C→+0x130, Listen Achse/Alliierte),
## Nichtkämpfer +0x1A5, Anzeigename +0x1A8, „wird gezählt“ +0x1A4, Listenprüfung +0x1A6, Befehlsreste (Streutabelle
## 0x89AB20, Ziffernblock-Zeile).
##   tools\godot.cmd --headless -- --mission=al1_waldgeister --autoplay=test_b0108


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.interactive != null, "ALPS1 geladen, interaktive Akteure eingerichtet")
	if m == null or m.interactive == null:
		_finish()
		return
	var s: Soldier = m.squad.leader()
	# Unverwundbar (Testlauf)
	for mem in m.squad.members:
		if is_instance_valid(mem):
			mem.max_health = 100000.0
			mem.health = mem.max_health
	var it := m.interactive

	# --- 1. Versteckte Kiste la_ammo_6 (Startbit 2 → Bit 0 = 0) ---
	var hid: OrigInteractive.OrigCrate = it.controls.get("LA_AMMO_6")
	check(hid != null, "Kiste la_ammo_6 vorhanden")
	if hid:
		check(not hid.frame.visible and hid.actor_state == 0 and not hid.can_interact(s),
			"la_ammo_6 versteckt und unbenutzbar bis SetActorState")
		check(int(hid.frame.get_meta("actor_state")) == 0, "_ACTOR_GetState(la_ammo_6) = 0")
		check(hid.stock == 10 and hid.airdrop_delay < 0.0, "Bestand 10, kein Abwurf (−1)", "%d %.1f" % [hid.stock, hid.airdrop_delay])
		hid.set_actor_state(1)
		check(hid.frame.visible and hid.actor_state == 1 and hid.can_interact(s), "SetActorState(1) blendet ein")
		hid.set_actor_state(0)
		check(not hid.frame.visible and not hid.can_interact(s), "SetActorState(0) blendet aus")
		hid.set_actor_state(1)
	var shown: OrigInteractive.OrigCrate = it.controls.get("LA_AMMO_2")
	check(shown != null and shown.frame.visible and shown.actor_state == 1, "la_ammo_2 (Startbit 1) sichtbar")

	# --- Bestand zählt herunter, Spielstand ---
	var eq: OrigInteractive.OrigCrate = it.controls.get("LA_AMMO_5")     # Ausrüstung, Limit 1, Bestand 1
	if eq:
		eq.set_actor_state(1)
		check(eq.stock == 1 and _ints(eq.items) == [7] and eq.items_axis.is_empty(), "la_ammo_5: Bestand 1, Liste Alliierte [7]",
			str([eq.stock, eq.items, eq.items_axis]))
		eq.interact(s)
		check(eq.stock == 0 and not eq.can_interact(s), "Bestand 1 → 0, Kiste leer")
		var d := eq.serialize()
		check(int(d.get("stock", -9)) == 0 and int(d.get("state", -9)) == 1, "Spielstand enthält Bestand und Zustand", str(d))
	if hid:
		var mates: Array = m.squad.members.filter(func(x): return is_instance_valid(x) and x.alive)
		var st0 := hid.stock
		for k in 3:
			hid.interact(mates[k % mates.size()])
		check(hid.stock == st0 - 3, "Bestand zählt je Entnahme herunter", "%d → %d" % [st0, hid.stock])
		var sv := hid.serialize()
		hid.stock = 99
		hid.set_actor_state(0)
		hid.deserialize(sv)
		check(hid.stock == st0 - 3 and hid.actor_state == 1 and hid.frame.visible, "Laden stellt Bestand/Zustand her")

	# --- Liste je Seite ---
	var c2: OrigInteractive.OrigCrate = it.controls.get("LA_AMMO_")
	if c2:
		var axis := Soldier.new()
		axis.team = Soldier.TEAM_AXIS
		check(_ints(c2.items_for(s)) == [60, 62] and c2.items_for(axis).is_empty(), "Liste A = Achse, B = Alliierte",
			str([c2.items_for(s), c2.items_for(axis)]))
		axis.free()

	# --- 2./3./4. Personenflags ---
	var nonc: Soldier = null
	var named: Soldier = null
	var uncounted: Soldier = null
	for nm in m.actor_params:
		var p: Dictionary = m.actor_params[nm].get("params", {})
		var a := m.get_node_or_null("DynamicRoot/" + String(nm).validate_node_name()) as Soldier
		if a == null:
			a = _find_soldier(String(nm).validate_node_name())
		if a == null:
			continue
		if nonc == null and int(p.get("noncombatant_flag", 0)) != 0:
			nonc = a
		if named == null and int(p.get("name_text_id", -1)) > 0:
			named = a
		if uncounted == null and int(p.get("counted_flag", 1)) == 0 and int(p.get("side", 0)) == 2:
			uncounted = a
	check(nonc != null, "ALPS1: Nichtkämpfer gefunden")
	if nonc:
		var eb := nonc.get_node_or_null("EnemyBrain") as EnemyBrain
		check(eb != null and eb.noncombatant() and not eb.uniform_available(), "Nichtkämpfer: Uniform benutzen gesperrt")
		eb.captured = true
		check(not eb.give_uniform(s), "Nichtkämpfer gibt keine Uniform ab")
		eb.captured = false
	check(named != null and OrigHud.person_name(named) != "", "Anzeigename aus Text-ID",
		OrigHud.person_name(named) if named else "-")
	if uncounted:
		check(not LsRuntime.counted_enemy(uncounted), "„wird gezählt“ = 0 → nicht in _GetCountOfCarnageEnemies")
	var all_n: int = m.runtime.call_api(null, "_GETNUMLIVEENEMIES", [])
	var carn_n: int = m.runtime.call_api(null, "_GETCOUNTOFCARNAGEENEMIES", [])
	check(carn_n <= all_n, "Carnage-Zählung ≤ lebende Gegner", "%d/%d" % [carn_n, all_n])

	# --- Listenprüfung: Wache mit Flag durchschaut die Uniform ---
	var g := m.enemies[0] as Soldier if not m.enemies.is_empty() else null
	if g:
		var per := g.get_node("Perception") as Perception
		var p0: Dictionary = (g.get_meta("orig_params", {}) as Dictionary).duplicate()
		var p1 := p0.duplicate()
		p1["checks_list_flag"] = 1
		g.set_meta("orig_params", p1)
		check(per.checks_list(), "Listenprüfung (+0x1A6) erkannt")
		p1["checks_list_flag"] = 0
		g.set_meta("orig_params", p1)
		check(not per.checks_list(), "ohne Flag keine Listenprüfung")
		g.set_meta("orig_params", p0)

	# --- 6. Streutabelle „Dorthin“ ---
	var a0 := CommandMenu.spread_point(Vector3(0, 0, -20), Vector3.ZERO, 0)
	var a1 := CommandMenu.spread_point(Vector3(0, 0, -20), Vector3.ZERO, 1)
	var a3 := CommandMenu.spread_point(Vector3(0, 0, -20), Vector3.ZERO, 3)
	check(a0.is_equal_approx(Vector3(0, 0, -20)), "Platz 0 = Zielpunkt")
	check(is_equal_approx(a1.distance_to(a0), sqrt(20.0)) and a1.z > -20.0, "Platz 1: 4 m quer, 2 m zurück", str(a1))
	check(is_equal_approx(a3.distance_to(a0), sqrt(68.0)) and is_equal_approx(a3.z, -12.0), "Platz 3: 2 m quer, 8 m zurück", str(a3))
	var cm := get_tree().root.find_child("CommandMenu", true, false)
	if cm and cm.has_method("key_line"):
		var kl: String = cm.key_line()
		check(kl.begins_with("0 Alle") and kl.contains("1 "), "Ziffernblock-Zeile mit Namen", kl)
	_finish()


func _find_soldier(nm: String) -> Soldier:
	for o in get_tree().get_nodes_in_group("soldiers"):
		if o.name == nm:
			return o
	return null


func _ints(a: Array) -> Array:
	return a.map(func(x): return int(x))
