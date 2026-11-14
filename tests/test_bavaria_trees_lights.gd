extends Node
var passed := 0
var failed := 0
var m: Mission
func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(2))
func check(ok: bool,label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ",label)
func _run() -> void:
	while m==null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var trees := 0
	for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
		if not root.visible:
			continue
		trees += 1
		check(root.get_meta("ground_contact_checked",false) and root.get_meta("root_flare",false),"Vollständiger Baum erfasst: "+str(root.get_path()))
	var leaves := 0
	for root in get_tree().get_nodes_in_group("bavaria_ground_foliage"):
		leaves += 1
		var bounds: AABB = m._templates.vertex_bounds(root,root.get_parent().global_transform)
		check(absf(bounds.position.y-float(root.get_meta("ground_floor_y"))+0.045)<0.003,"Laub-/Gebüschgruppe am echten Boden: "+str(root.get_path()))
	check(trees>95,"Auch Wegbäume, Außenbäume und Sniperbaum erfasst")
	# Zweiter, äußerer Waldgürtel
	var rings := get_tree().get_nodes_in_group("bavaria_outer_forest_ring")
	check(rings.size()==1,"Äußerer Waldgürtel vorhanden")
	if rings.size()==1:
		var ring_trees: Array = rings[0].get_children()
		check(ring_trees.size()>=60,"Äußerer Waldgürtel dicht (%d Bäume)"%ring_trees.size())
		var inner_max := 0.0
		for n in get_tree().get_nodes_in_group("bavaria_boundary_screen")[0].get_children():
			if n.is_in_group("bavaria_all_tree_roots"):
				inner_max = maxf(inner_max,_outside_dist(Vector2(n.global_position.x,n.global_position.z)))
		var bad := 0
		for tr in ring_trees:
			var d := _outside_dist(Vector2(tr.global_position.x,tr.global_position.z))
			var inside := Geometry2D.is_point_in_polygon(Vector2(tr.global_position.x,tr.global_position.z),PackedVector2Array(m.boundary))
			var cols := 0
			for b in tr.find_children("*","CollisionObject3D",true,false):
				cols += int(b.collision_layer!=0)
			if inside or d<=inner_max+3.0 or cols>0:
				bad += 1
		print("INFO Außenring: innerer Waldrand bis %.1f m, %d Bäume"%[inner_max,ring_trees.size()])
		check(bad==0,"Alle Gürtelbäume außerhalb von Spielfläche und innerem Waldrand, ohne Kollision (Wege/Zonen/Spawns liegen innen)")
	if DisplayServer.get_name()!="headless":
		var actual_stems := 0
		for root in get_tree().get_nodes_in_group("bavaria_all_tree_roots"):
			if not root.visible:
				continue
			for stem in root.find_children("*","MeshInstance3D",true,false):
				if String(stem.name) in ["tree","hi1kmen"]:
					actual_stems += 1
					_verify_stem(stem.mesh,stem.global_transform,str(root.get_path()))
		for group in ["bavaria_tree_batches","bavaria_hedge_batches"]:
			for node in get_tree().get_nodes_in_group(group):
				var mesh: Mesh = node.multimesh.mesh
				if not String(mesh.resource_name) in ["l_tree_tree","l_tree2_tree","l_tree4_tree","e_treb1_hi1kmen"]:
					continue
				for index in node.multimesh.instance_count:
					actual_stems += 1
					_verify_stem(mesh,node.global_transform*node.multimesh.get_instance_transform(index),str(node.name)+"/"+str(index))
		check(actual_stems==trees,"Jeder einzelne Stamm im echten Renderer geprüft (%d/%d)"%[actual_stems,trees])
	else:
		print("INFO MultiMesh-Vertexprüfung nur mit echtem Renderer; headless prüft Registrierung/Laub/Licht.")
	var covered := {}
	for entry in m.room_lighting.coverage:
		covered[entry.house+"/"+entry.room] = true
		var light: OmniLight3D = entry.light
		check(light.is_visible_in_tree() and light.light_energy>0 and light.omni_range>=3.0,"Aktive Lichtquelle "+entry.house+"/"+entry.room)
		# Kulissenhäuser außerhalb der Grenze (niemand darin) leuchten ohne Schatten (Lichtbudget Tag/Nacht)
		check((light.shadow_enabled or entry.room=="Kulisse") and light.distance_fade_begin<=18.0,"Wände schirmen Licht ab; kurze Licht-Sichtweite")
		check(entry.fixture.find_children("*","CollisionShape3D",true,false).is_empty(),"Leuchte blockiert keine Soldatenwege")
	for room in get_tree().get_nodes_in_group("bavaria_furnished_rooms"):
		check(covered.has(String(room.get_meta("house"))+"/"+String(room.name)),"Jedes eingerichtete Zimmer beleuchtet: "+String(room.name))
	var houses := get_tree().get_nodes_in_group("bavaria_buildings")
	houses.append_array(get_tree().get_nodes_in_group("bavaria_aux_houses"))
	for house in houses:
		check(m.room_lighting.coverage.any(func(entry): return entry.house==String(house.name)),"Jedes Haus beleuchtet: "+String(house.name))
	print("BAVARIA TREES/LIGHTS: %d trees, %d foliage groups, %d lights; %d passed, %d failed"%[trees,leaves,m.room_lighting.fixtures.size(),passed,failed])
	get_tree().quit(0 if failed==0 else 1)
func _outside_dist(q: Vector2) -> float:
	var best := INF
	for i in m.boundary.size():
		var a: Vector2 = m.boundary[i]
		var b: Vector2 = m.boundary[(i+1)%m.boundary.size()]
		best = minf(best,Geometry2D.get_closest_point_to_segment(q,a,b).distance_to(q))
	return best
func _verify_stem(mesh: Mesh,xf: Transform3D,label: String) -> void:
	var lo := Vector3(INF,INF,INF)
	var hi := Vector3(-INF,-INF,-INF)
	var vertices: Array = []
	if mesh.has_meta("main_trunk_base"):
		vertices = mesh.get_meta("main_trunk_base")
	else:
		for surface in mesh.get_surface_count():
			vertices.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	for vertex in vertices:
			var point: Vector3 = xf*vertex
			lo = lo.min(point)
			hi = hi.max(point)
	var foot := Vector3((lo.x+hi.x)*0.5,lo.y,(lo.z+hi.z)*0.5)
	var floor_y := 0.0 if m.inside_map(foot) else -0.3
	check(absf(lo.y-floor_y+0.045)<0.003,"Tatsächlicher kompakter Stammfuß ohne Luftspalt: "+label+" y="+str(lo.y))
