extends Node
## Zwei echte ENet-Prozesse prüfen Auswahl, Kartenladen, Bots und Positionsabgleich.
## tools/godot.cmd --headless -- --autoplay=test_bavaria_mp
var failed := 0
var passed := 0
var child_pid := -1
var peer_mode := false
var map_id := "bavaria"
var game_mode := Net.Mode.DEATHMATCH

class FlakTarget extends StaticBody3D:
	var hit := false
	func on_bullet_hit(_damage: float,_shooter: Node) -> void:
		hit = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("bavaria_peer")
	if Game.cli.has("occupation"):
		map_id = "bavaria_occupation"
		game_mode = Net.Mode.OCCUPATION
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func():
		check(false, "MP-Zeitüberschreitung")
		_finish())
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func wait_for(condition: Callable, seconds := 90.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()

func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		Net.local_name = "BavariaGuest"
		Net.local_team = 1
		Net.join("127.0.0.1", Net.PORT + 42, "")
		var ready := await wait_for(func():
			return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1))
		check(ready, "Client hat Bavaria und beide Spieler geladen")
		if ready:
			check(Game.current_mission_id == map_id and Net.mode() == game_mode, "Client erhält richtige Karte und Spielmodus")
			var m: Mission = Game.current_mission()
			var me: Soldier = Net._soldiers[Net.my_id()]
			check(await wait_for(func(): return m.nav_ready and m.actors_root.process_mode != Node.PROCESS_MODE_DISABLED),
				"Client-Navigation bereit und Bewegung freigegeben")
			check(m.inside_map(me.global_position) and me.alive, "Client lebt innerhalb der Grenze")
			check(m.asset_report.missing.is_empty(), "Client ohne fehlende Kartenassets")
			check(await wait_for(func(): return m.prank_mines.initialized and m.prank_mines.spent[0]),
				"Später Client erhält verbrauchte Mine ohne erneute Auslösung")
			check(m.prank_mines.effect_count==0,"Beitritt spielt alten Minenrauch/-ton nicht erneut")
			# Tageszyklus: Host hat vor dem Beitritt auf 2:30 Uhr gestellt (Zyklus 240 min); Client übernimmt Serverzeit.
			check(await wait_for(func(): return m.day_night.synced, 20.0),"Client erhält die Tageszeit vom Server (später Beitritt)")
			check(is_equal_approx(m.day_night.cycle_min,240.0),"Client übernimmt die Zyklusdauer des Servers")
			check(m.day_night.hour>2.3 and m.day_night.hour<3.8,"Client-Uhrzeit = Serverzeit (Nacht), nicht eigene Startzeit: %.2f"%m.day_night.hour)
			check(await wait_for(func(): return m.room_lighting.initialized and m.room_lighting.lights_on()==m.room_lighting.coverage.size(),20.0)
				and m.street_lamps.lights_on()==m.street_lamps.lights.size(),"Client: nachts alle Raumlichter und Laternen an")
			var start := me.global_position
			Input.action_press("move_forward")
			await get_tree().create_timer(1.2).timeout
			Input.action_release("move_forward")
			check(me.global_position.distance_to(start) > 0.8, "Client kann sich auf der Karte bewegen")
			await _client_climbs(m,me)
			await _client_flak(m,me)
			await _client_mg42(m,me)
			var mine: Node3D = m.prank_mines.mines[9]
			var health := me.health
			var effect_count: int = m.prank_mines.effect_count
			me.global_position = mine.global_position
			me.velocity = Vector3.ZERO
			check(await wait_for(func(): return m.prank_mines.spent[9]),"Client betritt Rauchmine; Host bestätigt Auslösung")
			check(m.prank_mines.effect_count==effect_count+1,"Client empfängt genau einen Rauch-/Toneffekt")
			check(me.alive and me.health==health,"Client bleibt nach Mine unverletzt")
			Net.send_chat("BAVARIA_MINE_OK")
			if game_mode == Net.Mode.OCCUPATION:
				check(await wait_for(func(): return Net.zone_owner.size() == 5), "Client erhält fünf synchronisierte Zonen")
				# Nach der Bewegungsprüfung den Verteidiger für die kontrollierte Einnahme aus der Zielzone nehmen.
				me.global_position = m.mp_spawns()[3].pos
				me.velocity = Vector3.ZERO
				await get_tree().create_timer(0.5).timeout
			Net.send_chat("BAVARIA_CLIENT_OK" if failed == 0 else "BAVARIA_CLIENT_FAIL")
			if game_mode == Net.Mode.OCCUPATION:
				check(await wait_for(func(): return Net.zone_owner.size() == 5 and Net.zone_owner[4] == 0, 45.0),
					"Client erhält den tatsächlichen Besitzerwechsel")
				check(m.runtime.find_frame(m.mp_zones()[4].flags.allied).visible,
					"Client zeigt die Flagge des neuen Besitzers")
			await wait_for(func(): return not Net.is_online, 90.0)
		_finish()
		return
	# Kartenliste und Spielmodi über das vorhandene Menü prüfen.
	var menu := get_tree().current_scene
	menu.open_lan()
	await get_tree().process_frame
	var lm: LanMenu = menu.lan_menu
	var found := -1
	for i in lm._map.item_count:
		if lm._map.get_item_metadata(i) == map_id:
			found = i
	check(found >= 0, "Bavaria im LAN-Menü auswählbar")
	if found >= 0:
		lm._map.select(found)
		lm._sync_mode()
		check(lm._mode.selected == game_mode and not lm._mode.is_item_disabled(game_mode), "Passender Deathmatch-/Eroberungsmodus auswählbar")
		check(lm._mode.is_item_disabled(1) and lm._mode.is_item_disabled(3), "Team-Deathmatch und Aufgaben nicht angeboten")
		check(lm._style_maps().has(map_id), "Karte in passender Modus-Rotation")
	# Testprotokoll benutzt viele Chat-ACKs; normale Flood-Regel dafür nur in diesem Test deaktivieren.
	Net.local_name = "BavariaHost"
	Net.local_team = 0
	Net.move_check = false   # B-022: Testclient versetzt seine Figur direkt an Flak/MG42/Leitern – kein Spielzug
	check(Net.host({"name":"Bavaria Test", "map":map_id, "mode":game_mode,
		"port":Net.PORT+42, "max_players":8, "time_limit_min":0, "score_limit":0, "warmup_s":0, "respawn_s":5,
		"bots_per_team":1, "password":"", "allow_vehicles":false, "flood_protect":false,
		"day_start_h":22, "day_cycle_min":240}), "Server mit angefordertem Spielmodus gestartet")
	var ready := await wait_for(func(): return Game.current_mission() != null and Net._soldiers.has(1) and Net._soldiers.size() >= 3)
	check(ready, "Host und zwei vorhandene MP-Bots erzeugt")
	if not ready:
		_finish()
		return
	var m: Mission = Game.current_mission()
	check(await wait_for(func(): return m.nav_ready and m.actors_root.process_mode != Node.PROCESS_MODE_DISABLED),
		"Host-Navigation bereit und Bots freigegeben")
	check(m.enemies.is_empty(), "Keine versehentlichen Kampagnengegner")
	# Die folgenden Kletter-/Bedienerprüfungen benötigen feste Figuren. Die bereits
	# erfolgreich erzeugten MP-Bots dürfen den Testclient dabei nicht zufällig töten.
	for id in Net._soldiers:
		if int(id)<0:
			Net._soldiers[id].process_mode = Node.PROCESS_MODE_DISABLED
	check(await wait_for(func(): return m.prank_mines.initialized),"Zehn Minen auf Host bereit")
	m.prank_mines.trigger(0) # Vor Clientbeitritt: Zustand muss ohne Effektwiederholung nachkommen.
	check(is_equal_approx(m.day_night.start_hour,22.0) and is_equal_approx(m.day_night.cycle_min,240.0),
		"Host übernimmt Startzeit/Zyklus aus den Server-Einstellungen")
	m.day_night.set_hour(2.5)   # vor dem Beitritt verstellt: Client muss diese Zeit bekommen, nicht 22 Uhr
	# Exportvorlagen verbieten --path; sie laden das eingebettete Projekt selbst.
	var args := ["--headless", "--log-file",
		ProjectSettings.globalize_path("res://test_output/bavaria_mp_client.log"), "--", "--autoplay=test_bavaria_mp", "--bavaria_peer=1"]
	if OS.has_feature("editor"):
		args.insert(1, "--path")
		args.insert(2, ProjectSettings.globalize_path("res://"))
	if game_mode == Net.Mode.OCCUPATION:
		args.append("--occupation=1")
	child_pid = OS.create_process(OS.get_executable_path(), args)
	check(child_pid > 0, "Zweiter Spielprozess gestartet")
	var joined := await wait_for(func(): return Net.players.values().any(func(p): return String(p.get("name", "")) == "BavariaGuest"))
	check(joined, "Client beigetreten")
	if joined:
		for soldier in Net._soldiers.values():
			soldier.set_meta("protect_until",Time.get_ticks_msec()+150000)
		await _host_climbs(m)
		await _host_flak(m)
		await _host_mg42(m)
		check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MINE_OK")),
			"Entfernter Client hat Minenprüfung beendet")
		check(m.prank_mines.spent[9],"Host registriert durch entfernten Client ausgelöste Mine")
	var ack := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text", "")).begins_with("BAVARIA_CLIENT_")))
	check(ack and Net.chat_log.any(func(e): return String(e.get("text", "")) == "BAVARIA_CLIENT_OK"), "Client bestätigt Karte, Assets, Spawn und Bewegung")
	for s in Net._soldiers.values():
		check(is_instance_valid(s) and m.inside_map(s.global_position) and s.global_position.y > -0.5,
			"Netzfigur innerhalb der Karte über Boden")
	if game_mode == Net.Mode.OCCUPATION:
		await _test_occupation(m)
	Net.leave(false)
	if child_pid > 0:
		await wait_for(func(): return not OS.is_process_running(child_pid), 8.0)
	_finish()

func _client_climbs(m: Mission, me: Soldier) -> void:
	for up in get_tree().get_nodes_in_group("bavaria_scene_ladders"):
		if up.at_top:
			continue
		me.global_position = up.bottom
		me.velocity = Vector3.ZERO
		await get_tree().create_timer(0.2).timeout
		up.interact(me)
		check(me.is_climbing(),"Client klettert tatsächlich: "+up.name)
		check(await wait_for(func(): return not me.is_climbing(),18.0) and me.global_position.distance_to(up.top)<0.5,
			"Client erreicht oberen Stand: "+up.name)
		Net.send_chat("BAVARIA_CLIMB_"+up.name)
		check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_HEIGHT_OK_"+up.name),10.0),
			"Host bestätigt replizierte Standhöhe: "+up.name)
		for down in get_tree().get_nodes_in_group("bavaria_scene_ladders"):
			if down.at_top and down.top.is_equal_approx(up.top):
				down.interact(me)
		check(await wait_for(func(): return not me.is_climbing(),18.0) and me.global_position.distance_to(up.bottom)<0.5,
			"Client steigt wieder zum Boden: "+up.name)

func _host_climbs(m: Mission) -> void:
	var guest_id := -1
	for id in Net.players:
		if Net.players[id].get("name","")=="BavariaGuest":
			guest_id = int(id)
	for up in get_tree().get_nodes_in_group("bavaria_scene_ladders"):
		if up.at_top:
			continue
		var got := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_CLIMB_"+up.name),40.0)
		var synced := got and await wait_for(func(): return Net._soldiers.has(guest_id) and Net._soldiers[guest_id].global_position.distance_to(up.top)<1.0,5.0)
		check(synced,"Entfernter Client auf Dach/Baum richtig synchronisiert: "+up.name)
		Net.send_chat("BAVARIA_HEIGHT_OK_"+up.name)

func _flak_target(m: Mission) -> Vector3:
	var frame: Node3D = m.field_emplacement.frame
	# Der bodennahe alte Zielpunkt liegt hinter einem absichtlich kollidierenden Wrack
	# (telo_col bei etwa -10/-29). Erhöhtes Flakziel: echter Treffer mit freier Flugbahn.
	return frame.global_position-frame.global_basis.z*18+Vector3.UP*4.5

func _client_flak(m: Mission,me: Soldier) -> void:
	var gun: OrigInteractive.OrigEmplacement = m.field_emplacement.gun
	m.controller.set_physics_process(false)
	me.global_position = gun.gunner_spot()+Vector3(1,0,0)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(0.2).timeout
	gun.interact(me)
	Net.used_interactable(gun)
	check(await wait_for(func(): return me.mounted==gun,5.0),"Client kann vorhandene Wiesenflak besetzen")
	Net.send_chat("BAVARIA_FLAK_MOUNTED")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_FLAK_READY"),15.0),"Host bestätigt replizierte Flakbesetzung")
	await get_tree().create_timer(0.7).timeout
	var direction := (_flak_target(m)-gun.shot_origin()).normalized()
	me.look_yaw = atan2(-direction.x,-direction.z)
	me.look_pitch = asin(direction.y)
	me.aim_point = _flak_target(m)
	me.has_aim_point = true
	me.aiming = true
	await get_tree().create_timer(0.2).timeout
	var ammo: int = me.current_weapon().in_mag
	me.trigger = true
	await get_tree().create_timer(0.6).timeout
	me.trigger = false
	check(me.current_weapon().in_mag<ammo,"Client verschießt echte Flakmunition")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_FLAK_HIT"),10.0),"Server bestätigt tatsächlichen Flaktreffer des Clients")
	me.has_aim_point = false
	gun.interact(me)
	Net.used_interactable(gun)
	check(await wait_for(func(): return me.mounted==null,5.0),"Client verlässt Flak mit persönlicher Ausrüstung")
	Net.send_chat("BAVARIA_FLAK_LEFT")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_FLAK_RELEASED"),10.0),"Host bestätigt freigegebene Flak")
	m.controller.set_physics_process(true)

func _host_flak(m: Mission) -> void:
	var gun: OrigInteractive.OrigEmplacement = m.field_emplacement.gun
	var target := FlakTarget.new()
	m.dynamic_root.add_child(target)
	target.global_position = _flak_target(m)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*2.5
	shape.shape = box
	target.add_child(shape)
	var received := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_FLAK_MOUNTED"),20.0)
	var synced := received and await wait_for(func(): return is_instance_valid(gun.gunner) and gun.gunner.get_meta("net_peer",1)!=1,5.0)
	check(synced,"Server sieht entfernten Client an der Flak")
	Net.send_chat("BAVARIA_FLAK_READY")
	check(await wait_for(func(): return target.hit,15.0),"Serverballistik erhält echten Flakschuss des Clients")
	if not target.hit:
		var exclusions: Array[RID] = gun.shot_exclusions()
		exclusions.append(target.get_rid())
		if is_instance_valid(gun.gunner):
			exclusions.append_array(gun.gunner.exclude_rids())
		var trace := m.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(gun.shot_origin(),target.global_position,Ballistics.MASK,exclusions))
		print("FLAK_TEST_DIAG origin=",gun.shot_origin()," target=",target.global_position," blocker=",trace)
	Net.send_chat("BAVARIA_FLAK_HIT" if target.hit else "BAVARIA_FLAK_MISSED")
	await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_FLAK_LEFT"),15.0)
	check(await wait_for(func(): return gun.gunner==null,5.0),"Server gibt Flak nach Clientausstieg frei")
	Net.send_chat("BAVARIA_FLAK_RELEASED")
	target.queue_free()

func _mg42_target(m: Mission) -> Vector3:
	var frame: Node3D = m.woodland_emplacement.frame
	return frame.global_position-frame.global_basis.z*18+Vector3.UP*1.8

func _client_mg42(m: Mission,me: Soldier) -> void:
	var gun: OrigInteractive.OrigEmplacement = m.woodland_emplacement.gun
	m.controller.set_physics_process(false)
	me.global_position = gun.gunner_spot()+Vector3(1,0,0)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(0.2).timeout
	gun.interact(me)
	Net.used_interactable(gun)
	check(await wait_for(func(): return me.mounted==gun,5.0),"Client kann vorhandene Holzhaus-MG42 besetzen")
	Net.send_chat("BAVARIA_MG42_MOUNTED")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MG42_READY"),15.0),"Host bestätigt replizierte MG42besetzung")
	await get_tree().create_timer(0.7).timeout
	var direction := (_mg42_target(m)-gun.shot_origin()).normalized()
	me.look_yaw = atan2(-direction.x,-direction.z)
	me.look_pitch = asin(direction.y)
	me.aim_point = _mg42_target(m)
	me.has_aim_point = true
	me.aiming = true
	await get_tree().create_timer(0.2).timeout
	var ammo: int = me.current_weapon().in_mag
	me.trigger = true
	await get_tree().create_timer(0.6).timeout
	me.trigger = false
	check(me.current_weapon().in_mag<ammo,"Client verschießt echte MG42munition")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MG42_HIT"),10.0),"Server bestätigt tatsächlichen MG42treffer des Clients")
	me.has_aim_point = false
	gun.interact(me)
	Net.used_interactable(gun)
	check(await wait_for(func(): return me.mounted==null,5.0),"Client verlässt MG42 mit persönlicher Ausrüstung")
	Net.send_chat("BAVARIA_MG42_LEFT")
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MG42_RELEASED"),10.0),"Host bestätigt freigegebene MG42")
	m.controller.set_physics_process(true)

func _host_mg42(m: Mission) -> void:
	var gun: OrigInteractive.OrigEmplacement = m.woodland_emplacement.gun
	var target := FlakTarget.new()
	m.dynamic_root.add_child(target)
	target.global_position = _mg42_target(m)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*2.5
	shape.shape = box
	target.add_child(shape)
	var received := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MG42_MOUNTED"),20.0)
	var synced := received and await wait_for(func(): return is_instance_valid(gun.gunner) and gun.gunner.get_meta("net_peer",1)!=1,5.0)
	check(synced,"Server sieht entfernten Client an der MG42")
	Net.send_chat("BAVARIA_MG42_READY")
	# Netzfigur des Clients in der Original-Bedienhaltung (gemeinsame Basis OrigEmplacement, re_notes_weapons §11)
	if synced:
		await get_tree().create_timer(0.6).timeout
		var ik = gun.pose_ik
		var er: Array = [float(ik.get("err_r")), float(ik.get("err_l"))] if ik else [-1.0, -1.0]
		check(is_instance_valid(gun.gunner) and String(gun.gunner.model.full_clip()).begins_with("emp_") and er[0] >= 0.0 and er[0] < 0.06 and er[1] >= 0.0 and er[1] < 0.06,
			"Netzfigur des Clients an der MG42 in Bedienhaltung, Hände an den Griffen (%.3f/%.3f m)" % er)
	check(await wait_for(func(): return target.hit,15.0),"Serverballistik erhält echten MG42schuss des Clients")
	Net.send_chat("BAVARIA_MG42_HIT" if target.hit else "BAVARIA_MG42_MISSED")
	await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text",""))=="BAVARIA_MG42_LEFT"),15.0)
	check(await wait_for(func(): return gun.gunner==null,5.0),"Server gibt MG42 nach Clientausstieg frei")
	Net.send_chat("BAVARIA_MG42_RELEASED")
	target.queue_free()

func _test_occupation(m: Mission) -> void:
	var zs: Array = m.mp_zones()
	check(zs.size() == 5 and Net.zone_owner.has(0) and Net.zone_owner.has(1), "Fünf Zonen mit je einer Teambasis und neutralen Zielen")
	var host: Soldier = Net._soldiers[1]
	var team := host.team
	# Für die Regelprüfung alle anderen Figuren am Rand halten und KI pausieren.
	for id in Net._soldiers:
		if id != 1:
			var s: Soldier = Net._soldiers[id]
			s.process_mode = Node.PROCESS_MODE_DISABLED
			s.global_position = m.mp_spawns()[3].pos
	var target := 4 if team == 0 else 0
	var center: Vector3 = (zs[target].xf as Transform3D).origin
	var score_before := int(Net.players[1]["score"])
	var team_before := float(Net.team_score[team])
	host.process_mode = Node.PROCESS_MODE_DISABLED
	host.global_position = center
	check(await wait_for(func(): return Net.zone_owner[target] == -1, 25.0), "Gegnerzone wird nach halber Einnahmezeit neutral")
	check(int(Net.players[1]["score"]) == score_before + Net.ZONE_NEUTRALIZE_PTS, "Neutralisieren nutzt vorhandene Punktewertung")
	check(await wait_for(func(): return Net.zone_owner[target] == team, 20.0), "Neutralisierte Zone wird eingenommen")
	check(int(Net.players[1]["score"]) == score_before + Net.ZONE_NEUTRALIZE_PTS + Net.ZONE_CAPTURE_PTS, "Einnahme nutzt vorhandene Punktewertung")
	check(float(Net.team_score[team]) > team_before, "Gehaltene Zonen erhöhen Teamwertung")
	var side := "allied" if team == 0 else "axis"
	check(m.runtime.find_frame(zs[target].flags[side]).visible and not m.runtime.find_frame(zs[target].flags.neutral).visible,
		"Vorhandener Net-Flaggenabgleich zeigt Besitzerwechsel")
	Net.request_zone(target)
	check(int(Net.players[1].get("zone", -1)) == target, "Eingenommene eigene Zone als Wiedereinstiegsort auswählbar")
	host.set_meta("protect_until", 0)
	host.apply_hit(1000, &"torso", null, Vector3.FORWARD)
	check(await wait_for(func():
		var s: Soldier = Net._soldiers.get(1)
		return is_instance_valid(s) and s != host and s.alive, 15.0), "Vorhandene Eroberungs-Respawn-Welle erzeugt neuen Soldaten")
	var respawned: Soldier = Net._soldiers[1]
	check((zs[target].slots as Array).any(func(slot): return (slot.pos as Vector3).distance_to(respawned.global_position) < 2.0),
		"Wiedereinstieg an gewählter eigener Eroberungszone")

func _finish() -> void:
	if Net.is_online:
		Net.leave(false)
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	print("ERGEBNIS: Bavaria MP %s: %d bestanden, %d fehlgeschlagen" % ["Client" if peer_mode else "Host", passed, failed])
	get_tree().quit(1 if failed else 0)
