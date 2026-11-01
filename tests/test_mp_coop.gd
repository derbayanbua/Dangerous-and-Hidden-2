extends "res://tests/test_net.gd"
## B-029 Coop-Stil (Original-Stil 3, re_notes_multiplayer §7), Server-Seite: LAN-Menü (Stil nur auf Kampagnenkarten,
## Standardwerte), Server mit Arctic-1A als Coop-Karte (Missions-KI + Originalskripte nur auf dem Server), zweiter
## kopfloser Prozess (tests/test_mp_coop_client.gd) tritt bei. Prüft Beitritt (Spielerseite), KI-Abgleich (Lage, Tod),
## Schwierigkeit (coopdifficulty → OrigMission._apply_difficulty), Leben je Spieler (cooplives, teamlives = 0),
## T20310 beim Tod ohne Leben, Teamleben (gemeinsamer Zähler) und Rundenende ohne Leben (Sieger KI).
##   tools\godot.cmd --headless -- --autoplay=test_mp_coop

const RESULT_C := "user://mp_coop_client_result.txt"
const MAP := "mp_arena_a1_blizzard"


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_C))
	await frames(5)
	check(Net.difficulty_level() == Game.difficulty(), "Einzelspieler: Schwierigkeit = Profil")
	Net.local_name = "Host"
	var menu := get_tree().current_scene
	menu.open_lan()
	await frames(3)
	var lm: LanMenu = menu.lan_menu
	# --- Menü: KOOPERATIV nur auf Kampagnenkarten (Arena), Original-MP-Karten haben ihren festen Stil
	var idx := -1
	var orig_idx := -1
	for i in lm._map.item_count:
		var id := String(lm._map.get_item_metadata(i))
		if id == MAP:
			idx = i
		if id == "mp_africa1_mp":
			orig_idx = i
	check(idx >= 0, "Arena-Karte Arctic 1A in der Liste")
	check(lm._mode.item_count == Net.MODE_NAMES.size() and lm._mode.get_item_text(Net.Mode.COOP) == "KOOPERATIV", "Stil KOOPERATIV im Menü")
	if orig_idx >= 0:
		lm._map.select(orig_idx)
		lm._sync_mode()
		check(lm._mode.is_item_disabled(Net.Mode.COOP), "Original-MP-Karte: KOOPERATIV gesperrt")
	lm._map.select(idx)
	lm._sync_mode()
	check(not lm._mode.is_item_disabled(Net.Mode.COOP), "Kampagnenkarte: KOOPERATIV wählbar")
	lm._mode.select(Net.Mode.COOP)
	lm._apply_style_defaults()
	check(int(lm._maxp.value) == 6 and int(lm._coop_lives.value) == 30 and lm._team_lives.button_pressed \
		and lm._coop_diff.get_selected_id() == 3 and lm._crosshair.button_pressed,
		"Coop-Standardwerte (6 Spieler, 30 Leben, Team-Leben, SCHWER, Fadenkreuz)",
		"%d/%d/%s/%d" % [int(lm._maxp.value), int(lm._coop_lives.value), lm._team_lives.button_pressed, lm._coop_diff.get_selected_id()])
	check(lm._style_maps().has(MAP) and not lm._style_maps().has("mp_africa1_mp"), "Kartenliste Coop = Kampagnenkarten")
	# Leben je Spieler: 3, Schwierigkeit LEICHT
	lm._coop_lives.value = 3
	lm._team_lives.button_pressed = false
	lm._coop_diff.select(0)
	lm._time.value = 0
	lm._respawn.value = 5
	lm._warm.value = 0
	lm._name_edit.text = "Coop"
	Net.local_name = "Host"          # das LAN-Menü setzt den Profilnamen; der Client erkennt Aufträge am Absender „Host“
	var cfg := lm.server_settings()
	check(int(cfg["mode"]) == Net.Mode.COOP and int(cfg["coop_lives"]) == 3 and int(cfg["coop_difficulty"]) == 1 \
		and not bool(cfg["team_lives"]), "Menü übergibt Coop-Regeln", str([cfg["mode"], cfg["coop_lives"], cfg["coop_difficulty"]]))
	check(LanMenu.config_text(cfg).contains("style cooperative") and LanMenu.config_text(cfg).contains("cooplives 3"),
		"Konfigurationsdatei (dedizierter Server) mit Coop-Schlüsseln")
	lm._host()
	check(Net.is_online and multiplayer.is_server() and Net.mode() == Net.Mode.COOP, "Coop-Server gestartet", Net.last_error)
	var m := await _wait_mission()
	check(m != null and bool(m.get("coop")), "Kampagnenkarte als Coop geladen")
	if m == null:
		_finish()
		return
	await frames(30)
	# --- Missions-KI und Skripte nur auf dem Server
	var ai: Array = Net.coop.ai
	check(ai.size() >= 5, "Missions-KI vorhanden", str(ai.size()))
	check(m.runtime.vms.size() > 0, "Originalskripte laufen auf dem Server", str(m.runtime.vms.size()))
	check(not m.orig_objectives.is_empty(), "Ziele der Originalmission geladen", str(m.orig_objectives.size()))
	check(Net.difficulty_level() == 1, "Coop: Schwierigkeit = coopdifficulty (1)")
	var scaled := false
	var enemy: Soldier = null
	for a in ai:
		if a is Soldier and (a as Soldier).team == Soldier.TEAM_AXIS and a.has_meta("orig_params_base"):
			var b: Dictionary = a.get_meta("orig_params_base")
			var p: Dictionary = a.get_meta("orig_params")
			if b.has("health") and float(b["health"]) > 0.0:
				scaled = is_equal_approx(float(p["health"]), float(b["health"]) * 0.7)
				enemy = a
				break
	check(scaled, "Gegnerwerte nach Stufe LEICHT (Gesundheit ×0,7, 0x5A8990)")
	# KI festhalten (Regeltest, keine zufälligen Gefechte); Lage/Tod laufen weiter über den Abgleich
	for a in ai:
		for c in (a as Node).get_children():
			if c is EnemyBrain or c.name == "Perception":
				c.process_mode = Node.PROCESS_MODE_DISABLED
	var me: Soldier = Net._soldiers.get(1)
	check(me != null and me.team == Soldier.TEAM_ALLIED, "Host auf der Spielerseite")
	check(int(Net.players[1].get("lives_used", 0)) == 1, "Erster Spawn zählt ein Leben (0x69D780)", str(Net.players[1].get("lives_used")))
	check(m.runtime.find_frame("commando1") == me, "Skripte sehen den Host als commando1")
	# Regeln Konsole / Serverinfo / SPIEL-INFO
	check(Net.server_command("cooplives") == "cooplives = 3", "Konsole: cooplives", Net.server_command("cooplives"))
	check(Net.server_command("coopdifficulty") == "coopdifficulty = 1", "Konsole: coopdifficulty")
	check(Net.server_command("allowcrosshair 0") == "allowcrosshair = false", "Konsole: allowcrosshair setzen")
	var info := Net.server_info()
	check(int(info["mode"]) == Net.Mode.COOP and int(info["rules"]["coop_lives"]) == 3 and not bool(info["rules"]["allow_crosshair"]),
		"Serverinfo mit Coop-Regeln (Fadenkreuz nur Anzeige)")
	var gi := GameInfoScreen.new()
	gi.info = info
	var gl := "\n".join(gi.info_lines())
	gi.free()
	check(gl.contains(SAS.text(20211, "TEAM-LEBEN").strip_edges()) and gl.contains(SAS.text(20220, "LEICHT").strip_edges()) \
		and gl.contains(Net.MODE_NAMES[Net.Mode.COOP]), "SPIEL-INFO zeigt Coop-Regeln", gl.substr(gl.length() - 200))
	# --- Client
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/mp_coop_client.log")
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog] + _project_args() + ["--", "--autoplay=test_mp_coop_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			if id > 1 and is_instance_valid(Net._soldiers[id]):
				cid = id
		if cid != 0:
			break
	check(cid != 0, "Client beigetreten")
	if cid == 0:
		_finish()
		return
	check(int(Net.players[cid]["team"]) == Soldier.TEAM_ALLIED, "Client auf der Spielerseite")
	check(not Net._server_set_team(cid, Soldier.TEAM_AXIS) and int(Net.players[cid]["team"]) == Soldier.TEAM_ALLIED,
		"Seitenwechsel zur Achse abgelehnt")
	check(m.runtime.find_frame("commando2") == Net._soldiers[cid], "Skripte sehen den Client als commando2")
	check(await _wait(func(): return _chat("CLIENT_READY"), 300.0), "Client meldet KI-Netzfiguren")
	# --- KI-Abgleich: Lage und Tod
	var mover: Soldier = null
	var victim: Soldier = null
	for a in ai:
		if a is Soldier and a.alive and a != enemy:
			if victim == null and (a as Soldier).team == Soldier.TEAM_AXIS:
				victim = a
			elif mover == null:
				mover = a
	mover.global_position += Vector3(2.0, 0.0, 1.5)
	await frames(20)
	var target := mover.global_position
	var host_kills := int(Net.players[1]["kills"])
	victim.apply_hit(5000.0, &"torso", me, Vector3.FORWARD)
	await frames(3)
	check(not victim.alive and Net.coop.dead.has(int(victim.get_meta("coop_ai"))), "KI auf dem Server getötet")
	check(int(Net.players[1]["kills"]) == host_kills + 1 and Net.coop.ai_kills == 1, "Abschuss der KI zählt für den Spieler")
	Net.send_chat("AI_CHECK %d %d %.2f %.2f %.2f" % [int(mover.get_meta("coop_ai")), int(victim.get_meta("coop_ai")), target.x, target.y, target.z])
	check(await _wait(func(): return _chat("AI_OK") or _chat("AI_FAIL"), 60.0) and _chat("AI_OK"), "Client sieht KI-Lage und KI-Tod")
	# --- Leben je Spieler (teamlives = 0, cooplives = 3)
	var cs: Soldier = Net._soldiers[cid]
	for k in 2:
		var gen := int(Net._gen.get(cid, 0))
		cs.set_meta("protect_until", 0)
		var sc := int(Net.players[cid]["score"])
		cs.apply_hit(5000.0, &"torso", enemy, Vector3.FORWARD)
		await frames(3)
		check(not cs.alive and int(Net.players[cid]["score"]) == sc, "Tod %d durch die KI (keine Selbsttötungs-Strafe)" % (k + 1))
		check(Net._respawn.has(cid), "Tod %d: Wiedereinstieg erlaubt (%d < 3 Leben)" % [k + 1, k + 1])
		check(await _wait(func(): return int(Net._gen.get(cid, 0)) > gen and is_instance_valid(Net._soldiers.get(cid)) \
			and Net._soldiers[cid].alive, 30.0), "Tod %d: Client wieder eingestiegen" % (k + 1))
		cs = Net._soldiers[cid]
		check(int(Net.players[cid]["lives_used"]) == k + 2, "Lebenszähler des Clients %d" % (k + 2), str(Net.players[cid]["lives_used"]))
	cs.set_meta("protect_until", 0)
	cs.apply_hit(5000.0, &"torso", enemy, Vector3.FORWARD)
	await frames(3)
	check(not Net._respawn.has(cid) and bool(Net.players[cid]["spectator"]), "Keine Leben mehr: kein Wiedereinstieg, Zuschauer")
	check(Net.coop_lives_left(cid) == 0 and Net.coop_lives_left(1) == 2, "Leben je Spieler getrennt (Host noch 2)")
	check(not Net.match_over, "Runde läuft weiter, solange der Host lebt")
	check(await _wait(func(): return _chat("NOLIVES_OK") or _chat("NOLIVES_FAIL"), 60.0) and _chat("NOLIVES_OK"),
		"Client zeigt T20310 (Keine verbleibenden Leben) 5 s")
	# --- Teamleben: gemeinsamer Zähler (bisher 1 + 3 = 4 Spawns), cooplives 5 → noch ein Wiedereinstieg
	check(Net.server_command("teamlives 1") == "teamlives = true" and Net.server_command("cooplives 5") == "cooplives = 5",
		"Konsole: teamlives/cooplives")
	check(Net.coop_team_spawns == 4 and Net.coop_lives_left(1) == 1, "Teamzähler 4 Spawns, 1 Leben übrig", str(Net.coop_team_spawns))
	var hgen := int(Net._gen.get(1, 0))
	me.set_meta("protect_until", 0)
	me.apply_hit(5000.0, &"torso", enemy, Vector3.FORWARD)
	await frames(3)
	check(Net._respawn.has(1), "Host: Wiedereinstieg über das Teamleben")
	check(await _wait(func(): return int(Net._gen.get(1, 0)) > hgen and Net._soldiers.get(1) and Net._soldiers[1].alive, 30.0),
		"Host wieder eingestiegen")
	check(Net.coop_team_spawns == 5 and not Net._can_respawn(1) and not Net._can_respawn(cid), "Teamleben aufgebraucht (5/5)")
	me = Net._soldiers[1]
	me.set_meta("protect_until", 0)
	me.apply_hit(5000.0, &"torso", enemy, Vector3.FORWARD)
	await frames(3)
	check(Net.last_nolives_ms > 0, "Host sieht T20310")
	# --- Ende ohne Leben: alle Spieler tot, keiner kann wieder einsteigen → Runde verloren (Sieger KI/Achse)
	check(await _wait(func(): return Net.match_over, 15.0), "Rundenende ohne Leben")
	check(Net.game_state == Net.State.WON and int(Net.team_wins[Soldier.TEAM_AXIS]) == 1, "Sieger: Missions-KI (Achse)",
		"Zustand %d, Siege %s" % [Net.game_state, str(Net.team_wins)])
	# Ergebnisse des Clients
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not FileAccess.file_exists(RESULT_C):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT_C) if FileAccess.file_exists(RESULT_C) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)
	_finish()


func _chat(text: String) -> bool:
	return Net.chat_log.any(func(e): return String(e["name"]) == "Gast" and String(e["text"]) == text)
