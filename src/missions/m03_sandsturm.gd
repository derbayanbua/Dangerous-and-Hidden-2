extends Mission
## Mission 3 "Unternehmen Sandsturm" (eigenständiger Inhalt).
## Libyen, Oktober 1942, Tag. Oase mit Stab des Afrikakorps und Flak-Stellungen.
## Schwerpunkte: Tarnung in Feinduniform (Original: Mission_SetUniformDisguise),
## Tageslicht (Lichtfaktor 1.0), weite Distanzen, Fahrzeuge zur Flucht.
##
## Norden = -Z. Oase-Mitte (0, -10), Start Dünen Ost (110, 55),
## einzelner Vorposten (75, 35), Sammelpunkt Südwest (-105, 100).

var flak_sites: Array[ChargeSite] = []
var plans: Pickups.Item
var _rp_smoke: OmniLight3D
var _hint := false


func _configure_environment(e: Environment, s: DirectionalLight3D) -> void:
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.36, 0.52, 0.78)
	sm.sky_horizon_color = Color(0.86, 0.8, 0.68)
	sm.ground_horizon_color = Color(0.78, 0.68, 0.5)
	e.fog_light_color = Color(0.9, 0.82, 0.66)
	e.fog_density = 0.0016
	e.ambient_light_energy = 0.9
	e.tonemap_exposure = 0.95
	s.rotation_degrees = Vector3(-58, -35, 0)   # hoch stehende Mittagssonne
	s.light_color = Color(1.0, 0.95, 0.85)
	s.light_energy = 1.7


func _build_world() -> void:
	light_factor = 1.0
	enemy_uniform = Color(0.62, 0.55, 0.38)        # Khaki (Afrikakorps)
	alarm_bell_pos = Vector3(-2, 4.0, -12)
	lb.color_ground = Color(0.84, 0.72, 0.5)
	lb.color_ground2 = Color(0.78, 0.66, 0.45)
	lb.color_road = Color(0.66, 0.57, 0.42)
	lb.color_foliage = Color(0.26, 0.36, 0.16)
	lb.noise.seed = 1942
	lb.noise.frequency = 0.009
	lb.height_scale = 1.5
	lb.flatten_zones = [
		[Vector3(0, 1.0, -10), 42.0, 0],
		[Vector3(110, 2.0, 55), 10.0, 0],
		[Vector3(75, 1.5, 35), 8.0, 0],
		[Vector3(-105, 1.0, 100), 12.0, 0],
	]
	lb.roads = [PackedVector2Array([Vector2(130, -15), Vector2(40, -12), Vector2(0, -8), Vector2(-40, 10), Vector2(-105, 100)])]
	lb.build_terrain()
	_build_oasis()
	_build_flak()
	_build_outpost()
	_build_rally_point()


func _build_oasis() -> void:
	var y := 1.0
	# Lehmbauten mit Flachdach
	lb.building(Vector3(-4, y, -16), 12.0, 8.0, 3.4, "sandstone", "sandstone", [["s", 2.0], ["e", 0.0]], true, 0.0, [], true)
	for b in [[Vector3(12, y, -20), 7.0, 6.0, [["w", 0.0]]], [Vector3(-20, y, -4), 6.0, 6.0, [["e", 0.0]]],
			[Vector3(14, y, 2), 8.0, 5.0, [["n", 0.0]]], [Vector3(-16, y, 12), 6.0, 7.0, [["n", 0.0]]],
			[Vector3(4, y, 14), 5.0, 5.0, [["w", 0.0]]]]:
		lb.building(b[0], b[1], b[2], 3.0, "sandstone", "sandstone", b[3], true, 0.0, [], true)
	# Kartentisch mit Lageplänen im Stabsquartier
	lb.box(Vector3(-7, y, -18), Vector3(1.8, 0.8, 1.0), "darkwood")
	plans = Pickups.Item.new()
	plans.item_name = "Lagepläne"
	plans.persistent_id = "plans"
	plans.color = Color(0.85, 0.82, 0.7)
	plans.mesh_size = Vector3(0.5, 0.03, 0.35)
	dynamic_root.add_child(plans)
	plans.global_position = Vector3(-7, y + 0.8, -18)
	# Wasserstelle mit Palmen
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 10)
	w.mesh = pm
	w.material_override = lb.mat("water")
	w.position = Vector3(-14, y - 0.35, -28)
	static_root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 22:
		var a := TAU * i / 22.0 + rng.randf() * 0.2
		var r := rng.randf_range(9.0, 14.0)
		lb.palm(-14 + cos(a) * r, -28 + sin(a) * r * 0.8, rng.randf_range(0.8, 1.2), rng.randf_range(-0.25, 0.25))
	for i in 18:
		lb.palm(rng.randf_range(-35, 35), rng.randf_range(-40, 25), rng.randf_range(0.8, 1.1), rng.randf_range(-0.2, 0.2))
	# Deckung: Fässer, Kisten, Sandsäcke, Mauerreste
	for p in [Vector3(6, y, -6), Vector3(7, y, -5), Vector3(-10, y, 2), Vector3(20, y, -8)]:
		lb.cylinder(p, 0.35, 1.0, "tank")
	lb.crate(Vector3(-2, y, 6), 1.1)
	lb.crate(Vector3(22, y, 6), 1.0, 0.3)
	lb.line_wall(Vector2(-30, -45), Vector2(-5, -48), 1.4, 0.6, "sandstone", [[12.0, 2.0]])
	lb.line_wall(Vector2(28, 22), Vector2(40, 8), 1.2, 0.6, "sandstone")
	# Fuhrpark: zwei Kübelwagen
	spawn_vehicle(Vector3(-4, y, 24), deg_to_rad(180), "veh_pool1")
	spawn_vehicle(Vector3(1, y, 24), deg_to_rad(180), "veh_pool2")
	var ammo := Pickups.AmmoCrate.new()
	ammo.persistent_id = "ammo_oasis"
	dynamic_root.add_child(ammo)
	ammo.global_position = Vector3(16, y, -1)


func _build_flak() -> void:
	var y := 1.0
	var names := ["Flak Ost", "Flak West", "Flak Nord"]
	var spots := [Vector3(30, y, 8), Vector3(-34, y, 14), Vector3(10, y, -44)]
	for i in 3:
		var p: Vector3 = spots[i]
		var gun := Node3D.new()
		static_root.add_child(gun)
		# Sandsackring
		for k in 6:
			var a := TAU * k / 6.0
			lb.sandbags(p + Vector3(cos(a), 0, sin(a)) * 4.2, 3.6, -a + PI * 0.5)
		# Lafette (Kreuz), Schild, Rohr
		lb.box(p, Vector3(5.0, 0.4, 0.5), "tank", 0.0, true, gun)
		lb.box(p, Vector3(0.5, 0.4, 5.0), "tank", 0.0, true, gun)
		lb.box(p + Vector3(0, 0.4, 0), Vector3(1.4, 1.2, 1.4), "tank", 0.0, true, gun)
		lb.box(p + Vector3(0, 1.1, -0.6), Vector3(2.2, 1.4, 0.1), "tank", 0.0, true, gun)
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.14
		cm.height = 5.5
		barrel.mesh = cm
		barrel.material_override = lb.mat("tank")
		gun.add_child(barrel)
		barrel.global_position = p + Vector3(0, 2.6, -1.8)
		barrel.rotation.x = -0.75
		var site := ChargeSite.new()
		site.target_name = names[i]
		site.persistent_id = "flak_%d" % i
		site.fuse = 25.0
		site.target_node = gun
		dynamic_root.add_child(site)
		site.global_position = p + Vector3(0, 0, 1.2)
		flak_sites.append(site)


func _build_outpost() -> void:
	# Einzelner Vorposten auf der Düne: Gelegenheit, eine Uniform zu erbeuten
	var c := lb.ground(75, 35)
	lb.sandbags(c + Vector3(0, 0, -2.2), 3.0, 0.0)
	lb.sandbags(c + Vector3(-1.6, 0, -0.8), 2.0, PI * 0.5)
	lb.box(c + Vector3(2.5, 0, 1.5), Vector3(2.0, 1.4, 1.6), "sandbag")   # Zeltplane über Kisten


func _build_rally_point() -> void:
	extraction_pos = lb.ground(-105, 100)
	extraction_radius = 10.0
	lb.box(extraction_pos + Vector3(4, 0, 0), Vector3(1.2, 1.0, 1.2), "wood")
	_rp_smoke = OmniLight3D.new()
	_rp_smoke.light_color = Color(1.0, 0.6, 0.2)
	_rp_smoke.light_energy = 0.0
	_rp_smoke.omni_range = 14.0
	dynamic_root.add_child(_rp_smoke)
	_rp_smoke.global_position = extraction_pos + Vector3.UP * 2.0


func _spawn_actors() -> void:
	var start := lb.ground(110, 55)
	spawn_roster(start, deg_to_rad(80), [Vector3(0, 0, 0), Vector3(-2, 0, 3), Vector3(2, 0, 3), Vector3(0, 0, 6)])
	var y := 1.0
	var g := func(x: float, z: float) -> Vector3: return lb.ground(x, z)
	# Vorposten (allein, mit Blick nach Osten)
	spawn_enemy(g.call(75, 34), deg_to_rad(-80), ["kar98k", "", ""], "s_outpost", {"sight": 70})
	# Flak-Bedienungen
	spawn_enemy(Vector3(31.5, y, 9.5), deg_to_rad(-90), ["kar98k", "", ""], "s_flak_e", {"sight": 75})
	spawn_enemy(Vector3(-35.5, y, 15.5), deg_to_rad(90), ["kar98k", "", ""], "s_flak_w", {"sight": 75})
	spawn_enemy(Vector3(11.5, y, -45.5), 0.0, ["mp40", "", ""], "s_flak_n", {"sight": 70})
	spawn_enemy(Vector3(28.5, y, 6.0), deg_to_rad(-60), ["mp40", "", "m24"], "s_flak_e2", {"sight": 60, "mode": "aggressive"})
	# Stab
	spawn_enemy(Vector3(-8.5, y, -16.5), deg_to_rad(-90), ["", "p08", ""], "s_officer", {"sight": 30, "officer": true})
	spawn_enemy(Vector3(-2, y, -11.3), PI, ["mp40", "", ""], "s_hq_door", {"sight": 45})
	spawn_enemy(Vector3(2, y, -16.5), PI * 0.5, ["kar98k", "", ""], "s_hq_east", {"sight": 45})
	# Streifen durch die Oase
	spawn_enemy(Vector3(0, y, 0), 0.0, ["mp40", "", "m24"], "s_patrol1", {"sight": 55, "mode": "aggressive",
		"patrol": PackedVector3Array([Vector3(0, y, 0), Vector3(20, y, -10), Vector3(5, y, -30), Vector3(-22, y, -15), Vector3(-10, y, 8)])})
	spawn_enemy(Vector3(-20, y, 20), 0.0, ["kar98k", "", ""], "s_patrol2", {"sight": 55,
		"patrol": PackedVector3Array([Vector3(-20, y, 20), Vector3(15, y, 18), Vector3(30, y, -20), Vector3(-30, y, -30)])})
	# Fuhrpark-Wache und Wasserstelle
	spawn_enemy(Vector3(-1.5, y, 20.5), PI, ["kar98k", "", ""], "s_pool", {"sight": 50})
	spawn_enemy(Vector3(-14, y, -20), 0.3, ["", "p08", ""], "s_water", {"sight": 35})
	# Außenposten Straße Ost und Düne Süd
	spawn_enemy(g.call(48, -13), deg_to_rad(-90), ["stg44", "", "m24"], "s_road", {"sight": 70, "mode": "aggressive"})
	spawn_enemy(g.call(0, 40), PI, ["kar98k", "", ""], "s_south", {"sight": 70,
		"patrol": PackedVector3Array([g.call(0, 40), g.call(-30, 45), g.call(25, 42)])})
	# Dachposten (Scharfschütze) auf dem Stabsquartier
	spawn_enemy(Vector3(-1, y + 3.65, -18), deg_to_rad(120), ["kar98k", "", ""], "s_roof",
		{"sight": 90, "stationary": true, "skill": 0.7})


func _setup_objectives() -> void:
	for i in flak_sites.size():
		var id := StringName("flak_%d" % i)
		add_objective(id, "%s sprengen" % flak_sites[i].target_name)
		flak_sites[i].destroyed.connect(complete_objective.bind(id))
	add_objective(&"plans", "Lagepläne aus dem Stabsquartier sichern")
	add_objective(&"extract", "Sammelpunkt in der Wüste (Südwest) erreichen")
	add_objective(&"stealth", "Keinen Alarm auslösen", true)
	plans.used.connect(func(_s): complete_objective(&"plans"))


func _on_alarm() -> void:
	fail_objective(&"stealth")


func _on_tick(_delta: float) -> void:
	if required_done(&"extract"):
		_rp_smoke.light_energy = 3.0 + sin(elapsed * 5.0)
		if not _hint:
			_hint = true
			Events.say("Ziele erfüllt — zum Sammelpunkt im Südwesten! Die Kübelwagen stehen im Fuhrpark.", 5.0)
		var alive := squad.alive_members()
		var inside := 0
		for m in alive:
			if Vector2(m.global_position.x - extraction_pos.x, m.global_position.z - extraction_pos.z).length() < extraction_radius:
				inside += 1
		if alive.size() > 0 and inside == alive.size():
			complete_objective(&"extract")
			if objective(&"stealth").state == Objective.State.ACTIVE:
				complete_objective(&"stealth")
			finish(true, "Flak ausgeschaltet, Pläne gesichert. %d von %d Männern zurück." % [alive.size(), squad.members.size()])
