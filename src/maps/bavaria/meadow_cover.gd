extends RefCounted
## Zwei statische, sichtbar zerbrochene Originaljäger im unveränderten Metermaßstab.
var m: Mission
var t: RefCounted
var roots: Array[Node3D] = []
var footprints: Array[PackedVector2Array] = []
var missing: Array[String] = []

func build(mission: Mission) -> void:
	m = mission
	t = m._templates
	if not m.get_tree().get_nodes_in_group("bavaria_aircraft_wrecks").is_empty():
		return
	for spec in [["Absturz_West","cutletadlo_af2",[495,470],-0.45],
		["Absturz_Ost","la_spitfire",[775,400],0.65]]:
		_aircraft(spec[0],spec[1],spec[2],float(spec[3]))
	print("BAVARIA AIRCRAFT: ",roots.size()," echte zerbrochene Jäger, fehlend=",missing)

func _aircraft(id: String, model: String, ref: Array, yaw: float) -> void:
	var path := OrigLevel.cache_root()+"/africa2/models/"+model+".glb"
	var content := OrigLevel.parse_glb(path)
	if content == null:
		missing.append(path)
		t.missing.append(path)
		return
	var n := Node3D.new()
	n.name = id
	m.static_root.add_child(n)
	n.add_child(content)
	var natural: AABB = t.mesh_bounds(content,Transform3D.IDENTITY)
	content.position -= Vector3(natural.get_center().x,0,natural.get_center().z)
	# Fahrwerk eingeknickt/abgerissen; keine intakte Parkposition auf ausgefahrenen Rädern.
	var gear_count := 0
	for name in ["carriage_l00","carriage_r00"]:
		var gear := content.find_child(name,true,false)
		if gear:
			gear.free()
			gear_count += 1
	var propeller := content.find_child("vrtule",true,false)
	if propeller:
		propeller.free()
	for mesh in content.find_children("*","MeshInstance3D",true,false):
		if String(mesh.name).to_lower().contains("bluur") or String(mesh.name).to_lower().contains("bilboard"):
			mesh.free()
	var detached := Node3D.new()
	detached.name = "AbgerissenerFluegel"
	n.add_child(detached)
	var moved := 0
	for mesh in content.find_children("*","MeshInstance3D",true,false):
		moved += _separate_wing(mesh,n,detached)
	# Um den tatsächlichen Flügelmittelpunkt drehen, nicht um den Rumpfursprung.
	var wing_bounds: AABB = t.mesh_bounds(detached,Transform3D.IDENTITY)
	var pivot := wing_bounds.get_center()
	detached.position = pivot
	for child in detached.get_children():
		child.position -= pivot
	detached.rotation = Vector3(0.12,1.45,-0.30)
	detached.position += Vector3(-0.5,0,2.0)
	wing_bounds = t.mesh_bounds(detached,Transform3D.IDENTITY)
	detached.position.y -= wing_bounds.position.y
	content.rotation = Vector3(0.18,0,-0.18)
	var body_bounds: AABB = t.mesh_bounds(content,Transform3D.IDENTITY)
	content.position.y -= body_bounds.position.y
	# Bauchlandung: Rumpf in die Erde einsinken lassen, statt auf dem tiefsten
	# übrig gebliebenen Spornrad scheinbar in der Luft zu balancieren.
	content.position.y -= 0.85
	_weather(content,0.58)
	_weather(detached,0.40)
	# Abgebrochene Propellerblätter am Bug und abgesplitterte Spanten.
	for i in 3:
		m.lb.box(Vector3(-0.7+i*0.6,0.04,-natural.size.z*0.38),Vector3(0.12,0.08,1.1),"old_steel",i*0.85,false,n)
	var bounds: AABB = t.mesh_bounds(n,n.transform.affine_inverse())
	var radius := 0.0
	for corner in 8:
		var p := bounds.get_endpoint(corner)
		radius = maxf(radius,Vector2(p.x,p.z).length())
	var center := _site(ref,radius+0.9,bounds,yaw)
	if not center.is_finite():
		n.free()
		return
	n.position = center
	n.rotation.y = yaw
	var polygon := _footprint(center,bounds,yaw,1.6)
	footprints.append(polygon)
	n.set_meta("clearance_footprint",polygon)
	n.set_meta("bounds",bounds)
	n.set_meta("radius",radius)
	n.set_meta("source",path)
	n.set_meta("natural_size",natural.size)
	n.set_meta("detached_meshes",moved)
	n.set_meta("removed_gear",gear_count)
	n.add_to_group("bavaria_aircraft_wrecks")
	n.add_to_group("bavaria_decorations")
	t._mesh_colliders(content)
	t._mesh_colliders(detached)
	_scorch(n,bounds)
	m._placed.append({"pos":center,"radius":radius+1.0,"purpose":"aircraft_wreck"})
	t.reused_models += 1
	roots.append(n)
	print("AIRCRAFT SITE ",id," center=",center," radius=",radius," detached meshes=",moved)

func _weather(root: Node3D, shade: float) -> void:
	for mesh in root.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(i)
			if original is StandardMaterial3D:
				var mat := original.duplicate() as StandardMaterial3D
				mat.albedo_color *= Color(shade,shade*0.94,shade*0.87)
				mat.roughness = 0.95
				mesh.set_surface_override_material(i,mat)

func _separate_wing(mesh: MeshInstance3D, root: Node3D, detached: Node3D) -> int:
	# Auch die großen kombinierten Rumpfmeshes enthalten Flügelgeometrie. Tatsächliche
	# Dreiecke teilen; nur die benannten Steuerflächen zu bewegen ließe intakte Flügel zurück.
	if mesh.mesh == null:
		return 0
	var xf: Transform3D = root.global_transform.affine_inverse()*mesh.global_transform
	var rest := ArrayMesh.new()
	var wing := ArrayMesh.new()
	var separated := false
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var keep := SurfaceTool.new()
		var broken := SurfaceTool.new()
		for builder in [keep,broken]:
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_material(mesh.get_active_material(surface))
		var counts := [0,0]
		for i in range(0,indices.size()-2,3):
			var center := xf*((vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0)
			var cut := center.x < -1.05 and center.z > -2.5 and center.z < 1.6
			var builder: SurfaceTool = broken if cut else keep
			counts[1 if cut else 0] += 3
			for j in 3:
				var index := indices[i+j]
				if not normals.is_empty():
					builder.set_normal(normals[index])
				if not uv.is_empty():
					builder.set_uv(uv[index])
				builder.add_vertex(vertices[index])
		if counts[0]>0:
			keep.commit(rest)
		if counts[1]>0:
			broken.commit(wing)
			separated = true
	if not separated:
		return 0
	mesh.mesh = rest if rest.get_surface_count()>0 else null
	var fragment := MeshInstance3D.new()
	fragment.name = String(mesh.name)+"_Abbruch"
	fragment.mesh = wing
	detached.add_child(fragment)
	fragment.transform = xf
	return 1

func _footprint(center: Vector3, bounds: AABB, yaw: float, margin: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pair in [Vector2(bounds.position.x-margin,bounds.position.z-margin),Vector2(bounds.end.x+margin,bounds.position.z-margin),Vector2(bounds.end.x+margin,bounds.end.z+margin),Vector2(bounds.position.x-margin,bounds.end.z+margin)]:
		var p := center+Basis(Vector3.UP,yaw)*Vector3(pair.x,0,pair.y)
		out.append(Vector2(p.x,p.z))
	return out

func _distance(q: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(q,poly):
		return 0.0
	var distance := INF
	for i in poly.size():
		distance = minf(distance,q.distance_to(Geometry2D.get_closest_point_to_segment(q,poly[i],poly[(i+1)%poly.size()])))
	return distance

func _safe(center: Vector3, bounds: AABB, yaw: float) -> bool:
	# Real orientierte Grundfläche samt 1,6m Seitenroute statt zu großer Kreisscheibe.
	var poly := _footprint(center,bounds,yaw,1.6)
	var meadow: PackedVector2Array = m.polygon(m.layout.meadow)
	for corner in poly:
		if not Geometry2D.is_point_in_polygon(corner,meadow):
			return false
	for old in footprints:
		if not Geometry2D.intersect_polygons(poly,old).is_empty():
			return false
	var actual := _footprint(center,bounds,yaw,0.0)
	for protection in [[m.pixel([575,554]),5.5],[m.pixel([690,490]),4.2]]:
		if _distance(Vector2(protection[0].x,protection[0].z),actual)<float(protection[1]):
			return false
	for spawn in m.mp_spawns():
		if _distance(Vector2(spawn.pos.x,spawn.pos.z),actual)<1.5:
			return false
	for road in m.layout.paths:
		for i in road.points.size()-1:
			var a: Vector3 = m.pixel(road.points[i])
			var b: Vector3 = m.pixel(road.points[i+1])
			var samples := ceili(a.distance_to(b)/0.5)
			for j in samples+1:
				var q := a.lerp(b,float(j)/maxi(samples,1))
				if _distance(Vector2(q.x,q.z),actual)<float(road.width)*0.5+0.8:
					return false
	for placed in m._placed:
		if placed.get("purpose","")=="aircraft_wreck":
			continue
		if _distance(Vector2(placed.pos.x,placed.pos.z),actual)<float(placed.radius)+0.8:
			return false
	return true

func _site(ref: Array, _radius: float, bounds: AABB, yaw: float) -> Vector3:
	var desired: Vector3 = m.pixel(ref)
	for ring in 40:
		for i in 48:
			var angle := TAU*float(i)/48.0
			var candidate := desired+Vector3(cos(angle),0,sin(angle))*float(ring)*1.25
			if _safe(candidate,bounds,yaw):
				return candidate
	push_error("Kein sicherer Flugzeug-Wrackplatz an "+str(ref))
	return Vector3.INF

func _scorch(parent: Node3D, bounds: AABB) -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode depth_draw_never,cull_disabled;
uniform sampler2D ground_texture : source_color,repeat_enable;
void fragment(){
 vec2 q=(UV-vec2(0.5))*2.0;
 float noise=sin(q.x*24.0+sin(q.y*17.0))*sin(q.y*31.0)*0.055;
 float fade=1.0-smoothstep(0.35,0.98,length(q)+noise);
 ALBEDO=texture(ground_texture,UV*3.0).rgb*vec3(0.26,0.20,0.13);
 ALPHA=fade*0.90;
 ROUGHNESS=1.0;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ground_texture",(m.lb.mat("earth") as StandardMaterial3D).albedo_texture)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 20:
		for j in [-1,i,(i+1)%20]:
			var angle := TAU*float(j)/20
			var radial := 0.88+0.1*sin(j*2.7)
			var v := Vector3.ZERO if j<0 else Vector3(cos(angle)*bounds.size.x*0.53*radial,0,sin(angle)*bounds.size.z*0.52*radial)
			v.y = 0.027
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5+v.x/(bounds.size.x*1.06),0.5+v.z/(bounds.size.z*1.04)))
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "BrandUndSchleifspur"
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
