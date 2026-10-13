extends "res://src/missions/orig_generic.gd"
## AFRICA6 „Raubvögel“: Bordschützen-Einsatz in der Ju 88 (Belege: docs/re_notes_ju88.md, Daten
## orig_cache/africa6/ju88.json aus tools/fmt_ju88.py).
## - Ju 88 folgt der festen Original-Flugbahn (#aircraftA1..6, 25 Bilder/s); Fortschritt nur, solange der
##   Akteur eingeschaltet ist (FRM_SetON durch das Originalskript nach der Zwischensequenz).
## - Spieler sitzen an SEAT01/02/03/00 (Board01..04) mit dem Original-MG des Sitzes.
## - SetActorState(ju88, n): n Jäger (Bf 109) mit zufälligen IDs 1–9, eigene Original-Bahnen, sichtbar ab 9–11 s,
##   feuern nur in ihren Feuerfenstern: Schaden an der Ju 88 = 180/s je Jäger × SetupJunkers88(a)·0,01.
## - Lebenspunkte Ju 88 5000, Jäger 10000 × (0,7/0,85/1,0 je Schwierigkeit); Treffer-Schaden ÷ b·0,01.
## - Sieg: Originalskript (Whenever _FrameInRange(ju88) < 500 am Dummy AF5_obj). Ju 88 bei 0 LP → gescheitert.
## Vereinfachungen: Schwenkgrenzen der MG-Stände und Absturz-/Wackelanimationen (#adamage, #bfshotdwn) nicht
## nachgebildet (Absturz der Jäger: Sturzflug + Explosion), Funksprüche fehlen.

const SEAT_OF_PLAYER := [1, 2, 3, 0]

var j88: Dictionary = {}
var ju88: Node3D
var flight_t := 0.0
var ju88_health := 5000.0
var damage_mult := 0.6          ## SetupJunkers88(a): a·0,01
var hit_div := 1.0              ## SetupJunkers88(b): b·0,01
var fighters: Array = []
var _path: Array = []            ## [[t, pos, rot], …] Ju 88
var _seated := false


func _init() -> void:
	super._init()


func _spawn_actors() -> void:
	super._spawn_actors()
	var d = LsRuntime._read_json(orig.mission_dir + "/ju88.json")
	j88 = d if typeof(d) == TYPE_DICTIONARY else {}
	ju88 = runtime.find_frame("ju88") if runtime else null
	if j88.is_empty() or ju88 == null:
		push_warning("AFRICA6: ju88.json oder Akteur ju88 fehlt (tools/fmt_ju88.py)")
		return
	_path = _keys(j88["path"]["segments"])
	ju88_health = _param("c100_health", 5000.0)
	_pose_body(ju88)
	ju88.set_meta("orig_ctl", self)
	ju88.visible = false          # Originalskript schaltet sie nach der Zwischensequenz ein
	_apply_path(ju88, _path, 0.0)
	_board_squad()


## Junkers88-Parameter aus actors.bin (c100 Lebenspunkte, c200 Jäger-LP, c300 Schadensrate je feuerndem Jäger)
func _param(key: String, dflt: float) -> float:
	var e = j88.get("actor", {}).get("params", {}).get(key, {})
	return float(e.get("value", dflt)) if e is Dictionary else dflt


## Ruhelage: Bug entlang Modell +X → BODY −90° Gier (Original #adamage0), dann Bug = Flugrichtung
static func _pose_body(n: Node3D) -> void:
	var body := n.find_child("BODY", true, false) as Node3D
	if body:
		body.quaternion = Quaternion(0.0, -0.70711, 0.0, 0.70711)


## Segmente → durchgehende Keyliste [Zeit s, Position, Rotation]
static func _keys(segments: Array) -> Array:
	var out: Array = []
	for seg in segments:
		var t0 := float(seg.get("start_s", 0.0))
		var rots: Array = seg.get("rot", [])
		var poss: Array = seg.get("pos", [])
		for i in poss.size():
			var p: Array = poss[i]
			var r: Array = rots[mini(i, rots.size() - 1)] if not rots.is_empty() else [0, 0, 0, 0, 1]
			out.append([t0 + float(p[0]) / 25.0, Vector3(p[1], p[2], p[3]), Quaternion(r[1], r[2], r[3], r[4]).normalized()])
	return out


static func _sample(keys: Array, t: float) -> Array:
	if keys.is_empty():
		return [Vector3.ZERO, Quaternion.IDENTITY]
	if t <= keys[0][0]:
		return [keys[0][1], keys[0][2]]
	var lo := 0
	var hi := keys.size() - 1
	if t >= keys[hi][0]:
		return [keys[hi][1], keys[hi][2]]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if keys[mid][0] <= t:
			lo = mid
		else:
			hi = mid
	var a: Array = keys[lo]
	var b: Array = keys[hi]
	var k := clampf((t - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
	return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Quaternion).slerp(b[2], k)]


static func _apply_path(n: Node3D, keys: Array, t: float) -> void:
	var s := _sample(keys, t)
	n.global_transform = Transform3D(Basis(s[1]), s[0])


func _board_squad() -> void:
	var seats: Array = j88.get("seats", [])
	for i in squad.members.size():
		var s: Soldier = squad.members[i]
		var seat: Dictionary = seats[SEAT_OF_PLAYER[i % 4]] if SEAT_OF_PLAYER[i % 4] < seats.size() else {}
		var item := int(seat.get("turret", {}).get("weapon_item", 37))
		var wd := WeaponDB.from_orig(item, true)
		if wd == null:
			wd = WeaponDB.get_weapon(&"bren")
		var w := Weapon.new(wd, false)
		w.in_mag = wd.magazine_size
		w.reserve = wd.magazine_size * 30
		var arr: Array[Weapon] = [w, null, null]
		s.weapons = arr
		s.current_slot = 0
		s.mounted = ju88
		s.collision_layer = 0
		s.collision_mask = 0
		s.stance = Soldier.Stance.CROUCH
		s.stance_request = Soldier.Stance.CROUCH
		s.set_meta("ju88_seat", seat)
		s._on_weapon_switched()
	_seated = true


## Schützen mit der Ju 88 mitführen (Sitzposition in Akteurkoordinaten aus ju88.json)
func _carry_squad() -> void:
	for s in squad.members:
		if not s.alive or not s.has_meta("ju88_seat"):
			continue
		var seat: Dictionary = s.get_meta("ju88_seat")
		var p: Array = seat.get("pos_actor", [0, 0, 0])
		s.global_position = ju88.global_transform * Vector3(p[0], p[1] - 0.6, p[2])
		s.velocity = Vector3.ZERO


# --- Skriptschnittstelle -------------------------------------------------------------

## SetActorState(ju88, n) mit n = 5/6/7: so viele Jäger mit verschiedenen zufälligen IDs 1–9
func set_actor_state(n: int) -> void:
	ju88.set_meta("actor_state", n)
	if n < 1 or n > 9 or not fighters.is_empty():
		return
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	ids.shuffle()
	var fac: Array = j88["fighters"].get("difficulty_factor", [0.7, 0.85, 1.0])
	var hp := _param("c200_fighter_health", 10000.0) * float(fac[clampi(Game.difficulty() - 1, 0, fac.size() - 1)])
	for id in ids.slice(0, n):
		for fp in j88["fighters"].get("paths", []):
			if int(fp.get("id", -1)) == id:
				_spawn_fighter(fp, hp)


func setup_junkers88(a: float, b: float) -> void:
	damage_mult = a * 0.01
	hit_div = maxf(b * 0.01, 0.01)


func _spawn_fighter(fp: Dictionary, hp: float) -> void:
	var f := Fighter.new()
	f.name = "Bf109_%d" % int(fp["id"])
	f.mission = self
	f.keys = _keys(fp.get("segments", []))
	f.windows = fp.get("fire_windows", [])
	f.health = hp
	dynamic_root.add_child(f)
	var vis: Node3D = orig.model_instance("la_bf109canyon")
	if vis:
		f.add_child(vis)
		_pose_body(vis)
	f.build_hitbox()
	f.visible = false
	fighters.append(f)


## Jäger: folgt seiner Originalbahn synchron zur Ju 88; Treffer per Ballistik (on_bullet_hit)
class Fighter extends Node3D:
	var mission
	var keys: Array = []
	var windows: Array = []
	var health := 10000.0
	var down := false
	var _fall_v := Vector3.ZERO
	var _fall_t := 0.0

	func build_hitbox() -> void:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10.0, 2.5, 9.0)       # Spannweite Bf 109 ≈ 9,9 m, Länge ≈ 9 m
		cs.shape = box
		body.add_child(cs)
		add_child(body)

	func firing(t: float) -> bool:
		if down:
			return false
		for w in windows:
			if t >= float(w.get("start_s", 0)) and t <= float(w.get("end_s", 0)):
				return true
		return false

	## Originalschaden in Spieleinheiten ×10 (weapon_db: Originalschaden/10), geteilt durch SetupJunkers88(b)
	func on_bullet_hit(dmg: float, _shooter: Node) -> void:
		if down or not visible:
			return
		health -= dmg * 10.0 / mission.hit_div
		if health <= 0.0:
			shoot_down()

	func shoot_down() -> void:
		down = true
		mission.stats["kills"] = int(mission.stats.get("kills", 0)) + 1
		Events.say("Jäger abgeschossen!", 2.5)
		_fall_v = -global_basis.z * 45.0 + Vector3.DOWN * 5.0
		Effects.explosion(global_position, 3.0)

	func tick(t: float, delta: float) -> void:
		if down:
			_fall_t += delta
			_fall_v += Vector3.DOWN * 9.8 * delta
			global_position += _fall_v * delta
			rotate_object_local(Vector3.FORWARD, 1.5 * delta)
			if _fall_t > 6.0:
				Effects.explosion(global_position, 8.0)
				queue_free()
			return
		mission._apply_path(self, keys, t)
		visible = t >= 9.0       # Original: unsichtbar bis 9 s, eingeblendet bis 11 s


func _on_tick(delta: float) -> void:
	super._on_tick(delta)
	if ju88 == null or j88.is_empty():
		return
	if ju88.visible:
		flight_t += delta
	_apply_path(ju88, _path, flight_t)
	if _seated:
		_carry_squad()
	var firing := 0
	for f in fighters:
		if is_instance_valid(f):
			f.tick(flight_t, delta)
			if f.firing(flight_t):
				firing += 1
	if firing > 0 and ju88.visible:
		var before := ju88_health
		ju88_health -= _param("c300_attack_damage", 180.0) * damage_mult * firing * delta
		# Original-Schadensstufen bei 4000/3000/2000/1000 LP
		if int(before / 1000.0) != int(ju88_health / 1000.0) and ju88_health > 0.0:
			Events.say("Ju 88 getroffen – Zustand %d %%" % int(ju88_health / 50.0), 2.5)
		if ju88_health <= 0.0 and not finished:
			Effects.explosion(ju88.global_position, 10.0)
			finish(false, "Die Ju 88 wurde abgeschossen.")
