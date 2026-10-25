extends Node
## fix_a2_marker: Kontrollbilder ARCTIC2 (Fenster, NICHT kopflos):
##   tools\godot.cmd -- --mission=a2_erkundung --autoplay=shots_a2_marker
##   → test_output/a2_marker_{1_freigabe,2_zeitzuender,3_randpfeile,4_aus}.png

const OUT := "res://test_output/a2_marker_%s.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _shot(nm: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % nm))
	print("SHOT ", nm, " ", img.get_size())


func _run() -> void:
	var until := Time.get_ticks_msec() + 300000
	var m: OrigMission = null
	while Time.get_ticks_msec() < until:
		m = Game.current_mission() as OrigMission
		if m and m.is_node_ready() and m.interactive and m.squad and m.squad.leader():
			break
		await get_tree().create_timer(0.2).timeout
	if m == null:
		get_tree().quit(1)
		return
	m.runtime.auto_skip = true
	for i in 30:
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
		await get_tree().create_timer(0.2).timeout
	m.runtime.auto_skip = false
	print("cutscene ", m.runtime.in_cutscene, " hud ", m.hud.visible)
	var s: Soldier = m.squad.leader()
	var bum := m.interactive.controls["BUM1"] as OrigInteractive.OrigExplosive
	var dvm: LsVM = null
	for vm in m.runtime.vms:
		if vm.name.to_lower().find("dynamit_1") >= 0:
			dvm = vm
	var anchor: Vector3 = dvm.me.global_position if dvm else bum.global_position
	# 2,5 m vor dem Platz, Blick auf den Platz
	var dir := (bum.global_position - anchor)
	dir.y = 0.0
	var away: Vector3 = Vector3(2.5, 0, 0) if dir.length() < 0.5 else -dir.normalized() * 2.5
	for i in 30:
		s.global_position = bum.global_position + away
		var to := bum.global_position - s.global_position
		s.look_yaw = atan2(-to.x, -to.z)
		s.look_pitch = -0.35
		await get_tree().create_timer(0.1).timeout
		if bum.state == 0:
			break
	print("BUM1 state ", bum.state)
	await get_tree().create_timer(0.5).timeout
	await _shot("1_freigabe")
	bum.interact(s)
	for i in 40:
		s.global_position = bum.global_position + away
		await get_tree().create_timer(0.1).timeout
		if bum.state == 1:
			break
	await get_tree().create_timer(2.0).timeout
	await _shot("2_zeitzuender")
	s.look_yaw += PI * 0.75
	s.look_pitch = 0.0
	await get_tree().create_timer(0.5).timeout
	await _shot("3_randpfeile")
	Settings.objective_markers = false
	await get_tree().create_timer(0.5).timeout
	await _shot("4_aus")
	Settings.objective_markers = true
	get_tree().quit(0)
