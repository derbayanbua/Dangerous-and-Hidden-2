extends Node
## Innenräume bleiben begehbar; echte Möbelkollision, KI-Wege und Soldatenbewegung.
var passed := 0
var failed := 0

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(240).timeout.connect(func():
		check(false,"Zeitlimit Innenraumabnahme")
		_finish())

func check(ok: bool,label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ",label)

func _run() -> void:
	var m: Mission
	while m==null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for member in m.squad.members:
		member.process_mode = Node.PROCESS_MODE_DISABLED
	if get_tree().get_nodes_in_group("bavaria_furnished_houses").is_empty():
		load("res://src/maps/bavaria/interior_decoration.gd").new().build(m)
		m._templates.release()
		m.nav_ready = false
		m._bake_navigation()
		while not m.nav_ready:
			await get_tree().create_timer(0.1).timeout
	if Game.cli.has("interior_regression"):
		var test: Node = load("res://tests/"+String(Game.cli.interior_regression)+".gd").new()
		get_tree().root.add_child(test)
		return
	var space := m.get_world_3d().direct_space_state
	var nav_map: RID = m.get_world_3d().navigation_map
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var houses := get_tree().get_nodes_in_group("bavaria_furnished_houses")
	var rooms := get_tree().get_nodes_in_group("bavaria_furnished_rooms")
	check(houses.size()==14,"Alle14 intakten betretbaren Wohnhäuser eingerichtet")
	check(rooms.size()>=houses.size()*2+6,"Tatsächliche Nutzräume und beide zugänglichen Obergeschosse eingerichtet")
	for house in houses:
		var types := {}
		for n in house.find_children("*","Node3D",true,false):
			if n.has_meta("furniture_type"):
				types[String(n.get_meta("furniture_type"))] = true
		for label in ["Holzbett","Holzstuhl","GerahmtesLandschaftsbild","Holzregal"]:
			check(types.has(label),"Haus mit "+label+": "+String(house.get_meta("house")))
		check(types.has("Esstisch") or types.has("Arbeitstisch"),"Haus mit nutzbarem Tisch: "+String(house.get_meta("house")))
		check(types.has("Kleiderschrank") or types.has("Kuechenschrank"),"Haus mit Schrank: "+String(house.get_meta("house")))
	var models: Dictionary = {}
	for n in get_tree().get_nodes_in_group("bavaria_furniture"):
		models[String(n.get_meta("furniture_type"))] = true
		if bool(n.get_meta("large",false)):
			check(not n.find_children("*","CollisionShape3D",true,false).is_empty(),"Großmöbel mit echter passender Kollision: "+n.name)
			var room: Node3D = n.get_parent()
			var bounds: AABB = m._templates.mesh_bounds(n,Transform3D.IDENTITY)
			var rect: Rect2 = room.get_meta("room_rect")
			check(rect.grow(0.04).encloses(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)),"Tatsächliche Möbelgeometrie bleibt im Raum: "+String(room.get_meta("house"))+" "+n.name)
	for label in ["Holzbett","Esstisch","Arbeitstisch","Holzstuhl","Kuechenschrank","Holzregal","Kleiderschrank","GerahmtesLandschaftsbild","HistorischerHerd"]:
		check(models.has(label),"Vorhandene historische Ausstattung: "+label)
	var house_room_targets := {}
	for room in rooms:
		if String(room.get_meta("role"))=="Treppenhaus":
			continue
		var rect: Rect2 = room.get_meta("room_rect")
		var side := signf(rect.get_center().x)
		var floor_y := float(room.get_meta("floor_height"))
		var local := Vector3(rect.end.x-0.32 if side<0 else rect.position.x+0.32,floor_y+0.12,rect.get_center().y)
		var point: Vector3 = room.to_global(local)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1|16
		query.transform = Transform3D(Basis(),point+Vector3.UP*0.85)
		check(space.intersect_shape(query).is_empty(),"Freier Soldatenstand im eingerichteten Raum: "+String(room.get_meta("house"))+" "+room.name)
		var house: Node3D = m.static_root.get_node(String(room.get_meta("house")))
		var start: Vector3 = house.to_global(Vector3(0,0.20,0))
		var route := NavigationServer3D.map_get_path(nav_map,start,point,true)
		check(route.size()>1 and route[-1].distance_to(point)<0.6,"Eingerichteter Raum per KI erreichbar: "+String(room.get_meta("house"))+" "+room.name)
		if floor_y<1 and not house_room_targets.has(house.name):
			house_room_targets[house.name] = [house,point]
	var soldier := Soldier.new()
	soldier.name = "EinrichtungsBewegungspruefer"
	m.actors_root.add_child(soldier)
	soldier.move_mode = Soldier.MoveMode.WALK
	soldier.stance_request = Soldier.Stance.STAND
	for data in house_room_targets.values():
		var house: Node3D = data[0]
		soldier.global_position = house.to_global(Vector3(0,0.25,0))
		soldier.velocity = Vector3.ZERO
		await get_tree().create_timer(0.2).timeout
		var route := NavigationServer3D.map_get_path(nav_map,soldier.global_position,data[1],true)
		var deadline := Time.get_ticks_msec()+7000
		for point in route:
			while Time.get_ticks_msec()<deadline:
				var direction: Vector3 = point-soldier.global_position
				direction.y = 0
				if direction.length()<0.20:
					break
				soldier.move_input = direction.normalized()*clampf(direction.length()/0.5,0.4,1.0)
				soldier.look_yaw = atan2(-direction.x,-direction.z)
				await get_tree().physics_frame
		soldier.move_input = Vector3.ZERO
		check(soldier.global_position.distance_to(data[1])<0.55,"Echter Soldat geht vom Flur in eingerichteten Raum: "+house.name+" pos="+str(soldier.global_position)+" Ziel="+str(data[1]))
	_finish()

func _finish() -> void:
	print("ERGEBNIS: Bavaria Innenräume: %d bestanden, %d fehlgeschlagen"%[passed,failed])
	get_tree().quit(1 if failed else 0)
