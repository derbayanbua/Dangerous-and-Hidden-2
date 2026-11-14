extends RefCounted
## Austauschbare historische Einrichtung; Geometrie/Netzregeln/Licht bleiben beim Hausgenerator.
var m: Mission
var t: RefCounted
var rooms: Array[Node3D] = []
var furnishings: Array[Node3D] = []
var removed_old_pairs := 0
var rejected := 0
var active_house: Node3D
var protected: Array[Rect2] = []
var occupied: Array[Rect2] = []
var house_size := Vector2.ZERO
var corridor_half := 1.0

func build(mission: Mission) -> void:
	m = mission
	t = m._templates
	var house_index := 0
	for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		if not house.get_meta("interior_partitioned",false):
			continue
		active_house = house
		house_size = house.get_meta("footprint_size")
		corridor_half = float(house.get_meta("corridor_half_width",1.0))
		_remove_old_table_pair(house)
		_protect_routes(house)
		var holder := Node3D.new()
		holder.name = "Einrichtung_"+String(house.name)
		m.static_root.add_child(holder)
		holder.global_transform = house.global_transform
		holder.add_to_group("bavaria_furnished_houses")
		holder.set_meta("house",String(house.name))
		var stairs := house.is_in_group("bavaria_stair_houses")
		if house.has_meta("plan_rooms"):
			_plan_house(holder,house,house_index)
			house_index += 1
			continue
		if house_size.y<6.4:
			_wide_room(holder,_room_rect(-1.0,0),-1.0)
			_wide_room(holder,_room_rect(1.0,0),1.0)
			house_index += 1
			continue
		var roles := ["Wohnen","Schlafen","Kueche","Arbeiten","Essen","Schlafen"] if house_size.x<8.3 else ["Schlafen","Essen","Kueche","Wohnen","Schlafen","Vorrat"]
		if house_index%2==1:
			roles[0] = "Arbeiten" if roles[0]=="Wohnen" else "Schlafen"
		if house_size.y/3.0-0.4<2.14:
			roles[0] = "Wohnen"
			roles[1] = "Schlafen"
		for side in [-1.0,1.0]:
			for row in 3:
				if stairs and side>0:
					continue
				var rect := _room_rect(side,row)
				var index := row+(3 if side>0 else 0)
				_room(holder,rect,0.06,String(roles[index]),side,row,house_index)
		if stairs:
			# Rechts bleibt der echte Treppenraum frei; links im zugänglichen OG drei Nutzbereiche.
			for row in 3:
				var upper_roles := ["Schlafen","Arbeiten","Vorrat"] if house_size.y/3.0-0.4>=2.14 else ["Arbeiten","Schlafen","Vorrat"]
				_room(holder,_room_rect(-1.0,row),3.18,upper_roles[row],-1.0,row,house_index)
			var coat := _new_room(holder,Rect2(1.2,house_size.y*0.5-1.5,house_size.x*0.5-1.5,1.2),0.06,"Treppenhaus")
			_prop(coat,"e_hanger",Vector3(house_size.x*0.5-0.6,0.06,house_size.y*0.5-0.6),0,1.0,false,"Garderobe")
		house_index += 1
	print("BAVARIA INTERIORS: ",house_index," Häuser, ",rooms.size()," Nutzräume/-bereiche, ",furnishings.size()," Einrichtungsobjekte; alte Einzelmöbel ersetzt=",removed_old_pairs," verworfene Stellversuche=",rejected)

## Haus 16: Räume nach Grundriss (house16_plan.plan_rooms), Einrichtung mit denselben Platzierungsregeln.
func _plan_house(holder: Node3D,house: Node3D,house_index: int) -> void:
	for spec in house.get_meta("plan_rooms"):
		var rect: Rect2 = spec.rect
		var role: String = spec.role
		if role=="Bad":
			var room := _new_room(holder,rect,0.06,"WC_Bad")
			_prop(room,"m_af5_vana01",Vector3(rect.position.x+0.45,0.06,rect.get_center().y),PI*0.5,1.0,true,"Badewanne")
			_prop(room,"m_af5_zachod01",Vector3(rect.end.x-0.30,0.06,rect.position.y+0.32),0,1.0,true,"Abort")
			_prop(room,"m_af5_umyv01",Vector3(rect.end.x-0.22,0.06,rect.end.y-0.45),-PI*0.5,1.0,true,"Waschbecken")
			_prop(room,"e_bucket",Vector3(rect.get_center().x,0.06,rect.position.y+0.25),0,0.9,false,"Eimer")
			continue
		var side: float = spec.side
		_room(holder,rect,0.06,role,side,1,house_index)
		var room: Node3D = rooms[-1]
		if role=="Wohnen":
			# Stubentisch mit Stühlen und Herrgottswinkel-Bild in der Wohnzimmermitte, Fensterwege frei.
			var table_pos := Vector3(rect.get_center().x+0.4,0.06,rect.get_center().y-0.2)
			var stube := _prop(room,"e_ktable",table_pos,0,0.773,true,"Stubentisch")
			if stube:
				for dx in [-0.85,0.85]:
					_prop(room,"e_chair",table_pos+Vector3(dx,0,0),-PI*0.5 if dx<0 else PI*0.5,0.78,true,"Holzstuhl")
				_prop(room,"e_flaska2",table_pos+Vector3(0,0.785,0),0,0.7,false,"Krug",stube)
			_prop(room,"e_wcase",Vector3(rect.end.x-0.35,0.06,rect.end.y-0.62),-PI*0.5,1.0,true,"Wohnzimmerschrank")
		elif role=="Kueche":
			var table_pos := Vector3(rect.get_center().x+0.5,0.06,rect.end.y-1.25)
			var ktisch := _prop(room,"e_ktable",table_pos,PI*0.5,0.773,true,"Kuechentisch")
			if ktisch:
				_prop(room,"e_chair",table_pos+Vector3(0,0,-0.95),PI,0.78,true,"Holzstuhl")
				_prop(room,"e_kicpot",table_pos+Vector3(0.2,0.785,0),0,0.6,false,"Topf",ktisch)
			_prop(room,"e_boiler",Vector3(rect.position.x+0.35,0.06,rect.end.y-0.40),PI*0.5,0.8,true,"Wasserkessel")
	# OG wie bisher: drei Nutzbereiche im zugänglichen linken Obergeschoss
	for row in 3:
		var upper_roles := ["Schlafen","Arbeiten","Vorrat"]
		_room(holder,_room_rect(-1.0,row),3.18,upper_roles[row],-1.0,row,house_index)
	var coat := _new_room(holder,Rect2(1.2,house_size.y*0.5-1.5,house_size.x*0.5-1.5,1.2),0.06,"Treppenhaus")
	_prop(coat,"e_hanger",Vector3(house_size.x*0.5-0.6,0.06,house_size.y*0.5-0.6),0,1.0,false,"Garderobe")

func _remove_old_table_pair(house: Node3D) -> void:
	# Die Vorlage stellte bisher ein einzelnes untergroßes Tisch-/Stuhlpaar ohne Raumbezug hin.
	# Nur diese beiden Modelltypen innerhalb dieses Hauses entfernen, keine Außenmöbel anfassen.
	for child in m.static_root.get_children():
		if not child is Node3D:
			continue
		var local: Vector3 = house.to_local(child.global_position)
		var is_template_pair := local.distance_to(Vector3(-house_size.x*0.32,0.12,0))<0.025 or local.distance_to(Vector3(-house_size.x*0.32,0.12,0.9))<0.025
		if is_template_pair:
			child.free()
			removed_old_pairs += 1
			t.reused_models -= 1

func _protect_routes(house: Node3D) -> void:
	protected.clear()
	# Mittelflur mit Soldaten-/Bewegungsabstand, einschließlich beider Haustüren.
	protected.append(Rect2(-corridor_half-0.34,-house_size.y*0.5,(corridor_half+0.34)*2,house_size.y))
	for z in ([0.0] if house_size.y<6.4 else [-house_size.y/3.0,0.0,house_size.y/3.0]):
		protected.append(Rect2(-corridor_half-0.54,z-0.43,(corridor_half+0.54)*2,0.86))
	for window in house.get_meta("shooting_windows",[])+house.get_meta("og_shooting_windows",[]):
		var side := signf(window.z)
		var z: float = window.z-side*1.4
		protected.append(Rect2(window.x-0.36,minf(z,window.z)-0.36,0.72,absf(window.z-z)+0.72))
	for entry in house.get_meta("entry_points",[]):
		var point: Vector3 = entry.point
		var inward: Vector3 = point-entry.normal*2.2
		var rect := Rect2(Vector2(point.x,point.z),Vector2.ZERO).expand(Vector2(inward.x,inward.z))
		protected.append(rect.grow(0.48))
	if house.is_in_group("bavaria_stair_houses"):
		var stairs: Array = house.get_meta("stair_path",[])
		if not stairs.is_empty():
			var rect := Rect2(stairs[0].x,stairs[0].z,0,0)
			for point in stairs:
				rect = rect.expand(Vector2(point.x,point.z))
			protected.append(rect.grow(0.85))

func _room_rect(side: float,row: int) -> Rect2:
	var x0 := -house_size.x*0.5+0.23 if side<0 else corridor_half+0.13
	var x1 := -corridor_half-0.13 if side<0 else house_size.x*0.5-0.23
	var count := 1.0 if house_size.y<6.4 else 3.0
	var z0 := -house_size.y*0.5+row*house_size.y/count+0.20
	var z1 := -house_size.y*0.5+(row+1)*house_size.y/count-0.20
	return Rect2(x0,z0,x1-x0,z1-z0)

func _wide_room(holder: Node3D,rect: Rect2,side: float) -> void:
	# Flache Hofhäuser besitzen einen zusammenhängenden Raum je Seite statt drei Streifen.
	var room := _new_room(holder,rect,0.06,"Wohnschlafen" if side<0 else "Wohnkueche")
	var outer := rect.position.x if side<0 else rect.end.x
	var inner := rect.end.x if side<0 else rect.position.x
	var facing := PI*0.5 if side<0 else -PI*0.5
	if side<0:
		_bed(room,Vector3(outer+0.51,0.06,-0.48),rect)
		_prop(room,"e_wcase",Vector3(outer+0.95,0.06,rect.end.y-0.52),0,1,true,"Kleiderschrank")
	else:
		var cabpos := Vector3(outer-0.95,0.06,rect.end.y-0.38)
		var stove_pos := Vector3(outer-3.35,0.06,rect.end.y-0.38)
		var stove := _prop(room,"e_gstove",stove_pos,PI,0.90,true,"HistorischerHerd")
		_prop(room,"e_kacbnt",cabpos,PI,0.84,true,"Kuechenschrank")
		if stove:
			_prop(room,"e_kicpot",stove_pos+Vector3.UP*0.88,0,0.65,false,"Emailletopf",stove)
	var tablepos := Vector3(inner+side*2.07,0.06,0)
	var table := _prop(room,"e_ktable",tablepos,PI*0.5,0.773,true,"Arbeitstisch" if side<0 else "Esstisch")
	if table:
		for z in [-1.15,1.15]:
			_prop(room,"e_chair",Vector3(tablepos.x,0.06,z),PI if z<0 else 0,0.78,true,"Holzstuhl")
		_papers(room,tablepos+Vector3(0,0.788,0.12))
	if side<0:
		var shelf := _prop(room,"e_shelvs",Vector3(-3.60,0.06,rect.position.y+0.32),0,0.82,true,"Holzregal")
		if shelf:
			_books(shelf)
	_picture(room,rect,side,0.06)
	_wall_shelf(room,Vector3(outer-side*0.17,2.18,0),side)

func _new_room(holder: Node3D,rect: Rect2,floor_y: float,role: String) -> Node3D:
	var n := Node3D.new()
	n.name = ("OG_" if floor_y>1 else "EG_")+role+"_"+str(rooms.size())
	holder.add_child(n)
	n.add_to_group("bavaria_furnished_rooms")
	n.set_meta("house",String(active_house.name))
	n.set_meta("room_rect",rect)
	n.set_meta("floor_height",floor_y)
	n.set_meta("role",role)
	rooms.append(n)
	occupied.clear()
	return n

func _room(holder: Node3D,rect: Rect2,floor_y: float,role: String,side: float,row: int,index: int) -> void:
	var room := _new_room(holder,rect,floor_y,role)
	var outer := rect.position.x if side<0 else rect.end.x
	var z := rect.get_center().y
	var facing := PI*0.5 if side<0 else -PI*0.5
	if role=="Schlafen":
		_bed(room,Vector3(outer-side*0.51,floor_y,z),rect)
		_prop(room,"e_wcase",Vector3(rect.get_center().x,floor_y,rect.position.y+0.51),0,1.0,true,"Kleiderschrank")
	elif role in ["Essen","Arbeiten"]:
		var shallow := rect.size.y<1.75
		var table_pos := Vector3(outer-side*(0.86 if shallow else 0.50),floor_y,z)
		var table := _prop(room,"e_ktable",table_pos,0 if shallow else PI*0.5,0.773,true,"Esstisch" if role=="Essen" else "Arbeitstisch")
		if table:
			if shallow:
				_prop(room,"e_chair",Vector3(outer-side*2.12,floor_y,z),facing+PI,0.78,true,"Holzstuhl")
			elif rect.size.x<2.2:
				for dz in [-1.16,1.16] if role=="Essen" else [1.16]:
					_prop(room,"e_chair",Vector3(outer-side*0.50,floor_y,z+dz),PI if dz<0 else 0,0.78,true,"Holzstuhl")
			else:
				for dz in [-0.70,0.70] if role=="Essen" else [0.70]:
					_prop(room,"e_chair",Vector3(outer-side*1.34,floor_y,z+dz),facing+PI,0.78,true,"Holzstuhl")
			_prop(room,"e_flaska1",table_pos+Vector3(0,0.785,-0.32),0,0.72,false,"Glasflasche",table)
			_papers(room,table_pos+Vector3(0,0.788,0.15))
	elif role=="Kueche":
		var cabinet_pos := Vector3(outer-side*0.38,floor_y,z+0.58)
		var cooker_pos := Vector3(outer-side*0.38,floor_y,z-0.91)
		var kitchen_yaw := facing
		if rect.size.y<2.9 and rect.size.x>3.2:
			cabinet_pos = Vector3(outer-side*1.0,floor_y,rect.position.y+0.38)
			cooker_pos = Vector3(outer-side*(3.5 if rect.size.x>5.0 else 2.5),floor_y,rect.position.y+0.38)
			kitchen_yaw = 0.0
		elif rect.size.y<2.9:
			# Schmale Küche: Hochschrank an innerer Querwand, Herd längs an Außenwand.
			cabinet_pos = Vector3(outer-side*1.0,floor_y,rect.position.y+0.34)
			cooker_pos = Vector3(outer-side*0.38,floor_y,z+0.35)
		var cabinet_yaw := 0.0 if rect.size.y<2.9 else kitchen_yaw
		var cabinet := _prop(room,"e_kacbnt",cabinet_pos,cabinet_yaw,0.84,true,"Kuechenschrank")
		var cooker := _prop(room,"e_gstove",cooker_pos,kitchen_yaw,0.90,true,"HistorischerHerd")
		if cooker:
			_prop(room,"e_kicpot",cooker_pos+Vector3.UP*0.88,0,0.65,false,"Emailletopf",cooker)
		if cabinet:
			_prop(room,"e_flaska1",cabinet_pos+Vector3.UP*0.88,0,0.72,false,"Vorratsflasche",cabinet)
	elif role=="Vorrat":
		var shelf := _prop(room,"e_shelvs",Vector3(outer-side*0.32,floor_y,z),facing,0.82,true,"Holzregal")
		if shelf:
			_books(shelf)
		_prop(room,"e_repbox",Vector3(rect.get_center().x,floor_y,rect.position.y+0.30),0,0.75,true,"Schubladenschrank")
	else:
		_prop(room,"e_armch2",Vector3(outer-side*0.55,floor_y,z+0.40),facing,0.88,true,"Lesesessel")
		_prop(room,"k_g_kamna",Vector3(outer-side*0.42,floor_y,z-0.92),0,1.0,true,"Kanonenofen")
		_side_table(room,Vector3(outer-side*0.52,floor_y,z-0.25))
	_picture(room,rect,side,floor_y)
	_wall_shelf(room,Vector3(outer-side*0.17,floor_y+2.12,z),side)
	# Ein kleiner Koffer/Truhenersatz nur, wenn der freie Raum wirklich übrig bleibt.
	if index%3==0 and role in ["Schlafen","Vorrat"]:
		_prop(room,"e_repbox",Vector3(rect.get_center().x,floor_y,rect.end.y-0.28),PI,0.65,true,"Alltagsschrank")

func _fits(room: Node3D,bounds: AABB,large: bool) -> bool:
	var rect: Rect2 = room.get_meta("room_rect")
	var footprint := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
	if not rect.grow(0.035).encloses(footprint):
		return false
	if large:
		for reserved in protected:
			if footprint.intersects(reserved):
				return false
		for previous in occupied:
			if footprint.grow(0.02).intersects(previous):
				return false
	return true

const WALL_ITEMS := ["GerahmtesLandschaftsbild"]

func _prop(room: Node3D,model: String,pos: Vector3,yaw: float,scale_value: float,large: bool,label: String,support: Node3D = null) -> Node3D:
	var n: Node3D = t.prop(model,Vector3.ZERO,0,scale_value,false)
	if n==null:
		return null
	n.reparent(room,false)
	n.position = pos
	n.rotation.y = yaw
	var bounds: AABB = t.mesh_bounds(n,Transform3D.IDENTITY)
	# 11/2026: Bodenkontakt/Auflage nach echten Mesh-Grenzen statt fester Höhen (schwebend/versunken behoben).
	var floor_y := float(room.get_meta("floor_height",0.06))
	var on_floor := pos.y < floor_y+0.2
	if on_floor and label not in WALL_ITEMS:
		n.position.y += floor_y-bounds.position.y
		bounds = t.mesh_bounds(n,Transform3D.IDENTITY)
	elif support != null and is_instance_valid(support):
		var sb: AABB = support.get_meta("bounds",t.mesh_bounds(support,Transform3D.IDENTITY))
		n.position.y += sb.end.y-bounds.position.y
		bounds = t.mesh_bounds(n,Transform3D.IDENTITY)
	if on_floor and not large and label not in WALL_ITEMS:
		# Kleinteile am Boden ebenfalls nicht in Türdurchgänge/Fensterplätze stellen.
		var fp := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
		for reserved in protected:
			if fp.intersects(reserved):
				n.free()
				t.reused_models -= 1
				rejected += 1
				return null
	if not _fits(room,bounds,large):
		n.free()
		t.reused_models -= 1
		rejected += 1
		return null
	n.name = label
	n.set_meta("source","czech3/models/"+model+".glb")
	n.set_meta("furniture_type",label)
	n.set_meta("large",large)
	n.set_meta("bounds",bounds)
	n.add_to_group("bavaria_furniture")
	if large:
		t._mesh_colliders(n)
		occupied.append(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z))
	furnishings.append(n)
	return n

func _bed(room: Node3D,pos: Vector3,rect: Rect2) -> void:
	var bed := Node3D.new()
	bed.name = "Holzbett"
	room.add_child(bed)
	bed.position = pos
	if rect.size.y<2.14:
		var side := signf(rect.get_center().x)
		bed.rotation.y = PI*0.5
		bed.position.x = rect.position.x+1.08 if side<0 else rect.end.x-1.08
	m.lb.box(Vector3(0,0.12,0),Vector3(0.98,0.28,2.14),"wood",0,true,bed)
	for z in [-1.03,1.03]:
		m.lb.box(Vector3(0,0,z),Vector3(1.00,0.86 if z<0 else 0.55,0.08),"darkwood",0,true,bed)
	var mattress: Node3D = t.prop("e_matrce",Vector3.ZERO,PI*0.5,0.94,false)
	mattress.reparent(bed,false)
	mattress.scale = Vector3(0.93,1.0,0.78) # Reales Einzelbett: Matratze ca. 2,00 × 0,90 m.
	mattress.position = Vector3(0,0.40,0)
	var bounds: AABB = t.mesh_bounds(bed,Transform3D.IDENTITY)
	if not _fits(room,bounds,true):
		if Game.cli.has("interior_debug"):
			print("BED REJECT ",active_house.name," ",room.name," rect=",rect," bounds=",bounds," protected=",protected)
		bed.free()
		t.reused_models -= 1
		rejected += 1
		return
	bed.set_meta("furniture_type","Holzbett")
	bed.set_meta("large",true)
	bed.set_meta("bounds",bounds)
	bed.set_meta("source","Eigenes Holzgestell + czech3/models/e_matrce.glb")
	bed.add_to_group("bavaria_furniture")
	furnishings.append(bed)
	occupied.append(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z))
	var folded: Node3D = t.prop("e_covrlt",Vector3.ZERO,0,1.0,false)
	folded.reparent(bed,false)
	folded.position = Vector3(0,0.54,0.65)

func _picture(room: Node3D,rect: Rect2,side: float,floor_y: float) -> void:
	# An der inneren Flurwand neben der Tür, nie vor einem nutzbaren Außenfenster.
	var pos := Vector3(-corridor_half-0.13 if side<0 else corridor_half+0.13,floor_y+1.35,rect.end.y-0.30)
	_prop(room,"ja_vobraz07",pos,-PI*0.5 if side<0 else PI*0.5,0.40,false,"GerahmtesLandschaftsbild")

func _side_table(room: Node3D,pos: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Beistelltisch"
	room.add_child(n)
	n.position = pos
	m.lb.box(Vector3(0,0.50,0),Vector3(0.43,0.07,0.43),"wood",0,false,n)
	for x in [-0.16,0.16]:
		for z in [-0.16,0.16]:
			m.lb.box(Vector3(x,0,z),Vector3(0.055,0.5,0.055),"darkwood",0,false,n)
	# Kleinmöbel sind sichtbar, verursachen aber keine unnötige Stolperkollision.
	n.add_to_group("bavaria_furniture")
	n.set_meta("furniture_type","Beistelltisch")
	n.set_meta("large",false)
	furnishings.append(n)

func _papers(room: Node3D,pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.60,0.54,0.41)
	mat.roughness = 1
	m.lb._mats["old_paper"] = mat
	for i in 3:
		m.lb.box(pos+Vector3(0,i*0.002,0),Vector3(0.22,0.002,0.29),"old_paper",i*0.06,false,room)

func _wall_shelf(room: Node3D,pos: Vector3,side: float) -> void:
	var shelf := Node3D.new()
	shelf.name = "Wandregal"
	room.add_child(shelf)
	shelf.position = pos
	m.lb.box(Vector3.ZERO,Vector3(0.28,0.055,1.05),"wood",0,false,shelf)
	for z in [-0.38,0.38]:
		m.lb.box(Vector3(side*0.02,-0.21,z),Vector3(0.20,0.22,0.04),"darkwood",0,false,shelf)
	for i in 4:
		m.lb.box(Vector3(0,0.055,-0.31+i*0.18),Vector3(0.18,0.22+(i%2)*0.04,0.06),"darkwood" if i%2 else "brick",0,false,shelf)
	shelf.set_meta("furniture_type","Holzregal")
	shelf.set_meta("large",false)
	shelf.set_meta("source","Eigenes historisches Brettregal mit Buchattrappen")
	shelf.add_to_group("bavaria_furniture")
	furnishings.append(shelf)

func _books(shelf: Node3D) -> void:
	for row in 3:
		for col in 5:
			m.lb.box(Vector3(-0.83+col*0.31,0.55+row*0.57,0.02),Vector3(0.14,0.28+0.04*(col%2),0.24),"darkwood" if col%2 else "brick",0,false,shelf)
