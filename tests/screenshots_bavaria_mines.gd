extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m: Mission
	while m==null or not m.nav_ready or not m.prank_mines.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	for actor in get_tree().get_nodes_in_group("soldiers"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var mine: Node3D = m.prank_mines.mines[1]
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.global_position = mine.global_position+Vector3(1.8,1.7,2.2)
	cam.look_at(mine.global_position+Vector3.UP*0.3)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_mine_before.png")
	m.prank_mines.trigger(1)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_mine_smoke.png")
	get_tree().quit()
