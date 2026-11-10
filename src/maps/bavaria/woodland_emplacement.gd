extends RefCounted
## MG42 aus dem Spiel, im begehbaren Holzhaus mit echtem Netz-/Waffenvertrag.
const Placement := preload("res://src/maps/bavaria/field_emplacement.gd")
var gun: OrigInteractive.OrigEmplacement
var frame: Node3D
var target := Vector3.ZERO
func build(m: Mission) -> void:
	var house: Node3D = m.static_root.get_node("woodland_shed")
	var size: Vector2 = house.get_meta("footprint_size")
	target = m.pixel([575,554],1.5)
	frame = Node3D.new()
	frame.name = "WoodlandMG42"
	m.static_root.add_child(frame)
	frame.position = house.to_global(Vector3(-size.x*0.5+0.45,0.02,0))
	var direction := target-frame.position
	frame.rotation.y = atan2(-direction.x,-direction.z)
	var path := OrigLevel.cache_root()+"/africa1/models/w_mg42stand.glb"
	var model := OrigLevel.parse_glb(path)
	if model==null:
		push_error("Woodland MG42 Modell fehlt")
		return
	frame.add_child(model)
	var pivot: Node3D = model.find_child("HORT00",true,false)
	# Original-Schwenkachse als horizontalen Ursprung verwenden; Originalmaße erhalten.
	var pivot_local := frame.to_local(pivot.global_position)
	model.position = Vector3(-pivot_local.x,0,-pivot_local.z)
	m._templates._mesh_colliders(model.find_child("Stojan",true,false)) # Nur das massive Dreibein, keine Ziel-/Kamerabilder.
	gun = Placement.FieldFlak.new()
	gun.name = "WoodlandMG42_Bedienung"
	m.dynamic_root.add_child(gun)
	gun.init(null,frame,{"name":"bavaria_woodland_mg42","inventory":[33,33,33,33,33,33]},WeaponDB.from_orig(33,true),0)
	gun.operator_offset = Vector3(0,0.1,1.70)
	gun.setup_rig({"left":25.0,"right":25.0,"up":15.0,"down":5.0})
	# Original-SEAT liegt weit hinter dem normalisierten Modell; freier Platz im Schuppen.
	gun.seat = null
	gun.global_position = gun.gunner_spot()+Vector3.UP*0.5
	gun.base_yaw = frame.rotation.y
	gun.add_to_group("bavaria_shed_mg42")
	# Fester hölzerner Waffenbock trägt die originale MG-Halterung.
	m.lb.box(Vector3.ZERO,Vector3(0.18,1.22,0.18),"darkwood",0,true,frame)
	m.lb.box(Vector3(0,1.17,0),Vector3(0.65,0.06,0.32),"darkwood",0,true,frame)
	frame.set_meta("source",path)
	frame.set_meta("firing_target",target)
	m._templates.reused_models += 1
	print("BAVARIA MG42: Bediener=",gun.gunner_spot()," Mündung=",gun.shot_origin()," Ziel=",target)
