class_name SAS
extends RefCounted
## Original-Kader, Werte, Inventar und Training (Hidden & Dangerous 2, belegt in
## docs/re_notes_roster_inventory.md; Daten: orig_cache/roster.json, inventory_rules.json, items.json).
##
## Kader: SAS-Soldaten 0–29 aus TABLES\HumanStore.def (Name, Porträt, Biografie, Rang, 9 Werte).
## Werte: Gesundheit, Kraft (= Traglast in kg), Ausdauer, Moral, Schießen, ?, Tarnung, Erste Hilfe, Schlösser.
## Inventar wie im Original (Kopf, Uniform, Hände, Schulter, Rücken = Rucksack-Gegenstand, Taschen 12 Einheiten,
## Rucksackinhalt) – mit EINER Vereinfachung (Vorgabe Auftraggeber): Taschen und Rucksackinhalt bilden
## ein gemeinsames Inventar; Kapazität = 12 + Raum des Rucksacks, kein manuelles Umschichten.
## Gesamtgewicht ≤ Kraft wie im Original.

const POCKET_SPACE := 12.0
const SLOTS := ["head", "uniform", "hands", "back", "shoulder"]
const SLOT_TEXT := {"head": 2711, "uniform": 2714, "hands": 2713, "back": 2710, "shoulder": 2715}
## Anzeige im Auswahlbildschirm (Original-Texte 2670–2676 bzw. Kürzel 2680–2686)
const STAT_PANEL := [["shooting", 2670, 2680], ["strength", 2671, 2681], ["health", 2672, 2682],
	["endurance", 2673, 2683], ["stealth", 2674, 2684], ["first_aid", 2675, 2685], ["lockpick", 2676, 2686]]
const MEDKITS := [53, 54]
const BINOCULARS := 99

static var _roster: Dictionary = {}
static var _rules: Dictionary = {}
static var _items: Dictionary = {}       ## Nummer -> Eintrag aus inventory_rules.items
static var _weapons: Dictionary = {}     ## Nummer -> Waffenwerte aus items.json
static var _presets: Dictionary = {}     ## Index -> Preset aus presets.def
static var _texts: Dictionary = {}


static func available() -> bool:
	return FileAccess.file_exists(OrigLevel.cache_root() + "/roster.json") \
		and FileAccess.file_exists(OrigLevel.cache_root() + "/inventory_rules.json")


static func _load() -> void:
	if not _roster.is_empty():
		return
	var r = LsRuntime._read_json(OrigLevel.cache_root() + "/roster.json")
	_roster = r if typeof(r) == TYPE_DICTIONARY else {}
	var i = LsRuntime._read_json(OrigLevel.cache_root() + "/inventory_rules.json")
	_rules = i if typeof(i) == TYPE_DICTIONARY else {}
	for it in _rules.get("items", []):
		_items[int(it["item"])] = it
	for k in WeaponDB.EXTRA_ITEMS:          # eigene Gegenstände (Panzerfaust-Rakete, Vorgabe Auftraggeber)
		_items[int(k)] = WeaponDB.EXTRA_ITEMS[k]
	for p in _rules.get("presets_def", {}).get("presets", []):
		_presets[int(p["index"])] = p
	var w = LsRuntime._read_json(OrigLevel.cache_root() + "/items.json")
	if typeof(w) == TYPE_DICTIONARY:
		for wp in w.get("weapons", []):
			_weapons[int(wp["id"])] = wp
	var t = LsRuntime._read_json(OrigLevel.cache_root() + "/texts_german.json")
	_texts = t if typeof(t) == TYPE_DICTIONARY else {}


static func text(id: int, fallback := "") -> String:
	_load()
	var s := String(_texts.get(str(id), ""))
	return s if s != "" else fallback


static func store(idx: int) -> Dictionary:
	_load()
	for s in _roster.get("soldiers", []):
		if int(s.get("store_index", -1)) == idx:
			return s
	return {}


static func store_indices() -> Array:
	_load()
	var out: Array = []
	for s in _roster.get("soldiers", []):
		var idx := int(s.get("store_index", -1))
		if idx >= 0 and idx <= 29 and s.get("selectable_sp", true):
			out.append(idx)
	return out


## Neuer Kampagnenstand: alle 30 SAS-Soldaten mit Originalwerten
static func new_states() -> Dictionary:
	var out := {}
	for idx in store_indices():
		var s := store(idx)
		out[str(idx)] = {"stats": (s.get("stats", {}) as Dictionary).duplicate(), "rank": int(s.get("rank", 0)),
			"experience": int(s.get("experience", 0)), "dead": false, "medals": [], "missions": 0}
	return out


static func display_name(idx: int) -> String:
	var s := store(idx)
	if s.is_empty():
		return "Soldat %d" % idx
	var nick := String(s["nickname"]) if s.get("nickname") != null else ""
	return "%s %s" % [s.get("first_name", ""), s.get("last_name", "")] + (" „%s“" % nick if nick != "" else "")


static func short_name(idx: int, rank: int) -> String:
	var s := store(idx)
	return "%s %s" % [rank_name(rank, true), s.get("last_name", "Soldat %d" % idx)]


static func rank_name(rank: int, abbr := false) -> String:
	_load()
	for r in _roster.get("ranks", []):
		if int(r.get("rank", -1)) == rank:
			return text(int(r.get("abbr_text_id" if abbr else "text_id", -1)), String(r.get("name", "")))
	return ""


static func rank_thresholds() -> Array:
	_load()
	var out: Array = []
	for r in _roster.get("ranks", []):
		if r.get("promote_when_total_xp_gt") != null:
			out.append(int(r["promote_when_total_xp_gt"]))
	return out


static func bio(idx: int) -> String:
	return String(store(idx).get("bio_de", ""))


static func portrait_path(idx: int) -> String:
	return OrigLevel.cache_root() + "/ui/hud/faces/x_f_%s.png" % String(store(idx).get("portrait_id", "001"))


## Original-Auto-Auswahl (0x695450): Platz 1 und 3 beste Schießen, Platz 2 beste Erste Hilfe,
## Platz 4 beste (Kraft − 0,1·Schießen); jeweils zufällig aus den besten 5
static func auto_select(states: Dictionary, size: int, keep: Array = []) -> Array:
	var team: Array = keep.duplicate()
	var crit := [func(st): return float(st["shooting"]), func(st): return float(st["first_aid"]),
		func(st): return float(st["shooting"]), func(st): return float(st["strength"]) - 0.1 * float(st["shooting"])]
	while team.size() < size:
		var pool: Array = []
		for k in states:
			if not states[k]["dead"] and not team.has(int(k)):
				pool.append(int(k))
		if pool.is_empty():
			break
		var c: Callable = crit[team.size() % 4]
		pool.sort_custom(func(a, b): return c.call(states[str(a)]["stats"]) > c.call(states[str(b)]["stats"]))
		team.append(pool[randi() % mini(5, pool.size())])
	return team


# --- Missionsdaten (Gamedata00.gdt, miss_itm.def) ---------------------------------

static func mission_info(folder: String) -> Dictionary:
	_load()
	for m in _rules.get("missions", []):
		if String(m.get("folder", "")).to_upper() == folder.to_upper():
			return m
	return {}


## Original: Teamauswahl nur bei Kampagnenbeginn bzw. wo die Mission sie vorsieht („select“),
## Auffüllen gefallener Plätze („refill“), sonst bleibt das Team („keep“).
static func team_mode(info: Dictionary) -> String:
	var t = info.get("team_selection")
	return t if t is String else "keep"


static func recommended_presets(info: Dictionary) -> Array:
	var out: Array = []
	for r in info.get("recommended", []):
		out.append(int(r.get("preset", -1)))
	return out


static func essentials(info: Dictionary) -> Array:
	var out: Array = []
	for e in info.get("mission_essentials", []):
		out.append([int(e["item"]), int(e.get("count", 1))])
	return out


# --- Gegenstände / Inventar --------------------------------------------------------

static func item(id: int) -> Dictionary:
	_load()
	return _items.get(id, {})


static func item_name(id: int) -> String:
	return String(item(id).get("name", "#%d" % id))


## Anzeigename aus den deutschen Originaltexten (items.sav Text-ID, z. B. 1229 „Kamera“), sonst interner Name
static func item_label(id: int) -> String:
	_load()
	var d: Dictionary = _item_data().get(id, {})
	var tid := int(d.get("text_id", 1000 + id))
	var t := text(tid, "")
	return t if t != "" else item_name(id)


## Symbol des Gegenstands (items.sav-Feld „icon“, 64×32) aus orig_cache/ui/menu/items (tools/_menu_export.py)
static func item_icon_path(id: int) -> String:
	var ic := String(_item_data().get(id, {}).get("icon", "")).to_lower()
	if ic == "":
		return ""
	var p := OrigLevel.cache_root() + "/ui/menu/items/%s.png" % ic
	return p if FileAccess.file_exists(p) else ""


## Lager-Klassifizierung des Inventarbildschirms (Texte 2719–2725, Gruppen GR_SmallWeapons … GR_Other in
## hd2.exe 0x67C270). Zuordnung über die Item-Gruppe (items.sav u70) = Annahme [P]:
## 0 leichte Waffen (Pistolen/Gewehre), 1 mittlere (MP/MG), 2 schwere (Raketenwerfer/Stellungen),
## 3 Sprengstoffe (Granaten, Ladungen, Minen), 4 Uniformen (Kopf/Uniform), 5 zusätzliche Ausrüstung.
## Magazine erscheinen bei ihrer Waffe (Zeile Waffe + Magazin wie im Original, item08/item09).
const CATEGORY_TEXT := [2719, 2720, 2721, 2723, 2724, 2725]


static func item_category(id: int) -> int:
	var d: Dictionary = _item_data().get(id, {})
	var g := int(d.get("u70", 9))
	var k := item_kind(id)
	if k == "weapon":
		if g in [5, 6]:
			return 0
		if g == 7:
			return 1
		if g in [0, 8]:
			return 2
		if g == 12 or (g == 9 and not item_name(id).to_lower().contains("knife")):
			return 3
		return 5
	if k != "ammo" and slot_for(id) in ["head", "uniform"]:
		return 4
	return 5


static var _item_full: Dictionary = {}


static func _item_data() -> Dictionary:
	if _item_full.is_empty():
		var w = LsRuntime._read_json(OrigLevel.cache_root() + "/items.json")
		if typeof(w) == TYPE_DICTIONARY:
			for it in w.get("items", []):
				_item_full[int(it["id"])] = it
		for k in WeaponDB.EXTRA_ITEMS:
			_item_full[int(k)] = WeaponDB.EXTRA_ITEMS[k]
	return _item_full


## Waffe, zu der ein Magazin gehört (-1 = keine)
static func weapon_of_ammo(ammo_item: int) -> int:
	_load()
	for k in WeaponDB.LAUNCHER_AMMO:        # Raketen der Werfer (Bazooka 206, Panzerschreck 205, Panzerfaust-Rakete)
		if int(WeaponDB.LAUNCHER_AMMO[k]) == ammo_item:
			return int(k)
	for k in _weapons:
		if int(_weapons[k].get("ammo_item", -1)) == ammo_item:
			return int(k)
	return -1


## Soldatentyp-Vorlagen des Inventarbildschirms (presets.def, Flags 0x04 Liste + 0x20 Alliierte, Sätze 32–40);
## Namen = Originaltexte 6508–6516 (Zuordnung über die Vorlagennamen = Annahme [P])
const PRESET_TEXT := {32: 6510, 33: 6511, 34: 6508, 35: 6509, 36: 6514, 37: 6515, 38: 6512, 39: 6513, 40: 6516}


static func soldier_type_presets() -> Array:
	_load()
	var out: Array = []
	for k in _presets:
		var f := int(_presets[k].get("flags", 0))
		if f & 0x04 and f & 0x20:
			out.append(int(k))
	out.sort()
	return out


static func preset_label(index: int) -> String:
	if PRESET_TEXT.has(index):
		return text(PRESET_TEXT[index], preset_name(index))
	return preset_name(index)


static func item_kind(id: int) -> String:
	return String(item(id).get("kind", "equipment"))


static func weight(id: int) -> float:
	return float(item(id).get("weight_kg", 0.0))


static func space(id: int) -> float:
	var it := item(id)
	if it.has("space_units"):
		return float(it["space_units"])
	var sc := int(it.get("size_class", 0))
	return 1.0 if sc == 0 else 2.0 * sc


static func backpack_space(id: int) -> float:
	_load()
	for b in _rules.get("back_slot_items", []):
		if int(b["item"]) == id:
			return float(b.get("space_units", 0))
	return 0.0


static func is_backpack(id: int) -> bool:
	return backpack_space(id) > 0.0


static func ammo_of(weapon_item: int) -> int:
	_load()
	if WeaponDB.LAUNCHER_AMMO.has(weapon_item):
		return int(WeaponDB.LAUNCHER_AMMO[weapon_item])
	return int(_weapons.get(weapon_item, {}).get("ammo_item", -1))


static func new_inventory() -> Dictionary:
	return {"hands": -1, "shoulder": -1, "head": -1, "uniform": -1, "back": -1, "items": []}


## Inventar aus einem Original-Preset (presets.def): Taschen und Rucksackinhalt zusammengeführt
static func preset_inventory(index: int) -> Dictionary:
	_load()
	var p: Dictionary = _presets.get(index, {})
	var inv := new_inventory()
	if p.is_empty():
		return inv
	inv["hands"] = int(p.get("hands", -1))
	inv["shoulder"] = int(p.get("shoulder", -1))
	inv["head"] = int(p.get("head", -1))
	inv["uniform"] = int(p.get("uniform", -1))
	inv["back"] = int(p.get("backpack", -1))
	for e in p.get("pockets", []) + p.get("backpack_contents", []):
		if e is Array and e.size() >= 1:
			add_item(inv, int(e[0]), int(e[1]) if e.size() > 1 else 1)
	return inv


static func preset_name(index: int) -> String:
	_load()
	return String(_presets.get(index, {}).get("name", "#%d" % index))


static func inv_weight(inv: Dictionary) -> float:
	var w := 0.0
	for k in SLOTS:
		if int(inv.get(k, -1)) >= 0:
			w += weight(int(inv[k]))
	for e in inv.get("items", []):
		w += weight(int(e[0])) * int(e[1])
	return w


static func inv_space(inv: Dictionary) -> float:
	var s := 0.0
	for e in inv.get("items", []):
		s += space(int(e[0])) * int(e[1])
	return s


static func inv_capacity(inv: Dictionary) -> float:
	return POCKET_SPACE + backpack_space(int(inv.get("back", -1)))


static func overloaded(inv: Dictionary, strength: float) -> bool:
	return inv_weight(inv) > strength + 0.001 or inv_space(inv) > inv_capacity(inv) + 0.001


## Passt der Gegenstand (Anzahl) ins gemeinsame Inventar? Gewicht ≤ Kraft, Raum ≤ Taschen + Rucksack
static func can_add(inv: Dictionary, strength: float, id: int, count: int = 1) -> bool:
	if inv_weight(inv) + weight(id) * count > strength + 0.001:
		return false
	return inv_space(inv) + space(id) * count <= inv_capacity(inv) + 0.001


static func count_of(inv: Dictionary, id: int) -> int:
	var n := 0
	for k in SLOTS:
		if int(inv.get(k, -1)) == id:
			n += 1
	for e in inv.get("items", []):
		if int(e[0]) == id:
			n += int(e[1])
	return n


static func add_item(inv: Dictionary, id: int, count: int = 1) -> void:
	for e in inv["items"]:
		if int(e[0]) == id:
			e[1] = int(e[1]) + count
			return
	inv["items"].append([id, count])


static func remove_item(inv: Dictionary, id: int, count: int = 1) -> int:
	for e in inv["items"]:
		if int(e[0]) == id:
			var n := mini(count, int(e[1]))
			e[1] = int(e[1]) - n
			if int(e[1]) <= 0:
				inv["items"].erase(e)
			return n
	return 0


## Passender Ausrüstungsplatz für einen Gegenstand (Hände für Langwaffen, Kopf, Uniform, Rücken);
## "" = gemeinsames Inventar (Taschen + Rucksack)
static func slot_for(id: int) -> String:
	var nm := item_name(id).to_lower()
	if is_backpack(id) or id in [231, 243, 244]:
		return "back"
	if nm.begins_with("uniform") or nm.begins_with("npc_") or id in [266, 267, 268, 269, 272, 273, 274, 275, 277]:
		return "uniform"
	if nm.contains("helm") or nm.contains("cap ") or nm.contains("baret") or nm.contains("brigad") or nm.contains("lodic") \
			or nm.contains("klobouk") or nm.contains("beranice") or nm.contains("turban") or nm.contains("kulich"):
		return "head"
	if item_kind(id) == "weapon":
		var wd := WeaponDB.from_orig(id)
		if wd and wd.slot == WeaponData.Slot.PRIMARY:
			return "hands"
	return ""


## Spielausrüstung aus dem Inventar: [Primärwaffe, Seitenwaffe, Granate], Magazine je Waffe,
## Granatenzahl, Verbandskästen, Fernglas, alle Originalnummern (für _IsInInventory)
static func to_loadout(inv: Dictionary) -> Dictionary:
	_load()
	var primary := ""
	var side := ""
	var nade := ""
	var nade_count := 0
	var launcher := ""
	var launcher_shots := 0
	var knife := ""
	var all_ids: Array = []
	var weapons: Array = []
	for k in ["hands", "shoulder"]:
		if int(inv.get(k, -1)) >= 0:
			weapons.append(int(inv[k]))
	for e in inv.get("items", []):
		for n in int(e[1]):
			all_ids.append(int(e[0]))
		if item_kind(int(e[0])) == "weapon" and not weapons.has(int(e[0])):
			weapons.append(int(e[0]))
	for k in SLOTS:
		if int(inv.get(k, -1)) >= 0:
			all_ids.append(int(inv[k]))
	var mags := {}
	for wid in weapons:
		var wd := WeaponDB.from_orig(wid)
		if wd == null:
			continue
		match wd.slot:
			WeaponData.Slot.SIDEARM:
				if side == "":
					side = String(wd.id)
					mags[side] = count_of(inv, ammo_of(wid))
			WeaponData.Slot.PRIMARY:
				if primary == "":
					primary = String(wd.id)
					mags[primary] = count_of(inv, ammo_of(wid))
			WeaponData.Slot.GRENADE:
				if nade == "":
					nade = String(wd.id)
					nade_count = count_of(inv, wid)
			WeaponData.Slot.LAUNCHER:
				if launcher == "":
					launcher = String(wd.id)
					# Panzerfaust: Einwegwaffe (Anzahl Waffen), sonst Raketen aus dem Inventar
					launcher_shots = count_of(inv, wid) if not WeaponDB.LAUNCHER_AMMO.has(wid) \
						else 1 + count_of(inv, int(WeaponDB.LAUNCHER_AMMO[wid]))
			WeaponData.Slot.MELEE:
				knife = String(wd.id)
	var medkits := 0
	for m in MEDKITS:
		medkits += count_of(inv, m)
	return {"loadout": [primary, side, nade, launcher, knife], "mags": mags, "grenades": nade_count,
		"launcher_shots": launcher_shots, "explosives": count_of(inv, 67) + count_of(inv, 68),
		"mines": count_of(inv, 70) + count_of(inv, 71), "medkits": medkits,
		"binoculars": count_of(inv, BINOCULARS) > 0, "items": all_ids}


## Lager vor einer Mission (Original Gamedata00.gdt: Typ 3 = neu befüllen aus den 0x18-Sätzen, Typ 4 = behalten).
## Satz mit Flag „ammo_of_weapon“: Anzahl = Magazine der Munition dieser Waffe (resolved_item).
static func mission_storage(info: Dictionary, current: Array) -> Array:
	if info.get("equipment_screen") != "equipment_new_storage" and not current.is_empty():
		return current
	var out: Array = []
	for r in info.get("storage_items_campaign", []):
		var id := int(r.get("resolved_item", r.get("item", -1)))
		if id < 0:
			continue
		var found := false
		for e in out:
			if int(e[0]) == id:
				e[1] = int(e[1]) + int(r.get("count", 1))
				found = true
		if not found:
			out.append([id, int(r.get("count", 1))])
	# Panzerfaust-Raketen (Vorgabe Auftraggeber, kein Originalgegenstand): je Panzerfaust im Lager zwei Raketen
	var pf := count_of({"items": out}, 38)
	if pf > 0 and count_of({"items": out}, WeaponDB.PANZERFAUST_AMMO) == 0:
		out.append([WeaponDB.PANZERFAUST_AMMO, pf * 2])
	return out if not out.is_empty() else current


# --- Training ---------------------------------------------------------------------

## Trainingszuwachs einer Mission aus den Zählern (roster.json „training“, Original 0x5A88F0/0x5A0BE0):
## Schießen +0,04 je Abschuss (max. 2), Tarnung +0,05 je 20 s Schleichen bzw. +0,03 je Abschuss eines
## ahnungslosen Gegners (max. 2), Ausdauer +0,1 je 25 s Sprint (max. 5), Erste Hilfe +0,1 je Verband (max. 5),
## Schlösser +0,5 je Schloss (max. 5), fest je Mission: Kraft +0,5, Moral +1.
static func training_gain(counters: Dictionary) -> Dictionary:
	_load()
	var tr: Dictionary = _roster.get("training", {})
	var cap := func(key: String, dflt: float) -> float: return float(tr.get(key, {}).get("per_mission_cap", dflt))
	var st: Dictionary = tr.get("stealth", {})
	return {
		"shooting": minf(float(tr.get("shooting", {}).get("gain_kill", 0.04)) * float(counters.get("kills", 0.0)), cap.call("shooting", 2.0)),
		"stealth": minf(float(st.get("gain_sneak", 0.05)) * floorf(float(counters.get("sneak_s", 0.0)) / 20.0)
			+ float(st.get("gain_kill_unaware", 0.03)) * float(counters.get("unseen_kills", 0.0)), cap.call("stealth", 2.0)),
		"endurance": minf(float(tr.get("endurance", {}).get("gain", 0.1)) * floorf(float(counters.get("sprint_s", 0.0)) / 25.0), cap.call("endurance", 5.0)),
		"first_aid": minf(float(tr.get("first_aid", {}).get("gain_use", 0.1)) * float(counters.get("heals", 0.0)), cap.call("first_aid", 5.0)),
		"lockpick": minf(float(tr.get("lockpick", {}).get("gain_use", 0.5)) * float(counters.get("locks", 0.0)), cap.call("lockpick", 5.0)),
		"strength": float(tr.get("strength", {}).get("fixed_per_mission", 0.5)),
		"morale": float(tr.get("morale", {}).get("fixed_per_mission", 1.0)),
	}


## Erfahrung einer Mission (Original 0x5A9640, re_notes_roster_inventory §3): Feind getötet +300, wenn er
## ahnungslos war, sonst +100; Ziel erfüllt: jeder Lebende +1000 je erfülltem Ziel (die +1500-Variante mit
## Ziel-Flag +0x14 ist nicht zugeordnet [P]). survived/success bleiben für die Aufrufer erhalten.
static func experience_gain(counters: Dictionary, survived: bool, _success: bool, objectives_done := 0) -> int:
	var kills := float(counters.get("kills", 0.0))
	var unseen := minf(float(counters.get("unseen_kills", 0.0)), kills)
	# Wehrlose getötet (0x5A0BE0): Gefangener −1000, Ergebener −500
	var penalty := 1000.0 * float(counters.get("prisoner_kills", 0.0)) + 500.0 * float(counters.get("defenseless_kills", 0.0))
	return int(100.0 * (kills - unseen) + 300.0 * unseen + (1000.0 * objectives_done if survived else 0.0) - penalty)


# --- Orden (12 Orden, Texte 10100+2·id; Vergabe hd2.exe 0x68C900, re_work/roster/d10.c) ---------------
## Kampagnen-Index wie FUN_006b8f90 (0 Tutorial … 7 Tschechien)
const CAMPAIGN_INDEX := {"tutorial": 0, "arctic": 1, "africa": 2, "norway": 3, "burma": 4, "alps": 5, "normandy": 6, "czech": 7}
const MEDAL_DEFENCE := 6


static func medal_name(id: int) -> String:
	return text(10100 + 2 * id, "Orden %d" % id)


static func medal_text(id: int) -> String:
	return text(10101 + 2 * id, "")


## Neuer Orden nach einer Mission (höchstens einer je Mission, Feld Team-Mitglied +0x38) wie 0x68C900:
## st = Kaderstand nach dem Hochzählen der Missionszähler, xp = Erfahrung dieser Mission, camp = Kampagnen-Index.
## Lebende: Germany-France Star (Alpen/Normandie), Burma Star, Africa Star bzw. Africa GSM (Afrika, nach Rang und
## Einsätzen); dann für alle VC ab 15000 XP; nur Lebende: MC ab 12000, MM ab 11000, DSO ab 10000, DCM ab 9000,
## War Medal und GSM nach Einsätzen und Rang. Zähler +0x3C/+0x40 = beide „missions“ (je Mission +1) [P].
static func award_medal(st: Dictionary, xp: int, camp: int) -> int:
	var has := func(m: int) -> bool: return (st.get("medals", []) as Array).has(m)
	var dead := bool(st.get("dead", false))
	var rank := int(st.get("rank", 0))
	var n := int(st.get("missions", 0))
	var out := -1
	if not dead:
		if camp in [5, 6] and not has.call(9):
			return 9
		if camp == 4 and not has.call(11):
			return 11
		if camp == 2:
			if not has.call(10):
				return 10
			if not has.call(3):
				var need := {2: 3, 3: 2, 4: 1, 5: 0}
				if need.has(n) and rank >= int(need[n]):
					return 3
	if xp >= 15000 and not has.call(8):
		out = 8
	if dead:
		return out
	if xp >= 12000 and not has.call(7):
		return 7
	if xp >= 11000 and not has.call(2):
		return 2
	if xp >= 10000 and not has.call(0):
		return 0
	if xp >= 9000 and not has.call(1):
		return 1
	if not has.call(5):
		var need5 := {1: 3, 2: 2, 3: 1, 4: 0}
		if need5.has(n) and rank >= int(need5[n]):
			out = 5
	if camp != 2 and not has.call(4):
		var need4 := {5: 3, 6: 2, 7: 1, 8: 0}
		if need4.has(n) and rank >= int(need4[n]):
			out = 4
	return out


## Nach der Mission (Original): Team erhält eigenen Zuwachs (Werte max. 100); alle übrigen lebenden Soldaten
## je Wert den Team-Durchschnitt × Zufallsfaktor 0,6–1,4 (roster.json „reserve_gain“).
## Erfahrung/Ränge für das Team. Rückgabe: Beförderte.
static func apply_mission(states: Dictionary, team: Array, gains: Dictionary, exp_gain: Dictionary) -> Array:
	var promoted: Array = []
	var avg := {}
	var alive_team := 0
	for idx in team:
		if gains.has(idx):
			alive_team += 1
	for idx in gains:
		var g: Dictionary = gains[idx]
		for k in g:
			avg[k] = avg.get(k, 0.0) + float(g[k]) / maxf(alive_team, 1)
	var thresholds := rank_thresholds()
	for k in states:
		var idx := int(k)
		var st: Dictionary = states[k]
		if st["dead"]:
			continue
		var g2: Dictionary = {}
		if team.has(idx):
			g2 = gains.get(idx, {})
		else:
			for key in avg:
				g2[key] = avg[key] * randf_range(0.6, 1.4)
		for key in g2:
			if st["stats"].has(key):
				var cap := 1000.0 if key == "health" else 100.0
				st["stats"][key] = minf(float(st["stats"][key]) + float(g2[key]), cap)
		if team.has(idx):
			st["missions"] = int(st.get("missions", 0)) + 1
			st["experience"] = int(st["experience"]) + int(exp_gain.get(idx, 0))
			var r := 0
			for th in thresholds:
				if int(st["experience"]) > th:
					r += 1
			if r > int(st["rank"]):
				st["rank"] = int(st["rank"]) + 1      # höchstens ein Rang je Mission
				promoted.append(idx)
	return promoted
