extends SceneTree
## B-018: Sitz der Helmmodelle am Kopf mehrerer Original-Figuren (Bindungslage).
##   tools\godot.cmd --headless --script res://tests/probe_helmet_fit.gd [-- fig1 fig2 ...]
## Gibt je Figur aus: Kopfgelenk f Ruhelage vs. Bindungslage (Skin), HÃ¼llkiste der Kopf-Vertices (Gewicht f) und
## HÃ¼llkiste typischer Helmmodelle im Figurraum.

const HELMS := ["b_ge_helm1", "b_en_helm1", "b_en_helmpar", "b_ge_cap1"]


func _load(p: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(p, st) != OK:
		return null
	return doc.generate_scene(st)


func _initialize() -> void:
	var root_dir := ProjectSettings.globalize_path("res://orig_cache")
	var figs: Array = Array(OS.get_cmdline_user_args())
	if figs.is_empty():
		figs = ["ge01a", "ge03", "en01", "en08", "ge10"]
	for h in HELMS:
		var hp := "%s/heads/%s.glb" % [root_dir, h]
		if not FileAccess.file_exists(hp):
			print("HELM fehlt ", h)
			continue
		var hn := _load(hp) as Node3D
		root.add_child(hn)
		print("HELM %s Kiste %s" % [h, _bounds(hn)])
		hn.queue_free()
	for f in figs:
		var p := "%s/characters/%s.glb" % [root_dir, f]
		if not FileAccess.file_exists(p):
			print("FIGUR fehlt ", f)
			continue
		var sc := _load(p) as Node3D
		root.add_child(sc)
		var sk := sc.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var bi := sk.find_bone("f")
		var rest := _rel(sc, sk) * sk.get_bone_global_rest(bi)
		var line := "FIGUR %s f-Ruhe %s basisY %s" % [f, rest.origin, rest.basis.y]
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.skin == null or m.mesh == null:
				continue
			for b in m.skin.get_bind_count():
				var bn := m.skin.get_bind_name(b)
				var idx := m.skin.get_bind_bone(b) if bn == "" else sk.find_bone(bn)
				if idx == bi:
					var bind := _rel(sc, m) * m.skin.get_bind_pose(b).affine_inverse()
					line += " | bind(%s) %s" % [m.name, bind.origin]
			# Kopf-Vertices (stÃ¤rkstes Gewicht auf f)
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			var n := 0
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bo = arr[Mesh.ARRAY_BONES]
				var we = arr[Mesh.ARRAY_WEIGHTS]
				if bo == null or we == null:
					continue
				var k: int = bo.size() / max(v.size(), 1)
				for i in v.size():
					var best := 0
					for j in k:
						if we[i * k + j] > we[i * k + best]:
							best = j
					var sb := int(bo[i * k + best])
					var bone := sb
					if sb < m.skin.get_bind_count():
						var bn2 := m.skin.get_bind_name(sb)
						bone = m.skin.get_bind_bone(sb) if bn2 == "" else sk.find_bone(bn2)
					if bone == bi:
						var w := _rel(sc, m) * v[i]
						lo = lo.min(w)
						hi = hi.max(w)
						n += 1
			if n > 0:
				line += " | kopf(%s) n=%d %s..%s" % [m.name, n, lo, hi]
		print(line)
		sc.queue_free()
	quit(0)


static func _rel(anc: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != anc:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _bounds(r: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or String(m.name).to_lower().begins_with("shadow"):
			continue
		var bb := _rel(r, m) * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out
