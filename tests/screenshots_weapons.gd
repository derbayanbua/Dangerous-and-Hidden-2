extends "res://tests/screenshots.gd"
## Kontrollbilder: Original-Waffenmodelle in der Hand der Original-Figuren (deutsch/alliiert), Ruhe- und
## Anschlaghaltung je Waffenklasse, Ganzkörper und Nahansicht. Startet einen LAN-Server mit 1 KI je Team:
##   tools\godot.cmd -- --autoplay=screenshots_weapons [--shots=w1,w2]
## Ausgabe: test_output/shot_w*.png; Konsole: Lage von Griff/Mündung und Laufrichtung beim Zielen.

const PAIRS := [["rifle", "kar98k", "enfield"], ["smg", "mp40", "thompson"], ["pistol", "p08", "colt"],
	["launcher", "panzerfaust", "bazooka"], ["mg", "o_19", "bren"], ["knife", "knife", "knife"], ["sd", "kar98k_sd", "mp40_sd"],
	["granate", "m24", "no36"]]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Net.local_name = "Kamera"
	Net.host({"name": "Waffen", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.TEAM_DEATHMATCH, "max_players": 8,
			"time_limit_min": 0, "score_limit": 0, "respawn_s": 5, "password": "", "port": Net.PORT + 31,
			"friendly_fire": false, "bots_per_team": 1})
	var bots: Array = []
	for i in 2400:
		await get_tree().process_frame
		bots.clear()
		for k in Net._soldiers:
			var s = Net._soldiers[k]
			if int(k) < 0 and is_instance_valid(s):
				bots.append(s)
		var cm := Game.current_mission()
		if bots.size() >= 2 and cm and cm.nav_ready:
			break
	await frames(120)       # Neu-Spawn nach dem Kartenabgleich abwarten (sonst freigegebene Figuren)
	bots.clear()
	for k in Net._soldiers:
		var s2 = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s2):
			bots.append(s2)
	var m := Game.current_mission()
	if m == null or bots.size() < 2:
		print("FEHLER: KI-Soldaten nicht gefunden ", bots.size())
		get_tree().quit(1)
		return
	bots.sort_custom(func(a, b): return int(a.team) > int(b.team))   # Achse zuerst
	await frames(20)
	var me = Net._soldiers.get(1)
	if me:
		me.visible = false
		me.process_mode = Node.PROCESS_MODE_DISABLED
	for s in bots:
		for n in ["EnemyBrain", "Perception"]:
			var c: Node = s.get_node_or_null(n)
			if c:
				c.process_mode = Node.PROCESS_MODE_DISABLED
	var base: Vector3 = bots[0].global_position
	for i in bots.size():
		var s = bots[i]
		s.global_position = base + Vector3(i * 1.6 - 0.8, 0.3, 0)
		s.move_input = Vector3.ZERO
		s.trigger = false
		s.look_yaw = PI                         # Blick nach +Z
		s.look_pitch = 0.0
		s.max_health = 100000.0
		s.health = 100000.0
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.far = 2000
	cam.current = true
	await frames(30)
	var idx := 1
	var pairs: Array = PAIRS
	var pre := "w"
	if String(Game.cli.get("pack", "")) == "1":
		pre = "wp"
		# B-051: Platzhalter für Waffen ohne Originalmodell (G43/MAS 36, P08 SD, Panzerschreck) → shot_wp*
		for it in [260, 262, 263]:
			WeaponDB.from_orig(it)
		pairs = [["p_gewehr", "o_262", "o_263"], ["p_pistole", "o_260", "o_260"], ["p_werfer", "panzerschreck", "panzerschreck"]]
	for pair in pairs:
		for i in 2:
			var s = bots[i]
			var wid := StringName(pair[1 + (0 if int(s.team) == Soldier.TEAM_AXIS else 1)])
			var ids: Array = ["", "", "", "", ""]
			ids[WeaponDB.get_weapon(wid).slot] = String(wid)
			s.equip(ids)
			s.aiming = false
			s.stance_request = Soldier.Stance.STAND
		await frames(40)
		for mode in ["ruhe", "anschlag"]:
			for s in bots:
				s.aiming = mode == "anschlag"
				s.look_yaw = PI
			await frames(50)
			for s in bots:
				_report(s, pair[0], mode)
			var mid: Vector3 = (bots[0].global_position + bots[1].global_position) * 0.5
			# Ganzkörper schräg von vorn-rechts, dann Nahansicht von der Seite (rechte Hand)
			cam.fov = 45
			cam.global_position = mid + Vector3(1.6, 1.4, 3.4)
			cam.look_at(mid + Vector3.UP * 0.95)
			await shot("%s%d_%s_%s_ganz" % [pre, idx, pair[0], mode])
			for i in 2:
				var s: Node3D = bots[i]
				for b in bots:
					b.set("look_yaw", PI)
				var hand := s.global_position + Vector3.UP * 1.3
				cam.fov = 40
				cam.global_position = hand + Vector3(-1.7, 0.25, 0.9)     # rechte Seite der Figur (Blick +Z)
				cam.look_at(hand + Vector3(0, 0, 0.25))
				await shot("%s%d_%s_%s_nah_%s" % [pre, idx, pair[0], mode, "achse" if int(s.team) == Soldier.TEAM_AXIS else "alliiert"])
		idx += 1
	if pre == "wp":
		await _pack_ground(cam, bots[0].global_position + Vector3(0, 0, 2.5))
		get_tree().quit()
		return
	# Hocken mit Anschlag (Gewehr)
	for i in 2:
		var s = bots[i]
		s.equip([("kar98k" if int(s.team) == Soldier.TEAM_AXIS else "enfield")])
		s.stance_request = Soldier.Stance.CROUCH
		s.aiming = true
	await frames(80)
	var mid2: Vector3 = (bots[0].global_position + bots[1].global_position) * 0.5
	cam.global_position = mid2 + Vector3(1.8, 1.0, 3.0)
	cam.look_at(mid2 + Vector3.UP * 0.6)
	await shot("w%d_hocken_anschlag" % idx)
	# Tod: Haltungsschicht aus, Waffe folgt der Todesanimation an der Hand
	idx += 1
	for s in bots:
		s.stance_request = Soldier.Stance.STAND
		s.aiming = false
	await frames(40)
	bots[0].die(null, Vector3(0, 0, -1))
	await frames(120)
	_report(bots[0], "tod", "-")
	cam.global_position = bots[0].global_position + Vector3(1.5, 2.2, 2.8)
	cam.look_at(bots[0].global_position + Vector3.UP * 0.2)
	await shot("w%d_tod" % idx)
	get_tree().quit()


## B-051: Platzhalter als Weltgegenstand (liegend wie Ablagestapel, gedreht um Z) nebeneinander.
func _pack_ground(cam: Camera3D, at: Vector3) -> void:
	var i := 0
	for it in OrigWeapons.PACK_ITEMS:
		var n := OrigWeapons.pack_item_model(int(it))
		if n == null:
			continue
		Game.current_mission().add_child(n)
		n.global_position = at + Vector3(i * 0.5 - 0.75, 0.06, 0)
		n.rotation = Vector3(0, 0, PI * 0.5)
		i += 1
	cam.fov = 40
	cam.global_position = at + Vector3(0.3, 1.6, 1.4)
	cam.look_at(at)
	await shot("wp9_boden")


## Prüfwerte: Waffe hängt an hw1, Mündungshöhe, Laufrichtung gegen Blickrichtung (Skalarprodukt).
func _report(s, cls: String, mode: String) -> void:
	var mdl = s.model
	var w: Node3D = mdl._weapon_mesh
	if w == null or not is_instance_valid(w):
		print("WAFFE ", cls, " ", mode, " ", s.name, ": keine")
		return
	var hand: Node3D = mdl._hand
	var barrel: Vector3 = w.global_basis * Vector3(0, 0, -1)
	var dotv: float = barrel.normalized().dot(s.aim_direction())
	print("WAFFE %s %s %s orig=%s an_hw1=%s Griff=%s Mündung=%s Lauf·Blick=%.2f Clip=%s" % [cls, mode, s.name,
		String(w.get_meta("pack", "")) if w.has_meta("pack") else str(w.has_meta("orig")), hand != null and w.get_parent() == hand, str(w.global_position - s.global_position),
		str(mdl.muzzle_point(barrel, 1.0) - s.global_position), dotv, mdl._hold_clip])
