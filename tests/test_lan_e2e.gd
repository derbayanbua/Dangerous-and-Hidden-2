extends "res://tests/lan_ui_base.gd"
## LAN Ende-zu-Ende über die Menüs (Server-Seite): Hauptmenü → MEHRSPIELER-SPIEL – LAN → Formular per Klick/
## Tastatur ausfüllen → „Server starten“; startet einen zweiten Spielprozess (tests/test_lan_e2e_client.gd),
## der genauso über die Menüs beitritt (Serverliste, falsches/richtiges Passwort) und über das Pausenmenü
## wieder geht. Zum Schluss verlässt auch der Server die Runde über das Pausenmenü.
##   tools\godot.cmd --headless -- --autoplay=test_lan_e2e --profiles_dir=user://test_lan_host --noimport

const RESULT := "user://lan_e2e_client_result.txt"
const PW := "geheim"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	var menu := await menu_with_profile("Host")
	# --- Hauptmenü → LAN ---
	var lan_b := visible_button("bmultiplayerlan")
	check(lan_b != null and not lan_b.disabled, "Hauptmenü: „MEHRSPIELER-SPIEL – LAN“ mit Profil wählbar")
	var inet := visible_button("bmultiplayernet")
	check(inet != null and not inet.disabled, "Hauptmenü: „MEHRSPIELER-SPIEL – INTERNET“ wählbar")
	check(await click(lan_b), "LAN-Knopf angeklickt")
	await frames(5)
	var lm: LanMenu = menu.lan_menu
	check(lm != null and lm.is_visible_in_tree() and not menu.stage.visible, "LAN-Menü offen, Hauptmenü ausgeblendet")
	if lm == null:
		_finish()
		return
	check(Net.local_name == "Host", "Spielername aus dem Profil", Net.local_name)
	# --- Zurück und wieder hinein ---
	check(await click(visible_button("Zurück")), "„Zurück“ angeklickt")
	await frames(5)
	check(menu.lan_menu == null and menu.stage.visible, "Zurück im Hauptmenü")
	await click(visible_button("bmultiplayerlan"))
	await frames(5)
	lm = menu.lan_menu
	# --- Spielstil hängt an der Karte (Original-MP-Karten: fester Stil) ---
	var orig_idx := -1
	var arena_idx := -1
	for i in lm._map.item_count:
		var id := String(lm._map.get_item_metadata(i))
		if orig_idx < 0 and Game.MISSIONS[id].get("mp_mode") != null:
			orig_idx = i
		if id == "mp_arena_a1_blizzard":
			arena_idx = i
	check(orig_idx >= 0 and arena_idx >= 0, "Kartenliste: Original-MP-Karten und Arena-Karten", str(lm._map.item_count))
	lm._map.select(orig_idx)
	lm._map.item_selected.emit(orig_idx)
	var fixed := int(Game.MISSIONS[String(lm._map.get_item_metadata(orig_idx))]["mp_mode"])
	var others_locked := true
	for i in lm._mode.item_count:
		if i != fixed and not lm._mode.is_item_disabled(i):
			others_locked = false
	check(lm._mode.selected == fixed and others_locked, "Original-Karte: Spielstil fest (%s)" % Net.MODE_NAMES[fixed])
	lm._map.select(arena_idx)
	lm._map.item_selected.emit(arena_idx)
	check(not lm._mode.is_item_disabled(1) and lm._mode.is_item_disabled(2), "Arena-Karte: Deathmatch/Team-Deathmatch wählbar")
	lm._mode.select(1)
	# --- Formular per Tastatur ---
	await type_into(lm._name_edit, "E2E-Server")
	check(lm._name_edit.text == "E2E-Server", "Servername eingetippt", lm._name_edit.text)
	await type_into(lm._pw, PW)
	check(lm._pw.text == PW, "Passwort eingetippt")
	lm._bots.value = 2
	lm._respawn.value = 5
	lm._warm.value = 0
	lm._maxp.value = 8
	lm._time.value = 0
	lm._score.value = 0
	var cfg := lm.server_settings()
	check(cfg["name"] == "E2E-Server" and cfg["mode"] == Net.Mode.TEAM_DEATHMATCH and cfg["bots_per_team"] == 2
		and cfg["password"] == PW, "Servereinstellungen aus dem Formular", str(cfg))
	# --- Server starten (Klick) ---
	check(await click(lm.find_child("HostButton", true, false)), "„Server starten“ angeklickt")
	check(Net.is_online and multiplayer.is_server(), "Server läuft", Net.last_error)
	# Ladebildschirm (Original loader.4ds) mit Fortschrittsbalken während des Hintergrundladens
	var loading := func() -> bool:
		var ml = get_tree().root.get_node_or_null("MissionLoader")
		return ml != null and ml.is_loading() and ml.screen != null
	var saw_loader: bool = await wait_for(loading, 10.0)
	check(saw_loader or not MissionLoader.timing.is_empty(), "Ladebildschirm mit Fortschritt beim Kartenladen")
	var has_bots := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(1) and _bot_count() >= 4
	check(await wait_for(has_bots, 400.0), "Karte geladen, eigener Soldat und 4 KI-Soldaten", str(_bot_count()))
	var hidden := func() -> bool:
		var ml = get_tree().root.get_node_or_null("MissionLoader")
		return ml != null and not ml.is_loading() and not is_instance_valid(ml.screen)
	check(await wait_for(hidden, 20.0), "Ladebildschirm nach dem Laden ausgeblendet")
	var m := Game.current_mission()
	if m == null:
		_finish()
		return
	check(m.squad.leader() == Net._soldiers.get(1), "Eigener Soldat wird gesteuert")
	# --- zweiten Prozess (Client) starten ---
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/lan_e2e_client.log")
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog, ] + _project_args() + ["--",
		"--autoplay=test_lan_e2e_client", "--profiles_dir=user://test_lan_client", "--noimport"])
	check(pid > 0, "Client-Prozess gestartet")
	var joined := func() -> bool: return _client_id() != 0
	check(await wait_for(joined, 300.0), "Client über die Menüs beigetreten", str(Net.players.keys()))
	var cid := _client_id()
	if cid != 0:
		check(String(Net.players[cid]["name"]) == "Gast" and Net.humans() == 2, "Spielerliste: Host + Gast (KI zählt nicht)",
			str(Net.humans()))
		check(Net.board_text().contains("Gast"), "Punktetabelle zeigt den Gast")
		# SPIELER-SETUP des Gastes im Spiel: Klasse 0 + Seitenwechsel (vorgemerkt), Chat aus dem Setup
		var team0 := int(Net.players[cid]["team"])
		var setup := func() -> bool: return Net.players.has(cid) and int(Net.players[cid].get("cls", -1)) == 0 \
			and int(Net.players[cid].get("next_team", team0)) != team0
		check(await wait_for(setup, 400.0), "Server: SPIELER-SETUP des Gastes übernommen (Klasse, Seite ab Wiedereinstieg)",
			str(Net.players.get(cid, {})))
		var chat := func() -> bool: return Net.chat_log.any(func(e): return String(e["text"]) == "Hallo aus dem Setup")
		check(await wait_for(chat, 60.0), "Server: Chat aus dem SPIELER-SETUP empfangen")
		var ps: Soldier = Net._soldiers.get(cid)
		check(is_instance_valid(ps) and ps.team == team0, "Seitenwechsel wirkt nicht sofort")
		if is_instance_valid(ps):
			ps.set_meta("protect_until", 0)
			ps.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
		var resp := func() -> bool:
			var s2: Soldier = Net._soldiers.get(cid)
			return is_instance_valid(s2) and s2.alive and s2 != ps and s2.team != team0
		check(await wait_for(resp, 120.0), "Wiedereinstieg des Gastes auf der neuen Seite")
		# Client geht über sein Pausenmenü → Server entfernt Spieler und Figur
		var gone := func() -> bool: return not Net.players.has(cid) and not Net._soldiers.has(cid)
		check(await wait_for(gone, 400.0), "Gast hat verlassen: Spieler und Figur entfernt")
		check(_bot_count() == 4 and Net.is_online, "Server und KI-Soldaten laufen weiter")
	# Ergebnisse des Clients
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		var nm := line.substr(6)
		check(line.begins_with("PASS"), nm if nm.begins_with("Client") else "Client: " + nm)
	# --- Server verlässt über das Pausenmenü ---
	await leave_via_pause_menu("Server")
	_finish()


func _bot_count() -> int:
	var n := 0
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]):
			n += 1
	return n


func _client_id() -> int:
	for k in Net.players:
		if int(k) > 1 and Net._soldiers.has(k) and is_instance_valid(Net._soldiers[k]):
			return int(k)
	return 0


## Exportierter Build (Spieltest): kein Projektpfad – die EXE startet sich selbst; im Editor-Binary: --path
func _project_args() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	if OS.has_feature("template"):
		return []
	return ["--path", ProjectSettings.globalize_path("res://")]
