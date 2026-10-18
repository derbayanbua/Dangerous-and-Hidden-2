class_name MoviePlayer
extends Control
## Filmwiedergabe wie im Original (Gamemovie\*.bik): Vollbild auf Schwarz, Seitenverhältnis erhalten, Esc/Leertaste/
## Eingabe/Mausklick überspringt den laufenden Film (Original: Taste bricht den Film ab). Bink spielt Godot nicht ab:
## die Filme werden lokal nach orig_cache/movies/<Name>.ogv (Theora/Vorbis) konvertiert (tools/convert_movies.ps1).
## Fehlt ein Film, wird er übersprungen. Gesehene Filme merkt sich das Profil (Menü FILME).

signal finished

var queue: Array = []            ## Filmnamen ohne Endung (z. B. "BriefArctic1a")
var current := ""
var played: Array = []           ## tatsächlich abgespielte Filme (Tests)
var _vp: VideoStreamPlayer
var _was_paused := false


## Filme nacheinander abspielen; cb wird danach aufgerufen (auch wenn keiner vorhanden war).
static func play_list(parent: Node, names: Array, cb: Callable = Callable()) -> Control:
	var mp = load("res://src/ui/movie_player.gd").new()
	mp.name = "MoviePlayer"
	mp.queue = names.duplicate()
	if cb.is_valid():
		mp.finished.connect(cb)
	parent.add_child(mp)
	return mp


## Gibt es mindestens einen abspielbaren Film in der Liste?
static func any_available(names: Array) -> bool:
	for n in names:
		if Game.movie_path(String(n)) != "":
			return true
	return false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var ar := AspectRatioContainer.new()
	ar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ar.ratio = 4.0 / 3.0
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ar)
	_vp = VideoStreamPlayer.new()
	_vp.expand = true
	_vp.bus = &"Music"
	_vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.finished.connect(_next)
	ar.add_child(_vp)
	_was_paused = get_tree().paused
	_next.call_deferred()


func _next() -> void:
	if is_instance_valid(_vp):
		_vp.stop()
	while not queue.is_empty():
		var n := String(queue.pop_front())
		var p := Game.movie_path(n)
		if p == "":
			continue
		var vs := VideoStreamTheora.new()
		vs.file = p
		_vp.stream = vs
		current = n
		played.append(n)
		Game.mark_film_seen(n)
		var oa := get_node_or_null("/root/OrigAudio")
		if oa and oa.has_method("stop_music"):
			oa.call("stop_music")
		_vp.play()
		# Film nach dem Seitenverhältnis des Videos ausrichten (Originalfilme 640×480 bzw. 4:3)
		var tex := _vp.get_video_texture()
		if tex and tex.get_height() > 0:
			(_vp.get_parent() as AspectRatioContainer).ratio = float(tex.get_width()) / float(tex.get_height())
		return
	current = ""
	finished.emit()
	queue_free()


## Laufenden Film überspringen
func skip() -> void:
	_next()


func _input(event: InputEvent) -> void:
	var skip_it := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip_it = (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	elif event is InputEventMouseButton and event.pressed:
		skip_it = true
	if skip_it:
		get_viewport().set_input_as_handled()
		skip()
