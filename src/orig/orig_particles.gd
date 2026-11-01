class_name OrigParticles
extends RefCounted
## Original-Partikeleffekte (B-028/O-007): TABLES\effects.def → tools/fmt_particles.py → orig_cache/effects/particles.json
## (+ Texturen effects/particles/d_*.png). Index = FRM_CreateParticle/FRM_CreateIndexedParticle-Nummer = Eintrag in der
## Tabelle (Name „NN - …“, Zuordnung über Skriptverwendung belegt, docs/status/b028.md).
## Je Emitter ein GPUParticles3D: Stoß (burst > 0, einmalig) bzw. Dauerausstoß (rate/s), Lebensdauer life_ms, Farbe/Alpha-
## verlauf, Steigen/Schwerkraft, Mischart additiv (blend 2) – Feldbedeutungen [P] aus Wertemustern, Partikelbewegung des
## LS3DF.dll nicht dekodiert [E]. Ohne Cache: bisheriger Platzhalter (Rauch/Feuer).

static var _table: Array = []
static var _loaded := false
static var _tex := {}
static var created: Array = []      ## Diagnose/Tests: [id, kind, emitter_count]


static func table() -> Array:
	if not _loaded:
		_loaded = true
		var p := OrigLevel.cache_root() + "/effects/particles.json"
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(d) == TYPE_DICTIONARY:
				_table = d.get("effects", [])
	return _table


static func definition(id: int) -> Dictionary:
	var t := table()
	return t[id] if id >= 0 and id < t.size() else {}


static func kind_of(id: int) -> String:
	var d := definition(id)
	return String(d.get("kind", "fire" if id in [43, 53] else "smoke"))


## Dauereffekt (mindestens ein Emitter mit Ausstoßrate) – sonst endet der Effekt nach dem Stoß
static func is_continuous(id: int) -> bool:
	var d := definition(id)
	if d.is_empty():
		return true
	for e in d.get("emitters", []):
		if int(e.get("rate", 0)) > 0:
			return true
	return false


static func _texture(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var p := OrigLevel.cache_root() + "/effects/particles/" + name.get_basename() + ".png"
	var t: Texture2D = null
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img:
			t = ImageTexture.create_from_image(img)
	_tex[name] = t
	return t


## Erzeugt den Effekt an pos unter parent. Rückgabe: Wurzelknoten (Kinder = ein GPUParticles3D je Emitter).
static func spawn(id: int, pos: Vector3, parent: Node) -> Node3D:
	var d := definition(id)
	var root := Node3D.new()
	root.name = "OrigParticle_%d" % id
	root.set_meta("particle_id", id)
	root.set_meta("particle_kind", kind_of(id))
	parent.add_child(root)
	root.global_position = pos
	var ems: Array = d.get("emitters", [])
	if ems.is_empty():
		ems = [{"rate": 15, "life_ms": 3000, "end_color": [1.0, 0.55, 0.15] if kind_of(id) == "fire" else [0.2, 0.2, 0.2],
			"alpha": [0.6, 0.5, 0.0], "rise": 2.0, "size": [0.6, 1.6, 0.6, 1.6]}]
	var additive := int(d.get("blend", 1)) == 2
	var tex := _texture(String(d.get("texture", "")))
	var max_life := 0.0
	for e in ems:
		var gp := _emitter(e, additive, tex)
		root.add_child(gp)
		max_life = maxf(max_life, gp.lifetime)
		gp.emitting = true
	var k := kind_of(id)
	if k in ["fire", "explosion"]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 12.0 if k == "explosion" else 8.0
		l.light_energy = 3.0 if k == "explosion" else 1.6
		root.add_child(l)
		if not is_continuous(id):
			var tw := root.create_tween()
			tw.tween_property(l, "light_energy", 0.0, maxf(max_life, 0.5))
	root.set_meta("max_life", max_life)
	created.append([id, k, ems.size()])
	return root


static func _emitter(e: Dictionary, additive: bool, tex: Texture2D) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	var burst := int(e.get("burst", 0))
	var rate := int(e.get("rate", 0))
	var life := clampf(float(e.get("life_ms", 2000)) / 1000.0, 0.1, 12.0)
	gp.lifetime = life
	if burst > 0 and rate <= 0:
		gp.one_shot = true
		gp.explosiveness = 0.9
		gp.amount = clampi(burst, 1, 256)
	else:
		gp.amount = clampi(int(ceil(maxf(rate, 1) * life)), 1, 512)
	gp.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 24, 20))
	var pm := ParticleProcessMaterial.new()
	var ext: Array = e.get("extent", [0.0, 0.0, 0.0])
	if ext.size() == 3 and (float(ext[0]) > 0.0 or float(ext[1]) > 0.0 or float(ext[2]) > 0.0):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(float(ext[0]), float(ext[1]), float(ext[2])) * 0.5
	var sp: Array = e.get("speed", [0.5, 1.5])
	var rise := float(e.get("rise", 0.0))
	pm.direction = Vector3.UP
	pm.spread = 180.0 if burst > 0 and rate <= 0 else 15.0
	pm.initial_velocity_min = maxf(float(sp[0]) if sp.size() > 0 else 0.5, rise * 0.5)
	pm.initial_velocity_max = maxf(float(sp[1]) if sp.size() > 1 else 1.5, rise)
	pm.gravity = Vector3(0.0, float(e.get("gravity", 0.0)), 0.0)
	var sz: Array = e.get("size", [0.5, 1.0, 0.5, 1.0])
	pm.scale_min = clampf(float(sz[0]) if sz.size() > 0 else 0.5, 0.05, 8.0) * 2.0
	pm.scale_max = clampf(float(sz[1]) if sz.size() > 1 else 1.0, 0.05, 8.0) * 2.0 + pm.scale_min * 0.5
	var col: Array = e.get("end_color", [1.0, 1.0, 1.0])
	var al: Array = e.get("alpha", [1.0, 1.0, 0.0])
	var c := Color(float(col[0]), float(col[1]), float(col[2]))
	var gr := Gradient.new()
	gr.set_color(0, Color(c, float(al[0]) if al.size() > 0 else 1.0))
	gr.set_color(1, Color(c, 0.0))
	gr.add_point(0.5, Color(c, float(al[1]) if al.size() > 1 else 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex:
		m.albedo_texture = tex
	q.material = m
	gp.draw_pass_1 = q
	return gp


## Effekt beenden: Ausstoß aus, nach der Lebensdauer entfernen
static func stop(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var life := float(n.get_meta("max_life", 1.0)) if n.has_meta("max_life") else 1.0
	for c in n.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = false
			life = maxf(life, (c as GPUParticles3D).lifetime)
	n.get_tree().create_timer(life + 0.5, false).timeout.connect(n.queue_free)
