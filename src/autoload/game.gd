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
const SAVE_DIR := "user://saves"

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
const CAMPAIGN_PATH := "user://campaign.json"
var campaign := {}


func new_campaign() -> void:
	campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
	save_campaign()


func load_campaign() -> void:
	# Automatisierte Tests arbeiten mit einer frischen Kampagne im Speicher
	if cli.has("autoplay") or not FileAccess.file_exists(CAMPAIGN_PATH):
		campaign = {"unlocked": [CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_PATH))
	if typeof(d) == TYPE_DICTIONARY and d.has("unlocked"):
		campaign = d
	else:
		new_campaign()


func save_campaign() -> void:
	if cli.has("autoplay"):
		return
	var f := FileAccess.open(CAMPAIGN_PATH, FileAccess.WRITE)
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
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	load_campaign()
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
	return "%s/%s.json" % [SAVE_DIR, slot]


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
