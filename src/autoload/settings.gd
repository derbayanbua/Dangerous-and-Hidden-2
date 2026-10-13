extends Node
## Persistente Benutzereinstellungen (user://settings.cfg): Grafik, Anzeige,
## Maus. Tastenbelegung verwaltet InputSetup in derselben Datei.

signal changed

const PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const QUALITY_NAMES: PackedStringArray = ["Niedrig", "Mittel", "Hoch", "Ultra"]

var resolution := Vector2i(1280, 720)
var fullscreen := false
var vsync := true
var quality := 2           ## 0..3, siehe QUALITY_NAMES
var render_scale := 1.0    ## 0.5..1.0 (FSR 1 bei < 1)
var fov := 70.0
var mouse_sensitivity := 0.12
var invert_y := false
var master_volume := 0.8

var _cfg := ConfigFile.new()


func _ready() -> void:
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


func save_settings() -> void:
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
	_cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		changed.emit()
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - resolution) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	changed.emit()


## Wendet die Qualitätsstufe auf ein WorldEnvironment und die Sonne an.
## Wird von der Mission beim Laden und bei jeder Änderung aufgerufen.
func apply_to_world(env: Environment, sun: DirectionalLight3D) -> void:
	if env:
		env.ssao_enabled = quality >= 1
		env.ssil_enabled = quality >= 3
		env.sdfgi_enabled = quality >= 3
		env.glow_enabled = quality >= 1
		env.volumetric_fog_enabled = quality >= 2
	if sun:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = [60.0, 120.0, 200.0, 300.0][quality]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality < 2 else Viewport.MSAA_2X
