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
## Stand 16.10.2026: Schaden, Abfall und Explosionen aus TABLES\items.sav v1.12 (orig_cache/items.json) und dem
## Schadensmodell von hd2.exe (docs/re_notes_weapons.md §10) – in Einzel- und Mehrspieler identisch.

static var _cache: Dictionary = {}


# --- Original-Schadensmodell (hd2.exe, docs/re_notes_weapons.md §10) -------------------------------------
## Trefferzonen Human::Damage 0x5A1C90 (Sprungtabelle 0x5A26D8, Zonen-Texte 8800–8806): 0 Körper ×1,0, 1 Kopf ×5,0,
## 2–5 linke/rechte Hand ×0,2, 6–9 linkes/rechtes Bein ×0,33 [B]. Hitbox-Namen des Nachbaus: torso/head/arm/leg.
const ZONE_FACTOR := {&"torso": 1.0, &"head": 5.0, &"arm": 0.2, &"leg": 0.33}
## Zone 11 = Helm (Strahltest gegen das Helmmodell vor dem Kopf, 0x455670): Geschoss verliert zuerst die Panzerung
## des Helmmaterials (hdmaterials.def Zeile 12 „Plech 2-6mm“ +0x28 = 150 zotti → 15), dann zu 30 % (RandFloat <
## 0,3 @0x80F5CC) Kopftreffer ×5,0, sonst Abpraller ×0,2 (0x5A20CA) [B]
const HELMET_ARMOR := 15.0
const HELMET_PIERCE_CHANCE := 0.3
const HELMET_PIERCE_FACTOR := 5.0
const HELMET_GLANCE_FACTOR := 0.2
## Kopf-/Helmgegenstände: items.sav Ausrüstung mit Kategorie 16 (Kopf), z. B. 27/32 G HELM, 64/69 US helm
const HEAD_ITEM_CATEGORY := 16


## Geschossschaden nach Flugstrecke (hd2.exe 0x44B3B0): bis falloff_start voller Schaden, danach linear
## −falloff_per_m je Meter, nicht unter 0 [B]. Eigene Waffen ohne Originalwert: unverändert.
static func bullet_damage(data: WeaponData, dist: float) -> float:
	if data == null:
		return 0.0
	if dist <= data.falloff_start or data.falloff_per_m <= 0.0:
		return data.damage
	return maxf(data.damage - (dist - data.falloff_start) * data.falloff_per_m, 0.0)


## Schaden einer Trefferzone (Original 0x5A1C90); helmet = Treffer auf den Helm, roll = Zufallswert 0..1 (Tests)
static func zone_damage(base: float, zone: StringName, helmet := false, roll := -1.0) -> float:
	if helmet:
		var rest := base - HELMET_ARMOR
		if rest <= 0.0:
			return 0.0
		var r: float = randf() if roll < 0.0 else roll
		return rest * (HELMET_PIERCE_FACTOR if r < HELMET_PIERCE_CHANCE else HELMET_GLANCE_FACTOR)
	return base * float(ZONE_FACTOR.get(zone, 1.0))


## --- Einzelspieler (Stand 23.10.2026, docs/re_notes_weapons.md §10b) -----------------------------------------------
## hd2.exe Human::Damage 0x5A1C90 wertet den Schwierigkeitsgrad nur im Einzelspieler (Spielmodus 0x982100 & 7 == 7) bzw.
## Koop (0x6B66B0: Spielart 3) und nur für Schadensart 1 (Geschoss, Aufruf aus 0x44B910) aus; Stufe = 0x6B6700 (SP:
## Profil-Schwierigkeit, MP fest 3). Opfer Seite 1 (Spielertrupp) oder 4 (verbündeter NPC): Schaden × 0,2 / 0,4 / 1,0 /
## 1,2 für Stufe 1 / 2 / 3 / 4 (Konstanten 0x80F540 / 0x80F554 / – / 0x80FAD0). Übrige Opfer: nur Stufe 1 und Schütze
## Seite 1 → × 1,2 (0x80FAD0) [B]. Danach Zonenfaktor, Abzug ⌊Schaden⌋ in zotti (__ftol 0x7E5E00). Helm (Zone 11):
## Durchschlag (RandFloat < 0,3) im SP gegen Seite 1 auf Stufe 1 × 1 statt × 5 (0x5A20F6–0x5A210E) [B].
## Im Mehrspieler (Net.is_online) bleibt zone_damage unverändert.
const SP_VICTIM_FACTOR := {1: 0.2, 2: 0.4, 3: 1.0, 4: 1.2}
const SP_EASY_SHOOTER_FACTOR := 1.2


## Seite eines Menschen wie actors.bin (+0x19C): 1 Spielertrupp, 2 Feind, 3 neutral, 4 verbündeter NPC
static func orig_side(s: Node) -> int:
	if s == null or not is_instance_valid(s):
		return 0
	var p = s.get_meta("orig_params", {}) if s.has_meta("orig_params") else {}
	if p is Dictionary and (p as Dictionary).has("side"):
		return int(p["side"])
	var t = s.get("team")
	if t == null:
		return 0
	if int(t) == Soldier.TEAM_ALLIED:
		return 1
	if int(t) == Soldier.TEAM_AXIS:
		return 2
	return 3


## Schwierigkeitsfaktor eines Geschosstreffers im Einzelspieler (0x5A1C90, s. o.)
static func sp_bullet_factor(victim: Node, attacker: Node, difficulty: int) -> float:
	var vs := orig_side(victim)
	if vs == 1 or vs == 4:
		return float(SP_VICTIM_FACTOR.get(difficulty, 1.0))
	if difficulty == 1 and orig_side(attacker) == 1:
		return SP_EASY_SHOOTER_FACTOR
	return 1.0


## Schaden eines Geschosstreffers nach Zone (gemeinsame Quelle für SP und MP). MP: zone_damage unverändert.
## SP: Schwierigkeitsfaktor vor dem Zonenfaktor, Helmregel Stufe 1, ganzzahlige zotti (Gesundheit 1 = 10 zotti).
static func bullet_hit_damage(base: float, zone: StringName, helmet: bool, victim: Node, attacker: Node,
		single_player: bool, difficulty: int, roll := -1.0) -> float:
	if not single_player:
		return zone_damage(base, zone, helmet, roll)
	var k := sp_bullet_factor(victim, attacker, difficulty)
	var b := base * k
	var d := 0.0
	if helmet:
		# Panzerung des Helmmaterials zieht schon das Geschoss ab (0x44B910), der Faktor wirkt danach in 0x5A1C90
		var rest := (base - HELMET_ARMOR) * k
		if rest <= 0.0:
			return 0.0
		var r: float = randf() if roll < 0.0 else roll
		var pierce := 1.0 if (difficulty == 1 and orig_side(victim) == 1) else HELMET_PIERCE_FACTOR
		d = rest * (pierce if r < HELMET_PIERCE_CHANCE else HELMET_GLANCE_FACTOR)
	else:
		d = b * float(ZONE_FACTOR.get(zone, 1.0))
	return floorf(d * 10.0 + 1e-4) / 10.0


## Explosion (hd2.exe 0x6DE780 → 0x6DDD40): Schaden = |(1 − Abstand/Radius) · Stärke| minus Materialpanzerung des
## Ziels (Mensch: Material 66 „Fleisch“ = 0), Schadensart 2/4 in Zone 0 (Körper) [B]
static func explosion_damage(strength: float, radius: float, dist: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	return absf((1.0 - dist / radius) * strength)


## Eigene Varianten → Originalgegenstand für die Kartenfreigabe (ALLOWEDITEMS): die deutschen Schalldämpferwaffen
## gelten als K98k bzw. MP 40 (Vorgabe Auftraggeber)
const VARIANT_BASE := {&"kar98k_sd": 4, &"mp40_sd": 18}


## Originalgegenstand einer Waffe (Original-Nummer, eigene ID oder „o_<n>“), −1 = kein Originalgegenstand
static func orig_item_of(w) -> int:
	if w is int:
		return w
	var id := StringName(str(w))
	if VARIANT_BASE.has(id):
		return int(VARIANT_BASE[id])
	if String(id).begins_with("o_"):
		return int(String(id).substr(2))
	var best := -1
	for k in ORIG_IDS:
		if ORIG_IDS[k] == id and (best < 0 or int(k) < best):
			best = int(k)
	return best


## Trägt der Soldat einen Helm? Originalinventar (Kopf-Gegenstand) bzw. Helmform der Figur
static func wears_helmet(s: Node) -> bool:
	if s == null:
		return false
	for it in s.get_meta("orig_items", []):
		var eq = OrigInteractive.item_info(int(it)).get("equip_raw", [])
		if eq is Array and (eq as Array).size() > 1 and int(eq[1]) == HEAD_ITEM_CATEGORY:
			return true
	# Original-Menschen (actors.bin) und SAS-Kader im Einzelspieler: nur der Kopfgegenstand zählt (0x455670 prüft das
	# Modell des Kopf-Inventarplatzes +0x74); ohne Kopfgegenstand kein Helm – die Platzhalter-Helmform „stahlhelm“
	# von spawn_enemy gab z. B. ARCTIC1 „metar“ (nur Uniform + P08) fälschlich einen Helm (Kopftreffer ×0,2 statt ×5)
	if s.has_meta("orig_params") or s.has_meta("sas"):
		return false
	var hs: String = String(s.get("helmet_style")) if "helmet_style" in s else ""
	return hs != "" and hs != "cap" and hs != "none"


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
	21: &"sten", 26: &"stg44", 29: &"bren", 61: &"m24", 62: &"no36", 60: &"no69", 63: &"no36",
	38: &"panzerfaust", 39: &"bazooka", 264: &"panzerschreck", 56: &"knife", 57: &"knife"}
## Munition der Raketenwerfer (items.sav; nicht in item_shoot.tbl): Bazooka 206, Panzerschreck 205.
## Panzerfaust: im Original Einwegwaffe; Vorgabe Auftraggeber: nachladbar mit eigener Raketen-Munition
## (Gegenstand PANZERFAUST_AMMO, kein Originalgegenstand – Nummer außerhalb der items.sav-Tabelle).
const PANZERFAUST_AMMO := 900
const LAUNCHER_AMMO := {39: 206, 264: 205, 38: PANZERFAUST_AMMO}
## Eigene Gegenstände für Inventar/Lager/Waffenliste (SAS): Werte [D], Symbol/Modell der Panzerfaust
const EXTRA_ITEMS := {PANZERFAUST_AMMO: {"item": PANZERFAUST_AMMO, "id": PANZERFAUST_AMMO, "name": "Panzerfaust-Rakete",
	"kind": "ammo", "weight_kg": 3.0, "size_class": 2, "space_units": 4, "icon": "wi_ge-panzfau60", "model": "w_panzer",
	"text_id": -1, "team_flag": 1, "u70": 9, "behaviours": [], "rounds": 1.0}}
const ORIG_PISTOLS := [0, 1, 2, 3, 5, 260, 261]
## Granaten/Handwaffen, die ein Soldat tragen kann (Bordwaffen, Geschütze, Flak u. a. nicht)
const ORIG_HANDHELD_MAX_KG := 15.0
static var _orig_table: Dictionary = {}


static func from_orig(item: int, mounted := false) -> WeaponData:
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
	if o.is_empty() or (float(o.get("weight_kg", 0.0)) > ORIG_HANDHELD_MAX_KG and not mounted) or int(o.get("magazine", 0)) <= 0:
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
		# items.sav Feuerwaffe +0x34 Abfallbeginn (m), +0x38 Abfall je m (zotti) [B 0x44B3B0]
		falloff_start = float(o.get("dist_param", 50.0)), falloff_per_m = float(o.get("recoil_spread", 0.0)) / 10.0,
		spread_hip = 2.8 if pistol else (4.5 if heavy else 3.0), spread_aim = 0.7 if pistol else (0.08 if act == WeaponData.Action.BOLT else 0.5),
		recoil_pitch = 2.0 if pistol else (1.3 if act == WeaponData.Action.AUTO else 3.2), recoil_yaw = 0.6,
		spread_per_shot = 0.3, aim_fov = 60.0 if pistol else (30.0 if String(o.get("name", "")).contains("optic") else 45.0),
		noise_radius = 15.0 if item in [7, 22, 260] else (60.0 if pistol else 130.0), weight = float(o.get("weight_kg", 4.0)),
		model_length = 0.22 if pistol else 1.0,
		sound = {7: &"silenced_rifle", 22: &"silenced_smg", 260: &"silenced_smg"}.get(item, &"")})


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
	# Werte [O] items.sav v1.12 (Schaden zotti/10, Abfall ab m, Abfall je m /10), Kurzname in Anführungszeichen.
	# "stengun" (21): dmg 300, Abfall ab 35 m mit 5,7/m, v0 366, reload 2.4
	_make({id = &"sten", display_name = "Sten Mk II", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = "9×19 mm", magazine_size = 32, start_magazines = 5,
		rpm = 600.0, reload_time = 2.4, muzzle_velocity = 366.0, damage = 30.0,
		falloff_start = 35.0, falloff_per_m = 0.57, spread_hip = 3.2, spread_aim = 0.9, recoil_pitch = 0.9, recoil_yaw = 0.5,
		spread_per_shot = 0.35, aim_fov = 55.0, noise_radius = 80.0, weight = 3.462, model_length = 0.76})
	# "thomson" (20): dmg 380, Abfall ab 25 m mit 6,6/m, v0 274, reload 2.4; Magazin 20 [O] (items.sav: Munition 189 „AMMO Thompson“ = 20 Patronen,
	# einzige Thompson-Munition der Tabelle – kein 30er-Magazin/Trommel im Original)
	_make({id = &"thompson", display_name = "Thompson M1A1", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = ".45 ACP", magazine_size = 20, start_magazines = 5,
		rpm = 600.0, reload_time = 2.4, muzzle_velocity = 274.0, damage = 38.0,
		falloff_start = 25.0, falloff_per_m = 0.66, spread_hip = 3.0, spread_aim = 0.8, recoil_pitch = 1.1, recoil_yaw = 0.6,
		spread_per_shot = 0.4, aim_fov = 55.0, noise_radius = 90.0, weight = 4.767, model_length = 0.81})
	# "Enf Mk4" (6): dmg 419, Abfall ab 70 m mit 1,8/m, v0 732, reload 3.2, Repetierzeit 1.4
	_make({id = &"enfield", display_name = "Lee-Enfield No. 4", slot = P, action = WeaponData.Action.BOLT,
		caliber = ".303 British", magazine_size = 10, start_magazines = 5, bolt_time = 1.4,
		reload_time = 3.2, muzzle_velocity = 732.0, damage = 41.9,
		falloff_start = 70.0, falloff_per_m = 0.18, spread_hip = 2.5, spread_aim = 0.08, recoil_pitch = 3.5, recoil_yaw = 0.6,
		spread_per_shot = 0.0, aim_fov = 40.0, noise_radius = 140.0, weight = 4.114, model_length = 1.13})
	# "garand" (10): dmg 390, Abfall ab 85 m mit 1,6/m, v0 853, reload 2.0, Intervall 0.2 s (= 300/min)
	_make({id = &"garand", display_name = "M1 Garand", slot = P, action = WeaponData.Action.SEMI,
		caliber = ".30-06", magazine_size = 8, start_magazines = 6, rpm = 300.0,
		reload_time = 2.0, muzzle_velocity = 853.0, damage = 39.0,
		falloff_start = 85.0, falloff_per_m = 0.16, spread_hip = 2.5, spread_aim = 0.1, recoil_pitch = 3.0, recoil_yaw = 0.7,
		spread_per_shot = 0.25, aim_fov = 42.0, noise_radius = 140.0, weight = 4.313, model_length = 1.1})
	# "BrenGun" (29): dmg 550, Abfall ab 75 m mit 2,0/m, v0 732, reload 2.4
	_make({id = &"bren", display_name = "Bren Mk II", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = ".303 British", magazine_size = 30, start_magazines = 4,
		rpm = 600.0, reload_time = 2.4, muzzle_velocity = 732.0, damage = 55.0,
		falloff_start = 75.0, falloff_per_m = 0.2, spread_hip = 4.5, spread_aim = 0.35, recoil_pitch = 1.4, recoil_yaw = 0.5,
		spread_per_shot = 0.25, aim_fov = 45.0, noise_radius = 160.0, weight = 10.13, model_length = 1.15,
		color = Color(0.22, 0.22, 0.2)})
	# "colt" (2): dmg 280, Abfall ab 15 m mit 12/m, v0 251, reload 2.0
	_make({id = &"colt", display_name = "Colt M1911", slot = S, action = WeaponData.Action.SEMI,
		caliber = ".45 ACP", magazine_size = 7, start_magazines = 4, rpm = 300.0,
		reload_time = 2.0, muzzle_velocity = 251.0, damage = 28.0,
		falloff_start = 15.0, falloff_per_m = 1.2, spread_hip = 2.8, spread_aim = 0.7, recoil_pitch = 2.4, recoil_yaw = 0.8,
		spread_per_shot = 0.3, aim_fov = 60.0, noise_radius = 60.0, weight = 1.106, model_length = 0.22,
		color = Color(0.15, 0.15, 0.15)})
	# Granaten/Werfer [O]: items.sav Werfer-Block +0x54 Explosionsstärke (zotti/10), +0x58 Radius (m) – No.36 1999/10 m,
	# No.69 1500/5 m, Stielhandgranate 39 1999/10 m, Panzerfaust 2900/6 m, Bazooka/Panzerschreck 2400/4,5 m [B Daten,
	# Zuordnung über hd2.exe 0x449290 → 0x451990 → 0x6DF170]; Schaden linear (1 − d/r) · Stärke (0x6DE780). Rest [D].
	_make({id = &"no36", display_name = "Mills-Granate No. 36", slot = G, action = WeaponData.Action.THROWN,
		magazine_size = 1, start_magazines = 2, rpm = 40.0, reload_time = 0.8,
		damage = 199.9, fuse_time = 4.0, blast_radius = 10.0, throw_speed = 18.0,
		noise_radius = 180.0, weight = 0.77, model_length = 0.1, color = Color(0.3, 0.33, 0.2)})
	# No. 69 (Original „No.69 Gran GB U“, 0,37 kg): Aufschlaggranate (Zündzeit [D])
	_make({id = &"no69", display_name = "Granate No. 69", slot = G, action = WeaponData.Action.THROWN,
		magazine_size = 1, start_magazines = 2, rpm = 40.0, reload_time = 0.8,
		damage = 150.0, fuse_time = 2.5, blast_radius = 5.0, throw_speed = 18.0,
		noise_radius = 180.0, weight = 0.37, model_length = 0.1, color = Color(0.25, 0.25, 0.22)})
	# Raketenwerfer (Stärke/Radius/v0 [O], übrige Werte [D], Gewichte aus items.sav): Aufschlagzünder (Grenade.impact).
	# Panzerfaust: im Original Einwegwaffe; Vorgabe Auftraggeber: mit Raketen-Munition (PANZERFAUST_AMMO)
	# nachladbar; improvisierte Nachladeanimation aus der Bazooka (3. Person !bazREL*, 1. Person #FPVBazReload
	# auf dem Panzerfaust-FPV-Modell), Nachladezeit 4,8 s = Länge dieser Clips [D]. Übung: 1 geladen + 2 Raketen.
	var L := WeaponData.Slot.LAUNCHER
	_make({id = &"panzerfaust", display_name = "Panzerfaust 60", faction = "axis", slot = L, action = WeaponData.Action.ROCKET,
		magazine_size = 1, start_magazines = 3, rpm = 60.0, reload_time = 4.8, muzzle_velocity = 45.0, damage = 290.0,
		blast_radius = 6.0, spread_hip = 2.0, spread_aim = 0.6, recoil_pitch = 4.0, aim_fov = 45.0,
		noise_radius = 150.0, weight = 6.8, model_length = 1.0, color = Color(0.3, 0.32, 0.22)})
	_make({id = &"bazooka", display_name = "M1 Bazooka", slot = L, action = WeaponData.Action.ROCKET,
		magazine_size = 1, start_magazines = 3, rpm = 60.0, reload_time = 5.0, muzzle_velocity = 91.0, damage = 240.0,
		blast_radius = 4.5, spread_hip = 2.0, spread_aim = 0.5, recoil_pitch = 3.0, aim_fov = 42.0,
		noise_radius = 150.0, weight = 6.0, model_length = 1.4, color = Color(0.28, 0.3, 0.2)})
	_make({id = &"panzerschreck", display_name = "Panzerschreck", faction = "axis", slot = L, action = WeaponData.Action.ROCKET,
		magazine_size = 1, start_magazines = 3, rpm = 60.0, reload_time = 5.0, muzzle_velocity = 105.0, damage = 240.0,
		blast_radius = 4.5, spread_hip = 2.0, spread_aim = 0.45, recoil_pitch = 3.0, aim_fov = 40.0,
		noise_radius = 160.0, weight = 8.6, model_length = 1.6, color = Color(0.25, 0.27, 0.2)})
	# Kampfmesser (Original knife GB/GER): lautlos, Nahkampf bis 1,6 m [D]
	_make({id = &"knife", display_name = "Kampfmesser", slot = WeaponData.Slot.MELEE, action = WeaponData.Action.MELEE,
		magazine_size = 1, start_magazines = 1, rpm = 80.0, reload_time = 0.1, damage = 90.0,
		noise_radius = 3.0, weight = 0.42, model_length = 0.25, color = Color(0.5, 0.5, 0.5)})
	# 2-cm-Flak 38 (Stellungen „la_flak“/„la_flake“): nicht in item_shoot.tbl gelesen → Designwerte [D]
	_make({id = &"flak38", display_name = "2-cm-Flak 38", faction = "axis", slot = P, action = WeaponData.Action.AUTO,
		caliber = "20 mm", magazine_size = 20, start_magazines = 6, rpm = 450.0, reload_time = 3.0,
		muzzle_velocity = 900.0, damage = 120.0, falloff_start = 400.0, spread_hip = 1.2, spread_aim = 0.4,
		recoil_pitch = 0.6, recoil_yaw = 0.3, spread_per_shot = 0.1, aim_fov = 40.0, noise_radius = 300.0,
		weight = 420.0, model_length = 2.0})
	# --- Achsenmächte ----------------------------------------------------
	# "98K" (4): dmg 488, Abfall ab 75 m mit 1,5/m, v0 747, reload 3.8, Repetierzeit 1.4
	_make({id = &"kar98k", display_name = "Karabiner 98k", faction = "axis", slot = P,
		action = WeaponData.Action.BOLT, caliber = "7,92×57 mm", magazine_size = 5, start_magazines = 6,
		bolt_time = 1.4, reload_time = 3.8, muzzle_velocity = 747.0,
		damage = 48.8, falloff_start = 75.0, falloff_per_m = 0.15, spread_hip = 2.5, spread_aim = 0.08, recoil_pitch = 3.6,
		recoil_yaw = 0.6, aim_fov = 40.0, noise_radius = 140.0, weight = 3.887, model_length = 1.11})
	# "MP 40" (18): dmg 340, Abfall ab 30 m mit 5,5/m, v0 366, reload 2.4
	_make({id = &"mp40", display_name = "MP 40", faction = "axis", slot = P, action = WeaponData.Action.AUTO,
		caliber = "9×19 mm", magazine_size = 32, start_magazines = 5, rpm = 600.0,
		reload_time = 2.4, muzzle_velocity = 366.0, damage = 34.0,
		falloff_start = 30.0, falloff_per_m = 0.55, spread_hip = 3.0, spread_aim = 0.8, recoil_pitch = 0.8, recoil_yaw = 0.4,
		spread_per_shot = 0.3, aim_fov = 55.0, noise_radius = 80.0, weight = 4.71, model_length = 0.83,
		color = Color(0.12, 0.12, 0.12)})
	# "MP 44" (26): items.sav v1.12 dmg 380, v0 750, Abfall ab 70 m mit 2,0/m (item_shoot.tbl alt: 333/655), reload 2.4
	_make({id = &"stg44", display_name = "StG 44", faction = "axis", slot = P, action = WeaponData.Action.AUTO,
		can_toggle_auto = true, caliber = "7,92×33 mm Kurz", magazine_size = 30, start_magazines = 4,
		rpm = 600.0, reload_time = 2.4, muzzle_velocity = 750.0, damage = 38.0,
		falloff_start = 70.0, falloff_per_m = 0.2, spread_hip = 3.5, spread_aim = 0.4, recoil_pitch = 1.3, recoil_yaw = 0.6,
		spread_per_shot = 0.35, aim_fov = 48.0, noise_radius = 120.0, weight = 5.136, model_length = 0.94,
		color = Color(0.16, 0.15, 0.13)})
	# Schallgedämpfte deutsche Waffen (Wunsch Auftraggeber, Mehrspieler): Karabiner 98k mit Schalldämpfer
	# (Unterschallmunition, Klang wie De-Lisle-Karabiner) und MP 40 mit Schalldämpfer (Klang wie Sten Mk II S).
	# Kein Original: Schaden des Grundmodells (K98k 488 / MP 40 340), Abfall wie De Lisle (25 m, 10,35/m) bzw.
	# Sten + Schalldämpfer (28 m, 5,0/m) [D, angelehnt an Originalwerte]
	_make({id = &"kar98k_sd", display_name = "Karabiner 98k (Schalldämpfer)", faction = "axis", slot = P,
		action = WeaponData.Action.BOLT, caliber = "7,92×57 mm (Unterschall)", magazine_size = 5, start_magazines = 6,
		bolt_time = 1.4, reload_time = 3.8, muzzle_velocity = 300.0, damage = 48.8, falloff_start = 25.0, falloff_per_m = 1.035,
		spread_hip = 2.5, spread_aim = 0.12, recoil_pitch = 2.6, recoil_yaw = 0.5, aim_fov = 40.0,
		noise_radius = 15.0, weight = 4.4, model_length = 1.3, sound = &"silenced_rifle"})
	_make({id = &"mp40_sd", display_name = "MP 40 (Schalldämpfer)", faction = "axis", slot = P,
		action = WeaponData.Action.AUTO, caliber = "9×19 mm", magazine_size = 32, start_magazines = 5, rpm = 600.0,
		reload_time = 2.4, muzzle_velocity = 305.0, damage = 34.0, falloff_start = 28.0, falloff_per_m = 0.5, spread_hip = 3.2,
		spread_aim = 0.9, recoil_pitch = 0.7, recoil_yaw = 0.4, spread_per_shot = 0.3, aim_fov = 55.0,
		noise_radius = 15.0, weight = 4.6, model_length = 1.0, color = Color(0.12, 0.12, 0.12), sound = &"silenced_smg"})
	# Stielhandgranate (Original „Stielhang. 39“, Gegenstand 61): Stärke/Radius [O], Wurf [D]
	_make({id = &"m24", display_name = "Stielhandgranate 24", faction = "axis", slot = G,
		action = WeaponData.Action.THROWN, magazine_size = 1, start_magazines = 2, rpm = 40.0,
		reload_time = 0.8, damage = 199.9, fuse_time = 3.5, blast_radius = 10.0, throw_speed = 18.0,
		noise_radius = 180.0, weight = 0.363, model_length = 0.35, color = Color(0.25, 0.27, 0.22)})
	# "parabel" (0): dmg 300, Abfall ab 15 m mit 14/m, v0 351, reload 1.7
	_make({id = &"p08", display_name = "Pistole 08", faction = "axis", slot = S, action = WeaponData.Action.SEMI,
		caliber = "9×19 mm", magazine_size = 8, start_magazines = 3, rpm = 300.0,
		reload_time = 1.7, muzzle_velocity = 351.0, damage = 30.0,
		falloff_start = 15.0, falloff_per_m = 1.4, spread_hip = 2.8, spread_aim = 0.7, recoil_pitch = 2.0, recoil_yaw = 0.7,
		aim_fov = 60.0, noise_radius = 60.0, weight = 0.965, model_length = 0.22, color = Color(0.12, 0.12, 0.12)})
