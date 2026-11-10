class_name Perception
extends Node
## Sinneskomponente eines Soldaten (Kind-Node).
## Sehen: Sichtkegel + Reichweite + Sichtlinien-Raycast. Erkennung wächst
## pro Ziel graduell (Haltung, Bewegung, Entfernung, Peripherie) — Grundlage
## für Schleichen. Hören: Events.noise_emitted innerhalb Radius * Hörfaktor.
## Belegte Originalparameter: HUMAN_SETSIGHTRANGE (meist 25–80 m),
## HUMAN_SETHEARRANGE (meist 50–80 m), bei Alarm Sichtweite 300 m.

signal target_detected(target: Soldier)      ## Erkennung erreicht 1.0
signal suspicious(position: Vector3)          ## Erkennung > 0.35 oder Geräusch
signal heard(position: Vector3, kind: StringName, source: Node)
signal corpse_seen(corpse: Soldier)

@export var sight_range := 55.0
@export var hear_range := 60.0    ## skaliert Geräuschradien (60 = Referenz)
@export var fov_deg := 130.0
@export var detection_speed := 1.0

var soldier: Soldier
var awareness := {}               ## Soldier -> 0..1
var visible_now := {}             ## Soldier -> bool (aktueller Tick)
var last_known := {}              ## Soldier -> Vector3
var known_corpses := {}           ## Soldier -> true
var disguise_seen := {}           ## AP-6: Soldier -> bool, getarnt wahrgenommen (aktueller Tick, nur orig_formula)
var _tick := 0.0
const TICK := 0.15

## B-021: Formel des Originals (nur Originalmissionen offline; setzt EnemyBrain, MP-Bots/Übungseinsätze unverändert).
## hd2.exe 0x5A59E0 „Sichtbarkeitsweite des Ziels“ (HUD zeigt sie als „%.0fm“, 0x4B4258; ECX = Ziel) [B, AP-7 I]:
##   Grundwert nach WAFFENHALTUNG (Steuerwort +0x50 Bits 0–2, Setzer 0x584B60): 50 m Waffe weg / 70 m bereit / 100 m Anschlag
##   oder im Fahrzeug [B]; in Bewegung (Bits 0xF8) × Gangklasse: 0x10000 Sprint ×1,8, 0x4000 Laufen/Gehen ×1,6, 0x2000 geduckt
##   ×1,3, 0x8000 ×1,2 (keinem KI-Gang zugeordnet), 0x1000 Schleichen ×1,05 [B]; nach eigenem Schuss (+0xB0 ≤ 8000 ms)
##   mindestens 300/380/450 m [B Werte, P Zuordnung zur Waffenhaltung], × Licht des Sektors (+0xDA4, 0x5AC350) [B].
##   Sicht 0x570280: Reichweite = min(Sichtbarkeitsweite, Sichtweite +0x110), Kegel ±50°, Treffer → sofort 100 [B].
var orig_formula := false
## G-004 (B-026): BEWUSSTE ABWEICHUNG – MP-Bots und Übungseinsätze (eigene Entwürfe) behalten die abgestufte Erkennung
## `_visibility` [E] (Spielbalance, kein Original-Gegenstück). Option `--orig_perception=1` schaltet die Original-Formel
## für alle KI ein (Vergleich/Spieltest). Wird beim ersten Zugriff aus der Kommandozeile gelesen.
static var _orig_all := -1


static func orig_everywhere() -> bool:
	if _orig_all < 0:
		_orig_all = 1 if "--orig_perception=1" in OS.get_cmdline_user_args() else 0
	return _orig_all == 1


static func set_orig_everywhere(on: bool) -> void:
	_orig_all = 1 if on else 0
const ORIG_HALF_FOV := 50.0                       ## Grad, 0x570280 (local_70 = 50) [B]
const ORIG_BASE := [50.0, 70.0, 100.0]            ## Waffenhaltung WEG/BEREIT/ANSCHLAG [B]
const ORIG_SHOT_FLOOR := [300.0, 380.0, 450.0]    ## nach Schuss (≤ 8 s) je Waffenhaltung [B Werte, P Zuordnung]
enum WeaponHold { AWAY, READY, AIMED }
## Gangklassen-Faktoren 0x5A59E0 [B]
const ORIG_GAIT_SPRINT := 1.8
const ORIG_GAIT_RUN := 1.6
const ORIG_GAIT_CROUCH := 1.3
const ORIG_GAIT_SNEAK := 1.05
const ORIG_SHOT_MS := 8.0                         ## 0x810BC0 = 8000 (7000 in Sonderfall 0x461A20) [B]


func _ready() -> void:
	soldier = get_parent() as Soldier
	_tick = randf() * TICK   # Last verteilen
	Events.noise_emitted.connect(_on_noise)


func _physics_process(delta: float) -> void:
	if soldier == null or not soldier.alive:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_refresh_light()
	_update_sight(TICK)


func enemy_team() -> int:
	if soldier.team == Soldier.TEAM_NEUTRAL:
		return -1     # neutrale Figuren suchen keine Ziele
	return Soldier.TEAM_AXIS if soldier.team == Soldier.TEAM_ALLIED else Soldier.TEAM_ALLIED


## Mögliche Gegner: Einzelspieler die andere Seite; Mehrspieler-KI (Deathmatch: jeder für sich) alle
## Soldaten anderer Teams außer Neutralen. Erkannt werden sie trotzdem nur über Sicht/Gehör (kein „Aimbot“).
## G-007 (B-026): Kandidatenliste je Team und Physikbild einmal gebaut und von allen Beobachtern geteilt (vorher legte online
## jeder Soldat je Takt ein neues Array über alle Soldaten an). Der Beobachter selbst ist nie im eigenen Teamfremd-Satz.
static var _cand_cache := {}      ## Team (online) bzw. Gegnerteam (offline) -> Array
static var _cand_frame := -1


func enemy_candidates() -> Array:
	var f := Engine.get_physics_frames()
	if f != _cand_frame:
		_cand_frame = f
		_cand_cache.clear()
	var key := (100 + soldier.team) if Net.is_online else enemy_team()
	if _cand_cache.has(key):
		return _cand_cache[key]
	var out: Array
	if Net.is_online:
		out = []
		for n in get_tree().get_nodes_in_group("soldiers"):
			var t := n as Soldier
			if t and t.team != soldier.team and t.team != Soldier.TEAM_NEUTRAL:
				out.append(t)
	else:
		out = get_tree().get_nodes_in_group("team_%d" % enemy_team())
	_cand_cache[key] = out
	return out


func _update_sight(dt: float) -> void:
	var eye := soldier.eye_position()
	var fwd := soldier.aim_direction()
	var space := soldier.get_world_3d().direct_space_state
	var half_fov := deg_to_rad(ORIG_HALF_FOV if orig_formula else fov_deg * 0.5)
	for node in enemy_candidates():
		var t := node as Soldier
		if t == null or not t.alive:
			continue
		var tpos := t.global_position + Vector3.UP * (1.2 if t.stance == Soldier.Stance.STAND else (0.8 if t.stance == Soldier.Stance.CROUCH else 0.3))
		var to := tpos - eye
		var seen := false
		# fix_performance: Vorfilter quadratisch (Reichweite ≤ sight_range), Kegel vor der teuren Sichtbarkeitsweite
		# (Licht über alle Lampen) und dem Raycast – Ergebnis unverändert
		var dist2 := to.length_squared()
		var ang := 0.0
		var cand := dist2 < sight_range * sight_range
		if cand:
			ang = fwd.angle_to(to)
			# Nahbereich: auch knapp hinter dem Sichtfeld wird Bewegung bemerkt
			cand = ang < half_fov or (dist2 < 16.0 and t.is_moving() and t.move_mode == Soldier.MoveMode.RUN)
		var dist := sqrt(dist2) if cand else 0.0
		var reach := sight_range
		if cand and orig_formula:
			reach = minf(sight_range, orig_visibility_distance(t))
		if orig_formula:
			disguise_seen[t] = false
		if cand and dist < reach:
			seen = _line_of_sight(space, eye, tpos, t)
			# AP-6: getarnter Spieler (Feinduniform, Tarnwert > 0) gilt als eigene Seite (0x5A84F0/0x5A0AB0): wahrgenommen
			# (zählt für −1/Update, OrigDisguise), aber kein Ziel [B]
			# Listenprüfung (Mensch +0x1A6, `checks_list_flag`): 0x5A0AB0 prüft bei gesetztem Flag vor dem Seitenvergleich,
			# ob das Ziel in der Spielerliste (0x89AD68+0x1C) steht → feindlich, Uniform wirkungslos [B] (CZECH5 GE_1,
			# CZECH6 C5_R01…, TUTORIAL T_Pool_Guard_1)
			if seen and orig_formula and OrigDisguise.is_cover_active(t) and not checks_list():
				disguise_seen[t] = true
				seen = false
			if seen:
				if orig_formula:
					awareness[t] = 1.0    # AP-3/AP-7: 0x570280 sofort 100, keine Rampe [B]
				else:
					var gain := _visibility(t, dist, ang, half_fov) * detection_speed * dt
					awareness[t] = minf(awareness.get(t, 0.0) + gain, 1.0)
				last_known[t] = t.global_position
		visible_now[t] = seen
		if not seen:
			awareness[t] = maxf(awareness.get(t, 0.0) - dt * 0.08, 0.0)
		var a: float = awareness.get(t, 0.0)
		if seen and a >= 1.0:
			target_detected.emit(t)
		elif seen and a > 0.35:
			suspicious.emit(t.global_position)
	# Gefallene Kameraden entdecken (Original: Reaktion auf tote Kameraden)
	for node in get_tree().get_nodes_in_group("corpses"):
		var c := node as Soldier
		if c == null or c.team != soldier.team or known_corpses.has(c):
			continue
		var cp := c.global_position + Vector3.UP * 0.3
		var to := cp - eye
		if to.length_squared() < sight_range * sight_range * 0.36 and fwd.angle_to(to) < half_fov and _line_of_sight(space, eye, cp, null):
			known_corpses[c] = true
			corpse_seen.emit(c)


## Wache mit Listenprüfung (+0x1A6): durchschaut die Feinduniform des Trupps [B 0x5A0AB0]
func checks_list() -> bool:
	if soldier == null or not soldier.has_meta("orig_params"):
		return false
	return int((soldier.get_meta("orig_params") as Dictionary).get("checks_list_flag", 0)) != 0


## Sichtbarkeitsfaktor pro Sekunde: 1.0 ≈ Erkennung in ~1 s.
func _visibility(t: Soldier, dist: float, ang: float, half_fov: float) -> float:
	var stance_k := [1.0, 0.55, 0.25][t.stance] as float
	var move_k := 0.6
	if t.is_moving():
		move_k = 1.6 if t.move_mode == Soldier.MoveMode.RUN else (0.8 if t.move_mode == Soldier.MoveMode.SNEAK or t.stance != Soldier.Stance.STAND else 1.1)
	if t.trigger and t.current_weapon() and t.current_weapon().cooldown > 0.0:
		move_k = 2.0   # Mündungsfeuer
	var dist_k := clampf(1.0 - dist / sight_range, 0.0, 1.0)
	dist_k = 0.15 + 2.6 * dist_k * dist_k
	var periph := 1.0 if ang < half_fov * 0.4 else 0.45
	# Tarnung: in Feinduniform auf Distanz unauffällig; aus der Nähe oder nach
	# eigenem Schuss fällt sie auf (Original: Mission_SetUniformDisguise)
	if t.disguised and t.seconds_since_shot() > 6.0 and not checks_list() and OrigDisguise.gear_matches(t):
		if dist > 8.0:
			return 0.0
		var odd := 1.0 if (t.stance == Soldier.Stance.PRONE or t.move_mode == Soldier.MoveMode.RUN) else 0.35
		periph *= odd
	var light := _light_of(t)
	return stance_k * move_k * dist_k * periph * 1.4 * light * Soldier.skill_k(t.skill_stealth, 1.3, 0.6)


## Sichtbarkeitsweite eines Ziels in m nach hd2.exe 0x5A59E0 (siehe orig_formula).
func orig_visibility_distance(t: Soldier) -> float:
	var hold := weapon_hold(t)
	var v: float = 100.0 if t.vehicle != null else ORIG_BASE[hold]
	if t.vehicle == null and t.is_moving():
		v *= orig_gait_factor(t)
	if t.seconds_since_shot() < ORIG_SHOT_MS:
		v = maxf(v, ORIG_SHOT_FLOOR[hold])
	var light := _light_of(t)
	# Tarnung in Feinduniform: seit AP-6 über den Tarnwert (OrigDisguise, Seitenwechsel 0x5A84F0) in _update_sight;
	# die frühere Schätzung 8 m/6 s [E] gilt nur noch außerhalb der Originalregeln (_visibility)
	return v * light


## Waffenhaltung des Ziels (Steuerwort +0x50 Bits 0–2, 0x559360) [B Werte]. Zuordnung im Nachbau [P]: kein Gewehr in der Hand
## (Hilfsmittel, Messer, Granate, unbewaffnet) = weg; Zielen = Anschlag; sonst bereit.
static func weapon_hold(t: Soldier) -> int:
	if t.aiming:
		return WeaponHold.AIMED
	var w := t.current_weapon()
	if t.tool != "" or w == null or w.data.action in [WeaponData.Action.MELEE, WeaponData.Action.THROWN]:
		return WeaponHold.AWAY
	return WeaponHold.READY


## Gangklassen-Faktor des bewegten Ziels [B Werte, P Zuordnung MoveMode → Gangklasse]: Sprint (RUN) ×1,8; Schleichen
## (SNEAK) ×1,05; geduckt/liegend bewegt ×1,3; aufrecht Gehen/Laufschritt ×1,6.
static func orig_gait_factor(t: Soldier) -> float:
	if t.move_mode == Soldier.MoveMode.RUN and t.stance == Soldier.Stance.STAND:
		return ORIG_GAIT_SPRINT
	if t.move_mode == Soldier.MoveMode.SNEAK:
		return ORIG_GAIT_SNEAK
	if t.stance != Soldier.Stance.STAND:
		return ORIG_GAIT_CROUCH
	return ORIG_GAIT_RUN


## AP-3/AP-7: 0x570280 meldet ein sichtbares Ziel innerhalb der Reichweite sofort mit 100 – keine Erkennungsrampe [B].
## Die Verzögerung bis zum ersten Schuss entsteht im Kampfautomaten (Zustand 0/4/5, OrigCombatFsm).
func _orig_gain(_t: Soldier, _dist: float, _reach: float) -> float:
	return INF


var _mission: Node

## fix_performance: Licht am Ziel je Physikbild nur einmal berechnen (light_at läuft über alle Lampen + Suchscheinwerfer;
## alle Beobachter desselben Bildes teilen den Wert – im selben Bild bewegt sich das Ziel nicht).
static var _light_cache := {}     ## Instanz-ID des Ziels -> Licht
static var _light_frame := -1


func _light_of(t: Soldier) -> float:
	if _mission == null:
		return 1.0
	var f := Engine.get_physics_frames()
	if f != _light_frame:
		_light_frame = f
		_light_cache.clear()
	var id := t.get_instance_id()
	if _light_cache.has(id):
		return _light_cache[id]
	var l: float = _mission.light_at(t.global_position + Vector3.UP)
	_light_cache[id] = l
	return l


func _refresh_light() -> void:
	if not is_instance_valid(_mission):
		var m := Game.current_mission()
		_mission = m if m and m.has_method("light_at") else null


func _line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, target: Soldier) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var ex: Array[RID] = [soldier.get_rid()]
	if soldier.vehicle is CollisionObject3D:
		ex.append((soldier.vehicle as CollisionObject3D).get_rid())   # Besatzung sieht nicht gegen die eigene Wanne
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return false
	# Optionale Kartenvegetation verdeckt Sicht, ohne Ballistik auf Welt-Layer 1 zu blockieren.
	var mission := Game.current_mission()
	return not (mission != null and mission.has_method("foliage_blocks_sight") and mission.foliage_blocks_sight(from,to))


func _on_noise(pos: Vector3, radius: float, source: Node, team: int, kind: StringName) -> void:
	if soldier == null or not soldier.alive or source == soldier:
		return
	if team == soldier.team and kind != &"alert" and kind != &"explosion" and kind != &"gunshot":
		return   # eigene Schritte/Einschläge ignorieren
	var eff := radius * (hear_range / 60.0)
	var d := soldier.global_position.distance_to(pos)
	if d > eff:
		return
	if orig_formula:
		# hd2.exe 0x5A5430 [B]: Hörweite +0x118 als harte Grenze; Lautstärke des Ereignisses entscheidet zufällig
		# (unalarmiert: verworfen, wenn rand·0,7 > Lautstärke). Lautstärke = Geräuschradius/60 [P Zuordnung].
		if d > hear_range:
			return
		var loud := clampf(radius / 60.0, 0.0, 1.0)
		if max_awareness() < 1.0 and randf() * 0.7 > loud:
			return
	heard.emit(pos, kind, source)
	if team != soldier.team and kind != &"alert":
		if source is Soldier and d < eff * 0.5 and kind == &"gunshot":
			# Nahe Schüsse geben die Richtung des Schützen preis
			last_known[source] = (source as Soldier).global_position
			awareness[source] = maxf(awareness.get(source, 0.0), 0.6)
		suspicious.emit(pos)


func max_awareness() -> float:
	var m := 0.0
	for k in awareness:
		if is_instance_valid(k) and k.alive:
			m = maxf(m, awareness[k])
	return m


## Bestes aktuell sichtbares und erkanntes Ziel.
func best_target() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for t in visible_now:
		if not is_instance_valid(t) or not t.alive or not visible_now[t]:
			continue
		if awareness.get(t, 0.0) < 1.0:
			continue
		var d := soldier.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


## G-009/fix_performance: läuft je Physikbild – ohne Kopie der Schlüssel, nur bei Fund wird gelöscht.
func forget_dead() -> void:
	var gone: Array = []
	for k in awareness:
		if not is_instance_valid(k) or not k.alive:
			gone.append(k)
	for k in gone:
		awareness.erase(k)
		visible_now.erase(k)
		last_known.erase(k)
