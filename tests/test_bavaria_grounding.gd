extends Node
var passed := 0
var failed := 0
func check(ok: bool, label: String):
 if ok: passed+=1; print("PASS ",label)
 else: failed+=1; print("FAIL ",label)
func _ready():
 _run.call_deferred()
func _run():
 var m=Game.current_mission()
 while m==null or not m.nav_ready:
  await get_tree().create_timer(.1).timeout
  m=Game.current_mission()
 for species in ["l_tree","l_tree2","l_tree4","e_treb1"]:
  for size in [.06,.25,.8,1.5]:
   var n=m._templates.prop(species,Vector3(2100,0,2100),.73,size)
   var bounds: AABB=m._templates.vertex_bounds(n,Transform3D.IDENTITY)
   check(absf(bounds.position.y)<.002,"Actual transformed ground vertices %s %.2f: %.5f"%[species,size,bounds.position.y])
   n.free()
 var parent=Node3D.new()
 m.static_root.add_child(parent)
 var bush=m.scene_details._border_bush(Vector3(2100,0,2100),.73,2.4,parent)
 var leaf=bush.get_child(0)
 var leaf_bounds: AABB=m._templates.vertex_bounds(leaf,bush.transform)
 check(absf(leaf_bounds.position.y)<.002,"Randlaub beruehrt Boden mit echten Blattvertices")
 check(absf(leaf_bounds.size.y-2.4)<.002,"Randlaub erreicht gewuenschte echte Hoehe")
 parent.free()
 m._templates.release()
 var space=m.get_world_3d().direct_space_state
 var beams=get_tree().get_nodes_in_group("bavaria_ground_beams")
 check(beams.size()==24,"Four grounded fallen timbers in each of six ruins")
 for n in beams:
  var bounds: AABB=m._templates.vertex_bounds(n,Transform3D.IDENTITY)
  check(absf(bounds.position.y)<.002,"Fallen timber lowest vertex on ground "+str(n.get_path()))
 var supports=get_tree().get_nodes_in_group("bavaria_roof_supports")
 check(supports.size()==24,"Four actual roof supports per ruin")
 for n in supports:
  var tip: Vector3=n.get_parent().to_global(n.get_meta("roof_point"))
  var query=PhysicsRayQueryParameters3D.create(tip+Vector3.UP*.35,tip-Vector3.UP*.25,1,[n.get_rid()])
  var hit=space.intersect_ray(query)
  check(not hit.is_empty() and hit.collider.get_parent()==n.get_parent(),"Support meets retained roof "+str(n.get_path()))
 print("BAVARIA GROUNDING: %d passed, %d failed"%[passed,failed])
 get_tree().quit(0 if failed==0 else 1)
