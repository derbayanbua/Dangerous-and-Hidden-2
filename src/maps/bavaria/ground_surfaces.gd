extends RefCounted
## Bodenmaterialien nur für Bavaria; keine Änderung anderer Karten.
## Die Bodentexturen (assets/maps/bavaria/ground/boden*.png) sind optional und nicht im Repository.
## Fehlen sie, bleiben die neutralen Materialien des LevelBuilders (Originaltexturen aus orig_cache bzw.
## prozedurale Farben, gesetzt in templates.gd) – `available` ist dann false.
var materials: Dictionary = {}
var sources: Dictionary = {}
var available := false
const GROUND_DIR := "res://assets/maps/bavaria/ground/"
const TEXTURES := [["grass_tex","boden_gras.png"],["flower_tex","boden-mit-mehrblumen.png"],["soil_tex","boden-mit-erde.png"],["light_soil_tex","boden_leicht_erdig.png"],["gravel_tex","boden_stein.png"],["stone_grass_tex","boden_stein_gras.png"]]
var _lb: LevelBuilder

func _init(lb: LevelBuilder) -> void:
	_lb = lb
	for pair in TEXTURES:
		if not ResourceLoader.exists(GROUND_DIR + pair[1]):
			continue
		var texture := load(GROUND_DIR + pair[1]) as Texture2D
		if texture == null:
			continue
		# Die Bodentexturen haben schmale helle Ränder (1–4 Pixel): beim Laden 8 px ausschließen.
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image = image.get_region(Rect2i(8,8,image.get_width()-16,image.get_height()-16))
		image.generate_mipmaps()
		sources[pair[0]] = ImageTexture.create_from_image(image)
	available = sources.size() == TEXTURES.size()
	if not available:
		sources.clear()
		return
	for entry in [["grass",0],["meadow",1],["earth",2],["gravel",3],["edge",4]]:
		var mat := ShaderMaterial.new()
		mat.shader = load(GROUND_DIR + "ground.gdshader")
		for key in sources:
			mat.set_shader_parameter(key,sources[key])
		mat.set_shader_parameter("surface_kind",entry[1])
		materials[entry[0]] = mat
	# Kleine Bodenbeete/Brandspuren beziehen ebenfalls die Bodentexturen.
	for entry in [["earth","soil_tex"],["grass","grass_tex"],["meadow","flower_tex"]]:
		var mat := lb.mat(entry[0]).duplicate() as StandardMaterial3D
		mat.albedo_texture = sources[entry[1]]
		mat.albedo_color = Color.WHITE
		mat.uv1_scale = Vector3.ONE/2.4
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.roughness = 0.95
		lb._mats[entry[0]] = mat

func material_for(key: String, id: String) -> Material:
	if not available:
		# Ersatz: neutrale LevelBuilder-Materialien (Originaltextur bzw. prozedurale Farbe)
		match key:
			"gravel", "edge": return _lb.mat("earth")
			"meadow": return _lb.mat("meadow")
			"earth": return _lb.mat("stone" if id.begins_with("row_lane") else "earth")
			_: return _lb.mat("grass")
	if key=="earth" and id.begins_with("row_lane"):
		key = "gravel"
	if key=="earth" and id=="farm_track":
		key = "edge"
	return materials.get(key,materials.grass)
