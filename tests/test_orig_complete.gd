extends "res://tests/test_gameplay.gd"
## Erfüllbarkeit eines Original-Einsatzes (alle 24 Kampagnenteile):
##   tools\godot.cmd --headless -- --mission=<id> --autoplay=test_orig_complete
## Ein Löser bedient die Originalmechanik statt Wegfindung per Teleport: Bereichsauslöser der Originalskripte anlaufen
## (_PlayerInRange/_AllPlayersInRange …), Gegenstände aufheben, Schalter/Funkgeräte/Foto-/Dokumentplätze benutzen,
## Sprengsätze anbringen und zünden, Leichen durchsuchen, Gegner ausschalten, Skriptziele (OnDeath) zerstören, mit
## Fahrzeugen die Zielpunkte anfahren. Trupp und verbündete NPCs sind unverwundbar. Runde 1–2 „leise“ (Gegner
## ohne Sicht/Gehör), Runde 3 normal. Ausgabe: ERFUELLBAR-Zeile je Mission (tools/run_completability.ps1 → Tabelle).
## Statisch: Ziele ohne SetObjectiveStatus(i, 1) in den Skripten werden als „kein Erfolgspfad im Skript“ gemeldet.

var m: OrigMission
var rt: LsRuntime
var mid := ""
var stealth := true
var god := true
var notes: Array[String] = []
var _t0 := 0
var _start_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(float(Game.cli.get("limit", "2400")), true, false, true).timeout.connect(func():
		notes.append("Zeitlimit des Lösers")
		_report())
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	if m == null or not is_instance_valid(m):
		return
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive:
			continue
		if s.team != Soldier.TEAM_AXIS and god:
			s.health = s.max_health
		elif s.team == Soldier.TEAM_AXIS and stealth:
			var per: Perception = s.get_node_or_null("Perception")
			if per:
				per.sight_range = 0.01
				per.hear_range = 0.0
				per.awareness.clear()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	# Laden (MissionLoader, Ladebildschirm) kann bei großen Karten Minuten dauern: nach Zeit warten, nicht nach Bildern
	while Time.get_ticks_msec() - _t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission() as OrigMission
	mid = Game.current_mission_id
	if m == null or m.runtime == null:
		notes.append("Mission nicht geladen")
		_report()
		return
	rt = m.runtime
	rt.auto_skip = true
	_start_pos = m.squad.leader().global_position
	Events.mission_finished.connect(_on_mission_finished)
	for s in m.squad.members:
		var sb = m.squad.brain_of(s)
		if sb:
			sb.roe = SquadBrain.ROE.HOLD_FIRE     # Kameraden schießen nicht selbst (kein Alarm durch Streufeuer)
		s.max_health = 100000.0      # unverwundbar auch gegen Einzeltreffer > Gesundheit
		s.health = s.max_health
		s.died.connect(_on_squad_died)
	Engine.time_scale = float(Game.cli.get("speed", "2"))
	notes.append("Strategie " + String(Game.cli.get("strategy", "kampf")))
	await seconds(1.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(2.0)
	var finished := false
	# TUTORIAL: streng geordneter Parcours mit Fehlschlag beim Verlassen der Hindernisbahn -> eigener Stationsablauf
	if mid == "training":
		finished = await load("res://tests/orig_complete_training.gd").new().run(self)
	# (TUTORIAL: keine allgemeinen Runden – sie töten den Beckenwächter, OnDeath → Ziel 7 verfehlt)
	for rnd in (0 if finished or mid == "training" else 3):
		stealth = rnd < 2
		if await _round(rnd):
			finished = true
			break
	if not finished:
		await _follow_up()
	_report()


## Zielstand als Text (für Fortschrittserkennung)
func _objective_state() -> String:
	var st := ""
	for idx in m.orig_objectives:
		var o: Objective = m.objective(m.orig_objectives[idx])
		if o:
			st += "%d:%d " % [idx, o.state]
	return st


## Nachlauf: skriptgesteuerte Abläufe brauchen Zeit (Wellen, die nach und nach geweckt werden, Fahrten, Verzögerungs-
## ketten wie CZECH3 Mrtvoler → Opeler → Vybihac, NORMANDY2 Blue-Welle → Panzerfahrt). Alle 20 s neue Gegner
## ausschalten und Auslösepunkte erneut anlaufen; Ende, wenn sich 4 Durchgänge lang nichts mehr ändert.
func _follow_up() -> void:
	var last := _objective_state()
	var still := 0
	var last_alive := -1
	for i in 16:
		if _done():
			return
		var alive_before := m.enemies.filter(func(e): return is_instance_valid(e) and e.alive and not e.has_meta("hands_up")).size()
		_kill_enemies(true)
		for p in _trigger_points():
			_teleport_squad(p)
			if await _wait(0.5):
				return
		_loot_all()
		# Funkgeräte, die ein Skript wieder freigibt (ARCTIC4: Meldung an die Zentrale am Ende), neue Gegenstände
		if await _interact_all(false):
			return
		if await _wait(20.0):
			return
		var now := _objective_state()
		if now != last or alive_before != last_alive:
			still = 0
		else:
			still += 1
		last = now
		last_alive = alive_before
		print("LOESER Nachlauf %d: %s(%d Gegner neu)" % [i + 1, now, alive_before])
		if still >= 4:
			return


## Missionsende: sofort berichten, solange die Mission noch existiert (danach wechselt die Szene)
func _on_mission_finished(_success: bool, _reason: String) -> void:
	_report.call_deferred()


func _on_squad_died(x: Soldier) -> void:
	print("LOESER Tod ", x.name, " durch ", x.last_attacker.name if is_instance_valid(x.last_attacker) else "Skript/Fall",
		" bei ", x.global_position)
	print_stack()
	notes.append("Tod %s" % x.name)


func _done() -> bool:
	return not is_instance_valid(m) or m.finished


func _wait(s: float) -> bool:
	await seconds(s)
	if is_instance_valid(rt) and rt.in_cutscene:
		rt.end_cutscene()
	return _done()


## Eine Runde aller Lösungsschritte; true = Mission beendet
func _round(r: int) -> bool:
	print("LOESER Runde %d (%s), %.0f s" % [r + 1, "leise" if r < 2 else "normal", (Time.get_ticks_msec() - _t0) / 1000.0])
	# Türen mit OnUse-Skript zuerst benutzen (z. B. ALPS2: beim Offizier anklopfen, sonst läuft seine 90-s-Frist ab)
	if r == 0 and await _use_scripted_doors():
		return true
	if r == 0 and await _follow_guides():
		return true
	# Strategie „kampf“ (Standard): Gegner zuerst ausschalten (verhindert z. B. ARCTIC4: Offizier läuft zum U-Boot) –
	# außer „geschützten“ (Name in einem Skript mit Fehlschlag-Pfad); Strategie „leise“ (--strategy=leise, z. B. NORWAY
	# „keinen Alarm auf der Tirpitz“): erst in Runde 3 töten
	var leise := String(Game.cli.get("strategy", "kampf")) == "leise"
	if r == 0:
		_capture_candidates()
		if not leise:
			_kill_enemies(true)
		if await _wait(2.0):
			return true
	for p in _trigger_points():
		_teleport_squad(p)
		if await _wait(1.0):
			return true
	if await _interact_all(r == 0):
		return true
	if await _shoot_targets():
		return true
	_loot_all()
	if r >= (2 if leise else 1):
		_kill_enemies(r == 1)
		if await _wait(3.0):
			return true
		_loot_all()
		for p in _trigger_points():
			_teleport_squad(p)
			if await _wait(1.0):
				return true
	if r >= 2:
		await _destroy_script_targets()
		if await _wait(3.0):
			return true
		if await _vehicle_tour():
			return true
	return await _wait(3.0)


func _use_scripted_doors() -> bool:
	var lead := _lead()
	if lead == null:
		return true
	for n in get_tree().get_nodes_in_group("interactables"):
		var d := n as OrigInteractive.OrigDoor
		if d == null or not is_instance_valid(d.frame):
			continue
		var vm = rt.vm_for(d.frame)
		if vm == null or not vm.code.handlers.has("ONUSE"):
			continue
		# nur Türen, deren OnUse etwas auslöst (Signal/Ziel) – nicht reine Lichtkarten-/Zustandstüren
		var sf := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
		if sf == null or RegEx.create_from_string("(?is)OnUse\\s*\\(\\s*\\)\\s*\\{[^}]*(SendSignal|SetObjectiveStatus)").search(sf.get_as_text()) == null:
			continue
		_teleport_to_pos(d.global_position + Vector3(0, 0, 1.2))
		await frames(2)
		if d.locked:
			d.locked = false
		var snap := _range_snapshot()
		d.interact(lead)
		print("LOESER Tür %s benutzt" % d.frame.name)
		if await _wait(3.0):
			return true
		# Plätze hinter der Tür sofort bedienen (ALPS2: Offizier wartet nach dem Anklopfen nur kurz auf die Dokumente
		# am Dokumentenplatz, dann telefoniert er → Alarm)
		for nd in get_tree().get_nodes_in_group("interactables"):
			var pl := nd as OrigInteractive.OrigPlace
			if pl and pl.global_position.distance_to(d.global_position) < 25.0 and pl.can_interact(lead):
				_teleport_to_pos(pl.global_position + Vector3(0.8, 0, 0))
				lead.global_position = pl.global_position + Vector3(0.8, 0.0, 0.0)
				await frames(2)
				if pl.can_interact(lead):
					pl.interact(lead)
					print("LOESER Platz %s bedient" % pl.name)
					if await _wait(3.0):
						return true
		if await _follow_new_triggers(snap):
			return true
	return false


## Aktive Whenever-Bedingungen in Skripten mit Spielernähe-Abfrage (Schlüssel „Skriptindex:Name“)
func _range_snapshot() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(?i)_(All)?PlayersInRange|_PlayerInRange")
	for i in rt.vms.size():
		var vm = rt.vms[i]
		if vm.terminated or not is_instance_valid(vm.me):
			continue
		var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
		if f == null or re.search(f.get_as_text()) == null:
			continue
		for w in vm.whenever_active:
			if vm.whenever_active[w]:
				out["%d:%s" % [i, w]] = vm.me
	return out


## Nach einer Aktion neu aktivierte Spielernähe-Abfragen anlaufen und dort warten (ALPS2: „Gehen Sie ins Lager und
## warten Sie auf die Soldaten“ – Detektor wird erst nach dem Dialog des Offiziers eingeschaltet)
func _follow_new_triggers(before: Dictionary) -> bool:
	var obj0 := _objective_state()
	for i in 20:
		if await _wait(2.0):
			return true
		var now := _range_snapshot()
		var fresh: Array = []
		for k in now:
			if not before.has(k) and not fresh.has(now[k]):
				fresh.append(now[k])
		if not fresh.is_empty():
			for own in fresh:
				print("LOESER neuer Auslöser ", (own as Node).name)
				_teleport_to_pos((own as Node3D).global_position)
				if await _wait(30.0):
					return true
			return false
		if i >= 4 and _objective_state() == obj0:
			return false        # nach 10 s ohne Zieländerung nicht weiter warten
	return false


## Führer/Begleiter (verbündete bzw. neutrale NPCs mit Skript): Trupp bleibt dicht hinter ihm, bis er 25 s
## stillsteht (Original: HUMAN_SetWaitForPlayer – der Führer wartet auf die Spieler)
func _follow_guides() -> bool:
	var guides: Array = []
	var waiting := {}       ## Führer mit HUMAN_SetWaitForPlayer (echte Führer, z. B. Sygurd ARCTIC1, Agent ALPS2)
	for vm in rt.vms:
		var s := vm.me as Soldier
		if s and s.alive and s.team != Soldier.TEAM_AXIS and not m.squad.members.has(s):
			guides.append(s)
			var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
			if f and f.get_as_text().to_lower().contains("human_setwaitforplayer"):
				waiting[s] = true
	guides.sort_custom(func(a, b): return a.global_position.distance_to(_start_pos) < b.global_position.distance_to(_start_pos))
	var first := true
	var budget := 150.0     # übrige Begleiter (z. B. kämpfende Verbündete BURMA2) insgesamt höchstens 150 s
	for g in guides:
		var patience := 15.0 if first else 5.0     # nur der nächste Führer bekommt Zeit für seine Begrüßung
		first = false
		var still := 0.0
		var total := 0.0
		var last: Vector3 = g.global_position
		var moved := false
		var cap := 240.0 if waiting.has(g) else minf(60.0, budget)
		while total < cap and is_instance_valid(g) and g.alive:
			# zuerst ansprechen (Annäherung), dann folgen
			var behind: Vector3 = g.global_position + (g.global_position - last).normalized() * -2.5 if g.global_position.distance_to(last) > 0.05 \
				else g.global_position + Vector3(1.4, 0.0, 0.0)
			# nicht über die Einsatzgebiet-Grenze folgen (BURMA2: angreifender Verbündeter BU2_Allied04 läuft in die
			# Warn-/Außenzone, der Trupp dahinter → „Einsatzgebiet verlassen“; ein Spieler folgt dort nicht)
			var area: Node = m.find_child("MissionArea", true, false)
			if area and area.has_method("flags_at") and int(area.flags_at(behind + Vector3(0, 0.3, 0))) != 0:
				print("LOESER Führer %s: Grenze des Einsatzgebiets, nicht weiter gefolgt" % g.name)
				break
			_teleport_to_pos(behind)
			if await _wait(1.0):
				return true
			total += 1.0
			if g.global_position.distance_to(last) > 0.5:
				still = 0.0
				moved = true
			else:
				still += 1.0
			last = g.global_position
			if still > (25.0 if moved else patience):
				break
		if not waiting.has(g):
			budget -= total
		print("LOESER Führer %s: %.0f s begleitet, bewegt %s" % [g.name, total, moved])
	return false


## Trupp (und angeschlossene NPCs mit Begleit-KI, z. B. AFRICA5 Schumann) an einen Ort setzen
func _teleport_to_pos(p: Vector3) -> void:
	var k := 0
	var who: Array = []
	who.append_array(m.squad.alive_members())
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s0 := n as Soldier
		if s0 and s0.alive and not who.has(s0):
			var eb = s0.get_node_or_null("EscortBrain")
			if eb and eb.get("released") == true:
				who.append(s0)
	var lead := _lead()
	if lead and lead.vehicle == null:
		lead.global_position = p + Vector3(0, 0.3, 0)     # aktiver Soldat genau am Ziel (Nähe-Abfragen ≤ 2 m)
		lead.velocity = Vector3.ZERO
	for s in who:
		if s.vehicle != null or s == lead:
			continue
		k += 1
		s.global_position = p + Vector3((k % 3) * 1.0 - 1.0, 0.3, (k / 3) * 1.0 + 0.5)
		s.velocity = Vector3.ZERO


## Skriptobjekte, deren Skript Spielernähe abfragt (Bereichsauslöser, Sammelpunkte, Fundorte). Fallen, die ein Ziel
## scheitern lassen („…fail…“-Auslöser ohne Erfolgsmeldung), werden ausgelassen.
var _points_cache: Array = []


func _trigger_points() -> Array:
	if not _points_cache.is_empty():
		return _points_cache.filter(func(n): return is_instance_valid(n))
	var re := RegEx.create_from_string("(?i)_(All)?PlayersInRange|_PlayerInRange|_GetDistToActivePlayer|_ItemInRange|FRM_GetNearestPlayer")
	# Fallen: Skripte, die Spieler töten (HUMAN_Kill(_PLAYER_ …), z. B. ARCTIC2 Einsturz) – Auslöser, die ihnen
	# Signale senden, werden nicht per Teleport angelaufen (Teleport überspringt das „Verlassen“ der Zone)
	var traps: Array[String] = []
	for vm in rt.vms:
		var tf := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
		var ts: String = tf.get_as_text().to_lower() if tf else ""
		if ts.contains("human_kill") and ts.contains("_player_") and is_instance_valid(vm.me):
			traps.append(String(vm.me.name).to_lower())
	for vm in rt.vms:
		var own: Node3D = vm.me
		if not is_instance_valid(own) or not own.is_inside_tree():
			continue
		if own is Soldier and ((own as Soldier).team == Soldier.TEAM_AXIS or m.squad.members.has(own)):
			continue
		var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		if vm.name.to_lower().contains("fail") and not src.to_lower().contains("setobjectivestatus"):
			continue
		var low := src.to_lower()
		# Zielskripte (SetObjectiveStatus) bleiben Auslöser, auch wenn sie die Falle kennen (ARCTIC2 „Rückkehr zur
		# Oberfläche“ schaltet die Falle bei Erfolg ab)
		if traps.any(func(t): return low.contains("\"" + t + "\"")) and not low.contains("setobjectivestatus"):
			continue
		if re.search(src) != null and not _points_cache.has(own):
			_points_cache.append(own)
	# Reihenfolge wie ein Spieler: jeweils der nächste noch nicht besuchte Punkt ab dem Start (Fortschritt im Gelände)
	var ordered: Array = []
	var rest: Array = _points_cache.duplicate()
	var at := _start_pos
	while not rest.is_empty():
		var best_i := 0
		var best_d := INF
		for i in rest.size():
			var dd: float = at.distance_to((rest[i] as Node3D).global_position)
			if dd < best_d:
				best_d = dd
				best_i = i
		var nx: Node3D = rest[best_i]
		rest.remove_at(best_i)
		ordered.append(nx)
		at = nx.global_position
	_points_cache = ordered
	return _points_cache


var _blasts: Array = []        ## Orte gezündeter Sprengsätze (Einsturzzonen, z. B. ARCTIC2 „Zaval“ tötet Spieler dort)


func _teleport_squad(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	for b in _blasts:
		if (b as Vector3).distance_to(target.global_position) < 30.0:
			return
	# Auslöser am Rand des Einsatzgebiets (Warn-/Außenzone, mission_area.gd) nicht per Teleport anlaufen: die
	# nachrückenden Kameraden laufen sonst über die Grenze (NORMANDY2 24.10.2026: Teleport nach (40,67) = 0x4000,
	# 1 s später ein Kamerad in 0x2000 → „Einsatzgebiet verlassen“)
	var area := m.get_node_or_null("MissionArea")
	if area == null:
		area = m.find_child("MissionArea", true, false)
	if area and int(area.flags_at(target.global_position + Vector3(0, 0.3, 0))) != 0:
		print("LOESER Auslöser an der Einsatzgebiet-Grenze ausgelassen: ", target.name)
		return
	_teleport_to_pos(target.global_position)


func _lead() -> Soldier:
	var l: Soldier = m.squad.leader()
	return l if l else (m.squad.alive_members()[0] if not m.squad.alive_members().is_empty() else null)


## Gegenstände, Plätze, Schalter, Funkgeräte, Sprengplätze, Kisten
func _interact_all(first: bool) -> bool:
	var lead := _lead()
	if lead == null:
		return true
	var items: Array = []
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is OrigInteractive.OrigWorldItem or n is OrigInteractive.OrigPlace or n is OrigInteractive.OrigExplosive \
				or n is OrigInteractive.OrigCrate or (n is OrigInteractive.OrigSwitch and (first or n.radio)):
			if n is OrigInteractive.OrigSwitch and _is_alarm_switch(n):
				continue
			items.append(n)
	# Sprengplätze zuletzt: erst Dokumente/Gegenstände/Plätze (BURMA1: Explosion vor Fund der Unterlagen = Ziel verfehlt)
	var expl := items.filter(func(x): return x is OrigInteractive.OrigExplosive)
	items = items.filter(func(x): return not (x is OrigInteractive.OrigExplosive)) + expl
	var fused := false
	for n in items:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var it := n as Interactable
		if not it.can_interact(lead):
			continue
		_teleport_squad(it)
		lead.global_position = it.global_position + Vector3(0.8, 0.0, 0.0)
		await frames(2)
		if not it.can_interact(lead):
			continue
		it.interact(lead)
		if it is OrigInteractive.OrigExplosive:
			# Anbringen 3 s, dann Zünder verkürzen und Abstand halten
			for i in 30:
				await frames(12)
				lead.global_position = it.global_position + Vector3(0.8, 0.0, 0.0)
				if (it as OrigInteractive.OrigExplosive).state == 1:
					break
			var ex := it as OrigInteractive.OrigExplosive
			if ex.state == 1:
				_teleport_to_pos(_start_pos)      # Abstand zur Ladung: zurück zum Startpunkt
				# erst den Bereich verlassen haben (Skripte melden das Verlassen, z. B. ARCTIC2 Einsturzzonen), dann zünden
				if await _wait(2.5):
					return true
				if ex.state != 1:
					continue
				if ex.has_timer and _protected_names().has(String(ex.frame.name).to_lower()):
					# Zündung lässt ein Ziel scheitern (ARCTIC2: Ladungen mit 5-min-Zünder, Explosion vor der Flucht
					# = Erdrutsch) -> Original-Zünder laufen lassen und weiter (Flucht über die Auslösepunkte)
					print("LOESER Ladung %s mit Originalzünder (%.0f s)" % [ex.frame.name, ex.countdown])
					fused = true
					continue
				_blasts.append(ex.global_position)
				if ex.has_timer:
					ex.countdown = 0.3
				else:
					ex.detonate()
		# Schalter: Zielskripte melden mit Delay; ein schnelles zweites Ereignis verwirft den laufenden Ablauf
		# (NORMANDY: Generator → 3 s → SetObjectiveStatus, Leuchtturmschalter unterbricht) – Spielertempo
		if await _wait(6.0 if it is OrigInteractive.OrigSwitch else 1.0):
			return true
	if fused:
		# Ladungen mit Originalzünder laufen: sofort alle Auslösepunkte (u. a. Rückkehr zur Oberfläche) anlaufen
		for p in _trigger_points():
			_teleport_squad(p)
			if await _wait(0.5):
				return true
	return false


## Alarmknopf (NORWAY „tlacitko“ → alarmer_2 → Sirenen/Tirpitz-Alarm): Skript nennt einen Alarm-/Sirenen-Frame
func _is_alarm_switch(sw) -> bool:
	if not is_instance_valid(sw.frame):
		return false
	var vm = rt.vm_for(sw.frame)
	if vm == null:
		return false
	var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
	return f != null and RegEx.create_from_string("(?i)\"[^\"]*(alarm|poplach|siren)[^\"]*\"").search(f.get_as_text()) != null


## Zielscheiben/Trefferobjekte beschießen: Kisten mit OnDeath (Zielscheiben, z. B. TUTORIAL-Schießstand) und
## Skriptobjekte mit OnHit (Trefferflächen) – wie ein Schuss des Spielers
func _shoot_targets() -> bool:
	var lead := _lead()
	if lead == null:
		return true
	var n := 0
	for vm in rt.vms:
		var own: Node3D = vm.me
		if not is_instance_valid(own) or vm.terminated or own is Soldier or own is Vehicle:
			continue
		var ctl = own.get_meta("orig_ctl") if own.has_meta("orig_ctl") else null
		if ctl is OrigInteractive.OrigCrate and not ctl.destroyed and ctl._is_target():
			ctl.on_bullet_hit(50.0, lead)
			n += 1
		elif ctl == null and vm.code.handlers.has("ONHIT"):
			rt.notify(own, "ONHIT")
			n += 1
	if n > 0:
		print("LOESER %d Ziele beschossen" % n)
	return await _wait(1.0)


func _loot_all() -> void:
	var lead := _lead()
	if lead == null:
		return
	for n in get_tree().get_nodes_in_group("interactables"):
		if n is Pickups.Loot and (n as Interactable).can_interact(lead):
			(n as Interactable).interact(lead)
		elif n is EnemyBrain.CaptureAction:
			for i in 3:
				if (n as Interactable).can_interact(lead):
					(n as Interactable).interact(lead)


## Gefangennahme (Original: Gegner mit niedriger Moral bzw. mit Missionsgegenständen ergeben sich): Hände hoch,
## gefangen nehmen, durchsuchen, erste Uniform anziehen (z. B. ALPS1 „Uniform des Fahrers“ _IsInInventory(129))
func _capture_candidates() -> void:
	var lead := _lead()
	if lead == null:
		return
	var n := 0
	for e in m.enemies:
		if not is_instance_valid(e) or not e.alive or e.vehicle != null:
			continue
		var b: EnemyBrain = e.get_node_or_null("EnemyBrain")
		if b == null or b.capture_action == null:
			continue
		if b.morale_initial >= 75.0 and e.get_meta("orig_loot", []).is_empty():
			continue
		lead.global_position = e.global_position + Vector3(1.0, 0.3, 0.0)
		b.surrender(lead)
		for i in 3:
			if b.capture_action.can_interact(lead):
				b.capture_action.interact(lead)
		n += 1
	print("LOESER %d Gegner gefangen genommen" % n)


var _protected: Dictionary = {}


## Namen, die in Skripten mit Fehlschlag-Pfad vorkommen (z. B. Zielperson, die überleben muss)
func _protected_names() -> Dictionary:
	if not _protected.is_empty():
		return _protected
	_protected["__init"] = true
	var fail_re := RegEx.create_from_string("(?i)SetObjectiveStatus\\s*\\(\\s*\\d+\\s*,\\s*3\\s*\\)")
	var name_re := RegEx.create_from_string("(?i)FRM_FindFrame\\s*\\(\\s*\\w+\\s*,\\s*\"([^\"]+)\"")
	var d := DirAccess.open(m.orig.mission_dir + "/scripts")
	if d:
		for fn in d.get_files():
			var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + fn, FileAccess.READ)
			var src := f.get_as_text() if f else ""
			if fail_re.search(src) == null:
				continue
			for mt in name_re.search_all(src):
				_protected[mt.get_string(1).to_lower()] = true
	return _protected


func _kill_enemies(spare_protected := false) -> void:
	var lead := _lead()
	var n := 0
	var prot := _protected_names()
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and not e.has_meta("hands_up"):
			if spare_protected and prot.has(String(e.name).to_lower()):
				continue
			e.die(lead)
			n += 1
	for d in get_tree().get_nodes_in_group("dogs"):
		if d.has_method("on_bullet_hit") and d.get("health") != null and float(d.health) > 0.0:
			d.on_bullet_hit(9999.0, lead)
	print("LOESER %d Gegner ausgeschaltet" % n)


## Skriptziele mit OnDeath (Fahrzeuge, zerstörbare Objekte, Kisten) zerstören
func _destroy_script_targets() -> void:
	var n := 0
	for vm in rt.vms.duplicate():
		if not vm.code.handlers.has("ONDEATH") or not is_instance_valid(vm.me) or vm.terminated:
			continue
		var own: Node3D = vm.me
		var n0 := n
		if own is Soldier:
			continue
		if _trigger_points().has(own) and own is Vehicle:
			print("LOESER schont Auslösepunkt ", own.name)
			continue      # Fluchtfahrzeuge (Skript fragt Spielernähe ab) nicht zerstören
		var sf := FileAccess.open(m.orig.mission_dir + "/scripts/" + vm.name, FileAccess.READ)
		if sf and RegEx.create_from_string("(?i)SetObjectiveStatus\\s*\\(\\s*\\d+\\s*,\\s*3\\s*\\)").search(sf.get_as_text()) != null:
			print("LOESER schont ", own.name, " (Fehlschlag-Skript)")
			continue      # Zerstörung lässt ein Ziel scheitern (z. B. AFRICA5 Ju 88 für die Flucht)
		if not own.has_meta("orig_ctl") and not own.has_meta("script_breakable") and not own is Vehicle:
			print("LOESER kein Ziel-Steuerobjekt: ", own.name, " (", vm.name, ")")
		if own is Vehicle and not (own as Vehicle).wrecked:
			if m.squad.members.any(func(s): return s.vehicle == own):
				continue
			(own as Vehicle).explode(_lead())
			print("LOESER zerstört ", own.name)
			n += 1
		elif own.has_meta("orig_ctl"):
			var ctl = own.get_meta("orig_ctl")
			if ctl is OrigInteractive.OrigDestructible and not ctl.destroyed:
				ctl.destroy()
				print("LOESER zerstört ", own.name)
				n += 1
			elif ctl is OrigInteractive.OrigCrate and ctl._is_target():
				ctl.on_explosion(100.0, _lead())
				print("LOESER sprengt Kiste ", own.name)
				n += 1
			else:
				print("LOESER nicht zerstörbar: ", own.name, " ", ctl)
		elif own.has_meta("script_breakable"):
			var br = own.get_meta("script_breakable")
			if not br.destroyed:
				br.on_explosion(100.0, _lead())
				print("LOESER sprengt ", own.name)
				n += 1
		# zeitlich versetzt: Zählerskripte verwerfen bei neuem Ereignis den laufenden Ablauf (NORMANDY: 4. Kanone
		# → Delay(3000) → SetObjectiveStatus; ein gleichzeitiges weiteres Signal würde das Ziel verschlucken)
		if n > n0 and await _wait(8.0):
			return
	print("LOESER %d Skriptziele zerstört" % n)


## Mit jedem intakten Fahrzeug (Trupp an Bord) alle Auslösepunkte anfahren (Flucht-/Sammelziele)
func _vehicle_tour() -> bool:
	for v in get_tree().get_nodes_in_group("vehicles"):
		var veh := v as Vehicle
		if veh == null or veh.wrecked or not veh.is_inside_tree():
			continue
		for s in m.squad.alive_members():
			if s.vehicle == null:
				veh.board(s, s == _lead())
		if not m.squad.alive_members().any(func(s): return s.vehicle == veh):
			continue
		for p in _trigger_points():
			if not is_instance_valid(p):
				continue
			# Grenze des Einsatzgebiets wie _teleport_squad (NORMANDY2 24.10.2026: Fahrzeug samt Trupp nach
			# (50.6, 1.0, 62.1) = 0x2000 versetzt → „Einsatzgebiet verlassen“)
			var area := m.find_child("MissionArea", true, false)
			if area and int(area.flags_at(p.global_position + Vector3(0, 0.3, 0))) != 0:
				continue
			veh.freeze = true
			veh.global_position = p.global_position + Vector3.UP * 0.5
			if await _wait(1.2):
				return true
		veh.leave_all()
	return false


## Ziele ohne Erfolgspfad: kein SetObjectiveStatus(i, 1) in den Skripten des Einsatzes
func _static_success_paths() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(?i)SetObjectiveStatus\\s*\\(\\s*(\\d+)\\s*,\\s*1\\s*\\)")
	var d := DirAccess.open(m.orig.mission_dir + "/scripts")
	if d == null:
		return out
	for fn in d.get_files():
		var f := FileAccess.open(m.orig.mission_dir + "/scripts/" + fn, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		var lines := src.split("\n")
		for ln in lines:
			var code := ln.split("//")[0]
			for mt in re.search_all(code):
				out[int(mt.get_string(1))] = true
	return out


var _reported := false


func _report() -> void:
	if _reported:
		return
	_reported = true
	Engine.time_scale = 1.0
	var r: Dictionary = Game.last_result
	var success := bool(r.get("success", false)) and String(r.get("mission", mid)) == mid
	var objs: Array = []
	if is_instance_valid(m):
		var paths := _static_success_paths()
		for idx in m.orig_objectives:
			var o: Objective = m.objective(m.orig_objectives[idx])
			if o:
				objs.append([idx, o.text, o.state, o.optional, paths.has(idx)])
	var req := 0
	var req_done := 0
	var lines: Array[String] = []
	for o in objs:
		var st_txt: String = ["aktiv", "erfüllt", "verfehlt", "inaktiv"][int(o[2])] if int(o[2]) < 4 else str(o[2])
		lines.append("  ZIEL %d [%s%s] %s: %s" % [o[0], "Zusatz" if o[3] else "Pflicht", "" if o[4] else ", kein Erfolgspfad im Skript",
			st_txt, o[1]])
		if not o[3] and int(o[2]) != Objective.State.INACTIVE:
			req += 1
			if int(o[2]) == Objective.State.DONE:
				req_done += 1
	for l in lines:
		print(l)
	# Diagnose: --dump_vms=teil1,teil2 → Zustand passender Skripte (empfangene Signale, Whenever, Variablen)
	if Game.cli.has("dump_vms") and is_instance_valid(rt):
		for part in String(Game.cli["dump_vms"]).to_lower().split(","):
			for vm in rt.vms:
				if String(vm.name).to_lower().contains(part):
					var vs := {}
					for k in vm.vars:
						vs[k] = vm.vars[k] if not (vm.vars[k] is Object) else (vm.vars[k].name if is_instance_valid(vm.vars[k]) else "<frei>")
					print("VMDUMP %s an %s: Signale %s Whenever %s ended %s term %s Var %s" % [vm.name,
						vm.me.name if is_instance_valid(vm.me) else "?", vm.signals.keys(), vm.whenever_active, vm.ended, vm.terminated, vs])
	var alive_n: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and is_instance_valid(m) and not m.squad.members.has(s):
			alive_n.append("%s(%d%s)" % [s.name, s.team, ",Fzg" if s.vehicle else ""])
	print("LOESER lebend: ", ", ".join(alive_n))
	var unimpl: Array = rt.unimplemented.keys() if is_instance_valid(rt) else []
	var reason := String(r.get("reason", "")) if success or r.get("mission", "") == mid else "läuft noch"
	print("ERFUELLBAR|%s|%s|%d|%d/%d|%s|%s|%s|%.0f s" % [mid, m.orig_mission if is_instance_valid(m) else "?",
		1 if success else 0, req_done, req, JSON.stringify(unimpl), reason, "; ".join(notes),
		(Time.get_ticks_msec() - _t0) / 1000.0])
	check(success, "Einsatz %s mit dem Löser erfolgreich abgeschlossen" % mid, reason)
	_finish()
