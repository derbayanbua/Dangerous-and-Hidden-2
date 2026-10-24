extends "res://tests/test_gameplay.gd"
## Einzelspieler-Waffen gegen das Original (Gegenstück zu test_mp_weapons/test_weapons_orig, docs/re_notes_weapons.md §10b):
##  A werte   Gesundheit aller Gegner/Kameraden der Originalmission = actors.bin/HumanStore (zotti) × Schwierigkeit / 10
##            (gleiche Skala wie Waffenschaden und MP); Schadenstabelle je Waffe × Zone × Schwierigkeit gegen eine eigene
##            Nachrechnung aus items.json/hd2.exe-Konstanten → test_output/sp_weapon_damage.txt
##  B zonen   Trefferzonen der SP-Gegnerfigur = humanzones.json (Größe, Gelenk), folgen Stehen/Hocken/Liegen/Zielen
##  C treffer echter Spielerinput: Fadenkreuz per Blickwinkel auf Kopf/Rumpf/Arm/Bein legen, rechte Maustaste halten,
##            Feuertaste → Treffer muss in der anvisierten (sichtbaren) Zone landen, Schaden = Originalformel;
##            Pistole, MP, Gewehr, Zielfernrohr, MG, Panzerfaust (Explosion)
##  D schwierig  Gegner→Spieler ×0,2/0,4/1/1,2, Spieler→Gegner Stufe 1 ×1,2, KI-Kamerad→Trupp kein Treffer
##  E ansicht Zielansicht je Waffenklasse (FOV = items.sav-Zoom, FPV-Modell = items.sav, Overlay); mit --shot=1 im Fenster
##            Bilder test_output/sp_view_<klasse>.png
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_sp_weapons [--phase=all|werte|zonen|treffer|schwierig|ansicht]

var table: Array[String] = []
var orig_items := {}
var m: Mission
var player: Soldier
var plat: StaticBody3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission()
	check(m != null and m is OrigMission, "Originalmission geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	await seconds(1.5)
	player = m.squad.leader()
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/items.json")
	for w in (d.get("weapons", []) if typeof(d) == TYPE_DICTIONARY else []):
		orig_items[int(w["id"])] = w
	var ph := String(Game.cli.get("phase", "all"))
	if ph in ["all", "werte"]:
		_phase_values()
	await _setup_range()
	if ph in ["all", "zonen"]:
		await _phase_zones()
	if ph in ["all", "treffer"]:
		await _phase_hits()
	if ph in ["all", "schwierig"]:
		await _phase_difficulty()
	if ph in ["all", "ansicht"]:
		await _phase_view()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/sp_weapon_damage.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(table) + "\n")
	_finish()


# --- A: Gesundheit und Schadenstabelle ----------------------------------------------------------------------------

const DIFF_HP := {1: 0.7, 2: 0.85, 3: 1.0, 4: 1.0}          # hd2.exe 0x5A8990, nur Seite 2
const DIFF_VICTIM := {1: 0.2, 2: 0.4, 3: 1.0, 4: 1.2}       # 0x5A1C90, Opfer Seite 1/4 (Konstanten 0x80F540/554/FAD0)
const ZF := {&"torso": 1.0, &"head": 5.0, &"arm": 0.2, &"leg": 0.33}


## Unabhängige Nachrechnung: Schaden in zotti nach Strecke (0x44B3B0), × Schwierigkeit, × Zone, ⌊⌋, /10
func expect(item: int, dist: float, zone: StringName, victim_side: int, shooter_side: int, diff: int) -> float:
	var o: Dictionary = orig_items.get(item, {})
	var z := float(o.get("damage", 0.0))
	var start := float(o.get("dist_param", 0.0))
	if dist > start:
		z = maxf(z - (dist - start) * float(o.get("recoil_spread", 0.0)), 0.0)
	var k := 1.0
	if victim_side in [1, 4]:
		k = DIFF_VICTIM[diff]
	elif diff == 1 and shooter_side == 1:
		k = 1.2
	return floorf(z * k * float(ZF[zone]) + 1e-4) / 10.0


func _phase_values() -> void:
	var diff := Game.difficulty()
	var bad: Array = []
	var n := 0
	for e in m.enemies:
		var p: Dictionary = e.get_meta("orig_params", {})
		if p.is_empty() or int(p.get("side", 2)) != 2:
			continue
		n += 1
		var want := float(p.get("health", 0)) * float(DIFF_HP[diff]) / 10.0
		if absf(e.max_health - want) > 0.01:
			bad.append("%s %.1f≠%.1f" % [e.persistent_id, e.max_health, want])
	# Helm nur mit Kopfgegenstand (items.dat Platz 0, Kategorie 16) – 0x455670
	var hbad: Array = []
	var nh := 0
	for e in m.enemies:
		var inv: Array = (m as OrigMission).actor_params.get(String(e.persistent_id), {}).get("inventory", []) if e.has_meta("orig_params") else []
		if not e.has_meta("orig_params"):
			continue
		var head := false
		for it in inv:
			var eq = OrigInteractive.item_info(int(it.get("item", -1))).get("equip_raw", [])
			if eq is Array and (eq as Array).size() > 1 and int(eq[1]) == 16:
				head = true
		if head:
			nh += 1
		if WeaponDB.wears_helmet(e) != head:
			hbad.append(String(e.persistent_id))
	check(hbad.is_empty(), "Helm/Kopfbedeckung der SP-Gegner nur laut items.dat-Kopfplatz", "%d mit Kopfgegenstand, falsch: %s" % [nh, str(hbad.slice(0, 6))])
	check(n > 10 and bad.is_empty(), "Gegner-Gesundheit = actors.bin × Schwierigkeit / 10 (Skala des Waffenschadens)", "%d Gegner %s" % [n, str(bad.slice(0, 5))])
	var sbad: Array = []
	var ns := 0
	for s in m.squad.members:
		if not s.has_meta("sas"):
			continue
		ns += 1
		var st: Dictionary = Game.sas_states().get(str(int(s.get_meta("sas"))), {}).get("stats", {})
		if absf(s.max_health - float(st.get("health", 0)) / 10.0) > 0.01:
			sbad.append("%s %.1f/%s" % [s.soldier_name, s.max_health, str(st.get("health"))])
	check(ns == 0 or sbad.is_empty(), "Kader-Gesundheit = HumanStore / 10", "%d SAS %s" % [ns, str(sbad)])
	# Originaldaten ARCTIC1: K98k-Rumpftreffer (488) tötet jeden Gegner mit ≤ 488 zotti (Original) – hier ebenso
	var one_shot := 0
	var one_shot_orig := 0
	for e in m.enemies:
		var p: Dictionary = e.get_meta("orig_params", {})
		if p.is_empty() or int(p.get("side", 2)) != 2:
			continue
		if float(p.get("health", 0)) * float(DIFF_HP[diff]) <= 488.0:
			one_shot_orig += 1
		if WeaponDB.bullet_hit_damage(WeaponDB.bullet_damage(WeaponDB.get_weapon(&"kar98k"), 25.0), &"torso", false, e, player, true, diff) >= e.max_health:
			one_shot += 1
	check(one_shot == one_shot_orig and one_shot > 0, "K98k-Rumpftreffer auf 25 m: tödlich für dieselben Gegner wie im Original", "%d/%d" % [one_shot, one_shot_orig])
	# Tabelle Waffen × Zonen × Schwierigkeit
	table.append("SP-Schadenstabelle (Gesundheit 1 = 10 zotti; items.sav v1.12, hd2.exe 0x44B3B0/0x5A1C90; Abstand 10 m)")
	table.append("Waffe | Zone | Spieler→Gegner St.1/2/3/4 | Gegner→Spieler St.1/2/3/4")
	var ok := true
	var cnt := 0
	var dummy_enemy := Soldier.new()
	dummy_enemy.team = Soldier.TEAM_AXIS
	var dummy_player := Soldier.new()
	dummy_player.team = Soldier.TEAM_ALLIED
	for wid in [&"colt", &"p08", &"sten", &"mp40", &"thompson", &"enfield", &"kar98k", &"garand", &"stg44", &"bren", &"o_17", &"o_13"]:
		var wd := WeaponDB.get_weapon(wid) if not String(wid).begins_with("o_") else WeaponDB.from_orig(int(String(wid).substr(2)))
		if wd == null:
			continue
		var item := WeaponDB.orig_item_of(wid)
		for zone in [&"head", &"torso", &"arm", &"leg"]:
			var a: Array = []
			var b: Array = []
			for diff2 in [1, 2, 3, 4]:
				var base := WeaponDB.bullet_damage(wd, 10.0)
				var got_e := WeaponDB.bullet_hit_damage(base, zone, false, dummy_enemy, dummy_player, true, diff2)
				var got_p := WeaponDB.bullet_hit_damage(base, zone, false, dummy_player, dummy_enemy, true, diff2)
				var we := expect(item, 10.0, zone, 2, 1, diff2)
				var wp := expect(item, 10.0, zone, 1, 2, diff2)
				cnt += 2
				if absf(got_e - we) > 0.051 or absf(got_p - wp) > 0.051:
					ok = false
					print("ABWEICHUNG %s %s St.%d: %.2f/%.2f %.2f/%.2f" % [wid, zone, diff2, got_e, we, got_p, wp])
				a.append("%.1f" % got_e)
				b.append("%.1f" % got_p)
			table.append("%s (%d) | %s | %s | %s" % [wd.display_name, item, zone, "/".join(a), "/".join(b)])
	dummy_enemy.free()
	dummy_player.free()
	check(ok and cnt >= 300, "SP-Schaden je Waffe × Zone × Schwierigkeit = Nachrechnung aus items.sav und hd2.exe", "%d Werte" % cnt)
	# MP unverändert: dieselbe Funktion ohne SP = zone_damage
	check(is_equal_approx(WeaponDB.bullet_hit_damage(48.8, &"head", false, null, null, false, 1), 244.0)
		and is_equal_approx(WeaponDB.bullet_hit_damage(48.8, &"arm", false, null, null, false, 4), 9.76),
		"Mehrspieler: Schaden ohne Schwierigkeitsfaktor (zone_damage unverändert)")
	# Helm Stufe 1: Spieler mit Helm, Durchschlag ×1 statt ×5
	var hp := Soldier.new()
	hp.team = Soldier.TEAM_ALLIED
	check(is_equal_approx(WeaponDB.bullet_hit_damage(48.8, &"head", true, hp, null, true, 1, 0.1), floorf((488.0 - 150.0) * 0.2) / 10.0)
		and is_equal_approx(WeaponDB.bullet_hit_damage(48.8, &"head", true, hp, null, true, 3, 0.1), floorf((488.0 - 150.0) * 5.0) / 10.0),
		"Helm im SP: Panzerung 150, Stufe 1 Spieler-Durchschlag ×1 (0x5A20F6), sonst ×5")
	hp.free()


# --- Schießstand über dem Startpunkt --------------------------------------------------------------------------------

var target: Soldier
var mate: Soldier


func _setup_range() -> void:
	# Einsatz-Intro (Zwischensequenz sperrt die Eingabe, eigene Kamera) überspringen wie mit Esc
	var rt = m.ls_runtime
	if rt:
		rt.set("auto_skip", true)
		if rt.get("in_cutscene"):
			rt.end_cutscene()
	for i in 600:
		if m.controller.input_enabled and not (rt and rt.get("in_cutscene")):
			break
		await frames(1)
	await seconds(1.0)
	m.rig.camera.current = true
	check(m.controller.input_enabled and m.controller.active == player, "Spielersteuerung aktiv (Intro übersprungen)")
	if m.ls_runtime and m.ls_runtime.get("area") and is_instance_valid(m.ls_runtime.area):
		m.ls_runtime.area.set_physics_process(false)          # Einsatzgebiet-Grenze ruht während der Messung
	# Gegner mit Originalfigur (Seite 2) als Ziel, alle übrigen eingefroren
	for e in m.enemies:
		if target == null and e.model.orig_figure != null and not e.model.orig_zones.is_empty() and e.alive:
			target = e
	isolate_enemies([target.persistent_id] if target else [])
	if target == null:
		check(false, "Gegner mit Original-Figur für die Treffer")
		return
	var b := target.get_node("EnemyBrain") as EnemyBrain
	b.enabled = false
	target.get_node("Perception").set_physics_process(false)
	var base := player.global_position + Vector3(0, 60, 0)
	plat = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(30, 1, 60)
	cs.shape = bx
	plat.add_child(cs)
	m.add_child(plat)
	plat.global_position = base - Vector3(0, 0.5, 0)
	for s in m.squad.members:
		var sb := m.squad.brain_of(s)
		if sb:
			sb.set_physics_process(false)
			sb.set_process(false)
	for i in m.squad.members.size():
		var s: Soldier = m.squad.members[i]
		s.global_position = base + Vector3(-6.0 - 2.0 * i, 0.2, 10.0)
		s.velocity = Vector3.ZERO
		if s != player and mate == null:
			mate = s
	player.global_position = base + Vector3(0, 0.2, 8.0)
	player.look_yaw = 0.0
	target.global_position = base + Vector3(0, 0.2, 0.0)
	target.look_yaw = PI
	target.velocity = Vector3.ZERO
	target.set_meta("orig_items", [])          # ohne Helm (sonst teilt der Helmzufall den Kopfschaden)
	target.set("helmet_style", "cap")


func _hold_target() -> void:
	target.move_input = Vector3.ZERO
	target.velocity = Vector3.ZERO
	target.trigger = false
	target.global_position.x = plat.global_position.x
	target.global_position.z = plat.global_position.z


# --- B: Trefferzonen der SP-Figur -----------------------------------------------------------------------------------

func _phase_zones() -> void:
	if target == null:
		return
	var tbl := SoldierModel.orig_zone_table()
	var fig: Node3D = target.model.orig_figure
	var sk := fig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var scl := sk.global_basis.get_scale()
	check(scl.distance_to(Vector3.ONE) < 0.02, "SP-Gegnerfigur %s ohne Skalierung (Zonen wie MP in Metern)" % str(target.get_meta("orig_model", "")), str(scl))
	var size_ok := true
	for hb in target.model.orig_zones:
		var bone := String(hb.get_meta("bone"))
		for z in tbl:
			if String(z["bone"]) == bone:
				var want := Vector3(z["max"][0], z["max"][1], z["max"][2]) - Vector3(z["min"][0], z["min"][1], z["min"][2])
				var cs := hb.get_child(0) as CollisionShape3D
				if ((cs.shape as BoxShape3D).size - want).length() > 0.001 or cs.global_basis.get_scale().distance_to(Vector3.ONE) > 0.02:
					size_ok = false
	check(target.model.orig_zones.size() == 10 and size_ok, "10 Original-Gelenkzonen (humanzones.4ds) in Originalgröße am SP-Gegner")
	var puppet := 0
	for h in target.model.root_pivot.find_children("*", "Hitbox", true, false):
		if (h as Hitbox).collision_layer != 0:
			puppet += 1
	check(puppet == 0, "Platzhalterzonen des SP-Gegners aus", str(puppet))
	for p in ["stehen", "hocken", "liegen", "zielen"]:
		target.aiming = p == "zielen"
		target.stance_request = {"stehen": Soldier.Stance.STAND, "hocken": Soldier.Stance.CROUCH, "liegen": Soldier.Stance.PRONE, "zielen": Soldier.Stance.STAND}[p]
		for i in 120:
			_hold_target()
			await frames(1)
		var bad: Array = []
		var eye := fig.find_child("Reye", true, false) as Node3D
		for hb in target.model.orig_zones:
			var bone := String(hb.get_meta("bone"))
			var cs := hb.get_child(0) as CollisionShape3D
			var bp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin
			# Kiste sitzt im Gelenkraum: Abstand Kistenmitte–Gelenk = lokale Lage (folgt der Animation)
			# (Arme/Rumpf/Kopf werden nach der Animation von IK/Anschlag-Modifier verändert, die Knochenabfrage liefert dann
			#  die Pose davor – Kopf wird über die sichtbaren Augen geprüft, wie test_mp_weapons)
			if absf(cs.global_position.distance_to(bp) - cs.position.length()) > 0.01 and not bone in ["h", "l", "i", "m", "c", "f"]:
				bad.append("%s %.3f" % [bone, cs.global_position.distance_to(bp)])
			if bone == "f" and eye:
				var loc := cs.global_transform.affine_inverse() * eye.global_position
				var half := (cs.shape as BoxShape3D).size * 0.5 + Vector3.ONE * 0.02
				if absf(loc.x) > half.x or absf(loc.y) > half.y or absf(loc.z) > half.z:
					bad.append("Kopfkiste ohne Augen %s" % loc)
		var head_y := 0.0
		for hb in target.model.orig_zones:
			if hb.zone == &"head":
				head_y = (hb.get_child(0) as Node3D).global_position.y - target.global_position.y
		check(bad.is_empty(), "SP-Zonen folgen der Haltung %s (Kopf %.2f m über dem Boden)" % [p, head_y], str(bad))
		if bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless":
			await _zone_shot(p)
	target.aiming = false
	target.stance_request = Soldier.Stance.STAND
	for i in 120:
		_hold_target()
		await frames(1)


func _zone_shot(p: String) -> void:
	target.model.show_zones(true)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 45.0
	var c := (target.model.orig_zones[0].get_child(0) as Node3D).global_position
	cam.global_position = c + Vector3(2.2, 0.9, 2.2)
	cam.look_at(c)
	cam.current = true
	await seconds(1.0)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/sp_zones_%s.png" % p))
	cam.queue_free()
	m.rig.camera.current = true
	target.model.show_zones(false)


# --- C: echter Spielerinput auf jede Zone -----------------------------------------------------------------------------

## Blick so drehen, dass die Bildmitte (Fadenkreuz) auf pt liegt (Kamera hängt am Kopf → iterativ)
func _aim_at(pt: Vector3) -> void:
	for i in 6:
		var cam := m.rig.camera
		var dv := pt - cam.global_position
		var fwd := -cam.global_basis.z
		var want_yaw := atan2(-dv.x, -dv.z)
		var want_pitch := atan2(dv.y, Vector2(dv.x, dv.z).length())
		var cur_yaw := atan2(-fwd.x, -fwd.z)
		var cur_pitch := asin(clampf(fwd.y, -1.0, 1.0))
		player.look_yaw += wrapf(want_yaw - cur_yaw, -PI, PI)
		player.look_pitch = clampf(player.look_pitch + (want_pitch - cur_pitch), -1.2, 1.2)
		for j in 6:
			_hold_target()
			await frames(1)


## Zone unter dem Fadenkreuz (gleicher Strahl wie CameraRig.crosshair_point)
func _zone_under_crosshair() -> Hitbox:
	var cam := m.rig.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 60.0, 1 | Hitbox.LAYER, player.exclude_rids())
	q.collide_with_areas = true
	var h := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty() or not (h.collider is Hitbox):
		return null
	return Ballistics._priority_zone(cam.get_world_3d().direct_space_state, h.collider, h.position, -cam.global_basis.z)


func _zone_box(zone: StringName) -> Hitbox:
	# frei von vorn sichtbare Kiste der Zone (Arm/Bein: die äußerste)
	var best: Hitbox = null
	var side := Vector3(cos(target.look_yaw), 0, -sin(target.look_yaw))
	for hb in target.model.orig_zones:
		if hb.zone != zone:
			continue
		var lat := absf(((hb.get_child(0) as Node3D).global_position - target.global_position).dot(side))
		if best == null or lat > absf(((best.get_child(0) as Node3D).global_position - target.global_position).dot(side)):
			best = hb
	return best


func _phase_hits() -> void:
	if target == null:
		return
	player.skill_shooting = 100.0
	var got := []
	var cb := func(amount: float, zone: StringName): got.append([amount, zone])
	target.damaged.connect(cb)
	var classes := [["Pistole", "colt", WeaponData.Slot.SIDEARM], ["MP", "sten", WeaponData.Slot.PRIMARY],
		["Gewehr", "enfield", WeaponData.Slot.PRIMARY], ["Zielfernrohr", "o_17", WeaponData.Slot.PRIMARY],
		["MG", "bren", WeaponData.Slot.PRIMARY]]
	var diff := Game.difficulty()
	for c in classes:
		var prim: String = c[1] if c[2] == WeaponData.Slot.PRIMARY else "enfield"
		var side: String = c[1] if c[2] == WeaponData.Slot.SIDEARM else "colt"
		player.equip([prim, side, "no36", "", "knife"])
		player.select_slot(c[2])
		await seconds(1.2)
		var w := player.current_weapon()
		var item := WeaponDB.orig_item_of(w.data.id)
		Input.action_press("aim")
		await seconds(1.0)
		var res: Array = []
		var ok_dmg := true
		var ok_zone := true
		for zone in [&"head", &"torso", &"arm", &"leg"]:
			var hit_aimed := false
			for attempt in 5:
				target.max_health = 100000.0
				target.health = 100000.0
				w.in_mag = w.data.magazine_size
				for i in 50:
					_hold_target()
					await frames(1)
				var hb := _zone_box(zone)
				await _aim_at((hb.get_child(0) as Node3D).global_position)
				var under := _zone_under_crosshair()
				got.clear()
				# Repetierer: warten bis schussbereit
				for i in 150:
					if w.cooldown <= 0.0 and not w.is_reloading() and m.rig.zoomed():
						break
					await frames(1)
				var shots0 := Ballistics.shots_fired
				await tap("fire")
				for i in 30:
					_hold_target()
					await frames(1)
				if got.is_empty():
					res.append("%s: kein Treffer (Fadenkreuz %s, Schüsse %d, Zoom %s)" % [zone, under.zone if under else "-",
						Ballistics.shots_fired - shots0, str(m.rig.zoomed())])
					continue
				var dist := player.eye_position().distance_to((hb.get_child(0) as Node3D).global_position)
				var hz: StringName = got[0][1]
				var want := expect(item, dist, hz, 2, 1, diff)
				if absf(float(got[0][0]) - want) > 0.051:
					ok_dmg = false
				res.append("%s→%s %.1f (soll %.1f, Fadenkreuz %s)" % [zone, hz, float(got[0][0]), want, under.zone if under else "-"])
				if hz == zone:
					hit_aimed = true
					break
			if not hit_aimed:
				ok_zone = false
		Input.action_release("aim")
		await seconds(0.5)
		check(ok_zone and ok_dmg, "%s (%s, Spielerinput, Zielen): Treffer an der anvisierten Zone, Schaden = Original" % [c[0], w.data.display_name], "; ".join(res))
		for r in res:
			table.append("Messung %s %s: %s" % [c[0], w.data.display_name, r])
	target.damaged.disconnect(cb)
	# Panzerfaust (Explosion, Art 2: ohne Schwierigkeitsfaktor), Rakete 3 m vor das Ziel auf den Boden
	player.equip(["enfield", "colt", "no36", "panzerfaust", "knife"])
	player.select_slot(WeaponData.Slot.LAUNCHER)
	await seconds(1.5)
	target.max_health = 100000.0
	target.health = 100000.0
	var before := target.health
	var aim_pt := target.global_position + Vector3(0, 0.05, 3.0)
	Input.action_press("aim")
	await seconds(1.0)
	await _aim_at(aim_pt)
	var impact := m.rig.crosshair_point()
	await tap("fire")
	for i in 240:
		_hold_target()
		await frames(1)
	Input.action_release("aim")
	var pf := WeaponDB.get_weapon(&"panzerfaust")
	var dmg := before - target.health
	var dd := impact.distance_to(target.global_position + Vector3.UP * 0.9)
	var want_pf := WeaponDB.explosion_damage(pf.damage, pf.blast_radius, dd)
	check(dmg > 0.0 and absf(dmg - want_pf) < 0.25 * want_pf + 3.0, "Panzerfaust (Spielerinput): Explosion (1 − d/6 m)·290 ohne Schwierigkeitsfaktor",
		"%.1f (erwartet ≈ %.1f bei %.2f m)" % [dmg, want_pf, dd])
	target.max_health = 100000.0
	target.health = 100000.0


# --- D: Schwierigkeitsgrad und Trupp ---------------------------------------------------------------------------------

func _shoot(shooter: Soldier, victim: Soldier, wid: StringName) -> float:
	var hb: Hitbox = null
	for h in victim.model.orig_zones:
		if h.zone == &"torso":
			hb = h
	var c: Vector3 = (hb.get_child(0) as Node3D).global_position if hb else victim.global_position + Vector3.UP
	var o := c + (shooter.global_position - victim.global_position).normalized() * 6.0
	o.y = c.y
	victim.max_health = 100000.0
	victim.health = 100000.0
	var before := victim.health
	Ballistics.fire(shooter, o, (c - o).normalized(), WeaponDB.get_weapon(wid), shooter.exclude_rids(), shooter.team)
	for i in 20:
		_hold_target()
		await frames(1)
	print("SCHUSS %s -> %s: %.1f (Zonen aktiv %d, lebt %s)" % [shooter.soldier_name, victim.soldier_name, before - victim.health, victim.model.orig_zones.filter(func(h): return h.collision_layer != 0).size(), str(victim.alive)])
	return before - victim.health


func _phase_difficulty() -> void:
	if target == null:
		return
	var old := Game.difficulty()
	# Spieler steht 8 m vor dem Ziel, Kamerad daneben
	mate.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	await seconds(0.5)
	var res: Array = []
	var ok := true
	for diff in [1, 2, 3, 4]:
		Game.profile["difficulty"] = diff
		var to_player: float = await _shoot(target, player, &"kar98k")
		var to_enemy: float = await _shoot(player, target, &"enfield")
		var want_p := floorf(488.0 * float(DIFF_VICTIM[diff]) + 1e-4) / 10.0
		var want_e := floorf(419.0 * (1.2 if diff == 1 else 1.0) + 1e-4) / 10.0
		if absf(to_player - want_p) > 0.051 or absf(to_enemy - want_e) > 0.051:
			ok = false
		res.append("St.%d Gegner→Spieler %.1f (soll %.1f), Spieler→Gegner %.1f (soll %.1f)" % [diff, to_player, want_p, to_enemy, want_e])
	check(ok, "Schwierigkeit im SP (0x5A1C90): Spieler ×0,2/0,4/1/1,2, Gegner Stufe 1 ×1,2", "; ".join(res))
	Game.profile["difficulty"] = 3
	var by_mate: float = await _shoot(mate, player, &"enfield")
	var by_player: float = await _shoot(player, mate, &"enfield")
	check(by_mate == 0.0 and absf(by_player - 41.9) < 0.051, "KI-Kamerad trifft den Trupp nicht (0x44BDB0), Spieler trifft Kameraden",
		"Kamerad→Spieler %.1f, Spieler→Kamerad %.1f" % [by_mate, by_player])
	Game.profile["difficulty"] = old
	for s in [player, mate]:
		s.max_health = 100.0
		s.health = 100.0


# --- E: Zielansicht je Waffenklasse -----------------------------------------------------------------------------------

func _phase_view() -> void:
	var shots := bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless"
	player.look_yaw = 0.0
	player.look_pitch = 0.0
	if is_instance_valid(target):
		target.global_position = plat.global_position + Vector3(0, 0.7, 0)
	var classes := [["pistole", "colt", WeaponData.Slot.SIDEARM], ["mp", "sten", WeaponData.Slot.PRIMARY],
		["gewehr", "enfield", WeaponData.Slot.PRIMARY], ["zielfernrohr", "o_17", WeaponData.Slot.PRIMARY],
		["mg", "bren", WeaponData.Slot.PRIMARY], ["panzerfaust", "panzerfaust", WeaponData.Slot.LAUNCHER]]
	for c in classes:
		var prim: String = c[1] if c[2] == WeaponData.Slot.PRIMARY else "enfield"
		var sidearm: String = c[1] if c[2] == WeaponData.Slot.SIDEARM else "colt"
		var launcher: String = "panzerfaust"
		player.equip([prim, sidearm, "no36", launcher, "knife"])
		player.select_slot(c[2])
		await seconds(1.5)
		if shots:
			await _aim_at(target.global_position + Vector3.UP * 1.2)
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/sp_view_%s_3rd.png" % c[0]))
		Input.action_press("aim")
		await seconds(1.6)
		if is_instance_valid(target):
			await _aim_at((target.model.orig_zones[1].get_child(0) as Node3D).global_position)
		var w := player.current_weapon()
		var z := OrigWeapons.zoom(w.data, player.team)
		var want_fov: float = OrigWeapons.vfov(float(z["fov_deg"])) if not z.is_empty() else m.rig.base_fov()
		var vm := m.rig.viewmodel_info()
		var key := OrigWeapons.fpv_key(w.data, player.team)
		var sc := int(z.get("scope", 5))
		var overlay_ok := (m.rig.optic_overlay() == sc) if sc <= 3 else m.rig.optic_overlay() == -1
		check(m.rig.fpv_active and absf(m.rig.camera.fov - want_fov) < 0.6 and vm["key"] == key and key != "" and overlay_ok
				and (vm["visible"] or sc <= 3),
			"Zielansicht %s (%s): Ego-Ansicht, FOV %.1f° (items.sav), FPV-Modell %s, Overlay %d" % [c[0], w.data.display_name, want_fov, key, sc],
			"fov %.1f vm %s overlay %d" % [m.rig.camera.fov, str(vm), m.rig.optic_overlay()])
		if shots:
			await seconds(0.5)
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/sp_view_%s.png" % c[0]))
		Input.action_release("aim")
		await seconds(0.8)
