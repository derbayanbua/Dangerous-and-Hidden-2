extends CanvasLayer
## Pausemenü (Esc): Fortsetzen, Speichern, Laden, Optionen, Hauptmenü.
## Schnellspeichern/-laden (F5/F9) wird ebenfalls hier behandelt.

var _root: Control
var _open := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var v := UIKit.centered_panel(_root)
	UIKit.title("PAUSE", 30, v)
	UIKit.button("Fortsetzen", close, v)
	UIKit.button("Schnellspeichern (F5)", func():
		Game.save_game("quick")
		close(), v)
	UIKit.button("Schnellladen (F9)", func(): Game.load_game("quick"), v)
	UIKit.button("Optionen", _options, v)
	UIKit.button("Mission neu starten", func(): Game.start_mission(Game.current_mission_id), v)
	UIKit.button("Zum Hauptmenü", Game.return_to_menu, v)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quicksave") and not _open:
		Game.save_game("quick")
	elif event.is_action_pressed("quickload"):
		Game.load_game("quick")


func open() -> void:
	var m := Game.current_mission()
	if m and (m.finished or (m.tactical_map and m.tactical_map.is_open)):
		return
	_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _options() -> void:
	var o = load("res://src/ui/options_menu.gd").new()
	_root.add_child(o)
