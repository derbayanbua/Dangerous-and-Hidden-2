class_name BodyAnim
extends RefCounted
## Ganzkörper-Animation der Original-Figuren (Haupt-AnimationPlayer): Bewegung je Haltung/Richtung/Gangart,
## Haltungswechsel, Lehnen, Drehen, Springen/Landen, Klettern, Leiter, Schwimmen, Treffer, Tode, Ergeben/Gefangener,
## Benutzen/Türen/Aufheben/Sprengstoff. Zuordnung aus TABLES\anim.sav (tools/human_anims.py ->
## orig_cache/characters/human_anims.json, docs/re_notes_weapons.md §12). Die Waffenhaltung (HoldPlayer, Clips h_*)
## liegt weiter als Oberkörperschicht darüber; arms_free() schaltet sie für Ganzkörperaktionen ab.

const DIRS := ["fwd", "fr", "right", "br", "back", "bl", "left", "fl"]   ## Sektoren zu 45°, im Uhrzeigersinn
## Gangarten (anim.sav): 0 langsam, 1 normal, 2 schnell, 3 verwundet, 4 Wache, 5 Sprint
const MODE_CANDIDATES := [[0, 1, 2, 5], [0, 1, 2], [0, 1, 2]]
const TRANSITIONS := {"01": "st_dr", "10": "dr_st", "12": "dr_le", "21": "le_dr", "02": "st_le", "20": "le_st"}

static var _table: Dictionary = {}
static var _speeds: Dictionary = {}    ## Clip -> natürliche Geschwindigkeit (links/rechts symmetrisch)

var anim: AnimationPlayer
var dir := "fwd"
var mode := 1
var oneshot := ""          ## laufende Ganzkörper-Einmalaktion (Clipname)
var oneshot_left := 0.0
var oneshot_rate := 1.0
var oneshot_arms := false  ## true: Arme gehören der Aktion (Haltungsschicht aus)
var oneshot_kind := ""     ## "transition", "hit", "land", "use", "knife", "climb"
var last_stance := -1
var last_health := -1.0
var _hit_signal := false
var air_t := 0.0
var _air_peak := 0.0
var _yaw_prev := INF
var _turn_t := 0.0
var state := ""            ## Dauerzustand für Tests/Kontrollbilder: move/idle/lean/ladder/swim/surrender/captive/…
var clip := ""             ## zuletzt gewählter Ganzkörperclip


static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(OrigLevel.cache_root() + "/characters/human_anims.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_table = d if d is Dictionary else {"move": {}, "full": {}, "upper": {}, "clips": {}}
		_prepare_speeds()
	return _table


## Natürliche Geschwindigkeit je Clip; Paare links/rechts (und Diagonalen) symmetrisch (größerer Wert), weil die
## Fußpunktmessung bei Kreuzschritten einzelner Clips zu klein ausfällt [E].
static func _prepare_speeds() -> void:
	var clips: Dictionary = _table.get("clips", {})
	for st in (_table.get("move", {}) as Dictionary):
		var dirs: Dictionary = _table["move"][st]
		for pair in [["left", "right"], ["fl", "fr"], ["bl", "br"], ["fwd", "fwd"], ["back", "back"]]:
			var a: Array = dirs.get(pair[0], [])
			var b: Array = dirs.get(pair[1], [])
			for m in mini(a.size(), b.size()):
				var sa := float((clips.get(a[m], {}) as Dictionary).get("speed", 0.0))
				var sb := float((clips.get(b[m], {}) as Dictionary).get("speed", 0.0))
				var s := maxf(maxf(sa, sb), 0.05)
				_speeds[a[m]] = maxf(float(_speeds.get(a[m], 0.0)), s)
				_speeds[b[m]] = maxf(float(_speeds.get(b[m], 0.0)), s)


static func full(key: String) -> String:
	return String((table().get("full", {}) as Dictionary).get(key, ""))


static func upper(key: String) -> String:
	return String((table().get("upper", {}) as Dictionary).get(key, ""))


static func clip_length(c: String) -> float:
	return float(((table().get("clips", {}) as Dictionary).get(c, {}) as Dictionary).get("length", 0.0))


## Zeitpunkt (s, Tempo 1) des ersten Ereignisses ev im Clip (z. B. "t" = Stich trifft), -1 = keins.
static func event_time(c: String, ev: String) -> float:
	for e in ((table().get("clips", {}) as Dictionary).get(c, {}) as Dictionary).get("events", []):
		if String(e[1]) == ev:
			return float(e[0])
	return -1.0


static func move_clip(stance: int, d: String, m: int) -> String:
	var lst: Array = ((table().get("move", {}) as Dictionary).get(str(stance), {}) as Dictionary).get(d, [])
	return String(lst[m]) if m < lst.size() else ""


static func natural_speed(c: String) -> float:
	table()
	return float(_speeds.get(c, 1.0))


func setup(player: AnimationPlayer) -> void:
	anim = player
	if anim == null:
		return
	table()
	# Bewegungs-/Ruhe-/Schwimm-/Leiterclips in Schleife, Aktionen/Tode einmalig
	var loops := {}
	for st in (_table.get("move", {}) as Dictionary):
		for d in (_table["move"][st] as Dictionary):
			for c in _table["move"][st][d]:
				loops[String(c)] = true
	for k in ["idle_zb", "crouch_zb", "prone_zb", "swim", "swim_idle", "dive", "dive_move", "ladder_up", "ladder_down",
			"tied", "wounded_lie"]:
		loops[full(k)] = true
	for c in loops:
		if c != "" and anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	for k in (_table.get("full", {}) as Dictionary):
		var c := full(k)
		if c != "" and not loops.has(c) and anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_NONE


func has(c: String) -> bool:
	return c != "" and anim != null and anim.has_animation(c)


## Ganzkörper-Einmalaktion; duration < 0 = Cliplänge. arms: Haltungsschicht während der Aktion aus.
func play_oneshot(c: String, duration: float = -1.0, arms: bool = false, kind: String = "") -> bool:
	if not has(c):
		return false
	var ln := anim.get_animation(c).length
	var dur := duration if duration > 0.0 else ln
	oneshot = c
	oneshot_left = dur
	oneshot_rate = clampf(ln / maxf(dur, 0.05), 0.25, 4.0)
	oneshot_arms = arms
	oneshot_kind = kind
	anim.play(c, 0.12, oneshot_rate)
	anim.seek(0.0, true)
	clip = c
	return true


func stop_oneshot() -> void:
	oneshot = ""
	oneshot_left = 0.0
	oneshot_kind = ""


func arms_free() -> bool:
	if oneshot != "" and oneshot_arms:
		return true
	return state in ["ladder", "swim", "climb", "captive_tied", "wounded_lie"]


func weapon_hidden() -> bool:
	if oneshot != "" and oneshot_arms and oneshot_kind == "use":
		return true          # Benutzen/Aufheben/Sprengsatz: beide Hände frei (Waffe am Rücken gedacht) [D]
	return state in ["ladder", "swim", "surrender", "captive", "captive_tied", "wounded_lie"]


## Lokale Bewegungsrichtung (Sektor) mit Hysterese: Winkel 0 = vorwärts (-Z), + = rechts.
func _sector(local: Vector2) -> String:
	var a := atan2(local.x, -local.y)
	var idx := posmod(int(round(a / (PI / 4.0))), 8)
	var cur := DIRS.find(dir)
	if cur >= 0:
		var ca := cur * PI / 4.0
		if absf(wrapf(a - ca, -PI, PI)) < PI / 8.0 + deg_to_rad(10.0):
			return dir
	return DIRS[idx]


## Gangart nach tatsächlicher Geschwindigkeit (gilt auch für Netzfiguren ohne Gangartangabe): Schwellen zwischen den
## Clips (m/s) so, dass Schleichen/Gehen/Laufschritt/Sprint des Spiels je einen eigenen Original-Clip bekommen;
## das Abspieltempo gleicht den Rest an (wenig Fußgleiten). 10 % Hysterese gegen Flackern [D].
const MODE_THRESH := [[1.05, 2.4, 4.3], [0.4, 1.0], [0.2, 0.7]]


func _pick_mode(stance: int, d: String, speed: float, wounded: bool) -> int:
	if wounded and stance == 0 and has(move_clip(stance, d, 3)):
		return 3
	var cands: Array = MODE_CANDIDATES[stance]
	var th: Array = MODE_THRESH[stance]
	var cur := cands.find(mode)
	var idx := 0
	for i in th.size():
		var t := float(th[i])
		if cur >= 0:
			t *= 1.1 if cur <= i else 0.9      # bisherige Gangart etwas länger halten
		if speed >= t:
			idx = i + 1
	var m: int = cands[mini(idx, cands.size() - 1)]
	return m if has(move_clip(stance, d, m)) else 1


## Haupt-Update: liefert {clip, rate, blend, seek (≥ 0: Standbild auf dieser Zeit)} oder {} (nichts ändern).
## s = Soldier, sb = Haltungsgewichte, speed = Bodengeschwindigkeit.
func update(delta: float, s, stance: int, speed: float, lean: float, basis: Basis) -> Dictionary:
	if anim == null or s == null:
		return {}
	var alive: bool = s.get("alive") != false
	# Treffer (auch Netzfiguren: Gesundheit fällt ohne damaged-Signal)
	var hp: float = float(s.get("health")) if s.get("health") != null else 100.0
	if last_health >= 0.0 and hp < last_health - 1.0 and alive and not _hit_signal:
		on_hit(stance, &"torso", Vector3.ZERO, speed)
	_hit_signal = false
	last_health = hp
	# Haltungswechsel
	if last_stance >= 0 and stance != last_stance and alive:
		var key: String = TRANSITIONS.get("%d%d" % [last_stance, stance], "")
		var c := full(key)
		var lock := 0.5
		if s.has_method("stance_transitioning"):
			lock = maxf(float(s.get("_stance_lock")), 0.35)
		if has(c) and oneshot_kind not in ["climb", "knife"]:
			# Original-Übergang in der Wechselzeit des Spiels (höchstens 3× schneller als im Original)
			play_oneshot(c, maxf(lock, anim.get_animation(c).length / 3.0), false, "transition")
	last_stance = stance
	# Klettern/Leiter beginnt: andere Einmalaktionen (Landung, Treffer, Übergang) abbrechen
	var climbing: bool = s.has_method("is_climbing") and s.is_climbing()
	if climbing and oneshot != "" and oneshot_kind != "climb":
		stop_oneshot()
	# Einmalaktion läuft
	if oneshot != "":
		oneshot_left -= delta
		if oneshot_left <= 0.0 or not alive:
			stop_oneshot()
		else:
			state = oneshot_kind if oneshot_kind != "" else "action"
			return {"clip": oneshot, "rate": oneshot_rate, "blend": 0.12, "keep": true}
	var v: Vector3 = s.get("velocity") if s.get("velocity") != null else Vector3.ZERO
	var local3 := basis.inverse() * v
	var local := Vector2(local3.x, local3.z)
	# Klettern über Hindernisse / Leiter
	if climbing:
		var info: Dictionary = s.climb_info() if s.has_method("climb_info") else {}
		if bool(info.get("ladder", false)):
			state = "ladder"
			var up := float(info.get("dy", 1.0)) >= 0.0
			var c := full("ladder_up" if up else "ladder_down")
			# 1 Zyklus (1,6 s) ≈ 2 Sprossen ≈ 0,6 m [E]; Tempo nach Steiggeschwindigkeit
			var vs := absf(float(info.get("dy", 1.0))) / maxf(float(info.get("duration", 1.0)), 0.2)
			return {"clip": c, "rate": clampf(vs / 0.375, 0.5, 2.5), "blend": 0.15}
		var h := float(info.get("dy", 1.0))
		var key := "step_up" if h < 0.95 else ("obstacle_mid" if h < 1.6 else "obstacle_high")
		var c2 := full(key)
		if has(c2):
			play_oneshot(c2, float(info.get("left", 0.5)), true, "climb")
			state = "climb"
			return {"clip": oneshot, "rate": oneshot_rate, "blend": 0.1, "keep": true}
	# Schwimmen / Tauchen
	if bool(s.get("swimming")):
		var under: bool = s.has_method("head_under_water") and s.head_under_water()
		var moving := v.length() > 0.3
		state = "swim"
		var c3 := full(("dive_move" if moving else "dive") if under else ("swim" if moving else "swim_idle"))
		if not has(c3):
			c3 = full("swim")
		return {"clip": c3, "rate": clampf(v.length() / 1.2, 0.6, 1.8) if moving else 1.0, "blend": 0.25}
	# Ergeben / gefangen / gefesselt (Meta von EnemyBrain bzw. Skript)
	if s.has_meta("tied"):
		state = "captive_tied"
		return {"clip": full("tied"), "rate": 1.0, "blend": 0.3}
	if s.has_meta("captured"):
		state = "captive"
	elif s.has_meta("hands_up"):
		state = "surrender"
	# Springen / Fallen / Landen
	var on_floor: bool = (s as CharacterBody3D).is_on_floor() if s is CharacterBody3D else true
	if bool(s.get("net_puppet")):
		on_floor = absf(v.y) < 1.5
	if not on_floor and alive:
		air_t += delta
		_air_peak = maxf(_air_peak, air_t)
		if air_t > 0.12:
			if v.y > 0.5 and has(full("jump_up")):
				state = "jump"
				return {"clip": full("jump_up"), "rate": 1.6, "blend": 0.1}
			if air_t > 0.45 and has(full("fall")):
				state = "fall"
				return {"clip": full("fall"), "rate": 1.0, "blend": 0.2}
	else:
		if _air_peak > 0.35 and alive:
			_air_peak = 0.0
			air_t = 0.0
			if play_oneshot(full("land"), 0.45, false, "land"):
				return {"clip": oneshot, "rate": oneshot_rate, "blend": 0.08, "keep": true}
		air_t = 0.0
		_air_peak = 0.0
	if state in ["surrender", "captive"]:
		# Oberkörper (Hände hoch) spielt die Haltungsschicht; Beine: Ruhe der Haltung
		var ic := full(["idle_zb", "crouch_zb", "prone_zb"][stance])
		return {"clip": ic, "rate": 1.0, "blend": 0.3}
	# Lehnen (Q/E): Original-Clip bis zum Scheitelbild ('p', Bild 28) überblendet, Standbild nach Lehnstärke
	if absf(lean) > 0.05 and speed < 0.6:
		var lc := full(("lean_l%d" if lean < 0.0 else "lean_r%d") % stance)
		if has(lc):
			state = "lean"
			var peak := event_time(lc, "p")
			if peak <= 0.0:
				peak = anim.get_animation(lc).length * 0.5
			return {"clip": lc, "seek": peak * clampf(absf(lean), 0.0, 1.0), "blend": 0.15}
	# Bewegung
	var wounded: bool = hp < float(s.get("max_health") if s.get("max_health") != null else 100.0) * 0.35
	if speed > 0.25:
		dir = _sector(local)
		mode = _pick_mode(stance, dir, speed, wounded)
		var mc := move_clip(stance, dir, mode)
		if has(mc):
			state = "move"
			var rate := clampf(speed / natural_speed(mc), 0.5, 2.3)
			return {"clip": mc, "rate": rate, "blend": 0.2}
	# Ruhe; Drehen auf der Stelle im Stand (otočit)
	var yaw: float = float(s.get("look_yaw")) if s.get("look_yaw") != null else 0.0
	if _yaw_prev != INF and stance == 0:
		var dy := wrapf(yaw - _yaw_prev, -PI, PI) / maxf(delta, 0.001)
		if absf(dy) > 1.2:
			_turn_t = 0.35
			_turn_left = dy > 0.0
	_yaw_prev = yaw
	_turn_t = maxf(_turn_t - delta, 0.0)
	if _turn_t > 0.0:
		var tc := full("turn_l" if _turn_left else "turn_r")
		if has(tc):
			state = "turn"
			return {"clip": tc, "rate": 1.3, "blend": 0.15}
	state = "idle"
	var idle := full(["idle_zb", "crouch_zb", "prone_zb"][stance])
	return {"clip": idle, "rate": 1.0, "blend": 0.25}


var _turn_left := false


## Treffer: Original-Trefferclip je Zone/Haltung (Tabelle 0x1A4AF); im Lauf nur ohne Ganzkörperclip (Beine laufen).
func on_hit(stance: int, zone: StringName, local_from: Vector3, speed: float) -> void:
	_hit_signal = true
	if oneshot_kind in ["climb", "knife", "use"] or speed > 1.0:
		return
	var key := "hit_belly"
	match String(zone):
		"head":
			key = "hit_head"
		"arm":
			key = "hit_shr" if local_from.x > 0.0 else "hit_shl"
		"leg", "legs":
			key = "hit_legr" if local_from.x > 0.0 else "hit_legl"
		_:
			key = "hit_back" if local_from.z > 0.25 else "hit_belly"
	var c := full("%s%d" % [key, clampi(stance, 0, 2)])
	if has(c):
		play_oneshot(c, minf(anim.get_animation(c).length, 1.0), false, "hit")


## Todesclip nach Haltung, Geschossrichtung (lokal, Figur blickt nach -Z) und Zone; kind "throat" = Messer von hinten.
func death_clip(stance: int, local_dir: Vector3, zone: String, kind: String) -> String:
	var keys: Array = []
	if kind == "throat":
		keys = ["death_throat"]
	elif stance == 2:
		keys = ["death_p1", "death_p2", "death_p4", "death_p5", "death_p6"]
	elif stance == 1:
		if absf(local_dir.x) > absf(local_dir.z) * 1.2:
			keys = ["death_kr"] if local_dir.x > 0.0 else ["death_kl"]
		elif local_dir.z > 0.0:
			keys = ["death_kb1", "death_kb3"]
		else:
			keys = ["death_c1", "death_c2", "death_c3", "death_c4"]
	elif zone == "head" and randf() < 0.5:
		keys = ["death_m"]
	elif local_dir.length() < 0.01:
		keys = ["death_b1", "death_b2", "death_b3", "death_b4", "death_m"]
	elif absf(local_dir.x) > absf(local_dir.z) * 1.2:
		keys = ["death_r"] if local_dir.x > 0.0 else ["death_l"]      # Geschoss nach rechts -> fällt nach rechts
	elif local_dir.z > 0.0:
		keys = ["death_b1", "death_b2", "death_b3", "death_b4"]        # von vorn getroffen -> nach hinten
	else:
		keys = ["death_f1", "death_f2", "death_f3", "death_f4", "death_f5"]
	keys.shuffle()
	for k in keys:
		var c := full(k)
		if has(c):
			return c
	return ""
