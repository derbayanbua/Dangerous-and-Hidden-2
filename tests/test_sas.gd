extends "res://tests/test_gameplay.gd"
## Originalkader (SAS), Teamauswahl-Regeln, gemeinsames Inventar (Taschen + Rucksack), Waffen aus der
## Originaltabelle, Training und Werteverbesserung nach dem Einsatz.
##   tools\godot.cmd --headless -- --autoplay=test_sas
## (Profil/Kampagne im Speicher; es wird nichts geschrieben.)


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
	Game.sas_states()[str(t[0])]["experience"] = 9000
	Game.sas_states()[str(t[0])]["rank"] = 0
	var res := Game.finish_sas([a, b], true)
	var st2 := Game.sas_states()
	check(st2[str(t[1])]["dead"] and not Game.sas_team().has(t[1]), "Gefallener: tot markiert, aus dem Team")
	check(absf(float(st2[str(t[0])]["stats"]["shooting"]) - minf(shoot_a + 0.4, 100.0)) < 0.001, "Team: Schießen +0,04 je Abschuss")
	var d_o := float(st2[str(outsider)]["stats"]["shooting"]) - shoot_o
	check(shoot_o >= 99.99 or (d_o >= 0.4 * 0.6 - 0.001 and d_o <= 0.4 * 1.4 + 0.001), "Übrige Soldaten: Durchschnitt × 0,6–1,4", "%.3f" % d_o)
	check(res["promoted"].size() == 1, "Beförderung bei > 10000 Erfahrung", str(res["promoted"]))
	a.free()
	b.free()
	_finish()
