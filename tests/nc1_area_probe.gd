extends "res://tests/test_orig_complete.gd"
## Agent Normandie/Tschechien-1: wie test_orig_complete, zusätzlich beim Missionsende Positionen und
## Einsatzgebiet-Bits (mission_area.gd) aller Trupp-Mitglieder sowie die letzten Löser-Teleports.
##   tools\godot.cmd --headless -- --mission=no2_schwerttaenzer --autoplay=nc1_area_probe --speed=2


var _last_flags := {}


func _physics_process(d: float) -> void:
	super._physics_process(d)
	if m == null or not is_instance_valid(m):
		return
	var area := m.get_node_or_null("MissionArea")
	if area == null:
		area = m.find_child("MissionArea", true, false)
	if area == null or m.squad == null:
		return
	for s in m.squad.members:
		if not is_instance_valid(s):
			continue
		var fl: int = area.flags_at(s.global_position)
		if fl != int(_last_flags.get(s.name, 0)):
			_last_flags[s.name] = fl
			print("GRENZE %s flags=0x%x pos=%s t=%d s" % [s.name, fl, str(s.global_position),
				(Time.get_ticks_msec() - _t0) / 1000])


func _on_mission_finished(success: bool, reason: String) -> void:
	if m and is_instance_valid(m) and m.squad:
		for s in m.squad.members:
			if is_instance_valid(s):
				print("ENDE-POS %s alive=%s pos=%s" % [s.name, str(s.alive), str(s.global_position)])
	super._on_mission_finished(success, reason)
