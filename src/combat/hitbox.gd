class_name Hitbox
extends Area3D
## Trefferzone eines Soldaten. Projektile prüfen per Raycast gegen
## Physik-Layer 3 (hitboxes) und leiten Treffer an den Soldaten weiter.

const LAYER := 1 << 2

@export var zone: StringName = &"torso"
@export var multiplier := 1.0
var soldier: Node


static func create(owner_soldier: Node, zone_name: StringName, mult: float, shape: Shape3D) -> Hitbox:
	var h := Hitbox.new()
	h.name = "Hitbox_%s" % zone_name
	h.zone = zone_name
	h.multiplier = mult
	h.soldier = owner_soldier
	h.collision_layer = LAYER
	h.collision_mask = 0
	h.monitoring = false
	h.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = shape
	h.add_child(cs)
	return h
