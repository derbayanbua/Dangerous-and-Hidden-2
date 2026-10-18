extends "res://tests/screenshots_fpv.gd"
## Kontrollbilder HUD rechts unten (tabl02: Waffe Hand/Schulter + Munition) und Waffenhaltung 3./1. Person:
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots_hud_weapons [--shots=h01,h06]
## Ausgabe: test_output/shot_h*.png (h01–h05 HUD-Ausschnitt ×3 mit Gewehr/MP/Pistole/Granate/Panzerfaust,
## h06 Bazooka im Anschlag, h07–h09 linke Hand am Griff stehend/hockend/liegend, h10 Schuss 3. Person,
## h11 Ego-Waffe an der Wand, h12 Panzerfaust-Nachladen 1. Person, h13 Ego-Hände der Uniform).


## Ausschnitt rechts unten (Feld tabl02 des Original-HUD) dreifach vergrößert speichern.
func hud_crop(name: String, m: Mission) -> void:
	if Game.cli.has("shots") and not Array(Game.cli["shots"].split(",")).has(name.substr(0, 3)):
		return
	await frames(6)
	var img := get_viewport().get_texture().get_image()
	var oh: OrigHud = m.hud.orig_hud
	var r: Rect2 = oh.elements["tabl02"]["screen"]
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var rr := Rect2i(Vector2i((r.position - Vector2(6, 6)) * k), Vector2i((r.size + Vector2(12, 12)) * k))
	var crop := img.get_region(rr)
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT + "shot_%s.png" % name)
	img.save_png(OUT + "shot_%s_voll.png" % name)
	print("SHOT ", name, " Hand=", oh.icon_of("i_hands"), " Schulter=", oh.icon_of("i_shoulder"), " Text=",
		oh.ammo_labels["hands"].text, " | ", oh.ammo_labels["name"].text, " | ", oh.ammo_labels["shoulder"].text, " | G ",
		oh.ammo_labels["grenades"].text)


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
	var rig: CameraRig = m.rig
	m.hud._obj_panel.visible = false
	# --- HUD rechts unten ---
	s.equip(["enfield", "colt", "no36", "panzerfaust", "knife"])
	await frames(60)
	await hud_crop("h01_hud_gewehr", m)
	s.equip(["thompson", "colt", "no36", "panzerfaust", "knife"])
	await frames(30)
	await hud_crop("h02_hud_mp", m)
	s.select_slot(WeaponData.Slot.SIDEARM)
	await frames(30)
	await hud_crop("h03_hud_pistole", m)
	s.select_slot(WeaponData.Slot.GRENADE)
	await frames(30)
	await hud_crop("h04_hud_granate", m)
	s.select_slot(WeaponData.Slot.LAUNCHER)
	s.current_weapon().reserve = 2
	await frames(30)
	await hud_crop("h05_hud_panzerfaust", m)
	# --- 3. Person mit Beobachterkamera ---
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.fov = 40
	# Spielkamera auf einen anderen Soldaten: sonst schaltet Zielen mit Zoomwaffe die Figur in die Ego-Ansicht
	rig.set_target(m.squad.members[1])
	s.equip(["enfield", "colt", "no36", "bazooka", "knife"])
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await frames(80)
	s.aiming = true
	m.controller.set_process(false)
	m.controller.set_physics_process(false)
	await secs(1.2)
	cam.global_position = s.global_position + Vector3(1.9, 1.6, -1.2)
	cam.look_at(s.global_position + Vector3(0, 1.45, -0.3))
	cam.current = true
	await snap("h06_bazooka_anschlag")
	cam.global_position = s.global_position + Vector3(0.3, 1.7, 2.2)
	cam.look_at(s.global_position + Vector3(0, 1.45, 0))
	await snap("h06b_bazooka_hinten")
	s.aiming = false
	s.select_slot(WeaponData.Slot.PRIMARY)
	await secs(1.2)
	var names := ["h07_ik_stehen", "h08_ik_hocken", "h09_ik_liegen"]
	var hts := [1.35, 0.95, 0.35]
	var st_list := [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]
	for i in 3:
		s.stance_request = st_list[i]
		await secs(1.8)
		s.aiming = true
		await secs(1.0)
		var h: float = hts[i]
		cam.global_position = s.global_position + Vector3(-1.4, h + 0.25, -1.3)
		cam.look_at(s.global_position + Vector3(0, h, -0.3))
		print("IK ", names[i], " Fehler=", s.model.left_hand_error())
		await snap(names[i])
		s.aiming = false
		await secs(0.4)
	s.stance_request = Soldier.Stance.STAND
	await secs(1.8)
	# Schuss in der 3. Person (Feuerclip + Rückstoß)
	s.current_weapon().in_mag = 5
	s.trigger = true
	await secs(0.08)
	s.trigger = false
	cam.global_position = s.global_position + Vector3(2.2, 1.5, -1.0)
	cam.look_at(s.global_position + Vector3(0, 1.35, -0.3))
	await snap("h10_schuss_3rd")
	await secs(1.0)
	m.controller.set_process(true)
	m.controller.set_physics_process(true)
	cam.current = false
	rig.set_target(s)
	rig.camera.current = true
	# --- 1. Person an einer Wand: Waffe ragt nicht hindurch ---
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(6, 4, 0.3)
	cs.shape = bx
	wall.add_child(cs)
	var wm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bx.size
	wm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.42)
	wm.material_override = mat
	wall.add_child(wm)
	m.add_child(wall)
	wall.global_position = s.global_position + Vector3(0, 1.5, -0.55)
	rig.toggle_mode()
	await secs(1.2)
	await snap("h11_ego_wand")
	wall.queue_free()
	await secs(0.3)
	await snap("h13_ego_haende_uniform")
	# Panzerfaust-Nachladen in der 1. Person
	s.equip(["enfield", "colt", "no36", "panzerfaust", "knife"])
	s.select_slot(WeaponData.Slot.LAUNCHER)
	await secs(2.6)
	var pf := s.current_weapon()
	pf.in_mag = 0
	pf.reserve = 2
	s.reload()
	await secs(1.6)
	await snap("h12_panzerfaust_nachladen_1st")
	await secs(2.2)
	await snap("h12b_panzerfaust_nachladen_1st_spaet")
	await secs(2.0)
	rig.toggle_mode()
	# Scharfschützenschuss-Serie (K98 mit Zielfernrohr): vor, während, nach dem Schuss, Repetieren, Nachladen
	s.equip(["o_13", "colt", "no36", "panzerfaust", "knife"])
	await secs(1.5)
	s.current_weapon().in_mag = 1
	Input.action_press("aim")
	await secs(1.2)
	await snap("h14_sniper_a_vor")
	Input.action_press("fire")
	await secs(0.05)
	Input.action_release("fire")
	await snap("h14_sniper_b_schuss")
	await secs(0.25)
	await snap("h14_sniper_c_rueckstoss")
	await secs(0.6)
	await snap("h14_sniper_d_repetieren")
	s.reload()
	await secs(1.0)
	await snap("h14_sniper_e_nachladen")
	await secs(s.current_weapon().data.reload_time + 0.8)
	await snap("h14_sniper_f_wieder_im_zielfernrohr")
	Input.action_release("aim")
	await secs(0.5)
	get_tree().quit()
