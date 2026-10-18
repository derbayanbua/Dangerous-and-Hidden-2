extends "res://tests/menu_shots.gd"
## Kontrollbilder (Fenster) der Filmwiedergabe:  tools\godot.cmd -- --autoplay=movie_shots --profiles_dir=user://test_shots_movie --noimport


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	for n in ["Intro", "BriefArctic1a"]:
		var mp = load("res://src/ui/movie_player.gd").play_list(get_tree().root, [n])
		await get_tree().create_timer(6.0).timeout
		await shot("film_" + n)
		if is_instance_valid(mp):
			mp.skip()
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
