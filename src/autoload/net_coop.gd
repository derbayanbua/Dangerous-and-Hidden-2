class_name NetCoop
extends Node
## B-029 Coop-Stil (Original-Stil 3, re_notes_multiplayer §7): Spieler gemeinsam gegen die KI einer Kampagnenkarte.
## Kind des Autoloads Net (/root/Net/Coop), damit die RPC-Pfade auf allen Rechnern gleich sind.
## Server-autoritativ: Die Missions-KI (EnemyBrain) und die Skripte der Originalmission laufen nur auf dem Server.
## Clients bauen dieselben Akteure in derselben Reihenfolge (mp_arena._spawn_coop_actors) als Netzfiguren ohne
## Gehirn; der Server schickt Lage (10 Hz gebündelt), Aktionen (Schüsse/Granaten über Net._do_act) und Tod.
## Treffer auf die KI rechnet nur der Server (Soldier.apply_hit), Spielerschüsse kommen wie bisher geprüft über Net._act.

const SYNC_S := 0.1              ## Lage der KI 10 Hz (Annahme [D]; Spieler 20 Hz)
const FULL_S := 2.0              ## vollständiger Stand alle 2 s (unverändert stehende KI, Spät-Beitretende)
const FIELDS := 8                ## je KI: Index, x, y, z, Blick-Gier, -Neigung, Haltung, Waffenplatz

var ai: Array = []               ## Index -> Soldier/Dog der Originalmission (Reihenfolge actors.bin)
var dead: Array = []             ## Server: Indizes gefallener KI
var _t := 0.0
var _full_t := 0.0
var _last := {}                  ## Index -> zuletzt gesendete Lage
var _spawn_k := 0                ## nächster Kommando-Startplatz
var _slots := {}                 ## Peer-ID -> Kommando-Nummer 0–3 (Skriptnamen commando1–4)
var ai_kills := 0                ## Server: von Spielern getötete KI (Tests/Anzeige)
var rx_states := 0               ## Client: empfangene Lagepakete (Tests)


func reset() -> void:
	ai.clear()
	dead.clear()
	_last.clear()
	_slots.clear()
	_spawn_k = 0
	ai_kills = 0
	rx_states = 0


## Mission (Server und Client) meldet die KI in fester Reihenfolge. Client: Netzfigur ohne Gehirn/Wahrnehmung.
func register_ai(n: Node3D) -> void:
	var idx := ai.size()
	ai.append(n)
	n.set_meta("coop_ai", idx)
	if Net.is_online and multiplayer.is_server():
		if n is Soldier:
			var s := n as Soldier
			s.net_hook = func(kind: String, a: Vector3, b: Vector3, wid: String): _cact.rpc(idx, kind, a, b, wid)
		elif n.has_signal("died_dog"):
			n.connect("died_dog", func(): _on_dog_died(idx))
		return
	# Client: Figur folgt nur dem Server
	if n is Soldier:
		var s2 := n as Soldier
		s2.net_puppet = true
		s2.net_target = s2.global_position
	for c in n.get_children():
		if c is EnemyBrain or c.name in ["EnemyBrain", "Perception"]:
			c.process_mode = Node.PROCESS_MODE_DISABLED
	if not n is Soldier:
		n.process_mode = Node.PROCESS_MODE_DISABLED       # Hund: Lage kommt vom Server


func had_enemies() -> bool:
	return ai.any(func(a): return is_instance_valid(a) and a is Soldier and (a as Soldier).team == Soldier.TEAM_AXIS)


func alive_count() -> int:
	var n := 0
	for a in ai:
		if is_instance_valid(a) and bool(a.get("alive")) and a is Soldier and (a as Soldier).team == Soldier.TEAM_AXIS:
			n += 1
	return n


## Kommando-Startplatz für den Spawn: reihum, belegte (lebender Soldat < 1 m) überspringen, höchstens 32 Versuche
func next_spawn(cand: Array, soldiers: Dictionary, id: int) -> int:
	for tries in 32:
		var i := _spawn_k % cand.size()
		_spawn_k += 1
		var p: Vector3 = cand[i]["pos"]
		var busy := false
		for pid in soldiers:
			var s: Soldier = soldiers[pid]
			if pid != id and is_instance_valid(s) and s.alive and s.global_position.distance_to(p) < 1.0:
				busy = true
		if not busy or tries == 31:
			return i
	return 0


## Server: Spielerfigur für die Originalskripte als commando1–4 / „_PLAYER_ n“ / Original-Spielername eintragen
func register_player(m: Node, s: Soldier, id: int) -> void:
	if m == null or m.get("runtime") == null:
		return
	if not _slots.has(id):
		var used: Array = _slots.values()
		for k in 4:
			if not used.has(k):
				_slots[id] = k
				break
	if not _slots.has(id):
		return
	var k: int = _slots[id]
	m.runtime.register_actor("commando%d" % (k + 1), s)
	m.runtime.register_actor("_PLAYER_ %d" % k, s)
	var names: Array = m.get("_player_names") if m.get("_player_names") != null else []
	if k < names.size():
		m.runtime.register_actor(String(names[k]), s)


# --- Server -------------------------------------------------------------------------------------

func server_tick(delta: float) -> void:
	if ai.is_empty():
		return
	_t -= delta
	_full_t -= delta
	if _t > 0.0:
		return
	_t = SYNC_S
	var full := _full_t <= 0.0
	if full:
		_full_t = FULL_S
	var buf := PackedFloat32Array()
	for i in ai.size():
		var n: Node3D = ai[i]
		if not is_instance_valid(n) or not bool(n.get("alive")):
			continue
		var p := n.global_position
		var yaw := float(n.get("look_yaw")) if n is Soldier else n.rotation.y
		var old: Array = _last.get(i, [])
		if not full and not old.is_empty() and (old[0] as Vector3).distance_to(p) < 0.03 and absf(float(old[1]) - yaw) < 0.02:
			continue
		_last[i] = [p, yaw]
		var s := n as Soldier
		buf.append_array([float(i), p.x, p.y, p.z, yaw, s.look_pitch if s else 0.0, float(s.stance) if s else 0.0,
			float(s.current_slot) if s else 0.0])
	if not buf.is_empty():
		_cst.rpc(buf)


## Server: Missions-KI gefallen (Mission._on_soldier_died → Net.on_soldier_died)
func on_ai_died(s: Node, attacker: Node) -> void:
	var idx := int(s.get_meta("coop_ai", -1))
	if idx < 0 or dead.has(idx):
		return
	dead.append(idx)
	_cdie.rpc(idx, (s as Node3D).global_position, int(s.get_meta("gore_mask", 0)))     # B-037: Abtrennung mitgeben
	if attacker and is_instance_valid(attacker) and attacker.has_meta("net_peer") and (s as Soldier).team == Soldier.TEAM_AXIS:
		var pid := int(attacker.get_meta("net_peer"))
		if Net.players.has(pid) and not Net.match_over and Net.game_state != Net.State.WARMUP:
			Net.players[pid]["kills"] = int(Net.players[pid]["kills"]) + 1
			Net.players[pid]["score"] = int(Net.players[pid]["score"]) + Net.PTS_KILL
			Net.players[pid]["ai_kills"] = int(Net.players[pid].get("ai_kills", 0)) + 1     # 0.11.1 Master-Bericht
			ai_kills += 1
			Net._update_ranks()
			Net._players.rpc(Net.players)


func _on_dog_died(idx: int) -> void:
	if dead.has(idx) or idx >= ai.size():
		return
	dead.append(idx)
	_cdie.rpc(idx, (ai[idx] as Node3D).global_position, 0)


## Server: gefallene KI an einen Spät-Beitretenden
func sync_to(peer: int) -> void:
	for idx in dead:
		if idx < ai.size() and is_instance_valid(ai[idx]):
			_cdie.rpc_id(peer, idx, (ai[idx] as Node3D).global_position, int(ai[idx].get_meta("gore_mask", 0)))
	_full_t = 0.0


# --- Client -------------------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _cst(buf: PackedFloat32Array) -> void:
	rx_states += 1
	var i := 0
	while i + FIELDS <= buf.size():
		var idx := int(buf[i])
		if idx >= 0 and idx < ai.size() and is_instance_valid(ai[idx]):
			var n: Node3D = ai[idx]
			var p := Vector3(buf[i + 1], buf[i + 2], buf[i + 3])
			if n is Soldier:
				var s := n as Soldier
				if s.alive:
					s.net_target = p
					s.look_yaw = buf[i + 4]
					s.look_pitch = buf[i + 5]
					s.stance_request = int(buf[i + 6])
					var slot := int(buf[i + 7])
					if slot != s.current_slot and slot >= 0 and slot < s.weapons.size() and s.weapons[slot] != null:
						s.current_slot = slot
						s._on_weapon_switched()
			elif bool(n.get("alive")):
				n.global_position = p
				n.rotation.y = buf[i + 4]
		i += FIELDS


@rpc("authority", "call_remote", "reliable")
func _cact(idx: int, kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	if idx < 0 or idx >= ai.size() or not ai[idx] is Soldier:
		return
	var s: Soldier = ai[idx]
	if is_instance_valid(s) and s.alive:
		Net._do_act(s, kind, a, b, wid)


@rpc("authority", "call_remote", "reliable")
func _cdie(idx: int, pos: Vector3, gore := 0) -> void:
	if idx < 0 or idx >= ai.size() or not is_instance_valid(ai[idx]):
		return
	if not dead.has(idx):
		dead.append(idx)
	var n: Node3D = ai[idx]
	if not bool(n.get("alive")):
		return
	n.global_position = pos
	if n is Soldier:
		(n as Soldier).net_target = pos
		if gore > 0:
			n.set_meta("_gore_net", Gore.sanitize_mask(gore))   # B-037: wie Net._killed (Abtrennung vom Server)
		(n as Soldier).die(null)
	elif n.has_method("die"):
		n.process_mode = Node.PROCESS_MODE_INHERIT
		n.call("die")
