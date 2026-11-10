extends Node
## Physische Deckung, offene Wrackfenster, Umlaufwege und geschützte Leiter-/Spawnplätze.
var passed := 0
var failed := 0

class BulletTarget extends StaticBody3D:
	var hit := false
	func on_bullet_hit(_damage: float,_shooter: Node) -> void:
		hit = true

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(180.0).timeout.connect(func():
		check(false,"Zeitlimit für Dekorationsabnahme")
		_finish())

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ",label)
	else:
		failed += 1
		print("FAIL ",label)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for s in m.squad.members:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	var space := m.get_world_3d().direct_space_state
	var nav_map: RID = m.get_world_3d().navigation_map
	check(m.war_decoration.missing.is_empty(),"Vorhandene Assets ohne fehlende Dateien")
	check(get_tree().get_nodes_in_group("bavaria_wrecks").size()==6,"Vier alte PKW, eine Halbkette und ein echtes Panzerwrack")
	check(get_tree().get_nodes_in_group("bavaria_fixed_cover").size()==10,"Zehn feste taktische Deckungsgruppen")
	check(get_tree().get_nodes_in_group("bavaria_damaged_machines").size()==2,"Zwei beschädigte historische Werkplätze")
	check(get_tree().get_nodes_in_group("bavaria_garden_groups").size()==6,"Sechs zusammenhängende Nutzgarten-/Gerätegruppen")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var bullet_tests: Array = []
	for n in get_tree().get_nodes_in_group("bavaria_wrecks"):
		check(n.get_meta("static_wreck",false) and n.find_children("*","Vehicle",true,false).is_empty(),"Statisches Wrack ohne Fahr-/Explosionszustand: "+n.name)
		var size: Vector3 = n.get_meta("bounds_size")
		var height := float(n.get_meta("cover_height"))
		var a: Vector3 = n.to_global(Vector3(-size.x*0.5-1,height,0))
		var b: Vector3 = n.to_global(Vector3(size.x*0.5+1,height,0))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
		check(not hit.is_empty() and n.is_ancestor_of(hit.get("collider")),"Chassis stoppt Querstrahl: "+n.name)
		bullet_tests.append([a,b,n.name])
		var radius := Vector2(size.x,size.z).length()*0.5+0.9
		var ring: Array[Vector3] = []
		var all_free := true
		for i in 8:
			var angle := TAU*i/8.0
			var pos: Vector3 = n.global_position+Vector3(cos(angle)*radius,0.1,sin(angle)*radius)
			ring.append(pos)
			all_free = all_free and _capsule_free(space,capsule,pos)
		check(all_free,"Soldatenkapsel kann das Wrack an acht Seiten umgehen: "+n.name)
		var connected := true
		for i in ring.size():
			var path := NavigationServer3D.map_get_path(nav_map,ring[i],ring[(i+1)%ring.size()],true)
			connected = connected and path.size()>=2 and path[0].distance_to(ring[i])<1.5 and path[-1].distance_to(ring[(i+1)%ring.size()])<1.5
		check(connected,"KI-Umlaufweg um alle acht Wrackseiten: "+n.name)
		if String(n.name).begins_with("PKW_"):
			# GLB-Fensteröffnungen von außen durchmessen; keine einfache Gesamt-AABB-Kollision.
			var window_gap := false
			for z in [-0.5,0.0,0.5]:
				var left: Vector3 = n.to_global(Vector3(-size.x,1.10,z))
				var right: Vector3 = n.to_global(Vector3(size.x,1.10,z))
				var query := PhysicsRayQueryParameters3D.create(left,right,1)
				var result := space.intersect_ray(query)
				window_gap = window_gap or result.is_empty()
			check(window_gap,"Zerstörte PKW-Fenster bleiben wirklich durchschießbar: "+n.name)
	for n in get_tree().get_nodes_in_group("bavaria_fixed_cover"):
		var a: Vector3 = n.to_global(Vector3(0,0.65,-3.0))
		var b: Vector3 = n.to_global(Vector3(0,0.65,2.5))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
		if hit.is_empty() or not n.is_ancestor_of(hit.get("collider")):
			print("COVER RAY BLOCK ",n.name," ",hit.get("collider").get_path() if hit.get("collider") else "Kein Treffer")
		check(not hit.is_empty() and n.is_ancestor_of(hit.get("collider")),"Feste Deckung stoppt den Schussstrahl: "+n.name)
		bullet_tests.append([a,b,n.name])
		var rear: Vector3 = n.to_global(Vector3(0,0.1,2.1))
		check(_capsule_free(space,capsule,rear),"Offener Zugang hinter der Deckung: "+n.name)
	for n in get_tree().get_nodes_in_group("bavaria_damaged_machines"):
		var bounds: AABB = m._templates.mesh_bounds(n,n.transform.affine_inverse())
		var radius := float(n.get_meta("placement_radius"))
		var within := true
		for corner in 8:
			var pos: Vector3 = bounds.get_endpoint(corner)
			within = within and Vector2(pos.x,pos.z).length()<=radius
		check(within,"Transformierte Werkplatz-Geometrie bleibt im geschützten Platzierungsradius: "+n.name)
		check(bounds.position.y>=-0.01 and bounds.position.y<0.1,"Auch umgelegtes Aggregat und Geräte sitzen auf dem Boden: "+n.name)
	for n in get_tree().get_nodes_in_group("bavaria_garden_groups"):
		var bounds: AABB = m._templates.mesh_bounds(n,n.transform.affine_inverse())
		var within := true
		for corner in 8:
			var pos: Vector3 = bounds.get_endpoint(corner)
			within = within and Vector2(pos.x,pos.z).length()<=float(n.get_meta("placement_radius"))
		check(within,"Reale Beete, Leine und unverkleinerte Requisiten passen in die reservierte Parzelle: "+n.name)
	for ladder in get_tree().get_nodes_in_group("bavaria_scene_ladders"):
		check(_capsule_free(space,capsule,ladder.global_position+Vector3.UP*0.1),"Leiter-Endpunkt durch Deko nicht verstellt: "+ladder.name)
	for spawn in m.mp_spawns():
		check(_capsule_free(space,capsule,spawn.pos),"DM-Startkapsel bleibt frei")
	for zone in m.mp_zones():
		for slot in zone.slots:
			check(_capsule_free(space,capsule,slot.pos),"Eroberungs-Startkapsel bleibt frei: "+str(zone.name))
	# Echte Ballistics-Projektile statt nur visueller oder geometrischer Behauptung.
	var weapon := WeaponData.new()
	weapon.damage = 10
	weapon.muzzle_velocity = 800
	weapon.falloff_start = 80
	var shooter := Node3D.new()
	m.dynamic_root.add_child(shooter)
	var targets: Array = []
	for shot in bullet_tests:
		var target := BulletTarget.new()
		m.dynamic_root.add_child(target)
		target.global_position = shot[1]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE*0.35
		shape.shape = box
		target.add_child(shape)
		targets.append(target)
	var controls: Array = []
	for shot in bullet_tests:
		var target := BulletTarget.new()
		m.dynamic_root.add_child(target)
		target.global_position = shot[1]+Vector3.UP*10
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE*0.35
		shape.shape = box
		target.add_child(shape)
		controls.append(target)
	await get_tree().physics_frame
	for shot in bullet_tests:
		Ballistics.fire(shooter,shot[0],(shot[1]-shot[0]).normalized(),weapon,[],-1)
		Ballistics.fire(shooter,shot[0]+Vector3.UP*10,(shot[1]-shot[0]).normalized(),weapon,[],-1)
	await get_tree().create_timer(0.3).timeout
	for i in targets.size():
		check(not targets[i].hit,"Echtes Projektil wird von Deckung abgefangen: "+str(bullet_tests[i][2]))
		check(controls[i].hit,"Positive Kontrolle trifft ohne Deckung: "+str(bullet_tests[i][2]))
		targets[i].queue_free()
		controls[i].queue_free()
	_finish()

func _capsule_free(space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(),position+Vector3.UP*0.85)
	query.collision_mask = 1 | 16
	var hits := space.intersect_shape(query)
	if not hits.is_empty():
		for hit in hits:
			print("BLOCKED ",position," by ",hit.collider.get_path())
	return hits.is_empty()

func _finish() -> void:
	print("ERGEBNIS: Bavaria Dekoration: %d bestanden, %d fehlgeschlagen" % [passed,failed])
	get_tree().quit(1 if failed else 0)
