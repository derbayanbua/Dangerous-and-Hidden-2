extends Node
## Masterserver-Anbindung 0.11 (Autoload `Master`). Nur Logik, keine Oberfläche.
## Spezifikation: Masterserver-Protokoll /v1 (Abschnitte 2, 4, 5, 6, 9, 10, 15.s/t/u/x/y/z).
##
## Öffentliche API (für das Menü):
##   Signale
##     status_changed(state: String, text: String)  state: "off" | "no_build" | "connecting" | "online" | "offline"
##     servers_updated(list: Array)                  Liste von Einträgen (siehe _entry_for)
##     login_done(ok: bool, info: Dictionary)        info: {guid_hash, name, rank, career?, code?, text?}
##     error(code: String, text: String)             Masterfehlercode (Abschnitt 6) bzw. NET_* / LIST_INVALID / NO_BUILD
##     match_reported(resp: Dictionary)              Spielserver: Antwort auf den Rundenbericht (verdict/ranked/career)
##     ranks_updated()                               Master-Ränge in Net.players geändert (Schlüssel "master_rank")
##   Abfragen
##     is_official_build() -> bool                   nur mit eingespeistem Build-Schlüssel
##     connect_master()                              nach Zustimmung zum Datenschutzhinweis; Liste + ggf. Anmeldung
##     refresh_servers(filter := {})                 filter: {mode:int, free:bool, nopw:bool}
##     ping_server(entry)                            UDP-Abfrage (Port+1), Ergebnis in entry.ping + servers_updated
##     login(profile := {})                          bindet/meldet das Konto an (GUID nach Abschnitt 9)
##     rank_of(guid_hash) -> int                     zuletzt bekannter Master-Rang (-1 = unbekannt)
##     fetch_rank(guid_hash) -> Dictionary           GET /v1/accounts/{gh}/stats (await)
##   Spielserver
##     load_server_key(path) -> String               RSA-Serverschlüssel laden/erzeugen, liefert server_id
##     register_server(info) / unregister_server(reason) / report_match(report)
##     set_peer_account(peer_id, guid_hash)          Zuordnung Spieler <-> Konto (nach Beitrittsbeleg)
## Ohne Master (offline, kein offizieller Build) laufen LAN, Direktbeitritt und Favoriten unverändert über Net.

signal status_changed(state: String, text: String)
signal servers_updated(list: Array)
signal login_done(ok: bool, info: Dictionary)
signal error(code: String, text: String)
signal match_reported(resp: Dictionary)
signal ranks_updated
signal promoted(level: int, rank_name: String)

var promotions_sent: Array = []      ## Spielserver: [peer_id, level] (Protokoll/Tests)

const CAREER := preload("res://src/campaign/career.gd")
const DEFAULT_URL :="https://hd2master.fun"
const BUILD_KEY_PATH := "res://build_key/client_key.pem"     ## nur in offiziellen Builds vorhanden (gitignored)
const COMPAT := 1
const CTX_CLIENT := "DH2/v1/client"
const ALG := "RS256-PKCS1"
const LIST_TOLERANCE_S := 5
const TIMEOUT_S := 8.0
const RETRIES := 2                  ## Wiederholungen bei Netzfehler/5xx/429 (Backoff 1 s, 3 s)
const REPORT_BACKOFF := [5.0, 30.0, 120.0]
const PING_PARALLEL := 8
const PING_INTERVAL_MS := 15000
const PING_TIMEOUT_MS := 2000
const REPORT_KEYS := ["match_id", "map", "mode", "round", "started_at", "ended_at", "partial", "result"]
const PLAYER_KEYS := ["gh", "name", "team", "kills", "deaths", "assists", "score", "teamkills", "suicides", "time_s",
	"won", "proof", "ai_kills", "objectives", "revives", "extracted", "victims"]
const PING_TAG :="DH2-QUERY"       ## = Net.QUERY_TAG

const TEXTS := {
	"BAD_REQUEST": "Ungültige Anfrage.", "INVALID_FIELD": "Ungültiger Wert.",
	"BAD_SIGNATURE": "Identitätsprüfung fehlgeschlagen.", "TIMESTAMP_SKEW": "Systemuhr prüfen.",
	"REPLAY": "Anfrage wiederholt – bitte erneut versuchen.", "KEY_REJECTED": "Serverschlüssel ungültig.",
	"SERVER_BANNED": "Server gesperrt.", "IP_BANNED": "Zugriff vorübergehend gesperrt.",
	"GUID_BANNED": "Dieses Konto ist gesperrt.", "PC_BANNED": "Dieser PC ist für Online-Spiele gesperrt.",
	"NAME_REJECTED": "Name nicht erlaubt.", "PORT_NOT_ALLOWED": "Port nicht zulässig (Standard 11001).",
	"UNKNOWN_SERVER": "Server beim Master unbekannt.", "UNKNOWN_ACCOUNT": "Konto unbekannt.",
	"STATUS_INCONSISTENT": "Serverstatus widersprüchlich.", "VERSION_UNSUPPORTED": "Serverversion wird nicht mehr unterstützt.",
	"CLIENT_OUTDATED": "Bitte Spiel aktualisieren.", "RATE_LIMITED": "Zu viele Anfragen.",
	"UNREACHABLE": "Server aus dem Internet nicht erreichbar (UDP 11001 weiterleiten).",
	"CAPACITY": "Masterserver ausgelastet.", "INTERNAL": "Masterserver-Fehler.",
	"GUID_CONFLICT": "Konto ist an einen anderen Schlüssel gebunden.",
	"NO_BUILD": "Kein offizieller Build – Masterserver nicht verfügbar.",
	"NET_OFFLINE": "Masterserver nicht erreichbar – LAN und Favoriten weiter nutzbar.",
	"LIST_INVALID": "Serverliste ungültig.",
}

var master_url := DEFAULT_URL
var state := "off"
var list: Array = []                 ## letzte gültige Serverliste (UI-Einträge)
var account := {}                    ## {guid_hash, name, rank, session, expires_at}
var key_bits := 3072                 ## Tests: 2048
var time_offset := 0                 ## nur für Tests (Uhrabweichung simulieren)

var _build_key: CryptoKey = null
var _build_kid := ""
var _crypto := Crypto.new()
var _ranks := {}                     ## guid_hash -> {rank, career, at}
var _peer_gh := {}                   ## Spielserver: peer_id -> guid_hash

# Spielserver
var server_key: CryptoKey = null
var server_id := ""
var build_hash := ""
var registered := false
var _reg_info := {}
var _hb_seq := 0
var _hb_timer: Timer = null

# Ping
var _psock: PacketPeerUDP = null
var _pings := {}                     ## "ip:port" -> {sent, last}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--master_url="):
			master_url = a.get_slice("=", 1).strip_edges().trim_suffix("/")
	_load_build_key()
	_hb_timer = Timer.new()
	_hb_timer.one_shot = true
	_hb_timer.timeout.connect(_heartbeat)
	add_child(_hb_timer)
	_print_dedicated_identity.call_deferred()


func _process(_d: float) -> void:
	_poll_pings()


# ------------------------------------------------------------------ Build-Schlüssel

func _load_build_key() -> void:
	if not FileAccess.file_exists(BUILD_KEY_PATH):
		return
	var k := CryptoKey.new()
	if k.load_from_string(FileAccess.get_file_as_string(BUILD_KEY_PATH), false) == OK:
		set_build_key(k)


## Build-Schlüssel setzen (offizieller Build bzw. Tests mit Laufzeit-Testschlüssel). null = kein offizieller Build.
func set_build_key(k: CryptoKey) -> void:
	_build_key = k
	_build_kid = "b1-" + fingerprint(k).substr(0, 16) if k != null else ""


func is_official_build() -> bool:
	return _build_key != null


func build_kid() -> String:
	return _build_kid


# ------------------------------------------------------------------ Kryptografie (Abschnitt 2/4)

static func sha256(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()


## hex(SHA256(DER(SPKI))) des öffentlichen Teils.
static func fingerprint(k: CryptoKey) -> String:
	return sha256(der_of(k.save_to_string(true))).hex_encode()


static func der_of(pem: String) -> PackedByteArray:
	var body := ""
	for line in pem.split("\n"):
		var l := line.strip_edges()
		if l == "" or l.begins_with("-----"):
			continue
		body += l
	return Marshalls.base64_to_raw(body)


static func b64url(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").replace("=", "")


func nonce(n: int) -> String:
	return b64url(_crypto.generate_random_bytes(n))


func now() -> int:
	return int(Time.get_unix_time_from_system()) + time_offset


func sign_ctx(ctx: String, payload: PackedByteArray, key: CryptoKey) -> PackedByteArray:
	var data := ctx.to_ascii_buffer()
	data.append(0)
	data.append_array(payload)
	return _crypto.sign(HashingContext.HASH_SHA256, sha256(data), key)


static func verify_ctx(ctx: String, payload: PackedByteArray, sig: PackedByteArray, key: CryptoKey) -> bool:
	if key == null or sig.is_empty():
		return false
	var data := ctx.to_ascii_buffer()
	data.append(0)
	data.append_array(payload)
	return Crypto.new().verify(HashingContext.HASH_SHA256, sha256(data), sig, key)


## Signierter Umschlag (Abschnitt 4.1). Pflichtfelder v/ts/nonce werden ergänzt.
func make_envelope(ctx: String, payload: Dictionary, key: CryptoKey, kid: String) -> Dictionary:
	var p := payload.duplicate(true)
	if not p.has("v"):
		p["v"] = 1
	if not p.has("ts"):
		p["ts"] = now()
	if not p.has("nonce") and ctx != "DH2/v1/joinproof":
		p["nonce"] = nonce(16)
	var raw := JSON.stringify(sanitize(p)).to_utf8_buffer()
	return {"alg": ALG, "kid": kid, "payload": Marshalls.raw_to_base64(raw),
		"sig": Marshalls.raw_to_base64(sign_ctx(ctx, raw, key))}


## Nur Tests (Editor-Binary): zusätzlicher Master-Testschlüssel {kid: CryptoKey}. In Exporten wirkungslos.
var test_master_keys := {}


func master_key(kid: String) -> CryptoKey:
	if OS.has_feature("editor") and test_master_keys.has(kid):
		return test_master_keys[kid]
	return MasterKeys.key_for(kid)


func active_master_kid() -> String:
	if OS.has_feature("editor") and not test_master_keys.is_empty():
		return String(test_master_keys.keys()[0])
	return String(MasterKeys.TRUSTED.keys()[0])


## Masterumschlag prüfen: kid bekannt (MasterKeys), Signatur über die Rohbytes, erst dann parsen. null = ungültig.
func open_master_envelope(env, ctx: String):
	if typeof(env) != TYPE_DICTIONARY or String(env.get("alg", "")) != ALG:
		return null
	var kid := String(env.get("kid", ""))
	if master_key(kid) == null:
		return null
	var raw := Marshalls.base64_to_raw(String(env.get("payload", "")))
	var sig := Marshalls.base64_to_raw(String(env.get("sig", "")))
	if not verify_ctx(ctx, raw, sig, master_key(kid)):
		return null
	var d = JSON.parse_string(raw.get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else null


## Header X-DH2-Auth (Abschnitt 15.s): kid.ts.nonce.b64sig über METHODE\nPFAD\nROHQUERY\nTS\nNONCE\nhex(sha256(body)).
func auth_header(method: String, path: String, raw_query: String, body: PackedByteArray, ts := -1, n := "") -> String:
	if ts < 0:
		ts = now()
	if n == "":
		n = nonce(32)
	var payload := "%s\n%s\n%s\n%d\n%s\n%s" % [method, path, raw_query, ts, n, sha256(body).hex_encode()]
	var sig := sign_ctx(CTX_CLIENT, payload.to_utf8_buffer(), _build_key)
	return "%s.%d.%s.%s" % [_build_kid, ts, n, Marshalls.raw_to_base64(sig)]


# ------------------------------------------------------------------ Eingabebereinigung

static func bad_char(c: int) -> bool:
	return (c < 0x20 and c != 0x09 and c != 0x0A and c != 0x0D) or c == 0x7F or (c >= 0x80 and c <= 0x9F) \
		or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x2069) \
		or c == 0xFEFF or (c >= 0xE000 and c <= 0xF8FF) or c >= 0xFFF0


static func clean_text(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if not bad_char(c):
			out += String.chr(c)
	return out


## Alle Strings (auch Schlüssel) rekursiv bereinigen.
static func sanitize(v):
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return clean_text(String(v))
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[sanitize(k)] = sanitize(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(sanitize(x))
			return a
	return v


# ------------------------------------------------------------------ HTTP

func error_text(code: String) -> String:
	return String(TEXTS.get(code, code))


## Signierte Anfrage. Liefert {ok, status, json, code, text, retry_after}. code = Masterfehlercode bzw. NET_OFFLINE/NO_BUILD.
func request(method: String, path: String, query := "", body = null, retries := RETRIES) -> Dictionary:
	if not is_official_build():
		return {"ok": false, "status": 0, "code": "NO_BUILD", "text": error_text("NO_BUILD")}
	var res := {}
	var delay := 1.0
	for attempt in retries + 1:
		# 0.11.2: signierte Umschläge je Versuch NEU bauen (eigene ts/nonce) – eine Wiederholung mit identischem Umschlag
		# wertet der Master als REPLAY-Verstoß. Aufrufer übergeben dafür ein Callable, das den Umschlag erzeugt.
		var b = body.call() if typeof(body) == TYPE_CALLABLE else body
		var raw := PackedByteArray()
		if typeof(b) == TYPE_PACKED_BYTE_ARRAY:
			raw = b
		elif b != null:
			raw = JSON.stringify(sanitize(b)).to_utf8_buffer()
		res = await _send(method, path, query, raw)
		var st := int(res["status"])
		var transient: bool = st == 0 or st == 429 or st >= 500
		if not transient or attempt == retries:
			break
		var wait := maxf(delay, float(res.get("retry_after", 0)))
		await get_tree().create_timer(minf(wait, 30.0)).timeout
		delay *= 3.0
	return res


func _send(method: String, path: String, query: String, raw: PackedByteArray) -> Dictionary:
	var hr := HTTPRequest.new()
	hr.timeout = TIMEOUT_S
	hr.use_threads = false
	add_child(hr)
	var url := master_url + path + ("?" + query if query != "" else "")
	var headers := PackedStringArray(["X-DH2-Auth: " + auth_header(method, path, query, raw), "Accept: application/json"])
	if not raw.is_empty():
		headers.append("Content-Type: application/json")
	var m := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT,
		"DELETE": HTTPClient.METHOD_DELETE}
	var err := hr.request_raw(url, headers, int(m.get(method, HTTPClient.METHOD_GET)), raw)
	var out := {"ok": false, "status": 0, "json": null, "code": "NET_OFFLINE", "text": error_text("NET_OFFLINE")}
	if err != OK:
		hr.queue_free()
		return out
	var r: Array = await hr.request_completed
	hr.queue_free()
	var result: int = r[0]
	var status: int = r[1]
	var bytes: PackedByteArray = r[3]
	if result != HTTPRequest.RESULT_SUCCESS or status == 0:
		return out       # Verbindung abgewiesen/geschlossen (unsignierte Anfragen werden kommentarlos getrennt)
	out["status"] = status
	var j = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
	out["json"] = j
	if status >= 200 and status < 300:
		out["ok"] = true
		out["code"] = ""
		out["text"] = ""
		return out
	var e = j.get("error", {}) if typeof(j) == TYPE_DICTIONARY else {}
	out["code"] = String(e.get("code", "HTTP_%d" % status)) if typeof(e) == TYPE_DICTIONARY else "HTTP_%d" % status
	out["text"] = error_text(out["code"])
	if typeof(e) == TYPE_DICTIONARY and e.has("retry_after"):
		out["retry_after"] = int(e["retry_after"])
	return out


func _set_state(s: String, text: String) -> void:
	state = s
	status_changed.emit(s, text)


func _fail(res: Dictionary) -> void:
	if res["code"] == "NET_OFFLINE":
		_set_state("offline", error_text("NET_OFFLINE"))
	error.emit(String(res["code"]), String(res["text"]))


# ------------------------------------------------------------------ Versionsobjekt (Abschnitt 3.1)

func build_info() -> Dictionary:
	var bid := String(ProjectSettings.get_setting("application/config/build_id", ""))
	if bid == "" or OS.has_feature("editor"):
		bid = "dev" if bid == "" else bid
	return {"game_version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"net_protocol": net_protocol(), "compat": COMPAT, "build_id": bid,
		"godot": String(Engine.get_version_info().get("string", "")).substr(0, 32)}


func net_protocol() -> String:
	var n := get_node_or_null("/root/Net")
	return String(n.PROTOCOL) if n else "DH2-LAN-6"


# ------------------------------------------------------------------ Client: Verbindung, Liste

func connect_master() -> void:
	if not is_official_build():
		_set_state("no_build", error_text("NO_BUILD"))
		error.emit("NO_BUILD", error_text("NO_BUILD"))
		return
	_set_state("connecting", "Verbinde mit Masterserver …")
	var ok := await refresh_servers()
	if ok:
		_set_state("online", "Masterserver verbunden.")


func list_query(filter := {}) -> String:
	var q := "proto=%s&compat=%d" % [net_protocol().uri_encode(), COMPAT]
	if filter.has("mode") and int(filter["mode"]) >= 0:
		q += "&mode=%d" % clampi(int(filter["mode"]), 0, 4)
	if bool(filter.get("free", false)):
		q += "&free=1"
	if bool(filter.get("nopw", false)):
		q += "&nopw=1"
	return q


## Liste holen und prüfen. true = gültige Liste (auch leer).
func refresh_servers(filter := {}) -> bool:
	var res := await request("GET", "/v1/servers", list_query(filter))
	if not res["ok"]:
		_fail(res)
		return false
	var entries = parse_server_list(res["json"])
	if entries == null:
		error.emit("LIST_INVALID", error_text("LIST_INVALID"))
		return false
	# Ping der bisherigen Einträge übernehmen
	var old := {}
	for e in list:
		old[e["id"]] = e.get("ping", -1)
	for e in entries:
		e["ping"] = old.get(e["id"], -1)
	list = entries
	if state != "online":
		_set_state("online", "Masterserver verbunden.")
	servers_updated.emit(list)
	return true


## Umschlag DH2/v1/serverlist prüfen (Abschnitt 5.4) und in UI-Einträge wandeln. null = ganze Liste verwerfen.
func parse_server_list(env):
	var p = open_master_envelope(env, "DH2/v1/serverlist")
	if p == null:
		return null
	var t := now()
	if t > int(p.get("expires_at", 0)) + LIST_TOLERANCE_S:
		return null
	if String(p.get("proto", "")) != net_protocol() or int(p.get("compat", -1)) != COMPAT:
		return null
	if typeof(p.get("servers")) != TYPE_ARRAY:
		return null
	var out := []
	for s in p["servers"]:
		if typeof(s) != TYPE_DICTIONARY or t > int(s.get("entry_expires_at", 0)):
			continue
		out.append(_entry_for(s))
	return out


func _entry_for(s: Dictionary) -> Dictionary:
	var b: Dictionary = s.get("build", {}) if typeof(s.get("build")) == TYPE_DICTIONARY else {}
	var verify := String(s.get("verify", "untrusted"))
	return {"id": clean_text(String(s.get("server_id", ""))), "name": clean_text(String(s.get("name", ""))).substr(0, 40),
		"host": String(s.get("ip", "")), "port": int(s.get("port", 11001)),
		"map": clean_text(String(s.get("map", ""))), "map_title": clean_text(String(s.get("map_title", ""))).substr(0, 64),
		"mode": int(s.get("mode", 0)), "phase": String(s.get("phase", "")),
		"players": int(s.get("players", 0)), "max_players": int(s.get("max", 0)), "bots": int(s.get("bots", 0)),
		"ping": -1, "version": clean_text(String(b.get("game_version", ""))), "build": b,
		"password": bool(s.get("pw", false)), "joinable": bool(s.get("joinable", true)),
		"dedicated": bool(s.get("ded", false)), "ranked": bool(s.get("ranked", false)) and verify == "ok",
		"verify": verify, "pubkey_pem": String(s.get("pubkey_pem", "")), "source": "master"}


# ------------------------------------------------------------------ Ping (Port+1, Net-Abfrageformat)

func ping_server(entry: Dictionary) -> void:
	var key := "%s:%d" % [entry.get("host", ""), int(entry.get("port", 11001))]
	var t := Time.get_ticks_msec()
	var pg: Dictionary = _pings.get(key, {})
	if t - int(pg.get("last", -PING_INTERVAL_MS)) < PING_INTERVAL_MS:
		return
	var running := 0
	for k in _pings:
		if int(_pings[k].get("sent", 0)) > 0:
			running += 1
	if running >= PING_PARALLEL or not String(entry.get("host", "")).is_valid_ip_address():
		return
	if _psock == null:
		_psock = PacketPeerUDP.new()
		_psock.bind(0)
	_psock.set_dest_address(String(entry["host"]), int(entry.get("port", 11001)) + 1)
	# gleiches Format wie Net.query_server; ohne Auffüllen antwortet der Server nur mit den Kernfeldern (reicht für Ping)
	var q := "%s %d|%s" % [PING_TAG, t, key]
	_psock.put_packet(q.to_utf8_buffer())
	_pings[key] = {"sent": t, "last": t}


func _poll_pings() -> void:
	if _psock == null:
		return
	var changed := false
	while _psock.get_available_packet_count() > 0:
		var d = JSON.parse_string(_psock.get_packet().get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var q := String(d.get("qid", ""))
		var key := q.get_slice("|", 1)
		if not _pings.has(key):
			continue
		var ms := Time.get_ticks_msec() - int(q.get_slice("|", 0))
		_pings[key]["sent"] = 0
		for e in list:
			if "%s:%d" % [e["host"], e["port"]] == key:
				e["ping"] = ms
				changed = true
	var t := Time.get_ticks_msec()
	for k in _pings:
		if int(_pings[k]["sent"]) > 0 and t - int(_pings[k]["sent"]) > PING_TIMEOUT_MS:
			_pings[k]["sent"] = 0
	if changed:
		servers_updated.emit(list)


# ------------------------------------------------------------------ Konto (Abschnitt 9)

static func pc_prefix() -> String:
	var hw := "v1|" + OS.get_processor_name().strip_edges().to_lower() + "|" + OS.get_unique_id()
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, "DH2-PC-PREFIX-v1".to_ascii_buffer(),
		hw.to_utf8_buffer()).slice(0, 16).hex_encode()


static func guid_hash_of(guid: String) -> String:
	return sha256(("DH2-GUID-v1|" + guid).to_utf8_buffer()).hex_encode().substr(0, 32)


func _account_path(profile: Dictionary) -> String:
	var dir := String(profile.get("dir", ""))
	if dir == "":
		var g := get_node_or_null("/root/Game")
		dir = g.profile_dir() if g and String(g.profile_name) != "" else "user://master_account"
	return dir.path_join("account.json")


func _load_account(path: String, pname: String) -> Dictionary:
	var acc := {}
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			acc = d
	if not RegEx.create_from_string("^[0-9a-f]{32}-[0-9a-f]{32}$").search(String(acc.get("guid", ""))) \
			or String(acc.get("key_pem", "")) == "":
		var k := _crypto.generate_rsa(key_bits)
		acc = {"guid": pc_prefix() + "-" + _crypto.generate_random_bytes(16).hex_encode(),
			"key_pem": k.save_to_string(false), "name": pname, "bound_at": 0, "master_kid": ""}
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_save_account(path, acc)
	return acc


func _save_account(path: String, acc: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(acc, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)


## GUID-Box (Abschnitt 9.4): RSA-PKCS1v15-KEM + AES-256-CBC + HMAC-SHA256.
func guid_box(guid: String, ts: int, akid: String, master_kid: String) -> Dictionary:
	var mk := master_key(master_kid)
	var k := _crypto.generate_random_bytes(32)
	var ek := _crypto.encrypt(mk, k)
	var kenc := _crypto.hmac_digest(HashingContext.HASH_SHA256, k, "DH2-GUIDBOX-ENC".to_ascii_buffer())
	var kmac := _crypto.hmac_digest(HashingContext.HASH_SHA256, k, "DH2-GUIDBOX-MAC".to_ascii_buffer())
	var iv := _crypto.generate_random_bytes(16)
	var pt := JSON.stringify({"guid": guid, "ts": ts, "akid": akid}).to_utf8_buffer()
	var padn := 16 - pt.size() % 16
	for i in padn:
		pt.append(padn)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, kenc, iv)
	var ct := aes.update(pt)
	aes.finish()
	var mac := "DH2-GUIDBOX-v1".to_ascii_buffer()
	mac.append(0)
	mac.append_array(master_kid.to_ascii_buffer())
	mac.append(0)
	mac.append_array(iv)
	mac.append_array(ct)
	var tag := _crypto.hmac_digest(HashingContext.HASH_SHA256, kmac, mac)
	return {"kid": master_kid, "ek": Marshalls.raw_to_base64(ek), "iv": Marshalls.raw_to_base64(iv),
		"ct": Marshalls.raw_to_base64(ct), "tag": Marshalls.raw_to_base64(tag)}


## Anmelden (bindet beim ersten Mal). profile: {name, dir?, rank?}. Rang kommt immer vom Master.
func login(profile := {}) -> bool:
	var pname := clean_text(String(profile.get("name", "")).strip_edges())
	if pname == "":
		var g := get_node_or_null("/root/Game")
		pname = String(g.profile_name) if g else ""
	var path := _account_path(profile)
	var acc := _load_account(path, pname)
	var key := CryptoKey.new()
	key.load_from_string(String(acc["key_pem"]), false)
	var akid := fingerprint(key)
	var gh := guid_hash_of(String(acc["guid"]))
	var lp := {"op": "login", "guid_hash": gh, "build": build_info()}
	if profile.has("rank"):
		lp["rank"] = int(profile["rank"])     # nur Information, nie maßgeblich
	var res := await request("POST", "/v1/accounts/login", "", func(): return make_envelope("DH2/v1/account", lp, key, akid))
	if not res["ok"] and (res["code"] == "UNKNOWN_ACCOUNT" or (int(acc.get("bound_at", 0)) == 0 and res["code"] != "NET_OFFLINE")):
		var bres := await _bind(acc, key, akid, pname)
		if not bres["ok"]:
			_login_fail(bres)
			return false
		acc["bound_at"] = int(bres["payload"].get("bound_at", now()))
		acc["master_kid"] = String(bres["kid"])
		acc["name"] = String(bres["payload"].get("name", pname))
		_save_account(path, acc)
		res = await request("POST", "/v1/accounts/login", "", func(): return make_envelope("DH2/v1/account", lp, key, akid))
	if not res["ok"]:
		_login_fail(res)
		return false
	var j: Dictionary = res["json"] if typeof(res["json"]) == TYPE_DICTIONARY else {}
	if String(j.get("guid_hash", "")) != gh:
		_login_fail({"code": "BAD_REQUEST", "text": error_text("BAD_REQUEST")})
		return false
	account = {"guid_hash": gh, "name": clean_text(String(j.get("name", pname))), "rank": int(j.get("rank", 1)),
		"session": String(j.get("session", "")), "expires_at": int(j.get("expires_at", 0)),
		"rank_overridden": bool(j.get("rank_overridden", false))}
	_ranks[gh] = {"rank": account["rank"], "at": now()}
	_acc_key = key
	_acc_akid = akid
	login_done.emit(true, {"guid_hash": gh, "name": account["name"], "rank": account["rank"]})
	return true


# ------------------------------------------------------------------ Beitritt (Abschnitt 9.6 / 10.2)

var _acc_key: CryptoKey = null       ## Kontoschlüssel nach erfolgreicher Anmeldung (nur im Speicher)
var _acc_akid := ""


## JOIN_HELLO.acc = {gh, akid, pub} des angemeldeten Kontos; {} ohne Anmeldung.
func join_account() -> Dictionary:
	if _acc_key == null or String(account.get("guid_hash", "")) == "":
		return {}
	return {"gh": String(account["guid_hash"]), "akid": _acc_akid, "pub": _acc_key.save_to_string(true)}


## Beitrittsbeleg (Abschnitt 10.2): Umschlag DH2/v1/joinproof, kid = account_key_id. {} ohne Konto/Server-ID.
func make_join_proof(sid: String, hn: String) -> Dictionary:
	var a := join_account()
	if a.is_empty() or sid == "" or hn == "":
		return {}
	return make_envelope("DH2/v1/joinproof", {"gh": a["gh"], "sid": sid, "hn": hn}, _acc_key, _acc_akid)


## Spielserver: Beleg prüfen (kid = Fingerabdruck des Kontoschlüssels aus JOIN_HELLO, Signatur, gh/sid/hn, Zeit).
## Liefert guid_hash oder "".
func verify_join_proof(env, acc: Dictionary, sid: String, hn: String) -> String:
	if typeof(env) != TYPE_DICTIONARY or typeof(acc) != TYPE_DICTIONARY or String(env.get("alg", "")) != ALG:
		return ""
	var k := CryptoKey.new()
	if k.load_from_string(String(acc.get("pub", "")), true) != OK:
		return ""
	var akid := fingerprint(k)
	if String(env.get("kid", "")) != akid or String(acc.get("akid", akid)) != akid:
		return ""
	var raw := Marshalls.base64_to_raw(String(env.get("payload", "")))
	if not verify_ctx("DH2/v1/joinproof", raw, Marshalls.base64_to_raw(String(env.get("sig", ""))), k):
		return ""
	var p = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY:
		return ""
	var gh := String(p.get("gh", ""))
	if gh != String(acc.get("gh", "")) or not RegEx.create_from_string("^[0-9a-f]{32}$").search(gh) \
			or String(p.get("sid", "")) != sid or String(p.get("hn", "")) != hn or absi(int(p.get("ts", 0)) - now()) > 300:
		return ""
	return gh


## Spielserver: Beleg eines Peers (für den Rundenbericht) und Zuordnung lösen.
var _peer_proof := {}                ## peer_id -> Umschlag §10.2


func set_peer_proof(peer_id: int, proof: Dictionary) -> void:
	_peer_proof[peer_id] = proof


func peer_account(peer_id: int) -> String:
	return String(_peer_gh.get(peer_id, ""))


func peer_proof(peer_id: int) -> Dictionary:
	return _peer_proof.get(peer_id, {})


func clear_peer(peer_id: int) -> void:
	_peer_gh.erase(peer_id)
	_peer_proof.erase(peer_id)


## Angemeldete Konten (für PROBE_RESP.acc, max. 32).
func online_accounts() -> Array:
	var out := []
	for pid in _peer_gh:
		out.append(String(_peer_gh[pid]))
	return out.slice(0, 32)


func _bind(acc: Dictionary, key: CryptoKey, akid: String, pname: String) -> Dictionary:
	var mkid := active_master_kid()
	var ts := now()
	var p := {"ts": ts, "op": "bind", "account_pubkey_pem": key.save_to_string(true), "name": pname,
		"build": build_info(), "guid_box": guid_box(String(acc["guid"]), ts, akid, mkid)}
	var res := await request("POST", "/v1/accounts/bind", "", func(): return make_envelope("DH2/v1/account", p, key, akid))
	if not res["ok"]:
		return res
	var pl = open_master_envelope(res["json"], "DH2/v1/master-response")
	if pl == null:
		return {"ok": false, "code": "BAD_SIGNATURE", "text": error_text("BAD_SIGNATURE")}
	return {"ok": true, "payload": pl, "kid": String(res["json"].get("kid", ""))}


func _login_fail(res: Dictionary) -> void:
	login_done.emit(false, {"code": res.get("code", ""), "text": res.get("text", "")})
	_fail(res)


## Zuletzt bekannter Master-Rang (-1 = unbekannt). Nie lokal berechnet.
func rank_of(gh: String) -> int:
	return int(_ranks.get(gh, {}).get("rank", -1))


func career_of(gh: String) -> Dictionary:
	return _ranks.get(gh, {}).get("career", {})


## Öffentliche Stats eines Kontos (rank, career, Zähler). Leeres Dictionary bei Fehler.
func fetch_rank(gh: String) -> Dictionary:
	if not RegEx.create_from_string("^[0-9a-f]{32}$").search(gh):
		return {}
	var res := await request("GET", "/v1/accounts/%s/stats" % gh)
	if not res["ok"] or typeof(res["json"]) != TYPE_DICTIONARY:
		return {}
	var j: Dictionary = res["json"]
	_ranks[gh] = {"rank": int(j.get("rank", -1)), "career": j.get("career", {}), "at": now()}
	return j


# ------------------------------------------------------------------ Spielserver (Abschnitt 5.1–5.3, 10, 15.t/u)

## Serverschlüssel laden oder (fehlt die Datei) erzeugen. Liefert die server_id (64 hex) bzw. "".
func load_server_key(path: String) -> String:
	var k := CryptoKey.new()
	if FileAccess.file_exists(path):
		if k.load(path, false) != OK:
			push_error("MASTER: Serverschlüssel nicht lesbar: " + path)
			return ""
	else:
		k = _crypto.generate_rsa(key_bits)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if k.save(path, false) != OK:
			push_error("MASTER: Serverschlüssel nicht speicherbar: " + path)
			return ""
	server_key = k
	server_id = fingerprint(k)
	return server_id


## SHA-256 über EXE und PCK (in dieser Reihenfolge, ein Hash). Im Editor leer.
func compute_build_hash() -> String:
	if OS.has_feature("editor"):
		return ""
	var exe := OS.get_executable_path()
	var pck := exe.get_basename() + ".pck"
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for p in [exe, pck]:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		while f.get_position() < f.get_length():
			h.update(f.get_buffer(1 << 20))
	build_hash = h.finish().hex_encode()
	return build_hash


func _print_dedicated_identity() -> void:
	var cfg := ""
	var keyp := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dedicated="):
			cfg = a.get_slice("=", 1)
		elif a.begins_with("--server_key="):
			keyp = a.get_slice("=", 1)
	if keyp == "" and cfg != "":
		keyp = cfg.get_basename() + ".key"
	if keyp == "":
		return
	if load_server_key(keyp) != "":
		compute_build_hash()
		print("MASTER: Server-ID %s (Schlüssel %s)" % [server_id, keyp.get_file()])
		if build_hash != "":
			print("MASTER: build_hash %s" % build_hash)


## Registrierung. info: {name, port, public?}. Startet den Heartbeat.
var _reg_fail_n := 0     ## aufeinanderfolgende Ablehnungen wegen Sperre (gestaffelte Wartezeit)


func register_server(info: Dictionary) -> bool:
	if server_key == null:
		error.emit("KEY_REJECTED", "Kein Serverschlüssel geladen.")
		return false
	_reg_info = info.duplicate()
	var p := {"pubkey_pem": server_key.save_to_string(true), "port": int(info.get("port", 11001)),
		"build": build_info(), "name": clean_text(String(info.get("name", "DH2-Server")).strip_edges()).substr(0, 40),
		"public": bool(info.get("public", true))}
	if build_hash != "":
		p["build_hash"] = build_hash
	var res := await request("POST", "/v1/servers/register", "", func(): return make_envelope("DH2/v1/register", p, server_key, server_id))
	if not res["ok"]:
		registered = false
		_fail(res)
		# später erneut versuchen; nach einer Sperre nicht jede Minute neu anmelden (zählt sonst als weiterer Verstoß):
		# retry_after des Masters beachten, sonst gestaffelt 60 s → 5 → 15 → 60 min (0.11.2)
		var wait := 60.0
		if String(res.get("code", "")) in ["SERVER_BANNED", "IP_BANNED", "KEY_REJECTED", "REPLAY"]:
			_reg_fail_n += 1
			wait = [300.0, 900.0, 3600.0][mini(_reg_fail_n - 1, 2)]
		wait = maxf(wait, float(res.get("retry_after", 0)))
		_hb_timer.start(minf(wait, 6.0 * 3600.0))
		return false
	_reg_fail_n = 0
	registered = true
	_hb_seq = maxi(_hb_seq, Time.get_ticks_msec())
	var j: Dictionary = res["json"] if typeof(res["json"]) == TYPE_DICTIONARY else {}
	_schedule_hb(int(j.get("heartbeat_interval", 30)))
	_set_state("online", "Server beim Master registriert (%s)." % String(j.get("state", "PENDING")))
	return true


func _schedule_hb(interval: int) -> void:
	_hb_timer.start(maxf(5.0, interval + randf_range(-3.0, 3.0)))


func _heartbeat() -> void:
	if not registered:
		if not _reg_info.is_empty():
			await register_server(_reg_info)
		return
	_hb_seq += 1
	var p := {"server_id": server_id, "seq": _hb_seq}
	var res := await request("POST", "/v1/servers/%s/heartbeat" % server_id, "",
		make_envelope("DH2/v1/heartbeat", p, server_key, server_id), 0)
	if res["ok"]:
		var j: Dictionary = res["json"] if typeof(res["json"]) == TYPE_DICTIONARY else {}
		if j.has("probe_error"):
			error.emit("UNREACHABLE", error_text("UNREACHABLE"))
		_schedule_hb(int(j.get("next_heartbeat", 30)))
	elif res["code"] == "UNKNOWN_SERVER":
		registered = false
		await register_server(_reg_info)
	else:
		_fail(res)
		_schedule_hb(30)


## Abmelden: DELETE /v1/servers/{id} mit signiertem Umschlag als Body (Abschnitt 5.3, gültig laut 15.s).
func unregister_server(reason := "shutdown") -> bool:
	_hb_timer.stop()
	var was := registered
	registered = false
	_reg_info = {}
	if not was or server_key == null:
		return false
	var p := {"server_id": server_id, "reason": reason if reason in ["shutdown", "map_end", "other"] else "other"}
	var res := await request("DELETE", "/v1/servers/" + server_id, "",
		make_envelope("DH2/v1/unregister", p, server_key, server_id), 0)
	return bool(res["ok"])


## Rundenbericht (Abschnitt 10.3 / 15.z). report: map, mode, round, started_at, ended_at, partial, result{winner,
## team_score, mission_success?, no_alarm?}, players[{gh,name,team,kills,deaths,assists,score,teamkills,suicides,
## time_s,won,proof, ai_kills?,objectives?,revives?,extracted?,victims?}]. Wiederholung 5/30/120 s.
func report_match(report: Dictionary) -> Dictionary:
	if server_key == null:
		return {}
	var p := {}
	for k in REPORT_KEYS:
		if report.has(k):
			p[k] = report[k].duplicate(true) if report[k] is Dictionary or report[k] is Array else report[k]
	var pls := []
	for pp in report.get("players", []):
		if typeof(pp) != TYPE_DICTIONARY:
			continue
		var q := {}
		for k in PLAYER_KEYS:            # nur bekannte Felder; nie XP/Rang vom Client übernehmen
			if pp.has(k):
				q[k] = pp[k]
		pls.append(q)
	p["players"] = pls.slice(0, 64)
	p["sid"] = server_id
	if not p.has("match_id"):
		p["match_id"] = nonce(16)
	p["build"] = build_info()
	if build_hash != "":
		p["build_hash"] = build_hash
	var res := {}
	for attempt in REPORT_BACKOFF.size() + 1:
		# neuer ts/nonce je Versuch, gleiche match_id (Replay-Schutz zahlt nur einmal aus)
		res = await request("POST", "/v1/matches/report", "",
			make_envelope("DH2/v1/stats", p, server_key, server_id), 0)
		var st := int(res["status"])
		if res["ok"] or (st != 0 and st != 429 and st < 500) or attempt == REPORT_BACKOFF.size():
			break
		await get_tree().create_timer(REPORT_BACKOFF[attempt]).timeout
	if not res["ok"]:
		_fail(res)
		return {}
	var j: Dictionary = res["json"] if typeof(res["json"]) == TYPE_DICTIONARY else {}
	for c in j.get("career", []):
		if typeof(c) == TYPE_DICTIONARY and c.has("gh"):
			var cr = c.get("career", {})
			var rk := int(cr.get("level", -1)) if typeof(cr) == TYPE_DICTIONARY else -1
			_ranks[String(c["gh"])] = {"rank": rk, "career": cr, "at": now()}
	match_reported.emit(j)
	if String(j.get("verdict", "")) == "ACCEPTED":
		_announce_promotions(j.get("career", []))
		await distribute_ranks(true)
	return j


## Beförderungsmeldung an den betroffenen Client (nur angenommene, gewertete Berichte).
func _announce_promotions(career) -> void:
	if typeof(career) != TYPE_ARRAY:
		return
	for c in career:
		if typeof(c) != TYPE_DICTIONARY or not bool(c.get("promoted", false)):
			continue
		var cr = c.get("career", {})
		var lvl := int(cr.get("level", 0)) if typeof(cr) == TYPE_DICTIONARY else 0
		for pid in _peer_gh:
			if String(_peer_gh[pid]) != String(c.get("gh", "")) or lvl <= 0:
				continue
			promotions_sent.append([int(pid), lvl])
			var mp := multiplayer.multiplayer_peer
			if mp != null and multiplayer.is_server() and int(pid) != multiplayer.get_unique_id() \
					and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				_promoted.rpc_id(int(pid), lvl)
			elif int(pid) == 1 or mp == null:
				_promoted(lvl)


## Client: Beförderung (Wert kommt ausschließlich vom Master über den Spielserver).
@rpc("authority", "call_remote", "reliable")
func _promoted(level: int) -> void:
	promoted.emit(level, CAREER.rank_name(level))
	var ev := get_node_or_null("/root/Events")
	if ev and ev.has_method("say"):
		ev.say("%s %s" % [tr("Befördert zu"), tr(CAREER.rank_name(level))], 5.0)


## Spielserver: Spieler-Peer einem Konto zuordnen (nach geprüftem Beitrittsbeleg) und Rang holen.
func set_peer_account(peer_id: int, gh: String) -> void:
	_peer_gh[peer_id] = gh
	_push_rank(peer_id)                # sofort leer (-1) bzw. bekannter Wert, dann nach der Abfrage aktuell
	if is_official_build():
		await fetch_rank(gh)
	_push_rank(peer_id)


## Ränge aller zugeordneten Spieler (neu) holen und an alle verteilen.
func distribute_ranks(fetch := true) -> void:
	for pid in _peer_gh.keys():
		if fetch:
			await fetch_rank(String(_peer_gh[pid]))
		_push_rank(int(pid))


func _push_rank(pid: int) -> void:
	var gh := String(_peer_gh.get(pid, ""))
	var rk := rank_of(gh)
	var mp := multiplayer.multiplayer_peer
	if mp != null and multiplayer.is_server() and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_rank_sync.rpc(pid, rk)
	else:
		_rank_sync(pid, rk)


## Master-Rang an alle (-1 = unbekannt → Feld leer). Kein lokaler Rang online.
@rpc("authority", "call_local", "reliable")
func _rank_sync(pid: int, rank: int) -> void:
	var n := get_node_or_null("/root/Net")
	if n and n.players.has(pid):
		n.players[pid]["master_rank"] = rank
	ranks_updated.emit()
