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
	var go := find_button("Einsatz beginnen")
	check(go != null, "Knopf „Einsatz beginnen“ vorhanden")

	# Teil 1A mit einem Gefallenen abschließen (Ziele wie per SetObjectiveStatus gesetzt)
	if go:
		go.pressed.emit()
	else:
		Game.start_mission("a1_blizzard")
	var m := await wait_mission() as OrigMission
	check(m != null and m.squad.members.size() == 4, "Arctic 1A mit vollem Kader")
	isolate_enemies([])
	var second: Soldier = m.squad.members[1]
	var second_name := second.soldier_name
	var second_pid := second.persistent_id
	second.die(null)
	m.runtime.game_values[30] = 99      # wie SaveGameValue(30, 99) im Originalskript
	for i in range(1, 5):
		m.set_orig_objective(i, 1)
	await frames(2)
	check(Game.last_result.get("mission", "") == "a1_blizzard" and Game.last_result.get("success", false),
		"Arctic 1A erfolgreich (alle Pflichtziele)", str(Game.last_result.get("reason", "")))
	check(Game.is_unlocked("a2_erkundung"), "Teil 1B freigeschaltet")
	check(Game.is_fallen(second_pid), "Gefallener im Kader vermerkt")
	check(Game.last_result.get("fallen", []).has(second_name), "Nachbesprechung nennt Gefallenen")
	check(Game.orig_game_values().get(30) == 99, "SaveGameValue-Werte für den nächsten Teil gesichert")

	for i in 400:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.name == "Debrief":
			break
	check(get_tree().current_scene != null and get_tree().current_scene.name == "Debrief", "Nachbesprechung angezeigt")
	# Teil 1C: vier Kommandos laut Original -> Ersatzmann rückt nach; Skriptwerte kommen an
	Game.start_mission("a3_rendezvous")
	var m3 := await wait_mission() as OrigMission
	var names := m3.squad.members.map(func(s): return s.soldier_name)
	check(not names.has(second_name), "Folgeteil ohne Gefallenen", ", ".join(names))
	check(m3.squad.members.size() == 4, "Ersatzmann aus der Reserve rückt nach", ", ".join(names))
	check(m3.runtime.game_values.get(30) == 99, "_LoadGameValue(30) liefert Wert aus Teil 1A")
	Game.return_to_menu()
	await frames(30)
	get_tree().current_scene.show_menu("campaign")
	await frames(3)
	var b2b := find_button("2.")
	check(b2b != null and not b2b.disabled, "Kampagnenliste: Teil 1B jetzt wählbar", b2b.text if b2b else "-")
	_finish()
