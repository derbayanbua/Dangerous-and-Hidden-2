extends Control
## Hauptmenü mit Einsatzbesprechung.

var _menu: VBoxContainer
var _brief_root: Control
var _ver: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.11, 0.12, 0.09)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.custom_minimum_size.x = 8
	stripe.color = UIKit.ACCENT
	add_child(stripe)
	_menu = UIKit.centered_panel(self)
	UIKit.title("DANGEROUS HIDDEN 2", 40, _menu)
	var sub := Label.new()
	sub.text = "Taktische Kommandoeinsätze 1944"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.66, 0.55))
	_menu.add_child(sub)
	_menu.add_child(HSeparator.new())
	var n := 1
	for id in Game.CAMPAIGN_ORDER:
		var unlocked := Game.is_unlocked(id)
		var done: bool = Game.campaign.get("completed", []).has(id)
		var label := "%d. %s%s" % [n, Game.MISSIONS[id]["title"], "  ✓" if done else ""]
		var b := UIKit.button(label if unlocked else "%d. — gesperrt —" % n, _show_briefing.bind(id), _menu)
		b.disabled = not unlocked or Game.alive_roster().is_empty()
		n += 1
	var prac := Label.new()
	prac.text = "Übungseinsätze (eigene Entwürfe, kein Original-Level)"
	prac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prac.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	_menu.add_child(prac)
	for id in Game.PRACTICE_MISSIONS:
		var pb := UIKit.button("Ü. %s" % Game.MISSIONS[id]["title"], _show_briefing.bind(id), _menu)
		pb.disabled = Game.alive_roster().is_empty()
	if Game.alive_roster().is_empty():
		var over := Label.new()
		over.text = "Der gesamte Kader ist gefallen. Kampagne beendet."
		over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		over.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
		_menu.add_child(over)
	UIKit.button("Neue Kampagne", func():
		Game.new_campaign()
		get_tree().reload_current_scene(), _menu)
	var load_b := UIKit.button("Spielstand laden", func(): Game.load_game("quick"), _menu)
	load_b.disabled = not Game.has_save("quick")
	UIKit.button("Optionen", _options, _menu)
	UIKit.button("Beenden", func(): get_tree().quit(), _menu)
	var ver := Label.new()
	ver.text = "v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]]
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	add_child(ver)
	_ver = ver


func _options() -> void:
	add_child(load("res://src/ui/options_menu.gd").new())


func _show_briefing(id: String) -> void:
	_menu.get_parent().get_parent().visible = false
	_ver.visible = false
	_brief_root = Control.new()
	_brief_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_brief_root)
	var v := UIKit.centered_panel(_brief_root, 820)
	UIKit.title("EINSATZBESPRECHUNG — %s" % Game.MISSIONS[id]["title"].to_upper(), 26, v)
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.text = Game.briefing_text(id)
	text.custom_minimum_size = Vector2(760, 190)
	text.fit_content = false   # feste Höhe, scrollt bei langen Briefings
	text.scroll_active = true
	v.add_child(text)
	v.add_child(HSeparator.new())
	_build_loadout(v)
	v.add_child(HSeparator.new())
	var keys := Label.new()
	keys.add_theme_font_size_override("font_size", 14)
	keys.text = _controls_summary()
	v.add_child(keys)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	UIKit.button("Zurück", func():
		_brief_root.queue_free()
		_ver.visible = true
		_menu.get_parent().get_parent().visible = true, row)
	UIKit.button("Einsatz beginnen", func(): Game.start_mission(id), row)


## Ausrüstung je Soldat: Primärwaffe und Granaten (Seitenwaffe fest: Colt).
func _build_loadout(parent: Control) -> void:
	var title := Label.new()
	title.text = "AUSRÜSTUNG"
	title.add_theme_color_override("font_color", UIKit.ACCENT)
	parent.add_child(title)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	parent.add_child(g)
	var fallen_names: Array[String] = []
	for x in Game.ROSTER + Game.RESERVE:
		if Game.is_fallen(x["pid"]):
			fallen_names.append(x["name"])
	if not fallen_names.is_empty():
		var fl := Label.new()
		fl.text = "Gefallen: " + ", ".join(fallen_names) + " — Ersatz aus der Reserve rückt nach."
		fl.add_theme_color_override("font_color", Color(0.75, 0.45, 0.38))
		parent.add_child(fl)
	for r in Game.alive_roster():
		var pid: String = r["pid"]
		var lo: Array = Game.loadout_for(pid).duplicate()
		var name_l := Label.new()
		name_l.text = r["name"] + ("  (Ersatz)" if Game.RESERVE.has(r) else "")
		name_l.custom_minimum_size.x = 180
		g.add_child(name_l)
		var prim := OptionButton.new()
		prim.custom_minimum_size.x = 300
		for i in Game.ALLIED_PRIMARIES.size():
			var wd := WeaponDB.get_weapon(StringName(Game.ALLIED_PRIMARIES[i]))
			prim.add_item("%s  (%s, %d Schuss)" % [wd.display_name, wd.caliber, wd.magazine_size], i)
			if Game.ALLIED_PRIMARIES[i] == lo[0]:
				prim.select(i)
		g.add_child(prim)
		var gren := CheckBox.new()
		gren.text = "Granaten"
		gren.button_pressed = lo[2] != ""
		g.add_child(gren)
		var update := func(_x = null):
			Game.loadouts[pid] = [Game.ALLIED_PRIMARIES[prim.selected], "colt", "no36" if gren.button_pressed else ""]
		prim.item_selected.connect(update)
		gren.toggled.connect(update)
		update.call()


func _controls_summary() -> String:
	var k := func(a): return InputSetup.binding_text(a)
	return ("Bewegen %s%s%s%s · Rennen %s · Schleichen %s · Hocken %s · Liegen %s · Lehnen %s/%s\n" +
		"Feuern %s · Zielen %s · Nachladen %s · Waffen 1–3 · Benutzen %s · Kamera %s\n" +
		"Soldat wählen F1–F4 · Befehle: Bewegen %s · Folgen %s · Halten %s · Feuer frei/halten %s · Formation %s · Haltung %s\n" +
		"Taktische Karte %s · Ziele %s · Schnellspeichern %s · Schnellladen %s") % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"),
		k.call("run"), k.call("sneak"), k.call("stance_crouch"), k.call("stance_prone"),
		k.call("lean_left"), k.call("lean_right"), k.call("fire"), k.call("aim"), k.call("reload"),
		k.call("interact"), k.call("camera_toggle"), k.call("order_move"), k.call("order_follow"),
		k.call("order_hold"), k.call("order_roe"), k.call("order_formation"), k.call("order_stance"),
		k.call("tactical_map"), k.call("objectives"), k.call("quicksave"), k.call("quickload")]
