class_name EscortBrain
extends AIBrain
## Begleitperson (z. B. befreiter Gefangener). Vor der Befreiung gefesselt
## (keine Bewegung, für Gegner kein Ziel). Danach folgt sie dem aktiven
## Soldaten des Trupps, übernimmt Haltung und Gangart, wartet bei großem
## Abstand geduckt. Unbewaffnet.

var squad: SquadManager
var released := false


func setup(s: Soldier) -> void:
	super.setup(s)
	s.remove_from_group("team_%d" % s.team)   # gefesselt: kein Ziel
	s.stance_request = Soldier.Stance.CROUCH


func release() -> void:
	if released:
		return
	released = true
	soldier.add_to_group("team_%d" % soldier.team)
	Events.say("%s: \"Danke! Ich folge Ihnen.\"" % soldier.soldier_name, 3.0)


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive:
		return
	if not released:
		soldier.stance_request = Soldier.Stance.CROUCH
		soldier.move_input = Vector3.ZERO
		return
	var lead := squad.leader() if squad else null
	if lead == null:
		update_movement(delta)
		return
	# Fahrzeug: mit dem Anführer ein-/aussteigen
	if lead.vehicle != null and soldier.vehicle == null and distance_to(lead.vehicle.global_position) < 4.0:
		lead.vehicle.board(soldier)
	elif lead.vehicle == null and soldier.vehicle != null:
		soldier.vehicle.leave(soldier)
	if soldier.vehicle != null:
		return
	var d := distance_to(lead.global_position)
	soldier.stance_request = lead.stance
	if d > 40.0:
		# zu weit weg: in Deckung warten
		stop_moving()
		soldier.stance_request = Soldier.Stance.CROUCH
	elif d > 3.5:
		var behind := lead.global_position - lead.forward() * 2.5
		move_to(behind, Soldier.MoveMode.RUN if d > 10.0 else lead.move_mode)
	else:
		stop_moving()
		soldier.look_yaw = rotate_toward(soldier.look_yaw, lead.look_yaw, delta * 3.0)
	update_movement(delta)


func serialize() -> Dictionary:
	return {"released": released}


func deserialize(d: Dictionary) -> void:
	if d.get("released", false):
		released = false
		release()
