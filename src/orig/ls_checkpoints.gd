class_name LsCheckpoints
extends RefCounted
## Checkpoint-/Wegpunktnetz der Originalskripte (CheckpointJoin/CheckpointSeparate, AP-5/B-033).
## Original [B] (GAP_REA §C): Netz = Spielobjekt 0x698500 +0x54. Join 0x51F490 → 0x51F280: beide Namen → IDs (0x51E1A0),
## gültig → Kante (u16 A, u16 B) an die Kantenliste +0x30 anhängen. Separate 0x51F5A0 → 0x51F4D0: passende Kante in
## beliebiger Richtung entfernen (letzte nach vorn). Die Liste wird mit dem Spielstand gesichert (Chunk 8000 → 0x523F30).
## Nachbau: Namen = Wegpunkte aus scene.json (LsRuntime.waypoints, Großschreibung), Kanten ungerichtet.
## Grundkanten (B-033): das Netz Welt+0x54 ist Abschnitt 1 von check2.bin (Lader 0x6D4323 → 0x523C00) [B], dekodiert von
## tools/fmt_drive.py („walk“ in drive.json) → `load_base`; `route_nodes` sucht im Gesamtnetz (Grund- + Skriptkanten).
## Join-Prüfung 0x5248C0 [B, b033_rest]: 0x51F280 ruft sie für B→A und danach A→B auf (beide müssen gelingen, sonst keine
## Listenkante; ein gelungener erster Teil bleibt im Knoten stehen). Je Knoten (Flags +0x14): 0x400 und 0x40 gesetzt,
## 0x80 frei (= nur EINE Skriptkante je Knoten), noch keine Verbindung zum anderen Knoten (0x5247A0), Anzahl ≠ 32, der
## Platz hinter den Grundkanten leer (Ziel 0xFFFF/Wert 0; den reserviert die Datei bei Flag 0x40), A ≠ B, gewichteter Abstand
## (1 − (w_A + w_B)/1024)·|AB| (0x5247E0, w = Byte +0x12) zwischen 0,001 und 250. Kantenwert = Abstand × 256. Danach Anzahl+1
## und 0x80 setzen. Separate 0x5249A0 löscht die Kante nur, wenn sie der letzte Platz ist, und gibt 0x80 frei.
## Nachbau: mit geladenem Grundnetz (`strict`) gelten Flag 0x40, ein Skriptplatz je Knoten, keine Grundverbindung und
## Abstand ≤ 250 m. Nicht nachgebildet: Byte +0x12 (fmt_drive exportiert es nicht, Gewicht = 0 [P]) und Bit 0x400 (wird erst
## im Speicher gesetzt, Quelle nicht gefunden; als gesetzt angenommen [P]). Ohne Grundnetz: nur „beide Namen bekannt, A ≠ B“.
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
	if strict and not base_pos.is_empty():
		var ia := node_of(ka)
		var ib := node_of(kb)
		if ia >= 0 and ib >= 0:
			# 0x51F280: erst B (Ziel A), dann A (Ziel B)
			if not _slot_ok(ib, ia):
				return false
			script_slot[ib] = true
			if not _slot_ok(ia, ib):
				return false   # B behält den Platz wie im Original (halbe Kante, keine Listenkante)
			script_slot[ia] = true
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
			script_slot.erase(node_of(ka))   # 0x5249A0: Platz leeren, 0x80 frei
			script_slot.erase(node_of(kb))
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
	script_slot.clear()


## 0x5248C0 für Knoten `n` mit Ziel `other` (siehe Dateikopf)
func _slot_ok(n: int, other: int) -> bool:
	if n == other or script_slot.has(n):
		return false
	if n < base_flags.size() and (int(base_flags[n]) & 0x40) == 0:
		return false
	if other in base_adj[n] or (int(base_flags[n]) & 0x3F) >= 0x20:
		return false
	var d: float = (base_pos[n] as Vector3).distance_to(base_pos[other])
	return d >= 0.001 and d <= JOIN_MAX_DIST


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
	script_slot.clear()
	for x in d.get("edges", []):
		if x is Array and x.size() >= 2:
			edges.append([_key(x[0]), _key(x[1])])
			for nm in [x[0], x[1]]:
				if node_of(nm) >= 0:
					script_slot[node_of(nm)] = true


# --- B-033: Grundkanten (check2.bin Abschnitt 1 = Fußwegenetz Welt+0x54, fmt_drive.py → drive.json „walk“) [B] -------
var base_pos: Array = []       ## Knoten -> Vector3 (Godot-Koordinaten)
var base_adj: Array = []       ## Knoten -> Array[int] (Verbindungen laut Datei, fast immer beidseitig)
var name_node := {}            ## NAME (groß) -> Knoten
var base_flags: Array = []     ## Knoten -> Flags +0x14 aus der Datei (0x40 = Skriptplatz reserviert)
var script_slot := {}          ## Knoten -> true, wenn sein Skriptplatz belegt ist (Bit 0x80)
var strict := true             ## Join-Prüfung 0x5248C0 anwenden, sobald das Grundnetz geladen ist
const JOIN_MAX_DIST := 250.0   ## 0x8109CC [B]
var _astar: AStar3D


func load_base(walk) -> void:
	base_pos.clear()
	base_adj.clear()
	base_flags.clear()
	name_node.clear()
	if not (walk is Dictionary):
		return
	for n in walk.get("nodes", []):
		var p: Array = n.get("pos", [0, 0, 0])
		base_pos.append(Vector3(p[0], p[1], p[2]))
		base_flags.append(int(n.get("flags", 0x40)))
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
	script_slot.clear()
	for e in edges:
		for x in e:
			if node_of(x) >= 0:
				script_slot[node_of(x)] = true


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