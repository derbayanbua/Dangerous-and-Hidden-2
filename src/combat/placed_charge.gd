class_name PlacedCharge
extends Node3D
## Abgelegter Sprengstoff (Zeitzünder 10 s) oder Mine (Annäherungszünder: Gegner/Fahrzeug ≤ 1,8 m).
## Schaden wie eine schwere Ladung, Deckung schützt (Sichtlinie zum Explosionspunkt).

const FUSE := 10.0
const RADIUS := 7.0
const DAMAGE := 420.0
const MINE_TRIGGER := 1.8

var kind := "explosive"           ## "explosive" oder "mine"
var owner_soldier: Soldier
var team := 0
var _t := 0.0
var _armed := false
var _done := false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var m: Mesh = CylinderMesh.new() if kind == "mine" else BoxMesh.new()
	if m is CylinderMesh:
		(m as CylinderMesh).top_radius = 0.14
		(m as CylinderMesh).bottom_radius = 0.16
		(m as CylinderMesh).height = 0.07
	else:
		(m as BoxMesh).size = Vector3(0.25, 0.12, 0.18)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.25) if kind == "mine" else Color(0.55, 0.2, 0.15)
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if kind == "explosive":
		if _t >= FUSE:
			explode()
		return
	# Mine scharf nach 3 s (Zeit zum Entfernen); löst bei Gegnern bzw. Fahrzeugen aus
	if _t < 3.0:
		return
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != team and s.team != Soldier.TEAM_NEUTRAL \
				and s.global_position.distance_to(global_position) < MINE_TRIGGER:
			explode()
			return
	for v in get_tree().get_nodes_in_group("vehicles"):
		if (v as Node3D).global_position.distance_to(global_position) < MINE_TRIGGER + 1.5:
			explode()
			return


func explode() -> void:
	if _done:
		return
	_done = true
	var pos := global_position + Vector3.UP * 0.2
	var by: Node = owner_soldier if is_instance_valid(owner_soldier) else null
	Effects.explosion(pos, RADIUS * 0.7)
	Events.emit_noise(pos, 300.0, by, team, &"explosion")
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive:
			continue
		var target := s.global_position + Vector3.UP * 0.5
		var d := pos.distance_to(target)
		if d > RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var f := 1.0 - d / RADIUS
		s.apply_hit(DAMAGE * f * f, &"torso", by, (target - pos).normalized())
	OrigInteractive.damage_objects(get_tree(), pos, RADIUS, DAMAGE, by)
	queue_free()
