class_name VehicleDamage
extends RefCounted
## Schadensmodell eines Originalfahrzeugs wie im Original (docs/re_notes_ai.md §4, hd2.exe):
## Jedes Fahrzeug lädt zusätzlich MODELS\DM<Modell>.4ds (0x4E09D0, String „DM%s“ 0x83BE6C; Export
## tools/fmt_vehicle_dm.py → orig_cache/<m>/models/dm_<modell>.glb). Darin:
##   D_ZONEnn {HP<n>, matid<n>}  Trefferzonen mit eigener Gesundheit (zotti) und Material (hdmaterials.def)
##   EXPL_Dnn {EXPL<s>}          Explosionspunkte: Verzögerung bis zur Zerstörung (s) bei Geschosstreffern
##   SEATnn                      Sitze (Insassen-Treffer beim Durchschlagen einer Zone)
##   HOR*/VERT*                  folgen den gleichnamigen Frames des Fahrzeugmodells (Turm/Rohr, 0x4E1DC0)
## Schaden (Car vtable +0xD4 = 0x4DBA10 → 0x4E1A20), Art 1 Geschoss, 2/4 Explosion, 7 Raketen-/Granat-Direkttreffer:
##   Zone: Art 2 = Zone mit dem nächsten Frame-Ursprung zum Explosionsort; sonst Strahltest Schütze → Treffpunkt
##   gegen die Zonengeometrie (keine Zone getroffen → kein Schaden) [B].
##   Rest = Schaden − Panzerung(matid) (hdmaterials.def +0x28); nur Rest > 0 wirkt: HP = ⌊HP − Rest⌋ [B 0x4E1D07].
##   HP < 0 → HP 0, Insassen mit Sitz-Frame im Schadensmodell erhalten den Rest (Art 1, 0x4E18C0); Art 1: nächster
##   unbenutzter EXPL_D mit EXPL ≠ 0 startet einen Zeitzünder (min. Restzeit, 0x4E1990), sonst sofort zerstört
##   (0x4E1FE0 → 0x4DBF00: Insassen tot, Explosion, Wrack) [B].
## Einheiten: Zonen-HP/Panzerung in zotti; der Nachbau rechnet Schaden in zotti/10 (WeaponDB) → ×10.

const ZOTTI := 10.0

var vehicle: Node3D               ## Vehicle (Wurzel des Fahrzeugs)
var root: Node3D                  ## Schadensmodell (unsichtbar, Kind des Fahrzeugmodells → gleiche Lage)
var zones: Array = []             ## {node, faces (lokal), hp, hp0, matid, name}
var expls: Array = []             ## {node, delay_ms, used}
var seat_frames := {}             ## Sitznummer → Node3D
var follow := []                  ## [DM-Frame, Frame des Fahrzeugmodells] (HOR*/VERT*)
var timer_ms := 0                 ## Zeitzünder (0 = aus), Original Schadensmodell +0xC
var destroyed := false

static var _armor := {}           ## matid → Panzerung (zotti), hdmaterials.def +0x28 (orig_cache/sounds.json)


static func armor_of(matid: int) -> float:
	if _armor.is_empty():
		var d = LsRuntime._read_json(OrigLevel.cache_root() + "/sounds.json")
		if typeof(d) == TYPE_DICTIONARY:
			for m in d.get("materials", []):
				var pen: Array = m.get("penetration_?", [0, 0])
				_armor[int(m.get("index", -1))] = float(pen[0]) if pen.size() > 0 else 0.0
		if _armor.is_empty():
			_armor[-1] = 0.0
	return float(_armor.get(matid, _armor.get(11, 0.0)))     # ohne matid: Material 11 (0x4DBEE0) [B]


## Schadensmodell laden; false, wenn es fehlt (dann bleibt das bisherige Strukturpunkte-Modell)
func setup_from(v: Node3D, visual: Node3D, path: String) -> bool:
	vehicle = v
	if visual == null or not FileAccess.file_exists(path):
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.base_path = path.get_base_dir()
	if doc.append_from_file(path, state) != OK:
		return false
	root = doc.generate_scene(state) as Node3D
	if root == null:
		return false
	root.name = "DamageModel"
	root.visible = false
	visual.add_child(root)
	var nodes: Array = state.json.get("nodes", [])
	for i in nodes.size():
		var nd: Dictionary = nodes[i]
		var nm := String(nd.get("name", "")).to_upper()
		var ex = nd.get("extras", {})
		var params := String(ex.get("params", "")).to_upper() if typeof(ex) == TYPE_DICTIONARY else ""
		# Knoten über den Namen im erzeugten Baum (get_scene_node liefert für Meshes freigegebene Importknoten)
		var n: Node = root.find_child(String(nd.get("name", "")), true, false)
		if n == null:
			continue
		if nm.begins_with("D_ZONE"):
			var faces := PackedVector3Array()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				faces = (n as MeshInstance3D).mesh.get_faces()
			var hp := _param(params, "HP")
			var mat := _param(params, "MATID")
			zones.append({"node": n, "faces": faces, "hp": hp, "hp0": hp, "matid": mat, "name": nm})
		elif nm.begins_with("EXPL_D"):
			# EXPL fehlt (z. B. DMla_sherman EXPL_D02 „HP1200,matid15“): Originalwert −1 s → sofort [B 0x4E19C0]
			var e := _param(params, "EXPL")
			expls.append({"node": n, "delay_ms": e * 1000, "used": false})
		elif nm.begins_with("SEAT") and nm.length() == 6 and nm.substr(4).is_valid_int():
			seat_frames[int(nm.substr(4))] = n
		elif nm.begins_with("HOR") or nm.begins_with("VERT"):
			var src := _find_named(visual, String(nd.get("name", "")), root)
			if src:
				follow.append([n, src])
	return not zones.is_empty()


## Zahl hinter einem Schlüssel in den Frame-Parametern („HP5000,matid16“); fehlt er: −1 (Original 0x4E19C0)
static func _param(params: String, key: String) -> int:
	var p := params.find(key)
	while p >= 0:
		var q := p + key.length()
		var s := ""
		while q < params.length() and (params[q].is_valid_int() or (s == "" and params[q] == "-")):
			s += params[q]
			q += 1
		if s.is_valid_int() and (p == 0 or not params[p - 1].is_valid_identifier()):
			return int(s)
		p = params.find(key, p + 1)
	return -1


static func _find_named(n: Node, nm: String, skip: Node) -> Node3D:
	if n == skip:
		return null
	if String(n.name).to_upper() == nm.to_upper() and n is Node3D:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm, skip)
		if r:
			return r
	return null


## Turm/Rohr: Frames HOR*/VERT* des Schadensmodells folgen dem Fahrzeugmodell (Original 0x4E1DC0 kopiert die Lage)
func sync() -> void:
	for f in follow:
		if is_instance_valid(f[0]) and is_instance_valid(f[1]):
			(f[0] as Node3D).transform = (f[1] as Node3D).transform


## Zone für einen Treffer: Art 2 = nächster Frame-Ursprung, sonst Strahl from → to gegen die Zonendreiecke
func pick_zone(kind: int, at: Vector3, from: Vector3) -> int:
	sync()
	if kind == 2:
		var best := -1
		var bd := 1e12
		for i in zones.size():
			var d := (zones[i]["node"] as Node3D).global_position.distance_squared_to(at)
			if d <= bd:            # Gleichstand: spätere Zone (Original vergleicht mit ≤)
				bd = d
				best = i
		return best
	var dir := at - from
	if dir.length() < 0.001:
		return -1
	var best_i := -1
	var best_t := INF
	for i in zones.size():
		var nd := zones[i]["node"] as Node3D
		var f: PackedVector3Array = zones[i]["faces"]
		if f.is_empty():
			continue
		var x := nd.global_transform
		for k in range(0, f.size() - 2, 3):
			var hit = Geometry3D.segment_intersects_triangle(from, from + dir * 1.5, x * f[k], x * f[k + 1], x * f[k + 2])
			if hit != null:
				var t := from.distance_squared_to(hit)
				if t < best_t:
					best_t = t
					best_i = i
	return best_i


## Schaden in zotti; Rückgabe: Zone (−1 = keine). by = Verursacher, from = Ursprung des Strahls (Schütze)
func damage(kind: int, amount: float, at: Vector3, from: Vector3, by: Node) -> int:
	if destroyed:
		return -1
	var zi := pick_zone(kind, at, from)
	if zi < 0:
		return -1
	var z: Dictionary = zones[zi]
	var rest := amount - armor_of(int(z["matid"]))
	if rest <= 0.0:
		return zi
	z["hp"] = int(floor(float(z["hp"]) - rest))
	if int(z["hp"]) >= 0:
		return zi
	z["hp"] = 0
	_hit_occupants(at, rest, by)
	if kind == 1:
		var ei := _nearest_expl(at)
		if ei < 0 or bool(expls[ei]["used"]):
			return zi
		var ms := int(expls[ei]["delay_ms"])
		if ms != 0:
			if timer_ms == 0 or ms < timer_ms:
				timer_ms = ms
			expls[ei]["used"] = true
			return zi
	_destroy(by)
	return zi


func _nearest_expl(at: Vector3) -> int:
	var best := -1
	var bd := 1e12
	for i in expls.size():
		var d := (expls[i]["node"] as Node3D).global_position.distance_squared_to(at)
		if d <= bd:
			bd = d
			best = i
	return best


## Zone durchschlagen: Insassen auf Sitzen mit Frame im Schadensmodell erhalten den Rest als Geschosstreffer, sofern
## der Strahl vom Treffpunkt den Sitz erreicht (Original 0x4E18C0 prüft gegen die Schadensmodell-Geometrie) [B];
## Nachbau ohne Verdeckungsprüfung innerhalb des Schadensmodells [P]
func _hit_occupants(at: Vector3, rest: float, by: Node) -> void:
	var occ: Array = vehicle.get("occupants")
	for idx in seat_frames:
		if idx < occ.size() and is_instance_valid(occ[idx]):
			var s := occ[idx] as Soldier
			if s and s.alive:
				s.apply_hit(rest / ZOTTI, &"torso", by, ((seat_frames[idx] as Node3D).global_position - at).normalized())


func _destroy(by: Node) -> void:
	if destroyed:
		return
	destroyed = true
	timer_ms = 0
	if vehicle.has_method("explode"):
		vehicle.explode(by)


## Zeitzünder nach Geschosstreffer (Original 0x4E1990, je Bild −dt ms)
func tick(delta: float, by: Node) -> void:
	if timer_ms == 0 or destroyed:
		return
	timer_ms -= int(round(delta * 1000.0))
	if timer_ms < 1:
		timer_ms = 0
		_destroy(by)


## Anteil der verbleibenden Zonen-Gesundheit (Anzeige/Tests)
func integrity() -> float:
	var a := 0.0
	var b := 0.0
	for z in zones:
		a += maxf(float(z["hp"]), 0.0)
		b += maxf(float(z["hp0"]), 1.0)
	return a / b if b > 0.0 else 1.0


func serialize() -> Dictionary:
	var hp := []
	for z in zones:
		hp.append(int(z["hp"]))
	var used := []
	for e in expls:
		used.append(bool(e["used"]))
	return {"hp": hp, "used": used, "timer": timer_ms}


func deserialize(d: Dictionary) -> void:
	var hp: Array = d.get("hp", [])
	for i in mini(hp.size(), zones.size()):
		zones[i]["hp"] = int(hp[i])
	var used: Array = d.get("used", [])
	for i in mini(used.size(), expls.size()):
		expls[i]["used"] = bool(used[i])
	timer_ms = int(d.get("timer", 0))
