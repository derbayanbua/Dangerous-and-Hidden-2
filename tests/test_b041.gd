extends "res://tests/test_gameplay.gd"
## B-041 Sichtweite CLASSIC/NEU + realistischer Himmel, B-042 HD/4K-Texturen (headless).
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_b041 --phase=classic
##   tools\godot.cmd --headless -- --mission=a2_erkundung --autoplay=test_b041 --phase=neu --view_mode=1
## classic: Nebel = Originalwerte aus extra.json (Tiefennebel Beginn/Ende, Farbe), kein Volumennebel, Kamera-far knapp
##   hinter dem Nebel, keine Ausblendung vor dem Nebelende; Option/Profil/Menü; B-042 Ablehnungsliste/Passprüfung.
## neu: kein Nebel, Kamera-far 6 km, Kleinkram mit weicher Ausblendung, große Objekte nie, LOD-Meshes erzeugt,
##   Umschalten zur Laufzeit stellt den Originalnebel wieder her.

const VD := preload("res://src/world/view_distance.gd")


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader() and PerfTuning.last.has("view_mode"):
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	await frames(5)
	var phase := String(Game.cli.get("phase", "classic"))
	_common(m)
	if phase == "neu":
		await _neu(m)
	else:
		await _classic(m)
		_b042()
	_finish()


func _common(m) -> void:
	check(Settings.VIEW_NAMES == ["CLASSIC", "NEU"], "Option Sichtweite mit zwei Stufen", str(Settings.VIEW_NAMES))
	check(Settings.PROFILE_KEYS["graphics"].has("view_mode"), "Sichtweite gehört zum Profil (graphics)")
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "view_mode", 1)
	var keep: int = Settings.view_mode
	Settings.load_from_config(cfg)
	check(Settings.view_mode == 1, "view_mode aus settings.cfg geladen", str(Settings.view_mode))
	cfg.set_value("graphics", "view_mode", 7)
	Settings.load_from_config(cfg)
	check(Settings.view_mode == 1, "ungültiger Wert wird begrenzt", str(Settings.view_mode))
	Settings.view_mode = keep
	var src := FileAccess.get_file_as_string("res://src/ui/main_menu.gd")
	check(src.contains("\"bviewmode\"") and src.contains("SICHTWEITE:"), "Menüeintrag SICHTWEITE (Optionen Anzeige)")
	var sm = m.env.sky.sky_material
	# B-050 ([D] 07.11.2026): Fotohimmel (PanoramaSkyMaterial) hat Vorrang vor dem Wolkenshader
	if bool(m.sky_fx.stats.get("photo", false)):
		check(sm is PanoramaSkyMaterial, "Fotohimmel aktiv (B-050, beide Stufen)", str(sm))
	elif Settings.quality >= 1:
		check(sm is ShaderMaterial, "Wolkenhimmel aktiv (beide Stufen)", str(sm))
		if sm is ShaderMaterial:
			check(float(sm.get_shader_parameter("haze")) > 0.0, "Horizontdunst gesetzt", str(sm.get_shader_parameter("haze")))
	check(m.sky_fx.climate == "snow", "Klimazone ARCTIC = Schnee", m.sky_fx.climate)


func _classic(m) -> void:
	var v: Dictionary = VD.orig_values(String(m.orig_mission))
	var rg: Vector2 = VD.classic_range(v)
	var e: Environment = m.env
	check(VD.mode() == Settings.VIEW_CLASSIC, "Stufe CLASSIC aktiv")
	check(float(v["view"]) > 0.0 and float(v["fog_range"]) > 0.0, "Originalwerte gelesen (view_distance, Nebellicht)",
		"view=%s fog=%s %s" % [v["view"], v["fog_range"], v["fog_name"]])
	check(e.fog_enabled and e.fog_mode == Environment.FOG_MODE_DEPTH, "Tiefennebel an")
	check(is_equal_approx(e.fog_depth_end, float(v["view"])), "Nebelende = Original-Sichtweite",
		"%.1f / %.1f" % [e.fog_depth_end, float(v["view"])])
	check(is_equal_approx(e.fog_depth_begin, rg.x) and rg.x < rg.y, "Nebelbeginn nach Regel", "%.1f" % e.fog_depth_begin)
	if v["fog_color"] != null:
		var want: Color = v["fog_color"]
		# B-050: mit Fotohimmel wird das Original-Nebellicht zu 70 % an den Foto-Horizont angeglichen (sky_fx.gd)
		if bool(m.sky_fx.stats.get("photo", false)) and m.sky_fx.stats.has("fog_color"):
			want = want.lerp(m.sky_fx.stats["fog_color"], 0.7)
		check(e.fog_light_color.is_equal_approx(want), "Nebelfarbe = Original-Nebellicht (B-050: an Foto-Horizont angeglichen)",
			"%s / %s" % [e.fog_light_color, want])
	check(not e.volumetric_fog_enabled, "kein künstlicher Volumennebel")
	Settings.apply()
	await frames(2)
	check(not e.volumetric_fog_enabled, "Volumennebel bleibt nach Settings.apply aus (Stufe %d)" % Settings.quality)
	var cam := get_viewport().get_camera_3d()
	check(cam != null and absf(cam.far - VD.camera_far()) < 0.5 and cam.far < float(v["view"]) * 1.2 + 10.0,
		"Kamera-far knapp hinter dem Nebelende", "%.1f" % (cam.far if cam else -1.0))
	var early := 0
	var total := 0
	var d: float = VD.classic_cull_distance()
	for n in m.orig.root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end > 0.0:
			total += 1
			if gi.visibility_range_end < d - 0.5:
				early += 1
	check(PerfTuning.last.get("view_mode") == "classic", "PerfTuning im CLASSIC-Modus", str(PerfTuning.last.get("view_mode")))
	check(early == 0, "keine Ausblendung vor dem Nebelende", "%d von %d (Grenze %.1f)" % [early, total, d])
	# Umschalten zur Laufzeit → NEU → zurück
	Settings.view_mode = Settings.VIEW_NEW
	Settings.apply()
	await frames(2)
	check(not e.fog_enabled and VD.camera_far() >= 5000.0, "Umschalten NEU zur Laufzeit: Nebel aus, volle Reichweite",
		"fog=%s far=%.0f" % [e.fog_enabled, VD.camera_far()])
	Settings.view_mode = Settings.VIEW_CLASSIC
	Settings.apply()
	await frames(2)
	check(e.fog_enabled and is_equal_approx(e.fog_depth_end, float(v["view"])), "zurück auf CLASSIC: Originalnebel wieder da")


func _neu(m) -> void:
	var e: Environment = m.env
	check(VD.mode() == Settings.VIEW_NEW, "Stufe NEU aktiv (--view_mode=1)")
	check(not e.fog_enabled and not e.volumetric_fog_enabled, "NEU: kein Nebel, kein Volumennebel")
	var cam := get_viewport().get_camera_3d()
	check(cam != null and cam.far >= 5000.0, "NEU: Kamera-far ≥ 5 km", "%.0f" % (cam.far if cam else -1.0))
	check(PerfTuning.last.get("view_mode") == "neu", "PerfTuning im NEU-Modus")
	var small_fade := 0
	var big_cut := 0
	for n in m.orig.root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.has_meta("b039_merged") or String(gi.get_parent().name) == "StaticMerge_B039":
			continue      # Sammelmeshes erben die Sichtweite ihrer (kleinen) Teile
		var box := gi.global_transform * gi.get_aabb()
		var s := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if s > 25.0 and gi.visibility_range_end > 0.0:
			big_cut += 1
		if s <= 0.6 and gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
			small_fade += 1
	check(big_cut == 0, "NEU: große Objekte ohne Entfernungsgrenze", str(big_cut))
	check(small_fade > 0 or PerfTuning.last.get("merge", {}).size() > 0, "NEU: Kleinkram weich ausgeblendet", str(small_fade))
	var lod: Dictionary = PerfTuning.last.get("lod", {})
	check(int(lod.get("meshes", 0)) > 0, "NEU: LOD-Meshes erzeugt", str(lod))
	check(get_viewport().mesh_lod_threshold >= 1.0 or not Settings.high_models, "NEU: LOD-Schwelle aktiv",
		str(get_viewport().mesh_lod_threshold))


func _b042() -> void:
	# Passprüfung: falsches Seitenverhältnis / verlorener Alphakanal → nächste Stufe
	var orig := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	orig.fill(Color(1, 1, 1, 0.0))
	var good := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var skew := Image.create(256, 240, false, Image.FORMAT_RGBA8)
	var noalpha := Image.create(256, 256, false, Image.FORMAT_RGB8)
	check(OrigLevel._hq_fits(orig, good), "B-042: passende KI-Textur angenommen")
	check(not OrigLevel._hq_fits(orig, skew), "B-042: falsches Seitenverhältnis abgelehnt")
	check(not OrigLevel._hq_fits(orig, noalpha), "B-042: verlorener Alphakanal abgelehnt")
	var rej := "%s/textures_4k/_reject.txt" % OrigLevel.cache_root()
	if FileAccess.file_exists(rej):
		var first := ""
		for line in FileAccess.get_file_as_string(rej).split("\n"):
			if line != "" and not line.begins_with("#"):
				first = line.get_slice("\t", 0)
				break
		check(first == "" or OrigLevel._hq_rejected("_4k", first), "B-042: Ablehnungsliste textures_4k wirkt", first)
	check(int(OrigLevel.hq_stats.get("swapped", 0)) > 0 or Settings.texture_suffixes() == [""],
		"B-042: KI-Texturen beim Laden getauscht", str(OrigLevel.hq_stats))
