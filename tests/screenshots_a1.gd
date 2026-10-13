extends "res://tests/screenshots.gd"
## Kontrollbilder Original-Mission Arctic 1A:
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=screenshots_a1


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 900:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	var hale := m.squad.leader()
	await frames(60)
	await shot("a1_01_start")
	# Luftbild über dem Zauntor (Gate_Guard)
	var gate: Dictionary = m.orig.actor("Gate_Guard")
	var gp: Vector3 = OrigLevel.xform(gate).origin if not gate.is_empty() else Vector3.ZERO
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.global_position = gp + Vector3(0, 90, 70)
	cam.look_at(gp)
	cam.far = 2000
	cam.current = true
	await frames(30)
	await shot("a1_02_aerial_gate")
	cam.global_position = gp + Vector3(0, 300, 1)
	cam.look_at(gp)
	await frames(30)
	await shot("a1_03_overview")
	# Bodennah am Tor
	cam.global_position = gp + Vector3(12, 2.5, 18)
	cam.look_at(gp + Vector3.UP * 1.5)
	await frames(30)
	await shot("a1_04_gate_ground")
	# Original-Figuren aus der Nähe: Torwache von vorn (Blickrichtung prüfen), Kommandos
	var rt: LsRuntime = m.ls_runtime
	if rt and rt.in_cutscene:
		rt.end_cutscene()
	cam.current = true
	var gg := rt.actors.get("GATE_GUARD") as Soldier if rt else null
	if gg:
		cam.global_position = gg.global_position + gg.forward() * 3.0 + Vector3.UP * 1.6
		cam.look_at(gg.global_position + Vector3.UP * 1.0)
		await frames(30)
		await shot("a1_05_guard_front")
	cam.global_position = hale.global_position + hale.forward() * 4.0 + Vector3(1.5, 1.8, 0)
	cam.look_at(hale.global_position + Vector3.UP * 1.0)
	await frames(30)
	await shot("a1_06_squad_front")
	get_tree().quit()
