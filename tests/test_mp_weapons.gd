extends "res://tests/test_gameplay.gd"
## Mehrspieler-Waffen nach dem Original (docs/re_notes_weapons.md §10, re_notes_multiplayer.md §1.7a):
##  A Schadenswerte aller MP-Waffen aus items.sav, Abfall, Trefferzonen (Kopf ×5, Helm, Arme ×0,2, Beine ×0,33),
##    Explosionen – Tabelle test_output/mp_weapon_damage.txt
##  B Erlaubte Gegenstände je Karte und Seite (alle 30 Original-MP-Karten) und Original-Klassen nach der Ersatzregel
##    – Liste test_output/mp_allowed_items.txt
##  C Echter Server (mp_africa1_obj): Bot-/Klassenausrüstung nur kartenerlaubt, gemessene Treffer per Ballistics
##    (Server rechnet), Original-MG-Stellungen (Modell, Drehachsen, Grenzen, Mündung, KI-Bedienung)
##   tools\godot.cmd --headless -- --autoplay=test_mp_weapons [--phase=all|table|maps|server] [--map=mp_africa1_obj]
##   Fensteraufnahme der MG-Stellung: tools\godot.cmd -- --autoplay=test_mp_weapons --phase=server --shot=1
##     → test_output/mp_mg_emplacement.png
##  D Bedienhaltung an Stellungen (anim.sav-Clip, Hände an RWS/LWS, Schwenk/Höhe/Rückstoß, Kamera, Absteigen):
##    --phase=pose (nur Original-MG, 1 KI je Seite), --phase=local (Stellungen einer lokalen Zusatzkarte); mit --shot=1
##    im Fenster → test_output/mp_pose_<waffe>_<gerade|links|rechts|hoch|3rd>.png

const MAP := "mp_africa1_obj"
var table: Array[String] = []
var allowed_txt: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(_timeout)
	_run.call_deferred()


func _timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func _run() -> void:
	await frames(5)
	var ph := String(Game.cli.get("phase", "all"))
	if ph in ["all", "table"]:
		_phase_table()
	if ph in ["all", "maps"]:
		_phase_maps()
	if ph in ["all", "server"]:
		await _phase_server()
	if ph == "pose":
		await _phase_pose()
	if ph in ["all", "hitbox"]:
		await _phase_hitbox()
	if ph in ["all", "local"]:
		await _phase_local()
	_write("mp_weapon_damage.txt", table)
	_write("mp_allowed_items.txt", allowed_txt)
	_finish()


func _write(name: String, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/" + name), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")


static func _near(a: float, b: float, eps := 0.02) -> bool:
	return absf(a - b) <= eps


# --- A: Schadenstabelle --------------------------------------------------------------------------------

func _mp_item_ids() -> Array:
	var ids: Array = []
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/mp_maps.json")
	for e in (d.get("maplist", []) if typeof(d) == TYPE_DICTIONARY else []):
		for a in e.get("allowed_items", []):
			if not ids.has(int(a["item_id"])):
				ids.append(int(a["item_id"]))
	ids.sort()
	return ids


func _phase_table() -> void:
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/items.json")
	check(typeof(d) == TYPE_DICTIONARY, "items.json (items.sav v1.12) vorhanden")
	if typeof(d) != TYPE_DICTIONARY:
		return
	var orig := {}
	for w in d.get("weapons", []):
		orig[int(w["id"])] = w
	var mp_ids := _mp_item_ids()
	check(mp_ids.size() >= 60, "Gegenstände aller MP-Karten (ALLOWEDITEMS)", str(mp_ids.size()))
	table.append("Schadenstabelle MP-Waffen (Gesundheit 100 = 1000 zotti; Original items.sav v1.12, hd2.exe 0x44B3B0/0x5A1C90)")
	table.append("Nr | Waffe | Grundschaden | Abfall ab m | je m | 25 m | 50 m | 100 m | 200 m | Kopf 25 m | Helm durch/ab 25 m | Arm | Bein | Kopftreffer tödlich bis")
	var ok_vals := true
	var bad: Array = []
	var n := 0
	for id in mp_ids:
		if not orig.has(id):
			continue
		var o: Dictionary = orig[id]
		var wd := WeaponDB.from_orig(id, true)
		if wd == null:
			bad.append(id)
			ok_vals = false
			continue
		n += 1
		if not (_near(wd.damage, float(o["damage"]) / 10.0) and _near(wd.falloff_start, float(o["dist_param"]))
				and _near(wd.falloff_per_m, float(o["recoil_spread"]) / 10.0)):
			ok_vals = false
			bad.append("%d %s: %.1f/%.1f/%.3f" % [id, o["name"], wd.damage, wd.falloff_start, wd.falloff_per_m])
		var b25 := WeaponDB.bullet_damage(wd, 25.0)
		var lethal := 0.0
		var dd := 0.0
		while dd <= 600.0 and WeaponDB.zone_damage(WeaponDB.bullet_damage(wd, dd), &"head") >= 100.0:
			lethal = dd
			dd += 1.0
		table.append("%d | %s (%s) | %.1f | %.0f | %.3f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f/%.1f | %.1f | %.1f | %s" % [id, o["name"], String(wd.id),
			wd.damage, wd.falloff_start, wd.falloff_per_m, b25, WeaponDB.bullet_damage(wd, 50.0), WeaponDB.bullet_damage(wd, 100.0),
			WeaponDB.bullet_damage(wd, 200.0), WeaponDB.zone_damage(b25, &"head"), WeaponDB.zone_damage(b25, &"head", true, 0.1),
			WeaponDB.zone_damage(b25, &"head", true, 0.9), WeaponDB.zone_damage(b25, &"arm"), WeaponDB.zone_damage(b25, &"leg"),
			("%.0f m" % lethal) if lethal > 0.0 else "nie"])
	check(ok_vals and n >= 25, "Schaden/Abfall aller MP-Feuerwaffen = items.sav (Schaden/10, Abfallbeginn, Abfall je m/10)", "%d Waffen %s" % [n, str(bad)])
	# eigene Einträge = Originalwerte
	var named := {&"kar98k": 4, &"mp40": 18, &"stg44": 26, &"p08": 0, &"sten": 21, &"thompson": 20, &"enfield": 6, &"garand": 10, &"bren": 29, &"colt": 2}
	var ok_named := true
	var named_bad: Array = []
	table.append("")
	table.append("Alle Werte der eigenen Waffeneinträge gegen items.sav (Nachbau / Original): Schaden | Abfall ab | je m | Kadenz bzw. Repetierzeit | Magazin | Nachladen s | v0 m/s | Gewicht kg | Munition | Zielstreuung (Original-Feld, Wirkung [P])")
	for k in named:
		var w := WeaponDB.get_weapon(k)
		var o: Dictionary = orig[int(named[k])]
		var fi := float(o["fire_interval_ms"]) / 1000.0
		var cad_ok: bool = _near(w.bolt_time, fi, 0.01) if fi >= 1.0 else _near(w.rpm, 60.0 / fi, 0.5)
		var vals_ok: bool = _near(w.damage, float(o["damage"]) / 10.0) and _near(w.falloff_start, float(o["dist_param"])) \
			and _near(w.falloff_per_m, float(o["recoil_spread"]) / 10.0) and cad_ok and w.magazine_size == int(o["magazine"]) \
			and _near(w.reload_time, float(o["reload_ms"]) / 1000.0) and _near(w.muzzle_velocity, float(o["muzzle_velocity"]), 0.5) \
			and _near(w.weight, float(o["weight_kg"]), 0.011)
		if not vals_ok:
			ok_named = false
			named_bad.append(String(k))
		table.append("%s (%d) | %.1f/%.1f | %.0f/%.0f | %.3f/%.3f | %s | %d/%d | %.1f/%.1f | %.0f/%.0f | %.2f/%.3f | %s | %.2f" % [k, named[k],
			w.damage, float(o["damage"]) / 10.0, w.falloff_start, float(o["dist_param"]), w.falloff_per_m, float(o["recoil_spread"]) / 10.0,
			("%.2f/%.2f s" % [w.bolt_time, fi]) if fi >= 1.0 else ("%.0f/%.0f /min" % [w.rpm, 60.0 / fi]), w.magazine_size, int(o["magazine"]),
			w.reload_time, float(o["reload_ms"]) / 1000.0, w.muzzle_velocity, float(o["muzzle_velocity"]), w.weight, float(o["weight_kg"]),
			String(o.get("ammo_name", "")), float(o.get("aim_spread", 0.0))])
	check(ok_named, "Eigene Waffeneinträge: Schaden, Abfall, Kadenz/Repetierzeit, Magazin, Nachladen, v0, Gewicht = items.sav", str(named_bad))
	# Messwerte der Formeln
	var k98 := WeaponDB.get_weapon(&"kar98k")
	var mp40 := WeaponDB.get_weapon(&"mp40")
	var p08 := WeaponDB.get_weapon(&"p08")
	check(_near(WeaponDB.bullet_damage(k98, 75.0), 48.8) and _near(WeaponDB.bullet_damage(k98, 175.0), 33.8), "K98k: voll bis 75 m, 100 m später −15", "%.1f" % WeaponDB.bullet_damage(k98, 175.0))
	check(_near(WeaponDB.bullet_damage(mp40, 60.0), 17.5) and WeaponDB.bullet_damage(mp40, 100.0) == 0.0, "MP 40: 60 m → 17,5; ab 92 m kein Schaden")
	check(WeaponDB.bullet_damage(p08, 40.0) == 0.0 and _near(WeaponDB.bullet_damage(p08, 20.0), 23.0), "P08: 20 m → 23; 40 m → 0")
	check(_near(WeaponDB.zone_damage(48.8, &"head"), 244.0) and _near(WeaponDB.zone_damage(48.8, &"torso"), 48.8)
		and _near(WeaponDB.zone_damage(48.8, &"arm"), 9.76) and _near(WeaponDB.zone_damage(48.8, &"leg"), 16.104),
		"Trefferzonen Kopf ×5, Körper ×1, Arm ×0,2, Bein ×0,33 (K98k 244/48,8/9,8/16,1)")
	check(_near(WeaponDB.zone_damage(48.8, &"head", true, 0.1), 169.0) and _near(WeaponDB.zone_damage(48.8, &"head", true, 0.5), 6.76)
		and WeaponDB.zone_damage(12.0, &"head", true, 0.1) == 0.0, "Helm: −15, dann 30 % ×5 / 70 % ×0,2; schwache Treffer bleiben stecken")
	var no36 := WeaponDB.get_weapon(&"no36")
	var pf := WeaponDB.get_weapon(&"panzerfaust")
	check(_near(WeaponDB.explosion_damage(no36.damage, no36.blast_radius, 0.0), 199.9) and _near(WeaponDB.explosion_damage(no36.damage, no36.blast_radius, 5.0), 99.95)
		and WeaponDB.explosion_damage(no36.damage, no36.blast_radius, 10.0) == 0.0, "Granate No.36: 1999 zotti, 10 m, linear (5 m → 99,95)")
	check(_near(pf.damage, 290.0) and _near(pf.blast_radius, 6.0) and _near(WeaponDB.get_weapon(&"bazooka").damage, 240.0)
		and _near(WeaponDB.get_weapon(&"m24").blast_radius, 10.0), "Werfer/Granaten: Stärke und Radius aus items.sav")
	table.append("")
	table.append("Explosionen (Stärke | Radius | 0 m | halber Radius): No.36 %.1f | %.1f m; No.69 %.1f | %.1f m; Stielhandgranate %.1f | %.1f m; Panzerfaust %.1f | %.1f m; Bazooka %.1f | %.1f m; Panzerschreck %.1f | %.1f m" % [
		no36.damage, no36.blast_radius, WeaponDB.get_weapon(&"no69").damage, WeaponDB.get_weapon(&"no69").blast_radius,
		WeaponDB.get_weapon(&"m24").damage, WeaponDB.get_weapon(&"m24").blast_radius, pf.damage, pf.blast_radius,
		WeaponDB.get_weapon(&"bazooka").damage, WeaponDB.get_weapon(&"bazooka").blast_radius,
		WeaponDB.get_weapon(&"panzerschreck").damage, WeaponDB.get_weapon(&"panzerschreck").blast_radius])
	table.append("Schalldämpfer-Varianten [D]: kar98k_sd %.1f ab %.0f m −%.3f/m; mp40_sd %.1f ab %.0f m −%.3f/m" % [
		WeaponDB.get_weapon(&"kar98k_sd").damage, WeaponDB.get_weapon(&"kar98k_sd").falloff_start, WeaponDB.get_weapon(&"kar98k_sd").falloff_per_m,
		WeaponDB.get_weapon(&"mp40_sd").damage, WeaponDB.get_weapon(&"mp40_sd").falloff_start, WeaponDB.get_weapon(&"mp40_sd").falloff_per_m])
	check(WeaponDB.orig_item_of(&"kar98k_sd") == 4 and WeaponDB.orig_item_of(&"mp40_sd") == 18 and WeaponDB.orig_item_of(&"no36") == 62,
		"Varianten zählen als Grundmodell (kar98k_sd → 4, mp40_sd → 18)")


# --- B: Freigabe je Karte, Klassen -----------------------------------------------------------------------

func _phase_maps() -> void:
	var d = LsRuntime._read_json(OrigLevel.cache_root() + "/mp_maps.json")
	if typeof(d) != TYPE_DICTIONARY:
		check(false, "mp_maps.json vorhanden")
		return
	var maps := 0
	var cls_ok := true
	var cls_bad: Array = []
	var side_ok := true
	var adapted := 0
	for e in d.get("maps", []):
		if not bool(e.get("playable_in_original", false)):
			continue
		var folder := String(e["folder"]).to_lower()
		var mp = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/mp.json")
		if typeof(mp) != TYPE_DICTIONARY or (mp.get("game_styles", []) as Array).is_empty():
			continue
		var st: Dictionary = mp["game_styles"][0]
		var allowed: Array = st.get("allowed_items", [])
		maps += 1
		var by_side: Dictionary = st.get("allowed_items_by_side", {})
		for t in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
			var side := "axis" if t == Soldier.TEAM_AXIS else "allied"
			var ids: Array = Net.allowed_of(allowed, t)
			var exp: Array = by_side.get(side, [])
			if not by_side.is_empty() and ids.size() != exp.size():
				side_ok = false
			var weap: Array = ids.filter(func(i): return String(OrigInteractive.item_info(int(i)).get("kind", "")) == "weapon")
			var names: Array = weap.map(func(i): return "%d %s" % [i, OrigInteractive.item_info(int(i)).get("name", "?")])
			allowed_txt.append("%s [%s] %s: %s" % [e["folder"], st.get("style_name", ""), side, ", ".join(names)])
		for p in st.get("presets", []):
			var team: int = Soldier.TEAM_AXIS if String(p.get("side", "")) == "axis" else Soldier.TEAM_ALLIED
			var storage := Net.storage_of(allowed, team)
			var slots: Array = p.get("slots", [])
			var uni: int = int(slots[3]["item_id"]) if slots.size() > 3 else -1
			var ad := Net.adapt_preset(p, storage, uni >= 0 and Net.item_side_flag(uni) == 1)
			var used: Array = [int(ad["hands"]), int(ad["shoulder"])]
			for it in ad["items"]:
				used.append(int(it[0]))
			for u in used:
				if u >= 0 and not storage.has(u):
					cls_ok = false
					cls_bad.append("%s %s: %d" % [folder, p["name"], u])
			if not (ad["replaced"] as Dictionary).is_empty() or not (ad["dropped"] as Array).is_empty():
				adapted += 1
				allowed_txt.append("   Klasse %s: Hand %d, ersetzt %s, entfallen %s" % [p["name"], ad["hands"], str(ad["replaced"]), str(ad["dropped"])])
			if int(ad["hands"]) < 0:
				cls_ok = false
				cls_bad.append("%s %s: keine Waffe" % [folder, p["name"]])
	check(maps == 30, "Alle 30 Original-MP-Karten mit Freigabeliste", str(maps))
	check(side_ok, "Freigabe je Seite = fmt_mp „allowed_items_by_side“ (items.sav-Seitenkennung)")
	check(cls_ok, "Original-Klassen nutzen nur kartenerlaubte Gegenstände (Ersatzregel 0x679850)", str(cls_bad.slice(0, 6)))
	check(adapted >= 1, "Klassen werden auf Karten mit fehlenden Waffen angepasst", "%d Klassen" % adapted)
	# Ersatzregel: Alliierter Scharfschütze auf Africa1_obj (kein Lee-Enfield-/Springfield-Zielfernrohr)
	var mp1 = LsRuntime._read_json(OrigLevel.cache_root() + "/africa1_obj/mp.json")
	if typeof(mp1) == TYPE_DICTIONARY:
		var allowed1: Array = mp1["game_styles"][0]["allowed_items"]
		var st1 := Net.storage_of(allowed1, Soldier.TEAM_ALLIED)
		check(not st1.has(17) and not st1.has(15), "Africa1_obj: kein Zielfernrohrgewehr der Alliierten erlaubt")
		var sub := Net.orig_substitute(17, st1, false, 4)
		check(sub >= 0 and st1.has(sub) and int(OrigInteractive.item_info(sub).get("inv_h", 0)) == 4, "Ersatz für Lee-Enfield (optics): Gewehr aus dem Lager", "%d %s" % [sub, OrigInteractive.item_info(sub).get("name", "")])
		var sub_axis := Net.orig_substitute(54, Net.storage_of(allowed1, Soldier.TEAM_AXIS), true, 0)
		allowed_txt.append("Africa1_obj Ersatzregel: Lee-Enfield optics (17) → %d, Verbandskasten bei Achsen-Uniform → %d" % [sub, sub_axis])


# --- C: echter Server ------------------------------------------------------------------------------------

func _host(map: String, bots: int, mode: int = Net.Mode.OBJECTIVES) -> Node:
	Net.local_name = "Host"
	if not Net.host({"name": "MPW", "map": map, "mode": mode, "max_players": 16, "time_limit_min": 0, "score_limit": 0,
			"respawn_s": 5, "password": "", "port": Net.PORT + 24, "friendly_fire": false, "bots_per_team": bots, "warmup_s": 0}):
		return null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.3).timeout
		var mm := Game.current_mission()
		if mm and Net._soldiers.has(1) and Net._soldiers.keys().filter(func(k): return int(k) < 0).size() >= bots * 2:
			return mm
	return null


func _brain(s: Soldier) -> BotBrain:
	return s.get_node_or_null("EnemyBrain") as BotBrain


func _phase_server() -> void:
	var map := String(Game.cli.get("map", MAP))
	var m = await _host(map, 5)
	check(m != null, "Server %s mit 5 KI-Soldaten je Seite" % map)
	if m == null:
		return
	var bots: Array = []
	for k in Net._soldiers:
		var s: Soldier = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s):
			bots.append(s)
			var b := _brain(s)
			if b:
				b.enabled = false
	check(Net.map_allowed_known(), "Karte hat eine Freigabeliste (Net.map_allowed_known)")
	var ax: Array = Net.map_allowed_items(Soldier.TEAM_AXIS)
	var al: Array = Net.map_allowed_items(Soldier.TEAM_ALLIED)
	check(ax.has(4) and ax.has(18) and not ax.has(6) and al.has(6) and not al.has(18), "Net.map_allowed_items je Seite", "Achse %d, Alliierte %d" % [ax.size(), al.size()])
	check(Net.is_item_allowed(Soldier.TEAM_AXIS, &"kar98k_sd") and Net.is_item_allowed(Soldier.TEAM_AXIS, &"mp40_sd"), "Schalldämpfer-K98k/MP 40 erlaubt, weil K98k/MP 40 erlaubt")
	# KI-Ausrüstung
	var bot_ok := true
	var bot_bad: Array = []
	var no_launcher := true
	for s in bots:
		for w in s.weapons:
			if w == null:
				continue
			if not Net.is_item_allowed(s.team, w.data.id):
				bot_ok = false
				bot_bad.append("%s %s" % [s.soldier_name, w.data.id])
			if w.data.slot == WeaponData.Slot.LAUNCHER:
				no_launcher = false
		var pw: Weapon = s.weapons[0]
		if pw == null:
			bot_ok = false
			bot_bad.append("%s ohne Primärwaffe" % s.soldier_name)
	check(bot_ok, "KI-Soldaten tragen nur kartenerlaubte Waffen (Rolle oder nächstbeste)", str(bot_bad))
	var any_launcher: bool = Net.is_item_allowed(Soldier.TEAM_AXIS, 38) or Net.is_item_allowed(Soldier.TEAM_ALLIED, 39)
	check(any_launcher or no_launcher, "Panzerabwehr ohne erlaubten Werfer: kein Werfer", "Werfer erlaubt: %s" % any_launcher)
	# 100 Bot-Ausstattungen je Rolle/Seite (Zufall) prüfen
	var kit_ok := true
	for i in 100:
		var t: int = Soldier.TEAM_AXIS if i % 2 == 0 else Soldier.TEAM_ALLIED
		var kit := Net.bot_kit(t, i % 5, false)
		for e in kit:
			if (e is int and int(e) >= 0) or e is String:
				if not Net.is_item_allowed(t, e):
					kit_ok = false
	check(kit_ok, "bot_kit wählt in 100 Ziehungen nur erlaubte Gegenstände")
	# Klassen am Host-Soldaten
	var host: Soldier = Net._soldiers.get(1)
	var cls_ok := true
	var cls_bad: Array = []
	# Original-Klassen: Ersatz aus dem gesamten Kartenlager (Ersatzregel filtert nur bei Achsen-Uniform auf die
	# Achse; z. B. alliierter Scharfschütze auf Africa1_obj → K98k optics); Schleicher: eigene Seite
	for t in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
		var st_all := Net.map_storage(t)
		for c in 6:
			Net._apply_class(m, host, t, c)
			for w in host.weapons:
				var oi: int = WeaponDB.orig_item_of(w.data.id) if w else -1
				var ok_w: bool = Net.is_item_allowed(t, w.data.id) if (w and c == 5) else (w == null or st_all.has(oi) or w.data.slot == WeaponData.Slot.MELEE)
				if w and not ok_w:
					cls_ok = false
					cls_bad.append("%d/%d %s" % [t, c, w.data.id])
	check(cls_ok, "Alle 6 Klassen beider Seiten nur mit kartenerlaubten Waffen (inkl. Schleicher)", str(cls_bad))
	await _hits(m, bots)
	await _emplacements(m, bots)
	await _leave()


## Nur Bedienhaltung an der Original-MG-Stellung (schneller Lauf: 1 KI je Seite)
func _phase_pose() -> void:
	var map := String(Game.cli.get("map", MAP))
	var m = await _host(map, 1)
	check(m != null, "Server %s (Bedienhaltung)" % map)
	if m == null:
		return
	var bots: Array = []
	for k in Net._soldiers:
		var s: Soldier = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s):
			bots.append(s)
			var b := _brain(s)
			if b:
				b.enabled = false
	await _emplacements(m, bots)
	await _leave()


## Lokale Zusatzkarte (nicht im Repository, Game.local_content „mp_maps_first“[0]): eigene Stellungen über die
## gemeinsame Basis OrigEmplacement (Gestaltung unverändert). Ohne lokale Inhalte übersprungen. --local_map=<id>
func _phase_local() -> void:
	var lm: Array = Game.local_content.get("mp_maps_first", [])
	var mid := String(Game.cli.get("local_map", lm[0] if not lm.is_empty() else ""))
	if mid == "" or not Game.MISSIONS.has(mid):
		print("Phase local: keine lokale Zusatzkarte – übersprungen")
		return
	var m = await _host(mid, 1, Net.Mode.DEATHMATCH)
	check(m != null, "Server %s (Bedienhaltung an eigenen Stellungen)" % mid)
	if m == null:
		return
	for k in Net._soldiers:
		var b := _brain(Net._soldiers[k])
		if b:
			b.enabled = false
	var g: Soldier = Net._soldiers.get(1)
	if not is_instance_valid(g):
		check(false, "Lokale Karte: Host-Soldat vorhanden")
		return
	var emps: Array = []
	for n in m.find_children("*", "", true, false):
		if n is OrigInteractive.OrigEmplacement:
			emps.append(n)
	check(not emps.is_empty(), "Lokale Karte: Stellungen vorhanden", str(emps.size()))
	for e in emps:
		var x: OrigInteractive.OrigEmplacement = e
		var grp := String(x.name)
		x.mount(g)
		await frames(5)
		check(g.mounted == x and not is_instance_valid(g.model._weapon_mesh), "Lokale Karte %s: besetzt, keine Handwaffe" % grp)
		var rig: CameraRig = m.get("rig")
		if rig and rig.target == g:
			var old_mode := rig.mode
			rig.mode = CameraRig.Mode.FIRST
			await frames(6)
			var cp := g.model.camera_point(true)
			check(rig.fpv_active and not rig._viewmodel.visible and rig.camera.global_position.distance_to(cp) < 0.3,
				"Lokale Karte %s: 1. Person ohne Ego-Waffe/-Hände, Kamera am Kamerapunkt der Stellung" % grp,
				"FPV %s, Ego-Modell sichtbar %s, Abstand %.2f m" % [rig.fpv_active, rig._viewmodel.visible, rig.camera.global_position.distance_to(cp)])
			# 3. Person mit der echten Spielkamera: Drehpunkt im Raum, Kamera frei mit Sicht auf den Schützen
			rig.mode = CameraRig.Mode.THIRD
			g.look_yaw = float(x.get("base_yaw")) if x.get("base_yaw") != null else x.frame.global_basis.get_euler().y
			g.look_pitch = 0.0
			await seconds(1.2)
			var head: Vector3 = x._figure_bone("f")
			var cpos := rig.camera.global_position
			var q := PhysicsRayQueryParameters3D.create(cpos, head, 1)
			q.exclude = x.shot_exclusions()
			var blocked := x.get_world_3d().direct_space_state.intersect_ray(q)
			var piv := g.model.camera_point(false)
			var q2 := PhysicsRayQueryParameters3D.create(head, piv, 1)
			q2.exclude = x.shot_exclusions()
			var piv_blocked := not x.get_world_3d().direct_space_state.intersect_ray(q2).is_empty()
			check(not rig.fpv_active and blocked.is_empty() and not piv_blocked and cpos.distance_to(head) > 0.4,
				"Lokale Karte %s: 3. Person – Kamera frei (nicht in Wand/Decke), Sicht auf den Schützen" % grp,
				"Abstand Kopf %.2f m, Sicht frei %s, Drehpunkt frei %s" % [cpos.distance_to(head), blocked.is_empty(), not piv_blocked])
			if bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless":
				g.model.visible = true
				_save_shot("mp_pose_local_%s_3rd_spielkamera.png" % grp)
			rig.mode = old_mode
			await frames(3)
		await _gunner_pose(x, g, "local " + grp)
		x.dismount()
		await frames(3)
		await _dismount_check(x, g, "local " + grp)
	await _leave()


## E Trefferzonen der Original-Figur (MODELS\humanzones.4ds, je Kiste am gleichnamigen Gelenk, re_notes_weapons §10a)
##   in allen Haltungen: stehen/hocken/liegen/zielen/laufen/Stellung/Fahrzeug. Je Zone: haftet am Gelenk, ein Strahl
##   von außen auf die Kistenmitte trifft zuerst genau diese Zone, Ballistics-Auflösung (Original-Reihenfolge) ergibt
##   die Zone (Arme dürfen vom Körper verdeckt sein). Tabelle test_output/mp_hitzones.txt, Fenster: mp_zones_<haltung>.png
var zone_txt: Array[String] = []


func _phase_hitbox() -> void:
	var map := String(Game.cli.get("map", MAP))
	var m = await _host(map, 1)
	check(m != null, "Server %s (Trefferzonen)" % map)
	if m == null:
		return
	var b: Soldier = null
	for k in Net._soldiers:
		var s: Soldier = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s):
			var br := _brain(s)
			if br:
				br.enabled = false
			if b == null and s.team == Soldier.TEAM_AXIS:
				b = s
	if b == null:
		check(false, "KI-Soldat für die Trefferzonenprüfung")
		return
	var table := SoldierModel.orig_zone_table()
	check(table.size() == 10, "Original-Trefferzonen aus humanzones.4ds (10 Gelenkkisten c f l m h i s t o p)", str(table.size()))
	var puppet_on := 0
	for h in b.model.root_pivot.find_children("*", "Hitbox", true, false):
		if (h as Hitbox).collision_layer != 0:
			puppet_on += 1
	check(b.model.orig_zones.size() == 10 and puppet_on == 0, "Zonen an den Gelenken der Original-Figur, Platzhalterzonen aus",
		"%d Gelenkzonen, %d Platzhalterzonen aktiv" % [b.model.orig_zones.size(), puppet_on])
	zone_txt.append("Haltung\tZone\tGelenk\tMitte(Höhe m)\tStrahl\tErsttreffer\tAuflösung")
	for p in ["stehen", "hocken", "liegen", "zielen", "laufen", "stellung", "fahrzeug"]:
		var ctx: Dictionary = await _zone_pose(m, b, p)
		if not bool(ctx.get("ok", true)):
			check(false, "Haltung %s herstellbar" % p, str(ctx))
			continue
		_check_zones(b, p)
		if bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless":
			await _zone_shot(b, p)
		await _zone_pose_end(m, b, p, ctx)
	_write("mp_hitzones.txt", zone_txt)
	await _leave()


func _zone_pose(m: Node, b: Soldier, p: String) -> Dictionary:
	var ctx := {"ok": true}
	b.aiming = false
	b.move_input = Vector3.ZERO
	b.trigger = false
	match p:
		"stehen":
			b.stance_request = Soldier.Stance.STAND
		"hocken":
			b.stance_request = Soldier.Stance.CROUCH
		"liegen":
			b.stance_request = Soldier.Stance.PRONE
		"zielen":
			b.stance_request = Soldier.Stance.STAND
			b.aiming = true
		"laufen":
			b.stance_request = Soldier.Stance.STAND
			b.move_input = b.forward()
		"stellung":
			var emps: Array = get_tree().get_nodes_in_group("emplacements").filter(func(x): return x is OrigInteractive.OrigEmplacement and x.gunner == null)
			if emps.is_empty():
				return {"ok": false, "why": "keine Stellung"}
			ctx["emp"] = emps[0]
			ctx["pos"] = b.global_position
			(emps[0] as OrigInteractive.OrigEmplacement).mount(b)
		"fahrzeug":
			if not m.has_method("spawn_vehicle"):
				return {"ok": false, "why": "spawn_vehicle fehlt"}
			var right := Vector3(cos(b.look_yaw), 0, -sin(b.look_yaw))
			var v: Vehicle = m.spawn_vehicle(b.global_position + right * 4.0 + Vector3.UP * 0.5, b.look_yaw, "zone_test_vehicle")
			await seconds(1.0)
			ctx["veh"] = v
			ctx["pos"] = b.global_position
			if not v.board(b, false, 1):
				return {"ok": false, "why": "Einsteigen fehlgeschlagen", "veh": v}
	await seconds(1.4 if p != "laufen" else 0.7)
	return ctx


func _zone_pose_end(_m: Node, b: Soldier, p: String, ctx: Dictionary) -> void:
	b.aiming = false
	b.move_input = Vector3.ZERO
	b.stance_request = Soldier.Stance.STAND
	if ctx.has("emp"):
		(ctx["emp"] as OrigInteractive.OrigEmplacement).dismount()
	if ctx.has("veh") and is_instance_valid(ctx["veh"]):
		var v: Vehicle = ctx["veh"]
		if b.vehicle == v:
			v.leave(b)
		v.queue_free()
	if ctx.has("pos"):
		b.global_position = ctx["pos"]
	if p == "liegen" or ctx.has("emp") or ctx.has("veh"):
		await seconds(1.0)
	await frames(3)


## Strahl von außen auf die Kistenmitte jeder Zone (6 Richtungen); erster Treffer dieses Soldaten muss die Zone sein
func _check_zones(b: Soldier, p: String) -> void:
	var space := b.get_world_3d().direct_space_state
	var sk := b.model.orig_figure.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# waagerechte Schussrichtungen rund um die Figur (Original-Strahltest 0x455670 wertet die ganze Flugstrecke eines
	# Schritts: von oben durch den Kopf zählt der Körper – daher nur liegend zusätzlich von oben)
	var dirs: Array = []
	for i in 8:
		var a := TAU * float(i) / 8.0
		dirs.append(Vector3(sin(a), 0.0, cos(a)))
	if p == "liegen":
		dirs.append(Vector3.UP)
	var hw := {"i": b.model.orig_figure.find_child("hw1", true, false), "m": b.model.orig_figure.find_child("hw2", true, false)}
	var attached := true
	var hit_ok := true
	var resolved_ok := true
	var bad: Array = []
	var active := 0
	for hb in b.model.orig_zones:
		if hb.collision_layer != 0:
			active += 1
		var bone := String(hb.get_meta("bone"))
		var cs := hb.get_child(0) as CollisionShape3D
		var center := cs.global_position
		# Arme werden nach der Animation per IK/Anschlag verändert: sichtbare Lage = Hand-Dummys hw1/hw2 (dort hängt
		# auch die Waffe); Unterarmkiste muss bis zur Hand reichen. Übrige Gelenke: Abstand Kistenmitte–Gelenk konstant.
		if hw.has(bone) and is_instance_valid(hw[bone]):
			var dh := center.distance_to((hw[bone] as Node3D).global_position)
			if dh > 0.3:
				attached = false
				bad.append("%s %.2f m von der Hand" % [bone, dh])
		elif bone == "f" and is_instance_valid(b.model.orig_figure.find_child("Reye", true, false)):
			# Kopf: sichtbare Augen (Kinder des Kopfgelenks) liegen in der Kopfkiste (Anschlag dreht die Wirbelsäule nach)
			var eye := (b.model.orig_figure.find_child("Reye", true, false) as Node3D).global_position
			var loc := cs.global_transform.affine_inverse() * eye
			var half := (cs.shape as BoxShape3D).size * 0.5 + Vector3.ONE * 0.02
			if absf(loc.x) > half.x or absf(loc.y) > half.y or absf(loc.z) > half.z:
				attached = false
				bad.append("Kopfkiste verfehlt die Augen (%s)" % loc)
		elif not bone in ["h", "l", "c"]:
			var bp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin
			if absf(center.distance_to(bp) - cs.position.length()) > 0.01:
				attached = false
				bad.append("%s nicht am Gelenk" % bone)
		var found := ""
		var res_zone := ""
		var first := ""
		for d in dirs:
			var ex: Array[RID] = []
			var h := {}
			for _i in 8:
				var q := PhysicsRayQueryParameters3D.create(center + d * 1.5, center, Hitbox.LAYER, ex)
				q.collide_with_areas = true
				q.collide_with_bodies = false
				h = space.intersect_ray(q)
				if h.is_empty() or not (h.collider is Hitbox) or (h.collider as Hitbox).soldier == b:
					break
				ex.append((h.collider as Hitbox).get_rid())
			if h.is_empty() or not (h.collider is Hitbox):
				continue
			var o := h.collider as Hitbox
			if first == "":
				first = "%s:%s" % [d, o.zone]
			if o == hb:
				found = str(d)
				res_zone = String(Ballistics._priority_zone(space, o, h.position, -d).zone)
				if res_zone == String(hb.zone):
					break
		zone_txt.append("%s\t%s\t%s\t%.2f\t%s\t%s\t%s" % [p, hb.zone, bone, center.y - b.global_position.y, found if found != "" else "-", first, res_zone])
		if found == "":
			hit_ok = false
			bad.append("%s/%s von keiner Seite zuerst getroffen (%s)" % [hb.zone, bone, first])
		elif res_zone != String(hb.zone) and not (hb.zone == &"arm" and res_zone == "torso"):
			resolved_ok = false
			bad.append("%s/%s aufgelöst als %s" % [hb.zone, bone, res_zone])
	check(active == 10 and attached and hit_ok and resolved_ok, "Trefferzonen %s: 10 Gelenkzonen aktiv, am Gelenk, jede von außen zuerst getroffen" % p, str(bad))


func _zone_shot(b: Soldier, p: String) -> void:
	b.model.show_zones(true)
	var cam := Camera3D.new()
	b.get_parent().add_child(cam)
	cam.fov = 45.0
	cam.current = true
	var c := b.model.orig_zones[0].get_child(0) as Node3D
	var mid := c.global_position
	var fwd := b.forward()
	var right := Vector3(cos(b.look_yaw), 0, -sin(b.look_yaw))
	cam.global_position = mid + fwd * 2.2 + right * 2.2 + Vector3.UP * 0.9
	cam.look_at(mid)
	await seconds(1.0)
	_save_shot("mp_zones_%s.png" % p)
	cam.queue_free()
	b.model.show_zones(false)


func _leave() -> void:
	Net.leave(false)
	await frames(10)


## Gemessene Treffer über Ballistics (Server rechnet den Schaden, Soldier.apply_hit)
func _hits(m: Node, bots: Array) -> void:
	var tgt: Soldier = null
	var shooter: Soldier = null
	for s in bots:
		if s.team == Soldier.TEAM_AXIS and tgt == null:
			tgt = s
		elif s.team == Soldier.TEAM_ALLIED and shooter == null:
			shooter = s
	if tgt == null or shooter == null:
		check(false, "Ziel und Schütze für Treffermessung")
		return
	var plat := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 200)
	cs.shape = bx
	plat.add_child(cs)
	m.add_child(plat)
	plat.global_position = Vector3(0, 599.5, -50)
	for s in [tgt, shooter]:
		s.global_position = Vector3(0, 600.1, 0)
		s.velocity = Vector3.ZERO
		s.look_yaw = 0.0
		s.stance_request = Soldier.Stance.STAND
		s.set_meta("protect_until", 0)
	tgt.look_yaw = PI
	shooter.global_position = Vector3(0, 600.1, -10)
	await frames(30)
	# Original-Figur: Zonen folgen der Haltung → erst messen, wenn das Ziel wirklich steht (Bot kann gelegen haben)
	var st0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - st0 < 8000 and (tgt.stance != Soldier.Stance.STAND or tgt.model._stance_blend.x < 0.98):
		tgt.stance_request = Soldier.Stance.STAND
		await frames(5)
	await seconds(0.5)
	# ohne Helm (sonst teilt der Helm-Zufall den Kopfschaden)
	tgt.set_meta("orig_items", [])
	tgt.set("helmet_style", "cap")
	# Ziel festhalten (keine KI-/Netzbewegung während der Messung)
	tgt.set_physics_process(false)
	for n in tgt.get_children():
		if n is AIBrain or n is Perception:
			n.set_process(false)
			n.set_physics_process(false)
	tgt.velocity = Vector3.ZERO
	var got := []
	var cb := func(amount: float, zone: StringName): got.append([amount, zone])
	tgt.damaged.connect(cb)
	var res: Array[String] = []
	var ok := true
	var mp40 := WeaponDB.get_weapon(&"mp40")
	var hb_by_zone := {}
	# aktive Zonen: Gelenkkisten der Original-Figur (humanzones), sonst Platzhalterpuppe; Arm/Bein = am weitesten außen
	# liegende Kiste (frei von vorn treffbar)
	var zl: Array = []
	if tgt.model and not tgt.model.orig_zones.is_empty():
		zl.append_array(tgt.model.orig_zones)
	else:
		zl.append_array(tgt.find_children("*", "Hitbox", true, false))
	var side := Vector3(cos(tgt.look_yaw), 0, -sin(tgt.look_yaw))
	for hb in zl:
		var h := hb as Hitbox
		if h.collision_layer == 0:
			continue
		var cur: Hitbox = hb_by_zone.get(h.zone)
		var lat := absf(((h.get_child(0) as Node3D).global_position - tgt.global_position).dot(side))
		if cur == null or (h.zone in [&"arm", &"leg"] and lat > absf(((cur.get_child(0) as Node3D).global_position - tgt.global_position).dot(side))):
			hb_by_zone[h.zone] = h
	for zone in [&"torso", &"head", &"arm", &"leg"]:
		var h: Hitbox = hb_by_zone.get(zone)
		if h == null:
			ok = false
			continue
		var c: Vector3 = (h.get_child(0) as Node3D).global_position
		for dist in [10.0, 60.0]:
			tgt.max_health = 100000.0
			tgt.health = 100000.0
			got.clear()
			# Trefferreaktion der Figur abklingen lassen, Zonenlage neu lesen (Zonen folgen der Animation); bei Armen/Beinen
			# die Kiste wählen, die von vorn frei liegt (Strahl + Original-Reihenfolge ergeben genau diese Zone)
			await seconds(1.5)
			var sp := shooter.get_world_3d().direct_space_state
			for cand in zl:
				var ch := cand as Hitbox
				if ch.zone != zone or ch.collision_layer == 0:
					continue
				var cc: Vector3 = (ch.get_child(0) as Node3D).global_position
				var cq := PhysicsRayQueryParameters3D.create(cc - Vector3(0, 0, 3), cc + Vector3(0, 0, 0.3), Hitbox.LAYER, shooter.exclude_rids())
				cq.collide_with_areas = true
				cq.collide_with_bodies = false
				var chit := sp.intersect_ray(cq)
				if not chit.is_empty() and chit.collider is Hitbox and Ballistics._priority_zone(sp, chit.collider, chit.position, Vector3(0, 0, 1)).zone == zone:
					h = ch
					break
			c = (h.get_child(0) as Node3D).global_position
			var dir := Vector3(0, 0, 1)
			var origin: Vector3 = c - dir * float(dist)
			shooter.global_position = Vector3(origin.x, 600.1, origin.z)
			await frames(2)
			var rq := PhysicsRayQueryParameters3D.create(origin, c + dir * 0.3, 1 | Hitbox.LAYER, shooter.exclude_rids())
			rq.collide_with_areas = true
			var rh := shooter.get_world_3d().direct_space_state.intersect_ray(rq)
			print("STRAHL %s %.0f m: %s" % [zone, dist, str(rh.get("collider")) + " " + str(rh.get("position"))])
			# Geschossfall vorhalten (Ballistics: Luftwiderstand 0,0026·v², Schwerkraft): t = (e^{k·d} − 1)/(k·v0)
			var k := 0.0026
			var tf := (exp(k * float(dist)) - 1.0) / (k * mp40.muzzle_velocity)
			var aim_at: Vector3 = c + Vector3.UP * (0.5 * 9.81 * tf * tf)
			# Gelenkkisten sind schmal (Körper ±0,15 m): auf 60 m bei Fehlschuss mit kleinem Höhenversatz wiederholen –
			# geprüft wird hier die Schadensformel nach Strecke und Zone, nicht die Treffsicherheit
			for off in [0.0, 0.12, -0.12, 0.25]:
				Ballistics.fire(shooter, origin, (aim_at + Vector3.UP * float(off) - origin).normalized(), mp40, shooter.exclude_rids(), shooter.team)
				await frames(40)
				if not got.is_empty() or dist < 30.0:
					break
			var hit_zone: StringName = got[0][1] if not got.is_empty() else &""
			var amt: float = float(got[0][0]) if not got.is_empty() else -1.0
			var exp := WeaponDB.zone_damage(WeaponDB.bullet_damage(mp40, dist), hit_zone)
			var good := not got.is_empty() and _near(amt, exp, 0.03 * exp + 0.4)
			ok = ok and good and (hit_zone == zone or dist > 30.0)
			res.append("MP 40 %s %.0f m: getroffen %s, Schaden %.2f (erwartet %.2f)" % [zone, dist, hit_zone, amt, exp])
	tgt.damaged.disconnect(cb)
	for r in res:
		print("TREFFER ", r)
		table.append("Messung " + r)
	check(ok, "Gemessene Treffer (MP 40, 10/60 m) = Original-Formel je Zone", str(res))
	# Kopftreffer tödlich: K98k auf 30 m, Ziel mit 100 LP
	tgt.max_health = 100.0
	tgt.health = 100.0
	var h2: Hitbox = hb_by_zone.get(&"head")
	if h2:
		var c2: Vector3 = (h2.get_child(0) as Node3D).global_position
		var o2 := c2 - Vector3(0, 0, 30)
		shooter.global_position = Vector3(o2.x, 600.1, o2.z)
		await frames(2)
		Ballistics.fire(shooter, o2, (c2 - o2).normalized(), WeaponDB.get_weapon(&"kar98k"), shooter.exclude_rids(), shooter.team)
		await frames(40)
		check(not tgt.alive, "Kopftreffer K98k auf 30 m tötet (48,8 × 5 = 244 > 100)")
	plat.queue_free()


## Original-MG-Stellungen: Modell aus orig_cache, Drehachsen HORT/VERT, Grenzen aus dem Rohr-Frame, Mündung SHDUM,
## Bedienung durch KI/Spieler (Rohr folgt dem Blick, Schuss aus der Mündung, keine Platzhalterwaffe in der Hand)
func _emplacements(m: Node, bots: Array) -> void:
	var emps: Array = get_tree().get_nodes_in_group("emplacements").filter(func(x): return x is OrigInteractive.OrigEmplacement)
	check(emps.size() >= 1, "MG-Stellungen auf der Karte", str(emps.size()))
	if emps.is_empty():
		return
	var model_ok := true
	var info: Array = []
	for e in emps:
		var x := e as OrigInteractive.OrigEmplacement
		var meshes := x.frame.find_children("*", "MeshInstance3D", true, false).size()
		var good := meshes >= 3 and x.hort != null and x.vert != null and x.muzzle != null and x.seat != null
		model_ok = model_ok and good
		info.append("%s %s Netze %d Grenzen %s" % [x.name, x.data.id, meshes, str(x.lim)])
	check(model_ok, "Original-Stellungsmodelle (4DS → glb) mit Drehachsen, Mündung und Sitz geladen", str(info.slice(0, 3)))
	var x: OrigInteractive.OrigEmplacement = emps[0]
	check(String(x.data.id) == "o_33", "Waffe aus dem Rohr-Frame (itemid33 = MG 42)", String(x.data.id))
	var g: Soldier = null
	for s in bots:
		if s.alive and s.team == Soldier.TEAM_AXIS:
			g = s
	if g == null:
		return
	x.mount(g)
	await frames(5)
	check(g.mounted == x and g.global_position.distance_to(x.gunner_spot()) < 0.4, "KI-Schütze sitzt am Sitz-Frame SEAT00")
	check(not is_instance_valid(g.model._weapon_mesh), "Keine Platzhalterwaffe in der Hand des Schützen")
	await _gunner_pose(x, g, "%s %s" % [String(x.data.id), Game.current_mission_id])
	var base := x.frame.global_basis.get_euler().y
	g.look_yaw = base + deg_to_rad(20.0)
	g.look_pitch = deg_to_rad(10.0)
	await frames(3)
	var dir := x.barrel_dir()
	check(dir.dot(g.aim_direction()) > 0.995, "Rohr folgt dem Blick (Seite 20°, Höhe 10°)", "%.4f" % dir.dot(g.aim_direction()))
	g.look_yaw = base + deg_to_rad(170.0)
	g.look_pitch = deg_to_rad(80.0)
	await frames(3)
	check(_near(rad_to_deg(x.aim_yaw), x.lim["left"], 0.5) and _near(rad_to_deg(x.aim_pitch), x.lim["up"], 0.5),
		"Schwenkgrenzen aus dem Originalmodell (links %.0f°, hoch %.0f°)" % [x.lim["left"], x.lim["up"]])
	var n0 := Ballistics._projectiles.size()
	g._fire_shot(g.weapons[0])
	var pr = Ballistics._projectiles.back() if Ballistics._projectiles.size() > n0 else null
	check(pr != null and (pr.pos as Vector3).distance_to(x.muzzle.global_position) < 0.05, "Schuss aus der Mündung SHDUM00 des Modells")
	if bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless":
		await _shot(x, g)
	x.dismount()
	await frames(3)
	check(g.mounted == null and g.weapons[0] != null and String(g.weapons[0].data.id) != "o_33", "Verlassen der Stellung gibt die eigene Waffe zurück")
	await _dismount_check(x, g, String(x.data.id))


## Absteigen: Bedienhaltung/IK aus, Figur gleitet zurück an den Soldaten (kein Sprung)
func _dismount_check(x: OrigInteractive.OrigEmplacement, g: Soldier, label: String) -> void:
	var fig: Node3D = g.model.orig_figure if g.model else null
	if not is_instance_valid(fig):
		return
	var d0 := fig.position.length()
	await seconds(0.6)
	check(g.model.full_clip() == "" and x.pose_ik == null and fig.position.length() < 0.02 and is_instance_valid(g.model._weapon_mesh),
		"%s: Absteigen – Haltung/IK aus, Figur gleitet zurück, eigene Waffe in der Hand" % label, "Versatz %.2f → %.3f m" % [d0, fig.position.length()])


const HAND_TOL := 0.06       ## Abstand Hand-Dummy hw1/hw2 – Griff RWS/LWS nach der IK (m)


func _hand_err(x: OrigInteractive.OrigEmplacement) -> Array:
	if x.pose_ik == null:
		return [-1.0, -1.0]
	print("  IK: Fehler r/l %.3f/%.3f, Vorbeuge %.2f (Ziel %.2f), Höhe %.2f" % [float(x.pose_ik.get("err_r")), float(x.pose_ik.get("err_l")),
		float(x.pose_ik.get("lean")), float(x.pose_ik.get("lean_target")), float(x.pose_ik.get("pitch"))])
	return [float(x.pose_ik.get("err_r")), float(x.pose_ik.get("err_l"))]


func _hands_ok(e: Array) -> bool:
	return e[0] >= 0.0 and e[0] < HAND_TOL and e[1] >= 0.0 and e[1] < HAND_TOL


## Bedienhaltung (docs/re_notes_weapons.md §11): Original-Clip aus anim.sav je SEAT-Haltungsziffer, Figur am SEAT00,
## Hände per IK an RWS/LWS (geradeaus, geschwenkt, erhöht), Clipbild folgt dem Schwenk, Oberkörper der Höhe,
## Rückstoß, Übergang beim Auf-/Absteigen, Kamera 1. Person am CAMERAFPV der Stellung
func _gunner_pose(x: OrigInteractive.OrigEmplacement, g: Soldier, label: String) -> void:
	var m := g.model
	var fig: Node3D = m.orig_figure if m else null
	check(is_instance_valid(fig), "%s: Schütze hat eine Originalfigur" % label)
	if not is_instance_valid(fig):
		return
	var base: float = x.get("base_yaw") if x.get("base_yaw") != null else x.frame.global_basis.get_euler().y
	g.look_yaw = base
	g.look_pitch = 0.0
	await seconds(0.7)
	var clip := x.pose_clip()
	var digit = OrigInteractive.rig_params(x.model_path).get("seat", "-") if x.model_path != "" else "-"
	check(clip.begins_with("emp_") and m.full_clip() == clip, "%s: Bedienhaltung aus anim.sav aktiv" % label, "%s, SEAT-Ziffer %s" % [clip, str(digit)])
	if is_instance_valid(x.pose_seat):
		check(fig.global_position.distance_to(x.pose_seat.global_position) < 0.05, "%s: Figur steht am Sitz-Frame SEAT00 (Übergang beendet)" % label,
			"%.3f m" % fig.global_position.distance_to(x.pose_seat.global_position))
	var e0 := _hand_err(x)
	check(_hands_ok(e0), "%s: beide Hände an den Griffen (geradeaus)" % label, "rechts %.3f m, links %.3f m" % e0)
	var h1: Node3D = fig.find_child("hw1", true, false)
	var hp0: Vector3 = h1.global_position if h1 else Vector3.ZERO
	var seek0: float = float(m.get("full_seek"))
	var cam := g.model.camera_point(true)
	var cam3 := g.model.camera_point(false)
	var head: Vector3 = x._figure_bone("f")
	var cam_dist := cam.distance_to(head)
	check(cam.is_finite() and cam_dist < 0.6 and cam3.is_finite() and cam3.distance_to(head) < 0.8,
		"%s: Kamera 1./3. Person am Schützen in der Stellung (CAMERAFPV bzw. Kopf)" % label, "1. Person %.2f m, 3. Person %.2f m vom Kopf" % [cam_dist, cam3.distance_to(head)])
	# Schwenk nach links (Grenze × 0,8)
	var yl: float = deg_to_rad(float(x.lim["left"]) * 0.8)
	g.look_yaw = base + yl
	await seconds(0.5)
	var e1 := _hand_err(x)
	var seek1: float = float(m.get("full_seek"))
	var moved := (h1.global_position - hp0).length() if h1 else 0.0
	check(_hands_ok(e1) and moved > 0.05, "%s: Hände folgen dem Schwenk (%.0f°)" % [label, rad_to_deg(yl)], "rechts %.3f, links %.3f m, Hand %.2f m bewegt, Clipzeit %.2f → %.2f s" % [e1[0], e1[1], moved, seek0, seek1])
	if clip != "emp_flaksed":
		check(seek1 > seek0 + 0.01, "%s: Ganzkörperbild folgt dem Schwenk (Seitenschwenk-Clip)" % label, "%.3f → %.3f s" % [seek0, seek1])
	var yr: float = deg_to_rad(float(x.lim["right"]) * 0.8)
	g.look_yaw = base - yr
	await seconds(0.5)
	var er := _hand_err(x)
	var seek_r: float = float(m.get("full_seek"))
	check(_hands_ok(er) and (clip == "emp_flaksed" or seek_r < seek0 - 0.01), "%s: Hände und Ganzkörperbild folgen dem Schwenk nach rechts (%.0f°)" % [label, rad_to_deg(yr)],
		"rechts %.3f, links %.3f m, Clipzeit %.3f s" % [er[0], er[1], seek_r])
	# Rohr hoch (Grenze × 0,8): Oberkörper neigt mit
	g.look_yaw = base
	var up: float = minf(deg_to_rad(float(x.lim["up"]) * 0.8), 0.7)
	g.look_pitch = up
	await seconds(0.5)
	var e2 := _hand_err(x)
	check(_hands_ok(e2) and x.pose_ik != null and float(x.pose_ik.get("pitch")) > 0.05, "%s: Hände/Oberkörper folgen der Höhenrichtung (%.0f°)" % [label, rad_to_deg(up)], "rechts %.3f, links %.3f m" % e2)
	# Rückstoß beim Schuss
	g.look_pitch = 0.0
	await seconds(0.2)
	if g.weapons[0] != null:
		g.weapons[0].in_mag = maxi(g.weapons[0].in_mag, 5)
		g._fire_shot(g.weapons[0])
		var kick: float = x.get("_kick")
		await frames(2)
		var e3 := _hand_err(x)
		check(kick > 0.5 and _hands_ok(e3), "%s: Rückstoß beim Schuss, Hände bleiben an den Griffen" % label, "Rückstoß %.2f, rechts %.3f, links %.3f m" % [kick, e3[0], e3[1]])
	if bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless":
		await _pose_shots(x, g, label)


## Fensteraufnahmen der Bedienhaltung: geradeaus, geschwenkt, erhöht (Seitenansicht) und 3. Person (Spielkamera-Abstand)
func _pose_shots(x: OrigInteractive.OrigEmplacement, g: Soldier, label: String) -> void:
	var tag := label.replace(" ", "_").to_lower()
	var base: float = x.get("base_yaw") if x.get("base_yaw") != null else x.frame.global_basis.get_euler().y
	var views := [["gerade", 0.0, 0.0], ["links", float(x.lim["left"]) * 0.8, 0.0], ["rechts", -float(x.lim["right"]) * 0.8, 0.0],
		["hoch", 0.0, minf(float(x.lim["up"]) * 0.8, 40.0)]]
	var cam := Camera3D.new()
	x.add_child(cam)
	cam.fov = 50.0
	cam.current = true
	var was_visible := g.model.visible
	g.model.visible = true          # eigener Spieler im MP ggf. 1. Person (Figur dort ausgeblendet)
	var piv :=x.pose_seat.global_position if is_instance_valid(x.pose_seat) else g.global_position
	var fwd := Vector3(-sin(base), 0, -cos(base))
	var side := Vector3(cos(base), 0, -sin(base))
	# Kamerastandort mit freier Sicht auf den Schützen (vorne schräg, seitlich, oben)
	var look_at := piv + fwd * 0.4 + Vector3.UP * 0.6
	var cands := [fwd * 2.4 + side * 1.4 + Vector3.UP * 1.3, fwd * 2.4 - side * 1.4 + Vector3.UP * 1.3, side * 2.4 + fwd * 0.8 + Vector3.UP * 1.4,
		-side * 2.4 + fwd * 0.8 + Vector3.UP * 1.4, fwd * 1.0 + side * 1.0 + Vector3.UP * 2.6]
	var cpos: Vector3 = piv + cands[0]
	var space := x.get_world_3d().direct_space_state
	for c in cands:
		var q := PhysicsRayQueryParameters3D.create(piv + c, look_at, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(look_at) < 1.0:
			cpos = piv + c
			break
	for v in views:
		g.look_yaw = base + deg_to_rad(float(v[1]))
		g.look_pitch = deg_to_rad(float(v[2]))
		cam.global_position = cpos
		cam.look_at(look_at)
		await seconds(1.0)
		_save_shot("mp_pose_%s_%s.png" % [tag, v[0]])
	# 3. Person: hinter und über dem Schützen in Blickrichtung (gamecam.set 3 m)
	g.look_yaw = base + deg_to_rad(10.0)
	g.look_pitch = 0.0
	cam.global_position = piv - fwd * 3.0 + Vector3.UP * 1.9
	cam.look_at(piv + fwd * 2.0 + Vector3.UP * 0.8)
	await seconds(1.0)
	_save_shot("mp_pose_%s_3rd.png" % tag)
	cam.queue_free()
	g.model.visible = was_visible
	g.look_yaw = base
	g.look_pitch = 0.0


func _save_shot(file: String) -> void:
	var p := ProjectSettings.globalize_path("res://test_output/" + file)
	get_viewport().get_texture().get_image().save_png(p)
	check(FileAccess.file_exists(p), "Fensteraufnahme " + file)


func _shot(x: OrigInteractive.OrigEmplacement, g: Soldier) -> void:
	g.look_yaw = x.frame.global_basis.get_euler().y + deg_to_rad(25.0)
	g.look_pitch = deg_to_rad(5.0)
	var cam := Camera3D.new()
	x.add_child(cam)
	var fwd := -x.frame.global_basis.z
	var side := x.frame.global_basis.x
	cam.global_position = x.frame.global_position + fwd * 2.6 + side * 1.6 + Vector3.UP * 1.5
	cam.look_at(x.frame.global_position + Vector3.UP * 0.8)
	cam.fov = 55.0
	cam.current = true
	await seconds(1.5)
	var img := get_viewport().get_texture().get_image()
	var p := ProjectSettings.globalize_path("res://test_output/mp_mg_emplacement.png")
	img.save_png(p)
	check(FileAccess.file_exists(p), "Fensteraufnahme MG-Stellung", p)
	cam.queue_free()
