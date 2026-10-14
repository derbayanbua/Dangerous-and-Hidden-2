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
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/mp_maps.json")
	if typeof(d) == TYPE_DICTIONARY:
		for e in d.get("maps", []):
			var folder := String(e.get("folder", ""))
			if folder == "" or not DirAccess.dir_exists_absolute(OrigLevel.cache_root() + "/" + folder.to_lower()):
				continue
			var id := "mp_" + folder.to_lower()
			MISSIONS[id] = {"title": String(e.get("title", folder)), "script": "res://src/missions/mp_arena.gd",
				"orig": folder, "k": 0, "briefing": "", "modes": e.get("modes", [])}
			MP_MAPS.append(id)
	for e in [["a1_blizzard", "ARCTIC1", 0], ["a2_erkundung", "ARCTIC2", 1], ["a3_rendezvous", "ARCTIC3", 2]] + ORIG_CAMPAIGN:
		var mid: String = "mp_arena_" + String(e[0])
		MISSIONS[mid] = {"title": "Arena: " + String(MISSIONS.get(e[0], {}).get("title", e[1])),
			"script": "res://src/missions/mp_arena.gd", "orig": e[1], "k": e[2], "briefing": ""}
		MP_MAPS.append(mid)


## Eigene Prototyp-Einsätze (kein Original-Leveldesign): jederzeit wählbar, nicht Teil der Kampagne.
var PRACTICE_MISSIONS: Array = ["m01_funkfeuer", "m02_nordlicht", "m03_sandsturm"]
var campaign := {}


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


func campaign_path() -> String:
	return profile_dir() + "/campaign.json"


func load_campaign() -> void:
	# Automatisierte Tests arbeiten mit einer frischen Kampagne im Speicher
	if _memory_profile or not has_profile() or not FileAccess.file_exists(campaign_path()):
		campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(campaign_path()))
	if typeof(d) == TYPE_DICTIONARY and d.has("unlocked"):
		campaign = d
	else:
		new_campaign()


func save_campaign() -> void:
	if _memory_profile or not has_profile():
		return
	var f := FileAccess.open(campaign_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(campaign, "\t"))


## Original-Skriptwerte (SaveGameValue/_LoadGameValue) über Missionsteile hinweg.
func orig_game_values() -> Dictionary:
	var out := {}
	var d: Dictionary = campaign.get("game_values", {})
	for k in d:
		out[int(k)] = d[k]
	return out


func store_orig_game_values(values: Dictionary) -> void:
	var d := {}
	for k in values:
		d[str(k)] = values[k]
	campaign["game_values"] = d
	save_campaign()


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
	if mode == "keep" and sas_team().size() < SQUAD_SIZE and _alive_team().size() == 0:
		return "select"
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
	if team.is_empty() or mode in ["select", "refill"]:
		team = SAS.auto_select(st, SQUAD_SIZE, team if mode != "select" or not team.is_empty() else [])
	set_sas_team(team)
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
## (Gesundheit wie Gegner mit Mission.HP-Skala 0,5; Magazine/Granaten/Verbände aus dem Inventar).
func apply_sas(s: Soldier, pid: String) -> void:
	var idx := sas_index(pid)
	var st: Dictionary = sas_states().get(str(idx), {})
	if st.is_empty():
		return
	var stats: Dictionary = st["stats"]
	s.max_health = clampf(float(stats.get("health", 500)) * 0.5, 50.0, 500.0)
	s.health = s.max_health
	s.skill_shooting = float(stats.get("shooting", 50))
	s.skill_stealth = float(stats.get("stealth", 50))
	s.skill_endurance = float(stats.get("endurance", 50))
	s.skill_first_aid = float(stats.get("first_aid", 50))
	var lo := SAS.to_loadout(sas_inventory(idx))
	s.medkits = int(lo["medkits"])
	s.has_binoculars = bool(lo["binoculars"])
	s.set_meta("orig_items", lo["items"])
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
## Erfahrung, Beförderungen, Gefallene. Ergebnis für die Nachbesprechung.
func finish_sas(members: Array, success: bool) -> Dictionary:
	var st := sas_states()
	var gains := {}
	var xp := {}
	var fallen: Array = []
	var team := sas_team()
	for s in members:
		var sol := s as Soldier
		if sol == null or not is_sas_pid(sol.persistent_id):
			continue
		var idx := sas_index(sol.persistent_id)
		if not st.has(str(idx)):
			continue
		if not sol.alive:
			st[str(idx)]["dead"] = true
			fallen.append(idx)
			continue
		gains[idx] = SAS.training_gain(sol.training)
		xp[idx] = SAS.experience_gain(sol.training, true, success)
		_write_back_inventory(sol, idx)
	var before := {}
	for idx in gains:
		before[idx] = (st[str(idx)]["stats"] as Dictionary).duplicate()
	var promoted := SAS.apply_mission(st, team.filter(func(i): return not fallen.has(i)), gains, xp)
	set_sas_team(team.filter(func(i): return not fallen.has(i)))
	var improved := {}
	for idx in before:
		var diff := {}
		for k in before[idx]:
			var d := float(st[str(idx)]["stats"][k]) - float(before[idx][k])
			if d > 0.0005:
				diff[k] = d
		improved[SAS.short_name(idx, int(st[str(idx)]["rank"]))] = diff
	campaign["sas_prepared"] = ""
	save_campaign()
	return {"promoted": promoted.map(func(i): return [SAS.display_name(i), SAS.rank_name(int(st[str(i)]["rank"]))]),
		"improved": improved, "fallen": fallen.map(func(i): return SAS.display_name(i))}


func _write_back_inventory(s: Soldier, idx: int) -> void:
	var inv := sas_inventory(idx)
	var lo := SAS.to_loadout(inv)
	# Originalnummer der Waffe je WeaponData (Hände, Schulter, Inventar)
	var orig_of := {}
	var wids: Array = [int(inv.get("hands", -1)), int(inv.get("shoulder", -1))]
	for e in inv["items"]:
		wids.append(int(e[0]))
	for wid in wids:
		if wid >= 0 and SAS.item_kind(wid) == "weapon":
			var wd := WeaponDB.from_orig(wid)
			if wd and not orig_of.has(wd.id):
				orig_of[wd.id] = wid
	for w in s.weapons:
		if w == null or not orig_of.has(w.data.id):
			continue
		var wid: int = orig_of[w.data.id]
		if w.data.slot == WeaponData.Slot.GRENADE:
			for e in inv["items"]:
				if int(e[0]) == wid:
					e[1] = w.in_mag + w.reserve
		else:
			var ammo := SAS.ammo_of(wid)
			for e in inv["items"]:
				if int(e[0]) == ammo:
					e[1] = int(ceil(float(w.reserve) / maxf(w.data.magazine_size, 1)))
	# verbrauchter Sprengstoff / Minen
	for pair in [["explosives", [68, 67]], ["mines", [70, 71]]]:
		var used := int(lo.get(pair[0], 0)) - int(s.get(pair[0]))
		for id in pair[1]:
			if used > 0:
				used -= SAS.remove_item(inv, id, used)
	var used_med := int(lo["medkits"]) - s.medkits
	for m in SAS.MEDKITS:
		if used_med > 0:
			used_med -= SAS.remove_item(inv, m, used_med)
	inv["items"] = inv["items"].filter(func(e): return int(e[1]) > 0)


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


func roster_entry(pid: String) -> Dictionary:
	if is_sas_pid(pid):
		return _sas_entry(sas_index(pid))
	for x in ROSTER + RESERVE:
		if x["pid"] == pid:
			return x
	return {}


## Von Mission.finish() aufgerufen: Fortschritt und Verluste fortschreiben.
func record_mission_result(id: String, success: bool, fallen_pids: Array) -> void:
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
	prepare_sas(id)
	get_tree().paused = false
	get_tree().change_scene_to_file(MISSION_SCENE)


func return_to_menu() -> void:
	if Net.is_online:
		Net.leave(false)      # Mehrspieler-Verbindung beenden
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)


func current_mission() -> Node:
	return get_tree().get_first_node_in_group("mission")


# --- Spielstände ---------------------------------------------------------

func save_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir(), slot]


func save_game(slot: String = "quick") -> bool:
	var mission := current_mission()
	if mission == null:
		return false
	var data := {
		"version": 1,
		"mission": current_mission_id,
		"timestamp": Time.get_datetime_string_from_system(),
		"state": mission.serialize(),
	}
	DirAccess.make_dir_recursive_absolute(save_dir())
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Speichern fehlgeschlagen: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	Events.say("Spiel gespeichert.")
	return true


func has_save(slot: String = "quick") -> bool:
	return FileAccess.file_exists(save_path(slot))


func load_game(slot: String = "quick") -> bool:
	if not has_save(slot):
		Events.say("Kein Spielstand vorhanden.")
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if typeof(data) != TYPE_DICTIONARY or not MISSIONS.has(data.get("mission", "")):
		push_error("Spielstand beschädigt: %s" % slot)
		return false
	pending_load = data["state"]
	start_mission(data["mission"])
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
