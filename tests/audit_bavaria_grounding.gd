extends Node
func _ready():
 var m=Game.current_mission()
 while m==null:
  await get_tree().create_timer(.1).timeout
  m=Game.current_mission()
 for species in ["l_tree","l_tree2","l_tree4","e_treb1"]:
  var n=m._templates.prop(species,Vector3.ZERO)
  for mesh in n.find_children("*","MeshInstance3D",true,false):
   var low=INF
   for si in mesh.mesh.get_surface_count():
    var a=mesh.mesh.surface_get_arrays(si)
    for v in a[Mesh.ARRAY_VERTEX]:low=minf(low,(mesh.global_transform*v).y)
   print("GROUND_AUDIT ",species," ",mesh.name," min ",low," xf ",mesh.global_transform.origin)
  n.free()
 m._templates.release()
 get_tree().quit()
