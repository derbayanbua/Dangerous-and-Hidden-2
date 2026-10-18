extends "res://tests/screenshots_fpv.gd"
## Ego-Perspektive vor und nach einem Uniform-/Figurwechsel (alliiert en01 -> deutsch ge01a -> alliiert en01):
## ruhig, zielend (Kimme/Korn), nachladend; dazu je eine Außenansicht der Figur.
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots_ego
## Ausgabe: test_output/shot_e*.png; Konsole: Augenhöhe und Kamera-Anker je Figur.


func _ego_set(s: Soldier, rig: CameraRig, tag: String, weapon: String) -> void:
	s.equip([weapon, "colt", "no36", "", "knife"])
	await secs(2.6)
	print("EGO %s: Auge %.3f m über den Füßen, Kamera-Abstand zum Anker %.4f m, Figur sichtbar=%s" % [tag,
		s.model.camera_point(true).y - s.global_position.y, rig.camera.global_position.distance_to(s.model.camera_point(true)),
		s.model.visible])
	await snap("%s_ruhig" % tag)
	_hold_aim(true)
	await secs(1.0)
	await snap("%s_zielen" % tag)
	_hold_aim(false)
	await secs(0.8)
	s.current_weapon().in_mag = 1
	s.reload()
	await secs(s.current_weapon().data.reload_time * 0.45)
	await snap("%s_nachladen" % tag)
	await secs(s.current_weapon().data.reload_time * 0.6 + 0.5)


func _outside(s: Soldier, m: Mission, rig: CameraRig, tag: String) -> void:
	rig.toggle_mode()
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 40
	cam.global_position = s.global_position + Vector3(1.8, 1.5, -2.6)
	cam.look_at(s.global_position + Vector3(0, 1.2, 0))
	cam.current = true
	await secs(0.8)
	await snap("%s_aussen" % tag)
	cam.current = false
	rig.camera.current = true
	cam.queue_free()
	rig.toggle_mode()
	await secs(0.5)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 600:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	var s := m.squad.leader()
	for e in m.enemies:
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
	for mm in m.squad.members:
		if mm != s:
			mm.global_position = m.lb.ground(40, 60, 0.3)
			mm.set_physics_process(false)
	var rig: CameraRig = m.rig
	s.model.attach_orig(OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb"))
	s.global_position = m.lb.ground(3, 34, 0.2)
	s.look_yaw = 0.0
	s.look_pitch = 0.02
	await secs(1.0)
	rig.toggle_mode()
	await _ego_set(s, rig, "e1_alliiert", "enfield")
	await _outside(s, m, rig, "e2_alliiert")
	# Uniformwechsel auf die deutsche Figur (in der Ego-Ansicht)
	s.put_on_uniform(Color(0.36, 0.38, 0.33), "stahlhelm", OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb"))
	await _ego_set(s, rig, "e3_deutsch", "kar98k")
	await _outside(s, m, rig, "e4_deutsch")
	# zurück auf eine alliierte Figur, MP
	s.put_on_uniform(Color(0.42, 0.38, 0.26), "brodie", OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb"))
	await _ego_set(s, rig, "e5_alliiert_mp", "thompson")
	get_tree().quit()
