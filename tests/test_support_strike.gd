extends Node
## B-011: Artillerieschlag / Luftangriff per Funkgerät, zwei echte ENet-Prozesse.
##  Host (Alliierte) + Client (Achse) + je 1 KI. Prüft Regeln/Konfiguration/SPIEL-INFO, offene Karte, Funkgerät-Spawn
##  (Original-Modell, freier Himmel, bei allen), Aufnahme (Server), Untermenü wie Original 0x4C02DD (nur passende Art),
##  Zielwahl → 3D-Kreis bei allen → Einschlag nach 5 s, Schaden nur im Radius, Kill-Feed-Ursache bei beiden, zweite Art
##  (abwechselnd), Ablehnung ohne Funkgerät, Bots nehmen das Funkgerät (supportbots), Abschalten per Konsole.
##   tools\godot.cmd --headless -- --autoplay=test_support_strike   (Client-Teilprozess: --ss_peer=1)

const PORT_OFS := 53
const STEP_HOST := "user://ss_step_host.json"
const STEP_CLIENT := "user://ss_step_client.txt"
const RESULT := "user://ss_client_result.txt"
const FB := preload("res://src/ui/mp_feedback.gd")

var passed := 0
var failed := 0
var lines: PackedStringArray = []
var peer_mode := false


static func _map() -> String:
	if Game.cli.has("ss_map"):
		return String(Game.cli["ss_map"])
	if Game.MISSIONS.has("mp_africa2_mp_zone"):
		return "mp_africa2_mp_zone"      # Original-Karte mit AIRCRAFTATACK und Funkgerätstellen
	return "mp_arena_a1_blizzard"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("ss_peer")
	get_tree().create_timer(900.0 if peer_mode else 1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func check(ok: bool, label: String, detail := "") -> void:
	var line: String = ("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")")
	print(line)
	lines.append(line)
	if ok:
		passed += 1
	else:
		failed += 1


func wait_for(cond: Callable, s := 60.0) -> bool:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return bool(cond.call())


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _client_peer() -> int:
	for id in Net._soldiers:
		if int(id) > 1 and is_instance_valid(Net._soldiers[id]):
			return int(id)
	return 0


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
	else:
		await _host()
	_finish()


func _freeze_bots() -> void:
	for id in Net._soldiers:
		var b: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(b):
			var br := b.get_node_or_null("EnemyBrain")
			if br:
				br.process_mode = Node.PROCESS_MODE_DISABLED
			b.move_input = Vector3.ZERO
			b.trigger = false


# --- Host ----------------------------------------------------------------------------------------------

func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT, RESULT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# Regeln/Konfiguration
	var d := Net.style_defaults(Net.Mode.TEAM_DEATHMATCH)
	check(int(d["support_strike"]) == 0 and int(d["support_interval_min"]) == 5 and not bool(d["support_bots"]),
		"Regeln: Unterstützung Standard aus, 5 min, KI aus")
	check(Net.RULE_KEYS.get("support_strike") == "supportstrike" and Net.RULE_KEYS.get("support_interval_min") == "supportinterval"
		and Net.RULE_KEYS.get("support_bots") == "supportbots", "Konsolen-/Konfigurationsschlüssel supportstrike/supportinterval/supportbots")
	var ct := LanMenu.config_text({"name": "x", "map": _map(), "support_strike": 3, "support_interval_min": 7, "support_bots": true})
	check(ct.contains("supportstrike 3") and ct.contains("supportinterval 7") and ct.contains("supportbots 1"),
		"Konfigurationsdatei des dedizierten Servers")
	check(SupportStrike.radio_model(SupportStrike.KIND_ART).get_meta("radio_model", "") != "", "Original-Funkgerätmodell (d_radio*) vorhanden")
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	var ok := Net.host({"name": "Funk", "map": _map(), "mode": int(Game.MISSIONS.get(_map(), {}).get("mp_mode", Net.Mode.TEAM_DEATHMATCH)),
		"port": Net.PORT + PORT_OFS, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 3,
		"bots_per_team": 1, "password": "", "allow_vehicles": false, "friendly_fire": false, "allow_respawn": true,
		"support_strike": 3, "support_interval_min": 1, "support_interval_s": 4.0, "support_bots": false, "flood_protect": false})
	check(ok and Net.is_online, "Server gestartet", Net.last_error)
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await wait_for(func(): return m.nav_ready, 240.0)
	m.controller.input_enabled = false
	var sup: SupportStrike = Net.support
	check(is_instance_valid(sup) and sup.map_open, "Unterstützung aktiv, Karte als offen erkannt", "%s open=%s" % [_map(), sup.map_open if sup else false])
	var info: Dictionary = Net.server_info()["rules"]
	check(int(info.get("support_strike", -1)) == 3 and int(info.get("support_interval_min", 0)) == 1, "SPIEL-INFO: Regeln in der Serverabfrage")
	check(FileAccess.get_file_as_string("res://src/ui/game_info_screen.gd").contains("Funk-Unterstützung"), "SPIEL-INFO zeigt Funk-Unterstützung")
	var orig_hidden := true
	for n in get_tree().get_nodes_in_group("world_items"):
		if int(n.get("item")) in SupportStrike.ITEM and n.visible:
			orig_hidden = false
	check(orig_hidden, "Frei liegende Original-Funkgeräte im Netz durch das Server-Funkgerät ersetzt")
	# Client
	var exe := OS.get_executable_path()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/support_strike_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	check(OS.create_process(exe, args + ["--", "--autoplay=test_support_strike", "--ss_peer=1"]) > 0, "Client-Prozess gestartet")
	await wait_for(func(): return _client_peer() != 0, 420.0)
	var cid := _client_peer()
	check(cid != 0, "Client beigetreten")
	if cid == 0:
		return
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("loaded"), 300.0)
	_freeze_bots()
	# Funkgerät erscheint (Test-Intervall 4 s)
	await wait_for(func(): return sup.radio_state == 1, 60.0)
	check(sup.radio_state == 1 and sup.radio_pos.is_finite() and sup.sky_open(sup.radio_pos), "Funkgerät erscheint auf begehbarem Boden unter freiem Himmel",
		str(sup.radio_pos))
	check(sup.radio_pos.distance_to(sup.center) < 400.0 or not sup.spawn_candidates.is_empty(), "Funkgerät ungefähr in der Kartenmitte bzw. an Original-Funkstelle")
	var first_kind := sup.radio_kind
	var base := sup.radio_pos
	var target := base + Vector3(6, 0, 0)
	var g := sup._find_ground(target)
	target = g if g.is_finite() else base
	var me: Soldier = Net._soldiers[1]
	me.global_position = target + Vector3.UP * 0.2
	me.set_meta("protect_until", 0)
	var puppet: Soldier = Net._soldiers[cid]
	# Ablehnung ohne Funkgerät
	check(sup.server_call(cid, first_kind, target) != "", "Anforderung ohne Funkgerät abgelehnt")
	_write(STEP_HOST, JSON.stringify({"step": "radio", "pos": [base.x, base.y, base.z], "kind": first_kind, "target": [target.x, target.y, target.z]}))
	await wait_for(func(): return sup.radio_state == 2 and sup.carrier == cid, 60.0)
	check(sup.radio_state == 2 and sup.carrier == cid, "Server: Client hat das Funkgerät aufgenommen")
	puppet.set_meta("protect_until", 0)
	var kf0 := Net.kill_feed.size()
	await wait_for(func(): return not sup.strikes.is_empty() or sup.ev_log.any(func(e): return String(e["ev"]) == "call"), 60.0)
	var call_ms := Time.get_ticks_msec()
	check(not sup.strikes.is_empty(), "Server: Schlag angefordert (Funkgerät verbraucht)", str(sup.radio_state))
	check(sup.radio_state == 0, "Funkgerät nach dem Schlag weg (genau ein Schlag)")
	check(sup.markers_shown >= 1, "Host: 3D-Kreis am Ziel sichtbar")
	await wait_for(func(): return sup.ev_log.any(func(e): return String(e["ev"]) == "wave"), 15.0)
	var c_ms := 0
	var w_ms := 0
	for ev in sup.ev_log:
		if String(ev["ev"]) == "call" and c_ms == 0:
			c_ms = int(ev["ms"])
		if String(ev["ev"]) == "wave" and w_ms == 0:
			w_ms = int(ev["ms"])
	var dt: int = w_ms - c_ms if c_ms > 0 and w_ms > 0 else Time.get_ticks_msec() - call_ms
	check(dt >= 4200 and dt <= 6500, "Einschlag nach ca. 5 s", "%d ms" % dt)
	await wait_for(func(): return not me.alive, 5.0)
	check(not me.alive, "Host im Wirkungsbereich getötet")
	await get_tree().create_timer(0.5).timeout
	var e: Dictionary = Net.kill_feed.back() if Net.kill_feed.size() > 0 else {}
	check(Net.kill_feed.size() > kf0 and int(e.get("killer", 0)) == cid and String(e.get("cause", "")) == SupportStrike.CAUSE[first_kind],
		"Kill-Feed: Funker als Schütze, Ursache %s" % SupportStrike.CAUSE[first_kind], str(e))
	check(FB.weapon_label(String(e.get("cause", ""))) != "" and FB.weapon_icon(String(e.get("cause", "")), 0) != null,
		"Kill-Feed: Bezeichnung und Funkgerätsymbol", FB.weapon_label(String(e.get("cause", ""))))
	check(sup.booms >= 3, "Host: Explosionen dargestellt", str(sup.booms))
	if first_kind == SupportStrike.KIND_AIR:
		check(sup.planes_shown >= 1, "Luftangriff: Flugzeug-Überflug")
	_write(STEP_HOST, JSON.stringify({"step": "struck", "kind": first_kind}))
	# Zweites Funkgerät (andere Art), Host nimmt es selbst und trifft den Client
	await wait_for(func(): return Net._soldiers.has(1) and is_instance_valid(Net._soldiers[1]) and Net._soldiers[1].alive, 30.0)
	await wait_for(func(): return sup.radio_state == 1, 30.0)
	check(sup.radio_state == 1 and sup.radio_kind != first_kind, "Zweites Funkgerät mit der anderen Art (abwechselnd)", str(sup.radio_kind))
	me = Net._soldiers[1]
	me.global_position = sup.radio_pos + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO
	var picked := sup.server_pickup(1)
	check(picked and sup.carrying(), "Host nimmt das Funkgerät auf", "alive=%s d=%.1f state=%d" % [me.alive, me.global_position.distance_to(sup.radio_pos), sup.radio_state])
	check(sup.open_menu() and sup.menu_open, "Host: Untermenü öffnet")
	var ml := sup.menu_lines()
	check(not ml[sup.radio_kind + 1].contains("(–)") and ml[2 - sup.radio_kind].contains("(–)"),
		"Untermenü wie Original: nur passende Art wählbar (T7280/T7281)", " | ".join(ml))
	check(not sup.choose(1 - sup.radio_kind) and sup.targeting == -1, "Falsche Art nicht wählbar")
	sup.open_menu()
	var k2 := sup.radio_kind
	check(sup.choose(k2) and sup.targeting == k2, "Zielwahl gestartet")
	puppet = Net._soldiers[cid]
	puppet.set_meta("protect_until", 0)
	var cpos := puppet.global_position
	var aw: Vector3 = sup._find_ground(base + Vector3(-45, 0, 0))
	if not cpos.is_finite() or (aw.is_finite() and cpos.distance_to(aw) > 3.0):
		cpos = aw if aw.is_finite() else base + Vector3(-45, 0, 0)
	me.global_position = cpos + Vector3(40, 0, 0) if sup._find_ground(cpos + Vector3(40, 0, 0)).is_finite() else me.global_position
	_write(STEP_HOST, JSON.stringify({"step": "second", "kind": k2}))
	sup.confirm_target(cpos)
	check(not sup.strikes.is_empty(), "Host: zweiter Schlag angefordert", "%s cpos=%s sky=%s" % [str(sup.ev_log.slice(-3)), cpos, sup.sky_open(cpos)])
	await wait_for(func(): return not puppet.alive or not is_instance_valid(puppet), 12.0)
	await get_tree().create_timer(0.5).timeout
	e = Net.kill_feed.back() if Net.kill_feed.size() > 0 else {}
	check(String(e.get("cause", "")) == SupportStrike.CAUSE[k2] and int(e.get("killer", 0)) == 1,
		"Zweiter Schlag: Client getötet, Ursache %s" % SupportStrike.CAUSE[k2], str(e))
	check(SupportStrike.RADIUS[SupportStrike.KIND_ART] == 10.0 and SupportStrike.RADIUS[SupportStrike.KIND_AIR] == 12.5
		and SupportStrike.WAVE_STRENGTH[SupportStrike.KIND_ART] * SupportStrike.WAVES[SupportStrike.KIND_ART]
			> SupportStrike.WAVE_STRENGTH[SupportStrike.KIND_AIR] * SupportStrike.WAVES[SupportStrike.KIND_AIR],
		"Artillerie 20 m stark, Luftangriff 25 m schwächer")
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("second_done"), 60.0)
	# Bots (supportbots)
	Net.server_command("supportbots 1", 0)
	await wait_for(func(): return sup.radio_state == 1, 30.0)
	var bot: Soldier = null
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]) and Net._soldiers[id].alive:
			bot = Net._soldiers[id]
	if bot:
		var bb = bot.get_node_or_null("EnemyBrain")
		check(bb == null or sup.bot_goal(bb).is_finite() or not bb.is_leader(), "KI-Führer läuft zum Funkgerät (bot_goal)")
		bot.global_position = sup.radio_pos + Vector3.UP * 0.2
		await wait_for(func(): return sup.radio_state == 2 and sup.carrier < 0, 5.0)
		check(sup.radio_state == 2 and sup.carrier < 0, "KI nimmt das Funkgerät auf (supportbots)")
	# Abschalten per Konsole
	var r := Net.server_command("supportstrike 0", 0)
	await get_tree().create_timer(0.5).timeout
	check(r.contains("supportstrike") and sup.radio_state == 0 and not sup.enabled(), "Konsole „supportstrike 0“ schaltet ab", r)
	_write(STEP_HOST, JSON.stringify({"step": "done"}))
	await wait_for(func(): return FileAccess.file_exists(RESULT), 120.0)
	for l in _read(RESULT).split("\n"):
		if l.begins_with("PASS") or l.begins_with("FAIL"):
			check(l.begins_with("PASS"), "Client: " + l.substr(6))


# --- Client --------------------------------------------------------------------------------------------

func _client() -> void:
	Net.local_name = "Gast"
	Net.local_team = Soldier.TEAM_AXIS
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", Net.PORT + PORT_OFS, "")
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() \
		and Net._soldiers.has(Net.my_id()) and is_instance_valid(Net.support), 420.0)
	var m: Mission = Game.current_mission()
	var sup: SupportStrike = Net.support
	await wait_for(func(): return sup.map_open, 10.0)
	check(is_instance_valid(sup) and sup.map_open, "Client: Unterstützung vorhanden, Karte offen")
	m.controller.input_enabled = false
	_write(STEP_CLIENT, "loaded")
	await wait_for(func(): return _read(STEP_HOST).contains("\"radio\""), 200.0)
	var st = JSON.parse_string(_read(STEP_HOST))
	await wait_for(func(): return sup.radio_state == 1, 20.0)
	check(sup.radio_state == 1 and is_instance_valid(sup._radio_node) and sup._radio_node.is_inside_tree(), "Client: Funkgerät sichtbar")
	var me: Soldier = Net._soldiers[Net.my_id()]
	me.global_position = sup.radio_pos + Vector3.UP * 0.2
	await get_tree().create_timer(1.0).timeout      # eigene Lage beim Server
	check(sup._radio_node.can_interact(me), "Client: Funkgerät aufnehmbar (Benutzen)")
	sup._radio_node.interact(me)
	await wait_for(func(): return sup.carrying(), 10.0)
	check(sup.carrying(), "Client: Funkgerät getragen (vom Server bestätigt)")
	check(sup.open_menu() and sup.menu_open, "Client: Untermenü „Unterst. anf.“ öffnet")
	var k := int(st["kind"])
	check(sup.choose(k) and sup.targeting == k, "Client: Zielwahl")
	var tp: Array = st["target"]
	var bp: Array = st["pos"]
	var away: Vector3 = sup._find_ground(Vector3(bp[0], bp[1], bp[2]) + Vector3(-45, 0, 0))
	me.global_position = (away if away.is_finite() else Vector3(bp[0], bp[1] + 2.0, bp[2]) + Vector3(-45, 0, 0)) + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	sup.confirm_target(Vector3(tp[0], tp[1], tp[2]))
	await wait_for(func(): return sup.markers_shown >= 1, 10.0)
	check(sup.markers_shown >= 1 and sup.radio_state == 0, "Client: 3D-Kreis empfangen, Funkgerät verbraucht")
	await wait_for(func(): return sup.booms >= 3, 12.0)
	check(sup.booms >= 3, "Client: Einschläge empfangen")
	if k == SupportStrike.KIND_AIR:
		check(sup.planes_shown >= 1, "Client: Flugzeug-Überflug")
	await wait_for(func(): return Net.kill_feed.any(func(e): return String(e["cause"]) == SupportStrike.CAUSE[k]), 10.0)
	check(Net.kill_feed.any(func(e): return String(e["cause"]) == SupportStrike.CAUSE[k] and int(e["killer"]) == Net.my_id()),
		"Client: Kill-Feed mit Ursache %s" % SupportStrike.CAUSE[k])
	await wait_for(func(): return _read(STEP_HOST).contains("\"second\""), 60.0)
	await wait_for(func(): return sup.markers_shown >= 2, 10.0)
	check(sup.markers_shown >= 2, "Client: zweiter Zielkreis sichtbar")
	await wait_for(func(): return Net.kill_feed.any(func(e): return int(e["killer"]) == 1 and String(e["cause"]).begins_with("support_")), 15.0)
	check(Net.kill_feed.any(func(e): return int(e["killer"]) == 1 and String(e["cause"]).begins_with("support_")), "Client: eigener Tod im Kill-Feed (Unterstützung)")
	_write(STEP_CLIENT, "second_done")
	await wait_for(func(): return _read(STEP_HOST).contains("\"done\""), 120.0)
	_write(RESULT, "\n".join(lines))


func _finish() -> void:
	if peer_mode:
		if not FileAccess.file_exists(RESULT):
			_write(RESULT, "\n".join(lines))
		Net.leave(false)
		get_tree().quit(0)
		return
	print("ERGEBNIS: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	_write(ProjectSettings.globalize_path("res://test_output/test_support_strike.txt"), "\n".join(lines) + "\nERGEBNIS: %d/%d\n" % [passed, passed + failed])
	Net.leave(false)
	get_tree().quit(1 if failed > 0 else 0)
