extends Node
## 0.11.5 – Dynamischer Tag-/Nachtwechsel auf ALLEN Karten, NUR im Mehrspieler (LAN und Internet gleich).
## BEWUSSTE ABWEICHUNG vom Original [D]. Per preload, kein class_name. Angelegt am Ende von Mission._ready über
## `attach` (Knoten „MpTageszeit“, feste Lage unter der Mission → RPC-Abgleich wie src/maps/bavaria/day_night.gd).
## Regeln (Net.RULE_KEYS): `day_night` (daynight, an/aus, Standard aus), `dn_start_h` (daynightstart, −1 = Original-
## stimmung der Karte, sonst Startstunde 0–23), `dn_cycle_min` (daynightcycle, Echtzeit-Minuten je 24 h). Wirkt ab
## Kartenstart; Einzelspieler und Karten mit eigenem Tageszyklus (Mission.day_night ≠ null, z. B. Bavaria) unberührt.
## Prinzip „relativ zur Karte“: Aus Sonnenhöhe/-richtung und Mission.light_factor wird die Originaluhrzeit der Karte
## geschätzt (`base_hour`). Alle Werte (Sonne/Mond-Richtung und -Energie, Lichtfarbe, Umgebungslicht, Nebel-/Volumen-
## nebelfarbe, Himmelsfarben bzw. sky_clouds-Parameter, Himmelsenergie bei Foto-/Sonderhimmeln, Belichtung,
## light_factor für die KI-Sicht) werden zwischen Nacht-, Original- und Tageswert interpoliert → bei `base_hour` exakt
## die Originalstimmung, dazwischen stetige (weiche) Übergänge. Grafikstufenwechsel (Settings.apply_to_world) setzt
## Ambient/Schatten neu; dieser Knoten rechnet danach mit denselben Basiswerten (q_base_amb) sofort neu → gleiche
## Stimmung auf jeder Stufe. Annahmen [E]: Sonnenbahn wie Bavaria (Spätfrühling), Paletten, Mondlicht.
## Server führt die Zeit; Clients fragen beim Beitritt (auch spät) per `request_state`, Server sendet `sync_state`
## alle SYNC_S und auf Anfrage. Keine neue Protokollversion (Knoten-RPCs).

const SYNC_S := 10.0
const ENV_S := 0.25
const NODE_NAME := "MpTageszeit"
const MOON_SWITCH := -0.07
const SkyFxScript := preload("res://src/world/sky_fx.gd")

var mission: Node
var env: Environment
var sun: DirectionalLight3D
var sky_fx: Node
var hour := 12.0
var base_hour := 12.0
var cycle_min := 60.0
var synced := false
var sync_count := 0
var stats := {}
var _base := {}
var _q := Quaternion.IDENTITY
var _sync_t := SYNC_S              ## erste Rundsendung erst nach SYNC_S (Clients laden noch; sie fragen selbst an)
var _env_t := 0.0
var _req_t := 0.0
var _req_n := 0
var _target_hour := -1.0
var _set := {}                      ## zuletzt gesetzte Werte (fremde Neusetzung erkennen → neue Basis)


static func wanted(m: Node) -> bool:
	if not Net.is_online or m == null:
		return false
	if not bool(Net.rule("day_night")):
		return false
	return m.get("day_night") == null


static func attach(m: Node) -> Node:
	if not wanted(m) or m.get("env") == null or m.get("sun") == null:
		return null
	var dn = load("res://src/world/mp_day_night.gd").new()
	dn.name = NODE_NAME
	dn.mission = m
	dn.env = m.env
	dn.sun = m.sun
	dn.sky_fx = m.get("sky_fx")
	dn._capture()
	m.add_child(dn)
	return dn


# --- Modell (gleiche Sonnenbahn wie Bavaria) ------------------------------------------------------------------

static func sun_sin(h: float) -> float:
	return 0.18 - 0.62 * cos(TAU * h / 24.0)

static func daylight_of(h: float) -> float:
	return smoothstep(-0.03, 0.30, sun_sin(h))

static func night_of(h: float) -> float:
	return 1.0 - smoothstep(-0.22, -0.04, sun_sin(h))

## Helligkeit 0 (tiefe Nacht) … 1 (Tag), stetig und monoton in der Sonnenhöhe
static func lightness_of(h: float) -> float:
	return 0.5 * daylight_of(h) + 0.5 * (1.0 - night_of(h))

## Richtung ZUR Sonne (Süden = +Z, Westen = −X; Norden −Z wie im Projekt)
static func to_sun(h: float) -> Vector3:
	var south := Vector3(0, 0, 1)
	var west := Vector3(-1, 0, 0)
	var phi := (h - 12.0) / 12.0 * PI
	var horiz := (south * cos(phi) + west * sin(phi)).normalized()
	var el := asin(clampf(sun_sin(h), -1.0, 1.0))
	return (horiz * cos(el) + Vector3.UP * sin(el)).normalized()

## Richtung ZUM Licht (Sonne, nachts Mond gegenüber)
static func to_light(h: float) -> Vector3:
	var s := to_sun(h)
	return s if sun_sin(h) > MOON_SWITCH else -s

## Modell-Lichtstärke 0…1 (Mond ≈ 0,06)
static func energy_of(h: float) -> float:
	var s := sun_sin(h)
	if s <= MOON_SWITCH:
		return 0.08 * (1.0 - smoothstep(-0.15, -0.07, s)) / 1.31
	return (0.16 * smoothstep(-0.07, -0.04, s) + 1.15 * smoothstep(-0.03, 0.35, s)) / 1.31

static func light_color_of(h: float) -> Color:
	var s := sun_sin(h)
	if s <= MOON_SWITCH:
		return Color(0.55, 0.62, 0.85)
	return Color(1.0, 0.58, 0.34).lerp(Color(1.0, 0.95, 0.88), smoothstep(0.0, 0.4, s))

## Originaluhrzeit aus Sonnenhöhe/-richtung und Lichtfaktor der Karte schätzen
static func estimate_hour(to_sun_dir: Vector3, light_factor: float) -> float:
	if light_factor <= 0.6:
		return 0.5                                          # Nachtkarte
	var s0 := clampf(to_sun_dir.y, -0.2, 0.8)
	if light_factor < 0.9:
		s0 = clampf(s0, -0.06, 0.15)                        # Dämmerung
	else:
		s0 = maxf(s0, 0.12)                                 # Tag: Sonne sicher über dem Horizont
	var a := acos(clampf((0.18 - s0) / 0.62, -1.0, 1.0))
	var h := 24.0 * a / TAU                                 # Vormittag
	if to_sun_dir.x < 0.0:                                  # Sonne im Westen → Nachmittag/Abend
		h = 24.0 - h
	return h

## Wert zwischen Nacht (lo), Original (base bei x0) und Tag (hi)
static func rel(base: float, lo: float, hi: float, x: float, x0: float) -> float:
	if x <= x0:
		return base if x0 <= 0.0001 else lerpf(lo, base, x / x0)
	return base if x0 >= 0.9999 else lerpf(base, hi, (x - x0) / (1.0 - x0))

static func rel_c(base: Color, lo: Color, hi: Color, x: float, x0: float) -> Color:
	return Color(rel(base.r, lo.r, hi.r, x, x0), rel(base.g, lo.g, hi.g, x, x0), rel(base.b, lo.b, hi.b, x, x0), base.a)


# --- Aufbau ---------------------------------------------------------------------------------------------------

func _capture() -> void:
	var lf := float(mission.get("light_factor")) if "light_factor" in mission else 1.0
	var b := sun.global_basis.z.normalized()               # DirectionalLight leuchtet entlang −Z → +Z = zum Licht
	base_hour = estimate_hour(b, lf)
	var lm := to_light(base_hour)
	_q = Quaternion(lm, b) if lm.dot(b) > -0.999 else Quaternion(Vector3.UP, PI)
	_base = {"light_factor": lf, "sun_energy": sun.light_energy, "sun_color": sun.light_color,
		"amb_color": env.ambient_light_color, "amb_energy": env.ambient_light_energy, "exposure": env.tonemap_exposure,
		"bg_energy": env.background_energy_multiplier, "vol_albedo": env.volumetric_fog_albedo,
		"lightness": lightness_of(base_hour), "energy": energy_of(base_hour), "color": light_color_of(base_hour)}
	_base_fog(env.fog_light_color)
	var proc: ProceduralSkyMaterial = sky_fx.get("procedural") if sky_fx and "procedural" in sky_fx else null
	if proc == null and env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		proc = env.sky.sky_material
	_base["proc"] = proc
	if proc:
		_base["top"] = proc.sky_top_color
		_base["hor"] = proc.sky_horizon_color
		_base["ghor"] = proc.ground_horizon_color
	_base["sky_night"] = 1.0 if sky_fx and bool(sky_fx.get("night")) else 0.0
	start_hour_from_rules()
	stats["base_hour"] = base_hour


func _base_fog(c: Color) -> void:
	_base["fog"] = c
	_set["fog"] = c


func start_hour_from_rules() -> void:
	var sh := int(Net.rule("dn_start_h"))
	hour = base_hour if sh < 0 else fposmod(float(sh), 24.0)
	cycle_min = maxf(1.0, float(Net.rule("dn_cycle_min")))


func _ready() -> void:
	if not Settings.changed.is_connected(_on_settings):
		Settings.changed.connect(_on_settings)
	apply()
	if Net.is_online and not multiplayer.is_server():
		request_state.rpc_id(1)
		_req_n = 1
		_req_t = 2.0


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings):
		Settings.changed.disconnect(_on_settings)


## Grafikstufe/Optionen geändert: Mission._apply_settings hat Ambient/Schatten neu gesetzt → gleich neu anwenden
func _on_settings() -> void:
	apply.call_deferred()


func _process(delta: float) -> void:
	hour = fposmod(hour + delta * 24.0 / (cycle_min * 60.0), 24.0)
	if _target_hour >= 0.0:
		var diff := wrapf(_target_hour - hour, -12.0, 12.0)
		hour = fposmod(hour + diff * minf(1.0, delta * 1.5), 24.0)
		_target_hour = fposmod(_target_hour + delta * 24.0 / (cycle_min * 60.0), 24.0)
		if absf(diff) < 0.0005:
			_target_hour = -1.0
	_env_t -= delta
	if _env_t <= 0.0:
		_env_t = ENV_S
		apply()
	else:
		_apply_sun()
	if not Net.is_online:
		return
	if multiplayer.is_server():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = SYNC_S
			sync_state.rpc(hour, cycle_min)
	elif not synced and _req_n < 6:
		_req_t -= delta
		if _req_t <= 0.0:
			_req_t = 2.0
			_req_n += 1
			request_state.rpc_id(1)


# --- Anwenden -------------------------------------------------------------------------------------------------

func _apply_sun() -> void:
	if sun == null:
		return
	var l := (_q * to_light(hour)).normalized()
	sun.global_basis = Basis.looking_at(-l, Vector3.UP if absf(l.y) < 0.98 else Vector3.FORWARD)
	var e := energy_of(hour)
	var be := float(_base["sun_energy"])
	sun.light_energy = rel(be, 0.0, maxf(be, 1.3), e, float(_base["energy"]))
	var c := light_color_of(hour)
	var c0: Color = _base["color"]
	var bc: Color = _base["sun_color"]
	var nc := Color(bc.r * c.r / maxf(c0.r, 0.05), bc.g * c.g / maxf(c0.g, 0.05), bc.b * c.b / maxf(c0.b, 0.05))
	var mx := maxf(nc.r, maxf(nc.g, nc.b))
	if mx > 1.0:
		nc = Color(nc.r / mx, nc.g / mx, nc.b / mx)
	sun.light_color = nc
	sun.shadow_enabled = Settings.shadows and sun.light_energy > 0.2
	stats["sun_energy"] = sun.light_energy


func apply() -> void:
	if env == null or _base.is_empty():
		return
	_apply_sun()
	var x := lightness_of(hour)
	var x0 := float(_base["lightness"])
	var s := sun_sin(hour)
	# Umgebungslicht: Grundwert wie Settings.apply_to_world (q_base_amb × Stufenfaktor) × Tageszeitfaktor
	var q := clampi(Settings.quality, 0, 4)
	var amb_q := float(env.get_meta("q_base_amb")) * (1.0 if q >= 3 else 1.12) if env.has_meta("q_base_amb") \
		else float(_base["amb_energy"])
	env.ambient_light_energy = amb_q * rel(1.0, 0.3, 1.25, x, x0)
	var ba: Color = _base["amb_color"]
	env.ambient_light_color = rel_c(ba, Color(0.16, 0.20, 0.34), ba.lerp(Color(0.62, 0.68, 0.78), 0.4), x, x0)
	var be := float(_base["exposure"])
	env.tonemap_exposure = rel(be, be * 1.25, be, x, x0)
	# Nebel: Sichtweite im Spiel umgeschaltet (ViewDistance setzt die Nebelfarbe neu) = neue Originalfarbe. Andere
	# Neusetzungen (sky_fx-Fotohimmel bei Settings.changed) werden überschrieben, nicht übernommen (sonst Drift).
	var vm = mission.get("_view_mode_applied")
	if vm != null and int(vm) != int(_set.get("view_mode", vm)) and not env.fog_light_color.is_equal_approx(_set["fog"]):
		_base["fog"] = env.fog_light_color
	_set["view_mode"] = vm
	var bf: Color = _base["fog"]
	var dusk := clampf(1.0 - absf(s) / 0.22, 0.0, 1.0) - clampf(1.0 - absf(sun_sin(base_hour)) / 0.22, 0.0, 1.0)
	var fog := rel_c(bf, Color(0.035, 0.045, 0.075), bf.lerp(Color(0.70, 0.75, 0.80), 0.5), x, x0)
	fog = fog.lerp(Color(0.85, 0.5, 0.3), maxf(dusk, 0.0) * 0.2)
	env.fog_light_color = fog
	_set["fog"] = fog
	var bv: Color = _base["vol_albedo"]
	env.volumetric_fog_albedo = rel_c(bv, Color(0.05, 0.06, 0.09), bv.lerp(Color(0.75, 0.78, 0.82), 0.5), x, x0)
	if "light_factor" in mission:
		var bl := float(_base["light_factor"])
		mission.light_factor = rel(bl, minf(bl, 0.5), maxf(bl, 1.0), x, x0)
	_apply_sky(x, x0, maxf(dusk, 0.0))
	stats["hour"] = hour
	stats["lightness"] = x


func _apply_sky(x: float, x0: float, dusk: float) -> void:
	var proc: ProceduralSkyMaterial = _base.get("proc")
	var top: Color
	var hor: Color
	var ghor: Color
	if proc:
		var bt: Color = _base["top"]
		var bh: Color = _base["hor"]
		var bg: Color = _base["ghor"]
		top = rel_c(bt, Color(0.01, 0.015, 0.04), bt.lerp(Color(0.25, 0.43, 0.75), 0.6), x, x0)
		hor = rel_c(bh, Color(0.05, 0.06, 0.10), bh.lerp(Color(0.70, 0.76, 0.84), 0.6), x, x0)
		hor = hor.lerp(Color(0.95, 0.55, 0.32), dusk * 0.35)
		ghor = rel_c(bg, Color(0.05, 0.05, 0.06), bg, x, x0)
		proc.sky_top_color = top
		proc.sky_horizon_color = hor
		proc.ground_horizon_color = ghor
	var cur: Material = env.sky.sky_material if env.sky else null
	var clouds: ShaderMaterial = sky_fx.get("material") if sky_fx and "material" in sky_fx else null
	var nv := rel(float(_base["sky_night"]), 1.0, 0.0, x, x0)
	if clouds and proc:
		clouds.set_shader_parameter("sky_top", top)
		clouds.set_shader_parameter("sky_horizon", hor)
		clouds.set_shader_parameter("ground_horizon", ghor)
		clouds.set_shader_parameter("cloud_light", hor.lerp(Color.WHITE, 0.75))
		clouds.set_shader_parameter("night", nv)
		clouds.set_shader_parameter("haze_color", env.fog_light_color)
		var cov := 0.45
		var cl: Dictionary = SkyFxScript.CLIMATES
		cov = float(cl.get(String(sky_fx.get("climate")), [0.45])[0])
		clouds.set_shader_parameter("stars", nv if cov < 0.6 else 0.0)
	var bb := float(_base["bg_energy"])
	if cur == null or cur == proc or (clouds != null and cur == clouds):
		env.background_energy_multiplier = bb
	else:
		env.background_energy_multiplier = rel(bb, bb * 0.08, maxf(bb, 1.0), x, x0)   # Foto-/Sonderhimmel
	stats["sky_night"] = nv


## Zeit setzen (Server; Tests). Im Mehrspieler sofort an alle.
func set_hour(h: float, cycle := -1.0) -> void:
	hour = fposmod(h, 24.0)
	if cycle > 0.0:
		cycle_min = cycle
	_target_hour = -1.0
	apply()
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
	cycle_min = maxf(1.0, cycle)
	sync_count += 1
	if not synced or absf(wrapf(h - hour, -12.0, 12.0)) > 0.25:
		hour = fposmod(h, 24.0)
		_target_hour = -1.0
		apply()
	else:
		_target_hour = fposmod(h, 24.0)
	synced = true
