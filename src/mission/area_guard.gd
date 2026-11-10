extends Node
## fix_0103 [D] Einsatzgebiet verlassen (nur Einzelspieler, Original- und eigene Missionen; per preload, kein class_name).
## Verlässt der aktive Spielersoldat das Einsatzgebiet, zeigt das HUD eine Warnung mit 10-s-Countdown; ist er danach nicht
## zurück, scheitert die Mission.
## Grenze (ohne Kollisionsabfrage, rein geometrisch):
##  1. Border-Flächen (Körper auf LevelBuilder.BORDER_LAYER, Frames „…border…“): senkrechte Dreiecke → 2D-Strecken (x/z);
##     Innen = Paritätstest mit Strahlen in vier Richtungen (Mehrheit ≥ 2 von 4 ungerade, Lücken im Zaun verzeihen).
##  2. ohne Border-Flächen: Kartengrenze = Grundriss der statischen Levelgeometrie (+2 m), dazu „unter die Karte gefallen“.
## Selbstschutz: Steht der aktive Soldat bei der ersten Prüfung schon „außerhalb“, ist die Grenze für diese Karte
## unbrauchbar → Wächter aus (Meldung AREAGUARD). Unter --autoplay nur mit --area_guard=1 aktiv (Tests versetzen Figuren).

const COUNTDOWN := 10.0
const CHECK_DT := 0.25

var mission: Node
var segments: Array = []            # [Vector2 a, Vector2 b]
var seg_rect := Rect2()
var map_box := AABB()
var mode := ""                      # "border" | "map" | "" (aus)
var outside := false
var left_t := 0.0                   # Restzeit des Countdowns
var failed := false
var _check_t := 0.0
var _armed := false
var _label: Label
var _layer: CanvasLayer


static func enabled_for_session() -> bool:
	if Net.is_online:
		return false
	var opt := String(Game.cli.get("area_guard", ""))
	if opt == "0":
		return false
	if Game.cli.has("autoplay"):
		return opt == "1"
	return true


func setup(m: Node) -> void:
	mission = m
	mode = "pending"
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = 120
	_label.offset_left = -480
	_label.offset_right = 480
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.25, 0.2))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.add_theme_font_size_override(&"font_size", 26)
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.visible = false
	_layer.add_child(_label)


## Grenze erfassen (beim ersten Prüfen, wenn die Karte steht). Öffentlich für Tests.
func build() -> void:
	segments.clear()
	_collect_border()
	if segments.size() >= 2:
		mode = "border"
	else:
		_collect_map_box()
		mode = "map" if map_box.size.x > 1.0 else ""
	print("AREAGUARD Modus %s, Strecken %d" % [mode if mode != "" else "aus", segments.size()])


func _collect_border() -> void:
	var r := Rect2()
	var first := true
	for b in mission.find_children("*", "StaticBody3D", true, false):
		var sb := b as StaticBody3D
		if sb.collision_layer & LevelBuilder.BORDER_LAYER == 0:
			continue
		for c in sb.get_children():
			if not (c is CollisionShape3D) or (c as CollisionShape3D).shape == null:
				continue
			var xf := (c as CollisionShape3D).global_transform
			var sh := (c as CollisionShape3D).shape
			if sh is ConcavePolygonShape3D:
				var f: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
				for i in range(0, f.size() - 2, 3):
					var p0: Vector3 = xf * f[i]
					var p1: Vector3 = xf * f[i + 1]
					var p2: Vector3 = xf * f[i + 2]
					var n := (p1 - p0).cross(p2 - p0)
					if n.length() < 1e-4 or absf(n.normalized().y) > 0.7:
						continue          # waagrechte „Deckel“ zählen nicht
					var q := [Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z)]
					var a: Vector2 = q[0]
					var bb: Vector2 = q[1]
					var best := (q[0] as Vector2).distance_squared_to(q[1])
					if (q[1] as Vector2).distance_squared_to(q[2]) > best:
						best = (q[1] as Vector2).distance_squared_to(q[2]); a = q[1]; bb = q[2]
					if (q[0] as Vector2).distance_squared_to(q[2]) > best:
						a = q[0]; bb = q[2]
					if a.distance_to(bb) < 0.05:
						continue
					segments.append([a, bb])
					var sr := Rect2(a, Vector2.ZERO).expand(bb)
					r = sr if first else r.merge(sr)
					first = false
			elif sh is BoxShape3D:
				var e := (sh as BoxShape3D).size * 0.5
				var cs := [Vector3(-e.x, 0, -e.z), Vector3(e.x, 0, -e.z), Vector3(e.x, 0, e.z), Vector3(-e.x, 0, e.z)]
				for k in 4:
					var u: Vector3 = xf * (cs[k] as Vector3)
					var v: Vector3 = xf * (cs[(k + 1) % 4] as Vector3)
					segments.append([Vector2(u.x, u.z), Vector2(v.x, v.z)])
					var sr2 := Rect2(Vector2(u.x, u.z), Vector2.ZERO).expand(Vector2(v.x, v.z))
					r = sr2 if first else r.merge(sr2)
					first = false
	seg_rect = r


func _collect_map_box() -> void:
	var root: Node = mission.get("static_root")
	if root == null:
		return
	var first := true
	for b in root.find_children("*", "StaticBody3D", true, false):
		var sb := b as StaticBody3D
		if sb.collision_layer & 1 == 0:
			continue
		for c in sb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var sh := (c as CollisionShape3D).shape
				var ab := AABB()
				if sh is ConcavePolygonShape3D:
					var f := (sh as ConcavePolygonShape3D).get_faces()
					if f.is_empty():
						continue
					ab = AABB(f[0], Vector3.ZERO)
					for v in f:
						ab = ab.expand(v)
				elif sh is BoxShape3D:
					ab = AABB(-(sh as BoxShape3D).size * 0.5, (sh as BoxShape3D).size)
				elif sh is HeightMapShape3D:
					var hm := sh as HeightMapShape3D
					ab = AABB(Vector3(-hm.map_width * 0.5, hm.get_min_height(), -hm.map_depth * 0.5),
						Vector3(hm.map_width, hm.get_max_height() - hm.get_min_height(), hm.map_depth))
				else:
					continue
				ab = (c as CollisionShape3D).global_transform * ab
				if ab.size.length() > 6000.0:
					continue
				map_box = ab if first else map_box.merge(ab)
				first = false


## Innen-Test (ohne Kollision). Öffentlich für Tests.
func is_inside(p: Vector3) -> bool:
	if mode == "border":
		var q := Vector2(p.x, p.z)
		if not seg_rect.grow(1.0).has_point(q):
			return false
		var odd := 0
		for d in 4:
			if _crossings(q, d) % 2 == 1:
				odd += 1
		return odd >= 2
	if mode == "map":
		var g := map_box.grow(2.0)
		return p.x >= g.position.x and p.x <= g.end.x and p.z >= g.position.z and p.z <= g.end.z \
			and p.y >= map_box.position.y - 8.0
	return true


## Zahl der Grenzdurchgänge eines Strahls von q in Richtung d (0 +x, 1 −x, 2 +z, 3 −z); Treffer < 0,6 m
## auseinander gelten als einer (zwei Dreiecke einer Wandfläche, Doppelflächen).
func _crossings(q: Vector2, d: int) -> int:
	var hits: Array[float] = []
	var along_x := d < 2
	var sgn := 1.0 if d % 2 == 0 else -1.0
	for s in segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ca := a.y if along_x else a.x
		var cb := b.y if along_x else b.x
		var c0 := q.y if along_x else q.x
		if (ca <= c0) == (cb <= c0):
			continue
		var t := (c0 - ca) / (cb - ca)
		var pos := lerpf(a.x, b.x, t) if along_x else lerpf(a.y, b.y, t)
		var rel := (pos - (q.x if along_x else q.y)) * sgn
		if rel > 0.0:
			hits.append(rel)
	hits.sort()
	var n := 0
	var last := -INF
	for h in hits:
		if h - last > 0.6:
			n += 1
		last = h
	return n


func _physics_process(delta: float) -> void:
	if mode == "" or failed or mission == null or bool(mission.get("finished")):
		_show(false)
		return
	var ctl = mission.get("controller")
	if ctl == null or not ctl.input_enabled:
		return               # Zwischensequenz/Menü: Countdown ruht
	var s: Soldier = ctl.active
	if s == null or not s.alive:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_DT
		var p: Vector3 = s.vehicle.global_position if s.vehicle != null else s.global_position
		var inside := _armed and is_inside(p)
		if not _armed:
			_armed = true
			build()
			inside = is_inside(p)
			if mode != "" and not inside:
				print("AREAGUARD Startpunkt %s liegt außerhalb der erkannten Grenze → Wächter aus" % p)
				mode = ""
				return
		if not inside and not outside:
			left_t = COUNTDOWN
		outside = not inside
	if outside:
		left_t -= delta
		_label.text = tr("EINSATZGEBIET VERLASSEN! Zurück in %d s, sonst scheitert die Mission.") % ceili(maxf(left_t, 0.0))
		_show(true)
		if left_t <= 0.0:
			failed = true
			_show(false)
			mission.finish(false, tr("Einsatzgebiet verlassen"))
	else:
		_show(false)


func _show(on: bool) -> void:
	if _label and _label.visible != on:
		_label.visible = on
