class_name WeaponDB
extends RefCounted
## Waffenregister.
##
## Herkunft der Werte (Details: docs/RE_FINDINGS.md, Abschnitt "item_shoot.tbl"):
##  [O] = aus Original-Tabelle TABLES\item_shoot.tbl übernommen
##        damage      = Feld 6 / 10   (Original "zotti": 1000 = volle Gesundheit,
##                                     hier Gesundheit 100)
##        muzzle_velocity = Feld 17   (m/s, deckt sich mit realen Werten)
##        reload_time = Feld 16       (s)
##        bolt_time / Einzelfeuer-Intervall = Feld 20 (s), nur Nicht-Automaten
##  [D] = eigene, historisch angelehnte Designwerte (Kadenz, Magazin,
##        Streuung, Rückstoß, Geräuschradius ...)
## Die Waffenauswahl folgt den Inventar-Icons des Originals (Maps/ii_*.565).

static var _cache: Dictionary = {}


static func get_weapon(id: StringName) -> WeaponData:
	if _cache.is_empty():
		_build()
	if not _cache.has(id) and String(id).begins_with("o_"):
		from_orig(int(String(id).substr(2)))     # aus der Originaltabelle erzeugte Waffe (z. B. Spielstand)
	assert(_cache.has(id), "Unbekannte Waffe: %s" % id)
	return _cache.get(id)


## Originalgegenstand (items.dat-Nummer) -> Waffe. Bekannte Waffen nutzen die Einträge oben, alle übrigen
## Handwaffen werden aus der Originaltabelle (orig_cache/items.json, item_shoot.tbl) erzeugt: Schaden/10,
## Feuerintervall, Nachladezeit, Mündungsgeschwindigkeit, Magazin, Gewicht [O]; Streuung/Rückstoß [D].
const ORIG_IDS := {0: &"p08", 2: &"colt", 4: &"kar98k", 6: &"enfield", 10: &"garand", 18: &"mp40", 20: &"thompson",
	21: &"sten", 26: &"stg44", 29: &"bren", 61: &"m24", 62: &"no36", 60: &"no69", 63: &"no36"}
const ORIG_PISTOLS := [0, 1, 2, 3, 5, 260, 261]
## Granaten/Handwaffen, die ein Soldat tragen kann (Bordwaffen, Geschütze, Flak u. a. nicht)
const ORIG_HANDHELD_MAX_KG := 15.0
static var _orig_table: Dictionary = {}


static func from_orig(item: int) -> WeaponData:
	if _cache.is_empty():
		_build()
	if ORIG_IDS.has(item):
		return _cache.get(ORIG_IDS[item])
	var gid := StringName("o_%d" % item)
	if _cache.has(gid):
		return _cache[gid]
	if _orig_table.is_empty():
		var f := FileAccess.open(OrigLevel.cache_root() + "/items.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if typeof(d) == TYPE_DICTIONARY:
			for wp in d.get("weapons", []):
				_orig_table[int(wp["id"])] = wp
	var o: Dictionary = _orig_table.get(item, {})
	if o.is_empty() or float(o.get("weight_kg", 0.0)) > ORIG_HANDHELD_MAX_KG or int(o.get("magazine", 0)) <= 0:
		return null
	var fi := float(o.get("fire_interval_ms", 200.0)) / 1000.0
	var pistol := ORIG_PISTOLS.has(item)
	var act := WeaponData.Action.AUTO if fi <= 0.11 else (WeaponData.Action.BOLT if fi >= 1.0 else WeaponData.Action.SEMI)
	var heavy := float(o.get("weight_kg", 4.0)) > 8.0
	return _make({id = gid, display_name = String(o.get("name", gid)), slot = WeaponData.Slot.SIDEARM if pistol else WeaponData.Slot.PRIMARY,
		action = act, can_toggle_auto = act == WeaponData.Action.AUTO, magazine_size = int(o["magazine"]),
		start_magazines = 4, rpm = 60.0 / maxf(fi, 0.05) if act != WeaponData.Action.AUTO else float(o.get("rate_rpm", 600)),
		bolt_time = fi if act == WeaponData.Action.BOLT else 0.0, reload_time = float(o.get("reload_ms", 2400.0)) / 1000.0,
		muzzle_velocity = float(o.get("muzzle_velocity", 400.0)), damage = float(o.get("damage", 300.0)) / 10.0,
		falloff_start = 20.0 if pistol else (150.0 if act != WeaponData.Action.AUTO else 60.0),
		spread_hip = 2.8 if pistol else (4.5 if heavy else 3.0), spread_aim = 0.7 if pistol else (0.08 if act == WeaponData.Action.BOLT else 0.5),
		recoil_pitch = 2.0 if pistol else (1.3 if act == WeaponData.Action.AUTO else 3.2), recoil_yaw = 0.6,
		spread_per_shot = 0.3, aim_fov = 60.0 if pistol else (30.0 if String(o.get("name", "")).contains("optic") else 45.0),
		noise_radius = 15.0 if item in [7, 22, 260] else (60.0 if pistol else 130.0), weight = float(o.get("weight_kg", 4.0)),
		model_length = 0.22 if pistol else 1.0})


static func all_ids() -> Array:
	if _cache.is_empty():
		_build()
	return _cache.keys()


static func _make(d: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	for k in d:
		w.set(k, d[k])
	if not d.has("reload_empty_time"):
		w.reload_empty_time = w.reload_time   # Original kennt nur eine Nachladezeit
	_cache[w.id] = w
	return w


static func _build() -> void:
	var P := WeaponData.Slot.PRIMARY
	var S := WeaponData.Slot.SIDEARM
	var G := WeaponData.Slot.GRENADE
	# --- Alliierte -------------------------------------------------------
	# Original-Datensatz "stengun": dmg 300, v0 366, reload 2.4
	_make({id = &"sten", display_name = "Sten Mk II", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = "9×19 mm", magazine_size = 32, start_magazines = 5,
		rpm = 540.0, reload_time = 2.4, muzzle_velocity = 366.0, damage = 30.0,
		falloff_start = 40.0, spread_hip = 3.2, spread_aim = 0.9, recoil_pitch = 0.9, recoil_yaw = 0.5,
		spread_per_shot = 0.35, aim_fov = 55.0, noise_radius = 80.0, weight = 3.2, model_length = 0.76})
	# "thomson": dmg 380, v0 274, reload 2.4
	_make({id = &"thompson", display_name = "Thompson M1A1", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = ".45 ACP", magazine_size = 30, start_magazines = 4,
		rpm = 700.0, reload_time = 2.4, muzzle_velocity = 274.0, damage = 38.0,
		falloff_start = 35.0, spread_hip = 3.0, spread_aim = 0.8, recoil_pitch = 1.1, recoil_yaw = 0.6,
		spread_per_shot = 0.4, aim_fov = 55.0, noise_radius = 90.0, weight = 4.8, model_length = 0.81})
	# "Enf Mk4": dmg 419, v0 732, reload 3.2, Repetierzeit 1.4
	_make({id = &"enfield", display_name = "Lee-Enfield No. 4", slot = P, action = WeaponData.Action.BOLT,
		caliber = ".303 British", magazine_size = 10, start_magazines = 5, bolt_time = 1.4,
		reload_time = 3.2, muzzle_velocity = 732.0, damage = 41.9,
		falloff_start = 150.0, spread_hip = 2.5, spread_aim = 0.08, recoil_pitch = 3.5, recoil_yaw = 0.6,
		spread_per_shot = 0.0, aim_fov = 40.0, noise_radius = 140.0, weight = 4.1, model_length = 1.13})
	# "garand": dmg 390, v0 853, reload 2.0, Intervall 0.2 s (= 300/min)
	_make({id = &"garand", display_name = "M1 Garand", slot = P, action = WeaponData.Action.SEMI,
		caliber = ".30-06", magazine_size = 8, start_magazines = 6, rpm = 300.0,
		reload_time = 2.0, muzzle_velocity = 853.0, damage = 39.0,
		falloff_start = 150.0, spread_hip = 2.5, spread_aim = 0.1, recoil_pitch = 3.0, recoil_yaw = 0.7,
		spread_per_shot = 0.25, aim_fov = 42.0, noise_radius = 140.0, weight = 4.3, model_length = 1.1})
	# "BrenGun": dmg 550, v0 732, reload 2.4
	_make({id = &"bren", display_name = "Bren Mk II", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = ".303 British", magazine_size = 30, start_magazines = 4,
		rpm = 520.0, reload_time = 2.4, muzzle_velocity = 732.0, damage = 55.0,
		falloff_start = 200.0, spread_hip = 4.5, spread_aim = 0.35, recoil_pitch = 1.4, recoil_yaw = 0.5,
		spread_per_shot = 0.25, aim_fov = 45.0, noise_radius = 160.0, weight = 10.1, model_length = 1.15,
		color = Color(0.22, 0.22, 0.2)})
	# "colt": dmg 280, v0 251, reload 2.0
	_make({id = &"colt", display_name = "Colt M1911", slot = S, action = WeaponData.Action.SEMI,
		caliber = ".45 ACP", magazine_size = 7, start_magazines = 4, rpm = 300.0,
		reload_time = 2.0, muzzle_velocity = 251.0, damage = 28.0,
		falloff_start = 20.0, spread_hip = 2.8, spread_aim = 0.7, recoil_pitch = 2.4, recoil_yaw = 0.8,
		spread_per_shot = 0.3, aim_fov = 60.0, noise_radius = 60.0, weight = 1.1, model_length = 0.22,
		color = Color(0.15, 0.15, 0.15)})
	# Granate: Designwerte (Granaten liegen nicht im gelesenen Tabellenteil)
	_make({id = &"no36", display_name = "Mills-Granate No. 36", slot = G, action = WeaponData.Action.THROWN,
		magazine_size = 1, start_magazines = 2, rpm = 40.0, reload_time = 0.8,
		damage = 220.0, fuse_time = 4.0, blast_radius = 8.0, throw_speed = 17.0,
		noise_radius = 180.0, weight = 0.77, model_length = 0.1, color = Color(0.3, 0.33, 0.2)})
	# No. 69 (Original „No.69 Gran GB U“, 0,37 kg): Aufschlaggranate, kleinerer Radius [D]
	_make({id = &"no69", display_name = "Granate No. 69", slot = G, action = WeaponData.Action.THROWN,
		magazine_size = 1, start_magazines = 2, rpm = 40.0, reload_time = 0.8,
		damage = 160.0, fuse_time = 2.5, blast_radius = 6.0, throw_speed = 19.0,
		noise_radius = 180.0, weight = 0.37, model_length = 0.1, color = Color(0.25, 0.25, 0.22)})
	# --- Achsenmächte ----------------------------------------------------
	# "98K": dmg 488, v0 747, reload 3.8, Repetierzeit 1.4
	_make({id = &"kar98k", display_name = "Karabiner 98k", faction = "axis", slot = P,
		action = WeaponData.Action.BOLT, caliber = "7,92×57 mm", magazine_size = 5, start_magazines = 6,
		bolt_time = 1.4, reload_time = 3.8, muzzle_velocity = 747.0,
		damage = 48.8, falloff_start = 150.0, spread_hip = 2.5, spread_aim = 0.08, recoil_pitch = 3.6,
		recoil_yaw = 0.6, aim_fov = 40.0, noise_radius = 140.0, weight = 3.9, model_length = 1.11})
	# "MP 40": dmg 340, v0 366, reload 2.4
	_make({id = &"mp40", display_name = "MP 40", faction = "axis", slot = P, action = WeaponData.Action.AUTO,
		caliber = "9×19 mm", magazine_size = 32, start_magazines = 5, rpm = 500.0,
		reload_time = 2.4, muzzle_velocity = 366.0, damage = 34.0,
		falloff_start = 45.0, spread_hip = 3.0, spread_aim = 0.8, recoil_pitch = 0.8, recoil_yaw = 0.4,
		spread_per_shot = 0.3, aim_fov = 55.0, noise_radius = 80.0, weight = 4.0, model_length = 0.83,
		color = Color(0.12, 0.12, 0.12)})
	# "MP 44": dmg 333, v0 655, reload 2.4
	_make({id = &"stg44", display_name = "StG 44", faction = "axis", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = "7,92×33 mm Kurz", magazine_size = 30, start_magazines = 4,
		rpm = 550.0, reload_time = 2.4, muzzle_velocity = 655.0, damage = 33.3,
		falloff_start = 100.0, spread_hip = 3.5, spread_aim = 0.4, recoil_pitch = 1.3, recoil_yaw = 0.6,
		spread_per_shot = 0.35, aim_fov = 48.0, noise_radius = 120.0, weight = 4.6, model_length = 0.94,
		color = Color(0.16, 0.15, 0.13)})
	# Stielhandgranate 24: Designwerte (größere Wurfweite durch Stiel, kleinerer Splitterradius)
	_make({id = &"m24", display_name = "Stielhandgranate 24", faction = "axis", slot = G,
		action = WeaponData.Action.THROWN, magazine_size = 1, start_magazines = 2, rpm = 40.0,
		reload_time = 0.8, damage = 200.0, fuse_time = 4.5, blast_radius = 7.0, throw_speed = 19.0,
		noise_radius = 180.0, weight = 0.6, model_length = 0.35, color = Color(0.25, 0.27, 0.22)})
	# "parabel": dmg 300, v0 351, reload 1.7
	_make({id = &"p08", display_name = "Pistole 08", faction = "axis", slot = S, action = WeaponData.Action.SEMI,
		caliber = "9×19 mm", magazine_size = 8, start_magazines = 3, rpm = 300.0,
		reload_time = 1.7, muzzle_velocity = 351.0, damage = 30.0,
		falloff_start = 20.0, spread_hip = 2.8, spread_aim = 0.7, recoil_pitch = 2.0, recoil_yaw = 0.7,
		aim_fov = 60.0, noise_radius = 60.0, weight = 0.9, model_length = 0.22, color = Color(0.12, 0.12, 0.12)})
