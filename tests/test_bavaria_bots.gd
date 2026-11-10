extends Node
## Lokale KI-Messung auf der Eroberungsvariante der Testkarte: N KI-Soldaten je Seite, Host geparkt.
## tools/godot.cmd --headless -- --autoplay=test_bavaria_bots [--bots=4] [--dur=240] [--hints=0|1] [--tag=x] [--dm=1]
## Messwerte → test_output/bavaria_bots<tag>.txt: Festhängen, Deckungs-/Stellungsnutzung, Zonenwechsel,
## Zeit bis Feindkontakt, Wandabstand, Zeit in Graben/Keller.
const STUCK_LIMIT := 20.0

var failed := 0
var passed := 0
var lines: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(3000.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung")
		_finish())
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("PASS " if ok else "FAIL ") + label)


func now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func game_wait(sec: float) -> void:
	var t := now() + sec
	while now() < t:
		await get_tree().physics_frame


func _run() -> void:
	await get_tree().process_frame
	var bots := int(Game.cli.get("bots", "4"))
	var dur := float(Game.cli.get("dur", "240"))
	BotGoals.use_map_hints = String(Game.cli.get("hints", "1")) != "0"
	var dm := String(Game.cli.get("dm", "0")) == "1"
	var map := "bavaria" if dm else "bavaria_occupation"
	var mode := Net.Mode.DEATHMATCH if dm else Net.Mode.OCCUPATION
	Net.local_name = "Host"
	var ok := Net.host({"name": "BavBots", "map": map, "mode": mode, "max_players": 16, "time_limit_min": 0, "score_limit": 0,
		"respawn_s": 5, "password": "", "port": Net.PORT + 23, "friendly_fire": false, "bots_per_team": bots, "warmup_s": 0})
	check(ok, "Server gestartet")
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while ok and Time.get_ticks_msec() - t0 < 600000:
		await get_tree().create_timer(0.5).timeout
		var mm := Game.current_mission()
		if mm and Net._soldiers.has(1) and _bots().size() >= (bots if dm else bots * 2) and mm.get("nav_ready") == true \
				and mm.actors_root.process_mode != Node.PROCESS_MODE_DISABLED:
			m = mm
			break
	check(m != null, "Karte geladen, Netz bereit, Bots da")
	if m == null:
		_finish()
		return
	var host: Soldier = Net._soldiers.get(1)
	if host:
		host.global_position = Vector3(0, -900, 0)
		host.set_physics_process(false)
	var hint_n: int = m.bot_hints(Vector3.ZERO, 10000.0).size() if m.has_method("bot_hints") else 0
	var kinds := {}
	if m.has_method("bot_hints"):
		for h in m.bot_hints(Vector3.ZERO, 10000.0):
			kinds[h.kind] = int(kinds.get(h.kind, 0)) + 1
	lines.append("hints_enabled=%s hints=%d %s" % [BotGoals.use_map_hints, hint_n, str(kinds)])
	if m.has_method("bot_hints") and m.has_method("mp_zones"):
		for h in m.bot_hints(Vector3.ZERO, 10000.0):
			if h.kind == "emplacement":
				var dz := INF
				for z in m.mp_zones():
					dz = minf(dz, BotNav.flat((z["xf"] as Transform3D).origin, h.pos))
				lines.append("stellung %s abstand_naechste_zone=%.1f m netz=%.1f m" % [str(h.pos.snapped(Vector3.ONE * 0.1)), dz,
					BotNav.flat(BotNav.closest(host, h.pos), h.pos) if host else -1.0])
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var anchor := {}
	var anchor_t := {}
	var stuck_max := {}
	var deep := {}
	var deep_max := 0.0
	var samples := 0
	var hold_samples := 0
	var hint_samples := 0
	var high_samples := 0
	var trench_samples := 0
	var wall_close := 0
	var vias := {}
	var mounts := {}
	var mounted_samples := 0
	var wall_close_free := 0       ## an der Wand, aber nicht an einer ausgewiesenen Stellung (Fenster liegen absichtlich an der Wand)
	var wall_sum := 0.0
	var first_contact := -1.0
	var owners: Array = Net.zone_owner.duplicate()
	var zone_changes := 0
	var kills0 := _kills()
	var t := 0.0
	var start := now()
	while t < dur:
		await game_wait(0.5)
		t = now() - start
		if Net.zone_owner.size() == owners.size():
			for i in owners.size():
				if int(owners[i]) != int(Net.zone_owner[i]):
					zone_changes += 1
			owners = Net.zone_owner.duplicate()
		for s in _bots():
			if not s.alive:
				anchor.erase(s)
				continue
			var b := s.get_node_or_null("EnemyBrain") as BotBrain
			if b == null:
				continue
			var p: Vector3 = s.global_position
			samples += 1
			vias[s.soldier_name] = maxi(int(vias.get(s.soldier_name, 0)), b.nav.route_vias)
			mounts[s.soldier_name] = maxi(int(mounts.get(s.soldier_name, 0)), b.emp_mounts)
			if s.mounted != null:
				mounted_samples += 1
			var wants: bool = b.has_move_target() and not s.is_climbing()
			if not anchor.has(s) or p.distance_to(anchor[s]) > 1.5 or not wants:
				anchor[s] = p
				anchor_t[s] = t
			stuck_max[s.soldier_name] = maxf(float(stuck_max.get(s.soldier_name, 0.0)), t - float(anchor_t[s]))
			# „gefangen unten“: will laufen, steckt aber am Stück in Graben/Keller (Halten dort ist gewollt)
			if p.y < -0.6:
				trench_samples += 1
			if p.y < -0.6 and wants:
				deep[s] = float(deep.get(s, 0.0)) + 0.5
				deep_max = maxf(deep_max, deep[s])
			else:
				deep[s] = 0.0
			if p.y > 2.5:
				high_samples += 1
			if b._holding or not wants:
				hold_samples += 1
				if m.has_method("bot_hint_stance") and m.bot_hint_stance(p) >= 0:
					hint_samples += 1
			if first_contact < 0.0:
				for e in b.perception.awareness:
					if is_instance_valid(e) and e.alive and e.team != s.team and float(b.perception.awareness[e]) > 0.5:
						first_contact = t
						break
			var md := 2.0
			for k in 8:
				var a := TAU * float(k) / 8.0
				var o: Vector3 = p +Vector3.UP * 0.9
				var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0, sin(a)) * 2.0, 1)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					md = minf(md, o.distance_to(hit.position))
			wall_sum += md
			if md < 0.4:
				wall_close += 1
				if not (m.has_method("bot_hint_stance") and m.bot_hint_stance(p) >= 0):
					wall_close_free += 1
		if Net.match_over:
			break
	var sm: Array = stuck_max.values()
	sm.sort()
	var worst: float = sm[-1] if not sm.is_empty() else 0.0
	var over10 := sm.filter(func(x): return x > 10.0).size()
	lines.append("dauer_s=%.0f bots=%d samples=%d" % [t, _bots().size(), samples])
	lines.append("festhaengen_max_s=%.1f bots_ueber_10s=%d" % [worst, over10])
	lines.append("halten_anteil_an_stellung=%.1f%% (halten %d, an Hinweis %d)" % [100.0 * hint_samples / maxf(hold_samples, 1), hold_samples, hint_samples])
	lines.append("anteil_erhoeht=%.1f%% anteil_graben_keller=%.1f%% laengste_zeit_unten_s=%.1f" % [100.0 * high_samples / maxf(samples, 1),
		100.0 * trench_samples / maxf(samples, 1), deep_max])
	lines.append("wand_mittel_m=%.2f wand_unter_0_4m=%.1f%% davon_ausserhalb_stellung=%.1f%%" % [wall_sum / maxf(samples, 1),
		100.0 * wall_close / maxf(samples, 1), 100.0 * wall_close_free / maxf(samples, 1)])
	lines.append("erster_feindkontakt_s=%.1f zonenwechsel=%d abschuesse=%d" % [first_contact, zone_changes, _kills() - kills0])
	var via_n := 0
	for v in vias.values():
		via_n += int(v)
	var mount_n := 0
	for v in mounts.values():
		mount_n += int(v)
	lines.append("routen_ueber_graben_flanke=%d stellung_besetzt=%d anteil_an_waffe=%.1f%%" % [via_n, mount_n,
		100.0 * mounted_samples / maxf(samples, 1)])
	for l in lines:
		print("BAVBOTS ", l)
	if BotGoals.use_map_hints:
		await _emplacement_probe(m)
	check(worst < STUCK_LIMIT * 2.0, "kein Bot > 40 s festgehängt (%.1f s)" % worst)
	check(deep_max < 60.0, "kein Bot > 60 s am Stück in Graben/Keller (%.1f s)" % deep_max)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/bavaria_bots%s.txt" % String(Game.cli.get("tag", ""))), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	_finish()


## Mechanik Waffenstellung: ein Mitglied wird an die Flak gesetzt, besetzt sie über _hold_in_area und verlässt sie
## nach Ablauf wieder (Server; Sitzvergabe über die Operator-Synchronisierung der Stellung).
func _emplacement_probe(m: Node) -> void:
	var gun = null
	for h in m.bot_hints(Vector3.ZERO, 10000.0):
		if h.kind == "emplacement" and is_instance_valid(h.emplacement) and h.emplacement.can_ai_mount(_bots()[0]):
			gun = h.emplacement
			break
	check(gun != null, "Kartenhinweis liefert freie Waffenstellung")
	if gun == null:
		return
	var b: BotBrain = null
	for s in _bots():
		var bb := s.get_node_or_null("EnemyBrain") as BotBrain
		if bb and s.alive and not bb.is_leader() and s.mounted == null:
			b = bb
			break
	check(b != null, "Mitglied für Stellungsprobe gefunden")
	if b == null:
		return
	var spot: Vector3 = BotNav.closest(b.soldier, gun.gunner_spot())
	b.soldier.global_position = spot + Vector3.UP * 0.1
	b.soldier.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var e = BotGoals.map_emplacement(b, spot, 5.0)
	check(e == gun, "BotGoals.map_emplacement findet die Stellung")
	b._emp = gun
	b.hold_pos = spot
	b._hold_t = 30.0
	b._hold_pick_t = now()
	b._hold_threat = b._group_threat()
	b._hold_owner = int(Net.zone_owner[b.goal_zone]) if b.goal_zone >= 0 and b.goal_zone < Net.zone_owner.size() else -1
	b._hold_in_area(0.05)
	check(b.soldier.mounted == gun and gun.gunner == b.soldier, "Bot besetzt die Stellung (Server)")
	lines.append("stellungsprobe besetzt=%s peer=%d" % [b.soldier.mounted == gun, int(b.soldier.get_meta("net_peer", 0))])
	b._emp_t = 500.0
	await game_wait(0.3)
	check(b.soldier.mounted == null and gun.gunner == null, "Bot verlässt die Stellung nach Ablauf")


func _kills() -> int:
	var n := 0
	for id in Net.players:
		n += int(Net.players[id].get("kills", 0))
	return n


func _bots() -> Array:
	var out: Array = []
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]):
			out.append(Net._soldiers[k])
	return out


func _finish() -> void:
	print("ERGEBNIS test_bavaria_bots: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	Net.leave(false)
	get_tree().quit(1 if failed > 0 else 0)
