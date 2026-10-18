extends "res://tests/test_gameplay.gd"
## Filme: alle Original-Filme (HD2_orig\Gamemovie\*.bik) konvertiert (orig_cache/movies/*.ogv) und abspielbar;
## Menü FILME, Abspieler (Überspringen), Verwundungs-Overlay AnimHit (HUD).
##   tools\godot.cmd --headless -- --autoplay=test_movies --profiles_dir=user://test_movies --noimport


func _run() -> void:
	await frames(10)
	var names: Array = []
	var d := DirAccess.open("D:/Workspace_D/HD2_orig/Gamemovie")
	if d:
		for f in d.get_files():
			if f.get_extension().to_lower() == "bik":
				names.append(f.get_basename())
	names.sort()
	check(names.size() == 47, "47 Original-Filme gefunden", str(names.size()))
	var missing: Array = []
	var broken: Array = []
	var vp := VideoStreamPlayer.new()
	vp.volume_db = -80.0
	get_tree().root.add_child(vp)
	for n in names:
		var p := Game.movie_path(n)
		if p == "":
			missing.append(n)
			continue
		var vs := VideoStreamTheora.new()
		vs.file = p
		vp.stream = vs
		vp.play()
		var ok := false
		for i in 40:
			await get_tree().process_frame
			if vp.is_playing() and vp.stream_position > 0.0:
				ok = true
				break
		var len := vp.get_stream_length()
		vp.stop()
		if not ok or len <= 0.0:
			broken.append("%s (%.2f s)" % [n, len])
	check(missing.is_empty(), "Alle Filme konvertiert (orig_cache/movies)", ", ".join(missing))
	check(broken.is_empty(), "Alle Filme abspielbar (Theora läuft, Länge > 0)", ", ".join(broken))
	vp.queue_free()

	# Abspieler: Liste nacheinander, Überspringen per Taste
	var played: Array = []
	var done := [false]
	var mp = load("res://src/ui/movie_player.gd").play_list(get_tree().root, ["Logo1", "Fehlt", "Logo2"], func(): done[0] = true)
	await frames(5)
	check(mp.current == "Logo1", "Abspieler startet den ersten Film", String(mp.current))
	mp.skip()
	await frames(3)
	check(mp.current == "Logo2", "Überspringen: fehlender Film wird ausgelassen, nächster läuft", String(mp.current))
	played = mp.played.duplicate()
	mp.skip()
	await frames(5)
	check(done[0] and played == ["Logo1", "Logo2"], "Liste beendet, Rückruf ausgeführt", str(played))

	# Menü FILME: SPIELEN freigegeben, sobald der Film konvertiert ist
	var menu := get_tree().current_scene
	Game.create_profile("Filme", 2)
	menu.show_menu("cinematics")
	await frames(2)
	(menu.find_child("film_Intro", true, false) as Button).pressed.emit()
	await frames(2)
	var play := menu.find_child("PlayFilm", true, false) as Button
	check(play != null and not play.disabled, "FILME: SPIELEN für das Intro freigegeben")
	play.pressed.emit()
	await frames(5)
	var mp2 := menu.find_child("MoviePlayer", true, false)
	check(mp2 != null and String(mp2.get("current")) == "Intro", "FILME: Intro wird abgespielt")
	if mp2:
		mp2.skip()
	await frames(5)
	check(Game.mission_videos("af1_spaghetti_airport") == ["BriefAfrica1"] and Game.movie_path("BriefAfrica1") != "",
		"Briefing-Video vor Afrika 1 vorhanden")
	Game.delete_profile("Filme")
	# Filmtexturen im Level (meshplayer.bin): ARCTIC1 Wasserfläche QuadPatch01 mit Arctic1.bik
	Game.start_mission("a1_blizzard")
	var m: Node = null
	for i in 3000:
		await get_tree().process_frame
		m = Game.current_mission()
		if m and m.get("orig") != null and m.get("squad") and m.squad.leader():
			break
	var mt: Array = m.get("movie_textures") if m else []
	check(mt.size() == 1 and mt[0][0] == "Arctic1" and mt[0][1] == "QuadPatch01", "ARCTIC1: Wasserfläche mit Filmtextur Arctic1.bik", str(mt))
	var vp2: VideoStreamPlayer = null
	if m:
		vp2 = m.find_child("MovieTexture_Arctic1", true, false) as VideoStreamPlayer
	await frames(10)
	check(vp2 != null and vp2.is_playing() and vp2.loop, "Filmtextur läuft in Schleife")
	_finish()
