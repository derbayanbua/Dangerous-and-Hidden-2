extends "res://tests/test_gameplay.gd"
## Panzer III „panzer01“ (AFRICA1) gegen Raketenwerfer: echte Raketen (Grenade.impact, wie Soldier 0x449290-Weg) aus
## 25 m auf Seite/Front/Heck, Zahl der Treffer bis zur Zerstörung je Waffe. Trupp unverwundbar.
## Erwartung nach Original (hd2.exe 0x449290 → Damage(7, Stärke) → 0x4E1A20, docs/status/panzer_schaden.md).
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_tank_rockets


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.runtime != null, "AFRICA1 geladen")
	if m == null:
		_finish()
		return
	var rt: LsRuntime = m.runtime
	rt.auto_skip = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	var tank := rt.find_frame("panzer01") as Vehicle
	check(tank != null and tank.damage_model != null, "panzer01 mit Schadensmodell")
	if tank == null or tank.damage_model == null:
		_finish()
		return
	var hale: Soldier = m.squad.leader()
	for sm in m.squad.members:
		sm.max_health = 1.0e9
		sm.health = sm.max_health
	# Gegner aus dem Weg (sie würden den Schützen/Panzer stören)
	isolate_enemies([])
	var dm: VehicleDamage = tank.damage_model
	var results := {}
	for wid in [&"panzerfaust", &"bazooka"]:
		var wd := WeaponDB.get_weapon(wid)
		for side in ["links", "rechts", "front", "heck", "heck_hoch"]:
			tank.respawn_now()
			tank.linear_velocity = Vector3.ZERO
			await physics(3)
			var b := dm.root.global_basis      # Achsen des Schadensmodells (Fahrzeugbasis ist um 180° gedreht)
			# Modell: Front −Z (Zone D_ZONE11 HP2200), Heck +Z (D_ZONE07 HP600 matid15), Seiten ±X (HP1600)
			var dirv: Vector3 = {"links": -b.x, "rechts": b.x, "front": -b.z, "heck": b.z, "heck_hoch": b.z}[side]
			dirv.y = 0.0
			dirv = dirv.normalized()
			var target := tank.global_position + tank.global_basis.y * 1.1
			var n := 0
			var zones_hit := []
			while n < 8 and not tank.wrecked:
				for sm in m.squad.members:
					sm.health = sm.max_health
				var before: Array = (dm.serialize()["hp"] as Array).duplicate()
				var g := Grenade.new()
				g.data = wd
				g.thrower = hale
				g.team = hale.team
				g.impact = true
				m.add_child(g)
				# Seiten/„heck_hoch“ von schräg oben (trifft die Kollisionsbox über dem Deck), Front/Heck flach aus 4,5 m (Grubenwand)
				var steep: bool = side in ["links", "rechts", "heck_hoch"]
				g.global_position = target + dirv * (10.0 if steep else 4.5) + Vector3.UP * (2.5 if steep else 0.2)
				g.linear_velocity = (target - g.global_position).normalized() * wd.muzzle_velocity
				n += 1
				g.body_entered.connect(func(bd): if not bd is Vehicle: print("  KONTAKT %s @ %s" % [bd.get_path(), g.global_position]))
				for k in 240:
					await get_tree().physics_frame
					if not is_instance_valid(g):
						break
				await physics(4)
				var after: Array = dm.serialize()["hp"]
				var z := "-"
				for i in after.size():
					if int(after[i]) != int(before[i]):
						z = "%s %d→%d" % [dm.zones[i]["name"], int(before[i]), int(after[i])]
				zones_hit.append(z)
			var key := "%s/%s" % [wid, side]
			results[key] = n if tank.wrecked else -1
			print("MESSUNG %s: %s Treffer bis Zerstörung; Zonen %s" % [key, str(n) if tank.wrecked else ">8", str(zones_hit)])
	# Erwartung [B] Original bzw. [E] Vorgabe: Panzerfaust Seite/Heck ≤ 2, Bazooka Heck 1
	check(results.get("panzerfaust/links", -1) in [1, 2] and results.get("panzerfaust/rechts", -1) in [1, 2],
		"Panzerfaust Seite: höchstens 2 Treffer", "%s/%s" % [results.get("panzerfaust/links"), results.get("panzerfaust/rechts")])
	check(results.get("panzerfaust/heck", -1) == 1, "Panzerfaust Heck: 1 Treffer", str(results.get("panzerfaust/heck")))
	check(results.get("bazooka/heck", -1) == 1, "Bazooka Heck: 1 Treffer", str(results.get("bazooka/heck")))
	check(results.get("panzerfaust/front", -1) > 0 and results.get("bazooka/front", -1) > 0,
		"Front zerstörbar (Panzerfaust/Bazooka)", "%s/%s" % [results.get("panzerfaust/front"), results.get("bazooka/front")])
	check(results.get("bazooka/links", -1) in [2, 3] and results.get("bazooka/rechts", -1) in [2, 3],
		"Bazooka Seite: 3 Treffer (2400 − 1750 = 650 gegen HP 1600)", "%s/%s" % [results.get("bazooka/links"), results.get("bazooka/rechts")])
	# Direkttreffer-Faktor 0x449290: Einzelspieler, Stufe 1, Schütze Spielertrupp × 4; sonst × 1
	# vorher (Strahl nur 1,5 m hinter dem Treffpunkt): Treffer auf die Box über dem Deck ohne Zone → kein Schaden
	check(results.get("panzerfaust/heck_hoch", -1) in [1, 2] and results.get("bazooka/heck_hoch", -1) in [1, 2, 3],
		"Treffer von schräg oben auf Box über dem Deck wirkt (Zone gefunden)", "%s/%s" % [results.get("panzerfaust/heck_hoch"), results.get("bazooka/heck_hoch")])
	check(is_equal_approx(Grenade.direct_hit_factor(hale, true, 1), 4.0) and is_equal_approx(Grenade.direct_hit_factor(hale, true, 2), 1.0)
		and is_equal_approx(Grenade.direct_hit_factor(hale, false, 1), 1.0) and is_equal_approx(Grenade.direct_hit_factor(null, true, 1), 1.0),
		"Raketen-Direkttreffer × 4 nur Einzelspieler/Stufe 1/Spielertrupp")
	_finish()


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
