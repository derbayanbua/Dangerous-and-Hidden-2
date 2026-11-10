extends Node
## Kartenabnahme: echte Physik, freie Starts, feste Grenze, zusammenhängende KI-Wege.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_map
var failed := 0
var passed := 0

class WindowTarget extends StaticBody3D:
	var received_hit := false
	func on_bullet_hit(_damage: float, _shooter: Node) -> void:
		received_hit = true

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		check(false, "Karte/Navigation nach 240 s nicht bereit")
		_finish())

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
	await get_tree().physics_frame
	check(Game.MP_MAPS.has("bavaria"), "Im MP-Kartenregister")
	var main_house: Node3D = m.static_root.get_node("haus_16")
	var radio_house: Node3D = m.static_root.get_node("haus_18_shed")
	var main_size: Vector2 = main_house.get_meta("footprint_size")
	check(absf(main_size.x-13.1)<0.01,"Haus 16 entspricht 13,10 m Planbreite")
	check(radio_house.get_meta("footprint_size").x>9.8 and radio_house.get_meta("footprint_size").x<10.2,"Antennenhaus: gemessener Kern mit separaten Anbauten statt kopiertem Haus-16-Rechteck")
	check(m._bounds().size.x>111 and m._bounds().size.x<113 and m._bounds().size.y>115 and m._bounds().size.y<117,"Blaue Kartenform am langen Haus-16-Umriss auf ca.112×116m kalibriert")
	check(main_house.global_basis.get_scale().is_equal_approx(Vector3.ONE),"Gebäude neu in Metern gebaut, keine gestauchten Türen/Soldaten")
	for road in m.layout.paths:
		check(float(road.width)>=0.85 and float(road.width)<3.2,"Planbezogene Wegbreite im neuen Maßstab: "+str(road.id))

	check(get_tree().get_nodes_in_group("bavaria_buildings").size() == int(m.layout.reference_alignment.expected_building_parts), "30 einzelne Gebäude/Hausteile")
	check(get_tree().get_nodes_in_group("bavaria_ruins").size() == 6, "Sechs zerstörte Gebäudeteile; Antennengebäude mit intaktem Dach")
	var antennas := get_tree().get_nodes_in_group("bavaria_roof_antennas")
	check(antennas.size() == 1, "Genau eine gelieferte Dachantenne vorhanden")
	if antennas.size() == 1:
		var antenna: Node3D = antennas[0]
		var mount := m.static_root.get_node("haus_18_shed") as Node3D
		var local := mount.to_local(antenna.global_position)
		check(antenna.get_meta("mounted_on") == "haus_18_shed" and m.inside_map(antenna.global_position),
			"Antenne auf dem rot markierten Nebengebäude innerhalb der Karte")
		check(absf(local.x-(float(mount.get_meta("footprint_size").x)*0.5+1.4))<0.02 and absf(local.z-float(mount.get_meta("footprint_size").y)*float(m.layout.buildings.filter(func(v):return v.id=="haus_18_shed")[0].tower_z_fraction))<0.01 and antenna.get_meta("ground_supported",false),
			"Antenne neben der Giebelwand auf bodengestütztem Metallturm")
		check(antenna.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Gelieferten Metermaßstab erhalten")
		check(antenna.has_node("MastCollision/CollisionShape3D"), "Gelieferte Mastkollision vorhanden")
		var complete := true
		var bounds := AABB()
		var meshes := get_tree().get_nodes_in_group("bavaria_antenna_visuals")
		for mesh in meshes:
			bounds = bounds.merge(antenna.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb())
			complete = complete and mesh.visibility_range_end == 0.0
			for surface in mesh.mesh.get_surface_count():
				complete = complete and mesh.get_active_material(surface) != null
		check(meshes.size() >= 8 and complete, "Antennenteile mit gelieferten Materialien und vollständiger Sichtweite")
		check(bounds.size.y > 10.0 and bounds.size.y < 12.0 and bounds.size.x > 14.0,
			"Vollständige Mast-/Strahlergeometrie im Originalmaßstab")
	check(m.asset_report.missing.is_empty(), "Alle Originaltexturen/Modelle vorhanden: " + str(m.asset_report.missing))
	check(m.asset_report.models > 30 and m.asset_report.textures >= 10, "Vorhandene Modelle und Texturen wiederverwendet")
	check(get_tree().get_nodes_in_group("bavaria_boundaries").size() == 4, "Vier physische Kartengrenzen")
	check(float(m.asset_report.trees) / (m._bounds().size.x*m._bounds().size.y) >= 180.0/(532.0*554.0), "Mindestens bisherige Baumdichte pro Quadratmeter")
	check(int(m.asset_report.decorations) >= 24, "Gezielte historische Gruppen auf kompakter Karte vorhanden")
	var tree_instances := 0
	for batch in get_tree().get_nodes_in_group("bavaria_tree_batches"):
		tree_instances += batch.multimesh.instance_count
	check(tree_instances >= int(m.asset_report.trees), "Baumgeometrie in Original-Mesh-Instanzen vollständig vorhanden")
	for building in get_tree().get_nodes_in_group("bavaria_buildings"):
		var visuals := building.find_children("*", "MeshInstance3D", true, false)
		var complete := visuals.size() == 1 and visuals[0].mesh != null
		if complete:
			var visual: MeshInstance3D = visuals[0]
			var bounds := visual.get_aabb()
			complete = bounds.size.y > 1.0 and bounds.size.x > 3.0 and bounds.size.z > 3.0
			complete = complete and (visual.visibility_range_end == 0.0 or visual.visibility_range_end >= 500.0)
			for surface in visual.mesh.get_surface_count():
				complete = complete and visual.get_active_material(surface) != null
		check(complete, "Vollständige Gebäudehülle mit gemeinsamen Sichtweiten und Materialien: " + building.name)
	var no_overlaps := true
	for i in m.building_footprints.size():
		for j in range(i + 1, m.building_footprints.size()):
			for intersection in Geometry2D.intersect_polygons(m.building_footprints[i], m.building_footprints[j]):
				var area := 0.0
				for k in intersection.size():
					area += intersection[k].cross(intersection[(k + 1) % intersection.size()])
				if absf(area) > 1.0:
					print("OVERLAP Gebäude %d/%d: %.2f m²" % [i,j,absf(area)*0.5])
					no_overlaps = false
	check(no_overlaps, "Keine überlappenden Gebäudegrundrisse")
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	for building in get_tree().get_nodes_in_group("bavaria_buildings"):
		if not building.get_meta("interior_partitioned", false):
			continue
		var visual: MeshInstance3D = building.get_node("CompleteBuildingVisual")
		var half_d := visual.get_aabb().size.z * 0.5 - 3.0
		for point in [Vector3(0,0.3,half_d),Vector3(0,0.3,0),Vector3(0,0.3,-half_d),Vector3(-1.0,0.3,0),Vector3(1.0,0.3,0)]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis(),building.to_global(point) + Vector3.UP * 0.85)
			query.collision_mask = 1 | 16
			check(space.intersect_shape(query).is_empty(), "Flur/Zimmerzugang frei: " + building.name + " " + str(point))
	await _check_enterable_rooms(m, space, capsule)
	var spawns: Array = m.mp_spawns()
	for i in spawns.size():
		var pos: Vector3 = spawns[i].pos
		check(m.inside_map(pos), "Start %02d innerhalb der blauen Grenze" % i)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis(), pos + Vector3.UP * 0.85)
		query.collision_mask = 1 | 16
		var hits := space.intersect_shape(query)
		for block in hits:
			print("SPAWN BLOCK ",i," ",block.collider.get_path())
		check(hits.is_empty(), "Start %02d mit freier Soldatenkapsel: %s" % [i, str(hits)])
		var ray := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2, pos - Vector3.UP * 2, 1)
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y) < 0.1, "Start %02d steht über begehbarem Boden" % i)
	var map: RID = m.get_world_3d().navigation_map
	check(Game.MP_MAPS.has("bavaria_occupation"), "Eroberungsvariante im MP-Kartenregister")
	check(m.mp_zones().size() == 5, "Fünf Eroberungszonen")
	for zone in m.mp_zones():
		var center: Vector3 = zone.xf.origin
		check(m.inside_map(center), "Zone %s innerhalb der Grenze" % zone.name)
		var path := NavigationServer3D.map_get_path(map, spawns[0].pos, center, true)
		check(path.size() > 1 and path[-1].distance_to(center) < 2.0, "Zone %s per KI erreichbar" % zone.name)
		for slot in zone.slots:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis(), slot.pos + Vector3.UP * 0.85)
			query.collision_mask = 1 | 16
			for hit in space.intersect_shape(query):
				print("ZONE BLOCK ",zone.name," pos=",slot.pos," ",hit.collider.get_path()," colliderpos=",hit.collider.global_position)
			check(m.inside_map(slot.pos) and space.intersect_shape(query).is_empty(), "Freier Eroberungsspawn an " + zone.name)
	var from: Vector3 = spawns[0].pos
	for i in range(1, spawns.size()):
		var target: Vector3 = spawns[i].pos
		var path := NavigationServer3D.map_get_path(map, from, target, true)
		check(path.size() > 1 and path[-1].distance_to(target) < 2.0,
			"KI-Pfad vom Weststart zu Start %02d (einschließlich Wiese/Ostseite)" % i)
	for i in m.boundary.size():
		var a: Vector2 = m.boundary[i]
		var b: Vector2 = m.boundary[(i + 1) % m.boundary.size()]
		var mid := (a + b) * 0.5
		var outward := mid.normalized()
		var center := Vector3(mid.x, 10, mid.y)
		var ray := PhysicsRayQueryParameters3D.create(center - Vector3(outward.x,0,outward.y) * 3,
			center + Vector3(outward.x,0,outward.y) * 3, 16)
		check(not space.intersect_ray(ray).is_empty(), "Grenze %d blockiert auch oberhalb des Zauns" % i)
	# Schützengräben (11/2026): Sohle trägt, KI erreicht den Graben vom Weststart und verlässt ihn wieder.
	for trench in get_tree().get_nodes_in_group("bavaria_trenches"):
		var fps: Array = trench.get_meta("floor_points")
		var deep: Vector3 = (fps[1] + fps[2]) * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(deep + Vector3.UP * 0.8, deep + Vector3.DOWN * 1.0, 1))
		check(not hit.is_empty() and absf(hit.position.y - deep.y) < 0.08, "Graben %s: Sohle auf %.2f m trägt" % [trench.name, deep.y])
		var into := NavigationServer3D.map_get_path(map, from, deep, true)
		var back := NavigationServer3D.map_get_path(map, deep, from, true)
		check(into.size() > 1 and into[-1].distance_to(deep) < 0.6 and back.size() > 1 and back[-1].distance_to(from) < 2.0,
			"Graben %s: per KI-Pfad erreichbar und wieder verlassbar" % trench.name)
	_finish()

func _check_enterable_rooms(m: Mission, space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D) -> void:
	var targets: Array[WindowTarget] = []
	var shots: Array = []
	var houses := 0
	# Echte interaktive Türen öffnen; der Test berücksichtigt deren bewegliche Collider.
	for door in m.find_children("*", "Door", true, false):
		door.set_open(true, true)
	for i in 3:
		await get_tree().physics_frame
	for building in get_tree().get_nodes_in_group("bavaria_buildings"):
		if not building.get_meta("interior_partitioned", false):
			continue
		houses += 1
		var windows: Array = building.get_meta("shooting_windows", [])
		check(windows.size() == 4, "Vier echte Fensterplätze: " + building.name)
		var half_d: float = absf(windows[0].z)
		for door in building.get_meta("entry_points",[]):
			var point: Vector3 = door.point
			var normal: Vector3 = door.normal
			var entry := PhysicsShapeQueryParameters3D.new()
			entry.shape = capsule
			entry.collision_mask = 1|16
			entry.transform = Transform3D(Basis(),building.to_global(point+Vector3.UP*1.15+normal*float(door.approach)))
			entry.motion = building.global_basis*(-normal*(float(door.approach)+1.5))
			var clear := space.intersect_shape(entry).is_empty() and space.cast_motion(entry)[0]>0.99
			if not clear:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 1|16
				query.transform = entry.transform
				query.transform.origin += entry.motion*minf(space.cast_motion(entry)[0]+0.05,1.0)
				for hit in space.intersect_shape(query):
					print("ENTRY BLOCK ",building.name," ",normal," ",hit.collider.get_path()," local=",building.to_local(hit.collider.global_position))
			check(clear,"Hauseingang mit Soldatenkapsel passierbar: "+building.name+" "+str(normal))
		for index in windows.size():
			var window: Vector3 = windows[index]
			var side := signf(window.z)
			var inside: Vector3 = building.to_global(window - Vector3(0,0,side * 1.4))
			var outside: Vector3 = building.to_global(window + Vector3(0,0,side * 1.0))
			var label := String(building.name) + " Fenster " + str(index + 1)
			var standing := PhysicsShapeQueryParameters3D.new()
			standing.shape = capsule
			standing.collision_mask = 1 | 16
			standing.transform = Transform3D(Basis(),Vector3(inside.x,1.15,inside.z))
			if not space.intersect_shape(standing).is_empty():
				for hit in space.intersect_shape(standing):
					print("WINDOW BLOCK ",label," ",hit.collider.get_path()," at ",building.to_local(hit.collider.global_position)," world ",hit.collider.global_position)
			check(space.intersect_shape(standing).is_empty(), "Freier Standplatz am " + label)
			var room := Vector3(inside.x,0.3,inside.z)
			var route := NavigationServer3D.map_get_path(m.get_world_3d().navigation_map,
				building.to_global(Vector3(0,0.3,0)),room,true)
			check(route.size() > 1 and route[-1].distance_to(room) < 1.0, "Zimmer vom Flur erreichbar: " + label)
			var sight := PhysicsRayQueryParameters3D.create(inside,outside,Ballistics.MASK)
			sight.collide_with_areas = true
			check(space.intersect_ray(sight).is_empty(), "Sicht-/Schusslinie nach draußen frei: " + label)
			var sill_from := Vector3(inside.x,0.6,inside.z)
			var sill_to := Vector3(outside.x,0.6,outside.z)
			check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(sill_from,sill_to,1)).is_empty(),
				"Mauer unter Fenster bietet Deckung: " + label)
			var target := WindowTarget.new()
			target.name = "Schussziel_" + String(building.name) + "_" + str(index)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.8,0.8,0.1)
			shape.shape = box
			target.add_child(shape)
			m.add_child(target)
			target.global_position = outside
			target.global_basis = building.global_basis
			targets.append(target)
			shots.append([building,inside,(outside-inside).normalized(),label])
	check(houses == 14, "14 betretbare Wohnhäuser mit Zimmern und Schussfenstern")
	await get_tree().physics_frame
	var weapon := WeaponData.new()
	weapon.muzzle_velocity = 750.0
	weapon.damage = 10.0
	weapon.falloff_start = 100.0
	for shot in shots:
		Ballistics.fire(shot[0],shot[1],shot[2],weapon,[], -1)
	await get_tree().create_timer(0.2).timeout
	for i in targets.size():
		check(targets[i].received_hit, "Echtes Projektil trifft Außenziel durch " + String(shots[i][3]))
		targets[i].queue_free()
	await get_tree().physics_frame

func _finish() -> void:
	print("ERGEBNIS: Bavaria: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(1 if failed else 0)
