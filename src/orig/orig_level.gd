class_name OrigLevel
extends RefCounted
## Baut einen Original-Level aus dem lokalen Cache (orig_cache/<mission>/), der von
## tools/convert_mission.py aus der HD2-Installation des Nutzers erzeugt wird.
##   scene.glb   statische Szene (Gelände, Gebäude) aus scene.4ds
##   models/*.glb  Modelle der Objektinstanzen
##   scene.json  Objekte aus scene2.bin (Instanzen, Dummies, Lichter, Kameras)
## Originaldateien werden nicht ins Spiel übernommen; ohne Cache bleibt der Level leer.

const CACHE_DIR := "res://orig_cache"
const OBJ_MODEL := 9
const OBJ_DUMMY := 6
const OBJ_LIGHT := 2
const OBJ_CAMERA := 3

var mission_dir := ""
var root: Node3D               ## statische Geometrie (wird ins Navmesh gebacken)
var nodes := {}                ## Name -> Node3D (Frames + Objekte), für Eltern und Skripte
var dummies := {}              ## Name -> Node3D (Ziel-/Skriptpositionen)
var objects: Array = []
var actors: Array = []         ## aus actors.bin: name, model, pos, rot, actor_type, params
var stats := {"meshes": 0, "instances": 0, "colliders": 0, "missing_models": []}
var _model_cache := {}


## Cache-Wurzel: im Projekt res://orig_cache, im Export neben der EXE.
static func cache_root() -> String:
	if DirAccess.dir_exists_absolute(CACHE_DIR):
		return CACHE_DIR
	return OS.get_executable_path().get_base_dir() + "/orig_cache"


static func cache_path(mission: String) -> String:
	return "%s/%s" % [cache_root(), mission.to_lower()]


static func available(mission: String) -> bool:
	return FileAccess.file_exists(cache_path(mission) + "/scene.glb")


func _init(mission: String, parent: Node3D) -> void:
	mission_dir = cache_path(mission)
	root = Node3D.new()
	root.name = "Orig_" + mission
	parent.add_child(root)


func build() -> bool:
	var scene := _load_glb(mission_dir + "/scene.glb")
	if scene == null:
		push_error("Original-Level fehlt: %s (tools/convert_mission.py ausführen)" % mission_dir)
		return false
	root.add_child(scene)
	_index(scene)
	_add_collision(scene)
	var f := FileAccess.open(mission_dir + "/scene.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		objects = data.get("objects", [])
		actors = data.get("actors", [])
		_place_objects()
	return true


func _load_glb(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.base_path = path.get_base_dir()
	if doc.append_from_file(path, state) != OK:
		push_error("glTF nicht ladbar: " + path)
		return null
	return doc.generate_scene(state) as Node3D


func _index(n: Node) -> void:
	if n is Node3D and not nodes.has(String(n.name)):
		nodes[String(n.name)] = n
	if n is MeshInstance3D:
		stats.meshes += 1
	for c in n.get_children():
		_index(c)


## Kollision für alle sichtbaren Meshes (Trimesh). Durchsichtige Vegetation
## (Alpha-Materialien) bekommt keine Kollision.
func _add_collision(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh and not _is_foliage(mi):
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			body.add_child(cs)
			mi.add_child(body)
			stats.colliders += 1
	for c in n.get_children():
		_add_collision(c)


func _is_foliage(mi: MeshInstance3D) -> bool:
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


func _model(name: String) -> Node3D:
	if not _model_cache.has(name):
		var n := _load_glb("%s/models/%s.glb" % [mission_dir, name])
		_model_cache[name] = n
		if n == null:
			stats.missing_models.append(name)
	var src: Node3D = _model_cache[name]
	return src.duplicate() as Node3D if src else null


func _place_objects() -> void:
	# erst alle Objekte erzeugen, dann Eltern zuordnen (Reihenfolge in der Datei beliebig)
	var created: Array = []
	for o in objects:
		var n: Node3D
		var t: int = int(o.get("type", -1))
		if t == OBJ_MODEL and o.has("model"):
			n = _model(o["model"])
			if n == null:
				n = Node3D.new()
			else:
				stats.instances += 1
		else:
			n = Node3D.new()
		n.name = String(o.get("name", "obj")).validate_node_name()
		var p: Array = o.get("pos", [0, 0, 0])
		var r: Array = o.get("rot", [0, 0, 0, 1])
		var s: Array = o.get("scale", [1, 1, 1])
		n.transform = Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3]).normalized()).scaled(Vector3(s[0], s[1], s[2])),
			Vector3(p[0], p[1], p[2]))
		n.set_meta("orig_type", t)
		created.append([n, o])
		if not nodes.has(String(o.get("name", ""))):
			nodes[String(o.get("name", ""))] = n
		if t == OBJ_DUMMY:
			dummies[String(o.get("name", ""))] = n
	for pair in created:
		var n: Node3D = pair[0]
		var parent_name: String = pair[1].get("parent", "")
		var parent: Node3D = nodes.get(parent_name) if parent_name != "" and parent_name != "Primary sector" else null
		if parent == null or parent == n:
			root.add_child(n)
		else:
			parent.add_child(n)
		if int(pair[1].get("type", -1)) == OBJ_MODEL:
			_add_collision(n)


func actor(name: String) -> Dictionary:
	var u := name.to_upper()
	for a in actors:
		if String(a.get("name", "")).to_upper() == u:
			return a
	return {}


static func xform(a: Dictionary) -> Transform3D:
	var p: Array = a.get("pos", [0, 0, 0])
	var r: Array = a.get("rot", [0, 0, 0, 1])
	return Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3]).normalized()), Vector3(p[0], p[1], p[2]))


## Instanz eines konvertierten Modells (z. B. für Akteure); null wenn nicht vorhanden.
func model_instance(name: String) -> Node3D:
	return _model(name.to_lower())


## Modellvorlagen (verwaiste Knoten außerhalb des Baums) freigeben; sonst bleiben Mesh-Instanzen bis zum
## Programmende bestehen (Leck, im Release-Export Absturz beim Beenden).
func release() -> void:
	for k in _model_cache:
		var n = _model_cache[k]
		if is_instance_valid(n) and not (n as Node).is_inside_tree():
			(n as Node).free()
	_model_cache.clear()


## Original-Figur mit Skelett und Animationen (tools/export_characters.py); null wenn nicht vorhanden.
func character_instance(model: String) -> Node3D:
	var key := "char:" + model.to_lower()
	if not _model_cache.has(key):
		_model_cache[key] = _load_glb("%s/characters/%s.glb" % [cache_root(), model.to_lower()])
	var src: Node3D = _model_cache[key]
	return src.duplicate() as Node3D if src else null


## Weltposition eines benannten Frames/Objekts (Skripte: FRM_FindFrame).
func frame_position(name: String) -> Vector3:
	var n: Node3D = nodes.get(name)
	return n.global_position if n else Vector3.INF
