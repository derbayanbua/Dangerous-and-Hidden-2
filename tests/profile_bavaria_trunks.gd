extends Node
func _ready():
 run.call_deferred()
func run():
 var m=Game.current_mission()
 while m==null or not m.nav_ready:
  await get_tree().create_timer(.1).timeout
  m=Game.current_mission()
 for species in ["l_tree","l_tree2","l_tree4","e_treb1"]:
  var n=m._templates.prop(species,Vector3.ZERO,0,1)
  for stem in n.find_children("*","MeshInstance3D",true,false):
   if not String(stem.name) in ["tree","hi1kmen"]:continue
   var vertices=[]
   var lo=INF
   var hi=-INF
   for si in stem.mesh.get_surface_count():
    for v in stem.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
     var q=stem.global_transform*v
     vertices.append(q)
     lo=minf(lo,q.y);hi=maxf(hi,q.y)
   print("PROFILE ",species," ",stem.name," low=",lo," high=",hi)
   for i in 20:
    var a=Vector3(INF,INF,INF);var b=Vector3(-INF,-INF,-INF);var count=0
    for v in vertices:
     if v.y>=lo+i*.25 and v.y<lo+(i+1)*.25:
      a=a.min(v);b=b.max(v);count+=1
    if count:print("SLICE ",i*.25," count=",count," xz=",Vector2(b.x-a.x,b.z-a.z)," center=",(a+b)*.5)
  n.free()
 m._templates.release()
 get_tree().quit()
