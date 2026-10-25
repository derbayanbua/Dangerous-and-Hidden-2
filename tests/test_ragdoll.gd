extends "res://tests/test_gameplay.gd"
## B-016 Ragdoll (src/actors/ragdoll.gd): Übergang Todesclip → Physik mit Impuls aus Schussrichtung, Ruhe → Einfrieren,
## Leichenort/Trefferzonen/Durchsuchen folgen, Explosion schleudert und weckt ruhende Leichen, Endpose exportieren/
## übernehmen (Netz/Spielstand), Option aus = Original-Todesclip, Fahrzeug, Obergrenze gleichzeitiger Ragdolls.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_ragdoll


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader() and mission().enemies.size() >= 10:
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	var keep_rd: bool = Settings.ragdoll
	check(Settings.ragdoll, "Option Ragdoll standardmäßig an")
	var es: Array = m.enemies.slice(0, 10)
	var ids: Array = []
	for e in es:
		ids.append(e.persistent_id)
	isolate_enemies(ids)
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	for mb in m.squad.members:
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
			mb.global_position += Vector3(0, 0, 80)
	# ebene Fläche südlich des Gehöfts (CLAUDE.md Testhinweise: z ≈ 20, x −25…25)
	s.look_yaw = 0.0
	s.global_position = _ground(Vector3(0, 0, 30))
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	var side := fwd.cross(Vector3.UP)
	for i in es.size():
		var e: Soldier = es[i]
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
		e.global_position = _ground(s.global_position + fwd * 8.0 + side * (float(i) - 4.5) * 4.6) + Vector3.UP * 0.05
		e.velocity = Vector3.ZERO
		e.max_health = 100.0
	# Übungseinsatz m01 nutzt die Platzhalterpuppe → Original-Figur ge01a anhängen (wie test_animations)
	_tpl = OrigWeapons._load(OrigLevel.cache_root() + "/characters/ge01a.glb")
	check(_tpl != null, "Original-Figur ge01a geladen")
	if _tpl == null:
		_finish()
		return
	for e in es:
		(e as Soldier).model.attach_orig(_tpl.duplicate())
	await seconds(1.0)
	var e0: Soldier = es[0]
	var rd0: Ragdoll = e0.model.ragdoll
	check(rd0 != null, "Original-Figur hat einen Ragdoll (Körper erst beim Tod)", str(e0.model.orig_figure))
	if rd0 == null:
		_finish()
		return
	check(rd0.bodies.is_empty() and not is_instance_valid(rd0.sim), "Lebende Figur ohne Physikkörper (Leistung)")

	# --- Schuss: Todesclip-Anfang → Ragdoll mit Impuls in Schussrichtung ---
	check(e0.is_on_floor(), "Testgegner steht auf dem Boden", str(e0.global_position))
	var p_start := rd0.pelvis_position()
	e0.health = 1.0
	var tgt := e0.global_position + Vector3.UP * 1.25
	var org := tgt - fwd * 6.0
	Ballistics.fire(s, org, (tgt - org).normalized(), WeaponDB.get_weapon(&"kar98k"), [] as Array[RID], s.team)
	await frames(4)
	check(not e0.alive, "Treffer tötet den Testgegner")
	check(e0.model.death_clip_name != "", "Original-Todesclip läuft zuerst", e0.model.death_clip_name)
	check(rd0.is_pending() or rd0.is_active(), "Ragdoll übernimmt nach dem Clipanfang", str(rd0.state))
	await seconds(0.3)
	check(rd0.is_active(), "Ragdoll simuliert", str(rd0.state))
	check(rd0.bodies.size() == 11, "11 Physikkörper am Original-Skelett", str(rd0.bodies.keys()))
	check(rd0.build_dev < 0.05, "Körper beim Bau in der Ruhelage (Gelenkgrenzen relativ zur T-Haltung)", "%.3f m" % rd0.build_dev)
	check(rd0.last_impulse.dot(fwd) > 10.0, "Impuls in Schussrichtung", str(rd0.last_impulse))
	var hit_bone_ok := String(e0.get_meta("_rd_hit", [Vector3.ZERO, ""])[1]) != ""
	check(hit_bone_ok, "Ballistik meldet Trefferpunkt und Gelenk", str(e0.get_meta("_rd_hit", [])))
	# Führungsphase: Körper folgen dem Original-Todesclip, danach volle Physik
	check(rd0.drive_total > 0.0 or rd0.drive_time > 0.0, "Führungsphase aktiv (Körper folgen dem Todesclip)",
		"%.2f s, Clip %s" % [rd0.drive_total, rd0._clip])
	var tw := 0.0
	while rd0.is_driving() and tw < 2.0:
		await seconds(0.05)
		tw += 0.05
	check(not rd0.is_driving() and rd0.drive_time >= Ragdoll.DRIVE_MIN - 0.05, "Führung klingt ab, dann volle Physik", "%.2f s" % rd0.drive_time)
	check(rd0.drive_target_travel > 0.1, "Zielpose aus dem Clip bewegt sich (Einknicken)", "%.2f m" % rd0.drive_target_travel)
	check(rd0.drive_err_max < 0.25, "Becken folgt der Clip-Pose bei starker Führung", "%.3f m" % rd0.drive_err_max)
	var anim_off := true
	for ap in e0.model.find_children("*", "AnimationPlayer", true, false):
		anim_off = anim_off and not (ap as AnimationPlayer).active
	check(anim_off, "Animation nach der Führungsphase angehalten")
	# Trefferzonen folgen dem simulierten Rumpf
	var zc: Node3D = _zone(e0, "c")
	var rb_c: PhysicalBone3D = rd0.bodies.get("c")
	check(zc != null and rb_c != null and zc.global_position.distance_to(rb_c.global_position) < 0.15,
		"Trefferzone Rumpf folgt dem Ragdoll", "%s / %s" % [zc.global_position if zc else "-", rb_c.global_position if rb_c else "-"])
	var t := 0.0
	while not rd0.is_frozen() and t < 12.0:
		await seconds(0.25)
		t += 0.25
	check(rd0.is_frozen(), "Leiche kommt zur Ruhe und wird eingefroren", "%.1f s" % t)
	check(not rb_c.is_simulating_physics(), "Physik nach dem Einfrieren aus")
	var p_end := rd0.pelvis_position()
	check((p_end - p_start).dot(fwd) > 0.05, "Körper fällt in Schussrichtung", "%.2f m" % (p_end - p_start).dot(fwd))
	var gy := _ground(p_end).y
	check(p_end.y < p_start.y - 0.4 and p_end.y > gy - 0.05 and p_end.y < gy + 0.45, "Becken liegt am Boden (nicht durchgefallen)",
		"%.2f → %.2f, Boden %.2f" % [p_start.y, p_end.y, gy])
	check(t < Ragdoll.MAX_SIM, "Ruhe erkannt (nicht erst nach der Höchstdauer)", "%.1f s" % t)
	check(e0.corpse_pinned and Vector2(e0.global_position.x - p_end.x, e0.global_position.z - p_end.z).length() < 0.05,
		"Leichenort (Soldat) unter dem Becken festgehalten", str(e0.global_position))
	check(_joint_ok(rd0.sk, "p", 140.0) and _joint_ok(rd0.sk, "t", 140.0) and _joint_ok(rd0.sk, "i", 150.0) and _joint_ok(rd0.sk, "m", 150.0),
		"Knie/Ellbogen innerhalb der Gelenkgrenzen", "%.0f/%.0f/%.0f/%.0f°" % [_joint_deg(rd0.sk, "p"), _joint_deg(rd0.sk, "t"),
			_joint_deg(rd0.sk, "i"), _joint_deg(rd0.sk, "m")])
	var hold_pose := rd0.pelvis_position()
	var zc_pos: Vector3 = zc.global_position if zc else Vector3.ZERO
	await seconds(1.0)
	check(rd0.pelvis_position().distance_to(hold_pose) < 0.01, "Endpose bleibt stehen (keine Animation überschreibt sie)")
	check(zc != null and zc.global_position.distance_to(zc_pos) < 0.01 and zc.global_position.distance_to(p_end) < 0.9,
		"Trefferzone Rumpf liegt an der eingefrorenen Leiche")
	# Durchsuchen: Aktion an der liegenden Leiche, funktioniert
	var loot: Pickups.Loot = null
	for c in e0.get_children():
		if c is Pickups.Loot:
			loot = c
	check(loot != null and loot.enabled, "Leiche durchsuchbar (Pickups.Loot aktiv)")
	if loot:
		check(Vector2(loot.global_position.x - p_end.x, loot.global_position.z - p_end.z).length() < 0.3,
			"Durchsuchen-Punkt an der liegenden Leiche", str(loot.global_position))
		var mags0 := s.weapons[0].reserve if s.weapons.size() > 0 and s.weapons[0] else 0
		s.global_position = loot.global_position + side * 0.6
		loot.interact(s)
		check(loot.looted, "Leiche durchsucht (Inventar übernommen)", "Reserve %d → %d" % [mags0, s.weapons[0].reserve if s.weapons.size() > 0 and s.weapons[0] else 0])
	var fx = Effects.blood_fx
	if fx and Settings.blood_level > 0:
		var pool_ok := false
		for d in fx.pools:
			if is_instance_valid(d) and d.get_meta("owner_soldier", 0) == e0.get_instance_id() \
					and Vector2(d.global_position.x - p_end.x, d.global_position.z - p_end.z).length() < 1.0:
				pool_ok = true
		check(pool_ok, "Blutlache (B-006) unter der Ragdoll-Leiche")

	# --- Explosion: schleudert den Sterbenden ---
	var e1: Soldier = es[1]
	var rd1: Ragdoll = e1.model.ragdoll
	var p1 := rd1.pelvis_position() if rd1 else e1.global_position
	var boom := e1.global_position - fwd * 1.5 + Vector3.UP * 0.2
	Effects.explosion(boom, 5.0)
	e1.apply_hit(500.0, &"torso", s, (e1.global_position - boom).normalized())
	await frames(3)
	check(rd1 != null and rd1.is_active(), "Explosion: Ragdoll sofort", str(rd1.state) if rd1 else "-")
	var max_y := p1.y
	t = 0.0
	while rd1 and not rd1.is_frozen() and t < 12.0:
		max_y = maxf(max_y, rd1.pelvis_position().y)
		await seconds(0.1)
		t += 0.1
	var d1 := Vector2(rd1.pelvis_position().x - p1.x, rd1.pelvis_position().z - p1.z).length() if rd1 else 0.0
	check(rd1 != null and rd1.is_frozen() and d1 > 0.8 and d1 < 15.0 and max_y > p1.y + 0.1, "Explosion schleudert den Körper", "%.2f m weit, %.2f m hoch" % [d1, max_y - p1.y])
	check(d1 > Vector2(p_end.x - p_start.x, p_end.z - p_start.z).length(), "Explosion wirft weiter als ein Gewehrtreffer")

	# --- Explosion weckt eine ruhende Leiche ---
	var before := rd0.pelvis_position()
	Effects.explosion(before + side * 1.2, 4.0)
	await frames(3)
	check(rd0.is_active() or rd0.is_pending(), "Ruhende Leiche wird von der Explosion geweckt", str(rd0.state))
	check(not e0.corpse_pinned, "Leiche während der Bewegung nicht festgehalten")
	t = 0.0
	while not rd0.is_frozen() and t < 12.0:
		await seconds(0.25)
		t += 0.25
	check(rd0.is_frozen() and rd0.pelvis_position().distance_to(before) > 0.3, "Leiche verschoben und wieder eingefroren",
		"%.2f m" % rd0.pelvis_position().distance_to(before))

	# --- Endpose: Export → andere Figur (Netz/Spät-Beitritt) und Spielstand ---
	var pose: PackedFloat32Array = e0.model.corpse_pose()
	check(pose.size() == 4 + 7 * rd0.sk.get_bone_count(), "Endpose exportiert", str(pose.size()))
	var e2: Soldier = es[2]
	e2.become_corpse()
	check(not e2.alive and e2.is_in_group("corpses"), "Leiche ohne Todesablauf (Spät-Beitritt)")
	check(e2.model.apply_corpse_pose(pose), "Endpose an einer anderen Figur übernommen")
	await frames(2)
	check(_pose_diff(rd0.sk, e2.model.ragdoll.sk) < 0.01 and e2.global_position.distance_to(e0.global_position) < 0.01,
		"Übernommene Endpose = Server-Lage", "%.4f" % _pose_diff(rd0.sk, e2.model.ragdoll.sk))
	var e3: Soldier = es[3]
	var save := e0.serialize()
	check(save.has("corpse_pose"), "Spielstand enthält die Endpose")
	e3.deserialize(save)
	await frames(2)
	check(not e3.alive and _pose_diff(rd0.sk, e3.model.ragdoll.sk) < 0.01, "Spielstand stellt die Leichenlage wieder her",
		"%.4f" % _pose_diff(rd0.sk, e3.model.ragdoll.sk))

	# --- Option aus: Original-Todesanimation ---
	Settings.ragdoll = false
	var e4: Soldier = es[4]
	e4.die(s, fwd)
	await seconds(0.5)
	var rd4: Ragdoll = e4.model.ragdoll
	check(rd4 != null and rd4.state == Ragdoll.State.IDLE and rd4.bodies.is_empty(), "Option aus: kein Ragdoll")
	var ap4 := e4.model.orig_figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(ap4 != null and ap4.active and ap4.current_animation == e4.model.death_clip_name, "Option aus: Original-Todesclip spielt",
		e4.model.death_clip_name)
	Settings.ragdoll = true

	# --- Tod im Fahrzeug: fällt heraus, Ragdoll sofort mit Fahrzeuggeschwindigkeit ---
	var veh: Vehicle = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is Vehicle:
			veh = v
			break
	if veh:
		var e5: Soldier = es[5]
		e5.global_position = veh.global_position + Vector3(2, 0, 0)
		var ok := veh.board(e5, false)
		await frames(3)
		check(ok and e5.vehicle == veh, "Testgegner sitzt im Fahrzeug")
		e5.die(s, fwd)
		await frames(3)
		check(e5.vehicle == null and e5.model.ragdoll.is_active(), "Tod im Fahrzeug: fällt heraus, Ragdoll sofort",
			str(e5.model.ragdoll.state))
	else:
		check(true, "(kein Fahrzeug in der Mission – Fahrzeugfall übersprungen)")

	# --- Obergrenze gleichzeitig simulierter Ragdolls ---
	var rest: Array = []
	for i in Ragdoll.MAX_ACTIVE + 2:
		var pos := _ground(s.global_position + fwd * 14.0 + side * (float(i) - 5.0) * 2.5) + Vector3.UP * 0.05
		var x: Soldier = m.spawn_soldier(pos, s.look_yaw + PI, Soldier.TEAM_AXIS, "rd%d" % i, ["mp40"], Color(0.36, 0.38, 0.33), "stahlhelm", "rd_cap_%d" % i)
		x.model.attach_orig(_tpl.duplicate())
		rest.append(x)
	var f0: int = Ragdoll.stats["forced"]
	await seconds(0.5)
	for e in rest:
		(e as Soldier).die(s, fwd)
	await seconds(0.4)
	check(Ragdoll.active_count() <= Ragdoll.MAX_ACTIVE, "Höchstens %d Ragdolls gleichzeitig" % Ragdoll.MAX_ACTIVE,
		"%d aktiv, %d Tote" % [Ragdoll.active_count(), rest.size()])
	if rest.size() + 1 > Ragdoll.MAX_ACTIVE:
		check(Ragdoll.stats["forced"] > f0, "Älteste Ragdolls werden vorzeitig eingefroren", str(Ragdoll.stats["forced"] - f0))
	print("Ragdoll-Statistik: ", Ragdoll.stats)
	Settings.ragdoll = keep_rd
	_tpl.free()
	_finish()


var _tpl: Node3D


func _ground(p: Vector3) -> Vector3:
	var h := mission().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.z), Vector3(p.x, -80.0, p.z), 1))
	if h.is_empty():
		print("DBG kein Boden bei ", p)
		return p
	return h.position


func _zone(e: Soldier, bone: String) -> Node3D:
	for hb in e.find_children("Hitbox_*", "Hitbox", true, false):
		if String(hb.get_meta("bone", "")) == bone and (hb as Hitbox).zone != Helmet.ZONE:
			return hb
	return null


## Winkel der lokalen Knochenrotation gegenüber der Ruhelage (T-Haltung) in Grad
func _joint_deg(sk: Skeleton3D, bone: String) -> float:
	var bi := sk.find_bone(bone)
	if bi < 0:
		return 0.0
	var q := sk.get_bone_rest(bi).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(bi)
	return rad_to_deg(q.get_angle())


func _joint_ok(sk: Skeleton3D, bone: String, max_deg: float) -> bool:
	return _joint_deg(sk, bone) <= max_deg


## größte Abweichung der Knochenposen (Skelettraum) zweier gleich aufgebauter Skelette
func _pose_diff(a: Skeleton3D, b: Skeleton3D) -> float:
	if a.get_bone_count() != b.get_bone_count():
		return 99.0
	var worst := 0.0
	for i in a.get_bone_count():
		worst = maxf(worst, a.get_bone_global_pose(i).origin.distance_to(b.get_bone_global_pose(i).origin))
	return worst
