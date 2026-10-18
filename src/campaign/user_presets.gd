extends RefCounted
## Eigene Ausrüstungsvorlagen wie im Original: <Profil>/user_presets_orig.def (re_notes_profiles §3).
## Format: u32 Version 3, u32 Anzahl, Anzahl × 440 Byte: char Name[32], i32 Plätze[5] (Kopf, Hände, Schulter,
## Uniform, Rucksack [P]), i32 n_a + 14 Paare (Gegenstand, Anzahl) = Taschen, i32 n_b + 32 Paare = Rucksackinhalt,
## i32 Flags (18 Achse, 34 Alliierte, 66 Deathmatch, 4 Einzelspieler), i32 Namens-Text-ID (6530–6547 „Leer 1…6“), i32 0.
## Die Originaldatei enthält 24 Vorlagen (je 6 Achse/Alliierte/Deathmatch/Einzelspieler); Einzelspieler = Block 4
## (Text-IDs „Leer 1…6“ 6530–6547 zyklisch, Zuordnung der Blöcke [P]).

const VERSION := 3
const RECORD := 440
const BLOCK_FLAGS := [18, 34, 66, 4]
const SP_BLOCK := 3
const SLOT_ORDER := ["head", "hands", "shoulder", "uniform", "back"]


static func path() -> String:
	return Game.profile_dir() + "/user_presets_orig.def" if Game.has_profile() else "user://user_presets_orig.def"


## Alle 24 Vorlagen (fehlt die Datei: leere Vorlagen wie im Original)
static func load_all() -> Array:
	var out: Array = []
	var f := FileAccess.open(path(), FileAccess.READ)
	if f and f.get_length() >= 8:
		var ver := f.get_32()
		var n := f.get_32()
		if ver == VERSION:
			for i in n:
				if f.get_position() + RECORD > f.get_length():
					break
				out.append(_read(f))
	if out.size() < 24:
		for i in range(out.size(), 24):
			out.append(empty(i))
	return out


static func empty(i: int) -> Dictionary:
	# Texte 6530–6547 = 3 × „Leer 1…6“ für 4 Blöcke: Zuordnung zyklisch [P]
	return {"name": "", "slots": [-1, -1, -1, -1, -1], "a": [], "b": [], "flags": BLOCK_FLAGS[i / 6], "text_id": 6530 + (i % 18)}


static func _read(f: FileAccess) -> Dictionary:
	var raw := f.get_buffer(32)
	var nm := raw.get_string_from_utf8()
	var slots: Array = []
	for k in 5:
		slots.append(_s32(f.get_32()))
	var na := _s32(f.get_32())
	var a: Array = []
	for k in 14:
		var it := _s32(f.get_32())
		var c := _s32(f.get_32())
		if k < na and it >= 0:
			a.append([it, c])
	var nb := _s32(f.get_32())
	var b: Array = []
	for k in 32:
		var it := _s32(f.get_32())
		var c := _s32(f.get_32())
		if k < nb and it >= 0:
			b.append([it, c])
	var flags := _s32(f.get_32())
	var tid := _s32(f.get_32())
	f.get_32()
	return {"name": nm, "slots": slots, "a": a, "b": b, "flags": flags, "text_id": tid}


static func _s32(v: int) -> int:
	return v - 0x100000000 if v >= 0x80000000 else v


static func save_all(list: Array) -> bool:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(VERSION)
	f.store_32(list.size())
	for p in list:
		var nm := String(p.get("name", "")).to_utf8_buffer()
		nm.resize(32)
		nm[31] = 0
		f.store_buffer(nm)
		for k in 5:
			f.store_32(int(p["slots"][k]) & 0xFFFFFFFF)
		var a: Array = p.get("a", [])
		f.store_32(mini(a.size(), 14))
		for k in 14:
			f.store_32((int(a[k][0]) if k < a.size() else -1) & 0xFFFFFFFF)
			f.store_32(int(a[k][1]) if k < a.size() else 0)
		var b: Array = p.get("b", [])
		f.store_32(mini(b.size(), 32))
		for k in 32:
			f.store_32((int(b[k][0]) if k < b.size() else -1) & 0xFFFFFFFF)
			f.store_32(int(b[k][1]) if k < b.size() else 0)
		f.store_32(int(p.get("flags", 4)))
		f.store_32(int(p.get("text_id", 6542)))
		f.store_32(0)
	return true


## Einzelspieler-Vorlagen (6 Stück)
static func sp_presets() -> Array:
	return load_all().slice(SP_BLOCK * 6, SP_BLOCK * 6 + 6)


static func is_empty(p: Dictionary) -> bool:
	for v in p.get("slots", []):
		if int(v) >= 0:
			return false
	return (p.get("a", []) as Array).is_empty() and (p.get("b", []) as Array).is_empty()


static func label(p: Dictionary) -> String:
	var nm := String(p.get("name", ""))
	var tid := int(p.get("text_id", 6530))
	return nm if nm != "" else SAS.text(tid, "Leer %d" % (posmod(tid - 6530, 6) + 1))


## Inventar (Game/SAS-Format) in Vorlage i (0–5) des Einzelspieler-Blocks speichern
static func store_sp(i: int, inv: Dictionary, nm: String) -> void:
	var all := load_all()
	var k := SP_BLOCK * 6 + i
	var p := empty(k)
	p["name"] = nm.substr(0, 31)
	for s in SLOT_ORDER.size():
		p["slots"][s] = int(inv.get(SLOT_ORDER[s], -1))
	var used := 0.0
	for e in inv.get("items", []):
		var sp := SAS.space(int(e[0])) * int(e[1])
		if (p["a"] as Array).size() < 14 and (used + sp <= SAS.POCKET_SPACE + 0.001 or int(inv.get("back", -1)) < 0):
			p["a"].append([int(e[0]), int(e[1])])
			used += sp
		elif (p["b"] as Array).size() < 32:
			p["b"].append([int(e[0]), int(e[1])])
	all[k] = p
	save_all(all)


## Vorlage als Inventar (SAS-Format): Taschen + Rucksack = gemeinsames Inventar
static func to_inventory(p: Dictionary) -> Dictionary:
	var inv := SAS.new_inventory()
	for s in SLOT_ORDER.size():
		inv[SLOT_ORDER[s]] = int(p["slots"][s])
	for e in (p.get("a", []) as Array) + (p.get("b", []) as Array):
		SAS.add_item(inv, int(e[0]), int(e[1]))
	return inv
