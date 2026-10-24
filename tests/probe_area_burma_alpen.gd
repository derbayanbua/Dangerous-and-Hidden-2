extends "res://tests/test_orig_complete.gd"
## Sonde (Agent Burma/Alpen): Löser test_orig_complete; bei Missionsende Lage des Trupps und Einsatzgebiet-Bits ausgeben.
##   tools\godot.cmd --headless -- --mission=bu2_bergkoenig --autoplay=probe_area_burma_alpen


func _on_mission_finished(success: bool, reason: String) -> void:
	var area: Node = null
	if is_instance_valid(rt):
		area = rt.get_node_or_null("MissionArea")
	if area == null and is_instance_valid(m):
		area = m.find_child("MissionArea", true, false)
	for s in m.squad.members:
		print("AREA Ende %s: %s pos=%s bits=%s fahrzeug=%s" % [success, s.name, s.global_position,
			area.flags_at(s.global_position) if area else "-", s.vehicle != null])
	super._on_mission_finished(success, reason)


func _teleport_to_pos(p: Vector3) -> void:
	super._teleport_to_pos(p)
	print("AREA Teleport %s" % p)
