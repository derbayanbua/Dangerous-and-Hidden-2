extends Node
## Persistente Benutzereinstellungen (user://settings.cfg): Grafik, Anzeige,
## Maus. Tastenbelegung verwaltet InputSetup in derselben Datei.

signal changed

const PATH := "user://settings.cfg"

## Vector2i.ZERO = Desktop-Auflösung (nativ). Oberfläche skaliert mit (stretch canvas_items, Basis 1280×720,
## Seitenverhältnis frei), Schriften als MSDF scharf in jeder Größe; 3D rendert nativ (bzw. render_scale).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440),
	Vector2i(3840, 1600), Vector2i(3840, 2160), Vector2i(5120, 2160),
]
const QUALITY_NAMES: PackedStringArray = ["Niedrig", "Mittel", "Hoch", "Ultra"]

var resolution := Vector2i.ZERO
var fullscreen := true
var vsync := true
var quality := 2           ## 0..3, siehe QUALITY_NAMES
var render_scale := 1.0    ## 0.5..1.0 (FSR 1 bei < 1)
var fov := 70.0
var mouse_sensitivity := 0.12
var invert_y := false
var master_volume := 0.8      ## Original „Sound-Lautstärke“ (Gesamt)
var music_volume := 0.7       ## Original „Musik-Lautstärke“ (Bus „Music“)
var gamma := 1.0              ## Original „Gamma-Korrektur“ (0,6 … 1,6)
var shadows := true           ## Original „SCHATTEN“
var subtitles := true         ## Original „UNTERTITEL“
var crosshair := true         ## Original v1.12 „FADENKREUZ ZULASSEN“

var _cfg := ConfigFile.new()


func _ready() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	apply()


func load_settings() -> void:
	if _cfg.load(PATH) != OK:
		return
	resolution = _cfg.get_value("display", "resolution", resolution)
	fullscreen = _cfg.get_value("display", "fullscreen", fullscreen)
	vsync = _cfg.get_value("display", "vsync", vsync)
	quality = _cfg.get_value("graphics", "quality", quality)
	render_scale = _cfg.get_value("graphics", "render_scale", render_scale)
	fov = _cfg.get_value("graphics", "fov", fov)
	mouse_sensitivity = _cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = _cfg.get_value("controls", "invert_y", invert_y)
	master_volume = _cfg.get_value("audio", "master_volume", master_volume)
	music_volume = _cfg.get_value("audio", "music_volume", music_volume)
	gamma = _cfg.get_value("graphics", "gamma", gamma)
	shadows = _cfg.get_value("graphics", "shadows", shadows)
	subtitles = _cfg.get_value("game", "subtitles", subtitles)
	crosshair = _cfg.get_value("game", "crosshair", crosshair)


func save_settings() -> void:
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return   # Tests verändern die Benutzereinstellungen nicht
	_cfg.load(PATH)  # vorhandene Sektionen (z. B. Tastenbelegung) erhalten
	_cfg.set_value("display", "resolution", resolution)
	_cfg.set_value("display", "fullscreen", fullscreen)
	_cfg.set_value("display", "vsync", vsync)
	_cfg.set_value("graphics", "quality", quality)
	_cfg.set_value("graphics", "render_scale", render_scale)
	_cfg.set_value("graphics", "fov", fov)
	_cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	_cfg.set_value("controls", "invert_y", invert_y)
	_cfg.set_value("audio", "master_volume", master_volume)
	_cfg.set_value("audio", "music_volume", music_volume)
	_cfg.set_value("graphics", "gamma", gamma)
	_cfg.set_value("graphics", "shadows", shadows)
	_cfg.set_value("game", "subtitles", subtitles)
	_cfg.set_value("game", "crosshair", crosshair)
	_cfg.save(PATH)


func apply() -> void:
	_apply_audio()
	if DisplayServer.get_name() == "headless":
		changed.emit()
		return
	# Kommandozeile (--resolution, Tests mit --autoplay) bestimmt das Fenster selbst
	var cli_window := OS.get_cmdline_args().has("--resolution") or "--autoplay" in " ".join(OS.get_cmdline_user_args())
	var screen := DisplayServer.screen_get_size()
	var res := effective_resolution()
	var scale_3d := render_scale
	if cli_window:
		pass
	elif fullscreen:
		# Vollbild immer in Desktop-Auflösung (scharfe Oberfläche); kleinere Wahl wirkt als 3D-Auflösung
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if res.y < screen.y:
			scale_3d *= float(res.y) / float(screen.y)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		res = res.min(screen)
		DisplayServer.window_set_size(res)
		DisplayServer.window_set_position((screen - res) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(scale_3d, 0.25, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vp.scaling_3d_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	changed.emit()


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.0001)))


func effective_resolution() -> Vector2i:
	if resolution == Vector2i.ZERO or DisplayServer.get_name() == "headless":
		return DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	return resolution


static func resolution_name(r: Vector2i) -> String:
	if r == Vector2i.ZERO:
		return "Desktop (nativ)"
	var g := _gcd(r.x, r.y)
	var aspect := "%d:%d" % [r.x / g, r.y / g]
	aspect = String({"683:384": "16:9", "64:27": "21:9", "43:18": "21:9", "12:5": "21:9", "8:5": "16:10"}.get(aspect, aspect))
	var tag := String({1280: " HD", 1920: " Full HD", 2560: " WQHD", 3840: " 4K UHD", 5120: " 5K"}.get(r.x, "")) if aspect == "16:9" else ""
	return "%d × %d (%s)%s" % [r.x, r.y, aspect, tag]


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


## Wendet die Qualitätsstufe auf ein WorldEnvironment und die Sonne an.
## Wird von der Mission beim Laden und bei jeder Änderung aufgerufen.
func apply_to_world(env: Environment, sun: DirectionalLight3D) -> void:
	if env:
		env.adjustment_enabled = not is_equal_approx(gamma, 1.0)
		env.adjustment_brightness = gamma
		env.ssao_enabled = quality >= 1
		env.ssil_enabled = quality >= 3
		env.sdfgi_enabled = quality >= 3
		env.glow_enabled = quality >= 1
		env.volumetric_fog_enabled = quality >= 2
	if sun:
		sun.shadow_enabled = shadows
		sun.directional_shadow_max_distance = [60.0, 120.0, 200.0, 300.0][quality]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality < 2 else Viewport.MSAA_2X
