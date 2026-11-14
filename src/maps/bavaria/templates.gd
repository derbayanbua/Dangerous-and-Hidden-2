extends RefCounted
## Map-lokale Vorlagen: vorhandener LevelBuilder + Texturen/Modelle aus orig_cache.
## Keine kopierten Originaldaten, keine Änderungen an gemeinsamen Spielsystemen.

var lb: LevelBuilder
const House16Plan := preload("res://src/maps/bavaria/house16_plan.gd")
const PLASTER_TEXTURED := ["haus_16", "haus_18_shed", "haus_18", "haus_18_extension", "haus_14", "haus_16_passage", "haus_16_passage_return"]
var rng := RandomNumberGenerator.new()
var _models := {}
var _model_vertex_bounds := {}
var _root_flare_mesh: CylinderMesh
var missing: Array[String] = []
var reused_models := 0
var reused_textures := 0

func _init(builder: LevelBuilder) -> void:
	lb = builder
	rng.seed = 19450428
	for pair in [
		["plaster", "2e_v8w1", 0.18], ["brick", "2e_v8w2", 0.4],
		["damaged", "2e_v8w1b", 0.3], ["roof", "2e_v8rf", 0.7],
		["slate", "2e_dosk", 0.6], ["wood", "2e_vwoo2", 0.5],
		["darkwood", "2e_vwoo2", 0.4], ["stone", "2e_sw1", 0.6],
		["earth", "2e_wgr2", 0.12], ["grass", "2e_wgr1l", 0.25],
		["meadow", "g_al1_012", 0.18],
		["rubble", "2e_wdmg2", 0.3]]:
		var path := OrigLevel.cache_root() + "/textures/" + String(pair[1]) + ".png"
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null:
			missing.append(path)
			continue
		var mat := lb.mat(String(pair[0])).duplicate() as StandardMaterial3D
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * float(pair[2])
		lb._mats[String(pair[0])] = mat
		reused_textures += 1
	# Optionale kachelbare Fassadentexturen (nicht im Repository). Fehlen sie, bleiben die neutralen
	# Materialien plaster/roof/wood (Originaltexturen bzw. prozedurale Farben); kein Eintrag in `missing`.
	for spec in [["h16_plaster", "plaster.png", 0.30], ["h16_roof", "roof_tiles.png", 0.25], ["h16_wood", "wood_boards.png", 0.55]]:
		var tex_path := "res://assets/maps/bavaria/facade/" + String(spec[1])
		var tex := load(tex_path) as Texture2D if ResourceLoader.exists(tex_path) else null
		if tex == null:
			continue
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = tex
		fm.roughness = 0.92
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		fm.uv1_triplanar = true
		fm.uv1_world_triplanar = true
		fm.uv1_scale = Vector3.ONE * float(spec[2])
		lb._mats[String(spec[0])] = fm
	# Sandsäcke mit echtem Sackmuster (prozedural: Albedo/Normal/Rauheit), ersetzt das einfarbige „sandbag“ dieser Karte
	# – wirkt auf Grabenbrustwehr, Feld-Sandsacknester und lb.sandbags/Kriegsdeko (nur diese Karteninstanz von lb).
	const SB_DIR := "res://assets/maps/bavaria/facade/"
	var sb_alb := load(SB_DIR + "sandbag_albedo.png") as Texture2D if ResourceLoader.exists(SB_DIR + "sandbag_albedo.png") \
			and ResourceLoader.exists(SB_DIR + "sandbag_normal.png") and ResourceLoader.exists(SB_DIR + "sandbag_roughness.png") else null
	if sb_alb:
		var sb := StandardMaterial3D.new()
		sb.albedo_texture = sb_alb
		sb.normal_enabled = true
		sb.normal_texture = load("res://assets/maps/bavaria/facade/sandbag_normal.png") as Texture2D
		sb.normal_scale = 1.4
		sb.roughness_texture = load("res://assets/maps/bavaria/facade/sandbag_roughness.png") as Texture2D
		sb.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		sb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		sb.uv1_triplanar = true
		sb.uv1_world_triplanar = true
		sb.uv1_scale = Vector3.ONE
		lb._mats["sandbag"] = sb

func prop(model: String, pos: Vector3, yaw := 0.0, scale_value := 1.0, collide := false) -> Node3D:
	var key := model.to_lower()
	if not _models.has(key):
		var path := OrigLevel.cache_root() + "/czech3/models/" + key + ".glb"
		_models[key] = OrigLevel.parse_glb(path)
		if _models[key] == null:
			missing.append(path)
		elif key in ["l_tree", "l_tree2", "l_tree4", "e_treb1"]:
			_upgrade_tree_textures(_models[key])
	var template: Node3D = _models[key]
	if template == null:
		return null
	# Eigenen Platzierungsknoten verwenden: Originalrotation/-skalierung des glTF-Wurzelknotens erhalten.
	var n := Node3D.new()
	n.name = "Original_" + key
	var content := template.duplicate() as Node3D
	n.add_child(content)
	lb.static_root.add_child(n)
	var bounds := mesh_bounds(content, Transform3D.IDENTITY)
	var ground_y := bounds.position.y
	if key in ["l_tree", "l_tree2", "l_tree4", "e_treb1"]:
		if not _model_vertex_bounds.has(key):
			_model_vertex_bounds[key] = vertex_bounds(content, Transform3D.IDENTITY)
		ground_y = (_model_vertex_bounds[key] as AABB).position.y
	# Die Modelle behalten ihre natürlichen Proportionen; lediglich Boden/Modellursprung normalisieren.
	var offset := Vector3(bounds.get_center().x, ground_y, bounds.get_center().z)
	content.position -= offset
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale_value
	if collide:
		_mesh_colliders(n)
	if key in ["l_tree", "l_tree2", "l_tree4", "e_treb1"]:
		n.add_to_group("bavaria_all_tree_roots")
		n.set_meta("species",key)
	reused_models += 1
	return n

## Baumtexturen (Rinde/Laub) map-lokal in der höchsten vorhandenen KI-Fassung (orig_cache/textures_4k, sonst _hd;
## _reject.txt beachtet), unabhängig von der allgemeinen Texturstufe. Mipmaps + anisotrope Filterung, Laub mit
## Alpha-Schere und Alpha-to-Coverage (saubere Kanten). Ohne HD-Dateien bleibt das Original.
static var tree_tex_stats := {}       ## Dateiname → [alte Größe, neue Größe, Stufe]
static var _tree_tex := {}
func _upgrade_tree_textures(root: Node3D) -> void:
	for mi in root.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.has_meta("bavaria_hd"):
				continue
			mat.set_meta("bavaria_hd",true)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var tex := mat.albedo_texture
			# Materialname = Original-Bitmap (z. B. „2E_LEAF1.BMP“) → Cache-Datei 2e_leaf1.png bzw. 2e_leaf1__ck.png (Farbschlüssel)
			var base := String(mat.resource_name).to_lower().get_basename()
			var file := ""
			for cand in [base + "__ck.png", base + ".png"]:
				if base != "" and FileAccess.file_exists("%s/textures/%s" % [OrigLevel.cache_root(), cand]):
					file = cand
					break
			if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or file.ends_with("__ck.png"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.alpha_antialiasing_edge = 0.3
			mat.set_meta("bavaria_tree_file", file)
			mat.set_meta("bavaria_tree_orig", tex)
			var hq := _tree_hq_texture(file, tex)
			if hq:
				mat.albedo_texture = hq

## Ferne Randbäume (dichter Hintergrundwald, hintere Reihen): Kopie des Baummaterials mit der HD-Stufe (textures_hd,
## halbe Kantenlänge der 4K-Fassung) statt 4K. Ohne HD-Datei bleibt das 4K-Material (null = unverändert).
static var _tree_far_mat := {}
func tree_far_material(mat: Material) -> Material:
	if mat == null or not mat.has_meta("bavaria_tree_file"):
		return null
	if _tree_far_mat.has(mat):
		return _tree_far_mat[mat]
	var file := String(mat.get_meta("bavaria_tree_file"))
	var result: Material = null
	var p := "%s/textures_hd/%s" % [OrigLevel.cache_root(), file]
	if file != "" and FileAccess.file_exists(p) and not OrigLevel._hq_rejected("_hd", file):
		var img := Image.load_from_file(p)
		var orig: Texture2D = mat.get_meta("bavaria_tree_orig", null)
		var orig_img := orig.get_image() if orig else null
		if img and (orig_img == null or OrigLevel._hq_fits(orig_img, img)):
			img.generate_mipmaps()
			if PerfTuning.b039("tex_compress"):
				PerfTuning.compress_image(img)
			var copy := mat.duplicate() as BaseMaterial3D
			copy.albedo_texture = ImageTexture.create_from_image(img)
			tree_tex_stats[file + " (fern)"] = [Vector2.ZERO, Vector2(img.get_width(), img.get_height()), "_hd"]
			result = copy
	_tree_far_mat[mat] = result
	return result

## Mesh mit HD-Materialien (nur Oberflächenmaterialien getauscht, Geometrie geteilt über Kopie der Oberflächen).
static var _tree_far_mesh := {}
func tree_far_mesh(mesh: Mesh) -> Mesh:
	if mesh == null:
		return mesh
	if _tree_far_mesh.has(mesh):
		return _tree_far_mesh[mesh]
	var out: Mesh = mesh
	var any := false
	var mats: Array = []
	for s in mesh.get_surface_count():
		var fm := tree_far_material(mesh.surface_get_material(s))
		mats.append(fm)
		any = any or fm != null
	if any:
		out = mesh.duplicate()
		for s in mats.size():
			if mats[s] != null:
				out.surface_set_material(s, mats[s])
	_tree_far_mesh[mesh] = out
	return out

func _tree_hq_texture(file: String, orig: Texture2D) -> Texture2D:
	if file == "" or orig == null:
		return null
	if _tree_tex.has(file):
		return _tree_tex[file]
	var result: Texture2D = null
	var orig_img := orig.get_image()
	for s in ["_4k", "_hd"]:
		var p := "%s/textures%s/%s" % [OrigLevel.cache_root(), s, file]
		if not FileAccess.file_exists(p) or OrigLevel._hq_rejected(s, file):
			continue
		var img := Image.load_from_file(p)
		if img == null or (orig_img and not OrigLevel._hq_fits(orig_img, img)):
			continue
		img.generate_mipmaps()
		if PerfTuning.b039("tex_compress"):
			PerfTuning.compress_image(img)
		result = ImageTexture.create_from_image(img)
		tree_tex_stats[file] = [orig.get_size(), Vector2(img.get_width(), img.get_height()), s]
		break
	_tree_tex[file] = result
	return result

func ground_vegetation(mission: Mission) -> void:
	# Vor jeder Instanzierung ausführen: auch Randbäume, Weggrün und Einzelbaum erfassen.
	var roots: Array = mission.get_tree().get_nodes_in_group("bavaria_all_tree_roots")
	roots.append_array(mission.get_tree().get_nodes_in_group("bavaria_ground_foliage"))
	for root in roots:
		if not root.visible or root.get_meta("ground_contact_checked",false):
			continue
		var stem: MeshInstance3D
		for mesh in root.find_children("*","MeshInstance3D",true,false):
			if String(mesh.name) in ["tree","hi1kmen"]:
				stem = mesh
				break
		var bounds := vertex_bounds(stem,stem.get_parent().global_transform) if stem else vertex_bounds(root,root.get_parent().global_transform)
		if stem and root.get_meta("species","")=="l_tree2":
			# Dieses Modell hat lange, dünne Wurzelausläufer UNTER dem eigentlichen Stammfuß.
			# Die kompakte unterste Stammquerschnitts-Ringgruppe beginnt etwa 2,5m darüber.
			if not stem.mesh.has_meta("main_trunk_base"):
				var ring: Array[Vector3] = []
				var unit: float = root.global_basis.y.length()
				for surface in stem.mesh.get_surface_count():
					for vertex in stem.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						var relative_y: float = ((stem.global_transform*vertex).y-bounds.position.y)/unit
						if relative_y>=2.5 and relative_y<2.75:
							ring.append(vertex)
				stem.mesh.set_meta("main_trunk_base",ring)
			var base_points: Array = stem.mesh.get_meta("main_trunk_base")
			var base_bounds := AABB(stem.global_transform*base_points[0],Vector3.ZERO)
			for point in base_points:
				base_bounds = base_bounds.expand(stem.global_transform*point)
			bounds.position = base_bounds.position
			bounds.size.x = base_bounds.size.x
			bounds.size.z = base_bounds.size.z
		var foot := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		# Die Außenkulisse hat ihren eigenen sichtbaren Boden bei -0,30m.
		var floor_y := 0.0 if mission.inside_map(foot) else -0.3
		var shift := floor_y-0.045-foot.y
		root.global_position.y += shift
		root.set_meta("ground_contact_checked",true)
		root.set_meta("ground_contact_before",foot.y-floor_y)
		root.set_meta("ground_contact_y",floor_y-0.045)
		root.set_meta("ground_floor_y",floor_y)
		root.set_meta("ground_shift",shift)
		if root.has_meta("foliage_index"):
			mission.scene_details.foliage[int(root.get_meta("foliage_index"))].center.y += shift
		if stem:
			# Breiter sichtbarer Wurzelansatz statt eines einzelnen tiefsten Modellvertices.
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for surface in stem.mesh.get_surface_count():
				for vertex in stem.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var v: Vector3 = stem.global_transform*vertex
					if v.y>=floor_y-0.10 and v.y<floor_y+0.12:
						low = low.min(v)
						high = high.max(v)
			var radius := clampf(maxf(high.x-low.x,high.z-low.z)*0.45,0.035,0.65)
			var height := clampf(bounds.size.y*0.04,0.04,0.20)
			var flare := MeshInstance3D.new()
			flare.name = "BodenschluessigerWurzelansatz"
			if _root_flare_mesh == null:
				_root_flare_mesh = CylinderMesh.new()
				_root_flare_mesh.resource_name = "BavariaRootFlare"
				_root_flare_mesh.top_radius = 0.65
				_root_flare_mesh.bottom_radius = 1.10
				_root_flare_mesh.height = 1.0
				_root_flare_mesh.radial_segments = 9
			flare.mesh = _root_flare_mesh
			flare.material_override = stem.get_active_material(0)
			root.add_child(flare)
			flare.global_transform = Transform3D(Basis.from_scale(Vector3(radius,height,radius)),Vector3((low.x+high.x)*0.5,floor_y-0.045+height*0.5,(low.z+high.z)*0.5))
			root.set_meta("ground_contact_point",Vector3((low.x+high.x)*0.5,floor_y,(low.z+high.z)*0.5))
			if root.has_meta("trunk_collision"):
				var shape := mission.get_node(NodePath(root.get_meta("trunk_collision"))) as CollisionShape3D
				shape.global_position = Vector3((low.x+high.x)*0.5,floor_y+shape.shape.height*0.5,(low.z+high.z)*0.5)
			root.set_meta("root_flare",true)

func mesh_bounds(node: Node3D, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf * node.transform
	var bounds := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh:
		bounds = xf * node.get_aabb()
		found = true
	for c in node.get_children():
		if c is Node3D:
			var b := mesh_bounds(c, xf)
			if b.size.length_squared() > 0.0:
				bounds = bounds.merge(b) if found else b
				found = true
	return bounds

func vertex_bounds(node: Node3D, parent_xf: Transform3D) -> AABB:
	# Import-AABBs can include empty space (l_tree4: almost three metres).
	# Transform actual vertices, including the complete glTF parent hierarchy.
	var xf := parent_xf * node.transform
	var bounds := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = xf * vertex
				bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
				found = true
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := vertex_bounds(child, xf)
			if child_bounds.size.length_squared() > 0.0:
				bounds = bounds.merge(child_bounds) if found else child_bounds
				found = true
	return bounds

func _mesh_colliders(n: Node3D) -> void:
	if n is MeshInstance3D and n.mesh:
		n.create_trimesh_collision()
	for c in n.get_children():
		if c is Node3D and not c is StaticBody3D:
			_mesh_colliders(c)

func house(id: String, pos: Vector3, w: float, d: float, h: float, yaw: float, kind: String, ruined: bool) -> Node3D:
	if id=="woodland_shed":
		return _woodland_shed(pos,w,d,h,yaw)
	if ruined:
		return _ruin(id, pos, w, d, h, yaw)
	var wall := "wood" if kind in ["barn", "shed"] else "plaster"
	var roof := "slate" if kind == "shed" else "roof"
	# Haus 16 und die Nachbarhäuser am Dorfrand: neue Putz-/Pfannen-/Bretter-Texturen (optional, sonst Standardmaterial).
	# Häuserzeile: auch die Reihenhäuser der Häuserzeile weiß verputzt mit braunem Pfannendach.
	if (id in PLASTER_TEXTURED or id.begins_with("reihe_")) and lb._mats.has("h16_plaster"):
		wall = "h16_wood" if kind in ["barn", "shed"] else "h16_plaster"
		roof = "h16_roof"
	var doors: Array = [["s", 0.0], ["n", 0.0]] if kind == "house" else []
	if id=="haus_16":
		doors = [["s",0.0],["n",House16Plan.BACK_DOOR_X]] # Plan: Bad/WC liegt hinten in der Mitte.
	elif id=="haus_2":
		doors = [["s",0.0],["e",0.0]] # Straßenfront liegt direkt an der blauen Grenze.
	elif id=="haus_18":
		doors = [["s",-w*0.24],["n",0.0]] # Anbau nicht mit der Haustür durchschneiden.
	var gaps: Array = [["s", 0.0, minf(4.0,maxf(0.4,w-0.6))], ["n", 0.0, minf(4.0,maxf(0.4,w-0.6))]] if kind != "house" else []
	var n := lb.building(pos, w, d, h, wall, roof, doors, true, yaw, gaps, false, 2 if kind == "house" else 0, 1.3 if kind == "house" else 1.6)
	n.set_meta("footprint_size", Vector2(w,d))
	var entries: Array = []
	for door in doors:
		var normal := Vector3(1,0,0) if door[0]=="e" else Vector3(0,0,1 if door[0]=="s" else -1)
		var point := Vector3(w*0.5,0,0) if door[0]=="e" else Vector3(float(door[1]),0,normal.z*d*0.5)
		entries.append({"point":point,"normal":normal,"approach":0.8 if id=="haus_2" else 2.0})
	n.set_meta("entry_points",entries)
	var terrace := id.begins_with("reihe_")
	# Der vorhandene Baukasten bleibt die Vorlage; bei diesen breiten Grundrissen flachere Satteldächer.
	# Haus 16: Dachneigung nach Plan-Schnitt (2,22 m Firsthöhe über 4,82 m), übrige Häuser unverändert.
	var roof_slope := House16Plan.ROOF_SLOPE if id == "haus_16" else 0.37
	n.set_meta("roof_slope", roof_slope)
	for roof_index in [n.get_child_count() - 4, n.get_child_count() - 3]:
		var plate: Node3D = n.get_child(roof_index)
		var sign_z := signf(plate.position.z)
		plate.rotation.x = roof_slope * sign_z
		plate.scale.z = cos(0.55) / cos(roof_slope)
		if terrace:
			plate.scale.x = w / (w + 0.8)   # Gemeinsame Hausgrenzen: keine überlappenden Dachüberstände.
		plate.position.y = h + tan(roof_slope) * (d * 0.5 + 0.4) * 0.5 - 0.1
	for gable_index in [n.get_child_count() - 2, n.get_child_count() - 1]:
		var gable := n.get_child(gable_index) as MeshInstance3D
		var prism := gable.mesh as PrismMesh
		prism.size.y = tan(roof_slope) * d * 0.5
		gable.position.y = h + prism.size.y * 0.5
		# 11/2026: Giebeldreieck mit Kollision (Kamera-Federarm/Schüsse gingen sonst oberhalb der Traufe ins Dach).
		var gb := StaticBody3D.new()
		gb.name = "GiebelKollision"
		var gcs := CollisionShape3D.new()
		var gshape := ConvexPolygonShape3D.new()
		var hy := prism.size.y * 0.5
		var hz := prism.size.z * 0.5
		var hx := prism.size.x * 0.5
		gshape.points = PackedVector3Array([Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(0, hy, -hz),
			Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(0, hy, hz)])
		gcs.shape = gshape
		gb.add_child(gcs)
		n.add_child(gb)              # nicht unter das Mesh: merge_building_visuals gibt die Quellmeshes frei
		gb.transform = gable.transform
	n.name = id
	n.add_to_group("bavaria_buildings")
	# Lesbare Fachwerk-/Putzfassaden, Fensterläden und niedriger Sockel.
	for side in [-1.0, 1.0]:
		# Sockel nicht durch die beiden Eingänge ziehen.
		var offset := -w*0.24 if id=="haus_18" and side>0 else 0.0
		if id=="haus_16" and side<0:
			offset = House16Plan.BACK_DOOR_X
		for sign_x in [-1.0, 1.0]:
			var gap_half := 0.90 if kind == "house" else minf(2.2,w*0.35)
			var lo := -w*0.5 if sign_x<0 else offset+gap_half
			var hi := offset-gap_half if sign_x<0 else w*0.5
			lb.box(Vector3((lo+hi)*0.5, 0, side * d * 0.5), Vector3(hi-lo, 0.38, 0.38), "stone", 0, true, n)   # 4 cm vor der Wand: kein Z-Fighting
		var count := maxi(int(w / 4.0), 2 if kind == "house" else 0)
		for i in count:
			var x := -w * 0.5 + (i + 0.5) * w / count
			if absf(x) < 1.3:
				continue
			for sx in [-1.0, 1.0]:
				if kind=="house" and absf(x+sx*0.77)<1.1:
					continue
				lb.box(Vector3(x + sx * 0.77, 0.95, side * (d * 0.5 + 0.18)), Vector3(0.42, 1.1, 0.12), "darkwood", 0, false, n)
			lb.box(Vector3(x, 0.92, side * (d * 0.5 + 0.15)), Vector3(1.35, 0.12, 0.3), "stone", 0, false, n)
			# Rahmen um die echten Erdgeschossöffnungen: keine Scheibe/Blende im Schussfeld.
			for frame_side in [-1.0,1.0]:
				lb.box(Vector3(x + frame_side * 0.55, 1.0, side * (d * 0.5 + 0.16)), Vector3(0.1,0.9,0.12), "darkwood", 0, false, n)
			lb.box(Vector3(x, 1.9, side * (d * 0.5 + 0.16)), Vector3(1.2,0.1,0.12), "darkwood", 0, false, n)
		if kind == "house":
			lb.box(Vector3(0, minf(h * 0.68, OG_SILL - 0.45), side * (d * 0.5 + 0.12)), Vector3(w + 0.02, 0.15, 0.1), "darkwood", 0, false, n)   # Gesims vor der Wandfläche (vorher koplanar → Z-Fighting)
	if kind == "house":
		lb.box(Vector3(w * 0.31, h, d * 0.18), Vector3(0.7, 1.8, 0.8), "brick", 0, true, n)
		# Tisch/Kisten stammen aus den vorhandenen Modellen; Fluchtwege bleiben frei.
		var b := Basis(Vector3.UP, yaw)
		if d>=6.4 and w>=8.3:
			prop("e_ktable", pos + b * Vector3(-w * 0.32, 0.12, 0), yaw, 0.7, true)
			prop("e_chair", pos + b * Vector3(-w * 0.32, 0.12, 0.9), yaw)
	else:
		# Kiste (1,8-fach ≈ 1,5 m) vollständig im Innenraum: Abstand zur Wandinnenseite statt fester Bruchteile
		# (früher ragte sie in schmalen Schuppen bis 0,95 m durch die Außenwand; Clipping-Prüftest).
		var crate_half := 0.80
		if d > 2.0 * (crate_half + 0.2) and w > 2.0 * (crate_half + 0.2):
			var cx := -minf(w * 0.27, w * 0.5 - 0.18 - crate_half)
			var cz := minf(d * 0.25, d * 0.5 - 0.18 - crate_half)
			prop("e_pbx1", pos + Basis(Vector3.UP, yaw) * Vector3(cx, 0.1, cz), yaw, 1.8, true)
	_facade_details(n, w, d, h, kind, terrace)
	_interior(n, w, d, h, kind)
	if id == "haus_16":
		House16Plan.build(lb, self, n, w, d)
	if String(n.name) in OG_OPEN_HOUSES:
		open_og_windows(n, w, d, h)
	if n.get_meta("interior_partitioned", false):
		# Vier überprüfbare Fensterplätze in den äußeren Zimmern (vorne/hinten, links/rechts).
		var shooting_windows: Array[Vector3] = []
		var count := maxi(int(w / 4.0), 2)
		for side in [-1.0,1.0]:
			for room_side in [-1.0,1.0]:
				var best_x := 0.0
				var best_distance := INF
				for i in count:
					var x := -w * 0.5 + (i + 0.5) * w / count
					if absf(x) < 1.3:
						continue
					if absf(x - room_side * w * 0.25) < best_distance:
						best_x = x
						best_distance = absf(x - room_side * w * 0.25)
				shooting_windows.append(Vector3(best_x,1.5,side * d * 0.5))
		n.set_meta("shooting_windows", shooting_windows)
	merge_building_visuals(n)
	return n

func _facade_details(n: Node3D, w: float, d: float, h: float, kind: String, terrace: bool) -> void:
	# Geschlossene Obergeschossfenster sind Fassadendetails; Erdgeschossöffnungen bleiben spielbar.
	for side in [-1.0, 1.0]:
		if kind == "house" and h > 5.0:
			# Haus 16: drei OG-Zimmer je Fassade laut Plan → drei Fenster.
			var count := 3 if String(n.name) == "haus_16" else maxi(int(w / 5.2), 2)
			for i in count:
				var x := -w * 0.5 + (i + 0.5) * w / count
				og_window(n, Vector3(x, OG_SILL, side * (d * 0.5 + 0.15)), side, false, 0.0, String(n.name) in OG_OPEN_HOUSES)
		# Traufbalken lassen beide Dachhälften sauber an der Fassade anschließen.
		lb.box(Vector3(0, h - 0.08, side * (d * 0.5 + 0.14)), Vector3(w if terrace else w + 0.6, 0.18, 0.22), "darkwood", 0, false, n)
	if kind in ["barn", "shed"]:
		for x in [-w * 0.5 + 0.2, 0.0, w * 0.5 - 0.2]:
			for side in [-1.0, 1.0]:
				if absf(x) > 2.2:
					lb.box(Vector3(x, 0, side * (d * 0.5 + 0.12)), Vector3(0.22, h, 0.22), "darkwood", 0, false, n)
	# Durchgehende Firstabdeckung, statt sichtbarer Spalte zwischen den Dachplatten.
	var slope: float = n.get_meta("roof_slope", 0.37)
	var ridge_y := h + tan(slope) * (d * 0.5 + 0.4) - 0.12
	lb.box(Vector3(0, ridge_y, 0), Vector3(w if terrace else w + 0.85, 0.18, 0.28), "roof", 0, false, n)

## Obergeschossfenster (11/2026, „OG-Fenster sichtbar“): Brüstung 4,0 m, Glas 1,1 × 1,4 m dunkel mit
## warmem Schein, Blockrahmen, Sprossenkreuz, Fensterbank, offene Läden. Alle Teile stehen ≥ 4 cm vor der Wandfläche
## (keine koplanaren Flächen → kein Z-Fighting) und sind kräftig genug für die Mesh-LOD-Stufen der Ferne.
## face = Lage der äußeren Wandfläche (lokal), outward = ±1 entlang z (Traufseite) bzw. x (Giebel, gable = true).
const OG_SILL := 4.0
var _og_glass: StandardMaterial3D

## Begehbare Obergeschosse (Treppenhäuser): Traufseiten-Fenster sind echte Wandöffnungen mit Klarglas.
const OG_OPEN_HOUSES := ["haus_16", "haus_18_shed"]
const OG_GLASS_W := 1.1
const OG_GLASS_H := 1.4
var _og_clear: StandardMaterial3D

func og_window(n: Node3D, face: Vector3, outward: float, gable: bool, push := 0.0, open := false) -> void:
	if open:
		_og_open_window(n, face, outward)
		return
	if _og_glass == null:
		_og_glass = StandardMaterial3D.new()
		_og_glass.albedo_color = Color(0.07, 0.10, 0.11)
		_og_glass.roughness = 0.15
		_og_glass.metallic_specular = 0.9
		# Ferne geschlossene Fenster behalten ihren warmen Schein, wenn Raumlichter ausblenden.
		_og_glass.emission_enabled = true
		_og_glass.emission = Color(1.0, 0.52, 0.18)
		_og_glass.emission_energy_multiplier = 0.30
		_og_glass.set_meta("bavaria_og_glass", true)
		lb._mats["og_window_glass"] = _og_glass
	var holder := Node3D.new()
	holder.name = "OG_Fenster"
	n.add_child(holder)
	holder.position = face + (Vector3(outward, 0, 0) if gable else Vector3(0, 0, outward)) * push
	holder.rotation.y = PI * 0.5 if gable else 0.0
	# Lokales System: Fassade in x, außen = +z·s (bei Giebeln über die Drehung)
	var s := outward if not gable else outward
	var y := 0.0
	lb.box(Vector3(0, y, s * 0.05), Vector3(1.1, 1.4, 0.06), "og_window_glass", 0, false, holder)
	for sx in [-1.0, 1.0]:
		lb.box(Vector3(sx * 0.62, y - 0.08, s * 0.08), Vector3(0.14, 1.56, 0.12), "darkwood", 0, false, holder)
		# offene Klappläden, leicht vor der Wand
		lb.box(Vector3(sx * 1.0, y, s * 0.07), Vector3(0.5, 1.4, 0.06), "wood", 0, false, holder)
	for dy in [0.0, 0.68, 1.4]:
		lb.box(Vector3(0, y + dy - 0.045, s * 0.10), Vector3(1.24, 0.09, 0.08), "darkwood", 0, false, holder)
	lb.box(Vector3(0, y, s * 0.10), Vector3(0.07, 1.4, 0.08), "darkwood", 0, false, holder)
	lb.box(Vector3(0, y - 0.14, s * 0.10), Vector3(1.4, 0.07, 0.2), "stone", 0, false, holder)   # Fensterbank
	var list: Array = n.get_meta("og_windows", [])
	list.append(face)
	n.set_meta("og_windows", list)

## Echtes OG-Fenster (Traufseite, Wandfläche bei z = face.z): Klarglas mittig in der Laibung, Rahmen/Sprossen außen,
## Fensterbank innen und außen. Kollision: nur Bewegungssperre (Ebene 5) in der Öffnung – man fällt nicht hinaus,
## Blicke und Schüsse gehen hindurch (wie die EG-Fensterplätze). Die Wand selbst schneidet open_og_windows auf.
func _og_open_window(n: Node3D, face: Vector3, s: float) -> void:
	if _og_clear == null:
		_og_clear = StandardMaterial3D.new()
		_og_clear.albedo_color = Color(0.62, 0.72, 0.76, 0.16)
		_og_clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_og_clear.roughness = 0.04
		_og_clear.metallic_specular = 0.9
		_og_clear.cull_mode = BaseMaterial3D.CULL_DISABLED
		_og_clear.set_meta("bavaria_og_clear_glass", true)
		lb._mats["og_window_clear"] = _og_clear
	var holder := Node3D.new()
	holder.name = "OG_Fenster_offen"
	n.add_child(holder)
	holder.position = face
	# Glas in der Wandmitte (Wand 0,30 m: Außenfläche bei face, Mitte 0,15 m innen)
	lb.box(Vector3(0, 0, -s * 0.15), Vector3(OG_GLASS_W, OG_GLASS_H, 0.012), "og_window_clear", 0, false, holder)
	for sx in [-1.0, 1.0]:
		lb.box(Vector3(sx * 0.62, -0.08, s * 0.08), Vector3(0.14, 1.56, 0.12), "darkwood", 0, false, holder)
		lb.box(Vector3(sx * 1.0, 0, s * 0.07), Vector3(0.5, 1.4, 0.06), "wood", 0, false, holder)
		# Laibung innen (dunkles Holz statt offener Wandschnittkanten)
		lb.box(Vector3(sx * (OG_GLASS_W * 0.5 + 0.02), 0, -s * 0.15), Vector3(0.04, OG_GLASS_H, 0.30), "darkwood", 0, false, holder)
	for dy in [0.0, 0.68, 1.4]:
		lb.box(Vector3(0, dy - 0.045, -s * 0.15), Vector3(OG_GLASS_W, 0.05, 0.04), "darkwood", 0, false, holder)
	lb.box(Vector3(0, 0, -s * 0.15), Vector3(0.04, OG_GLASS_H, 0.04), "darkwood", 0, false, holder)
	lb.box(Vector3(0, -0.14, s * 0.10), Vector3(1.4, 0.07, 0.2), "stone", 0, false, holder)       # Fensterbank außen
	lb.box(Vector3(0, -0.05, -s * 0.36), Vector3(1.3, 0.05, 0.16), "darkwood", 0, false, holder)  # Fensterbrett innen
	var stop := StaticBody3D.new()
	stop.name = "OG_Fenster_Sperre"
	stop.collision_layer = LevelBuilder.FENCE_LAYER
	stop.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(OG_GLASS_W, OG_GLASS_H, 0.10)
	cs.shape = shape
	cs.position = Vector3(0, OG_GLASS_H * 0.5, -s * 0.15)
	stop.add_child(cs)
	holder.add_child(stop)
	stop.add_to_group("bavaria_og_window_stops")
	var list: Array = n.get_meta("og_windows", [])
	list.append(face)
	n.set_meta("og_windows", list)
	var open_list: Array = n.get_meta("og_open_windows", [])
	open_list.append(face)
	n.set_meta("og_open_windows", open_list)

## Schneidet die Außenwand (Traufseiten) an jedem echten OG-Fenster auf und legt Fensterplätze im OG an
## (Meta „og_shooting_windows“: x, OG-Boden, Wandebene; wie „shooting_windows“ im EG).
func open_og_windows(n: Node3D, w: float, d: float, h: float) -> void:
	var places: Array[Vector3] = []
	var top := minf(OG_SILL + OG_GLASS_H, h - 0.12)
	for face in n.get_meta("og_open_windows", []):
		var side := signf(face.z)
		for wall in n.get_children():
			if not (wall is Node3D) or wall is StaticBody3D or wall is MeshInstance3D or absf(wall.position.z - side * d * 0.5) > 0.01 \
					or absf(wall.rotation.y) > 0.01 or wall.get_child_count() == 0:
				continue
			_cut_wall(wall, face.x, OG_SILL, top, OG_GLASS_W * 0.5)
		places.append(Vector3(face.x, House16Plan.OG_FLOOR, side * d * 0.5))
	n.set_meta("og_shooting_windows", places)

func _cut_wall(wall: Node3D, cx: float, y0: float, y1: float, half: float) -> void:
	for piece in wall.get_children():
		var mi: MeshInstance3D = null
		for c in piece.get_children():
			if c is MeshInstance3D:
				mi = c
		if mi == null or not (mi.mesh is BoxMesh):
			continue
		var sz: Vector3 = (mi.mesh as BoxMesh).size
		var x0: float = piece.position.x - sz.x * 0.5
		var x1: float = piece.position.x + sz.x * 0.5
		var yb: float = piece.position.y
		var yt: float = yb + sz.y
		if x1 <= cx - half + 0.001 or x0 >= cx + half - 0.001 or yt <= y0 + 0.001 or yb >= y1 - 0.001:
			continue
		var material := mi.material_override
		var parts: Array = []
		if cx - half > x0 + 0.01:
			parts.append([x0, cx - half, yb, yt])
		if cx + half < x1 - 0.01:
			parts.append([cx + half, x1, yb, yt])
		var mx0 := maxf(x0, cx - half)
		var mx1 := minf(x1, cx + half)
		if y0 > yb + 0.01:
			parts.append([mx0, mx1, yb, y0])
		if y1 < yt - 0.01:
			parts.append([mx0, mx1, y1, yt])
		for p in parts:
			var body := lb.box(Vector3((p[0] + p[1]) * 0.5, p[2], piece.position.z), Vector3(p[1] - p[0], p[3] - p[2], sz.z), "plaster", 0, true, wall)
			for c in body.get_children():
				if c is MeshInstance3D:
					c.material_override = material
		piece.free()

## Nach dem Aufbau aller Gebäude: freie Giebelseiten intakter Wohnhäuser bekommen ein OG-Fenster (Anbauten,
## Nachbarhäuser und Reihenhaus-Trennwände ausgenommen); danach Gebäudehülle neu zusammenfassen.
func finish_og_windows(mission) -> void:
	for n in mission.get_tree().get_nodes_in_group("bavaria_buildings"):
		if n.is_in_group("bavaria_ruins") or String(n.get_meta("building_kind", "")) != "house" or not n.has_meta("footprint_size"):
			continue
		var size: Vector2 = n.get_meta("footprint_size")
		var added := 0
		for sx in [-1.0, 1.0]:
			var free := true
			for zz in [-0.3, 0.0, 0.3]:
				var probe: Vector3 = n.to_global(Vector3(sx * (size.x * 0.5 + 0.8), 0, zz * size.y))
				if not mission.inside_map(probe):
					free = false
				var pd = mission.get("scene_details")
				if pd and pd.tower_base != Vector3.ZERO and Vector2(probe.x - pd.tower_base.x, probe.z - pd.tower_base.z).length() < 3.0:
					free = false   # Antennenturm mit Wandankern auf dieser Giebelseite
				for f in mission.building_footprints:
					if Geometry2D.is_point_in_polygon(Vector2(probe.x, probe.z), f):
						free = false
			if free and size.y > 3.0:
				og_window(n, Vector3(sx * (size.x * 0.5 + 0.15), OG_SILL, 0.0), sx, true)
				added += 1
		if added > 0:
			merge_building_visuals(n)

func _interior(n: Node3D, w: float, d: float, h: float, kind: String) -> void:
	n.set_meta("building_kind", kind)
	if kind == "house" and w > 5.0 and d > 3.5 and h > 5.0:
		# Wohnräume im kalibrierten Grundriss; 2 m Flur, Türen bleiben in Soldatenmaßen.
		n.set_meta("interior_partitioned", true)
		var corridor := minf(1.0,w*0.14)
		n.set_meta("corridor_half_width", corridor)
		var stairs := String(n.name) in ["haus_16","haus_18_shed"]
		if String(n.name) == "haus_16":
			# Raumaufteilung nach Plan (house16_plan._eg_walls) statt Standardflur/-zimmer.
			_stair_floor(n,w,d)
			n.set_meta("corridor_half_width", 0.5)
			return
		if stairs:
			_stair_floor(n,w,d)
		else:
			var ceiling := lb.box(Vector3(0, 3.0, 0), Vector3(w - 0.4, 0.18, d - 0.4), "plaster", 0, true, n)
			# Nicht zugängliche Obergeschosse bleiben außerhalb der Navmesh-Quellgeometrie.
			var ceiling_body := StaticBody3D.new()
			ceiling_body.name = "CeilingCollision_" + String(n.name)
			lb.dynamic_root.add_child(ceiling_body)
			ceiling_body.global_transform = ceiling.global_transform
			for child in ceiling.get_children():
				if child is CollisionShape3D:
					child.reparent(ceiling_body, true)
		var gaps: Array = []
		for door_z in ([-d / 3.0, 0.0, d / 3.0] if d>=6.4 else [0.0]):
			gaps.append([door_z,1.8,0.0,2.3,false])
		for side in [-1.0,1.0]:
			lb._wall(n, Vector3(side * corridor,0,0), d - 0.5, 3.0, 0.18, PI * 0.5, gaps.duplicate(true), "plaster")
			var room_width := w * 0.5 - corridor
			for room_z in [-d / 6.0,d / 6.0]:
				if (stairs and side > 0) or d<6.4:
					continue # Rechte Haushälfte: zusammenhängender echter Treppenraum.
				lb.box(Vector3(side * (corridor + room_width * 0.5),0,room_z), Vector3(room_width,3.0,0.18), "plaster", 0, true, n)
			# Niedrige Sockelleisten betonen den Bodenanschluss, ohne die Flurtüren zu verschließen.
			for room_z in [-d / 3.0,0.0,d / 3.0]:
				lb.box(Vector3(side * (w * 0.5 - 0.2),0.05,room_z), Vector3(0.12,0.18,d / 3.0 - 0.3), "darkwood", 0, false, n)
	elif kind in ["barn", "shed"]:
		# Tragwerk unter dem Satteldach bleibt aus der Bodenperspektive sichtbar.
		var rise := tan(0.37) * d * 0.5
		for x in [-w * 0.3,0.0,w * 0.3]:
			lb.box(Vector3(x,h - 0.22,0), Vector3(0.22,0.22,d - 0.3), "darkwood", 0, false, n)
			for side in [-1.0,1.0]:
				var rafter := lb.box(Vector3(x,h + rise * 0.5 - 0.18,side * d * 0.25), Vector3(0.18,0.18,d * 0.5 / cos(0.37)), "darkwood", 0, false, n)
				rafter.rotation.x = side * 0.37

func merge_building_visuals(root: Node3D, group_name := "bavaria_building_visuals") -> void:
	# PerfTuning blendet kleine Wandstücke sonst bei 70–320 m aus, während Dächer stehen bleiben.
	# Ein gemeinsames Mesh pro Haus behält alle Teile in derselben Sichtweitenklasse.
	var surfaces := {}
	var sources := root.find_children("*", "MeshInstance3D", true, false)
	for mi in sources:
		if not mi.mesh:
			continue
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var material: Material = mi.get_active_material(si)
			if not surfaces.has(material):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(material)
				surfaces[material] = st
			surfaces[material].append_from(mi.mesh, si, xf)
	var mesh := ArrayMesh.new()
	for st in surfaces.values():
		st.commit(mesh)
	var visual := MeshInstance3D.new()
	visual.name = "CompleteBuildingVisual" if group_name == "bavaria_building_visuals" else "CompleteTreeVisual"
	visual.mesh = mesh
	# Wiederholtes Zusammenfassen nach Fassadenergänzungen: Namen vor dem Einfügen freigeben.
	for mi in sources:
		mi.free()
	root.add_child(visual)
	visual.add_to_group(group_name)

func _ruin(id: String, pos: Vector3, w: float, d: float, h: float, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.name = id + "_Ruine"
	n.add_to_group("bavaria_buildings")
	n.add_to_group("bavaria_ruins")
	lb.static_root.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	lb.box(Vector3(0, -0.1, 0), Vector3(w, 0.18, d), "rubble", 0, true, n)
	# Unregelmäßige Wandreste und mehrere breite, tatsächlich begehbare Breschen.
	for side in [-1.0, 1.0]:
		for i in 5:
			if i == 2 or (i == 1 and (side > 0 or id=="haus_2_tail")):
				continue
			var bh := h * rng.randf_range(0.22, 0.88)
			lb.box(Vector3(-w * 0.5 + (i + 0.5) * w / 5.0, 0, side * d * 0.5), Vector3(w / 5.0 - 0.5, bh, 0.5), "damaged", 0, true, n)
		lb.box(Vector3(side * w * 0.5, 0, -d * 0.28), Vector3(0.5, h * 0.7, d * 0.4), "brick", 0, true, n)
	# Erhaltene Dachhälfte, verkohlte Balken; keine unsichtbare intakte Dachkollision.
	var roof := lb.box(Vector3(-w * 0.26, h * 0.67, -d * 0.25), Vector3(w * 0.46, 0.18, d * 0.5), "roof", 0, true, n)
	roof.rotation.x = 0.28
	# Erhaltenes Dachstück an verkohlten Stützen abfangen; keine frei schwebende Dachplatte.
	for x in [-w * 0.46, -w * 0.24]:
		for z in [-d * 0.43, -d * 0.07]:
			var beam_h: float = h * 0.67 - tan(0.28) * (z + d * 0.25) + 0.04
			var support := lb.box(Vector3(x, 0, z), Vector3(0.22, beam_h, 0.22), "darkwood", 0, true, n)
			support.add_to_group("bavaria_roof_supports")
			support.set_meta("roof_point",Vector3(x,beam_h,z))
	for i in 4:
		var beam := lb.box(Vector3(-w * 0.3 + i * w * 0.19, 0.3, -d * 0.16), Vector3(0.22, 0.22, d * 0.5), "darkwood", 0.18 * i, false, n)
		beam.rotation.x = 0.0
		# Rest the lowest rotated vertex on the real ground instead of a fixed hover offset.
		beam.position.y -= vertex_bounds(beam,Transform3D.IDENTITY).position.y
		beam.add_to_group("bavaria_ground_beams")
	for i in 18:
		var p := Vector3(rng.randf_range(-w * 0.43, w * 0.43), 0.05, rng.randf_range(-d * 0.4, d * 0.4))
		# Mittelachse für Spieler/KI freihalten; kleine Trümmer ohne Stolperkollision.
		if absf(p.x) < 2.5:
			continue
		lb.box(p, Vector3(rng.randf_range(0.3, 1.4), rng.randf_range(0.15, 0.55), rng.randf_range(0.3, 1.0)), "brick", rng.randf_range(-PI, PI), false, n)
	merge_building_visuals(n)
	return n

func release() -> void:
	for n in _models.values():
		if is_instance_valid(n):
			n.free()
	_models.clear()
	_tree_far_mesh.clear()   # Schlüssel = Vorlagenmeshes dieses Ladevorgangs (die Instanzen halten ihre Kopien selbst)
	_tree_far_mat.clear()


func _stair_floor(n: Node3D, w: float, d: float) -> void:
	# Zweiläufig, 18 Steigungen à 17,67 cm, Auftritt 29 cm, Laufbreite 1,10 m.
	# Die begehbare Geschossdecke spart beide Läufe aus; kein Collider durch das Treppenloch.
	var right := minf(4.85,w*0.5-0.90)
	var left := right-1.50
	var x0 := left-0.60
	var x1 := right+0.60
	var z0 := -2.00
	var z1 := 1.90
	for rect in [Rect2(-w*0.5+0.2,-d*0.5+0.2,x0+w*0.5-0.2,d-0.4),
		Rect2(x1,-d*0.5+0.2,w*0.5-0.2-x1,d-0.4),
		Rect2(x0,-d*0.5+0.2,x1-x0,z0+d*0.5-0.2),
		Rect2(x0,z1,x1-x0,d*0.5-0.2-z1)]:
		lb.box(Vector3(rect.get_center().x,3.0,rect.get_center().y),Vector3(rect.size.x,0.18,rect.size.y),"wood",0,true,n)
	var rise := 3.18/18.0
	var run := 0.29
	var start_z := 1.60
	var landing_z := start_z-9*run
	for i in 9:
		var height := (i+1)*rise
		lb.box(Vector3(left,0,start_z-(i+0.5)*run),Vector3(1.10,height,run+0.012),"wood",0,true,n)
		var upper := (i+10)*rise
		lb.box(Vector3(right,0,landing_z+(i+0.5)*run),Vector3(1.10,upper,run+0.012),"wood",0,true,n)
	lb.box(Vector3((left+right)*0.5,0,landing_z-0.45),Vector3(2.60,9*rise,0.90),"wood",0,true,n)
	lb.box(Vector3(right,3.0,1.85),Vector3(1.10,0.18,0.60),"wood",0,true,n)
	# Seitenschutz am offenen Treppenauge, Podest und Obergeschoss. Handlaufhöhe 95 cm.
	for x in [left-0.55,right+0.55]:
		for i in 10:
			var z := start_z-i*run
			var y := i*rise if x<right else (18-i)*rise
			lb.box(Vector3(x,y,z),Vector3(0.06,0.95,0.06),"darkwood",0,false,n)
	_stair_hand(n,Vector3(left-0.55,0.95,start_z),Vector3(left-0.55,9*rise+0.95,landing_z))
	_stair_hand(n,Vector3(right+0.55,18*rise+0.95,start_z),Vector3(right+0.55,9*rise+0.95,landing_z))
	_stair_hand(n,Vector3(left-0.55,9*rise+0.95,landing_z-0.90),Vector3(right+0.55,9*rise+0.95,landing_z-0.90))
	for x in [x0,x1]:
		lb.box(Vector3(x,3.18,(z0+z1)*0.5),Vector3(0.08,0.95,z1-z0),"darkwood",0,true,n)
	# Das Treppenloch ist über dem oberen Ausstieg nach +Z offen.
	lb.box(Vector3((x0+x1)*0.5,3.18,z0),Vector3(x1-x0,0.95,0.08),"darkwood",0,true,n)
	n.add_to_group("bavaria_stair_houses")
	n.set_meta("stair_rise",rise)
	n.set_meta("stair_run",run)
	n.set_meta("stair_path",[Vector3(left,0.10,2.10),Vector3(left,9*rise+0.05,landing_z-0.45),
		Vector3(right,9*rise+0.05,landing_z-0.45),Vector3(right,3.23,2.45)])

func _stair_hand(parent: Node3D,a: Vector3,b: Vector3) -> void:
	var beam := lb.box(Vector3.ZERO,Vector3(0.07,a.distance_to(b),0.07),"darkwood",0,false,parent)
	for child in beam.get_children():
		if child is Node3D:
			child.position.y -= a.distance_to(b)*0.5
	beam.position = (a+b)*0.5
	beam.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

func _woodland_shed(pos: Vector3,w: float,d: float,h: float,yaw: float) -> Node3D:
	# Schmaler Referenz-Holzbau, Eingang auf der Feldseite und gedeckte Giebelstellung.
	var door_x := w*0.22
	var n := lb.building(pos,w,d,h,"wood","roof",[["s",door_x]],false,yaw,[["w",0.0,2.3]])
	n.name = "woodland_shed"
	n.add_to_group("bavaria_buildings")
	n.add_to_group("bavaria_enterable_sheds")
	n.set_meta("footprint_size",Vector2(w,d))
	n.set_meta("building_kind","barn")
	n.set_meta("entry_points",[{"point":Vector3(door_x,0,d*0.5),"normal":Vector3(0,0,1),"approach":1.5}])
	n.set_meta("mg_aperture",Vector3(-w*0.5,1.5,0))
	# Tor wird zur Schießöffnung: niedrige Brüstung und tragender Sturz, dazwischen frei.
	lb.box(Vector3(-w*0.5,0,0),Vector3(0.3,0.95,2.3),"wood",0,true,n)
	lb.box(Vector3(-w*0.5,2.10,0),Vector3(0.3,h-2.4,2.3),"wood",0,true,n)
	for z in [-1.20,1.20]:
		lb.box(Vector3(-w*0.5,0,z),Vector3(0.22,h,0.16),"darkwood",0,true,n)
	# Durchgehende ebene Dielen; kleine Gegenstände bleiben abseits des Eingangs.
	lb.box(Vector3(0,-0.05,0),Vector3(w-0.35,0.09,d-0.35),"wood",0,true,n)
	var b := Basis(Vector3.UP,yaw)
	prop("e_pbx1",pos+b*Vector3(w*0.40,0,-d*0.22),yaw,1.0,true)
	prop("e_ktable",pos+b*Vector3(w*0.31,0,-d*0.23),yaw,0.7,true)
	merge_building_visuals(n)
	return n



