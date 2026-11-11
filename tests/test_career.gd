extends "res://tests/test_gameplay.gd"
## Karriere-XP / 15 Dienstgrade (0.11.1): Tabelle = Master-Standardwerte, Schwellen, Speichern/Laden atomar,
## Einzelspieler-XP nach Mission, Online: Master-Rang maßgeblich, Client-XP ignoriert, UNRANKED ohne Meldung (Mock).
##   tools\godot.cmd --headless -- --autoplay=test_career --profiles_dir=user://test_career --noimport

const MOCK := preload("res://tests/master_mock.gd")

## Erwartete Werte (Master progression, Standard)
const NAMES := ["Private", "Private First Class", "Corporal", "Sergeant", "Staff Sergeant", "Technical Sergeant",
	"First Sergeant", "Master Sergeant", "Second Lieutenant", "First Lieutenant", "Captain", "Major",
	"Lieutenant Colonel", "Colonel", "Brigadier General"]
const XP := [0, 1500, 5000, 14000, 32000, 65000, 115000, 185000, 280000, 410000, 580000, 810000, 1100000, 1500000, 2000000]


func _run() -> void:
	await frames(3)
	_table()
	_save_load()
	_sp_mission()
	await _online()
	_finish()


func _table() -> void:
	check(Career.RANKS.size() == 15, "15 Dienstgrade")
	var ok := true
	for i in 15:
		ok = ok and Career.RANKS[i]["name"] == NAMES[i] and int(Career.RANKS[i]["xp"]) == XP[i] and int(Career.RANKS[i]["level"]) == i + 1
	check(ok, "Namen/Schwellen = Master")
	var r: Dictionary = Career.REWARDS
	check(r["pvp_kill"] == 20 and r["ai_kill"] == 5 and r["assist"] == 10 and r["objective"] == 150 and r["mission_success"] == 250 \
		and r["pvp_win"] == 150 and r["extraction"] == 100 and r["revive"] == 50 and r["no_alarm"] == 100 and r["teamkill"] == -200, "XP-Werte = Master")
	check(Career.STAR_EVERY == 250000 and Career.LIMITS["max_xp_per_hour"] == 4000 and Career.LIMITS["pvp_kills_per_victim"] == 5, "Stern/Grenzen = Master")
	check(Career.status(0)["level"] == 1 and Career.status(1499)["level"] == 1 and Career.status(1500)["level"] == 2, "Schwelle 1500")
	var s := Career.status(3250)
	check(s["level"] == 2 and s["remaining"] == 1750 and is_equal_approx(s["progress"], 0.5), "Fortschritt in der Stufe", str(s))
	check(Career.status(2000000)["level"] == 15 and Career.status(2000000)["stars"] == 0, "Höchster Rang")
	check(Career.status(2600000)["stars"] == 2 and Career.status(2600000)["over_max"], "Dienststerne je 250000")
	check(Career.status(-50)["xp"] == 0, "nie negativ")
	var bt_ok := true
	for lv in range(1, 16):
		var bt := Career.badge_texture(lv)
		bt_ok = bt_ok and bt != null and bt.get_width() == 32
	check(bt_ok, "Platzhalter-Abzeichen 1–15 erzeugt")
	check(Career.badge_of(11) == "cpt" and Career.badge_path(1).ends_with("pvt.png"), "Abzeichen-Zuordnung")


func _save_load() -> void:
	var dir := "user://test_career/p1"
	for f in ["career.json", "career.json.bak", "career.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	check(Career.load_profile(dir)["xp"] == 0, "Neues Profil")
	var p := Career.load_profile(dir)
	p["xp"] = 4200
	check(Career.save_profile(dir, p) == OK, "Speichern atomar")
	p["xp"] = 4300
	Career.save_profile(dir, p)
	check(Career.load_profile(dir)["xp"] == 4300 and Career.load_profile(dir)["format"] == Career.FORMAT, "Laden mit Formatversion")
	# kaputte Hauptdatei → Rückfall auf .bak
	var f := FileAccess.open(dir.path_join("career.json"), FileAccess.WRITE)
	f.store_string("{kaputt")
	f.close()
	check(Career.load_profile(dir)["xp"] == 4200, "Rückfall auf .bak bei kaputter Datei")
	var g := FileAccess.open(dir.path_join("career.json"), FileAccess.WRITE)
	g.store_string(JSON.stringify({"format": 99, "xp": 9}))
	g.close()
	check(Career.load_profile(dir)["format"] == Career.FORMAT, "Neuere Formatversion nicht übernommen")


func _sp_mission() -> void:
	var dir := "user://test_career/p2"
	for f in ["career.json", "career.json.bak", "career.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	var res := {"success": true, "time": 900, "stats": {"kills": 12, "alarm": false},
		"objectives": [["a", 1, false], ["b", 1, false], ["c", 2, true], ["d", 0, true]]}
	var x := Career.mission_xp(res)
	check(x["total"] == 12 * 5 + 2 * 150 + 250 + 100, "SP-XP nach Tabelle", str(x))
	var a := Career.apply_mission(dir, res)
	check(a["gained"] == 710 and Career.load_profile(dir)["xp"] == 710 and Career.load_profile(dir)["missions"] == 1, "SP-XP gespeichert")
	res["stats"]["alarm"] = true
	res["success"] = false
	check(Career.mission_xp(res)["total"] == 60 + 300, "Ohne Erfolg/mit Alarm keine Boni")
	for i in 2:
		a = Career.apply_mission(dir, {"success": true, "stats": {"kills": 0, "alarm": false}, "objectives": [["x", 1, false]]})
	check(a["promoted"] and a["new"]["level"] == 2, "Beförderung lokal (Stufe 2)", str(Career.load_profile(dir)["xp"]))
	check(SAS.rank_name(3) != "" and Game.has_method("commit_debrief") and "last_career" in Game, "Original-SAS-Ränge unverändert, Karriere getrennt")


func _online() -> void:
	var M = get_node("/root/Master")
	var saved: String = M.master_url
	M.key_bits = 2048
	var bkey := Crypto.new().generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(bkey.save_to_string(true), true)
	M.set_build_key(bkey)
	var mock = MOCK.new()
	add_child(mock)
	mock.setup(pub)
	M.test_master_keys = {mock.master_kid: mock.master_key}
	M.master_url = "http://127.0.0.1:%d" % mock.port
	var dir := "user://test_career/acc"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("account.json")))
	# Client meldet Rang 15 → Master-Wert gilt
	check(await M.login({"name": "Karl", "dir": dir, "rank": 15}), "Login")
	check(M.account["rank"] == 5, "Client-Rang ignoriert, Master-Rang übernommen")
	var body: String = mock.log.filter(func(e): return String(e["path"]).ends_with("/login"))[-1]["body"]
	var pl = JSON.parse_string(Marshalls.base64_to_raw(JSON.parse_string(body)["payload"]).get_string_from_utf8())
	check(not pl.has("xp") and not pl.has("career"), "Client sendet keine XP")
	# Spielserver: Bericht → Beförderung an den Client, Rang an alle
	M.load_server_key("user://test_career/server.key")
	await M.register_server({"name": "S", "port": 11001})
	M._hb_timer.stop()
	var net = get_node("/root/Net")
	var gh := "d".repeat(32)
	net.players[55] = {"name": "Karl"}
	await M.set_peer_account(55, gh)
	check(net.players[55].get("master_rank") == 7, "Rang je Spieler vom Master an Net.players")
	var rep := {"map": "m", "mode": 4, "round": 1, "started_at": 1, "ended_at": 700, "partial": false,
		"result": {"winner": 0, "team_score": [1, 0], "mission_success": true, "no_alarm": true},
		"players": [{"gh": gh, "name": "Karl", "team": 0, "kills": 0, "ai_kills": 14, "objectives": 2, "revives": 1,
			"extracted": true, "victims": {}, "deaths": 0, "assists": 0, "score": 5, "teamkills": 0, "suicides": 0,
			"time_s": 690, "won": true, "proof": {}, "xp": 999999}]}
	M.promotions_sent.clear()
	var j: Dictionary = await M.report_match(rep)
	var rlog: Array = mock.log.filter(func(e): return e["path"] == "/v1/matches/report")
	var sent = JSON.parse_string(Marshalls.base64_to_raw(JSON.parse_string(rlog[-1]["body"])["payload"]).get_string_from_utf8())
	check(j.get("verdict") == "ACCEPTED" and M.promotions_sent.size() == 1 and M.promotions_sent[0] == [55, 3], "Beförderungsmeldung an den Client", str(M.promotions_sent))
	check(sent != null and sent["players"][0]["ai_kills"] == 14 and sent["result"]["mission_success"] and not sent["players"][0].has("xp"), "Berichtsfelder ai_kills/mission_success übertragen")
	M.promotions_sent.clear()
	mock.report_verdict = "UNRANKED"
	j = await M.report_match(rep)
	check(j.get("verdict") == "UNRANKED" and M.promotions_sent.is_empty(), "UNRANKED ohne Beförderungsmeldung")
	net.players.erase(55)
	await M.unregister_server()
	# LAN: Original-Beförderung unverändert
	check(net.rank_of(25) == 2 and net.rank_of(500) == 7, "LAN-Rang min(⌊Punkte/10⌋, 7)")
	M.master_url = saved
	M.test_master_keys = {}
	M.set_build_key(null)
