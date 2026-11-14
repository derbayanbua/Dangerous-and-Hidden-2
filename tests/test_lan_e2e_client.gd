extends "res://tests/lan_ui_base.gd"
## LAN Ende-zu-Ende (Client-Seite, von test_lan_e2e als zweiter Prozess gestartet): Hauptmenü → LAN →
## Server in der Liste anklicken → „Beitreten“ ohne Passwort (abgewiesen) → Passwort eintippen → beitreten,
## laufen, über das Pausenmenü verlassen. Ergebnisse nach user://lan_e2e_client_result.txt.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (Client)")
		_finish())
	_run.call_deferred()


func _run() -> void:
	var menu := await menu_with_profile("Gast")
	check(await click(visible_button("bmultiplayerlan")), "Client: LAN-Knopf angeklickt")
	await frames(5)
	var lm: LanMenu = menu.lan_menu
	if lm == null:
		check(false, "Client: LAN-Menü offen")
		_finish()
		return
	# 0.11.2: LAN-Liste im Original-Serverbrowser (multiplayer menu.4ds) / LAN list in the original server browser
	var br: ServerBrowserScreen = lm.browser
	# Fremde LAN-Server (z. B. Dauerläufe) möglich → Eintrag „E2E-Server“ suchen / other LAN servers may exist → find ours
	var idx_of := func() -> int:
		if not is_instance_valid(br):
			return -1
		for i in br.entries.size():
			if String(br.entries[i].get("name", "")).contains("E2E-Server"):
				return i
		return -1
	var row_of := func() -> Control:
		var i: int = idx_of.call()
		return br.stage.find_child("Row%d" % i, true, false) as Control if i >= 0 else null
	var listed := func() -> bool: return row_of.call() != null
	check(await wait_for(listed, 20.0), "Server erscheint in der LAN-Liste (Broadcast)")
	if not listed.call():
		_finish()
		return
	var ei: int = idx_of.call()
	var e0: Dictionary = br.entries[ei]
	var name_lbl := br.stage.find_child("RowName%d" % ei, true, false) as Label
	check(name_lbl != null and name_lbl.text.contains("E2E-Server") and int(e0.get("mode", -1)) == 1 and int(e0.get("bots", 0)) == 4
		and bool(e0.get("pw", false)) and int(e0.get("players", 0)) == 1 and int(e0.get("max", 0)) == 8,
		"Listeneintrag: Name, Stil, Spieler, KI, Passwort", str(e0))
	# Auswahl muss die sekündliche Aktualisierung überstehen (an zwei Aktualisierungen gekoppelt, nicht an Zeit)
	await click(row_of.call())
	var updates := [0]
	var cnt := func() -> void: updates[0] += 1
	Net.servers_updated.connect(cnt)
	var two := func() -> bool: return updates[0] >= 2
	await wait_for(two, 30.0)
	Net.servers_updated.disconnect(cnt)
	check(br.selected >= 0 and br.selected == idx_of.call(), "Auswahl bleibt bei Listenaktualisierung erhalten", "%d Aktualisierungen" % updates[0])
	# SPIEL-INFO (gameinfo.4ds) zum markierten Server: Server-Info, Regeln, Spielerliste
	lm.open_game_info()
	await frames(3)
	var gi: GameInfoScreen = lm.info_screen
	check(gi != null and String((gi.find_child("Info", true, false) as Label).text).contains("E2E-Server"),
		"%s: Server-Name und Regeln" % SAS.text(2312, "SPIEL-INFO"))
	check(gi != null and gi.find_child("Player0", true, false) != null, "SPIEL-INFO: Spielerliste (SPIELER-STATUS)")
	if gi:
		gi.closed.emit()
	await frames(3)
	check(lm.info_screen == null, "SPIEL-INFO geschlossen (ZURÜCK)")
	# --- ohne Passwort: abgewiesen ---
	# SPIEL BEITRETEN → Passwortabfrage (Server mit Passwort), leer bestätigen / join → password prompt, confirm empty
	check(await click(visible_button("JoinButton")), "„%s“ angeklickt" % SAS.text(2310, "SPIEL BEITRETEN"))
	await frames(2)
	var pw_ok := visible_button("IpJoin")
	check(pw_ok != null and br.find_child("PwEdit", true, false) != null, "Passwortabfrage vor dem Beitritt")
	check(await click(pw_ok), "Beitritt ohne Passwort bestätigt")
	var rejected := func() -> bool: return lm._status.text.contains("Falsches Passwort")
	check(await wait_for(rejected, 60.0), "Abgewiesen mit Meldung „Falsches Passwort“", lm._status.text)
	var offline := func() -> bool: return not Net.is_online and Game.current_mission() == null and lm.is_visible_in_tree()
	check(await wait_for(offline, 20.0), "Nach Abweisung: offline, im LAN-Menü")
	# --- mit Passwort ---
	await wait_for(listed, 20.0)
	if br.selected < 0 or br.selected != idx_of.call():
		await click(row_of.call())
	await frames(2)
	check(await click(visible_button("JoinButton")), "„%s“ angeklickt (mit Passwort)" % SAS.text(2310, "SPIEL BEITRETEN"))
	await frames(2)
	var pwe := br.find_child("PwEdit", true, false) as LineEdit
	if pwe:
		await type_into(pwe, "geheim")
		if pwe.text != "geheim":
			pwe.text = "geheim"       # kopflos 64×64 px: Feld liegt ggf. außerhalb des Fensters (nicht anklickbar)
	var ipj := visible_button("IpJoin")
	if not await click(ipj) and ipj:
		ipj.pressed.emit()
	var in_game := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1)
	check(await wait_for(in_game, 400.0), "Beigetreten: Karte geladen, eigener Soldat und Server-Soldat")
	var me: Soldier = Net._soldiers.get(Net.my_id())
	if not is_instance_valid(me):
		_finish()
		return
	var bots := 0
	for k in Net._soldiers:
		if int(k) < 0:
			bots += 1
	check(bots == 4, "KI-Soldaten des Servers sichtbar", str(bots))
	check(Game.current_mission().squad.leader() == me, "Eigener Soldat wird gesteuert")
	check(Game.current_mission().enemies.is_empty(), "Client rechnet keine KI (Server-Berechnung)")
	await frames(30)
	var p0 := me.global_position
	Input.action_press("move_forward")
	var walked := func() -> bool:
		var c: Soldier = Net._soldiers.get(Net.my_id())
		return is_instance_valid(c) and (c != me or c.global_position.distance_to(p0) > 0.5)
	var ok_walk: bool = await wait_for(walked, 30.0)
	Input.action_release("move_forward")
	var cur: Soldier = Net._soldiers.get(Net.my_id())
	check(ok_walk, "Eigene Bewegung", "%.1f m" % (cur.global_position.distance_to(p0) if is_instance_valid(cur) else -1.0))
	await frames(30)
	# --- SPIELER-SETUP im Spiel (Pausenmenü, T2521): Seite + Klasse + Chat, wirksam ab dem nächsten Wiedereinstieg ---
	await press_action("pause")
	await frames(3)
	var psb: Button = get_tree().root.find_child("PlayerSetupButton", true, false)
	check(psb != null and psb.is_visible_in_tree(), "Client: Pausenmenü bietet „%s“" % SAS.text(2521, "SPIELER-SETUP"))
	if psb and not await click(psb):
		psb.pressed.emit()
	await frames(3)
	var ps: Node = get_tree().root.find_child("PlayerSetup", true, false)
	check(ps != null, "Client: SPIELER-SETUP im Spiel geöffnet")
	if ps:
		var my_team := int(Net.players[Net.my_id()]["team"])
		var other := Soldier.TEAM_AXIS if my_team == Soldier.TEAM_ALLIED else Soldier.TEAM_ALLIED
		_hit(ps, "Side_" + ("axis" if other == Soldier.TEAM_AXIS else "allies"))
		await frames(2)
		_hit(ps, "ClassOpen")
		await frames(2)
		_hit(ps, "Class0")
		await frames(2)
		var ce: LineEdit = ps.get("_chat_edit")
		if ce:
			ce.text = "Hallo aus dem Setup"
			ce.text_submitted.emit(ce.text)
		var acc: Button = ps.find_child("Accept", true, false)
		check(acc != null, "Client: AKZEPTIEREN vorhanden")
		if acc and not await click(acc):
			acc.pressed.emit()
		await frames(5)
		check(Net.local_class == MpClasses.MEDIC, "Client: Klasse gewählt (%s)" % tr(MpClasses.NAMES[MpClasses.MEDIC]))
		var changed := func() -> bool: return int(Net.players[Net.my_id()].get("cls", -1)) == 0 \
			and int(Net.players[Net.my_id()].get("next_team", Net.players[Net.my_id()]["team"])) == other
		check(await wait_for(changed, 60.0), "Client: Server übernimmt Klasse und Seite (request_class/request_team)")
		await press_action("pause")        # Pausenmenü schließen
		# Server tötet den Soldaten → Wiedereinstieg auf der neuen Seite
		var respawned := func() -> bool:
			var s: Soldier = Net._soldiers.get(Net.my_id())
			return is_instance_valid(s) and s.alive and s.team == other
		# Original T7406: nach der Respawn-Zeit „FEUER DRÜCKEN FÜR RESPAWN“ → Feuer = sofort wieder im Spiel
		var ready_fire := func() -> bool: return Net.respawn_ready()
		var got_ready: bool = await wait_for(ready_fire, 120.0)
		var hud = Game.current_mission().get_node_or_null("MpHud") if Game.current_mission() else null
		check(got_ready and hud != null and String(hud.state_text()) == Net.tx(7406, "FEUER DRÜCKEN FÜR RESPAWN"),
			"Client: HUD „%s“ nach Ablauf der Respawn-Zeit" % Net.tx(7406, "FEUER DRÜCKEN FÜR RESPAWN"))
		var t_fire := Time.get_ticks_msec()
		await press_action("fire")
		check(await wait_for(respawned, 120.0), "Client: nach Wiedereinstieg auf der gewählten Seite")
		check(Time.get_ticks_msec() - t_fire < 2900 or not got_ready, "Client: Feuertaste löst den Wiedereinstieg sofort aus",
			"%d ms" % (Time.get_ticks_msec() - t_fire))
	await get_tree().create_timer(2.0).timeout
	await leave_via_pause_menu("Client")
	_finish()


## Klickfläche (OrigScreen.hit) auslösen – kopflos ist das Fenster nur 64×64 px groß
func _hit(root: Node, nm: String) -> void:
	var c: Control = root.find_child(nm, true, false)
	check(c != null, "Client: Feld %s" % nm)
	if c:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		c.gui_input.emit(ev)


var _quitting := false


func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://lan_e2e_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
		f.close()
	get_tree().quit(1 if failed > 0 else 0)
