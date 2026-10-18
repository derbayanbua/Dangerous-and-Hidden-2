extends Node
## Mehrspieler LAN (Client-Seite, wird von test_net als zweiter Prozess gestartet): Server per LAN-Suche
## finden, beitreten, laufen; Tod durch den Server erkennen, Wiedereinstieg prüfen. Ergebnisse nach
## user://net_client_result.txt (liest test_net).

var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
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
	while Time.get_ticks_msec() - t0 < 400000:      # Karte laden: unter Last mehrere Minuten
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
	# Chat und Voice-Chat an den Server (Server leitet weiter)
	Net.send_chat("Hallo Host")
	var pcm := PackedFloat32Array()
	for i in 320:
		pcm.append(0.6 * sin(TAU * 300.0 * i / 8000.0))
	for k in 5:
		Net.voice.send_frame(pcm)
	check(Net.voice.frames_sent == 5 and Net.voice.codec_rate() == 8000, "Sprachpakete gesendet (64 kbps)")
	# laufen, bis der Server trifft (Ereignis statt fester Bildzahl; unter Last dauert es länger)
	Input.action_press("move_forward")
	var tw := Time.get_ticks_msec()
	while me.alive and Time.get_ticks_msec() - tw < 300000:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(not me.alive, "Tod durch Server-Treffer kommt an")
	var saw_wait := false
	var respawned := false
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 180000:
		await get_tree().physics_frame
		var hud = m.get_node_or_null("MpHud")
		if hud and String(hud.state_text()).contains(Net.tx(7405, "AUF RESPAWN WARTEN")):
			saw_wait = true
		var again: Soldier = Net._soldiers.get(Net.my_id())
		if is_instance_valid(again) and again.alive and again != me:
			respawned = true
			check(m.squad.leader() == again, "Neuer Soldat wird gesteuert")
			break
	check(saw_wait, "HUD: %s mit Countdown" % Net.tx(7405, "AUF RESPAWN WARTEN"))
	check(respawned, "Wiedereinstieg auf dem Client (automatisch nach Respawn-Zeit + 3 s)")
	check(Net.chat_log.any(func(e): return String(e["name"]) == "Host" and String(e["text"]) == "Hallo Gast"), "Chat des Servers empfangen")
	# Fahrzeug-Abgleich (test_net: Host fährt das Testfahrzeug im Kreis)
	var car: Vehicle = load("res://tests/test_net.gd").net_test_car(m)
	var c0 := car.global_position
	var boarded := false
	var followed := false
	var moved := 0.0
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 150000:
		await get_tree().physics_frame
		var h: Soldier = Net._soldiers.get(1)
		if is_instance_valid(h) and h.vehicle == car and h.seat_index == 0:
			boarded = true
		if car.freeze and car._net_t >= 0.0:
			followed = true
		moved = maxf(moved, car.global_position.distance_to(c0))
		if boarded and followed and moved > 5.0:
			break
	check(boarded, "Fahrzeug: Host sitzt auch beim Client am Steuer (Sitzabgleich)")
	check(followed and moved > 5.0, "Fahrzeug: Lage vom Fahrer kommt an (kinematisch nachgeführt)", "%.1f m" % moved)
	_done()


var _quitting := false


func _done() -> void:
	if _quitting:
		return
	_quitting = true
	var f := FileAccess.open("user://net_client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	# verbunden bleiben, bis der Server seine Prüfungen abgeschlossen hat und die Verbindung beendet (Ereignis)
	var t0 := Time.get_ticks_msec()
	while Net.is_online and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(0.5).timeout
	Net.leave(false)
	get_tree().quit()
