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
	_apply_walk_patches()
	_build_display_extras()
	return true


## B-036 [D]: unsichtbare Lauf-Korrekturen je Karte ([D]: „ohne Leertaste die Treppe hinauf“).
## kind "ramp": begehbare Fläche von a nach b (Oberkante durch a und b, Breite w); kind "guide": senkrechte Leitwand
## von a nach b, Höhe h, damit man nicht in eine Spalte/Keilfläche läuft, sondern in die begehbare Gasse gleitet.
## Liegen unter der statischen Geometrie → gehen ins Navmesh ein (Cache-Schlüssel enthält die Quellgeometrie).
## kind "stair" (B-010b): nur Navigation – NavigationLink3D vom Fuß (a = unterster Tritt, 0,55 m davor, eine Stufe
## tiefer) zum Austritt (b = oberster Tritt, 0,45 m dahinter, eine Stufe höher). Für steile Original-Stahltreppen mit
## echter Stufenkollision, die Recast nicht als Fläche erfasst (überlappende Tritte → kein Kopfraum je Rasterspalte);
## die KI läuft den Link wie einen Weg (AIBrain: ohne Meta „climb“/„ladder“ einfach weiter). Physik unverändert,
## kein Navmesh-Neubau (Links sind dynamisch, nicht im Cache). Tritte aus test_stairs (`stairs_report*`).
const WALK_PATCHES := {
	# NORWAY (nw1_dampfleitung): 14 Stahltreppen, test_stairs T1–T16 (T3/T4/T7/T8 = Doppelfunde von T1/T2/T5/T6).
	# T17/T18 fehlen bewusst: auch der Spieler kommt dort nicht hinauf (Kopfraum), ein Link führte die KI in die Falle.
	"norway": [
		{"kind": "stair", "a": Vector3(60.2, 5.1, -270.0), "b": Vector3(60.2, 7.4, -267.6)},
		{"kind": "stair", "a": Vector3(50.8, 5.1, -270.0), "b": Vector3(50.8, 7.4, -267.6)},
		{"kind": "stair", "a": Vector3(60.1, 7.6, -263.5), "b": Vector3(60.1, 9.9, -261.1)},
		{"kind": "stair", "a": Vector3(50.9, 7.6, -263.5), "b": Vector3(50.9, 9.9, -261.1)},
		{"kind": "stair", "a": Vector3(-115.9, 6.8, -330.2), "b": Vector3(-115.1, 9.0, -328.2)},
		{"kind": "stair", "a": Vector3(-110.3, 6.8, -316.3), "b": Vector3(-109.5, 9.0, -314.3)},
		{"kind": "stair", "a": Vector3(-97.7, 6.8, -339.1), "b": Vector3(-96.6, 9.0, -337.2)},
		{"kind": "stair", "a": Vector3(-57.8, 6.7, -249.9), "b": Vector3(-58.7, 9.0, -252.0)},
		{"kind": "stair", "a": Vector3(-69.9, 6.7, -244.1), "b": Vector3(-71.1, 9.0, -246.0)},
		{"kind": "stair", "a": Vector3(-90.2, 6.8, -326.3), "b": Vector3(-89.1, 9.0, -324.4)},
		{"kind": "stair", "a": Vector3(-91.9, 9.4, -323.3), "b": Vector3(-91.2, 11.4, -321.8)},
		{"kind": "stair", "a": Vector3(-106.8, 9.4, -316.0), "b": Vector3(-106.1, 11.4, -314.5)},
	],

	# ARCTIC2 T1 (B-036: keine Lauf-Korrektur nötig, T1_sten_67 ist die schräge Innenbegrenzung): B-010b nur Navigation –
	# die Stockwerke waren im Netz nur senkrecht verbunden (Scherentreppe, Läufe überdecken sich) → Link je Rampe 01–08.
	"arctic2": [
		{"kind": "ramp_links", "match": "xT1_schod_", "a": Vector3.ZERO, "b": Vector3.ZERO},
	],
}


## kind "ramp_links": je versteckter Ersatzrampe (Frame-Name enthält "match", mit Kollisionskörper) ein Link vom
## unteren zum oberen Ende (Mittel der Eckpunkte ≤ 0,15 m über dem Tiefst- bzw. unter dem Höchstpunkt, je 0,6 m über
## das Ende hinaus). Für Scherentreppen, deren Läufe sich in der Draufsicht überdecken (ARCTIC2 T1).
func _ramp_links(body: Node3D, pat: String) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not String(mi.name).to_lower().contains(pat):
			continue
		if mi.find_children("*", "StaticBody3D", false, false).is_empty():
			continue                                    # ohne Körper (ARCTIC2 xT1_schod_09/10) nicht begehbar
		var xf := Transform3D()
		var q: Node = mi
		while q != null and q != root:
			if q is Node3D:
				xf = (q as Node3D).transform * xf
			q = q.get_parent()
		var vs: Array[Vector3] = []
		var lo := INF
		var hi := -INF
		for v in mi.mesh.get_faces():
			var w: Vector3 = xf * v
			vs.append(w)
			lo = minf(lo, w.y)
			hi = maxf(hi, w.y)
		if hi - lo < 0.5:
			continue
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		var na := 0
		var nb := 0
		for w in vs:
			if w.y <= lo + 0.15:
				a += w
				na += 1
			elif w.y >= hi - 0.15:
				b += w
				nb += 1
		a /= maxi(na, 1)
		b /= maxi(nb, 1)
		a.y = lo
		b.y = hi
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var link := NavigationLink3D.new()
		link.name = "RampLink_%s" % mi.name
		link.bidirectional = true
		link.set_meta("stair", true)
		body.add_child(link)
		link.start_position = a - dir * 0.6
		link.end_position = b + dir * 0.6
		stats["stair_links"] = int(stats.get("stair_links", 0)) + 1
		if Game.cli.has("klz_debug"):
			print("KLZ: Rampen-Link %s %s -> %s" % [mi.name, link.start_position, link.end_position])


func _apply_walk_patches() -> void:
	var key := mission_dir.get_file().to_lower()
	if not WALK_PATCHES.has(key):
		return
	var body := StaticBody3D.new()
	body.name = "WalkPatches"
	body.collision_layer = 1
	root.add_child(body)
	for p: Dictionary in WALK_PATCHES[key]:
		var a: Vector3 = p["a"]
		var b: Vector3 = p["b"]
		if p["kind"] == "ramp_links":
			if not Game.cli.has("nav_stair_links_off"):
				_ramp_links(body, String(p["match"]).to_lower())
			continue
		if p["kind"] == "stair":
			if Game.cli.has("nav_stair_links_off"):
				continue
			var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var link := NavigationLink3D.new()
			link.name = "StairLink%d" % body.get_child_count()
			link.bidirectional = true
			link.set_meta("stair", true)
			body.add_child(link)
			link.start_position = a - dir * 0.55 + Vector3.DOWN * 0.16
			link.end_position = b + dir * 0.45 + Vector3.UP * 0.16
			stats["stair_links"] = int(stats.get("stair_links", 0)) + 1
			continue
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var d := b - a
		var flat := Vector3(d.x, 0, d.z)
		var yaw := atan2(flat.x, flat.z)
		if p["kind"] == "guide":
			var h: float = p.get("h", 1.2)
			box.size = Vector3(0.06, h, flat.length())
			cs.transform = Transform3D(Basis(Vector3.UP, yaw), (a + b) * 0.5 + Vector3.UP * h * 0.5)
		else:
			var thick := 0.12
			var pitch := -atan2(d.y, flat.length())
			box.size = Vector3(float(p.get("w", 1.0)), thick, d.length())
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
			cs.transform = Transform3D(basis, (a + b) * 0.5 - basis.y * thick * 0.5)
		cs.shape = box
		body.add_child(cs)


# --- B-035: Glows, Umhängungen, Lichtkegel, Lightmaps (tools/fmt_glows.py, tools/fmt_lightmaps.py) ---------------
## glows.json [B scene.4ds Visual 6]: Glow-Elemente (Größe, Textur) → additive Sprite3D am Frame + kleines Licht [E].
## lightmaps.json [B scene2.bin]: 0x4020-Umhängungen (z. B. NORMANDY majak_volum01/vol_majak01/02 → m_maj_svet01,
## damit drehen Lichtkegel und Glows mit FRM_RotateY des Leuchtturmlichts), Lightmap-Stufen und -Gruppen.
var lightmaps := {}            ## levels/groups/reparent/lens aus lightmaps.json
var glow_nodes: Array = []     ## Frames mit Glow-Sprites
var volumetric_nodes: Array = []
var _lm_level := {}            ## Frame-Name -> aktive Skriptstufe
const GLOW_LIGHT_RANGE := 8.0  ## m [E]
const GLOW_LIGHT_ENERGY := 1.5 ## [E]


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _build_display_extras() -> void:
	lightmaps = _read_json(mission_dir + "/lightmaps.json")
	var glows := _read_json(mission_dir + "/glows.json")
	var scripted := {}
	var fs := _read_json(mission_dir + "/scene.json")
	for k in fs.get("scripts", {}):
		scripted[String(k)] = true
	# Umhängung nur für Glow-/Lichtkegel-Frames und Kinder skriptgesteuerter Frames (statische Wände bleiben unberührt) [E]
	var glow_names := {}
	for g in glows.get("glows", []):
		glow_names[String(g.get("name", ""))] = true
	var rp: Dictionary = lightmaps.get("reparent", {})
	for child_name in rp:
		var par_name := String(rp[child_name])
		var cn := String(child_name)
		if not (glow_names.has(cn) or cn.to_lower().contains("volum") or scripted.has(par_name)):
			continue
		var c: Node3D = nodes.get(cn.validate_node_name(), nodes.get(cn))
		var p: Node3D = nodes.get(par_name.validate_node_name(), nodes.get(par_name))
		if c and p and c != p and c.get_parent() != p and not p.is_ancestor_of(c) and not c.is_ancestor_of(p):
			c.reparent(p, true)
			stats["reparented"] = int(stats.get("reparented", 0)) + 1
	for n in nodes.values():
		if n is MeshInstance3D and String(n.name).to_lower().contains("volum"):
			_make_volumetric(n as MeshInstance3D)
	for g in glows.get("glows", []):
		var gn := String(g.get("name", ""))
		var node: Node3D = nodes.get(gn.validate_node_name(), nodes.get(gn))
		if node:
			_add_glow(node, g.get("elements", []))


## Lichtkegel (NORMANDY majak_volum01, Material G_F1_MAJAK, Alpha 0,25): selbstleuchtend, additiv [P]
func _make_volumetric(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as StandardMaterial3D
		if m == null or m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var nm := m.duplicate() as StandardMaterial3D
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		nm.cull_mode = BaseMaterial3D.CULL_DISABLED
		nm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.set_surface_override_material(s, nm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	volumetric_nodes.append(mi)


func _add_glow(node: Node3D, elements: Array) -> void:
	var col := Color(1, 0.95, 0.8)
	for e in elements:
		var tex_name := String(e.get("texture", "")).get_basename().to_lower()
		var p := "%s/textures/%s.png" % [cache_root(), tex_name]
		if tex_name == "" or not FileAccess.file_exists(p):
			continue
		var img := Image.load_from_file(p)
		if img == null:
			continue
		var sp := Sprite3D.new()
		sp.name = "Glow_" + tex_name
		sp.texture = ImageTexture.create_from_image(img)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		sp.double_sided = true
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Elementgröße in Frame-Einheiten (Frame-Skalierung wirkt mit, z. B. 4,14 am Leuchtturm) [P]
		sp.pixel_size = float(e.get("size", 1.0)) / maxf(float(img.get_width()), 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = sp.texture
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sp.material_override = mat
		node.add_child(sp)
	var light := OmniLight3D.new()
	light.name = "GlowLight"
	light.light_color = col
	light.omni_range = GLOW_LIGHT_RANGE
	light.light_energy = GLOW_LIGHT_ENERGY
	light.shadow_enabled = false
	node.add_child(light)
	glow_nodes.append(node)


func lightmap_group(group: String) -> Array:
	var g: Dictionary = lightmaps.get("groups", {})
	if g.has(group):
		return g[group]
	for k in g:
		if String(k).to_lower() == group.to_lower():
			return g[k]
	return []


## Helligkeitsfaktor der Skriptstufe (Satz n+1) relativ zu Stufe 0; 1.0 ohne Daten
func lightmap_factor(frame_name: String, level: int) -> float:
	var lv: Dictionary = lightmaps.get("levels", {})
	var d = lv.get(frame_name)
	if d == null:
		for k in lv:
			if String(k).to_lower() == frame_name.to_lower():
				d = lv[k]
				break
	if typeof(d) != TYPE_DICTIONARY:
		return 1.0
	var base := float(d.get("1", 0.0))
	if base <= 0.0:
		return 1.0
	var key := str(level + 1)
	if not d.has(key):
		return _median_ratio(key)     # Satz in den Daten nicht lesbar → Median der vollständigen Frames [P]
	return clampf(float(d[key]) / base, 0.15, 3.0)


var _median_cache := {}


func _median_ratio(key: String) -> float:
	if _median_cache.has(key):
		return _median_cache[key]
	var r: Array = []
	var lv: Dictionary = lightmaps.get("levels", {})
	for k in lv:
		var d: Dictionary = lv[k]
		if d.has(key) and float(d.get("1", 0.0)) > 0.0:
			r.append(float(d[key]) / float(d["1"]))
	r.sort()
	var v := 1.0 if r.is_empty() else clampf(float(r[r.size() / 2]), 0.15, 3.0)
	_median_cache[key] = v
	return v


func lightmap_level(frame_name: String) -> int:
	return int(_lm_level.get(frame_name.to_lower(), 0))


## Lightmap-Stufe setzen: Albedo aller Meshes des Frames × Faktor (Ursprungsfarbe bleibt in Meta „lm_base“)
func set_lightmap(frame: Node3D, frame_name: String, level: int) -> float:
	_lm_level[frame_name.to_lower()] = level
	var f := lightmap_factor(frame_name, level)
	var meshes: Array = []
	if frame is MeshInstance3D:
		meshes.append(frame)
	meshes.append_array(frame.find_children("*", "MeshInstance3D", true, false))
	for mi in meshes:
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for s in m3.mesh.get_surface_count():
			var m := m3.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			if not m.has_meta("lm_base"):
				m = m.duplicate() as BaseMaterial3D
				m.set_meta("lm_base", m.albedo_color)
				m3.set_surface_override_material(s, m)
			var b: Color = m.get_meta("lm_base")
			m.albedo_color = Color(b.r * f, b.g * f, b.b * f, b.a)
	return f


## DECORATOR_SetOn: Bewuchs aus/an (Grafikoption „Gras“ bleibt Voraussetzung)
func set_decorator(on: bool) -> void:
	for g in grass_nodes:
		if is_instance_valid(g):
			g.visible = on and Settings.grass


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
			# B-036: Sichtverdecker („xxx_occlude01“ ARCTIC4 bei (−130; 0; 35), „yyy_occlude…“, „occlude104“) sind reine
			# Render-Hilfskörper ohne Klz-Link – im Original ohne Kollision; hier sperrten sie den Weg (a4 Löser fest)
			if String(mi.name).to_lower().contains("occlude") or String(mi.get_parent().name).to_lower().contains("occlude"):
				collide = false
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
		if collide and not e[1] and not e[2] and not e[3] and not e[4]:
			# fix_no2_panzer: sichtbarer Frame ganz ohne Klz-Link (kein Original-Kollisionskörper) und klein (≤ 8 m Grundriss,
			# ≤ 3 m hoch: Schutt „m_trosky_*“, Kleinkram) – Figuren/Geschosse kollidieren weiter, Fahrzeuge fahren hindurch
			# (Vehicle._passable_exceptions). NORMANDY2: Sherman blieb an m_trosky_07 (3,5 × 4,3 m, 2,6 m hoch inkl. 1,2 m
			# unter Gelände) auf AmiiTank_2 hängen. Große Frames ohne Link (Gebäudeteile) bleiben für Fahrzeuge fest [E].
			var wb2 := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
			if wb2.size.y <= 3.0 and maxf(wb2.size.x, wb2.size.z) <= 8.0:
				for c in mi.get_children():
					if c is StaticBody3D:
						c.add_to_group(&"vehicle_passable")
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
	var comp := PerfTuning.b039("tex_compress")    # B-039 (Eingriff B-039, nur diese Funktion)
	if sfx == [""]:
		if comp:
			_compress_state_images(state, {})
		return
	var imgs := state.get_images()
	var js: Dictionary = state.json
	var jimgs: Array = js.get("images", [])
	var swapped := {}
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
			var orig_img := (imgs[i] as ImageTexture).get_image()
			for s in sfx:
				if s == "":
					break
				var p := "%s/textures%s/%s" % [cache_root(), s, file]
				if FileAccess.file_exists(p) and not _hq_rejected(s, file):
					hq = Image.load_from_file(p)
					if hq and not _hq_fits(orig_img, hq):
						hq = null       # B-042: falsche Proportion/Alpha verloren → nächste Stufe
						continue
					if hq:
						hq.generate_mipmaps()
						if comp:
							PerfTuning.compress_image(hq)
						_hq_mutex.lock()
						_hq_cache[key] = hq
						_hq_mutex.unlock()
					break
		if hq:
			(imgs[i] as ImageTexture).set_image(hq)
			swapped[i] = true
			_hq_mutex.lock()
			hq_stats["swapped"] += 1
			_hq_mutex.unlock()
	if comp:
		_compress_state_images(state, swapped)


## B-042: Ablehnungsliste je Stufe (tools/b042_texcheck.py --write → textures<stufe>/_reject.txt: Farbabweichung,
## Seitenverhältnis, Alpha verloren). Abgelehnte Dateien fallen auf die nächste Stufe zurück (4K → HD → Original).
static var _reject := {}
static var hq_stats := {"swapped": 0, "rejected": 0, "unfit": 0}

static func _hq_rejected(suffix: String, file: String) -> bool:
	_hq_mutex.lock()
	if not _reject.has(suffix):
		var names := {}
		var f := FileAccess.open("%s/textures%s/_reject.txt" % [cache_root(), suffix], FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line := f.get_line()
				if line != "" and not line.begins_with("#"):
					names[line.get_slice("\t", 0)] = true
		_reject[suffix] = names
	var r: bool = (_reject[suffix] as Dictionary).has(file)
	if r:
		hq_stats["rejected"] += 1
	_hq_mutex.unlock()
	return r


## B-042: KI-Fassung passt zum Original (gleiches Seitenverhältnis ±1 %, Alphakanal erhalten)?
static func _hq_fits(orig: Image, hq: Image) -> bool:
	if orig == null or hq == null or orig.get_width() == 0 or orig.get_height() == 0:
		return hq != null
	var ro := float(hq.get_width()) / orig.get_width()
	var rh := float(hq.get_height()) / orig.get_height()
	var ok := absf(ro - rh) <= 0.01 * maxf(ro, rh)
	var oa := orig.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_LA8, Image.FORMAT_RGBA4444, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH]
	var ha := hq.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_LA8, Image.FORMAT_RGBA4444, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH]
	if oa and not ha and orig.detect_alpha() != Image.ALPHA_NONE:
		ok = false
	if not ok:
		_hq_mutex.lock()
		hq_stats["unfit"] += 1
		_hq_mutex.unlock()
	return ok


## B-039: übrige (nicht getauschte) Bilder des glTF komprimieren; Normalenkarten (materials[].normalTexture) als BC5.
static func _compress_state_images(state: GLTFState, skip: Dictionary) -> void:
	var imgs := state.get_images()
	var js: Dictionary = state.json
	var normal_src := {}
	var texs: Array = js.get("textures", [])
	for m in js.get("materials", []):
		var nt = (m as Dictionary).get("normalTexture")
		if nt is Dictionary:
			var ti := int(nt.get("index", -1))
			if ti >= 0 and ti < texs.size():
				normal_src[int((texs[ti] as Dictionary).get("source", -1))] = true
	for i in imgs.size():
		if skip.has(i) or not (imgs[i] is ImageTexture):
			continue
		var img := (imgs[i] as ImageTexture).get_image()
		if img == null or img.is_compressed():
			continue
		PerfTuning.compress_image(img, normal_src.has(i))
		if img.is_compressed():
			(imgs[i] as ImageTexture).set_image(img)


## B-039: Zwischenspeicher der HD-/4K-Bilder leeren (Kartenwechsel; die Vorlagen halten ihre Texturen selbst)
static func clear_hq_cache() -> void:
	_hq_mutex.lock()
	_hq_cache.clear()
	_hq_mutex.unlock()


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
		if mi.has_meta("klz_proxy") and not Game.cli.has("nav_proxy_flip_off"):
			_orient_proxy_up(mi, cs.shape as ConcavePolygonShape3D)
		# B-036: Kartengrenze „BORDER“ (Wände + Deckel, ARCTIC3 Deckel bei y 22,4 tiefer als die Hügel) nur einseitig –
		# beidseitig war die Deckeloberseite begehbar, der Löser lief in a3 auf ihr kreuz und quer über die Karte
		# nur Deckelteile (Unterkante ≥ 10 m über dem Ursprung, z. B. ARCTIC3 Border_15…29 bei 15,3…22,4); Seitenwände
		# bleiben beidseitig, damit niemand hinausläuft
		var is_border := String(mi.get_path()).contains("/BORDER/") and not Game.cli.has("border_two_sided") \
			and mi.is_inside_tree() and (mi.global_transform * mi.get_aabb()).position.y >= 10.0
		if two_sided and not is_border:
			# Klz-Ebenen wirken beidseitig; versteckte Ersatzkörper sind teils nach unten orientiert (ARCTIC2 T1_strop_19)
			(cs.shape as ConcavePolygonShape3D).backface_collision = true
		body.add_child(cs)
		mi.add_child(body)
		stats.colliders += 1


## B-010b: Recast (Navmesh) wertet nur Dreiecke als begehbar, deren Vorderseite nach oben zeigt. Versteckte
## Ersatzkörper sind im Original teils nach unten orientiert (Klz wirkt beidseitig; ARCTIC2 T1_strop_19, NORWAY
## BB_kolize09/10) → Kollision ok, aber nicht im Netz. Überwiegend nach unten zeigende Ersatzkörper (Fläche „unten“ >
## 2 × „oben“, also verkehrt gewickelt statt geschlossener Kiste) werden umgedreht; physikalisch gleich, da beidseitig
## kollidierend. Nur Ersatzkörper: eine Ausweitung auf alle Klz-Flächen drehte auf NORWAY 82 Formen (auch Decken-
## platten) ohne Gewinn – verworfen. `--nav_proxy_flip_off` = alter Stand.
func _orient_proxy_up(mi: MeshInstance3D, shape: ConcavePolygonShape3D) -> void:
	var f := shape.get_faces()
	var b := mi.global_transform.basis if mi.is_inside_tree() else mi.transform.basis
	var up := 0.0
	var down := 0.0
	for i in range(0, f.size() - 2, 3):
		var n := (b * (f[i + 2] - f[i])).cross(b * (f[i + 1] - f[i]))   # Godot-Vorderseite (im Uhrzeigersinn)
		if absf(n.y) <= 0.5 * n.length():
			continue
		if n.y > 0.0:
			up += n.length()
		else:
			down += n.length()
	if down <= 2.0 * up or down <= 0.0:
		return
	for i in range(0, f.size() - 2, 3):
		var t := f[i + 1]
		f[i + 1] = f[i + 2]
		f[i + 2] = t
	shape.set_faces(f)
	stats["proxy_flipped"] = int(stats.get("proxy_flipped", 0)) + 1
	if Game.cli.has("klz_debug"):
		print("KLZ: Ersatzkörper %s umgedreht (oben %.2f, unten %.2f)" % [mi.name, up, down])


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
		if t == OBJ_MODEL and o.has("model"):
			n.set_meta("orig_model", String(o["model"]))   # ls_anim: Darsteller-Figur bei Skriptanimation (rest_095)
		n.set_meta("klz_obj", String(n.name))
		if String(o.get("parent", "")) == "Backdrop sector":
			n.set_meta("backdrop", true)      # Himmelskulisse (LS3D-Backdrop-Sektor): nie Kollision
			# fix_af1_ferne: Der Backdrop-Sektor ist im Original kamerabezogen (Himmelswürfel, AFRICA1 m_oblohaaf1 = 324 m
			# um den Ursprung, Karte reicht bis ±412 m). Weltfest stand er als vernebelte graue Wand in der Landschaft.
			# Den Himmel stellen ProceduralSky + sky_fx (B-013) dar → Kulisse ausblenden. --backdrop=1 = alter Stand.
			if String(Game.cli.get("backdrop", "0")) != "1":
				n.visible = false
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
