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


static func enabled() -> bool:
	return String(Game.cli.get("perf_tuning", "1")) != "0"


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
	print("PERF: Sichtweiten %d/%d Objekte, %d ohne Schatten, %d Lichter mit Ausblendung" % [st.ranged, st.meshes, st.no_shadow,
		st.lights])
	return st
