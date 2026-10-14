extends Node
## Mehrspieler im LAN – OHNE DirectPlay (Vorgabe Auftraggeber): Godot-ENet (UDP, Port 27100) mit der
## High-Level-API (RPC), LAN-Serversuche per eigenem UDP-Broadcast (Port 27101).
##
## Server-Autorität: Der Server (Spieler 1) berechnet Treffer, Schaden, Tod, Punkte, Respawn und Spielende.
## Jeder Spieler steuert seinen eigenen Soldaten und sendet dessen Zustand (20 Hz) sowie Aktionen
## (Schuss, Rakete, Granate, Messer, Ladung) – alle Rechner stellen diese dar, nur der Server wertet aus.
## Alle RPCs liegen hier (Autoload /root/Net), damit die Knotenpfade auf allen Rechnern gleich sind.

const PORT := 27100
const DISCOVERY_PORT := 27101
const PROTOCOL := "DH2-LAN-1"
const SYNC_INTERVAL := 0.05
enum Mode { DEATHMATCH, TEAM_DEATHMATCH, OCCUPATION }
const MODE_NAMES := ["Deathmatch", "Team-Deathmatch", "Besetzung"]

signal servers_updated
signal players_updated
signal status_changed(text: String)

var is_online := false
var settings := {}            ## name, map, mode, max_players, time_limit_min, score_limit, respawn_s, friendly_fire, password
var players := {}             ## Peer-ID -> {name, team, kills, deaths, score}
var servers := {}             ## "ip:port" -> Serverinfo (+ ip, seen)
var team_score := [0, 0]
var last_error := ""
var match_over := false
var local_name := "Spieler"

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
var _board: CanvasLayer
var _board_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func is_authority() -> bool:
	return not is_online or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online else 1


func mode() -> int:
	return int(settings.get("mode", Mode.DEATHMATCH))


# --- Server / Client ---------------------------------------------------------------

func host(cfg: Dictionary) -> bool:
	leave(false)
	_peer = ENetMultiplayerPeer.new()
	var port := int(cfg.get("port", PORT))
	var err := _peer.create_server(port, clampi(int(cfg.get("max_players", 8)), 2, 16))
	if err != OK:
		last_error = "Server konnte nicht gestartet werden (Port %d belegt?)" % port
		return false
	multiplayer.multiplayer_peer = _peer
	is_online = true
	settings = cfg.duplicate()
	settings["port"] = port
	players = {1: _new_player(local_name, _pick_team())}
	_bc = PacketPeerUDP.new()
	_bc.set_broadcast_enabled(true)
	_bc.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_begin_match()
	return true


func join(ip: String, port: int = PORT, password := "") -> bool:
	leave(false)
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
	is_online = false
	players.clear()
	_soldiers.clear()
	_respawn.clear()
	match_over = false
	_show_board(false)
	if to_menu and Game.current_mission():
		Game.return_to_menu()


func _new_player(n: String, team: int) -> Dictionary:
	return {"name": n, "team": team, "kills": 0, "deaths": 0, "score": 0}


## Team-Deathmatch: kleineres Team; Deathmatch: eigene Seite je Spieler (für Freund/Feind-Logik)
func _pick_team() -> int:
	if mode() == Mode.DEATHMATCH:
		return 10 + players.size()
	var n := [0, 0]
	for p in players.values():
		if int(p["team"]) in [0, 1]:
			n[int(p["team"])] += 1
	return 0 if n[0] <= n[1] else 1


func _on_connected() -> void:
	_register.rpc_id(1, local_name, _join_pw, PROTOCOL)


func _on_connection_failed() -> void:
	last_error = "Verbindung fehlgeschlagen."
	leave(false)
	status_changed.emit(last_error)


func _on_server_lost() -> void:
	last_error = "Verbindung zum Server verloren."
	leave(true)
	status_changed.emit(last_error)


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(id):
		Events.say("%s hat das Spiel verlassen." % players[id]["name"], 3.0)
	players.erase(id)
	_remove_player.rpc(id)
	_players.rpc(players)


@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, password: String, proto: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if proto != PROTOCOL:
		reason = "Andere Spielversion."
	elif String(settings.get("password", "")) != "" and password != String(settings["password"]):
		reason = "Falsches Passwort."
	elif players.size() >= int(settings.get("max_players", 8)):
		reason = "Server ist voll."
	if reason != "":
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(1.0).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	players[id] = _new_player(pname.substr(0, 24), _pick_team())
	_players.rpc(players)
	Events.say("%s ist beigetreten." % pname, 3.0)
	_enter_match.rpc_id(id, settings, team_score)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	last_error = "Abgewiesen: " + reason
	status_changed.emit(last_error)
	leave(false)


@rpc("authority", "call_remote", "reliable")
func _enter_match(cfg: Dictionary, scores: Array) -> void:
	settings = cfg
	team_score = scores
	match_over = false
	_soldiers.clear()
	Game.start_mission(String(cfg["map"]))


@rpc("authority", "call_local", "reliable")
func _players(p: Dictionary) -> void:
	players = p
	players_updated.emit()


func _begin_match() -> void:
	match_over = false
	_match_t = 0.0
	team_score = [0, 0]
	for p in players.values():
		p["kills"] = 0
		p["deaths"] = 0
		p["score"] = 0
	_soldiers.clear()
	_respawn.clear()
	Game.start_mission(String(settings["map"]))


# --- Mission / Spieler-Soldaten ----------------------------------------------------

## Von der Mission nach dem Aufbau aufgerufen (Mehrspieler: keine KI, keine Skripte)
func mission_ready(_m: Node) -> void:
	if not is_online:
		return
	if multiplayer.is_server():
		_server_spawn(1)
	else:
		_client_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for pid in _soldiers:
		var s: Soldier = _soldiers[pid]
		if is_instance_valid(s) and s.alive:
			_spawn.rpc_id(id, pid, String(players.get(pid, {}).get("name", "?")), int(players.get(pid, {}).get("team", 0)),
				s.global_position, s.look_yaw, int(_gen.get(pid, 0)))
	_players.rpc_id(id, players)
	_server_spawn(id)


func _server_spawn(id: int) -> void:
	var m = Game.current_mission()
	if m == null or not players.has(id):
		return
	var team := int(players[id]["team"])
	var pts: Array = m.mp_spawns() if m.has_method("mp_spawns") else []
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
	_gen[id] = int(_gen.get(id, 0)) + 1
	_spawn.rpc(id, String(players[id]["name"]), team, pos, yaw, int(_gen[id]))


@rpc("authority", "call_local", "reliable")
func _spawn(id: int, pname: String, team: int, pos: Vector3, yaw: float, gen: int) -> void:
	var m = Game.current_mission()
	if m == null:
		return
	var old: Soldier = _soldiers.get(id)
	if is_instance_valid(old) and old.alive:
		old.queue_free()
	var allied := team != 1
	var lo := ["sten", "colt", "no36"] if allied else ["mp40", "p08", "m24"]
	var col := Color(0.43, 0.39, 0.25) if team == 0 else (Color(0.36, 0.38, 0.33) if team == 1 \
		else Color.from_hsv(fmod(float(team) * 0.17, 1.0), 0.35, 0.45))
	var s: Soldier = m.spawn_soldier(pos, yaw, team, pname, lo, col, "brodie" if allied else "stahlhelm", "P%d_%d" % [id, gen])
	s.set_meta("net_peer", id)
	m._default_kit(s)
	s.max_health = 100.0
	s.health = 100.0
	_soldiers[id] = s
	_hp_sent[id] = s.health
	if id == my_id():
		s.net_hook = _local_action
		var sq = m.squad
		sq.members.clear()
		sq.add_member(s)
		sq.set_active(0)
		m.controller.set_active(s)
		m.rig.set_target(s)
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
		_sync_t = SYNC_INTERVAL
		_st.rpc(me.global_position, me.velocity, me.look_yaw, me.look_pitch, me.stance, me.current_slot, me.aiming)
	if multiplayer.is_server():
		_server_tick(delta)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _st(pos: Vector3, vel: Vector3, yaw: float, pitch: float, stance: int, slot: int, aiming: bool) -> void:
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
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


## Aktion des eigenen Soldaten (Soldier.net_hook) an alle anderen
func _local_action(kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	_act.rpc(kind, a, b, wid)


@rpc("any_peer", "call_remote", "reliable")
func _act(kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	var s: Soldier = _soldiers.get(multiplayer.get_remote_sender_id())
	if not is_instance_valid(s) or not s.alive:
		return
	var wd: WeaponData = WeaponDB.get_weapon(StringName(wid)) if wid != "" else null
	match kind:
		"shot":
			Ballistics.fire(s, a, b, wd, s.exclude_rids(), s.team)
			Effects.muzzle_flash(a + b * 0.9, b)
			Effects.play(Effects.weapon_sound(wd), a, 0.0, 1.0, wd.noise_radius * 2.0)
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
			if multiplayer.is_server() and s.weapons.size() > WeaponData.Slot.MELEE and s.weapons[WeaponData.Slot.MELEE]:
				s.look_yaw = b.x
				s._melee(s.weapons[WeaponData.Slot.MELEE])
		"explosive", "mine":
			var c := PlacedCharge.new()
			c.kind = kind
			c.owner_soldier = s
			c.team = s.team
			s.get_parent().add_child(c)
			c.global_position = a


# --- Server: Schaden, Tod, Punkte, Respawn, Spielende ------------------------------------

func _server_tick(delta: float) -> void:
	if match_over:
		_end_t -= delta
		if _end_t <= 0.0:
			_begin_match()
			_enter_match.rpc(settings, team_score)
		return
	_match_t += delta
	for id in _soldiers:
		var s: Soldier = _soldiers[id]
		if is_instance_valid(s) and s.alive and absf(s.health - float(_hp_sent.get(id, s.health))) > 0.5:
			_hp_sent[id] = s.health
			_hp.rpc(id, s.health)
	for id in _respawn.keys():
		_respawn[id] -= delta
		if _respawn[id] <= 0.0:
			_respawn.erase(id)
			_server_spawn(id)
	var tl := float(settings.get("time_limit_min", 10)) * 60.0
	if tl > 0.0 and _match_t >= tl:
		_server_end("Zeit abgelaufen")


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
	_killed.rpc(victim, killer)
	if players.has(victim):
		players[victim]["deaths"] += 1
	var pts := 0
	if killer != 0 and killer != victim and players.has(killer):
		var same := int(players[killer]["team"]) == int(players.get(victim, {}).get("team", -1))
		pts = -1 if same and mode() != Mode.DEATHMATCH else 1
		players[killer]["kills"] += 1 if pts > 0 else 0
		players[killer]["score"] += pts
		if mode() == Mode.TEAM_DEATHMATCH and int(players[killer]["team"]) in [0, 1]:
			team_score[int(players[killer]["team"])] += pts
	elif players.has(victim):
		players[victim]["score"] -= 1      # Selbsttötung
	_players.rpc(players)
	_respawn[victim] = float(settings.get("respawn_s", 5))
	var lim := int(settings.get("score_limit", 20))
	if lim > 0:
		var best := 0
		if mode() == Mode.TEAM_DEATHMATCH:
			best = maxi(team_score[0], team_score[1])
		else:
			for p in players.values():
				best = maxi(best, int(p["score"]))
		if best >= lim:
			_server_end("Punktelimit erreicht")


@rpc("authority", "call_local", "reliable")
func _killed(victim: int, killer: int) -> void:
	var s: Soldier = _soldiers.get(victim)
	if is_instance_valid(s) and s.alive and not multiplayer.is_server():
		s.die(_soldiers.get(killer))
	var vn := String(players.get(victim, {}).get("name", "?"))
	var kn := String(players.get(killer, {}).get("name", ""))
	Events.say("%s → %s" % [kn, vn] if kn != "" and killer != victim else "%s ist gefallen." % vn, 3.0)
	if victim == my_id():
		Events.say("Wiedereinstieg in %d s …" % int(settings.get("respawn_s", 5)), 3.0)


func _server_end(reason: String) -> void:
	match_over = true
	_end_t = 12.0
	_end.rpc(reason, players, team_score)


@rpc("authority", "call_local", "reliable")
func _end(reason: String, p: Dictionary, scores: Array) -> void:
	players = p
	team_score = scores
	match_over = true
	Events.say("Runde beendet: %s" % reason, 8.0)
	_show_board(true)


# --- Punktetabelle (Tab halten; Original 2611–2625) ---------------------------------------

func _process(_delta: float) -> void:
	_process_browse()
	if not is_online or Game.current_mission() == null:
		return
	_show_board(match_over or Input.is_action_pressed("soldier_next"))


func board_text() -> String:
	var lines: PackedStringArray = ["%s – %s" % [MODE_NAMES[clampi(mode(), 0, 2)], String(settings.get("name", ""))]]
	if mode() == Mode.TEAM_DEATHMATCH:
		lines.append("Alliierte %d : %d Achsenmächte" % [team_score[0], team_score[1]])
	lines.append("%-24s %6s %6s %6s %6s" % ["Spieler", "Punkte", "Frags", "Tode", "Ping"])
	var ids := players.keys()
	ids.sort_custom(func(a, b): return int(players[a]["score"]) > int(players[b]["score"]))
	for id in ids:
		var p: Dictionary = players[id]
		var ping := 0
		if _peer and multiplayer.is_server() and id != 1:
			var pp := _peer.get_peer(id)
			ping = pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if pp else 0
		lines.append("%-24s %6d %6d %6d %6d" % [String(p["name"]).substr(0, 24), int(p["score"]), int(p["kills"]), int(p["deaths"]), ping])
	return "\n".join(lines)


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


func _poll_discovery(delta: float) -> void:
	if _bc and multiplayer.is_server():
		_bc_t -= delta
		if _bc_t <= 0.0:
			_bc_t = 1.0
			var info := {"tag": PROTOCOL, "name": settings.get("name", "DH2-Server"), "map": settings.get("map", ""),
				"map_title": Game.MISSIONS.get(String(settings.get("map", "")), {}).get("title", ""),
				"mode": mode(), "players": players.size(), "max": int(settings.get("max_players", 8)),
				"port": int(settings.get("port", PORT)), "pw": String(settings.get("password", "")) != ""}
			_bc.put_packet(JSON.stringify(info).to_utf8_buffer())


func _process_browse() -> void:
	if _listen == null:
		return
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY and d.get("tag", "") == PROTOCOL:
			d["ip"] = ip
			d["seen"] = Time.get_ticks_msec()
			servers["%s:%d" % [ip, int(d.get("port", PORT))]] = d
			changed = true
	for k in servers.keys():
		if Time.get_ticks_msec() - int(servers[k]["seen"]) > 4000:
			servers.erase(k)
			changed = true
	if changed:
		servers_updated.emit()
