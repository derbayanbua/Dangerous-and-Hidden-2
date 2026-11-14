extends "res://tests/lan_ui_base.gd"
## 0.11.5: Rangliste – Master.fetch_leaderboard gegen den lokalen Master-Nachbau (tests/master_mock.gd, 127.0.0.1,
## Laufzeit-Testschlüssel, nie der echte Master) und Bildschirm RANGLISTE im Internet-Menü (Blättern, eigenes Konto,
## Lade-/Fehleranzeige, ZURÜCK).
##   tools\godot.cmd --headless -- --autoplay=test_leaderboard --profiles_dir=user://test_leaderboard --noimport

const MOCK := preload("res://tests/master_mock.gd")

var M: Node
var mock: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


static func gh_of(i: int) -> String:
	return ("%08x" % (0x1000 + i)).repeat(4)


func _run() -> void:
	var menu := await menu_with_profile("Rangliste")
	M = get_node("/root/Master")
	var saved_url: String = M.master_url
	var r0: Dictionary = await M.fetch_leaderboard(0, 20)
	check(not r0["ok"] and r0["code"] == "NO_BUILD", "Ohne Build-Schlüssel keine Anfrage", str(r0["code"]))
	var bkey := Crypto.new().generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(bkey.save_to_string(true), true)
	M.set_build_key(bkey)
	mock = MOCK.new()
	add_child(mock)
	mock.setup(pub)
	M.test_master_keys = {mock.master_kid: mock.master_key}
	M.master_url = "http://127.0.0.1:%d" % mock.port
	check(mock.port > 0, "Lokaler Master-Nachbau läuft", str(mock.port))
	var own := gh_of(22)
	for i in 45:
		mock.lb_entries.append({"gh": gh_of(i), "name": ("Spieler%02d" % i) + (String.chr(0x200B) if i == 3 else ""),
			"xp": 100000 - i * 1000, "rank": 7 - i / 10, "rank_name": "Rang %d" % (7 - i / 10), "stars": i % 3,
			"kills": 500 - i, "deaths": 100 + i, "wins": 40 - i % 40, "matches": 90 - i, "revives": 3, "heals": 4})
	mock.lb_entries.append({"gh": "kein-hash", "name": "Ungültig", "xp": 1})   # ungültige gh → verworfen

	await _client_tests()
	await _ui_tests(menu, own)

	check(mock.log.all(func(e): return String(e["auth"]) == ""), "Alle Anfragen mit gültiger X-DH2-Auth-Signatur")
	M.master_url = saved_url
	M.test_master_keys = {}
	M.set_build_key(null)
	M.account = {}
	_finish()


func _client_tests() -> void:
	var got := []
	var cb := func(p): got.append(p)
	M.leaderboard_received.connect(cb)
	var r: Dictionary = await M.fetch_leaderboard(0, 20)
	var last: Dictionary = mock.log[-1]
	check(last["path"] == "/v1/leaderboard" and last["query"] == "offset=0&limit=20" and last["auth"] == "",
		"GET /v1/leaderboard?offset=0&limit=20 signiert", "%s?%s %s" % [last["path"], last["query"], last["auth"]])
	check(r["ok"] and r["entries"].size() == 20 and int(r["total"]) == 46, "Seite 1: 20 Einträge, total", "%s %d" % [r["ok"], int(r["total"])])
	check(int(r["entries"][0]["pos"]) == 1 and int(r["entries"][0]["xp"]) == 100000 and r["entries"][0]["gh"] == gh_of(0),
		"Felder pos/xp/gh übernommen")
	check(String(r["entries"][3]["name"]) == "Spieler03", "Name bereinigt (Steuerzeichen entfernt)", String(r["entries"][3]["name"]))
	check(got.size() == 1 and got[0]["entries"].size() == 20, "Signal leaderboard_received")
	M.leaderboard_received.disconnect(cb)
	r = await M.fetch_leaderboard(40, 20)
	check(r["ok"] and r["entries"].size() == 5, "Letzte Seite: ungültige gh verworfen (5 statt 6)", str(r["entries"].size()))
	r = await M.fetch_leaderboard(-5, 500)
	check(mock.log[-1]["query"] == "offset=0&limit=100", "offset/limit auf 0..10000 / 1..100 begrenzt", mock.log[-1]["query"])
	check(r["ok"], "Signierter Umschlag (DH2/v1/leaderboard, Test-kid) angenommen")
	var reject := {"plain": "Unsignierte Antwort", "badsig": "Manipulierter Payload", "wrongkid": "Falscher kid/fremder Schlüssel",
		"wrongctx": "Signatur mit anderem Kontext", "stale": "generated_at älter als 10 min",
		"future": "generated_at > 2 min in der Zukunft", "garbage": "Signiert, aber ohne entries"}
	for mode in reject:
		mock.lb_mode = mode
		r = await M.fetch_leaderboard(0, 20)
		check(not r["ok"] and r["code"] == "LIST_INVALID" and r["entries"].is_empty(), String(reject[mode]) + " → abgelehnt", r["code"])
	var k0 = M.test_master_keys
	M.test_master_keys = {}
	mock.lb_mode = "ok"
	r = await M.fetch_leaderboard(0, 20)
	check(not r["ok"] and r["code"] == "LIST_INVALID", "Test-Schlüssel nicht eingetragen → abgelehnt (nur eingebettete Master-Keys)", r["code"])
	M.test_master_keys = k0
	mock.lb_mode = "ok"
	mock.fail_next["/v1/leaderboard"] = [400, "INVALID_FIELD"]
	r = await M.fetch_leaderboard(0, 20)
	check(not r["ok"] and r["code"] == "INVALID_FIELD", "Masterfehler wird gemeldet", r["code"])


func _ui_tests(menu: Node, own: String) -> void:
	MasterLink.force_mock = false
	M.account = {"guid_hash": own}          # angemeldetes Konto (Login selbst prüft test_master_client)
	Game.profile["online_consent"] = true
	menu.open_lan(true)
	await frames(6)
	var lm: LanMenu = menu.lan_menu
	var br: ServerBrowserScreen = lm.browser if lm else null
	check(br != null and br.visible, "Internet-Serverbrowser offen")
	if br == null:
		return
	var lb_btn: Button = br.find_child("LeaderboardButton", true, false)
	check(lb_btn != null and lb_btn.text == tr("RANGLISTE") and not lb_btn.disabled, "Knopf RANGLISTE im Internet-Browser")
	if lb_btn == null:
		return
	lb_btn.pressed.emit()
	var lb: LeaderboardScreen = lm.leaderboard
	check(lb != null and lb.is_visible_in_tree() and not br.visible, "RANGLISTE geöffnet, Browser ausgeblendet")
	if lb == null:
		return
	check(lb.loading and _status(lb) == tr("Lade Rangliste …"), "Ladeanzeige während der Anfrage", _status(lb))
	check(await wait_for(func(): return not lb.loading, 15.0), "Seite geladen")
	check(lb.has_layout() == br.has_layout(), "Original-Modell multiplayer menu wie der Browser")
	check((lb.find_child("Title", true, false) as Label).text == tr("RANGLISTE"), "Titel RANGLISTE")
	var heads := ["pos", "name", "rank_name", "xp", "kills", "deaths", "wins", "matches"]
	check(heads.all(func(h): return lb.find_child("Head_" + h, true, false) != null), "8 Spaltenköpfe")
	check(lb.find_child("Cell_name_19", true, false) != null and lb.find_child("Cell_name_20", true, false) == null,
		"20 Zeilen je Seite")
	check((lb.find_child("Cell_pos_0", true, false) as Label).text == "1"
		and (lb.find_child("Cell_name_0", true, false) as Label).text == "Spieler00"
		and (lb.find_child("Cell_xp_0", true, false) as Label).text == "100000", "Zeile 1: Pos/Name/XP")
	check(_status(lb) == tr("Seite %d von %d") % [1, 3] + "   ·   46 " + tr("Einträge"), "Statuszeile Seite 1 von 3", _status(lb))
	check(lb.find_child("OwnRow", true, false) == null, "Seite 1 ohne eigenes Konto")
	check(_btn(lb, "PrevButton").disabled and not _btn(lb, "NextButton").disabled, "Seite 1: zurück gesperrt, vor frei")
	_btn(lb, "NextButton").pressed.emit()
	await wait_for(func(): return not lb.loading, 15.0)
	check(mock.log[-1]["query"] == "offset=20&limit=20", "Vorblättern lädt offset=20", mock.log[-1]["query"])
	var own_row := lb.find_child("OwnRow", true, false) as ColorRect
	var own_name := lb.find_child("Cell_name_2", true, false) as Label
	check(own_row != null and own_name != null and own_name.text == "Spieler22"
		and own_name.get_theme_color("font_color") == OrigScreen.INK_RED, "Eigenes Konto (Pos. 23) hervorgehoben")
	check(own_row != null and absf(own_row.position.y - (LeaderboardScreen.ROW_Y0 + 2 * LeaderboardScreen.ROW_H)) < 0.1,
		"Hervorhebung auf der richtigen Zeile")
	_btn(lb, "NextButton").pressed.emit()
	await wait_for(func(): return not lb.loading, 15.0)
	check(lb.page == 2 and lb.find_child("Cell_name_4", true, false) != null and lb.find_child("Cell_name_5", true, false) == null
		and _btn(lb, "NextButton").disabled, "Letzte Seite: 5 Zeilen, vor gesperrt")
	_btn(lb, "PrevButton").pressed.emit()
	await wait_for(func(): return not lb.loading, 15.0)
	check(lb.page == 1 and mock.log[-1]["query"] == "offset=20&limit=20", "Zurückblättern")
	# Fehleranzeige
	mock.lb_mode = "garbage"
	_btn(lb, "RefreshButton").pressed.emit()
	await wait_for(func(): return not lb.loading, 15.0)
	check(lb.error_text != "" and _status(lb).begins_with(tr("Rangliste nicht verfügbar")) and lb.entries.is_empty()
		and lb.find_child("Cell_name_0", true, false) == null, "Fehleranzeige bei ungültiger Antwort", _status(lb))
	mock.lb_mode = "ok"
	var saved: Array = mock.lb_entries
	mock.lb_entries = []
	_btn(lb, "RefreshButton").pressed.emit()
	await wait_for(func(): return not lb.loading, 15.0)
	check(lb.error_text == "" and _status(lb) == tr("Noch keine gewerteten Spiele"), "Leere Rangliste: Hinweis", _status(lb))
	mock.lb_entries = saved
	var tro := TranslationServer.get_translation_object("en")
	check(tro != null and tro.get_message("RANGLISTE") == "LEADERBOARD" and tro.get_message("Lade Rangliste …") != "",
		"Texte übersetzt (en)")
	_btn(lb, "BackButton").pressed.emit()
	await frames(2)
	check(lm.leaderboard == null and br.visible, "ZURÜCK: wieder im Serverbrowser")
	(br.find_child("BackButton", true, false) as Button).pressed.emit()
	await frames(2)


func _btn(lb: Node, n: String) -> Button:
	return lb.find_child(n, true, false) as Button


func _status(lb: Node) -> String:
	var l := lb.find_child("text_online", true, false) as Label
	return l.text if l else ""
