extends "res://tests/test_gameplay.gd"
## Masterserver-Anbindung 0.11.1 gegen lokalen Mock (127.0.0.1, Laufzeit-Testschlüssel, nie der echte Server).
##   tools\godot.cmd --headless -- --autoplay=test_master_client --profiles_dir=user://test_master_client --noimport

const MC := preload("res://src/autoload/master_client.gd")
const MOCK := preload("res://tests/master_mock.gd")

var M: Node
var mock: Node
var _sig := {}


func _on(name: String, a = null, b = null) -> void:
	_sig[name] = [a, b]


func _run() -> void:
	M = get_node("/root/Master")
	var saved_url: String = M.master_url
	M.key_bits = 2048
	check(not M.is_official_build(), "Editor ohne Build-Schlüssel = kein offizieller Build")
	M.status_changed.connect(func(s, t): _on("status", s, t))
	M.error.connect(func(c, t): _on("error", c, t))
	M.servers_updated.connect(func(l): _on("servers", l))
	M.login_done.connect(func(ok, info): _on("login", ok, info))
	M.match_reported.connect(func(r): _on("report", r))
	await M.connect_master()
	check(M.state == "no_build" and _sig.get("error", [""])[0] == "NO_BUILD", "Ohne Schlüssel: Meldung NO_BUILD, kein Master")
	var r0: Dictionary = await M.request("GET", "/v1/servers", "proto=x&compat=1")
	check(r0["code"] == "NO_BUILD" and r0["status"] == 0, "Ohne Schlüssel keine Anfrage")

	# Testschlüssel zur Laufzeit
	var ck := Crypto.new()
	var bkey := ck.generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(bkey.save_to_string(true), true)
	M.set_build_key(bkey)
	check(M.is_official_build(), "Mit Schlüssel offizieller Build")
	check(RegEx.create_from_string("^b1-[0-9a-f]{16}$").search(M.build_kid()) != null, "kid-Format b1-<16 hex>", M.build_kid())
	mock = MOCK.new()
	add_child(mock)
	mock.setup(pub)
	M.test_master_keys = {mock.master_kid: mock.master_key}
	M.master_url = "http://127.0.0.1:%d" % mock.port

	_signature_format(pub)
	_sanitize()
	await _list_tests()
	await _errors()
	await _login_tests()
	await _server_tests()
	await _offline()
	_test_user_files()

	M.master_url = saved_url
	M.test_master_keys = {}
	M.set_build_key(null)
	_finish()


## 0.11.5: Testprofil isoliert – Net-/Master-Nutzerdateien liegen bei --autoplay im Testordner, nie unter user://.
func _test_user_files() -> void:
	var AUTH = load("res://src/autoload/net_auth.gd")
	var LAN = load("res://src/ui/lan_menu.gd")
	var paths := {"known_hosts": AUTH.known_hosts_path(), "favoriten": Net.fav_path(), "kartenlisten": LAN.maplist_path(),
		"server.key": Net._server_key_path(), "filter": Game.user_file("mp_filter.json"), "dedicated": Game.user_file("dedicated"),
		"master_account": Game.user_file("master_account")}
	var bad: Array = []
	for k in paths:
		var p := String(paths[k])
		if not Game.is_test_profiles_dir(p.get_base_dir()) and not p.begins_with(Game.TEST_USER_DIR + "/"):
			bad.append("%s=%s" % [k, p])
	check(bad.is_empty(), "Testprofil: Nutzerdateien im Testordner (%s)" % String(paths["known_hosts"]).get_base_dir(), str(bad))
	check(String(paths["known_hosts"]).begins_with("user://test_master_client/_userdata/"),
		"known_hosts im --profiles_dir-Testordner", String(paths["known_hosts"]))
	# Schreiben/Lesen über die echten Funktionen landet im Testordner; die Datei unter user:// bleibt unberührt
	var real := "user://known_hosts.json"
	var real_before := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<fehlt>"
	AUTH.save_known_hosts({"test.invalid:1": {"sid": "x"}})
	var real_after := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<fehlt>"
	check(AUTH.load_known_hosts().has("test.invalid:1") and FileAccess.file_exists(String(paths["known_hosts"]))
		and real_before == real_after, "known_hosts: Test schreibt nur in den Testordner")
	var fav_bak: Array = Net.favorites.duplicate()
	Net.favorites = ["test.invalid:2"]
	Net.save_favorites()
	Net.favorites = []
	Net.load_favorites()
	check(Net.favorites == ["test.invalid:2"] and FileAccess.file_exists(Net.fav_path()), "Favoriten: im Testordner gespeichert/geladen")
	Net.favorites = fav_bak
	check(Game.profile_dir().begins_with("user://test") and not Game.profile_dir().begins_with("user://profiles"),
		"Profilordner im Testbereich", Game.profile_dir())


func _signature_format(pub: CryptoKey) -> void:
	var body := "{\"a\":1}".to_utf8_buffer()
	var h: String = M.auth_header("POST", "/v1/accounts/login", "", body, 1794200000, "A".repeat(43))
	var p := h.split(".")
	check(p.size() == 4 and p[1] == "1794200000" and p[2] == "A".repeat(43), "Header kid.ts.nonce.sig")
	# unabhängige Nachrechnung: "DH2/v1/client" 0x00 METHODE\nPFAD\nQUERY\nTS\nNONCE\nhex(sha256(body))
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(body)
	var payload := "POST\n/v1/accounts/login\n\n1794200000\n%s\n%s" % ["A".repeat(43), hc.finish().hex_encode()]
	var data := "DH2/v1/client".to_ascii_buffer()
	data.append(0)
	data.append_array(payload.to_utf8_buffer())
	var hc2 := HashingContext.new()
	hc2.start(HashingContext.HASH_SHA256)
	hc2.update(data)
	var sig := Marshalls.base64_to_raw(p[3])
	check(sig.size() == 256 and Crypto.new().verify(HashingContext.HASH_SHA256, hc2.finish(), sig, pub), "Signatur verifiziert (Testvektor)")
	var bad := payload.replace("POST", "GET ")
	var d2 := "DH2/v1/client".to_ascii_buffer()
	d2.append(0)
	d2.append_array(bad.to_utf8_buffer())
	check(not MC.verify_ctx("DH2/v1/client", bad.to_utf8_buffer(), sig, pub), "Geänderte Methode → Signatur ungültig")
	check(MC.der_of(pub.save_to_string(true)).size() > 200 and MC.fingerprint(pub).length() == 64, "Fingerabdruck SHA-256(DER) 64 hex")
	var n: String = M.nonce(32)
	check(n.length() == 43 and not n.contains("=") and not n.contains("+"), "Nonce 32 Byte b64url ohne Padding")
	check(M.nonce(16).length() == 22, "Umschlag-Nonce 16 Byte = 22 Zeichen")


func _sanitize() -> void:
	var s := "A%sB%sC%sD%sE%sF%sG\nH" % [String.chr(0x200B), String.chr(0x202E), String.chr(0), String.chr(7), String.chr(0xFEFF), String.chr(0xE000)]
	check(MC.clean_text(s) == "ABCDEFG\nH", "Steuer-/Bidi-/Nullbreitenzeichen entfernt", MC.clean_text(s).c_escape())
	var d = MC.sanitize({"n" + String.chr(0x200D): ["x" + String.chr(0x2066) + "y", 3]})
	check(d.has("n") and d["n"][0] == "xy" and d["n"][1] == 3, "Rekursive Bereinigung")
	var env: Dictionary = M.make_envelope("DH2/v1/register", {"name": "Srv" + String.chr(0x202E)}, M._crypto.generate_rsa(2048), "k")
	var pl = JSON.parse_string(Marshalls.base64_to_raw(env["payload"]).get_string_from_utf8())
	check(pl["name"] == "Srv" and pl["v"] == 1 and pl["nonce"].length() == 22 and pl.has("ts"), "Umschlag mit v/ts/nonce, bereinigt")


func _list_tests() -> void:
	var ok: bool = await M.refresh_servers({"mode": 2, "nopw": true})
	check(ok and M.state == "online", "Liste geholt, Status online")
	var q := String(mock.log[-1]["query"])
	check(q.begins_with("proto=DH2-LAN-") and q.contains("&compat=1") and q.contains("mode=2") and q.contains("nopw=1"), "Query proto/compat/Filter", q)
	check(mock.log[-1]["auth"] == "", "Mock akzeptiert Signatur")
	var l: Array = M.list
	check(l.size() == 2, "Abgelaufener Eintrag ausgeblendet", str(l.size()))
	if l.size() == 2:
		var a: Dictionary = l[0]
		for k in ["id", "name", "host", "port", "map", "mode", "players", "max_players", "ping", "version", "password", "dedicated", "ranked", "verify"]:
			if not a.has(k):
				check(false, "Feld " + k)
		check(a["name"] == "TestServer" and a["max_players"] == 16 and a["password"] and a["dedicated"], "Eintrag geparst/bereinigt", a["name"])
		check(a["ranked"] and a["verify"] == "ok", "ranked/verify ok")
		check(not l[1]["ranked"] and l[1]["verify"] == "untrusted", "nicht ranked (untrusted)")
	check(_sig.has("servers") and (_sig["servers"][0] as Array).size() == 2, "Signal servers_updated")
	for mode in ["badsig", "expired", "proto"]:
		mock.list_mode = mode
		_sig.erase("error")
		var r: bool = await M.refresh_servers()
		check(not r and _sig.get("error", [""])[0] == "LIST_INVALID" and M.list.size() == 2, "Liste verworfen: " + mode)
	mock.list_mode = "ok"
	var k0 = M.test_master_keys
	M.test_master_keys = {}
	check(not await M.refresh_servers(), "Unbekannte Master-kid → verworfen")
	M.test_master_keys = k0


func _errors() -> void:
	mock.fail_next = {"/v1/servers": [426, "CLIENT_OUTDATED"]}
	_sig.erase("error")
	check(not await M.refresh_servers(), "426 abgelehnt")
	check(_sig.get("error", [""])[0] == "CLIENT_OUTDATED" and _sig["error"][1] == "Bitte Spiel aktualisieren.", "Fehlercode + Spieltext")
	mock.fail_next = {"/v1/servers": [429, "RATE_LIMITED", 1]}
	var n0: int = mock.log.size()
	var t0 := Time.get_ticks_msec()
	check(await M.refresh_servers(), "429 → Wiederholung mit Backoff erfolgreich")
	check(mock.log.size() - n0 == 2 and Time.get_ticks_msec() - t0 >= 900, "genau eine Wiederholung nach retry_after")
	mock.fail_next = {"/v1/servers": [403, "IP_BANNED"]}
	n0 = mock.log.size()
	check(not await M.refresh_servers() and mock.log.size() - n0 == 1, "403 ohne Wiederholung")
	# unsignierte/falsch signierte Anfrage: Mock schließt kommentarlos → NET_OFFLINE
	var good: CryptoKey = M._build_key
	M.set_build_key(Crypto.new().generate_rsa(2048))
	var r: Dictionary = await M.request("GET", "/v1/servers", M.list_query(), null, 0)
	check(r["code"] == "NET_OFFLINE" and mock.log[-1]["auth"] == "auth_unknown_build", "Fremder Schlüssel → Verbindung geschlossen")
	M.set_build_key(good)
	M.time_offset = -300
	r = await M.request("GET", "/v1/servers", M.list_query(), null, 0)
	check(not r["ok"] and mock.log[-1]["auth"] == "auth_stale", "Zeitabweichung erkannt (Mock)")
	M.time_offset = 0


func _login_tests() -> void:
	var dir := "user://test_master_client/acc"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("account.json")))
	var ok: bool = await M.login({"name": "Tester" + String.chr(0x200B), "dir": dir, "rank": 9})
	check(ok, "Login nach automatischer Bindung")
	check(mock.accounts.size() == 1, "GUID-Box vom Mock geöffnet und geprüft")
	var g: String = mock.accounts.values()[0]["guid"]
	check(RegEx.create_from_string("^[0-9a-f]{32}-[0-9a-f]{32}$").search(g) != null and g.substr(0, 32) == MC.pc_prefix(), "GUID-Format und PC-Präfix")
	check(M.account.get("rank") == 5 and M.rank_of(M.account["guid_hash"]) == 5, "Rang vom Master übernommen (lokal 9 ignoriert)")
	check(M.account.get("rank_overridden") == true, "Abweichung vom Master gemeldet")
	check(M.account.get("name") == "Tester", "Name bereinigt")
	var acc = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("account.json")))
	check(acc != null and acc.get("guid") == g and int(acc.get("bound_at", 0)) > 0, "account.json gespeichert")
	var n0: int = mock.log.size()
	check(await M.login({"dir": dir}), "Zweites Login ohne Bindung")
	check(mock.log.size() - n0 == 1 and String(mock.log[-1]["path"]).ends_with("/login"), "nur eine Anfrage")
	mock.fail_next = {"/v1/accounts/login": [403, "GUID_BANNED"]}
	check(not await M.login({"dir": dir}) and _sig["login"][0] == false and _sig["login"][1]["code"] == "GUID_BANNED", "Gesperrtes Konto → login_done(false)")
	var st: Dictionary = await M.fetch_rank(M.account["guid_hash"])
	check(st.get("rank") == 7 and M.rank_of(M.account["guid_hash"]) == 7, "Rang per GET …/stats")
	check((await M.fetch_rank("../x")).is_empty(), "Ungültiger guid_hash abgewiesen")


func _server_tests() -> void:
	var path := "user://test_master_client/server.key"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var sid: String = M.load_server_key(path)
	check(sid.length() == 64 and FileAccess.file_exists(path), "Serverschlüssel erzeugt, server_id 64 hex")
	check(M.load_server_key(path) == sid, "Serverschlüssel wieder geladen (gleiche ID)")
	check(await M.register_server({"name": "Mein" + String.chr(0x202E) + "Server", "port": 11001}), "Registrierung")
	check(M.registered and mock.servers.has(sid) and mock.servers[sid]["name"] == "MeinServer", "Mock: Umschlag mit Hostschlüssel geprüft")
	check(M._hb_timer.time_left > 20.0, "Heartbeat geplant", str(M._hb_timer.time_left))
	M._hb_timer.stop()
	# Spieler zuordnen → Rang an Net.players
	var net = get_node("/root/Net")
	net.players[77] = {"name": "X"}
	await M.set_peer_account(77, "f".repeat(32))
	check(net.players[77].get("master_rank") == 7, "Master-Rang in Net.players")
	var rep := {"map": "m", "mode": 2, "round": 1, "started_at": 1, "ended_at": 100, "partial": false,
		"result": {"winner": 0, "team_score": [1, 0]},
		"players": [{"gh": "f".repeat(32), "name": "X", "team": 0, "kills": 3, "ai_kills": 2, "objectives": 1,
			"revives": 0, "victims": {"e".repeat(32): 3}, "deaths": 1, "assists": 0, "score": 3, "teamkills": 0,
			"suicides": 0, "time_s": 99, "won": true, "proof": {}}]}
	var j: Dictionary = await M.report_match(rep)
	check(j.get("verdict") == "ACCEPTED" and _sig.has("report"), "Bericht angenommen, Signal match_reported")
	check(M.career_of("f".repeat(32)).get("level") == 7 or M.rank_of("f".repeat(32)) == 7, "Rang nach Bericht neu geholt")
	mock.report_verdict = "UNRANKED"
	j = await M.report_match(rep)
	check(j.get("verdict") == "UNRANKED" and j.get("ranked") == false, "UNRANKED-Antwort")
	net.players.erase(77)
	await M.unregister_server()
	check(not M.registered, "Abgemeldet")


func _offline() -> void:
	M.master_url = "http://127.0.0.1:1"
	_sig.erase("status")
	var t0 := Time.get_ticks_msec()
	await M.connect_master()
	check(M.state == "offline" and _sig.get("error", [""])[0] == "NET_OFFLINE", "Offline erkannt", M.state)
	# 3 Versuche je Zeitlimit 8 s + Backoff 1/3 s → höchstens ~30 s
	check(Time.get_ticks_msec() - t0 < 35000, "Offline-Fallback mit Zeitlimit", "%d ms" % (Time.get_ticks_msec() - t0))
	check(M.list.size() == 2, "Letzte Liste bleibt")
	var net = get_node("/root/Net")
	net.query_server("127.0.0.1", 11001)       # Favoriten-/LAN-Abfrage läuft unabhängig vom Master
	check(typeof(net.favorites) == TYPE_ARRAY and M.is_official_build(), "Favoriten/LAN ohne Master nutzbar")
