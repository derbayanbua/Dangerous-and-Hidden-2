class_name LsCheckpoints
extends RefCounted
## Checkpoint-/Wegpunktnetz der Originalskripte (CheckpointJoin/CheckpointSeparate, AP-5/B-033).
## Original [B] (GAP_REA §C): Netz = Spielobjekt 0x698500 +0x54. Join 0x51F490 → 0x51F280: beide Namen → IDs (0x51E1A0),
## gültig → Kante (u16 A, u16 B) an die Kantenliste +0x30 anhängen. Separate 0x51F5A0 → 0x51F4D0: passende Kante in
## beliebiger Richtung entfernen (letzte nach vorn). Die Liste wird mit dem Spielstand gesichert (Chunk 8000 → 0x523F30).
## Nachbau: Namen = Wegpunkte aus scene.json (LsRuntime.waypoints, Großschreibung), Kanten ungerichtet.
## Grundkanten (B-033): das Netz Welt+0x54 ist Abschnitt 1 von check2.bin (Lader 0x6D4323 → 0x523C00) [B], dekodiert von
## tools/fmt_drive.py („walk“ in drive.json) → `load_base`; `route_nodes` sucht im Gesamtnetz (Grund- + Skriptkanten).
## Prüfungen 0x5248C0 nicht dekodiert [P]: hier nur „beide Namen bekannt, A ≠ B“.
## Nutzung für Führerwege: `path(a, b)` (Breitensuche über die Kanten), `neighbors(a)`, `has_edge(a, b)`.

var edges: Array = []          ## [[A, B], …] in Einfügereihenfolge (wie Original-Kantenliste)
var known: Callable            ## Name (groß) -> bool; leer = alle Namen zulassen
var log_changes := false


func _init(known_names: Callable = Callable()) -> void:
	known = known_names


static func _key(n) -> String:
	return String(n).strip_edges().to_upper()


func _valid(a: String) -> bool:
	return a != "" and (not known.is_valid() or bool(known.call(a)))


## CheckpointJoin(A, B): Kante anhängen. Rückgabe true, wenn angelegt (doppelte Kanten legt das Original ebenfalls an [P];
## hier wird eine bestehende Kante nicht verdoppelt, damit Separate sie sicher entfernt).
func join(a, b) -> bool:
	var ka := _key(a)
	var kb := _key(b)
	if ka == kb or not _valid(ka) or not _valid(kb):
		return false
	if has_edge(ka, kb):
		return false
	edges.append([ka, kb])
	if log_changes:
		print("Checkpoint: Kante %s – %s" % [ka, kb])
	return true


## CheckpointSeparate(A, B): passende Kante (beliebige Richtung) entfernen; letzte Kante rückt an ihre Stelle (0x51F4D0).
func separate(a, b) -> bool:
	var ka := _key(a)
	var kb := _key(b)
	for i in edges.size():
		var e: Array = edges[i]
		if (e[0] == ka and e[1] == kb) or (e[0] == kb and e[1] == ka):
			edges[i] = edges[edges.size() - 1]
			edges.pop_back()
			if log_changes:
				print("Checkpoint: Kante %s – %s getrennt" % [ka, kb])
			return true
	return false


func has_edge(a, b) -> bool:
	var ka := _key(a)
	var kb := _key(b)
	for e in edges:
		if (e[0] == ka and e[1] == kb) or (e[0] == kb and e[1] == ka):
			return true
	return false


func neighbors(a) -> Array:
	var ka := _key(a)
	var out := []
	for e in edges:
		if e[0] == ka:
			out.append(e[1])
		elif e[1] == ka:
			out.append(e[0])
	return out


## Kürzeste Kantenfolge (Anzahl Kanten) von A nach B, inklusive A und B; [] ohne Verbindung.
func path(a, b) -> Array:
	var ka := _key(a)
	var kb := _key(b)
	if ka == kb:
		return [ka]
	var prev := {ka: ""}
	var queue := [ka]
	while not queue.is_empty():
		var c: String = queue.pop_front()
		for n in neighbors(c):
			if prev.has(n):
				continue
			prev[n] = c
			if n == kb:
				var out := [kb]
				var p: String = c
				while p != "":
					out.push_front(p)
					p = prev[p]
				return out
			queue.append(n)
	return []


func clear() -> void:
	edges.clear()


## Spielstand (AP-1 ruft das über LsRuntime.save_state/load_state auf)
func save_state() -> Dictionary:
	var e := []
	for x in edges:
		e.append([x[0], x[1]])
	return {"v": 1, "edges": e}


func load_state(d) -> void:
	edges.clear()
	if not (d is Dictionary):
		return
	for x in d.get("edges", []):
		if x is Array and x.size() >= 2:
			edges.append([_key(x[0]), _key(x[1])])


# --- B-033: Grundkanten (check2.bin Abschnitt 1 = Fußwegenetz Welt+0x54, fmt_drive.py → drive.json „walk“) [B] -------
var base_pos: Array = []       ## Knoten -> Vector3 (Godot-Koordinaten)
var base_adj: Array = []       ## Knoten -> Array[int] (Verbindungen laut Datei, fast immer beidseitig)
var name_node := {}            ## NAME (groß) -> Knoten
var _astar: AStar3D


func load_base(walk) -> void:
	base_pos.clear()
	base_adj.clear()
	name_node.clear()
	if not (walk is Dictionary):
		return
	for n in walk.get("nodes", []):
		var p: Array = n.get("pos", [0, 0, 0])
		base_pos.append(Vector3(p[0], p[1], p[2]))
		var adj: Array = []
		for l in n.get("links", []):
			adj.append(int(l[0]))
		base_adj.append(adj)
	_astar = AStar3D.new()
	for i in base_pos.size():
		_astar.add_point(i, base_pos[i])
	for i in base_adj.size():
		for j in base_adj[i]:
			if j >= 0 and j < base_pos.size() and j != i:
				_astar.connect_points(i, j, false)
	for nm in walk.get("names", []):
		var k := _key(nm.get("name", ""))
		if k != "" and not name_node.has(k) and int(nm.get("node", -1)) < base_pos.size():
			name_node[k] = int(nm.get("node", -1))   # erster Treffer wie 0x51E1A0


func node_of(a) -> int:
	return int(name_node.get(_key(a), -1))


func nearest_node(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius * radius
	for i in base_pos.size():
		var d: float = (base_pos[i] as Vector3).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best


## Kürzester Weg (Länge) im Gesamtnetz aus Grundkanten und Skriptkanten (CheckpointJoin über die Namen), AStar3D.
## Rückgabe {"nodes": [Knoten…] inkl. Start/Ziel, "script_edge": true wenn eine Skriptkante benutzt wird}; leer = keine Verbindung.
func route_nodes(a: int, b: int) -> Dictionary:
	var n := base_pos.size()
	if a < 0 or b < 0 or a >= n or b >= n or _astar == null:
		return {}
	var added: Array = []
	var script_pairs := {}
	for e in edges:
		var ia := node_of(e[0])
		var ib := node_of(e[1])
		if ia < 0 or ib < 0 or ia == ib:
			continue
		script_pairs[Vector2i(mini(ia, ib), maxi(ia, ib))] = true
		if not _astar.are_points_connected(ia, ib):
			_astar.connect_points(ia, ib)
			added.append([ia, ib])
	var ids := _astar.get_id_path(a, b)
	for x in added:
		_astar.disconnect_points(x[0], x[1])
	if ids.is_empty():
		return {}
	var out: Array = []
	var used := false
	for i in ids.size():
		out.append(int(ids[i]))
		if i > 0:
			var k := Vector2i(mini(ids[i - 1], ids[i]), maxi(ids[i - 1], ids[i]))
			if script_pairs.has(k) and not (int(ids[i]) in base_adj[ids[i - 1]]) and not (int(ids[i - 1]) in base_adj[ids[i]]):
				used = true
	return {"nodes": out, "script_edge": used}