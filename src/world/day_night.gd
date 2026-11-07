extends Node
## 0.10.1 – dynamischer Tag-/Nachtwechsel (BEWUSSTE ABWEICHUNG vom Original, Nutzerauftrag 07.11.2026). Per preload.
## Kind der Mission (aus Mission._setup_environment über `attach`), nur auf Karten in MAPS. 1 Tag = DAY_LEN s
## (`--day_len=`), Startzeit `--day_start=<Stunde>`, `--daynight=0` = aus (fester Fotohimmel wie bisher).
## - Sonnenstand: Bahn Ost → Süd (Mittag 55° hoch) → West; nachts Mondlicht (bläulich, schwach, ohne Schatten).
## - Himmel: sky_daynight.gdshader überblendet die vorhandenen CC0-Fotohimmel (Tag/Abend/Nacht, docs/SKY_SOURCES.md),
##   prozedural Sonnenscheibe, Dämmerungsglühen, Sterne, Mond. Abendfoto wird zur Sonne gedreht (hellste Spalte).
## - Licht/Umgebung/Nebelfarbe/Belichtung/Mission.light_factor folgen der Sonnenhöhe.
## - Mehrspieler: der Server zählt die Tageszeit (`shared_s`), Net._hud_snapshot überträgt sie als „dn“ (alle 0,5 s);
##   Clients laufen lokal weiter und gleichen weich nach (Sprung bei > 3 s Abweichung) → alle sehen denselben Stand.
## Kosten: Sonnenlage alle 0,1 s, Himmel-/Nebelwerte alle 0,5 s (Radiance inkrementell, 128er Würfel).

const SHADER := preload("res://src/world/sky_daynight.gdshader")
const SkyPhoto := preload("res://src/world/sky_hdri.gd")
const MAPS := ["normandy3_mp"]
## [HDRI-ID, Helligkeit] für Tag / Dämmerung / Nacht
## „a|b“ = erste vorhandene Datei. Index 3 = Morgendämmerung (ersetzt Index 1 vor Mittag).
const SKIES := [["kloofendal_48d_partly_cloudy_puresky|kloofendal_overcast_puresky", 0.9],
	["qwantani_dusk_2_puresky|evening_road_01_puresky", 0.5], ["kloppenheim_02_puresky", 0.3],
	["qwantani_sunrise_puresky|qwantani_dusk_2_puresky|evening_road_01_puresky", 0.5]]
const DAY_LEN := 600.0
const NOON_ELEV := 55.0
## Server-Tageszeit [s im Zyklus] für Net._hud_snapshot; −1 = kein Tag/Nacht aktiv
static var shared_s := -1.0
static var _horizon_cache := {}
static var _bright_cache := {}

var mission: Node
var env: Environment
var sun: DirectionalLight3D
var material: ShaderMaterial
var day_len := DAY_LEN
var t := 0.0                    ## Sekunden im Zyklus (0 = Mitternacht)
var stats := {}
var _base_sun_energy := 1.3
var _base_shadow := true
var _base_ambient := Color(0.9, 0.9, 0.9)
var _base_ambient_energy := 0.5
var _base_exposure := 1.0
var _fog_cols: Array = []
var _eve_bright_u := 0.0
var _eve_texs: Array = []       ## [Abend, Morgen]
var _eve_fog: Array = []
var _eve_us: Array = []
var _eve_idx := -1
var _day_u := 0.0
var _sun_acc := 1.0
var _sky_acc := 1.0
var _last_dn := -2.0


static func wanted(m: Node) -> bool:
	if String(Game.cli.get("daynight", "1")) == "0" or not SkyPhoto.enabled():
		return false
	var om = m.get("orig_mission")
	return om != null and MAPS.has(String(om).to_lower())


## Aus Mission._setup_environment nach sky_fx.setup. Rückgabe: Knoten oder null (Karte ohne Tag/Nacht).
static func attach(m: Node, e: Environment, s: DirectionalLight3D, fx: Node) -> Node:
	if e == null or s == null or not wanted(m):
		return null
	var dn = load("res://src/world/day_night.gd").new()
	if not dn._setup(m, e, s):
		dn.free()
		return null
	m.add_child(dn)
	if fx and "day_night_material" in fx:
		fx.day_night_material = dn.material
		fx.apply()
	dn._update_sun()
	dn._update_sky()
	return dn


func _setup(m: Node, e: Environment, s: DirectionalLight3D) -> bool:
	mission = m
	env = e
	sun = s
	name = "DayNight"
	var texs: Array = []
	var ids: Array = []
	for sk in SKIES:
		var p := ""
		for id in String(sk[0]).split("|"):
			p = SkyPhoto.path_for(id)
			if p != "":
				ids.append(id)
				break
		var tx: Texture2D = SkyPhoto._texture(p) if p != "" else null
		if tx == null:
			stats["missing"] = sk[0]
			return false
		texs.append(tx)
		_fog_cols.append(horizon_of(tx) * float(sk[1]))
	stats["skies"] = ids
	_eve_texs = [texs[1], texs[3]]
	_eve_fog = [_fog_cols[1], _fog_cols[3]]
	_eve_us = [bright_u(texs[1]), bright_u(texs[3])]
	_day_u = bright_u(texs[0], true)
	_eve_bright_u = _eve_us[0]
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("sky_day", texs[0])
	material.set_shader_parameter("sky_eve", texs[1])
	material.set_shader_parameter("sky_night", texs[2])
	material.set_shader_parameter("energies", Vector3(SKIES[0][1], SKIES[1][1], SKIES[2][1]))
	day_len = maxf(float(Game.cli.get("day_len", DAY_LEN)), 10.0)
	t = fposmod(float(Game.cli.get("day_start", "9.0")) / 24.0 * day_len, day_len)
	_base_sun_energy = maxf(sun.light_energy, 1.2)
	_base_shadow = sun.shadow_enabled
	_base_ambient = env.ambient_light_color
	_base_ambient_energy = env.ambient_light_energy
	_base_exposure = env.tonemap_exposure
	if env.sky:
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	stats["active"] = true
	return true


## Mittlere Farbe knapp über dem Horizont (Ring), normiert auf ≤ 1
static func horizon_of(tx: Texture2D) -> Color:
	if _horizon_cache.has(tx):
		return _horizon_cache[tx]
	var c := Color(0.6, 0.62, 0.65)
	var img: Image = tx.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var acc := Color(0, 0, 0, 0)
		var w := img.get_width()
		var h := img.get_height()
		for yy in [int(h * 0.46), int(h * 0.48)]:
			for i in 64:
				acc += img.get_pixel(int(float(i) / 64.0 * w), yy)
		acc /= 128.0
		var mx := maxf(acc.r, maxf(acc.g, acc.b))
		if mx > 1.0:
			acc = Color(acc.r / mx, acc.g / mx, acc.b / mx)
		c = Color(acc.r, acc.g, acc.b, 1.0)
	_horizon_cache[tx] = c
	return c


## Hellste Spalte (u 0..1) im Band über dem Horizont (Sonnenstand des Fotos)
static func bright_u(tx: Texture2D, high := false) -> float:
	var key := [tx, high]
	if _bright_cache.has(key):
		return _bright_cache[key]
	var best_u := 0.0
	var img: Image = tx.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var best := -1.0
		for i in 128:
			var x := int((float(i) + 0.5) / 128.0 * w)
			var s := 0.0
			for yy in ([0.08, 0.16, 0.24, 0.32, 0.40] if high else [0.30, 0.36, 0.42, 0.47]):
				var c := img.get_pixel(x, int(h * yy))
				s += c.r + c.g + c.b
			if s > best:
				best = s
				best_u = (float(i) + 0.5) / 128.0
	_bright_cache[key] = best_u
	return best_u


## Richtung ZUR Sonne für die Tageszeit (Osten +X, Norden −Z → Mittag im Süden +Z)
func sun_dir() -> Vector3:
	var a := (t / day_len - 0.25) * TAU
	var tilt := deg_to_rad(NOON_ELEV)
	return Vector3(cos(a), sin(a) * sin(tilt), sin(a) * cos(tilt)).normalized()


func hour() -> float:
	return t / day_len * 24.0


func _process(delta: float) -> void:
	if Net.is_online and not multiplayer.is_server():
		t = fposmod(t + delta, day_len)
		var dn = Net.hud_info.get("dn", null)
		if dn != null and float(dn) >= 0.0 and float(dn) != _last_dn:
			_last_dn = float(dn)
			var err := wrapf(float(dn) - t, -day_len * 0.5, day_len * 0.5)
			if absf(err) > 3.0:
				t = fposmod(float(dn), day_len)
			else:
				t = fposmod(t + err * 0.25, day_len)
			stats["sync_err"] = err
	else:
		t = fposmod(t + delta, day_len)
		shared_s = t
	_sun_acc += delta
	_sky_acc += delta
	if _sun_acc >= 0.1:
		_sun_acc = 0.0
		_update_sun()
	if _sky_acc >= 0.5:
		_sky_acc = 0.0
		_update_sky()


func _exit_tree() -> void:
	shared_s = -1.0


func _daylight(e: float) -> float:
	return smoothstep(-0.12, 0.25, e)


func _update_sun() -> void:
	var s := sun_dir()
	var e := s.y
	var moon := Vector3(-s.x, maxf(-s.y, 0.35), -s.z).normalized()
	var light_dir := s if e > -0.06 else moon
	sun.global_basis = Basis.looking_at(-light_dir, Vector3.UP if absf(light_dir.y) < 0.98 else Vector3.FORWARD)
	if e > -0.06:
		var k := smoothstep(-0.06, 0.3, e)
		sun.light_energy = _base_sun_energy * k
		sun.light_color = Color(1.0, 0.5, 0.28).lerp(Color(1.0, 0.95, 0.88), smoothstep(0.0, 0.45, e))
		sun.shadow_enabled = _base_shadow and e > 0.02
	else:
		sun.light_energy = 0.14 * smoothstep(-0.06, -0.2, e)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.shadow_enabled = false
	stats["elev"] = rad_to_deg(asin(clampf(e, -1.0, 1.0)))
	stats["energy"] = sun.light_energy
	if material:
		material.set_shader_parameter("moon_dir", moon)


func _update_sky() -> void:
	var s := sun_dir()
	var e := s.y
	var wd := smoothstep(0.04, 0.3, e)
	var wn := smoothstep(-0.04, -0.22, e)
	var we := maxf(1.0 - wd - wn, 0.0)
	var w := Vector3(wd, we, wn)
	var dl := _daylight(e)
	# Morgen- bzw. Abendfoto (Wechsel mittags/mitternachts, dann ist das Dämmerungsgewicht 0)
	var ei := 1 if hour() < 12.0 else 0
	if ei != _eve_idx and material:
		_eve_idx = ei
		material.set_shader_parameter("sky_eve", _eve_texs[ei])
		_fog_cols[1] = _eve_fog[ei]
		_eve_bright_u = _eve_us[ei]
		stats["eve"] = "morgen" if ei == 1 else "abend"
	if material:
		material.set_shader_parameter("weights", w)
		# Abendfoto: hellste Spalte zur Sonne drehen (u-Konvention wie im Shader: atan(x, z) / 2π)
		var us := fposmod(atan2(s.x, s.z) / TAU, 1.0)
		# Tagesfoto mit eigener Sonne: deren Richtung ebenfalls zur Sonne drehen; Scheibe nur in der Dämmerung prozedural
		material.set_shader_parameter("rotations", Vector3(fposmod(_day_u - us, 1.0), fposmod(_eve_bright_u - us, 1.0), 0.0))
		var g := clampf(1.0 - absf(e) / 0.22, 0.0, 1.0)
		material.set_shader_parameter("glow", g * 0.55)
		material.set_shader_parameter("sun_disc", clampf(1.0 - wd, 0.0, 1.0) * smoothstep(-0.04, 0.02, e))
		material.set_shader_parameter("sun_color", sun.light_color)
		material.set_shader_parameter("stars", wn)
		material.set_shader_parameter("exposure", lerpf(0.55, 1.0, dl))
	var fog := Color(0, 0, 0)
	for i in 3:
		fog += (_fog_cols[i] as Color) * w[i]
	fog = fog.lerp(Color(1.0, 0.55, 0.3) * 0.7, clampf(1.0 - absf(e) / 0.2, 0.0, 1.0) * 0.25)
	env.fog_light_color = Color(fog.r, fog.g, fog.b, 1.0) * lerpf(0.45, 1.0, dl)
	if material:
		material.set_shader_parameter("horizon_fog", env.fog_light_color)
		material.set_shader_parameter("horizon_mix", 0.9 if env.fog_enabled else 0.0)
	env.ambient_light_color = _base_ambient.lerp(Color(0.45, 0.55, 0.8), 1.0 - dl)
	env.ambient_light_energy = _base_ambient_energy * lerpf(0.4, 1.0, dl)
	env.tonemap_exposure = _base_exposure * lerpf(1.3, 1.0, dl)
	if mission and "light_factor" in mission:
		mission.light_factor = lerpf(0.5, 1.0, dl)
	stats["weights"] = w
	stats["hour"] = hour()
	stats["fog"] = env.fog_light_color
