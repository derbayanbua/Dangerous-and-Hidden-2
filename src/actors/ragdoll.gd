class_name Ragdoll
extends Node
## B-016 Ragdoll-Physik für Gefallene – BEWUSSTE ABWEICHUNG vom Original (Vorgabe Auftraggeber, Option
## `Settings.ragdoll`, Standard an; aus = Original-Todesclip wie bisher).
##
## Original [B]: Tode sind reine Animationsclips aus TABLES\anim.sav (`!smrtB*`, `#death*`, `#deathleh*`, `!smrtsed*`,
## `!smrtauto*` …, re_notes_weapons §12/§13); hd2.exe/LS3DF.dll enthalten keine Ragdoll-/Starrkörper-Bezeichner (die
## einzige Fundstelle „Physics“ 0x432CE0 ist ein Frame-Parameter neben „phobj“/„break“). Die Auswahlroutine der Tode
## ist nicht dekodiert [P] – der Nachbau wählt über `BodyAnim.death_clip`.
##
## Nachbau: PhysicalBoneSimulator3D + 11 PhysicalBone3D am Original-Skelett (Becken a, Rumpf c, Kopf f, Oberarme h/l,
## Unterarme i/m, Oberschenkel o/s, Unterschenkel p/t – dieselben Gelenke wie die Trefferzonen aus humanzones.4ds,
## deren Kisten als Körperformen dienen). Die übrigen Knochen (Hände, Füße, Schlüsselbeine, Hals) folgen ihrem Elternteil.
## Ablauf: Tod → Original-Todesclip beginnt (START_DELAY, Explosion sofort) → Simulation, deren Körper zunächst per
## Geschwindigkeitssteuerung der Clip-Pose folgen (Führungsphase/Active Ragdoll, Stärke klingt über DRIVE_FRAC der
## Cliplänge ab; Teilimpuls sofort, Rest beim Loslassen) → volle Physik mit Impuls aus Schussrichtung/Schaden bzw.
## Explosion → Ruhe (oder MAX_SIM) → Endpose als Knochenposen eingefroren, Physikkörper aus,
## Soldat (Ursprung = Leichenort für Durchsuchen/Blutlache/KI) unter das Becken versetzt und festgehalten.
## Leistung: höchstens MAX_ACTIVE gleichzeitig simulierte Ragdolls (die älteste wird eingefroren), Körper nur auf
## Ebene 9 gegen die Welt (keine Selbstkollision, keine Wirkung auf Schüsse/Sicht/Bewegung).
## MP: der Server bestimmt die Endlage (Net.corpse_settled → _corpse_pose an alle, auch an Spät-Beitretende); Clients
## simulieren lokal zur Anzeige und übernehmen danach die Endpose des Servers.
## Werte (Massen, Gelenkgrenzen, Impulsstärken, Ruheschwellen) sind Design [E].

const LAYER := 1 << 8          ## Physik-Ebene 9: nur Ragdoll-Körper
const MASK := 1                ## kollidiert nur mit der Welt
const MAX_ACTIVE := 8
const START_DELAY := 0.12      ## s Original-Todesclip vor der Übergabe an die Physik
const MAX_SIM := 9.0           ## s, danach wird in jedem Fall eingefroren
const REST_LIN := 0.2          ## m/s
const REST_ANG := 0.9          ## rad/s
const REST_TIME := 0.6         ## s in Ruhe → einfrieren
const MIN_SIM := 0.8           ## s Mindestdauer (Impuls muss erst wirken)
const BULLET_IMPULSE := Vector2(16.0, 85.0)    ## N·s min/max am getroffenen Körper
const EXPL_RANGE_K := 1.6      ## Explosionen schieben bis Radius × K
const PELVIS_BOX := [Vector3(-0.15, -0.10, -0.11), Vector3(0.15, 0.12, 0.11)]

## Knochen → Masse [kg] und Gelenkgrenzen [Grad] je Achse (Knochenachsen der Ruhelage: X seitlich, Y oben, Z hinten;
## Figur blickt nach −Z). Ruhelage = T-Haltung mit Einheitsrotationen (en01.glb). Vorzeichen nach den
## Modellkonventionen: +X dreht ein hängendes Glied nach vorn, ein aufragendes nach hinten.
const BONES := {
	"a": {"mass": 12.0},
	"c": {"mass": 20.0, "lim": [[-55, 25], [-30, 30], [-25, 25]]},
	"f": {"mass": 5.0, "lim": [[-45, 40], [-60, 60], [-30, 30]]},
	"h": {"mass": 2.5, "lim": [[-80, 80], [-80, 80], [-85, 60]]},
	"l": {"mass": 2.5, "lim": [[-80, 80], [-80, 80], [-60, 85]]},
	"i": {"mass": 1.8, "lim": [[-10, 10], [0, 140], [-10, 10]]},
	"m": {"mass": 1.8, "lim": [[-10, 10], [-140, 0], [-10, 10]]},
	"o": {"mass": 8.0, "lim": [[-25, 105], [-30, 30], [-10, 40]]},
	"s": {"mass": 8.0, "lim": [[-25, 105], [-30, 30], [-40, 10]]},
	"p": {"mass": 4.5, "lim": [[-130, 2], [-8, 8], [-5, 5]]},
	"t": {"mass": 4.5, "lim": [[-130, 2], [-8, 8], [-5, 5]]},
}

enum State { IDLE, PENDING, ACTIVE, FROZEN }

static var _active: Array = []          ## simulierende Ragdolls (älteste vorn)
static var _recent: Array = []          ## [pos, radius, ms] jüngster Explosionen
static var stats := {"started": 0, "frozen": 0, "forced": 0, "pushed": 0, "net_poses": 0}

var model: Node3D                       ## SoldierModel
var soldier: Node3D
var sk: Skeleton3D
var anim: AnimationPlayer
var sim: PhysicalBoneSimulator3D
var bodies := {}                        ## Knochenname → PhysicalBone3D
var state := State.IDLE
var sim_time := 0.0
var rest_time := 0.0
var frozen_pose := PackedFloat32Array()  ## letzte Endpose (Spielstand/Netz)
var settled_at := Vector3.INF            ## Leichenort nach dem Einfrieren
var last_impulse := Vector3.ZERO         ## Gesamtimpuls (Tests)
var _pending_t := 0.0
var _hit := {}                           ## {"dir", "amount", "bone", "pos", "vel", "explosive"}
var _push_queue: Array = []              ## [impuls, weltpos, knochen] für den ersten Physikschritt
var _started_once := false
var build_dev := 0.0                     ## größte Abweichung Körper ↔ Ruhelage beim Bau (Test)
signal settled(pose: PackedFloat32Array)


## Ist Ragdoll für diese Figur gewünscht und möglich?
static func wanted(fig_skeleton: Skeleton3D) -> bool:
	return Settings.ragdoll and fig_skeleton != null and fig_skeleton.find_bone("a") >= 0 and fig_skeleton.find_bone("c") >= 0


static func active_count() -> int:
	_active = _active.filter(func(r): return is_instance_valid(r) and r.state == State.ACTIVE)
	return _active.size()


## Ragdoll an einer Figur anlegen (noch ohne Physikkörper; die entstehen erst beim Tod)
static func attach(p_model: Node3D, p_soldier: Node3D, p_sk: Skeleton3D, p_anim: AnimationPlayer) -> Ragdoll:
	var r := Ragdoll.new()
	r.name = "Ragdoll"
	r.model = p_model
	r.soldier = p_soldier
	r.sk = p_sk
	r.anim = p_anim
	p_model.add_child(r)
	return r


## Tod: Übergabe an die Physik nach `delay` s (Explosion: 0). hit = siehe _hit.
func begin(hit: Dictionary, delay: float = START_DELAY) -> void:
	if state != State.IDLE:
		return
	_hit = hit
	# Körper sofort bauen: der Simulator übernimmt die Startlage erst mit der nächsten Skelett-Aktualisierung,
	# daher startet die Simulation frühestens im nächsten Physikschritt (delay 0 = Explosion).
	if not _build():
		return
	state = State.PENDING
	_pending_t = delay


func is_active() -> bool:
	return state == State.ACTIVE


func is_frozen() -> bool:
	return state == State.FROZEN


func is_pending() -> bool:
	return state == State.PENDING


func cancel() -> void:
	if state == State.ACTIVE and is_instance_valid(sim):
		sim.physical_bones_stop_simulation()
	_active.erase(self)
	state = State.IDLE


func _physics_process(delta: float) -> void:
	match state:
		State.PENDING:
			_pending_t -= delta
			if _pending_t <= 0.0:
				_start()
		State.ACTIVE:
			_tick(delta)


# --- Aufbau -------------------------------------------------------------------------------------------------------

## Physikkörper bauen. Die Gelenkrahmen legt Godot beim Eintritt in den Baum aus der aktuellen Lage fest – daher
## wird das Skelett dafür kurz in die Ruhelage (T-Haltung) gesetzt, damit die Gelenkgrenzen relativ zur Ruhelage gelten.
func _build() -> bool:
	if is_instance_valid(sim):
		return true
	if not is_instance_valid(sk):
		return false
	var saved := _save_local_poses()
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSim"
	sk.add_child(sim)                 # letzter Modifier → wirkt nach Haltungsschicht/IK
	var zones := {}
	for z in SoldierModel.orig_zone_table():
		zones[String(z["bone"])] = [Vector3(z["min"][0], z["min"][1], z["min"][2]), Vector3(z["max"][0], z["max"][1], z["max"][2])]
	for bn: String in BONES:
		if sk.find_bone(bn) < 0:
			continue
		var cfg: Dictionary = BONES[bn]
		var box: Array = PELVIS_BOX if bn == "a" else zones.get(bn, [])
		if box.is_empty():
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "RB_" + bn
		pb.bone_name = bn
		pb.collision_layer = LAYER
		pb.collision_mask = MASK
		pb.mass = float(cfg["mass"])
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = 0.1
		pb.angular_damp = 1.2
		pb.can_sleep = true
		if cfg.has("lim"):
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			var lim: Array = cfg["lim"]
			for ai in 3:
				var ax: String = ["x", "y", "z"][ai]
				pb.set("joint_constraints/%s/angular_limit_enabled" % ax, true)
				pb.set("joint_constraints/%s/angular_limit_lower" % ax, float(lim[ai][0]))
				pb.set("joint_constraints/%s/angular_limit_upper" % ax, float(lim[ai][1]))
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var mn: Vector3 = box[0]
		var mx: Vector3 = box[1]
		shape.size = (mx - mn).max(Vector3(0.04, 0.04, 0.04))
		cs.shape = shape
		cs.position = (mn + mx) * 0.5
		pb.add_child(cs)
		sim.add_child(pb)
		bodies[bn] = pb
		# Prüfwert: Körper beim Bau in der Ruhelage des Knochens (Gelenkrahmen relativ zur T-Haltung)
		build_dev = maxf(build_dev, pb.global_position.distance_to(sk.global_transform * sk.get_bone_global_rest(sk.find_bone(bn)).origin))
	_restore_local_poses(saved)
	sk.force_update_all_bone_transforms()
	return bodies.size() >= 6


func _save_local_poses() -> Array:
	var out := []
	for i in sk.get_bone_count():
		out.append([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i)])
	return out


func _restore_local_poses(saved: Array) -> void:
	for i in mini(saved.size(), sk.get_bone_count()):
		sk.set_bone_pose_position(i, saved[i][0])
		sk.set_bone_pose_rotation(i, saved[i][1])
		sk.set_bone_pose_scale(i, saved[i][2])


## Andere Skelett-Modifier (Anschlag, IK, Stellungs-IK) abschalten – die Animation läuft weiter (Führungsphase)
func _quiet_modifiers() -> void:
	for c in sk.get_children():
		if c is SkeletonModifier3D and c != sim:
			(c as SkeletonModifier3D).active = false


## Alle anderen Skelett-Modifier (Anschlag, IK, Stellungs-IK) und die Animation anhalten
func _quiet_skeleton() -> void:
	# Alle Animationsspieler der Figur anhalten (active = false wirkt auch, wenn später jemand play() ruft,
	# z. B. die MG-Stellung beim Absteigen des toten Bedieners)
	if is_instance_valid(anim):
		anim.pause()
	if is_instance_valid(model):
		for ap in model.find_children("*", "AnimationPlayer", true, false):
			(ap as AnimationPlayer).active = false
	for c in sk.get_children():
		if c is SkeletonModifier3D and c != sim:
			(c as SkeletonModifier3D).active = false


# --- Simulation ---------------------------------------------------------------------------------------------------

func _start() -> void:
	if not is_instance_valid(sim):
		state = State.IDLE
		return
	var drive := not _started_once and not bool(_hit.get("explosive", false)) and _setup_drive()
	if drive:
		_quiet_modifiers()            # Todesclip läuft weiter (Hände/Füße/Hals, Zielpose der Führungsphase)
	else:
		_quiet_skeleton()
	# Der Simulator übernimmt die Startlage aus dem zuletzt aktualisierten Skelett (aktuelle Todesclip-Pose)
	sim.active = true
	sim.physical_bones_start_simulation()
	state = State.ACTIVE
	sim_time = 0.0
	rest_time = 0.0
	stats["started"] += 1
	_active.append(self)
	while active_count() > MAX_ACTIVE:
		var oldest: Ragdoll = _active[0]
		stats["forced"] += 1
		oldest.freeze()
	if not _started_once:
		_started_once = true
		_queue_hit_impulses()
		_queue_recent_explosions()


func _queue_hit_impulses() -> void:
	var vel: Vector3 = _hit.get("vel", Vector3.ZERO)
	if vel.length() > 0.1:
		for bn in bodies:
			var pb: PhysicalBone3D = bodies[bn]
			_push_queue.append([vel * pb.mass, Vector3.INF, bn])
	if bool(_hit.get("explosive", false)):
		return                        # Explosion: über _recent/push_explosion
	var dir: Vector3 = _hit.get("dir", Vector3.ZERO)
	if dir.length() < 0.01:
		return
	dir = (dir.normalized() + Vector3.UP * 0.12).normalized()
	var amount := float(_hit.get("amount", 30.0))
	var mag := clampf(BULLET_IMPULSE.x + amount * 0.45, BULLET_IMPULSE.x, BULLET_IMPULSE.y)
	var bn := String(_hit.get("bone", ""))
	if not bodies.has(bn):
		bn = zone_bone(String(_hit.get("zone", "torso")))
	if not bodies.has(bn):
		bn = "c"
	if drive_total > 0.0:
		# Führungsphase: ein Teil des Impulses sofort (Treffer sichtbar), der Rest beim Loslassen
		_push_queue.append([dir * mag * 0.4, _hit.get("pos", Vector3.INF), bn])
		_late_push.append([dir * mag * 0.6, Vector3.INF, bn])
	else:
		_push_queue.append([dir * mag, _hit.get("pos", Vector3.INF), bn])


# --- Führungsphase (Active Ragdoll): Körper folgen dem Original-Todesclip, Stärke klingt ab -----------------------
## BEWUSSTE ABWEICHUNG: Das Original spielt den Todesclip vollständig. Hier beginnt der Tod mit dem Original-Clip
## (Einknicken, Fallrichtung, Haltung je Zone/Richtung über BodyAnim.death_clip); ab START_DELAY simulieren die Körper,
## werden aber DRIVE_FRAC der Cliplänge lang per Geschwindigkeitssteuerung auf die Clip-Pose gezogen (Stärke fällt
## quadratisch auf 0) – fließender Übergang statt schlaffer Puppe, Clip bestimmt Ablauf und Timing [E].
const DRIVE_FRAC := 0.55       ## Anteil der Cliplänge bis zur vollen Physik
const DRIVE_MIN := 0.25
const DRIVE_MAX := 0.9
const DRIVE_GAIN := 0.6
const DRIVE_STRENGTH := 0.85
var drive_total := 0.0
var drive_time := 0.0
var drive_err_max := 0.0                 ## größte Abweichung Becken ↔ Clip-Pose bei Stärke ≥ 0,5 (Test)
var drive_target_travel := 0.0           ## Weg der Becken-Zielpose während der Führung (Test)
var _clip := ""
var _clip_t0 := 0.0
var _tracks := {}                        ## Knochenindex → [Positionsspur, Rotationsspur]
var _late_push: Array = []
var _drive_start := Vector3.INF


func _setup_drive() -> bool:
	_clip = String(_hit.get("clip", ""))
	if _clip == "" or not is_instance_valid(anim) or not anim.has_animation(_clip):
		return false
	var a := anim.get_animation(_clip)
	_clip_t0 = clampf(anim.current_animation_position if anim.current_animation == _clip else START_DELAY, 0.0, a.length)
	_tracks.clear()
	for ti in a.get_track_count():
		var tt := a.track_get_type(ti)
		if tt != Animation.TYPE_POSITION_3D and tt != Animation.TYPE_ROTATION_3D:
			continue
		var bi := sk.find_bone(String(a.track_get_path(ti).get_concatenated_subnames()))
		if bi < 0:
			continue
		if not _tracks.has(bi):
			_tracks[bi] = [-1, -1]
		_tracks[bi][0 if tt == Animation.TYPE_POSITION_3D else 1] = ti
	if _tracks.is_empty():
		return false
	drive_total = clampf(a.length * DRIVE_FRAC - _clip_t0, DRIVE_MIN, DRIVE_MAX)
	drive_time = 0.0
	return true


## Weltlage der Knochen in der Clip-Pose zur Clipzeit t (direkt aus den Animationsspuren, unabhängig vom Skelett)
func _clip_world(t: float) -> Dictionary:
	var a := anim.get_animation(_clip)
	t = minf(t, a.length)
	var glob := {}
	var out := {}
	var skg := sk.global_transform
	for bn in bodies:
		var bi := sk.find_bone(bn)
		out[bn] = skg * _clip_global(a, t, bi, glob)
	return out


func _clip_global(a: Animation, t: float, bi: int, memo: Dictionary) -> Transform3D:
	if memo.has(bi):
		return memo[bi]
	var rest := sk.get_bone_rest(bi)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	if _tracks.has(bi):
		var tr: Array = _tracks[bi]
		if int(tr[0]) >= 0:
			pos = a.position_track_interpolate(int(tr[0]), t)
		if int(tr[1]) >= 0:
			rot = a.rotation_track_interpolate(int(tr[1]), t)
	var local := Transform3D(Basis(rot), pos)
	var par := sk.get_bone_parent(bi)
	var g := local if par < 0 else _clip_global(a, t, par, memo) * local
	memo[bi] = g
	return g


func _drive(delta: float) -> void:
	drive_time += delta
	var k := clampf(drive_time / drive_total, 0.0, 1.0)
	var w := DRIVE_STRENGTH * (1.0 - k * k)
	var targets := _clip_world(_clip_t0 + drive_time)
	var inv_dt := 1.0 / maxf(delta, 0.001)
	for bn in bodies:
		var pb: PhysicalBone3D = bodies[bn]
		var tg: Transform3D = targets[bn]
		var lin := (tg.origin - pb.global_position) * inv_dt * DRIVE_GAIN
		var q := tg.basis.get_rotation_quaternion() * pb.global_basis.get_rotation_quaternion().inverse()
		if q.w < 0.0:
			q = -q
		var ang := Vector3.ZERO
		var angle := q.get_angle()
		if angle > 0.0001:
			ang = q.get_axis() * angle * inv_dt * DRIVE_GAIN
		pb.linear_velocity = pb.linear_velocity.lerp(lin, w)
		pb.angular_velocity = pb.angular_velocity.lerp(ang, w)
		if bn == "a":
			if _drive_start == Vector3.INF:
				_drive_start = tg.origin
			drive_target_travel = maxf(drive_target_travel, tg.origin.distance_to(_drive_start))
			if w >= 0.5:
				drive_err_max = maxf(drive_err_max, tg.origin.distance_to(pb.global_position))
	if k >= 1.0:
		drive_total = 0.0
		_quiet_skeleton()             # ab jetzt volle Physik, Animation aus
		_push_queue.append_array(_late_push)
		_late_push.clear()


func is_driving() -> bool:
	return state == State.ACTIVE and drive_total > 0.0


func _queue_recent_explosions() -> void:
	var now := Time.get_ticks_msec()
	for e in _recent:
		if now - int(e[2]) <= 600:
			push_explosion(e[0], e[1], false)


## Trefferzone → Knochen des Ragdolls
static func zone_bone(zone: String) -> String:
	match zone:
		"head", "helmet":
			return "f"
		"arm":
			return "h"
		"leg", "legs":
			return "o"
	return "c"


func _tick(delta: float) -> void:
	sim_time += delta
	if not _push_queue.is_empty():
		for p in _push_queue:
			var pb: PhysicalBone3D = bodies.get(p[2])
			if pb == null:
				continue
			var at: Vector3 = p[1]
			if at.is_finite():
				pb.apply_impulse(p[0], at - pb.global_position)
			else:
				pb.apply_central_impulse(p[0])
			last_impulse += p[0]
		_push_queue.clear()
		rest_time = 0.0
		return
	if drive_total > 0.0:
		_drive(delta)
		rest_time = 0.0
		return
	var still := true
	for bn in bodies:
		var pb: PhysicalBone3D = bodies[bn]
		if pb.linear_velocity.length() > REST_LIN or pb.angular_velocity.length() > REST_ANG:
			still = false
			break
	rest_time = rest_time + delta if still else 0.0
	if (sim_time >= MIN_SIM and rest_time >= REST_TIME) or sim_time >= MAX_SIM:
		freeze()


## Explosion schiebt diesen Körper (auch eine bereits eingefrorene Leiche: wird geweckt)
func push_explosion(pos: Vector3, radius: float, wake := true) -> bool:
	if state == State.PENDING and not _started_once:
		return false                  # beim ersten Start über _recent
	var center := pelvis_position()
	var reach := maxf(radius, 1.0) * EXPL_RANGE_K
	var d := center.distance_to(pos)
	if d > reach:
		return false
	if state == State.FROZEN or state == State.IDLE:
		if not wake or not _build():
			return false
		_started_once = true
		_unfreeze()
	var dv := clampf(radius * 1.8, 3.0, 12.0) * (1.0 - d / reach)
	for bn in bodies:
		var pb: PhysicalBone3D = bodies[bn]
		var away := pb.global_position - pos + Vector3.UP * 0.6
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		_push_queue.append([away * dv * pb.mass, pb.global_position + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)), bn])
	stats["pushed"] += 1
	return true


func _unfreeze() -> void:
	if is_instance_valid(soldier) and soldier.has_method("unpin_corpse"):
		soldier.call("unpin_corpse")
	_quiet_skeleton()
	state = State.PENDING             # Start im nächsten Physikschritt (Simulator liest die eingefrorene Pose)
	_pending_t = 0.0


## Weltlage des Beckens (simuliert bzw. aktuelle Knochenpose)
func pelvis_position() -> Vector3:
	var pb: PhysicalBone3D = bodies.get("a")
	if state == State.ACTIVE and pb != null:
		return pb.global_position
	var bi := sk.find_bone("a") if is_instance_valid(sk) else -1
	if bi < 0:
		return soldier.global_position if is_instance_valid(soldier) else Vector3.ZERO
	return sk.global_transform * sk.get_bone_global_pose(bi).origin


# --- Einfrieren / Endpose -------------------------------------------------------------------------------------------

## Endpose übernehmen: Weltlage aller Knochen erfassen, Physik aus, Soldat unter das Becken versetzen (nur wo die
## Leichenlage maßgeblich ist: Einzelspieler/Server), Knochenposen fest setzen.
func freeze() -> void:
	if state != State.ACTIVE:
		return
	drive_total = 0.0
	_late_push.clear()
	_quiet_skeleton()                 # auch bei vorzeitigem Einfrieren in der Führungsphase
	var world := _world_bone_poses()
	sim.physical_bones_stop_simulation()
	sim.active = false
	_active.erase(self)
	state = State.FROZEN
	stats["frozen"] += 1
	var authoritative := not Net.is_online or Net.is_authority()
	var origin: Vector3 = soldier.global_position
	if authoritative:
		var wa: Transform3D = world[sk.find_bone("a")]
		origin = _ground_below(wa.origin)
		if soldier.has_method("pin_corpse"):
			soldier.call("pin_corpse", origin)
	_set_world_poses(world)
	settled_at = soldier.global_position
	frozen_pose = export_pose()
	_place_search_points()
	settled.emit(frozen_pose)
	if authoritative and Net.is_online:
		Net.corpse_settled(soldier, frozen_pose)


func _world_bone_poses() -> Array:
	var n := sk.get_bone_count()
	var world := []
	world.resize(n)
	var skg := sk.global_transform
	for i in n:
		world[i] = null
	for i in n:
		_world_of(i, world, skg)
	return world


func _world_of(i: int, world: Array, skg: Transform3D) -> Transform3D:
	if world[i] != null:
		return world[i]
	var bn := sk.get_bone_name(i)
	var t: Transform3D
	var pb: PhysicalBone3D = bodies.get(bn)
	if pb != null and state == State.ACTIVE:
		t = pb.global_transform * pb.body_offset.affine_inverse()
	else:
		var par := sk.get_bone_parent(i)
		var base := skg if par < 0 else _world_of(par, world, skg)
		t = base * sk.get_bone_pose(i)
	world[i] = t.orthonormalized()
	return world[i]


func _set_world_poses(world: Array) -> void:
	var inv_sk := sk.global_transform.affine_inverse()
	for i in sk.get_bone_count():
		var par := sk.get_bone_parent(i)
		var wi: Transform3D = world[i]
		var base: Transform3D = inv_sk
		if par >= 0:
			var wp: Transform3D = world[par]
			base = wp.affine_inverse()
		var local: Transform3D = base * wi
		sk.set_bone_pose_position(i, local.origin)
		sk.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	sk.force_update_all_bone_transforms()


func _ground_below(p: Vector3) -> Vector3:
	var space := sk.get_world_3d().direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 3.0, 1))
	return h.position if not h.is_empty() else Vector3(p.x, p.y - 0.2, p.z)


## Durchsuchen-Punkte (Pickups.Loot, FieldInventory.SearchSpot) an die liegende Leiche
func _place_search_points() -> void:
	if not is_instance_valid(soldier):
		return
	var c := pelvis_position()
	for ch in soldier.get_children():
		if ch is Interactable:
			(ch as Node3D).global_position = Vector3(c.x, soldier.global_position.y, c.z)


## Endpose als Zahlenfeld: [Ursprung x, y, z, Knochenzahl, je Knochen Pos(3) + Quaternion(4)] im Skelettraum
func export_pose() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var o: Vector3 = soldier.global_position
	out.append_array([o.x, o.y, o.z, float(sk.get_bone_count())])
	for i in sk.get_bone_count():
		var p := sk.get_bone_pose_position(i)
		var q := sk.get_bone_pose_rotation(i)
		out.append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w])
	return out


## Endpose übernehmen (Netz/Spielstand/Spät-Beitritt): laufende Simulation abbrechen, Ursprung setzen, Posen fest
func apply_pose(pose: PackedFloat32Array, set_origin := true) -> bool:
	if pose.size() < 4 or not is_instance_valid(sk):
		return false
	var n := int(pose[3])
	if n != sk.get_bone_count() or pose.size() < 4 + n * 7:
		return false
	if state == State.ACTIVE:
		sim.physical_bones_stop_simulation()
		sim.active = false
		_active.erase(self)
	_push_queue.clear()
	_late_push.clear()
	drive_total = 0.0
	_quiet_skeleton()
	if set_origin and soldier.has_method("pin_corpse"):
		soldier.call("pin_corpse", Vector3(pose[0], pose[1], pose[2]))
	for i in n:
		var k := 4 + i * 7
		sk.set_bone_pose_position(i, Vector3(pose[k], pose[k + 1], pose[k + 2]))
		sk.set_bone_pose_rotation(i, Quaternion(pose[k + 3], pose[k + 4], pose[k + 5], pose[k + 6]).normalized())
	sk.force_update_all_bone_transforms()
	state = State.FROZEN
	frozen_pose = pose
	settled_at = soldier.global_position
	_place_search_points()
	stats["net_poses"] += 1
	return true


# --- Explosionen (Effects.explosion) ----------------------------------------------------------------------------------

## Von Effects.explosion aufgerufen (läuft auf jedem Rechner mit, da rein optisch): merkt die Explosion für gleich
## startende Ragdolls und schiebt laufende/ruhende Leichen in Reichweite.
static func explosion(tree: SceneTree, pos: Vector3, radius: float) -> void:
	var now := Time.get_ticks_msec()
	_recent = _recent.filter(func(e): return now - int(e[2]) <= 600)
	_recent.append([pos, radius, now])
	if not Settings.ragdoll or tree == null:
		return
	for r in tree.get_nodes_in_group("ragdolls"):
		var rd := r as Ragdoll
		if rd and rd.state in [State.ACTIVE, State.FROZEN]:
			rd.push_explosion(pos, radius, true)


func _enter_tree() -> void:
	add_to_group("ragdolls")


func _exit_tree() -> void:
	_active.erase(self)
