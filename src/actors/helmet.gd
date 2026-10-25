class_name Helmet
extends RefCounted
## B-014: Kopfgegenstand (Helm/Mütze, items.sav Ausrüstung Kategorie 16) sichtbar am Original-Modell, eigene
## Helm-Trefferfläche, Abschießen mit Flugphysik und Ablage als aufnehmbarer Gegenstand (SP und MP server-autoritativ).
##
## Belege (docs/re_notes_weapons.md §10/§10a, Dekompilat re_work/mpw/d1.c):
## - Strahltest 0x455670 prüft ZUERST das Helm-Modell des Kopf-Inventarplatzes (Mensch +0x74[0]) → Zone 11, erst danach
##   die 10 Gelenkvolumen [B]. Helm-Material hdmaterials Zeile 12 „Plech 2-6mm“ = 150 zotti Panzerung, danach in
##   Human::Damage 0x5A1C90 Fall 0xB: RandFloat < 0,3 → ×5 (Durchschlag), sonst ×0,2 (Abpraller) [B] – ein Abpraller
##   rettet also vor dem tödlichen Kopfschuss (WeaponDB.zone_damage/bullet_hit_damage, unverändert).
## - Fall 0xB setzt die Trefferart-Maske 1 statt 8/0x10/0x20 (0x5A21D6 ff.) und Bit 0x2000 für die Trefferreaktion
##   0x5ABBD0 [B Code]; ob das Original den Helm dabei vom Kopf schlägt, ist NICHT belegt [?].
## - Abfliegen, Liegenbleiben und Wiederaufsetzen: Vorgabe Auftraggeber (B-014) [D]. Flug: Starrkörper mit der
##   Kistenform des Helmmodells, Impuls in Schussrichtung + nach oben [D Werte]; liegt der Helm still (oder nach
##   REST_TIMEOUT), wird er zum Ablagestapel (FieldInventory.Pile) mit dem Helmgegenstand → Benutzen/Inventar (I):
##   auf den Kopf-Platz ziehen = aufsetzen.
## - Modelllage: Die Helmmodelle (MODELS\B_*_HELM*.4ds) liegen im Figurraum der Bindungslage (Ursprung ≈ 1,74 m über
##   dem Boden); sie werden mit der Bindungslage an das Kopfgelenk „f“ gehängt und folgen so jeder Animation [P].

const HEAD_BONE := "f"
const ZONE := &"helmet"
## Helm-Trefferfläche = Hüllkiste des Helmmodells ab diesem Höhenanteil (Rand/Gesicht frei) [P]
const BOX_FROM := 0.35
## Standard-Kopfgegenstand für Figuren ohne Originalinventar (Helmform „stahlhelm“/„brodie“ der Übungseinsätze/Bots):
## 76 „G helm zelena“ (Achse), 79 „A helm sesitkou“ (Alliierte) [P Zuordnung]
const DEFAULT_AXIS := 76
const DEFAULT_ALLIED := 79
const FLY_SPEED := 3.2          ## m/s in Schussrichtung [D]
const FLY_UP := 2.4             ## m/s nach oben [D]
const REST_TIMEOUT := 4.0       ## s bis zur Ablage, falls der Körper nicht einschläft [D]

static var _model_dirs: Array = []
static var _templates := {}


## Getragener Kopfgegenstand (−1 = keiner): Kopf-Platz des Inventars (Meta inv_layout, nur wenn auch in orig_items),
## sonst erster Kopfgegenstand in orig_items; ohne Inventar-Meta die Helmform der Figur.
static func head_item(s: Node) -> int:
	if s == null or not is_instance_valid(s):
		return -1
	var orig: Array = s.get_meta("orig_items", []) if s.has_meta("orig_items") else []
	var layout: Dictionary = s.get_meta("inv_layout", {}) if s.has_meta("inv_layout") else {}
	if layout.has("head"):
		var h := int(layout["head"])
		if h >= 0 and orig.has(h):
			return h
		if h < 0:
			return -1
	for it in orig:
		if is_head_item(int(it)):
			return int(it)
	if s.has_meta("orig_items") or s.has_meta("orig_params") or s.has_meta("sas") or s.has_meta("helmet_lost"):
		return -1
	return style_default(s)


static func is_head_item(id: int) -> bool:
	if id < 0:
		return false
	var eq = OrigInteractive.item_info(id).get("equip_raw", [])
	return eq is Array and (eq as Array).size() > 1 and int(eq[1]) == WeaponDB.HEAD_ITEM_CATEGORY


## Kopfgegenstand nach der Helmform (Platzhalterwert), −1 bei Mütze/ohne
static func style_default(s: Node) -> int:
	var hs: String = String(s.get("helmet_style")) if "helmet_style" in s else ""
	if hs == "" or hs == "cap" or hs == "none":
		return -1
	var t = s.get("team")
	return DEFAULT_ALLIED if t != null and int(t) == Soldier.TEAM_ALLIED else DEFAULT_AXIS


## Figuren ohne Originalinventar: Standardhelm einmalig als echter Gegenstand ins Inventar (damit Abschießen/Aufheben/
## Aufsetzen über dasselbe Inventar laufen). Kader/Original-Akteure/MP-Ausrüstung bringen ihren Kopf selbst mit.
static func ensure_default(s: Node) -> void:
	if s == null or s.has_meta("orig_params") or s.has_meta("sas") or s.has_meta("helmet_lost"):
		return
	var orig: Array = s.get_meta("orig_items", []) if s.has_meta("orig_items") else []
	for it in orig:
		if is_head_item(int(it)):
			return
	if s.has_meta("inv_layout") and int((s.get_meta("inv_layout") as Dictionary).get("head", -2)) == -1:
		return
	var d := style_default(s)
	if d < 0 or not is_head_item(d):
		return
	orig = orig.duplicate()
	orig.append(d)
	s.set_meta("orig_items", orig)


## --- Modell -------------------------------------------------------------------------------------------------

static func _dirs() -> Array:
	if _model_dirs.is_empty():
		var root := OrigLevel.cache_root()
		var da := DirAccess.open(root)
		if da:
			for d in da.get_directories():
				if DirAccess.dir_exists_absolute(root + "/" + d + "/models"):
					_model_dirs.append(d)
		_model_dirs.sort()
	return _model_dirs


## Helmmodell des Gegenstands (Wurzel = Figurraum der Bindungslage) oder null
static func model_of(item: int) -> Node3D:
	var key := String(OrigInteractive.item_info(item).get("model", "")).to_lower()
	if key == "":
		return null
	if not _templates.has(key):
		var root := OrigLevel.cache_root()
		# orig_cache/heads = alle Kopfgegenstände (D:\Workspace_D\tools\export_head_items.py), sonst Missionsordner
		var tpl: Node3D = OrigLevel.parse_glb("%s/heads/%s.glb" % [root, key])
		for d in ([] if tpl else _dirs()):
			var p := "%s/%s/models/%s.glb" % [root, d, key]
			if FileAccess.file_exists(p):
				tpl = OrigLevel.parse_glb(p)
				if tpl:
					break
		_templates[key] = tpl
	var t: Node3D = _templates[key]
	if t == null:
		return null
	var n := t.duplicate() as Node3D
	for c in n.find_children("shadow*", "", true, false):
		(c as Node).queue_free()        # Schattenkarte des Originals (Dummy) nicht anzeigen
	return n


## Hüllkiste aller Meshes im Raum der Wurzel
static func bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bb: AABB = OrigWeapons._rel(root, m) * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## Liegend/fliegend: Modell um die Mitte der Hüllkiste zentriert
static func loose_model(item: int) -> Node3D:
	var n := model_of(item)
	if n == null:
		return null
	var holder := Node3D.new()
	holder.name = "HelmetModel"
	var bb := bounds(n)
	holder.add_child(n)
	n.position = -bb.get_center()
	holder.set_meta("size", bb.size)
	return holder


## --- Abschießen ---------------------------------------------------------------------------------------------

## Helm-Treffer (Ballistics, nur Einzelspieler/Server): Gegenstand vom Kopf, Flugkörper, später Ablagestapel
static func knock_off(s: Soldier, dir: Vector3) -> void:
	if not is_instance_valid(s) or (Net.is_online and not Net.is_authority()):
		return
	var item := head_item(s)
	if item < 0:
		return
	var model = s.get("model")
	var xf: Transform3D = s.global_transform
	if model and model.has_method("helmet_transform"):
		xf = model.helmet_transform()
	# Inventar: Kopf-Platz leeren (Gegenstand verlässt den Soldaten)
	var inv := FieldInventory.view(s)
	if int(inv["head"]) == item:
		inv["head"] = -1
	else:
		SAS.remove_item(inv, item, 1)
	FieldInventory.apply(s, inv, FieldInventory.weapon_pool(s))
	var orig: Array = (s.get_meta("orig_items", []) as Array).duplicate()
	if orig.has(item):
		orig.erase(item)      # apply führt orig_items aus dem Inventar; Standardhelm (nur orig_items) ebenfalls weg
		s.set_meta("orig_items", orig)
	s.set_meta("helmet_lost", true)
	if model and model.has_method("refresh_helmet"):
		model.refresh_helmet()
	var d: Vector3 = dir.normalized() if dir.length() > 0.01 else -s.global_basis.z
	var vel := d * FLY_SPEED + Vector3.UP * FLY_UP
	var spin := Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))
	var parent: Node = s.get_parent() if s.get_parent() else Game.current_mission()
	spawn_body(parent, item, xf, vel, spin, true)
	if Net.is_online:
		Net.inventory_broadcast(FieldInventory.key_of(s), FieldInventory.export_state(s))
		Net.helmet_knocked(FieldInventory.key_of(s), item, xf, vel, spin)


## Flugkörper anlegen; authority = legt beim Stillstand den Ablagestapel an (Client: nur Darstellung)
static func spawn_body(parent: Node, item: int, xf: Transform3D, vel: Vector3, spin: Vector3, authority: bool) -> HelmetBody:
	var b := HelmetBody.new()
	b.item = item
	b.authority = authority
	b.name = "HelmetBody"
	parent.add_child(b)
	b.setup(xf, vel, spin)
	return b


## Fliegender Helm (Starrkörper, kollidiert nur mit der Welt)
class HelmetBody extends RigidBody3D:
	var item := -1
	var authority := true
	var age := 0.0
	var _done := false

	func setup(xf: Transform3D, vel: Vector3, spin: Vector3) -> void:
		var vis := Helmet.loose_model(item)
		var size := Vector3(0.24, 0.16, 0.28)
		if vis:
			size = (vis.get_meta("size") as Vector3).max(Vector3(0.05, 0.05, 0.05))
			add_child(vis)
		else:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.13
			sm.height = 0.13
			sm.is_hemisphere = true
			mi.mesh = sm
			add_child(mi)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		mass = 1.2
		continuous_cd = true
		global_transform = xf
		linear_velocity = vel
		angular_velocity = spin
		add_to_group("helmet_bodies")

	func _physics_process(delta: float) -> void:
		age += delta
		if _done:
			return
		if not authority:
			# Darstellung beim Client: verschwindet, sobald der Server-Ablagestapel da ist (oder nach Zeitablauf)
			if age > Helmet.REST_TIMEOUT + 3.0 or (age > 0.3 and FieldInventory.pile_near(global_position) != null):
				_done = true
				queue_free()
			return
		if (age > 0.6 and (sleeping or linear_velocity.length() < 0.05)) or age > Helmet.REST_TIMEOUT or global_position.y < -500.0:
			_done = true
			Helmet.land(self)


## Helm liegt: Ablagestapel mit dem Gegenstand an dieser Stelle (SP/Server), an alle Rechner melden
static func land(b: HelmetBody) -> void:
	var parent := b.get_parent()
	var at := b.global_position
	var bb: Vector3 = Vector3(0.24, 0.16, 0.28)
	var vis := b.get_node_or_null("HelmetModel") as Node3D
	if vis:
		bb = vis.get_meta("size")
	at.y -= bb.y * 0.5
	var pile := FieldInventory.spawn_pile(parent if parent else Game.current_mission(), at, "")
	var pv := FieldInventory.view(pile)
	SAS.add_item(pv, b.item, 1)
	FieldInventory.apply(pile, pv, [])
	pile.refresh_model()
	if Net.is_online:
		Net.inventory_broadcast(FieldInventory.key_of(pile), FieldInventory.export_state(pile))
	b.queue_free()
