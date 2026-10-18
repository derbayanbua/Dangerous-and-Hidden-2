extends "res://tests/lan_ui_base.gd"
## Kontrollbilder SPIELER-SETUP aus dem LAN-Menü (Fenster): tools\godot.cmd --resolution 1600x900 -- --autoplay=shots_player_setup
## --profiles_dir=user://shots_ps --noimport → test_output/ps_lan_<breite>_*.png


func _run() -> void:
	var menu := await menu_with_profile("Bild")
	menu.open_lan()
	await frames(10)
	var lm: LanMenu = menu.lan_menu
	lm.open_player_setup()
	await frames(20)
	var w := int(get_viewport().get_visible_rect().size.x)
	await _shot("ps_lan_%d_1" % w)
	var ps = lm.player_setup
	ps._toggle("class")
	await frames(5)
	await _shot("ps_lan_%d_2_klassen" % w)
	ps._toggle("class")
	ps._toggle("items")
	await frames(5)
	await _shot("ps_lan_%d_3_kategorien" % w)
	_finish()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/%s.png" % n))
	check(true, n)
