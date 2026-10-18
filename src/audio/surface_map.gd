class_name SurfaceMap
extends RefCounted
## Untergrund-Material der Original-Kollisionsflächen (orig_cache/<mission>/surface.bin, tools/fmt_klz.py aus
## MISSIONS\<m>\tree.klz). Jedes Dreieck trägt die Materialzeile aus TABLES\hdmaterials.def; daraus folgen
## Schrittklang (+0x20, IngameSounds Kat. 0) und Einschlagklang (+0x30, Kat. 4) wie im Original
## (hd2.exe 0x75D5D8/0x75C940; docs/re_notes_audio.md §4).

const CELL := 4.0

var tris := PackedVector3Array()      ## 3 Punkte je Dreieck (Weltkoordinaten Godot)
var normals := PackedVector3Array()
var mats := PackedByteArray()
var grid := {}                        ## Vector2i (Zelle CELL m in x/z) -> PackedInt32Array Dreiecksindizes
var count := 0


static func load_file(path: String) -> SurfaceMap:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var b := f.get_buffer(f.get_length())
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "HDSF":
		return null
	var n := b.decode_u32(8)
	if b.size() < 12 + n * 40:
		return null
	var m := SurfaceMap.new()
	m.count = n
	m.tris.resize(n * 3)
	m.normals.resize(n)
	m.mats.resize(n)
	var fl := b.slice(12).to_float32_array()
	var tmp := {}
	for k in n:
		var o := k * 10
		m.mats[k] = b[12 + k * 40]
		var a := Vector3(fl[o + 1], fl[o + 2], fl[o + 3])
		var c := Vector3(fl[o + 4], fl[o + 5], fl[o + 6])
		var d := Vector3(fl[o + 7], fl[o + 8], fl[o + 9])
		m.tris[k * 3] = a
		m.tris[k * 3 + 1] = c
		m.tris[k * 3 + 2] = d
		var nn := (c - a).cross(d - a)
		m.normals[k] = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP
		var x0 := int(floor(minf(a.x, minf(c.x, d.x)) / CELL))
		var x1 := int(floor(maxf(a.x, maxf(c.x, d.x)) / CELL))
		var z0 := int(floor(minf(a.z, minf(c.z, d.z)) / CELL))
		var z1 := int(floor(maxf(a.z, maxf(c.z, d.z)) / CELL))
		if (x1 - x0) * (z1 - z0) > 4096:
			continue      # entartet riesig (Randflächen): ignorieren
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var key := Vector2i(x, z)
				if not tmp.has(key):
					tmp[key] = []
				tmp[key].append(k)
	for key in tmp:
		m.grid[key] = PackedInt32Array(tmp[key])
	return m


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


## Material des Bodens unter/an einer Fußposition (Dreieck mit |n.y| > 0,3, dessen Fläche den Punkt in x/z
## enthält und dessen Höhe zwischen pos.y − down und pos.y + up liegt; das höchste gewinnt). −1 = keins.
func floor_material(pos: Vector3, up := 0.6, down := 1.2) -> int:
	var lst: PackedInt32Array = grid.get(_cell(pos), PackedInt32Array())
	var best := -1
	var best_y := -INF
	for k in lst:
		var n := normals[k]
		if absf(n.y) < 0.3:
			continue
		var a := tris[k * 3]
		var b := tris[k * 3 + 1]
		var c := tris[k * 3 + 2]
		if not _inside_xz(pos.x, pos.z, a, b, c):
			continue
		var y := a.y - (n.x * (pos.x - a.x) + n.z * (pos.z - a.z)) / n.y
		if y > pos.y + up or y < pos.y - down:
			continue
		if y > best_y:
			best_y = y
			best = k
	return int(mats[best]) if best >= 0 else -1


## Material der Fläche an einem Trefferpunkt (Abstand zur Ebene < 0,15 m, Punkt im Dreieck). −1 = keins.
func surface_material(pos: Vector3) -> int:
	var lst: PackedInt32Array = grid.get(_cell(pos), PackedInt32Array())
	var best := -1
	var best_d := 0.15
	for k in lst:
		var n := normals[k]
		var a := tris[k * 3]
		var d := absf(n.dot(pos - a))
		if d >= best_d:
			continue
		var q := pos - n * n.dot(pos - a)
		if _inside_3d(q, a, tris[k * 3 + 1], tris[k * 3 + 2], n):
			best_d = d
			best = k
	return int(mats[best]) if best >= 0 else -1


static func _inside_xz(px: float, pz: float, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d1 := (px - b.x) * (a.z - b.z) - (a.x - b.x) * (pz - b.z)
	var d2 := (px - c.x) * (b.z - c.z) - (b.x - c.x) * (pz - c.z)
	var d3 := (px - a.x) * (c.z - a.z) - (c.x - a.x) * (pz - a.z)
	var neg := d1 < -1e-6 or d2 < -1e-6 or d3 < -1e-6
	var pos := d1 > 1e-6 or d2 > 1e-6 or d3 > 1e-6
	return not (neg and pos)


static func _inside_3d(p: Vector3, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> bool:
	var e := 0.02
	return n.dot((b - a).cross(p - a)) >= -e and n.dot((c - b).cross(p - b)) >= -e \
		and n.dot((a - c).cross(p - c)) >= -e
