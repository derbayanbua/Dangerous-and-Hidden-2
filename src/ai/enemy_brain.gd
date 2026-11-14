class_name EnemyBrain
extends AIBrain
## Gegner-KI. Zustände nach dem Vorbild der Original-Skript-API
## (HUMAN_SETMODE_Guard, Patrouillen über Wegpunkte, HUMAN_Investigate,
## HUMAN_LookAround, OnAlarm/HUMAN_MoveToAlarm, KI-Modi Aggressive/Defensive).
##
##  GUARD/PATROL --(Verdacht)--> INVESTIGATE --(Erkennung)--> COMBAT
##        ^                            |                         |
##        +-------- (nichts) ----- SEARCH <---- (Ziel verloren) -+

enum State { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH }
enum Mode { AGGRESSIVE, DEFENSIVE }

const STATE_NAMES := ["Wache", "Patrouille", "Untersucht", "Kampf", "Sucht"]

var state: int = State.GUARD
var ai_mode: int = Mode.DEFENSIVE
var stationary := false           ## verlässt den Posten nie (z. B. Wachturm, MG-Nest)
var patrol_points: PackedVector3Array = []
var patrol_index := 0
var patrol_wait := 0.0
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var alert_level := 0.0            ## 0 ruhig .. 1 alarmiert (bleibt erhöht)
var target: Soldier
var investigate_pos := Vector3.ZERO
var search_time := 0.0
var _state_time := 0.0
var _cover_pos := Vector3.INF
var _peek_timer := 0.0
var _peeking := true
var _no_los_time := 0.0
var _look_timer := 0.0
var _shout_cooldown := 0.0
var _base_sight := 55.0
var _corpse_to_check: Soldier
var _grenade_cd := 1.0
var _engaged_time := 0.0
var _flanked := false
var _flank_retry := 0.0           ## s bis zum nächsten Flankenversuch, wenn keine Flanke gefunden wurde
var flank_target := Vector3.INF   ## zuletzt gewählte Flankenposition (Debug/Test)
## Feuern in der Bewegung (auf dem Weg in Deckung/zur Flanke) bis zu dieser Entfernung.
## Treffsicherheit sinkt dabei über die Bewegungsstreuung des Soldaten (Soldier.current_spread).
var move_fire_range := 35.0

# --- Steuerung durch Original-Skripte (LsRuntime) ---
var runtime: Node                 ## LsRuntime, falls die Mission Originalskripte nutzt
var script_control := false       ## HUMAN_SETAIMODE_Zombie: nur Skript, keine eigene Taktik
var zombie_mode := false          ## B-021: Original-Modus 0x400 (Zombie): Leine min(Sicht/3; 25) m, Suche 7–12 s
var suspended := false            ## HUMAN_Suspend(true)
var script_alarm_enabled := true  ## SetAlarmType(…, true/false)
var script_stance := -1
var script_move_mode: int = Soldier.MoveMode.WALK
var script_look_at := Vector3.INF
var _script_target := Vector3.INF
var _alarm_notified := false
## HUMAN_SetWaitForPlayer: beim Führen anhalten, wenn der Spieler zurückbleibt
var wait_for_player := false
var wait_stop_dist := 12.0
var wait_resume_dist := 8.0
var _waiting_player := false

# --- Alarmarten (Original SetAlarmType(Maske, an/aus) / _GetAlarmType). Bedeutung der 10 Bits laut
# Originalskriptkommentar (BURMA2 bu2_08.scr, CZECH6 c5_r*.scr) [B]:
const AL_NEAR_SHOT := 1       ## nahe Schüsse
const AL_SHOT := 2            ## Schüsse
const AL_STEPS := 4           ## Schritte
const AL_SOUND := 8           ## Geräusche (OnUse: Türen, Schalter)
const AL_EXPLOSION := 16
const AL_SEE := 32            ## Feind gesehen
const AL_HURT := 64           ## verwundet
const AL_DEATHCRY := 128      ## Todesschrei eines Kameraden
const AL_FRIENDLY := 256      ## Beschuss durch die eigene Seite
const AL_CORPSE := 512        ## Leiche gesehen
var alarm_mask := 1023        ## SetAlarmType: welche Alarmarten OnAlarm auslösen
var events_enabled := true    ## HUMAN_SetEvents(false): keine KI-Ereignisse an das Skript (z. B. schlafende Posten)
var last_alarm_type := 0      ## _GetAlarmType: Art des Alarms, der zuletzt OnAlarm ausgelöst hat
var alarm_pos := Vector3.INF  ## Ort des letzten Alarmreizes (HUMAN_MoveToAlarm)
var _stimulus := AL_SEE
var _script_alarm_t := 0.0
## Skriptgesteuerte (Zombie-)Akteure: OnAlarmDone, wenn so lange kein neuer Alarmreiz kam (ANNAHME, Dauer nicht belegt)
const SCRIPT_ALARM_HOLD := 25.0

# --- Moral / Ergeben / Gefangennahme (hd2.exe, docs/re_notes_ai_surrender.md) ---
## Moral aus actors.bin (+0xF8, Standard 80). Ab Anfangsmoral ≥ 90 gerät der Soldat nie in Panik (Flag 1),
## ab ≥ 75 kämpft er in Panik bewaffnet weiter (Flag 2) [B 0x547A81, 0x5487DF, 0x54B955].
var morale := 80.0
var morale_initial := 80.0
var surrendered := false      ## Hände hoch (0x5A6450: KI vtable +0x100, Byte +0x2C1)
var captured := false         ## gefangen genommen (Flag 0x4000000, 0x5A6380)
var uniform_taken := false    ## Uniform abgegeben (Byte +0x1A5)
## Abstand, unter dem ein bedrängter Soldat sich ergibt statt zu fliehen: 15 m [B 0x80F620]
const SURRENDER_DIST := 15.0
var _surrender_check := 0.0
var _surrender_delay := -1.0   ## Original: Hände hoch nach 300 ms (Zustand 0x2000002, Zähler 0x12C)
var _captor: Soldier
var capture_action: Node      ## EnemyBrain.CaptureAction (Interactable am Soldaten)
var look_around := 0          ## HUMAN_LookAround(n), 0 = aus
var _look_around_t := 0.0
var _look_around_base := 0.0


func set_look_around(n: int) -> void:
	look_around = maxi(n, 0)
	_look_around_t = 0.0
	_look_around_base = soldier.look_yaw
	script_look_at = Vector3.INF


func script_move(pos: Vector3) -> void:
	# af1_finale2 [P]: Skriptweg mit allen Alarmarten gesperrt (SetAlarmType(1023, false)) beendet ein vorher (z. B. im
	# HUMAN_Suspend durch Leichen/Schüsse) begonnenes Untersuchen/Suchen – sonst übernimmt die Suche und der Soldat kehrt
	# zum Spawnposten zurück (AFRICA1-Verstärkung). Kampf (gesehener Feind) bleibt.
	if runtime != null and alarm_mask == 0 and (state == State.INVESTIGATE or state == State.SEARCH):
		set_state(State.GUARD)
	_script_move_abort_combat()
	_script_interrupted = false
	_script_target = pos
	_script_route = []
	script_look_at = Vector3.INF
	move_to(pos, script_move_mode)


func script_move_done() -> bool:
	if _script_interrupted:
		# Alarm-Skriptweg [P]: die eigene KI hat den Weg unterbrochen (Kampf/Suche). Im Original wartet der Skript-pc
		# (+0x1D8) weiter; fortgesetzt wird erst mit einer beendeten Bewegung (0x58D900) – also wenn die KI wieder ruhig
		# ist und ihr Heimweg endet. Vorher galt „kein Laufziel“ (Kampfautomat hält an) als Ankunft → das Skript gab
		# sofort den nächsten HUMAN_Move, mitten im Kampf. NUR mit `--skriptweg_warten=1` (Messung 10.11.: mehr
		# 40-s-Grenzen in ARCTIC4/CZECH6, TIRPIC_18 wartet im Kampf „Verloren“) – Standard aus.
		if (state == State.GUARD or state == State.PATROL) and not has_move_target():
			_script_interrupted = false
			return true
		return false
	var done := not has_move_target() or arrived(1.2)
	if done and not _script_route.is_empty():
		# B-033: nächster Wegpunkt der Checkpoint-Kantenfolge (LsRuntime._checkpoint_route)
		var rest := _script_route
		script_move(rest.pop_front())
		_script_route = rest
		return false
	if done and _script_target.is_finite():
		_script_target = Vector3.INF
		_script_prio = false
		if not script_control:
			# B-036c: Posten = erreichte Stelle (sonst läuft die Wache in der Delay-Pause zum Spawn zurück)
			home_pos = soldier.global_position
			home_yaw = soldier.look_yaw
	return done


## Alarm-Skriptweg (09.11.2026, docs/status/alarm_skriptweg.md): HUMAN_Move hat Vorrang vor Kampf/Suche. hd2.exe
## 0x421C00 Fall 0x1F → 0x5AF1D0 → 0x58E780: Bewegungsauftrag + Skript-pc (+0x1D8, Rückmeldung erst bei Ankunft) und,
## wenn der Gang NICHT 0x1000 ist (+0x1B0, nach Opcode-Reihenfolge Silence [P]), 0x58C400 = Kampf-/Alarmverhalten
## zurücksetzen (dieselbe Funktion ruft der Automat 0x549AE0 in Zustand 2 vor dem Heimweg) [B Ablauf, P Deutung].
## Vorher hielt OrigCombatFsm den Soldaten fest, der Weg lief in die 40-s-Grenze (ARCTIC3 squad1_4/5, sq1_p2_1/2,
## ARCTIC4 static_guard_4, NORWAY tirpic4/5/18). Nur Originalmissionen offline; `--skriptweg=0` = Stand davor.
## OnAlarmDone wird dabei NICHT gemeldet (kein Beleg, dass 0x58C400 das Skriptereignis auslöst) [P].
func script_move_override() -> bool:
	return _orig_rules() and String(Game.cli.get("skriptweg", "1")) != "0"


## Alarm-Skriptweg [E]: dieser Skriptweg hat Kampf/Suche beendet – bis zur Ankunft lenken Geräusche/Leichen/Zurufe
## nicht ab (Original: Skript-pc +0x1D8 wartet auf Ankunft; ob Hörreize den Auftrag im Original abbrechen, ist offen).
## Gesehener Feind und Treffer starten den Kampf weiterhin.
var _script_prio := false
var _script_interrupted := false   ## Skriptweg von Kampf/Suche unterbrochen (nur mit script_move_override)


func _script_move_abort_combat() -> void:
	if state != State.COMBAT and state != State.SEARCH and state != State.INVESTIGATE:
		return
	if not script_move_override() or script_move_mode == Soldier.MoveMode.SNEAK:
		return
	if Game.cli.has("debug_skriptweg"):
		print("SKRIPTWEG_ABBRUCH %s Zustand %s" % [soldier.name, state_name()])
	var notified := _alarm_notified
	_alarm_notified = false      # Zustandswechsel ohne ONALARMDONE
	set_state(_calm_state())
	_alarm_notified = notified
	_script_prio = true
	_search_limit = -1.0
	search_time = 0.0
	stop_moving()


## B-036c: HUMAN_Move läuft auch nach HUMAN_SETAIMODE_Defensive/Aggressive (script_control = false) – das Skript führt
## die Bewegung, solange die eigene KI ruhig ist (Wache/Patrouille). Vorher brach `_guard` (stop_moving am Posten) jeden
## Skriptweg sofort ab → bu1_01/al2_08 forderten denselben Weg endlos neu an.
func script_move_active() -> bool:
	return _script_target.is_finite() and (state == State.GUARD or state == State.PATROL)


## B-033: HUMAN_Move über die Checkpoint-Kanten (CheckpointJoin): Zwischenpunkte nacheinander, Ziel zuletzt.
## Jeder andere script_move verwirft eine laufende Kantenfolge.
var _script_route: Array = []


func script_route(points: Array) -> void:
	var q := points.duplicate()
	if q.is_empty():
		return
	_script_prio = false      # neuer Skriptbefehl; script_move setzt es wieder, wenn er Kampf/Suche beendet
	script_move(q.pop_front())
	_script_route = q


## HUMAN_IllFire(Ziel, ms): ms lang auf ein Ziel (Akteur oder Frame) feuern, z. B. Zielscheiben (ALPS1), Hinrichtung
## (ARCTIC3 Killer); blockiert das Skript für die Dauer
var _ill_fire_t := 0.0
var _ill_target: Node3D


func script_ill_fire(t: Node3D, seconds: float) -> void:
	_ill_target = t
	_ill_fire_t = maxf(seconds, 0.1)
	stop_moving()


func ill_fire_done() -> bool:
	return _ill_fire_t <= 0.0


func _ill_fire_tick(delta: float) -> void:
	_ill_fire_t -= delta
	soldier.move_input = Vector3.ZERO
	if not is_instance_valid(_ill_target) or _ill_fire_t <= 0.0:
		_ill_fire_t = 0.0
		cease_fire()
		return
	var p := _ill_target.global_position + (Vector3.UP * 1.2 if _ill_target is Soldier else Vector3.ZERO)
	look_at_point(p, delta, 8.0)
	soldier.aim_point = p
	soldier.has_aim_point = true
	soldier.aiming = true
	var w := soldier.current_weapon()
	if w == null:
		return
	if w.in_mag == 0 and not w.is_reloading():
		soldier.reload()
	_handle_bursts(w, facing_error(p) < 0.15, delta, distance_to(p))


func script_attack(t: Soldier) -> void:
	script_control = false
	target = t
	perception.awareness[t] = 1.0
	perception.last_known[t] = t.global_position
	set_state(State.COMBAT)


## AP-6: HUMAN_Attack/HUMAN_IllFire (gemeinsamer Handler 0x422776 → 0x58F1F0/0x58F260) [B]: Kampfauftrag am Gehirn
## (+0x1C4 Ziel-Akteur bzw. +0x1C8 Ziel-Frame, +0x1C0 = Argument 2, +0xB4 = IllFire, +0x1DC = Skript-pc für die Rückmeldung),
## Skript blockiert bis zur Rückmeldung. Argument 2 in den Originalskripten 200…60000 → Dauer in ms [P] (AFRICA3
## af3a_18: „Warnschüsse in die Luft“, HUMAN_Attack(look_alarm, 200)).
## Nachbau: Ziel = gegnerischer Soldat → Kampfautomat (OrigCombatFsm über _combat, Originalmissionen offline) mit diesem
## Ziel; Rückmeldung bei Ablauf der Dauer, Tod des Ziels oder Ende des Kampfes. Ziel = Frame/kein Gegner → feuern auf den
## Punkt für die Dauer. IllFire (+0xB4) = immer gezieltes Feuern auf Akteur/Frame ohne Automat [P]; die genaue Wirkung von
## +0xB4 im Automaten ist nicht dekodiert [offen].
## AP-6: HUMAN_SetSniper(an, n) → 0x4226B0 → 0x5AF700/0x5AE610 [B Setzer]: Gedächtnis(+0xB4).sniper = {Lage bei Aufruf
## (Frame +0x70), float(n), an/aus}. Der Leser von +0x14 ist nicht gefunden [offen]. Deutung [P]: n = Bewegungsradius in m
## um den Posten – die Originalskripte setzen nur 1/3/5/8/10 (AFRICA1/3/5), als Sichtweite unplausibel. Nachbau:
## Leine = n m um die Postenlage, kein Anmarsch/Nachrücken über die Leine hinaus, Heimweg = Posten; Sicht/Treffsicherheit
## unverändert (die frühere Annahme Sicht ≥ 120 m/Treffsicherheit +0,25 [E] entfällt). Flag 0x800 ist NICHT Sniper (blind).
var sniper_enabled := false
var sniper_post := Vector3.ZERO
var sniper_range := 0.0


func set_sniper(on: bool, range_m: float) -> void:
	sniper_enabled = on
	sniper_range = maxf(range_m, 0.0)
	if on:
		sniper_post = soldier.global_position
		home_pos = sniper_post
		home_yaw = soldier.look_yaw


var attack_left := 0.0
var attack_illfire := false
var _attack_target: Soldier


func script_attack_order(t: Node3D, seconds: float, illfire: bool) -> void:
	attack_illfire = illfire
	var s := t as Soldier
	# IllFire (Flag +0xB4) = gezieltes Feuern ohne Positionswechsel [P] (ALPS1 Zielscheiben, ARCTIC3 Hinrichtung)
	if not illfire and s and s.alive and s.team != soldier.team and s.team != Soldier.TEAM_NEUTRAL:
		_attack_target = s
		attack_left = maxf(seconds, 0.1)
		_ill_fire_t = 0.0
		script_attack(s)
		orig_fsm = null      # frischer Automat (Zustand 0) mit diesem Ziel
		return
	_attack_target = null
	attack_left = 0.0
	script_ill_fire(t, seconds)


func attack_done() -> bool:
	if _attack_target == null:
		return ill_fire_done()
	if attack_left <= 0.0 or not is_instance_valid(_attack_target) or not _attack_target.alive \
			or state != State.COMBAT or not soldier.alive:
		_attack_target = null
		attack_left = 0.0
		return true
	return false


## HUMAN_SETAIMODE_Defensive/Aggressive nach Zombie (B-020): Typisch ist OnAlarm → HUMAN_SETAIMODE_Defensive → EndScript
## (ARCTIC1 r_arc1a_walker*.scr). Die eigene KI übernimmt den anstehenden Alarm: gesehener Feind → Kampf, sonst zum Ort
## des Alarmreizes (HUMAN_MoveToAlarm-Ziel). Posten = aktuelle Stelle (der Skriptweg hat ihn verlegt). Vorher blieb der
## Soldat in „Wache“ und lief zum Spawnpunkt zurück, bis ihn ein neuer Reiz traf [E Übergabe; Original-KI nicht dekodiert].
func leave_script_control() -> void:
	if not script_control:
		return
	script_control = false
	look_around = 0
	script_look_at = Vector3.INF
	home_pos = soldier.global_position
	home_yaw = soldier.look_yaw
	if not _alarm_notified:
		return
	alert_level = 1.0
	if is_instance_valid(target) and target.alive and perception.awareness.get(target, 0.0) >= 1.0:
		perception.last_known[target] = target.global_position
		set_state(State.COMBAT)
	elif alarm_pos.is_finite():
		investigate_pos = alarm_pos
		set_state(State.SEARCH)
		_alarm_move(_leash_clamp(alarm_pos))


## Aktionsradius um den Posten (hd2.exe 0x5478C0 speichert die Startlage in KI +0x180; Radius KI +0x1A4) [B Werte]:
## Aggressiv (Flag 0x100, 0x547AD0) 100000 = unbegrenzt; Defensiv (0x200, Standard ohne Modus, 0x547AF0)
## min(Sichtweite/2, 50) m; dritter Modus (0x400, 0x547BF0) min(Sichtweite/3, 25) m. Deutung „Leine um den Posten“ [P].
## B-021: der dritte Modus 0x400 ist HUMAN_SETAIMODE_Zombie – Skriptdispatcher 0x421C00, Opcode 0xCF (Namenstabelle
## 0x835F40) → 0x4225D3 push 0x400 → 0x5AF3F0 → 0x558400 → 0x547BF0 [B]. Opcode 0xCD Aggressive = 0x100, 0xCE Defensive = 0x200.
func leash_radius() -> float:
	# nur Originalmissionen (LsRuntime); eigene Übungseinsätze und MP-Bots behalten ihr bisheriges Verhalten
	if not _orig_rules():
		return INF
	if sniper_enabled:
		return sniper_range
	var sight :=float(soldier.get_meta("orig_params", {}).get("sight_range", _base_sight))
	if zombie_mode:
		return minf(sight / 3.0, 25.0)
	if ai_mode == Mode.AGGRESSIVE:
		return INF
	return minf(sight * 0.5, 50.0)


## Original-KI-Regeln (Leine, Suchzeit, Wahrnehmungsformel, Granatbedingung) nur für Originalmissionen offline.
func _orig_rules() -> bool:
	return runtime != null and not Net.is_online


func _in_leash(p: Vector3) -> bool:
	var r := leash_radius()
	return r == INF or Vector2(p.x - home_pos.x, p.z - home_pos.z).length() <= r


## ai_orig2: Leinengebiet als Fußwegenetz-Knotenliste (Original-Liste +0x168/+0x158 [B Nutzung, P Inhalt]), je
## Posten/Leine einmal berechnet (keine Schleife je Bild). Leine unbegrenzt → leere Liste (Zweig gilt nur nicht-aggressiv).
var _leash_cache: Array = []
var _leash_key := ""


func leash_nodes(net: LsCheckpoints) -> Array:
	var r := leash_radius()
	if r == INF or net == null:
		return []
	var key := "%s|%.1f|%d" % [str(home_pos.snapped(Vector3.ONE * 0.5)), r, net.base_pos.size()]
	if key != _leash_key:
		_leash_key = key
		_leash_cache = []
		for k in net.base_pos.size():
			var p: Vector3 = net.base_pos[k]
			if Vector2(p.x - home_pos.x, p.z - home_pos.z).length() <= r and absf(p.y - home_pos.y) < 6.0:
				_leash_cache.append(k)
	return _leash_cache


## Punkt auf den Aktionsradius zurückholen
func _leash_clamp(p: Vector3) -> Vector3:
	var r := leash_radius()
	var d := Vector2(p.x - home_pos.x, p.z - home_pos.z)
	if r == INF or d.length() <= r:
		return p
	d = d.normalized() * r
	return Vector3(home_pos.x + d.x, p.y, home_pos.z + d.y)


func calm_down() -> void:
	alert_level = 0.0
	set_state(_calm_state())


func _notify_script(key: String) -> void:
	if runtime and is_instance_valid(runtime):
		runtime.notify(soldier, key)


func _script_tick(delta: float) -> void:
	if script_stance >= 0:
		soldier.stance_request = script_stance
	if script_look_at.is_finite() and not has_move_target():
		look_at_point(script_look_at + Vector3.UP * 1.5, delta, 4.0)
	elif look_around > 0 and not has_move_target():
		# HUMAN_LookAround(n): Umsehen um die aktuelle Blickrichtung (Weite nach n – ANNAHME, Stufen nicht belegt)
		_look_around_t += delta
		soldier.look_yaw = _look_around_base + sin(_look_around_t * 0.6) * minf(0.25 * look_around, 1.2)
	soldier.move_mode = script_move_mode
	if wait_for_player and has_move_target():
		var nearest := INF
		for p in get_tree().get_nodes_in_group("team_0"):
			var ps := p as Soldier
			if ps and ps != soldier and ps.alive and ps.is_player_controlled:
				nearest = minf(nearest, distance_to(ps.global_position))
		if nearest > wait_stop_dist:
			_waiting_player = true
		elif nearest < wait_resume_dist:
			_waiting_player = false
		if _waiting_player:
			soldier.move_input = Vector3.ZERO
			return
	update_movement(delta, true)
var flank_origin := Vector3.INF   ## Position bei der Flankenentscheidung
var orig_fsm: OrigCombatFsm       ## AP-3: Kampfautomat 0x549AE0 (nur Originalmissionen offline, im Kampf)
var _search_limit := -1.0


func setup(s: Soldier) -> void:
	super.setup(s)
	home_pos = s.global_position
	home_yaw = s.look_yaw
	_base_sight = perception.sight_range
	perception.target_detected.connect(_on_detected)
	perception.suspicious.connect(_on_suspicious)
	perception.heard.connect(_on_heard)
	perception.corpse_seen.connect(_on_corpse)
	Events.alarm_raised.connect(_on_alarm)
	s.damaged.connect(_on_damaged)
	s.died.connect(func(_x): OrigAudio.set_combat(self, false))
	Events.soldier_died.connect(_on_any_death)
	state = State.PATROL if patrol_points.size() > 1 else State.GUARD
	if s.team == Soldier.TEAM_AXIS and not Net.is_online:
		var ca := CaptureAction.new()
		ca.name = "CaptureAction"
		ca.brain = self
		s.add_child(ca)
		capture_action = ca


func _physics_process(delta: float) -> void:
	if not enabled or soldier == null or not soldier.alive:
		return
	if perception:
		perception.orig_formula = _orig_rules() or Perception.orig_everywhere()   # B-021; G-004 Option: Wahrnehmungsformel des Originals nur in Originalmissionen offline
	path_follow_fix = b044_fix()    # B-044: Wegfolge-Korrektur/Fortschrittswächter (AIBrain)
	if surrendered or captured:
		_surrender_tick(delta)
		return
	if suspended:
		# B-020: HUMAN_Suspend friert den Akteur ein. Vorher blieb die letzte Laufabsicht stehen – ARCTIC1 Kanisternik lief
		# als „ruhender“ Akteur geradeaus weiter, den Hang hinunter und aus der Karte.
		soldier.move_input = Vector3.ZERO
		soldier.trigger = false
		return
	_surrender_check -= delta
	if _surrender_check <= 0.0:
		_surrender_check = 0.25
		_check_surrender()
		if surrendered:
			return
	_call_cooldown = maxf(_call_cooldown - delta, 0.0)
	if _script_alarm_t > 0.0:
		_script_alarm_t -= delta
		if _script_alarm_t <= 0.0 and _alarm_notified and script_control:
			_alarm_notified = false
			_notify_script("ONALARMDONE")
	if attack_left > 0.0:
		attack_left -= delta
	if _ill_fire_t > 0.0:
		_ill_fire_tick(delta)
		return
	if soldier.mounted != null or (soldier.vehicle != null and soldier.seat_index > 0 \
			and soldier.vehicle.has_method("seat_weapon") and soldier.vehicle.seat_weapon(soldier.seat_index) != null):
		_mounted_tick(delta)
		return
	if (script_control and not _zombie_fights()) or script_move_active():
		_script_tick(delta)
		return
	# perf_gross: Tick-Staffelung nach Distanz (nur Ruhezustände Wache/Patrouille, Verhalten unverändert –
	# der Zustand bekommt die aufgelaufene Zeit). > 60 m jedes 2., > 120 m jedes 4. Bild. `--ai_lod=0` = aus.
	if (state == State.GUARD or state == State.PATROL) and _ai_lod_on:
		_lod_acc += delta
		_lod_n += 1
		if _lod_n >= _lod_every:
			_lod_n = 0
			_lod_every = _lod_interval()
		else:
			return
		delta = _lod_acc
	_lod_acc = 0.0
	_state_time += delta
	_shout_cooldown = maxf(_shout_cooldown - delta, 0.0)
	match state:
		State.GUARD: _guard(delta)
		State.PATROL: _patrol(delta)
		State.INVESTIGATE: _investigate(delta)
		State.COMBAT: _combat(delta)
		State.SEARCH: _search(delta)
	if stationary and state != State.GUARD:
		stop_moving()
	update_movement(delta, state != State.COMBAT or (orig_fsm != null and orig_fsm.face_move))


var _lod_acc := 0.0
var _lod_n := 0
var _lod_every := 1
static var _ai_lod_on: bool:
	get:
		if _ai_lod_state < 0:
			_ai_lod_state = 0 if (Game != null and String(Game.cli.get("ai_lod", "1")) == "0") else 1
		return _ai_lod_state == 1
static var _ai_lod_state := -1


## perf_gross: Takt nach Abstand zur Kamera (Spieler). Unbekannte Kamera → jedes Bild.
func _lod_interval() -> int:
	var vp := soldier.get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return 1
	var d2 := cam.global_position.distance_squared_to(soldier.global_position)
	if d2 > 14400.0:
		return 4
	if d2 > 3600.0:
		return 2
	return 1


func set_state(s: int) -> void:
	if s == state:
		return
	# Original-Skriptereignisse: OnAlarm beim Eintritt in den Kampf, OnAlarmDone bei Beruhigung
	if s == State.COMBAT:
		_script_alarm(_stimulus, target.global_position if is_instance_valid(target) else soldier.global_position)
	elif (s == State.GUARD or s == State.PATROL) and _alarm_notified:
		_alarm_notified = false
		_notify_script("ONALARMDONE")
	# Original-Missionsmusik: Action, solange mindestens ein Gegner im Kampf ist (hd2.exe 0x5832F0 -> 0x69E920)
	OrigAudio.set_combat(self, s == State.COMBAT)
	# Gegner-Rufe (speech.set Sätze „Enemy G #1–#4“, deutsche Aufnahmen 9000xxxx); Zuordnung der Ereignisse
	# zu den KI-Zuständen nach den Satznamen (speech.txt) – Auslösezeitpunkte = Annahme
	if soldier and soldier.alive:
		if s == State.INVESTIGATE and state != State.COMBAT:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_SUSPICIOUS, 4.0)
		elif (s == State.GUARD or s == State.PATROL) and state == State.INVESTIGATE:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_NOTHING, 4.0)
		elif (s == State.GUARD or s == State.PATROL) and state == State.SEARCH:
			OrigAudio.speak_event(soldier, OrigAudio.EV_E_CANCEL, 4.0)
	state = s
	if s != State.GUARD and s != State.PATROL:
		if _script_target.is_finite() and script_move_override() and String(Game.cli.get("skriptweg_warten", "0")) == "1":
			_script_interrupted = true    # Alarm-Skriptweg: Skript wartet weiter (s. script_move_done)
		_script_target = Vector3.INF    # B-036c: Skriptweg endet mit Kampf/Untersuchen/Suche
		_script_route = []
	_script_prio = false     # Alarm-Skriptweg: jeder Zustandswechsel beendet den Vorrang (_script_move_abort_combat setzt ihn danach)
	_state_time = 0.0
	_cover_pos = Vector3.INF
	_engaged_time = 0.0
	_flanked = false
	_flank_retry = 0.0
	if s != State.COMBAT:
		cease_fire()
	orig_fsm = null    # AP-3: Automat startet bei jedem Kampfeintritt neu (Zustand 0)


# --- Zustände ----------------------------------------------------------------

func _guard(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	if distance_to(home_pos) > 1.5:
		move_to(home_pos, Soldier.MoveMode.WALK)
		return
	stop_moving()
	# langsames Umsehen um die Grundrichtung (HUMAN_LookAround)
	var sweep := sin(_state_time * 0.35) * 0.6 * (1.0 + alert_level)
	soldier.look_yaw = rotate_toward(soldier.look_yaw, home_yaw + sweep, delta * 1.2)
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)


func _patrol(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	if patrol_points.is_empty():
		set_state(State.GUARD)
		return
	if patrol_wait > 0.0:
		patrol_wait -= delta
		soldier.look_yaw += sin(_state_time * 0.8) * delta * 0.5
		return
	var p := patrol_points[patrol_index]
	if distance_to(p) < 1.2 or not has_move_target():
		if distance_to(p) < 1.2:
			patrol_index = (patrol_index + 1) % patrol_points.size()
			patrol_wait = randf_range(1.5, 4.0)
			return
		move_to(p, Soldier.MoveMode.WALK)
	soldier.look_pitch = move_toward(soldier.look_pitch, 0.0, delta)


func _investigate(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	soldier.aiming = true
	if _state_time < 1.2:
		# erst hinsehen (Reaktion), dann vorsichtig hingehen
		stop_moving()
		look_at_point(investigate_pos + Vector3.UP, delta, 3.0)
		return
	var goal := _leash_clamp(investigate_pos)
	if b044_fix() and distance_to(investigate_pos) > 2.0 and not has_move_target():
		# B-044: Punkt außerhalb der Leine bzw. ohne Weg → nicht 25 s auf der Stelle „hingehen“, sondern hier umsehen [E]
		var rp := reachable_point(goal)
		if not rp.is_finite() or distance_to(rp) < 2.0:
			goal = soldier.global_position
		else:
			goal = rp
	if distance_to(investigate_pos) > 2.0 and distance_to(goal) > 2.0:
		if not (b044_fix() and has_move_target()):
			move_to(goal, Soldier.MoveMode.WALK)
	else:
		stop_moving()
		if _corpse_to_check and is_instance_valid(_corpse_to_check):
			_raise_alarm("Leiche gefunden")
			_corpse_to_check = null
		_look_timer += delta
		soldier.look_yaw += delta * 1.2
		if _look_timer > 5.0:
			_look_timer = 0.0
			set_state(State.SEARCH if alert_level > 0.5 else _calm_state())
	if _state_time > 25.0:
		set_state(_calm_state())


## Sucht eine Deckung seitlich versetzt zur Achse Gegner–Ziel (beide Seiten, zufällige Reihenfolge,
## wachsender Suchradius, je Kombination mehrere Stichprobenrunden). INF, wenn keine echte Flanke
## (mindestens 5 m seitlich) gefunden wurde.
func _find_flank(tpos: Vector3, threat_eye: Vector3) -> Vector3:
	var to_t := tpos - soldier.global_position
	to_t.y = 0.0
	var first := -1.0 if randf() < 0.5 else 1.0
	for radius: float in [8.0, 12.0, 16.0]:
		for side: float in [first, -first]:
			var perp := Vector3(-to_t.z, 0, to_t.x).normalized() * side
			var center := soldier.global_position + perp * 12.0 + to_t.normalized() * minf(to_t.length() * 0.3, 8.0)
			for _round in 2:
				var c := find_cover_around(center, threat_eye, radius)
				if c.is_finite() and absf((c - soldier.global_position).dot(perp)) > 5.0:
					return c
	return Vector3.INF


func _combat(delta: float) -> void:
	perception.forget_dead()
	# Panik (Moral < 20) ohne Standhaftigkeit und Feind ≥ 15 m: Flucht (Original-Zustand 0x4000002) [B]; Fluchtweg 25 m [E]
	if ((morale < 20.0 and morale_initial < 90.0) or not is_armed()) and not (is_armed() and morale_initial >= 75.0) \
			and is_instance_valid(target) and target.alive and distance_to(target.global_position) >= SURRENDER_DIST:
		if not has_move_target() or arrived(1.5):
			var away := soldier.global_position - target.global_position
			away.y = 0.0
			var fp := soldier.global_position + away.normalized() * 25.0
			if b044_fix():
				# abgebrochener Fluchtweg (physisch versperrt, obwohl das Netz einen Weg kennt): Ziel merken und meiden
				if _flee_goal.is_finite() and distance_to(_flee_goal) > 3.0:
					_flee_bad.append(_flee_goal)
					if _flee_bad.size() > 8:
						_flee_bad.pop_front()
				fp = _flee_point(away.normalized())
				_flee_goal = fp
			if fp.is_finite():
				move_to(fp, Soldier.MoveMode.RUN)
			else:
				soldier.stance_request = Soldier.Stance.CROUCH    # kein erreichbarer Fluchtpunkt: ducken [E]
		cease_fire()
		return
	var visible := perception.best_target()
	if visible:
		target = visible
		_no_los_time = 0.0
	else:
		_no_los_time += delta
	if (target == null or not target.alive) and not (orig_fsm != null and _orig_rules()):
		target = null
		set_state(State.SEARCH)
		return
	if target == null or not target.alive:
		_orig_fsm_tick(delta)    # AP-3: Ziel tot/verloren – der Automat entscheidet (Zustand 8 → neues Ziel bzw. 2)
		return
	var tpos: Vector3 = perception.last_known.get(target, target.global_position)
	var threat_eye := tpos + Vector3.UP * 1.5
	# Kampfrufe: „Get Him! / He's Here!“ (Ereignis 119) bei Sicht, unbewaffnet „I Don't Have A Gun“ (114);
	# Abstand 8–14 s je Sprecher = Annahme
	if visible and _state_time > 2.0:
		var armed := soldier.current_weapon() != null and soldier.current_weapon().data.action != WeaponData.Action.MELEE
		OrigAudio.speak_event(soldier, OrigAudio.EV_E_ATTACK if armed else OrigAudio.EV_E_NO_WEAPON, randf_range(8.0, 14.0))

	# Granate: Ziel hält sich hinter Deckung auf (Original: ATTACK_THROW_GRENADE).
	# Vor der Deckungslogik, damit auch auf dem Weg in Deckung geworfen wird.
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	var tdist := distance_to(tpos)
	# B-021 Originalmissionen: hd2.exe 0x552200 erlaubt den Wurf erst ab 20 m und nur bei fast gleicher Höhe
	# (|Δy|/Abstand < sin 10° = 0,1736) [B]; Obergrenze 32 m und Abklingzeit bleiben [E].
	var min_gren := 20.0 if _orig_rules() else 8.0
	var level_ok := not _orig_rules() or absf(tpos.y - soldier.global_position.y) < 0.1736 * maxf(tdist, 0.1)
	var gren_ok := _no_los_time > 2.0
	if _orig_rules() and OrigCombatFsm.ai_orig2():
		gren_ok = false
		if _grenade_cd <= 0.0:
			if tdist < min_gren or tdist >= 32.0:
				if _gren_check <= 0.0:
					_gren_block("abstand")
					_gren_check = 0.5
				_gren_check -= delta
			elif not level_ok:
				if _gren_check <= 0.0:
					_gren_block("neigung")
					_gren_check = 0.5
				_gren_check -= delta
			else:
				gren_ok = _orig_grenade_ok(tpos, delta)
	if gren_ok and _grenade_cd <= 0.0 and tdist > min_gren and tdist < 32.0 and level_ok and not stationary:
		_grenade_cd = randf_range(12.0, 20.0)
		if throw_grenade_at(tpos):
			stop_moving()
			_cover_pos = Vector3.INF   # danach neue Deckung wählen
			return
		_gren_block("wurf_fehl")

	# AP-3: Originalmissionen offline → Kampfautomat hd2.exe 0x549AE0 (OrigCombatFsm) statt eigener Deckungs-/Flankenlogik.
	# AP-48f (0.10.1): auch Stellungsposten (stationary, im Original unbekannt) laufen über den Automaten, ohne Ortswechsel
	# (OrigCombatFsm.hold_post); `--b048f=0` = alte Herausschau-Logik.
	if _orig_rules() and (not stationary or String(Game.cli.get("b048f", "1")) != "0"):
		_orig_fsm_tick(delta)
		return
	if stationary:
		_cover_pos = soldier.global_position
	# Deckung suchen (einmalig bzw. wenn Deckung verloren)
	if _cover_pos == Vector3.INF and _state_time > 0.2:
		var bias := 0.6 if ai_mode == Mode.AGGRESSIVE else 0.0
		_cover_pos = find_cover(threat_eye, 14.0 if ai_mode == Mode.AGGRESSIVE else 9.0, bias)
		if _cover_pos.is_finite() and _in_leash(_cover_pos):
			move_to(_cover_pos, Soldier.MoveMode.RUN)
		else:
			_cover_pos = soldier.global_position   # keine Deckung: vor Ort hinknien
	var in_cover := _cover_pos.is_finite() and distance_to(_cover_pos) < 1.5
	if not in_cover and has_move_target():
		# auf dem Weg in Deckung bzw. zur Flanke: im Laufen weiterfeuern (Niederhalten),
		# solange das Ziel sichtbar und in Reichweite ist
		soldier.stance_request = Soldier.Stance.STAND
		if visible and distance_to(target.global_position) < move_fire_range:
			# aus der Hüfte im Laufschritt: Zielen würde das Rennen auf Gehen ×0,6 bremsen
			# (Soldier._update_movement), Sprinten erlaubt kein Feuern -> JOG, ungenauer (spread_hip)
			soldier.move_mode = Soldier.MoveMode.JOG
			engage(target, delta)
			soldier.aiming = false
		else:
			soldier.move_mode = Soldier.MoveMode.RUN
			cease_fire()
			_turn_towards_dir((agent.get_next_path_position() - soldier.global_position).normalized(), delta, 8.0)
		return
	stop_moving()

	# Flankieren (nur aggressiv): nach längerem Feuergefecht seitlich versetzt
	# neue Deckung suchen, um das Ziel aus einem anderen Winkel zu fassen
	_engaged_time += delta
	_flank_retry = maxf(_flank_retry - delta, 0.0)
	if ai_mode == Mode.AGGRESSIVE and not stationary and not _flanked and _engaged_time > 8.0 and _flank_retry <= 0.0:
		var flank := _find_flank(tpos, threat_eye)
		if flank.is_finite() and _in_leash(flank):
			_flanked = true
			_cover_pos = flank
			flank_target = flank
			flank_origin = soldier.global_position
			move_to(flank, Soldier.MoveMode.RUN)
			return
		# keine Flanke gefunden: nicht aufgeben, nach kurzer Zeit erneut suchen
		# (Stichproben sind zufällig, Lage/Ziel können sich ändern)
		_flank_retry = 2.0

	# Herausschauen und Feuern im Wechsel mit Abducken
	_peek_timer -= delta
	if _peek_timer <= 0.0:
		_peeking = not _peeking
		_peek_timer = randf_range(1.8, 3.5) if _peeking else randf_range(1.0, 2.2)
	if _peeking or not visible:
		soldier.stance_request = Soldier.Stance.CROUCH if _crouch_has_los(threat_eye) else Soldier.Stance.STAND
		if visible:
			engage(target, delta)
		else:
			cease_fire()
			look_at_point(threat_eye, delta, 4.0)
	else:
		soldier.stance_request = Soldier.Stance.CROUCH
		cease_fire()
		var w := soldier.current_weapon()
		if w and w.in_mag < w.data.magazine_size * 0.4:
			soldier.reload()

	# Ziel länger nicht sichtbar
	if _no_los_time > 6.0:
		if ai_mode == Mode.AGGRESSIVE:
			investigate_pos = tpos
			set_state(State.SEARCH)
		elif _no_los_time > 14.0:
			set_state(State.SEARCH)


## ai_orig2 (08.11.2026): Granatbedingung 0x552200 vollständig dekodiert [B] (≥ 20 m und Neigung < sin 10° prüft _combat):
##  - Automatenzustand (+0xA8, virtuell +0x10) NICHT 0/2/6/7/9 (Eröffnen, Verloren, Wechsel wählen, Laufen, Nachrücken);
##  - 0x5AE890: kein Eintrag der Liste +0x7C näher als 2 m (d² < 4) an der eigenen Lage – Liste = eigene Leute [P];
##  - Ziel ist der vom Spieler gesteuerte Mensch (0x5AC4C0 == Spiel+0x18 → +0x1F8);
##  - 0x552190: Strahl von eigener Lage + 0,5 m waagrecht zum Ziel + 0,15 m hoch zum Zielpunkt (+0x260 = Kopf [P]) über
##    0x6F7C90(…, 3) – Wurf nur bei Ergebnis 0 (= frei [P]). Die alte Nachbaubedingung „Ziel ≥ 2 s unsichtbar“ [E] entfällt.
## Takt: höchstens alle 0,5 s geprüft [E] (ein Strahl, keine Pro-Bild-Kosten).
var _gren_check := 0.0
var grenade_checks := 0          ## Zähler (Test/Messung)


func _orig_grenade_ok(tpos: Vector3, delta: float) -> bool:
	_gren_check -= delta
	if _gren_check > 0.0:
		return false
	_gren_check = 0.5
	var gw: Weapon = soldier.weapons[WeaponData.Slot.GRENADE] if soldier.weapons.size() > WeaponData.Slot.GRENADE else null
	if gw == null or gw.total_ammo() <= 0:
		return _gren_block("keine_granate")
	if orig_fsm == null or orig_fsm.state in [OrigCombatFsm.S_OPEN, OrigCombatFsm.S_LOST, OrigCombatFsm.S_CHOOSE,
			OrigCombatFsm.S_MOVE, OrigCombatFsm.S_ADVANCE]:
		return _gren_block("zustand")
	if not (is_instance_valid(target) and target.is_player_controlled):
		return _gren_block("kein_spieler")
	var me := soldier.global_position
	if not _friends_near(me, 2.0).is_empty():
		return _gren_block("eigener_2m")
	grenade_checks += 1
	var flat := tpos - me
	flat.y = 0.0
	var from := me + (flat.normalized() * 0.5 if flat.length() > 0.01 else Vector3.ZERO) + Vector3.UP * 0.15
	var q := PhysicsRayQueryParameters3D.create(from, tpos + Vector3.UP * 1.6, 1)
	if not soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return _gren_block("strahl")
	return true


## Messung: Gründe, aus denen 0x552200 den Wurf verweigert (Test/Sonde)
var gren_blocks := {}


func _gren_block(why: String) -> bool:
	gren_blocks[why] = int(gren_blocks.get(why, 0)) + 1
	return false


func _friends_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s != soldier and s.alive and s.team == soldier.team and s.global_position.distance_squared_to(p) < r * r:
			out.append(s)
	return out


## AP-3: ein Schritt des Kampfautomaten 0x549AE0; Zustand 12 abgelaufen („Suche beendet“) → Ruhezustand.
func _orig_fsm_tick(delta: float) -> void:
	if orig_fsm == null:
		orig_fsm = OrigCombatFsm.new(self)
		orig_fsm.start(target if is_instance_valid(target) and target.alive else null)
		if not (is_instance_valid(target) and target.alive):
			orig_fsm.start_search(investigate_pos if investigate_pos != Vector3.ZERO else soldier.global_position)
	if not orig_fsm.tick(delta):
		orig_fsm = null
		target = null
		set_state(_calm_state())


func _search(delta: float) -> void:
	soldier.stance_request = Soldier.Stance.STAND
	soldier.aiming = true
	search_time += delta
	if not has_move_target() or arrived(1.5):
		_look_timer += delta
		soldier.look_yaw += delta * 1.5
		if _look_timer > 3.0:
			_look_timer = 0.0
			# zufälliger Punkt um die letzte bekannte Position (HUMAN_MoveRandomRadius)
			var p := investigate_pos + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			if b044_fix():
				p = _search_point()
				if p.is_finite():
					move_to(p, Soldier.MoveMode.WALK)
			else:
				move_to(_leash_clamp(p), Soldier.MoveMode.WALK)
	# Suchdauer: Originalmissionen defensiv 20–30 s (KI +0x194 = rand·10 + 20, 0x547AF0), Zombie 7–12 s
	# (rand·5 + 7, 0x547BF0) [B Wert, P Deutung], sonst 40 s
	if _search_limit < 0.0:
		if _orig_rules() and zombie_mode:
			_search_limit = randf_range(7.0, 12.0)
		else:
			_search_limit = randf_range(20.0, 30.0) if leash_radius() != INF else 40.0
	if _state_time > _search_limit:
		_search_limit = -1.0
		search_time = 0.0
		set_state(_calm_state())


## B-044: Korrekturen gegen Stillstand (nur Originalmissionen offline; `--b044=0` = Stand davor, Messvergleich).
static func b044_switch() -> bool:
	return String(Game.cli.get("b044", "1")) != "0"


## AF1-Verteidiger (0.10.3): Zombie (0x400) kämpft/sucht selbst, sobald er im Kampf bzw. in der Suche danach ist.
func _zombie_fights() -> bool:
	return zombie_mode and (state == State.COMBAT or state == State.SEARCH) and hear_alarm_fix()


## AF1-Verteidiger (0.10.3): gehörter Schuss bleibt Alarm (Suche) statt „Untersucht“; `--af1def=0` = Stand davor.
func hear_alarm_fix() -> bool:
	return _orig_rules() and String(Game.cli.get("af1def", "1")) != "0"


func b044_fix() -> bool:
	return _orig_rules() and b044_switch()


## Punkt aufs Navigationsnetz holen und nur zurückgeben, wenn ein Weg von hier aus hinführt (Pfadende < 2,5 m), sonst INF.
## Netz noch nicht fertig: Punkt unverändert.
func reachable_point(p: Vector3) -> Vector3:
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	var q := NavigationServer3D.map_get_closest_point(map, p)
	if Vector2(q.x - p.x, q.z - p.z).length() > 4.0:
		return Vector3.INF
	var path := AIBrain.nav_path(map, soldier.global_position, q)   # B-010c
	if path.is_empty() or path[path.size() - 1].distance_to(q) > 2.5:
		return Vector3.INF
	return q


## Flucht (Panik 0x4000002): statt eines festen Punkts 25 m vom Feind weg (lag oft hinter Mauern/außerhalb des Netzes →
## Soldat lief auf der Stelle) den ersten erreichbaren Punkt im Fächer ±90° um die Fluchtrichtung, 25 bzw. 15 m [E].
func _flee_point(away: Vector3) -> Vector3:
	if away.length() < 0.1:
		away = -soldier.aim_direction()
		away.y = 0.0
	for r: float in [25.0, 15.0, 8.0]:
		for a: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.57, -1.57, 2.2, -2.2]:
			var p := reachable_point(soldier.global_position + away.normalized().rotated(Vector3.UP, a) * r)
			if not p.is_finite() or distance_to(p) <= 4.0:
				continue
			var bad := false
			for q in _flee_bad:
				if (q as Vector3).distance_to(p) < 6.0:
					bad = true
					break
			if not bad:
				return p
	_flee_bad.clear()     # alles versucht: von vorn
	return Vector3.INF


var _flee_goal := Vector3.INF
var _flee_bad: Array = []


## Suche (Zustand „Sucht“): Zufallspunkt um den Suchort; nur erreichbare Punkte, die nicht schon hier liegen (vorher lag der
## an die Leine geklemmte Punkt oft auf der eigenen Stelle bzw. hinter einer Netzinsel → Soldat stand 15–40 s). Sonst
## Zufallspunkt im Leinengebiet um den Posten (wie 0x557D10 „Wegpunkt im Leinengebiet“ [B Ablauf, E Auswahl]).
func _search_point() -> Vector3:
	for k in 9:
		var c := investigate_pos if k < 4 else (home_pos if k < 6 else soldier.global_position)
		var rad := 10.0 if k < 4 else (minf(leash_radius(), 15.0) if k < 6 else 6.0)
		var p := reachable_point(_leash_clamp(c + Vector3(randf_range(-rad, rad), 0, randf_range(-rad, rad))))
		if p.is_finite() and distance_to(p) > 2.5:
			return p
	return Vector3.INF


## Alarm/Geräusch: zum (an die Leine geklemmten) Ort rennen. B-044: ohne Weg dorthin (Netzinsel, Leuchtturmspitze …) nicht
## loslaufen – die Suche wählt dann erreichbare Punkte (_search_point) [E].
func _alarm_move(p: Vector3) -> void:
	if b044_fix():
		var rp := reachable_point(p)
		if not rp.is_finite():
			stop_moving()
			return
		p = rp
	move_to(p, Soldier.MoveMode.RUN)


func _calm_state() -> int:
	return State.PATROL if patrol_points.size() > 1 else State.GUARD


func _crouch_has_los(threat_eye: Vector3) -> bool:
	var from := soldier.global_position + Vector3.UP * 1.05
	var q := PhysicsRayQueryParameters3D.create(from, threat_eye, 1)
	return soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Reaktionen --------------------------------------------------------------

## Alarmreiz an das Originalskript: OnAlarm nur, wenn die Art per SetAlarmType erlaubt ist; _GetAlarmType
## liefert danach diese Art, HUMAN_MoveToAlarm läuft zum Ort des Reizes.
func _script_alarm(type: int, pos: Vector3) -> void:
	if surrendered or captured:
		return
	alarm_pos = pos
	if not script_alarm_enabled or not events_enabled or (alarm_mask & type) == 0:
		return
	_script_alarm_t = SCRIPT_ALARM_HOLD
	if _alarm_notified:
		return
	last_alarm_type = type
	_alarm_notified = true
	if Game.cli.has("debug_alarm"):
		print("ALARM %s Art %d bei %s" % [soldier.name, type, pos])
		print_stack()
	_notify_script("ONALARM")


func _on_detected(t: Soldier) -> void:
	if not soldier.alive or suspended or surrendered or captured:
		return
	if script_control:
		# Zombie-Modus: das Skript entscheidet (OnAlarm), die KI greift nicht selbst ein
		target = t
		_script_alarm(AL_SEE, t.global_position)
		if not (zombie_mode and hear_alarm_fix()):
			return
		# AF1-Verteidiger (0.10.3): Modus 0x400 ist im Original ein KI-Modus mit eigener Leine min(Sicht/3; 25) m und
		# Suchzeit 7–12 s (0x547BF0 [B]) – also mit Kampf/Suche. Skriptkommentar af1_09.scr Z. 79 zum Zombie-Aufruf:
		# „sollte Defensive sein, darf sich aber nicht bewegen“ [B]. Gesehener Feind/Treffer → eigener Kampf in der
		# kleinen Leine; Bewegungen im Ruhezustand bleiben beim Skript.
		_stimulus = AL_SEE
		if state != State.COMBAT:
			set_state(State.COMBAT)
			alert_level = 1.0
			_shout(t.global_position)
		return
	target = t
	_stimulus = AL_SEE
	if state != State.COMBAT:
		set_state(State.COMBAT)
		alert_level = 1.0
		perception.sight_range = maxf(_base_sight, 120.0)
		_shout(t.global_position)


func _on_suspicious(pos: Vector3) -> void:
	if state == State.COMBAT or not soldier.alive or suspended or script_control:
		return
	# af1_finale2 [P]: Skriptweg mit SetAlarmType(1023, false) (AFRICA1-Verstärkung af1_posily_NN.scr „all off“ bis zur
	# Stellung) – Geräusche lenken nicht ab; vorher → Untersuchen/Suche → zurück zum Spawnposten, Wellen kamen nie an
	if _script_deaf(0):
		return
	# AF1-Verteidiger (0.10.3): Perception._on_noise sendet nach `heard` noch `suspicious` – das stufte den eben über
	# _on_heard alarmierten Soldaten (Suche, rennt zum Schuss) jedes Mal auf „Untersucht“ zurück und setzte dessen
	# 1,2-s-Hinsehphase neu: unter Dauerfeuer blieb er stehen. Original 0x5A5430 [B]: ein Geräusch erzeugt genau einen
	# Alarmeintrag je (Art, Quelle) in der Liste +0x2AC, wiederholte Reize frischen nur Ort/Zeit auf (kein Herabstufen).
	if state == State.SEARCH and hear_alarm_fix():
		return
	investigate_pos = pos
	alert_level = maxf(alert_level, 0.4)
	if state != State.INVESTIGATE:
		set_state(State.INVESTIGATE)


## Geräuschart -> Original-Alarmart (Zuordnung nach den Kommentar-Bezeichnungen; „alert“ = Zuruf eines
## Kameraden mit Feindsicht -> 32 und Schüsse unter 15 m -> 1 sind ANNAHMEN)
func _alarm_type_of(kind: StringName, pos: Vector3, source: Node) -> int:
	match kind:
		&"gunshot", &"impact":
			if source is Soldier and (source as Soldier).team == soldier.team:
				return 0
			return AL_NEAR_SHOT if distance_to(pos) < 15.0 else AL_SHOT
		&"explosion":
			return AL_EXPLOSION
		&"step", &"climb", &"engine":
			return AL_STEPS
		&"door", &"voice", &"melee", &"bark":
			return AL_SOUND
		&"alert":
			return AL_SEE
	return 0


func _on_heard(pos: Vector3, kind: StringName, source: Node) -> void:
	if not soldier.alive or state == State.COMBAT or suspended or surrendered or captured:
		return
	var at := _alarm_type_of(kind, pos, source)
	if _script_deaf(at):
		return      # af1_finale2: Alarmart gesperrt, Skriptweg läuft (s. _script_deaf; Art 0 = eigene Schüsse → nur bei Maske 0)
	if at != 0 and (at != AL_STEPS or (source is Soldier and (source as Soldier).team != soldier.team)):
		_stimulus = at
		if script_control:
			investigate_pos = pos
			_script_alarm(at, pos)
		else:
			alarm_pos = pos
			# AF1-Verteidiger (0.10.3): OnAlarm hängt im Original nicht am KI-Modus – die Alarmsetzer des Gehirns
			# (0x5902D0 Geräusch 2/4/8/16, 0x5900E0 Art 1; docs/status/b036b.md) melden jedem Akteur mit erlaubter Art.
			# Vorher bekamen Defensive/Aggressive nur beim Kampfeintritt (Sicht) ein OnAlarm; AF1-Skripte setzen dort
			# Sichtweite 300, rennen zum Alarmpunkt (af1_01 „AF1_01_alert“) und drehen sich zum Spieler.
			if hear_alarm_fix():
				_script_alarm(at, pos)
	if script_control:
		return
	if kind == &"alert":
		# Kamerad meldet Feindkontakt: dorthin, kampfbereit
		investigate_pos = pos
		alert_level = 1.0
		set_state(State.SEARCH)
		_alarm_move(_leash_clamp(pos))
	elif kind == &"gunshot" or kind == &"explosion" or kind == &"impact":
		alert_level = 1.0
		if hear_alarm_fix() and state == State.SEARCH:
			# 0x5A5430 [B]: derselbe Reiz frischt den Alarmeintrag auf (Ort, timeGetTime) → Suchzeit neu [P], kein neuer
			# Weg je Schuss (vorher alle 0,1–0,3 s neu geplant); neuer Weg nur bei deutlich anderem Ort oder ohne Ziel.
			_state_time = 0.0
			if investigate_pos.distance_to(pos) < 5.0 and has_move_target():
				return
		investigate_pos = pos
		set_state(State.SEARCH)
		_alarm_move(_leash_clamp(pos))


## af1_finale2 [P]: Skriptweg (HUMAN_Move, KI ruhig) mit per SetAlarmType gesperrter Alarmart (0 = alle gesperrt) –
## Geräusch/Leiche/Zuruf lenken nicht ab. AFRICA1-Verstärkung af1_posily_NN.scr läuft mit SetAlarmType(1023, false)
## („all off“) zur Stellung und schaltet erst dort 511 ein; vorher → Untersuchen/Suche → zurück zum Spawnposten.
## Gesehene Feinde (_on_detected) und Treffer wirken weiter.
func _script_deaf(type: int) -> bool:
	if not script_move_active() or runtime == null:
		return false
	if _script_prio and has_move_target():
		return true     # Alarm-Skriptweg [E]: der Weg, der Kampf/Suche beendet hat, läuft bis zur Ankunft (nur Sicht/Treffer)
	return alarm_mask == 0 if type == 0 else (alarm_mask & type) == 0


func _on_corpse(c: Soldier) -> void:
	if surrendered or captured:
		return
	if _script_deaf(AL_CORPSE):
		return
	_stimulus = AL_CORPSE
	if script_control:
		_script_alarm(AL_CORPSE, c.global_position)
		return
	alarm_pos = c.global_position
	if state == State.COMBAT:
		return
	_corpse_to_check = c
	investigate_pos = c.global_position
	alert_level = 1.0
	set_state(State.INVESTIGATE)


func _on_damaged(_amount: float, _zone: StringName) -> void:
	if not soldier.alive:
		return
	var a := soldier.last_attacker as Soldier
	if surrendered and not captured:
		# Original: Beschuss eines Ergebenen (Ereignis 0x40000010/15) -> Flucht bzw. Gegenwehr [P 0x54B820]
		_end_surrender(a)
		return
	if captured:
		return
	# Original 0x5484B0: aggressiv (0x100) und Gesundheit < 50 % (0x5A5FF0 = Gesundheit·100/Höchstwert) → defensiv (0x200) [B]
	if ai_mode == Mode.AGGRESSIVE and runtime != null and not Net.is_online \
			and soldier.health * 100.0 / maxf(soldier.max_health, 0.001) < 50.0:
		ai_mode = Mode.DEFENSIVE
	if a and is_instance_valid(a):
		var same := a.team == soldier.team
		_stimulus = AL_FRIENDLY if same else AL_HURT
		if script_control:
			_script_alarm(_stimulus, a.global_position)
		if same:
			return
		perception.awareness[a] = 1.0
		perception.last_known[a] = a.global_position
		_on_detected(a)
		# K11 (B-048, 0.10.1) [P]: Treffer → Alarm → Automat ab Zustand 0 neu (4/5), wenn er gerade heimkehrt/ruht/sucht
		if orig_fsm != null and _orig_rules():
			orig_fsm.on_hit(a)


func _on_alarm(pos: Vector3, _by: Node) -> void:
	if not soldier.alive or state == State.COMBAT or surrendered or captured:
		return
	if script_control:
		_script_alarm(AL_SHOT, pos)
		_notify_script("ONGLOBALALARM")
		return
	_notify_script("ONGLOBALALARM")
	if _script_deaf(AL_SHOT):
		return
	# Original: OnAlarm -> Sichtweite 300, rennen
	alert_level = 1.0
	perception.sight_range = maxf(_base_sight, 150.0)
	investigate_pos = pos
	set_state(State.SEARCH)
	_alarm_move(_leash_clamp(pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))))


func _shout(pos: Vector3) -> void:
	if _shout_cooldown > 0.0:
		return
	_shout_cooldown = 6.0
	OrigAudio.speak_event(soldier, OrigAudio.EV_E_SEE, 3.0)    # „I See Him / Enemy!“ (speech.set 121)
	Events.emit_noise(soldier.global_position, 35.0, soldier, soldier.team, &"alert")
	# Feindkontakt im Gefecht löst nach kurzer Zeit den Gesamtalarm aus
	get_tree().create_timer(6.0, false).timeout.connect(_alarm_if_still_fighting)


## Gegner hat sein Ziel getötet: Ruf „I Got Him / He's Dead“ (speech.set Ereignis 118)
func _on_any_death(s: Node, attacker: Node) -> void:
	if attacker == soldier and s != soldier and soldier.alive:
		OrigAudio.speak_event(soldier, OrigAudio.EV_E_KILLED, 3.0)
	# Todesschrei eines Kameraden in Hörweite (Alarmart 128); die Moral bleibt unverändert (Original, re_notes_ai §1)
	if s is Soldier and s != soldier and soldier.alive and (s as Soldier).team == soldier.team:
		var d := distance_to((s as Soldier).global_position)
		if d < perception.hear_range * 0.5 and not surrendered and not captured:
			_stimulus = AL_DEATHCRY
			if script_control:
				_script_alarm(AL_DEATHCRY, (s as Soldier).global_position)


func _alarm_if_still_fighting() -> void:
	if soldier.alive and state == State.COMBAT:
		_raise_alarm("Feindkontakt")


## Leichenfund/Feindkontakt. Übungseinsätze/MP: mission.raise_alarm → kartenweite Kaskade [E].
## Originalmissionen offline (B-031): mission.raise_alarm zählt nur und ruft local_alarm dieses Soldaten auf.
func _raise_alarm(_reason: String) -> void:
	var m := Game.current_mission()
	if m and m.has_method("raise_alarm"):
		m.raise_alarm(soldier.global_position, soldier)


## B-031 (GAP_REA §2): Alarm nur für diesen Akteur – über Skript (HUMAN_SetAlarm) oder eigenen Leichenfund/Kampf.
## Andere Gegner erfahren davon nur über ihr eigenes Gehör: Zuruf mit Lautstärke 1 (Radius 60 → wirksam = Hörweite
## des Hörers, Perception._on_noise; Plan „Hörweite des Hörers“ [P]) bzw. über die Schüsse. Keine Rundmeldung [B 0x549AE0].
func local_alarm(pos: Vector3) -> void:
	if not soldier.alive or surrendered or captured:
		return
	alarm_pos = pos
	alert_level = 1.0
	if script_control:
		_script_alarm(AL_SHOT, pos)    # wie bisher beim Skript-Alarm (Art 2) [E]
	elif state != State.COMBAT and state != State.SEARCH and not _script_deaf(AL_SHOT):
		perception.sight_range = maxf(_base_sight, 150.0)
		investigate_pos = pos
		set_state(State.SEARCH)
		_alarm_move(_leash_clamp(pos))
	if _call_cooldown <= 0.0:
		_call_cooldown = CALL_OUT_COOLDOWN
		Events.emit_noise(soldier.global_position, 60.0, soldier, soldier.team, &"alert")


const CALL_OUT_COOLDOWN := 6.0
var _call_cooldown := 0.0


func state_name() -> String:
	if captured:
		return "Gefangen"
	if surrendered:
		return "Ergeben"
	return STATE_NAMES[state]


# --- Ergeben / Gefangennahme ------------------------------------------------------
# Original (hd2.exe, docs/re_notes_ai.md §1): Panik bei Moral < 20 (außer Anfangsmoral ≥ 90) oder ohne Waffe
# [B 0x5487DF]; in Panik mit sichtbarem Feind: bewaffnet und Anfangsmoral ≥ 75 -> weiterkämpfen, sonst Feind unter 15 m
# -> ergeben (Hände hoch nach 300 ms), sonst fliehen [B 0x54B955–0x54B9D6]. Gefangennehmen (T7038) nur bei Ergebenen,
# „Uniform benutzen“ (T7044) nur bei lebenden Gefangenen – an Leichen ist der Eintrag grau [B 0x4BF670 Fall 3].
# ANNAHME (Auslöser im Spiel): Wird ein ahnungsloser Soldat (nicht im Kampf) aus höchstens 15 m mit einer Schusswaffe
# anvisiert, sinkt seine Moral schlagartig um 70 (Überraschung) – er gerät in Panik und ergibt sich.

## Spieler-/Truppsoldat, der diesen Soldaten aus höchstens 15 m mit einer Schusswaffe anvisiert (Sichtlinie)
func _threat_aiming() -> Soldier:
	var chest := soldier.global_position + Vector3.UP * 1.1
	for n in get_tree().get_nodes_in_group("team_%d" % Soldier.TEAM_ALLIED):
		var t := n as Soldier
		if t == null or not t.alive or t.vehicle != null or t.disguised:
			continue
		var d := t.global_position.distance_to(soldier.global_position)
		if d > SURRENDER_DIST:
			continue
		var w := t.current_weapon()
		if w == null or w.data.action in [WeaponData.Action.MELEE, WeaponData.Action.THROWN]:
			continue
		if not t.aiming:
			continue
		var to := chest - t.eye_position()
		if t.aim_direction().angle_to(to) > deg_to_rad(maxf(10.0, rad_to_deg(atan2(0.6, maxf(d, 0.5))))):
			continue
		var q := PhysicsRayQueryParameters3D.create(t.eye_position(), chest, 1)
		if not soldier.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		return t
	return null


func is_armed() -> bool:
	for w in soldier.weapons:
		if w and w.data.action not in [WeaponData.Action.MELEE, WeaponData.Action.THROWN] and w.total_ammo() > 0:
			return true
	return false


func _check_surrender() -> void:
	if soldier.team != Soldier.TEAM_AXIS or soldier.vehicle != null or soldier.mounted != null or Net.is_online:
		return
	if _surrender_delay >= 0.0:
		return
	# Original (re_notes_ai §1, Nachtrag 23.10.2026): die Moral ändert sich im Einsatz nicht (einzige Schreibzugriffe
	# auf Mensch +0xF8: Laden/Schwierigkeit 0x59EA90/0x59EDC0 und +100 über 0x5A64F0 aus 0x547D80) [B]. Panik daher nur
	# bei Moral < 20 ohne Flag 1 oder ohne Waffe (0x548610/0x54B730); in Panik mit gesehenem Feind: bewaffnet + Flag 2
	# -> kämpfen, sonst nächster Feind < 15 m -> ergeben, sonst Flucht (_combat) [B 0x54B8F0]. Die früheren Annahmen
	# (Anvisieren −70, Verwundung, Kameradentod) sind entfernt.
	var panic := (morale < 20.0 and morale_initial < 90.0) or not is_armed()
	if not panic:
		return
	if is_armed() and morale_initial >= 75.0:
		return     # Original: bewaffnet und standhaft -> kämpft weiter (Zustand 0x8000001)
	var t := perception.best_target()
	if t == null or t.team != Soldier.TEAM_ALLIED or distance_to(t.global_position) >= SURRENDER_DIST:
		return
	_captor = t
	_surrender_delay = 0.3
	cease_fire()
	stop_moving()


## Zustand „ergeben“/„gefangen“: steht mit erhobenen Händen (gefangen: kniet) und tut nichts
func _surrender_tick(delta: float) -> void:
	soldier.trigger = false
	soldier.aiming = false
	soldier.move_input = Vector3.ZERO
	_move_target = Vector3.INF
	soldier.stance_request = Soldier.Stance.CROUCH if captured else Soldier.Stance.STAND
	if is_instance_valid(_captor) and not captured:
		look_at_point(_captor.eye_position(), delta, 3.0)


func _process(delta: float) -> void:
	if _surrender_delay < 0.0 or soldier == null:
		return
	_surrender_delay -= delta
	if _surrender_delay < 0.0 and soldier.alive and not surrendered:
		surrender(_captor)


## Hände hoch: kein Ziel mehr für die KI des Trupps (neutral), Skript ruht bis zum Tod
func surrender(by: Soldier = null) -> void:
	if surrendered or not soldier.alive:
		return
	surrendered = true
	_surrender_delay = -1.0
	_captor = by
	cease_fire()
	stop_moving()
	OrigAudio.set_combat(self, false)
	soldier.set_meta("hands_up", true)
	if soldier.model and soldier.model.has_method("set_hands_up"):
		soldier.model.set_hands_up(true)
	_set_team(Soldier.TEAM_NEUTRAL)
	var vm = runtime.vm_for(soldier) if runtime and is_instance_valid(runtime) else null
	if vm:
		vm.paused = true
	# Ruf beim Ergeben: Satz „I Don't Have A Gun“ (speech.set Ereignis 114) – Zuordnung ANNAHME
	OrigAudio.speak_event(soldier, OrigAudio.EV_E_NO_WEAPON, 3.0)
	if by and by.is_player_controlled:
		Events.say("%s ergibt sich." % soldier.soldier_name, 2.5)


func _set_team(t: int) -> void:
	soldier.remove_from_group("team_%d" % soldier.team)
	soldier.team = t
	soldier.add_to_group("team_%d" % t)


## Ergebener wird beschossen: bewaffnet -> Gegenwehr, sonst Flucht (Original 0x54B820: 0x8000001 bzw. 0x4000002)
func _end_surrender(attacker: Soldier) -> void:
	surrendered = false
	soldier.remove_meta("hands_up")
	if soldier.model and soldier.model.has_method("set_hands_up"):
		soldier.model.set_hands_up(false)
	_set_team(Soldier.TEAM_AXIS)
	morale_initial = minf(morale_initial, 74.0)    # kein zweites Ergeben aus Standhaftigkeit
	var vm = runtime.vm_for(soldier) if runtime and is_instance_valid(runtime) else null
	if vm:
		vm.paused = false
	script_control = false
	if attacker and is_armed():
		_on_detected(attacker)
	elif attacker:
		var away := soldier.global_position - attacker.global_position
		away.y = 0.0
		set_state(State.SEARCH)
		move_to(soldier.global_position + away.normalized() * 30.0, Soldier.MoveMode.RUN)


## Gefangennehmen (Original T7038): Waffen abgeben, niederknien; danach Durchsuchen und Uniform möglich
func capture(by: Soldier) -> void:
	if not surrendered or captured or not soldier.alive:
		return
	captured = true
	_captor = by
	soldier.set_meta("captured", true)
	# abgegebene Waffen (Original: Waffe wird fallengelassen) – Munition bleibt beim Durchsuchen erhältlich
	for i in soldier.weapons.size():
		var w := soldier.weapons[i]
		if w and w.data.action != WeaponData.Action.MELEE:
			soldier.set_meta("surrendered_weapons", soldier.get_meta("surrendered_weapons", []) + [w])
			soldier.weapons[i] = null
	soldier._on_weapon_switched()
	Events.say("%s ist gefangen." % soldier.soldier_name, 2.5)
	# Gefangener zählt für Skripte als ausgeschaltet (_ACTOR_GetState 0) -> auch OnDeath (Zähler wie CZECH3
	# „dummy_reinforcement“ brauchen sonst jeden Toten). ANNAHME: Original-Ereignis bei Gefangennahme nicht dekodiert.
	if runtime and is_instance_valid(runtime) and not soldier.has_meta("death_notified"):
		soldier.set_meta("death_notified", true)
		runtime.notify(soldier, "ONDEATH")


## Leicheninhalt/Taschen eines Gefangenen übernehmen (wie Pickups.Loot)
func search(by: Soldier) -> String:
	var total := 0
	for cw in soldier.get_meta("surrendered_weapons", []):
		var w0 := cw as Weapon
		if w0 == null or w0.data.slot == WeaponData.Slot.GRENADE:
			continue
		for w in by.weapons:
			if w and w.data.caliber == w0.data.caliber and w0.total_ammo() > 0:
				var got := w.add_ammo(w0.total_ammo())
				w0.reserve = maxi(w0.reserve - got, 0)
				total += got
	var taken: Array[String] = []
	for oid in soldier.get_meta("orig_loot", []):
		taken.append(OrigInteractive.give_item(by, int(oid)))
	soldier.set_meta("orig_loot", [])
	var parts: Array[String] = []
	if total > 0:
		parts.append("%d Schuss" % total)
	parts.append_array(taken)
	return ", ".join(parts) if not parts.is_empty() else "nichts Brauchbares"


## Nichtkämpfer (actors.bin Mensch +0x1A5, `noncombatant_flag`): „Uniform benutzen“ (T7044) bleibt grau [B]
## (Zivilisten, Ärzte, Piloten …; 14 Kampagnenkarten).
func noncombatant() -> bool:
	if soldier == null or not soldier.has_meta("orig_params"):
		return false
	return int((soldier.get_meta("orig_params") as Dictionary).get("noncombatant_flag", 0)) != 0


## Uniform verfügbar: noch nicht abgegeben und kein Nichtkämpfer
func uniform_available() -> bool:
	return not uniform_taken and not noncombatant()


## Uniform eines Gefangenen anziehen (Original T7044, nur lebende Gefangene); Uniform zählt als Gegenstand
func give_uniform(to: Soldier) -> bool:
	if not captured or not uniform_available() or not soldier.alive or to.disguised:
		return false
	uniform_taken = true
	# Original-Figur der Uniform (Modell des Gefangenen, z. B. ge01a) übergeben: Soldier tauscht nur die Figur
	var fig: Node3D = null
	var m := Game.current_mission()
	if soldier.has_meta("orig_model") and m and m.get("orig") != null:
		fig = m.orig.character_instance(String(soldier.get_meta("orig_model")))
	to.put_on_uniform(soldier.uniform_color, soldier.helmet_style, fig)
	to.set_meta("uniform_figure", String(soldier.get_meta("orig_model", "")))
	if soldier.has_meta("orig_uniform"):
		var inv: Array = to.get_meta("orig_items", [])
		inv.append(int(soldier.get_meta("orig_uniform")))
		to.set_meta("orig_items", inv)
	return true


## Benutzen am Gegner: Gefangennehmen -> Durchsuchen -> Uniform benutzen
class CaptureAction extends Interactable:
	var brain: EnemyBrain
	var searched := false

	func _ready() -> void:
		super._ready()
		enabled = false

	func _physics_process(_d: float) -> void:
		var s := brain.soldier
		if s == null:
			return
		global_position = s.global_position + Vector3.UP * 0.9
		enabled = s.alive and (brain.surrendered or brain.captured)
		if brain.captured:
			prompt = OrigInteractive.text(7044, "Uniform benutzen") if searched else OrigInteractive.text(7043, "Suchen & Mun. sammeln")
		else:
			prompt = OrigInteractive.text(7038, "Gefangennehmen")

	func can_interact(s: Soldier) -> bool:
		var live := brain.soldier != null and brain.soldier.alive and (brain.surrendered or brain.captured)
		if not live or s.team != Soldier.TEAM_ALLIED or s.vehicle != null:
			return false
		if brain.captured and searched:
			return brain.uniform_available() and not s.disguised
		return true

	func interact(s: Soldier) -> void:
		if not can_interact(s):
			return
		if not brain.captured:
			brain.capture(s)
		elif not searched:
			searched = true
			Events.say("Durchsucht: %s" % brain.search(s), 2.5)
		elif brain.give_uniform(s):
			Events.say("%s trägt jetzt eine feindliche Uniform. Nicht schießen, Abstand halten!" % s.soldier_name, 4.0)
		super.interact(s)


# --- Waffenstellungen / Bordwaffen ----------------------------------------------------

## Besetzte Stellung bzw. Waffensitz im Fahrzeug: nicht bewegen, sichtbare Feinde bekämpfen (Zombie-Modus: nur zielen)
func _mounted_tick(delta: float) -> void:
	_script_tick_stance_only()
	perception.forget_dead()
	var t := perception.best_target()
	if t == null and is_instance_valid(target) and target.alive and perception.awareness.get(target, 0.0) >= 1.0 \
			and perception.visible_now.get(target, false):
		t = target
	if t and not script_control:
		if state != State.COMBAT:
			target = t
			_stimulus = AL_SEE
			set_state(State.COMBAT)
		target = t
		engage(t, delta)
	else:
		cease_fire()
		if script_look_at.is_finite():
			look_at_point(script_look_at + Vector3.UP * 1.5, delta, 2.0)


func _script_tick_stance_only() -> void:
	soldier.move_input = Vector3.ZERO
	_move_target = Vector3.INF


## Waffenstellungen besetzt die Gegner-KI nur über das Originalskript (HUMAN_BoardVehicle(Stellung, 1, Sitz)): die
## Gegner-KI von hd2.exe sucht keine Stellungen selbst (keine Typ-21-Abfrage im KI-Code 0x540000–0x55FFFF; Typ-21-
## Prüfungen nur in 0x45B890 Schaden, 0x4B0920 Zielanzeige, 0x74A690) [P, re_notes_ai §3]. Die frühere Annahme
## (Ausgangsposition ≤ 3 m neben einer Stellung → im Kampf besetzen) ist entfernt.


func serialize() -> Dictionary:
	return {"state": state, "alert": alert_level, "patrol_index": patrol_index, "morale": morale,
		"surrendered": surrendered, "captured": captured, "uniform_taken": uniform_taken}


func deserialize(d: Dictionary) -> void:
	alert_level = d.get("alert", 0.0)
	morale = float(d.get("morale", morale))
	uniform_taken = bool(d.get("uniform_taken", false))
	if bool(d.get("surrendered", false)) or bool(d.get("captured", false)):
		surrender(null)
		if bool(d.get("captured", false)):
			captured = true
			soldier.set_meta("captured", true)
			for i in soldier.weapons.size():
				if soldier.weapons[i] and soldier.weapons[i].data.action != WeaponData.Action.MELEE:
					soldier.weapons[i] = null
		return
	patrol_index = int(d.get("patrol_index", 0)) % maxi(patrol_points.size(), 1)
	var s := int(d.get("state", state))
	# Kampf-/Suchzustände werden nach dem Laden als Suche fortgesetzt
	if s == State.COMBAT or s == State.INVESTIGATE:
		s = State.SEARCH
		investigate_pos = soldier.global_position
	set_state(s)
