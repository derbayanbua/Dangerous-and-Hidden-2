extends Node
## Bluteffekte (Kind des Autoloads Effects; ohne class_name). Belege/Abweichung: CLAUDE.md „Bluteffekte“.
## Original [B]: Option „BLUTFLECKEN“ (T2421, ja/nein), Texturen MAPS\x_blood00..05.tga (hd2.exe Formatzeichenkette
## „x_blood%02d.tga“ neben x_expl/x_decal), d_blood/d_bloodflak, blood/blooda.bmp → orig_cache/effects/blood
## (D:\Workspace_D\tools\fmt_blood.py). Wie das Original sie verteilt, ist nicht dekodiert [P].
## Stufen (Settings.blood_level): 0 AUS = nur Trefferklang; 1 ORIGINAL = Spritzer + kleiner Bodenfleck;
## 2 MEHR (BEWUSSTE ABWEICHUNG, Auftraggeber): GPU-Spritzer in Schussrichtung + Austritt (Zone/Schaden), kurzer
## pulsierender Strahl bei schweren Treffern, Spritzer-Decals an Wand/Boden dahinter, wachsende Lachen unter
## Leichen/liegenden Verwundeten. Rein lokal/kosmetisch (MP: aus den ohnehin lokal laufenden Treffern/Toden).
## B-006 Abschluss: Kleidungsblut (Decal an eigener BoneAttachment3D, Renderebene 20 nur Figuren → folgt Animation
## und Ragdoll), Blutspur laufender Verwundeter, Ersatzblut für Treffer ohne Projektil (Messer/Splitter/Ladung),
## roter Bildschirmrand mit Original-Spritzern bei Treffern am aktiven Soldaten. Alles bei Stufe AUS abgeschaltet.

const MAX_SPLATS := 64          ## Wand-/Bodenspritzer (Ringpuffer)
const MAX_POOLS := 24           ## Lachen (älteste blendet aus)
const MAX_JETS := 6
const MAX_SPRAYS := 12          ## gleichzeitige Partikel-Spritzer
const MAX_WOUNDS := 48          ## Kleidungs-Decals an Figuren (Ringpuffer über alle Figuren)
const MAX_WOUNDS_PER := 8       ## je Figur
const MAX_TRAILS := 48          ## Tropfspur-Flecken laufender Verwundeter (Ringpuffer)
const SCAN_S := 1.0
const TRAIL_S := 0.25
const TRAIL_HP := 0.5           ## Spur ab ≤ 50 % Gesundheit [D]
const TRAIL_STEP := 0.9         ## m zwischen zwei Tropfen [D]
const WORLD_MASK := 1
const WOUND_LAYER := 1 << 19    ## Renderebene 20: nur Figurenmeshes – Kleidungs-Decals treffen nicht die Welt

var splats: Array = []
var pools: Array = []
var jets: Array[Dictionary] = []
var sprays: Array = []
var wounds: Array = []
var trails: Array = []
var stats := {"sprays": 0, "jets": 0, "splats": 0, "pools": 0, "wounds": 0, "trails": 0, "edge": 0, "extra_hits": 0}   ## Zähler für Tests
var _tex := {}
var _scan := 0.0
var _trail_t := 0.0
var _drip_next := {}
var _trail_last := {}           ## Soldat-ID -> Ort des letzten Tropfens
var _last_hit := {}             ## Soldat-ID -> Bildnummer des letzten hit() (Ballistik)
var _extra_next := {}           ## Soldat-ID -> ms (Splitter/Messer drosseln)
## Treffer-Feedback am Bildschirmrand (aktiver Soldat): roter Rand + Original-Spritzer x_blood00/04
var edge_layer: CanvasLayer
var edge_alpha := 0.0
var _edge_rect: ColorRect
var _edge_splats: Array = []
var _edge_soldier: Node
var _edge_hp := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Events.soldier_died.connect(_on_died)
	Events.soldier_damaged.connect(_on_damaged)


func reset() -> void:
	splats.clear()
	pools.clear()
	jets.clear()
	sprays.clear()
	wounds.clear()
	trails.clear()
	_drip_next.clear()
	_trail_last.clear()
	_last_hit.clear()
	_extra_next.clear()
	_edge_soldier = null
	_edge_hp = -1.0
	edge_alpha = 0.0
	if edge_layer:
		edge_layer.visible = false


func level() -> int:
	return Settings.blood_level if Settings.blood else 0


func _parent() -> Node3D:
	return get_parent()._parent()


func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var t: Texture2D = null
	var path := OrigLevel.cache_root().path_join("effects/blood/" + name + ".png")
	var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	else:
		t = get_parent()._blood_tex   # ohne Originaldaten: eigene runde Textur
	_tex[name] = t
	return t


func _k() -> float:
	return PerfTuning.QUALITY_K[clampi(Settings.quality, 0, 3)]


## Treffer an einer Figur. dir = Flugrichtung des Geschosses, zone = Trefferzone, victim = Soldat
func hit(pos: Vector3, normal: Vector3, dir: Vector3, zone: StringName, victim: Node) -> void:
	var lv := level()
	var parent := _parent()
	if lv == 0 or parent == null:
		return
	if victim != null and is_instance_valid(victim):
		_last_hit[victim.get_instance_id()] = Engine.get_process_frames()
	if dir.length() < 0.01:
		dir = -normal
	dir = dir.normalized()
	if lv == 1:
		get_parent()._puff(pos, normal, Color(0.4, 0.03, 0.03, 0.9), 5)
		_floor_splat(pos + dir * 0.3, 0.35, "x_blood0%d" % randi_range(1, 3), 2.5)
		return
	var head := zone == &"head"
	var limb := zone == &"arm" or zone == &"leg"
	var strength: float = 1.6 if head else (0.6 if limb else 1.0)
	var dead := victim != null and is_instance_valid(victim) and not bool(victim.get("alive"))
	if dead:
		strength *= 1.2
	# Austritt (Schussrichtung) kräftig, Eintritt (zum Schützen) schwächer
	_spray(parent, pos, dir, strength, 28.0)
	_spray(parent, pos, (-dir + normal * 0.3).normalized(), strength * 0.45, 40.0)
	# Spritzer an Wand/Boden hinter dem Getroffenen
	var space := parent.get_world_3d().direct_space_state
	var reach := 2.0 + 1.5 * strength
	var q := PhysicsRayQueryParameters3D.create(pos + dir * 0.25, pos + dir * reach, WORLD_MASK)
	var h := space.intersect_ray(q)
	if not h.is_empty():
		var tn: String = "x_blood04" if randf() < 0.5 else "x_blood00"
		_splat(h.position, h.normal, (0.45 + 0.35 * strength) * randf_range(0.8, 1.2), tn)
	for i in (3 if head else 2):
		_floor_splat(pos + dir * randf_range(0.4, 1.4) * strength + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)),
			randf_range(0.25, 0.55) * strength, "x_blood0%d" % randi_range(1, 3), 3.0)
	# kurzer pulsierender Strahl bei schweren Treffern (Kopf immer, Rumpf tödlich oder jeder zweite)
	if victim is Node3D and (head or (zone != &"" and not limb and (dead or randf() < 0.5))):
		_jet(victim as Node3D, pos, (dir * 0.6 + normal * 0.4).normalized(), randf_range(1.2, 2.0) if head else randf_range(0.5, 1.6))
	# Blut auf der Kleidung: Einschuss (zum Schützen) und Austritt (Schussrichtung), am nächsten Knochen
	if victim is Node3D:
		wound(victim as Node3D, pos, normal if normal.length() > 0.01 else -dir, 0.16 + 0.06 * strength)
		wound(victim as Node3D, pos + dir * 0.18, dir, 0.2 + 0.08 * strength)


# --- Blut auf der Kleidung (Decal auf dem Skin-Mesh, hängt am Knochen → folgt Animation/Ragdoll) ---------------

## Nächster Knochen des Skeletts zur Weltposition (−1 ohne Skelett)
static func nearest_bone(sk: Skeleton3D, pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in sk.get_bone_count():
		var d := (sk.global_transform * sk.get_bone_global_pose(i).origin).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best


## Anker für Kleidungsblut: eigene BoneAttachment3D am nächsten Knochen der Figur; ohne Skelett die nächste
## Trefferzone (Platzhalterpuppe: Gliedknoten), sonst die Figur selbst.
func _wound_anchor(victim: Node3D, pos: Vector3) -> Node3D:
	var best: Skeleton3D = null
	for sk in victim.find_children("*", "Skeleton3D", true, false):
		if (sk as Skeleton3D).is_visible_in_tree() and (sk as Skeleton3D).get_bone_count() > 0:
			best = sk
			break
	if best != null:
		var bi := nearest_bone(best, pos)
		if bi >= 0:
			var bname := best.get_bone_name(bi)
			var nm := "BloodBone_" + bname.validate_node_name()
			var ba := best.get_node_or_null(nm) as BoneAttachment3D
			if ba == null:
				ba = BoneAttachment3D.new()
				ba.name = nm
				best.add_child(ba)
				ba.bone_name = bname
			return ba
	var hb_best: Node3D = null
	var hd := INF
	for hb in victim.find_children("*", "Hitbox", true, false):
		var d := (hb as Node3D).global_position.distance_squared_to(pos)
		if d < hd:
			hd = d
			hb_best = hb
	return hb_best if hb_best != null else victim


## Figurenmeshes auf Renderebene 20 legen (zusätzlich, bestehende Ebenen bleiben) – nur sie empfangen Kleidungsblut
func _mark_meshes(victim: Node3D) -> void:
	for mi in victim.find_children("*", "VisualInstance3D", true, false):
		if not (mi is Decal) and not (mi is GPUParticles3D):
			(mi as VisualInstance3D).layers |= WOUND_LAYER


## Blutfleck auf der Kleidung. normal = von der Körperoberfläche nach außen.
func wound(victim: Node3D, pos: Vector3, normal: Vector3, size: float) -> Decal:
	if level() < 2 or victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return null
	var mine: Array = []
	for w in wounds:
		if is_instance_valid(w) and w.get_meta("owner_soldier", 0) == victim.get_instance_id():
			mine.append(w)
	if mine.size() >= MAX_WOUNDS_PER:
		_drop_wound(mine[0])
	_mark_meshes(victim)
	var anchor := _wound_anchor(victim, pos)
	var d := Decal.new()
	d.name = "BloodWound"
	d.texture_albedo = tex("x_blood0%d" % (4 if randf() < 0.5 else 0))
	d.modulate = Color(0.55, 0.04, 0.03)
	d.albedo_mix = 0.95
	d.cull_mask = WOUND_LAYER
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.35
	d.distance_fade_enabled = true
	d.distance_fade_begin = 35.0 * _k()
	d.distance_fade_length = 8.0
	d.size = Vector3(size, 0.22, size)
	d.set_meta("owner_soldier", victim.get_instance_id())
	anchor.add_child(d)
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, x.cross(up)).orthonormalized().rotated(up, randf() * TAU), pos)
	wounds.append(d)
	stats["wounds"] += 1
	while wounds.size() > MAX_WOUNDS:
		_drop_wound(wounds[0])
	return d


func _drop_wound(w) -> void:
	wounds.erase(w)
	if is_instance_valid(w):
		w.queue_free()


# --- Treffer ohne Projektil (Messer, Splitter, Sprengladung, Hund) ---------------------------------------------

func _on_damaged(s: Node, amount: float, zone: StringName, attacker: Node) -> void:
	if level() == 0 or amount < 1.0 or attacker == null or attacker == s or not (s is Node3D):
		return
	call_deferred("_extra_hit", s.get_instance_id(), Engine.get_process_frames(), zone, attacker.get_instance_id())


## Kam im selben Bild kein Ballistik-Treffer (Effects.blood) für dieses Opfer, Blut an der Trefferzone erzeugen
func _extra_hit(id: int, frame: int, zone: StringName, att_id: int) -> void:
	if int(_last_hit.get(id, -1)) >= frame:
		return
	var s := instance_from_id(id) as Node3D
	if s == null or not is_instance_valid(s) or not s.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if int(_extra_next.get(id, 0)) > now:
		return
	_extra_next[id] = now + 150
	var z: StringName = zone if zone in [&"head", &"arm", &"leg"] else &"torso"
	var pos := body_center(s)
	for hb in s.find_children("*", "Hitbox", true, false):
		if (hb as Hitbox).zone == z:
			pos = (hb as Node3D).global_position
			break
	var att := instance_from_id(att_id) as Node3D
	var dir := (pos - att.global_position) if att != null and is_instance_valid(att) else -s.global_basis.z
	dir.y *= 0.3
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	stats["extra_hits"] += 1
	hit(pos, -dir, dir, z, s)


func _particle_mat(tn: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(tn)
	m.albedo_color = Color(0.55, 0.03, 0.03)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process_mat(dir: Vector3, spread: float, vmin: float, vmax: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0.7, 0.7, 0.7, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _spray(parent: Node3D, pos: Vector3, dir: Vector3, strength: float, spread: float) -> void:
	while sprays.size() >= MAX_SPRAYS:
		var old = sprays.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = clampi(int(22.0 * strength * _k()), 6, 48)
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.process_material = _process_mat(dir, spread, 1.5 * strength, 5.5 * strength)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07) * (1.0 + 0.3 * strength)
	qm.material = _particle_mat("x_blood0%d" % randi_range(1, 3))
	p.draw_pass_1 = qm
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	p.visibility_range_end = 70.0 * _k()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	sprays.append(p)
	stats["sprays"] += 1
	get_tree().create_timer(p.lifetime + 0.4, false).timeout.connect(p.queue_free)


func _jet(victim: Node3D, pos: Vector3, dir: Vector3, dur: float) -> void:
	if jets.size() >= MAX_JETS:
		var old: Dictionary = jets.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
	var p := GPUParticles3D.new()
	p.amount = clampi(int(28.0 * _k()), 10, 40)
	p.lifetime = 0.7
	p.process_material = _process_mat(Vector3(0, 0, 1), 10.0, 1.6, 3.2)
	p.local_coords = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	qm.material = _particle_mat("x_blood01")
	p.draw_pass_1 = qm
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	victim.add_child(p)
	p.global_position = pos
	# lokale +Z = Strahlrichtung (Prozessmaterial-Richtung), folgt danach der Figur
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	p.global_basis = Basis.looking_at(-dir, up)
	p.emitting = true
	jets.append({"node": p, "t": 0.0, "dur": dur, "victim": victim})
	stats["jets"] += 1


func _process(delta: float) -> void:
	for j in jets.duplicate():
		if not is_instance_valid(j["node"]):      # Opfer samt Strahl entfernt (Rundenwechsel/Leiche weg)
			jets.erase(j)
			continue
		var p: GPUParticles3D = j["node"]
		j["t"] += delta
		var t: float = j["t"]
		var dur: float = j["dur"]
		if t >= dur:
			p.emitting = false
			jets.erase(j)
			get_tree().create_timer(p.lifetime + 0.2, false).timeout.connect(p.queue_free)
			continue
		# Herzschlag ~1,6 Hz, abklingend
		var pulse := 0.35 + 0.65 * pow(maxf(sin(t * TAU * 1.6), 0.0), 2.0)
		p.amount_ratio = clampf(pulse * (1.0 - t / dur), 0.05, 1.0)
		p.speed_scale = 0.7 + 0.5 * pulse
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		_scan_soldiers()
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = TRAIL_S
		_trail_tick()
		_follow_pools()
	_edge_tick(delta)


# --- Blutspuren laufender Verwundeter ----------------------------------------------------------------------------

func _trail_tick() -> void:
	if level() < 2 or _parent() == null:
		return
	for s in get_tree().get_nodes_in_group("soldiers"):
		if not (s is Node3D) or not bool(s.get("alive")):
			continue
		var mh := float(s.get("max_health")) if s.get("max_health") != null else 100.0
		if float(s.get("health")) > TRAIL_HP * mh:
			continue
		var key: int = s.get_instance_id()
		var p: Vector3 = (s as Node3D).global_position
		if not _trail_last.has(key):
			_trail_last[key] = p
			continue
		var last: Vector3 = _trail_last[key]
		if Vector2(p.x - last.x, p.z - last.z).length() < TRAIL_STEP * randf_range(0.8, 1.3):
			continue
		_trail_last[key] = p
		var d := _floor_splat(p + Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15)), randf_range(0.12, 0.24),
			"x_blood0%d" % randi_range(1, 3), 2.0, 0.0, false, true)
		if d != null:
			d.set_meta("owner_soldier", key)


## Lachen wachsen unter der Körpermitte – folgt die Leiche noch (Ragdoll rutscht/kippt), wandert die Lache mit
func _follow_pools() -> void:
	if _parent() == null:
		return
	var now := Time.get_ticks_msec()
	for d in pools:
		if not is_instance_valid(d) or int(d.get_meta("follow_until", 0)) < now:
			continue
		var s := instance_from_id(int(d.get_meta("owner_soldier", 0))) as Node3D
		if s == null or not is_instance_valid(s):
			continue
		var c := body_center(s)
		if Vector2(c.x - d.global_position.x, c.z - d.global_position.z).length() < 0.08:
			continue
		var h := _parent().get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.6, c + Vector3.DOWN * 2.5, WORLD_MASK))
		if not h.is_empty():
			d.global_position = h.position


# --- Treffer-Feedback am Bildschirmrand ---------------------------------------------------------------------------

func _active_soldier() -> Node:
	var m = Game.current_mission()
	if m == null or not is_instance_valid(m):
		return null
	var c = m.get("controller")
	return c.get("active") if c != null and is_instance_valid(c) else null


func _edge_tick(delta: float) -> void:
	var s := _active_soldier()
	if level() == 0 or s == null or not is_instance_valid(s):
		_edge_hp = -1.0
		_edge_soldier = s
		edge_alpha = 0.0
		if edge_layer:
			edge_layer.visible = false
		return
	var hp := float(s.get("health"))
	var mh := float(s.get("max_health")) if s.get("max_health") != null else 100.0
	if s != _edge_soldier:
		_edge_soldier = s
		_edge_hp = hp
	# Gesundheitsabfall statt Schadenssignal: gilt auch für Netz-Clients (Gesundheit kommt per Net._hp)
	if _edge_hp >= 0.0 and hp < _edge_hp - 0.5 and bool(s.get("alive")):
		flash_edge(clampf((_edge_hp - hp) / maxf(mh, 1.0) * 3.0, 0.35, 1.0))
	_edge_hp = hp
	var low := 0.0
	if bool(s.get("alive")) and hp < 0.35 * mh:
		low = 0.18 + 0.1 * sin(Time.get_ticks_msec() * 0.001 * TAU * 1.2)   # Herzschlag bei schwerer Verwundung
	edge_alpha = maxf(edge_alpha - delta * 0.8, 0.0)
	var a := maxf(edge_alpha, low)
	if edge_layer == null:
		if a <= 0.0:
			return
		_build_edge()
	edge_layer.visible = a > 0.005
	(_edge_rect.material as ShaderMaterial).set_shader_parameter("intensity", a)
	for sp in _edge_splats:
		(sp as TextureRect).modulate.a = clampf(edge_alpha * 1.4, 0.0, 0.9)


## Treffer am aktiven Soldaten: Rand aufblitzen, 2–3 Original-Spritzer an zufälligen Randstellen
func flash_edge(strength: float) -> void:
	if level() == 0:
		return
	if edge_layer == null:
		_build_edge()
	edge_alpha = clampf(maxf(edge_alpha, strength), 0.0, 1.0)
	stats["edge"] += 1
	var vs := edge_layer.get_viewport().get_visible_rect().size if edge_layer.is_inside_tree() else Vector2(1280, 720)
	var n := 2 if level() < 2 else 3
	for i in _edge_splats.size():
		var sp: TextureRect = _edge_splats[i]
		sp.visible = i < n
		var side := randi() % 4
		var sz := vs.y * randf_range(0.22, 0.34)
		sp.size = Vector2(sz, sz)
		sp.pivot_offset = sp.size * 0.5
		sp.rotation = randf() * TAU
		var t := randf_range(0.1, 0.9)
		match side:
			0: sp.position = Vector2(vs.x * t, 0) - sp.size * Vector2(0.5, 0.6)
			1: sp.position = Vector2(vs.x * t, vs.y) - sp.size * Vector2(0.5, 0.4)
			2: sp.position = Vector2(0, vs.y * t) - sp.size * Vector2(0.6, 0.5)
			_: sp.position = Vector2(vs.x, vs.y * t) - sp.size * Vector2(0.4, 0.5)


func _build_edge() -> void:
	edge_layer = CanvasLayer.new()
	edge_layer.name = "BloodEdge"
	edge_layer.layer = 4          # unter dem HUD (5) und allen Menüs
	add_child(edge_layer)
	_edge_rect = ColorRect.new()
	_edge_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float intensity = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p * vec2(0.9, 1.0));
	float a = smoothstep(0.55, 1.35, r) * intensity;
	COLOR = vec4(0.45, 0.0, 0.0, a * 0.85);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_edge_rect.material = sm
	edge_layer.add_child(_edge_rect)
	for i in 3:
		var sp := TextureRect.new()
		sp.texture = tex("x_blood04" if i % 2 == 0 else "x_blood00")
		sp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sp.stretch_mode = TextureRect.STRETCH_SCALE
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.self_modulate = Color(0.6, 0.03, 0.02)
		sp.modulate.a = 0.0
		sp.visible = false
		edge_layer.add_child(sp)
		_edge_splats.append(sp)


## Leichen (auch bereits liegende/geladene) und liegende Schwerverwundete bekommen eine Lache
func _scan_soldiers() -> void:
	if level() < 2 or _parent() == null:
		return
	for c in get_tree().get_nodes_in_group("corpses"):
		if c is Node3D and not c.has_meta("_blood_pool"):
			c.set_meta("_blood_pool", true)
			_pool_for(c as Node3D, randf_range(1.1, 1.6), 0.0)
	for s in get_tree().get_nodes_in_group("soldiers"):
		if not (s is Node3D) or not bool(s.get("alive")) or s.has_meta("_blood_pool"):
			continue
		var hp := float(s.get("health"))
		if hp <= 0.0 or hp > 35.0:
			continue
		var vel = s.get("velocity")
		if vel is Vector3 and (vel as Vector3).length() > 0.3:
			continue
		var key: int = s.get_instance_id()
		var now := Time.get_ticks_msec()
		if int(_drip_next.get(key, 0)) > now:
			continue
		_drip_next[key] = now + 6000
		_floor_splat((s as Node3D).global_position, randf_range(0.3, 0.5), "x_blood05", 2.0, 4.0)


func _on_died(soldier: Node, _attacker: Node) -> void:
	if level() < 2 or not (soldier is Node3D) or soldier.has_meta("_blood_pool"):
		return
	soldier.set_meta("_blood_pool", true)
	_pool_for(soldier as Node3D, randf_range(1.2, 1.8), 1.0)   # nach dem Fallen


## Körpermitte: Rumpf-Trefferzone (folgt dem Todesclip), sonst Figurenursprung
func body_center(s: Node3D) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for hb in s.find_children("*", "Hitbox", true, false):
		if (hb as Hitbox).zone == &"torso":
			sum += (hb as Node3D).global_position
			n += 1
	return sum / n if n > 0 else s.global_position


func _pool_for(s: Node3D, size: float, delay: float) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay, false).timeout.connect(_pool_later.bind(s.get_instance_id(), size))
		return
	var grow := randf_range(6.0, 10.0)
	var d := _floor_splat(body_center(s), size, "x_blood05", 2.5, grow, true)
	if d != null:
		d.set_meta("owner_soldier", s.get_instance_id())
		d.set_meta("follow_until", Time.get_ticks_msec() + int(grow * 1000.0))


func _pool_later(id: int, size: float) -> void:
	var s := instance_from_id(id) as Node3D
	if s != null and is_instance_valid(s):
		_pool_for(s, size, 0.0)


## Fleck/Lache auf dem Boden (Raycast nach unten, auf die Bodennormale ausgerichtet). grow > 0 = wächst so lange.
func _floor_splat(pos: Vector3, size: float, tn: String, down := 2.5, grow := 0.0, pool := false, trail := false) -> Decal:
	var parent := _parent()
	if parent == null:
		return null
	var space := parent.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.DOWN * down, WORLD_MASK)
	var h := space.intersect_ray(q)
	if h.is_empty():
		return null
	return _splat(h.position, h.normal, size, tn, grow, pool or tn == "x_blood05", trail)


func _splat(pos: Vector3, normal: Vector3, size: float, tn: String, grow := 0.0, pool := false, trail := false) -> Decal:
	var parent := _parent()
	if parent == null:
		return null
	var d := Decal.new()
	d.texture_albedo = tex(tn)
	d.modulate = Color(0.75, 0.06, 0.05) if pool else Color(0.9, 0.12, 0.1)
	d.albedo_mix = 1.0
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 50.0 * _k()
	d.distance_fade_length = 10.0
	d.size = Vector3(size, 0.5, size)
	parent.add_child(d)
	d.global_position = pos
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	d.global_basis = Basis(x, up, x.cross(up)).orthonormalized().rotated(up, randf() * TAU)
	if grow > 0.0:
		d.size = Vector3(size * 0.15, 0.5, size * 0.15)
		var tw := d.create_tween()
		tw.tween_property(d, "size", Vector3(size, 0.5, size), grow).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var ring: Array = pools if pool else (trails if trail else splats)
	var cap := MAX_POOLS if pool else (MAX_TRAILS if trail else MAX_SPLATS)
	ring.append(d)
	stats["pools" if pool else ("trails" if trail else "splats")] += 1
	while ring.size() > cap:
		var old = ring.pop_front()
		if is_instance_valid(old):
			var tw2: Tween = old.create_tween()
			tw2.tween_property(old, "modulate:a", 0.0, 1.5)
			tw2.tween_callback(old.queue_free)
	return d
