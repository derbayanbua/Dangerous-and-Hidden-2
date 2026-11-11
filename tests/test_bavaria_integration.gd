extends Node
## Bavaria – Spielintegration (Auswahl, Spielstile, Rotation, dedizierter Server, Spawns/Zonen/Navmesh,
## Waffenfreigabe/Klassen, Stellungen, Untergrund, Bots, zwei echte ENet-Prozesse). Kartengestaltung prüft
## weiterhin tests/test_bavaria_map.gd (Gestaltungs-Agent).
##   tools\godot.cmd --headless -- --autoplay=test_bavaria_integration [--phase=local|mp]
## Teilprozess (Client, startet der Test selbst): --bi_peer=1

const IDS := ["bavaria", "bavaria_occupation", "bavaria_tdm"]
const MODES := [0, 2, 1]          # Net.Mode: DEATHMATCH, OCCUPATION, TEAM_DEATHMATCH
const MP_PORT_OFS := 43

var passed := 0
var failed := 0
var peer_mode := false
var child_pid := -1
var metrics: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("bi_peer")
	get_tree().create_timer(300.0 if peer_mode else 1800.0, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func check(ok: bool, label: String, detail := "") -> void:
	var line: String = ("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")")
	print(line)
	if ok:
		passed += 1
	else:
		failed += 1


func wait_for(condition: Callable, s := 60.0) -> bool:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return bool(condition.call())


func _chat_has(text: String) -> bool:
	for e in Net.chat_log:
		if String(e.get("text", "")) == text:
			return true
	return false


func _chat_prefix(prefix: String) -> String:
	for e in Net.chat_log:
		var t := String(e.get("text", ""))
		if t.begins_with(prefix):
			return t
	return ""


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
		_finish()
		return
	var phase := String(Game.cli.get("phase", "all"))
	if phase in ["all", "local"]:
		await _registry_and_menus()
		_dedicated_config()
		await _free_view()
		await _styles_and_rotation()
	if phase in ["all", "mp"]:
		await _two_process()
	_finish()


# --- 1. Register, LAN-/Internet-Menü, Rotation ----------------------------------------------------------

func _registry_and_menus() -> void:
	for i in IDS.size():
		var id: String = IDS[i]
		var pos := Game.MP_MAPS.size() - IDS.size() + i
		check(Game.MP_MAPS.find(id) == pos and Game.MISSIONS.has(id), "Register: Testkarte %s am Listenende (Position %d)" % [id, pos])
		check(bool(Game.MISSIONS[id].get("test_map", false)) and String(Game.MISSIONS[id].get("title", "")).begins_with("Bavaria (Test"),
			"Register: als Testkarte gekennzeichnet (%s)" % String(Game.MISSIONS[id].get("title", "")))
		check(int(Game.MISSIONS[id].get("mp_mode", -1)) == int(MODES[i]), "Register: fester Spielstil %s" % Net.MODE_NAMES[MODES[i]])
		var img := String(Game.MISSIONS[id].get("map_image", ""))
		check(img == "" or ResourceLoader.exists(img), "Kartenbild optional, falls eingetragen vorhanden: " + id)
	check(Game.PRACTICE_MISSIONS.has("bavaria"), "Einzelspieler: freie Besichtigung in den Übungseinsätzen")
	var menu = get_tree().current_scene
	await wait_for(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("open_lan"), 30.0)
	menu = get_tree().current_scene
	if menu == null or not menu.has_method("open_lan"):
		check(false, "Hauptmenü verfügbar")
		return
	Game.profile["online_consent"] = true     # Internet: Datenschutz-Hinweis bereits bestätigt
	for internet in [false, true]:
		menu.open_lan(internet)
		await get_tree().process_frame
		var lm: LanMenu = menu.lan_menu
		var what: String = "Internet" if internet else "LAN"
		var last_other := -1      # letzte Nicht-Testkarte: Testkarten stehen dahinter
		for k in lm._map.item_count:
			if not bool(Game.MISSIONS.get(String(lm._map.get_item_metadata(k)), {}).get("test_map", false)):
				last_other = k
		var prev := last_other
		for i in IDS.size():
			var idx := -1
			for k in lm._map.item_count:
				if String(lm._map.get_item_metadata(k)) == IDS[i]:
					idx = k
			check(idx > prev, "%s-Menü: Testkarte %s am Ende der Liste (Position %d)" % [what, IDS[i], idx])
			prev = maxi(prev, idx)
			if idx < 0:
				continue
			lm._map.select(idx)
			lm._sync_mode()
			var m: int = MODES[i]
			check(lm._mode.selected == m and not lm._mode.is_item_disabled(m), "%s-Menü: Stil %s für %s" % [what, Net.MODE_NAMES[m], IDS[i]])
			check(lm._mode.is_item_disabled(Net.Mode.OBJECTIVES), "%s-Menü: HD2-Aufgaben für %s nicht angeboten (keine Aufgaben)" % [what, IDS[i]])
			var rot: Array = lm.map_rotation()
			check(not rot.is_empty() and rot[0] == IDS[i] and lm._style_maps().has(IDS[i]), "%s-Menü: Kartenrotation beginnt mit %s" % [what, IDS[i]])
			var cfg := lm.server_settings()
			check(String(cfg["map"]) == IDS[i] and int(cfg["mode"]) == m, "%s-Menü: Servereinstellungen %s" % [what, IDS[i]])
		lm.queue_free()
		menu.lan_menu = null
		await get_tree().process_frame


# --- 2. Dedizierter Server: Konfigurationszeilen / Kartennamen -----------------------------------------

func _dedicated_config() -> void:
	for i in IDS.size():
		Net._cfg_pending = {}
		var text := LanMenu.config_text({"name": "Ded", "map": IDS[i], "mode": MODES[i], "map_list": [IDS[i]], "port": Net.PORT + 45})
		for l in text.split("\n"):
			if l.strip_edges() in ["server", ""]:
				continue
			Net.server_command(l)
		check(String(Net._cfg_pending.get("map", "")) == IDS[i] and int(Net._cfg_pending.get("mode", -1)) == int(MODES[i]),
			"Dedizierte Konfig: mapname %s / style" % IDS[i], str(Net._cfg_pending.get("map", "")))
	Net._cfg_pending = {}
	check(Net.resolve_map("Bavaria", Net.Mode.DEATHMATCH) == "bavaria", "Kartenname „Bavaria“ im DM-Stil")
	check(Net.resolve_map("Bavaria", Net.Mode.OCCUPATION) == "bavaria_occupation", "Kartenname „Bavaria“ im Besetzungs-Stil")
	check(Net.resolve_map("Bavaria", Net.Mode.TEAM_DEATHMATCH) == "bavaria_tdm", "Kartenname „Bavaria“ im Team-DM-Stil")
	check(Net.resolve_map("BAVARIA_TDM") == "bavaria_tdm", "Karten-ID ohne Beachtung der Schreibweise")
	check(Net.resolve_map("bavaria_alt_occupation") == "bavaria_occupation" and Game.canonical_map_id("bavaria_alt") == "bavaria"
		and Game.canonical_map_id("bavaria_alt_tdm") == "bavaria_tdm" and Game.canonical_map_id("mp_arena_a1_blizzard") == "mp_arena_a1_blizzard",
		"Ältere Karten-IDs (Konfigurationen/Spielstände) werden auf die aktuellen abgebildet")
	var lm := Net.server_command("listmaps")
	check(lm.contains("bavaria ") and lm.contains("bavaria_occupation"), "listmaps nennt Bavaria (DM/Besetzung)")


# --- 3. Einzelspieler: freie Besichtigung --------------------------------------------------------------

func _free_view() -> void:
	var t0 := Time.get_ticks_msec()
	Game.start_mission("bavaria")
	var ok := await wait_for(func(): return Game.current_mission() != null and Game.current_mission_id == "bavaria" and Game.current_mission().get("squad") != null and Game.current_mission().is_node_ready(), 300.0)
	check(ok, "Freie Besichtigung startet (Einzelspieler)")
	if not ok:
		return
	var m = Game.current_mission()
	metrics.append("Laden freie Besichtigung (kopflos): %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var lead: Soldier = m.squad.leader()
	check(is_instance_valid(lead) and m.inside_map(lead.global_position), "Trupp steht innerhalb der Kartengrenze")
	check(OrigAudio.default_material == 50 and int(OrigAudio.material_info(50).get("step_sound", -1)) >= 0,
		"Untergrund: Schrittklang-Material %d" % OrigAudio.default_material, str(OrigAudio.material_info(50).get("name", "")))
	check(String(m.ambience_sound) != "", "Umgebungsklang gesetzt", String(m.ambience_sound))


# --- 4. Server: DM → TDM → Besetzung über die Kartenrotation ------------------------------------------

func _await_map(id: String, old) -> Variant:
	var ok := await wait_for(func(): return Game.current_mission() != null and Game.current_mission() != old and Game.current_mission_id == id and Net._soldiers.has(1), 400.0)
	if not ok:
		return null
	var m = Game.current_mission()
	await wait_for(func(): return m.nav_ready, 120.0)
	return m


func _styles_and_rotation() -> void:
	Net.local_name = "BavariaHost"
	Net.local_team = 0
	Net.local_class = 2
	var t0 := Time.get_ticks_msec()
	var old = Game.current_mission()
	var cfg := {"name": "Bavaria Integration", "map": IDS[0], "mode": MODES[0], "map_list": IDS.duplicate(),
		"port": Net.PORT + MP_PORT_OFS, "max_players": 12, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0,
		"respawn_s": 5, "bots_per_team": 2, "password": "", "allow_vehicles": false, "friendly_fire": false, "round_count": 1}
	check(Net.host(cfg), "Server Bavaria (Deathmatch) gestartet")
	for i in IDS.size():
		var m = await _await_map(IDS[i], old)
		check(m != null and Net.mode() == int(MODES[i]), "Rotation lädt %s im Stil %s" % [IDS[i], Net.MODE_NAMES[MODES[i]]])
		if m == null:
			return
		metrics.append("Laden %s als Server (kopflos, inkl. Navmesh): %.1f s" % [IDS[i], (Time.get_ticks_msec() - t0) / 1000.0])
		await _check_map_data(m, int(MODES[i]))
		if int(MODES[i]) == Net.Mode.DEATHMATCH:
			await _check_emplacements(m)
		if int(MODES[i]) == Net.Mode.OCCUPATION:
			await _check_bots_zones(m)
		old = m
		t0 = Time.get_ticks_msec()
		if i < IDS.size() - 1:
			Net.change_map()            # nächste Karte der Kartenliste (wie nextmap / Rundenende)
	Net.leave(false)
	await get_tree().create_timer(1.0).timeout


func _on_nav(nav_map: RID, p: Vector3) -> bool:
	var q := NavigationServer3D.map_get_closest_point(nav_map, p)
	return Vector2(q.x, q.z).distance_to(Vector2(p.x, p.z)) < 1.0 and absf(q.y - p.y) < 1.6


func _path_ok(nav_map: RID, a: Vector3, b: Vector3) -> bool:
	var pa := NavigationServer3D.map_get_closest_point(nav_map, a)
	var pb := NavigationServer3D.map_get_closest_point(nav_map, b)
	var path := NavigationServer3D.map_get_path(nav_map, pa, pb, true)
	return path.size() >= 2 and path[path.size() - 1].distance_to(pb) < 1.5


func _check_map_data(m, md: int) -> void:
	var sp: Array = m.mp_spawns()
	var t0 := sp.filter(func(p): return int(p["team"]) == 0).size()
	var t1 := sp.filter(func(p): return int(p["team"]) == 1).size()
	check(sp.size() == 16 and t0 == 8 and t1 == 8, "[%s] 16 Spawnpunkte, je Seite 8" % Net.MODE_NAMES[md], "%d/%d" % [t0, t1])
	var nav_map: RID = m.get_world_3d().navigation_map
	var bad: PackedStringArray = []
	for p in sp:
		if not m.inside_map(p["pos"]) or not _on_nav(nav_map, p["pos"]) or not _path_ok(nav_map, sp[0]["pos"], p["pos"]):
			bad.append(str(p["pos"]))
	check(bad.is_empty(), "[%s] Spawns in der Grenze, auf dem Navmesh, zusammenhängend" % Net.MODE_NAMES[md], ", ".join(bad))
	var zs: Array = m.mp_zones()
	check(zs.size() == 5, "[%s] 5 Zonen-Datensätze" % Net.MODE_NAMES[md])
	var zbad: PackedStringArray = []
	for z in zs:
		var c: Vector3 = (z["xf"] as Transform3D).origin
		if float(z["capture_time"]) != 15.0 or float(z["radius"]) < 3.5 or (z["slots"] as Array).size() != 4:
			zbad.append(String(z["name"]) + " Daten")
		if not _path_ok(nav_map, sp[0]["pos"], c):
			zbad.append(String(z["name"]) + " Pfad")
		for s in z["slots"]:
			if not _on_nav(nav_map, s["pos"]) or not Net.zone_contains(z, s["pos"]):
				zbad.append(String(z["name"]) + " Slot " + str(s["pos"]))
	check(zbad.is_empty(), "[%s] Zonen: 15 s Einnahme, Radius ≥ 3,5 m, 4 Startplätze in der Zone auf dem Navmesh, Pfad" % Net.MODE_NAMES[md],
		", ".join(zbad))
	check(not bool(m.get("frontline")), "[%s] Zonen frei angreifbar (frontline=false, keine Nachbarschaftsliste nötig)" % Net.MODE_NAMES[md])
	# Waffenfreigabe (Registerschlüssel mp_allowed_from, Game._register_test_maps) und Klassen (mp_presets)
	check(Net.map_allowed_known() and not Net.map_allowed_items(0).is_empty() and not Net.map_allowed_items(1).is_empty(),
		"[%s] Waffenfreigabe aktiv (wie NORMANDY2_MP_ZONE)" % Net.MODE_NAMES[md],
		"%d/%d" % [Net.map_allowed_items(0).size(), Net.map_allowed_items(1).size()])
	check(m.mp_presets(0).size() == 5 and m.mp_presets(1).size() == 5, "[%s] Klassenvorlagen je Seite 5" % Net.MODE_NAMES[md])
	await _check_launchers(m, md)
	var host: Soldier = Net._soldiers.get(1)
	check(is_instance_valid(host) and host.has_meta("mp_class") and host.weapons[0] != null, "[%s] Spielerklasse angewendet" % Net.MODE_NAMES[md],
		str(host.get_meta("mp_class", "-")) if is_instance_valid(host) else "-")
	var kit_bad: PackedStringArray = []
	var bots := 0
	for id in Net.players:
		if int(id) < 0:
			bots += 1
			var team := int(Net.players[id].get("team", 0))
			# Deathmatch: eigene Seite je Bot (Team ≥ 10), bot_kit wählt zufällig Alliierten- ODER Achsen-Ausrüstung
			var sides: Array = [team] if team in [0, 1] else [0, 1]
			var ok_side := false
			for t in sides:
				var all_ok := true
				for it in Net.players[id].get("kit", []):
					if int(it) >= 0 and not Net.is_item_allowed(int(t), int(it)):
						all_ok = false
				ok_side = ok_side or all_ok
			if not ok_side:
				kit_bad.append("%d:%s" % [int(id), str(Net.players[id].get("kit", []))])
	check(bots >= 2 and kit_bad.is_empty(), "[%s] %d Bots mit kartenerlaubter Ausrüstung" % [Net.MODE_NAMES[md], bots], ", ".join(kit_bad))
	var flag_visible := false
	if m.runtime != null and not zs.is_empty():
		var f = m.runtime.find_frame(String(zs[0]["flags"]["allied"]))
		flag_visible = f != null and f.visible
	check(flag_visible == (md == Net.Mode.OCCUPATION), "[%s] Zonenflaggen nur in Besetzung sichtbar" % Net.MODE_NAMES[md])


## Raketenwerfer (Registerschlüssel mp_extra_allowed): Freigabe je Seite, Grenadier-Klasse mit Werfer + Raketen,
## Server feuert auf Gebäude und Wrack → Explosion ohne Absturz.
func _check_launchers(m, md: int) -> void:
	var tag: String = Net.MODE_NAMES[md]
	check(Net.is_item_allowed(0, 39) and Net.is_item_allowed(1, 264) and not Net.is_item_allowed(1, 39),
		"[%s] Raketenwerfer freigegeben: Bazooka (Alliierte), Panzerschreck (Achse)" % tag)
	var st0: Dictionary = Net.map_storage(0)
	var st1: Dictionary = Net.map_storage(1)
	check(int(st0.get(206, 0)) > 0 and int(st1.get(205, 0)) > 0, "[%s] Raketen im Kartenlager (206/205)" % tag,
		"%d/%d" % [int(st0.get(206, 0)), int(st1.get(205, 0))])
	check(MpLoadout.map_allowed(IDS[MODES.find(md)]).any(func(e): return int(e.get("item_id", -1)) == 264),
		"[%s] SPIELER-SETUP-Lager enthält den Panzerschreck" % tag)
	var me: Soldier = Net._soldiers.get(1)
	if not is_instance_valid(me):
		check(false, "[%s] Host-Soldat für Werfertest" % tag)
		return
	me.set_meta("protect_until", Time.get_ticks_msec() + 30000)
	var kinds := {0: &"bazooka", 1: &"panzerschreck"}
	var old_team := me.team
	for t in [0, 1]:
		Net._apply_class(m, me, t, MpClasses.ANTITANK)
		var lw: Weapon = me.weapons[WeaponData.Slot.LAUNCHER]
		check(lw != null and lw.data.id == kinds[t] and lw.in_mag == 1 and lw.reserve >= 2,
			"[%s] Panzerabwehr-Klasse Seite %d: %s mit 1+≥2 Raketen" % [tag, t, String(kinds[t])],
			("%s %d+%d" % [lw.data.id, lw.in_mag, lw.reserve]) if lw else "kein Werfer")
	me.team = old_team
	var lw2: Weapon = me.weapons[WeaponData.Slot.LAUNCHER]
	if lw2 == null:
		return
	var targets: Array = []
	var house := m.static_root.get_node_or_null("haus_16") as Node3D
	if house:
		targets.append(["Gebäude haus_16", house.global_position + Vector3(0, 1.5, 0)])
	var wreck := m.find_child("PKW_Dorfrand", true, false) as Node3D
	if wreck:
		targets.append(["Wrack PKW_Dorfrand", wreck.global_position + Vector3(0, 0.8, 0)])
	check(targets.size() == 2, "[%s] Ziele Gebäude/Wrack gefunden" % tag)
	for tg in targets:
		var aim: Vector3 = tg[1]
		var to := aim - me.eye_position()
		me.global_position = aim - Vector3(to.x, 0, to.z).normalized() * 12.0 + Vector3(0, 0.2, 0)
		me.velocity = Vector3.ZERO
		await get_tree().physics_frame
		me.aim_point = aim
		me.has_aim_point = true
		var n0: int = Effects.explosion_count
		me._fire_shot(lw2)
		var boom := await wait_for(func(): return Effects.explosion_count > n0, 8.0)
		check(boom and is_instance_valid(m) and is_instance_valid(me), "[%s] Server-Raketenschuss auf %s explodiert ohne Absturz" % [tag, tg[0]])
	me.has_aim_point = false


func _check_emplacements(m) -> void:
	var me: Soldier = Net._soldiers.get(1)
	if not is_instance_valid(me):
		return
	me.set_meta("protect_until", Time.get_ticks_msec() + 60000)
	m.controller.set_physics_process(false)
	for e in [m.field_emplacement, m.woodland_emplacement]:
		var gun = e.gun
		me.global_position = gun.gunner_spot() + Vector3(1, 0, 0)
		me.velocity = Vector3.ZERO
		await get_tree().create_timer(0.2).timeout
		gun.interact(me)
		Net.used_interactable(gun)
		var on := await wait_for(func(): return me.mounted == gun, 5.0)
		gun.interact(me)
		Net.used_interactable(gun)
		var off := await wait_for(func(): return me.mounted == null and gun.gunner == null, 5.0)
		check(on and off, "Stationäre Waffe bedienbar und freigegeben (Server): " + String(gun.name))
	m.controller.set_physics_process(true)


func _check_bots_zones(m) -> void:
	# Bots laufen frei; Host-Figur ruht geschützt am Rand, damit sie keine Zone blockiert.
	var me: Soldier = Net._soldiers.get(1)
	if is_instance_valid(me):
		me.set_meta("protect_until", Time.get_ticks_msec() + 300000)
		me.process_mode = Node.PROCESS_MODE_DISABLED
	var zs: Array = m.mp_zones()
	var start := {}
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]):
			start[id] = Net._soldiers[id].global_position
	var moved := {}
	var entered := {}
	var owners0: Array = Net.zone_owner.duplicate()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000:
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			var s: Soldier = Net._soldiers[id]
			if int(id) >= 0 or not is_instance_valid(s) or not s.alive:
				continue
			if start.has(id) and s.global_position.distance_to(start[id]) > 5.0:
				moved[id] = true
			for i in zs.size():
				if i < Net.zone_owner.size() and int(Net.zone_owner[i]) != s.team and Net.zone_contains(zs[i], s.global_position):
					if not entered.has(id):
						entered[id] = "%s nach %.0f s" % [String(zs[i]["name"]), (Time.get_ticks_msec() - t0) / 1000.0]
		if entered.size() >= 2 and Net.zone_owner != owners0:
			break
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	check(moved.size() >= start.size() - 1 and not start.is_empty(), "Bots verlassen ihre Startplätze (Navmesh, Besetzung)",
		"%d/%d" % [moved.size(), start.size()])
	check(not entered.is_empty(), "Bots erreichen gegnerische/neutrale Zonen", str(entered.values()))
	metrics.append("Bots Besetzung: %d/%d bewegt, %d in fremden Zonen, Besitz %s → %s nach %.0f s" % [moved.size(), start.size(),
		entered.size(), str(owners0), str(Net.zone_owner), dt])
	if is_instance_valid(me):
		me.process_mode = Node.PROCESS_MODE_INHERIT


# --- 5. Zwei echte Prozesse: Beitritt, Spawn, Bewegung, Treffer, Zone -------------------------------------

func _two_process() -> void:
	Net.local_name = "BavariaHost"
	Net.local_team = 0
	Net.local_class = 2
	var old = Game.current_mission()
	Net.move_check = false        # B-022: Testclient versetzt seine Figur direkt in Zone C – kein Spielzug
	check(Net.host({"name": "Bavaria MP", "map": "bavaria_occupation", "mode": Net.Mode.OCCUPATION,
		"port": Net.PORT + MP_PORT_OFS, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0,
		"respawn_s": 5, "bots_per_team": 1, "password": "", "allow_vehicles": false, "friendly_fire": false,
		"flood_protect": false, "team_balance": false}), "MP: Server (Besetzung) gestartet")
	var m = await _await_map("bavaria_occupation", old)
	if m == null:
		check(false, "MP: Karte auf dem Server geladen")
		return
	var sp: Array = m.mp_spawns()
	for id in Net._soldiers:
		if int(id) < 0:
			var b: Soldier = Net._soldiers[id]
			b.process_mode = Node.PROCESS_MODE_DISABLED
			b.set_meta("protect_until", Time.get_ticks_msec() + 300000)
	var args := ["--headless", "--log-file",
		ProjectSettings.globalize_path("res://test_output/test_bavaria_integration_client.log"), "--",
		"--autoplay=test_bavaria_integration", "--bi_peer=1"]
	if OS.has_feature("editor"):              # Exportvorlagen verbieten --path (eingebettetes Projekt)
		args.insert(1, "--path")
		args.insert(2, ProjectSettings.globalize_path("res://"))
	child_pid = OS.create_process(OS.get_executable_path(), args)
	check(child_pid > 0, "MP: zweiter Spielprozess gestartet")
	var guest := -1
	var joined := await wait_for(func(): return _guest_id() != 0, 240.0)
	check(joined, "MP: Client beigetreten")
	if not joined:
		return
	guest = _guest_id()
	var spawned := await wait_for(func(): return _chat_prefix("BI_SPAWNED") != "", 240.0)
	var gs: Soldier = Net._soldiers.get(guest)
	check(spawned and is_instance_valid(gs) and gs.alive and m.inside_map(gs.global_position), "MP: Client-Figur auf dem Server gespawnt")
	# Bewegung
	var moved := await wait_for(func(): return _chat_prefix("BI_MOVED ") != "", 60.0)
	if moved:
		var parts := _chat_prefix("BI_MOVED ").split(" ")
		var rep := Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
		gs = Net._soldiers.get(guest)
		var ok := await wait_for(func(): return is_instance_valid(gs) and gs.global_position.distance_to(rep) < 1.0, 5.0)
		check(ok, "MP: Client-Bewegung auf dem Server synchron", str(gs.global_position.distance_to(rep)) if is_instance_valid(gs) else "-")
	else:
		check(false, "MP: Client meldet Bewegung")
	# Treffer: Host-Figur vor den Client stellen, Client schießt, Server bestätigt Schaden
	var me: Soldier = Net._soldiers.get(1)
	m.controller.set_physics_process(false)
	gs = Net._soldiers.get(guest)
	if is_instance_valid(me) and is_instance_valid(gs):
		check(int(Net.players.get(guest, {}).get("team", -1)) != me.team, "MP: Client und Host in verschiedenen Teams")
		me.global_position = _clear_spot(m, gs, me)
		me.velocity = Vector3.ZERO
		# Nicht PROCESS_MODE_DISABLED: das entfernt die Trefferzonen (Area3D) aus der Physik. Steuerung ruht (controller aus).
		me.set_meta("protect_until", 0)
		var h0 := me.health
		await get_tree().create_timer(0.6).timeout
		Net.send_chat("BI_TARGET_READY")
		var hit := await wait_for(func(): return not is_instance_valid(me) or me.health < h0 or not me.alive, 40.0)
		check(hit, "MP: Treffer des Clients vom Server bestätigt", "LP %.0f → %.0f" % [h0, me.health if is_instance_valid(me) else -1.0])
		Net.send_chat("BI_HIT_OK" if hit else "BI_HIT_MISSED")
		if is_instance_valid(me) and me.alive:
			me.global_position = sp[0]["pos"]
	m.controller.set_physics_process(true)
	# Zone: Client nimmt die neutrale Wiese (C) ein
	var team := int(Net.players.get(guest, {}).get("team", 1))
	var in_zone := await wait_for(func(): return _chat_has("BI_IN_ZONE"), 90.0)
	var captured := in_zone and await wait_for(func(): return Net.zone_owner.size() == 5 and int(Net.zone_owner[2]) == team, 40.0)
	check(captured, "MP: Client nimmt Zone C auf dem Server ein", str(Net.zone_owner))
	Net.send_chat("BI_ZONE_OK" if captured else "BI_ZONE_FAIL")
	var done := await wait_for(func(): return _chat_prefix("BI_CLIENT_DONE") != "", 90.0)
	var res := _chat_prefix("BI_CLIENT_DONE")
	check(done and res.contains(" OK"), "MP: Client-Prüfungen bestanden", res)
	Net.leave(false)
	if child_pid > 0:
		await wait_for(func(): return not OS.is_process_running(child_pid), 10.0)


## Freier Platz 6–8 m vom Client mit freier Sichtlinie (Brust zu Brust) auf dem Navmesh
func _clear_spot(m, gs: Soldier, me: Soldier) -> Vector3:
	var nav_map: RID = m.get_world_3d().navigation_map
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var eye := gs.global_position + Vector3.UP * 1.5
	for dist in [7.0, 6.0, 8.0, 5.0]:
		for k in 16:
			var a: float = TAU * float(k) / 16.0
			var cand := NavigationServer3D.map_get_closest_point(nav_map, gs.global_position + Vector3(cos(a), 0, sin(a)) * dist)
			if cand.distance_to(gs.global_position) < 4.5 or not m.inside_map(cand):
				continue
			var q := PhysicsRayQueryParameters3D.create(eye, cand + Vector3.UP * 1.3)
			q.exclude = [gs.get_rid(), me.get_rid()]
			if space.intersect_ray(q).is_empty():
				return cand + Vector3.UP * 0.1
	return gs.global_position + gs.forward() * 7.0

func _guest_id() -> int:
	for id in Net.players:
		if String(Net.players[id].get("name", "")) == "BavariaGuest":
			return int(id)
	return 0


func _client() -> void:
	Net.local_name = "BavariaGuest"
	Net.local_team = 1
	Net.local_class = 2
	Net.join("127.0.0.1", Net.PORT + MP_PORT_OFS, "")
	var ready := await wait_for(func(): return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1), 240.0)
	check(ready, "Client: Karte geladen, eigene Figur und Host vorhanden")
	if not ready:
		return
	var m = Game.current_mission()
	check(Game.current_mission_id == "bavaria_occupation" and Net.mode() == Net.Mode.OCCUPATION, "Client: richtige Karte und Spielstil")
	await wait_for(func(): return m.nav_ready and m.actors_root.process_mode != Node.PROCESS_MODE_DISABLED, 120.0)
	var me: Soldier = Net._soldiers[Net.my_id()]
	check(me.alive and m.inside_map(me.global_position), "Client: Spawn innerhalb der Karte")
	var own_zone := false
	for z in m.mp_zones():
		for s in z["slots"]:
			if (s["pos"] as Vector3).distance_to(me.global_position) < 2.5:
				own_zone = true
	check(own_zone, "Client: Spawn an einem Startplatz einer eigenen Zone")
	Net.send_chat("BI_SPAWNED")
	var start := me.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.8).timeout
	check(me.global_position.distance_to(start) > 1.0, "Client: Bewegung", str(me.global_position.distance_to(start)))
	var p := me.global_position
	Net.send_chat("BI_MOVED %.3f %.3f %.3f" % [p.x, p.y, p.z])
	# Treffer
	await wait_for(func(): return _chat_has("BI_TARGET_READY"), 60.0)
	m.controller.set_physics_process(false)
	var host: Soldier = Net._soldiers.get(1)
	for attempt in 6:
		if _chat_prefix("BI_HIT_") != "" or not is_instance_valid(host):
			break
		var target := host.global_position + Vector3.UP * 1.25
		var eye := me.global_position + Vector3.UP * 1.6
		var d := (target - eye).normalized()
		me.look_yaw = atan2(-d.x, -d.z)
		me.look_pitch = asin(d.y)
		me.aim_point = target
		me.has_aim_point = true
		me.aiming = true
		await get_tree().create_timer(0.5).timeout
		var w := me.current_weapon()
		var ammo0: int = w.in_mag if w else -1
		me.trigger = true
		await get_tree().create_timer(0.3).timeout
		me.trigger = false
		print("CLIENT Schuss %d: Ziel %s Abstand %.1f m Magazin %d → %d" % [attempt, str(target.snapped(Vector3.ONE * 0.1)),
			eye.distance_to(target), ammo0, w.in_mag if w else -1])
		await get_tree().create_timer(1.6).timeout
	me.has_aim_point = false
	me.aiming = false
	await wait_for(func(): return _chat_prefix("BI_HIT_") != "", 30.0)
	check(_chat_has("BI_HIT_OK"), "Client: Server bestätigt eigenen Treffer")
	# Zone C (Wiese) einnehmen
	var zs: Array = m.mp_zones()
	var c: Vector3 = (zs[2]["xf"] as Transform3D).origin
	me.global_position = c + Vector3(0.5, 0.2, 0.5)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	Net.send_chat("BI_IN_ZONE")
	var t: int = me.team
	var mine := await wait_for(func(): return Net.zone_owner.size() == 5 and int(Net.zone_owner[2]) == t, 45.0)
	check(mine, "Client: Besitzwechsel der Zone C empfangen", str(Net.zone_owner))
	var side: String = "allied" if t == Soldier.TEAM_ALLIED else "axis"
	var flag = m.runtime.find_frame(String(zs[2]["flags"][side]))
	check(flag != null and flag.visible, "Client: Flagge des neuen Besitzers sichtbar")
	await wait_for(func(): return _chat_prefix("BI_ZONE_") != "", 30.0)
	check(_chat_has("BI_ZONE_OK"), "Client: Server bestätigt Einnahme")
	m.controller.set_physics_process(true)
	Net.send_chat("BI_CLIENT_DONE %s %d/%d" % ["OK" if failed == 0 else "FAIL", passed, passed + failed])
	await wait_for(func(): return not Net.is_online, 60.0)


func _finish() -> void:
	if Net.is_online:
		Net.leave(false)
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	for l in metrics:
		print("METRIK ", l)
	print("\nERGEBNIS: Bavaria-Integration %s: %d bestanden, %d fehlgeschlagen" % ["Client" if peer_mode else "Host", passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
