class_name Door
extends Interactable
## Drehtür mit Kollision (AnimatableBody3D). Öffnet vom Benutzer weg.

var width := 1.1
var height := 2.1
var color := Color(0.35, 0.24, 0.15)
var is_open := false
var _hinge: Node3D
var _body: AnimatableBody3D
var _open_sign := 1.0


func _ready() -> void:
	super._ready()
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)
	_body = AnimatableBody3D.new()
	_body.collision_layer = 1
	_body.position = Vector3(width * 0.5, height * 0.5, 0)
	_hinge.add_child(_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.07)
	cs.shape = bs
	_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	_body.add_child(mi)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.035
	km.height = 0.07
	knob.mesh = km
	knob.position = Vector3(width * 0.4, -0.05, 0.06)
	_body.add_child(knob)
	_update_prompt()


func interact(s: Soldier) -> void:
	# Tür öffnet sich von der Person weg
	var local := global_basis.inverse() * (s.global_position - global_position)
	_open_sign = -1.0 if local.z > 0.0 else 1.0
	set_open(not is_open)
	Events.emit_noise(global_position, 6.0, s, s.team, &"door")
	super.interact(s)


func set_open(o: bool, instant := false) -> void:
	is_open = o
	var target := (PI * 0.5 * _open_sign) if o else 0.0
	if instant:
		_hinge.rotation.y = target
	else:
		create_tween().tween_property(_hinge, "rotation:y", target, 0.6).set_trans(Tween.TRANS_SINE)
	_update_prompt()


func _update_prompt() -> void:
	prompt = "Tür schließen" if is_open else "Tür öffnen"


func serialize() -> Dictionary:
	return {"open": is_open, "sign": _open_sign}


func deserialize(d: Dictionary) -> void:
	_open_sign = d.get("sign", 1.0)
	set_open(d.get("open", false), true)
