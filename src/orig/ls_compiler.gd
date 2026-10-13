class_name LsCompiler
extends RefCounted
## Compiler für die Skriptsprache der LS3D-Engine (Hidden & Dangerous 2, *.scr).
## Sprachumfang aus den Originalskripten rekonstruiert:
##   Deklarationen   frame a; integer x = 0; float f;
##   Zuweisung       x = Ausdruck;
##   Aufrufe         HUMAN_Move("GG_3");   Funktionen mit "_" liefern Werte
##   Kontrollfluss   If (Bed) {…} Else {…}   goto Ziel;   Label Ziel:
##   Atomar          Block { … }
##   Ereignisse      OnSignal(n) / OnAlarm() / OnAlarmDone() / OnDeath() / OnCutScene(n) /
##                   OnCutSceneDone(n) / OnUse() / OnExit() / OnHit() { … }
##   Bedingungen     Whenever Name (Bed) { … }   (SetWhenever(Name, bool))
## Ergebnis: lineare Befehlsliste + Tabellen für Sprungmarken, Ereignisse und Whenevers.
## Ereignis-/Whenever-Blöcke werden im normalen Ablauf übersprungen. Löst ein Ereignis aus,
## springt der Ablauf in den Block und läuft danach HINTER dem Block weiter (kein Rücksprung).
## Belegt durch die Originalskripte, z. B. Sygurd: Warteschleife, "OnSignal(3) {}" und danach
## HUMAN_Move(...) – das leere Ereignis setzt den Ablauf hinter dem Block fort.

const KEYWORDS := ["BLOCK", "IF", "ELSE", "GOTO", "LABEL", "WHENEVER", "AND", "OR", "NOT", "TRUE", "FALSE"]
const DECL_TYPES := ["FRAME", "INTEGER", "FLOAT", "BOOL", "STRING"]
const HANDLERS := ["ONSIGNAL", "ONALARM", "ONALARMDONE", "ONDEATH", "ONCUTSCENE", "ONCUTSCENEDONE",
	"ONUSE", "ONEXIT", "ONHIT", "ONGLOBALALARM", "ONENTER"]

var source_name := ""
var errors: Array[String] = []
var _toks: Array = []   ## [Art, Wert, Zeile]
var _i := 0
var ops: Array = []
var labels := {}        ## NAME -> pc
var handlers := {}      ## "ONSIGNAL:5" / "ONALARM" -> pc
var whenevers := {}     ## NAME -> {"cond": Ausdruck, "pc": int}
var _pending_gotos: Array = []


## include_dir: Ordner für #include "datei" (gleicher Ordner wie das Skript oder Skriptwurzel)
static func compile(text: String, name := "", include_dir := "") -> LsCompiler:
	var c := LsCompiler.new()
	c.source_name = name
	c._tokenize(_preprocess(text, include_dir, 0))
	c._parse_program()
	return c


static func _preprocess(text: String, include_dir: String, depth: int) -> String:
	if not "#" in text:
		return text
	var out := PackedStringArray()
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			if s.to_lower().begins_with("#include") and depth < 4 and include_dir != "":
				var q := s.split("\"")
				if q.size() >= 2:
					var inc := _find_include(include_dir, q[1])
					if inc != "":
						var f := FileAccess.open(inc, FileAccess.READ)
						if f:
							out.append(_preprocess(f.get_buffer(f.get_length()).get_string_from_ascii(), include_dir, depth + 1))
			out.append("")   # Zeilennummern grob erhalten
		else:
			out.append(line)
	return "\n".join(out)


static func _find_include(dir: String, file: String) -> String:
	for cand in [dir.path_join(file), dir.get_base_dir().path_join(file)]:
		if FileAccess.file_exists(cand):
			return cand
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.to_lower() == file.to_lower():
				return dir.path_join(f)
	return ""


func ok() -> bool:
	return errors.is_empty()


# --- Lexer ---------------------------------------------------------------------

func _tokenize(t: String) -> void:
	var i := 0
	var line := 1
	var n := t.length()
	while i < n:
		var ch := t[i]
		if ch == "\n":
			line += 1
			i += 1
		elif ch == " " or ch == "\t" or ch == "\r" or ch.unicode_at(0) < 32:
			i += 1
		elif ch == "/" and i + 1 < n and t[i + 1] == "/":
			while i < n and t[i] != "\n":
				i += 1
		elif ch == "/" and i + 1 < n and t[i + 1] == "*":
			i += 2
			while i + 1 < n and not (t[i] == "*" and t[i + 1] == "/"):
				if t[i] == "\n":
					line += 1
				i += 1
			i += 2
		elif ch == "\"":
			var j := i + 1
			while j < n and t[j] != "\"" and t[j] != "\n":
				j += 1
			_toks.append(["str", t.substr(i + 1, j - i - 1), line])
			i = j + 1
		elif _is_digit(ch) or (ch == "." and i + 1 < n and _is_digit(t[i + 1])):
			var j := i
			while j < n and (_is_digit(t[j]) or t[j] == "."):
				j += 1
			_toks.append(["num", t.substr(i, j - i), line])
			i = j
		elif _is_ident_start(ch):
			var j := i
			while j < n and (_is_ident_start(t[j]) or _is_digit(t[j])):
				j += 1
			_toks.append(["id", t.substr(i, j - i), line])
			i = j
		else:
			var two := t.substr(i, 2)
			if two in ["==", "!=", "<=", ">=", "&&", "||", "<>"]:
				_toks.append(["op", two, line])
				i += 2
			else:
				_toks.append(["op", ch, line])
				i += 1
	_toks.append(["eof", "", line])


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_ident_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c == "%" or c.unicode_at(0) > 127


# --- Parser-Hilfen ----------------------------------------------------------------

func _peek(o := 0) -> Array:
	return _toks[mini(_i + o, _toks.size() - 1)]


func _next() -> Array:
	var t: Array = _toks[_i]
	_i = mini(_i + 1, _toks.size() - 1)
	return t


func _is_op(v: String, o := 0) -> bool:
	var t := _peek(o)
	return t[0] == "op" and t[1] == v


func _is_kw(v: String, o := 0) -> bool:
	var t := _peek(o)
	return t[0] == "id" and String(t[1]).to_upper() == v


func _accept_op(v: String) -> bool:
	if _is_op(v):
		_next()
		return true
	return false


func _expect_op(v: String) -> void:
	if not _accept_op(v):
		_err("'%s' erwartet, gefunden '%s'" % [v, _peek()[1]])


func _err(msg: String) -> void:
	errors.append("%s:%d: %s" % [source_name, _peek()[2], msg])
	# Fehlerbehandlung: bis zum nächsten ; oder } springen
	while _peek()[0] != "eof" and not _is_op(";") and not _is_op("}"):
		_next()
	_accept_op(";")


func _emit(op: Array) -> int:
	ops.append(op)
	return ops.size() - 1


# --- Programm / Anweisungen -------------------------------------------------------

func _parse_program() -> void:
	while _peek()[0] != "eof":
		var before := _i
		_statement()
		if _i == before:
			_next()   # Sicherheitsnetz gegen Endlosschleifen
	_emit(["end"])
	for g in _pending_gotos:
		var lab: String = g[1]
		if labels.has(lab):
			ops[g[0]][1] = labels[lab]
		else:
			errors.append("%s: Sprungmarke '%s' fehlt" % [source_name, lab])
			ops[g[0]][1] = ops.size() - 1


func _block_or_statement() -> void:
	if _accept_op("{"):
		while _peek()[0] != "eof" and not _is_op("}"):
			var before := _i
			_statement()
			if _i == before:
				_next()
		_expect_op("}")
	else:
		_statement()


func _statement() -> void:
	var t := _peek()
	if t[0] == "op":
		if _accept_op(";"):
			return
		if _is_op("{"):
			_block_or_statement()
			return
		_err("unerwartetes Zeichen '%s'" % t[1])
		return
	if t[0] != "id":
		_err("Anweisung erwartet")
		return
	var word := String(t[1]).to_upper()
	if word == "BLOCK":
		_next()
		_emit(["atomic", true])
		_block_or_statement()
		_emit(["atomic", false])
	elif word == "IF":
		_parse_if()
	elif word == "GOTO":
		_next()
		var lab := String(_next()[1]).to_upper()
		_pending_gotos.append([_emit(["jmp", -1]), lab])
		_accept_op(";")
	elif word == "GOSUB":
		_next()
		var lab2 := String(_next()[1]).to_upper()
		_pending_gotos.append([_emit(["gosub", -1]), lab2])
		_accept_op(";")
	elif word == "RETURN":
		_next()
		_emit(["return"])
		_accept_op(";")
	elif word == "LABEL":
		_next()
		var lab := String(_next()[1]).to_upper()
		labels[lab] = ops.size()
		_accept_op(":")
	elif word == "WHENEVER":
		_parse_whenever()
	elif word in HANDLERS:
		_parse_handler(word)
	elif word in DECL_TYPES and _peek(1)[0] == "id":
		_parse_decl(word)
	elif _peek(1)[0] == "op" and _peek(1)[1] == ":" :
		# "Name:" als Sprungmarke
		_next()
		_next()
		labels[word] = ops.size()
	elif _is_op("(", 1):
		var call := _parse_call()
		_emit(["call", call[1], call[2], t[2]])
		_accept_op(";")
	elif _is_op("=", 1):
		_next()
		_next()
		_emit(["assign", word, _expr()])
		_accept_op(";")
	else:
		_err("unbekannte Anweisung '%s'" % t[1])


func _parse_if() -> void:
	_next()
	# Bedingung meist geklammert; einige Originalskripte lassen die Klammern weg
	var cond := _expr()
	_accept_op(";")
	var jf := _emit(["jmpf", cond, -1])
	_block_or_statement()
	if _is_kw("ELSE"):
		_next()
		var jend := _emit(["jmp", -1])
		ops[jf][2] = ops.size()
		_block_or_statement()
		ops[jend][1] = ops.size()
	else:
		ops[jf][2] = ops.size()


func _parse_whenever() -> void:
	_next()
	var name := "_ANON%d" % whenevers.size()   # "Whenever(Bed)" ohne Namen
	if not _is_op("("):
		name = String(_next()[1]).to_upper()
	_expect_op("(")
	var cond := _expr()
	_accept_op(";")
	_expect_op(")")
	var skip := _emit(["jmp", -1])
	whenevers[name] = {"cond": cond, "pc": ops.size()}
	_block_or_statement()
	ops[skip][1] = ops.size()


func _parse_handler(word: String) -> void:
	_next()
	var key := word
	if _accept_op("("):
		if not _is_op(")"):
			var arg := _expr()
			if arg[0] == "num":
				key = "%s:%d" % [word, int(arg[1])]
		_accept_op(";")
		_expect_op(")")
	var skip := _emit(["jmp", -1])
	handlers[key] = ops.size()
	_block_or_statement()
	ops[skip][1] = ops.size()


func _parse_decl(kind: String) -> void:
	_next()
	while true:
		var name := String(_next()[1]).to_upper()
		var init = null
		if _accept_op("="):
			init = _expr()
		_emit(["decl", name, kind, init])
		if not _accept_op(","):
			break
	_accept_op(";")


func _parse_call() -> Array:
	var name := String(_next()[1]).to_upper()
	_expect_op("(")
	var args: Array = []
	while not _is_op(")") and _peek()[0] != "eof":
		if _accept_op(";"):
			continue
		args.append(_expr())
		if not _accept_op(","):
			_accept_op(";")
			if not _is_op(")"):
				break
	_expect_op(")")
	return ["call", name, args]


# --- Ausdrücke ---------------------------------------------------------------------

func _expr() -> Array:
	var a := _and_expr()
	while _is_kw("OR") or _is_op("||"):
		_next()
		a = ["bin", "OR", a, _and_expr()]
	return a


func _and_expr() -> Array:
	var a := _not_expr()
	while _is_kw("AND") or _is_op("&&"):
		_next()
		a = ["bin", "AND", a, _not_expr()]
	return a


func _not_expr() -> Array:
	if _is_op("!") or _is_kw("NOT"):
		_next()
		return ["not", _not_expr()]
	return _cmp_expr()


func _cmp_expr() -> Array:
	var a := _add_expr()
	for op in ["==", "!=", "<=", ">=", "<", ">", "<>"]:
		if _is_op(op):
			_next()
			return ["bin", "!=" if op == "<>" else op, a, _add_expr()]
	return a


func _add_expr() -> Array:
	var a := _mul_expr()
	while _is_op("+") or _is_op("-"):
		var op: String = _next()[1]
		a = ["bin", op, a, _mul_expr()]
	return a


func _mul_expr() -> Array:
	var a := _unary()
	while _is_op("*") or _is_op("/"):
		var op: String = _next()[1]
		a = ["bin", op, a, _unary()]
	return a


func _unary() -> Array:
	if _accept_op("-"):
		return ["neg", _unary()]
	return _primary()


func _primary() -> Array:
	var t := _peek()
	if t[0] == "num":
		_next()
		return ["num", float(t[1]) if "." in String(t[1]) else int(String(t[1]).to_int())]
	if t[0] == "str":
		_next()
		return ["str", t[1]]
	if _accept_op("("):
		var e := _expr()
		_accept_op(";")
		_expect_op(")")
		return e
	if t[0] == "id":
		var w := String(t[1]).to_upper()
		if w == "TRUE":
			_next()
			return ["num", 1]
		if w == "FALSE":
			_next()
			return ["num", 0]
		if _is_op("(", 1):
			return _parse_call()
		_next()
		return ["var", w]
	_err("Ausdruck erwartet, gefunden '%s'" % t[1])
	return ["num", 0]
