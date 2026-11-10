extends Mission
## Bavaria — genau eine eigene MP-Karte, Testkarte, blau begrenzte Spielfläche.
## Lageplan im gemeinsamen, am Grundriss Haus 16 kalibrierten Metermaßstab.

const LAYOUT := "res://assets/maps/bavaria/layout.json"
const GroundSurfaces := preload("res://src/maps/bavaria/ground_surfaces.gd")
const WoodlandEmplacement := preload("res://src/maps/bavaria/woodland_emplacement.gd")
const Templates := preload("res://src/maps/bavaria/templates.gd")
const SceneDetails := preload("res://src/maps/bavaria/scene_details.gd")
const WarDecoration := preload("res://src/maps/bavaria/war_decoration.gd")
const FieldEmplacement := preload("res://src/maps/bavaria/field_emplacement.gd")
const InteriorDecoration := preload("res://src/maps/bavaria/interior_decoration.gd")
const MeadowCover := preload("res://src/maps/bavaria/meadow_cover.gd")
const PrankMines := preload("res://src/maps/bavaria/prank_mines.gd")
const RoomLighting := preload("res://src/maps/bavaria/room_lighting.gd")
const FieldTrenches := preload("res://src/maps/bavaria/field_trenches.gd")
const SceneMatch := preload("res://src/maps/bavaria/scene_match.gd")
const REF_ORIGIN := Vector2(650, 720)
const X_AXIS := Vector2(0.576, 0.817)
const Z_AXIS := Vector2(-0.817, 0.576)
var ground_surfaces: RefCounted
var woodland_emplacement: RefCounted
var layout: Dictionary = {}
var boundary := PackedVector2Array()
var building_footprints: Array[PackedVector2Array] = []
var asset_report := {}
var _templates: RefCounted
var _rng := RandomNumberGenerator.new()
var _placed: Array[Dictionary] = []
var _zones: Array = []
var scene_details: RefCounted
var war_decoration: RefCounted
var field_emplacement: RefCounted
var meadow_cover: RefCounted
var interior_decoration: RefCounted
var frontline := false
var prank_mines: Node3D
var room_lighting: Node3D
# Net._zones verwendet denselben find_frame-Vertrag wie bei Originalkarten.
# Hier gibt es keine Original-Skript-VM; nur registrierte Flaggenknoten werden aufgelöst.
class ZoneFrames:
	extends RefCounted
	var frames := {}
	func find_frame(id: String) -> Node3D:
		return frames.get(id)
var runtime := ZoneFrames.new()

func pixel(p, y := 0.0) -> Vector3:
	var v := Vector2(float(p[0]), float(p[1])) - REF_ORIGIN
	var scale_value := float(layout.get("meters_per_reference_pixel", 0.62))
	return Vector3(v.dot(X_AXIS) * scale_value, y, v.dot(Z_AXIS) * scale_value)

func layout_scale() -> float:
	# Nur planbezogene Längen; Soldaten, Türen, Fahrzeuge und Leitern bleiben in Metern.
	return float(layout["meters_per_reference_pixel"]) / 0.62

func polygon(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		var v := pixel(p)
		out.append(Vector2(v.x, v.z))
	return out

func inside_map(p: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), boundary)

func _build_world() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	boundary = polygon(layout["boundary"])
	_rng.seed = 19450428
	lb.height_scale = 0.0
	lb.size = 720.0
	light_factor = 1.0
	ground_material = 50
	ambience_sound = "a_birds.wav"
	_templates = Templates.new(lb)
	ground_surfaces = GroundSurfaces.new(lb)
	# Rein optische Fortsetzung außerhalb der Spielgrenze, ohne Boden-/Navmesh-Kollision.
	_ground(PackedVector2Array([Vector2(-1400,-1400),Vector2(1400,-1400),Vector2(1400,1400),Vector2(-1400,1400)]),
		"meadow", -0.3, false, "DistantCountryside", {}, [_house16_cellar_hole()] + FieldTrenches.hole_polygons())
	# Spielboden mit Aussparung für den Kellerhals von Haus 16 (begehbarer Keller nach Plan).
	# + abgesenkte Schützengräben auf dem Feld (FieldTrenches).
	var holes: Array = [_house16_cellar_hole()]
	holes.append_array(FieldTrenches.hole_polygons())
	_ground(boundary, "grass", 0.0, true, "PlayableGround", {}, holes)
	_ground(polygon(layout["meadow"]), "meadow", 0.012, false, "Wiese", {}, FieldTrenches.hole_polygons())
	_build_roads()
	_build_houses()
	woodland_emplacement = WoodlandEmplacement.new()
	woodland_emplacement.build(self)
	scene_details = SceneDetails.new(self)
	scene_details.build()
	SceneMatch.build(self)   # Szenendetails: Zaun/Tor, Hecke, Platten, Gartenhaus, Fassaden
	_templates.finish_og_windows(self)   # 11/2026: OG-Fenster auch an freien Giebeln
	_build_zones()
	field_emplacement = FieldEmplacement.new()
	field_emplacement.build(self)
	meadow_cover = MeadowCover.new()
	meadow_cover.build(self)
	war_decoration = WarDecoration.new(self)
	war_decoration.build()
	FieldTrenches.build_cover(self)
	interior_decoration = InteriorDecoration.new()
	interior_decoration.build(self)
	_build_gardens()
	_build_woodland()
	_templates.ground_vegetation(self)
	_cull_trees_at_buildings()
	_batch_tree_visuals()
	_build_details()
	SceneMatch.clear_sightlines(self)
	_build_border()
	room_lighting = RoomLighting.new()
	room_lighting.name = "Hausbeleuchtung"
	room_lighting.mission = self
	add_child(room_lighting)
	prank_mines = PrankMines.new()
	prank_mines.name = "Rauchminen"
	prank_mines.mission = self
	add_child(prank_mines)
	asset_report = {"textures": _templates.reused_textures, "models": _templates.reused_models,
		"missing": _templates.missing.duplicate(), "trees":get_tree().get_nodes_in_group("bavaria_trees").size(),
		"decorations":get_tree().get_nodes_in_group("bavaria_decorations").size()}
	_templates.release()
	print("BAVARIA: %d Gebäude, %d Originalmodelle, %d Originaltexturen, Grenze %.0f × %.0f m" % [
		get_tree().get_nodes_in_group("bavaria_buildings").size(), asset_report.models,
		asset_report.textures, _bounds().size.x, _bounds().size.y])
	print("BAVARIA DETAILS: %d Bäume, %d Dekogruppen" % [asset_report.trees, asset_report.decorations])

func _bounds() -> Rect2:
	var b := Rect2(boundary[0], Vector2.ZERO)
	for p in boundary:
		b = b.expand(p)
	return b

## Weltrechteck des Kellerhalses von Haus 16 (aus Layout + House16Plan, vor dem Hausbau berechnet).
func _house16_cellar_hole() -> PackedVector2Array:
	var spec: Dictionary = {}
	for b in layout["buildings"]:
		if b.id == "haus_16":
			spec = b
	if spec.is_empty():
		return PackedVector2Array()
	var angle := deg_to_rad(float(spec.angle))
	var direction := Vector2(cos(angle), sin(angle))
	var yaw := atan2(-direction.dot(Z_AXIS), direction.dot(X_AXIS))
	var k := float(layout.meters_per_reference_pixel)
	var r: Rect2 = Templates.House16Plan.stairwell_rect(float(spec.w) * k, float(spec.d) * k)
	var c := pixel(spec.center)
	var out := PackedVector2Array()
	for v in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var q: Vector3 = c + Basis(Vector3.UP, yaw) * Vector3(v.x, 0, v.y)
		out.append(Vector2(q.x, q.z))
	return out

func _ground(poly: PackedVector2Array, material: String, y: float, collision: bool, id: String, route: Dictionary = {}, holes: Array = []) -> void:
	var pieces: Array = [poly]
	var cut_holes: Array = holes.filter(func(h): return h.size() >= 3)
	if not cut_holes.is_empty():
		# Löcher ohne Innenringe: Fläche in senkrechte Streifen an allen Loch-Eckpunkten teilen.
		# Zwischen zwei Schnittlinien reicht jedes Loch von Streifenrand zu Streifenrand (keine Ecke im Inneren),
		# daher liefert clip_polygons nur Außenkonturen.
		var xs: Array = [-9000.0, 9000.0]
		for h in cut_holes:
			for p in h:
				xs.append(p.x)
		xs.sort()
		pieces = []
		for i in xs.size() - 1:
			if xs[i + 1] - xs[i] < 0.001:
				continue
			var strip := PackedVector2Array([Vector2(xs[i],-9000), Vector2(xs[i + 1],-9000), Vector2(xs[i + 1],9000), Vector2(xs[i],9000)])
			var parts: Array = Geometry2D.intersect_polygons(poly, strip)
			for h in cut_holes:
				var next: Array = []
				for part in parts:
					next.append_array(Geometry2D.clip_polygons(part, h))
				parts = next
			pieces.append_array(parts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		_ground_triangles(st, piece, y)
	_ground_finish(st, material, collision, id, route)

func _ground_triangles(st: SurfaceTool, poly: PackedVector2Array, y: float) -> void:
	var triangles := Geometry2D.triangulate_polygon(poly)
	for i in range(0, triangles.size(), 3):
		# Godot verwendet im Uhrzeigersinn angeordnete Vorderseiten.
		var a := poly[triangles[i]]
		var b := poly[triangles[i + 1]]
		var c := poly[triangles[i + 2]]
		if (b - a).cross(c - a) < 0:
			var tmp := b
			b = c
			c = tmp
		for p in [a, b, c]:
			st.set_normal(Vector3.UP)
			st.set_uv(p * 0.12)
			st.add_vertex(Vector3(p.x, y, p.y))

func _ground_finish(st: SurfaceTool, material: String, collision: bool, id: String, route: Dictionary) -> void:
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = mesh
	mi.material_override = ground_surfaces.material_for(material,id)
	if not route.is_empty() and mi.material_override is ShaderMaterial:   # ohne Bodentexturen: Standardmaterial
		mi.material_override = mi.material_override.duplicate()
		mi.material_override.set_shader_parameter("route_a",Vector2(route.a.x,route.a.z))
		mi.material_override.set_shader_parameter("route_b",Vector2(route.b.x,route.b.z))
		mi.material_override.set_shader_parameter("route_half_width",route.half_width)
	static_root.add_child(mi)
	if collision:
		mi.create_trimesh_collision()

func _build_roads() -> void:
	for road in layout["paths"]:
		var points: Array = road["points"]
		for i in points.size() - 1:
			var a := pixel(points[i])
			var b := pixel(points[i + 1])
			var normal := Vector2(-(b.z - a.z), b.x - a.x).normalized() * float(road["width"]) * 0.5
			var strip := PackedVector2Array([Vector2(a.x, a.z) + normal, Vector2(b.x, b.z) + normal,
				Vector2(b.x, b.z) - normal, Vector2(a.x, a.z) - normal])
			# Wege enden exakt an der blau vorgegebenen Grenze.
			for clipped in Geometry2D.intersect_polygons(strip, boundary):
				_ground(clipped, "earth", 0.025, false, String(road["id"]),{"a":a,"b":b,"half_width":float(road.width)*0.5})

func _house(id: String, pos: Vector3, w: float, d: float, height: float, yaw: float, kind: String, ruined: bool) -> void:
	_templates.house(id, pos, w, d, height, yaw, kind, ruined)
	var corners := PackedVector2Array()
	for v in [Vector3(-w/2, 0, -d/2), Vector3(w/2, 0, -d/2), Vector3(w/2, 0, d/2), Vector3(-w/2, 0, d/2)]:
		var q: Vector3 = pos + Basis(Vector3.UP, yaw) * v
		corners.append(Vector2(q.x, q.z))
	building_footprints.append(corners)

func _build_houses() -> void:
	for building in layout["buildings"]:
		_build_reference_part(building)
	for row in layout["rows"]:
		for unit in row["reference_units"]:
			_build_reference_part(unit)
	# Kellerhals Haus 16 wie ein Grundriss behandeln: keine Deko/Vegetation in der Treppengrube.
	var hole := _house16_cellar_hole()
	if hole.size() >= 3:
		building_footprints.append(hole)
	# Schützengräben (abgesenkt, begehbar); ihre Umrisse gelten wie Grundrisse für Deko/Vegetation.
	FieldTrenches.build(self)
	building_footprints.append_array(FieldTrenches.hole_polygons())

func _build_reference_part(spec: Dictionary, auxiliary := false) -> void:
	var angle := deg_to_rad(float(spec.angle))
	var direction := Vector2(cos(angle),sin(angle))
	var yaw := atan2(-direction.dot(Z_AXIS),direction.dot(X_AXIS))
	var scale_value := float(layout.meters_per_reference_pixel)
	var w := float(spec.w)*scale_value
	var d := float(spec.d)*scale_value
	var pos := pixel(spec.center)
	_house(spec.id,pos,w,d,float(spec.height),yaw,spec.kind,bool(spec.ruined))
	var node := static_root.get_node(String(spec.id)+("_Ruine" if bool(spec.ruined) else "")) as Node3D
	node.set_meta("reference_center",Vector2(spec.center[0],spec.center[1]))
	node.set_meta("reference_dimensions",Vector2(spec.w,spec.d))
	node.set_meta("source_component",int(spec.source_component))
	if auxiliary:
		node.remove_from_group("bavaria_buildings")
		node.add_to_group("bavaria_reference_extensions")
	for extension in spec.get("extensions",[]):
		_build_reference_part(extension,true)

func _free(p: Vector3, margin := 5.0) -> bool:
	if not inside_map(p):
		return false
	var q := Vector2(p.x, p.z)
	if Geometry2D.is_point_in_polygon(q,polygon(layout["meadow"])):
		return false
	# Referenzhof/markanter Baum werden bewusst gestaltet, nicht zufällig zugestellt.
	var reference_local := Vector2(q.dot(Vector2(X_AXIS.x,Z_AXIS.x)),q.dot(Vector2(X_AXIS.y,Z_AXIS.y))) / float(layout["meters_per_reference_pixel"]) + REF_ORIGIN
	if Rect2(450,800,250,310).has_point(reference_local):
		return false
	for i in boundary.size():
		if Geometry2D.get_closest_point_to_segment(q, boundary[i], boundary[(i + 1) % boundary.size()]).distance_to(q) < margin + 1.0:
			return false
	for f in building_footprints:
		if Geometry2D.is_point_in_polygon(q, f):
			return false
		for i in f.size():
			if Geometry2D.get_closest_point_to_segment(q, f[i], f[(i + 1) % f.size()]).distance_to(q) < margin:
				return false
	for s in layout["spawns"]:
		if pixel(s["pixel"]).distance_to(p) < 6.0:
			return false
	for z in layout.get("occupation_zones", []):
		if pixel(z["pixel"]).distance_to(p) < float(z["radius"]) + 4.0:
			return false
	for road in layout["paths"]:
		var points: Array = road["points"]
		for i in points.size() - 1:
			var a := pixel(points[i])
			var b := pixel(points[i + 1])
			if Geometry2D.get_closest_point_to_segment(q, Vector2(a.x,a.z), Vector2(b.x,b.z)).distance_to(q) < float(road["width"]) * 0.5 + margin:
				return false
	for item in _placed:
		if p.distance_to(item.pos) < float(item.radius) + margin:
			return false
	return true

func _build_zones() -> void:
	# Gleiches Zonenformat wie mp_arena._load_mp_json. Einnahme/Wertung/Respawn bleiben in Net.
	for data in layout.get("occupation_zones", []):
		var center := pixel(data["pixel"], 0.8)
		var slots: Array = []
		for offset in [Vector3(-2,0,-2), Vector3(2,0,-2), Vector3(-2,0,2), Vector3(2,0,2)]:
			slots.append({"pos": pixel(data["pixel"], 0.3) + offset, "yaw": 0.0})
		var flags := {}
		var owner := int(data["owner"])
		for side in ["allied", "axis", "neutral"]:
			flags[side] = String(data["id"]) + "_" + side
		_zones.append({"name": data["id"], "text": data["name"], "shape":"sphere",
			"xf": Transform3D(Basis(), center), "scale":Vector3.ONE,
			"radius":float(data["radius"]), "capture_time":float(data["capture_time_s"]),
			"owner":owner, "capturable":true, "flags":flags, "slots":slots})
		if int(Game.MISSIONS.get(Game.current_mission_id, {}).get("mp_mode", -1)) != Net.Mode.OCCUPATION:
			continue
		var pole := pixel(data["pixel"]) + Vector3(-4, 0, 0)
		lb.cylinder(pole, 0.07, 4.2, "darkwood", false, dynamic_root)
		for side in flags:
			var flag := MeshInstance3D.new()
			flag.name = flags[side]
			var quad := QuadMesh.new()
			quad.size = Vector2(1.8, 1.0)
			flag.mesh = quad
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.18,0.35,0.7) if side == "allied" else (Color(0.65,0.17,0.13) if side == "axis" else Color(0.7,0.7,0.62))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.material_override = mat
			dynamic_root.add_child(flag)
			flag.position = pole + Vector3(0.9, 3.5, 0)
			flag.visible = side == ("allied" if owner == 0 else ("axis" if owner == 1 else "neutral"))
			runtime.frames[flags[side]] = flag
		var label := Label3D.new()
		label.text = data["name"]
		label.position = pole + Vector3(0, 5, 0)
		label.font_size = 64
		label.pixel_size = 0.015
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dynamic_root.add_child(label)

func mp_zones() -> Array:
	return _zones

func woodland_clearance(p: Vector3,margin: float) -> bool:
	var house: Node3D = static_root.get_node("woodland_shed")
	var q := house.to_local(p)
	var size: Vector2 = house.get_meta("footprint_size")
	return absf(q.x)>size.x*0.5+margin or absf(q.z)>size.y*0.5+margin

func _tree(p: Vector3, scale_value: float, species: String) -> bool:
	var n: Node3D = _templates.prop(species, p, _rng.randf_range(-PI, PI), scale_value)
	if n == null:
		lb.tree(p.x, p.z, scale_value)
		return true
	# Echte Kronenausdehnung im Hausraum prüfen, nicht nur den kollidierenden Stamm.
	var bounds: AABB = _templates.mesh_bounds(n,Transform3D.IDENTITY)
	var house: Node3D = static_root.get_node("woodland_shed")
	var size: Vector2 = house.get_meta("footprint_size")
	var canopy := Rect2()
	for i in 8:
		var q := house.to_local(bounds.get_endpoint(i))
		if i==0:canopy = Rect2(Vector2(q.x,q.z),Vector2.ZERO)
		else:canopy = canopy.expand(Vector2(q.x,q.z))
	if canopy.intersects(Rect2(-size*0.5,size).grow(0.9)):
		n.free()
		return false
	n.add_to_group("bavaria_trees")
	_placed.append({"pos":p, "radius":3.5})
	# Nur Stammkollision: Blätter blockieren keine KI-Pfade und keine Spielerbewegung.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.32 * scale_value
	cylinder.height = 5.5 * scale_value
	shape.shape = cylinder
	shape.position = p + Vector3.UP * cylinder.height * 0.5
	body.add_child(shape)
	static_root.add_child(body)
	n.set_meta("trunk_collision",shape.get_path())
	return true

## Der tatsächliche Stammfuß (Vertexmessung in ground_vegetation) kann bei asymmetrischen Originalkronen
## (l_tree4) Meter neben dem Platzierungspunkt liegen. Zufallsbäume, deren echter Stamm in einem Grundriss
## oder < 1,2 m vor einer Fassade steht, werden entfernt (Clipping-Prüftest; gezielt gesetzte Laubgruppen bleiben).
func _cull_trees_at_buildings() -> void:
	for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
		if root.has_meta("foliage_index") or not is_instance_valid(root):
			continue
		var foot: Vector3 = root.get_meta("ground_contact_point", root.global_position)
		var q := Vector2(foot.x, foot.z)
		var hit := false
		for f in building_footprints:
			if Geometry2D.is_point_in_polygon(q, f):
				hit = true
			for i in f.size():
				if Geometry2D.get_closest_point_to_segment(q, f[i], f[(i + 1) % f.size()]).distance_to(q) < 1.2:
					hit = true
		if hit:
			if root.has_meta("trunk_collision"):
				var shape := get_node_or_null(NodePath(root.get_meta("trunk_collision")))
				if shape:
					shape.get_parent().free()
			root.free()

func _build_woodland() -> void:
	# Mehrreihiger Mischwald entlang der Referenzgrenze, keine einzelne Reihe gleicher Tannen.
	var species := ["l_tree", "l_tree2", "l_tree4", "e_treb1"]
	var planted := 0
	for i in 1500:
		var t := _rng.randf_range(0.03, 0.97)
		var edge := Vector2(746,138).lerp(Vector2(1140,697), t)
		if i % 3 == 0:
			edge = Vector2(746,138).lerp(Vector2(120,800), t)
		var ref := edge + (Vector2(650,720) - edge).normalized() * _rng.randf_range(22, 135)
		var p := pixel([ref.x, ref.y])
		if _free(p, 2.2):
			if _tree(p, _rng.randf_range(0.85, 1.5), species[planted % species.size()]):
				planted += 1
		if planted >= 150:
			break
	# Obst-/Hausgärten: kleine Laubbäume zwischen den bebauten Parzellen.
	for i in 1000:
		var p := pixel([_rng.randf_range(260, 1010), _rng.randf_range(710, 1190)])
		if _free(p, 2.2):
			if _tree(p, _rng.randf_range(0.55, 0.95), species[planted % 3]):
				planted += 1
		if planted >= 210:
			break

func _build_details() -> void:
	# Vorhandene HD2-Requisiten: Fässer, Holzstapel, Kisten, Eimer und Bänke.
	var models := ["k_barelmir3", "e_pbx1", "ja_drevo", "e_bucket", "e_wuchar"]
	var count := 0
	for i in 1200:
		var p := pixel([_rng.randf_range(220, 1040), _rng.randf_range(680, 1210)])
		if not _free(p, 2.0):
			continue
		var model: String = models[count % models.size()]
		var n: Node3D = _templates.prop(model, p, _rng.randf_range(-PI, PI), 1.0, model in ["k_barelmir3", "e_pbx1", "ja_drevo"])
		if n:
			n.add_to_group("bavaria_decorations")
			_placed.append({"pos":p, "radius":2.0})
			count += 1
		if count >= 90:
			break
	# Kleine Nutzgärten mit niedrigen Holzbeeteinfassungen; rein optische Reihen ohne Stolperkollision.
	var gardens := 0
	for i in 500:
		var p := pixel([_rng.randf_range(330, 850), _rng.randf_range(790, 1130)])
		if not _free(p, 5.0):
			continue
		var bed := Node3D.new()
		bed.name = "KitchenGarden"
		static_root.add_child(bed)
		bed.position = p
		bed.add_to_group("bavaria_decorations")
		lb.box(Vector3.ZERO, Vector3(6,0.05,4), "earth", 0, false, bed)
		for s in [-1.0,1.0]:
			lb.box(Vector3(s*3,0,0), Vector3(0.12,0.15,4.2), "wood", 0, false, bed)
			lb.box(Vector3(0,0,s*2), Vector3(6.2,0.15,0.12), "wood", 0, false, bed)
		for row in 5:
			lb.box(Vector3(-2.4+row*1.2,0.06,0), Vector3(0.4,0.08,3.7), "grass", 0, false, bed)
		_placed.append({"pos":p, "radius":5.0})
		gardens += 1
		if gardens >= 12:
			break

func _batch_tree_visuals() -> void:
	# Wiederholte Originalmeshes instanzieren statt tausende einzelne Baumteile zu zeichnen.
	# Die originalen Meshes, UVs und Materialien bleiben unverändert; Stammkollisionen bleiben separat.
	var batches := {}
	var sources: Array[MeshInstance3D] = []
	for tree in get_tree().get_nodes_in_group("bavaria_trees"):
		for child in tree.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var key := str(mi.mesh.get_instance_id()) + ":" + str(mi.material_override.get_instance_id() if mi.material_override else 0)
			if not batches.has(key):
				batches[key] = {"mesh":mi.mesh, "material":mi.material_override, "transforms":[]}
			batches[key].transforms.append(static_root.global_transform.affine_inverse() * mi.global_transform)
			sources.append(mi)
	for batch in batches.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch.mesh
		multi.instance_count = batch.transforms.size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "TreeBatch"
		instance.multimesh = multi
		instance.material_override = batch.material
		static_root.add_child(instance)
		instance.add_to_group("bavaria_tree_batches")
	# Kinder vor Eltern entfernen; einige glTF-Modelle besitzen Mesh-Knoten als Wurzel.
	for i in range(sources.size() - 1, -1, -1):
		if is_instance_valid(sources[i]):
			sources[i].free()

func _build_gardens() -> void:
	# Niedrige Grundstücksmauern, Gassen und Deckung folgen den bestehenden Parzellen.
	for pair in [ [[370,555],[567,752]], [[613,785],[764,634]],
		[[539,898],[658,1013]], [[677,1113],[825,964]], [[267,827],[358,917]],
		[[759,654],[690,727]], [[856,829],[784,900]] ]:
		var a := pixel(pair[0])
		var b := pixel(pair[1])
		var dist := a.distance_to(b)
		_garden_wall(Vector2(a.x,a.z),Vector2(b.x,b.z))
	# Original-Requisiten: Holzkisten, Fässer, Brennholz und Möbel, keine modernen Fahrzeuge/PV.
	for coord in [[312,778],[393,856],[553,1171],[711,913],[802,724],[1019,700],[725,283]]:
		var p := pixel(coord)
		if _free(p, 2):
			_templates.prop("e_pbx1", p, 0.5, 1.7, true)
			_templates.prop("ja_klada2", p + Vector3(3, 0, 1), 0.4, 1.0, true)
	for coord in [[472,651],[610,623],[805,546],[493,783],[750,875]]:
		var p := pixel(coord)
		if _free(p, 3):
			lb.sandbags(p, 5.5, 0.25)
			lb.sandbags(p + Vector3(2.5, 0, 1.8), 3.5, PI * 0.5)

func _garden_wall(a: Vector2,b: Vector2) -> void:
	# Parzellenmauern enden vor den jetzt exakt eingemessenen Hausumrissen.
	# So ragen weder sichtbare Mauer noch Collider in Wohnräume hinein.
	var steps := ceili(a.distance_to(b)/0.20)
	var start := -1
	for i in steps+1:
		var q := a.lerp(b,float(i)/steps)
		var valid := absf(float(i)/steps-0.5)*a.distance_to(b)>2.5
		for footprint in building_footprints:
			if Geometry2D.is_point_in_polygon(q,footprint):
				valid = false
			for j in footprint.size():
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q,footprint[j],footprint[(j+1)%footprint.size()]))<0.95:
					valid = false
		if valid and start<0:
			start = i
		if start>=0 and (not valid or i==steps):
			var end := i-1 if not valid else i
			if end-start>1:
				lb.line_wall(a.lerp(b,float(start)/steps),a.lerp(b,float(end)/steps),0.9,0.45,"stone")
			start = -1

func _build_border() -> void:
	# Blaue Linie = feste Spielgrenze. Bewegungsbarriere nur auf Layer 5: Sicht/Schüsse bleiben frei.
	for i in boundary.size():
		var a := boundary[i]
		var b := boundary[(i + 1) % boundary.size()]
		var dir := b - a
		var mid := (a + b) * 0.5
		var body := StaticBody3D.new()
		body.name = "MapBoundary_%d" % i
		body.collision_layer = LevelBuilder.FENCE_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(dir.length() + 1.0, 80.0, 0.35)
		cs.shape = box
		body.add_child(cs)
		dynamic_root.add_child(body)
		body.position = Vector3(mid.x, 35.0, mid.y)
		body.rotation.y = atan2(-dir.y, dir.x)
		body.add_to_group("bavaria_boundaries")
		# Sichtbare historische Grenzmarkierung: Holzpfähle und Stacheldraht exakt entlang der Linie.
		lb.fence(a, b, [], 1.8)
		for t in [0.15, 0.5, 0.85]:
			var p := a.lerp(b, t)
			lb.box(Vector3(p.x, 0, p.y), Vector3(0.18, 2.4, 0.18), "darkwood")
			lb.box(Vector3(p.x, 1.5, p.y), Vector3(1.4, 0.55, 0.1), "wood", atan2(-dir.y, dir.x), false)

func _configure_environment(e: Environment, light: DirectionalLight3D) -> void:
	e.fog_light_color = Color(0.63, 0.66, 0.59)
	e.fog_density = 0.00065
	e.volumetric_fog_density = 0.0003
	e.volumetric_fog_albedo = Color(0.43, 0.46, 0.60)
	e.fog_aerial_perspective = 0.1
	# Feste Abenddämmerung: Sonne knapp unter dem westlichen Horizont.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.48, 0.56, 0.76)
	e.ambient_light_energy = 0.34
	light.rotation_degrees = Vector3(2, -35, 0)
	light.light_color = Color(1.0, 0.58, 0.34)
	light.light_energy = 0.16
	if scene_details:
		scene_details.configure_sky(e)

func foliage_blocks_sight(from: Vector3, to: Vector3) -> bool:
	return scene_details != null and scene_details.blocks_sight(from,to)

## KI-Hinweise (Gräben, Deckung, Fenster, Haus 16, erhöhte Posten) für die allgemeine Bot-KI; beim ersten Abruf erzeugt.
var bot_hint_data: RefCounted

func _bot_hint_data() -> RefCounted:
	if bot_hint_data == null:
		bot_hint_data = preload("res://src/maps/bavaria/bot_hints.gd").new()
		bot_hint_data.build(self)
	elif not bot_hint_data.on_nav and nav_ready:
		bot_hint_data.build(self)        # vor dem Netz erzeugt: jetzt ans Netz heften
	return bot_hint_data

func bot_route_via(from: Vector3, to: Vector3) -> Array:
	return _bot_hint_data().route_via(from, to)

func bot_hints(center: Vector3, radius: float) -> Array:
	return _bot_hint_data().near(center, radius)

func bot_hint_stance(pos: Vector3) -> int:
	return _bot_hint_data().stance_at(pos)

func _spawn_actors() -> void:
	if Net.is_online:
		# Net erzeugt Bots sofort nach mission_ready. Auf dieser Karte erst nach dem
		# ersten Navmesh-Abgleich bewegen lassen (verhindert verfrühte Kartenabfragen).
		actors_root.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		# Direktstart ist eine freie Kartenbesichtigung mit bestehendem Trupp, ohne erfundene Kampagne.
		var start := pixel(layout["spawns"][0]["pixel"], 0.3)
		spawn_roster(start, 0.0, [Vector3.ZERO, Vector3(2,0,0), Vector3(0,0,2), Vector3(2,0,2)])

func _on_tick(_delta: float) -> void:
	if nav_ready and actors_root.process_mode == Node.PROCESS_MODE_DISABLED:
		actors_root.process_mode = Node.PROCESS_MODE_INHERIT

func _nav_tile_done(reg: NavigationRegion3D, tile: NavigationMesh) -> void:
	await super._nav_tile_done(reg, tile)
	if _nav_pending > 0 or not is_inside_tree():
		return
	# Nach dem Bake kann der Server seine Suchstruktur noch asynchron aufbauen.
	# Erst freigeben, wenn der bekannte Bodenstart tatsächlich auf dem Netz gefunden wird.
	nav_ready = false
	var nav_map := get_world_3d().navigation_map
	var start := pixel(layout["spawns"][0]["pixel"], 0.3)
	var deadline := Time.get_ticks_msec() + 15000
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		if NavigationServer3D.map_get_closest_point(nav_map,start).distance_to(start) < 2.0:
			nav_ready = true
			return
		await get_tree().create_timer(0.02).timeout
	push_error("Bavaria: Navigationsserver nach Bake nicht bereit")

func _setup_objectives() -> void:
	pass

## Integration: Klassenvorlagen (Net._apply_class, SPIELER-SETUP „Klasse“) wie die Waffenfreigabe aus der
## Karte aus dem Registereintrag "mp_allowed_from" (Game._register_test_maps: NORMANDY2_MP_ZONE,
## Alliierte/Achse, 5 Original-Klassen je Seite).
var _presets_cache := {}

func mp_presets(team: int) -> Array:
	if _presets_cache.is_empty():
		_presets_cache = {"allied": [], "axis": []}
		var folder: String = Game.mp_allowed_from("bavaria")
		var d = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/mp.json") if folder != "" else null
		if typeof(d) == TYPE_DICTIONARY and not (d.get("game_styles", []) as Array).is_empty():
			for p in d["game_styles"][0].get("presets", []):
				_presets_cache[String(p.get("side", "allied"))].append(_with_launcher(p))
	return _presets_cache["axis" if team == Soldier.TEAM_AXIS else "allied"]

## Raketenwerfer (Freigabe über "mp_extra_allowed"): Grenadier-Klasse („heavy gunner“) trägt ihn auf der Schulter,
## Alliierte M1 Bazooka (39) + 2 Raketen 206, Achse Panzerschreck (264) + 2 Raketen 205 [D].
const LAUNCHER_PRESET := {"allied": [39, 206], "axis": [264, 205]}
const LAUNCHER_ROCKETS := 2

static func _with_launcher(p: Dictionary) -> Dictionary:
	if not String(p.get("name", "")).to_lower().ends_with("heavy gunner"):
		return p
	var lp: Array = LAUNCHER_PRESET["axis" if String(p.get("side", "allied")) == "axis" else "allied"]
	var q := p.duplicate(true)
	var slots: Array = q.get("slots", [])
	if slots.size() > 2:
		slots[2] = {"item_id": int(lp[0]), "name": null}
	(q["list_a"] as Array).append({"item_id": int(lp[1]), "count": LAUNCHER_ROCKETS, "name": null})
	return q

## Integration: Kartenbild (Draufsicht, tests/render_bavaria_map.gd) für Ladebildschirm und Spawnzonen-Karte.
## rect = abgebildeter Weltausschnitt (x/z), quadratisch um die blaue Grenze, wie beim Erzeugen.
const MAP_IMAGE := "res://assets/ui/mp_maps/bavaria.png"

func mp_map_rect() -> Rect2:
	var b := _bounds()
	var side := maxf(b.size.x, b.size.y) * 1.08
	return Rect2(b.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))

func mp_map_image() -> Dictionary:
	if not ResourceLoader.exists(MAP_IMAGE):
		return {}
	return {"texture": load(MAP_IMAGE), "rect": mp_map_rect()}

func mp_spawns() -> Array:
	var out: Array = []
	for s in layout["spawns"]:
		out.append({"pos": pixel(s["pixel"], 0.3), "yaw": -PI * 0.5 if int(s["team"]) == 0 else PI * 0.5, "team": int(s["team"])})
	return out
