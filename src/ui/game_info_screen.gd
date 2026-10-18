class_name GameInfoScreen
extends OrigScreen
## Original „SPIEL-INFO“ / „INFO ZUM AUSGEWÄHLTEN SPIEL“ (T2312/T2568) nach MODELS\gameinfo.4ds (hd2.exe 0x62F3E0):
##  links  TEAM-STATUS (T2569): Zeilen „allied“/„axis“ mit Teampunkten, Siegen, Spielern;
##         SPIELER-STATUS (T2570) als Liste LB_Players (table00, Bildlauf scroll00) mit Getötet (T2593) / Punkte (T2594)
##  rechts SERVER INFO (T2571–2579) und SPIELREGELN (T2580–2592) des gewählten Servers
##  Knöpfe SPIEL-INFO FORTSETZEN (T2565, Abfrage erneuern), SPIEL BEITRETEN (T2566), ZURÜCK (T2567)
## Daten: Serverinfo der LAN-Liste bzw. Favoriten (Net.server_info über Broadcast/Abfrage Port + 1).

signal join_requested(info: Dictionary)
signal closed

const ROW_H := 21.0
var info := {}
var key := ""                    ## „ip:port“ für die Aktualisierung
var list_ofs := 0


func open(server: Dictionary) -> void:
	info = server.duplicate(true)
	key = String(server.get("key", "%s:%d" % [server.get("ip", ""), int(server.get("port", Net.PORT))]))
	setup_stage()
	Net.servers_updated.connect(_on_update)
	build()


func _exit_tree() -> void:
	if Net.servers_updated.is_connected(_on_update):
		Net.servers_updated.disconnect(_on_update)


func _on_update() -> void:
	var fresh: Dictionary = Net.servers.get(key, Net.fav_info.get(key, {}))
	if not fresh.is_empty():
		var k := key
		info = fresh.duplicate(true)
		info["key"] = k
		build()


func refresh() -> void:
	Net.query_server(String(info.get("ip", "")), int(info.get("port", Net.PORT)))


static func _yn(v) -> String:
	return SAS.text(2001, "JA") if bool(v) else SAS.text(2000, "NEIN")


func build() -> void:
	begin("gameinfo")
	title(2568, "INFO ZUM AUSGEWÄHLTEN SPIEL")
	text_at("text_team status", SAS.text(2569, "TEAM-STATUS"), 16)
	var ts: Array = info.get("ts", [0, 0])
	var w: Array = info.get("w", [0, 0])
	var plist: Array = info.get("plist", [])
	var team_mode := int(info.get("mode", 0)) != Net.Mode.DEATHMATCH
	for side in [["allied", Soldier.TEAM_ALLIED, "Alliierte"], ["axis", Soldier.TEAM_AXIS, "Achsenmächte"]]:
		draw_frame(side[0])
		var n := 0
		for p in plist:
			if int(p[1]) == int(side[1]):
				n += 1
		var t: int = side[1]
		var txt: String = String(side[2]) + "   –"
		if team_mode:
			txt = "%s   %s %d   %s %d   %s %d" % [side[2], SAS.text(2594, "Punkte"), int(ts[t]) if t < ts.size() else 0,
				"Siege", int(w[t]) if t < w.size() else 0, SAS.text(2306, "SPIELER").capitalize(), n]
		label(rect(side[0], Rect2(68, 135, 414, 36)).grow_individual(-48, 0, -6, 0), txt, 14).name = "Team_" + String(side[0])
	# Spieler-Status (Liste)
	text_at("text_", "%s" % SAS.text(2570, "SPIELER-STATUS"), 14)
	var hr := rect("text_", Rect2(68, 240, 414, 18))
	label(Rect2(hr.position.x + 250, hr.position.y, 75, hr.size.y), SAS.text(2593, "Getötet"), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	label(Rect2(hr.position.x + 330, hr.position.y, 75, hr.size.y), SAS.text(2594, "Punkte"), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_frames(["table00", "scroll00", "sliderbase"])
	var area := rect("text_status", Rect2(121, 268, 351, 427))
	_rows = int(area.size.y / ROW_H)
	var sorted_p := plist.duplicate()
	sorted_p.sort_custom(func(a, b): return int(a[3]) > int(b[3]))
	list_ofs = clampi(list_ofs, 0, maxi(sorted_p.size() - _rows, 0))
	for i in range(list_ofs, mini(sorted_p.size(), list_ofs + _rows)):
		var p: Array = sorted_p[i]
		var y := area.position.y + (i - list_ofs) * ROW_H
		var team_t := ""
		if team_mode and int(p[1]) in [0, 1]:
			team_t = " [%s]" % Net.team_name(int(p[1]))
		var pl := label(Rect2(area.position.x - 40, y, 230, ROW_H), "%s%s%s" % [String(p[0]), team_t,
			" (KI)" if p.size() > 4 and bool(p[4]) else ""], 13)
		pl.name = "Player%d" % i
		label(Rect2(area.position.x + 199, y, 75, ROW_H), str(int(p[2])), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT)
		label(Rect2(area.position.x + 279, y, 75, ROW_H), str(int(p[3])), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	orig_button("barrow up", "", _scroll.bind(-1), list_ofs > 0, "ListUp")
	orig_button("barrow down", "", _scroll.bind(1), list_ofs + _rows < sorted_p.size(), "ListDown")
	# Server-Info und Spielregeln
	text_at("text_01", "\n".join(info_lines()), 14, HORIZONTAL_ALIGNMENT_LEFT, INK, true, Rect2(525, 115, 414, 464)).name = "Info"
	orig_button("brefresh status", SAS.text(2565, "SPIEL-INFO FORTSETZEN"), refresh, true, "InfoRefresh")
	orig_button("bjoin game", SAS.text(2566, "SPIEL BEITRETEN"), func(): join_requested.emit(info),
		not bool(info.get("offline", false)), "InfoJoin")
	orig_button("breturn", SAS.text(2567, "ZURÜCK"), func(): closed.emit(), true, "InfoBack")


var _rows := 20


func _scroll(d: int) -> void:
	list_ofs += d * _rows
	build()


## Zeilen der rechten Seite: SERVER INFO (T2571–2579) und SPIELREGELN (T2580–2592)
func info_lines() -> PackedStringArray:
	var r: Dictionary = info.get("rules", {})
	var t := func(id: int, fb: String) -> String: return SAS.text(id, fb).strip_edges()
	var same := String(info.get("tag", Net.PROTOCOL)) == Net.PROTOCOL and \
		String(info.get("ver", "")) == String(ProjectSettings.get_setting("application/config/version"))
	var ping := int(info.get("ping", -1))
	var mode := int(info.get("mode", 0))
	var out: PackedStringArray = [t.call(2571, "SERVER INFO"),
		"%s %s" % [t.call(2572, "Server-Name:"), String(info.get("name", "?"))],
		"%s %s:%d" % [t.call(2573, "Server-IP:"), String(info.get("ip", "")), int(info.get("port", Net.PORT))],
		"%s %s" % [t.call(2574, "Ping:"), ("%d ms" % ping) if ping >= 0 else "–"],
		"%s %d / %d%s" % [t.call(2575, "Spieler:"), int(info.get("players", 0)), int(info.get("max", 0)),
			(" (+%d KI)" % int(info.get("bots", 0))) if int(info.get("bots", 0)) > 0 else ""],
		"%s %s" % [t.call(2576, "Dedizierter Server:"), _yn(info.get("ded", false))],
		"%s %s" % [t.call(2577, "Passwort:"), _yn(info.get("pw", false))],
		"%s %s" % [t.call(2578, "Internet-Server:"), _yn(info.get("inet", false))],
		"%s: %s" % [t.call(2579, "Selbe Version"), _yn(same)],
		"", t.call(2580, "SPIELREGELN"),
		"%s %s" % [t.call(2581, "Spiel-Art:"), ServerFilterScreen.style_name(mode)],
		"%s %s" % [t.call(2582, "Aktueller Kartenname:"), String(info.get("map_title", info.get("map", "")))],
		"%s %d" % [t.call(2583, "Zu tötende Gegner:"), int(r.get("score_limit", 0))],
		"%s %d min" % [t.call(2584, "Runden-Limit:"), int(r.get("time_limit_min", 0))],
		"%s %d / %d" % [t.call(2585, "Rundenzahl:"), int(info.get("rn", 1)), int(r.get("round_count", 1))],
		"%s %d s" % [t.call(2586, "Vorlaufzeit:"), int(r.get("warmup_s", 0))],
		"%s %d s" % [t.call(2587, "Respawn-Zeit:"), int(r.get("respawn_s", 0))],
		"%s %s" % [t.call(2588, "Respawn erlauben:"), _yn(r.get("allow_respawn", false))],
		"%s %s" % [t.call(2589, "Friendly Fire:"), _yn(r.get("friendly_fire", false))],
		"%s %s" % [t.call(2590, "Autom. Teamausgleich:"), _yn(r.get("team_balance", false))],
		"%s %s" % [t.call(2591, "3.-Person-Ansicht:"), _yn(r.get("third_person", false))],
		"%s %d s" % [t.call(2592, "Spawn-Schutz-Zeit:"), int(r.get("spawn_protect_s", 0))],
		# Ergänzungen (kein Original-Text): Kill-Cam, Namen über Spielern, Trefferanzeige
		"Kill-Cam: %s" % _yn(r.get("kill_cam", false)),
		"Namen über Spielern: %s" % _yn(r.get("show_names", true)),
		"Trefferanzeige: %s" % _yn(r.get("hit_indicator", true))]
	return out
