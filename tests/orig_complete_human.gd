extends RefCounted
## B-036: Löser-Modus „menschlich“ für test_orig_complete (--human=1, run_completability.ps1 -Human).
## Regeln: keine Positionen/Transformationen setzen, nichts teleportieren, keine Ziele/Signale/Zustände schalten.
## Gesteuert wird nur der aktive Soldat über dieselben Eingaben wie ein Spieler (Input-Aktionen move_*, Blickwinkel
## look_yaw/look_pitch = Maus, stance_stand = Leertaste/Klettern/Leiter, interact = Benutzen über
## PlayerController.interact_target, fire/aim/reload), Wege über das Navigationsnetz (NavigationServer3D-Pfad, Leiter-/
## Kletter-Links wie ein Spieler mit der Leertaste). Trupp per Befehl (order_follow), Soldatenwechsel per F1–F4
## (soldier_1…4). Gegner werden bekämpft (zielen + schießen). Teleports der Originalskripte (FRM_Teleport*/HUMAN_Teleport
## …) sind erlaubt, werden aber erkannt (Sprung > 4 m in einem Physikschritt) und im Bericht ausgewiesen.
## Abweichungen/Hilfen [E]: Trupp unverwundbar wie im Standardlöser (Gesundheit wird nachgefüllt, --god=0 schaltet ab);
## Zwischensequenzen werden wie mit Esc übersprungen; Durchsuchen von Leichen übernimmt alles (Interactable.interact
## direkt statt Ziehen im Inventarfenster).

var t           ## Test (test_orig_complete.gd)
var m: OrigMission
var rt: LsRuntime
var pc: PlayerController
var teleports: Array[String] = []
var blockers: Array[String] = []
var game_time := 0.0
var _last := {}
var _shots := 0
var _kills := 0
var _diag_t := 0.0


func run(test) -> bool:
	t = test
	m = t.m
	rt = t.rt
	pc = m.controller
	t.get_tree().physics_frame.connect(_on_physics_frame)
	var w := 0.0
	while not m.nav_ready and w < 240.0:
		await t.seconds(1.0)
		w += 1.0
	print("LOESER-M Navigationsnetz bereit nach %.0f s (nav_ready=%s)" % [w, m.nav_ready])
	await _skip_cutscene()
	_press("order_follow")
	if await _follow_guides():
		return true
	for rnd in 4:
		print("LOESER-M Runde %d, Spielzeit %.0f s, Ziele %s" % [rnd + 1, game_time, t._objective_state()])
		# B-036: aktives Kampfziel („Töten Sie …“) → Gegnerjagd vor den übrigen Auslösern
		if _kill_objective_active():
			print("LOESER-M Kampfziel aktiv – Gegnerjagd zuerst")
			if await _hunt_enemies():
				return true
		if await _visit_triggers():
			return true
		if await _use_all():
			return true
		if await _loot_all():
			return true
		if rnd >= 1 and await _hunt_enemies():
			return true
		if rnd >= 1 and await _visit_triggers():
			return true
		if await _idle(5.0):
			return true
	return t._done()


# --- Beobachtung ----------------------------------------------------------------------------------------------------

func _on_physics_frame() -> void:
	if not is_instance_valid(m):
		return
	game_time += t.get_physics_process_delta_time()
	for s in m.squad.members:
		if not is_instance_valid(s) or not s.alive:
			continue
		var p: Vector3 = s.global_position
		if _last.has(s) and s.vehicle == null:
			var d: float = (_last[s] as Vector3).distance_to(p)
			if d > 4.0:
				var line := "%s %.0f s: %s (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f) %.0f m%s" % [s.name, game_time,
					"aktiv" if s == pc.active else "Kamerad", _last[s].x, _last[s].y, _last[s].z, p.x, p.y, p.z, d,
					" in Zwischensequenz" if rt.in_cutscene else ""]
				teleports.append(line)
				print("LOESER-M SKRIPT-TELEPORT ", line)
		_last[s] = p


# --- Eingaben ---------------------------------------------------------------------------------------------------------

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "fire", "aim", "run"]:
		Input.action_release(a)


func _lead() -> Soldier:
	return pc.active if is_instance_valid(pc.active) and pc.active.alive else t._lead()


func _face(p: Vector3, pitch := true) -> void:
	var s := _lead()
	var d := p - s.eye_position()
	s.look_yaw = atan2(-d.x, -d.z)
	if pitch:
		s.look_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
	else:
		s.look_pitch = 0.0


func _step() -> bool:
	await t.get_tree().physics_frame
	if is_instance_valid(rt) and rt.in_cutscene:
		await _skip_cutscene()
	return t._done()


func _idle(sec: float) -> bool:
	_release_all()
	var el := 0.0
	while el < sec:
		if await _step():
			return true
		el += t.get_physics_process_delta_time()
		if await _fight_if_needed():
			return true
	return false


func _skip_cutscene() -> void:
	# wie Esc im Spiel (Sequenz überspringen); der Löser setzt dabei nichts selbst
	if is_instance_valid(rt) and rt.in_cutscene:
		rt.end_cutscene()
		await t.frames(3)


# --- Bewegung über das Navigationsnetz -----------------------------------------------------------------------------

func _map() -> RID:
	return _lead().get_world_3d().navigation_map


func _query(from: Vector3, to: Vector3) -> NavigationPathQueryResult3D:
	var q := NavigationPathQueryParameters3D.new()
	q.map = _map()
	q.start_position = from
	q.target_position = to
	q.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_OWNERS
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r


## Soldat steht nicht auf dem Navigationsnetz (nächster Netzpunkt > 0,8 m entfernt, z. B. auf einem Grenzkörper)
func _off_mesh(p: Vector3) -> bool:
	return NavigationServer3D.map_get_closest_point(_map(), p).distance_to(p) > 0.8


## Läuft zum Ziel. 0 = erreicht, 1 = nicht erreicht (Blocker), 2 = Mission beendet.
func go_to(target: Vector3, tol := 1.3, max_t := 240.0, label := "") -> int:
	var el := 0.0
	var path := PackedVector3Array()
	var owners := PackedInt64Array()
	var idx := 0
	var repath := 0.0
	var stuck_t := 0.0
	var stuck_n := 0
	var ref_pos := _lead().global_position
	var strafe := 0.0
	var strafe_dir := 1.0
	var door_t := 0.0
	var fight_t := 0.0
	var best := INF
	var best_goal := INF
	var wp_best := INF
	while el < max_t:
		if await _step():
			return 2
		var dt: float = t.get_physics_process_delta_time()
		el += dt
		var s := _lead()
		if s == null:
			return 1
		if s.vehicle != null:
			_press("interact")          # aussteigen
			continue
		var flat := Vector2(target.x - s.global_position.x, target.z - s.global_position.z)
		if flat.length() < tol and absf(target.y - s.global_position.y) < 2.6:
			_release_all()
			return 0
		best = minf(best, flat.length())
		_diag_t -= dt
		if _diag_t <= 0.0:
			_diag_t = 5.0
			_maybe_checkpoint_save()
			print("LOESER-M Weg %s: bei %s Ziel %s %.1f m, Pfad %d/%d, Eingabe %s, UI %s, aktiv %s, Absicht %s, Sequenz %s" % [label,
				_v(s.global_position), _v(target), flat.length(), idx, path.size(), pc.input_enabled, pc.ui_blocking(),
				s == pc.active, _v(s.move_input), rt.in_cutscene])
		if not pc.input_enabled:
			# Skript sperrt die Steuerung (Dialog/Sequenz) – wie ein Spieler warten
			_release_all()
			continue
		fight_t -= dt
		if fight_t <= 0.0:
			fight_t = 0.3
			if await _fight_if_needed():
				return 2
		if s.is_climbing():
			_release_all()
			continue
		repath -= dt
		if repath <= 0.0 or idx >= path.size():
			var r := _query(s.global_position, target)
			path = r.get_path()
			owners = r.get_path_owner_ids()
			# abseits des Netzes (z. B. auf einem Felsen): erst zum nächsten Netzpunkt laufen
			idx = 1 if path.size() > 1 and Vector2(path[0].x - s.global_position.x, path[0].z - s.global_position.z).length() < 0.8 else 0
			repath = 3.0
			wp_best = INF
		var next := target
		if idx < path.size():
			next = path[idx]
			var fd := Vector2(next.x - s.global_position.x, next.z - s.global_position.z).length()
			# Fortschritt zum aktuellen Wegpunkt (Pendeln zählt nicht als Fortschritt)
			# Wegpunkt waagerecht erreicht: auch wenn er tiefer liegt (Soldat steht auf einem Körper über dem Netz, z. B.
			# ARCTIC1 Grenzkörper BORDER/Border_15 4 m über dem Boden) – weiter zum nächsten Punkt = heruntersteigen
			var dy: float = next.y - s.global_position.y
			# B-036 a2: in mehrstöckigen Gebäuden (ARCTIC2 T1, Böden −1,7/−5,2/−8,7) liegt der Wegpunkt des unteren
			# Stockwerks waagerecht direkt unter dem Soldaten → nur abseits des Netzes großzügig, sonst ≤ 1,2 m tiefer
			var low := -8.0 if _off_mesh(s.global_position) else -1.2
			if fd < 0.6 and dy < 3.0 and dy > low:
				if await _maybe_link(path, owners, idx):
					return 2
				idx += 1
				wp_best = INF
				continue
		# Türen auf dem Weg wie ein Spieler mit der Benutzen-Taste öffnen
		door_t -= dt
		if door_t <= 0.0:
			door_t = 0.3
			if await _open_door_ahead(next):
				return 2
		var d := next - s.global_position
		# deutlich über dem Netz (auf einem Körper ohne Netz, z. B. BORDER-Oberkante): zur Zielseite hinabsteigen
		if s.global_position.y - next.y > 1.5 and _off_mesh(s.global_position):
			d = target - s.global_position
		d.y = 0.0
		if d.length() > 0.05:
			s.look_yaw = atan2(-d.x, -d.z)
			s.look_pitch = 0.0
		Input.action_press("move_forward")
		if strafe > 0.0:
			strafe -= dt
			Input.action_press("move_left" if strafe_dir < 0 else "move_right")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")
		# Feststecken: Leertaste (Klettern/Leiter), seitlich ausweichen, neu planen
		# Feststecken = Zielabstand seit 4 s nicht um 1 m kleiner (Pendeln zählt nicht als Fortschritt)
		stuck_t += dt
		if flat.length() < best_goal - 1.0:
			best_goal = flat.length()
			stuck_n = 0
			stuck_t = 0.0
		if stuck_t > 4.0:
			stuck_t = 0.0
			stuck_n += 1
			wp_best = INF
			if stuck_n == 1 or stuck_n % 4 == 0:
				_press("stance_stand")        # Leertaste: Klettern/Leiter/Hindernis
			elif stuck_n % 4 == 3 and idx + 1 < path.size():
				idx += 1                      # Wegpunkt überspringen
			else:
				strafe = 1.0
				strafe_dir = -strafe_dir
				repath = 0.0
			if stuck_n == 6:
				print("LOESER-M fest bei %s: Wegpunkt %d/%d %s, Besitzer %s" % [_v(s.global_position), idx, path.size(),
					_v(next), instance_from_id(owners[idx]) if idx < owners.size() and owners[idx] != 0 else "-"])
			if stuck_n >= 10:
				_release_all()
				_blocker("%s festgefahren bei %s (Ziel %s, %.0f m)" % [label, _v(s.global_position), _v(target), flat.length()])
				return 1
	_release_all()
	if label.begins_with("Führer"):
		return 1          # Teilstrecke hinter dem Führer (30 s je Abschnitt), kein Blocker
	_blocker("%s Zeitlimit %.0f s bei %s (Ziel %s, bester Abstand %.1f m)" % [label, max_t, _v(_lead().global_position), _v(target), best])
	return 1


func _v(p: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]


func _blocker(txt: String) -> void:
	print("LOESER-M BLOCKER ", txt)
	if blockers.size() < 40:
		blockers.append(txt)


## Navigations-Link am Wegpunkt: Leiter (Leertaste an der Leiter) oder Kletterstelle (Leertaste vor der Wand)
func _maybe_link(path: PackedVector3Array, owners: PackedInt64Array, idx: int) -> bool:
	if idx + 1 >= path.size() or idx >= owners.size():
		return false
	var o: Object = instance_from_id(owners[idx]) if owners[idx] != 0 else null
	if not (o is NavigationLink3D):
		return false
	var s := _lead()
	var to: Vector3 = path[idx + 1]
	if o.has_meta("ladder") or (o.has_meta("climb") and to.y - s.global_position.y > Soldier.STEP_HEIGHT):
		_release_all()
		_face(to, false)
		for k in 4:
			_press("stance_stand")
			for f in 20:
				if await _step():
					return true
				if s.is_climbing():
					break
			if s.is_climbing():
				break
			# an die Wand/Leiter herantreten
			Input.action_press("move_forward")
			for f in 10:
				if await _step():
					return true
			Input.action_release("move_forward")
		var w := 0.0
		while s.is_climbing() and w < 20.0:
			if await _step():
				return true
			w += t.get_physics_process_delta_time()
	return false


func _open_door_ahead(next: Vector3) -> bool:
	var s := _lead()
	var dir := next - s.global_position
	dir.y = 0.0
	dir = dir.normalized()
	for n in t.get_tree().get_nodes_in_group("interactables"):
		if not (n is OrigInteractive.OrigDoor) or n.is_open:
			continue
		var to: Vector3 = (n as Node3D).global_position - s.global_position
		if to.y < -2.5 or to.y > 2.5:
			continue      # Tür in anderem Stockwerk (OrigDoor.can_interact bietet sie nicht an)
		to.y = 0.0
		if to.length() < 2.6 and (to.length() < 0.8 or to.normalized().dot(dir) > 0.3):
			print("LOESER-M Tür %s öffnen" % n.name)
			# Abstand nehmen: der Flügel hält am davorstehenden Soldaten an (OrigDoor) – wie ein Spieler zurücktreten
			_release_all()
			_face((n as Node3D).global_position, false)
			if to.length() < 1.3:
				Input.action_press("move_back")
				for f in 20:
					if await _step():
						return true
				Input.action_release("move_back")
			if await use(n, false):
				return true
			for f in 40:
				if await _step():
					return true
			if not n.is_open:
				print("LOESER-M Tür %s bleibt zu (Ziel angeboten: %s)" % [n.name, pc.interact_target.name if pc.interact_target else "-"])
			return false
	return false


# --- Benutzen ------------------------------------------------------------------------------------------------------

## Hingehen, ansehen, Benutzen-Taste – nur wenn der PlayerController genau dieses Ziel anbietet. true = Mission beendet.
func use(it: Interactable, walk := true) -> bool:
	if not is_instance_valid(it):
		return false
	if walk:
		var r: int = await go_to(it.global_position, 1.0, 240.0, "Benutzen %s" % it.name)
		if r == 2:
			return true
	_release_all()
	for k in 6:
		if not is_instance_valid(it):
			return false
		_face(it.global_position)
		for f in 3:
			if await _step():
				return true
		if pc.interact_target == it:
			_press("interact")
			for f in 4:
				if await _step():
					return true
			return false
		# näher heran
		_face(it.global_position, false)
		Input.action_press("move_forward")
		for f in 8:
			if await _step():
				return true
		Input.action_release("move_forward")
	if walk:
		_blocker("Benutzen nicht angeboten: %s bei %s (Abstand %.1f m, can_interact=%s)" % [it.name, _v(it.global_position),
			_lead().global_position.distance_to(it.global_position), it.can_interact(_lead())])
	return false


# --- Kampf ---------------------------------------------------------------------------------------------------------

var _prot: Dictionary = {}


func _hostile(e: Soldier) -> bool:
	if not is_instance_valid(e) or not e.alive or e.has_meta("hands_up") or e.team != Soldier.TEAM_AXIS:
		return false
	if _prot.is_empty():
		_prot = t._protected_names()
	return not _prot.has(String(e.name).to_lower())


func _visible(e: Soldier) -> bool:
	var s := _lead()
	var from := s.eye_position()
	var to := e.eye_position() - Vector3(0, 0.35, 0)
	if from.distance_to(to) > 90.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array[RID] = []
	for x in m.squad.members:
		if is_instance_valid(x):
			ex.append(x.get_rid())
	q.exclude = ex
	var hit := s.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == e or (hit["position"] as Vector3).distance_to(to) < 0.9


func _visible_enemy() -> Soldier:
	var best: Soldier = null
	var bd := INF
	for e in m.enemies:
		if _hostile(e):
			var d: float = e.global_position.distance_to(_lead().global_position)
			if d < bd and d < 90.0 and _visible(e):
				bd = d
				best = e
	return best


## Sichtbaren Gegner bekämpfen (zielen, Feuerstöße, nachladen). true = Mission beendet.
func _fight_if_needed() -> bool:
	var e := _visible_enemy()
	if e == null:
		return false
	_release_all()
	var el := 0.0
	var unseen := 0.0
	var burst := 0.0
	while el < 25.0 and is_instance_valid(e) and e.alive and not e.has_meta("hands_up"):
		var s := _lead()
		if s.vehicle != null:
			break
		_face(e.eye_position() - Vector3(0, 0.45, 0))
		Input.action_press("aim")
		var w := s.current_weapon()
		if w and w.in_mag <= 0:
			Input.action_release("fire")
			_press("reload")
		else:
			burst += t.get_physics_process_delta_time()
			if fmod(burst, 0.5) < 0.15:
				Input.action_press("fire")
			else:
				Input.action_release("fire")
		if await _step():
			_release_all()
			return true
		el += t.get_physics_process_delta_time()
		if not _visible(e):
			unseen += t.get_physics_process_delta_time()
			if unseen > 2.0:
				break
		else:
			unseen = 0.0
	_release_all()
	if is_instance_valid(e) and not e.alive:
		_kills += 1
	return false


## Gegner aufsuchen (nächste zuerst) und bekämpfen
var _saved_after := {}

## B-036: Zwischenspielstand „b036_<mission>_ziel<n>“, sobald Pflichtziel n erfüllt ist (für --from_save).
## Nur außerhalb von Zwischensequenzen und bei freier Spielereingabe; nicht im Lauf ab Spielstand.
func _maybe_checkpoint_save() -> void:
	if Game.cli.has("from_save") or not pc.input_enabled:
		return
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o and o.state == Objective.State.DONE and not o.optional and not _saved_after.has(idx):
			_saved_after[idx] = true
			var slot := "b036_%s_ziel%d" % [String(Game.current_mission_id), idx]
			print("LOESER-M Zwischenstand gespeichert: %s = %s (Spielzeit %.0f s)" % [slot, Game.save_game(slot), game_time])


func _kill_objective_active() -> bool:
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o and o.state == Objective.State.ACTIVE and not o.optional:
			var s := o.text.to_lower()
			if s.contains("töten") or s.contains("vernichten") or s.contains("eliminieren") or s.contains("kill"):
				return true
	return false


func _hunt_enemies() -> bool:
	for k in 60:
		var best: Soldier = null
		var bd := INF
		for e in m.enemies:
			if _hostile(e) and e.vehicle == null:
				var d: float = e.global_position.distance_to(_lead().global_position)
				if d < bd:
					bd = d
					best = e
		if best == null:
			return false
		print("LOESER-M Jagd auf %s (%.0f m)" % [best.name, bd])
		var r: int = await go_to(best.global_position, 6.0, 150.0, "Gegner %s" % best.name)
		if r == 2:
			return true
		if await _fight_if_needed():
			return true
		if is_instance_valid(best) and best.alive and r == 1:
			_prot[String(best.name).to_lower()] = true      # unerreichbar: nicht erneut anlaufen
	return false


# --- Lösungsschritte -----------------------------------------------------------------------------------------------

func _follow_guides() -> bool:
	var guides: Array = []
	var waiting := {}
	for vm in rt.vms:
		var s := vm.me as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS and not m.squad.members.has(s):
			guides.append(s)
			var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
			if f and f.get_as_text().to_lower().contains("human_setwaitforplayer"):
				waiting[s] = true
	for g in guides:
		# Tod eines Führers lässt Ziele scheitern (ARCTIC1 Rebel OnDeath → SendSignal(OBJ,9) → Ziel 1 = 3): Ursache festhalten
		(g as Soldier).died.connect(func(x): _blocker("Führer %s gestorben bei %.0f s durch %s bei %s" % [x.name, game_time,
			x.last_attacker.name if is_instance_valid(x.last_attacker) else "Skript/Explosion/Fall", _v(x.global_position)]))
	guides.sort_custom(func(a, b): return a.global_position.distance_to(t._start_pos) < b.global_position.distance_to(t._start_pos))
	var budget := 150.0
	var first := true
	for g in guides:
		var cap := 600.0 if waiting.has(g) else minf(60.0, budget)
		# Führer mit HUMAN_SetWaitForPlayer begrüßen erst (Dialog, ARCTIC1 Rebel ~40 s) und laufen dann los
		var patience := (60.0 if waiting.has(g) else 15.0) if first else (30.0 if waiting.has(g) else 5.0)
		first = false
		var total := 0.0
		var still := 0.0
		var moved := false
		var last: Vector3 = g.global_position
		var t0 := game_time
		# erst zum Führer hingehen (ansprechen = Nähe), dann folgen
		if _lead().global_position.distance_to(g.global_position) > 4.0:
			var ra: int = await go_to(g.global_position, 2.5, 420.0, "Weg zum Führer %s" % g.name)
			if ra == 2:
				return true
		t0 = game_time
		last = g.global_position
		var tick := game_time
		while total < cap and is_instance_valid(g) and g.alive:
			var area: Node = m.find_child("MissionArea", true, false)
			if area and area.has_method("flags_at") and int(area.flags_at(g.global_position + Vector3(0, 0.3, 0))) != 0:
				print("LOESER-M Führer %s: Grenze des Einsatzgebiets" % g.name)
				break
			if _lead().global_position.distance_to(g.global_position) > 3.0:
				var r: int = await go_to(g.global_position, 2.5, 30.0, "Führer %s" % g.name)
				if r == 2:
					return true
			elif await _idle(1.0):
				return true
			total = game_time - t0
			if g.global_position.distance_to(last) > 0.5:
				still = 0.0
				moved = true
			else:
				still += game_time - tick
			tick = game_time
			last = g.global_position
			if still > (25.0 if moved else patience):
				break
		if not waiting.has(g):
			budget -= total
		print("LOESER-M Führer %s: %.0f s begleitet, bewegt %s" % [g.name, total, moved])
	return false


func _visit_triggers() -> bool:
	# wie ein Spieler: immer den nächstgelegenen noch nicht besuchten Punkt ab der aktuellen Lage
	var rest: Array = t._trigger_points().duplicate()
	while not rest.is_empty():
		var here := _lead().global_position
		rest = rest.filter(func(n): return is_instance_valid(n))
		if rest.is_empty():
			break
		rest.sort_custom(func(a, b): return here.distance_to(a.global_position) < here.distance_to(b.global_position))
		var p: Node3D = rest.pop_front()
		if not _trigger_matters(p):
			continue
		var area := m.find_child("MissionArea", true, false)
		if area and int(area.flags_at((p as Node3D).global_position + Vector3(0, 0.3, 0))) != 0:
			continue
		print("LOESER-M Auslöser %s" % p.name)
		var r: int = await go_to((p as Node3D).global_position, 1.5, 300.0, "Auslöser %s" % p.name)
		if r == 2:
			return true
		if await _idle(2.0):
			return true
	return false


## Auslöser, deren Skript nur Effekte steuert (ARCTIC1 dummy_efekt*: Partikel/Klang bei Spielernähe), haben keinen
## Einfluss auf Ziele/Ablauf – ein Spieler muss sie nicht gezielt anlaufen. Relevant = Skript sendet Signale, setzt
## Ziele, startet Sequenzen oder speichert Werte.
func _trigger_matters(p: Node) -> bool:
	var vm = rt.vm_for(p)
	if vm == null:
		return true
	var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
	if f == null:
		return true
	var src := f.get_as_text().to_lower()
	# Führer/NPCs werden über _follow_guides begleitet, nicht als Auslöser angelaufen; Skripte, die bei Spielernähe ein
	# Ziel scheitern lassen (ARCTIC1 r_arc1a_rebel_dabing: „Spieler geht mit Albert zurück“ → SendSignal(OBJ,14) = Ziel 1
	# verfehlt), meidet ein Spieler ebenfalls
	if p is Soldier or RegEx.create_from_string("(?i)sendsignal\\s*\\([^)]*\\)\\s*;\\s*//[^\\n]*fail").search(src) != null:
		print("LOESER-M Auslöser %s ausgelassen (Führer bzw. Fehlschlag-Auslöser, %s)" % [p.name, vm.name])
		return false
	for k in ["sendsignal", "setobjectivestatus", "csc_", "savegamevalue", "mission_", "human_", "frm_teleport"]:
		if src.contains(k):
			return true
	print("LOESER-M Auslöser %s nur Effekt (%s) – ausgelassen" % [p.name, vm.name])
	return false


func _use_all() -> bool:
	var items: Array = []
	for n in t.get_tree().get_nodes_in_group("interactables"):
		if n is OrigInteractive.OrigWorldItem or n is OrigInteractive.OrigPlace or n is OrigInteractive.OrigExplosive \
				or n is OrigInteractive.OrigCrate or (n is OrigInteractive.OrigSwitch and not t._is_alarm_switch(n)):
			items.append(n)
	var expl := items.filter(func(x): return x is OrigInteractive.OrigExplosive)
	items = items.filter(func(x): return not (x is OrigInteractive.OrigExplosive)) + expl
	for n in items:
		if not is_instance_valid(n) or not n.is_inside_tree() or not (n as Interactable).can_interact(_lead()):
			continue
		print("LOESER-M Benutzen %s" % n.name)
		if await use(n):
			return true
		if n is OrigInteractive.OrigExplosive:
			var ex := n as OrigInteractive.OrigExplosive
			# Anbringen 3 s stillstehen, dann Abstand halten und auf den Zünder warten
			if await _idle(3.6):
				return true
			if ex.state == 1:
				print("LOESER-M Ladung %s angebracht (Zünder %s, %.0f s)" % [ex.name, ex.has_timer, ex.countdown])
				var away: Vector3 = t._start_pos
				var r: int = await go_to(away, 3.0, minf(maxf(ex.countdown - 2.0, 10.0), 120.0), "Abstand Ladung")
				if r == 2:
					return true
		elif await _idle(4.0 if n is OrigInteractive.OrigSwitch else 1.0):
			return true
	return false


func _loot_all() -> bool:
	for n in t.get_tree().get_nodes_in_group("interactables"):
		if not (n is Pickups.Loot) or not is_instance_valid(n) or not (n as Interactable).can_interact(_lead()):
			continue
		if (n as Node3D).global_position.distance_to(_lead().global_position) > 120.0:
			continue
		var r: int = await go_to((n as Node3D).global_position, 1.6, 90.0, "Leiche")
		if r == 2:
			return true
		if r == 0 and (n as Interactable).can_interact(_lead()):
			(n as Interactable).interact(_lead())     # „alles nehmen“ statt Ziehen im Inventarfenster [E]
	for n in t.get_tree().get_nodes_in_group("interactables"):
		if n is EnemyBrain.CaptureAction and (n as Interactable).can_interact(_lead()):
			if await use(n):
				return true
	return false


func summary() -> String:
	return "menschlich: Spielzeit %.0f s, Skript-Teleports %d, Blocker %d, Gegner bekämpft %d" % [game_time, teleports.size(),
		blockers.size(), _kills]
