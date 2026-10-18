class_name MissionLoader
extends Node
## Missionen laden wie im Original mit Ladebildschirm und Fortschrittsbalken (MISSIONS\<m>\loader.4ds, LoadingScreen),
## dazu Hintergrundladen und Zwischenspeicher:
##  1. alte Szene sofort entladen (Game.current_mission() = null, Net arbeitet nicht mehr auf der alten Karte)
##  2. glTF-Dateien der Karte (scene.glb, models/*.glb) in WorkerThreadPool-Aufgaben parsen und als Vorlagen ablegen
##     (Texturtausch HD/4K inklusive); der Balken folgt den geladenen Bytes, das Fenster bleibt bedienbar
##  3. Missionsszene wechseln; OrigLevel._load_glb nimmt Kopien der Vorlagen (take) statt neu zu parsen
##  4. Bildschirm ausblenden, sobald die Mission bereit ist
## Vorlagen bleiben für die zuletzt geladene Karte (+ Figuren, kartenübergreifend) erhalten: neue Runde/erneuter
## Versuch/Kartenwechsel zurück lädt ohne glTF-Parsen. Mesh/Material-Ressourcen werden beim Kopieren geteilt.

## Ein Arbeits-Thread: paralleles glTF-Parsen (4 Threads) führte gelegentlich zu Speicherzugriffsfehlern (16.10.2026,
## test_mp_modes) – ein Hintergrund-Thread hält das Fenster bedienbar und bleibt stabil
const PRELOAD_THREADS := 1
const LOAD_FPS := 20

static var _tmpl := {}               ## glb-Pfad -> Node3D-Vorlage (nicht im Baum)
static var _tmpl_mutex := Mutex.new()
static var _tmpl_dir := ""           ## Kartenordner der Vorlagen (andere werden beim Wechsel verworfen)
static var timing := {}              ## letzte Messung: Phasen in ms (Tests/Messung)

var mission_id := ""
var screen: LoadingScreen
var _layer: CanvasLayer
var _gen := 0
var _files: Array = []               ## [Pfad, Bytes]
var _done_bytes := 0
var _total_bytes := 1
var _done_count := 0
var _count_mutex := Mutex.new()
var _task := -1
var _phase := ""
var _t0 := 0
var _t_parse := 0
var _t_scene := 0


static func instance() -> MissionLoader:
	var tree := Engine.get_main_loop() as SceneTree
	var n := tree.root.get_node_or_null("MissionLoader") as MissionLoader
	if n == null:
		n = MissionLoader.new()
		n.name = "MissionLoader"
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(n)
	return n


## Einstieg aus Game.start_mission
static func load_mission(id: String) -> void:
	instance().begin(id)


## Laufendes Laden verwerfen (Rückkehr ins Hauptmenü)
static func cancel() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var n := tree.root.get_node_or_null("MissionLoader") as MissionLoader
	if n:
		n._gen += 1
		n._phase = ""
		n._hide()
		Engine.max_fps = Settings.max_fps


## Vergleichsmessung „vorher“: --no_load_cache schaltet Hintergrundladen und Zwischenspeicher ab
static func enabled() -> bool:
	return not Game.cli.has("no_load_cache")


## Schlüssel: Pfad + gewählte Texturstufe (HD/4K-Tausch ist in der Vorlage enthalten)
static func _key(path: String) -> String:
	return "%s|%s" % [path, String(Settings.texture_suffixes()[0])]


## Kopie einer Vorlage (null = nicht vorhanden → normal laden)
static func take(path: String) -> Node3D:
	if not enabled():
		return null
	_tmpl_mutex.lock()
	var t: Node3D = _tmpl.get(_key(path))
	_tmpl_mutex.unlock()
	if t == null or not is_instance_valid(t):
		return null
	return t.duplicate() as Node3D


## Frisch geladene Datei als Vorlage merken (OrigLevel._load_glb)
static func remember(path: String, n: Node3D) -> void:
	if n == null or not enabled():
		return
	instance()                 # Knoten unter /root gibt die Vorlagen beim Beenden frei (_exit_tree)
	_tmpl_mutex.lock()
	if not _tmpl.has(_key(path)):
		_tmpl[_key(path)] = n.duplicate() as Node3D
	_tmpl_mutex.unlock()


## Vorlagen sind verwaiste Knoten: beim Programmende freigeben (sonst Leck/Absturz beim Beenden im Export)
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
	clear_cache()


## Vorlagen anderer Karten freigeben (Figuren/Waffen bleiben)
static func _evict_except(mission_dir: String) -> void:
	_tmpl_mutex.lock()
	for p in _tmpl.keys():
		var s := String(p)
		if s.contains("/characters/") or s.contains("/weapons/") or s.begins_with(mission_dir + "/"):
			continue
		var n = _tmpl[p]
		if is_instance_valid(n):
			(n as Node).free()
		_tmpl.erase(p)
	_tmpl_dir = mission_dir
	_tmpl_mutex.unlock()


static func clear_cache() -> void:
	_evict_except("<keiner>")
	_tmpl_mutex.lock()
	for p in _tmpl.keys():
		if is_instance_valid(_tmpl[p]):
			(_tmpl[p] as Node).free()
	_tmpl.clear()
	_tmpl_mutex.unlock()


func begin(id: String) -> void:
	_gen += 1
	var gen := _gen
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)      # laufende Aufgabe sauber beenden
		_task = -1
	mission_id = id
	_t0 = Time.get_ticks_msec()
	timing = {}
	_phase = "unload"
	_show(id)
	# alte Szene sofort entladen: Netz/Skripte sehen keine alte Mission mehr (SceneTree setzt current_scene beim
	# Verlassen des Baums auf null)
	var cs := get_tree().current_scene
	if cs:
		cs.queue_free()           # am Ende dieses Bildes (Aufruf kann aus der alten Szene kommen)
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _gen:
		return
	_collect(id)
	_phase = "parse"
	# Während des Vorladens zeigt der Hauptthread nur den Ladebildschirm: Bildrate begrenzen (Rechenzeit für die
	# Arbeits-Threads; Bildzahl-basierte Warteschleifen der Tests laufen nicht leer)
	Engine.max_fps = LOAD_FPS
	if not _files.is_empty():
		var task := WorkerThreadPool.add_group_task(_parse_one, _files.size(), mini(PRELOAD_THREADS,
			maxi(OS.get_processor_count() - 1, 1)), true, "Karte laden")
		_task = task
		while not WorkerThreadPool.is_group_task_completed(task):
			_progress(0.05 + 0.8 * float(_done_bytes) / float(_total_bytes))
			await get_tree().process_frame
			if gen != _gen:
				break
		if _task == task:             # sonst hat ein neuer Ladevorgang bereits darauf gewartet
			WorkerThreadPool.wait_for_group_task_completion(task)
			_task = -1
	if gen != _gen:
		return
	Engine.max_fps = Settings.max_fps
	_t_parse = Time.get_ticks_msec() - _t0
	_phase = "build"
	_progress(0.85, SAS.text(8904, "Mission wird geladen"))
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _gen:
		return
	get_tree().change_scene_to_file(Game.MISSION_SCENE)
	# warten, bis die Mission aufgebaut ist (Mission._ready läuft synchron im Szenenwechsel)
	var w0 := Time.get_ticks_msec()
	while gen == _gen and Time.get_ticks_msec() - w0 < 600000:
		await get_tree().process_frame
		var m = Game.current_mission()
		if m and m.is_node_ready():
			break
	_t_scene = Time.get_ticks_msec() - _t0
	if gen == _gen:
		PerfTuning.apply(Game.current_mission())
	timing = {"parse_ms": _t_parse, "ready_ms": _t_scene, "files": _files.size(), "bytes": _total_bytes,
		"cached": _files.is_empty()}
	print("LADEN: %s – glTF %d Dateien (%.1f MB) %.2f s, Mission bereit %.2f s" % [id, _files.size(), _total_bytes / 1048576.0,
		_t_parse / 1000.0, _t_scene / 1000.0])
	if gen == _gen:
		_progress(1.0, SAS.text(8905, "Spiel läuft"))
		await get_tree().process_frame
		if gen == _gen:
			_phase = ""
			_hide()


func timing_text() -> String:
	if timing.is_empty():
		return ""
	return "glTF-Vorladen %.2f s (%d Dateien, %.1f MB%s), bis Mission bereit %.2f s" % [float(timing["parse_ms"]) / 1000.0,
		int(timing["files"]), float(timing["bytes"]) / 1048576.0, ", alles aus dem Zwischenspeicher" if timing["cached"] else "",
		float(timing["ready_ms"]) / 1000.0]


## glTF-Dateien der Karte, die noch nicht als Vorlage vorliegen
func _collect(id: String) -> void:
	_files.clear()
	_done_bytes = 0
	_done_count = 0
	var folder := Game.orig_folder(id)        # auch ARCTIC1–3 (eigene Zuordnung ORIG_FOLDER_1)
	if folder == "" or not OrigLevel.available(folder):
		_total_bytes = 1
		return
	var dir := OrigLevel.cache_path(folder)
	_evict_except(dir)
	var paths: Array = [dir + "/scene.glb"]
	for f in DirAccess.get_files_at(dir + "/models"):
		if f.get_extension().to_lower() == "glb":
			paths.append(dir + "/models/" + f)
	var total := 0
	for p in paths:
		if _tmpl.has(_key(p)):
			continue
		var fa := FileAccess.open(p, FileAccess.READ)
		var sz: int = fa.get_length() if fa else 0
		_files.append([p, sz, _key(p)])        # Schlüssel im Hauptthread (Settings nicht aus Threads lesen)
		total += sz
	_total_bytes = maxi(total, 1)


## Arbeitsaufgabe (WorkerThreadPool): eine glb-Datei parsen und als Vorlage ablegen
func _parse_one(i: int) -> void:
	var p := String(_files[i][0])
	var n := OrigLevel.parse_glb(p)
	if n:
		var k := String(_files[i][2])
		_tmpl_mutex.lock()
		if _tmpl.has(k):
			n.free()
		else:
			_tmpl[k] = n
		_tmpl_mutex.unlock()
	_count_mutex.lock()
	_done_bytes += int(_files[i][1])
	_done_count += 1
	_count_mutex.unlock()


# --- Ladebildschirm ------------------------------------------------------------------------------------------

func _show(id: String) -> void:
	_hide()
	_layer = CanvasLayer.new()
	_layer.name = "LoadingLayer"
	_layer.layer = 120
	add_child(_layer)
	screen = LoadingScreen.new()
	screen.name = "LoadingScreen"
	_layer.add_child(screen)
	screen.open(id)
	_progress(0.02)


func _hide() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	screen = null


func _progress(frac: float, text := "") -> void:
	if is_instance_valid(screen):
		screen.set_progress(frac, text)


## Ladebildschirm sichtbar (Tests)
func is_loading() -> bool:
	return _phase != ""
