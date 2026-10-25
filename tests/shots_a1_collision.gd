extends "res://tests/test_gameplay.gd"
## Kontrollbilder Kamera an Wänden in Arctic 1 (FENSTER, vorher/nachher):
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_a1_collision [--collision_legacy=1] [--tag=_vorher]
## → test_output/a1_wall_<n><tag>.png. Stellen aus test_a1_collision (Blick durch die Wand im alten Stand).

## [Fuß, Wandnormale (Blickrichtung der Figur = Rücken zur Wand), Lehnen]
const SPOTS := [
	[Vector3(23.36, 22.42, -74.47), Vector3(0.9945, 0, 0.1045), 0.0],
	[Vector3(23.36, 22.42, -74.47), Vector3(0.1045, 0, -0.9945), 0.0],
	[Vector3(23.36, 22.42, -74.47), Vector3(0.9945, 0, 0.1045), 1.0],
]


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if m.get("runtime") != null:
		(m.get("runtime") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for e in m.enemies:
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
	var s: Soldier = m.squad.leader()
	s.max_health = 1e9
	s.health = 1e9
	var tag := String(Game.cli.get("tag", ""))
	var k := 0
	for sp in SPOTS:
		k += 1
		var fwd: Vector3 = sp[1]
		s.global_position = sp[0] + Vector3.UP * 0.1
		s.velocity = Vector3.ZERO
		s.look_yaw = atan2(-fwd.x, -fwd.z)
		s.look_pitch = -0.15
		s.lean = sp[2]
		await seconds(2.0)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := ProjectSettings.globalize_path("res://test_output/a1_wall_%d%s.png" % [k, tag])
		img.save_png(p)
		print("SHOT ", p, " Kamera ", m.rig.camera.global_position)
	s.lean = 0.0
	check(true, "Bilder erstellt")
	_finish()
