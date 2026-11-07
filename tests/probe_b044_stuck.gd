extends "res://tests/test_gameplay.gd"
## B-044 Messwerkzeug: Wie viele Einzelspieler-Gegner bleiben im Alarm/Kampf bzw. mit aktivem Bewegungsbefehl
## länger reglos – und warum?
##   tools\godot.cmd --headless -- --mission=<id> --autoplay=probe_b044_stuck [--hotspots=5] [--dwell=45]
##       [--still_s=15] [--tag=vorher] [--speed=1] [--test_timeout=1500]
## Ablauf: Intro überspringen, Trupp unverwundbar (god), dann nacheinander an K weit auseinanderliegende Gegnergruppen
## (Punktwahl „am weitesten entfernt“) heranteleportieren (25 m), einen Schuss abgeben und `dwell` s beobachten.
## Alle 0,5 s je Gegner: „relevant“ = Kampf/Suche/Untersuchen, Alarm gemeldet oder Skriptbewegung aktiv. Bleibt ein
## relevanter Gegner ≥ still_s s innerhalb 1 m, wird ein Stillstand mit Ursache gezählt:
##   erlaubt: stellung (stationary/MG), sniper (Leine ≤ 10 m), skript_haelt (Zombie ohne Laufziel: Delay/Warten)
##   Fehler: kein_pfad (Laufziel ohne Navmesh-Weg), abseits_netz (Soldat nicht auf dem Netz), festgefahren (Weg da, keine
##           Bewegung), keine_wahrnehmung (Kampf ohne Ziel/Wahrnehmung), ziel_unerreichbar (Ziel ohne Weg erreichbar),
##           fsm_<Zustand> (Automat ohne Laufziel), skript_bewegung (HUMAN_Move o. ä. kommt nicht voran), wache_alarm.
## Ergebnis: test_output/b044_<mission>_<tag>.txt, Zeile „B044_SUMME …“.

var _lines: PackedStringArray = []
var _t := 0.0
var _rec := {}            ## Soldat -> {anchor, since, relevant_since, counted, cause}
var _ever_relevant := {}  ## Soldat -> true
var _stalls: Array = []   ## {name, cause, detail, dur, t}
var _open := {}           ## Soldat -> Index in _stalls
var _still_s := 15.0
var _rt: LsRuntime
var _names := {}


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 80.0, 1))
	return Vector3.INF if hit.is_empty() else hit.position


## B-044b: Kollider mit Elternname, Ebene und Herkunft (static = unter Mission.static_root = Navmesh-Quelle,
## dyn = außerhalb, z. B. dynamic_root/Akteurmodelle) – zeigt Kollision, die das Navmesh nicht kennt.
func _body_desc(o: Node) -> String:
	if o is Soldier:
		return String(o.name)
	var p := o.get_parent()
	var nm := String(p.name) if p else String(o.name)
	var src := "static" if mission().static_root and mission().static_root.is_ancestor_of(o) else "dyn"
	var lay := int(o.get("collision_layer")) if "collision_layer" in o else 0
	return "%s[%s,L%d]" % [nm, src, lay]


func _map() -> RID:
	return mission().get_viewport().world_3d.navigation_map


func _path_end_gap(from: Vector3, to: Vector3) -> float:
	var map := _map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return 0.0
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty():
		return INF
	return path[path.size() - 1].distance_to(to)


func _enemies() -> Array:
	var out: Array = []
	for e in mission().enemies:
		if is_instance_valid(e) and e.alive and e.team == Soldier.TEAM_AXIS and e.get_node_or_null("EnemyBrain") is EnemyBrain:
			out.append(e)
	return out


func _relevant(b: EnemyBrain) -> bool:
	if b.suspended or b.surrendered or b.captured or not b.enabled:
		return false
	if b.script_control:
		return b.has_move_target() or b._alarm_notified
	return b.state in [EnemyBrain.State.COMBAT, EnemyBrain.State.SEARCH, EnemyBrain.State.INVESTIGATE] or b._alarm_notified


func _vm_info(s: Soldier) -> String:
	var vm = _rt.vm_for(s) if _rt and _rt.has_method("vm_for") else null
	if vm == null:
		return "-"
	if vm.ended or vm.terminated:
		return "ende"
	if vm.wait > 0.0:
		return "delay"
	if vm.wait_until.is_valid() and vm.block_pc >= 0 and vm.block_pc < vm.code.ops.size():
		return "wartet:" + str(vm.code.ops[vm.block_pc][1])
	return "läuft"


## Ursache eines Stillstands: [kategorie, detail]
func _cause(s: Soldier, b: EnemyBrain) -> Array:
	var vm := _vm_info(s)
	var fsm := b.orig_fsm.state_name() if b.orig_fsm != null else "-"
	var mt: Vector3 = b._move_target
	var d := "bew=%s mor=%.0f abbr=%d zust=%s fsm=%s vm=%s ziel=%s mt=%s" % [b.is_armed(), b.morale, b.progress_aborts, b.state_name(), fsm, vm,
		b.target.name if is_instance_valid(b.target) else "-", mt.snapped(Vector3.ONE * 0.1) if mt.is_finite() else "-"]
	if b.stationary or s.mounted != null or s.vehicle != null:
		return ["stellung", d]
	if b.sniper_enabled and b.sniper_range <= 10.0:
		return ["sniper", d]
	var map := _map()
	var cp := NavigationServer3D.map_get_closest_point(map, s.global_position)
	var off := cp.distance_to(s.global_position)
	d += " netz=%.1f" % off
	if mt.is_finite():
		d += " abst=%.1f nächst=%.1f" % [Vector2(mt.x - s.global_position.x, mt.z - s.global_position.z).length(),
			b.agent.get_next_path_position().distance_to(s.global_position)]
	d += " v=%.2f mi=%.2f halt=%d gang=%d fest=%.1f umweg=%.1f kletter=%.1f fzg=%s" % [Vector2(s.velocity.x, s.velocity.z).length(),
		s.move_input.length(), s.stance, s.move_mode, b._stuck_time, b._detour, b._climb_retry, s.vehicle != null]
	var hits := PackedStringArray()
	for i in s.get_slide_collision_count():
		var o := s.get_slide_collision(i).get_collider() as Node
		if o and not hits.has(_body_desc(o)):
			hits.append(_body_desc(o))
	var kc := KinematicCollision3D.new()
	var fw := Vector3(s.move_input.x, 0, s.move_input.z)
	if fw.length() > 0.1 and s.test_move(s.global_transform, fw.normalized() * 0.4, kc):
		var o2 := kc.get_collider() as Node
		hits.append("vorn:" + (_body_desc(o2) if o2 else "?"))
	d += " pos=%s stößt=%s" % [s.global_position.snapped(Vector3.ONE * 0.1), ",".join(hits)]
	if b.script_control:
		if b.has_move_target():
			var g := _path_end_gap(s.global_position, mt)
			d += " lücke=%.1f" % g
			if off > 1.0:
				return ["abseits_netz", d]
			return ["kein_pfad" if g > 3.0 else "skript_bewegung", d]
		return ["skript_haelt", d]
	if b.has_move_target():
		var g2 := _path_end_gap(s.global_position, mt)
		d += " lücke=%.1f" % g2
		if off > 1.0:
			return ["abseits_netz", d]
		if g2 > 3.0:
			return ["kein_pfad", d]
		return ["festgefahren", d]
	if b.state == EnemyBrain.State.COMBAT:
		if not is_instance_valid(b.target) or not b.target.alive or b.perception.awareness.get(b.target, 0.0) < 1.0:
			return ["keine_wahrnehmung", d]
		var tg := _path_end_gap(s.global_position, b.target.global_position)
		d += " ziellücke=%.1f sicht=%s" % [tg, b.perception.visible_now.get(b.target, false)]
		if tg > 3.0:
			# Ziel sichtbar, aber ohne Weg (z. B. Leuchtturm): Automat feuert/wechselt am Posten – kein Fehler
			return ["ziel_unerreichbar_sicht" if b.perception.visible_now.get(b.target, false) else "ziel_unerreichbar", d]
		return ["fsm_" + fsm, d]
	if b.state in [EnemyBrain.State.GUARD, EnemyBrain.State.PATROL]:
		return ["wache_alarm", d]
	return ["zustand_" + b.state_name(), d]


const ALLOWED := ["stellung", "sniper", "skript_haelt", "ziel_unerreichbar_sicht"]


func _sample() -> void:
	for e in _enemies():
		var s := e as Soldier
		var b := s.get_node("EnemyBrain") as EnemyBrain
		var r: Dictionary = _rec.get(s, {})
		var rel := _relevant(b)
		if r.is_empty() or s.global_position.distance_to(r["anchor"]) > 1.0 or not rel:
			if _open.has(s):
				_stalls[_open[s]]["dur"] = _t - float(_stalls[_open[s]]["t0"])
				_open.erase(s)
			r = {"anchor": s.global_position, "since": _t}
		_rec[s] = r
		if not rel:
			continue
		_ever_relevant[s] = true
		var still := _t - float(r["since"])
		if still >= _still_s and not _open.has(s):
			var c := _cause(s, b)
			_stalls.append({"name": _names.get(s, s.name), "cause": c[0], "detail": c[1], "t0": float(r["since"]), "dur": still})
			_open[s] = _stalls.size() - 1
			_log("STILL t=%.0f %-20s %-18s %s" % [_t, _names.get(s, s.name), c[0], c[1]])
		elif _open.has(s):
			_stalls[_open[s]]["dur"] = still


func _observe(secs: float) -> void:
	var steps := int(secs / 0.5)
	for i in steps:
		await seconds(0.5)
		if mission() == null or not is_instance_valid(mission()):
			return
		_t += 0.5
		for sm in mission().squad.members:
			if is_instance_valid(sm) and sm.alive:
				sm.max_health = 100000.0
				sm.health = sm.max_health
		_sample()


func _place_squad(near: Vector3, enemy_pos: Vector3) -> void:
	var space := mission().get_viewport().world_3d.direct_space_state
	var map := _map()
	var dir := (near - enemy_pos)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var best := Vector3.INF
	for k in 12:
		var a := dir.rotated(Vector3.UP, k * TAU / 12.0)
		var p := enemy_pos + a * 25.0
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(p) < 6.0 and _path_end_gap(q, enemy_pos) < 3.0:
			best = q
			break
	if not best.is_finite():
		best = _ground(space, enemy_pos + dir * 25.0)
		if not best.is_finite():
			best = enemy_pos + dir * 25.0
	var i := 0
	for sm in mission().squad.members:
		if is_instance_valid(sm) and sm.alive and sm.vehicle == null:
			sm.global_position = best + Vector3.UP * 0.3 + Vector3(i % 2, 0, i / 2) * 1.2
			sm.velocity = Vector3.ZERO
			i += 1
	var c: Soldier = mission().squad.leader()
	var to := enemy_pos - c.global_position
	c.look_yaw = atan2(-to.x, -to.z)


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	_rt = m.runtime
	m.finished = true    # Missionsende (Erfolg/Fehlschlag durch Skript) unterdrücken: nur messen
	_still_s = float(Game.cli.get("still_s", "15"))
	Engine.time_scale = float(Game.cli.get("speed", "1"))
	await seconds(2.0)
	if _rt.in_cutscene:
		_rt.end_cutscene()
	for i in 3600:
		if m.nav_ready:
			break
		await get_tree().process_frame
	await seconds(1.0)
	for k in _rt.actors:
		_names[_rt.actors[k]] = k
	var all := _enemies()
	var unarmed := all.filter(func(e): return not (e.get_node("EnemyBrain") as EnemyBrain).is_armed()).map(func(e): return _names.get(e, e.name))
	_log("== B-044 %s: %d Gegner, still_s=%.0f, unbewaffnet am Start: %s" % [m.name, all.size(), _still_s, str(unarmed)])
	# Ruhephase (Skriptpatrouillen ohne Spieler): 20 s
	await _observe(float(Game.cli.get("calm", "20")))
	# Hotspots: am weitesten voneinander entfernte Gegner
	var hs: Array[Vector3] = []
	var k_hot := int(Game.cli.get("hotspots", "5"))
	var c0: Soldier = m.squad.leader()
	var ref := c0.global_position
	while hs.size() < k_hot and not all.is_empty():
		var best_e: Soldier = null
		var best_d := -1.0
		for e in all:
			var dmin := ref.distance_to(e.global_position) if hs.is_empty() else INF
			for h in hs:
				dmin = minf(dmin, h.distance_to(e.global_position))
			if dmin > best_d:
				best_d = dmin
				best_e = e
		if best_e == null or (hs.size() > 0 and best_d < 30.0):
			break
		hs.append(best_e.global_position)
	var dwell := float(Game.cli.get("dwell", "45"))
	for h in hs:
		_log("== HOTSPOT %s (t=%.0f)" % [h.snapped(Vector3.ONE), _t])
		_place_squad(ref, h)
		await frames(10)
		var c: Soldier = m.squad.leader()
		c.trigger = true
		await frames(20)
		c.trigger = false
		await _observe(dwell)
	# offene Stillstände abschließen
	var by := {}
	var bad := 0
	var bad_enemies := {}
	var allowed := 0
	for st in _stalls:
		by[st["cause"]] = int(by.get(st["cause"], 0)) + 1
		if ALLOWED.has(st["cause"]):
			allowed += 1
		else:
			bad += 1
			bad_enemies[st["name"]] = true
	_log("== STILLSTÄNDE (≥ %.0f s)" % _still_s)
	for st in _stalls:
		_log("  %-20s %-18s %5.0f s  %s" % [st["name"], st["cause"], st["dur"], st["detail"]])
	var causes := PackedStringArray()
	for k in by:
		causes.append("%s=%d" % [k, by[k]])
	var summary := "B044_SUMME mission=%s gegner=%d relevant=%d stillstand_fehler=%d (gegner %d) erlaubt=%d anteil=%.1f%% ursachen=%s" % [
		m.name, all.size(), _ever_relevant.size(), bad, bad_enemies.size(), allowed,
		100.0 * bad_enemies.size() / maxf(_ever_relevant.size(), 1.0), ",".join(causes)]
	_log(summary)
	var tag := String(Game.cli.get("tag", "messung"))
	var f := FileAccess.open("res://test_output/b044_%s_%s.txt" % [Game.cli.get("mission", m.name), tag], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
	check(true, "Messung abgeschlossen", summary)
	_finish()
