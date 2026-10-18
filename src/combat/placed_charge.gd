class_name PlacedCharge
extends Node3D
## Abgelegter Sprengstoff (Zeitzünder 10 s) oder Mine (Annäherungszünder: Gegner/Fahrzeug ≤ 1,8 m).
## Schaden nach dem Original-Explosionsmodell (WeaponDB.explosion_damage, hd2.exe 0x6DE780), Deckung schützt
## (Sichtlinie zum Explosionspunkt).
## Vorgabe Auftraggeber (17.10.2026): gelegte Minen und Ladungen lassen sich durch Beschuss zur Detonation
## bringen (Trefferfläche auf Ebene 3 wie Trefferzonen, blockiert Geschosse, nicht die Bewegung) und gehen
## durch Explosionen in der Nähe mit hoch (Gruppe „destructibles“ → OrigInteractive.damage_objects).
## Mehrspieler: Beschuss wertet nur der Server aus; jede Detonation auf dem Server wird an alle verteilt
## (Net.charge_detonated → _charge_boom), Clients lassen die Ladung an derselben Stelle explodieren.

const FUSE := 10.0
const MINE_TRIGGER := 1.8
## Mine: items.sav 70 „Mina“ Verhalten 2 (placed_explosive): Stärke 2500 zotti (= 250 Gesundheit), Radius 5,0 m [P]
const MINE_STRENGTH := 250.0
const MINE_RADIUS := 5.0
## Sprengladung des Spielers: Dynamit/Sprengstofftasche (items.sav 67/68) ohne eigene Explosionswerte – bisheriger
## Designwert 420 / 7 m [D], seit 17.10.2026 mit dem linearen Originalabfall
const CHARGE_STRENGTH := 420.0
const CHARGE_RADIUS := 7.0
## Verzögerung der Kettenreaktion (s), damit Folgeexplosionen sichtbar nacheinander kommen [D]
const CHAIN_DELAY := 0.18
## Mindestschaden einer Explosion, der die Ladung mitreißt [D]
const CHAIN_MIN_DAMAGE := 1.0

var kind := "explosive"           ## "explosive" oder "mine"
var owner_soldier: Soldier
var team := 0
var _t := 0.0
var _armed := false
var _done := false
var _chain_by: Node
var _chain_t := -1.0
var hit_area: Area3D              ## Trefferfläche für Geschosse (Ebene 3)
var defuse_spot: DefuseSpot       ## Benutzen-Punkt zum Entschärfen
## Entschärfen: Original-Aktion 2 fest 4000 ms, ohne Fähigkeit/Werkzeug, jeder darf (auch der Leger)
## (hd2.exe 0x586200, Menü 0x4B1C2D Text 7021, Fortschritt Text 7075 [B])
const DEFUSE_TIME := 4.0
## Abbruch, wenn sich der Entschärfende weiter als dies vom Startpunkt entfernt (m) [D]
const DEFUSE_MOVE_TOL := 0.6
## Annäherungszünder: geduckte/liegende Soldaten lösen erst bei Berührung aus (Original zündet nur bei Kontakt,
## Kugel 0,5 m um den Menschen, hd2.exe 0x59FFD0 [B]) – so kann man heranschleichen und entschärfen [D]
const MINE_TOUCH := 0.5


func strength() -> float:
	return MINE_STRENGTH if kind == "mine" else CHARGE_STRENGTH


func radius() -> float:
	return MINE_RADIUS if kind == "mine" else CHARGE_RADIUS


func _ready() -> void:
	add_to_group("placed_charges")
	add_to_group("destructibles")
	var vis := OrigWeapons.world_model("w_antiman" if kind == "mine" else "w_explosive")
	if vis:
		add_child(vis)
		_ground_model(vis)
	else:
		var mi := MeshInstance3D.new()
		var m: Mesh = CylinderMesh.new() if kind == "mine" else BoxMesh.new()
		if m is CylinderMesh:
			(m as CylinderMesh).top_radius = 0.14
			(m as CylinderMesh).bottom_radius = 0.16
			(m as CylinderMesh).height = 0.07
			mi.position.y = 0.035
		else:
			(m as BoxMesh).size = Vector3(0.25, 0.12, 0.18)
			mi.position.y = 0.06
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.25) if kind == "mine" else Color(0.55, 0.2, 0.15)
		mi.material_override = mat
		add_child(mi)
	# Trefferfläche: etwas größer als das Modell, ragt über den Boden, damit flache Schüsse sie vor dem Boden treffen
	hit_area = Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = Hitbox.LAYER
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.monitorable = true
	hit_area.set_meta("hit_proxy", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.42, 0.2, 0.42) if kind == "mine" else Vector3(0.4, 0.26, 0.34)
	cs.shape = bs
	cs.position.y = bs.size.y * 0.5 - 0.03
	hit_area.add_child(cs)
	add_child(hit_area)
	# Entschärfen per Benutzen-Taste (Vorgabe Auftraggeber): eigener Interaktionspunkt
	defuse_spot = DefuseSpot.new()
	defuse_spot.name = "Defuse"
	defuse_spot.charge = self
	add_child(defuse_spot)
	_init_spot_id.call_deferred()       # Lage setzt der Erzeuger direkt nach add_child


## Gleiche Kennung auf allen Rechnern (Net._use findet das Objekt über persistent_id): aus der Lage in cm.
func _init_spot_id() -> void:
	if is_instance_valid(defuse_spot) and is_inside_tree():
		var p := global_position * 100.0
		defuse_spot.persistent_id = "charge_%d_%d_%d" % [roundi(p.x), roundi(p.y), roundi(p.z)]


## Original-Modell auf den Boden stellen (Unterkante auf y = 0 des Ladungsknotens).
func _ground_model(vis: Node3D) -> void:
	var lo := INF
	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = OrigWeapons._rel(self, mi as Node3D) * (mi as MeshInstance3D).get_aabb()
		lo = minf(lo, ab.position.y)
	if lo < INF:
		vis.position.y -= lo


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _chain_t >= 0.0:
		_chain_t -= delta
		if _chain_t < 0.0:
			explode(_chain_by)
			return
	_t += delta
	if kind == "explosive":
		if _t >= FUSE:
			explode()
		return
	# Mine scharf nach 3 s (Zeit zum Entfernen); löst bei Gegnern bzw. Fahrzeugen aus
	if _t < 3.0:
		return
	if not _armed:
		_armed = true
		OrigAudio.play_group(OrigAudio.CAT_WEAPON, 71, global_position)   # Kat. 3 „All Mine Armed“
	var defuser: Soldier = defuse_spot.worker if is_instance_valid(defuse_spot) and defuse_spot.busy() else null
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive or s.team == team or s.team == Soldier.TEAM_NEUTRAL or s == defuser:
			continue
		var reach := MINE_TOUCH if s.stance != Soldier.Stance.STAND else MINE_TRIGGER
		if s.global_position.distance_to(global_position) < reach:
			explode()
			return
	for v in get_tree().get_nodes_in_group("vehicles"):
		if (v as Node3D).global_position.distance_to(global_position) < MINE_TRIGGER + 1.5:
			explode()
			return


## Geschosstreffer (Ballistics über Meta „hit_proxy“ der Trefferfläche): sofortige Detonation. Im Mehrspieler
## entscheidet der Server (Clients simulieren dieselben Schüsse, ignorieren den Treffer aber).
func on_bullet_hit(_damage: float, by: Node) -> void:
	if _done or not Net.is_authority():
		return
	explode(by)


## Explosion in der Nähe (OrigInteractive.damage_objects): Kettenreaktion mit kurzer Verzögerung.
func on_explosion(damage: float, by: Node) -> void:
	if _done or _chain_t >= 0.0 or damage < CHAIN_MIN_DAMAGE:
		return
	_chain_by = by
	_chain_t = CHAIN_DELAY


func is_done() -> bool:
	return _done


## by: Auslöser (Schütze bzw. Verursacher der auslösenden Explosion); ohne gültigen Auslöser der Leger.
func explode(by: Node = null) -> void:
	if _done:
		return
	_done = true
	if hit_area:
		hit_area.collision_layer = 0
	if is_instance_valid(defuse_spot) and defuse_spot.busy():
		defuse_spot.cancel("Detonation")
	var pos := global_position + Vector3.UP * 0.2
	if not (is_instance_valid(by) and by is Soldier):
		by = owner_soldier if is_instance_valid(owner_soldier) else null
	if Net.is_online and multiplayer.is_server():
		Net.charge_detonated(global_position)
	print("LADUNG: %s detoniert bei %s (Auslöser %s)" % [kind, global_position.snapped(Vector3.ONE * 0.01),
		(by as Node).name if is_instance_valid(by) else "-"])
	var r := radius()
	var dmg_strength := strength()
	# Original Kat. 6/16 „Explosion Naloz Ext“ (Sprengladung); Mine 6/30 „Explosion Mina“ – deren Dateien fehlen
	# in der Installation, dann 6/0 (Ersatz)
	var snd := [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_CHARGE_OUT]
	if kind == "mine":
		snd = [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_MINE if not OrigAudio.pick(6, OrigAudio.EXP_MINE).is_empty() else OrigAudio.EXP_GRENADE]
	Effects.explosion(pos, r * 0.7, snd)
	Events.emit_noise(pos, 300.0, by, team, &"explosion")
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive:
			continue
		var target := s.global_position + Vector3.UP * 0.5
		var d := pos.distance_to(target)
		if d > r:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		s.apply_hit(WeaponDB.explosion_damage(dmg_strength, r, d), &"torso", by, (target - pos).normalized())
	OrigInteractive.damage_objects(get_tree(), pos, r, dmg_strength, by)
	queue_free()


## Client: der Server meldet eine Detonation an pos – die passende eigene Ladung explodiert (Darstellung; Schaden
## rechnet ohnehin nur der Server).
static func remote_detonate(tree: SceneTree, pos: Vector3) -> bool:
	var best: PlacedCharge = null
	var best_d := 0.75
	for n in tree.get_nodes_in_group("placed_charges"):
		var c := n as PlacedCharge
		if c == null or c.is_done():
			continue
		var d := c.global_position.distance_to(pos)
		if d < best_d:
			best = c
			best_d = d
	if best == null:
		return false
	remote_booms += 1
	best.explode()
	return true


## Vom Server gemeldete und hier ausgeführte Detonationen (Tests)
static var remote_booms := 0
## Vom Server gemeldete und hier ausgeführte Entschärfungen (Tests)
static var remote_defuses := 0
## Entschärfungen insgesamt (Tests)
static var defused_count := 0


## Entschärfen abgeschlossen: Ladung wird ersatzlos entfernt – wie im Original (hd2.exe 0x584E30 Fall 2 →
## 0x5FEEE0: Mine aus, Netzmeldung, Akteur löschen; kein Gegenstand ins Inventar oder auf den Boden [B]).
## Im Mehrspieler entscheidet der Server und meldet es an alle (Net.charge_defused).
func defuse(by: Soldier) -> void:
	if _done:
		return
	_done = true
	defused_count += 1
	print("LADUNG: %s entschärft bei %s (%s)" % [kind, global_position.snapped(Vector3.ONE * 0.01),
		by.name if is_instance_valid(by) else "-"])
	if hit_area:
		hit_area.collision_layer = 0
	if Net.is_online and multiplayer.is_server():
		Net.charge_defused(global_position)
	if is_instance_valid(by) and by.alive:
		Events.say("%s: %s entschärft." % [by.soldier_name, "Mine" if kind == "mine" else "Sprengladung"], 2.5)
	OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_BOMB, global_position, self)
	queue_free()


## Client: der Server meldet eine Entschärfung an pos.
static func remote_defuse(tree: SceneTree, pos: Vector3) -> bool:
	for n in tree.get_nodes_in_group("placed_charges"):
		var c := n as PlacedCharge
		if c and not c.is_done() and c.global_position.distance_to(pos) < 0.75:
			remote_defuses += 1
			c.defuse(c.defuse_spot.worker if is_instance_valid(c.defuse_spot) else null)
			return true
	return false


## Benutzen-Punkt „Entschärfen“ (Original-Text 7075 „Entschärft“ / Aufforderung wie beim Sprengplatz).
## Dauer DEFUSE_TIME; Abbruch bei Bewegung, Treffer oder Tod. Der Entschärfende löst die Mine dabei nicht aus.
class DefuseSpot extends Interactable:
	var charge: PlacedCharge
	var worker: Soldier
	var _left := 0.0
	var _from := Vector3.ZERO
	var _hp := 0.0

	func _ready() -> void:
		super._ready()
		prompt = "%s: %s" % ["Mine" if charge.kind == "mine" else "Sprengladung", OrigInteractive.text(OrigInteractive.TXT_DEFUSE, "Entschärfen")]

	func busy() -> bool:
		return _left > 0.0

	func can_interact(s: Soldier) -> bool:
		return enabled and not busy() and is_instance_valid(charge) and not charge.is_done() and s != null and s.alive \
			and s.vehicle == null

	func interact(s: Soldier) -> void:
		if not can_interact(s):
			return
		worker = s
		print("LADUNG: Entschärfen begonnen von %s (%s)" % [s.name, persistent_id])
		_left = DEFUSE_TIME
		_from = s.global_position
		_hp = s.health
		s.work_label = OrigInteractive.text(7075, "Entschärft")
		s.work_total = DEFUSE_TIME
		s.work_left = DEFUSE_TIME
		if s.stance == Soldier.Stance.STAND:
			s.stance_request = Soldier.Stance.CROUCH      # zum Entschärfen in die Hocke
		Events.say(s.work_label + " …", DEFUSE_TIME)
		OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_BOMB, global_position, self)   # „Bomb manipulation“
		super.interact(s)

	func cancel(reason: String) -> void:
		if is_instance_valid(worker):
			worker.work_left = 0.0
			if worker.is_player_controlled:
				Events.say("Entschärfen abgebrochen (%s)." % reason, 1.5)
		_left = 0.0
		worker = null

	func _physics_process(delta: float) -> void:
		if _left <= 0.0:
			return
		if not is_instance_valid(worker) or not worker.alive:
			cancel("ausgefallen")
			return
		var d := worker.global_position - _from
		d.y = 0.0
		if d.length() > DEFUSE_MOVE_TOL:
			cancel("bewegt")
			return
		if worker.health < _hp - 0.5:
			cancel("getroffen")
			return
		_left -= delta
		worker.work_left = maxf(_left, 0.0)
		if _left > 0.0:
			return
		_left = 0.0
		worker.work_left = 0.0
		if Net.is_authority():
			charge.defuse(worker)
		# Client: Ergebnis kommt vom Server (Net._charge_evt)
