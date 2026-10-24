extends Node
## Mehrspieler im LAN – OHNE DirectPlay (Vorgabe Auftraggeber): Godot-ENet (UDP, Port 27100) mit der
## High-Level-API (RPC), LAN-Serversuche per eigenem UDP-Broadcast (Port 27101).
##
## Server-Autorität: Der Server (Spieler 1) berechnet Treffer, Schaden, Tod, Punkte, Respawn und Spielende.
## Jeder Spieler steuert seinen eigenen Soldaten und sendet dessen Zustand (20 Hz) sowie Aktionen
## (Schuss, Rakete, Granate, Messer, Ladung) – alle Rechner stellen diese dar, nur der Server wertet aus.
## Alle RPCs liegen hier (Autoload /root/Net), damit die Knotenpfade auf allen Rechnern gleich sind.

## Original-Standardport 11001 (0x2AF9, re_notes_multiplayer §2.2), Menübereich 1024–65530 (T2378).
## Server-Abfrage (Name/Karte/Spieler/Ping für Favoriten und Internet) per UDP auf Port + 1.
const PORT := 11001
const PORT_MIN := 1024
const PORT_MAX := 65530
const DISCOVERY_PORT := 27101
const PROTOCOL := "DH2-LAN-3"         ## 3: Respawn per Feuertaste, Ränge, Spiel-Info-Daten (15.10.2026)
const QUERY_TAG := "DH2-QUERY"
const SYNC_INTERVAL := 0.05
## Spielstile des Originals (docs/re_notes_multiplayer.md): DEATHMATCH (2891), BESETZUNG (2892),
## HD2-AUFGABEN (2893); Team-Deathmatch ist eine Ergänzung für die Arena-Karten.
enum Mode { DEATHMATCH, TEAM_DEATHMATCH, OCCUPATION, OBJECTIVES }
const MODE_NAMES := ["DEATHMATCH", "TEAM-DEATHMATCH", "BESETZUNG", "HD2-AUFGABEN"]
## Punkte laut Original: Abschuss +1, Selbsttötung −1, Teamkill −10 (3 Teamkills = Rauswurf);
## Besetzung: +2 je Anwesendem beim Neutralisieren, +5 beim Einnehmen, Team +0,0125/s je Zone
const PTS_KILL := 1
const PTS_SUICIDE := -1
const PTS_TEAMKILL := -10
const TEAMKILL_KICK := 3
const SPAWN_PROTECT_S := 5.0          ## Original-Standard spawnprotection (alle Stile 5 s)
const ZONE_NEUTRALIZE_PTS := 2
const ZONE_CAPTURE_PTS := 5
const ZONE_TEAM_PTS_PER_S := 0.0125
const OBJ_LATE_JOIN_S := 30.0
const END_PAUSE_S := 5.0              ## Original: 5 s nach Rundenende, dann nächste Runde/Karte (0x69AF10)
const ZONE_START_DELAY_S := 5.0       ## Original: Zoneneinnahme erst nach Aufwärmzeit + 5 s

## Server-Regeln (Server-Config +0x228, Konsolen-Schlüsselwörter aus HD2DS.exe) mit Standardwerten je Stil
## (re_notes_multiplayer §2.2: Spalten DM / Besetzung / Aufgaben). Schlüssel: Netz-Einstellung → Konsole.
const RULE_KEYS := {
	"max_players": "maxclients", "score_limit": "pointlimit", "time_limit_min": "roundlimit",
	"round_count": "roundcount", "warmup_s": "warmup", "respawn_s": "respawntime", "allow_respawn": "allowrespawn",
	"friendly_fire": "friendlyfire", "team_balance": "autoteambalance", "third_person": "3rdpersonview",
	"spawn_protect_s": "spawnprotection", "inverse_damage": "inversedamage", "falling_damage": "fallingdmg",
	"flood_protect": "floodprotect", "allow_vehicles": "allowvehicles", "bots_per_team": "bots",
	# ServerLauncher „Advanced“ (T2036–2040), Konsole HD2DS/hd2.exe 0x742480 (Fälle 0x34/0x35/0x37):
	# maxping [ms], maxfreq [Hz], maxinactivity [s] (intern ms, Ausgabe /1000), autorestart
	"max_ping": "maxping", "max_freq": "maxfreq", "max_inactivity": "maxinactivity", "autorestart": "autorestart",
	# Ergänzung (kein Original-Schlüssel): Namen über Spielern / Trefferanzeige erlauben (src/ui/mp_feedback.gd)
	"show_names": "shownames", "hit_indicator": "hitindicator", "hurt_indicator": "hurtindicator", "kill_cam": "killcam",
}
## Wertebereiche: Menü (0x629EE0) bzw. Konsole; bots = Ergänzung (KI-Soldaten je Team); 0 = „No limit“ (T2010)
const RULE_RANGE := {
	"max_players": [2, 32], "score_limit": [0, 999], "time_limit_min": [0, 99], "round_count": [1, 999],
	"warmup_s": [0, 99], "respawn_s": [3, 99], "spawn_protect_s": [0, 15], "inverse_damage": [0, 999],
	"bots_per_team": [0, 16], "max_ping": [0, 9999], "max_freq": [0, 100], "max_inactivity": [0, 3600],
}
## Server-Grenzen (Launcher-Standard „No limit“ = 0): Rauswurf erst, wenn der Ping so lange ununterbrochen über
## maxping liegt (Annahme, Original-Prüfung nicht dekodiert); Flood-Schutz: höchstens FLOOD_MSGS Chatzeilen in
## FLOOD_WINDOW_S, sonst FLOOD_MUTE_S stumm (Annahme)
const PING_KICK_GRACE_S := 10.0
const FLOOD_MSGS := 4
const FLOOD_WINDOW_S := 3.0
const FLOOD_MUTE_S := 10.0
## Wiedereinstieg (Original 0x59FEC6: Client fordert nach respawntime + 3 s neu an): nach Ablauf der Respawn-Zeit
## „FEUER DRÜCKEN FÜR RESPAWN“ (T7406), Feuer = sofort, sonst automatisch nach weiteren 3 s
const RESPAWN_AUTO_S := 3.0
## MP-Rang (hd2.exe 0x72FD60, Schwellen 0x844F94): min(⌊Punkte/10⌋, 7), Meldungen T8900–8903
const RANK_STEP := 10
const RANK_MAX := 7
const STYLE_DEFAULTS := [
	{"max_players": 32, "score_limit": 20, "time_limit_min": 0, "round_count": 3, "warmup_s": 10, "respawn_s": 5,
		"allow_respawn": true, "friendly_fire": false, "team_balance": false, "third_person": false, "spawn_protect_s": 5,
		"inverse_damage": 100, "falling_damage": true, "flood_protect": true, "allow_vehicles": true},
	{"max_players": 32, "score_limit": 0, "time_limit_min": 30, "round_count": 3, "warmup_s": 10, "respawn_s": 30,
		"allow_respawn": true, "friendly_fire": true, "team_balance": true, "third_person": false, "spawn_protect_s": 5,
		"inverse_damage": 100, "falling_damage": true, "flood_protect": true, "allow_vehicles": true},
	{"max_players": 32, "score_limit": 0, "time_limit_min": 5, "round_count": 3, "warmup_s": 10, "respawn_s": 0,
		"allow_respawn": false, "friendly_fire": true, "team_balance": true, "third_person": false, "spawn_protect_s": 5,
		"inverse_damage": 100, "falling_damage": true, "flood_protect": true, "allow_vehicles": true},
]


## Standardwerte für einen Spielstil (Team-Deathmatch wie Deathmatch, Arena-Ergänzung)
static func style_defaults(m: int) -> Dictionary:
	var col := 0 if m in [Mode.DEATHMATCH, Mode.TEAM_DEATHMATCH] else (1 if m == Mode.OCCUPATION else 2)
	var d := (STYLE_DEFAULTS[col] as Dictionary).duplicate()
	d.merge(LIMIT_DEFAULTS)
	d.merge(FEEDBACK_DEFAULTS)
	d["kill_cam"] = m == Mode.DEATHMATCH          # Kill-Cam (Ergänzung): Standard nur im Deathmatch an
	return d


## Ergänzung Trefferfeedback/Namen (alle Stile an; Spieler kann es zusätzlich in den Optionen abschalten)
## hit_indicator = Trefferanzeige für den Schützen (Hitmarker/Meldung/Klang), hurt_indicator = Richtungsbogen beim Getroffenen
const FEEDBACK_DEFAULTS := {"show_names": true, "hit_indicator": true, "hurt_indicator": true}


## Launcher-Felder „Max ping/Max frequency/Max inactivity/Autorestart“: Standard „No limit“ bzw. aus (alle Stile)
const LIMIT_DEFAULTS := {"max_ping": 0, "max_freq": 0, "max_inactivity": 0, "autorestart": false}


## Server-Regel mit Standard des aktuellen Stils
func rule(key: String) -> Variant:
	if settings.has(key):
		return settings[key]
	return style_defaults(mode()).get(key, 0)


## Originaltext (orig_cache/texts_german.json) mit Ersatztext
static func tx(id: int, fb := "") -> String:
	return SAS.text(id, fb).strip_edges()

signal servers_updated
signal players_updated
signal status_changed(text: String)

var is_online := false
var settings := {}            ## name, map, mode, max_players, time_limit_min, score_limit, respawn_s, friendly_fire, password
var players := {}             ## Peer-ID -> {name, team, kills, deaths, score}
var servers := {}             ## "ip:port" -> Serverinfo (+ ip, seen)
var team_score := [0.0, 0.0]      ## Index = Soldier-Team (0 Alliierte, 1 Achse)
var zone_owner: Array = []          ## Besetzung: Besitzer je Zone (Soldier-Team, −1 neutral)
var zone_progress: Array = []       ## Einnahmefortschritt (s) und angreifendes Team
var zone_attacker: Array = []
var obj_done: Array = []            ## HD2-Aufgaben: erledigte Aufgaben-Indizes
var last_error := ""
var match_over := false
var local_name := "Spieler"
var dedicated := false        ## Dedizierter Server (HD2DS): kein eigener Spieler (Peer 1 ohne Soldat)
## Spielzustand wie Original (+0x88): 3 Aufwärmen, 0 läuft, 1 Team gewonnen, 2 Rundenende
enum State { RUNNING = 0, WON = 1, ENDED = 2, WARMUP = 3 }
var game_state := 0
var round_no := 1             ## laufende Runde auf der aktuellen Karte (bis round_count)
var team_wins := [0, 0]       ## Siege je Team (Soldier-Team-Index), Rücksetzen beim Kartenwechsel
var hud_info := {}            ## vom Server (2 Hz): Zustand, Zeiten, Runde, Welle, Abstimmung
var public_ip := ""           ## Internet-Server: öffentliche IP (UPnP)
var upnp_status := ""
var respawn_at := 0           ## Client: Zeitpunkt (ms) des eigenen Wiedereinstiegs (0 = keiner)
var _warm_t := 0.0
var _info_t := 0.0
var voice: VoiceChat
var chat_focus := false       ## Chat-/Konsolen-Eingabe offen (Push-to-talk und Steuerung ruhen)

var _peer: ENetMultiplayerPeer
var _bc: PacketPeerUDP
var _bc_t := 0.0
var _listen: PacketPeerUDP
var _join_pw := ""
var _sync_t := 0.0
var _soldiers := {}           ## Peer-ID -> Soldier (aktuell)
var _gen := {}                ## Peer-ID -> laufende Nummer (Knotennamen beim Respawn)
var _respawn := {}            ## Peer-ID -> Restsekunden
var _hp_sent := {}
var _match_t := 0.0
var _end_t := 0.0
var _last_vehicle := ""
var _last_seat := -1
var _board: CanvasLayer
var _board_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)
	load_favorites()
	load_filter()
	voice = VoiceChat.new()
	voice.name = "Voice"
	add_child(voice)
	Events.soldier_damaged.connect(_on_soldier_damaged)      # Trefferfeedback (nur Server wertet aus)
	_check_dedicated_cli()


func is_authority() -> bool:
	return not is_online or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online else 1


func mode() -> int:
	return int(settings.get("mode", Mode.DEATHMATCH))


# --- Server / Client ---------------------------------------------------------------

## Server starten. cfg: name, map, mode, password, port, internet, dedicated, map_list, admin_login, admin_pass
## und die Regeln aus RULE_KEYS (fehlende = Original-Standard des Stils).
func host(cfg: Dictionary) -> bool:
	leave(false)
	_peer = ENetMultiplayerPeer.new()
	var port := clampi(int(cfg.get("port", PORT)), PORT_MIN, PORT_MAX)
	var err := _peer.create_server(port, clampi(int(cfg.get("max_players", 8)), 2, 32))   # Original-Servermenü: 2–32
	if err != OK:
		last_error = "Server konnte nicht gestartet werden (Port %d belegt?)" % port
		return false
	multiplayer.multiplayer_peer = _peer
	is_online = true
	settings = cfg.duplicate(true)
	settings["port"] = port
	dedicated = bool(cfg.get("dedicated", false))
	var ml: Array = settings.get("map_list", [])
	if ml.is_empty() or not ml.has(String(settings["map"])):
		ml = [String(settings["map"])] + ml
	settings["map_list"] = ml
	round_no = 1
	team_wins = [0, 0]
	var my_team: int = local_team if local_team in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS] and mode() != Mode.DEATHMATCH else _pick_team()
	players = {} if dedicated else {1: _new_player(local_name, my_team, local_class)}
	if not dedicated:
		players[1]["admin"] = true          # wer den Server im Spiel erstellt, ist Admin
		players[1]["figure"] = local_figure  # Figurwahl aus dem SPIELER-SETUP
		if not local_loadout.is_empty():
			players[1]["loadout"] = MpLoadout.sanitize(local_loadout)   # Prüfung beim Spawn (Karte geladen)
	_bc = PacketPeerUDP.new()
	_bc.set_broadcast_enabled(true)
	_bc.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_query = PacketPeerUDP.new()
	if _query.bind(port + 1) != OK:
		_query = null
	if bool(settings.get("internet", false)):
		_upnp_open(port)
	_begin_match()
	return true


func join(ip: String, port: int = PORT, password := "") -> bool:
	leave(false)
	ip = ip.strip_edges()
	if ip.contains(":") and ip.count(":") == 1:          # „host:port“
		port = int(ip.get_slice(":", 1))
		ip = ip.get_slice(":", 0)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		last_error = "Verbindung nicht möglich (%s)" % error_string(err)
		return false
	multiplayer.multiplayer_peer = _peer
	is_online = true
	_join_pw = password
	status_changed.emit("Verbinde mit %s:%d …" % [ip, port])
	return true


## Verbindung beenden. to_menu: zurück ins Hauptmenü
func leave(to_menu := true) -> void:
	if _peer:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_bc = null
	if _query:
		_query.close()
	_query = null
	_upnp_close()
	is_online = false
	players.clear()
	_soldiers.clear()
	_respawn.clear()
	match_over = false
	dedicated = false
	game_state = State.RUNNING
	hud_info = {}
	respawn_at = 0
	_vote = {}
	chat_log.clear()
	kill_feed.clear()
	hit_log.clear()
	hurt_log.clear()
	chat_focus = false
	if voice:
		voice.reset()
	_show_board(false)
	if to_menu and Game.current_mission():
		Game.return_to_menu()


func _new_player(n: String, team: int, cls := 2) -> Dictionary:
	return {"name": n, "team": team, "kills": 0, "deaths": 0, "score": 0, "teamkills": 0, "cls": cls, "spectator": false}


## Team-Deathmatch: kleineres Team; Deathmatch: eigene Seite je Spieler (für Freund/Feind-Logik)
func _pick_team() -> int:
	if mode() == Mode.DEATHMATCH:
		return 10 + players.size()
	# Original (0x727800/0x7301C0): Verhältnis aus BALANCED der Karte (z. B. Africa1 60/40 Alliierte/Achse)
	var na := _team_humans(Soldier.TEAM_ALLIED)
	var nx := _team_humans(Soldier.TEAM_AXIS)
	var r := balance_ratio()
	var da := absf(na + 1 - r * nx)
	var dx := absf(na - r * (nx + 1))
	return Soldier.TEAM_ALLIED if da <= dx else Soldier.TEAM_AXIS


## BALANCED-Verhältnis Alliierte/Achse der Karte (Standard 50/50)
func balance_ratio() -> float:
	var m = Game.current_mission()
	var mp = m.get("mp") if m else null
	var b = null
	if mp is Dictionary and not (mp.get("game_styles", []) as Array).is_empty():
		b = mp["game_styles"][0].get("balanced")
	if b is Dictionary and float(b.get("axis", 0)) > 0.0:
		return float(b.get("allied", 50)) / float(b["axis"])
	return 1.0


## Teamausgleich verletzt? (Original: |n_A − (b_A/b_B)·n_B| ≥ 1,5)
func _unbalanced(na: int, nx: int) -> bool:
	return absf(na - balance_ratio() * nx) >= 1.5


## Menschliche Spieler (ohne KI-Soldaten)
func humans() -> int:
	var n := 0
	for p in players.values():
		if not bool(p.get("bot", false)):
			n += 1
	return n


func team_mode() -> bool:
	return mode() != Mode.DEATHMATCH


## Freund-Feind-Schaden (Server-Option, Standard aus): Treffer von Teamkameraden wirken nicht
func friendly_fire() -> bool:
	return not team_mode() or bool(rule("friendly_fire"))


func third_person_allowed() -> bool:
	return not is_online or bool(rule("third_person"))


func vehicles_allowed() -> bool:
	return not is_online or bool(rule("allow_vehicles"))


## Fallschaden (Server-Regel fallingdmg; nur Mehrspieler). Höhe des Schadens = Annahme (Soldier).
func fall_damage(s: Soldier, amount: float) -> void:
	if not is_online or not bool(rule("falling_damage")) or amount <= 0.0:
		return
	if multiplayer.is_server():
		hit_source = "fall"
		s.apply_hit(amount, &"legs", s, Vector3.DOWN)
		hit_source = ""
	elif s == _soldiers.get(my_id()):
		_fall_req.rpc_id(1, amount)


@rpc("any_peer", "call_remote", "reliable")
func _fall_req(amount: float) -> void:
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
	if multiplayer.is_server() and is_instance_valid(s) and s.alive and bool(rule("falling_damage")):
		hit_source = "fall"
		s.apply_hit(clampf(amount, 0.0, 500.0), &"legs", s, Vector3.DOWN)
		hit_source = ""


## Umgekehrter Schaden (inversedamage %, Original-Standard 100): Schütze erleidet bei Teamtreffern zusätzlich
## diesen Anteil selbst (re_notes_multiplayer §1.6 [P]). Aufruf aus Soldier.apply_hit (nur Server).
func inverse_damage(attacker: Soldier, amount: float) -> void:
	var pct := float(rule("inverse_damage"))
	if pct > 0.0 and is_instance_valid(attacker) and attacker.alive:
		attacker.apply_hit(amount * pct / 100.0, &"torso", attacker, Vector3.ZERO)


func _on_connected() -> void:
	_relax_timeout(1)
	print("NET: verbunden, melde an als ", local_name)
	_register.rpc_id(1, local_name, _join_pw, PROTOCOL, local_class, local_team)
	if local_figure != "":
		_figure_req.rpc_id(1, local_figure)      # Figurwahl (SPIELER-SETUP), gleicher Kanal → nach der Anmeldung
	if not local_loadout.is_empty():
		_loadout_req.rpc_id(1, local_loadout)    # Einzel-Ausrüstung (nach Figur: Traglast der Figur)


func _on_connection_failed() -> void:
	last_error = "Verbindung fehlgeschlagen."
	leave(false)
	status_changed.emit(last_error)


func _on_server_lost() -> void:
	last_error = "Verbindung zum Server verloren."
	leave(true)
	status_changed.emit(last_error)


## Kartenladen blockiert ein Spiel bis zu Minuten: ENet-Zeitlimit großzügig (sonst Trennung beim Laden)
const PEER_TIMEOUT_MS := 300000


func _relax_timeout(id: int) -> void:
	if _peer:
		var pp := _peer.get_peer(id)
		if pp:
			pp.set_timeout(PEER_TIMEOUT_MS, PEER_TIMEOUT_MS, PEER_TIMEOUT_MS)


func _on_peer_connected(id: int) -> void:
	_relax_timeout(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("NET: Spieler ", id, " getrennt")
	if players.has(id):
		Events.say("%s hat das Spiel verlassen." % players[id]["name"], 3.0)
	players.erase(id)
	for d in [_active_ms, _ready_peers, _ping_over, _chat_times, _muted_until, _last_st_ms, ping_override]:
		(d as Dictionary).erase(id)
	_remove_player.rpc(id)
	_players.rpc(players)


var local_team := -1          ## gewünschte Seite aus dem SPIELER-SETUP (−1 automatisch)
var local_class := 2         ## gewünschte Klasse (0 MG-, 1 Scharf-, 2 Gewehr-, 3 Grenadier, 4 Sturmschütze)
var local_figure := ""       ## Figurwahl SPIELER-SETUP: "" Standard, "hero:axis"/"hero:allied", "mp:<HumanStore 30–56>"
var local_loadout := {}      ## Einzel-Ausrüstung SPIELER-SETUP (SAS-Inventar), {} = Klassen-Vorlage


@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, password: String, proto: String, cls: int = 2, team_pref := -1) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if proto != PROTOCOL:
		reason = "Andere Spielversion."
	elif String(settings.get("password", "")) != "" and password != String(settings["password"]):
		reason = "Falsches Passwort."
	elif humans() >= int(settings.get("max_players", 8)):          # KI-Soldaten belegen keine Spielerplätze
		reason = "Server ist voll."
	if reason != "":
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(1.0).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	players[id] = _new_player(pname.substr(0, 24), _pick_team(), cls)
	if team_pref in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS] and team_mode():
		var auto_team := int(players[id]["team"])
		players[id]["team"] = -1
		players[id]["team"] = team_pref if not _server_set_team_check(team_pref) else auto_team
	# HD2-Aufgaben: kein Wiedereinstieg; wer nach 30 s beitritt, schaut zu (Original)
	# (Original 0x69E340: Rundenzeit > 30 s und kein „Respawn erlauben“ → Zuschauer, Text 20311)
	players[id]["spectator"] = not bool(rule("allow_respawn")) and game_state != State.WARMUP and _match_t > OBJ_LATE_JOIN_S
	print("NET: Spieler ", id, " angemeldet: ", pname)
	_players.rpc(players)
	Events.say("%s ist beigetreten." % pname, 3.0)
	_enter_match.rpc_id(id, public_settings(), team_score)
	if bool(players[id]["spectator"]):
		_tell(id, tx(20311, "Runde hat bereits begonnen - schaltet zum Zuschauermodus"))


## Einstellungen ohne Geheimnisse (Passwort, Admin-Zugang) für die Clients
func public_settings() -> Dictionary:
	var s := settings.duplicate(true)
	s["has_password"] = String(s.get("password", "")) != ""
	for k in ["password", "admin_login", "admin_pass"]:
		s.erase(k)
	return s


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	last_error = "Abgewiesen: " + reason
	status_changed.emit(last_error)
	leave(Game.current_mission() != null)       # im Spiel rausgeworfen (Admin, Ping, Inaktivität) → Hauptmenü


@rpc("authority", "call_remote", "reliable")
func _enter_match(cfg: Dictionary, scores: Array) -> void:
	print("NET: betrete Runde, Karte ", cfg.get("map"))
	settings = cfg
	team_score = scores
	match_over = false
	_soldiers.clear()
	Game.start_mission(String(cfg["map"]))


@rpc("authority", "call_local", "reliable")
func _players(p: Dictionary) -> void:
	players = p
	players_updated.emit()


# --- Chat, Team-/Klassenwahl (Schnittstelle auch für den Spieler-Setup-Bildschirm) -----------------
## Original: „Nachricht an alle“ (T2853) / „Nachricht ans Team“ (T2854). Server verteilt; Team-Nachrichten
## nur an Spieler desselben Teams. Text beginnend mit „/“ = Konsolenbefehl (Admin, s. server_command).
signal chat_received(sender_name: String, text: String, team_only: bool)
const CHAT_MAX := 120


func send_chat(text: String, team_only := false) -> void:
	text = text.strip_edges().substr(0, CHAT_MAX)
	if text == "":
		return
	if not is_online:
		chat_received.emit(local_name, text, team_only)
		return
	if multiplayer.is_server():
		_server_chat(1, text, team_only)
	else:
		_chat_req.rpc_id(1, text, team_only)


@rpc("any_peer", "call_remote", "reliable")
func _chat_req(text: String, team_only: bool) -> void:
	if multiplayer.is_server():
		_touch(multiplayer.get_remote_sender_id())
		_server_chat(multiplayer.get_remote_sender_id(), text.substr(0, CHAT_MAX), team_only)


func _server_chat(from: int, text: String, team_only: bool) -> void:
	if not players.has(from) and from != 0:
		return
	if text.begins_with("/"):
		_chat_command(from, text.substr(1))
		return
	if _flooding(from):
		_tell(from, "%s: Nachricht nicht gesendet." % tx(8922, "floodprotect"))
		return
	var nm := String(players[from]["name"]) if players.has(from) else "ADMIN"     # Original „ADMIN: %s“
	var team := int(players[from]["team"]) if players.has(from) else -1
	for id in players.keys():
		if int(id) <= 0:
			continue
		if team_only and team_mode() and int(players[id]["team"]) != team:
			continue
		if int(id) == 1:
			_chat(nm, text, team_only)
		else:
			_chat.rpc_id(int(id), nm, text, team_only)
	if dedicated:
		_chat(nm, text, team_only)


@rpc("authority", "call_remote", "reliable")
func _chat(sender_name: String, text: String, team_only: bool) -> void:
	chat_log.append({"name": sender_name, "text": text, "team": team_only})
	if chat_log.size() > 50:
		chat_log.pop_front()
	chat_received.emit(sender_name, text, team_only)
	if dedicated:
		print("CHAT%s %s: %s" % [" (Team)" if team_only else "", sender_name, text])


## Nachricht nur an einen Spieler (Serverantworten auf Befehle)
func _tell(to: int, text: String) -> void:
	if to == 1 and not dedicated:
		_chat("Server", text, false)
	elif to > 1:
		_chat.rpc_id(to, "Server", text, false)
	else:
		print("SERVER: ", text)


var chat_log: Array = []


## Chat-Befehl („/befehl …“): Konsolenbefehle; Admin-Befehle nur nach Admin-Login
func _chat_command(from: int, line: String) -> void:
	var r := server_command(line, from)
	if r != "":
		_tell(from, r)


## Eingabe der Spiel-Konsole (Taste ^, Original „KONSOLE“ 2852): Zeile an den Server; Antwort per Chat „Server“
func console_command(line: String) -> void:
	line = line.strip_edges()
	if line.get_slice(" ", 0).to_lower() in ["fps", "showfps"]:
		# lokaler Befehl (kein Serverbefehl): FPS-Anzeige „fps“ umschalten bzw. „fps 0/1“
		var a: String = line.get_slice(" ", 1).to_lower() if line.contains(" ") else ""
		Settings.show_fps = (a in ["1", "on", "true", "an"]) if a != "" else not Settings.show_fps
		Settings.save_settings()
		Settings.changed.emit()
		_chat("Konsole", "FPS-Anzeige %s" % ("an" if Settings.show_fps else "aus"), false)
		return
	if line == "" or not is_online:
		return
	if multiplayer.is_server():
		var r := server_command(line, 0 if dedicated else 1)
		if r != "":
			_chat("Server", r, false)
	else:
		_console_req.rpc_id(1, line)


@rpc("any_peer", "call_remote", "reliable")
func _console_req(line: String) -> void:
	if multiplayer.is_server():
		_touch(multiplayer.get_remote_sender_id())
		_chat_command(multiplayer.get_remote_sender_id(), line.substr(0, 200))


## Teamwahl (Server prüft; Teamausgleich: kein Wechsel ins größere Team)
func request_team(team: int) -> void:
	if not is_online:
		return
	if multiplayer.is_server():
		_server_set_team(1, team)
	else:
		_team_req.rpc_id(1, team)


func request_class(cls: int) -> void:
	local_class = cls
	if not is_online:
		return
	if multiplayer.is_server():
		_server_set_class(1, cls)
	else:
		_class_req.rpc_id(1, cls)


## Einzel-Ausrüstung aus dem SPIELER-SETUP (SAS-Inventarformat, MpLoadout); leer = Klassen-Vorlage. Der Server prüft
## (erlaubt/Lager, Traglast, Plätze) und rüstet ab dem nächsten (Wieder-)Einstieg damit aus.
func request_loadout(inv: Dictionary) -> void:
	local_loadout = MpLoadout.sanitize(inv) if not inv.is_empty() else {}
	if not is_online:
		return
	if multiplayer.is_server():
		_server_set_loadout(1, local_loadout)
	else:
		_loadout_req.rpc_id(1, local_loadout)


@rpc("any_peer", "call_remote", "reliable")
func _loadout_req(inv: Dictionary) -> void:
	if multiplayer.is_server():
		_touch(multiplayer.get_remote_sender_id())
		_server_set_loadout(multiplayer.get_remote_sender_id(), inv)


## Freigabeliste für Ausrüstungsprüfungen: geladene Karte, sonst mp.json der eingestellten Karte
func loadout_allowed() -> Array:
	if Game.current_mission() != null or not is_online:
		return _current_allowed()
	return MpLoadout.map_allowed(String(settings.get("map", "")))


## Fehlertext (leer = gültig) der Ausrüstung eines Spielers für seine (nächste) Seite
func loadout_error(id: int, inv: Dictionary) -> String:
	var p: Dictionary = players.get(id, {})
	var team := int(p.get("next_team", p.get("team", 0)))
	var side := "axis" if team == Soldier.TEAM_AXIS else "allied"
	var style := MpLoadout.map_style(String(settings.get("map", "")))
	var heads := MpLoadout.heads_for(inv, style.get("presets", []), side)
	return MpLoadout.check(inv, loadout_allowed(), team, MpLoadout.strength_of(String(p.get("figure", ""))), heads)


func _server_set_loadout(id: int, inv: Dictionary) -> void:
	if not players.has(id) or bool(players[id].get("bot", false)):
		return
	var clean := MpLoadout.sanitize(inv)
	if MpLoadout.is_empty(clean):
		players[id].erase("loadout")
		_players.rpc(players)
		return
	var err := loadout_error(id, clean)
	if err != "":
		_tell(id, err)
		return
	players[id]["loadout"] = clean
	_players.rpc(players)


## Spawnzone festlegen (Original „SPAWN-ZONE FESTLEGEN“ T2507/2528): gilt beim nächsten Spawn, wenn die
## Zone dann dem eigenen Team gehört (sonst frontnächste eigene Zone)
func request_zone(zone: int) -> void:
	if not is_online:
		return
	if players.has(my_id()):
		players[my_id()]["zone"] = zone
	if multiplayer.is_server():
		if players.has(1):
			players[1]["zone"] = zone
	else:
		_zone_req.rpc_id(1, zone)


@rpc("any_peer", "call_remote", "reliable")
func _zone_req(zone: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(id):
		players[id]["zone"] = zone


@rpc("any_peer", "call_remote", "reliable")
func _team_req(team: int) -> void:
	if multiplayer.is_server():
		_server_set_team(multiplayer.get_remote_sender_id(), team)


@rpc("any_peer", "call_remote", "reliable")
func _class_req(cls: int) -> void:
	if multiplayer.is_server():
		_server_set_class(multiplayer.get_remote_sender_id(), cls)


## Ergebnis: true = gewechselt
func _server_set_team(id: int, team: int) -> bool:
	if not players.has(id) or not team_mode() or not team in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
		return false
	var cur := int(players[id].get("next_team", players[id]["team"]))
	if cur == team:
		return true
	if bool(players[id].get("bot", false)):
		return false
	var na := _team_humans(Soldier.TEAM_ALLIED) + (1 if team == Soldier.TEAM_ALLIED else -1)
	var nx := _team_humans(Soldier.TEAM_AXIS) + (1 if team == Soldier.TEAM_AXIS else -1)
	if bool(rule("team_balance")) and _unbalanced(na, nx) and absf(na - balance_ratio() * nx) > \
			absf(_team_humans(Soldier.TEAM_ALLIED) - balance_ratio() * _team_humans(Soldier.TEAM_AXIS)):
		_tell(id, "%s: Wechsel nicht möglich." % tx(2372, "AUTO. TEAMAUSGLEICH"))
		return false
	# Wirkt ab dem nächsten Wiedereinstieg (SPIELER-SETUP im Spiel); ohne lebenden Soldaten sofort
	var s: Soldier = _soldiers.get(id)
	if is_instance_valid(s) and s.alive and Game.current_mission():
		players[id]["next_team"] = team
	else:
		players[id]["team"] = team
		players[id].erase("next_team")
	_players.rpc(players)
	_tell(id, "Seite: %s (ab dem nächsten Wiedereinstieg)" % team_name(team))
	return true


## Gewünschte Seite beim Beitritt (SPIELER-SETUP vor dem Beitritt): true = verletzt den Teamausgleich
func _server_set_team_check(team: int) -> bool:
	if not bool(rule("team_balance")):
		return false
	var na := _team_humans(Soldier.TEAM_ALLIED) + (1 if team == Soldier.TEAM_ALLIED else 0)
	var nx := _team_humans(Soldier.TEAM_AXIS) + (1 if team == Soldier.TEAM_AXIS else 0)
	return _unbalanced(na, nx)


func _server_set_class(id: int, cls: int) -> void:
	if not players.has(id):
		return
	players[id]["cls"] = clampi(cls, 0, CLASS_NAMES.size() - 1)
	_players.rpc(players)


# --- Server-Konsole (HD2DS „HD2 console“), Admin, Rauswurf, Abstimmungen ------------------------------
## Schlüsselwörter wie im Original (HD2DS.exe 0x486F78 ff.): Regeln (RULE_KEYS), mapname, removemap, style,
## domain, sessionname, help, exec, server, dedicated, vote, voteyes, listplayers, kickplayer, nextmap, restart,
## port, password, quit, voicechat, listmaps, adminpass, adminlogin, svcmd, say, sayteam.
## Ergänzungen: status, map <karte>, kick (= kickplayer), bots <n> (KI-Soldaten je Team), teamdeathmatch.
## from: 0 = Server-Konsole (alle Rechte), sonst Peer-ID (Admin-Befehle erst nach „adminlogin <name> <passwort>“).
const VOTE_RULES := {"maxclients": 8910, "pointlimit": 8911, "roundlimit": 8912, "roundcount": 8913, "warmup": 8914,
	"respawntime": 8915, "allowrespawn": 8916, "friendlyfire": 8917, "autoteambalance": 8918, "spawnprotection": 8919,
	"3rdpersonview": 8920, "inversedamage": 8921, "floodprotect": 8922, "fallingdmg": 8923}
const VOTE_TIME_S := 30.0       ## Annahme (Originaldauer nicht dekodiert)
const STYLE_WORDS := {"deathmatch": Mode.DEATHMATCH, "teamdeathmatch": Mode.TEAM_DEATHMATCH,
	"occupation": Mode.OCCUPATION, "objectives": Mode.OBJECTIVES}
var _cfg_pending := {}          ## Konsole vor dem Start („server“): Einstellungen
var _vote := {}


func _is_admin(from: int) -> bool:
	return from == 0 or bool(players.get(from, {}).get("admin", false))


func _cfg() -> Dictionary:
	return settings if is_online else _cfg_pending


## Konsolenzeile ausführen; Rückgabe = Ausgabe
func server_command(line: String, from := 0) -> String:
	line = line.strip_edges()
	if line == "" or line.begins_with(";") or line.begins_with("#") or line.begins_with("//"):
		return ""
	var sp := line.find(" ")
	var kw := (line if sp < 0 else line.substr(0, sp)).to_lower()
	var arg := "" if sp < 0 else line.substr(sp + 1).strip_edges()
	if arg.length() >= 2 and arg.begins_with("\"") and arg.ends_with("\""):
		arg = arg.substr(1, arg.length() - 2)
	var c := _cfg()
	# --- für alle Spieler ---
	match kw:
		"help":
			return "Console keywords: " + ", ".join(PackedStringArray(["help", "status", "listplayers", "listmaps", "say", "sayteam",
				"vote", "voteyes", "adminlogin", "svcmd", "kickplayer", "nextmap", "restart", "map", "mapname", "removemap", "style",
				"domain", "sessionname", "port", "password", "voicechat", "adminpass", "exec", "server", "dedicated", "quit"]
				+ RULE_KEYS.values()))
		"say", "sayteam":
			if from == 0:
				_server_chat(0, arg, kw == "sayteam")
			else:
				_server_chat(from, arg, kw == "sayteam")
			return ""
		"listplayers", "status":
			return _status_text(kw == "status")
		"listmaps":
			var out: PackedStringArray = []
			for m in [Mode.DEATHMATCH, Mode.OCCUPATION, Mode.OBJECTIVES]:
				out.append(["Deathmatch maps:", "", "Occupation maps:", "Objectives maps:"][m])
				for id in Game.MP_MAPS:
					if Game.MISSIONS[id].get("mp_mode", Mode.DEATHMATCH) == m or (m == Mode.DEATHMATCH and Game.MISSIONS[id].get("mp_mode") == null):
						out.append("  %s  (%s)" % [id, Game.MISSIONS[id]["title"]])
			return "\n".join(out)
		"vote":
			return start_vote(from, arg)
		"voteyes":
			return vote_yes(from)
		"adminlogin":
			if from != 0:
				var parts := arg.split(" ", false)
				var pw := String(parts[parts.size() - 1]) if parts.size() > 0 else ""
				var nm := String(parts[0]) if parts.size() > 1 else String(settings.get("admin_login", ""))
				if String(settings.get("admin_pass", "")) != "" and pw == String(settings["admin_pass"]) \
						and nm == String(settings.get("admin_login", "")):
					players[from]["admin"] = true
					print("NET: Admin-Rechte für ", players[from]["name"])
					return "Admin rights granted!"
				return "Incorrect admin password!"
		"svcmd":
			return server_command(arg, from)
	if not _is_admin(from):
		return "You don't have admin rights!" if kw in ["adminpass", "svcmd", "kickplayer", "kick", "nextmap", "restart",
			"map", "mapname", "removemap", "style", "domain", "sessionname", "port", "password", "voicechat", "exec", "server",
			"dedicated", "quit", "bots"] or RULE_KEYS.values().has(kw) else "unknown command"
	# --- Admin / Server-Konsole ---
	for key in RULE_KEYS:
		if RULE_KEYS[key] == kw:
			if arg == "":
				return "%s = %s" % [kw, str(c.get(key, style_defaults(int(c.get("mode", 0))).get(key, 0)))]
			return _set_rule(key, arg)
	match kw:
		"adminlogin":
			c["admin_login"] = arg
			return ""
		"adminpass":
			c["admin_pass"] = arg
			return ""
		"sessionname":
			c["name"] = arg
			return "sessionname: %s" % arg
		"password":
			c["password"] = arg
			return "password: " + arg
		"port":
			if not arg.is_valid_int() or int(arg) < PORT_MIN or int(arg) > PORT_MAX:
				return "Port number allowed only in range <%d, %d>." % [PORT_MIN, PORT_MAX]
			c["port"] = int(arg)
			return "port  %d" % int(arg)
		"domain":
			if not arg in ["local", "internet"]:
				return "invalid parameters"
			c["internet"] = arg == "internet"
			return "domain: %s" % arg
		"style", "deathmatch", "occupation", "objectives", "teamdeathmatch", "cooperative":
			var w := arg if kw == "style" else kw
			if w == "cooperative":
				return "Coop mode is not supported by original server."
			if not STYLE_WORDS.has(w):
				return "invalid parameters"
			c["mode"] = int(STYLE_WORDS[w])
			return "style: %s" % w
		"voicechat":
			var codec := voice_codec_from(arg)
			if codec < 0:
				return "Not valid voice codec"
			c["voice_codec"] = codec
			return "voicechat %s" % arg
		"mapname", "removemap", "map":
			var id := resolve_map(arg, int(c.get("mode", -1)))
			if id == "":
				return "Map %s doesn't exist!" % arg
			var ml: Array = c.get("map_list", [])
			if kw == "removemap":
				ml.erase(id)
			elif not ml.has(id):
				ml.append(id)
			c["map_list"] = ml
			if not c.has("map") or (kw == "mapname" and not is_online and ml.size() == 1):
				c["map"] = id
			if kw == "map":
				if is_online:
					change_map(id)
				else:
					c["map"] = id
			return "maps: " + ", ".join(PackedStringArray(ml))
		"nextmap":
			if not is_online:
				return "not supported yet"
			change_map()
			return "nextmap: %s" % settings["map"]
		"restart":
			if not is_online:
				return "not supported yet"
			restart_round()
			return "restart"
		"kickplayer", "kick":
			var id := find_player(arg)
			if id == 0:
				return "invalid parameters"
			kick(id, tx(8871, "Der Admin hat die Verbindung zu Ihnen beendet."), tx(8875, "Die Verbindung zu %s wurde vom Admin beendet."))
			return ""
		"exec":
			return exec_file(arg, from)
		"server", "dedicated":
			if kw == "dedicated":
				c["dedicated"] = arg in ["", "1", "true", "yes"]
				if kw == "dedicated" and arg != "":
					return ""
			if is_online:
				return "server already running"
			return start_from_console()
		"botdebug":
			return BotDebug.toggle(arg)       # Debug-Ansicht der KI-Soldaten (Ziele/Pfade, nur auf dem Server)
		"quit":
			if from != 0:
				_tell(from, "Closing game. Wait please.")
			print("Closing game. Wait please.")
			leave(false)
			get_tree().quit.call_deferred()
			return "Closing game. Wait please."
	return "unknown command"


## Regel setzen (Bereiche RULE_RANGE; Ja/Nein als 0/1); Spieler-/Bot-Zahl und Karten wirken ab der nächsten Runde
func _set_rule(key: String, arg: String) -> String:
	var c := _cfg()
	var v: Variant
	if key in RULE_RANGE:
		if not arg.is_valid_int():
			return "a number required"
		var r: Array = RULE_RANGE[key]
		v = clampi(int(arg), int(r[0]), int(r[1]))
	else:
		var low := arg.to_lower()
		if not low in ["0", "1", "true", "false", "yes", "no", "on", "off"]:
			return "invalid value"
		v = low in ["1", "true", "yes", "on"]
	c[key] = v
	if is_online:
		_rules_changed.rpc(public_settings())
	return "%s = %s" % [RULE_KEYS[key], str(v)]


@rpc("authority", "call_remote", "reliable")
func _rules_changed(cfg: Dictionary) -> void:
	settings = cfg


func _status_text(full: bool) -> String:
	var out: PackedStringArray = []
	if full:
		out.append("%s  |  %s  |  %s  |  Runde %d/%d  |  Port %d%s" % [String(settings.get("name", "")), String(settings.get("map", "")),
			MODE_NAMES[clampi(mode(), 0, 3)], round_no, int(rule("round_count")), int(settings.get("port", PORT)),
			"  |  öffentl. IP %s" % public_ip if public_ip != "" else ""])
	out.append("%s %d / %d" % [tx(2306, "SPIELER"), humans(), int(rule("max_players"))])
	var ids := players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = players[id]
		out.append("%d - %s  [%s]  %s %d  Ping %d%s%s" % [int(id), String(p["name"]), team_name(int(p["team"])), tx(2594, "Punkte"),
			int(p["score"]), peer_ping(int(id)), "  KI" if bool(p.get("bot", false)) else "", "  ADMIN" if bool(p.get("admin", false)) else ""])
	return "\n".join(out)


static func team_name(t: int) -> String:
	return "Alliierte" if t == Soldier.TEAM_ALLIED else ("Achse" if t == Soldier.TEAM_AXIS else "–")


## Spieler über Nummer (listplayers) oder Namen finden (nur Menschen)
func find_player(s: String) -> int:
	s = s.strip_edges()
	if s.is_valid_int() and players.has(int(s)) and int(s) > 1:
		return int(s)
	for id in players:
		if int(id) > 1 and String(players[id]["name"]).to_lower() == s.to_lower():
			return int(id)
	return 0


## Karte auflösen: Karten-ID (mp_africa1_mp), Original-Ordner (AFRICA1_MP) oder Kartenname (Africa1) im Stil
func resolve_map(s: String, style := -1) -> String:
	s = s.strip_edges()
	if Game.MP_MAPS.has(s):
		return s
	if Game.MP_MAPS.has("mp_" + s.to_lower()):
		return "mp_" + s.to_lower()
	if Game.MP_MAPS.has(s.to_lower()):
		return s.to_lower()                 # eigene Karten-ID in anderer Schreibweise (Großbuchstaben)
	# Zwei Durchgänge: zuerst Karten genau dieses Stils (Kartenname + teamdeathmatch → TDM-Eintrag derselben Karte),
	# danach die bisherige großzügige Zuordnung (Arena-Karten ohne festen Stil, TDM auf DM-Karten)
	for strict in [true, false]:
		for id in Game.MP_MAPS:
			var e: Dictionary = Game.MISSIONS[id]
			var st = e.get("mp_mode")
			var tl := String(e.get("title", "")).to_lower()
			if not (tl == s.to_lower() or tl.begins_with(s.to_lower() + " ")):
				continue
			if strict and (style < 0 or st == null or int(st) != style):
				continue
			if style < 0 or st == null or int(st) == style or (style == Mode.TEAM_DEATHMATCH and int(st) == Mode.DEATHMATCH):
				return id
	return ""


## Spieler entfernen (Admin, Abstimmung, Teamkill, Ping, Inaktivität). msg_all mit %s = Spielername.
func kick(id: int, msg_victim: String, msg_all: String) -> void:
	if not players.has(id) or id <= 1 or bool(players[id].get("kicked", false)):
		return
	players[id]["kicked"] = true
	var nm := String(players[id]["name"])
	_announce(fmt_s(msg_all, [nm]))
	if multiplayer.get_peers().has(id):
		_rejected.rpc_id(id, msg_victim)
		get_tree().create_timer(1.0).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))


## --- Server-Grenzen: maxping, maxinactivity, maxfreq, floodprotect (ServerLauncher „Advanced“) ---------------
var _active_ms := {}          ## Peer-ID -> letzte Spieleraktivität (ms): Bewegung, Blick, Aktion, Chat
var _ready_peers := {}        ## Peer-ID -> Karte geladen (_client_ready); vorher keine Ping-/Inaktivitätsprüfung
var _ping_over := {}          ## Peer-ID -> Sekunden ununterbrochen über maxping
var _chat_times := {}         ## Peer-ID -> Zeitstempel der letzten Chatzeilen (Flood-Schutz)
var _muted_until := {}
var _last_st_ms := {}         ## maxfreq: letzter angenommener Zustand je Peer
var _limit_t := 0.0
var ping_override := {}       ## Tests: Peer-ID -> erzwungener Ping (ms)


func _touch(id: int) -> void:
	_active_ms[id] = Time.get_ticks_msec()


## Ping eines Peers in ms (ENet-Umlaufzeit; Server-Spieler 0)
func peer_ping(id: int) -> int:
	if ping_override.has(id):
		return int(ping_override[id])
	if _peer == null or not multiplayer.is_server() or id <= 1 or not multiplayer.get_peers().has(id):
		return 0
	var pp := _peer.get_peer(id)
	return pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if pp else 0


## 1-s-Takt (Server): zu hoher Ping (PING_KICK_GRACE_S am Stück) bzw. keine Eingabe seit maxinactivity s → Rauswurf
## mit den Originaltexten 8873/8877 bzw. 8872/8876. Geprüft werden nur Menschen mit geladener Karte und
## lebendem Soldaten (Zuschauer/Wartende sind nicht inaktiv).
func _limits_tick(delta: float) -> void:
	_limit_t -= delta
	if _limit_t > 0.0:
		return
	_limit_t = 1.0
	var now := Time.get_ticks_msec()
	var max_ping := int(rule("max_ping"))
	var max_idle := int(rule("max_inactivity"))
	for id in players.keys():
		var pid := int(id)
		if pid <= 1 or bool(players[id].get("bot", false)) or not _ready_peers.has(pid):
			continue
		if max_ping > 0:
			if peer_ping(pid) > max_ping:
				_ping_over[pid] = float(_ping_over.get(pid, 0.0)) + 1.0
			else:
				_ping_over.erase(pid)
			if float(_ping_over.get(pid, 0.0)) >= PING_KICK_GRACE_S:
				kick(pid, tx(8873, "Ihre Verbindung wurde aufgrund eines zu hohen Ping beendet."),
					tx(8877, "Die Verbindung zu %s wurde aufgrund eines zu hohen Ping beendet."))
				continue
		var s: Soldier = _soldiers.get(pid)
		if max_idle > 0 and is_instance_valid(s) and s.alive and now - int(_active_ms.get(pid, now)) > max_idle * 1000:
			kick(pid, tx(8872, "Ihre Verbindung wurde aufgrund von Inaktivität beendet."),
				tx(8876, "Die Verbindung zu %s wurde aufgrund Inaktivität beendet."))


## Flood-Schutz (floodprotect, Original-Standard an): zu viele Chatzeilen in kurzer Zeit → eine Weile stumm
func _flooding(id: int) -> bool:
	if not bool(rule("flood_protect")) or id <= 0:
		return false
	var now := Time.get_ticks_msec()
	if now < int(_muted_until.get(id, 0)):
		return true
	var arr: Array = (_chat_times.get(id, []) as Array).filter(func(t): return now - int(t) < int(FLOOD_WINDOW_S * 1000.0))
	arr.append(now)
	_chat_times[id] = arr
	if arr.size() > FLOOD_MSGS:
		_muted_until[id] = now + int(FLOOD_MUTE_S * 1000.0)
		return true
	return false


## maxfreq [Hz]: Zustandstakt begrenzen (Clients senden höchstens so oft; zu dichte Pakete verwirft der Server)
func _state_hz() -> float:
	var hz := float(Settings.CONNECTION_HZ[clampi(Settings.connection_type, 0, 4)])
	var mf: int = int(rule("max_freq")) if is_online else 0
	return minf(hz, float(mf)) if mf > 0 else hz


## --- MP-Rang (Punkte/10, höchstens 7) mit Beförderungs-/Degradierungsmeldung (T8900–8903) ---------------------
static func rank_of(score: int) -> int:
	return clampi(floori(score / float(RANK_STEP)), 0, RANK_MAX)


func _update_ranks() -> void:
	for id in players.keys():
		var p: Dictionary = players[id]
		var r := rank_of(int(p.get("score", 0)))
		var old := int(p.get("rank", 0))
		if r != old:
			p["rank"] = r
			_rank_msg.rpc(int(id), r, r > old)


@rpc("authority", "call_local", "reliable")
func _rank_msg(id: int, rank: int, up: bool) -> void:
	if players.has(id):
		players[id]["rank"] = rank
	var rn := SAS.rank_name(rank)
	if id == my_id() and not dedicated:
		Events.say("%s %s" % [tx(8901 if up else 8900, "Befördert zu" if up else "Degradiert zu"), rn], 4.0)
	else:
		_chat("Server", "%s %s %s" % [String(players.get(id, {}).get("name", "?")), tx(8903 if up else 8902,
			"wurde befördert zu" if up else "wurde degradiert zu"), rn], false)
	rank_log.append([id, rank, up])


var rank_log: Array = []      ## Tests/Anzeige: [Peer-ID, Rang, befördert]


## Konfigurationsdatei im Original-ServerLauncher-Stil (eine Konsolenzeile je Zeile) ausführen
func exec_file(path: String, from := 0) -> String:
	if not FileAccess.file_exists(path) and path.is_relative_path():
		path = OS.get_executable_path().get_base_dir().path_join(path)       # neben der Programmdatei
	if not FileAccess.file_exists(path):
		return "Can not find config file."
	var out: PackedStringArray = []
	for l in FileAccess.get_file_as_string(path).split("\n"):
		var r := server_command(l.strip_edges(), from)
		if r != "":
			out.append(r)
	return "\n".join(out)


## „server“: mit den bisher gesetzten Konsolenwerten starten (Stil-Standards für fehlende Regeln)
func start_from_console() -> String:
	var c := _cfg_pending.duplicate(true)
	var m := int(c.get("mode", Mode.DEATHMATCH))
	var ml: Array = c.get("map_list", [])
	if ml.is_empty():
		return "Cannot create server! No map!"
	for k in style_defaults(m):
		if not c.has(k):
			c[k] = style_defaults(m)[k]
	if not c.has("map"):
		c["map"] = ml[0]
	c["mode"] = m
	if not c.has("name"):
		c["name"] = tx(2025, "H&D 2 SERVER")
	if not c.has("port"):
		c["port"] = PORT
	var mm = Game.MISSIONS.get(String(c["map"]), {}).get("mp_mode")
	if mm != null:
		c["mode"] = int(mm)
	if not host(c):
		return last_error
	return "Creating H&D2 Server (%s, Port %d)" % [String(c["map"]), int(c["port"])]


## --- Abstimmungen (Original-Texte 8910–8932) ---
func start_vote(from: int, arg: String) -> String:
	if not is_online or not multiplayer.is_server():
		return "not supported yet"
	if not _vote.is_empty():
		return tx(8930, "Abstimmung gestartet") + ": " + String(_vote["text"])
	var sp := arg.find(" ")
	var what := (arg if sp < 0 else arg.substr(0, sp)).to_lower()
	var val := "" if sp < 0 else arg.substr(sp + 1).strip_edges()
	var cmd := ""
	var text := ""
	match what:
		"kickplayer", "kick":
			var id := find_player(val)
			if id == 0:
				return "Not valid voting command"
			cmd = "kickplayer %d" % id
			text = "%s: %s" % [tx(8924, "Spieler rauswerfen"), players[id]["name"]]
		"nextmap":
			cmd = "nextmap"
			text = tx(8925, "nächste Karte")
		"restart":
			cmd = "restart"
			text = tx(8926, "Neustart")
		_:
			if VOTE_RULES.has(what) and val != "":
				cmd = "%s %s" % [what, val]
				text = "%s = %s" % [tx(int(VOTE_RULES[what]), what), val]
			elif what == "selfdamage" and val != "":
				cmd = "inversedamage %s" % val
				text = "%s = %s" % [tx(8921, what), val]
	if cmd == "":
		return "Not valid voting command"
	_vote = {"cmd": cmd, "text": text, "yes": [from] if from > 0 else [], "until": Time.get_ticks_msec() + int(VOTE_TIME_S * 1000.0)}
	_announce("%s: %s" % [tx(8930, "Abstimmung gestartet"), text])
	_vote_tick()
	return ""


func vote_yes(from: int) -> String:
	if _vote.is_empty():
		return "Not valid voting command"
	if from > 0 and not (_vote["yes"] as Array).has(from):
		(_vote["yes"] as Array).append(from)
	_vote_tick()
	return ""


## Annahme: einfache Mehrheit der menschlichen Spieler (Originalregel nicht dekodiert)
func _vote_needed() -> int:
	return int(floor(humans() / 2.0)) + 1


func _vote_tick() -> void:
	if _vote.is_empty():
		return
	var yes: Array = (_vote["yes"] as Array).filter(func(i): return players.has(i))
	_vote["yes"] = yes
	if yes.size() >= _vote_needed():
		var cmd := String(_vote["cmd"])
		_vote = {}
		_announce(tx(8931, "Abstimmung angenommen"))
		server_command(cmd, 0)
	elif Time.get_ticks_msec() > int(_vote["until"]):
		_vote = {}
		_announce(tx(8932, "Abstimmung abgelehnt"))


func _team_humans(t: int) -> int:
	var n := 0
	for p in players.values():
		if not bool(p.get("bot", false)) and int(p.get("next_team", p["team"])) == t:
			n += 1
	return n


func _begin_match() -> void:
	match_over = false
	_match_t = 0.0
	team_score = [0.0, 0.0]
	zone_owner.clear()
	obj_done.clear()
	_wave_t = 0.0
	_bot_groups.clear()
	for k in players.keys():
		if int(k) < 0:
			players.erase(k)       # KI-Soldaten werden je Runde neu erzeugt
	for p in players.values():
		p["kills"] = 0
		p["deaths"] = 0
		p["score"] = 0
		p["teamkills"] = 0
		p["spectator"] = false
		p["rank"] = 0
	_soldiers.clear()
	_respawn.clear()
	_vip.clear()
	_ready_peers.clear()          # Karte wird neu geladen: Grenzen erst wieder nach _client_ready prüfen
	_ping_over.clear()
	_warm_t = float(rule("warmup_s"))
	game_state = State.WARMUP if _warm_t > 0.0 else State.RUNNING
	Game.start_mission(String(settings["map"]))


# --- Mission / Spieler-Soldaten ----------------------------------------------------

## Von der Mission nach dem Aufbau aufgerufen (Mehrspieler: keine KI, keine Skripte)
func mission_ready(_m: Node) -> void:
	if not is_online:
		return
	print("NET: Mission bereit (Server: ", multiplayer.is_server(), ")")
	if multiplayer.is_server():
		if not dedicated:
			_server_spawn(1)
		_add_bots()
	else:
		_client_ready.rpc_id(1)
	_ensure_hud(_m)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_ready_peers[id] = true
	_touch(id)
	for pid in _soldiers:
		var s: Soldier = _soldiers[pid]
		if is_instance_valid(s) and s.alive:
			_spawn.rpc_id(id, pid, String(players.get(pid, {}).get("name", "?")), int(players.get(pid, {}).get("team", 0)),
				s.global_position, s.look_yaw, int(_gen.get(pid, 0)), players.get(pid, {}).get("kit", []))
	_players.rpc_id(id, players)
	_obj_states.rpc_id(id, _object_states())      # Türen: aktueller Stand für Spät-Beitretende
	_server_spawn(id)


## Teamausgleich während der Runde (Regel autoteambalance): Kriterium wie Original 0x7301C0
## |n_A − (b_A/b_B)·n_B| ≥ 1,5 über die (nächste) Seite der menschlichen Spieler (0x72FF50 mit +0x68). Beim
## (Wieder-)Einstieg wird ein Spieler des größeren Teams auf die andere Seite gesetzt, wenn das Ungleichgewicht
## dadurch kleiner wird; Meldung an alle (T2372 + Seite). Das Original prüft nachweislich nur bei Teamwahl/Beitritt
## (0x727800 Fall 5, kein weiterer Aufrufer); das Umsetzen beim Respawn ist Vorgabe des Auftraggebers [A].
func _auto_balance(id: int) -> void:
	if id < 0 or not team_mode() or not bool(rule("team_balance")) or bool(players[id].get("bot", false)):
		return
	var t := int(players[id]["team"])
	if not t in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
		return
	var na := _team_humans(Soldier.TEAM_ALLIED)
	var nx := _team_humans(Soldier.TEAM_AXIS)
	if not _unbalanced(na, nx):
		return
	var o: int = Soldier.TEAM_AXIS if t == Soldier.TEAM_ALLIED else Soldier.TEAM_ALLIED
	var na2: int = na + (1 if o == Soldier.TEAM_ALLIED else -1)
	var nx2: int = nx + (1 if o == Soldier.TEAM_AXIS else -1)
	var r := balance_ratio()
	if absf(na2 - r * nx2) >= absf(na - r * nx):
		return
	players[id]["team"] = o
	players[id].erase("zone")
	balance_log.append([id, t, o])
	_players.rpc(players)
	_announce("%s: %s → %s" % [tx(2372, "AUTO. TEAMAUSGLEICH"), String(players[id]["name"]), team_name(o)])


var balance_log: Array = []           ## [Peer-ID, alte Seite, neue Seite] (Tests)


## Lebende Teamkameraden (Spieler und KI-Soldaten der eigenen Seite) für die Kompasspunkte (OrigHud); im
## Deathmatch keine
func compass_mates(me: Soldier) -> Array:
	var out: Array = []
	if not is_online or not team_mode() or me == null:
		return out
	for pid in _soldiers:
		var s: Soldier = _soldiers[pid]
		if is_instance_valid(s) and s != me and s.alive and s.team == me.team:
			out.append(s)
	return out


func _server_spawn(id: int) -> void:
	var m = Game.current_mission()
	if m == null or not players.has(id):
		return
	if bool(players[id].get("spectator", false)):
		return
	_touch(id)                # Inaktivität zählt ab dem (Wieder-)Einstieg
	if players[id].has("next_team"):
		players[id]["team"] = int(players[id]["next_team"])      # Teamwechsel aus dem SPIELER-SETUP
		players[id].erase("next_team")
		_players.rpc(players)
	_auto_balance(id)
	var team := int(players[id]["team"])
	var pts: Array = m.mp_spawns() if m.has_method("mp_spawns") else []
	if mode() in [Mode.OCCUPATION, Mode.OBJECTIVES] and m.has_method("mp_zones"):
		# Original: Spawn an einer eigenen Zone (Spieler wählt; hier: eigene Zone nächst einer gegnerischen)
		var zs: Array = m.mp_zones()
		if zone_owner.size() != zs.size():
			zone_owner = zs.map(func(z): return int(z["owner"]))
		var own: Array = []
		for i in zs.size():
			if i < zone_owner.size() and zone_owner[i] == team and not (zs[i]["slots"] as Array).is_empty():
				own.append(i)
		if not own.is_empty():
			own.sort_custom(func(a, b): return _front_dist(zs, a, team) < _front_dist(zs, b, team))
			# Spieler-Wahl auf der Spawnzonen-Karte (T2507/2525), sonst frontnächste eigene Zone
			var want := int(players[id].get("zone", -1))
			var zi: int = want if own.has(want) else int(own[0])
			pts = (zs[zi]["slots"] as Array).map(func(s): return {"pos": s["pos"], "yaw": s["yaw"], "team": team})
	var cand: Array = pts.filter(func(p): return mode() == Mode.DEATHMATCH or int(p.get("team", -1)) in [-1, team])
	if cand.is_empty():
		cand = pts
	var pos := Vector3.ZERO
	var yaw := 0.0
	if not cand.is_empty():
		# Spawnpunkt mit dem größten Abstand zum nächsten lebenden Gegner
		var best := -1.0
		for p in cand:
			var d := 1e9
			for pid in _soldiers:
				var s: Soldier = _soldiers[pid]
				if is_instance_valid(s) and s.alive and pid != id:
					d = minf(d, (p["pos"] as Vector3).distance_to(s.global_position))
			d += randf() * 5.0
			if d > best:
				best = d
				pos = p["pos"]
				yaw = float(p.get("yaw", 0.0))
	if mode() == Mode.DEATHMATCH and not cand.is_empty():
		var c: Dictionary = cand[randi() % cand.size()]      # Original: zufälliger freier Spawnpunkt
		pos = c["pos"]
		yaw = float(c.get("yaw", 0.0))
	_gen[id] = int(_gen.get(id, 0)) + 1
	print("NET: Spawn für ", id, " bei ", pos)
	var kit: Array = bot_kit(team, int(players[id].get("role", 0)), bool(players[id].get("hero", false))) if id < 0 else []
	players[id]["kit"] = kit
	if players[id].has("loadout"):
		# Einzel-Ausrüstung erneut prüfen (Seite/Karte/Figur können sich geändert haben), sonst Klassen-Vorlage
		var lerr := loadout_error(id, players[id]["loadout"])
		if lerr != "":
			players[id].erase("loadout")
			_tell(id, lerr)
			_players.rpc(players)
	_assign_vip(id, team)
	_spawn.rpc(id, String(players[id]["name"]), team, pos, yaw, int(_gen[id]), kit, String(players[id].get("vip_model", "")))


# --- VIP-Ziele (HD2-Aufgaben, mpmaplist type="VIP", hd2.exe 0x69D9C0/0x69E340) ---------------------
## Der erste Spieler der VIP-Seite (vip_team, Gegenseite des Ziel-Teams), der spawnt, wird VIP und erhält die
## VIP-Uniform (vip_uniform_id 146 „Uniform GE14“ bzw. 128); stirbt er, gilt die Aufgabe als erfüllt [P].
var _vip := {}                ## Aufgaben-Index -> Peer-ID des VIP


func _assign_vip(id: int, team: int) -> void:
	var m = Game.current_mission()
	if mode() != Mode.OBJECTIVES or m == null or not m.has_method("mp_objectives"):
		return
	for o in m.mp_objectives():
		if String(o.get("type", "")) != "VIP" or obj_done.has(int(o["index"])) or int(o.get("vip_team", -9)) != team:
			continue
		var cur = _vip.get(int(o["index"]))
		if cur == null or (cur == id):
			_vip[int(o["index"])] = id
			players[id]["vip"] = int(o["index"])
			players[id]["vip_model"] = String(o.get("vip_model", ""))
			return


## VIP-Liste für Anzeige: Peer-ID -> Aufgaben-Index
func vip_of(id: int) -> int:
	return int(players.get(id, {}).get("vip", -1))


@rpc("authority", "call_local", "reliable")
func _spawn(id: int, pname: String, team: int, pos: Vector3, yaw: float, gen: int, kit: Array = [], vip_model := "") -> void:
	var m = Game.current_mission()
	if m == null:
		return
	var old: Soldier = _soldiers.get(id)
	if is_instance_valid(old) and old.alive:
		old.queue_free()
	elif is_instance_valid(old):
		get_tree().create_timer(20.0).timeout.connect(func(): if is_instance_valid(old): old.queue_free())   # Leiche räumen
	var allied := team != Soldier.TEAM_AXIS
	var lo := ["sten", "colt", "no36"] if allied else ["mp40", "p08", "m24"]
	var col := Color(0.43, 0.39, 0.25) if team == 0 else (Color(0.36, 0.38, 0.33) if team == 1 \
		else Color.from_hsv(fmod(float(team) * 0.17, 1.0), 0.35, 0.45))
	var s: Soldier = m.spawn_soldier(pos, yaw, team, pname, lo, col, "brodie" if allied else "stahlhelm", "P%d_%d" % [id, gen])
	s.set_meta("net_peer", id)
	m._default_kit(s)
	var own_inv = players.get(id, {}).get("loadout", {})
	if kit.is_empty() and own_inv is Dictionary and not (own_inv as Dictionary).is_empty():
		_apply_inventory(s, own_inv)
	elif kit.is_empty():
		_apply_class(m, s, team, int(players.get(id, {}).get("cls", 2)))
	else:
		_apply_kit(s, kit)
	s.max_health = 100.0
	s.health = 100.0
	var pinfo: Dictionary = players.get(id, {}).duplicate()
	if vip_model != "":
		pinfo["model"] = vip_model
		s.set_meta("vip", true)
		s.set_meta("mp_class", "VIP")
	_attach_figure(m, s, team, pinfo)
	s.set_meta("spawn_ms", Time.get_ticks_msec())
	s.set_meta("protect_until", int(s.get_meta("spawn_ms")) + int(float(rule("spawn_protect_s")) * 1000.0))
	_soldiers[id] = s
	_hp_sent[id] = s.health
	if id < 0 and multiplayer.is_server():
		_make_bot(s, id)
	elif id < 0:
		s.net_puppet = true
		s.net_target = pos
	elif id == my_id():
		s.net_hook = _local_action
		var sq = m.squad
		sq.members.clear()
		sq.add_member(s)
		sq.set_active(0)
		m.controller.set_active(s)
		m.rig.set_target(s)
		respawn_at = 0
		if not third_person_allowed() and m.rig.mode != CameraRig.Mode.FIRST:
			m.rig.toggle_mode()          # 3.-Person-Ansicht nicht erlaubt (Server-Regel, Original-Standard)
	else:
		s.net_puppet = true
		s.net_target = pos


@rpc("authority", "call_local", "reliable")
func _remove_player(id: int) -> void:
	var s: Soldier = _soldiers.get(id)
	if is_instance_valid(s):
		s.queue_free()
	_soldiers.erase(id)
	players.erase(id)


# --- Zustandsabgleich -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_online:
		return
	_poll_discovery(delta)
	var me: Soldier = _soldiers.get(my_id())
	_sync_t -= delta
	if is_instance_valid(me) and me.alive and _sync_t <= 0.0:
		_sync_t = 1.0 / _state_hz()    # Verbindungsart (Optionen), begrenzt durch maxfreq des Servers
		_st.rpc(me.global_position, me.velocity, me.look_yaw, me.look_pitch, me.stance, me.current_slot, me.aiming)
		# Fahrzeug: Sitzwechsel/Ein-/Aussteigen melden, als Fahrer die Fahrzeuglage
		var vpath := String(me.vehicle.get_path()) if me.vehicle else ""
		if vpath != _last_vehicle or me.seat_index != _last_seat:
			_last_vehicle = vpath
			_last_seat = me.seat_index
			_seat.rpc(vpath, me.seat_index)
		_sync_vehicle(me)
	if multiplayer.is_server():
		_server_tick(delta)
		_bot_sync(delta)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _st(pos: Vector3, vel: Vector3, yaw: float, pitch: float, stance: int, slot: int, aiming: bool) -> void:
	var sid := multiplayer.get_remote_sender_id()
	var s: Soldier = _soldiers.get(sid)
	if not is_instance_valid(s) or not s.alive:
		return
	if multiplayer.is_server():
		var now := Time.get_ticks_msec()
		var mf := int(rule("max_freq"))
		if mf > 0 and now - int(_last_st_ms.get(sid, 0)) < int(500.0 / mf):
			return                  # maxfreq: deutlich zu dichte Zustandspakete verwerfen
		_last_st_ms[sid] = now
		if pos.distance_to(s.net_target) > 0.05 or absf(yaw - s.look_yaw) > 0.01 or absf(pitch - s.look_pitch) > 0.01 \
				or stance != s.stance_request or aiming != s.aiming:
			_touch(sid)             # Eingabe des Spielers (Inaktivitäts-Rauswurf)
	s.net_target = pos
	s.net_velocity = vel
	s.look_yaw = yaw
	s.look_pitch = pitch
	s.stance_request = stance
	s.aiming = aiming
	if slot != s.current_slot and slot < s.weapons.size() and s.weapons[slot] != null:
		s.current_slot = slot
		s._on_weapon_switched()


## Aktion des eigenen Soldaten (Soldier.net_hook) an alle anderen
func _local_action(kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	_act.rpc(kind, a, b, wid)


@rpc("any_peer", "call_remote", "reliable")
func _act(kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	_touch(multiplayer.get_remote_sender_id())
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
	if not is_instance_valid(s) or not s.alive:
		return
	_do_act(s, kind, a, b, wid)


## Aktion eines (fremden) Soldaten darstellen; nur der Server wertet Treffer aus
func _do_act(s: Soldier, kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	var wd: WeaponData = WeaponDB.get_weapon(StringName(wid)) if wid != "" else null
	match kind:
		"shot":
			Ballistics.fire(s, a, b, wd, s.exclude_rids(), s.team)
			Effects.muzzle_flash(a + b * 0.9, b)
			Effects.play(Effects.weapon_sound(wd), a, 0.0, 1.0, wd.noise_radius * 2.0)
			Events.emit_noise(s.global_position, wd.noise_radius, s, s.team, &"gunshot")
			# Netzfigur: Feuerclip + Rückstoß wie beim lokalen Schützen (ohne Modell-/Haltungswechsel)
			if s.model and s.model.has_method("_on_shot_fired") and s.current_weapon():
				s.model._on_shot_fired(s.current_weapon())
			# Waffenstellung: Rohrrückstoß, die Hände des Schützen folgen den Griffen (OrigEmplacement)
			if is_instance_valid(s.mounted) and s.mounted.has_method("_on_gunner_shot"):
				s.mounted._on_gunner_shot(null)
		"rocket", "grenade":
			var g := Grenade.new()
			g.data = wd
			g.thrower = s
			g.team = s.team
			g.impact = kind == "rocket"
			s.get_parent().add_child(g)
			g.global_position = a
			g.linear_velocity = b
			g.add_collision_exception_with(s)
		"melee":
			# Messer serverbestätigt: der Server sticht mit (Treffer zum Stichbild, Ziel-Hinweis a.x mit Lagetoleranz),
			# die übrigen Rechner zeigen nur die Stichanimation
			if multiplayer.is_server() and s.weapons.size() > WeaponData.Slot.MELEE and s.weapons[WeaponData.Slot.MELEE]:
				s.look_yaw = b.x
				var hint: Soldier = _soldiers.get(int(a.x)) if a.y > 0.5 else null
				s._melee(s.weapons[WeaponData.Slot.MELEE], hint, true)
			elif not multiplayer.is_server() and s.has_method("melee_visual"):
				s.look_yaw = b.x
				s.melee_visual()
		"lean":
			s.lean = clampf(a.x, -1.0, 1.0)      # Lehnen der Netzfigur (Q/E, BodyAnim)
		"explosive", "mine":
			var c := PlacedCharge.new()
			c.kind = kind
			c.owner_soldier = s
			c.team = s.team
			s.get_parent().add_child(c)
			c.global_position = a
		"tool":
			# Hilfsmittel in der Hand der Netzfigur (Verband/Mine/Sprengstoff/Fernglas), Code in a.x
			s.tool = String(Soldier.TOOL_KEYS[clampi(int(a.x), 0, Soldier.TOOL_KEYS.size() - 1)])


## Server: gelegte Mine/Ladung detoniert (Beschuss, Kettenreaktion, Zünder) – bei allen Clients ebenfalls
func charge_detonated(pos: Vector3) -> void:
	if is_online and multiplayer.is_server():
		_charge_boom.rpc(pos)


@rpc("authority", "call_remote", "reliable")
func _charge_boom(pos: Vector3) -> void:
	PlacedCharge.remote_detonate(get_tree(), pos)


## Server: gelegte Mine/Ladung entschärft – bei allen Clients entfernen
func charge_defused(pos: Vector3) -> void:
	if is_online and multiplayer.is_server():
		_charge_defuse.rpc(pos)


@rpc("authority", "call_remote", "reliable")
func _charge_defuse(pos: Vector3) -> void:
	PlacedCharge.remote_defuse(get_tree(), pos)


# --- Weltobjekte und Fahrzeuge ------------------------------------------------------------

## Eigener Spieler hat ein Objekt benutzt (Tür, Schalter, Leiter …): bei allen anderen ebenfalls ausführen
func used_interactable(it: Node) -> void:
	var pid := String(it.get("persistent_id")) if it.get("persistent_id") != null else ""
	if pid == "":
		pid = String(it.get_path())
	_use.rpc(pid)


@rpc("any_peer", "call_remote", "reliable")
func _use(pid: String) -> void:
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
	if not is_instance_valid(s):
		return
	for n in get_tree().get_nodes_in_group("interactables"):
		var p = n.get("persistent_id")
		if (p != null and String(p) == pid) or String(n.get_path()) == pid:
			if n is OrigInteractive.OrigLadder:
				return       # Klettern ist Bewegung des Spielers selbst (kommt über den Zustandsabgleich)
			if n.has_method("net_state") and not multiplayer.is_server():
				return       # Türen: Server führt aus und meldet den Zustand (object_state), kein Umschalten je Rechner
			n.interact(s)
			return


## Server: Zustand eines Weltobjekts mit net_state()/net_apply() (Türen/Schranken) an alle – auch nach KI-Öffnen,
## Auto-Schließen, Skript (SetActorState/DOOR_Lock) und Schlossknacken. Vorher schaltete jeder Rechner beim Benutzen
## nur um: Spät-Beitretende und KI-geöffnete Türen liefen auseinander (Tür offen gezeigt, beim Server zu).
func object_state(it: Node) -> void:
	if is_online and multiplayer.is_server() and not _ready_peers.is_empty():
		_obj_state.rpc(String(it.get("persistent_id")), it.net_state())


@rpc("authority", "call_remote", "reliable")
func _obj_state(pid: String, st: Dictionary) -> void:
	for n in get_tree().get_nodes_in_group("interactables"):
		if n.has_method("net_apply") and String(n.get("persistent_id")) == pid:
			n.net_apply(st, false)
			return


func _object_states() -> Dictionary:
	var out := {}
	for n in get_tree().get_nodes_in_group("interactables"):
		if n.has_method("net_state") and String(n.get("persistent_id")) != "":
			out[String(n.get("persistent_id"))] = n.net_state()
	return out


@rpc("authority", "call_remote", "reliable")
func _obj_states(states: Dictionary) -> void:
	for n in get_tree().get_nodes_in_group("interactables"):
		var pid := String(n.get("persistent_id")) if n.get("persistent_id") != null else ""
		if n.has_method("net_apply") and states.has(pid):
			n.net_apply(states[pid], true)


# --- Ingame-Inventar (FieldInventory): Aktion als Anfrage an den Server, Stand der Inventare an alle ----------

func inventory_request(op: Dictionary) -> void:
	if multiplayer.is_server():
		FieldInventory.server_execute(_soldiers.get(my_id()), op)
	else:
		_inv_req.rpc_id(1, op)


@rpc("any_peer", "call_remote", "reliable")
func _inv_req(op: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	_touch(sid)
	FieldInventory.server_execute(_soldiers.get(sid), op)


func inventory_broadcast(key: String, state: Dictionary) -> void:
	if is_online and multiplayer.is_server():
		_inv_state.rpc(key, state)


@rpc("authority", "call_remote", "reliable")
func _inv_state(key: String, state: Dictionary) -> void:
	FieldInventory.receive_state(key, state)


## Fahrer meldet die Fahrzeuglage; Ein-/Aussteigen anderer kommt über deren Zustand (Sitz)
func _sync_vehicle(me: Soldier) -> void:
	var v := me.vehicle as Vehicle
	if v == null or me.seat_index != 0:
		return
	_veh.rpc(String(v.get_path()), v.global_transform, v.linear_velocity)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _veh(path: String, xf: Transform3D, vel: Vector3) -> void:
	var v := get_node_or_null(path) as Vehicle
	if v == null:
		return
	v.net_apply(xf, vel)       # folgt kinematisch und geglättet, solange Lagen vom Fahrer kommen


@rpc("any_peer", "call_remote", "reliable")
func _seat(path: String, seat: int) -> void:
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
	if not is_instance_valid(s):
		return
	var v := get_node_or_null(path) as Vehicle
	if s.vehicle and s.vehicle != v:
		(s.vehicle as Vehicle).leave(s)
	if v == null:
		return
	if s.vehicle == null:
		v.board(s, seat == 0)
	if s.seat_index != seat:
		v.switch_seat(s, seat)


# --- Server: Schaden, Tod, Punkte, Respawn, Spielende ------------------------------------

func _server_tick(delta: float) -> void:
	_vote_tick()
	if Game.current_mission() == null:
		return                  # Karte lädt (Hintergrundladen): Spielzeit, Aufwärmen und Wiedereinstiege ruhen
	_limits_tick(delta)
	_info_t -= delta
	if _info_t <= 0.0:
		_info_t = 0.5
		_info.rpc(_hud_snapshot())
	if match_over:
		_end_t -= delta
		if _end_t <= 0.0:
			_next_round()
		return
	for id in _soldiers:
		var s: Soldier = _soldiers[id]
		if is_instance_valid(s) and s.alive and absf(s.health - float(_hp_sent.get(id, s.health))) > 0.5:
			_hp_sent[id] = s.health
			_hp.rpc(id, s.health)
	if game_state == State.WARMUP:
		# Aufwärmen (Original-Zustand 3, HUD 7402): kein Zeitlimit, keine Wertung, sofortiger Wiedereinstieg
		_warm_t -= delta
		for id in _respawn.keys():
			_respawn[id] -= delta
			if _respawn[id] <= 0.0:
				_respawn.erase(id)
				_server_spawn(id)
		if _warm_t <= 0.0:
			_warmup_finished()
		return
	_match_t += delta
	if mode() == Mode.OCCUPATION:
		_wave_t -= delta
		if _wave_t <= 0.0:
			_wave_t = float(rule("respawn_s")) + 1.0         # Original: Welle alle (Respawn-Zeit + 1) s
			for id in _respawn.keys():
				_respawn.erase(id)
				_server_spawn(id)
		_zones_tick(delta)
	else:
		for id in _respawn.keys():
			_respawn[id] -= delta
			if _respawn[id] <= 0.0:
				_respawn.erase(id)
				_server_spawn(id)
	if mode() in [Mode.OBJECTIVES, Mode.OCCUPATION] and _match_t > 5.0:
		for t in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
			if _team_alive(t) == 0 and _team_players(t) > 0 and _team_alive(1 - t) > 0 \
					and (mode() == Mode.OBJECTIVES or not zone_owner.has(t)) and not _respawn_pending(t):
				_server_end("%s ausgeschaltet" % ["Alliierte", "Achsenmächte"][t], 1 - t)
				return
	var tl := float(rule("time_limit_min")) * 60.0
	if tl > 0.0 and _match_t >= tl:
		_server_end("Zeit abgelaufen", _time_winner())


## Team wartet noch auf Wiedereinstieg (dann nicht „ausgeschaltet“)
func _respawn_pending(t: int) -> bool:
	if not bool(rule("allow_respawn")):
		return false
	for id in _respawn:
		if int(players.get(id, {}).get("team", -9)) == t:
			return true
	return false


## Sieger bei Zeitablauf (Original 0x699B50): Besetzung – alle Zonen → Inhaber, sonst mehr Teampunkte mit ≥ 1 Zone
## → Alliierte, sonst Achse; Aufgaben – Verteidiger (Gegenseite des Ziel-Teams), offene Ziele zählen für ihn;
## Team-Deathmatch – mehr Punkte; Deathmatch – kein Siegerteam.
func _time_winner() -> int:
	var a := Soldier.TEAM_ALLIED
	var x := Soldier.TEAM_AXIS
	match mode():
		Mode.OCCUPATION:
			if not zone_owner.is_empty() and zone_owner.all(func(o): return o == a):
				return a
			if team_score[a] > team_score[x] and zone_owner.has(a):
				return a
			return x
		Mode.OBJECTIVES:
			var m = Game.current_mission()
			var side := a
			if m and m.has_method("mp_objectives") and not m.mp_objectives().is_empty():
				side = int(m.mp_objectives()[0]["team"])
			var winner := 1 - side
			if m and m.has_method("mp_objectives"):
				for o in m.mp_objectives():
					if not obj_done.has(int(o["index"])):
						team_score[winner] += float(o["value"])
			return winner
		Mode.TEAM_DEATHMATCH:
			if team_score[a] == team_score[x]:
				return -1
			return a if team_score[a] > team_score[x] else x
	return -1


func _warmup_finished() -> void:
	game_state = State.RUNNING
	_match_t = 0.0
	team_score = [0.0, 0.0]
	for p in players.values():
		for k in ["kills", "deaths", "score", "teamkills", "rank"]:
			p[k] = 0
		p["spectator"] = false
	_respawn.clear()
	_vip.clear()
	for id in players.keys():
		players[id].erase("vip")
		players[id].erase("vip_model")
	_players.rpc(players)
	_scores.rpc(team_score)
	_announce("Aufwärmen beendet – die Runde beginnt.")
	for id in players.keys():
		_server_spawn(int(id))           # alle neu aufstellen (Aufwärmphase zählt nicht)


## Nächste Runde bzw. nach `roundcount` Runden nächste Karte der Kartenliste (Original 0x6997B0/0x69B9F0)
func _next_round() -> void:
	round_no += 1
	if round_no > int(rule("round_count")):
		var ml: Array = settings.get("map_list", [])
		var i := ml.find(String(settings["map"]))
		if not ml.is_empty():
			_set_map(String(ml[(i + 1) % ml.size()]))
		round_no = 1
		team_wins = [0, 0]
	_begin_match()
	_enter_match.rpc(public_settings(), team_score)


## Karte setzen (Stil folgt einer Original-MP-Karte mit festem Stil)
func _set_map(id: String) -> void:
	settings["map"] = id
	var fixed = Game.MISSIONS.get(id, {}).get("mp_mode")
	if fixed != null:
		settings["mode"] = int(fixed)
	elif mode() > Mode.TEAM_DEATHMATCH:
		settings["mode"] = Mode.DEATHMATCH


## Sofortiger Karten-/Rundenwechsel (Konsole/Abstimmung: nextmap, mapname, restart)
func change_map(id := "") -> void:
	if not is_online or not multiplayer.is_server():
		return
	if id == "":
		var ml: Array = settings.get("map_list", [])
		var i := ml.find(String(settings["map"]))
		id = String(ml[(i + 1) % ml.size()]) if not ml.is_empty() else String(settings["map"])
	_set_map(id)
	round_no = 1
	team_wins = [0, 0]
	_begin_match()
	_enter_match.rpc(public_settings(), team_score)


func restart_round() -> void:
	if is_online and multiplayer.is_server():
		_begin_match()
		_enter_match.rpc(public_settings(), team_score)


## Zustand für das MP-HUD (Server → alle, 2 Hz)
func _hud_snapshot() -> Dictionary:
	var vote := {}
	if not _vote.is_empty():
		vote = {"text": String(_vote["text"]), "yes": (_vote["yes"] as Array).size(), "need": _vote_needed(),
			"left": maxf(float(_vote["until"] - Time.get_ticks_msec()) / 1000.0, 0.0)}
	return {"st": game_state, "t": _match_t, "tl": float(rule("time_limit_min")) * 60.0, "wl": _warm_t,
		"rn": round_no, "rc": int(rule("round_count")), "w": team_wins, "wave": _wave_t if mode() == Mode.OCCUPATION else -1.0,
		"alive": [_team_alive(Soldier.TEAM_ALLIED), _team_alive(Soldier.TEAM_AXIS)], "vote": vote, "obj": obj_done,
		"over": match_over, "pg": _pings()}


func _pings() -> Dictionary:
	var out := {}
	for id in players:
		if int(id) > 1:
			out[int(id)] = peer_ping(int(id))
	return out


@rpc("authority", "call_local", "unreliable_ordered")
func _info(d: Dictionary) -> void:
	hud_info = d
	game_state = int(d.get("st", 0))
	round_no = int(d.get("rn", 1))
	team_wins = d.get("w", [0, 0])


## Meldung an alle (Chat-Zeile „Server“ + Bildschirmmeldung)
func _announce(text: String) -> void:
	_say_all.rpc(text)


@rpc("authority", "call_local", "reliable")
func _say_all(text: String) -> void:
	Events.say(text, 4.0)
	_chat("Server", text, false)


@rpc("authority", "call_remote", "unreliable_ordered")
func _hp(id: int, hp: float) -> void:
	var s: Soldier = _soldiers.get(id)
	if is_instance_valid(s) and s.alive:
		s.health = hp


## Vom Server aufgerufen (Events.soldier_died der Mission)
func on_soldier_died(s: Node, attacker: Node) -> void:
	if not is_online or not multiplayer.is_server() or match_over or not s.has_meta("net_peer"):
		return
	var victim := int(s.get_meta("net_peer"))
	if _soldiers.get(victim) != s:
		return
	var killer := int(attacker.get_meta("net_peer")) if attacker and is_instance_valid(attacker) and attacker.has_meta("net_peer") else 0
	var warm := game_state == State.WARMUP
	# Wiedereinstieg: Aufwärmen immer; sonst nur mit „Respawn erlauben“ (Besetzung: Welle)
	var resp := -1.0
	if warm:
		resp = 3.0
	elif bool(rule("allow_respawn")):
		resp = 0.0 if mode() == Mode.OCCUPATION else float(rule("respawn_s"))
	# Menschen außerhalb des Aufwärmens: nach der Respawn-Zeit „FEUER DRÜCKEN FÜR RESPAWN“ (T7406), sonst nach 3 s
	var press := resp > 0.0 and not warm and victim > 0
	# Kill-Feed: Ursache (Waffen-ID bzw. „fall“) aus dem letzten Treffer, Teamkill vom Server bestimmt
	var tk := killer != 0 and killer != victim and team_mode() and players.has(killer) \
		and int(players[killer]["team"]) == int(players.get(victim, {}).get("team", -1))
	_killed.rpc(victim, killer, resp, String(s.get_meta("last_zone", "")) == "head", press,
		String(s.get_meta("last_cause", "")), tk, s.global_position)
	if resp < 0.0 and players.has(victim) and victim > 0:
		players[victim]["spectator"] = true         # Original 20312: schaltet zum Zuschauermodus
	elif resp == 0.0:
		_respawn[victim] = -1.0      # Welle (alle Respawn-Zeit + 1 s)
	elif resp > 0.0:
		_respawn[victim] = resp + (RESPAWN_AUTO_S if press else 0.0)
		_respawn_ready_ms[victim] = Time.get_ticks_msec() + int(resp * 1000.0)
	# VIP getötet → Aufgabe erfüllt
	var vi := vip_of(victim)
	if vi >= 0 and not warm:
		objective_done(vi)
	if warm:
		_players.rpc(players)
		return
	if players.has(victim):
		players[victim]["deaths"] += 1
	var pts := 0
	if killer != 0 and killer != victim and players.has(killer):
		var same := team_mode() and int(players[killer]["team"]) == int(players.get(victim, {}).get("team", -1))
		pts = PTS_TEAMKILL if same else PTS_KILL
		players[killer]["kills"] += 1 if pts > 0 else 0
		players[killer]["score"] += pts
		if same:
			players[killer]["teamkills"] += 1
			if int(players[killer]["teamkills"]) >= TEAMKILL_KICK and killer > 1:
				kick(killer, tx(8870, "Sie wurden vom Server getrennt, weil Sie Team-Mitglieder getötet haben."),
					tx(8874, "Die Verbindung zu %s wurde aufgrund von Teamkilling beendet."))
		if mode() == Mode.TEAM_DEATHMATCH and int(players[killer]["team"]) in [0, 1]:
			team_score[int(players[killer]["team"])] += pts
	elif players.has(victim):
		players[victim]["score"] += PTS_SUICIDE
	_update_ranks()
	_players.rpc(players)
	var lim := int(rule("score_limit"))
	if lim > 0:
		var best := 0
		if mode() == Mode.TEAM_DEATHMATCH:
			best = maxi(team_score[0], team_score[1])
		else:
			for p in players.values():
				best = maxi(best, int(p["score"]))
		if best >= lim:
			var w := -1
			if mode() == Mode.TEAM_DEATHMATCH:
				w = Soldier.TEAM_ALLIED if team_score[Soldier.TEAM_ALLIED] >= team_score[Soldier.TEAM_AXIS] else Soldier.TEAM_AXIS
			_server_end("Punktelimit erreicht", w)


## Abschussmeldung (Original 8860–8862) und eigener Wiedereinstieg (resp: s, 0 = Welle, < 0 = keiner;
## press: nach resp s Feuer drücken bzw. automatisch nach weiteren RESPAWN_AUTO_S s)
@rpc("authority", "call_local", "reliable")
func _killed(victim: int, killer: int, resp := -1.0, head := false, press := false, cause := "", tk := false,
		pos := Vector3.INF) -> void:
	var s: Soldier = _soldiers.get(victim)
	if is_instance_valid(s) and s.alive and not multiplayer.is_server():
		# Leiche an der Server-Lage: Netzfiguren folgen dem Zustand nur, solange sie leben und ihre Physik läuft (vor
		# nav_ready ruht sie) – sonst bliebe die Leiche z. B. am Spawnpunkt liegen und Durchsuchen schiene „außer Reichweite“
		if s.net_puppet and pos.is_finite():
			s.global_position = pos
			s.net_target = pos
		s.die(_soldiers.get(killer))
	var vn := String(players.get(victim, {}).get("name", "?"))
	var kn := String(players.get(killer, {}).get("name", ""))
	var msg := ""
	var suicide := killer == victim or killer == 0
	# Original-Meldungen T8853 (Sturz), T8855 (Selbstmord), T8859 (Friendly-Fire), T8860 (Kopfschuss), T8861/8862
	if cause == "fall":
		msg = tx(8853, "%s fiel zu Boden und starb!!!").replace("%s", vn)
	elif kn != "" and killer != victim:
		msg = fmt_s(tx(8859 if tk else (8860 if head else 8861), "%s hat %s getötet."), [kn, vn])
	elif killer == victim:
		msg = tx(8855, "%s begeht Selbstmord!!!").replace("%s", vn)
	else:
		msg = tx(8862, "%s wurde getötet.").replace("%s", vn)
	Events.say(msg, 3.0)
	# Kill-Feed (src/ui/mp_feedback.gd): Schütze [Waffensymbol] Opfer, Teamfarben, ~5 s, höchstens 5 Einträge
	kill_feed.append({"text": msg, "killer": killer, "victim": victim, "kname": kn, "vname": vn,
		"kteam": int(players.get(killer, {}).get("team", -1)), "vteam": int(players.get(victim, {}).get("team", -1)),
		"cause": cause, "head": head and not suicide, "tk": tk, "suicide": suicide, "ms": Time.get_ticks_msec()})
	if kill_feed.size() > KILL_FEED_MAX:
		kill_feed.pop_front()
	kill_feed_changed.emit()
	if victim == my_id():
		respawn_press = press
		if resp > 0.0:
			respawn_at = Time.get_ticks_msec() + int(resp * 1000.0)
		elif resp == 0.0:
			respawn_at = -1          # nächste Welle (HUD: hud_info.wave)
		else:
			respawn_at = 0
			Events.say(tx(20312, "Wartet auf Respawn - schaltet zum Zuschauermodus"), 4.0)
		killed_me.emit(killer, cause)        # Kill-Cam (src/ui/kill_cam.gd) entscheidet selbst


var kill_feed: Array = []        ## Einträge (Dictionary, s. _killed), neueste hinten
const KILL_FEED_MAX := 5
signal kill_feed_changed
signal killed_me(killer: int, cause: String)    ## eigener Soldat getötet (alle Rechner, nach Respawn-Zeitpunkt)


# --- Trefferfeedback (serverbestätigt; Anzeige src/ui/mp_feedback.gd) ------------------------------------
## Der Server meldet jeden angewandten Treffer (nach Spawnschutz/Friendly-Fire-Prüfung in Soldier.apply_hit) dem
## Schützen (_hit_confirm: Zone, tödlich, Teamkamerad) und dem Getroffenen (_hurt_from: Lage des Schützen für die
## Richtungsanzeige). Bots erhalten nichts. Waffe des letzten Treffers → Opfer-Meta „last_cause“ (Kill-Feed).
signal hit_confirmed(info: Dictionary)
signal hurt_received(from_pos: Vector3)
var hit_source := ""              ## Server: Ursache des laufenden Treffers („fall“ oder Waffen-ID, z. B. Granate)
var hit_log: Array = []           ## Client: empfangene Trefferbestätigungen (Tests)
var hurt_log: Array = []          ## Client: empfangene Richtungsmeldungen (Tests)


func _on_soldier_damaged(s: Node, amount: float, zone: StringName, attacker: Node) -> void:
	if not is_online or not multiplayer.is_server() or not (s is Soldier) or not s.has_meta("net_peer"):
		return
	var cause := hit_source
	if cause == "" and attacker is Soldier and attacker != s:
		var w: Weapon = (attacker as Soldier).current_weapon()
		cause = String(w.data.id) if w and w.data else ""
	s.set_meta("last_cause", cause)
	if amount <= 0.0 or not (attacker is Soldier) or attacker == s or not attacker.has_meta("net_peer"):
		return
	var victim := int(s.get_meta("net_peer"))
	var shooter := int(attacker.get_meta("net_peer"))
	if victim > 0 and bool(rule("hurt_indicator")):
		_send_feedback(victim, "_hurt_from", [(attacker as Soldier).global_position])
	if shooter > 0 and bool(rule("hit_indicator")):
		var ff := team_mode() and (attacker as Soldier).team == (s as Soldier).team
		_send_feedback(shooter, "_hit_confirm", [victim, String(zone), (s as Soldier).health <= 0.0, ff])


## An einen Spieler senden; der Host (Peer 1) ruft direkt auf (call_remote-RPC erreicht ihn selbst nicht)
func _send_feedback(id: int, fn: String, args: Array) -> void:
	if id == my_id():
		callv(fn, args)
	elif _peer and id > 1:
		callv("rpc_id", [id, StringName(fn)] + args)


@rpc("authority", "call_remote", "reliable")
func _hit_confirm(victim: int, zone: String, killed: bool, ff: bool) -> void:
	var info := {"victim": victim, "name": String(players.get(victim, {}).get("name", "?")), "zone": zone,
		"head": zone == "head", "killed": killed, "ff": ff, "ms": Time.get_ticks_msec()}
	hit_log.append(info)
	if hit_log.size() > 32:
		hit_log.pop_front()
	hit_confirmed.emit(info)


@rpc("authority", "call_remote", "reliable")
func _hurt_from(from_pos: Vector3) -> void:
	hurt_log.append({"pos": from_pos, "ms": Time.get_ticks_msec()})
	if hurt_log.size() > 32:
		hurt_log.pop_front()
	hurt_received.emit(from_pos)


var respawn_press := false     ## eigener Wiedereinstieg wartet nach Ablauf auf die Feuertaste (T7406)


## Respawn-Zeit abgelaufen, Wiedereinstieg per Feuertaste möglich (HUD „FEUER DRÜCKEN FÜR RESPAWN“)
func respawn_ready() -> bool:
	if not respawn_press or respawn_at <= 0 or Time.get_ticks_msec() < respawn_at:
		return false
	var s: Soldier = _soldiers.get(my_id())
	return not is_instance_valid(s) or not s.alive


## Feuertaste nach Ablauf der Respawn-Zeit: sofort wieder einsteigen
func request_respawn() -> void:
	if not is_online or not respawn_ready():
		return
	if multiplayer.is_server():
		_server_respawn_req(my_id())
	else:
		_respawn_req.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _respawn_req() -> void:
	if multiplayer.is_server():
		_server_respawn_req(multiplayer.get_remote_sender_id())


## Server: Feuertaste angenommen, wenn die Respawn-Zeit abgelaufen ist (Spielzeit-Countdown oder Echtzeit – unter
## Last läuft die Physikzeit langsamer als die Uhr des Clients, der „bereit“ nach Echtzeit anzeigt)
var _respawn_ready_ms := {}


func _server_respawn_req(id: int) -> void:
	_touch(id)
	if not _respawn.has(id) or float(_respawn[id]) < 0.0 or match_over:
		return
	if float(_respawn[id]) <= RESPAWN_AUTO_S + 0.05 or Time.get_ticks_msec() >= int(_respawn_ready_ms.get(id, 1 << 60)) - 250:
		_respawn.erase(id)
		_server_spawn(id)


## Original-Formatstring mit %s/%d nacheinander füllen
static func fmt_s(t: String, args: Array) -> String:
	for a in args:
		var i := t.find("%s")
		var j := t.find("%d")
		if i < 0 or (j >= 0 and j < i):
			i = j
		if i < 0:
			break
		t = t.substr(0, i) + str(a) + t.substr(i + 2)
	return t


## Rundenende; winner = Soldier-Team (−1 keins). Siegmeldung 7403/7404 + Siege 8935/8936 (Original 0x699590).
func _server_end(reason: String, winner := -1) -> void:
	if match_over:
		return
	match_over = true
	game_state = State.WON if winner >= 0 else State.ENDED
	_end_t = END_PAUSE_S
	if winner in [0, 1]:
		team_wins[winner] += 1
	_end.rpc(reason, players, team_score, winner, team_wins)


@rpc("authority", "call_local", "reliable")
func _end(reason: String, p: Dictionary, scores: Array, winner := -1, wins: Array = [0, 0]) -> void:
	players = p
	team_score = scores
	team_wins = wins
	match_over = true
	if winner in [0, 1]:
		var axis := winner == Soldier.TEAM_AXIS
		Events.say(tx(7403 if axis else 7404, "GEWONNEN"), 8.0)
		_chat("Server", tx(8933 if axis else 8934, ""), false)
		_chat("Server", "%s %d   %s %d" % [tx(8935, "Siege Achsenmächte:"), int(wins[Soldier.TEAM_AXIS]),
			tx(8936, "Siege Alliierte:"), int(wins[Soldier.TEAM_ALLIED])], false)
	Events.say("Runde beendet: %s" % reason, 8.0)
	_show_board(true)


# --- Punktetabelle (Tab halten; Original 2611–2625) ---------------------------------------

func _process(_delta: float) -> void:
	if watchdog:
		_wd_pump()
		return
	_process_browse()
	if not is_online or Game.current_mission() == null:
		return
	_show_board(match_over or Input.is_action_pressed("soldier_next"))


func board_text() -> String:
	var lines: PackedStringArray = ["%s – %s" % [MODE_NAMES[clampi(mode(), 0, 3)], String(settings.get("name", ""))]]
	lines.append("%s %d / %d" % [tx(2585, "Rundenzahl:"), round_no, int(rule("round_count"))])
	if team_mode():
		lines.append("Alliierte %d : %d Achsenmächte" % [int(team_score[0]), int(team_score[1])])
		lines.append("%s %d   %s %d" % [tx(8936, "Siege Alliierte:"), int(team_wins[0]), tx(8935, "Siege Achsenmächte:"), int(team_wins[1])])
	if mode() == Mode.OCCUPATION and not zone_owner.is_empty():
		lines.append("Zonen: " + " ".join(zone_owner.map(func(o): return "A" if o == Soldier.TEAM_ALLIED else ("X" if o == Soldier.TEAM_AXIS else "–"))))
	# Spalten wie im Original (2611 Spieler Name, 2616 Punkte, 2613 Getötet, 2614 Gestorben, 2612 Ping) + MP-Rang
	lines.append("%-24s %-6s %6s %6s %6s %6s" % [tx(2611, "Spieler Name"), "Rang", tx(2616, "Punkte"), tx(2613, "Getötet"),
		tx(2614, "Gestorben"), tx(2612, "Ping")])
	var ids := players.keys()
	ids.sort_custom(func(a, b): return int(players[a]["score"]) > int(players[b]["score"]))
	for id in ids:
		var p: Dictionary = players[id]
		lines.append("%-24s %-6s %6d %6d %6d %6d" % [String(p["name"]).substr(0, 24), SAS.rank_name(int(p.get("rank", 0)), true).substr(0, 6),
			int(p["score"]), int(p["kills"]), int(p["deaths"]), shown_ping(int(id))])
	return "\n".join(lines)


## Ping für Anzeigen: Server misst selbst, Clients erhalten die Werte mit dem HUD-Zustand (2 Hz)
func shown_ping(id: int) -> int:
	if is_online and multiplayer.is_server():
		return peer_ping(id)
	return int((hud_info.get("pg", {}) as Dictionary).get(id, 0))


func _show_board(on: bool) -> void:
	if not on:
		if _board:
			_board.visible = false
		return
	if _board == null:
		_board = CanvasLayer.new()
		_board.layer = 20
		add_child(_board)
		var p := PanelContainer.new()
		p.set_anchors_preset(Control.PRESET_CENTER)
		p.position = Vector2(-330, -200)
		p.custom_minimum_size = Vector2(660, 0)
		p.theme = UIKit.theme()
		_board.add_child(p)
		_board_label = Label.new()
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		_board_label.add_theme_font_override("font", mono)
		p.add_child(_board_label)
	_board_label.text = board_text()
	_board.visible = true


# --- LAN-Suche (UDP-Broadcast) -------------------------------------------------------------

func start_browse() -> bool:
	stop_browse()
	scan_paused = false
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null
		last_error = "LAN-Suche: Port %d belegt." % DISCOVERY_PORT
		return false
	servers.clear()
	return true


func stop_browse() -> void:
	if _listen:
		_listen.close()
	_listen = null


## Serverinfo (LAN-Broadcast und Antwort auf Abfragen): Name, Karte, Stil, Spieler, KI, Passwort, dediziert,
## Internet, Voice-Codec (Original-Serverliste: Symbole Passwort/dediziert/Voice, T2302–2306)
func server_info() -> Dictionary:
	return {"tag": PROTOCOL, "name": settings.get("name", "DH2-Server"), "map": settings.get("map", ""),
		"map_title": Game.MISSIONS.get(String(settings.get("map", "")), {}).get("title", ""),
		"mode": mode(), "players": humans(), "bots": players.size() - humans(), "max": int(rule("max_players")),
		"port": int(settings.get("port", PORT)), "pw": String(settings.get("password", "")) != "",
		"ded": dedicated, "inet": bool(settings.get("internet", false)), "voice": int(settings.get("voice_codec", 0)),
		"rules": {"round_count": int(rule("round_count")), "time_limit_min": int(rule("time_limit_min")),
			"score_limit": int(rule("score_limit")), "warmup_s": int(rule("warmup_s")), "respawn_s": int(rule("respawn_s")),
			"allow_respawn": bool(rule("allow_respawn")), "friendly_fire": bool(rule("friendly_fire")),
			"team_balance": bool(rule("team_balance")), "third_person": bool(rule("third_person")),
			"spawn_protect_s": int(rule("spawn_protect_s")), "kill_cam": bool(rule("kill_cam")),
			"show_names": bool(rule("show_names")), "hit_indicator": bool(rule("hit_indicator")),
			"hurt_indicator": bool(rule("hurt_indicator"))},
		# Spiel-Info (gameinfo.4ds): Version (Filter „Selbe Version“ T2579), Team-/Spieler-Status, Runde
		"ver": String(ProjectSettings.get_setting("application/config/version")), "ts": [int(team_score[0]), int(team_score[1])],
		"w": team_wins, "rn": round_no, "st": game_state, "plist": _info_players()}


## Spielerliste für die Serverabfrage (Spiel-Info): [Name, Team, Getötet, Punkte, KI]; höchstens 40 Einträge
func _info_players() -> Array:
	var out: Array = []
	for id in players:
		var p: Dictionary = players[id]
		out.append([String(p["name"]).substr(0, 24), int(p["team"]), int(p.get("kills", 0)), int(p.get("score", 0)),
			bool(p.get("bot", false))])
		if out.size() >= 40:
			break
	return out


func _poll_discovery(delta: float) -> void:
	if _bc and multiplayer.is_server():
		_bc_t -= delta
		if _bc_t <= 0.0:
			_bc_t = 1.0
			_bc.put_packet(JSON.stringify(server_info()).to_utf8_buffer())
	_poll_query()


## Server: Abfragen („DH2-QUERY <zeit>“ an Port + 1) mit der Serverinfo beantworten
func _poll_query() -> void:
	if _query == null:
		return
	while _query.get_available_packet_count() > 0:
		var pkt := _query.get_packet().get_string_from_utf8()
		var ip := _query.get_packet_ip()
		var pt := _query.get_packet_port()
		if pkt.begins_with(QUERY_TAG):
			var info := server_info()
			info["qid"] = pkt.substr(QUERY_TAG.length()).strip_edges()
			_query.set_dest_address(ip, pt)
			_query.put_packet(JSON.stringify(info).to_utf8_buffer())


var _query: PacketPeerUDP
var _qsock: PacketPeerUDP
var _q_t := 0.0
var favorites: Array = []      ## „host:port“ (Original FAVORITEN T20100–20103)
var fav_info := {}              ## „host:port“ -> Serverinfo + ping
const FAV_PATH := "user://mp_favorites.json"


func load_favorites() -> void:
	var d = LsRuntime._read_json(ProjectSettings.globalize_path(FAV_PATH))
	favorites = d.get("favorites", []) if typeof(d) == TYPE_DICTIONARY else []


func save_favorites() -> void:
	var f := FileAccess.open(FAV_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"favorites": favorites}, "\t"))


func add_favorite(addr: String) -> void:
	addr = addr.strip_edges()
	if addr == "":
		return
	if not addr.contains(":"):
		addr += ":%d" % PORT
	if not favorites.has(addr):
		favorites.append(addr)
		save_favorites()


func remove_favorite(addr: String) -> void:
	favorites.erase(addr)
	fav_info.erase(addr)
	save_favorites()


## Abfrage senden (Ping/Info); Antwort in _process_browse → servers bzw. fav_info
func query_server(host_addr: String, port: int) -> void:
	if _qsock == null:
		_qsock = PacketPeerUDP.new()
		_qsock.bind(0)
	var ip := host_addr if host_addr.is_valid_ip_address() else IP.resolve_hostname(host_addr, IP.TYPE_IPV4)
	if ip == "":
		return
	_qsock.set_dest_address(ip, port + 1)
	_qsock.put_packet(("%s %d|%s:%d" % [QUERY_TAG, Time.get_ticks_msec(), host_addr, port]).to_utf8_buffer())


func _process_browse() -> void:
	_scan_tick()
	if scan_paused:
		return
	var changed := false
	if _listen != null:
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY and String(d.get("tag", "")).begins_with("DH2-LAN"):     # auch andere Versionen (Filter)
				d["ip"] = ip
				d["seen"] = Time.get_ticks_msec()
				var key := "%s:%d" % [ip, int(d.get("port", PORT))]
				d["ping"] = servers.get(key, {}).get("ping", -1)
				servers[key] = d
				changed = true
		for k in servers.keys():
			if Time.get_ticks_msec() - int(servers[k]["seen"]) > 6000:     # Broadcast 1/s; unter Last großzügig
				servers.erase(k)
				changed = true
	# Ping/Info der LAN-Server und Favoriten alle 2 s abfragen
	if _listen != null or browsing_favorites:
		_q_t -= get_process_delta_time()
		if _q_t <= 0.0:
			_q_t = 2.0
			for k in servers:
				query_server(String(servers[k]["ip"]), int(servers[k].get("port", PORT)))
			if browsing_favorites:
				for a in favorites:
					query_server(String(a).get_slice(":", 0), int(String(a).get_slice(":", 1)) if String(a).contains(":") else PORT)
	if _qsock != null:
		while _qsock.get_available_packet_count() > 0:
			var d = JSON.parse_string(_qsock.get_packet().get_string_from_utf8())
			if typeof(d) != TYPE_DICTIONARY or not String(d.get("tag", "")).begins_with("DH2-LAN"):
				continue
			var q := String(d.get("qid", ""))
			var ping := Time.get_ticks_msec() - int(q.get_slice("|", 0))
			var addr := q.get_slice("|", 1)
			d["ping"] = ping
			d["ip"] = addr.get_slice(":", 0)
			d["seen"] = Time.get_ticks_msec()
			if favorites.has(addr):
				fav_info[addr] = d
			for k in servers:
				if k == addr:
					servers[k]["ping"] = ping
			changed = true
	if changed:
		servers_updated.emit()


var browsing_favorites := false


# --- LISTE NEU EINLESEN / LISTE AKTUALISIEREN (T2325/2327, während des Laufs HALT T2326/2328) ----------------
## Neu einlesen: Liste leeren und LAN-Broadcasts bzw. Favoriten neu sammeln; Aktualisieren: alle bekannten Server
## sofort neu abfragen (Ping/Spieler/Karte). Laufzeit SCAN_S, HALT beendet vorzeitig und hält die Liste an
## (keine weiteren Abfragen, bis wieder gesucht wird). Dauer und Halt-Verhalten [A] (GameSpy-Liste im Original).
signal scan_changed
const SCAN_S := 3.0
var scan_kind := ""              ## "" ruht, "reread" (2325) oder "update" (2327)
var scan_paused := false
var _scan_until := 0


func reread_list() -> void:
	servers.clear()
	fav_info.clear()
	scan_paused = false
	if not browsing_favorites and _listen == null:
		start_browse()
	_q_t = 0.0
	_scan_start("reread")
	servers_updated.emit()


func update_list() -> void:
	scan_paused = false
	_q_t = 0.0
	_scan_start("update")


func halt_scan() -> void:
	scan_kind = ""
	scan_paused = true
	scan_changed.emit()


func _scan_start(kind: String) -> void:
	scan_kind = kind
	_scan_until = Time.get_ticks_msec() + int(SCAN_S * 1000.0)
	scan_changed.emit()


func _scan_tick() -> void:
	if scan_kind != "" and Time.get_ticks_msec() >= _scan_until:
		scan_kind = ""
		scan_changed.emit()


# --- Server-Filter (Original „SERVER-FILTER“ server filters.4ds, hd2.exe 0x638590, T2552–2564/2579) ---------------
## style −1 = ALLE ARTEN (T2890), sonst Mode; max_ping 0 = beliebig; Kästchen: NUR PASSENDE (antwortet auf Abfrage),
## NUR DEDIZIERTE, NUR NICHT-LEERE, NUR NICHT-VOLLE, OHNE PASSWORTE, Selbe Version
const FILTER_PATH := "user://mp_filter.json"
const FILTER_DEFAULTS := {"style": -1, "max_ping": 0, "responding": false, "dedicated": false, "not_empty": false,
	"not_full": false, "no_password": false, "same_version": false}
var server_filter := FILTER_DEFAULTS.duplicate()


func load_filter() -> void:
	server_filter = FILTER_DEFAULTS.duplicate()
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return                  # Tests: immer ungefiltert, gespeicherter Filter bleibt unberührt
	var d = LsRuntime._read_json(ProjectSettings.globalize_path(FILTER_PATH))
	if typeof(d) == TYPE_DICTIONARY:
		for k in FILTER_DEFAULTS:
			if d.has(k):
				server_filter[k] = d[k]


func save_filter() -> void:
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return
	var f := FileAccess.open(FILTER_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(server_filter))


## Serverinfo gegen den Filter prüfen (Liste und Favoriten)
func filter_pass(s: Dictionary, flt: Dictionary = {}) -> bool:
	var f: Dictionary = server_filter if flt.is_empty() else flt
	var offline := bool(s.get("offline", false))
	var ping := int(s.get("ping", -1))
	if bool(f.get("responding", false)) and (offline or ping < 0):
		return false
	if offline:
		return true             # Favorit ohne Antwort: nur „NUR PASSENDE“ blendet ihn aus
	var st := int(f.get("style", -1))
	if st >= 0 and int(s.get("mode", -9)) != st:
		return false
	var mp := int(f.get("max_ping", 0))
	if mp > 0 and ping > mp:
		return false
	if bool(f.get("dedicated", false)) and not bool(s.get("ded", false)):
		return false
	if bool(f.get("not_empty", false)) and int(s.get("players", 0)) <= 0:
		return false
	if bool(f.get("not_full", false)) and int(s.get("players", 0)) >= int(s.get("max", 32)):
		return false
	if bool(f.get("no_password", false)) and bool(s.get("pw", false)):
		return false
	if bool(f.get("same_version", false)) and (String(s.get("tag", PROTOCOL)) != PROTOCOL
			or String(s.get("ver", "")) != String(ProjectSettings.get_setting("application/config/version"))):
		return false
	return true


# --- Internet-Server (Ersatz für GameSpy: UPnP-Portfreigabe, öffentliche IP, Beitritt per IP/Hostname) -------
var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_port := 0


func _upnp_open(port: int) -> void:
	upnp_status = "UPnP: Router wird gesucht …"
	status_changed.emit(upnp_status)
	_upnp_port = port
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(port: int) -> void:
	var u := UPNP.new()
	var res := {"ok": false, "ip": "", "u": null}
	if u.discover(2000, 2) == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		var e1 := u.add_port_mapping(port, port, "Dangerous Hidden 2", "UDP", 0)
		u.add_port_mapping(port + 1, port + 1, "Dangerous Hidden 2 Abfrage", "UDP", 0)
		res = {"ok": e1 == UPNP.UPNP_RESULT_SUCCESS, "ip": u.query_external_address(), "u": u}
	_upnp_done.call_deferred(res)


func _upnp_done(res: Dictionary) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not is_online:
		if res.get("u"):
			(res["u"] as UPNP).delete_port_mapping(_upnp_port, "UDP")
			(res["u"] as UPNP).delete_port_mapping(_upnp_port + 1, "UDP")
		return
	_upnp = res.get("u")
	public_ip = String(res.get("ip", ""))
	if bool(res.get("ok", false)):
		upnp_status = "Internet-Server: Port %d (UDP) per UPnP freigegeben – öffentliche IP %s" % [_upnp_port, public_ip]
	else:
		upnp_status = "UPnP nicht verfügbar – Ports %d und %d (UDP) im Router freigeben. Lokale IP: %s" % [_upnp_port,
			_upnp_port + 1, ", ".join(local_ips())]
	print("NET: ", upnp_status)
	status_changed.emit(upnp_status)
	_chat("Server", upnp_status, false)          # im Spiel als Chatzeile sichtbar


func _upnp_close() -> void:
	if _upnp:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
		_upnp.delete_port_mapping(_upnp_port + 1, "UDP")
	_upnp = null
	public_ip = ""
	upnp_status = ""


static func local_ips() -> PackedStringArray:
	var out: PackedStringArray = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# --- Dedizierter Server (HD2DS-Entsprechung) ------------------------------------------------------------
## Start: Godot … --headless -- --dedicated[=<datei.cfg>]. Datei = Konsolenzeilen wie die Konfigurationen des
## Original-ServerLaunchers (sessionname "…", style deathmatch, mapname …, port 11001, adminlogin/adminpass,
## Regeln, bots n, letzte Zeile „server“). Danach liest die Server-Konsole Befehle von der Standardeingabe.
var _stdin_thread: Thread


func _check_dedicated_cli() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--dedicated" or a.begins_with("--dedicated="):
			_start_dedicated.call_deferred(a.get_slice("=", 1) if a.contains("=") else "")


func _start_dedicated(cfg_path: String) -> void:
	var uargs := OS.get_cmdline_user_args()
	if not uargs.has("--autorestart_child") and (uargs.has("--autorestart") or _cfg_autorestart(cfg_path)):
		_run_watchdog(cfg_path)
		return
	print("HD2 console – Dangerous Hidden 2, dedizierter Server. Type 'help' for keywords list")
	local_name = "Server"
	_cfg_pending = {"dedicated": true}
	if cfg_path != "":
		var r := exec_file(cfg_path, 0)
		if r != "":
			print(r)
	if not is_online and not (_cfg_pending.get("map_list", []) as Array).is_empty():
		print(start_from_console())
	elif not is_online:
		print("Kein Server gestartet: mapname <karte> und server eingeben (listmaps zeigt die Karten).")
	_stdin_thread = Thread.new()
	_stdin_thread.start(_stdin_loop)


func _stdin_loop() -> void:
	# read_string_from_stdin liefert je Aufruf eine Zeile (ohne Zeilenende); mehrere Zeilen trotzdem aufteilen
	while true:
		var s := OS.read_string_from_stdin(1024)
		if s.strip_edges() == "":
			OS.delay_msec(100)
			continue
		for l in s.split("\n", false):
			_console_line.call_deferred(l.strip_edges())


func _console_line(l: String) -> void:
	if l == "":
		return
	if watchdog:
		_wd_forward(l)
		return
	print("> ", l)
	var r := server_command(l, 0)
	if r != "":
		print(r)


## --- autorestart (Original: „hd2ds.exe -autorestart“, Pipe \\.\pipe\autorestart, „HD2AutoRestart“): ein Wächter-
## prozess startet den eigentlichen Server als Kindprozess und startet ihn neu, wenn er unerwartet endet (Absturz);
## Konsole (stdin) und Ausgabe werden durchgereicht; „quit“ beendet beide. Launcher 1062: eindeutiger Sitzungsname.
var watchdog := false
var _wd_cfg := ""
var _wd_pid := 0
var _wd_io: FileAccess
var _wd_err: FileAccess
var _wd_quit := false
var _wd_restarts := 0


static func _cfg_autorestart(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	for l in FileAccess.get_file_as_string(path).split("\n"):
		var w := l.strip_edges().to_lower().split(" ", false)
		if w.size() >= 2 and w[0] == "autorestart":
			return w[1] in ["1", "true", "yes", "on"]
	return false


func _run_watchdog(cfg_path: String) -> void:
	watchdog = true
	_wd_cfg = cfg_path
	print("HD2AutoRestart – Wächter des dedizierten Servers (autorestart 1)")
	_wd_spawn()
	_stdin_thread = Thread.new()
	_stdin_thread.start(_stdin_loop)


func _wd_spawn() -> void:
	var a: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	a.append_array(["--", "--dedicated=" + _wd_cfg, "--autorestart_child"])
	var r := OS.execute_with_pipe(OS.get_executable_path(), a, false)
	_wd_pid = int(r.get("pid", 0))
	_wd_io = r.get("stdio")
	_wd_err = r.get("stderr")
	print("AUTORESTART: Server-Prozess %d gestartet" % _wd_pid)


func _wd_forward(l: String) -> void:
	if l.strip_edges().to_lower() == "quit":
		_wd_quit = true
	if _wd_io:
		_wd_io.store_string(l + "\n")
		_wd_io.flush()


## Wächter-Takt (_process): Ausgabe des Servers durchreichen, Ende erkennen und neu starten
func _wd_pump() -> void:
	for pipe in [_wd_io, _wd_err]:
		if pipe == null:
			continue
		for i in 32:
			var b: PackedByteArray = (pipe as FileAccess).get_buffer(4096)
			if b.is_empty():
				break
			printraw(b.get_string_from_utf8())
	if _wd_pid > 0 and not OS.is_process_running(_wd_pid):
		if _wd_quit:
			print("AUTORESTART: Server beendet (quit) – Wächter endet")
			_wd_pid = 0
			get_tree().quit()
			return
		_wd_restarts += 1
		print("AUTORESTART: Server-Prozess %d unerwartet beendet – Neustart %d" % [_wd_pid, _wd_restarts])
		_wd_spawn()


func _ensure_hud(m: Node) -> void:
	if dedicated or m == null or m.get_node_or_null("MpHud"):
		return
	var h: Node = load("res://src/ui/mp_hud.gd").new()
	h.name = "MpHud"
	m.add_child(h)


# --- Voice-Chat (Codec-Auswahl wie Original T2880–2887; Umsetzung VoiceChat, src/autoload/voice_chat.gd) ----------
## 0 = nicht benutzt. Ohne externe Codecs: μ-law 8 bit, 8 kHz (= 64 kbps, T2887) bzw. 4 kHz (= 32 kbps, T2886);
## die schmaleren Original-Codecs 1–5 werden auf 32 kbps abgebildet (Vereinfachung).
const VOICE_CODECS := [0, 6, 7]


static func voice_codec_from(s: String) -> int:
	s = s.strip_edges().to_lower()
	if s.is_valid_int() and int(s) >= 0 and int(s) <= 7:
		return int(s)
	for i in 8:
		if s != "" and tx(2880 + i, "").to_lower().contains(s):
			return i
	return -1


static func voice_rate(codec: int) -> int:
	return 0 if codec <= 0 else (8000 if codec >= 7 else 4000)


# --- Spielstile: Klassen, Besetzung, HD2-Aufgaben -----------------------------------------------

var _wave_t := 0.0


func _team_alive(t: int) -> int:
	var n := 0
	for id in _soldiers:
		var s: Soldier = _soldiers[id]
		if is_instance_valid(s) and s.alive and s.team == t:
			n += 1
	return n


func _team_players(t: int) -> int:
	return players.values().filter(func(p): return int(p["team"]) == t).size()


## Original-Klassen (mp.json presets, 5 je Seite): Waffe in der Hand + Taschenliste
const CLASS_ORDER := ["gunner", "sniper", "rifleman", "heavy gunner", "assault gunner"]
const CLASS_NAMES := ["MG-Schütze", "Scharfschütze", "Gewehrschütze", "Grenadier", "Sturmschütze", "Schleicher (Schalldämpfer)"]


func _apply_class(m: Node, s: Soldier, team: int, cls: int) -> void:
	if cls == 5:
		# Ergänzung: Schleicher mit Schalldämpferwaffe (Achse: K98k/MP 40 mit Schalldämpfer; Alliierte: De Lisle/Sten),
		# nur kartenerlaubte Waffen; auf allen Rechnern gleich (Auswahl über den Namen statt Zufall)
		var side: String = "axis" if team == Soldier.TEAM_AXIS else "allied"
		var pool := allowed_pool(team, BOT_WEAPONS[side][BotBrain.Role.SNEAKER])
		var h := absi(s.soldier_name.hash())
		var prim = pool[h % pool.size()] if not pool.is_empty() else substitute_allowed(team, WeaponDB.orig_item_of(BOT_WEAPONS[side][BotBrain.Role.SNEAKER][0]))
		var sp := allowed_pool(team, [BOT_SNEAK_SIDEARM[side]] + (BOT_SIDEARM[side] as Array))
		var sarm: int = int(sp[0]) if not sp.is_empty() else -1
		var gr: int = int(BOT_GRENADE[side]) if is_item_allowed(team, BOT_GRENADE[side]) else substitute_allowed(team, int(BOT_GRENADE[side]))
		var kn: int = 57 if side == "allied" else 56
		_apply_kit(s, [prim, sarm, gr, -1, kn if is_item_allowed(team, kn) else -1])
		s.set_meta("mp_class", CLASS_NAMES[5])
		return
	if not m.has_method("mp_presets"):
		return
	var want: String = CLASS_ORDER[clampi(cls, 0, 4)]
	for p in m.mp_presets(team):
		var nm := String(p.get("name", "")).to_lower()
		if not nm.ends_with(want) or (want == "gunner" and (nm.ends_with("heavy gunner") or nm.ends_with("assault gunner"))):
			continue
		var inv := SAS.new_inventory()
		var slots: Array = p.get("slots", [])
		inv["head"] = int(slots[0]["item_id"]) if slots.size() > 0 else -1
		inv["hands"] = int(slots[1]["item_id"]) if slots.size() > 1 else -1
		inv["uniform"] = int(slots[3]["item_id"]) if slots.size() > 3 else -1
		var entries: Array = []
		for it in (p.get("list_a", []) as Array) + (p.get("list_b", []) as Array):
			entries.append([int(it.get("item_id", -1)), int(it.get("count", 1))])
		if map_allowed_known():
			# Original-Regel: Vorlage an das Kartenlager anpassen (Ersatz/Entfall, hd2.exe 0x679B80/0x677620);
			# Ersatzsuche nur unter Achsen-Gegenständen, wenn die Uniform der Achse gehört (Kennung 1)
			var uni := int(inv["uniform"])
			var ad := adapt_preset(p, map_storage(team), uni >= 0 and item_side_flag(uni) == 1)
			inv["hands"] = int(ad["hands"])
			if int(ad["shoulder"]) >= 0:
				inv["shoulder"] = int(ad["shoulder"])
			entries = ad["items"]
			s.set_meta("mp_class_adapt", {"replaced": ad["replaced"], "dropped": ad["dropped"]})
		for it in entries:
			if int(it[0]) >= 0:
				SAS.add_item(inv, int(it[0]), int(it[1]))
		var lo := SAS.to_loadout(inv)
		var ids: Array = lo["loadout"]
		var keep_launcher := s.weapons[WeaponData.Slot.LAUNCHER]
		if keep_launcher and not is_item_allowed(team, keep_launcher.data.id):
			# Standard-Werfer des Nachbaus nur, wenn die Karte einen Werfer der Seite erlaubt (sonst der erlaubte)
			var lorder: Array = [39, 38] if team != Soldier.TEAM_AXIS else [38, 39]
			var lp := allowed_pool(team, lorder)
			keep_launcher = Weapon.new(WeaponDB.from_orig(int(lp[0]), true), false) if not lp.is_empty() else null
			if keep_launcher:
				keep_launcher.in_mag = 1
				keep_launcher.reserve = 2
		var keep_knife := s.weapons[WeaponData.Slot.MELEE]
		s.equip([ids[0], ids[1], ids[2], "", ""])
		s.weapons[WeaponData.Slot.LAUNCHER] = keep_launcher if ids[3] == "" else s.weapons[WeaponData.Slot.LAUNCHER]
		s.weapons[WeaponData.Slot.MELEE] = keep_knife
		for w in s.weapons:
			if w == null or w.data.slot in [WeaponData.Slot.LAUNCHER, WeaponData.Slot.MELEE]:
				continue
			if w.data.slot == WeaponData.Slot.GRENADE:
				w.in_mag = 1 if int(lo["grenades"]) > 0 else 0
				w.reserve = maxi(int(lo["grenades"]) - 1, 0)
			else:
				w.in_mag = w.data.magazine_size
				w.reserve = w.data.magazine_size * int(lo["mags"].get(String(w.data.id), 0))
		s.medkits = maxi(int(lo["medkits"]), 1)
		s.set_meta("orig_items", lo["items"])
		s.set_meta("mp_class", String(p.get("text", p.get("name", ""))))
		s.set_meta("mp_uniform", int(inv["uniform"]))     # Klassen-Uniform → Figur (_attach_figure)
		return


## Einzel-Ausrüstung aus dem SPIELER-SETUP (vom Server geprüft): genau die gewählten Gegenstände – Waffen aus Händen/
## Schulter/Inventar, Magazine/Granaten/Werfergeschosse/Verbandskästen/Sprengstoff/Minen nach Anzahl, Fernglas nur
## wenn eingepackt (wie im Einzelspieler, SAS.to_loadout)
func _apply_inventory(s: Soldier, inv: Dictionary) -> void:
	var lo := SAS.to_loadout(inv)
	var ids: Array = lo["loadout"]
	s.equip([ids[0], ids[1], ids[2], ids[3], ids[4]])
	for w in s.weapons:
		if w == null or w.data.slot == WeaponData.Slot.MELEE:
			continue
		match w.data.slot:
			WeaponData.Slot.GRENADE:
				w.in_mag = 1 if int(lo["grenades"]) > 0 else 0
				w.reserve = maxi(int(lo["grenades"]) - 1, 0)
			WeaponData.Slot.LAUNCHER:
				w.in_mag = 1 if int(lo["launcher_shots"]) > 0 else 0
				w.reserve = maxi(int(lo["launcher_shots"]) - 1, 0)
			_:
				w.in_mag = w.data.magazine_size
				w.reserve = w.data.magazine_size * int(lo["mags"].get(String(w.data.id), 0))
	s.medkits = int(lo["medkits"])
	s.explosives = int(lo["explosives"])
	s.mines = int(lo["mines"])
	s.has_binoculars = bool(lo["binoculars"])
	s.set_meta("orig_items", lo["items"])
	FieldInventory.set_start_order(s, inv)      # Ingame-Inventar (I) in der Reihenfolge der Ausrüstung
	s.set_meta("mp_loadout", inv.duplicate(true))
	s.set_meta("mp_uniform", int(inv.get("uniform", -1)))  # gewählte Uniform → Figur (_attach_figure)
	s.set_meta("mp_class", tx(2535, "Soldaten-Ausrüstung:").trim_suffix(":"))


## Besetzung: Abstand einer Zone zur nächsten nicht eigenen Zone (Front)
func _front_dist(zs: Array, i: int, team: int) -> float:
	var best := 1e9
	for j in zs.size():
		if j < zone_owner.size() and zone_owner[j] != team:
			best = minf(best, (zs[i]["xf"] as Transform3D).origin.distance_to((zs[j]["xf"] as Transform3D).origin))
	return best


static func zone_contains(z: Dictionary, p: Vector3) -> bool:
	var xf: Transform3D = z["xf"]
	if String(z["shape"]) == "box":
		var l: Vector3 = xf.affine_inverse() * p
		var sc: Vector3 = z["scale"]
		return absf(l.x) <= sc.x * 0.5 and absf(l.y) <= sc.y * 0.5 + 2.0 and absf(l.z) <= sc.z * 0.5
	return xf.origin.distance_to(p) <= float(z["radius"])


## Darf team die Zone i angreifen? (FRONTLINE: nur Nachbarzonen der eigenen Zonen)
func _attackable(m: Node, i: int, team: int) -> bool:
	if not m.get("frontline"):
		return true
	for j in [i - 1, i + 1]:
		if j >= 0 and j < zone_owner.size() and zone_owner[j] == team:
			return true
	return false


func _zones_tick(delta: float) -> void:
	var m = Game.current_mission()
	if m == null or not m.has_method("mp_zones"):
		return
	var zs: Array = m.mp_zones()
	if zone_owner.size() != zs.size() or zone_progress.size() != zs.size():
		if zone_owner.size() != zs.size():
			zone_owner = zs.map(func(z): return int(z["owner"]))
		zone_progress = zs.map(func(_z): return 0.0)
		zone_attacker = zs.map(func(_z): return -1)
		_zones.rpc(zone_owner, zone_progress)
	var changed := false
	var may_capture := _match_t >= ZONE_START_DELAY_S     # Original: erst nach Aufwärmzeit + 5 s
	for i in zs.size():
		var z: Dictionary = zs[i]
		if not z["capturable"] or not may_capture:
			continue
		var cnt := [0, 0]
		var present := [[], []]
		for id in _soldiers:
			var s: Soldier = _soldiers[id]
			if is_instance_valid(s) and s.alive and s.team in [0, 1] and zone_contains(z, s.global_position):
				cnt[s.team] += 1
				present[s.team].append(id)
		var owner: int = zone_owner[i]
		var att := -1
		for t in [0, 1]:
			if t != owner and cnt[t] > 0 and cnt[t] > cnt[1 - t] and (owner == -1 or cnt[owner] == 0) and _attackable(m, i, t):
				att = t
		var cap := float(z["capture_time"])
		if att == -1:
			zone_progress[i] = maxf(float(zone_progress[i]) - delta, 0.0)
			continue
		if zone_attacker[i] != att:
			zone_attacker[i] = att
			zone_progress[i] = 0.0
		zone_progress[i] = float(zone_progress[i]) + delta
		# Original: halbe Einnahmezeit → neutral, zweite Hälfte → Besitz des Angreifers
		if owner != -1 and zone_progress[i] >= cap * 0.5:
			zone_owner[i] = -1
			zone_progress[i] = 0.0
			for id in present[att]:
				players[id]["score"] += ZONE_NEUTRALIZE_PTS
			Events.say("%s neutralisiert" % z["text"], 3.0)
			changed = true
		elif owner == -1 and zone_progress[i] >= cap * 0.5:
			zone_owner[i] = att
			zone_progress[i] = 0.0
			for id in present[att]:
				players[id]["score"] += ZONE_CAPTURE_PTS
			Events.say("%s eingenommen (%s)" % [z["text"], ["Alliierte", "Achsenmächte"][att]], 3.0)
			changed = true
	for o in zone_owner:
		if o in [0, 1]:
			team_score[o] += ZONE_TEAM_PTS_PER_S * delta
	if changed:
		_update_ranks()
		_players.rpc(players)
	_zone_sync_t -= delta
	if changed or _zone_sync_t <= 0.0:
		_zone_sync_t = 0.5
		_zones.rpc(zone_owner, zone_progress)
		_scores.rpc(team_score)
	# Ende: Punktelimit, ein Team hält alle Zonen
	var lim := float(rule("score_limit"))
	if lim > 0.0 and maxf(team_score[0], team_score[1]) >= lim:
		_server_end("Punktelimit erreicht", 0 if team_score[0] >= team_score[1] else 1)
	for t in [0, 1]:
		if not zone_owner.is_empty() and zone_owner.all(func(o): return o == t):
			_server_end("%s halten alle Zonen" % ["Alliierte", "Achsenmächte"][t], t)


var _zone_sync_t := 0.0


@rpc("authority", "call_local", "unreliable_ordered")
func _zones(owners: Array, progress: Array) -> void:
	zone_owner = owners
	zone_progress = progress
	var m = Game.current_mission()
	if m == null or not m.has_method("mp_zones") or m.runtime == null:
		return
	var zs: Array = m.mp_zones()
	for i in mini(zs.size(), owners.size()):
		var f: Dictionary = zs[i]["flags"]
		var show := "allied" if owners[i] == Soldier.TEAM_ALLIED else ("axis" if owners[i] == Soldier.TEAM_AXIS else "neutral")
		for side in f:
			var fr: Node3D = m.runtime.find_frame(f[side]) if String(f[side]) != "" else null
			if fr:
				fr.visible = side == show


@rpc("authority", "call_remote", "unreliable_ordered")
func _scores(ts: Array) -> void:
	team_score = ts


## HD2-Aufgaben: Originalskript meldet Aufgabe n erledigt → Punkte für die begünstigte Seite
func objective_done(index: int) -> void:
	if not is_online or not multiplayer.is_server() or match_over or obj_done.has(index) or game_state == State.WARMUP:
		return
	var m = Game.current_mission()
	if m == null or not m.has_method("mp_objectives"):
		return
	for o in m.mp_objectives():
		if int(o["index"]) == index:
			obj_done.append(index)
			team_score[int(o["team"])] += float(o["value"])
			# Original 0x69B900: jeder lebende Spieler des Teams erhält ebenfalls `value` Punkte
			for id in _soldiers:
				var s: Soldier = _soldiers[id]
				if is_instance_valid(s) and s.alive and s.team == int(o["team"]) and players.has(id):
					players[id]["score"] += int(o["value"])
			_update_ranks()
			_players.rpc(players)
			_objective.rpc(index, team_score)
			if obj_done.size() >= m.mp_objectives().size():
				_server_end("Alle Aufgaben erfüllt", int(o["team"]))
			return


@rpc("authority", "call_local", "reliable")
func _objective(index: int, ts: Array) -> void:
	team_score = ts
	if not obj_done.has(index):
		obj_done.append(index)
	var m = Game.current_mission()
	if m and m.has_method("mp_objectives"):
		for o in m.mp_objectives():
			if int(o["index"]) == index:
				var me: Soldier = _soldiers.get(my_id())
				var axis := is_instance_valid(me) and me.team == Soldier.TEAM_AXIS
				Events.say("Aufgabe %d: %s" % [index, o["axis_text"] if axis else o["allied_text"]], 5.0)


# --- KI-Soldaten (Server-Option „KI-Soldaten je Team“) -------------------------------------------
## Laufen nur auf dem Server (BotBrain), Clients sehen Netzfiguren. IDs < 0. Rollen fest im Wechsel:
## Sturmsoldat (schweres MG), Sanitäter (Karabiner), Panzerabwehr (Raketenwerfer), Scharfschütze, Schleicher.
## Waffen zufällig aus der Rolle (Originalgegenstände), Munition passend (Magazine der Waffe).

const BOT_WEAPONS := {
	"allied": {0: [29, 28], 1: [11], 2: [6, 10], 3: [15, 17], 4: [7, 22]},
	"axis": {0: [33, 19], 1: [4], 2: [4, 26], 3: [13], 4: ["kar98k_sd", "mp40_sd"]},
}
## Schleicher: schallgedämpfte Pistole als Seitenwaffe (Achse: Parabellum mit Schalldämpfer 260)
const BOT_SNEAK_SIDEARM := {"allied": 2, "axis": 260}
const BOT_LAUNCHER := {"allied": [39], "axis": [264, 38]}
const BOT_SIDEARM := {"allied": [2, 1], "axis": [0]}
const BOT_GRENADE := {"allied": 62, "axis": 61}
const BOT_NAMES := {"allied": ["Miller", "Baker", "Carter", "Hughes", "Walsh", "Turner", "Brooks", "Reed", "Fisher", "Shaw",
		"Grant", "Doyle", "Hayes", "Lynch", "Murphy", "Price"],
	"axis": ["Becker", "Wagner", "Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Neumann", "Krüger",
		"Braun", "Zimmermann", "Hartmann", "Lange", "Krause", "Vogel"]}
var _bot_groups := {}          ## Team -> Array[Array[BotBrain]]
var _bot_sync_t := 0.0


## Heldenfiguren mit Bestwerten (je Seite höchstens eine; erste KI ihres Teams, am Ende der Figurliste). Im Repository
## gibt es KEINE Helden: sie kommen nur aus lokalen Dateien (nicht im Repository) – user_assets/heroes.json
## ({"heroes": [...]}) bzw. Game.LOCAL_CONTENT („heroes“). Eintrag: team, name, face, face_public, model.
## Gesichtstexturen (zylindrische 256x128-Abwicklung wie die Original-Gesichtstexturen) liegen lokal: user_assets/,
## local/heroes/ oder orig_cache/heroes (vollständige Köpfe aus convert_all.ps1, bevorzugt). Ohne lokale Datei: [].
const DEFAULT_HEROES := []
const LOCAL_HERO_DIR := "res://local/heroes"


static func hero_face_path(file: String) -> String:
	if file == "":
		return ""
	for dir in [ProjectSettings.globalize_path("res://user_assets"), ProjectSettings.globalize_path(LOCAL_HERO_DIR),
			OrigLevel.cache_root() + "/heroes"]:
		if FileAccess.file_exists(dir + "/" + file):
			return dir + "/" + file
	return ""


static func heroes() -> Array:
	var d = LsRuntime._read_json(ProjectSettings.globalize_path("res://user_assets/heroes.json"))
	if typeof(d) == TYPE_DICTIONARY and d.has("heroes"):
		return d["heroes"]
	var lc := Game.read_local_content()
	if lc.has("heroes"):
		return lc["heroes"]
	return DEFAULT_HEROES


# --- Figurwahl (SPIELER-SETUP „Militärische Kräfte“, player screen.4ds) ---------------------------------------
## Figuren: die beiden Helden (eigenes Modell + Gesicht) und die MP-Figuren „MP 1…27“ (HumanStore 30–56: nur das
## Gesicht e_fNNN wechselt, Körper = Modell der Seite, roster.json „face_texture“). Spielerwahl = players[id]["figure"].
static func figure_ids() -> Array:
	var out: Array = []
	for i in range(30, 57):
		if String(SAS.store(i).get("category", "")) == "mp_slot":
			out.append("mp:%d" % i)
	for h in heroes():              # Vorgabe Auftraggeber 16.10.2026: Helden ganz hinten (nach „MP 1…27“)
		out.append("hero:" + String(h.get("team", "")))
	return out


static func hero_of(side: String) -> Dictionary:
	for h in heroes():
		if String(h.get("team", "")) == side:
			return h
	return {}


static func figure_name(fig: String) -> String:
	if fig.begins_with("hero:"):
		return String(hero_of(fig.substr(5)).get("name", "Held"))
	if fig.begins_with("mp:"):
		var s := SAS.store(int(fig.substr(3)))
		return "%s %s" % [s.get("first_name", "MP"), s.get("last_name", "")]
	return ""


## Seite, zu der eine Figur gehört ("" = beide)
static func figure_side(fig: String) -> String:
	return fig.substr(5) if fig.begins_with("hero:") else ""


## Modell der Figur auf einer Seite (Helden: eigenes Modell ihrer Armee)
static func figure_model(fig: String, side: String) -> String:
	if fig.begins_with("hero:"):
		return String(hero_of(fig.substr(5)).get("model", MP_UNIFORM_MODEL.get(side, "en08")))
	return String(MP_UNIFORM_MODEL.get(side, "en08"))     # MP-Figur: Gesicht auf der MP-Standarduniform


## Gesichtstextur der Figur (Held: lokale Gesichter, siehe hero_face_path; exportierter Build: importierte
## Textur unter LOCAL_HERO_DIR; MP-Figur: Original-Gesicht e_fNNN aus orig_cache/textures)
static func figure_face(fig: String) -> Texture2D:
	var path := ""
	if fig.begins_with("hero:"):
		var h := hero_of(fig.substr(5))
		var face := String(h.get("face", ""))
		path = hero_face_path(face)
		var pub := String(h.get("face_public", ""))
		if path == "":
			path = hero_face_path(pub)
		if path == "" and pub != "" and ResourceLoader.exists(LOCAL_HERO_DIR + "/" + pub):
			return load(LOCAL_HERO_DIR + "/" + pub)
	elif fig.begins_with("mp:"):
		var ft := String(SAS.store(int(fig.substr(3))).get("face_texture", "")).to_lower()
		if ft != "" and FileAccess.file_exists(OrigLevel.cache_root() + "/textures/%s.png" % ft):
			path = OrigLevel.cache_root() + "/textures/%s.png" % ft
	if path == "":
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img else null


## Gesichtstextur auf alle Original-Gesichtsmaterialien (Präfix „E_F0“, Tausch wie hd2.exe 0x48A5C0) setzen
static func apply_face(fig: Node3D, tex: Texture2D) -> void:
	if fig == null or tex == null:
		return
	for mi in fig.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(si) as StandardMaterial3D
			if mat and mat.resource_name.to_upper().begins_with("E_F0"):
				var nm := mat.duplicate() as StandardMaterial3D
				nm.albedo_texture = tex
				(mi as MeshInstance3D).set_surface_override_material(si, nm)


## Figur wählen (gilt ab dem nächsten Spawn; vor dem Beitritt: wird bei der Anmeldung übertragen)
func request_figure(fig: String) -> void:
	local_figure = fig
	if not is_online:
		return
	if multiplayer.is_server():
		if players.has(1):
			players[1]["figure"] = fig
			_players.rpc(players)
	else:
		_figure_req.rpc_id(1, fig)


@rpc("any_peer", "call_remote", "reliable")
func _figure_req(fig: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and (fig == "" or figure_ids().has(fig)):
		players[id]["figure"] = fig
		_players.rpc(players)


func _add_bots() -> void:
	var n := clampi(int(settings.get("bots_per_team", 0)), 0, 16)
	if n <= 0:
		return
	var hs := heroes()
	var next_id := -1
	for k in players.keys():
		if int(k) < 0:
			next_id = mini(next_id, int(k) - 1)
	var teams: Array = [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]
	for ti in 2:
		for i in n:
			var side := "allied" if teams[ti] == Soldier.TEAM_ALLIED else "axis"
			var team: int = teams[ti] if team_mode() else 10 + players.size()
			var nm := "%s %s" % ["Pvt." if side == "allied" else "Gefr.", BOT_NAMES[side][i % BOT_NAMES[side].size()]]
			var hero := false
			if i == 0:
				for h in hs:
					if String(h.get("team", "")) == side:
						nm = String(h.get("name", nm))
						hero = true
			players[next_id] = {"name": nm, "team": team, "kills": 0, "deaths": 0, "score": 0, "teamkills": 0,
				"cls": 0, "spectator": false, "bot": true, "role": i % 5, "hero": hero, "side": side}
			next_id -= 1
	_players.rpc(players)
	for id in players.keys():
		if int(id) < 0:
			_server_spawn(int(id))


## Zufällige Rollenwaffe mit passender Munition: [Primär, Pistole, Granate, Raketenwerfer, Messer] (Original-IDs).
## Nur auf der Karte erlaubte Gegenstände der eigenen Seite (map_allowed_items); fehlt die Rollenwaffe, wählt die
## Original-Ersatzregel (orig_substitute) die nächstbeste erlaubte Waffe; ohne erlaubten Werfer kein Werfer.
func bot_kit(team: int, role: int, hero: bool) -> Array:
	var side: String = "axis" if team == Soldier.TEAM_AXIS else ("allied" if team == Soldier.TEAM_ALLIED else ["allied", "axis"][randi() % 2])
	var t: int = Soldier.TEAM_AXIS if side == "axis" else Soldier.TEAM_ALLIED
	var want: Array = BOT_WEAPONS[side][role]
	var pool := allowed_pool(t, want)
	var primary = pool[randi() % pool.size()] if not pool.is_empty() else substitute_allowed(t, WeaponDB.orig_item_of(want[0]))
	var lpool: Array = allowed_pool(t, BOT_LAUNCHER[side]) if role == BotBrain.Role.AT else []
	var launcher: int = int(lpool[randi() % lpool.size()]) if not lpool.is_empty() else -1
	var sneak_arm: Array = [BOT_SNEAK_SIDEARM[side]] if role == BotBrain.Role.SNEAKER else []
	var spool: Array = allowed_pool(t, sneak_arm)
	if spool.is_empty():
		spool = allowed_pool(t, BOT_SIDEARM[side])
	var side_arm: int = int(spool[randi() % spool.size()]) if not spool.is_empty() else substitute_allowed(t, int(BOT_SIDEARM[side][0]))
	var gren: int = int(BOT_GRENADE[side]) if is_item_allowed(t, BOT_GRENADE[side]) else substitute_allowed(t, int(BOT_GRENADE[side]))
	var knife: int = 57 if side == "allied" else 56
	if not is_item_allowed(t, knife):
		knife = 56 if knife == 57 else 57
		knife = knife if is_item_allowed(t, knife) else -1
	return [primary, side_arm, gren, launcher, knife]


# --- Kartenfreigabe ALLOWEDITEMS (mpmaplist v1.12, docs/re_notes_multiplayer.md §1.7a) ----------------
## Seitenkennung items.sav +0x7C (hd2.exe Gegenstand +0x44, Lader 0x7DFCF0): 0 Alliierte, 1 Achse, 2 beide, 3 nicht
## wählbar (Bordwaffen/Geschütze). Der Nachbau ordnet erlaubte Gegenstände damit den Seiten zu [B Daten, P Zuordnung].
static func item_side_flag(item: int) -> int:
	if WeaponDB.EXTRA_ITEMS.has(item):
		return int(WeaponDB.EXTRA_ITEMS[item].get("team_flag", 2))
	return int(OrigInteractive.item_info(item).get("team_flag", 2))


static func _side_ok(team: int, item: int) -> bool:
	var f := item_side_flag(item)
	return f == 2 or (f == 1 and team == Soldier.TEAM_AXIS) or (f == 0 and team != Soldier.TEAM_AXIS)


## Eigene Karten ohne Original-Freigabeliste: Vorgabe [D] = Liste einer passenden Original-MP-Karte, im
## Missionsregister als "mp_allowed_from" (Game.mp_allowed_from) eingetragen.
var _custom_allowed_cache := {}


## Freigabeliste (ALLOWEDITEMS-Einträge) der aktuellen Karte; leer = keine
func _current_allowed() -> Array:
	var m = Game.current_mission()
	if m != null and m.has_method("mp_allowed_known") and bool(m.mp_allowed_known()):
		return m.mp_allowed_items()
	var mid: String = String(settings.get("map", "")) if is_online else ""
	var folder: String = Game.mp_allowed_from(mid) if mid != "" else ""
	if folder != "":
		if not _custom_allowed_cache.has(folder):
			var d = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/mp.json")
			var lst: Array = []
			if typeof(d) == TYPE_DICTIONARY and not (d.get("game_styles", []) as Array).is_empty():
				lst = d["game_styles"][0].get("allowed_items", [])
			_custom_allowed_cache[folder] = lst
		return _custom_allowed_cache[folder]
	return []


## Hat die aktuelle Karte eine Freigabeliste? (Original-MP-Karten ja, eigene Karten mit "mp_allowed_from"; Kampagnenkarten
## als Arena nein = unbeschränkt)
func map_allowed_known() -> bool:
	return not _current_allowed().is_empty()


## Erlaubte Gegenstände (Original-Nummern) der aktuellen Karte für eine Seite – Schnittstelle für Inventar,
## Spieler-Setup und KI. Ohne Freigabeliste (map_allowed_known() = false): leer = unbeschränkt.
func map_allowed_items(team: int) -> Array:
	return allowed_of(_current_allowed(), team)


## Lager der Karte (Original-MP-Lager, 0x6A5C30): Gegenstand → Anzahl aus item_num, Munition ammo_item → ammo_num
## [B Liste, P Bedeutung ammo_num]. side_only: nur Gegenstände der eigenen Seite.
func map_storage(team: int, side_only := false) -> Dictionary:
	return storage_of(_current_allowed(), team, side_only)


## Dieselben Auswertungen für eine beliebige ALLOWEDITEMS-Liste (mp.json „allowed_items“; Tests/Werkzeuge)
static func allowed_of(allowed: Array, team: int) -> Array:
	var out: Array = []
	for e in allowed:
		var id := int(e.get("item_id", -1))
		if id >= 0 and _side_ok(team, id) and not out.has(id):
			out.append(id)
	return out


static func storage_of(allowed: Array, team: int, side_only := false) -> Dictionary:
	var st := {}
	for e in allowed:
		var id := int(e.get("item_id", -1))
		if id < 0 or (side_only and not _side_ok(team, id)):
			continue
		st[id] = int(st.get(id, 0)) + maxi(int(e.get("item_num", 1)), 1)
		var am := int(e.get("ammo_item", OrigInteractive.item_info(id).get("ammo_item", -1)))
		if am >= 0 and int(e.get("ammo_num", -1)) > 0:
			st[am] = int(st.get(am, 0)) + int(e["ammo_num"])
	return st


## Darf die Seite den Gegenstand/die Waffe auf dieser Karte nutzen? Eigene Varianten zählen als Grundmodell
## (kar98k_sd → K98k 4, mp40_sd → MP 40 18; Vorgabe Auftraggeber). Ohne Freigabeliste immer erlaubt.
func is_item_allowed(team: int, item) -> bool:
	if not map_allowed_known():
		return true
	var id := WeaponDB.orig_item_of(item)
	if id < 0:
		return false
	if id == WeaponDB.PANZERFAUST_AMMO:
		id = 38
	return map_allowed_items(team).has(id)


## Teilmenge einer Waffenliste (Original-Nummern oder eigene IDs), die auf der Karte für die Seite erlaubt ist
func allowed_pool(team: int, pool: Array) -> Array:
	return pool.filter(func(x): return is_item_allowed(team, x))


## Nächstbeste erlaubte Waffe der eigenen Seite nach der Original-Ersatzregel (−1 = keine)
func substitute_allowed(team: int, wanted: int) -> int:
	if wanted < 0:
		return -1
	if is_item_allowed(team, wanted):
		return wanted
	return orig_substitute(wanted, map_storage(team, true), false, 0)


## Original-Ersatzregel (hd2.exe 0x679850, aufgerufen aus der Vorlagen-Anpassung 0x679B80): sucht im Lager die
## beste Alternative zum gewünschten Gegenstand. Kandidaten: Lagerbestand > 0, bei Achsen-Uniform nur Gegenstände
## mit Seitenkennung 1 (axis_only). Punkte: derselbe Gegenstand +51; gleicher Typ (items.sav Typfeld, hd2.exe
## Gegenstand +0x5C: 2 Pistole, 3 MP, 4 Gewehr, 5 MG, 12 Sturmgewehr, 6 Werfer, 9 Granate …) +100, beide mit
## Zielfernrohr +150, beide schallgedämpft (7/22/260) +160; sonst bei Handwaffentypen (< 7 oder 12) je Kandidatentyp
## 2: +30, 3/4: +60, 5: +50 (+111 für gewünschtes Sturmgewehr), 12: +50, sonst +10, beide schallgedämpft +110.
## Munitionsbedarf need > 0: Lagermunition < need → (n − need)·10, sonst +30, keine → −100. Höchste Punktzahl > 0
## gewinnt; Munitionsgegenstände werden nie ersetzt. Rückgabe: Ersatz (gleich wanted = behalten) oder −1 = entfällt.
static func orig_substitute(wanted: int, storage: Dictionary, axis_only: bool, need := 0) -> int:
	var wi := OrigInteractive.item_info(wanted)
	if wi.is_empty() or String(wi.get("kind", "")) == "ammo":
		return wanted
	var wt := _item_type(wi)
	var best := -1
	var best_sc := -2147483648
	for k in storage:
		var id := int(k)
		if int(storage[k]) <= 0 or id < 0 or id >= 500:
			continue
		var ci := OrigInteractive.item_info(id)
		if ci.is_empty() or String(ci.get("kind", "")) == "ammo":
			continue
		if axis_only and int(ci.get("team_flag", 2)) != 1:
			continue
		var sc: int = 51 if id == wanted else 0
		var ct := _item_type(ci)
		var both_sd: bool = id in [22, 7, 260] and wanted in [22, 7, 260]
		if ct == wt and wt != 0x13:
			if wt == 4 and _scoped(wi) and _scoped(ci):
				sc += 150
			else:
				sc += 160 if both_sd else 100
		elif (wt < 7 or wt == 12) and (ct < 7 or ct == 12):
			match ct:
				2:
					sc += 30
				3, 4:
					sc += 60
				5:
					sc += 111 if wt == 12 else 50
				12:
					sc += 50
				_:
					sc += 10
			if both_sd:
				sc += 110
		var am := int(ci.get("ammo_item", -1))
		if ct < 13 and am >= 0 and need > 0:
			var n := int(storage.get(am, 0))
			sc += (n - need) * 10 if n < need else 30
			if n == 0:
				sc -= 100
		if sc > best_sc and sc > 0:
			best_sc = sc
			best = id
	return best


## items.sav Typfeld (Gegenstand +0x5C, virtuell +0x10; in items.json „inv_h“, Ausrüstung equip_raw[1])
static func _item_type(it: Dictionary) -> int:
	if String(it.get("kind", "")) == "weapon":
		return int(it.get("inv_h", 0))
	var eq = it.get("equip_raw", [])
	return int(eq[1]) if eq is Array and (eq as Array).size() > 1 else 0


## Zielfernrohr: Verhalten Code 5 (Zoom) mit Overlay < 4 (0x679850: Verhalten +8 == 4 und +0xC < 4)
static func _scoped(it: Dictionary) -> bool:
	for b in it.get("behaviours", []):
		if int(b.get("code", 0)) == 5:
			var raw: Array = b.get("raw_u32", [])
			return raw.size() > 2 and int(raw[2]) < 4
	return false


## Original-Vorlagenanpassung (0x679B80 + Ausrüsten 0x677620/0x67BDD0): jeder Gegenstand der Klasse wird nach
## orig_substitute ersetzt (Waffen in Hand/Schulter mit Munitionsbedarf, abhängige Munition folgt der Ersatzwaffe)
## und dann nur in der verfügbaren Lagermenge übernommen; nicht verfügbare Gegenstände entfallen.
## Rückgabe: {"hands", "shoulder", "head", "items": [[id, n], …], "replaced": {alt: neu}, "dropped": [ids]}.
## Ohne Lager (Karte ohne Freigabeliste) unverändert übernehmen: storage leer → Aufrufer nutzt die Vorlage direkt.
static func adapt_preset(p: Dictionary, storage: Dictionary, axis_only: bool) -> Dictionary:
	var st := storage.duplicate()
	var slots: Array = p.get("slots", [])
	var lists: Array = (p.get("list_a", []) as Array) + (p.get("list_b", []) as Array)
	var ammo_map := {}
	# Kopf: gehört zur Uniform (items.sav Uniform equip_raw[3] = Standardhelm, z. B. GE03 → 76), nicht aus dem Lager
	var res := {"hands": -1, "shoulder": -1, "head": int(slots[0]["item_id"]) if slots.size() > 0 else -1,
		"items": [], "replaced": {}, "dropped": []}
	for si in [[1, "hands"], [2, "shoulder"]]:
		var want: int = int(slots[si[0]]["item_id"]) if slots.size() > int(si[0]) else -1
		if want < 0:
			continue
		var need := 0
		var am := int(OrigInteractive.item_info(want).get("ammo_item", -1))
		if si[0] in [1, 2] and am >= 0:
			for it in lists:
				if int(it.get("item_id", -1)) == am:
					need += int(it.get("count", 1))
		var got := orig_substitute(want, st, axis_only, need)
		if got != want and got >= 0:
			res["replaced"][want] = got
			var nam := int(OrigInteractive.item_info(got).get("ammo_item", -1))
			if am >= 0 and nam >= 0:
				ammo_map[am] = nam
		if got >= 0 and int(st.get(got, 0)) > 0:
			st[got] = int(st[got]) - 1
			res[si[1]] = got
		else:
			res["dropped"].append(want)
	for it in lists:
		var id := int(it.get("item_id", -1))
		var n := int(it.get("count", 1))
		if id < 0:
			continue
		var got := int(ammo_map.get(id, -1))
		if got < 0:
			got = orig_substitute(id, st, axis_only, 0)
			if got != id and got >= 0:
				res["replaced"][id] = got
		var take: int = mini(n, int(st.get(got, 0))) if got >= 0 else 0
		if take <= 0:
			res["dropped"].append(id)
			continue
		st[got] = int(st[got]) - take
		res["items"].append([got, take])
	return res


func _apply_kit(s: Soldier, kit: Array) -> void:
	var ids: Array = []
	for i in 5:
		var e = kit[i] if i < kit.size() else -1
		var wd: WeaponData = null
		if e is String:
			wd = WeaponDB.get_weapon(StringName(e))       # eigene Waffe (z. B. MP 40 mit Schalldämpfer)
		elif int(e) >= 0:
			wd = WeaponDB.from_orig(int(e), true)
		ids.append(String(wd.id) if wd else "")
	# Primärwaffe muss in Platz 0 (z. B. MP 40 als Schleicherwaffe), Pistole in Platz 1
	s.equip(ids)
	for w in s.weapons:
		if w and w.data.slot == WeaponData.Slot.GRENADE:
			w.reserve = 1
	s.set_meta("orig_items", kit.filter(func(x): return x is int and x >= 0))


## Originalfigur je Seite; Held: eigenes Modell und lokale Gesichtstextur (hero_face_path)
func _attach_figure(m: Node, s: Soldier, team: int, p: Dictionary) -> void:
	var orig = m.get("orig")          # null auf eigenen Karten ohne Original-Ordner → character_figure
	var side := String(p.get("side", "axis" if team == Soldier.TEAM_AXIS else "allied"))
	# Körper = Uniform der Klasse/Ausrüstung (Gegenstand → items.json „model“), sonst MP-Standarduniform der Seite
	var model := String(MP_UNIFORM_MODEL.get(side, "en08"))
	var um: String = uniform_model(int(s.get_meta("mp_uniform", -1))) if is_instance_valid(s) else ""
	if um != "":
		model = um
	var face := ""
	if bool(p.get("hero", false)):
		for h in heroes():
			if String(h.get("team", "")) == side:
				model = String(h.get("model", model))
				face = String(h.get("face", ""))
				if hero_face_path(face) == "":
					face = String(h.get("face_public", face))
	# Spieler: Figurwahl aus dem SPIELER-SETUP (Held der eigenen Armee bzw. MP-Gesicht); Bots behalten ihre Helden
	var pfig := String(p.get("figure", ""))
	var fig_tex: Texture2D = null
	if not bool(p.get("hero", false)) and pfig != "":
		var f2 := pfig
		if pfig.begins_with("hero:") and figure_side(pfig) != side:
			f2 = "hero:" + side
		if f2.begins_with("hero:"):
			model = figure_model(f2, side)         # Held: eigenes Modell; MP-Figur: nur Gesicht auf der Uniform
		fig_tex = figure_face(f2)
	var fig: Node3D = null
	if String(p.get("model", "")) != "":
		fig = character_figure(orig, String(p["model"]))       # VIP-Uniform (z. B. ge14)
	if fig == null:
		fig = character_figure(orig, model)
	if fig == null:
		return
	var fp := hero_face_path(face) if face != "" else ""
	var tex: Texture2D = null
	if fp != "":
		var img := Image.load_from_file(fp)
		if img:
			tex = ImageTexture.create_from_image(img)
	elif face != "" and ResourceLoader.exists(LOCAL_HERO_DIR + "/" + face):
		tex = load(LOCAL_HERO_DIR + "/" + face)                  # exportierter Build: importierte Textur
	if fig_tex:
		tex = fig_tex
	if tex:
		for mi in fig.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for si in mesh.get_surface_count():
				var mat := (mi as MeshInstance3D).get_active_material(si) as StandardMaterial3D
				if mat and mat.resource_name.to_upper().begins_with("E_F0"):
					var nm := mat.duplicate() as StandardMaterial3D
					nm.albedo_texture = tex
					(mi as MeshInstance3D).set_surface_override_material(si, nm)
	s.model.attach_orig(fig)


## MP-Standarduniform je Seite = Uniform der Original-Klassenvorlagen (mp.json presets aller 30 Original-MP-Karten:
## Alliierte Gegenstand 123 „Uniform EN08“, Achse 129 „Uniform GE03“). Früher ge01a/en01 (Winteruniformen der Arktis).
const MP_UNIFORM_MODEL := {"axis": "ge03", "allied": "en08"}


## Figurmodell eines Uniform-Gegenstands (items.json „model“, z. B. 129 → ge03); "" ohne Uniform/Figurdatei
static func uniform_model(item: int) -> String:
	if item < 0 or not SAS.available():
		return ""
	var mdl := String(SAS._item_data().get(item, {}).get("model", "")).to_lower()
	if mdl == "" or not FileAccess.file_exists("%s/characters/%s.glb" % [OrigLevel.cache_root(), mdl]):
		return ""
	return mdl


## Original-Figur (orig_cache/characters/<modell>.glb). Original-Karten: über ihr OrigLevel (Vorlagen-Cache);
## eigene Karten ohne Original-Ordner (kein `orig`): dieselbe Datei über den Vorlagenspeicher des
## MissionLoader (Kopie je Spawn), damit Spieler/Bots dort dieselben Figuren wie auf Original-MP-Karten tragen.
static func character_figure(orig, model: String) -> Node3D:
	if orig != null:
		return orig.character_instance(model)
	var path := "%s/characters/%s.glb" % [OrigLevel.cache_root(), model.to_lower()]
	var n := MissionLoader.take(path)
	if n == null:
		n = OrigLevel.parse_glb(path)
		MissionLoader.remember(path, n)
	return n


func _make_bot(s: Soldier, id: int) -> void:
	var p: Dictionary = players[id]
	var role := int(p.get("role", 0))
	var b := BotBrain.new()
	b.name = "EnemyBrain"
	b.role = role
	var hero := bool(p.get("hero", false))
	# Treffsicherheit/Reaktion je Rolle (wie Einzelspieler-Gegner, keine Zielhilfe)
	b.accuracy_skill = [0.4, 0.4, 0.35, 0.6, 0.45][role] if not hero else 0.8
	b.reaction_time = [0.7, 0.8, 0.8, 1.0, 0.6][role] if not hero else 0.4
	s.add_child(b)
	b.setup(s)
	if role == BotBrain.Role.MEDIC:
		s.medkits = 3
	if hero:
		# beste Werte (Original-Höchstwerte 100)
		s.skill_shooting = 100.0
		s.skill_stealth = 100.0
		s.skill_endurance = 100.0
		s.skill_first_aid = 100.0
		s.max_health = 150.0
		s.health = 150.0
		s.medkits = maxi(s.medkits, 2)
	s.net_hook = func(kind: String, a: Vector3, bb: Vector3, wid: String): _bact.rpc(id, kind, a, bb, wid)
	# Gruppe (bis 4) im Team
	var team := s.team
	if not _bot_groups.has(team):
		_bot_groups[team] = []
	var gs: Array = []
	for g in _bot_groups[team]:
		var alive: Array = g.filter(func(x): return is_instance_valid(x) and x.soldier and x.soldier.alive)
		if not alive.is_empty():
			gs.append(alive)
	var grp: Array = []
	for g in gs:
		if g.size() < 4:
			grp = g
			break
	if grp.is_empty():
		gs.append(grp)
	grp.append(b)
	_bot_groups[team] = gs
	for i in grp.size():
		grp[i].group = grp
		grp[i].slot = i


func _bot_sync(delta: float) -> void:
	_bot_sync_t -= delta
	if _bot_sync_t > 0.0:
		return
	_bot_sync_t = SYNC_INTERVAL
	for id in _soldiers:
		if int(id) >= 0:
			continue
		var s: Soldier = _soldiers[id]
		if is_instance_valid(s) and s.alive:
			_bst.rpc(int(id), s.global_position, s.velocity, s.look_yaw, s.look_pitch, s.stance, s.current_slot, s.aiming)


@rpc("authority", "call_remote", "unreliable_ordered")
func _bst(id: int, pos: Vector3, vel: Vector3, yaw: float, pitch: float, stance: int, slot: int, aiming: bool) -> void:
	var s: Soldier = _soldiers.get(id)
	if not is_instance_valid(s) or not s.alive:
		return
	s.net_target = pos
	s.net_velocity = vel
	s.look_yaw = yaw
	s.look_pitch = pitch
	s.stance_request = stance
	s.aiming = aiming
	if slot != s.current_slot and slot < s.weapons.size() and s.weapons[slot] != null:
		s.current_slot = slot
		s._on_weapon_switched()


@rpc("authority", "call_remote", "reliable")
func _bact(id: int, kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	var s: Soldier = _soldiers.get(id)
	if is_instance_valid(s) and s.alive:
		_do_act(s, kind, a, b, wid)


func used_interactable_by(s: Soldier, it: Node) -> void:
	if not is_online or not multiplayer.is_server() or not s.has_meta("net_peer"):
		return
	var pid := String(it.get("persistent_id")) if it.get("persistent_id") != null else String(it.get_path())
	_use_by.rpc(int(s.get_meta("net_peer")), pid)


@rpc("authority", "call_remote", "reliable")
func _use_by(id: int, pid: String) -> void:
	var s: Soldier = _soldiers.get(id)
	if not is_instance_valid(s):
		return
	for n in get_tree().get_nodes_in_group("interactables"):
		var p = n.get("persistent_id")
		if (p != null and String(p) == pid) or String(n.get_path()) == pid:
			if n.has_method("net_state"):
				return       # Türen: Zustand kommt über object_state
			n.interact(s)
			return


## Spielziel für einen KI-Gruppenführer (Server): Zielwahl in BotGoals (Zonen angreifen/verteidigen/halten nach
## Weglänge über das Netz, Aufgabenobjekte benutzen/verteidigen, Gegner suchen; Netzpunkt, kein Pendeln)
func bot_goal(b: BotBrain) -> Vector3:
	var r := BotGoals.choose(b)
	var best: Dictionary = r.get("best", {})
	return best["pos"] if not best.is_empty() else Vector3.INF


## Ziel auf das Navigationsnetz legen (erreichbarer Punkt)
func _on_nav(b: BotBrain, p: Vector3) -> Vector3:
	var map := b.soldier.get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, p)
	return q if q != Vector3.ZERO or p.length() < 1.0 else p
