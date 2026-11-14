extends Node
## 0.11.5 – Tag-/Nachtwechsel auf allen Karten (src/world/mp_day_night.gd), nur Mehrspieler.
## tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_mp_daynight
## Ablauf Host: (1) Einzelspieler m01 unberührt (auch mit gesetzter Regel), (2) Server mit Regel aus = Karte unverändert,
## (3) Regel per Konsole an + Neustart: Ausgangsstimmung = Original, Zeit läuft, Licht ändert sich glatt, Tag ≠ Nacht,
## Grafikstufenwechsel ändert die Stimmung nicht, (4) zweiter Prozess tritt spät bei und übernimmt die Serverzeit.
const MAP := "mp_arena_a1_blizzard"
const PORT_OFS := 61
const MpDN := preload("res://src/world/mp_day_night.gd")
var failed := 0
var passed := 0
var child_pid := -1
var peer_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("dn_peer")
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung")
		_finish())
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)


func wait_for(condition: Callable, seconds := 120.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()


func _snap(m: Mission) -> Dictionary:
	return {"sun_e": m.sun.light_energy, "sun_dir": m.sun.global_basis.z, "sun_c": m.sun.light_color,
		"fog": m.env.fog_light_color, "amb_c": m.env.ambient_light_color, "amb_e": m.env.ambient_light_energy,
		"lf": m.light_factor, "exp": m.env.tonemap_exposure}


func _same(a: Dictionary, b: Dictionary, eps := 0.02) -> String:
	for k in a:
		var va = a[k]
		var vb = b[k]
		var d := 0.0
		if va is float:
			d = absf(va - vb)
		elif va is Vector3:
			d = (va as Vector3).distance_to(vb)
		elif va is Color:
			d = Vector3(va.r - vb.r, va.g - vb.g, va.b - vb.b).length()
		if d > eps:
			return "%s: %s ≠ %s" % [k, str(va), str(vb)]
	return ""


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
		_finish()
		return
	# (1) Einzelspieler: kein Tag-/Nachtwechsel, auch wenn die Regel in den Einstellungen stünde
	var sp_ok := await wait_for(func(): return Game.current_mission() != null, 120.0)
	check(sp_ok, "Einzelspieler-Mission geladen")
	if sp_ok:
		var sp: Mission = Game.current_mission()
		Net.settings["day_night"] = true
		check(sp.mp_day_night == null and not MpDN.wanted(sp), "Einzelspieler: kein MP-Tag/Nacht (offline)")
		var a := _snap(sp)
		await get_tree().create_timer(2.0).timeout
		check(_same(a, _snap(sp), 0.0005) == "", "Einzelspieler: Licht bleibt unverändert")
		Net.settings.erase("day_night")
	# (2) Server mit Regel aus
	Net.local_name = "DnHost"
	Net.local_team = 0
	check(Net.host({"name": "DN Test", "map": MAP, "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + PORT_OFS,
		"max_players": 4, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0,
		"password": "", "allow_vehicles": false, "flood_protect": false}), "Server gestartet (Regel aus)")
	check(not bool(Net.rule("day_night")) and int(Net.rule("dn_start_h")) == -1 and int(Net.rule("dn_cycle_min")) == 60,
		"Standard: daynight aus, Start = Karte, 60 min")
	var ok := await wait_for(func(): return Game.current_mission() != null and Game.current_mission_id == MAP and Net._soldiers.has(1))
	check(ok, "MP-Karte geladen")
	if not ok:
		_finish()
		return
	var m0: Mission = Game.current_mission()
	await get_tree().create_timer(1.0).timeout
	check(m0.mp_day_night == null and m0.get_node_or_null(MpDN.NODE_NAME) == null, "Regel aus: kein Tageszeit-Knoten")
	var orig := _snap(m0)
	await get_tree().create_timer(3.0).timeout
	check(_same(orig, _snap(m0), 0.0005) == "", "Regel aus: Licht/Nebel/light_factor unverändert")
	# (3) Regel per Konsole an, Neustart
	var reply := Net.server_command("daynight 1")
	check(reply.contains("daynight"), "Konsole: daynight 1 → " + reply)
	check(bool(Net.rule("day_night")), "Regel day_night gesetzt")
	Net.restart_round()
	ok = await wait_for(func(): return Game.current_mission() != null and Game.current_mission() != m0 \
		and Game.current_mission().mp_day_night != null and Net._soldiers.has(1))
	check(ok, "Neustart mit Regel an: Tageszeit-Knoten vorhanden")
	if not ok:
		_finish()
		return
	var m: Mission = Game.current_mission()
	var dn = m.mp_day_night
	check(dn.name == MpDN.NODE_NAME, "Knotenname fest (RPC-Pfad)")
	print("DN base_hour=%.2f lf=%.2f" % [dn.base_hour, orig["lf"]])
	check(absf(wrapf(dn.hour - dn.base_hour, -12.0, 12.0)) < 0.05, "Start = Originaluhrzeit der Karte (%.2f h)" % dn.base_hour)
	var diff := _same(orig, _snap(m), 0.03)
	check(diff == "", "Ausgangsstimmung = Originalstimmung der Karte " + diff)
	var h0: float = dn.hour
	await get_tree().create_timer(3.0).timeout
	check(wrapf(dn.hour - h0, -12.0, 12.0) > 0.01, "Zeit läuft (%.3f → %.3f h)" % [h0, dn.hour])
	# Glätte: ganzer Tag in kleinen Schritten, keine Sprünge
	var prev := {}
	var worst := 0.0
	var worst_k := ""
	var lf_min := 9.0
	var lf_max := -9.0
	# Schritt 0,01 h = 1,5 s Echtzeit bei 60 min je Tag; ein Sprung bliebe bei feinerem Raster groß, eine Rampe nicht
	for i in 2401:
		dn.set_hour(float(i) * 0.01)
		var s := {"lf": m.light_factor, "amb_e": m.env.ambient_light_energy, "sun_e": m.sun.light_energy,
			"fog": Vector3(m.env.fog_light_color.r, m.env.fog_light_color.g, m.env.fog_light_color.b),
			"amb_c": Vector3(m.env.ambient_light_color.r, m.env.ambient_light_color.g, m.env.ambient_light_color.b)}
		lf_min = minf(lf_min, m.light_factor)
		lf_max = maxf(lf_max, m.light_factor)
		if not prev.is_empty():
			for k in s:
				var d: float = (s[k] - prev[k]).length() if s[k] is Vector3 else absf(s[k] - prev[k])
				if d > worst:
					worst = d
					worst_k = "%s bei %.2f h" % [k, float(i) * 0.01]
		prev = s
	check(worst < 0.05, "Licht ändert sich glatt (größter Schritt je 1,5 s Echtzeit %.3f, %s)" % [worst, worst_k])
	dn.set_hour(13.0)
	var day := _snap(m)
	dn.set_hour(1.0)
	var night := _snap(m)
	check(day["lf"] > night["lf"] + 0.2 and night["lf"] <= 0.55, "KI-Sicht: light_factor Tag %.2f > Nacht %.2f" % [day["lf"], night["lf"]])
	check(day["sun_e"] > night["sun_e"] * 3.0, "Sonnen-/Mondenergie Tag %.2f > Nacht %.2f" % [day["sun_e"], night["sun_e"]])
	check(day["amb_e"] > night["amb_e"] and (day["fog"] as Color).v > (night["fog"] as Color).v, "Umgebungslicht und Nebel nachts dunkler")
	check((day["sun_dir"] as Vector3).distance_to(night["sun_dir"]) > 0.3, "Licht kommt nachts aus anderer Richtung (Mond)")
	check(lf_min < lf_max, "light_factor folgt der Tageszeit")
	# Grafikstufe wechseln: gleiche Stimmung
	dn.set_hour(20.4)
	var before := _snap(m)
	var qb := float(m.env.get_meta("q_base_amb")) if m.env.has_meta("q_base_amb") else 1.0
	var qf := func(): return (1.0 if Settings.quality >= 3 else 1.12)
	var amb_rel_before: float = before["amb_e"] / (qb * qf.call())
	var old_q := Settings.quality
	Settings.quality = 0 if old_q >= 2 else 3
	Settings.changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	dn.set_hour(20.4)
	var after := _snap(m)
	var amb_rel_after: float = after["amb_e"] / (qb * qf.call())
	before.erase("amb_e")
	after.erase("amb_e")
	diff = _same(before, after, 0.005)
	check(diff == "" and absf(amb_rel_before - amb_rel_after) < 0.005, "Grafikstufenwechsel: Lichtstimmung gleich " + diff)
	Settings.quality = old_q
	Settings.changed.emit()
	# SPIEL-INFO-Daten
	var r: Dictionary = Net.server_info().get("rules", {})
	check(bool(r.get("day_night", false)) and int(r.get("dn_cycle_min", 0)) == 60, "Serverinfo (SPIEL-INFO) meldet Tag/Nacht")
	# (4) Spät-Beitritt: Zeit vorher verstellt
	dn.set_hour(3.0)
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_daynight_client.log"),
		"--", "--autoplay=test_mp_daynight", "--dn_peer=1"]
	if OS.has_feature("editor"):
		args.insert(1, "--path")
		args.insert(2, ProjectSettings.globalize_path("res://"))
	child_pid = OS.create_process(OS.get_executable_path(), args)
	check(child_pid > 0, "Zweiter Spielprozess gestartet")
	var ack := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text", "")).begins_with("DN_CLIENT_")), 300.0)
	check(ack and Net.chat_log.any(func(e): return String(e.get("text", "")) == "DN_CLIENT_OK"), "Client bestätigt Zeitübernahme")
	Net.leave(false)
	if child_pid > 0:
		await wait_for(func(): return not OS.is_process_running(child_pid), 8.0)
	_finish()


func _client() -> void:
	Net.local_name = "DnGuest"
	Net.local_team = 1
	Net.join("127.0.0.1", Net.PORT + PORT_OFS, "")
	var ready := await wait_for(func(): return Game.current_mission() != null and Net._soldiers.has(Net.my_id()), 240.0)
	check(ready, "Client hat Karte geladen")
	if ready:
		var m: Mission = Game.current_mission()
		check(bool(Net.rule("day_night")), "Client kennt Regel daynight")
		check(m.mp_day_night != null, "Client hat Tageszeit-Knoten")
		if m.mp_day_night:
			var dn = m.mp_day_night
			check(await wait_for(func(): return dn.synced, 30.0), "Client erhält Tageszeit vom Server (später Beitritt)")
			check(dn.hour > 2.9 and dn.hour < 3.6, "Client-Uhrzeit = Serverzeit (Nacht), nicht Kartenstart: %.2f" % dn.hour)
			check(m.light_factor < 0.6, "Client: Nachtlicht für KI-Sicht (%.2f)" % m.light_factor)
	Net.send_chat("DN_CLIENT_OK" if failed == 0 else "DN_CLIENT_FAIL")
	await wait_for(func(): return not Net.is_online, 60.0)


func _finish() -> void:
	if Net.is_online:
		Net.leave(false)
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	print("ERGEBNIS: MP Tag/Nacht %s: %d bestanden, %d fehlgeschlagen" % ["Client" if peer_mode else "Host", passed, failed])
	get_tree().quit(1 if failed else 0)
