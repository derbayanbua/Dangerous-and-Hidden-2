extends Node
## Projektilsimulation (Autoload "Ballistics").
## Geschosse fliegen mit Schwerkraft und quadratischem Luftwiderstand;
## jeder Physikschritt prüft das Flugsegment per Raycast gegen Welt
## (Layer 1) und Trefferzonen (Layer 3). Schaden skaliert mit der
## Restenergie (v/v0)^2 ab falloff_start.

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
	var travelled := 0.0
	var age := 0.0
	var shooter: Node
	var team := -1
	var exclude: Array[RID] = []
	var space: PhysicsDirectSpaceState3D
	var world: World3D

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
	if hit.is_empty():
		p.travelled += p.pos.distance_to(next)
		p.pos = next
		return true
	p.travelled += p.pos.distance_to(hit.position)
	var energy := 1.0
	if p.travelled > p.falloff_start:
		energy = clampf(pow(p.vel.length() / p.v0, 2.0), 0.25, 1.0)
	var collider: Object = hit.collider
	if collider is Hitbox:
		var hb := collider as Hitbox
		if is_instance_valid(hb.soldier) and hb.soldier.has_method("apply_hit"):
			hits += 1
			hb.soldier.apply_hit(p.damage * energy * hb.multiplier, hb.zone, p.shooter, p.vel.normalized())
		Effects.blood(hit.position, hit.normal)
	else:
		# Zerstörbare Objekte (z. B. Suchscheinwerfer) bieten on_bullet_hit an
		var target: Node = collider as Node
		for i in 3:
			if target == null or target.has_method("on_bullet_hit"):
				break
			target = target.get_parent()
		if target and target.has_method("on_bullet_hit"):
			target.on_bullet_hit(p.damage * energy, p.shooter)
		Effects.impact(hit.position, hit.normal)
		# Einschläge sind in der Nähe hörbar (Beschuss-Reaktion der KI).
		Events.emit_noise(hit.position, 12.0, p.shooter, p.team, &"impact")
	return false
