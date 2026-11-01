extends RefCounted
## B-040: Ergebnis von Mission._bake_navigation je Karte zwischenspeichern (Netz bzw. Kacheln + Inselbrücken/
## Kletterstellen mit Metadaten). Ablage `user://navcache/<karte>_<schlüssel>.navc` (zstd, store_var):
## user:// ist immer beschreibbar (auch im Export, wo res:// schreibgeschützt ist), gilt für eigene Karten ohne
## orig_cache-Ordner und liegt außerhalb des Projekts. Leiter-Links werden immer neu gesetzt (verweisen auf
## Leiter-Knoten, kosten < 1 ms), Laufzeit-Links (Zaunschnitt B-017, Türen) bleiben ohnehin dynamisch.
## Schlüssel = SHA-256 über: Quellgeometrie des Bakes (Ecken + Indizes), Kartendateien (Größe/Zeitstempel),
## Navigationsparameter, Kachelplan, Code-Version (config/version + MD5 von mission.gd/nav_cache.gd/soldier.gd)
## und die Optionen (--no_nav_bridges, --nav_slope, --nav_tiles). Abschalten: --nav_cache=0.

const DIR := "user://navcache"
const FORMAT := 1


static func enabled() -> bool:
	return str(Game.cli.get("nav_cache", "1")) != "0"


## Kartenname für den Dateinamen (Originalordner bzw. Missionsskript)
static func map_id(m: Node) -> String:
	var o = m.get("orig")
	if o != null and "mission_dir" in o and str(o.mission_dir) != "":
		return str(o.mission_dir).trim_suffix("/").get_file().validate_filename()
	var sp: String = m.get_script().resource_path if m.get_script() else "mission"
	return sp.get_file().get_basename().validate_filename()


static func _file_stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path.get_file() + ":-"
	return "%s:%d:%d" % [path.get_file(), FileAccess.get_size(path), FileAccess.get_modified_time(path)]


static func _dir_stamp(path: String) -> String:
	var d := DirAccess.open(path)
	if d == null:
		return path.get_file() + ":-"
	var n := 0
	var total := 0
	var newest := 0
	for f in d.get_files():
		var p := path.path_join(f)
		n += 1
		total += FileAccess.get_size(p)
		newest = maxi(newest, FileAccess.get_modified_time(p))
	return "%s:%d:%d:%d" % [path.get_file(), n, total, newest]


static func _code_md5(path: String) -> String:
	var h := FileAccess.get_md5(path)
	return h if h != "" else "-"


static func make_key(m: Node, nm: NavigationMesh, src: NavigationMeshSourceGeometryData3D, plan: String) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var parts: Array[String] = ["fmt%d" % FORMAT, map_id(m)]
	# Kartendaten
	var o = m.get("orig")
	if o != null and "mission_dir" in o and str(o.mission_dir) != "":
		var md := str(o.mission_dir)
		for f in ["scene.glb", "scene.json", "collision.json", "interactive.json", "extra.json"]:
			parts.append(_file_stamp(md.path_join(f)))
		parts.append(_dir_stamp(md.path_join("models")))
	if m.get_script():
		parts.append(_file_stamp(m.get_script().resource_path))
	# Navigationsparameter
	parts.append("nm:%s|%s|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s" % [nm.agent_radius, nm.agent_height, nm.agent_max_climb,
		nm.agent_max_slope, nm.cell_size, nm.cell_height, nm.geometry_parsed_geometry_type, nm.geometry_collision_mask,
		nm.region_min_size, nm.filter_low_hanging_obstacles, nm.filter_ledge_spans, nm.filter_walkable_low_height_spans])
	parts.append("soldier:%s|%s" % [Soldier.STEP_HEIGHT, Soldier.CLIMB_MAX])
	# Code-Version
	parts.append("ver:%s" % ProjectSettings.get_setting("application/config/version", ""))
	for p in ["res://src/mission/mission.gd", "res://src/mission/nav_cache.gd", "res://src/actors/soldier.gd"]:
		parts.append(_code_md5(p))
	# Optionen
	for opt in ["no_nav_bridges", "nav_slope", "nav_tiles"]:
		parts.append("%s=%s" % [opt, str(Game.cli.get(opt, "<none>"))])
	parts.append("plan:" + plan)
	hc.update("\n".join(parts).to_utf8_buffer())
	# Quellgeometrie (deckt eigene Karten und Laufzeit-Aufbau ab)
	hc.update(src.get_vertices().to_byte_array())
	hc.update(src.get_indices().to_byte_array())
	return map_id(m) + "_" + hc.finish().hex_encode().substr(0, 24)


static func path_of(key: String) -> String:
	return DIR.path_join(key + ".navc")


static func read(key: String) -> Dictionary:
	var p := path_of(key)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	if not (d is Dictionary) or d.get("key", "") != key or int(d.get("format", 0)) != FORMAT:
		push_warning("NAV-CACHE: ungültige Datei %s – neu backen" % p)
		return {}
	return d


## Schreibt atomar (.tmp → umbenennen) und entfernt ältere Stände derselben Karte.
static func write(key: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["key"] = key
	data["format"] = FORMAT
	var p := path_of(key)
	var tmp := p + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("NAV-CACHE: kann %s nicht schreiben" % tmp)
		return
	f.store_var(data, false)
	f.close()
	var d := DirAccess.open(DIR)
	if d == null:
		return
	if d.file_exists(p.get_file()):
		d.remove(p.get_file())
	if d.rename(tmp.get_file(), p.get_file()) != OK:
		push_warning("NAV-CACHE: Umbenennen fehlgeschlagen %s" % tmp)
		return
	var prefix := key.substr(0, key.rfind("_") + 1)
	for other in d.get_files():
		if other.begins_with(prefix) and other.ends_with(".navc") and other != p.get_file() \
				and other.trim_prefix(prefix).count("_") == 0:
			d.remove(other)


## Netz einer Region als Daten (Ecken + Polygone)
static func pack_region(reg: NavigationRegion3D, is_main: bool) -> Dictionary:
	var nm := reg.navigation_mesh
	var polys: Array = []
	if nm:
		for i in nm.get_polygon_count():
			polys.append(nm.get_polygon(i))
	return {"name": String(reg.name), "main": is_main, "xf": reg.transform,
		"verts": nm.get_vertices() if nm else PackedVector3Array(), "polys": polys,
		"aabb": nm.filter_baking_aabb if nm else AABB(), "border": nm.border_size if nm else 0.0,
		"edge": nm.edge_max_error if nm else 1.3}


static func unpack_mesh(base: NavigationMesh, r: Dictionary) -> NavigationMesh:
	var nm := base.duplicate() as NavigationMesh
	nm.clear_polygons()
	nm.filter_baking_aabb = r.get("aabb", AABB())
	nm.border_size = float(r.get("border", 0.0))
	nm.edge_max_error = float(r.get("edge", 1.3))
	nm.set_vertices(r["verts"])
	for p in r["polys"]:
		nm.add_polygon(p)
	return nm
