class_name IngameInventory
extends CanvasLayer
## Ingame-Inventar 1:1 nach dem Original (MODELS\gameinterface.4ds, Frame „inventory“; Builder hd2.exe 0x4A0EE0,
## Anzeige 0x4A3920, Öffnen 0x49DE90/0x4A4380, Füllen 0x4A26D0; docs/re_notes_ingame_inventory.md):
##   oben `items00` = eigenes Inventar (Hände, Schulter, Kopf, Uniform, Rücken, Ablegen, Taschen item000–030,
##   Rucksack item040–070, Gewicht „%d/%d kg“), unten `items01` = durchsuchter Körper bzw. ohne zweites Inventar
##   `skills` (Soldatenwerte). Laufzeitlage SetPos(0.178, −0.333) = linke obere Bildschirmecke (tools/
##   _menu_export_ingame_inv.py -> orig_cache/ui/menu/layout/ingame inventory.json).
## Bedienung: Ziehen und Ablegen (rote Ziel-Markierungen sel*), Klick wählt / Klick aufs Ziel verschiebt,
## Doppelklick nimmt bzw. legt in die Hände [P], Rechtsklick = Beschreibung (`description`), „Ablegen“ wirft weg.
## Taste I bzw. Esc schließt. Das Spiel läuft weiter (Original: kein Pausenaufruf beim Öffnen [P]); Eingaben
## gehen an das Inventar (kein Feuern/Umsehen, Maus sichtbar). Logik: FieldInventory (Mehrspieler per Server).

signal closed

## Bühne links oben (das Original-Inventar liegt am linken Bildrand), Maßstab wie das 4:3-HUD
class InvScreen extends OrigScreen:
	func _fit() -> void:
		if not is_instance_valid(stage):
			return
		var k := minf(size.x / REF.x, size.y / REF.y)
		if k <= 0.0:
			return
		stage.scale = Vector2(k, k)
		stage.position = Vector2.ZERO


const ItemOrder := preload("res://src/ui/item_order.gd")
const LAYOUT := "ingame inventory"
## Platz -> Text-ID (Builder 0x4A0F6C: Schleife 0xA96 + i über back, head, drop, hand, uniform, shoulder)
const SLOT_TEXT := {"hands": 2713, "shoulder": 2715, "head": 2711, "uniform": 2714, "back": 2710, "drop": 2712}
const SIDE := {
	"own": {"name": "namexx00", "wt_cr": "allcpctcr00", "wt": "allcpct00", "over": "overload00", "wt_txt": "text_allcpct00",
		"slots": {"hands": ["hands0", "text_hands", "selhands"], "shoulder": ["shoulder0", "text_shoulder", "selshoulder"],
			"head": ["head0", "text_head", "selhead"], "uniform": ["uniform0", "text_uniform", "seluniform"],
			"back": ["bck0", "text_back", "selbck"], "drop": ["drop0", "text_drop", "seldrop"]},
		"pockets": ["item000", "item010", "item020", "item030"], "pack": ["item040", "item050", "item060", "item070"],
		"p_bar": ["hlcpctcr00", "hlcpct00"], "b_bar": ["hlcpctcr01", "hlcpct01"], "p_tab": "hlstrscaptab",
		"b_tab": "bkpckcaptab", "p_txt": "text_hlstrscap", "b_txt": "text_bkpckcap", "sel_p": "selholsters",
		"sel_b": "selbackpack", "p_scroll": ["scroll13", "normal13", "sliderbase12", "barrow up23", "barrow down23"],
		"b_scroll": ["scroll14", "normal14", "sliderbase13", "barrow up24", "barrow down24"]},
	"other": {"name": "namexx01", "wt_cr": "allcpctcr01", "wt": "allcpct01", "over": "overload01", "wt_txt": "text_allcpct01",
		"slots": {"hands": ["hands", "text_hands01", "selhands01"], "shoulder": ["shoulder", "text_shoulder01", "selshoulder01"],
			"head": ["head", "text_head01", "selhead01"], "uniform": ["uniform", "text_uniform01", "seluniform01"],
			"back": ["bck", "text_back01", "selbck01"], "drop": ["drop", "text_drop01", "seldrop01"]},
		"pockets": ["item00", "item01", "item02", "item03"], "pack": ["item04", "item05", "item06", "item07"],
		"p_bar": ["hlcpctcr02", "hlcpct02"], "b_bar": ["hlcpctcr03", "hlcpct03"], "p_tab": "hlstrscaptab01",
		"b_tab": "bkpckcaptab01", "p_txt": "text_hlstrscap01", "b_txt": "text_bkpckcap01", "sel_p": "selholsters01",
		"sel_b": "selbackpack01", "p_scroll": ["scroll15", "normal15", "sliderbase14", "barrow up25", "barrow down25"],
		"b_scroll": ["scroll16", "normal16", "sliderbase15", "barrow up26", "barrow down26"]},
}
## Soldatenwerte (`skills`, Builder 0x4A1AF3: Texte 0xA6E + i = 2670–2676, Überschrift 2667)
const SKILL_ROWS := [["shooting", "text_shooting", "shcpctcr00", "shcpct00", "text_shooting01"],
	["strength", "text_strenght", "stcpctcr00", "stcpct00", "text_strenght01"],
	["health", "text_health", "hecpctcr00", "hecpct00", "text_health01"],
	["endurance", "text_endurance", "encpctcr00", "encpct00", "text_endurance01"],
	["stealth", "text_stealth", "sicpctcr00", "sicpct00", "text_stealth01"],
	["first_aid", "text_first aid", "facpctcr00", "facpct00", "text_first aid01"],
	["lockpick", "text_lockpick", "lpcpctcr00", "lpcpct00", "text_lockpick01"]]

var screen: InvScreen
var me: Soldier
var other: Node
var sel := {}                    ## markierter Gegenstand {side, from, id}
var ofs := {"own": [0, 0], "other": [0, 0]}     ## Bildlauf Taschen/Rucksack
var last_message := ""
var _open := false
var _rev := -1
var _tick := 0.0
var _desc := {}                  ## angezeigte Beschreibung {id, at}


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = InvScreen.new()
	screen.name = "InventoryScreen"
	add_child(screen)
	screen.setup_stage(true)
	if screen.get_child_count() > 0 and screen.get_child(0) is ColorRect:
		(screen.get_child(0) as ColorRect).visible = false       # Spielbild bleibt unverdunkelt (HUD-Element)
	screen.visible = false


func is_open() -> bool:
	return _open


## Öffnen (Taste I: nur eigenes Inventar; Durchsuchen: zweites Inventar = Leiche, Gefangener, Ablagestapel)
func open_for(s: Soldier, oth: Node = null) -> bool:
	if s == null or not is_instance_valid(s) or not s.alive:
		return false
	me = s
	other = oth
	sel = {}
	_desc = {}
	ofs = {"own": [0, 0], "other": [0, 0]}
	_open = true
	screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screen.click_sound()
	refresh()
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	screen.visible = false
	me = null
	other = null
	sel = {}
	_desc = {}
	var ctl := get_parent()
	var blocked: bool = ctl != null and ctl.has_method("ui_blocking") and bool(ctl.call("ui_blocking"))
	if not blocked and not Game.cli.has("autoplay"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	# B-018 Bedienung [P]: Mausrad blättert die Spalte unter dem Zeiger, Entf/Rücktaste legt den markierten Gegenstand
	# ab, Eingabe = Doppelklick-Aktion (Ausrüsten/Ablegen in die Taschen) für den markierten Gegenstand
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var col := _column_at(screen.stage.get_local_mouse_position())
		if not col.is_empty():
			_scroll_by(String(col[0]), int(col[1]), -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not sel.is_empty():
		match (event as InputEventKey).keycode:
			KEY_DELETE, KEY_BACKSPACE:
				if sel["side"] == "own":
					move_item("own", String(sel["from"]), int(sel["id"]), "own", "drop")
					get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				var s0 := sel.duplicate()
				sel = {}
				quick(String(s0["side"]), String(s0["from"]), int(s0["id"]))
				get_viewport().set_input_as_handled()


## Spalte (Seite, 0 Taschen / 1 Rucksack) unter einem Punkt der Bühne, sonst []
func _column_at(at: Vector2) -> Array:
	for side in ["own", "other"]:
		if side == "other" and (other == null or not is_instance_valid(other)):
			continue
		var f: Dictionary = SIDE[side]
		var cols := [f["pockets"], f["pack"]]
		for c in 2:
			var boxes: Array = cols[c]
			var r := screen.rect(boxes[0])
			for b in boxes:
				r = r.merge(screen.rect(b))
			if r.grow(4).has_point(at):
				return [side, c]
	return []


func _process(delta: float) -> void:
	if not _open:
		return
	if not is_instance_valid(me) or not me.alive:
		close()
		return
	if other != null:
		var gone := not is_instance_valid(other)
		if not gone and other is Node3D and (other as Node3D).global_position.distance_to(me.global_position) > FieldInventory.REACH * 2.0:
			gone = true
		if not gone and other is Soldier and (other as Soldier).alive and not other.has_meta("captured"):
			gone = true
		if gone:
			other = null
			sel = {}
			_rev = -1
	_tick -= delta
	if FieldInventory.revision != _rev or _tick <= 0.0:
		refresh()


func side_node(side: String) -> Node:
	return me if side == "own" else other


# --- Aufbau ----------------------------------------------------------------------------------------------

func refresh() -> void:
	if not _open or not is_instance_valid(me):
		return
	_rev = FieldInventory.revision
	_tick = 0.5
	screen.begin(LAYOUT)
	screen.draw_frame("inventory")
	_side("own", me)
	if other != null and is_instance_valid(other):
		_side("other", other)
	else:
		_skills(me)
	_markers()
	_setup_drag()
	if not _desc.is_empty():
		_description(int(_desc["id"]), _desc["at"])


func _name_of(n: Node) -> String:
	if n is Soldier:
		var s := n as Soldier
		if s.has_meta("sas") and SAS.available():
			var st: Dictionary = Game.sas_states().get(str(int(s.get_meta("sas"))), {})
			return SAS.short_name(int(s.get_meta("sas")), int(st.get("rank", 0)))
		return s.soldier_name
	return SAS.text(7025, "Nehmen")


func _side(side: String, node: Node) -> void:
	var f: Dictionary = SIDE[side]
	var inv := FieldInventory.view(node)
	var w := SAS.inv_weight(inv)
	var st := FieldInventory.strength(node)
	screen.draw_frame(f["name"])
	screen.text_at(f["name"], _name_of(node), 13).name = "Name_" + side
	screen.draw_frame(f["wt_cr"])
	if node is Soldier:
		screen.bar(f["wt"], w / maxf(st, 1.0))
		if w > st + 0.001:
			screen.draw_frame(f["over"])
		screen.text_at(f["wt_txt"], "%d/%d kg" % [roundi(w), roundi(st)], 12, HORIZONTAL_ALIGNMENT_RIGHT).name = "Weight_" + side
	for slot in f["slots"]:
		var fr: Array = f["slots"][slot]
		screen.text_at(fr[1], SAS.text(int(SLOT_TEXT[slot]), slot), 11, HORIZONTAL_ALIGNMENT_CENTER)
		var id: int = -1 if slot == "drop" else int(inv.get(slot, -1))
		_item_box(fr[0], id)
		var cb := _on_click.bind(side, slot, id)
		screen.hit(screen.rect(fr[0]), cb, "%s_slot_%s" % [side, slot], true)
	# Taschen + Rucksack (Anzeige wie SasScreen: Taschen bis 12 Raumeinheiten, Rest Rucksack)
	var cols := split_columns(inv)
	var pocket_used := 0.0
	for e in cols[0]:
		pocket_used += SAS.space(int(e[0])) * int(e[1])
	var pack_used := 0.0
	for e in cols[1]:
		pack_used += SAS.space(int(e[0])) * int(e[1])
	var pack_cap := SAS.backpack_space(int(inv.get("back", -1)))
	screen.draw_frame(f["p_bar"][0])
	screen.bar(f["p_bar"][1], pocket_used / SAS.POCKET_SPACE, true)
	screen.draw_frame(f["b_bar"][0])
	screen.bar(f["b_bar"][1], pack_used / pack_cap if pack_cap > 0.0 else 0.0, true)
	screen.text_at(f["p_tab"], SAS.text(2716, "Taschen"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	screen.text_at(f["b_tab"], SAS.text(2717, "Rucksack"), 11, HORIZONTAL_ALIGNMENT_CENTER)
	screen.text_at(f["p_txt"], "%d%%" % roundi(100.0 * pocket_used / SAS.POCKET_SPACE), 10, HORIZONTAL_ALIGNMENT_CENTER)
	screen.text_at(f["b_txt"], ("%d%%" % roundi(100.0 * pack_used / pack_cap)) if pack_cap > 0.0 else SAS.text(2727, "KEINE").strip_edges(),
		10, HORIZONTAL_ALIGNMENT_CENTER)
	var area := screen.rect(f["pockets"][0]).merge(screen.rect(f["pack"][3]))
	screen.hit(area, _on_click.bind(side, "items", -1), "%s_area" % side, true)
	var o: Array = ofs[side]
	o[0] = clampi(int(o[0]), 0, maxi((cols[0] as Array).size() - 4, 0))
	o[1] = clampi(int(o[1]), 0, maxi((cols[1] as Array).size() - 4, 0))
	_column(side, cols[0], f["pockets"], int(o[0]))
	_column(side, cols[1], f["pack"], int(o[1]))
	_scroll(side, 0, f["p_scroll"], (cols[0] as Array).size())
	_scroll(side, 1, f["b_scroll"], (cols[1] as Array).size())


## Reihenfolge ItemOrder: Aufnahmereihenfolge wie im Original (0x7D7390/0x4A2010), Munition direkt unter ihrer
## Waffe in der Liste (Vorgabe Auftraggeber) – gilt für das eigene und das durchsuchte Inventar
static func split_columns(inv: Dictionary) -> Array:
	return SAS.split_items(inv)     # B-014: Rucksackspalte nur mit angelegtem Rucksack


func _column(side: String, entries: Array, boxes: Array, start: int) -> void:
	for i in boxes.size():
		var k := start + i
		var id: int = int(entries[k][0]) if k < entries.size() else -1
		_item_box(boxes[i], id, int(entries[k][1]) if k < entries.size() else 0)
		if id >= 0:
			if sel.get("side", "") == side and sel.get("from", "") == "items" and int(sel.get("id", -1)) == id:
				var f: Dictionary = SIDE[side]
				var hs: Array = f["slots"]["hands"]
				screen.draw_frame(hs[2], screen.rect(boxes[i]).position - screen.rect(hs[0]).position)
			screen.hit(screen.rect(boxes[i]), _on_click.bind(side, "items", id), "%s_item_%d" % [side, id], true)


func _scroll(side: String, col: int, parts: Array, n: int) -> void:
	var mx := maxi(n - 4, 0)
	var pos := int(ofs[side][col])
	screen.draw_frame(parts[0])
	var b := screen.rect(parts[2])
	var k := screen.rect(parts[1])
	var frac: float = 0.0 if mx <= 0 else clampf(float(pos) / float(mx), 0.0, 1.0)
	screen.draw_frame(parts[1], Vector2(0, b.position.y + (b.size.y - k.size.y) * frac - k.position.y))
	screen.orig_button(parts[3], "", _scroll_by.bind(side, col, -1), pos > 0, "%s_up%d" % [side, col])
	screen.orig_button(parts[4], "", _scroll_by.bind(side, col, 1), pos < mx, "%s_down%d" % [side, col])


func _scroll_by(side: String, col: int, d: int) -> void:
	ofs[side][col] = int(ofs[side][col]) + d
	refresh()


## Symbol auf einem Platz (X_BUBBLE = Rahmenring, X_SQUARE = Innenfläche -> ii_*/wi_*-Symbol, items.sav „icon“)
func _item_box(frame: String, id: int, count := 0) -> void:
	var ov := {}
	var icon: String = SAS.item_icon_path(id) if id >= 0 else ""
	if icon != "":
		ov["X_SQUARE.BMP"] = screen.tex_file(icon)
	screen.draw_frame(frame, Vector2.ZERO, ov)
	var r := screen.rect(frame)
	if id >= 0 and icon == "":
		screen.label(r.grow(-3), SAS.item_label(id), 9, OrigScreen.INK, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, true)
	if count > 1:
		screen.label(Rect2(r.position + Vector2(3, r.size.y - 15), Vector2(r.size.x - 6, 13)), "%d" % count, 11,
			OrigScreen.INK, HORIZONTAL_ALIGNMENT_RIGHT)


func _skills(s: Soldier) -> void:
	screen.draw_frame("staty")
	screen.text_at("text_soldier stats", SAS.text(2667, "Soldaten-Optionen:"), 12)
	var stats := soldier_stats(s)
	for i in SKILL_ROWS.size():
		var row: Array = SKILL_ROWS[i]
		screen.text_at(row[1], SAS.text(2670 + i, String(row[0])), 11)
		screen.draw_frame(row[2])
		var v := float(stats.get(row[0], 0.0))
		screen.bar(row[3], v / (1000.0 if row[0] == "health" else 100.0))
		screen.text_at(row[4], "%d" % roundi(v), 11, HORIZONTAL_ALIGNMENT_RIGHT)


## Werte des Soldaten (Kader: Originalwerte, Gesundheit nach aktuellem Zustand; sonst Fähigkeiten der Figur) [P]
static func soldier_stats(s: Soldier) -> Dictionary:
	var out := {}
	if s.has_meta("sas") and SAS.available():
		out = (Game.sas_states().get(str(int(s.get_meta("sas"))), {}).get("stats", {}) as Dictionary).duplicate()
	var hf := clampf(s.health / maxf(s.max_health, 1.0), 0.0, 1.0)
	out["health"] = float(out.get("health", 600.0)) * hf
	for k in [["shooting", s.skill_shooting], ["stealth", s.skill_stealth], ["endurance", s.skill_endurance],
			["first_aid", s.skill_first_aid]]:
		if not out.has(k[0]):
			out[k[0]] = float(k[1]) if float(k[1]) >= 0.0 else 50.0
	if not out.has("strength"):
		out["strength"] = FieldInventory.strength(s)
	if not out.has("lockpick"):
		out["lockpick"] = float(s.get_meta("lockpick", 50.0))
	return out


## Rote Ziel-Markierungen (MM_RED sel*) für den markierten Gegenstand: erlaubte Plätze beider Inventare
func _markers() -> void:
	if sel.is_empty():
		return
	var id := int(sel["id"])
	for side in ["own", "other"]:
		if side == "other" and other == null:
			continue
		var f: Dictionary = SIDE[side]
		if side == sel["side"] and String(sel["from"]) in f["slots"]:
			screen.draw_frame(f["slots"][sel["from"]][2])
		for slot in ["hands", "shoulder", "head", "uniform", "back"]:
			if (side != sel["side"] or slot != sel["from"]) and FieldInventory.accepts(slot, id):
				screen.draw_frame(f["slots"][slot][2])
		if side != sel["side"] or sel["from"] != "items":
			screen.draw_frames([f["sel_p"], f["sel_b"]])
		if side == sel["side"]:
			screen.draw_frame(f["slots"]["drop"][2])


# --- Bedienung ----------------------------------------------------------------------------------------------

func _on_click(dbl: bool, side: String, from: String, id: int) -> void:
	_desc = {}
	if dbl and id >= 0:
		quick(side, from, id)
		return
	if not sel.is_empty():
		var same_spot: bool = sel["side"] == side and sel["from"] == from and (from != "items" or int(sel["id"]) == id)
		var reselect: bool = sel["side"] == side and from == "items" and sel["from"] == "items"
		if not same_spot and not reselect:
			var to: String = "drop" if from == "drop" else from
			move_item(String(sel["side"]), String(sel["from"]), int(sel["id"]), side, to)
			return
		if same_spot:
			sel = {}
			refresh()
			return
	sel = {"side": side, "from": from, "id": id} if id >= 0 else {}
	screen.click_sound()
	refresh()


## Doppelklick [P]: fremder Gegenstand -> eigener passender Platz bzw. Taschen; eigener Platz -> Taschen;
## eigene Tasche -> Hände (Waffen/Hilfsmittel) bzw. Kopf/Uniform/Rücken
func quick(side: String, from: String, id: int) -> String:
	var own := FieldInventory.view(me)
	var to := "items"
	if side == "other":
		var want := SAS.slot_for(id)
		if want == "" and FieldInventory.accepts("hands", id) and int(own["hands"]) < 0:
			want = "hands"
		# B-018: Langwaffe bei belegten Händen auf den freien Rückenplatz statt in die Taschen
		if want == "hands" and int(own["hands"]) >= 0 and FieldInventory.accepts("shoulder", id):
			want = "shoulder"
		if want != "" and int(own.get(want, -1)) < 0 and FieldInventory.accepts(want, id):
			to = want
		return move_item("other", from, id, "own", to)
	# B-018: Rücken ↔ Hände per Doppelklick; Langwaffe aus den Händen auf den freien Rücken
	if from == "shoulder":
		return move_item("own", from, id, "own", "hands")
	if from == "hands" and FieldInventory.accepts("shoulder", id) and int(own["shoulder"]) < 0:
		return move_item("own", from, id, "own", "shoulder")
	if from == "items":
		var want := SAS.slot_for(id)
		if want in ["head", "uniform", "back"]:
			to = want
		elif FieldInventory.accepts("hands", id):
			to = "hands"
		else:
			return ""
	return move_item("own", from, id, "own", to)


## Verschieben (auch für Tests): Seite "own"/"other", Platz bzw. "items", Ziel zusätzlich "drop"
func move_item(src_side: String, from: String, id: int, dst_side: String, to: String) -> String:
	var src := side_node(src_side)
	var dst := side_node(dst_side)
	sel = {}
	if src == null or dst == null or not is_instance_valid(me):
		return "?"
	var res := FieldInventory.request(me, src, from, id, dst, to)
	last_message = res
	if res != "":
		Events.say(res, 2.0)
	else:
		screen.click_sound()
	refresh()
	return res


func _setup_drag() -> void:
	for c in screen.stage.get_children():
		if not c is Control or not c.has_meta("hit"):
			continue
		var h := String(c.get_meta("hit"))
		var parts := h.split("_")
		if parts.size() < 2 or not parts[0] in ["own", "other"]:
			continue
		var side := parts[0]
		var src := {}
		var target := {"side": side, "to": "items"}
		if parts[1] == "slot" and parts.size() >= 3:
			var slot := parts[2]
			target["to"] = slot
			var inv := FieldInventory.view(side_node(side))
			if slot != "drop" and int(inv.get(slot, -1)) >= 0:
				src = {"side": side, "from": slot, "id": int(inv[slot])}
		elif parts[1] == "item" and parts.size() >= 3:
			src = {"side": side, "from": "items", "id": int(parts[2])}
		elif parts[1] != "area":
			continue
		(c as Control).set_drag_forwarding(_drag_from.bind(c, src), _can_drop.bind(target), _drop_on.bind(target))
		# B-018: klare Plätze – Hinweis mit Platzname und Gegenstand unter dem Zeiger [P]
		var tip := ""
		if parts[1] == "slot" and SLOT_TEXT.has(String(target["to"])):
			tip = SAS.text(int(SLOT_TEXT[String(target["to"])]), String(target["to"]))
		if src.has("id"):
			tip = (tip + ": " if tip != "" else "") + SAS.item_label(int(src["id"]))
		(c as Control).tooltip_text = tip
		if src.has("id"):
			(c as Control).gui_input.connect(_right_click.bind(int(src["id"])))


func _drag_from(_at: Vector2, c: Control, src: Dictionary) -> Variant:
	if src.is_empty():
		return null
	var id := int(src["id"])
	var icon := SAS.item_icon_path(id)
	var pv := TextureRect.new()
	pv.texture = screen.tex_file(icon) if icon != "" else null
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.size = Vector2(70, 41) * screen.stage.scale
	pv.modulate = Color(1, 1, 1, 0.8)
	if pv.texture == null:
		var l := Label.new()
		l.text = SAS.item_label(id)
		pv.add_child(l)
	c.set_drag_preview(pv)
	sel = src.duplicate()
	return src


func _can_drop(_at: Vector2, data: Variant, target: Dictionary) -> bool:
	if not data is Dictionary or not (data as Dictionary).has("from"):
		return false
	var d := data as Dictionary
	var to := String(target["to"])
	if d["side"] == target["side"] and d["from"] == to and to != "drop":
		return false
	return FieldInventory.accepts(to, int(d["id"]))


func _drop_on(_at: Vector2, data: Variant, target: Dictionary) -> void:
	var d := data as Dictionary
	move_item(String(d["side"]), String(d["from"]), int(d["id"]), String(target["side"]), String(target["to"]))


func _right_click(ev: InputEvent, id: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_desc = {"id": id, "at": screen.stage.get_local_mouse_position()}
		refresh()


## Beschreibung (Frame `description` des HUD-Modells, X_B_DNLF/X_B_DNRG) an der Maus: Name, Gewicht, Magazin,
## Mündungsgeschwindigkeit, Zielfernrohr (Texte 2730–2734 wie der Ausrüstungsbildschirm)
func _description(id: int, at: Vector2) -> void:
	var fr := screen.rect("description", Rect2(-912, -81, 257, 122))
	var shift := Vector2(clampf(at.x + 12.0, 0.0, OrigScreen.REF.x - fr.size.x), clampf(at.y + 12.0, 0.0, OrigScreen.REF.y - fr.size.y)) - fr.position
	var ov := Control.new()
	ov.name = "Description"
	ov.size = OrigScreen.REF
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.stage.add_child(ov)
	screen.draw_frames(["shadow04", "description"], ov, shift)
	var l := Label.new()
	l.name = "DescriptionText"
	l.position = fr.position + shift + Vector2(10, 8)
	l.size = fr.size - Vector2(20, 16)
	l.text = "\n".join(description_lines(id))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", OrigScreen.INK)
	ov.add_child(l)


static func description_lines(id: int) -> Array:
	var lines: Array = [SAS.item_label(id), "%s : %.2f kg" % [SAS.text(2730, "Gewicht"), SAS.weight(id)]]
	var wd: Dictionary = SAS._weapons.get(id, {})
	if not wd.is_empty():
		if int(wd.get("magazine", 0)) > 0:
			lines.append("%s : %d" % [SAS.text(2731, "Anzahl der Kugeln im Magazin"), int(wd.get("magazine", 0))])
		if float(wd.get("muzzle_velocity", 0.0)) > 0.0:
			lines.append("%s : %.2f m/s" % [SAS.text(2732, "Schussgeschwindigkeit"), float(wd.get("muzzle_velocity", 0.0))])
	return lines
