extends "res://tests/probe_b044_stuck.gd"
## Gap-Analyse (09.11.2026): Skriptabläufe einer Originalmission beobachten – welche blockierenden Befehle
## (HUMAN_Move/Drive/BoardVehicle/Attack …) kommen an, welche laufen in die Zeitgrenze der VM (= Weg/Fahrt kommt nicht an),
## welche Skripte hängen am Ende noch. Baut auf probe_b044_stuck auf (Trupp unverwundbar, Ruhephase, Hotspots mit Schuss).
##   tools\run_locked.ps1 -Name gap -Log test_output\gap_<id>.log -GodotArgs "--headless -- --mission=<id> --autoplay=probe_gap_scripts --calm=120 --hotspots=4 --dwell=40"
## Ergebnis: test_output/gap_<mission>.txt, Zeilen BLOCK_OK / BLOCK_TIMEOUT / HAENGT, Summe GAP_SUMME.

var _blk := {}        ## LsVM -> {pc, cmd, args, t0}
var _done := {}       ## cmd -> [ok, timeout, max_s]
var _timeouts: Array = []


func _op_desc(vm: LsVM, pc: int) -> Array:
	if pc < 0 or pc >= vm.code.ops.size():
		return ["?", ""]
	var op: Array = vm.code.ops[pc]
	if op[0] != "call":
		return [str(op[0]), ""]
	var a := PackedStringArray()
	for e in op[2]:
		a.append(str(e[1]) if e is Array and e.size() > 1 else str(e))
	return [str(op[1]), ",".join(a)]


func _sample() -> void:
	super._sample()
	if _rt == null:
		return
	for vm in _rt.vms:
		var blocking: bool = vm.wait_until.is_valid() and not vm.ended
		var cur: Dictionary = _blk.get(vm, {})
		if not cur.is_empty() and (not blocking or vm.block_pc != int(cur["pc"]) or float(cur["t0"]) > _t):
			var dur := _t - float(cur["t0"])
			var cmd := String(cur["cmd"])
			var rec: Array = _done.get(cmd, [0, 0, 0.0])
			var to: bool = vm.wait_timeout <= 0.0 and not blocking
			if to:
				rec[1] += 1
				_timeouts.append("%s %s(%s) %.0f s" % [vm.name, cmd, cur["args"], dur])
				_log("BLOCK_TIMEOUT t=%.0f %s %s(%s) nach %.0f s" % [_t, vm.name, cmd, cur["args"], dur])
			else:
				rec[0] += 1
			rec[2] = maxf(rec[2], dur)
			_done[cmd] = rec
			_blk.erase(vm)
			cur = {}
		if blocking and cur.is_empty():
			var d := _op_desc(vm, vm.block_pc)
			_blk[vm] = {"pc": vm.block_pc, "cmd": d[0], "args": d[1], "t0": _t}


func _finish() -> void:
	_log("== BLOCKIERENDE BEFEHLE (fertig / Zeitgrenze / längste s)")
	for k in _done:
		_log("  %-28s ok=%d timeout=%d max=%.0f" % [k, _done[k][0], _done[k][1], _done[k][2]])
	_log("== HAENGT AM ENDE (blockiert)")
	var hang := 0
	for vm in _blk:
		var c: Dictionary = _blk[vm]
		_log("HAENGT %s %s(%s) seit %.0f s" % [vm.name, c["cmd"], c["args"], _t - float(c["t0"])])
		hang += 1
	var tot := 0
	for k in _done:
		tot += int(_done[k][1])
	var s := "GAP_SUMME mission=%s timeouts=%d haengt=%d" % [Game.cli.get("mission", "?"), tot, hang]
	_log(s)
	var f := FileAccess.open("res://test_output/gap_%s.txt" % Game.cli.get("mission", "x"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
	super._finish()
