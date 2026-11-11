extends Node
## Lokaler Masterserver-Nachbau für Tests (nur 127.0.0.1, eigene Implementierung nach Spezifikation /v1).
## Prüft X-DH2-Auth wie der echte Master (Build-Testschlüssel), signiert Antworten mit einem Laufzeit-Testschlüssel.
## Schalter: list_mode ("ok"|"badsig"|"expired"|"proto"), fail_next {pfad: [status, code, retry_after]}, drop_unsigned.

const MC := preload("res://src/autoload/master_client.gd")

var port := 0
var master_key: CryptoKey
var master_kid := ""
var build_pub: CryptoKey
var build_kid := ""
var list_mode := "ok"
var fail_next := {}
var report_verdict := "ACCEPTED"
var stats_rank := 7
var log: Array = []                 ## {method, path, query, auth_ok, body}
var accounts := {}                  ## guid_hash -> {pub, name, guid}
var servers := {}
var seen_nonces := {}
var _srv := TCPServer.new()
var _conns: Array = []
var _crypto := Crypto.new()


func setup(build_public: CryptoKey) -> void:
	build_pub = build_public
	build_kid = "b1-" + MC.fingerprint(build_public).substr(0, 16)
	master_key = _crypto.generate_rsa(2048)
	master_kid = "m1-" + MC.fingerprint(master_key).substr(0, 16)
	for p in range(18431, 18460):
		if _srv.listen(p, "127.0.0.1") == OK:
			port = p
			break


func _exit_tree() -> void:
	_srv.stop()


func _process(_d: float) -> void:
	while _srv.is_connection_available():
		_conns.append({"s": _srv.take_connection(), "buf": PackedByteArray()})
	for c in _conns.duplicate():
		var s: StreamPeerTCP = c["s"]
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		var n := s.get_available_bytes()
		if n > 0:
			c["buf"].append_array(s.get_data(n)[1])
		var req = _parse(c["buf"])
		if req != null:
			_conns.erase(c)
			_handle(s, req)


func _parse(buf: PackedByteArray):
	var txt := buf.get_string_from_ascii()
	var he := txt.find("\r\n\r\n")
	if he < 0:
		return null
	var lines := txt.substr(0, he).split("\r\n")
	var first := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var k := lines[i].get_slice(":", 0).strip_edges().to_lower()
		headers[k] = lines[i].substr(lines[i].find(":") + 1).strip_edges()
	var clen := int(headers.get("content-length", "0"))
	if buf.size() < he + 4 + clen:
		return null
	var target := first[1]
	return {"method": first[0], "path": target.get_slice("?", 0), "query": target.get_slice("?", 1) if target.contains("?") else "",
		"headers": headers, "body": buf.slice(he + 4, he + 4 + clen)}


## Gleiche Prüfung wie der Master (eigene Implementierung): "" = gültig, sonst Grund.
func check_auth(req: Dictionary) -> String:
	var h := String(req["headers"].get("x-dh2-auth", ""))
	var parts := h.split(".")
	if parts.size() != 4:
		return "auth_format"
	if parts[0] != build_kid:
		return "auth_unknown_build"
	var ts := int(parts[1])
	if absi(int(Time.get_unix_time_from_system()) - ts) > 60:
		return "auth_stale"
	if parts[2].length() != 43:
		return "auth_nonce"
	var payload := "%s\n%s\n%s\n%s\n%s\n%s" % [req["method"], req["path"], req["query"], parts[1], parts[2],
		MC.sha256(req["body"]).hex_encode()]
	if not MC.verify_ctx("DH2/v1/client", payload.to_utf8_buffer(), Marshalls.base64_to_raw(parts[3]), build_pub):
		return "auth_bad_sig"
	if seen_nonces.has(parts[2]):
		return "auth_replay"
	seen_nonces[parts[2]] = true
	return ""


func _handle(s: StreamPeerTCP, req: Dictionary) -> void:
	var reason := check_auth(req)
	var entry := {"method": req["method"], "path": req["path"], "query": req["query"], "auth": reason,
		"body": req["body"].get_string_from_utf8()}
	log.append(entry)
	if reason != "":
		s.disconnect_from_host()      # official: kommentarlos schließen
		return
	if fail_next.has(req["path"]):
		var f: Array = fail_next[req["path"]]
		fail_next.erase(req["path"])
		var e := {"code": f[1], "message": "test"}
		if f.size() > 2:
			e["retry_after"] = f[2]
		_reply(s, int(f[0]), {"error": e})
		return
	var p: String = req["path"]
	if req["method"] == "GET" and p == "/v1/servers":
		_reply(s, 200, _list(req["query"]))
	elif p == "/v1/accounts/bind":
		_bind(s, req)
	elif p == "/v1/accounts/login":
		_login(s, req)
	elif req["method"] == "GET" and p.begins_with("/v1/accounts/") and p.ends_with("/stats"):
		_reply(s, 200, {"guid_hash": p.get_slice("/", 3), "rank": stats_rank,
			"career": {"level": stats_rank, "name": "Test", "xp": 12345}})
	elif p == "/v1/servers/register":
		var pl = _open(req["body"], "DH2/v1/register", "pubkey_pem")
		if pl == null:
			_reply(s, 401, {"error": {"code": "BAD_SIGNATURE"}})
			return
		servers[pl["sid"]] = pl
		_reply(s, 202, {"server_id": pl["sid"], "state": "PENDING", "heartbeat_interval": 30, "timeout": 60})
	elif p == "/v1/matches/report":
		var env = JSON.parse_string(req["body"].get_string_from_utf8())
		var pl = _open_with(env, "DH2/v1/stats", _server_pub(String(env.get("kid", ""))))
		if pl == null:
			_reply(s, 401, {"error": {"code": "BAD_SIGNATURE"}})
			return
		reports.append(pl)
		if report_verdict == "UNRANKED":
			_reply(s, 200, {"match_id": pl["match_id"], "verdict": "UNRANKED", "ranked": false, "verify": "untrusted"})
			return
		var car := []
		for pp in pl.get("players", []):
			car.append({"gh": pp["gh"], "xp_gained": 420, "old_rank": 2, "promoted": true,
				"career": {"level": 3, "name": "Sergeant", "xp": 5100}})
		_reply(s, 200, {"match_id": pl["match_id"], "verdict": "ACCEPTED", "reasons": [], "career": car})
	elif req["method"] == "POST" and p.begins_with("/v1/servers/") and p.ends_with("/heartbeat"):
		var sid := p.get_slice("/", 3)
		if not servers.has(sid):
			_reply(s, 404, {"error": {"code": "UNKNOWN_SERVER"}})
			return
		heartbeats += 1
		_reply(s, 200, {"state": "ONLINE", "last_verified": int(Time.get_unix_time_from_system()), "next_heartbeat": 30})
	elif req["method"] == "DELETE" and p.begins_with("/v1/servers/"):
		var sid := p.get_slice("/", 3)
		var env = JSON.parse_string(req["body"].get_string_from_utf8())
		if _open_with(env, "DH2/v1/unregister", _server_pub(sid)) == null:
			_reply(s, 401, {"error": {"code": "BAD_SIGNATURE"}})
			return
		servers.erase(sid)
		unregistered.append(sid)
		_reply(s, 204, null)
	else:
		_reply(s, 404, {"error": {"code": "NOT_FOUND"}})


var reports: Array = []             ## geöffnete Berichts-Payloads (Tests)
var heartbeats := 0
var unregistered: Array = []


func _server_pub(kid: String) -> CryptoKey:
	if not servers.has(kid):
		return null
	var k := CryptoKey.new()
	k.load_from_string(String(servers[kid]["pubkey_pem"]), true)
	return k


func _open_with(env, ctx: String, key: CryptoKey):
	if typeof(env) != TYPE_DICTIONARY or key == null:
		return null
	var raw := Marshalls.base64_to_raw(String(env.get("payload", "")))
	if not MC.verify_ctx(ctx, raw, Marshalls.base64_to_raw(String(env.get("sig", ""))), key):
		return null
	return JSON.parse_string(raw.get_string_from_utf8())


## Umschlag mit dem im Payload mitgelieferten Schlüssel prüfen (kid = Fingerabdruck).
func _open(body: PackedByteArray, ctx: String, field: String):
	var env = JSON.parse_string(body.get_string_from_utf8())
	if typeof(env) != TYPE_DICTIONARY:
		return null
	var pre = JSON.parse_string(Marshalls.base64_to_raw(String(env.get("payload", ""))).get_string_from_utf8())
	if typeof(pre) != TYPE_DICTIONARY:
		return null
	var k := CryptoKey.new()
	if k.load_from_string(String(pre.get(field, "")), true) != OK or MC.fingerprint(k) != String(env.get("kid", "")):
		return null
	var pl = _open_with(env, ctx, k)
	if pl != null:
		pl["sid"] = env["kid"]
	return pl


func envelope(ctx: String, payload: Dictionary) -> Dictionary:
	var raw := JSON.stringify(payload).to_utf8_buffer()
	var data := ctx.to_ascii_buffer()
	data.append(0)
	data.append_array(raw)
	var sig := _crypto.sign(HashingContext.HASH_SHA256, MC.sha256(data), master_key)
	return {"alg": "RS256-PKCS1", "kid": master_kid, "payload": Marshalls.raw_to_base64(raw), "sig": Marshalls.raw_to_base64(sig)}


func _list(query: String) -> Dictionary:
	var t := int(Time.get_unix_time_from_system())
	var proto := query.get_slice("proto=", 1).get_slice("&", 0).uri_decode()
	var entry := {"server_id": "a".repeat(64), "pubkey_pem": "", "ip": "127.0.0.1", "port": 11001,
		"name": "Test" + String.chr(0x200B) + "Server", "build": {"game_version": "0.11.1", "net_protocol": proto, "compat": 1},
		"map": "m", "map_title": "Karte", "mode": 2, "phase": "playing", "players": 3, "max": 16, "bots": 2,
		"pw": true, "joinable": true, "ded": true, "verified_at": t, "entry_expires_at": t + 60,
		"ranked": true, "verify": "ok"}
	var e2 := entry.duplicate()
	e2["server_id"] = "b".repeat(64)
	e2["ranked"] = false
	e2["verify"] = "untrusted"
	e2["pw"] = false
	var e3 := entry.duplicate()
	e3["server_id"] = "c".repeat(64)
	e3["entry_expires_at"] = t - 5            # abgelaufen → ausblenden
	var pl := {"v": 1, "list_version": 1, "alg": "RS256-PKCS1", "kid": master_kid, "generated_at": t,
		"expires_at": t + 20, "proto": proto, "compat": 1, "servers": [entry, e2, e3]}
	if list_mode == "expired":
		pl["expires_at"] = t - 30
	elif list_mode == "proto":
		pl["proto"] = "DH2-LAN-0"
	var env := envelope("DH2/v1/serverlist", pl)
	if list_mode == "badsig":
		env["payload"] = Marshalls.raw_to_base64(JSON.stringify(pl).replace("Karte", "Fake").to_utf8_buffer())
	return env


func _bind(s: StreamPeerTCP, req: Dictionary) -> void:
	var pl = _open(req["body"], "DH2/v1/account", "account_pubkey_pem")
	if pl == null:
		_reply(s, 401, {"error": {"code": "BAD_SIGNATURE"}})
		return
	# GUID-Box öffnen (Abschnitt 9.4)
	var box: Dictionary = pl["guid_box"]
	var k := _crypto.decrypt(master_key, Marshalls.base64_to_raw(String(box["ek"])))
	var kenc := _crypto.hmac_digest(HashingContext.HASH_SHA256, k, "DH2-GUIDBOX-ENC".to_ascii_buffer())
	var kmac := _crypto.hmac_digest(HashingContext.HASH_SHA256, k, "DH2-GUIDBOX-MAC".to_ascii_buffer())
	var iv := Marshalls.base64_to_raw(String(box["iv"]))
	var ct := Marshalls.base64_to_raw(String(box["ct"]))
	var mac := "DH2-GUIDBOX-v1".to_ascii_buffer()
	mac.append(0)
	mac.append_array(String(box["kid"]).to_ascii_buffer())
	mac.append(0)
	mac.append_array(iv)
	mac.append_array(ct)
	if k.size() != 32 or _crypto.hmac_digest(HashingContext.HASH_SHA256, kmac, mac) != Marshalls.base64_to_raw(String(box["tag"])):
		_reply(s, 400, {"error": {"code": "BAD_REQUEST", "message": "guid_box invalid"}})
		return
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, kenc, iv)
	var pt := aes.update(ct)
	aes.finish()
	pt = pt.slice(0, pt.size() - pt[pt.size() - 1])
	var inner = JSON.parse_string(pt.get_string_from_utf8())
	if typeof(inner) != TYPE_DICTIONARY or int(inner["ts"]) != int(pl["ts"]) or String(inner["akid"]) != String(pl["sid"]) \
			or not RegEx.create_from_string("^[0-9a-f]{32}-[0-9a-f]{32}$").search(String(inner["guid"])):
		_reply(s, 400, {"error": {"code": "BAD_REQUEST", "message": "guid_box invalid"}})
		return
	var gh := MC.guid_hash_of(String(inner["guid"]))
	accounts[gh] = {"pub": pl["account_pubkey_pem"], "name": pl["name"], "guid": inner["guid"], "akid": pl["sid"]}
	_reply(s, 200, envelope("DH2/v1/master-response", {"v": 1, "guid_hash": gh, "name": pl["name"], "bound_at": int(pl["ts"])}))


func _login(s: StreamPeerTCP, req: Dictionary) -> void:
	var env = JSON.parse_string(req["body"].get_string_from_utf8())
	var pre = JSON.parse_string(Marshalls.base64_to_raw(String(env.get("payload", ""))).get_string_from_utf8())
	var gh := String(pre.get("guid_hash", ""))
	if not accounts.has(gh):
		_reply(s, 404, {"error": {"code": "UNKNOWN_ACCOUNT"}})
		return
	var k := CryptoKey.new()
	k.load_from_string(String(accounts[gh]["pub"]), true)
	if env.get("kid") != accounts[gh]["akid"] or _open_with(env, "DH2/v1/account", k) == null:
		_reply(s, 401, {"error": {"code": "BAD_SIGNATURE"}})
		return
	var over: bool = pre.has("rank") and int(pre["rank"]) != 5
	_reply(s, 200, {"session": "x".repeat(43), "expires_at": int(Time.get_unix_time_from_system()) + 3600,
		"guid_hash": gh, "name": accounts[gh]["name"], "rank": 5, "rank_source": "master", "rank_overridden": over})


func _reply(s: StreamPeerTCP, status: int, j) -> void:
	var body := JSON.stringify(j).to_utf8_buffer() if j != null else PackedByteArray()
	var head := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]
	s.put_data(head.to_ascii_buffer())
	s.put_data(body)
	s.disconnect_from_host()
