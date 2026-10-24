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


func muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var parent := _parent()
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0
	light.omni_range = 4.0
	parent.add_child(light)
	light.global_position = pos + dir * 0.1
	var mesh := MeshInstance3D.new()
	var q := SphereMesh.new()
	q.radius = 0.06
	q.height = 0.2
	mesh.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.add_child(mesh)
	get_tree().create_timer(0.045, false).timeout.connect(light.queue_free)


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
func explosion(pos: Vector3, radius: float, sound: Array = [6, 0]) -> void:
	var parent := _parent()
	if parent == null:
		return
	if sound.size() >= 2:
		OrigAudio.play_group(int(sound[0]), int(sound[1]), pos)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 12.0
	light.omni_range = radius * 3.0
	parent.add_child(light)
	light.global_position = pos + Vector3.UP
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	tw.tween_callback(light.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 60
	p.lifetime = 2.5
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.18, 0.16)
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.3))
	grad.add_point(0.15, Color(0.3, 0.27, 0.24))
	grad.set_color(grad.get_point_count() - 1, Color(0.15, 0.15, 0.15))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	_decal(pos + Vector3.UP * 0.2, Vector3.UP, _hole_tex, radius * 0.4)


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
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.05)
	p.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
