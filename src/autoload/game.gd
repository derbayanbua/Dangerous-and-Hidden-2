extends Node
## Spielablauf: Szenenwechsel (Menü <-> Mission), Missionsregister,
## Spielstände und Kommandozeilenoptionen für automatisierte Tests.
##
## Kommandozeile (nach "--" an Godot übergeben):
##   --mission=<id>        Mission direkt starten (überspringt Menü)
##   --screenshot=<pfad>   Nach --frames Frames Screenshot speichern und beenden
##   --frames=<n>          Frame-Anzahl für --screenshot (Standard 120)
##   --autoplay=<script>   Testskript aus res://tests/autoplay/ ausführen

const MAIN_MENU := "res://scenes/main.tscn"
const MISSION_SCENE := "res://scenes/mission.tscn"
## Spielstände und Kampagne liegen je Profil unter user://profiles/<name>/ (Original: Profile mit
## eigenem Fortschritt, Schwierigkeitsgrad und Statistik; change_profile.4ds, Texte 2151–2193).
var profiles_dir := "user://profiles"   ## Tests: --profiles_dir=user://test_profiles

## Missionsregister: id -> Daten. script = Skript, das die Welt aufbaut.
## Optionale Schlüssel eigener Karten: "map_image" (Kartenbild für den Ladebildschirm), "mp_allowed_from"
## (Original-MP-Ordner, dessen Freigabeliste ALLOWEDITEMS und Klassenvorlagen die Karte übernimmt).
## Weitere Einträge kommen optional aus den lokalen Zusatzinhalten (LOCAL_CONTENT, nicht im Repository).
var MISSIONS := {
	# Originalmission 1 (Arctic): Titel/Briefing kommen aus den Originaltexten (orig_texts)
	"a1_blizzard": {
		"title": "Arctic 1A – Erster Angriff",
		"script": "res://src/missions/a1_blizzard.gd",
		"orig_texts": [4501, 4502, 4503, 4504, 4505, 4506, 4507, 4508],
		"briefing": "",
	},
	"a2_erkundung": {
		"title": "Arctic 1B – Erkundung",
		"script": "res://src/missions/a2_erkundung.gd",
		"orig_texts": [4511, 4512, 4513, 4514, 4515, 4516, 4517],
		"briefing": "",
	},
	"a3_rendezvous": {
		"title": "Arctic 1C – Rendezvous",
		"script": "res://src/missions/a3_rendezvous.gd",
		"orig_texts": [4521, 4522, 4523, 4524, 4525, 4526, 4527],
		"briefing": "",
	},
	"m01_funkfeuer": {
		"title": "Unternehmen Funkfeuer",
		"script": "res://src/missions/m01_funkfeuer.gd",
		"briefing": "Normandie-Hinterland, Mai 1944.\n\nDie Wehrmacht betreibt auf einem Gehöft eine Funkstation, die alliierte Bomberverbände meldet. Ihr Trupp ist in der Abenddämmerung per Fallschirm südlich des Waldes gelandet.\n\nAUFTRAG\n1. Sprengen Sie den Funksender im Gehöft.\n2. Sichern Sie das Codebuch aus dem Stabsgebäude.\n3. Erreichen Sie den Abholpunkt am Weiher im Norden.\n\nOptional: Lösen Sie keinen Alarm aus. Ein ausgelöster Alarm alarmiert die gesamte Garnison.",
	},
	"m02_nordlicht": {
		"title": "Unternehmen Nordlicht",
		"script": "res://src/missions/m02_nordlicht.gd",
		"briefing": "Norwegen, Fjordküste, Januar 1943. Nacht.\n\nDie Kriegsmarine versorgt ihre U-Boote aus einem Treibstofflager am Fjord. Im Wachgebäude des Lagers wird Olav Brekke festgehalten, unser wichtigster Kontakt im Widerstand.\n\nAUFTRAG\n1. Sprengen Sie beide Tanklager (West und Ost).\n2. Befreien Sie Brekke aus dem Wachgebäude im Osten des Lagers.\n3. Bringen Sie Brekke lebend zum Boot am Ufer im Norden.\n\nHINWEISE\nZwei Suchscheinwerfer bestreichen das Gelände. Wer im Lichtkegel steht, wird sofort gesehen; die Scheinwerfer lassen sich ausschießen, das ist aber hörbar. Der Stacheldraht ist im Westen an einer Stelle durchtrennt. Laternen erhellen die Wege.\n\nStirbt Brekke, ist der Einsatz gescheitert.",
	},
	"m03_sandsturm": {
		"title": "Unternehmen Sandsturm",
		"script": "res://src/missions/m03_sandsturm.gd",
		"briefing": "Libysche Wüste, Oktober 1942. Mittag.\n\nIn einer Oase hat das Afrikakorps einen Stab eingerichtet. Drei 8,8-cm-Flak schützen den Platz gegen unsere Luftaufklärung.\n\nAUFTRAG\n1. Sprengen Sie alle drei Flak-Stellungen (Ost, West, Nord).\n2. Sichern Sie die Lagepläne aus dem Stabsquartier (größter Lehmbau).\n3. Erreichen Sie den Sammelpunkt in der Wüste im Südwesten.\n\nHINWEISE\nBei Tageslicht sieht man Sie in der offenen Wüste weit. Ein einzelner Vorposten liegt auf der Düne westlich Ihres Startpunkts: Wer die Uniform eines Gefallenen anzieht (Leiche durchsuchen, dann erneut benutzen), wird auf Abstand nicht erkannt – solange er nicht schießt und sich nicht zu nah heranwagt. Ihre übrigen Männer tragen weiter Khaki-Drillich der Briten: Lassen Sie sie zurück, wenn Sie sich getarnt einschleichen.\n\nIm Fuhrpark stehen zwei Kübelwagen. Der Sammelpunkt liegt über 150 m von der Oase entfernt.",
	},
}

## Missionsübergreifender Trupp (Original: feste Kommandotruppe mit Ausrüstung je Soldat).
const ROSTER := [
	{"pid": "sq_hale", "name": "Sgt. Hale", "loadout": ["thompson", "colt", "no36"]},
	{"pid": "sq_brennan", "name": "Cpl. Brennan", "loadout": ["enfield", "colt", "no36"]},
	{"pid": "sq_ashworth", "name": "Pte. Ashworth", "loadout": ["bren", "colt", ""]},
	{"pid": "sq_kowalski", "name": "Pte. Kowalski", "loadout": ["sten", "colt", "no36"]},
]
const ALLIED_PRIMARIES := ["sten", "thompson", "enfield", "garand", "bren"]
## Reserve: rückt für Gefallene nach (Trupp bleibt bis zu 4 Mann stark).
const RESERVE := [
	{"pid": "rs_doyle", "name": "Pte. Doyle", "loadout": ["garand", "colt", "no36"]},
	{"pid": "rs_mercer", "name": "Pte. Mercer", "loadout": ["sten", "colt", "no36"]},
	{"pid": "rs_novak", "name": "L/Cpl. Novak", "loadout": ["enfield", "colt", ""]},
	{"pid": "rs_harlow", "name": "Pte. Harlow", "loadout": ["thompson", "colt", "no36"]},
]
const SQUAD_SIZE := 4

## In der Einsatzbesprechung gewählte Ausrüstung: pid -> [primär, seitenwaffe, granate]
var loadouts := {}

## Kampagne: Reihenfolge, Freischaltung, gefallene Kadermitglieder.
var CAMPAIGN_ORDER: Array = ["a1_blizzard", "a2_erkundung", "a3_rendezvous"]

## Original-Kampagne (Hidden & Dangerous 2): [id, Missionsordner, k] mit k = Index der Original-Texttabelle
## (Titel 4501+10k …). Teile ohne eigenes Skript laufen über src/missions/orig_generic.gd.
const ORIG_CAMPAIGN := [
	["a4_eisberg", "ARCTIC4", 3],
	["af1_spaghetti_airport", "AFRICA1", 4], ["af2_flugschau", "AFRICA2", 5], ["af3_gaeste", "AFRICA3", 6],
	["af4_karawane", "AFRICA4", 7], ["af5_whiskey_bar", "AFRICA5", 8], ["af6_raubvoegel", "AFRICA6", 9],
	["nw1_dampfleitung", "NORWAY", 10],
	["bu1_ameisenhuegel", "BURMA1", 11], ["bu2_bergkoenig", "BURMA2", 12],
	["al1_waldgeister", "ALPS1", 13], ["al2_makler", "ALPS2", 14],
	["no1_leuchtturm", "NORMANDY", 16], ["no2_schwerttaenzer", "NORMANDY2", 17],
	["cz1_eintrittsgeld", "CZECH1", 18], ["cz2_maulwurf", "CZECH2", 19], ["cz3_geschaeft", "CZECH3", 20],
	["cz4_volksfest", "CZECH4", 21], ["cz5_trink_aus", "CZECH5", 22], ["cz6_abrechnung", "CZECH6", 23],
]
const ORIG_TRAINING := ["training", "TUTORIAL", 24]
## Teile mit eigener Mechanik (sonst orig_generic.gd)
const ORIG_SPECIAL_SCRIPTS := {"af6_raubvoegel": "res://src/missions/af6_raubvoegel.gd"}


## Original-Missionen anmelden (Titel aus den Originaltexten; fehlt der Cache, bleibt der Ordnername).
func _register_orig_missions() -> void:
	var texts = null
	var f := FileAccess.open(OrigLevel.cache_root() + "/texts_german.json", FileAccess.READ)
	if f:
		texts = JSON.parse_string(f.get_as_text())
	for e in ORIG_CAMPAIGN + [ORIG_TRAINING]:
		var k: int = e[2]
		var title: String = e[1]
		if typeof(texts) == TYPE_DICTIONARY and texts.has(str(4501 + 10 * k)):
			title = String(texts[str(4501 + 10 * k)])
		MISSIONS[e[0]] = {"title": title, "script": ORIG_SPECIAL_SCRIPTS.get(e[0], "res://src/missions/orig_generic.gd"), "orig": e[1], "k": k,
			"orig_texts": [4501 + 10 * k, 4502 + 10 * k, 4503 + 10 * k, 4504 + 10 * k, 4505 + 10 * k,
				4506 + 10 * k, 4507 + 10 * k, 4508 + 10 * k], "briefing": ""}
		if e != ORIG_TRAINING and not CAMPAIGN_ORDER.has(e[0]):
			CAMPAIGN_ORDER.append(e[0])
	if not PRACTICE_MISSIONS.has(ORIG_TRAINING[0]):
		PRACTICE_MISSIONS.insert(0, ORIG_TRAINING[0])
	_register_mp_maps(texts)
	# Titel der Teile 1A–1C ebenfalls aus den Originaltexten
	for pair in [["a1_blizzard", 4501], ["a2_erkundung", 4511], ["a3_rendezvous", 4521]]:
		if typeof(texts) == TYPE_DICTIONARY and texts.has(str(pair[1])):
			MISSIONS[pair[0]]["title"] = String(texts[str(pair[1])])
## Mehrspieler-Karten: Original-MP-Karten (orig_cache/mp_maps.json, tools/fmt_mp.py) und – als Arena –
## alle Kampagnenkarten (Level, Türen, Fahrzeuge der Originalmission; keine KI, keine Skripte).
var MP_MAPS: Array = []


func _register_mp_maps(texts) -> void:
	MP_MAPS.clear()
	# Lokale eigene Karten (local_content „mp_maps_first“) direkt in der Hauptauswahl, vor Originalen/Arenen.
	for id in local_content.get("mp_maps_first", []):
		if MISSIONS.has(String(id)) and not MP_MAPS.has(String(id)):
			MP_MAPS.append(String(id))
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/mp_maps.json")
	if typeof(d) == TYPE_DICTIONARY:
		# Original-MP-Karten (nur im Original spielbare, je Karte genau ein Spielstil)
		const STYLE_MODE := {"deathmatch": 0, "occupation": 2, "objectives": 3}
		const STYLE_TEXT := {"deathmatch": "Deathmatch", "occupation": "Besetzung", "objectives": "HD2-Aufgaben"}
		for e in d.get("maps", []):
			var folder := String(e.get("folder", ""))
			if folder == "" or not bool(e.get("playable_in_original", true)) \
					or not FileAccess.file_exists(OrigLevel.cache_root() + "/" + folder.to_lower() + "/scene.json"):
				continue
			var st: Array = e.get("styles", [])
			var style := String(st[0].get("style", "deathmatch")) if not st.is_empty() else "deathmatch"
			var id := "mp_" + folder.to_lower()
			MISSIONS[id] = {"title": "%s (%s)" % [String(e.get("map_name", folder)), STYLE_TEXT.get(style, style)],
				"script": "res://src/missions/mp_arena.gd", "orig": folder, "k": 0, "briefing": "",
				"mp_mode": int(STYLE_MODE.get(style, 0))}
			MP_MAPS.append(id)
	for e in [["a1_blizzard", "ARCTIC1", 0], ["a2_erkundung", "ARCTIC2", 1], ["a3_rendezvous", "ARCTIC3", 2]] + ORIG_CAMPAIGN:
		var mid: String = "mp_arena_" + String(e[0])
		MISSIONS[mid] = {"title": "Arena: " + String(MISSIONS.get(e[0], {}).get("title", e[1])),
			"script": "res://src/missions/mp_arena.gd", "orig": e[1], "k": e[2], "briefing": ""}
		MP_MAPS.append(mid)



## Eigene Prototyp-Einsätze (kein Original-Leveldesign): jederzeit wählbar, nicht Teil der Kampagne.
var PRACTICE_MISSIONS: Array = ["m01_funkfeuer", "m02_nordlicht", "m03_sandsturm"]
var campaign := {}


## Lokale Zusatzinhalte (Ordner res://local/, gitignored – NICHT im Repository): eigene Karten/Einsätze
## (Registereinträge, MP-Kartenauswahl, Übungseinsätze) und Heldenfiguren (Net.heroes()). Fehlt die Datei
## (frischer Klon), läuft das Spiel ohne diese Inhalte. Format: siehe Kopf von local_content.gd.
const LOCAL_CONTENT := "res://local/local_content.gd"
var local_content := {}


## Inhalt von LOCAL_CONTENT (static func content() -> Dictionary); {} ohne lokale Datei
static func read_local_content() -> Dictionary:
	if not ResourceLoader.exists(LOCAL_CONTENT):
		return {}
	var sc = load(LOCAL_CONTENT)
	if not (sc is Script) or not (sc as Script).get_script_method_list().any(func(m): return String(m.get("name", "")) == "content"):
		return {}
	var d = sc.content()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _load_local_content() -> void:
	local_content = read_local_content()
	var ms = local_content.get("missions", {})
	if typeof(ms) == TYPE_DICTIONARY:
		for id in ms:
			MISSIONS[String(id)] = ms[id]
	for id in local_content.get("practice_missions", []):
		if MISSIONS.has(String(id)) and not PRACTICE_MISSIONS.has(String(id)):
			PRACTICE_MISSIONS.append(String(id))


## Original-MP-Ordner, dessen Freigabeliste/Klassen eine eigene Karte übernimmt (Registerschlüssel "mp_allowed_from")
func mp_allowed_from(map: String) -> String:
	return String(MISSIONS.get(map, {}).get("mp_allowed_from", ""))


# --- Profile ---------------------------------------------------------------------

## Schwierigkeitsgrade 1..4 = Original-Texte 2157–2160 (leicht, normal, schwer, sehr schwer)
const DIFFICULTY_TEXT := {1: 2157, 2: 2158, 3: 2159, 4: 2160}
var profile := {}               ## {name, difficulty, created, playtime, kills, enemies_killed, shots, missions}
var profile_name := ""
var _memory_profile := false    ## Tests: Profil nur im Speicher, nichts wird geschrieben


func has_profile() -> bool:
	return profile_name != ""


func difficulty() -> int:
	return int(profile.get("difficulty", 2))


func profile_dir(n: String = profile_name) -> String:
	return profiles_dir + "/" + _safe_name(n)


func save_dir() -> String:
	return profile_dir() + "/saves" if has_profile() else "user://saves"


static func _safe_name(n: String) -> String:
	var out := ""
	for c in n.strip_edges():
		out += c if c.is_valid_identifier() or c in "0123456789 -" else "_"
	return out.substr(0, 40)


func list_profiles() -> Array[String]:
	var out: Array[String] = []
	if _memory_profile:
		if profile_name != "":
			out.append(profile_name)
		return out
	var d := DirAccess.open(profiles_dir)
	if d == null:
		return out
	for sub in d.get_directories():
		var f := FileAccess.open(profiles_dir + "/" + sub + "/profile.json", FileAccess.READ)
		if f:
			var p = JSON.parse_string(f.get_as_text())
			if typeof(p) == TYPE_DICTIONARY:
				out.append(String(p.get("name", sub)))
	out.sort()
	return out


func create_profile(n: String, diff: int = 2) -> bool:
	n = n.strip_edges()
	if n == "" or _safe_name(n) == "" or list_profiles().has(n):
		return false
	profile = {"name": n, "difficulty": diff, "created": Time.get_datetime_string_from_system(false, true),
		"playtime": 0.0, "kills": 0, "enemies_killed": 0, "shots": 0, "missions": 0}
	profile_name = n
	end_single_mission()
	game_mode = MODE_CAMPAIGN
	_campaigns = {}
	if not _memory_profile:
		DirAccess.make_dir_recursive_absolute(profile_dir() + "/saves")
		save_profile()
	new_campaign()
	_remember_current()
	_use_profile_options()
	return true


func select_profile(n: String) -> bool:
	if _memory_profile:
		return n == profile_name
	var f := FileAccess.open(profile_dir(n) + "/profile.json", FileAccess.READ)
	if f == null:
		return false
	var p = JSON.parse_string(f.get_as_text())
	if typeof(p) != TYPE_DICTIONARY:
		return false
	profile = p
	profile_name = n
	end_single_mission()
	game_mode = MODE_CAMPAIGN
	_campaigns = {}
	DirAccess.make_dir_recursive_absolute(profile_dir() + "/saves")
	load_campaign()
	_remember_current()
	_use_profile_options()
	return true


func rename_profile(old: String, n: String) -> bool:
	n = n.strip_edges()
	if n == "" or list_profiles().has(n) or not list_profiles().has(old):
		return false
	if not _memory_profile:
		if DirAccess.rename_absolute(profile_dir(old), profile_dir(n)) != OK:
			return false
	if old == profile_name:
		profile_name = n
		profile["name"] = n
		save_profile()
		_remember_current()
	elif not _memory_profile:
		var f := FileAccess.open(profile_dir(n) + "/profile.json", FileAccess.READ)
		var p = JSON.parse_string(f.get_as_text()) if f else {}
		if typeof(p) == TYPE_DICTIONARY:
			p["name"] = n
			var w := FileAccess.open(profile_dir(n) + "/profile.json", FileAccess.WRITE)
			if w:
				w.store_string(JSON.stringify(p, "\t"))
	return true


func delete_profile(n: String) -> bool:
	if not list_profiles().has(n):
		return false
	if not _memory_profile:
		_remove_dir(profile_dir(n))
	if n == profile_name:
		profile_name = ""
		profile = {}
		campaign = {}
		var rest := list_profiles()
		if not rest.is_empty():
			select_profile(rest[0])
		else:
			_remember_current()
			_use_profile_options()
	return true


func _remove_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_dir(path + "/" + sub)
	DirAccess.remove_absolute(path)


func set_difficulty(diff: int) -> void:
	profile["difficulty"] = clampi(diff, 1, 4)
	save_profile()


func save_profile() -> void:
	if _memory_profile or not has_profile():
		return
	var f := FileAccess.open(profile_dir() + "/profile.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "\t"))


func _remember_current() -> void:
	if _memory_profile:
		return
	DirAccess.make_dir_recursive_absolute(profiles_dir)
	var f := FileAccess.open(profiles_dir + "/current.txt", FileAccess.WRITE)
	if f:
		f.store_string(profile_name)


func _load_current_profile() -> void:
	if cli.has("autoplay") and cli.has("profiles_dir"):
		# Test mit echten Profildateien in einem eigenen, frisch geleerten Ordner (Start ohne Profil)
		profiles_dir = String(cli["profiles_dir"])
		_remove_dir(profiles_dir)   # danach normal weiter (Import, sofern nicht --noimport)
	elif cli.has("autoplay"):
		_memory_profile = true
		profile_name = "Test"
		profile = {"name": "Test", "difficulty": int(cli.get("difficulty", "3")), "playtime": 0.0,
			"kills": 0, "enemies_killed": 0, "shots": 0, "missions": 0}
		campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
		return
	_import_orig_profiles()
	var cur := ""
	if FileAccess.file_exists(profiles_dir + "/current.txt"):
		cur = FileAccess.get_file_as_string(profiles_dir + "/current.txt").strip_edges()
	if cur == "" or not select_profile(cur):
		var all := list_profiles()
		if not all.is_empty():
			select_profile(all[0])


func _use_profile_options() -> void:
	if _memory_profile:
		return
	Settings.use_profile(profile_dir() + "/options.cfg" if has_profile() else "")
	InputSetup.load_bindings()


## Original-Profile (HD2_orig\PlayersProfiles, entschlüsselt von tools/fmt_profile.py -> orig_cache/
## profiles_import.json) beim ersten Start übernehmen: Name, Schwierigkeit, Kampagnenfortschritt
## (Missionsnummer: Training 0, ARCTIC1 1 … in Kampagnenreihenfolge), letzter Spielstand, Options.bin.
## Nicht übernommen: Tastenbelegung (DirectInput-Codes) und Original-Spielstände (anderes Engine-Format).
func _import_orig_profiles() -> void:
	if _memory_profile or cli.has("noimport") or FileAccess.file_exists(profiles_dir + "/orig_import_done"):
		return
	var f := FileAccess.open(OrigLevel.cache_root() + "/profiles_import.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	DirAccess.make_dir_recursive_absolute(profiles_dir)
	var best := ""
	var best_prog := -2
	for e in data.get("profiles", []):
		var pr: Dictionary = e.get("profile", {})
		var n := String(pr.get("name", e.get("folder", ""))).strip_edges()
		if n == "" or list_profiles().has(n):
			continue
		var diff := int(pr.get("difficulty", {}).get("value", 2))
		if not create_profile(n, clampi(diff, 1, 4)):
			continue
		var prog := int(pr.get("progress", {}).get("original", {}).get("max_ordinal", -1))
		if prog >= 1:
			var upto := mini(prog, CAMPAIGN_ORDER.size())
			campaign["unlocked"] = CAMPAIGN_ORDER.slice(0, upto)
			campaign["completed"] = CAMPAIGN_ORDER.slice(0, upto - 1)
			save_campaign()
		var ls: Dictionary = pr.get("last_save", {})
		if ls.get("parts") is Dictionary:
			profile["orig_last_save"] = "%s – %s (%s)" % [ls["parts"].get("mode", ""), ls["parts"].get("mission", ""),
				ls["parts"].get("date", "")]
		profile["imported_from"] = "Hidden & Dangerous 2 (PlayersProfiles/%s)" % e.get("folder", n)
		save_profile()
		_import_orig_options(e.get("options", {}))
		if prog > best_prog:
			best_prog = prog
			best = n
	var mark := FileAccess.open(profiles_dir + "/orig_import_done", FileAccess.WRITE)
	if mark:
		mark.store_string(Time.get_datetime_string_from_system())
	if best != "":
		select_profile(best)


func _import_orig_options(o: Dictionary) -> void:
	var s: Dictionary = o.get("settings", {})
	if s.is_empty():
		return
	var pc := ConfigFile.new()
	var t: Dictionary = s.get("detail_toggles", {})
	var g := {"gamma": 0.6 + float(s.get("gamma", 50.0)) / 100.0 * 0.8,
		"shadows": t.get("shadows", true), "morphing": t.get("morphing", true), "decals": t.get("footprints_decorations", true),
		"blood": t.get("bloodstains", true), "grass": t.get("grass", true), "dynamic_lights": t.get("dynamics", true),
		"high_models": t.get("high_res_models", true), "quality": clampi(int(s.get("detail_preset", {}).get("index", 2)), 0, 2)}
	for k in g:
		pc.set_value("graphics", k, g[k])
	pc.set_value("audio", "master_volume", clampf(float(s.get("sound_volume", 80.0)) / 100.0, 0.0, 1.0))
	pc.set_value("audio", "music_volume", clampf(float(s.get("music_volume", 70.0)) / 100.0, 0.0, 1.0))
	# Original-Mausempfindlichkeit 0–100 (Standard 66,6) -> eigene Skala (Standard 0,12)
	pc.set_value("controls", "mouse_sensitivity", clampf(0.12 * float(s.get("mouse_sensitivity", 66.6)) / 66.6, 0.03, 0.4))
	pc.set_value("controls", "invert_y", bool(s.get("invert_mouse", false)))
	pc.set_value("game", "subtitles", bool(s.get("subtitles", true)))
	pc.set_value("game", "crosshair", bool(s.get("allow_crosshair", true)))
	pc.save(profile_dir() + "/options.cfg")
	Settings.use_profile(profile_dir() + "/options.cfg")


## Statistik fürs Profil (Original-Profilinfo: Spielzeit, Getötete, Munition)
func add_profile_stats(seconds: float, kills: int, shots: int) -> void:
	if not has_profile():
		return
	profile["playtime"] = float(profile.get("playtime", 0.0)) + seconds
	profile["enemies_killed"] = int(profile.get("enemies_killed", 0)) + kills
	profile["kills"] = int(profile.get("kills", 0)) + kills
	profile["shots"] = int(profile.get("shots", 0)) + shots
	profile["missions"] = int(profile.get("missions", 0)) + 1
	save_profile()


func new_campaign() -> void:
	campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
	save_campaign()


## Kampagnenstand je Spielmodus (Original: getrennter Fortschritt Kampagne/Einzelgänger/Blutbad, profile.sav 0x1F05)
func campaign_path() -> String:
	return profile_dir() + "/" + {MODE_CAMPAIGN: "campaign.json", MODE_LONE_WOLF: "campaign_lone_wolf.json",
		MODE_CARNAGE: "campaign_carnage.json"}.get(game_mode, "campaign.json")


func load_campaign() -> void:
	# Automatisierte Tests arbeiten mit einer frischen Kampagne im Speicher (je Modus)
	if _memory_profile or not has_profile() or not FileAccess.file_exists(campaign_path()):
		var fresh := {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
		campaign = _campaigns.get(game_mode, fresh) if _memory_profile else fresh
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(campaign_path()))
	if typeof(d) == TYPE_DICTIONARY and d.has("unlocked"):
		campaign = d
	else:
		new_campaign()


func save_campaign() -> void:
	if _in_preview:
		return
	if single_mission:
		return             # Original: Einzelmissionen ändern den Kampagnenstand nicht
	_campaigns[game_mode] = campaign
	if _memory_profile or not has_profile():
		return
	var f := FileAccess.open(campaign_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(campaign, "\t"))


# --- Spielmodi (Original singleplayer.4ds: Kampagne, Einzelgänger, Blutbad, Einzelmission, Einzelmission-Blutbad) ---
## Original [0x8AE924]+8 = Modus 1 Kampagne, 2 Einzelgänger, 3 Blutbad; +4 = 1 bei Einzelmission
## (re_notes_profiles). Skriptwert _SPGetGameType = Modus (+4 bei Einzelmission; die Skripte prüfen 3 oder 7 für
## Blutbad, 2 für Einzelgänger – die Zuordnung 5/7 = Einzelmission ist eine Annahme [P]).
## Einzelgänger: Team aus einem Mann, „Team wieder auffüllen“ entfällt (0x6C20F0). Blutbad: zusätzliches Ziel
## „Töten Sie die Feinde“ (T6063, *_obj_krvak.scr). Einzelmission: freigeschaltete Kampagnenmission mit Team- und
## Ausrüstungswahl (Lager = Summe aller Listen der Kampagne bis zur Mission, 0x6B93C0), ändert nichts am Stand.
const MODE_CAMPAIGN := 1
const MODE_LONE_WOLF := 2
const MODE_CARNAGE := 3
## Spielstand-Präfixe je Modus-Slot (profile.sav 0x1EFA…0x1EFE)
const MODE_PREFIX := {1: "CAM", 2: "LOW", 3: "CAR"}
const MODE_TEXT := {1: 2202, 2: 2203, 3: 2204}
var game_mode := MODE_CAMPAIGN
var single_mission := false
var _campaigns := {}             ## Kampagnenstände je Modus (Speicher; Tests ohne Dateien)
var _sm_backup := {}             ## Kampagnenstand während einer Einzelmission (Kopie wird verworfen)


func sp_game_type() -> int:
	return game_mode + (4 if single_mission else 0)


func is_carnage() -> bool:
	return game_mode == MODE_CARNAGE


func team_size() -> int:
	return 1 if game_mode == MODE_LONE_WOLF else SQUAD_SIZE


func mode_prefix() -> String:
	return ("SM" if single_mission else "") + String(MODE_PREFIX.get(game_mode, "CAM"))


func mode_title() -> String:
	if single_mission:
		return SAS.text(2206 if is_carnage() else 2205, "EINZELMISSION")
	return SAS.text(int(MODE_TEXT.get(game_mode, 2202)), "KAMPAGNE")


## Spielmodus wählen (Hauptmenü Einzelspieler). single = Einzelmission (Basis: Stand der Kampagne, als Kopie).
func set_game_mode(m: int, single := false) -> void:
	end_single_mission()
	var base: int = MODE_CAMPAIGN if single else m
	if base != game_mode:
		save_campaign()
		game_mode = base
		load_campaign()
	if single:
		_sm_backup = campaign
		campaign = campaign.duplicate(true)
		campaign["sas_prepared"] = ""
		single_mission = true
		game_mode = MODE_CARNAGE if m == MODE_CARNAGE else MODE_CAMPAIGN


func end_single_mission() -> void:
	if not single_mission:
		return
	single_mission = false
	game_mode = MODE_CAMPAIGN
	campaign = _sm_backup
	_sm_backup = {}


## Fortschritt je Modus (profile.sav 0x1F05: max, Kampagne, Einzelgänger, Blutbad = Missions-Ordinal)
func mode_progress(m: int) -> int:
	return int(profile.get("progress", {}).get(str(m), -1))


# --- Nachbesprechung: Übernahme erst bei SPEICHERN UND FORTSETZEN (Original 0x68CE00 → 0x68C300) -------------
## Mission.finish bereitet einen geänderten Kampagnenstand vor (Kopie): Gefallene, Training, Erfahrung, Ränge,
## Orden, Freischaltung, Skriptwerte. Erst commit_debrief() übernimmt ihn (und speichert den Fortschritt);
## ERNEUT VERSUCHEN / Hauptmenü verwerfen ihn.
var _pending := {}
var _in_preview := false
var _diary_pending: Array = []   ## Tagebuch-Einträge (Text-IDs) des laufenden Einsatzes (ADDDIARYTEXT)


func _pending_campaign() -> Dictionary:
	if _pending.is_empty():
		_pending = campaign.duplicate(true)
	return _pending


## f auf dem vorbereiteten Kampagnenstand ausführen (Game.campaign zeigt währenddessen auf die Kopie)
func _on_pending(f: Callable) -> Variant:
	var real := campaign
	campaign = _pending_campaign()
	_in_preview = true
	var r = f.call()
	_in_preview = false
	_pending = campaign
	campaign = real
	return r


func has_pending_debrief() -> bool:
	return not _pending.is_empty()


## SPEICHERN UND FORTSETZEN: vorbereiteten Stand übernehmen, Tagebuch anhängen, Fortschritt des Modus setzen.
## Einzelmissionen ändern nichts (Original 0x68C2E0: Übernahme nur in der Kampagne).
func commit_debrief() -> void:
	if _pending.is_empty():
		return
	if single_mission:
		_pending = {}
		_diary_pending.clear()
		return
	var diary: Array = _pending.get("diary", [])
	diary.append_array(_diary_pending)
	_pending["diary"] = diary
	_diary_pending.clear()
	campaign = _pending
	_pending = {}
	save_campaign()
	var ord := -1
	for id in campaign.get("completed", []):
		ord = maxi(ord, CAMPAIGN_ORDER.find(id) + 1)
	if ord >= 0 and has_profile():
		var pr: Dictionary = profile.get("progress", {})
		pr[str(game_mode)] = maxi(int(pr.get(str(game_mode), -1)), ord)
		pr["max"] = maxi(int(pr.get("max", -1)), ord)
		profile["progress"] = pr
		save_profile()


func discard_debrief() -> void:
	_pending = {}
	_diary_pending.clear()


## Skriptbefehl ADDDIARYTEXT(Text-ID) (ls_runtime.gd): Eintrag im Tagebuch der Nachbesprechung
func add_diary_text(text_id: int) -> void:
	if _diary_pending.is_empty() or int(_diary_pending.back()) != text_id:
		_diary_pending.append(text_id)


## Tagebuch: bisherige Einträge der Kampagne + die dieses Einsatzes (Text-IDs)
func diary_entries() -> Array:
	var out: Array = (_pending if not _pending.is_empty() else campaign).get("diary", []).duplicate()
	out.append_array(_diary_pending)
	return out


func new_diary_entries() -> Array:
	return _diary_pending.duplicate()


## Original-Skriptwerte (SaveGameValue/_LoadGameValue) über Missionsteile hinweg.
func orig_game_values() -> Dictionary:
	var out := {}
	var d: Dictionary = campaign.get("game_values", {})
	for k in d:
		out[int(k)] = d[k]
	return out


## Missionsende: Werte gehen in den vorbereiteten Stand (übernommen mit SPEICHERN UND FORTSETZEN)
func store_orig_game_values(values: Dictionary) -> void:
	var d := {}
	for k in values:
		d[str(k)] = values[k]
	_pending_campaign()["game_values"] = d


func is_unlocked(id: String) -> bool:
	return PRACTICE_MISSIONS.has(id) or campaign.get("unlocked", []).has(id)


## Briefingtext; bei Originalmissionen aus den Originaltexten (Text\german).
func briefing_text(id: String) -> String:
	var m: Dictionary = MISSIONS.get(id, {})
	if not m.has("orig_texts"):
		return m.get("briefing", "")
	var f := FileAccess.open(OrigLevel.cache_root() + "/texts_german.json", FileAccess.READ)
	var texts = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(texts) != TYPE_DICTIONARY:
		return "(Originaltexte fehlen: tools/convert_mission.py ausführen)"
	var lines: PackedStringArray = []
	var ids: Array = m["orig_texts"]
	for i in ids.size():
		lines.append(String(texts.get(str(ids[i]), "")))
		if i == 1 or i == 2:
			lines.append("")
	return "\n".join(lines).strip_edges()


func is_fallen(pid: String) -> bool:
	return campaign.get("fallen", []).has(pid)


# --- Original-Kader (SAS, src/campaign/sas.gd) --------------------------------------
## Originalkampagne: 30 SAS-Soldaten mit Werten, Rang, Erfahrung; Team (bis 4) und Inventare je Profil
## in campaign["sas"], ["team"], ["inv"], ["storage"]. Teamauswahl nur, wo das Original sie vorsieht.

const ORIG_FOLDER_1 := {"a1_blizzard": "ARCTIC1", "a2_erkundung": "ARCTIC2", "a3_rendezvous": "ARCTIC3"}


func orig_folder(id: String) -> String:
	if ORIG_FOLDER_1.has(id):
		return ORIG_FOLDER_1[id]
	return String(MISSIONS.get(id, {}).get("orig", ""))


func uses_sas(id: String) -> bool:
	return CAMPAIGN_ORDER.has(id) and orig_folder(id) != "" and SAS.available()


func sas_states() -> Dictionary:
	if not campaign.has("sas") or typeof(campaign["sas"]) != TYPE_DICTIONARY or campaign["sas"].is_empty():
		campaign["sas"] = SAS.new_states()
	return campaign["sas"]


func sas_team() -> Array:
	var out: Array = []
	for i in campaign.get("team", []):
		out.append(int(i))
	return out


func sas_inventory(idx: int) -> Dictionary:
	var invs: Dictionary = campaign.get("inv", {})
	if not invs.has(str(idx)):
		invs[str(idx)] = SAS.new_inventory()
		campaign["inv"] = invs
	return invs[str(idx)]


func set_sas_team(team: Array) -> void:
	campaign["team"] = team.duplicate()


## Teamauswahl im Menü erforderlich? „select“ = freie Auswahl, „refill“ = Gefallene ersetzen.
func sas_team_mode(id: String) -> String:
	var mode := SAS.team_mode(SAS.mission_info(orig_folder(id)))
	if sas_team().is_empty():
		return "select"
	if single_mission:
		return "select"            # Einzelmission: Ablauf Team (Typ 2) → Ausrüstung (0x6B9680)
	if mode == "keep" and sas_team().size() < team_size() and _alive_team().size() == 0:
		return "select"
	if mode == "refill" and game_mode == MODE_LONE_WOLF:
		return "keep" if not _alive_team().is_empty() else "select"     # 0x6C20F0: Auffüllen entfällt
	return mode


func _alive_team() -> Array:
	var st := sas_states()
	return sas_team().filter(func(i): return st.has(str(i)) and not st[str(i)]["dead"])


## Vor einem Kampagneneinsatz: Team gültig machen (Gefallene raus; automatische Auswahl, falls nötig),
## Lager nach Gamedata00.gdt befüllen, Inventare neuer Mitglieder mit der Original-Empfehlung ausstatten,
## Missionsgegenstände (miss_itm.def „essentials“) sicherstellen. Mehrfach aufrufbar (nur einmal je Mission).
func prepare_sas(id: String, force := false) -> void:
	if not uses_sas(id):
		return
	if campaign.get("sas_prepared", "") == id and not force:
		return
	var info := SAS.mission_info(orig_folder(id))
	var st := sas_states()
	var team := _alive_team()
	var mode := sas_team_mode(id)
	var new_storage: bool = info.get("equipment_screen") == "equipment_new_storage"   # null = kein Ausrüstungsbildschirm
	if team.size() > team_size():
		team = team.slice(0, team_size())
	if team.is_empty() or mode in ["select", "refill"]:
		team = SAS.auto_select(st, team_size(), team if mode != "select" or not team.is_empty() else [])
	set_sas_team(team)
	if mode == "select" and not single_mission:
		_defence_medal(info)
	if single_mission:
		campaign["storage"] = single_mission_storage(id)
		new_storage = true
	else:
		campaign["storage"] = SAS.mission_storage(info, campaign.get("storage", []))
	var rec := SAS.recommended_presets(info)
	# Empfohlene Presets: schwerstes Preset an den kräftigsten Soldaten (Traglast = Kraft)
	var need: Array = []
	for i in team.size():
		var inv := sas_inventory(team[i])
		var empty: bool = int(inv.get("hands", -1)) < 0 and inv.get("items", []).is_empty()
		if empty or (new_storage and mode == "select"):
			need.append(team[i])
	var presets: Array = []
	for i in need.size():
		presets.append(SAS.preset_inventory(rec[i % rec.size()] if not rec.is_empty() else 1))
	presets.sort_custom(func(a, b): return SAS.inv_weight(a) > SAS.inv_weight(b))
	need.sort_custom(func(a, b): return float(st[str(a)]["stats"]["strength"]) > float(st[str(b)]["stats"]["strength"]))
	for i in need.size():
		campaign["inv"][str(need[i])] = presets[i]
	ensure_essentials(id)
	# Grundausstattung jedes Soldaten: Messer (Original „knife - GB“ 57) und Verbandskasten (54)
	for idx in team:
		var inv := sas_inventory(idx)
		var strength := float(st[str(idx)]["stats"]["strength"])
		for basic in [57, 54]:
			if SAS.count_of(inv, basic) == 0 and SAS.can_add(inv, strength, basic):
				SAS.add_item(inv, basic, 1)
	for idx in team:
		fit_inventory(idx, id)
	campaign["sas_prepared"] = id
	save_campaign()


## Kampagnenbeginn (Teamauswahl Typ 2, 0x6908F0): lebende Soldaten der Tabelle 0x841CB0[Kampagne] erhalten die
## Defence Medal (Orden 6), sofern noch nicht vorhanden.
func _defence_medal(info: Dictionary) -> void:
	var camp := String(info.get("campaign", ""))
	var given: Array = campaign.get("defence_given", [])
	if camp == "" or given.has(camp):
		return
	var r = LsRuntime._read_json(OrigLevel.cache_root() + "/roster.json")
	var table: Array = r.get("defence_medal_table_0x841CB0", {}).get(camp, []) if typeof(r) == TYPE_DICTIONARY else []
	var st := sas_states()
	for idx in table:
		var s: Dictionary = st.get(str(int(idx)), {})
		if s.is_empty() or bool(s.get("dead", false)):
			continue
		var med: Array = s.get("medals", [])
		if not med.has(SAS.MEDAL_DEFENCE):
			med.append(SAS.MEDAL_DEFENCE)
		s["medals"] = med
	given.append(camp)
	campaign["defence_given"] = given


## Einzelmission (0x6B93C0): Lager = Summe aller Lagerlisten der Kampagne bis einschließlich dieser Mission
func single_mission_storage(id: String) -> Array:
	var info := SAS.mission_info(orig_folder(id))
	var camp := String(info.get("campaign", ""))
	var ord := int(info.get("ordinal", -1))
	var out: Array = []
	for i in range(0, ord + 1):
		var mi := {}
		for c in CAMPAIGN_ORDER:
			var m := SAS.mission_info(orig_folder(c))
			if int(m.get("ordinal", -2)) == i:
				mi = m
		if mi.is_empty() or String(mi.get("campaign", "")) != camp:
			continue
		for e in SAS.mission_storage(mi, []):
			var found := false
			for o in out:
				if int(o[0]) == int(e[0]):
					o[1] = int(o[1]) + int(e[1])
					found = true
			if not found:
				out.append([int(e[0]), int(e[1])])
	return out


## Überladung abbauen (Original sperrt das Fortsetzen bei Überladung): zuerst Munition/Kleinteile aus dem
## Inventar ins Lager, dann die Schulterwaffe. Benötigte Missionsgegenstände bleiben.
func fit_inventory(idx: int, id: String = current_mission_id) -> void:
	var inv := sas_inventory(idx)
	var strength := float(sas_states()[str(idx)]["stats"]["strength"])
	var keep: Array = SAS.essentials(SAS.mission_info(orig_folder(id))).map(func(e): return e[0])
	if not campaign.has("storage"):
		campaign["storage"] = []
	var store := {"items": campaign["storage"]}
	var guard := 200
	while SAS.overloaded(inv, strength) and guard > 0:
		guard -= 1
		var victim := -1
		for i in range(inv["items"].size() - 1, -1, -1):
			if not keep.has(int(inv["items"][i][0])):
				victim = int(inv["items"][i][0])
				break
		if victim >= 0:
			SAS.add_item(store, victim, SAS.remove_item(inv, victim, 1))
		elif int(inv.get("shoulder", -1)) >= 0:
			SAS.add_item(store, int(inv["shoulder"]), 1)
			inv["shoulder"] = -1
		else:
			break


## Benötigte Gegenstände der Mission (z. B. Arctic1: Drahtschere, Fotoapparat) ins Team-Inventar
func ensure_essentials(id: String) -> void:
	var team := sas_team()
	if team.is_empty():
		return
	var info := SAS.mission_info(orig_folder(id))
	if bool(info.get("solo_mission", false)):
		# nur team[0] wird eingesetzt (ARCTIC2): Gegenstände von den anderen zu ihm umlagern
		for e in SAS.essentials(info):
			for idx in team.slice(1):
				var n := SAS.remove_item(sas_inventory(idx), e[0], e[1])
				if n > 0:
					SAS.add_item(sas_inventory(team[0]), e[0], n)
		team = team.slice(0, 1)
	for e in SAS.essentials(info):
		var have := 0
		for idx in team:
			have += SAS.count_of(sas_inventory(idx), e[0])
		if have >= e[1]:
			continue
		var target: int = team[0]
		for idx in team:
			if SAS.can_add(sas_inventory(idx), float(sas_states()[str(idx)]["stats"]["strength"]), e[0], e[1] - have):
				target = idx
				break
		SAS.add_item(sas_inventory(target), e[0], e[1] - have)


func is_sas_pid(pid: String) -> bool:
	return pid.begins_with("sas_")


func sas_index(pid: String) -> int:
	return int(pid.substr(4)) if is_sas_pid(pid) else -1


func _sas_entry(idx: int) -> Dictionary:
	var st: Dictionary = sas_states().get(str(idx), {})
	return {"pid": "sas_%d" % idx, "name": SAS.short_name(idx, int(st.get("rank", 0))), "sas": idx}


## Kaderwerte, Inventar und Ausrüstung eines SAS-Soldaten auf die Spielfigur übertragen
## (Gesundheit wie Gegner mit OrigMission.HP_SCALE; Magazine/Granaten/Verbände aus dem Inventar).
func apply_sas(s: Soldier, pid: String) -> void:
	var idx := sas_index(pid)
	var st: Dictionary = sas_states().get(str(idx), {})
	if st.is_empty():
		return
	var stats: Dictionary = st["stats"]
	# HumanStore-Gesundheit in zotti (Spawn 0x59EDC0 → Mensch +0xEC), Spielskala 1 = 10 zotti wie Gegner und Waffenschaden
	s.max_health = maxf(float(stats.get("health", 500)) * OrigMission.HP_SCALE, 1.0)
	s.health = s.max_health
	s.skill_shooting = float(stats.get("shooting", 50))
	s.skill_stealth = float(stats.get("stealth", 50))
	s.skill_endurance = float(stats.get("endurance", 50))
	s.skill_first_aid = float(stats.get("first_aid", 50))
	var lo := SAS.to_loadout(sas_inventory(idx))
	s.medkits = int(lo["medkits"])
	s.has_binoculars = bool(lo["binoculars"])
	s.set_meta("orig_items", lo["items"])
	FieldInventory.set_start_order(s, sas_inventory(idx))   # Missionsstart 0x59EB60: Reihenfolge des Ausrüstungsbildschirms
	s.set_meta("sas", idx)
	s.set_meta("lockpick", float(stats.get("lockpick", 50)))
	# Feinduniform im Inventar (z. B. ALPS2 „Uniform GE03“): von Beginn an getarnt (Original:
	# MISSION_SetUniformDisguise schaltet die Tarnung bei Enttarnung ab)
	var uni := int(sas_inventory(idx).get("uniform", -1))
	var un := SAS.item_name(uni).to_lower() if uni >= 0 else ""
	if un.begins_with("uniform ge") or un.begins_with("npc_ge") or un.begins_with("uniform it"):
		s.set_meta("start_disguise", true)
		s.put_on_uniform(Color(0.36, 0.38, 0.33), "cap")
	for w in s.weapons:
		if w == null:
			continue
		if w.data.slot == WeaponData.Slot.GRENADE:
			var n := int(lo["grenades"])
			w.in_mag = 1 if n > 0 else 0
			w.reserve = maxi(n - 1, 0)
		elif w.data.slot == WeaponData.Slot.LAUNCHER:
			var shots := maxi(int(lo.get("launcher_shots", 1)), 1)
			w.in_mag = 1
			w.reserve = shots - 1
		elif w.data.slot == WeaponData.Slot.MELEE:
			w.in_mag = 1
		else:
			var mags := int(lo["mags"].get(String(w.data.id), 0))
			w.in_mag = w.data.magazine_size
			w.reserve = w.data.magazine_size * maxi(mags, 0)
	s.explosives = int(lo.get("explosives", 0))
	s.mines = int(lo.get("mines", 0))


## Nach dem Einsatz: Verbrauch ins Inventar zurückschreiben (Magazine, Granaten, Verbände), Training,
## Erfahrung, Beförderungen, Orden, Gefallene – auf dem vorbereiteten Stand (Übernahme erst mit
## SPEICHERN UND FORTSETZEN, commit_debrief). Ergebnis für die Nachbesprechung inkl. Soldatenpanels.
func finish_sas(members: Array, success: bool) -> Dictionary:
	var done := 0
	for o in last_result.get("objectives", []):
		if int(o[1]) == Objective.State.DONE:
			done += 1
	return _on_pending(func(): return _finish_sas(members, success, done))


func _finish_sas(members: Array, success: bool, objectives_done: int) -> Dictionary:
	var st := sas_states()
	var gains := {}
	var xp := {}
	var fallen: Array = []
	var team := sas_team()
	var before := {}
	var order: Array = []
	for s in members:
		var sol := s as Soldier
		if sol == null or not is_sas_pid(sol.persistent_id):
			continue
		var idx := sas_index(sol.persistent_id)
		if not st.has(str(idx)):
			continue
		order.append(idx)
		before[idx] = {"stats": (st[str(idx)]["stats"] as Dictionary).duplicate(), "rank": int(st[str(idx)]["rank"]),
			"medals": (st[str(idx)].get("medals", []) as Array).duplicate()}
		xp[idx] = SAS.experience_gain(sol.training, sol.alive, success, objectives_done)
		if not sol.alive:
			st[str(idx)]["dead"] = true
			fallen.append(idx)
			continue
		gains[idx] = SAS.training_gain(sol.training)
		_write_back_inventory(sol, idx)
	var promoted := SAS.apply_mission(st, team.filter(func(i): return not fallen.has(i)), gains, xp)
	# Orden (0x68C900, nur Kampagne): je Teammitglied höchstens einer je Einsatz
	var camp := int(SAS.CAMPAIGN_INDEX.get(String(SAS.mission_info(orig_folder(current_mission_id)).get("campaign", "")).to_lower(), -1))
	var new_medals := {}
	if not single_mission and camp >= 0:
		for idx in order:
			var sd: Dictionary = st[str(idx)]
			if bool(sd["dead"]):
				sd["missions"] = int(sd.get("missions", 0)) + 1
				sd["experience"] = int(sd["experience"]) + int(xp.get(idx, 0))
			var m := SAS.award_medal(sd, int(xp.get(idx, 0)), camp)
			if m >= 0:
				var med: Array = sd.get("medals", [])
				if not med.has(m):
					med.append(m)
				sd["medals"] = med
				new_medals[idx] = m
	set_sas_team(team.filter(func(i): return not fallen.has(i)))
	var improved := {}
	var panels: Array = []
	for idx in order:
		var sd: Dictionary = st[str(idx)]
		var diff := {}
		for k in before[idx]["stats"]:
			var d := float(sd["stats"][k]) - float(before[idx]["stats"][k])
			if d > 0.0005:
				diff[k] = d
		if not bool(sd["dead"]):
			improved[SAS.short_name(idx, int(sd["rank"]))] = diff
		panels.append({"idx": idx, "name": SAS.display_name(idx), "rank": int(sd["rank"]), "rank_before": int(before[idx]["rank"]),
			"dead": bool(sd["dead"]), "stats": (before[idx]["stats"] as Dictionary).duplicate(), "gains": diff,
			"medals": (sd.get("medals", []) as Array).duplicate(), "new_medal": int(new_medals.get(idx, -1)),
			"xp": int(xp.get(idx, 0))})
	campaign["sas_prepared"] = ""
	return {"promoted": promoted.map(func(i): return [SAS.display_name(i), SAS.rank_name(int(st[str(i)]["rank"]))]),
		"improved": improved, "fallen": fallen.map(func(i): return SAS.display_name(i)), "members": panels}


## Missionsende wie Original 0x698F80 → 0x5A9040 → 0x5A8B50 (docs/re_notes_roster_inventory.md §4b): der Team-
## Datensatz wird geleert (0x6A27C0) und vollständig aus dem aktuellen Inventar des Menschen neu geschrieben – Kopf,
## Uniform, Rücken, Schulter, Hände, Taschen- und Rucksackgruppen in Gruppenreihenfolge. Damit bleibt alles, was der
## Soldat am Ende trägt (auch im Einsatz Aufgehobenes); Weggeworfenes/Verbrauchtes fehlt. Einzige Ausnahme: eine
## abgefeuerte Panzerfaust 60 (Gegenstand 38, Ladung 0) in Händen/Schulter wird nicht übernommen. Gleiche Sorten
## werden danach zusammengefasst (0x6A2A90).
func _write_back_inventory(s: Soldier, idx: int) -> void:
	var inv := FieldInventory.view(s)      # aktuelles Inventar, Reihenfolge fortgeschrieben (inv_order)
	var hand_w: Weapon = s.current_weapon() if s.tool == "" else null
	var sh_w: Weapon = OrigHud.shoulder_weapon(s)
	for pair in [["hands", hand_w], ["shoulder", sh_w]]:
		var w: Weapon = pair[1]
		if int(inv[pair[0]]) == PANZERFAUST_60 and w != null and w.in_mag <= 0:
			inv[pair[0]] = -1
	var merged: Array = []
	for e in inv["items"]:
		if int(e[1]) > 0:
			SAS.add_item({"items": merged}, int(e[0]), int(e[1]))
	inv["items"] = merged
	sas_inventory(idx)                     # legt campaign["inv"] an, falls nötig
	campaign["inv"][str(idx)] = inv


const PANZERFAUST_60 := 38      ## items.sav „Panzer faust 60“ (Sonderfall in 0x5A8B50)


## Einsatzfähiger Trupp: überlebender Stammkader, aufgefüllt aus der Reserve.
## Originalkampagne: das SAS-Team (Gefallene fehlen; aufgefüllt nur, wo das Original es vorsieht).
func alive_roster() -> Array:
	if uses_sas(current_mission_id):
		prepare_sas(current_mission_id)
		return _alive_team().map(func(i): return _sas_entry(i))
	var r := ROSTER.filter(func(x): return not is_fallen(x["pid"]))
	for x in RESERVE:
		if r.size() >= SQUAD_SIZE:
			break
		if not is_fallen(x["pid"]):
			r.append(x)
	return r


## Gesamter Kader gefallen? (Menü: Kampagne beendet) – ohne Nebenwirkung (alive_roster bereitet ein Team vor)
func roster_exhausted() -> bool:
	if SAS.available() and campaign.has("sas"):
		for k in sas_states():
			if not bool(sas_states()[k]["dead"]):
				return false
		return true
	for x in ROSTER + RESERVE:
		if not is_fallen(x["pid"]):
			return false
	return true


func roster_entry(pid: String) -> Dictionary:
	if is_sas_pid(pid):
		return _sas_entry(sas_index(pid))
	for x in ROSTER + RESERVE:
		if x["pid"] == pid:
			return x
	return {}


## Von Mission.finish() aufgerufen: Fortschritt und Verluste fortschreiben (im vorbereiteten Stand;
## übernommen mit SPEICHERN UND FORTSETZEN).
func record_mission_result(id: String, success: bool, fallen_pids: Array) -> void:
	_on_pending(func(): _record_mission_result(id, success, fallen_pids))


func _record_mission_result(id: String, success: bool, fallen_pids: Array) -> void:
	for pid in fallen_pids:
		if not campaign["fallen"].has(pid):
			campaign["fallen"].append(pid)
	if success:
		if not campaign["completed"].has(id):
			campaign["completed"].append(id)
		var i := CAMPAIGN_ORDER.find(id)
		if i >= 0 and i + 1 < CAMPAIGN_ORDER.size() and not campaign["unlocked"].has(CAMPAIGN_ORDER[i + 1]):
			campaign["unlocked"].append(CAMPAIGN_ORDER[i + 1])
	save_campaign()

var current_mission_id := ""
var pending_load: Dictionary = {}   ## wird nach dem Laden der Mission angewandt
var last_result := {}               ## für das Nachbesprechungsmenü

var cli := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_load_local_content()
	_register_orig_missions()
	_load_current_profile()
	if cli.has("screenshot"):
		_screenshot_after(int(cli.get("frames", "120")), cli["screenshot"])
	if cli.has("mission"):
		start_mission.call_deferred(cli["mission"])
	if cli.has("autoplay"):
		# Testskript als Kind der Wurzel: überlebt Szenenwechsel (Laden)
		var script: GDScript = load("res://tests/%s.gd" % cli["autoplay"])
		if script == null or not script.can_instantiate():
			push_error("Autoplay-Skript nicht ladbar: %s" % cli["autoplay"])
			get_tree().quit(2)
			return
		var t: Node = script.new()
		t.name = "Autoplay"
		get_tree().root.add_child.call_deferred(t)


## Original-Setup „Wenn inakt. aussetz.“: Mission pausieren, wenn das Fenster den Fokus verliert
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.pause_unfocused and not cli.has("autoplay"):
		var m := current_mission()
		if m and not get_tree().paused:
			var pm := m.get_node_or_null("PauseMenu")
			if pm and pm.has_method("open"):
				pm.open()


func loadout_for(pid: String) -> Array:
	if is_sas_pid(pid):
		var lo: Array = SAS.to_loadout(sas_inventory(sas_index(pid)))["loadout"]
		return lo if lo[0] != "" or lo[1] != "" else ["", "colt", ""]
	if loadouts.has(pid):
		return loadouts[pid]
	var e := roster_entry(pid)
	return e["loadout"] if not e.is_empty() else ["sten", "colt", ""]


func start_mission(id: String) -> void:
	if not MISSIONS.has(id):
		push_error("Unbekannte Mission: %s" % id)
		return
	current_mission_id = id
	discard_debrief()
	# Speicherzähler je Einsatz (Original: Missionsobjekt +0x10); beim Laden aus dem Spielstand
	saves_used = int(pending_load.get("_saves_used", 0)) if not pending_load.is_empty() else 0
	_diary_pending = (pending_load.get("_diary", []) as Array).duplicate() if not pending_load.is_empty() else []
	prepare_sas(id)
	get_tree().paused = false
	if MissionLoader.enabled():
		MissionLoader.load_mission(id)     # Ladebildschirm (loader.4ds) + Hintergrundladen/Zwischenspeicher
	else:
		get_tree().change_scene_to_file(MISSION_SCENE)


func return_to_menu() -> void:
	MissionLoader.cancel()
	if Net.is_online:
		Net.leave(false)      # Mehrspieler-Verbindung beenden
	discard_debrief()
	end_single_mission()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)


# --- Filme (Gamemovie\*.bik → orig_cache/movies/<name>.ogv, tools/convert_movies.ps1) -----------------------
## Menü FILME: Filmliste des Profils (profile.sav 0x1EC8, 0x6A6B10) mit Texten 160–169; „Intro“ ab Werk gesehen.
const FILMS := [[160, "Intro"], [161, "IntroArctic"], [162, "IntroAfrica"], [163, "IntroNorway"], [164, "IntroBurma"],
	[165, "IntroAlps"], [166, "IntroNormandy"], [167, "IntroCzech"], [168, "Outro1"], [169, "Outro2"]]


## Pfad des konvertierten Films („" = nicht vorhanden; Bink selbst spielt Godot nicht ab)
static func movie_path(name: String) -> String:
	var base := OrigLevel.cache_root() + "/movies/" + name.get_basename()
	for ext in [".ogv", ".OGV"]:
		if FileAccess.file_exists(base + ext):
			return base + ext
	var lower := OrigLevel.cache_root() + "/movies/" + name.get_basename().to_lower() + ".ogv"
	return lower if FileAccess.file_exists(lower) else ""


func film_seen(name: String) -> bool:
	return name == "Intro" or (profile.get("films_seen", []) as Array).has(name)


func mark_film_seen(name: String) -> void:
	var seen: Array = profile.get("films_seen", [])
	if not seen.has(name):
		seen.append(name)
		profile["films_seen"] = seen
		save_profile()


## Film im Einsatz (Skriptbefehl PlayAvi, z. B. Czech6 „Outro1.bik“): Spiel angehalten, danach weiter
func play_movie(name: String) -> void:
	if movie_path(name) == "" or cli.has("autoplay"):
		return
	var was := get_tree().paused
	get_tree().paused = true
	load("res://src/ui/movie_player.gd").play_list(get_tree().root, [name.get_basename()], func(): get_tree().paused = was)


## Videoknoten vor einer Mission (Gamedata00.gdt): Kampagnen-Intro (vor der Teamauswahl am Kampagnenbeginn) und
## Briefing-Video der Mission. Rückgabe: Dateinamen ohne Endung in Abspielreihenfolge.
func mission_videos(id: String) -> Array:
	var out: Array = []
	var info := SAS.mission_info(orig_folder(id))
	if info.is_empty():
		return out
	var r = LsRuntime._read_json(OrigLevel.cache_root() + "/inventory_rules.json")
	if typeof(r) == TYPE_DICTIONARY:
		for c in r.get("campaigns", []):
			if String(c.get("name", "")).to_lower() != String(info.get("campaign", "")).to_lower():
				continue
			var flow: Array = c.get("flow", [])
			var first := ""
			for n in flow:
				if n.has("mission"):
					first = String(n["mission"])
					break
			if first.to_lower() == String(info.get("folder", "")).to_lower():
				for n in flow:
					if n.has("video"):
						out.append(String(n["video"]).get_basename())
					elif n.has("mission"):
						break
	for n in info.get("flow", []):
		if n is Dictionary and n.has("video"):
			out.append(String(n["video"]).get_basename())
	return out


## Wunsch an das Hauptmenü beim nächsten Aufbau (z. B. nach der Nachbesprechung: Missionsliste mit der nächsten
## Mission); {"menu": "campaign", "select": id}
var menu_request := {}


## Nach SPEICHERN UND FORTSETZEN: zur Missionsliste des Modus mit dem nächsten Teil
func continue_campaign() -> void:
	var idx := CAMPAIGN_ORDER.find(current_mission_id)
	var nxt: String = CAMPAIGN_ORDER[idx + 1] if idx >= 0 and idx + 1 < CAMPAIGN_ORDER.size() else ""
	var sm := single_mission
	menu_request = {"menu": "single_mission" if sm else "campaign", "select": "" if sm else nxt,
		"mode": game_mode, "single": sm, "videos": _videos_after(current_mission_id)}
	return_to_menu()


## Videoknoten nach einer Mission im Kampagnenablauf (Czech6: Outro2, credits)
func _videos_after(id: String) -> Array:
	var out: Array = []
	var info := SAS.mission_info(orig_folder(id))
	var r = LsRuntime._read_json(OrigLevel.cache_root() + "/inventory_rules.json")
	if info.is_empty() or typeof(r) != TYPE_DICTIONARY:
		return out
	for c in r.get("campaigns", []):
		var after := false
		for n in c.get("flow", []):
			if n.has("mission"):
				after = String(n["mission"]).to_lower() == String(info.get("folder", "")).to_lower()
			elif after and n.has("video"):
				out.append(String(n["video"]).get_basename())
	return out


func current_mission() -> Node:
	return get_tree().get_first_node_in_group("mission")


# --- Spielstände ---------------------------------------------------------

func save_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir(), slot]


## Speicherbegrenzung je Einsatz (hd2.exe 0x69A619/0x69CEFA): Wert aus 0x6B6700 = Schwierigkeitsgrad des Profils
## (+0x34, re_notes_profiles). 3 „Schwer“: höchstens 3 Speicherungen je Einsatz, danach Hinweis T9526 mit der
## Zahl freier Plätze (3 − Zähler); 4 „Sehr schwer“: Speichern nicht möglich (T6599). Leicht/Normal unbegrenzt.
const SAVES_PER_MISSION_HARD := 3
var saves_used := 0              ## Speicherungen im laufenden Einsatz (Missionsobjekt +0x10; im Spielstand)


## Freie Speicherplätze im Einsatz (-1 = unbegrenzt)
func saves_left() -> int:
	match difficulty():
		3:
			return maxi(SAVES_PER_MISSION_HARD - saves_used, 0)
		4:
			return 0
	return -1


func can_save() -> String:
	if current_mission() == null or Net.is_online:
		return SAS.text(6599, "Speichern eines Spielstands ist in diesem Spielmodus nicht möglich")
	if difficulty() >= 4:
		return SAS.text(6599, "Speichern eines Spielstands ist in diesem Spielmodus nicht möglich")
	if saves_left() == 0:
		return SAS.text(9526, "Es sind %d Speicherplätze frei").replace("%d", "0")
	return ""


## Neuer Spielstandname im Modus-Slot (Original XXX_%02d%02d.sav, hier mit laufender Nummer je Mission)
func new_save_slot() -> String:
	var ord := CAMPAIGN_ORDER.find(current_mission_id) + 1
	var base: String = "%s_%02d" % [mode_prefix(), ord] if ord > 0 else "%s_%s" % [mode_prefix(), current_mission_id]
	var n := 1
	while has_save("%s_%02d" % [base, n]):
		n += 1
	return "%s_%02d" % [base, n]


func save_game(slot: String = "quick") -> bool:
	var mission := current_mission()
	if mission == null:
		return false
	var why := can_save()
	if why != "":
		Events.say(why, 3.0)
		return false
	var state: Dictionary = mission.serialize()
	saves_used += 1
	state["_saves_used"] = saves_used
	state["_diary"] = _diary_pending.duplicate()
	var data := {
		"version": 2,
		"mission": current_mission_id,
		"title": String(MISSIONS.get(current_mission_id, {}).get("title", current_mission_id)),
		"mode": game_mode, "single": single_mission, "mode_title": mode_title(),
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"state": state,
	}
	DirAccess.make_dir_recursive_absolute(save_dir())
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		saves_used -= 1
		push_error("Speichern fehlgeschlagen: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	if has_profile():
		profile["last_save"] = slot
		profile["last_save_text"] = "%s$%s$%s" % [mode_title(), data["title"], data["timestamp"]]
		save_profile()
	Events.say(SAS.text(2041, "Speichern abgeschlossen."), 2.0)
	var left := saves_left()
	if left >= 0:
		Events.say(SAS.text(9526, "Es sind %d Speicherplätze frei").replace("%d", str(left)), 3.0)
	return true


func has_save(slot: String = "quick") -> bool:
	return FileAccess.file_exists(save_path(slot))


func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))


## Spielstandliste des Profils (neueste zuerst): [{slot, title, mode_title, timestamp, mission}]
func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(save_dir())
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var slot := f.get_basename()
		var data = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
		if typeof(data) != TYPE_DICTIONARY or not MISSIONS.has(String(data.get("mission", ""))):
			continue
		var mt := FileAccess.get_modified_time(ProjectSettings.globalize_path(save_path(slot)))
		out.append({"slot": slot, "mission": String(data["mission"]),
			"title": String(data.get("title", MISSIONS[data["mission"]].get("title", ""))),
			"mode_title": String(data.get("mode_title", "")), "timestamp": String(data.get("timestamp", "")), "mtime": mt})
	out.sort_custom(func(a, b): return int(a["mtime"]) > int(b["mtime"]))
	return out


## Letzter Spielstand des Profils (Original LASTSAVE) – für WEITER SPIELEN
func last_save() -> String:
	var s := String(profile.get("last_save", ""))
	if s != "" and has_save(s):
		return s
	var all := list_saves()
	return String(all[0]["slot"]) if not all.is_empty() else ""


func load_game(slot: String = "quick") -> bool:
	if not has_save(slot):
		Events.say("Kein Spielstand vorhanden.")
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if typeof(data) != TYPE_DICTIONARY or not MISSIONS.has(data.get("mission", "")):
		push_error("Spielstand beschädigt: %s" % slot)
		return false
	# Spielmodus des Spielstands herstellen (Modus-Slot)
	var m := int(data.get("mode", game_mode))
	var single := bool(data.get("single", false))
	if m != game_mode or single != single_mission:
		set_game_mode(m, single)
	pending_load = data["state"]
	start_mission(data["mission"])
	Events.say(SAS.text(2042, "Laden abgeschlossen."), 2.0)
	return true


## Von der Mission nach dem Aufbau aufgerufen.
func consume_pending_load() -> Dictionary:
	var d := pending_load
	pending_load = {}
	return d


# --- Testunterstützung ----------------------------------------------------

func _screenshot_after(frames: int, path: String) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SCREENSHOT %s -> %s" % [path, error_string(err)])
	get_tree().quit()
