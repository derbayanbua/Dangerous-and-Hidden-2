extends Node
## Kontrollbilder der Menüs:  tools\godot.cmd -- --autoplay=menu_shots

const OUT := "res://test_output/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "menu_%s.png" % name)
	print("SHOT ", name)


func _run() -> void:
	var menu := get_tree().current_scene
	await shot("01_main")
	menu.show_menu("singleplayer")
	await shot("02_singleplayer")
	menu.show_menu("campaign")
	await shot("03_campaign")
	menu.show_menu("options")
	await shot("04_options")
	menu._show_briefing("a1_blizzard")
	await shot("05_briefing")
	get_tree().quit()
