extends "res://tests/test_gameplay.gd"
## Hilfen für die LAN-Ende-zu-Ende-Tests: echte Mausklicks/Tastatureingaben über den Viewport (statt
## Funktionsaufrufe), damit Sichtbarkeit, Sperren und Signalverdrahtung der Menüs mitgeprüft werden.


func visible_button(text: String) -> Button:
	for b in get_tree().root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.is_visible_in_tree() and (bt.text == text or String(bt.name).contains(text.validate_node_name())):
			return bt
	return null


func _screen_point(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	get_tree().root.push_input(mv, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		get_tree().root.push_input(ev, true)
		await get_tree().process_frame


## Klick auf die Mitte eines Steuerelements; true, wenn es sichtbar, bedienbar und im Fenster liegt
func click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	var p := _screen_point(c, c.size * 0.5)
	if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(p):
		return false
	await click_at(p)
	return true


func click_item(list: ItemList, i: int) -> void:
	await click_at(_screen_point(list, list.get_item_rect(i).get_center()))


## Text in ein Eingabefeld tippen (Fokus per Klick, Inhalt vorher markieren und ersetzen)
func type_into(e: LineEdit, text: String) -> void:
	await click(e)
	e.select_all()
	for ch in text:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.pressed = pressed
			ev.unicode = ch.unicode_at(0)
			ev.keycode = OS.find_keycode_from_string(ch.to_upper())
			get_tree().root.push_input(ev, true)
		await get_tree().process_frame


func press_action(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		get_tree().root.push_input(ev, true)
		await get_tree().process_frame


## Profil anlegen (wie über „PROFIL ERSTELLEN“) und Hauptmenü neu aufbauen
func menu_with_profile(pname: String) -> Node:
	for i in 30:
		await get_tree().process_frame
	Game.create_profile(pname, 2)
	var menu := get_tree().current_scene
	menu.show_menu("main_menu")
	await get_tree().process_frame
	return menu


func wait_for(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


## Pausenmenü (Esc) öffnen und „Zum Hauptmenü“ anklicken; prüft Mehrspieler-Sperren
func leave_via_pause_menu(who: String) -> void:
	await press_action("pause")
	await frames(3)
	# Original-Pausemenü (main ingame.4ds): ZURÜCK ZUM HAUPTMENÜ (T2522) bzw. SPEICHERN (T2518, MP gesperrt)
	var back := visible_button("MainMenu")
	var save := visible_button("Save")
	check(back != null and not get_tree().paused, who + ": Pausenmenü offen, Spiel läuft weiter (Mehrspieler)")
	check(save != null and save.disabled, who + ": Schnellspeichern im Mehrspieler gesperrt")
	check(await click(back), who + ": „Zum Hauptmenü“ angeklickt")
	var in_menu := func() -> bool: return not Net.is_online and Game.current_mission() == null and visible_button("bmultiplayerlan") != null
	var ok: bool = await wait_for(in_menu, 90.0)
	check(ok, who + ": Verbindung beendet, zurück im Hauptmenü")
