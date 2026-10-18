class_name FpsOverlay
extends CanvasLayer
## Optionale Bildraten-Anzeige (Ergänzung, kein Original-Element): kleine Zahl in der linken oberen Bildschirmecke,
## in Menüs, Einzel- und Mehrspieler. Schalter Settings.show_fps (Optionen SPIEL „FPS ANZEIGEN“, Standard aus),
## MP-Konsole „fps [0|1]“, Kommandozeile --fps=1. Hängt am Autoload Settings (immer vorhanden).

var label: Label
var _t := 0.0


func _ready() -> void:
	name = "FpsOverlay"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.name = "Fps"
	label.position = Vector2(6, 2)
	label.size = Vector2(120, 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.6))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	visible = Settings.show_fps
	_refresh()


func _process(delta: float) -> void:
	visible = Settings.show_fps
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh()


func _refresh() -> void:
	label.text = "%d FPS" % int(round(Engine.get_frames_per_second()))
