extends Node
## Independent audit of placed props and actual MultiMesh transforms.
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("MultiMesh-Kontrolle benötigt echten Renderer; Dummy liefert Identität.")
		get_tree().quit(2)
		return
	var m=Game.current_mission()
	while m==null or not m.nav_ready:
		await get_tree().create_timer(.1).timeout
		m=Game.current_mission()
	for group in ["bavaria_tree_batches","bavaria_hedge_batches"]:
		for node in get_tree().get_nodes_in_group(group):
			var mesh: Mesh=node.multimesh.mesh
			var lo:=INF
			var hi:=-INF
			for index in node.multimesh.instance_count:
				var xf: Transform3D=node.global_transform*node.multimesh.get_instance_transform(index)
				var bottom:=INF
				for surface in mesh.get_surface_count():
					for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						bottom=minf(bottom,(xf*vertex).y)
				lo=minf(lo,bottom)
				hi=maxf(hi,bottom)
			print("CONTROL_BATCH ",group," ",node.name," ",mesh.resource_name," count ",node.multimesh.instance_count," bottom_range ",lo," to ",hi)
	for greenhouse in get_tree().get_nodes_in_group("bavaria_greenhouses"):
		print("CONTROL_GREENHOUSE ",greenhouse.global_position," xf ",greenhouse.global_transform)
	get_tree().quit()
