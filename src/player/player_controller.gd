class_name PlayerController
extends Node
## Übersetzt Eingaben in Absichten des aktiven Soldaten und Squad-Befehle.

var squad: SquadManager
var rig: CameraRig
var mission: Node
var active: Soldier
var input_enabled := true
var interact_target: Interactable

var _crouch_toggle := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func set_active(s: Soldier) -> void:
	active = s
	rig.set_target(s)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_instance_valid(active):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity * 0.01
		if active.using_binoculars:
			sens *= 12.0 / Settings.fov
		elif active.aiming and active.current_weapon():
			sens *= active.current_weapon().data.aim_fov / Settings.fov
		active.look_yaw -= event.relative.x * sens
		var dy: float = event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		active.look_pitch = clampf(active.look_pitch - dy, deg_to_rad(-80), deg_to_rad(80))
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("camera_toggle"):
		rig.toggle_mode()
	elif event.is_action_pressed("stance_crouch"):
		active.stance_request = Soldier.Stance.STAND if active.stance_request == Soldier.Stance.CROUCH else Soldier.Stance.CROUCH
	elif event.is_action_pressed("stance_prone"):
		active.stance_request = Soldier.Stance.CROUCH if active.stance_request == Soldier.Stance.PRONE else Soldier.Stance.PRONE
	elif event.is_action_pressed("stance_stand"):
		active.stance_request = Soldier.Stance.STAND
	elif event.is_action_pressed("reload"):
		active.reload()
	elif event.is_action_pressed("weapon_1"):
		active.select_slot(0)
	elif event.is_action_pressed("weapon_2"):
		active.select_slot(1)
	elif event.is_action_pressed("weapon_3"):
		active.select_slot(2)
	elif event.is_action_pressed("weapon_next"):
		active.cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		active.cycle_weapon(-1)
	elif event.is_action_pressed("binoculars"):
		active.toggle_binoculars()
	elif event.is_action_pressed("medkit"):
		if active.medkits <= 0:
			Events.say("Kein Verbandskasten mehr.", 1.5)
		elif not active.start_heal(get_tree().get_nodes_in_group("team_%d" % active.team)):
			Events.say("Niemand in Reichweite ist verwundet.", 1.5)
	elif event.is_action_pressed("fire_mode"):
		var w := active.current_weapon()
		if w and w.toggle_fire_mode():
			Events.say("Feuermodus: %s" % w.fire_mode_text(), 1.5)
	elif event.is_action_pressed("interact"):
		if active.vehicle != null:
			# Aussteigen: Fahrer lässt alle aussteigen
			var v: Vehicle = active.vehicle
			if active.seat_index == 0:
				v.leave_all()
			else:
				v.leave(active)
			Events.say("Ausgestiegen.", 1.5)
		elif interact_target and is_instance_valid(interact_target):
			interact_target.interact(active)
	elif event.is_action_pressed("soldier_1"):
		squad.set_active(0)
	elif event.is_action_pressed("soldier_2"):
		squad.set_active(1)
	elif event.is_action_pressed("soldier_3"):
		squad.set_active(2)
	elif event.is_action_pressed("soldier_4"):
		squad.set_active(3)
	elif event.is_action_pressed("soldier_next"):
		squad.cycle_active()
	elif event.is_action_pressed("order_move"):
		var p := rig.crosshair_point(150.0)
		squad.order_all(SquadBrain.Order.MOVE, p)
		Events.say("Befehl: Dorthin bewegen (%d m)" % int(active.global_position.distance_to(p)), 2.0)
	elif event.is_action_pressed("order_grenade"):
		var gp := rig.crosshair_point(60.0)
		var thrower := squad.order_grenade(gp)
		if thrower:
			Events.say("Befehl: %s, Granate dorthin (%d m)" % [thrower.soldier_name, int(thrower.global_position.distance_to(gp))], 2.0)
		else:
			Events.say("Niemand im Trupp hat noch Granaten.", 2.0)
	elif event.is_action_pressed("order_follow"):
		squad.order_all(SquadBrain.Order.FOLLOW)
		Events.say("Befehl: Mir folgen", 2.0)
	elif event.is_action_pressed("order_hold"):
		squad.order_all(SquadBrain.Order.HOLD)
		Events.say("Befehl: Position halten", 2.0)
	elif event.is_action_pressed("order_roe"):
		var r := squad.toggle_roe()
		Events.say("Befehl: %s" % ("Feuer frei" if r == SquadBrain.ROE.FIRE_AT_WILL else "Feuer halten"), 2.0)
	elif event.is_action_pressed("order_formation"):
		Events.say("Formation: %s" % squad.cycle_formation(), 2.0)
	elif event.is_action_pressed("order_stance"):
		var st := active.stance
		for m in squad.members:
			var b := squad.brain_of(m)
			if b and m != active:
				b.stance_override = st if b.stance_override != st else -1
		Events.say("Befehl: Haltung %s" % ["Stehen", "Hocken", "Liegen"][st], 2.0)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(active) or not active.alive:
		return
	if not input_enabled:
		active.move_input = Vector3.ZERO
		active.trigger = false
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if active.vehicle != null:
		var v: Vehicle = active.vehicle
		if active.seat_index == 0:
			v.throttle = -iv.y
			v.steer_input = -iv.x
			v.handbrake = Input.is_action_pressed("stance_stand")
		active.aiming = Input.is_action_pressed("aim") and active.seat_index > 0
		active.trigger = active.seat_index > 0 and Input.is_action_pressed("fire")
		active.aim_point = rig.crosshair_point()
		active.has_aim_point = true
		interact_target = null
		return
	var basis := Basis(Vector3.UP, active.look_yaw)
	active.move_input = basis * Vector3(iv.x, 0, iv.y)
	if Input.is_action_pressed("run"):
		active.move_mode = Soldier.MoveMode.RUN
	elif Input.is_action_pressed("sneak"):
		active.move_mode = Soldier.MoveMode.SNEAK
	else:
		active.move_mode = Soldier.MoveMode.WALK
	# Automatisierte Tests simulieren Eingaben ohne Mausfang
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.cli.has("autoplay")
	active.trigger = captured and Input.is_action_pressed("fire")
	active.aiming = captured and Input.is_action_pressed("aim")
	var l := 0.0
	if Input.is_action_pressed("lean_left"):
		l -= 1.0
	if Input.is_action_pressed("lean_right"):
		l += 1.0
	active.lean = l if active.stance != Soldier.Stance.PRONE else 0.0
	active.aim_point = rig.crosshair_point()
	active.has_aim_point = true
	# Rückstoß auf die Blickrichtung anwenden
	var r := active.consume_recoil()
	if r != Vector2.ZERO:
		active.look_pitch = clampf(active.look_pitch + deg_to_rad(r.x), deg_to_rad(-80), deg_to_rad(80))
		active.look_yaw += deg_to_rad(r.y)
	_update_interact_target()


func _update_interact_target() -> void:
	var best: Interactable = null
	var best_d := 2.4
	var fwd := active.forward()
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.can_interact(active):
			continue
		var to := it.global_position - active.global_position
		to.y = 0
		var d := to.length()
		if d < best_d and (d < 0.9 or fwd.angle_to(to) < 1.0):
			best_d = d
			best = it
	interact_target = best
