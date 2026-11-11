extends "res://tests/test_gameplay.gd"
## Sonde: Frames nach Namensmuster (--pat=Regex) mit Welt-Kasten, Drehung, Eltern, Sichtbarkeit.
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=probe_a2_frames --pat=kridlo|mriz
## Ergebnis test_output/probe_frames_<mission>.txt

var _out: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_out.append(s)


func _run() -> void:
	for i in 3600:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime") and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	await seconds(2.0)
	var pat := "kridlo|mriz|okno|^g_A1_la"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pat="):
			pat = a.substr(6)
	var re := RegEx.create_from_string("(?i)" + pat)
	for n in m.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if re.search(String(n3.name)) == null:
			continue
		var b := OrigInteractive.world_aabb(n3)
		var path := ""
		var p := n3.get_parent()
		for k in 3:
			if p == null:
				break
			path = String(p.name) + "/" + path
			p = p.get_parent()
		_log("%s vis=%s par=%s pos=%s size=%s euler=%s scale=%s" % [n3.name, n3.is_visible_in_tree(), path,
			b.position, b.size, n3.global_basis.get_euler() * 57.2958, n3.global_basis.get_scale()])
	var f := FileAccess.open("res://test_output/probe_frames_%s.txt" % Game.current_mission_id, FileAccess.WRITE)
	f.store_string("\n".join(_out))
	f.close()
	_finish()
