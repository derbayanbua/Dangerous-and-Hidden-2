extends Node
## Tageszyklus, Raumlicht, Laternen und echte OG-Fenster der Karte Bavaria.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_daynight
## Prüft: Raumliste aus dem Bau gegen Leuchten (kein Raum ohne Licht, Licht im Raum), Tag/Dämmerung/Nacht-Schaltung,
## Zyklus läuft, Laternen (freie Standorte, Kollision am Mast, keine Schatten), OG-Fenster (Sicht/Schuss frei,
## Bewegungssperre, Standplatz, Navmesh, echtes Projektil), Lichtbudget.
var failed := 0
var passed := 0

class WindowTarget extends StaticBody3D:
	var received_hit := false
	func on_bullet_hit(_damage: float, _shooter: Node) -> void:
		received_hit = true

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (300 s)")
		_finish())

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	print("ERGEBNIS test_bavaria_daynight: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var dn = m.day_night
	check(dn != null and String(dn.name) == "Tageszeit" and dn.get_parent() == m, "Tageszyklus-Knoten „Tageszeit“ an fester Stelle")
	_rooms(m)
	_lamps(m)
	await _og_windows(m)
	await _cycle(m)
	_budget(m)
	_finish()

# --- Raumlicht --------------------------------------------------------------------------------------------
func _rooms(m: Mission) -> void:
	var rl = m.room_lighting
	var inventory: Array = rl.collect_rooms()
	check(inventory.size() >= 155, "Raumliste aus dem Bau vollständig erfasst: %d Räume" % inventory.size())
	check(rl.coverage.size() == inventory.size(), "Je Raum genau eine Leuchte (%d Leuchten / %d Räume)" % [rl.coverage.size(), inventory.size()])
	var keys := {}
	for c in rl.coverage:
		keys[String(c.house) + "/" + String(c.room)] = c
	var missing: Array[String] = []
	var outside_room: Array[String] = []
	for r in inventory:
		var key := String(r.house) + "/" + String(r.room)
		if not keys.has(key):
			missing.append(key)
			continue
		var c: Dictionary = keys[key]
		var light: OmniLight3D = c.light
		var fixture: Node3D = c.fixture
		if not (light.omni_range >= 4.0 and fixture.get_child_count() >= 3):
			outside_room.append(key + " (Modell/Licht unvollständig)")
		var floor_y: float = (r.parent as Node3D).to_global(Vector3(0, r.floor, 0)).y
		var h := light.global_position.y - floor_y
		if h < 1.0 or h > 2.6:
			outside_room.append(key + " (Höhe %.2f)" % h)
		if r.has("rect"):
			var local: Vector3 = (r.parent as Node3D).to_local(light.global_position)
			if not (r.rect as Rect2).grow(0.05).has_point(Vector2(local.x, local.z)):
				outside_room.append(key + " (außerhalb der Raumfläche)")
	for k in missing:
		print("RAUM OHNE LICHT ", k)
	for k in outside_room:
		print("LEUCHTE FALSCH ", k)
	check(missing.is_empty(), "Kein Raum ohne Lichtquelle (%d fehlend)" % missing.size())
	check(outside_room.is_empty(), "Jede Leuchte mit Modell und Licht im eigenen Raum (%d Abweichungen)" % outside_room.size())
	var roles := {}
	for r in inventory:
		roles[String(r.room).split("_")[0] if String(r.room).begins_with("Keller") else String(r.room)] = true
	var names: Array = []
	for r in inventory:
		names.append(String(r.room))
	check(names.any(func(n): return n.contains("WC_Bad")), "Bad/WC beleuchtet")
	check(names.has("Keller_West") and names.has("Keller_Ost"), "Keller Haus 16 beleuchtet (zwei Hälften)")
	check(names.any(func(n): return n.begins_with("Flur_")) and names.has("ObergeschossFlur") and names.has("Treppenpodest"),
		"Flure, OG-Flur und Treppenpodest beleuchtet")
	check(names.has("Anbau") and names.has("Innenraum") and names.has("Kulisse"), "Anbauten, Scheunen/Schuppen/Ruinen und Kulissenhäuser beleuchtet")
	# Jedes Gebäude (begehbar oder Kulisse) hat mindestens eine Leuchte
	var houses := {}
	for c in rl.coverage:
		houses[String(c.house)] = true
	var all_houses: Array = m.get_tree().get_nodes_in_group("bavaria_buildings") + m.get_tree().get_nodes_in_group("bavaria_reference_extensions")
	var dark: Array[String] = []
	for h in all_houses:
		if not houses.has(String(h.name)):
			dark.append(String(h.name))
	check(dark.is_empty(), "Jedes Gebäude mit Licht (ohne: %s)" % ", ".join(dark))
	var holder_ok := true
	for c in rl.coverage:
		var light: OmniLight3D = c.light
		holder_ok = holder_ok and light.distance_fade_enabled and light.distance_fade_begin <= 20.0
	check(holder_ok, "Raumlichter mit Entfernungsausblendung (≤ 20 m)")

# --- Laternen ---------------------------------------------------------------------------------------------
func _lamps(m: Mission) -> void:
	var sl = m.street_lamps
	var poles: Array = sl.lamps.filter(func(l): return l.get_meta("kind") == "pole")
	var walls: Array = sl.lamps.filter(func(l): return l.get_meta("kind") == "wall")
	check(poles.size() >= 12, "Mastlaternen entlang der Wege: %d" % poles.size())
	check(walls.size() >= 12, "Wandleuchten an den Haustüren: %d" % walls.size())
	var roads := {}
	for p in poles:
		roads[String(p.get_meta("road"))] = true
	check(roads.has("dorfrand") and roads.has("haeuserzeile"), "Beide Dorfwege beleuchtet")
	var space := m.get_world_3d().direct_space_state
	var bad: Array[String] = []
	for p in poles:
		var pole := p as StaticBody3D
		var pos := pole.global_position
		var q := Vector2(pos.x, pos.z)
		# Abstand zu Wegen, Starts, Zonenmitten, Türen und Fensterplätzen
		for road in m.layout["paths"]:
			var pts: Array = road["points"]
			for i in pts.size() - 1:
				var a: Vector3 = m.pixel(pts[i])
				var b: Vector3 = m.pixel(pts[i + 1])
				if Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(q) < float(road.width) * 0.5 + 0.3:
					bad.append(pole.name + " auf Weg " + String(road.id))
		for s in m.layout["spawns"]:
			if m.pixel(s["pixel"]).distance_to(Vector3(pos.x, 0, pos.z)) < 2.9:
				bad.append(pole.name + " an Start")
		for z in m.layout.get("occupation_zones", []):
			if m.pixel(z["pixel"]).distance_to(Vector3(pos.x, 0, pos.z)) < 3.4:
				bad.append(pole.name + " an Zonenmitte")
		for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
			for w in house.get_meta("shooting_windows", []):
				var wp: Vector3 = house.to_global(w)
				if Vector2(wp.x, wp.z).distance_to(q) < 2.5:
					bad.append(pole.name + " vor Fensterplatz " + house.name)
			for e in house.get_meta("entry_points", []):
				var ep: Vector3 = house.to_global(e.point + e.normal * 1.0)
				if Vector2(ep.x, ep.z).distance_to(q) < 2.3:
					bad.append(pole.name + " vor Tür " + house.name)
		check(m.inside_map(pos), "Laterne innerhalb der Spielgrenze: " + pole.name)
		# Kollision am Mast vorhanden (Ebene Welt) und Mast steht frei (keine Überschneidung mit anderer Geometrie)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0.6, 1.2, 0), pos + Vector3(-0.6, 1.2, 0), 1))
		check(not hit.is_empty() and hit.collider == pole, "Mast hat Kollision: " + pole.name)
		var query := PhysicsShapeQueryParameters3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.16
		cyl.height = 3.2
		query.shape = cyl
		query.transform = Transform3D(Basis(), pos + Vector3.UP * 1.75)
		query.collision_mask = 1 | 16
		query.exclude = [pole.get_rid()]
		var overlaps := space.intersect_shape(query, 8)
		for o in overlaps:
			bad.append(pole.name + " schneidet " + str(o.collider.get_path()))
	for b in bad:
		print("LATERNE BLOCKIERT ", b)
	check(bad.is_empty(), "Laternen blockieren keine Wege/Starts/Zonen/Türen/Fensterplätze und schneiden nichts (%d)" % bad.size())
	var shadows := 0
	for l in sl.lights:
		shadows += int((l as OmniLight3D).shadow_enabled)
	check(shadows == 0 and sl.lights.size() == sl.lamps.size(), "Je Laterne ein Licht, alle ohne Schatten")
	# Navmesh um die Masten: Weg an der Laterne vorbei bleibt erreichbar
	var nav := m.get_world_3d().navigation_map
	var blocked := 0
	for p in poles:
		var pos: Vector3 = p.global_position
		var road_dir: Vector3 = -(p as Node3D).global_basis.z
		var a := NavigationServer3D.map_get_closest_point(nav, pos + road_dir * 1.6 + (p as Node3D).global_basis.x * 2.0)
		var b := NavigationServer3D.map_get_closest_point(nav, pos + road_dir * 1.6 - (p as Node3D).global_basis.x * 2.0)
		var path := NavigationServer3D.map_get_path(nav, a, b, true)
		if path.size() < 2 or path[-1].distance_to(b) > 0.5:
			blocked += 1
	check(blocked == 0, "Weg neben jeder Laterne begehbar (Navmesh), blockiert: %d" % blocked)

# --- OG-Fenster -------------------------------------------------------------------------------------------
func _og_windows(m: Mission) -> void:
	var space := m.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var targets: Array = []
	var shots: Array = []
	var total := 0
	for name in ["haus_16", "haus_18_shed"]:
		var house := m.static_root.get_node_or_null(name) as Node3D
		check(house != null, "Treppenhaus vorhanden: " + name)
		if house == null:
			continue
		var places: Array = house.get_meta("og_shooting_windows", [])
		check(places.size() >= 4, "Echte OG-Fenster mit Öffnung: %s %d" % [name, places.size()])
		for i in places.size():
			var wv: Vector3 = places[i]
			var side := signf(wv.z)
			var label := "%s OG-Fenster %d" % [name, i + 1]
			var eye_y := wv.y + 1.5
			var inside := house.to_global(Vector3(wv.x, eye_y, wv.z - side * 0.9))
			var outside := house.to_global(Vector3(wv.x, eye_y, wv.z + side * 1.2))
			var sight := PhysicsRayQueryParameters3D.create(inside, outside, Ballistics.MASK)
			sight.collide_with_areas = true
			var hit := space.intersect_ray(sight)
			if not hit.is_empty():
				print("OG SICHT ", label, " ", hit.collider.get_path())
			check(hit.is_empty(), "Blick/Schuss nach draußen frei: " + label)
			var back := space.intersect_ray(PhysicsRayQueryParameters3D.create(outside, inside, Ballistics.MASK))
			check(back.is_empty(), "Von außen hineinsehen: " + label)
			var stop := space.intersect_ray(PhysicsRayQueryParameters3D.create(inside, outside, LevelBuilder.FENCE_LAYER))
			check(not stop.is_empty() and stop.collider.is_in_group("bavaria_og_window_stops"), "Bewegungssperre in der Öffnung (nicht hinausfallen): " + label)
			var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(house.to_global(Vector3(wv.x, wv.y + 0.5, wv.z - side * 0.9)),
				house.to_global(Vector3(wv.x, wv.y + 0.5, wv.z + side * 1.2)), 1))
			check(not below.is_empty(), "Brüstung unter dem OG-Fenster: " + label)
			var standing := PhysicsShapeQueryParameters3D.new()
			standing.shape = capsule
			standing.collision_mask = 1 | 16
			standing.transform = Transform3D(Basis(), house.to_global(Vector3(wv.x, wv.y + 1.2, wv.z - side * 0.75)))
			var usable := space.intersect_shape(standing).is_empty()
			if usable:
				total += 1
				var target := WindowTarget.new()
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(0.8, 0.8, 0.1)
				shape.shape = box
				target.add_child(shape)
				m.add_child(target)
				target.global_position = house.to_global(Vector3(wv.x, eye_y, wv.z + side * 1.4))
				target.global_basis = house.global_basis
				targets.append(target)
				shots.append([house, inside, (target.global_position - inside).normalized(), label])
			else:
				print("OG-FENSTER OHNE STANDPLATZ (Treppe/Möbel) ", label)
		var glass_ok := false
		for n in house.find_children("OG_Fenster_offen", "Node3D", true, false):
			glass_ok = true
		check(glass_ok, "Glas/Rahmen der offenen OG-Fenster gebaut: " + name)
	check(total >= 6, "Mindestens sechs nutzbare OG-Fensterplätze (frei für Soldatenkapsel): %d" % total)
	var hints: Array = m._bot_hint_data().hints.filter(func(h): return h.get("upper", false))
	check(hints.size() >= 4, "Bot-Hinweise für OG-Fensterplätze am Navmesh: %d" % hints.size())
	await get_tree().physics_frame
	var weapon := WeaponData.new()
	weapon.muzzle_velocity = 750.0
	weapon.damage = 10.0
	weapon.falloff_start = 100.0
	for shot in shots:
		Ballistics.fire(shot[0], shot[1], shot[2], weapon, [], -1)
	await get_tree().create_timer(0.25).timeout
	for i in targets.size():
		check(targets[i].received_hit, "Echtes Projektil durch " + String(shots[i][3]))
		targets[i].queue_free()

# --- Tageszyklus ------------------------------------------------------------------------------------------
func _cycle(m: Mission) -> void:
	var dn = m.day_night
	var rl = m.room_lighting
	var sl = m.street_lamps
	dn.set_hour(12.0, 0.0)
	await get_tree().process_frame
	var st: Dictionary = dn.state()
	check(dn.phase() == "tag" and st.daylight > 0.9 and m.sun.light_energy > 0.9 and not st.moon, "Mittag: Tag, Sonne hoch und hell")
	check(rl.lights_on() == 0 and sl.lights_on() == 0, "Tagsüber Raumlichter und Laternen aus")
	check(is_equal_approx(m.light_factor, 1.0), "Wahrnehmung am Tag unverändert")
	check(m.sun.global_basis.z.y < -0.5 or (-m.sun.global_basis.z).y < -0.5, "Sonne steht hoch (Licht fällt steil)")
	var day_amb: float = m.env.ambient_light_energy
	dn.set_hour(19.35, 0.0)
	await get_tree().process_frame
	check(dn.phase() == "daemmerung" and rl.lights_on() == rl.coverage.size() and sl.lights_on() == sl.lights.size(),
		"Abenddämmerung: alle Raumlichter und Laternen an")
	dn.set_hour(0.5, 0.0)
	await get_tree().process_frame
	st = dn.state()
	check(dn.phase() == "nacht" and st.moon and m.sun.light_energy < 0.1, "Nacht: Mondlicht schwach")
	check(rl.lights_on() == rl.coverage.size() and sl.lights_on() == sl.lights.size(), "Nachts alle Lichter an")
	check(m.env.ambient_light_energy < day_amb * 0.5, "Nachts deutlich weniger Umgebungslicht")
	check(m.light_factor < 0.6, "Wahrnehmung nachts eingeschränkt (light_factor %.2f)" % m.light_factor)
	var sky := m.env.sky.sky_material if m.env.sky else null
	if sky is ShaderMaterial:
		check(float(sky.get_shader_parameter("night")) > 0.9, "Alpenhimmel-Shader nachts getönt")
	dn.set_hour(6.0, 0.0)
	await get_tree().process_frame
	var to_sun: Vector3 = dn.state().to_sun
	var east: Vector3 = Vector3(m.scene_details.south.z, 0, -m.scene_details.south.x)
	check(Vector2(to_sun.x, to_sun.z).normalized().dot(Vector2(east.x, east.z).normalized()) > 0.9, "Morgens Sonne im Osten")
	# Zyklus läuft: 1 min je Tag → 3 s ≈ 1,2 h
	dn.set_hour(10.0, 1.0)
	await get_tree().create_timer(3.0).timeout
	check(dn.hour > 10.6 and dn.hour < 12.0, "Zyklus läuft (1 min/24 h): %.2f h nach 3 s" % dn.hour)
	dn.set_hour(dn.hour, 0.0)
	var h0: float = dn.hour
	await get_tree().create_timer(1.0).timeout
	check(is_equal_approx(dn.hour, h0), "Zyklus 0 = feste Zeit")

func _budget(m: Mission) -> void:
	var lights := m.find_children("*", "Light3D", true, false)
	var shadowed := 0
	var omni := 0
	for l in lights:
		if l is OmniLight3D or l is SpotLight3D:
			omni += 1
			shadowed += int(l.shadow_enabled)
			if not l.distance_fade_enabled:
				print("LICHT OHNE AUSBLENDUNG ", l.get_path())
	print("LICHTBUDGET: %d Punkt-/Spotlichter, davon %d mit Schatten" % [omni, shadowed])
	check(shadowed <= m.room_lighting.coverage.size(), "Schatten nur bei Raumlichtern (%d)" % shadowed)
	check(lights.filter(func(l): return (l is OmniLight3D or l is SpotLight3D) and not l.distance_fade_enabled).is_empty(),
		"Alle Punktlichter mit Entfernungsausblendung")
