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
var atomic := false
var signals := {}              ## empfangene Signalnummern
var signals_disabled := false
var disabled_signal_ids := {}   ## EnableSignal(n, false): einzelne Signalnummern sperren
var whenevers_disabled := false
var whenever_active := {}
var events: Array[String] = []
var trace := false


func _init(compiled: LsCompiler, owner: Node3D, runtime, script_name := "") -> void:
	code = compiled
	me = owner
	rt = runtime
	name = script_name
	for w in code.whenevers:
		whenever_active[w] = true


## Ereignis auslösen (z. B. "ONSIGNAL:5", "ONALARM", "ONDEATH").
func fire(key: String) -> bool:
	if key.begins_with("ONSIGNAL:") and (signals_disabled or disabled_signal_ids.has(int(key.substr(9)))):
		return false
	if not code.handlers.has(key):
		return false
	events.append(key)
	return true


func signal_received(n: int) -> void:
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
	# Ereignisse unterbrechen (nicht während Block{})
	if not atomic and not events.is_empty():
		_enter(code.handlers[events.pop_front()])
	elif not atomic and not whenevers_disabled:
		for w in code.whenevers:
			if whenever_active.get(w, false) and _truthy(_eval(code.whenevers[w]["cond"])):
				whenever_active[w] = false
				_enter(code.whenevers[w]["pc"])
				break
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


static func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b
