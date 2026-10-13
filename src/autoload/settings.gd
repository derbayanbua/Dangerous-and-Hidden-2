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
var morphing := true          ## Original „MORPHING“ (Gesichtsanimation; im Nachbau noch ohne Wirkung)
var decals := true            ## Original „FUSSSPUREN, DEKORATIONEN“ (Einschusslöcher/Spuren)
var blood := true             ## Original „BLUTFLECKEN“
var grass := true             ## Original „GRAS“ (Bodenvegetation der Originallevel)
var dynamic_lights := true    ## Original „DYNAMIK“ (dynamische Lichter)
var high_models := true       ## Original „MODELLE MIT HOHER AUFLÖSUNG“ (Detailstufen-Schwelle)
## Original-Detailstufen (Texte 2414–2417): 0 niedrig, 1 mittel, 2 hoch, 3 angepasst
## Werte = Original-Tabellen aus Options.bin (docs/re_notes_profiles.md, belegt)
const DETAIL_PRESETS := [
	{"shadows": false, "morphing": false, "decals": false, "blood": false, "grass": false, "dynamic_lights": false, "high_models": false, "quality": 0},
	{"shadows": false, "morphing": true, "decals": false, "blood": true, "grass": false, "dynamic_lights": true, "high_models": false, "quality": 1},
	{"shadows": true, "morphing": true, "decals": true, "blood": true, "grass": true, "dynamic_lights": true, "high_models": true, "quality": 2},
]
## Wie im Original gehören die Menü-Optionen zum Profil (Options.bin im Profilordner); Setup-Werte
## (Auflösung, VSync, Kantenglättung …) sind rechnerweit wie beim Original-setup.exe.
const PROFILE_KEYS := {
	"graphics": ["gamma", "shadows", "morphing", "decals", "blood", "grass", "dynamic_lights", "high_models", "quality"],
	"audio": ["master_volume", "music_volume"],
	"controls": ["mouse_sensitivity", "invert_y"],
	"game": ["subtitles", "crosshair"],
}
var profile_path := ""     ## <Profil>/options.cfg; leer = keine Profiloptionen (alles global)

var subtitles := true         ## Original „UNTERTITEL“
var crosshair := true         ## Original v1.12 „FADENKREUZ ZULASSEN“
# --- aus dem Original-Setup (setup.exe, LS3D_setup), soweit heute sinnvoll ---
## VSync-Modus: 0 aus, 1 an, 2 adaptiv, 3 Dreifachpuffer (Original „Triple-Buffering“)
var vsync_mode := 1
const VSYNC_NAMES := ["AUS", "AN", "ADAPTIV", "DREIFACHPUFFER"]
## Bildrate begrenzen (Original „Wiederh.-Rate“); 0 = unbegrenzt
var max_fps := 0
const FPS_STEPS := [0, 30, 60, 75, 120, 144, 165, 240]
## Kantenglättung (Original „Fullscene-Antialiasing“): 0 aus, 1 FXAA, 2 MSAA 2×, 3 MSAA 4×, 4 MSAA 8×, 5 TAA
var aa_mode := 1
const AA_NAMES := ["AUS", "FXAA", "MSAA 2×", "MSAA 4×", "MSAA 8×", "TAA"]
## Texturqualität (Original „Text.-Qual./-Gr.“): 0 Original, 1 KI-HD, 2 KI-4K (falls erzeugt)
var texture_quality := 1
const TEXTURE_NAMES := ["ORIGINAL", "HD (KI)", "4K (KI)"]
## Anisotrope Filterung: 0 aus, 1 2×, 2 4×, 3 8×, 4 16×
var anisotropy := 3
const ANISO_NAMES := ["AUS", "2×", "4×", "8×", "16×"]
## Original „Wenn inakt. aussetz.“: Spiel pausieren, wenn das Fenster den Fokus verliert
var pause_unfocused := true

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
	for k in ["morphing", "decals", "blood", "grass", "dynamic_lights", "high_models"]:
		set(k, _cfg.get_value("graphics", k, get(k)))
	for k in ["vsync_mode", "max_fps", "aa_mode", "texture_quality", "anisotropy", "pause_unfocused"]:
		set(k, _cfg.get_value("setup", k, get(k)))


func save_settings() -> void:
	if "--autoplay" in " ".join(OS.get_cmdline_user_args()):
		return   # Tests verändern die Benutzereinstellungen nicht
	if profile_path != "":
		var pc := ConfigFile.new()
		pc.load(profile_path)   # Tastenbelegung (Sektion keys) erhalten
		for sec in PROFILE_KEYS:
			for k in PROFILE_KEYS[sec]:
				pc.set_value(sec, k, get(k))
		pc.save(profile_path)
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
	for k in ["morphing", "decals", "blood", "grass", "dynamic_lights", "high_models"]:
		_cfg.set_value("graphics", k, get(k))
	for k in ["vsync_mode", "max_fps", "aa_mode", "texture_quality", "anisotropy", "pause_unfocused"]:
		_cfg.set_value("setup", k, get(k))
	_cfg.save(PATH)


func apply() -> void:
	_apply_audio()
	Engine.max_fps = max_fps
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
	vsync = vsync_mode != 0
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][clampi(vsync_mode, 0, 3)])
	Engine.max_fps = max_fps
	var vp := get_viewport()
	vp.mesh_lod_threshold = 0.0 if high_models else 4.0
	_apply_aa(vp)
	vp.scaling_3d_scale = clampf(scale_3d, 0.25, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vp.scaling_3d_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	changed.emit()


## Profil gewechselt: Profiloptionen laden (fehlen sie, bleiben die aktuellen Werte)
func use_profile(path: String) -> void:
	profile_path = path
	if path == "":
		return
	var pc := ConfigFile.new()
	if pc.load(path) == OK:
		for sec in PROFILE_KEYS:
			for k in PROFILE_KEYS[sec]:
				set(k, pc.get_value(sec, k, get(k)))
	apply()


func _apply_aa(vp: Viewport) -> void:
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X, Viewport.MSAA_DISABLED][clampi(aa_mode, 0, 5)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa_mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa_mode == 5
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X,
		Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X][clampi(anisotropy, 0, 4)]


## Ordner-Suffixe der Texturfassungen in Reihenfolge der Bevorzugung (gewählte Stufe, dann niedriger)
func texture_suffixes() -> Array:
	if texture_quality >= 2:
		return ["_4k", "_hd", ""]
	if texture_quality == 1:
		return ["_hd", ""]
	return [""]


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.0001)))


## Detailstufe anwenden (Original: GRAFIK-DETAILS NIEDRIG/MITTEL/HOCH setzen die Einzelschalter)
func set_detail_preset(i: int) -> void:
	var p: Dictionary = DETAIL_PRESETS[clampi(i, 0, 2)]
	for k in p:
		set(k, p[k])


## 0..2 wenn die Schalter einer Detailstufe entsprechen, sonst 3 = ANGEPASST
func detail_level() -> int:
	for i in DETAIL_PRESETS.size():
		var same := true
		for k in DETAIL_PRESETS[i]:
			if k != "quality" and get(k) != DETAIL_PRESETS[i][k]:
				same = false
		if same:
			return i
	return 3


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
		env.adjustment_enabled = true          # Sättigung/Kontrast der Mission bleiben erhalten
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
	_apply_aa(get_viewport())
