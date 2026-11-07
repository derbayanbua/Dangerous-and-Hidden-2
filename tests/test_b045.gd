extends "res://tests/test_gameplay.gd"
## B-045 Ragdoll ohne verzerrte Leichen + realistischerer Gore.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_b045
## Teil 1 (Ragdoll): 4 Todesarten (Kopfschuss, Explosion, Sturz, MG-Salve) × 4 Figurmodelle (ge01a, en01, ge03, ci04).
##   Gemessen wird während der Simulation (jedes Bild) und nach dem Einfrieren: Abstand jedes Knochens zu seinem
##   Elternknochen gegen die Ruhepose (|d/d_rest − 1|, Toleranz 5 %) und die Skalierung der Knochenbasis (Skinning,
##   Toleranz 5 %). Zeilen „B045-MESS …“ = Messwerte für den Statusbericht.
## Teil 2 (Gore): Wunden je Kaliber/Zone, Austrittswunde, Blutmenge, Stümpfe, Lachen, Stufe AUS schaltet alles ab.

const MODELS := ["ge01a", "en01", "ge03", "ci04"]
const KINDS := ["kopfschuss", "explosion", "sturz", "mg_salve"]
const TOL := 0.05

var _tpls := {}
var _worst := {}          ## Art → [max Länge sim, max Länge Ende, max Skala, Knochen]


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader() and mission().enemies.size() >= 1:
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	isolate_enemies([])
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	for mb in m.squad.members:
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
			mb.global_position += Vector3(0, 0, 80)
	s.look_yaw = 0.0
	s.global_position = _ground(Vector3(0, 0, 30))
	Settings.ragdoll = true
	var keep_lv: int = Settings.blood_level
	Settings.blood_level = 2
	for mn in MODELS:
		var t: Node3D = OrigWeapons._load(OrigLevel.cache_root() + "/characters/%s.glb" % mn)
		check(t != null, "Figur %s geladen" % mn)
		if t:
			_tpls[mn] = t
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	var row := 0
	for kind in KINDS:
		var batch: Array = []
		for mi in MODELS.size():
			var mn: String = MODELS[mi]
			if not _tpls.has(mn):
				continue
			var pos := _ground(s.global_position + fwd * (8.0 + row * 7.0) + side * (float(mi) - 1.5) * 5.0)
			var e: Soldier = m.spawn_soldier(pos + Vector3.UP * 0.05, PI, Soldier.TEAM_AXIS, "b045_%s_%s" % [kind, mn], ["mp40"],
				Color(0.36, 0.38, 0.33), "stahlhelm", "b045_%s_%s" % [kind, mn])
			e.model.attach_orig((_tpls[mn] as Node3D).duplicate())
			if e.has_node("EnemyBrain"):
				e.get_node("EnemyBrain").enabled = false
			if e.has_node("Perception"):
				e.get_node("Perception").set_physics_process(false)
			e.max_health = 100.0
			e.health = 100.0
			batch.append(e)
		row += 1
		await seconds(0.8)
		if kind == "sturz":
			for e in batch:
				var feet: Vector3 = (e as Soldier).global_position
				_test_block(feet - Vector3.UP * 0.05, Vector3(2.0, 3.0, 2.0), 0.0)
				(e as Soldier).global_position = feet + Vector3.UP * 3.05 + fwd * 0.8
			await seconds(0.8)
		if kind == "kopfschuss" and batch.size() > 0:
			_print_hierarchy((batch[0] as Soldier).model.ragdoll.sk)
		for e in batch:
			_kill(s, e, kind, fwd)
		await _measure(kind, batch)
	for kind in KINDS:
		var w: Array = _worst.get(kind, [9.0, 9.0, 9.0, "-"])
		print("B045-MESS %s: Knochenabstand max. Abweichung während Simulation %.1f %%, nach Ruhe %.1f %%, Skala %.1f %% (Knochen %s)" % [
			kind, w[0] * 100.0, w[1] * 100.0, w[2] * 100.0, w[3]])
		check(w[1] <= TOL, "%s: Knochenabstände nach Ragdoll-Ende = Ruhepose (± 5 %%)" % kind, "%.1f %% (%s)" % [w[1] * 100.0, w[3]])
		check(w[0] <= TOL, "%s: keine Streckung während der Simulation (± 5 %%)" % kind, "%.1f %%" % (w[0] * 100.0))
		check(w[2] <= TOL, "%s: Knochen unskaliert (Mesh nicht verzerrt)" % kind, "%.1f %%" % (w[2] * 100.0))
	await _gore_part(m, s, fwd, side)
	Settings.blood_level = keep_lv
	for t in _tpls.values():
		(t as Node3D).free()
	_finish()


func _kill(s: Soldier, e: Soldier, kind: String, fwd: Vector3) -> void:
	match kind:
		"kopfschuss":
			var zf := _zone(e, "f")
			var tgt: Vector3 = zf.global_position if zf else e.global_position + Vector3.UP * 1.6
			Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
		"explosion":
			var boom := e.global_position - fwd * 1.2 + Vector3.UP * 0.3
			Effects.explosion(boom, 5.0)
			e.apply_hit(500.0, &"torso", s, (e.global_position - boom).normalized())
		"sturz":
			e.health = 1.0
			var tgt := e.global_position + Vector3.UP * 1.2
			Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
		"mg_salve":
			e.health = 60.0
			_burst(s, e, fwd)


func _burst(s: Soldier, e: Soldier, fwd: Vector3) -> void:
	var w := WeaponDB.get_weapon(&"bren")   # MG (items.sav BrenGun, Schaden 55)
	for k in 6:
		if not is_instance_valid(e):
			return
		var zc := _zone(e, "c")
		var tgt: Vector3 = zc.global_position if zc else e.global_position + Vector3.UP * 1.2
		tgt += Vector3(randf_range(-0.1, 0.1), randf_range(-0.15, 0.15), 0)
		Ballistics.fire(s, tgt - fwd * 6.0, fwd, w, [] as Array[RID], s.team)
		await seconds(0.1)


func _measure(kind: String, batch: Array) -> void:
	var t := 0.0
	var worst_bone := ""
	var started := false
	# Während der Simulation nach der Modifier-Kette messen (skeleton_updated = Pose, die das Skinning sieht)
	var sim_max := [0.0]
	var hooks := []
	for e in batch:
		var rd: Ragdoll = (e as Soldier).model.ragdoll
		if rd == null or not is_instance_valid(rd.sk):
			continue
		var sk := rd.sk
		var cb := func() -> void:
			if rd.is_active():
				sim_max[0] = maxf(sim_max[0], stretch(sk)[0])
		sk.skeleton_updated.connect(cb)
		hooks.append([sk, cb])
	while t < 14.0:
		var all_frozen := true
		for e in batch:
			var rd: Ragdoll = (e as Soldier).model.ragdoll
			if rd == null:
				continue
			if rd.is_active():
				started = true
			if not rd.is_frozen():
				all_frozen = false
		if all_frozen and started:
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for h in hooks:
		if is_instance_valid(h[0]):
			(h[0] as Skeleton3D).skeleton_updated.disconnect(h[1])
	check(started, "%s: Ragdolls gestartet" % kind)
	var end_max := 0.0
	var sc_max := 0.0
	var frozen := 0
	for e in batch:
		var rd: Ragdoll = (e as Soldier).model.ragdoll
		if rd and rd.is_frozen():
			frozen += 1
		if rd:
			var r := stretch(rd.sk)
			if r[0] > end_max:
				end_max = r[0]
				worst_bone = "%s/%s" % [r[2], (e as Soldier).name]
			sc_max = maxf(sc_max, r[1])
	check(frozen == batch.size(), "%s: alle Leichen eingefroren" % kind, "%d/%d nach %.1f s" % [frozen, batch.size(), t])
	_worst[kind] = [sim_max[0], end_max, sc_max, worst_bone]


## [größte relative Abweichung Knochenabstand, größte Skalenabweichung, Knochenname] gegen die Ruhepose.
## Abgetrennte (Gore, Skala ~0) Knochen und deren Kinder werden übersprungen.
static func stretch(sk: Skeleton3D) -> Array:
	var worst := 0.0
	var sc := 0.0
	var bn := ""
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var g := sk.get_bone_global_pose(i)
		var s3 := g.basis.get_scale()
		if s3.x < 0.2:
			continue
		sc = maxf(sc, maxf(absf(s3.x - 1.0), maxf(absf(s3.y - 1.0), absf(s3.z - 1.0))))
		if p < 0:
			continue
		if sk.get_bone_global_pose(p).basis.get_scale().x < 0.2:
			continue
		var d_rest := sk.get_bone_global_rest(i).origin.distance_to(sk.get_bone_global_rest(p).origin)
		if d_rest < 0.03:
			continue
		var d := g.origin.distance_to(sk.get_bone_global_pose(p).origin)
		var dev := absf(d / d_rest - 1.0)
		if dev > worst:
			worst = dev
			bn = sk.get_bone_name(i)
	return [worst, sc, bn]


func _print_hierarchy(sk: Skeleton3D) -> void:
	var out := []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		out.append("%s<%s" % [sk.get_bone_name(i), sk.get_bone_name(p) if p >= 0 else "-"])
	print("B045-SKELETT ", " ".join(out))


# --- Teil 2: Gore -------------------------------------------------------------------------------------------------

func _gore_part(m: Mission, s: Soldier, fwd: Vector3, side: Vector3) -> void:
	var fx = Effects.blood_fx
	check(fx != null, "Bluteffekte vorhanden")
	if fx == null or not _tpls.has("ge01a"):
		return
	var base := _ground(s.global_position + side * 30.0 + fwd * 10.0)
	var mk := func(i: int) -> Soldier:
		var e: Soldier = m.spawn_soldier(_ground(base + side * float(i) * 3.5) + Vector3.UP * 0.05, PI, Soldier.TEAM_AXIS,
			"b045_g%d" % i, ["mp40"], Color(0.36, 0.38, 0.33), "stahlhelm", "b045_g%d" % i)
		e.model.attach_orig((_tpls["ge01a"] as Node3D).duplicate())
		if e.has_node("EnemyBrain"):
			e.get_node("EnemyBrain").enabled = false
		if e.has_node("Perception"):
			e.get_node("Perception").set_physics_process(false)
		e.max_health = 400.0
		e.health = 400.0
		return e
	var es: Array = []
	for i in 8:
		es.append(mk.call(i))
	await seconds(0.8)

	# Kaliber: Pistole → kleine Wunde, Gewehr → größere Wunde + Austrittswunde, Blutmenge steigt mit dem Kaliber
	Settings.blood_level = 2
	var w_p: Dictionary = fx.wound_profile(WeaponDB.get_weapon(&"colt"), "torso")
	var w_r: Dictionary = fx.wound_profile(WeaponDB.get_weapon(&"kar98k"), "torso")
	var w_h: Dictionary = fx.wound_profile(WeaponDB.get_weapon(&"kar98k"), "head")
	var w_m: Dictionary = fx.wound_profile(WeaponDB.get_weapon(&"mp40"), "arm")
	print("B045-GORE Wundprofile Pistole %s | Gewehr %s | Gewehr Kopf %s | MP Arm %s" % [w_p, w_r, w_h, w_m])
	check(float(w_r["size"]) > float(w_p["size"]) and float(w_r["blood"]) > float(w_p["blood"]),
		"Gewehrwunde größer/blutiger als Pistolenwunde")
	check(bool(w_r["exit"]) and not bool(w_m["exit"]) or bool(w_r["exit"]), "Gewehr durchschlägt (Austrittswunde)")
	check(float(w_h["blood"]) > float(w_r["blood"]), "Kopftreffer blutet stärker als Rumpftreffer")
	check(float(w_m["blood"]) < float(w_r["blood"]), "Gliedtreffer blutet schwächer")

	# Echter Treffer Gewehr Rumpf → Eintritts- und Austrittswunde an der Figur
	var e0: Soldier = es[0]
	var wc0: int = fx.stats.get("wounds", 0)
	var ex0: int = fx.stats.get("exit_wounds", 0)
	var zc := _zone(e0, "c")
	var tgt: Vector3 = zc.global_position if zc else e0.global_position + Vector3.UP * 1.2
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await frames(4)
	check(int(fx.stats.get("wounds", 0)) > wc0, "Gewehrtreffer: Wunde an der Figur", str(fx.stats))
	check(int(fx.stats.get("exit_wounds", 0)) > ex0, "Gewehrtreffer: Austrittswunde auf der Rückseite", str(fx.stats))
	var bw := e0.find_children("*Wound_*", "", true, false)
	check(bw.size() >= 2, "Wunden hängen an der Figur (Eintritt + Austritt)", str(bw.size()))
	# Pistole: keine Austrittswunde
	var e1: Soldier = es[1]
	ex0 = fx.stats.get("exit_wounds", 0)
	zc = _zone(e1, "c")
	tgt = zc.global_position if zc else e1.global_position + Vector3.UP * 1.2
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"colt"), [] as Array[RID], s.team)
	await frames(4)
	check(int(fx.stats.get("exit_wounds", 0)) == ex0, "Pistolentreffer Rumpf: keine Austrittswunde")
	# Lache: tödlicher Kopfschuss → größere Lache als Gliedtod
	var e2: Soldier = es[2]
	e2.health = 1.0
	var zf := _zone(e2, "f")
	tgt = zf.global_position if zf else e2.global_position + Vector3.UP * 1.6
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await seconds(1.5)
	var pool_sz := 0.0
	for d in fx.pools:
		if is_instance_valid(d) and d.get_meta("owner_soldier", 0) == e2.get_instance_id():
			pool_sz = maxf(pool_sz, float(d.get_meta("pool_max", 0.0)))
	check(pool_sz > 0.0, "Blutlache unter der Leiche (Kopfschuss)", "%.2f m" % pool_sz)
	var e3: Soldier = es[3]
	e3.set_meta("_gore_zone", "leg")
	e3.set_meta("_gore_ms", Time.get_ticks_msec())
	e3.set_meta("_gore_w", WeaponDB.get_weapon(&"colt"))
	e3.die(s, fwd)
	await seconds(1.5)
	var pool_leg := 0.0
	for d in fx.pools:
		if is_instance_valid(d) and d.get_meta("owner_soldier", 0) == e3.get_instance_id():
			pool_leg = maxf(pool_leg, float(d.get_meta("pool_max", 0.0)))
	check(pool_sz > pool_leg, "Lache je Todesart: Kopfschuss Gewehr > Beintreffer Pistole", "%.2f / %.2f m" % [pool_sz, pool_leg])

	# EXTRA GORE: Stumpf mit Knochen/Fleisch, Blutlache am Stumpf, Teil mit Schnittfläche
	Settings.blood_level = Settings.BLOOD_GORE
	Gore.force_roll = 0.0
	var e4: Soldier = es[4]
	e4.health = 1.0
	zf = _zone(e4, "f")
	tgt = zf.global_position if zf else e4.global_position + Vector3.UP * 1.6
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await frames(4)
	var sk4: Skeleton3D = e4.model.ragdoll.sk
	check(int(e4.get_meta("gore_mask", 0)) == Gore.bit("f"), "EXTRA GORE: Kopfschuss Gewehr trennt den Kopf ab")
	var cap := sk4.find_child("GoreStump_*", true, false)
	check(cap != null and cap.find_child("GoreBone", true, false) != null and cap.find_child("GoreFlesh", true, false) != null,
		"Stumpf mit Fleischrand und Knochen", str(cap))
	var piece: RigidBody3D = Gore.pieces().back() if Gore.piece_count() > 0 else null
	check(piece != null and piece.find_child("GoreCut", true, false) != null, "Abgetrenntes Teil mit Schnittfläche")
	await seconds(1.0)
	var stump_pool := false
	for d in fx.pools:
		if is_instance_valid(d) and d.get_meta("owner_soldier", 0) == e4.get_instance_id() and float(d.get_meta("pool_max", 0.0)) >= pool_sz:
			stump_pool = true
	check(stump_pool, "EXTRA GORE: große Lache am Stumpf")
	var r4 := stretch(sk4)
	check(r4[0] <= TOL, "EXTRA GORE: Rest der Leiche unverzerrt", "%.1f %%" % (r4[0] * 100.0))
	Gore.force_roll = -1.0

	# Stufe AUS: kein Blut, keine Wunden, keine Abtrennung
	Settings.blood_level = 0
	var e5: Soldier = es[5]
	var wc: int = fx.stats.get("wounds", 0)
	var pools0: int = fx.pools.size()
	e5.health = 1.0
	zf = _zone(e5, "f")
	tgt = zf.global_position if zf else e5.global_position + Vector3.UP * 1.6
	Ballistics.fire(s, tgt - fwd * 6.0, fwd, WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await seconds(1.5)
	check(int(fx.stats.get("wounds", 0)) == wc and fx.pools.size() <= pools0 and e5.find_children("*Wound*", "", true, false).is_empty(),
		"Stufe AUS: keine Wunden/Lachen")
	check(Gore.mask_node(e5.model.ragdoll.sk) == null and e5.model.ragdoll.sk.find_child("GoreStump_*", true, false) == null,
		"Stufe AUS: keine Abtrennung")
	Settings.blood_level = 2


func _ground(p: Vector3) -> Vector3:
	var h := mission().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.z), Vector3(p.x, -80.0, p.z), 1))
	return h.position if not h.is_empty() else p


func _zone(e: Soldier, bone: String) -> Node3D:
	for hb in e.find_children("Hitbox_*", "Hitbox", true, false):
		if String(hb.get_meta("bone", "")) == bone and (hb as Hitbox).zone != Helmet.ZONE:
			return hb
	return null
