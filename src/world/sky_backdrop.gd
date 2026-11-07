extends RefCounted
## B-050 / AP-50a – Original-Himmel (LS3D „Backdrop sector“) kamerafest darstellen. Per preload genutzt (kein class_name).
##
## Original: Objekte im Backdrop-Sektor (AFRICA1 m_oblohaAF1, NORWAY m_obloha_ng1, ARCTIC1 g_A1_sky2, CZECH e_skybx*, …)
## werden ohne Kameraverschiebung gezeichnet – der Himmelswürfel „wandert“ mit der Kamera, Wolken/Licht sind in die
## Texturen gemalt [B: Sektorname/Modelle aus scene2.bin; P: kamerabezogenes Zeichnen].
## Nachbau (statt Ausblenden, fix_af1_ferne): jede Fläche bekommt einen Shader, der
##   - nur die Drehung der Kamera anwendet (Position = Weltlage relativ zum Levelursprung = relativ zur Kamera),
##   - die Tiefe fest an die Fernebene legt (Reverse-Z: winziger Wert) → steht hinter jeder Geometrie, unabhängig von
##     Kamera-far (CLASSIC ~Sichtweite, NEU 6 km) und Kartengröße; der af1-Fehler (graue Wand in der Landschaft) kann
##     nicht mehr entstehen,
##   - unbeleuchtet und ohne Nebel zeichnet (Farben/Licht stehen im Bild), keine Schatten wirft.
## Flares/Glow (2flare*, 4black/5black: schwarzer Grund) additiv. Unter dem Würfelrand bleibt der prozedurale Himmel.
## `--backdrop=0` = ausgeblendet (Stand fix_af1_ferne, Vergleichsbilder), `--backdrop=1` = alter weltfester Stand.

const GROUP := &"orig_backdrop"
const META := "sky_backdrop"

const _CODE_HEAD := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, %s;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 origin = vec3(0.0);
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - origin;
	vec3 vp = mat3(VIEW_MATRIX) * wp;        // nur Drehung: Himmel bleibt um die Kamera zentriert
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
	POSITION.z = 1e-6;                        // Reverse-Z: Tiefe ~ Fernebene, hinter jeder Geometrie
}
void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo;
	ALBEDO = c.rgb;
%s
}
"""

static var _shaders := {}
static var stats := {"meshes": 0, "surfaces": 0, "additive": 0}


static func mode() -> String:
	return String(Game.cli.get("backdrop", "2"))


static func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		if kind == "add":
			sh.code = _CODE_HEAD % ["blend_add, depth_draw_never", "\tALPHA = 1.0;"]
		else:
			sh.code = _CODE_HEAD % ["depth_draw_opaque", "\tif (c.a < 0.5) { discard; }"]
		_shaders[kind] = sh
	return _shaders[kind]


static func is_additive(mat_name: String, tex_path: String) -> bool:
	var s := (mat_name + " " + tex_path.get_file()).to_lower()
	return s.contains("flare") or s.contains("black") or s.contains("glow")


## Alle Meshes unterhalb `n` in kamerafeste Himmelsflächen umwandeln.
static func convert(n: Node, origin := Vector3.ZERO) -> int:
	var count := 0
	var list: Array = [n] + n.find_children("*", "MeshInstance3D", true, false)
	for x in list:
		var mi := x as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var tex: Texture2D = null
			var col := Color.WHITE
			var nm := ""
			var opaque_alpha := false
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
				col = (src as BaseMaterial3D).albedo_color
				opaque_alpha = (src as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			if src:
				nm = src.resource_name
			var add := is_additive(nm, tex.resource_path if tex else "")
			var m := ShaderMaterial.new()
			m.shader = _shader("add" if add else "opaque")
			m.render_priority = -100
			if tex:
				m.set_shader_parameter("albedo_tex", tex)
			if opaque_alpha:
				col.a = 1.0
			m.set_shader_parameter("albedo", col)
			m.set_shader_parameter("origin", origin)
			mi.set_surface_override_material(s, m)
			stats.surfaces += 1
			if add:
				stats.additive += 1
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.extra_cull_margin = 16384.0         # Weltlage ≠ Bildlage: nie wegschneiden
		mi.visibility_range_end = 0.0
		mi.set_meta(META, true)
		mi.add_to_group(GROUP)
		count += 1
	stats.meshes += count
	return count


static func is_backdrop_mesh(n: Node) -> bool:
	return n != null and n.has_meta(META)


## Szene hat einen sichtbaren Original-Himmel (sky_fx verzichtet dann auf Rauschwolken/Wolkenschatten)
static func present(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP):
		if (n as Node3D).is_visible_in_tree():
			return true
	return false
