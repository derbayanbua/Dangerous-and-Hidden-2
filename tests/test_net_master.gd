extends "res://tests/test_net.gd"
## 0.11.1 Anbindung Spiel ↔ Master (Server-Seite, 2 Prozesse, lokaler Master-Mock 127.0.0.1, nie der echte Master).
## Internet-Server eines (Test-)offiziellen Builds: Registrierung, ENet-Auth mit Beitrittsbeleg → Konto des Clients
## zugeordnet (Master.set_peer_account, Rang in Net.players), Rundenende → Bericht mit Spieler + Beleg, Antwort career →
## Beförderung beim Client, UNRANKED → keine Meldung, Abmeldung. Dazu Auth-Einzelprüfungen (Rahmen, Host-Identität,
## Version) und LAN ohne Master (Server ohne Schlüssel, unsignierte Challenge, Beitritt ohne Konto).
##   tools\godot.cmd --headless -- --autoplay=test_net_master

const MOCK := preload("res://tests/master_mock.gd")
const AUTH := preload("res://src/autoload/net_auth.gd")
const DIR := "user://test_net_master"
const RES_FILE := "user://test_net_master/client_result.txt"

var mock: Node
var M: Node


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RES_FILE))
	await frames(5)
	M = get_node("/root/Master")
	M.key_bits = 2048
	check(Net.PROTOCOL == "DH2-LAN-6" and M.build_info()["net_protocol"] == "DH2-LAN-6", "Protokoll DH2-LAN-6 (Master: DH2-LAN-6:1)")
	_unit_auth()
	await _lan_without_master()
	# Test-Build-Schlüssel und Mock; Schlüssel für den Client-Prozess im Testordner (nur Laufzeit-Testschlüssel)
	var ck := Crypto.new()
	var bkey := ck.generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(bkey.save_to_string(true), true)
	M.set_build_key(bkey)
	mock = MOCK.new()
	add_child(mock)
	mock.setup(pub)
	M.test_master_keys = {mock.master_kid: mock.master_key}
	M.master_url = "http://127.0.0.1:%d" % mock.port
	bkey.save(DIR + "/build.key")
	mock.master_key.save(DIR + "/master_pub.key", true)
	var f := FileAccess.open(DIR + "/mock.txt", FileAccess.WRITE)
	f.store_string("%d\n%s" % [mock.port, mock.master_kid])
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/server.key"))
	var sid: String = M.load_server_key(DIR + "/server.key")
	# Server über Net.host (Internet-Modus)
	Net.local_name = "Host"
	var ok := Net.host({"name": "Mastertest", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.DEATHMATCH, "spawn_protect_s": 0,
		"internet": true, "port": Net.PORT, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5})
	check(ok and Net.master_mode(), "Internet-Server eines offiziellen Builds = Master-Modus", Net.last_error)
	check(await _wait(func() -> bool: return mock.servers.has(sid), 30.0), "Registrierung beim Master (Serverschlüssel)", sid.substr(0, 16))
	check(M.registered and M._hb_timer.time_left > 0.0, "Heartbeat geplant")
	var m := await _wait_mission()
	check(m != null, "Karte geladen")
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/net_master_client.log")
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog] + _project_args() + ["--", "--autoplay=test_net_master_client"])
	check(pid > 0, "Client-Prozess gestartet")
	var cid := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000 and cid == 0:
		await get_tree().create_timer(0.25).timeout
		for id in Net.players:
			if int(id) > 1:
				cid = int(id)
	check(cid != 0, "Client beigetreten (ENet-Auth abgeschlossen)")
	if cid == 0:
		_end_test()
		return
	var gh_ok := func() -> bool: return M.peer_account(cid) != "" and int(Net.players.get(cid, {}).get("master_rank", -1)) == 7
	check(await _wait(gh_ok, 60.0), "Beitrittsbeleg geprüft → Konto zugeordnet, Master-Rang (GET stats) in Net.players",
		"%s / %s" % [M.peer_account(cid), str(Net.players.get(cid, {}).get("master_rank"))])
	var gh: String = M.peer_account(cid)
	check(mock.accounts.has(gh), "Zugeordnetes Konto ist das beim Master gebundene Konto des Clients")
	check(String(Net.players[cid].get("gh", "")) == gh and not Net.players[1].has("gh"), "Host ohne Konto, Client mit Konto")
	check(Net.shown_rank(cid)["text"] == tr(Career.rank_name(7)) and Net.board_text().contains(tr(Career.rank_name(7))),
		"Punktetabelle: Master-Dienstgrad", Net.shown_rank(cid)["text"])
	check(Net.board_rows.has(7), "Punktetabelle: Abzeichen-Spalte (Stufe 7)")
	var pl: Array = Net.server_info()["plist"]
	check(pl.any(func(r): return r.size() > 5 and String(r[5]) == tr(Career.rank_name(7))), "SPIEL-INFO: Dienstgrad in der Spielerliste")
	# Abschuss als Statistik (Client stirbt durch den Host)
	await _wait(func() -> bool: return is_instance_valid(Net._soldiers.get(cid)) and Net._soldiers[cid].alive, 60.0)
	await get_tree().create_timer(2.0).timeout
	var cs: Soldier = Net._soldiers.get(cid)
	var hs: Soldier = Net._soldiers.get(1)
	if is_instance_valid(cs) and is_instance_valid(hs):
		cs.apply_hit(1000.0, &"torso", hs, Vector3.FORWARD)
	await _wait(func() -> bool: return int(Net.players[1].get("pvp_kills", 0)) >= 1, 20.0)
	await get_tree().create_timer(6.0).timeout       # Bericht: Mindestdauer ist Sache des Masters; Mock prüft nicht
	# Rundenende → Bericht (ACCEPTED, Beförderung)
	var n0: int = mock.reports.size()
	Net._server_end("Testende", Soldier.TEAM_ALLIED)
	check(await _wait(func() -> bool: return mock.reports.size() > n0, 30.0), "Rundenende → Bericht beim Master")
	if mock.reports.size() > n0:
		var r: Dictionary = mock.reports[-1]
		var ps: Array = r.get("players", [])
		check(ps.size() == 1 and String(ps[0]["gh"]) == gh, "Bericht enthält genau den Spieler mit Konto (Bots/Host ohne Beleg nicht)", str(ps.size()))
		if ps.size() == 1:
			var p0: Dictionary = ps[0]
			for k in ["kills", "deaths", "score", "teamkills", "suicides", "time_s", "won", "proof", "ai_kills", "objectives", "revives", "victims"]:
				check(p0.has(k), "Spielerfeld " + k)
			check(int(p0["deaths"]) >= 1 and typeof(p0["proof"]) == TYPE_DICTIONARY and String(p0["proof"].get("kid", "")) != "",
				"Tode und Beitrittsbeleg (Umschlag joinproof)")
			var prf: Dictionary = p0["proof"]
			var ppl = JSON.parse_string(Marshalls.base64_to_raw(String(prf["payload"])).get_string_from_utf8())
			check(ppl != null and ppl["sid"] == sid and ppl["gh"] == gh, "Beleg: sid des Servers, gh des Kontos")
		var hp: Dictionary = Net.players[1]
		check(int(hp.get("pvp_kills", 0)) >= 1 and (hp.get("victims", {}) as Dictionary).get(gh, 0) >= 1,
			"Host-Zähler: PvP-Abschuss und Opfer je Konto (Host selbst ohne Konto nicht im Bericht)")
		check(r.has("match_id") and r.has("started_at") and r.has("ended_at") and r["result"]["winner"] == Soldier.TEAM_ALLIED
			and r["mode"] == Net.Mode.DEATHMATCH and not r["partial"], "Berichtsfelder match_id/Zeiten/result/mode")
	await _wait(func() -> bool: return M.promotions_sent.size() >= 1, 20.0)
	check(M.promotions_sent.size() == 1 and int(M.promotions_sent[0][0]) == cid and int(M.promotions_sent[0][1]) == 3,
		"career promoted → Beförderung an den Client (Stufe 3)", str(M.promotions_sent))
	Net.send_chat("PHASE_UNRANKED")
	await get_tree().create_timer(3.0).timeout
	# zweite Runde: UNRANKED → keine Meldung
	mock.report_verdict = "UNRANKED"
	Net.match_over = false
	var n1: int = mock.reports.size()
	Net._server_end("Testende 2", Soldier.TEAM_AXIS)
	check(await _wait(func() -> bool: return mock.reports.size() > n1, 30.0), "Zweiter Bericht (UNRANKED)")
	await get_tree().create_timer(3.0).timeout
	check(M.promotions_sent.size() == 1, "UNRANKED → keine Beförderung")
	Net.send_chat("PHASE_END")
	check(await _wait(func() -> bool: return FileAccess.file_exists(RES_FILE), 120.0), "Ergebnis des Clients liegt vor")
	if FileAccess.file_exists(RES_FILE):
		for l in FileAccess.get_file_as_string(RES_FILE).split("\n", false):
			check(l.begins_with("PASS"), "Client: " + l.substr(6))
	# Abmeldung beim Beenden
	Net.leave(false)
	check(await _wait(func() -> bool: return mock.unregistered.has(sid), 20.0), "Abmeldung (DELETE mit signiertem Umschlag)")
	_end_test()


func _end_test() -> void:
	if M:
		M.test_master_keys = {}
		M.set_build_key(null)
		M.master_url = M.DEFAULT_URL
	_finish()


## Einzelprüfungen der Auth-Bausteine (ohne Netz).
func _unit_auth() -> void:
	var fr: PackedByteArray = AUTH.frame_json(AUTH.HELLO, {"a": 1})
	var p: Dictionary = AUTH.parse(fr)
	check(fr.slice(0, 4).get_string_from_ascii() == "DH2A" and fr[4] == 1 and fr[5] == 0x30 and p["type"] == 0x30
		and AUTH.body_json(p["body"])["a"] == 1, "Rahmen DH2A/ver/type/len (BE)")
	var bad := fr.duplicate()
	bad.append(0)
	check(AUTH.parse(bad).is_empty() and AUTH.parse("XXXX".to_ascii_buffer()).is_empty(), "Ungültige Rahmen verworfen")
	check(AUTH.fingerprint_text("0123456789abcdef" + "0".repeat(48)) == "0123-4567-89AB-CDEF", "Fingerabdruck XXXX-XXXX-XXXX-XXXX")
	# Host-Identität (Abschnitt 8) mit einem Testschlüssel
	var a: Node = Net.auth
	var k := Crypto.new().generate_rsa(2048)
	var sid: String = M.fingerprint(k)
	var kh_bak := AUTH.load_known_hosts()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH.known_hosts_path()))
	a._cnonce = "N".repeat(43)
	var env: Dictionary = M.make_envelope("DH2/v1/join", {"n": a._cnonce, "sid": sid, "pubkey_pem": k.save_to_string(true),
		"t_host": 0, "hn": "H".repeat(43)}, k, sid)
	a.expect = {}
	a.host_key = "unit.test:11001"
	var r1: Dictionary = a.check_challenge(env)
	check(String(r1.get("sid", "")) == sid and AUTH.load_known_hosts().has("unit.test:11001"), "Unbekannter Direktserver: TOFU gespeichert")
	check(a.check_challenge(env).get("sid", "") == sid and bool(a.last_host["known"]), "Bekannt und gleich: still")
	var k2 := Crypto.new().generate_rsa(2048)
	var sid2: String = M.fingerprint(k2)
	var env2: Dictionary = M.make_envelope("DH2/v1/join", {"n": a._cnonce, "sid": sid2, "pubkey_pem": k2.save_to_string(true),
		"t_host": 0, "hn": "H".repeat(43)}, k2, sid2)
	check(a.check_challenge(env2).get("error", "") == "HOST_KEY_MISMATCH", "Bekannt und anders: HOST_KEY_MISMATCH")
	a.accept_host_change = true
	check(a.check_challenge(env2).get("sid", "") == sid2, "Ersetzen nur ausdrücklich")
	a.expect = {"server_id": sid}
	check(a.check_challenge(env2).get("error", "") == "HOST_KEY_MISMATCH", "Masterliste: andere server_id → Abbruch ohne Rückfall")
	var forged := env.duplicate()
	forged["payload"] = Marshalls.raw_to_base64(Marshalls.base64_to_raw(env["payload"]).get_string_from_utf8().replace("H".repeat(43), "X".repeat(43)).to_utf8_buffer())
	a.expect = {}
	check(a.check_challenge(forged).get("error", "") == "BAD_SIGNATURE", "Verfälschte Challenge: BAD_SIGNATURE")
	a._cnonce = "other"
	check(a.check_challenge(env).get("error", "") == "BAD_SIGNATURE", "Falsche Client-Nonce abgewiesen")
	a.expect = {}
	a.host_key = ""
	a.accept_host_change = false
	AUTH.save_known_hosts(kh_bak)
	# Beitrittsbeleg prüfen (Kontoschlüssel im Speicher)
	var ak := Crypto.new().generate_rsa(2048)
	var akid: String = M.fingerprint(ak)
	var proof: Dictionary = M.make_envelope("DH2/v1/joinproof", {"gh": "a".repeat(32), "sid": sid, "hn": "H".repeat(43)}, ak, akid)
	var acc := {"gh": "a".repeat(32), "akid": akid, "pub": ak.save_to_string(true)}
	check(M.verify_join_proof(proof, acc, sid, "H".repeat(43)) == "a".repeat(32), "Beleg gültig → guid_hash")
	check(M.verify_join_proof(proof, acc, sid, "Z".repeat(43)) == "", "Beleg mit fremder Host-Nonce abgewiesen")
	check(M.verify_join_proof(proof, acc, sid2, "H".repeat(43)) == "", "Beleg für anderen Server abgewiesen")
	var acc2 := acc.duplicate()
	acc2["gh"] = "b".repeat(32)
	check(M.verify_join_proof(proof, acc2, sid, "H".repeat(43)) == "", "Beleg mit fremdem Konto abgewiesen")


## LAN ohne Master (kein Build-Schlüssel): kein Masterverkehr, Bericht nicht gesendet, Original-Rang.
func _lan_without_master() -> void:
	check(not M.is_official_build(), "LAN-Teil: kein offizieller Build")
	# Zustand eines laufenden Servers ohne Kartenladen (Beitritt/Handshake ohne Master prüft test_net zweiprozessig)
	Net.is_online = true
	Net.settings = {"internet": true, "mode": Net.Mode.DEATHMATCH}
	Net.players = {1: Net._new_player("Host", 0, 3)}
	check(not Net.master_mode(), "Ohne offiziellen Build kein Master-Modus (auch mit Internet-Einstellung)")
	Net.settings["internet"] = false
	Net.players[1]["score"] = 25
	Net._update_ranks()
	check(Net.shown_rank(1)["text"] == SAS.rank_name(2, true) and not Net.shown_rank(1)["master"], "LAN: Original-Rang min(⌊Punkte/10⌋,7)")
	Net.last_report = {}
	Net._master_report(-1)
	Net._master_start()
	check(Net.last_report.is_empty() and not M.registered, "LAN: kein Rundenbericht, keine Registrierung")
	Net.is_online = false
	Net.players = {}
	Net.settings = {}
	await frames(5)
