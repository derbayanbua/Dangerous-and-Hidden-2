extends "res://tests/test_gameplay.gd"
## AF1-Verteidiger-Sonde: wie reagieren die Gegner der Basis auf einen Angriff?
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=probe_af1_defenders [--secs=60] [--radius=120]
##     [--foe=<Name>] [--dist=30] [--tag=] [--af1def=0]
## Trupp unverwundbar und feuert nicht; der Führer steht --dist m vor dem dichtesten Gegnerhaufen und „schießt“ (Schussgeräusch
## seiner Waffe alle 0,3 s, wie Soldier._fire_once) – sichtbar und hörbar. Gemessen werden alle Gegner ≤ --radius m:
## Anteil im Kampf/Suche/Untersuchen nach 10/30/60 s, je bemerkt, je geschossen, Schüsse/min, Sperrgründe
## (suspendiert/Skript/Zombie), Wegstrecke. Ausgabe test_output/af1_def_<tag>.txt.

var shots := 0
var shooters := {}
var noticed := {}
var moved := {}
var start_pos := {}
var lines: PackedStringArray = []


func _snapshot(t: float, foes: Array, c: Soldier) -> void:
	var cnt := {}
	var why := {}
	for s: Soldier in foes:
		var eb = s.get_node_or_null("EnemyBrain")
		if eb == null:
			continue
		var st: String = "tot" if not s.alive else String(eb.state_name())
		cnt[st] = int(cnt.get(st, 0)) + 1
		if s.alive:
			if eb.suspended:
				why["suspendiert"] = int(why.get("suspendiert", 0)) + 1
			if eb.script_control:
				why["skript(zombie)"] = int(why.get("skript(zombie)", 0)) + 1
			if eb.stationary:
				why["stationary"] = int(why.get("stationary", 0)) + 1
			if eb.sniper_enabled:
				why["sniper"] = int(why.get("sniper", 0)) + 1
			why["modus_%d" % int(eb.ai_mode)] = int(why.get("modus_%d" % int(eb.ai_mode), 0)) + 1
	var combat := int(cnt.get("Kampf", 0))
	var l := "T=%02d gegner=%d kampf=%d (%.2f) zustand=%s gruende=%s bemerkt=%d geschossen=%d bewegt=%d schuesse=%d" % [
		int(t), foes.size(), combat, float(combat) / maxf(foes.size(), 1), str(cnt), str(why), noticed.size(), shooters.size(),
		moved.size(), shots]
	print("AF1DEF ", l)
	lines.append(l)


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader() and mission().get("runtime"):
			break
		await get_tree().process_frame
	var m := mission()
	var rt: LsRuntime = m.runtime
	m.finished = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	for i in 1800:
		if m.nav_ready:
			break
		await get_tree().process_frame
	await seconds(3.0)
	for sm in m.squad.members:
		sm.max_health = 1.0e9
		sm.health = sm.max_health
		var sb = sm.get_node_or_null("SquadBrain")
		if sb:
			sb.set("fire_at_will", false)
	var c: Soldier = m.squad.leader()
	var all: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.team != c.team and s.team != Soldier.TEAM_NEUTRAL and s.get_node_or_null("EnemyBrain"):
			all.append(s)
	check(not all.is_empty(), "Gegner vorhanden", str(all.size()))
	if all.is_empty():
		_finish()
		return
	# Basis = Gegner mit den meisten Nachbarn ≤ 40 m (oder --foe)
	var f0: Soldier = all[0]
	var best := -1
	for s: Soldier in all:
		var k := 0
		for o: Soldier in all:
			if o.global_position.distance_to(s.global_position) < 40.0:
				k += 1
		if k > best:
			best = k
			f0 = s
	if Game.cli.has("foe"):
		for s: Soldier in all:
			if String(s.name) == String(Game.cli["foe"]):
				f0 = s
	var fwd := f0.aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var space := c.get_world_3d().direct_space_state
	var tp := f0.global_position + fwd * float(Game.cli.get("dist", "30"))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 30, tp + Vector3.DOWN * 60, 1))
	c.global_position = ((hit.position as Vector3) + Vector3.UP * 0.3) if not hit.is_empty() else tp
	c.velocity = Vector3.ZERO
	# Rest des Trupps weit hinter den Führer (misst nur die Reaktion auf den Führer)
	var radius := float(Game.cli.get("radius", "120"))
	var foes: Array = all.filter(func(s): return (s as Soldier).global_position.distance_to(c.global_position) <= radius)
	print("AF1DEF basis=%s pos=%s gegner_im_radius=%d namen=%s" % [f0.name, str(c.global_position.round()), foes.size(),
		str(foes.map(func(s): return String(s.name)))])
	for s: Soldier in foes:
		start_pos[s] = s.global_position
		s.shot_fired.connect(func(_w): shots += 1; shooters[s.name] = int(shooters.get(s.name, 0)) + 1)
	var w := c.current_weapon()
	var noise := w.data.noise_radius if w else 60.0
	var secs := float(Game.cli.get("secs", "60"))
	var t := 0.0
	var next_snap := [10.0, 30.0, 60.0, 90.0, 120.0]
	while t < secs:
		await seconds(0.3)
		t += 0.3
		for sm in m.squad.members:
			sm.health = sm.max_health
		# Angriff: Schussgeräusch des Führers (wie Soldier._fire_once → Events.emit_noise gunshot)
		Events.emit_noise(c.global_position, noise, c, c.team, &"gunshot")
		c.last_shot_time = Time.get_ticks_msec() / 1000.0    # Sichtbarkeit nach Schuss (Perception ORIG_SHOT_FLOOR)
		for s: Soldier in foes:
			var eb = s.get_node_or_null("EnemyBrain")
			if eb and s.alive and (int(eb.state) != 0 and int(eb.state) != 1 or eb.get("_alarm_notified")):
				noticed[s.name] = true
			if s.alive and s.global_position.distance_to(start_pos[s]) > 3.0:
				moved[s.name] = true
			if s.alive:
				for wp in s.weapons:
					if wp != null and (wp as Weapon).data.slot != WeaponData.Slot.GRENADE:
						(wp as Weapon).reserve = maxi((wp as Weapon).reserve, (wp as Weapon).data.magazine_size * 4)
		if not next_snap.is_empty() and t >= next_snap[0] - 0.01:
			next_snap.pop_front()
			_snapshot(t, foes, c)
	var spm := shots * 60.0 / secs
	var detail := []
	for s: Soldier in foes:
		var eb = s.get_node_or_null("EnemyBrain")
		detail.append("%s:%s,d=%.0f,susp=%s,zomb=%s,mode=%d,sch=%d" % [s.name, eb.state_name(),
			s.global_position.distance_to(c.global_position), eb.suspended, eb.script_control, int(eb.ai_mode),
			int(shooters.get(s.name, 0))])
	var tag := String(Game.cli.get("tag", "af1def_" + String(Game.cli.get("af1def", "1"))))
	var summary := "AF1DEF_SUM tag=%s secs=%.0f gegner=%d bemerkt=%d geschossen=%d bewegt=%d schuesse=%d schuesse_pro_min=%.1f" % [
		tag, secs, foes.size(), noticed.size(), shooters.size(), moved.size(), shots, spm]
	print(summary)
	print("AF1DEF_DETAIL ", " | ".join(detail))
	lines.append(summary)
	lines.append("DETAIL " + " | ".join(detail))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var fa := FileAccess.open("res://test_output/af1_def_%s.txt" % tag, FileAccess.WRITE)
	if fa:
		for l in lines:
			fa.store_line(l)
	check(true, "Messung abgeschlossen", summary)
	_finish()
