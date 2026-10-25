class_name PlayerSetupScreen
extends OrigScreen
## Mehrspieler „SPIELER-SETUP“ (Text 2551) nach MODELS\player screen.4ds (hd2.exe 0x682AB7–0x6834D1,
## docs/re_notes_menus_equipment.md): Seitenwahl (Flaggen + Kästchen), Klassen-/Vorlagenliste aus mp.json
## (ALLOWEDPRESETS, Texte 6500–6520), Ausrüstungsplätze der Vorlage, auf der Karte erlaubte Gegenstände
## (ALLOWEDITEMS), Soldaten-Status, Chat, Figurwahl „Militärische Kräfte“ (T2538: MP-Figuren
## „MP 1…27“ + optionale lokale Helden am Listenende (Net.heroes()), Porträtstreifen mit Bildlauf scroll11,
## 3D-Vorschau 3Dview mit Gesichtstextur).
## Anbindung an Net: local_class / request_class / request_loadout / request_team / request_figure / send_chat.
## Einzel-Ausrüstung (MpLoadout): erlaubte Gegenstände per Doppelklick, Klick auf Platz oder Ziehen an den Soldaten,
## Doppelklick/„Ablegen“/Zurückziehen nimmt sie ab; Gewicht/Raum wie im Original (Überladung 2023, Lager 9522).
## Klassen-Vorlagen bleiben als Vorlage; dazu je Seite 6 eigene Vorlagen (user_presets_orig.def, SPEICHERN/UMBENENNEN).
## PUNKTESTAND schaltet die rechte Seite auf den Punktestand um, Knopf dann „SOLDATEN-STATUS ANZEIGEN“ (T2530;
## Umschalter zweier Felder mit Knopftext 2529/2530 in hd2.exe 0x685EE0 [P Zuordnung]).

signal accepted
signal back_requested

const CLASS_SUFFIX := ["gunner", "sniper", "rifleman", "heavy gunner", "assault gunner"]
const ITEM_BOXES := ["item08", "item11", "item13", "item15", "item09", "item10", "item12", "item14"]
## Kategorie-Liste der erlaubten Gegenstände (soldier type01) – dieselben Gruppen wie im Inventar
const ITEM_CATS := [2719, 2720, 2721, 2722, 2723, 2724, 2725]

var map_id := ""
var mp: Dictionary = {}          ## Spielstil der Karte aus mp.json (presets, allowed_items)
var team_pref := -1              ## -1 automatisch, Soldier.TEAM_ALLIED / TEAM_AXIS
var cls := 2
var item_cat := 0
var item_ofs := 0
var sel_item := -1
var dropdown := ""
var team_chat := false
var respawn_s := 0
var _chat: Array = []            ## [Name, Text, Team]
var _chat_edit: LineEdit
var figure := ""                 ## gewählte Figur (Net.figure_ids), "" = Standard der Seite
var fig_ofs := 0
var preview: SubViewport         ## 3D-Vorschau (Tests)
var preview_model: Node3D
static var _glb_cache := {}
var inv: Dictionary = {}         ## Ausrüstung im SPIELER-SETUP (SAS-Inventar, MpLoadout)
var custom := false              ## vom Spieler verändert (sonst gilt die Klassen-Vorlage des Servers)
var user_sel := -1               ## gewählte eigene Vorlage 0–5 der Seite (−1 = Klasse)
var sel_inv := ""                ## markierter Platz bzw. "item:<ID>" am Soldaten
var right_panel := "status"      ## rechte Seite: "status" (Soldaten-Status/Vorschau) oder "scores" (Punktestand)
var last_msg := ""               ## letzter Hinweis (Tests)
var _rename_edit: LineEdit


func open(map: String, respawn := -1) -> void:
	map_id = map
	setup_stage()
	cls = clampi(int(Net.local_class), 0, Net.CLASS_NAMES.size() - 1)
	var lt = Net.get("local_team")
	if lt != null:
		team_pref = int(lt)
	respawn_s = respawn if respawn >= 0 else int(Net.settings.get("respawn_s", 5))
	figure = String(Net.get("local_figure")) if Net.get("local_figure") != null else ""
	var fid: Array = Net.figure_ids()
	if figure != "" and fid.has(figure):
		fig_ofs = clampi(fid.find(figure) - 1, 0, maxi(fid.size() - 4, 0))
	mp = _load_style(map)
	var own: Dictionary = Net.local_loadout
	if not own.is_empty() and MpLoadout.check(own, allowed_list(), ui_team(), strength(), _heads(own)) == "":
		inv = own.duplicate(true)
		custom = true
		_inv_side = _side()
	else:
		reset_to_class()
	if Net.has_signal("chat_received"):
		Net.connect("chat_received", _on_chat)
	if Net.has_signal("players_updated"):
		Net.players_updated.connect(_on_players)
	build()


## Spielstil (Presets, erlaubte Gegenstände) der Karte; Arena-Karten ohne MP-Daten: erste Original-MP-Karte
static func _load_style(map: String) -> Dictionary:
	var ids: Array = [map] + Game.MP_MAPS
	for id in ids:
		var folder := String(Game.MISSIONS.get(id, {}).get("orig", "")).to_lower()
		if folder == "":
			continue
		var d = LsRuntime._read_json(OrigLevel.cache_root() + "/" + folder + "/mp.json")
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var st: Array = d.get("game_styles", [])
		if not st.is_empty() and not (st[0].get("presets", []) as Array).is_empty():
			return st[0]
	return {}


func _t(id: int, fb: String) -> String:
	return SAS.text(id, fb)


# --- Einzel-Ausrüstung --------------------------------------------------------------------------------
## Seite für Lager/Prüfung (Deathmatch: Seite der Figur bzw. Wunschseite)
func ui_team() -> int:
	return Soldier.TEAM_AXIS if _side() == "axis" else Soldier.TEAM_ALLIED


## Freigabeliste der Karte (leer = unbeschränkt, wie die Server-Prüfung)
func allowed_list() -> Array:
	return MpLoadout.map_allowed(map_id)


func strength() -> float:
	return MpLoadout.strength_of(figure)


func _heads(i: Dictionary) -> Array:
	return MpLoadout.heads_for(i, mp.get("presets", []), _side())


## Ausrüstung = Klassen-Vorlage der Seite (an das Lager angepasst)
func reset_to_class() -> void:
	inv = MpLoadout.from_preset(class_preset(cls), allowed_list(), ui_team())
	custom = false
	user_sel = -1
	sel_inv = ""
	_inv_side = _side()


var _inv_side := ""               ## Seite, für die inv zusammengestellt ist (Seitenwechsel → Klassen-Vorlage)


func _say(t: String) -> void:
	last_msg = t
	if t != "":
		Events.say(t, 3.0)


## Gegenstand an den Soldaten (Doppelklick im Lager, Klick auf Platz, Ziehen); want = Platz/"items"/""
func give_item(id: int, want := "") -> bool:
	var err := MpLoadout.give(inv, id, allowed_list(), ui_team(), strength(), want)
	if err != "":
		click_sound()
		_say(err)
		build()
		return false
	custom = true
	sel_inv = ""
	click_sound()
	build()
	return true


## Platz bzw. ein Stück aus Taschen/Rucksack ablegen
func take_item(what: String) -> void:
	MpLoadout.take(inv, what.trim_prefix("item:"))
	custom = true
	sel_inv = ""
	click_sound()
	build()


func block() -> int:
	return MpLoadout.preset_block(ui_team(), _deathmatch())


## Eigene Vorlage j wählen: leer → nur markieren (SPEICHERN belegt sie); belegt → anwenden (nur Lagerbestand,
## fehlende Gegenstände: Hinweis 9522 wie im Original)
func pick_user_preset(j: int) -> void:
	user_sel = j
	dropdown = ""
	var p: Dictionary = MpLoadout.user_presets(block())[j]
	if not MpLoadout.user_preset_empty(p):
		var want := MpLoadout.user_preset_inventory(p)
		var al := allowed_list()
		var err := MpLoadout.check(want, al, ui_team(), strength(), _heads(want))
		if err == "":
			inv = want
		else:
			inv = SAS.new_inventory()
			for k in ["uniform", "back", "hands", "shoulder"]:
				if int(want.get(k, -1)) >= 0:
					MpLoadout.give(inv, int(want[k]), al, ui_team(), strength(), k)
			for e in want.get("items", []):
				for n in int(e[1]):
					if MpLoadout.give(inv, int(e[0]), al, ui_team(), strength(), "items") != "":
						break
			_say(_t(9522, "Gegenstand steht nicht in der Liste der verfügbaren Gegenstände."))
		custom = true
	click_sound()
	build()


## SPEICHERN: aktuelle Ausrüstung in die gewählte eigene Vorlage (hd2.exe 0x687C60)
func save_preset() -> void:
	if user_sel < 0:
		return
	click_sound()
	var p := MpLoadout.save_user_preset(block(), user_sel, inv)
	_say("%s: %s" % [_t(2531, "SPEICHERN"), MpLoadout.user_preset_label(p)])
	build()


## UMBENENNEN: Namenseingabe (≤ 29 Zeichen) für die gewählte eigene Vorlage
func open_rename() -> void:
	if user_sel < 0:
		return
	click_sound()
	var ov := dialog(_t(2532, "UMBENENNEN") + "\n\n\n", [[_t(2013, "OK"), _rename_ok],
		[_t(2506, "ZURÜCK"), func(): pass]])
	ov.name = "RenameDialog"
	_rename_edit = LineEdit.new()
	_rename_edit.name = "RenameInput"
	_rename_edit.max_length = 29
	_rename_edit.text = MpLoadout.user_preset_label(MpLoadout.user_presets(block())[user_sel])
	_rename_edit.position = REF * 0.5 + Vector2(-130, 2)
	_rename_edit.size = Vector2(260, 30)
	_rename_edit.add_theme_color_override("font_color", INK)
	_rename_edit.add_theme_font_size_override("font_size", 15)
	ov.add_child(_rename_edit)
	_rename_edit.grab_focus()
	_rename_edit.select_all()
	_rename_edit.text_submitted.connect(_rename_submit.bind(ov))


func _rename_ok() -> void:
	rename_preset(_rename_edit.text if is_instance_valid(_rename_edit) else "")


func _rename_submit(t: String, ov: Control) -> void:
	ov.queue_free()
	rename_preset(t)


func rename_preset(nm: String) -> void:
	if user_sel < 0 or nm.strip_edges() == "":
		return
	MpLoadout.rename_user_preset(block(), user_sel, nm)
	build()


func _side() -> String:
	var t := team_pref
	if t < 0 and Net.is_online and Net.players.has(Net.my_id()):
		var me: Dictionary = Net.players[Net.my_id()]
		t = int(me.get("next_team", me.get("team", -1)))
	return "axis" if t == Soldier.TEAM_AXIS else "allied"


func _deathmatch() -> bool:
	var m = Game.MISSIONS.get(map_id, {}).get("mp_mode")
	return (Net.is_online and Net.mode() == Net.Mode.DEATHMATCH) or (m != null and int(m) == 0)


## Vorlage (mp.json) der gewählten Klasse und Seite
func class_preset(c: int) -> Dictionary:
	if c < 0 or c >= CLASS_SUFFIX.size():
		return {}
	for p in mp.get("presets", []):
		if String(p.get("side", "")) != _side():
			continue
		var nm := String(p.get("name", "")).to_lower()
		if nm.ends_with(CLASS_SUFFIX[c]) and not (CLASS_SUFFIX[c] == "gunner" and (nm.ends_with("heavy gunner") or nm.ends_with("assault gunner"))):
			return p
	return {}


func class_label(c: int) -> String:
	var p := class_preset(c)
	if not p.is_empty():
		return _t(int(p.get("text_id", 0)), String(p.get("text", Net.CLASS_NAMES[c])))
	return String(Net.CLASS_NAMES[clampi(c, 0, Net.CLASS_NAMES.size() - 1)])


func build() -> void:
	if _inv_side != _side():
		reset_to_class()          # Lager/Uniformen der anderen Seite: zurück zur Klassen-Vorlage
	begin("player screen")
	title(2551, "SPIELER-SETUP", "text_playerarrangement")
	text_at("text_etimated time", _t(2534, "Voraussichtliche Zeit:").strip_edges() + " " + ("%d s" % respawn_s if Net.is_online else "–"), 12)
	text_at("text_warm up", _t(2533, "Respawn-Zeit:") + " %d s" % respawn_s, 12)
	_team_choice()
	text_at("text_equipment", _t(2535, "Soldaten-Ausrüstung:").strip_edges(), 15)
	_equip_panel()
	_class_box()
	orig_button("brename preset", _t(2532, "UMBENENNEN"), open_rename, user_sel >= 0, "RenamePreset", 13)
	orig_button("bsave preset", _t(2531, "SPEICHERN"), save_preset, user_sel >= 0, "SavePreset", 13)
	_allowed_items()
	# rechts: Figur, Status (bzw. Punktestand), Chat
	text_at("text_draft", _t(2538, "Militärische Kräfte").strip_edges(), 15)
	_figures()
	if right_panel == "scores" and Net.is_online:
		_scores_panel()
	else:
		text_at("text_selected soldier stats", _t(2537, "Soldaten-Status:").strip_edges(), 15)
		var st_idx: int = int(figure.substr(3)) if figure.begins_with("mp:") else 30
		stat_rows(SAS.store(st_idx).get("stats", {}), 3)
		_preview()
	_chat_box()
	orig_button("baccept", _t(2505, "AKZEPTIEREN"), accept, true, "Accept")
	orig_button("bgame info", _t(2530, "SOLDATEN-STATUS ANZEIGEN") if right_panel == "scores" else _t(2508, "PUNKTESTAND"),
		toggle_scores, Net.is_online, "Scores", 14 if right_panel == "scores" else 17)
	orig_button("bback", _t(2506, "ZURÜCK"), func(): back_requested.emit(), true, "Back")
	if dropdown == "class":
		_class_list()
	elif dropdown == "items":
		_cat_list()
	_setup_drag()


# --- Ziehen und Ablegen (wie Ausrüstungsbildschirm sas_screen.gd) --------------------------------------
## Quellen: Lager „Allowed<ID>“, Plätze „Slot_<Platz>“, Taschen/Rucksack „Inv<ID>“; Ziele: Plätze, „Slot_drop“,
## Inventarfläche „InvArea“, Lagerfläche „StoreArea“
func _setup_drag() -> void:
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
		elif h.begins_with("Allowed") and h.substr(7).is_valid_int():
			src = {"from": "store", "id": int(h.substr(7))}
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
		var want := MpLoadout.slot_of(int(data["id"]))
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
	if not _can_drop(Vector2.ZERO, data, target):
		return false
	var id := int(data["id"])
	var from := String(data["from"])
	sel_item = -1
	sel_inv = ""
	if from == "store":
		return give_item(id, "items" if target == "inv" else target.substr(5))
	if from == "slot":
		var slot := String(data["slot"])
		if target in ["store", "drop"]:
			take_item(slot)
			return true
		if target == "inv":
			var trial := inv.duplicate(true)
			trial[slot] = -1
			SAS.add_item(trial, id, 1)
			if SAS.overloaded(trial, strength()):
				_say(SAS.text(2023, "Ein Soldat ist überladen, bitte Gegenstand ablegen."))
				build()
				return false
			inv = trial
		else:
			var other := target.substr(5)
			var o := int(inv.get(other, -1))
			inv[other] = id
			inv[slot] = o
		custom = true
		click_sound()
		build()
		return true
	if target in ["store", "drop"]:
		take_item("item:%d" % id)
		return true
	SAS.remove_item(inv, id, 1)
	if give_item(id, target.substr(5)):
		return true
	SAS.add_item(inv, id, 1)
	build()
	return false


## Seitenwahl: Kästchen leer = automatisch; Häkchen = gewünschte Seite (yesnormal); Spielerzahlen je Seite
func _team_choice() -> void:
	var dm := _deathmatch()
	var counts := [0, 0]
	for p in Net.players.values():
		var t := int(p.get("team", -1))
		if t in [Soldier.TEAM_ALLIED, Soldier.TEAM_AXIS]:
			counts[0 if t == Soldier.TEAM_ALLIED else 1] += 1
	for side in [["allies", "01", Soldier.TEAM_ALLIED, "text_allied00", 0], ["axis", "00", Soldier.TEAM_AXIS, "text_axis00", 1]]:
		var v := draw_frame(side[0])
		var box: String = ("yesnormal" if team_pref == side[2] else "emptynormal") + side[1]
		var bv := draw_frame(box, rect("emptynormal" + side[1]).position - rect(box).position)
		if dm:
			v.modulate = Color(1, 1, 1, 0.45)
			bv.modulate = Color(1, 1, 1, 0.45)
		text_at(side[3], "%d" % counts[side[4]], 13, HORIZONTAL_ALIGNMENT_CENTER)
		if not dm:
			var team: int = side[2]
			hit(rect("emptynormal" + side[1]).merge(rect(side[0])), func(_d: bool):
				click_sound()
				team_pref = -1 if team_pref == team else team
				build(), "Side_" + String(side[0]))


## PUNKTESTAND ↔ SOLDATEN-STATUS ANZEIGEN (rechte Seite)
func toggle_scores() -> void:
	click_sound()
	right_panel = "status" if right_panel == "scores" else "scores"
	build()


## Punktestand im Bereich Soldaten-Status/Vorschau (Net.board_text: Spieler, Rang, Abschüsse, Punkte, Ping)
func _scores_panel() -> void:
	text_at("text_selected soldier stats", _t(2508, "PUNKTESTAND").strip_edges(), 15)
	# Fläche unter der Überschrift bis zum Chat, über Soldaten-Status und 3D-Vorschau (nicht über die Figurenleiste)
	var hdr := rect("text_selected soldier stats", Rect2(534, 290, 240, 20))
	var right := rect("3Dview", Rect2(783, 93, 202, 350)).end.x
	var bottom := rect("text_chat", Rect2(534, 500, 100, 20)).position.y - 6.0
	var r := Rect2(hdr.position.x, hdr.end.y + 4.0, right - hdr.position.x, maxf(bottom - hdr.end.y - 4.0, 40.0))
	var txt: String = Net.board_text() if Net.has_method("board_text") else ""
	var l := label(r.grow(-4), txt, 11, INK, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true)
	l.name = "ScoresText"


func _class_box() -> void:
	draw_frame("soldier type")
	var head_txt := class_label(cls)
	if user_sel >= 0:
		head_txt = MpLoadout.user_preset_label(MpLoadout.user_presets(block())[user_sel])
	elif custom:
		head_txt += " *"
	text_at("header", head_txt, 15).name = "ClassHeader"
	hit(rect("header"), func(_d: bool): _toggle("class"), "ClassOpen")
	orig_button("cbdown01", "", func(): _toggle("class"), true, "ClassArrow")


func _toggle(which: String) -> void:
	click_sound()
	dropdown = "" if dropdown == which else which
	build()


func _class_list() -> void:
	draw_frames(["shadow01", "listbox"])
	var r := rect("text00", Rect2(84, 231, 307, 207))
	# Klassen-Vorlagen (ALLOWEDPRESETS) und eigene Vorlagen der Seite („… user preset1–6“, Leer 1…6)
	var ups: Array = MpLoadout.user_presets(block())
	var n: int = Net.CLASS_NAMES.size() + ups.size()
	var row_h := minf(22.0, (r.size.y - 4.0) / float(n))
	var fs: int = 14 if row_h >= 18.0 else 11
	for c in Net.CLASS_NAMES.size():
		var lr := Rect2(r.position + Vector2(0, row_h * c), Vector2(r.size.x, row_h - 1))
		label(lr, class_label(c), fs, INK_RED if c == cls and user_sel < 0 else INK)
		hit(lr, _pick_class.bind(c), "Class%d" % c)
	for j in ups.size():
		var lr := Rect2(r.position + Vector2(0, row_h * (Net.CLASS_NAMES.size() + j)), Vector2(r.size.x, row_h - 1))
		var up: Dictionary = ups[j]
		var col: Color = INK_RED if j == user_sel else (INK_DISABLED if MpLoadout.user_preset_empty(up) else INK)
		label(lr, MpLoadout.user_preset_label(up), fs, col)
		hit(lr, func(_d: bool): pick_user_preset(j), "UserPreset%d" % j)


func _pick_class(_d: bool, c: int) -> void:
	click_sound()
	cls = c
	dropdown = ""
	reset_to_class()
	build()


## Ausrüstung des Soldaten (bearbeitbar): Plätze Hände/Schulter/Kopf/Uniform/Rücken, Taschen + Rucksack als
## Original-Spalten (Stapel der Reihe nach in die Taschen bis 12 Raumeinheiten, Rest Rucksack), Gewicht/Raum-Balken,
## Überladung (overload). Klick auf Platz mit markiertem Lager-Gegenstand = dorthin; Doppelklick = ablegen.
const SLOT_FRAMES := {"hands": ["hands", "text_hands", "selhands"], "shoulder": ["shoulder", "text_shoulder", "selshoulder"],
	"head": ["head", "text_head", "selhead"], "uniform": ["uniform", "text_uniform", "seluniform"], "back": ["back", "text_back", "selbck"]}
const POCKET_BOXES := ["item00", "item01", "item02", "item03"]
const PACK_BOXES := ["item04", "item05", "item06", "item07"]
var pocket_ofs := 0
var pack_ofs := 0


func split_columns(i: Dictionary) -> Array:
	return SAS.split_items(i)     # B-018: gleiche Aufteilung wie SAS-/Ingame-Inventar (Munition zuerst in den Rucksack)


func _equip_panel() -> void:
	draw_frames(["table01", "hlcpctcr02", "hlcpctcr00", "hlcpctcr01"])
	var w := SAS.inv_weight(inv)
	var stg := strength()
	bar("hlcpct02", w / maxf(stg, 1.0))
	if SAS.overloaded(inv, stg):
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
	text_at("text_cpcty", "%s: %.1f / %d Kg" % [_t(2730, "Gewicht"), w, int(stg)], 11).name = "WeightText"
	text_at("text_hlstrscap", "%d%%" % roundi(100.0 * pocket_used / SAS.POCKET_SPACE), 11, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("text_bkpckcap", ("%d%%" % roundi(100.0 * pack_used / pack_cap)) if pack_cap > 0.0 else _t(2727, "KEINE").strip_edges(),
		11, HORIZONTAL_ALIGNMENT_CENTER)
	for slot in SLOT_FRAMES:
		var f: Array = SLOT_FRAMES[slot]
		text_at(f[1], _t(SAS.SLOT_TEXT[slot], slot), 11, HORIZONTAL_ALIGNMENT_CENTER)
		_box(f[0], int(inv.get(slot, -1)))
		hit(rect(f[0]), _slot_click.bind(slot), "Slot_" + slot, true)
	text_at("text_drop", _t(2712, "Ablegen"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	_box("drop", -1)
	hit(rect("drop"), _drop_click, "Slot_drop", true)
	text_at("text_holsters", _t(2716, "Taschen"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	text_at("text_backpack", _t(2717, "Rucksack"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	pocket_ofs = clampi(pocket_ofs, 0, maxi((cols[0] as Array).size() - 4, 0))
	pack_ofs = clampi(pack_ofs, 0, maxi((cols[1] as Array).size() - 4, 0))
	hit(rect("item00").merge(rect("item07")), _inv_area_click, "InvArea", true)
	_column(cols[0], POCKET_BOXES, pocket_ofs)
	_column(cols[1], PACK_BOXES, pack_ofs)
	draw_frames(["scroll13", "normal13", "scroll14", "normal14"])
	orig_button("barrow up23", "", _scroll_col.bind("pockets", -1), pocket_ofs > 0, "PocketsUp")
	orig_button("barrow down23", "", _scroll_col.bind("pockets", 1), pocket_ofs < (cols[0] as Array).size() - 4, "PocketsDown")
	orig_button("barrow up24", "", _scroll_col.bind("pack", -1), pack_ofs > 0, "PackUp")
	orig_button("barrow down24", "", _scroll_col.bind("pack", 1), pack_ofs < (cols[1] as Array).size() - 4, "PackDown")
	# Ziel-Markierungen für den im Lager markierten Gegenstand bzw. Auswahlrahmen am Soldaten
	if sel_item >= 0 and sel_inv == "":
		var target := MpLoadout.slot_of(sel_item)
		if target == "hands" and int(inv.get("hands", -1)) >= 0:
			draw_frame("selshoulder")
		if target != "" and SLOT_FRAMES.has(target):
			draw_frame(SLOT_FRAMES[target][2])
		elif target == "":
			draw_frames(["selholsters", "selbackpack"])
	elif SLOT_FRAMES.has(sel_inv):
		draw_frame(SLOT_FRAMES[sel_inv][2])
	if sel_inv != "":
		draw_frame("seldrop")


func _column(entries: Array, boxes: Array, ofs: int) -> void:
	for i in boxes.size():
		var k := ofs + i
		var id: int = int(entries[k][0]) if k < entries.size() else -1
		_box(boxes[i], id, int(entries[k][1]) if k < entries.size() else 0)
		if id >= 0:
			if sel_inv == "item:%d" % id:
				draw_frame("selhands", rect(boxes[i]).position - rect("hands").position)
			hit(rect(boxes[i]), _inv_item_click.bind(id), "Inv%d" % id, true)


func _scroll_col(which: String, d: int) -> void:
	if which == "pockets":
		pocket_ofs += d
	else:
		pack_ofs += d
	build()


func _slot_click(dbl: bool, slot: String) -> void:
	if sel_item >= 0 and sel_inv == "" and not dbl:
		var id := sel_item
		sel_item = -1
		give_item(id, slot)
		return
	if dbl:
		take_item(slot)
		return
	click_sound()
	sel_inv = slot if int(inv.get(slot, -1)) >= 0 else ""
	build()


func _inv_item_click(dbl: bool, id: int) -> void:
	if dbl:
		take_item("item:%d" % id)
		return
	click_sound()
	sel_item = -1
	sel_inv = "item:%d" % id
	build()


## Klick in die Taschen/Rucksack-Fläche mit markiertem Lager-Gegenstand: ins Inventar
func _inv_area_click(_dbl: bool) -> void:
	if sel_item >= 0 and sel_inv == "":
		give_item(sel_item, "items")


## „Ablegen“: markierten Gegenstand vom Soldaten nehmen
func _drop_click(_dbl: bool) -> void:
	if sel_inv != "":
		take_item(sel_inv)


func _box(frame: String, id: int, count := 0, shift := Vector2.ZERO) -> void:
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
		label(Rect2(r.position + Vector2(4, r.size.y - 16), Vector2(r.size.x - 8, 14)), "%d" % count, 12, INK, HORIZONTAL_ALIGNMENT_RIGHT)


## Lager der Karte für die eigene Seite nach Kategorie (ALLOWEDITEMS + Munition der Waffen aus ammo_num), 4×2 Felder
func allowed_in_category() -> Array:
	var out: Array = []
	var src: Array = allowed_list()
	if src.is_empty():
		src = mp.get("allowed_items", [])
	var st: Dictionary = Net.storage_of(src, ui_team(), true)
	var ids: Array = st.keys()
	ids.sort()
	for k in ids:
		var id := int(k)
		if id < 0 or int(st[k]) <= 0:
			continue
		var c: int = 3 if SAS.item_kind(id) == "ammo" else SAS.item_category(id)
		# ITEM_CATS: 0 leicht, 1 mittel, 2 schwer, 3 Magazine, 4 Sprengstoffe, 5 Uniformen, 6 Ausrüstung
		var ui: int = c if c <= 2 else (3 if SAS.item_kind(id) == "ammo" else c + 1)
		if ui == item_cat:
			out.append(id)
	if item_cat > 2:
		return out
	# Waffengruppen: Raster spaltenweise (oben Waffe, darunter ihre Munition – Vorgabe Auftraggeber wie im
	# Ausrüstungsbildschirm); Waffe ohne Munition im Lager → leeres Feld darunter
	var paired: Array = []
	for w in out:
		paired.append(w)
		var am := SAS.ammo_of(int(w))
		paired.append(am if am >= 0 and int(st.get(am, 0)) > 0 and am != int(w) else -1)
	return paired


func _allowed_items() -> void:
	draw_frames(["table22", "soldier type01"])
	text_at("header01", _t(ITEM_CATS[item_cat], ""), 15).name = "ItemsHeader"
	hit(rect("header01"), func(_d: bool): _toggle("items"), "ItemsOpen")
	orig_button("cbdown03", "", func(): _toggle("items"), true, "ItemsArrow")
	var ids := allowed_in_category()
	item_ofs = clampi(item_ofs, 0, maxi(((ids.size() + 1) / 2 - 4) * 2, 0))
	var al := allowed_list()
	var area := rect(ITEM_BOXES[0])
	for b in ITEM_BOXES:
		area = area.merge(rect(b))
	hit(area, func(_d: bool): pass, "StoreArea", true)
	for i in ITEM_BOXES.size():
		var col := i % 4
		var row := i / 4
		var k := item_ofs + col * 2 + row
		var id: int = int(ids[k]) if k < ids.size() else -1
		var left: int = MpLoadout.remaining(inv, al, ui_team(), id) if id >= 0 else 0
		_box(ITEM_BOXES[i], id, left if not al.is_empty() else 0)
		if id >= 0:
			if id == sel_item:
				draw_frame("sel" + ITEM_BOXES[i])
			hit(rect(ITEM_BOXES[i]), _allowed_click.bind(id), "Allowed%d" % id, true)
	orig_button("barrow up25", "", _scroll_items.bind(-2), item_ofs > 0, "ItemsLeft")
	orig_button("barrow down25", "", _scroll_items.bind(2), item_ofs + 8 < ids.size(), "ItemsRight")
	if sel_item >= 0:
		var lines: Array = [SAS.item_label(sel_item), "%s : %.2f kg" % [_t(2730, "Gewicht"), SAS.weight(sel_item)]]
		var wd: Dictionary = SAS._weapons.get(sel_item, {})
		if not wd.is_empty():
			lines.append("%s : %d" % [_t(2731, "Anzahl der Kugeln im Magazin"), int(wd.get("magazine", 0))])
			lines.append("%s : %.2f m/s" % [_t(2732, "Schussgeschwindigkeit"), float(wd.get("muzzle_velocity", 0.0))])
		if not al.is_empty():
			lines.append("Lager : %d" % maxi(MpLoadout.remaining(inv, al, ui_team(), sel_item), 0))
		text_at("text_weapons info", "\n".join(lines), 12, HORIZONTAL_ALIGNMENT_LEFT, INK, true)
	if last_msg != "":
		text_at("text_weapons info", "\n\n\n\n\n" + last_msg, 11, HORIZONTAL_ALIGNMENT_LEFT, INK_RED, true).name = "SetupMsg"


func _scroll_items(d: int) -> void:
	item_ofs += d
	build()


## Klick markiert (Ziel-Markierung am Soldaten), Doppelklick gibt den Gegenstand an den Soldaten
func _allowed_click(dbl: bool, id: int) -> void:
	sel_inv = ""
	if dbl:
		sel_item = id
		give_item(id)
		return
	click_sound()
	sel_item = id
	build()


func _cat_list() -> void:
	draw_frames(["shadow02", "listbox01"])
	var r := rect("text01", Rect2(84, 532, 307, 193))
	for i in ITEM_CATS.size():
		var lr := Rect2(r.position + Vector2(0, 24 * i), Vector2(r.size.x, 22))
		label(lr, _t(ITEM_CATS[i], ""), 14, INK_RED if i == item_cat else INK)
		hit(lr, func(_d: bool):
			item_cat = i
			item_ofs = 0
			dropdown = ""
			build(), "ItemCat%d" % i)


## Figurwahl „Militärische Kräfte“ (photo03 + table13–15, roter selector, Bildlauf scroll11): MP-Figuren
## „MP 1…27“ (HumanStore 30–56) und – nur mit lokaler Datei – Helden je Armee mit eigenem Modell (Net.heroes()).
## Klick wählt (Held: zugleich seine Armee, außer Deathmatch); AKZEPTIEREN überträgt die Wahl (Net.request_figure).
func _figures() -> void:
	var ids: Array = Net.figure_ids()
	fig_ofs = clampi(fig_ofs, 0, maxi(ids.size() - 4, 0))
	var slots := ["photo03", "table13", "table14", "table15"]
	var p0 := rect("photo03").position
	for i in slots.size():
		var k := fig_ofs + i
		if k >= ids.size():
			break
		var fid: String = ids[k]
		var r := rect(slots[i])
		draw_frame("photo03", r.position - p0, {"X_F_001.BMP": figure_portrait(fid)})
		if fid == figure:
			draw_frame("selector", r.position - p0)
		hit(r, _pick_figure.bind(fid), "Figure_" + fid.replace(":", "_"))
	_scroll_knob(float(fig_ofs), float(maxi(ids.size() - 4, 0)))
	orig_button("barrow up11", "", _scroll_figures.bind(-1), fig_ofs > 0, "FigLeft")
	orig_button("barrow down11", "", _scroll_figures.bind(1), fig_ofs < ids.size() - 4, "FigRight")


func _scroll_knob(pos: float, mx: float) -> void:
	draw_frame("scroll11")
	var b := rect("sliderbase11")
	var k := rect("normal110")
	var frac: float = 0.0 if mx <= 0.0 else clampf(pos / mx, 0.0, 1.0)
	draw_frame("normal110", Vector2(b.position.x + (b.size.x - k.size.x) * frac - k.position.x, 0))


func _scroll_figures(d: int) -> void:
	click_sound()
	fig_ofs += d
	build()


func _pick_figure(_dbl: bool, fid: String) -> void:
	click_sound()
	figure = "" if figure == fid else fid
	var side := Net.figure_side(figure)
	if side != "" and not _deathmatch():
		team_pref = Soldier.TEAM_AXIS if side == "axis" else Soldier.TEAM_ALLIED
	build()


## Porträt (54×79) der Figur: MP-Figur = Original-Porträt x_f_NNN; Held = lokales Foto (user_assets, nie im
## Repository) bzw. Ausschnitt der Gesichtstextur
func figure_portrait(fid: String) -> Texture2D:
	if fid.begins_with("mp:"):
		return tex_file(SAS.portrait_path(int(fid.substr(3))))
	var photo := ProjectSettings.globalize_path("res://user_assets/hero_photo.jpg")
	if FileAccess.file_exists(photo):
		return tex_file(photo)
	var face := Net.figure_face(fid)
	if face == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = face
	var sz := face.get_size()
	at.region = Rect2(sz.x * 0.36, sz.y * 0.08, sz.x * 0.28, sz.y * 0.8)
	return at


## 3D-Vorschau (3Dview) der gewählten Figur: Originalfigur (orig_cache/characters) mit Gesichtstextur, dreht sich;
## darunter Name der Figur und Seite.
func _preview() -> void:
	var r := rect("3Dview", Rect2(783, 93, 202, 350))
	var side := _side()
	var fid: String = figure
	var name_txt: String = Net.figure_name(fid) if fid != "" else _t(2538, "Militärische Kräfte").strip_edges()
	var svc := SubViewportContainer.new()
	svc.name = "Preview3D"
	svc.position = r.position
	svc.size = r.size - Vector2(0, 24)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(svc)
	preview = SubViewport.new()
	preview.own_world_3d = true
	preview.transparent_bg = true
	preview.size = Vector2i(int(svc.size.x), int(svc.size.y))
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(preview)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 2.9)
	cam.fov = 40.0
	preview.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	preview.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.65)
	env.environment.ambient_light_energy = 0.8
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	preview.add_child(env)
	preview_model = _character(Net.figure_model(fid, side) if fid != "" else ("ge01a" if side == "axis" else "en01"))
	if preview_model:
		var holder := Node3D.new()
		holder.name = "Turntable"
		preview.add_child(holder)
		holder.add_child(preview_model)
		if fid != "":
			var f2 := fid
			if fid.begins_with("hero:") and Net.figure_side(fid) != side:
				f2 = "hero:" + side
			Net.apply_face(preview_model, Net.figure_face(f2))
		var ap := preview_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for a in ap.get_animation_list():
				if String(a).to_lower().contains("idle"):
					ap.play(a)
					break
	else:
		label(Rect2(r.position + Vector2(6, 120), Vector2(r.size.x - 12, 60)), "(Originalfiguren fehlen: export_characters.py)", 11,
			INK, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, true)
	label(Rect2(r.position.x, r.end.y - 24, r.size.x, 22), name_txt, 14, INK, HORIZONTAL_ALIGNMENT_CENTER).name = "FigureName"


func _process(delta: float) -> void:
	if _pending_build and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not get_viewport().gui_is_dragging() \
			and not (is_instance_valid(_rename_edit) and _rename_edit.is_inside_tree()):
		_pending_build = false
		build()
	if is_instance_valid(preview):
		var t := preview.get_node_or_null("Turntable") as Node3D
		if t:
			t.rotate_y(delta * 0.6)


## Originalfigur aus orig_cache/characters/<modell>.glb (Kopie aus dem Zwischenspeicher)
static func _character(model: String) -> Node3D:
	var key := model.to_lower()
	if not _glb_cache.has(key):
		var path := "%s/characters/%s.glb" % [OrigLevel.cache_root(), key]
		var n: Node3D = null
		if FileAccess.file_exists(path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			state.base_path = path.get_base_dir()
			if doc.append_from_file(path, state) == OK:
				n = doc.generate_scene(state) as Node3D
		_glb_cache[key] = n
	var src: Node3D = _glb_cache[key]
	return src.duplicate() as Node3D if src else null


func _chat_box() -> void:
	text_at("text_chat", _t(2536, "Chat:").strip_edges(), 15)
	draw_frame("table21")
	var log_r := rect("text02", Rect2(534, 453, 397, 130))
	var lines: Array = []
	for c in _chat.slice(maxi(_chat.size() - 7, 0)):
		lines.append(("(Team) " if bool(c[2]) else "") + "%s: %s" % [c[0], c[1]])
	label(log_r.grow(-4), "\n".join(lines), 12, INK, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM, true).name = "ChatLog"
	draw_frame("normal17")
	_chat_edit = LineEdit.new()
	_chat_edit.name = "ChatInput"
	var ir := rect("normal17", Rect2(534, 583, 363, 33))
	_chat_edit.position = ir.position + Vector2(6, 2)
	_chat_edit.size = ir.size - Vector2(12, 4)
	_chat_edit.flat = true
	_chat_edit.add_theme_color_override("font_color", INK)
	_chat_edit.add_theme_font_size_override("font_size", 14)
	_chat_edit.editable = Net.is_online and Net.has_method("send_chat")
	_chat_edit.text_submitted.connect(func(t: String):
		if t.strip_edges() != "" and Net.has_method("send_chat"):
			Net.call("send_chat", t.strip_edges(), team_chat)
		_chat_edit.clear())
	stage.add_child(_chat_edit)
	var tb := "xallnormal" if team_chat else "allnormal"
	draw_frame(tb, rect("allnormal").position - rect(tb).position)
	hit(rect("allnormal"), func(_d: bool):
		team_chat = not team_chat
		build(), "ChatTeam")


func _on_players() -> void:
	if is_inside_tree():
		_rebuild_soon()


func _on_chat(sender: String, t: String, team_only: bool) -> void:
	_chat.append([sender, t, team_only])
	if is_inside_tree():
		_rebuild_soon()


## Netz-Aktualisierungen (Spielerliste, Chat) bauen den Bildschirm neu – nie mitten in einem Mausklick/Ziehen
## (sonst geht das Loslassen an ein verworfenes Feld verloren), sondern erst nach dem Loslassen
var _pending_build := false


func _rebuild_soon() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or get_viewport().gui_is_dragging() or \
			(is_instance_valid(_rename_edit) and _rename_edit.is_inside_tree()):
		_pending_build = true
	else:
		build()


## AKZEPTIEREN: Klasse/Seite an Net (vor dem Beitritt: local_class/local_team; im Spiel: request_class/request_team)
func accept() -> void:
	Net.local_class = cls
	# Einzel-Ausrüstung nur, wenn verändert bzw. eigene Vorlage (sonst Klassen-Vorlage des Servers)
	var err: String = MpLoadout.check(inv, allowed_list(), ui_team(), strength(), _heads(inv)) if custom else ""
	if err != "":
		_say(err)
		build()
		return
	Net.request_figure(figure)
	if Net.get("local_team") != null:
		Net.set("local_team", team_pref)
	if Net.is_online:
		if Net.has_method("request_class"):
			Net.call("request_class", cls)
		if team_pref >= 0 and Net.has_method("request_team"):
			Net.call("request_team", team_pref)
	# nach Figur (Traglast) und Seite (Lager der Seite) – gleicher zuverlässiger Kanal, Reihenfolge bleibt erhalten
	Net.request_loadout(inv.duplicate(true) if custom else {})
	accepted.emit()
