class_name OrigAirAttack
extends Node3D
## Angreifendes Flugzeug (Original-Akteurtyp 36 „AirAttack“, AFRICA1 Macchi „macchi_nalet“, AFRICA2 Bf 109 „mes03/mes04“).
## Nachbau von hd2.exe (re_work/ju88/air_all.c, Klasse 36, Konstruktor 0x5E3C90):
##   Bewegung 0x5E5960, Zielwahl AirAttack_SetTarget → 0x5E7570, MG-Feuer 0x5E81C0, Einschlag 0x5E3A80, Treffer 0x5E3B80.
## Belegte Werte [O] (Konstanten aus hd2.exe gelesen):
##   Geschwindigkeit 100 m/s; Mindestabstand zum Boden/Höchsthöhe je Phase 30/100 (frei), 35/100 (Anflug), 25/40 (Überflug);
##   Phasen: 0 Abflug bis 400 m waagrechter Abstand → 1 Anflug (Feuer, wenn das Ziel in Sicht und < 200 m) → bei < 50 m
##   2 Überflug → ab 80 m wieder 0. Ohne Ziel (AirAttack_SetTarget(x, false)) Geradeausflug.
##   MG: alle 25 ms ein Einschlagpunkt = Ziel + Flugrichtung·(Zufall 0–50 + Abstand − 125)·0,15 + seitlich (Zufall 0–6 − 3);
##   Einschlag prüft per Strahl, ob ein Mensch getroffen wird (Schaden = Parameter f15c). Höhenregelung: Steigen bei
##   Bodennähe, sonst Nicken gegen 0 (0,0015/ms ab-, 0,0003/ms aufwärts), im Anflug zur Zielhöhe 0,001/ms.
##   Klänge motor1–4.wav (Schleife, Tonhöhe 1,25 − Zufall 0,5), MG kul_d1–5.wav, Einschläge sand01–05.wav.
##   Gesundheit = Parameter f158 (Bf 109 800, Macchi 600), bei 0 → Rauch (Partikel 16), Skript-OnDeath, fliegt weiter.
## Annahmen [E]: Wenderate 0,9 rad/s, Querlage beim Kurven, Laufzeit der Geschosse = Abstand / 800 m/s,
##   Skalierung Gesundheit/Schaden wie bei Menschen (OrigMission.HP_SCALE = 0,5).

const SPEED := 100.0
const TURN_RATE := 0.9          ## [E] rad/s
const FIRE_INTERVAL := 0.025    ## [O] 25 ms
const FIRE_RANGE := 200.0       ## [O]
const BULLET_SPEED := 800.0     ## [E]

var mission: Mission
var runtime: Node
var visual: Node3D
var state := 0
var free_flight := true         ## 0x135: kein Ziel → geradeaus
var target: Node3D
var min_clear := 30.0
var max_height := 100.0
var dir := Vector3.FORWARD
var health := 400.0
var damage := 35.0
var dead := false
var _fire_t := 0.0
var _impacts: Array = []        ## [Zeit, Startpunkt, Einschlagpunkt]
var _engine: AudioStreamPlayer3D
var _mg: AudioStreamPlayer3D
var _smoke: Node3D
var _bank := 0.0
var _visible_target := false
var _hit_area: Area3D
var stats := {"shots": 0, "impacts": 0, "human_hits": 0, "sight_ok": 0, "sight_fail": 0}


func setup(m: Mission, rt: Node, vis: Node3D, params: Dictionary, hp_scale: float) -> void:
	mission = m
	runtime = rt
	visual = vis
	if vis:
		add_child(vis)
		# Modell-Kollision (Ebene 1) würde Sichtstrahlen/Einschläge vom Flugzeug aus blockieren – Treffer über _hit_area
		for n in vis.find_children("*", "CollisionObject3D", true, false):
			(n as CollisionObject3D).collision_layer = 0
			(n as CollisionObject3D).collision_mask = 0
	health = float(params.get("f158_?", 800.0)) * hp_scale
	damage = float(params.get("f15c_?", 70.0)) * hp_scale
	set_meta("actor_state", 1)


var _dir_init := false


## Startrichtung = Nase des Originalmodells (nach der Z-Spiegelung −Z, wie bei Figuren/Fahrzeugen); erst im ersten
## Physikschritt, weil die Lage nach add_child gesetzt wird
func _init_dir() -> void:
	_dir_init = true
	dir = -global_basis.z
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()


func _ready() -> void:
	# Trefferfläche für Beschuss (Ballistics: Area ohne Hitbox → on_bullet_hit)
	_hit_area = Area3D.new()
	_hit_area.collision_layer = Hitbox.LAYER
	_hit_area.collision_mask = 0
	_hit_area.monitoring = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _visual_size()
	cs.shape = box
	_hit_area.add_child(cs)
	add_child(_hit_area)
	_hit_area.set_meta("hit_proxy", self)


func _visual_size() -> Vector3:
	var aabb := AABB()
	var first := true
	if visual:
		for n in visual.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var a := mi.get_aabb()
			a = (visual.global_transform.affine_inverse() * mi.global_transform) * a if mi.is_inside_tree() else a
			aabb = a if first else aabb.merge(a)
			first = false
	if first or aabb.size.length() < 1.0:
		return Vector3(10, 2.5, 9)
	return aabb.size


## AirAttack_SetTarget(frame, an) – hd2.exe 0x5E7570
func set_air_target(t: Node3D, on: bool) -> void:
	min_clear = 30.0
	max_height = 100.0
	if on and (t != null or state == 3):
		free_flight = false
		state = 2
		min_clear = 35.0
		max_height = 100.0
		target = t
		return
	free_flight = true


func on_bullet_hit(dmg: float, _shooter: Node) -> void:
	if dead:
		return
	health -= dmg
	if health > 0.0:
		return
	dead = true
	set_meta("actor_state", 0)
	# hd2.exe 0x5E3B80: Zustand 3 → sofort wieder Überflug ohne Ziel, Rauchfahne (Partikel 16) am Flugzeug
	state = 2
	target = null
	free_flight = false
	if runtime and runtime.has_method("_particles"):
		_smoke = runtime._particles(16, global_position)
	if runtime and runtime.has_method("notify"):
		runtime.notify(self, "ONDEATH")


func _physics_process(delta: float) -> void:
	if not _dir_init:
		_init_dir()
		# später angehängte Körper (Modell-/Skript-Trefferflächen) blockieren sonst Sicht und Einschläge vom Flugzeug aus
		for n in find_children("*", "CollisionObject3D", true, false):
			if n != _hit_area:
				(n as CollisionObject3D).collision_layer = 0
				(n as CollisionObject3D).collision_mask = 0
	if not is_visible_in_tree():
		if _engine:
			_engine.stop()
		return
	if _engine == null or not _engine.playing:
		_start_engine()
	_visible_target = false
	var tpos := global_position
	var has_t := is_instance_valid(target) and not free_flight
	if has_t:
		tpos = target.global_position + Vector3.UP * 1.0
	var to := tpos - global_position
	var d2 := to.x * to.x + to.z * to.z
	if not free_flight:
		match state:
			0:
				if d2 > 160000.0:
					state = 1
					min_clear = 35.0
					max_height = 100.0
			1:
				if d2 < 2500.0:
					state = 2
					min_clear = 25.0
					max_height = 40.0
				if has_t:
					_visible_target = _sees(target)
					stats["sight_ok" if _visible_target else "sight_fail"] += 1
					var want := Vector3(to.x, 0, to.z).normalized()
					_turn_towards(want, delta)
			2:
				if d2 > 6400.0:
					state = 0
	_height_control(delta, to)
	dir = dir.normalized()
	global_position += dir * SPEED * delta
	_orient(delta)
	if state == 1 and not free_flight and has_t and _visible_target and sqrt(to.length_squared()) < FIRE_RANGE and not dead:
		_fire_t -= delta
		while _fire_t < 0.0:
			_fire_t += FIRE_INTERVAL
			_shoot(tpos, to)
		if _mg == null or not _mg.playing:
			_mg = OrigAudio.play_file("kul_d%d.wav" % randi_range(1, 5), global_position, 20.0, 400.0, 1.0, self)
	_process_impacts(delta)
	if is_instance_valid(_smoke):
		_smoke.global_position = global_position


func _sees(t: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	# Original 0x5E5960: sichtbar, wenn der Strahl das Ziel trifft – das Fahrzeug, in dem das Ziel sitzt, zählt als Ziel
	var ex: Array[RID] = []
	var veh = t.get("vehicle") if t is Soldier else null
	if veh is CollisionObject3D and is_instance_valid(veh):
		ex.append((veh as CollisionObject3D).get_rid())
	elif t is CollisionObject3D:
		ex.append((t as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(global_position, t.global_position + Vector3.UP * 1.2, 1, ex)
	var h := space.intersect_ray(q)
	if not h.is_empty() and int(stats["sight_fail"]) < 3:
		print("AIRATTACK %s: Sicht zum Ziel verdeckt durch %s bei %s" % [name, str(h.collider.get_path()) if h.collider else "?", h.position])
	return h.is_empty()


func _turn_towards(want: Vector3, delta: float) -> void:
	var h := Vector3(dir.x, 0, dir.z)
	if h.length() < 0.01 or want.length() < 0.01:
		return
	h = h.normalized()
	var ang := h.signed_angle_to(want, Vector3.UP)
	var step := clampf(ang, -TURN_RATE * delta, TURN_RATE * delta)
	_bank = lerpf(_bank, clampf(-ang, -0.8, 0.8), delta * 2.0)
	var nh := h.rotated(Vector3.UP, step)
	var y := dir.y
	dir = Vector3(nh.x * sqrt(maxf(1.0 - y * y, 0.0)), y, nh.z * sqrt(maxf(1.0 - y * y, 0.0)))


func _height_control(delta: float, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1000.0, global_position + Vector3.DOWN * 10000.0, 1)
	var g := space.intersect_ray(down)
	var ms := delta * 1000.0
	var climb := false
	if not g.is_empty():
		var h: float = global_position.y - (g.position as Vector3).y
		if h < min_clear and (h <= max_height or _visible_target):
			climb = true
	var fwd := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * min_clear, 1)
	if not space.intersect_ray(fwd).is_empty():
		climb = true
	if climb:
		dir.y = minf(dir.y + 2.0 * delta, 0.6)
	elif dir.y > 0.0:
		dir.y = maxf(dir.y - ms * 0.0015 / maxf(1.0 - dir.y, 0.05), 0.0)
	elif dir.y < 0.0:
		dir.y = minf(dir.y + ms * 0.0003 / maxf(1.0 + dir.y, 0.05), 0.0)
	if _visible_target and not climb:
		var ty := to.normalized().y
		dir.y = move_toward(dir.y, ty, ms * 0.001)
	if not g.is_empty() and global_position.y - (g.position as Vector3).y > max_height and not _visible_target:
		dir.y = minf(dir.y, -0.05)


func _orient(delta: float) -> void:
	if dir.length() < 0.01:
		return
	if state != 1:
		_bank = lerpf(_bank, 0.0, delta * 1.5)
	var b := Basis.looking_at(dir, Vector3.UP)
	b = b * Basis(Vector3.FORWARD, _bank)
	global_basis = b


func _start_engine() -> void:
	_engine = OrigAudio.play_file("motor%d.wav" % randi_range(1, 4), global_position, 30.0, 800.0, 1.0, self, true)
	if _engine:
		_engine.pitch_scale = 1.25 - randf() * 0.5


## Einschlagpunkt wie 0x5E81C0
func _shoot(tpos: Vector3, to: Vector3) -> void:
	var dist := to.length()
	var hdir := Vector3(dir.x, 0, dir.z).normalized()
	var side := hdir.cross(Vector3.UP).normalized()
	var p := tpos + hdir * ((randf() * 50.0 + dist - 125.0) * 0.15) + side * (randf() * 6.0 - 3.0)
	p.y = tpos.y - 1.0
	stats["shots"] += 1
	_impacts.append([dist / BULLET_SPEED, global_position, p])


func _process_impacts(delta: float) -> void:
	var i := 0
	while i < _impacts.size():
		_impacts[i][0] -= delta
		if _impacts[i][0] > 0.0:
			i += 1
			continue
		var from: Vector3 = _impacts[i][1]
		var at: Vector3 = _impacts[i][2]
		_impacts.remove_at(i)
		_impact(from, at)


## Einschlag 0x5E3A80: Strahl vom Abschuss bis 1,2 × zum Einschlagpunkt; Mensch getroffen → Schaden
func _impact(from: Vector3, at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var end := from + (at - from) * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, end, 1 | Hitbox.LAYER, [_hit_area.get_rid()])
	q.collide_with_areas = true
	var h := space.intersect_ray(q)
	if h.is_empty():
		return
	var pos: Vector3 = h.position
	var c = h.collider
	stats["impacts"] += 1
	if c is Hitbox and is_instance_valid((c as Hitbox).soldier):
		var hb := c as Hitbox
		stats["human_hits"] += 1
		if hb.soldier.has_method("apply_hit"):
			hb.soldier.apply_hit(damage, hb.zone, null, (at - from).normalized())
		Effects.blood(pos, h.normal)
	else:
		Effects.impact(pos, h.normal)
		if randi() % 4 == 0:
			OrigAudio.play_file("sand%02d.wav" % randi_range(1, 5), pos, 5.0, 80.0, 0.8)
