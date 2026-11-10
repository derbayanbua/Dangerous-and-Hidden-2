extends RefCounted
## Individueller Detailausbau ausschließlich für Bavaria.
var m: Mission
var lb: LevelBuilder
var t: RefCounted
var foliage: Array[Dictionary] = []
var roof_stand := Vector3.ZERO
var tree_stand := Vector3.ZERO
var tower_base := Vector3.ZERO
var south := Vector3(0.817,0,0.576).normalized()
var border_offsets: Array[float] = []
var border_leaf_mesh: Mesh
var border_leaf_material: Material
var border_leaf_transform := Transform3D.IDENTITY
var border_core_mesh: SphereMesh
var border_core_material: StandardMaterial3D

class SceneLadder extends OrigInteractive.OrigLadder:
	# Zwei Endpunkte benutzen das bestehende Klettern und dessen MP-Bewegungsabgleich.
	func climb(s: Soldier) -> void:
		if s.is_climbing():
			return
		var dest := bottom if at_top else top
		var corner := Vector3(bottom.x,top.y + 0.25,bottom.z)
		s.start_path_climb(s.global_position,corner,dest,absf(top.y-bottom.y)/1.2 + 0.6)
		_rung_sounds(s,absf(top.y-bottom.y)/1.2)
		used.emit(s)

func _init(mission: Mission) -> void:
	m = mission
	lb = m.lb
	t = m._templates

func p(ref: Array, y := 0.0) -> Vector3:
	return m.pixel(ref,y)

func build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.31,0.34,0.32)
	metal.metallic = 0.65
	metal.roughness = 0.65
	lb._mats["old_steel"] = metal
	_tower()
	_sniper_tree()
	_courtyard()
	_meadow_edges()
	_boundary_screen()
	t.ground_vegetation(m)
	_batch_hedges()
	_grass_verges()
	configure_sky(m.env)

func _beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, material: String, collide := false) -> Node3D:
	var n := lb.box(Vector3.ZERO,Vector3(thickness,a.distance_to(b),thickness),material,0,collide,parent)
	n.position = (a+b)*0.5
	# lb.box geometry starts at y=0, center it before orienting the complete body.
	for child in n.get_children():
		if child is Node3D:
			child.position.y -= a.distance_to(b)*0.5
	n.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return n

func _ladder(id: String, bottom: Vector3, top: Vector3, material: String) -> void:
	var height := top.y-bottom.y
	var root := Node3D.new()
	root.name = id + "_Sprossen"
	m.dynamic_root.add_child(root)
	for x in [-0.32,0.32]:
		_beam(root,bottom+Vector3(x,0,0),Vector3(bottom.x+x,top.y+0.5,bottom.z),0.06,material)
	for i in int(height/0.28)+1:
		_beam(root,bottom+Vector3(-0.32,i*0.28,0),bottom+Vector3(0.32,i*0.28,0),0.055,material)
	for upper in [false,true]:
		var ladder := SceneLadder.new()
		ladder.name = id + ("_oben" if upper else "_unten")
		ladder.persistent_id = "bavaria_" + ladder.name
		ladder.bottom = bottom
		ladder.top = top
		ladder.at_top = upper
		ladder.prompt = "Hinunterklettern" if upper else "Hinaufklettern"
		m.dynamic_root.add_child(ladder)
		ladder.global_position = top if upper else bottom
		ladder.add_to_group("bavaria_scene_ladders")

func _tower() -> void:
	var house := m.static_root.get_node("haus_18_shed") as Node3D
	var spec: Dictionary = m.layout["buildings"].filter(func(b): return b.id == "haus_18_shed")[0]
	var w := float(spec.w)*float(m.layout.meters_per_reference_pixel)
	var d := float(spec.d)*float(m.layout.meters_per_reference_pixel)
	var ridge := float(spec.height)+tan(0.37)*(d*0.5+0.4)
	var local_base := Vector3(w*0.5+1.4,0,d*float(spec.get("tower_z_fraction",0.0)))
	tower_base = house.to_global(local_base)
	var support := Node3D.new()
	support.name = "SeitlicherAntennenturm"
	m.dynamic_root.add_child(support)
	support.global_transform = house.global_transform
	# Der gelieferte obere Gittermast ist 3,56 m hoch; neues Unterteil schließt daran an.
	var join_y := ridge-3.56
	for x in [-0.42,0.42]:
		for z in [-0.42,0.42]:
			lb.box(local_base+Vector3(x,-0.05,z),Vector3(0.42,0.22,0.42),"stone",0,true,support)
			_beam(support,local_base+Vector3(x,0.12,z),local_base+Vector3(x,join_y,z),0.085,"old_steel",true)
	for i in int(ceil(join_y/0.8)):
		var y0 := i*0.8+0.12
		var y1 := minf(y0+0.8,join_y)
		for side in [-1.0,1.0]:
			_beam(support,local_base+Vector3(-0.42,y0,side*0.42),local_base+Vector3(0.42,y1,side*0.42),0.045,"old_steel")
			_beam(support,local_base+Vector3(side*0.42,y0,-0.42),local_base+Vector3(side*0.42,y1,0.42),0.045,"old_steel")
	for y in [2.0,4.0,5.8]:
		_beam(support,local_base+Vector3(0,y,0),Vector3(w*0.5-0.1,y,0),0.09,"old_steel")
	var antenna := load("res://assets/maps/bavaria/roof_antenna/roof_hf_antenna.tscn").instantiate() as Node3D
	antenna.name = "BavariaRoofAntenna"
	support.add_child(antenna)
	antenna.position = local_base + Vector3.UP*join_y
	antenna.set_meta("mounted_on","haus_18_shed")
	antenna.set_meta("ground_supported",true)
	antenna.add_to_group("bavaria_roof_antennas")
	for mesh in antenna.find_children("*","MeshInstance3D",true,false):
		mesh.add_to_group("bavaria_antenna_visuals")
	# 11/2026: Es gibt auf dem Dach des Antennenhauses KEINEN Firststeg/Laufpfad.
	# Steg, Übergang und die nur dorthin führende Turmleiter entfallen; Turm und Antenne bleiben (nicht begehbar).
	roof_stand = Vector3.ZERO
	_antenna_platform(support, local_base)
	support.add_to_group("bavaria_towers")

## 11/2026: Antenne per Leiter besteigbar. Steigleiter vor der Außenseite des Gitterturms (mit Haltern
## am Turm), oben eine Gitterplattform mit Geländer rund um den Mast (unterhalb des Antennenmasts, unter dem
## Querträger zur Hauswand). Kein Dachsteg. Klettern über SceneLadder (OrigLadder/start_path_climb, MP-Abgleich).
const ANTENNA_DECK_Y := 3.6
var antenna_stand := Vector3.ZERO

func _antenna_platform(support: Node3D, base: Vector3) -> void:
	var y := ANTENNA_DECK_Y
	var deck := Node3D.new()
	deck.name = "AntennenPlattform"
	support.add_child(deck)
	deck.add_to_group("bavaria_antenna_platform")
	# Gitterrost x −0,9 … +1,3 (Leiterseite außen), z ±1,0; trägt (Kollision), Oberkante = y
	lb.box(base + Vector3(0.2, y - 0.08, 0), Vector3(2.2, 0.08, 2.0), "old_steel", 0, true, deck)
	for z in [-0.95, 0.95]:
		_beam(deck, base + Vector3(-0.9, y - 0.12, z), base + Vector3(1.3, y - 0.12, z), 0.07, "old_steel")
	# Geländer 1,0 m: z-Seiten durchgehend, Außenseite mit Leiteröffnung, Hausseite mit Lücke für den Querträger
	for z in [-1.0, 1.0]:
		lb.box(base + Vector3(0.2, y, z), Vector3(2.2, 1.0, 0.05), "old_steel", 0, true, deck).get_child(1).visible = false
		for k in 6:
			_beam(deck, base + Vector3(-0.9 + k * 0.44, y, z), base + Vector3(-0.9 + k * 0.44, y + 1.0, z), 0.04, "old_steel")
		_beam(deck, base + Vector3(-0.9, y + 1.0, z), base + Vector3(1.3, y + 1.0, z), 0.05, "old_steel")
		_beam(deck, base + Vector3(-0.9, y + 0.5, z), base + Vector3(1.3, y + 0.5, z), 0.035, "old_steel")
	for seg in [[-1.0, -0.4], [0.4, 1.0]]:
		var zc: float = (seg[0] + seg[1]) * 0.5
		var lz: float = seg[1] - seg[0]
		lb.box(base + Vector3(1.3, y, zc), Vector3(0.05, 1.0, lz), "old_steel", 0, true, deck).get_child(1).visible = false
		_beam(deck, base + Vector3(1.3, y + 1.0, seg[0]), base + Vector3(1.3, y + 1.0, seg[1]), 0.05, "old_steel")
	for seg in [[-1.0, -0.2], [0.2, 1.0]]:
		var zc: float = (seg[0] + seg[1]) * 0.5
		var lz: float = seg[1] - seg[0]
		lb.box(base + Vector3(-0.9, y, zc), Vector3(0.05, 1.0, lz), "old_steel", 0, true, deck).get_child(1).visible = false
		_beam(deck, base + Vector3(-0.9, y + 1.0, seg[0]), base + Vector3(-0.9, y + 1.0, seg[1]), 0.05, "old_steel")
	# Steigleiter vor der Außenseite (x = +1,35), Holme/Sprossen im Turm-Bezugssystem, Halter alle 1,2 m
	var lx := 1.35
	for z in [-0.25, 0.25]:
		_beam(deck, base + Vector3(lx, 0.0, z), base + Vector3(lx, y + 1.1, z), 0.05, "old_steel")
	for i in int(y / 0.28) + 1:
		_beam(deck, base + Vector3(lx, i * 0.28 + 0.2, -0.25), base + Vector3(lx, i * 0.28 + 0.2, 0.25), 0.04, "old_steel")
	var hy := 1.0
	while hy < y:
		for z in [-0.25, 0.25]:
			_beam(deck, base + Vector3(lx, hy, z), base + Vector3(0.42, hy, z * 1.6), 0.035, "old_steel")
		hy += 1.2
	var bottom := support.to_global(base + Vector3(lx + 0.45, 0.0, 0.0))
	var top := support.to_global(base + Vector3(0.95, y, 0.0))
	antenna_stand = top
	for upper in [false, true]:
		var ladder := SceneLadder.new()
		ladder.name = "antenne_leiter" + ("_oben" if upper else "_unten")
		ladder.persistent_id = "bavaria_" + ladder.name
		ladder.bottom = bottom
		ladder.top = top
		ladder.at_top = upper
		ladder.prompt = "Hinunterklettern" if upper else "Hinaufklettern"
		m.dynamic_root.add_child(ladder)
		ladder.global_position = top if upper else bottom
		ladder.add_to_group("bavaria_scene_ladders")
		ladder.add_to_group("bavaria_antenna_ladders")

func _sniper_tree() -> void:
	var center := p(m.layout.sniper_tree.pixel)
	var root := t.prop("l_tree",center,0,0.75) as Node3D
	root.name = "SniperBaum"
	root.add_to_group("bavaria_trees")
	root.add_to_group("bavaria_sniper_tree")
	var canopy := root.find_child("koruna",true,false) as MeshInstance3D
	if canopy == null:
		for mesh in root.find_children("*","MeshInstance3D",true,false):
			if mesh.name != "tree":
				canopy = mesh
				break
	# Hängende Original-Laubgruppen, unabhängig von der Stammkollision.
	if canopy:
		var bounds: AABB = t.vertex_bounds(canopy,canopy.transform.affine_inverse())
		for i in 10:
			var angle := TAU*float(i)/10.0
			# Zwei schmale Öffnungen für Blicke/Schüsse, der Rest bleibt ein dichter Laubvorhang.
			var low_skirt := i in [1,6]
			var leaf := MeshInstance3D.new()
			leaf.mesh = canopy.mesh
			leaf.material_override = canopy.material_override
			var holder := Node3D.new()
			m.dynamic_root.add_child(holder)
			holder.position = center+Vector3(cos(angle)*3.2,0.3,sin(angle)*3.2)
			holder.scale = Vector3(3.0/maxf(bounds.size.x,0.1),(3.0 if low_skirt else 5.5)/maxf(bounds.size.y,0.1),3.0/maxf(bounds.size.z,0.1))
			holder.add_child(leaf)
			leaf.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			holder.add_to_group("bavaria_ground_foliage")
			holder.set_meta("foliage_index",foliage.size())
			foliage.append({"center":center+Vector3(cos(angle)*3.2,1.8 if low_skirt else 3.0,sin(angle)*3.2),"radius":Vector3(1.5,1.4 if low_skirt else 2.7,1.5)})
	var wood := Node3D.new()
	wood.name = "Aststand"
	m.dynamic_root.add_child(wood)
	wood.position = center
	lb.cylinder(Vector3.ZERO,0.45,4.5,"darkwood",true,wood)
	lb.box(Vector3(1.3,3.32,0.8),Vector3(2.4,0.18,2.4),"wood",0,true,wood)
	for offset in [Vector3(-0.2,2.0,0),Vector3(0.3,1.5,-0.2)]:
		_beam(wood,offset,Vector3(2.1,3.3,1.6),0.18,"darkwood",true)
	tree_stand = center+Vector3(1.3,3.55,0.8)
	_ladder("Baumleiter",center+Vector3(2.3,0.05,0.8),tree_stand,"darkwood")
	# Einzelbaum wird nicht mit dem allgemeinen Wald vereinigt.
	root.remove_from_group("bavaria_trees")
	m._placed.append({"pos":center,"radius":8.0})

func blocks_sight(a: Vector3, b: Vector3) -> bool:
	for volume in foliage:
		var start: Vector3 = (a-volume.center)/volume.radius
		var end: Vector3 = (b-volume.center)/volume.radius
		var dir := end-start
		var nearest := start+dir*clampf(-start.dot(dir)/maxf(dir.length_squared(),0.00001),0,1)
		if nearest.length_squared() < 0.85:
			return true
	return false

func _segment(a: Array, b: Array, width: float, mat: String, y := 0.04) -> void:
	var from := p(a)
	var to := p(b)
	var delta := to-from
	lb.box((from+to)*0.5+Vector3.UP*y,Vector3(delta.length(),0.025,width),mat,atan2(-delta.z,delta.x),false)

func _hedge(a: Array, b: Array, height: float, width := 1.7) -> void:
	var from := p(a)
	var to := p(b)
	var count := maxi(int(from.distance_to(to)/2.0),1)
	for i in count:
		var pos := from.lerp(to,(float(i)+0.5)/count)
		if not m.woodland_clearance(pos,width+0.6):
			continue
		var shrub := t.prop("l_tree4",pos, float(i)*1.7,0.25) as Node3D
		if shrub:
			var bounds: AABB = t.mesh_bounds(shrub,Transform3D.IDENTITY)
			shrub.scale *= Vector3(width/maxf(bounds.size.x,0.1),height/maxf(bounds.size.y,0.1),width*1.8/maxf(bounds.size.z,0.1))
			shrub.add_to_group("bavaria_hedges")
			foliage.append({"center":pos+Vector3.UP*height*0.5,"radius":Vector3(width,height*0.48,width)})

func _greenhouse(ref: Array, w: float, d: float, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Gewaechshaus"
	m.static_root.add_child(root)
	root.position = p(ref)
	root.rotation.y = yaw
	root.add_to_group("bavaria_greenhouses")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.28,0.35,0.32,0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.25
	lb._mats["old_glass"] = glass
	for x in [-w*0.5,w*0.5]:
		for z in [-d*0.5,d*0.5]:
			_beam(root,Vector3(x,0,z),Vector3(x,2.0,z),0.09,"darkwood")
	for i in int(w/1.7)+1:
		var x := -w*0.5+float(i)*w/int(w/1.7)
		for side in [-1.0,1.0]:
			_beam(root,Vector3(x,0,side*d*0.5),Vector3(x,2.0,side*d*0.5),0.055,"darkwood")
			_beam(root,Vector3(x,2.0,side*d*0.5),Vector3(x,3.0,0),0.055,"darkwood")
			# Einzelne fehlende Scheiben; Glas rein optisch, Schüsse bleiben möglich.
			if i%4 != 2:
				lb.box(Vector3(x,0.35,side*d*0.5),Vector3(1.5,1.55,0.018),"old_glass",0,false,root)
	for side in [-1.0,1.0]:
		_beam(root,Vector3(-w*0.5,2,side*d*0.5),Vector3(w*0.5,2,side*d*0.5),0.07,"darkwood")
		var panel := lb.box(Vector3(0,2.50,side*d*0.25),Vector3(w-0.2,0.018,sqrt(d*d*0.25+1.0)),"old_glass",0,false,root)
		panel.rotation.x = atan(2.0/d)*side
	_beam(root,Vector3(-w*0.5,3,0),Vector3(w*0.5,3,0),0.08,"darkwood")
	lb.box(Vector3(0,0.02,0),Vector3(w-0.6,0.07,d-0.8),"earth",0,false,root)

func _gate(a: Array, b: Array) -> void:
	var from := p(a)
	var to := p(b)
	var root := Node3D.new()
	root.name = "Gartentor"
	m.static_root.add_child(root)
	root.add_to_group("bavaria_gates")
	for pos in [from,to]:
		lb.cylinder(pos,0.07,1.5,"old_steel",true,root)
	# Offenes Tor seitlich: der Durchgang bleibt tatsächlich passierbar.
	var offset := Vector3(0,0,1.7)
	for y in [0.3,1.35]:
		_beam(root,from+Vector3.UP*y,from+offset+Vector3.UP*y,0.04,"old_steel")
	for i in 7:
		_beam(root,from+offset*(i/6.0)+Vector3.UP*0.3,from+offset*(i/6.0)+Vector3.UP*1.35,0.018,"old_steel")

func _courtyard() -> void:
	# Gemeinsam sichtbare Hofobjekte, keine Duplikate pro Kamera.
	# Garten: ein langes Gewächshaus (8 m; länger ragt in garden_barn) statt eines kleinen
	_greenhouse([666,902],8.0,3.6,-0.03)
	_greenhouse([560,1051],13*m.layout_scale(),4.5*m.layout_scale(),-0.03)
	_gate([542,907],[551,916])
	_hedge([672,972],[747,1030],2.2)
	_hedge([557,778],[530,817],3.0,2.0)
	_segment([527,884],[559,974],2.0,"earth")
	_segment([559,974],[617,1090],1.4,"stone")
	# Niedrige alte Beeteinfassungen und Materialplätze statt moderner Maschinen.
	for i in 3:
		var center := p([575+i*15,910+i*7])
		lb.box(center,Vector3(6.5*m.layout_scale(),0.12,2.8*m.layout_scale()),"earth",0,false)
		for side in [-1.0,1.0]:
			lb.box(center+Vector3(0,0,side*1.5*m.layout_scale()),Vector3(6.8*m.layout_scale(),0.35,0.18),"stone",0,true)
	for i in 7:
		lb.box(p([528,866],i*0.09),Vector3(2.4*m.layout_scale(),0.08,1.4*m.layout_scale()),"stone",0,true)
	for pair in [["ja_drevo",[551,950]],["k_barelmir3",[530,881]],["e_bucket",[550,921]],["e_wuchar",[650,991]]]:
		t.prop(pair[0],p(pair[1]),0,1.0,pair[0] in ["ja_drevo","k_barelmir3"])
	# Gartenfassaden der Häuserzeilen: schmale überdeckte Laubengänge, keine Zugänge vortäuschen.
	for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		if not String(house.name).begins_with("reihe_") or house.is_in_group("bavaria_ruins"):
			continue
		var box: AABB = house.get_node("CompleteBuildingVisual").get_aabb()
		var w := box.size.x
		var d := box.size.z-0.8
		for x in [-w*0.35,0.0,w*0.35]:
			_beam(house,Vector3(x,0,d*0.5+1.8),Vector3(x,5.8,d*0.5+1.8),0.13,"darkwood")
		lb.box(Vector3(0,3.0,d*0.5+1.0),Vector3(w-0.2,0.18,1.9),"wood",0,false,house)
		lb.box(Vector3(0,5.8,d*0.5+1.0),Vector3(w+0.15,0.14,2.3),"roof",0,false,house)
		for x in range(int(w/0.6)):
			lb.box(Vector3(-w*0.5+0.3+x*0.6,3.17,d*0.5+1.8),Vector3(0.06,0.85,0.07),"darkwood",0,false,house)
		# Neue Bauteile wieder mit vollständiger Hausdarstellung verbinden.
		t.merge_building_visuals(house)
	# Verputzte Hofwand: Regenfallrohr, dunkler Sockel, schmaler Steinweg.
	var house := m.static_root.get_node("haus_18_shed") as Node3D
	var size: Vector2 = house.get_meta("footprint_size")
	_beam(house,Vector3(-size.x*0.45,0,size.y*0.5+0.16),Vector3(-size.x*0.45,6,size.y*0.5+0.16),0.09,"old_steel")
	lb.box(Vector3(0,0,size.y*0.5+0.12),Vector3(size.x,0.35,0.25),"stone",0,false,house)
	t.merge_building_visuals(house)

func _meadow_edges() -> void:
	_hedge([380,530],[720,218],2.8,2.3)
	_hedge([757,277],[907,454],2.7,2.3)
	_hedge([895,472],[624,746],2.0,1.8)
	# Zwei Fahrspuren parallel zum rechten Wiesenrand.
	for offset in [-2.0,2.0]:
		_segment([584+offset,731],[845+offset,458],0.55,"earth")
	# Verwitterter kleiner Schuppen am Wiesenrand; Randobjekt, kein 25. Wohnhaus.
	var hut := lb.building(p([853,475]),7,4,2.7,"wood","slate",[],false,0,[["s",0,1.7]])
	hut.name = "Wiesenhuette"
	hut.add_to_group("bavaria_aux_houses")
	hut.set_meta("footprint_size",Vector2(7,4))
	for i in 44:
		var ref := [385+i*7.1,527-i*6.4]
		if not m.woodland_clearance(p(ref),1.0):
			continue
		var grass := t.prop("l_tree4",p(ref),i*0.8,0.06) as Node3D
		if grass:
			grass.scale.y *= 0.7

func _border_bush(pos: Vector3, yaw: float, height: float, parent: Node3D) -> Node3D:
	if border_leaf_mesh == null:
		var sample := t.prop("l_tree4",Vector3.ZERO,0,1.0) as Node3D
		var crown := sample.find_child("Rectangle05",true,false) as MeshInstance3D
		border_leaf_mesh = crown.mesh
		border_leaf_material = crown.material_override
		border_leaf_transform = crown.global_transform
		sample.visible = false
	var root := Node3D.new()
	root.name = "DichtesRandgebuesch"
	parent.add_child(root)
	var leaf := MeshInstance3D.new()
	leaf.mesh = border_leaf_mesh
	leaf.material_override = border_leaf_material
	root.add_child(leaf)
	leaf.transform = border_leaf_transform
	var bounds := leaf.transform*leaf.get_aabb()
	var actual: AABB = t.vertex_bounds(leaf,Transform3D.IDENTITY)
	bounds.position.y = actual.position.y
	bounds.size.y = actual.size.y
	leaf.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	root.scale = Vector3(4.6/bounds.size.x,height/bounds.size.y,2.4/bounds.size.z)
	root.rotation.y = yaw
	root.position = pos
	# Deckender innerer Laubkörper schließt die großen transparenten Zwischenräume
	# der alten Blattkarten; außen bleiben die Originalblätter sichtbar.
	if border_core_mesh == null:
		border_core_mesh = SphereMesh.new()
		border_core_mesh.radius = 1.0
		border_core_mesh.height = 2.0
		border_core_mesh.radial_segments = 8
		border_core_mesh.rings = 4
		border_core_material = StandardMaterial3D.new()
		border_core_material.albedo_color = Color(0.18,0.24,0.10)
		border_core_material.roughness = 1.0
		var noise := FastNoiseLite.new()
		noise.frequency = 0.15
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.noise = noise
		var colors := Gradient.new()
		colors.set_color(0,Color(0.09,0.14,0.045))
		colors.set_color(1,Color(0.30,0.37,0.15))
		texture.color_ramp = colors
		border_core_material.albedo_color = Color.WHITE
		border_core_material.albedo_texture = texture
		border_core_material.uv1_triplanar = true
		border_core_material.uv1_world_triplanar = true
		border_core_material.uv1_scale = Vector3.ONE*0.75
	var core := MeshInstance3D.new()
	core.mesh = border_core_mesh
	core.material_override = border_core_material
	root.add_child(core)
	core.global_transform = Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(Vector3(2.3,height*0.46,1.2)),pos+Vector3.UP*(height*0.45))
	root.add_to_group("bavaria_exterior_foliage")
	root.add_to_group("bavaria_ground_foliage")
	return root

func _boundary_screen() -> void:
	# Sichtschutz außerhalb der unveränderten festen Grenze. Keine neuen Spielflächen/Collider.
	var center := Vector2.ZERO
	for point in m.boundary:
		center += point
	center /= m.boundary.size()
	var root := Node3D.new()
	root.name = "AeussereRandkulisse"
	m.dynamic_root.add_child(root)
	root.add_to_group("bavaria_boundary_screen")
	for edge in m.boundary.size():
		var a: Vector2 = m.boundary[edge]
		var b: Vector2 = m.boundary[(edge+1)%m.boundary.size()]
		var dir := (b-a).normalized()
		var outward := Vector2(-dir.y,dir.x)
		if outward.dot((a+b)*0.5-center)<0:
			outward = -outward
		var yaw := atan2(-dir.y,dir.x)
		var count := int(ceil(a.distance_to(b)/3.2))
		for i in count:
			var along := a.lerp(b,(float(i)+0.5)/count)
			for row in 2:
				var pos := along+dir*(row*1.5)+outward*(3.3+row*2.5)
				var hedge := _border_bush(Vector3(pos.x,-0.25,pos.y),yaw,3.5+0.6*sin(i*1.9+edge),root)
				_measure_border(hedge,a,outward)
			if i%5==2:
				var pos := along+outward*8.0
				var tree := t.prop("l_tree" if i%2==0 else "l_tree2",Vector3(pos.x,-0.25,pos.y),0,0.8) as Node3D
				var bounds: AABB = t.mesh_bounds(tree,Transform3D.IDENTITY)
				tree.scale *= Vector3(6.0/maxf(bounds.size.x,0.1),(9.0+i%3)/maxf(bounds.size.y,0.1),6.0/maxf(bounds.size.z,0.1))
				tree.rotation.y = yaw
				tree.reparent(root,true)
				tree.add_to_group("bavaria_exterior_foliage")
				_measure_border(tree,a,outward)
		# Einzelne Häuser hinter dem nahen Hecken-/Gebüschsaum, nicht als starre Häuserwand.
		for fraction in [0.24,0.72]:
			var pos := a.lerp(b,fraction)+outward*9.0
			var house := lb.building(Vector3(pos.x,-0.25,pos.y),16,12,6,"plaster","roof",[],true,yaw)
			house.name = "Randhaus_"+str(edge)+"_"+str(fraction)
			house.add_to_group("bavaria_aux_houses")
			house.set_meta("footprint_size",Vector2(16,12))
			house.reparent(root,true)
			for body in house.find_children("*","StaticBody3D",true,false):
				body.collision_layer = 0
				body.collision_mask = 0
			_measure_border(house,a,outward)
			t.merge_building_visuals(house,"bavaria_border_house_visuals")

func _measure_border(node: Node3D, a: Vector2, outward: Vector2) -> void:
	var closest := INF
	# Tatsächliche transformierte Mesh-Bounds prüfen, nicht nur die Modellursprünge.
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var box: AABB = mesh.get_aabb()
		for index in 8:
			var point: Vector3 = mesh.global_transform*box.get_endpoint(index)
			closest = minf(closest,(Vector2(point.x,point.z)-a).dot(outward))
	border_offsets.append(closest)

func _batch_hedges() -> void:
	# Hecken bleiben auch über die vergrößerte Wiese als zusammenhängender Saum sichtbar.
	var batches := {}
	var sources: Array[MeshInstance3D] = []
	for hedge in m.get_tree().get_nodes_in_group("bavaria_hedges"):
		for mesh in hedge.find_children("*","MeshInstance3D",true,false):
			var key := str(mesh.mesh.get_instance_id())+":"+str(mesh.material_override.get_instance_id() if mesh.material_override else 0)
			if not batches.has(key):
				batches[key] = {"mesh":mesh.mesh,"material":mesh.material_override,"transforms":[]}
			batches[key].transforms.append(mesh.global_transform)
			sources.append(mesh)
	for data in batches.values():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = data.mesh
		batch.instance_count = data.transforms.size()
		for i in batch.instance_count:
			batch.set_instance_transform(i,data.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "HeckensaumInstanzen"
		visual.multimesh = batch
		visual.material_override = data.material
		visual.add_to_group("bavaria_hedge_batches")
		m.static_root.add_child(visual)
	for mesh in sources:
		mesh.free()

func _grass_verges() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Drei schmale gekreuzte Halme pro Büschel, keine Alpha-Flächen oder Physikkollision.
	for i in 3:
		var rot := Basis(Vector3.UP,i*PI/3.0)
		for v in [Vector3(-0.022,0,0),Vector3(0.022,0,0),Vector3(0.055,0.48,0.04)]:
			st.set_normal(rot*Vector3.FORWARD)
			st.add_vertex(rot*v)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34,0.40,0.18)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh.surface_set_material(0,material)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = 2200
	var rng := RandomNumberGenerator.new()
	rng.seed = 4724
	var planted := 0
	for i in batch.instance_count:
		var pos: Vector3
		if i < 1600:
			var f := rng.randf()
			var a := Vector2(382,530).lerp(Vector2(728,213),f) if i%2==0 else Vector2(895,475).lerp(Vector2(621,748),f)
			pos = p([a.x+rng.randf_range(-5,5),a.y+rng.randf_range(-5,5)],0.025)
		else:
			var c := p(m.layout.sniper_tree.pixel)
			pos = c+Vector3(rng.randf_range(-8,8),0.025,rng.randf_range(-8,8))
		if not m.woodland_clearance(pos,0.4):
			continue
		var scale_value := rng.randf_range(0.5,1.3)
		batch.set_instance_transform(planted,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),pos))
		batch.set_instance_color(planted,Color(rng.randf_range(0.8,1.1),rng.randf_range(0.85,1.1),0.8))
		planted += 1
	batch.visible_instance_count = planted
	var visual := MultiMeshInstance3D.new()
	visual.name = "Grasraender"
	visual.multimesh = batch
	m.static_root.add_child(visual)

const PANORAMA := "res://assets/maps/bavaria/south_alps_reference.png"   # optional (nicht im Repository)

func configure_sky(e: Environment) -> void:
	if not ResourceLoader.exists(PANORAMA):
		return   # ohne Panorama: normaler Missionshimmel (ProceduralSky + sky_fx)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/maps/bavaria/alps_sky.gdshader")
	mat.set_shader_parameter("panorama",load(PANORAMA))
	mat.set_shader_parameter("south_direction",south)
	mat.set_shader_parameter("panorama_repeats",3.0)
	e.sky = Sky.new()
	e.sky.sky_material = mat
	e.fog_light_color = Color(0.30,0.34,0.47)
	e.fog_density = 0.0018
	e.fog_sky_affect = 0.12
	e.volumetric_fog_density = 0.00018



