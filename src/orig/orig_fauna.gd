class_name OrigFauna
extends Node3D
## B-053 Kosmetische Originalakteure: Typ 27 Uhr, Typ 29 Vogelschwarm, Typ 32 Fische (interactive.json
## "clocks"/"birds"/"fish"). Typ 36 Luftangriff ist eigenständig in src/orig/orig_air_attack.gd.
## Kennzeichnung: [B] in hd2.exe belegt, [P] plausibel/teilbelegt, [E] eigene Festlegung.
##
## Uhr [B] (Update 0x5B8610): Laufzeit +0xC0 (s seit Erzeugung) und Sekundentakt +0xC4. Nur wenn der Frame „sec“
##   existiert und der Takt 1 s übersteigt, werden alle Zeiger gesetzt (Sprung 1×/s, Rest bleibt im Takt):
##   Drehung um die lokale z-Achse auf die Ausgangsdrehung, Minuten −t·0,0017453 rad, Stunden −t·0,00014544 rad.
##   Sekunden −t·2π/60 [P] (Konstante liegt im FPU-Pfad, Muster wie min/hour). Uhrzeit = Missionslaufzeit, keine
##   Systemzeit [B]. Spielstand: Laufzeit.
## Vogelschwarm [B] (Tick 0x5BB4D0, Auffliegen 0x5BB140, Einzelvogel 0x47A2F0): Felder +0xA0 Modus, +0xA8 Radius,
##   +0xAC Auslösedistanz, Anzahl, Modellname. Prüfung alle 1000 ms: Mensch oder Kamera näher als die Auslösedistanz
##   → Auffliegen (einmalig, +0xBC). Vogel: Geschwindigkeit 5 + Zufall 0–2 m/s, Richtung = normiert(Vorwärtsachse
##   des Vogels + (Zufall 0–0,5; 1; Zufall 0–0,5)), Taumelrate π/(Zufall 1–100).
##   Modus 2: Vögel sitzen ab Start im Quadratgitter √n über 2·Radius [P]; Modus 1: Vögel entstehen erst beim
##   Auffliegen im Radius [P]; Modus 0: vorhandene Szenenobjekte mit dem Modellnamen im Radius werden übernommen [P].
##   Auslöser [B]: Spielerplätze und Menschen mit Seite +0x19C == 1 (Spielertrupp), dazu die Kamera.
##   Schüsse in Auslösedistanz scheuchen ebenfalls auf [P]. Beim Auffliegen KI-Lärmmeldung Art 0xB am Schwarmort
##   (nur Einzelspieler, Flag „> 3 Vögel“) [B], hier Events.emit_noise(kind "birds", 30 m [E]). Klang: Aufruf
##   0x475530 ohne belegte Gruppe → IngameSounds Kat. 11 „Bird/Birds Fly Away“ (≤ 3 / > 3 Vögel) [E].
##   Wegflug: nach 25 s bzw. 250 m ausgeblendet [E], Flügelschlag [E].
## Fische [B] (Tick 0x5DBEC0, Aktivprüfung 0x5DCA60): Felder +0xBC Höchstgeschwindigkeit, +0xC0 Radius, Anzahl.
##   Aktiv (sichtbar, gerechnet) nur, wenn die Kamera näher als Radius + 15 m ist. Zustände: 0 beschleunigen
##   (+0,007 m/s je ms bis Höchstgeschwindigkeit, Schwarm zieht sich zusammen: xz×1,111, y×0,9), 1 bremsen
##   (exponentiell auf 1/10), 2 Pause 3–5 s, dann neue Richtung (Gieren ±135° [P], Nicken ±27° [B]) und Schwarm
##   lockert auf (xz×0,9, y×1,111). Vertikalanteil der Richtung klingt mit 1/s ab. Kollision im Original per
##   Kugelstrahl mit dem Radius → hier: Strahl 1 m voraus gegen die Welt (Ebene 1), Spiegelung an der Normale,
##   zusätzlich bleibt die Schwarmmitte in der Kugel um den Startpunkt [E]. Darstellung als MultiMesh (Leistung) [E]; Grafikstufe 0 halbiert die Fischzahl [E].

const CLOCK_MIN_RATE := 0.0017453294      ## [B] rad/s
const CLOCK_HOUR_RATE := 0.00014544411    ## [B] rad/s
const CLOCK_SEC_RATE := TAU / 60.0        ## [P]
const FOWL_CHECK_S := 1.0                 ## [B] 1000 ms
const FOWL_FADE_S := 25.0                 ## [E]
const FOWL_FADE_DIST := 250.0             ## [E]
const FISH_CAM_MARGIN := 15.0             ## [B]
const FISH_ACCEL := 7.0                   ## [B] 0,007 je ms → m/s²
const FISH_MODEL := "ryba"
const FOWL_SOUND_CAT := 11                ## IngameSounds.def „Bird(s) Fly Away“ [E Zuordnung]
const FOWL_NOISE_RADIUS := 30.0           ## [E] Lärmradius (Lautstärke 0,5)

var mission: Node
var runtime: Node
var orig: OrigLevel
var clocks: Array = []
var fowls: Array = []
var fishes: Array = []
var stats := {"clocks": 0, "clock_hands": 0, "fowls": 0, "birds": 0, "fish_schools": 0, "fish": 0, "missing": []}
var cam_override = null   ## Tests: Vector3 statt Kameraposition


func setup(m: Node, rt: Node, o: OrigLevel) -> void:
	mission = m
	runtime = rt
	orig = o
	name = "OrigFauna"
	var d = LsRuntime._read_json(o.mission_dir + "/interactive.json")
	if typeof(d) != TYPE_DICTIONARY:
		return
	for e in d.get("clocks", []):
		_add_clock(e)
	for e in d.get("birds", []):
		_add_fowl(e)
	for e in d.get("fish", []):
		_add_fish(e)
	if Events.has_signal("noise_emitted"):
		Events.noise_emitted.connect(_on_noise)


func camera_pos() -> Vector3:
	if cam_override is Vector3:
		return cam_override
	var c := get_viewport().get_camera_3d() if is_inside_tree() else null
	return c.global_position if c else Vector3.INF


func _xform(e: Dictionary) -> Transform3D:
	if mission and mission.has_method("actor_xform"):
		var a := {"pos": e.get("local", {}).get("pos", [0, 0, 0]), "rot": e.get("local", {}).get("rot", [0, 0, 0, 1]),
			"parent": e.get("parent", "")}
		return mission.actor_xform(a)
	return OrigLevel.xform(e.get("world", {}))


func _actor_node(nm: String) -> Node3D:
	if runtime == null:
		return null
	var acts: Dictionary = runtime.get("actors") if runtime.get("actors") is Dictionary else {}
	if acts.has(nm) and acts[nm] is Node3D:
		return acts[nm]
	for k in acts:
		if String(k).to_lower() == nm.to_lower() and acts[k] is Node3D:
			return acts[k]
	return null


# --- Typ 27 Uhr -----------------------------------------------------------------------------------------------
func _add_clock(e: Dictionary) -> void:
	var nm := String(e.get("name", ""))
	var n := _actor_node(nm)
	if n == null:
		stats.missing.append(nm)
		return
	var c := OrigClock.new()
	c.setup(nm, n)
	clocks.append(c)
	stats.clocks += 1
	stats.clock_hands += c.hands.size()


class OrigClock:
	extends RefCounted
	var name := ""
	var root: Node3D
	var hands := {}          ## "hour"/"min"/"sec" -> [Node3D, Basis Ausgangsdrehung]
	var elapsed := 0.0       ## +0xC0
	var tick := 0.0          ## +0xC4
	var jumps := 0

	func setup(nm: String, n: Node3D) -> void:
		name = nm
		root = n
		for h in ["hour", "min", "sec"]:
			var f := n.find_child(h, true, false) as Node3D
			if f:
				hands[h] = [f, f.basis]

	func step(dt: float) -> void:
		elapsed += dt
		tick += dt
		if not hands.has("sec") or tick <= 1.0:
			return
		apply()
		tick -= floorf(tick)
		jumps += 1

	func angle(h: String) -> float:
		match h:
			"min": return -elapsed * CLOCK_MIN_RATE
			"hour": return -elapsed * CLOCK_HOUR_RATE
			_: return -elapsed * CLOCK_SEC_RATE

	func apply() -> void:
		for h in hands:
			var f: Node3D = hands[h][0]
			if is_instance_valid(f):
				f.basis = (hands[h][1] as Basis) * Basis(Vector3(0, 0, 1), angle(h))


# --- Typ 29 Vogelschwarm --------------------------------------------------------------------------------------
func _add_fowl(e: Dictionary) -> void:
	var p: Dictionary = e.get("params", {})
	var f := OrigFowl.new()
	f.name = String(e.get("name", "fowl")).validate_node_name()
	f.mode = int(p.get("ua0_?", 1))
	f.radius = float(p.get("fa8_?", 2.0))
	f.trigger_dist = float(p.get("fac_?", 5.0))
	f.count = int(p.get("count_?", 5))
	if Settings.quality <= 0:
		f.count = maxi(1, f.count / 2)    # [E]
	var model := String(p.get("name_?", "ptacekletacek")).to_lower()
	add_child(f)
	f.global_transform = _xform(e)
	f.fauna = self
	f.template = orig.model_instance(model) if orig else null
	if f.template == null:
		stats.missing.append(model)
	f.build(orig, model)
	fowls.append(f)
	stats.fowls += 1
	stats.birds += f.birds.size() if f.mode != 1 else f.count


class OrigFowl:
	extends Node3D
	var fauna
	var mode := 1
	var radius := 2.0
	var trigger_dist := 5.0
	var count := 5
	var template: Node3D
	var flown := false        ## +0xBC
	var noise_sent := false
	var sound_played := false
	var birds: Array = []     ## [Node3D, Vector3 Geschwindigkeit, Taumelrate, Phase]
	var _check := FOWL_CHECK_S
	var _t := 0.0

	func build(o: OrigLevel, model: String) -> void:
		if mode == 2 and template:
			var side := maxi(1, ceili(sqrt(float(count))))
			var step := 2.0 * radius / float(side)
			for i in count:
				var x := -radius + step * (0.5 + float(i % side))
				var z := -radius + step * (0.5 + float(i / side))
				_new_bird(Vector3(x, 0, z), randf() * TAU)
		elif mode == 0 and o:
			for k in o.nodes:
				var n = o.nodes[k]
				if n is Node3D and String(k).to_lower().begins_with(model.substr(0, 4)) \
						and (n as Node3D).global_position.distance_to(global_position) <= radius:
					birds.append([n, Vector3.ZERO, 0.0, randf() * TAU])

	func _new_bird(local_pos: Vector3, yaw: float) -> Node3D:
		var b := template.duplicate() as Node3D
		add_child(b)
		b.position = local_pos
		b.rotation.y = yaw
		birds.append([b, Vector3.ZERO, 0.0, randf() * TAU])
		return b

	func fly_up() -> void:
		if flown:
			return
		flown = true
		_t = 0.0
		var many := count > 3   # [B] 0x5BB140: Flag „mehr als 3 Vögel“ in der Lärmmeldung
		# KI-Lärmmeldung Art 0xB [B] (nur Einzelspieler, 0x982100 & 2) am Schwarmort; Radius [E].
		if not Net.is_online:
			Events.emit_noise(global_position, FOWL_NOISE_RADIUS, self, -1, &"birds")
			noise_sent = true
		# Klang [E]: IngameSounds.def Kategorie 11 „Bird Fly Away“ (0) / „Birds Fly Away“ (1); Aufruf 0x475530 ohne
		# belegte Gruppennummer.
		if OrigAudio and OrigAudio.has_method("play_group"):
			sound_played = OrigAudio.play_group(FOWL_SOUND_CAT, 1 if many else 0, global_position) != null
		if mode == 1 and template:
			for i in count:
				var a := randf() * TAU
				var r := randf() * radius
				_new_bird(Vector3(cos(a) * r, 0, sin(a) * r), randf() * TAU)
		for b in birds:
			var n: Node3D = b[0]
			if not is_instance_valid(n):
				continue
			var fwd := -n.global_transform.basis.z.normalized()
			var dir := (fwd + Vector3(randf() * 0.5, 1.0, randf() * 0.5)).normalized()
			b[1] = dir * (5.0 + randf() * 2.0)
			b[2] = PI / float(randi() % 100 + 1)

	func near(p: Vector3) -> bool:
		return p.distance_squared_to(global_position) < trigger_dist * trigger_dist

	func _process(dt: float) -> void:
		if not flown:
			_check -= dt
			if _check > 0.0:
				return
			while _check <= 0.0:
				_check += FOWL_CHECK_S
			if fauna and near(fauna.camera_pos()):
				fly_up()
				return
			# [B] 0x5BB4D0: Spielerplätze + Menschen mit Typ 3 und Seite +0x19C == 1 (Spielertrupp); Gegner,
			# Neutrale und verbündete NPCs (Seite 2/3/4) scheuchen nicht auf.
			for s in get_tree().get_nodes_in_group("soldiers"):
				if s is Node3D and s.get("alive") != false and WeaponDB.orig_side(s) == 1 \
						and near((s as Node3D).global_position):
					fly_up()
					return
			return
		_t += dt
		var gone := _t > FOWL_FADE_S
		for b in birds:
			var n: Node3D = b[0]
			if not is_instance_valid(n) or not n.visible:
				continue
			var v: Vector3 = b[1]
			v = v.rotated(Vector3.UP, float(b[2]) * dt * sin(_t * 1.3 + float(b[3])))
			b[1] = v
			n.global_position += v * dt
			if v.length_squared() > 0.01:
				n.look_at(n.global_position + v, Vector3.UP)
			_flap(n, _t * 12.0 + float(b[3]))
			if gone or n.global_position.distance_to(global_position) > FOWL_FADE_DIST:
				n.visible = false

	func _flap(n: Node3D, ph: float) -> void:
		var a := sin(ph) * 0.7
		var l := n.find_child("Object02", true, false) as Node3D
		var r := n.find_child("Object04", true, false) as Node3D
		if l:
			l.rotation.z = a
		if r:
			r.rotation.z = -a


func _on_noise(pos: Vector3, _radius: float, _src: Node, _team: int, kind: StringName) -> void:
	if not String(kind).to_lower().contains("shot") and String(kind) != "gun":
		return
	for f in fowls:
		if is_instance_valid(f) and f.near(pos):
			f.fly_up()


# --- Typ 32 Fische --------------------------------------------------------------------------------------------
func _add_fish(e: Dictionary) -> void:
	var p: Dictionary = e.get("params", {})
	var s := OrigFish.new()
	s.name = String(e.get("name", "fish")).validate_node_name()
	s.max_speed = float(p.get("f_bc_?", 1.0))
	s.radius = float(p.get("f_c0_?", 8.0))
	s.count = int(p.get("u_c4_?", 50))
	if Settings.quality <= 0:
		s.count = maxi(1, s.count / 2)    # [E]
	add_child(s)
	s.global_transform = _xform(e)
	s.fauna = self
	var tpl: Node3D = orig.model_instance(FISH_MODEL) if orig else null
	if tpl == null:
		stats.missing.append(FISH_MODEL)
	s.build(tpl)
	fishes.append(s)
	stats.fish_schools += 1
	stats.fish += s.count


class OrigFish:
	extends Node3D
	var fauna
	var max_speed := 1.0     ## +0xBC
	var radius := 8.0        ## +0xC0
	var count := 50
	var state := 0           ## +0xB0
	var speed := 0.0         ## +0xCC
	var pause := 0.0         ## +0xB4
	var dir := Vector3.FORWARD
	var center := Vector3.ZERO   ## Schwarmmitte (lokal)
	var offsets: Array = []
	var active := false
	var mm: MultiMeshInstance3D
	var steps := 0
	var world_bounces := 0
	const WORLD_PROBE := 1.0   ## [E] m Vorlauf des Kollisionsstrahls

	func build(tpl: Node3D) -> void:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		for i in count:
			offsets.append(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * minf(radius * 0.25, 2.0))
		var mesh: Mesh = null
		if tpl:
			for c in tpl.find_children("*", "MeshInstance3D", true, false):
				mesh = (c as MeshInstance3D).mesh
				break
			tpl.free()
		if mesh == null:
			return
		mm = MultiMeshInstance3D.new()
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.mesh = mesh
		m.instance_count = count
		mm.multimesh = m
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mm.visible = false
		add_child(mm)

	func _scale_spread(xz: float, y: float) -> void:
		for i in offsets.size():
			var o: Vector3 = offsets[i]
			offsets[i] = Vector3(o.x * xz, o.y * y, o.z * xz)

	func set_active(on: bool) -> void:
		active = on
		if mm:
			mm.visible = on

	func _process(dt: float) -> void:
		var cam: Vector3 = fauna.camera_pos() if fauna else Vector3.INF
		var lim := radius + FISH_CAM_MARGIN
		var on := cam.distance_squared_to(global_position) <= lim * lim
		if on != active:
			set_active(on)
		if not on:
			return
		steps += 1
		var ms := dt * 1000.0
		match state:
			0:
				speed += ms * 0.007   # [B] +0,007 je ms
				if speed > max_speed:
					speed = max_speed
					state = 1
					_scale_spread(1.1111112, 0.9)
			1:
				var lo := max_speed * 0.1
				speed -= ((speed - lo) + 0.1) * ms * 0.001
				if speed < lo:
					speed = lo
					state = 2
					pause = (3000 + randi() % 2000) * 0.001
			2:
				pause -= dt
				if pause < 0.0:
					state = 0
					var yaw := randf_range(-0.75 * PI, 0.75 * PI)
					var pitch := randf() * 0.94247778 - 0.47123894
					dir = dir.rotated(Vector3.UP, yaw)
					var side := dir.cross(Vector3.UP)
					if side.length_squared() > 1e-6:
						dir = dir.rotated(side.normalized(), pitch)
					dir = dir.normalized()
					_scale_spread(0.9, 1.1111112)
		# Vertikalanteil klingt mit 1/s ab [B]
		dir.y = move_toward(dir.y, 0.0, dt)
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
		var nc := center + dir * speed * dt
		var hit := _world_hit(center, nc)
		if not hit.is_empty():
			# Weltkollision [E] (Original: Kugelstrahl mit dem Radius): an der Flächennormale spiegeln
			var nrm: Vector3 = global_transform.basis.inverse() * (hit["normal"] as Vector3)
			if nrm.length_squared() > 1e-6:
				dir = dir.bounce(nrm.normalized()).normalized()
			world_bounces += 1
			nc = center
		elif nc.length() > radius:
			dir = dir.bounce(nc.normalized()).normalized()   # [E]
			nc = center
		center = nc
		_draw()

	## Strahl von der Schwarmmitte in Bewegungsrichtung, 1 m Vorlauf, nur Welt (Ebene 1) [E].
	func _world_hit(from_l: Vector3, to_l: Vector3) -> Dictionary:
		if not is_inside_tree() or get_world_3d() == null:
			return {}
		var a := to_global(from_l)
		var mv := to_global(to_l) - a
		var b := a + (mv.normalized() if mv.length_squared() > 1e-8 else global_transform.basis * dir) * WORLD_PROBE
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		return get_world_3d().direct_space_state.intersect_ray(q)

	func _draw() -> void:
		if mm == null or mm.multimesh == null:
			return
		var b := Basis.looking_at(dir, Vector3.UP) if absf(dir.dot(Vector3.UP)) < 0.99 else Basis()
		for i in offsets.size():
			mm.multimesh.set_instance_transform(i, Transform3D(b, center + offsets[i]))


# --- Ablauf / Spielstand --------------------------------------------------------------------------------------
func _process(dt: float) -> void:
	for c in clocks:
		c.step(dt)


func save_state() -> Dictionary:
	var cl := {}
	for c in clocks:
		cl[c.name] = [c.elapsed, c.tick]
	var fl := []
	for f in fowls:
		if is_instance_valid(f) and f.flown:
			fl.append(String(f.name))
	return {"v": 1, "clocks": cl, "fowls_flown": fl}


func load_state(d) -> void:
	if not (d is Dictionary):
		return
	var cl: Dictionary = d.get("clocks", {})
	for c in clocks:
		if cl.has(c.name) and cl[c.name] is Array and (cl[c.name] as Array).size() >= 2:
			c.elapsed = float(cl[c.name][0])
			c.tick = float(cl[c.name][1])
			if c.hands.has("sec"):
				c.apply()
	var fl: Array = d.get("fowls_flown", [])
	for f in fowls:
		if is_instance_valid(f) and fl.has(String(f.name)):
			f.flown = true
			for b in f.birds:
				if is_instance_valid(b[0]):
					(b[0] as Node3D).visible = false
