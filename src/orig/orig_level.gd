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
	var klz := _load_collision_info()
	if not klz:
		_add_collision(scene)
	var f := FileAccess.open(mission_dir + "/scene.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		objects = data.get("objects", [])
		actors = data.get("actors", [])
		_place_objects(not klz)
	if klz:
		_build_orig_collision()
	return true


# --- Kollision wie im Original (tree.klz + scene2.bin, tools/fmt_klz.py → collision.json) -------------------
## Original [B, docs/re_notes_collision.md]: Begehbar ist nur, was tree.klz als Flächenkollision verlinkt. Die
## Leveldesigner ersetzen Treppen, Podeste usw. durch unsichtbare Ersatzkörper (scene2.bin Chunk 0x4033 = versteckt,
## z. B. Rampen x_schody*/xx_schod_col_*, VOLUM_*); die sichtbaren Stufen selbst haben keine Flächenkollision.
## Nachbau: versteckte Frames unsichtbar (Kollision nur mit Klz-Link), sichtbare Frames ohne eigene Klz-Flächen,
## die vollständig in einem versteckten begehbaren Ersatzkörper liegen, ohne Kollision; alles Übrige wie bisher
## (Trimesh des sichtbaren Meshes als Näherung der Klz-Flächen/-Kisten).
var _klz_faces := {}      ## Name bzw. „Objekt.Frame“ -> true (Bit 0: Flächen)
var _klz_vols := {}       ## nur Kistenvolumen (Bit 1)
var _hidden := {}         ## scene2.bin 0x4033
var _klz_pass := {}       ## tree.klz-Links mit Bit 0x100000 (Grenze, Drahtgeflecht, Zelt): nur Bewegung sperren (Ebene 5)
var _klz_boxes := {}      ## Kisten (XTOBB/AABB) – solche Frames behalten ihre Kollision


func _load_collision_info() -> bool:
	var f := FileAccess.open(mission_dir + "/collision.json", FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for pair in [["faces", _klz_faces], ["volumes", _klz_vols], ["hidden", _hidden], ["boxes", _klz_boxes],
			["pass_through", _klz_pass]]:
		for n in d.get(pair[0], []):
			pair[1][_klz_key(String(n))] = true
	return true


## Knotennamen sind in Godot bereinigt (validate_node_name); „Objekt.Frame“ teilweise bereinigen
static func _klz_key(n: String) -> String:
	var i := n.find(".")
	if i > 0:
		return n.substr(0, i).validate_node_name() + "." + n.substr(i + 1).validate_node_name()
	return n.validate_node_name()


const PROXY_MAX_EXTENT := 40.0     ## m: größere versteckte Körper sind keine Ersatzkörper (Kartenränder, Taktikgrenze)


func _build_orig_collision() -> void:
	var meshes: Array = []          # [MeshInstance3D, versteckt, Flächen, Volumen, Kiste]
	_klz_walk(root, "", false, meshes)
	var proxies: Array[AABB] = []
	var proxy_names: Array[String] = []
	var proxy_strict: Array[bool] = []     ## sichtbare Rampe: nur Stufenkörper (≥ 20 % ihres Volumens) ersetzen
	for e in meshes:
		var mi: MeshInstance3D = e[0]
		if not e[2] or mi.mesh == null:
			continue
		var sh := _slope_shares(mi)
		# versteckter Ersatzkörper – oder eine sichtbar gebliebene Designer-Rampe (ARCTIC3 x_schody02: wenige
		# Dreiecke, überwiegend 10–50° geneigt)
		var wb := mi.global_transform * mi.get_aabb()
		var ramp: bool = not e[1] and mi.mesh.get_faces().size() <= 48 and sh.y >= 0.5 and wb.size.y >= 0.4 \
			and wb.size.y <= 6.0 and maxf(wb.size.x, wb.size.z) <= 15.0      # keine Dachflächen/Hänge
		# Ersatzkörper sind Treppen-/Podestkörper, keine kartengroßen Hilfsflächen: CZECH1 „tactical_mode_border/border03“
		# (versteckt, Klz-Fläche, ~ganzer Bahnhof) hob sonst die Kollision von 2403 sichtbaren Frames auf (Treppen, Möbel;
		# test_stairs CZECH1 0/5) [B-010]
		var huge: bool = maxf(wb.size.x, wb.size.z) > PROXY_MAX_EXTENT or String(mi.get_path()).contains("tactical_mode")
		if ((e[1] and sh.x >= 0.2) or ramp) and not huge:
			proxies.append((mi.global_transform * mi.get_aabb()).grow(0.3))
			proxy_names.append(String(mi.name))
			proxy_strict.append(ramp and not e[1])
			mi.set_meta("klz_proxy", true)
	stats["proxies"] = proxies.size()
	stats["proxied"] = 0
	var dbg := Game.cli.has("klz_debug")
	for e in meshes:
		var mi: MeshInstance3D = e[0]
		var collide: bool = e[2] or e[3]            # versteckt: nur mit Klz-Link
		if _in_backdrop(mi):
			# Himmelskulisse (Objekte im „Backdrop sector“, z. B. AFRICA2 g_AF2_sky): keine Kollision – sonst blockiert
			# die Himmelskugel Schüsse nach oben und die Sicht angreifender Flugzeuge (Akteurtyp 36)
			_mesh_collider(mi, false)
			continue
		if not e[1] and not e[2] and not e[4]:      # sichtbar, ohne Klz-Flächen und ohne Kiste (nur OBB/kein Link)
			collide = true
			var box := mi.global_transform * mi.get_aabb()
			for k in proxies.size():
				if proxies[k].encloses(box) and (not proxy_strict[k] or _vol(box) >= 0.2 * _vol(proxies[k].grow(-0.3))):
					collide = false                 # Original: nur der versteckte Ersatzkörper kollidiert
					stats.proxied += 1
					if dbg:
						print("KLZ: %s (%s) -> Ersatz %s" % [mi.name, mi.get_parent().name, proxy_names[k]])
					break
		# Klz-Ebenen wirken beidseitig (Ersatzkörper/Treppenuntersichten ARCTIC2 T2_strop_03 zeigen teils nach unten);
		# ebenso Wände: von hinten/innen getroffene einseitige Trimeshes ließen Kamera-Kugel und Figur durch (Fix A1
		# 24.10.2026, test_a1_collision). Klz-Flächenlink = Kollision auch bei Alpha-Material (ARCTIC1 Gelände-
		# Kacheln Object121–154 mit Überblendschicht G_A1_10T galten als „Laub“ -> keine Kollision -> Durchfallen).
		if Game.cli.has("collision_legacy"):       # Vergleichslauf alter Stand (test_a1_collision vorher/nachher)
			_mesh_collider(mi, collide, e[1] or mi.has_meta("klz_proxy"))
		else:
			_mesh_collider(mi, collide, true, e[2])
		if e[5]:
			# Klz-Bit 0x100000 (Grenze „Border - enemy filter“, Drahtgeflecht, Zeltplane): sperrt nur Bewegung, Sicht und
			# Geschosse gehen durch (Ebene 5 wie Zäune) [P, docs/re_notes_script_anims.md §6]
			for c in mi.get_children():
				if c is StaticBody3D:
					(c as StaticBody3D).collision_layer = 1 << 4
			stats["pass_through"] = int(stats.get("pass_through", 0)) + 1


static func _in_backdrop(n: Node) -> bool:
	while n != null:
		if n.has_meta("backdrop"):
			return true
		n = n.get_parent()
	return false


func _klz_walk(n: Node, obj: String, hidden: bool, out: Array) -> void:
	var key := ""
	if n.has_meta("klz_obj"):
		obj = String(n.get_meta("klz_obj"))       # Objektinstanz aus scene2.bin: Links „Objekt.Frame“
		key = obj
	elif n != root:
		key = String(n.name) if obj == "" else obj + "." + String(n.name)
	# nur Geometrie verstecken (Frames, Modellobjekte); Dummies/Lichter/Klänge behalten ihre Sichtbarkeit
	if key != "" and _hidden.has(key) and n is Node3D and int(n.get_meta("orig_type", OBJ_MODEL)) == OBJ_MODEL:
		hidden = true
		(n as Node3D).visible = false
		stats["hidden"] = int(stats.get("hidden", 0)) + 1
	if n is MeshInstance3D:
		out.append([n, hidden, _klz_faces.has(key), _klz_vols.has(key), _klz_boxes.has(key), _klz_pass.has(key)])
	for c in n.get_children():
		if not (c is CollisionObject3D):
			_klz_walk(c, obj, hidden, out)


static func _vol(b: AABB) -> float:
	return maxf(b.size.x, 0.1) * maxf(b.size.y, 0.1) * maxf(b.size.z, 0.1)


## Flächenanteile: x = begehbar (|n.y| > 0,5; Rampen/Podeste ja, reine Wände/Kartenrand nein),
## y = Rampe (10–50° geneigt)
static func _slope_shares(mi: MeshInstance3D) -> Vector2:
	var f := mi.mesh.get_faces()
	var b := mi.global_transform.basis
	var total := 0.0
	var walk := 0.0
	var ramp := 0.0
	for i in range(0, f.size() - 2, 3):
		var n := (b * (f[i + 1] - f[i])).cross(b * (f[i + 2] - f[i]))
		var a := n.length()
		total += a
		if a > 0.0 and absf(n.y) > 0.5 * a:
			walk += a
		if a > 0.0 and absf(n.y) > 0.643 * a and absf(n.y) < 0.985 * a:
			ramp += a
	return Vector2(walk, ramp) / total if total > 0.0 else Vector2.ZERO


func _load_glb(path: String) -> Node3D:
	# Vorlage aus dem Hintergrundladen/Zwischenspeicher (MissionLoader): Kopie statt erneutem glTF-Parsen
	var pre := MissionLoader.take(path)
	if pre:
		return pre
	var n := parse_glb(path)
	MissionLoader.remember(path, n)
	return n


## glTF laden (auch aus Arbeits-Threads des MissionLoader; Knoten außerhalb des Baums)
static func parse_glb(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.base_path = path.get_base_dir()
	if doc.append_from_file(path, state) != OK:
		push_error("glTF nicht ladbar: " + path)
		return null
	_swap_textures(state)
	return doc.generate_scene(state) as Node3D


## Texturqualität (Original-Setup „Text.-Qual.“): Bilddaten der referenzierten Original-PNG gegen die
## KI-Fassung aus textures_hd/textures_4k tauschen (gleicher Dateiname); glTF-Dateien bleiben unverändert.
static var _hq_cache := {}
static var _hq_mutex := Mutex.new()      ## Hintergrundladen in mehreren Threads

static func _swap_textures(state: GLTFState) -> void:
	var sfx: Array = Settings.texture_suffixes()
	if sfx == [""]:
		return
	var imgs := state.get_images()
	var js: Dictionary = state.json
	var jimgs: Array = js.get("images", [])
	for i in mini(imgs.size(), jimgs.size()):
		var uri := String(jimgs[i].get("uri", ""))
		if uri == "" or not (imgs[i] is ImageTexture):
			continue
		var file := uri.get_file()
		var key := "%s|%s" % [sfx[0], file]
		_hq_mutex.lock()
		var hq: Image = _hq_cache.get(key)
		_hq_mutex.unlock()
		if hq == null:
			for s in sfx:
				if s == "":
					break
				var p := "%s/textures%s/%s" % [cache_root(), s, file]
				if FileAccess.file_exists(p):
					hq = Image.load_from_file(p)
					if hq:
						hq.generate_mipmaps()
						_hq_mutex.lock()
						_hq_cache[key] = hq
						_hq_mutex.unlock()
					break
		if hq:
			(imgs[i] as ImageTexture).set_image(hq)


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
		_mesh_collider(n as MeshInstance3D, true)
	for c in n.get_children():
		_add_collision(c)


## Gras/Wasser erfassen und (collide) Trimesh-Kollision anlegen
func _mesh_collider(mi: MeshInstance3D, collide: bool, two_sided := false, klz_faces := false) -> void:
	var foliage := mi.mesh != null and _is_foliage(mi)
	if foliage and mi.get_aabb().size.y < 1.5 and not klz_faces:
		grass_nodes.append(mi)
	if klz_faces:
		foliage = false        # Original: in tree.klz als Flächen verlinkt -> begehbar/fest, egal welches Material
	if mi.mesh and not foliage and _is_water(mi, klz_faces):
		# Wasserfläche (QuadPatch/„more“, Material VODA*/MORE*): keine Kollision, als Wasserbereich merken
		var box: AABB = mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		water.append(box)
	elif collide and mi.mesh and not foliage and _has_area(mi.mesh):    # entartete Meshes (Linien, Flächen ohne Inhalt) ohne Kollision
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		if two_sided:
			# Klz-Ebenen wirken beidseitig; versteckte Ersatzkörper sind teils nach unten orientiert (ARCTIC2 T1_strop_19)
			(cs.shape as ConcavePolygonShape3D).backface_collision = true
		body.add_child(cs)
		mi.add_child(body)
		stats.colliders += 1


static func _has_area(mesh: Mesh) -> bool:
	var f := mesh.get_faces()
	for i in range(0, f.size() - 2, 3):
		if (f[i + 1] - f[i]).cross(f[i + 2] - f[i]).length_squared() > 1e-10:
			return true
	return false


## Wasserflächen (Welt-AABB, Oberkante = Wasserspiegel): Schwimmen/Tauchen (Soldier, Mission.water_level_at)
var water: Array[AABB] = []


## klz_faces: in tree.klz als begehbare Fläche verlinkt – dann zählt nur ein Wassermaterial (VODA*/MORE*), nicht der
## Name: ARCTIC1 „m_ark01_hrdr_.QuadPatch01“ (Haupteingang, links) ist Klz-Fläche mit Material 36 „Schnee – kugelfest“
## (surface.bin) und Textur G_A1_1B, galt aber wegen „QuadPatch“ als Wasser -> keine Kollision, Schwimmen (B-017).
static func _is_water(mi: MeshInstance3D, klz_faces := false) -> bool:
	var box := mi.get_aabb()
	if box.size.y > 0.8 or box.size.x * box.size.z < 16.0:
		return false       # Wasser ist eine große, flache Fläche
	var nm := String(mi.name).to_lower() + "|" + String(mi.get_parent().name).to_lower()
	# „more“ = Meer (ARCTIC1 more2 = U-Boot-Becken mit Filmtextur, ohne Klz-Link; war einseitig nach unten
	# orientiert und kollidierte erst mit beidseitigen Trimeshes -> sperrte das Navmesh der Bunkertreppe)
	if not klz_faces and (nm.contains("quadpatch") or nm.begins_with("more") or nm.contains("|more")):
		return true
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		var rn := (m.resource_name if m else "").to_lower()
		if rn.begins_with("voda") or rn.begins_with("more"):
			return true
	return false


## Wasserspiegel an einer Position (NAN = kein Wasser)
func water_level_at(p: Vector3) -> float:
	var best := NAN
	for b in water:
		if p.x >= b.position.x and p.x <= b.end.x and p.z >= b.position.z and p.z <= b.end.z:
			var top := b.end.y
			if p.y < top + 0.5 and (is_nan(best) or top > best):
				best = top
	return best


## Original-Option „GRAS“: niedrige Vegetation (Alpha-Material, < 1,5 m hoch) ein-/ausblenden
var grass_nodes: Array[MeshInstance3D] = []


func apply_grass_setting() -> void:
	for g in grass_nodes:
		if is_instance_valid(g):
			g.visible = Settings.grass


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


func _place_objects(collide := true) -> void:
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
		n.set_meta("klz_obj", String(n.name))
		if String(o.get("parent", "")) == "Backdrop sector":
			n.set_meta("backdrop", true)      # Himmelskulisse (LS3D-Backdrop-Sektor): nie Kollision
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
		if collide and int(pair[1].get("type", -1)) == OBJ_MODEL and not n.has_meta("backdrop"):
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
