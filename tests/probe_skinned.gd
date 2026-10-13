extends SceneTree
## Prüft konvertierte Original-Charaktere (Skin + 5DS-Animationen) zur Laufzeit.
##   tools\godot.cmd --headless --script res://tests/probe_skinned.gd [-- <glb> ...]
## Standard: D:/Workspace_D/re_work/chars/ge10.glb und en01.glb (aus tools/skinned_gltf.py).
## Lädt per GLTFDocument, sucht Skeleton3D/AnimationPlayer/geskinnte MeshInstance3D,
## spielt Animationen an, setzt Zeitpunkte und gibt Knochen-Weltpositionen aus.
## Exit 0 = alle Prüfungen bestanden.

const DEFAULT_FILES := ["D:/Workspace_D/re_work/chars/ge10.glb", "D:/Workspace_D/re_work/chars/en01.glb"]
const PROBE_BONES := ["a", "f", "j", "n", "r", "v"]   # Becken, Kopf, Hände, Füße

var _files: Array = []
var _scenes: Array = []
var _fails := 0
var _frame := 0


func _initialize() -> void:
	_files = Array(OS.get_cmdline_user_args())
	if _files.is_empty():
		_files = DEFAULT_FILES.duplicate()
	for f in _files:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(f, st)
		if err != OK:
			_fail("%s: append_from_file Fehler %d" % [f, err])
			_scenes.append(null)
			continue
		var sc: Node = doc.generate_scene(st)
		root.add_child(sc)
		_scenes.append(sc)
		print("GELADEN %s: Knoten %d, Animationen %d, Skins %d" % [f.get_file(), st.get_nodes().size(),
			st.get_animations().size(), st.get_skins().size()])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false   # einen Frame warten, damit alles im Baum ist
	for i in _files.size():
		if _scenes[i] != null:
			_check(_files[i], _scenes[i])
	print("ERGEBNIS: %s (%d Fehler)" % ["OK" if _fails == 0 else "FEHLER", _fails])
	quit(0 if _fails == 0 else 1)
	return true


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)


func _find(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_find(c, cls, out)


func _check(path: String, sc: Node) -> void:
	var skels: Array = []
	var players: Array = []
	var meshes: Array = []
	_find(sc, "Skeleton3D", skels)
	_find(sc, "AnimationPlayer", players)
	_find(sc, "MeshInstance3D", meshes)
	if skels.size() != 1:
		_fail("%s: erwartet 1 Skeleton3D, gefunden %d" % [path, skels.size()])
		return
	if players.is_empty():
		_fail("%s: kein AnimationPlayer" % path)
		return
	var sk: Skeleton3D = skels[0]
	var ap: AnimationPlayer = players[0]
	var skinned := 0
	for m: MeshInstance3D in meshes:
		if m.skin != null and m.get_node_or_null(m.skeleton) == sk:
			skinned += 1
			print("  Skin-Mesh %s: %d Bindungen, %d Oberflächen" % [m.name, m.skin.get_bind_count(), m.mesh.get_surface_count()])
	if skinned == 0:
		_fail("%s: kein an das Skelett gebundenes Mesh" % path)
	print("  Skelett: %d Knochen; Animationen: %s" % [sk.get_bone_count(), ap.get_animation_list()])
	for b in PROBE_BONES:
		if sk.find_bone(b) < 0:
			_fail("%s: Knochen %s fehlt" % [path, b])
			return
	var rest := _bone_world(sk, "f")
	print("  Ruhelage Kopf f = %s" % rest)
	for an in ap.get_animation_list():
		if an == "RESET":
			continue
		var anim := ap.get_animation(an)
		ap.play(an)
		var line := "  %-7s len %.2fs Spuren %d |" % [an, anim.length, anim.get_track_count()]
		var moved := false
		var prev := Vector3.INF
		for k in 3:
			var t := anim.length * k / 2.0
			ap.seek(t, true)
			var head := _bone_world(sk, "f")
			var lh := _bone_world(sk, "j")
			var lf := _bone_world(sk, "r")
			line += " t=%.2f Kopf(%.2f,%.2f,%.2f) Hand j(%.2f,%.2f,%.2f) Fuß r y=%.2f |" % [t, head.x, head.y, head.z, lh.x, lh.y, lh.z, lf.y]
			if prev != Vector3.INF and prev.distance_to(lh) > 0.01:
				moved = true
			prev = lh
			if not (head.is_finite() and lh.is_finite()):
				_fail("%s/%s: ungültige Knochenpose" % [path, an])
		print(line)
		if not moved and an != "idle":
			_fail("%s/%s: Hand bewegt sich nicht" % [path, an])
		ap.stop()
	# Plausibilität der Haltung im Stehen: Kopf deutlich über Händen, Füße am Boden
	if ap.has_animation("idle"):
		ap.play("idle")
		ap.seek(0.0, true)
		var h := _bone_world(sk, "f")
		var hand := _bone_world(sk, "j")
		var foot := _bone_world(sk, "r")
		print("  idle t=0: Kopf y %.3f, Hand y %.3f, Fuß y %.3f" % [h.y, hand.y, foot.y])
		if not (h.y > 1.4 and hand.y < 1.2 and foot.y < 0.2):
			_fail("%s: idle-Haltung unplausibel" % path)


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin
