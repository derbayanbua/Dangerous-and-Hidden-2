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


## Menschliche Reaktionszeit (s) bis zum ersten Schuss: Grundwert der Rolle, länger auf Distanz und gegen
## geduckte/liegende Ziele, kürzer gegen laufende (fallen auf); ±20 % Streuung.
## Human-like reaction time (s) before the first shot: role base, longer at range and against crouched/prone
## targets, shorter against moving ones (they stand out); ±20 % jitter.
static func reaction(base: float, dist: float, stance: int, moving: bool) -> float:
	var r := base + clampf(dist / 50.0 * 0.25, 0.0, 0.8)
	if stance == Soldier.Stance.CROUCH:
		r += 0.1
	elif stance == Soldier.Stance.PRONE:
		r += 0.25
	if moving:
		r -= 0.1
	return maxf(r * randf_range(0.8, 1.2), 0.35)


## Anfänglicher Zielfehler (Meter am Ziel): wächst mit Distanz, kleinem Ziel und geringem Können; senkrecht nur
## nach unten (Brust/Bauch statt Kopf – kein sofortiger Kopfschuss). Wird in BotBrain.engage über die Zielzeit abgebaut.
## Initial aim error (metres at the target): grows with range, small target and low skill; vertical part only
## downwards (chest/belly instead of head – no instant headshot). BotBrain.engage reduces it over tracking time.
static func aim_offset(dist: float, stance: int, skill: float) -> Vector3:
	var m := (0.15 + dist * 0.012) * clampf(1.3 - skill, 0.3, 1.3)
	if stance == Soldier.Stance.PRONE:
		m *= 1.4
	elif stance == Soldier.Stance.CROUCH:
		m *= 1.15
	var a := randf() * TAU
	return Vector3(cos(a) * m, -absf(sin(a)) * m * 0.6, sin(a) * m * 0.5)


static func trait_name(t: int) -> String:
	return NAMES[t] if t >= 0 and t < NAMES.size() else "?"
