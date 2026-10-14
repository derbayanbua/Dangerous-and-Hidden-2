extends "res://src/missions/orig_generic.gd"
## Mehrspieler-Karte: Original-Level mit Objekten, Türen, Leitern, Fahrzeugen, Lichtern und Klängen –
## ohne KI-Figuren, Skripte und Missionsziele. Spielerfiguren erzeugt der Server (Net).
## Spawnpunkte: orig_cache/<ordner>/mp.json (Original-MP-Karten, tools/fmt_mp.py) – sonst aus den
## Akteuren der Kampagnenmission (Spielerstarts = Team Alliierte, Gegnerpositionen = Team Achse).

var _spawn_points: Array = []


func _spawn_actors() -> void:
	if orig == null or orig.actors.is_empty():
		return
	runtime = LsRuntime.new()
	add_child(runtime)
	runtime.setup(self, orig)
	ls_runtime = runtime
	var ex := OrigExtras.new()
	add_child(ex)
	ex.setup(self, runtime, orig.mission_dir)
	runtime.extras = ex
	for a in orig.actors:
		var nm: String = a.get("name", "")
		var model := String(a.get("model", ""))
		var typ := int(a.get("actor_type", -1))
		var t := actor_xform(a)
		var low := nm.to_lower()
		if typ == 10 or low.begins_with("commando") or low.begins_with("spawnsingle"):
			_spawn_points.append({"pos": t.origin + Vector3.UP * 0.5, "yaw": t.basis.get_euler().y, "team": 0})
			continue
		if typ in [3, 30]:
			if typ == 3:
				_spawn_points.append({"pos": t.origin + Vector3.UP * 0.5, "yaw": t.basis.get_euler().y, "team": 1})
			continue
		if typ == 4:
			_spawn_orig_car(nm, model, t)
			continue
		var inst: Node3D = orig.model_instance(model) if model != "" else null
		if inst == null:
			inst = Node3D.new()
		inst.name = nm.validate_node_name()
		dynamic_root.add_child(inst)
		inst.global_transform = t
		if model != "" and typ in [5, 7, 9, 13, 14, 15, 20, 21, 22, 23, 25, 28]:
			orig._add_collision(inst)
		runtime.register_actor(nm, inst)
	interactive = OrigInteractive.new()
	interactive.name = "OrigInteractive"
	add_child(interactive)
	interactive.setup(self, runtime, orig)
	_load_mp_json()
	print("MP: %d Spawnpunkte" % _spawn_points.size())


## Original-MP-Daten (Spawns je Team), falls vorhanden
func _load_mp_json() -> void:
	var d = LsRuntime._read_json(orig.mission_dir + "/mp.json")
	if typeof(d) != TYPE_DICTIONARY:
		return
	var pts: Array = []
	for sp in d.get("spawns", []):
		var p: Array = sp.get("pos", [])
		if p.size() == 3:
			pts.append({"pos": Vector3(p[0], p[1], p[2]) + Vector3.UP * 0.5, "yaw": float(sp.get("yaw", 0.0)),
				"team": int(sp.get("team", -1))})
	if not pts.is_empty():
		_spawn_points = pts


func mp_spawns() -> Array:
	if _spawn_points.is_empty():
		return [{"pos": Vector3(0, 2, 0), "yaw": 0.0, "team": -1}]
	return _spawn_points


func _setup_objectives() -> void:
	pass       # Mehrspieler: Punkte statt Missionsziele
