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


## Helligkeitsfaktor an einer Position (für die Sicht-Erkennung).
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
	Effects.start_ambience(self, func() -> Vector3:
		return rig.camera.global_position if is_instance_valid(rig) else Vector3.ZERO)


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


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	# Werte als Vielfache der Zellgröße (sonst rundet Recast mit Warnung)
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | (1 << 4)   # Welt + Zäune
	nm.region_min_size = 4.0
	nm.filter_low_hanging_obstacles = true
	nm.filter_ledge_spans = true
	nm.filter_walkable_low_height_spans = true
	nav_region.navigation_mesh = nm   # Kartenzellgröße: project.godot navigation/3d/*
	nav_region.bake_finished.connect(func():
		nav_ready = true
		print("NAV: Navigationsnetz fertig (%d Polygone)" % nav_region.navigation_mesh.get_polygon_count()))
	# Asynchron backen; KI läuft bis dahin direkt auf Ziele zu.
	nav_region.bake_navigation_mesh.call_deferred(true)


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
		spawn_squad_member(start + Basis(Vector3.UP, yaw) * off, yaw, r["name"], Game.loadout_for(r["pid"]), r["pid"])


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
		0, 2:
			# 0 = in Arbeit, 2 = wieder offen (z. B. Beweisstück aus dem Inventar entfernt)
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


func _check_orig_completion() -> void:
	if finished or orig_objectives.is_empty():
		return
	for o in objectives:
		if not o.optional and o.state != Objective.State.DONE:
			return
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
	if finished:
		return
	if s is Soldier and (s as Soldier).team == Soldier.TEAM_AXIS and attacker is Soldier \
			and (attacker as Soldier).team == Soldier.TEAM_ALLIED:
		stats["kills"] += 1
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
	var fallen := []
	for mm in squad.members:
		if not mm.alive:
			fallen.append(mm.persistent_id)
	Game.last_result["fallen"] = fallen.map(func(pid): return _name_of(pid))
	Game.record_mission_result(Game.current_mission_id, success, fallen)
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
		"squad": sq, "active": squad.active_index, "formation": squad.formation,
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
	squad.formation = int(d.get("formation", 0))
	var act := int(d.get("active", 0))
	if not squad.set_active(act):
		squad.cycle_active()
	Events.say("Spielstand geladen.", 2.0)
