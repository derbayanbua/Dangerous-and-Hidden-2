extends Node
## Echte Physik-/Nav-/Ballistikabnahme der beiden Flugzeug-Deckungsgruppen.
var passed := 0
var failed := 0

class Target extends StaticBody3D:
	var hit := false
	func on_bullet_hit(_damage: float,_shooter: Node) -> void:
		hit = true

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(180.0).timeout.connect(func():
		check(false,"Zeitlimit Wiesenabnahme")
		_finish())

func check(ok: bool, label: String) -> void:
	passed += 1 if ok else 0
	failed += 0 if ok else 1
	print("PASS " if ok else "FAIL ",label)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for s in m.squad.members:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	var wrecks := get_tree().get_nodes_in_group("bavaria_aircraft_wrecks")
	check(wrecks.size()==2,"Zwei Originalflugzeug-Wrackgruppen integriert")
	var space := m.get_world_3d().direct_space_state
	var nav_map: RID = m.get_world_3d().navigation_map
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var shots: Array = []
	for n in wrecks:
		var bounds: AABB = n.get_meta("bounds")
		var natural: Vector3 = n.get_meta("natural_size")
		check(n.global_basis.get_scale().is_equal_approx(Vector3.ONE) and natural.x>9 and natural.z>8,"Originaljäger im natürlichen Metermaßstab: "+n.name)
		check(int(n.get_meta("detached_meshes"))>=1 and int(n.get_meta("removed_gear"))==2,"Flügel sichtbar abgerissen und Fahrwerk eingeknickt/entfernt: "+n.name)
		check(n.has_node("AbgerissenerFluegel") and n.has_node("BrandUndSchleifspur"),"Getrennte Bruchgruppe und Brand-/Schleifspur: "+n.name)
		var radius := float(n.get_meta("radius"))
		var footprint := PackedVector2Array()
		for corner in [Vector3(bounds.position.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.end.z),Vector3(bounds.position.x,0,bounds.end.z)]:
			var world: Vector3 = n.to_global(corner)
			footprint.append(Vector2(world.x,world.z))
		check(_distance(m.pixel([575,554]),footprint)>=5.49,"Tatsächliche Wrackkontur hält Einnahmeradius samt Gehreserve frei: "+n.name)
		check(_distance(m.pixel([690,490]),footprint)>=4.19,"Tatsächliche Wrackkontur hält Flak samt Bedienerregion frei: "+n.name)
		var materials := true
		for mesh in n.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null:
				continue
			for i in mesh.mesh.get_surface_count():
				materials = materials and mesh.get_active_material(i)!=null
		check(materials,"Originaloberflächen mit erhaltener Texturierung: "+n.name)
		for side in [-1.0,1.0]:
			var x := bounds.position.x-1.2 if side<0 else bounds.end.x+1.2
			var a: Vector3 = n.to_global(Vector3(x,0.15,bounds.position.z-0.6))
			var b: Vector3 = n.to_global(Vector3(x,0.15,bounds.end.z+0.6))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 1|16
			query.transform = Transform3D(Basis(),a+Vector3.UP*0.85)
			query.motion = b-a
			check(space.intersect_shape(query).is_empty() and space.cast_motion(query)[0]>0.99,"Echte Soldatenkapsel passiert Seitenroute "+str(side)+": "+n.name)
			var path := NavigationServer3D.map_get_path(nav_map,a,b,true)
			check(path.size()>=2 and path[0].distance_to(a)<1.5 and path[-1].distance_to(b)<1.5,"KI-Pfad an Seite "+str(side)+" vorhanden: "+n.name)
		var found_cover := false
		for height in [0.45,0.75,1.1]:
			for z in [-1.0,0.0,1.0]:
				var a: Vector3 = n.to_global(Vector3(bounds.position.x-0.3,height,z))
				var b: Vector3 = n.to_global(Vector3(bounds.end.x+0.3,height,z))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
				if not found_cover and not hit.is_empty() and n.is_ancestor_of(hit.collider):
					found_cover = true
					shots.append([a,b,n.name])
		check(found_cover,"Wrackrumpf bietet echte niedrige Schussdeckung: "+n.name)
	for spawn in m.mp_spawns():
		check(_free(space,capsule,spawn.pos),"DM-Startkapsel nach Flugzeugplatzierung frei")
	for zone in m.mp_zones():
		for slot in zone.slots:
			check(_free(space,capsule,slot.pos),"Eroberungs-Startkapsel frei: "+str(zone.name))
	var shooter := Node3D.new()
	m.dynamic_root.add_child(shooter)
	var weapon := WeaponData.new()
	weapon.muzzle_velocity = 800
	weapon.falloff_start = 80
	var blocked: Array = []
	var controls: Array = []
	for shot in shots:
		blocked.append(_target(m,shot[1]))
		controls.append(_target(m,shot[1]+Vector3.UP*12))
	await get_tree().physics_frame
	for shot in shots:
		Ballistics.fire(shooter,shot[0],(shot[1]-shot[0]).normalized(),weapon,[],-1)
		Ballistics.fire(shooter,shot[0]+Vector3.UP*12,(shot[1]-shot[0]).normalized(),weapon,[],-1)
	await get_tree().create_timer(0.4).timeout
	for i in shots.size():
		check(not blocked[i].hit,"Echtes Projektil vom Flugzeug abgefangen: "+str(shots[i][2]))
		check(controls[i].hit,"Positive Kontrolle trifft ohne Flugzeugdeckung: "+str(shots[i][2]))
	_finish()

func _distance(position: Vector3, polygon: PackedVector2Array) -> float:
	var p := Vector2(position.x,position.z)
	if Geometry2D.is_point_in_polygon(p,polygon):
		return 0
	var closest := INF
	for i in polygon.size():
		closest = minf(closest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()])))
	return closest

func _target(m: Mission, position: Vector3) -> Target:
	var target := Target.new()
	m.dynamic_root.add_child(target)
	target.global_position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*0.45
	shape.shape = box
	target.add_child(shape)
	return target

func _free(space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, pos: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1|16
	query.transform = Transform3D(Basis(),pos+Vector3.UP*0.85)
	return space.intersect_shape(query).is_empty()

func _finish() -> void:
	print("ERGEBNIS: Bavaria Wiese: %d bestanden, %d fehlgeschlagen"%[passed,failed])
	get_tree().quit(1 if failed else 0)
