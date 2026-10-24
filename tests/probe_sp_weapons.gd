extends "res://tests/test_gameplay.gd"
## Sonde (nur Diagnose): Gesundheit, Figuren, Trefferzonen und Waffen im Einzelspieler einer Originalmission.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=probe_sp_weapons


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	await seconds(2.0)
	var m := mission()
	print("PROBE Schwierigkeit ", Game.difficulty(), " Mission ", Game.current_mission_id)
	for s in m.squad.members:
		var ws: Array = s.weapons.map(func(w): return String(w.data.id) if w else "")
		var fig: Node3D = s.model.orig_figure
		print("PROBE TRUPP %s pid=%s hp=%.1f/%.1f team=%d waffen=%s figur=%s scale=%s zonen=%d sas=%s" % [s.soldier_name, s.persistent_id,
			s.health, s.max_health, s.team, ws, fig.name if fig else "-", str(fig.global_basis.get_scale()) if fig else "-",
			s.model.orig_zones.size(), str(s.get_meta("sas", -1))])
	var n := 0
	for e in m.enemies:
		n += 1
		if n > 12:
			break
		var p: Dictionary = e.get_meta("orig_params", {})
		var fig: Node3D = e.model.orig_figure
		var puppet := 0
		for h in e.model.root_pivot.find_children("*", "Hitbox", true, false):
			if (h as Hitbox).collision_layer != 0:
				puppet += 1
		var zs := ""
		for hb in e.model.orig_zones:
			var cs := hb.get_child(0) as CollisionShape3D
			zs += "%s:%s@%.2f " % [hb.zone, hb.get_meta("bone"), cs.global_position.y - e.global_position.y]
		print("PROBE GEGNER %s hp=%.1f/%.1f orig=%s modell=%s figurscale=%s rootscale=%s zonen=%d puppe=%d helm=%s waffen=%s" % [e.persistent_id,
			e.health, e.max_health, str(p.get("health", "-")), str(e.get_meta("orig_model", "")),
			str(fig.global_basis.get_scale()) if fig else "-", str(e.global_basis.get_scale()), e.model.orig_zones.size(), puppet,
			str(WeaponDB.wears_helmet(e)), str(e.weapons.map(func(w): return String(w.data.id) if w else ""))])
		print("PROBE   ", zs)
	_finish()
