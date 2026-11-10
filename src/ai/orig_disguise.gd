class_name OrigDisguise
extends RefCounted
## AP-6 (B-034): Uniformtarnung nach hd2.exe (GAP_REA AP-7 G). Nur Originalmissionen offline (Einzelspieler,
## DAT_00982100 & 7 == 7). Ersetzt die frühere Schätzung „getarnt ab 8 m, 6 s nach Schuss“ [E].
##
## Original [B]: Tarnwert Mensch+0x16C (0…100).
##  - Anziehen einer Uniform (0x59D100): sofort 100 (Soldier.put_on_uniform).
##  - Mensch-Update 0x59FFD0: zuerst 0x5A50A0 → −1 je lebendem Gegner, der den Spieler wahrnimmt (Sensor 0x46F320) und ihn
##    nicht in der Freundliste hat; danach (nur SP) 0x5A60D0(0.5) → +0,5, wenn alle Kleidungsplätze feindlich sind, sonst 0.
##    Leiche tragen (+0x174) → 0. Die Zunahme ist eine Konstante je Aufruf, NICHT mit dt skaliert (Aufruf mit 0x3F000000,
##    dt geht nur an andere Teilaufrufe) [B].
##  - Seite (0x5A84F0): Tarnung an und Wert > 0 → Seite der Uniform; Wert ≤ 0 → eigene Seite (enttarnt).
## Takt: das Mensch-Update läuft je Simulationsbild [P]; die Bildrate des Originals ist nicht fest belegt → Nachbau festes
## Raster UPDATE_HZ = 30 Hz [E] (Netto bei einem Beobachter −0,5/Update = −15/s → von 100 auf 0 in ≈ 6,7 s).
## Nachbau-Zuordnung [P]: „ganze Kleidung feindlich“ = Soldier.disguised (Feinduniform angezogen); „Leiche tragen“ =
## Meta „carried“ ist ein Soldat; „nimmt wahr“ = Perception.disguise_seen (Kegel/Weite/Sichtlinie wie 0x570280).

const UPDATE_HZ := 30.0
const GAIN := 0.5
const LOSS_PER_OBSERVER := 1.0
const MAX_VALUE := 100.0

var _acc := 0.0


## Ein Update-Schritt (rein, testbar): neuer Wert.
static func step(value: float, observers: int, enemy_clothes: bool, carrying_corpse: bool) -> float:
	value -= LOSS_PER_OBSERVER * observers
	if carrying_corpse or not enemy_clothes:
		return 0.0
	return clampf(value + GAIN, 0.0, MAX_VALUE)


## Getarnt im Sinne von 0x5A84F0: Feinduniform und Wert > 0 – dazu [D]: keine sichtbare Ausrüstung der eigenen Seite.
static func is_cover_active(s: Soldier) -> bool:
	return s != null and s.disguised and s.disguise_value > 0.0 and gear_matches(s)


## [D] Abweichung vom Original: Die Tarnung wirkt nur, wenn auch alles Sichtbare zur Feindseite passt – Waffe in der
## Hand, an der Schulter, auf dem Rücken und der Rucksack (oder kein Rucksack). Seitenkennung items.sav +0x7C
## (Net.item_side_flag: 0 Alliierte, 1 Achse, 2 beide); ein Gegenstand nur der eigenen Seite verrät den Soldaten.
static func gear_matches(s: Soldier) -> bool:
	var own_flag := 1 if s.team == Soldier.TEAM_AXIS else 0
	for id in visible_items(s):
		if id >= 0 and Net.item_side_flag(id) == own_flag:
			return false
	return true


## Sichtbare Gegenstände: Hände, Schulter, Rücken (Rucksack) und zweite Langwaffe auf dem Rücken.
static func visible_items(s: Soldier) -> Array:
	var out: Array = []
	var inv := FieldInventory.view(s)
	for slot in ["hands", "shoulder", "back"]:
		out.append(int(inv.get(slot, -1)))
	var bw := FieldInventory.back_weapon(s)
	if bw:
		out.append(FieldInventory.weapon_item(bw, s.team))
	return out


static func carrying_corpse(s: Soldier) -> bool:
	if not s.has_meta("carried"):
		return false
	var c = s.get_meta("carried")
	return c is Soldier and is_instance_valid(c)


## Gegner, die s gerade wahrnehmen (Perception.disguise_seen bzw. visible_now).
static func observers_of(s: Soldier, tree: SceneTree) -> int:
	var n := 0
	for node in tree.get_nodes_in_group("soldiers"):
		var o := node as Soldier
		if o == null or not o.alive or o.team == s.team or o.team == Soldier.TEAM_NEUTRAL:
			continue
		var p: Perception = o.get_node_or_null("Perception")
		if p and (p.disguise_seen.get(s, false) or p.visible_now.get(s, false)):
			n += 1
	return n


## Je Physikbild aus LsRuntime; wendet das 30-Hz-Raster auf alle Soldaten in Feinduniform des Trupps an.
func tick(delta: float, members: Array, tree: SceneTree) -> void:
	_acc += delta
	var step_s := 1.0 / UPDATE_HZ
	while _acc >= step_s:
		_acc -= step_s
		for m in members:
			var s := m as Soldier
			if s == null or not s.alive:
				continue
			if not s.disguised:
				s.disguise_value = 0.0
				continue
			s.disguise_value = step(s.disguise_value, observers_of(s, tree), true, carrying_corpse(s))
