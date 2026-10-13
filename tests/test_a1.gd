extends "res://tests/test_gameplay.gd"
## Original-Mission Arctic 1A: Level, Akteure, Skripte, Ziele.
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_a1


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and Game.current_mission_id == "a1_blizzard", "Original-Mission Arctic 1A geladen")
	check(m.orig != null and m.orig.stats.meshes > 1000, "Original-Level aus scene.4ds", "%d Meshes" % m.orig.stats.meshes)
	check(m.orig.stats.instances > 1500, "Objektinstanzen aus scene2.bin", str(m.orig.stats.instances))
	check(m.squad.members.size() == 4, "Vier Kommandos an Original-Startpositionen")
	var rt: LsRuntime = m.runtime
	check(rt != null and rt.vms.size() >= 100, "Originalskripte laufen", "%d VMs" % rt.vms.size())
	check(rt.waypoints.size() > 200, "KI-Wegpunkte aus check2.bin", str(rt.waypoints.size()))
	var oh: OrigHud = m.hud.orig_hud if m.hud else null
	check(oh != null and oh.elements.size() > 80, "Original-HUD (gameinterface.4ds) aktiv", "%d Elemente" % (oh.elements.size() if oh else 0))
	await frames(3)
	if oh:
		check(oh.elements.has("player00") and (oh.elements["player00"]["node"] as Control).visible
			and not (oh.elements["player01"]["node"] as Control).visible, "HUD markiert aktiven Soldaten (Feld 1)")
		check(not (oh.elements["soldier05"]["node"] as Control).visible, "HUD: freie Felder 5–6 ausgeblendet (4 Kommandos)")
		var hb: Control = oh.elements["health00"]["node"]
		var full_h := hb.size.y
		m.squad.members[0].health = m.squad.members[0].max_health * 0.5
		oh._process(0.016)   # headless tickt fast nur Physikframes -> HUD-Aktualisierung direkt auslösen
		check(absf(hb.size.y - full_h * 0.5) < 2.0, "HUD-Gesundheitsleiste folgt der Gesundheit", "%.1f von %.1f px" % [hb.size.y, full_h])
		m.squad.members[0].health = m.squad.members[0].max_health
	var ex := rt.extras
	check(ex != null and ex.stats.lights + ex.stats.spots > 60, "Original-Lichter (scene2 0x4040)",
		"%d Punkt, %d Spot" % [ex.stats.lights, ex.stats.spots] if ex else "-")
	check(ex != null and ex.stats.sounds > 20, "Original-Klangquellen (sounds.bin)", str(ex.stats.sounds) if ex else "-")
	check(ex != null and ex.stats.tracks >= 5, "Original-Spuren (tracks.dat)", str(ex.stats.tracks) if ex else "-")
	check(ex != null and ex.music.stream != null and ex.mission_music.get("normal", "") == "ar1.ogg",
		"Missionsmusik ar1.ogg (Musiktabelle Eintrag 19)")
	# Original-Grafikoptionen wirken im Level: GRAS (Vegetation) und DYNAMIK (dynamische Lichter)
	check(m.orig.grass_nodes.size() > 20, "Gras-Objekte erkannt (Option GRAS)", str(m.orig.grass_nodes.size()))
	# Texturqualität „HD (KI)“: Originaltexturen sind höchstens 512 px, KI-Fassungen bis 2048 px
	var max_w := 0
	for mi in m.orig.root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mini(mesh.get_surface_count(), 2):
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat and mat.albedo_texture:
				max_w = maxi(max_w, mat.albedo_texture.get_width())
		if max_w > 512:
			break
	check(max_w > 512, "Level nutzt KI-HD-Texturen (Option Texturqualität)", "größte Breite %d px" % max_w)
	Settings.grass = false
	Settings.dynamic_lights = false
	Settings.changed.emit()
	await frames(2)
	var grass_off: bool = m.orig.grass_nodes.all(func(g): return not g.visible)
	var lights_off: bool = ex._lights.all(func(l): return not l.visible)
	check(grass_off and lights_off and ex._lights.size() > 50, "GRAS/DYNAMIK aus: Vegetation und Lichter ausgeblendet")
	Settings.grass = true
	Settings.dynamic_lights = true
	Settings.changed.emit()
	await frames(2)
	check(m.orig.grass_nodes.all(func(g): return g.visible), "GRAS wieder an")
	var lamp_ok := m.light_at(m.lamps[0][0]) > m.light_factor if m.lamps.size() > 0 else false
	check(lamp_ok, "Original-Lichter erhellen ihre Umgebung für die Sicht-Erkennung")
	var gg := rt.actors.get("GATE_GUARD") as Soldier
	check(gg != null and gg.team == Soldier.TEAM_AXIS, "Torwache Gate_Guard gespawnt")
	var ggw: Array = gg.weapons.map(func(w): return String(w.data.id) if w else "")
	check(ggw.has("kar98k") and ggw.has("m24"), "Torwache: Karabiner 98K + Stielhandgranaten (items.dat)", str(ggw))
	check(is_equal_approx(gg.max_health, 100.0) and is_equal_approx(gg.get_node("Perception").sight_range, 35.0),
		"Torwache: Original-HP 200, Sichtweite 35 m (actors.bin)", "%.0f HP, %.0f m" % [gg.max_health, gg.get_node("Perception").sight_range])
	# Schwierigkeitsgrad des Profils wirkt wie im Original auf Gegnerwerte (leicht ×0,7)
	Game.profile["difficulty"] = 1
	m._apply_orig_params(gg, "Gate_Guard")
	check(is_equal_approx(gg.max_health, 70.0), "Schwierigkeit „leicht“: Torwache 200×0,7 HP", "%.1f HP" % gg.max_health)
	Game.profile["difficulty"] = 3
	m._apply_orig_params(gg, "Gate_Guard")
	var kan := rt.actors.get("KANISTERNIK") as Soldier
	check(kan != null and kan.weapons[0] != null and kan.weapons[0].data.id == &"mp40", "Kanisternik mit MP 40 (items.dat)")
	var rebel := rt.actors.get("REBEL") as Soldier
	check(rebel != null and rebel.team == Soldier.TEAM_NEUTRAL, "Sygurd (Rebel) gespawnt, neutral (Original-Seite 4)")
	check(gg.model.orig_figure != null and gg.model.orig_figure.find_child("Skeleton3D", true, false) != null,
		"Torwache als Original-Figur mit Skelett (ge01*)")
	check(m.squad.members[0].model.orig_figure != null, "Kommandos als Original-Figur (en01)")
	check(rebel.model._orig_anim != null and rebel.model._orig_anim.has_animation("walk"),
		"Sygurd mit Originalanimationen (idle/walk/run/…)")
	check(rt.in_cutscene or rt.cutscene_id == 0, "Intro-Zwischensequenz startet (CSC_RunCutscene)")
	await seconds(2.0)
	check(rt.in_cutscene and rt.cutscene_id == 1, "Original-Intro läuft (Zwischensequenz 1)")
	rt.end_cutscene()   # Überspringen wie per Leertaste
	await seconds(2.0)
	check(not rt.in_cutscene and m.controller.input_enabled, "Zwischensequenz übersprungen, Steuerung frei")
	var active := 0
	for o in m.objectives:
		if o.state != Objective.State.INACTIVE:
			active += 1
	check(active >= 1, "Skript aktiviert Missionsziele (SetObjectiveStatus)", "%d aktiv, Aufrufe %s, Zuordnung %s" % [
		active, rt.calls.get("SETOBJECTIVESTATUS", 0), m.orig_objectives])
	check(not m.finished, "Mission läuft nach dem Intro weiter", str(Game.last_result.get("reason", "")))
	if m.finished:
		for o in m.objectives:
			print("  Ziel ", o.id, " Zustand ", o.state)
		_finish()
		return
	var gb := gg.get_node("EnemyBrain") as EnemyBrain
	check(gb.script_control, "Torwache im Original-Modus 'Zombie' (skriptgesteuert)")
	check(gb.suspended, "Torwache ruht, solange kein Spieler in 107 m ist (HUMAN_Suspend)")

	# --- Originalablauf: Kontakt zu Sygurd ---
	var said: Array[String] = []
	Events.message.connect(func(t, _s): said.append(t))
	var hale := m.squad.leader()
	isolate_enemies([])   # Wachen ruhigstellen, damit kein Alarm den Ablauf ändert
	var rb := rebel.get_node("EnemyBrain") as EnemyBrain
	var rpos := rebel.global_position
	# Annäherung auf 25 m: Sygurd winkt ("Hier!")
	hale.global_position = rpos + Vector3(0, 1.0, 25)
	await seconds(6.0)
	var waved := said.any(func(t): return t == rt.text(1990241))
	check(waved, "Sygurd ruft bei Annäherung (Original-Dialog 01990241)", rt.text(1990241))
	# Auf 4 m heran: Begrüßung (01990213–16)
	hale.global_position = rebel.global_position + Vector3(0, 1.0, 3.5)
	await seconds(12.0)
	check(said.any(func(t): return t == rt.text(1990214)), "Begrüßungsdialog: " + rt.text(1990214))
	# 10 s beobachten: welchen Clip spielt Sygurd, während er sich bewegt?
	var clip_while_leading := ""
	var last := rebel.global_position
	for i in 20:
		await seconds(0.5)
		if rebel.global_position.distance_to(last) > 0.3 and clip_while_leading == "":
			clip_while_leading = rebel.model._orig_clip
		last = rebel.global_position
	var moved := rebel.global_position.distance_to(rpos)
	check(moved > 3.0, "Sygurd führt los (Wegpunkte AlBert_* / Rebel_*)", "%.1f m" % moved)
	check(clip_while_leading in ["walk", "run", "sprint"], "Original-Laufanimation während der Bewegung", clip_while_leading)
	check(not m.finished, "Mission läuft (Ziel 1 nicht verfehlt)", str(Game.last_result.get("reason", "")))

	# --- Weitere Original-Akteure: Wachhund, LKW, MG-Stellung ---
	var dog := rt.actors.get("PES_00") as Dog
	check(dog != null and dog._visual != null, "Wachhund pes_00 mit Originalmodell (Akteurtyp 30)")
	check(dog != null and dog.owner_frame == rt.actors.get("WALKER_GUARD_4"),
		"Hund folgt Besitzer walker_guard_4 (DOG_SetOwner)")
	check(dog != null and dog.aggressive, "Hund aggressiv (DOG_SETAIMODE_Aggressive)")
	var truck := rt.actors.get("AUTI_BAD") as Vehicle
	check(truck != null and truck.custom_visual != null, "LKW Auti_BAD als Fahrzeug mit Originalmodell (Opel)")
	check(truck != null and truck.fuel == 0.0, "Fahrerskript leert den Tank (Car_SetFuel(auto, 0))")
	check(rt.find_frame("Auti_BAD.WHL01") != null, "Unterframe Auti_BAD.WHL01 auffindbar (Modell.Frame)")
	# Optionales Ziel 5: LKW zerstören -> Original-Organizer meldet Signal 15 an das Zielskript
	truck.explode()
	await seconds(3.0)
	var o5 := m.objective(&"o5")
	check(o5 != null and o5.state == Objective.State.DONE, "LKW zerstört -> optionales Ziel 5 erfüllt (Originalskript)",
		str(o5.state) if o5 else "-")
	check(said.any(func(t): return t == rt.text(1990260)), "Original-Meldung: " + rt.text(1990260))
	check(dog != null and dog.alive and dog.global_position.is_finite(), "Hund lebt, Position gültig")

	print("Untertitel: ", said)
	print("Befehle ausgeführt: ", rt.calls.size(), " verschiedene; nicht umgesetzt: ", rt.unimplemented)
	_finish()
