extends Mission
## Mission 2 "Unternehmen Nordlicht" (eigenständiger Inhalt).
## Norwegen, Winter 1943, Nacht. Treibstofflager der Kriegsmarine am Fjord.
## Neue Mechaniken: Nacht (Lichtfaktor 0.5), Laternen und schwenkende
## Suchscheinwerfer (wer im Licht steht, wird schnell entdeckt; Scheinwerfer
## können ausgeschossen werden), Stacheldraht (blockiert Bewegung, nicht Sicht),
## Befreiung und Eskorte eines Gefangenen.
##
## Norden = -Z. Lager-Mitte (0, -20), Start Wald Südwest (-70, 100),
## Abholung Boot am Ufer (-10, -84).

var depot_a: ChargeSite
var depot_b: ChargeSite
var prisoner: Soldier
var prisoner_brain: EscortBrain
var _boat_light: OmniLight3D
var _hint := false


class ReleaseSpot extends Interactable:
	var brain: EscortBrain

	func _ready() -> void:
		super._ready()
		prompt = "Gefangenen befreien"

	func can_interact(_s: Soldier) -> bool:
		return enabled and brain and not brain.released and brain.soldier.alive

	func interact(s: Soldier) -> void:
		if not can_interact(s):
			return
		enabled = false
		brain.release()
		super.interact(s)


func _configure_environment(e: Environment, moon: DirectionalLight3D) -> void:
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.02, 0.03, 0.07)
	sm.sky_horizon_color = Color(0.08, 0.1, 0.16)
	sm.ground_horizon_color = Color(0.08, 0.09, 0.12)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sm.sun_angle_max = 5.0
	e.ambient_light_energy = 0.35
	e.ambient_light_color = Color(0.45, 0.5, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.fog_light_color = Color(0.12, 0.14, 0.2)
	e.fog_density = 0.006
	e.tonemap_exposure = 1.5
	e.glow_intensity = 1.0
	moon.rotation_degrees = Vector3(-38, 35, 0)
	moon.light_color = Color(0.6, 0.68, 0.9)
	moon.light_energy = 0.32


func _build_world() -> void:
	light_factor = 0.5   # Nacht
	# Übungseinsatz (eigener Entwurf): Original-Winterwind (ARCTIC1 a_winter), Untergrund Schnee (Zeile 34 „Sníh“)
	ambience_sound = "a_winter.wav"
	ground_material = 34
	alarm_bell_pos = Vector3(0, 4.0, -5)
	lb.color_ground = Color(0.82, 0.84, 0.88)
	lb.color_ground2 = Color(0.74, 0.77, 0.82)
	lb.color_road = Color(0.5, 0.47, 0.44)
	lb.color_foliage = Color(0.16, 0.23, 0.18)
	lb.noise.seed = 1943
	lb.flatten_zones = [
		[Vector3(0, 1.0, -20), 42.0, 0],
		[Vector3(-10, -2.6, -100), 40.0, 0],     # Ufer/Fjord
		[Vector3(-70, 0.5, 100), 10.0, 0],
	]
	lb.roads = [PackedVector2Array([Vector2(0, 16), Vector2(5, 60), Vector2(30, 130)]),
		PackedVector2Array([Vector2(0, -55), Vector2(-8, -78)])]
	lb.build_terrain()
	_build_depot()
	_build_shore()
	_build_forest()


func _build_depot() -> void:
	var y := 1.0
	# Stacheldraht ums Lager (x -42..42, z -56..16): Tor Süd, Tor Nord, Lücke West (durchtrennt)
	lb.fence(Vector2(-42, 16), Vector2(42, 16), [[42.0, 5.0]])
	lb.fence(Vector2(42, 16), Vector2(42, -56))
	lb.fence(Vector2(42, -56), Vector2(-42, -56), [[42.0, 5.0]])
	lb.fence(Vector2(-42, -56), Vector2(-42, 16), [[36.0, 1.6]])
	# Wachhäuschen Südtor + Schlagbaum
	lb.building(Vector3(-5, y, 19), 2.5, 2.5, 2.4, "wood", "slate", [["e", 0.0]], false)
	lb.box(Vector3(0, y + 0.9, 17), Vector3(5.0, 0.12, 0.12), "wood", 0.0, false)

	# Kaserne (Mitte)
	lb.building(Vector3(0, y, -5), 16.0, 7.0, 3.2, "wood", "slate", [["s", -3.0], ["n", 4.0]])
	# Wachgebäude mit Zelle (Ost), Tür West, Innenwand mit Durchgang
	lb.building(Vector3(26, y, 0), 9.0, 6.0, 3.0, "concrete", "slate", [["w", 0.0]])
	_cell_wall(Vector3(27.5, y, 0))

	# Tanklager A (Nordwest) und B (Nordost)
	var tanks_a := Node3D.new()
	static_root.add_child(tanks_a)
	for p in [Vector3(-24, y, -38), Vector3(-16, y, -40), Vector3(-20, y, -46)]:
		_tank(p, tanks_a)
	var tanks_b := Node3D.new()
	static_root.add_child(tanks_b)
	for p in [Vector3(18, y, -40), Vector3(26, y, -42), Vector3(22, y, -48)]:
		_tank(p, tanks_b)
	depot_a = _charge(Vector3(-20, y, -34.2), "Tanklager West", tanks_a, "depot_a")
	depot_b = _charge(Vector3(22, y, -36.2), "Tanklager Ost", tanks_b, "depot_b")

	# Fässer/Kisten als Deckung
	for p in [Vector3(-8, y, -22), Vector3(-7, y, -23.5), Vector3(9, y, -25), Vector3(-30, y, -12), Vector3(14, y, 8)]:
		lb.cylinder(p, 0.35, 1.0, "tank")
	lb.crate(Vector3(-12, y, -14), 1.1)
	lb.crate(Vector3(6, y, -16), 1.0, 0.4)
	lb.box(Vector3(-2, y, -30), Vector3(5.0, 1.4, 2.2), "wood")      # Holzstapel
	lb.sandbags(Vector3(0, y, -52.5), 4.0, 0.0)

	# Suchscheinwerfer-Türme
	_tower(Vector3(-36, y, 10), deg_to_rad(-135), "sl_sw")
	_tower(Vector3(36, y, -50), deg_to_rad(45), "sl_ne")
	# Laternen
	add_lamp(Vector3(0, y + 3.0, 15))
	add_lamp(Vector3(-3, y + 3.0, -1.0))
	add_lamp(Vector3(22, y + 2.8, 0.5))
	add_lamp(Vector3(0, y + 3.0, -54))
	# Kübelwagen neben der Kaserne (Flucht zum Ufer über das Nordtor)
	spawn_vehicle(Vector3(-12, y, 4), deg_to_rad(90), "veh_depot")
	var ammo := Pickups.AmmoCrate.new()
	ammo.persistent_id = "ammo_depot"
	dynamic_root.add_child(ammo)
	ammo.global_position = Vector3(-34, y, -26)


func _cell_wall(p: Vector3) -> void:
	# Zellenwand mit Gittertür-Öffnung (offen, Gefangener dahinter)
	lb.box(p + Vector3(0, 0, -2.0), Vector3(0.2, 3.0, 2.0), "concrete")
	lb.box(p + Vector3(0, 0, 2.0), Vector3(0.2, 3.0, 2.0), "concrete")
	lb.box(p + Vector3(0, 2.2, 0), Vector3(0.2, 0.8, 2.0), "concrete")


func _tank(p: Vector3, parent: Node3D) -> void:
	lb.cylinder(p, 3.0, 6.0, "tank", true, parent)
	lb.cylinder(p + Vector3(0, 6.0, 0), 2.6, 0.4, "tank", false, parent)


func _charge(p: Vector3, nm: String, target: Node3D, pid: String) -> ChargeSite:
	var c := ChargeSite.new()
	c.target_name = nm
	c.persistent_id = pid
	c.fuse = 25.0
	c.target_node = target
	dynamic_root.add_child(c)
	c.global_position = p
	return c


func _tower(p: Vector3, yaw: float, pid: String) -> void:
	for dx in [-1.2, 1.2]:
		for dz in [-1.2, 1.2]:
			lb.box(p + Vector3(dx, 0, dz), Vector3(0.25, 5.0, 0.25), "darkwood")
	lb.box(p + Vector3(0, 5.0, 0), Vector3(3.0, 0.2, 3.0), "darkwood")
	for s in [-1.0, 1.0]:
		lb.box(p + Vector3(0, 5.2, s * 1.45), Vector3(3.0, 1.0, 0.1), "darkwood")
		lb.box(p + Vector3(s * 1.45, 5.2, 0), Vector3(0.1, 1.0, 3.0), "darkwood")
	var sl := Searchlight.new()
	sl.persistent_id = pid
	sl.sweep_center = yaw
	sl.sweep_width = 0.9
	sl.reach = 75.0
	dynamic_root.add_child(sl)
	sl.global_position = p + Vector3(0.8, 6.5, 0.8)


func _build_shore() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 60)
	w.mesh = pm
	w.material_override = lb.mat("water")
	w.position = Vector3(0, -1.6, -105)
	static_root.add_child(w)
	# Steg und Boot
	lb.box(Vector3(-10, -1.4, -86), Vector3(2.5, 0.25, 9.0), "darkwood")
	lb.box(Vector3(-6.5, -1.7, -90), Vector3(2.0, 0.9, 5.5), "wood", 0.1, false)
	extraction_pos = lb.ground(-10, -80)
	extraction_radius = 8.0
	_boat_light = OmniLight3D.new()
	_boat_light.light_color = Color(0.5, 0.7, 1.0)
	_boat_light.light_energy = 0.0
	_boat_light.omni_range = 8.0
	dynamic_root.add_child(_boat_light)
	_boat_light.global_position = Vector3(-6.5, 0.0, -90)


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for i in 380:
		var x := rng.randf_range(-128, 128)
		var z := rng.randf_range(-70, 128)
		if x > -52 and x < 52 and z > -66 and z < 26:
			continue   # Lagerfläche frei
		if Vector2(x + 70, z - 100).length() < 9.0 or lb._road_distance(x, z) < 5.0:
			continue
		lb.tree(x, z, rng.randf_range(0.8, 1.4), rng.randf() < 0.85)
	# Felsbrocken als Deckung am Hang
	for i in 25:
		var x := rng.randf_range(-60, 60)
		var z := rng.randf_range(-75, -60)
		lb.box(lb.ground(x, z, -0.3), Vector3(rng.randf_range(1.2, 2.5), rng.randf_range(0.9, 1.6), rng.randf_range(1.2, 2.5)), "stone", rng.randf() * PI)


func _spawn_actors() -> void:
	var start := lb.ground(-70, 100)
	spawn_roster(start, deg_to_rad(-30), [Vector3(0, 0, 0), Vector3(-2, 0, 3), Vector3(2, 0, 3), Vector3(0, 0, 6)])
	var y := 1.0
	var g := func(x: float, z: float) -> Vector3: return lb.ground(x, z)
	var night := 0.7   # Sichtweiten nachts kürzer (Originalwerte meist 25–80 m)
	# Südtor
	spawn_enemy(Vector3(-3, y, 18.5), PI, ["kar98k", "", ""], "n_gate1", {"sight": 45 * night})
	spawn_enemy(Vector3(3, y, 18.5), PI, ["mp40", "", ""], "n_gate2", {"sight": 45 * night})
	# Türme
	spawn_enemy(Vector3(-36, y + 5.25, 10), deg_to_rad(-135), ["kar98k", "", ""], "n_tw_sw",
		{"sight": 70 * night, "stationary": true, "skill": 0.7})
	spawn_enemy(Vector3(36, y + 5.25, -50), deg_to_rad(45), ["kar98k", "", ""], "n_tw_ne",
		{"sight": 70 * night, "stationary": true, "skill": 0.7})
	# Kasernen-Streife und Offizier
	spawn_enemy(Vector3(-10, y, -10), 0.0, ["mp40", "", "m24"], "n_yard1", {"sight": 40 * night, "mode": "aggressive",
		"patrol": PackedVector3Array([Vector3(-10, y, -10), Vector3(10, y, -12), Vector3(12, y, -30), Vector3(-12, y, -30)])})
	spawn_enemy(Vector3(2, y, -6), PI, ["", "p08", ""], "n_officer", {"sight": 30 * night, "officer": true})
	# Tanklager-Wachen
	spawn_enemy(Vector3(-20, y, -31), 0.3, ["kar98k", "", ""], "n_depa", {"sight": 45 * night,
		"patrol": PackedVector3Array([Vector3(-20, y, -31), Vector3(-30, y, -42), Vector3(-12, y, -50)])})
	spawn_enemy(Vector3(22, y, -33), -0.3, ["stg44", "", ""], "n_depb", {"sight": 45 * night,
		"patrol": PackedVector3Array([Vector3(22, y, -33), Vector3(32, y, -44), Vector3(14, y, -50)])})
	# Wachgebäude
	spawn_enemy(Vector3(20.5, y, 1.5), -PI * 0.5, ["mp40", "", ""], "n_guard1", {"sight": 40 * night})
	spawn_enemy(Vector3(25, y, -1.5), PI * 0.5, ["", "p08", ""], "n_guard2", {"sight": 20})
	# Außenstreifen am Zaun
	spawn_enemy(g.call(-46, 20), 0.0, ["kar98k", "", "m24"], "n_perim1", {"sight": 45 * night, "mode": "aggressive",
		"patrol": PackedVector3Array([g.call(-46, 20), g.call(-46, -60), g.call(46, -60), g.call(46, 20)])})
	spawn_enemy(g.call(46, -60), PI, ["mp40", "", "m24"], "n_perim2", {"sight": 45 * night,
		"patrol": PackedVector3Array([g.call(46, -60), g.call(46, 20), g.call(-46, 20), g.call(-46, -60)])})
	# Uferstreife und Nordtor
	spawn_enemy(g.call(-2, -60), 0.0, ["kar98k", "", ""], "n_north", {"sight": 45 * night})
	spawn_enemy(g.call(-20, -74), 0.0, ["mp40", "", ""], "n_shore", {"sight": 40 * night,
		"patrol": PackedVector3Array([g.call(-20, -74), g.call(10, -76), g.call(-30, -70)])})

	# Gefangener (norwegischer Widerstandskämpfer) in der Zelle
	prisoner = spawn_soldier(Vector3(29.5, y, 0.5), PI * 0.5, Soldier.TEAM_ALLIED, "Olav Brekke",
		["", "", ""], Color(0.25, 0.22, 0.2), "cap", "prisoner")
	prisoner.max_health = 70.0
	prisoner.health = 70.0
	prisoner_brain = EscortBrain.new()
	prisoner_brain.name = "EscortBrain"
	prisoner.add_child(prisoner_brain)
	prisoner_brain.squad = squad
	prisoner_brain.setup(prisoner)
	var spot := ReleaseSpot.new()
	spot.brain = prisoner_brain
	spot.persistent_id = "release"
	dynamic_root.add_child(spot)
	spot.global_position = Vector3(28.5, y, 0.5)
	prisoner.died.connect(func(_s): if not finished: finish(false, "Der Gefangene ist tot."))


func _setup_objectives() -> void:
	add_objective(&"depot_a", "Tanklager West sprengen")
	add_objective(&"depot_b", "Tanklager Ost sprengen")
	add_objective(&"prisoner", "Gefangenen aus dem Wachgebäude befreien")
	add_objective(&"extract", "Mit dem Gefangenen das Boot am Ufer erreichen")
	add_objective(&"stealth", "Keinen Alarm auslösen", true)
	depot_a.destroyed.connect(func(): complete_objective(&"depot_a"))
	depot_b.destroyed.connect(func(): complete_objective(&"depot_b"))


func _on_alarm() -> void:
	fail_objective(&"stealth")


func _on_tick(_delta: float) -> void:
	if prisoner_brain.released and objective(&"prisoner").state == Objective.State.ACTIVE:
		complete_objective(&"prisoner")
	var ready := required_done(&"extract")
	if ready:
		_boat_light.light_energy = 1.5
		if not _hint:
			_hint = true
			Events.say("Alle Ziele erfüllt — zum Boot am Ufer (Norden)!", 5.0)
		var alive := squad.alive_members()
		var inside := 0
		for m in alive:
			if Vector2(m.global_position.x - extraction_pos.x, m.global_position.z - extraction_pos.z).length() < extraction_radius:
				inside += 1
		var p_in := Vector2(prisoner.global_position.x - extraction_pos.x, prisoner.global_position.z - extraction_pos.z).length() < extraction_radius
		if alive.size() > 0 and inside == alive.size() and p_in and prisoner.alive:
			complete_objective(&"extract")
			if objective(&"stealth").state == Objective.State.ACTIVE:
				complete_objective(&"stealth")
			finish(true, "Lager zerstört, Brekke in Sicherheit. %d von %d Männern zurück." % [alive.size(), squad.members.size()])


func _serialize_extra() -> Dictionary:
	return {"prisoner": prisoner.serialize(), "escort": prisoner_brain.serialize()}


func _deserialize_extra(d: Dictionary) -> void:
	if d.has("prisoner"):
		prisoner.deserialize(d["prisoner"])
	if d.has("escort"):
		prisoner_brain.deserialize(d["escort"])
