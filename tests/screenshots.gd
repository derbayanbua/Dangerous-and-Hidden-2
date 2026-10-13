extends Node
## Erzeugt Kontroll-Screenshots (benötigt Fenster/Renderer, nicht headless):
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=screenshots
## Ausgabe: test_output/shot_*.png

const OUT := "res://test_output/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Optional: --shots=04,07 erzeugt nur diese Bilder (Rest wird schnell übersprungen)
func shot(name: String) -> void:
	if Game.cli.has("shots") and not Array(Game.cli["shots"].split(",")).has(name.substr(0, 2)):
		return
	await frames(25)
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "shot_%s.png" % name)
	print("SHOT ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 600:
		var m0 := Game.current_mission()
		if m0 and m0.squad and m0.squad.leader():
			break
		await get_tree().process_frame
	var m: Mission = Game.current_mission()
	var hale := m.squad.leader()
	await frames(60)
	await shot("01_start")
	# Gehöft vom Südweg aus (Blick nach Norden)
	hale.global_position = m.lb.ground(4, 40, 0.2)
	hale.look_yaw = 0.05
	hale.look_pitch = 0.05
	for e in m.enemies:
		e.get_node("EnemyBrain").enabled = false
		e.get_node("Perception").set_physics_process(false)
	await shot("02_farm_south")
	# Hockend hinter der Hofmauer
	hale.global_position = m.lb.ground(-29, -10, 0.2)
	hale.look_yaw = -PI * 0.5
	hale.stance_request = Soldier.Stance.CROUCH
	await frames(40)
	await shot("03_crouch_wall")
	# Liegend, Zielen
	hale.stance_request = Soldier.Stance.PRONE
	hale.aiming = true
	await frames(80)
	await shot("04_prone_aim")
	hale.aiming = false
	hale.stance_request = Soldier.Stance.STAND
	await frames(60)
	# Hof von innen, Blick auf Stabsgebäude
	hale.global_position = Vector3(6, m.farm_h + 0.2, -6)
	hale.look_yaw = deg_to_rad(40)
	await shot("05_courtyard")
	# Gegner-Nahaufnahme
	var e: Soldier = m.enemies[3]
	hale.global_position = e.global_position + Vector3(0, 0, 4)
	hale.look_yaw = 0.0
	await shot("06_enemy")
	# 1. Person mit Waffe
	m.rig.toggle_mode()
	hale.global_position = m.lb.ground(3, 30, 0.2)
	hale.look_yaw = 0.0
	hale.aiming = true
	await shot("07_fpv_aim")
	m.rig.toggle_mode()
	hale.aiming = false
	# Taktische Karte über dem Gehöft, ein Soldat mit Bewegungsbefehl
	if not Game.cli.has("shots") or Array(Game.cli["shots"].split(",")).has("08"):
		hale.global_position = m.lb.ground(2, 24, 0.2)
		m.squad.order_one(m.squad.members[2], SquadBrain.Order.MOVE, m.lb.ground(-20, 14))
		m.tactical_map.open()
		m.tactical_map._zoom_i = 2
		m.tactical_map.selected.append(m.squad.members[2])
		m.tactical_map._update_camera()
		await shot("08_tactical_map")
		m.tactical_map.close()
	# Fernglas auf das Gehöft
	if not Game.cli.has("shots") or Array(Game.cli["shots"].split(",")).has("10"):
		hale.global_position = m.lb.ground(4, 60, 0.2)
		hale.look_yaw = 0.0
		hale.look_pitch = 0.02
		hale.using_binoculars = true
		await frames(40)
		await shot("10_binoculars")
		hale.using_binoculars = false
	# Kübelwagen mit Fahrer und Mitfahrer
	if not Game.cli.has("shots") or Array(Game.cli["shots"].split(",")).has("09"):
		var v: Vehicle = get_tree().get_nodes_in_group("vehicles")[0]
		hale.global_position = v._entry.global_position + Vector3.UP * 0.3
		v.board(hale, true)
		v.board(m.squad.members[3])
		hale.look_yaw = v.global_rotation.y + PI + 0.5
		hale.look_pitch = -0.15
		await frames(40)
		await shot("09_vehicle")
	get_tree().quit()
