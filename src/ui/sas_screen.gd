class_name SasScreen
extends OrigScreen
## Bildschirme vor einem Kampagneneinsatz, 1:1 nach den Original-Menümodellen (docs/re_notes_menus_equipment.md):
##   „AUSWAHL DER TEAM-MITGLIEDER“ / „TEAM WIEDER AUFFÜLLEN“ = MODELS\team members selection.4ds (Texte 2651–2686)
##   „INVENTAR-AUSWAHL“ / „INVENTAR WECHSELN“            = MODELS\items selection.4ds (Texte 2701–2740)
##   „AKTIVEN SOLDAT AUSWÄHLEN“ (Einzelkämpfer-Einsätze)   = MODELS\selection screen.4ds
## Ablauf wie im Original: Teamauswahl nur, wenn die Mission sie vorsieht (Gamedata00.gdt), danach Ausrüstung,
## dann Einsatz. Bedienung: Klick wählt, Doppelklick übernimmt/legt zurück (das Original zieht per Maus;
## Ziel-Markierungen MM_RED wie im Original).
## Vereinfachung (Vorgabe Auftraggeber): Taschen + Rucksack = ein gemeinsames Inventar. Die Darstellung zeigt
## die Original-Spalten „Taschen“ (12 Raumeinheiten) und „Rucksack“; die Aufteilung ist nur Anzeige.

signal back_requested
signal start_requested

const UserPresets := preload("res://src/campaign/user_presets.gd")
const ItemOrder := preload("res://src/ui/item_order.gd")

const POOL_PHOTOS := ["photo03", "photo04", "photo05", "photo06", "photo07"]
const POOL_TABLES := ["table11", "table13", "table14", "table15", "table12"]
const TEAM_TABLES := ["table18", "table19", "table20", "table21"]
const TEAM_FRAMES := ["member04", "member01", "member02", "member03"]
const TEAM_PHOTOS := ["member00", "photo00", "photo01", "photo02"]
const EQ_PHOTOS := ["photo03", "photo04", "photo05", "photo06"]
const MEDAL_FRAMES := ["DSO", "DCM", "MILIT_MEDAL", "GSM_AFRICA", "GSM", "WAR_MEDAL", "DEFENCE_MEDAL", "MILITARY_CROSS",
	"VICTORIA_CROSS", "GERM_FRANCE_STAR", "AFRICA_STAR", "BURMA_STAR"]
## Ausrüstungsplätze im Modell: Frame, Beschriftung, Ziel-Markierung
const SLOT_FRAMES := {"hands": ["hands", "text_hands", "selhands"], "shoulder": ["shoulder", "text_shoulder", "selshoulder"],
	"head": ["head", "text_head", "selhead"], "uniform": ["uniform", "text_uniform", "seluniform"],
	"back": ["back", "text_back", "selbck"]}
const POCKETS := ["item00", "item01", "item02", "item03"]
const PACK := ["item04", "item05", "item06", "item07"]
const STORE_TOP := 192.0
const STORE_BOTTOM := 568.0

var mission_id := ""
var mode := "keep"            ## select / refill / keep (SAS.team_mode)
var page := ""                ## "team" oder "equip"
var focus_idx := -1           ## angezeigter Soldat (Kaderindex)
var info_page := false        ## Teamauswahl: Biografie statt Werte (Knopf SOLDATEN-INFO)
var status_page := false      ## Inventar: Soldaten-Status statt Ausrüstung (Knopf 2736/2735)
var pool_ofs := 0
var category := 0             ## Lager-Klassifizierung (SAS.CATEGORY_TEXT)
var store_ofs := 0
var pocket_ofs := 0
var pack_ofs := 0
var sel_store := -1           ## im Lager markierter Gegenstand
var sel_inv := ""             ## markierter Platz am Soldaten („hands“ … bzw. „item:<id>“)
var dropdown := ""            ## offene Aufklappliste: "type" / "filter"
var _locked: Array = []       ## refill: überlebende Mitglieder bleiben im Team
var _type_of := {}            ## Soldat -> gewählte Soldatentyp-Vorlage (Anzeige der Aufklappliste)
var _status_text := ""


func open(id: String) -> void:
	mission_id = id
	setup_stage()
	Game.prepare_sas(id)
	mode = Game.sas_team_mode(id)
	_locked = Game.sas_team() if mode == "refill" else []
	if mode in ["select", "refill"]:
		show_team()
	else:
		_after_team()


## Ausrüstungsbildschirm nur, wo das Original einen Typ-3/4-Knoten hat (Gamedata00.gdt; keiner vor AFRICA6, auch
## nicht in der Einzelmission 0x6B9680 „entfällt für Ordinal 10“, re_notes_roster_inventory §2) – sonst direkt in den Einsatz
func _after_team() -> void:
	var inf := _info()
	var eq = inf.get("equipment_screen", "equipment_new_storage")
	if not inf.is_empty() and (eq == null or String(eq) == ""):
		Game.save_campaign()
		start_requested.emit.call_deferred()
		return
	show_equipment()


func _t(id: int, fb: String) -> String:
	return SAS.text(id, fb)


func _info() -> Dictionary:
	return SAS.mission_info(Game.orig_folder(mission_id))


func _portrait(idx: int) -> Texture2D:
	return tex_file(SAS.portrait_path(idx))


func _strength(idx: int) -> float:
	return float(Game.sas_states()[str(idx)]["stats"].get("strength", 20.0))


# --- Teamauswahl (team members selection.4ds) ------------------------------------------

func show_team() -> void:
	page = "team"
	dropdown = ""
	begin("team members selection")
	title(2652 if mode == "refill" else 2651, "AUSWAHL DER TEAM-MITGLIEDER")
	var st := Game.sas_states()
	var team := Game.sas_team()
	var pool := SAS.store_indices()
	if focus_idx < 0:
		focus_idx = team[0] if not team.is_empty() else (pool[0] if not pool.is_empty() else -1)
	# links: Soldaten-Auswahl als Porträtstreifen (5 sichtbar, Bildlauf)
	text_at("text_military service draft", _t(2659, "Soldaten-Auswahl:"), 15)
	pool_ofs = clampi(pool_ofs, 0, maxi(pool.size() - POOL_PHOTOS.size(), 0))
	draw_frames(POOL_TABLES)
	var p0 := rect("photo03").position
	for i in POOL_PHOTOS.size():
		var k := pool_ofs + i
		if k >= pool.size():
			break
		var idx: int = pool[k]
		var pr := rect(POOL_PHOTOS[i])
		draw_frame(POOL_PHOTOS[i], Vector2.ZERO, {"X_F_001.BMP": _portrait(idx)})
		if bool(st.get(str(idx), {}).get("dead", false)):
			draw_frame("death", pr.position - p0)
		if idx == focus_idx:
			draw_frame("selector", pr.position - p0)
		hit(pr, func(dbl: bool): _pool_click(idx, dbl), "Pool%d" % idx)
	_scrollbar_h("scroll00", "normal09", "sliderbase", float(pool_ofs), float(maxi(pool.size() - POOL_PHOTOS.size(), 0)))
	orig_button("barrow up", "", func(): _scroll_pool(-1), pool_ofs > 0, "PoolLeft")
	orig_button("barrow down", "", func(): _scroll_pool(1), pool_ofs < pool.size() - POOL_PHOTOS.size(), "PoolRight")
	# Name + Rang des gewählten Soldaten (bnamexx)
	if focus_idx >= 0:
		var fs: Dictionary = st.get(str(focus_idx), {})
		label(rect("normal10", Rect2(68.7, 291.7, 414, 36)), "%s %s" % [SAS.rank_name(int(fs.get("rank", 0))),
			SAS.display_name(focus_idx)], 17, INK, HORIZONTAL_ALIGNMENT_CENTER).name = "SoldierName"
	text_at("text_selected soldier stats", _t(2668 if info_page else 2667, "Soldaten-Optionen:"), 15)
	if focus_idx >= 0:
		if info_page:
			text_at("text_05", SAS.bio(focus_idx), 13, HORIZONTAL_ALIGNMENT_LEFT, INK, true).name = "Bio"
		else:
			_stat_panel(focus_idx, 2)
		_medals(focus_idx)
	orig_button("bselected soldier info", _t(2666 if info_page else 2665, "SOLDATEN-INFO"), func():
		info_page = not info_page
		show_team(), focus_idx >= 0, "Info")
	# rechts: die 4 Teamplätze
	draw_frames(TEAM_TABLES + TEAM_FRAMES)
	for s in TEAM_TABLES.size():
		var tr := rect(TEAM_TABLES[s])
		if s < team.size():
			var idx: int = team[s]
			draw_frame(TEAM_PHOTOS[s], Vector2.ZERO, {"X_F_001.BMP": _portrait(idx)})
			var ms: Dictionary = st.get(str(idx), {})
			text_at("text_name0%d" % s, SAS.display_name(idx), 17).name = "TeamName%d" % s
			text_at("text_team member0%d" % s, "%s%s" % [SAS.rank_name(int(ms.get("rank", 0))),
				"" if not _locked.has(idx) else "  ✓"], 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
			if idx == focus_idx:
				draw_frame("selector", rect(TEAM_PHOTOS[s]).position - p0 - Vector2(1.1, 1.2))
			hit(tr, func(dbl: bool): _team_click(idx, dbl), "Team%d" % s)
	# Knöpfe (Frame-Namen laut Modell, Beschriftung laut Code 0x693590)
	var in_team := team.has(focus_idx)
	var dead := focus_idx >= 0 and bool(st.get(str(focus_idx), {}).get("dead", false))
	var can_assign: bool = (not _locked.has(focus_idx)) if in_team else (focus_idx >= 0 and not dead and team.size() < Game.team_size())
	orig_button("bassign - detach", _t(2658 if in_team else 2657, "HINZUFÜGEN"), func():
		team_remove(focus_idx) if Game.sas_team().has(focus_idx) else team_add(focus_idx), can_assign,
		"Remove" if in_team else "Add")
	orig_button("baccept and continue", _t(2654, "AUTOMATISCHE AUSWAHL"), auto_select, true, "Auto")
	orig_button("bauto assign", _t(2653, "FORTSETZEN"), _after_team, not team.is_empty(), "Continue")
	orig_button("bback", _t(2655, "ZURÜCK"), func(): back_requested.emit(), true, "Back")


func _scroll_pool(d: int) -> void:
	pool_ofs += d
	show_team()


func _pool_click(idx: int, dbl: bool) -> void:
	click_sound()
	focus_idx = idx
	if dbl:
		if Game.sas_team().has(idx):
			team_remove(idx)
		else:
			team_add(idx)
		return
	show_team()


func _team_click(idx: int, dbl: bool) -> void:
	focus_idx = idx
	if dbl and not _locked.has(idx):
		team_remove(idx)
		return
	_refresh()


## Waagrechte Bildlaufleiste: Leiste + Schieber an der Position pos/max
func _scrollbar_h(bar_frame: String, knob: String, base: String, pos: float, mx: float) -> void:
	draw_frame(bar_frame)
	var b := rect(base)
	var k := rect(knob)
	var frac: float = 0.0 if mx <= 0.0 else clampf(pos / mx, 0.0, 1.0)
	draw_frame(knob, Vector2(b.position.x + (b.size.x - k.size.x) * frac - k.position.x, 0))


func _scrollbar_v(bar_frame: String, knob: String, base: String, pos: float, mx: float) -> void:
	draw_frame(bar_frame)
	var b := rect(base)
	var k := rect(knob)
	var frac: float = 0.0 if mx <= 0.0 else clampf(pos / mx, 0.0, 1.0)
	draw_frame(knob, Vector2(0, b.position.y + (b.size.y - k.size.y) * frac - k.position.y))


## Werteleisten (panel02): col 2 = Frames der Teamauswahl, col 3 = Inventar/Mehrspieler
func _stat_panel(idx: int, col: int) -> void:
	var stats: Dictionary = Game.sas_states().get(str(idx), {}).get("stats", {})
	stat_rows(stats, col)


## Orden (medals_panel, 12 Plätze medal01…12): Bandschnalle <ORDEN>_b an der Platzmitte [P]
func _medals(idx: int) -> void:
	var got: Array = Game.sas_states().get(str(idx), {}).get("medals", [])
	for i in mini(got.size(), 12):
		var m := int(got[i])
		if m < 0 or m >= MEDAL_FRAMES.size():
			continue
		var dummy: Array = fr("medal%02d" % (i + 1)).get("pos_px", [])
		var name: String = MEDAL_FRAMES[m] + "_b"
		if dummy.size() == 2 and not fr(name).is_empty():
			var r := rect(name)
			draw_frame(name, Vector2(float(dummy[0]), float(dummy[1])) - r.get_center())


func team_add(idx: int) -> void:
	var team := Game.sas_team()
	if idx < 0 or team.has(idx) or team.size() >= Game.team_size() or Game.sas_states()[str(idx)]["dead"]:
		return
	team.append(idx)
	Game.set_sas_team(team)
	var inv := Game.sas_inventory(idx)
	if int(inv.get("hands", -1)) < 0 and inv.get("items", []).is_empty():
		_apply_recommended(idx)
	focus_idx = idx
	if page == "team":
		show_team()


func team_remove(idx: int) -> void:
	var team := Game.sas_team()
	if not team.has(idx) or _locked.has(idx):
		return
	team.erase(idx)
	Game.set_sas_team(team)
	if page == "team":
		show_team()


func auto_select() -> void:
	var keep: Array = _locked.duplicate()
	Game.set_sas_team(SAS.auto_select(Game.sas_states(), Game.team_size(), keep))
	for idx in Game.sas_team():
		var inv := Game.sas_inventory(idx)
		if int(inv.get("hands", -1)) < 0 and inv.get("items", []).is_empty():
			_apply_recommended(idx)
	if not Game.sas_team().has(focus_idx) and not Game.sas_team().is_empty():
		focus_idx = Game.sas_team()[0]
	if page == "team":
		show_team()


# --- Inventar-Auswahl (items selection.4ds) ------------------------------------------

func _storage() -> Dictionary:
	if not Game.campaign.has("storage"):
		Game.campaign["storage"] = []
	return {"items": Game.campaign["storage"]}


## Typ 3 „INVENTAR-AUSWAHL“ (neues Lager) bzw. Typ 4 „INVENTAR WECHSELN“ (Restbestand)
func new_storage() -> bool:
	return String(_info().get("equipment_screen", "equipment_new_storage")) != "equipment_keep_storage"


func show_equipment() -> void:
	page = "equip"
	var team := Game.sas_team()
	if not team.has(focus_idx):
		focus_idx = team[0] if not team.is_empty() else -1
	Game.ensure_essentials(mission_id)
	begin("items selection")
	title(2701 if new_storage() else 2702, "INVENTAR-AUSWAHL")
	_team_strip(team)
	if focus_idx >= 0:
		var inv := Game.sas_inventory(focus_idx)
		var w := SAS.inv_weight(inv)
		var over := SAS.overloaded(inv, _strength(focus_idx))
		text_at("name- capacity", "%s: %.1f / %d Kg" % [SAS.short_name(focus_idx, int(Game.sas_states()[str(focus_idx)]["rank"])),
			w, int(_strength(focus_idx))], 17, HORIZONTAL_ALIGNMENT_LEFT, INK_RED if over else INK).name = "Load"
		text_at("text_inventory", _t(2739 if status_page else 2728, "Inventar:"), 15)
		if status_page:
			draw_frame("table01")
			stat_rows(Game.sas_states()[str(focus_idx)]["stats"], 3)
		else:
			_equip_panel(inv, w, over)
		_type_box()
	orig_button("bassign to all", _t(2735 if status_page else 2736, "SOLDATEN-STATUS ANZEIGEN"), func():
		status_page = not status_page
		show_equipment(), focus_idx >= 0, "StatusToggle")
	_essentials()
	# rechts: Lager
	text_at("text_military storages", _t(2707, "Lager:"), 15)
	_store_list()
	_filter_box()
	orig_button("baccept and continue", _t(2704 if new_storage() else 2737, "EMPFOHLENE AUSWAHL"), func():
		if new_storage():
			_apply_recommended(focus_idx)
		else:
			auto_refill()
		show_equipment(), focus_idx >= 0, "Recommended")
	orig_button("bauto equip", _t(2703, "FORTSETZEN"), func(): try_start(), not team.is_empty(), "Continue")
	orig_button("bback", _t(2705, "ZURÜCK"), func(): show_team() if mode in ["select", "refill"] else back_requested.emit(),
		true, "Back")
	_setup_drag()
	if dropdown == "type":
		_type_list()
	elif dropdown == "filter":
		_filter_list()
	if _status_text != "":
		var msg := _status_text
		_status_text = ""
		dialog(msg, [[_t(2013, "OK"), func(): pass]])


func _team_strip(team: Array) -> void:
	text_at("text_team", _t(2706, "Team:"), 15)
	draw_frame("table16")
	draw_frames(["table11", "table13", "table14", "table15"])
	var p0 := rect("photo03").position
	for s in mini(team.size(), EQ_PHOTOS.size()):
		var idx: int = team[s]
		var pr := rect(EQ_PHOTOS[s])
		draw_frame(EQ_PHOTOS[s], Vector2.ZERO, {"X_F_063.BMP": _portrait(idx)})
		if idx == focus_idx:
			draw_frame("selector", pr.position - p0)
		hit(pr, func(_dbl: bool): _focus(idx), "Soldier%d" % idx)


func _focus(idx: int) -> void:
	click_sound()
	focus_idx = idx
	sel_inv = ""
	pocket_ofs = 0
	pack_ofs = 0
	if page == "team":
		show_team()
	else:
		show_equipment()


## Symbol eines Gegenstands auf einem Platz-Frame (X_BUBBLE = Rahmenring, X_SQUARE = Innenfläche -> ii_*/wi_*-Symbol)
func _item_box(frame: String, id: int, shift := Vector2.ZERO, count := 0) -> void:
	var ov := {}
	var icon: String = SAS.item_icon_path(id) if id >= 0 else ""
	if icon != "":
		ov["X_SQUARE.BMP"] = tex_file(icon)
	draw_frame(frame, shift, ov)
	var r := rect(frame)
	r.position += shift
	if id >= 0 and icon == "":
		label(r.grow(-4), SAS.item_label(id), 10, INK, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, true)
	if count > 1:
		label(Rect2(r.position + Vector2(4, r.size.y - 16), Vector2(r.size.x - 8, 14)), "%d" % count, 12, INK,
			HORIZONTAL_ALIGNMENT_RIGHT)


## Taschen + Rucksack als Original-Spalten (Anzeige; Logik = gemeinsames Inventar): Stapel der Reihe nach in die
## Taschen (bis 12 Raumeinheiten), der Rest in den Rucksack. Reihenfolge ItemOrder: Aufnahmereihenfolge wie im
## Original (0x6A3080/0x672280), Munition direkt unter ihrer Waffe in der Liste (Vorgabe Auftraggeber)
func split_columns(inv: Dictionary) -> Array:
	return SAS.split_items(inv)     # B-014: Rucksackspalte nur mit angelegtem Rucksack


func _equip_panel(inv: Dictionary, w: float, over: bool) -> void:
	draw_frames(["table01", "hlcpctcr02", "hlcpctcr00", "hlcpctcr01"])
	bar("hlcpct02", w / maxf(_strength(focus_idx), 1.0))
	if over:
		bar("overload", 1.0)
	var cols := split_columns(inv)
	var pocket_used := 0.0
	for e in cols[0]:
		pocket_used += SAS.space(int(e[0])) * int(e[1])
	var pack_used := 0.0
	for e in cols[1]:
		pack_used += SAS.space(int(e[0])) * int(e[1])
	var pack_cap := SAS.backpack_space(int(inv.get("back", -1)))
	bar("hlcpct00", pocket_used / SAS.POCKET_SPACE, true)
	bar("hlcpct01", pack_used / pack_cap if pack_cap > 0.0 else 0.0, true)
	text_at("text_cpcty", "%s: %.1f / %d Kg" % [_t(2730, "Gewicht"), w, int(_strength(focus_idx))], 11)
	text_at("text_hlstrscap", "%d%%" % roundi(100.0 * pocket_used / SAS.POCKET_SPACE), 11, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("text_bkpckcap", ("%d%%" % roundi(100.0 * pack_used / pack_cap)) if pack_cap > 0.0 else _t(2727, "KEINE").strip_edges(),
		11, HORIZONTAL_ALIGNMENT_CENTER)
	for slot in SLOT_FRAMES:
		var f: Array = SLOT_FRAMES[slot]
		text_at(f[1], _t(SAS.SLOT_TEXT[slot], slot), 11, HORIZONTAL_ALIGNMENT_CENTER)
		var id := int(inv.get(slot, -1))
		_item_box(f[0], id)
		hit(rect(f[0]), func(dbl: bool): _slot_click(slot, dbl), "Slot_" + slot, true)
	text_at("text_drop", _t(2712, "Ablegen"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	_item_box("drop", -1)
	hit(rect("drop"), func(_dbl: bool): _drop_click(), "Slot_drop", true)
	text_at("text_holsters", _t(2716, "Taschen"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("text_backpack", _t(2717, "Rucksack"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	pocket_ofs = clampi(pocket_ofs, 0, maxi((cols[0] as Array).size() - 4, 0))
	pack_ofs = clampi(pack_ofs, 0, maxi((cols[1] as Array).size() - 4, 0))
	hit(rect("item00").merge(rect("item07")), func(_d: bool): pass, "InvArea")     # Ablagefläche Taschen/Rucksack
	_column(cols[0], POCKETS, pocket_ofs)
	_column(cols[1], PACK, pack_ofs)
	_scrollbar_v("scroll13", "normal13", "sliderbase12", float(pocket_ofs), float(maxi((cols[0] as Array).size() - 4, 0)))
	_scrollbar_v("scroll14", "normal14", "sliderbase13", float(pack_ofs), float(maxi((cols[1] as Array).size() - 4, 0)))
	orig_button("barrow up23", "", func():
		pocket_ofs -= 1
		show_equipment(), pocket_ofs > 0, "PocketsUp")
	orig_button("barrow down23", "", func():
		pocket_ofs += 1
		show_equipment(), pocket_ofs < (cols[0] as Array).size() - 4, "PocketsDown")
	orig_button("barrow up24", "", func():
		pack_ofs -= 1
		show_equipment(), pack_ofs > 0, "PackUp")
	orig_button("barrow down24", "", func():
		pack_ofs += 1
		show_equipment(), pack_ofs < (cols[1] as Array).size() - 4, "PackDown")
	# Ziel-Markierungen (MM_RED) für den im Lager gewählten Gegenstand, Auswahlrahmen am Soldaten
	if sel_store >= 0:
		var target := SAS.slot_for(sel_store)
		if target == "hands" and int(inv.get("hands", -1)) >= 0:
			draw_frame("selshoulder")
		if target != "":
			draw_frame(SLOT_FRAMES[target][2])
		else:
			draw_frames(["selholsters", "selbackpack"])
	elif sel_inv in SLOT_FRAMES:
		draw_frame(SLOT_FRAMES[sel_inv][2])
	if sel_inv != "":
		draw_frame("seldrop")


func _column(entries: Array, boxes: Array, ofs: int) -> void:
	for i in boxes.size():
		var k := ofs + i
		var id: int = int(entries[k][0]) if k < entries.size() else -1
		_item_box(boxes[i], id, Vector2.ZERO, int(entries[k][1]) if k < entries.size() else 0)
		if id >= 0:
			if sel_inv == "item:%d" % id:
				draw_frame("selhands", rect(boxes[i]).position - rect("hands").position)
			hit(rect(boxes[i]), func(dbl: bool): _inv_item_click(id, dbl), "Inv%d" % id, true)


func _slot_click(slot: String, dbl: bool) -> void:
	click_sound()
	if sel_store >= 0:
		var id := sel_store
		give(focus_idx, id, 1, slot)
		return
	if dbl:
		unequip(focus_idx, slot)
		return
	sel_inv = slot if int(Game.sas_inventory(focus_idx).get(slot, -1)) >= 0 else ""
	show_equipment()


func _inv_item_click(id: int, dbl: bool) -> void:
	click_sound()
	if dbl:
		take_back(focus_idx, id)
		sel_inv = ""
		return
	sel_store = -1
	sel_inv = "item:%d" % id
	show_equipment()


## „Ablegen“: markierten Gegenstand ins Lager zurück
func _drop_click() -> void:
	click_sound()
	if sel_inv.begins_with("item:"):
		take_back(focus_idx, int(sel_inv.substr(5)))
	elif sel_inv != "":
		unequip(focus_idx, sel_inv)
	sel_inv = ""
	_refresh()


## Lagerliste (allitemspanel): Zeile = Symbol item08 (+ Magazin item09 bei Waffen) und Text text_info00.
## Reihenfolge (ItemOrder): Munition steht direkt unter der passenden Waffe (Zeilen mit 84 px: item09 unter
## item08, sonst eigene Folgezeile); teilen sich mehrere Waffen ein Magazin, nur unter der ersten; Munition ohne
## Waffe im Lager am Ende der Kategorie ihrer Waffe.
func store_rows() -> Array:
	var store: Array = _storage()["items"]
	var have := {}
	for e in store:
		if int(e[1]) > 0:
			have[int(e[0])] = int(e[1])
	# Besitzer jedes Magazins = erste passende Waffe im Lager (Kategorie, dann Name) – kategorieübergreifend,
	# damit z. B. MG-42-Gurte nicht zusätzlich als „ohne Waffe“ erscheinen, wenn nur ein MG 15 im Lager ist
	var all: Array = []
	for id in have:
		if not ItemOrder.is_ammo(id):
			all.append(id)
	all.sort_custom(_by_category_label)
	var owner := {}
	for id in all:
		var am := ItemOrder.ammo_for(id)
		if am >= 0 and have.has(am) and not owner.has(am):
			owner[am] = id
	var rows: Array = []
	for id in all:
		if SAS.item_category(id) != category:
			continue
		var am := ItemOrder.ammo_for(id)
		var weapon := SAS.item_kind(id) == "weapon"
		if am < 0 or int(owner.get(am, -1)) != id:
			rows.append({"id": id, "ammo": -1, "weapon": weapon})
		elif category <= 2:
			rows.append({"id": id, "ammo": am, "weapon": weapon})
		else:
			rows.append({"id": id, "ammo": -1, "weapon": weapon})
			rows.append({"id": am, "ammo": -1, "of": id})
	var orphans: Array = []
	for id in have:
		if ItemOrder.is_ammo(id) and not owner.has(id) and ItemOrder.ammo_category(id) == category:
			orphans.append(id)
	orphans.sort_custom(func(a, b): return SAS.item_label(int(a)) < SAS.item_label(int(b)))
	for id in orphans:
		rows.append({"id": id, "ammo": -1})
	return rows


func _by_category_label(a: Variant, b: Variant) -> bool:
	return ItemOrder.by_category_label(int(a), int(b))


func _store_count(id: int) -> int:
	for e in _storage()["items"]:
		if int(e[0]) == id:
			return int(e[1])
	return 0


func _store_list() -> void:
	draw_frame("table02")
	hit(rect("table02"), func(_d: bool): pass, "StoreArea")      # Ablagefläche Lager (Ziehen und Ablegen)
	var rows := store_rows()
	var row_h: float = 84.0 if category <= 2 else 42.0
	var visible := int((STORE_BOTTOM - STORE_TOP) / row_h)
	store_ofs = clampi(store_ofs, 0, maxi(rows.size() - visible, 0))
	var icon0 := rect("item08")
	var info0 := rect("text_info00")
	for i in visible:
		var k := store_ofs + i
		if k >= rows.size():
			break
		var row: Dictionary = rows[k]
		var id := int(row["id"])
		var dy := Vector2(0, row_h * i)
		_item_box("item08", id, dy)
		hit(Rect2(icon0.position + dy, icon0.size), func(dbl: bool): _store_click(id, dbl), "Store%d" % id, true)
		if sel_store == id:
			draw_frame("itemselector", dy)
		var am := int(row.get("ammo", -1))
		var lines: Array = ["%s  (%d)" % [SAS.item_label(id), _store_count(id)],
			"%s : %.2f kg" % [_t(2730, "Gewicht"), SAS.weight(id)]]
		if bool(row.get("weapon", false)):
			var mag := int(SAS._weapons.get(id, {}).get("magazine", 0))
			if mag > 0:
				lines.append("%s : %d" % [_t(2731, "Anzahl der Kugeln im Magazin"), mag])
		if am >= 0:
			_item_box("item09", am, dy)
			hit(Rect2(rect("item09").position + dy, icon0.size), func(dbl: bool): _store_click(am, dbl), "Store%d" % am, true)
			if sel_store == am:
				draw_frame("itemselector01", dy)
			lines.append("%s  (%d)" % [SAS.item_label(am), _store_count(am)])
		var tr := Rect2(info0.position + dy + Vector2(4, 0), Vector2(info0.size.x - 4, row_h - 2))
		label(tr, "\n".join(lines), 12, INK, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true)
		hit(tr, func(dbl: bool): _store_click(id, dbl), "StoreText%d" % id, true)
	_scrollbar_v("scroll01", "normal10", "sliderbase01", float(store_ofs), float(maxi(rows.size() - visible, 0)))
	orig_button("barrow up01", "", func():
		store_ofs -= 1
		show_equipment(), store_ofs > 0, "StoreUp")
	orig_button("barrow down01", "", func():
		store_ofs += 1
		show_equipment(), store_ofs < rows.size() - visible, "StoreDown")


func _store_click(id: int, dbl: bool) -> void:
	click_sound()
	sel_inv = ""
	if dbl and focus_idx >= 0:
		give(focus_idx, id)
		return
	sel_store = -1 if sel_store == id else id
	show_equipment()


## Klassifizierung (filter): Aufklappliste mit den Gruppen 2719–2725
func _filter_box() -> void:
	draw_frame("filter")
	text_at("header", _t(SAS.CATEGORY_TEXT[category], "LEICHTE WAFFEN"), 15, HORIZONTAL_ALIGNMENT_LEFT).name = "FilterHeader"
	hit(rect("header"), func(_d: bool): _toggle_dropdown("filter"), "FilterOpen")
	orig_button("cbdown01", "", func(): _toggle_dropdown("filter"), true, "FilterArrow")


func _filter_list() -> void:
	draw_frames(["shadow02", "listbox"])
	var r := rect("text00", Rect2(534, 172, 322, 190))
	for i in SAS.CATEGORY_TEXT.size():
		var lr := Rect2(r.position + Vector2(0, 24 * i), Vector2(r.size.x, 22))
		label(lr, _t(SAS.CATEGORY_TEXT[i], ""), 15, INK_RED if i == category else INK)
		hit(lr, func(_d: bool):
			category = i
			store_ofs = 0
			sel_store = -1
			dropdown = ""
			show_equipment(), "Category%d" % i)


func _toggle_dropdown(which: String) -> void:
	click_sound()
	dropdown = "" if dropdown == which else which
	show_equipment()


## Soldatentyp (soldier type): Vorlage aus presets.def für den gewählten Soldaten
func _type_box() -> void:
	draw_frame("soldier type")
	var cur := int(_type_of.get(focus_idx, -1))
	text_at("headerx", SAS.preset_label(cur) if cur >= 0 else _t(500, "KEINE"), 15).name = "TypeHeader"
	hit(rect("headerx"), func(_d: bool): _toggle_dropdown("type"), "TypeOpen")
	orig_button("cbdown01x", "", func(): _toggle_dropdown("type"), true, "TypeArrow")


## Liste: KEINE + Soldatentyp-Vorlagen (presets.def) + eigene Vorlagen „Leer 1…6“ (user_presets_orig.def).
## Eigene Vorlage: leer → aktuelle Ausrüstung des Soldaten speichern; belegt → anwenden; Umschalt+Klick → überschreiben.
func _type_list() -> void:
	draw_frames(["shadow01", "listboxx"])
	var r := rect("text00x", Rect2(72, 336, 326, 207))
	var entries: Array = [-1] + SAS.soldier_type_presets()
	var user := UserPresets.sp_presets()
	var row_h := minf(21.0, (r.size.y - 6.0) / float(entries.size() + user.size()))
	var fs: int = 14 if row_h >= 18.0 else 11
	for i in entries.size():
		var p: int = entries[i]
		var lr := Rect2(r.position + Vector2(0, row_h * i), Vector2(r.size.x, row_h - 1))
		label(lr, SAS.preset_label(p) if p >= 0 else _t(500, "KEINE"), fs, INK_RED if p == int(_type_of.get(focus_idx, -1)) else INK)
		hit(lr, _pick_type.bind(p), "Type%d" % p)
	for j in user.size():
		var lr := Rect2(r.position + Vector2(0, row_h * (entries.size() + j)), Vector2(r.size.x, row_h - 1))
		var up: Dictionary = user[j]
		var empty := UserPresets.is_empty(up)
		label(lr, ("+ " if empty else "• ") + UserPresets.label(up), fs, INK_DISABLED if empty else INK)
		hit(lr, _pick_user_preset.bind(j), "UserPreset%d" % j)


func _pick_type(_d: bool, p: int) -> void:
	dropdown = ""
	apply_preset(focus_idx, p)
	show_equipment()


func _pick_user_preset(_d: bool, j: int) -> void:
	click_sound()
	dropdown = ""
	var up: Dictionary = UserPresets.sp_presets()[j]
	if UserPresets.is_empty(up) or Input.is_key_pressed(KEY_SHIFT):
		save_user_preset(j)
	else:
		apply_user_preset(focus_idx, j)
	show_equipment()


## Aktuelle Ausrüstung des gewählten Soldaten als eigene Vorlage j (0–5) speichern
func save_user_preset(j: int) -> void:
	if focus_idx < 0:
		return
	var st: Dictionary = Game.sas_states().get(str(focus_idx), {})
	UserPresets.store_sp(j, Game.sas_inventory(focus_idx), "Vorlage %d – %s" % [j + 1,
		SAS.short_name(focus_idx, int(st.get("rank", 0)))])
	_say("Vorlage %d gespeichert (user_presets_orig.def)." % (j + 1))


## Eigene Vorlage anwenden: Gegenstände aus dem Lager, soweit vorhanden (fehlende: Hinweis 9522)
func apply_user_preset(idx: int, j: int) -> void:
	if idx < 0:
		return
	var want := UserPresets.to_inventory(UserPresets.sp_presets()[j])
	_apply_inventory(idx, want)


func _apply_inventory(idx: int, want: Dictionary) -> void:
	var inv := Game.sas_inventory(idx)
	var store := _storage()
	for slot in SAS.SLOTS:
		if int(inv.get(slot, -1)) >= 0:
			SAS.add_item(store, int(inv[slot]), 1)
			inv[slot] = -1
	for e in inv.get("items", []):
		SAS.add_item(store, int(e[0]), int(e[1]))
	inv["items"] = []
	var missing := false
	for slot in SAS.SLOTS:
		var id := int(want.get(slot, -1))
		if id < 0:
			continue
		if _store_count(id) > 0:
			SAS.remove_item(store, id, 1)
			inv[slot] = id
		else:
			missing = true
	for e in want["items"]:
		var n := mini(int(e[1]), _store_count(int(e[0])))
		if n < int(e[1]):
			missing = true
		if n > 0 and SAS.can_add(inv, _strength(idx), int(e[0]), n):
			SAS.remove_item(store, int(e[0]), n)
			SAS.add_item(inv, int(e[0]), n)
	if missing:
		_say(_t(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände."))


func _essentials() -> void:
	var ess := SAS.essentials(_info())
	if ess.is_empty():
		return
	var missing := missing_essentials()
	var names: Array = []
	for e in ess:
		names.append(("%d× " % int(e[1]) if int(e[1]) > 1 else "") + SAS.item_label(int(e[0])))
	text_at("text_mission essentials", _t(2729, "Benötigte Gegenstände für die Mission:") + "\n" + ", ".join(names), 13,
		HORIZONTAL_ALIGNMENT_LEFT, INK_RED if not missing.is_empty() else INK, true).name = "Essentials"


## Gegenstand aus dem Lager an den Soldaten: gewünschter bzw. passender Platz (Hände/Schulter/Kopf/Uniform/
## Rücken; belegter Platz wird getauscht) oder ins gemeinsame Inventar (Gewicht ≤ Kraft, Raum ≤ Taschen + Rucksack).
func give(idx: int, id: int, count := -1, want := "") -> bool:
	var store := _storage()
	var have := _store_count(id)
	if have <= 0 or idx < 0:
		return false
	var inv := Game.sas_inventory(idx)
	var slot := SAS.slot_for(id)
	if want == "items":
		slot = ""            # auf Taschen/Rucksack gezogen: ins gemeinsame Inventar statt auf einen Platz
		want = ""
	if slot == "hands" and want == "shoulder":
		slot = "shoulder"
	elif slot == "hands" and want == "" and int(inv.get("hands", -1)) >= 0 and int(inv.get("shoulder", -1)) < 0:
		slot = "shoulder"
	if want in SLOT_FRAMES and want != slot:
		_say("%s → %s: nicht möglich." % [SAS.item_label(id), _t(SAS.SLOT_TEXT[want], want)])
		return false
	if slot != "":
		var old := int(inv.get(slot, -1))
		var w: float = SAS.inv_weight(inv) + SAS.weight(id) - (SAS.weight(old) if old >= 0 else 0.0)
		if w > _strength(idx) + 0.001:
			_say("Zu schwer für %s." % SAS.display_name(idx))
			return false
		if slot == "back":
			# Original 0x6A3080: Rucksacktausch nur, wenn der neue den bisherigen Inhalt fasst (B-014)
			var trial := inv.duplicate(true)
			trial["back"] = id
			if not SAS.fits(trial):
				_say("%s: Inhalt passt nicht." % SAS.item_label(id))
				return false
		SAS.remove_item(store, id, 1)
		if old >= 0:
			SAS.add_item(store, old, 1)
		inv[slot] = id
	else:
		var n: int = 1 if count < 0 else mini(count, have)
		if not SAS.can_add(inv, _strength(idx), id, n):
			_say("Kein Platz bzw. zu schwer (Taschen + Rucksack).")
			return false
		SAS.remove_item(store, id, n)
		SAS.add_item(inv, id, n)
	sel_store = id if _store_count(id) > 0 else -1
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
	while not SAS.fits(inv) and not inv["items"].is_empty():
		var e: Array = inv["items"].back()
		take_back(idx, int(e[0]), int(e[1]))
	_refresh()


## Soldatentyp-Vorlage anwenden: bisherige Ausrüstung ins Lager, Vorlage aus dem Lager, soweit vorhanden
## (fehlende Gegenstände: Hinweis 9522 wie im Original)
func apply_preset(idx: int, preset: int) -> void:
	if idx < 0:
		return
	_type_of[idx] = preset
	if preset < 0:
		return
	var inv := Game.sas_inventory(idx)
	var store := _storage()
	for slot in SAS.SLOTS:
		if int(inv.get(slot, -1)) >= 0:
			SAS.add_item(store, int(inv[slot]), 1)
			inv[slot] = -1
	for e in inv.get("items", []):
		SAS.add_item(store, int(e[0]), int(e[1]))
	inv["items"] = []
	var want := SAS.preset_inventory(preset)
	var missing := false
	for slot in SAS.SLOTS:
		var id := int(want.get(slot, -1))
		if id < 0:
			continue
		if _store_count(id) > 0:
			SAS.remove_item(store, id, 1)
			inv[slot] = id
		else:
			missing = true
	for e in want["items"]:
		var n := mini(int(e[1]), _store_count(int(e[0])))
		if n < int(e[1]):
			missing = true
		if n > 0 and SAS.can_add(inv, _strength(idx), int(e[0]), n):
			SAS.remove_item(store, int(e[0]), n)
			SAS.add_item(inv, int(e[0]), n)
	if missing:
		_say(_t(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände."))


## Original „EMPFOHLENE AUSWAHL“: Preset aus miss_itm.def für den Platz im Team (bisherige Ausrüstung ins Lager)
func _apply_recommended(idx: int) -> void:
	var rec := SAS.recommended_presets(_info())
	if rec.is_empty() or idx < 0:
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


## „AUTOMATISCHES AUFFÜLLEN“ (Typ 4, Text 2737): Magazine der getragenen Waffen aus dem Lager bis zur Menge der
## empfohlenen Vorlage des Teamplatzes nachfüllen (Regel = Annahme [P], Handler nicht disassembliert)
func auto_refill() -> void:
	var rec := SAS.recommended_presets(_info())
	for idx in Game.sas_team():
		var inv := Game.sas_inventory(idx)
		var want: Dictionary = SAS.preset_inventory(rec[maxi(Game.sas_team().find(idx), 0) % rec.size()]) if not rec.is_empty() else SAS.new_inventory()
		for slot in ["hands", "shoulder"]:
			var wpn := int(inv.get(slot, -1))
			var am: int = SAS.ammo_of(wpn) if wpn >= 0 else -1
			if am < 0:
				continue
			var target := maxi(SAS.count_of(want, am), 4)
			while SAS.count_of(inv, am) < target and _store_count(am) > 0 and SAS.can_add(inv, _strength(idx), am, 1):
				SAS.remove_item(_storage(), am, 1)
				SAS.add_item(inv, am, 1)


func missing_essentials() -> Array:
	var out: Array = []
	for e in SAS.essentials(_info()):
		var have := 0
		for idx in Game.sas_team():
			have += SAS.count_of(Game.sas_inventory(idx), e[0])
		if have < e[1]:
			out.append(e[0])
	return out


## Original: Überladung verhindert das Fortsetzen (Text 2023); benötigte Gegenstände müssen dabei sein.
func can_start() -> String:
	if Game.sas_team().is_empty():
		return "Kein Team."
	for idx in Game.sas_team():
		if SAS.overloaded(Game.sas_inventory(idx), _strength(idx)):
			return _t(2023, "%s ist überladen." % SAS.display_name(idx))
	var miss := missing_essentials()
	if not miss.is_empty():
		var names: Array = []
		for i in miss:
			names.append(SAS.item_label(i))
		return _t(2729, "Benötigte Gegenstände für die Mission:") + " " + ", ".join(names)
	return ""


func _unarmed() -> bool:
	for idx in Game.sas_team():
		var inv := Game.sas_inventory(idx)
		var armed := false
		for slot in ["hands", "shoulder"]:
			armed = armed or int(inv.get(slot, -1)) >= 0
		for e in inv.get("items", []):
			armed = armed or SAS.item_kind(int(e[0])) == "weapon" and SAS.item_category(int(e[0])) <= 2
		if not armed:
			return true
	return false


## FORTSETZEN: Überladung/Pflichtgegenstände sperren; unbewaffnete Soldaten -> Rückfrage 9521 (JA/ANNULLIEREN);
## Einzelkämpfer-Einsatz -> Dialog „AKTIVEN SOLDAT AUSWÄHLEN“
func try_start(confirmed := false) -> bool:
	var why := can_start()
	if why != "":
		_say(why)
		return false
	if not confirmed and _unarmed() and page == "equip":
		dialog(_t(9521, "Einige Ihrer Soldaten sind unbewaffnet. Wirklich weiter machen?"),
			[[_t(2001, "JA"), func(): try_start(true)], [_t(2008, "ANNULLIEREN"), func(): pass]])
		return false
	if bool(_info().get("solo_mission", false)) and page == "equip" and Game.sas_team().size() > 1 and not _solo_chosen:
		_select_active_dialog()
		return false
	Game.save_campaign()
	start_requested.emit()
	return true


var _solo_chosen := false
var _solo_pick := -1


## Original-Dialog „AKTIVEN SOLDAT AUSWÄHLEN“ (selection screen.4ds); der gewählte Soldat rückt an Platz 1
func _select_active_dialog() -> void:
	var lay := load_layout("selection screen")
	var team := Game.sas_team()
	if _solo_pick < 0:
		_solo_pick = team[0]
	var ov := Control.new()
	ov.name = "SelectActive"
	ov.size = REF
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(ov)
	draw_from(lay, ["shadow03", "table", "table11", "table13", "table14", "table15"], ov)
	var t := rect_in(lay, "text_select one soldier", Rect2(342, 253, 338, 34))
	var l := Label.new()
	l.position = t.position
	l.size = t.size
	l.text = _t(2738, "AKTIVEN SOLDAT AUSWÄHLEN")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", INK)
	ov.add_child(l)
	var photos := ["photo03", "photo04", "photo05", "photo06"]
	var p0 := rect_in(lay, "photo03").position
	for i in mini(team.size(), 4):
		var idx: int = team[i]
		var pr := rect_in(lay, photos[i])
		draw_from(lay, [photos[i]], ov, Vector2.ZERO, {"X_F_001.BMP": _portrait(idx)})
		if idx == _solo_pick:
			draw_from(lay, ["selector"], ov, pr.position - p0)
		var c := Control.new()
		c.position = pr.position
		c.size = pr.size
		c.name = "Pick%d" % idx
		c.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_solo_pick = idx
				ov.queue_free()
				_select_active_dialog())
		ov.add_child(c)
	button_from(lay, "button01", _t(2001, "JA"), func():
		ov.queue_free()
		var tm := Game.sas_team()
		tm.erase(_solo_pick)
		tm.push_front(_solo_pick)
		Game.set_sas_team(tm)
		_solo_chosen = true
		try_start(true), true, "PickYes", 16, Rect2(312, 394, 193, 35), Vector2.ZERO, ov)
	button_from(lay, "button00", _t(2008, "ANNULLIEREN"), func(): ov.queue_free(), true, "PickNo", 16,
		Rect2(519, 394, 193, 35), Vector2.ZERO, ov)


# --- Ziehen und Ablegen (Original: Gegenstände per Maus zwischen Lager, Plätzen, Taschen/Rucksack und „Ablegen“
# ziehen; rote Ziel-Markierungen sel*) und Beschreibung (MODELS\description.4ds, Rechtsklick) ---------------------

## Ziehquellen/Ablageziele an den Klickflächen des Bildschirms (Kennung „hit“-Meta: Store<ID>, StoreText<ID>,
## Slot_<Platz>, Inv<ID>, InvArea, StoreArea)
func _setup_drag() -> void:
	if focus_idx < 0:
		return
	var inv := Game.sas_inventory(focus_idx)
	for c in stage.get_children():
		if not c is Control or not c.has_meta("hit"):
			continue
		var h := String(c.get_meta("hit"))
		var src := {}
		var target := ""
		if h == "StoreArea":
			target = "store"
		elif h == "InvArea":
			target = "inv"
		elif h.begins_with("StoreText") or (h.begins_with("Store") and h.substr(5).is_valid_int()):
			var sid := int(h.trim_prefix("StoreText").trim_prefix("Store"))
			src = {"from": "store", "id": sid}
			target = "store"
		elif h.begins_with("Slot_"):
			var slot := h.substr(5)
			target = "drop" if slot == "drop" else "slot:" + slot
			if slot != "drop" and int(inv.get(slot, -1)) >= 0:
				src = {"from": "slot", "slot": slot, "id": int(inv.get(slot, -1))}
		elif h.begins_with("Inv") and h.substr(3).is_valid_int():
			src = {"from": "inv", "id": int(h.substr(3))}
			target = "inv"
		else:
			continue
		(c as Control).set_drag_forwarding(_drag_from.bind(c, src), _can_drop.bind(target), _drop_on.bind(target))
		if src.has("id"):
			(c as Control).gui_input.connect(_right_click.bind(int(src["id"])))


func _drag_from(_at: Vector2, c: Control, src: Dictionary) -> Variant:
	if src.is_empty():
		return null
	var id := int(src["id"])
	var icon := SAS.item_icon_path(id)
	var pv := TextureRect.new()
	pv.texture = tex_file(icon) if icon != "" else null
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.size = Vector2(70, 41) * stage.scale
	pv.modulate = Color(1, 1, 1, 0.8)
	if pv.texture == null:
		var l := Label.new()
		l.text = SAS.item_label(id)
		l.add_theme_color_override("font_color", INK)
		pv.add_child(l)
	c.set_drag_preview(pv)
	return src


func _can_drop(_at: Vector2, data: Variant, target: String) -> bool:
	if not data is Dictionary or not (data as Dictionary).has("from"):
		return false
	var from := String(data["from"])
	if target.begins_with("slot:"):
		var slot := target.substr(5)
		if from == "slot":
			return String(data["slot"]) != slot and String(data["slot"]) in ["hands", "shoulder"] and slot in ["hands", "shoulder"]
		var want := SAS.slot_for(int(data["id"]))
		return want == slot or (want == "hands" and slot == "shoulder")
	match target:
		"store", "drop":
			return from != "store"
		"inv":
			return from != "inv"
	return false


func _drop_on(_at: Vector2, data: Variant, target: String) -> void:
	drop_item(data, target)


## Ablegen (auch für Tests): data = {from: store/slot/inv, id, slot}, target = store/drop/inv/slot:<Platz>
func drop_item(data: Dictionary, target: String) -> bool:
	if not _can_drop(Vector2.ZERO, data, target) or focus_idx < 0:
		return false
	click_sound()
	var id := int(data["id"])
	var from := String(data["from"])
	var inv := Game.sas_inventory(focus_idx)
	sel_store = -1
	sel_inv = ""
	var ok := true
	if from == "store":
		ok = give(focus_idx, id, 1, "items" if target == "inv" else target.substr(5))
	elif from == "slot":
		var slot := String(data["slot"])
		if target in ["store", "drop"]:
			unequip(focus_idx, slot)
		elif target == "inv":
			inv[slot] = -1
			if SAS.can_add(inv, _strength(focus_idx), id):
				SAS.add_item(inv, id, 1)
			else:
				inv[slot] = id
				_say("Kein Platz bzw. zu schwer (Taschen + Rucksack).")
				ok = false
		else:
			var other := target.substr(5)
			var o := int(inv.get(other, -1))
			inv[other] = id
			inv[slot] = o
	else:
		if target in ["store", "drop"]:
			take_back(focus_idx, id, 1)
		else:
			# aus Taschen/Rucksack auf einen Platz: über das Lager (Gewichtsprüfung in give), sonst zurück
			SAS.remove_item(inv, id, 1)
			SAS.add_item(_storage(), id, 1)
			ok = give(focus_idx, id, 1, target.substr(5))
			if not ok:
				SAS.remove_item(_storage(), id, 1)
				SAS.add_item(inv, id, 1)
	_refresh()
	return ok


func _right_click(ev: InputEvent, id: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		show_description(id, stage.get_local_mouse_position())


## Beschreibung eines Gegenstands (MODELS\description.4ds, Rahmen „description“ an der Maus): Name, Gewicht,
## Magazin, Mündungsgeschwindigkeit, Zielfernrohr (Texte 2730–2734 wie die Lagerdetails 0x680D0A)
func description_lines(id: int) -> Array:
	var lines: Array = [SAS.item_label(id), "%s : %.2f kg" % [_t(2730, "Gewicht"), SAS.weight(id)]]
	var wd: Dictionary = SAS._weapons.get(id, {})
	if not wd.is_empty():
		if int(wd.get("magazine", 0)) > 0:
			lines.append("%s : %d" % [_t(2731, "Anzahl der Kugeln im Magazin"), int(wd.get("magazine", 0))])
		if float(wd.get("muzzle_velocity", 0.0)) > 0.0:
			lines.append("%s : %.2f m/s" % [_t(2732, "Schussgeschwindigkeit"), float(wd.get("muzzle_velocity", 0.0))])
		if float(wd.get("scope_zoom", 0.0)) > 1.0:
			lines.append("%s : %.2f x" % [_t(2734, "Zielfernrohr"), float(wd.get("scope_zoom", 0.0))])
	var am := SAS.ammo_of(id)
	if am >= 0:
		lines.append(SAS.item_label(am))
	return lines


func show_description(id: int, at: Vector2) -> void:
	var old := stage.get_node_or_null("Description")
	if old:
		old.queue_free()
	var lay := load_layout("description")
	var ov := Control.new()
	ov.name = "Description"
	ov.size = REF
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(ov)
	var fr0 := rect_in(lay, "description", Rect2(-128, 30, 256, 122))
	var pos := Vector2(clampf(at.x, -fr0.position.x + 4.0, REF.x - fr0.end.x - 4.0), clampf(at.y - fr0.position.y + 8.0, 0.0, REF.y - fr0.end.y))
	draw_from(lay, ["shadow", "description"], ov, pos)
	var tr := rect_in(lay, "text", Rect2(-117, 43, 234, 97))
	tr.position += pos
	var l := Label.new()
	l.name = "DescriptionText"
	l.position = tr.position
	l.size = tr.size
	l.text = "\n".join(description_lines(id))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", INK)
	ov.add_child(l)
	ov.gui_input.connect(_close_overlay.bind(ov))


func _close_overlay(ev: InputEvent, ov: Control) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		ov.queue_free()


func _say(t: String) -> void:
	_status_text = t
	if page == "equip" and is_inside_tree():
		_refresh()


func _refresh() -> void:
	if page == "equip":
		show_equipment.call_deferred()
	elif page == "team":
		show_team.call_deferred()
