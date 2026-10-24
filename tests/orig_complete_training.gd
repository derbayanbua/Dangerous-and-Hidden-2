extends RefCounted
## TUTORIAL-Durchlauf für den Erfüllbarkeitslöser (tests/test_orig_complete.gd, Mission „training“).
## Das Original-Tutorial ist ein streng geordneter Parcours (orig_cache/tutorial/scripts): Ausbilder 1 Hindernisbahn →
## Ausbilder 2 Schießstand (4 Räume) → Ausbilder 6 Granaten/Bazooka → Ausbilder 8 Sprengstoff → dummy_order/Ausbilder 7
## Jeep → Ausbilder 9 Tauchen (Marke 247 holen, Tauchgerät am Becken lassen) → Jeep zurück → Teamarbeit (Befehle an
## T_panak_2..4: zu den Fässern, durch den Stacheldraht). Der allgemeine Löser läuft Auslöser nach Entfernung an und
## verlässt dabei den Hindernisparcours (T_dummy_AC_hint: zweimal außer 28 m → Ziel 1 verfehlt). Hier bedient ein
## Spielerersatz die Stationen in Originalreihenfolge über die Originalmechanik: Teleport an die Auslöser (wie der
## allgemeine Löser), Gegenstände aufheben, echte Projektile (Ballistics) auf die Zielscheiben, echte Granaten/
## Bazooka-Geschosse (Grenade mit Originaldaten), Sprengsätze anbringen, Jeep mit Trupp an Bord versetzen.
## Rückgabe von run(): true = Mission beendet.

var t      ## Testknoten (test_orig_complete.gd)
var m: OrigMission
var rt: LsRuntime
var log_prefix := "LOESER TUT "


func run(test) -> bool:
	t = test
	m = t.m
	rt = t.rt
	if await _obstacle_course():
		return true
	if await _range():
		return true
	if await _heavy():
		return true
	if await _explosives():
		return true
	if await _vehicle_and_diving():
		return true
	if await _teamwork():
		return true
	return t._done()


## Skriptvariable (Name ohne Groß-/Kleinschreibung), -1 = nicht vorhanden
func _vm_var(vm, nm: String) -> int:
	for k in vm.vars:
		if String(k).to_lower() == nm:
			var v = vm.vars[k]
			return int(v) if (v is int or v is float or v is bool) else -1
	return -1


func _p(s: String) -> void:
	print(log_prefix + s)


func _f(nm: String) -> Node3D:
	return rt.find_frame(nm)


func _lead() -> Soldier:
	return t._lead()


## Original-Zielstand: 0 aktiv, 1 erfüllt, 2 verfehlt, 3 inaktiv (Objective.State)
func _obj(idx: int) -> int:
	if not m.orig_objectives.has(idx):
		return -1
	var o: Objective = m.objective(m.orig_objectives[idx])
	return int(o.state) if o else -1


func _go(nm: String, wait := 1.5) -> bool:
	var f := _f(nm)
	if f == null:
		_p("Frame fehlt: " + nm)
		return await t._wait(0.1)
	t._teleport_to_pos(f.global_position)
	return await t._wait(wait)


func _go_pos(p: Vector3, wait := 1.5) -> bool:
	t._teleport_to_pos(p)
	return await t._wait(wait)


## Warten, bis cond() wahr ist (höchstens timeout s); true = Mission beendet
func _until(cond: Callable, timeout: float, step := 0.5) -> bool:
	var tt := 0.0
	while tt < timeout:
		if cond.call():
			return false
		if await t._wait(step):
			return true
		tt += step
	return false


func _world_item(id: int, near := Vector3.INF) -> OrigInteractive.OrigWorldItem:
	var best: OrigInteractive.OrigWorldItem = null
	var bd := INF
	for n in t.get_tree().get_nodes_in_group("world_items"):
		var wi := n as OrigInteractive.OrigWorldItem
		if wi == null or wi.item != id or not wi.can_interact(_lead()):
			continue
		var d := 0.0 if near == Vector3.INF else wi.global_position.distance_to(near)
		if d < bd:
			bd = d
			best = wi
	return best


## Gegenstand aufheben wie der Spieler (hingehen, Benutzen)
func _pick(id: int, near := Vector3.INF) -> bool:
	var wi := _world_item(id, near)
	if wi == null:
		_p("Gegenstand %d nicht gefunden" % id)
		return false
	t._teleport_to_pos(wi.global_position + Vector3(0.6, 0.0, 0.0))
	await t.frames(2)
	var lead := _lead()
	lead.global_position = wi.global_position + Vector3(0.6, 0.0, 0.0)
	wi.interact(lead)
	_p("Gegenstand %d aufgehoben (%s)" % [id, wi.name])
	await t._wait(0.5)
	return true


func _has(id: int) -> bool:
	for s in m.squad.alive_members():
		if (s as Soldier).get_meta("orig_items", []).has(id):
			return true
	return false


## Echter Schuss (Ballistics, Originalwaffe in der Hand) aus 4 m auf die Mitte des Frames
func _shoot_at(f: Node3D, wid: int) -> void:
	var lead := _lead()
	var c := OrigInteractive.world_aabb(f).get_center()
	var data := WeaponDB.from_orig(wid)
	if data == null:
		_p("keine Waffendaten für %d" % wid)
		return
	var dir := (c - lead.global_position).normalized()
	var from := c - dir * 4.0
	var ex: Array[RID] = []
	for s in m.squad.members:
		ex.append((s as Soldier).get_rid())
	Ballistics.fire(lead, from, (c - from).normalized(), data, ex, lead.team)


## Zielscheiben einer Reihe (dummy_targetN schaltet sie nacheinander ein): jede sichtbare beschießen, bis die Reihe
## durch ist (done.call() wahr). Ersatz bei Wirkungslosigkeit (Blocker): Explosion an der Scheibe.
var shots_without_effect := 0


func _shoot_row(names: Array, wid: int, done: Callable, timeout := 90.0) -> bool:
	var tt := 0.0
	var tries := {}
	while tt < timeout and not done.call():
		for nm in names:
			var f := _f(nm)
			if f == null or not f.is_visible_in_tree():
				continue
			if f.has_meta("tut_down"):
				continue
			tries[nm] = int(tries.get(nm, 0)) + 1
			if int(tries[nm]) <= 3:
				_shoot_at(f, wid)
			elif int(tries[nm]) == 4:
				shots_without_effect += 1
				_p("Zielscheibe %s reagiert nicht auf Beschuss -> Ersatz Explosion (Blocker)" % nm)
				var br = f.get_meta("script_breakable") if f.has_meta("script_breakable") else null
				if br:
					br.on_explosion(100.0, _lead())
				f.set_meta("tut_down", true)
		if await t._wait(0.8):
			return true
		tt += 0.8
	return false


## Granate/Bazooka-Geschoss mit Originaldaten am Ziel zünden (wie ein Treffer)
func _blast_at(p: Vector3, item: int) -> void:
	var g := Grenade.new()
	g.data = WeaponDB.from_orig(item)
	if g.data == null:
		_p("keine Waffendaten für %d" % item)
		g.free()
		return
	g.thrower = _lead()
	g.team = _lead().team
	g.impact = item == 39
	m.add_child(g)
	g.global_position = p + Vector3.UP * 0.3
	g.explode()


func _door(nm: String) -> OrigInteractive.OrigDoor:
	var f := _f(nm)
	if f and f.has_meta("orig_ctl"):
		return f.get_meta("orig_ctl") as OrigInteractive.OrigDoor
	return null


# --- 1. Hindernisbahn (Ziel 1) -------------------------------------------------------------------------------

func _obstacle_course() -> bool:
	_p("Hindernisbahn")
	if await t._wait(2.0):
		return true
	# Reihenfolge wie die Strecke: Schlangenlauf (SW1-3), Laufplanken (LA1/2), Barrieren + Leiterwand (BA1-5),
	# Gräben (ZA1/2), Stacheldraht (WI). Zählerskripte verwerfen bei schnellem Folgeereignis den laufenden Ablauf
	# (TUT_Instructor1_aid: Delay(3000) vor MOC+1) -> je Abschnitt 4,5 s Pause wie ein Spieler.
	for grp in [["dummy_SW1", "dummy_SW2", "dummy_SW3"], ["dummy_LA1", "dummy_LA2"],
			["dummy_BA1_1", "dummy_BA2", "dummy_BA3", "dummy_BA4", "dummy_BA5"], ["dummy_ZA1", "dummy_ZA2"], ["dummy_WI"]]:
		for nm in grp:
			if await _go(nm, 1.2):
				return true
		if await t._wait(4.5):
			return true
	if await _until(func(): return _obj(1) != 0, 20.0):
		return true
	_p("Ziel 1 Stand %d" % _obj(1))
	return false


# --- 2. Schießstand (Ziel 2) ---------------------------------------------------------------------------------

func _range() -> bool:
	_p("Schießstand")
	var i2 := _f("TUT_Instructor2")
	# Ausbilder 2 geht nach Signal 10 zu BD1 und wartet (PIR 4 m)
	if await _until(func(): return i2.global_position.distance_to(_f("BD1").global_position if _f("BD1") else i2.global_position) < 2.0, 30.0):
		return true
	if await _go_pos(i2.global_position + Vector3(1.0, 0.0, 0.0), 3.0):
		return true
	# Er geht zu D1_Instr; Spieler betritt Raum 1 (dummy_WCR1, 2 m) -> Erklärung, dann erste Scheibe
	if await _until(func(): return _f("D1_Instr") == null or i2.global_position.distance_to(_f("D1_Instr").global_position) < 1.5, 40.0):
		return true
	if await _go("dummy_WCR1", 1.0):
		return true
	await _pick(2)          # Colt 1911
	if await _go("dummy_WCR1", 1.0):
		return true
	var rows := [
		[["m_tut_panak_1", "m_tut_panak_11", "m_tut_panak_12", "m_tut_panak_13", "m_tut_panak_14"], 2, "dummy_WCR2", [20, 28]],
		[["m_tut_panak_2", "m_tut_panak_21", "m_tut_panak_22", "m_tut_panak_23", "m_tut_panak_24"], 20, "dummy_WCR3", [15]],
		[["m_tut_panak_3", "m_tut_panak_31", "m_tut_panak_32", "m_tut_panak_33", "m_tut_panak_34"], 15, "dummy_WCR4", []],
		[["m_tut_panak_4", "m_tut_panak_41", "m_tut_panak_42", "m_tut_panak_43", "m_tut_panak_44"], 15, "", []]]
	for ri in rows.size():
		var names: Array = rows[ri][0]
		var last := names[names.size() - 1] as String
		# Reihe beginnt, wenn die erste Scheibe aufgestellt ist (Ausbilder spricht vorher)
		if await _until(func(): return _f(names[0]) != null and _f(names[0]).is_visible_in_tree(), 60.0):
			return true
		_p("Reihe %d aktiv" % (ri + 1))
		var vm_done := func():
			var lf := _f(last)
			return lf != null and lf.has_meta("tut_down") or (rt.vm_for(lf) != null and rt.vm_for(lf).terminated)
		if await _shoot_row(names, rows[ri][1], vm_done):
			return true
		_p("Reihe %d fertig" % (ri + 1))
		if rows[ri][2] == "":
			break
		# Ausbilder nimmt die Waffen ab, öffnet die nächste Tür und geht weiter; Spieler folgt in den nächsten Raum
		if await t._wait(6.0):
			return true
		if await _go(rows[ri][2], 1.5):
			return true
		for it in rows[ri][3]:
			await _pick(it)
		if await _go(rows[ri][2], 1.0):
			return true
	if await _until(func(): return _obj(2) != 0, 30.0):
		return true
	_p("Ziel 2 Stand %d" % _obj(2))
	return false


# --- 3. Granaten/Bazooka (Ziel 3) ------------------------------------------------------------------------------

func _heavy() -> bool:
	_p("Granaten/Bazooka")
	var i6 := _f("TUT_Instructor6")
	if await _go_pos(i6.global_position + Vector3(1.5, 0.0, 0.0), 12.0):
		return true
	await _pick(39)
	await _pick(60)
	await _pick(62)
	var targets := ["m_tut_panak_5", "m_tut_panak_6", "m_tut_panak_7", "m_tut_panak_8", "la_bar_01", "la_Tut_tancik_01"]
	for nm in targets:
		var f := _f(nm)
		if f == null:
			_p("Ziel fehlt: " + nm)
			continue
		var c := OrigInteractive.world_aabb(f).get_center()
		_blast_at(c, 39 if nm == "la_Tut_tancik_01" else 62)
		_p("Explosion an %s" % nm)
		if await t._wait(2.0):
			return true
	if await _until(func(): return _obj(3) != 0, 20.0):
		return true
	_p("Ziel 3 Stand %d" % _obj(3))
	return false


# --- 4. Sprengstoff (Ziel 4) -----------------------------------------------------------------------------------

func _explosives() -> bool:
	_p("Sprengstoff")
	var i8 := _f("TUT_Instructor8")
	if await _go_pos(i8.global_position + Vector3(1.0, 0.0, 0.0), 2.0):
		return true
	# Er führt über EX_1..4 (PIR2 5 m)
	var ex4 := _f("EX_4")
	if ex4 and await _until(func(): return i8.global_position.distance_to(ex4.global_position) < 1.5, 40.0):
		return true
	if await _go_pos(i8.global_position + Vector3(1.0, 0.0, 0.0), 6.0):
		return true
	for k in 3:
		await _pick(67)
	var lead := _lead()
	for nm in ["d_ebplace_1", "d_ebplace_2", "d_ebplace_3"]:
		var f := _f(nm)
		var ex: OrigInteractive.OrigExplosive = f.get_meta("orig_ctl") if f and f.has_meta("orig_ctl") else null
		if ex == null:
			_p("Sprengplatz fehlt: " + nm)
			continue
		t._teleport_to_pos(ex.global_position + Vector3(0.8, 0.0, 0.0))
		await t.frames(2)
		lead.global_position = ex.global_position + Vector3(0.8, 0.0, 0.0)
		if not ex.can_interact(lead):
			_p("%s nicht benutzbar (Zustand %d)" % [nm, ex.state])
			continue
		ex.interact(lead)
		for i in 40:
			await t.frames(10)
			lead.global_position = ex.global_position + Vector3(0.8, 0.0, 0.0)
			if ex.state == 1:
				break
		_p("%s Zustand %d, Zünder %.0f s" % [nm, ex.state, ex.countdown])
	# hinter die Schutzmauer zurück (Ausbilder) und die 30-s-Zünder abwarten
	if await _go_pos(i8.global_position + Vector3(1.0, 0.0, 0.0), 1.0):
		return true
	if await _until(func(): return _obj(4) != 0, 60.0):
		return true
	_p("Ziel 4 Stand %d" % _obj(4))
	return false


# --- 5./6. Jeep und Tauchen ------------------------------------------------------------------------------------

func _jeep() -> Vehicle:
	return _f("jeep") as Vehicle


func _drive_to(p: Vector3, wait := 1.5) -> bool:
	var v := _jeep()
	if v == null:
		return await _go_pos(p, wait)
	for s in m.squad.alive_members():
		if (s as Soldier).vehicle == null:
			v.board(s, s == _lead())
	v.freeze = true
	v.global_position = p + Vector3.UP * 0.6
	if await t._wait(0.3):
		return true
	v.freeze = false
	return await t._wait(wait)


func _leave_jeep() -> void:
	var v := _jeep()
	if v:
		v.leave_all()


func _vehicle_and_diving() -> bool:
	_p("Jeep/Tauchen")
	if await _go("dummy_order", 2.0):
		return true
	var i7 := _f("TUT_Instructor7")
	if await _go_pos(i7.global_position + Vector3(1.0, 0.0, 0.0), 12.0):
		return true
	var v := _jeep()
	if v == null:
		_p("Jeep fehlt")
		return false
	# mit dem Jeep weg (> 20 m vom Ausbilder, CarIsAway) und zum Taucherausbilder
	var i9 := _f("TUT_Instructor9")
	if await _drive_to(v.global_position + (i9.global_position - v.global_position).normalized() * 40.0, 3.0):
		return true
	if await _drive_to(i9.global_position + Vector3(4.0, 0.0, 0.0), 2.0):
		return true
	_leave_jeep()
	if await _go_pos(i9.global_position + Vector3(1.0, 0.0, 0.0), 20.0):
		return true
	# Canyon (8 m) -> Signal 17: Tor auf, Ausbilder geht zu I9CSC, Rückkehr-Abfrage an
	if await _go("T_dummy_canyon", 3.0):
		return true
	await _pick(231)                 # Tauchgerät
	var tag := _world_item(247)
	if tag:
		await _pick(247)             # Erkennungsmarke unter Wasser
	# Tauchgerät am Becken zurücklassen (t_dummy_bubly prüft _ItemInRange(231, 20))
	var bub := _f("T_dummy_bubly")
	if bub:
		t._teleport_to_pos(bub.global_position + Vector3(0.0, 1.0, 0.0))
		await t.frames(2)
	var lead := _lead()
	var dropped := false
	for from in ["items"] + FieldInventory.SLOTS:
		if FieldInventory.count_at(FieldInventory.view(lead), from, 231) > 0:
			var err := FieldInventory.drop(lead, from, 231)
			_p("Tauchgerät abgelegt (%s) %s" % [from, err])
			dropped = err == ""
			break
	if not dropped:
		_p("Tauchgerät nicht abgelegt")
	if await _go("T_dummy_canyon", 3.0):
		return true
	if await _go_pos(i9.global_position + Vector3(0.8, 0.0, 0.0), 12.0):
		return true
	if await _until(func(): return _obj(6) != 0, 20.0):
		return true
	_p("Ziel 6 Stand %d" % _obj(6))
	# Jeep zurück zu Ausbilder 7 (PIRBACK: Spieler und Jeep je < 10 m)
	v = _jeep()
	if v:
		t._teleport_to_pos(v.global_position + Vector3(2.0, 0.0, 0.0))
		await t.frames(2)
	if await _drive_to(i7.global_position + Vector3(5.0, 0.0, 0.0), 2.0):
		return true
	_leave_jeep()
	if await _go_pos(i7.global_position + Vector3(1.5, 0.0, 0.0), 6.0):
		return true
	if await _until(func(): return _obj(5) != 0, 20.0):
		return true
	_p("Ziel 5 Stand %d" % _obj(5))
	return false


# --- 7./8. Teamarbeit ------------------------------------------------------------------------------------------

func _teamwork() -> bool:
	_p("Teamarbeit")
	if await _until(func(): return _obj(7) != 0, 30.0):
		return true
	_p("Ziel 7 Stand %d, Ziel 8 Stand %d" % [_obj(7), _obj(8)])
	# Ausbilder 1 (TPIR 10 m) gibt den Befehl: Soldaten zu den Fässern (la_bar_20), dann durch den Draht (dummy_WI)
	var i1 := _f("TUT_Instructor1")
	if await _go_pos(i1.global_position + Vector3(1.5, 0.0, 0.0), 12.0):
		return true
	# Wer zu den Fässern muss, bestimmt das Original: tut_playersspawned zählt die Spieler (= Teammitglieder _PLAYER_ n),
	# la_bar_20 (barel2.scr) weist bareller_N/Wires_N zu: 1 Spieler → T_panak_2..4, 4 Spieler → eigene Kameraden
	# _PLAYER_ 1..3 (bareller_4.scr). Die Soldaten-Frames stehen in den Variablen des zugewiesenen Skripts.
	if await t._wait(3.0):
		return true
	var npcs: Array = []
	var bvm = rt.vm_for(_f("dummy_bareller")) if _f("dummy_bareller") else null
	if bvm:
		for k in bvm.vars:
			var s := bvm.vars[k] as Soldier
			if s and s.alive and not npcs.has(s) and s != _lead():
				npcs.append(s)
	if npcs.is_empty():
		for nm in ["T_panak_2", "T_panak_3", "T_panak_4"]:
			var s := _f(nm) as Soldier
			if s and s.alive:
				npcs.append(s)
	_p("Teamsoldaten: %s (%s)" % [", ".join(npcs.map(func(x): return String(x.name))), bvm.name if bvm else "?"])
	# Befehl „dorthin bewegen“: die Soldaten laufen zu den Fässern (FRAMEINRANGE < 4) und durch den Stacheldraht
	# bareller_N/Wires_N messen _FrameInRange(Soldat) < 4 vom Skriptträger dummy_bareller bzw. dummy_WI_players.
	# Wie ein befolgter Halten-Befehl bleiben sie dort (Teleport je 0,5 s wiederholt, sonst folgt die Trupp-KI dem Führer).
	for target in ["dummy_bareller", "dummy_WI_players"]:
		var tf := _f(target)
		if tf == null:
			continue
		var hold := func():
			for i in npcs.size():
				var s := npcs[i] as Soldier
				if s.global_position.distance_to(tf.global_position) > 2.5:
					s.global_position = tf.global_position + Vector3(float(i) - 1.0, 0.3, 0.8)
					s.velocity = Vector3.ZERO
			return false
		for k in 14:
			hold.call()
			if await t._wait(0.5):
				return true
		if target == "dummy_bareller":
			# dummy_timer OnSignal(1) spricht 5 s (Delay(5000)) und setzt erst danach Part1Ok; ein neues Signal (2 vom
			# Stacheldraht) unterbricht den laufenden Ablauf (ls_vm) -> Part1Ok bliebe 0. Ein Spieler braucht für den
			# Befehl „durch den Draht“ ohnehin länger: warten, bis Part1Ok gesetzt ist.
			var tm := _f("dummy_timer")
			var part1 := func():
				hold.call()
				return tm != null and rt.vm_for(tm) != null and _vm_var(rt.vm_for(tm), "part1ok") == 1
			if await _until(part1, 20.0):
				return true
			_p("Fässer: Part1Ok %d" % (_vm_var(rt.vm_for(tm), "part1ok") if tm and rt.vm_for(tm) else -1))
	if await _until(func(): return _obj(8) == 1, 30.0):
		return true
	_p("Ziel 8 Stand %d" % _obj(8))
	return await t._wait(5.0)
