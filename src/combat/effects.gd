extends Node
## Visuelle Effekte und Klang-Brücke (Autoload "Effects").
## Klänge kommen ausschließlich aus den Originaldaten (OrigAudio, orig_cache/sounds.json, tools/fmt_sounds.py);
## die früheren synthetisierten Platzhalterklänge sind entfallen. Ohne Originaldaten bleibt es still.

const MAX_DECALS := 80

var _decals: Array[Node3D] = []
var _hole_tex: Texture2D
var _blood_tex: Texture2D
var _container: Node3D
var blood_fx: Node      ## src/combat/blood_fx.gd


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_hole_tex = _radial_texture(Color(0.05, 0.05, 0.05, 0.95), 32)
	_blood_tex = _radial_texture(Color(0.35, 0.02, 0.02, 0.9), 32)
	blood_fx = preload("res://src/combat/blood_fx.gd").new()
	blood_fx.name = "BloodFx"
	add_child(blood_fx)


## Die Mission ruft dies auf, damit Effekte mit der Welt entfernt werden.
func set_container(node: Node3D) -> void:
	_container = node
	_decals.clear()
	if blood_fx:
		blood_fx.reset()


func _parent() -> Node3D:
	if is_instance_valid(_container):
		return _container
	return null


## Kompatible Klang-Schnittstelle (Netzfiguren, ältere Aufrufer):
##   "shot:<waffe>"  Schuss der Waffe (Original-Waffenklang), "step" Schritt (Untergrund), "explosion",
##   "click" leerer Abzug, "bolt" Repetieren. volume_db wirkt zusätzlich zum Tabellenwert.
func play(sound: StringName, pos: Vector3, volume_db := 0.0, _pitch := 1.0, _max_distance := 250.0) -> void:
	var s := String(sound)
	var vol := db_to_linear(volume_db)
	if s.begins_with("shot:"):
		var wd := WeaponDB.get_weapon(StringName(s.substr(5)))
		OrigAudio.play_weapon(wd, "shoot", pos, null, -1, vol)
	elif s == "step":
		OrigAudio.play_step(pos, null, vol)
	elif s == "explosion":
		OrigAudio.play_group(OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_GRENADE, pos, null, vol)
	elif s == "click":
		OrigAudio.play_group(OrigAudio.CAT_WEAPON, OrigAudio.W_EMPTY, pos, null, vol)


## Schlüssel des Schussklangs einer Waffe (für play/Netz)
func weapon_sound(data: WeaponData) -> StringName:
	return StringName("shot:" + String(data.id))


## Mündungsfeuer (Überarbeitung 0.10.1). Größe je Waffenart (`flash_scale`), heller Kern quer zur Laufachse, 3–4
## Flammenzungen längs der Laufachse, kurzer Lichtblitz (35 ms). Leistung: Meshes/Materialien/Texturen werden einmalig
## angelegt und geteilt; höchstens MAX_FLASH_LIGHTS Lichter gleichzeitig, Schüsse > 60 m von der Kamera ohne Licht.
## Schalldämpfer (size 0): kein sichtbares Feuer. parent != null: Feuer hängt lokal an diesem Knoten (FPV-Mündung
## „flash“, folgt der Waffenanimation; Materialien mit z_clip_scale wie die FPV-Waffe), pos/dir werden dann ignoriert.
const MAX_FLASH_LIGHTS := 4
const FLASH_TIME := 0.035
var _flash_lights := 0
var flashes_spawned := 0            ## Statistik für Tests
var last_flash := {}                ## Tests: {"pos", "anchor" (Mündungsknoten), "vm"}
static var _mf_core_mesh: QuadMesh
static var _mf_petal_mesh: QuadMesh
static var _mf_mats := {}


## Größenfaktor des Mündungsfeuers je Waffe (1 = Gewehr) [D] – im Original ein festes Billboard „flash“ je Modell.
static func flash_scale(data: WeaponData) -> float:
	if data == null:
		return 1.0
	if String(data.sound).begins_with("silenced"):
		return 0.0
	if data.action == WeaponData.Action.ROCKET:
		return 1.8
	if data.slot == WeaponData.Slot.SIDEARM:
		return 0.5
	if data.muzzle_velocity < 500.0:
		return 0.7                      # Maschinenpistolen (Pistolenpatrone)
	if (data.action == WeaponData.Action.AUTO or data.can_toggle_auto) and (data.magazine_size >= 40 or data.weight >= 8.0):
		return 1.25                     # Maschinengewehre (Bren, MG 34/42, BAR …)
	return 1.0


func _mf_mat(petal: bool, vm: bool) -> StandardMaterial3D:
	var key := int(petal) * 2 + int(vm)
	if _mf_mats.has(key):
		return _mf_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _flash_petal_texture(64) if petal else _flash_star_texture(128 if Settings.quality >= 3 else 64)
	m.albedo_color = Color(1.0, 0.78, 0.45)
	if not petal:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if vm and "use_z_clip_scale" in m:
		m.set("use_z_clip_scale", true)
		m.set("z_clip_scale", 0.05)
	_mf_mats[key] = m
	return m


func muzzle_flash(pos: Vector3, dir: Vector3, size := 1.0, parent: Node3D = null, light := true) -> void:
	var root := _parent()
	if root == null and parent == null:
		return
	if size <= 0.0:
		return
	if _mf_core_mesh == null:
		_mf_core_mesh = QuadMesh.new()
		_mf_core_mesh.size = Vector2(0.24, 0.24)
		_mf_petal_mesh = QuadMesh.new()
		_mf_petal_mesh.size = Vector2(0.09, 0.30)
		_mf_petal_mesh.center_offset = Vector3(0.0, 0.14, 0.0)   # Zunge wächst von der Mündung nach +Y (lokal)
	var vm := parent != null
	var holder := Node3D.new()
	holder.name = "MuzzleFlash"
	if vm:
		# Knoten „flash“ ist selbst unsichtbar (Original-Billboard ausgeblendet) -> Geschwister mit seiner Lage;
		# Ausrichtung: Schussrichtung dir (FPV-Lauf liegt praktisch auf der Blickachse)
		var pp := parent.get_parent() as Node3D
		if pp == null:
			return
		pp.add_child(holder)
		var vd := dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var vup := Vector3.UP if absf(vd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		holder.global_transform = Transform3D(Basis.looking_at(vd, vup), parent.global_position)
	else:
		root.add_child(holder)
		var d := dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		holder.global_transform = Transform3D(Basis.looking_at(d, up), pos)   # lokal -Z = Schussrichtung
	flashes_spawned += 1
	last_flash = {"pos": holder.global_position, "anchor": parent.global_position if vm else pos, "vm": vm}
	var s := size * randf_range(0.8, 1.2)
	var core := MeshInstance3D.new()
	core.mesh = _mf_core_mesh
	core.material_override = _mf_mat(false, vm)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3.ONE * s
	core.position = Vector3(0, 0, -0.03 * s)
	core.rotation.z = randf() * TAU
	holder.add_child(core)
	if Settings.quality >= 1:
		var n := 3 + randi() % 2
		var a0 := randf() * TAU
		for i in n:
			var p := MeshInstance3D.new()
			p.mesh = _mf_petal_mesh
			p.material_override = _mf_mat(true, vm)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Quad-Ebene enthält die Laufachse: +Y nach -Z kippen, dann um die Laufachse verteilen
			p.basis = Basis(Vector3(0, 0, -1), a0 + TAU * float(i) / float(n)) * Basis(Vector3.RIGHT, -PI * 0.5)
			p.basis = p.basis.scaled(Vector3(1.0, randf_range(0.7, 1.3), 1.0) * s)
			holder.add_child(p)
	if light and _flash_lights < MAX_FLASH_LIGHTS and holder.is_inside_tree():
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		if cam == null or cam.global_position.distance_to(holder.global_position) < 60.0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.72, 0.38)
			l.light_energy = 2.2 * clampf(size, 0.25, 1.6)
			l.omni_range = 2.5 + 2.5 * clampf(size, 0.0, 1.8)
			l.omni_attenuation = 1.6
			l.shadow_enabled = false
			l.light_specular = 0.2
			holder.add_child(l)
			l.position = Vector3(0, 0, -0.1)
			_flash_lights += 1
			l.tree_exiting.connect(func(): _flash_lights = maxi(0, _flash_lights - 1))
	get_tree().create_timer(FLASH_TIME, false).timeout.connect(holder.queue_free)


static var _star_tex := {}
static var _petal_tex: Texture2D


## Flammenzunge: schmaler, nach vorn spitz zulaufender Streifen (Mündung = untere Kante)
static func _flash_petal_texture(res: int) -> Texture2D:
	if _petal_tex != null:
		return _petal_tex
	var img := Image.create(res, res * 2, false, Image.FORMAT_RGBA8)
	for y in res * 2:
		var t := 1.0 - float(y) / float(res * 2 - 1)        # 0 Mündung (unten) … 1 Spitze (oben)
		var w := (1.0 - t) * 0.9 + 0.05
		for x in res:
			var u := absf((float(x) + 0.5) / float(res) * 2.0 - 1.0)
			var a := clampf(1.0 - u / w, 0.0, 1.0) * clampf(1.0 - t, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.75 + 0.25 * (1.0 - t), 0.4 + 0.5 * (1.0 - t), a * a))
	img.generate_mipmaps()
	_petal_tex = ImageTexture.create_from_image(img)
	return _petal_tex


## Mündungsstern: heller Kern mit 5–6 unregelmäßigen Zacken
static func _flash_star_texture(res: int) -> Texture2D:
	if _star_tex.has(res):
		return _star_tex[res]
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var c := float(res) * 0.5
	var spikes := [0.0, 1.1, 2.0, 3.3, 4.2, 5.3]
	for y in res:
		for x in res:
			var p := Vector2(x + 0.5 - c, y + 0.5 - c) / c
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var s := 0.0
			for sa in spikes:
				var da := absf(wrapf(ang - float(sa), -PI, PI))
				s = maxf(s, clampf(1.0 - da * 6.0, 0.0, 1.0) * clampf(1.0 - r, 0.0, 1.0))
			var core := clampf(1.0 - r * 2.4, 0.0, 1.0)
			var a := clampf(core + s * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.9 + 0.1 * core, 0.7 + 0.3 * core, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_star_tex[res] = tex
	return tex


## Einschlag: Staub, Einschussloch und Original-Einschlagklang je Untergrund (hdmaterials.def +0x30)
func impact(pos: Vector3, normal: Vector3) -> void:
	_puff(pos, normal, Color(0.45, 0.4, 0.33, 0.8), 6)
	_decal(pos, normal, _hole_tex, 0.06)
	OrigAudio.play_impact(pos - normal * 0.02)


## Treffer an einer Figur: Blut und Original-Klang „Flash or Dead Body“ (Kat. 4/7)
## dir = Flugrichtung, zone = Trefferzone, victim = Getroffener (Spritzer/Strahl/Decals: src/combat/blood_fx.gd)
func blood(pos: Vector3, normal: Vector3, dir := Vector3.ZERO, zone: StringName = &"", victim: Node = null) -> void:
	OrigAudio.play_group(OrigAudio.CAT_HIT, OrigAudio.HIT_FLESH, pos)
	blood_fx.hit(pos, normal, dir, zone, victim)   # Stufe AUS (Original „BLUTFLECKEN“ nein) = nichts


## Explosion: sound = [Kategorie, Gruppe] der Klangtabelle (Standard Kat. 6/0 „Explosion Grenade“),
## leer = ohne Klang (z. B. wenn das Original-Objekt seinen Zerstörungsklang selbst spielt).
## B-013 (rein optisch, Schaden/Radius bleiben bei den Aufrufern aus items.sav): GPU-Feuerball, Rauchsäule, Trümmer,
## Funken, Druckwelle, Hitzeflimmern, Licht, Kamera-Erschütterung, Brandfleck-Decal (src/combat/explosion_fx.gd).
## kind (optional, z. B. B-011): &"artillery", &"air", &"vehicle", &"water" – nur Darstellung.
func explosion(pos: Vector3, radius: float, sound: Array = [6, 0], kind: StringName = &"") -> void:
	var parent := _parent()
	if parent == null:
		return
	if sound.size() >= 2:
		OrigAudio.play_group(int(sound[0]), int(sound[1]), pos)
	if kind == &"" and sound.size() >= 2 and int(sound[0]) == OrigAudio.CAT_EXPLOSION and int(sound[1]) == OrigAudio.EXP_WATER:
		kind = &"water"
	last_explosion = ExplosionFx.spawn(parent, pos, radius, Settings.quality, kind)
	explosion_count += 1
	Ragdoll.explosion(get_tree(), pos, radius)     # B-016: Leichen/Gefallene schleudern (auch auf Clients)
	var big := kind == &"artillery" or kind == &"air"
	shake(pos, clampf(radius / 5.0, 0.4, 2.0) * (1.6 if big else 1.0))
	if kind != &"water":
		var res: int = 256 if Settings.quality >= 3 else 128
		_decal(pos + Vector3.UP * 0.2, Vector3.UP, ExplosionFx.scorch_texture(res), radius * (0.55 if Settings.quality >= 1 else 0.4))


const ExplosionFx := preload("res://src/combat/explosion_fx.gd")
var last_explosion := {}       ## {"node", "parts", "lifetime"} der letzten Explosion (Tests, B-011)
var explosion_count := 0
var _shake := 0.0
var _shake_cam: Camera3D


## Kamera-Erschütterung: Stärke fällt mit der Entfernung zur aktiven Kamera (bis ≈ 60 m), klingt in ≈ 0,6 s ab.
## Wirkt über h_offset/v_offset (CameraRig nutzt sie nicht) → keine Änderung an Zielrichtung/Ballistik.
func shake(pos: Vector3, strength: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(pos)
	var s := strength * clampf(1.0 - d / 60.0, 0.0, 1.0)
	if s <= 0.01:
		return
	if _shake_cam != cam and is_instance_valid(_shake_cam):
		_shake_cam.h_offset = 0.0
		_shake_cam.v_offset = 0.0
	_shake_cam = cam
	_shake = maxf(_shake, s)


func shake_amount() -> float:
	return _shake


func _process(dt: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - dt * 1.8, 0.0)
	if not is_instance_valid(_shake_cam):
		_shake = 0.0
		return
	var a := _shake * _shake * 0.04
	_shake_cam.h_offset = randf_range(-a, a)
	_shake_cam.v_offset = randf_range(-a, a)
	if _shake <= 0.0:
		_shake_cam.h_offset = 0.0
		_shake_cam.v_offset = 0.0


func _puff(pos: Vector3, normal: Vector3, color: Color, amount: int) -> void:
	var parent := _parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if Settings.quality >= 1:
		# B-013: weiche, wachsende Staubwolke (Billboard mit Rauschtextur) statt Würfelchen
		var qm := QuadMesh.new()
		qm.size = Vector2(0.28, 0.28)
		p.mesh = qm
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = ExplosionFx.puff_texture(128 if Settings.quality >= 3 else 64)
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		p.lifetime = 1.1
		p.damping_min = 2.0
		p.damping_max = 4.0
		p.gravity = Vector3(0, -0.4, 0)
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = sc
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		p.color_ramp = g
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 0.05)
		p.mesh = bm
	p.material_override = mat
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _decal(pos: Vector3, normal: Vector3, tex: Texture2D, size: float) -> void:
	if not Settings.decals:
		return   # Original-Option „FUSSSPUREN, DEKORATIONEN“
	var parent := _parent()
	if parent == null:
		return
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(size, 0.1, size)
	d.cull_mask = 1
	parent.add_child(d)
	d.global_position = pos
	# Decal projiziert entlang -Y: Y-Achse an der Normalen ausrichten.
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	d.global_basis = Basis(x, up, x.cross(up)).orthonormalized()
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		var old: Node3D = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# --- Atmosphäre (Übungseinsätze; Originalmissionen haben ihre Klangquellen aus sounds.bin) -----------

var _ambience: AudioStreamPlayer
var ambience_file := ""


## Umgebungsschleife einer Übungsmission (Original-Umgebungsaufnahme, Zuordnung je Einsatz durch die Mission).
## Leer = keine (Originalmissionen).
func start_ambience(parent: Node, file: String) -> void:
	ambience_file = file
	if file == "":
		return
	var st := OrigAudio.stream(file, true)
	if st == null:
		return
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = st
	_ambience.bus = &"SFX"
	_ambience.volume_db = -10.0
	parent.add_child(_ambience)
	_ambience.play()


## Alarm am Ort (Übungseinsätze): Original-Alarmschiene „Anim09 Alarm kolejnice“ (Kat. 11/29), mehrfach.
func alarm_bell(pos: Vector3) -> void:
	if _parent() == null:
		return
	for i in 4:
		get_tree().create_timer(i * 2.5, false).timeout.connect(func():
			OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_ALARM, pos))


func _radial_texture(color: Color, size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 0.6) * color.a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)
