extends Node
## Mehrspieler LAN (Client-Seite, wird von test_net als zweiter Prozess gestartet): Server per LAN-Suche
## finden, beitreten, laufen; Tod durch den Server erkennen, Wiedereinstieg prüfen. Ergebnisse nach
## user://net_client_result.txt (liest test_net).

var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(400.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	var ip := ""
	if Net.start_browse():
		for i in 100:
			await get_tree().create_timer(0.1).timeout
			if not Net.servers.is_empty():
				ip = String(Net.servers.values()[0]["ip"])
				break
	check(ip != "", "LAN-Suche findet den Server (UDP-Broadcast)", ip)
	Net.stop_browse()
	Net.join(ip if ip != "" else "127.0.0.1", Net.PORT, "")
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:      # Karte laden: bis 3 min
		await get_tree().create_timer(0.2).timeout
		m = Game.current_mission()
		if m and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1):
			break
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(is_instance_valid(me) and me.alive, "Eigener Soldat vom Server erzeugt")
	var host: Soldier = Net._soldiers.get(1)
	check(is_instance_valid(host) and host.net_puppet, "Soldat des Servers sichtbar (Netzfigur)")
	if not is_instance_valid(me):
		_done()
		return
	Input.action_press("move_forward")
	for i in 900:
		await get_tree().physics_frame
		if not me.alive:
			break
	Input.action_release("move_forward")
	check(not me.alive, "Tod durch Server-Treffer kommt an")
	for i in 600:
		await get_tree().physics_frame
		var again: Soldier = Net._soldiers.get(Net.my_id())
		if is_instance_valid(again) and again.alive and again != me:
			check(true, "Wiedereinstieg auf dem Client")
			check(m.squad.leader() == again, "Neuer Soldat wird gesteuert")
			break
	_done()


func _done() -> void:
	var f := FileAccess.open("user://net_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	Net.leave(false)
	get_tree().quit()
