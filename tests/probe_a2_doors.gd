extends "res://tests/test_gameplay.gd"
## Sonde ARCTIC2-Türen (09.11.2026, Zusatzauftrag Gap-Analyse): fliegende Gitterflügel und blockierte Durchgänge.
##   tools\run_locked.ps1 -Name a2doors -Log test_output\probe_a2_doors.log -GodotArgs "--headless -- --mission=a2_erkundung --autoplay=probe_a2_doors"
## Je Tür: Flügel-Mitte vor/nach dem Öffnen (Abstand zur Angel – „fliegt“, wenn > Flügelbreite + 0,5 m), danach
## Kapseldurchgang (Soldat) durch die Türmitte in beide Richtungen; Blocker mit Name/Ebene/Herkunft.
## Zusätzlich: alle Knoten unter dynamic_root, die sich in 20 s Leerlauf > 3 m bewegen. Ergebnis test_output/probe_a2_doors.txt

const TestDoors := preload("res://tests/test_normandie_doors.gd")

var _out: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_out.append(s)


func _desc(o: Object) -> String:
	if o == null:
		return "-"
	var n := o as Node
	var p := n.get_parent()
	var lay := int(o.get("collision_layer")) if "collision_layer" in o else 0
	var src := "static" if mission().static_root and mission().static_root.is_ancestor_of(n) else "dyn"
	return "%s/%s[%s,L%d]" % [p.name if p else "-", n.name, src, lay]


func _center(n: Node3D) -> Vector3:
	var b := OrigInteractive.world_aabb(n)
	return b.get_center()


func _run() -> void:
	for i in 3600:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime") and mission().nav_ready:
			break
		await get_tree().process_frame
	var m := mission()
	m.finished = true
	if m.runtime.in_cutscene:
		m.runtime.end_cutscene()
	await seconds(1.0)
	var me: Soldier = m.squad.leader()
	me.max_health = 1e9
	me.health = 1e9
	me.set_meta("protect_until", 1e12)
	isolate_enemies([])
	var fnd := String(Game.cli.get("find", ""))
	if fnd != "":
		for n in m.find_children(fnd, "", true, false):
			var metas := PackedStringArray()
			for k in n.get_meta_list():
				metas.append("%s=%s" % [k, str(n.get_meta(k)).left(40)])
			var bodies := PackedStringArray()
			for b in n.find_children("*", "CollisionObject3D", true, false):
				bodies.append("%s L%d" % [b.name, (b as CollisionObject3D).collision_layer])
			_log("FIND %s klasse=%s aabb=%s meta=%s körper=%s" % [n.get_path(), n.get_class(),
				OrigInteractive.world_aabb(n as Node3D) if n is Node3D else "-", ",".join(metas), ",".join(bodies)])
		var f0 := FileAccess.open("res://test_output/probe_a2_find.txt", FileAccess.WRITE)
		if f0:
			f0.store_string("\n".join(_out))
		check(true, "Suche fertig", fnd)
		_finish()
		return
	# Leerlauf: Bewegung dynamischer Knoten
	var pos0 := {}
	for n in m.dynamic_root.find_children("*", "Node3D", true, false):
		pos0[n] = (n as Node3D).global_position
	await seconds(20.0)
	for n in pos0:
		if is_instance_valid(n) and not (n is Soldier) and (n as Node3D).global_position.distance_to(pos0[n]) > 3.0:
			_log("LEERLAUF_BEWEGT %s %.1f m" % [_desc(n), (n as Node3D).global_position.distance_to(pos0[n])])
	var it: OrigInteractive = m.get("interactive")
	var space := m.get_viewport().world_3d.direct_space_state
	var bad := 0
	for k in it.controls:
		var d = it.controls[k]
		if not (d is OrigInteractive.OrigDoor):
			continue
		var leaf: Node3D = d.frame
		if leaf == null:
			continue
		var hinge: Vector3 = leaf.global_position
		var c0 := _center(leaf)
		var w := OrigInteractive.world_aabb(leaf).size.length()
		d.locked = false
		d.set_open(true)
		await seconds(3.0)
		var c1 := _center(leaf)
		var fly := c1.distance_to(hinge) > w + 0.5 or absf(c1.y - c0.y) > 0.5
		# Kapseldurchgang durch die Türöffnung (geschlossene Lage = Türmitte)
		var st: Array = TestDoors.stand_for(m, d)
		var nrm: Vector3 = st[1]
		var mid: Vector3 = st[2]
		var block := "-"
		var gq := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 0.5, mid + Vector3.DOWN * 3.0, 1)
		var gh := space.intersect_ray(gq)
		var floor_y: float = gh.position.y if not gh.is_empty() else mid.y - 1.0
		for side in [1.0, -1.0]:
			var a: Vector3 = Vector3(mid.x, floor_y + 0.1, mid.z) - nrm * side * 1.2
			me.global_position = a
			me.velocity = Vector3.ZERO
			await frames(2)
			var kc := KinematicCollision3D.new()
			if me.test_move(me.global_transform, nrm * side * 2.4, kc):
				var o := kc.get_collider()
				if o != leaf and not (o is Node and leaf.is_ancestor_of(o)):
					block = _desc(o) + " @" + str(kc.get_position().snapped(Vector3.ONE * 0.1))
		var line := "TUER %-24s flügel %.2f->%.2f m (Angel) dy=%.2f %s durchgang=%s statisch=%s pos=%s" % [k,
			c0.distance_to(hinge), c1.distance_to(hinge), c1.y - c0.y, "FLIEGT" if fly else "ok", block, d.static_leaf, mid.snapped(Vector3.ONE * 0.1)]
		_log(line)
		if fly:
			bad += 1
		d.set_open(false)
		await seconds(0.5)
	_log("A2DOORS_SUMME fliegt=%d" % bad)
	var f := FileAccess.open("res://test_output/probe_a2_doors.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out))
	check(true, "Sonde fertig", "fliegt=%d" % bad)
	_finish()
