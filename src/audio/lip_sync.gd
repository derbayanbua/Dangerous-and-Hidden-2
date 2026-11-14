class_name LipSync
extends Node
## B-052: Gesichtsanimation zu Sprachaufnahmen (Status docs/status/b0112_lipsync.md, Belege docs/re_notes_lipsync.md).
##
## Daten: orig_cache/dabing/<id>.dat (= TABLES\dabing\%08d.dat, fmt_dabing.py), <id> = Nummer der gespielten
## Aufnahme <id>.wav. Aufbau [B] hd2.exe 0x71E860: u32 Bildzahl n, u32 1, n × 8 Byte; je Bild 6 Werte (Byte/255).
## Abspielen [B] hd2.exe 0x71EE00: Bild = Abspielzeit_ms / 20 (50 fps); Ende, wenn der Klang aus ist oder das
## vorletzte Bild erreicht ist; danach 200 ms Schließen (Mundwerte b0/b1 × Restzeit/200). Einblenden: Faktor f
## steigt um 0,008 je ms, solange f < 1 gilt Wert = f·neu + (1 − f)·vorheriger (letzte Werte des Sprechers).
## Gewichte je (Kanal, Ziel) des Kopf-Morphs, Blendshape „m<Kanal>_<Ziel>“ (Ziel 0 = Grundform):
##   Kanal 0: 1 = b0·b1, 2 = b0·(1−b1), 3 = (1−b0)(1−b2), 4 = (1−b0)·b2
##   Kanal 1: 1 = b3·b4, 2 = (1−b3)·b4, 3 = 1−b4
##   Kanal 2: 1 = b5·b4, 2 = (1−b5)·b4, 3 = 1−b4
## Leistung: Gewichte werden nur gesetzt, wenn die Figur höchstens NEAR_DIST von der aktiven Kamera entfernt ist.

const NODE_NAME := "LipSync"
const FRAME_MS := 20.0
const CLOSE_MS := 200.0
const FADE_PER_MS := 0.008
const NEAR_DIST := 30.0
const WEIGHTS := [  # [Kanal, Ziel]
	[0, 1], [0, 2], [0, 3], [0, 4], [1, 1], [1, 2], [1, 3], [2, 1], [2, 2], [2, 3]]

static var _cache := {}        ## id -> PackedByteArray (leer = fehlt)

var data := PackedByteArray()
var frames := 0
var player: Node               ## AudioStreamPlayer/-3D des Satzes
var meshes: Array = []         ## [[MeshInstance3D, {name: index}]]
var closing := false
var close_left := CLOSE_MS
var fade := 0.0
var prev := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var last_weights := {}         ## Testhilfe: zuletzt berechnete Gewichte je Blendshape-Name
var updates := 0


## Gesichtsdaten-ID aus dem Dateinamen der Aufnahme („90001234.wav“ -> „90001234“); "" = keine.
static func id_of(wav_file: String) -> String:
	var b := wav_file.get_file().get_basename()
	return b if b.is_valid_int() else ""


static func load_data(id: String) -> PackedByteArray:
	if id == "":
		return PackedByteArray()
	if _cache.has(id):
		return _cache[id]
	var d := PackedByteArray()
	var path := OrigLevel.cache_root() + "/dabing/%s.dat" % id
	if FileAccess.file_exists(path):
		d = FileAccess.get_file_as_bytes(path)
		if d.size() < 8 or d.size() < 8 + 8 * d.decode_u32(0):
			d = PackedByteArray()
	if _cache.size() > 256:
		_cache.clear()
	_cache[id] = d
	return d


## Morph-Meshes einer Figur (Blendshapes m*_*), [] = Figur ohne Gesichtsdaten (alter Figuren-Cache).
static func face_meshes(who: Node) -> Array:
	var out := []
	if who == null or not is_instance_valid(who):
		return out
	for n in who.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var am := mi.mesh as ArrayMesh
		if am == null or am.get_blend_shape_count() == 0:
			continue
		var idx := {}
		for w in WEIGHTS:
			var nm := "m%d_%d" % [w[0], w[1]]
			var i := mi.find_blend_shape_by_name(nm)
			if i >= 0:
				idx[nm] = i
		if not idx.is_empty():
			out.append([mi, idx])
	return out


## Gesichtsanimation zum gerade gestarteten Satz an der sprechenden Figur. Rückgabe: Treiber oder null
## (keine Daten / Figur ohne Morph-Ziele -> nichts, kein Fehler).
static func start(who: Node, wav_file: String, p: Node) -> LipSync:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree() or p == null:
		return null
	var d := load_data(id_of(wav_file))
	var ms := face_meshes(who) if not d.is_empty() else []
	if "--lip_debug" in OS.get_cmdline_user_args():
		print("LIPSYNC %s %s daten=%d morph=%d" % [who.name, wav_file.get_file(), d.size(), ms.size()])
	if d.is_empty() or d.decode_u32(0) < 2:
		return null
	if ms.is_empty():
		return null
	var old := who.get_node_or_null(NODE_NAME)
	var keep := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	if old is LipSync:
		keep = (old as LipSync).prev
		old.name = "LipSyncOld"
		old.queue_free()
	elif who.has_meta("_lip_prev"):
		keep = who.get_meta("_lip_prev")
	var ls := LipSync.new()
	ls.name = NODE_NAME
	ls.data = d
	ls.frames = d.decode_u32(0)
	ls.player = p
	ls.meshes = ms
	ls.prev = keep
	who.add_child(ls)
	return ls


func _byte(frame: int, k: int) -> float:
	return data[8 + frame * 8 + k] / 255.0


func _playing() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return bool(player.call("is_playing"))


func _process(delta: float) -> void:
	var dt := delta * 1000.0
	var b := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	if not closing:
		var t := 0.0
		if _playing():
			t = float(player.call("get_playback_position")) * 1000.0
		var fi := int(t / FRAME_MS)
		if not _playing() or fi >= frames - 1:
			closing = true
		else:
			for k in 6:
				b[k] = _byte(fi, k)
			if fade < 1.0:
				fade += dt * FADE_PER_MS
				if fade < 1.0:
					for k in 6:
						b[k] = fade * b[k] + (1.0 - fade) * prev[k]
	if closing:
		close_left = maxf(close_left - dt, 0.0)
		var last := frames - 2
		for k in 6:
			b[k] = _byte(last, k)
		var s := close_left / CLOSE_MS
		b[0] *= s
		b[1] *= s
		prev = b
	_apply(b)
	if closing and close_left <= 0.0:
		var who := get_parent()
		if who:
			who.set_meta("_lip_prev", prev)
		queue_free()


static func weights_of(b: PackedFloat32Array) -> Dictionary:
	return {
		"m0_1": b[0] * b[1], "m0_2": b[0] * (1.0 - b[1]), "m0_3": (1.0 - b[0]) * (1.0 - b[2]), "m0_4": (1.0 - b[0]) * b[2],
		"m1_1": b[3] * b[4], "m1_2": (1.0 - b[3]) * b[4], "m1_3": 1.0 - b[4],
		"m2_1": b[5] * b[4], "m2_2": (1.0 - b[5]) * b[4], "m2_3": 1.0 - b[4]}


func _near() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var who := get_parent() as Node3D
	if cam == null or who == null:
		return true
	return cam.global_position.distance_to(who.global_position) <= NEAR_DIST


func _apply(b: PackedFloat32Array) -> void:
	last_weights = weights_of(b)
	if not closing:
		prev = b
	if not _near() and not (closing and close_left <= 0.0):
		return
	updates += 1
	for e in meshes:
		var mi: MeshInstance3D = e[0]
		if not is_instance_valid(mi):
			continue
		var idx: Dictionary = e[1]
		for nm in idx:
			mi.set_blend_shape_value(idx[nm], last_weights[nm])
