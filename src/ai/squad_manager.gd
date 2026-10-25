class_name SquadManager
extends Node
## Verwaltet den Spielertrupp: Mitglieder, aktiven (gesteuerten) Soldaten,
## Formation und Befehle. Formationen wie im Original (B-019, docs/re_notes_commands.md §7):
## Platztabellen hd2.exe 0x8AB1D0 (je Typ 6 Plätze, Platz 0 = Anführer, Einheitsabstände; Initialisierung 0x596760 ff.,
## Kopie 0x5971E0, gesetzt von 0x597420), Maßstab = Abstandsstufe 0…7 × 0,75 + 1,5 m (0x4563F0, Start 3 → 3,75 m),
## neue Formation bei Truppbildung = Pfeil (0x5A91A0). Befehle 21/22/23 → Linie (Typ 0) / Kolonne (1) / Pfeil (3),
## 24/25 → Stufe −1/+1 (0x456020). Trennung: Zielpunkte < 1,2 m auseinander werden auf 1,2 m geschoben (0x598550),
## Platz an begehbaren Boden ≤ 5 m geheftet (0x59B7B0).

enum Formation { COLUMN, LINE, WEDGE, QUAD }
const FORMATION_NAMES := ["Kolonne", "Linie", "Pfeil", "Block 2×3"]
## Remake-Formation -> Original-Formationstyp (0 Linie, 1 Kolonne, 2 Quad2X3, 3 Pfeil)
const ORIG_TYPE := {Formation.COLUMN: 1, Formation.LINE: 0, Formation.WEDGE: 3, Formation.QUAD: 2}
## Original-Plätze je Typ (LS3D: x rechts, z vorn; Einheit = Formationsmaßstab) [B 0x596760]
const ORIG_SLOTS := {
	0: [Vector2(0, 0), Vector2(-1, 0), Vector2(-2, 0), Vector2(-3, 0), Vector2(-4, 0), Vector2(-5, 0)],
	1: [Vector2(0, 0), Vector2(0, -1), Vector2(0, -2), Vector2(0, -3), Vector2(0, -4), Vector2(0, -5)],
	2: [Vector2(0, 0), Vector2(1, 0), Vector2(0, -1), Vector2(1, -1), Vector2(0, -2), Vector2(1, -2)],
	3: [Vector2(0, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(-2, -2), Vector2(-1, -2.5), Vector2(1, -2.5)],
}
## Blickrichtung je Platz (nur Pfeil weicht ab; sonst geradeaus) [B]
const ORIG_DIRS := {3: [Vector2(0, 1), Vector2(-0.5, 1), Vector2(0.5, 1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 1)]}
const SEPARATION := 1.2          ## Mindestabstand der Zielpunkte [B 0x80FAD0]
const SNAP_RADIUS := 5.0         ## Platz an begehbaren Boden heften [B 0x59B7B0: 5,0]

signal active_changed(soldier: Soldier)
signal orders_changed

var members: Array[Soldier] = []
var active_index := 0
var formation: int = Formation.WEDGE
## Abstandsstufe 0…7 (Original Team +0x120, Start 3)
var spacing_level := 3
## Formationsmaßstab in m (= Stufe × 0,75 + 1,5); Setzen rundet auf die nächste Stufe
var spacing: float:
	get:
		return SPACING_MIN + SPACING_STEP * spacing_level
	set(v):
		spacing_level = clampi(int(round((v - SPACING_MIN) / SPACING_STEP)), 0, SPACING_LEVELS)


func add_member(s: Soldier) -> void:
	members.append(s)
	var brain := SquadBrain.new()
	brain.name = "SquadBrain"
	s.add_child(brain)
	brain.squad = self
	brain.setup(s)
	s.died.connect(_on_member_died)


func brain_of(s: Soldier) -> SquadBrain:
	return s.get_node_or_null("SquadBrain") as SquadBrain


func leader() -> Soldier:
	if active_index < members.size():
		return members[active_index]
	return null


func alive_members() -> Array[Soldier]:
	var r: Array[Soldier] = []
	for m in members:
		if m.alive:
			r.append(m)
	return r


func set_active(i: int) -> bool:
	if i < 0 or i >= members.size() or not members[i].alive:
		return false
	var prev := leader()
	if prev and prev != members[i]:
		prev.is_player_controlled = false
		prev.trigger = false
		prev.aiming = false
		prev.move_input = Vector3.ZERO
		# Original (hd2.exe 0x53BC50 → Team-vtable+0x34 = 0x4593E0): gibt der Spieler einen Soldaten ab, hören alle
		# KI-Kameraden, die ihm folgten, auf zu folgen (0x5377F0(0, leise bleibt)) und bleiben, wo sie sind; der
		# abgegebene Soldat selbst folgt niemandem [P]. Erst „Folgt mir“/„Neu sammeln“ bindet sie an den neuen Soldaten.
		var b := brain_of(prev)
		if b:
			b.clear_tasks()
			b.set_order(SquadBrain.Order.HOLD)
		for m in members:
			var mb := brain_of(m)
			if m != prev and m != members[i] and m.alive and mb and mb.order == SquadBrain.Order.FOLLOW:
				mb.set_order(SquadBrain.Order.HOLD, Vector3.ZERO, mb.quiet)
	active_index = i
	var cur := members[i]
	if cur in selected:
		selected.erase(cur)
		selection_changed.emit()
	cur.is_player_controlled = true
	var cb := brain_of(cur)
	if cb:
		cb.stop_moving()
		cb.cease_fire()
	active_changed.emit(cur)
	Events.active_soldier_changed.emit(cur)
	return true


## Einzelauswahl „SOLDAT 1–4 WÄHLEN“ (Original-Aktionen 35–38, T2862–2865, Options.bin „profile“: Tasten 1–4,
## Kategorie BEFEHLE). Markierte Kameraden zeigt die Truppleiste mit dem grauen Feld `select*` (gameinterface.4ds,
## 0x4B30E0). Wirkung [E]: Befehle „an alle“ (Ziffernblock 0, Direkttasten) gehen nur an die Markierten, solange
## jemand markiert ist; erneutes Drücken hebt die Markierung auf.
var selected: Array[Soldier] = []
signal selection_changed


func toggle_select(i: int) -> bool:
	if i < 0 or i >= members.size() or not members[i].alive or members[i] == leader():
		return false
	var s := members[i]
	if s in selected:
		selected.erase(s)
	else:
		selected.append(s)
	selection_changed.emit()
	return true


func is_selected(s: Soldier) -> bool:
	return s in selected


func clear_selection() -> void:
	if not selected.is_empty():
		selected.clear()
		selection_changed.emit()


## Empfänger eines Befehls „an alle“: markierte lebende Kameraden, sonst alle außer dem Anführer.
func order_recipients() -> Array[Soldier]:
	var lead := leader()
	var r: Array[Soldier] = []
	for m in alive_members():
		if m != lead and (selected.is_empty() or m in selected):
			r.append(m)
	return r


func cycle_active() -> void:
	for k in range(1, members.size() + 1):
		if set_active((active_index + k) % members.size()):
			return


## Folgende Kameraden in Platzreihenfolge (Platz 1…5; Original: Beitrittsreihenfolge, Anführer auf Platz 0).
func _followers(lead: Soldier) -> Array[Soldier]:
	var others: Array[Soldier] = []
	for m in members:
		if m != lead and m.alive:
			others.append(m)
	return others


## Rohplatz (ohne Trennung/Heften) für Platzindex i ≥ 1 relativ zum Anführer, Weltkoordinaten.
func _raw_slot(i: int, lead: Soldier) -> Vector3:
	var tbl: Array = ORIG_SLOTS[ORIG_TYPE.get(formation, 3)]
	var v: Vector2
	if i < tbl.size():
		v = tbl[i]
	else:
		# mehr als 6 (nur eigene Übungseinsätze): hinter dem letzten Platz fortsetzen [E]
		v = Vector2(tbl[tbl.size() - 1]) + (Vector2(tbl[tbl.size() - 1]) - Vector2(tbl[tbl.size() - 2])) * (i - tbl.size() + 1)
	# LS3D (x rechts, z vorn) -> Godot (x rechts, −z vorn)
	var off := Vector3(v.x, 0.0, -v.y) * spacing
	return lead.global_position + Basis(Vector3.UP, lead.look_yaw) * off


## Formationsplätze aller Folgenden (Weltkoordinaten), mit Trennung 1,2 m (0x598550) und Heften an den Boden
## (Navigationsnetz ≤ 5 m, 0x59B7B0). Schlüssel = Soldat.
func formation_slots(lead: Soldier) -> Dictionary:
	var out := {}
	var pts: Array[Vector3] = [lead.global_position]
	var map := _nav_map(lead)
	var i := 1
	for m in _followers(lead):
		var p := _raw_slot(i, lead)
		p = _snap(p, map)
		for q in pts:
			var d := p - q
			d.y = 0.0
			if d.length() < SEPARATION:
				var dir := d.normalized() if d.length() > 0.01 else (Basis(Vector3.UP, lead.look_yaw) * Vector3(1, 0, 0))
				p = Vector3(q.x, p.y, q.z) + dir * SEPARATION
				break
		pts.append(p)
		out[m] = p
		i += 1
	return out


func _nav_map(lead: Soldier) -> RID:
	var w := lead.get_world_3d() if lead.is_inside_tree() else null
	if w == null:
		return RID()
	var map := w.navigation_map
	if NavigationServer3D.map_get_iteration_id(map) <= 0:
		return RID()
	return map


func _snap(p: Vector3, map: RID) -> Vector3:
	if not map.is_valid():
		return p
	var cp := NavigationServer3D.map_get_closest_point(map, p)
	if cp.is_finite() and cp != Vector3.ZERO and cp.distance_to(p) <= SNAP_RADIUS:
		# Netzhöhe liegt eine Zellhöhe über dem Boden → Höhe nur bei anderem Stockwerk übernehmen
		return Vector3(cp.x, cp.y if absf(cp.y - p.y) > 1.5 else p.y, cp.z)
	return p


## Formationsplatz für Mitglied s relativ zum Anführer (Weltkoordinaten).
func formation_slot(s: Soldier, lead: Soldier) -> Vector3:
	var f := Engine.get_physics_frames() * 1000 + formation * 10 + spacing_level
	if f != _slot_frame or lead != _slot_lead:
		_slot_frame = f
		_slot_lead = lead
		_slot_cache = formation_slots(lead)
	return _slot_cache.get(s, s.global_position)


var _slot_frame := -1
var _slot_lead: Soldier = null
var _slot_cache := {}


## Blickrichtung (Yaw-Offset zur Blickrichtung des Anführers) des Platzes – Original-Platzrichtungen (Pfeil fächert auf).
func slot_watch_offset(s: Soldier) -> float:
	var lead := leader()
	var i := _followers(lead).find(s) + 1 if lead else 0
	var dirs: Array = ORIG_DIRS.get(ORIG_TYPE.get(formation, 3), [])
	if i <= 0 or i >= dirs.size():
		return 0.0
	var d: Vector2 = dirs[i]
	return -atan2(d.x, d.y)


## Befehlsmenü „Formation“ (Original 7250–7255): Formation setzen, enger/weiter in Stufen (0x456020 Fall 0x18/0x19).
const SPACING_MIN := 1.5         ## Stufe 0 [B 0x80FA98]
const SPACING_STEP := 0.75       ## je Stufe [B 0x80F900]
const SPACING_LEVELS := 7        ## höchste Stufe [B 0x456020: < 7]
const SPACING_MAX := SPACING_MIN + SPACING_STEP * SPACING_LEVELS   ## 6,75 m


func set_formation(f: int) -> void:
	formation = f
	orders_changed.emit()


## Abstand ändern: d < 0 = eine Stufe enger, d > 0 = eine Stufe weiter. false am Rand.
func change_spacing(d: float) -> bool:
	var nl := clampi(spacing_level + (1 if d > 0.0 else -1), 0, SPACING_LEVELS)
	if nl == spacing_level:
		return false
	spacing_level = nl
	orders_changed.emit()
	return true


## Original vtable +0x40 / +0x3C (0x4595D0/0x4595C0): kleinste bzw. größte Stufe erreicht.
func at_min_spacing() -> bool:
	return spacing_level == 0


func at_max_spacing() -> bool:
	return spacing_level == SPACING_LEVELS


## Hat der Soldat einen Taktik-Plan (Bewegungsbefehl aus der taktischen Karte)?
func has_plan(s: Soldier) -> bool:
	var b := brain_of(s)
	return b != null and s.alive and b.plan and b.order == SquadBrain.Order.MOVE


## Direkttaste L (Zusatz, nicht im Original): durch die drei Menüformationen Pfeil → Linie → Kolonne blättern.
func cycle_formation() -> String:
	var order := [Formation.WEDGE, Formation.LINE, Formation.COLUMN]
	var i := order.find(formation)
	formation = order[(i + 1) % order.size()]
	orders_changed.emit()
	return FORMATION_NAMES[formation]


## Befehl an alle KI-Mitglieder.
func order_all(o: int, pos := Vector3.ZERO) -> void:
	var i := 0
	for m in order_recipients():
		var b := brain_of(m)
		if o == SquadBrain.Order.MOVE:
			# Zielpunkte leicht auffächern
			var ang := TAU * i / 4.0
			b.set_order(o, pos + Vector3(cos(ang), 0, sin(ang)) * (1.5 if i > 0 else 0.0))
		else:
			b.set_order(o, pos)
		i += 1
	orders_changed.emit()


## Befehl an ein einzelnes KI-Mitglied (taktische Karte).
func order_one(s: Soldier, o: int, pos := Vector3.ZERO) -> void:
	var b := brain_of(s)
	if b and s.alive and s != leader():
		b.set_order(o, pos)
		b.plan = o == SquadBrain.Order.MOVE     # Kartenbefehl = Taktik-Plan (Befehlsmenü „Taktik-Modus“)
		orders_changed.emit()


## Granatbefehl (Original-Signal ATTACK_THROW_GRENADE): das nächste KI-Mitglied
## mit Granate wirft auf target. Gibt den Werfer zurück oder null.
func order_grenade(target: Vector3) -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for m in order_recipients():
		if m.weapons.size() <= WeaponData.Slot.GRENADE:
			continue
		var g := m.weapons[WeaponData.Slot.GRENADE]
		if g == null or g.total_ammo() <= 0:
			continue
		var d := m.global_position.distance_to(target)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return null
	brain_of(best).grenade_target = target
	orders_changed.emit()
	return best


func toggle_roe() -> int:
	var lead := leader()
	var new_roe := SquadBrain.ROE.HOLD_FIRE
	for m in members:
		var b := brain_of(m)
		if m != lead and b:
			new_roe = SquadBrain.ROE.FIRE_AT_WILL if b.roe == SquadBrain.ROE.HOLD_FIRE else SquadBrain.ROE.HOLD_FIRE
			break
	for m in (members if selected.is_empty() else selected):
		var b := brain_of(m)
		if b:
			b.roe = new_roe
	orders_changed.emit()
	return new_roe


func _on_member_died(s: Soldier) -> void:
	Events.say("%s ist gefallen!" % s.soldier_name, 4.0)
	if s == leader():
		# Steuerung automatisch an den nächsten Lebenden übergeben
		for k in range(1, members.size()):
			if set_active((active_index + k) % members.size()):
				break
	orders_changed.emit()


func all_dead() -> bool:
	return alive_members().is_empty()
