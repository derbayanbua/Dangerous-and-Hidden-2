extends Node
## Mehrspieler-Rückmeldungen, zwei echte ENet-Prozesse (Team-Deathmatch, 1 KI je Team, Kill-Cam an; Karte: erste
##  Team-DM-Karte der Hauptauswahl – mit lokalen Zusatzinhalten deren eigene Karte, sonst Arena; --mf_map=<id>):
##  Host (Alliierte) + Client (Achse). Prüft Original-Figuren auf der Karte (Spieler/Bots, Seite, Waffe in der Hand),
##  serverbestätigte Trefferanzeige beim Schützen (Host und Client), Treffergeräusch, Richtungsanzeige beim Getroffenen,
##  Kill-Feed bei beiden (Waffensymbol, Kopfschuss), Namen (Teamkamerad sichtbar, durch Wand verdeckt, Gegner nur beim
##  Anvisieren, Reichweite, Tarnung, Deathmatch ohne Teamnamen), Kill-Cam (Tod → Kamera auf Schützen → Überspringen →
##  Feuer → Respawn), keine Kill-Cam bei Selbsttötung, FPS-Option/Konsole, Server-Regeln.
##   tools\godot.cmd --headless -- --autoplay=test_mp_feedback
## Client-Teilprozess (startet der Test selbst): --mf_peer=1

const PORT_OFS := 47
const FALLBACK_MAP := "mp_arena_a1_blizzard"
const STEP_HOST := "user://mf_step_host.json"
const STEP_CLIENT := "user://mf_step_client.txt"
const RESULT := "user://mf_client_result.txt"
const FB := preload("res://src/ui/mp_feedback.gd")

## Testkarte: --mf_map, sonst erste Team-DM-Karte der Hauptauswahl (lokale Zusatzkarten stehen vorn), sonst Arena
static func _map() -> String:
	if Game.cli.has("mf_map"):
		return String(Game.cli["mf_map"])
	for id in Game.MP_MAPS:
		if int(Game.MISSIONS.get(id, {}).get("mp_mode", -1)) == Net.Mode.TEAM_DEATHMATCH:
			return String(id)
	return FALLBACK_MAP


var passed := 0
var failed := 0
var lines: PackedStringArray = []
var peer_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("mf_peer")
	get_tree().create_timer(900.0 if peer_mode else 1500.0, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func _client_peer() -> int:
	for id in Net._soldiers:
		if int(id) > 1 and is_instance_valid(Net._soldiers[id]):
			return int(id)
	return 0


func _client_loaded() -> bool:
	var mm = Game.current_mission()
	return mm != null and mm.is_node_ready() and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1) and _bots().size() == 2


func _respawned(old: Soldier) -> bool:
	var s2: Soldier = Net._soldiers.get(Net.my_id())
	return is_instance_valid(s2) and s2.alive and s2 != old


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


func _hud():
	var m = Game.current_mission()
	return m.get_node_or_null("MpHud") if m else null


func _bots() -> Dictionary:
	var out := {}
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(s) and s.alive:
			out[s.team] = s
	return out


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
	else:
		await _host()
	_finish()


## Figuren wie auf Original-MP-Karten: Klassen-Uniform (Achse GE03, Alliierte EN08), Helden eigenes Modell
## (nur lokale Helden, Net.heroes()), Waffe an der Hand
func _check_figures(tag: String) -> void:
	var n := 0
	var bad: PackedStringArray = []
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if not is_instance_valid(s) or not s.alive:
			continue
		n += 1
		var fig: Node3D = s.model.orig_figure if s.model else null
		var side := "axis" if s.team == Soldier.TEAM_AXIS else "allied"
		var want: String = String(Net.MP_UNIFORM_MODEL[side])
		if Net.heroes().any(func(h): return String(h.get("name", "")) == s.soldier_name):
			want = Net.figure_model("hero:" + side, side)
		elif Net.uniform_model(int(s.get_meta("mp_uniform", -1))) != "":
			want = Net.uniform_model(int(s.get_meta("mp_uniform", -1)))
		var got: String = String(fig.get_meta("figure_model", "")) if is_instance_valid(fig) else "-"
		var wm: Node3D = s.model.get("_weapon_mesh")
		var in_hand := is_instance_valid(wm) and is_instance_valid(fig) and fig.is_ancestor_of(wm)
		if not got.begins_with(want) or not in_hand:      # Knotenname mit Zählsuffix (z. B. „en012“)
			bad.append("%s:%s/%s hand=%s" % [s.soldier_name, got, want, in_hand])
	check(n >= 3 and bad.is_empty(), "%s: Original-Figuren auf der Karte (Seite passend, Waffe in der Hand)" % tag,
		"%d Soldaten %s" % [n, ", ".join(bad)])


# --- Host ----------------------------------------------------------------------------------------------

func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT, RESULT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var dm := Net.style_defaults(Net.Mode.DEATHMATCH)
	var tdm := Net.style_defaults(Net.Mode.TEAM_DEATHMATCH)
	check(dm["kill_cam"] and not tdm["kill_cam"] and dm["show_names"] and dm["hit_indicator"],
		"Server-Regeln: Kill-Cam Standard nur Deathmatch, Namen/Trefferanzeige an")
	check(Net.RULE_KEYS.get("kill_cam") == "killcam" and Net.RULE_KEYS.get("show_names") == "shownames"
		and Net.RULE_KEYS.get("hit_indicator") == "hitindicator", "Konsolen-/Konfigurationsschlüssel killcam/shownames/hitindicator")
	var ct := LanMenu.config_text({"name": "x", "map": _map(), "kill_cam": true, "show_names": false, "hit_indicator": true})
	check(ct.contains("killcam 1") and ct.contains("shownames 0") and ct.contains("hitindicator 1"), "Konfigurationsdatei des dedizierten Servers")
	# FPS-Option (Konsole lokal, Overlay am Autoload Settings)
	var ov = Settings.get_node_or_null("FpsOverlay")
	check(ov != null and not Settings.show_fps and not ov.visible, "FPS-Anzeige vorhanden, Standard aus")
	Net.console_command("fps 1")
	await get_tree().process_frame
	check(Settings.show_fps and ov.visible and String(ov.label.text).ends_with("FPS"), "Konsole „fps 1“: Anzeige an", ov.label.text)
	Net.console_command("fps")
	await get_tree().process_frame
	check(not Settings.show_fps and not ov.visible, "Konsole „fps“: umgeschaltet (aus)")
	# Server: Team-Deathmatch, Host Alliierte, Kill-Cam per Servereinstellung an
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	Net.local_figure = ""
	var ok := Net.host({"name": "MP-Feedback", "map": _map(), "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + PORT_OFS,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 1,
		"password": "", "allow_vehicles": false, "kill_cam": true, "friendly_fire": false})
	check(ok and Net.is_online, "Server gestartet", Net.last_error)
	var m: Mission = null
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	m = Game.current_mission()
	await wait_for(func(): return m.nav_ready and _bots().size() == 2, 240.0)
	check(_bots().size() == 2, "Zwei KI-Soldaten (je Team einer)")
	_check_figures("Host")
	var me: Soldier = Net._soldiers.get(1)
	var hf: String = String(me.model.orig_figure.get_meta("figure_model", "")) if is_instance_valid(me.model.orig_figure) else "-"
	check(hf.begins_with("en08") and int(me.get_meta("mp_uniform", -1)) == 123, "Host (Alliierte): Klassen-Uniform EN08 (Gegenstand 123)", hf)
	# Client starten
	var exe := OS.get_executable_path()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_feedback_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, args + ["--", "--autoplay=test_mp_feedback", "--mf_peer=1"])
	check(pid > 0, "Client-Prozess gestartet")
	await wait_for(func(): return _client_peer() != 0, 420.0)
	var cid := _client_peer()
	check(cid != 0 and int(Net.players[cid]["team"]) == Soldier.TEAM_AXIS, "Client beigetreten (Achse)")
	if cid == 0:
		return
	# Bots anhalten und aufstellen: freie Richtung ab Host-Standort suchen
	var bots := _bots()
	for t in bots:
		var b: Soldier = bots[t]
		var br := b.get_node_or_null("EnemyBrain")
		if br:
			br.process_mode = Node.PROCESS_MODE_DISABLED
		b.move_input = Vector3.ZERO
		b.trigger = false
		b.set_meta("protect_until", 0)
	me.set_meta("protect_until", 0)
	m.controller.input_enabled = false
	# offener Platz (Zonenmitte mit freiem Umkreis, tests/shots_mp_feedback.gd): Client in der Mitte, Teamkamerad
	# (Achsen-Bot) 5 m seitlich, Gegner (alliierter Bot) 8 m voraus, Host abseits
	var base: Vector3 = load("res://tests/shots_mp_feedback.gd")._open_spot(m, me.global_position, me)
	var client_pos := base
	var axis_pos := base + Vector3(5.0, 0.0, 0.0)
	var allied_pos := base + Vector3(0.0, 0.0, -8.0)
	me.global_position = base + Vector3(-5.0, 0.0, 6.0)
	(bots[Soldier.TEAM_ALLIED] as Soldier).global_position = allied_pos
	(bots[Soldier.TEAM_AXIS] as Soldier).global_position = axis_pos
	await get_tree().create_timer(1.0).timeout
	_write(STEP_HOST, JSON.stringify({"step": "pos", "client": [client_pos.x, client_pos.y, client_pos.z],
		"allied": int(Net._soldiers.find_key(bots[Soldier.TEAM_ALLIED])), "axis": int(Net._soldiers.find_key(bots[Soldier.TEAM_AXIS]))}))
	# Host-Treffer auf den gegnerischen Achsen-Bot: Kopf, dann tödlich
	var hud = _hud()
	var fb = hud.feedback
	var axis_bot: Soldier = bots[Soldier.TEAM_AXIS]
	var n0: int = fb.hits_shown
	var s0: int = fb.sounds_played
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("names_done"), 240.0)
	check(_read(STEP_CLIENT).begins_with("names_done"), "Client: Namensprüfung abgeschlossen")
	axis_bot.apply_hit(20.0, &"head", me, Vector3.FORWARD)
	await get_tree().process_frame
	check(fb.hits_shown == n0 + 1 and fb.hit_kind == "head" and String(Net.hit_log.back()["zone"]) == "head",
		"Host: serverbestätigter Kopftreffer → Hitmarker (Kopf)", "%s %d" % [fb.hit_kind, fb.hits_shown])
	check(fb.sounds_played > s0 and String(fb.last_sound).begins_with("flesh"), "Host: Treffergeräusch (Original „Flash or Dead Body“)", fb.last_sound)
	check(String(fb.hit_text).contains(axis_bot.soldier_name) and String(fb.hit_text).contains(Net.tx(8802, "Kopf")),
		"Host: Original-Treffermeldung T8851 mit Zone", fb.hit_text)
	var kf0 := Net.kill_feed.size()
	var wid: String = String(me.current_weapon().data.id) if me.current_weapon() else ""
	axis_bot.apply_hit(500.0, &"torso", me, Vector3.FORWARD)
	await get_tree().process_frame
	check(fb.hit_kind == "kill", "Host: Tötungstreffer → Hitmarker (tödlich)", fb.hit_kind)
	var e: Dictionary = Net.kill_feed.back() if not Net.kill_feed.is_empty() else {}
	check(Net.kill_feed.size() >= mini(kf0 + 1, Net.KILL_FEED_MAX) and int(e.get("killer", 0)) == 1 and String(e.get("cause", "")) == wid
		and not bool(e.get("tk", true)) and FB.feed_entries().size() >= 1, "Host: Kill-Feed-Eintrag Host [Waffe] Bot", str(e))
	check(FB.weapon_icon(wid, Soldier.TEAM_ALLIED) != null, "Kill-Feed: Original-Waffensymbol wi_* für %s" % wid)
	# Client-Treffer (vom Server bestätigt): Client-Figur trifft den alliierten Bot; dann tötet der Host den Client (Kopf)
	var puppet: Soldier = Net._soldiers[cid]
	puppet.set_meta("protect_until", 0)
	(bots[Soldier.TEAM_ALLIED] as Soldier).apply_hit(15.0, &"arm", puppet, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout
	_write(STEP_HOST, JSON.stringify({"step": "client_hit"}))
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("ready_to_die"), 60.0)
	puppet.apply_hit(500.0, &"head", me, Vector3.FORWARD)
	await get_tree().process_frame
	var e2: Dictionary = Net.kill_feed.back() if not Net.kill_feed.is_empty() else {}
	check(int(e2.get("victim", 0)) == cid and bool(e2.get("head", false)), "Host: Kill-Feed Host → Client mit Kopfschuss-Marke", str(e2))
	_write(STEP_HOST, JSON.stringify({"step": "killed"}))
	# Ergebnisse des Clients abwarten (Kill-Cam, Überspringen, Respawn)
	await wait_for(func(): return FileAccess.file_exists(RESULT), 300.0)
	for line in _read(RESULT).split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	# Selbsttötung: keine Kill-Cam beim Host
	var kc = hud.kill_cam
	var shown0: int = kc.shown
	me = Net._soldiers.get(1)
	if is_instance_valid(me) and me.alive:
		me.set_meta("protect_until", 0)
		me.apply_hit(500.0, &"torso", me, Vector3.ZERO)
		await get_tree().process_frame
		check(not me.alive and kc.shown == shown0 and not kc.active, "Selbsttötung: keine Kill-Cam")
		var e3: Dictionary = Net.kill_feed.back()
		check(bool(e3.get("suicide", false)) and int(e3.get("victim", 0)) == 1, "Kill-Feed: Selbstmord gekennzeichnet")
	Net.leave(false)


# --- Client --------------------------------------------------------------------------------------------

func _client() -> void:
	var res: PackedStringArray = []
	Net.local_name = "Gast"
	Net.local_team = Soldier.TEAM_AXIS
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", Net.PORT + PORT_OFS, "")
	await wait_for(_client_loaded, 420.0)
	var m: Mission = Game.current_mission()
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(is_instance_valid(me) and me.team == Soldier.TEAM_AXIS, "Eigener Soldat (Achse)")
	if not is_instance_valid(me):
		_write(RESULT, "\n".join(lines))
		return
	_check_figures("Client")
	var cf: String = String(me.model.orig_figure.get_meta("figure_model", "")) if is_instance_valid(me.model.orig_figure) else "-"
	check(cf.begins_with("ge03"), "Client (Achse): Klassen-Uniform GE03", cf)
	await wait_for(func(): return _read(STEP_HOST).contains("\"pos\""), 240.0)
	var st = JSON.parse_string(_read(STEP_HOST))
	var cp: Array = st.get("client", [0, 0, 0]) if st is Dictionary else [0, 0, 0]
	var allied: Soldier = Net._soldiers.get(int(st.get("allied", 0))) if st is Dictionary else null
	var axis: Soldier = Net._soldiers.get(int(st.get("axis", 0))) if st is Dictionary else null
	m.controller.input_enabled = false
	me.global_position = Vector3(cp[0], cp[1], cp[2])
	await get_tree().create_timer(2.0).timeout           # Bot-Lagen kommen an (20 Hz), eigener Stand stabil
	check(is_instance_valid(allied) and is_instance_valid(axis), "Bots auf dem Client vorhanden")
	if is_instance_valid(allied) and is_instance_valid(axis):
		await _client_names(m, me, allied, axis)
	_write(STEP_CLIENT, "names_done")
	# Trefferbestätigung des Servers für den Client (Arm-Treffer auf den alliierten Bot)
	await wait_for(func(): return _read(STEP_HOST).contains("client_hit"), 120.0)
	await wait_for(func(): return not Net.hit_log.is_empty(), 10.0)
	var fb = _hud().feedback
	var h: Dictionary = Net.hit_log.back() if not Net.hit_log.is_empty() else {}
	check(String(h.get("zone", "")) == "arm" and fb.hit_kind == "body" and fb.hits_shown >= 1,
		"Client: serverbestätigter Treffer → Hitmarker beim Schützen", str(h))
	check(Net.kill_feed.any(func(e): return int(e["killer"]) == 1 and int(e["vteam"]) == Soldier.TEAM_AXIS),
		"Client: Kill-Feed-Eintrag des Host-Abschusses empfangen")
	# Tod durch den Host → Richtungsanzeige, Kill-Feed, Kill-Cam auf den Schützen
	var kc = _hud().kill_cam
	var hurts0 := Net.hurt_log.size()
	_write(STEP_CLIENT, "ready_to_die")
	await wait_for(func(): return not me.alive, 60.0)
	await get_tree().process_frame
	check(not me.alive, "Client getötet (Server)")
	check(Net.hurt_log.size() > hurts0 and fb.active_hurts().size() >= 1, "Client: Richtungsanzeige des erlittenen Treffers")
	var host: Soldier = Net._soldiers.get(1)
	if not Net.hurt_log.is_empty() and is_instance_valid(host):
		check((Net.hurt_log.back()["pos"] as Vector3).distance_to(host.global_position) < 2.0, "Richtung zeigt auf den Schützen")
	var e2: Dictionary = Net.kill_feed.back() if not Net.kill_feed.is_empty() else {}
	check(int(e2.get("killer", 0)) == 1 and int(e2.get("victim", 0)) == Net.my_id() and bool(e2.get("head", false)),
		"Client: Kill-Feed Host → Gast (Kopfschuss)", str(e2))
	check(kc.active and kc.killer_id == 1 and kc.cam.current, "Kill-Cam aktiv, Kamera auf dem Schützen")
	await get_tree().create_timer(1.2).timeout
	if kc.active and is_instance_valid(host):
		var info: String = kc.info_text()
		check(info.contains("Host") and info.contains("LP") and info.contains(" m"), "Kill-Cam-Einblendung: Name, Waffe, Entfernung, LP", info.replace("\n", " | "))
		check(kc.cam.global_position.distance_to(host.global_position) < 7.0, "Kill-Cam-Kamera beim Schützen",
			"%.1f m" % kc.cam.global_position.distance_to(host.global_position))
	# Überspringen (Feuer) vor der Respawn-Bereitschaft → Original-Anzeige, dann Feuer → Respawn
	var ev := InputEventAction.new()
	ev.action = "fire"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not kc.active and kc.skipped and m.rig.camera.current, "Kill-Cam per Feuertaste übersprungen")
	await wait_for(func(): return Net.respawn_ready(), 20.0)
	check(String(_hud().state_text()) == Net.tx(7406, "FEUER DRÜCKEN FÜR RESPAWN"), "Danach Original-Anzeige „FEUER DRÜCKEN FÜR RESPAWN“")
	var t_ready := Time.get_ticks_msec()
	var ev2 := InputEventAction.new()
	ev2.action = "fire"
	ev2.pressed = true
	Input.parse_input_event(ev2)
	var back: bool = await wait_for(_respawned.bind(me), 10.0)
	check(back and Time.get_ticks_msec() - t_ready < 2500, "Feuer → sofortiger Respawn", "%d ms" % (Time.get_ticks_msec() - t_ready))
	_write(RESULT, "\n".join(lines))
	await wait_for(func(): return not Net.is_online, 120.0)


func _cam_at(m: Mission, from: Vector3, look: Vector3) -> Camera3D:
	var c := Camera3D.new()
	m.add_child(c)
	c.global_position = from
	c.look_at(look, Vector3.UP)
	return c


## Diagnose: was der Fadenkreuzstrahl trifft (Klasse/Name/Abstand) und Lage der Ziel-Trefferzonen
static func _ray_dbg(cam: Camera3D, me: Soldier, target: Soldier) -> String:
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 90.0, 1 | Hitbox.LAYER)
	q.collide_with_areas = true
	q.exclude = me.exclude_rids()
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var hb := target.find_children("*", "Hitbox", true, false)
	var hbs := ""
	for h in hb:
		hbs += "%s@%s " % [(h as Hitbox).zone, str((h as Node3D).global_position.snapped(Vector3.ONE * 0.1))]
	var what := "nichts" if hit.is_empty() else "%s %s %.1f m" % [hit.collider.get_class(), hit.collider.name, cam.global_position.distance_to(hit.position)]
	return "Strahl: %s | Ziel %s | Zonen: %s" % [what, str(target.global_position.snapped(Vector3.ONE * 0.1)), hbs]


static func _tag(tags: Array, s: Soldier) -> Dictionary:
	for t in tags:
		if int(t["id"]) == int(Net._soldiers.find_key(s)):
			return t
	return {}


func _client_names(m: Mission, me: Soldier, allied: Soldier, axis: Soldier) -> void:
	var eye := me.eye_position()
	var mate_head: Vector3 = FB.head_point(axis)
	var foe_head: Vector3 = FB.head_point(allied)
	# Teamkamerad (Achsen-Bot) sichtbar, auch ohne Anvisieren; Gegner (alliierter Bot) dabei nicht
	var cam := _cam_at(m, eye, mate_head + Vector3(1.5, 0, 0))
	var tags: Array = FB.compute_name_tags(cam)
	var t := _tag(tags, axis)
	check(not t.is_empty() and t["kind"] == "team" and t["color"] == FB.team_color(Soldier.TEAM_AXIS) and t["name"] == axis.soldier_name,
		"Teamkamerad: Name in Teamfarbe sichtbar", "%s | ich %s lebt=%s | Kamerad %s" % [str(tags),
		str(me.global_position.snapped(Vector3.ONE * 0.1)), me.alive, str(axis.global_position.snapped(Vector3.ONE * 0.1))])
	check(_tag(tags, allied).is_empty(), "Gegner ohne Anvisieren: kein Name")
	# Wand zwischen Kamera und Teamkamerad → verdeckt
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3, 4, 0.3)
	cs.shape = bx
	wall.add_child(cs)
	m.add_child(wall)
	wall.global_position = eye.lerp(mate_head, 0.5)
	wall.look_at(mate_head, Vector3.UP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(_tag(FB.compute_name_tags(cam), axis).is_empty(), "Teamkamerad hinter Wand: kein Name")
	wall.queue_free()
	await get_tree().physics_frame
	# Gegner direkt anvisiert → Name (Gegnerfarbe); knapp daneben → keiner
	cam.look_at(allied.eye_position() + Vector3(0, -0.4, 0), Vector3.UP)
	var ft := _tag(FB.compute_name_tags(cam), allied)
	check(not ft.is_empty() and ft["kind"] == "aimed" and ft["color"] == FB.team_color(Soldier.TEAM_ALLIED), "Gegner angevisiert: Name sichtbar",
		_ray_dbg(cam, me, allied))
	cam.look_at(foe_head + (foe_head - eye).cross(Vector3.UP).normalized() * 2.5, Vector3.UP)
	check(_tag(FB.compute_name_tags(cam), allied).is_empty(), "Gegner nicht angevisiert: kein Name")
	# Gegner angevisiert, aber zu weit (90 m)
	var far := foe_head + (eye - foe_head).normalized() * 90.0
	var cam2 := _cam_at(m, far, allied.eye_position() + Vector3(0, -0.4, 0))
	check(_tag(FB.compute_name_tags(cam2), allied).is_empty(), "Gegner außerhalb der Reichweite: kein Name")
	cam2.queue_free()
	# Tarnung: getarnter Gegner erscheint wie ein Teamkamerad (eigene Farbe), auch ohne Anvisieren
	allied.disguised = true
	cam.look_at(foe_head + (foe_head - eye).cross(Vector3.UP).normalized() * 2.5, Vector3.UP)   # im Bild, nicht angevisiert
	var dt := _tag(FB.compute_name_tags(cam), allied)
	check(not dt.is_empty() and dt["kind"] == "team" and dt["color"] == FB.team_color(Soldier.TEAM_AXIS), "Getarnter Gegner: wie eigenes Team, nicht verraten")
	allied.disguised = false
	# Deathmatch: keine Teamnamen
	var mode0: int = Net.settings.get("mode", 1)
	Net.settings["mode"] = Net.Mode.DEATHMATCH
	check(_tag(FB.compute_name_tags(cam), axis).is_empty(), "Deathmatch: keine Teamnamen")
	Net.settings["mode"] = mode0
	# Optionen: Namen abschalten
	Settings.show_names = false
	check(FB.compute_name_tags(cam).is_empty(), "Option „Namen über Spielern“ aus: keine Namen")
	Settings.show_names = true
	cam.queue_free()


func _finish() -> void:
	if peer_mode:
		if not FileAccess.file_exists(RESULT):
			_write(RESULT, "\n".join(lines))
		Net.leave(false)
		get_tree().quit(0)
		return
	print("ERGEBNIS: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	_write(ProjectSettings.globalize_path("res://test_output/test_mp_feedback.txt"), "\n".join(lines) + "\nERGEBNIS: %d/%d\n" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)
