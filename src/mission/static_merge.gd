extends RefCounted
## B-039: Draw Calls senken – kleine, statische, undurchsichtige Level-Meshes (Originalkarten) je Material, Schattenwurf,
## Sichtweite und Rasterzelle zu einem Mesh zusammenfassen. Die Originalknoten bleiben im Baum (Kollision, Namen,
## Skripte, Navmesh unverändert); nur ihre Render-Instanz wird ausgeblendet (RenderingServer.instance_set_visible).
## Ausgenommen (sicher statt maximal): alles, dessen Name oder Vorfahrenname in Missionsskripten, interactive.json,
## meshplayer.json, lightmaps.json oder glows.json vorkommt (FRM_SetOn/Rotate/Lightmaps/Filmtexturen/Türen), Gras
## (Option/DECORATOR_SetOn), Lichtkegel, durchsichtige Materialien (Sortierung), Skin/Blendshapes, gespiegelte
## Transformationen, große Meshes (> MAX_VERTS Ecken je Fläche: dort zählt die Geometrie, nicht der Aufruf).
## Sichtweite: Zellgröße = ¼ der Sichtweite (8–64 m) → Ausblendabstand weicht höchstens ~⅛ der Sichtweite ab.
## Abschalten: --static_merge=0 bzw. --b039=0.

const MAX_VERTS := 3000
const TOKEN_FILES := ["interactive.json", "meshplayer.json", "lightmaps.json", "glows.json"]
static var last := {}


static func apply(m: Node) -> Dictionary:
	var st := {"groups": 0, "merged": 0, "skipped_protected": 0, "candidates": 0}
	last = st
	var orig = m.get("orig") if m else null
	if orig == null or orig.get("root") == null or not PerfTuning.b039("static_merge"):
		return st
	var root: Node3D = orig.root
	var prot := _protected_tokens(String(orig.mission_dir))
	var skip := {}
	for g in orig.grass_nodes:
		skip[g] = true
	for v in orig.volumetric_nodes:
		skip[v] = true
	var groups := {}          # Schlüssel -> {mat, shadow, range, margin, items: [[mesh, surface, xform]]}
	var hide: Array = []
	var stack: Array = [[root, false]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var protected_: bool = e[1]
		if n != root and not protected_ and _is_protected(String(n.name), prot):
			protected_ = true
			if Game.cli.has("merge_debug"):
				print("MERGE geschuetzt: %s (%d Meshes)" % [n.get_path(), n.find_children("*", "MeshInstance3D", true, false).size()])
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, protected_])
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if protected_:
			st.skipped_protected += 1
			continue
		if skip.has(mi) or not _eligible(mi):
			continue
		st.candidates += 1
		var xf := mi.global_transform
		var rng := mi.visibility_range_end
		var cell := clampf(rng * 0.25, 8.0, 64.0) if rng > 0.0 else 64.0
		var c3 := (xf * mi.get_aabb()).get_center()
		var ck := Vector3i(floori(c3.x / cell), floori(c3.y / cell), floori(c3.z / cell))
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var key := "%d|%d|%d|%.1f|%s|%d" % [mat.get_instance_id() if mat else 0, int(mi.cast_shadow),
				mi.mesh.surface_get_format(s) & 0xFF, rng, str(ck), mi.layers]
			if not groups.has(key):
				groups[key] = {"mat": mat, "shadow": mi.cast_shadow, "range": rng, "margin": mi.visibility_range_end_margin,
					"layers": mi.layers, "items": []}
			groups[key]["items"].append([mi.mesh, s, xf])
		hide.append(mi)
	var holder := Node3D.new()
	holder.name = "StaticMerge_B039"
	root.add_child(holder)
	var made := {}            # MeshInstance (Quelle) -> true, sobald alle Flächen zusammengefasst sind
	for key in groups:
		var g: Dictionary = groups[key]
		var stool := SurfaceTool.new()
		for it in g["items"]:
			stool.append_from(it[0], it[1], it[2])
		var am := stool.commit()
		if am == null or am.get_surface_count() == 0:
			continue
		am.surface_set_material(0, g["mat"])
		var out := MeshInstance3D.new()
		out.mesh = am
		out.cast_shadow = g["shadow"]
		out.layers = g["layers"]
		out.visibility_range_end = g["range"]
		out.visibility_range_end_margin = g["margin"]
		out.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		holder.add_child(out)
		st.groups += 1
	for mi in hide:
		RenderingServer.instance_set_visible((mi as MeshInstance3D).get_instance(), false)
		mi.set_meta("b039_merged", true)
		st.merged += 1
	last = st
	print("PERF: Zusammenfassung %d Meshes -> %d Gruppen (%d geschützt)" % [st.merged, st.groups, st.skipped_protected])
	return st


static func _eligible(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.skin != null:
		return false
	if mi.material_override != null or mi.get_blend_shape_count() > 0 or mi.mesh.get_blend_shape_count() > 0:
		return false
	if mi.global_transform.basis.determinant() <= 0.0:
		return false
	if mi.mesh.get_surface_count() == 0:
		return false
	for s in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var arr_len: int = mi.mesh.surface_get_array_len(s)
		if arr_len > MAX_VERTS:
			return false
		var mat := mi.get_active_material(s)
		if mat == null:
			return false
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
				return false
		else:
			return false            # Shadermaterialien (Wasser, Filme …) nicht anfassen
	return true


static func _protected_tokens(dir: String) -> Dictionary:
	var out := {}
	var texts: Array = []
	var sd := dir + "/scripts"
	if DirAccess.dir_exists_absolute(sd):
		for f in DirAccess.get_files_at(sd):
			var fa := FileAccess.open(sd + "/" + f, FileAccess.READ)
			if fa:
				texts.append(fa.get_buffer(fa.get_length()).get_string_from_ascii())
	for f in TOKEN_FILES:
		var fa := FileAccess.open(dir + "/" + f, FileAccess.READ)
		if fa:
			texts.append(fa.get_as_text())
	var fs := FileAccess.open(dir + "/scene.json", FileAccess.READ)
	if fs:
		var d = JSON.parse_string(fs.get_as_text())
		if d is Dictionary:
			for k in (d as Dictionary).get("scripts", {}):
				texts.append(String(k))
			for a in (d as Dictionary).get("actors", []):
				texts.append(String((a as Dictionary).get("name", "")))
	var re := RegEx.new()
	re.compile("[A-Za-z0-9_#%\\-]+")
	for t in texts:
		for mt in re.search_all(String(t)):
			out[mt.get_string().to_upper()] = true
	return out


static func _is_protected(nm: String, prot: Dictionary) -> bool:
	var u := nm.to_upper()
	if u.length() < 3 or u == "SCENE":     # glTF-Wurzel „scene“ und Kurzwörter sind keine Frame-Namen
		return false
	if prot.has(u):
		return true
	# Godot bereinigt Namen (validate_node_name: „.“ „:“ „@“ … → „_“): Originalform mit Punkt nicht rekonstruierbar,
	# daher auch Teile vor/nach „_“-Ersetzungen nicht prüfen – Skripte nennen Frames meist unverändert.
	return false
