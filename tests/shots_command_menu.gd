extends "res://tests/test_systems.gd"
## B-019 Kontrollbilder des Befehlsmenüs im Original-Frame „rollmenu“ (NUR IM FENSTER, nicht headless):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_command_menu
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_command_menu
## → test_output/b019_menu_<mission>_{main,bewegung,formation,aktion_tuer,aktion_gegner,einzel,pfeil}.png


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var mid := String(Game.current_mission_id) if "current_mission_id" in Game else "mission"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var path := "res://test_output/b019_menu_%s_%s.png" % [mid, tag]
	img.save_png(path)
	print("BILD ", path)


func _open(cm: CommandMenu, target: int, digits: Array) -> void:
	cm.open_for(target)
	await frames(2)
	for d in digits:
		cm.press_digit(int(d))
		await frames(2)


func _run() -> void:
	for i in 900:
		if mission() and mission().squad and mission().squad.leader() and mission().controller.input_enabled:
			break
		await get_tree().process_frame
	var m := mission()
	if m == null:
		check(false, "Mission geladen")
		_finish()
		return
	for i in 1500:
		if m.nav_ready:
			break
		await frames(1)
	await seconds(1.0)
	var cm: CommandMenu = m.controller.command_menu
	await _open(cm, -1, [])
	await _shot("main")
	cm.press_digit(1)
	await _shot("bewegung")
	cm.press_digit(0)
	cm.press_digit(7)
	await _shot("formation")
	cm.close()
	# Aktion an der nächsten Tür und am nächsten Gegner
	var door: Node3D = null
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Door or n is OrigInteractive.OrigDoor:
			if door == null or (n as Node3D).global_position.distance_to(m.squad.leader().global_position) < door.global_position.distance_to(m.squad.leader().global_position):
				door = n
	if door:
		cm.context_override = door
		await _open(cm, -1, [3])
		await _shot("aktion_tuer")
		cm.close()
	if not m.enemies.is_empty():
		cm.context_override = m.enemies[0]
		await _open(cm, -1, [3])
		await _shot("aktion_gegner")
		cm.close()
	cm.context_override = null
	if m.squad.members.size() > 1:
		await _open(cm, 1, [])
		await _shot("einzel")
		cm.close()
	# Folgen: Pfeil-Formation nach 4 s Laufen (Abstand/Plätze sichtbar)
	m.squad.set_formation(SquadManager.Formation.WEDGE)
	for mm in m.squad.members:
		if mm != m.squad.leader():
			m.squad.brain_of(mm).set_order(SquadBrain.Order.FOLLOW)
	Input.action_press("move_forward")
	await seconds(4.0)
	Input.action_release("move_forward")
	await seconds(2.0)
	await _shot("pfeil")
	check(true, "Kontrollbilder erzeugt")
	_finish()
