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
## B-041 Sichtweite NEU: [größte Ausdehnung bis m, Sichtweite m (0 = nie), Schatten] – Überblendung statt Aufpoppen
const NEW_STEPS := [[0.6, 150.0, false], [2.0, 350.0, true], [6.0, 800.0, true], [25.0, 0.0, true]]
const LIGHT_FADE_NEW_M := 220.0
const LOD_MIN_VERTS := 600         ## B-041: LOD erst ab dieser Eckenzahl je Mesh
const LOD_MAX_TOTAL := 4000000       ## Obergrenze Ecken je Karte (Ladezeit/Speicher)
static var last := {}
const StaticMergeScript := preload("res://src/mission/static_merge.gd")
const ViewDistanceScript := preload("res://src/world/view_distance.gd")


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
	# B-041: CLASSIC mit Originalnebel → nichts vor dem Nebelende ausblenden (dahinter ist alles unsichtbar);
	# NEU → Kleinkram weich nach Größe ausblenden, große Objekte nie (keine Entfernungsgrenze).
	var classic_d: float = ViewDistanceScript.classic_cull_distance()
	var neu: bool = ViewDistanceScript.is_new()
	st["view_mode"] = "neu" if neu else ("classic" if classic_d > 0.0 else "eigen")
	var steps: Array = NEW_STEPS if neu else SIZE_STEPS
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
			for step in steps:
				if s <= float(step[0]):
					var rng := float(step[1]) * k
					if classic_d > 0.0:
						rng = classic_d + s      # Abstand zählt zur Objektmitte: Größe zuschlagen (Rand noch im Nebel)
					if rng <= 0.0:
						break                                # NEU: groß = nie ausblenden (Schatten bleiben)
					gi.visibility_range_end = rng
					if neu:
						gi.visibility_range_end_margin = rng * 0.15
						gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
					else:
						gi.visibility_range_end_margin = 0.0 if classic_d > 0.0 else rng * 0.1
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
		if neu:
			l.distance_fade_begin = LIGHT_FADE_NEW_M * k
		elif classic_d > 0.0:
			l.distance_fade_begin = maxf(LIGHT_FADE_M * k, classic_d - 20.0)
		l.distance_fade_length = 20.0
		st.lights += 1
	last = st
	st["merge"] = StaticMergeScript.apply(m)   # B-039: nach den Sichtweiten (Gruppen übernehmen sie)
	if neu and String(Game.cli.get("neu_lod", "1")) != "0":
		st["lod"] = _generate_lods(roots)        # B-041: vereinfachte Meshes für die Ferne
	print("PERF: Sichtweiten %d/%d Objekte, %d ohne Schatten, %d Lichter mit Ausblendung (%s)" % [st.ranged, st.meshes,
		st.no_shadow, st.lights, st.view_mode])
	return st


## B-041: automatische Detailstufen (meshoptimizer über ImporterMesh.generate_lods) für große statische Level-Meshes.
## Godot wählt je Bild die Stufe nach Bildschirmgröße (Viewport.mesh_lod_threshold) – fern vereinfacht, beim Annähern
## wieder voll. Gemeinsame Meshes werden nur einmal umgebaut. Nur Dreiecksflächen ohne Skin/Blendshapes.
static func _generate_lods(roots: Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var res := {"meshes": 0, "verts": 0, "skipped": 0, "ms": 0}
	var done := {}
	for r in roots:
		if r == null or not is_instance_valid(r):
			continue
		for n in (r as Node).find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if not mi.visible or mi.skin != null or mi.has_meta("b039_merged"):
				continue
			var am := mi.mesh as ArrayMesh
			if am == null:
				continue
			if done.has(am):
				if done[am] != null:
					mi.mesh = done[am]
				continue
			done[am] = null
			if am.get_blend_shape_count() > 0:
				continue
			var verts := 0
			var ok := true
			for s in am.get_surface_count():
				verts += am.surface_get_array_len(s)
				if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					ok = false
			if not ok or verts < LOD_MIN_VERTS:
				continue
			if res.verts + verts > LOD_MAX_TOTAL:
				res.skipped += 1
				continue
			var im := ImporterMesh.new()
			for s in am.get_surface_count():
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(s), [], {}, am.surface_get_material(s),
					am.surface_get_name(s))
			im.generate_lods(60.0, 0.0, [])
			var nm := im.get_mesh()
			if nm == null:
				continue
			for meta in am.get_meta_list():
				nm.set_meta(meta, am.get_meta(meta))
			done[am] = nm
			mi.mesh = nm
			res.meshes += 1
			res.verts += verts
	res.ms = Time.get_ticks_msec() - t0
	print("PERF: LOD %d Meshes (%d Ecken, %d übersprungen) in %d ms" % [res.meshes, res.verts, res.skipped, res.ms])
	return res
