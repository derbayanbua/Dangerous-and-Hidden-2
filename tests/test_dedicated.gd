extends "res://tests/lan_ui_base.gd"
## Dedizierter Server (HD2DS-Entsprechung), zwei Prozesse: startet einen kopflosen Server mit
## Konfigurationsdatei im ServerLauncher-Stil (--dedicated=<datei>) und Standardeingabe als Server-Konsole,
## tritt als Client bei und prüft: kein Server-Soldat, Serverabfrage (Favoriten/Ping), KI-Soldaten,
## Konsole „say“, Chat-Befehle ohne/mit Admin-Login, Fern-Konsole (bots, svcmd, status), Abstimmung,
## Kartenwechsel per „nextmap“ mit neu erzeugten Bots, Rauswurf per Konsole, „quit“.
##   tools\godot.cmd --headless -- --autoplay=test_dedicated --profiles_dir=user://test_ded --noimport

const DPORT := 11061


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2100.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


var _stdio: FileAccess
var _stderr: FileAccess
var _pid := 0
var out_text := ""          ## Ausgabe der Server-Konsole (stdout über die Pipe)


## Pipe laufend leeren (sonst blockiert der Server beim Schreiben) und Ausgabe sammeln
func _process(_d: float) -> void:
	if _stdio == null:
		return
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 64:
			var b: PackedByteArray = pipe.get_buffer(4096)
			if b.is_empty():
				break
			out_text += b.get_string_from_utf8()
	if out_text.length() > 200000:
		out_text = out_text.substr(out_text.length() - 100000)


func _console(line: String) -> void:
	_stdio.store_string(line + "\n")
	_stdio.flush()


func _bots() -> int:
	var n := 0
	for k in Net._soldiers:
		if int(k) < 0 and is_instance_valid(Net._soldiers[k]):
			n += 1
	return n


func _chat_has(s: String) -> bool:
	for e in Net.chat_log:
		if String(e["text"]).contains(s) or String(e["name"]).contains(s):
			return true
	return false


func _run() -> void:
	await frames(10)
	var cfg := ProjectSettings.globalize_path("res://test_output/test_dedicated.cfg")     # Pfad ohne Leerzeichen
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(["// Testkonfiguration (Schlüsselwörter wie HD2DS / ServerLauncher)",
		"sessionname \"Ded-Test\"", "style deathmatch", "mapname mp_arctic2_mp", "mapname mp_arctic1_mp", "port %d" % DPORT,
		"warmup 0", "pointlimit 0", "roundlimit 0", "respawntime 5", "bots 1", "adminlogin chef", "adminpass geheim", "server"])) + "\n")
	f.close()
	var exe := OS.get_executable_path()
	var r := OS.execute_with_pipe(exe, ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/dedicated_server.log"),
		] + _project_args() + ["--", "--dedicated=" + cfg], false)
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	_pid = int(r.get("pid", 0))
	check(_pid > 0 and _stdio != null, "Dedizierter Server gestartet (Pipe für die Konsole)", str(_pid))
	if _pid <= 0:
		_finish()
		return
	# --- Serverabfrage wie Favoriten (UDP Port + 1): Name, dediziert, KI ---
	var addr := "127.0.0.1:%d" % DPORT
	Net.favorites = [addr]
	Net.browsing_favorites = true
	var info_ok := func() -> bool: return Net.fav_info.has(addr) and int(Net.fav_info[addr].get("bots", 0)) >= 2
	check(await wait_for(info_ok, 400.0), "Serverabfrage: antwortet, Karte geladen, KI-Soldaten", str(Net.fav_info.get(addr, {})))
	var info: Dictionary = Net.fav_info.get(addr, {})
	check(info.get("name") == "Ded-Test" and bool(info.get("ded", false)) and int(info.get("players", -1)) == 0 and int(info.get("ping", -1)) >= 0,
		"Info: Name aus sessionname, dediziert, 0 Spieler, Ping", str(info))
	Net.browsing_favorites = false
	Net.favorites = []
	# --- beitreten ---
	Net.local_name = "Spieler1"
	Net.join("127.0.0.1", DPORT)
	var in_game := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and _bots() >= 2
	check(await wait_for(in_game, 400.0), "Beigetreten: Karte, eigener Soldat, KI-Soldaten")
	check(not Net.players.has(1) and not Net._soldiers.has(1) and Net.humans() == 1, "Kein Spieler/Soldat für den dedizierten Server",
		str(Net.players.keys()))
	check(Game.current_mission_id == "mp_arctic2_mp", "Erste Karte der Kartenliste")
	var hud = Game.current_mission().get_node_or_null("MpHud") if Game.current_mission() else null
	check(hud != null, "MP-HUD beim Client")
	# --- Server-Konsole über die Standardeingabe ---
	_console("say Hallo vom Server")
	var said := func() -> bool: return _chat_has("Hallo vom Server")
	check(await wait_for(said, 60.0), "Konsole (stdin) „say“ → Chat beim Client (ADMIN)")
	check(_chat_has("ADMIN"), "Absender „ADMIN“ wie im Original")
	# --- Chat-Befehle / Admin ---
	Net.send_chat("/nextmap")
	var denied := func() -> bool: return _chat_has("You don't have admin rights!")
	check(await wait_for(denied, 60.0), "Ohne Admin: „You don't have admin rights!“")
	Net.send_chat("/adminlogin chef falsch")
	var wrong := func() -> bool: return _chat_has("Incorrect admin password!")
	check(await wait_for(wrong, 60.0), "Falsches Admin-Passwort abgelehnt")
	Net.send_chat("/adminlogin chef geheim")
	var granted := func() -> bool: return _chat_has("Admin rights granted!")
	check(await wait_for(granted, 60.0), "Admin-Login: „Admin rights granted!“")
	Net.console_command("bots 2")
	var b2 := func() -> bool: return _chat_has("bots = 2")
	check(await wait_for(b2, 60.0), "Fern-Konsole: bots 2")
	Net.console_command("svcmd pointlimit 3")
	var pl := func() -> bool: return _chat_has("pointlimit = 3")
	check(await wait_for(pl, 60.0), "svcmd pointlimit 3")
	Net.console_command("status")
	var st := func() -> bool: return _chat_has("Ded-Test") and _chat_has("Spieler1")
	check(await wait_for(st, 60.0), "status: Server und Spielerliste")
	Net.console_command("vote pointlimit 4")
	var voted := func() -> bool: return _chat_has(Net.tx(8931, "Abstimmung angenommen"))
	check(await wait_for(voted, 60.0), "Abstimmung (1 Spieler): angenommen")
	check(int(Net.settings.get("score_limit", 0)) == 4, "Regel beim Client aktualisiert", str(Net.settings.get("score_limit")))
	# --- Kartenwechsel: bots 2 → 4 KI ---
	Net.console_command("nextmap")
	var b_map := func() -> bool: return Game.current_mission_id == "mp_arctic1_mp" and Game.current_mission() != null \
		and Net._soldiers.has(Net.my_id()) and _bots() >= 4
	check(await wait_for(b_map, 400.0), "nextmap: Karte 2, KI neu erzeugt (bots 2 je Seite)", "%s %d" % [Game.current_mission_id, _bots()])
	check(Net.humans() == 1, "KI-Soldaten belegen keine Spielerplätze", str(Net.humans()))
	check(out_text.contains("Creating H&D2 Server") and out_text.contains("HD2 console"), "Konsolenausgabe des Servers (stdout)")
	_console("listplayers")
	var lp := func() -> bool: return out_text.contains("> listplayers") and out_text.contains("Spieler1")
	check(await wait_for(lp, 60.0), "Konsole (stdin) „listplayers“ gibt die Spielerliste aus")
	# --- Rauswurf über die Server-Konsole, danach quit ---
	_console("kickplayer Spieler1")
	var kicked := func() -> bool: return not Net.is_online and Net.last_error.contains(Net.tx(8871, "Admin"))
	check(await wait_for(kicked, 60.0), "kickplayer: Client getrennt (T8871)", Net.last_error)
	_console("quit")
	var gone := func() -> bool: return not OS.is_process_running(_pid)
	check(await wait_for(gone, 60.0), "quit beendet den dedizierten Server")
	if OS.is_process_running(_pid):
		OS.kill(_pid)
	await _autorestart_part()
	_finish()


## autorestart (Original „hd2ds.exe -autorestart“): Wächter startet den Server als Kindprozess und nach einem Absturz
## neu; maxinactivity: Spieler ohne Eingabe wird mit Originaltext 8872 getrennt
func _autorestart_part() -> void:
	var port2 := DPORT + 2
	var cfg := ProjectSettings.globalize_path("res://test_output/test_dedicated_ar.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(["sessionname \"Ded-AR\"", "style deathmatch", "mapname mp_arctic2_mp",
		"port %d" % port2, "warmup 0", "pointlimit 0", "roundlimit 0", "respawntime 5", "maxinactivity 4", "autorestart 1",
		"server"])) + "\n")
	f.close()
	out_text = ""
	var r := OS.execute_with_pipe(OS.get_executable_path(), ["--headless", "--log-file",
		ProjectSettings.globalize_path("res://test_output/dedicated_watchdog.log")] + _project_args() + ["--", "--dedicated=" + cfg], false)
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	_pid = int(r.get("pid", 0))
	var child := func() -> int:
		var rx := RegEx.create_from_string("AUTORESTART: Server-Prozess (\\d+) gestartet")
		var ms := rx.search_all(out_text)
		return int(ms[ms.size() - 1].get_string(1)) if not ms.is_empty() else 0
	var started := func() -> bool: return child.call() > 0
	check(await wait_for(started, 60.0), "autorestart: Wächter startet den Server als Kindprozess", out_text.substr(0, 200))
	var c1: int = child.call()
	# erst die Serverabfrage abwarten (Karte geladen), dann beitreten und still stehen → Rauswurf (maxinactivity 4 s)
	var addr0 := "127.0.0.1:%d" % port2
	Net.fav_info.clear()
	Net.favorites = [addr0]
	Net.browsing_favorites = true
	var up := func() -> bool: return Net.fav_info.has(addr0)
	await wait_for(up, 300.0)
	Net.browsing_favorites = false
	Net.favorites = []
	Net.local_name = "Steher"
	Net.join("127.0.0.1", port2)
	var ing := func() -> bool: return Game.current_mission() != null and Net._soldiers.has(Net.my_id())
	check(await wait_for(ing, 300.0), "autorestart-Server: beigetreten")
	var kicked := func() -> bool: return not Net.is_online and Net.last_error.contains("Inaktivit")
	check(await wait_for(kicked, 120.0), "maxinactivity: ohne Eingabe getrennt (T8872)", Net.last_error)
	var menu_back := func() -> bool: return Game.current_mission() == null
	check(await wait_for(menu_back, 60.0), "Nach dem Rauswurf zurück im Hauptmenü")
	# Absturz simulieren: Kindprozess beenden → Wächter startet neu, Server antwortet wieder
	if c1 > 0:
		OS.kill(c1)
	var restarted := func() -> bool: return out_text.contains("Neustart 1") and child.call() != c1 and child.call() > 0
	check(await wait_for(restarted, 60.0), "autorestart: nach Absturz neu gestartet", out_text.substr(maxi(out_text.length() - 300, 0)))
	var addr := "127.0.0.1:%d" % port2
	Net.fav_info.clear()
	Net.favorites = [addr]
	Net.browsing_favorites = true
	var answers := func() -> bool: return Net.fav_info.has(addr) and String(Net.fav_info[addr].get("name", "")) == "Ded-AR"
	check(await wait_for(answers, 300.0), "autorestart: neu gestarteter Server antwortet (Abfrage)")
	Net.browsing_favorites = false
	Net.favorites = []
	_console("quit")
	var w_gone := func() -> bool: return not OS.is_process_running(_pid)
	check(await wait_for(w_gone, 90.0), "quit beendet Server und Wächter")
	for p in [_pid, child.call()]:
		if int(p) > 0 and OS.is_process_running(int(p)):
			OS.kill(int(p))


## Exportierter Build (Spieltest): kein Projektpfad – die EXE startet sich selbst; im Editor-Binary: --path
func _project_args() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	if OS.has_feature("template"):
		return []
	return ["--path", ProjectSettings.globalize_path("res://")]
