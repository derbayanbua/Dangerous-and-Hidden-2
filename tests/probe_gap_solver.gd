extends "res://tests/test_orig_complete.gd"
## Gap-Analyse Tschechien (09.11.2026): Löser `test_orig_complete` (Trupp unverwundbar) durchläuft die Mission; dabei
## wird jede Skript-VM beobachtet: welche blockierenden Befehle (HUMAN_Move/Drive/BoardVehicle/Attack …) enden normal,
## welche laufen in die VM-Zeitgrenze (= Weg/Fahrt kommt nicht an), was hängt am Ende. Dazu Fahrzeugfahrten
## (Strecke, Reststrecke) und Gegner, die nie aus HUMAN_Suspend kamen.
##   tools\run_locked.ps1 -Name gapcz -Log test_output\gapcz_<id>.log -GodotArgs "--headless -- --mission=<id> --autoplay=probe_gap_solver"
## Ergebnis: test_output/gapcz_<mission>.txt (BLOCK_TIMEOUT / HAENGT / FAHRT / RUHEND / GAPCZ_SUMME).

var _gblk := {}        ## LsVM -> {pc, cmd, args, t0}
var _gdone := {}       ## cmd -> [ok, timeout, max_s]
var _glines: PackedStringArray = []
var _gt := 0.0
var _gacc := 0.0
var _veh := {}         ## Fahrzeug -> {start, max_d, last}
var _woke := {}        ## Soldat -> true (war einmal nicht suspendiert)


func _glog(s: String) -> void:
	print(s)
	_glines.append(s)


func _op_desc(vm: LsVM, pc: int) -> Array:
	if vm.code == null or pc < 0 or pc >= vm.code.ops.size():
		return ["?", ""]
	var op: Array = vm.code.ops[pc]
	if op[0] != "call":
		return [str(op[0]), ""]
	var a := PackedStringArray()
	for e in op[2]:
		a.append(str(e[1]) if e is Array and e.size() > 1 else str(e))
	return [str(op[1]), ",".join(a)]


func _physics_process(d: float) -> void:
	super._physics_process(d)
	if rt == null or not is_instance_valid(m):
		return
	_gt += d
	_gacc += d
	if _gacc < 0.25:
		return
	_gacc = 0.0
	for vm in rt.vms:
		var blocking: bool = vm.wait_until.is_valid() and not vm.ended
		var cur: Dictionary = _gblk.get(vm, {})
		if not cur.is_empty() and (not blocking or vm.block_pc != int(cur["pc"])):
			var dur := _gt - float(cur["t0"])
			var cmd := String(cur["cmd"])
			var rec: Array = _gdone.get(cmd, [0, 0, 0.0])
			if vm.wait_timeout <= 0.0 and not blocking:
				rec[1] += 1
				_glog("BLOCK_TIMEOUT t=%.0f %s %s(%s) nach %.0f s" % [_gt, vm.name, cmd, cur["args"], dur])
			else:
				rec[0] += 1
			rec[2] = maxf(rec[2], dur)
			_gdone[cmd] = rec
			_gblk.erase(vm)
			cur = {}
		if blocking and cur.is_empty():
			var dd := _op_desc(vm, vm.block_pc)
			_gblk[vm] = {"pc": vm.block_pc, "cmd": dd[0], "args": dd[1], "t0": _gt}
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not (v is Node3D) or not is_instance_valid(v):
			continue
		var r: Dictionary = _veh.get(v, {})
		if r.is_empty():
			r = {"start": v.global_position, "max_d": 0.0, "last": v.global_position}
		r["max_d"] = maxf(float(r["max_d"]), (v.global_position as Vector3).distance_to(r["start"]))
		r["last"] = v.global_position
		_veh[v] = r
	for e in m.enemies:
		if is_instance_valid(e) and e.alive:
			var b = e.get_node_or_null("EnemyBrain")
			if b and not b.suspended:
				_woke[e] = true


func _report() -> void:
	if _reported:
		return
	_glog("== BLOCKIERENDE BEFEHLE (fertig / Zeitgrenze / längste s)")
	for k in _gdone:
		_glog("  %-28s ok=%d timeout=%d max=%.0f" % [k, _gdone[k][0], _gdone[k][1], _gdone[k][2]])
	var hang := 0
	for vm in _gblk:
		var c: Dictionary = _gblk[vm]
		if is_instance_valid(vm) and String(c["cmd"]) not in ["Delay", "?"]:
			_glog("HAENGT %s %s(%s) seit %.0f s" % [vm.name, c["cmd"], c["args"], _gt - float(c["t0"])])
			hang += 1
	for v in _veh:
		if is_instance_valid(v):
			_glog("FAHRT %s max=%.0f m end=%s" % [v.name, _veh[v]["max_d"], str(_veh[v]["last"]).replace(" ", "")])
	var sleeping := PackedStringArray()
	if is_instance_valid(m):
		for e in m.enemies:
			if is_instance_valid(e) and e.alive and not _woke.has(e):
				sleeping.append(String(e.name))
	_glog("RUHEND (nie aus Suspend, lebend): %d %s" % [sleeping.size(), ", ".join(sleeping)])
	var tot := 0
	for k in _gdone:
		tot += int(_gdone[k][1])
	_glog("GAPCZ_SUMME mission=%s timeouts=%d haengt=%d t=%.0f" % [mid, tot, hang, _gt])
	var f := FileAccess.open("res://test_output/gapcz_%s.txt" % mid, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_glines))
		f.close()
	super._report()
