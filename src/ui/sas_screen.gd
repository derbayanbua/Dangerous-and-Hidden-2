class_name SasScreen
extends Control
## Teamauswahl und Ausrüstung vor einem Kampagneneinsatz (Original: „AUSWAHL DER TEAM-MITGLIEDER“ /
## „TEAM WIEDER AUFFÜLLEN“ und „INVENTAR-AUSWAHL“, Texte 2651–2740). Ablauf wie im Original:
## Teamauswahl nur, wenn die Mission sie vorsieht (Gamedata00.gdt), danach Ausrüstung, dann Einsatz.
## Vereinfachung (Vorgabe Auftraggeber): Taschen + Rucksack = ein gemeinsames Inventar.

signal back_requested
signal start_requested

var mission_id := ""
var mode := "keep"            ## select / refill / keep (SAS.team_mode)
var page := ""                ## "team" oder "equip"
var focus_idx := -1           ## angezeigter Soldat (Kaderindex)
var _locked: Array = []       ## refill: überlebende Mitglieder bleiben im Team
var _root: VBoxContainer
var _status: Label


func open(id: String) -> void:
	mission_id = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	Game.prepare_sas(id)
	mode = Game.sas_team_mode(id)
	_locked = Game.sas_team() if mode == "refill" else []
	if mode in ["select", "refill"]:
		show_team()
	else:
		show_equipment()


func _t(id: int, fb: String) -> String:
	return SAS.text(id, fb)


func _page(title: String) -> VBoxContainer:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.04, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	UIKit.title(title, 26, _root)
	return _root


func _btn(txt: String, cb: Callable, parent: Node, node_name := "", enabled := true) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(150, 38)
	b.disabled = not enabled
	b.pressed.connect(cb)
	if node_name != "":
		b.name = node_name
	parent.add_child(b)
	return b


func _small(txt: String, parent: Node, color := UIKit.TEXT, size := 15) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


# --- Teamauswahl --------------------------------------------------------------------

func show_team() -> void:
	page = "team"
	var v := _page(_t(2652 if mode == "refill" else 2651, "AUSWAHL DER TEAM-MITGLIEDER"))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	var st := Game.sas_states()
	var team := Game.sas_team()
	# links: verfügbare Soldaten
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	cols.add_child(left)
	_small(_t(2659, "Soldaten-Auswahl:"), left, UIKit.ACCENT, 17)
	var avail := ItemList.new()
	avail.name = "Available"
	avail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(avail)
	for idx in SAS.store_indices():
		var s: Dictionary = st.get(str(idx), {})
		if s.is_empty() or s["dead"] or team.has(idx):
			continue
		var i := avail.add_item("%s  (%s)" % [SAS.display_name(idx), SAS.rank_name(int(s["rank"]), true)])
		avail.set_item_metadata(i, idx)
	avail.item_selected.connect(func(i): _focus(int(avail.get_item_metadata(i))))
	avail.item_activated.connect(func(i): team_add(int(avail.get_item_metadata(i))))
	# Mitte: Info zum ausgewählten Soldaten
	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 420
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.name = "Info"
	cols.add_child(mid)
	# rechts: Team
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	cols.add_child(right)
	_small(_t(2706, "Team:"), right, UIKit.ACCENT, 17)
	var tl := ItemList.new()
	tl.name = "Team"
	tl.custom_minimum_size.y = 170
	right.add_child(tl)
	for idx in team:
		var i := tl.add_item(SAS.short_name(idx, int(st[str(idx)]["rank"])) + ("" if not _locked.has(idx) else "  ✓"))
		tl.set_item_metadata(i, idx)
	tl.item_selected.connect(func(i): _focus(int(tl.get_item_metadata(i))))
	tl.item_activated.connect(func(i): team_remove(int(tl.get_item_metadata(i))))
	var tb := VBoxContainer.new()
	right.add_child(tb)
	_btn(_t(2657, "HINZUFÜGEN"), func(): team_add(focus_idx), tb, "Add", focus_idx >= 0 and not team.has(focus_idx) and team.size() < Game.SQUAD_SIZE)
	_btn(_t(2658, "ENTFERNEN"), func(): team_remove(focus_idx), tb, "Remove", team.has(focus_idx) and not _locked.has(focus_idx))
	_btn(_t(2654, "AUTOMATISCHE AUSWAHL"), auto_select, tb, "Auto")
	if focus_idx < 0:
		focus_idx = team[0] if not team.is_empty() else -1
	_fill_info(mid, focus_idx)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_btn(_t(2655, "ZURÜCK"), func(): back_requested.emit(), row, "Back")
	_btn(_t(2653, "FORTSETZEN"), show_equipment, row, "Continue", not team.is_empty())


func _focus(idx: int) -> void:
	focus_idx = idx
	if page == "team":
		show_team()
	else:
		show_equipment()


func _fill_info(parent: VBoxContainer, idx: int) -> void:
	_small(_t(2668, "Soldaten-Info:"), parent, UIKit.ACCENT, 17)
	if idx < 0:
		return
	var st: Dictionary = Game.sas_states().get(str(idx), {})
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	parent.add_child(top)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(96, 120)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var p := SAS.portrait_path(idx)
	if FileAccess.file_exists(p):
		img.texture = ImageTexture.create_from_image(Image.load_from_file(p))
	top.add_child(img)
	var nv := VBoxContainer.new()
	top.add_child(nv)
	_small(SAS.display_name(idx), nv, UIKit.TEXT, 19)
	_small(SAS.rank_name(int(st.get("rank", 0))), nv, UIKit.ACCENT)
	_small("Einsätze: %d   Erfahrung: %d" % [int(st.get("missions", 0)), int(st.get("experience", 0))], nv)
	_small(_t(2666, "SOLDATEN-STATISTIK"), parent, UIKit.ACCENT, 15)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	parent.add_child(g)
	var stats: Dictionary = st.get("stats", {})
	for e in SAS.STAT_PANEL:
		_small(_t(e[1], e[0]), g)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(200, 14)
		bar.show_percentage = false
		bar.max_value = 1000.0 if e[0] == "health" else 100.0
		bar.value = float(stats.get(e[0], 0))
		g.add_child(bar)
		_small(("%d" if e[0] == "health" else "%.1f") % float(stats.get(e[0], 0)) + (" kg" if e[0] == "strength" else ""), g)
	var bio := _small(SAS.bio(idx), parent, Color(0.8, 0.78, 0.7), 14)
	bio.custom_minimum_size.x = 400


func team_add(idx: int) -> void:
	var team := Game.sas_team()
	if idx < 0 or team.has(idx) or team.size() >= Game.SQUAD_SIZE or Game.sas_states()[str(idx)]["dead"]:
		return
	team.append(idx)
	Game.set_sas_team(team)
	var inv := Game.sas_inventory(idx)
	if int(inv.get("hands", -1)) < 0 and inv.get("items", []).is_empty():
		_apply_recommended(idx)
	focus_idx = idx
	show_team()


func team_remove(idx: int) -> void:
	var team := Game.sas_team()
	if not team.has(idx) or _locked.has(idx):
		return
	team.erase(idx)
	Game.set_sas_team(team)
	show_team()


func auto_select() -> void:
	var keep: Array = _locked.duplicate()
	Game.set_sas_team(SAS.auto_select(Game.sas_states(), Game.SQUAD_SIZE, keep))
	for idx in Game.sas_team():
		var inv := Game.sas_inventory(idx)
		if int(inv.get("hands", -1)) < 0 and inv.get("items", []).is_empty():
			_apply_recommended(idx)
	show_team()


# --- Ausrüstung ---------------------------------------------------------------------

func _storage() -> Dictionary:
	if not Game.campaign.has("storage"):
		Game.campaign["storage"] = []
	return {"items": Game.campaign["storage"]}


func _strength(idx: int) -> float:
	return float(Game.sas_states()[str(idx)]["stats"].get("strength", 20.0))


func show_equipment() -> void:
	page = "equip"
	var team := Game.sas_team()
	if not team.has(focus_idx):
		focus_idx = team[0] if not team.is_empty() else -1
	Game.ensure_essentials(mission_id)
	var v := _page(_t(2701, "INVENTAR-AUSWAHL"))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	var st := Game.sas_states()
	for idx in team:
		var b := _btn(SAS.short_name(idx, int(st[str(idx)]["rank"])), _focus.bind(idx), tabs, "Soldier%d" % idx)
		b.toggle_mode = true
		b.button_pressed = idx == focus_idx
		if SAS.overloaded(Game.sas_inventory(idx), _strength(idx)):
			b.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	if focus_idx < 0:
		return
	var inv := Game.sas_inventory(focus_idx)
	# links: Ausrüstungsplätze + gemeinsames Inventar
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	cols.add_child(left)
	_small(_t(2718, "AUSRÜSTUNG FÜR AUSGEWÄHLTEN SOLDAT") + " — " + SAS.display_name(focus_idx), left, UIKit.ACCENT, 17)
	var sg := GridContainer.new()
	sg.columns = 2
	left.add_child(sg)
	for slot in ["hands", "shoulder", "head", "uniform", "back"]:
		_small(_t(SAS.SLOT_TEXT[slot], slot) + ":", sg)
		var id := int(inv.get(slot, -1))
		var label := SAS.item_name(id) if id >= 0 else _t(2727, "KEINE").strip_edges()
		if slot == "back" and id >= 0 and SAS.is_backpack(id):
			label += "  (+%d Raum)" % int(SAS.backpack_space(id))
		_btn(label, unequip.bind(focus_idx, slot), sg, "Slot_" + slot, id >= 0).custom_minimum_size.x = 330
	var w := SAS.inv_weight(inv)
	var sp := SAS.inv_space(inv)
	var cap := SAS.inv_capacity(inv)
	var over := SAS.overloaded(inv, _strength(focus_idx))
	_small("%s: %.1f / %.1f kg     %s + %s: %d / %d" % [_t(2730, "Gewicht"), w, _strength(focus_idx),
		_t(2716, "Taschen"), _t(2717, "Rucksack"), int(sp), int(cap)], left,
		Color(0.95, 0.4, 0.3) if over else UIKit.TEXT, 16).name = "Load"
	_small(_t(2728, "Inventar:"), left, UIKit.ACCENT, 16)
	var il := ItemList.new()
	il.name = "Inventory"
	il.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(il)
	for e in inv.get("items", []):
		var i := il.add_item("%d × %s" % [int(e[1]), SAS.item_name(int(e[0]))])
		il.set_item_metadata(i, int(e[0]))
	il.item_activated.connect(func(i): take_back(focus_idx, int(il.get_item_metadata(i))))
	# rechts: Lager
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_small(_t(2707, "Lager:"), right, UIKit.ACCENT, 17)
	var sl := ItemList.new()
	sl.name = "Storage"
	sl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sl)
	var store: Array = _storage()["items"]
	store.sort_custom(func(a, b): return [SAS.item_kind(int(a[0])), SAS.item_name(int(a[0]))] < [SAS.item_kind(int(b[0])), SAS.item_name(int(b[0]))])
	for e in store:
		var i := sl.add_item("%d × %s   (%.2f kg)" % [int(e[1]), SAS.item_name(int(e[0])), SAS.weight(int(e[0]))])
		sl.set_item_metadata(i, int(e[0]))
	sl.item_activated.connect(func(i): give(focus_idx, int(sl.get_item_metadata(i))))
	_small("Doppelklick: Gegenstand übernehmen bzw. ins Lager zurücklegen", right, Color(0.7, 0.68, 0.6), 13)
	# benötigte Gegenstände
	var missing := missing_essentials()
	var ess := SAS.essentials(SAS.mission_info(Game.orig_folder(mission_id)))
	if not ess.is_empty():
		_small(_t(2729, "Benötigte Gegenstände für die Mission:") + " " + ", ".join(ess.map(func(e): return SAS.item_name(e[0]))),
			v, Color(0.95, 0.4, 0.3) if not missing.is_empty() else UIKit.ACCENT, 15)
	_status = _small("", v, Color(0.95, 0.4, 0.3), 15)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_btn(_t(2705, "ZURÜCK"), func(): show_team() if mode in ["select", "refill"] else back_requested.emit(), row, "Back")
	_btn(_t(2704, "EMPFOHLENE AUSWAHL"), func():
		_apply_recommended(focus_idx)
		show_equipment(), row, "Recommended")
	_btn(_t(2703, "FORTSETZEN"), try_start, row, "Continue")


## Gegenstand aus dem Lager an den Soldaten: passender Platz (Hände/Kopf/Uniform/Rücken; belegter Platz
## wird getauscht) oder ins gemeinsame Inventar (Gewicht ≤ Kraft, Raum ≤ Taschen + Rucksack).
func give(idx: int, id: int, count := -1) -> bool:
	var store := _storage()
	var have := 0
	for e in store["items"]:
		if int(e[0]) == id:
			have = int(e[1])
	if have <= 0:
		return false
	var inv := Game.sas_inventory(idx)
	var slot := SAS.slot_for(id)
	if slot == "hands" and int(inv.get("hands", -1)) >= 0 and int(inv.get("shoulder", -1)) < 0:
		slot = "shoulder"
	if slot != "":
		var old := int(inv.get(slot, -1))
		var w := SAS.inv_weight(inv) + SAS.weight(id) - (SAS.weight(old) if old >= 0 else 0.0)
		if w > _strength(idx) + 0.001:
			_say("Zu schwer für %s." % SAS.display_name(idx))
			return false
		SAS.remove_item(store, id, 1)
		if old >= 0:
			SAS.add_item(store, old, 1)
		inv[slot] = id
	else:
		# Munition/Kleinteile: sinnvolle Menge auf einmal (ein Magazin = ein Gegenstand)
		var n := 1 if count < 0 else mini(count, have)
		if not SAS.can_add(inv, _strength(idx), id, n):
			_say("Kein Platz bzw. zu schwer (Taschen + Rucksack).")
			return false
		SAS.remove_item(store, id, n)
		SAS.add_item(inv, id, n)
	_refresh()
	return true


func take_back(idx: int, id: int, count := 1) -> void:
	var inv := Game.sas_inventory(idx)
	var n := SAS.remove_item(inv, id, count)
	if n > 0:
		SAS.add_item(_storage(), id, n)
	_refresh()


func unequip(idx: int, slot: String) -> void:
	var inv := Game.sas_inventory(idx)
	var id := int(inv.get(slot, -1))
	if id < 0:
		return
	inv[slot] = -1
	SAS.add_item(_storage(), id, 1)
	# ohne Rucksack passt der Inhalt evtl. nicht mehr -> Überzähliges zurück ins Lager
	while SAS.inv_space(inv) > SAS.inv_capacity(inv) + 0.001 and not inv["items"].is_empty():
		var e: Array = inv["items"].back()
		take_back(idx, int(e[0]), int(e[1]))
	_refresh()


## Original „EMPFOHLENE AUSWAHL“: Preset aus miss_itm.def für den Platz im Team (bisherige Ausrüstung ins Lager)
func _apply_recommended(idx: int) -> void:
	var rec := SAS.recommended_presets(SAS.mission_info(Game.orig_folder(mission_id)))
	if rec.is_empty():
		return
	var pos := maxi(Game.sas_team().find(idx), 0)
	var inv := Game.sas_inventory(idx)
	var store := _storage()
	for slot in SAS.SLOTS:
		if int(inv.get(slot, -1)) >= 0:
			SAS.add_item(store, int(inv[slot]), 1)
	for e in inv.get("items", []):
		SAS.add_item(store, int(e[0]), int(e[1]))
	var fresh := SAS.preset_inventory(rec[pos % rec.size()])
	Game.campaign["inv"][str(idx)] = fresh
	# Preset-Gegenstände stammen aus dem Lager, soweit vorhanden
	for slot in SAS.SLOTS:
		if int(fresh.get(slot, -1)) >= 0:
			SAS.remove_item(store, int(fresh[slot]), 1)
	for e in fresh["items"]:
		SAS.remove_item(store, int(e[0]), int(e[1]))
	Game.ensure_essentials(mission_id)
	Game.fit_inventory(idx, mission_id)


func missing_essentials() -> Array:
	var out: Array = []
	for e in SAS.essentials(SAS.mission_info(Game.orig_folder(mission_id))):
		var have := 0
		for idx in Game.sas_team():
			have += SAS.count_of(Game.sas_inventory(idx), e[0])
		if have < e[1]:
			out.append(e[0])
	return out


## Original: Überladung verhindert das Fortsetzen; benötigte Gegenstände müssen dabei sein.
func can_start() -> String:
	if Game.sas_team().is_empty():
		return "Kein Team."
	for idx in Game.sas_team():
		if SAS.overloaded(Game.sas_inventory(idx), _strength(idx)):
			return "%s ist überladen." % SAS.display_name(idx)
	var miss := missing_essentials()
	if not miss.is_empty():
		return "Es fehlt: " + ", ".join(miss.map(func(i): return SAS.item_name(i)))
	return ""


func try_start() -> bool:
	var why := can_start()
	if why != "":
		_say(why)
		return false
	Game.save_campaign()
	start_requested.emit()
	return true


func _say(t: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = t


func _refresh() -> void:
	if page == "equip":
		show_equipment.call_deferred()
