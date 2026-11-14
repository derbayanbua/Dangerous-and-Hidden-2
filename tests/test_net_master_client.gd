extends Node
## 0.11.1 Client-Seite zu test_net_master (zweiter Prozess): Test-Build-Schlüssel und Master-Testschlüssel aus dem
## Testordner, Anmeldung beim lokalen Mock, Beitritt mit Beitrittsbeleg, Master-Rang in der Liste, Beförderung im HUD,
## keine Meldung bei UNRANKED. Ergebnis nach user://test_net_master/client_result.txt.

const DIR := "user://test_net_master"

var lines: PackedStringArray = []
var promos: Array = []
var _kh_bak = null


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _chat_seen(t: String) -> bool:
	return Net.chat_log.any(func(e): return String(e["text"]) == t)


func _run() -> void:
	var M := get_node("/root/Master")
	M.key_bits = 2048
	var bk := CryptoKey.new()
	bk.load(DIR + "/build.key", false)
	M.set_build_key(bk)
	var info := FileAccess.get_file_as_string(DIR + "/mock.txt").split("\n")
	var mk := CryptoKey.new()
	mk.load(DIR + "/master_pub.key", true)
	M.test_master_keys = {info[1]: mk}
	M.master_url = "http://127.0.0.1:%s" % info[0]
	M.promoted.connect(func(l, n): promos.append([l, n]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/client_acc/account.json"))
	_kh_bak = Net.auth.load_known_hosts()   # nach dem Test wiederherstellen: der signierte Eintrag für 127.0.0.1:PORT
	# würde sonst spätere LAN-Tests (unsignierter Host, gleiche Adresse) mit HOST_KEY_MISMATCH abweisen
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Net.auth.known_hosts_path()))
	var ok: bool = await M.login({"name": "Gast", "dir": DIR + "/client_acc"})
	check(ok and not M.join_account().is_empty(), "Anmeldung beim Master (Mock), Konto für JOIN_HELLO")
	Net.local_name = "Gast"
	Net.join("127.0.0.1", Net.PORT, "")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		if Game.current_mission() and Net._soldiers.has(Net.my_id()):
			break
	check(Net._soldiers.has(Net.my_id()), "Beigetreten (ENet-Auth, Host-Challenge geprüft)")
	check(Net.auth.last_host.get("signed", false) and String(Net.auth.last_host.get("server_id", "")).length() == 64,
		"Challenge mit Serverschlüssel signiert", str(Net.auth.last_host))
	check(Net.auth.load_known_hosts().has("127.0.0.1:%d" % Net.PORT), "Direktbeitritt: Serveridentität gemerkt (TOFU)")
	var me := Net.my_id()
	check(await _wait(func() -> bool: return int(Net.players.get(me, {}).get("master_rank", -1)) == 7, 60.0),
		"Eigener Master-Rang vom Server verteilt", str(Net.players.get(me, {}).get("master_rank")))
	check(Net.shown_rank(me)["master"] and Net.shown_rank(1)["text"] == "", "Online: Host ohne Konto → Rang leer (kein lokaler Rang)")
	check(await _wait(func() -> bool: return promos.size() >= 1, 240.0), "Beförderungsmeldung empfangen", str(promos))
	if promos.size() >= 1:
		check(int(promos[0][0]) == 3 and String(promos[0][1]) == Career.rank_name(3), "Beförderung Stufe 3 (Wert vom Master)")
	var hud := get_tree().root.find_child("MpHud", true, false)
	if hud == null:
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if n.has_method("show_promotion"):
				hud = n
	check(hud != null and hud.promo_text.contains(tr(Career.rank_name(3))), "Beförderung im MP-HUD angezeigt",
		hud.promo_text if hud else "kein HUD")
	await _wait(func() -> bool: return _chat_seen("PHASE_END"), 240.0)
	check(_chat_seen("PHASE_UNRANKED") and promos.size() == 1, "UNRANKED → keine weitere Beförderung", str(promos.size()))
	_done()


func _done() -> void:
	if _kh_bak != null:
		Net.auth.save_known_hosts(_kh_bak)
	var f := FileAccess.open(DIR + "/client_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	get_tree().quit()
