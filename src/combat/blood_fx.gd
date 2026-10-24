extends Node
## Bluteffekte (Kind des Autoloads Effects; ohne class_name). Belege/Abweichung: CLAUDE.md „Bluteffekte“.
## Original [B]: Option „BLUTFLECKEN“ (T2421, ja/nein), Texturen MAPS\x_blood00..05.tga (hd2.exe Formatzeichenkette
## „x_blood%02d.tga“ neben x_expl/x_decal), d_blood/d_bloodflak, blood/blooda.bmp → orig_cache/effects/blood
## (D:\Workspace_D\tools\fmt_blood.py). Wie das Original sie verteilt, ist nicht dekodiert [P].
## Stufen (Settings.blood_level): 0 AUS = nur Trefferklang; 1 ORIGINAL = Spritzer + kleiner Bodenfleck;
## 2 MEHR (BEWUSSTE ABWEICHUNG, Auftraggeber): GPU-Spritzer in Schussrichtung + Austritt (Zone/Schaden), kurzer
## pulsierender Strahl bei schweren Treffern, Spritzer-Decals an Wand/Boden dahinter, wachsende Lachen unter
## Leichen/liegenden Verwundeten. Rein lokal/kosmetisch (MP: aus den ohnehin lokal laufenden Treffern/Toden).

const MAX_SPLATS := 64          ## Wand-/Bodenspritzer (Ringpuffer)
const MAX_POOLS := 24           ## Lachen (älteste blendet aus)
const MAX_JETS := 6
const MAX_SPRAYS := 12          ## gleichzeitige Partikel-Spritzer
const SCAN_S := 1.0
const WORLD_MASK := 1

var splats: Array = []
var pools: Array = []
var jets: Array[Dictionary] = []
var sprays: Array = []
var stats := {"sprays": 0, "jets": 0, "splats": 0, "pools": 0}   ## Zähler für Tests
var _tex := {}
var _scan := 0.0
var _drip_next := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Events.soldier_died.connect(_on_died)


func reset() -> void:
	splats.clear()
	pools.clear()
	jets.clear()
	sprays.clear()
	_drip_next.clear()


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
	var d := _floor_splat(body_center(s), size, "x_blood05", 2.5, randf_range(6.0, 10.0), true)
	if d != null:
		d.set_meta("owner_soldier", s.get_instance_id())


func _pool_later(id: int, size: float) -> void:
	var s := instance_from_id(id) as Node3D
	if s != null and is_instance_valid(s):
		_pool_for(s, size, 0.0)


## Fleck/Lache auf dem Boden (Raycast nach unten, auf die Bodennormale ausgerichtet). grow > 0 = wächst so lange.
func _floor_splat(pos: Vector3, size: float, tn: String, down := 2.5, grow := 0.0, pool := false) -> Decal:
	var parent := _parent()
	if parent == null:
		return null
	var space := parent.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.DOWN * down, WORLD_MASK)
	var h := space.intersect_ray(q)
	if h.is_empty():
		return null
	return _splat(h.position, h.normal, size, tn, grow, pool or tn == "x_blood05")


func _splat(pos: Vector3, normal: Vector3, size: float, tn: String, grow := 0.0, pool := false) -> Decal:
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
	var ring: Array = pools if pool else splats
	var cap := MAX_POOLS if pool else MAX_SPLATS
	ring.append(d)
	stats["pools" if pool else "splats"] += 1
	while ring.size() > cap:
		var old = ring.pop_front()
		if is_instance_valid(old):
			var tw2: Tween = old.create_tween()
			tw2.tween_property(old, "modulate:a", 0.0, 1.5)
			tw2.tween_callback(old.queue_free)
	return d
