extends Node
## Echte Leiterfahrten, stabile Standflächen, Laubsichtschutz und freie Ballistik.
var passed := 0
var failed := 0

class Target extends StaticBody3D:
	var hit := false
	func on_bullet_hit(_damage: float,_shooter: Node) -> void:
		hit = true

func check(ok: bool, text: String) -> void:
	if ok:
		passed += 1
		print("PASS ",text)
	else:
		failed += 1
		print("FAIL ",text)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for soldier in m.squad.members:
		soldier.process_mode = Node.PROCESS_MODE_DISABLED
	var s := Soldier.new()
	s.name = "Kletterpruefer"
	m.actors_root.add_child(s)
	var space := m.get_world_3d().direct_space_state
	var ladders := get_tree().get_nodes_in_group("bavaria_scene_ladders")
	check(ladders.size() == 4,"Leiter-Endpunkte: Baum (2) und Antennen-Steigleiter (2), kein Dachsteg")
	var pdx = m.get("scene_details")
	var astand: Vector3 = pdx.antenna_stand
	check(astand != Vector3.ZERO and m.inside_map(astand) and astand.y > 3.0, "Antennenplattform als oberer Standplatz (%.2f m)" % astand.y)
	var hint_ok := false
	if m.has_method("bot_hints"):
		for h in m.bot_hints(astand, 3.0):
			if String(h.get("kind", "")) == "high" and (h["pos"] as Vector3).distance_to(astand) < 0.5:
				hint_ok = true
	check(hint_ok, "Bot-Hinweis „erhöhter Posten“ auf der Antennenplattform")
	check(m.get("scene_details").roof_stand == Vector3.ZERO and get_tree().get_nodes_in_group("bavaria_towers").size() == 1,
		"Antennenturm vorhanden, kein begehbarer Dachsteg")
	for ladder in ladders:
		if ladder.at_top:
			continue
		s.global_position = ladder.bottom
		s.velocity = Vector3.ZERO
		s.move_input = Vector3.ZERO
		await get_tree().physics_frame
		check(ladder.can_interact(s),"Leiter vom Boden benutzbar: "+ladder.name)
		ladder.interact(s)
		check(s.is_climbing(),"Vorhandener Kletterzustand gestartet: "+ladder.name)
		var until := Time.get_ticks_msec()+20000
		while s.is_climbing() and Time.get_ticks_msec()<until:
			await get_tree().physics_frame
		check(s.global_position.distance_to(ladder.top)<0.2,"Echter Aufstieg endet am oberen Stand: "+ladder.name)
		await get_tree().create_timer(0.5).timeout
		check(absf(s.global_position.y-ladder.top.y)<0.25 and s.is_on_floor(),"Standfläche trägt Soldaten nach Aufstieg: "+ladder.name)
		var down: Node
		for candidate in ladders:
			if candidate.at_top and candidate.top.is_equal_approx(ladder.top):
				down = candidate
		check(down != null and down.can_interact(s),"Abstieg oben erreichbar: "+ladder.name)
		if down:
			down.interact(s)
			until = Time.get_ticks_msec()+20000
			while s.is_climbing() and Time.get_ticks_msec()<until:
				await get_tree().physics_frame
			check(s.global_position.distance_to(ladder.bottom)<0.2,"Echter Abstieg endet am Boden: "+ladder.name)
	var detail: RefCounted = m.scene_details
	check(get_tree().get_nodes_in_group("bavaria_greenhouses").size()==2,"Zwei referenzbezogene Gewächshäuser")
	check(get_tree().get_nodes_in_group("bavaria_hedges").size()>50,"Mehrschichtige gezielte Hecken vorhanden")
	var has_panorama := ResourceLoader.exists("res://assets/maps/bavaria/south_alps_reference.png")
	if has_panorama:
		check(m.env.sky.sky_material is ShaderMaterial,"Südpanorama als Himmelsmaterial ohne Parallaxe")
		check(float(m.env.sky.sky_material.get_shader_parameter("panorama_repeats"))==3.0,"Alpenkulisse umfasst nahtlos den gesamten 360-Grad-Horizont")
	else:
		check(m.env.sky != null and not (m.env.sky.sky_material is ShaderMaterial and m.env.sky.sky_material.shader != null \
			and m.env.sky.sky_material.shader.resource_path.ends_with("alps_sky.gdshader")),"Ohne Panorama: normaler Missionshimmel")
	check(get_tree().get_nodes_in_group("bavaria_boundary_screen").size()==1,"Zusätzlicher äußerer Sichtschutzsaum vorhanden")
	var exterior: RefCounted = m.scene_details
	var correct_offset: bool = exterior.border_offsets.size()>150
	print("BORDER MESH OFFSETS count=",exterior.border_offsets.size()," minimum=",exterior.border_offsets.min())
	for distance in exterior.border_offsets:
		correct_offset = correct_offset and distance>=1.9
	check(correct_offset,"Alle äußeren Kulissen-Meshes beginnen frühestens etwa 2 m hinter der Grenze")
	var colliding := false
	for root in get_tree().get_nodes_in_group("bavaria_boundary_screen"):
		for body in root.find_children("*","CollisionObject3D",true,false):
			colliding = colliding or body.collision_layer!=0
	check(not colliding,"Außenkulisse fügt keine zusätzliche spielbare Kollision hinzu")
	if has_panorama:
		check((m.env.sky.sky_material.get_shader_parameter("south_direction") as Vector3).distance_to(Vector3(0.817,0,0.576).normalized())<0.01,
			"Panorama nach Süden im gedrehten Kartenlayout ausgerichtet")
	# Ein Laubvorhang isoliert vom Stamm: Welt-Raycast frei, KI-Sicht dennoch verdeckt.
	var volume: Dictionary = detail.foliage[0]
	var center: Vector3 = volume.center
	var tangent := Vector3(-(center-detail.tree_stand).z,0,(center-detail.tree_stand).x).normalized()
	var a := center-tangent*2.2
	var b := center+tangent*2.2
	check(detail.blocks_sight(a,b),"Dichtes Laub unterbricht Sichtlinie")
	var ray := PhysicsRayQueryParameters3D.create(a,b,1)
	check(space.intersect_ray(ray).is_empty(),"Laubvorhang hat keine kugelsichere Weltkollision")
	var perception := Perception.new()
	s.add_child(perception)
	check(not perception._line_of_sight(space,a,b,s),"Tatsächliche KI-Sichtprüfung berücksichtigt Laub")
	var clear_a: Vector3 = detail.tree_stand+Vector3(0,5,0)
	var clear_b: Vector3 = clear_a+Vector3.UP*3
	check(not detail.blocks_sight(clear_a,clear_b),"Freie Sicht außerhalb des Laubvorhangs bleibt möglich")
	var target := Target.new()
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	cs.shape = shape
	target.add_child(cs)
	m.add_child(target)
	target.global_position = b
	await get_tree().physics_frame
	var weapon := WeaponData.new()
	weapon.muzzle_velocity = 750
	Ballistics.fire(s,a,(b-a).normalized(),weapon,[],0)
	await get_tree().create_timer(0.2).timeout
	check(target.hit,"Echte Ballistik trifft durch Laub hindurch")
	target.hit = false
	var muzzle: Vector3 = detail.tree_stand+Vector3.UP*1.5
	var outward := Vector3(cos(TAU/10.0),0,sin(TAU/10.0))
	target.global_position = muzzle+outward*9.0
	await get_tree().physics_frame
	check(not detail.blocks_sight(muzzle,target.global_position),"Natürliche Beobachtungslücke am Baumstand bleibt frei")
	Ballistics.fire(s,muzzle,outward,weapon,[],0)
	await get_tree().create_timer(0.2).timeout
	check(target.hit,"Schütze kann vom Aststand ein Außenziel treffen")
	print("ERGEBNIS: Bavaria Details: %d bestanden, %d fehlgeschlagen"%[passed,failed])
	get_tree().quit(1 if failed else 0)
