extends Node
## Kontrollbilder Ausbau 11/2026 (Fenster): Haus 16 Front/Rück/Innenräume/Keller, Schützengräben innen/außen, Felddeckung.
## tools/godot.cmd -- --mission=bavaria --autoplay=screenshots_bavaria_ausbau [--tag=after] → test_output/bavaria_ausbau/<tag>_*.png
var tag := "after"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	tag = String(Game.cli.get("tag", "after"))
	var m: Mission
	while m == null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/bavaria_ausbau"))
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.fov = 70
	var h: Node3D = m.static_root.get_node("haus_16")
	var size: Vector2 = h.get_meta("footprint_size")
	var views := [
		["h16_front", Vector3(-2.0, 1.7, size.y * 0.5 + 4.2), Vector3(0, 3.2, 0)],
		["h16_back", Vector3(5.0, 1.7, -size.y * 0.5 - 8.5), Vector3(0, 2.5, -size.y * 0.5)],
		["h16_kellerhals", Vector3(0.2, 1.75, -size.y * 0.5 - 2.4), Vector3(4.5, -1.6, -size.y * 0.5 - 0.9)],
		["h16_kueche", Vector3(2.2, 1.65, 4.0), Vector3(-1.0, 1.0, 0.5)],
		["h16_wohnzimmer", Vector3(-1.9, 1.65, 4.2), Vector3(-5.5, 1.0, 0.8)],
		["h16_zimmer", Vector3(-2.0, 1.65, -0.8), Vector3(-5.5, 1.0, -3.8)],
		["h16_gang_bad", Vector3(2.2, 1.65, -1.2), Vector3(-1.0, 1.0, -3.6)],
		["h16_keller_ost", Vector3(6.0, -0.75, -4.2), Vector3(-1.0, -1.8, 2.0)],
		["h16_keller_west", Vector3(-1.5, -0.75, 1.2), Vector3(-6.0, -1.6, -3.5)],
	]
	for v in views:
		cam.global_position = h.to_global(v[1])
		cam.look_at(h.to_global(v[2]))
		await _save(cam, v[0])
	for t in get_tree().get_nodes_in_group("bavaria_trenches"):
		var fps: Array = t.get_meta("floor_points")
		var a: Vector3 = fps[1]
		var b: Vector3 = fps[2]
		cam.global_position = a + Vector3.UP * 1.55
		cam.look_at(b + Vector3.UP * 1.2)
		await _save(cam, String(t.name) + "_innen")
		var ledge: Dictionary = t.get_meta("ledges")[0]
		cam.global_position = ledge.stand + Vector3.UP * 1.55
		cam.look_at(ledge.stand + ledge.out * 20.0 + Vector3.UP * 1.0)
		await _save(cam, String(t.name) + "_schuetzenauftritt")
		var mid: Vector3 = (a + b) * 0.5
		cam.global_position = Vector3(mid.x, 1.7, mid.z) - ledge.out * 9.0 + Vector3(2, 0, 2)
		cam.look_at(Vector3(mid.x, -0.4, mid.z))
		await _save(cam, String(t.name) + "_aussen")
	var covers := get_tree().get_nodes_in_group("bavaria_field_cover")
	for i in mini(covers.size(), 6):
		var c: Node3D = covers[i]
		cam.global_position = c.global_position + Vector3(5, 1.7, 5)
		cam.look_at(c.global_position + Vector3.UP * 0.6)
		await _save(cam, "feld_" + String(c.get_meta("cover_kind")) + "_" + str(i))
	cam.global_position = Vector3(-22, 14, 14)
	cam.look_at(Vector3(-24, 0, -18))
	await _save(cam, "feld_uebersicht")
	print("ERGEBNIS screenshots_bavaria_ausbau: fertig")
	get_tree().quit(0)

func _save(camera: Camera3D, id: String) -> void:
	camera.reset_physics_interpolation()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_ausbau/" + tag + "_" + id + ".png")
	print("SHOT ", id)
