extends "res://tests/test_orig_complete.gd"
## Kontrollbilder (Fenster) eines Original-Einsatzes während des Lösers test_orig_complete (Agent Afrika):
##   tools\godot.cmd -- --mission=af1_spaghetti_airport --autoplay=shots_orig_afrika [--speed=1]
## Bilder test_output/afrika/<id>_<nn>_<anlass>.png: Intro-Sequenz, Start, jede Zieländerung (höchstens alle 8 s),
## Missionsende. Ergebnis wie test_orig_complete (ERFUELLBAR-Zeile).

const SHOT_DIR := "res://test_output/afrika/"
var _shot_n := 0
var _last_shot_ms := -100000
var _final_done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	super._ready()
	Events.objective_updated.connect(_on_obj_shot)
	_start_shots.call_deferred()


func _snap(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var id := String(Game.current_mission_id)
	var p := SHOT_DIR + "%s_%02d_%s.png" % [id, _shot_n, tag.validate_filename()]
	_shot_n += 1
	img.save_png(p)
	var lead: Soldier = null
	if mission() and mission().squad:
		lead = mission().squad.leader()
	print("SHOT %s %s" % [p, str(lead.global_position) if lead else "-"])


func _start_shots() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	await _snap("intro")
	# nach dem Überspringen der Intro-Sequenz (Löser: 1 s nach dem Laden)
	await get_tree().create_timer(4.0, true, false, true).timeout
	await _snap("start")


func _on_obj_shot(id: StringName) -> void:
	if _final_done or Time.get_ticks_msec() - _last_shot_ms < 8000:
		return
	_last_shot_ms = Time.get_ticks_msec()
	var o: Objective = mission().objective(id) if mission() else null
	await _snap("ziel_%s_%d" % [id, o.state if o else -1])


func _report() -> void:
	if not _final_done:
		_final_done = true
		await _snap("ende")
	super._report()
