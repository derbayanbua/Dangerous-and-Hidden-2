extends RefCounted
## Ausschließlich Bavaria: bewusst gesetzte WW2-Deckungs- und Hofgruppen.
## Keine Fahrzeuge/Interaktionen, kein globales Scatter und keine vorgetäuschten Gräben.
var m: Mission
var lb: LevelBuilder
var templates: RefCounted
var sources := {}
var sites: Array[Dictionary] = []
var missing: Array[String] = []
var root: Node3D
var layout_ratio := 1.0

func _init(mission: Mission) -> void:
	m = mission
	lb = m.lb
	templates = m._templates

func build() -> void:
	layout_ratio = float(m.layout.get("meters_per_reference_pixel",0.62))/0.62
	root = Node3D.new()
	root.name = "HistorischeDeckungUndHoefe"
	m.static_root.add_child(root)
	_reserve_entry_corridors()
	var worn_earth := lb.mat("earth").duplicate() as StandardMaterial3D
	worn_earth.albedo_color = Color(0.51,0.42,0.30)
	worn_earth.roughness = 1.0
	lb._mats["war_worn_earth"] = worn_earth
	# Straßen-/Hofränder statt Fahrbahnmitten; Fahrzeuge bleiben im natürlichen Metermaßstab.
	for spec in [
		["PKW_Dorfrand",[273,851],"la_citr_vrak01",0.4],
		["PKW_Gartenpassage",[564,803],"la_citr_vrak01",1.5],
		["PKW_Haeuserzeile",[1007,573],"la_citr_vrak01",-0.7],
		["PKW_Suedgarten",[650,1149],"la_citr_vrak01",2.2],
		["Halbkette_Zeilenrand",[830,548],"la_hakl_vrak01",-0.8],
		["Tiger_Wiesenrand",[699,367],"la_tiger_vrak01",0.2]]:
		_wreck(spec[0],spec[1],spec[2],float(spec[3]))
	for spec in [
		["Feldstellung_West",[480,464],"sandbags",0.65],
		["Feldstellung_Ost",[798,411],"sandbags",-0.6],
		["Wiesendeckung",[609,572],"sandbags",0.3],
		["Obstgartendeckung",[770,1058],"sandbags",-0.5],
		["Mauerrest_Garten",[552,879],"masonry",0.4],
		["Mauerrest_Dorfrand",[281,916],"masonry",-0.6],
		["Mauerrest_Zeilen",[947,824],"masonry",0.1],
		["Holzlager_Hof",[526,979],"woodstore",0.0],
		["Holzlager_Sued",[684,1137],"woodstore",0.5],
		["Holzlager_Wiese",[736,287],"woodstore",0.0]]:
		_cover(spec[0],spec[1],spec[2],float(spec[3]))
	for spec in [["Werkplatz_Hof",[565,963],false],["Werkplatz_Scheune",[377,794],true]]:
		_workshop(spec[0],spec[1],spec[2])
	for spec in [
		["Nutzgarten_Hecke",[587,990],0.0],
		["Nutzgarten_Zeilen",[757,904],0.5],
		["Nutzgarten_Sued",[725,1114],-0.4],
		["Geraeteplatz_Nord",[771,542],0.3],
		["Geraeteplatz_Dorfrand",[352,924],0.1],
		["Geraeteplatz_Ost",[1005,746],-0.7]]:
		_garden(spec[0],spec[1],float(spec[2]))
	for source in sources.values():
		if is_instance_valid(source):
			source.free()
	sources.clear()
	print("BAVARIA WAR DECORATION: ",sites.size()," bewusst platzierte Gruppen, fehlend: ",missing)

func _reserve_entry_corridors() -> void:
	# Reservierungen gelten auch für die nachfolgende allgemeine Wald-/Requisitenphase.
	# Ein Fassmodell kann über seinen eigenen Ursprung hinausragen: daher nicht nur
	# Fassadenabstand, sondern den tatsächlichen beidseitigen Türweg freihalten.
	for building in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		if not building.get_meta("interior_partitioned",false) or not building.has_meta("footprint_size"):
			continue
		var size: Vector2 = building.get_meta("footprint_size")
		for side in [-1.0,1.0]:
			for offset in [0.0,1.25,2.5]:
				var pos: Vector3 = building.to_global(Vector3(0,0,side*(size.y*0.5+offset)))
				m._placed.append({"pos":pos,"radius":1.0,"purpose":"house_entry"})

func _allowed(center: Vector3, radius: float) -> bool:
	var q := Vector2(center.x,center.z)
	if not m.inside_map(center):
		return false
	for i in m.boundary.size():
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q,m.boundary[i],m.boundary[(i+1)%m.boundary.size()]))<radius+0.8:
			return false
	# Abstand schützt Fassaden, alle bestehenden Fensterstände und beide Hauseingänge.
	for footprint in m.building_footprints:
		if Geometry2D.is_point_in_polygon(q,footprint):
			return false
		for i in footprint.size():
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q,footprint[i],footprint[(i+1)%footprint.size()]))<radius+0.55:
				return false
	for spawn in m.layout.spawns:
		if center.distance_to(m.pixel(spawn.pixel))<radius+1.4:
			return false
	# Nur der tatsächliche Wiedereinstiegs-/Flaggenkern bleibt leer, nicht die ganze Zone.
	for zone in m.mp_zones():
		for slot in zone.slots:
			if center.distance_to(slot.pos)<radius+0.85:
				return false
	for ladder in m.get_tree().get_nodes_in_group("bavaria_scene_ladders"):
		if center.distance_to(ladder.global_position)<radius+1.4:
			return false
	for path in m.layout.paths:
		for i in path.points.size()-1:
			var a: Vector3 = m.pixel(path.points[i])
			var b: Vector3 = m.pixel(path.points[i+1])
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q,Vector2(a.x,a.z),Vector2(b.x,b.z)))<float(path.width)*0.5+radius+0.75:
				return false
	# Die anschließende Garten-Bauphase besitzt feste Grundstücksmauern; auch den
	# Rückzug einer Stellung nicht erst nachträglich mit einer dieser Mauern kreuzen.
	for segment in [ [[370,555],[567,752]], [[613,785],[764,634]],
		[[539,898],[658,1013]], [[677,1113],[825,964]], [[267,827],[358,917]],
		[[759,654],[690,727]], [[856,829],[784,900]] ]:
		var a: Vector3 = m.pixel(segment[0])
		var b: Vector3 = m.pixel(segment[1])
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q,Vector2(a.x,a.z),Vector2(b.x,b.z)))<radius+0.65:
			return false
	for placed in m._placed:
		if center.distance_to(placed.pos)<radius+float(placed.radius)+0.45:
			return false
	for placed in sites:
		if center.distance_to(placed.center)<radius+float(placed.radius)+0.65:
			return false
	# Bereits gezielt konstruierte Gewächshäuser, Beete und Steinlager schützen.
	for protected in [[666,902,16.0],[560,1051,10.0],[599,920,18.0],[528,866,5.0]]:
		if center.distance_to(m.pixel([protected[0],protected[1]]))<radius+float(protected[2])*layout_ratio:
			return false
	return true

func _site(ref: Array, radius: float) -> Vector3:
	var desired: Vector3 = m.pixel(ref)
	if _allowed(desired,radius):
		return desired
	# Kleine deterministische lokale Korrektur, keine beliebige Füllung der Karte.
	for ring in range(1,40):
		for i in 48:
			var angle := TAU*float(i)/48.0
			var candidate := desired+Vector3(cos(angle),0,sin(angle))*float(ring)
			if _allowed(candidate,radius):
				return candidate
	push_error("Keine sichere Dekoposition in Referenzumgebung "+str(ref))
	return Vector3.INF

func _rect_site(ref: Array, yaw: float) -> Vector3:
	# Eine schmale reale Gartenparzelle braucht keinen pauschalen 6-m-Kreis.
	var rect := Rect2(-2.15,-1.90,4.2,3.4)
	var basis := Basis(Vector3.UP,yaw)
	var desired: Vector3 = m.pixel(ref)
	for ring in 50:
		for i in 48:
			var angle := TAU*i/48.0
			var pos := desired+Vector3(cos(angle),0,sin(angle))*float(ring)
			var poly := PackedVector2Array()
			for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				var p: Vector3 = pos+basis*Vector3(corner.x,0,corner.y)
				poly.append(Vector2(p.x,p.z))
			if _rect_safe(pos,basis,rect,poly):
				return pos
	push_error("Keine sichere Gartenparzelle bei "+str(ref))
	return Vector3.INF

func _rect_safe(pos: Vector3, basis: Basis, rect: Rect2, poly: PackedVector2Array) -> bool:
	for point in poly:
		if not m.inside_map(Vector3(point.x,0,point.y)):
			return false
	for footprint in m.building_footprints:
		if not Geometry2D.intersect_polygons(poly,footprint).is_empty():
			return false
		for point in footprint:
			var local: Vector3 = basis.inverse()*(Vector3(point.x,0,point.y)-pos)
			if rect.grow(0.55).has_point(Vector2(local.x,local.z)):
				return false
	var protected_points: Array = []
	for spawn in m.layout.spawns:
		protected_points.append(m.pixel(spawn.pixel))
	for zone in m.mp_zones():
		for slot in zone.slots:
			protected_points.append(slot.pos)
	for ladder in m.get_tree().get_nodes_in_group("bavaria_scene_ladders"):
		protected_points.append(ladder.global_position)
	for point in protected_points:
		var local: Vector3 = basis.inverse()*(point-pos)
		if rect.grow(0.85).has_point(Vector2(local.x,local.z)):
			return false
	for placed in m._placed:
		var local: Vector3 = basis.inverse()*(placed.pos-pos)
		var p := Vector2(local.x,local.z)
		var nearest := Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.y,rect.position.y,rect.end.y))
		if p.distance_to(nearest)<float(placed.radius)+0.45:
			return false
	for path in m.layout.paths:
		for i in path.points.size()-1:
			var a: Vector3 = basis.inverse()*(m.pixel(path.points[i])-pos)
			var b: Vector3 = basis.inverse()*(m.pixel(path.points[i+1])-pos)
			if _crosses_rect(Vector2(a.x,a.z),Vector2(b.x,b.z),rect.grow(float(path.width)*0.5+0.65)):
				return false
	for segment in [ [[370,555],[567,752]], [[613,785],[764,634]], [[539,898],[658,1013]],
		[[677,1113],[825,964]], [[267,827],[358,917]], [[759,654],[690,727]], [[856,829],[784,900]] ]:
		var a: Vector3 = basis.inverse()*(m.pixel(segment[0])-pos)
		var b: Vector3 = basis.inverse()*(m.pixel(segment[1])-pos)
		if _crosses_rect(Vector2(a.x,a.z),Vector2(b.x,b.z),rect.grow(0.55)):
			return false
	for protected in [[666,902,16.0],[560,1051,10.0],[599,920,18.0],[528,866,5.0]]:
		var p: Vector3 = basis.inverse()*(m.pixel([protected[0],protected[1]])-pos)
		var nearest := Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.z,rect.position.y,rect.end.y))
		if Vector2(p.x,p.z).distance_to(nearest)<float(protected[2])*layout_ratio:
			return false
	return true

func _crosses_rect(a: Vector2,b: Vector2,rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4])!=null:
			return true
	return false

func _group(id: String, position: Vector3, radius: float, size: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.name = id
	root.add_child(n)
	n.position = position
	n.rotation.y = yaw
	n.add_to_group("bavaria_war_groups")
	n.add_to_group("bavaria_decorations")
	n.set_meta("bounds_size",size)
	n.set_meta("placement_radius",radius)
	sites.append({"center":position,"radius":radius,"node":n})
	m._placed.append({"pos":position,"radius":radius})
	return n

func _asset(relative: String) -> Node3D:
	if not sources.has(relative):
		var path := OrigLevel.cache_root()+"/"+relative+".glb"
		sources[relative] = OrigLevel.parse_glb(path)
		if sources[relative] == null:
			missing.append(path)
			templates.missing.append(path)
	if sources[relative] == null:
		return null
	var wrapper := Node3D.new()
	var content := (sources[relative] as Node3D).duplicate() as Node3D
	wrapper.add_child(content)
	var bounds: AABB = templates.mesh_bounds(content,Transform3D.IDENTITY)
	content.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	wrapper.set_meta("source",relative)
	wrapper.set_meta("natural_size",bounds.size)
	templates.reused_models += 1
	return wrapper

func _wreck(id: String, ref: Array, model: String, yaw: float) -> void:
	var asset := _asset("normandy2_mp_zone/models/"+model)
	if asset == null:
		return
	var size: Vector3 = asset.get_meta("natural_size")
	var radius := Vector2(size.x,size.z).length()*0.5+0.45
	var center := _site(ref,radius+0.85)
	if not center.is_finite():
		asset.free()
		return
	var n := _group(id,center,radius+0.85,size,yaw)
	n.add_to_group("bavaria_wrecks")
	n.set_meta("source",asset.get_meta("source"))
	n.set_meta("static_wreck",true)
	n.add_child(asset)
	# Dreiecksflächen der wirklichen Wrackhülle statt massiver Fensterscheiben-/Luftbox.
	templates._mesh_colliders(asset)
	_ground_patch(n,Vector3.ZERO,Vector3(size.x+1.5,0.035,size.z+1.5),"war_worn_earth",true)
	for i in 5:
		var side := -1.0 if i%2 else 1.0
		lb.box(Vector3(side*(size.x*0.5+0.25),0.02,(i-2)*0.4),Vector3(0.30,0.06,0.18),"old_steel",i*0.8,false,n)
	# Nachprüfbare lokale Unterkörper-Deckungsstrahlen, keine Fahrzeugspielsysteme.
	n.set_meta("cover_height",0.60 if model=="la_citr_vrak01" else 0.85)

func _ground_patch(parent: Node3D, pos: Vector3, size: Vector3, material: String, irregular := false) -> void:
	if not irregular:
		lb.box(pos,size,material,0,false,parent)
		return
	# Ausgetretener Rand folgt der Objektgruppe, kein rechteckiger Teppich auf der Wiese.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		for index in [-1,i,(i+1)%14]:
			var angle := TAU*float(index)/14.0
			var edge := 0.90+sin(float(index)*2.7)*0.10
			var v := Vector3.ZERO if index<0 else Vector3(cos(angle)*size.x*0.5*edge,0,sin(angle)*size.z*0.5*edge)
			v += pos+Vector3.UP*size.y
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(v.x,v.z)*0.12)
			surface.add_vertex(v)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = lb.mat(material)
	parent.add_child(mesh)

func _cover(id: String, ref: Array, kind: String, yaw: float) -> void:
	var radius := 3.15 if kind=="sandbags" else 2.85
	var center := _site(ref,radius)
	if not center.is_finite():
		return
	var n := _group(id,center,radius,Vector3(4.0,1.2,3.2),yaw)
	n.add_to_group("bavaria_fixed_cover")
	n.set_meta("cover_height",0.65)
	_ground_patch(n,Vector3(-0.1,0.015,0),Vector3(3.8,0.03,3.3),"war_worn_earth",true)
	if kind == "sandbags":
		# U-Stellung mit offenem rückwärtigem Zugang; kein flach übermalter Graben.
		_bag_wall(n,Vector3(0,0,-1.0),2.8,0.0)
		_bag_wall(n,Vector3(-1.25,0,0),2.1,PI*0.5)
		_bag_wall(n,Vector3(1.25,0,0),2.1,PI*0.5)
		for x in [-1.0,1.0]:
			lb.box(Vector3(x,0,0.5),Vector3(0.16,0.55,0.8),"darkwood",0,true,n)
	elif kind == "masonry":
		for row in 3:
			for col in 4-row:
				lb.box(Vector3((col-(3-row)*0.5)*0.67+(0.10 if row%2 else 0),row*0.35,-1.0),Vector3(0.63,0.34,0.58),"damaged",sin(col*2.0)*0.05,true,n)
		for i in 10:
			lb.box(Vector3(sin(i*1.7)*2.2,0,cos(i*2.3)*1.6),Vector3(0.25,0.12,0.18),"rubble",i*0.7,false,n)
	else:
		lb.box(Vector3(0,0,-1),Vector3(2.8,1.05,1.15),"darkwood",0,true,n)
		for i in 12:
			lb.box(Vector3(0,(i+1)*0.085,-1),Vector3(2.95,0.07,1.3),"wood",sin(i*2.3)*0.025,false,n)
		for x in [-1.15,1.15]:
			lb.box(Vector3(x,0,-0.2),Vector3(0.14,1.3,0.14),"wood",0,true,n)

func _bag_wall(parent: Node3D, center: Vector3, length: float, yaw: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = center
	holder.rotation.y = yaw
	var collider := lb.box(Vector3(-0.05,0,0),Vector3(length,0.95,0.58),"sandbag",0,true,holder)
	for child in collider.get_children():
		if child is MeshInstance3D:
			child.free()
	var bag := CapsuleMesh.new()
	bag.radius = 0.19
	bag.height = 0.78
	bag.radial_segments = 8
	bag.rings = 2
	var count := int(length/0.65)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = bag
	batch.multimesh.instance_count = 3*count
	batch.material_override = lb.mat("sandbag")
	holder.add_child(batch)
	for row in 3:
		for i in count:
			var basis := Basis(Vector3.FORWARD,PI*0.5)*Basis.from_scale(Vector3(0.85,1,1.55))
			var position := Vector3(-length*0.5+0.38+i*0.65+(0.13 if row%2 else 0),0.17+row*0.31,0)
			batch.multimesh.set_instance_transform(row*count+i,Transform3D(basis,position))

func _workshop(id: String, ref: Array, toppled: bool) -> void:
	var center := _site(ref,3.6)
	if not center.is_finite():
		return
	var n := _group(id,center,3.6,Vector3(5.5,2.5,4),0.2)
	n.add_to_group("bavaria_damaged_machines")
	_ground_patch(n,Vector3.ZERO,Vector3(4.5,0.035,4.0),"stone")
	var boiler := _asset("czech6_mp_zone/models/la_agreg01")
	if boiler:
		n.add_child(boiler)
		boiler.position = Vector3(-0.6,0.05,-0.6)
		if toppled:
			boiler.rotation.z = -0.6
			var b: AABB = templates.mesh_bounds(boiler,Transform3D.IDENTITY)
			boiler.position.y -= b.position.y
		templates._mesh_colliders(boiler)
		boiler.set_meta("disabled_boiler",true)
	for i in 4:
		lb.box(Vector3(0.6+i*0.23,0,-1.2),Vector3(0.10,0.10,1.5),"old_steel",0.2*i,true,n)
	for item in [["ja_drevo",Vector3(1.1,0,0.5),0.55],["k_barelmir3",Vector3(-1.4,0,0.8),0.7],["e_bucket",Vector3(0.5,0,1.1),1.0]]:
		_small_prop(n,item[0],item[1],float(item[2]),item[0]=="k_barelmir3")

func _small_prop(parent: Node3D, model: String, position: Vector3, scale_value: float, collision: bool) -> void:
	var prop: Node3D = templates.prop(model,Vector3.ZERO,0,scale_value,collision)
	if prop:
		prop.reparent(parent,false)
		prop.position = position

func _garden(id: String, ref: Array, yaw: float) -> void:
	# Kleinere echte Parzelle im realistischen Ortsmaßstab; Requisiten selbst
	# werden nicht geschrumpft. Vier Meter Wäscheleine brauchen keinen 10-m-Kreis.
	var compact := layout_ratio<0.5
	var half_width := 1.3 if compact else 2.8
	var radius := 3.05 if compact else 5.3
	var center := _rect_site(ref,yaw) if compact else _site(ref,radius)
	if not center.is_finite():
		return
	var n := _group(id,center,radius,Vector3(4.5 if compact else 7,2.4,6),yaw)
	n.add_to_group("bavaria_garden_groups")
	# Kompost-/Nutzbeet, Handkarren, aufgelegte Bretter und schlichte Wäscheleine.
	var bed_depth := 1.8 if compact else 2.8
	var bed_center := -0.9 if compact else -1.2
	var line_z := 1.3 if compact else 2.0
	_ground_patch(n,Vector3(0,0.015,bed_center),Vector3(half_width*2+0.2,0.03,bed_depth),"earth")
	for x in [-half_width,half_width]:
		lb.box(Vector3(x,0,bed_center),Vector3(0.12,0.32,bed_depth+0.1),"wood",0,true,n)
	for z in [bed_center-bed_depth*0.5,bed_center+bed_depth*0.5]:
		lb.box(Vector3(0,0,z),Vector3(half_width*2,0.30,0.12),"wood",0,true,n)
	for row in 3:
		_ground_patch(n,Vector3(0,0.05,bed_center-bed_depth*0.35+row*bed_depth*0.35),Vector3(half_width*2-0.8,0.06,0.32),"grass")
	for x in [-half_width+0.2,half_width-0.2]:
		lb.cylinder(Vector3(x,0,line_z),0.055,2.25,"darkwood",true,n)
	lb.box(Vector3(0,2.15,line_z),Vector3(half_width*2-0.4,0.025,0.025),"darkwood",0,false,n)
	for i in (2 if compact else 3):
		lb.box(Vector3((-0.6+i*1.2) if compact else (-1.7+i*1.4),1.10,line_z),Vector3(0.8,1.05,0.02),"sandbag",0,false,n)
	_small_prop(n,"e_wuchar",Vector3(half_width+0.2,0,-0.3),0.9,false)
	_small_prop(n,"e_bucket",Vector3(-2,0,0.7),1.0,false)
