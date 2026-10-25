class_name Mission
extends Node3D
## Basis jeder Mission: Umgebung/Beleuchtung, Navigationsnetz, Trupp,
## Gegner, Ziele, Alarm, Ende, Pause und Spielstände.
## Konkrete Missionen überschreiben _build_world(), _spawn_actors(),
## _setup_objectives() und optional _on_tick().

var lb: LevelBuilder
var nav_region: NavigationRegion3D
var static_root: Node3D
var dynamic_root: Node3D
var actors_root: Node3D
var effects_root: Node3D
var env: Environment
var sun: DirectionalLight3D
var sky_fx: Node3D        ## src/world/sky_fx.gd (B-013: Wolkenhimmel, Wolkenschatten)
var squad: SquadManager
var controller: PlayerController
var rig: CameraRig
var hud: Node
var tactical_map: Node
var objectives: Array[Objective] = []
var enemies: Array[Soldier] = []
var alarm_raised := false
var finished := false
var elapsed := 0.0
var stats := {"kills": 0, "shots": 0, "alarm": false}
var nav_ready := false
var extraction_pos := Vector3.ZERO
var extraction_radius := 8.0
## Lichtverhältnisse: skaliert die Sicht-Erkennung (1 = Tag, 0.8 = Dämmerung, 0.5 = Nacht)
var light_factor := 1.0
var enemy_uniform := Color(0.34, 0.37, 0.33)   ## Feldgrau; Afrika: Khaki
var alarm_bell_pos := Vector3.INF   ## Ort der Alarmglocke (Mission setzt ihn)
## Lokale Lichtquellen für die Sichtbarkeit: [Position, Radius, Stärke]
var lamps: Array = []
## Klang (Übungseinsätze; Originalmissionen nutzen sounds.bin/tree.klz): Umgebungsschleife (Original-Aufnahme)
## und Untergrund für Schritte/Einschläge als Zeile in TABLES\hdmaterials.def (−1 = keiner)
var ambience_sound := ""
var ground_material := -1


## Helligkeitsfaktor an einer Position (für die Sicht-Erkennung).
## Wasserspiegel an einer Position (NAN = kein Wasser); Originalmissionen: OrigLevel.water
func water_level_at(_pos: Vector3) -> float:
	return NAN


func light_at(pos: Vector3) -> float:
	var l := light_factor
	for lp in lamps:
		var d := pos.distance_to(lp[0])
		if d < lp[1]:
			l = maxf(l, lerpf(lp[2], light_factor, d / lp[1]))
	for sl in get_tree().get_nodes_in_group("searchlights"):
		if sl.illuminates(pos):
			l = maxf(l, 1.6)
	return l


## Fahrzeug abstellen (dynamisch, nicht im Navmesh).
func spawn_vehicle(pos: Vector3, yaw: float, pid: String, vname := "Kübelwagen") -> Vehicle:
	var v := Vehicle.new()
	v.name = pid
	v.persistent_id = pid
	v.vehicle_name = vname
	dynamic_root.add_child(v)
	v.global_position = pos + Vector3.UP * 0.4
	v.global_rotation.y = yaw
	return v


## Laterne/Lampe mit Licht und Sichtbarkeitswirkung.
func add_lamp(pos: Vector3, radius := 9.0, color := Color(1.0, 0.8, 0.5), energy := 2.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = radius
	o.shadow_enabled = Settings.quality >= 2
	dynamic_root.add_child(o)
	o.global_position = pos
	lamps.append([pos, radius, 1.2])
	return o


## Hook für Missionen: Umgebung/Licht anpassen (z. B. Nacht).
func _configure_environment(_env: Environment, _sun: DirectionalLight3D) -> void:
	pass


func _ready() -> void:
	add_to_group("mission")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Ballistics.clear()
	OrigAudio.clear_mission()
	_setup_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	static_root = Node3D.new()
	static_root.name = "Static"
	nav_region.add_child(static_root)
	dynamic_root = Node3D.new()
	dynamic_root.name = "Dynamic"
	add_child(dynamic_root)
	actors_root = Node3D.new()
	actors_root.name = "Actors"
	add_child(actors_root)
	effects_root = Node3D.new()
	effects_root.name = "Effects"
	add_child(effects_root)
	Effects.set_container(effects_root)
	lb = LevelBuilder.new(static_root, dynamic_root)
	_build_world()
	OrigAudio.default_material = ground_material
	_bake_navigation()

	squad = SquadManager.new()
	squad.name = "Squad"
	add_child(squad)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	controller = PlayerController.new()
	controller.name = "PlayerController"
	controller.squad = squad
	controller.rig = rig
	controller.mission = self
	add_child(controller)
	squad.active_changed.connect(controller.set_active)

	_spawn_actors()
	_setup_objectives()
	Events.soldier_died.connect(_on_soldier_died)

	var hud_script := load("res://src/ui/hud.gd")
	hud = hud_script.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)

	var map_script := load("res://src/ui/tactical_map.gd")
	tactical_map = map_script.new()
	tactical_map.name = "TacticalMap"
	add_child(tactical_map)
	tactical_map.setup(self)

	var pause_script := load("res://src/ui/pause_menu.gd")
	var pause = pause_script.new()
	pause.name = "PauseMenu"
	add_child(pause)

	squad.set_active(0)
	var pending := Game.consume_pending_load()
	if not pending.is_empty():
		deserialize(pending)
	if not Game.cli.has("screenshot") and not Game.cli.has("autoplay"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings.changed.connect(_apply_settings)
	Effects.start_ambience(self, ambience_sound)
	if Net.is_online:
		Net.mission_ready.call_deferred(self)    # Mehrspieler: Spielerfiguren kommen vom Server


func _apply_settings() -> void:
	Settings.apply_to_world(env, sun)
	if rig and rig.camera:
		rig.camera.fov = Settings.fov


# --- Umgebung --------------------------------------------------------------------

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.42, 0.58)
	sm.sky_horizon_color = Color(0.78, 0.66, 0.52)
	sm.ground_horizon_color = Color(0.5, 0.45, 0.38)
	sm.ground_bottom_color = Color(0.18, 0.17, 0.15)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.62, 0.52)
	env.fog_density = 0.0022
	env.fog_aerial_perspective = 0.35
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.85, 0.78, 0.7)
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-24, -120, 0)   # tiefe Abendsonne aus Westen
	sun.light_color = Color(1.0, 0.85, 0.68)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	add_child(sun)
	_configure_environment(env, sun)
	Settings.apply_to_world(env, sun)
	# B-013: Wolkenhimmel + Wolkenschatten (übernimmt die eben eingestellten Missionsfarben)
	sky_fx = preload("res://src/world/sky_fx.gd").new()
	add_child(sky_fx)
	sky_fx.setup(self, env, sun)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	# Werte als Vielfache der Zellgröße (sonst rundet Recast mit Warnung). Radius 0,2 m (eine Zelle Erosion; Kapsel
	# 0,3 m gleitet an Ecken ab): schmale Original-Treppenhäuser/Podeste (≈ 1 m) bleiben im Netz. Zelle 0,15 m wäre
	# genauer, sprengt aber auf großen Karten (AFRICA3/4) das Recast-Raster. Steigen 0,4 m = Soldier.STEP_HEIGHT.
	nm.agent_radius = 0.2
	nm.agent_height = 1.6    # Treppen unter Deckenkanten (AFRICA1-Dach) bleiben im Netz
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 50.0     # = Soldier.floor_max_angle (steile Original-Ersatzrampen, z. B. ARCTIC1 x_schody05 ≈ 37–45°)
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | (1 << 4)   # Welt + Zäune
	nm.region_min_size = 4.0
	nm.filter_low_hanging_obstacles = true
	nm.filter_ledge_spans = true
	nm.filter_walkable_low_height_spans = true
	nav_region.navigation_mesh = nm   # Kartenzellgröße: project.godot navigation/3d/*
	# Asynchron backen; KI läuft bis dahin direkt auf Ziele zu.
	_bake_tiles.call_deferred(nm)


## Große Originalkarten (AFRICA2/4/5, ARCTIC4, NORWAY: > 1 km) überschreiten im Ganzen die Recast-Grenze (Godot bricht
## mit „would likely crash the engine“ ab → leeres Netz; eine gröbere Zelle erodiert Türen/Treppen zu Inseln und ließ
## ARCTIC4 bei 0,4 m mit Speichermangel abstürzen). Daher in Kacheln NAV_TILE × NAV_TILE m mit unveränderter Zelle
## 0,2 m backen – nacheinander (gleichzeitige Bakes sprengten den Speicher und lieferten leere Kacheln), Randzone
## border_size + edge_max_error ≤ 1 (Godot-Vorgabe für deckungsgleiche Kachelkanten), Kanten verbinden sich in der
## Navigationskarte. Kleine Karten = ein Stück wie bisher.
const NAV_TILE := 128.0
const NAV_TILE_BORDER := 2.0
var _nav_pending := 0
var _nav_regions: Array[NavigationRegion3D] = []
var _nav_queue: Array = []


func _bake_tiles(nm: NavigationMesh) -> void:
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, nav_region)
	var box := src.get_bounds()
	# Navigationskarte gehört zur Welt des Hauptfensters und bleibt über Kartenwechsel bestehen → immer setzen
	NavigationServer3D.map_set_cell_size(nav_region.get_navigation_map(), nm.cell_size)
	if (box.size.x / nm.cell_size) * (box.size.z / nm.cell_size) > NAV_MAX_COLUMNS or Game.cli.has("nav_tiles"):
		_bake_tiled(nm, src)
		return
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _nav_whole_done.bind(nm, src))


const NAV_MAX_COLUMNS := 24000000.0


func _nav_whole_done(nm: NavigationMesh, src: NavigationMeshSourceGeometryData3D) -> void:
	if not is_inside_tree():
		return
	if nm.get_polygon_count() > 0:
		if Game.cli.has("nav_debug"):
			print("NAV: Karte Zelle %.2f, Netz Zelle %.2f, Regionen in der Karte %d" % [NavigationServer3D.map_get_cell_size(
				nav_region.get_navigation_map()), nm.cell_size, NavigationServer3D.map_get_regions(nav_region.get_navigation_map()).size()])
		nav_region.navigation_mesh = nm
		_nav_regions = [nav_region]
		_nav_pending = 1
		_nav_tile_done(nav_region, nm)
		return
	# Godot verweigert den Bake im Ganzen (Raster zu groß, auch durch den Höhenumfang) → Kacheln
	_bake_tiled(nm, src)


func _bake_tiled(nm: NavigationMesh, src: NavigationMeshSourceGeometryData3D) -> void:
	var box := src.get_bounds()
	var nx := maxi(ceili(box.size.x / NAV_TILE), 1)
	var nz := maxi(ceili(box.size.z / NAV_TILE), 1)
	if nx * nz == 1:
		nx = 2           # nur bei zu großem Höhenumfang: dennoch teilen
	print("NAV: Kachelbake %.0f × %.0f m (Höhe %.0f m) → %d Kacheln, Zelle %.2f m" % [box.size.x, box.size.z, box.size.y,
		nx * nz, nm.cell_size])
	_nav_pending = nx * nz
	_nav_regions.clear()
	_nav_queue.clear()
	var focus := nav_focus_points()
	# Kachelraster auf das Zellraster legen: Recast rundet border_size auf ganze Zellen AUF (2,0 m / 0,2 m = 10,000…02 →
	# 11 Zellen = 2,2 m), dann fehlen zwischen den Kacheln 0,4 m und die Kanten verbinden sich nicht (AFRICA2_MP_ZONE:
	# Südhälfte abgetrennt). Daher Rand = ganze Zellen (knapp darunter angegeben), Kachelmaße/-ursprung Vielfache der Zelle.
	var cs := nm.cell_size
	var border_cells := ceili(NAV_TILE_BORDER / cs - 0.01)
	var border := border_cells * cs
	var tw := ceilf((box.size.x + cs) / nx / cs) * cs
	var td := ceilf((box.size.z + cs) / nz / cs) * cs
	var ox := floorf(box.position.x / cs) * cs
	var oz := floorf(box.position.z / cs) * cs
	for ix in nx:
		for iz in nz:
			var tile := nm.duplicate() as NavigationMesh
			tile.border_size = border - cs * 0.05
			tile.edge_max_error = 1.0
			tile.filter_baking_aabb = AABB(Vector3(ox + ix * tw - border, box.position.y - 1.0, oz + iz * td - border),
				Vector3(tw + 2.0 * border, box.size.y + 2.0, td + 2.0 * border))
			if not focus.is_empty() and not _near_focus(tile.filter_baking_aabb, focus):
				_nav_pending -= 1
				continue
			var reg := nav_region
			if ix + iz > 0:
				reg = NavigationRegion3D.new()
				reg.name = "Nav_%d_%d" % [ix, iz]
				add_child(reg)
			_nav_regions.append(reg)
			_nav_queue.append([reg, tile])
	if _nav_queue.is_empty():
		push_warning("NAV: keine Kachel im Spielbereich – kein Navigationsnetz")
		nav_ready = true
		return
	print("NAV: %d von %d Kacheln im Spielbereich (≤ %.0f m um Soldaten/Spawns/Zonen/Leitern)" % [_nav_queue.size(), nx * nz,
		NAV_FOCUS_MARGIN])
	_nav_t0 = Time.get_ticks_msec()
	_bake_next_tile(src)


## Spielbereich für den Kachelbake sehr großer Karten (AFRICA6 5,7 × 4 km = 1395 Kacheln): nur Kacheln im Umkreis
## NAV_FOCUS_MARGIN um diese Punkte werden gebacken. Missionen können ergänzen (super aufrufen).
const NAV_FOCUS_MARGIN := 250.0


func nav_focus_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in get_tree().get_nodes_in_group("soldiers"):
		out.append((s as Node3D).global_position)
	for l in get_tree().get_nodes_in_group("ladders"):
		out.append((l as Node3D).global_position)
	var sps = get("_spawn_points")
	if sps is Array:
		for sp in sps:
			out.append(sp.pos)
	var zs = get("_zones")
	if zs is Array:
		for z in zs:
			out.append((z.xf as Transform3D).origin)
	return out


static func _near_focus(box: AABB, focus: PackedVector3Array) -> bool:
	var b := box.grow(NAV_FOCUS_MARGIN)
	for p in focus:
		if p.x >= b.position.x and p.x <= b.end.x and p.z >= b.position.z and p.z <= b.end.z:
			return true
	return false


var _nav_t0 := 0


func _bake_next_tile(src: NavigationMeshSourceGeometryData3D) -> void:
	if not is_inside_tree() or _nav_queue.is_empty():
		return
	var job: Array = _nav_queue.pop_front()
	NavigationServer3D.bake_from_source_geometry_data_async(job[1], src, _nav_tile_baked.bind(job[0], job[1], src))


func _nav_tile_baked(reg: NavigationRegion3D, tile: NavigationMesh, src: NavigationMeshSourceGeometryData3D) -> void:
	if not is_inside_tree():
		return
	if _nav_queue.is_empty():
		print("NAV: Kacheln gebacken in %d ms" % (Time.get_ticks_msec() - _nav_t0))
	else:
		_bake_next_tile.call_deferred(src)
	_nav_tile_done(reg, tile)

func _nav_tile_done(reg: NavigationRegion3D, tile: NavigationMesh) -> void:
	if not is_instance_valid(reg):
		return
	reg.navigation_mesh = tile
	_nav_pending -= 1
	if _nav_pending == 0:
		# Regionen werden erst beim Abgleich der Navigationskarte wirksam; große Regionen synchronisiert Godot
		# asynchron über mehrere Bilder (BURMA1_MP_ZONE: Abfragen lieferten noch (0,0,0)) → warten, bis ein Eckpunkt
		# jeder Region über die Karte auffindbar ist (höchstens 2 min; AFRICA2 1,1 km braucht lange)
		var probes: Array[Vector3] = []
		for r in _nav_regions:
			if r.navigation_mesh and r.navigation_mesh.get_vertices().size() > 0:
				probes.append(r.global_transform * r.navigation_mesh.get_vertices()[0])
		for i in 7200:
			await get_tree().physics_frame
			if not is_inside_tree():
				return
			var ok := i >= 2
			var map := nav_region.get_navigation_map()
			for p in probes:
				if NavigationServer3D.map_get_closest_point(map, p).distance_to(p) > 0.6:
					ok = false
					break
			if ok:
				print("NAV: Karte abgeglichen nach %d Physikschritten" % i)
				break
			if i == 7199:
				push_warning("NAV: Navigationskarte nach 2 min noch nicht abgeglichen")
		if not Game.cli.has("no_nav_bridges"):   # Inselbrücken/Kletterstellen (B-010), abschaltbar zur Messung
			await _bridge_islands()
			if not is_inside_tree():
				return
		_add_ladder_links()
		if not ladder_links.is_empty() or not bridge_links.is_empty():
			# Verbindungen wirken erst nach einem vollständigen (asynchronen) Abgleich der Navigationskarte – zwei
			# Physikschritte reichten nicht (ARCTIC1: nur 26 von 271 Links begehbar) → warten, bis ein Link-Pfad
			# über die letzte Verbindung führt (höchstens 30 s)
			var links: Array[NavigationLink3D] = []
			links.append_array(bridge_links)
			links.append_array(ladder_links)
			var probe_l: NavigationLink3D = links[-1]
			var map2 := nav_region.get_navigation_map()
			for i in 1800:
				await get_tree().physics_frame
				if not is_inside_tree():
					return
				var pth := NavigationServer3D.map_get_path(map2, probe_l.global_transform * probe_l.start_position,
					probe_l.global_transform * probe_l.end_position, true)
				if i >= 2 and pth.size() > 0 and pth[pth.size() - 1].distance_to(probe_l.global_transform * probe_l.end_position) < 0.6:
					print("NAV: Verbindungen wirksam nach %d Physikschritten" % i)
					break
		nav_ready = true
		var polys := 0
		for r in _nav_regions:
			polys += r.navigation_mesh.get_polygon_count() if r.navigation_mesh else 0
		print("NAV: Navigationsnetz fertig (%d Polygone, %d Kacheln)" % [polys, _nav_regions.size()])
		if _nav_regions.size() > 1 and Game.cli.has("nav_debug"):
			var counts: Array = []
			for r in _nav_regions:
				counts.append(r.navigation_mesh.get_polygon_count() if r.navigation_mesh else -1)
				if r.navigation_mesh and r.navigation_mesh.get_polygon_count() == 0:
					print("NAV: leere Kachel ", r.navigation_mesh.filter_baking_aabb)
			print("NAV: Kacheln ", counts)


## Inselbrücken: Recast trennt begehbare Flächen, die ein Soldat physisch verbindet – Türschwellen, Erosion an engen
## Durchgängen (Radius), Stufen an Kachel-/Zellgrenzen. Je Paar von Netzinseln wird die kürzeste Verbindung gesucht
## (waagerecht ≤ BRIDGE_MAX_GAP, Höhenunterschied ≤ Soldier.STEP_HEIGHT); passt die Soldatenkapsel frei hindurch
## (Formabfrage über die Strecke, Boden darunter), entsteht eine NavigationLink3D in beide Richtungen.
const BRIDGE_MAX_GAP := 1.2
const BRIDGE_SPACING := 6.0   ## m: je Inselpaar höchstens eine Verbindung je Feld dieser Größe
var _dbg_sizes: Array = []
const CLIMB_MAX_GAP := 1.6     ## Kletterstelle: waagerechter Abstand Netzkante unten ↔ oben (Mauerdicke + Erosion)
var bridge_links: Array[NavigationLink3D] = []


var _slice := 0


func _bridge_islands() -> void:
	var t0 := Time.get_ticks_msec()
	_slice = t0
	# Eckpunkte aller Regionen verschweißen (Kacheln teilen Randpunkte), Inseln per Union-Find über Polygone
	var weld := {}                         # Vector3i -> globaler Punkt
	var gpos := PackedVector3Array()
	var uf: Array = []
	var edges := {}                        # Vector2i(a, b) -> [Anzahl, Polygon]
	var pcount := 0
	for r in _nav_regions:
		var nm := r.navigation_mesh
		if nm == null:
			continue
		var vs := nm.get_vertices()
		var xf := r.global_transform
		var gid := PackedInt32Array()
		for v in vs:
			var w := xf * v
			var key := Vector3i((w * 10.0).round())
			if not weld.has(key):
				weld[key] = gpos.size()
				gpos.append(w)
			gid.append(weld[key])
		for pi in nm.get_polygon_count():
			if Time.get_ticks_msec() - _slice > 8:      # Zeitscheiben: große Karten (NORWAY 14 s) ohne Standbild
				await get_tree().process_frame
				_slice = Time.get_ticks_msec()
				if not is_inside_tree():
					return
			uf.append(pcount)
			var poly := nm.get_polygon(pi)
			for k in poly.size():
				# Verbunden sind Polygone nur über gemeinsame Kanten (Godot-Navigationskarte), nicht über einen
				# gemeinsamen Eckpunkt (AFRICA5_MP: Bunkerboden berührt das Gelände nur an einer Ecke)
				var gv := gid[poly[k]]
				var gn := gid[poly[(k + 1) % poly.size()]]
				var ek := Vector2i(mini(gv, gn), maxi(gv, gn))
				if edges.has(ek):
					edges[ek][0] += 1
					_uf_union(uf, edges[ek][1], pcount)
				else:
					edges[ek] = [1, pcount]
			pcount += 1
	if pcount == 0:
		return
	# Prüfpunkte = Randkanten (nur von einem Polygon benutzt) alle 0,4 m abgetastet: die nächste Stelle zweier Inseln
	# liegt meist mitten auf langen Wandkanten, nicht an Eckpunkten
	var verts := PackedVector3Array()
	var island := PackedInt32Array()
	var isl_size := {}
	for ek in edges:
		var e: Array = edges[ek]
		if e[0] != 1:
			continue
		var isl := _uf_find(uf, e[1])
		isl_size[isl] = int(isl_size.get(isl, 0)) + 1
		var a: Vector3 = gpos[ek.x]
		var b: Vector3 = gpos[ek.y]
		var n := maxi(ceili(a.distance_to(b) / 0.4), 1)
		for i in n:
			verts.append(a.lerp(b, float(i) / n))
			island.append(isl)
	if isl_size.size() < 2:
		return
	if Game.cli.has("bridge_debug"):
		var xz := String(Game.cli["bridge_debug"]).split_floats(",")
		for i in verts.size():
			if Vector2(verts[i].x - xz[0], verts[i].z - xz[1]).length() < 2.5:
				print("   Randpunkt %s Insel %d (%d Kanten)" % [verts[i], island[i], isl_size[island[i]]])
	# Raster 1,5 m
	var grid := {}
	for i in verts.size():
		if island[i] < 0:
			continue
		var k := Vector2i(floori(verts[i].x / 1.5), floori(verts[i].z / 1.5))
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(i)
	var best := {}                         # Inselpaar -> [Abstand, a, b]
	for i in verts.size():
		if Time.get_ticks_msec() - _slice > 8:      # Zeitscheiben: große Karten (NORWAY 14 s) ohne Standbild
			await get_tree().process_frame
			_slice = Time.get_ticks_msec()
			if not is_inside_tree():
				return
		var ii := island[i]
		if ii < 0:
			continue
		var a := verts[i]
		var k0 := Vector2i(floori(a.x / 1.5), floori(a.z / 1.5))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell = grid.get(k0 + Vector2i(dx, dz))
				if cell == null:
					continue
				for j in cell:
					var jj := island[j]
					if jj <= ii:
						continue
					var b := verts[j]
					var dy := absf(a.y - b.y)
					if dy > Soldier.CLIMB_MAX:
						continue
					var d := Vector2(a.x - b.x, a.z - b.z).length()
					if d > (BRIDGE_MAX_GAP if dy <= Soldier.STEP_HEIGHT else CLIMB_MAX_GAP):
						continue
					# Bewertung: Stufe/Schwelle vor Kletterstelle (Höhe zählt dreifach)
					var score: float = d + (0.0 if dy <= Soldier.STEP_HEIGHT else 3.0 * dy)
					# je Inselpaar und BRIDGE_SPACING-Feld der beste Kandidat: lange Nahtstellen (Geländeteile, Wegränder)
					# brauchen viele Übergänge, sonst entstehen Umwege über eine einzige Brücke
					var key := Vector3i(ii, jj, 0)
					var bcell := Vector2i(floori(a.x / BRIDGE_SPACING), floori(a.z / BRIDGE_SPACING))
					var per: Dictionary = best.get(key, {})
					if not per.has(bcell) or score < per[bcell][0]:
						per[bcell] = [score, a, b]
						best[key] = per
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.4
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cap
	params.collision_mask = 1 | (1 << 4)
	var n_climb := 0
	for key in best:
		if Time.get_ticks_msec() - _slice > 8:      # Zeitscheiben: große Karten (NORWAY 14 s) ohne Standbild
			await get_tree().process_frame
			_slice = Time.get_ticks_msec()
			if not is_inside_tree():
				return
		if Game.cli.has("bridge_debug"):
			_dbg_sizes = [isl_size.get(key.x, 0), isl_size.get(key.y, 0)]
		var per: Dictionary = best[key]
		for bc in per:
			var cand: Array = per[bc]
			var r := _try_bridge(space, params, cap, cand[1], cand[2])
			if r == 2:
				n_climb += 1
	print("NAV: %d Inseln, %d Inselbrücken, davon %d Kletterstellen (%d ms)" % [isl_size.size(), bridge_links.size(), n_climb,
		Time.get_ticks_msec() - t0])


## Verbindung prüfen und anlegen: 0 = verworfen, 1 = Brücke (Schwelle/Spalt), 2 = Kletterstelle
func _try_bridge(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D, cap: CapsuleShape3D,
		p: Vector3, q: Vector3) -> int:
	var a: Vector3 = p if p.y <= q.y else q          # a = unten
	var b: Vector3 = q if p.y <= q.y else p
	var climb := b.y - a.y > Soldier.STEP_HEIGHT
	var dbg := false
	if Game.cli.has("bridge_debug"):         # --bridge_debug=x,z: Kandidaten im Umkreis von 6 m mit Ergebnis ausgeben
		var xz := String(Game.cli["bridge_debug"]).split_floats(",")
		dbg = Vector2(a.x - xz[0], a.z - xz[1]).length() < 6.0 or Vector2(b.x - xz[0], b.z - xz[1]).length() < 6.0
	if dbg:
		print("BRIDGE? %s -> %s (dy %.2f, d %.2f) Inselgrößen %s" % [a, b, b.y - a.y, Vector2(a.x - b.x, a.z - b.z).length(), str(_dbg_sizes)])
	if climb:
		# Kletterstelle (Soldier.try_climb bis CLIMB_MAX): Kopffreiheit über dem unteren Punkt bis über die Oberkante
		params.transform = Transform3D(Basis(), a + Vector3.UP * (0.45 + cap.height * 0.5))
		params.motion = Vector3.UP * (b.y - a.y)
		var up := space.cast_motion(params)
		if up.is_empty() or up[0] < 0.99:
			if dbg:
				print("   kein Kopfraum ", up)
			return 0
	# Kapsel (Unterkante 0,45 m über dem höheren Punkt) muss frei vom einen zum anderen Punkt gleiten können
	var lift := b.y - a.y + 0.45 + cap.height * 0.5
	params.transform = Transform3D(Basis(), a + Vector3.UP * lift)
	params.motion = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var cm := space.cast_motion(params)
	if cm.is_empty() or cm[0] < 0.99:
		if dbg:
			print("   Weg versperrt ", cm)
		return 0
	if not climb:
		# Boden in der Mitte (keine Brücke über Abgründe)
		var mid := (a + b) * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 0.5, mid + Vector3.DOWN * 0.6, 1))
		if hit.is_empty():
			return 0
	var link := NavigationLink3D.new()
	link.name = ("ClimbLink_%d" if climb else "IslandBridge_%d") % bridge_links.size()
	link.bidirectional = true
	# Endpunkte liegen genau auf den Randkanten → je 0,15 m ins eigene Polygon versetzen (auf der Kante verbindet
	# die Navigationskarte den Link nicht zuverlässig)
	var hd := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if hd.length() > 0.05:
		hd = hd.normalized() * 0.15
		a -= hd
		b += hd
	link.start_position = NavigationServer3D.map_get_closest_point(nav_region.get_navigation_map(), a)
	link.end_position = NavigationServer3D.map_get_closest_point(nav_region.get_navigation_map(), b)
	if climb:
		link.set_meta("climb", true)
	dynamic_root.add_child(link)
	bridge_links.append(link)
	return 2 if climb else 1

static func _uf_find(uf: Array, x: int) -> int:
	while uf[x] != x:
		uf[x] = uf[uf[x]]
		x = uf[x]
	return x


static func _uf_union(uf: Array, a: int, b: int) -> void:
	var ra := _uf_find(uf, a)
	var rb := _uf_find(uf, b)
	if ra != rb:
		uf[rb] = ra


## Original-Leitern (OrigInteractive.OrigLadder, Gruppe „ladders“) als Navigationsverbindungen Fuß ↔ Austritt, damit
## Türme/Dächer mit Spawnpunkten (z. B. ARCTIC1_MP) im Netz erreichbar sind. Die KI erkennt die Verbindung über
## NavigationAgent3D.link_reached; Metadaten „ladder“ = Leiter-Knoten am Fuß (Benutzen klettert hinauf/hinunter).
var ladder_links: Array[NavigationLink3D] = []


func _add_ladder_links() -> void:
	var map := nav_region.get_navigation_map()
	for l in get_tree().get_nodes_in_group("ladders"):
		if not ("at_top" in l) or l.at_top or not ("top" in l):
			continue
		var bottom: Vector3 = l.bottom
		var top: Vector3 = l.top
		var a := NavigationServer3D.map_get_closest_point(map, bottom)
		# Austritt: Netzpunkt nahe der Oberkante (Kletterweg setzt den Soldaten 0,7 m vom Leiterkopf ab)
		var b := NavigationServer3D.map_get_closest_point(map, top + Vector3.UP * 0.1)
		if a.distance_to(bottom) > 2.0 or b.distance_to(top) > 2.0 or absf(b.y - a.y) < 1.0:
			continue
		var link := NavigationLink3D.new()
		link.name = "LadderLink_%d" % ladder_links.size()
		link.bidirectional = true
		link.start_position = a
		link.end_position = b
		link.set_meta("ladder", l)
		for o in get_tree().get_nodes_in_group("ladders"):
			if o != l and o.at_top and o.top.is_equal_approx(top) and o.bottom.is_equal_approx(bottom):
				link.set_meta("ladder_top", o)
				break
		dynamic_root.add_child(link)
		ladder_links.append(link)
	if not ladder_links.is_empty():
		print("NAV: %d Leiter-Verbindungen" % ladder_links.size())


# --- Erzeugung --------------------------------------------------------------------

func _build_world() -> void:
	pass


func _spawn_actors() -> void:
	pass


func _setup_objectives() -> void:
	pass


func _exit_tree() -> void:
	# Statischer Materialcache hält GPU-Ressourcen; vor dem Herunterfahren der Server freigeben
	# (sonst Absturz beim Beenden im Release-Export, 0xC0000374)
	SoldierModel._mat_cache.clear()
	OrigWeapons.release()
	OrigAudio.clear_mission()
	OrigAudio.stop_music()
	OrigAudio.stop_cutscene_music()


func spawn_soldier(pos: Vector3, yaw: float, team: int, sname: String, loadout: Array,
		color: Color, helmet: String, pid: String) -> Soldier:
	var s := Soldier.new()
	s.name = pid
	s.persistent_id = pid
	s.soldier_name = sname
	s.team = team
	s.uniform_color = color
	s.helmet_style = helmet
	s.equip(loadout)
	actors_root.add_child(s)
	s.global_position = pos + Vector3.UP * 0.1
	s.look_yaw = yaw
	var p := Perception.new()
	p.name = "Perception"
	s.add_child(p)
	return s


## Spawnt den Kader aus Game.ROSTER mit der gewählten Ausrüstung.
## offsets: lokale Aufstellung relativ zu start (Index = Kaderposition).
func spawn_roster(start: Vector3, yaw: float, offsets: Array, max_count := -1) -> void:
	var roster := Game.alive_roster()   # Gefallene der Kampagne fehlen
	if roster.is_empty():
		roster = Game.ROSTER                # Notfall: nie ohne Trupp starten
	if max_count > 0 and roster.size() > max_count:
		roster = roster.slice(0, max_count)   # z. B. Original-Teil 1B: Einzelk?mpfer
	for i in roster.size():
		var r: Dictionary = roster[i]
		var off: Vector3 = offsets[i] if i < offsets.size() else Vector3(i * 1.5, 0, 0)
		var sm := spawn_squad_member(start + Basis(Vector3.UP, yaw) * off, yaw, r["name"], Game.loadout_for(r["pid"]), r["pid"])
		if Game.is_sas_pid(r["pid"]):
			Game.apply_sas(sm, r["pid"])     # Originalwerte und Inventar des SAS-Soldaten
		else:
			_default_kit(sm)


## Übungseinsätze: volle Grundausstattung (Primärwaffe, Raketenwerfer, Pistole, Messer, Granaten,
## Sprengstoff, Mine, Erste Hilfe) für die vereinfachte Waffenwahl
func _default_kit(s: Soldier) -> void:
	if s.weapons[WeaponData.Slot.LAUNCHER] == null:
		var b := Weapon.new(WeaponDB.get_weapon(&"bazooka"), false)
		b.in_mag = 1
		b.reserve = 2
		s.weapons[WeaponData.Slot.LAUNCHER] = b
	if s.weapons[WeaponData.Slot.MELEE] == null:
		s.weapons[WeaponData.Slot.MELEE] = Weapon.new(WeaponDB.get_weapon(&"knife"))
	s.explosives = maxi(s.explosives, 2)
	s.mines = maxi(s.mines, 2)
	s.medkits = maxi(s.medkits, 1)


func spawn_squad_member(pos: Vector3, yaw: float, sname: String, loadout: Array, pid: String) -> Soldier:
	var s := spawn_soldier(pos, yaw, Soldier.TEAM_ALLIED, sname, loadout, Color(0.43, 0.39, 0.25), "brodie", pid)
	s.get_node("Perception").sight_range = 70.0
	squad.add_member(s)
	return s


## Gegner mit KI. opts: sight, hear, mode ("aggressive"/"defensive"),
## patrol (PackedVector3Array), stationary (bool), skill (0..1), officer (bool)
func spawn_enemy(pos: Vector3, yaw: float, loadout: Array, pid: String, opts := {}) -> Soldier:
	var officer: bool = opts.get("officer", false)
	var uni: Color = opts.get("uniform", enemy_uniform)
	var s := spawn_soldier(pos, yaw, Soldier.TEAM_AXIS, "Offizier" if officer else "Soldat",
		loadout, uni if not officer else uni.darkened(0.1),
		"cap" if officer else opts.get("helmet", "stahlhelm"), pid)
	var per: Perception = s.get_node("Perception")
	per.sight_range = opts.get("sight", 50.0)
	per.hear_range = opts.get("hear", 60.0)
	var b := EnemyBrain.new()
	b.name = "EnemyBrain"
	b.patrol_points = opts.get("patrol", PackedVector3Array())
	b.ai_mode = EnemyBrain.Mode.AGGRESSIVE if opts.get("mode", "defensive") == "aggressive" else EnemyBrain.Mode.DEFENSIVE
	b.accuracy_skill = opts.get("skill", 0.45)
	b.reaction_time = opts.get("reaction", 0.7)
	s.add_child(b)
	b.setup(s)
	b.stationary = opts.get("stationary", false)
	enemies.append(s)
	var loot := Pickups.Loot.new()
	loot.corpse = s
	loot.enabled = false
	s.add_child(loot)
	s.died.connect(func(_x): loot.enabled = true)
	return s


# --- Ziele / Ablauf ---------------------------------------------------------------

func add_objective(id: StringName, text: String, optional := false) -> Objective:
	var o := Objective.new(id, text, optional)
	objectives.append(o)
	return o


func objective(id: StringName) -> Objective:
	for o in objectives:
		if o.id == id:
			return o
	return null


func complete_objective(id: StringName) -> void:
	var o := objective(id)
	if o and (o.state == Objective.State.ACTIVE or o.state == Objective.State.INACTIVE):
		o.state = Objective.State.DONE
		Events.say("Ziel erfüllt: %s" % o.text, 4.0)
		Events.objective_updated.emit(id)


func fail_objective(id: StringName) -> void:
	var o := objective(id)
	if o and o.state == Objective.State.ACTIVE:
		o.state = Objective.State.FAILED
		Events.say("Ziel verfehlt: %s" % o.text, 4.0)
		Events.objective_updated.emit(id)


## Original-Skripte: SetObjectiveStatus(Index, Status) mit 0 = in Arbeit, 1 = erfüllt, 3 = gescheitert.
## Die Mission ordnet Index -> Objective über orig_objectives zu.
var orig_objectives := {}
var ls_runtime: Node


func set_orig_objective(index: int, status: int) -> void:
	var id: StringName = orig_objectives.get(index, &"")
	var o := objective(id)
	if o == null:
		return
	match status:
		0, 2, 4:
			# 0 = in Arbeit, 2 = wieder offen (z. B. Beweisstück aus dem Inventar entfernt),
			# 4 = angezeigt, nachrangig (Skriptkommentare: „optional“/„must survive“)
			o.secondary = status == 4
			if o.state != Objective.State.ACTIVE:
				o.state = Objective.State.ACTIVE
				Events.objective_updated.emit(id)
		1:
			complete_objective(id)
		3:
			o.state = Objective.State.ACTIVE
			fail_objective(id)
			if not o.optional:
				finish(false, o.text)
	_check_orig_completion()


## Siegbedingung der Originalmissionen (abgeleitet aus den Skripten, nicht im Code belegt):
## alle AKTIVIERTEN Pflichtziele erfüllt (nicht aktivierte zählen nicht – z. B. alternative Sammelpunkte),
## mindestens eines erfüllt, und der Zustand bleibt 3 s stabil (Skripte schalten nach einem Erfolg oft
## sofort das nächste Ziel frei).
var _completion_pending := false


func _orig_complete_now() -> bool:
	var any := false
	for o in objectives:
		if o.optional or o.state == Objective.State.INACTIVE or (o.secondary and o.state == Objective.State.ACTIVE):
			continue
		if o.state != Objective.State.DONE:
			return false
		any = true
	return any


func _check_orig_completion() -> void:
	if finished or orig_objectives.is_empty() or _completion_pending or not _orig_complete_now():
		return
	_completion_pending = true
	await get_tree().create_timer(3.0, false).timeout
	_completion_pending = false
	if not finished and _orig_complete_now():
		finish(true, "Alle Einsatzziele erfüllt.")


func required_done(except: StringName = &"") -> bool:
	for o in objectives:
		if not o.optional and o.id != except and o.state != Objective.State.DONE:
			return false
	return true


func raise_alarm(pos: Vector3, by: Node) -> void:
	if alarm_raised:
		return
	alarm_raised = true
	stats["alarm"] = true
	Events.say("ALARM! Die Garnison ist alarmiert.", 5.0)
	Events.alarm_raised.emit(pos, by)
	Effects.alarm_bell(alarm_bell_pos if alarm_bell_pos.is_finite() else pos)
	_on_alarm()


func _on_alarm() -> void:
	pass


func _on_soldier_died(s: Node, attacker: Node) -> void:
	if Net.is_online:
		Net.on_soldier_died(s, attacker)     # Mehrspieler: Punkte/Respawn statt Missionsende
		return
	if finished:
		return
	if s is Soldier and (s as Soldier).team == Soldier.TEAM_AXIS and attacker is Soldier \
			and (attacker as Soldier).team == Soldier.TEAM_ALLIED:
		stats["kills"] += 1
		# Training (Original 0x5A0BE0): Abschuss; Gegner ahnungslos (nicht im Kampf/Suche) -> Tarnung
		var att := attacker as Soldier
		att.train("kills")
		var eb: EnemyBrain = s.get_node_or_null("EnemyBrain")
		if eb and eb.state in [EnemyBrain.State.GUARD, EnemyBrain.State.PATROL]:
			att.train("unseen_kills")
	elif s is Soldier and attacker is Soldier and (attacker as Soldier).team == Soldier.TEAM_ALLIED:
		# Wehrlose getötet (Original 0x5A0BE0): Gefangener −1000, Ergebener −500 Erfahrung
		var eb2: EnemyBrain = s.get_node_or_null("EnemyBrain")
		if eb2 and eb2.captured:
			(attacker as Soldier).train("prisoner_kills")
		elif eb2 and eb2.surrendered:
			(attacker as Soldier).train("defenseless_kills")
	if squad.all_dead():
		finish(false, "Der gesamte Trupp ist gefallen.")


func _physics_process(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_on_tick(delta)


func _on_tick(_delta: float) -> void:
	pass


func _name_of(pid: String) -> String:
	var e := Game.roster_entry(pid)
	return e["name"] if not e.is_empty() else pid


func finish(success: bool, reason: String) -> void:
	if finished:
		return
	finished = true
	stats["shots"] = Ballistics.shots_fired
	Game.last_result = {
		"success": success, "reason": reason, "time": elapsed, "stats": stats.duplicate(),
		"objectives": objectives.map(func(o): return [o.text, o.state, o.optional]),
		"mission": Game.current_mission_id,
	}
	if Game.uses_sas(Game.current_mission_id):
		Game.last_result["sas"] = Game.finish_sas(squad.members, success)
	var fallen := []
	for mm in squad.members:
		if not mm.alive:
			fallen.append(mm.persistent_id)
	Game.last_result["fallen"] = fallen.map(func(pid): return _name_of(pid))
	Game.record_mission_result(Game.current_mission_id, success, fallen)
	Game.add_profile_stats(elapsed, int(stats.get("kills", 0)), int(stats.get("shots", 0)))
	Events.mission_finished.emit(success, reason)
	controller.input_enabled = false
	get_tree().create_timer(3.0, true, false, true).timeout.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/debrief.tscn"))


# --- Spielstände --------------------------------------------------------------------

func serialize() -> Dictionary:
	var sq := {}
	for m in squad.members:
		var d := m.serialize()
		d["brain"] = squad.brain_of(m).serialize()
		sq[m.persistent_id] = d
	var en := {}
	for e in enemies:
		var d := e.serialize()
		d["brain"] = (e.get_node("EnemyBrain") as EnemyBrain).serialize()
		en[e.persistent_id] = d
	var inter := {}
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it and it.persistent_id != "":
			inter[it.persistent_id] = it.serialize()
	for n in get_tree().get_nodes_in_group("persistent"):
		if "persistent_id" in n and n.persistent_id != "":
			inter[n.persistent_id] = n.serialize()
	var obj := {}
	for o in objectives:
		obj[String(o.id)] = o.state
	return {
		"squad": sq, "active": squad.active_index, "formation": squad.formation, "spacing_level": squad.spacing_level,
		"enemies": en, "interactables": inter, "objectives": obj, "extra": _serialize_extra(),
		"alarm": alarm_raised, "elapsed": elapsed, "stats": stats,
	}


## Hooks für missionsspezifischen Zustand (z. B. Begleitperson).
func _serialize_extra() -> Dictionary:
	return {}


func _deserialize_extra(_d: Dictionary) -> void:
	pass


func deserialize(d: Dictionary) -> void:
	for m in squad.members:
		if d["squad"].has(m.persistent_id):
			var md: Dictionary = d["squad"][m.persistent_id]
			m.deserialize(md)
			squad.brain_of(m).deserialize(md.get("brain", {}))
	for e in enemies:
		if d["enemies"].has(e.persistent_id):
			var ed: Dictionary = d["enemies"][e.persistent_id]
			e.deserialize(ed)
			(e.get_node("EnemyBrain") as EnemyBrain).deserialize(ed.get("brain", {}))
			if not e.alive:
				var loot := e.find_children("*", "Interactable", false, false)
				for l in loot:
					(l as Interactable).enabled = true
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it and it.persistent_id != "" and d["interactables"].has(it.persistent_id):
			it.deserialize(d["interactables"][it.persistent_id])
	for n in get_tree().get_nodes_in_group("persistent"):
		if "persistent_id" in n and d["interactables"].has(n.persistent_id):
			n.deserialize(d["interactables"][n.persistent_id])
	for o in objectives:
		if d["objectives"].has(String(o.id)):
			o.state = int(d["objectives"][String(o.id)])
	_deserialize_extra(d.get("extra", {}))
	alarm_raised = d.get("alarm", false)
	elapsed = d.get("elapsed", 0.0)
	stats = d.get("stats", stats)
	squad.formation = int(d.get("formation", SquadManager.Formation.WEDGE))
	squad.spacing_level = int(d.get("spacing_level", 3))
	var act := int(d.get("active", 0))
	if not squad.set_active(act):
		squad.cycle_active()
	Events.say("Spielstand geladen.", 2.0)
