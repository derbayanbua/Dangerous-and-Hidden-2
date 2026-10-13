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
const MISSIONS := {
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
const CAMPAIGN_ORDER := ["a1_blizzard", "a2_erkundung", "a3_rendezvous"]
## Eigene Prototyp-Einsätze (kein Original-Leveldesign): jederzeit wählbar, nicht Teil der Kampagne.
const PRACTICE_MISSIONS := ["m01_funkfeuer", "m02_nordlicht", "m03_sandsturm"]
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
		_remove_dir(profiles_dir)
		return
	if cli.has("autoplay"):
		_memory_profile = true
		profile_name = "Test"
		profile = {"name": "Test", "difficulty": int(cli.get("difficulty", "3")), "playtime": 0.0,
			"kills": 0, "enemies_killed": 0, "shots": 0, "missions": 0}
		campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
		return
	var cur := ""
	if FileAccess.file_exists(profiles_dir + "/current.txt"):
		cur = FileAccess.get_file_as_string(profiles_dir + "/current.txt").strip_edges()
	if cur == "" or not select_profile(cur):
		var all := list_profiles()
		if not all.is_empty():
			select_profile(all[0])


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


## Einsatzfähiger Trupp: überlebender Stammkader, aufgefüllt aus der Reserve.
func alive_roster() -> Array:
	var r := ROSTER.filter(func(x): return not is_fallen(x["pid"]))
	for x in RESERVE:
		if r.size() >= SQUAD_SIZE:
			break
		if not is_fallen(x["pid"]):
			r.append(x)
	return r


func roster_entry(pid: String) -> Dictionary:
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


func loadout_for(pid: String) -> Array:
	if loadouts.has(pid):
		return loadouts[pid]
	var e := roster_entry(pid)
	return e["loadout"] if not e.is_empty() else ["sten", "colt", ""]


func start_mission(id: String) -> void:
	if not MISSIONS.has(id):
		push_error("Unbekannte Mission: %s" % id)
		return
	current_mission_id = id
	get_tree().paused = false
	get_tree().change_scene_to_file(MISSION_SCENE)


func return_to_menu() -> void:
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
