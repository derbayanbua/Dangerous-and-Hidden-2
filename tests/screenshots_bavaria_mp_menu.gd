extends Node
## Tatsächliche normale MP-Hauptauswahl für die Anleitung aufnehmen.
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	for i in 5:
		await get_tree().process_frame
	var menu = get_tree().current_scene
	menu.open_lan()
	var lm: LanMenu = menu.lan_menu
	for mode in [0,1]:
		lm._map.select(mode)
		lm._sync_mode()
		var id: String = lm._map.get_item_metadata(mode)
		var expected := "bavaria" if mode==0 else "bavaria_occupation"
		if id!=expected or lm._mode.selected!=(0 if mode==0 else 2) or not lm.map_rotation().has(id):
			push_error("Bavaria fehlt in normaler Karten-/Modusauswahl")
			get_tree().quit(1)
			return
		print("MP MAIN LIST ",mode,": ",lm._map.get_item_text(mode)," -> ",id," mode=",lm._mode.selected)
		if DisplayServer.get_name()!="headless":
			for i in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://test_output/bavaria_mp_main_list_"+str(mode)+".png")
	Net.stop_browse()
	get_tree().quit()
