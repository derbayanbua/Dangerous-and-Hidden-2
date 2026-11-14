extends "res://tests/test_sp_weapons.gd"
## 0.10.1 Visier/Ballistik/Mündungsfeuer/Luft anhalten (Status docs/status/waffen_visier.md):
##  A bahn     je Waffe (alle Feuerwaffen der WeaponDB) und Distanz 10–400 m: Ballistics.solve_direction trifft den
##             Zielpunkt mit demselben Integrator wie Ballistics._step (< 2 cm); Kugelfall ohne Ausgleich wird protokolliert
##             (Schwerkraft 9,8, Originalwaffen ohne Widerstand wie hd2.exe 0x44B910) → test_output/aim_ballistics.txt
##  B treffer  Standard (Original, Präzises Zielen aus): Einschlag nah exakt, Fall wächst mit der Distanz und folgt der
##             vorhergesagten 9,8-m/s²-Kurve; mit Option „Präzises Zielen“ (Ballistics.force_compensation = 1):
##             echter Spielerinput je Waffenklasse (Pistole, MP, Gewehr, Zielfernrohr, MG) auf eine Wand in 10/25/50/
##             100/200 m: rechte Maustaste, Fadenkreuz-/Visier-/Absehenmitte = CameraRig.crosshair_point, Feuertaste,
##             Einschlag (Ballistics.projectile_impact) gegen Zielpunkt; Streuung/Rückstoß für die Messung 0
##  C atem     Zielfernrohr + Shift: Wackeln ~0 beim Anhalten, nach BREATH_HOLD_S Atemnot (stärkeres Wackeln, kein
##             erneutes Anhalten), Erholung; HUD-Atemanzeige sichtbar
##  D feuer    Mündungsfeuer: Größe je Waffenart, Schalldämpfer ohne Feuer, 1. Person an der FPV-Mündung, Lichtgrenze
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_aim_ballistics [--phase=all|bahn|treffer|atem|feuer]

var rep: Array[String] = []
var wall: StaticBody3D


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission()
	check(m != null, "Mission geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	await seconds(1.5)
	player = m.squad.leader()
	var ph := String(Game.cli.get("phase", "all"))
	if ph in ["all", "bahn"]:
		_phase_path()
	if ph in ["all", "streu"]:
		_phase_scatter()
	if ph in ["all", "streu", "rueck"]:
		_phase_recoil()
	if ph in ["streu", "rueck"]:
		_finish()
		return
	await _setup_range()
	for s in m.squad.members:            # Vorgabe: keine Läufe ohne Unverwundbarkeit
		s.max_health = 100000.0
		s.health = s.max_health
	if target:
		target.global_position += Vector3(25, 0, 0)       # Zielfigur aus der Schusslinie
	if ph in ["all", "treffer"]:
		await _phase_aim_hits()
	if ph in ["all", "atem"]:
		await _phase_breath()
	if ph in ["all", "feuer"]:
		await _phase_flash()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/aim_ballistics.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(rep) + "\n")
	_finish()


# --- S: Zielstreuung (0.10.7, items.sav dw15, hd2.exe 0x545140) ------------------------------------------------------

func _scatter_span(dir: Vector3, deg: float, n: int) -> Vector2:
	## gemessene Höchstabweichung (Grad) und Spannweite quer (Grad, max − min einer Querachse)
	var rng := RandomNumberGenerator.new()
	rng.seed = 107
	var mx := 0.0
	var lo := 1e9
	var hi := -1e9
	var right := dir.cross(Vector3.UP).normalized()
	for i in n:
		var d := Ballistics.scatter_orig(dir, tan(deg_to_rad(deg)), rng)
		mx = maxf(mx, rad_to_deg(dir.angle_to(d)))
		var s := rad_to_deg(asin(clampf(d.dot(right), -1.0, 1.0)))
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return Vector2(mx, hi - lo)


func _phase_scatter() -> void:
	var dir := Vector3(0.3, 0.05, -1.0).normalized()
	for row in [[&"kar98k", 4, 0.1031], [&"mp40", 18, 1.432]]:
		var wd := WeaponDB.get_weapon(row[0])
		var o := WeaponDB._orig_row(int(row[1]))
		var want := float(row[2])
		check(absf(wd.spread_aim - want) < 0.003, "S %s Zielstreuung = dw15·0,01 rad" % row[0],
			"%.4f° (dw15 %s)" % [wd.spread_aim, str(o.get("aim_spread"))])
		var r := _scatter_span(dir, wd.spread_aim, 4000)
		rep.append("S %s: max %.4f° Spannweite quer %.4f° (Soll max %.4f°)" % [row[0], r.x, r.y, want])
		check(r.x <= want * 1.001 and r.x > want * 0.97, "S %s gemessene Höchstabweichung ≈ %.2f°" % [row[0], want], "%.4f°" % r.x)
		check(r.y > want * 1.8 and r.y <= want * 2.002, "S %s Spannweite ≈ 2 × %.2f°" % [row[0], want], "%.4f°" % r.y)
	# Verteilung: Betrag gleichverteilt (Median ≈ halber Höchstwert, nicht 0,71 wie flächengleich)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mags: Array[float] = []
	for i in 4000:
		mags.append(dir.angle_to(Ballistics.scatter_orig(dir, 0.01, rng)))
	mags.sort()
	var med: float = mags[2000] / atan(0.01)
	check(absf(med - 0.5) < 0.04, "S Betrag gleichverteilt (Median/Höchstwert ≈ 0,5)", "%.3f" % med)
	check(Ballistics.scatter_orig(dir, 0.0) == dir, "S dw15 = 0 → keine Streuung")
	# Soldat: stehend, ruhend, zielend, ohne Kaderwert, ausgeruht → genau dw15
	var s: Soldier = mission().squad.leader()
	var keep := [s.skill_shooting, s.stamina, s.aiming]
	s.equip(["mp40", "colt", "no36", "", "knife"])
	s.select_slot(WeaponData.Slot.PRIMARY)
	s.skill_shooting = -1.0
	s.stamina = 100.0
	s.aiming = true
	var cw := s.current_weapon()
	if cw:
		cw.bloom = 0.0
	if s.stance == 0 and s.current_speed() < 0.01 and cw and cw.data.id == &"mp40":
		check(absf(s.current_spread() - 1.432) < 0.01, "S Soldat zielend/stehend ohne Kaderwert = dw15", "%.4f°" % s.current_spread())
		s.skill_shooting = 100.0
		check(absf(s.current_spread() - 1.432 * 0.7) < 0.01, "S Schießen 100 → ×0,7 [E]", "%.4f°" % s.current_spread())
	else:
		check(false, "S Soldat für Streuprobe bereit", "stance %d v %.2f" % [s.stance, s.current_speed()])
	s.skill_shooting = keep[0]
	s.stamina = keep[1]
	s.aiming = keep[2]


# --- R: Rückstoß (0.11.2, hd2.exe 0x5454D0) und Zielgenauigkeit 0x5A8100 ---------------------------------------------

func _phase_recoil() -> void:
	var s: Soldier = mission().squad.leader()
	var keep := [s.skill_shooting, s.stamina, s.aiming, s.is_player_controlled, s.stance]
	s.is_player_controlled = true
	s.skill_shooting = 100.0
	s.stamina = 100.0
	s.aiming = false
	s.equip(["mp40", "colt", "no36", "", "knife"])
	s.select_slot(WeaponData.Slot.PRIMARY)
	var diff := Net.difficulty_level()
	var dk := 0.3 if diff == 1 else (0.8 if diff == 2 else 1.0)
	if s.current_speed() > 0.3 or s.stance != 0:
		check(false, "R Soldat steht still", "v %.2f stance %d" % [s.current_speed(), s.stance])
	# Grundwert (0x542B10): bereit 0,1, Anschlag 0,25; Schießen 100 → +0
	check(absf(s.orig_aim_base() - 0.1) < 1e-4, "R Grundwert Waffe bereit = 0,1", "%.3f" % s.orig_aim_base())
	s.aiming = true
	check(absf(s.orig_aim_base() - 0.25) < 1e-4, "R Grundwert Anschlag = 0,25", "%.3f" % s.orig_aim_base())
	s.skill_shooting = 60.0
	check(absf(s.orig_aim_base() - 0.65) < 1e-4, "R Grundwert + (100 − Schießen)·0,01", "%.3f" % s.orig_aim_base())
	s.skill_shooting = 100.0
	s.aiming = false
	# Faktoren je Waffenart: MP 0,3 / Pistole 0,8 / Gewehr 0,4 / ZF-Gewehr 1,0 / Sturmgewehr 0,5
	var rows := [[&"mp40", 0.3], [&"colt", 0.8], [&"kar98k", 0.4], [&"o_13", 0.4], [&"stg44", 0.5], [&"bren", 0.4]]
	for row in rows:
		var wd := WeaponDB.get_weapon(row[0])
		check(absf(WeaponDB.recoil_kind_factor(wd) - float(row[1])) < 1e-4, "R Faktor %s = %.1f" % [row[0], row[1]],
			"%.2f (Art %d)" % [WeaponDB.recoil_kind_factor(wd), WeaponDB.recoil_kind(wd)])
	var w := s.current_weapon()
	var r0 := s.orig_recoil_strength(w)
	check(absf(r0 - 0.1 * 0.3 * dk) < 1e-4, "R Stärke MP 40 bereit, ausgeruht", "%.4f (Stufe %d)" % [r0, diff])
	s.aiming = true
	var ra := s.orig_recoil_strength(w)
	check(absf(ra - 0.25 * 0.3 * 0.5 * dk) < 1e-4, "R Zielen ×0,5 (Anschlag 0,25)", "%.4f" % ra)
	s.stamina = 40.0
	var rs := s.orig_recoil_strength(w)
	check(absf(rs - ra * 1.6) < 1e-4, "R Ausdauer 40 % → ×(2 − 0,4)", "%.4f" % rs)
	s.stamina = 100.0
	# messbare Ablenkung: y nur nach oben, x/z symmetrisch, Höchstwert R·0,2
	var rng := RandomNumberGenerator.new()
	rng.seed = 112
	var dir := Vector3(0, 0, -1)
	var up_min := 1.0
	var up_max := -1.0
	var sx := 0.0
	for i in 2000:
		var d := s.apply_orig_recoil(dir, w, rng)
		up_min = minf(up_min, d.y)
		up_max = maxf(up_max, d.y)
		sx += d.x
	rep.append("R MP40 zielend: R %.4f, y %.5f…%.5f, Mittel x %.5f" % [ra, up_min, up_max, sx / 2000.0])
	check(up_min >= -1e-6 and up_max > ra * 0.2 * 0.9 and up_max <= ra * 0.2 * 1.01, "R Rückstoß hebt nur (y ≤ R·0,2)",
		"%.5f…%.5f" % [up_min, up_max])
	check(absf(sx / 2000.0) < ra * 0.2 * 0.05, "R seitlich symmetrisch", "%.5f" % (sx / 2000.0))
	# KI-Controller: Grundwert 0 → kein Rückstoß
	s.is_player_controlled = false
	check(s.orig_recoil_strength(w) == 0.0 and s.apply_orig_recoil(dir, w, rng) == dir, "R KI ohne Rückstoß (Grundwert 0)")
	s.is_player_controlled = true
	# Zielgenauigkeit 0x5A8100 = Grundwert + dw15·0,01
	var acc := s.orig_accuracy()
	check(absf(acc - (0.25 + tan(deg_to_rad(w.data.spread_aim)))) < 1e-4, "R Zielgenauigkeit = Grundwert + dw15·0,01",
		"%.4f" % acc)
	rep.append("R Fadenkreuz MP40 zielend: %.4f → Abstand %.4f" % [acc, acc * 0.025 + 0.01])
	s.skill_shooting = keep[0]
	s.stamina = keep[1]
	s.aiming = keep[2]
	s.is_player_controlled = keep[3]


# --- A: Flugbahn/Ausgleich je Waffe ----------------------------------------------------------------------------------

const DISTS := [10.0, 25.0, 50.0, 100.0, 200.0, 300.0, 400.0]


func _phase_path() -> void:
	rep.append("A Flugbahn: Fehler mit Ausgleich (cm) / Kugelfall ohne Ausgleich (cm) je Distanz %s m" % str(DISTS))
	var worst := 0.0
	var n := 0
	var origin := Vector3(3.0, 101.6, -7.0)
	for id in WeaponDB.all_ids():
		var d := WeaponDB.get_weapon(id)
		if d == null or d.action in [WeaponData.Action.THROWN, WeaponData.Action.ROCKET, WeaponData.Action.MELEE]:
			continue
		var cells: Array[String] = []
		for dist in DISTS:
			for yaw in [0.0, 2.1]:
				var tgt: Vector3 = origin + Vector3(-sin(yaw), 0.02, -cos(yaw)).normalized() * float(dist)
				var dir := Ballistics.solve_direction(origin, tgt, d)
				var rh := Vector2(tgt.x - origin.x, tgt.z - origin.z).length()
				var p := Ballistics.trajectory_point(origin, dir * d.muzzle_velocity, Ballistics.drag_of(d), rh)
				var e := p.distance_to(tgt)
				worst = maxf(worst, e)
				n += 1
				if yaw == 0.0:
					var raw := Ballistics.trajectory_point(origin, (tgt - origin).normalized() * d.muzzle_velocity,
						Ballistics.drag_of(d), rh)
					cells.append("%.1f/%.0f" % [e * 100.0, (tgt.y - raw.y) * 100.0])
		rep.append("  %-10s v0 %4.0f  %s" % [String(id), d.muzzle_velocity, "  ".join(cells)])
	check(n > 0 and worst < 0.02, "A Ausgleich trifft den Zielpunkt (alle Waffen, 10–400 m)", "%d Fälle, max. %.2f cm" % [n, worst * 100.0])
	var k98 := WeaponDB.get_weapon(&"k98") if WeaponDB.all_ids().has(&"k98") else null
	check(Ballistics.GRAVITY == 9.8, "A Schwerkraft wie Original 9,8 m/s² (0x80F9F4)")
	if k98:
		check(Ballistics.drag_of(k98) == 0.0, "A Originalwaffe ohne Luftwiderstand (0x44B910)")


# --- B: Treffer gegen Zielpunkt mit echtem Input -------------------------------------------------------------------

func _wall_at(dist: float) -> void:
	if wall == null:
		wall = StaticBody3D.new()
		wall.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(40, 30, 0.5)
		cs.shape = bx
		wall.add_child(cs)
		m.add_child(wall)
	var eye := player.eye_position()
	wall.global_position = Vector3(eye.x, eye.y, eye.z - dist - 0.25)


func _neutral(w: Weapon) -> void:
	var d := w.data.duplicate() as WeaponData
	d.spread_aim = 0.0
	d.spread_hip = 0.0
	d.spread_move_add = 0.0
	d.spread_per_shot = 0.0
	d.recoil_pitch = 0.0
	d.recoil_yaw = 0.0
	w.data = d
	w.bloom = 0.0
	player.orig_recoil_off = true       # 0.11.2: Bahnmessung ohne Rückstoß (eigene Phase R)


func _phase_aim_hits() -> void:
	player.skill_shooting = 100.0
	player.stamina = 100.0
	var impacts: Array = []
	var cb := func(pos: Vector3, _c: Object, sh: Node):
		if sh == player:
			impacts.append(pos)
	Ballistics.projectile_impact.connect(cb)
	var classes := [["Pistole", "colt", WeaponData.Slot.SIDEARM], ["MP", "sten", WeaponData.Slot.PRIMARY],
		["Gewehr", "enfield", WeaponData.Slot.PRIMARY], ["Zielfernrohr", "o_17", WeaponData.Slot.PRIMARY],
		["MG", "o_28", WeaponData.Slot.PRIMARY]]   # 0.11.4: Bren nur liegend -> stehend mit BAR messen
	for mode in [0, 1]:
		Ballistics.force_compensation = mode
		rep.append("B Treffer (%s) – Abweichung Einschlag vom Visierpunkt (cm), Zoom, Optik"
			% ("Original: Kugelfall" if mode == 0 else "Präzises Zielen: Ausgleich"))
		await _aim_hits_classes(classes, impacts, mode)
	Ballistics.force_compensation = -1
	check(not Settings.precise_aim and not Ballistics.compensation_enabled(), "B Standard = Original (Präzises Zielen aus)")
	Ballistics.projectile_impact.disconnect(cb)


func _aim_hits_classes(classes: Array, impacts: Array, mode: int) -> void:
	for c in classes:
		var prim: String = c[1] if c[2] == WeaponData.Slot.PRIMARY else "enfield"
		var side: String = c[1] if c[2] == WeaponData.Slot.SIDEARM else "colt"
		player.equip([prim, side, "no36", "", "knife"])
		player.select_slot(c[2])
		await seconds(1.2)
		var w := player.current_weapon()
		if w == null:
			check(false, "B %s ausgerüstet" % c[0])
			continue
		_neutral(w)
		Input.action_press("aim")
		m.rig.breath_force = 1          # Luft anhalten: kein Wackeln zwischen Zielen und Schuss
		await seconds(1.0)
		var line: Array[String] = []
		var worst := 0.0
		var missing := 0
		var errs: Array[float] = []
		var model_bad := 0.0          # Original: Abweichung des Einschlags von der vorhergesagten Fallkurve
		for dist in [10.0, 25.0, 50.0, 100.0, 200.0]:
			_wall_at(dist)
			m.rig.breath = 1.0
			m.rig.breath_winded = false
			var eye := player.eye_position()
			var aim_pt := Vector3(eye.x + 0.3, eye.y + 0.2, eye.z - dist)
			await _aim_at(aim_pt)
			for i in 150:
				if w.cooldown <= 0.0 and not w.is_reloading():
					break
				await frames(1)
			w.in_mag = w.data.magazine_size
			await frames(2)
			var want := m.rig.crosshair_point()
			impacts.clear()
			await tap("fire")
			for i in 90:
				if not impacts.is_empty():
					break
				await frames(1)
			if impacts.is_empty():
				missing += 1
				line.append("%dm: -" % int(dist))
				continue
			var imp: Vector3 = impacts[0]
			var e: float = imp.distance_to(want)
			errs.append(e)
			worst = maxf(worst, e / maxf(dist, 1.0))
			if mode == 0:
				# Vorhersage: Schuss vom Augpunkt entlang der Visierlinie, Fall wie Ballistics._step
				var o := player.eye_position()
				var rh := Vector2(want.x - o.x, want.z - o.z).length()
				var pred := Ballistics.trajectory_point(o, (want - o).normalized() * w.data.muzzle_velocity,
					Ballistics.drag_of(w.data), rh)
				model_bad = maxf(model_bad, absf(imp.y - pred.y) / maxf(dist, 1.0))
			line.append("%dm: %.1f" % [int(dist), e * 100.0])
		Input.action_release("aim")
		m.rig.breath_force = -1
		rep.append("  %-12s %s  (Zoom %s, Overlay %d)" % [c[0], "  ".join(line), str(m.rig.zoomed()), m.rig.optic_overlay()])
		if mode == 1:
			# Toleranz 1 mrad (Bildwechsel zwischen Messung und Schuss, Wackelreste)
			check(missing == 0 and worst < 0.0015, "B Präzise: %s trifft die Visiermitte 10–200 m" % c[0], "  ".join(line))
		else:
			var grows := errs.size() == 5
			for i in range(1, errs.size()):
				grows = grows and errs[i] >= errs[i - 1] - 0.005
			check(missing == 0 and errs[0] < 0.03 and grows and errs[4] > errs[0] and model_bad < 0.0015,
				"B Original: %s nah exakt, Fall wächst mit Distanz, folgt 9,8 m/s²" % c[0],
				"%s  (Kurvenabweichung %.2f mrad)" % ["  ".join(line), model_bad * 1000.0])


# --- C: Luft anhalten -----------------------------------------------------------------------------------------------

func _sway_amp_sample(frames_n: int) -> float:
	var mx := 0.0
	var prev := -m.rig.camera.global_basis.z
	var base_yaw := player.look_yaw
	var base_pitch := player.look_pitch
	for i in frames_n:
		player.look_yaw = base_yaw
		player.look_pitch = base_pitch
		await frames(1)
		var f := -m.rig.camera.global_basis.z
		mx = maxf(mx, f.angle_to(prev))
		prev = f
	return mx


func _phase_breath() -> void:
	player.equip(["o_17", "colt", "no36", "", "knife"])
	player.select_slot(WeaponData.Slot.PRIMARY)
	await seconds(1.2)
	Input.action_press("aim")
	await seconds(1.5)
	var scoped: bool = m.rig.optic_overlay() >= 0 and m.rig.optic_overlay() <= 3
	check(scoped, "C Zielfernrohr aktiv", "Overlay %d" % m.rig.optic_overlay())
	m.rig.breath_force = 0
	m.rig.breath = 1.0
	var normal := await _sway_amp_sample(60)
	m.rig.breath_force = 1
	await seconds(0.5)
	check(m.rig.breath_state() == "hold", "C Shift hält die Luft an", m.rig.breath_state())
	var held := await _sway_amp_sample(60)
	check(held < normal * 0.2 + 1e-6, "C Wackeln beim Anhalten gestoppt", "%.6f → %.6f rad/Bild" % [normal, held])
	var bar = m.hud.get("_breath_bar") if m.get("hud") else null
	check(bar == null or bar.visible, "C HUD-Atemanzeige sichtbar")
	await seconds(m.rig.BREATH_HOLD_S)
	check(m.rig.breath_winded and not m.rig.breath_holding, "C nach %.0f s Atemnot, Anhalten nicht mehr möglich" % m.rig.BREATH_HOLD_S,
		m.rig.breath_state())
	var winded := await _sway_amp_sample(60)
	check(winded > normal * 1.3, "C Atemnot wackelt stärker", "%.6f vs. normal %.6f" % [winded, normal])
	m.rig.breath_force = 0
	await seconds(m.rig.BREATH_REGEN_S * m.rig.BREATH_RESUME + 0.5)
	check(not m.rig.breath_winded, "C Erholung beendet die Atemnot", "Atem %.2f" % m.rig.breath)
	rep.append("C Atem: Wackeln normal %.6f, angehalten %.6f, Atemnot %.6f rad/Bild" % [normal, held, winded])
	m.rig.breath_force = -1
	Input.action_release("aim")
	await seconds(0.5)


# --- D: Mündungsfeuer -----------------------------------------------------------------------------------------------

func _phase_flash() -> void:
	var sz := {}
	for id in ["colt", "sten", "enfield", "bren", "o_7"]:
		if WeaponDB.all_ids().has(StringName(id)):
			sz[id] = Effects.flash_scale(WeaponDB.get_weapon(StringName(id)))
	rep.append("D Mündungsfeuer-Größen: %s" % str(sz))
	check(sz.get("colt", 0.0) < sz.get("sten", 0.0) and sz.get("sten", 0.0) < sz.get("enfield", 0.0)
		and sz.get("enfield", 0.0) < sz.get("bren", 0.0), "D Größe Pistole < MP < Gewehr < MG", str(sz))
	var sil: WeaponData = WeaponDB.from_orig(7)
	if sil:
		check(Effects.flash_scale(sil) == 0.0, "D Schalldämpfer (De Lisle) ohne Mündungsfeuer", String(sil.sound))
	# 1. Person: Feuer an der FPV-Mündung
	player.equip(["enfield", "colt", "no36", "", "knife"])
	player.select_slot(WeaponData.Slot.PRIMARY)
	await seconds(1.2)
	_wall_at(30.0)
	Input.action_press("aim")
	await seconds(1.0)
	var fm: Node3D = player.fpv_muzzle
	check(m.rig.fpv_active and is_instance_valid(fm), "D FPV-Mündung gefunden", "fpv %s" % str(m.rig.fpv_active))
	var n0: int = Effects.flashes_spawned
	var w := player.current_weapon()
	w.in_mag = w.data.magazine_size
	await tap("fire")
	await frames(1)
	check(Effects.flashes_spawned > n0, "D Schuss erzeugt Mündungsfeuer")
	var lf: Dictionary = Effects.last_flash
	check(bool(lf.get("vm", false)) and (lf["pos"] as Vector3).distance_to(lf["anchor"]) < 0.01,
		"D Feuer sitzt an der FPV-Mündung", str(lf))
	await seconds(0.1)
	check(Effects._flash_lights == 0, "D Lichtblitz nach 35 ms erloschen", str(Effects._flash_lights))
	Input.action_release("aim")
	# Welt: Mündungspunkt am Waffenmodell, Lichtgrenze bei vielen Schüssen
	var p0 := player.model.muzzle_point(player.aim_direction(), 1.0)
	for i in 10:
		Effects.muzzle_flash(p0, Vector3.FORWARD, 1.0)
	check(Effects._flash_lights <= Effects.MAX_FLASH_LIGHTS, "D höchstens %d Blitzlichter gleichzeitig" % Effects.MAX_FLASH_LIGHTS,
		str(Effects._flash_lights))
	await seconds(0.1)
