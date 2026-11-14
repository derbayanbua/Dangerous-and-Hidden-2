extends Node
## Dynamischer Tag-/Nachtzyklus der Karte: Sonne/Mond (eine Richtungsleuchte), Himmel (alps_sky-Uniforms bzw.
## ProceduralSky ohne Panorama), Umgebungslicht, Nebel, Raumlichter, Laternen und OG-Fensterschein.
## Einstellungen: Server-Regeln `day_start_h` (Startstunde 0–23) und `day_cycle_min` (Minuten je 24 h, 0 = feste
## Zeit); Tests/Bilder: `--daytime=<h>` und `--daycycle=<min>` überschreiben.
## Mehrspieler serverautoritativ: der Server führt die Zeit und sendet sie (alle SYNC_S und auf Anfrage beim
## Beitritt, auch spät) über eigene RPCs dieses Knotens – ohne neue Netz-Protokollversion. Ältere Gegenstellen
## ohne diesen Knoten verwerfen die Nachricht nur (Konsolenhinweis); dann läuft die Zeit dort lokal.
const DEFAULT_START := 19.0
const DEFAULT_CYCLE := 60.0
const SYNC_S := 10.0
const ENV_S := 0.5
var mission: Node
var hour := DEFAULT_START
var start_hour := DEFAULT_START
var cycle_min := DEFAULT_CYCLE
var synced := false             ## Client: mindestens einmal vom Server erhalten
var sync_count := 0
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _proc_sky: ProceduralSkyMaterial
var _base := {}
var _sync_t := 0.0
var _env_t := 0.0
var _target_hour := -1.0
var _state := {}

func _ready() -> void:
	name = "Tageszeit"
	start_hour = float(Game.cli.get("daytime", _rule("day_start_h", DEFAULT_START)))
	cycle_min = maxf(0.0, float(Game.cli.get("daycycle", _rule("day_cycle_min", DEFAULT_CYCLE))))
	hour = fposmod(start_hour, 24.0)
	if Net.is_online and not multiplayer.is_server():
		request_state.rpc_id(1)
	_apply(true)

func _rule(key: String, fallback: float) -> float:
	# Server-Einstellungen (LAN-Menü/Konfiguration); ohne Eintrag (ältere Konfiguration, Einzelspieler) Kartenstandard
	return float(Net.settings[key]) if Net.settings.has(key) else fallback

func bind(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun
	_base = {"fog_color": env.fog_light_color, "fog_density": env.fog_density, "vol_density": env.volumetric_fog_density,
		"vol_albedo": env.volumetric_fog_albedo}
	_sky_mat = env.sky.sky_material as ShaderMaterial if env.sky else null
	_proc_sky = env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	_apply(true)

## Himmel/Nebel wurden nach bind() ausgetauscht (scene_details.configure_sky): Grundwerte neu übernehmen.
func rebind() -> void:
	if _env:
		bind(_env, _sun)

func _process(delta: float) -> void:
	if cycle_min > 0.0:
		hour = fposmod(hour + delta * 24.0 / (cycle_min * 60.0), 24.0)
	if _target_hour >= 0.0:
		# Client: kleine Abweichungen weich angleichen
		var diff := wrapf(_target_hour - hour, -12.0, 12.0)
		var step := diff * minf(1.0, delta * 1.5)
		hour = fposmod(hour + step, 24.0)
		_target_hour = fposmod(_target_hour + (delta * 24.0 / (cycle_min * 60.0) if cycle_min > 0.0 else 0.0), 24.0)
		if absf(diff) < 0.0005:
			_target_hour = -1.0
	_env_t -= delta
	_apply(_env_t <= 0.0)
	if _env_t <= 0.0:
		_env_t = ENV_S
	if Net.is_online and multiplayer.is_server():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = SYNC_S
			sync_state.rpc(hour, cycle_min)

## Sinus der Sonnenhöhe (Spätfrühling, Aufgang ≈ 4:50, Untergang ≈ 19:10, Mittag ≈ 53°)
static func sun_sin(h: float) -> float:
	return 0.18 - 0.62 * cos(TAU * h / 24.0)

static func daylight_of(h: float) -> float:
	return smoothstep(-0.03, 0.30, sun_sin(h))

static func night_of(h: float) -> float:
	return 1.0 - smoothstep(-0.22, -0.04, sun_sin(h))

## Lampen: 1 = an (Dämmerung/Nacht), 0 = aus (Tag)
static func lamp_level_of(h: float) -> float:
	return 1.0 - smoothstep(0.12, 0.45, daylight_of(h))

func phase() -> String:
	var d := daylight_of(hour)
	var n := night_of(hour)
	if n > 0.5:
		return "nacht"
	if d > 0.5:
		return "tag"
	return "daemmerung"

func state() -> Dictionary:
	return _state

func _south() -> Vector3:
	var sd = mission.get("scene_details") if mission else null
	var s: Vector3 = sd.south if sd and sd.get("south") is Vector3 else Vector3(0.817, 0, 0.576).normalized()
	return Vector3(s.x, 0, s.z).normalized()

func _apply(full: bool) -> void:
	var s := sun_sin(hour)
	var day := daylight_of(hour)
	var night := night_of(hour)
	var lamp := lamp_level_of(hour)
	var south := _south()
	var west := Vector3(-south.z, 0, south.x)
	var phi := (hour - 12.0) / 12.0 * PI
	var horiz := (south * cos(phi) + west * sin(phi)).normalized()
	var el := asin(clampf(s, -1.0, 1.0))
	var to_sun := (horiz * cos(el) + Vector3.UP * sin(el)).normalized()
	var moon := s <= -0.07
	_state = {"hour": hour, "sun_sin": s, "daylight": day, "night": night, "lamp": lamp, "moon": moon, "to_sun": to_sun}
	if _sun:
		var to_light := -to_sun if moon else to_sun
		_sun.global_basis = Basis.looking_at(-to_light, Vector3.UP if absf(to_light.y) < 0.98 else Vector3.FORWARD)
		if moon:
			_sun.light_color = Color(0.55, 0.62, 0.85)
			_sun.light_energy = 0.08 * (1.0 - smoothstep(-0.15, -0.07, s))
		else:
			_sun.light_color = Color(1.0, 0.58, 0.34).lerp(Color(1.0, 0.95, 0.88), smoothstep(0.0, 0.4, s))
			_sun.light_energy = 0.16 * smoothstep(-0.07, -0.04, s) + 1.15 * smoothstep(-0.03, 0.35, s)
		_sun.visible = _sun.light_energy > 0.002
	if mission and "light_factor" in mission:
		mission.light_factor = lerpf(1.0, 0.5, night)     # Wahrnehmung: Nacht wie Nachtmissionen
	if not full:
		return
	if _env:
		var amb := Color(0.48, 0.56, 0.76).lerp(Color(0.62, 0.68, 0.78), day).lerp(Color(0.16, 0.20, 0.34), night)
		_env.ambient_light_color = amb
		_env.ambient_light_energy = lerpf(lerpf(0.34, 0.58, day), 0.16, night)
		if not _base.is_empty():
			var fc: Color = _base.fog_color
			_env.fog_light_color = fc.lerp(Color(0.70, 0.75, 0.80), day).lerp(Color(0.035, 0.045, 0.075), night)
			_env.fog_density = float(_base.fog_density) * lerpf(1.0, 0.65, day)
			var va: Color = _base.vol_albedo
			_env.volumetric_fog_albedo = va.lerp(Color(0.75, 0.78, 0.82), day).lerp(Color(0.05, 0.06, 0.09), night)
	if _sky_mat:
		_sky_mat.set_shader_parameter("daylight", day)
		_sky_mat.set_shader_parameter("night", night)
		_sky_mat.set_shader_parameter("sun_direction", to_sun)
	elif _proc_sky:
		_proc_sky.sky_top_color = Color(0.32, 0.42, 0.58).lerp(Color(0.25, 0.43, 0.75), day).lerp(Color(0.01, 0.015, 0.04), night)
		_proc_sky.sky_horizon_color = Color(0.78, 0.66, 0.52).lerp(Color(0.70, 0.76, 0.84), day).lerp(Color(0.05, 0.06, 0.10), night)
		_proc_sky.ground_horizon_color = Color(0.5, 0.45, 0.38).lerp(Color(0.05, 0.05, 0.06), night)
	var rl = mission.get("room_lighting") if mission else null
	if rl and rl.has_method("set_level"):
		rl.set_level(lamp)
	var sl = mission.get("street_lamps") if mission else null
	if sl:
		sl.set_level(lamp)
	var glass = mission.get("og_glass_material") if mission else null
	if glass is StandardMaterial3D:
		glass.emission_energy_multiplier = 0.30 * lamp

## Zeit setzen (Server/Einzelspieler; Tests). Im Mehrspieler sofort an alle.
func set_hour(h: float, cycle := -1.0) -> void:
	hour = fposmod(h, 24.0)
	if cycle >= 0.0:
		cycle_min = cycle
	_target_hour = -1.0
	_apply(true)
	if Net.is_online and multiplayer.is_server():
		sync_state.rpc(hour, cycle_min)

@rpc("any_peer", "call_remote", "reliable")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(peer):
		sync_state.rpc_id(peer, hour, cycle_min)

@rpc("authority", "call_remote", "reliable")
func sync_state(h: float, cycle: float) -> void:
	cycle_min = maxf(0.0, cycle)
	sync_count += 1
	if not synced or absf(wrapf(h - hour, -12.0, 12.0)) > 0.25:
		hour = fposmod(h, 24.0)
		_target_hour = -1.0
		_apply(true)
	else:
		_target_hour = fposmod(h, 24.0)
	synced = true
