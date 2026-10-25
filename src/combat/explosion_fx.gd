extends RefCounted
## B-013 – Explosionsdarstellung (BEWUSSTE ABWEICHUNG vom Original, Vorgabe Auftraggeber: rein optisch;
## Schaden/Radius kommen unverändert aus items.sav über WeaponDB.explosion_damage bei den Aufrufern).
## Aufbau je Explosion (Kind-Knoten eines „Explosion“-Wurzelknotens, gemeinsam freigegeben):
##   Fireball (GPU-Partikel, additiv), Smoke (aufsteigende, beleuchtete Rauchsäule), Debris (Trümmer mit Schwerkraft),
##   Sparks (Funken entlang der Flugrichtung), Shockwave (Bodenring + Staub), HeatHaze (Hitzeflimmern, Bildschirm-
##   verzerrung), Flash (kurzes Licht, flackernd). Mengen/Teile je Grafikstufe (Settings.quality 0..4):
##   Niedrig: nur Feuerball, Rauch, Licht (wenige Partikel); Mittel +Trümmer/Funken; Hoch +Druckwelle;
##   Ultra/4K Ultra +Hitzeflimmern, Turbulenz, Lichtschatten, größere Texturen.
## Texturen werden prozedural neu erzeugt (Rauschen → weiche Rauchballen), keine Originaldaten.

const COUNT_K := [0.35, 0.6, 1.0, 1.4, 2.0]
static var _puff_cache := {}
static var _ring_shader: Shader
static var _haze_shader: Shader


## kind: &"" Granate/Standard, &"artillery"/&"air" (B-011: große Säule), &"vehicle" (Brand, lange Rauchfahne),
## &"water" (Wasserfontäne statt Feuerball). Liefert {"node": Wurzel, "parts": [Namen], "lifetime": s}.
static func spawn(parent: Node3D, pos: Vector3, radius: float, q: int, kind: StringName = &"") -> Dictionary:
	q = clampi(q, 0, 4)
	var k: float = COUNT_K[q]
	var rs := clampf(radius / 4.0, 0.5, 4.0)          # Größenmaßstab (Granate r≈4–6 m → 1–1,5)
	var big := kind == &"artillery" or kind == &"air"
	if big:
		rs *= 1.4
	var water := kind == &"water"
	var root := Node3D.new()
	root.name = "Explosion"
	parent.add_child(root)
	root.global_position = pos
	var parts: PackedStringArray = []
	var tex_res: int = 256 if q >= 3 else (128 if q >= 1 else 64)
	var puff := puff_texture(tex_res)
	if not water:
		root.add_child(_fireball(rs, k, puff, q))
		parts.append("Fireball")
	var smoke_life: float = (6.0 if big or kind == &"vehicle" else 4.5) * (1.0 if q >= 2 else 0.7)
	root.add_child(_smoke(rs, k, puff, q, smoke_life, water))
	parts.append("Smoke")
	if q >= 1:
		root.add_child(_debris(rs, k, water))
		parts.append("Debris")
		if not water:
			root.add_child(_sparks(rs, k))
			parts.append("Sparks")
	if q >= 2:
		_shockwave(root, radius)
		parts.append("Shockwave")
	if q >= 3 and not water:
		_heat_haze(root, rs)
		parts.append("HeatHaze")
	if not water:
		_flash(root, radius, q)
		parts.append("Flash")
	var life := smoke_life + 1.5
	root.get_tree().create_timer(life, false).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free())
	return {"node": root, "parts": parts, "lifetime": life}


static func _particles(pname: String, amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pname
	p.amount = maxi(amount, 2)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 60, 60))
	p.emitting = true
	return p


static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(e): return float(e[0])))
	g.colors = PackedColorArray(points.map(func(e): return e[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for e in points:
		c.add_point(Vector2(e[0], e[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _billboard_mat(tex: Texture2D, additive: bool, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.proximity_fade_enabled = true       # weiche Kanten am Boden (Soft Particles)
	m.proximity_fade_distance = 0.6
	return m


static func _fireball(rs: float, k: float, puff: Texture2D, q: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 * rs
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5 * rs
	pm.initial_velocity_max = 6.0 * rs
	pm.damping_min = 5.0
	pm.damping_max = 9.0
	pm.gravity = Vector3(0, 1.2, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.8
	pm.scale_max = 1.5
	pm.scale_curve = _curve([[0.0, 0.35], [0.25, 1.0], [1.0, 1.3]])
	pm.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.8, 1.0)], [0.12, Color(1.0, 0.7, 0.25, 1.0)],
		[0.45, Color(0.85, 0.28, 0.06, 0.8)], [0.75, Color(0.25, 0.08, 0.03, 0.4)], [1.0, Color(0, 0, 0, 0)]])
	if q >= 3:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.5
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * 1.6 * rs
	qm.material = _billboard_mat(puff, true, false)
	var p := _particles("Fireball", int(28.0 * k * clampf(rs, 1.0, 2.5)), 0.9, pm, qm)
	p.explosiveness = 1.0
	return p


static func _smoke(rs: float, k: float, puff: Texture2D, q: int, life: float, water: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6 * rs
	pm.direction = Vector3.UP
	pm.spread = 25.0 if not water else 12.0
	pm.initial_velocity_min = 1.5 * rs
	pm.initial_velocity_max = (4.5 if not water else 9.0) * rs
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.gravity = Vector3(0.25, 0.5, 0.0) if not water else Vector3(0, -6.0, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.scale_min = 0.9
	pm.scale_max = 1.6
	pm.scale_curve = _curve([[0.0, 0.4], [0.3, 1.0], [1.0, 2.4]])
	if water:
		pm.color_ramp = _ramp([[0.0, Color(0.9, 0.95, 1.0, 0.0)], [0.08, Color(0.9, 0.95, 1.0, 0.85)],
			[1.0, Color(0.85, 0.9, 0.95, 0.0)]])
	else:
		pm.color_ramp = _ramp([[0.0, Color(0.25, 0.22, 0.2, 0.0)], [0.06, Color(0.22, 0.19, 0.17, 0.85)],
			[0.5, Color(0.32, 0.3, 0.28, 0.6)], [1.0, Color(0.45, 0.43, 0.41, 0.0)]])
	if q >= 3:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.8
		pm.turbulence_noise_scale = 6.0
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * 2.2 * rs
	qm.material = _billboard_mat(puff, false, true)
	var p := _particles("Smoke", int(22.0 * k * clampf(rs, 1.0, 2.5)), life, pm, qm)
	p.explosiveness = 0.75
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p


static func _debris(rs: float, k: float, water: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3 * rs
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 5.0 * sqrt(rs)
	pm.initial_velocity_max = 15.0 * sqrt(rs)
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.scale_min = 0.4
	pm.scale_max = 1.6
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.07, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 1.0, 0.8) if water else Color(0.22, 0.19, 0.16)
	if water:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.95
	bm.material = m
	var p := _particles("Debris", int(24.0 * k), 1.8, pm, bm)
	p.explosiveness = 1.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	return p


static func _sparks(rs: float, k: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 10.0 * sqrt(rs)
	pm.initial_velocity_max = 24.0 * sqrt(rs)
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.particle_flag_align_y = true          # Funken als Striche entlang der Flugrichtung
	pm.scale_curve = _curve([[0.0, 1.0], [1.0, 0.2]])
	pm.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.5, Color(1.0, 0.55, 0.15, 1.0)], [1.0, Color(0.6, 0.15, 0.0, 0.0)]])
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.45, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.material = m
	var p := _particles("Sparks", int(36.0 * k), 0.9, pm, bm)
	p.explosiveness = 1.0
	return p


## Druckwelle: schnell wachsender Staub-/Hitzering am Boden (0,4 s)
static func _shockwave(root: Node3D, radius: float) -> MeshInstance3D:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float progress = 0.0;
uniform vec4 tint : source_color = vec4(0.75, 0.68, 0.58, 0.55);
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float edge = progress;
	float w = 0.08 + 0.25 * progress;
	float ring = smoothstep(edge - w, edge, r) * (1.0 - smoothstep(edge, edge + 0.04, r));
	float n = 0.6 + 0.4 * h(vec2(floor(a * 18.0), 3.0));
	ALBEDO = tint.rgb;
	ALPHA = ring * n * tint.a * (1.0 - progress);
}
"""
	var mi := MeshInstance3D.new()
	mi.name = "Shockwave"
	var pl := PlaneMesh.new()
	pl.size = Vector2.ONE * radius * 3.0
	mi.mesh = pl
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3.UP * 0.15
	root.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, 0.45)
	return mi


## Hitzeflimmern: wachsende Kugel, die das Bild dahinter verzerrt (Bildschirmtextur)
static func _heat_haze(root: Node3D, rs: float) -> MeshInstance3D:
	if _haze_shader == null:
		_haze_shader = Shader.new()
		_haze_shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	vec2 off = NORMAL.xy * strength * rim * 0.035 * (0.7 + 0.3 * sin(TIME * 40.0 + UV.x * 30.0));
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = clamp(rim * 2.0, 0.0, 1.0) * step(0.001, strength);
}
"""
	var mi := MeshInstance3D.new()
	mi.name = "HeatHaze"
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = _haze_shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3.UP * rs
	mi.scale = Vector3.ONE * 0.3 * rs
	root.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 5.0 * rs, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): m.set_shader_parameter("strength", v), 1.0, 0.0, 0.6)
	return mi


static func _flash(root: Node3D, radius: float, q: int) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 16.0
	light.omni_range = radius * 4.0
	light.shadow_enabled = q >= 3
	light.position = Vector3.UP * 1.2
	root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 6.0, 0.08)
	tw.tween_property(light, "light_energy", 9.0, 0.06)
	tw.tween_property(light, "light_energy", 0.0, 0.55).set_ease(Tween.EASE_IN)
	return light


## Weicher Rauch-/Feuerballen: radialer Verlauf × Rauschen (prozedural, je Auflösung zwischengespeichert)
static func puff_texture(res: int) -> Texture2D:
	if _puff_cache.has(res):
		return _puff_cache[res]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 4
	n.frequency = 6.0 / float(res)
	n.seed = 4711
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var c := float(res) * 0.5
	for y in res:
		for x in res:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = smoothstep(0.0, 1.0, a) * clampf(0.35 + v * 0.9, 0.0, 1.0)
			var b := 0.75 + 0.25 * v
			img.set_pixel(x, y, Color(b, b, b, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_puff_cache[res] = tex
	return tex


## Brandfleck-Textur für das Decal (dunkler, ausgefranster Fleck)
static func scorch_texture(res: int) -> Texture2D:
	var key := -res
	if _puff_cache.has(key):
		return _puff_cache[key]
	var n := FastNoiseLite.new()
	n.fractal_octaves = 5
	n.frequency = 5.0 / float(res)
	n.seed = 99
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var c := float(res) * 0.5
	for y in res:
		for x in res:
			var p := Vector2(x + 0.5 - c, y + 0.5 - c)
			var d := p.length() / c + n.get_noise_2d(x, y) * 0.35
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 0.5) * 0.92
			var g := 0.03 + 0.05 * (n.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(g, g * 0.9, g * 0.8, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_puff_cache[key] = tex
	return tex
