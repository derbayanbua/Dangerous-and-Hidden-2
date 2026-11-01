extends Node
## B-029 Coop (Client-Seite, von test_mp_coop als zweiter Prozess gestartet): Beitritt, Missions-KI als Netzfiguren
## (ohne Gehirn, Lage vom Server), KI-Lage/-Tod aus dem Abgleich, T20310 beim Tod ohne Leben.
## Ergebnisse nach user://mp_coop_client_result.txt.

const RESULT := "user://mp_coop_client_result.txt"
var lines: PackedStringArray = []
var _written := false


func check(c: bool, name: String, detail := "") -> void:
	print("COOP-CLIENT ", "PASS " if c else "FAIL ", name, "  ", detail)
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _host_chat(prefix: String) -> String:
	for e in Net.chat_log:
		if String(e["name"]) == "Host" and String(e["text"]).begins_with(prefix):
			return String(e["text"])
	return ""


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	Net.local_team = Soldier.TEAM_AXIS          # Wunsch Achse: im Coop muss der Server die Spielerseite vergeben
	var ip := ""
	if Net.start_browse():
		for i in 100:
			await get_tree().create_timer(0.1).timeout
			if not Net.servers.is_empty():
				ip = String(Net.servers.values()[0]["ip"])
				break
	Net.stop_browse()
	Net.join(ip if ip != "" else "127.0.0.1", Net.PORT, "")
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		m = Game.current_mission()
		if m and Net._soldiers.has(Net.my_id()):
			break
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(is_instance_valid(me) and me.alive, "Eigener Soldat vom Server erzeugt")
	if not is_instance_valid(me):
		_done()
		return
	check(Net.mode() == Net.Mode.COOP, "Stil KOOPERATIV übernommen")
	check(me.team == Soldier.TEAM_ALLIED, "Spielerseite trotz Wunsch Achse", str(me.team))
	var ai: Array = Net.coop.ai
	check(ai.size() >= 5, "Missions-KI als Netzfiguren", str(ai.size()))
	var puppets := ai.all(func(a): return not a is Soldier or (a as Soldier).net_puppet)
	var brains_off := true
	for a in ai:
		for c in (a as Node).get_children():
			if c is EnemyBrain and c.process_mode != Node.PROCESS_MODE_DISABLED:
				brains_off = false
	check(puppets and brains_off, "KI ohne eigenes Gehirn (Server-autoritativ)")
	check(m.runtime == null or m.runtime.vms.is_empty(), "Originalskripte laufen nicht auf dem Client")
	check(await _wait(func(): return Net.coop.rx_states > 0, 20.0), "KI-Lage vom Server empfangen", str(Net.coop.rx_states))
	Net.send_chat("CLIENT_READY")
	print("COOP-CLIENT bereit, warte auf Auftrag")
	# KI-Lage/-Tod
	check(await _wait(func(): return _host_chat("AI_CHECK") != "", 300.0), "Prüfauftrag des Servers")
	var parts := _host_chat("AI_CHECK").split(" ", false)
	print("COOP-CLIENT Auftrag ", parts)
	if parts.size() >= 6:
		var mi := int(parts[1])
		var vi := int(parts[2])
		var p := Vector3(float(parts[3]), float(parts[4]), float(parts[5]))
		var dist := func() -> float:
			return (ai[mi] as Soldier).net_target.distance_to(p) if mi < ai.size() and ai[mi] is Soldier else 999.0
		var dead := func() -> bool:
			return vi < ai.size() and is_instance_valid(ai[vi]) and not bool(ai[vi].get("alive"))
		var ok := await _wait(func(): return dead.call() and float(dist.call()) < 1.0, 15.0)
		check(ok, "KI-Lage und KI-Tod übernommen", "%.2f m, tot %s" % [float(dist.call()), str(dead.call())])
		Net.send_chat("AI_OK" if ok else "AI_FAIL")
	else:
		Net.send_chat("AI_FAIL")
	# drei Tode (Leben je Spieler 3): beim letzten T20310
	var ok2 := await _wait(func(): return Net.last_nolives_ms > 0, 180.0)
	check(ok2 and Net.respawn_at == 0, "T20310 „Keine verbleibenden Leben“ angezeigt, kein Wiedereinstieg")
	var used_ok := await _wait(func(): return int(Net.players.get(Net.my_id(), {}).get("lives_used", 0)) == 3, 10.0)
	check(used_ok and Net.coop_lives_left(Net.my_id()) == 0, "Lebenszähler am Client 3/3, 0 übrig",
		"%s / %d" % [str(Net.players.get(Net.my_id(), {}).get("lives_used")), Net.coop_lives_left(Net.my_id())])
	Net.send_chat("NOLIVES_OK" if ok2 else "NOLIVES_FAIL")
	check(await _wait(func(): return Net.match_over, 120.0), "Rundenende am Client")
	_done()


func _done() -> void:
	if _written:
		return
	_written = true
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	await get_tree().create_timer(1.0).timeout
	Net.leave(false)
	get_tree().quit()
