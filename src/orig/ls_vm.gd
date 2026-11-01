class_name LsVM
extends RefCounted
## Ausführung eines kompilierten Original-Skripts (LsCompiler) für ein Objekt.
## Semantik (aus den Originalskripten abgeleitet):
## - Hauptablauf läuft sequenziell; Delay(ms) und blockierende Befehle (HUMAN_Move) warten.
## - Ereignisse (OnSignal, OnAlarm, OnDeath …) VERWERFEN den laufenden Ablauf (außer in
##   Block{}) und springen in ihren Block; danach geht es hinter dem Block weiter.
## - EndScript() beendet den laufenden Ablauf; registrierte Ereignisse bleiben aktiv.
## - Whenever-Bedingungen werden jeden Tick geprüft und lösen einmalig aus
##   (SetWhenever(Name, true) aktiviert erneut).

const MAX_OPS_PER_TICK := 800

var code: LsCompiler
var name := ""
var me: Node3D                 ## eigenes Objekt (FRM_GetMyFrame)
var rt                         ## LsRuntime
var pc := 0
var vars := {}
var stack: Array = []          ## Ereignis-Rücksprünge [pc, wait, wait_until, ended]
var gosub_stack: Array[int] = []
var wait := 0.0
var wait_until := Callable()
var wait_timeout := 0.0
var ended := false
var death_revived := false      ## nach EndScript nur für OnDeath wieder aktiv (hd2.exe 0x41D920)
var terminated := false        ## EndScript(): Skript endgültig beendet (Ereignisse/Whenever wirkungslos)
var atomic := false
var signals := {}              ## empfangene Signalnummern
var signals_disabled := false
var disabled_signal_ids := {}   ## EnableSignal(n, false): einzelne Signalnummern sperren
var whenevers_disabled := false
var whenever_active := {}
var events: Array[String] = []
var trace := false
var paused := false             ## Akteur hat sich ergeben/ist gefangen: Skript ruht (bis OnDeath)
## Prüftakt je Whenever (SetWheneverTime, AP-5): Name -> ms; fehlend = jeder Tick [E], vorhanden (auch 0) = 500-ms-Raster
## (_check_whenevers); Spielstand (AP-1) sichert alle drei Felder bereits (Original 0x4147D0: je Whenever Periode, verstrichene Zeit, an/aus).
var whenever_interval_ms := {}
var whenever_elapsed_ms := {}   ## Name -> seit der letzten Prüfung verstrichene Zeit (ms) (AP-5; Original 0x4147D0)
var whenever_tick_ms := 0       ## VM-weiter Whenever-Takt (ms, 0 = jeder Tick), Original 0x4147D0 [B] (AP-5)
var block_pc := -1              ## Index des blockierenden Befehls (wait_until) – Spielstand: nach dem Laden neu anstoßen


func _init(compiled: LsCompiler, owner: Node3D, runtime, script_name := "") -> void:
	code = compiled
	me = owner
	rt = runtime
	name = script_name
	for w in code.whenevers:
		whenever_active[w] = true


## Ereignis auslösen (z. B. "ONSIGNAL:5", "ONALARM", "ONDEATH").
func fire(key: String) -> bool:
	# OnDeath läuft auch nach EndScript(): hd2.exe 0x41D920 setzt den Einsprung (+0xDC) und löscht das Ende-Flag +0xD4,
	# das EndScript (0x41980B) setzt; OnUse 0x41D960 u. a. tun das nicht → bleiben nach EndScript wirkungslos [B]
	if terminated and key == "ONDEATH" and code.handlers.has(key) and not death_revived:
		terminated = false
		ended = false
		death_revived = true
		events.clear()
		events.append(key)
		return true
	if terminated or (death_revived and key != "ONDEATH"):
		return false
	if key.begins_with("ONSIGNAL:") and (signals_disabled or disabled_signal_ids.has(int(key.substr(9)))):
		return false
	if not code.handlers.has(key):
		return false
	events.append(key)
	return true


func signal_received(n: int) -> void:
	# Original: DisableSignals/EnableSignal(n, false) sperren auch _SignalReceived (BURMA1 bu1_timer.scr)
	if signals_disabled or disabled_signal_ids.has(n):
		return
	signals[n] = true
	fire("ONSIGNAL:%d" % n)


var _started := false


func tick(delta: float) -> void:
	# Erster Takt: zuerst den Skriptanfang ausführen (Deklarationen, FRM_FindFrame …), erst danach
	# Ereignisse und Whenever-Bedingungen prüfen – sonst lösen Bedingungen mit noch leeren Variablen aus
	# (z. B. „!_ACTOR_GetState(schumman)“ in AFRICA5 meldete Schumann sofort als tot).
	if not _started:
		_started = true
		_run()
		return
	if terminated:
		return
	if paused:
		if not events.has("ONDEATH"):
			return
		paused = false
		atomic = false
		events.clear()
		events.append("ONDEATH")
	# Ereignisse unterbrechen (nicht während Block{})
	if not atomic and not events.is_empty():
		_enter(code.handlers[events.pop_front()])
	elif not atomic and not whenevers_disabled and not death_revived:
		_check_whenevers(delta)
	if wait > 0.0:
		wait -= delta
		if wait > 0.0:
			return
		wait = 0.0
	if wait_until.is_valid():
		wait_timeout -= delta
		if not wait_until.call() and wait_timeout > 0.0:
			return
		wait_until = Callable()
	if ended:
		return
	_run()


## Whenever-Takt (AP-5, hd2.exe 0x4167B0 [B]): VM-Akku `whenever_tick_ms` += dt; solange > 500: für jede aktive Whenever
## (von hinten nach vorn) elapsed += 500, erst bei elapsed > Periode: elapsed −= Periode und Bedingung prüfen; trifft sie
## zu → Sprung, Whenever deaktiviert sich (nur SetWhenever aktiviert wieder), laufendes Delay wird abgebrochen (_enter).
## Standardperiode beim Anlegen im Original offen [E]: Whenever OHNE SetWheneverTime (kein Eintrag in
## whenever_interval_ms) werden wie bisher jeden Tick geprüft – erhält das Verhalten der 24 Teile. Mit SetWheneverTime
## (auch 0) gilt das 500-ms-Raster. Pro Tick löst höchstens eine Whenever aus (bisheriges Verhalten).
const WHENEVER_SLICE_MS := 500.0


## B-039: Raster für ALLE Whenever (Original-Schleife 0x4167B0 prüft nur in 500-ms-Scheiben [B]); ohne SetWheneverTime
## gilt Periode 0 = jede Scheibe [E: Standardperiode offen]. Nur mit `--whenever_raster=1` (Messung/Option); Standard
## bleibt die AP-5-Festlegung „ohne SetWheneverTime jeden Tick“ (Abstimmung Koordinator 31.10.2026).
static var raster_all := -1


func _check_whenevers(delta: float) -> void:
	if raster_all < 0:
		# Standard AUS (AP-5-Festlegung [E], test_orig_cmds): nur mit --whenever_raster=1 alle Whenever im Raster
		raster_all = 1 if PerfTuning.b039() and String(Game.cli.get("whenever_raster", "0")) == "1" else 0
	if raster_all == 1:
		_check_whenevers_raster(delta)
		return
	var fired := ""
	if not whenever_interval_ms.is_empty():
		whenever_tick_ms += int(round(delta * 1000.0))
		var keys: Array = code.whenevers.keys()
		while whenever_tick_ms > WHENEVER_SLICE_MS:
			whenever_tick_ms -= int(WHENEVER_SLICE_MS)
			if fired != "":
				continue
			for i in range(keys.size() - 1, -1, -1):
				var w: String = keys[i]
				if not whenever_interval_ms.has(w) or not whenever_active.get(w, false):
					continue
				var el: float = float(whenever_elapsed_ms.get(w, 0.0)) + WHENEVER_SLICE_MS
				var per := float(whenever_interval_ms[w])
				if el > per:
					el -= per
					whenever_elapsed_ms[w] = el
					if _truthy(_eval(code.whenevers[w]["cond"])):
						fired = w
						break
				else:
					whenever_elapsed_ms[w] = el
	if fired == "":
		for w in code.whenevers:
			if whenever_interval_ms.has(w):
				continue
			if whenever_active.get(w, false) and _truthy(_eval(code.whenevers[w]["cond"])):
				fired = w
				break
	if fired != "":
		whenever_active[fired] = false
		_enter(code.whenevers[fired]["pc"])


func _check_whenevers_raster(delta: float) -> void:
	if code.whenevers.is_empty():
		return
	whenever_tick_ms += int(round(delta * 1000.0))
	if whenever_tick_ms <= WHENEVER_SLICE_MS:
		return
	var fired := ""
	var keys: Array = code.whenevers.keys()
	while whenever_tick_ms > WHENEVER_SLICE_MS:
		whenever_tick_ms -= int(WHENEVER_SLICE_MS)
		if fired != "":
			continue
		for i in range(keys.size() - 1, -1, -1):
			var w: String = keys[i]
			if not whenever_active.get(w, false):
				continue
			var el: float = float(whenever_elapsed_ms.get(w, 0.0)) + WHENEVER_SLICE_MS
			var per := float(whenever_interval_ms.get(w, 0))
			if el > per:
				el -= per
				whenever_elapsed_ms[w] = el
				if _truthy(_eval(code.whenevers[w]["cond"])):
					fired = w
					break
			else:
				whenever_elapsed_ms[w] = el
	if fired != "":
		whenever_active[fired] = false
		_enter(code.whenevers[fired]["pc"])


func _enter(target_pc: int) -> void:
	# Ereignis = Sprung: laufenden Ablauf (inkl. Unterprogramme) verwerfen
	stack.clear()
	gosub_stack.clear()
	pc = target_pc
	wait = 0.0
	wait_until = Callable()
	ended = false


func _ret() -> void:
	if stack.is_empty():
		ended = true
		return
	var s: Array = stack.pop_back()
	pc = s[0]
	wait = s[1]
	wait_until = s[2]
	ended = s[3]
	wait_timeout = s[4]


func _run() -> void:
	var budget := MAX_OPS_PER_TICK
	while budget > 0 and not ended and wait <= 0.0 and not wait_until.is_valid():
		budget -= 1
		if pc < 0 or pc >= code.ops.size():
			ended = true
			return
		var op: Array = code.ops[pc]
		pc += 1
		match op[0]:
			"call":
				_call(op[1], op[2])
			"assign":
				vars[op[1]] = _eval(op[2])
			"decl":
				if op[3] != null:
					vars[op[1]] = _eval(op[3])
				elif not vars.has(op[1]):
					vars[op[1]] = null if op[2] == "FRAME" else 0
			"jmp":
				pc = op[1]
			"jmpf":
				if not _truthy(_eval(op[1])):
					pc = op[2]
			"gosub":
				gosub_stack.append(pc)
				pc = op[1]
			"return":
				if gosub_stack.is_empty():
					_ret()
				else:
					pc = gosub_stack.pop_back()
			"ret":
				_ret()
			"atomic":
				atomic = op[1]
			"end":
				ended = true
				stack.clear()
				return
	if budget <= 0 and trace:
		print("LS %s: Befehlsbudget erschöpft (Schleife ohne Delay?) pc=%d" % [name, pc])


func _call(fname: String, args: Array) -> void:
	match fname:
		"DELAY":
			wait = maxf(float(_eval(args[0])) / 1000.0, 0.0) if args.size() > 0 else 0.0
			return
		"ENDSCRIPT":
			ended = true
			terminated = true
			events.clear()
			stack.clear()
			atomic = false
			return
		"SETWHENEVER":
			if args.size() >= 2 and args[0][0] == "var":
				whenever_active[args[0][1]] = _truthy(_eval(args[1]))
			return
		"DISABLESIGNALS":
			signals_disabled = _truthy(_eval(args[0])) if args.size() > 0 else true
			return
		"ENABLESIGNAL":
			var sid := int(_eval(args[0])) if args.size() > 0 else -1
			if args.size() > 1 and not _truthy(_eval(args[1])):
				disabled_signal_ids[sid] = true
			else:
				disabled_signal_ids.erase(sid)
			return
		"DISABLEWHENEVERS":
			whenevers_disabled = _truthy(_eval(args[0])) if args.size() > 0 else true
			return
	var r = rt.call_api(self, fname, args)
	if r is Dictionary:
		if r.has("wait"):
			wait = r["wait"]
		if r.has("wait_until"):
			wait_until = r["wait_until"]
			block_pc = pc - 1     # _call kommt nur aus der Anweisung "call" (pc zeigt schon dahinter)
			wait_timeout = r.get("timeout", 60.0)


## Wertet einen Ausdruck aus. Funktionsaufrufe ("_PlayerInRange") gehen an die Laufzeit.
func _eval(e):
	match e[0]:
		"num", "str":
			return e[1]
		"var":
			if vars.has(e[1]):
				return vars[e[1]]
			return 0
		"call":
			if e[1] == "_SIGNALRECEIVED":
				var n := int(_eval(e[2][0])) if e[2].size() > 0 else 0
				if signals.get(n, false):
					signals.erase(n)
					return 1
				return 0
			var v = rt.call_api(self, e[1], e[2])
			return 0 if v == null or v is Dictionary else v
		"not":
			return 0 if _truthy(_eval(e[1])) else 1
		"neg":
			return -_num(_eval(e[1]))
		"bin":
			var op: String = e[1]
			if op == "AND":
				return 1 if _truthy(_eval(e[2])) and _truthy(_eval(e[3])) else 0
			if op == "OR":
				return 1 if _truthy(_eval(e[2])) or _truthy(_eval(e[3])) else 0
			var a = _eval(e[2])
			var b = _eval(e[3])
			match op:
				"==": return 1 if _same(a, b) else 0
				"!=": return 0 if _same(a, b) else 1
				"<": return 1 if _num(a) < _num(b) else 0
				">": return 1 if _num(a) > _num(b) else 0
				"<=": return 1 if _num(a) <= _num(b) else 0
				">=": return 1 if _num(a) >= _num(b) else 0
				"+": return _num(a) + _num(b)
				"-": return _num(a) - _num(b)
				"*": return _num(a) * _num(b)
				"/": return _num(a) / _num(b) if _num(b) != 0 else 0
	return 0


## Argument als Wert (für die Laufzeit-API)
func value(e):
	return _eval(e)


static func _num(v) -> float:
	if v is int or v is float:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v == null:
		return 0.0
	return 1.0


static func _truthy(v) -> bool:
	if v is int or v is float:
		return v != 0
	if v is bool:
		return v
	return v != null


# --- Spielstand (B-030/AP-1) ------------------------------------------------------------
## Zustand als JSON-taugliches Dictionary. `enc` wandelt Skriptwerte (Frames!) um (LsRuntime.save_value).
## Ein blockierender Befehl (HUMAN_Move …, wait_until = Callable) ist nicht speicherbar: gespeichert wird sein
## Anweisungsindex, nach dem Laden wird er erneut ausgeführt (AP-1 Punkt 4).
func save_state(enc: Callable) -> Dictionary:
	var v := {}
	for k in vars:
		v[k] = enc.call(vars[k])
	var st: Array = []
	for s in stack:
		st.append([s[0], s[1], (s[2] as Callable).is_valid() if s[2] is Callable else false, s[3], s[4] if s.size() > 4 else 0.0])
	return {
		"script": name, "pc": pc, "started": _started, "ended": ended, "terminated": terminated,
		"death_revived": death_revived, "atomic": atomic, "paused": paused,
		"wait": wait, "blocking": wait_until.is_valid(), "block_pc": block_pc, "wait_timeout": wait_timeout,
		"gosub": Array(gosub_stack), "stack": st, "events": Array(events), "vars": v,
		"signals": signals.keys().filter(func(k): return signals[k]), "signals_disabled": signals_disabled,
		"disabled_signal_ids": disabled_signal_ids.keys(), "whenevers_disabled": whenevers_disabled,
		"whenever_active": whenever_active.duplicate(),
		"whenever_interval_ms": whenever_interval_ms.duplicate(), "whenever_elapsed_ms": whenever_elapsed_ms.duplicate(),
		"whenever_tick_ms": whenever_tick_ms,
	}


func load_state(d: Dictionary, dec: Callable) -> void:
	vars.clear()
	var v: Dictionary = d.get("vars", {})
	for k in v:
		vars[String(k)] = dec.call(v[k])
	pc = int(d.get("pc", 0))
	_started = bool(d.get("started", true))
	ended = bool(d.get("ended", false))
	terminated = bool(d.get("terminated", false))
	death_revived = bool(d.get("death_revived", false))
	atomic = bool(d.get("atomic", false))
	paused = bool(d.get("paused", false))
	wait = float(d.get("wait", 0.0))
	wait_timeout = float(d.get("wait_timeout", 0.0))
	wait_until = Callable()
	block_pc = int(d.get("block_pc", -1))
	if bool(d.get("blocking", false)) and block_pc >= 0:
		pc = block_pc      # blockierenden Befehl erneut ausführen (Ziel/Argumente stehen im Skript)
		wait = 0.0
	gosub_stack.clear()
	for g in d.get("gosub", []):
		gosub_stack.append(int(g))
	stack.clear()
	for s in d.get("stack", []):
		# Rücksprung mit blockierendem Befehl: ohne Callable fortsetzen (Stapel wird derzeit nirgends befüllt)
		stack.append([int(s[0]), float(s[1]), Callable(), bool(s[3]), float(s[4])])
	events.clear()
	for e in d.get("events", []):
		events.append(String(e))
	signals.clear()
	for n in d.get("signals", []):
		signals[int(n)] = true
	signals_disabled = bool(d.get("signals_disabled", false))
	disabled_signal_ids.clear()
	for n in d.get("disabled_signal_ids", []):
		disabled_signal_ids[int(n)] = true
	whenevers_disabled = bool(d.get("whenevers_disabled", false))
	var wa: Dictionary = d.get("whenever_active", {})
	for w in wa:
		whenever_active[String(w)] = bool(wa[w])
	whenever_interval_ms.clear()
	var wi: Dictionary = d.get("whenever_interval_ms", {})
	for w in wi:
		whenever_interval_ms[String(w)] = int(wi[w])
	whenever_elapsed_ms.clear()
	var wn: Dictionary = d.get("whenever_elapsed_ms", {})
	for w in wn:
		whenever_elapsed_ms[String(w)] = float(wn[w])
	whenever_tick_ms = int(d.get("whenever_tick_ms", 0))


static func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b
