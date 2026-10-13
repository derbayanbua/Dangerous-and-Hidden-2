extends Mission
## Mission 1 "Unternehmen Funkfeuer" (eigenständiger Inhalt).
## Normandie-Hinterland 1944, Abenddämmerung. Gehöft mit Funkstation.
## Lösungswege: Westen (Heckenpfad, wenig Wachen), Osten (Obstgarten, Turm
## im Blick), Straße (Kontrollpunkt). Stealth oder offener Angriff möglich.
##
## Koordinaten: Norden = -Z. Gehöft-Mitte (0, -10), Start (0, 108), Abholpunkt (0, -88).

const FARM := Vector3(0, 0, -10)
var farm_h := 0.0
var radio_site: ChargeSite
var codebook: Pickups.Item
var _extract_marker: OmniLight3D
var _extract_hint_shown := false


func _build_world() -> void:
	farm_h = 1.0
	light_factor = 0.8   # Abenddämmerung
	alarm_bell_pos = Vector3(-6, farm_h + 3.0, -14)   # Glocke am Stabsgebäude
	lb.flatten_zones = [
		[Vector3(0, farm_h, -10), 34.0, 0],
		[Vector3(0, -1.2, -100), 18.0, 0],      # Weiher-Senke
		[Vector3(60, 0.6, -18), 10.0, 0],       # Kontrollpunkt
		[Vector3(0, 0.0, 108), 10.0, 0],        # Landeplatz
	]
	lb.roads = [PackedVector2Array([Vector2(130, -22), Vector2(80, -20), Vector2(60, -18), Vector2(28, -10), Vector2(10, -10)]),
		PackedVector2Array([Vector2(0, 14), Vector2(4, 40), Vector2(20, 75), Vector2(30, 130)]),
		PackedVector2Array([Vector2(-8, -31), Vector2(-4, -60), Vector2(2, -84)])]
	lb.build_terrain()
	_build_farm()
	_build_checkpoint()
	_build_hedgerows()
	_build_vegetation()
	_build_pond()


func _build_farm() -> void:
	var y := farm_h
	# Bruchsteinmauer um den Hof (x -26..26, z -32..10), Tore S, O, N
	lb.line_wall(Vector2(-26, 10), Vector2(26, 10), 1.8, 0.5, "stone", [[26.0, 4.5]])          # Südtor x=0
	lb.line_wall(Vector2(26, 10), Vector2(26, -32), 1.8, 0.5, "stone", [[20.0, 5.0]])          # Osttor z=-10
	lb.line_wall(Vector2(26, -32), Vector2(-26, -32), 1.8, 0.5, "stone", [[34.0, 3.5]])        # Nordpforte x=-8
	lb.line_wall(Vector2(-26, -32), Vector2(-26, 10), 1.8, 0.5, "stone", [[30.0, 1.5]])        # schmale Lücke West z=-2

	# Stabsgebäude (Codebuch) — Türen Süd und Ost
	lb.building(Vector3(-12, y, -19), 12.0, 8.0, 3.2, "plaster", "roof", [["s", 2.0], ["e", 0.0]])
	# Innenwand mit Durchgang
	_inner_wall(Vector3(-14, y, -19))
	# Tisch mit Codebuch
	lb.box(Vector3(-16, y, -21), Vector3(1.6, 0.8, 0.9), "darkwood")
	codebook = Pickups.Item.new()
	codebook.item_name = "Codebuch"
	codebook.persistent_id = "codebook"
	codebook.color = Color(0.45, 0.08, 0.06)
	dynamic_root.add_child(codebook)
	codebook.global_position = Vector3(-16, y + 0.8, -21)
	lb.crate(Vector3(-8, y, -22), 0.9)
	lb.box(Vector3(-9, y, -16), Vector3(2.0, 0.9, 0.8), "darkwood")   # Kartentisch

	# Scheune — offenes Tor im Westen
	lb.building(Vector3(12, y, -21), 14.0, 10.0, 5.0, "wood", "slate", [], false, 0.0, [["w", 0.0, 4.0]])
	for i in 4:
		lb.box(Vector3(14 + (i % 2) * 2.0, y, -24 + i * 1.6), Vector3(1.6, 1.0, 1.2), "hay")

	# Funkhütte mit Sender, Tür Nord
	lb.building(Vector3(8, y, 0), 5.0, 4.0, 2.8, "plaster", "slate", [["n", 0.0]])
	var transmitter := lb.box(Vector3(9, y, 0.8), Vector3(1.4, 1.5, 0.6), "radio")
	transmitter.name = "Transmitter"
	radio_site = ChargeSite.new()
	radio_site.target_name = "Funksender"
	radio_site.persistent_id = "radio"
	radio_site.fuse = 20.0
	radio_site.target_node = transmitter
	dynamic_root.add_child(radio_site)
	radio_site.global_position = Vector3(9, y, 0.1)
	# Antennenmast
	lb.cylinder(Vector3(12.5, y, 3), 0.12, 16.0, "metal")
	lb.box(Vector3(12.5, y + 15.5, 3), Vector3(3.0, 0.08, 0.08), "metal", 0.0, false)

	# Wachturm Südost (Plattform 4 m), Brüstung als Deckung
	var tp := Vector3(22, y, 6)
	for dx in [-1.2, 1.2]:
		for dz in [-1.2, 1.2]:
			lb.box(tp + Vector3(dx, 0, dz), Vector3(0.25, 4.0, 0.25), "wood")
	lb.box(tp + Vector3(0, 4.0, 0), Vector3(3.0, 0.2, 3.0), "wood")
	for s in [-1.0, 1.0]:
		lb.box(tp + Vector3(0, 4.2, s * 1.45), Vector3(3.0, 1.0, 0.1), "wood")
		lb.box(tp + Vector3(s * 1.45, 4.2, 0), Vector3(0.1, 1.0, 3.0), "wood")
	lb.box(tp + Vector3(0, 6.2, 0), Vector3(3.4, 0.15, 3.4), "roof", 0.0, false)

	# MG-Nest vor dem Südtor
	lb.sandbags(Vector3(0, y, 15.5), 4.0, 0.0)
	lb.sandbags(Vector3(-2.2, y, 14.2), 2.6, PI * 0.5)
	lb.sandbags(Vector3(2.2, y, 14.2), 2.6, PI * 0.5)

	# Deckung im Hof: Kisten, Karren, Brunnen, Holzstapel
	lb.crate(Vector3(-3, y, -4), 1.0, 0.3)
	lb.crate(Vector3(-2, y, -4.5), 0.8, 0.1)
	lb.crate(Vector3(18, y, -6), 1.1)
	lb.box(Vector3(4, y, -12), Vector3(3.0, 1.1, 1.6), "wood", 0.4)          # Karren
	lb.cylinder(Vector3(-2, y, -12), 1.0, 0.9, "stone")                      # Brunnen
	lb.box(Vector3(-22, y, 4), Vector3(4.0, 1.4, 1.2), "darkwood")          # Holzstapel
	lb.box(Vector3(20, y, -29), Vector3(4.0, 1.6, 1.4), "darkwood")
	var crate_ammo := Pickups.AmmoCrate.new()
	crate_ammo.persistent_id = "ammo_barn"
	dynamic_root.add_child(crate_ammo)
	crate_ammo.global_position = Vector3(8, y, -26)


func _inner_wall(p: Vector3) -> void:
	# Innenwand Nord-Süd mit Türöffnung in der Mitte
	lb.box(p + Vector3(0, 0, -2.75), Vector3(0.2, 3.1, 2.5), "plaster")
	lb.box(p + Vector3(0, 0, 2.75), Vector3(0.2, 3.1, 2.5), "plaster")
	lb.box(p + Vector3(0, 2.2, 0), Vector3(0.2, 0.9, 3.0), "plaster")


func _build_checkpoint() -> void:
	var c := lb.ground(60, -18)
	lb.building(c + Vector3(4, 0, -6), 3.0, 3.0, 2.5, "wood", "slate", [["s", 0.0]])
	lb.box(c + Vector3(0, 0.9, 0), Vector3(7.0, 0.15, 0.15), "wood", 0.1, false)   # Schranke
	lb.box(c + Vector3(-3.5, 0, 0), Vector3(0.3, 1.0, 0.3), "wood")
	lb.sandbags(c + Vector3(-4, 0, 4), 3.0, 0.2)
	lb.sandbags(c + Vector3(5, 0, 4), 3.0, -0.2)
	# abgestellter Kübelwagen am Kontrollpunkt (alternativer Fluchtweg zum Abholpunkt)
	spawn_vehicle(lb.ground(67, -27), deg_to_rad(80), "veh_cp")


func _build_hedgerows() -> void:
	# Bocage: undurchsichtige Hecken mit Durchlässen — Sichtschutz für Annäherung
	lb.line_wall(Vector2(-125, 48), Vector2(-12, 48), 2.6, 1.6, "hedge", [[45.0, 3.0], [80.0, 3.0]])
	lb.line_wall(Vector2(14, 44), Vector2(125, 44), 2.6, 1.6, "hedge", [[30.0, 3.0], [70.0, 4.0]])
	lb.line_wall(Vector2(-48, 48), Vector2(-48, -60), 2.6, 1.6, "hedge", [[40.0, 3.0], [80.0, 3.0]])
	lb.line_wall(Vector2(-34, 30), Vector2(-34, -45), 2.4, 1.4, "hedge", [[20.0, 3.0], [55.0, 3.0]])
	lb.line_wall(Vector2(44, 40), Vector2(44, 5), 2.4, 1.4, "hedge", [[18.0, 3.0]])
	lb.line_wall(Vector2(40, -40), Vector2(100, -40), 2.4, 1.4, "hedge", [[25.0, 3.0]])
	lb.line_wall(Vector2(-60, -60), Vector2(-15, -60), 2.4, 1.4, "hedge", [[20.0, 3.0]])


func _build_vegetation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Wald im Süden (Landeplatz-Lichtung ausgespart)
	for i in 260:
		var x := rng.randf_range(-128, 128)
		var z := rng.randf_range(62, 128)
		if Vector2(x, z - 108).length() < 12.0 or absf(x - lerpf(4, 30, clampf((z - 40) / 90.0, 0, 1))) < 4.0:
			continue
		lb.tree(x, z, rng.randf_range(0.8, 1.3), rng.randf() < 0.4)
	# Obstgarten im Osten
	for ix in 5:
		for iz in 4:
			lb.tree(52 + ix * 7 + rng.randf_range(-1, 1), 14 + iz * 7 + rng.randf_range(-1, 1), 0.6, false)
	# Baumgruppen
	for i in 50:
		var x := rng.randf_range(-128, 128)
		var z := rng.randf_range(-128, 60)
		if Vector2(x - FARM.x, z - FARM.z).length() < 40.0 or Vector2(x, z + 100).length() < 22.0:
			continue
		if lb._road_distance(x, z) < 6.0:
			continue
		lb.tree(x, z, rng.randf_range(0.7, 1.2), rng.randf() < 0.3)
	# Wald im Norden hinter dem Weiher
	for i in 90:
		var x := rng.randf_range(-128, 128)
		var z := rng.randf_range(-128, -112)
		lb.tree(x, z, rng.randf_range(0.8, 1.3), rng.randf() < 0.5)


func _build_pond() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 22)
	w.mesh = pm
	w.material_override = lb.mat("water")
	w.position = Vector3(0, -1.0, -104)
	static_root.add_child(w)
	extraction_pos = lb.ground(0, -86)
	extraction_radius = 8.0


func _spawn_actors() -> void:
	# --- Trupp (Startpunkt Waldlichtung) ---
	var start := lb.ground(0, 108)
	# look_yaw 0 = Blick nach Norden (-Z)
	spawn_roster(start, 0.0, [Vector3(0, 0, 0), Vector3(-2, 0, 3), Vector3(2, 0, 3), Vector3(0, 0, 6)])

	var y := farm_h
	var g := func(x: float, z: float) -> Vector3: return lb.ground(x, z)
	# --- Gegner ---
	# Kontrollpunkt
	spawn_enemy(g.call(58, -14), deg_to_rad(-90), ["kar98k", "", ""], "e_cp1", {"sight": 55})
	spawn_enemy(g.call(63, -22), deg_to_rad(-60), ["mp40", "", "m24"], "e_cp2", {"sight": 50, "mode": "aggressive",
		"patrol": PackedVector3Array([g.call(63, -22), g.call(70, -25), g.call(63, -14)])})
	# Straßenstreife Kontrollpunkt <-> Osttor
	spawn_enemy(g.call(40, -14), deg_to_rad(90), ["kar98k", "", ""], "e_road", {"sight": 50,
		"patrol": PackedVector3Array([g.call(40, -14), g.call(55, -17), g.call(31, -11)])})
	# Südtor-Posten und MG-Nest
	spawn_enemy(Vector3(3, y, 11.5), PI, ["kar98k", "p08", ""], "e_gate", {"sight": 45})
	spawn_enemy(Vector3(0, y, 13.6), PI, ["stg44", "", ""], "e_mg", {"sight": 60, "stationary": true, "skill": 0.55})
	# Wachturm (Scharfschütze, belegt: HUMAN_SetSniper / Sichtweite bis 200 m)
	spawn_enemy(Vector3(22, y + 4.25, 6), deg_to_rad(160), ["kar98k", "", ""], "e_tower",
		{"sight": 85, "stationary": true, "skill": 0.75, "reaction": 0.9})
	# Hofstreife
	spawn_enemy(Vector3(-4, y, -6), 0.0, ["mp40", "", "m24"], "e_yard", {"sight": 40, "mode": "aggressive",
		"patrol": PackedVector3Array([Vector3(-4, y, -6), Vector3(16, y, -8), Vector3(18, y, -28) + Vector3(0, 0, 4), Vector3(-2, y, -27), Vector3(-20, y, -6)])})
	# Funker in der Hütte
	spawn_enemy(Vector3(7, y, -0.5), deg_to_rad(0), ["", "p08", ""], "e_radio", {"sight": 25})
	# Offizier + Türwache im Stabsgebäude
	spawn_enemy(Vector3(-16.5, y, -18), deg_to_rad(-90), ["", "p08", ""], "e_officer", {"sight": 30, "officer": true})
	spawn_enemy(Vector3(-10, y, -13.6), PI, ["mp40", "", ""], "e_hq", {"sight": 40})
	# Außenstreife entlang der Hofmauer (aggressiv)
	spawn_enemy(g.call(-30, 14), 0.0, ["kar98k", "", "m24"], "e_perim", {"sight": 50, "mode": "aggressive",
		"patrol": PackedVector3Array([g.call(-30, 14), g.call(-30, -36), g.call(30, -36), g.call(30, 14)])})
	# Nordpforte / Weiher-Streife
	spawn_enemy(g.call(-8, -36), 0.0, ["mp40", "", ""], "e_north", {"sight": 45,
		"patrol": PackedVector3Array([g.call(-8, -36), g.call(-4, -62), g.call(8, -75)])})


func _setup_objectives() -> void:
	add_objective(&"radio", "Funksender im Gehöft sprengen")
	add_objective(&"codebook", "Codebuch aus dem Stabsgebäude sichern")
	add_objective(&"extract", "Abholpunkt am Weiher im Norden erreichen")
	add_objective(&"stealth", "Keinen Alarm auslösen", true)
	radio_site.destroyed.connect(func(): complete_objective(&"radio"))
	codebook.used.connect(func(_s): complete_objective(&"codebook"))
	_extract_marker = OmniLight3D.new()
	_extract_marker.light_color = Color(1.0, 0.3, 0.2)
	_extract_marker.light_energy = 0.0
	_extract_marker.omni_range = 12.0
	dynamic_root.add_child(_extract_marker)
	_extract_marker.global_position = extraction_pos + Vector3.UP * 1.5


func _on_alarm() -> void:
	fail_objective(&"stealth")


func _on_tick(_delta: float) -> void:
	var ready := objective(&"radio").is_done() and objective(&"codebook").is_done()
	if ready:
		_extract_marker.light_energy = 2.0 + sin(elapsed * 6.0)   # Leuchtsignal
		if not _extract_hint_shown:
			_extract_hint_shown = true
			Events.say("Hauptziele erfüllt — zum Abholpunkt am Weiher (Norden)!", 5.0)
		# alle Lebenden müssen im Abholbereich sein
		var alive := squad.alive_members()
		var inside := 0
		for m in alive:
			var d := Vector2(m.global_position.x - extraction_pos.x, m.global_position.z - extraction_pos.z).length()
			if d < extraction_radius:
				inside += 1
		if inside == alive.size() and alive.size() > 0:
			complete_objective(&"extract")
			if objective(&"stealth").state == Objective.State.ACTIVE:
				complete_objective(&"stealth")
			finish(true, "Auftrag ausgeführt. %d von %d Männern zurück." % [alive.size(), squad.members.size()])
