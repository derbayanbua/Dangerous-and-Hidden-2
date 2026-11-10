extends Node
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ",label)
	else: failed += 1; print("FAIL ",label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m=Game.current_mission()
	while m==null or not m.nav_ready:
		await get_tree().create_timer(.1).timeout
		m=Game.current_mission()
	var panels := 0
	for house in get_tree().get_nodes_in_group("bavaria_greenhouses"):
		for panel in house.get_children():
			if not panel is Node3D or absf(panel.rotation.x)<0.01:continue
			var mi: MeshInstance3D = null
			for child in panel.get_children():
				if child is MeshInstance3D:mi=child;break
			if mi==null or not mi.mesh is BoxMesh or mi.mesh.size.y>0.03:continue
			var extent: float=mi.mesh.size.z*0.5
			var a: Vector3=panel.transform*mi.transform*Vector3(0,0,-extent)
			var b: Vector3=panel.transform*mi.transform*Vector3(0,0,extent)
			panels+=1
			check(absf(minf(a.y,b.y)-2.0)<0.012,"Gewächshaus Dach-Traufanschluss "+str(house.get_path()))
			check(absf(maxf(a.y,b.y)-3.0)<0.012,"Gewächshaus Dach-Firstanschluss "+str(house.get_path()))
	check(panels==4,"Zwei Dachflächen an beiden Gewächshäusern geprüft")
	print("BAVARIA CONTROL: %d passed, %d failed"%[passed,failed])
	get_tree().quit(0 if failed==0 else 1)


