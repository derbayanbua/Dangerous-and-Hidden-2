extends "res://tests/test_gameplay.gd"
## Kampagnenfluss: Freischaltung, gefallene Kadermitglieder bleiben gefallen.
##   tools\godot.cmd --headless -- --autoplay=test_campaign
## (Kampagne läuft im Speicher; user://campaign.json wird nicht verändert.)


func find_button(prefix: String) -> Button:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix):
			return b
	return null


func wait_mission(prev: Node = null) -> Mission:
	for i in 3000:
		await get_tree().process_frame
		var m := mission()
		if m and m != prev and m.squad and m.squad.leader():
			return m
	return null


func _run() -> void:
	await frames(10)
	check(Game.is_unlocked("a1_blizzard") and not Game.is_unlocked("a2_erkundung"), "Neue Kampagne: nur Arctic 1A frei")
	check(Game.is_unlocked("m01_funkfeuer"), "Übungseinsätze ohne Freischaltung wählbar")
	get_tree().current_scene.show_menu("campaign")      # Einzelspieler -> Kampagne (Original-Menüaufbau)
	await frames(3)
	var b2 := find_button("2.")
	check(b2 != null and b2.disabled, "Kampagnenliste: Teil 1B gesperrt", b2.text if b2 else "-")
	check(Game.briefing_text("a1_blizzard").begins_with("Operation Schneeball"), "Briefing aus Originaltexten",
		Game.briefing_text("a1_blizzard").substr(0, 60))

	# Start über die Oberfläche wie ein Spieler: Kampagne -> Mission wählen -> START -> Einsatz beginnen
	var menu := get_tree().current_scene
	var b1 := find_button("1.")
	check(b1 != null and not b1.disabled, "Kampagnenliste: Teil 1A wählbar", b1.text if b1 else "-")
	check(menu._start_btn != null and menu._start_btn.disabled, "START gesperrt, solange keine Mission gewählt ist")
	b1.pressed.emit()
	await frames(2)
	check(not menu._start_btn.disabled, "START nach Auswahl freigegeben")
	menu._start_btn.pressed.emit()
	await frames(3)
	check(menu._brief_root != null and is_instance_valid(menu._brief_root), "START öffnet die Einsatzbesprechung")
	var go := find_button("Team und Ausrüstung")
	check(go != null, "Knopf „Team und Ausrüstung“ vorhanden (Originalkader)")

	# Original-Ablauf: Teamauswahl (Arctic1 = Kampagnenbeginn) -> Inventar-Auswahl -> Einsatz
	var started := false
	if go:
		go.pressed.emit()
		await frames(3)
		var scr: SasScreen = menu.sas_screen
		check(scr != null and scr.page == "team" and Game.sas_team().size() == 4, "Teamauswahl mit 4 SAS-Soldaten",
			"%s %s" % [scr.page if scr else "-", Game.sas_team()])
		if scr:
			var cont := scr.find_child("Continue", true, false) as Button
			check(cont != null and not cont.disabled, "FORTSETZEN (Text 2653) aktiv")
			if cont:
				cont.pressed.emit()
			await frames(3)
			check(scr.page == "equip" and scr.can_start() == "", "Ausrüstung: empfohlene Auswahl, nicht überladen", scr.can_start())
			started = scr.try_start()
	if not started:
		Game.start_mission("a1_blizzard")
	var m := await wait_mission() as OrigMission
	check(m != null and m.squad.members.size() == 4, "Arctic 1A mit vollem Kader")
	check(m != null and Game.is_sas_pid(m.squad.members[0].persistent_id) and m.squad.members[0].skill_shooting > 0.0,
		"Trupp = Original-SAS-Soldaten mit Werten", m.squad.members[0].soldier_name if m else "-")
	isolate_enemies([])
	var second: Soldier = m.squad.members[1]
	var second_name := second.soldier_name
	var second_pid := second.persistent_id
	second.die(null)
	m.runtime.game_values[30] = 99      # wie SaveGameValue(30, 99) im Originalskript
	# Originalskript r_arc1a_objectives: OnCutscene(1) aktiviert Ziel 3 erst mit der Intro-Sequenz –
	# vorher gesetzte Ziele würden zurückgesetzt. Darauf warten.
	for attempt in 6:
		for i in range(1, 5):
			m.set_orig_objective(i, 1)
		await seconds(3.5)   # Siegbedingung muss 3 s stabil sein
		if m.finished:
			break
	check(Game.last_result.get("mission", "") == "a1_blizzard" and Game.last_result.get("success", false),
		"Arctic 1A erfolgreich (alle Pflichtziele)", str(Game.last_result.get("reason", "")) + " | " +
		str(m.objectives.map(func(o): return "%s:%d%s" % [o.id, o.state, "o" if o.optional else ""])) + " " + str(m.orig_objectives))
	check(Game.last_result.get("fallen", []).has(second_name), "Nachbesprechung nennt Gefallenen")
	# Original 0x68C300: Übernahme erst mit SPEICHERN UND FORTSETZEN
	check(not Game.is_unlocked("a2_erkundung") and not Game.is_fallen(second_pid) and Game.has_pending_debrief(),
		"Vor SPEICHERN UND FORTSETZEN: Kampagnenstand unverändert (vorbereitet)")

	for i in 400:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.name == "Debrief":
			break
	var deb := get_tree().current_scene
	check(deb != null and deb.name == "Debrief", "Nachbesprechung angezeigt")
	await frames(3)
	var members: Array = Game.last_result.get("sas", {}).get("members", [])
	check(members.size() == 4 and members.filter(func(x): return bool(x["dead"])).size() == 1,
		"Nachbesprechung: 4 Soldatenpanels, einer gefallen", str(members.map(func(x): return x["name"])))
	check(deb.find_child("SoldierName", true, false) != null and deb.find_child("RankBadge", true, false) != null
		and deb.find_child("Value_shooting", true, false) != null, "Soldatenpanel: Name, Rangabzeichen, Werteleisten")
	# Tagebuch (ADDDIARYTEXT): Eintrag des Einsatzes erscheint auf der Tagebuchseite
	Game.add_diary_text(4501)
	(deb.find_child("Diary", true, false) as Button).pressed.emit()
	await frames(3)
	var dl := deb.find_child("DiaryLeft", true, false) as Label
	var dr := deb.find_child("DiaryRight", true, false) as Label
	var dtxt: String = (dl.text if dl else "") + "\n" + (dr.text if dr else "")
	check(dtxt.contains(SAS.text(4501, "?")), "TAGEBUCH zeigt den Eintrag (ADDDIARYTEXT)", dtxt.substr(0, 80))
	(deb.find_child("DiaryBack", true, false) as Button).pressed.emit()
	await frames(3)
	var sc := deb.find_child("SaveContinue", true, false) as Button
	check(sc != null and not sc.disabled, "SPEICHERN UND FORTSETZEN aktiv (Erfolg)")
	if sc:
		sc.pressed.emit()
	await frames(2)
	var yes := deb.find_child("Dialog0", true, false) as Button
	check(yes != null, "Rückfrage „%s“" % SAS.text(9523, "Wollen Sie das Spiel speichern?"))
	if yes:
		yes.pressed.emit()
	for i in 200:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.name != "Debrief" and get_tree().current_scene.has_method("show_menu"):
			break
	await frames(5)
	check(Game.is_unlocked("a2_erkundung"), "Teil 1B freigeschaltet")
	check(Game.is_fallen(second_pid), "Gefallener im Kader vermerkt")
	check(Game.orig_game_values().get(30) == 99, "SaveGameValue-Werte für den nächsten Teil gesichert")
	check(Game.diary_entries().has(4501), "Tagebuch in den Kampagnenstand übernommen")
	var menu2 := get_tree().current_scene
	check(menu2 != null and menu2.get("current_menu") == "campaign" and menu2.get("selected_mission") == "a2_erkundung",
		"Danach Missionsliste mit dem nächsten Teil gewählt", str(menu2.get("selected_mission")) if menu2 else "-")
	# Teil 1C: vier Kommandos laut Original -> Ersatzmann rückt nach; Skriptwerte kommen an
	Game.start_mission("a3_rendezvous")
	var m3 := await wait_mission() as OrigMission
	var names := m3.squad.members.map(func(s): return s.soldier_name)
	check(not names.has(second_name), "Folgeteil ohne Gefallenen", ", ".join(names))
	# Original (Gamedata00.gdt): vor Arctic 1C kein Auffüllen – erst vor Arctic 2 („refill“)
	check(m3.squad.members.size() == 3, "Arctic 1C: Team bleibt ohne Ersatz (Original)", ", ".join(names))
	check(Game.sas_team_mode("a4_eisberg") == "refill", "Vor Arctic 2 (Eisberg): Team wieder auffüllen")
	check(m3.runtime.game_values.get(30) == 99, "_LoadGameValue(30) liefert Wert aus Teil 1A")
	Game.return_to_menu()
	await frames(30)
	get_tree().current_scene.show_menu("campaign")
	await frames(3)
	var b2b := find_button("2.")
	check(b2b != null and not b2b.disabled, "Kampagnenliste: Teil 1B jetzt wählbar", b2b.text if b2b else "-")
	_finish()
