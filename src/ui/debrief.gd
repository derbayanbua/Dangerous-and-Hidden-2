extends OrigScreen
## Nachbesprechung „ABSCHLUSSBESPRECHUNG“ (T2751/2752) 1:1 nach MODELS\debriefing.4ds (Builder hd2.exe
## 0x68E12F–0x68EDBD, GAP_ANALYSE Anhang A.4) und Tagebuch nach MODELS\diary.4ds (0x68D6F5–0x68DCBE):
##  links  Team-Status: je Soldat ein Panel (Bildlauf scroll00): Porträt + Gefallen-Band, Rangabzeichen (X_RANKS),
##         Name, Kurzzeile (Rang bzw. T2765 „Gefallen“), „Status-Verbesserung“ (T2770) mit 7 Werteleisten und rotem
##         Zuwachsbalken je Wert (upgradeNN = Training dieses Einsatzes), Orden (T2771, 12 Bandschnallen), „Neue
##         Orden“ (T2772: großes Ordensbild + Text 10100+2·id).
##  rechts Status (T2760): Missionsergebnis, Aufgaben mit T2915–2918; Knöpfe ERNEUT VERSUCHEN (T2764),
##         SPEICHERN UND FORTSETZEN (T2754 → Rückfrage T9523/T9524, dann Werteübernahme 0x68C300 und Fortschritt),
##         TAGEBUCH ANZEIGEN (T2755), ZURÜCK ZUM HAUPTMENÜ (T2756).
## Werte werden erst bei SPEICHERN UND FORTSETZEN übernommen (Game.commit_debrief); ERNEUT VERSUCHEN/Hauptmenü
## verwerfen den vorbereiteten Stand. Einzelmission/Übungseinsatz: statt Speichern „ZUM MISSIONSAUSWAHL-MENÜ“ (T2762).

## Zeilen des Panels: Wert, Beschriftung, Rahmen, Füllung, Zuwachs, Zahl (Text 2670+i laut SAS.STAT_PANEL)
const ROWS := [["health", "name_health", "02", "upgrade01", "text_health01"],
	["strength", "name_strenght", "01", "upgrade02", "text_strenght01"],
	["endurance", "name_endurance", "03", "upgrade03", "text_endurance01"],
	["shooting", "name_shooting", "00", "upgrade04", "text_shooting01"],
	["stealth", "name_stealth", "04", "upgrade05", "text_stealth01"],
	["first_aid", "name_first aid", "05", "upgrade06", "text_first aid01"],
	["lockpick", "name_lockpick", "06", "upgrade07", "text_lockpick01"]]
## Rangabzeichen je Rang 0–8 (0x68EA24: 8 Abzeichen; Warrant Officer = Abzeichen class1 aus dem Modell [P])
const RANK_FRAMES := ["rank_private", "rank_corporal", "rank_sergeant", "rank_StaffSergeant", "rank_WarrantOfficerclass1",
	"rank_second_lieutenant", "rank_lieutenant", "rank_captain", "rank_major"]
const MEDAL_FRAMES := ["DSO", "DCM", "MILIT_MEDAL", "GSM_AFRICA", "GSM", "WAR_MEDAL", "DEFENCE_MEDAL", "MILITARY_CROSS",
	"VICTORIA_CROSS", "GERM_FRANCE_STAR", "AFRICA_STAR", "BURMA_STAR"]

var r: Dictionary = {}
var members: Array = []
var member_i := 0
var page := "debrief"            ## "debrief" / "diary"
var diary_page := 0
var saved := false


func _exit_tree() -> void:
	OrigAudio.stop_music()


func _ready() -> void:
	name = "Debrief"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	r = Game.last_result
	members = r.get("sas", {}).get("members", [])
	setup_stage()
	# Original-Musik der Nachbesprechung: Kat. 12 Gruppe 1 „Success Menu“ bzw. 2 „Fail Menu“
	OrigAudio.play_music(1 if success() else 2)
	show_debrief()


func success() -> bool:
	return bool(r.get("success", false))


func _t(id: int, fb: String) -> String:
	return SAS.text(id, fb)


## Kampagnenstand übernehmbar? (nur Kampagnenmodi, nicht Einzelmission/Übung)
func can_save() -> bool:
	return success() and Game.has_pending_debrief() and not Game.single_mission \
		and Game.CAMPAIGN_ORDER.has(String(r.get("mission", ""))) and not saved


# --- Nachbesprechung ------------------------------------------------------------------------

func show_debrief() -> void:
	page = "debrief"
	begin("debriefing")
	title(2751 if success() else 2752, "ABSCHLUSSBESPRECHUNG")
	text_at("text_team status", _t(2761, "Team Status:"), 15)
	draw_frame("table00")
	_soldier_panel()
	# rechts: Status
	text_at("text_status", _t(2760, "Status:"), 15)
	var mtitle := String(Game.MISSIONS.get(String(r.get("mission", "")), {}).get("title", ""))
	text_at("text_mission status", "%s%s" % [mtitle, _t(2915 if success() else 2916, " -- ERFOLG" if success() else " -- GESCHEITERT")],
		16, HORIZONTAL_ALIGNMENT_LEFT, INK if success() else INK_RED, true).name = "MissionStatus"
	text_at("text_objectives", _objectives_text(), 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true).name = "Objectives"
	orig_button("bretry immediately", _t(2764, "ERNEUT VERSUCHEN"), retry, true, "Retry")
	var sm := Game.single_mission or not Game.CAMPAIGN_ORDER.has(String(r.get("mission", "")))
	if sm:
		orig_button("bsave and continue", _t(2762, "ZUM MISSIONSAUSWAHL-MENÜ"), to_mission_list, true, "SaveContinue")
	else:
		orig_button("bsave and continue", _t(2754, "SPEICHERN UND FORTSETZEN"), save_and_continue, can_save(), "SaveContinue")
	orig_button("bload", _t(2755, "TAGEBUCH ANZEIGEN"), show_diary, true, "Diary")
	orig_button("bexit to main menu", _t(2756, "ZURÜCK ZUM HAUPTMENÜ"), exit_to_menu, true, "MainMenu")


func _objectives_text() -> String:
	var lines: Array = []
	var reason := String(r.get("reason", ""))
	for o in r.get("objectives", []):
		var st := int(o[1])
		if st == Objective.State.INACTIVE:
			continue
		var tid: int = {Objective.State.DONE: 2915, Objective.State.FAILED: 2916}.get(st, 2917)
		lines.append("%s%s%s" % [String(o[0]), " (optional)" if bool(o[2]) else "", _t(tid, "")])
	if lines.is_empty() and reason != "":
		lines.append(reason)
	return "\n".join(lines)


## Soldatenpanel (panel_soldier00) des gewählten Teammitglieds; Bildlauf über die Mitglieder
func _soldier_panel() -> void:
	draw_frames(["scroll00", "sliderbase"])
	var n := members.size()
	member_i = clampi(member_i, 0, maxi(n - 1, 0))
	var b := rect("sliderbase")
	var k := rect("normal09")
	var frac: float = 0.0 if n <= 1 else float(member_i) / float(n - 1)
	draw_frame("normal09", Vector2(0, b.position.y + (b.size.y - k.size.y) * frac - k.position.y))
	orig_button("barrow up", "", _scroll_member.bind(-1), member_i > 0, "SoldierUp")
	orig_button("barrow down", "", _scroll_member.bind(1), member_i < n - 1, "SoldierDown")
	if n == 0:
		# Übungseinsatz (kein Originalkader): Gefallene als Text
		var fallen: Array = r.get("fallen", [])
		text_at("text_name00", _t(2761, "Team Status:"), 16)
		text_at("text_soldierstats00", "%s: %s" % [_t(2765, "Gefallen"), ", ".join(fallen) if not fallen.is_empty() else "–"],
			13, HORIZONTAL_ALIGNMENT_LEFT, INK, true).name = "Fallen"
		return
	var m: Dictionary = members[member_i]
	var idx := int(m.get("idx", -1))
	var dead := bool(m.get("dead", false))
	draw_frame("soldier00", Vector2.ZERO, {"X_F_001.BMP": tex_file(SAS.portrait_path(idx))})
	if dead:
		draw_frame("death")
	# Rangabzeichen an soldier_rank (pos_px)
	var rank := clampi(int(m.get("rank", 0)), 0, RANK_FRAMES.size() - 1)
	var rp: Array = fr("soldier_rank").get("pos_px", [])
	if rp.size() == 2 and not fr(RANK_FRAMES[rank]).is_empty():
		var rr := rect(RANK_FRAMES[rank])
		draw_frame(RANK_FRAMES[rank], Vector2(float(rp[0]), float(rp[1])) - rr.get_center()).name = "RankBadge"
	text_at("text_name00", String(m.get("name", "")), 17).name = "SoldierName"
	var line: String = _t(2765, "Gefallen") if dead else SAS.rank_name(int(m.get("rank", 0)))
	if not dead and int(m.get("rank", 0)) > int(m.get("rank_before", 0)):
		line = "%s %s" % [_t(2769, "Befördert zum"), SAS.rank_name(int(m.get("rank", 0)))]
	text_at("text_soldierstats00", line, 14, HORIZONTAL_ALIGNMENT_LEFT, INK_RED if dead else INK, true).name = "SoldierLine"
	text_at("text_selected soldier stats", _t(2770, "Status-Verbesserung"), 15)
	var stats: Dictionary = m.get("stats", {})
	var gains: Dictionary = m.get("gains", {})
	for row in ROWS:
		var key: String = row[0]
		var i := 0
		for e in SAS.STAT_PANEL:
			if e[0] == key:
				i = int(e[1]) - 2670
		text_at(row[1], _t(2670 + i, key), 12)
		draw_frame("hlcpctcr" + row[2])
		var cap: float = 1000.0 if key == "health" else 100.0
		var v0 := float(stats.get(key, 0.0))
		var v1 := v0 + float(gains.get(key, 0.0))
		# roter Zuwachsbalken (MM_RED) bis zum neuen Wert, darüber die Leiste bis zum alten Wert
		if v1 > v0 + 0.0005:
			var up := bar(row[3], v1 / cap)
			up.name = "Upgrade_" + key
		bar("hlcpct" + row[2], v0 / cap)
		var shown: String = "%d %%" % roundi(v1 / 10.0) if key == "health" else ("%d Kg" % roundi(v1) if key == "strength" else "%d %%" % roundi(v1))
		text_at(row[4], shown, 12, HORIZONTAL_ALIGNMENT_RIGHT).name = "Value_" + key
	# Orden (Bandschnallen _b an den Platzmitten medal01…12)
	text_at("text_decorations", _t(2771, "Orden"), 15)
	var got: Array = m.get("medals", [])
	for i in mini(got.size(), 12):
		var med := int(got[i])
		var dummy: Array = fr("medal%02d" % (i + 1)).get("pos_px", [])
		var nm: String = MEDAL_FRAMES[clampi(med, 0, 11)] + "_b"
		if dummy.size() == 2 and not fr(nm).is_empty():
			draw_frame(nm, Vector2(float(dummy[0]), float(dummy[1])) - rect(nm).get_center()).name = "Medal%d" % med
	# Neuer Orden: großes Ordensbild (_a) + Name und Beschreibung
	var nm2 := int(m.get("new_medal", -1))
	if nm2 >= 0:
		text_at("text_new decoration", _t(2772, "Neue Orden"), 15)
		text_at("text_new medal", "%s\n\n%s" % [SAS.medal_name(nm2), SAS.medal_text(nm2)], 13, HORIZONTAL_ALIGNMENT_LEFT, INK, true,
			Rect2(119, 560, 268, 135)).name = "NewMedal"
		var np: Array = fr("new_medal").get("pos_px", [])
		var big: String = MEDAL_FRAMES[clampi(nm2, 0, 11)] + "_a"
		if np.size() == 2 and not fr(big).is_empty():
			draw_frame(big, Vector2(float(np[0]), float(np[1])) - rect(big).get_center()).name = "NewMedalImage"


## SPEICHERN UND FORTSETZEN: Rückfrage (T9524, wenn schon ein Fortschritt gespeichert ist, sonst T9523)
func save_and_continue() -> void:
	if not can_save():
		return
	var q: int = 9524 if Game.mode_progress(Game.game_mode) >= 0 else 9523
	dialog(_t(q, "Wollen Sie das Spiel speichern?"), [[_t(2001, "JA"), commit], [_t(2008, "ANNULLIEREN"), func(): pass]])


## Werteübernahme + Fortschritt (0x68C300, 0x6B12D0), danach zur Missionsliste mit dem nächsten Teil
func commit() -> void:
	Game.commit_debrief()
	saved = true
	Game.continue_campaign()


func retry() -> void:
	Game.discard_debrief()
	Game.start_mission(String(r.get("mission", "m01_funkfeuer")))


func exit_to_menu() -> void:
	if can_save():
		dialog(_t(2004, "SIND SIE SICHER?"), [[_t(2001, "JA"), Game.return_to_menu], [_t(2008, "ANNULLIEREN"), func(): pass]])
	else:
		Game.return_to_menu()


# --- Tagebuch (diary.4ds) -------------------------------------------------------------------

## Seiten: Einträge (ADDDIARYTEXT, Text-IDs) der Kampagne und dieses Einsatzes; je Doppelseite links text_02,
## rechts text_01. Ohne Einträge: T2766 „Keine neue Information“.
func diary_pages() -> Array:
	var paras: Array = []
	for tid in Game.diary_entries():
		var t := _t(int(tid), "")
		if t != "":
			paras.append(t.strip_edges())
	if paras.is_empty():
		paras.append(_t(2766, "Keine neue Information"))
	var pages: Array = []
	var cur: Array = []
	var lines := 0
	const MAX_LINES := 22
	const CHARS := 46
	for p in paras:
		var need: int = 1 + int(ceil(float(String(p).length()) / CHARS)) + String(p).count("\n")
		if lines + need > MAX_LINES and not cur.is_empty():
			pages.append("\n\n".join(cur))
			cur = []
			lines = 0
		cur.append(p)
		lines += need
	if not cur.is_empty():
		pages.append("\n\n".join(cur))
	return pages


func show_diary() -> void:
	page = "diary"
	begin("diary")
	title(2753, "TAGEBUCH")
	var pages := diary_pages()
	# Doppelseite: neueste Einträge zuerst sichtbar (letzte Doppelseite) beim ersten Öffnen
	var spreads := maxi(int(ceil(pages.size() / 2.0)), 1)
	if diary_page < 0 or diary_page >= spreads:
		diary_page = spreads - 1
	var left: String = pages[diary_page * 2] if diary_page * 2 < pages.size() else ""
	var right: String = pages[diary_page * 2 + 1] if diary_page * 2 + 1 < pages.size() else ""
	text_at("text_02", left, 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true).name = "DiaryLeft"
	text_at("text_01", right, 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true).name = "DiaryRight"
	orig_button("bprevious page", _t(2757, "VORHERGEHENDE SEITE"), _turn_page.bind(-1), diary_page > 0, "PrevPage")
	orig_button("bnext page", _t(2758, "NÄCHSTE SEITE"), _turn_page.bind(1), diary_page < spreads - 1, "NextPage")
	orig_button("bexit", _t(2759, "ZURÜCK"), show_debrief, true, "DiaryBack")


func _turn_page(d: int) -> void:
	diary_page += d
	show_diary()


func _scroll_member(d: int) -> void:
	member_i += d
	show_debrief()


## Einzelmission: Stand bleibt unverändert (commit verwirft); Übungseinsatz: Ergebnis (Gefallene, ✓) übernehmen
func to_mission_list() -> void:
	Game.commit_debrief()
	Game.menu_request = {"menu": "single_mission", "mode": Game.game_mode, "single": Game.single_mission}
	Game.return_to_menu()
