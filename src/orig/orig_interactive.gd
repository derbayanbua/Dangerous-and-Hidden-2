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
static func damage_objects(tree: SceneTree, pos: Vector3, radius: float, damage: float, by: Node = null) -> void:
	for n in tree.get_nodes_in_group("destructibles") + tree.get_nodes_in_group("vehicles") + tree.get_nodes_in_group("dogs"):
		var n3 := n as Node3D
		if n3 == null or not n3.has_method("on_bullet_hit"):
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
	var is_open: bool:
		get:
			return state == 1 or state == 2

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
		# Drehsinn (nicht belegt): so wählen, dass der Flügel in die gespeicherte Öffnungsrichtung schwenkt
		var od: Array = p.get("open_dir_gltf", [])
		if not slide and od.size() == 3:
			var dir_w := frame.global_basis * Vector3(od[0], od[1], od[2])
			var c := frame.global_transform.affine_inverse() * box.get_center()
			var moved := frame.global_basis * (Basis(axis, 0.3) * c - c)
			if dir_w.length() > 0.01 and moved.dot(dir_w) < 0.0:
				sgn = -1.0
		if int(p.get("initial_state", 0)) == 1:
			amount = open_amount
			target = open_amount
			state = 1
			_apply()
		frame.set_meta("actor_state", state)
		_update_prompt()

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
				Events.say("%s aufgeschlossen." % label, 2.0)
			elif lockpickable:
				# Dauer aus der Fertigkeit Schlösser (Original: Getter 8, Text 7073)
				_picker = s
				_pick_from = s.global_position
				_pick_left = lerpf(8.0, 2.0, clampf(float(s.get_meta("lockpick", 50.0)) / 100.0, 0.0, 1.0))
				Events.say(OrigInteractive.text(7073, "Knackt Schloss") + " …", _pick_left)
			else:
				Events.say("%s ist verschlossen." % label, 2.0)
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
		target = open_amount if o else 0.0
		state = 2 if o else 3
		frame.set_meta("actor_state", state)
		_update_prompt()
		if partner_name != "":
			var other = host.controls.get(partner_name.to_upper())
			if other is OrigDoor and other != self and other.is_open != o:
				other.partner_name = ""      # kein Ping-Pong
				other.set_open(o)
				other.partner_name = String(p["partner_door"]) if p.get("partner_door") != null else ""

	func set_actor_state(n: int) -> void:
		set_open(n != 0)

	func set_locked(b: bool) -> void:
		if b and state != 0:
			return          # Original: Abschließen nur im geschlossenen Zustand
		locked = b
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
		if not is_equal_approx(amount, target):
			amount = move_toward(amount, target, speed * delta)
			_apply()
			if is_equal_approx(amount, target):
				state = 1 if target > 0.0 else 0
				frame.set_meta("actor_state", state)
				_update_prompt()

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
		l.prompt = "%s: %s" % [label, text(TXT_USE, "Benutzen")]
		mission.dynamic_root.add_child(l)
		l.global_position = top if at_top else bottom
	stats.ladders += 1


class OrigLadder extends Interactable:
	var top: Vector3
	var bottom: Vector3
	var at_top := false

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
		else:
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

	func init(h: OrigInteractive, f: Node3D, e: Dictionary, is_radio: bool) -> void:
		host = h
		frame = f
		radio = is_radio
		var p: Dictionary = e.get("params", {})
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

	func init(h: OrigInteractive, f: Node3D, e: Dictionary) -> void:
		host = h
		frame = f
		var p: Dictionary = e.get("params", {})
		persistent_id = "oexpl_" + String(e["name"])
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
		host.runtime._explosion(pos, radius, dmg)
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

	func init(h: OrigInteractive, f: Node3D, e: Dictionary) -> void:
		host = h
		frame = f
		add_to_group("destructibles")
		add_to_group("persistent")
		persistent_id = "odestr_" + String(e["name"])
		var p: Dictionary = e.get("params", {})
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
		_add(d * 10.0 * 0.25, by)

	func on_explosion(d: float, by: Node) -> void:
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
		Effects.explosion(global_position, 4.0)
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
	if wid == null:
		return
	var wd: WeaponData = WeaponDB.from_orig(int(wid), true) if wid is int else WeaponDB.get_weapon(StringName(wid))
	if wd == null:
		return
	var x := OrigEmplacement.new()
	x.name = "Emplacement_" + String(e["name"]).validate_node_name()
	mission.dynamic_root.add_child(x)
	x.init(self, f, e, wd, stance)
	_register(e, f, x)
	stats.emplacements += 1


class OrigEmplacement extends Interactable:
	var host: OrigInteractive
	var frame: Node3D
	var data: WeaponData
	var stance := 1
	var ammo_mags := 0
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

	func can_interact(s: Soldier) -> bool:
		return enabled and not destroyed and (gunner == null or gunner == s) and s.vehicle == null

	func interact(s: Soldier) -> void:
		if gunner == s:
			dismount()
		else:
			mount(s)
		super.interact(s)

	## Besetzen: Schütze hinter der Waffe (Modelle blicken nach −Z), Waffe der Stellung in der Hand
	func mount(s: Soldier) -> void:
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
		s.global_position = frame.global_position + frame.global_basis.z.normalized() * 0.9 + Vector3.UP * 0.1
		s.look_yaw = frame.global_basis.get_euler().y
		s.stance_request = stance
		s._on_weapon_switched()
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
		s.mounted = null
		s._on_weapon_switched()
		gunner = null
		prompt = "%s: %s" % [data.display_name, OrigInteractive.text(TXT_USE, "Benutzen")]

	func _physics_process(_delta: float) -> void:
		if gunner and (not is_instance_valid(gunner) or not gunner.alive):
			if is_instance_valid(gunner):
				dismount()
			gunner = null

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
	var nm := SAS.item_name(id) if SAS.item(id).size() > 0 else String(info.get("name", "#%d" % id))
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
