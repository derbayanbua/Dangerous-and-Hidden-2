class_name MpLoadout
extends RefCounted
## Einzel-Ausrüstung im Mehrspieler (SPIELER-SETUP, player screen.4ds): Inventar im SAS-Format (Kopf, Hände, Schulter,
## Uniform, Rücken + gemeinsames Inventar Taschen/Rucksack wie im Einzelspieler-Ausrüstungsbildschirm) aus den auf der
## Karte erlaubten Gegenständen (ALLOWEDITEMS → Lager je Spieler: item_num, Munition der Waffe ammo_num; hd2.exe
## 0x6186F0/0x6A5C30). Prüfung wie im Original-Ausrüstungsbildschirm: Gegenstand im Lager der eigenen Seite (sonst
## Hinweis 9522), Gesamtgewicht ≤ Kraft der Figur und Raum ≤ Taschen (12) + Rucksack (sonst 2023), Gegenstand auf
## passendem Platz. Kopf = Standardhelm der Uniform (items.sav Uniform equip_raw[3], z. B. GE03 → 76) [B Daten,
## P Bedeutung]; ohne Uniform der Helm einer Klassen-Vorlage der Seite.
## Karten ohne Freigabeliste (Arena): keine Lagergrenze, nur Gewicht/Raum/Plätze.

const MAX_ITEMS := 46            ## 14 Taschen- + 32 Rucksackpaare (user_presets_orig.def)
const UserPresets := preload("res://src/campaign/user_presets.gd")
static var _style_cache := {}


## Spielstil (mp.json game_styles[0]: presets, allowed_items) einer Karte; eigene Karten über
## Registerschlüssel "mp_allowed_from" (Game.mp_allowed_from); Arena-Karten ohne MP-Daten: {}
static func map_style(map: String) -> Dictionary:
	if _style_cache.has(map):
		return _style_cache[map]
	var folder := Game.orig_folder(map).to_lower()
	var custom: String = Game.mp_allowed_from(map)
	if custom != "":
		folder = custom
	var st := {}
	if folder != "":
		var d = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/mp.json")
		if typeof(d) == TYPE_DICTIONARY and not (d.get("game_styles", []) as Array).is_empty():
			st = d["game_styles"][0]
	_style_cache[map] = st
	return st


## ALLOWEDITEMS der Karte (leer = keine Freigabeliste)
static func map_allowed(map: String) -> Array:
	return map_style(map).get("allowed_items", [])


# --- Eigene MP-Vorlagen (user_presets_orig.def, „Axis/Allied/Deadmatch user preset1–6“, hd2.exe 0x67DC0A ff.) ---
## SPEICHERN (hd2.exe 0x687C60): gewählte Vorlage j der Seite (0x4C4) wird mit der aktuellen Ausrüstung belegt
## (0x6878D0); Seite 0/1/2 → Flags 0x10/0x20/0x40 | 2 = 18 Achse / 34 Alliierte / 66 Deathmatch = Blöcke 0/1/2.
## Trägt die Vorlage noch den Standardnamen (Text-ID ≠ −1), erhält sie „<Basis><j+1>“ und Text-ID −1; Name ≤ 29
## Zeichen; danach wird die Datei geschrieben (0x67D930). Basistext (globale Zeichenkette 0x8AE91C) nicht
## aufgelöst → „Vorlage “ [P]. UMBENENNEN (Knopf brename preset, nur bei gewählter eigener Vorlage) [P Dialog].
static func preset_block(team: int, dm: bool) -> int:
	return 2 if dm else (0 if team == Soldier.TEAM_AXIS else 1)


static func user_presets(block: int) -> Array:
	return UserPresets.load_all().slice(block * 6, block * 6 + 6)


static func user_preset_empty(p: Dictionary) -> bool:
	return UserPresets.is_empty(p)


static func user_preset_label(p: Dictionary) -> String:
	return UserPresets.label(p)


static func user_preset_inventory(p: Dictionary) -> Dictionary:
	return UserPresets.to_inventory(p)


static func save_user_preset(block: int, j: int, inv: Dictionary) -> Dictionary:
	var all := UserPresets.load_all()
	var k := block * 6 + j
	var old: Dictionary = all[k]
	var nm := String(old.get("name", ""))
	var tid := int(old.get("text_id", 6530 + k % 18))
	if tid != -1 or nm == "":
		nm = "Vorlage %d" % (j + 1)
		tid = -1
	all[k] = to_preset(inv, nm, int(UserPresets.BLOCK_FLAGS[block]), tid)
	UserPresets.save_all(all)
	return all[k]


static func rename_user_preset(block: int, j: int, nm: String) -> void:
	var all := UserPresets.load_all()
	var k := block * 6 + j
	all[k]["name"] = nm.strip_edges().substr(0, 29)
	all[k]["text_id"] = -1 if String(all[k]["name"]) != "" else 6530 + k % 18
	UserPresets.save_all(all)


## Kraft (= Traglast kg) der gewählten Figur: MP-Figur HumanStore 30–56, sonst Satz 30
static func strength_of(figure: String) -> float:
	var idx: int = int(figure.substr(3)) if figure.begins_with("mp:") else 30
	return float(SAS.store(idx).get("stats", {}).get("strength", 30.0))


## Typfeld der Ausrüstung (items.sav equip_raw[1]: 15 Uniform, 16 Kopf, 17 Rucksack)
static func equip_type(id: int) -> int:
	var eq = OrigInteractive.item_info(id).get("equip_raw", [])
	return int(eq[1]) if eq is Array and (eq as Array).size() > 1 else 0


## Standardhelm einer Uniform (−1 = keiner)
static func uniform_head(uniform: int) -> int:
	if uniform < 0:
		return -1
	var eq = OrigInteractive.item_info(uniform).get("equip_raw", [])
	return int(eq[3]) if eq is Array and (eq as Array).size() > 3 else -1


## Platz eines Gegenstands: hands (Langwaffe, auch Schulter), uniform, head, back oder "" (Taschen/Rucksack)
static func slot_of(id: int) -> String:
	match equip_type(id):
		15:
			return "uniform"
		16:
			return "head"
		17:
			return "back"
	if SAS.is_backpack(id):
		return "back"
	return SAS.slot_for(id)


## Netzdaten → sauberes Inventar (fremde Typen, negative Anzahlen, zu viele Einträge verworfen)
static func sanitize(inv) -> Dictionary:
	var out := SAS.new_inventory()
	if not inv is Dictionary:
		return out
	for k in SAS.SLOTS:
		var v = (inv as Dictionary).get(k, -1)
		out[k] = int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else -1
	var items = (inv as Dictionary).get("items", [])
	if items is Array:
		for e in items:
			if e is Array and (e as Array).size() >= 2 and typeof(e[0]) in [TYPE_INT, TYPE_FLOAT]:
				var id := int(e[0])
				var n := clampi(int(e[1]), 0, 99)
				if id >= 0 and n > 0 and (out["items"] as Array).size() < MAX_ITEMS:
					SAS.add_item(out, id, n)
	return out


static func is_empty(inv: Dictionary) -> bool:
	for k in SAS.SLOTS:
		if int(inv.get(k, -1)) >= 0:
			return false
	return (inv.get("items", []) as Array).is_empty()


## Lager je Spieler für eine Seite (nur Gegenstände der Seite)
static func storage(allowed: Array, team: int) -> Dictionary:
	return Net.storage_of(allowed, team, true)


## Noch verfügbare Anzahl eines Gegenstands (Lager − bereits am Soldaten); ohne Freigabeliste unbegrenzt
static func remaining(inv: Dictionary, allowed: Array, team: int, id: int) -> int:
	if allowed.is_empty():
		return 99
	return int(storage(allowed, team).get(id, 0)) - SAS.count_of(inv, id)


## Erlaubte Helme (Kopf gehört zur Uniform; Vorlagen-Helme der Seite)
static func heads_for(inv: Dictionary, presets: Array, side: String) -> Array:
	var out: Array = []
	var h := uniform_head(int(inv.get("uniform", -1)))
	if h >= 0:
		out.append(h)
	for p in presets:
		if String(p.get("side", "")) == side:
			var slots: Array = p.get("slots", [])
			if not slots.is_empty() and int(slots[0].get("item_id", -1)) >= 0:
				out.append(int(slots[0]["item_id"]))
	return out


## Prüfung (Server und SPIELER-SETUP). Ergebnis "" = gültig, sonst Original-Hinweistext.
static func check(inv: Dictionary, allowed: Array, team: int, strength: float, heads: Array = []) -> String:
	for k in ["hands", "shoulder"]:
		var w := int(inv.get(k, -1))
		if w >= 0 and slot_of(w) != "hands":
			return "%s: %s" % [SAS.text(SAS.SLOT_TEXT[k], k).strip_edges(), SAS.item_label(w)]
	for k in ["uniform", "back", "head"]:
		var id := int(inv.get(k, -1))
		if id >= 0 and slot_of(id) != k:
			return "%s: %s" % [SAS.text(SAS.SLOT_TEXT[k], k).strip_edges(), SAS.item_label(id)]
	var need := {}
	for k in ["hands", "shoulder", "uniform", "back"]:
		var id := int(inv.get(k, -1))
		if id >= 0:
			need[id] = int(need.get(id, 0)) + 1
	for e in inv.get("items", []):
		need[int(e[0])] = int(need.get(int(e[0]), 0)) + int(e[1])
	var head := int(inv.get("head", -1))
	if allowed.is_empty():
		for id in need:
			if OrigInteractive.item_info(int(id)).is_empty() and SAS.item(int(id)).is_empty():
				return SAS.text(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände.")
	else:
		var st := storage(allowed, team)
		if head >= 0 and not heads.has(head):
			need[head] = int(need.get(head, 0)) + 1
		for id in need:
			if int(need[id]) > int(st.get(id, 0)):
				return SAS.text(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände.") + " (%s)" % SAS.item_label(int(id))
	if SAS.overloaded(inv, strength):
		return SAS.text(2023, "Ein Soldat ist überladen, bitte Gegenstand ablegen.")
	return ""


## Klassen-Vorlage (mp.json preset) als Inventar, an das Lager der Karte angepasst (Original-Regel 0x679B80)
static func from_preset(p: Dictionary, allowed: Array, team: int) -> Dictionary:
	var inv := SAS.new_inventory()
	if p.is_empty():
		return inv
	var slots: Array = p.get("slots", [])
	inv["head"] = int(slots[0]["item_id"]) if slots.size() > 0 else -1
	inv["hands"] = int(slots[1]["item_id"]) if slots.size() > 1 else -1
	inv["shoulder"] = int(slots[2]["item_id"]) if slots.size() > 2 else -1
	inv["uniform"] = int(slots[3]["item_id"]) if slots.size() > 3 else -1
	inv["back"] = int(slots[4]["item_id"]) if slots.size() > 4 else -1
	if allowed.is_empty():
		for it in (p.get("list_a", []) as Array) + (p.get("list_b", []) as Array):
			if int(it.get("item_id", -1)) >= 0:
				SAS.add_item(inv, int(it["item_id"]), int(it.get("count", 1)))
		return inv
	var uni := int(inv["uniform"])
	var st := storage(allowed, team)
	var ad := Net.adapt_preset(p, Net.storage_of(allowed, team), uni >= 0 and Net.item_side_flag(uni) == 1)
	inv["hands"] = int(ad["hands"])
	inv["shoulder"] = int(ad["shoulder"])
	# Uniform/Rucksack der Vorlage nur, wenn die Karte sie anbietet (sonst erste erlaubte Uniform der Seite)
	if uni >= 0 and int(st.get(uni, 0)) <= 0:
		inv["uniform"] = -1
		for id in st:
			if slot_of(int(id)) == "uniform" and int(st[id]) > 0:
				inv["uniform"] = int(id)
				break
	if int(inv["back"]) >= 0 and int(st.get(int(inv["back"]), 0)) <= 0:
		inv["back"] = -1
	var h := uniform_head(int(inv["uniform"]))
	if h >= 0:
		inv["head"] = h
	for it in ad["items"]:
		SAS.add_item(inv, int(it[0]), int(it[1]))
	return inv


## Gegenstand an den Soldaten (Platz oder Taschen/Rucksack); Ergebnis "" = ok, sonst Hinweis
static func give(inv: Dictionary, id: int, allowed: Array, team: int, strength: float, want := "") -> String:
	if remaining(inv, allowed, team, id) <= 0:
		return SAS.text(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände.")
	var slot := slot_of(id)
	if want == "items":
		slot = ""
	elif slot == "hands" and want == "shoulder":
		slot = "shoulder"
	elif slot == "hands" and want == "" and int(inv.get("hands", -1)) >= 0 and int(inv.get("shoulder", -1)) < 0:
		slot = "shoulder"
	if want in ["hands", "shoulder", "uniform", "back", "head"] and want != slot:
		return "%s → %s: nicht möglich." % [SAS.item_label(id), SAS.text(SAS.SLOT_TEXT[want], want).strip_edges()]
	var trial := inv.duplicate(true)
	if slot != "":
		trial[slot] = id
		if slot == "uniform":
			var h := uniform_head(id)
			if h >= 0:
				trial["head"] = h
	else:
		SAS.add_item(trial, id, 1)
	if SAS.overloaded(trial, strength):
		return SAS.text(2023, "Ein Soldat ist überladen, bitte Gegenstand ablegen.")
	for k in trial:
		inv[k] = trial[k]
	return ""


## Gegenstand ablegen (Platz oder ein Stück aus Taschen/Rucksack)
static func take(inv: Dictionary, slot_or_item: String) -> void:
	if slot_or_item in SAS.SLOTS:
		inv[slot_or_item] = -1
		# ohne Rucksack passt der Inhalt evtl. nicht mehr → Überzähliges ablegen
		while not SAS.fits(inv) and not (inv["items"] as Array).is_empty():     # B-014: Raum nur mit Rucksack
			var e: Array = (inv["items"] as Array).back()
			SAS.remove_item(inv, int(e[0]), int(e[1]))
	elif slot_or_item.is_valid_int():
		SAS.remove_item(inv, int(slot_or_item), 1)


## Inventar ↔ Vorlage (user_presets_orig.def-Datensatz, Taschen bis 12 Raumeinheiten, Rest Rucksack)
static func to_preset(inv: Dictionary, nm: String, flags: int, text_id: int) -> Dictionary:
	var p := {"name": nm.substr(0, 29), "slots": [-1, -1, -1, -1, -1], "a": [], "b": [], "flags": flags, "text_id": text_id}
	var order := ["head", "hands", "shoulder", "uniform", "back"]
	for s in order.size():
		p["slots"][s] = int(inv.get(order[s], -1))
	var used := 0.0
	for e in inv.get("items", []):
		var sp := SAS.space(int(e[0])) * int(e[1])
		if (p["a"] as Array).size() < 14 and (used + sp <= SAS.POCKET_SPACE + 0.001 or not SAS.is_backpack(int(inv.get("back", -1)))):
			p["a"].append([int(e[0]), int(e[1])])
			used += sp
		elif (p["b"] as Array).size() < 32:
			p["b"].append([int(e[0]), int(e[1])])
	return p
