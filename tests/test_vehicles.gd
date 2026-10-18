extends "res://tests/test_gameplay.gd"
## Fahrzeuge: Einsteigen, Mitfahrer, Fahren, Lenken, Motorgeräusch, Aussteigen,
## Zerstörung.   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_vehicles


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Messfahrten aller Fahrzeugtypen dauern länger als die übliche Testzeit
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if Game.cli.has("physics_only"):          # Entwicklung: nur die Messfahrten
		isolate_enemies([])
		await _physics_tests(m)
		_finish()
		return
	for i in 1200:
		if m.nav_ready:
			break
		await frames(1)
	isolate_enemies([])
	var vs := get_tree().get_nodes_in_group("vehicles")
	check(vs.size() == 1, "Kübelwagen vorhanden")
	var v: Vehicle = vs[0]
	await seconds(2.0)
	var y0 := v.global_position.y
	await seconds(1.0)
	check(absf(v.global_position.y - y0) < 0.05 and v.linear_velocity.length() < 0.3, "Fahrzeug steht ruhig auf den Rädern", "y=%.2f" % v.global_position.y)

	# Einsteigen als Fahrer
	var hale := m.squad.leader()
	var entry: Interactable = v._entry
	hale.global_position = entry.global_position + v.global_basis.x * -0.6 + Vector3.UP * 0.3
	var d := entry.global_position - hale.global_position
	hale.look_yaw = atan2(-d.x, -d.z)
	await frames(10)
	check(m.controller.interact_target == entry, "Einstieg als Interaktion", str(m.controller.interact_target))
	await tap("interact")
	check(hale.vehicle == v and hale.seat_index == 0 and v.driver() == hale, "Spieler sitzt am Steuer")

	# Kamerad mit Folgebefehl steigt zu
	var kow: Soldier = m.squad.members[3]
	m.squad.brain_of(kow).set_order(SquadBrain.Order.FOLLOW)
	kow.global_position = v.global_position + v.global_basis.x * 2.5 + Vector3.UP * 0.3
	await seconds(1.5)
	check(kow.vehicle == v and kow.seat_index > 0, "Kamerad steigt als Mitfahrer zu", "Sitz %d" % kow.seat_index)

	# Fahren
	var p0 := v.global_position
	var yaw0 := v.global_rotation.y
	if Game.cli.has("debug_drive"):
		_watch(v, 5.0)
	await hold("move_forward", 3.0)
	var moved := p0.distance_to(v.global_position)
	check(moved > 5.0, "Fahrzeug fährt", "%.1f m in 3 s" % moved)
	check((v.global_position - p0).dot(v.global_basis.z) > 0.0, "Fahrtrichtung = Motorhaube voran (+Z)")
	check(hale.global_position.distance_to(v.seat_transform(0).origin) < 1.0, "Fahrer bewegt sich mit dem Fahrzeug")
	check(kow.global_position.distance_to(v.seat_transform(kow.seat_index).origin) < 1.0, "Mitfahrer bewegt sich mit")
	yaw0 = v.global_rotation.y
	Input.action_press("move_left")
	await hold("move_forward", 0.7)
	Input.action_release("move_left")
	var turned := angle_difference(yaw0, v.global_rotation.y)
	# positiver Yaw = Drehung nach links (gegen den Uhrzeigersinn von oben)
	check(turned > 0.15, "Lenken links dreht nach links", "%.0f°" % rad_to_deg(turned))
	# Bremsen (Handbremse = Leertaste)
	Input.action_press("stance_stand")
	await seconds(2.5)
	Input.action_release("stance_stand")
	check(v.speed_kmh() < 5.0, "Handbremse bringt das Fahrzeug zum Stehen", "%.1f km/h" % v.speed_kmh())

	# Motorgeräusch alarmiert Gegner in Hörweite
	var listener := enemy("e_road")
	var lb2 := listener.get_node("EnemyBrain") as EnemyBrain
	listener.set_physics_process(true)
	listener.get_node("Perception").set_physics_process(true)
	lb2.enabled = true
	listener.global_position = v.global_position + v.global_basis.z * 30.0 + Vector3.UP * 2.0
	lb2.home_pos = listener.global_position
	lb2.set_state(EnemyBrain.State.GUARD)
	await seconds(0.5)
	await hold("move_forward", 1.5)
	check(lb2.state != EnemyBrain.State.GUARD, "Motorgeräusch weckt Gegner", EnemyBrain.STATE_NAMES[lb2.state])
	lb2.enabled = false
	listener.die(null)
	Input.action_press("stance_stand")
	await seconds(2.0)
	Input.action_release("stance_stand")

	# Aussteigen: Fahrer lässt alle aussteigen, Kamerad folgt wieder zu Fuß
	await tap("interact")
	await seconds(1.0)
	check(hale.vehicle == null and v.driver() == null, "Spieler steigt aus")
	check(kow.vehicle == null, "Mitfahrer steigt mit aus")
	check(hale.is_on_floor(), "Ausgestiegener steht auf dem Boden")

	# Zerstörung
	v.on_bullet_hit(1000.0, null)
	await frames(5)
	check(v.wrecked and not entry.can_interact(hale), "Zerschossenes Fahrzeug ist Wrack")

	if not Game.cli.has("terrain_only"):
		await _physics_tests(m)
	_finish()


func _watch(v: Vehicle, secs: float) -> void:
	var f0 := Engine.get_physics_frames()
	while _since(f0) < secs:
		await get_tree().create_timer(0.25, true, true).timeout
		var ld: Array = []
		for w in v.drive.wheels:
			ld.append("%.0f/%.2f%s m%d" % [w.load, w.length, "*" if w.contact else "", w.mat])
		print("WATCH v=%.1f thr=%.2f st=%.2f ang=%.2f g=%d F=%.0f yaw=%.0f up=%.2f lin=%s %s" % [v.drive.speed * 3.6, v.drive.throttle,
			v.drive.steer_in, v.drive.steer_angle, v.drive.gear, v.drive.drive_force, rad_to_deg(v.global_rotation.y), v.global_basis.y.y, str(v.linear_velocity), str(ld)])


# --- Fahrphysik (VehicleDrive): Messfahrten auf einer ebenen Teststrecke ------------------------------------

const TRACK_Y := 400.0
## Fahrzeugtypen mit Originaldaten/-modell: [Bezeichnung, Mission (Cache), Akteur in vehicles.json, Modell]
const TYPES := [
	["Kübelwagen", "arctic1", "la_kubelW_", "la_kubelw"],
	["Jeep", "africa1", "la_Jeepsas_01", "la_jeepsas"],
	["BMW R75 mit Beiwagen", "africa1", "la_BmwR_", "la_bmwr75"],
	["Opel Blitz", "arctic3", "Opel_01", "la_opelwin"],
	["Bedford", "africa2_mp_zone", "la_Bedford_", "la_bedford"],
	["Halbkette Sd.Kfz. 251", "africa2_mp_zone", "la_hakl_Af_", "la_hakl_af"],
	["Panzer III", "africa1", "panzer01", "la_panzer iiiaf"],
	["Sherman", "africa2_mp_zone", "la_shermanAf_4", "la_shermanaf"],
	["Tiger", "africa2_mp_zone", "La_tiger_", "la_tiger"],
]
var _drv: Soldier
var _levels: Array = []


func _physics_tests(m: Mission) -> void:
	# Echtzeit: Engine.time_scale würde den Physikschritt vergrößern (explizite Federkräfte instabil)
	var t_start := Time.get_ticks_msec()
	_test_block(Vector3(0, TRACK_Y - 1.0, 0), Vector3(500, 1, 1400), 0.0)
	_drv = m.squad.members[2]
	m.squad.brain_of(_drv).set_order(SquadBrain.Order.HOLD)
	# 1) Platzhalter-Kübelwagen (Originalwerte Kübelwagen): Beschleunigung, Kurve, Bremsweg, Schnee vs. Straße
	var k := _spawn_car("Kübelwagen", {}, "", "", Vector3(-150, TRACK_Y, -600))
	await _board(k)
	k.drive.surface_override = 48             # „Cesta, silnice“
	var r := await _measure(k, true)
	check(r["t50"] > 0.0 and r["t50"] < 12.0, "Beschleunigung 0–50 km/h (Kübelwagen, Straße)", "%.1f s" % r["t50"])
	check(r["top"] > 70.0 and r["top"] < 100.0, "Höchstgeschwindigkeit aus Getriebe/Radradius", "%.0f km/h (berechnet %.0f)" % [r["top"], k.drive.top_speed * 3.6])
	check(r["min_up"] > 0.6 and r["corner_g"] > 0.4, "Kurvenfahrt mit Höchstgeschwindigkeit ohne Überschlag", "Querbeschl. %.2f g, Neigung min. up.y %.2f" % [r["corner_g"], r["min_up"]])
	check(r["brake50"] > 6.0 and r["brake50"] < 20.0, "Bremsweg 50→0 km/h (Straße)", "%.1f m" % r["brake50"])
	if Game.cli.has("quick"):
		Engine.time_scale = 1.0
		return
	var road_brake: float = r["brake50"]
	var road_g: float = r["corner_g"]
	await _reset_car(k, Vector3(-150, TRACK_Y, -600))
	k.drive.surface_override = 34             # „Sníh“
	var rs := await _measure(k, false)
	check(rs["brake50"] > road_brake * 1.5, "Grip: Bremsweg auf Schnee deutlich länger als auf Straße",
		"Schnee %.1f m / Straße %.1f m" % [rs["brake50"], road_brake])
	check(rs["corner_g"] < road_g * 0.75, "Grip: Kurvenhaftung auf Schnee geringer", "%.2f g / %.2f g" % [rs["corner_g"], road_g])
	# Handbremse: Heck bricht aus (Drift), Fahrzeug kommt kontrolliert zum Stehen
	await _reset_car(k, Vector3(-150, TRACK_Y, -600))
	k.drive.surface_override = 48
	k.throttle = 1.0
	while k.drive.speed * 3.6 < 50.0:
		await frames(1)
	k.throttle = 0.0
	k.steer_input = 0.6
	k.handbrake = true
	var yaw_hb := k.global_rotation.y
	var slip_max := 0.0
	var fh := Engine.get_physics_frames()
	while _since(fh) < 2.5:
		await frames(1)
		var vel := k.linear_velocity
		if vel.length() > 2.0:
			slip_max = maxf(slip_max, rad_to_deg(vel.normalized().angle_to(k.global_basis.z)))
	k.handbrake = false
	k.steer_input = 0.0
	var turn_hb := absf(rad_to_deg(angle_difference(yaw_hb, k.global_rotation.y)))
	check(slip_max > 12.0 and slip_max < 110.0 and turn_hb < 160.0 and k.global_basis.y.y > 0.8, "Handbremse: kontrollierter Drift ohne Überschlag", "Schwimmwinkel max. %.0f°, Drehung %.0f°" % [slip_max, rad_to_deg(angle_difference(yaw_hb, k.global_rotation.y))])
	# Rückwärtsgang
	await _reset_car(k, Vector3(-150, TRACK_Y, -600))
	k.throttle = -1.0
	await seconds(3.0)
	k.throttle = 0.0
	check(k.drive.gear == -1 and k.drive.speed < -2.0, "Rückwärtsgang", "%.1f km/h" % (k.drive.speed * 3.6))
	# 2) Skriptfahrt (HUMAN_Drive-Pfad) mit der Physik: L-förmige Route, Ziel < 2 m
	await _reset_car(k, Vector3(-150, TRACK_Y, -600))
	k.handbrake = false
	_drv.is_player_controlled = false
	var p0 := k.global_position
	var route := [p0 + Vector3(0, 0, 60), p0 + Vector3(0, 0, 110), p0 + Vector3(45, 0, 125), p0 + Vector3(80, 0, 125)]
	k.drive_path(route, 40.0)
	var t := 0.0
	var fd := Engine.get_physics_frames()
	while not k.drive_done() and t < 60.0:
		await frames(1)
		t = _since(fd)
	var dist: float = (k.global_position - route[3]).length()
	check(k.drive_done() and dist < 3.0 and t < 40.0, "Skriptfahrt (HUMAN_Drive) erreicht das Ziel physikalisch",
		"%.1f s, Abstand %.1f m, Fahrtrichtung %.0f°" % [t, dist, rad_to_deg(k.global_rotation.y)])
	await seconds(2.0)
	check(k.drive.speed < 0.5, "Skriptfahrt hält am Ziel an", "%.1f km/h" % (k.drive.speed * 3.6))
	_drv.is_player_controlled = true
	await _unboard(k)
	k.queue_free()
	# 3) Alle Fahrzeugtypen mit Originaldaten und -modell: Messwerte
	var x := -180.0
	for ty in TYPES:
		var data := _orig_data(ty[1], ty[2])
		var veh := _spawn_car(ty[0], data, ty[1], ty[3], Vector3(x, TRACK_Y, -600))
		x += 30.0
		if veh == null:
			continue
		await _board(veh)
		veh.drive.surface_override = 48
		var rr := await _measure(veh, true)
		var inf := veh.drive.info()
		var msg := "%s [%s, %s]: %.0f kg, %.0f PS, %d Räder, r=%.2f m | 0–30 %.1f s, 0–50 %s, Vmax %.0f km/h (Getriebe %.0f) | Bremsweg %s | Kurve %.2f g, up.y min %.2f" % [
			ty[0], inf["kind"], "Original" if not data.is_empty() else "Standard", inf["mass"], inf["power_ps"], inf["wheels"],
			inf["radius"], rr["t30"], ("%.1f s" % rr["t50"]) if rr["t50"] > 0.0 else "–", rr["top"], inf["top_kmh"],
			("%.1f m ab %.0f km/h" % [rr["brake50"], rr["brake_from"]]), rr["corner_g"], rr["min_up"]]
		print("MESSUNG " + msg + "  [%d s]" % ((Time.get_ticks_msec() - t_start) / 1000))
		check(rr["top"] > 10.0 and rr["min_up"] > 0.5 and rr["brake50"] > 0.0, "Fahrtest %s" % ty[0], msg)
		if veh.drive.kind == VehicleDrive.Kind.TANK:
			await _reset_car(veh, veh.global_position)
			var y0 := veh.global_rotation.y
			var q0 := veh.global_position
			veh.steer_input = 1.0
			await seconds(1.0)
			var y1 := veh.global_rotation.y
			await seconds(2.0)
			var rate := rad_to_deg(angle_difference(y1, veh.global_rotation.y)) / 2.0
			veh.steer_input = 0.0
			var moved := Vector2(veh.global_position.x - q0.x, veh.global_position.z - q0.z).length()
			print("MESSUNG %s dreht auf der Stelle: %.0f °/s, Versatz %.2f m" % [ty[0], rate, moved])
			check(rate > 12.0 and moved < 2.0, "%s dreht auf der Stelle (Kettenlenkung)" % ty[0], "%.0f °/s, Versatz %.2f m, gesamt %.0f°" % [rate, moved, rad_to_deg(angle_difference(y0, veh.global_rotation.y))])
		await _unboard(veh)
		veh.queue_free()
		await frames(2)
	for l in _levels:
		(l as OrigLevel).release()
	Engine.time_scale = 1.0


func _orig_data(mission_dir: String, actor: String) -> Dictionary:
	var p := OrigLevel.cache_path(mission_dir) + "/vehicles.json"
	if not FileAccess.file_exists(p):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(j) != TYPE_DICTIONARY:
		return {}
	return (j as Dictionary).get("vehicles", {}).get(actor, {})


func _spawn_car(label: String, data: Dictionary, mission_dir: String, model: String, pos: Vector3) -> Vehicle:
	var v := Vehicle.new()
	v.name = ("tv_" + label).validate_node_name()
	v.vehicle_name = label
	v.drive_model = model if model != "" else label
	v.drive_data = data
	if mission_dir != "" and model != "":
		var holder := Node3D.new()
		get_tree().current_scene.add_child(holder)
		var ol := OrigLevel.new(mission_dir, holder)
		_levels.append(ol)
		var vis := ol.model_instance(model)
		if vis:
			vis.rotation.y = PI
			v.custom_visual = vis
		elif data.is_empty():
			return null
	mission().dynamic_root.add_child(v)
	v.global_position = pos + Vector3.UP * 0.3
	v.global_rotation.y = 0.0
	return v


func _board(v: Vehicle) -> void:
	_drv.is_player_controlled = true
	v.board(_drv, true)
	v.freeze = false
	await seconds(1.5)


func _unboard(v: Vehicle) -> void:
	v.leave_all()
	_drv.is_player_controlled = false
	await frames(2)


func _reset_car(v: Vehicle, pos: Vector3) -> void:
	v.throttle = 0.0
	v.steer_input = 0.0
	v.handbrake = false
	v.global_transform = Transform3D(Basis(), pos + Vector3.UP * 0.3)
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	await seconds(1.5)


## Warten in simulierter Zeit (auch bei Engine.time_scale > 1 exakt)
func seconds(s: float) -> void:
	var f0 := Engine.get_physics_frames()
	while _since(f0) < s:
		await get_tree().physics_frame


## Simulierte Zeit (Physikschritte) – unabhängig von Engine.time_scale
func _since(f0: int) -> float:
	return float(Engine.get_physics_frames() - f0) / 60.0


## Messfahrt: Vollgas bis Vmax (bzw. 30 s), Vollkurve 3 s bei Vmax (Querbeschleunigung, Kippen), dann
## Neustart, auf min(50 km/h, 95 % Vmax) beschleunigen und voll bremsen (Bremsweg, auf 50 km/h normiert)
func _measure(v: Vehicle, full: bool) -> Dictionary:
	var res := {"t30": -1.0, "t50": -1.0, "top": 0.0, "corner_g": 0.0, "min_up": 1.0, "brake50": 0.0, "brake_from": 0.0}
	var start := v.global_position
	var dt := 1.0 / 60.0
	var t := 0.0
	var flat := 0.0
	var vmax := 0.0
	var t_best := 0.0
	v.throttle = 1.0
	var f0 := Engine.get_physics_frames()
	while t < (30.0 if full else 12.0):
		await frames(1)
		t = _since(f0)
		var kmh := v.drive.speed * 3.6
		if res["t30"] < 0.0 and kmh >= 30.0:
			res["t30"] = t
		if res["t50"] < 0.0 and kmh >= 50.0:
			res["t50"] = t
		if kmh > vmax + 0.3:
			vmax = kmh
			t_best = t
		flat = t - t_best
		res["min_up"] = minf(res["min_up"], v.global_basis.y.y)
		if Game.cli.has("debug_drive") and Engine.get_physics_frames() % 30 < 2:
			var ld: Array = []
			for w in v.drive.wheels:
				ld.append("%.0f/%.2f%s" % [w.load, w.length, "*" if w.contact else ""])
			print("DBG t=%.1f v=%.1f g=%d rpm=%.0f F=%.0f up=%.2f y=%.2f lin=%s %s" % [t, kmh, v.drive.gear, v.drive.rpm, v.drive.drive_force, v.global_basis.y.y, v.global_position.y, str(v.linear_velocity), str(ld)])
		if flat > 2.5 or (not full and kmh > 52.0):
			break
	res["top"] = vmax
	# Vollkurve bei Höchstgeschwindigkeit
	var acc := 0.0
	var n := 0
	v.steer_input = 1.0
	var fc := Engine.get_physics_frames()
	while _since(fc) < 3.0:
		await frames(1)
		if _since(fc) > 1.0:
			# Querbeschleunigung im stationären Kreis: Bahngeschwindigkeit × Gierrate
			acc += absf(v.angular_velocity.dot(v.global_basis.y)) * Vector2(v.linear_velocity.x, v.linear_velocity.z).length()
			n += 1
		res["min_up"] = minf(res["min_up"], v.global_basis.y.y)
	res["corner_g"] = acc / maxf(n, 1) / VehicleDrive.G
	v.steer_input = 0.0
	v.throttle = 0.0
	# Bremsweg
	await _reset_car(v, start)
	var target := minf(50.0, vmax * 0.95)
	v.throttle = 1.0
	t = 0.0
	f0 = Engine.get_physics_frames()
	while v.drive.speed * 3.6 < target and t < 40.0:
		await frames(1)
		t = _since(f0)
	var v0 := v.drive.speed
	var p0 := v.global_position
	v.throttle = -1.0
	t = 0.0
	f0 = Engine.get_physics_frames()
	while v.drive.speed > 0.8 and t < 20.0:
		await frames(1)
		t = _since(f0)
	v.throttle = 0.0
	var d := Vector2(v.global_position.x - p0.x, v.global_position.z - p0.z).length() + 0.8 * 0.8 / 10.0
	res["brake_from"] = v0 * 3.6
	res["brake50"] = d * pow(50.0 / maxf(v0 * 3.6, 1.0), 2.0) if v0 * 3.6 < 49.0 else d
	await seconds(1.0)
	await _reset_car(v, start)
	return res
