extends "res://tests/test_systems.gd"
## Eingabezeile im Einzelspieler (Schalter und Sofortbefehle).
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_quick_line

const _CF := preload("res://src/combat/combat_flags.gd")
var _ql: Node


func _r(code: String) -> String:
	return _ql.run(Marshalls.base64_to_utf8(code))


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	var c: PlayerController = m.controller
	_ql = c.get_node_or_null("QuickLine")
	check(_ql != null, "Eingabezeile vorhanden")
	if _ql == null:
		_finish()
		return
	var lead: Soldier = m.squad.leader()
	c.set_active(lead)
	check(_ql.run("xyz") == "unknown command", "Unbekanntes Wort")
	check(_r("aGFwcHlhbW1v") == "a number required", "Zahl verlangt")
	check(_r("aHlkcm9zaG9jayAy") == "invalid value", "Wertebereich 0,1")

	# Gegner fällt mit einem Treffer
	var enemy: Soldier = null
	for s in get_tree().get_nodes_in_group("soldiers"):
		if s is Soldier and s.team == Soldier.TEAM_AXIS and s.alive:
			enemy = s
			break
	check(enemy != null, "Gegner gefunden")
	check(_r("aHlkcm9zaG9jayAx") == "ok" and _r("aHlkcm9zaG9jaw==") == "1", "Schalter 1 an")
	if enemy:
		enemy.apply_hit(1.0, &"leg", lead, Vector3.FORWARD)
		check(not enemy.alive, "Ein Treffer tödlich", "%.1f" % enemy.health)
	var before := lead.health
	lead.apply_hit(5.0, &"body", null, Vector3.FORWARD)
	check(lead.alive and is_equal_approx(lead.health, before - 5.0), "Eigener Trupp nicht betroffen")
	_r("aHlkcm9zaG9jayAw")

	# Heilen
	for mm in m.squad.members:
		mm.health = 30.0
	check(_r("aGVhbA==") == "ok", "Heilen ok")
	var all_full := true
	for mm in m.squad.members:
		all_full = all_full and is_equal_approx(mm.health, mm.max_health)
	check(all_full, "Ganzer Trupp geheilt")

	# Munition / Streuung
	check(_r("aGFwcHlhbW1vIDE=") == "ok" and _CF.keep_mag, "Munitionsschalter an")
	check(_r("c25pcGVyIDE=") == "ok" and _CF.steady, "Streuungsschalter an")
	var w := lead.current_weapon()
	if w:
		w.in_mag = w.data.magazine_size
		var n := w.in_mag
		w.in_mag -= 1
		lead._fire_shot(w)
		check(w.in_mag == n, "Magazin bleibt voll", "%d/%d" % [w.in_mag, n])
	_r("aGFwcHlhbW1vIDA=")
	_r("c25pcGVyIDA=")

	# Gegenstand
	var inv_before: int = (lead.get_meta("orig_items", []) as Array).size()
	check(_r("Z2l2ZWl0ZW0gdGhvbXBzb24=") == "ok", "Gegenstand ok")
	check((lead.get_meta("orig_items", []) as Array).size() > inv_before, "Gegenstand erhalten")

	# Anzeige
	check(_r("bm9fZ2kgMQ==") == "ok" and m.hud and not m.hud.visible, "Anzeige aus")
	_r("bm9fZ2kgMA==")
	check(m.hud.visible, "Anzeige an")

	# Online ohne Wirkung
	_r("aHlkcm9zaG9jayAx")
	Net.is_online = true
	check(not _CF.active(_CF.one_hit), "Online wirkungslos")
	check(_r("aGVhbA==") == "", "Online keine Befehle")
	Net.is_online = false
	_r("aHlkcm9zaG9jayAw")

	# Taste ^ (physisch links neben 1) öffnet die Zeile; Tottasten-Variante (nur keycode ^) ebenso
	for variant in ["physical", "circumflex"]:
		var ev := InputEventKey.new()
		ev.pressed = true
		if variant == "physical":
			ev.physical_keycode = KEY_QUOTELEFT
		else:
			ev.keycode = KEY_ASCIICIRCUM
			ev.unicode = 0x5E
		_ql._input(ev)
		check(_ql.is_open(), "Taste ^ öffnet Zeile (%s)" % variant)
		_ql._close()
	# pos: Antwort sichtbar im HUD, Zwischenablage, auch mit vorangestelltem ^ der Tottaste
	var msgs: Array = []
	var cb := func(t: String, sec: float): msgs.append([t, sec])
	Events.message.connect(cb)
	_ql._on_submit("^pos")
	Events.message.disconnect(cb)
	check(msgs.size() == 1 and String(msgs[0][0]).begins_with("pos ") and float(msgs[0][1]) >= 5.0,
		"pos zeigt Lage mehrere Sekunden", str(msgs))
	check(DisplayServer.clipboard_get().begins_with("pos ") or DisplayServer.get_name() == "headless",
		"pos in Zwischenablage")
	var shown := false
	if m.hud and m.hud.get("_msg_box"):
		for l in m.hud._msg_box.get_children():
			if l is Label and l.text.begins_with("pos "):
				shown = l.visible
	check(shown, "pos-Zeile im HUD")

	# Aktiver Soldat
	var mate: Soldier = null
	for mm in m.squad.members:
		if mm != lead and mm.alive:
			mate = mm
	if mate:
		c.set_active(mate)
		_r("a2lsbA==")
		check(not mate.alive, "Aktiver Soldat tot")
	_finish()
