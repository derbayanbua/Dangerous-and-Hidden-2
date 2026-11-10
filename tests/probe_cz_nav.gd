extends "res://tests/test_gameplay.gd"
## Gap-Analyse Tschechien (09.11.2026): Erreichbarkeit von Skript-Wegpunkten im Navmesh.
##   --pairs=Soldat:Wegpunkt,Soldat:Wegpunkt …  (Namen wie im Originalskript, Groß-/Kleinschreibung egal)
## Je Paar: Navmesh-Pfad vom Soldaten zum Wegpunkt, Restabstand Pfadende↔Ziel, Höhe des nächsten Netzpunkts. Zeilen NAV_PAAR.


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	await seconds(3.0)
	var map := m.get_viewport().world_3d.navigation_map
	for pair in String(Game.cli.get("pairs", "")).split(",", false):
		var ab := pair.split(":")
		var s: Node3D = m.runtime.find_frame(ab[0])
		var w: Node3D = m.runtime.find_frame(ab[1])
		if s == null or w == null:
			print("NAV_PAAR %s fehlt (soldat=%s wp=%s)" % [pair, s != null, w != null])
			continue
		var path := NavigationServer3D.map_get_path(map, s.global_position, w.global_position, true)
		var gap := INF if path.is_empty() else path[path.size() - 1].distance_to(w.global_position)
		var cp := NavigationServer3D.map_get_closest_point(map, w.global_position)
		print("NAV_PAAR %s von=%s ziel=%s pfadpunkte=%d luecke=%.2f netz_am_ziel=%.2f" % [pair, str(s.global_position.round()),
			str(w.global_position.round()), path.size(), gap, cp.distance_to(w.global_position)])
	check(true, "Navmesh-Paare geprüft")
	_finish()
