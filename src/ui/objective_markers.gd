class_name ObjectiveMarkers
extends Control
## BEWUSSTE ABWEICHUNG vom Original (Vorgabe Auftraggeber „Quest-Ziele deutlicher markieren“):
## dezente Zielmarker im Bild bzw. Pfeile am Bildschirmrand mit Entfernung für aktive Missionsziele mit bekanntem Ort.
## Das Original zeigt Ziele nur im Zielbildschirm (Text) – hier zusätzlich, abschaltbar (Settings.objective_markers,
## Optionen SPIEL „ZIELMARKIERUNGEN“, Standard an). Stil: Farbe/Umriss wie die Original-HUD-Schrift (x_mo2-Beige).
##
## Ortsquellen (nur Daten/Skripte, nichts erfunden):
##  1. Missionsobjekte: Original-Sprengplätze (Typ 22) ohne Ladung (Zustand 0 frei bzw. 3 noch versteckt), Foto-/
##     Dokumentplätze (15/23) im Zustand 0 – solange ein Pflichtziel aktiv ist.
##  2. Skript-Zielorte (OrigMission): Frame eines Skripts, dessen `Whenever (… _PlayerInRange(r) …)` im Rumpf
##     `SetObjectiveStatus(i, 1)` setzt (auch über `CSC_RunCutscene(k)` → `OnCutsceneDone(k)`), für Pflichtziel i.
##  3. Eigene Missionen: `Mission.objective_target(id)` (falls vorhanden) → Node3D/Vector3.

const COL := Color(0.95, 0.9, 0.75, 0.9)        ## wie Zeitzünder-Schrift (OrigHud)
const COL_DIM := Color(0.95, 0.9, 0.75, 0.55)
const OUTLINE := Color(0.08, 0.06, 0.04, 0.85)
const MAX_SHOWN := 4
const EDGE := 36.0

var mission: Mission
var targets: Array = []          ## [{pos, label, kind, screen, on_screen, dist}] (Tests)
var _script_targets := {}        ## Original-Zielindex -> Array[Node3D]
var _scanned := false
var _acc := 0.0
var _font: Font


func setup(m: Mission) -> void:
	mission = m
	name = "ObjectiveMarkers"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_acc -= delta
	if _acc <= 0.0:
		_acc = 0.2
		_collect()
	queue_redraw()


func _enabled() -> bool:
	if not Settings.objective_markers or mission == null or not is_instance_valid(mission):
		return false
	var rt = mission.get("runtime")
	if rt and is_instance_valid(rt) and bool(rt.get("in_cutscene")):
		return false
	return true


## Pflichtziele aktiv? (Original: Status 0 „in Arbeit“; nicht freigeschaltete Ziele sind INACTIVE)
func _active_mandatory() -> Array:
	var out: Array = []
	for o in mission.objectives:
		if o.state == Objective.State.ACTIVE and not o.optional and not o.secondary:
			out.append(o)
	return out


func _collect() -> void:
	targets.clear()
	if not _enabled():
		return
	var act := _active_mandatory()
	if act.is_empty():
		return
	# 1. Missionsobjekte (Original-Akteure)
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is OrigInteractive.OrigExplosive:
			var x := n as OrigInteractive.OrigExplosive
			# nur freigegebene, sichtbare Plätze (versteckte – Zustand 3 – nicht verraten)
			if x.enabled and x.state == 0 and x.frame.is_visible_in_tree():
				_add(x.global_position, x.label, "explosive")
		elif n is OrigInteractive.OrigPlace:
			var p := n as OrigInteractive.OrigPlace
			if p.enabled and p.state == 0:
				_add(p.global_position, "", "place")
	# 2./3. Zielorte je aktivem Pflichtziel
	if mission is OrigMission:
		_scan_scripts()
		for idx in mission.orig_objectives:
			var o: Objective = mission.objective(mission.orig_objectives[idx])
			if o == null or not act.has(o):
				continue
			for f in _script_targets.get(int(idx), []):
				if is_instance_valid(f):
					_add((f as Node3D).global_position, o.text, "objective")
	elif mission.has_method("objective_target"):
		for o in act:
			var t = mission.objective_target(o.id)
			if t is Node3D and is_instance_valid(t):
				_add((t as Node3D).global_position, o.text, "objective")
			elif t is Vector3:
				_add(t, o.text, "objective")
	var from := _eye()
	for t in targets:
		t["dist"] = from.distance_to(t["pos"])
	targets.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	if targets.size() > MAX_SHOWN:
		targets.resize(MAX_SHOWN)


func _add(pos: Vector3, label: String, kind: String) -> void:
	for t in targets:
		if (t["pos"] as Vector3).distance_to(pos) < 1.0:
			return
	targets.append({"pos": pos, "label": label, "kind": kind, "screen": Vector2.ZERO, "on_screen": false, "dist": 0.0})


func _eye() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		return cam.global_position
	var a: Soldier = mission.controller.active if mission and mission.controller else null
	return a.global_position if a else Vector3.ZERO


## Skript-Zielorte aus den Originalskripten (einmalig, Quelltext ohne Kommentare)
func _scan_scripts() -> void:
	if _scanned:
		return
	_scanned = true
	var rt = mission.get("runtime")
	if rt == null or rt.orig == null:
		return
	var sdir: String = rt.orig.mission_dir + "/scripts"
	for vm in rt.vms:
		if vm.me == null or vm.me is Soldier or vm.name == "":
			continue
		var f := FileAccess.open(sdir + "/" + vm.name, FileAccess.READ)
		if f == null:
			continue
		for idx in script_objective_targets(f.get_buffer(f.get_length()).get_string_from_ascii()):
			if not _script_targets.has(idx):
				_script_targets[idx] = []
			_script_targets[idx].append(vm.me)


## Zielindizes, die ein Skript beim Betreten seines Bereichs erfüllt (statisch, für Tests öffentlich)
static func script_objective_targets(src: String) -> Array:
	var lines: Array = []
	for l: String in src.split("\n"):
		var c: int = l.find("//")
		lines.append(l.substr(0, c) if c >= 0 else l)
	var blocks := {}       # Kopf -> Rumpftext
	var cur := ""
	var body := ""
	var heads: Array = []
	var head_re := RegEx.create_from_string("^(Whenever|OnSignal|OnCutsceneDone|OnCutscene|OnDeath|OnUse|OnHit|Label|label)\\b")
	for l in lines:
		var t := String(l).strip_edges(true, false)
		if head_re.search(String(l)) != null:
			if cur != "":
				blocks[cur] = body
			cur = t
			heads.append(t)
			body = ""
		elif cur != "":
			body += String(l) + "\n"
	if cur != "":
		blocks[cur] = body
	var set_re := RegEx.create_from_string("SetObjectiveStatus\\s*\\(\\s*(\\d+)\\s*,\\s*1\\s*\\)")
	var cut_re := RegEx.create_from_string("CSC_RunCutscene\\s*\\(\\s*(\\d+)\\s*\\)")
	var out: Array = []
	for h in heads:
		if not String(h).begins_with("Whenever") or String(h).find("_PlayerInRange") < 0:
			continue
		var b: String = blocks.get(h, "")
		var texts: Array = [b]
		for m in cut_re.search_all(b):
			for h2 in heads:
				if String(h2).replace(" ", "").begins_with("OnCutsceneDone(%s)" % m.get_string(1)):
					texts.append(blocks.get(h2, ""))
		for tx in texts:
			for m in set_re.search_all(String(tx)):
				var i := int(m.get_string(1))
				if not out.has(i):
					out.append(i)
	return out


func _draw() -> void:
	if targets.is_empty() or not _enabled():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var center := size * 0.5
	var fs := maxi(10, int(size.y / 60.0))
	for t in targets:
		var p: Vector3 = t["pos"] + Vector3(0, 0.6, 0)
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		var inner := rect.grow(-EDGE)
		var on := not behind and inner.has_point(sp)
		t["on_screen"] = on
		var dist_txt := "%d m" % int(round(float(t["dist"])))
		if on:
			t["screen"] = sp
			# kleiner, nach unten zeigender Keil über dem Ziel
			var s := 7.0
			var pts := PackedVector2Array([sp + Vector2(-s, -2 * s), sp + Vector2(s, -2 * s), sp])
			draw_colored_polygon(pts, COL_DIM if t["kind"] != "objective" else COL)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), OUTLINE, 1.5)
			_text(sp + Vector2(0, -2 * s - 4), dist_txt, fs)
		else:
			var d := sp - center
			if behind:
				d = -d
				if d.length() < 1.0:
					d = Vector2(0, 1)
			var dir := d.normalized()
			var half := inner.size * 0.5
			var k: float = minf(absf(half.x / dir.x) if absf(dir.x) > 0.001 else 1e9, absf(half.y / dir.y) if absf(dir.y) > 0.001 else 1e9)
			var ep := center + dir * k
			t["screen"] = ep
			var s2 := 9.0
			var nrm := Vector2(-dir.y, dir.x)
			var tri := PackedVector2Array([ep + dir * s2, ep - dir * s2 + nrm * s2 * 0.8, ep - dir * s2 - nrm * s2 * 0.8])
			draw_colored_polygon(tri, COL)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), OUTLINE, 1.5)
			_text(ep - dir * (s2 + fs), dist_txt, fs)


func _text(pos: Vector2, s: String, fs: int) -> void:
	if _font == null:
		return
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos + Vector2(-w * 0.5, 0)
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.04, 0.03, 1.0))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL)
