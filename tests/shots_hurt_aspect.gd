extends Node
## Treffer-Richtungsbogen in verschiedenen Seitenverhältnissen (Fenster, nicht kopflos):
##   tools\godot.cmd -- --autoplay=shots_hurt_aspect
##   → test_output/mp_hurt_{16x9,16x10,21x9,4x3}.png und mp_hurt_aspect.txt (Fenster-/Oberflächengröße, Kreis-
##     Mittelpunkt gegen Fadenkreuz, Skalierung x/y der Zeichenfläche). Host allein auf einer Arena-Karte; drei
##     Treffermeldungen (vorn, rechts hinten, links) über Net._hurt_from mit festgehaltener Anzeigezeit.

const OUT := "res://test_output/%s"
const MAP := "mp_arena_a1_blizzard"
const ASPECTS := [["16x9", 16.0 / 9.0], ["16x10", 1.6], ["21x9", 64.0 / 27.0], ["4x3", 4.0 / 3.0]]

var report: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_quit_fail)
	_run.call_deferred()


func _quit_fail() -> void:
	get_tree().quit(1)


func _loaded() -> bool:
	var m = Game.current_mission()
	return m != null and m.is_node_ready() and Net._soldiers.has(1) and m.get_node_or_null("MpHud") != null


func _run() -> void:
	Net.local_name = "Spieler"
	Net.host({"name": "Aspect", "map": MAP, "mode": Net.Mode.DEATHMATCH, "port": Net.PORT + 49, "max_players": 4,
		"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0, "password": ""})
	var until := Time.get_ticks_msec() + 400000
	while not _loaded() and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.2).timeout
	var m = Game.current_mission()
	var me: Soldier = Net._soldiers.get(1)
	me.set_meta("protect_until", Time.get_ticks_msec() + 900000)
	m.controller.input_enabled = false
	var fb = m.get_node("MpHud").feedback
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	report.append("Bildschirm %s, nutzbar %s" % [screen, usable])
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
		# drei Treffer: vorn, rechts hinten, links (relativ zur Blickrichtung des Soldaten)
		var fwd := me.forward()
		var right := fwd.cross(Vector3.UP).normalized()
		var p := me.global_position
		var now := Time.get_ticks_msec() + 3000       # Anzeige für das Standbild festhalten (Bildrate unter Last gering)
		fb._hurts.clear()
		for pos in [p + fwd * 12.0, p + (right - fwd).normalized() * 12.0, p - right * 12.0]:
			Net._hurt_from(pos)
		for hh in fb._hurts:
			hh["ms"] = now
		await get_tree().process_frame
		var win := DisplayServer.window_get_size()
		var area: Vector2 = fb.size
		var xf: Transform2D = fb.get_global_transform_with_canvas()
		var g: Dictionary = fb.hurt_arc_geometry(area, 0.0)
		var hud = m.get("hud")
		var ch: Control = hud.get("_crosshair") if hud else null
		var ch_c: Vector2 = ch.get_global_rect().get_center() if ch else Vector2(-1, -1)
		var fb_c: Vector2 = fb.get_global_rect().position + g["center"]
		report.append("%s: Fenster %s (%.3f), Fläche %s (%.3f), Skalierung x %.3f / y %.3f, Bogenmitte %s, Fadenkreuz %s, Radius %.0f" % [
			asp[0], win, float(win.x) / float(win.y), area, area.x / area.y, xf.get_scale().x, xf.get_scale().y, fb_c, ch_c, float(g["radius"])])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT % ("mp_hurt_%s.png" % asp[0])))
		print("SHOT mp_hurt_%s.png %s" % [asp[0], img.get_size()])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT % "mp_hurt_aspect.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	print("\n".join(report))
	Net.leave(false)
	get_tree().quit(0)
