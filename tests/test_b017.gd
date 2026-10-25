extends "res://tests/test_gameplay.gd"
## B-017 Level-Fehler: Türen africa1/no2 (echte Benutzen-Taste), arctic1 Ziele/Wasser/Zaun.
##   tools\godot.cmd --headless -- --mission=<id> --autoplay=test_b017 --phase=doors|probe
## Phase doors: jede Original-Tür von ihrem Standplatz per Benutzen-Taste öffnen und schließen.
## Phase probe: Türen und türähnliche Frames im Umkreis des Starts auflisten (Fehlersuche).

const TestDoors := preload("res://tests/test_normandie_doors.gd")

var _m: Mission
var _me: Soldier


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1400.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


## Mehrspieler-Karte (Server): Zielmarker ohne Skriptfehler „bool(null)“ (objective_markers.gd:49)
func _mp_markers() -> void:
	Net.local_name = "B017"
	Net.local_team = Soldier.TEAM_AXIS
	Net.host({"name": "B017", "map": "mp_normandy2_mp_zone", "mode": Net.Mode.OCCUPATION, "port": Net.PORT,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0,
		"password": "", "allow_vehicles": false})
	check(await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 400.0), "MP-Karte geladen")
	_m = Game.current_mission()
	var om := _markers()
	Settings.objective_markers = true
	var r = om._enabled()
	check(typeof(r) == TYPE_BOOL, "MP: ObjectiveMarkers._enabled ohne Skriptfehler", "runtime=%s Ergebnis=%s" % [_m.get("runtime"), r])
	om._collect()
	check(true, "MP: ObjectiveMarkers._collect gelaufen")
	Net.leave(false)


func _run() -> void:
	await frames(5)
	if String(Game.cli.get("phase", "")) == "mp_markers":
		await _mp_markers()
		_finish()
		return
	check(await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and mm.squad and mm.squad.leader(), 500.0), "Einsatz geladen")
	_m = Game.current_mission()
	_me = _m.squad.leader()
	var rt: LsRuntime = _m.get("runtime")
	for s in _m.squad.members:
		s.set_meta("protect_until", 1e12)
	if String(Game.cli.get("phase", "doors")) == "doors":
		# KI-Kameraden anhalten: no2 lief ein Kamerad während des Intros in die Außenzone → Einsatz beendet (Folge-/KI-
		# Verhalten gehört zu B-019/B-020, hier nicht Gegenstand)
		for s in _m.squad.members:
			if s != _me:
				s.process_mode = Node.PROCESS_MODE_DISABLED
	if rt:
		rt.auto_skip = true
		for i in 240:
			await get_tree().process_frame
			if not is_instance_valid(rt):
				check(false, "Einsatz während des Intros beendet")
				_finish()
				return
			if rt.in_cutscene:
				rt.end_cutscene()
	var phase := String(Game.cli.get("phase", "doors"))
	if phase == "probe":
		await _probe()
	elif phase == "water":
		_probe_water()
	elif phase == "doors":
		await _doors()
	elif phase == "arctic":
		# Laufproben ohne Missionsskripte (Teleport weg vom Führer löst sonst „utekl jsi albertovi“ → Einsatz verloren)
		rt.process_mode = Node.PROCESS_MODE_DISABLED
		await _arctic_water()
		await _arctic_fence()
		rt.process_mode = Node.PROCESS_MODE_INHERIT
		await _arctic_objectives()
	_finish()


func _probe() -> void:
	var it: OrigInteractive = _m.get("interactive")
	var start := _me.global_position
	print("START ", start, " Trupp ", _m.squad.members.map(func(s): return s.global_position))
	for k in it.controls:
		var d = it.controls[k]
		if d is OrigInteractive.OrigDoor:
			print("DOOR %s pos=%s dist=%.1f floor=%.2f locked=%s key=%d pick=%s amount=%.2f/%.2f prompt=%s can=%s" % [k, d.global_position,
				d.global_position.distance_to(start), d.floor_y, d.locked, d.key_item, d.lockpickable, d.amount, d.open_amount,
				d.prompt, d.can_interact(_me)])
	var want := String(Game.cli.get("nodes", "")).split(",", false)
	for n in _m.find_children("*", "Node3D", true, false):
		if want.has(String(n.name)):
			print("NODE %s aabb=%s parent=%s klasse=%s kinder=%s" % [n.name, OrigInteractive.world_aabb(n), n.get_parent().name, n.get_class(),
				n.get_children().map(func(c): return "%s:%s" % [c.name, c.get_class()])])
	var excl: Array[RID] = []
	var exn := String(Game.cli.get("exclude", "")).split(",", false)
	for n in _m.find_children("*", "Node3D", true, false):
		if exn.has(String(n.name)):
			for c in n.get_children():
				if c is CollisionObject3D:
					excl.append((c as CollisionObject3D).get_rid())
	for r in String(Game.cli.get("rays", "")).split(";", false):
		var ab := r.split("/")
		var a := _v3(ab[0])
		var b := _v3(ab[1])
		var q := PhysicsRayQueryParameters3D.create(a, b, 0xFFFFFFFF)
		q.hit_back_faces = true
		q.exclude = excl
		var hit := _m.get_world_3d().direct_space_state.intersect_ray(q)
		print("RAY %s -> %s: %s" % [a, b, ("%s bei %s" % [(hit["collider"] as Node).get_path(), hit["position"]]) if not hit.is_empty() else "frei"])
	if want.size() > 0 or Game.cli.has("rays"):
		return
	# türflügelähnliche statische Meshes (Höhe 1,6–2,8 m, Breite 0,5–1,6 m, dünn) im Umkreis
	var rad := float(Game.cli.get("radius", "2000"))
	for n in _m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		var w := maxf(b.size.x, b.size.z)
		var t := minf(b.size.x, b.size.z)
		if b.size.y > 1.6 and b.size.y < 2.8 and w > 0.5 and w < 1.6 and t < 0.25 and b.get_center().distance_to(start) < rad:
			var dyn := String(mi.get_path()).contains("/Dynamic/")
			var coll := not mi.find_children("*", "CollisionObject3D", false, false).is_empty()
			print("LEAF %s aabb=%s dist=%.1f parent=%s dyn=%s koll=%s kinder=%s" % [mi.name, b, b.get_center().distance_to(start),
				mi.get_parent().name, dyn, coll, mi.get_children().map(func(c): return String(c.name))])
	for n in _m.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if (nm.contains("dv") or nm.contains("door") or nm.contains("dver") or nm.contains("vrat")) and not n.has_meta("orig_ctl"):
			var p := (n as Node3D).global_position
			if p.distance_to(start) < float(Game.cli.get("radius", "2000")):
				print("FRAME %s pos=%s dist=%.1f parent=%s" % [n.name, p, p.distance_to(start), n.get_parent().name])


func _probe_water() -> void:
	var orig: OrigLevel = _m.get("orig")
	print("WATERBOXES ", orig.water.size())
	for n in orig.root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and OrigLevel._is_water(mi):
			print("WATER %s parent=%s aabb=%s mats=%s" % [mi.name, mi.get_parent().name, mi.global_transform * mi.get_aabb(),
				range(mi.mesh.get_surface_count()).map(func(i): return mi.get_active_material(i).resource_name if mi.get_active_material(i) else "-")])
	for b: AABB in orig.water:
		var c := b.get_center()
		var sm: SurfaceMap = OrigAudio.surface
		print("WATERBOX %s Material %d" % [b, sm.floor_material(Vector3(c.x, b.end.y, c.z), 1.5, 3.0) if sm else -2])
	for nm in ["objectives", "Rebel", "dummy_PLOT", "dummy_BRANY"]:
		var f = _m.runtime.find_frame(nm)
		print("FRAME %s %s" % [nm, (f as Node3D).global_position if f else "-"])
	print("START ", _me.global_position)


func _floor_at(x: float, z: float, from_y := 30.0) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -50, z), 1)
	q.exclude = _me.exclude_rids()
	var h := _m.get_world_3d().direct_space_state.intersect_ray(q)
	return null if h.is_empty() else h["position"]


func _markers() -> ObjectiveMarkers:
	var l := _m.find_children("*", "ObjectiveMarkers", true, false)
	if l.is_empty():
		var om := ObjectiveMarkers.new()
		om.setup(_m)
		_m.add_child(om)
		return om
	return l[0] as ObjectiveMarkers


## arctic1: Ziele in Original-Reihenfolge, Zielmarker erst Führer (Ziel 1), danach Eingang (Ziel 2)
func _arctic_objectives() -> void:
	await seconds(1.0)
	var o1: Objective = _m.objective(_m.orig_objectives.get(1, &""))
	var o2: Objective = _m.objective(_m.orig_objectives.get(2, &""))
	check(o1 != null and o2 != null and _m.objectives.find(o1) < _m.objectives.find(o2), "arctic1: Zielliste beginnt mit dem Führer (Ziel 1)",
		o1.text if o1 else "-")
	await _wait(func(): return o1.state == Objective.State.ACTIVE, 20.0)
	check(o1.state == Objective.State.ACTIVE and o2.state == Objective.State.ACTIVE, "arctic1: Führer und Eingang nach dem Intro aktiv (Original)",
		"o1=%d o2=%d" % [o1.state, o2.state])
	var om := _markers()
	Settings.objective_markers = true
	om._collect()
	var rebel: Node3D = _m.runtime.find_frame("Rebel")
	var entr: Node3D = _m.runtime.find_frame("objectives")
	var at_rebel := false
	var at_entr := false
	for t in om.targets:
		at_rebel = at_rebel or (t["pos"] as Vector3).distance_to(rebel.global_position) < 1.0
		at_entr = at_entr or (t["pos"] as Vector3).distance_to(entr.global_position) < 1.0
	check(at_rebel and not at_entr, "arctic1: Zielmarker zuerst am Führer, nicht an der Basis", str(om.targets.map(func(t): return t["pos"])))
	_m.set_orig_objective(1, 1)          # wie r_arc1a_objectives.scr nach Signal 4 des Führers
	om._collect()
	at_rebel = false
	at_entr = false
	for t in om.targets:
		at_rebel = at_rebel or (t["pos"] as Vector3).distance_to(rebel.global_position) < 1.0
		at_entr = at_entr or (t["pos"] as Vector3).distance_to(entr.global_position) < 1.0
	check(at_entr and not at_rebel, "arctic1: nach dem Führer zeigt der Marker zum Eingang", str(om.targets.map(func(t): return t["pos"])))


## arctic1: Fläche links am Haupteingang (m_ark01_hrdr_.QuadPatch01, Klz-Schnee) ist begehbar, kein Wasser
func _arctic_water() -> void:
	isolate_enemies([])
	_me.set_meta("protect_until", 1e12)
	var orig: OrigLevel = _m.get("orig")
	var p0 = _floor_at(64.0, -12.0, 15.0)
	var pc = _floor_at(64.0, -4.0, 15.0)
	check(pc != null and absf(float(pc.y) - 4.0) < 1.0, "arctic1: Haupteingang links hat festen Boden (Klz-Fläche)", str(pc))
	check(is_nan(orig.water_level_at(Vector3(64.0, 4.0, -4.0))), "arctic1: kein Wasserbereich am Haupteingang links")
	if p0 == null:
		return
	_me.global_position = p0 + Vector3.UP * 0.3
	_me.velocity = Vector3.ZERO
	TestDoors.face(_me, Vector3.BACK)        # +z: über die Fläche
	await frames(10)
	var swam := false
	var miny := 1e9
	for i in 5:
		await hold("move_forward", 0.6)
		swam = swam or _me.swimming
		miny = minf(miny, _me.global_position.y)
	check(not swam and _me.global_position.z > -4.0 and miny > 3.0, "arctic1: über die Fläche laufen ohne Schwimmen (Vorwärtstaste)",
		"Pos=%s minY=%.2f schwimmt=%s" % [_me.global_position, miny, swam])


## arctic1: Zaunfeld per Benutzen-Taste mit Drahtschere zerschneiden, danach durchlaufen
func _arctic_fence() -> void:
	var it: OrigInteractive = _m.get("interactive")
	check(int(it.stats.get("fences", 0)) >= 100, "arctic1: zerschneidbare Zaunfelder eingerichtet", str(it.stats.get("fences", 0)))
	var inv: Array = _me.get_meta("orig_items", [])
	var had := inv.has(OrigInteractive.WIRE_CUTTER)
	if not had:
		for s in _m.squad.members:
			if OrigInteractive.has_item(s, OrigInteractive.WIRE_CUTTER):
				had = true
		inv.append(OrigInteractive.WIRE_CUTTER)
		_me.set_meta("orig_items", inv)
	check(had, "arctic1: Drahtschere (59) im Trupp")
	var pc: PlayerController = _m.controller
	var tried := 0
	for k in it.controls:
		var fc = it.controls[k]
		if not (fc is OrigInteractive.OrigFence) or fc.cut:
			continue
		var mi := fc.frame as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var la := mi.get_aabb()
		var thin := Vector3.RIGHT if la.size.x < la.size.z else Vector3.BACK
		var nrm: Vector3 = (mi.global_basis * thin)
		nrm.y = 0
		nrm = nrm.normalized()
		var c: Vector3 = fc.global_position
		var a = _floor_at(c.x - nrm.x * 1.3, c.z - nrm.z * 1.3, c.y + 2.0)
		var b = _floor_at(c.x + nrm.x * 1.3, c.z + nrm.z * 1.3, c.y + 2.0)
		if a == null or b == null or absf(float(a.y) - fc.floor_y) > 0.4 or absf(float(b.y) - fc.floor_y) > 0.4:
			continue
		if not is_nan(_m.get("orig").water_level_at(a)):
			continue
		tried += 1
		_me.global_position = a + Vector3.UP * 0.2
		_me.velocity = Vector3.ZERO
		TestDoors.face(_me, nrm)
		await frames(10)
		var s0 := (_me.global_position - c).dot(nrm)
		await hold("move_forward", 1.2)
		var blocked := (_me.global_position - c).dot(nrm) < 0.0
		_me.global_position = a + Vector3.UP * 0.2
		_me.velocity = Vector3.ZERO
		TestDoors.face(_me, nrm)
		await frames(10)
		pc._update_interact_target()
		var tgt := String(pc.interact_target.name) if pc.interact_target else "-"
		if pc.interact_target != fc:
			if tried < 6:
				continue
		await tap("interact")
		var done := await _wait(func(): return fc.cut, 8.0)
		check(pc.interact_target == fc or done, "Zaun %s: Benutzen-Taste wählt das Zaunfeld" % k, "Ziel=%s" % tgt)
		check(blocked, "Zaun %s: vor dem Schneiden versperrt" % k, "s0=%.2f" % s0)
		check(done and int(fc.frame.get_meta("actor_state", 0)) == 1, "Zaun %s: mit Drahtschere zerschnitten (Zustand 1)" % k)
		await frames(5)
		await hold("move_forward", 1.6)
		var s1 := (_me.global_position - c).dot(nrm)
		check(s1 > 0.3, "Zaun %s: danach durchlaufbar (Vorwärtstaste)" % k, "Abstand %.2f" % s1)
		return
	check(false, "arctic1: kein prüfbares Zaunfeld gefunden", str(tried))


static func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Alle Türen per Benutzen-Taste (Standplatz wie test_normandie_doors)
func _doors() -> void:
	isolate_enemies([])
	for n in _m.find_children("*", "CharacterBody3D", true, false):
		if n is Soldier and n != _me:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			(n as Soldier).global_position = Vector3(-120, 40, -120)
	_me.set_meta("protect_until", 1e12)
	var it: OrigInteractive = _m.get("interactive")
	var only := String(Game.cli.get("doors", "")).to_upper().split(",", false)
	var pc: PlayerController = _m.controller
	for k in it.controls:
		var d = it.controls[k]
		if not (d is OrigInteractive.OrigDoor):
			continue
		if not only.is_empty() and not only.has(String(k)):
			continue
		if d.is_open:
			d.set_open(false)
			await _wait(func(): return d.state == 0, 6.0)
		var st: Array = TestDoors.stand_for(_m, d)
		var tgt := "-"
		# Standplatz vor der Tür; greift die Auswahl eine Nachbartür (enge Doppeltür), von der Gegenseite
		for cand in [[1.0, 1.35], [1.0, 0.8], [-1.0, 1.35], [-1.0, 0.8]]:
			var side: float = cand[0]
			var n: Vector3 = st[1] * side
			_me.global_position = Vector3(st[2].x, st[0].y, st[2].z) - n * float(cand[1])
			_me.velocity = Vector3.ZERO
			TestDoors.face(_me, n)
			await frames(6)
			pc._update_interact_target()
			tgt = String(pc.interact_target.name) if pc.interact_target else "-"
			if pc.interact_target == d:
				d.set_meta("b017_stand", [_me.global_position, n])
				break
		var was_locked: bool = d.locked
		if d.locked and d.key_item >= 0 and not d.lockpickable:
			# Schlüsseltür (Original): Schlüssel liegt in der Welt – hier direkt ins Originalinventar
			var inv: Array = _me.get_meta("orig_items", [])
			inv.append(d.key_item)
			_me.set_meta("orig_items", inv)
		await tap("interact")
		if d.locked and d._pick_left <= 0.0 and was_locked:
			check(false, "Tür %s: verschlossen, Benutzen ohne Wirkung" % k, "Schlüssel %d knackbar %s Ziel %s" % [d.key_item, d.lockpickable, tgt])
			continue
		if was_locked:
			await _wait(func(): return not d.locked, 12.0)
			await tap("interact")
		var opened := await _wait(func(): return d.state == 1 or d.amount >= minf(d.open_amount, 1.0) - 0.01, 8.0)
		if d.static_leaf and opened:
			# durch die geöffnete Tür laufen (Vorwärtstaste) und wieder zurück
			var c: Vector3 = st[2]
			var nrm := (Vector3(c.x, 0, c.z) - Vector3(_me.global_position.x, 0, _me.global_position.z)).normalized()
			TestDoors.face(_me, nrm)
			var s0 := (_me.global_position - c).dot(nrm)
			await hold("move_forward", 1.6)
			var s1 := (_me.global_position - c).dot(nrm)
			check(s0 < 0.0 and s1 > 0.4, "Tür %s: offen durchlaufbar (Vorwärtstaste)" % k, "Abstand %.2f -> %.2f" % [s0, s1])
			TestDoors.face(_me, -nrm)
			await hold("move_forward", 1.6)
			# Schließen von 1,35 m vor der Tür (außerhalb des Schwenkbereichs, innerhalb der Benutzen-Reichweite)
			_me.global_position = Vector3(c.x, _me.global_position.y, c.z) - nrm * 1.35
			if d.has_meta("b017_stand"):          # Standplatz, von dem die Auswahl diese Tür trifft (enge Doppeltür)
				_me.global_position = d.get_meta("b017_stand")[0]
				nrm = d.get_meta("b017_stand")[1]
			_me.velocity = Vector3.ZERO
			TestDoors.face(_me, nrm)
			await frames(4)
			pc._update_interact_target()
		await tap("interact")
		var closed := await _wait(func(): return d.state == 0, 8.0)
		if not closed:
			var obs: Array = d._overlaps(d._ignore).map(func(r):
				var o := instance_from_id(PhysicsServer3D.body_get_object_instance_id(r))
				return String(o.get_path()) if o is Node else str(r))
			print("DOORSTUCK %s Betrag %.2f Ziel %s Hindernisse %s" % [k, d.amount, pc.interact_target.name if pc.interact_target else "-", obs])
		check(opened and closed, "Tür %s: Benutzen-Taste öffnet und schließt" % k,
			"Ziel=%s Zustand=%d Betrag=%.2f verschlossen=%s Pos=%s Soldat=%s" % [tgt, d.state, d.amount, was_locked, st[2], _me.global_position])
