extends RefCounted
## B-041 Sichtweite (Option Settings.view_mode, Profil). Per preload genutzt (kein class_name).
##
## CLASSIC = Nebel/Sichtweite wie im Original:
##   - Sichtgrenze = scene2.bin Kopf 0x3011 „view_distance“ (extra.json scene.view_distance) [B: Wert; P: Bedeutung
##     = Sichtweite/Nebelende]. Dahinter ist alles im Nebel (Nebelfarbe = Original-Nebellicht bzw. Hintergrundfarbe).
##   - Nebelbeginn = Reichweite des Original-Nebellichts (Licht Typ 5, Chunk 0x4044 [0], extra.json lights[type=fog].range)
##     im Primärsektor [P]; Wasser/Unterwasser/Zwischensequenz-Nebel werden nicht genommen. Liegt sie ≥ 80 % der
##     Sichtweite, beginnt der Nebel bei der halben Sichtweite [E] (sonst harte Kante).
##   - Linearer Tiefennebel (Godot FOG_MODE_DEPTH), voll deckend am Ende; Kamera-far knapp dahinter.
##   - Keine künstlichen Zusätze mehr: kein Volumennebel, keine eigenen Missionsnebel (a1–a3), keine Sichtweiten-
##     Ausblendung VOR dem Nebelende (PerfTuning blendet erst hinter dem Nebel aus).
## NEU = kein Nebel und keine Entfernungsgrenze (Kamera-far 6 km). Leistung über Ferndetails:
##   - PerfTuning: Kleinkram nach Größe weich ausgeblendet (Sichtbereich mit Überblendung, beim Annähern sofort wieder
##     da), große Objekte nie; Lichter blenden später aus.
##   - Automatische Mesh-LOD (meshoptimizer über ImporterMesh.generate_lods) für große statische Meshes; Godot wählt
##     die Stufe je Bild nach Bildschirmgröße (Nachladen beim Annähern = höhere LOD-Stufe); Texturen über Mipmaps.
## Der Himmel (sky_fx.gd) gilt für beide Stufen.

const WATER_WORDS := ["water", "voda", "sea", "under", "ponorka", "cut", "pevnost", "wa_sect", "more"]
const NEW_FAR := 6000.0
const DEFAULT_FAR := 1200.0
## Zuletzt angewandte Werte (Tests/Messung): mode, view, fog_begin, fog_end, far, fog_color, source
static var current := {}


## `--b041=0` = Stand vor B-041 (nur Vergleichsbilder/-messung): keine Sichtweitenregel, alte Nebel/Ausblendung.
static func enabled() -> bool:
	return String(Game.cli.get("b041", "1")) != "0"


static func mode() -> int:
	if not enabled():
		return Settings.VIEW_CLASSIC
	var c = Game.cli.get("view_mode", null)
	if c != null:
		return clampi(int(c), 0, 1)
	return Settings.view_mode


static func is_new() -> bool:
	return mode() == Settings.VIEW_NEW


## Kamera-Fernebene für alle Spielkameras (CameraRig, Zuschauer, Zwischensequenz)
static func camera_far() -> float:
	return float(current.get("far", DEFAULT_FAR))


## Originalwerte einer Missions-/Kartenordners aus extra.json
static func orig_values(folder: String) -> Dictionary:
	var out := {"view": 300.0, "fog_range": -1.0, "fog_color": null, "fog_name": "", "clip_far": 1000.0}
	if folder == "":
		return out
	var extra = LsRuntime._read_json(OrigLevel.cache_path(folder) + "/extra.json")
	if typeof(extra) != TYPE_DICTIONARY:
		return out
	var sc: Dictionary = extra.get("scene", {})
	if sc.get("view_distance") != null:
		out["view"] = maxf(float(sc["view_distance"]), 20.0)
	var cnf = sc.get("clip_near_far")
	if cnf is Array and cnf.size() >= 2:
		out["clip_far"] = float(cnf[1])
	var best: Dictionary = {}
	var best_score := -1
	for l in extra.get("lights", []):
		if String(l.get("type", "")) != "fog":
			continue
		var nm := String(l.get("name", "")).to_lower()
		var skip := false
		for w in WATER_WORDS:
			if nm.contains(w):
				skip = true
		if skip:
			continue
		var score := 1
		if (l.get("sectors", []) as Array).has("Primary sector"):
			score += 2
		if score > best_score:
			best_score = score
			best = l
	if not best.is_empty():
		out["fog_range"] = float(best.get("range", -1.0))
		out["fog_name"] = String(best.get("name", ""))
		var c: Array = best.get("color", [])
		if c.size() >= 3:
			out["fog_color"] = Color(c[0], c[1], c[2])
	return out


## Nebelbeginn/-ende nach der CLASSIC-Regel (s. Kopf)
static func classic_range(v: Dictionary) -> Vector2:
	var end := float(v.get("view", 300.0))
	var r := float(v.get("fog_range", -1.0))
	var begin := r if r > 0.0 and r < end * 0.8 else end * 0.5
	return Vector2(begin, end)


## Auf die Umgebung einer Mission anwenden. Nur Originalmissionen/-karten (Ordner bekannt) bekommen die Originalwerte;
## eigene Karten behalten in CLASSIC ihren Nebel, in NEU entfällt er auch dort.
static func apply(m: Node, env: Environment) -> Dictionary:
	if env == null:
		return {}
	if not enabled():
		current = {"mode": -1, "far": DEFAULT_FAR, "source": "vor B-041"}
		return current
	var folder := ""
	var om = m.get("orig_mission") if m else null
	if om != null:
		folder = String(om)
	var md := mode()
	var st := {"mode": md, "folder": folder}
	if folder != "":
		env.set_meta("b041_no_volfog", true)
		env.volumetric_fog_enabled = false
	if md == Settings.VIEW_NEW:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.set_meta("b041_no_volfog", true)
		st["far"] = NEW_FAR
		st["source"] = "neu"
	elif folder != "":
		var v := orig_values(folder)
		var rg := classic_range(v)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = rg.x
		env.fog_depth_end = rg.y
		env.fog_depth_curve = 1.0
		env.fog_density = 1.0
		env.fog_aerial_perspective = 0.0
		env.fog_sky_affect = 0.35        # Horizont geht in den Nebel über, Wolken bleiben sichtbar
		if v["fog_color"] != null:
			env.fog_light_color = v["fog_color"]
		st["view"] = v["view"]
		st["fog_begin"] = rg.x
		st["fog_end"] = rg.y
		st["fog_name"] = v["fog_name"]
		st["fog_color"] = env.fog_light_color
		st["far"] = rg.y * 1.05 + 5.0
		st["source"] = "original"
	else:
		st["far"] = DEFAULT_FAR
		st["source"] = "eigene Karte"
	current = st
	if m and m.is_inside_tree():
		var cam := m.get_viewport().get_camera_3d()
		if cam and not cam.has_meta("b041_keep_far"):
			cam.far = camera_far()
	return st


## Sichtbereichsende für PerfTuning: CLASSIC = nichts vor dem Nebelende ausblenden (dahinter unsichtbar);
## liefert -1, wenn keine Originalgrenze gilt.
static func classic_cull_distance() -> float:
	if int(current.get("mode", 0)) != Settings.VIEW_CLASSIC or not current.has("fog_end"):
		return -1.0
	return float(current["fog_end"]) * 1.05 + 5.0
