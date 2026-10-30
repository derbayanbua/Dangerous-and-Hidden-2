extends Node
## Skriptanimationen der Original-Missionsskripte (*.i3d = MODELS\<name>.5DS, Export tools/fmt_i3d.py → orig_cache/anims).
## Belege docs/re_notes_script_anims.md:
##  * FRM_SetAnimation (Opcode 0x5D) / FRM_SetAnimationDelayed (0x60): Handler hd2.exe 0x41BAA7. Argumente (Frame, Name,
##    Kanal): Animationssatz laden (Cache 0x8AEC18, 0x41FC10), Modus am Satz (+8) = 2 bzw. 1 (0x41D4C0), dann
##    Frame->SetAnimation(Satz, Kanal, 1.0, 0) (vtbl +0x84). Leerer Name: Kanal stoppen (vtbl +0x9C/+0x8C) und leeren.
##  * FRM_ResetAnimation (0x61, 0x41B9F1): wie leerer Name, zusätzlich vtbl +0x20(1) = Ruhelage [P].
##  * FRM_StopAnimation (0x63, 0x41B96E): Kanal anhalten (vtbl +0x8C), Lage bleibt [P].
##  * CSC_SetCameraAnimation (0xA7, 0x41CB37): Zwischensequenz-Objekt (0x486510) vtbl +0xB0(Frame, Name).
## Anwendung (re_notes_5ds_skin §4 [B]): 5DS-Werte ersetzen die LOKALE Lage der gleichnamigen Frames unter dem Ziel
## (Knochen der Figur bzw. Unterframes des Modells). Kameraanimation: das (einzige) Animationsobjekt gibt die WELT-Lage
## des Kameraframes vor (Daten: #CamAf2a1..6 liegen in Weltkoordinaten der Karte, Ju-88-Analogie 0x5F6100) [P].
## Zeitbasis 25 Bilder/s [P, re_notes_ju88 §2.2: #CamA6a6 210 Bilder ↔ 8300 ms Skriptpause]. Nach dem letzten Bild bleibt
## die letzte Lage stehen (keine Wiederholung) [E: Abspielmodus des Satzes (+8) im LS3DF.dll nicht dekodiert].
## 5DS-Ereignisse „$datei.wav a b“ (Sprechgeräusche der Darsteller) spielen die Datei am Frame ab [P: a/b = Mindest-/
## Höchstabstand].

const FPS := 25.0

var _cache := {}        ## Name (klein) -> Daten (Dictionary) oder null
var _tracks: Array = [] ## {target, channel, data, t, binds, camera, done, ev_i}
var _rest := {}         ## Schlüssel (Instanz-ID/Knochen) -> ursprüngliche Lage
var _suspended := {}    ## Ziel -> [AnimationPlayer/SkeletonModifier3D, die während der Animation ruhen]
var played := []        ## Diagnose/Tests: gestartete Animationen [Ziel, Name]


func _ready() -> void:
	process_priority = -1     # vor LsRuntime._process (Kamera der Zwischensequenz folgt dem Kameraframe)


static func norm_name(n: String) -> String:
	var s := n.strip_edges().replace("%%", "%")
	if s.to_lower().ends_with(".i3d"):
		s = s.substr(0, s.length() - 4)
	return s


func load_anim(n: String):
	var key := norm_name(n).to_lower()
	if _cache.has(key):
		return _cache[key]
	# Binärformat „HDA1“ (tools/fmt_i3d.py); Schlüssel als PackedFloat32Array [Bild, Werte…] – das frühere JSON
	# brauchte beim Parsen sehr viel Speicher (nativer Absturz bei knappem Speicher, AFRICA1 24.10.2026)
	var f := FileAccess.open(OrigLevel.cache_root() + "/anims/" + key + ".hda", FileAccess.READ)
	_cache[key] = _read_hda(f) if f else null
	if _cache[key] == null:
		push_warning("Skriptanimation fehlt im Cache: %s (tools/fmt_i3d.py)" % key)
	return _cache[key]


static func _read_hda(f: FileAccess):
	if f.get_length() < 10 or f.get_buffer(4).get_string_from_ascii() != "HDA1":
		return null
	var d := {"last_frame": f.get_32(), "objects": []}
	var nobj := f.get_16()
	for i in nobj:
		var o := {"name": f.get_buffer(f.get_8()).get_string_from_ascii()}
		for ch in [["rot", 5], ["pos", 4], ["scale", 4]]:
			var n := f.get_32()
			if n > 0:
				var buf := f.get_buffer(n * int(ch[1]) * 4)
				o[ch[0]] = buf.to_float32_array()
		var ne := f.get_32()
		if ne > 0:
			var evs := []
			for k in ne:
				var fr := f.get_float()
				evs.append([fr, f.get_buffer(f.get_16()).get_string_from_ascii()])
			o["events"] = evs
		d["objects"].append(o)
	return d


## FRM_SetAnimation / FRM_SetAnimationDelayed. Leerer Name = Kanal leeren.
func set_animation(target: Node3D, anim_name: String, channel: int, loop := false, ai_human := false) -> bool:
	if target == null:
		return false
	_drop(target, channel, false)
	if norm_name(anim_name) == "":
		_release_if_idle(target)
		return true
	var d = load_anim(anim_name)
	if d == null:
		_release_if_idle(target)
		return false
	# ai_human (HUMAN_SetAnim): endet, sobald die Figur sich bewegt, kämpft oder stirbt [E]
	var tr := {"target": target, "channel": channel, "data": d, "t": 0.0, "camera": false, "done": false, "ev_i": 0,
		"name": norm_name(anim_name), "loop": loop, "ai": ai_human}
	tr["binds"] = _bind(target, d)
	_suspend(target)
	_tracks.append(tr)
	played.append([String(target.name), norm_name(anim_name)])
	_apply(tr)
	return true


## CSC_SetCameraAnimation: Kameraframe folgt dem Animationsobjekt (Weltlage). Leerer Name = beenden.
func set_camera_animation(cam: Node3D, anim_name: String) -> bool:
	if cam == null:
		return false
	_drop(cam, -1, false)
	if norm_name(anim_name) == "":
		return true
	var d = load_anim(anim_name)
	if d == null or (d["objects"] as Array).is_empty():
		return false
	var tr := {"target": cam, "channel": -1, "data": d, "t": 0.0, "camera": true, "done": false, "ev_i": 0,
		"name": norm_name(anim_name), "binds": [{"node": cam, "obj": d["objects"][0], "world": true}]}
	_tracks.append(tr)
	played.append([String(cam.name), norm_name(anim_name)])
	_apply(tr)
	return true


## FRM_StopAnimation: Kanal anhalten, Lage bleibt
func stop_animation(target: Node3D, channel: int) -> void:
	_drop(target, channel, false)
	_release_if_idle(target)


## FRM_ResetAnimation: Kanal leeren und Ruhelage herstellen
func reset_animation(target: Node3D, channel: int) -> void:
	_drop(target, channel, true)
	_release_if_idle(target)


func is_playing(target: Node3D) -> bool:
	for tr in _tracks:
		if tr["target"] == target and not tr["done"]:
			return true
	return false


func _drop(target: Node3D, channel: int, restore: bool) -> void:
	for tr in _tracks.duplicate():
		if tr["target"] == target and (channel < 0 or int(tr["channel"]) == channel or tr["camera"]):
			_tracks.erase(tr)
			if restore:
				for b in tr["binds"]:
					_restore(b)


func _release_if_idle(target: Node3D) -> void:
	for tr in _tracks:
		if tr["target"] == target:
			return
	if _suspended.has(target):
		for n in _suspended[target]:
			if is_instance_valid(n):
				if n is AnimationPlayer:
					(n as AnimationPlayer).active = true
				elif n is SkeletonModifier3D:
					(n as SkeletonModifier3D).active = true
		_suspended.erase(target)


## Während einer Skriptanimation ruhen die Spielanimationen der Figur (BodyAnim/Haltung/IK)
func _suspend(target: Node3D) -> void:
	if _suspended.has(target):
		return
	var lst: Array = []
	for n in target.find_children("*", "AnimationPlayer", true, false):
		if (n as AnimationPlayer).active:
			(n as AnimationPlayer).active = false
			lst.append(n)
	for n in target.find_children("*", "SkeletonModifier3D", true, false):
		if (n as SkeletonModifier3D).active:
			(n as SkeletonModifier3D).active = false
			lst.append(n)
	_suspended[target] = lst


## Statische Menschenmodelle der Szene (Objekttyp 9, z. B. AFRICA1 „CUTit1“ = it02) sind als ungeskinnte Meshes in
## T-Haltung exportiert; ihre Knochen-Frames (a, b, c …) bewegen das Mesh nicht → Darsteller standen in T-Pose.
## Bei der ersten Skriptanimation wird die geskinnte Originalfigur (orig_cache/characters/<modell>.glb, gleiche
## Knochennamen) eingesetzt und das statische Mesh ausgeblendet [E: Original zeichnet dieselbe Figur geskinnt].
func _actor_figure(target: Node3D) -> Node3D:
	var ex := target.get_node_or_null("ActorFigure") as Node3D
	if ex:
		return ex
	if not target.has_meta("orig_model") or target.find_child("a", true, false) == null:
		return null
	var rt = get_parent()
	var lvl = rt.get("orig") if rt else null
	if lvl == null or not lvl.has_method("character_instance"):
		return null
	var fig: Node3D = lvl.character_instance(String(target.get_meta("orig_model")))
	if fig == null:
		return null
	for v in target.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).visible = false
	fig.name = "ActorFigure"
	target.add_child(fig)
	return fig


## Animationsobjekte den Knochen/Unterframes des Ziels zuordnen (Namen ohne Groß-/Kleinschreibung)
func _bind(target: Node3D, d: Dictionary) -> Array:
	var binds: Array = []
	var sk: Skeleton3D = null
	var sks := target.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		var fig := _actor_figure(target)
		if fig:
			sks = fig.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		sk = sks[0] as Skeleton3D
	var nodes := {}
	for c in target.find_children("*", "Node3D", true, false):
		var k := String(c.name).to_lower()
		if not nodes.has(k):
			nodes[k] = c
	for o in d["objects"]:
		var nm := String(o["name"]).to_lower()
		if sk:
			var bi := -1
			for i in sk.get_bone_count():
				if sk.get_bone_name(i).to_lower() == nm:
					bi = i
					break
			if bi >= 0:
				binds.append({"skel": sk, "bone": bi, "obj": o})
				continue
		# Nicht-Knochen-Frames einer Figur (hw1, camera3RD … als Knoten unter dem Skelett) nicht verschieben
		if nodes.has(nm) and not (sk and sk.is_ancestor_of(nodes[nm])):
			binds.append({"node": nodes[nm], "obj": o})
	return binds


func _process(delta: float) -> void:
	for tr in _tracks.duplicate():
		if not is_instance_valid(tr["target"]):
			_tracks.erase(tr)
			continue
		if tr.get("ai", false) and float(tr["t"]) > 0.5 and _ai_interrupted(tr["target"]):
			_tracks.erase(tr)
			_release_if_idle(tr["target"])
			continue
		if tr["done"]:
			continue
		tr["t"] = float(tr["t"]) + delta
		_apply(tr)


func _ai_interrupted(t: Node3D) -> bool:
	if not (t is Soldier):
		return false
	var s := t as Soldier
	if not s.alive or Vector2(s.velocity.x, s.velocity.z).length() > 0.4:
		return true
	var b = s.get_node_or_null("EnemyBrain")
	return b != null and (b.state == EnemyBrain.State.COMBAT or b.state == EnemyBrain.State.SEARCH)


func _apply(tr: Dictionary) -> void:
	var d: Dictionary = tr["data"]
	var last := float(d.get("last_frame", 0))
	var f := float(tr["t"]) * FPS
	if f >= last and tr.get("loop", false) and last > 0.0:
		f = fmod(f, last)
		tr["t"] = f / FPS
		tr["ev_i"] = 0
	elif f >= last:
		f = last
		tr["done"] = true
	for b in tr["binds"]:
		var o: Dictionary = b["obj"]
		var pos = _sample(o.get("pos", []), f, 3)
		var rot = _sample(o.get("rot", []), f, 4)
		var scl = _sample(o.get("scale", []), f, 3)
		if b.has("skel"):
			var sk: Skeleton3D = b["skel"]
			if not is_instance_valid(sk):
				continue
			var bi: int = b["bone"]
			_remember(b)
			if pos != null:
				sk.set_bone_pose_position(bi, pos)
			if rot != null:
				sk.set_bone_pose_rotation(bi, rot)
			if scl != null:
				sk.set_bone_pose_scale(bi, scl)
		else:
			var n: Node3D = b["node"]
			if not is_instance_valid(n):
				continue
			_remember(b)
			if b.get("world", false):
				var q: Quaternion = n.global_basis.get_rotation_quaternion()
				if rot != null:
					q = rot
				var p: Vector3 = n.global_position
				if pos != null:
					p = pos
				n.global_transform = Transform3D(Basis(q), p)
			else:
				if pos != null:
					n.position = pos
				if rot != null:
					n.quaternion = rot
				if scl != null:
					n.scale = scl
		# Ereignisse (Klänge) bis zum aktuellen Bild auslösen
		var evs: Array = o.get("events", [])
		while int(tr["ev_i"]) < evs.size() and float(evs[int(tr["ev_i"])][0]) <= f:
			_event(tr["target"], String(evs[int(tr["ev_i"])][1]))
			tr["ev_i"] = int(tr["ev_i"]) + 1


func _event(target: Node3D, ev: String) -> void:
	if not ev.begins_with("$"):
		return
	var parts := ev.substr(1).split(" ", false)
	if parts.is_empty():
		return
	var mn := float(parts[1]) if parts.size() > 1 else 1.0
	var mx := float(parts[2]) if parts.size() > 2 else 30.0
	OrigAudio.play_file(parts[0], target.global_position, mn, maxf(mx, mn + 1.0) * 4.0, 1.0, target)


func _remember(b: Dictionary) -> void:
	var key: String
	if b.has("skel"):
		key = "%d:%d" % [(b["skel"] as Object).get_instance_id(), int(b["bone"])]
		if not _rest.has(key):
			var sk: Skeleton3D = b["skel"]
			_rest[key] = [sk.get_bone_pose_position(b["bone"]), sk.get_bone_pose_rotation(b["bone"]), sk.get_bone_pose_scale(b["bone"])]
	else:
		key = str((b["node"] as Object).get_instance_id())
		if not _rest.has(key):
			_rest[key] = (b["node"] as Node3D).transform


func _restore(b: Dictionary) -> void:
	if b.has("skel"):
		var key := "%d:%d" % [(b["skel"] as Object).get_instance_id(), int(b["bone"])]
		if _rest.has(key) and is_instance_valid(b["skel"]):
			var sk: Skeleton3D = b["skel"]
			var r: Array = _rest[key]
			sk.set_bone_pose_position(b["bone"], r[0])
			sk.set_bone_pose_rotation(b["bone"], r[1])
			sk.set_bone_pose_scale(b["bone"], r[2])
	else:
		var key2 := str((b["node"] as Object).get_instance_id())
		if _rest.has(key2) and is_instance_valid(b["node"]):
			(b["node"] as Node3D).transform = _rest[key2]


## Schlüssel [Bild, Werte…] linear (Position/Skalierung) bzw. sphärisch (Rotation) interpolieren; vor dem ersten/nach dem
## letzten Schlüssel gilt dieser.
static func _sample(keys, f: float, n: int):
	if not (keys is PackedFloat32Array) or (keys as PackedFloat32Array).is_empty():
		return null
	var k: PackedFloat32Array = keys
	var st := n + 1
	var cnt := k.size() / st
	var lo := 0
	var hi := cnt - 1
	if f <= k[0]:
		return _val(k, 0, n)
	if f >= k[hi * st]:
		return _val(k, hi * st, n)
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if k[mid * st] <= f:
			lo = mid
		else:
			hi = mid
	var fa := k[lo * st]
	var fb := k[hi * st]
	var t := (f - fa) / maxf(fb - fa, 0.0001)
	if n == 4:
		return (_val(k, lo * st, 4) as Quaternion).slerp(_val(k, hi * st, 4), t)
	return (_val(k, lo * st, 3) as Vector3).lerp(_val(k, hi * st, 3), t)


static func _val(k: PackedFloat32Array, i: int, n: int):
	if n == 4:
		return Quaternion(k[i + 1], k[i + 2], k[i + 3], k[i + 4]).normalized()
	return Vector3(k[i + 1], k[i + 2], k[i + 3])
