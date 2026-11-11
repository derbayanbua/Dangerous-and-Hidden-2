extends "res://tests/test_gameplay.gd"
## Sonde: alle Türen/statischen Flügel einer Karte mit Welt-Kasten (Breite/Höhe), Zustand, Achse.
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=probe_a2_doors
## Ergebnis test_output/probe_doors_<mission>.txt

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
	await seconds(3.0)
	for d in m.dynamic_root.get_children():
		if not (d.has_method("set_open") or String(d.name).begins_with("Door_") or String(d.name).begins_with("LeafDoor_")):
			continue
		if not d.get("frame"):
			continue
		var b := OrigInteractive.world_aabb(d.frame)
		var horiz := maxf(b.size.x, b.size.z)
		var flag := "QUER" if horiz > b.size.y * 1.15 and b.size.y < 1.6 else ""
		_log("%s %s leaf=%s state=%d amt=%.2f/%.2f axis=%s slide=%s pos=%s size=%s rot=%s %s" % [d.name, d.frame.name,
			d.get("static_leaf"), d.state, d.amount, d.open_amount, d.axis, d.slide, b.position, b.size,
			d.frame.global_basis.get_euler() * 57.3, flag])
	var f := FileAccess.open("res://test_output/probe_doors_%s.txt" % Game.current_mission_id, FileAccess.WRITE)
	f.store_string("\n".join(_out))
	f.close()
	_finish()
