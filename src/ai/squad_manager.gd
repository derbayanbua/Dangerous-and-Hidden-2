class_name SquadManager
extends Node
## Verwaltet den Spielertrupp: Mitglieder, aktiven (gesteuerten) Soldaten,
## Formation und Befehle. Belegte Formationen im Original:
## Column, Line, Quad2X3, ArrowSharp (Keil), ArrowInvert, Quad3X2.

enum Formation { COLUMN, LINE, WEDGE, QUAD }
const FORMATION_NAMES := ["Kolonne", "Linie", "Keil", "Block 2×2"]

signal active_changed(soldier: Soldier)
signal orders_changed

var members: Array[Soldier] = []
var active_index := 0
var formation: int = Formation.COLUMN
var spacing := 3.0


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
		var b := brain_of(prev)
		if b:
			b.set_order(SquadBrain.Order.FOLLOW)
	active_index = i
	var cur := members[i]
	cur.is_player_controlled = true
	var cb := brain_of(cur)
	if cb:
		cb.stop_moving()
		cb.cease_fire()
	active_changed.emit(cur)
	Events.active_soldier_changed.emit(cur)
	return true


func cycle_active() -> void:
	for k in range(1, members.size() + 1):
		if set_active((active_index + k) % members.size()):
			return


## Formationsplatz für Mitglied s relativ zum Anführer (Weltkoordinaten).
func formation_slot(s: Soldier, lead: Soldier) -> Vector3:
	var others: Array[Soldier] = []
	for m in members:
		if m != lead and m.alive:
			others.append(m)
	var idx := others.find(s)
	if idx < 0:
		return s.global_position
	var off := Vector3.ZERO
	var sp := spacing
	match formation:
		Formation.COLUMN:
			off = Vector3(0, 0, sp * (idx + 1))
		Formation.LINE:
			var side := 1.0 if idx % 2 == 0 else -1.0
			off = Vector3(side * sp * (idx / 2 + 1), 0, 0.5)
		Formation.WEDGE:
			var side2 := 1.0 if idx % 2 == 0 else -1.0
			var row := idx / 2 + 1
			off = Vector3(side2 * sp * row * 0.8, 0, sp * row * 0.8)
		Formation.QUAD:
			var grid := [Vector3(sp, 0, 0), Vector3(0, 0, sp), Vector3(sp, 0, sp), Vector3(-sp, 0, sp)]
			off = grid[idx % grid.size()]
	var basis := Basis(Vector3.UP, lead.look_yaw)
	return lead.global_position + basis * off


## Blickrichtung (Yaw-Offset) für Rundumsicherung im Stand.
func slot_watch_offset(s: Soldier) -> float:
	var idx := members.find(s)
	return [0.0, 0.6, -0.6, PI][idx % 4]


## Befehlsmenü „Formation“ (Original 7250–7254): Formation setzen, enger/weiter (Abstände = Annahme).
const SPACING_MIN := 1.5
const SPACING_MAX := 6.0
const SPACING_STEP := 1.0


func set_formation(f: int) -> void:
	formation = f
	orders_changed.emit()


func change_spacing(d: float) -> bool:
	var ns := clampf(spacing + d, SPACING_MIN, SPACING_MAX)
	if is_equal_approx(ns, spacing):
		return false
	spacing = ns
	orders_changed.emit()
	return true


## Hat der Soldat einen Taktik-Plan (Bewegungsbefehl aus der taktischen Karte)?
func has_plan(s: Soldier) -> bool:
	var b := brain_of(s)
	return b != null and s.alive and b.plan and b.order == SquadBrain.Order.MOVE


func cycle_formation() -> String:
	formation = (formation + 1) % FORMATION_NAMES.size()
	orders_changed.emit()
	return FORMATION_NAMES[formation]


## Befehl an alle KI-Mitglieder.
func order_all(o: int, pos := Vector3.ZERO) -> void:
	var lead := leader()
	var i := 0
	for m in alive_members():
		if m == lead:
			continue
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
	for m in alive_members():
		if m == leader() or m.weapons.size() <= WeaponData.Slot.GRENADE:
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
	for m in members:
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
