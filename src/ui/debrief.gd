extends Control
## Nachbesprechung nach Missionsende.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.11, 0.08)
	add_child(bg)
	var r: Dictionary = Game.last_result
	var v := UIKit.centered_panel(self, 640)
	UIKit.title("AUFTRAG ERFÜLLT" if r.get("success", false) else "AUFTRAG GESCHEITERT", 34, v)
	var l := Label.new()
	var lines: Array[String] = [r.get("reason", ""), ""]
	for o in r.get("objectives", []):
		var mark: String = ["offen", "erfüllt", "verfehlt", "nicht aktiviert"][o[1]]
		lines.append("%-48s %s%s" % [o[0], mark, " (optional)" if o[2] else ""])
	var st: Dictionary = r.get("stats", {})
	var t := int(r.get("time", 0.0))
	lines.append("")
	lines.append("Einsatzdauer: %d:%02d min" % [t / 60, t % 60])
	lines.append("Ausgeschaltete Gegner: %d" % st.get("kills", 0))
	lines.append("Abgegebene Schüsse (alle): %d" % st.get("shots", 0))
	lines.append("Alarm ausgelöst: %s" % ("ja" if st.get("alarm", false) else "nein"))
	var fallen: Array = r.get("fallen", [])
	lines.append("Gefallen: %s" % (", ".join(fallen) if not fallen.is_empty() else "niemand"))
	var idx := Game.CAMPAIGN_ORDER.find(r.get("mission", ""))
	if r.get("success", false) and idx >= 0 and idx + 1 < Game.CAMPAIGN_ORDER.size():
		lines.append("")
		lines.append("Freigeschaltet: %s" % Game.MISSIONS[Game.CAMPAIGN_ORDER[idx + 1]]["title"])
	l.text = "\n".join(lines)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	UIKit.button("Erneut spielen", func(): Game.start_mission(r.get("mission", "m01_funkfeuer")), row)
	UIKit.button("Hauptmenü", Game.return_to_menu, row)
