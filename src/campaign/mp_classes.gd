class_name MpClasses
extends RefCounted
## 0.11.1 – Mehrspieler-Klassen und Soldatenwerte. BEWUSSTE ABWEICHUNG vom Original [D]: Das Original kennt im MP
## 5 Klassen je Seite (mp.json-Vorlagen, MG-/Scharf-/Gewehrschütze, Grenadier, Sturmschütze) und Figuren ohne
## Kaderwerte. Hier: 7 eigene Klassen, deren Ausrüstung aus dem Lager der Karte (ALLOWEDITEMS) zusammengestellt wird,
## und MP-Figuren mit den Werten des SAS-Kaders (orig_cache/roster.json) – gleiche Wirkung wie im Einzelspieler
## (Gesundheit × OrigMission.HP_SCALE, Schießen → Streuung, Tarnung → Erkennbarkeit, Ausdauer → Sprint, Erste Hilfe →
## Verband, Schlösser → Knacken, Kraft → Traglast; Moral ohne Wirkung wie im Einzelspieler).
## Server-maßgeblich: Clients senden nur Klasse (Net.request_class) und Figur (Net.request_figure); Werte und
## Klassen-Ausrüstung berechnet jeder Rechner deterministisch aus Klasse, Figur, Seite und Karte.
## Kartenvorgaben haben Vorrang: nicht erlaubte Waffe → nächste Wunschwaffe bzw. Original-Ersatzregel
## (Net.orig_substitute); Panzerabwehr ohne erlaubten Werfer → zusätzliche Granaten. Alle Mengen/Wahlen [D].

enum { MEDIC, SNIPER, ANTITANK, ASSAULT, SNEAKER, HEAVY, SCOUT }
const COUNT := 7
const DEFAULT := ASSAULT
const KEYS := ["medic", "sniper", "antitank", "assault", "sneaker", "heavy", "scout"]
## Schlüssel = deutscher Text (locale/ui_texts.csv)
const NAMES := ["Sanitäter", "Scharfschütze", "Panzerabwehr", "Sturmsoldat", "Schleicher", "Schwerer Schütze", "Aufklärer"]
const DESCS := [
	"Sanitäter: MP oder Karabiner, zwei kleine und ein großer Verbandskasten, Überspritze. Soldat mit bestem Erste-Hilfe-Wert.",
	"Scharfschütze: schweres Scharfschützengewehr. Soldat mit bestem Schießen-Wert.",
	"Panzerabwehr: leichter Karabiner, Raketen, Minen und Sprengstoff (ohne Werfer auf der Karte: mehr Granaten). Soldat mit hoher Kraft.",
	"Sturmsoldat: Maschinenpistole oder Sturmgewehr und viele Granaten. Soldat mit ausgewogenen Werten.",
	"Schleicher: schallgedämpfte Waffen mit weniger Streuung. Soldat mit hoher Tarnung.",
	"Schwerer Schütze: schweres MG, Minen und Granaten. Soldat mit mittlerer Traglast.",
	"Aufklärer: leichtes Scharfschützengewehr, Fernglas und Granaten. Soldat mit hoher Ausdauer und wenig Gesundheit.",
]
## Rolle der KI-Soldaten (BotBrain.Role: ASSAULT, MEDIC, AT, SNIPER, SNEAKER) je Klasse
const BOT_ROLE := [1, 3, 2, 0, 4, 0, 3]
## Schleicher: Streuungsfaktor mit schallgedämpfter Waffe [D]
const SNEAK_SPREAD_K := 0.6
## Großer Verbandskasten (items.sav 53 „medikit BIG“): Heilwirkung × 2 gegenüber dem kleinen (54) [D]
const BIG_MEDKIT := 53
const SMALL_MEDKIT := 54
const BIG_MEDKIT_K := 2.0
## Überspritze (Wiederbeleben): PLATZHALTER-Gegenstand ohne Wirkung, Wirkung kommt mit dem Coop-Block [D]
const REVIVE_SYRINGE := 901

## Wunschwaffen je Klasse und Seite (Original-Nummern, Reihenfolge = Vorrang)
const PRIMARY := {
	MEDIC: {"allied": [21, 11, 20], "axis": [18, 4]},
	SNIPER: {"allied": [17, 15], "axis": [13, 16]},
	ANTITANK: {"allied": [11, 6], "axis": [4]},
	ASSAULT: {"allied": [20, 21, 10], "axis": [26, 18]},
	SNEAKER: {"allied": [7, 22], "axis": [4, 18]},
	HEAVY: {"allied": [29, 28, 34], "axis": [33, 19, 31]},
	SCOUT: {"allied": [15, 17], "axis": [13, 16]},
}
const PRIMARY_MAGS := [4, 6, 3, 6, 5, 4, 5]
const GRENADES := [1, 1, 2, 6, 1, 3, 3]
const ANTITANK_NO_LAUNCHER_GRENADES := 6
const SIDEARM := {"allied": [2, 1], "axis": [0]}
const SNEAK_SIDEARM := {"allied": [2], "axis": [260, 0]}
const GRENADE := {"allied": [62, 60], "axis": [61]}
const KNIFE := {"allied": [57, 56], "axis": [56, 57]}
const LAUNCHER := {"allied": [39, 264, 38], "axis": [264, 38, 39]}
const BACKPACK := {"allied": [101, 222, 228, 100], "axis": [97, 95]}
## Schalldämpfer-Varianten der Achse (eigene Waffen, zählen als Grundmodell – Net.is_item_allowed)
const AXIS_SILENCED := {4: "kar98k_sd", 18: "mp40_sd"}

## Uniform je Klima der Karte und Seite (Vorrang der Reihe nach; Helm = Standardhelm der Uniform) [D]
const UNIFORMS := {
	"winter": {"allied": [122, 118], "axis": [126, 136]},
	"desert": {"allied": [119, 114], "axis": [139, 140, 141]},
	"jungle": {"allied": [120, 118], "axis": [162, 161]},
	"temperate": {"allied": [123, 118], "axis": [129, 131]},
}


static func label(c: int) -> String:
	return TranslationServer.translate(NAMES[clampi(c, 0, COUNT - 1)])


static func description(c: int) -> String:
	return TranslationServer.translate(DESCS[clampi(c, 0, COUNT - 1)])


static func side_of(team: int) -> String:
	return "axis" if team == Soldier.TEAM_AXIS else "allied"


# --- Soldatenwahl nach Werten -------------------------------------------------------------------------------
## Kader-Index einer Figur ("sas:N" SAS-Kader, "mp:N" MP-Figur HumanStore 30–56), sonst −1
static func figure_store(fig: String) -> int:
	if fig.begins_with("sas:") and fig.substr(4).is_valid_int():
		return int(fig.substr(4))
	if fig.begins_with("mp:") and fig.substr(3).is_valid_int():
		return int(fig.substr(3))
	return -1


static func stats_of(idx: int) -> Dictionary:
	return (SAS.store(idx).get("stats", {}) as Dictionary) if idx >= 0 else {}


## Bewertung eines Kadersoldaten für eine Klasse (höher = besser)
static func score(c: int, st: Dictionary, avg: Dictionary, med_strength: float) -> float:
	var hp := float(st.get("health", 500.0))
	var kr := float(st.get("strength", 30.0))
	match c:
		MEDIC:
			return float(st.get("first_aid", 50.0)) + hp * 0.001
		SNIPER:
			return float(st.get("shooting", 50.0)) + float(st.get("stealth", 50.0)) * 0.001
		ANTITANK:
			return kr + hp * 0.001
		SNEAKER:
			return float(st.get("stealth", 50.0)) + float(st.get("shooting", 50.0)) * 0.001
		HEAVY:
			return -absf(kr - med_strength) * 10.0 + hp * 0.01
		SCOUT:
			return float(st.get("endurance", 50.0)) - hp * 0.1
	# ASSAULT: möglichst nahe am Kaderdurchschnitt (ausgewogene Werte)
	var d := 0.0
	for k in avg:
		var span := 600.0 if k == "health" else (40.0 if k == "strength" else 100.0)
		d += absf(float(st.get(k, 50.0)) - float(avg[k])) / span
	return -d


## Kadersoldat mit den passenden Werten für die Klasse (gleicher Gleichstand → kleinerer Index)
static func best_soldier(c: int) -> int:
	var pool: Array = SAS.store_indices()
	if pool.is_empty():
		return -1
	var avg := {}
	var strengths: Array = []
	for idx in pool:
		var st := stats_of(int(idx))
		strengths.append(float(st.get("strength", 30.0)))
		for k in ["health", "strength", "endurance", "shooting", "stealth", "first_aid"]:
			avg[k] = float(avg.get(k, 0.0)) + float(st.get(k, 50.0)) / pool.size()
	strengths.sort()
	var med: float = strengths[strengths.size() / 2]
	var best := -1
	var best_sc := -INF
	for idx in pool:
		var sc := score(c, stats_of(int(idx)), avg, med)
		if sc > best_sc + 1e-6:
			best_sc = sc
			best = int(idx)
	return best


static func best_figure(c: int) -> String:
	var idx := best_soldier(c)
	return "sas:%d" % idx if idx >= 0 else ""


## Wirksame Figur eines Spielers: eigene Wahl, sonst der Soldat seiner Klasse
static func effective_figure(fig: String, c: int) -> String:
	if fig.begins_with("hero:"):
		return fig
	return fig if not stats_of(figure_store(fig)).is_empty() else best_figure(c)


static func strength_of(fig: String) -> float:
	return float(stats_of(figure_store(fig)).get("strength", 30.0))


## Kaderwerte auf die Figur (wie Game.apply_sas; Server und Clients gleich, Quelle nur roster.json)
static func apply_stats(s: Soldier, fig: String, c: int) -> void:
	var st := stats_of(figure_store(fig))
	if st.is_empty():
		s.max_health = 100.0
		s.health = 100.0
	else:
		s.max_health = maxf(float(st.get("health", 500)) * OrigMission.HP_SCALE, 1.0)
		s.health = s.max_health
		s.skill_shooting = float(st.get("shooting", 50))
		s.skill_stealth = float(st.get("stealth", 50))
		s.skill_endurance = float(st.get("endurance", 50))
		s.skill_first_aid = float(st.get("first_aid", 50))
		s.set_meta("lockpick", float(st.get("lockpick", 50)))
		s.set_meta("mp_strength", float(st.get("strength", 30)))
	s.set_meta("mp_figure", fig)
	s.set_meta("mp_class_id", c)
	s.silenced_spread_k = SNEAK_SPREAD_K if c == SNEAKER else 1.0


# --- Ausrüstung ---------------------------------------------------------------------------------------------
static func climate_of(map: String) -> String:
	var f := (Game.orig_folder(map) + " " + map).to_lower()
	if f.contains("arctic") or f.contains("norway") or f.contains("arkt"):
		return "winter"
	if f.contains("africa") or f.contains("afrika") or f.begins_with("af"):
		return "desert"
	if f.contains("burma"):
		return "jungle"
	return "temperate"


static func _avail(inv: Dictionary, allowed: Array, team: int, id: int) -> bool:
	if id < 0 or SAS.item(id).is_empty():
		return false
	if allowed.is_empty():
		return Net._side_ok(team, id)
	return MpLoadout.remaining(inv, allowed, team, id) > 0


## Erste verfügbare Wunschwaffe, sonst Original-Ersatzregel aus dem Lager der Seite (−1 = keine)
static func _pick(inv: Dictionary, allowed: Array, team: int, prefs: Array, substitute := true) -> int:
	for id in prefs:
		if _avail(inv, allowed, team, int(id)):
			return int(id)
	if not substitute or allowed.is_empty() or prefs.is_empty():
		return -1
	var got := Net.orig_substitute(int(prefs[0]), Net.storage_of(allowed, team, true), team == Soldier.TEAM_AXIS, 0)
	return got if _avail(inv, allowed, team, got) else -1


static func uniform_for(map: String, team: int, allowed: Array) -> int:
	var inv := SAS.new_inventory()
	var side := side_of(team)
	var prefs: Array = (UNIFORMS[climate_of(map)][side] as Array) + (UNIFORMS["temperate"][side] as Array)
	for id in prefs:
		if _avail(inv, allowed, team, int(id)):
			return int(id)
	for k in Net.storage_of(allowed, team, true):
		if MpLoadout.slot_of(int(k)) == "uniform":
			return int(k)
	return -1


static func _add(inv: Dictionary, allowed: Array, team: int, strength: float, id: int, n: int) -> int:
	var got := 0
	for i in n:
		if id < 0 or not _avail(inv, allowed, team, id) or not SAS.can_add(inv, strength, id, 1):
			break
		SAS.add_item(inv, id, 1)
		got += 1
	return got


## Klassen-Ausrüstung im SAS-Inventarformat (MpLoadout), an Karte, Seite und Traglast angepasst
static func build(c: int, team: int, allowed: Array, map: String, strength: float) -> Dictionary:
	c = clampi(c, 0, COUNT - 1)
	var side := side_of(team)
	var inv := SAS.new_inventory()
	var uni := uniform_for(map, team, allowed)
	inv["uniform"] = uni
	inv["head"] = MpLoadout.uniform_head(uni)
	var bp := _pick(inv, allowed, team, BACKPACK[side], false)
	if bp >= 0:
		inv["back"] = bp
	var prim := _pick(inv, allowed, team, PRIMARY[c][side])
	if prim >= 0:
		inv["hands"] = prim
	var am := SAS.ammo_of(prim) if prim >= 0 else -1
	if am >= 0 and am != prim:
		_add(inv, allowed, team, strength, am, 2)                 # Grundmenge zuerst, Rest weiter unten
	var sa := _pick(inv, allowed, team, (SNEAK_SIDEARM if c == SNEAKER else SIDEARM)[side])
	if sa >= 0 and _add(inv, allowed, team, strength, sa, 1) > 0:
		_add(inv, allowed, team, strength, SAS.ammo_of(sa), 1)
	_add(inv, allowed, team, strength, _pick(inv, allowed, team, KNIFE[side], false), 1)
	var nade := _pick(inv, allowed, team, GRENADE[side])
	var nades := int(GRENADES[c])
	match c:
		MEDIC:
			_add(inv, allowed, team, strength, SMALL_MEDKIT, 2)
			_add(inv, allowed, team, strength, BIG_MEDKIT, 1)
			_add(inv, allowed, team, strength, REVIVE_SYRINGE, 1)
		ANTITANK:
			var la := _pick(inv, allowed, team, LAUNCHER[side], false)
			if la >= 0 and _add(inv, allowed, team, strength, la, 1) > 0:
				# möglichst viele Raketen, Minen, Sprengstoff (Traglast der Figur)
				if WeaponDB.LAUNCHER_AMMO.has(la):
					_add(inv, allowed, team, strength, int(WeaponDB.LAUNCHER_AMMO[la]), 6)
				if la == 38:
					_add(inv, allowed, team, strength, 38, 3)
				_add(inv, allowed, team, strength, 71, 2)
				_add(inv, allowed, team, strength, 70, 3)
				_add(inv, allowed, team, strength, 68, 3)
				_add(inv, allowed, team, strength, 67, 2)
			else:
				nades += ANTITANK_NO_LAUNCHER_GRENADES    # kein Raketenwerfer auf der Karte erlaubt
				_add(inv, allowed, team, strength, 70, 2)
				_add(inv, allowed, team, strength, 68, 2)
		HEAVY:
			_add(inv, allowed, team, strength, 70, 2)
		SNIPER, SCOUT:
			_add(inv, allowed, team, strength, 99, 1)
	_add(inv, allowed, team, strength, nade, nades)
	if c != MEDIC:
		_add(inv, allowed, team, strength, SMALL_MEDKIT, 1)
	if am >= 0 and am != prim:
		_add(inv, allowed, team, strength, am, maxi(int(PRIMARY_MAGS[c]) - 2, 0))
	return inv


## Schleicher der Achse: K98k/MP 40 aus dem Lager als Schalldämpfer-Variante führen (nach Net._apply_inventory)
static func finish_weapons(s: Soldier, c: int, team: int) -> void:
	if c != SNEAKER or team != Soldier.TEAM_AXIS:
		return
	var w: Weapon = s.weapons[WeaponData.Slot.PRIMARY]
	if w == null:
		return
	var oi := WeaponDB.orig_item_of(w.data.id)
	if not AXIS_SILENCED.has(oi):
		return
	var wd := WeaponDB.get_weapon(StringName(AXIS_SILENCED[oi]))
	if wd == null:
		return
	var nw := Weapon.new(wd)
	nw.in_mag = mini(w.in_mag, wd.magazine_size)
	nw.reserve = w.reserve
	s.weapons[WeaponData.Slot.PRIMARY] = nw
	if s.current_slot == WeaponData.Slot.PRIMARY:
		s.select_slot(WeaponData.Slot.PRIMARY)
