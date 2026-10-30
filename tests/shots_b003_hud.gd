extends Node
## B-003 Kontrollbilder der ergänzten Original-HUD-Elemente (Fenster, NICHT kopflos):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_b003_hud
##   → test_output/b003_hud_{gesamt,feld,kompass,fortschritt}.png
## Gezeigt: Originalschrift im Waffenfeld (Stile 0x36–0x39), Befehls-/Stimmungssymbole der Kameraden (command*/mind*),
## Kompass-Sektoren rot/blau, Fortschrittsbalken (Arbeit, Atemluft), Aktionssymbol am Benutzen-Ziel, Name am Fadenkreuz.

const OUT := "res://test_output/%s"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _shot(name: String, crop := Rect2()) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop.size.x > 1.0:
		img = img.get_region(Rect2i(crop.intersection(Rect2(Vector2.ZERO, img.get_size()))))
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", name, " ", img.get_size())


func _run() -> void:
	var until := Time.get_ticks_msec() + 300000
	var m: Mission = null
	while Time.get_ticks_msec() < until:
		m = Game.current_mission() as Mission
		if m and m.is_node_ready() and m.find_child("OrigHud", true, false) != null and m.controller and m.controller.active:
			break
		await get_tree().create_timer(0.2).timeout
	var hud := m.find_child("OrigHud", true, false) as OrigHud if m else null
	if hud == null:
		print("Kein OrigHud")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().create_timer(1.0).timeout
	var s := m.controller.active
	var sq := m.squad
	# Kameraden: verschiedene Befehle/Feuerregeln, einer legt einen Verband an
	var mates := sq.alive_members().filter(func(x): return x != s)
	if mates.size() > 0:
		sq.brain_of(mates[0]).set_order(SquadBrain.Order.HOLD)
		sq.brain_of(mates[0]).roe = SquadBrain.ROE.HOLD_FIRE
	if mates.size() > 1:
		sq.brain_of(mates[1]).set_order(SquadBrain.Order.MOVE, mates[1].global_position + Vector3(3, 0, 0))
	if mates.size() > 2:
		mates[2].heal_time_left = 30.0
	# Name am Fadenkreuz: Kamera auf den ersten Kameraden richten
	if mates.size() > 0:
		var to: Vector3 = mates[0].global_position - s.global_position
		s.look_yaw = atan2(-to.x, -to.z)
	# Kompass-Sektoren: Treffer von rechts, Schuss von links
	var right := s.global_position + Vector3(cos(-s.look_yaw), 0, sin(-s.look_yaw)) * 10.0
	var kr := hud._sector_of(right, "rd")
	if kr >= 0:
		hud.sector_rd[kr] = 60.0
	var kb := hud._sector_of(s.global_position - (right - s.global_position), "bl")
	if kb >= 0:
		hud.sector_bl[kb] = 60.0
	# Arbeit (Fortschrittsbalken) + Aktionssymbol
	s.work_total = 4.0
	s.work_left = 1.4
	s.work_label = "Entschärfen"
	await get_tree().create_timer(0.8).timeout
	hud.sector_rd[maxi(kr, 0)] = 60.0
	hud.sector_bl[maxi(kb, 0)] = 60.0
	var vs := hud.size
	await _shot("b003_hud_gesamt.png")
	await _shot("b003_hud_feld.png", Rect2(0, vs.y * 0.86, vs.x, vs.y * 0.14))
	await _shot("b003_hud_kompass.png", Rect2(0, 0, vs.y * 0.2, vs.y * 0.2))
	await _shot("b003_hud_fortschritt.png", Rect2(vs.x * 0.25, vs.y * 0.45, vs.x * 0.5, vs.y * 0.45))
	s.work_total = 0.0
	s.work_left = 0.0
	print("Fadenkreuzname: ", hud.cross_name_text, "  Aktionssymbol: ", hud.action_icon_file, "  Sektoren ", kr, "/", kb)
	get_tree().quit(0)
