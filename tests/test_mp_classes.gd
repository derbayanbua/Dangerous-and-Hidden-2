extends "res://tests/test_gameplay.gd"
## 0.11.1: MP-Klassen (MpClasses) – Soldatenwahl nach Kaderwerten, Klassen-Ausrüstung je Karte/Seite, Ersatz bei
## Kartenfreigabe, Panzerabwehr ohne Werfer → Granaten, Uniform je Klima, Werte nur aus roster.json (Client-Werte
## werden verworfen), Schleicher-Bonus, großer Verbandskasten, KI-Klassen.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_mp_classes


func _map_of(folder: String) -> String:
	for id in Game.MP_MAPS:
		if Game.orig_folder(String(id)).to_lower() == folder:
			return String(id)
	return ""


var _nm := ""


func _b(c: int, t: int, mp := "") -> Dictionary:
	var mid: String = mp if mp != "" else _nm
	return MpClasses.build(c, t, MpLoadout.map_allowed(mid), mid, MpClasses.strength_of(MpClasses.best_figure(c)))


func _stat(idx: int, k: String) -> float:
	return float(MpClasses.stats_of(idx).get(k, 0.0))


func _items_of(inv: Dictionary) -> Array:
	var out: Array = []
	for k in SAS.SLOTS:
		if k != "head" and int(inv.get(k, -1)) >= 0:     # Helm gehört zur Uniform (nicht aus dem Lager)
			out.append(int(inv[k]))
	for e in inv.get("items", []):
		out.append(int(e[0]))
	return out


func _run() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and SAS.available(), "Mission und Kaderdaten geladen")
	isolate_enemies([])
	var pool: Array = SAS.store_indices()
	check(pool.size() == 30 and MpClasses.COUNT == 7 and Net.CLASS_NAMES.size() == 7, "30 Kadersoldaten, 7 Klassen")

	# --- Soldatenwahl nach Werten ---
	var mx := func(k: String) -> float:
		var b := -1e9
		for idx in pool:
			b = maxf(b, _stat(int(idx), k))
		return b
	var sn := MpClasses.best_soldier(MpClasses.SNIPER)
	var md := MpClasses.best_soldier(MpClasses.MEDIC)
	var at := MpClasses.best_soldier(MpClasses.ANTITANK)
	var sk := MpClasses.best_soldier(MpClasses.SNEAKER)
	var sc := MpClasses.best_soldier(MpClasses.SCOUT)
	var hv := MpClasses.best_soldier(MpClasses.HEAVY)
	var asl := MpClasses.best_soldier(MpClasses.ASSAULT)
	check(_stat(sn, "shooting") == mx.call("shooting"), "Scharfschütze: bester Schießen-Wert", "%d (%.0f)" % [sn, _stat(sn, "shooting")])
	check(_stat(md, "first_aid") == mx.call("first_aid"), "Sanitäter: bester Erste-Hilfe-Wert", "%d (%.0f)" % [md, _stat(md, "first_aid")])
	check(_stat(at, "strength") == mx.call("strength"), "Panzerabwehr: höchste Kraft", "%d (%.0f kg)" % [at, _stat(at, "strength")])
	check(_stat(sk, "stealth") == mx.call("stealth"), "Schleicher: beste Tarnung", "%d (%.0f)" % [sk, _stat(sk, "stealth")])
	var ss: Array = pool.map(func(i): return _stat(int(i), "strength"))
	ss.sort()
	check(absf(_stat(hv, "strength") - float(ss[ss.size() / 2])) <= 3.0, "Schwerer Schütze: mittlere Traglast",
		"%.0f kg / Median %.0f" % [_stat(hv, "strength"), float(ss[ss.size() / 2])])
	var avg_end := 0.0
	var avg_hp := 0.0
	for idx in pool:
		avg_end += _stat(int(idx), "endurance") / pool.size()
		avg_hp += _stat(int(idx), "health") / pool.size()
	check(_stat(sc, "endurance") > avg_end and _stat(sc, "health") <= avg_hp, "Aufklärer: hohe Ausdauer, wenig Gesundheit",
		"%.0f/%.0f, LP %.0f/%.0f" % [_stat(sc, "endurance"), avg_end, _stat(sc, "health"), avg_hp])
	check(asl >= 0 and asl not in [sn, md, at, sk], "Sturmsoldat: ausgewogener Soldat (kein Spezialist)", str(asl))
	check(MpClasses.best_figure(MpClasses.SNIPER) == "sas:%d" % sn and Net.figure_ids().has("sas:%d" % sn),
		"Klassenwahl → Figur sas:N in der Figurliste")

	# --- Ausrüstung je Klasse/Karte/Seite ---
	var maps := {"desert": _map_of("africa2_mp_zone"), "winter": _map_of("arctic1_mp"), "jungle": _map_of("burma1_mp"),
		"temperate": _map_of("normandy_mp")}
	check(not maps.values().has(""), "Testkarten im Register", str(maps))
	var all_ok := true
	var bad: Array = []
	for clim in maps:
		var map: String = maps[clim]
		var allowed := MpLoadout.map_allowed(map)
		for team in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
			var side := MpClasses.side_of(team)
			for c in MpClasses.COUNT:
				var fig := MpClasses.best_figure(c)
				var stg := MpClasses.strength_of(fig)
				var inv := MpClasses.build(c, team, allowed, map, stg)
				var err := MpLoadout.check(inv, allowed, team, stg, MpLoadout.heads_for(inv, [], side))
				if err != "" or int(inv["hands"]) < 0:
					all_ok = false
					bad.append("%s/%s/%s: %s" % [clim, side, MpClasses.KEYS[c], err if err != "" else "ohne Waffe"])
				for id in _items_of(inv):
					if id != MpClasses.REVIVE_SYRINGE and not allowed.is_empty() and MpLoadout.remaining(SAS.new_inventory(), allowed, team, id) <= 0:
						all_ok = false
						bad.append("%s/%s/%s: %d nicht erlaubt" % [clim, side, MpClasses.KEYS[c], id])
	check(all_ok, "Alle Klassen auf 4 Karten × 2 Seiten: gültig (Lager, Traglast, Plätze) und nur erlaubte Gegenstände", str(bad))

	var nm: String = maps["temperate"]
	var al := MpLoadout.map_allowed(nm)
	var A := Soldier.TEAM_ALLIED
	var X := Soldier.TEAM_AXIS
	_nm = nm
	var med: Dictionary = _b(MpClasses.MEDIC, A)
	check(SAS.count_of(med, 54) == 2 and SAS.count_of(med, 53) == 1 and SAS.count_of(med, MpClasses.REVIVE_SYRINGE) == 1
		and int(med["hands"]) in [21, 11, 20, 18, 4], "Sanitäter: MP/Karabiner, 2 kleine + 1 großer Verbandskasten, Überspritze",
		str(med))
	var sni: Dictionary = _b(MpClasses.SNIPER, A)
	var sct: Dictionary = _b(MpClasses.SCOUT, A)
	check(Net._scoped(OrigInteractive.item_info(int(sni["hands"]))) and Net._scoped(OrigInteractive.item_info(int(sct["hands"])))
		and SAS.weight(int(sni["hands"])) >= SAS.weight(int(sct["hands"])) and SAS.count_of(sct, 99) == 1,
		"Scharfschütze schweres / Aufklärer leichtes Zielfernrohrgewehr, Fernglas", "%d / %d" % [int(sni["hands"]), int(sct["hands"])])
	var hvy: Dictionary = _b(MpClasses.HEAVY, A)
	check(Net._item_type(OrigInteractive.item_info(int(hvy["hands"]))) == 5 and SAS.count_of(hvy, 62) + SAS.count_of(hvy, 60) >= 2,
		"Schwerer Schütze: MG und Granaten", str(hvy["hands"]))
	var ass: Dictionary = _b(MpClasses.ASSAULT, X)
	check(SAS.count_of(ass, 61) >= 4, "Sturmsoldat: viele Granaten", "%d" % SAS.count_of(ass, 61))
	# Kartenfreigabe: MG 42 (33) ist auf den Original-Karten nicht erlaubt → Ersatz
	var hvx: Dictionary = _b(MpClasses.HEAVY, X)
	check(not al.is_empty() and int(hvx["hands"]) != 33 and int(hvx["hands"]) >= 0 and MpLoadout.remaining(SAS.new_inventory(), al, X, int(hvx["hands"])) > 0,
		"Kartenfreigabe: nicht erlaubtes MG 42 → erlaubte Alternative", str(hvx["hands"]))
	# Panzerabwehr mit/ohne erlaubten Werfer
	var at_d: Dictionary = _b(MpClasses.ANTITANK, A, maps["desert"])
	var at_w: Dictionary = _b(MpClasses.ANTITANK, A, maps["winter"])
	check(SAS.count_of(at_d, 39) == 1 and SAS.count_of(at_d, 206) >= 1, "Panzerabwehr: Bazooka + Raketen, wo erlaubt",
		"Raketen %d" % SAS.count_of(at_d, 206))
	var g_w := SAS.count_of(at_w, 62) + SAS.count_of(at_w, 60)
	check(SAS.count_of(at_w, 39) == 0 and g_w > int(MpClasses.GRENADES[MpClasses.ANTITANK]), "Panzerabwehr ohne erlaubten Werfer → mehr Granaten",
		"%d Granaten" % g_w)
	check(Net._item_type(OrigInteractive.item_info(int(at_d["hands"]))) == 4 and SAS.weight(int(at_d["hands"])) < 3.0,
		"Panzerabwehr: leichter Karabiner", str(at_d["hands"]))
	# Uniform je Karte
	var u := func(clim: String, t: int) -> int: return int(MpClasses.build(MpClasses.ASSAULT, t, MpLoadout.map_allowed(maps[clim]), maps[clim], 40.0)["uniform"])
	check(u.call("winter", A) == 122 and u.call("winter", X) == 126, "Uniform Arktis: Winteruniformen", "%d/%d" % [u.call("winter", A), u.call("winter", X)])
	check(u.call("desert", A) == 119 and u.call("desert", X) == 139, "Uniform Afrika: Wüstenuniformen", "%d/%d" % [u.call("desert", A), u.call("desert", X)])
	check(u.call("jungle", A) == 120 and u.call("temperate", A) == 123 and u.call("temperate", X) == 129, "Uniform Burma/Normandie")
	var winv: Dictionary = MpClasses.build(MpClasses.ASSAULT, X, [], "mp_arctic1_mp", 40.0)
	check(int(winv["head"]) == MpLoadout.uniform_head(int(winv["uniform"])) and int(winv["head"]) >= 0, "Helm passend zur Uniform")

	# --- Werte: Quelle nur roster.json, Client-Werte verworfen ---
	var base: Vector3 = m.squad.leader().global_position + Vector3(4, 0, 0)
	var s: Soldier = m.spawn_squad_member(base, 0.0, "MP", ["garand", "colt"], "mp_cls_1")
	await frames(2)
	s.skill_shooting = 100.0
	s.max_health = 999.0
	MpClasses.apply_stats(s, "sas:%d" % sn, MpClasses.SNIPER)
	check(is_equal_approx(s.skill_shooting, _stat(sn, "shooting")) and is_equal_approx(s.max_health, _stat(sn, "health") * OrigMission.HP_SCALE)
		and is_equal_approx(FieldInventory.strength(s), _stat(sn, "strength")) and is_equal_approx(float(s.get_meta("lockpick")), _stat(sn, "lockpick")),
		"Kaderwerte auf der MP-Figur (wie Einzelspieler)", "%.0f / %.1f LP" % [s.skill_shooting, s.max_health])
	var forged := MpLoadout.sanitize({"hands": 10, "items": [[180, 2]], "stats": {"shooting": 100}, "health": 999, "strength": 99})
	check(not forged.has("stats") and not forged.has("health") and not forged.has("strength"), "Server: Werte im Ausrüstungspaket verworfen")
	check(not Net.figure_ids().has("sas:99") and MpClasses.effective_figure("sas:99", MpClasses.MEDIC) == MpClasses.best_figure(MpClasses.MEDIC),
		"Server: unbekannte Figur abgelehnt → Soldat der Klasse")
	check(MpClasses.effective_figure("", MpClasses.SCOUT) == "sas:%d" % sc, "Ohne Figurwahl: Soldat der Klasse")

	# --- Schleicher-Bonus ---
	var sd := m.spawn_squad_member(base + Vector3(3, 0, 0), 0.0, "SD", [String(WeaponDB.from_orig(7).id), "colt"], "mp_cls_2")
	await frames(2)
	sd.select_slot(0)
	sd.aiming = true
	sd.stamina = 100.0
	sd.velocity = Vector3.ZERO
	await frames(2)
	MpClasses.apply_stats(sd, "sas:%d" % sk, MpClasses.ASSAULT)
	var sp0 := sd.current_spread()
	MpClasses.apply_stats(sd, "sas:%d" % sk, MpClasses.SNEAKER)
	var sp1 := sd.current_spread()
	check(sp1 < sp0 * 0.8 and sp1 > 0.0, "Schleicher: weniger Streuung mit Schalldämpferwaffe", "%.3f° → %.3f°" % [sp0, sp1])
	s.select_slot(0)
	s.aiming = true
	MpClasses.apply_stats(s, "sas:%d" % sk, MpClasses.ASSAULT)
	var g0 := s.current_spread()
	MpClasses.apply_stats(s, "sas:%d" % sk, MpClasses.SNEAKER)
	check(is_equal_approx(s.current_spread(), g0), "Schleicher-Bonus nicht bei Waffen ohne Schalldämpfer")

	# --- Klassen auf dem Soldaten (Net._apply_class, wie Server/Clients/KI) ---
	Net._apply_class(m, sd, X, MpClasses.SNEAKER)
	var pw: Weapon = sd.weapons[WeaponData.Slot.PRIMARY]
	check(pw != null and CommandMenu.has_silenced(sd) and String(sd.get_meta("mp_class", "")) == MpClasses.label(MpClasses.SNEAKER),
		"Schleicher (Achse): Schalldämpferwaffe", pw.data.id if pw else "-")
	Net._apply_class(m, s, A, MpClasses.MEDIC)
	check(s.medkits == 3 and int(s.get_meta("big_medkits", 0)) == 1, "Sanitäter am Soldaten: 3 Verbände, davon 1 groß")
	var pat: Soldier = m.squad.members[0] if m.squad.members[0] != s and m.squad.members[0] != sd else m.squad.members[1]
	pat.health = 1.0
	var big := s.apply_bandage(pat)
	pat.health = 1.0
	var small := s.apply_bandage(pat)
	check(big > small * 1.8, "Großer Verbandskasten heilt doppelt", "+%.1f / +%.1f" % [big, small])
	check(MpClasses.BOT_ROLE.size() == MpClasses.COUNT and int(MpClasses.BOT_ROLE[MpClasses.MEDIC]) == BotBrain.Role.MEDIC
		and int(MpClasses.BOT_ROLE[MpClasses.ANTITANK]) == BotBrain.Role.AT, "KI-Soldaten: Rolle je Klasse")
	_finish()
