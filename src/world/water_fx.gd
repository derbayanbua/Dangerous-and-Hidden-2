extends RefCounted
## 0.10.1 – realistisches Wasser (BEWUSSTE ABWEICHUNG, Nutzerauftrag 07.11.2026). Per preload (kein class_name).
## Ersetzt auf ausgewählten Karten das Material der Wasser-Frames (bisher Normandy3.bik-Filmtextur aus meshplayer.json)
## durch `water_realistic.gdshader` und hält den dann unnötigen Film an (spart Theora-Dekodierung).
## `--water=orig` = alter Stand (Film).

const SHADER := preload("res://src/world/water_realistic.gdshader")
## Kartenordner (klein) → [Frame-Namen, Parameter]
const MAPS := {
	"normandy3_mp": [["voda"], {"shallow_color": Color(0.17, 0.29, 0.25), "deep_color": Color(0.03, 0.08, 0.08),
		"flow": Vector2(0.22, 0.06), "clarity": 1.4}],
}
static var stats := {}


static func apply(mission: Node, orig) -> int:
	stats = {"meshes": 0, "surfaces": 0}
	if orig == null or String(Game.cli.get("water", "new")) == "orig":
		return 0
	var key := String(mission.get("orig_mission")).to_lower()
	if not MAPS.has(key):
		return 0
	var frames: Array = MAPS[key][0]
	var params: Dictionary = MAPS[key][1]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for p in params:
		mat.set_shader_parameter(p, params[p])
	mat.render_priority = -1
	for fname in frames:
		var node: Node3D = orig.nodes.get(fname)
		if node == null:
			for k in orig.nodes:
				if String(k).to_lower() == String(fname).to_lower():
					node = orig.nodes[k]
					break
		if node == null:
			continue
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi in meshes:
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			m3.material_override = mat
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m3.set_meta("b039_merged_skip", true)
			stats["meshes"] += 1
			stats["surfaces"] += m3.mesh.get_surface_count()
	# Filmtextur nicht mehr sichtbar → Wiedergabe beenden
	if stats["meshes"] > 0:
		for vp in mission.find_children("MovieTexture_*", "VideoStreamPlayer", true, false):
			(vp as VideoStreamPlayer).stop()
			vp.get_parent().queue_free()
	stats["material"] = mat
	if stats["meshes"] > 0:
		var upd := func(): update_fade(mat)
		if mission.is_node_ready():
			upd.call()
		else:
			mission.ready.connect(upd, CONNECT_ONE_SHOT)
		Settings.changed.connect(upd)
		mission.tree_exited.connect(func():
			if Settings.changed.is_connected(upd):
				Settings.changed.disconnect(upd), CONNECT_ONE_SHOT)
	return int(stats["meshes"])


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
