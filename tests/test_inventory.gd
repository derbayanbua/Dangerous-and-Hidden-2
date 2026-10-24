extends "res://tests/test_gameplay.gd"
## Ingame-Inventar nach dem Original (gameinterface.4ds „inventory“, Taste I = T2847) und Durchsuchen mit zwei
## Inventaren: Öffnen/Schließen (I, Esc), keine Pause, Maus frei, Linksklick schießt nicht, Gegenstand verschieben,
## Waffe in die Hand (wirkt sofort inkl. HUD), Wegwerfen/Aufheben, Leiche durchsuchen (Waffe + Munition nehmen),
## Uniform nur vom Gefangenen. Danach Mehrspieler zweiprozessig (Server + Client tests/test_inventory_client.gd):
## Durchsuchen einer Leiche wird über den Server abgeglichen.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_inventory [--phase=sp|mp|all]
## Fenster (Kontrollbilder test_output/inventory_*.png): ohne --headless, zusätzlich --shots=1

const MP_PORT_OFS := 40
const ItemOrderT := preload("res://src/ui/item_order.gd")
const RESULT := "user://inv_client_result.txt"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func place(s: Soldier, x: float, z: float, yaw: float) -> void:
	s.global_position = mission().lb.ground(x, z, 0.3)
	s.look_yaw = yaw
	s.velocity = Vector3.ZERO


func inv_ui() -> IngameInventory:
	return mission().controller.inventory


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not Game.cli.has("shots"):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var p := ProjectSettings.globalize_path("res://test_output/inventory_%s.png" % name)
	img.save_png(p)
	print("BILD ", p)


func _run() -> void:
	var phase := String(Game.cli.get("phase", "all"))
	if phase in ["all", "sp"]:
		await _sp()
	if phase == "real":
		await _real()
	if phase in ["all", "mp"]:
		await _mp()
	_finish()


## Echte Taste (Ereignis über den Viewport wie vom Betriebssystem, keine Test-API)
func press_key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
		await frames(3)


## Blick auf einen Punkt (Brusthöhe)
func face(s: Soldier, p: Vector3) -> void:
	var to := p - s.eye_position()
	s.look_yaw = atan2(-to.x, -to.z)
	s.look_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 1.2)


## Mittelpunkt der sichtbaren Figur (Leiche liegt nach der Todesanimation nicht am Ursprung)
static func body_center(s: Soldier) -> Vector3:
	var box := AABB()
	var first := true
	for n in s.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := vi.global_transform * vi.get_aabb()
		if b.size.length() > 6.0:
			continue
		box = b if first else box.merge(b)
		first = false
	return s.global_position if first else box.get_center()


## Echter Spielablauf (Einzelspieler, z. B. --mission=a1_blizzard): Gegner töten, zur Leiche, Benutzen-Taste F
func _real() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.nav_ready:
			break
	var m := mission()
	var lead := m.squad.leader()
	# Einleitungssequenz abwarten (Originalmissionen sperren bis dahin die Eingaben)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		var rt = m.get("runtime")
		if m.controller.input_enabled and not (rt != null and bool(rt.get("in_cutscene"))):
			break
		await frames(10)
	check(m.controller.input_enabled, "Spieleingaben frei (nach Einleitung)")
	var target: Soldier = null
	var best := 1e9
	for e in m.enemies:
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(lead.global_position) < best:
			best = e.global_position.distance_to(lead.global_position)
			target = e
	check(target != null, "Gegner vorhanden", target.name if target else "-")
	if target == null:
		return
	isolate_enemies([target.persistent_id])
	var eb := target.get_node_or_null("EnemyBrain")
	if eb:
		eb.set("enabled", false)
	target.set_physics_process(true)
	# Spieler neben den Gegner, Gegner fällt durch echten Treffer (apply_hit wie ein Projektil)
	var dir := (target.global_position - lead.global_position)
	dir.y = 0.0
	lead.global_position = target.global_position - dir.normalized() * 3.0 + Vector3.UP * 0.3
	lead.velocity = Vector3.ZERO
	await frames(10)
	target.apply_hit(5000.0, &"torso", lead, dir.normalized())
	await seconds(2.5)
	check(not target.alive, "Gegner getötet")
	var bc := body_center(target)
	print("REAL: Ursprung %s, Figur %s (Abstand %.2f m)" % [target.global_position, bc, Vector2(bc.x - target.global_position.x, bc.z - target.global_position.z).length()])
	# zur Leiche gehen (echte Bewegung mit W, Blick auf die Figur)
	face(lead, bc)
	Input.action_press("move_forward")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		face(lead, bc)
		await frames(2)
		var flat := Vector2(bc.x - lead.global_position.x, bc.z - lead.global_position.z).length()
		if flat < 1.4:
			break
	Input.action_release("move_forward")
	await frames(10)
	face(lead, bc)
	await frames(5)
	var it = m.controller.interact_target
	check(it != null and (it is Pickups.Loot or it is FieldInventory.SearchSpot), "Leiche ist Benutzen-Ziel (Hinweis „Durchsuchen“)",
		str(it.get("prompt")) if it else "kein Ziel")
	await press_key(KEY_F)
	await frames(5)
	var ui := inv_ui()
	check(ui.is_open() and ui.other == target, "Taste F an der Leiche öffnet das Inventar mit beiden Inventaren")
	await shot("real_sp")
	await press_key(KEY_I)
	check(not ui.is_open(), "Taste I schließt")


# --- Einzelspieler -------------------------------------------------------------------------------------------

func _sp() -> void:
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	isolate_enemies([])
	var hale := m.squad.leader()
	for mm in m.squad.members:
		if mm != hale:
			var sb := m.squad.brain_of(mm)
			sb.roe = SquadBrain.ROE.HOLD_FIRE
			sb.set_order(SquadBrain.Order.HOLD)
			place(mm, -100 + m.squad.members.find(mm) * 2.0, 100, 0.0)
			sb.hold_pos = mm.global_position
	place(hale, 5, 21, 0.0)
	hale.select_slot(WeaponData.Slot.PRIMARY)
	await frames(10)

	# --- Tastenbelegung (Original Options.bin: INVENTAR = I, GEGENST. FALLENL. = Rücktaste) ---
	var ev_i: Array = InputMap.action_get_events("inventory")
	check(not ev_i.is_empty() and ev_i[0] is InputEventKey and (ev_i[0] as InputEventKey).physical_keycode == KEY_I,
		"Taste I = Inventar (Original-Standardbelegung T2847)")
	var ev_d: Array = InputMap.action_get_events("drop_item")
	check(not ev_d.is_empty() and (ev_d[0] as InputEventKey).physical_keycode == KEY_BACKSPACE, "Rücktaste = Gegenstand fallenlassen (T2827)")
	check(InputSetup.ACTIONS.has("inventory") and InputSetup.display_name("inventory") == "Inventar", "Inventar in der Tastenbelegung")

	# --- Öffnen mit I ---
	var ui := inv_ui()
	check(ui != null and not ui.is_open(), "Inventar vorhanden, geschlossen")
	await tap("inventory")
	check(ui.is_open() and ui.me == hale and ui.other == null, "Taste I öffnet das eigene Inventar")
	check(not get_tree().paused, "Spiel läuft weiter (Original: keine Pause beim Inventar)")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Maus sichtbar")
	check(m.controller.ui_blocking(), "Spieleingaben gesperrt")
	var lay_ok := ui.screen.has_layout() and ui.screen.stage.get_node_or_null("own_slot_hands") != null \
		and ui.screen.stage.get_node_or_null("own_slot_shoulder") != null and ui.screen.stage.get_node_or_null("own_slot_drop") != null
	check(lay_ok, "Original-Layout (gameinterface.4ds: Hände/Schulter/Kopf/Uniform/Rücken/Ablegen, Taschen, Rucksack)")
	var r_inv := ui.screen.rect("inventory")
	check(absf(r_inv.position.x) < 2.0 and absf(r_inv.position.y) < 2.0 and absf(r_inv.size.x - 416.0) < 3.0,
		"Laufzeitlage wie Original (SetPos 0.178/−0.333 -> linke obere Ecke, 416 × 528 px)", str(r_inv))
	check(ui.screen.stage.get_node_or_null("Name_own") != null and ui.screen.stage.get_node_or_null("Weight_own") != null
		and String((ui.screen.stage.get_node("Weight_own") as Label).text).ends_with("kg"), "Name und Gewicht „%d/%d kg“")
	check(ui.screen.stage.get_node_or_null("text_soldier stats") != null, "Ohne zweites Inventar: Soldatenwerte (skills)")
	var v := FieldInventory.view(hale)
	var thompson := OrigHud.weapon_item(hale.weapons[WeaponData.Slot.PRIMARY], hale.team)
	var colt := OrigHud.weapon_item(hale.weapons[WeaponData.Slot.SIDEARM], hale.team)
	check(int(v["hands"]) == thompson and thompson >= 0, "Hände = Waffe in der Hand", str(v["hands"]))
	check(SAS.count_of(v, SAS.ammo_of(thompson)) > 0 and SAS.count_of(v, colt) == 1, "Magazine und Pistole in den Taschen",
		str(v["items"]))
	await shot("own")

	# --- Linksklick schießt nicht, Maus dreht nicht ---
	var mag0 := hale.weapons[0].in_mag
	var yaw0 := hale.look_yaw
	Input.action_press("fire")
	var mm_ev := InputEventMouseMotion.new()
	mm_ev.relative = Vector2(200, 0)
	Input.parse_input_event(mm_ev)
	await frames(20)
	Input.action_release("fire")
	check(hale.weapons[0].in_mag == mag0 and not hale.trigger, "Linksklick bei offenem Inventar schießt nicht")
	check(absf(hale.look_yaw - yaw0) < 0.0001, "Kein Umsehen bei offenem Inventar")

	# --- Waffe in die Hand (Ziehen: Taschen -> Hände), wirkt sofort inkl. HUD ---
	var res := ui.move_item("own", "items", colt, "own", "hands")
	await frames(3)
	check(res == "" and hale.current_slot == WeaponData.Slot.SIDEARM and hale.tool == "", "Pistole in die Hände: Waffe gewechselt", res)
	v = FieldInventory.view(hale)
	check(int(v["hands"]) == colt and int(v["shoulder"]) == thompson, "Inventar: Pistole in den Händen, MP auf der Schulter")
	var hud = m.get("hud")
	if hud is OrigHud:
		await frames(3)
		check((hud as OrigHud).hands_item == colt and (hud as OrigHud).shoulder_item == thompson, "HUD zeigt Hand/Schulter sofort")
	# Klick-Bedienung: Klick wählt (rote Ziel-Markierungen), Klick aufs Ziel verschiebt
	ui._on_click(false, "own", "shoulder", thompson)
	check(not ui.sel.is_empty(), "Klick markiert Gegenstand (Ziel-Markierungen sel*)")
	ui._on_click(false, "own", "hands", colt)
	await frames(3)
	check(hale.current_slot == WeaponData.Slot.PRIMARY and int(FieldInventory.view(hale)["hands"]) == thompson,
		"Klick aufs Ziel: MP zurück in die Hände (Tausch)")
	# Gegenstand verschieben: Verbandskasten Taschen -> Hände (Hilfsmittel) -> Taschen
	if hale.medkits > 0:
		var mk := 54
		res = ui.move_item("own", "items", mk, "own", "hands")
		await frames(2)
		check(res == "" and hale.tool == "medkit", "Verbandskasten in die Hände = Hilfsmittel gewählt", res)
		res = ui.move_item("own", "hands", mk, "own", "items")
		await frames(2)
		check(res == "" and hale.tool == "" and hale.medkits > 0, "Verbandskasten zurück in die Taschen")
		hale.select_slot(WeaponData.Slot.PRIMARY)
	# Doppelklick (Taschen -> Hände)
	ui.quick("own", "items", colt)
	await frames(2)
	check(hale.current_slot == WeaponData.Slot.SIDEARM, "Doppelklick: Pistole in die Hände")
	hale.select_slot(WeaponData.Slot.PRIMARY)
	await frames(2)

	# --- Wegwerfen (Ablegen) und wieder aufnehmen ---
	var nade: int = OrigHud.weapon_item(hale.weapons[WeaponData.Slot.GRENADE], hale.team) if hale.weapons[WeaponData.Slot.GRENADE] else -1
	var n_nade: int = SAS.count_of(FieldInventory.view(hale), nade) if nade >= 0 else 0
	if nade >= 0 and n_nade > 0:
		res = ui.move_item("own", "items", nade, "own", "drop")
		await frames(3)
		var pile := FieldInventory.pile_near(hale.global_position)
		check(res == "" and pile != null and SAS.count_of(FieldInventory.view(pile), nade) == n_nade
			and (hale.weapons[WeaponData.Slot.GRENADE] == null), "Ablegen: Granaten liegen am Boden (Ablagestapel)", res)
		if pile:
			check(pile.can_interact(hale), "Ablagestapel aufnehmbar (T7025)")
			ui.open_for(hale, pile)
			res = ui.move_item("other", "items", nade, "own", "items")
			await frames(3)
			check(res == "" and hale.weapons[WeaponData.Slot.GRENADE] != null
				and hale.weapons[WeaponData.Slot.GRENADE].total_ammo() == n_nade, "Granaten wieder aufgenommen", res)
			await frames(2)
			check(not is_instance_valid(pile) or FieldInventory.is_empty(pile), "Leerer Ablagestapel verschwindet")
	# Taste Rücktaste wirft den Gegenstand in den Händen weg (geschlossenes Inventar)
	ui.close()
	await frames(2)
	check(not ui.is_open(), "Schließen")

	# --- Schließen mit I bzw. Esc ---
	await tap("inventory")
	check(ui.is_open(), "erneut geöffnet")
	await tap("inventory")
	check(not ui.is_open(), "Taste I schließt")
	await tap("inventory")
	await tap("pause")
	var pm = m.get_node_or_null("PauseMenu")
	check(not ui.is_open() and not (pm and pm.is_open()), "Esc schließt das Inventar (kein Pausenmenü)")
	if pm and pm.is_open():
		pm.close()

	# --- Leiche durchsuchen: zwei Inventare, Waffe und Munition nehmen ---
	var dead: Soldier = null
	for e in m.enemies:
		if e.weapons.size() > 0 and e.weapons[0] != null:
			dead = e
			break
	var eb := dead.get_node("EnemyBrain") as EnemyBrain
	eb.enabled = false
	dead.set_physics_process(true)
	place(dead, 6, 22, 0.0)
	place(hale, 5.2, 21.4, 0.0)
	dead.die(hale)
	await seconds(1.0)
	var dw := OrigHud.weapon_item(dead.weapons[0], dead.team)
	var dam := SAS.ammo_of(dw)
	hale.look_yaw = atan2(-(dead.global_position.x - hale.global_position.x), -(dead.global_position.z - hale.global_position.z))
	await frames(10)
	check(m.controller.interact_target is Pickups.Loot, "Leiche als Interaktionsziel (Durchsuchen)")
	await tap("interact")
	check(ui.is_open() and ui.other == dead, "Benutzen an der Leiche öffnet die Original-Ansicht mit zwei Inventaren")
	check(ui.screen.stage.get_node_or_null("other_slot_hands") != null and ui.screen.stage.get_node_or_null("text_soldier stats") == null,
		"Zweites Inventar (items01) statt Soldatenwerte")
	var dv := FieldInventory.view(dead)
	check(int(dv["hands"]) == dw and dw >= 0, "Leiche: Waffe in den Händen", str(dv))
	await shot("search")
	# Munition nehmen (ganzer Stapel)
	var mags_dead := SAS.count_of(dv, dam)
	res = ui.move_item("other", "items", dam, "own", "items")
	await frames(3)
	check(mags_dead > 0 and res == "" and SAS.count_of(FieldInventory.view(hale), dam) >= mags_dead
		and SAS.count_of(FieldInventory.view(dead), dam) == 0, "Munition der Leiche übernommen", "%d Magazine %s" % [mags_dead, res])
	# Waffe direkt in die Hände
	res = ui.move_item("other", "hands", dw, "own", "hands")
	await frames(3)
	check(res == "" and OrigHud.weapon_item(hale.current_weapon(), hale.team) == dw, "Waffe der Leiche in die Hände (sofort in der Hand)", res)
	check(hale.current_weapon() != null and hale.current_weapon().reserve > 0, "Übernommene Magazine sind Reserve der neuen Waffe",
		str(hale.current_weapon().reserve if hale.current_weapon() else -1))
	check(SAS.count_of(FieldInventory.view(hale), thompson) == 1, "Eigene MP bleibt im Inventar")
	check(hale.get_meta("orig_items", []).has(dw), "Originalgegenstände aktualisiert (_IsInInventory)")
	# Uniform einer Leiche: gesperrt
	dv = FieldInventory.view(dead)
	var du := int(dv["uniform"])
	res = ui.move_item("other", "uniform", du, "own", "uniform") if du >= 0 else "keine"
	check(du >= 0 and res != "" and not hale.disguised, "Uniform einer Leiche nicht nehmbar (nur von Gefangenen)", res)
	ui.close()
	# erneutes Durchsuchen
	await frames(10)
	var spot := dead.get_node_or_null("SearchSpot")
	check(spot != null and spot.can_interact(hale), "Leiche bleibt durchsuchbar, solange sie etwas trägt")
	# Waffe zurück auf die eigene MP
	hale.select_slot(WeaponData.Slot.PRIMARY)

	# --- Gefangener: Durchsuchen und Uniform ---
	var pr: Soldier = null
	for e in m.enemies:
		if e != dead and e.alive:
			pr = e
			break
	var pb := pr.get_node("EnemyBrain") as EnemyBrain
	pr.set_physics_process(true)
	place(pr, 10, 24, 0.0)
	place(hale, 10, 25.2, 0.0)
	pb.enabled = true
	pb.surrender(hale)
	await frames(3)
	pb.capture_action.interact(hale)
	await frames(3)
	check(pb.captured, "Gegner gefangen genommen")
	check(m.controller._open_search(pb.capture_action) and ui.other == pr, "Durchsuchen des Gefangenen öffnet zwei Inventare")
	check((pb.capture_action as EnemyBrain.CaptureAction).searched, "Schritt „Suchen“ erledigt (danach Uniform benutzen)")
	var pv := FieldInventory.view(pr)
	var pu := int(pv["uniform"])
	res = ui.move_item("other", "uniform", pu, "own", "uniform")
	await frames(3)
	check(pu >= 0 and res == "" and hale.disguised and pb.uniform_taken, "Uniform vom Gefangenen angezogen (Tarnung)", res)
	check(int(FieldInventory.view(hale)["uniform"]) == pu, "Feinduniform auf dem eigenen Uniformplatz")
	await shot("prisoner")
	ui.close()
	hale.disguised = false
	await _order(hale)


## Ingame-Inventar in Aufnahmereihenfolge (Original 0x7D7390 anhängen/stapeln, 0x7D7470 aufrücken, Anzeige 0x4A2010):
## drei Gegenstände in der Mission aufheben (echte Weltgegenstände, Benutzen), Reihenfolge im I-Menü prüfen
func _order(hale: Soldier) -> void:
	var ui := inv_ui()
	var ids0 := _ids(FieldInventory.view(hale))
	# drei Ausrüstungsgegenstände ohne Laufzeitabbild, absteigende Nummern (keine Sortierung nach Nummer erlaubt)
	var cands: Array = []
	for id in range(400, 100, -1):
		if cands.size() >= 3:
			break
		if SAS.item(id).size() > 0 and not SAS.item_kind(id) in ["weapon", "ammo"] and not FieldInventory.TOOL_IDS.has(id) \
				and SAS.slot_for(id) == "" and not ids0.has(id) and not ItemOrderT.is_ammo(id):
			cands.append(id)
	check(cands.size() == 3, "Reihenfolge: drei Testgegenstände gefunden", str(cands))
	if cands.size() < 3:
		return
	for id in cands:
		_pick(hale, int(id))
		await frames(2)
	var ids := _ids(FieldInventory.view(hale))
	check(ids == ids0 + cands, "Aufgenommenes hinten angehängt, in Aufnahmereihenfolge (nicht nach Nummer)",
		"vorher %s, nachher %s" % [ids0, ids])
	_pick(hale, int(cands[0]))
	await frames(2)
	var v := FieldInventory.view(hale)
	check(_ids(v) == ids0 + cands and SAS.count_of(v, int(cands[0])) == 2, "Gleiche Sorte zur vorhandenen Gruppe (Anzahl 2, Stelle bleibt)",
		str(v["items"]))
	# Anzeige im I-Menü (Taschen, dann Rucksack) in derselben Reihenfolge
	await tap("inventory")
	check(ui.is_open(), "I-Menü geöffnet")
	var cols := IngameInventory.split_columns(FieldInventory.view(hale))
	var shown: Array = []
	for c in cols:
		for e in c:
			shown.append(int(e[0]))
	var pos := cands.map(func(id): return shown.find(int(id)))
	check(pos[0] >= 0 and pos[0] < pos[1] and pos[1] < pos[2] and pos[2] == shown.size() - 1,
		"I-Menü zeigt die Aufnahmereihenfolge (letzter Gegenstand am Ende)", "Anzeige %s" % [shown])
	await shot("order")
	# Entfernen: ganze Gruppe ablegen -> Rest rückt auf; erneut aufgenommen -> ans Ende
	var res := ui.move_item("own", "items", int(cands[1]), "own", "drop")
	await frames(3)
	ids = _ids(FieldInventory.view(hale))
	check(res == "" and ids == ids0 + [cands[0], cands[2]], "Abgelegte Gruppe fehlt, Rest rückt auf", "%s %s" % [res, ids])
	# erneut in der Welt aufgehoben (Benutzen; Ablagestapel-Weg prüft oben schon die Granaten, hier wäre der Raum
	# durch die zusätzlich aufgehobenen Testgegenstände ggf. erschöpft)
	var pile := FieldInventory.pile_near(hale.global_position)
	if pile:
		ui.open_for(hale, pile)
		print("INFO Ablagestapel -> Taschen: '%s', Raum %.1f/%.1f" % [ui.move_item("other", "items", int(cands[1]), "own", "items"),
			SAS.inv_space(FieldInventory.view(hale)), FieldInventory.capacity(hale, FieldInventory.view(hale))])
		await frames(3)
		print("INFO Reihenfolge nach Stapel: %s" % [_ids(FieldInventory.view(hale))])
		if SAS.count_of(FieldInventory.view(hale), int(cands[1])) > 0:
			FieldInventory.drop(hale, "items", int(cands[1]))      # für den Weltweg unten wieder ablegen
	ui.close()
	_pick(hale, int(cands[1]))
	await frames(2)
	ids = _ids(FieldInventory.view(hale))
	check(ids == ids0 + [cands[0], cands[2], cands[1]], "Wieder aufgenommen: neue Gruppe am Ende", str(ids))
	await tap("inventory")
	await shot("order_after")
	ui.close()
	# Mehrspieler-Abgleich trägt die Reihenfolge (export_state/import_state)
	var st := FieldInventory.export_state(hale)
	check((st.get("order", []) as Array) == ids, "Reihenfolge im Netzabgleich enthalten")
	await _mission_end(hale, cands)


## Missionsende (Original 0x698F80 → 0x5A9040 → 0x5A8B50): SAS-Datensatz = aktuelles Inventar des Soldaten.
## Aufgehobenes bleibt, Abgelegtes/Verbrauchtes fehlt, Reihenfolge der Gruppen bleibt.
func _mission_end(hale: Soldier, cands: Array) -> void:
	const IDX := 9999                       # Prüf-Datensatz (kein echter Kadersoldat), danach entfernt
	var invs: Dictionary = Game.campaign.get("inv", {})
	Game.campaign["inv"] = invs
	invs[str(IDX)] = SAS.new_inventory()
	SAS.add_item(invs[str(IDX)], 54, 3)     # alter Stand: soll vollständig ersetzt werden
	var dropped := int(cands[2])
	FieldInventory.drop(hale, "items", dropped)
	await frames(2)
	var med0 := hale.medkits
	if med0 > 0:
		hale.medkits = med0 - 1             # ein Verband verbraucht
	var v := FieldInventory.view(hale)
	Game._write_back_inventory(hale, IDX)
	var inv: Dictionary = Game.sas_inventory(IDX)
	check(SAS.count_of(inv, int(cands[0])) == 2 and SAS.count_of(inv, int(cands[1])) == 1,
		"Missionsende: im Einsatz Aufgehobenes ins SAS-Inventar übernommen (0x5A8B50)", str(inv["items"]))
	check(SAS.count_of(inv, dropped) == 0, "Missionsende: Abgelegtes nicht übernommen", str(inv["items"]))
	var med := 0
	for m in FieldInventory.MEDKITS:
		med += SAS.count_of(inv, m)
	check(med == hale.medkits, "Missionsende: Verbrauchtes fehlt (Verbände %d → %d)" % [med0, med], str(inv["items"]))
	check(_ids(inv) == _ids(v) and int(inv["hands"]) == int(v["hands"]) and int(inv["shoulder"]) == int(v["shoulder"])
		and int(inv["uniform"]) == int(v["uniform"]), "Missionsende: Hände/Schulter/Uniform/Taschen wie im Einsatz, Gruppenreihenfolge",
		"%s / %s" % [_ids(inv), _ids(v)])
	invs.erase(str(IDX))


func _pick(s: Soldier, id: int) -> void:
	var wi := OrigInteractive.OrigWorldItem.new()
	wi.item = id
	mission().add_child(wi)
	wi.interact(s)
	wi.queue_free()


func _ids(inv: Dictionary) -> Array:
	return (inv["items"] as Array).map(func(e): return int(e[0]))


# --- Mehrspieler (zweiprozessig) -----------------------------------------------------------------------------

func _mp() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	Net.local_name = "Host"
	var port := Net.PORT + MP_PORT_OFS
	var ok := Net.host({"name": "Inventar", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.DEATHMATCH, "max_players": 8,
		"time_limit_min": 0, "score_limit": 0, "respawn_s": 99, "password": "", "port": port, "friendly_fire": true,
		"bots_per_team": 1, "warmup_s": 0})
	check(ok and Net.is_online, "MP: Server gestartet", Net.last_error)
	var m: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.3).timeout
		m = Game.current_mission()
		if m and Net._soldiers.has(1) and Net._soldiers.keys().filter(func(k): return int(k) < 0).size() >= 2:
			break
	check(m != null and Net._soldiers.has(1), "MP: Karte und Soldaten")
	if m == null:
		return
	_park_bots()
	Events.soldier_died.connect(func(s, _a): print("MP-TOD ", s.persistent_id))
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/inv_client.log")
	var args := ["--headless", "--log-file", clog]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--", "--autoplay=test_inventory_client", "--port=%d" % port]
	var pid := OS.create_process(exe, args)
	check(pid > 0, "MP: Client-Prozess gestartet")
	var cid := 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000 and cid == 0:
		await get_tree().create_timer(0.25).timeout
		_park_bots()
		for id in Net._soldiers:
			if int(id) > 1 and is_instance_valid(Net._soldiers[id]) and (Net._soldiers[id] as Soldier).alive:
				cid = int(id)
	check(cid != 0, "MP: Client beigetreten")
	if cid == 0:
		Net.leave(false)
		return
	var puppet: Soldier = Net._soldiers[cid]
	await get_tree().create_timer(2.0).timeout
	# Bot neben dem Client erschießen (Server-Treffer) -> Leiche auf beiden Rechnern
	var bot: Soldier = null
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]) and (Net._soldiers[id] as Soldier).alive:
			bot = Net._soldiers[id]
			break
	var bw: int = OrigHud.weapon_item(bot.current_weapon(), bot.team) if bot and bot.current_weapon() else -1
	bot.global_position = puppet.global_position + Vector3(1.2, 0.2, 0.0)
	bot.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	bot.set_meta("protect_until", 0)
	bot.apply_hit(1000.0, &"torso", Net._soldiers[1], Vector3.FORWARD)
	await frames(5)
	print("MP-DIAG: Client-Figur %s (net_target %s), Bot-Leiche %s" % [puppet.global_position, puppet.net_target, bot.global_position])
	get_tree().create_timer(3.0).timeout.connect(func(): print("MP-DIAG +3s: Client-Figur %s (net_target %s), Bot-Leiche %s" % [puppet.global_position, puppet.net_target, bot.global_position]))
	check(not bot.alive and bw >= 0, "MP: Bot-Leiche neben dem Client", str(bw))
	# Client durchsucht und nimmt die Waffe in die Hände (Anfrage an den Server)
	var taken := func() -> bool: return _has_weapon(Net._soldiers.get(cid), bw) and int(FieldInventory.view(bot)["hands"]) != bw
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not taken.call():
		await get_tree().create_timer(0.25).timeout
	check(taken.call(), "MP: Server hat die Waffe aus der Leiche dem Client gegeben (Server-Stand)")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt: String = FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "MP: Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "MP-Client: " + line.substr(6))
	# Host: echte Taste F an einer zweiten Bot-Leiche
	var host: Soldier = Net._soldiers.get(1)
	var bot2: Soldier = null
	for id in Net._soldiers:
		var sb: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(sb) and sb.alive:
			bot2 = sb
	if bot2 and is_instance_valid(host) and host.alive:
		bot2.global_position = host.global_position + host.forward() * 1.2 + Vector3.UP * 0.2
		await frames(10)
		bot2.set_meta("protect_until", 0)
		bot2.apply_hit(1000.0, &"torso", host, host.forward())
		await seconds(1.5)
		face(host, body_center(bot2))
		await frames(10)
		var it = m.controller.interact_target
		check(it is FieldInventory.SearchSpot, "MP-Host: Leiche ist Benutzen-Ziel", str(it.get("prompt")) if it else "kein Ziel")
		await press_key(KEY_F)
		var ui := m.controller.inventory as IngameInventory
		check(ui.is_open() and ui.other == bot2, "MP-Host: Taste F öffnet das Inventar mit beiden Inventaren")
		await shot("real_mp")
		ui.close()
	Net.leave(false)


func _has_weapon(s: Soldier, item: int) -> bool:
	if not is_instance_valid(s):
		return false
	for w in s.weapons:
		if w != null and OrigHud.weapon_item(w, s.team) == item:
			return true
	return false


func _park_bots() -> void:
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(s):
			var b := s.get_node_or_null("EnemyBrain")
			if b:
				b.set("enabled", false)
			s.trigger = false
			s.move_input = Vector3.ZERO
