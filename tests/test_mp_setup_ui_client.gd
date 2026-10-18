extends "res://tests/lan_ui_base.gd"
## Client zu test_mp_setup_ui (Fenster 1280×720): tritt bei, bedient im laufenden Spiel Pausenmenü → SPIELER-SETUP mit
## echten Eingabeereignissen (Input.parse_input_event → derselbe Weg wie Maus/Tastatur), prüft: kein Schuss, Maus frei,
## Auswahl übernommen; Kontrollbilder test_output/mp_setup_ingame_*.png. Ergebnis → user://mp_setup_ui_result.txt.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (Client)")
		_finish())
	_run.call_deferred()


## Echter Mausklick (Input-Singleton → Aktionsstatus „fire“ + GUI-Verteilung) an einer Fensterposition
func real_click(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	Input.parse_input_event(mv)
	await frames(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await frames(3)


## Echter Doppelklick (zweites Drücken mit double_click wie vom Betriebssystem gemeldet)
func real_dblclick(p: Vector2) -> void:
	await real_click(p)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.double_click = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await frames(3)


func dbl_click_node(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	await real_dblclick(get_viewport().get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5)))
	return true


func hit_node(ps: Node, name: String) -> Control:
	for c in ps.find_children("*", "Control", true, false):
		if c.has_meta("hit") and String(c.get_meta("hit")) == name:
			return c
	return null


## Feld eines Stapels in Taschen/Rucksack; liegt er weiter unten, mit den Original-Pfeilen weiterblättern
func find_inv_hit(ps: Node, id: int) -> Control:
	var h := hit_node(ps, "Inv%d" % id)
	for i in 12:
		if h != null:
			return h
		var down: Button = ps.find_child("PocketsDown", true, false)
		if down == null or down.disabled:
			down = ps.find_child("PackDown", true, false)
		if down == null or down.disabled:
			return null
		await click_node(down)
		await frames(3)
		h = hit_node(ps, "Inv%d" % id)
	return h


func click_node(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_transform_with_canvas() * (c.size * 0.5)
	if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(p):
		return false
	# Fensterkoordinaten (Inhaltsskalierung canvas_items: Fenster kann kleiner als 1280×720 sein)
	await real_click(get_viewport().get_final_transform() * p)
	return true


func real_key(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(3)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	img.save_png(ProjectSettings.globalize_path("res://test_output/mp_setup_ingame_%s.png" % name))


func _run() -> void:
	await frames(20)
	# eigene Deathmatch-Vorlage 1 (Datensatz 12) vor dem Test leeren
	var ups: Array = MpLoadout.UserPresets.load_all()
	ups[12] = MpLoadout.UserPresets.empty(12)
	MpLoadout.UserPresets.save_all(ups)
	Net.local_name = "Klicker"
	var port := int(Game.cli.get("setup_port", str(Net.PORT)))
	Net.join("127.0.0.1", port)
	var in_game := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) \
		and Net._soldiers[Net.my_id()].alive
	check(await wait_for(in_game, 600.0), "Client: im Spiel")
	var m = Game.current_mission()
	if m == null:
		_finish()
		return
	await frames(30)
	var me: Soldier = Net._soldiers[Net.my_id()]
	var shots0 := Ballistics.shots_fired
	var w: Weapon = me.current_weapon()
	var mag0: int = w.in_mag if w else -1
	# Pausenmenü (Esc) während der Runde
	await real_key("pause")
	await frames(5)
	var pm = m.get_node("PauseMenu")
	check(pm.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not get_tree().paused,
		"Pausenmenü offen, Maus frei, Runde läuft weiter")
	var psb: Button = m.find_child("PlayerSetupButton", true, false)
	await shot("0_pause")
	check(await click_node(psb), "Klick auf SPIELER-SETUP")
	await frames(10)
	var ps = m.find_child("PlayerSetup", true, false)
	var hov := get_viewport().gui_get_hovered_control()
	check(ps != null, "SPIELER-SETUP im Spiel geöffnet", "Knopf %s %s gesperrt=%s, unter der Maus: %s" % [psb.get_global_rect() if psb else "-",
		str(psb.get_global_transform_with_canvas() * (psb.size * 0.5)) if psb else "-", str(psb.disabled) if psb else "-",
		str(hov.get_path()) if hov else "-"])
	if ps == null:
		_finish()
		return
	await shot("1_offen")
	# Klasse: Liste aufklappen, MG-Schütze wählen (echte Klicks)
	check(await click_node(ps.find_child("ClassOpen", true, false)), "Klick: Klassenliste")
	await frames(5)
	check(await click_node(ps.find_child("Class0", true, false)), "Klick: Klasse 0")
	await frames(5)
	# Gegenstandsliste unten links (Kategorie aufklappen, Gegenstand anklicken) – Kontrollbilder des Bereichs
	check(await click_node(ps.find_child("ItemsOpen", true, false)), "Klick: Kategorienliste unten links")
	await frames(5)
	await shot("1b_kategorien")
	await click_node(ps.find_child("ItemCat0", true, false))
	await frames(5)
	var item_hit: Control = null
	for c in ps.find_children("Allowed*", "Control", true, false):
		item_hit = c
		break
	check(item_hit != null and await click_node(item_hit), "Klick: erlaubter Gegenstand")
	await frames(5)
	await shot("1c_gegenstand")
	# --- Einzel-Ausrüstung: Doppelklick auf einen erlaubten Gegenstand → an den Soldaten (Lager, Traglast) ---
	var pick_id := -1
	var pick_hit: Control = null
	# Kategorie MAGAZINE (Lager je Seite: ammo_num der erlaubten Waffen)
	await click_node(ps.find_child("ItemsOpen", true, false))
	await frames(5)
	await click_node(ps.find_child("ItemCat3", true, false))
	await frames(5)
	for c in ps.find_children("Allowed*", "Control", true, false):
		var id := int(String(c.get_meta("hit", "Allowed-1")).substr(7))
		if id >= 0 and MpLoadout.remaining(ps.inv, ps.allowed_list(), ps.ui_team(), id) > 0 and (SAS.can_add(ps.inv, ps.strength(), id, 1) \
				or SAS.count_of(ps.inv, id) > 0):
			pick_id = id
			pick_hit = c
			break
	# Taschen voll (Vorlage füllt 12 Raumeinheiten): zuerst ein Stück davon per Doppelklick ablegen
	if pick_id >= 0 and not SAS.can_add(ps.inv, ps.strength(), pick_id, 1):
		var c0 := SAS.count_of(ps.inv, pick_id)
		# Stapel anklicken (markiert) und auf „Ablegen“ klicken (Original-Feld drop)
		var ih: Control = await find_inv_hit(ps, pick_id)
		var sel_ok := await click_node(ih)
		await frames(3)
		var drop_ok := await click_node(hit_node(ps, "Slot_drop"))
		var taken := func() -> bool: return SAS.count_of(ps.inv, pick_id) == c0 - 1
		await wait_for(taken, 10.0)      # Eingaben werden im Fenster unter Last verzögert verarbeitet
		check(sel_ok and drop_ok and SAS.count_of(ps.inv, pick_id) == c0 - 1, "Markieren + ABLEGEN: ein Stück aus den Taschen genommen (Platz frei)",
			"ok %s/%s %s %d → %d, sel %s, dropdown '%s', Maus über %s, Meldung %s" % [sel_ok, drop_ok, SAS.item_label(pick_id), c0, SAS.count_of(ps.inv, pick_id), ps.sel_inv,
			ps.dropdown, str(get_viewport().gui_get_hovered_control().get_path()) if get_viewport().gui_get_hovered_control() else "-", ps.last_msg])
		await frames(5)
		pick_hit = hit_node(ps, "Allowed%d" % pick_id)
	var n_before := SAS.count_of(ps.inv, pick_id)
	var dbg := []
	for c in ps.find_children("Allowed*", "Control", true, false):
		var id := int(String(c.get_meta("hit", "Allowed-1")).substr(7))
		dbg.append("%d:%d:%s" % [id, MpLoadout.remaining(ps.inv, ps.allowed_list(), ps.ui_team(), id), SAS.can_add(ps.inv, ps.strength(), id, 1)])
	check(pick_hit != null and await dbl_click_node(pick_hit), "Doppelklick: erlaubter Gegenstand (%s)" % SAS.item_label(pick_id),
		"cat %d, %s, w %.1f/%.1f" % [ps.item_cat, ", ".join(dbg), SAS.inv_weight(ps.inv), ps.strength()])
	await frames(5)
	check(SAS.count_of(ps.inv, pick_id) == n_before + 1 and ps.custom, "Gegenstand am Soldaten (Einzel-Ausrüstung)",
		"%d → %d" % [n_before, SAS.count_of(ps.inv, pick_id)])
	check(MpLoadout.check(ps.inv, ps.allowed_list(), ps.ui_team(), ps.strength(), ps._heads(ps.inv)) == "", "Ausrüstung gültig (Lager/Traglast)")
	await shot("1d_einzelausruestung")
	# Ablegen per Doppelklick auf das Feld in Taschen/Rucksack, dann wieder hinzufügen
	var inv_hit: Control = await find_inv_hit(ps, pick_id)
	if inv_hit == null:
		for sl in ["hands", "shoulder", "uniform", "back"]:
			if int(ps.inv.get(sl, -1)) == pick_id:
				inv_hit = hit_node(ps, "Slot_" + sl)
	check(inv_hit != null and await dbl_click_node(inv_hit), "Doppelklick am Soldaten: Gegenstand ablegen")
	await frames(5)
	check(SAS.count_of(ps.inv, pick_id) == n_before, "Gegenstand abgelegt")
	pick_hit = hit_node(ps, "Allowed%d" % pick_id)
	await dbl_click_node(pick_hit)
	await frames(5)
	check(SAS.count_of(ps.inv, pick_id) == n_before + 1, "Erneut hinzugefügt")
	var my_inv: Dictionary = ps.inv.duplicate(true)
	# --- Eigene Vorlage: Liste → „Leer 1“ (Deathmatch-Block) → SPEICHERN → UMBENENNEN ---
	check(await click_node(ps.find_child("ClassOpen", true, false)), "Klick: Vorlagenliste")
	await frames(5)
	check(await click_node(hit_node(ps, "UserPreset0")), "Klick: eigene Vorlage 1")
	await frames(5)
	var save_b: Button = ps.find_child("SavePreset", true, false)
	check(save_b != null and not save_b.disabled and await click_node(save_b), "Klick: SPEICHERN (aktiv bei eigener Vorlage)")
	await frames(5)
	var up: Dictionary = MpLoadout.user_presets(ps.block())[0]
	var up_inv := MpLoadout.user_preset_inventory(up)
	check(not MpLoadout.user_preset_empty(up) and SAS.count_of(up_inv, pick_id) == SAS.count_of(my_inv, pick_id)
		and int(up.get("flags", 0)) == 66, "Vorlage gespeichert (user_presets_orig.def, Block Deathmatch Flags 66)",
		"%s flags %d" % [MpLoadout.user_preset_label(up), int(up.get("flags", 0))])
	var ren_b: Button = ps.find_child("RenamePreset", true, false)
	check(ren_b != null and not ren_b.disabled and await click_node(ren_b), "Klick: UMBENENNEN")
	await frames(5)
	var ren_e: LineEdit = ps.find_child("RenameInput", true, false)
	check(ren_e != null, "Namenseingabe offen")
	if ren_e:
		ren_e.grab_focus()
		ren_e.select_all()
		await type_into(ren_e, "Sturm")
		if ren_e.text != "Sturm":
			ren_e.text = "Sturm"
		await shot("1e_umbenennen")
		check(await click_node(ps.find_child("Dialog0", true, false)), "Klick: OK")
		await frames(5)
	check(MpLoadout.user_preset_label(MpLoadout.user_presets(ps.block())[0]) == "Sturm", "Vorlage umbenannt",
		MpLoadout.user_preset_label(MpLoadout.user_presets(ps.block())[0]))
	var hdr: Label = ps.find_child("ClassHeader", true, false)
	check(hdr != null and hdr.text == "Sturm", "Kopfzeile zeigt die eigene Vorlage", hdr.text if hdr else "")
	# PUNKTESTAND ↔ SOLDATEN-STATUS ANZEIGEN (rechte Seite)
	check(await click_node(ps.find_child("Scores", true, false)), "Klick: PUNKTESTAND")
	await frames(5)
	check(ps.right_panel == "scores" and ps.find_child("ScoresText", true, false) != null, "Rechte Seite: Punktestand")
	await shot("1f_punktestand")
	check(await click_node(ps.find_child("Scores", true, false)), "Klick: SOLDATEN-STATUS ANZEIGEN")
	await frames(5)
	check(ps.right_panel == "status" and ps.find_child("Preview3D", true, false) != null, "Rechte Seite: Soldaten-Status")
	# Figur: ans Ende blättern und Held der Seite anklicken (Helden stehen ganz hinten)
	var right: Control = ps.find_child("FigRight", true, false)
	for i in 40:
		if right == null or right.disabled:
			break
		await click_node(right)
		await frames(3)
		right = ps.find_child("FigRight", true, false)
	var hero = ps.find_child("Figure_hero_allied", true, false)
	if hero == null:
		hero = ps.find_child("Figure_hero_axis", true, false)
	if hero == null:
		# Helden nur lokal (nicht im Repository): ohne sie die letzte MP-Figur der Liste
		for c in ps.find_children("Figure_mp_*", "Control", true, false):
			hero = c
	check(hero != null and await click_node(hero), "Klick: letzte Figur der Liste (Held, falls lokal vorhanden)")
	await frames(5)
	await shot("2_auswahl")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Maus bleibt während der Klicks frei (nicht gefangen)")
	check(Ballistics.shots_fired == shots0 and (w == null or w.in_mag == mag0), "Kein Schuss durch Klicks im Menü",
		"%d Schüsse" % (Ballistics.shots_fired - shots0))
	check(await click_node(ps.find_child("Accept", true, false)), "Klick: AKZEPTIEREN")
	await frames(10)
	check(Net.local_class == 0 and String(Net.local_figure) != "", "Auswahl übernommen (Klasse, Figur)",
		"%d %s" % [Net.local_class, Net.local_figure])
	check(not Net.local_loadout.is_empty() and SAS.count_of(Net.local_loadout, pick_id) == SAS.count_of(my_inv, pick_id),
		"Einzel-Ausrüstung an den Server gesendet (request_loadout)")
	check(m.find_child("PlayerSetup", true, false) == null and pm.is_open(), "SPIELER-SETUP geschlossen, Pausenmenü offen")
	check(Ballistics.shots_fired == shots0, "Auch AKZEPTIEREN-Klick feuert nicht")
	# Pausenmenü schließen → Steuerung wieder im Spiel, Maus gefangen
	await real_key("pause")
	await frames(5)
	check(not pm.is_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Menü zu: Maus wieder gefangen")
	await frames(10)
	check(Ballistics.shots_fired == shots0, "Kein nachträglicher Schuss nach dem Schließen")
	await shot("3_spiel")
	# Server tötet den Soldaten (Test) → Wiedereinstieg mit der eigenen Ausrüstung (auch auf diesem Rechner)
	var respawned := func() -> bool:
		var s2 = Net._soldiers.get(Net.my_id())
		return is_instance_valid(s2) and s2 != me and s2.alive and s2.has_meta("mp_loadout")
	check(await wait_for(respawned, 120.0), "Client: Wiedereinstieg mit eigener Ausrüstung")
	if respawned.call():
		var s3: Soldier = Net._soldiers[Net.my_id()]
		check((s3.get_meta("orig_items", []) as Array).has(pick_id), "Client: Gegenstand %s am Soldaten" % SAS.item_label(pick_id),
			str(s3.get_meta("orig_items", [])))
	_finish()


var _quitting := false


func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://mp_setup_ui_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
		f.close()
	await get_tree().create_timer(2.0).timeout
	Net.leave(false)
	get_tree().quit(1 if failed > 0 else 0)
