extends "res://tests/test_gameplay.gd"
## Original-Klänge und -Musik (OrigAudio, orig_cache/sounds.json, surface.bin): Zuordnungen vorhanden und ladbar,
## Waffen nutzen Original-Klänge, Schritte je Untergrund, Musikwechsel Normal/Action/Ereignis.
## Headless gibt es keine Audioausgabe – geprüft werden Zuordnung, Dateien und Abspielaufrufe (OrigAudio.history).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_audio


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and Game.current_mission_id == "a1_blizzard", "Original-Mission Arctic 1A geladen")
	check(OrigAudio.available(), "sounds.json geladen (tools/fmt_sounds.py)")
	var cats: Array = OrigAudio.data.get("categories", [])
	check(cats.size() == 14 and (cats[2]["groups"] as Array).size() >= 50, "Klangtabelle IngameSounds.def: 14 Kategorien",
		"%d Kategorien" % cats.size())

	# --- alle Tabellendateien vorhanden (bis auf die in der Installation fehlenden) und je Kategorie ladbar ---
	var total := 0
	var have := 0
	var loaded := 0
	for c in cats:
		var first := true
		for g in c["groups"]:
			for v in g["variants"]:
				total += 1
				if OrigAudio.has_file(String(v["file"])):
					have += 1
					if first:
						first = false
						if OrigAudio.stream(String(v["file"])) != null:
							loaded += 1
	var missing: Array = OrigAudio.data.get("missing_files", [])
	check(have + missing.size() == total and missing.size() <= 61, "Alle Tabellenklänge im Cache (fehlend nur Datadisk-Dateien)",
		"%d von %d, fehlend %d" % [have, total, missing.size()])
	check(loaded >= 12, "Je Kategorie eine Datei als AudioStream ladbar", str(loaded))
	var music_dir := DirAccess.get_files_at(OrigLevel.cache_root() + "/music")
	check(music_dir.size() >= 43, "Alle 43 Original-Musikstücke konvertiert", str(music_dir.size()))

	# --- Waffen: Zuordnung aus items.sav ---
	var w := func(id: StringName, kind: String) -> Array: return OrigAudio.weapon_sound(WeaponDB.get_weapon(id), kind)
	check(w.call(&"kar98k", "shoot") == [2, 5] and w.call(&"mp40", "shoot") == [2, 0] and w.call(&"colt", "shoot") == [2, 14],
		"Schussklänge: K98 „G K98 + Optics“, MP 40, Colt", str([w.call(&"kar98k", "shoot"), w.call(&"mp40", "shoot")]))
	check(w.call(&"kar98k_sd", "shoot") == [2, 15] and w.call(&"mp40_sd", "shoot") == [2, 2],
		"Vorgabe: K98k SD = De-Lisle-Schuss, MP 40 SD = Sten-Schalldämpfer")
	check(w.call(&"mp40", "reload") == [3, 2] and w.call(&"colt", "armed") == [3, 42] and w.call(&"kar98k", "bolt") == [3, 29]
		and w.call(&"garand", "last_shot") == [2, 29] and w.call(&"mp40", "empty") == [3, 4],
		"Nachladen, Ziehen, Repetieren, letzter Schuss (Garand), leerer Abzug")
	check(w.call(&"no36", "shoot") == [2, 42] and w.call(&"m24", "shoot") == [2, 43] and w.call(&"bazooka", "shoot") == [2, 25],
		"Granatwurf No. 36 / Stielhandgranate, Bazooka")
	var knife := WeaponDB.get_weapon(&"knife")
	check(OrigAudio.weapon_sound(knife, "shoot", Soldier.TEAM_AXIS) == [2, 40] and OrigAudio.weapon_sound(knife, "shoot", Soldier.TEAM_ALLIED) == [2, 41],
		"Messer: G Knife (Achse) / B Knife (Alliierte)")

	# --- Schuss im Spiel nutzt den Original-Klang ---
	isolate_enemies([])
	var s: Soldier = m.squad.leader()
	var n0 := OrigAudio.played_count("weapon:shoot")
	var wpn := s.current_weapon()
	check(wpn != null, "Soldat hat eine Waffe", str(wpn))
	if wpn:
		s._fire_shot(wpn)
		var last := OrigAudio.last_played("weapon:shoot")
		var want := OrigAudio.weapon_sound(wpn.data, "shoot", s.team)
		check(OrigAudio.played_count("weapon:shoot") == n0 + 1 and String(last.get("file", "")) == String(wpn.data.id)
			and [int(last["cat"]), int(last["id"])] == want, "Feuern spielt den Original-Schussklang der Waffe", str(last))

	# --- Untergrund (tree.klz) -> Schrittklang ---
	check(OrigAudio.surface != null and OrigAudio.surface.count > 10000, "surface.bin geladen (tree.klz-Material)",
		str(OrigAudio.surface.count if OrigAudio.surface else 0))
	var mat := OrigAudio.floor_material(s.global_position)
	var grp := int(OrigAudio.material_info(mat).get("step_sound", -1))
	check(mat >= 0 and grp >= 0, "Boden unter dem Soldaten: Material und Schrittgruppe",
		"Material %d %s -> Kat. 0/%d" % [mat, OrigAudio.material_info(mat).get("name", "?"), grp])
	var st0 := OrigAudio.played_count("step")
	var p := OrigAudio.play_step(s.global_position)
	check(p != null and p.stream != null and OrigAudio.played_count("step") == st0 + 1, "Schrittklang je Untergrund spielt")
	check(OrigAudio.material_info(34).get("step_sound", -1) == 7 and OrigAudio.material_info(50).get("step_sound", -1) == 1
		and OrigAudio.material_info(56).get("hit_sound", -1) == 8, "hdmaterials.def: Schnee -> Snow, Gras -> Grass, Hauswand -> Bricks")
	var i0 := OrigAudio.played_count("impact")
	Effects.impact(s.global_position + Vector3(2, 0.02, 0), Vector3.UP)
	check(OrigAudio.played_count("impact") == i0 + 1, "Einschlag spielt Original-Einschlagklang", str(OrigAudio.last_played("impact")))

	# --- Figurenklänge (hd2.exe-Tabelle) ---
	var h := OrigAudio.human_event("to_prone", s.global_position, s)
	check(h != null and OrigAudio.last_played("human:to_prone").get("file", "") == "o_lay.wav", "Haltungswechsel: o_lay.wav (Ereignis 4)")

	# --- Sprache ---
	var e: Soldier = m.enemies[0]
	var vs := OrigAudio.voice_set_of(e)
	check(vs in [9, 10, 11, 12], "Gegner nutzt deutschen Sprachsatz aus actors.bin", str(vs))
	e.set_meta("_speech_until", -1.0)
	var dur := OrigAudio.speak_event(e, OrigAudio.EV_E_SEE)
	var sp := OrigAudio.last_played("speech")
	check(dur > 0.2 and String(sp.get("file", "")).begins_with("9000"), "Gegner-Ruf „Ich sehe ihn“ (deutsche Aufnahme)", str(sp))
	var vs1 := OrigAudio.voice_set_of(s)
	check(vs1 >= 1 and vs1 <= 4 and not OrigAudio.speech_ids(vs1, OrigAudio.EV_HURT).is_empty(), "Trupp: English #Teamplatz mit Schmerzlauten")

	# --- Musik: Normal / Action / Ereignis ---
	check(OrigAudio.music_file == "ar1.ogg", "Missionsmusik Normal ar1.ogg (scene2.bin 0xB840 = 19)", OrigAudio.music_file)
	OrigAudio._combatants.clear()
	var dummy := Node.new()
	add_child(dummy)
	OrigAudio.set_combat(dummy, true)
	await seconds(5.0)
	check(OrigAudio.music_file == "ar1_a.ogg", "Gegner im Kampf -> Action-Musik ar1_a.ogg (Überblendung 4 s)", OrigAudio.music_file)
	OrigAudio.set_combat(dummy, false)
	await seconds(5.0)
	check(OrigAudio.music_file == "ar1.ogg", "Kein Gegner mehr im Kampf -> Normalmusik", OrigAudio.music_file)
	OrigAudio.script_play_music(36)
	await seconds(5.0)
	check(OrigAudio.music_file == "event victory.ogg", "Skript PlayMusic(36) -> „Event Victory“", OrigAudio.music_file)
	OrigAudio.script_play_music(-1)
	await seconds(5.0)
	check(OrigAudio.music_file == "ar1.ogg", "PlayMusic(-1) -> zurück zur Missionsmusik", OrigAudio.music_file)
	check(OrigAudio.play_cutscene_music(15) and OrigAudio._vol_target < 0.2, "PlayCutsceneMusic: Einlage, Missionsmusik gedämpft")
	OrigAudio.stop_cutscene_music()

	# --- Türen, Fahrzeuge, Menü ---
	var door: Node = null
	for c in m.dynamic_root.get_children():
		if c is OrigInteractive.OrigDoor and not ((c as OrigInteractive.OrigDoor).p.get("sound_slots", {}) as Dictionary).is_empty():
			door = c
			break
	if door:
		var d0 := OrigAudio.played_count("group", OrigAudio.CAT_OBJECT)
		door.locked = false
		door.set_open(not door.is_open)
		check(OrigAudio.played_count("group", OrigAudio.CAT_OBJECT) > d0, "Tür: Original-Türklang (Akteur-Chunk 0x65)")
	else:
		check(false, "Tür mit Original-Klängen gefunden")
	var car: Vehicle = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not (v as Vehicle).sound_files.is_empty():
			car = v
	check(car != null, "Fahrzeug mit Original-Motorklängen (actors.bin-Parameterblock)")
	if car:
		car._classify_sounds()
		check((car._snd["levels"] as Array).size() >= 3 and String(car._snd["idle"]) != "" and String(car._snd["on"]) != "",
			"Motor: Start, Leerlauf, Fahrstufen", str(car._snd))
	OrigAudio.play_ui("button")
	check(OrigAudio.last_played("ui").get("file", "") == "button.wav", "Menüklick button.wav (Kat. 10)")
	check(OrigAudio.music_file_of(0) in ["main menu.ogg", "main menu 2.ogg"] and OrigAudio.music_file_of(1) == "success menu.ogg",
		"Musiktabelle: Hauptmenü, Erfolg")
	for bus in ["Music", "SFX", "Voice"]:
		check(AudioServer.get_bus_index(bus) >= 0, "Audiobus %s (Lautstärke-Regler)" % bus)
	check(not Effects.has_method("_synth_shot"), "Keine synthetisierten Klänge mehr")
	_finish()
