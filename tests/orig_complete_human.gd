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
		_door_fail.clear()      # neue Runde: evtl. inzwischen Schlüssel gefunden
		_obj_visited.clear()
		if await _go_objective_targets():
			return true
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
	# B-036 a2: Kantenmitten statt Fadenziehen – bei U-Treppen (ARCTIC2 T1) überdecken sich die Läufe in der Draufsicht,
	# das Fadenziehen lieferte dann einen Eckpunkt 3 m senkrecht unter dem Soldaten (Treppe wurde nie begangen)
	q.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r


var _obj_targets_said := false
var _hunt_target: Node = null   # Zielperson in der Jagd: nur auf sie schießen
var _obj_visited := {}      # "Ziel|Frame" → schon angelaufen (je Runde)
var _obj_targets := {}      # Zielindex → [Skriptframes], deren Skript das Ziel per _PlayerInRange erfüllt

## Zielorte aus den Originalskripten wie die Zielmarker (ObjectiveMarkers.script_objective_targets): Skriptframe, dessen
## Whenever(_PlayerInRange…) bzw. Zwischensequenz → OnCutsceneDone das Ziel auf erfüllt setzt.
func _scan_objective_targets() -> void:
	if not _obj_targets.is_empty() or rt == null or rt.orig == null:
		return
	var sdir: String = rt.orig.mission_dir + "/scripts"
	var srcs := {}
	for vm in rt.vms:
		if vm.me == null or vm.name == "" or not is_instance_valid(vm.me):
			continue
		var f := FileAccess.open(sdir + "/" + vm.name, FileAccess.READ)
		if f == null:
			continue
		srcs[vm] = f.get_buffer(f.get_length()).get_string_from_ascii()
	var sig_map := {}
	for vm in srcs:
		if vm.me is Soldier:
			continue
		for idx in ObjectiveMarkers.script_objective_targets(srcs[vm]):
			if not _obj_targets.has(idx):
				_obj_targets[idx] = []
			_obj_targets[idx].append(vm.me)
		var sm := ObjectiveMarkers.signal_objectives(srcs[vm])
		if not sm.is_empty():
			sig_map[String(vm.me.name).to_lower()] = sm
	# Personen, deren Skript dem Zielskript das Erfolgssignal schickt (a4 r_arc3_marine_officer_1.scr: OnDeath →
	# SendSignal(OBJ, 12) → „Whenever HOLD (_SignalReceived(12))“ → SetObjectiveStatus(4, 1) = U-Boot taucht nicht)
	for vm in srcs:
		if not (vm.me is Soldier):
			continue
		for pair in ObjectiveMarkers.signal_senders(srcs[vm]):
			var sm: Dictionary = sig_map.get(String(pair[0]).to_lower(), {})
			if sm.has(int(pair[1])):
				var idx: int = sm[int(pair[1])]
				if not _obj_targets.has(idx):
					_obj_targets[idx] = []
				if not _obj_targets[idx].has(vm.me):
					_obj_targets[idx].append(vm.me)


## Aktive Pflichtziele mit Skript-Zielort ansteuern (a2 Ziel 4 „Kehren Sie zur Oberfläche zurück“: nach dem Anbringen
## laufen 300-s-Zünder, r_arc1b_objective5.scr tötet den Spieler, der dann noch unten ist – wie ein Spieler sofort raus).
## true = Mission beendet.
func _go_objective_targets() -> bool:
	_scan_objective_targets()
	if not _obj_targets_said:
		_obj_targets_said = true
		for k in _obj_targets:
			print("LOESER-M Zielorte Ziel %s: %s" % [k, ", ".join(_obj_targets[k].map(func(x): return String(x.name)))])
	# feindliche Zielpersonen zuerst (sie laufen weg bzw. lösen ein Scheitern aus), dann Zielorte
	var order: Array = m.orig_objectives.keys()
	order.sort_custom(func(a, b):
		var ha: bool = _obj_targets.has(int(a)) and _obj_targets[int(a)].any(func(x): return is_instance_valid(x) and x is Soldier and _hostile(x))
		var hb: bool = _obj_targets.has(int(b)) and _obj_targets[int(b)].any(func(x): return is_instance_valid(x) and x is Soldier and _hostile(x))
		return ha and not hb)
	for idx in order:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o == null or o.optional or not _obj_targets.has(int(idx)):
			continue
		if o.state == Objective.State.DONE or o.state == Objective.State.FAILED:
			continue
		for fr in _obj_targets[int(idx)]:
			if not is_instance_valid(fr):
				continue
			# noch nicht aktive Ziele nur für feindliche Zielpersonen vorziehen (a4: Offizier läuft schon los, bevor
			# Ziel 4 freigeschaltet ist)
			if o.state != Objective.State.ACTIVE and not (fr is Soldier and _hostile(fr)):
				continue
			print("LOESER-M Zielort Ziel %s: %s" % [idx, fr.name])
			if fr is Soldier and _hostile(fr):
				# feindliche Zielperson (Erfolg bei ihrem Tod): heranlaufen und bekämpfen, bis sie fällt (max. 240 s)
				var tt := 0.0
				_hunt_target = fr
				# a4 Lauf 7: Marine_Officer_1 startet bei _PlayerInRange(30) zum U-Boot (→ Ziel 4 verfehlt) – also Trupp
				# halten lassen und aus > 30 m schießen, Abstand schrittweise 45 → 33 m verkleinern, solange er nicht sichtbar ist
				_press("order_hold")
				var stand_off := 45.0
				while tt < 240.0 and is_instance_valid(fr) and (fr as Soldier).alive:
					var t0 := game_time
					var r2: int = await go_to((fr as Node3D).global_position, stand_off, 60.0, "Zielperson %s" % fr.name)
					if _visible(fr):
						for k in 3:
							if await _fight_if_needed():
								return true
					elif stand_off > 33.0:
						stand_off -= 4.0
					if r2 == 2:
						return true
					if await _fight_if_needed():
						return true
					tt += maxf(game_time - t0, 1.0)
				_hunt_target = null
				continue
			var vkey := "%s|%s" % [idx, fr.get_instance_id()]
			if _obj_visited.has(vkey):
				continue          # Ort schon besucht (je Runde einmal; wird zu Rundenbeginn zurückgesetzt)
			_obj_visited[vkey] = true
			if await go_to((fr as Node3D).global_position, 2.5, 300.0, "Zielort %s" % fr.name) == 2:
				return true
	return false


var _area: Node = null      # MissionArea (Einsatzgebietsgrenze, src/orig/mission_area.gd)
var _fight_time := {}       # Gegner-ID → Kampfsekunden ohne Erfolg
var _no_ammo_said := false
var _door_fail := {}        # Türname → Fehlversuche (je Runde zurückgesetzt)
var _ramps: Array = []
var _ramp_uses := {}        # Rampenindex → Benutzungen im aktuellen go_to (Wiederholungsgrenze)      # [[a: Vector3, b: Vector3], …] Enden der Treppenrampen (Weltlage, auf der Rampe gemessen)

## Treppenrampen der Karte (Frames „*schod*“ mit Kollisionskörper, auch versteckte Ersatzrampen): je Rampe die
## beiden Enden der Längsachse, Höhe per Strahl auf den Körper. Das ist, was ein Spieler sieht: „da ist die Treppe“.
func _collect_ramps() -> void:
	_ramps.clear()
	var sp := _lead().get_world_3d().direct_space_state
	for n in m.find_children("*schod*", "Node3D", true, false):
		var bodies := n.find_children("*", "CollisionObject3D", true, false)
		if bodies.is_empty():
			continue
		var aabb := AABB()
		for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
			var b: AABB = mi.global_transform * mi.get_aabb()
			aabb = b if aabb.size == Vector3.ZERO else aabb.merge(b)
		if aabb.size.y < 0.8 or aabb.size.y > 4.0:
			continue
		var c := aabb.get_center()
		var along_x := aabb.size.x > aabb.size.z
		var half := (aabb.size.x if along_x else aabb.size.z) * 0.5 - 0.35
		var ends: Array = []
		for sgn in [-1.0, 1.0]:
			var p := c + (Vector3(sgn * half, 0, 0) if along_x else Vector3(0, 0, sgn * half))
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, aabb.end.y + 0.5, p.z), Vector3(p.x, aabb.position.y - 0.5, p.z))
			var h := sp.intersect_ray(q)
			ends.append(h.position if h else Vector3(p.x, aabb.get_center().y, p.z))
		_ramps.append(ends)
	print("LOESER-M Treppenrampen: %d" % _ramps.size())


## Treppe nehmen: Rampe, deren eines Ende auf Soldatenhöhe liegt (≤ 0,7 m, ≤ 6 m waagerecht) und deren anderes Ende
## näher an der Zielhöhe ist → erst zum nahen Ende, dann zum fernen Ende laufen. Wiederholt, bis keine passt.
## 0 = fertig, 2 = Mission beendet.
func _take_stairs(target: Vector3, max_t: float) -> int:
	if _ramps.is_empty():
		_collect_ramps()
	var s := _lead()
	var el := 0.0
	var used := {}
	while el < max_t and absf(target.y - s.global_position.y) > 1.2:
		var pick := -1
		var near := Vector3()
		var far := Vector3()
		var best := INF
		for i in _ramps.size():
			if used.has(i) or int(_ramp_uses.get(i, 0)) >= 2:
				continue
			for j in 2:
				var a: Vector3 = _ramps[i][j]
				var b: Vector3 = _ramps[i][1 - j]
				var fl := Vector2(a.x - s.global_position.x, a.z - s.global_position.z).length()
				if absf(a.y - s.global_position.y) > 0.7 or fl > 6.0:
					continue
				if absf(b.y - target.y) >= absf(a.y - target.y) - 0.5:
					continue
				if fl < best:
					best = fl
					pick = i
					near = a
					far = b
		if pick < 0:
			break
		used[pick] = true
		_ramp_uses[pick] = int(_ramp_uses.get(pick, 0)) + 1
		var dy_before: float = absf(target.y - s.global_position.y)
		print("LOESER-M Treppe %s → %s" % [_v(near), _v(far)])
		# Laufgasse: Rampenmitte, sonst seitlich versetzt (a2 xT1_schod_06 aufwärts: Mitte x 24,6 blockiert am Geländer,
		# Sonde: nur die Westhälfte x 23–24 führt hinauf) – bis zur ersten Gasse mit Höhengewinn
		var axis := (far - near)
		axis.y = 0.0
		var side := Vector3(-axis.z, 0, axis.x).normalized()
		# Gassen nach freier Sicht entlang der Rampe ordnen (Strahl 0,9 m über der Rampe vom nahen zum fernen Ende): die
		# Scherentreppe T1 hat innen eine schräge Mittelwand – die freie Gasse zuerst, sonst verstreicht der 150-s-Zünder
		# (r_arc1b_bum*.scr: 300 × 500 ms) mit Fehlversuchen
		var offs: Array = [0.0, -0.8, 0.8, -1.2, 1.2]
		var free := {}
		var sp := s.get_world_3d().direct_space_state
		for o in offs:
			var q := PhysicsRayQueryParameters3D.create(near + side * o + Vector3.UP * 0.9, far + side * o + Vector3.UP * 0.9)
			q.exclude = [s.get_rid()]
			var hh := sp.intersect_ray(q)
			free[o] = (near + side * o).distance_to(hh.position) if hh else 99.0
		offs.sort_custom(func(x, y): return free[x] > free[y])
		for off in offs:
			var h0: float = absf(target.y - s.global_position.y)
			if await _walk_ramp(near + side * off, far + side * off, target) == 2:
				return 2
			if absf(target.y - s.global_position.y) <= h0 - 0.5:
				break
			print("LOESER-M Treppe: Gasse %.1f m ohne Höhengewinn" % off)
		# Richtungsprüfung: hat der Lauf die Höhe zum Ziel nicht verringert, Rampe für diesen Weg sperren
		if absf(target.y - s.global_position.y) > dy_before - 0.5:
			_ramp_uses[pick] = 99
			print("LOESER-M Treppe ohne Höhengewinn – für diesen Weg gesperrt")
	return 0


## Eine Rampe in einer Gasse ablaufen: zum nahen Ende, zum fernen Ende, 0,8 m darüber hinaus. 2 = Mission beendet.
func _walk_ramp(near: Vector3, far: Vector3, _target: Vector3) -> int:
	var s := _lead()
	if true:
		# erst 1 m vor dem Rampenfuß in der Gasse ausrichten, dann gerade hinauf/hinab (Sonde: gerade Gassen x 25,0–25,8
		# führen an xT1_schod_06 ohne Leertaste hinauf; schräg vom Absatz an die Innenwand gelaufen blieb man hängen)
		var ax := far - near
		ax.y = 0.0
		var pre := near - ax.normalized() * 1.0
		for goal in [pre, near, far, far + (far - near).normalized() * 0.8]:
			var tt := 0.0
			var dt_door := 0.0
			while tt < 8.0:
				dt_door -= t.get_physics_process_delta_time()
				if dt_door <= 0.0:
					dt_door = 0.5
					if await _open_door_ahead(goal):      # Tür am Treppenkopf (ARCTIC2 m_dv_stOP vor dem Kellerlauf)
						return 2
				var d: Vector3 = goal - s.global_position
				d.y = 0.0
				if d.length() < 0.35:
					break
				s.look_yaw = atan2(-d.x, -d.z)
				s.look_pitch = 0.0
				Input.action_press("move_forward")
				if await _step():
					return 2
				tt += t.get_physics_process_delta_time()
			_release_all()
	return 0


## Aus dem Wasser: Ufer-/Netzpunkte nahe der Wasserhöhe (≤ 1,5 m darüber) ringsum suchen (5–80 m, alle 15°), zum
## nächsten schwimmen (Blick waagerecht + Vorwärts, an der Kante Leertaste). 2 = Mission beendet.
func _escape_water() -> int:
	var s := _lead()
	var wl: float = s.water_level()
	if is_nan(wl):
		wl = s.global_position.y
	var best := Vector3.INF
	var bd := INF
	for r in [5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 60.0, 80.0]:
		for k in 24:
			var a := TAU * k / 24.0
			var p := s.global_position + Vector3(sin(a) * r, 0, cos(a) * r)
			p.y = wl
			var cp := NavigationServer3D.map_get_closest_point(_map(), p)
			if cp.y - wl > 1.5 or cp.y - wl < -0.5 or Vector2(cp.x - p.x, cp.z - p.z).length() > 3.0:
				continue
			var d := Vector2(cp.x - s.global_position.x, cp.z - s.global_position.z).length()
			if d < bd:
				bd = d
				best = cp
		if bd < INF:
			break
	if bd == INF:
		print("LOESER-M im Wasser: kein Ufer gefunden")
		return await _explore_toward(s.global_position + Vector3(0, 5, 0), 20.0)
	print("LOESER-M im Wasser bei %s → Ufer %s (%.0f m)" % [_v(s.global_position), _v(best), bd])
	var tt := 0.0
	var prog_t := 0.0
	var prog_best := INF
	var detour := 0.0
	var detour_dir := 1.0
	while tt < 120.0 and (s.swimming or Vector2(best.x - s.global_position.x, best.z - s.global_position.z).length() > 1.0):
		var d := best - s.global_position
		d.y = 0.0
		if d.length() < 0.6:
			break
		# a3 Lauf 2: hing 15 min unter dem Steg (Pfeiler) – ohne Fortschritt 3 s lang seitlich ausweichen (±60°, 2 s)
		if d.length() < prog_best - 0.5:
			prog_best = d.length()
			prog_t = 0.0
		prog_t += t.get_physics_process_delta_time()
		if prog_t > 3.0:
			prog_t = 0.0
			detour = 2.0
			detour_dir = -detour_dir
		var yaw := atan2(-d.x, -d.z)
		if detour > 0.0:
			detour -= t.get_physics_process_delta_time()
			yaw += detour_dir * PI / 3.0
		s.look_yaw = yaw
		s.look_pitch = 0.0
		Input.action_press("move_forward")
		if fmod(tt, 1.0) < t.get_physics_process_delta_time():
			_press("stance_stand")
		if await _step():
			return 2
		tt += t.get_physics_process_delta_time()
	_release_all()
	return 0


## Erkunden ohne Netz: 16 Richtungen je 1,5 s laufen; bringt eine Richtung das Ziel (3D) um ≥ 0,5 m näher, von dort
## weitermachen, sonst die nächste Richtung. Nur Spielereingaben (Blick + Vorwärts, Leertaste an Hindernissen).
## 0 = fertig/abgebrochen, 2 = Mission beendet.
func _explore_toward(target: Vector3, max_t: float) -> int:
	var s := _lead()
	var el := 0.0
	var best: float = (target - s.global_position).length()
	var k := 0
	var fails := 0
	print("LOESER-M Erkunden ab %s Richtung %s (Netz ohne Verbindung)" % [_v(s.global_position), _v(target)])
	while el < max_t and fails < 32:
		var to := target - s.global_position
		var base := atan2(-to.x, -to.z)
		var step := (k % 16 + 1) / 2          # 0, 1, 1, 2, 2 … 8 → ±180° in Schritten von 22,5°
		var yaw := base + float(step) * TAU / 16.0 * (1.0 if k % 2 == 1 else -1.0)
		k += 1
		s.look_yaw = yaw
		s.look_pitch = 0.0
		Input.action_press("move_forward")
		var tt := 0.0
		var last := s.global_position
		var dur := 0.7 if fails < 16 else 1.6      # erst kurze Schritte (Treppenabsatz), dann lange
		while tt < dur:
			if await _step():
				return 2
			var dt: float = t.get_physics_process_delta_time()
			tt += dt
			el += dt
			if s.global_position.distance_to(last) < 0.02 and tt > 0.5:
				_press("stance_stand")
			last = s.global_position
		_release_all()
		var d: float = (target - s.global_position).length()
		if d < best - 0.5:
			best = d
			fails = 0
			k = 0
			if absf(target.y - s.global_position.y) < 1.2 or Vector2(to.x, to.z).length() < 1.0:
				break
		else:
			fails += 1
	print("LOESER-M Erkunden Ende bei %s (Abstand %.1f m)" % [_v(s.global_position), best])
	return 0


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
	var stair_calls := 0
	var climb_t := 0.0
	_ramp_uses.clear()
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
		# großer Abstand (Zielperson aus der Ferne, a4 Offizier 4 m höher auf dem Boot): Höhe egal
		if flat.length() < tol and (tol >= 10.0 or absf(target.y - s.global_position.y) < 2.6):
			_release_all()
			return 0
		best = minf(best, flat.length())
		# B-036 a3: ins Wasser gefallen (Steg dummy_TheEnd2 → Meer, Boden „dno“ −12,9) – wie ein Spieler zum nächsten
		# flachen Ufer schwimmen, statt im Wasser „Netz ohne Verbindung“ zu erkunden
		# Einsatzgebiet (a3 Lauf 5: Jagd auf FreeMan_1 jenseits der Grenze → „Ihr Team hat das Einsatzgebiet verlassen“):
		# wie ein Spieler bei der Warnung „Sie verlassen das Einsatzgebiet“ (Bit 0x4000) umkehren und das Ziel aufgeben
		if _area == null:
			_area = m.find_child("MissionArea", true, false)
		if _area and _area.has_method("flags_at") and (int(_area.flags_at(s.global_position)) & 0x6000) != 0:
			_release_all()
			Input.action_press("move_back")
			for f in 45:
				if await _step():
					return 2
			_release_all()
			_blocker("%s jenseits der Einsatzgebietsgrenze – umgekehrt bei %s" % [label, _v(s.global_position)])
			return 1
		if s.swimming:
			if await _escape_water() == 2:
				return 2
			repath = 0.0
			continue
		# Kante: vor einem Absturz > 2 m (Stegende a3 dummy_TheEnd2) anhalten; Ziel nah genug → als erreicht werten
		if flat.length() < 5.0 and s.is_on_floor():
			var fw := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
			var fq := PhysicsRayQueryParameters3D.create(s.global_position + fw * 0.8 + Vector3.UP * 0.5,
				s.global_position + fw * 0.8 + Vector3.DOWN * 2.0)
			fq.exclude = [s.get_rid()]
			if s.get_world_3d().direct_space_state.intersect_ray(fq).is_empty() and target.y > s.global_position.y - 1.5:
				_release_all()
				print("LOESER-M Kante vor %s – angehalten (%.1f m vom Ziel)" % [label, flat.length()])
				return 0
		# Ziel waagerecht schon da, aber ein Stockwerk höher/tiefer (a2 Ziel 4: „objectives“ oben im Turm T1, Soldat
		# kreiste darunter, bis die 300-s-Zünder hochgingen) → sofort Treppen nehmen statt erst Feststecken abzuwarten
		# Wiederholungsgrenze (a2 Lauf 14: derselbe Lauf −5,4 → −6,8 vierzigmal): höchstens 4 Treppenversuche je Weg
		if flat.length() < 3.0 and absf(target.y - s.global_position.y) > 2.0 and not s.is_climbing() and stair_calls < 4:
			stair_calls += 1
			_release_all()
			if await _take_stairs(target, 120.0) == 2:
				return 2
			repath = 0.0
			if absf(target.y - s.global_position.y) > 2.0 and el > 30.0:
				var er2: int = await _explore_toward(target, 30.0)
				if er2 == 2:
					return 2
			continue
		_diag_t -= dt
		if _diag_t <= 0.0:
			_diag_t = 5.0
			_maybe_checkpoint_save()
			print("LOESER-M Weg %s: bei %s Ziel %s %.1f m, Pfad %d/%d, Eingabe %s, UI %s, aktiv %s, Absicht %s, Sequenz %s, Klettern %s, Haltung %d, Boden %s, v %s, Taste %s" % [label,
				_v(s.global_position), _v(target), flat.length(), idx, path.size(), pc.input_enabled, pc.ui_blocking(),
				s == pc.active, _v(s.move_input), rt.in_cutscene, s.is_climbing(), int(s.stance), s.is_on_floor(),
				_v(s.velocity), Input.is_action_pressed("move_forward")])
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
		# Kletterstelle direkt vor uns (a4 ClimbLink_352 bei (−72,5; 0,4; 62,8): Kante unter einem Schneeüberhang, Wegpunkt
		# kaum höher, daher griff _maybe_link nicht) → wie ein Spieler alle 0,8 s Leertaste
		var lk_i := idx - 1 if idx > 0 else 0
		if lk_i < owners.size() and owners[lk_i] != 0:
			var lo: Object = instance_from_id(owners[lk_i])
			if lo is NavigationLink3D and lo.has_meta("climb") and s.velocity.length() < 0.5:
				climb_t -= dt
				if climb_t <= 0.0:
					climb_t = 0.8
					_press("stance_stand")
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
		# Fortschritt: bei gültigem Netzpfad (Ende am Ziel) = verbleibende Pfadlänge (Umwege zählen, a2 Lauf 9: Weg in den
		# Ostkeller über 160 Punkte), sonst 3D-Abstand (Treppe hinab zählt als Fortschritt)
		var path_ok := path.size() > 1 and path[path.size() - 1].distance_to(target) < 1.5
		# Netz-„Senkrechte“ (a2 T1: Stockwerke nur übereinander verbunden) zählt nicht als gültiger Pfad
		for k in range(maxi(idx, 0), path.size() - 1):
			var sg: Vector3 = path[k + 1] - path[k]
			if absf(sg.y) > 1.2 and Vector2(sg.x, sg.z).length() < 1.0:
				path_ok = false
				break
		var d3: float = (target - s.global_position).length()
		if path_ok and idx < path.size():
			d3 = s.global_position.distance_to(path[idx])
			for k in range(idx, path.size() - 1):
				d3 += path[k].distance_to(path[k + 1])
		if d3 < best_goal - 1.0:
			best_goal = d3
			stuck_n = 0
			stuck_t = 0.0
		if stuck_t > 4.0:
			stuck_t = 0.0
			stuck_n += 1
			wp_best = INF
			# B-036 a2: Navmesh ohne Treppenverbindung (ARCTIC2 T1: Start-Insel oben, Stockwerke nur senkrecht „verbunden“)
			# → wie ein Spieler die Umgebung ablaufen und jede Richtung nehmen, die dem Ziel in 3D näher bringt
			if stuck_n % 2 == 0 and absf(target.y - s.global_position.y) > 1.5 and not path_ok:
				var er: int = await _take_stairs(target, 120.0)
				if er == 0 and absf(target.y - s.global_position.y) > 1.5:
					er = await _explore_toward(target, 60.0)
				if er == 2:
					return 2
				repath = 0.0
				if (target - s.global_position).length() < best_goal - 1.0:
					best_goal = (target - s.global_position).length()
					stuck_n = 0
				continue
			# gültiger Pfad, aber ein bewegtes Hindernis liegt darauf (a4: Eisscholle Y_ulomek_02 per Skript verschoben,
			# Navmesh noch vom Ausgangszustand) → einmal um das Hindernis herum erkunden
			# a4 Lauf 13: festgefahren 0,45 m vor Tür m_a3_dvere_01 (Baracke vor den Unterlagen), Löser versuchte sie nie
			# (geschlossen) bzw. ein offener Flügel versperrte den Gang → nächste Tür ≤ 1,5 m in jedem Zustand umschalten
			if stuck_n == 3:
				var nd: Node = null
				var ndd := 1.5
				for n in t.get_tree().get_nodes_in_group("interactables"):
					if n is OrigInteractive.OrigDoor and (n as Node3D).global_position.distance_to(s.global_position + Vector3.UP) < ndd:
						ndd = (n as Node3D).global_position.distance_to(s.global_position + Vector3.UP)
						nd = n
				if nd:
					print("LOESER-M fest an Tür %s (offen=%s, angeboten=%s) – umschalten" % [nd.name, nd.is_open, nd.can_interact(s)])
					Input.action_press("move_back")
					for f in 15:
						if await _step():
							return 2
					_release_all()
					if await use(nd, false):
						return 2
					repath = 0.0
					continue
			if stuck_n == 5 and path_ok:
				var er3: int = await _explore_toward(target, 40.0)
				if er3 == 2:
					return 2
				repath = 0.0
				continue
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
		if int(_door_fail.get(n.name, 0)) >= 3:
			continue      # verschlossen (Schlüssel fehlt) bzw. anderes Stockwerk – je Runde nur 3 Versuche
		var to: Vector3 = (n as Node3D).global_position - s.global_position
		if not n.can_interact(s):
			continue      # Tür in anderem Stockwerk (Spiel bietet sie nicht an) – zählt nicht als Fehlversuch
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
				_door_fail[n.name] = int(_door_fail.get(n.name, 0)) + 1
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
	# Jagd auf eine Zielperson (a4 Marine_Officer_1): Munition nur für sie (Lauf 6 kam mit leerem Magazin an –
	# alle Patronen auf Wachen verschossen; Trupp ist unverwundbar, andere Gegner dürfen warten)
	if _hunt_target != null and is_instance_valid(_hunt_target) and e != _hunt_target:
		if _visible(_hunt_target):
			e = _hunt_target
		else:
			return false
	# B-036 a2 Lauf 10: Soldat stand minutenlang (Absicht 0) – ein sichtbarer, aber nicht zu treffender Gegner bzw.
	# leeres Magazin ohne Reserve hielt ihn im Kampf fest. Je Gegner höchstens 60 s, ohne Munition Waffe wechseln.
	var spent: float = float(_fight_time.get(e.get_instance_id(), 0.0))
	if spent > 60.0:
		return false
	var w0 := _lead().current_weapon()
	if w0 and w0.in_mag <= 0 and int(w0.get("reserve")) <= 0:
		for act in ["equip_2", "equip_1", "equip_3"]:
			if InputMap.has_action(act):
				_press(act)
				for f in 30:
					if await _step():
						return true
				var w1 := _lead().current_weapon()
				if w1 and (w1.in_mag > 0 or int(w1.get("reserve")) > 0):
					break
		var w2 := _lead().current_weapon()
		if w2 == null or (w2.in_mag <= 0 and int(w2.get("reserve")) <= 0):
			if not _no_ammo_said:
				_no_ammo_said = true
				print("LOESER-M keine Munition mehr – Kämpfe werden ausgelassen")
			return false
	_release_all()
	print("LOESER-M Kampf gegen %s" % e.name)
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
	if is_instance_valid(e):
		_fight_time[e.get_instance_id()] = spent + el
		if el >= 24.0 and e.alive:
			print("LOESER-M Kampf gegen %s ohne Erfolg (%.0f s gesamt)" % [e.name, spent + el])
	if is_instance_valid(e) and not e.alive:
		_kills += 1
	return false


## Gegner aufsuchen (nächste zuerst) und bekämpfen
var _saved_after := {}

## B-036: Zwischenspielstand „b036_<mission>_ziel<n>“, sobald Pflichtziel n erfüllt ist (für --from_save).
## Nur außerhalb von Zwischensequenzen und bei freier Spielereingabe; nicht im Lauf ab Spielstand.
func _maybe_checkpoint_save() -> void:
	if not pc.input_enabled:
		return
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o and o.state == Objective.State.DONE and not o.optional and not _saved_after.has(idx):
			_saved_after[idx] = true
			var slot := "b036_%s_ziel%d" % [String(Game.current_mission_id), idx]
			if Game.has_save(slot):
				continue          # schon vorhanden (Lauf ab Spielstand) – nicht überschreiben
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
		# ganz heran (a3 r_ar3_pilot.scr: „Whenever NPCecko (_PlayerInRange(2))“ → Pilot schließt sich an = Ziel 1;
		# vorher hielt der Löser 2,5–4 m Abstand und das Ziel blieb offen)
		if _lead().global_position.distance_to(g.global_position) > 1.5:
			# höchstens 90 s (a4: Pilot steht 2,2 m höher auf dem Boot, 420 s vergeblich – Offizier lief derweil zum U-Boot)
			var ra: int = await go_to(g.global_position, 1.2, 90.0, "Weg zum Führer %s" % g.name)
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
		# neu aktive Pflichtziele mit Zielort/Zielperson haben Vorrang (a4 Lauf 2: Ziel 4 „U-Boot nicht untertauchen“
		# wurde erst nach Ziel 1 aktiv, der Offizier lief derweil zum Boot)
		if await _go_objective_targets():
			return true
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
	# Todesfallen meidet ein Spieler auch: Skript tötet den Spieler in Reichweite (ARCTIC3 r_ar3_kill_player.scr
	# „dummy_kill_player_1“: Whenever _PlayerInRange(35) → HUMAN_Kill des Spielers, „Spieler blieb in der Basis“)
	var trap := String(p.name).to_lower().contains("kill_player") \
		or RegEx.create_from_string("human_kill(ex)?\\s*\\(\\s*(player|_player_|pl)\\w*\\s*\\)").search(src) != null
	if trap:
		print("LOESER-M Auslöser %s ausgelassen (Todesfalle, %s)" % [p.name, vm.name])
		return false
	if p is Soldier or RegEx.create_from_string("(?i)sendsignal\\s*\\([^)]*\\)\\s*;\\s*//[^\\n]*fail").search(src) != null:
		print("LOESER-M Auslöser %s ausgelassen (Führer bzw. Fehlschlag-Auslöser, %s)" % [p.name, vm.name])
		return false
	# reine Weck-Auslöser (a4 r_arc3_antis_aktiv1.scr „dummy_AntiS_1…7“, teils 24 m hoch auf Felsen: _PlayerInRange(10)
	# → SendSignal an die Scharfschützen AntiSniper_1–3) bringen kein Ziel weiter – auslassen, wenn das Skript nichts am
	# Missionsstand ändert und alle Signalempfänger Soldaten sind
	if not RegEx.create_from_string("setobjectivestatus|csc_|savegamevalue|mission_|frm_teleport|setactorstate|human_kill").search(src):
		var all_soldiers := true
		var any_target := false
		for mm in RegEx.create_from_string("frm_findframe\\s*\\(\\s*\\w+\\s*,\\s*\"([^\"]+)\"").search_all(src):
			any_target = true
			var nd := m.find_child(mm.get_string(1), true, false)
			# nicht (mehr) vorhanden = gefallener Gegner (a4 Lauf 11: AntiSniper schon tot → AntiS_7 wurde wieder angelaufen)
			if nd != null and not (nd is Soldier):
				all_soldiers = false
				break
		if any_target and all_soldiers:
			print("LOESER-M Auslöser %s weckt nur Gegner (%s) – ausgelassen" % [p.name, vm.name])
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
				# B-036 a2: kein Rückweg zum Start mehr (Pfad oft unerreichbar, Soldat stand 2 min an der Wand und
				# wurde dabei erschossen) – weiter zum nächsten Ziel; ist dadurch ein Rückkehrziel aktiv geworden, sofort hin
				if await _go_objective_targets():
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
