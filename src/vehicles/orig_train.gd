class_name OrigTrain
extends Node
## Zug (Akteurtyp 14 „Train“, CZECH1 „lokotka“): Lok und Wagen wie im Original (docs/re_notes_ai.md §5, hd2.exe):
## Parameter je Fahrzeug (Chunk 0x0A Frame-Name, 0x14 f32 Länge, 0x1E f32 Abstand; Lok = erster Eintrag) [B Daten,
## Loader 0x5BD1A0/0x5BE360]; Zuglänge = Σ(Länge + Abstand) (0x5BD490), Wagen werden beim Start dem Gleis entlang
## hinter die Lok gesetzt und folgen ihr (0x5BD820: Wagenrahmen, Räder WHL/WHR, Drehgestelle THL/THR) [B Ablauf].
## Die Lok fährt über das Originalskript (FRM_WatchTrack „vlak1“, orig_extras.gd). Nachbau: die Wagen laufen auf der
## von der Lok gefahrenen Bahn im Abstand ihrer Ausgangslage im Level (Wagenabstände der Leveldaten) [P – Original
## rechnet Achsen auf dem Gleis]. Vor dem Start bleibt der Zug wie im Level geparkt.

var loco: Node3D
var cars: Array = []              ## {node, dist (Bogenlänge hinter der Lok), fwd0 (Weltvorwärts beim Start), basis0, dy}
var params: Array = []            ## [{name, length, gap}] aus den Akteurparametern
var _hist: Array = []             ## Lagen der Lok (Vector3), älteste zuerst
var _last := Vector3.INF
var _back_local := Vector3.BACK   ## Lok-lokale Richtung nach hinten (zu den Wagen)
var _total := 0.0


## Akteurparameter (Bytes): Folge von {u16 Chunk, u32 Länge inkl. 6-Byte-Kopf, Daten}
static func parse_params(raw: PackedByteArray) -> Array:
	var out: Array = []
	var p := 0
	var cur := {}
	while p + 6 <= raw.size():
		var id := raw.decode_u16(p)
		var ln := raw.decode_u32(p + 2)
		if ln < 6 or p + ln > raw.size():
			break
		var data := raw.slice(p + 6, p + ln)
		match id:
			0x0A:
				if not cur.is_empty():
					out.append(cur)
				cur = {"name": data.get_string_from_ascii(), "length": 10.0, "gap": 3.0}   # Standard +0x38 = 10, +0x3C = 3 [B 0x5BD221]
			0x14:
				if not cur.is_empty() and data.size() >= 4:
					cur["length"] = data.decode_float(0)
			0x1E:
				if not cur.is_empty() and data.size() >= 4:
					cur["gap"] = data.decode_float(0)
		p += ln
	if not cur.is_empty():
		out.append(cur)
	return out


func setup(l: Node3D, find_frame: Callable, raw: PackedByteArray) -> void:
	loco = l
	params = parse_params(raw)
	var prev_pos := loco.global_position
	var acc := 0.0
	for i in range(1, params.size()):
		var n: Node3D = find_frame.call(String(params[i]["name"]))
		if n == null:
			continue
		var d := prev_pos.distance_to(n.global_position)
		acc += d
		var fwd0 := (prev_pos - n.global_position)
		fwd0.y = 0.0
		cars.append({"node": n, "dist": acc, "fwd0": fwd0.normalized() if fwd0.length() > 0.01 else Vector3.FORWARD,
			"basis0": n.global_basis, "dy": n.global_position.y - loco.global_position.y})
		prev_pos = n.global_position
	for p in params:
		_total += float(p["length"]) + float(p["gap"])
	if not cars.is_empty():
		var back := (cars[0]["node"] as Node3D).global_position - loco.global_position
		back.y = 0.0
		_back_local = loco.global_basis.inverse() * back.normalized()
	_last = loco.global_position


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(loco) or cars.is_empty():
		return
	var p := loco.global_position
	var moved := p.distance_to(_last)
	if moved < 0.005:
		return
	if moved > 8.0 or _hist.is_empty():
		_seed(p)            # Fahrtbeginn (Lok an den Spuranfang gesetzt): Wagen gerade hinter die Lok
	elif p.distance_to(_hist[_hist.size() - 1]) > 0.25:
		_hist.append(p)
	_last = p
	_trim()
	_place()


func _seed(p: Vector3) -> void:
	_hist.clear()
	var back := loco.global_basis * _back_local
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var far: float = float(cars[cars.size() - 1]["dist"]) + 20.0
	var s := far
	while s > 0.0:
		_hist.append(p + back * s)
		s -= 1.0
	_hist.append(p)


func _trim() -> void:
	var need: float = float(cars[cars.size() - 1]["dist"]) + 25.0
	var acc := 0.0
	for i in range(_hist.size() - 1, 0, -1):
		acc += (_hist[i] as Vector3).distance_to(_hist[i - 1])
		if acc > need and i > 1:
			_hist = _hist.slice(i - 1)
			return


## Punkt und Fahrtrichtung in Bogenlänge s hinter der Lok (auf der gefahrenen Bahn)
func _at(s: float) -> Array:
	var acc := 0.0
	for i in range(_hist.size() - 1, 0, -1):
		var a: Vector3 = _hist[i]
		var b: Vector3 = _hist[i - 1]
		var seg := a.distance_to(b)
		if acc + seg >= s and seg > 0.0001:
			var t := (s - acc) / seg
			var dir := a - b
			dir.y = 0.0
			return [a.lerp(b, t), dir.normalized() if dir.length() > 0.0001 else Vector3.FORWARD]
		acc += seg
	var last: Vector3 = _hist[0]
	return [last, Vector3.FORWARD]


func _place() -> void:
	for c in cars:
		var r := _at(float(c["dist"]))
		var n := c["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var fwd: Vector3 = r[1]
		var q := Quaternion(c["fwd0"] as Vector3, fwd) if (c["fwd0"] as Vector3).dot(fwd) > -0.999 else Quaternion(Vector3.UP, PI)
		n.global_transform = Transform3D(Basis(q) * (c["basis0"] as Basis), (r[0] as Vector3) + Vector3.UP * float(c["dy"]))
