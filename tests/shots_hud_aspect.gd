extends Node
## B-014: Original-HUD an den echten Bildschirmrändern je Seitenverhältnis (Fenster, NICHT kopflos):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_hud_aspect
##   → test_output/hud_aspect_{16x9,16x10,21x9,4x3}.png und hud_aspect.txt (Fenstergröße, Lage von Truppleiste,
##     Waffenfeld, Kompass, Haltungsfeld). Erwartung: Haltungsfeld/Kompass am linken, Waffenfeld am rechten Rand;
##     bei 4:3 dieselbe Lage wie vor B-014 (4:3-Rahmen = ganze Breite).

const OUT := "res://test_output/%s"
const ASPECTS := [["16x9", 16.0 / 9.0], ["16x10", 1.6], ["21x9", 64.0 / 27.0], ["4x3", 4.0 / 3.0]]
const PROBES := ["tabl01", "soldier00", "soldier05", "tabl02", "i_hands", "kompas", "tabl03"]

var report: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _run() -> void:
	var until := Time.get_ticks_msec() + 300000
	var m: Mission = null
	while Time.get_ticks_msec() < until:
		m = Game.current_mission() as Mission
		if m and m.is_node_ready() and m.find_child("OrigHud", true, false) != null:
			break
		await get_tree().create_timer(0.2).timeout
	if m == null:
		get_tree().quit(1)
		return
	var hud := m.find_child("OrigHud", true, false) as OrigHud
	if hud == null:
		print("Kein OrigHud (orig_cache/ui/hud fehlt)")
		get_tree().quit(1)
		return
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for asp in ASPECTS:
		var h := mini(720, usable.y - 80)
		var w := int(round(h * float(asp[1])))
		if w > usable.x - 40:
			w = usable.x - 40
			h = int(round(w / float(asp[1])))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(w, h))
		for i in 8:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		var line := "%s: Fenster %s, HUD %s" % [asp[0], DisplayServer.window_get_size(), hud.size]
		for nm in PROBES:
			if hud.elements.has(nm):
				var r: Rect2 = hud.elements[nm].get("screen", Rect2())
				line += ", %s x %.0f–%.0f" % [nm, r.position.x, r.end.x]
		report.append(line)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT % ("hud_aspect_%s.png" % asp[0])))
		print("SHOT hud_aspect_%s.png %s" % [asp[0], img.get_size()])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT % "hud_aspect.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	print("\n".join(report))
	get_tree().quit(0)
