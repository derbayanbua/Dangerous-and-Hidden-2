class_name OrigInteractive
extends Node
## Interaktive Originalakteure aus orig_cache/<mission>/interactive.json (tools/fmt_interactive.py;
## Belege: docs/re_notes_interactive.md): Türen/Tore (6) und Schranken (28), Leitern (8), Schalter (13),
## Funkgeräte (7), Sprengplätze (22), zerstörbare Objekte (25 „Animation“), Kisten (9), Fotoplätze (15),
## Dokumentplätze (23). Skriptschnittstelle: SetActorState / _ACTOR_GetState / DOOR_Lock / OnUse / OnDeath.
## Waffenstellungen (21): Waffe aus dem Modellnamen (ANNAHME, im Original nicht in den Parametern), Munition aus
## dem items.dat-Inventar der Stellung. Nicht umgesetzt: Fässer (5), Zerstörungsanimationen (.i3d).

const TXT_OPEN := 7023
const TXT_CLOSE := 7041
const TXT_UNLOCK := 7020
const TXT_PICK := 7033
const TXT_USE := 7022
const TXT_PLANT := 7047
const TXT_DEFUSE := 7021
const TXT_PHOTO := 7018
const TXT_AMMO := 7053

var mission: Node
var runtime: LsRuntime
var orig: OrigLevel
var stats := {"world_items": 0, "emplacements": 0, "doors": 0, "ladders": 0, "switches": 0, "explosives": 0, "destructibles": 0, "crates": 0,
	"photos": 0, "documents": 0, "radios": 0, "missing": 0}
var controls := {}        ## Name (groß) -> Steuerobjekt


func setup(m: Node, rt: LsRuntime, o: OrigLevel) -> void:
	mission = m
	runtime = rt
	orig = o
	var d = LsRuntime._read_json(o.mission_dir + "/interactive.json")
	if typeof(d) != TYPE_DICTIONARY:
		return
	for e in d.get("doors", []):
		_door(e, false)
	for e in d.get("barriers", []):
		_door(e, true)
	for e in d.get("ladders", []):
		_ladder(e)
	for e in d.get("switches", []):
		_switch(e, "switches")
	for e in d.get("radios", []):
		_switch(e, "radios")
	for e in d.get("explosive_places", []):
		_explosive(e)
	for e in d.get("destructibles", []):
		_destructible(e)
	for e in d.get("crates", []):
		_crate(e)
	for e in d.get("emplacements", []):
		_emplacement(e)
	_world_items()
	for e in d.get("photo_places", []):
		_place(e, "photos", TXT_PHOTO, 229)
	for e in d.get("document_places", []):
		var p: Dictionary = e.get("params", {})
		_place(e, "documents", int(p.get("action_text", 7051)), int(p.get("required_item", -1)))
	_static_leaves()
	_fences()


# --- Zerschneidbare Zäune (B-017) -------------------------------------------------------------------------------
## Original [B]: Zaunfelder sind 4DS-Frames mit Parameter „phobj … break <Modell>“ (hd2.exe 0x410B40: Physikobjekt,
## Ersatzmodell nach dem Zerschneiden, Standard „plotdira“; ARCTIC1 114 Felder plot_a* mit Material 20 „Pletivo“ und
## Ersatz m_plotdira). Aktionsmenü 0x4BF670 Fall 0x23: „Benutze Drahtschneider“ (T7035) nur mit Drahtschere im
## Inventar (0x5A7ED0; Gegenstand 59 „wire-cutter“, items.sav). Skripte lesen/setzen den Zustand (r_arc1a_ploty.scr
## speichert _ACTOR_GetState je Feld als SaveGameValue 111–223, r_ar3_ploty.scr stellt ihn mit SetActorState her).
## Annahmen [E]: Zustand 0 = ganz, 1 = zerschnitten; Dauer 3 s, Abbruch bei > 1 m Bewegung; Klang Kat. 11 Nr. 25.
const WIRE_CUTTER := 59
const TXT_CUTTER := 7035
const FENCE_CUT_TIME := 3.0

func _fences() -> void:
	if orig == null:
		return
	var f := FileAccess.open(orig.mission_dir + "/scene.glb", FileAccess.READ)
	if f == null or f.get_length() < 20 or f.get_32() != 0x46546C67:
		return
	f.get_32()
	f.get_32()
	var ln := f.get_32()
	f.get_32()
	var j = JSON.parse_string(f.get_buffer(ln).get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY:
		return
	var re := RegEx.create_from_string("break([A-Za-z0-9_]+)")
	for n in j.get("nodes", []):
		var ex = n.get("extras", {})
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		var pr := String(ex.get("params", ""))
		if not pr.begins_with("phobj"):
			continue
		var m := re.search(pr)
		if m == null:
			continue
		var nm := String(n.get("name", ""))
		var fr := runtime.find_frame(nm)
		if fr == null:
			continue
		var c := OrigFence.new()
		c.name = "Fence_" + nm.validate_node_name()
		mission.dynamic_root.add_child(c)
		c.init(self, fr, nm, m.get_string(1))
		controls[nm.to_upper()] = c
		fr.set_meta("orig_ctl", c)
		stats["fences"] = int(stats.get("fences", 0)) + 1


class OrigFence extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var break_model := ""
	var cut := false
	var floor_y := 0.0
	var _left := 0.0
	var _by: Soldier
	var _from := Vector3.ZERO
	var _snd: AudioStreamPlayer3D
	var _broken: Node3D

	func init(h: OrigInteractive, f: Node3D, nm: String, model: String) -> void:
		host = h
		frame = f
		break_model = model
		persistent_id = "ofence_" + nm
		var box := OrigInteractive.world_aabb(f)
		global_position = box.get_center()
		floor_y = box.position.y
		frame.set_meta("actor_state", 0)
		_add_block()
		_update_prompt()

	## Original: Physikobjekt mit eigener Kollision (nicht in tree.klz). Das Drahtgeflecht hat Alpha-Material und bekam
	## im Nachbau als „Laub“ keine Kollision – man lief hindurch. Wie die Klz-Pletivo-Flächen (Bit 0x100000,
	## re_notes_script_anims §6): Kasten je Mesh auf Ebene 5 – sperrt Bewegung, Sicht und Geschosse gehen durch.
	func _add_block() -> void:
		var list: Array = frame.find_children("*", "MeshInstance3D", true, false)
		if frame is MeshInstance3D:
			list.append(frame)
		for mi in list:
			var me := mi as MeshInstance3D
			if me.mesh == null:
				continue
			var bb := me.get_aabb()
			var body := StaticBody3D.new()
			body.name = "FenceBlock"
			body.collision_layer = 1 << 4
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = bb.size.max(Vector3(0.12, 0.12, 0.12))
			cs.shape = box
			cs.position = bb.get_center()
			body.add_child(cs)
			me.add_child(body)

	func _update_prompt() -> void:
		prompt = OrigInteractive.text(TXT_CUTTER, "Benutze Drahtschneider") + (" …" if _left > 0.0 else "")

	func can_interact(s: Soldier) -> bool:
		return enabled and not cut and s.global_position.y > floor_y - 1.0 and s.global_position.y < floor_y + 1.8

	func interact(s: Soldier) -> void:
		if cut or _left > 0.0:
			return
		if not host.allowed(s, WIRE_CUTTER):
			Events.say("Keine Drahtschere.", 2.0)
			return
		if not OrigInteractive.has_item(s, WIRE_CUTTER):
			Events.say("Drahtschere fehlt im Trupp – Zaun wird trotzdem geöffnet.", 2.0)
		_by = s
		_from = s.global_position
		_left = FENCE_CUT_TIME
		Events.say(OrigInteractive.text(TXT_CUTTER, "Benutze Drahtschneider") + " …", FENCE_CUT_TIME)
		_snd = OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_WIRECUT, global_position, self)
		_update_prompt()
		super.interact(s)

	func _physics_process(delta: float) -> void:
		if _left <= 0.0:
			return
		if not is_instance_valid(_by) or not _by.alive or _by.global_position.distance_to(_from) > 1.0:
			_left = 0.0
			if is_instance_valid(_snd):
				_snd.queue_free()
			_update_prompt()
			return
		_left -= delta
		if _left <= 0.0:
			Events.emit_noise(global_position, 5.0, _by, _by.team, &"fence")
			set_cut(true)

	func set_cut(b: bool) -> void:
		if not b or cut:
			return
		cut = true
		_left = 0.0
		frame.set_meta("actor_state", 1)
		# Feld samt Kindern ausblenden, Kollision aus; Ersatzmodell (offenes Zaunfeld) an dieselbe Stelle
		frame.visible = false
		for b2 in frame.find_children("*", "CollisionObject3D", true, false):
			var co := b2 as CollisionObject3D
			co.collision_layer = 0
			co.collision_mask = 0
		var inst: Node3D = host.orig.model_instance(break_model) if host.orig else null
		if inst:
			inst.name = "Cut_" + String(frame.name).validate_node_name()
			host.mission.dynamic_root.add_child(inst)
			inst.global_transform = frame.global_transform
			_broken = inst
		_update_prompt()
		if Net.is_online and is_inside_tree():
			Net.object_state(self)

	func set_actor_state(n: int) -> void:
		set_cut(n != 0)

	func net_state() -> Dictionary:
		return {"cut": cut}

	func net_apply(st: Dictionary, _snap: bool) -> void:
		set_cut(bool(st.get("cut", cut)))

	func serialize() -> Dictionary:
		return {"enabled": enabled, "cut": cut}

	func deserialize(d: Dictionary) -> void:
		enabled = d.get("enabled", true)
		set_cut(bool(d.get("cut", false)))


# --- Statische Türflügel mit Klinke (B-017, ABWEICHUNG [D]) -----------------------------------------------------
## Original [B]: Manche Eingangstüren sind keine Türakteure (kein Typ-6-Eintrag in scene2.bin), sondern statische
## Frames mit Klinke „dhandle*“: AFRICA1 HL_DV09/HL_DV11 (Haupteingang vorne/hinten, in tree.klz gar nicht verlinkt),
## NORMANDY2 m_H36 (am Startpunkt, Klz-Kiste). Im Original lassen sie sich nicht benutzen. Vorgabe Auftraggeber
## (B-017): solche Flügel öffnen per Benutzen wie Drehtüren – Angel an der Kante gegenüber der Klinke, 90°, Drehsinn
## zur freien Seite. Flügel ohne freien Durchgang dahinter (Attrappe vor einer Wand) bleiben unbenutzbar.
const LEAF_MIN_H := 1.6
const LEAF_MAX_H := 2.8

func _static_leaves() -> void:
	if orig == null or orig.root == null:
		return
	var seen := {}
	for n in orig.root.find_children("dhandle*", "MeshInstance3D", true, false):
		var leaf := n.get_parent() as MeshInstance3D
		if leaf == null or seen.has(leaf) or leaf.has_meta("orig_ctl") or leaf.mesh == null or not leaf.is_visible_in_tree():
			continue
		seen[leaf] = true
		var b := leaf.global_transform * leaf.get_aabb()
		var wide := maxf(b.size.x, b.size.z)
		var thin := minf(b.size.x, b.size.z)
		if b.size.y < LEAF_MIN_H or b.size.y > LEAF_MAX_H or wide < 0.5 or wide > 1.4 or thin > 0.25:
			continue
		var p := leaf.get_parent()
		var skip := false
		while p != null and p != orig.root:
			if p.has_meta("orig_ctl"):
				skip = true            # Flügel eines echten Türakteurs
				break
			p = p.get_parent()
		if skip:
			continue
		# Angel: senkrechte Kante gegenüber der Klinke
		var hb := (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
		var along := Vector3.RIGHT if b.size.x >= b.size.z else Vector3.BACK
		var c := b.get_center()
		var hs := signf((hb.get_center() - c).dot(along))
		if hs == 0.0:
			hs = 1.0
		var hinge := Vector3(c.x, b.position.y, c.z) - along * hs * wide * 0.5
		var pivot := Node3D.new()
		pivot.name = "Leaf_" + String(leaf.name).validate_node_name()
		mission.dynamic_root.add_child(pivot)
		pivot.global_position = hinge
		leaf.reparent(pivot, true)
		var e := {"name": String(leaf.name), "params": {"open_amount": PI * 0.5, "speed": PI * 0.5, "axis_gltf": [0, 1, 0],
			"label_text": 7153}}
		var d := OrigDoor.new()
		d.name = "LeafDoor_" + String(leaf.name).validate_node_name()
		mission.dynamic_root.add_child(d)
		d.init(self, pivot, e, false)
		d.persistent_id = "oleaf_%s_%d_%d" % [String(leaf.name), roundi(c.x * 10.0), roundi(c.z * 10.0)]
		d.static_leaf = true
		d.leaf_normal = Vector3.BACK if along == Vector3.RIGHT else Vector3.RIGHT
		pivot.set_meta("orig_ctl", d)
		controls["LEAF:" + String(leaf.name).to_upper() + ":%d" % stats.get("leaf_doors", 0)] = d
		stats["leaf_doors"] = int(stats.get("leaf_doors", 0)) + 1


static func text(id: int, fb: String) -> String:
	return SAS.text(id, fb) if id > 0 else fb


func _frame(e: Dictionary) -> Node3D:
	var f := runtime.find_frame(String(e.get("name", "")))
	if f == null:
		stats.missing += 1
	return f


static func world_aabb(n: Node3D) -> AABB:
	var have := false
	var box := AABB()
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for x in list:
		var mi := x as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if not have else box.merge(b)
		have = true
	if not have:
		box = AABB(n.global_position - Vector3(0.4, 0.0, 0.4), Vector3(0.8, 2.0, 0.8))
	return box


func _register(e: Dictionary, frame: Node3D, ctl: Object) -> void:
	controls[String(e.get("name", "")).to_upper()] = ctl
	if frame:
		frame.set_meta("orig_ctl", ctl)


static func has_item(s: Soldier, item: int) -> bool:
	return item < 0 or s.get_meta("orig_items", []).has(item)


static func take_item(s: Soldier, item: int) -> void:
	var inv: Array = s.get_meta("orig_items", [])
	inv.erase(item)
	s.set_meta("orig_items", inv)


func anyone_has(item: int) -> bool:
	if mission.squad == null:
		return false
	for m in mission.squad.members:
		if m.alive and has_item(m, item):
			return true
	return false


## Benötigter Gegenstand (Original: Aktion nur mit Gegenstand im Inventar). Damit kein Einsatz unlösbar
## wird, ist die Aktion auch erlaubt, wenn der Soldat kein Originalinventar hat oder niemand im Trupp den
## Gegenstand besitzt (ABWEICHUNG, z. B. falsch gepackt) – dann mit Hinweis.
func allowed(s: Soldier, item: int) -> bool:
	return item < 0 or has_item(s, item) or not s.has_meta("orig_items") or not anyone_has(item)


## Explosionsschaden an zerstörbaren Objekten, Fahrzeugen, Hunden (MakeExplosion, Sprengplätze, Granaten)
## vehicle_factor: Raketen-Explosionsstärke je Aufschlagziel (hd2.exe 0x449290: Fahrzeug 0,1, Welt 0,5, Mensch 1,0) –
## im Nachbau nur für Fahrzeug-Schadensmodelle angewandt (Vehicle.explosion_at), Menschen unverändert
static func damage_objects(tree: SceneTree, pos: Vector3, radius: float, damage: float, by: Node = null, vehicle_factor := 1.0) -> void:
	for n in tree.get_nodes_in_group("destructibles") + tree.get_nodes_in_group("vehicles") + tree.get_nodes_in_group("dogs"):
		var n3 := n as Node3D
		if n3 == null or not n3.has_method("on_bullet_hit"):
			continue
		# Originalfahrzeug mit Schadensmodell (DM<Modell>.4ds): Explosion trifft die nächste Zone (Vehicle.explosion_at)
		if n.has_method("explosion_at") and n.explosion_at(pos, radius, damage * vehicle_factor, by):
			continue
		var r := radius + 1.5
		var dv := pos.distance_to(n3.global_position + Vector3.UP * 0.5)
		if dv < r:
			if n.has_method("on_explosion"):
				n.on_explosion(damage * (1.0 - dv / r), by)
			else:
				n3.on_bullet_hit(damage * 2.5 * (1.0 - dv / r), by)


# --- Türen / Schranken --------------------------------------------------------------

func _door(e: Dictionary, barrier: bool) -> void:
	var f := _frame(e)
	if f == null:
		return
	var d := OrigDoor.new()
	d.name = "Door_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(d)
	d.init(self, f, e, barrier)
	_register(e, f, d)
	stats.doors += 1


class OrigDoor extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var p: Dictionary
	var state := 0            ## 0 zu, 1 offen, 2 öffnet, 3 schließt (Original)
	var amount := 0.0
	var target := 0.0
	var base: Transform3D
	var axis := Vector3.UP
	var sgn := 1.0
	var slide := false
	var speed := PI * 0.5
	var open_amount := PI * 0.5
	var locked := false
	var key_item := -1
	var lockpickable := true
	var label := "Tür"
	var partner_name := ""
	var auto_close := false
	var _close_in := 0.0
	var _pick_left := 0.0
	var _picker: Soldier
	var _pick_from := Vector3.ZERO
	var _move_snd: AudioStreamPlayer3D
	var floor_y := 0.0         ## Unterkante des Flügels (Stockwerk der Tür)
	var is_open: bool:
		get:
			return state == 1 or state == 2

	## Türklang (Original-Akteur Chunk 0x65, IngameSounds Kat. 1): open = Öffnen-Start, closed = Zu-Ende,
	## moving = Bewegung (Schleife), lock/unlock/wrong_key/lockpick/locked_rattle (hd2.exe 0x601F90)
	func _snd(slot: String, loop := false) -> AudioStreamPlayer3D:
		var id := int((p.get("sound_slots", {}) as Dictionary).get(slot, -1))
		if id < 0:
			return null
		return OrigAudio.play_group(OrigAudio.CAT_OBJECT, id, global_position, self, 1.0, loop)

	func _stop_move_snd() -> void:
		if is_instance_valid(_move_snd):
			_move_snd.queue_free()
		_move_snd = null

	func init(h: OrigInteractive, f: Node3D, e: Dictionary, barrier: bool) -> void:
		host = h
		frame = f
		p = e.get("params", {})
		persistent_id = "odoor_" + String(e["name"])
		slide = int(p.get("motion", 0)) == 1
		open_amount = absf(float(p.get("open_amount", PI * 0.5)))
		speed = maxf(absf(float(p.get("speed", PI * 0.5))), 0.2)
		var ax: Array = p.get("axis_gltf", p.get("axis", [0, 1, 0]))
		axis = Vector3(ax[0], ax[1], ax[2]).normalized() if Vector3(ax[0], ax[1], ax[2]).length() > 0.01 else Vector3.UP
		locked = bool(p.get("locked", false))
		key_item = int(p.get("key_item", -1))
		lockpickable = bool(p.get("lockpickable", true))
		auto_close = bool(p.get("auto_close", false))
		partner_name = String(p["partner_door"]) if p.get("partner_door") != null else ""
		label = OrigInteractive.text(int(p.get("label_text", 7153 if not barrier else -1)), "Tür" if not barrier else "Schranke")
		# Türflügel aus der Navmesh-Geometrie nehmen (Durchgang bleibt begehbar; KI öffnet selbst)
		if frame.get_parent() != host.mission.dynamic_root:
			frame.reparent(host.mission.dynamic_root, true)
		base = frame.transform
		var box := OrigInteractive.world_aabb(frame)
		global_position = box.get_center()
		floor_y = box.position.y
		# Drehsinn wie hd2.exe 0x5FF700: Lage = quat(Achse +0x210, Betrag +0x264) ⊗ Ausgangslage, Betrag 0…open_amount,
		# also fester Drehsinn um die Datenachse (kein open_dir). In glTF: +Betrag um axis_gltf im Frame-Raum. Gegenprobe
		# tests/probe_door_swing.gd (Flügel geöffnet in statischer Geometrie, 204 Drehtüren auf 4 Karten): +Betrag 44,
		# −Betrag 112; die frühere open_dir-Annahme drehte z. B. auf NORMANDY2 11 von 18 Türen in die Wand.
		sgn = 1.0
		_ensure_collision()
		if int(p.get("initial_state", 0)) == 1:
			# Original 0x600CC0: Betrag beginnt bei 0, Startzustand offen → Öffnen-Befehl (0x5FF4B0 Modus 2, stumm hier)
			target = open_amount
			state = 2
		frame.set_meta("actor_state", state)
		_update_prompt()

	var _ignore: Array[RID] = []
	var _ignore_ready := false
	var _blocked_wait := 0.0

	## Original 0x600CC0: die Tür legt ihr Kollisionsvolumen selbst aus dem Frame-Kasten an (0x6EF3E0), unabhängig von
	## tree.klz. Hat der Flügel keinen Körper (z. B. NORMANDY2 H38_123: liegt im versteckten Treppen-Ersatzkörper und
	## verlor dadurch seine Kollision), bekommt er hier einen Kasten aus seinem Mesh (Ebene 1 wie die Welt).
	func _ensure_collision() -> void:
		if not frame.find_children("*", "CollisionObject3D", true, false).is_empty():
			return
		var list: Array = frame.find_children("*", "MeshInstance3D", true, false)
		if frame is MeshInstance3D:
			list.append(frame)
		for mi in list:
			var me := mi as MeshInstance3D
			if me.mesh == null:
				continue
			var bb := me.get_aabb()
			var body := StaticBody3D.new()
			body.name = "DoorBody"
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = bb.size.max(Vector3(0.03, 0.03, 0.03))
			cs.shape = box
			cs.position = bb.get_center()
			body.add_child(cs)
			me.add_child(body)
			print("TÜR: Kollisionskasten ergänzt für %s" % String(frame.name))

	## Beim ersten Physikschritt: eigene Kollisionskörper des Flügels zählen nicht als Hindernis
	func _prepare_ignore() -> void:
		_ignore_ready = true
		_ignore = _own_rids()
		if static_leaf:
			_check_leaf()

	var static_leaf := false          ## B-017: statischer Türflügel mit Klinke (kein Türakteur), siehe _static_leaves
	var leaf_normal := Vector3.BACK

	## Statischer Flügel: nur benutzbar, wenn hinter ihm Durchgang ist (Strahl quer durch die Öffnung frei, Boden auf
	## beiden Seiten); Drehsinn zur Seite mit weniger Weltüberschneidung bei 90°.
	func _check_leaf() -> void:
		var space := frame.get_world_3d().direct_space_state
		var box := OrigInteractive.world_aabb(frame)
		var c := box.get_center()
		var mid := Vector3(c.x, box.position.y + 1.0, c.z)
		var q := PhysicsRayQueryParameters3D.create(mid - leaf_normal * 1.2, mid + leaf_normal * 1.2, 1)
		q.exclude = _ignore
		q.hit_back_faces = true
		var free := space.intersect_ray(q).is_empty()
		var floors := 0
		for sd in [-1.0, 1.0]:
			var at: Vector3 = Vector3(c.x, box.position.y, c.z) + leaf_normal * sd * 0.9
			var fq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6, 1)
			fq.exclude = _ignore
			if not space.intersect_ray(fq).is_empty():
				floors += 1
		if not free or floors < 2:
			enabled = false
			return
		var best := 1.0
		var best_n := 1 << 30
		for s in [1.0, -1.0]:
			sgn = s
			amount = open_amount
			_apply()
			var k := _overlaps(_ignore, false).size()
			if k < best_n:
				best_n = k
				best = s
		sgn = best
		amount = 0.0
		_apply()

	func _own_rids() -> Array[RID]:
		var out: Array[RID] = []
		for b in frame.find_children("*", "CollisionObject3D", true, false):
			out.append((b as CollisionObject3D).get_rid())
		return out

	## Flügelvolumen (je Mesh ein Kasten, 6 cm/15 cm geschrumpft) gegen Welt (Ebene 1) und Soldaten (Ebene 2)
	func _overlaps(exclude: Array[RID], chars := true, only_chars := false) -> Array[RID]:
		var out: Array[RID] = []
		if not is_inside_tree():
			return out
		var space := frame.get_world_3d().direct_space_state
		var list: Array = frame.find_children("*", "MeshInstance3D", true, false)
		if frame is MeshInstance3D:
			list.append(frame)
		for mi in list:
			var me := mi as MeshInstance3D
			if me.mesh == null:
				continue
			var bb := me.get_aabb()
			var box := BoxShape3D.new()
			box.size = (bb.size - Vector3(0.12, 0.3, 0.12)).max(Vector3(0.01, 0.01, 0.01))
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = me.global_transform * Transform3D(Basis(), bb.get_center())
			q.collision_mask = 2 if only_chars else ((1 | 2) if chars else 1)
			q.exclude = exclude
			for r in space.intersect_shape(q, 8):
				var c = r.get("collider")
				if c is Node and not (c is CharacterBody3D) and String((c as Node).get_path()).contains("/Dynamic/"):
					continue           # andere Türen/Objekte unter dynamic_root
				out.append(r["rid"])
		return out

	## Nur Türen im eigenen Stockwerk: Die Benutzen-Auswahl misst waagrecht – in mehrstöckigen Häusern (NORMANDY2
	## H38: H38_92 unter H38_154, H38_75 unter H38_123, 3,16 m übereinander) griff sonst die Tür darüber/darunter.
	func can_interact(s: Soldier) -> bool:
		return enabled and s.global_position.y > floor_y - 1.0 and s.global_position.y < floor_y + 1.6

	func _update_prompt() -> void:
		if _pick_left > 0.0:
			prompt = "%s: %s" % [label, OrigInteractive.text(7073, "Knackt Schloss")]
		elif locked:
			prompt = "%s: %s" % [label, OrigInteractive.text(TXT_PICK if lockpickable else TXT_UNLOCK, "Aufschließen")]
		else:
			prompt = "%s: %s" % [label, OrigInteractive.text(TXT_CLOSE if is_open else TXT_OPEN, "Schließen" if is_open else "Öffnen")]

	func interact(s: Soldier) -> void:
		if locked:
			if key_item >= 0 and OrigInteractive.has_item(s, key_item):
				locked = false
				_snd("unlock")
				Events.say("%s aufgeschlossen." % label, 2.0)
			elif lockpickable:
				# Dauer aus der Fertigkeit Schlösser (Original: Getter 8, Text 7073)
				_picker = s
				_pick_from = s.global_position
				_pick_left = lerpf(8.0, 2.0, clampf(float(s.get_meta("lockpick", 50.0)) / 100.0, 0.0, 1.0))
				Events.say(OrigInteractive.text(7073, "Knackt Schloss") + " …", _pick_left)
				# Schlossknacken: Türklang „lockpick“, sonst Kat. 11 „Lockpicking“ (l_dhook.wav)
				if _snd("lockpick") == null:
					OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_LOCKPICK, global_position, self)
			else:
				Events.say("%s ist verschlossen." % label, 2.0)
				if _snd("locked_rattle") == null:
					_snd("wrong_key")
				Events.emit_noise(global_position, 6.0, s, s.team, &"door")
			_update_prompt()
			return
		set_open(not is_open)
		Events.emit_noise(global_position, 6.0, s, s.team, &"door")
		host.runtime.notify(frame, "ONUSE")
		super.interact(s)

	func ai_open(_s: Soldier) -> void:
		if not locked and not is_open:
			set_open(true)
			if auto_close:
				_close_in = 15.0

	func set_open(o: bool) -> void:
		if o and locked:
			return
		if is_inside_tree() and not is_equal_approx(amount, open_amount if o else 0.0):
			if o:
				_snd("open")
			_stop_move_snd()
			_move_snd = _snd("moving", true)
		target = open_amount if o else 0.0
		state = 2 if o else 3
		frame.set_meta("actor_state", state)
		_update_prompt()
		if partner_name != "":
			var other = host.controls.get(partner_name.to_upper())
			if other is OrigDoor and other != self and other.is_open != o:
				var keep: String = other.partner_name
				other.partner_name = ""      # kein Ping-Pong
				other.set_open(o)
				other.partner_name = keep
		_net()

	func set_actor_state(n: int) -> void:
		set_open(n != 0)

	func set_locked(b: bool) -> void:
		if b and state != 0:
			return          # Original: Abschließen nur im geschlossenen Zustand
		if b != locked and is_inside_tree():
			_snd("lock" if b else "unlock")
		locked = b
		_update_prompt()
		_net()

	## Mehrspieler: der Server ist maßgeblich und meldet jede Zustandsänderung (Net.object_state); Clients übernehmen
	## sie mit net_apply (Spät-Beitritt: sofort, sonst mit Bewegung/Klang).
	func _net() -> void:
		if Net.is_online and is_inside_tree():
			Net.object_state(self)

	func net_state() -> Dictionary:
		return {"open": target > 0.0, "locked": locked, "amount": amount}

	func net_apply(st: Dictionary, snap: bool) -> void:
		locked = bool(st.get("locked", locked))
		var o := bool(st.get("open", target > 0.0))
		if snap:
			_stop_move_snd()
			target = open_amount if o else 0.0
			amount = clampf(float(st.get("amount", target)), 0.0, open_amount)
			state = (1 if o else 0) if is_equal_approx(amount, target) else (2 if o else 3)
			_apply()
			frame.set_meta("actor_state", state)
		elif o != (target > 0.0):
			var keep := partner_name
			partner_name = ""                # Partnerflügel meldet der Server selbst
			set_open(o)
			partner_name = keep
		_update_prompt()

	func _physics_process(delta: float) -> void:
		if _pick_left > 0.0:
			if not is_instance_valid(_picker) or not _picker.alive or _picker.global_position.distance_to(_pick_from) > 1.0:
				_pick_left = 0.0
				_update_prompt()
			else:
				_pick_left -= delta
				if _pick_left <= 0.0:
					locked = false
					_picker.train("locks")
					Events.say("Schloss geknackt.", 2.0)
					_update_prompt()
					_net()
		if _close_in > 0.0:
			_close_in -= delta
			if _close_in <= 0.0 and is_open:
				var near := false
				for m in host.mission.squad.members:
					near = near or (m.alive and m.global_position.distance_to(global_position) < 10.0)
				if near:
					_close_in = 2.0
				else:
					set_open(false)
		if not _ignore_ready:
			_prepare_ignore()
		if _blocked_wait > 0.0:
			_blocked_wait -= delta
		elif not is_equal_approx(amount, target):
			var prev := amount
			var step := speed * delta
			amount = move_toward(prev, target, step)
			_apply()
			# Original 0x5FF700/0x6F78F0: Flügelvolumen gegen Hindernisse – bei Kollision letzten Schritt zurücknehmen,
			# 200 ms warten, dann erneut (Zustand bleibt „öffnet/schließt“). Hier nur gegen Soldaten (Ebene 2): welche
			# Kollisionsklasse das Original prüft (Maske 2), ist nicht belegt; gegen die Levelgeometrie blieben Flügel mit
			# knapp bemessenem Datenwinkel an Wand-/Zargenflächen hängen (NORMANDY2-Bank).
			if not slide and not _overlaps(_ignore, true, true).is_empty():
				amount = prev
				_apply()
				_blocked_wait = 0.2
				_stop_move_snd()
			if _blocked_wait <= 0.0 and is_equal_approx(amount, target):
				state = 1 if target > 0.0 else 0
				frame.set_meta("actor_state", state)
				_update_prompt()
				_stop_move_snd()
				if state == 0:
					_snd("closed")

	func _apply() -> void:
		if slide:
			frame.transform = Transform3D(base.basis, base.origin + base.basis * axis * amount)
		else:
			frame.transform = base * Transform3D(Basis(axis, sgn * amount), Vector3.ZERO)

	func serialize() -> Dictionary:
		return {"state": state, "amount": amount, "target": target, "locked": locked}

	func deserialize(d: Dictionary) -> void:
		amount = float(d.get("amount", 0.0))
		target = float(d.get("target", amount))
		state = int(d.get("state", 0))
		locked = bool(d.get("locked", locked))
		_apply()
		frame.set_meta("actor_state", state)
		_update_prompt()


# --- Leitern ------------------------------------------------------------------------

func _ladder(e: Dictionary) -> void:
	var t: Array = e.get("top_world", [])
	var b: Array = e.get("bottom_world", [])
	if t.size() != 3 or b.size() != 3:
		stats.missing += 1
		return
	var top := Vector3(t[0], t[1], t[2])
	var bottom := Vector3(b[0], b[1], b[2])
	if top.y < bottom.y:
		var x := top
		top = bottom
		bottom = x
	var p: Dictionary = e.get("params", {})
	var label := text(int(p.get("label_text", 7154)), "Leiter")
	for at_top in [false, true]:
		var l := OrigLadder.new()
		l.name = "Ladder_%s_%s" % [String(e["name"]).validate_node_name(), "top" if at_top else "bottom"]
		l.top = top
		l.bottom = bottom
		l.at_top = at_top
		l.climb_sound = int(p.get("climb_sound", -1))
		l.prompt = "%s: %s" % [label, text(TXT_USE, "Benutzen")]
		mission.dynamic_root.add_child(l)
		l.global_position = top if at_top else bottom
	stats.ladders += 1


class OrigLadder extends Interactable:
	var top: Vector3
	var bottom: Vector3
	var at_top := false
	var climb_sound := -1        ## Akteur Typ 8 +0x174: Kat. 0 „Ladder Metal/Wooden/Stone“

	## Sprossenklang während des Kletterns (je 0,45 s = Annahme)
	func _rung_sounds(s: Soldier, dur: float) -> void:
		if climb_sound < 0:
			return
		var n := maxi(int(dur / 0.45), 1)
		for i in n:
			get_tree().create_timer(i * 0.45, false).timeout.connect(func():
				if is_instance_valid(s):
					OrigAudio.play_group(OrigAudio.CAT_STEP, climb_sound, s.global_position))

	func _ready() -> void:
		super._ready()
		add_to_group("ladders")

	func can_interact(s: Soldier) -> bool:
		return enabled and not s.is_climbing() and absf(s.global_position.y - global_position.y) < 1.6

	func interact(s: Soldier) -> void:
		climb(s)

	## Klettern (Original: Ein-/Ausstieg über Dummies „up“/„down“; Steuerung im Original nicht belegt →
	## Benutzen bzw. Springen an der Leiter klettert ganz hinauf bzw. hinunter, ~1,2 m/s)
	func climb(s: Soldier) -> void:
		var from := s.global_position
		var h := maxf(top.y - bottom.y, 0.5)
		if not at_top:
			var away := Vector3(top.x - from.x, 0, top.z - from.z)
			away = away.normalized() if away.length() > 0.05 else s.forward()
			s.start_path_climb(from, Vector3(top.x, top.y + 0.1, top.z), top + away * 0.7 + Vector3.UP * 0.05, h / 1.2 + 0.5)
			_rung_sounds(s, h / 1.2)
		else:
			_rung_sounds(s, h / 1.6)
			var away2 := Vector3(bottom.x - from.x, 0, bottom.z - from.z)
			away2 = away2.normalized() if away2.length() > 0.05 else -s.forward()
			s.start_path_climb(from, Vector3(bottom.x, bottom.y + 0.1, bottom.z) + away2 * 0.2, bottom + away2 * 0.6 + Vector3.UP * 0.05,
				h / 1.6 + 0.4)
		super.interact(s)


# --- Schalter / Funkgeräte ----------------------------------------------------------

func _switch(e: Dictionary, kind: String) -> void:
	var f := _frame(e)
	if f == null:
		return
	var sw := OrigSwitch.new()
	sw.name = "Switch_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(sw)
	sw.init(self, f, e, kind == "radios")
	_register(e, f, sw)
	stats[kind] += 1


class OrigSwitch extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var state := 1
	var required_item := -1
	var radio := false
	var sound := -1          ## Kat. 1: Schalter +0xD8 „sound“, Funkgerät „active_sound“ (z. B. 50 „Radio active“)

	func init(h: OrigInteractive, f: Node3D, e: Dictionary, is_radio: bool) -> void:
		host = h
		frame = f
		radio = is_radio
		var p: Dictionary = e.get("params", {})
		sound = int(p.get("active_sound" if radio else "sound", -1))
		persistent_id = "oswitch_" + String(e["name"])
		state = clampi(int(p.get("initial_state", 1)), 1, 3) if not radio else int(p.get("state", 1))
		required_item = int(p.get("required_item", -1))
		global_position = OrigInteractive.world_aabb(frame).get_center()
		prompt = "%s: %s" % [OrigInteractive.text(int(p.get("label_text", 7155 if not radio else -1)), "Funkgerät" if radio else "Schalter"),
			OrigInteractive.text(TXT_USE, "Benutzen")]
		_show()

	func can_interact(s: Soldier) -> bool:
		return enabled and host.allowed(s, required_item) and (not radio or state == 1)

	func interact(s: Soldier) -> void:
		if not radio:
			state = 2 if state == 1 else 1
			_show()
		else:
			state = 2       # Original: benutztes Funkgerät -> Zustand 2 (Skripte prüfen _ACTOR_GetState == 2)
			frame.set_meta("actor_state", state)
			Events.say("Funkspruch abgesetzt.", 2.5)
		if sound >= 0:
			OrigAudio.play_group(OrigAudio.CAT_OBJECT, sound, global_position, self)
		Events.emit_noise(global_position, 5.0, s, s.team, &"door")
		host.runtime.notify(frame, "ONUSE")
		super.interact(s)

	func set_actor_state(n: int) -> void:
		state = n
		_show()

	## Original: Kind-Frame „1“/„2“/„3“ = Zustand sichtbar, übrige ausgeblendet
	func _show() -> void:
		frame.set_meta("actor_state", state)
		if radio:
			return
		var digits := 0
		for c in frame.get_children():
			if c is Node3D and String(c.name) in ["1", "2", "3"]:
				digits += 1
		if digits == 0:
			return
		for c in frame.get_children():
			if c is Node3D and String(c.name) in ["1", "2", "3"]:
				(c as Node3D).visible = String(c.name) == str(state)

	func serialize() -> Dictionary:
		return {"state": state}

	func deserialize(d: Dictionary) -> void:
		state = int(d.get("state", state))
		_show()


# --- Sprengplätze -------------------------------------------------------------------

func _explosive(e: Dictionary) -> void:
	var f := _frame(e)
	if f == null:
		return
	var x := OrigExplosive.new()
	x.name = "Explosive_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(x)
	x.init(self, f, e)
	_register(e, f, x)
	stats.explosives += 1


class OrigExplosive extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var state := 0            ## 0 frei, 1 Ladung platziert, 2 explodiert, 3 versteckt
	var required_item := 68
	var timer := 15.0
	var has_timer := true
	var radius := 10.0
	var strength := 1.0
	var label := "Sprengplatz"
	var countdown := -1.0
	var _work := 0.0
	var _worker: Soldier
	var _work_kind := ""
	var explosion_sound := 16     ## Akteur Typ 22 +0xA8 (Kat. 6); Standard „Explosion Naloz Ext“

	func init(h: OrigInteractive, f: Node3D, e: Dictionary) -> void:
		host = h
		frame = f
		var p: Dictionary = e.get("params", {})
		persistent_id = "oexpl_" + String(e["name"])
		if int(p.get("explosion_sound", -1)) >= 0:
			explosion_sound = int(p["explosion_sound"])
		required_item = int(p.get("required_item", 68))
		has_timer = bool(p.get("has_timer", true))
		timer = float(p.get("timer_ms", 15000)) / 1000.0
		var rr := float(p.get("radius", p.get("radius_?", 10.0)))
		radius = clampf(rr / 1000.0 if rr > 100.0 else rr, 3.0, 30.0)
		strength = float(p.get("strength", p.get("strength_?", 12000)))
		label = OrigInteractive.text(int(p.get("label_text", 7161)), "Sprengplatz")
		global_position = OrigInteractive.world_aabb(frame).get_center()
		state = 3 if bool(p.get("hidden", false)) else (1 if bool(p.get("armed_at_start", false)) else 0)
		_show()

	func can_interact(s: Soldier) -> bool:
		if not enabled or state == 2 or state == 3 or _work > 0.0:
			return false
		return state == 1 or host.allowed(s, required_item)

	func interact(s: Soldier) -> void:
		# Original: Anbringen 3 s (Text 7072), Entschärfen 4 s (Text 7075)
		_worker = s
		_work_kind = "plant" if state == 0 else "defuse"
		_work = 3.0 if state == 0 else 4.0
		Events.say(OrigInteractive.text(7072 if state == 0 else 7075, "Bringt Sprengstoff an" if state == 0 else "Entschärft") + " …", _work)
		OrigAudio.play_group(OrigAudio.CAT_MISC, OrigAudio.MISC_BOMB, global_position, self)   # „Player01 Bomb manipulation“
		super.interact(s)

	func _physics_process(delta: float) -> void:
		if _work > 0.0:
			if not is_instance_valid(_worker) or not _worker.alive or _worker.global_position.distance_to(global_position) > 3.0:
				_work = 0.0
			else:
				_work -= delta
				if _work <= 0.0:
					if _work_kind == "plant":
						OrigInteractive.take_item(_worker, required_item)
						set_actor_state(1)
						Events.say("%s: Ladung angebracht%s." % [label, " (%d s)" % int(timer) if has_timer else ""], 3.0)
					else:
						set_actor_state(0)
		if countdown > 0.0:
			countdown -= delta
			if countdown <= 0.0:
				detonate()

	func set_actor_state(n: int) -> void:
		state = n
		countdown = timer if n == 1 and has_timer else -1.0
		_show()

	func detonate() -> void:
		state = 2
		countdown = -1.0
		var pos := global_position
		var dmg := clampf(strength / 50.0, 150.0, 1200.0)
		host.runtime._explosion(pos, radius, dmg, [OrigAudio.CAT_EXPLOSION, explosion_sound])
		_show()

	## Original-Marker: „explosive_on“ (Ladung) / „explosive_off“ (frei) im Modell
	func _show() -> void:
		frame.set_meta("actor_state", state)
		prompt = "%s: %s" % [label, OrigInteractive.text(TXT_PLANT if state == 0 else TXT_DEFUSE, "Sprengstoff anbringen" if state == 0 else "Entschärfen")]
		for c in frame.find_children("*", "Node3D", true, false):
			var nm := String(c.name).to_lower()
			if nm.begins_with("explosive_on"):
				(c as Node3D).visible = state == 1
			elif nm.begins_with("explosive_off"):
				(c as Node3D).visible = state == 0
		frame.visible = state != 3

	func serialize() -> Dictionary:
		return {"state": state, "countdown": countdown}

	func deserialize(d: Dictionary) -> void:
		state = int(d.get("state", state))
		countdown = float(d.get("countdown", -1.0))
		_show()


# --- Zerstörbare Objekte (Typ 25) ---------------------------------------------------

func _destructible(e: Dictionary) -> void:
	var f := _frame(e)
	if f == null:
		return
	var x := OrigDestructible.new()
	x.name = "Destructible_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(x)
	x.init(self, f, e)
	_register(e, f, x)
	stats.destructibles += 1


class OrigDestructible extends Node3D:
	var host: OrigInteractive
	var frame: Node3D
	var health := 1000.0
	var damage := 0.0
	var destroyed := false
	var persistent_id := ""
	var label := ""
	var destroy_sound := 0        ## Akteur Typ 25 +0xA8 (Kat. 6, z. B. 2 „Explosion Dirt“, 23/24 „Cisterna“)

	func init(h: OrigInteractive, f: Node3D, e: Dictionary) -> void:
		host = h
		frame = f
		add_to_group("destructibles")
		add_to_group("persistent")
		persistent_id = "odestr_" + String(e["name"])
		var p: Dictionary = e.get("params", {})
		destroy_sound = int(p.get("destroy_sound", 0))
		health = float(p.get("health", 1000.0))
		label = OrigInteractive.text(int(p.get("label_text", -1)), "")
		global_position = OrigInteractive.world_aabb(frame).get_center()
		frame.set_meta("actor_state", 1)
		# Treffer an den Kollisionskörpern des Objekts werden hierher umgeleitet (Ballistik: hit_proxy)
		for b in frame.find_children("*", "StaticBody3D", true, false):
			b.set_meta("hit_proxy", self)

	## Schaden in Originaleinheiten (Spielschaden ×10, vgl. weapon_db: Originalschaden/10).
	## Gewehrkugeln wirken nur zu 25 % (ANNAHME – Original-Trefferarten nicht belegt), Explosionen voll.
	func on_bullet_hit(d: float, by: Node) -> void:
		host.runtime.notify(frame, "ONHIT")      # Originalskript-Ereignis OnHit (z. B. CZECH1 Lampen)
		_add(d * 10.0 * 0.25, by)

	func on_explosion(d: float, by: Node) -> void:
		host.runtime.notify(frame, "ONHIT")
		_add(d * 10.0, by)

	func _add(v: float, _by: Node) -> void:
		if destroyed or health < 0.0:
			return       # health < 0: nur per Skript zerstörbar
		damage += v
		if damage > health:
			destroy()

	func set_actor_state(n: int) -> void:
		if n != 666 and not destroyed:
			destroy()

	func destroy() -> void:
		destroyed = true
		var snd: Array = [OrigAudio.CAT_EXPLOSION, destroy_sound] if destroy_sound >= 0 else []
		Effects.explosion(global_position, 4.0, snd)
		frame.set_meta("actor_state", 0)
		# Original: Zerstörungsanimation (.i3d, nicht dekodiert) – Ersatz: Original-Frame ausblenden
		frame.visible = false
		for b in frame.find_children("*", "StaticBody3D", true, false):
			(b as StaticBody3D).collision_layer = 0
		host.runtime.notify(frame, "ONDEATH")

	func serialize() -> Dictionary:
		return {"destroyed": destroyed, "damage": damage}

	func deserialize(d: Dictionary) -> void:
		damage = float(d.get("damage", 0.0))
		if bool(d.get("destroyed", false)) and not destroyed:
			destroyed = true
			frame.visible = false
			frame.set_meta("actor_state", 0)


# --- Kisten, Foto- und Dokumentplätze ------------------------------------------------

func _crate(e: Dictionary) -> void:
	var f := _frame(e)
	if f == null:
		return
	var c := OrigCrate.new()
	c.name = "Crate_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(c)
	c.init(self, f, e)
	_register(e, f, c)
	stats.crates += 1


class OrigCrate extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var take_limit := 20
	var taken := {}            ## Soldat -> Anzahl Entnahmen
	var equipment := false
	var items: Array = []

	var destroyed := false

	## Original: Kisten-Skripte reagieren auf OnDeath (BURMA1 bu1_ondeath*.scr) – durch Explosionen zerstörbar
	func on_bullet_hit(d: float, by: Node) -> void:
		host.runtime.notify(frame, "ONHIT")
		if _is_target():
			on_explosion(maxf(d, 20.0), by)

	## Zielscheibe = Kiste, deren Skript auf OnDeath wartet (Original: Treffer → OnDeath)
	func _is_target() -> bool:
		var vm = host.runtime.vm_of.get(frame)
		return vm != null and vm.code.handlers.has("ONDEATH")

	func on_explosion(d: float, _by: Node) -> void:
		if destroyed or d < 20.0:
			return
		destroyed = true
		enabled = false
		frame.visible = false
		frame.set_meta("actor_state", 0)
		OrigAudio.play_group(OrigAudio.CAT_OBJECT, 12, global_position)    # Kat. 1 „Crate Damaged“
		host.runtime.notify(frame, "ONDEATH")

	func init(h: OrigInteractive, f: Node3D, e: Dictionary) -> void:
		host = h
		frame = f
		add_to_group("destructibles")
		for b in frame.find_children("*", "StaticBody3D", true, false):
			b.set_meta("hit_proxy", self)
		var p: Dictionary = e.get("params", {})
		persistent_id = "ocrate_" + String(e["name"])
		take_limit = maxi(int(p.get("take_limit", 20)), 1)
		equipment = bool(p.get("equipment_box", false))
		items = (p.get("items_list_a", []) as Array) + (p.get("items_list_b", []) as Array)
		global_position = OrigInteractive.world_aabb(frame).get_center()
		prompt = "%s: %s" % [OrigInteractive.text(int(p.get("label_text", 1305)), "Kiste"), OrigInteractive.text(TXT_AMMO, "Munition nehmen")]

	func can_interact(s: Soldier) -> bool:
		return enabled and int(taken.get(s.persistent_id, 0)) < take_limit

	## Munitionskiste: je Benutzung ein Magazin für jede getragene Waffe (Original: Menü „Munition nehmen“
	## bis take_limit); Ausrüstungskiste: Gegenstände der Liste ins Originalinventar
	func interact(s: Soldier) -> void:
		taken[s.persistent_id] = int(taken.get(s.persistent_id, 0)) + 1
		OrigAudio.play_group(OrigAudio.CAT_OBJECT, OrigAudio.OBJ_CRATE_OPEN, global_position, self)   # „Crate Opened“
		if equipment and not items.is_empty():
			var inv: Array = s.get_meta("orig_items", [])
			for it in items:
				if int(it) >= 0:
					inv.append(int(it))
					if int(it) in SAS.MEDKITS:
						s.medkits += 1
			s.set_meta("orig_items", inv)
			Events.say("Ausrüstung entnommen.", 2.0)
		else:
			var got := 0
			for w in s.weapons:
				if w != null and w.data.slot != WeaponData.Slot.GRENADE:
					got += w.add_ammo(w.data.magazine_size)
			var names: Array = []
			for it in items:
				if int(it) >= 0:
					names.append(OrigInteractive.give_item(s, int(it)))
			Events.say("Munition entnommen (%d Schuss)%s." % [got, (": " + ", ".join(names)) if not names.is_empty() else ""], 2.0)
		super.interact(s)

	func serialize() -> Dictionary:
		return {"taken": taken}

	func deserialize(d: Dictionary) -> void:
		taken = d.get("taken", {})


func _place(e: Dictionary, kind: String, action_text: int, item: int) -> void:
	var f := _frame(e)
	if f == null:
		return
	var pl := OrigPlace.new()
	pl.name = "Place_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(pl)
	pl.init(self, f, e, action_text, item, kind == "documents")
	_register(e, f, pl)
	stats[kind] += 1


## Fotoplatz (15, benötigt Gegenstand 229 „Fotoaparat“) / Dokumentplatz (23, Gegenstand wird abgelegt)
class OrigPlace extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var item := -1
	var consume := false
	var state := 0

	func init(h: OrigInteractive, f: Node3D, e: Dictionary, action_text: int, it: int, documents: bool) -> void:
		host = h
		frame = f
		item = it
		consume = documents
		persistent_id = "oplace_" + String(e["name"])
		var p: Dictionary = e.get("params", {})
		global_position = OrigInteractive.world_aabb(frame).get_center()
		prompt = "%s: %s" % [OrigInteractive.text(int(p.get("label_text", -1)), "Ziel"),
			OrigInteractive.text(action_text, "Dokumente platzieren" if documents else "Foto machen")]
		frame.set_meta("actor_state", 0)

	func can_interact(s: Soldier) -> bool:
		return enabled and state == 0 and host.allowed(s, item)

	func interact(s: Soldier) -> void:
		if consume:
			OrigInteractive.take_item(s, item)
		else:
			OrigAudio.play_group(OrigAudio.CAT_OBJECT, OrigAudio.OBJ_FOTO, global_position, self)   # Kat. 1 „Foto“
		state = 1
		frame.set_meta("actor_state", 1)
		host.runtime.notify(frame, "ONUSE")
		Events.say("Erledigt: %s" % prompt, 2.5)
		super.interact(s)

	func set_actor_state(n: int) -> void:
		state = n
		frame.set_meta("actor_state", n)

	func serialize() -> Dictionary:
		return {"state": state}

	func deserialize(d: Dictionary) -> void:
		set_actor_state(int(d.get("state", 0)))


# --- Waffenstellungen (Typ 21) -------------------------------------------------------

## Modellname -> Waffe (Originalnummer bzw. eigene ID) und Haltung des Schützen [ANNAHME nach Modellnamen]
const EMPLACEMENT_WEAPONS := [["w_mg42lie", 33, 2], ["w_mg42", 33, 1], ["w_97crouch", 30, 1], ["w_97", 30, 0],
	["la_flak4x38", "flak38", 0], ["la_flak", "flak38", 0], ["la_boatgun", 37, 0], ["la_pancer_vez", 48, 0]]


## Waffe, die eine Munitionsart verschießt (items.sav: Waffe +ammo_item), z. B. 216 -> MG 42, 218 -> Browning 1919
## DUO (Bootsgeschütz), 219 -> Bunker-MG, 220 -> 17-mm-Kanone, 209 -> Flak 38, 213 -> KwK 40 (Tiger) [O]
static func weapon_for_ammo(ammo: int) -> int:
	item_info(0)
	var best := -1
	for id in _items:
		var it: Dictionary = _items[id]
		if String(it.get("kind", "")) == "weapon" and int(it.get("ammo_item", -1)) == ammo:
			# „TMP“-Einträge (Flak TMP) sind Entwickler-Varianten; die reguläre Waffe bevorzugen
			if best < 0 or String(_items[best].get("name", "")).contains("TMP"):
				best = int(id)
	return best


## Bordwaffen und Geschütze aus items.sav: Schusswaffen über WeaponDB.from_orig(…, mounted); Werfer (Flak, Kanonen,
## Pak) als Geschoss mit Aufschlagzünder: Feuerintervall interval_ms, Nachladen reload_ms, Geschwindigkeit velocity,
## Magazin = Schuss je Munitionsgegenstand [O]; Explosionsstärke und -radius des Geschosses = Werfer-Verhalten
## Laufzeit +0x5C/+0x60 (items.json „strength“/„blast_radius“, Datensatz +0xDC/+0xE0; hd2.exe 0x449290: Direkttreffer
## Fahrzeug = Damage(7, Stärke), Explosion 0x451990) [B] – z. B. KwK 40 4000/5,5 m, KwK 36 3250/6 m, Flak 38 1400/3 m;
## Schaden im Nachbau zotti/10 wie WeaponDB. Ohne diese Felder (alter Cache): bisherige Annahme damage_f3/10 bzw. 300 [E]
static func heavy_weapon(item: int) -> WeaponData:
	if item < 0:
		return null
	var wd := WeaponDB.from_orig(item, true)
	if wd:
		return wd
	var gid := StringName("o_%d" % item)
	if gid in WeaponDB.all_ids():
		return WeaponDB.get_weapon(gid)
	var info := item_info(item)
	var bs: Array = info.get("behaviours", [])
	if bs.is_empty() or String((bs[0] as Dictionary).get("type", "")) != "projectile_launcher":
		return null
	var b: Dictionary = bs[0]
	var interval := maxf(float(b.get("interval_ms", 1000.0)) / 1000.0, 0.1)
	var cannon := interval >= 1.0
	var rounds := int(item_info(int(info.get("ammo_item", -1))).get("rounds", 1.0))
	var dmg := float(b.get("damage_f3", 99.0))
	var strength := float(b.get("strength", -1.0))
	var radius := float(b.get("blast_radius", -1.0))
	var damage := 300.0 if cannon or dmg <= 99.0 else dmg / 10.0
	if strength > 0.0:
		damage = strength / 10.0
	if radius <= 0.0:
		radius = maxf(float(b.get("f15", 0.0)), 3.0 if not cannon else 4.0)
	return WeaponDB._make({id = gid, display_name = String(info.get("name", gid)), slot = WeaponData.Slot.PRIMARY,
		action = WeaponData.Action.ROCKET, magazine_size = maxi(rounds, 1), start_magazines = 6,
		rpm = 60.0 / interval, reload_time = float(b.get("reload_ms", 3000.0)) / 1000.0,
		muzzle_velocity = clampf(float(b.get("velocity", 250.0)), 40.0, 1000.0),
		damage = damage, blast_radius = radius,
		spread_hip = 0.6, spread_aim = 0.3, recoil_pitch = 2.0 if cannon else 0.8, recoil_yaw = 0.3, spread_per_shot = 0.1,
		noise_radius = 400.0 if cannon else 250.0, weight = float(info.get("weight_kg", 500.0)), model_length = 2.0, aim_fov = 30.0})


func _emplacement(e: Dictionary) -> void:
	var f := _frame(e)
	if f == null:
		return
	var model := String(e.get("model", "")).to_lower()
	var wid = null
	var stance := 1
	for row in EMPLACEMENT_WEAPONS:
		if model.begins_with(row[0]):
			wid = row[1]
			stance = row[2]
			break
	# Waffe über die Munition im items.dat-Inventar der Stellung (Original: Stellung verschießt ihre Munition)
	var wd: WeaponData = null
	for it in e.get("inventory", []):
		var ammo := int(it.get("item", -1)) if it is Dictionary else int(it)
		var wi := weapon_for_ammo(ammo)
		if wi < 0 and item_info(ammo).get("kind", "") == "weapon":
			wi = ammo
		wd = heavy_weapon(wi)
		if wd:
			break
	# Originalmodell: Rohr-Frame BARREL00_00 trägt „itemid<n>,up,down,left,right“ (4DS-Frameparameter) [B Daten]
	var rig: Dictionary = rig_params(orig.mission_dir + "/models/" + model + ".glb") if orig else {}
	if int(rig.get("itemid", -1)) >= 0:
		var bw := heavy_weapon(int(rig["itemid"]))
		if bw:
			wd = bw
	if wd == null and wid != null:
		wd = WeaponDB.from_orig(int(wid), true) if wid is int else WeaponDB.get_weapon(StringName(wid))
	if wd == null:
		return
	if wid == null:
		stance = 1 if model.contains("crouch") else (2 if model.contains("lie") else 0)
	var x := OrigEmplacement.new()
	x.name = "Emplacement_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(x)
	x.init(self, f, e, wd, stance)
	x.model_path = orig.mission_dir + "/models/" + model + ".glb" if orig else ""
	x.setup_rig(rig)
	_register(e, f, x)
	stats.emplacements += 1


static var _rig_cache := {}


## Parameter des Rohr-Frames einer Stellung aus dem glTF-Export (extras.params des 4DS-Frames BARRELnn_xx):
## itemid (Waffe, items.sav), up/down/left/right (Schwenkgrenzen in Grad) [B Daten, Bedeutung der Grenzen P]
static func rig_params(path: String) -> Dictionary:
	if _rig_cache.has(path):
		return _rig_cache[path]
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f and f.get_length() > 20 and f.get_32() == 0x46546C67:
		f.get_32()
		f.get_32()
		var ln := f.get_32()
		f.get_32()
		var j = JSON.parse_string(f.get_buffer(ln).get_string_from_utf8())
		if typeof(j) == TYPE_DICTIONARY:
			for n in j.get("nodes", []):
				var nm := String(n.get("name", "")).to_upper()
				var ex = n.get("extras", {})
				if typeof(ex) != TYPE_DICTIONARY:
					continue
				# Sitz-Frame „SEAT<Ziffern>“: erste Ziffer = Haltung des Bedieners (1 sitzend, 2 stehend, 3 hockend,
				# 6 liegend; Daten aller Stellungsmodelle, Bit 8 = Geschütz, re_notes_ju88 §2.5) [B Daten, P Deutung]
				# Klänge am Seitenrichtungs-Frame HORT00: SOUNDM Bewegung (Schleife), SOUNDS Stopp; Kat. 3 (0x4C6E50) [B]
				if nm.begins_with("HORT") and not out.has("soundm"):
					var hp := String(ex.get("params", "")).to_upper()
					for key in ["SOUNDM", "SOUNDS"]:
						var at := hp.find(key)
						if at >= 0:
							var digits := ""
							var q: int = at + String(key).length()
							while q < hp.length() and hp[q].is_valid_int():
								digits += hp[q]
								q += 1
							if digits != "":
								out[key.to_lower()] = int(digits)
					continue
				if nm.begins_with("SEAT") and not out.has("seat"):
					var sp := String(ex.get("params", "")).to_upper()
					if sp.begins_with("SEAT") and sp.length() > 4 and sp.substr(4, 1).is_valid_int():
						out["seat"] = int(sp.substr(4, 1))
					continue
				if not nm.begins_with("BARREL") or out.has("itemid"):
					continue
				for tok in String(ex.get("params", "")).to_lower().replace("matid", ",matid").split(",", false):
					var t := String(tok).strip_edges()
					for key in ["itemid", "up", "down", "left", "right"]:
						if t.begins_with(key) and t.substr(key.length()).is_valid_int():
							out[key] = int(t.substr(key.length()))
	_rig_cache[path] = out
	return out


class OrigEmplacement extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var data: WeaponData
	var stance := 1
	var ammo_mags := 0
	## Originalmodell der Stellung: Seitenrichtung HORT00, Höhenrichtung VERT00 (Kind von HORT), Rohr BARREL00_00,
	## Mündung SHDUM00, Sitz SEAT00 (Konvention wie Fahrzeugtürme, vehicle.gd); Grenzen aus rig_params
	var hort: Node3D
	var vert: Node3D
	var muzzle: Node3D
	var seat: Node3D
	var base_h := Transform3D()
	var base_v := Transform3D()
	var lim := {"up": 30.0, "down": 30.0, "left": 60.0, "right": 60.0}
	var aim_yaw := 0.0              ## aktuelle Rohrdrehung relativ zur Stellung (rad, + = links)
	var aim_pitch := 0.0            ## + = hoch

	## Drehachsen des Originalmodells suchen (nur bei Stellungen aus interactive.json; eigene Kartenwaffen
	## wie Flak-Unterklassen eigener Karten steuern ihr Modell selbst)
	func setup_rig(rig: Dictionary) -> void:
		for k in ["up", "down", "left", "right"]:
			if rig.has(k):
				lim[k] = float(rig[k])
		snd_m = int(rig.get("soundm", -1))
		snd_s = int(rig.get("sounds", -1))
		for n in frame.find_children("*", "Node3D", true, false):
			var nm := String(n.name).to_upper()
			if hort == null and nm.begins_with("HORT"):
				hort = n
			elif vert == null and nm.begins_with("VERT"):
				vert = n
			elif muzzle == null and nm.begins_with("SHDUM"):
				muzzle = n
			elif seat == null and nm.begins_with("SEAT"):
				seat = n
		if hort:
			base_h = hort.transform
		if vert:
			base_v = vert.transform
		if seat:
			global_position = seat.global_position + Vector3.UP * 0.5

	## Mündung des Originalmodells (Schussursprung, Soldier._fire_shot)
	func shot_origin() -> Vector3:
		if is_instance_valid(muzzle):
			return muzzle.global_position
		return gunner.eye_position() + gunner.aim_direction() * 1.0 if is_instance_valid(gunner) else frame.global_position

	## Eigene Kollision der Stellung nicht treffen
	func shot_exclusions() -> Array[RID]:
		var out: Array[RID] = []
		for b in frame.find_children("*", "CollisionObject3D", true, false):
			out.append((b as CollisionObject3D).get_rid())
		return out

	## Rohr folgt dem Blick des Schützen innerhalb der Originalgrenzen; der Blick wird auf die Grenzen gesetzt,
	## damit Schuss und Rohr übereinstimmen (Spieler, KI, Netzfiguren)
	func _aim_rig() -> void:
		if hort == null and vert == null:
			return
		var base_yaw := frame.global_basis.get_euler().y
		var rel := wrapf(gunner.look_yaw - base_yaw, -PI, PI)
		rel = clampf(rel, -deg_to_rad(lim["right"]), deg_to_rad(lim["left"]))
		var pit := clampf(gunner.look_pitch, -deg_to_rad(lim["down"]), deg_to_rad(lim["up"]))
		gunner.look_yaw = base_yaw + rel
		gunner.look_pitch = pit
		_rig_sound(absf(rel - aim_yaw) + absf(pit - aim_pitch) > 0.0005, get_physics_process_delta_time())
		aim_yaw = rel
		aim_pitch = pit
		if hort:
			hort.transform = Transform3D(Basis(Vector3.UP, rel) * base_h.basis, base_h.origin)
		if vert:
			var b := base_v.basis * Basis(Vector3.RIGHT, pit)
			if hort == null:
				b = Basis(Vector3.UP, rel) * b
			# Rückstoß: Rohr fährt beim Schuss bis 3 cm zurück (lokal +Z), Hände folgen den Griffen [E]
			vert.transform = Transform3D(b, base_v.origin + b * Vector3(0, 0, 0.03 * _kick))

	## Richtklänge wie Fahrzeugtürme (Vehicle._turret_sound, hd2.exe 0x4C2580): Bewegung → SOUNDM-Schleife (z. B. 60
	## „All Cannons work“, 78 „All Machingun work“), > 300 ms Stillstand → Schleife aus, SOUNDS (z. B. 79) [B]
	var snd_m := -1
	var snd_s := -1
	var _snd_on := false
	var _snd_still := 0.0
	var _snd_loop: Node
	var _snd_stop: Node

	func _rig_sound(moving: bool, delta: float) -> void:
		if snd_m < 0:
			return
		var src: Node3D = hort if hort else (vert if vert else frame)
		if moving:
			_snd_still = 0.0
			if not _snd_on:
				_snd_on = true
				if is_instance_valid(_snd_stop):
					_snd_stop.queue_free()
				_snd_loop = OrigAudio.play_group(3, snd_m, src.global_position, src, 1.0, true)
			return
		_snd_still += delta * 1000.0
		if _snd_on and _snd_still > 300.0:
			_snd_on = false
			if is_instance_valid(_snd_loop):
				_snd_loop.queue_free()
			if snd_s >= 0:
				_snd_stop = OrigAudio.play_group(3, snd_s, src.global_position, src)

	## Rohrrichtung in Weltkoordinaten (Modelle: Lauf entlang −Z)
	func barrel_dir() -> Vector3:
		var p: Node3D = vert if vert else hort
		return -(p.global_basis.z.normalized()) if p else -frame.global_basis.z

	# --- Bedienhaltung des Schützen (docs/re_notes_weapons.md §11) ------------------------------------------
	## Original: Figur am Sitz-Frame SEAT00, Ganzkörper-Clip aus TABLES\anim.sav (Tabelle 0x1B36C) je Haltungsziffer
	## des SEAT-Parameters (1 sitzend (flaksed, 2 stehend (mg42_stand/(w97_stand, 3 hockend (mg42crouch/(w97_crouch,
	## 6 liegend (mg42lie) [B Daten]. Die 5–6 Schlüsselbilder dieser Clips sind ein Seitenschwenk (Bild 0 Figur
	## 0,6 m rechts … Bild 5 0,5 m links) → Bild nach Seitenrichtung des Rohrs [P]. Hände per IK an RWS/LWS.
	const EmplacementIK := preload("res://src/actors/emplacement_ik.gd")
	var model_path := ""            ## glb des Stellungsmodells (Haltungsziffer aus rig_params), sonst Meta „source“
	var pose_seat: Node3D           ## SEAT00 (Figurenursprung)
	var grip_r: Node3D              ## RWS
	var grip_l: Node3D              ## LWS
	var pose_hort: Node3D           ## Seitenrichtungs-Frame (Unterklassen eigener Karten drehen ihn selbst)
	var pose_hort_rest := Basis()
	var pose_ik: SkeletonModifier3D
	var _pose_clip := ""
	var _kick := 0.0                ## Rückstoß 0..1 (Rohr fährt kurz zurück, Hände folgen den Griffen)
	var _trans_t := 1.0             ## Auf-/Absteigen: Überblendung Figur Laufposition ↔ Sitz (0..1)
	var _trans_from := Transform3D()   ## Weltlage der Figur vor dem Besetzen
	var _fig_rest := Transform3D()     ## Ruhelage der Figur im SoldierModel (nach dem Verlassen wiederhergestellt)

	func _pose_nodes() -> void:
		for n in frame.find_children("*", "Node3D", true, false):
			var nm := String(n.name).to_upper()
			if pose_seat == null and nm.begins_with("SEAT"):
				pose_seat = n
			elif grip_r == null and nm == "RWS":
				grip_r = n
			elif grip_l == null and nm == "LWS":
				grip_l = n
			elif pose_hort == null and nm.begins_with("HORT"):
				pose_hort = n
		if pose_hort:
			pose_hort_rest = pose_hort.transform.basis

	## Haltungsclip der Figur (export_characters.py „emp_*“): Haltungsziffer des SEAT-Frames, Modellname als Rückfall
	func pose_clip() -> String:
		if _pose_clip != "":
			return _pose_clip
		var path := model_path if model_path != "" else String(frame.get_meta("source", ""))
		var nm := path.get_file().to_lower()
		var digit: int = int(OrigInteractive.rig_params(path).get("seat", -1)) if path != "" else -1
		if digit < 0:
			digit = 1 if nm.contains("flak") else (6 if nm.contains("lie") else (3 if nm.contains("crouch") else 2))
		var w97 := nm.begins_with("w_97")
		match digit:
			1:
				_pose_clip = "emp_flaksed"
			3:
				_pose_clip = "emp_w97_crouch" if w97 else "emp_mg42crouch"
			6:
				_pose_clip = "emp_mg42lie"
			_:
				_pose_clip = "emp_w97_stand" if w97 else "emp_mg42_stand"
		return _pose_clip

	## Seitenschwenk des Rohrs gegenüber der Ruhelage (rad, + = links)
	func pose_yaw() -> float:
		if pose_hort == null:
			return aim_yaw
		var f0 := -(pose_hort_rest.z)
		var f1 := -(pose_hort.transform.basis.z)
		return atan2(f0.cross(f1).y, f0.dot(f1))

	## Clipzeit nach Seitenrichtung: Mittelbild 3 von 5 (0,12 s) bei geradeaus, Bild 5 = ganz links, 0 = ganz rechts
	func pose_seek(length: float) -> float:
		if length <= 0.15:
			return 0.0          # (flaksed: Sitz dreht mit der Lafette, ein Standbild
		var c := length * 0.6
		var y := pose_yaw()
		# Schwenkbereich des Clips = Grenzen des Original-Rohrframes (auch wenn eine Karte enger begrenzt)
		var path := model_path if model_path != "" else String(frame.get_meta("source", ""))
		var rp: Dictionary = OrigInteractive.rig_params(path) if path.ends_with(".glb") else {}
		var l: float = float(rp.get("left", lim["left"]))
		var r: float = float(rp.get("right", lim["right"]))
		if y >= 0.0:
			return c + clampf(y / deg_to_rad(maxf(l, 1.0)), 0.0, 1.0) * (length - c)
		return c - clampf(-y / deg_to_rad(maxf(r, 1.0)), 0.0, 1.0) * c

	func _pose_begin(s: Soldier) -> void:
		if pose_seat == null and grip_r == null:
			_pose_nodes()
		var m := s.model
		if m == null or not is_instance_valid(m.orig_figure):
			return
		_fig_rest = m.orig_figure.transform
		_fig_rest.basis = Basis.from_euler(Vector3(0, 0, 0)).scaled(_fig_rest.basis.get_scale())   # ohne Anschlagdrehung
		var ap := m.orig_figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation(pose_clip()):
			ap.get_animation(pose_clip()).loop_mode = Animation.LOOP_LINEAR   # Standbild per seek, nie „beendet“
		m.play_full(pose_clip())
		var sk_list := m.orig_figure.find_children("*", "Skeleton3D", true, false)
		if sk_list.is_empty():
			return
		var sk := sk_list[0] as Skeleton3D
		pose_ik = EmplacementIK.new()
		pose_ik.name = "EmplacementIK"
		sk.add_child(pose_ik)
		pose_ik.call("setup", sk, m.orig_figure.find_child("hw1", true, false), m.orig_figure.find_child("hw2", true, false), grip_r, grip_l)
		if not s.shot_fired.is_connected(_on_gunner_shot):
			s.shot_fired.connect(_on_gunner_shot)

	func _pose_end(s: Soldier) -> void:
		if is_instance_valid(pose_ik):
			pose_ik.queue_free()
		pose_ik = null
		if is_instance_valid(s):
			if s.shot_fired.is_connected(_on_gunner_shot):
				s.shot_fired.disconnect(_on_gunner_shot)
			var m := s.model
			if m and is_instance_valid(m.orig_figure):
				m.play_full("")
				m.set("full_seek", -1.0)
				var ap := m.orig_figure.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap:
					ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE   # Standbild-Modus aus (auch beim Tod)
				# Absteigen: Figur gleitet in 0,35 s vom Sitz zurück an den Soldaten (Clip blendet 0,2 s über)
				var fig := m.orig_figure
				var from := fig.global_position
				fig.transform = _fig_rest
				var to := fig.position
				fig.global_position = from
				fig.create_tween().tween_property(fig, "position", to, 0.35).set_trans(Tween.TRANS_SINE)

	func _on_gunner_shot(_w) -> void:
		_kick = 1.0

	var _cam_fpv: Node3D
	## 1. Person: Dummy CAMERAFPV am Rohr des Stellungsmodells (folgt Schwenk/Neigung), ohne Dummy (Flak) am Kopf der
	## Figur; 3. Person: Drehpunkt über dem Kopf der Figur am Sitz (Kopf + 0,45 m ≈ camera3RD stehend 2,085 m) [P]
	func camera_point(fpv: bool) -> Vector3:
		if fpv:
			if _cam_fpv == null:
				for n in frame.find_children("*", "Node3D", true, false):
					if String(n.name).to_upper() == "CAMERAFPV":
						_cam_fpv = n
						break
			if is_instance_valid(_cam_fpv):
				return _cam_fpv.global_position
		var head := _figure_bone("f")
		if not head.is_finite():
			return Vector3.INF
		var up: float = 0.1 if fpv else 0.45
		# Unter Decken/Dächern (Holzhaus-MG) bleibt der Drehpunkt im Raum, sonst läge die 3.-Person-Kamera
		# über bzw. in der Decke und zeigte nur Holz
		var q := PhysicsRayQueryParameters3D.create(head, head + Vector3.UP * (up + 0.2), 1)
		q.exclude = shot_exclusions()
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			up = minf(up, maxf(head.distance_to(hit["position"]) - 0.2, 0.0))
		return head + Vector3.UP * up

	## Clipzeit, deren Handmitte (hw1/hw2) der Mitte der Griffe RWS/LWS am nächsten liegt (Skelettraum der Figur am
	## Sitz): das Schwenkbild ergibt sich so aus der tatsächlichen Kolbenlage, auch bei kartenspezifischen Grenzen.
	## −1 = keine Griffe/Hände (dann pose_seek nach Winkel)
	static var _hand_tables := {}
	func _fit_seek(fig: Node3D, anim: Animation, clip: String) -> float:
		if not is_instance_valid(grip_r) or not is_instance_valid(grip_l) or not is_instance_valid(pose_ik):
			return -1.0
		var sk := pose_ik.get_parent() as Skeleton3D
		var hr := fig.find_child("hw1", true, false) as Node3D
		var hl := fig.find_child("hw2", true, false) as Node3D
		if sk == null or hr == null or hl == null:
			return -1.0
		var key := "%s|%s" % [clip, String(fig.get_meta("figure_model", fig.name))]
		if not _hand_tables.has(key):
			_hand_tables[key] = _hand_table(sk, anim, hr.transform.origin, hl.transform.origin)
		var target := sk.global_transform.affine_inverse() * ((grip_r.global_position + grip_l.global_position) * 0.5)
		var best := -1.0
		var best_d := INF
		for e in _hand_tables[key]:
			var d := (e[1] as Vector3).distance_squared_to(target)
			if d < best_d - 0.000001:
				best_d = d
				best = float(e[0])
		return best

	## Handmitte je Clipzeit (41 Stützstellen) per Vorwärtskinematik aus den Spuren des Clips
	static func _hand_table(sk: Skeleton3D, anim: Animation, off_r: Vector3, off_l: Vector3) -> Array:
		var pos_tr := {}
		var rot_tr := {}
		for i in anim.get_track_count():
			var b := sk.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
			if b < 0:
				continue
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				pos_tr[b] = i
			elif anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				rot_tr[b] = i
		var jr := sk.find_bone("j")
		var jl := sk.find_bone("n")
		var out := []
		if jr < 0 or jl < 0:
			return out
		for k in 41:
			var t := anim.length * float(k) / 40.0
			var cache := {}
			var mid := (_bone_at(sk, anim, jr, t, pos_tr, rot_tr, cache) * off_r + _bone_at(sk, anim, jl, t, pos_tr, rot_tr, cache) * off_l) * 0.5
			out.append([t, mid])
		return out

	static func _bone_at(sk: Skeleton3D, anim: Animation, b: int, t: float, pos_tr: Dictionary, rot_tr: Dictionary, cache: Dictionary) -> Transform3D:
		if cache.has(b):
			return cache[b]
		var rest := sk.get_bone_rest(b)
		var p := rest.origin
		var q := rest.basis.get_rotation_quaternion()
		if pos_tr.has(b):
			p = anim.position_track_interpolate(pos_tr[b], t)
		if rot_tr.has(b):
			q = anim.rotation_track_interpolate(rot_tr[b], t)
		var x := Transform3D(Basis(q).scaled(rest.basis.get_scale()), p)
		var par := sk.get_bone_parent(b)
		if par >= 0:
			x = _bone_at(sk, anim, par, t, pos_tr, rot_tr, cache) * x
		cache[b] = x
		return x

	## Weltlage eines Figurknochens des Schützen (INF ohne Originalfigur)
	func _figure_bone(bone: String) -> Vector3:
		if not is_instance_valid(gunner) or gunner.model == null or not is_instance_valid(gunner.model.orig_figure):
			return Vector3.INF
		var sks := gunner.model.orig_figure.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			return Vector3.INF
		var sk := sks[0] as Skeleton3D
		var i := sk.find_bone(bone)
		return (sk.global_transform * sk.get_bone_global_pose(i)).origin if i >= 0 else Vector3.INF

	## Figur am Sitz (Überblendung beim Auf-/Absteigen), Clipzeit nach Schwenk, Oberkörper nach Höhenrichtung
	func _pose_update(delta: float) -> void:
		if not is_instance_valid(gunner) or gunner.model == null or not is_instance_valid(gunner.model.orig_figure):
			return
		var m := gunner.model
		var fig := m.orig_figure
		_trans_t = move_toward(_trans_t, 1.0, delta / 0.35)
		var seat_x := Transform3D(m.global_basis, gunner.global_position)
		if is_instance_valid(pose_seat):
			seat_x = Transform3D(pose_seat.global_basis.orthonormalized(), pose_seat.global_position)
		elif is_instance_valid(frame):
			seat_x = Transform3D(Basis(Vector3.UP, frame.global_basis.get_euler().y), gunner.global_position)
		var k := smoothstep(0.0, 1.0, _trans_t)
		# Aufsteigen: Figur gleitet in 0,35 s vom Standort vor dem Besetzen in die Bedienhaltung (statt Teleport)
		var sc := fig.global_basis.get_scale()
		var tx := _trans_from.interpolate_with(seat_x, k)
		fig.global_transform = Transform3D(tx.basis.orthonormalized().scaled_local(sc), tx.origin)
		var clip := pose_clip()
		var ap := fig.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation(clip):
			var anim := ap.get_animation(clip)
			var ln := anim.length
			var t := _fit_seek(fig, anim, clip)
			m.set("full_seek", clampf(t if t >= 0.0 else pose_seek(ln), 0.0, ln * 0.999))
		if is_instance_valid(pose_ik):
			pose_ik.set("weight", k)
			pose_ik.set("pitch", clampf(gunner.look_pitch, -0.7, 0.7))
	var gunner: Soldier
	var _saved: Array = []
	var _saved_slot := 0
	var destroyed := false

	func init(h: OrigInteractive, f: Node3D, e: Dictionary, wd: WeaponData, st: int) -> void:
		host = h
		frame = f
		data = wd
		stance = st
		persistent_id = "oempl_" + String(e["name"])
		ammo_mags = maxi((e.get("inventory", []) as Array).size(), 2)
		global_position = frame.global_position + Vector3.UP * 0.5
		frame.set_meta("actor_state", 3)
		prompt = "%s: %s" % [data.display_name, OrigInteractive.text(TXT_USE, "Benutzen")]
		add_to_group("emplacements")
		_pose_nodes()        # Ruhelage der Seitenrichtung vor dem ersten Schwenk merken

	func can_interact(s: Soldier) -> bool:
		return enabled and not destroyed and (gunner == null or gunner == s) and s.vehicle == null

	## KI (EnemyBrain / HUMAN_BoardVehicle): frei, nicht zerstört
	func can_ai_mount(s: Soldier) -> bool:
		return not destroyed and (gunner == null or not is_instance_valid(gunner) or not gunner.alive or gunner == s) \
			and s.alive and s.vehicle == null

	## Platz des Schützen: Sitz-Frame SEAT00 des Originalmodells, sonst hinter der Waffe (Modelle blicken nach −Z)
	func gunner_spot() -> Vector3:
		if is_instance_valid(seat):
			return seat.global_position
		return frame.global_position + frame.global_basis.z.normalized() * 0.9

	func interact(s: Soldier) -> void:
		if gunner == s:
			dismount()
		else:
			mount(s)
		super.interact(s)

	## Besetzen: Schütze hinter der Waffe (Modelle blicken nach −Z), Waffe der Stellung in der Hand
	func mount(s: Soldier) -> void:
		if gunner == s:
			return
		if gunner and is_instance_valid(gunner) and gunner.mounted == self:
			dismount()
		gunner = s
		s.mounted = self
		_saved = s.weapons.duplicate()
		_saved_slot = s.current_slot
		var w := Weapon.new(data, false)
		w.in_mag = data.magazine_size if ammo_mags > 0 else 0
		w.reserve = data.magazine_size * maxi(ammo_mags - 1, 0)
		var arr: Array[Weapon] = [w, null, null]
		s.weapons = arr
		s.current_slot = 0
		_trans_from = s.model.orig_figure.global_transform if s.model and is_instance_valid(s.model.orig_figure) \
			else Transform3D(Basis(), s.global_position)
		_trans_t = 0.0
		s.global_position = gunner_spot() + Vector3.UP * 0.1
		s.look_yaw = frame.global_basis.get_euler().y
		s.stance_request = stance
		s._on_weapon_switched()
		_pose_begin(s)
		prompt = "%s: verlassen" % data.display_name

	func dismount() -> void:
		if gunner == null:
			return
		var s := gunner
		if s.weapons.size() > 0 and s.weapons[0] != null:
			ammo_mags = int(ceil(float(s.weapons[0].in_mag + s.weapons[0].reserve) / maxf(data.magazine_size, 1)))
		var arr: Array[Weapon] = []
		for x in _saved:
			arr.append(x)
		s.weapons = arr
		s.current_slot = _saved_slot
		_pose_end(s)
		s.mounted = null
		s._on_weapon_switched()
		gunner = null
		prompt = "%s: %s" % [data.display_name, OrigInteractive.text(TXT_USE, "Benutzen")]

	func _physics_process(delta: float) -> void:
		_kick = move_toward(_kick, 0.0, delta * 12.0)
		if gunner and (not is_instance_valid(gunner) or not gunner.alive):
			if is_instance_valid(gunner):
				dismount()
			gunner = null
		elif gunner and gunner.mounted == self:
			_aim_rig()

	func _process(delta: float) -> void:
		if gunner and is_instance_valid(gunner) and gunner.mounted == self:
			_pose_update(delta)

	## Original: SetActorState(w, 2) = zerstört (Bediener erhalten Schaden)
	func set_actor_state(n: int) -> void:
		frame.set_meta("actor_state", n)
		if n == 2 and not destroyed:
			destroyed = true
			var g := gunner
			dismount()
			Effects.explosion(frame.global_position, 3.0)
			if g and g.alive:
				g.apply_hit(60.0, &"torso", null, Vector3.UP)

	func serialize() -> Dictionary:
		return {"ammo": ammo_mags, "destroyed": destroyed}

	func deserialize(d: Dictionary) -> void:
		ammo_mags = int(d.get("ammo", ammo_mags))
		destroyed = bool(d.get("destroyed", false))


# --- Frei liegende Gegenstände (items.dat ohne Besitzer, actor_params.json „non_actor_stores“) ----------

static var _items: Dictionary = {}     ## items.sav: Nummer -> Eintrag (Name, Weltmodell, Text, Art)


static func item_info(id: int) -> Dictionary:
	if _items.is_empty():
		var d = LsRuntime._read_json(OrigLevel.cache_root() + "/items.json")
		if typeof(d) == TYPE_DICTIONARY:
			for it in d.get("items", []):
				_items[int(it.get("id", -1))] = it
	return _items.get(id, {})


func _world_items() -> void:
	var ap = LsRuntime._read_json(orig.mission_dir + "/actor_params.json")
	if typeof(ap) != TYPE_DICTIONARY:
		return
	for r in ap.get("non_actor_stores", {}).get("", []):
		var pa: Array = r.get("pos", [])
		if pa.size() != 3:
			continue
		var it := OrigWorldItem.new()
		it.host = self
		it.item = int(r["item"])
		mission.dynamic_root.add_child(it)
		# items.dat-Positionen liegen in LS3D-Koordinaten (z gespiegelt wie scene.json)
		it.global_position = Vector3(pa[0], pa[1], -float(pa[2]))
		it.build()
		stats.world_items += 1


## Gegenstand (Nummer) im Umkreis: frei liegend oder bei einem Soldaten des Trupps (Original _ItemInRange)
func item_in_range(id: int, pos: Vector3, r: float) -> bool:
	for n in get_tree().get_nodes_in_group("world_items"):
		var wi := n as OrigWorldItem
		if wi and wi.item == id and wi.visible and wi.enabled and wi.global_position.distance_to(pos) <= r:
			return true
	# abgelegte Gegenstände (Ablagestapel FieldInventory.Pile, Original: fallen gelassener Gegenstand liegt wieder frei;
	# TUTORIAL: Tauchgerät muss am Becken zurückbleiben, t_dummy_bubly _ItemInRange(231, 20))
	for n in get_tree().get_nodes_in_group("field_piles"):
		var pile := n as Node3D
		if pile and pile.global_position.distance_to(pos) <= r \
				and FieldInventory.count_at(FieldInventory.view(pile), "items", id) > 0:
			return true
	if mission.squad:
		for m in mission.squad.members:
			if m.alive and has_item(m, id) and m.global_position.distance_to(pos) <= r:
				return true
	return false


## Aufheben: Gegenstand ins Originalinventar; Munition/Granaten/Verband wirken sofort
static func give_item(s: Soldier, id: int) -> String:
	var inv: Array = s.get_meta("orig_items", [])
	inv.append(id)
	s.set_meta("orig_items", inv)
	var info := item_info(id)
	# Meldung mit dem Original-Gegenstandsnamen (deutsche Originaltexte, items.sav Text-ID)
	var nm := SAS.item_label(id) if SAS.item(id).size() > 0 or info.has("text_id") else String(info.get("name", "#%d" % id))
	if id in SAS.MEDKITS:
		s.medkits += 1
	var kind := String(info.get("kind", SAS.item_kind(id)))
	if kind == "weapon":
		var wd := WeaponDB.from_orig(id)
		if wd:
			var slot := int(wd.slot)
			if slot < s.weapons.size() and s.weapons[slot] != null and s.weapons[slot].data == wd:
				s.weapons[slot].add_ammo(wd.magazine_size)
			elif slot < s.weapons.size() and s.weapons[slot] == null:
				var w := Weapon.new(wd, false)
				w.in_mag = wd.magazine_size if wd.slot != WeaponData.Slot.GRENADE else 1
				s.weapons[slot] = w
	elif kind == "ammo":
		for w in s.weapons:
			if w and w.data.slot != WeaponData.Slot.GRENADE:
				for wid in WeaponDB.ORIG_IDS:
					if WeaponDB.ORIG_IDS[wid] == w.data.id and SAS.ammo_of(wid) == id:
						w.add_ammo(w.data.magazine_size)
	return nm


class OrigWorldItem extends Interactable:
	var host: OrigInteractive
	var item := -1

	func build() -> void:
		add_to_group("world_items")
		var info := OrigInteractive.item_info(item)
		var model := String(info.get("model", ""))
		var vis: Node3D = host.orig.model_instance(model) if model != "" else null
		if vis == null:
			vis = OrigWeapons.world_model(model)   # Waffen: gemeinsamer Cache (tools/export_weapons.py)
		if vis == null:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.08, 0.22)
			mi.mesh = bm
			vis = mi
		add_child(vis)
		var txt := int(info.get("text_id", -1))
		prompt = "%s: %s" % [OrigInteractive.text(txt, String(info.get("name", "Gegenstand"))), "Aufheben"]
		persistent_id = "oitem_%d_%d_%d" % [item, int(global_position.x * 10), int(global_position.z * 10)]
		# Original: Frame trägt den Modellnamen (Skripte: FRM_FindFrame(x, "item_slozka3"); ITEM_Teleport)
		if model != "":
			name = model.validate_node_name()
			host.runtime.register_actor(model, self)

	func interact(s: Soldier) -> void:
		var nm := OrigInteractive.give_item(s, item)
		Events.say("%s aufgehoben: %s" % [s.soldier_name, nm], 2.5)
		enabled = false
		visible = false
		super.interact(s)

	func can_interact(_s: Soldier) -> bool:
		return enabled and visible

	func serialize() -> Dictionary:
		return {"enabled": enabled, "pos": [global_position.x, global_position.y, global_position.z], "visible": visible}

	func deserialize(d: Dictionary) -> void:
		enabled = bool(d.get("enabled", true))
		visible = bool(d.get("visible", true))
		var pa: Array = d.get("pos", [])
		if pa.size() == 3:
			global_position = Vector3(pa[0], pa[1], pa[2])
