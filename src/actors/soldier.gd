class_name Soldier
extends CharacterBody3D
## Spielfigur (Spieler, Teammitglied oder Gegner).
## Gesteuert wird ausschließlich über "Absichten" (move_input, move_mode,
## stance_request, look_yaw/look_pitch, trigger, aim_point ...). Dieselbe
## Schnittstelle nutzen PlayerController, SquadBrain und EnemyBrain.
##
## Belegte Original-Mechaniken (docs/RE_FINDINGS.md): Haltungen Stand/Crouch/Lie
## (HUMAN_SETMODE_*), Gangarten Walk/Run, Ausdauer (staminabar), Gesundheit
## (healthbar), Seh-/Hörreichweite (HUMAN_SETSIGHTRANGE/SETHEARRANGE),
## getrennte Schadenszonen ("Unknow damage zone").

signal died(soldier: Soldier)
signal damaged(amount: float, zone: StringName)
signal weapon_changed(weapon: Weapon)
signal stance_changed(stance: int)
signal shot_fired(weapon: Weapon)
## Animierte Aktion begonnen ("reload", "draw", "throw", "heal"); die 1. Person spielt dazu die FPV-Animation
signal action_started(kind: String, duration: float)
signal grenade_released(grenade: Node)
## Figur/Modell gewechselt (Uniform): Kamera setzt Anker und Sichtbarkeit neu
signal model_changed(model: Node3D)

enum Stance { STAND, CROUCH, PRONE }
## WALK/SNEAK: KI und Originalskripte (Patrouille, HUMAN_SETMODE_*); JOG: Normaltempo des
## Spielers (moderne Steuerung: immer Laufschritt, Shift = Sprint/RUN, leise nur geduckt/liegend)
enum MoveMode { WALK, RUN, SNEAK, JOG }

const FALL_SAFE_V := 9.0
const TEAM_ALLIED := 0
const TEAM_AXIS := 1
## Neutral (Original actors.bin Seite 3/4: Zivilisten, Gefangene, Sonderfiguren): wird von keiner Seite
## gezielt angegriffen und greift selbst nicht an, bis ein Skript ihn dem Team zuordnet (SetNPCTeamStatus).
const TEAM_NEUTRAL := 2

## Geschwindigkeiten m/s [Stance][MoveMode] (Designwerte)
const SPEEDS := [
	[1.7, 5.4, 0.95, 3.3],   # stehen: gehen, sprinten, schleichen, normal
	[1.1, 2.3, 0.7, 1.3],    # hocken (normal = leises Schleichen)
	[0.45, 0.75, 0.35, 0.6], # liegen (kriechen)
]
const EYE_HEIGHT := [1.62, 1.05, 0.32]
const CAPSULE_HEIGHT := [1.8, 1.2, 0.6]
const STANCE_TIME := [0.0, 0.35, 0.9]   ## Wechselzeit in Haltung X hinein
## Schrittgeräusch-Radius in m [Stance][MoveMode]
const STEP_NOISE := [[7.0, 20.0, 2.5, 11.0], [4.0, 9.0, 1.5, 2.5], [1.5, 2.5, 1.0, 1.2]]
const JUMP_VELOCITY := 4.2
## Klettern/Überspringen beim Sprung vor einem Hindernis (Höhe über den Füßen, m)
const CLIMB_MIN := 0.45
const CLIMB_MAX := 2.3
## Stufen automatisch hinauf (Original: Stufen mit eigener Klz-Flächenkollision, z. B. CZECH3-Wendeltreppe 0,17 m,
## begeht die Figur ohne Rampe [B]; Höhe 0,4 m = Navmesh agent_max_climb [E]). Abwärts hält floor_snap_length.
const STEP_HEIGHT := 0.4

@export var soldier_name := "Soldat"
@export var team := TEAM_ALLIED
@export var max_health := 100.0
@export var uniform_color := Color(0.42, 0.38, 0.26)
@export var helmet_style := "brodie"
@export var persistent_id := ""         ## für Spielstände

# --- Zustand ---
var health := 100.0
var stamina := 100.0
var stance: int = Stance.STAND
var alive := true
var weapons: Array[Weapon] = []        ## Index = WeaponData.Slot
var current_slot := 0
var grenade_cooldown := 0.0

# --- Absichten (werden pro Frame vom Controller gesetzt) ---
var move_input := Vector3.ZERO      ## Weltrichtung, Länge 0..1
var move_mode: int = MoveMode.WALK
var stance_request: int = Stance.STAND
var look_yaw := 0.0                 ## Rad, Körperausrichtung
var look_pitch := 0.0               ## Rad, Zielneigung (+ = hoch)
var trigger := false
var aiming := false
var lean := 0.0                     ## -1 links .. 1 rechts
var aim_point := Vector3.ZERO       ## Weltpunkt, auf den die Waffe zielt
var has_aim_point := false
var extra_spread := 0.0             ## Zusatzstreuung (Grad), z. B. KI-Fehler
var is_player_controlled := false

# --- intern ---
var model: SoldierModel
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _stance_lock := 0.0
var _recoil := Vector2.ZERO          ## (pitch, yaw) Grad, wird vom Controller verbraucht
var _step_accum := 0.0
var _hitbox_rids: Array[RID] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var last_attacker: Node = null
var vehicle: Node = null            ## Fahrzeug, in dem der Soldat sitzt
var mounted: Node = null            ## besetzte Waffenstellung (OrigInteractive.OrigEmplacement)
var seat_index := -1

## Ausrüstung (Original-Inventar: ii_aid/ii_aidbig, ii_binoc)
var medkits := 1
var has_binoculars := true
var using_binoculars := false
var heal_time_left := 0.0           ## > 0: legt gerade einen Verband an
var heal_target: Soldier
const HEAL_DURATION := 3.0
const HEAL_AMOUNT := 45.0
## Platzierbare Ausrüstung (Original: Dynamit/Sprengstofftasche 67/68, Minen 70/71)
var explosives := 0
var mines := 0
## Gewähltes Hilfsmittel statt Waffe ("" = Waffe; "explosive", "mine", "medkit", "binoculars"):
## Linksklick benutzt es (vereinfachte Steuerung, Vorgabe Auftraggeber). Wechsel steckt die Waffe weg und
## nimmt das Original-Modell des Hilfsmittels in die Hand (_on_tool_changed); zurück zur Waffe = Ziehen.
var tool := "":
	set(v):
		if v == tool:
			return
		var was := tool
		tool = v
		_on_tool_changed(was)
var _tool_trigger_prev := false
## Laufende Arbeit mit Fortschrittsanzeige (z. B. Mine entschärfen, PlacedCharge.DefuseSpot); work_left > 0 = aktiv
var work_label := ""
var work_left := 0.0
var work_total := 0.0
var _tool_quiet := false             ## Wechsel ohne Zieh-Animation (select_slot wechselt gleich die Waffe)
## Original-Weltmodelle der Hilfsmittel (items.sav: 54 l_medkit, 70 w_antiman, 67/68 Sprengladung, 99 w_binocul),
## erstes vorhandenes wird genommen
const TOOL_MODELS := {"medkit": ["l_medkit"], "mine": ["w_antiman"],
	"explosive": ["w_explosive", "w_dynamite", "d_explbag"], "binoculars": ["w_binocul"]}
## Original-FPV-Modelle der Hilfsmittel (items.sav fpv_model; nur die Mine ist im Cache exportiert)
const TOOL_FPV := {"mine": "w_antimanfpv"}
## Netzcode der Hilfsmittel (Aktion „tool“, Index in a.x)
const TOOL_KEYS := ["", "explosive", "mine", "medkit", "binoculars"]


## Modellname des Hilfsmittels in der Hand ("" = keins gewählt; Platzhalter, wenn kein Original im Cache).
func tool_model_name(key: String = tool) -> String:
	if key == "":
		return ""
	var names: Array = TOOL_MODELS.get(key, [])
	var found := OrigWeapons.first_model(names)
	return found if found != "" else "placeholder:" + key


func _on_tool_changed(was: String) -> void:
	if not is_node_ready():
		return
	if tool != "":
		var cw := current_weapon()
		if cw:
			cw.cancel_reload()
	if model:
		model.stop_action()
		if heal_time_left <= 0.0:
			model.set_prop(tool_model_name())
	_net("tool", Vector3(maxi(TOOL_KEYS.find(tool), 0), 0, 0), Vector3.ZERO, "")   # wid bleibt leer (Waffen-ID)
	if _tool_quiet:
		return
	weapon_changed.emit(current_weapon())
	if tool == "" and was != "":
		var w := current_weapon()
		if w:
			w.cooldown = maxf(w.cooldown, 0.5)
			OrigAudio.play_weapon(w.data, "armed", global_position, self, team)
		play_weapon_action("draw")          # Waffe wieder ziehen (anim.sav „vyt*“, 1. Person „arm“)
var _trigger_prev := false
var _melee_cd := 0.0
var _lean_sent := 0.0
## Mehrspieler (Net): Soldat eines anderen Spielers – Position/Blick kommen aus dem Netz
var net_puppet := false
var net_target := Vector3.ZERO
var net_velocity := Vector3.ZERO
## eigener Mehrspieler-Soldat: Aktionen (kind, a, b, Waffen-ID) an die anderen Rechner melden
var net_hook: Callable


func _net(kind: String, a: Vector3, b: Vector3, wid: String) -> void:
	if net_hook.is_valid() and not net_puppet:
		net_hook.call(kind, a, b, wid)

## Original-Fähigkeiten des SAS-Kaders (0–100, roster.json); < 0 = ohne Kaderwerte (neutral).
## Wirkung (Annahme, Größenordnung am Original orientiert): Schießen -> Streuung, Tarnung -> Erkennbarkeit,
## Ausdauer -> Sprintverbrauch, Erste Hilfe -> Wirkung eines Verbands.
var skill_shooting := -1.0
var skill_stealth := -1.0
var skill_endurance := -1.0
var skill_first_aid := -1.0
## Trainingszähler der laufenden Mission (SAS.training_gain): kills, sneak_s, sprint_s, heals, locks, unseen_kills
var training := {}


static func skill_k(v: float, at0: float, at100: float) -> float:
	return 1.0 if v < 0.0 else lerpf(at0, at100, clampf(v / 100.0, 0.0, 1.0))


func train(key: String, amount: float = 1.0) -> void:
	training[key] = training.get(key, 0.0) + amount


## Verband anlegen: Kamerad vor sich (≤ 2 m, verletzt) oder sich selbst.
func start_heal(candidates: Array) -> bool:
	if medkits <= 0 or heal_time_left > 0.0 or vehicle != null:
		return false
	var best: Soldier = null
	for c in candidates:
		var s := c as Soldier
		if s == null or s == self or not s.alive or s.health >= s.max_health - 1.0:
			continue
		if s.global_position.distance_to(global_position) < 2.0:
			best = s
			break
	if best == null and health < max_health - 1.0:
		best = self
	if best == null:
		return false
	heal_target = best
	heal_time_left = HEAL_DURATION
	using_binoculars = false
	var cw := current_weapon()
	if cw:
		cw.cancel_reload()
	# Verbandskasten in die Hand (Original-Weltmodell l_medkit, items.sav 54) und kniende Original-Animation
	# (anim.sav „!medik01“ Kamerad / „!medik“ selbst – Zuordnung [P])
	if model:
		model.stop_action()
		model.set_prop(MEDKIT_MODEL)
		model.play_full("medic_self" if best == self else "medic")
	action_started.emit("heal", HEAL_DURATION)
	# Original Kat. 11 „Medic“ (24) bzw. „Medic samolecitel“ (26, Selbstversorgung)
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_SELF_MEDIC if best == self else OrigAudio.MISC_MEDIC,
		global_position, self)
	return true


func _update_heal(delta: float) -> void:
	if heal_time_left <= 0.0:
		return
	trigger = false
	move_input = Vector3.ZERO
	heal_time_left -= delta
	if not is_instance_valid(heal_target) or not heal_target.alive or not alive:
		heal_time_left = 0.0
		_end_heal_anim()
		return
	if heal_time_left <= 0.0:
		heal_time_left = 0.0
		_end_heal_anim()
		medkits -= 1
		var amount := HEAL_AMOUNT * skill_k(skill_first_aid, 0.7, 1.4)
		heal_target.heal(amount)
		train("heals")
		if medkits <= 0 and tool == "medkit":
			tool = ""                       # letzter Verband verbraucht: zurück zur Waffe
		Events.say("%s versorgt %s (+%d)." % [soldier_name, "sich selbst" if heal_target == self else heal_target.soldier_name, int(amount)], 2.5)


const MEDKIT_MODEL := "l_medkit"


func _end_heal_anim() -> void:
	if model:
		model.play_full("")
		model.set_prop(tool_model_name())   # gewähltes Hilfsmittel bleibt in der Hand, sonst wieder die Waffe
	action_started.emit("heal_end", 0.0)


## Tarnung (Original: Mission_SetUniformDisguise). Gegner erkennen einen
## getarnten Soldaten auf Distanz nicht, solange er nicht kürzlich geschossen hat.
var disguised := false
var last_shot_time := -100.0


## figure: Original-Figur der neuen Uniform (z. B. OrigLevel.character_instance("ge01a")). Trägt der Soldat schon
## eine Original-Figur, bleibt das Modell erhalten und nur die Figur wird getauscht (SoldierModel.attach_orig löst die
## alte samt Kamerapunkten, Hand-Dummy und Waffe); ohne neue Figur bleibt die bisherige Original-Figur.
func put_on_uniform(color: Color, helmet: String, figure: Node3D = null) -> void:
	disguised = true
	uniform_color = color
	helmet_style = helmet
	if model and is_instance_valid(model.orig_figure):
		if figure:
			model.attach_orig(figure)
			if tool != "":
				model.set_prop(tool_model_name())   # Hilfsmittel an die Hand der neuen Figur
		model_changed.emit(model)
		return
	var old := model
	model = SoldierModel.new()
	model.name = "Model"
	add_child(model)
	model.build(self, color, helmet)
	if old:
		old.queue_free()
	_hitbox_rids.clear()
	for hb in model.find_children("*", "Hitbox", true, false):
		_hitbox_rids.append((hb as Hitbox).get_rid())
	if figure:
		model.attach_orig(figure)
	_on_weapon_switched()
	model_changed.emit(model)


func seconds_since_shot() -> float:
	return Time.get_ticks_msec() / 1000.0 - last_shot_time


func toggle_binoculars() -> void:
	if not has_binoculars or vehicle != null and seat_index == 0:
		return
	using_binoculars = not using_binoculars
	trigger = false
	aiming = false


func enter_vehicle(v: Node, seat: int) -> void:
	vehicle = v
	seat_index = seat
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	stance = Stance.CROUCH        # sitzend ≈ hockend (Sichtbarkeit, Trefferfläche)
	stance_request = Stance.CROUCH
	_apply_capsule(Stance.CROUCH)


func exit_vehicle(at: Vector3) -> void:
	vehicle = null
	seat_index = -1
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1) | (1 << 4)
	global_position = at
	velocity = Vector3.ZERO


func _ready() -> void:
	add_to_group("soldiers")
	add_to_group("team_%d" % team)
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1) | (1 << 4)   # Welt, Figuren, Zäune
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	health = max_health
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.3
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	add_child(_shape)
	_apply_capsule(Stance.STAND)
	model = SoldierModel.new()
	model.name = "Model"
	add_child(model)
	model.build(self, uniform_color, helmet_style)
	for hb in find_children("*", "Hitbox", true, false):
		_hitbox_rids.append((hb as Hitbox).get_rid())
	look_yaw = rotation.y
	rotation = Vector3.ZERO
	if not weapons.is_empty():
		_on_weapon_switched()


## Ausrüstung vor oder nach _ready festlegen. ids: Primär, Seitenwaffe, Granate.
func equip(ids: Array) -> void:
	weapons.clear()
	for id in ids:
		weapons.append(Weapon.new(WeaponDB.get_weapon(StringName(id))) if id != "" else null)
	while weapons.size() < WeaponData.SLOT_COUNT:
		weapons.append(null)        # Plätze: Primär, Pistole, Granate, Raketenwerfer, Messer
	current_slot = 0
	while current_slot < weapons.size() and weapons[current_slot] == null:
		current_slot += 1
	if is_node_ready():
		_on_weapon_switched()


func current_weapon() -> Weapon:
	if current_slot < weapons.size():
		return weapons[current_slot]
	return null


func exclude_rids() -> Array[RID]:
	var r: Array[RID] = _hitbox_rids.duplicate()
	r.append(get_rid())
	if model:
		for hb in model.orig_zones:      # Trefferzonen der Original-Figur (an Gelenken, bei Figurwechsel neu)
			if is_instance_valid(hb):
				r.append(hb.get_rid())
	if is_instance_valid(mounted) and mounted.has_method("shot_exclusions"):
		r.append_array(mounted.shot_exclusions())
	if vehicle != null and is_instance_valid(vehicle) and vehicle is CollisionObject3D:
		r.append((vehicle as CollisionObject3D).get_rid())   # Insassen schießen nicht ins eigene Fahrzeug
	return r


func eye_position() -> Vector3:
	var right := Vector3(cos(look_yaw), 0, -sin(look_yaw))
	var h: float = model.head.global_position.y + 0.1 if model else global_position.y + EYE_HEIGHT[stance]
	var p := global_position
	p.y = h
	return p + right * lean * 0.35


func aim_direction() -> Vector3:
	return Vector3(
		-sin(look_yaw) * cos(look_pitch),
		sin(look_pitch),
		-cos(look_yaw) * cos(look_pitch)).normalized()


func forward() -> Vector3:
	return Vector3(-sin(look_yaw), 0, -cos(look_yaw))


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.3


func current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Physik / Bewegung -------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= _gravity * delta
			move_and_slide()
		return
	if net_puppet:
		# Netzfigur: weich zur gemeldeten Position, Animation aus der gemeldeten Geschwindigkeit
		var d := net_target - global_position
		global_position = net_target if d.length() > 4.0 else global_position + d * clampf(12.0 * delta, 0.0, 1.0)
		velocity = net_velocity
		# Schritte der Netzfigur hörbar machen (KI-Soldaten auf dem Server hören Spieler wie im Einzelspiel)
		var spd := Vector2(net_velocity.x, net_velocity.z).length()
		_step_accum += spd * delta
		if spd > 0.4 and _step_accum > 1.6:
			_step_accum = 0.0
			var r := 20.0 if spd > 4.5 else (9.0 if stance == Stance.STAND else 2.5)
			Events.emit_noise(global_position, r, self, team, &"step")
			if stance != Stance.PRONE:
				OrigAudio.play_step(global_position, null, clampf(r / 20.0, 0.35, 1.0))
		_update_stance(delta)
		_update_weapon_timers(delta)
		rotation.y = look_yaw
		model.update_anim(delta, stance, Vector2(net_velocity.x, net_velocity.z).length(), look_pitch, aiming, lean)
		return
	if vehicle != null:
		# im Fahrzeug: Position folgt dem Sitz, Waffen (Mitfahrer) bleiben nutzbar
		if not is_instance_valid(vehicle):
			exit_vehicle(global_position)
		else:
			var t: Transform3D = vehicle.seat_transform(seat_index)
			global_position = t.origin - Vector3.UP * 0.55
			if seat_index == 0:
				trigger = false   # Fahrer schießt nicht
			_update_weapon(delta)
			# Körper in Fahrtrichtung (Fahrzeug vorne = +Z, Soldat vorne = -Z);
			# Mitfahrer, die zielen, drehen sich zum Ziel
			rotation.y = look_yaw if (aiming and seat_index > 0) else vehicle.global_rotation.y + PI
			model.update_anim(delta, Stance.CROUCH, 0.0, look_pitch, aiming, 0.0)
			return
	_update_heal(delta)
	if using_binoculars:
		trigger = false
		aiming = false
	_update_stance(delta)
	_update_movement(delta)
	_update_weapon(delta)
	rotation.y = look_yaw
	# Lehnen an die anderen Rechner (Netzfigur zeigt den Original-Lehnclip)
	var lq := roundf(lean * 4.0) / 4.0
	if lq != _lean_sent:
		_lean_sent = lq
		_net("lean", Vector3(lq, 0, 0), Vector3.ZERO, "")
	model.update_anim(delta, stance, current_speed(), look_pitch, aiming, lean)


func _update_stance(delta: float) -> void:
	_stance_lock = maxf(_stance_lock - delta, 0.0)
	if stance_request == stance or _stance_lock > 0.0:
		return
	if stance_request < stance and not _has_headroom(stance_request):
		stance_request = stance
		return
	var from := stance
	stance = stance_request
	_stance_lock = maxf(STANCE_TIME[stance], STANCE_TIME[from] * 0.8)
	_apply_capsule(stance)
	stance_changed.emit(stance)
	# Original-Figurenklänge (hd2.exe 0x84E938, Ereignisse 4/5/6 aus der Haltungsänderung 0x779F65)
	if alive:
		OrigAudio.human_event(["to_stand", "to_crouch", "to_prone"][stance], global_position, self)


func _apply_capsule(s: int) -> void:
	var h: float = CAPSULE_HEIGHT[s]
	_capsule.height = h
	_capsule.radius = 0.3
	_shape.position = Vector3(0, h * 0.5, 0)


func _has_headroom(s: int) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = CAPSULE_HEIGHT[s]
	params.shape = cap
	params.transform = Transform3D(Basis(), global_position + Vector3(0, cap.height * 0.5 + 0.05, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func stance_transitioning() -> bool:
	return _stance_lock > 0.0


func _update_movement(delta: float) -> void:
	var mode := move_mode
	if mode == MoveMode.RUN and (stamina < 5.0 or aiming or stance != Stance.STAND):
		mode = MoveMode.JOG if is_player_controlled else MoveMode.WALK
	if _climb_t > 0.0:
		_update_climb(delta)
		return
	if mounted != null:
		velocity = Vector3.ZERO      # an der Waffenstellung: nur Drehen und Schießen
		return
	var lvl := water_level()
	if not is_nan(lvl) and global_position.y + 1.1 < lvl:
		_update_swim(delta, lvl, mode)
		return
	swimming = false
	var wish := move_input.limit_length(1.0)
	var speed: float = SPEEDS[stance][mode]
	if aiming:
		speed *= 0.6
	if health < max_health * 0.35:
		speed *= 0.75   # verletzt
	if stance_transitioning() and stance == Stance.PRONE:
		speed = 0.0
	var target := wish * speed
	var accel := 10.0 if is_on_floor() else 2.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * maxf(speed, 1.0))
	velocity.z = move_toward(velocity.z, target.z, accel * delta * maxf(speed, 1.0))
	if is_on_floor() and _jump_request:
		velocity.y = JUMP_VELOCITY
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	_jump_request = false
	var vy_before := velocity.y
	var was_floor := is_on_floor()
	_step_up(delta)
	move_and_slide()
	# Landung nach Sprung/Fall: Schritt auf dem Untergrund (Original-Schrittklang, Lautstärke nach Aufprall – Annahme)
	if not was_floor and is_on_floor() and vy_before < -3.0:
		OrigAudio.play_step(global_position, null, clampf(-vy_before / 6.0, 0.5, 1.0))
	# Mehrspieler-Regel „Verletzung beim Fallen“ (fallingdmg): Aufprall > 9 m/s (≈ 4 m Fallhöhe) verletzt;
	# Schwelle und Stärke sind Annahmen (Originalformel nicht dekodiert). Einzelspieler unverändert.
	if Net.is_online and is_on_floor() and vy_before < -FALL_SAFE_V and (is_player_controlled or Net.is_authority()):
		Net.fall_damage(self, (-vy_before - FALL_SAFE_V) * 15.0)

	# Ausdauer: Rennen kostet, Gewicht der Ausrüstung erhöht den Verbrauch.
	var moving := current_speed() > 0.3
	if moving and mode == MoveMode.RUN and stance == Stance.STAND:
		stamina = maxf(stamina - (10.0 + _carried_weight() * 0.4) * delta * skill_k(skill_endurance, 1.4, 0.7), 0.0)
		train("sprint_s", delta)
	else:
		if moving and stance != Stance.STAND:
			train("sneak_s", delta)
		stamina = minf(stamina + (12.0 if not moving else 6.0) * delta, 100.0)

	# Schrittgeräusche für die Gehör-KI
	if moving and is_on_floor():
		_step_accum += current_speed() * delta
		if _step_accum > 1.6:
			_step_accum = 0.0
			var r: float = STEP_NOISE[stance][mode]
			Events.emit_noise(global_position, r, self, team, &"step")
			_step_count += 1
			# Original: Schritt je Untergrund (tree.klz-Material -> hdmaterials.def +0x20 -> Kat. 0); dazu
			# Ausrüstungsgeräusch je Haltung (hd2.exe-Tabelle Ereignis 7/8/9: o_lwmv/o_mimv/o_frun, 0x7596AA).
			# Lautstärke nach Gangart und Takt der Ausrüstungsgeräusche sind Annahmen.
			if stance == Stance.PRONE:
				OrigAudio.human_event("move_prone", global_position, self)
			else:
				OrigAudio.play_step(global_position, null, clampf(r / 20.0, 0.35, 1.0))
				if _step_count % 2 == 0:
					if stance == Stance.CROUCH:
						OrigAudio.human_event("move_crouch", global_position, self)
					elif mode == MoveMode.RUN:
						OrigAudio.human_event("move_run", global_position, self)


# --- Springen / Klettern (moderne Steuerung: Sprungtaste vor Hindernis = klettern) ---
var _jump_request := false
var _climb_t := 0.0
var _climb_dur := 0.0
var _climb_from := Vector3.ZERO
var _climb_mid := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _step_count := 0


func is_climbing() -> bool:
	return _climb_t > 0.0


## Sprungtaste: aus Hocke/Liegen aufstehen; stehend vor einem Hindernis hinaufklettern bzw.
## darüber steigen, sonst springen.
func jump_or_climb() -> void:
	if stance != Stance.STAND:
		stance_request = Stance.STAND
		return
	if _climb_t > 0.0 or not is_on_floor() or vehicle != null:
		return
	# Original-Leiter in Reichweite: Springen klettert sie hinauf/hinunter (moderne Steuerung)
	for l in get_tree().get_nodes_in_group("ladders"):
		var ln := l as Node3D
		var dxz := Vector2(ln.global_position.x - global_position.x, ln.global_position.z - global_position.z).length()
		if dxz < 1.3 and l.can_interact(self):
			l.climb(self)
			return
	if not try_climb():
		_jump_request = true


func try_climb() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := forward()
	fwd.y = 0.0
	if fwd.length() < 0.1:
		return false
	fwd = fwd.normalized()
	var feet := global_position
	var ex: Array[RID] = exclude_rids()
	# 1. Hindernis vor dem Soldaten (Knie- oder Brusthöhe)
	var hit := {}
	for h in [0.5, 1.2, 1.9]:
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * h, feet + Vector3.UP * h + fwd * 1.0, 1, ex)
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return false
	var wall: Vector3 = hit.position
	wall.y = feet.y
	# 2. Oberkante direkt hinter der Vorderseite
	var top := _ray_down(space, wall + fwd * 0.12, feet.y + CLIMB_MAX + 0.4, feet.y + 0.2, ex)
	if not top.is_finite():
		return false
	var h_top := top.y - feet.y
	if h_top < CLIMB_MIN or h_top > CLIMB_MAX:
		return false
	# 3a. Dünnes Hindernis (Zaun, Mauer): dahinter landen
	var beyond := _ray_down(space, wall + fwd * 0.9, top.y + 0.5, feet.y - 1.5, ex)
	var on_top := _ray_down(space, wall + fwd * 0.45, top.y + 0.5, top.y - 0.25, ex)
	var dest := Vector3.INF
	if on_top.is_finite() and _fits(on_top):
		dest = on_top                                   # breite Kante: hinaufklettern
	elif beyond.is_finite() and h_top <= 1.4 and _fits(beyond):
		dest = beyond                                   # über Zaun/Mauer steigen
	if not dest.is_finite():
		return false
	_climb_from = feet
	_climb_mid = Vector3(feet.x, top.y + 0.15, feet.z) + fwd * 0.25
	_climb_to = dest + Vector3.UP * 0.02
	_climb_dur = 0.35 + h_top * 0.35
	_climb_t = _climb_dur
	_climb_ladder = false
	velocity = Vector3.ZERO
	Events.emit_noise(global_position, 6.0, self, team, &"climb")
	# Original-Figurenklänge: Ereignis 17 „o_juover“ (über Zaun/Mauer), 13–15 „o_over…“ (Klettern; Zuordnung
	# der drei Varianten nach Höhe = Annahme)
	var ev: String = "jump_over" if dest == beyond else ("climb_over" if h_top < 1.0 else ("climb_over2" if h_top < 1.7 else "climb_over3"))
	OrigAudio.human_event(ev, global_position, self)
	return true


## Step-up (CharacterBody3D kennt keinen): Stufenkante vor den Füßen → anheben, falls darüber frei und dahinter
## begehbarer Boden höchstens STEP_HEIGHT höher liegt; die Bewegung übernimmt danach move_and_slide.
func _step_up(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if velocity.y > 0.5 or h.length() < 0.2:
		return
	var xf := global_transform
	# auf dem Boden oder an Kanten hängend (Rampe über Stufen: Kontakte mit steilen Kantennormalen)
	if not is_on_floor() and not test_move(xf, Vector3.DOWN * 0.08):
		return
	var dir := h.normalized()
	var hit := KinematicCollision3D.new()
	if not test_move(xf, dir * maxf(h.length() * delta, 0.12), hit) or hit.get_normal().y > cos(floor_max_angle):
		return                                  # frei oder begehbare Schräge
	var raised := xf
	var up_hit := KinematicCollision3D.new()
	raised.origin += up_hit.get_travel() if test_move(xf, Vector3.UP * STEP_HEIGHT, up_hit) else Vector3.UP * STEP_HEIGHT
	if raised.origin.y - xf.origin.y < 0.1:
		return                                  # keine Kopffreiheit
	var space := get_world_3d().direct_space_state
	for dist in [0.12, 0.25, 0.4]:
		var probe: Vector3 = dir * maxf(h.length() * delta, dist)
		if test_move(raised, probe):
			return                              # Wand statt Stufe
		var ahead := raised.translated(probe)
		var down := KinematicCollision3D.new()
		if not test_move(ahead, Vector3.DOWN * (STEP_HEIGHT + 0.05), down):
			continue
		var land := ahead.origin + down.get_travel()
		# Neigung der Trittfläche per Strahl (Kapselkontakt an Kanten liefert schräge Normalen)
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.1, land + Vector3.DOWN * 0.3,
			collision_mask, [get_rid()]))
		var ny: float = ray.normal.y if not ray.is_empty() else down.get_normal().y
		var rise := land.y - xf.origin.y
		if ny >= cos(floor_max_angle) and rise > 0.02 and rise <= STEP_HEIGHT:
			global_position.y += rise + 0.01
			velocity.y = minf(velocity.y, 0.0)
			return


func _ray_down(space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float, to_y: float, ex: Array[RID]) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.z), Vector3(at.x, to_y, at.z), 1, ex)
	var r := space.intersect_ray(q)
	return r.position if not r.is_empty() else Vector3.INF


func _fits(at: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = CAPSULE_HEIGHT[Stance.STAND] - 0.1
	params.shape = cap
	params.transform = Transform3D(Basis(), at + Vector3(0, cap.height * 0.5 + 0.08, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


## --- Schwimmen / Tauchen (Original: NORWAY Magnetminen unter Wasser, TUTORIAL Tauchbecken; Tauchgerät
## „akvalung“ = Gegenstand 231). Steuerung (moderne Vereinfachung): in Blickrichtung schwimmen/tauchen,
## Springen = auftauchen; ohne Eingabe treibt der Soldat zur Oberfläche. Luft 30 s ohne Tauchgerät.
const AIR_MAX := 30.0
var swimming := false
var air := AIR_MAX
var _swim_snd := 0.0
var _mission_ref: Node


func water_level() -> float:
	if not is_instance_valid(_mission_ref):
		_mission_ref = Game.current_mission()
	if _mission_ref and _mission_ref.has_method("water_level_at"):
		return _mission_ref.water_level_at(global_position)
	return NAN


func head_under_water() -> bool:
	var lvl := water_level()
	return not is_nan(lvl) and global_position.y + 1.45 < lvl


func _update_swim(delta: float, lvl: float, mode: int) -> void:
	swimming = true
	stance_request = Stance.STAND
	var wish := move_input.limit_length(1.0)
	var speed := 2.2 if mode == MoveMode.RUN else 1.4
	var v := wish * speed
	if wish.length() > 0.1:
		v.y = sin(look_pitch) * speed      # tauchen/aufsteigen in Blickrichtung
	else:
		v.y = 0.5                          # Auftrieb
	if _jump_request:
		v.y = 1.6
	_jump_request = false
	# an der Oberfläche schwimmen (Kopf über Wasser)
	if global_position.y + 1.4 > lvl and v.y > 0.0:
		v.y = 0.0
	velocity = velocity.lerp(v, clampf(4.0 * delta, 0.0, 1.0))
	move_and_slide()
	trigger = false
	aiming = false
	# Original-Figurenklänge: Schwimmen (Ereignis 0 p_swim) bzw. Tauchen (1 p_swuw), Ertrinken (18 drown);
	# Takt 1,2 s = Annahme
	_swim_snd -= delta
	var under := global_position.y + 1.45 < lvl
	if _swim_snd <= 0.0 and (wish.length() > 0.1 or (under and air <= 0.0)):
		_swim_snd = 1.2
		var ev := "swim"
		if under and air <= 0.0:
			ev = "drown"
		elif under:
			ev = "swim_underwater"
		OrigAudio.human_event(ev, global_position, self)
	if global_position.y + 1.45 < lvl and not get_meta("orig_items", []).has(231):
		air -= delta
		if air <= 0.0 and alive:
			health -= 10.0 * delta     # ertrinken
			if health <= 0.0:
				die(null)
	else:
		air = minf(air + 6.0 * delta, AIR_MAX)


## Kletterbewegung entlang eines Pfades (z. B. Original-Leitern): erst zu mid (60 %), dann zu to
func start_path_climb(from: Vector3, mid: Vector3, to: Vector3, duration: float) -> void:
	_climb_from = from
	_climb_mid = mid
	_climb_to = to
	_climb_dur = maxf(duration, 0.2)
	_climb_t = _climb_dur
	# Leiter: überwiegend senkrechter Weg (Original-Leiter, Kletterstellen) -> Leiteranimation #LEZUP/#LEZDWN
	_climb_ladder = absf(to.y - from.y) > 1.2 and Vector2(to.x - from.x, to.z - from.z).length() < absf(to.y - from.y)
	velocity = Vector3.ZERO
	Events.emit_noise(global_position, 6.0, self, team, &"climb")


var _climb_ladder := false


## Laufende Kletterbewegung für die Animation (BodyAnim): ladder, dy (Höhe), duration, left (Restzeit).
func climb_info() -> Dictionary:
	var dy := _climb_to.y - _climb_from.y
	if not _climb_ladder:
		dy = maxf(_climb_mid.y - 0.15 - _climb_from.y, 0.0)    # Hindernishöhe (try_climb: mid = Oberkante + 0,15)
	return {"ladder": _climb_ladder, "dy": dy, "duration": _climb_dur, "left": _climb_t}


func _update_climb(delta: float) -> void:
	_climb_t = maxf(_climb_t - delta, 0.0)
	var k := 1.0 - _climb_t / _climb_dur
	# erst hoch (60 %), dann nach vorn auf/über die Kante
	if k < 0.6:
		global_position = _climb_from.lerp(_climb_mid, k / 0.6)
	else:
		global_position = _climb_mid.lerp(_climb_to, (k - 0.6) / 0.4)
	velocity = Vector3.ZERO


func _carried_weight() -> float:
	var w := 0.0
	for wpn in weapons:
		if wpn:
			w += wpn.data.weight
	return w


# --- Waffen ------------------------------------------------------------------

func _update_weapon_timers(delta: float) -> void:
	grenade_cooldown = maxf(grenade_cooldown - delta, 0.0)
	if _stab_left >= 0.0:
		_stab_left -= delta
		if _stab_left < 0.0:
			_melee_hit()            # Stichbild erreicht (auch Netzfiguren auf dem Server)
	if net_puppet:
		_melee_cd = maxf(_melee_cd - delta, 0.0)
	for w in weapons:
		if w:
			w.tick(delta)
	if _throw_left > 0.0:
		_throw_left -= delta
		if _throw_left <= 0.0:
			_throw_left = 0.0
			if alive:
				_release_grenade()


func _update_weapon(delta: float) -> void:
	_update_weapon_timers(delta)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if is_throwing():
		return                      # Wurfanimation läuft: Waffe ruht bis die Granate die Hand verlassen hat
	if tool != "":
		if trigger and not _tool_trigger_prev:
			use_tool()
		_tool_trigger_prev = trigger
		return
	var w := current_weapon()
	if w == null:
		return
	var can_fire := not stance_transitioning() and not (move_mode == MoveMode.RUN and is_moving() and not aiming)
	if w.data.action == WeaponData.Action.MELEE:
		# Klick wird gemerkt (auch während der Erholung), gehaltene Taste sticht weiter
		if trigger and not _tool_trigger_prev:
			_stab_queued = true
		if (_stab_queued or trigger) and _melee_cd <= 0.0 and _stab_left < 0.0:
			_stab_queued = false
			_melee(w)
		_tool_trigger_prev = trigger
		return
	if w.data.slot == WeaponData.Slot.GRENADE:
		if trigger and can_fire and grenade_cooldown <= 0.0 and w.total_ammo() > 0:
			throw_grenade(w)
		return
	# Abzug bei leerem Magazin: Original „All Empty“ (Kat. 3/4)
	if trigger and not _trigger_prev and can_fire and w.in_mag <= 0 and not w.is_reloading():
		OrigAudio.play_weapon(w.data, "empty", global_position, self, team)
	_trigger_prev = trigger
	if w.trigger(trigger and can_fire):
		_fire_shot(w)


func _fire_shot(w: Weapon) -> void:
	var origin := eye_position()
	if is_instance_valid(mounted) and mounted.has_method("shot_origin"):
		origin = mounted.shot_origin()
	var dir := aim_direction()
	if has_aim_point:
		var to := aim_point - origin
		if to.length() > 1.0:
			dir = to.normalized()
	var spread_deg := current_spread()
	dir = _apply_spread(dir, spread_deg)
	if w.data.action == WeaponData.Action.ROCKET:
		_fire_rocket(w, origin, dir)
		_net("rocket", origin + dir * 1.0, dir * w.data.muzzle_velocity, String(w.data.id))
	else:
		Ballistics.fire(self, origin, dir, w.data, exclude_rids(), team)
		_net("shot", origin, dir, String(w.data.id))
	var muzzle := origin + dir * 0.9
	if is_instance_valid(mounted) and mounted.has_method("shot_origin"):
		muzzle = origin                     # Waffenstellung: Mündungsfeuer an der Mündung des Stellungsmodells
	elif model and model.weapon_socket:
		muzzle = model.muzzle_point(dir, w.data.model_length)
	Effects.muzzle_flash(muzzle, dir)
	# Original-Schussklang der Waffe (items.sav +u4 -> Kat. 2), beim letzten Schuss zusätzlich +u17
	# („(LS)“: Garand-Ping, P08/Colt/Tokarev/Taisho); Hülsen auf hartem Boden Kat. 5/0 (Zuordnung = Annahme)
	OrigAudio.play_weapon(w.data, "shoot", muzzle, null, team)
	if w.in_mag == 0:
		OrigAudio.play_weapon(w.data, "last_shot", muzzle, null, team)
	if w.data.action != WeaponData.Action.ROCKET:
		get_tree().create_timer(0.45, false).timeout.connect(_shell_sound)
	Events.emit_noise(global_position, w.data.noise_radius, self, team, &"gunshot")
	# Rückstoß: liegend mit Zweibein (Bren) / aufgelegt deutlich weniger
	var k := 1.0
	if stance == Stance.CROUCH:
		k = 0.8
	elif stance == Stance.PRONE:
		k = 0.55
	_recoil += Vector2(w.data.recoil_pitch * k, randf_range(-1.0, 1.0) * w.data.recoil_yaw * k)
	last_shot_time = Time.get_ticks_msec() / 1000.0
	shot_fired.emit(w)
	if w.data.action == WeaponData.Action.BOLT:
		get_tree().create_timer(0.35, false).timeout.connect(_bolt_sound)


## Raketenwerfer: Geschoss mit Aufschlagzünder (Grenade.impact)
func _fire_rocket(w: Weapon, origin: Vector3, dir: Vector3) -> void:
	var g := Grenade.new()
	g.data = w.data
	g.thrower = self
	g.team = team
	g.impact = true
	get_parent().add_child(g)
	g.global_position = origin + dir * 1.0
	g.linear_velocity = dir * w.data.muzzle_velocity
	g.add_collision_exception_with(self)
	if vehicle != null and is_instance_valid(vehicle) and vehicle is PhysicsBody3D:
		g.add_collision_exception_with(vehicle)    # Bordkanone: Geschoss trifft nicht das eigene Fahrzeug
	# Panzerfaust: im Original Einwegwaffe; Vorgabe Auftraggeber: das Rohr bleibt und wird mit Raketen-Munition
	# (WeaponDB.PANZERFAUST_AMMO) nachgeladen – auch ohne Vorrat, damit aufgenommene Raketen nutzbar sind.


## --- Messer (Original: Haltesatz „hand“ in TABLES\anim.sav, +0xF40 „(bodnuti“ stehend / „(bodnutidrep“ hockend,
## +0xFA0 von hinten „!podrezSTa“ stehend (Ganzkörper) / „(podrezKL02“ hockend; Opfer „!smrtpodrez“).
## Vorgabe Auftraggeber „schneller“: Clips mit KNIFE_RATE statt Original-Tempo 0,9/1,0, Treffer zum Stichbild
## (5DS-Ereignis „t“), kurze Erholung, Klick während der Erholung wird gemerkt, gehaltene Taste sticht weiter.
## Ziel wird zum Stichzeitpunkt bestimmt (bis KNIFE_RANGE vor dem Soldaten, ganz nah in jeder Richtung);
## von hinten tödlich. Mehrspieler: Treffer nur auf dem Server (Soldier.apply_hit), Ziel-Hinweis des Clients mit
## Lagetoleranz (Netzfiguren hinken ~0,1 s hinterher).
const KNIFE_RATE := 2.5
const KNIFE_RECOVER := 0.3          ## s nach dem Stich bis zum nächsten (vorher feste Sperre 60/rpm = 0,75 s)
const KNIFE_RANGE := 1.8
const KNIFE_NET_TOLERANCE := 0.9    ## zusätzliche Reichweite (m) für den Ziel-Hinweis eines Clients auf dem Server
var _stab_left := -1.0              ## > 0: Zeit bis zum Treffer des laufenden Stichs
var _stab_weapon: Weapon
var _stab_hint: Node3D
var _stab_hint_net := false
var _stab_queued := false
var _stab_started_ms := 0
## Tests/Messung: letzte Stiche {start_ms, hit_ms, target, behind, clip}
var knife_log: Array = []


## Bestes Messerziel: nah (≤ 0,8 m, Kapseln berühren sich bei 0,6 m) in jeder Richtung, sonst bis KNIFE_RANGE (+extra) im Kegel ±55° vor dem Soldaten.
func _knife_target(extra: float = 0.0) -> Node3D:
	var fwd := forward()
	var best: Node3D = null
	var best_d := KNIFE_RANGE + extra
	for n in get_tree().get_nodes_in_group("soldiers") + get_tree().get_nodes_in_group("dogs"):
		var t := n as Node3D
		if not _knife_valid(t):
			continue
		var to := t.global_position - global_position
		if absf(to.y) > 1.6:
			continue
		to.y = 0.0
		var d := to.length()
		if d < best_d and (d < 0.8 + extra * 0.5 or fwd.angle_to(to) < 0.96):
			best = t
			best_d = d
	return best


func _knife_valid(t: Node3D) -> bool:
	if t == null or t == self or not is_instance_valid(t) or not t.is_inside_tree():
		return false
	if t is Soldier and (not (t as Soldier).alive or (t as Soldier).team == team):
		return false
	return true


func _knife_behind(t: Node3D) -> bool:
	return t is Soldier and (t as Soldier).forward().dot((t.global_position - global_position).normalized()) > 0.4


## Stich beginnen (Animation, Klang); der Treffer folgt zum Stichbild (_melee_hit). hint: Ziel-Vorschlag (Client).
func _melee(w: Weapon, hint: Node3D = null, hint_from_net := false) -> void:
	var target := hint if _knife_valid(hint) else _knife_target()
	var behind := _knife_behind(target)
	var crouched := stance != Stance.STAND
	var key := ("knife_back_kl" if crouched else "knife_back_st") if behind else ("knife_dr" if crouched else "knife_st")
	var c := BodyAnim.upper(key) if key != "knife_back_st" else BodyAnim.full(key)
	var ln := BodyAnim.clip_length(c)
	var t_hit := BodyAnim.event_time(c, "t")
	if ln <= 0.0 or t_hit < 0.0:
		ln = 0.5
		t_hit = 0.15 * KNIFE_RATE
	var dur := ln / KNIFE_RATE
	_stab_left = t_hit / KNIFE_RATE
	_stab_weapon = w
	_stab_hint = target
	_stab_hint_net = hint_from_net
	_stab_started_ms = Time.get_ticks_msec()
	_melee_cd = _stab_left + KNIFE_RECOVER
	if model:
		if key == "knife_back_st":
			model.play_body(key, dur, false, "knife")       # Ganzkörper (Schritt an das Opfer), Hand mit Messer
		elif c != "":
			model.play_action(c, dur, 0.06)
	var hid: int = int(target.get_meta("net_peer", 0)) if target else 0
	var has_hint: float = 1.0 if target and target.has_meta("net_peer") else 0.0
	_net("melee", Vector3(hid, has_hint, 0), Vector3(look_yaw, 0, 0), "")
	Events.emit_noise(global_position, w.data.noise_radius, self, team, &"melee")
	last_shot_time = Time.get_ticks_msec() / 1000.0
	shot_fired.emit(w)
	OrigAudio.play_weapon(w.data, "shoot", global_position + Vector3.UP, self, team)   # Kat. 2 „G/B Knife“
	knife_log.append({"start_ms": _stab_started_ms, "hit_ms": -1, "target": "", "behind": behind, "clip": c})
	if knife_log.size() > 16:
		knife_log.pop_front()


## Nur Darstellung (Netzfigur auf Clients): Stichanimation ohne Trefferwertung.
func melee_visual() -> void:
	var t := _knife_target()
	var behind := _knife_behind(t)
	var crouched := stance != Stance.STAND
	var key := ("knife_back_kl" if crouched else "knife_back_st") if behind else ("knife_dr" if crouched else "knife_st")
	var c := BodyAnim.upper(key) if key != "knife_back_st" else BodyAnim.full(key)
	var dur := BodyAnim.clip_length(c) / KNIFE_RATE
	if model and dur > 0.0:
		if key == "knife_back_st":
			model.play_body(key, dur, false, "knife")
		else:
			model.play_action(c, dur, 0.06)
	var w: Weapon = current_weapon()
	if w and w.data.action == WeaponData.Action.MELEE:
		OrigAudio.play_weapon(w.data, "shoot", global_position + Vector3.UP, self, team)


## Stichbild erreicht: Ziel jetzt bestimmen (Hinweis bevorzugt, sonst Suche) und Schaden anwenden.
func _melee_hit() -> void:
	var w := _stab_weapon
	_stab_weapon = null
	if w == null or not alive:
		return
	var best: Node3D = null
	var tol := KNIFE_NET_TOLERANCE if _stab_hint_net else 0.25
	if _knife_valid(_stab_hint):
		var to := _stab_hint.global_position - global_position
		if absf(to.y) <= 1.6 and Vector2(to.x, to.z).length() <= KNIFE_RANGE + tol:
			best = _stab_hint
	if best == null:
		best = _knife_target(tol if _stab_hint_net else 0.0)
	_stab_hint = null
	if not knife_log.is_empty():
		(knife_log[-1] as Dictionary)["hit_ms"] = Time.get_ticks_msec()
		(knife_log[-1] as Dictionary)["target"] = String(best.name) if best else ""
	if best == null:
		return
	var fwd := forward()
	if best is Soldier:
		var ts := best as Soldier
		var behind := _knife_behind(ts)
		# Treffer: Kat. 4 „Knife CUT“ (von hinten) bzw. „Knife JAB“ (Zuordnung = Annahme)
		OrigAudio.play_group(OrigAudio.CAT_HIT, OrigAudio.HIT_KNIFE_CUT if behind else OrigAudio.HIT_KNIFE_JAB,
			ts.global_position + Vector3.UP * 1.2)
		if behind:
			ts.set_meta("death_kind", "throat")     # Opfer: „!smrtpodrez“ (Kehlschnitt)
		ts.apply_hit(w.data.damage * (3.0 if behind else 1.0), &"torso", self, fwd)
		if ts.alive:
			ts.remove_meta("death_kind")
	elif best.has_method("on_bullet_hit"):
		best.on_bullet_hit(w.data.damage, self)


# --- Auswahl (Mausrad + Linksklick) und Hilfsmittel -------------------------------

## Wählbare Einträge in fester Reihenfolge: Primärwaffe, Raketenwerfer, Pistole, Messer, Granate,
## Sprengstoff, Mine, Erste Hilfe, Fernglas. Jeder Eintrag: {key, label, count}
func selection_entries() -> Array:
	var out: Array = []
	var slots := [[WeaponData.Slot.PRIMARY, "Primärwaffe"], [WeaponData.Slot.LAUNCHER, "Raketenwerfer"],
		[WeaponData.Slot.SIDEARM, "Pistole"], [WeaponData.Slot.MELEE, "Messer"], [WeaponData.Slot.GRENADE, "Granate"]]
	for e in slots:
		var i: int = e[0]
		if i < weapons.size() and weapons[i] != null and (i != WeaponData.Slot.GRENADE or weapons[i].total_ammo() > 0):
			out.append({"key": "slot:%d" % i, "label": "%s – %s" % [e[1], weapons[i].data.display_name],
				"count": weapons[i].total_ammo() if weapons[i].data.action != WeaponData.Action.MELEE else -1})
	if explosives > 0:
		out.append({"key": "explosive", "label": "Sprengstoff", "count": explosives})
	if mines > 0:
		out.append({"key": "mine", "label": "Mine", "count": mines})
	if medkits > 0:
		out.append({"key": "medkit", "label": "Erste Hilfe", "count": medkits})
	if has_binoculars:
		out.append({"key": "binoculars", "label": "Fernglas", "count": -1})
	return out


func selected_key() -> String:
	if tool != "":
		return tool
	return "slot:%d" % current_slot


func apply_selection(key: String) -> void:
	if using_binoculars and key != "binoculars":
		toggle_binoculars()
	if key.begins_with("slot:"):
		var slot := int(key.substr(5))
		if tool != "" and slot != current_slot:
			_tool_quiet = true          # select_slot zieht gleich die neue Waffe
			tool = ""
			_tool_quiet = false
		if not select_slot(slot):
			weapon_changed.emit(current_weapon())
		return
	tool = key
	_tool_trigger_prev = true      # der auswählende Klick löst nicht sofort aus
	if key == "binoculars" and not using_binoculars:
		toggle_binoculars()


## Hilfsmittel benutzen (Linksklick)
func use_tool() -> void:
	match tool:
		"medkit":
			if medkits <= 0:
				Events.say("Kein Verbandskasten mehr.", 1.5)
			elif not start_heal(get_tree().get_nodes_in_group("team_%d" % team)):
				Events.say("Niemand in Reichweite ist verwundet.", 1.5)
		"binoculars":
			toggle_binoculars()
			if not using_binoculars:
				tool = ""
		"explosive", "mine":
			_place_charge(tool)


## Benutzen-Animation der Original-Figur (anim.sav): Tür „!dvereST02/!dvereKL03“, Aufheben/Durchsuchen
## „(uchprestoj4/(uchpredrep“, Sprengsatz/Entschärfen kniend „!manipulm“, Fesseln „!svazuje1“; sonst Hand ausstrecken
## wie an der Tür (Schalter, Funkgerät, Kisten). Fahrzeuge, Leitern, Stellungen haben eigene Bewegungen.
func play_use_anim(it: Node) -> void:
	if model == null or not alive or net_puppet or vehicle != null:
		return
	if it is OrigInteractive.OrigLadder or it is OrigInteractive.OrigEmplacement or it is Vehicle.VehicleEntry:
		return
	var crouched := stance != Stance.STAND
	var key := "door_kl" if crouched else "door_st"
	var dur := 0.8
	if it is Pickups.Item or it is Pickups.AmmoCrate or it is Pickups.Loot or it is OrigInteractive.OrigWorldItem \
			or it is OrigInteractive.OrigCrate:
		key = "pickup_dr" if crouched else "pickup_st"
	elif it is OrigInteractive.OrigExplosive or it is PlacedCharge.DefuseSpot or it is ChargeSite:
		key = "manip_kl"
		dur = 1.6
	elif it is EnemyBrain.CaptureAction:
		key = "tying"
		dur = 1.4
	model.play_body(key, dur, true, "use")


## Sprengstoff (Zeitzünder 10 s) bzw. Mine (Annäherungszünder) vor dem Soldaten ablegen. An einem
## Original-Sprengplatz in Reichweite wird stattdessen dessen Aktion ausgeführt.
func _place_charge(kind: String) -> void:
	if kind == "explosive":
		for n in get_tree().get_nodes_in_group("interactables"):
			if n is OrigInteractive.OrigExplosive and n.can_interact(self) \
					and (n as Node3D).global_position.distance_to(global_position) < 2.5:
				n.interact(self)
				return
	var have := explosives if kind == "explosive" else mines
	if have <= 0:
		tool = ""
		return
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_BOMB, global_position, self)   # „Player01 Bomb manipulation“
	var c := PlacedCharge.new()
	c.kind = kind
	c.owner_soldier = self
	c.team = team
	get_parent().add_child(c)
	# auf den Boden vor dem Soldaten legen (Hang: nicht in den Boden, nicht in der Luft)
	var at := global_position + forward() * 0.7
	var gq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at + Vector3.DOWN * 1.5, 1, exclude_rids())
	var gh := get_world_3d().direct_space_state.intersect_ray(gq)
	if not gh.is_empty():
		at = gh.position
	c.global_position = at + Vector3.UP * 0.02
	_net(kind, c.global_position, Vector3.ZERO, "")
	if kind == "explosive":
		explosives -= 1
		_consume_orig([68, 67])
		Events.say("%s: Sprengladung gelegt – 10 s!" % soldier_name, 2.5)
	else:
		mines -= 1
		_consume_orig([70, 71])
		Events.say("%s: Mine gelegt." % soldier_name, 2.0)
	action_started.emit("tool_use", 0.8)    # 1. Person: Ablegen (FPV „shot“, z. B. FPVAntimanShot)
	if model:
		model.play_body("manip_kl", 1.0, true, "use")   # 3. Person: kniend ablegen (anim.sav „!manipulm“)
	if (explosives if kind == "explosive" else mines) <= 0:
		tool = ""


func _consume_orig(ids: Array) -> void:
	var inv: Array = get_meta("orig_items", [])
	for id in ids:
		if inv.has(id):
			inv.erase(id)
			break
	set_meta("orig_items", inv)


## Taste G: Granate sofort werfen, ohne die Waffe zu wechseln
func quick_grenade() -> bool:
	var g: Weapon = weapons[WeaponData.Slot.GRENADE] if weapons.size() > WeaponData.Slot.GRENADE else null
	if g == null or g.total_ammo() <= 0 or grenade_cooldown > 0.0 or vehicle != null or not alive or is_throwing():
		return false
	throw_grenade(g)
	return true


## Repetieren (items.sav +u18 -> Kat. 3 „… (Mauser)“), nach dem Schuss eines Repetierers
func _bolt_sound() -> void:
	var w := current_weapon()
	if alive and w:
		OrigAudio.play_weapon(w.data, "bolt", global_position, self, team)


## Hülsen: Kat. 5/0 „Pistol Bullets Hard“ nur auf hartem Untergrund (Stein, Beton, Asphalt, Holz, Metall, Eis);
## „Pistol Bullets Soft/Liquid“ sind im Original leer (Annahme: auf weichem Boden still)
const HARD_STEP_GROUPS := [3, 4, 5, 10, 11, 26, 31, 33, 37]
var _shell_t := 0.0


func _shell_sound() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not alive or now - _shell_t < 0.25:
		return
	_shell_t = now
	var m := OrigAudio.floor_material(global_position)
	if HARD_STEP_GROUPS.has(int(OrigAudio.material_info(m).get("step_sound", -1))):
		OrigAudio.play_group(OrigAudio.CAT_FALL, OrigAudio.FALL_SHELL_HARD, global_position + forward() * 0.3 + Vector3.UP * 0.1)


## Aktuelle Streuung (Halbwinkel in Grad) aus Waffe, Haltung, Bewegung, Ausdauer.
func current_spread() -> float:
	var w := current_weapon()
	if w == null:
		return 0.0
	var base := w.data.spread_aim if aiming else w.data.spread_hip
	var stance_k := [1.0, 0.75, 0.5][stance] as float
	var move_k := clampf(current_speed() / 2.0, 0.0, 1.0) * w.data.spread_move_add
	var fatigue := (1.0 - stamina / 100.0) * (0.6 if aiming else 0.3)
	var skill := skill_k(skill_shooting, 1.5, 0.7)
	return (base * stance_k + move_k + w.bloom * (0.6 if aiming else 1.0) + fatigue) * skill + extra_spread


static func _apply_spread(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return dir
	# Gleichverteilung in der Kreisscheibe des Streukegels
	var r := deg_to_rad(spread_deg) * sqrt(randf())
	var a := randf() * TAU
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	return (dir + right * tan(r) * cos(a) + up2 * tan(r) * sin(a)).normalized()


## Vom Controller abgeholter Rückstoß (Grad), danach zurückgesetzt.
func consume_recoil() -> Vector2:
	var r := _recoil
	_recoil = Vector2.ZERO
	return r


func reload() -> bool:
	var w := current_weapon()
	if is_throwing() or heal_time_left > 0.0:
		return false
	if w and w.start_reload():
		OrigAudio.play_weapon(w.data, "reload", global_position, self, team)    # items.sav +u10 -> Kat. 3
		# Original-Nachladeanimation (TABLES\anim.sav, Satz +0x1300, je Haltung), Dauer = Nachladezeit
		play_weapon_action("reload", w.reload_left)
		return true
	return false


## Waffenaktion animieren: 3. Person über die Oberkörperschicht der Figur (Clip aus anim.sav), 1. Person über
## action_started (CameraRig spielt die FPV-Animation aus FpvAnims.sav). duration < 0 = Cliplänge.
func play_weapon_action(kind: String, duration: float = -1.0) -> void:
	var w := current_weapon()
	if w == null:
		return
	var clip := OrigWeapons.action_clip(w.data, team, kind, stance)
	if duration < 0.0:
		duration = float(OrigWeapons.clip_info(clip).get("length", 0.0))
	if model and clip != "":
		model.play_action(clip, duration)
	action_started.emit(kind, duration)


## --- Granatwurf mit Original-Wurfanimation (anim.sav +0x1240 „hod*“; Granate verlässt die Hand zum
## Auslösezeitpunkt des Clips = größte Handgeschwindigkeit, export_weapons.py [P]) ---
var _throw_left := 0.0
var _throw_data: WeaponData
var _throw_velocity := Vector3.INF
var _throw_weapon: Weapon


func is_throwing() -> bool:
	return _throw_left > 0.0


func select_slot(slot: int) -> bool:
	if tool != "" and slot == current_slot and slot < weapons.size() and weapons[slot] != null:
		if using_binoculars:
			toggle_binoculars()
		tool = ""                      # vom Hilfsmittel zurück zur Waffe (Setter: Ziehen)
		return true
	if slot < 0 or slot >= weapons.size() or weapons[slot] == null or slot == current_slot:
		return false
	if slot == WeaponData.Slot.GRENADE and weapons[slot].total_ammo() <= 0:
		return false
	if using_binoculars:
		toggle_binoculars()
	_tool_quiet = true                 # Waffe wird unten gewechselt und gezogen
	tool = ""
	_tool_quiet = false
	var w := current_weapon()
	if w:
		w.cancel_reload()
	if model:
		model.stop_action()
	current_slot = slot
	_on_weapon_switched()
	play_weapon_action("draw")          # Ziehen (anim.sav +0x220 „vyt*“)
	return true


func cycle_weapon(dir: int) -> void:
	for i in range(1, weapons.size() + 1):
		var s := posmod(current_slot + dir * i, weapons.size())
		if select_slot(s):
			return


func _on_weapon_switched() -> void:
	var w := current_weapon()
	if model:
		model.set_weapon(w.data if w else null)
	if w:
		w.cooldown = maxf(w.cooldown, 0.5)  # Waffe ziehen
		OrigAudio.play_weapon(w.data, "armed", global_position, self, team)    # items.sav Basis+0x78 -> Kat. 3
	weapon_changed.emit(w)


## override_velocity: von der KI berechnete Abwurfgeschwindigkeit (sonst Blickrichtung).
func throw_grenade(w: Weapon, override_velocity := Vector3.INF) -> void:
	if is_throwing():
		return
	if w.in_mag <= 0:
		if w.reserve <= 0:
			return
		w.reserve -= 1
		w.in_mag = 1
	w.in_mag -= 1
	var cw := current_weapon()
	if cw:
		cw.cancel_reload()
	# Wurfclip des gehaltenen Satzes: im Stand Ganzkörperwurf, in Bewegung nur Oberkörper (…vP)
	var src: WeaponData = cw.data if cw else w.data
	var clip := OrigWeapons.action_clip(src, team, "throw_move" if is_moving() else "throw", stance)
	var ci := OrigWeapons.clip_info(clip)
	var length := float(ci.get("length", 0.0))
	var release := float(ci.get("release", 0.0))
	grenade_cooldown = maxf(1.2, length)
	_throw_data = w.data
	_throw_weapon = w
	_throw_velocity = override_velocity
	if model == null or clip == "" or release <= 0.0 or not model.play_action(clip, length):
		_release_grenade()
		return
	_throw_left = release
	if cw:
		cw.cooldown = maxf(cw.cooldown, length)
	action_started.emit("throw", length)


## Granate verlässt die Hand (Auslösezeitpunkt der Wurfanimation).
func _release_grenade() -> void:
	var data := _throw_data
	if data == null:
		return
	_throw_data = null
	var g := Grenade.new()
	g.data = data
	g.thrower = self
	g.team = team
	get_parent().add_child(g)
	var origin := eye_position() + aim_direction() * 0.5
	g.global_position = origin
	var dir := aim_direction()
	dir.y += 0.25
	g.linear_velocity = dir.normalized() * data.throw_speed * (0.7 if stance == Stance.PRONE else 1.0)
	if _throw_velocity.is_finite():
		g.linear_velocity = _throw_velocity
	g.add_collision_exception_with(self)
	OrigAudio.play_weapon(data, "shoot", origin, null, team)    # Wurf: items.sav +u4 -> Kat. 2 „… Throw“
	_net("grenade", origin, g.linear_velocity, String(data.id))
	grenade_released.emit(g)
	var w := _throw_weapon
	_throw_weapon = null
	if w and w.total_ammo() <= 0 and current_slot == WeaponData.Slot.GRENADE and weapons[current_slot] == w:
		cycle_weapon(-1)


# --- Schaden -----------------------------------------------------------------

func apply_hit(amount: float, zone: StringName, attacker: Node, direction: Vector3) -> void:
	if not alive:
		return
	if Net.is_online:
		if not Net.is_authority():
			return       # Mehrspieler: Schaden berechnet nur der Server (Gesundheit kommt per Net._hp)
		if has_meta("protect_until") and Time.get_ticks_msec() < int(get_meta("protect_until")):
			return       # Spawnschutz (Original: einige Sekunden nach dem Erscheinen)
		if attacker is Soldier and attacker != self and (attacker as Soldier).team == team and not Net.friendly_fire():
			return       # Freund-Feind-Schaden aus
		set_meta("last_zone", String(zone))
		if attacker is Soldier and attacker != self and (attacker as Soldier).team == team and Net.team_mode():
			Net.inverse_damage(attacker as Soldier, amount)     # Server-Regel „Umgekehrter Schaden“
	# Zonen-/Helmfaktoren rechnet der Aufrufer (Ballistics → WeaponDB.zone_damage, hd2.exe 0x5A1C90)
	health -= amount
	last_attacker = attacker
	damaged.emit(amount, zone)
	Events.soldier_damaged.emit(self, amount, zone, attacker)
	if health <= 0.0:
		die(attacker, direction)
	elif amount >= 1.0:
		# Schmerzlaut des Sprachsatzes (speech.set Ereignis 117 „Injury/Ouch“), je Sprecher höchstens alle 1,5 s
		OrigAudio.speak_event(self, OrigAudio.EV_HURT, 1.5)


func heal(amount: float) -> void:
	if alive:
		health = minf(health + amount, max_health)


func die(attacker: Node = null, direction := Vector3.ZERO) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	trigger = false
	move_input = Vector3.ZERO
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.leave(self)       # Gefallene fallen aus dem Fahrzeug
	collision_layer = 0          # Leichen blockieren keine Bewegung
	_apply_capsule(Stance.PRONE)
	for hb in find_children("*", "Hitbox", true, false):
		(hb as Hitbox).collision_layer = 0
	remove_from_group("team_%d" % team)
	add_to_group("corpses")
	# Netzfigur auf Clients: Richtung aus der Lage des Schützen (Todesclip je Richtung, BodyAnim.death_clip)
	if direction.length() < 0.01 and attacker is Node3D and is_instance_valid(attacker) and attacker != self:
		direction = global_position - (attacker as Node3D).global_position
	model.play_death(direction)
	# Todesschrei (speech.set Ereignis 115 „Death“) und Körperfall (Kat. 0/44 „Uni Bodyfall“, nach 0,7 s = Annahme)
	set_meta("_speech_until", -1.0)
	OrigAudio.speak_event(self, OrigAudio.EV_DEATH)
	get_tree().create_timer(0.7, false).timeout.connect(func():
		if is_instance_valid(self):
			OrigAudio.play_group(OrigAudio.CAT_STEP, OrigAudio.STEP_BODYFALL, global_position))
	died.emit(self)
	Events.soldier_died.emit(self, attacker)


# --- Spielstand --------------------------------------------------------------

func serialize() -> Dictionary:
	var ws := []
	for w in weapons:
		ws.append(w.serialize() if w else null)
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": look_yaw, "health": health, "stamina": stamina, "stance": stance,
		"alive": alive, "slot": current_slot, "weapons": ws, "medkits": medkits,
		"disguised": disguised, "uniform": uniform_color.to_html(), "helmet": helmet_style,
	}


func deserialize(d: Dictionary) -> void:
	var p: Array = d["pos"]
	global_position = Vector3(p[0], p[1], p[2])
	look_yaw = d["yaw"]
	health = d["health"]
	stamina = d.get("stamina", 100.0)
	medkits = int(d.get("medkits", medkits))
	if d.get("disguised", false):
		put_on_uniform(Color.html(d.get("uniform", "5a5e54")), d.get("helmet", "stahlhelm"))
	weapons.clear()
	for wd in d["weapons"]:
		weapons.append(Weapon.deserialize(wd) if wd != null else null)
	current_slot = int(d.get("slot", 0))
	_on_weapon_switched()
	stance = int(d.get("stance", 0))
	stance_request = stance
	_apply_capsule(stance)
	if not d.get("alive", true):
		alive = false
		collision_layer = 0
		for hb in find_children("*", "Hitbox", true, false):
			(hb as Hitbox).collision_layer = 0
		remove_from_group("team_%d" % team)
		add_to_group("corpses")
		model.set_dead_instant()
