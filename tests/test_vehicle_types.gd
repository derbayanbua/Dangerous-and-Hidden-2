extends "res://tests/test_gameplay.gd"
## B-043: alle Fahrzeugtypen der Originalmissionen (Inventar docs/status/b043.md) – je Typ mit Originalmodell,
## Car-Parametern (vehicles.json), Munition (actor_params) und Schadensmodell DM<Modell>: Sitze, Ein-/Aussteigen,
## Fahren (Spielereingabe), Verfolgerkamera, jede Bordwaffe (Richten mit Original-hs/vs, Feuern, Nachladen),
## KI-Schütze an der Hauptwaffe, Server-Prüfung eines Client-Schusses (B-022 _act_error), Schaden bis zum Wrack,
## Insassen tot, Wrack nicht mehr besteigbar, Netzstand (net_state → Zwilling) für Clients.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_vehicle_types [--types=la_tiger,la_jeepsas]

const TRACK_Y := 600.0
## [Bezeichnung, Mission (Cache), Akteur, Modell] – je Modell ein Vertreter, bevorzugt mit Munition im Inventar
const TYPES := [
	["Kübelwagen (Winter)", "arctic1", "la_kubelW_", "la_kubelw"],
	["Kübelwagen (Afrika)", "africa3", "la_kubelAf", "la_kubelafbez"],
	["Kübelwagen (Europa)", "czech5", "la_kubelEv_1", "la_kubelev"],
	["Kübelwagen (Europa, MP)", "czech4_mp_zone", "la_kubelEvbez_", "la_kubelevbez"],
	["Kübelwagen (sowj.)", "czech6", "Kubel_RUS", "la_kubel_rus"],
	["Jeep SAS (MG)", "africa1", "la_Jeepsas_01", "la_jeepsas"],
	["Jeep", "tutorial", "Jeep", "la_jeepuvj"],
	["Jeep (Winter)", "ardens1_obj", "la_JeepW_", "la_jeepw"],
	["BMW R75 Beiwagen", "africa1", "la_BmwR_", "la_bmwr75"],
	["Opel Blitz (Europa)", "czech5", "La_OpelE_1", "la_opele"],
	["Opel Blitz (Winter)", "arctic3", "Opel_01", "la_opelwin"],
	["Opel Blitz (Winter, Wrack)", "arctic1", "Auti_BAD", "la_opelwduo"],
	["Opel Blitz (Afrika)", "africa5", "Broken_Opel", "la_opelaf"],
	["Opel Blitz (Afrika, Plane)", "africa4", "La_OpelAf2", "la_opelafk"],
	["Opel Blitz Flak 38", "africa1", "la_OpelFuj", "la_opelfaf"],
	["Bedford", "tutorial", "la_Bedford_1", "la_bedford"],
	["Krupp Protze", "czech6_mp_zone", "la_krupp_", "la_krupp"],
	["Halbkette Sd.Kfz. 251 (Afrika)", "africa4", "Opel02", "la_hakl_af"],
	["Halbkette Sd.Kfz. 251 (Europa)", "czech5", "la_hakl_Ev_1", "la_hakl_ev"],
	["Halbkette M3", "czech6_mp_zone", "la_halftruck_", "la_halftruck"],
	["Puma Sd.Kfz. 234", "czech6_mp_zone", "la_puma_", "la_puma"],
	["Panzer III (Afrika)", "africa1", "panzer01", "la_panzer iiiaf"],
	["Panzer III", "normandy3_mp", "la_Panzer III_", "la_panzer iii"],
	["Panther", "czech6", "la_panther_", "la_panther"],
	["Tiger (Afrika)", "africa4", "tiger01", "la_tiger"],
	["Tiger (Europa)", "normandy2", "La_tigerEv", "la_tigerev"],
	["Tiger (Winter)", "ardens1_obj", "la_tigerW_", "la_tigerw"],
	["Sherman", "normandy2", "la_sherman", "la_sherman"],
	["Sherman (Afrika)", "africa2_mp_zone", "la_shermanAf_", "la_shermanaf"],
	["Sherman (Winter)", "ardens1_obj", "la_shermanW_", "la_shermanw"],
	["ISU-152", "czech6", "Isu152", "la_isu152"],
]

var _levels := {}
var _hale: Soldier
var _gunner_pool: Array = []
var _summary: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2400.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	if m.get("runtime") and m.runtime:
		m.runtime.auto_skip = true
		await seconds(1.0)
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
	isolate_enemies([])
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e.vehicle == null and e.mounted == null:
			_gunner_pool.append(e)
	_hale = m.squad.leader()
	_hale.max_health = 99999.0
	_hale.health = 99999.0
	for mb in m.squad.members:
		if mb != _hale:
			m.squad.brain_of(mb).set_order(SquadBrain.Order.HOLD)
			mb.global_position = Vector3(-300, TRACK_Y + 0.5, -300)
	_test_block(Vector3(0, TRACK_Y - 1.0, 0), Vector3(400, 1, 400), 0.0)
	var only: Array = String(Game.cli.get("types", "")).split(",", false)
	var x := -150.0
	for ty in TYPES:
		if not only.is_empty() and not only.any(func(o): return String(ty[3]).contains(String(o))):
			continue
		await _test_type(ty, Vector3(x, TRACK_Y, -120.0))
		x += 10.0
		if x > 150.0:
			x = -150.0
	print("B043-INVENTAR")
	for l in _summary:
		print("  " + l)
	for k in _levels:
		(_levels[k] as OrigLevel).release()
	_finish()


func _actor_ammo(mis: String, actor: String) -> Array:
	var out: Array = []
	var p := OrigLevel.cache_path(mis) + "/actor_params.json"
	var j = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	if typeof(j) != TYPE_DICTIONARY:
		return out
	var acts: Dictionary = j.get("actors", {})
	for k in acts:
		if String(k).to_lower() == actor.to_lower():
			for it in acts[k].get("inventory", []):
				if String(it.get("kind", "")) == "ammo":
					out.append(int(it.get("item", -1)))
	return out


func _drive_data(mis: String, actor: String) -> Dictionary:
	var p := OrigLevel.cache_path(mis) + "/vehicles.json"
	var j = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	if typeof(j) != TYPE_DICTIONARY:
		return {}
	var vd: Dictionary = j.get("vehicles", {})
	for k in vd:
		if String(k).to_lower() == actor.to_lower():
			return vd[k]
	return {}


## Fahrzeug wie OrigMission._spawn_orig_car (Modell, Car-Parameter, Munition, Rohr-Parameter, Schadensmodell)
func _spawn(ty: Array, pos: Vector3, suffix := "") -> Vehicle:
	var mis: String = ty[1]
	var model: String = ty[3]
	if not _levels.has(mis):
		var holder := Node3D.new()
		get_tree().current_scene.add_child(holder)
		_levels[mis] = OrigLevel.new(mis, holder)
	var ol: OrigLevel = _levels[mis]
	var vis: Node3D = ol.model_instance(model)
	if vis == null:
		return null
	vis.rotation.y = PI
	var v := Vehicle.new()
	v.name = ("b043_" + model + suffix).validate_node_name()
	v.persistent_id = "b043_" + model + suffix
	v.vehicle_name = ty[0]
	v.custom_visual = vis
	v.drive_model = model
	v.drive_data = _drive_data(mis, ty[2])
	v.ammo_items = _actor_ammo(mis, ty[2])
	var dir := OrigLevel.cache_path(mis)
	v.model_path = dir + "/models/" + model.to_lower() + ".glb"
	v.dm_path = dir + "/models/dm_" + model.to_lower() + ".glb"
	mission().dynamic_root.add_child(v)
	v.global_position = pos + Vector3.UP * 0.4
	v.global_rotation.y = 0.0
	return v


func _test_type(ty: Array, pos: Vector3) -> void:
	var label: String = ty[0]
	var v := _spawn(ty, pos)
	check(v != null, "%s: Originalmodell %s geladen" % [label, ty[3]])
	if v == null:
		_summary.append("%s | %s | Modell fehlt" % [label, ty[3]])
		return
	await seconds(1.5)
	var line := "%s | %s/%s | %d Sitze | DM %s" % [label, ty[1], ty[2], v.seats.size(), "ja" if v.damage_model else "nein"]
	check(v.seats.size() >= 2 and v.occupants.size() == v.seats.size(), "%s: Sitze aus SEATnn" % label, "%d" % v.seats.size())
	check(v.damage_model != null, "%s: Schadensmodell DM geladen" % label)
	check(absf(v.linear_velocity.y) < 0.5 and v.global_basis.y.y > 0.9, "%s: steht auf den Rädern/Ketten" % label)

	# --- Einsteigen (Spieler, Fahrer) und Fahren mit der Spielereingabe ---
	_hale.global_position = v.global_position + v.global_basis.x * (v._size.x * 0.5 + 1.2) + Vector3.UP * 0.2
	await frames(2)
	check(v.board(_hale, true) and _hale.vehicle == v and _hale.seat_index == 0, "%s: Spieler steigt als Fahrer ein" % label)
	var p0 := v.global_position
	var heavy := float(v.drive_data.get("mass_kg", 1000.0)) > 15000.0
	await hold("move_forward", 4.0 if heavy else 3.0)
	var moved := (v.global_position - p0).dot(v.global_basis.z)
	if moved < 2.0 and v.drive:
		var ws: Array = []
		for w in v.drive.wheels:
			ws.append("z%.2f r%.2f %s%s%s L%.0f" % [w.center.z, w.radius, "F" if w.front else "", "D" if w.driven else "", "*" if w.contact else "", w.load])
		print("B043-FAHRT %s: frozen=%s sleep=%s gear=%d thr=%.2f F=%.0f speed=%.2f info=%s räder=%s" % [label, v.freeze, v.sleeping,
			v.drive.gear, v.drive.throttle, v.drive.drive_force, v.drive.speed, str(v.drive.info()), str(ws)])
	check(moved > (2.0 if heavy else 4.0), "%s: fährt vorwärts (Spielereingabe)" % label, "%.1f m" % moved)
	var y0 := v.global_rotation.y
	Input.action_press("move_left")
	await hold("move_forward", 1.5)
	Input.action_release("move_left")
	var turned := angle_difference(y0, v.global_rotation.y)
	check(turned > 0.05, "%s: lenkt nach links" % label, "%.0f°" % rad_to_deg(turned))
	Input.action_press("stance_stand")
	await seconds(4.0)
	Input.action_release("stance_stand")
	check(v.speed_kmh() < 6.0 and v.global_basis.y.y > 0.8, "%s: bremst, bleibt aufrecht" % label, "%.1f km/h" % v.speed_kmh())
	line += " | %.1f m Fahrt" % moved
	# Verfolgerkamera: Drehpunkt über dem Fahrzeug, Abstand nach Größe
	var cp := v.chase_pivot()
	check(cp.y > v.global_position.y + 0.8 and v.chase_distance() >= 5.5 and v.chase_distance() <= 12.0,
		"%s: Verfolgerkamera über dem Fahrzeug" % label, "Höhe %.1f m, Abstand %.1f m" % [cp.y - v.global_position.y, v.chase_distance()])
	# Mitfahrer (Kamerad) und Aussteigen
	var mate: Soldier = null
	for mb in mission().squad.members:
		if mb != _hale and mb.alive and mb.vehicle == null:
			mate = mb
			break
	if mate:
		mate.global_position = v.global_position + Vector3.UP * 0.3 + v.global_basis.x * 3.0
		var ok := v.board(mate)
		check(ok and mate.seat_index > 0, "%s: Mitfahrer steigt zu" % label, "Sitz %d" % mate.seat_index)
		await frames(3)
		if ok:
			check(mate.global_position.distance_to(v.seat_transform(mate.seat_index).origin) < 1.5, "%s: Mitfahrer am Sitz" % label)
			v.leave(mate)
			mate.global_position = Vector3(-300, TRACK_Y + 0.5, -300)
	var own := _hale.weapons.duplicate()
	v.leave(_hale)
	await frames(3)
	check(_hale.vehicle == null and v.driver() == null and _hale.model.visible, "%s: Spieler steigt aus" % label)
	var same := _hale.weapons.size() == own.size()
	for i in own.size():
		same = same and _hale.weapons[i] == own[i]
	check(same, "%s: eigene Waffen nach dem Aussteigen zurück" % label)

	# --- Bordwaffen ---
	var weapons_txt: Array = []
	var main_seat := -1
	for i in v.turrets:
		var w: Weapon = v.seat_weapon(i)
		if w == null:
			continue
		var cannon := w.data.action == WeaponData.Action.ROCKET and w.data.shot_interval() >= 1.0
		if main_seat < 0 or cannon:
			main_seat = i
		weapons_txt.append("S%d %s (%d+%d)" % [i, w.data.display_name, w.in_mag, w.reserve])
		await _test_turret(v, i, label)
	line += " | Waffen: " + (", ".join(weapons_txt) if not weapons_txt.is_empty() else "keine")
	if main_seat >= 0:
		await _test_ai_gunner(v, main_seat, label)

	# --- Schaden/Zerstörung (Server) und Netzstand für Clients ---
	var crew: Soldier = null
	for o in v.occupants:
		if is_instance_valid(o):
			crew = o
	if crew == null and not _gunner_pool.is_empty():
		crew = _next_gunner()
		if crew:
			v.board(crew, false, main_seat if main_seat >= 0 else 0)
	var dm := v.damage_model
	if v.armored and dm:
		var hp0: Array = dm.zones.map(func(z): return int(z["hp"]))
		for i in 5:
			v.projectile_hit(1, 48.8, v.global_position + Vector3.UP * v._size.y * 0.5, -v.global_basis.z, _hale)
		check(dm.zones.map(func(z): return int(z["hp"])) == hp0 and not v.wrecked, "%s: Gewehrtreffer durchschlagen die Panzerung nicht" % label)
	var hits := 0
	var aim := v.global_position + Vector3.UP * maxf(v._size.y * 0.5, 0.6)
	var dirs := [-v.global_basis.z, v.global_basis.z, v.global_basis.x, -v.global_basis.x, Vector3.DOWN]
	while not v.wrecked and hits < 80:
		var d: Vector3 = dirs[hits % dirs.size()]
		v.projectile_hit(7, 290.0, aim, d, _hale)       # Panzerfaust-Direkttreffer (2900 zotti)
		hits += 1
		await frames(1)
	if not v.wrecked:
		for i in 6:
			v.explosion_at(aim, 5.5, 400.0, _hale)      # Kanonengranate 4000 zotti / 5,5 m am Rumpf
			await frames(1)
	await frames(3)
	check(v.wrecked, "%s: durch Treffer zerstört" % label, "%d Panzerfaust-Treffer" % hits)
	line += " | Wrack nach %d PzF" % hits
	if crew:
		check(not crew.alive and crew.vehicle == null, "%s: Insasse beim Zerstören getötet" % label)
	check(not v._entry.can_interact(_hale) and not v.board(_hale, true), "%s: Wrack nicht besteigbar" % label)
	var twin := _spawn(ty, pos + Vector3(0, 0, 40.0), "_net")
	if twin:
		await frames(3)
		twin.apply_net_state(v.net_state())
		check(twin.wrecked and twin.damage_model != null and twin.damage_model.serialize() == v.damage_model.serialize(),
			"%s: Netzstand (Zonen/Wrack) beim Client übernommen" % label)
		twin.queue_free()
	_summary.append(line)
	await seconds(0.3)
	v.queue_free()
	await frames(2)


func _next_gunner() -> Soldier:
	while not _gunner_pool.is_empty():
		var g: Soldier = _gunner_pool.pop_front()
		if is_instance_valid(g) and g.alive and g.vehicle == null:
			return g
	return null


func _test_turret(v: Vehicle, idx: int, label: String) -> void:
	var t: Dictionary = v.turrets[idx]
	var nm := "%s Sitz %d" % [label, idx]
	_hale.global_position = v.global_position + v.global_basis.x * (v._size.x * 0.5 + 1.2) + Vector3.UP * 0.2
	await frames(1)
	if not v.board(_hale, false, idx):
		check(false, "%s: Spieler besetzt die Bordwaffe" % nm)
		return
	var w := _hale.current_weapon()
	check(w != null and w == v.seat_weapon(idx), "%s: Bordwaffe in der Hand" % nm, w.data.display_name if w else "-")
	if w == null:
		v.leave(_hale)
		return
	# Richten: Blick weit nach links, Rohr folgt mit hs (begrenzt durch left)
	var d0 := v.turret_dir(idx)
	var yaw0 := atan2(-d0.x, -d0.z)
	for i in 30:
		var cd := v.turret_dir(idx)
		_hale.look_yaw = atan2(-cd.x, -cd.z) + 1.0
		await get_tree().physics_frame
	var d1 := v.turret_dir(idx)
	var turned := absf(angle_difference(yaw0, atan2(-d1.x, -d1.z)))
	var want := minf(float(t["hs"]) * 30.0 / Engine.physics_ticks_per_second, float(t["left"]))
	check(turned > want * 0.6 and turned < want * 1.3 + 0.02, "%s: Seitenrichten (hs %.0f°/s, links %s)" % [nm, rad_to_deg(t["hs"]),
		"frei" if float(t["left"]) >= Vehicle.NO_LIMIT else "%.0f°" % rad_to_deg(t["left"])], "%.1f° (Soll %.1f°)" % [rad_to_deg(turned), rad_to_deg(want)])
	for i in 60:
		_hale.look_pitch = 1.0
		await get_tree().physics_frame
	var up := rad_to_deg(asin(clampf(v.turret_dir(idx).y - d1.y, -1.0, 1.0)))
	check(up > 1.0, "%s: Höhenrichten" % nm, "+%.1f°" % up)
	for i in 60:
		_hale.look_pitch = 0.0
		await get_tree().physics_frame
	# Feuern (Spielereingabe)
	var shots := [0]
	var cb := func(_w): shots[0] += 1
	_hale.shot_fired.connect(cb)
	var ammo0 := w.total_ammo()
	var integ0: float = v.damage_model.integrity() if v.damage_model else 1.0
	Input.action_press("fire")
	await frames(6)
	Input.action_release("fire")
	await seconds(1.0)
	check(shots[0] >= 1 and w.total_ammo() < ammo0, "%s: feuert (Munition %d → %d)" % [nm, ammo0, w.total_ammo()])
	check(not v.wrecked and (v.damage_model == null or is_equal_approx(v.damage_model.integrity(), integ0)),
		"%s: eigener Schuss beschädigt das Fahrzeug nicht" % nm)
	# Server-Prüfung (B-022): Client-Schuss aus dem Fahrzeug wird angenommen
	var kind := "rocket" if w.data.action == WeaponData.Action.ROCKET else "shot"
	var md := v.turret_dir(idx)
	var b := md * w.data.muzzle_velocity if kind == "rocket" else md
	_hale.set_meta("fire_rates", {})
	var why: String = Net._act_error(_hale, kind, v.muzzle_point(idx), b, String(w.data.id))
	check(why == "", "%s: Server nimmt Bordwaffenschuss an (MP)" % nm, why)
	# Nachladen: Magazin leeren, Taste R, Reserve füllt nach
	if w.reserve > 0:
		w.in_mag = 0
		var res0 := w.reserve
		await tap("reload")
		await seconds(w.data.reload_time + 0.6)
		check(w.in_mag > 0 and w.reserve < res0, "%s: Nachladen (%.1f s)" % [nm, w.data.reload_time], "Magazin %d, Reserve %d → %d" % [w.in_mag, res0, w.reserve])
		shots[0] = 0
		Input.action_press("fire")
		await frames(6)
		Input.action_release("fire")
		await seconds(0.5)
		check(shots[0] >= 1, "%s: feuert nach dem Nachladen" % nm)
	else:
		# Original-Inventar mit nur einer Munitionseinheit (Jeep SAS: 1× 202) = ein Gurt ohne Reserve
		print("B043-HINWEIS %s: keine Reservemunition im Originalinventar (%d+0)" % [nm, w.in_mag])
		w.in_mag = 0
		await tap("reload")
		await seconds(0.3)
		check(w.in_mag == 0 and not w.is_reloading(), "%s: ohne Reserve kein Nachladen" % nm)
	_hale.shot_fired.disconnect(cb)
	v.leave(_hale)
	await frames(2)


func _test_ai_gunner(v: Vehicle, idx: int, label: String) -> void:
	var g := _next_gunner()
	if g == null:
		return
	var sw := v.seat_weapon(idx)
	if sw and sw.in_mag <= 0:
		sw.in_mag = sw.data.magazine_size      # Spielertest hat das Magazin geleert (Jeep: keine Reserve)
	g.set_physics_process(true)
	g.global_position = v.global_position + v.global_basis.x * (v._size.x * 0.5 + 1.2) + Vector3.UP * 0.2
	await frames(1)
	check(v.board(g, false, idx) and g.vehicle == v, "%s: KI besetzt die Hauptwaffe (Sitz %d)" % [label, idx])
	var gb := g.get_node("EnemyBrain") as EnemyBrain
	gb.enabled = true
	gb.suspended = false
	gb.script_control = false
	var per: Perception = g.get_node("Perception")
	per.set_physics_process(true)
	var fwd := v.turret_dir(idx)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else v.global_basis.z
	var tgt := v.muzzle_point(idx) + fwd * 25.0
	_hale.global_position = Vector3(tgt.x, TRACK_Y + 0.1, tgt.z)
	_hale.velocity = Vector3.ZERO
	per.sight_range = 80.0
	per.awareness[_hale] = 1.0
	per.last_known[_hale] = _hale.global_position
	var shots := [0]
	var cb := func(_w): shots[0] += 1
	g.shot_fired.connect(cb)
	for i in 100:
		await frames(6)
		per.awareness[_hale] = 1.0
		if shots[0] >= 1:
			break
	g.shot_fired.disconnect(cb)
	if shots[0] < 1:
		var eye := g.eye_position()
		var tp := _hale.global_position + Vector3.UP * 1.2
		var los := per._line_of_sight(g.get_world_3d().direct_space_state, eye, tp, _hale)
		var q := PhysicsRayQueryParameters3D.create(eye, tp, 1, [g.get_rid(), v.get_rid()])
		var hit := g.get_world_3d().direct_space_state.intersect_ray(q)
		print("B043-KI %s: %s sicht=%s bewusst=%.2f winkel=%.0f° LOS=%s Treffer=%s skript=%s auge=%s ziel=%s reach=%.0f orig=%s" % [label,
			g.name, per.visible_now.get(_hale, false), per.awareness.get(_hale, 0.0), rad_to_deg(g.aim_direction().angle_to(tp - eye)), los,
			str(hit.get("collider")) if not hit.is_empty() else "-", gb.script_control, eye, tp, per.orig_visibility_distance(_hale) if per.orig_formula else per.sight_range, per.orig_formula])
	check(shots[0] >= 1, "%s: KI-Schütze feuert die Bordwaffe" % label, "%d Schuss, Zustand %s" % [shots[0], gb.state_name()])
	gb.enabled = false
	_hale.global_position = v.global_position + Vector3(0, 0, -20)
