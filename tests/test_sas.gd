extends "res://tests/test_gameplay.gd"
## Originalkader (SAS), Teamauswahl-Regeln, gemeinsames Inventar (Taschen + Rucksack), Waffen aus der
## Originaltabelle, Training und Werteverbesserung nach dem Einsatz.
##   tools\godot.cmd --headless -- --autoplay=test_sas
## (Profil/Kampagne im Speicher; es wird nichts geschrieben.)

const ItemOrderT := preload("res://src/ui/item_order.gd")


func _run() -> void:
	await frames(5)
	check(SAS.available(), "Kaderdaten vorhanden (roster.json, inventory_rules.json)")
	var st := SAS.new_states()
	check(st.size() == 30, "30 auswählbare SAS-Soldaten", str(st.size()))
	var lauer: Dictionary = st.get("0", {})
	check(SAS.display_name(0).contains("Lauer") and float(lauer["stats"]["health"]) == 515.0 and float(lauer["stats"]["strength"]) == 21.0,
		"Originalwerte (Douglas Lauer: Gesundheit 515, Kraft 21)", SAS.display_name(0))
	check(SAS.rank_name(1) == "Corporal" and SAS.rank_name(1, true) == "Corp.", "Ränge aus den Originaltexten", SAS.rank_name(1))
	var team := SAS.auto_select(st, 4)
	var uniq := {}
	for i in team:
		uniq[i] = true
	check(team.size() == 4 and uniq.size() == 4, "Automatische Auswahl: 4 verschiedene Soldaten", str(team))

	# --- Inventar ---
	var inv := SAS.preset_inventory(1)        # ice_rifle
	check(inv["hands"] == 10 and inv["back"] == 228 and SAS.count_of(inv, 180) == 5, "Preset „ice_rifle“: Garand, Rucksack EN3, 5 Magazine")
	check(SAS.inv_capacity(inv) == 62.0, "Gemeinsames Inventar: 12 Taschen + 50 Rucksack = 62 Raum", str(SAS.inv_capacity(inv)))
	var lo := SAS.to_loadout(inv)
	check(lo["loadout"][0] == "garand" and lo["loadout"][1] == "colt" and lo["loadout"][2] == "no69",
		"Ausrüstung im Spiel: Garand, Colt, Granate No. 69", str(lo["loadout"]))
	check(int(lo["mags"]["garand"]) == 5 and int(lo["medkits"]) == 1 and int(lo["grenades"]) == 1, "Magazine, Verband, Granaten gezählt", str(lo))
	var light := SAS.new_inventory()
	for i in 12:
		SAS.add_item(light, 9)     # Kompass, Raum 1
	check(not SAS.can_add(light, 30.0, 9), "Ohne Rucksack: 12 Raumeinheiten voll")
	light["back"] = 101         # backpack EN: +30
	check(SAS.can_add(light, 30.0, 9, 10), "Mit Rucksack mehr Platz – ohne Umschichten zwischen Tasche und Rucksack")
	check(not SAS.can_add(light, 5.0, 29), "Traglast: Bren (10,1 kg) bei Kraft 5 kg abgelehnt")

	# --- Waffen aus der Originaltabelle ---
	var delisle := WeaponDB.from_orig(7)
	check(delisle != null and delisle.action == WeaponData.Action.BOLT and delisle.noise_radius < 20.0 and is_equal_approx(delisle.damage, 62.0),
		"De Lisle aus item_shoot.tbl erzeugt (Repetierer, schallgedämpft, Schaden 620/10)")
	check(WeaponDB.from_orig(41) == null, "Geschütz (1540 kg) ist keine Handwaffe")
	check(WeaponDB.get_weapon(&"o_7") == delisle, "Erzeugte Waffe über ihre ID abrufbar (Spielstände)")

	# --- Missionsregeln (Gamedata00.gdt) ---
	Game.campaign = {"unlocked": [Game.CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
	check(Game.uses_sas("a1_blizzard") and not Game.uses_sas("m01_funkfeuer"), "Originalkampagne nutzt den Kader, Übungseinsätze nicht")
	check(Game.sas_team_mode("a1_blizzard") == "select", "Arctic 1A: Teamauswahl (Kampagnenbeginn)")
	Game.prepare_sas("a1_blizzard")
	check(Game.sas_team().size() == 4, "Team vorbereitet", str(Game.sas_team()))
	check(Game.sas_team_mode("a2_erkundung") == "keep" and Game.sas_team_mode("a3_rendezvous") == "keep",
		"Arctic 1B/1C: keine Auswahl (Team bleibt)")
	check(Game.sas_team_mode("a4_eisberg") == "refill", "Arctic 2: Team wieder auffüllen")
	check(Game.sas_team_mode("af1_spaghetti_airport") == "select", "Afrika 1: neue Teamauswahl")
	var store: Array = Game.campaign.get("storage", [])
	var colts := 0
	for e in store:
		if int(e[0]) == 2:
			colts = int(e[1])
	check(colts == 5, "Lager aus Gamedata00.gdt (5× Colt 1911)", str(colts))
	var have_cam := 0
	var have_cut := 0
	for i in Game.sas_team():
		have_cam += SAS.count_of(Game.sas_inventory(i), 229)
		have_cut += SAS.count_of(Game.sas_inventory(i), 59)
	check(have_cam >= 1 and have_cut >= 1, "Benötigte Gegenstände (Fotoapparat, Drahtschere) im Team")

	# --- Bildschirm: Team und Ausrüstung ---
	var scr := SasScreen.new()
	get_tree().root.add_child(scr)
	scr.open("a1_blizzard")
	await frames(2)
	check(scr.page == "team", "Bildschirm beginnt mit der Teamauswahl")
	var first: int = Game.sas_team()[0]
	scr.team_remove(first)
	check(Game.sas_team().size() == 3, "ENTFERNEN")
	scr.team_add(first)
	check(Game.sas_team().size() == 4, "HINZUFÜGEN")
	scr.show_equipment()
	await frames(2)
	check(scr.page == "equip" and scr.can_start() == "", "Inventar-Auswahl: startbereit", scr.can_start())
	var sold := scr.focus_idx
	var inv2 := Game.sas_inventory(sold)
	var before := SAS.count_of(inv2, 54)
	scr.take_back(sold, 54)
	check(SAS.count_of(inv2, 54) == before - 1, "Gegenstand ins Lager zurück")
	check(scr.give(sold, 54), "Gegenstand aus dem Lager übernommen")
	var bren_store := false
	for e in Game.campaign["storage"]:
		bren_store = bren_store or int(e[0]) == 29
	if bren_store:
		# Bren in die Hände: bisherige Langwaffe -> Schulter bzw. Lager; Gewicht wird geprüft
		var strength := float(Game.sas_states()[str(sold)]["stats"]["strength"])
		var w0 := SAS.inv_weight(Game.sas_inventory(sold))
		var ok := scr.give(sold, 29)
		var w := SAS.inv_weight(Game.sas_inventory(sold))
		# angenommen -> Traglast eingehalten; abgelehnt -> hätte sie überschritten, Inventar unverändert
		check((ok and w <= strength + 0.01) or (not ok and w0 + SAS.weight(29) > strength - 4.2 and is_equal_approx(w, w0)),
			"Bren: Traglast geprüft", "%.1f kg (vorher %.1f, Kraft %.1f, ok %s)" % [w, w0, strength, ok])
	Game.sas_inventory(sold)["items"].append([245, 5])   # 5 Goldbarren à 12 kg
	check(scr.can_start() != "" and not scr.try_start(), "Überladen: Fortsetzen gesperrt (wie im Original)", scr.can_start())
	Game.sas_inventory(sold)["items"] = Game.sas_inventory(sold)["items"].filter(func(e): return int(e[0]) != 245)
	check(scr.can_start() == "", "Nach dem Ablegen wieder startbereit", scr.can_start())
	# --- Original-Layout (items selection.4ds / team members selection.4ds) ---
	check(SAS.item_label(229) == SAS.text(1229, "") and SAS.item_label(229) != SAS.item_name(229),
		"Gegenstandsnamen aus den Originaltexten", SAS.item_label(229))
	check(SAS.item_icon_path(21) != "" and FileAccess.file_exists(SAS.item_icon_path(21)), "Gegenstandssymbol (wi_br-sten)",
		SAS.item_icon_path(21))
	scr.show_equipment()
	await frames(2)
	check(scr.has_layout() and scr.find_child("Continue", true, false) != null and scr.find_child("Recommended", true, false) != null
		and scr.find_child("StatusToggle", true, false) != null, "Inventar: Original-Knöpfe aus dem Modell")
	var cols := scr.split_columns(Game.sas_inventory(sold))
	var pocket_sp := 0.0
	for e in cols[0]:
		pocket_sp += SAS.space(int(e[0])) * int(e[1])
	check((cols[0].size() + cols[1].size()) == Game.sas_inventory(sold)["items"].size() and pocket_sp <= SAS.POCKET_SPACE + 0.01,
		"Taschen (≤ 12 Raum) + Rucksack: Anzeige des gemeinsamen Inventars", "%d + %d, %.0f" % [cols[0].size(), cols[1].size(), pocket_sp])
	scr.category = 1
	var rows := scr.store_rows()
	var all_mid := not rows.is_empty()
	for r in rows:
		var rid := int(r["id"])
		var rc: int = ItemOrderT.ammo_category(rid) if ItemOrderT.is_ammo(rid) else SAS.item_category(rid)
		all_mid = all_mid and rc == 1
	check(all_mid, "Lager-Klassifizierung MITTLERE WAFFEN", str(rows.map(func(r): return SAS.item_label(int(r["id"])))))
	await _check_ammo_order(scr, sold)
	var sten_before := SAS.count_of(Game.sas_inventory(sold), 190)
	scr._store_click(190, true)
	check(SAS.count_of(Game.sas_inventory(sold), 190) == sten_before + 1, "Doppelklick im Lager übernimmt (Sten-Magazin)")
	scr.take_back(sold, 190)
	scr.status_page = true
	scr.show_equipment()
	await frames(2)
	check(scr.find_child("text_shooting01", true, false) != null, "Umschaltung SOLDATEN-STATUS ANZEIGEN (Werteleisten)")
	scr.status_page = false
	scr.show_team()
	await frames(2)
	check(scr.find_child("Pool%d" % SAS.store_indices()[0], true, false) != null and scr.find_child("PoolRight", true, false) != null,
		"Teamauswahl: Porträtstreifen mit Bildlauf")
	var info_b := scr.find_child("Info", true, false) as Button
	if info_b:
		info_b.pressed.emit()
	await frames(2)
	check(scr.info_page and scr.find_child("Bio", true, false) != null, "SOLDATEN-INFO zeigt die Biografie")
	scr.queue_free()

	# --- Training und Werte nach dem Einsatz ---
	var g := SAS.training_gain({"kills": 100, "sprint_s": 60.0, "sneak_s": 45.0, "heals": 2, "unseen_kills": 1})
	check(is_equal_approx(g["shooting"], 2.0) and is_equal_approx(g["endurance"], 0.2) and is_equal_approx(g["stealth"], 0.13)
		and is_equal_approx(g["first_aid"], 0.2) and is_equal_approx(g["strength"], 0.5) and is_equal_approx(g["morale"], 1.0),
		"Training: Obergrenzen und Raten wie im Original", str(g))
	var t: Array = Game.sas_team()
	var a := Soldier.new()
	a.persistent_id = "sas_%d" % t[0]
	a.training = {"kills": 10.0}
	var b := Soldier.new()
	b.persistent_id = "sas_%d" % t[1]
	b.alive = false
	var outsider := -1
	for k in Game.sas_states():
		if not t.has(int(k)):
			outsider = int(k)
			break
	var shoot_a := float(Game.sas_states()[str(t[0])]["stats"]["shooting"])
	var shoot_o := float(Game.sas_states()[str(outsider)]["stats"]["shooting"])
	Game.sas_states()[str(t[0])]["experience"] = 9500
	Game.sas_states()[str(t[0])]["rank"] = 0
	Game.discard_debrief()
	var res := Game.finish_sas([a, b], true)
	check(not Game.sas_states()[str(t[1])]["dead"] and is_equal_approx(float(Game.sas_states()[str(t[0])]["stats"]["shooting"]), shoot_a),
		"Werte erst bei SPEICHERN UND FORTSETZEN übernommen (0x68C300)")
	var pm: Array = res.get("members", [])
	check(pm.size() == 2 and float(pm[0]["gains"].get("shooting", 0.0)) > 0.39, "Nachbesprechung: Zuwachs je Wert (rote Balken)", str(pm))
	Game.commit_debrief()
	var st2 := Game.sas_states()
	check(st2[str(t[1])]["dead"] and not Game.sas_team().has(t[1]), "Gefallener: tot markiert, aus dem Team")
	check(absf(float(st2[str(t[0])]["stats"]["shooting"]) - minf(shoot_a + 0.4, 100.0)) < 0.001, "Team: Schießen +0,04 je Abschuss")
	var d_o := float(st2[str(outsider)]["stats"]["shooting"]) - shoot_o
	check(shoot_o >= 99.99 or (d_o >= 0.4 * 0.6 - 0.001 and d_o <= 0.4 * 1.4 + 0.001), "Übrige Soldaten: Durchschnitt × 0,6–1,4", "%.3f" % d_o)
	check(res["promoted"].size() == 1, "Beförderung bei > 10000 Erfahrung", str(res["promoted"]))
	# Erfahrung nach Original 0x5A9640: +100 je Abschuss, +300 bei ahnungslosem Gegner, +1000 je erfülltem Ziel
	check(SAS.experience_gain({"kills": 3.0, "unseen_kills": 1.0}, true, true, 2) == 2500, "Erfahrung: 2×100 + 300 + 2×1000")
	# Orden (0x68C900): Afrika → Africa Star; Alpen → Germany-France Star; VC ab 15000 auch posthum; War Medal nach Einsätzen
	check(SAS.award_medal({"medals": [], "rank": 0, "missions": 1}, 0, 2) == 10, "Afrika: Africa Star")
	check(SAS.award_medal({"medals": [10], "rank": 3, "missions": 2}, 0, 2) == 3, "Afrika: Africa General Service Medal (Rang/Einsätze)")
	check(SAS.award_medal({"medals": [], "rank": 0, "missions": 1}, 0, 5) == 9, "Alpen: Germany-France Star")
	check(SAS.award_medal({"medals": [], "rank": 0, "missions": 1, "dead": true}, 15000, 1) == 8, "Victoria Cross posthum ab 15000")
	check(SAS.award_medal({"medals": [], "rank": 0, "missions": 1}, 9000, 1) == 1, "DCM ab 9000 Erfahrung")
	check(SAS.award_medal({"medals": [], "rank": 3, "missions": 1}, 0, 1) == 5, "War Medal (1 Einsatz, Rang ≥ 3)")
	# Defence Medal beim Kampagnenbeginn (0x6908F0): gelistete lebende Soldaten
	Game.campaign = {"unlocked": [Game.CAMPAIGN_ORDER[0]], "completed": [], "fallen": []}
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	Game.prepare_sas("af1_spaghetti_airport", true)
	check((Game.sas_states()["7"].get("medals", []) as Array).has(6), "Afrika-Beginn: Defence Medal (Tabelle 0x841CB0)")
	# Spielmodi: Einzelgänger = 1 Mann, Blutbad-Spieltyp für die Skripte
	Game.set_game_mode(Game.MODE_LONE_WOLF)
	Game.prepare_sas("a1_blizzard", true)
	check(Game.sas_team().size() == 1 and Game.sp_game_type() == 2, "Einzelgänger: Team aus einem Mann, _SPGetGameType 2",
		str(Game.sas_team()))
	check(Game.sas_team_mode("a4_eisberg") == "keep", "Einzelgänger: „Team wieder auffüllen“ entfällt (0x6C20F0)")
	Game.set_game_mode(Game.MODE_CARNAGE)
	check(Game.sp_game_type() == 3 and Game.is_carnage() and Game.campaign.get("completed", []).is_empty(),
		"Blutbad: eigener Kampagnenstand, _SPGetGameType 3")
	Game.set_game_mode(Game.MODE_CARNAGE, true)
	check(Game.sp_game_type() == 7 and Game.single_mission and Game.sas_team_mode("a2_erkundung") == "select",
		"Einzelmission-Blutbad: Spieltyp 7, Teamauswahl")
	var sm_store := Game.single_mission_storage("a3_rendezvous")
	check(not sm_store.is_empty(), "Einzelmission: Lager = Summe der Kampagnenlisten bis zur Mission", str(sm_store.size()))
	Game.end_single_mission()
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	check(Game.game_mode == Game.MODE_CAMPAIGN and not Game.single_mission, "Zurück zur Kampagne")
	# Speicherbegrenzung (0x69CEFA): Schwer 3 Plätze, Sehr schwer keiner
	var d0 := Game.difficulty()
	Game.profile["difficulty"] = 3
	Game.saves_used = 1
	check(Game.saves_left() == 2, "Schwer: 3 Speicherplätze je Einsatz (T9526)")
	Game.profile["difficulty"] = 4
	check(Game.saves_left() == 0, "Sehr schwer: Speichern nicht möglich (T6599)")
	Game.profile["difficulty"] = 2
	check(Game.saves_left() == -1, "Normal: unbegrenzt")
	Game.profile["difficulty"] = d0
	Game.saves_used = 0
	a.free()
	b.free()
	_finish()


## Vorgabe Auftraggeber: passende Munition steht immer direkt unter der passenden Waffe (Lagerliste, Taschen/
## Rucksack, Ingame-Inventar); gemeinsame Munition nur unter der ersten Waffe; Munition ohne Waffe am Ende
func _check_ammo_order(scr: SasScreen, _sold: int) -> void:
	var saved: Array = Game.campaign.get("storage", []).duplicate(true)
	var saved_cat := scr.category
	# Sten + Sten (Schalld.) teilen Magazin 190; MP 40-Magazin 187 ohne MP 40; MG-42-Gurt 216 nur mit MG 15 (schwer)
	Game.campaign["storage"] = [[187, 4], [190, 9], [22, 1], [21, 2], [20, 1], [216, 3], [37, 1], [172, 6], [7, 1], [2, 2]]
	scr.category = 1
	var rows := scr.store_rows()
	var ids: Array = rows.map(func(r): return int(r["id"]))
	var sten_first := SAS.item_label(21) < SAS.item_label(22)
	var first_sten := 21 if sten_first else 22
	var ok := true
	var ammo_rows := 0
	for r in rows:
		if int(r.get("ammo", -1)) == 190:
			ammo_rows += 1
			ok = ok and int(r["id"]) == first_sten
	check(ok and ammo_rows == 1, "Lager: Sten-Magazin genau einmal, unter der ersten Sten", str(rows))
	check(not ids.has(216) and ids.back() == 187 and not ids.has(190),
		"Lager: Munition ohne Waffe (MP 40) am Ende der Kategorie, MG-42-Gurt bei seinem MG 15", str(ids))
	scr.category = 2
	rows = scr.store_rows()
	var mg15_row := {}
	for r in rows:
		if int(r["id"]) == 37:
			mg15_row = r
	check(int(mg15_row.get("ammo", -1)) == 216, "Lager SCHWERE WAFFEN: MG-42-Gurt unter dem MG 15", str(rows))
	scr.category = 0
	rows = scr.store_rows()
	var colt_first := SAS.item_label(2) < SAS.item_label(7)
	var c_ok := 0
	for r in rows:
		if int(r.get("ammo", -1)) == 172:
			c_ok += 1 if int(r["id"]) == (2 if colt_first else 7) else 100
	check(c_ok == 1, "Lager: Colt-1911-Munition nur unter der ersten Waffe (Colt / De Lisle)", str(rows))
	scr.category = 5
	rows = scr.store_rows()
	var none_ammo := true
	for r in rows:
		none_ammo = none_ammo and not ItemOrderT.is_ammo(int(r["id"]))
	check(none_ammo, "ZUSÄTZLICHE AUSRÜSTUNG: keine Waffenmunition mehr dort", str(rows))
	Game.campaign["storage"] = saved
	scr.category = saved_cat
	# Inventar des Soldaten: Sten in den Händen -> Sten-Magazin oben; Colt in der Tasche -> Colt-Munition direkt
	# darunter; MP-40-Magazin ohne Waffe am Ende
	var inv := {"hands": 21, "shoulder": -1, "head": -1, "uniform": -1, "back": 101,
		"items": [[172, 2], [9, 1], [187, 1], [2, 1], [190, 3]]}
	var want := [190, 9, 2, 172, 187]
	for cols in [scr.split_columns(inv), IngameInventory.split_columns(inv)]:
		var seq: Array = []
		for e in cols[0] + cols[1]:
			seq.append(int(e[0]))
		check(seq == want, "Taschen/Rucksack: Munition unter ihrer Waffe, ohne Waffe am Ende", str(seq))
	check(inv["items"][0][0] == 172, "Reihenfolge ist nur Anzeige (Inventar unverändert)")
	await frames(1)
