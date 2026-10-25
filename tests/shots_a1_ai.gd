extends "res://tests/test_gameplay.gd"
## B-020 Kontrollbilder (FENSTER): Hund mit Originalanimationen und Wachen in ARCTIC1.
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_a1_ai   → test_output/b020_*.png


func _shot(name: String) -> void:
	await frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://test_output/b020_%s.png" % name)
	print("BILD ", name)


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for sm in m.squad.members:
		sm.max_health = 100000.0
		sm.health = sm.max_health
	var c: Soldier = m.squad.members[0]
	var dog := rt.actors.get("PES_00") as Dog
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	for clip in ["idle", "walk", "run", "attack", "bark", "lie"]:
		if dog._anim and dog._anim.has_animation(clip):
			dog.suspended = true
			dog._anim.play(clip)
			await seconds(0.6)
			cam.global_position = dog.global_position + Vector3(2.2, 1.0, 1.2)
			cam.look_at(dog.global_position + Vector3.UP * 0.4)
			await _shot("dog_" + clip)
	dog.suspended = false
	c.global_position = dog.global_position + Vector3(5, 0.3, 0)
	dog.raise(c)
	await seconds(2.5)
	cam.global_position = dog.global_position + Vector3(3, 1.6, 3)
	cam.look_at(dog.global_position + Vector3.UP * 0.4)
	await _shot("dog_angriff")
	var w := rt.actors.get("WALKER_GUARD_1") as Soldier
	cam.global_position = w.global_position + Vector3(4, 2, 4)
	cam.look_at(w.global_position + Vector3.UP)
	await _shot("walker1")
	check(true, "Bilder aufgenommen")
	_finish()
