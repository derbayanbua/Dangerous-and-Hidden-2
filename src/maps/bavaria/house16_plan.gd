extends RefCounted
## Haus 16 (haus_16) nach eigenem Schnitt und EG-Grundriss
## (Keller, EG, OG).
## Schnitt: Keller lichte Höhe 2,10 m (voll unterkellert, Mittelwand), EG 2,50 m, OG 2,75 m, Dach 2,22 m bis First
## (Satteldach ca. 24,7° über 9,64 m Tiefe), Pfannendeckung.
## EG-Grundriss (5,30 + 7,80 = 13,10 m): links Zimmer (13,81 m², hinten) und Wohnzimmer (27,40 m², vorn), Mitte hinten
## WC/Bad, Gang mit Treppe, Mitte vorn Küche (Tiefe 4,40), rechts zwei Zimmer.
## Abweichungen (begründet, siehe docs/bavaria_ausbau_2026-11.md): Die im Plan gewendelte Treppe im Gang ist die
## bestehende, geprüfte zweiläufige Treppe im rechten Hausteil (rechte Zimmer = Treppen-/Wohnhalle); der Rücksprung
## der rechten Hausseite (≈1,4 m) bleibt Teil des Rechteckgrundrisses (Vorraum); EG-Boden bleibt auf Geländehöhe
## (+0,05 m) statt +0,40 m, weil Türen, Fenster, Treppe (18 Steigungen) und 551 Kartenprüfungen darauf aufbauen.
## Lokales Hauskoordinatensystem: x = 13,10-m-Front (links −6,55), z = Tiefe, Rückseite −z (Kellertreppen laut Plan).

const CELLAR_FLOOR := -2.40   # Oberkante Kellerboden (EG-Boden +0,05, Decke = EG-Bodenplatte −0,30)
const OG_FLOOR := 3.18        # Oberkante OG-Decke (bestehende zweiläufige Treppe)
const ROOF_SLOPE := 0.431     # atan(2,22 / 4,82)
const STEPS := 14
const RUN := 0.27
const WELL_CLEAR := 1.15      # lichte Breite Kellerhals
const WALL_T := 0.24
const BACK_DOOR_X := 0.95     # Hintertür neben dem Bad (Plan: Bad/WC hinten Mitte)
const TOP_X := 1.55           # oberste Stufe des Kellerhalses (Abgang nach +x)
const LANDING := 1.24
const EG_WALL_H := 3.0
const W_LEFT := -1.6          # Trennwand linke Zimmer | Gang/Küche (Plan 5,30 m-Achse, für Flurfreiheit 0,35 m versetzt)
const W_BATH_X := -0.45     # Flurfreiheit Hausmittelachse (Kartenprüfung) vor Plantreue
const W_BATH_Z := -2.75
const W_KITCHEN_Z := -0.75
const W_LEFT_SPLIT_Z := -0.30

static func landing_x0() -> float:
	return TOP_X + (STEPS - 1) * RUN

## Kellerhals außen an der Rückseite, lokales Rechteck für das Bodenloch.
static func stairwell_rect(_w: float, d: float) -> Rect2:
	var x0 := TOP_X
	var x1 := landing_x0() + LANDING + WALL_T
	var z_in := -d * 0.5 - 0.15
	var z_out := z_in - WELL_CLEAR - WALL_T
	return Rect2(x0, z_out, x1 - x0, z_in - z_out)

## Raumflächen (innen, lokal) für Einrichtung/Licht.
static func plan_rooms(w: float, d: float) -> Array:
	var x_out := -w * 0.5 + 0.23
	var z_back := -d * 0.5 + 0.23
	var z_front := d * 0.5 - 0.23
	return [
		{"role": "Schlafen", "label": "Zimmer", "side": -1.0, "rect": Rect2(x_out, z_back, W_LEFT - 0.12 - x_out, W_LEFT_SPLIT_Z - 0.12 - z_back)},
		{"role": "Wohnen", "label": "Wohnzimmer", "side": -1.0, "rect": Rect2(x_out, W_LEFT_SPLIT_Z + 0.12, W_LEFT - 0.12 - x_out, z_front - W_LEFT_SPLIT_Z - 0.12)},
		{"role": "Bad", "label": "WC_Bad", "side": -1.0, "rect": Rect2(W_LEFT + 0.12, z_back, W_BATH_X - 0.12 - W_LEFT - 0.12, W_BATH_Z - 0.12 - z_back)},
		{"role": "Kueche", "label": "Kueche", "side": 1.0, "rect": Rect2(W_LEFT + 0.12, W_KITCHEN_Z + 0.12, 2.55 - W_LEFT - 0.12, z_front - W_KITCHEN_Z - 0.12)},
	]

static func build(lb: LevelBuilder, templates, n: Node3D, w: float, d: float) -> void:
	_eg_walls(lb, n, w, d)
	n.set_meta("plan_rooms", plan_rooms(w, d))
	var rise := -CELLAR_FLOOR / STEPS
	# Kellerboden und Außenwände (unter Gelände, daher nur von innen und im Kellerhals sichtbar).
	lb.box(Vector3(0, CELLAR_FLOOR - 0.2, 0), Vector3(w - 0.1, 0.2, d - 0.1), "stone", 0, true, n)
	var ch := -0.30 - CELLAR_FLOOR
	var door_c := landing_x0() + LANDING * 0.5
	for side in [-1.0, 1.0]:
		var gaps: Array = []
		if side < 0:
			gaps.append([door_c, 1.0, 0.0, 1.95, false])
		lb._wall(n, Vector3(0, CELLAR_FLOOR, side * d * 0.5), w + 0.3, ch, 0.3, 0.0, gaps, "plaster")
		lb._wall(n, Vector3(side * w * 0.5, CELLAR_FLOOR, 0), d - 0.3, ch, 0.3, PI * 0.5, [], "plaster")
	# Mittelwand laut Schnitt, zwei Durchgänge.
	lb._wall(n, Vector3(0, CELLAR_FLOOR, 0), w - 0.3, ch, WALL_T, 0.0, [[-2.6, 1.2, 0.0, 1.95, false], [door_c - 0.4, 1.2, 0.0, 1.95, false]], "plaster")
	# Kellerhals: Stufen (abwärts nach +x), Podest, Stützwände, Brüstung über Gelände.
	var z_in := -d * 0.5 - 0.15
	var zc := z_in - WELL_CLEAR * 0.5
	var lx0 := landing_x0()
	lb.box(Vector3(lx0 + LANDING * 0.5, CELLAR_FLOOR - 0.2, zc), Vector3(LANDING, 0.2, WELL_CLEAR), "stone", 0, true, n)
	for i in STEPS - 1:
		var top := -(i + 1) * rise
		lb.box(Vector3(TOP_X + (i + 0.5) * RUN, CELLAR_FLOOR - 0.2, zc), Vector3(RUN + 0.01, top - CELLAR_FLOOR + 0.2, WELL_CLEAR), "stone", 0, true, n)
	var r := stairwell_rect(w, d)
	var z_wall := z_in - WELL_CLEAR - WALL_T * 0.5
	lb.box(Vector3(r.get_center().x, CELLAR_FLOOR - 0.2, z_wall), Vector3(r.size.x, -CELLAR_FLOOR + 0.2 + 0.45, WALL_T), "stone", 0, true, n)
	lb.box(Vector3(lx0 + LANDING + WALL_T * 0.5, CELLAR_FLOOR - 0.2, zc), Vector3(WALL_T, -CELLAR_FLOOR + 0.2 + 0.45, WELL_CLEAR + 0.01), "stone", 0, true, n)
	# Geländer auf der Brüstung (Rohr, 0,95 m über Gelände)
	lb.box(Vector3(r.get_center().x, 0.92, z_wall), Vector3(r.size.x, 0.05, 0.05), "darkwood", 0, false, n)
	for x in [r.position.x + 0.1, r.get_center().x, r.end.x - 0.1]:
		lb.box(Vector3(x, 0.45, z_wall), Vector3(0.05, 0.5, 0.05), "darkwood", 0, false, n)
	# Kellerleuchten (je Kellerhälfte) baut room_lighting.gd aus plan_levels.cellar_floor (Modell + Licht, Tageszyklus).
	_cellar_decor(lb, templates, n, w, d)
	_yard_decor(lb, templates, n, w, d)
	n.set_meta("plan_storeys", ["Keller", "EG", "OG", "Dach"])
	n.set_meta("plan_levels", {"cellar_floor": CELLAR_FLOOR, "eg_floor": 0.05, "og_floor": OG_FLOOR,
		"eaves": 6.0, "roof_slope_deg": rad_to_deg(ROOF_SLOPE), "cellar_clear": ch})
	n.set_meta("plan_probes", [
		{"name": "Keller West", "point": Vector3(-3.0, CELLAR_FLOOR, 1.6)},
		{"name": "Keller Ost", "point": Vector3(3.0, CELLAR_FLOOR, -1.6)},
		{"name": "Kellerhals Podest", "point": Vector3(lx0 + LANDING * 0.5, CELLAR_FLOOR, zc)},
		{"name": "Kellertreppe Mitte", "point": Vector3(TOP_X + 6.5 * RUN, -7 * rise, zc)},
		{"name": "EG Gang", "point": Vector3(1.4, 0.05, -1.8)},
		{"name": "EG Küche", "point": Vector3(0.0, 0.05, 1.5)},
		{"name": "OG Flur", "point": Vector3(-0.2, OG_FLOOR, -3.4)}])
	n.set_meta("cellar_path", [n.to_global(Vector3(TOP_X - 1.2, 0.05, zc - 0.2)), n.to_global(Vector3(-3.0, CELLAR_FLOOR + 0.05, 1.6))])
	n.set_meta("plan_room_points", {"Zimmer": Vector3(-4.0, 0.05, -2.4), "Wohnzimmer": Vector3(-4.0, 0.05, 2.4),
		"WC_Bad": Vector3(-0.75, 0.05, -3.4), "Kueche": Vector3(0.4, 0.05, 1.0), "Gang": Vector3(1.4, 0.05, -1.8)})

static func _eg_walls(lb: LevelBuilder, n: Node3D, w: float, d: float) -> void:
	var h := EG_WALL_H
	var t := 0.18
	# Längswand linke Zimmer | Gang/Küche, Türen zum Zimmer (vom Gang) und zum Wohnzimmer (von der Küche).
	# _wall mit yaw π/2: lokale Wand-x entspricht −z.
	lb._wall(n, Vector3(W_LEFT, 0, 0), d - 0.3, h, t, PI * 0.5, [[2.2, 1.0, 0.0, 2.1, false], [-1.4, 1.0, 0.0, 2.1, false]], "plaster")
	# Zimmer | Wohnzimmer
	var lx0 := -w * 0.5 + 0.15
	var lx1 := W_LEFT - t * 0.5
	lb._wall(n, Vector3((lx0 + lx1) * 0.5, 0, W_LEFT_SPLIT_Z), lx1 - lx0, h, t, 0.0, [], "plaster")
	# WC/Bad hinten Mitte (Tür zum Gang)
	var bx0 := W_LEFT + t * 0.5
	var bx1 := W_BATH_X
	lb._wall(n, Vector3((bx0 + bx1) * 0.5, 0, W_BATH_Z), bx1 - bx0, h, t, 0.0, [[0.0, 0.8, 0.0, 2.05, false]], "plaster")
	var bz0 := -d * 0.5 + 0.15
	lb._wall(n, Vector3(W_BATH_X, 0, (bz0 + W_BATH_Z) * 0.5), W_BATH_Z - bz0, h, t, PI * 0.5, [], "plaster")
	# Gang | Küche (Plan: Küchentür vom Gang)
	var kx0 := W_LEFT + t * 0.5
	var kx1 := 2.6
	lb._wall(n, Vector3((kx0 + kx1) * 0.5, 0, W_KITCHEN_Z), kx1 - kx0, h, t, 0.0, [[0.7 - (kx0 + kx1) * 0.5, 1.1, 0.0, 2.1, false]], "plaster")
	# Kaminzug zwischen Küche und rechtem Zimmer (im Plan schraffierter Schornstein)
	lb.box(Vector3(2.75, 0, W_KITCHEN_Z + 0.25), Vector3(0.38, h, 0.38), "brick", 0, true, n)

static func _p(templates, n: Node3D, model: String, local: Vector3, yaw: float, s: float, collide: bool, group := "bavaria_house16_decor") -> Node3D:
	var p: Node3D = templates.prop(model, n.to_global(local), n.global_rotation.y + yaw, s, collide)
	if p:
		p.add_to_group(group)
		p.add_to_group("bavaria_decorations")
		p.set_meta("house16_local", local)
	return p

static func _cellar_decor(lb: LevelBuilder, templates, n: Node3D, w: float, d: float) -> void:
	var f := CELLAR_FLOOR
	# Vorratsregale mit Eingemachtem an der Westwand (Nordhälfte)
	for z in [-3.9, -2.5]:
		var shelf := lb.box(Vector3(-6.05, f, z), Vector3(0.45, 1.8, 1.25), "darkwood", 0, true, n)
		for y in [0.45, 0.95, 1.45]:
			lb.box(Vector3(-6.05, f + y, z), Vector3(0.47, 0.04, 1.27), "wood", 0, false, n)
			for k in 4:
				_p(templates, n, "e_flaska1" if (k + int(y * 10)) % 2 == 0 else "e_flaska2", Vector3(-6.05, f + y + 0.04, z - 0.45 + k * 0.3), 0.0, 0.55, false, "bavaria_house16_cellar")
		shelf.add_to_group("bavaria_house16_cellar")
	# Fässer und Kisten (Ostseite Süd), Kohlenhaufen mit Bretterverschlag (Südwest), Werkzeug auf Kiste
	for spec in [[Vector3(5.7, f, 3.9), 0.0], [Vector3(4.9, f, 4.0), 0.6], [Vector3(5.8, f, 3.0), 1.1]]:
		_p(templates, n, "k_barelmir3", spec[0], spec[1], 0.9, true, "bavaria_house16_cellar")
	_p(templates, n, "e_pbx1", Vector3(-5.7, f, -0.9), 0.3, 1.1, true, "bavaria_house16_cellar")
	_p(templates, n, "e_pbx1", Vector3(5.4, f, 1.4), 1.2, 1.2, true, "bavaria_house16_cellar")
	var bin := Node3D.new()
	bin.name = "Kohlenverschlag"
	n.add_child(bin)
	bin.position = Vector3(-5.4, f, 3.6)
	lb.box(Vector3(0, 0, -0.95), Vector3(2.0, 0.9, 0.06), "darkwood", 0, true, bin)
	lb.box(Vector3(-0.98, 0, 0), Vector3(0.06, 0.9, 1.9), "darkwood", 0, true, bin)
	var coal := StandardMaterial3D.new()
	coal.albedo_color = Color(0.06, 0.06, 0.065)
	coal.roughness = 0.55
	lb._mats["h16_coal"] = coal
	for i in 5:
		var c := lb.box(Vector3(-0.4 + (i % 3) * 0.35, 0, 0.2 - (i / 3) * 0.5), Vector3(0.9 - i * 0.1, 0.35 - i * 0.04, 0.8), "h16_coal", 0.3 * i, false, bin)
		c.add_to_group("bavaria_house16_cellar")
	bin.add_to_group("bavaria_house16_cellar")
	_p(templates, n, "w_pliers", Vector3(-5.7, f + 0.98, -0.9), 0.5, 1.0, false, "bavaria_house16_cellar")
	_p(templates, n, "e_bucket", Vector3(-4.2, f, 4.1), 0.0, 1.0, false, "bavaria_house16_cellar")

static func _yard_decor(lb: LevelBuilder, templates, n: Node3D, w: float, d: float) -> void:
	# Hofgegenstände nicht unter dem Hausknoten (sonst zählen sie zur Gebäudehülle/-sichtbox), sondern daneben.
	var yard := Node3D.new()
	yard.name = "Hof_haus_16"
	n.get_parent().add_child(yard)
	yard.transform = n.transform
	yard.add_to_group("bavaria_house16_decor")
	# Außen: nur Bereiche ohne Türwege (Tür vorn x=0, hinten x=0,95), Kellerhals und Fensterplätze.
	# Brennholzstapel an der linken Giebelseite (unter dem Dachüberstand, typisch bayerisch).
	_p(templates, n, "ja_drevo", Vector3(-w * 0.5 - 1.1, 0.0, 0.0), PI * 0.5, 0.7, true)
	# Hackstock mit Axt-Ersatz und Schubkarre hinter dem Haus links
	_p(templates, n, "ja_klada2", Vector3(6.0, 0.0, -d * 0.5 - 2.4), 0.4, 0.8, true)
	_p(templates, n, "e_wuchar", Vector3(-0.9, 0.0, -d * 0.5 - 2.9), 1.1, 1.0, true)
	# Milchkannen/Eimer hinten links neben der Badwand (Türweg x=0,95 frei; Front zum Dorfweg bleibt frei)
	for k in 3:
		_p(templates, n, "e_bucket", Vector3(-1.0 - k * 0.42, 0.0, -d * 0.5 - 0.55), 0.0, 1.0, false)
	# Hausbank an der Rückseite zwischen Schussfenster (x=−4,37) und Bad
	var bench := Node3D.new()
	bench.name = "Hausbank"
	yard.add_child(bench)
	bench.position = Vector3(-2.75, 0, -d * 0.5 - 0.45)
	bench.rotation.y = PI
	lb.box(Vector3(0, 0.42, 0), Vector3(1.6, 0.06, 0.38), "h16_wood" if lb._mats.has("h16_wood") else "wood", 0, true, bench)
	for x in [-0.7, 0.7]:
		lb.box(Vector3(x, 0, 0), Vector3(0.08, 0.42, 0.32), "darkwood", 0, false, bench)
	lb.box(Vector3(0, 0.48, -0.17), Vector3(1.6, 0.4, 0.05), "darkwood", 0, false, bench)
	bench.add_to_group("bavaria_house16_decor")
	# Wäscheleine zwischen zwei Pfosten hinten rechts (über Kopfhöhe, ohne Kollision der Leine)
	var line := Node3D.new()
	line.name = "Waescheleine"
	yard.add_child(line)
	line.position = Vector3(4.6, 0, -d * 0.5 - 6.0)  # nicht vor dem hinteren Schussfenster
	for x in [-2.0, 2.0]:
		lb.box(Vector3(x, 0, 0), Vector3(0.09, 2.1, 0.09), "darkwood", 0, true, line)
	lb.box(Vector3(0, 2.0, 0), Vector3(4.0, 0.015, 0.015), "stone", 0, false, line)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.82, 0.80, 0.72)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	lb._mats["h16_cloth"] = cloth
	for i in 4:
		lb.box(Vector3(-1.4 + i * 0.9, 1.35, 0), Vector3(0.6, 0.62, 0.01), "h16_cloth", 0, false, line)
	line.add_to_group("bavaria_house16_decor")
	# Lattenzaun/Gartentor: zwischen Haus und Scheune bzw. Antennenhaus ist kein Platz ohne Wegsperre (Spawn, Durchgang);
	# das vorhandene offene Gartentor (scene_details) bleibt.
