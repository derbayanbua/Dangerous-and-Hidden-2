extends Node
var passed := 0
var failed := 0
class Target extends StaticBody3D:
	var hit := false
	func on_bullet_hit(_damage: float,_shooter: Node) -> void:
		hit = true
func check(ok: bool,label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(180).timeout.connect(func():
		check(false,"Zeitlimit Boden/MG42")
		_finish())
func _run() -> void:
	var m: Mission
	while m==null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for member in m.squad.members:
		member.process_mode = Node.PROCESS_MODE_DISABLED
	if ResourceLoader.exists("res://assets/maps/bavaria/ground/boden_gras.png"):
		check(m.ground_surfaces.sources.size()==6,"Alle sechs optionalen Bodentexturen geladen")
		for key in m.ground_surfaces.sources:
			check(m.ground_surfaces.sources[key].get_size()==Vector2(1138,747),"Bodentextur ohne hellen Rand, keine Verkleinerung: "+key)
	else:
		check(not m.ground_surfaces.available and m.ground_surfaces.material_for("grass","x") != null,"Ohne Bodentexturen: neutrale Ersatzmaterialien")
	for id in ["PlayableGround","Wiese","row_lane_38","farm_track"]:
		var surface: MeshInstance3D = m.static_root.get_node(id)
		if m.ground_surfaces.available:
			check(surface.material_override is ShaderMaterial,"Neues Bodenmaterial aktiv: "+id)
		else:
			check(surface.material_override != null,"Ersatz-Bodenmaterial aktiv: "+id)
	var house: Node3D = m.static_root.get_node("woodland_shed")
	check(house.is_in_group("bavaria_enterable_sheds"),"Holzhaus als begehbare Stellung gebaut")
	var grass: MultiMeshInstance3D = m.static_root.get_node("Grasraender")
	var clear_grass := true
	for i in grass.multimesh.visible_instance_count:
		clear_grass = clear_grass and m.woodland_clearance(grass.multimesh.get_instance_transform(i).origin,0.39)
	check(clear_grass,"Keine sichtbaren Grasbüschel durch den Holzhausboden")
	var gun: OrigInteractive.OrigEmplacement = m.woodland_emplacement.gun
	check(WeaponDB.orig_item_of(gun.data.id)==33,"MG42 nutzt vorhandene Waffenwerte aus Spielcode")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var space := m.get_world_3d().direct_space_state
	for door in m.find_children("*","Door",true,false):
		door.set_open(true,true)
	await get_tree().physics_frame
	var entry: Dictionary = house.get_meta("entry_points")[0]
	var start: Vector3 = house.to_global(entry.point+entry.normal*1.5)+Vector3.UP*0.12
	var inside: Vector3 = house.to_global(Vector3(0,0.12,0))
	var route := NavigationServer3D.map_get_path(m.get_world_3d().navigation_map,start,gun.gunner_spot(),true)
	check(route.size()>1 and route[-1].distance_to(gun.gunner_spot())<0.7,"KI erreicht MG42 durch den tatsächlichen Eingang")
	for p in [start,inside,gun.gunner_spot()]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.collision_mask = 1|16
		q.transform = Transform3D(Basis(),p+Vector3.UP*0.85)
		for hit in space.intersect_shape(q):
			print("MG BLOCK ",hit.collider.get_path())
		check(space.intersect_shape(q).is_empty(),"Freier Soldatenstand Eingang/Innenraum/Bedienplatz: "+str(p))
	var s := Soldier.new()
	m.actors_root.add_child(s)
	s.global_position = start
	s.move_mode = Soldier.MoveMode.WALK
	s.stance_request = Soldier.Stance.STAND
	await _walk(s,Array(route).slice(1))
	check(s.global_position.distance_to(gun.gunner_spot())<0.65,"Echter Soldat betritt Holzhaus und geht bis zum MG42")
	var saved := s.weapons.duplicate()
	var exit := s.global_position
	gun.interact(s)
	check(s.mounted==gun and gun.gunner==s,"MG42 lässt sich tatsächlich besetzen")
	await get_tree().create_timer(0.7).timeout
	var direction := -gun.frame.global_basis.z
	var target := Target.new()
	m.dynamic_root.add_child(target)
	target.global_position = gun.shot_origin()+direction*18
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*1.5
	c.shape = box
	target.add_child(c)
	var sight := PhysicsRayQueryParameters3D.create(gun.shot_origin(),target.global_position,1)
	sight.exclude = gun.shot_exclusions()
	var hit := space.intersect_ray(sight)
	check(hit.is_empty(),"Echte Mündung schießt durch die Schießöffnung frei auf die Wiese")
	if not hit.is_empty():print("MG SIGHT BLOCK ",hit.collider.get_path()," at ",hit.position)
	await get_tree().physics_frame
	var ammo := s.current_weapon().in_mag
	s.look_yaw = gun.frame.rotation.y
	s.look_pitch = 0
	s.aiming = true
	s.trigger = true
	await get_tree().create_timer(0.5).timeout
	s.trigger = false
	check(s.current_weapon().in_mag<ammo,"MG42 verbraucht echte Munition")
	check(target.hit,"MG42 trifft tatsächliches Außenziel mit Spielballistik")
	check(s.current_weapon().start_reload(),"Vorhandener MG42-Nachladevorgang startet")
	await get_tree().create_timer(gun.data.reload_time+0.3).timeout
	check(s.current_weapon().in_mag==gun.data.magazine_size,"MG42-Magazin wird nachgeladen")
	s.look_yaw = gun.frame.rotation.y+PI
	s.look_pitch = 1.2
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(absf(wrapf(s.look_yaw-gun.frame.rotation.y,-PI,PI))<=deg_to_rad(25.1),"Schwenkbereich bleibt auf die Feldseite begrenzt")
	check(s.look_pitch<=deg_to_rad(15.1),"Rohr und Ballistik beachten Höhenrichtgrenze")
	gun.interact(s)
	check(s.mounted==null and s.weapons==saved and s.global_position.distance_to(exit)<0.2,"Ausstieg stellt persönliche Ausrüstung am freien Platz wieder her")
	target.queue_free()
	s.queue_free()
	_finish()
func _walk(s: Soldier,points: Array) -> void:
	for target in points:
		var deadline := Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			var delta: Vector3 = target-s.global_position
			delta.y = 0
			if delta.length()<0.18:break
			s.move_input = delta.normalized()*clampf(delta.length()/0.5,0.4,1.0)
			s.look_yaw = atan2(-delta.x,-delta.z)
			await get_tree().physics_frame
		s.move_input = Vector3.ZERO
func _finish() -> void:
	print("ERGEBNIS: Bavaria Boden/MG42: %d bestanden, %d fehlgeschlagen"%[passed,failed])
	get_tree().quit(1 if failed else 0)
