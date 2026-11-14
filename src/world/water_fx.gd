extends RefCounted
## Wasseroptik (BEWUSSTE ABWEICHUNG vom Original). Per preload (kein class_name).
## 0.10.1: Normandie 3 („voda“, ersetzte die Normandy3.bik-Filmtextur). 0.10.8: alle Originalkarten – jede erkannte
## Wasserfläche (`OrigLevel.water_meshes`, gleiche Erkennung wie Schwimmen: QuadPatch/„more“, Material VODA*/MORE*)
## bekommt `water_realistic.gdshader` mit einem Stil je Klimazone [D]. Basisfarbe = mittlere Albedo des Original-
## materials, zum Stil gemischt (Originalfarben bleiben erkennbar). Qualität je `Settings.quality`, Ausblenden zum
## Nebelende (CLASSIC) bzw. zur Fernebene (NEU). Rückfall: Option `Settings.water_mode` = ORIGINAL bzw. `--water=orig`.
## Kollision, Schwimmen/Tauchen und Navmesh bleiben unberührt (nur material_override).

const SHADER := preload("res://src/world/water_realistic.gdshader")

## Stile je Klimazone [D]: Farben, Durchsicht, Trübung, Wellen, Schaum, Strömung
const STYLES := {
	"arctic": {"shallow_color": Color(0.30, 0.46, 0.50), "deep_color": Color(0.03, 0.10, 0.15), "clarity": 3.5,
		"turbidity": 0.0, "wave_height": 0.03, "wave_scale": 1.2, "normal_strength": 0.45, "foam_amount": 0.15,
		"edge_foam": 0.55, "foam_color": Color(0.90, 0.95, 0.98), "flow": Vector2(0.04, 0.02), "roughness_base": 0.03},
	# 0.10.8 nach Kontrollbild no1: vorher (Durchsicht 1,6/Trübung 0,15/Normale 0,7) silbrig und Meeresgrund-Raster sichtbar
	"normandy": {"shallow_color": Color(0.20, 0.30, 0.25), "deep_color": Color(0.05, 0.10, 0.09), "clarity": 0.9,
		"turbidity": 0.55, "wave_height": 0.09, "wave_scale": 1.6, "normal_strength": 0.5, "foam_amount": 0.6,
		"edge_foam": 0.8, "foam_color": Color(0.85, 0.88, 0.86), "flow": Vector2(0.10, 0.05), "roughness_base": 0.06},
	"burma": {"shallow_color": Color(0.36, 0.30, 0.18), "deep_color": Color(0.14, 0.11, 0.06), "clarity": 0.5,
		"turbidity": 0.8, "wave_height": 0.015, "wave_scale": 0.8, "normal_strength": 0.35, "foam_amount": 0.0,
		"edge_foam": 0.3, "foam_color": Color(0.62, 0.56, 0.44), "flow": Vector2(0.35, 0.10), "roughness_base": 0.10},
	"norway": {"shallow_color": Color(0.10, 0.20, 0.22), "deep_color": Color(0.01, 0.04, 0.06), "clarity": 2.4,
		"turbidity": 0.05, "wave_height": 0.05, "wave_scale": 1.4, "normal_strength": 0.55, "foam_amount": 0.2,
		"edge_foam": 0.45, "foam_color": Color(0.80, 0.85, 0.88), "flow": Vector2(0.06, 0.03), "roughness_base": 0.04},
	"africa": {"shallow_color": Color(0.22, 0.42, 0.40), "deep_color": Color(0.03, 0.14, 0.18), "clarity": 2.2,
		"turbidity": 0.1, "wave_height": 0.03, "wave_scale": 1.0, "normal_strength": 0.5, "foam_amount": 0.15,
		"edge_foam": 0.5, "foam_color": Color(0.92, 0.92, 0.86), "flow": Vector2(0.05, 0.03), "roughness_base": 0.03},
	"czech": {"shallow_color": Color(0.22, 0.28, 0.20), "deep_color": Color(0.05, 0.08, 0.06), "clarity": 1.0,
		"turbidity": 0.45, "wave_height": 0.02, "wave_scale": 0.9, "normal_strength": 0.45, "foam_amount": 0.0,
		"edge_foam": 0.35, "foam_color": Color(0.75, 0.78, 0.72), "flow": Vector2(0.30, 0.08), "roughness_base": 0.06},
	"alps": {"shallow_color": Color(0.20, 0.34, 0.34), "deep_color": Color(0.03, 0.08, 0.10), "clarity": 2.5,
		"turbidity": 0.1, "wave_height": 0.02, "wave_scale": 0.9, "normal_strength": 0.45, "foam_amount": 0.0,
		"edge_foam": 0.4, "foam_color": Color(0.88, 0.92, 0.94), "flow": Vector2(0.25, 0.06), "roughness_base": 0.04},
	"default": {"shallow_color": Color(0.17, 0.29, 0.25), "deep_color": Color(0.03, 0.08, 0.08), "clarity": 1.4,
		"turbidity": 0.1, "wave_height": 0.04, "flow": Vector2(0.22, 0.06), "edge_foam": 0.3},
}
## Zusätzliche Frames je Kartenordner (klein), die keine erkannte Wasserfläche sind (Normandie 3: „voda“ mit Film)
const EXTRA_FRAMES := {"normandy3_mp": ["voda"], "normandy3_mp_zone": ["voda"]}
## Abweichende Parameter einzelner Karten [D] (Normandie 3: Fluss unter der Brücke wie in 0.10.1)
const MAP_OVERRIDES := {
	"normandy3_mp": {"wave_height": 0.04, "wave_scale": 1.0, "foam_amount": 0.0, "flow": Vector2(0.22, 0.06), "clarity": 1.4},
	"normandy3_mp_zone": {"wave_height": 0.04, "wave_scale": 1.0, "foam_amount": 0.0, "flow": Vector2(0.22, 0.06), "clarity": 1.4},
}
## Anteil der Originalfarbe an der Wasserfarbe [D]
const ORIG_TINT := 0.3
## Grafikstufe → Wellenzahl, Kräuselung, Schaum-Faktor
const QUALITY := [[2, 0.0, 0.0], [3, 0.2, 0.6], [4, 0.35, 1.0], [6, 0.35, 1.0], [6, 0.45, 1.0]]

static var stats := {}


## Klimazone nach Kartenordner (Originalordnername, klein).
static func zone_of(folder: String) -> String:
	var f := folder.to_lower()
	for z in ["arctic", "normandy", "burma", "norway", "czech", "alps"]:
		if f.begins_with(z):
			return z
	if f.begins_with("africa") or f.begins_with("afrika"):
		return "africa"
	return "default"


static func enabled() -> bool:
	return String(Game.cli.get("water", "new")) != "orig" and Settings.water_mode == 0


## Parameter für eine Karte (Stil + Kartenabweichung + Grafikstufe).
## true, wenn mi unter einem angehängten Modell (Frame „m_*“) unterhalb von root liegt.
## True if mi sits below an attached model frame ("m_*") under root.
static func _under_model(mi: Node, root: Node) -> bool:
	var n := mi
	while n != null and n != root:
		if String(n.name).to_lower().begins_with("m_"):
			return true
		n = n.get_parent()
	return false


static func params_for(folder: String, quality: int) -> Dictionary:
	var p: Dictionary = (STYLES["default"] as Dictionary).duplicate()
	p.merge(STYLES[zone_of(folder)], true)
	p.merge(MAP_OVERRIDES.get(folder.to_lower(), {}), true)
	var q: Array = QUALITY[clampi(quality, 0, QUALITY.size() - 1)]
	p["wave_count"] = q[0]
	p["ripple"] = q[1]
	p["foam_amount"] = float(p.get("foam_amount", 0.0)) * float(q[2])
	p["edge_foam"] = float(p.get("edge_foam", 0.0)) * float(q[2])
	return p


static func apply(mission: Node, orig) -> int:
	stats = {"meshes": 0, "surfaces": 0, "zone": "", "enabled": false}
	if orig == null:
		return 0
	var key := String(mission.get("orig_mission")).to_lower()
	stats["zone"] = zone_of(key)
	if not enabled():
		return 0
	var targets: Array = []
	for mi in orig.get("water_meshes") if orig.get("water_meshes") != null else []:
		if is_instance_valid(mi) and not targets.has(mi):
			targets.append(mi)
	for fname in EXTRA_FRAMES.get(key, []):
		var node: Node3D = orig.nodes.get(fname)
		if node == null:
			for k in orig.nodes:
				if String(k).to_lower() == String(fname).to_lower():
					node = orig.nodes[k]
					break
		if node == null:
			continue
		# 0.11.4: nur die Wasserfläche selbst, keine angehängten Kinder (Normandy 3: Felsen m_N3_oppisk_39 unter
		# „voda“ bekam sonst den Wassershader). / Only the water surface itself, not attached children.
		var meshes: Array = []
		if node is MeshInstance3D:
			meshes.append(node)
		for mi2 in node.find_children("*", "MeshInstance3D", true, false):
			if not _under_model(mi2, node):
				meshes.append(mi2)
		for mi in meshes:
			if not targets.has(mi):
				targets.append(mi)
	if targets.is_empty():
		return 0
	var params := params_for(key, Settings.quality)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	# Originalfarbe einmischen (mittlere Albedo der Originalmaterialien)
	var oc := _orig_color(targets)
	if oc.a > 0.0:
		params["shallow_color"] = (params["shallow_color"] as Color).lerp(Color(oc.r, oc.g, oc.b), ORIG_TINT)
		params["deep_color"] = (params["deep_color"] as Color).lerp(Color(oc.r, oc.g, oc.b) * 0.3, ORIG_TINT * 0.5)
	for p in params:
		mat.set_shader_parameter(p, params[p])
	mat.render_priority = -1
	for mi in targets:
		var m3 := mi as MeshInstance3D
		if m3 == null or m3.mesh == null:
			continue
		m3.set_meta("water_orig_override", m3.material_override)
		m3.material_override = mat
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m3.set_meta("b039_merged_skip", true)
		m3.set_meta("water_fx", true)
		stats["meshes"] += 1
		stats["surfaces"] += m3.mesh.get_surface_count()
	# Filmtexturen auf Wasser (meshplayer) nicht mehr sichtbar → Wiedergabe beenden (nur Normandie 3 wie 0.10.1)
	if stats["meshes"] > 0 and EXTRA_FRAMES.has(key):
		for vp in mission.find_children("MovieTexture_*", "VideoStreamPlayer", true, false):
			(vp as VideoStreamPlayer).stop()
			vp.get_parent().queue_free()
	stats["material"] = mat
	stats["enabled"] = stats["meshes"] > 0
	stats["params"] = params
	if stats["meshes"] > 0:
		var upd := func():
			update_fade(mat)
			_update_quality(mat, key)
		if mission.is_node_ready():
			upd.call()
		else:
			mission.ready.connect(upd, CONNECT_ONE_SHOT)
		Settings.changed.connect(upd)
		mission.tree_exited.connect(func():
			if Settings.changed.is_connected(upd):
				Settings.changed.disconnect(upd), CONNECT_ONE_SHOT)
	return int(stats["meshes"])


static func _orig_color(targets: Array) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for mi in targets:
		var m3 := mi as MeshInstance3D
		if m3 == null or m3.mesh == null:
			continue
		for i in m3.mesh.get_surface_count():
			var m := m3.get_active_material(i)
			if m is BaseMaterial3D:
				var c: Color = (m as BaseMaterial3D).albedo_color
				var t := (m as BaseMaterial3D).albedo_texture
				if t and t.get_image():
					var img := t.get_image()
					if img.is_compressed():
						img = img.duplicate()
						img.decompress()
					img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
					c *= img.get_pixel(0, 0)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		if n >= 8:
			break
	if n == 0:
		return Color(0, 0, 0, 0)
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z, 1.0)


static func _update_quality(mat: ShaderMaterial, key: String) -> void:
	if not is_instance_valid(mat):
		return
	var q: Array = QUALITY[clampi(Settings.quality, 0, QUALITY.size() - 1)]
	var base := params_for(key, 4)
	mat.set_shader_parameter("wave_count", q[0])
	mat.set_shader_parameter("ripple", q[1])
	mat.set_shader_parameter("foam_amount", float(base.get("foam_amount", 0.0)) * float(q[2]))
	mat.set_shader_parameter("edge_foam", float(base.get("edge_foam", 0.0)) * float(q[2]))
	stats["quality"] = Settings.quality


## Wasser vor dem Nebelende ausblenden (CLASSIC); NEU ohne Nebel: erst an der Kamera-Fernebene
static func update_fade(mat: ShaderMaterial) -> void:
	if not is_instance_valid(mat):
		return
	var vd = preload("res://src/world/view_distance.gd")
	var c: Dictionary = vd.current
	var fe := float(c.get("fog_end", -1.0))
	if fe <= 0.0:
		fe = float(c.get("far", 6000.0)) * 0.95
	mat.set_shader_parameter("far_fade_begin", fe * 0.8)
	mat.set_shader_parameter("far_fade_end", fe * 0.98)
	stats["fade_end"] = fe * 0.98
