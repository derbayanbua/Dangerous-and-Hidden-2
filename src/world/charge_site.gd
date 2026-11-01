class_name ChargeSite
extends Interactable
## Ziel für eine Sprengladung (z. B. Funksender). Nach dem Anbringen läuft
## ein Zeitzünder; die Explosion zerstört das Ziel und ist weit hörbar.

signal destroyed

@export var fuse := 20.0
@export var target_name := "Ziel"
var armed := false
var is_destroyed := false
var time_left := 0.0
var target_node: Node3D        ## wird bei Zerstörung ausgeblendet/ersetzt
var _charge_mesh: MeshInstance3D
var _planter: Soldier


func _ready() -> void:
	super._ready()
	prompt = "Sprengladung anbringen (%s)" % target_name


func can_interact(_s: Soldier) -> bool:
	return enabled and not armed and not is_destroyed


func interact(s: Soldier) -> void:
	if not can_interact(s):
		return
	_planter = s
	arm(fuse)
	Events.say("Sprengladung scharf: %d Sekunden! In Deckung!" % int(fuse), 4.0)
	super.interact(s)


func arm(seconds: float) -> void:
	armed = true
	time_left = seconds
	_charge_mesh = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.2, 0.12, 0.1)
	_charge_mesh.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.5, 0.3)
	_charge_mesh.material_override = m
	_charge_mesh.position = Vector3(0, 0.8, 0)
	add_child(_charge_mesh)


func _physics_process(delta: float) -> void:
	if not armed or is_destroyed:
		return
	time_left -= delta
	if time_left <= 0.0:
		detonate()


func detonate() -> void:
	armed = false
	is_destroyed = true
	enabled = false
	if _charge_mesh:
		_charge_mesh.queue_free()
	var pos := global_position + Vector3.UP
	# G-006 (B-026): Stärke/Radius der Sprengladung des Spielers (PlacedCharge, linearer Originalabfall über
	# WeaponDB.explosion_damage) statt fest 250/8 m; trifft auch Fahrzeuge/Zerstörbares; Lärm-Team = Team des Anbringenden.
	var r := PlacedCharge.CHARGE_RADIUS
	var by: Soldier = _planter if is_instance_valid(_planter) else null
	Effects.explosion(pos, r * 0.85, [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_CHARGE_OUT])   # „Explosion Naloz Ext“
	Events.emit_noise(pos, 400.0, by, by.team if by else Soldier.TEAM_ALLIED, &"explosion")
	WeaponDB.apply_blast(get_tree(), get_world_3d().direct_space_state, pos, r, PlacedCharge.CHARGE_STRENGTH, by)
	if is_instance_valid(target_node):
		target_node.visible = false
		for c in target_node.find_children("*", "CollisionShape3D", true, false):
			(c as CollisionShape3D).disabled = true
	destroyed.emit()


func serialize() -> Dictionary:
	return {"armed": armed, "destroyed": is_destroyed, "time_left": time_left}


func deserialize(d: Dictionary) -> void:
	if d.get("destroyed", false):
		is_destroyed = true
		enabled = false
		if is_instance_valid(target_node):
			target_node.visible = false
			for c in target_node.find_children("*", "CollisionShape3D", true, false):
				(c as CollisionShape3D).disabled = true
	elif d.get("armed", false):
		arm(d.get("time_left", fuse))
