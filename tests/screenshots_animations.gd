extends "res://tests/screenshots.gd"
## Kontrollbild-Serien der Soldatenanimationen (BodyAnim, TABLES\anim.sav) mit Original-Figuren deutsch (ge01a) und
## alliiert (en01) nebeneinander; Bewegung auf der Stelle (Figuren manuell getrieben), je Zustand 3–4 Bilder.
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots_animations [--only=walk,knife]
## Ausgabe: test_output/anim/<zustand>_<n>.png

const DIR := "res://test_output/anim/"
var pair: Array = []
var cam: Camera3D
var center := Vector3.ZERO
var follow := false
var _vdir := Vector3(1, 0, 0)
var _vdist := 4.2
var _vh := 1.0


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(DIR + name + ".png")
	print("SHOT ", name)


func _want(key: String) -> bool:
	if not Game.cli.has("only"):
		return true
	return Array(String(Game.cli["only"]).split(",")).has(key)


func _tick(secs: float) -> void:
	for i in int(secs * 60.0):
		for s in pair:
			if not s.is_physics_processing():
				s.model.update_anim(1.0 / 60.0, s.stance, Vector2(s.velocity.x, s.velocity.z).length(), s.look_pitch, s.aiming, s.lean)
		await get_tree().physics_frame


## Serie: n Bilder im Abstand dt (s) nach einer Vorlaufzeit pre.
func _series(name: String, n: int, dt: float, pre: float = 0.0) -> void:
	await _tick(pre)
	for i in n:
		await _tick(dt)
		if follow:
			var c0: Vector3 = (pair[0].global_position + pair[1].global_position) * 0.5
			cam.global_position = c0 + _vdir.normalized() * _vdist + Vector3.UP * _vh
			cam.look_at(c0 + Vector3.UP * 0.7)
		await frames(2)
		_shot("%s_%d" % [name, i + 1])


func _view(from_dir: Vector3, dist: float = 4.2, h: float = 1.0) -> void:
	_vdir = from_dir
	_vdist = dist
	_vh = h
	cam.global_position = center + from_dir.normalized() * dist + Vector3.UP * h
	cam.look_at(center + Vector3.UP * 0.7)


func _reset(stance: int = 0) -> void:
	for i in pair.size():
		var s: Soldier = pair[i]
		s.set_physics_process(true)
		s.swimming = false
		s.lean = 0.0
		s.velocity = Vector3.ZERO
		s.move_input = Vector3.ZERO
		s.aiming = false
		s.stance = stance
		s.stance_request = stance
		s._apply_capsule(stance)
		s.model._stance_blend = Vector3(1 if stance == 0 else 0, 1 if stance == 1 else 0, 1 if stance == 2 else 0)
		s.model.body.last_stance = stance
		s.model.body.stop_oneshot()
		for k in ["hands_up", "captured", "death_kind"]:
			if s.has_meta(k):
				s.remove_meta(k)
		s.global_position = mission_ground(center + Vector3(i * 1.7 - 0.85, 0, 0))
		s.look_yaw = 0.0
		s.health = s.max_health


func mission_ground(p: Vector3) -> Vector3:
	var m: Mission = Game.current_mission()
	return m.lb.ground(p.x, p.z, 0.05)


func _freeze(e: Soldier) -> void:
	for n in ["EnemyBrain", "Perception", "SquadBrain"]:
		var c: Node = e.get_node_or_null(n)
		if c:
			c.process_mode = Node.PROCESS_MODE_DISABLED


func _in_place(stance: int, vel: Vector3, mode: int) -> void:
	for s in pair:
		s.set_physics_process(false)
		s.stance = stance
		s.velocity = vel
		s.move_mode = mode


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for i in 600:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	await frames(30)
	for e in m.enemies:
		_freeze(e)
		e.global_position += Vector3(0, -50, 0)
	for mm in m.squad.members:
		_freeze(mm)
		mm.global_position += Vector3(80, 0, 80)
	m.controller.set_process(false)
	m.controller.set_physics_process(false)
	m.controller.set_process_unhandled_input(false)
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	center = mission_ground(Vector3(0, 0, 22))
	var g: Soldier = m.enemies[0]
	var a: Soldier = m.squad.members[1] if m.squad.members.size() > 1 else m.squad.leader()
	g.model.attach_orig(OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb"))
	a.model.attach_orig(OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb"))
	g.equip(["mp40", "p08", "m24", "", "knife"])
	a.equip(["enfield", "colt", "no36", "", "knife"])
	pair = [g, a]
	for s in pair:
		s.max_health = 100.0
		s.process_mode = Node.PROCESS_MODE_INHERIT
	cam = Camera3D.new()
	m.add_child(cam)
	cam.fov = 50
	cam.current = true
	_reset()
	await _tick(1.0)
	var side := Vector3(1, 0, -0.35)
	var front := Vector3(0.25, 0, -1)
	# --- Ruhe je Haltung ---
	if _want("idle"):
		for st in 3:
			_reset(st)
			_view(side if st < 2 else Vector3(1, 0, -0.6), 4.0, 0.8 - st * 0.25)
			await _series("idle_%d" % st, 1, 0.8)
	# --- Bewegung auf der Stelle (Sektor/Gangart wie im Spiel) ---
	if _want("walk"):
		var cases := [["walk_fwd", 0, Vector3(0, 0, -1.7), Soldier.MoveMode.WALK],
			["jog_fwd", 0, Vector3(0, 0, -3.3), Soldier.MoveMode.JOG], ["sprint_fwd", 0, Vector3(0, 0, -5.4), Soldier.MoveMode.RUN],
			["sneak_fwd", 0, Vector3(0, 0, -0.95), Soldier.MoveMode.SNEAK], ["walk_back", 0, Vector3(0, 0, 1.7), Soldier.MoveMode.WALK],
			["strafe_left", 0, Vector3(-1.7, 0, 0), Soldier.MoveMode.WALK], ["strafe_right", 0, Vector3(1.7, 0, 0), Soldier.MoveMode.WALK],
			["diag_fl", 0, Vector3(-1.2, 0, -1.2), Soldier.MoveMode.WALK],
			["crouch_fwd", 1, Vector3(0, 0, -1.1), Soldier.MoveMode.WALK], ["crouch_left", 1, Vector3(-1.1, 0, 0), Soldier.MoveMode.WALK],
			["crouch_back", 1, Vector3(0, 0, 0.7), Soldier.MoveMode.WALK],
			["crawl_fwd", 2, Vector3(0, 0, -0.6), Soldier.MoveMode.JOG], ["crawl_left", 2, Vector3(-0.45, 0, 0), Soldier.MoveMode.WALK],
			["crawl_back", 2, Vector3(0, 0, 0.45), Soldier.MoveMode.WALK]]
		for cs in cases:
			_reset(cs[1])
			_in_place(cs[1], cs[2], cs[3])
			_view(side, 4.2, [1.0, 0.7, 0.5][cs[1]])
			await _series(cs[0], 3, 0.18, 0.6)
	# --- Haltungswechsel ---
	if _want("stance"):
		for tr in [[0, 1, "st_dr"], [1, 2, "dr_le"], [2, 0, "le_st"], [0, 2, "st_le"]]:
			_reset(tr[0])
			_view(side, 4.2, 0.8)
			await _tick(0.6)
			for s in pair:
				s.stance_request = tr[1]
			await _series("stance_" + tr[2], 4, 0.15)
			await _tick(1.5)
	# --- Lehnen ---
	if _want("lean"):
		for st in 2:
			for dir in [-1.0, 1.0]:
				_reset(st)
				for s in pair:
					s.lean = dir
				_view(front, 4.2, 0.9 - st * 0.3)
				await _series("lean_%s_%d" % ["l" if dir < 0 else "r", st], 1, 0.8)
	# --- Springen / Klettern / Leiter ---
	if _want("jump"):
		follow = true
		_reset(0)
		_view(side, 4.5, 1.0)
		await _tick(0.4)
		for s in pair:
			s.jump_or_climb()
		await _series("jump", 4, 0.12)
		await _tick(1.0)
		_reset(0)
		await _tick(0.3)
		for s in pair:
			var p: Vector3 = s.global_position
			s.start_path_climb(p, p + Vector3(0, 1.05, -0.3), p + Vector3(0, 0.9, -0.9), 0.9)
		await _series("climb_low", 4, 0.2)
		await _tick(0.8)
		_reset(0)
		await _tick(0.3)
		for s in pair:
			var p: Vector3 = s.global_position
			s.start_path_climb(p, p + Vector3(0, 1.8, -0.3), p + Vector3(0, 1.6, -0.9), 1.4)
		await _series("climb_high", 4, 0.3)
		await _tick(0.8)
		_reset(0)
		await _tick(0.3)
		for s in pair:
			var p: Vector3 = s.global_position
			s.start_path_climb(p, p + Vector3(0, 2.0, 0), p + Vector3(0, 3.2, -0.4), 3.0)
		_view(side, 5.5, 2.0)
		await _series("ladder_up", 3, 0.45, 0.3)
		await _tick(2.5)
	follow = false
	# --- Schwimmen (Zustand manuell) ---
	if _want("swim"):
		_reset(0)
		for s in pair:
			s.set_physics_process(false)
			s.swimming = true
			s.velocity = Vector3(0, 0, -1.2)
		_view(side, 4.2, 1.2)
		await _series("swim", 3, 0.3, 0.5)
		for s in pair:
			s.velocity = Vector3.ZERO
		await _series("swim_idle", 1, 0.8)
	# --- Treffer ---
	if _want("hit"):
		for z in [["head", Vector3(0, 0, 1)], ["leg", Vector3(0, 0, 1)], ["arm", Vector3(0, 0, 1)], ["torso", Vector3(0, 0, -1)]]:
			_reset(0)
			_view(side, 4.2, 1.0)
			await _tick(0.4)
			for s in pair:
				s.max_health = 100000.0
				s.health = 100000.0
				s.apply_hit(5.0, StringName(z[0]), pair[1] if s == pair[0] else pair[0], z[1])
			await _series("hit_" + String(z[0]), 3, 0.2)
			await _tick(0.8)
		for s in pair:
			s.max_health = 100.0
	# --- Ergeben / Gefangener ---
	if _want("surrender"):
		_reset(0)
		_view(front, 4.2, 1.0)
		for s in pair:
			s.set_meta("hands_up", true)
		await _series("surrender", 2, 0.6)
		for s in pair:
			s.set_meta("captured", true)
			s.stance_request = 1
		await _series("captive", 2, 0.8)
	# --- Benutzen / Aufheben / Sprengstoff ---
	if _want("use"):
		for k in [["door_st", 0], ["pickup_st", 0], ["manip_kl", 0], ["tying", 0]]:
			_reset(k[1])
			_view(side, 4.2, 0.9)
			await _tick(0.4)
			for s in pair:
				s.model.play_body(k[0], 1.6, true, "use")
			await _series("use_" + String(k[0]), 3, 0.4)
	# --- Messer von vorn (Stichfolge) ---
	if _want("knife"):
		_reset(0)
		for s in pair:
			s.select_slot(WeaponData.Slot.MELEE)
		await _tick(0.8)
		_view(side, 4.0, 1.0)
		for s in pair:
			s._melee(s.current_weapon())
		await _series("knife_front", 4, 0.06)
		await _tick(0.6)
		_reset(1)
		for s in pair:
			s.select_slot(WeaponData.Slot.MELEE)
		await _tick(0.8)
		for s in pair:
			s._melee(s.current_weapon())
		await _series("knife_crouch", 4, 0.07)
		await _tick(0.6)
		# von hinten: Angreifer en01 hinter ge01a, Kehlschnitt
		_reset(0)
		var vic: Soldier = pair[0]
		var att: Soldier = pair[1]
		att.select_slot(WeaponData.Slot.MELEE)
		vic.global_position = mission_ground(center)
		att.global_position = mission_ground(center + Vector3(0, 0, 0.75))
		vic.look_yaw = 0.0
		att.look_yaw = 0.0
		await _tick(0.8)
		_view(Vector3(1, 0, 0.2), 4.0, 1.0)
		att._melee(att.current_weapon())
		await _series("knife_back", 4, 0.1)
		await _series("death_throat", 3, 0.9)
	# --- Tode je Richtung ---
	if _want("death"):
		for d in [["front", Vector3(0, 0, 1)], ["back", Vector3(0, 0, -1)], ["left", Vector3(1, 0, 0)], ["right", Vector3(-1, 0, 0)]]:
			_reset(0)
			_view(Vector3(1, 0, 0.1), 5.0, 1.4)
			await _tick(0.4)
			for s in pair:
				s.die(null, d[1])
			await _series("death_" + String(d[0]), 3, 0.5)
			# wiederbeleben für den nächsten Fall
			for s in pair:
				s.alive = true
				s.collision_layer = 1 << 1
				s.model._dead = false
				s.model.body.stop_oneshot()
				s.add_to_group("team_%d" % s.team)
				s.remove_from_group("corpses")
				s.model._orig_clip = ""
				s.model.set_weapon(s.current_weapon().data if s.current_weapon() else null)
	print("FERTIG")
	get_tree().quit(0)
