extends RefCounted
## Filmtexturen der Level (Original MISSIONS\<m>\meshplayer.bin → orig_cache/<m>/meshplayer.json,
## D:\Workspace_D\tools\fmt_meshplayer.py): Wasserflächen u. a. tragen einen Film aus GameMovie (Arctic1.bik,
## Iceberg.bik, more2.bik, Normandy3.bik; 256×256, Schleife) als Videotextur (hd2.exe 0x4847E4 „GameMovie\%s“).
## Der Film läuft in einem unsichtbaren VideoStreamPlayer; seine Textur ersetzt die Grundfarbtextur aller Meshes
## des Frames. Ohne konvertierten Film (tools/convert_movies.ps1) bleibt die statische Originaltextur.


static func apply(mission: Node, orig: OrigLevel) -> Array:
	var applied: Array = []
	if orig == null:
		return applied
	var d = LsRuntime._read_json(orig.mission_dir + "/meshplayer.json")
	if typeof(d) != TYPE_DICTIONARY:
		return applied
	for e in d.get("entries", []):
		var movie := String(e.get("movie", "")).get_basename()
		var frame := String(e.get("frame", ""))
		var path := Game.movie_path(movie)
		var node: Node3D = orig.nodes.get(frame)
		if node == null:
			for k in orig.nodes:
				if String(k).to_lower() == frame.to_lower():
					node = orig.nodes[k]
					break
		if path == "" or node == null:
			continue
		var vp := VideoStreamPlayer.new()
		vp.name = "MovieTexture_" + movie
		vp.loop = true
		vp.volume_db = -80.0
		vp.size = Vector2(4, 4)
		vp.modulate.a = 0.0
		vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vs := VideoStreamTheora.new()
		vs.file = path
		vp.stream = vs
		var layer := CanvasLayer.new()
		layer.name = "MovieTextureLayer"
		layer.layer = -100
		mission.add_child(layer)
		layer.add_child(vp)
		vp.play()
		var tex := vp.get_video_texture()
		if tex == null:
			continue
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi in meshes:
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var mat := m3.get_active_material(si) as StandardMaterial3D
				if mat == null:
					continue
				var nm := mat.duplicate() as StandardMaterial3D
				nm.albedo_texture = tex
				m3.set_surface_override_material(si, nm)
		applied.append([movie, frame])
	return applied
