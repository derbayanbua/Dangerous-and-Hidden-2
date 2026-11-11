extends "res://tests/lan_ui_base.gd"
## 0.11.2 Hotfix: KI-Soldaten auf einem dedizierten Server (zwei Prozesse, wie Internet-/Demo-Server mit Bots).
## Startet einen kopflosen dedizierten Server (--dedicated=<cfg>, bots > 0, SPIELER-SETUP aktiv wie im echten Betrieb),
## tritt als Client bei, bestätigt das Setup und prüft:
##  - Spawn-Schutz des Clients: HUD-Restzeit, Feuern gesperrt (lokal und vom Server verworfen), endet nach der Zeit
##  - Bots bewegen sich, erkennen den Client und beschießen ihn (Gesundheit sinkt / Treffer-Richtung)
##  - Client trifft einen Bot: Server bestätigt den Treffer, Bot-Gesundheit sinkt
##   tools\godot.cmd --headless -- --autoplay=test_mp_bots_online --setup_gate=1 --profiles_dir=user://test_mp_bots_online --noimport

const DPORT := 11081

var _stdio: FileAccess
var _stderr: FileAccess
var _pid := 0
var out_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_end())
	_run.call_deferred()


func _process(_d: float) -> void:
	if _stdio == null:
		return
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 64:
			var b: PackedByteArray = pipe.get_buffer(4096)
			if b.is_empty():
				break
			out_text += b.get_string_from_utf8()
	if out_text.length() > 400000:
		out_text = out_text.substr(out_text.length() - 200000)


func _project_args() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	if OS.has_feature("template"):
		return []
	return ["--path", ProjectSettings.globalize_path("res://")]


func _bots() -> Array:
	var out: Array = []
	for k in Net._soldiers:
		var s = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s) and s.alive:
			out.append(s)
	return out


func _me() -> Soldier:
	var s = Net._soldiers.get(Net.my_id())
	return s if is_instance_valid(s) else null


func _end() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		_stdio.store_string("quit\n")
		_stdio.flush()
		await get_tree().create_timer(3.0, true, false, true).timeout
		if OS.is_process_running(_pid):
			OS.kill(_pid)
	var f := FileAccess.open("res://test_output/mp_bots_online_server.txt", FileAccess.WRITE)
	if f:
		f.store_string(out_text)
	_finish()


func _aim_at(me: Soldier, target: Vector3) -> void:
	var from := me.global_position + Vector3(0, 1.5, 0)
	var d := target - from
	me.look_yaw = atan2(-d.x, -d.z)
	me.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	await frames(10)
	var cfg := ProjectSettings.globalize_path("res://test_output/test_mp_bots_online.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	var style := "deathmatch"
	var map := "mp_arctic2_mp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--map="):
			map = a.get_slice("=", 1)
	f.store_string("\n".join(PackedStringArray(["sessionname \"Bot-Test\"", "style " + style, "mapname " + map,
		"port %d" % DPORT, "warmup 0", "pointlimit 0", "roundlimit 0", "timelimit 0", "respawntime 3", "spawnprotection 5",
		"bots 3", "server"])) + "\n")
	f.close()
	# Server ohne --autoplay: SPIELER-SETUP aktiv wie auf dem echten Demo-Server
	var r := OS.execute_with_pipe(OS.get_executable_path(), ["--headless", "--log-file",
		ProjectSettings.globalize_path("res://test_output/mp_bots_online_server.log")] + _project_args()
		+ ["--", "--dedicated=" + cfg, "--bot_trace=1"], false)
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	_pid = int(r.get("pid", 0))
	check(_pid > 0, "Dedizierter Server gestartet", str(_pid))
	if _pid <= 0:
		_end()
		return
	var addr := "127.0.0.1:%d" % DPORT
	Net.favorites = [addr]
	Net.browsing_favorites = true
	var up := func() -> bool: return Net.fav_info.has(addr) and int(Net.fav_info[addr].get("bots", 0)) >= 6
	check(await wait_for(up, 500.0), "Server läuft mit 6 KI-Soldaten", str(Net.fav_info.get(addr, {})))
	Net.browsing_favorites = false
	Net.favorites = []
	Net.local_name = "Tester"
	Net.join("127.0.0.1", DPORT)
	var joined := func() -> bool: return Game.current_mission() != null and _bots().size() >= 6
	check(await wait_for(joined, 500.0), "Beigetreten, KI-Soldaten sichtbar", str(_bots().size()))
	check(Net.setup_pending, "Client im SPIELER-SETUP (Setup-Sperre wie im Betrieb)")
	# --- Bots bewegen sich schon ohne gespawnten Spieler ---
	var p0 := {}
	for b in _bots():
		p0[b.name] = b.global_position
	await seconds(12.0)
	var moved := 0
	for b in _bots():
		if p0.has(b.name) and (b.global_position - p0[b.name]).length() > 2.0:
			moved += 1
	check(moved >= 2, "KI-Soldaten bewegen sich (Server-Gehirn aktiv)", "%d von %d" % [moved, _bots().size()])
	# --- Setup bestätigen → Spawn mit Spawn-Schutz ---
	Net.confirm_setup()
	var spawned := func() -> bool: return _me() != null and _me().alive
	check(await wait_for(spawned, 60.0), "Nach AKZEPTIEREN gespawnt")
	var me := _me()
	if me == null:
		_end()
		return
	check(me.has_meta("protect_until") and Net.spawn_protected(me), "Spawn-Schutz aktiv nach dem Spawn")
	check(Net.spawn_protect_left(me) > 3.0 and Net.spawn_protect_left(me) <= 5.01, "Restzeit ≈ 5 s",
		str(Net.spawn_protect_left(me)))
	var hud = Game.current_mission().get_node_or_null("MpHud")
	await frames(5)
	check(hud != null and hud.has_method("protect_text") and String(hud.protect_text()).contains(Net.tx(20313, "Respawn-Schutz")),
		"HUD zeigt „Spawn-Schutz“ mit Restzeit", str(hud.protect_text()) if hud and hud.has_method("protect_text") else "")
	# Feuern während des Schutzes: lokal gesperrt
	var w = me.current_weapon()
	var ammo0: int = w.in_mag if w else -1
	me.trigger = true
	await frames(20)
	me.trigger = false
	check(w != null and w.in_mag == ammo0, "Feuern während Spawn-Schutz gesperrt (keine Munition verbraucht)",
		"%d -> %d" % [ammo0, w.in_mag if w else -1])
	# Server verwirft Schüsse während des Schutzes (manipulierter Client sendet trotzdem)
	var rej0 := out_text.count("verworfen: Spawn-Schutz")
	Net._act.rpc_id(1, "shot", me.global_position + Vector3(0, 1.5, 0), Vector3(-sin(me.look_yaw), 0, -cos(me.look_yaw)),
		String(w.data.id) if w else "")
	var rej := func() -> bool: return out_text.count("verworfen: Spawn-Schutz") > rej0
	check(await wait_for(rej, 20.0), "Server verwirft Schuss während Spawn-Schutz (NET-AUTH)")
	# Schutz endet nach der Zeit
	var over := func() -> bool: return not Net.spawn_protected(me)
	check(await wait_for(over, 10.0), "Spawn-Schutz endet nach 5 s")
	await frames(5)
	check(hud == null or not hud.has_method("protect_text") or String(hud.protect_text()) == "", "HUD-Hinweis verschwindet")
	# --- Kampf: auf den nächsten Bot zielen und schießen, Bots greifen an ---
	var hp_start := me.health
	var hits_on_bots := 0
	var bot_hp_dropped := false
	var hurt := false
	var bot_hp0 := {}
	var t_end := Time.get_ticks_msec() + 240000
	var last_bot_shots := 0
	while Time.get_ticks_msec() < t_end:
		await frames(2)
		me = _me()
		if me == null or not me.alive:
			hurt = true        # gestorben = beschossen
			var back := func() -> bool: return _me() != null and _me().alive
			await wait_for(back, 30.0)
			continue
		if me.health < hp_start - 0.01 or not Net.hurt_log.is_empty():
			hurt = true
		for e in Net.hit_log:
			if int(e.get("victim", 0)) < 0:
				hits_on_bots += 1
		Net.hit_log.clear()
		var best: Soldier = null
		var bd := 1e9
		for b in _bots():
			if b.team == me.team:
				continue
			if not bot_hp0.has(b.name):
				bot_hp0[b.name] = b.health
			elif b.health < float(bot_hp0[b.name]) - 0.01:
				bot_hp_dropped = true
			var d: float = b.global_position.distance_to(me.global_position)
			if d < bd and _los(me, b):
				bd = d
				best = b
		if best != null and bd < 90.0:
			_aim_at(me, best.global_position + Vector3(0, 1.2, 0))
			me.aiming = true
			me.trigger = not me.trigger
			var cw = me.current_weapon()
			if cw and cw.in_mag <= 0:
				me.trigger = false
				me.reload()
		else:
			me.trigger = false
		if hurt and hits_on_bots > 0 and bot_hp_dropped:
			break
	me = _me()
	if me:
		me.trigger = false
	check(hits_on_bots > 0, "Server bestätigt Treffer auf KI-Soldaten", str(hits_on_bots))
	check(bot_hp_dropped, "KI-Soldat nimmt Schaden (Gesundheit sinkt beim Client)")
	check(hurt, "KI-Soldaten erkennen und beschießen den Client", "hurt_log %d" % Net.hurt_log.size())
	check(not out_text.contains("SCRIPT ERROR"), "Server ohne Skriptfehler", _first_error())
	_end()


func _first_error() -> String:
	var i := out_text.find("SCRIPT ERROR")
	return out_text.substr(i, 300) if i >= 0 else ""


func _los(me: Soldier, b: Soldier) -> bool:
	var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3(0, 1.5, 0), b.global_position + Vector3(0, 1.2, 0), 1)
	return me.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
