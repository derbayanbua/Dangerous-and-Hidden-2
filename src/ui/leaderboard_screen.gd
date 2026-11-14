class_name LeaderboardScreen
extends OrigScreen
## 0.11.5: RANGLISTE im Internet-Menü (Masterserver GET /v1/leaderboard, PROTOCOL §15.l) im Original-Look:
## Menümodell MODELS\multiplayer menu.4ds wie der Internet-Serverbrowser (Tabelle table00, Knöpfe der unteren Reihe,
## Statuszeile text_online). Spalten POS./NAME/RANG/XP/KILLS/TODE/SIEGE/SPIELE, 20 Einträge je Seite, eigenes Konto
## (guid_hash des angemeldeten Kontos) rot hervorgehoben, Blättern, AKTUALISIEREN, ZURÜCK, Lade-/Fehleranzeige.
## Daten über MasterLink.source (Autoload Master bzw. Ersatz in Tests).
## 0.11.5: leaderboard in the internet menu, original look (same model as the server browser), 20 rows per page,
## own account highlighted, paging, refresh, back, loading/error line. Data via MasterLink.source.

signal back_requested

const PAGE := 20
const ROW_Y0 := 221.0
const ROW_H := 18.9
## Spalten [x0, x1] innerhalb der Tabelle table00 (117–926 wie die Serverzeilen)
const COLS := [["pos", "POS.", 119.0, 160.0, HORIZONTAL_ALIGNMENT_RIGHT], ["name", "NAME", 170.0, 392.0, HORIZONTAL_ALIGNMENT_LEFT],
	["rank_name", "RANG", 396.0, 556.0, HORIZONTAL_ALIGNMENT_LEFT], ["xp", "XP", 560.0, 640.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["kills", "KILLS", 644.0, 712.0, HORIZONTAL_ALIGNMENT_RIGHT], ["deaths", "TODE", 716.0, 782.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["wins", "SIEGE", 786.0, 852.0, HORIZONTAL_ALIGNMENT_RIGHT], ["matches", "SPIELE", 856.0, 924.0, HORIZONTAL_ALIGNMENT_RIGHT]]
const OWN_COLOR := Color(0.62, 0.08, 0.04, 0.18)

var master: Node
var page := 0
var total := 0
var entries: Array = []
var own_gh := ""
var loading := false
var error_text := ""
var _req := 0                      ## laufende Anfrage (ältere Antworten verwerfen) / request generation


func open() -> void:
	setup_stage()
	master = MasterLink.source(get_tree())
	if master.has_method("own_guid_hash"):
		own_gh = String(master.call("own_guid_hash"))
	load_page(0)


func load_page(p: int) -> void:
	page = maxi(p, 0)
	loading = true
	error_text = ""
	_req += 1
	var gen := _req
	build()
	var src = master                    # untypisiert: Autoload Master oder Ersatz / untyped: Master or stand-in
	var res: Dictionary = await src.fetch_leaderboard(page * PAGE, PAGE)
	if gen != _req or not is_instance_valid(self):
		return
	loading = false
	if master.has_method("own_guid_hash"):
		own_gh = String(master.call("own_guid_hash"))
	if bool(res.get("ok", false)):
		entries = res.get("entries", [])
		total = int(res.get("total", 0))
		# Seite hinter dem Ende (Liste geschrumpft) → letzte Seite / page past the end → last page
		if entries.is_empty() and total > 0 and page > 0:
			load_page(last_page())
			return
	else:
		entries = []
		var t := String(res.get("text", ""))
		error_text = tr("Rangliste nicht verfügbar") + (": " + t if t != "" else "")
	build()


func last_page() -> int:
	return maxi(floori(float(total - 1) / PAGE), 0) if total > 0 else 0


func page_count() -> int:
	return last_page() + 1


func build() -> void:
	begin("multiplayer menu")
	text_at("text_screen", tr("RANGLISTE"), 24, HORIZONTAL_ALIGNMENT_RIGHT, INK, false,
		Rect2(584.7, 44.0, 354.5, 43.0)).name = "Title"
	text_at("text_h&dversion", "Dangerous and Hidden 2 (unofficial) · v%s" % ProjectSettings.get_setting("application/config/version"),
		14, HORIZONTAL_ALIGNMENT_LEFT, INK, false, Rect2(71.2, 61.6, 414.1, 23.1))
	draw_frames(["table00"])
	for c in COLS:
		label(Rect2(c[2], 181.3, c[3] - c[2], 32.6), tr(String(c[1])), 13, INK, c[4]).name = "Head_" + String(c[0])
	var rows := Control.new()
	rows.name = "Rows"
	rows.size = REF
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(rows)
	for i in mini(entries.size(), PAGE):
		_row(i, entries[i])
	var has_prev := page > 0 and not loading
	var has_next := (page + 1) * PAGE < total and not loading
	orig_button("badd/remove", tr("VORHERIGE SEITE"), func(): load_page(page - 1), has_prev, "PrevButton", 15)
	orig_button("benter server ip", tr("NÄCHSTE SEITE"), func(): load_page(page + 1), has_next, "NextButton", 15)
	orig_button("bview game info", tr("AKTUALISIEREN"), func(): load_page(page), not loading, "RefreshButton", 15)
	orig_button("bback", SAS.text(2313, "ZURÜCK"), func(): back_requested.emit(), true, "BackButton")
	var st := text_at("text_online", status_line(), 14, HORIZONTAL_ALIGNMENT_LEFT, INK_RED if error_text != "" else INK,
		false, Rect2(73, 606.3, 865.4, 25))
	st.name = "text_online"


func status_line() -> String:
	if loading:
		return tr("Lade Rangliste …")
	if error_text != "":
		return error_text
	if total == 0:
		return tr("Noch keine gewerteten Spiele")
	return tr("Seite %d von %d") % [page + 1, page_count()] + "   ·   %d " % total + tr("Einträge")


func _row(k: int, e: Dictionary) -> void:
	var y := ROW_Y0 + k * ROW_H
	var own := own_gh != "" and String(e.get("gh", "")) == own_gh
	if own:
		var hl := ColorRect.new()
		hl.name = "OwnRow"
		hl.color = OWN_COLOR
		hl.position = Vector2(117.7, y)
		hl.size = Vector2(809.0, ROW_H)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.get_node("Rows").add_child(hl)
	var ink := INK_RED if own else INK
	for c in COLS:
		var key := String(c[0])
		var v = e.get(key, "")
		var txt := String(v) if typeof(v) == TYPE_STRING else str(int(v))
		var l := label(Rect2(c[2], y, c[3] - c[2], ROW_H), txt, 12, ink, c[4])
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # Spielernamen nie übersetzen / never translate names
		l.name = "Cell_%s_%d" % [key, k]
