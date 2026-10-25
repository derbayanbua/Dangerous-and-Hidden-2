extends Node3D
## B-013 – Himmel/Wolken/Wolkenschatten (BEWUSSTE ABWEICHUNG vom Original, Vorgabe Auftraggeber: optische
## Aufwertung, Spielwerte/Leveldesign unverändert). Kind der Mission (Mission._setup_environment).
## - Übernimmt Farben/Sonne aus dem ProceduralSkyMaterial, das die Mission (bzw. die Original-Lichter aus extra.json)
##   eingestellt hat → Original-Stimmung/Tageszeit bleibt; ersetzt es ab Stufe „Mittel“ durch sky_clouds.gdshader.
##   Missionen mit eigenem Himmels-Shader (kein ProceduralSkyMaterial) bleiben unberührt.
## - Wolkenschatten (ab „Hoch“, nur bei Tageslicht): ein großes, mit der Kamera mitwanderndes Decal mit nahtlos
##   kachelbarer Wolkenmaske, das mit derselben Windgeschwindigkeit wie die Himmelswolken zieht.
## - Klimazone aus dem Missionsnamen (Schnee/Wüste/Dschungel/gemäßigt) = Annahme für Bedeckung/Farbe.
## Stufe „Niedrig“: unveränderter prozeduraler Himmel, keine Schatten → keine Zusatzkosten (VM/WARP).

const SHADER := preload("res://src/world/sky_clouds.gdshader")
const CLOUD_HEIGHT := 1000.0      ## gedachte Wolkenhöhe [m] (koppelt Himmel-UV und Schattengeschwindigkeit)
const CLOUD_SCALE := 0.9
const SHADOW_PERIOD := 420.0      ## Kachelgröße der Schattenmaske [m]; Decal = 2×2 Kacheln
## [Bedeckung, Dichte, Schattenstärke, Wolkenunterseite]
const CLIMATES := {
	"temperate": [0.45, 1.0, 0.38, Color(0.46, 0.49, 0.56)],
	"snow": [0.62, 1.15, 0.30, Color(0.55, 0.57, 0.62)],
	"desert": [0.18, 0.7, 0.45, Color(0.62, 0.55, 0.48)],
	"jungle": [0.55, 1.1, 0.40, Color(0.42, 0.46, 0.46)],
}
static var _mask_cache := {}

var env: Environment
var sun: DirectionalLight3D
var mission: Node
var procedural: ProceduralSkyMaterial
var material: ShaderMaterial
var climate := "temperate"
var night := false
var wind_uv := Vector2(0.006, 0.002)
var shadow_decal: Decal
var stats := {"applied": 0}


func setup(m: Node, e: Environment, s: DirectionalLight3D) -> void:
	mission = m
	env = e
	sun = s
	name = "SkyFx"
	if env == null or env.sky == null or not (env.sky.sky_material is ProceduralSkyMaterial):
		return   # eigener Himmel der Karte (z. B. Panorama-Shader) → unverändert lassen
	procedural = env.sky.sky_material
	climate = detect_climate(m)
	var lf = m.get("light_factor")
	night = lf != null and float(lf) < 0.8
	# Windrichtung je Mission fest (reproduzierbar), Geschwindigkeit ≈ 5–9 m/s in Wolkenhöhe
	var h := absi(hash(_mission_key(m)))
	var ang := float(h % 360) * PI / 180.0
	var spd := 0.0045 + float(h % 7) * 0.0005
	wind_uv = Vector2(cos(ang), sin(ang)) * spd
	if not Settings.changed.is_connected(apply):
		Settings.changed.connect(apply)
	apply()


static func _mission_key(m: Node) -> String:
	var k := ""
	var om = m.get("orig_mission")
	if om != null:
		k = String(om)
	var sc: Script = m.get_script()
	if sc:
		k += " " + sc.resource_path.get_file()
	return k.to_lower()


## Klimazone (Annahme nach Missionsname): ARCTIC/NORWAY/Nordlicht = Schnee, AFRICA/Sandsturm = Wüste, BURMA = Dschungel
static func detect_climate(m: Node) -> String:
	var k := _mission_key(m)
	for w in ["arctic", "norway", "a1_", "a2_", "a3_", "nordlicht", "nw", "blizzard"]:
		if k.contains(w):
			return "snow"
	for w in ["africa", "af", "sandsturm", "libyen"]:
		if k.contains(w):
			return "desert"
	if k.contains("burma") or k.contains("bu"):
		return "jungle"
	return "temperate"


func apply() -> void:
	if procedural == null or env == null or env.sky == null:
		return
	stats["applied"] += 1
	var q := Settings.quality
	if q <= 0:
		env.sky.sky_material = procedural
		_set_shadows(false)
		return
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
	var c: Array = CLIMATES[climate]
	var p := procedural
	material.set_shader_parameter("sky_top", p.sky_top_color)
	material.set_shader_parameter("sky_horizon", p.sky_horizon_color)
	material.set_shader_parameter("ground_horizon", p.ground_horizon_color)
	material.set_shader_parameter("ground_bottom", p.ground_bottom_color)
	material.set_shader_parameter("sky_curve", p.sky_curve)
	material.set_shader_parameter("ground_curve", p.ground_curve)
	material.set_shader_parameter("sky_energy", p.sky_energy_multiplier)
	material.set_shader_parameter("sun_angle_max", p.sun_angle_max)
	material.set_shader_parameter("sun_curve", p.sun_curve)
	material.set_shader_parameter("coverage", float(c[0]))
	material.set_shader_parameter("density", float(c[1]))
	material.set_shader_parameter("cloud_dark", c[3])
	material.set_shader_parameter("cloud_light", p.sky_horizon_color.lerp(Color.WHITE, 0.75))
	material.set_shader_parameter("cloud_scale", CLOUD_SCALE)
	material.set_shader_parameter("wind", wind_uv)
	material.set_shader_parameter("octaves", [3, 4, 5, 6, 7][q])
	material.set_shader_parameter("light_steps", [1, 1, 2, 3, 4][q])
	material.set_shader_parameter("night", 1.0 if night else 0.0)
	env.sky.sky_material = material
	# Radiance (Umgebungslicht/Reflexe) schrittweise aktualisieren: bewegte Wolken kosten sonst jedes Bild einen Cubemap-Pass
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256 if q >= 4 else (Sky.RADIANCE_SIZE_128 if q >= 2 else Sky.RADIANCE_SIZE_64)
	_set_shadows(q >= 2 and not night and sun != null and sun.light_energy >= 0.5)


## Weltgeschwindigkeit der Wolken [m/s] (passend zur Himmelsprojektion uv = xz / y · scale)
func wind_world() -> Vector2:
	return wind_uv * CLOUD_HEIGHT / CLOUD_SCALE


func _set_shadows(on: bool) -> void:
	if not on:
		if shadow_decal:
			shadow_decal.queue_free()
			shadow_decal = null
		set_process(false)
		return
	var res: int = 512 if Settings.quality >= 3 else 256
	var tex := cloud_mask(res, float(CLIMATES[climate][0]))
	if shadow_decal == null:
		shadow_decal = Decal.new()
		shadow_decal.name = "CloudShadows"
		shadow_decal.size = Vector3(SHADOW_PERIOD * 2.0, 900.0, SHADOW_PERIOD * 2.0)
		shadow_decal.cull_mask = 1
		shadow_decal.upper_fade = 0.05
		shadow_decal.lower_fade = 0.05
		add_child(shadow_decal)
	shadow_decal.texture_albedo = tex
	var strength := float(CLIMATES[climate][2]) * clampf(sun.light_energy / 1.4, 0.4, 1.0)
	shadow_decal.modulate = Color(1, 1, 1, strength)
	set_process(true)
	_process(0.0)


func _process(_dt: float) -> void:
	if shadow_decal == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	var t := Time.get_ticks_msec() / 1000.0
	var w := wind_world() * t
	# Kachelraster mit dem Wind verschoben; Decal-Mitte = nächster Rasterpunkt zur Kamera (Rand ≥ halbe Kachel entfernt)
	var gx := w.x + roundf((cp.x - w.x) / SHADOW_PERIOD) * SHADOW_PERIOD
	var gz := w.y + roundf((cp.z - w.y) / SHADOW_PERIOD) * SHADOW_PERIOD
	shadow_decal.global_position = Vector3(gx, cp.y, gz)


## Nahtlos kachelbare Wolkenmaske (schwarz, Alpha = Wolke), 2×2 gekachelt; zwischengespeichert je Größe/Bedeckung
static func cloud_mask(res: int, coverage: float) -> Texture2D:
	var key := "%d_%.2f" % [res, coverage]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 4.0 / float(res)
	n.seed = 1013
	var src := n.get_seamless_image(res, res, false, false, 0.15)
	src.convert(Image.FORMAT_L8)
	var img := Image.create(res * 2, res * 2, false, Image.FORMAT_LA8)
	var tile := Image.create(res, res, false, Image.FORMAT_LA8)
	var lo := 0.62 - coverage * 0.45
	for y in res:
		for x in res:
			var v := src.get_pixel(x, y).r
			var a := smoothstep(lo, lo + 0.22, v)
			tile.set_pixel(x, y, Color(0, 0, 0, a))
	for ty in 2:
		for tx in 2:
			img.blit_rect(tile, Rect2i(0, 0, res, res), Vector2i(tx * res, ty * res))
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mask_cache[key] = tex
	return tex
