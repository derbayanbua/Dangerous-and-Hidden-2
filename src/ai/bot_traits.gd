class_name BotTraits
extends RefCounted
## Charakter-Eigenschaften (Persönlichkeiten) der Mehrspieler-KI-Soldaten, zusätzlich zur Rolle (BotBrain.Role).
## Zuweisung nach Rolle UND tatsächlich ausgegebener Waffe (Kartenwaffen können die Rollenwaffe ersetzen):
##   CAMPER     – Schalldämpfer-Typ: verdeckte Stellung mit Sicht auf Zufahrten/Zone, bleibt lange, wechselt nach Entdeckung
##   FLANKER    – umgeht seitlich über Deckung, rückt vor während Deckungsfeuer läuft, Granaten in Deckungen/Räume
##   SUPPORT    – Deckungsfeuer: MG, Feuerstöße auf Feind bzw. letzte bekannte Lage, bleibt in Deckung, Stellungswechsel
##   SNIPER     – große Distanz, erhöhte/verdeckte Stellung, Stellungswechsel nach dem Schuss
##   RIFLEMAN   – Standardverhalten der Einzelspieler-Gegner-KI (Deckung, Herausschauen, Flankieren); Sanitäter
## Rein serverseitig; Einzelspieler-KI unberührt.

enum Trait { RIFLEMAN, CAMPER, FLANKER, SUPPORT, SNIPER }
const NAMES := ["Schütze", "Camper", "Flankierer", "Deckungsfeuer", "Scharfschütze"]


## Waffenart der Primärwaffe: "mg", "scoped", "silenced", "auto", "rifle", ""
static func weapon_kind(s: Soldier) -> String:
	if s == null or s.weapons.is_empty():
		return ""
	var w: Weapon = s.weapons[WeaponData.Slot.PRIMARY]
	if w == null:
		return ""
	var d := w.data
	if (d.action == WeaponData.Action.AUTO or d.can_toggle_auto) and (d.weight > 8.0 or d.magazine_size >= 47):
		return "mg"
	if d.aim_fov <= 30.0 and d.action in [WeaponData.Action.BOLT, WeaponData.Action.SEMI]:
		return "scoped"
	if d.noise_radius < 20.0:
		return "silenced"
	if d.action == WeaponData.Action.AUTO or d.can_toggle_auto:
		return "auto"
	return "rifle"


## Seitenwaffe schallgedämpft?
static func has_silenced_sidearm(s: Soldier) -> bool:
	var p: Weapon = s.weapons[WeaponData.Slot.SIDEARM] if s.weapons.size() > WeaponData.Slot.SIDEARM else null
	return p != null and p.data.noise_radius < 20.0


## Persönlichkeit passend zu Rolle und Waffe. role = BotBrain.Role (ASSAULT, MEDIC, AT, SNIPER, SNEAKER)
static func pick(role: int, s: Soldier) -> int:
	var k := weapon_kind(s)
	match role:
		0:   # Sturmsoldat
			return Trait.SUPPORT if k == "mg" else Trait.FLANKER
		1:   # Sanitäter: bleibt beim Trupp (Standardverhalten)
			return Trait.RIFLEMAN
		2:   # Panzerabwehr: Raketenwerfer/Granaten gegen Deckungen
			return Trait.FLANKER
		3:   # Scharfschütze
			return Trait.SNIPER if k == "scoped" else (Trait.CAMPER if k == "silenced" else Trait.RIFLEMAN)
		4:   # Schleicher
			return Trait.CAMPER if (k == "silenced" or has_silenced_sidearm(s) or k == "scoped") else Trait.FLANKER
	# unbekannte Rolle: nach Waffe
	match k:
		"mg": return Trait.SUPPORT
		"scoped": return Trait.SNIPER
		"silenced": return Trait.CAMPER
	return Trait.RIFLEMAN


static func trait_name(t: int) -> String:
	return NAMES[t] if t >= 0 and t < NAMES.size() else "?"
