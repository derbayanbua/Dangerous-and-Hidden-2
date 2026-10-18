class_name FieldInventory
extends RefCounted
## Ingame-Inventar (Original: Inventar des HUD-Modells MODELS\gameinterface.4ds, Taste I = Aktion T2847
## „INVENTAR“; Durchsuchen = Aktionsmenü Fall 7, hd2.exe 0x4B2830 -> 0x49DE90 -> 0x4A4380 mit zweitem Inventar,
## docs/re_notes_ingame_inventory.md). Hier: Logik und Mehrspieler-Abgleich; Darstellung in IngameInventory.
##
## Modell wie im SAS-Bildschirm: {hands, shoulder, head, uniform, back, items: [[Gegenstand, Anzahl]]}
## (Taschen + Rucksack = ein gemeinsames Inventar, Vereinfachung des Auftraggebers). Die Laufzeit des Soldaten
## (Waffen mit Magazin/Reserve, Granaten, Verbände, Fernglas, Sprengstoff, Minen) bleibt die Wahrheit:
## view() leitet das Inventar daraus ab, apply() schreibt es nach jeder Aktion zurück. Was die Laufzeit nicht
## abbildet (zweite Waffe derselben Art, Munition ohne Waffe), liegt in Meta „inv_extra“, Kopf/Uniform/Rücken
## in „inv_layout“; „orig_items“ enthält danach alle getragenen Gegenstände (_IsInInventory der Skripte).
## Regel des Auftraggebers: Uniform nur von lebenden Gefangenen (Leichen: Uniform gesperrt).

const SLOTS := ["hands", "shoulder", "head", "uniform", "back"]
const MEDKITS := [54, 53]
const BINOC := 99
const EXPLOSIVES := [68, 67]
const MINES := [70, 71]
const TOOL_IDS := [53, 54, 99, 67, 68, 70, 71]
const DEFAULT_STRENGTH := 40.0          ## Traglast ohne Kaderwert (kg) [P]
const ENEMY_UNIFORM := 126              ## „Uniform GE01a“ für Gegner ohne Originalinventar [P]
const REACH := 3.0                      ## Durchsuchen/Aufheben: Abstand (m), auch Server-Prüfung

## Änderungszähler (Darstellung aktualisiert sich bei Änderung, auch nach Netzabgleich)
static var revision := 0


# --- Ableiten -----------------------------------------------------------------------------------------

static func weapon_item(w: Weapon, team: int) -> int:
	return OrigHud.weapon_item(w, team)


static func mag_count(w: Weapon) -> int:
	if w.data.slot == WeaponData.Slot.LAUNCHER or w.data.magazine_size <= 1:
		return maxi(w.reserve, 0)
	return int(ceil(float(maxi(w.reserve, 0)) / float(w.data.magazine_size)))


static func _bump(d: Dictionary, id: int, n: int) -> void:
	d[id] = int(d.get(id, 0)) + n


static func view(n: Node) -> Dictionary:
	if n is Soldier:
		return _soldier_view(n as Soldier)
	if n == null:
		return SAS.new_inventory()
	return (n.get_meta("field_inv", SAS.new_inventory()) as Dictionary).duplicate(true)


static func _soldier_view(s: Soldier) -> Dictionary:
	var inv := SAS.new_inventory()
	var explained := {}
	var hand_w: Weapon = s.current_weapon() if s.tool == "" else null
	var sh_w: Weapon = OrigHud.shoulder_weapon(s)
	var ws: Array = []
	for w in s.weapons:
		if w:
			ws.append(w)
	for w in s.get_meta("surrendered_weapons", []):
		if w:
			ws.append(w)
	for w0 in ws:
		var w := w0 as Weapon
		var id := weapon_item(w, s.team)
		if id < 0:
			continue
		var n := 1
		if w.data.slot == WeaponData.Slot.GRENADE:
			n = w.total_ammo()
			if n <= 0:
				continue
		_bump(explained, id, n)
		if w == hand_w and int(inv["hands"]) < 0:
			inv["hands"] = id
			n -= 1
		elif w == sh_w and int(inv["shoulder"]) < 0:
			inv["shoulder"] = id
			n -= 1
		if n > 0:
			SAS.add_item(inv, id, n)
		if w.data.slot != WeaponData.Slot.GRENADE and w.data.action != WeaponData.Action.MELEE:
			var am := SAS.ammo_of(id)
			var mags := mag_count(w)
			if am >= 0 and mags > 0:
				SAS.add_item(inv, am, mags)
				_bump(explained, am, mags)
	var orig: Array = s.get_meta("orig_items", [])
	_tool(inv, 53 if orig.has(53) and not orig.has(54) else 54, s.medkits, s.tool == "medkit")
	_tool(inv, BINOC, 1 if s.has_binoculars else 0, s.tool == "binoculars")
	_tool(inv, 67 if orig.has(67) and not orig.has(68) else 68, s.explosives, s.tool == "explosive")
	_tool(inv, 71 if orig.has(71) and not orig.has(70) else 70, s.mines, s.tool == "mine")
	for e in s.get_meta("inv_extra", []):
		SAS.add_item(inv, int(e[0]), int(e[1]))
		_bump(explained, int(e[0]), int(e[1]))
	# übrige Originalgegenstände (Dokumente, Schlüssel, Kopf, Uniform, Rucksack …); Waffen/Munition nur, soweit
	# die Laufzeit sie nicht schon zeigt (z. B. von Skripten gegebene Gegenstände)
	var counts := {}
	for id in orig:
		_bump(counts, int(id), 1)
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		if TOOL_IDS.has(int(id)):
			continue
		var n := int(counts[id])
		var k := SAS.item_kind(int(id))
		if k == "weapon" or k == "ammo":
			n -= int(explained.get(int(id), 0))
		if n > 0:
			SAS.add_item(inv, int(id), n)
	var layout: Dictionary = s.get_meta("inv_layout", {})
	for slot in ["head", "uniform", "back"]:
		var want := int(layout.get(slot, -2))
		if want == -2:
			want = -1
			for e in inv["items"]:
				if SAS.slot_for(int(e[0])) == slot:
					want = int(e[0])
					break
		if want >= 0 and SAS.remove_item(inv, want, 1) > 0:
			inv[slot] = want
	# Gegner/Gefangene: Uniform am Körper (Original: Uniform des Akteurs, items.dat Slot 4)
	if int(inv["uniform"]) < 0 and not _uniform_gone(s):
		var u := enemy_uniform(s)
		if u >= 0:
			if SAS.remove_item(inv, u, 1) <= 0:
				pass
			inv["uniform"] = u
	return inv


static func _tool(inv: Dictionary, id: int, n: int, in_hand: bool) -> void:
	if n <= 0:
		return
	if in_hand and int(inv["hands"]) < 0:
		inv["hands"] = id
		n -= 1
	if n > 0:
		SAS.add_item(inv, id, n)


## Uniform eines Gegners (Original-Akteursinventar Slot 4, sonst Wehrmachtsuniform); -1 = keine
static func enemy_uniform(s: Soldier) -> int:
	if s.has_meta("orig_uniform"):
		return int(s.get_meta("orig_uniform"))
	if s.get_node_or_null("EnemyBrain") != null and s.team != Soldier.TEAM_ALLIED and not s.has_meta("sas"):
		return ENEMY_UNIFORM
	return -1


static func _uniform_gone(s: Soldier) -> bool:
	var b := s.get_node_or_null("EnemyBrain")
	if b and bool(b.get("uniform_taken")):
		return true
	for c in s.get_children():
		if c is Pickups.Loot and (c as Pickups.Loot).uniform_taken:
			return true
	return false


static func strength(n: Node) -> float:
	if n is Soldier and n.has_meta("sas"):
		var st: Dictionary = Game.sas_states().get(str(int(n.get_meta("sas"))), {})
		return float((st.get("stats", {}) as Dictionary).get("strength", DEFAULT_STRENGTH))
	return DEFAULT_STRENGTH if n is Soldier else 9999.0


## Raum Taschen + Rucksack (Kader: Original 12 + Rucksack; Übungs-/Mehrspielerfiguren ohne Kaderinventar
## mindestens DEFAULT_SPACE, da ihre Grundausstattung nicht nach den Originalregeln gepackt ist [P])
const DEFAULT_SPACE := 40.0


static func capacity(n: Node, inv: Dictionary) -> float:
	if n is Soldier and not n.has_meta("sas"):
		return maxf(SAS.inv_capacity(inv), DEFAULT_SPACE)
	if not n is Soldier:
		return 9999.0
	return SAS.inv_capacity(inv)


static func is_empty(n: Node) -> bool:
	if not is_instance_valid(n):
		return true
	var inv := view(n)
	if not (inv["items"] as Array).is_empty():
		return false
	for k in SLOTS:
		if int(inv[k]) >= 0 and not (k == "uniform" and n is Soldier and not (n as Soldier).alive):
			return false
	return true


static func count_at(inv: Dictionary, from: String, id: int) -> int:
	if from in SLOTS:
		return 1 if int(inv.get(from, -1)) == id else 0
	for e in inv["items"]:
		if int(e[0]) == id:
			return int(e[1])
	return 0


## Darf der Platz den Gegenstand aufnehmen? (Hände: alles außer Kleidung/Rucksack; Schulter: Langwaffen)
static func accepts(slot: String, id: int) -> bool:
	match slot:
		"items", "drop":
			return true
		"hands":
			# Waffen und benutzbare Hilfsmittel (Verband, Fernglas, Sprengstoff, Minen) – wie die Waffenwahl
			return TOOL_IDS.has(id) or (SAS.item_kind(id) == "weapon" and WeaponDB.from_orig(id) != null)
		"shoulder":
			if SAS.item_kind(id) != "weapon" or MINES.has(id):
				return false
			var wd := WeaponDB.from_orig(id)
			return wd != null and wd.slot in [WeaponData.Slot.PRIMARY, WeaponData.Slot.LAUNCHER]
		"head", "uniform", "back":
			return SAS.slot_for(id) == slot
	return false


# --- Zurückschreiben -------------------------------------------------------------------------------------

## Waffenobjekte beider Seiten (Magazinstand bleibt beim Tauschen erhalten)
static func weapon_pool(n: Node) -> Array:
	var out: Array = []
	if n is Soldier:
		for w in (n as Soldier).weapons:
			if w:
				out.append(w)
		for w in n.get_meta("surrendered_weapons", []):
			if w:
				out.append(w)
	elif n:
		out.append_array(n.get_meta("field_weapons", []))
	return out


static func _take_pool(pool: Array, id: int, team: int) -> Weapon:
	for w in pool:
		if weapon_item(w as Weapon, team) == id or weapon_item(w as Weapon, -1) == id:
			pool.erase(w)
			return w as Weapon
	return null


static func flatten(inv: Dictionary) -> Array:
	var out: Array = []
	for k in SLOTS:
		if int(inv.get(k, -1)) >= 0:
			out.append(int(inv[k]))
	for e in inv["items"]:
		for i in int(e[1]):
			out.append(int(e[0]))
	return out


static func apply(n: Node, inv: Dictionary, pool: Array) -> void:
	revision += 1
	if not n is Soldier:
		var ws: Array = []
		for e in inv["items"]:
			if SAS.item_kind(int(e[0])) == "weapon":
				for i in int(e[1]):
					var w := _take_pool(pool, int(e[0]), -1)
					if w:
						ws.append(w)
		n.set_meta("field_inv", inv)
		n.set_meta("field_weapons", ws)
		return
	var s := n as Soldier
	var captured := s.has_meta("captured")
	var old_w := s.current_weapon()
	var old_key := s.selected_key()
	var total := {}
	for id in flatten(inv):
		_bump(total, int(id), 1)
	s.medkits = int(total.get(53, 0)) + int(total.get(54, 0))
	s.has_binoculars = int(total.get(BINOC, 0)) > 0
	s.explosives = int(total.get(67, 0)) + int(total.get(68, 0))
	s.mines = int(total.get(70, 0)) + int(total.get(71, 0))
	# Waffen: Reihenfolge Hände, Schulter, Taschen/Rucksack; je Laufzeitplatz eine Waffe
	var order: Array = []
	for k in ["hands", "shoulder"]:
		if int(inv[k]) >= 0 and not order.has(int(inv[k])):
			order.append(int(inv[k]))
	for e in inv["items"]:
		if not order.has(int(e[0])):
			order.append(int(e[0]))
	var new_w: Array = []
	new_w.resize(WeaponData.SLOT_COUNT)
	var surrendered: Array = []
	var extra := {}
	for id in order:
		if TOOL_IDS.has(int(id)) or SAS.item_kind(int(id)) != "weapon":
			continue
		var cnt := int(total.get(int(id), 0))
		var wd := WeaponDB.from_orig(int(id))
		if wd == null:
			_bump(extra, int(id), cnt)
			continue
		var slot := int(wd.slot)
		if captured:
			for i in (1 if slot == WeaponData.Slot.GRENADE else cnt):
				var wc := _take_pool(pool, int(id), s.team)
				if wc == null:
					wc = _new_weapon(wd)
				if slot == WeaponData.Slot.GRENADE:
					wc.in_mag = 1
					wc.reserve = cnt - 1
				surrendered.append(wc)
			continue
		if slot >= new_w.size() or new_w[slot] != null:
			_bump(extra, int(id), cnt)
			continue
		var w := _take_pool(pool, int(id), s.team)
		if w == null:
			w = _new_weapon(wd)
		if slot == WeaponData.Slot.GRENADE:
			w.in_mag = 1 if cnt > 0 else 0
			w.reserve = maxi(cnt - 1, 0)
		elif cnt > 1:
			_bump(extra, int(id), cnt - 1)
		new_w[slot] = w
	# Munition der Waffen (Magazine in den Taschen): Teilmagazin bleibt erhalten
	var used_ammo := {}
	var armed: Array = new_w.duplicate()
	armed.append_array(surrendered)
	for w0 in armed:
		var w := w0 as Weapon
		if w == null or w.data.slot == WeaponData.Slot.GRENADE or w.data.action == WeaponData.Action.MELEE:
			continue
		var am := SAS.ammo_of(weapon_item(w, s.team))
		if am < 0 or used_ammo.has(am):
			if am >= 0:
				w.reserve = 0
			continue
		var cnt := int(total.get(am, 0))
		used_ammo[am] = true
		var old := mag_count(w)
		if cnt == old:
			pass
		elif cnt <= 0:
			w.reserve = 0
		elif w.data.slot == WeaponData.Slot.LAUNCHER or w.data.magazine_size <= 1:
			w.reserve = cnt
		else:
			var part := w.data.magazine_size
			if old > 0:
				part = clampi(w.reserve - (old - 1) * w.data.magazine_size, 1, w.data.magazine_size)
			w.reserve = (cnt - 1) * w.data.magazine_size + part
	for id in total:
		if SAS.item_kind(int(id)) == "ammo" and not used_ammo.has(int(id)) and not TOOL_IDS.has(int(id)):
			_bump(extra, int(id), int(total[id]))
	var ex: Array = []
	for id in extra:
		if int(extra[id]) > 0:
			ex.append([int(id), int(extra[id])])
	s.set_meta("inv_extra", ex)
	s.set_meta("inv_layout", {"head": int(inv["head"]), "uniform": int(inv["uniform"]), "back": int(inv["back"])})
	s.set_meta("orig_items", flatten(inv))
	if captured:
		s.set_meta("surrendered_weapons", surrendered)
	s.weapons.clear()
	for w in new_w:
		s.weapons.append(w as Weapon)
	if not s.alive or captured:
		return
	_apply_hands(s, int(inv["hands"]), old_w, old_key)


static func _new_weapon(wd: WeaponData) -> Weapon:
	var w := Weapon.new(wd, false)
	w.in_mag = wd.magazine_size if wd.slot != WeaponData.Slot.GRENADE else 1
	if wd.action == WeaponData.Action.MELEE:
		w.in_mag = 1
	return w


## Gegenstand in den Händen = gewählte Waffe/Hilfsmittel (Original: Inventar +0xC = Hand, HUD i_hands)
static func _apply_hands(s: Soldier, hand: int, old_w: Weapon, old_key: String) -> void:
	var key := ""
	if MEDKITS.has(hand):
		key = "medkit"
	elif hand == BINOC:
		key = "binoculars"
	elif EXPLOSIVES.has(hand):
		key = "explosive"
	elif MINES.has(hand):
		key = "mine"
	elif hand >= 0:
		for i in s.weapons.size():
			if s.weapons[i] and weapon_item(s.weapons[i], s.team) == hand:
				key = "slot:%d" % i
				break
	if key == "":
		# leere Hände: auf einen freien Laufzeitplatz (unbewaffnet)
		s.tool = ""
		if s.using_binoculars:
			s.toggle_binoculars()
		for i in s.weapons.size():
			if s.weapons[i] == null:
				s.current_slot = i
				break
		s._on_weapon_switched()
		return
	if key != old_key:
		if key.begins_with("slot:"):
			var i := int(key.substr(5))
			s.tool = ""
			if s.using_binoculars:
				s.toggle_binoculars()
			if i == s.current_slot or not s.select_slot(i):
				s.current_slot = i
				s._on_weapon_switched()
		else:
			s.apply_selection(key)
	elif s.current_weapon() != old_w:
		s._on_weapon_switched()


# --- Aktionen -------------------------------------------------------------------------------------------

## Gegenstand verschieben: aus „from“ (Platz oder "items") von src nach „to“ (Platz, "items" oder "drop") von dst.
## Rückgabe "" = ausgeführt, sonst Meldung. Auf Taschen/Rucksack wandert der ganze Stapel, auf einen Platz einer.
static func move(src: Node, from: String, id: int, dst: Node, to: String) -> String:
	if not is_instance_valid(src) or not is_instance_valid(dst):
		return "?"
	var a := view(src)
	var same := src == dst
	var b: Dictionary = a if same else view(dst)
	var have := count_at(a, from, id)
	if have <= 0:
		return "Gegenstand nicht vorhanden"
	if to == "drop":
		return drop(src, from, id)
	if same and from == to and from != "items":
		return ""
	if not accepts(to, id):
		return "Gegenstand passt nicht auf diesen Platz"
	# Uniform: nur von lebenden Gefangenen (Vorgabe Auftraggeber; Original T7044 an Leichen gesperrt)
	if from == "uniform" and not same and src is Soldier:
		var ss := src as Soldier
		if not ss.alive:
			return OrigInteractive.text(7044, "Uniform benutzen") + ": nur von Gefangenen"
		var br := ss.get_node_or_null("EnemyBrain")
		if br and bool(br.get("captured")) and dst is Soldier and to == "uniform":
			return _take_uniform(ss, br, dst as Soldier, id)
		return OrigInteractive.text(7044, "Uniform benutzen") + ": nur auf den eigenen Uniformplatz"
	var n: int = 1 if to in SLOTS else have
	if from in SLOTS:
		a[from] = -1
	else:
		SAS.remove_item(a, id, n)
	if to in SLOTS:
		var occ := int(b[to])
		if occ >= 0:
			if same and from in SLOTS:
				a[from] = occ
			else:
				SAS.add_item(b, occ, 1)
		b[to] = id
	else:
		SAS.add_item(b, id, n)
	# Raum (Taschen + Rucksack) und Gewicht (≤ Kraft): nur prüfen, wenn die Aktion die Last erhöht
	var before := view(dst)
	if SAS.inv_space(b) > capacity(dst, b) + 0.001 and SAS.inv_space(b) > SAS.inv_space(before) + 0.001:
		return "Kein Platz (Taschen + Rucksack)"
	# Traglast nur für Kadersoldaten (Kraft aus HumanStore.def); Übungs-/MP-Figuren haben keinen Kraftwert [P]
	if not same and dst.has_meta("sas") and SAS.inv_weight(b) > strength(dst) + 0.001 \
			and SAS.inv_weight(b) > SAS.inv_weight(before) + 0.001:
		return "Zu schwer (Traglast %d kg)" % int(strength(dst))
	var pool := weapon_pool(src)
	if not same:
		pool.append_array(weapon_pool(dst))
	if same:
		apply(src, a, pool)
	else:
		apply(src, a, pool)
		apply(dst, b, pool)
	_after_take(src, dst)
	return ""


static func _take_uniform(prisoner: Soldier, br: Node, to: Soldier, id: int) -> String:
	if not br.has_method("give_uniform") or not bool(br.call("give_uniform", to)):
		return OrigInteractive.text(7044, "Uniform benutzen") + ": nicht möglich"
	var inv := view(to)
	if not prisoner.has_meta("orig_uniform"):
		var items: Array = to.get_meta("orig_items", [])
		items.append(id)
		to.set_meta("orig_items", items)
		inv = view(to)
	var old := int(inv["uniform"])
	if old != id and SAS.remove_item(inv, id, 1) > 0:
		if old >= 0:
			SAS.add_item(inv, old, 1)
		inv["uniform"] = id
	apply(to, inv, weapon_pool(to))
	revision += 1
	return ""


## Leere Ablagestapel entfernen
static func _after_take(src: Node, dst: Node) -> void:
	for n in [src, dst]:
		if n is Pile and is_empty(n) and not Net.is_online:
			(n as Node).queue_free()


## „Ablegen“/Wegwerfen (Original T2712 bzw. Taste GEGENST. FALLENL. T2827): Gegenstand fällt vor dem Soldaten zu
## Boden (Ablagestapel, wieder aufnehmbar). Rückgabe "" = ausgeführt.
static func drop(src: Node, from: String, id: int) -> String:
	var a := view(src)
	var n := count_at(a, from, id)
	if n <= 0:
		return "Gegenstand nicht vorhanden"
	if from == "uniform" and src is Soldier and (not (src as Soldier).alive or src.has_meta("captured")):
		return OrigInteractive.text(7044, "Uniform benutzen") + ": nur von Gefangenen"
	if from in SLOTS:
		a[from] = -1
		n = 1
	else:
		SAS.remove_item(a, id, n)
	var pool := weapon_pool(src)
	var src3 := src as Node3D
	var pile: Pile = pile_near(src3.global_position) if src3 else null
	if pile == null:
		pile = spawn_pile(src3.get_parent() if src3 and src3.get_parent() else Game.current_mission(),
			src3.global_position if src3 else Vector3.ZERO, "")
	var pv := view(pile)
	SAS.add_item(pv, id, n)
	pool.append_array(weapon_pool(pile))
	apply(src, a, pool)
	apply(pile, pv, pool)
	pile.refresh_model()
	_after_take(src, pile)
	return ""


static var _pile_seq := 0


static func pile_near(p: Vector3) -> Pile:
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.get_nodes_in_group("field_piles"):
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(p) < 1.5:
			return n as Pile
	return null


static func spawn_pile(parent: Node, at: Vector3, pname: String) -> Pile:
	var pile := Pile.new()
	_pile_seq += 1
	pile.name = pname if pname != "" else "FieldPile_%d" % _pile_seq
	parent.add_child(pile)
	pile.global_position = at
	return pile


## Ablagestapel (fallengelassene Gegenstände): Weltmodell des ersten Gegenstands (items.sav), benutzbar wie
## ein durchsuchter Körper (zwei Inventare).
class Pile extends Interactable:
	var _vis: Node3D
	var _vis_item := -2

	func _ready() -> void:
		super._ready()
		add_to_group("field_piles")
		prompt = OrigInteractive.text(7025, "Nehmen")
		refresh_model()

	func can_interact(s: Soldier) -> bool:
		return enabled and s.is_player_controlled and not FieldInventory.is_empty(self)

	func interact(s: Soldier) -> void:
		FieldInventory.open_search(s, self)

	func refresh_model() -> void:
		var inv := FieldInventory.view(self)
		var first := -1
		for e in inv["items"]:
			first = int(e[0])
			break
		if first == _vis_item:
			return
		_vis_item = first
		if is_instance_valid(_vis):
			_vis.queue_free()
		_vis = null
		if first < 0:
			return
		var model := String(OrigInteractive.item_info(first).get("model", ""))
		_vis = OrigWeapons.world_model(model) if model != "" else null
		if _vis == null:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.1, 0.22)
			mi.mesh = bm
			mi.position.y = 0.05
			_vis = mi
		else:
			_vis.rotation = Vector3(0.0, 0.0, PI * 0.5)
			_vis.position.y = 0.06
		add_child(_vis)


## Durchsuchen-Ziel an einer Leiche ohne eigene Durchsuchen-Aktion (Mehrspieler-Leichen, erneutes Durchsuchen)
class SearchSpot extends Interactable:
	var body: Soldier

	func _ready() -> void:
		super._ready()
		prompt = OrigInteractive.text(7043, "Suchen & Mun. sammeln")

	func can_interact(s: Soldier) -> bool:
		return enabled and is_instance_valid(body) and not body.alive and s != body and s.is_player_controlled \
			and not FieldInventory.is_empty(body)

	func interact(s: Soldier) -> void:
		FieldInventory.open_search(s, body)


static func add_search_spot(body: Soldier) -> void:
	for c in body.get_children():
		if c is SearchSpot:
			return
	var sp := SearchSpot.new()
	sp.name = "SearchSpot"
	sp.body = body
	body.add_child(sp)
	for c in body.get_children():
		if c is Pickups.Loot:
			sp.global_position = (c as Node3D).global_position     # gleiche Stelle wie die Durchsuchen-Aktion


## Inventar-Ansicht des gesteuerten Soldaten öffnen (zweites Inventar = durchsuchter Körper/Ablagestapel)
static func open_search(s: Soldier, other: Node) -> bool:
	var m := Game.current_mission()
	if m == null or m.get("controller") == null:
		return false
	var inv_ui = (m.get("controller") as Node).get("inventory")
	if inv_ui == null or not s.is_player_controlled:
		return false
	return bool(inv_ui.open_for(s, other))


# --- Mehrspieler (Server-autoritativ: Inventaraktion als RPC, Leicheninhalt beim Server) --------------------

## Aktion des eigenen Spielers: Einzelspieler/Server sofort, Client per Net an den Server
static func request(me: Soldier, src: Node, from: String, id: int, dst: Node, to: String) -> String:
	if not Net.is_online:
		return move(src, from, id, dst, to)
	var op := {"src": key_of(src), "from": from, "id": id, "dst": key_of(dst), "to": to}
	if Net.is_authority():
		return server_execute(me, op)
	op["me"] = export_state(me)
	Net.inventory_request(op)
	return ""


static func key_of(n: Node) -> String:
	if n is Soldier:
		return "s:" + String((n as Soldier).persistent_id)
	if n:
		return "p:" + String(n.name)
	return ""


static func node_of(key: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if key.begins_with("s:"):
		var pid := key.substr(2)
		var best: Soldier = null
		for n in tree.get_nodes_in_group("soldiers"):
			var s := n as Soldier
			if s and String(s.persistent_id) == pid and (best == null or s.alive):
				best = s
		return best
	if key.begins_with("p:"):
		for n in tree.get_nodes_in_group("field_piles"):
			if String(n.name) == key.substr(2):
				return n
	return null


## Server: Aktion eines Spielers prüfen (eigener Soldat beteiligt, zweites Inventar in Reichweite) und ausführen;
## danach den Stand aller beteiligten Inventare an alle Rechner (Net._inv_state)
static func server_execute(me: Soldier, op: Dictionary) -> String:
	if not is_instance_valid(me) or not me.alive:
		return "?"
	if op.has("me") and me.net_puppet:
		import_state(me, op["me"], true)     # Munitionsstand des Spielers (seine Schüsse zählt sein Rechner)
	var src := node_of(String(op.get("src", "")))
	var dst := node_of(String(op.get("dst", "")))
	if src == null or dst == null or (src != me and dst != me):
		print("INVENTAR: Anfrage ohne eigenen Soldaten abgelehnt: %s -> %s" % [op.get("src", ""), op.get("dst", "")])
		return "?"
	var other: Node = dst if src == me else src
	if other != me:
		if other is Soldier and ((other as Soldier).alive and not other.has_meta("captured")):
			print("INVENTAR: lebender Soldat nicht durchsuchbar")
			return "?"
		# Lage des Spielers: gemeldete Position (net_target), die Netzfigur folgt ihr verzögert
		var mp: Vector3 = me.net_target if me.net_puppet else me.global_position
		if (other as Node3D).global_position.distance_to(mp) > REACH * 1.5:
			print("INVENTAR: außer Reichweite (%.1f m)" % (other as Node3D).global_position.distance_to(mp))
			return "?"
	var piles_before := {}
	for p in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("field_piles"):
		piles_before[p] = true
	var res := move(src, String(op.get("from", "")), int(op.get("id", -1)), dst, String(op.get("to", "")))
	if res != "":
		print("INVENTAR: Aktion abgelehnt (%s): %s" % [str(op.get("id", -1)), res])
	if res == "":
		var changed: Array = [src, dst]
		for p in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("field_piles"):
			if not changed.has(p) and (not piles_before.has(p) or String(op.get("to", "")) == "drop"):
				changed.append(p)
		for n in changed:
			if is_instance_valid(n):
				Net.inventory_broadcast(key_of(n), export_state(n))
	return res


static func export_state(n: Node) -> Dictionary:
	if not n is Soldier:
		var p3 := n as Node3D
		var ws: Array = []
		for w in n.get_meta("field_weapons", []):
			ws.append([String((w as Weapon).data.id), (w as Weapon).in_mag, (w as Weapon).reserve])
		return {"pile": true, "pos": [p3.global_position.x, p3.global_position.y, p3.global_position.z],
			"inv": n.get_meta("field_inv", SAS.new_inventory()), "fw": ws}
	var s := n as Soldier
	var w_out: Array = []
	for i in s.weapons.size():
		var w := s.weapons[i]
		if w:
			w_out.append([i, String(w.data.id), w.in_mag, w.reserve])
	var surr: Array = []
	for w in s.get_meta("surrendered_weapons", []):
		surr.append([String((w as Weapon).data.id), (w as Weapon).in_mag, (w as Weapon).reserve])
	return {"w": w_out, "cur": s.current_slot, "tool": s.tool, "med": s.medkits, "bin": s.has_binoculars,
		"exp": s.explosives, "mine": s.mines, "orig": s.get_meta("orig_items", []), "extra": s.get_meta("inv_extra", []),
		"layout": s.get_meta("inv_layout", {}), "surr": surr}


## Stand übernehmen (Client: vom Server; Server: Munitionsstand des anfragenden Spielers)
static func import_state(n: Node, d: Dictionary, ammo_only := false) -> void:
	revision += 1
	if not n is Soldier:
		n.set_meta("field_inv", d.get("inv", SAS.new_inventory()))
		var ws: Array = []
		for e in d.get("fw", []):
			var w := Weapon.new(WeaponDB.get_weapon(StringName(e[0])), false)
			w.in_mag = int(e[1])
			w.reserve = int(e[2])
			ws.append(w)
		n.set_meta("field_weapons", ws)
		if n is Pile:
			(n as Pile).refresh_model()
		return
	var s := n as Soldier
	if ammo_only:
		for e in d.get("w", []):
			var i := int(e[0])
			if i < s.weapons.size() and s.weapons[i] and String(s.weapons[i].data.id) == String(e[1]):
				s.weapons[i].in_mag = int(e[2])
				s.weapons[i].reserve = int(e[3])
		s.medkits = mini(s.medkits, int(d.get("med", s.medkits)))
		return
	var old_w := s.current_weapon()
	var nw: Array = []
	nw.resize(WeaponData.SLOT_COUNT)
	for e in d.get("w", []):
		var i := int(e[0])
		var w: Weapon = s.weapons[i] if i < s.weapons.size() and s.weapons[i] and String(s.weapons[i].data.id) == String(e[1]) else null
		if w == null:
			w = Weapon.new(WeaponDB.get_weapon(StringName(e[1])), false)
		w.in_mag = int(e[2])
		w.reserve = int(e[3])
		if i < nw.size():
			nw[i] = w
	s.weapons.clear()
	for w in nw:
		s.weapons.append(w as Weapon)
	var surr: Array = []
	for e in d.get("surr", []):
		var w := Weapon.new(WeaponDB.get_weapon(StringName(e[0])), false)
		w.in_mag = int(e[1])
		w.reserve = int(e[2])
		surr.append(w)
	if not surr.is_empty() or s.has_meta("surrendered_weapons"):
		s.set_meta("surrendered_weapons", surr)
	s.medkits = int(d.get("med", 0))
	s.has_binoculars = bool(d.get("bin", false))
	s.explosives = int(d.get("exp", 0))
	s.mines = int(d.get("mine", 0))
	s.set_meta("orig_items", (d.get("orig", []) as Array).duplicate())
	s.set_meta("inv_extra", (d.get("extra", []) as Array).duplicate(true))
	s.set_meta("inv_layout", (d.get("layout", {}) as Dictionary).duplicate())
	s.current_slot = clampi(int(d.get("cur", s.current_slot)), 0, WeaponData.SLOT_COUNT - 1)
	s.tool = String(d.get("tool", ""))
	if s.alive and (s.current_weapon() != old_w or not s.net_puppet):
		s._on_weapon_switched()


## Client: Stand vom Server (Net._inv_state); fehlende Ablagestapel werden angelegt
static func receive_state(key: String, d: Dictionary) -> void:
	var n := node_of(key)
	if n == null and key.begins_with("p:") and d.get("pile", false):
		var m := Game.current_mission()
		if m == null:
			return
		var pa: Array = d.get("pos", [0, 0, 0])
		var parent: Node = m.get("dynamic_root") if m.get("dynamic_root") != null else m
		n = spawn_pile(parent, Vector3(float(pa[0]), float(pa[1]), float(pa[2])), key.substr(2))
	if n:
		import_state(n, d)
