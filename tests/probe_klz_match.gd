extends "res://tests/test_gameplay.gd"
## Sonde: Welt-Kasten jedes Frames mit Original-Kollisionskasten (tree.klz XTOBB, z gespiegelt) vergleichen.
## Eingabe test_output/xt_<ordner>.json ({name: [minx,miny,minz,maxx,maxy,maxz]}, „a.b“ = Kind b von a).
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=probe_klz_match [--xt=res://test_output/xt_arctic2.json]
## Ergebnis test_output/klz_match_<mission>.txt (Abweichung Mitte/Größe > 0,25 m)

var _out: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_out.append(s)


func _run() -> void:
	for i in 4800:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime") and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	await seconds(2.0)
	var path := String(Game.cli.get("xt", "res://test_output/xt_arctic2.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var bad := 0
	var ok := 0
	var missing := 0
	for key: String in data:
		var parts := key.split(".")
		var n: Node3D = m.runtime.find_frame(parts[0])
		if n and parts.size() > 1:
			n = n.find_child(parts[1], true, false) as Node3D
		if n == null:
			missing += 1
			continue
		var has_mesh := n is MeshInstance3D or not n.find_children("*", "MeshInstance3D", true, false).is_empty()
		if not has_mesh:
			continue
		var a: Array = data[key]
		var ob := AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3] - a[0], a[4] - a[1], a[5] - a[2]))
		var b := OrigInteractive.world_aabb(n)
		var dc := b.get_center().distance_to(ob.get_center())
		var ds := (b.size - ob.size).abs()
		if dc > 0.25 or ds.x > 0.25 or ds.y > 0.25 or ds.z > 0.25:
			bad += 1
			_log("ABWEICHUNG %s vis=%s dMitte=%.2f orig=%s/%s nachbau=%s/%s" % [key, n.is_visible_in_tree(), dc, ob.get_center(),
				ob.size, b.get_center(), b.size])
		else:
			ok += 1
	_log("ERGEBNIS_SONDE ok=%d abweichend=%d fehlend=%d" % [ok, bad, missing])
	var f := FileAccess.open("res://test_output/klz_match_%s.txt" % Game.current_mission_id, FileAccess.WRITE)
	f.store_string("\n".join(_out))
	f.close()
	_finish()
