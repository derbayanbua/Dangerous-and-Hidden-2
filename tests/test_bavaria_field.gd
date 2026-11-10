extends Node
## Echte Treppenbewegung und bedienbare vorhandene Flak, keine Metadaten-Abnahme.
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
		check(false,"Zeitlimit Feld-/Treppenabnahme")
		_finish())

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for member in m.squad.members:
		member.process_mode = Node.PROCESS_MODE_DISABLED
	var s := Soldier.new()
	s.name = "TreppenUndFlakPruefer"
	m.actors_root.add_child(s)
	s.move_mode = Soldier.MoveMode.WALK
	s.stance_request = Soldier.Stance.STAND
	var houses := get_tree().get_nodes_in_group("bavaria_stair_houses")
	check(houses.size()==2,"Zwei Wohnhäuser mit echten zweiläufigen Innentreppen")
	for house in houses:
		var local: Array = house.get_meta("stair_path")
		var points: Array[Vector3] = []
		for p in local:
			points.append(house.to_global(p))
		check(float(house.get_meta("stair_rise"))<0.19 and float(house.get_meta("stair_run"))>=0.28,"Begehbare reale Stufenmaße: "+house.name)
		s.global_position = points[0]
		s.velocity = Vector3.ZERO
		await get_tree().create_timer(0.2).timeout
		var path := NavigationServer3D.map_get_path(m.get_world_3d().navigation_map,points[0],points[-1],true)
		print("STAIR NAV ",house.name," path=",path)
		for p in points:
			print("STAIR NAV NEAREST ",p," -> ",NavigationServer3D.map_get_closest_point(m.get_world_3d().navigation_map,p))
		check(path.size()>1 and path[-1].distance_to(points[-1])<0.5,"KI-Pfad führt ins Obergeschoss: "+house.name)
		await _walk(s,points.slice(1))
		check(s.global_position.distance_to(points[-1])<0.5 and s.is_on_floor(),"Soldat geht beide Läufe hinauf und steht oben: "+house.name+" pos="+str(s.global_position))
		points.reverse()
		await _walk(s,points.slice(1))
		check(s.global_position.distance_to(points[-1])<0.5 and s.is_on_floor(),"Soldat geht über das Podest wieder hinunter: "+house.name)
		path = NavigationServer3D.map_get_path(m.get_world_3d().navigation_map,points[-1],points[0],true)
		await _walk(s,Array(path).slice(1))
		check(s.global_position.distance_to(points[0])<0.6 and s.is_on_floor(),"Soldat folgt echtem KI-Pfad nach oben: "+house.name)
	var gun: OrigInteractive.OrigEmplacement = m.field_emplacement.gun
	check(gun != null and gun.data == WeaponDB.get_weapon(&"flak38"),"Vorhandene Flak-38-Waffe und Interaktion aus Spielcode")
	s.global_position = gun.gunner_spot()+Vector3(1.0,0,0)
	s.velocity = Vector3.ZERO
	var saved := s.weapons.duplicate()
	var exit := s.global_position
	gun.interact(s)
	check(s.mounted==gun and gun.gunner==s and s.current_weapon().data.id==&"flak38","Flak tatsächlich über Benutzen besetzt")
	var other := Soldier.new()
	m.actors_root.add_child(other)
	check(not gun.can_interact(other),"Besetzte Flak kann nicht von zweitem Soldaten übernommen werden")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1|16
	query.transform = Transform3D(Basis(),s.global_position+Vector3.UP*0.85)
	check(m.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Bediener steht frei neben der Geschützkollision")
	await get_tree().create_timer(0.65).timeout # Vorhandene 0,5-s-Bereitmachzeit der Waffe abwarten.
	s.look_yaw = gun.frame.rotation.y
	s.look_pitch = 0.0
	s.aiming = true
	var target := Target.new()
	m.dynamic_root.add_child(target)
	target.global_position = s.eye_position()+s.aim_direction()*15
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*2.0
	var collision := CollisionShape3D.new()
	collision.shape = box
	target.add_child(collision)
	await get_tree().physics_frame
	var before := s.current_weapon().in_mag
	s.trigger = true
	await get_tree().create_timer(0.45).timeout
	s.trigger = false
	check(s.current_weapon().in_mag<before,"Bedienbarer Abzug verbraucht echte Flakmunition")
	check(target.hit,"Flak trifft Außenziel mit echter Spielballistik")
	check(s.current_weapon().start_reload(),"Flak kann mit angebrochenem Magazin nachgeladen werden")
	await get_tree().create_timer(3.2).timeout
	check(s.current_weapon().in_mag==gun.data.magazine_size,"Vorhandener Nachladevorgang füllt Flakmagazin wieder")
	var angle_before: float = gun.traverse.rotation.y
	s.look_yaw += 0.6
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(absf(gun.traverse.rotation.y-angle_before)>0.4,"Sichtbares Geschütz folgt der horizontalen Ausrichtung")
	s.look_pitch = 1.2
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(absf(gun.elevation.rotation.x-gun.elevation_rest.x-1.2)<0.02,"Flak kann über 60 Grad nach oben gerichtet werden")
	s.look_pitch = -1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(absf(s.look_pitch+0.17)<0.02,"Rohr und Schussrichtung beachten gemeinsam die untere Höhenrichtgrenze")
	gun.interact(s)
	check(s.mounted==null and gun.gunner==null and s.weapons==saved,"Verlassen stellt persönliche Waffen wieder her")
	check(s.global_position.distance_to(exit)<0.2,"Verlassen kehrt an freien Einstiegsplatz zurück")
	target.queue_free()
	other.queue_free()
	s.queue_free()
	_finish()

func _walk(s: Soldier,points: Array) -> void:
	for target in points:
		var deadline := Time.get_ticks_msec()+12000
		while Time.get_ticks_msec()<deadline:
			var delta: Vector3 = target-s.global_position
			delta.y = 0
			if delta.length()<0.15:
				break
			s.move_input = delta.normalized()*clampf(delta.length()/0.5,0.4,1.0)
			s.look_yaw = atan2(-delta.x,-delta.z)
			await get_tree().physics_frame
		s.move_input = Vector3.ZERO
	await get_tree().create_timer(0.25).timeout

func _finish() -> void:
	print("ERGEBNIS: Bavaria Feld/Treppen: %d bestanden, %d fehlgeschlagen" % [passed,failed])
	get_tree().quit(1 if failed else 0)
