extends "res://tests/test_gameplay.gd"
## AFRICA1 Zwischensequenz 10 (Soldat AF1_21 stellen): eigene Figur muss sichtbar sein, auch wenn der Spieler in der
## 1. Person war (vorher blieb der Körper ausgeblendet, CameraRig._apply_head_visibility).
##   tools\godot.cmd -- --mission=af1_spaghetti_airport --autoplay=test_af1_cutscene   (Fenster → Bilder)
## Bilder: test_output/af1_cutscene/*.png


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _process(_d: float) -> void:
	var m := mission()
	if m and m.squad:
		for s in m.squad.members:      # Unverwundbarkeit
			if is_instance_valid(s):
				s.health = s.max_health


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/af1_cutscene"))
	var p := "res://test_output/af1_cutscene/%s.png" % name
	get_viewport().get_texture().get_image().save_png(p)
	print("BILD ", ProjectSettings.globalize_path(p))


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime"):
			break
		await get_tree().process_frame
	await frames(10)
	var m := mission()
	var rt = m.get("runtime") if m else null
	check(rt != null, "AFRICA1 mit Skriptlaufzeit geladen")
	if rt == null:
		_finish()
		return
	# Intro-Sequenzen (1, dann 3 mit Darstellerkopien der SAS) überspringen wie mit der Leertaste, bis Spielbetrieb
	var calm := 0
	var skipped := 0
	while calm < 90 and Time.get_ticks_msec() - t0 < 400000:
		if rt.in_cutscene:
			print("DBG überspringe Sequenz ", rt.cutscene_id)
			rt.end_cutscene()
			skipped += 1
			calm = 0
		else:
			calm += 1
		await get_tree().process_frame
	print("DBG übersprungen=%d" % skipped)
	await frames(10)
	var hidden := []
	for s in m.squad.members:
		if is_instance_valid(s) and s.alive and not s.is_visible_in_tree():
			hidden.append(String(s.name))
	check(hidden.is_empty(), "nach dem Intro: alle Truppmitglieder sichtbar (FRM_SetOn(player,true) aus OnCutsceneDone(3))",
		str(hidden))
	var rig = m.rig
	var me: Soldier = rig.target
	if rig.mode != 1:      # CameraRig.Mode.FIRST
		rig.toggle_mode()
	await frames(5)
	print("DBG fpv=%s model.vis=%s fig=%s me.vis=%s incut=%s fake=%s sca=%s want=%s" % [rig.fpv_active, me.model.visible,
		me.model.orig_figure, me.visible, rt.in_cutscene, rt.fake_cutscene, rig._script_camera(), rig._want_fpv(false)])
	check(not me.model.visible and rig.fpv_active, "1. Person: eigene Figur ausgeblendet (Ausgangslage)")
	rt.auto_skip = false
	var caller := LsVM.new(LsCompiler.new(), null, rt)
	caller.wait = 1000.0
	rt.run_cutscene(10, caller)
	await get_tree().create_timer(1.5).timeout
	check(rt.in_cutscene, "Zwischensequenz 10 läuft")
	check(not rig.fpv_active, "Zwischensequenz: Ego-Ansicht aus")
	# Spielerfigur vor die Sequenzkamera zwischen Kamera und Soldat AF1_21 stellen (Original: Spieler steht beim Stellen
	# vor ihm), damit sie im Bild ist
	var cam := get_viewport().get_camera_3d()
	var off: Node3D = rt.actors.get("AF1_21") if "actors" in rt else null
	if cam and off:
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		var p: Vector3 = cam.global_position + fwd.normalized() * 3.0
		p.y = off.global_position.y
		me.global_position = p
		me.look_yaw = atan2(-(off.global_position.x - p.x), -(off.global_position.z - p.z))
		me.velocity = Vector3.ZERO
	print("DBG cam=%s off=%s" % [cam, off])
	await frames(10)
	var vis_all := true
	for s in m.squad.members:
		if is_instance_valid(s) and s.alive and s.model:
			var mv: bool = s.model.is_visible_in_tree() and s.model.head.visible
			if s.model.orig_figure:
				mv = mv and s.model.orig_figure.is_visible_in_tree()
			print("DBG %s vis=%s head=%s s.vis=%s m.vis=%s fig=%s" % [s.name, s.model.is_visible_in_tree(), s.model.head.visible,
				s.visible, s.model.visible, s.model.orig_figure.visible if s.model.orig_figure else null])
			vis_all = vis_all and mv
	check(vis_all, "Zwischensequenz: Körper aller Truppmitglieder sichtbar (auch Spielerfigur)")
	await _shot("cutscene10_a")
	await get_tree().create_timer(1.5).timeout
	await _shot("cutscene10_b")
	rt.call_api(caller, "CSC_ENDCUTSCENE", [])
	await get_tree().create_timer(1.0).timeout
	print("DBG nach: incut=%s fake=%s fpv=%s mode=%s want=%s m.vis=%s" % [rt.in_cutscene, rt.fake_cutscene, rig.fpv_active,
		rig.mode, rig._want_fpv(false), me.model.visible])
	check(not rt.in_cutscene and rig.fpv_active and not me.model.visible, "nach der Sequenz wieder 1. Person, Figur aus")
	_finish()
