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
	await shot("01_main")
	var menu := get_tree().current_scene
	menu._show_briefing("m01_funkfeuer")
	await shot("02_briefing")
	menu._brief_root.queue_free()
	menu._menu.get_parent().get_parent().visible = true
	menu._options()
	await shot("03_options")
	var opts := menu.get_child(menu.get_child_count() - 1)
	var tabs: TabContainer = opts.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	await shot("04_keys")
	get_tree().quit()
