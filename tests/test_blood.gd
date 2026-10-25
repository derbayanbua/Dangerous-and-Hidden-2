extends "res://tests/test_gameplay.gd"
## Bluteffekte (src/combat/blood_fx.gd): Spritzer, Strahl, Wand-/Bodendecals, wachsende Lachen (Leiche, bereits
## liegende Leiche), Obergrenzen, Stufen AUS/ORIGINAL/MEHR, echter Projektiltreffer; Kleidungsblut am Knochen,
## Messer-/Splittertreffer, Blutspur Verwundeter, Bildschirmrand.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_blood --profiles_dir=user://blut


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader() and mission().enemies.size() >= 4:
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	var fx = Effects.blood_fx
	check(fx != null, "BloodFx am Autoload Effects")
	var keep_level: int = Settings.blood_level
	if FileAccess.file_exists(OrigLevel.cache_root().path_join("effects/blood/x_blood05.png")):
		check(fx.tex("x_blood05") != Effects._blood_tex and fx.tex("x_blood05").get_width() == 128,
			"Original-Textur x_blood05 aus orig_cache geladen")
	var es: Array = m.enemies.slice(0, 4)
	var ids: Array = []
	for e in es:
		ids.append(e.persistent_id)
	isolate_enemies(ids)
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	for mb in m.squad.members:   # Kameraden würden die Testgegner erschießen
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
			mb.global_position += Vector3(0, 0, 80)
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	var side := fwd.cross(Vector3.UP)
	for i in es.size():
		var e: Soldier = es[i]
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
		e.global_position = s.global_position + fwd * 6.0 + side * (float(i) - 1.5) * 3.0
		e.velocity = Vector3.ZERO
	await seconds(0.5)
	var e0: Soldier = es[0]
	var wall := _test_block(e0.global_position + fwd * 1.6 - Vector3.UP * 0.5, Vector3(3.0, 3.0, 0.3), s.look_yaw)
	await frames(3)

	# --- MEHR (Standard) ---
	check(Settings.blood_level == 2 or Settings.BLOOD_NAMES.size() == 3, "Option Blut dreistufig", str(Settings.blood_level))
	Settings.blood_level = 2
	var st0: Dictionary = fx.stats.duplicate()
	var head: Vector3 = e0.global_position + Vector3.UP * 1.55
	Effects.blood(head, -fwd, fwd, &"head", e0)
	await frames(2)
	check(fx.stats["sprays"] - st0["sprays"] >= 2, "Kopftreffer: Austritts- und Eintrittsspritzer (GPU-Partikel)",
		str(fx.stats["sprays"] - st0["sprays"]))
	var spray: GPUParticles3D = fx.sprays.back() if fx.sprays.size() > 0 and is_instance_valid(fx.sprays.back()) else null
	check(spray != null and spray.amount >= 6, "Spritzer mit Partikeln", str(spray.amount) if spray else "-")
	check(fx.stats["splats"] - st0["splats"] >= 3, "Spritzer-Decals an Wand und Boden",
		str(fx.stats["splats"] - st0["splats"]))
	var on_wall := false
	for d in fx.splats:
		if is_instance_valid(d) and absf((d.global_position - e0.global_position).dot(fwd) - 1.45) < 0.3:
			on_wall = true
	check(on_wall, "Decal auf der Wand hinter dem Getroffenen (Raycast)")
	check(fx.stats["jets"] - st0["jets"] == 1 and fx.jets.size() >= 1, "Kopftreffer: Blutstrahl", str(fx.jets.size()))
	var ratios := []
	for i in 6:
		await seconds(0.12)
		if fx.jets.size() > 0 and is_instance_valid(fx.jets.back()["node"]):
			ratios.append(snappedf(fx.jets.back()["node"].amount_ratio, 0.01))
	check(ratios.size() >= 3 and ratios.max() - ratios.min() > 0.05, "Strahl pulsiert/klingt ab", str(ratios))
	await seconds(1.6)
	check(fx.jets.is_empty(), "Strahl endet nach höchstens 2 s", str(fx.jets.size()))
	# Gliedmaßentreffer schwächer als Kopftreffer
	Effects.blood(head - Vector3.UP * 0.8, -fwd, fwd, &"leg", e0)
	await frames(2)
	var leg_amount: int = fx.sprays[fx.sprays.size() - 2].amount
	Effects.blood(head, -fwd, fwd, &"head", e0)
	await frames(2)
	var head_amount: int = fx.sprays[fx.sprays.size() - 2].amount
	check(head_amount > leg_amount, "Kopf spritzt stärker als Bein", "%d > %d" % [head_amount, leg_amount])

	# --- Blut auf der Kleidung (Decal am Knochen) ---
	var w_head: Decal = null
	for w in fx.wounds:
		if is_instance_valid(w) and w.get_meta("owner_soldier", 0) == e0.get_instance_id():
			if w_head == null or w.global_position.y > w_head.global_position.y:
				w_head = w
	check(fx.stats["wounds"] - st0["wounds"] >= 2 and w_head != null, "Treffer: Blut auf der Kleidung (Ein- und Austritt)",
		str(fx.stats["wounds"] - st0["wounds"]))
	var has_skel := e0.find_children("*", "Skeleton3D", true, false).size() > 0
	if w_head:
		check(w_head.cull_mask == fx.WOUND_LAYER, "Kleidungs-Decal trifft nur Figurenmeshes (Renderebene 20)")
		check(not has_skel or w_head.get_parent() is BoneAttachment3D, "Kleidungs-Decal hängt am Knochen",
			w_head.get_parent().get_class())
		var marked := false
		for mi in e0.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).is_visible_in_tree() and (mi as MeshInstance3D).layers & fx.WOUND_LAYER:
				marked = true
		check(marked, "Figurenmeshes empfangen Kleidungsblut")
	var wy0: float = w_head.global_position.y if w_head else 0.0

	# --- Lache unter der Leiche, wächst ---
	var p0: int = fx.stats["pools"]
	e0.die(s, fwd)
	await seconds(1.6)
	check(e0.has_meta("_blood_pool") and _pool_near(fx, fx.body_center(e0)) != null, "Leiche bekommt eine Blutlache", str(fx.stats["pools"] - p0))
	var pool = _pool_near(fx, fx.body_center(e0))
	var sz1: float = pool.size.x if pool else 0.0
	await seconds(2.5)
	var sz2: float = pool.size.x if pool and is_instance_valid(pool) else 0.0
	check(sz2 > sz1 + 0.1, "Lache wächst", "%.2f → %.2f" % [sz1, sz2])
	check(pool != null and pool.global_basis.y.dot(Vector3.UP) > 0.7, "Lache auf den Boden ausgerichtet")
	check(w_head != null and is_instance_valid(w_head) and w_head.global_position.y < wy0 - 0.4,
		"Kleidungsblut folgt der fallenden Leiche (Knochen statt fester Position)",
		"%.2f → %.2f" % [wy0, w_head.global_position.y] if w_head and is_instance_valid(w_head) else "-")
	check(pool != null and pool.has_meta("follow_until"), "Lache folgt der Körpermitte während sie wächst")
	# --- bereits liegende Leiche (z. B. aus Spielstand) ---
	var e1: Soldier = es[1]
	e1.alive = false
	e1.add_to_group("corpses")
	await seconds(1.5)
	check(e1.has_meta("_blood_pool") and _pool_near(fx, fx.body_center(e1)) != null, "Bereits liegende Leiche bekommt eine Lache")
	# --- echter Projektiltreffer ---
	var sp0: int = fx.stats["sprays"]
	var e2: Soldier = es[2]
	var tgt := e2.global_position + Vector3.UP * 1.2
	var org := tgt - fwd * 5.0
	Ballistics.fire(s, org, (tgt - org).normalized(), WeaponDB.get_weapon(&"kar98k") if s.current_weapon() == null else s.current_weapon().data, [] as Array[RID], s.team)
	await seconds(0.4)
	print("Projektil: e2 alive=%s health=%.0f hits=%d" % [e2.alive, e2.health, Ballistics.hits])
	check(fx.stats["sprays"] > sp0, "Echter Projektiltreffer erzeugt Blutspritzer", str(fx.stats["sprays"] - sp0))
	check(fx.stats["extra_hits"] == st0["extra_hits"], "Projektiltreffer wird nicht doppelt (ohne Ersatzblut)",
		str(fx.stats["extra_hits"] - st0["extra_hits"]))

	# --- Messer/Splitter: Treffer ohne Projektil ---
	var e3: Soldier = es[3]
	var x0: Dictionary = fx.stats.duplicate()
	e3.apply_hit(5.0, &"torso", s, fwd)
	await frames(3)
	check(fx.stats["extra_hits"] == x0["extra_hits"] + 1 and fx.stats["sprays"] > x0["sprays"] and fx.stats["wounds"] > x0["wounds"],
		"Messer-/Splittertreffer erzeugt Blut (Spritzer + Kleidung)", str(fx.stats["extra_hits"] - x0["extra_hits"]))

	# --- Blutspur eines laufenden Verwundeten ---
	e3.health = e3.max_health * 0.3
	var t0: int = fx.stats["trails"]
	for i in 6:
		e3.global_position += side * 1.3
		await seconds(0.35)
	check(fx.stats["trails"] - t0 >= 3, "Verwundeter hinterlässt beim Laufen eine Blutspur", str(fx.stats["trails"] - t0))
	e3.health = e3.max_health
	t0 = fx.stats["trails"]
	for i in 4:
		e3.global_position -= side * 1.3
		await seconds(0.35)
	check(fx.stats["trails"] == t0, "Unverletzter läuft ohne Spur")

	# --- Treffer-Feedback am Bildschirmrand (aktiver Soldat) ---
	var active = m.controller.active if m.get("controller") else null
	check(active == s, "Testsoldat ist der aktive Soldat", str(active))
	var ed0: int = fx.stats["edge"]
	s.apply_hit(4.0, &"torso", e3, -fwd)
	await frames(3)
	check(fx.stats["edge"] == ed0 + 1 and fx.edge_layer != null and fx.edge_layer.visible and fx.edge_alpha > 0.2,
		"Treffer am Spieler: roter Bildschirmrand mit Spritzern", "%d %.2f" % [fx.stats["edge"] - ed0, fx.edge_alpha])
	var vis_splats := 0
	for sp in fx._edge_splats:
		if sp.visible and sp.texture != null:
			vis_splats += 1
	check(vis_splats >= 2, "Randspritzer mit Blut-Textur", str(vis_splats))
	await seconds(1.6)
	check(fx.edge_alpha < 0.1, "Bildschirmrand klingt ab", "%.2f" % fx.edge_alpha)
	s.health = s.max_health

	# --- Obergrenzen ---
	for i in 120:
		Effects.blood(head, -fwd, fwd, &"torso", e2)
	await frames(2)
	check(fx.splats.size() <= fx.MAX_SPLATS and fx.sprays.size() <= fx.MAX_SPRAYS and fx.jets.size() <= fx.MAX_JETS,
		"Obergrenzen (Ringpuffer) eingehalten", "%d/%d/%d" % [fx.splats.size(), fx.sprays.size(), fx.jets.size()])
	for c in get_tree().get_nodes_in_group("corpses"):
		c.remove_meta("_blood_pool")
	for i in 30:
		fx._pool_for(e1, 1.0, 0.0)
	await frames(2)
	check(fx.pools.size() <= fx.MAX_POOLS, "Lachen begrenzt", str(fx.pools.size()))
	var e2w := 0
	for w in fx.wounds:
		if is_instance_valid(w) and w.get_meta("owner_soldier", 0) == e2.get_instance_id():
			e2w += 1
	check(fx.wounds.size() <= fx.MAX_WOUNDS and e2w <= fx.MAX_WOUNDS_PER, "Kleidungsblut begrenzt (gesamt/je Figur)",
		"%d/%d" % [fx.wounds.size(), e2w])
	check(fx.trails.size() <= fx.MAX_TRAILS, "Blutspur begrenzt", str(fx.trails.size()))
	await seconds(2.0)

	# --- Kleidungsblut an einem Skelett (Original-Figuren/Ragdoll): eigene BoneAttachment3D am nächsten Knochen ---
	var fig := Node3D.new()
	m.add_child(fig)
	fig.global_position = s.global_position + side * 10.0
	var sk := Skeleton3D.new()
	fig.add_child(sk)
	sk.add_bone("becken")
	sk.add_bone("kopf")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(0, Transform3D(Basis(), Vector3(0, 1.0, 0)))
	sk.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 0.6, 0)))
	sk.reset_bone_poses()
	await frames(2)
	var wk: Decal = fx.wound(fig, fig.global_position + Vector3(0, 1.55, 0.1), Vector3.BACK, 0.2)
	var ba := wk.get_parent() as BoneAttachment3D if wk else null
	check(ba != null and ba.bone_name == "kopf", "Skelett: Kleidungsblut an BoneAttachment3D des nächsten Knochens",
		ba.bone_name if ba else "-")
	var wp0: Vector3 = wk.global_position if wk else Vector3.ZERO
	sk.set_bone_pose_position(1, Vector3(0.5, 0.6, 0))   # Knochen bewegt sich (Animation/Ragdoll)
	await frames(3)
	check(wk != null and wk.global_position.distance_to(wp0 + Vector3(0.5, 0, 0)) < 0.05, "Skelett: Kleidungsblut folgt dem Knochen",
		str(wk.global_position - wp0) if wk else "-")
	fig.queue_free()

	# --- ORIGINAL ---
	Settings.blood_level = 1
	var o0: Dictionary = fx.stats.duplicate()
	Effects.blood(head, -fwd, fwd, &"head", e2)
	await frames(2)
	check(fx.stats["sprays"] == o0["sprays"] and fx.stats["jets"] == o0["jets"] and fx.stats["splats"] == o0["splats"] + 1,
		"ORIGINAL: Spritzer + ein Bodenfleck, kein Strahl/Wanddecal")

	# --- AUS ---
	Settings.blood = false
	check(Settings.blood_level == 0, "Original-Schalter BLUTFLECKEN nein = Blut AUS")
	var a0: Dictionary = fx.stats.duplicate()
	Effects.blood(head, -fwd, fwd, &"head", e2)
	check(fx.wound(e2, head, -fwd, 0.2) == null, "AUS: kein Kleidungsblut")
	e3.health = e3.max_health * 0.3
	e3.apply_hit(3.0, &"torso", s, fwd)          # Messer-/Splittertreffer
	s.apply_hit(2.0, &"torso", e3, -fwd)         # Spielertreffer → Rand
	for i in 3:
		e3.global_position += side * 1.3       # laufender Verwundeter
		await seconds(0.35)
	check(fx.edge_layer == null or not fx.edge_layer.visible, "AUS: kein Bildschirmrand")
	s.health = s.max_health
	e3.die(s, fwd)
	await seconds(2.0)
	check(fx.stats == a0, "AUS: keine Partikel, Decals, Strahlen, Lachen, Spuren, Kleidungsblut, Rand", str(fx.stats))
	check(_pool_near(fx, fx.body_center(e3)) == null, "AUS: Leiche ohne Lache", "meta %s" % e3.has_meta("_blood_pool"))
	Settings.blood = true
	check(Settings.blood_level == 2, "BLUTFLECKEN ja = Standard MEHR")
	Settings.blood_level = keep_level
	_finish()


func _pool_near(fx, p: Vector3) -> Decal:
	for d in fx.pools:
		if is_instance_valid(d) and Vector2(d.global_position.x - p.x, d.global_position.z - p.z).length() < 1.0:
			return d
	return null