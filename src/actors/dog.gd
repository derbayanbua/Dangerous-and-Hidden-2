class_name Dog
extends CharacterBody3D
## Wachhund (Original: Akteurtyp 30, Modell "(pes", Skriptbefehle DOG_*).
## Folgt seinem Besitzer (DOG_SetOwner), bemerkt Kommandos über Sicht/Gehör,
## schlägt dann Alarm (Bellen, ONALARM ans Skript) und greift an (DOG_Attack).
## Kann erschossen werden (Ballistik ruft on_bullet_hit). Animation: Platzhalter
## (statisches Originalmodell, wippt beim Laufen).

signal died_dog

const BITE_RANGE := 2.1       ## Original 0x5C49A0: Biss trifft, wenn das Ziel näher als 2,1 m ist (0x811FA0) [B]
const BITE_APPROACH := 1.3    ## so nah läuft der Hund heran, bevor er zubeißt [E]
const BITE_INTERVAL := 0.9    ## Ersatztakt ohne Angriffsclip [E]

var runtime: LsRuntime
var owner_frame: Node3D            ## DOG_SetOwner
var suspended := false             ## DOG_Suspend
var aggressive := true             ## DOG_SETAIMODE_*
var run_mode := false              ## DOG_SETMODE_Run / Walk
var sight_range := 30.0            ## DOG_SetRangeSight
var hear_range := 40.0             ## DOG_SetRangeHear
var health := 45.0
var bite_damage := 14.0           ## Original: Biss 50 (Skala wie Soldaten)
var alive := true
var alarmed := false               ## Alarmbit (DOG_ClearAlarm löscht nur dieses)
var attacking := false             ## DOG_Attack bzw. eigener Angriff (aggressiv) – bleibt nach DOG_ClearAlarm
var target: Soldier                ## Angriffsziel
var attack_any := false            ## DOG_Attack(NULL): nächstes Ziel selbst wählen
var move_target := Vector3.INF     ## DOG_Move(Wegpunkt)
var lying := false                 ## DOG_SETMODE_Lie

var _visual: Node3D
var _agent: NavigationAgent3D
var _bite_t := 0.0
var _bark_t := 0.0
var _scan_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _bob := 0.0


func setup(visual: Node3D) -> void:
	_visual = visual
	if visual:
		add_child(visual)
		var aps := visual.find_children("*", "AnimationPlayer", true, false)
		_anim = aps[0] as AnimationPlayer if not aps.is_empty() else null
		if _anim:
			for a in ["idle", "walk", "run", "sniff", "attack", "attack2", "lie", "bark"]:
				if _anim.has_animation(a):
					_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			_play("idle")


## Original-Hundeanimationen (TABLES\dog_anim.sav, Überblendung 250 ms [B]; export_characters.py --dogs → characters/(pes.glb).
## Ohne skinned Modell (alter Cache): statisches Modell, das beim Laufen wippt.
var _anim: AnimationPlayer
var _cur_anim := ""
var _oneshot := 0.0
const BLEND := 0.25


func _play(n: String, force := false) -> void:
	if _anim == null or not _anim.has_animation(n) or (n == _cur_anim and not force):
		return
	_cur_anim = n
	_anim.play(n, BLEND)


func _play_once(n: String) -> float:
	if _anim == null or not _anim.has_animation(n):
		return 0.0
	_play(n, true)
	_oneshot = _anim.get_animation(n).length
	return _oneshot


func _update_anim(delta: float, hv: Vector3, biting: bool) -> void:
	if _anim == null:
		return
	if _oneshot > 0.0:
		_oneshot -= delta
		return
	var v := Vector2(hv.x, hv.z).length()
	if biting:
		_play("attack")
	elif v > 3.5:
		_play("run")
	elif v > 0.2:
		_play("walk")
	elif lying:
		if _cur_anim != "lie" and _cur_anim != "lie_down" and _play_once("lie_down") > 0.0:
			return
		_play("lie")
	elif _cur_anim == "lie" and _play_once("stand_up") > 0.0:
		return
	elif alarmed or attacking:
		_play("bark")
	else:
		_play("idle")


func _ready() -> void:
	add_to_group("dogs")
	collision_layer = 1
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.6, 1.0)
	cs.shape = box
	cs.position = Vector3(0, 0.35, 0)
	add_child(cs)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.8
	_agent.target_desired_distance = 1.0
	add_child(_agent)
	Events.noise_emitted.connect(_on_noise)
	Events.alarm_raised.connect(_on_global_alarm)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if suspended:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_scan()
	var goal := Vector3.INF
	var speed := 2.0
	var biting := false
	if attacking and (target == null or not target.alive) and attack_any:
		target = _nearest_enemy(999.0, false)
	if is_instance_valid(target) and target.alive and attacking:
		goal = target.global_position
		speed = 7.5 if run_mode or attacking else 3.0
		var d := global_position.distance_to(goal)
		_bite_t -= delta
		if d < BITE_APPROACH:
			goal = Vector3.INF
			biting = true
			var to := target.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
			if _bite_t <= 0.0:
				# Original 0x5C49A0 „Kousnul jsem humana“: Biss im Angriffszustand (5/6), wenn das Ziel < 2,1 m ist; Schaden
				# Art 8 = Biss (+0x4A4, Std. 50 zotti) [B]. Takt = Länge des Angriffsclips (pesutok) [P]
				_bite_t = _anim.get_animation("attack").length if _anim and _anim.has_animation("attack") else BITE_INTERVAL
				if d < BITE_RANGE:
					target.apply_hit(bite_damage, &"leg", self, to.normalized())
				OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_DOG_ATTACK, global_position, self)   # „Dog Attack“
		_bark_t -= delta
		if _bark_t <= 0.0:
			_bark_t = 1.6
			Events.emit_noise(global_position, 70.0, self, Soldier.TEAM_AXIS, &"bark")
			# Original Kat. 11: „Dog Woof“ (Bellen), beim Rennen „Dog Runing“ (Takt 1,6 s = Annahme)
			OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_DOG_WOOF if randf() < 0.7 else OrigAudio.MISC_DOG_RUN,
				global_position, self)
	elif move_target.is_finite():
		if global_position.distance_to(move_target) < 1.2:
			move_target = Vector3.INF
		else:
			goal = move_target
			speed = 4.0 if run_mode else 2.2
	elif lying:
		goal = Vector3.INF
	elif is_instance_valid(owner_frame):
		var od := global_position.distance_to(owner_frame.global_position)
		if od > 3.0:
			goal = owner_frame.global_position
			speed = 4.5 if od > 8.0 else 2.2
	var hv := Vector3.ZERO
	if goal.is_finite():
		_agent.target_position = goal
		var nxt := _agent.get_next_path_position()
		if _agent.is_navigation_finished() or nxt.distance_to(global_position) < 0.05:
			nxt = goal
		hv = (nxt - global_position)
		hv.y = 0.0
		if hv.length() > 0.05:
			hv = hv.normalized() * speed
			rotation.y = lerp_angle(rotation.y, atan2(hv.x, hv.z), clampf(delta * 8.0, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	if _anim:
		_update_anim(delta, hv, biting)
	elif _visual:
		_bob += delta * hv.length() * 2.5
		_visual.position.y = absf(sin(_bob)) * 0.06 if hv.length() > 0.1 else 0.0


func _scan() -> void:
	if alarmed or attacking or not aggressive:
		return
	var e := _nearest_enemy(sight_range, true)
	if e:
		raise(e)


func _nearest_enemy(max_dist: float, need_los: bool) -> Soldier:
	var best: Soldier = null
	var bd := max_dist
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_ALLIED):
		var s := n as Soldier
		if s == null or not s.alive or s.vehicle != null:
			continue
		var d := global_position.distance_to(s.global_position)
		if d >= bd:
			continue
		if need_los:
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, s.global_position + Vector3.UP * 1.0, 1, [get_rid()])
			if not space.intersect_ray(q).is_empty():
				continue
		best = s
		bd = d
	return best


func _on_noise(pos: Vector3, radius: float, source: Node, team: int, _kind: StringName) -> void:
	if not alive or suspended or alarmed or attacking or team == Soldier.TEAM_AXIS:
		return
	if pos.distance_to(global_position) <= minf(radius, hear_range):
		raise(source as Soldier)


func _on_global_alarm(_pos: Vector3, _by: Node) -> void:
	# Besitzer/Garnison alarmiert -> Hund wird scharf (Original: OnAlarm im Hundeskript)
	if alive and not suspended and not alarmed and not attacking and aggressive:
		raise(null)


## Hund schlägt an: Skript bekommt ONALARM; Garnison wird über Bellen geweckt.
func raise(by: Soldier) -> void:
	if alarmed or attacking:
		return
	alarmed = true
	if aggressive:
		attacking = true
	if by:
		target = by
	else:
		attack_any = true
	Events.emit_noise(global_position, 70.0, self, Soldier.TEAM_AXIS, &"bark")
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_DOG_WOOF, global_position, self)
	if runtime:
		runtime.notify(self, "ONALARM")


## DOG_ClearAlarm (Opcode 0x11 → KI-vtable +0x38 = 0x5CE700 mit 0): löscht nur das Alarmbit 0x80000000 und die
## Alarmquelle +0x1C; Angriffsflags (0x140000) und Ziel +0x8C aus DOG_Attack (0x5CF7C0) bleiben [B]. ARCTIC1
## r_arc1a_dog.scr läuft nach OnAlarm → DOG_Attack(NULL) durch bis „label wait: DOG_ClearAlarm()“ – früher brach das den
## Angriff sofort ab (B-020: „Hund verhält sich fehlerhaft“).
func clear_alarm() -> void:
	alarmed = false


## Angriff beenden (Spielstand/Skriptende) – im Original kein eigener Skriptbefehl dafür
func stop_attack() -> void:
	attacking = false
	target = null
	attack_any = false


func on_bullet_hit(damage: float, shooter: Node) -> void:
	apply_hit(damage, &"torso", shooter, Vector3.ZERO)


func apply_hit(amount: float, _zone: StringName, attacker: Node, _dir: Vector3) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		die()
		return
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_DOG_HURT, global_position, self)   # „Dog Injure“
	if not lying:
		_play_once("hurt")     # zraneni2 (dog_anim.sav Eintrag 19) [P]
	if attacker is Soldier and not alarmed and not attacking:
		raise(attacker)


func die() -> void:
	alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_DOG_DEATH, global_position)   # „Dog Death“
	if _anim and _anim.has_animation("death"):
		# Tod im Liegen (pessmrtleh) bzw. im Stand (pessmrt1), dog_anim.sav Einträge 12–16 [P]
		var dn := "death_lie" if lying and _anim.has_animation("death_lie") else "death"
		_anim.get_animation(dn).loop_mode = Animation.LOOP_NONE
		_cur_anim = ""
		_play(dn)
	elif _visual:
		_visual.rotation.z = PI * 0.5
		_visual.position.y = 0.2
	died_dog.emit()
	if runtime:
		runtime.notify(self, "ONDEATH")
