class_name PerfTuning
extends RefCounted
## Bildrate auf großen Originalkarten: Sichtweite nach Objektgröße (Godot-Sichtbarkeitsbereich = HLOD ohne
## Ersatzmodelle), kleine Objekte ohne Schattenwurf, Lichter mit Entfernungsausblendung. Nur die statische Level-
## Geometrie (Figuren, Fahrzeuge, Waffen bleiben unberührt). Reichweiten skaliert mit der Qualitätsstufe; Nebel der
## Missionen (Dichte 0,0022 → > 1,5 km praktisch unsichtbar) begrenzt die Sicht ohnehin. Aufruf: MissionLoader, sobald
## die Mission steht; abschaltbar mit --perf_tuning=0 (Vergleichsmessung).

## [größte Ausdehnung bis m, Sichtweite m, Schatten werfen]
const SIZE_STEPS := [[0.6, 70.0, false], [2.0, 140.0, true], [6.0, 320.0, true], [25.0, 900.0, true]]
const QUALITY_K := [0.6, 0.8, 1.0, 1.6, 2.4]   ## Stufe 4 = „4K Ultra“ (B-013)
const LIGHT_FADE_M := 90.0
static var last := {}
const StaticMergeScript := preload("res://src/mission/static_merge.gd")


static func enabled() -> bool:
	return String(Game.cli.get("perf_tuning", "1")) != "0"


## B-039: Hauptschalter der Gesamt-Optimierung (`--b039=0` = Stand vor B-039, Vergleichsmessung). Einzelschalter:
## `--static_merge=0`, `--tex_compress=0`, `--whenever_raster=0`.
static func b039(sub := "") -> bool:
	if String(Game.cli.get("b039", "1")) == "0":
		return false
	return sub == "" or String(Game.cli.get(sub, "1")) != "0"


## B-039: Bild blockkomprimieren (BC1/BC3 bzw. BC5 für Normalen), damit Texturen im Grafikspeicher – unter WARP im
## Arbeitsspeicher – 4–8× weniger belegen. Mipmaps vorher. Kleine Bilder (< 64 px) und schon komprimierte bleiben.
static func compress_image(img: Image, normal := false) -> void:
	if img == null or img.is_compressed() or img.get_width() < 64 or img.get_height() < 64:
		return
	if img.get_width() % 4 != 0 or img.get_height() % 4 != 0:
		return
	if not img.has_mipmaps():
		img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_SRGB)


static func apply(m: Node) -> Dictionary:
	var st := {"meshes": 0, "ranged": 0, "no_shadow": 0, "lights": 0}
	if m == null or not enabled():
		last = st
		return st
	var k: float = QUALITY_K[clampi(Settings.quality, 0, 4)]
	var roots: Array = []
	var orig = m.get("orig")
	if orig != null and orig.get("root") != null:
		roots.append(orig.root)
	elif m.get("static_root") != null:
		roots.append(m.static_root)
	for r in roots:
		for n in (r as Node).find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			st.meshes += 1
			var box := gi.global_transform * gi.get_aabb()
			var s := maxf(box.size.x, maxf(box.size.y, box.size.z))
			for step in SIZE_STEPS:
				if s <= float(step[0]):
					var rng := float(step[1]) * k
					gi.visibility_range_end = rng
					gi.visibility_range_end_margin = rng * 0.1
					gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
					st.ranged += 1
					if not bool(step[2]) and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						st.no_shadow += 1
					break
	for n in m.find_children("*", "Light3D", true, false):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		l.distance_fade_enabled = true
		l.distance_fade_begin = LIGHT_FADE_M * k
		l.distance_fade_length = 20.0
		st.lights += 1
	last = st
	st["merge"] = StaticMergeScript.apply(m)   # B-039: nach den Sichtweiten (Gruppen übernehmen sie)
	print("PERF: Sichtweiten %d/%d Objekte, %d ohne Schatten, %d Lichter mit Ausblendung" % [st.ranged, st.meshes, st.no_shadow,
		st.lights])
	return st
