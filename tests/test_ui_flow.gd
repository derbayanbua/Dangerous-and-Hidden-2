extends "res://tests/test_gameplay.gd"
## Menüabläufe nach dem Original: Spielmodi (Einzelgänger, Blutbad, Einzelmission-Blutbad), FILME, Inventar
## (Ziehen und Ablegen, Beschreibung, eigene Vorlagen user_presets_orig.def), MP-Figurwahl mit Helden und 3D-Vorschau.
##   tools\godot.cmd --headless -- --autoplay=test_ui_flow --profiles_dir=user://test_ui_flow --noimport


const UP := preload("res://src/campaign/user_presets.gd")


## Ersatz für OrigMission.orig: lädt Originalfiguren aus orig_cache/characters und merkt sich die Modelle
class FakeOrig:
	var requested: Array = []

	func character_instance(model: String) -> Node3D:
		requested.append(model)
		return PlayerSetupScreen._character(model)


class FakeMission extends Node:
	var orig := FakeOrig.new()


func btn(name_part: String) -> Button:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if String(b.name).contains(name_part.validate_node_name()) or (b as Button).text == name_part:
			return b
	return null


func sp(a: String) -> String:
	return str(InputSetup.spec_of(a))


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


## Tastenmenü: Umbelegen (Taste/Maus/Rad), Tausch, Löschen, Esc, Blättern, Standard, Speichern → Neu laden.
## Key menu: rebind (key/mouse/wheel), swap, clear, Esc, paging, defaults, save → reload.
func _keys_rebind_roundtrip(menu) -> void:
	InputSetup.reset_defaults()
	var listed := {}
	for cat in menu.KEY_CATEGORIES:
		for a in cat[1]:
			listed[a] = true
	var missing := InputSetup.ACTIONS.keys().filter(func(a): return not listed.has(a))
	check(missing.is_empty(), "Tastenmenü: alle InputSetup-Aktionen erreichbar", str(missing))
	menu.options_page = "keys"
	menu._keys_category = 0
	menu._keys_part = 0
	menu.show_menu("options")
	await frames(2)
	# Blättern über alle Unterseiten: jede Aktion erscheint als Zeile, danach wieder Seite 1
	var seen := {}
	var pages := 0
	for c in menu.KEY_CATEGORIES.size():
		pages += menu._keys_parts(c)
	for i in pages:
		for b in menu.find_children("key_*", "Button", true, false):
			seen[String(b.name).substr(4)] = true
		(menu.find_child("bkeys_page", true, false) as Button).pressed.emit()
		await frames(2)
	check(seen.size() == InputSetup.ACTIONS.size() and menu._keys_category == 0 and menu._keys_part == 0,
		"Blättern: %d Seiten zeigen alle Aktionen, danach Seite 1" % pages, "%d/%d" % [seen.size(), InputSetup.ACTIONS.size()])
	menu._keys_prev_page()
	check(menu._keys_category == menu.KEY_CATEGORIES.size() - 1 and menu._keys_part == menu._keys_parts(menu._keys_category) - 1,
		"Zurückblättern von Seite 1 → letzte Seite")
	menu._keys_category = 0
	menu._keys_part = 0
	menu.show_menu("options")
	await frames(2)
	# Zeilen liegen über den Standard-Knöpfen (Stage-Koordinaten, Auflösung skaliert nur die Bühne)
	var low := 0.0
	for b in menu.find_children("key_*", "Button", true, false):
		low = maxf(low, (b as Button).position.y + (b as Button).size.y)
	check(low <= 626.0, "Belegungszeilen enden vor STANDARD-Knöpfen", str(low))
	# Umbelegen per Menü: Zeile anklicken, Taste drücken
	var row := menu.find_child("key_lean_left", true, false) as Button
	var lean = InputSetup.spec_of("lean_left")
	row.pressed.emit()
	await frames(2)
	check(menu._waiting_action == "lean_left", "Zeile anklicken wartet auf Taste")
	menu._input(_key(KEY_ESCAPE))
	await frames(2)
	check(menu._waiting_action == "" and sp("lean_left") == str(lean), "Esc bricht ab, Belegung unverändert")
	menu._waiting_action = "jump"
	menu._input(_key(KEY_K))
	await frames(2)
	check(sp("jump") == str(KEY_K), "Umbelegen mit Tastatur (K)")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	menu._waiting_action = "climb"
	menu._input(wheel)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	menu._waiting_action = "speed_up"
	menu._input(mb)
	await frames(2)
	check(sp("climb") == "mouse:%d" % MOUSE_BUTTON_WHEEL_UP and InputSetup.binding_text("climb") == "Rad hoch"
		and sp("speed_up") == "mouse:%d" % MOUSE_BUTTON_XBUTTON1, "Umbelegen mit Mausrad und Maustaste")
	# Doppelbelegung: jump bekommt W → move_forward erhält K (Tausch)
	var swapped: Array = InputSetup.rebind("jump", _key(KEY_W))
	check(swapped == ["move_forward"] and sp("move_forward") == str(KEY_K) and sp("jump") == str(KEY_W),
		"Doppelbelegung wird getauscht", str(swapped))
	check(InputSetup.conflicts("tac_regroup", KEY_W).is_empty(), "Taktik-Kontext kollidiert nicht mit Spieltasten")
	# Löschen per Rechtsklick
	menu.show_menu("options")
	await frames(2)
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	(menu.find_child("key_run", true, false) as Button).gui_input.emit(rc)
	await frames(2)
	check(sp("run") == "<null>" and InputSetup.binding_text("run") == "—", "Rechtsklick löscht Taste (unbelegt)")
	# Speichern → Neustart simulieren (Standard laden) → gespeicherte Belegung lesen
	var path := "user://test_ui_flow/keys_roundtrip.cfg"
	DirAccess.make_dir_recursive_absolute("user://test_ui_flow")
	var cfg := ConfigFile.new()
	InputSetup.write_keys(cfg)
	check(cfg.save(path) == OK, "Belegung gespeichert")
	InputSetup.read_keys(null)
	check(sp("jump") == "<null>" and sp("run") != "<null>", "Neustart: Standardbelegung aktiv")
	var cfg2 := ConfigFile.new()
	cfg2.load(path)
	InputSetup.read_keys(cfg2)
	check(sp("jump") == str(KEY_W) and sp("move_forward") == str(KEY_K) and sp("run") == "<null>"
		and sp("climb") == "mouse:%d" % MOUSE_BUTTON_WHEEL_UP, "Neu laden: Umbelegung, Tausch, unbelegt und Mausrad erhalten")
	# Standard wiederherstellen per Menüknopf
	(menu.find_child("bdefault1", true, false) as Button).pressed.emit()
	await frames(2)
	check(sp("move_forward") == str(KEY_W) and sp("jump") == "<null>", "STANDARD-EINSTELLUNGEN 1 stellt Vorgabe her")
	DirAccess.remove_absolute(path)
	menu.options_page = "graphics"


func _run() -> void:
	await frames(10)
	var menu := get_tree().current_scene
	Game.create_profile("UiFlow", 3)
	menu.show_menu("main_menu")
	await frames(2)
	# --- FILME (Original: single mission 2, Titel 2109, Liste 159) ---
	var bc := btn("bcinematics")
	check(bc != null and not bc.disabled, "Hauptmenü: FILME freigegeben")
	bc.pressed.emit()
	await frames(2)
	check(menu.current_menu == "cinematics", "FILME geöffnet")
	var intro := menu.find_child("film_Intro", true, false) as Button
	var arc := menu.find_child("film_IntroArctic", true, false) as Button
	check(intro != null and not intro.disabled and arc != null and arc.disabled, "Filmliste: Intro gesehen (ab Werk), Kampagnen-Intros gesperrt")
	intro.pressed.emit()
	await frames(2)
	var play := menu.find_child("PlayFilm", true, false) as Button
	var have := Game.movie_path("Intro") != ""
	check(play != null and play.disabled == not have, "SPIELEN nur mit konvertiertem Film (orig_cache/movies)", "Film vorhanden: %s" % have)
	Game.mark_film_seen("IntroArctic")
	menu.show_menu("cinematics")
	await frames(2)
	check(not (menu.find_child("film_IntroArctic", true, false) as Button).disabled, "Gesehener Film wird freigeschaltet (Profil)")
	check(Game.mission_videos("a1_blizzard") == ["IntroArctic", "BriefArctic1a"] and Game.mission_videos("a2_erkundung") == ["BriefArctic1b"],
		"Videoknoten: Kampagnen-Intro + Briefing-Video (Gamedata00.gdt)", str(Game.mission_videos("a1_blizzard")))

	# --- Spielmodi ---
	menu.show_menu("singleplayer")
	await frames(2)
	for n in ["blone wolf", "carnage", "bsingle mission- carnage"]:
		check(btn(n) != null and not btn(n).disabled, "Einzelspieler: „%s“ freigegeben" % n)
	btn("blone wolf").pressed.emit()
	await frames(2)
	check(menu.current_menu == "campaign" and Game.game_mode == Game.MODE_LONE_WOLF and Game.team_size() == 1
		and (menu.find_child("ListTitle", true, false) as Label).text == menu.text(2203), "EINZELGÄNGER: Kampagnenliste, Team aus einem Mann")
	btn("bexit").pressed.emit()
	await frames(2)
	btn("carnage").pressed.emit()
	await frames(2)
	check(Game.game_mode == Game.MODE_CARNAGE and Game.sp_game_type() == 3, "BLUTBAD: Spieltyp 3 für die Skripte")
	btn("bexit").pressed.emit()
	await frames(2)
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	Game.campaign["completed"] = ["a1_blizzard"]
	Game.campaign["unlocked"] = ["a1_blizzard", "a2_erkundung"]
	Game.save_campaign()
	menu.show_menu("singleplayer")
	await frames(2)
	btn("bsingle mission- carnage").pressed.emit()
	await frames(2)
	var ids: Array = []
	for c in menu.stage.get_children():
		if c is Button and c.has_meta("mission"):
			ids.append(String(c.get_meta("mission")))
	check(menu.current_menu == "single_mission" and Game.single_mission and Game.sp_game_type() == 7
		and ids.has("a2_erkundung") and not ids.has("m01_funkfeuer"), "EINZELMISSION – BLUTBAD: freigeschaltete Originalteile", str(ids))
	Game.campaign["completed"].append("a2_erkundung")
	btn("bexit").pressed.emit()
	await frames(2)
	check(not Game.single_mission and not Game.campaign.get("completed", []).has("a2_erkundung"),
		"Einzelmission ändert den Kampagnenstand nicht (Kopie verworfen)")

	# --- Inventar: Ziehen und Ablegen, Beschreibung, eigene Vorlagen ---
	Game.prepare_sas("a1_blizzard", true)
	var scr := SasScreen.new()
	get_tree().root.add_child(scr)
	scr.open("a1_blizzard")
	scr.show_equipment()
	await frames(2)
	var sold: int = scr.focus_idx
	var inv := Game.sas_inventory(sold)
	# leichtester Gegenstand im Lager, der kein Ausrüstungsplatz ist (passt sicher in Taschen/Rucksack)
	var light := -1
	for e in Game.campaign.get("storage", []):
		if int(e[1]) > 0 and SAS.slot_for(int(e[0])) == "" and (light < 0 or SAS.weight(int(e[0])) < SAS.weight(light)):
			light = int(e[0])
	var colt0 := SAS.count_of(inv, light)
	check(scr.find_child("InvArea", true, false) != null and scr.find_child("StoreArea", true, false) != null, "Ablageflächen Taschen/Rucksack und Lager")
	var ok: bool = scr.drop_item({"from": "store", "id": light}, "inv")
	await frames(2)
	check(ok and SAS.count_of(Game.sas_inventory(sold), light) == colt0 + 1, "Ziehen: Lager → Taschen (%s)" % SAS.item_label(light))
	ok = scr.drop_item({"from": "inv", "id": light}, "drop")
	await frames(2)
	check(ok and SAS.count_of(Game.sas_inventory(sold), light) == colt0, "Ziehen: Taschen → „Ablegen“ (zurück ins Lager)")
	var hands := int(Game.sas_inventory(sold).get("hands", -1))
	if hands >= 0:
		ok = scr.drop_item({"from": "slot", "slot": "hands", "id": hands}, "slot:shoulder")
		await frames(2)
		check(ok and int(Game.sas_inventory(sold).get("shoulder", -1)) == hands, "Ziehen: Hände → Schulter")
		scr.drop_item({"from": "slot", "slot": "shoulder", "id": hands}, "slot:hands")
		await frames(2)
	check(not scr._can_drop(Vector2.ZERO, {"from": "store", "id": 2}, "slot:head"), "Ungültiges Ziel (Pistole auf den Kopf) abgelehnt")
	scr.show_description(21, Vector2(400, 300))
	await frames(1)
	var dt := scr.find_child("DescriptionText", true, false) as Label
	check(dt != null and dt.text.contains(SAS.item_label(21)) and dt.text.contains(SAS.text(2730, "Gewicht")),
		"Beschreibung (description.4ds): Name, Gewicht, Magazin", dt.text.replace("\n", " | ") if dt else "-")
	# eigene Vorlage speichern und anwenden
	scr.save_user_preset(0)
	check(FileAccess.file_exists(Game.profile_dir() + "/user_presets_orig.def"), "user_presets_orig.def angelegt")
	var up: Dictionary = UP.sp_presets()[0]
	check(not UP.is_empty(up) and int(up["slots"][1]) == int(Game.sas_inventory(sold).get("hands", -1)),
		"Vorlage 1: Ausrüstung gespeichert (Original-Format v3, 440 Byte je Satz)", UP.label(up))
	var f := FileAccess.open(Game.profile_dir() + "/user_presets_orig.def", FileAccess.READ)
	check(f != null and f.get_32() == 3 and f.get_32() == 24 and f.get_length() == 8 + 24 * 440, "Dateiformat: Version 3, 24 Vorlagen")
	f = null
	var before := SAS.inv_weight(Game.sas_inventory(sold))
	scr.apply_preset(sold, -1)
	scr._apply_inventory(sold, SAS.new_inventory())
	check(SAS.inv_weight(Game.sas_inventory(sold)) < 0.01, "Ausrüstung abgelegt")
	scr.apply_user_preset(sold, 0)
	await frames(2)
	check(absf(SAS.inv_weight(Game.sas_inventory(sold)) - before) < 0.01, "Eigene Vorlage angewandt (aus dem Lager)",
		"%.2f / %.2f kg" % [SAS.inv_weight(Game.sas_inventory(sold)), before])
	scr.dropdown = "type"
	scr.show_equipment()
	await frames(2)
	check(scr.find_child("UserPreset0", true, false) != null and scr.find_child("UserPreset5", true, false) != null,
		"Vorlagenliste: eigene Vorlagen „Leer 1…6“")
	scr.queue_free()

	# --- Mehrspieler SPIELER-SETUP: Figurwahl (mit lokalen Helden, falls vorhanden) ---
	var ps := PlayerSetupScreen.new()
	get_tree().root.add_child(ps)
	ps.open(String(Game.MP_MAPS[0]) if not Game.MP_MAPS.is_empty() else "")
	await frames(2)
	var fids: Array = Net.figure_ids()
	var hs: Array = Net.heroes()                    # Helden nur mit lokaler Datei (nicht im Repository)
	var h_axis: Dictionary = Net.hero_of("axis")
	var pick: String = "hero:axis" if not h_axis.is_empty() else String(fids[0])
	# 0.11.1: Reihenfolge SAS-Kader „sas:N“ → „MP 1…27“ → Helden (ganz hinten)
	var fig_rank := func(f) -> int:
		var s := String(f)
		return 0 if s.begins_with("sas:") else (1 if s.begins_with("mp:") else (2 if s.begins_with("hero:") else 9))
	var ranks: Array = fids.map(fig_rank)
	var ordered := not ranks.has(9)
	for i in range(1, ranks.size()):
		if int(ranks[i]) < int(ranks[i - 1]):
			ordered = false
	var n_mp := ranks.count(1)
	if hs.is_empty():
		check(ordered and n_mp >= 20 and not ranks.has(2),
			"Figurliste ohne lokale Helden: SAS-Kader, dann MP 1…27", str(fids.size()))
	else:
		check(ordered and n_mp >= 20 and int(ranks[ranks.size() - 1]) == 2,
			"Figurliste: Helden ganz hinten (nach SAS-Kader und MP 1…27)")
	ps.fig_ofs = maxi(fids.size() - 4, 0)          # Porträtstreifen ans Ende blättern (Helden)
	ps.build()
	await frames(2)
	if not hs.is_empty():
		var hall := fids.size() >= 20
		for h in hs:
			var hid := "hero:" + String(h.get("team", ""))
			hall = hall and fids.has(hid) and ps.find_child("Figure_" + hid.replace(":", "_"), true, false) != null
		check(hall, "Figuren: lokale Helden + MP 1…27, Porträtstreifen zeigt die Helden", str(fids.size()))
	ps._pick_figure(false, pick)
	await frames(3)
	var fname := ps.find_child("FigureName", true, false) as Label
	check(fname != null and fname.text == Net.figure_name(pick)
			and (h_axis.is_empty() or ps.team_pref == Soldier.TEAM_AXIS or ps._deathmatch()),
		"Figur gewählt (Held der Achse → Wehrmacht, Deathmatch: keine Seite)",
		"%s, Seite %d, DM %s" % [fname.text if fname else "-", ps.team_pref, ps._deathmatch()])
	if not h_axis.is_empty():
		check(Net.figure_model(pick, "axis") == String(h_axis.get("model", "")), "Held: eigenes Modell")
	check(Net.figure_face(pick) != null and Net.figure_face("mp:30") != null, "Gesichtstexturen (gewählte Figur, MP-Figur)")
	var faced := false
	if ps.preview_model:
		for mi in ps.preview_model.find_children("*", "MeshInstance3D", true, false):
			for si in (mi as MeshInstance3D).get_surface_override_material_count():
				if (mi as MeshInstance3D).get_surface_override_material(si) != null:
					faced = true
	check(ps.preview != null and (ps.preview_model == null or faced), "3D-Vorschau mit Gesichtstextur",
		"Modell: %s" % (ps.preview_model != null))
	var ofs0: int = ps.fig_ofs           # Helden stehen am Ende: Bildlauf zurück prüfen
	ps._scroll_figures(-1)
	await frames(2)
	check(ps.fig_ofs == ofs0 - 1, "Bildlauf durch die Figuren")
	ps.accept()
	check(Net.local_figure == pick, "AKZEPTIEREN überträgt die Figur (Net.request_figure)")
	Net.local_figure = ""
	ps.queue_free()
	# Spawn mit gewählter Figur (Net._attach_figure): Spieler-Figur „Held“ auf der eigenen Seite, Bots unverändert
	var fm := FakeMission.new()
	var s := Soldier.new()
	get_tree().root.add_child(s)
	await frames(1)
	Net._attach_figure(fm, s, Soldier.TEAM_AXIS, {"figure": "hero:axis"})
	var faced2 := 0
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			var mat := (mi as MeshInstance3D).get_surface_override_material(si) as StandardMaterial3D
			if mat and mat.resource_name.to_upper().begins_with("E_F0"):
				faced2 += 1
	check(fm.orig.requested == ["ge01a"] and faced2 > 0, "Spieler erscheint mit gewählter Figur (ge01a + Heldengesicht)",
		"%s, %d Gesichtsflächen" % [str(fm.orig.requested), faced2])
	fm.orig.requested.clear()
	Net._attach_figure(fm, s, Soldier.TEAM_ALLIED, {"figure": "hero:axis"})
	check(fm.orig.requested == ["en01"], "Held der Gegenseite gewählt → Held der eigenen Armee (en01)", str(fm.orig.requested))
	s.queue_free()
	fm.free()
	await _keys_rebind_roundtrip(menu)
	Game.delete_profile("UiFlow")
	_finish()
