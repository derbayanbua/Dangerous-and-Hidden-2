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


## Original-MP-Daten (tools/fmt_mp.py, docs/re_notes_multiplayer.md). Teamnummern im Original:
## 0 = Achse, 1 = Alliierte, 2 = neutral → Soldier.TEAM_AXIS / TEAM_ALLIED / −1
var mp: Dictionary = {}
var _zones: Array = []
var _objectives: Array = []
var _presets := {"allied": [], "axis": []}


static func orig_team(t: int) -> int:
	return Soldier.TEAM_AXIS if t == 0 else (Soldier.TEAM_ALLIED if t == 1 else -1)


static func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() == 3 else Vector3.INF


static func _yaw_of(rot) -> float:
	if rot is Array and rot.size() == 4:
		return Basis(Quaternion(rot[0], rot[1], rot[2], rot[3]).normalized()).get_euler().y
	return 0.0


func _load_mp_json() -> void:
	var d = LsRuntime._read_json(orig.mission_dir + "/mp.json")
	if typeof(d) != TYPE_DICTIONARY:
		return
	mp = d
	var pts: Array = []
	for sp in d.get("spawn_points", d.get("spawns", [])):
		var p := _v3(sp.get("pos", []))
		if p.is_finite():
			pts.append({"pos": p + Vector3.UP * 0.5, "yaw": _yaw_of(sp.get("rot")), "team": orig_team(int(sp.get("team", -1)))})
	if not pts.is_empty():
		_spawn_points = pts
	for z in d.get("zones", []):
		var w: Dictionary = z.get("world", {})
		var slots: Array = []
		for s in z.get("spawn_slots", []):
			var sp2 := _v3(s.get("pos", []))
			if sp2.is_finite():
				slots.append({"pos": sp2 + Vector3.UP * 0.5, "yaw": _yaw_of(s.get("rot"))})
		var sc := _v3(w.get("scale", [1, 1, 1]))
		var xf := Transform3D(Basis(Quaternion(w["rot"][0], w["rot"][1], w["rot"][2], w["rot"][3]).normalized()) if w.has("rot") else Basis(),
			_v3(z.get("center", w.get("pos", [0, 0, 0]))))
		var flags := {}
		for side in ["axis", "allied", "neutral"]:
			var ff = z.get("flag_frames", {}).get(side)
			flags[side] = String(ff["frame"]) if ff is Dictionary else ""
		_zones.append({"name": String(z.get("name", "")), "text": String(z["name_text"]) if z.get("name_text") != null else String(z.get("name", "")),
			"shape": String(z.get("shape", "sphere")), "xf": xf, "scale": sc,
			"radius": float((z.get("radii_world", [5, 5, 5]) as Array)[0]), "capture_time": maxf(float(z.get("capture_time_s", 15)), 1.0),
			"owner": orig_team(int(z.get("initial_owner", 2))), "capturable": bool(z.get("capturable", true)),
			"flags": flags, "slots": slots})
	var style: Dictionary = (d.get("game_styles", []) as Array)[0] if not (d.get("game_styles", []) as Array).is_empty() else {}
	for o in style.get("objectives", []):
		var ob := {"index": int(o["index"]), "team": orig_team(int(o.get("side_team", 1))), "value": int(o.get("value", 1)),
			"type": String(o.get("type", "normal")), "allied_text": String(o.get("allied_text", "")), "axis_text": String(o.get("axis_text", ""))}
		if ob["type"] == "VIP":
			# VIP (0x69D9C0): Seite gegenüber dem Ziel-Team, Uniform vip_uniform_id → Figur (z. B. „Uniform GE14“ → ge14)
			var vt := String(o.get("vip_team", ""))
			ob["vip_team"] = Soldier.TEAM_AXIS if vt == "axis" else (Soldier.TEAM_ALLIED if vt == "allied" else 1 - int(ob["team"]))
			ob["vip_uniform_id"] = int(o.get("vip_uniform_id", -1))
			var un := String(o.get("vip_uniform", "")).strip_edges()
			ob["vip_model"] = un.get_slice(" ", un.get_slice_count(" ") - 1).to_lower() if un != "" else ""
		_objectives.append(ob)
	for p in style.get("presets", []):
		_presets[String(p.get("side", "allied"))].append(p)
	# ALLOWEDITEMS (mpmaplist v1.12, Parser hd2.exe 0x6186F0): im Mehrspieler wählbare Gegenstände der Karte
	_allowed_known = style.has("allowed_items")
	_allowed = style.get("allowed_items", [])
	frontline = bool(style.get("frontline", false))
	# Original-MP-Skripte (mpscripts.dta + scripts.dta) auf allen Rechnern; Ziele wertet der Server aus
	var assign: Dictionary = {}
	for k in d.get("scripts", {}).get("assignments", {}):
		assign.merge(d["scripts"]["assignments"][k])
	if not assign.is_empty():
		var n := runtime.start_scripts(assign)
		print("MP: %d Originalskripte" % n)


var frontline := false


func mp_zones() -> Array:
	return _zones


func mp_objectives() -> Array:
	return _objectives


## HD2-Aufgaben: Lage je Aufgabe = Objekt, dessen Original-MP-Skript diese Aufgabe meldet (mp.json facts)
func mp_objective_points() -> Dictionary:
	var out := {}
	var facts: Dictionary = mp.get("scripts", {}).get("facts", {})
	var assign: Dictionary = {}
	for k in mp.get("scripts", {}).get("assignments", {}):
		assign.merge(mp["scripts"]["assignments"][k])
	for frame in assign:
		var f: Dictionary = facts.get(String(assign[frame]).to_lower(), {})
		for st in f.get("set_objective_status", []):
			if int(st[1]) == 1:
				var node: Node3D = runtime.find_frame(String(frame)) if runtime else null
				if node and node.is_inside_tree():
					out[int(st[0])] = node.global_position
	return out


## Vordefinierte Klassen (Original: 5 je Seite: MG-, Scharf-, Gewehr-, Sturmschütze, Grenadier)
func mp_presets(team: int) -> Array:
	return _presets["axis" if team == Soldier.TEAM_AXIS else "allied"]


var _allowed: Array = []
var _allowed_known := false


## Erlaubte Gegenstände der Karte (mp.json „allowed_items“: item_id, item_num, ammo_num, ammo_item) – leer und
## mp_allowed_known() = false bei Kampagnenkarten als Arena (keine Freigabeliste im Original → unbeschränkt)
func mp_allowed_items() -> Array:
	return _allowed


func mp_allowed_known() -> bool:
	return _allowed_known


## Original-Missionsskripte melden Aufgaben: im Mehrspieler an Net (Punkte für die begünstigte Seite)
func set_orig_objective(index: int, status: int) -> void:
	if status == 1:
		Net.objective_done(index)


func mp_spawns() -> Array:
	if _spawn_points.is_empty():
		return [{"pos": Vector3(0, 2, 0), "yaw": 0.0, "team": -1}]
	return _spawn_points


func _setup_objectives() -> void:
	pass       # Mehrspieler: Punkte statt Missionsziele
