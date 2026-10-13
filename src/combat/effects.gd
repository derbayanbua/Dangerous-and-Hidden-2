extends Node
## Visuelle und akustische Effekte (Autoload "Effects").
## Klänge werden beim Start prozedural synthetisiert (gefiltertes Rauschen
## mit Hüllkurve), es werden keine Fremd-Assets verwendet.

const MAX_DECALS := 80
const MIX_RATE := 22050

var _sounds := {}
var _decals: Array[Node3D] = []
var _hole_tex: Texture2D
var _blood_tex: Texture2D
var _container: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_sounds[&"pistol"] = _synth_shot(0.25, 2400.0, 0.9)
	_sounds[&"smg"] = _synth_shot(0.22, 1800.0, 0.9)
	_sounds[&"rifle"] = _synth_shot(0.6, 1300.0, 1.0)
	_sounds[&"explosion"] = _synth_shot(1.8, 380.0, 1.0)
	_sounds[&"click"] = _synth_click()
	_sounds[&"bolt"] = _synth_click(0.12, 3)
	_sounds[&"step"] = _synth_shot(0.07, 900.0, 0.18)
	_sounds[&"wind"] = _synth_wind(6.0)
	_sounds[&"bird"] = _synth_chirp()
	_sounds[&"alarm"] = _synth_bell(2.0)
	_hole_tex = _radial_texture(Color(0.05, 0.05, 0.05, 0.95), 32)
	_blood_tex = _radial_texture(Color(0.35, 0.02, 0.02, 0.9), 32)


## Die Mission ruft dies auf, damit Effekte mit der Welt entfernt werden.
func set_container(node: Node3D) -> void:
	_container = node
	_decals.clear()


func _parent() -> Node3D:
	if is_instance_valid(_container):
		return _container
	return null


func play(sound: StringName, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 250.0) -> void:
	var parent := _parent()
	if parent == null or not _sounds.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.max_distance = max_distance
	p.unit_size = 8.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func weapon_sound(data: WeaponData) -> StringName:
	if data.slot == WeaponData.Slot.SIDEARM:
		return &"pistol"
	if data.muzzle_velocity < 500.0:
		return &"smg"
	return &"rifle"


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


func impact(pos: Vector3, normal: Vector3) -> void:
	_puff(pos, normal, Color(0.45, 0.4, 0.33, 0.8), 6)
	_decal(pos, normal, _hole_tex, 0.06)


func blood(pos: Vector3, normal: Vector3) -> void:
	_puff(pos, normal, Color(0.4, 0.03, 0.03, 0.9), 5)


func explosion(pos: Vector3, radius: float) -> void:
	var parent := _parent()
	if parent == null:
		return
	play(&"explosion", pos, 6.0, 1.0, 600.0)
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


# --- Atmosphäre --------------------------------------------------------------

var _ambience: AudioStreamPlayer
var _bird_timer: Timer
var _listener_ref: Callable


## Startet Wind (Schleife) und gelegentliche Vogelrufe um den Spieler.
## listener: Callable, das die aktuelle Hörerposition liefert.
func start_ambience(parent: Node, listener: Callable) -> void:
	_listener_ref = listener
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _sounds[&"wind"]
	_ambience.volume_db = -22.0
	parent.add_child(_ambience)
	_ambience.play()
	_bird_timer = Timer.new()
	_bird_timer.wait_time = 6.0
	_bird_timer.timeout.connect(_bird)
	parent.add_child(_bird_timer)
	_bird_timer.start()


func _bird() -> void:
	_bird_timer.wait_time = randf_range(4.0, 14.0)
	if not _listener_ref.is_valid():
		return
	var p: Vector3 = _listener_ref.call()
	var off := Vector3(randf_range(-30, 30), randf_range(4, 10), randf_range(-30, 30))
	play(&"bird", p + off, -14.0, randf_range(0.85, 1.2), 80.0)


## Alarmglocke (läutet mehrfach) am Ort des Alarms.
func alarm_bell(pos: Vector3) -> void:
	var parent := _parent()
	if parent == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[&"alarm"]
	p.max_distance = 500.0
	p.unit_size = 30.0
	p.volume_db = 4.0
	parent.add_child(p)
	p.global_position = pos
	var rings := [0]
	p.finished.connect(func():
		rings[0] += 1
		if rings[0] < 6:
			p.play()
		else:
			p.queue_free())
	p.play()


# --- Synthese --------------------------------------------------------------

## Windrauschen: zweifach tiefpassgefiltertes Rauschen mit langsamer
## Amplitudenmodulation, nahtlos schleifbar.
func _synth_wind(length: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	var y2 := 0.0
	var alpha := 0.02
	for i in n:
		var t := float(i) / n
		y += alpha * (randf_range(-1.0, 1.0) - y)
		y2 += alpha * (y - y2)
		var gust := 0.6 + 0.4 * sin(TAU * t * 2.0) * sin(TAU * t * 3.0)
		# Ränder überblenden, damit die Schleife nicht knackt
		var edge := minf(minf(t * 20.0, (1.0 - t) * 20.0), 1.0)
		data.encode_s16(i * 2, int(clampf(y2 * 9.0 * gust * edge, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav


## Vogelruf: zwei kurze Frequenz-Sweeps.
func _synth_chirp() -> AudioStreamWAV:
	var n := int(0.35 * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var local := fmod(t, 0.17) / 0.17
		var f := lerpf(3200.0, 4600.0, local) + sin(t * 180.0) * 200.0
		phase += TAU * f / MIX_RATE
		var env := sin(PI * local) * (1.0 if t < 0.34 else 0.0)
		data.encode_s16(i * 2, int(sin(phase) * env * 0.35 * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav


## Glocke: obertonreicher, abklingender Schlag.
func _synth_bell(length: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var partials := [[520.0, 1.0], [1040.0, 0.5], [1310.0, 0.35], [1780.0, 0.2], [2600.0, 0.1]]
	for i in n:
		var t := float(i) / MIX_RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-t * (1.5 + p[0] / 1200.0))
		data.encode_s16(i * 2, int(clampf(s * 0.45, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav

func _synth_shot(length: float, cutoff: float, gain: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / MIX_RATE
	var alpha := dt / (rc + dt)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 7.0 / length) * minf(t * 2000.0, 1.0)
		var x := randf_range(-1.0, 1.0)
		y += alpha * (x - y)
		y2 += alpha * (y - y2)
		# tieffrequenter "Knall"-Anteil am Anfang
		var thump := sin(TAU * 70.0 * t) * exp(-t * 30.0)
		var s := clampf((y2 * 3.0 + thump * 0.6) * env * gain, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _synth_click(length := 0.05, clicks := 1) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var local := fmod(t * clicks, length) / length
		var s := randf_range(-1.0, 1.0) * exp(-local * 40.0) * 0.5
		data.encode_s16(i * 2, int(s * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav


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
