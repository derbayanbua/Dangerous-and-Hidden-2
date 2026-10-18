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
	if hs.is_empty():
		check(fids.size() >= 20 and fids.all(func(f): return String(f).begins_with("mp:")),
			"Figurliste ohne lokale Helden: nur MP 1…27", str(fids.size()))
	else:
		check(String(fids[fids.size() - 1]).begins_with("hero:") and String(fids[0]).begins_with("mp:"),
			"Figurliste: Helden ganz hinten (nach MP 1…27)")
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
	Game.delete_profile("UiFlow")
	_finish()
