extends Node
## Projektilsimulation (Autoload "Ballistics").
## Geschosse fliegen mit Schwerkraft und quadratischem Luftwiderstand;
## jeder Physikschritt prüft das Flugsegment per Raycast gegen Welt
## (Layer 1) und Trefferzonen (Layer 3). Schaden wie im Original: linearer Abfall nach
## Flugstrecke und Trefferzone (WeaponDB.bullet_damage/zone_damage); eigene Waffen ohne
## Originalwert skalieren mit der Restenergie (v/v0)^2 ab falloff_start.

const GRAVITY := 9.81
const MAX_LIFETIME := 3.0
const MASK := 1 | Hitbox.LAYER

class Projectile:
	var pos: Vector3
	var vel: Vector3
	var v0: float
	var drag: float
	var damage: float
	var falloff_start: float
	var data: WeaponData
	var travelled := 0.0
	var age := 0.0
	var shooter: Node
	var team := -1
	var exclude: Array[RID] = []
	var space: PhysicsDirectSpaceState3D
	var world: World3D
	var whizzed := false

var _projectiles: Array[Projectile] = []
var impact_scene_parent: Node   ## Mission setzt hier ihren Effekt-Container

## Statistik für Tests/Debug
var shots_fired := 0
var hits := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func clear() -> void:
	_projectiles.clear()


func fire(shooter: Node, origin: Vector3, direction: Vector3, data: WeaponData, exclude: Array[RID], team: int) -> void:
	var p := Projectile.new()
	p.pos = origin
	p.vel = direction.normalized() * data.muzzle_velocity
	p.v0 = data.muzzle_velocity
	# Widerstandsbeiwert: Gewehrgeschosse verlieren über 300 m ~30 %,
	# Pistolengeschosse deutlich schneller.
	p.drag = 0.0012 if data.muzzle_velocity > 600.0 else 0.0026
	p.damage = data.damage
	p.falloff_start = data.falloff_start
	p.data = data
	p.shooter = shooter
	p.team = team
	p.exclude = exclude
	p.world = (shooter as Node3D).get_world_3d()
	_projectiles.append(p)
	shots_fired += 1


func _physics_process(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var alive: Array[Projectile] = []
	for p in _projectiles:
		if _step(p, delta):
			alive.append(p)
	_projectiles = alive


## Vorbeiflug am Hörer (Kamera): Original Kat. 4/11 „Whizz Bullet Effect“ einmal je Geschoss, wenn das
## Flugsegment näher als 3 m an der Kamera vorbeigeht (Abstand = Annahme; eigene Schüsse ausgenommen).
func _whizz(p: Projectile, next: Vector3) -> void:
	if p.whizzed or p.travelled < 8.0:
		return
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return
	var c := cam.global_position
	var seg := next - p.pos
	var t := clampf((c - p.pos).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	var closest := p.pos + seg * t
	if closest.distance_to(c) < 3.0:
		p.whizzed = true
		OrigAudio.play_group(OrigAudio.CAT_HIT, OrigAudio.HIT_WHIZZ, closest)


## Helmtreffer: obere Hälfte der Kopfzone (Original: eigener Strahltest gegen das Helmmodell, 0x455670 – Form im
## Nachbau angenähert [P])
static func _helmet_part(hb: Hitbox, pos: Vector3) -> bool:
	var cs: Node3D = hb.get_child(0) as Node3D if hb.get_child_count() > 0 else null
	var c: Vector3 = cs.global_position if cs else hb.global_position
	# obere Hälfte entlang der Kopfachse (Knochen f, +Y = Scheitel), damit auch liegend/geneigt der Helm oben ist
	var up: Vector3 = cs.global_basis.y.normalized() if cs else Vector3.UP
	return (pos - c).dot(up) >= 0.0


static func _has_helmet_box(s: Node) -> bool:
	var m = s.get("model") if s else null
	return m != null and m.has_method("has_helmet_box") and bool(m.has_helmet_box())


## Zonenreihenfolge des Originals (0x455670 prüft die Volumen in fester Reihenfolge, nicht nach Abstand):
## Körper vor Kopf/Helm vor Armen vor Beinen. Liegt z. B. ein Arm vor der Brust, zählt der Rumpftreffer.
const ZONE_ORDER := [&"torso", &"head", &"arm", &"leg"]


static func _priority_zone(space: PhysicsDirectSpaceState3D, hb: Hitbox, at: Vector3, dir: Vector3) -> Hitbox:
	var best := hb
	var ex: Array[RID] = [hb.get_rid()]
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(at - dir * 0.05, at + dir * 1.0, Hitbox.LAYER, ex)
		q.collide_with_areas = true
		q.collide_with_bodies = false
		var h := space.intersect_ray(q)
		if h.is_empty() or not (h.collider is Hitbox):
			break
		var o := h.collider as Hitbox
		ex.append(o.get_rid())
		if o.soldier == hb.soldier and ZONE_ORDER.find(o.zone) >= 0 and ZONE_ORDER.find(o.zone) < ZONE_ORDER.find(best.zone):
			best = o
	return best


## Einzelspieler (hd2.exe Projektil 0x44B910, 0x44BDB0–0x44BDE5): ist der Schütze nicht der vom Spieler gesteuerte Mensch
## (0x5A0890: Steuerobjekt +0x48 == 1) und haben Schütze und Getroffener Seite 1 (Spielertrupp), wird der Mensch nicht
## getroffen – Kugeln der KI-Kameraden fliegen durch den eigenen Trupp [B Code; „vom Spieler gesteuert“ = Deutung P].
static func _sp_squad_pass(p: Projectile, hb: Hitbox) -> bool:
	if Net.is_online or not is_instance_valid(hb.soldier) or not (p.shooter is Soldier) or p.shooter == hb.soldier:
		return false
	var m := Game.current_mission() as Mission
	if m == null or m.squad == null or p.shooter == m.squad.leader():
		return false
	return WeaponDB.orig_side(p.shooter) == 1 and WeaponDB.orig_side(hb.soldier) == 1


## Gibt true zurück, solange das Projektil weiterfliegt.
func _step(p: Projectile, delta: float) -> bool:
	p.age += delta
	if p.age > MAX_LIFETIME or p.world == null:
		return false
	if not is_instance_valid(p.shooter):
		p.shooter = null
	var speed := p.vel.length()
	p.vel -= p.vel * (p.drag * speed * delta)
	p.vel.y -= GRAVITY * delta
	var next := p.pos + p.vel * delta
	var space := p.world.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.pos, next, MASK, p.exclude)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	_whizz(p, next)
	if hit.is_empty():
		p.travelled += p.pos.distance_to(next)
		p.pos = next
		return true
	p.travelled += p.pos.distance_to(hit.position)
	# Original (hd2.exe 0x44B3B0): linearer Abfall nach Flugstrecke; eigene Waffen ohne Originalwert: Restenergie
	var base := p.damage
	if p.data and p.data.falloff_per_m > 0.0:
		base = WeaponDB.bullet_damage(p.data, p.travelled)
	elif p.travelled > p.falloff_start:
		base = p.damage * clampf(pow(p.vel.length() / p.v0, 2.0), 0.25, 1.0)
	var collider: Object = hit.collider
	if collider is Hitbox:
		var hb := collider as Hitbox
		if _sp_squad_pass(p, hb):
			# Einzelspieler: Geschosse von KI-Kameraden durchdringen den eigenen Trupp (s. _sp_squad_pass)
			p.exclude.append_array(hb.soldier.exclude_rids() if hb.soldier.has_method("exclude_rids") else [hb.get_rid()])
			p.travelled -= p.pos.distance_to(hit.position)
			return true
		if is_instance_valid(hb.soldier) and hb.soldier.has_method("apply_hit"):
			hits += 1
			# B-014: das Helmmodell wird im Original zuerst geprüft (0x455670 → Zone 11): trifft der Strahl zuerst die
			# Helmfläche, bleibt es ein Helmtreffer; sonst feste Zonenreihenfolge (die Helmfläche zählt dort nicht)
			if hb.zone != Helmet.ZONE:
				hb = _priority_zone(space, hb, hit.position, p.vel.normalized())
			# Trefferzone wie im Original (Kopf ×5, Helm, Arme ×0,2, Beine ×0,33); im Einzelspieler zusätzlich der
			# Schwierigkeitsgrad (hd2.exe 0x5A1C90) – gemeinsame Quelle WeaponDB.bullet_hit_damage
			var helmet := hb.zone == Helmet.ZONE and WeaponDB.wears_helmet(hb.soldier)
			if hb.zone == &"head" and WeaponDB.wears_helmet(hb.soldier) and not _has_helmet_box(hb.soldier):
				helmet = _helmet_part(hb, hit.position)      # ohne Helmmodell: Näherung obere Kopfhälfte [P]
			var zone: StringName = &"head" if hb.zone == Helmet.ZONE else hb.zone
			hb.soldier.apply_hit(WeaponDB.bullet_hit_damage(base, zone, helmet, hb.soldier, p.shooter, not Net.is_online,
				Game.difficulty()), zone, p.shooter, p.vel.normalized())
			if hb.zone == Helmet.ZONE:
				# Helm getroffen: Funken statt Blut, Helm fliegt vom Kopf (Vorgabe Auftraggeber, Helmet.knock_off)
				Effects.impact(hit.position, hit.normal)
				Helmet.knock_off(hb.soldier as Soldier, p.vel)
				return false
		Effects.blood(hit.position, hit.normal, p.vel.normalized(), hb.zone, hb.soldier)
	else:
		# Zerstörbare Objekte (z. B. Suchscheinwerfer) bieten on_bullet_hit an
		var target: Node = collider as Node
		if target and target.has_meta("hit_proxy") and is_instance_valid(target.get_meta("hit_proxy")):
			target = target.get_meta("hit_proxy")     # z. B. zerstörbare Originalobjekte (OrigInteractive)
		for i in 3:
			if target == null or target.has_method("on_bullet_hit"):
				break
			target = target.get_parent()
		if target and target.has_method("projectile_hit"):
			# Fahrzeug mit Original-Schadensmodell: Treffpunkt/Richtung für den Zonen-Strahltest (Damage Art 1)
			target.projectile_hit(1, base, hit.position, p.vel.normalized(), p.shooter)
		elif target and target.has_method("on_bullet_hit"):
			target.on_bullet_hit(base, p.shooter)
		Effects.impact(hit.position, hit.normal)
		# Einschläge sind in der Nähe hörbar (Beschuss-Reaktion der KI).
		Events.emit_noise(hit.position, 12.0, p.shooter, p.team, &"impact")
	return false
