extends "res://tests/test_gameplay.gd"
## B-013 Grafik-Modernisierung (headless): Grafikstufen inkl. „4K Ultra“ (Optionen, Stufenwechsel zur Laufzeit,
## Umgebungs-/Schatten-/Texturwerte), Wolkenhimmel + Wolkenschatten, Explosionen erzeugen ihre Effekte je Stufe,
## Kamera-Erschütterung, Explosion ohne Schadensänderung.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_graphics


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	var keep_q: int = Settings.quality
	var keep_tex: int = Settings.texture_quality

	# --- Stufen ---
	check(Settings.QUALITY_NAMES.size() == 5 and Settings.QUALITY_NAMES[4] == "4K Ultra", "Grafikstufe „4K Ultra“ vorhanden",
		str(Settings.QUALITY_NAMES))
	Settings.quality = 9
	check(Settings.quality == 4, "Stufe wird auf 0..4 begrenzt", str(Settings.quality))
	Settings.texture_quality = 1
	Settings.quality = 4
	check(Settings.texture_suffixes()[0] == "_4k", "4K Ultra wählt textures_4k zuerst", str(Settings.texture_suffixes()))
	Settings.quality = 2
	check(Settings.texture_suffixes()[0] == "_hd", "Hoch: HD-Texturen nach Texturoption", str(Settings.texture_suffixes()))
	var expect := [  # [ssao, ssil, sdfgi, vol_fog, ssr]
		[false, false, false, false, false], [true, false, false, false, false], [true, false, false, true, false],
		[true, true, true, true, false], [true, true, true, true, true]]
	var shadow_d: Array = []
	for q in 5:
		Settings.quality = q
		Settings.apply()
		await frames(2)
		var e: Environment = m.env
		var got := [e.ssao_enabled, e.ssil_enabled, e.sdfgi_enabled, e.volumetric_fog_enabled, e.ssr_enabled]
		check(got == expect[q], "Stufe %s: SSAO/SSIL/SDFGI/Vol.-Nebel/SSR" % Settings.QUALITY_NAMES[q], str(got))
		shadow_d.append(m.sun.directional_shadow_max_distance)
		var sky_mat = e.sky.sky_material
		if q == 0:
			check(sky_mat is ProceduralSkyMaterial, "Niedrig: schneller prozeduraler Himmel", str(sky_mat))
		else:
			check(sky_mat is ShaderMaterial and (sky_mat as ShaderMaterial).shader.resource_path.ends_with("sky_clouds.gdshader"),
				"Stufe %d: Wolkenhimmel-Shader aktiv" % q, str(sky_mat))
		var dec: Decal = m.sky_fx.shadow_decal
		var want_shadow: bool = q >= 2 and not m.sky_fx.night and m.sun.light_energy >= 0.5
		check((dec != null and is_instance_valid(dec)) == want_shadow, "Stufe %d: Wolkenschatten %s" % [q, "an" if want_shadow else "aus"],
			"night=%s sun=%.2f" % [m.sky_fx.night, m.sun.light_energy])
	check(shadow_d[4] > shadow_d[3] and shadow_d[3] > shadow_d[0], "Schattenweite steigt mit der Stufe", str(shadow_d))
	check(get_viewport().use_taa, "4K Ultra: TAA aktiv (bei FXAA/aus)")
	Settings.quality = 3
	Settings.apply()
	check(Settings.aa_mode == 5 or not get_viewport().use_taa, "unter 4K Ultra kein erzwungenes TAA")
	var p := (m.env.sky.sky_material as ShaderMaterial)
	var top: Color = p.get_shader_parameter("sky_top")
	check(top.is_equal_approx(m.sky_fx.procedural.sky_top_color), "Himmelsfarbe der Mission übernommen", str(top))
	check(m.sky_fx.wind_world().length() > 2.0 and m.sky_fx.wind_world().length() < 15.0, "Wolkenwind 2–15 m/s",
		str(m.sky_fx.wind_world().length()))
	var SkyFx = load("res://src/world/sky_fx.gd")
	check(SkyFx.cloud_mask(64, 0.45).get_width() == 128, "Wolkenmaske 2×2 gekachelt")

	# --- Optionen-Overlay ---
	var om: Control = load("res://src/ui/options_menu.gd").new()
	add_child(om)
	await frames(2)
	var ob: OptionButton = null
	for n in om.find_children("*", "OptionButton", true, false):
		if (n as OptionButton).item_count == Settings.QUALITY_NAMES.size() and (n as OptionButton).get_item_text(4) == "4K Ultra":
			ob = n
	check(ob != null, "Optionen: Auswahl Grafikqualität mit 4K Ultra")
	if ob:
		ob.select(4)
		ob.item_selected.emit(4)
		check(Settings.quality == 4, "Optionen: Auswahl setzt 4K Ultra", str(Settings.quality))
	om.queue_free()

	# --- Explosionen ---
	var s: Soldier = m.squad.leader()
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = s.global_position + Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw)) * 8.0
	var hp0: float = s.health
	var counts: Array = []
	for q in 5:
		Settings.quality = q
		var c0: int = Effects.explosion_count
		Effects.explosion(at, 5.0, [])
		await frames(2)
		var le: Dictionary = Effects.last_explosion
		check(Effects.explosion_count == c0 + 1 and le.has("node") and is_instance_valid(le["node"]),
			"Stufe %d: Explosion erzeugt Effektknoten" % q)
		var parts: PackedStringArray = le.get("parts", PackedStringArray())
		var need := ["Fireball", "Smoke", "Flash"]
		if q >= 1:
			need += ["Debris", "Sparks"]
		if q >= 2:
			need += ["Shockwave"]
		if q >= 3:
			need += ["HeatHaze"]
		var miss := []
		for n in need:
			if not parts.has(n) or le["node"].get_node_or_null(n) == null:
				miss.append(n)
		check(miss.is_empty(), "Stufe %d: Teile %s" % [q, ", ".join(need)], "fehlt %s" % str(miss))
		var fb: GPUParticles3D = le["node"].get_node_or_null("Fireball")
		counts.append(fb.amount if fb else 0)
		check(fb != null and fb.amount > 0 and fb.one_shot and fb.process_material is ParticleProcessMaterial, "Stufe %d: Feuerball als GPU-Partikel" % q)
	check(counts[4] > counts[2] and counts[2] > counts[0], "Partikelmenge steigt mit der Stufe", str(counts))
	var fl: OmniLight3D = Effects.last_explosion["node"].get_node_or_null("Flash")
	check(fl != null and fl.light_energy > 0.0, "Explosionslicht leuchtet")
	if cam:
		check(Effects.shake_amount() > 0.0, "Kamera-Erschütterung in der Nähe", str(Effects.shake_amount()))
		await seconds(1.5)
		check(Effects.shake_amount() == 0.0 and cam.h_offset == 0.0 and cam.v_offset == 0.0, "Erschütterung klingt ab, Kamera zurückgesetzt")
	else:
		check(true, "keine aktive Kamera (headless) – Erschütterung übersprungen")
	check(is_equal_approx(s.health, hp0), "Effects.explosion verändert keinen Schaden (nur Darstellung)", "%s → %s" % [hp0, s.health])
	check(is_equal_approx(WeaponDB.explosion_damage(250.0, 5.0, 2.5), 125.0), "Explosionsschaden weiter linear nach items.sav",
		str(WeaponDB.explosion_damage(250.0, 5.0, 2.5)))
	Settings.quality = 4
	Effects.explosion(at, 10.0, [], &"artillery")
	var art: Dictionary = Effects.last_explosion
	Effects.explosion(at, 4.0, [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_WATER])
	var wat: Dictionary = Effects.last_explosion
	check(float(art["lifetime"]) > 6.0, "Artillerie (B-011): lange Rauchsäule", str(art["lifetime"]))
	check(not wat["parts"].has("Fireball") and wat["parts"].has("Smoke"), "Wasser: Fontäne statt Feuerball", str(wat["parts"]))
	await seconds(9.0)
	check(not is_instance_valid(art["node"]), "Explosionsknoten werden wieder freigegeben")
	Settings.quality = keep_q
	Settings.texture_quality = keep_tex
	Settings.apply()
	_finish()
