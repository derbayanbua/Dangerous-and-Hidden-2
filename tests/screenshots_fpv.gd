extends "res://tests/screenshots.gd"
## Kontrollbilder Kamera/Zielen/Aktionen mit Original-Figur (en01) und Original-FPV-Modellen:
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots_fpv [--shots=f01,f05]
## Ausgabe: test_output/shot_f*.png (3.-Person-Kamera stehend/hockend/liegend, Zielen Gewehr/Zielfernrohr/MP/
## Pistole, 1. Person, Nachladen 3./1. Person, Granatwurf, Verbandskasten, Panzerfaust nachladen).


## Physikzeit abwarten (Animationen/Nachladen laufen im Physiktakt; das Rendern unter WARP ist langsamer).
func secs(t: float) -> void:
	for i in int(t * 60.0):
		await get_tree().physics_frame


## Bild mitten in einer Aktion: Spiel anhalten, zeichnen lassen, speichern.
func snap(name: String) -> void:
	if Game.cli.has("shots") and not Array(Game.cli["shots"].split(",")).has(name.substr(0, 3)):
		return
	get_tree().paused = true
	await frames(4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "shot_%s.png" % name)
	print("SHOT ", name)
	get_tree().paused = false


func _hold_aim(on: bool) -> void:
	if on:
		Input.action_press("aim")
	else:
		Input.action_release("aim")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 600:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	var s := m.squad.leader()
	for e in m.enemies:
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
	for mm in m.squad.members:
		if mm != s:
			mm.global_position = m.lb.ground(40, 60, 0.3)
			mm.set_physics_process(false)
	var fig := OrigWeapons._load(OrigLevel.cache_root() + "/characters/en01.glb")
	s.model.attach_orig(fig)
	s.global_position = m.lb.ground(3, 34, 0.2)
	s.look_yaw = 0.0
	s.look_pitch = 0.0
	s.equip(["enfield", "colt", "no36", "bazooka", "knife"])
	var rig: CameraRig = m.rig
	await frames(90)
	# 3. Person
	await shot("f01_3rd_stehen")
	s.stance_request = Soldier.Stance.CROUCH
	await frames(70)
	await shot("f02_3rd_hocken")
	s.stance_request = Soldier.Stance.PRONE
	await frames(110)
	await shot("f03_3rd_liegen")
	s.stance_request = Soldier.Stance.STAND
	await frames(110)
	# Zielen Gewehr (Kimme/Korn) auf das Gehöft
	s.look_pitch = 0.02
	_hold_aim(true)
	await frames(60)
	await shot("f04_zielen_gewehr")
	_hold_aim(false)
	await frames(40)
	# Zielfernrohr (Lee-Enfield mit Zielfernrohr, Gegenstand 17)
	s.equip(["o_17", "colt", "no36", "bazooka", "knife"])
	await frames(40)
	_hold_aim(true)
	await frames(60)
	await shot("f05_zielfernrohr")
	_hold_aim(false)
	await frames(40)
	# MP (Thompson) und Pistole (Colt)
	s.equip(["thompson", "colt", "no36", "bazooka", "knife"])
	await frames(90)
	_hold_aim(true)
	await frames(60)
	await shot("f06_zielen_mp")
	_hold_aim(false)
	await frames(30)
	s.select_slot(WeaponData.Slot.SIDEARM)
	await frames(90)
	_hold_aim(true)
	await frames(60)
	await shot("f07_zielen_pistole")
	_hold_aim(false)
	await frames(30)
	s.select_slot(WeaponData.Slot.PRIMARY)
	await frames(90)
	# 1. Person (Hüfte)
	rig.toggle_mode()
	await frames(80)
	await shot("f08_1st_person")
	# Nachladen 1. Person (Mitte der Animation)
	s.current_weapon().in_mag = 3
	s.reload()
	await secs(s.current_weapon().data.reload_time * 0.45)
	await snap("f09_nachladen_1st")
	await secs(2.0)
	rig.toggle_mode()
	await frames(40)
	# Beobachterkamera seitlich für die 3.-Person-Aktionen
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 45
	var side := func():
		cam.global_position = s.global_position + Vector3(2.4, 1.3, 1.2)
		cam.look_at(s.global_position + Vector3(0, 1.1, -0.2))
	s.current_weapon().in_mag = 3
	s.reload()
	side.call()
	cam.current = true
	await secs(s.current_weapon().data.reload_time * 0.45)
	await snap("f10_nachladen_3rd")
	await secs(2.0)
	# Granatwurf (Auslösen ~1,36 s)
	s.quick_grenade()
	await secs(1.0)
	side.call()
	await snap("f11_granatwurf_3rd")
	await secs(5.0)
	# Verbandskasten
	s.health = s.max_health * 0.4
	s.medkits = 2
	s.start_heal([])
	await secs(1.5)
	side.call()
	await snap("f12_verband_3rd")
	await secs(2.0)
	cam.current = false
	rig.camera.current = true
	rig.toggle_mode()
	s.health = s.max_health * 0.4
	s.start_heal([])
	await secs(1.0)
	await snap("f13_verband_1st")
	await secs(2.5)
	rig.toggle_mode()
	# Panzerfaust nachladen (3. Person seitlich)
	s.equip(["thompson", "colt", "no36", "panzerfaust", "knife"])
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await frames(100)
	var pf := s.current_weapon()
	pf.in_mag = 0
	pf.reserve = 2
	s.reload()
	side.call()
	cam.current = true
	await secs(1.5)
	await snap("f14_panzerfaust_nachladen")
	await secs(2.5)
	# Granatwurf in der 1. Person (Granate in der Hand)
	cam.current = false
	rig.camera.current = true
	rig.toggle_mode()
	s.select_slot(WeaponData.Slot.GRENADE)
	await secs(1.5)
	s.quick_grenade()
	await secs(0.6)
	await snap("f15_granatwurf_1st")
	await secs(3.5)
	# Panzerfaust in der 1. Person mit Rakete nachladen (improvisiert: Bazooka-FPV-Clip)
	s.equip(["thompson", "colt", "no36", "panzerfaust", "knife"])
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await secs(2.6)
	var pf2 := s.current_weapon()
	pf2.in_mag = 0
	pf2.reserve = 2
	s.reload()
	await secs(2.2)
	await snap("f16_panzerfaust_nachladen_1st")
	await secs(3.0)
	rig.toggle_mode()
	get_tree().quit()
