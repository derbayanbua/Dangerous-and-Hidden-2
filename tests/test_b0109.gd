extends "res://tests/test_gameplay.gd"
## 0.10.9 Akteursdefinitionen in actors.bin ohne Tiefengrenze (tools/fmt_scene2.parse_actor_defs, hd2.exe liest die
## verschachtelten 0xAE21 sequentiell über den Chunk-Stapel, docs/re_notes_actors_items.md §1a).
## Prüft Akteurzahlen, neue Lichtschalter/Fässer/Menschen/Spielerstarts und dass nichts doppelt angelegt wird.
##   tools\godot.cmd --headless -- --mission=cz1_eintrittsgeld --autoplay=test_b0109
##   tools\godot.cmd --headless -- --mission=no1_leuchtturm --autoplay=test_b0109

const EXPECT := {"czech1": 107, "normandy": 146, "normandy_mp": 100}


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.interactive != null, "Originalmission geladen")
	if m == null or m.interactive == null:
		_finish()
		return
	for mem in m.squad.members:
		if is_instance_valid(mem):
			mem.max_health = 100000.0
			mem.health = mem.max_health
	var dir := String(m.orig.mission_dir)
	var key := dir.get_file().to_lower()

	# --- Akteurzahlen aller drei betroffenen Missionen (Cache) ---
	for k in EXPECT:
		var ap = LsRuntime._read_json(dir.get_base_dir() + "/" + k + "/actor_params.json")
		var n: int = ap.get("actors", {}).size() if typeof(ap) == TYPE_DICTIONARY else -1
		check(n == EXPECT[k], "%s: %d Akteursdefinitionen" % [k, EXPECT[k]], str(n))

	# --- keine Doppelungen: Akteurnamen in scene.json eindeutig, Steuerobjekte je Frame genau einmal ---
	var names := {}
	var dup := []
	for a in m.orig.actors:
		var nm := String(a.get("name", "")).to_lower()
		if names.has(nm):
			dup.append(nm)
		names[nm] = true
	check(dup.is_empty(), "Akteurnamen eindeutig", str(dup))
	var frames := {}
	var dup_ctl := []
	for c in m.interactive.controls.values():
		var f = c.get("frame") if c is Object else null
		if f is Node3D:
			if frames.has(f):
				dup_ctl.append(String(f.name))
			frames[f] = true
	check(dup_ctl.is_empty(), "kein Frame doppelt gesteuert", str(dup_ctl))

	var s: Soldier = m.squad.leader()
	if key == "czech1":
		var ok := 0
		var toggled := 0
		for i in range(1, 19):
			var sw = m.interactive.controls.get("VYPINAC%02d" % i)
			if sw is OrigInteractive.OrigSwitch:
				ok += 1
				var st0: int = sw.state
				sw.interact(s)
				if sw.state != st0 and int(sw.frame.get_meta("actor_state", sw.state)) == sw.state:
					toggled += 1
				sw.interact(s)
		check(ok == 18, "18 Lichtschalter vypinac01…18 als Schalter", str(ok))
		check(toggled == 18, "alle Lichtschalter schalten (Zustand 1↔2)", str(toggled))
		var bar := 0
		for i in range(8, 12):
			if m.interactive.controls.get("K_BARELMIR_%d" % i) is OrigInteractive.OrigBarrel:
				bar += 1
		check(bar == 4, "Fässer k_barelmir_8…11 als Fass-Akteure", str(bar))
		check(int(m.actor_params.get("posila_sklad01", {}).get("actor_type", -1)) == 3, "posila_sklad01: Menschparameter vorhanden")
		check(_humans(m, "posila_sklad01") == 1, "Verstärkung posila_sklad01 genau einmal als Figur", str(_humans(m, "posila_sklad01")))
		# Ge_27_chcanie = Null-Akteur (Typ 33) am Gegner Ge27b_, Träger des Skripts SS1_moc.scr
		check(int(m.actor_params.get("Ge_27_chcanie", {}).get("actor_type", -1)) == 33, "Ge_27_chcanie: Null-Akteur (Typ 33)")
		check(m.ls_runtime.find_frame("Ge_27_chcanie") != null, "Ge_27_chcanie als Frame vorhanden (Skriptträger)")
		check(_humans(m, "Ge_27_chcanie") == 0, "Ge_27_chcanie keine zusätzliche Figur")
	elif key == "normandy":
		var bar := 0
		for k in m.interactive.controls:
			if String(k).begins_with("M_AF") and m.interactive.controls[k] is OrigInteractive.OrigBarrel:
				bar += 1
		check(bar >= 23, "Fässer m_AF*_bar_* als Fass-Akteure (≥ 23)", str(bar))
		var starts := 0
		for i in range(1, 5):
			var f = m.ls_runtime.find_frame("Spawnsingle%02d" % i)
			if f is Soldier and m.squad.members.has(f):
				starts += 1
		check(starts == m.squad.members.size() and starts == 4, "Spawnsingle01…04 = Spielerstarts (Trupp 4)", str(starts))
		check(_humans(m, "N49") == 1, "N49 einmal als Figur angelegt", str(_humans(m, "N49")))
	_finish()


func _humans(m: Mission, nm: String) -> int:
	var n := 0
	for x in m.find_children("*", "CharacterBody3D", true, false):
		if x is Soldier and not m.squad.members.has(x) and (String(x.name) == nm.validate_node_name() or String(x.get_meta("orig_name", "")) == nm):
			n += 1
	return n
