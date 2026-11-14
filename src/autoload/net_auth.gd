extends Node
## ENet-Auth auf dem Spielport (DH2-LAN-6, Masterserver-Protokoll Abschnitt 7/8/9.6/10.2). Kind von Net („Auth“).
## Rahmen "DH2A" | ver 1 | type | len (2 Byte BE) | Rumpf. Host: PROBE/PING (nie complete_auth), JOIN_HELLO →
## JOIN_CHALLENGE_RESP (Umschlag DH2/v1/join, mit Serverschlüssel signiert; LAN ohne Schlüssel: alg "none") → JOIN_OK
## (Host-Nonce + optionaler Beitrittsbeleg) → complete_auth. Client: Host-Identität nach Abschnitt 8
## (Masterliste streng, sonst known_hosts / Trust-on-first-use). LAN ohne Master bleibt spielbar (kein Konto nötig).

const MAGIC := "DH2A"
const VER := 1
const PROBE_REQ := 0x10
const PROBE_RESP := 0x11
const PING_REQ := 0x20
const PING_RESP := 0x21
const HELLO := 0x30
const CHALLENGE := 0x31
const JOIN_OK := 0x32
const ERROR := 0x3F
const E_VERSION := 0x01
const E_BAD_REQUEST := 0x02
const E_RATE := 0x03
const E_FULL := 0x04
const E_BANNED := 0x05
const E_HOST_KEY := 0x06
const E_BAD_SIG := 0x07
const E_TIMEOUT := 0x08
const ERR_NAMES := {0x01: "VERSION_MISMATCH", 0x02: "BAD_REQUEST", 0x03: "RATE_LIMITED", 0x04: "SERVER_FULL",
	0x05: "BANNED", 0x06: "HOST_KEY_MISMATCH", 0x07: "BAD_SIGNATURE", 0x08: "TIMEOUT"}
const MAX_REQ := 256
const MAX_PROBE_RESP := 4096
const MAX_OTHER := 1024
## Abweichung [D]: JOIN_HELLO mit acc.pub (RSA-3072-PEM ≈ 650 Byte) und JOIN_OK mit Beitrittsbeleg passen nicht in
## 256/1024 Byte → 3072 Byte für diese beiden Typen.
const MAX_HELLO := 3072
## Abweichung [D]: auth_timeout 30 s statt 3 s – Kartenladen blockiert den Host-Hauptthread (Zeitgeber laufen weiter).
const AUTH_TIMEOUT_S := 30.0
const KNOWN_HOSTS := "user://known_hosts.json"
const PER_IP_PEERS := 2
const PER_IP_REQ := 4
const PER_IP_WINDOW_MS := 10000
const GLOBAL_NOJOIN := 4

var net: Node                        ## /root/Net
var log_lines: Array = []            ## Tests/Diagnose
## Client
var expect := {}                     ## {server_id, pubkey_pem} aus der Masterliste (streng), sonst {}
var host_key := ""                   ## "<host_lower>:<port>"
var accept_host_change := false      ## nur ausdrücklich (Dialog „ersetzen“) – sonst Abbruch bei geänderter Identität
var last_host := {}                  ## {server_id, fingerprint, signed, known} der letzten Prüfung
var _cnonce := ""
## Host
var _pending := {}                   ## peer -> {ip, t, hn, acc, join}
var _ip_req := {}                    ## ip -> [ticks]
var _live := {}                      ## peer -> true, solange ENet ihn kennt / while ENet knows the peer
var _dropping := {}                  ## peer -> true, Trennung bereits geplant / drop already scheduled


func _mp() -> SceneMultiplayer:
	return multiplayer as SceneMultiplayer


func _master() -> Node:
	return get_node_or_null("/root/Master")


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()
	print("NET-AUTH: ", s)


## Vor create_server/create_client aufrufen (beide Seiten brauchen den Rückruf).
func install() -> void:
	var m := _mp()
	if m == null:
		return
	m.auth_callback = _on_auth
	m.auth_timeout = AUTH_TIMEOUT_S
	if not m.peer_authenticating.is_connected(_on_authenticating):
		m.peer_authenticating.connect(_on_authenticating)
		m.peer_authentication_failed.connect(_on_auth_failed)
	if not m.peer_disconnected.is_connected(_on_peer_gone):
		m.peer_disconnected.connect(_on_peer_gone)


## Peer ist weg (getrennt oder Auth fehlgeschlagen): kein weiteres disconnect_peer mehr.
## Peer is gone (disconnected or auth failed): no further disconnect_peer.
func _on_peer_gone(peer: int) -> void:
	_live.erase(peer)
	_pending.erase(peer)


func reset() -> void:
	_pending.clear()
	_cnonce = ""


# ------------------------------------------------------------------ Rahmen

static func frame(type: int, body: PackedByteArray) -> PackedByteArray:
	var out := MAGIC.to_ascii_buffer()
	out.append(VER)
	out.append(type)
	out.append((body.size() >> 8) & 0xFF)
	out.append(body.size() & 0xFF)
	out.append_array(body)
	return out


static func frame_json(type: int, d: Dictionary) -> PackedByteArray:
	return frame(type, JSON.stringify(d).to_utf8_buffer())


## {type, body} oder {} bei ungültigem Rahmen.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != MAGIC or data[4] != VER:
		return {}
	var n := (data[6] << 8) | data[7]
	if data.size() != 8 + n:
		return {}
	return {"type": int(data[5]), "body": data.slice(8)}


static func body_json(body: PackedByteArray):
	var d = JSON.parse_string(body.get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else null


func _send(peer: int, type: int, d: Dictionary) -> void:
	_mp().send_auth(peer, frame_json(type, d))


func _send_error(peer: int, code: int, extra := {}) -> void:
	var b := PackedByteArray([code])
	if not extra.is_empty():
		b.append_array(JSON.stringify(extra).to_utf8_buffer())
	_mp().send_auth(peer, frame(ERROR, b))
	_drop_later(peer)


## Trennt einen Peer verzögert – höchstens einmal und nur, solange er noch verbunden ist
## (v0.11.3-Demo: ~200 Fehler „disconnect_peer … !peers.has“ und freigegebene Lambda-Captures).
## Drops a peer after a delay – at most once and only while it is still connected.
func _drop_later(peer: int, ms := 200) -> void:
	if _dropping.has(peer) or not _live.has(peer):
		_pending.erase(peer)
		return
	_dropping[peer] = true
	var me: WeakRef = weakref(self)
	get_tree().create_timer(ms / 1000.0, true, false, true).timeout.connect(func():
		var a = me.get_ref()
		if a == null:
			return
		a._drop_now(peer))


func _drop_now(peer: int) -> void:
	_dropping.erase(peer)
	_pending.erase(peer)
	if not _live.has(peer):
		return
	_live.erase(peer)
	var p: ENetMultiplayerPeer = net._peer if net != null and is_instance_valid(net) else null
	if p and p.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		p.disconnect_peer(peer)


# ------------------------------------------------------------------ gemeinsamer Rückruf

func _on_authenticating(peer: int) -> void:
	if multiplayer.is_server():
		_live[peer] = true
		var ip := _peer_ip(peer)
		var same := _pending.values().filter(func(e): return e["ip"] == ip).size()
		var nojoin := _pending.values().filter(func(e): return not e["join"]).size()
		if same >= PER_IP_PEERS or nojoin >= GLOBAL_NOJOIN:
			_log("Peer %d (%s): zu viele Auth-Verbindungen -> getrennt" % [peer, ip])
			_drop_later(peer, 0)
			return
		_pending[peer] = {"ip": ip, "t": Time.get_ticks_msec(), "hn": "", "acc": {}, "join": false}
	elif peer == 1:
		_client_hello()


func _on_auth_failed(peer: int) -> void:
	if multiplayer.is_server() and _pending.has(peer) and net:
		net._reject_log(peer, "peer", "Anmeldung (ENet-Auth) nicht abgeschlossen -> getrennt")
	_pending.erase(peer)
	_live.erase(peer)
	if not multiplayer.is_server() and peer == 1 and net:
		net.auth_failed("TIMEOUT", "")


func _on_auth(peer: int, data: PackedByteArray) -> void:
	var f := parse(data)
	if multiplayer.is_server():
		_host_msg(peer, f, data.size())
	elif peer == 1:
		_client_msg(f)


func _peer_ip(peer: int) -> String:
	var p: ENetMultiplayerPeer = net._peer if net else null
	if p == null:
		return ""
	var pp := p.get_peer(peer)
	return pp.get_remote_address() if pp else ""


# ------------------------------------------------------------------ Host

func _rate_ok(ip: String) -> bool:
	var t := Time.get_ticks_msec()
	var l: Array = (_ip_req.get(ip, []) as Array).filter(func(x): return t - int(x) < PER_IP_WINDOW_MS)
	l.append(t)
	_ip_req[ip] = l
	return l.size() <= PER_IP_REQ


func _host_msg(peer: int, f: Dictionary, size: int) -> void:
	if f.is_empty() or not _pending.has(peer):
		_log("Peer %d: ungültiger Rahmen (%d Byte) -> getrennt" % [peer, size])
		_drop_later(peer, 0)
		return
	var e: Dictionary = _pending[peer]
	var type := int(f["type"])
	var body: PackedByteArray = f["body"]
	var limit := MAX_REQ if type in [PROBE_REQ, PING_REQ] else (MAX_HELLO if type in [HELLO, JOIN_OK] else MAX_OTHER)
	if body.size() > limit:
		_log("Peer %d: Rahmen 0x%02x zu groß (%d > %d) -> getrennt" % [peer, type, body.size(), limit])
		_drop_later(peer, 0)
		return
	if type in [PROBE_REQ, PING_REQ, HELLO] and not _rate_ok(String(e["ip"])):
		_send_error(peer, E_RATE)
		return
	var d = body_json(body)
	if d == null:
		_send_error(peer, E_BAD_REQUEST)
		return
	match type:
		PROBE_REQ:
			_send_probe_resp(peer, d)
			_drop_later(peer)
		PING_REQ:
			var si: Dictionary = net.server_info()
			_send(peer, PING_RESP, {"q": int(d.get("q", 0)), "players": int(si["players"]), "max": int(si["max"])})
			_drop_later(peer)
		HELLO:
			_host_hello(peer, e, d)
		JOIN_OK:
			_host_join_ok(peer, e, d)
		_:
			_drop_later(peer, 0)


func _signing_key() -> Array:
	var m := _master()
	if m and m.server_key != null and String(m.server_id) != "":
		return [m.server_key, String(m.server_id)]
	return [null, ""]


## Umschlag mit Serverschlüssel; ohne Schlüssel (LAN) unsigniert (alg "none").
func _host_envelope(ctx: String, payload: Dictionary) -> Dictionary:
	var k := _signing_key()
	if k[0] != null:
		return _master().make_envelope(ctx, payload, k[0], k[1])
	var p := payload.duplicate()
	p["v"] = 1
	return {"alg": "none", "kid": "", "payload": Marshalls.raw_to_base64(JSON.stringify(p).to_utf8_buffer()), "sig": ""}


func _send_probe_resp(peer: int, req: Dictionary) -> void:
	var k := _signing_key()
	var m := _master()
	var si: Dictionary = net.server_info()
	var phase := "playing"
	var gs := int(net.game_state)
	if gs == int(net.State.WARMUP):
		phase = "warmup"
	elif gs == int(net.State.WON) or gs == int(net.State.ENDED):
		phase = "round_end"
	if Game.current_mission() == null:
		phase = "loading"
	var full: bool = int(si["players"]) >= int(si["max"])
	var late_block: bool = int(net.mode()) == int(net.Mode.OBJECTIVES) and not bool(net.rule("allow_respawn")) \
		and float(net._match_t) > float(net.OBJ_LATE_JOIN_S)
	var p := {"n": String(req.get("n", "")), "sid": k[1], "t_host": m.now() if m else 0, "port": int(si["port"]),
		"build": m.build_info() if m else {}, "name": String(si["name"]).substr(0, 40), "map": String(si["map"]).substr(0, 64),
		"map_title": String(si["map_title"]).substr(0, 64), "mode": clampi(int(si["mode"]), 0, 4), "phase": phase,
		"players": int(si["players"]), "max": int(si["max"]), "bots": int(si["bots"]), "pw": bool(si["pw"]),
		"joinable": not full and not late_block, "ded": bool(si["ded"]),
		"acc": m.online_accounts() if m else []}
	var env := _host_envelope("DH2/v1/status", p)
	_log("PROBE von %s beantwortet (sid %s)" % [_pending.get(peer, {}).get("ip", "?"), String(k[1]).substr(0, 12)])
	_mp().send_auth(peer, frame(PROBE_RESP, JSON.stringify(env).to_utf8_buffer()))


func _host_hello(peer: int, e: Dictionary, d: Dictionary) -> void:
	e["join"] = true
	var m := _master()
	var b = d.get("build", {})
	var mine: Dictionary = m.build_info() if m else {"net_protocol": net.PROTOCOL, "compat": 1}
	if typeof(b) != TYPE_DICTIONARY or String(b.get("net_protocol", "")) != String(mine["net_protocol"]) \
			or int(b.get("compat", -1)) != int(mine["compat"]):
		_log("Peer %d: andere Spielversion (%s) -> abgewiesen" % [peer, str(b)])
		_send_error(peer, E_VERSION, {"server_build": mine})
		return
	if net.humans() >= int(net.settings.get("max_players", 8)):
		_send_error(peer, E_FULL)
		return
	var acc = d.get("acc", {})
	e["acc"] = acc if typeof(acc) == TYPE_DICTIONARY else {}
	e["hn"] = m.nonce(32) if m else Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
	var k := _signing_key()
	var p := {"n": String(d.get("n", "")).substr(0, 64), "sid": k[1], "pubkey_pem": k[0].save_to_string(true) if k[0] else "",
		"t_host": m.now() if m else 0, "hn": e["hn"]}
	_mp().send_auth(peer, frame(CHALLENGE, JSON.stringify(_host_envelope("DH2/v1/join", p)).to_utf8_buffer()))


func _host_join_ok(peer: int, e: Dictionary, d: Dictionary) -> void:
	if String(e["hn"]) == "" or String(d.get("hn", "")) != String(e["hn"]):
		_log("Peer %d: JOIN_OK mit falscher Host-Nonce -> getrennt" % peer)
		_send_error(peer, E_BAD_REQUEST)
		return
	var gh := ""
	var m := _master()
	var proof = d.get("proof", {})
	if m and typeof(proof) == TYPE_DICTIONARY and not proof.is_empty() and String(_signing_key()[1]) != "":
		gh = m.verify_join_proof(proof, e["acc"], String(_signing_key()[1]), String(e["hn"]))
		if gh == "":
			_log("Peer %d: Beitrittsbeleg ungültig (Spieler ohne Konto)" % peer)
	net.auth_accounts[peer] = {"gh": gh, "proof": proof if gh != "" else {}}
	_pending.erase(peer)
	_mp().complete_auth(peer)


# ------------------------------------------------------------------ Client

func _client_hello() -> void:
	var m := _master()
	_cnonce = m.nonce(32) if m else Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
	var d := {"n": _cnonce, "build": m.build_info() if m else {"net_protocol": net.PROTOCOL, "compat": 1},
		"want_id": String(expect.get("server_id", ""))}
	var acc: Dictionary = m.join_account() if m else {}
	if not acc.is_empty():
		d["acc"] = acc
	_send(1, HELLO, d)


func _client_msg(f: Dictionary) -> void:
	if f.is_empty():
		net.auth_failed("BAD_REQUEST", "")
		return
	var body: PackedByteArray = f["body"]
	match int(f["type"]):
		ERROR:
			var code := int(body[0]) if body.size() > 0 else E_BAD_REQUEST
			var extra = body_json(body.slice(1)) if body.size() > 1 else null
			var info := ""
			if code == E_VERSION and extra != null:
				info = String((extra.get("server_build", {}) as Dictionary).get("game_version", "?"))
			net.auth_failed(String(ERR_NAMES.get(code, "BAD_REQUEST")), info)
		CHALLENGE:
			var env = body_json(body)
			var res := check_challenge(env)
			if String(res.get("error", "")) != "":
				_log("Host-Identität abgelehnt: " + String(res["error"]))
				net.auth_failed(String(res["error"]), "")
				return
			var ok := {"hn": String(res["hn"])}
			var m := _master()
			if m and String(res["sid"]) != "":
				var pr: Dictionary = m.make_join_proof(String(res["sid"]), String(res["hn"]))
				if not pr.is_empty():
					ok["proof"] = pr
			_send(1, JOIN_OK, ok)
			_mp().complete_auth(1)
		_:
			net.auth_failed("BAD_REQUEST", "")


## Abschnitt 8: Challenge prüfen. Liefert {sid, hn} oder {error}.
func check_challenge(env) -> Dictionary:
	if typeof(env) != TYPE_DICTIONARY:
		return {"error": "BAD_REQUEST"}
	var raw := Marshalls.base64_to_raw(String(env.get("payload", "")))
	var p = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY or String(p.get("n", "")) != _cnonce or String(p.get("hn", "")).length() < 16:
		return {"error": "BAD_SIGNATURE"}
	var signed := String(env.get("alg", "")) != "none"
	var sid := ""
	if signed:
		var k := CryptoKey.new()
		var MC = load("res://src/autoload/master_client.gd")
		if k.load_from_string(String(p.get("pubkey_pem", "")), true) != OK:
			return {"error": "BAD_SIGNATURE"}
		sid = MC.fingerprint(k)
		if sid != String(p.get("sid", "")) or sid != String(env.get("kid", "")) \
				or not MC.verify_ctx("DH2/v1/join", raw, Marshalls.base64_to_raw(String(env.get("sig", ""))), k):
			return {"error": "BAD_SIGNATURE"}
	last_host = {"server_id": sid, "fingerprint": fingerprint_text(sid), "signed": signed, "known": false}
	# Fall 1: Masterliste – streng, kein Rückfall
	if not expect.is_empty():
		if sid == "" or sid != String(expect.get("server_id", "")):
			return {"error": "HOST_KEY_MISMATCH"}
		return {"sid": sid, "hn": String(p["hn"])}
	# Fall 2/3: known_hosts (Trust-on-first-use)
	var kh := load_known_hosts()
	if kh.has(host_key):
		var known := String((kh[host_key] as Dictionary).get("server_id", ""))
		last_host["known"] = true
		if known != sid and not accept_host_change:
			_log("Serveridentität von %s hat sich geändert (%s -> %s)" % [host_key, known.substr(0, 16), sid.substr(0, 16)])
			return {"error": "HOST_KEY_MISMATCH"}
	if sid != "" and host_key != "":
		var first := int((kh.get(host_key, {}) as Dictionary).get("first_seen", 0))
		var now := int(Time.get_unix_time_from_system())
		if not kh.has(host_key) or accept_host_change or first == 0:
			_log("Neuer Server %s, Fingerabdruck %s" % [host_key, last_host["fingerprint"]])
			first = now
		kh[host_key] = {"server_id": sid, "first_seen": first, "last_seen": now}
		save_known_hosts(kh)
	accept_host_change = false
	return {"sid": sid, "hn": String(p["hn"])}


## Fingerabdruck XXXX-XXXX-XXXX-XXXX (erste 16 Hex).
static func fingerprint_text(sid: String) -> String:
	if sid.length() < 16:
		return ""
	var s := sid.substr(0, 16).to_upper()
	return "%s-%s-%s-%s" % [s.substr(0, 4), s.substr(4, 4), s.substr(8, 4), s.substr(12, 4)]


## Pfad der known_hosts-Datei (0.11.5: in Tests im Testprofil, Game.user_path).
static func known_hosts_path() -> String:
	return Game.user_path(KNOWN_HOSTS.trim_prefix("user://"))


static func load_known_hosts() -> Dictionary:
	var p := known_hosts_path()
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func save_known_hosts(d: Dictionary) -> void:
	var f := FileAccess.open(known_hosts_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))
