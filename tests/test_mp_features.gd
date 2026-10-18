extends "res://tests/lan_ui_base.gd"
## Mehrspieler-Funktionen nach Original (Server-Seite, ein Prozess):
## Server-Regeln/Standards je Stil, Servermenü (Felder, Konfigurationsdatei), Aufwärmphase mit HUD, Spawnschutz,
## 3.-Person-/Fahrzeug-/Fallschaden-Regeln, umgekehrter Schaden, Chat (Taste T, Eingabezeile), Konsole/Admin,
## Abstimmungen, Rundenzahl + Kartenrotation (Bots neu), Zuschauer mit Kamera, Spawnzonen-Karte, VIP-Ziel,
## μ-law-Sprachkodierung, Internet-Menü.
##   tools\godot.cmd --headless -- --autoplay=test_mp_features --profiles_dir=user://test_mp_features --noimport

const MAP_A := "mp_arctic2_mp"
const MAP_B := "mp_arctic1_mp"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2700.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait_map(id: String, need_bots := 0) -> Node:
	var ok := func() -> bool:
		var mm := Game.current_mission()
		return mm != null and Game.current_mission_id == id and mm.squad != null and (Net.dedicated or Net._soldiers.has(1)) \
			and _bot_count() >= need_bots
	await wait_for(ok, 400.0)
	return Game.current_mission() if ok.call() else null


func _bot_count() -> int:
	var n := 0
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]) and Net._soldiers[k].alive:
			n += 1
	return n


func _run() -> void:
	var menu := await menu_with_profile("Host")
	# Versionsanzeige im Hauptmenü frei sichtbar (nicht unter der Kordel des Zettelbilds, unten rechts)
	var ver: Label = menu.stage.find_child("Version", true, false)
	check(ver != null and ver.is_visible_in_tree() and ver.text == "v%s" % ProjectSettings.get_setting("application/config/version")
		and ver.position.x >= 500.0 and ver.get_rect().end.y <= 768.0, "Hauptmenü: Versionsanzeige sichtbar platziert",
		ver.text if ver else "-")
	# --- Standardwerte je Stil (re_notes_multiplayer §2.2) ---
	var dm := Net.style_defaults(Net.Mode.DEATHMATCH)
	var oc := Net.style_defaults(Net.Mode.OCCUPATION)
	var ob := Net.style_defaults(Net.Mode.OBJECTIVES)
	check(dm["score_limit"] == 20 and dm["round_count"] == 3 and dm["warmup_s"] == 10 and dm["spawn_protect_s"] == 5
		and not dm["friendly_fire"] and not dm["third_person"] and dm["inverse_damage"] == 100, "Standards Deathmatch (Original)")
	check(oc["time_limit_min"] == 30 and oc["respawn_s"] == 30 and oc["team_balance"] and oc["friendly_fire"], "Standards Besetzung (Original)")
	check(ob["time_limit_min"] == 5 and not ob["allow_respawn"], "Standards HD2-Aufgaben (Original: kein Respawn)")
	check(Net.PORT == 11001, "Original-Standardport 11001")

	# --- Internet-Menü ---
	var inet := visible_button("bmultiplayernet")
	check(inet != null and not inet.disabled, "Hauptmenü: MEHRSPIELER-SPIEL – INTERNET aktiv")
	check(await click(inet), "Internet-Knopf angeklickt")
	await frames(5)
	var lm: LanMenu = menu.lan_menu
	check(lm != null and lm.internet and lm._inet.button_pressed and Net.browsing_favorites, "Internet-Menü offen (Internet-Server vorgewählt, Favoriten)")
	Net.favorites.clear()
	lm._ip.text = "127.0.0.1:%d" % (Net.PORT + 40)
	var fav_b: Button = lm.find_child("AddFavorite", true, false)
	check(fav_b != null and fav_b.is_visible_in_tree(), "Knopf „%s“" % SAS.text(20102, "ZU FAVORITEN HINZUFÜGEN"))
	if not await click(fav_b):
		fav_b.pressed.emit()          # kopflos 64×64 px: Knopf außerhalb des Fensters
	check(Net.favorites.has("127.0.0.1:%d" % (Net.PORT + 40)), "Favorit gespeichert", str(Net.favorites))
	var irb: Button = lm.find_child("RereadButton", true, false)
	var iub: Button = lm.find_child("UpdateButton", true, false)
	check(irb != null and iub != null and irb.text == SAS.text(2325, "LISTE NEU EINLESEN") and iub.text == SAS.text(2327, "LISTE AKTUALISIEREN"),
		"Internet-Menü: Knöpfe LISTE NEU EINLESEN / LISTE AKTUALISIEREN (T2325/2327)")
	if iub != null:
		if not await click(iub):
			iub.pressed.emit()
		check(Net.scan_kind == "update" and iub.text == SAS.text(2328, "HALT"), "LISTE AKTUALISIEREN: Favoriten neu abgefragt, Knopf HALT (T2328)")
		var idone := func() -> bool: return Net.scan_kind == ""
		check(await wait_for(idone, 10.0) and iub.text == SAS.text(2327, "LISTE AKTUALISIEREN"), "Abfrage beendet → Knopf wieder LISTE AKTUALISIEREN")
	check(await click(visible_button("Zurück")), "Zurück")
	await frames(5)

	# --- LAN-Menü: Server-Regeln ---
	await click(visible_button("bmultiplayerlan"))
	await frames(5)
	lm = menu.lan_menu
	var ai := -1
	for i in lm._map.item_count:
		if lm._map.get_item_metadata(i) == "mp_arena_a1_blizzard":
			ai = i
	lm._map.select(ai)
	lm._map.item_selected.emit(ai)
	lm._mode.select(1)
	lm._mode.item_selected.emit(1)
	check(lm._rounds.value == 3 and lm._warm.value == 10 and lm._protect.value == 5 and lm._inverse.value == 100
		and not lm._third.button_pressed and lm._vehicles.button_pressed and lm._falling.button_pressed and lm._port.value == Net.PORT,
		"Servermenü: Rundenzahl, Aufwärmzeit, Spawn-Schutz, umgek. Schaden, 3.-Person, Fahrzeuge, Fallschaden, Port")
	lm._bots.value = 1
	var cfg := lm.server_settings()
	var keys_ok := true
	for k in Net.RULE_KEYS:
		if not cfg.has(k) and k != "flood_protect":       # floodprotect: nur Konsole (nicht im Original-Menü)
			keys_ok = false
	check(keys_ok and (cfg["map_list"] as Array).size() > 1 and cfg["bots_per_team"] == 1, "server_settings: alle Regeln, Kartenliste, KI-Soldaten",
		str((cfg["map_list"] as Array).size()))
	var ct := LanMenu.config_text(cfg)
	check(ct.contains("sessionname") and ct.contains("mapname mp_arena_a1_blizzard") and ct.contains("bots 1") and ct.contains("warmup 10")
		and ct.ends_with("server\n"), "Konfigurationsdatei im ServerLauncher-Stil (inkl. bots)")
	# Serverliste: LISTE NEU EINLESEN (T2325) leert und sucht neu, HALT (T2326) hält an
	var rb: Button = lm.find_child("RereadButton", true, false)
	var ub: Button = lm.find_child("UpdateButton", true, false)
	check(rb != null and ub != null and rb.text == SAS.text(2325, "LISTE NEU EINLESEN") and ub.text == SAS.text(2327, "LISTE AKTUALISIEREN"),
		"LAN-Menü: Knöpfe LISTE NEU EINLESEN / LISTE AKTUALISIEREN (T2325/2327)")
	if rb != null and ub != null:
		Net.servers["10.9.8.7:1"] = {"name": "alt", "ip": "10.9.8.7", "port": 1, "seen": Time.get_ticks_msec()}
		if not await click(rb):
			rb.pressed.emit()
		check(Net.scan_kind == "reread" and rb.text == SAS.text(2326, "HALT") and not Net.servers.has("10.9.8.7:1"),
			"LISTE NEU EINLESEN: Liste geleert, Suche läuft, Knopf HALT (T2326)")
		var sdone := func() -> bool: return Net.scan_kind == ""
		check(await wait_for(sdone, 10.0) and rb.text == SAS.text(2325, "LISTE NEU EINLESEN"), "Suche beendet → Knopf wieder LISTE NEU EINLESEN")
		if not await click(ub):
			ub.pressed.emit()
		check(Net.scan_kind == "update" and ub.text == SAS.text(2328, "HALT"), "LISTE AKTUALISIEREN: Abfrage läuft, Knopf HALT (T2328)")
		if not await click(ub):
			ub.pressed.emit()
		check(Net.scan_kind == "" and Net.scan_paused and ub.text == SAS.text(2327, "LISTE AKTUALISIEREN"), "HALT: Abfrage angehalten")
		Net.update_list()
	check(await click(visible_button("Zurück")), "Zurück ins Hauptmenü")
	await frames(5)

	# --- Server: Team-Deathmatch, Aufwärmen, Regeln, 2 Runden, Kartenliste A → B ---
	Net.local_name = "Host"
	Net.local_class = 2
	# Aufwärmzeit lang (unter Last würde eine kurze schon während der Prüfungen ablaufen); Ende wird unten ausgelöst
	var ok := Net.host({"name": "Features", "map": MAP_A, "mode": Net.Mode.TEAM_DEATHMATCH, "max_players": 8, "time_limit_min": 0,
		"score_limit": 0, "respawn_s": 5, "port": Net.PORT + 30, "friendly_fire": true, "bots_per_team": 1, "warmup_s": 90,
		"round_count": 2, "map_list": [MAP_A, MAP_B], "third_person": false, "allow_vehicles": false, "falling_damage": true,
		"admin_login": "chef", "admin_pass": "pw"})
	check(ok, "Server gestartet", Net.last_error)
	# Ladebildschirm (Original MISSIONS\ARCTIC2_MP\loader.4ds): Mehrspieler-Fassung mit Kartenbild und Balken
	var ld := func() -> bool:
		var ml = get_tree().root.get_node_or_null("MissionLoader")
		return ml != null and ml.is_loading() and is_instance_valid(ml.screen)
	if await wait_for(ld, 10.0):
		var ls: LoadingScreen = get_tree().root.get_node("MissionLoader").screen
		check(ls.frames.has("MP_screen") and ls.frames.has("mapa") and ls.frames.has("loadbar"),
			"Ladebildschirm: Original-MP-Layout (Hintergrund, Kartenbild, Ladebalken)", str(ls.frames.keys().size()))
		var prog := func() -> bool: return not is_instance_valid(ls) or ls.progress > 0.04
		check(await wait_for(prog, 60.0), "Ladebildschirm: Fortschritt steigt")
	var m := await _wait_map(MAP_A, 2)
	check(m != null, "Karte A geladen (eigener Soldat + 2 KI)")
	if m == null:
		_finish()
		return
	await frames(10)
	var hud: MpHud = m.get_node_or_null("MpHud")
	check(hud != null, "MP-HUD an der Mission")
	check(Net.game_state == Net.State.WARMUP, "Aufwärmphase aktiv (Zustand 3)")
	var info_ok := func() -> bool: return int(Net.hud_info.get("st", -1)) == Net.State.WARMUP
	await wait_for(info_ok, 20.0)
	check(hud.top_text().contains(Net.tx(7402, "AUFWÄRMEN")), "HUD: %s mit Restzeit" % Net.tx(7402, "AUFWÄRMEN"), hud.top_text())
	# Original-HUD-Grafiken (gameinterface.4ds): Punktetafel mit Wappen, Teampunkte
	check(hud.gfx.has("mp_scoretable") and (hud.gfx["mp_scoretable"] as Control).visible and (hud.gfx["mpaxis_score"] as Control).visible,
		"MP-HUD: Original-Punktetafel mp_scoretable mit Wappen (Team-Spiel)")
	check(hud._score_label != null and hud._score_label.text.contains(":"), "MP-HUD: Teampunkte in der Punktetafel", hud._score_label.text if hud._score_label else "")
	var me: Soldier = Net._soldiers[1]
	check(m.rig.mode == CameraRig.Mode.FIRST and not Net.third_person_allowed(), "3.-Person nicht erlaubt → 1. Person")
	await press_action("camera_toggle")
	check(m.rig.mode == CameraRig.Mode.FIRST, "Kamerawechsel gesperrt")
	check(not Net.vehicles_allowed(), "Fahrzeuge nicht erlaubt (allowvehicles 0)")
	# Dauer zeitunabhängig prüfen (unter Last kann der Schutz bis hierher schon abgelaufen sein)
	var prot := int(me.get_meta("protect_until", 0)) - int(me.get_meta("spawn_ms", 0))
	check(prot == 5000, "Spawn-Schutz 5 s (Original-Standard)", str(prot))
	me.set_meta("protect_until", Time.get_ticks_msec() + 3000)          # Anzeige bei aktivem Schutz
	await frames(3)
	check(hud.state_text().contains(Net.tx(20313, "Respawn-Schutz")), "HUD: Respawn-Schutz", hud.state_text())
	# Abschuss in der Aufwärmphase zählt nicht
	var mate: Soldier = null
	var foe: Soldier = null
	for k in Net._soldiers:
		if int(k) < 0:
			if Net._soldiers[k].team == me.team:
				mate = Net._soldiers[k]
			else:
				foe = Net._soldiers[k]
	foe.set_meta("protect_until", 0)
	foe.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
	await frames(3)
	check(int(Net.players[1]["kills"]) == 0, "Abschuss während des Aufwärmens ohne Wertung")
	Net._warm_t = 0.5                  # Aufwärmen jetzt beenden (Ereignis statt Wartezeit)
	var ok_w := func() -> bool: return Net.game_state == Net.State.RUNNING
	check(await wait_for(ok_w, 30.0), "Aufwärmen beendet → Runde läuft")
	await frames(10)
	me = Net._soldiers[1]
	check(is_instance_valid(me) and me.alive and int(Net.players[1]["score"]) == 0, "Nach dem Aufwärmen neu aufgestellt, Punkte 0")
	for k in Net._soldiers:
		if int(k) < 0 and Net._soldiers[k].team == me.team:
			mate = Net._soldiers[k]
	# Umgekehrter Schaden (Freund-Feind an, 100 %)
	me.set_meta("protect_until", 0)
	mate.set_meta("protect_until", 0)
	var h0 := mate.health
	me.apply_hit(20.0, &"torso", mate, Vector3.FORWARD)
	check(is_equal_approx(h0 - mate.health, 20.0), "Umgekehrter Schaden: Schütze erleidet 100 % des Teamtreffers", "%.1f" % (h0 - mate.health))
	# Fallschaden
	var h1 := me.health
	Net.fall_damage(me, 15.0)
	check(me.health < h1, "Fallschaden (Regel an)")
	Net.server_command("fallingdmg 0")
	h1 = me.health
	Net.fall_damage(me, 15.0)
	check(is_equal_approx(me.health, h1) and not bool(Net.rule("falling_damage")), "Fallschaden aus per Konsole „fallingdmg 0“")

	# --- MP-Rang (Punkte/10, max. 7) mit Beförderung/Degradierung (T8900–8903) ---
	Net.rank_log.clear()
	Net.players[1]["score"] = 9
	for k in Net._soldiers:
		if int(k) < 0 and Net._soldiers[k].team != me.team and Net._soldiers[k].alive:
			foe = Net._soldiers[k]
	if is_instance_valid(foe):
		foe.set_meta("protect_until", 0)
		foe.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
		await frames(3)
	check(int(Net.players[1].get("rank", 0)) == 1 and Net.rank_log.any(func(r): return r[0] == 1 and r[1] == 1 and r[2]),
		"Rang: 10 Punkte → Rang 1, Meldung „%s“" % Net.tx(8901, "Sie wurden befördert zu"), str(Net.rank_log))
	check(Net.rank_of(75) == 7 and Net.rank_of(200) == 7 and Net.rank_of(-5) == 0, "Rangformel min(⌊Punkte/10⌋, 7)")
	for k in Net._soldiers:
		if int(k) < 0 and Net._soldiers[k].team == me.team and Net._soldiers[k].alive:
			mate = Net._soldiers[k]
	if is_instance_valid(mate):
		mate.set_meta("protect_until", 0)
		me.set_meta("protect_until", Time.get_ticks_msec() + 60000)       # umgekehrter Schaden trifft den Schützen nicht
		mate.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
		await frames(3)
		me.set_meta("protect_until", 0)
	check(int(Net.players[1].get("rank", 0)) == 0 and Net.rank_log.any(func(r): return r[0] == 1 and r[1] == 0 and not r[2]),
		"Teamkill −10 → degradiert (%s)" % Net.tx(8900, "Sie wurden degradiert zu"), str(Net.rank_log))
	check(Net.board_text().contains("Rang"), "Punktetabelle mit Rang-Spalte")

	# --- „FEUER DRÜCKEN FÜR RESPAWN“ (T7406): nach der Respawn-Zeit, Feuertaste = sofort ---
	me = Net._soldiers[1]
	me.set_meta("protect_until", 0)
	me.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
	await frames(3)
	check(hud.state_text().begins_with(Net.tx(7405, "AUF RESPAWN WARTEN")), "HUD: %s mit Countdown" % Net.tx(7405, ""), hud.state_text())
	var rr := func() -> bool: return Net.respawn_ready()
	check(await wait_for(rr, 60.0), "Respawn-Zeit abgelaufen → Feuertaste möglich")
	check(hud.state_text() == Net.tx(7406, "FEUER DRÜCKEN FÜR RESPAWN"), "HUD: %s" % Net.tx(7406, ""), hud.state_text())
	check(Net._respawn.has(1), "Ohne Feuertaste noch kein Wiedereinstieg (automatisch erst nach weiteren 3 s)")
	await press_action("fire")
	await frames(2)
	var me2: Soldier = Net._soldiers.get(1)
	check(not Net._respawn.has(1) and is_instance_valid(me2) and me2.alive and me2 != me, "Feuertaste: sofortiger Wiedereinstieg")
	me = me2

	# --- Kompasspunkte der Teamkameraden (kul_us, hd2.exe 0x4936C0/0x493860) ---
	var oh = m.find_child("OrigHud", true, false)
	mate = null
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]) and Net._soldiers[k].team == me.team and Net._soldiers[k].alive:
			mate = Net._soldiers[k]
	if mate == null:
		var mate_back := func() -> bool:
			for k in Net._soldiers:
				if int(k) < 0 and is_instance_valid(Net._soldiers[k]) and Net._soldiers[k].team == me.team and Net._soldiers[k].alive:
					return true
			return false
		await wait_for(mate_back, 30.0)
		for k in Net._soldiers:
			if int(k) < 0 and is_instance_valid(Net._soldiers[k]) and Net._soldiers[k].team == me.team and Net._soldiers[k].alive:
				mate = Net._soldiers[k]
	await frames(5)
	var nm := Net.compass_mates(me).size()
	check(oh != null and mate != null and nm >= 1 and oh.compass_dots.size() == nm, "Kompass: je lebendem Kamerad ein Punkt",
		"%d Kameraden, %d Punkte" % [nm, oh.compass_dots.size() if oh else -1])
	if oh != null and not oh.compass_dots.is_empty():
		var dot: TextureRect = oh.compass_dots.values()[0]["node"]
		var dial: Rect2 = oh.elements["kmpscvr"]["screen"]
		var tpl: Rect2 = oh.elements["kul_us"]["screen"]
		var rad := tpl.get_center().distance_to(dial.get_center())
		var dd := dot.get_rect().get_center().distance_to(dial.get_center())
		check(dot.visible and absf(dd - rad) < 1.0 and dot.texture == (oh.elements["kul_us"]["node"] as TextureRect).texture,
			"Kompasspunkt (kul_us) auf dem Ring der Vorlage", "%.2f / %.2f" % [dd, rad])
	if mate != null:
		mate.set_meta("protect_until", 0)
		mate.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
		var faded := func() -> bool: return oh == null or oh.compass_dots.size() < nm
		check(await wait_for(faded, 10.0), "Kamerad tot → Punkt blendet aus und verschwindet")

	# --- Teamausgleich während der Runde (autoteambalance, Kriterium 0x7301C0) beim Wiedereinstieg ---
	var side0 := int(Net.players[1]["team"])
	var bal0 = Net.settings.get("team_balance", null)
	Net.server_command("autoteambalance 1")
	Net.players[9001] = Net._new_player("Gast A", side0)
	Net.players[9002] = Net._new_player("Gast B", side0)
	Net.balance_log.clear()
	me = Net._soldiers[1]
	me.set_meta("protect_until", 0)
	me.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
	check(await wait_for(rr, 60.0), "Teamausgleich: Respawn bereit")
	await press_action("fire")
	await frames(3)
	var other: int = Soldier.TEAM_AXIS if side0 == Soldier.TEAM_ALLIED else Soldier.TEAM_ALLIED
	check(int(Net.players[1]["team"]) == other and Net.balance_log.size() == 1 and is_instance_valid(Net._soldiers.get(1))
		and Net._soldiers[1].team == other, "Teamausgleich: Spieler beim Wiedereinstieg ins kleinere Team gesetzt",
		"%d → %d %s" % [side0, int(Net.players[1]["team"]), str(Net.balance_log)])
	check(Net.chat_log.any(func(e): return String(e["text"]).begins_with(Net.tx(2372, "AUTO. TEAMAUSGLEICH")) and String(e["text"]).contains("Host")),
		"Teamausgleich: Meldung an alle (T2372 + Name + Seite)", String(Net.chat_log.back()["text"]))
	Net.players.erase(9001)
	Net.players.erase(9002)
	Net.players[1]["team"] = side0
	if bal0 == null:
		Net.settings.erase("team_balance")
	else:
		Net.settings["team_balance"] = bal0
	me = Net._soldiers[1]

	# --- Server-Grenzen: Flood-Schutz, Ping-/Inaktivitäts-Rauswurf (Logik, Gast-Eintrag ohne echte Verbindung) ---
	Net._chat_times.clear()
	Net._muted_until.clear()
	var n0 := Net.chat_log.size()
	for i in 6:
		Net.send_chat("Flut %d" % i)
	await frames(2)
	var got_flood := Net.chat_log.filter(func(e): return String(e["text"]).begins_with("Flut")).size()
	check(got_flood == Net.FLOOD_MSGS and Net.chat_log.size() > n0, "floodprotect: höchstens %d Zeilen in %d s, Rest unterdrückt" %
		[Net.FLOOD_MSGS, int(Net.FLOOD_WINDOW_S)], str(got_flood))
	Net._muted_until.clear()
	Net._chat_times.clear()
	check(Net.server_command("maxping 300") == "maxping = 300" and Net.server_command("maxinactivity 2") == "maxinactivity = 2"
		and Net.server_command("maxfreq 10").begins_with("maxfreq"), "Konsole: maxping/maxinactivity/maxfreq (Launcher-Felder)")
	check(is_equal_approx(Net._state_hz(), 10.0), "maxfreq begrenzt den Zustandstakt", str(Net._state_hz()))
	# Gast 77 (ohne Verbindung): Ping 999 ms über 10 s → Rauswurf mit Originaltext
	Net.players[77] = Net._new_player("Lahm", Soldier.TEAM_AXIS)
	Net._ready_peers[77] = true
	Net.ping_override[77] = 999
	Net._ping_over[77] = Net.PING_KICK_GRACE_S - 1.0
	Net._limit_t = 0.0
	Net._limits_tick(0.1)
	check(bool(Net.players.get(77, {}).get("kicked", false)) and String(Net.chat_log.back()["text"]).contains("Lahm"),
		"maxping: Rauswurf nach %d s über dem Grenzwert (T8877)" % int(Net.PING_KICK_GRACE_S), String(Net.chat_log.back()["text"]))
	Net.players.erase(77)
	# Gast 78 mit lebendem Soldaten, seit 5 s keine Eingabe → Inaktivität (T8876)
	Net.players[78] = Net._new_player("Schlaf", Soldier.TEAM_AXIS)
	Net._ready_peers[78] = true
	Net._soldiers[78] = me
	Net._active_ms[78] = Time.get_ticks_msec() - 5000
	Net._limit_t = 0.0
	Net._limits_tick(0.1)
	check(bool(Net.players.get(78, {}).get("kicked", false)) and String(Net.chat_log.back()["text"]).contains("Schlaf"),
		"maxinactivity: Rauswurf nach 2 s ohne Eingabe (T8876)", String(Net.chat_log.back()["text"]))
	Net._soldiers.erase(78)
	Net.players.erase(78)
	for k in ["maxping 0", "maxinactivity 0", "maxfreq 0"]:
		Net.server_command(k)

	# --- Chat über die Tastatur (T = alle, Y = Team) ---
	var got := []
	var cb := func(n, t, team): got.append([n, t, team])
	Net.chat_received.connect(cb)
	await _key(KEY_T)
	check(hud._line.visible and not m.controller.input_enabled, "Taste T öffnet die Chat-Zeile (%s), Steuerung ruht" % Net.tx(2853, ""))
	await type_into(hud._line, "Hallo alle")
	await _key(KEY_ENTER)
	await frames(3)
	check(got.size() == 1 and got[0][0] == "Host" and got[0][1] == "Hallo alle" and not got[0][2] and m.controller.input_enabled,
		"Chat an alle gesendet und empfangen", str(got))
	await _key(KEY_Y)
	await type_into(hud._line, "Nur Team")
	await _key(KEY_ENTER)
	await frames(3)
	check(got.size() == 2 and got[1][2], "Team-Chat (%s)" % Net.tx(2854, ""), str(got))
	hud._chat_t = 5.0
	await frames(2)
	check(hud.chat_text().contains("(Team) Host: Nur Team"), "Chatverlauf im HUD")
	Net.chat_received.disconnect(cb)

	# --- Konsole / Admin ---
	check(Net.server_command("listplayers").contains("Host"), "Konsole: listplayers")
	check(Net.server_command("pointlimit 7") == "pointlimit = 7" and int(Net.rule("score_limit")) == 7, "Konsole: pointlimit 7")
	check(Net.server_command("bots 3").contains("3") and int(Net.settings["bots_per_team"]) == 3, "Konsole: bots 3 (ab nächster Runde)")
	check(Net.server_command("roundlimit 5", 99) == "You don't have admin rights!", "Ohne Admin-Rechte abgelehnt")
	await _key(KEY_QUOTELEFT)
	check(hud._line.visible and hud._input_kind == "console", "Taste ^ öffnet die Konsole")
	await type_into(hud._line, "help")
	await _key(KEY_ENTER)
	await frames(3)
	check(String(Net.chat_log.back()["text"]).begins_with("Console keywords:"), "Konsole im Spiel: help")

	# --- Abstimmungen ---
	check(Net.start_vote(0, "kaputt") == "Not valid voting command", "Ungültige Abstimmung abgelehnt")
	Net.start_vote(0, "pointlimit 9")
	var vote_shown := func() -> bool: return not (Net.hud_info.get("vote", {}) as Dictionary).is_empty() and hud._vote.visible
	check(await wait_for(vote_shown, 20.0), "Abstimmung läuft, HUD „voting“")
	await frames(2)
	check(hud._vote_band != null and hud._vote_band.visible, "HUD: Abstimmungsband (Original-Element „voting“)")
	await _key(KEY_F1)
	await frames(3)
	check(int(Net.rule("score_limit")) == 9 and Net._vote.is_empty(), "F1 = zustimmen → %s, Regel geändert" % Net.tx(8931, ""))
	Net.start_vote(0, "restart")
	Net._vote["until"] = 0
	Net._vote_tick()
	check(Net._vote.is_empty() and Game.current_mission_id == MAP_A, "Abstimmung ohne Mehrheit nach Ablauf abgelehnt")

	# --- Rundenende → Runde 2 auf A, dann Kartenwechsel nach B (Bots neu erzeugt, jetzt 3 je Team) ---
	Net._server_end("Test", Soldier.TEAM_ALLIED)
	check(Net.team_wins[Soldier.TEAM_ALLIED] == 1, "Sieg gezählt (Siege Alliierte)")
	var r2 := func() -> bool: return Net.round_no == 2 and not Net.match_over and Game.current_mission() != null and Net._soldiers.has(1)
	check(await wait_for(r2, 400.0), "Nach 5 s Pause: Runde 2 auf derselben Karte")
	check(Game.current_mission_id == MAP_A, "Karte A bleibt (Rundenzahl 2)")
	m = await _wait_map(MAP_A, 6)
	check(m != null and _bot_count() == 6, "Runde 2: KI-Soldaten neu erzeugt (bots 3 → 6)", str(_bot_count()))
	# Zwischenspeicher: dieselbe Karte erneut → keine glTF-Datei neu geparst
	var ml_t: Dictionary = MissionLoader.timing
	check(bool(ml_t.get("cached", false)), "Ladezeit: Runde 2 lädt die Karte aus dem Zwischenspeicher", str(ml_t))
	Net._warm_t = 0.5
	Net._server_end("Test 2", Soldier.TEAM_AXIS)
	m = await _wait_map(MAP_B, 6)
	Net._warm_t = minf(Net._warm_t, 0.5)
	check(m != null and Net.round_no == 1 and Net.team_wins == [0, 0], "Nach 2 Runden: Kartenwechsel A → B, Siege zurückgesetzt",
		"%s r%d %s" % [Game.current_mission_id, Net.round_no, str(Net.team_wins)])
	check(_bot_count() == 6, "Karte B: KI-Soldaten (bots 3) erzeugt, belegen keine Spielerplätze", "%d / humans %d" % [_bot_count(), Net.humans()])
	check(Net.server_command("map " + MAP_A).begins_with("maps:"), "Konsole: map <karte>")
	m = await _wait_map(MAP_A, 6)
	check(m != null, "Konsolen-Kartenwechsel ausgeführt")

	# --- Zuschauer: Respawn nicht erlaubt ---
	Net.server_command("allowrespawn 0")
	Net._warm_t = minf(Net._warm_t, 0.5)
	await wait_for(ok_w, 60.0)          # Aufwärmphase der neuen Runde beenden lassen
	await frames(10)
	me = Net._soldiers[1]
	me.set_meta("protect_until", 0)
	me.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
	await frames(10)
	hud = m.get_node_or_null("MpHud")
	check(bool(Net.players[1]["spectator"]) and hud.spectating, "Ohne Respawn: Zuschauermodus (T20312)")
	check(hud._spec_cam != null and hud._spec_cam.current and hud.spec_target_id != 0, "Zuschauerkamera folgt einem Spieler",
		str(hud.spec_target_id))
	var t1 := hud.spec_target_id
	await press_action("fire")
	check(hud.spec_target_id != t1 or _bot_count() <= 1, "Feuer: nächster Spieler")
	await press_action("stance_stand")
	check(hud.spec_free, "Leertaste: freie Kamera")
	Net.leave(false)
	await frames(10)

	# --- Besetzung: Spawnzonen-Karte und gewählte Zone ---
	Net.host({"name": "Zonen", "map": "mp_burma1_mp_zone", "mode": Net.Mode.OCCUPATION, "port": Net.PORT + 30, "warmup_s": 0,
		"respawn_s": 5, "time_limit_min": 0})
	m = await _wait_map("mp_burma1_mp_zone")
	if m:
		await frames(20)
		hud = m.get_node("MpHud")
		check(hud._has_zones(), "Besetzung: Spawnzonen vorhanden")
		check(OrigAudio.surface != null, "Untergrund-Daten (surface.bin) auch auf der Mehrspielerkarte")
		await press_action("tactical_map")
		check(hud.zone_map_open(), "Taste M: %s" % Net.tx(2525, "KARTE DER SPAWN-ZONEN:"))
		hud._zone_panel.queue_redraw()
		await get_tree().process_frame          # kopflos gibt es kein frame_post_draw
		await get_tree().process_frame
		await frames(2)
		var zm: Control = hud._zone_panel
		check(bool(zm.orig_map), "Spawnzonen-Karte mit Original-Kartenbild (MISSIONS\\BURMA1_MP_ZONE\\map.4ds, MAPA_B1_*)")
		var own: Array = (zm._rects as Dictionary).keys()
		check(own.size() >= 1, "Eigene Zonen anklickbar", str(own))
		if own.size() >= 1:
			var pick: int = own[own.size() - 1]
			# Kopflos ist das Fenster 64×64 px: Mausklick direkt an die Karte (lokale Koordinaten, Punkt in der Zonenfläche)
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = zm.zone_point(pick)
			zm._gui_input(ev)
			check(int(Net.players[1].get("zone", -1)) == pick, "Spawnzone per Klick festgelegt", str(Net.players[1].get("zone")))
			await press_action("tactical_map")
			me = Net._soldiers[1]
			me.set_meta("protect_until", 0)
			me.apply_hit(500.0, &"torso", null, Vector3.FORWARD)
			var sp := func() -> bool: return is_instance_valid(Net._soldiers.get(1)) and Net._soldiers[1].alive and Net._soldiers[1] != me
			check(await wait_for(sp, 120.0), "Wiedereinstieg mit der Welle")
			var zs: Array = m.mp_zones()
			var near := false
			for s in zs[pick]["slots"]:
				if (s["pos"] as Vector3).distance_to(Net._soldiers[1].global_position) < 3.0:
					near = true
			check(near, "Spawn in der gewählten Zone")
	Net.leave(false)
	await frames(10)

	# --- HD2-Aufgaben: VIP (CZECH3_OBJ, Ziel 1 „VIP“, Uniform GE14, Seite Achse) ---
	Net.host({"name": "VIP", "map": "mp_czech3_obj", "mode": Net.Mode.OBJECTIVES, "port": Net.PORT + 30, "warmup_s": 0,
		"bots_per_team": 1, "time_limit_min": 0})
	m = await _wait_map("mp_czech3_obj", 2)
	if m:
		await frames(20)
		var vip_o: Dictionary = {}
		for o in m.mp_objectives():
			if o["type"] == "VIP":
				vip_o = o
		check(not vip_o.is_empty() and vip_o["vip_model"] == "ge14" and vip_o["vip_team"] == Soldier.TEAM_AXIS, "VIP-Ziel aus mpmaplist (Uniform GE14, Achse)")
		var vip_id := 0
		for id in Net.players:
			if Net.vip_of(int(id)) == int(vip_o.get("index", -9)):
				vip_id = int(id)
		var vs: Soldier = Net._soldiers.get(vip_id)
		check(vip_id != 0 and is_instance_valid(vs) and vs.team == Soldier.TEAM_AXIS and vs.has_meta("vip"), "Erster Achsen-Spieler wird VIP", str(vip_id))
		hud = m.get_node("MpHud")
		check(hud.objectives_text().contains("○"), "HUD: Zielliste (mpobjectives)")
		await frames(2)
		check(not hud._obj_icons.is_empty() and hud._obj_icons[0].visible and hud._obj_icons[0].texture != null
			and hud._obj_labels[0].text != "", "HUD: Original-Zielsymbole mpneutral_objNN mit Aufgabentext")
		if is_instance_valid(vs):
			var ts0: float = Net.team_score[vip_o["team"]]
			vs.set_meta("protect_until", 0)
			vs.apply_hit(500.0, &"torso", Net._soldiers.get(1), Vector3.FORWARD)
			await frames(5)
			check(Net.obj_done.has(int(vip_o["index"])) and Net.team_score[vip_o["team"]] - ts0 >= float(vip_o["value"]),
				"VIP getötet → Aufgabe erfüllt (+%d)" % int(vip_o["value"]))
			check(hud.objectives_text().contains("✔"), "HUD: Ziel abgehakt")
			await frames(2)
			var vi := -1
			for i in m.mp_objectives().size():
				if int(m.mp_objectives()[i]["index"]) == int(vip_o["index"]):
					vi = i
			var side := "axis" if int(vip_o["team"]) == Soldier.TEAM_AXIS else "allied"
			check(vi >= 0 and hud._obj_icons[vi].texture == MpHud.crop("mp%s_obj%02d" % [side, vi]),
				"HUD: erfülltes Ziel mit Wappen des begünstigten Teams (mp%s_obj)" % side)
	# --- Server-Filter und Spiel-Info (Original-Bildschirme server filters.4ds / gameinfo.4ds) ---
	var info := Net.server_info()
	info["ip"] = "127.0.0.1"
	info["ping"] = 12
	info["key"] = "127.0.0.1:%d" % (Net.PORT + 30)
	var gi := GameInfoScreen.new()
	add_child(gi)
	gi.open(info)
	await frames(2)
	var itxt := String((gi.find_child("Info", true, false) as Label).text)
	check(itxt.contains("VIP") and itxt.contains(SAS.text(2583, "Zu tötende Gegner:").strip_edges()) and itxt.contains("12 ms"),
		"SPIEL-INFO: Server-Info und Spielregeln (T2571–2592)", itxt.substr(0, 80))
	check(gi.find_child("Player0", true, false) != null and gi.find_child("Team_allied", true, false) != null,
		"SPIEL-INFO: TEAM-STATUS und SPIELER-STATUS")
	gi.queue_free()
	Net.leave(false)
	var srv := [{"name": "A", "mode": 0, "ping": 30, "players": 0, "max": 8, "ded": false, "pw": false, "tag": Net.PROTOCOL,
			"ver": String(ProjectSettings.get_setting("application/config/version"))},
		{"name": "B", "mode": 2, "ping": 400, "players": 3, "max": 3, "ded": true, "pw": true, "tag": "DH2-LAN-1", "ver": "0.1"},
		{"name": "C", "mode": 2, "ping": -1, "players": 2, "max": 8, "ded": true, "pw": false, "tag": Net.PROTOCOL,
			"ver": String(ProjectSettings.get_setting("application/config/version"))}]
	var pass_names := func(flt: Dictionary) -> String:
		return ",".join(PackedStringArray(srv.filter(func(s): return Net.filter_pass(s, flt)).map(func(s): return String(s["name"]))))
	var base := Net.FILTER_DEFAULTS.duplicate()
	check(pass_names.call(base) == "A,B,C", "Filter: ohne Einschränkung alle Server")
	var f2 := base.duplicate()
	f2["style"] = 2
	check(pass_names.call(f2) == "B,C", "Filter: Gesuchte Art BESETZUNG")
	f2 = base.duplicate()
	f2["max_ping"] = 100
	f2["responding"] = true
	check(pass_names.call(f2) == "A", "Filter: MAXIMALER PING + NUR PASSENDE (antwortende)")
	f2 = base.duplicate()
	for k in ["dedicated", "not_empty"]:
		f2[k] = true
	check(pass_names.call(f2) == "B,C", "Filter: NUR DEDIZIERTE + NUR NICHT-LEERE")
	f2 = base.duplicate()
	for k in ["not_full", "no_password", "same_version"]:
		f2[k] = true
	check(pass_names.call(f2) == "A,C", "Filter: NUR NICHT-VOLLE + OHNE PASSWORTE + Selbe Version")
	# Bildschirm bedienen: Art weiterschalten, Kästchen „NUR DEDIZIERTE“ Ja, Ping eintragen, AKZEPTIEREN
	var fs := ServerFilterScreen.new()
	add_child(fs)
	fs.open()
	await frames(2)
	check(fs.has_layout() and fs.find_child("StyleText", true, false) != null, "SERVER-FILTER: Original-Layout server filters.4ds")
	(fs.find_child("StyleRight", true, false) as Button).pressed.emit()
	await frames(1)
	var yes_ded: Control = fs.find_child("Yes_dedicated", true, false)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	yes_ded.gui_input.emit(ev2)
	await frames(1)
	(fs.find_child("MaxPing", true, false) as LineEdit).text = "250"
	var acc_ok := [false]
	fs.closed.connect(func(a): acc_ok[0] = a)
	(fs.find_child("FilterAccept", true, false) as Button).pressed.emit()
	await frames(1)
	check(acc_ok[0] and int(Net.server_filter["style"]) == 0 and bool(Net.server_filter["dedicated"]) and int(Net.server_filter["max_ping"]) == 250,
		"SERVER-FILTER: Art/Kästchen/Ping übernommen (AKZEPTIEREN)", str(Net.server_filter))
	fs.queue_free()
	# LAN-Liste wendet den Filter an
	Net.servers = {"127.0.0.1:1": srv[0].duplicate(), "127.0.0.1:2": srv[1].duplicate()}
	Net.servers["127.0.0.1:1"]["ip"] = "127.0.0.1"
	Net.servers["127.0.0.1:2"]["ip"] = "127.0.0.1"
	Net.server_filter = base.duplicate()
	Net.server_filter["dedicated"] = true
	var lm2 := LanMenu.new()
	add_child(lm2)
	lm2.open()
	Net.stop_browse()
	Net.servers = {"127.0.0.1:1": srv[0].duplicate(), "127.0.0.1:2": srv[1].duplicate()}
	lm2._refresh()
	check(lm2._list.item_count == 1 and lm2._list.get_item_text(0).begins_with("B") and lm2._filter_label.text.contains("1"),
		"LAN-Liste: SERVER-FILTER blendet Server aus (1 ausgeblendet)", str(lm2._list.item_count))
	Net.server_filter = base.duplicate()
	lm2.queue_free()
	Net.servers.clear()

	# --- Sprachkodierung (μ-law, 64/32 kbps ohne externe Codecs) ---
	var pcm := PackedFloat32Array()
	for i in 320:
		pcm.append(0.5 * sin(TAU * 440.0 * i / 8000.0))
	var dec := VoiceChat.decode(VoiceChat.encode(pcm))
	var err := 0.0
	for i in pcm.size():
		err = maxf(err, absf(dec[i] - pcm[i]))
	check(VoiceChat.encode(pcm).size() == 320 and err < 0.02, "μ-law: 40 ms bei 8 kHz = 320 Byte (64 kbps), Fehler < 2 %", "%.4f" % err)
	check(Net.voice_rate(7) == 8000 and Net.voice_rate(6) == 4000 and Net.voice_rate(0) == 0, "Codec-Auswahl 64/32 kbps/aus")
	_finish()


func _key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.pressed = pressed
		ev.keycode = code
		ev.physical_keycode = code
		get_tree().root.push_input(ev, true)
		await get_tree().process_frame
