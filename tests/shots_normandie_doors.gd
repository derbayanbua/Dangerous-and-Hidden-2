extends Node
## Diagnose/Kontrollbilder (Fenster): Türen am deutschen Spawn von Normandy2 (Besetzung, Operation Schwerttänzer).
##   tools\godot.cmd -- --autoplay=shots_normandie_doors [--map=mp_normandy2_mp_zone] --resolution 1280x720
##   → test_output/normandie_doors_*.png, Protokoll in der Konsole (DOOR …)

const OUT := "res://test_output/normandie_doors_%s.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", OUT % name, " ", img.get_size())


func _wait(cond: Callable, s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until and not cond.call():
		await get_tree().create_timer(0.1).timeout


func _run() -> void:
	var map := String(Game.cli.get("map", "mp_normandy2_mp_zone"))
	Net.local_name = "Achse"
	Net.local_team = Soldier.TEAM_AXIS
	Net.host({"name": "Shots", "map": map, "mode": Net.Mode.OCCUPATION, "port": Net.PORT + 52,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0,
		"password": "", "allow_vehicles": false})
	await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await get_tree().create_timer(2.0).timeout
	var me: Soldier = Net._soldiers.get(1)
	print("DOOR me at ", me.global_position, " team ", me.team)
	var it: OrigInteractive = m.get("interactive")
	print("DOOR stats ", it.stats if it else "-")
	var center := Vector3(36.0, 0.5, 86.5)
	for k in it.controls:
		var c = it.controls[k]
		if c is OrigInteractive.OrigDoor:
			print("DOOR ctl %s pos %s dist %.1f state %d" % [k, c.global_position, c.global_position.distance_to(center), c.state])
	for nm in ["m_H19", "m_H20", "m_H27", "m_H28", "m_H31", "m_H32", "m_H33", "m_H35", "m_H36", "m_H38", "m_H39", "dhandle"]:
		var f: Node3D = m.orig.nodes.get(nm) if m.orig else null
		if f == null:
			print("DOOR frame %s fehlt" % nm)
			continue
		var bodies := f.find_children("*", "CollisionObject3D", true, false)
		var box := OrigInteractive.world_aabb(f)
		print("DOOR frame %s vis %s par %s aabb %s bodies %d" % [nm, f.is_visible_in_tree(), f.get_parent().name, box, bodies.size()])
	m.controller.input_enabled = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	m.add_child(cam)
	cam.current = true
	if m.get("hud"):
		m.hud.visible = false
	var hud = m.get_node_or_null("MpHud")
	if hud:
		hud.visible = false
	me.global_position = Vector3(48.7, 0.4, 85.2)
	var views := [
		["in1", Vector3(37.0, 1.6, 87.0), Vector3(33.0, 1.4, 86.0)],
		["in2", Vector3(37.0, 1.6, 87.0), Vector3(41.0, 1.4, 86.0)],
		["in3", Vector3(37.0, 1.6, 87.0), Vector3(37.0, 1.4, 83.0)],
		["in4", Vector3(37.0, 1.6, 87.0), Vector3(37.0, 1.4, 91.0)],
		["out_s", Vector3(36.0, 2.0, 78.0), Vector3(36.0, 1.4, 86.0)],
		["out_w", Vector3(26.0, 2.0, 86.0), Vector3(35.0, 1.4, 86.0)],
		["out_e", Vector3(48.0, 2.0, 86.0), Vector3(38.0, 1.4, 86.0)],
		["top", Vector3(36.0, 25.0, 80.0), Vector3(36.0, 0.0, 86.5)],
	]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		await _save(v[0])
	Net.leave(false)
	get_tree().quit(0)
