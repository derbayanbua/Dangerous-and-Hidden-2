class_name Dog
extends CharacterBody3D
## Wachhund (Original: Akteurtyp 30, Modell "(pes", Skriptbefehle DOG_*).
## Folgt seinem Besitzer (DOG_SetOwner), bemerkt Kommandos über Sicht/Gehör,
## schlägt dann Alarm (Bellen, ONALARM ans Skript) und greift an (DOG_Attack).
## Kann erschossen werden (Ballistik ruft on_bullet_hit). Animation: Platzhalter
## (statisches Originalmodell, wippt beim Laufen).

signal died_dog

const BITE_RANGE := 1.4
const BITE_INTERVAL := 0.9

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
var alarmed := false
var target: Soldier                ## Angriffsziel
var attack_any := false            ## DOG_Attack(NULL): nächstes Ziel selbst wählen

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
	if alarmed and target == null and attack_any:
		target = _nearest_enemy(999.0, false)
	if is_instance_valid(target) and target.alive and alarmed:
		goal = target.global_position
		speed = 7.5 if run_mode or alarmed else 3.0
		var d := global_position.distance_to(goal)
		_bite_t -= delta
		if d < BITE_RANGE:
			goal = Vector3.INF
			if _bite_t <= 0.0:
				_bite_t = BITE_INTERVAL
				target.apply_hit(bite_damage, &"leg", self, (target.global_position - global_position).normalized())
				Effects.play(&"step", global_position, 2.0, 0.5, 40.0)
		_bark_t -= delta
		if _bark_t <= 0.0:
			_bark_t = 1.6
			Events.emit_noise(global_position, 70.0, self, Soldier.TEAM_AXIS, &"bark")
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
	if _visual:
		_bob += delta * hv.length() * 2.5
		_visual.position.y = absf(sin(_bob)) * 0.06 if hv.length() > 0.1 else 0.0


func _scan() -> void:
	if alarmed or not aggressive:
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
	if not alive or suspended or alarmed or team == Soldier.TEAM_AXIS:
		return
	if pos.distance_to(global_position) <= minf(radius, hear_range):
		raise(source as Soldier)


func _on_global_alarm(_pos: Vector3, _by: Node) -> void:
	# Besitzer/Garnison alarmiert -> Hund wird scharf (Original: OnAlarm im Hundeskript)
	if alive and not suspended and not alarmed and aggressive:
		raise(null)


## Hund schlägt an: Skript bekommt ONALARM; Garnison wird über Bellen geweckt.
func raise(by: Soldier) -> void:
	if alarmed:
		return
	alarmed = true
	if by:
		target = by
	else:
		attack_any = true
	Events.emit_noise(global_position, 70.0, self, Soldier.TEAM_AXIS, &"bark")
	if runtime:
		runtime.notify(self, "ONALARM")


func clear_alarm() -> void:
	alarmed = false
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
	elif attacker is Soldier and not alarmed:
		raise(attacker)


func die() -> void:
	alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	if _visual:
		_visual.rotation.z = PI * 0.5
		_visual.position.y = 0.2
	died_dog.emit()
	if runtime:
		runtime.notify(self, "ONDEATH")
