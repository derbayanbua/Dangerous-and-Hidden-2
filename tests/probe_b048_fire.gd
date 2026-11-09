extends "res://tests/test_gameplay.gd"
## B-048 Messsonde: Schüsse/min und Trefferquote der Gegner gegen den (unverwundbaren) Trupp.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=probe_b048_fire [--b048=0] [--secs=90] [--tag=]
## Vorgehen: Trupp unverwundbar, Führer 25 m vor die nächsten 3 Gegner (Sicht), Zeitfenster messen.
## Zählt shot_fired der Gegner und soldier_damaged am Trupp mit Gegner als Angreifer. Ausgabe test_output/b048_fire_<tag>.txt.

var shots := 0
var hits := 0
var by_enemy := {}
var grenades := 0
var cover_samples := 0
var cover_hits := 0
var low_samples := 0


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	m.finished = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for i in 1800:
		if m.nav_ready:
			break
		await get_tree().process_frame
	for sm in m.squad.members:
		sm.max_health = 1.0e9
		sm.health = sm.max_health
	var c: Soldier = m.squad.leader()
	var foes: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != c.team and s.team != Soldier.TEAM_NEUTRAL and s.get_node_or_null("EnemyBrain"):
			foes.append(s)
	foes.sort_custom(func(a, b): return a.global_position.distance_to(c.global_position) < b.global_position.distance_to(c.global_position))
	# ai_orig2: --grenadiers=1 → nur Gegner mit Granaten (Originalausrüstung) messen
	if String(Game.cli.get("grenadiers", "0")) == "1":
		foes = foes.filter(func(s): return s.weapons.size() > WeaponData.Slot.GRENADE and s.weapons[WeaponData.Slot.GRENADE] != null \
			and s.weapons[WeaponData.Slot.GRENADE].total_ammo() > 0)
		print("GRENADIERE %d: %s" % [foes.size(), str(foes.map(func(s): return s.name))])
	if Game.cli.has("foe"):
		var pick = foes.filter(func(s): return String(s.name) == String(Game.cli["foe"]))
		if not pick.is_empty():
			foes.erase(pick[0])
			foes.push_front(pick[0])
	check(not foes.is_empty(), "Gegner vorhanden", str(foes.size()))
	if foes.is_empty():
		_finish()
		return
	var f0: Soldier = foes[0]
	var fwd := f0.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := c.get_world_3d().direct_space_state
	var tp := f0.global_position + fwd * float(Game.cli.get("dist", "25"))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 20, tp + Vector3.DOWN * 40, 1))
	c.global_position = ((hit.position as Vector3) + Vector3.UP * 0.3) if not hit.is_empty() else tp
	c.velocity = Vector3.ZERO
	for s in foes.slice(0, 3):
		s.shot_fired.connect(func(_w): shots += 1; by_enemy[s.name] = int(by_enemy.get(s.name, 0)) + 1)
		s.grenade_released.connect(func(_g): grenades += 1)
	Events.soldier_damaged.connect(func(v, _a, _z, att):
		if v is Soldier and (v as Soldier).team == c.team and att is Soldier and foes.slice(0, 3).has(att):
			hits += 1)
	# Trupp feuert nicht zurück: Kameraden halten
	for sm in m.squad.members:
		var sb = sm.get_node_or_null("SquadBrain")
		if sb and sb.has_method("set"):
			sb.set("fire_at_will", false)
	var secs := float(Game.cli.get("secs", "90"))
	var t := 0.0
	while t < secs:
		await seconds(1.0)
		t += 1.0
		for sm in m.squad.members:
			sm.health = sm.max_health
		# ai_orig2: Munitionsgrenze aufheben – Reserve der Gegner (nicht Magazin/Granaten) jede Sekunde auffüllen
		for s in foes.slice(0, 3):
			for w in (s as Soldier).weapons:
				if w != null and (w as Weapon).data.slot != WeaponData.Slot.GRENADE:
					(w as Weapon).reserve = maxi((w as Weapon).reserve, (w as Weapon).data.magazine_size * 4)
		# ai_orig2: Deckungsnutzung = Anteil Gegner-Sekunden ohne freie Linie Brust → Auge des Führers (nur Testsonde)
		var eye := c.global_position + Vector3.UP * 1.5
		for s in foes.slice(0, 3):
			if not (s as Soldier).alive:
				continue
			cover_samples += 1
			var q := PhysicsRayQueryParameters3D.create((s as Soldier).global_position + Vector3.UP * 1.1, eye, 1)
			if not space.intersect_ray(q).is_empty():
				cover_hits += 1
			if (s as Soldier).stance != Soldier.Stance.STAND:
				low_samples += 1
	var cover := (float(cover_hits) / cover_samples) if cover_samples > 0 else 0.0
	var low := (float(low_samples) / cover_samples) if cover_samples > 0 else 0.0
	var spm := shots * 60.0 / secs
	var rate := (float(hits) / shots) if shots > 0 else 0.0
	var tag := String(Game.cli.get("tag", "b048_" + String(Game.cli.get("b048", "1"))))
	var line := "B048_FIRE tag=%s b048=%s secs=%.0f shots=%d shots_per_min=%.1f hits=%d hit_rate=%.3f grenades=%d cover=%.2f low=%.2f je_gegner=%s" % [
		tag, Game.cli.get("b048", "1"), secs, shots, spm, hits, rate, grenades, cover, low, str(by_enemy)]
	var blocks := {}
	for s in foes.slice(0, 3):
		var eb = (s as Soldier).get_node_or_null("EnemyBrain")
		if eb and eb.get("gren_blocks") != null:
			for k in eb.gren_blocks:
				blocks[k] = int(blocks.get(k, 0)) + int(eb.gren_blocks[k])
	line += " granat_sperren=%s" % str(blocks)
	print(line)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var fa := FileAccess.open("res://test_output/b048_fire_%s.txt" % tag, FileAccess.WRITE)
	if fa:
		fa.store_line(line)
	check(true, "Messung abgeschlossen", line)
	_finish()
