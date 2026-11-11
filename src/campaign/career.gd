class_name Career
extends RefCounted
## Karriere-XP und 15 Dienstgrade (0.11.1). Werte identisch zur Standardtabelle des Masterservers (Rangformel v2,
## Protokoll Abschnitt 15.z). Online ist allein der Master maßgeblich; diese Tabelle dient der Anzeige und dem
## lokalen Einzelspieler-Profil (zählt nie global). LAN: unverändert nur Original-Beförderung min(⌊Punkte/10⌋, 7).

const FORMAT := 1
const FILE := "career.json"

## Stufe 1..15: Name, XP-Schwelle, Abzeichen-Platzhalter (zentrale Zuordnung, eigene einfache Grafik).
const RANKS := [
	{"level": 1, "name": "Private", "xp": 0, "badge": "pvt"},
	{"level": 2, "name": "Private First Class", "xp": 1500, "badge": "pfc"},
	{"level": 3, "name": "Corporal", "xp": 5000, "badge": "cpl"},
	{"level": 4, "name": "Sergeant", "xp": 14000, "badge": "sgt"},
	{"level": 5, "name": "Staff Sergeant", "xp": 32000, "badge": "ssg"},
	{"level": 6, "name": "Technical Sergeant", "xp": 65000, "badge": "tsg"},
	{"level": 7, "name": "First Sergeant", "xp": 115000, "badge": "1sg"},
	{"level": 8, "name": "Master Sergeant", "xp": 185000, "badge": "msg"},
	{"level": 9, "name": "Second Lieutenant", "xp": 280000, "badge": "2lt"},
	{"level": 10, "name": "First Lieutenant", "xp": 410000, "badge": "1lt"},
	{"level": 11, "name": "Captain", "xp": 580000, "badge": "cpt"},
	{"level": 12, "name": "Major", "xp": 810000, "badge": "maj"},
	{"level": 13, "name": "Lieutenant Colonel", "xp": 1100000, "badge": "ltc"},
	{"level": 14, "name": "Colonel", "xp": 1500000, "badge": "col"},
	{"level": 15, "name": "Brigadier General", "xp": 2000000, "badge": "bg"},
]
const STAR_EVERY := 250000

## XP je Ereignis (Master progression, Standard).
const REWARDS := {"pvp_kill": 20, "ai_kill": 5, "assist": 10, "objective": 150, "mission_success": 250,
	"pvp_win": 150, "extraction": 100, "revive": 50, "no_alarm": 100, "teamkill": -200}
## Grenzen (Master, Standard). Einzelspieler nutzt nur max_objectives/max_revives.
const LIMITS := {"min_active_s": 120, "max_objectives": 20, "max_revives": 10, "max_revives_per_hour": 12,
	"ai_kills_full": 120, "ai_kills_decay": 0.5, "ai_kills_max_per_hour": 400, "pvp_kills_per_victim": 5,
	"max_xp_per_hour": 4000, "bonus_allowance": 4000}


## Stand zu einer XP-Summe: {level, name, badge, xp, next_level, next_name, next_xp, remaining, progress, stars, over_max}.
static func status(xp: int) -> Dictionary:
	xp = maxi(xp, 0)
	var i := 0
	for k in RANKS.size():
		if xp >= int(RANKS[k]["xp"]):
			i = k
	var r: Dictionary = RANKS[i]
	var out := {"level": r["level"], "name": r["name"], "badge": r["badge"], "xp": xp, "stars": 0, "over_max": false}
	if i + 1 < RANKS.size():
		var n: Dictionary = RANKS[i + 1]
		var span := int(n["xp"]) - int(r["xp"])
		out.merge({"next_level": n["level"], "next_name": n["name"], "next_xp": n["xp"],
			"remaining": int(n["xp"]) - xp, "progress": float(xp - int(r["xp"])) / span})
	else:
		var over := xp - int(r["xp"])
		out["stars"] = over / STAR_EVERY
		out["over_max"] = true
		out["remaining"] = STAR_EVERY - over % STAR_EVERY
		out["progress"] = float(over % STAR_EVERY) / STAR_EVERY
	return out


static func rank_name(level: int) -> String:
	return String(RANKS[clampi(level, 1, RANKS.size()) - 1]["name"])


## Zentrale Zuordnung Dienstgrad → Abzeichen-Platzhalter (eigene Grafik unter res://assets/ui/career/<badge>.png,
## fehlt sie, zeichnet das Menü das Kürzel).
static func badge_of(level: int) -> String:
	return String(RANKS[clampi(level, 1, RANKS.size()) - 1]["badge"])


static func badge_path(level: int) -> String:
	return "res://assets/ui/career/%s.png" % badge_of(level)


## Platzhalter-Abzeichen, prozedural (eigene einfache Grafik, keine Vorlage): Stufen 1–8 Winkel (1–3) + Balken
## darunter, Offiziere 9–14 senkrechte Balken/Raute, 15 Stern. Liefert bei vorhandener Datei badge_path() diese.
static func badge_texture(level: int, size := 32) -> Texture2D:
	level = clampi(level, 1, RANKS.size())
	if ResourceLoader.exists(badge_path(level)):
		return load(badge_path(level))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.85, 0.75, 0.45) if level >= 9 else Color(0.8, 0.8, 0.75)
	var u := size / 16.0
	if level <= 8:
		var chev := clampi(level - 1, 0, 3) if level < 4 else 3
		for k in chev:
			for x in size:
				var y := int(abs(x - size / 2.0) * 0.6 + 3 * u + k * 3 * u)
				img.fill_rect(Rect2i(x, size - 1 - y - int(u), 1, maxi(1, int(u * 1.5))), c)
		for k in maxi(0, level - 4):      # Wippen unter den Winkeln
			img.fill_rect(Rect2i(int(3 * u), int(size - 3 * u - k * 2 * u), int(10 * u), maxi(1, int(u))), c)
		if level == 1:
			img.fill_rect(Rect2i(int(6 * u), int(6 * u), int(4 * u), int(4 * u)), c)
	elif level <= 14:
		var bars: int = [1, 2, 2, 2, 2, 3][level - 9]
		for k in bars:
			img.fill_rect(Rect2i(int((4 + k * 4) * u), int(3 * u), int(2 * u), int(10 * u)), c)
		if level >= 12:
			img.fill_rect(Rect2i(int(6 * u), int(12 * u), int(4 * u), int(2 * u)), Color(0.7, 0.7, 0.7))
	else:
		for y in size:
			var w := int((1.0 - abs(y - size / 2.0) / (size / 2.0)) * size * 0.45)
			img.fill_rect(Rect2i(size / 2 - w, y, w * 2, 1), c)
	return ImageTexture.create_from_image(img)


## XP einer Einzelspielermission. result = Game.last_result {success, stats{kills, alarm}, objectives[[text, state, optional]]}.
static func mission_xp(result: Dictionary) -> Dictionary:
	var st: Dictionary = result.get("stats", {})
	var done := 0
	for o in result.get("objectives", []):
		if typeof(o) == TYPE_ARRAY and o.size() > 1 and int(o[1]) == 1:     # Objective.State.DONE
			done += 1
	done = mini(done, int(LIMITS["max_objectives"]))
	var ok := bool(result.get("success", false))
	var parts := {"ai_kill": int(st.get("kills", 0)) * int(REWARDS["ai_kill"]),
		"objective": done * int(REWARDS["objective"]),
		"mission_success": int(REWARDS["mission_success"]) if ok else 0,
		"no_alarm": int(REWARDS["no_alarm"]) if ok and not bool(st.get("alarm", false)) else 0}
	var total := 0
	for k in parts:
		total += int(parts[k])
	parts["total"] = maxi(total, 0)        # Karriere sinkt nie
	return parts


static func new_profile() -> Dictionary:
	return {"format": FORMAT, "xp": 0, "missions": 0, "successes": 0, "ai_kills": 0, "objectives": 0, "play_time_s": 0}


static func path_for(dir: String) -> String:
	return dir.path_join(FILE)


## Lokales Profil laden (Rückfall .bak/.tmp über Game.read_save, falls vorhanden). Fehlt es → neues Profil.
static func load_profile(dir: String) -> Dictionary:
	var p := path_for(dir)
	var txt := ""
	for f in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(f):
			txt = FileAccess.get_file_as_string(f)
			var d = JSON.parse_string(txt)
			if typeof(d) == TYPE_DICTIONARY and int(d.get("format", 0)) >= 1 and int(d.get("format", 0)) <= FORMAT:
				var out := new_profile()
				out.merge(d, true)
				out["xp"] = maxi(int(out["xp"]), 0)
				return out
	return new_profile()


static func save_profile(dir: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var d := data.duplicate()
	d["format"] = FORMAT
	var game := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Game")
	if game == null:
		return ERR_UNAVAILABLE
	return game.write_file_atomic(path_for(dir), JSON.stringify(d, "\t"))     # Game.write_file_atomic (.tmp → .bak → ersetzen)


## Missionsergebnis auf das Profil anwenden und speichern. Liefert {gained, old, new, promoted}.
static func apply_mission(dir: String, result: Dictionary) -> Dictionary:
	var prof := load_profile(dir)
	var x := mission_xp(result)
	var old := status(int(prof["xp"]))
	prof["xp"] = int(prof["xp"]) + int(x["total"])
	prof["missions"] = int(prof["missions"]) + 1
	if bool(result.get("success", false)):
		prof["successes"] = int(prof["successes"]) + 1
	prof["ai_kills"] = int(prof["ai_kills"]) + int(result.get("stats", {}).get("kills", 0))
	prof["objectives"] = int(prof["objectives"]) + int(x["objective"]) / int(REWARDS["objective"])
	prof["play_time_s"] = int(prof["play_time_s"]) + int(result.get("time", 0))
	save_profile(dir, prof)
	var nw := status(int(prof["xp"]))
	return {"gained": x["total"], "parts": x, "old": old, "new": nw, "promoted": int(nw["level"]) > int(old["level"])}
