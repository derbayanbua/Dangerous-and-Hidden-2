extends "res://tests/test_gameplay.gd"
## KI-Soldaten im Mehrspieler (Server): Rollen mit Rollenwaffen und Persönlichkeiten, Gruppen, Heldenfiguren (lokal),
## realistische Erkennung (kein Sofort-Erfassen), Gefecht, Trupp-Taktik (Abstand, Deckungsfeuer in Feuerstößen,
## Flankenweg), Wegfindung/Zielerreichung in BESETZUNG und HD2-AUFGABEN auf mehreren Original-MP-Karten,
## kein Festhängen (> 20 s), Gefechtsrunde mit beiden Teams.
##   tools\godot.cmd --headless -- --autoplay=test_bots [--phase=all|roles|dm|tactics|nav|combat]
##       [--occ_maps=mp_a,mp_b] [--obj_maps=mp_c,…] [--nav_s=150] [--combat_map=mp_x] [--combat_s=150]
## Messwerte je Karte: test_output/bot_metrics.txt

const OCC_MAPS := ["mp_burma1_mp_zone", "mp_czech4_mp_zone", "mp_normandy2_mp_zone", "mp_alps1_mp_zone"]   ## + lokale BESETZUNG-Karten
const OBJ_MAPS := ["mp_burma1_obj", "mp_arctic1_obj", "mp_czech2_obj", "mp_africa3_obj", "mp_arctic3_obj"]
const STUCK_LIMIT := 20.0
const PLAT := Vector3(0, 400, 0)        ## Testgelände (Taktik) hoch über der Karte

var metrics: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(7200.0, true, false, true).timeout.connect(_timeout)
	_run.call_deferred()


func _timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_write_metrics()
	_finish()


func _host(map: String, m: int, bots: int) -> Node:
	Net.local_name = "Host"
	if not Net.host({"name": "Bots", "map": map, "mode": m, "max_players": 16, "time_limit_min": 0, "score_limit": 0,
			"respawn_s": 5, "password": "", "port": Net.PORT + 20, "friendly_fire": false, "bots_per_team": bots, "warmup_s": 0}):
		return null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.3).timeout
		var mm := Game.current_mission()
		# erst messen, wenn das (asynchron gebackene) Navigationsnetz fertig ist
		if mm and Net._soldiers.has(1) and Net._soldiers.keys().filter(func(k): return int(k) < 0).size() >= bots * 2 \
				and mm.get("nav_ready") != false:
			return mm
	return null


func _bots() -> Array:
	var out: Array = []
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]):
			out.append(Net._soldiers[k])
	return out


func _brain(s: Soldier) -> BotBrain:
	return s.get_node_or_null("EnemyBrain") as BotBrain


func _park(s: Soldier, i: int) -> void:
	var b := _brain(s)
	if b:
		b.enabled = false
		b.stop_moving()
	s.global_position = Vector3(-2000 - i * 5, -400, -2000)
	s.velocity = Vector3.ZERO
	s.set_physics_process(false)


func _host_off() -> void:
	var host: Soldier = Net._soldiers.get(1)
	if is_instance_valid(host):
		host.global_position = Vector3(0, -900, 0)
		host.set_physics_process(false)


func _leave() -> void:
	Net.leave(false)
	await frames(10)


func _run() -> void:
	await frames(5)
	var ph := String(Game.cli.get("phase", "all"))
	if ph in ["all", "roles"]:
		await _phase_roles()
	if ph in ["all", "tactics"]:
		await _phase_tactics()
	if ph in ["all", "dm"]:
		await _phase_dm()
	if ph in ["all", "nav"]:
		await _phase_nav()
	if ph in ["all", "combat"]:
		await _phase_combat()
	_write_metrics()
	_finish()


func _write_metrics() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/bot_metrics%s.txt" % String(Game.cli.get("tag", ""))), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(metrics) + "\n")


# --- Rollen, Persönlichkeiten, Gruppen, Helden, Erkennung -------------------------------------------

func _phase_roles() -> void:
	var m = await _host("mp_arena_a1_blizzard", Net.Mode.TEAM_DEATHMATCH, 5)
	check(m != null, "Server mit 5 KI-Soldaten je Team")
	if m == null:
		return
	var bots := _bots()
	check(bots.size() == 10, "10 KI-Soldaten erzeugt", str(bots.size()))
	var roles := {}
	var personas := {}
	var role_ok := true
	var persona_ok := true
	for s in bots:
		var b := _brain(s)
		if b == null:
			role_ok = false
			continue
		roles[b.role] = int(roles.get(b.role, 0)) + 1
		personas[b.persona] = int(personas.get(b.persona, 0)) + 1
		var w: Weapon = s.weapons[0]
		match b.role:
			BotBrain.Role.ASSAULT:
				role_ok = role_ok and w != null and w.data.weight > 8.0             # schweres MG
			BotBrain.Role.MEDIC:
				role_ok = role_ok and w != null and s.medkits >= 2
			BotBrain.Role.AT:
				role_ok = role_ok and s.weapons[WeaponData.Slot.LAUNCHER] != null and s.weapons[WeaponData.Slot.LAUNCHER].data.action == WeaponData.Action.ROCKET
			BotBrain.Role.SNIPER:
				role_ok = role_ok and w != null and w.data.aim_fov <= 30.0          # Zielfernrohr
			BotBrain.Role.SNEAKER:
				var p2: Weapon = s.weapons[WeaponData.Slot.SIDEARM]
				role_ok = role_ok and w != null and (w.data.noise_radius < 20.0 or (p2 != null and p2.data.noise_radius < 20.0))
		if w == null or w.total_ammo() <= w.data.magazine_size:      # passende Munition (Reservemagazine)
			role_ok = false
		# Persönlichkeit passt zur Waffe
		var k := BotTraits.weapon_kind(s)
		match b.persona:
			BotTraits.Trait.SUPPORT:
				persona_ok = persona_ok and k == "mg"
			BotTraits.Trait.SNIPER:
				persona_ok = persona_ok and k == "scoped"
			BotTraits.Trait.CAMPER:
				persona_ok = persona_ok and (k in ["silenced", "scoped"] or BotTraits.has_silenced_sidearm(s))
		if not role_ok:
			print("ROLLE ", b.role, ": ", w.data.display_name if w else "-", " aim_fov ", w.data.aim_fov if w else 0)
	check(roles.size() == 5 and role_ok, "Rollen mit Rollenwaffen und Munition (Sturm-MG, Sanitäter, Panzerabwehr, Scharfschütze, Schleicher)", str(roles))
	check(personas.size() >= 4 and persona_ok, "Persönlichkeiten passend zur Waffe (Camper, Flankierer, Deckungsfeuer, Scharfschütze)",
		str(personas.keys().map(func(p): return BotTraits.trait_name(p))))
	var in_groups := bots.filter(func(s): return _brain(s).group.size() >= 2).size()
	var max_group := 0
	for s in bots:
		max_group = maxi(max_group, _brain(s).group.size())
	check(in_groups >= 8 and max_group <= 4, "KI-Soldaten handeln in Gruppen (bis 4)", "%d in Gruppen" % in_groups)
	var hs := Net.heroes()
	if not hs.is_empty():
		var names: Array = Net.players.values().map(func(p): return String(p["name"]))
		check(hs.all(func(h): return names.has(String(h["name"]))), "Heldenfiguren (lokal) im Spiel", str(names))
		var hero: Soldier = null
		for s in bots:
			if s.soldier_name == String(hs[0]["name"]):
				hero = s
		check(hero != null and hero.skill_shooting == 100.0 and hero.max_health > 100.0, "Held mit Bestwerten")
	# Erkennung realistisch: Gegner im Rücken auf 25 m wird nicht sofort erkannt
	var a: Soldier = bots.filter(func(s): return s.team == Soldier.TEAM_ALLIED)[0]
	var x: Soldier = bots.filter(func(s): return s.team == Soldier.TEAM_AXIS)[0]
	var ba := _brain(a)
	var i := 0
	for s in bots:
		if s != a and s != x:
			_park(s, i)
			i += 1
	_brain(x).enabled = false
	_host_off()
	ba.enabled = false
	a.global_position = Vector3(0, 30, 0)
	x.global_position = Vector3(0, 30, -25)
	a.velocity = Vector3.ZERO
	x.velocity = Vector3.ZERO
	a.look_yaw = PI        # blickt nach Süden (+Z), Gegner liegt nördlich (−Z)
	x.look_yaw = PI
	(a.get_node("Perception") as Perception).awareness.clear()
	await frames(2)
	ba.enabled = true
	ba.set_state(EnemyBrain.State.GUARD)
	await seconds(0.5)
	check(ba.perception.best_target() == null, "Gegner im Rücken nicht sofort erkannt (kein Aimbot)")
	await _leave()


# --- Feuerkampf auf der kompakten Original-DM-Karte -----------------------------------------------

func _phase_dm() -> void:
	var m = await _host("mp_arctic2_mp", Net.Mode.DEATHMATCH, 2)
	check(m != null, "Deathmatch ARCTIC2_MP mit 4 KI-Soldaten")
	if m == null:
		return
	var bots := _bots()
	_host_off()
	for s in bots:
		s.set_physics_process(true)
		var eb := _brain(s)
		eb.enabled = true
		eb.perception.awareness.clear()
		eb.perception.last_known.clear()
		eb.target = null
		eb.goal = Vector3.INF
		eb.set_state(EnemyBrain.State.GUARD)
	var shots0 := Ballistics.shots_fired
	var deaths := 0
	var t := 0
	while t < 150:
		await seconds(1.0)
		t += 1
		deaths = 0
		for k in Net.players:
			deaths += int(Net.players[k]["deaths"])
		if deaths >= 1:
			break
	for s in bots:
		if is_instance_valid(s):
			var bb := _brain(s)
			print("BOT %s %s %s ziel %s %s" % [s.soldier_name, bb.state_name() if bb else "-", str(s.global_position.snapped(Vector3.ONE)),
				bb.goal_kind if bb else "", str(bb.goal.snapped(Vector3.ONE)) if bb and bb.goal.is_finite() else "-"])
	check(Ballistics.shots_fired > shots0, "KI-Soldaten schießen", str(Ballistics.shots_fired - shots0))
	check(deaths >= 1, "Gefecht der KI-Soldaten mit Verlusten", "%d Tote nach %d s Spielzeit" % [deaths, t])
	metrics.append("DM mp_arctic2_mp: %d Schüsse, %d Tote nach %d s" % [Ballistics.shots_fired - shots0, deaths, t])
	await _leave()


# --- Trupp-Taktik auf einem Testgelände mit Mauerraster ---------------------------------------------

## Ebene 100 × 100 m mit niedrigen Mauern (1,2 m) im 9-m-Raster; eigenes Navigationsnetz
func _platform(m: Node) -> Node3D:
	var reg := NavigationRegion3D.new()
	reg.name = "BotTestPlatform"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.agent_radius = 0.4
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.4
	reg.navigation_mesh = nm
	m.add_child(reg)
	reg.global_position = PLAT
	_box(reg, Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	for xi in range(-4, 5):
		for zi in range(-4, 5):
			if (xi + zi) % 2 != 0:
				continue
			_box(reg, Vector3(xi * 9.0, 0.6, zi * 9.0 + 4.5), Vector3(3.0, 1.2, 0.5))
	reg.bake_navigation_mesh(false)
	await frames(10)
	return reg


func _box(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.position = pos
	return b


func _place(s: Soldier, p: Vector3, yaw: float) -> void:
	s.set_physics_process(true)
	s.global_position = PLAT + p + Vector3.UP * 0.1
	s.velocity = Vector3.ZERO
	s.look_yaw = yaw
	s.health = s.max_health
	var b := _brain(s)
	if b:
		b.perception.awareness.clear()
		b.perception.last_known.clear()
		b.perception.visible_now.clear()
		b.target = null
		b.set_state(EnemyBrain.State.GUARD)
		b.enabled = true


func _dummy(s: Soldier, p: Vector3) -> void:
	_place(s, p, 0.0)
	_brain(s).enabled = false
	s.max_health = 100000.0
	s.health = 100000.0
	s.move_input = Vector3.ZERO
	s.trigger = false


func _phase_tactics() -> void:
	var m = await _host("mp_arena_a1_blizzard", Net.Mode.TEAM_DEATHMATCH, 4)
	check(m != null, "Taktik: Server mit 4 KI-Soldaten je Team")
	if m == null:
		return
	_host_off()
	var bots := _bots()
	var i := 0
	for s in bots:
		_park(s, i)
		i += 1
	await _platform(m)
	var allies: Array = bots.filter(func(s): return s.team == Soldier.TEAM_ALLIED)
	var axis: Array = bots.filter(func(s): return s.team == Soldier.TEAM_AXIS)
	var grp: Array = _brain(allies[0]).group.filter(func(b): return is_instance_valid(b))
	check(grp.size() == 4, "Taktik: Trupp mit 4 KI-Soldaten", str(grp.size()))
	await _tactic_spacing(grp)
	for s in allies:
		_park(s, 0)
	await _tactic_support(grp, axis)
	for s in allies:
		_park(s, 0)
	for s in axis:
		_park(s, 1)
	await _tactic_flank(grp, axis)
	await _leave()


## Abstand: Trupp quert das Gelände (Ziel 70 m entfernt) und hält am Ziel; nächster Kamerad selten < 3 m
func _tactic_spacing(grp: Array) -> void:
	var lead: BotBrain = grp[0]
	for k in grp.size():
		var b: BotBrain = grp[k]
		_place(b.soldier, Vector3(-3.0 + k * 2.0, 0, 44), 0.0)      # eng beieinander starten (2 m)
	lead.test_goal = BotNav.closest(lead.soldier, PLAT + Vector3(0, 0, -35))
	lead.goal = Vector3.INF
	var near := 0
	var samples := 0
	var nn_all: Array = []
	var min_after := INF
	var t := 0.0
	while t < 40.0:
		await seconds(0.25)
		t += 0.25
		if t < 4.0:
			continue
		for b in grp:
			var d := BotSquad.nearest_mate(b)
			nn_all.append(d)
			samples += 1
			if d < 3.0:
				near += 1
			min_after = minf(min_after, d)
	nn_all.sort()
	var med: float = nn_all[nn_all.size() / 2] if not nn_all.is_empty() else 0.0
	var frac := float(near) / maxf(samples, 1)
	var arrived := BotNav.flat(lead.soldier.global_position, lead.test_goal) < 4.0
	var hold_d: Array = []
	for b in grp:
		hold_d.append(snappedf(BotSquad.nearest_mate(b), 0.1))
	print("ABSTAND Median %.1f m, Anteil < 3 m %.1f %%, Minimum %.1f m, am Ziel %s, Endabstände %s" % [med, frac * 100.0, min_after, arrived, hold_d])
	metrics.append("Taktik Abstand: Median nächster Kamerad %.1f m, Anteil < 3 m %.1f %%, Minimum %.1f m, Endabstände %s" % [med, frac * 100.0, min_after, hold_d])
	check(arrived, "Trupp erreicht das Ziel auf dem Gelände (Mauerraster)", str(lead.soldier.global_position - PLAT))
	check(med >= 5.0 and frac <= 0.08, "KI-Soldaten halten Abstand (Median ≥ 5 m, < 3 m höchstens 8 %)", "Median %.1f, %.1f %%" % [med, frac * 100.0])
	check(hold_d.all(func(d): return d >= 4.5), "Am Ziel getrennte Halteplätze (≥ 4,5 m)", str(hold_d))
	lead.test_goal = Vector3.INF


func _find(grp: Array, p: int) -> BotBrain:
	for b in grp:
		if b.persona == p:
			return b
	return null


## Deckungsfeuer: MG-Bot feuert in Feuerstößen auf sichtbaren Feind, hält danach die letzte bekannte Lage hinter
## einer Mauer nieder und wechselt nach Feuerstößen die Stellung
func _tactic_support(grp: Array, axis: Array) -> void:
	var sb := _find(grp, BotTraits.Trait.SUPPORT)
	check(sb != null, "Trupp hat einen Deckungsfeuer-Bot (MG)")
	if sb == null:
		return
	var enemy: Soldier = axis[0]
	_dummy(enemy, Vector3(0, 0, -2))
	_place(sb.soldier, Vector3(0, 0, 30), 0.0)
	await frames(3)
	var times: Array = []
	var cb := func(_w): times.append(BotGoals.now())
	sb.soldier.shot_fired.connect(cb)
	var start := sb.soldier.global_position
	sb.perception.awareness[enemy] = 1.0
	sb.perception.last_known[enemy] = enemy.global_position
	sb._on_detected(enemy)
	await seconds(14.0)
	# Feuerstöße aus den Schusszeiten (Lücke > 0,5 s trennt)
	var groups: Array = []
	var cur := 0
	var last := -10.0
	var pauses: Array = []
	for tt in times:
		if float(tt) - last > 0.5 and cur > 0:
			groups.append(cur)
			pauses.append(float(tt) - last)
			cur = 0
		cur += 1
		last = float(tt)
	if cur > 0:
		groups.append(cur)
	var mean_pause := 0.0
	for p in pauses:
		mean_pause += float(p)
	mean_pause /= maxf(pauses.size(), 1)
	print("FEUERSTÖSSE %s Pausen %s Stellungswechsel %d burst_log %s" % [groups, pauses.map(func(p): return snappedf(p, 0.1)), sb.relocations, sb.burst_log.size()])
	var sizes_ok := groups.size() >= 3 and groups.filter(func(g): return g >= 3 and g <= 12).size() >= groups.size() - 1
	check(sizes_ok and mean_pause >= 0.8, "Deckungsfeuer in Feuerstößen (3–12 Schuss, Pausen ≥ 0,8 s)",
		"%d Stöße %s, mittl. Pause %.1f s" % [groups.size(), groups, mean_pause])
	# Sicht nehmen: Mauer vor den Gegner → Niederhalten der letzten bekannten Position
	var wall := _box(Game.current_mission(), enemy.global_position + Vector3(0, 1.5, 3.0), Vector3(6, 3, 0.6))
	await seconds(1.0)
	var n0 := times.size()
	var vis_after := false
	for k in 12:
		await seconds(0.5)
		vis_after = vis_after or sb.perception.best_target() == enemy
	var supp := times.size() - n0
	check(supp >= 5 and not vis_after, "Niederhalten der letzten bekannten Feindposition ohne Sicht", "%d Schuss, sichtbar %s" % [supp, vis_after])
	await seconds(6.0)
	var moved := BotNav.flat(sb.soldier.global_position, start)
	check(sb.relocations >= 1, "Deckungsfeuer-Bot wechselt nach Feuerstößen die Stellung", "%d Wechsel, %.1f m vom Start" % [sb.relocations, moved])
	metrics.append("Taktik Deckungsfeuer: %d Feuerstöße %s, mittl. Pause %.1f s, Niederhalten ohne Sicht %d Schuss, %d Stellungswechsel"
		% [groups.size(), groups, mean_pause, supp, sb.relocations])
	sb.soldier.shot_fired.disconnect(cb)
	wall.queue_free()


## Flankenweg: Gegner hinter Mauer bekannt; Deckungsfeuer hält nieder, Flankierer rückt seitlich (≥ 8 m) vor
func _tactic_flank(grp: Array, axis: Array) -> void:
	var fb := _find(grp, BotTraits.Trait.FLANKER)
	var sb := _find(grp, BotTraits.Trait.SUPPORT)
	check(fb != null, "Trupp hat einen Flankierer")
	if fb == null:
		return
	var enemy: Soldier = axis[0]
	_dummy(enemy, Vector3(0, 0, -2))
	enemy.stance_request = Soldier.Stance.CROUCH
	var wall := _box(Game.current_mission(), PLAT + Vector3(0, 1.0, 0.6), Vector3(5, 2.0, 0.6))
	_place(fb.soldier, Vector3(4, 0, 32), 0.0)
	if sb:
		_place(sb.soldier, Vector3(-6, 0, 33), 0.0)
	await frames(3)
	var g0 := fb.grenades_thrown
	var start := fb.soldier.global_position
	for b in [fb, sb]:
		if b != null:
			b.support(enemy, b.soldier.global_position)       # Feindlage per Zuruf bekannt, nicht gesehen
	var supp_at_flank := false
	var lat_max := 0.0
	var axis_dir := (enemy.global_position - start)
	axis_dir.y = 0.0
	axis_dir = axis_dir.normalized()
	var perp := Vector3(-axis_dir.z, 0, axis_dir.x)
	var t := 0.0
	var flank_t := -1.0
	var first_lat := 0.0
	while t < 30.0:
		await seconds(0.5)
		t += 0.5
		if fb.flank_count > 0 and flank_t < 0.0:
			flank_t = t
			supp_at_flank = sb != null and BotGoals.now() < fb.leader().suppress_until + 1.0
			# erste Flanke: seitlicher Versatz des Flankenziels zur Achse Ausgangsdeckung → Gegner
			var ax := enemy.global_position - fb.flank_origin
			ax.y = 0.0
			var pp := Vector3(-ax.z, 0, ax.x).normalized()
			first_lat = absf((fb.flank_target - fb.flank_origin).dot(pp))
		lat_max = maxf(lat_max, absf((fb.soldier.global_position - start).dot(perp)))
	var tgt_lat: float = first_lat
	var closer := fb.soldier.global_position.distance_to(enemy.global_position) < start.distance_to(enemy.global_position)
	print("FLANKE Versuche %d Ziel seitlich %.1f m, tatsächlich seitlich %.1f m, näher %s, Granaten %d, Deckungsfeuer dabei %s, Stöße %d" % [
		fb.flank_count, tgt_lat, lat_max, closer, fb.grenades_thrown - g0, supp_at_flank, sb.bursts if sb else -1])
	check(fb.flank_count >= 1 and tgt_lat >= 8.0 and lat_max >= 6.0, "Flankierer umgeht seitlich (Flankenziel ≥ 8 m, gelaufen ≥ 6 m quer zur Feindachse)",
		"Ziel %.1f m, gelaufen %.1f m" % [tgt_lat, lat_max])
	check(sb == null or sb.bursts >= 1, "Deckungsfeuer hält während des Vorrückens nieder", "%d Stöße, beim Losgehen %s" % [sb.bursts if sb else 0, supp_at_flank])
	wall.queue_free()
	# Granate in Deckung/Raum: Gegner in einer Mauerecke (U-Form, offen nach hinten), Flankierer 16 m davor
	for s in [fb.soldier] + ([sb.soldier] if sb else []):
		_park(s, 2)
	_dummy(enemy, Vector3(30, 0, -20))
	enemy.stance_request = Soldier.Stance.CROUCH
	var room: Array = [_box(Game.current_mission(), PLAT + Vector3(30, 1.2, -17.5), Vector3(5, 2.4, 0.4)),
		_box(Game.current_mission(), PLAT + Vector3(27.5, 1.2, -20), Vector3(0.4, 2.4, 5)),
		_box(Game.current_mission(), PLAT + Vector3(32.5, 1.2, -20), Vector3(0.4, 2.4, 5))]
	_place(fb.soldier, Vector3(30, 0, -4), 0.0)
	var gw: Weapon = fb.soldier.weapons[WeaponData.Slot.GRENADE]
	if gw:
		gw.in_mag = 1
		gw.reserve = 1
	await frames(3)
	var g1 := fb.grenades_thrown
	fb.support(enemy, fb.soldier.global_position)
	await seconds(8.0)
	var thrown := fb.grenades_thrown - g1
	check(thrown >= 1, "Flankierer wirft Granate in die Deckung des Gegners (ohne Sicht)", str(thrown))
	metrics.append("Taktik Flanke: Flankenziel %.1f m seitlich, gelaufen %.1f m quer, näher %s, Deckungsfeuer beim Losgehen %s, Granaten in Deckung %d"
		% [tgt_lat, lat_max, closer, supp_at_flank, thrown])
	for r in room:
		r.queue_free()


# --- Wegfindung/Zielerreichung auf Original-MP-Karten ------------------------------------------------

func _list(key: String, def: Array) -> Array:
	return Array(String(Game.cli[key]).split(",", false)) if Game.cli.has(key) else def


func _phase_nav() -> void:
	var dur := float(Game.cli.get("nav_s", "150"))
	var results: Array = []
	var occ: Array = OCC_MAPS.duplicate()
	for lid in Game.local_content.get("mp_maps_first", []):      # lokale Zusatzkarten (nicht im Repository)
		if int(Game.MISSIONS.get(String(lid), {}).get("mp_mode", -1)) == Net.Mode.OCCUPATION:
			occ.append(String(lid))
	for id in _list("occ_maps", occ):
		results.append(await _nav_round(String(id), Net.Mode.OCCUPATION, 4, dur))
	for id in _list("obj_maps", OBJ_MAPS):
		results.append(await _nav_round(String(id), Net.Mode.OBJECTIVES, 4, dur))
	var ok_occ := results.filter(func(r): return r.get("mode", -1) == Net.Mode.OCCUPATION and r.get("pass", false) and String(r.get("id", "")).begins_with("mp_")).size()
	var ok_obj := results.filter(func(r): return r.get("mode", -1) == Net.Mode.OBJECTIVES and r.get("pass", false) and String(r.get("id", "")).begins_with("mp_")).size()
	check(ok_occ >= 3, "Besetzung: Zielerreichung auf ≥ 3 Original-MP-Karten", "%d Karten" % ok_occ)
	check(ok_obj >= 3, "HD2-Aufgaben: Zielerreichung auf ≥ 3 Original-MP-Karten", "%d Karten" % ok_obj)


## Eine Seite (ohne Gegner, reine Wegfindung) läuft dur s Spielzeit: Zielquote, Zeiten, längstes Festhängen
func _nav_round(map: String, mode: int, n: int, dur: float) -> Dictionary:
	var m = await _host(map, mode, n)
	if m == null:
		check(false, "%s: Server mit KI-Soldaten" % map)
		metrics.append("%s: Laden fehlgeschlagen" % map)
		return {"mode": mode, "pass": false}
	_host_off()
	# angreifende Seite: Besetzung = Team mit weniger Zonen; Aufgaben = Team mit den meisten Aufgaben
	var team := Soldier.TEAM_ALLIED
	if mode == Net.Mode.OBJECTIVES:
		var cnt := [0, 0]
		for o in m.mp_objectives():
			if int(o["team"]) in [0, 1]:
				cnt[int(o["team"])] += 1
		team = 0 if cnt[0] >= cnt[1] else 1
	else:
		var own := [0, 0]
		for z in m.mp_zones():
			if int(z["owner"]) in [0, 1]:
				own[int(z["owner"])] += 1
		team = 0 if own[0] <= own[1] else 1
	var active: Array = []
	var i := 0
	for s in _bots():
		if s.team == team:
			active.append(s)
		else:
			_park(s, i)
			i += 1
	var owners0: Array = Net.zone_owner.duplicate()
	var obj0 := Net.obj_done.size()
	var anchor := {}
	var anchor_t := {}
	var stuck := {}
	var idle := {}
	var idle_max := 0.0
	var logs := {}
	var nud := {}
	var stuck_n := {}
	var ended := ""
	var t := 0.0
	var worst := ""
	while t < dur:
		await seconds(0.5)
		t += 0.5
		for s in active:
			if not is_instance_valid(s) or not s.alive:
				continue
			var b := _brain(s)
			var moving_wanted: bool = b.has_move_target() and not s.is_climbing() and s.heal_time_left <= 0.0     # will laufen
			if not anchor.has(s) or s.global_position.distance_to(anchor[s]) > 1.5 or not moving_wanted:
				anchor[s] = s.global_position
				anchor_t[s] = t
			# Stillstand ohne Laufziel, obwohl das Ziel nicht erreicht ist (wartet z. B. in der Formation)
			if b.goal.is_finite() and not b._holding and not b.has_move_target() and b.state == EnemyBrain.State.GUARD:
				idle[s] = float(idle.get(s, 0.0)) + 0.5
				idle_max = maxf(idle_max, float(idle[s]))
			else:
				idle[s] = 0.0
			var st: float = t - float(anchor_t[s])
			if st > float(stuck.get(s, 0.0)):
				stuck[s] = st
				if st > STUCK_LIMIT:
					worst = "%s bei %s (%s, Ziel %s %s)" % [s.soldier_name, str(s.global_position.snapped(Vector3.ONE)), b.state_name(),
						b.goal_kind, str(b.goal.snapped(Vector3.ONE))]
			# Verlauf je Bot sichern (bei Rundenende werden die KI-Soldaten neu erzeugt)
			logs[s.soldier_name] = b.goal_log.duplicate(true)
			nud[s.soldier_name] = b.nav.nudges
			stuck_n[s.soldier_name] = float(stuck.get(s, 0.0))
		if Net.match_over:
			ended = "Runde gewonnen nach %.0f s" % t
			break
		if int(t * 2.0) % 60 == 0:
			for s in active:
				if is_instance_valid(s):
					var b := _brain(s)
					print("SPUR %s %.0fs %s %s %s ziel %s %s gehalten %s fest %.1f" % [map, t, s.soldier_name, BotTraits.trait_name(b.persona),
						str(s.global_position.snapped(Vector3.ONE)), b.goal_kind, str(b.goal.snapped(Vector3.ONE)) if b.goal.is_finite() else "-",
						b._holding, b.nav.prog_t])
	# Auswertung je Bot: Ziele (Abstand > 5 m beim Setzen), erreicht/abgelöst/offen, Zeiten
	var reached := 0
	var open := 0
	var superseded := 0
	var times: Array = []
	var first_ok := 0
	var max_stuck := 0.0
	var nudges := 0
	var tnow := BotGoals.now()
	for nm in logs:
		nudges += int(nud[nm])
		max_stuck = maxf(max_stuck, float(stuck_n[nm]))
		var glog: Array = (logs[nm] as Array).filter(func(e): return float(e["dist"]) > 5.0)
		for k in glog.size():
			var e: Dictionary = glog[k]
			if float(e["reach_t"]) >= 0.0:
				reached += 1
				times.append(float(e["reach_t"]) - float(e["set_t"]))
			elif k < glog.size() - 1:
				superseded += 1
			elif tnow - float(e["set_t"]) > 60.0 and ended == "":
				open += 1             # jüngere Ziele (< 60 s) zählen nicht als verfehlt
		if not glog.is_empty() and float(glog[0]["reach_t"]) >= 0.0:
			first_ok += 1
	times.sort()
	var mean := 0.0
	for x in times:
		mean += float(x)
	mean /= maxf(times.size(), 1)
	var quote := float(reached) / maxf(reached + open, 1)
	var changed := 0
	for k in mini(owners0.size(), Net.zone_owner.size()):
		if int(owners0[k]) != int(Net.zone_owner[k]):
			changed += 1
	var extra: String = "Zonen gewechselt %d/%d" % [changed, Net.zone_owner.size()] if mode == Net.Mode.OCCUPATION \
		else "Aufgaben erledigt %d/%d" % [Net.obj_done.size() - obj0, m.mp_objectives().size()]
	var line := "%s (%s, %d Bots, %.0f s): Ziele erreicht %d, offen %d, abgelöst %d → Quote %.0f %%, erstes Ziel %d/%d, Zeit Ø %.0f s / max %.0f s, längstes Festhängen %.1f s, längster Stillstand vor dem Ziel %.1f s, Netz-Korrekturen %d, %s%s" % [
		map, "Besetzung" if mode == Net.Mode.OCCUPATION else "Aufgaben", active.size(), dur, reached, open, superseded, quote * 100.0,
		first_ok, active.size(), mean, float(times[times.size() - 1]) if not times.is_empty() else 0.0, max_stuck, idle_max, nudges, extra, (", " + ended) if ended != "" else ""]
	print("NAVMESS ", line)
	if worst != "":
		print("   FESTHÄNGEN: ", worst)
	metrics.append(line)
	var pass_ok := reached >= 1 and quote >= 0.75 and max_stuck <= STUCK_LIMIT
	# je Karte hart: kein Festhängen; Zielquote fließt in die Gesamtprüfung (≥ 3 Original-Karten je Modus) ein
	check(max_stuck <= STUCK_LIMIT, "%s: kein KI-Soldat > %.0f s festgehängt" % [map, STUCK_LIMIT],
		"max. fest %.1f s; Zielquote %.0f %% (%d erreicht)%s" % [max_stuck, quote * 100.0, reached, "" if pass_ok else " – Quote unter 75 %"])
	await _leave()
	return {"mode": mode, "pass": pass_ok, "id": map}


# --- Gefechtsrunde (beide Teams) --------------------------------------------------------------------

func _phase_combat() -> void:
	var map := String(Game.cli.get("combat_map", "mp_burma1_mp_zone"))
	var dur := float(Game.cli.get("combat_s", "150"))
	var m = await _host(map, Net.Mode.OCCUPATION, 4)
	check(m != null, "Gefechtsrunde %s mit 4 KI-Soldaten je Team" % map)
	if m == null:
		return
	_host_off()
	var shots0 := Ballistics.shots_fired
	var owners0: Array = Net.zone_owner.duplicate()
	var anchor := {}
	var anchor_t := {}
	var max_stuck := 0.0
	var worst := ""
	var near := 0
	var samples := 0
	var t := 0.0
	while t < dur:
		await seconds(0.5)
		t += 0.5
		for s in _bots():
			if not s.alive:
				continue
			var b := _brain(s)
			if b == null:
				continue
			var moving_wanted: bool = b.has_move_target() and not s.is_climbing() and s.heal_time_left <= 0.0     # will laufen
			if not anchor.has(s) or s.global_position.distance_to(anchor[s]) > 1.5 or not moving_wanted:
				anchor[s] = s.global_position
				anchor_t[s] = t
			var st: float = t - float(anchor_t[s])
			if st > max_stuck:
				max_stuck = st
				worst = "%s %s %s %s" % [s.soldier_name, str(s.global_position.snapped(Vector3.ONE)), b.state_name(), b.goal_kind]
			if b.state != EnemyBrain.State.COMBAT:
				samples += 1
				if BotSquad.nearest_mate(b) < 3.0:
					near += 1
	var deaths := 0
	for k in Net.players:
		deaths += int(Net.players[k]["deaths"])
	var changed := 0
	for k in mini(owners0.size(), Net.zone_owner.size()):
		if int(owners0[k]) != int(Net.zone_owner[k]):
			changed += 1
	var frac := float(near) / maxf(samples, 1)
	var line := "Gefecht %s (%.0f s, 4 gegen 4): %d Schüsse, %d Tote, Zonen gewechselt %d, Punkte %.1f : %.1f, längstes Festhängen %.1f s (%s), Abstand < 3 m %.1f %%" % [
		map, dur, Ballistics.shots_fired - shots0, deaths, changed, Net.team_score[0], Net.team_score[1], max_stuck, worst, frac * 100.0]
	print("NAVMESS ", line)
	metrics.append(line)
	check(Ballistics.shots_fired > shots0 and changed >= 1, "Gefechtsrunde: Gefecht und Zonenwechsel", "%d Schüsse, %d Zonen" % [Ballistics.shots_fired - shots0, changed])
	check(max_stuck <= STUCK_LIMIT, "Gefechtsrunde: kein KI-Soldat > %.0f s festgehängt" % STUCK_LIMIT, "%.1f s %s" % [max_stuck, worst])
	check(frac <= 0.15, "Gefechtsrunde: KI-Soldaten kleben nicht aneinander (< 3 m höchstens 15 %)", "%.1f %%" % (frac * 100.0))
	await _leave()
