extends Node
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok:
		passed += 1
		print("PASS ",label)
	else:
		failed += 1
		print("FAIL ",label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var m: Mission
	while m==null or not m.nav_ready or not m.prank_mines.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	for actor in get_tree().get_nodes_in_group("soldiers"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var field = m.prank_mines
	check(field.mines.size()==10,"Genau zehn Rauchminen")
	check(field.SOUND.get_length()>0.1,"MP3 als AudioStream geladen")
	var s := Soldier.new()
	m.actors_root.add_child(s)
	s.process_mode = Node.PROCESS_MODE_DISABLED
	var health := s.health
	for index in field.mines.size():
		var mine: Node3D = field.mines[index]
		check(m.inside_map(mine.global_position),"Mine %d innerhalb Spielgrenze"%index)
		var clear := true
		for spawn in m.mp_spawns():
			if Vector2(spawn.pos.x-mine.global_position.x,spawn.pos.z-mine.global_position.z).length()<3.0:
				clear = false
		check(clear,"Mine %d abseits der Spawns"%index)
		var previous: int = field.effect_count
		s.global_position = mine.global_position+Vector3.UP*2.0
		await get_tree().create_timer(0.15).timeout
		check(not field.spent[index],"Mine %d löst nicht vom Stockwerk darüber aus"%index)
		s.global_position = mine.global_position
		await get_tree().create_timer(0.15).timeout
		check(field.spent[index] and field.effect_count==previous+1,"Mine %d durch Soldatenfüße ausgelöst"%index)
		check(s.health==health and s.alive and s.velocity==Vector3.ZERO,"Mine %d ohne Schaden oder Druckwelle"%index)
		await get_tree().create_timer(0.15).timeout
		check(field.effect_count==previous+1,"Mine %d löst nicht wiederholt aus"%index)
	var effects := get_tree().get_nodes_in_group("bavaria_prank_effects")
	check(not effects.is_empty(),"Kurze Raucheffekte erzeugt")
	if not effects.is_empty():
		var effect = effects[-1]
		var audio: AudioStreamPlayer3D = effect.get_child(0)
		var smoke: CPUParticles3D = effect.get_child(1)
		check(audio.stream==field.SOUND and audio.max_distance==25.0,"Räumliches Originalgeräusch statt Explosion")
		check(smoke.one_shot and smoke.lifetime<1.5,"Rauchschwaden kurz und einmalig")
	await get_tree().create_timer(maxf(field.SOUND.get_length()+0.3,2.3)).timeout
	check(get_tree().get_nodes_in_group("bavaria_prank_effects").is_empty(),"Rauch und Audioknoten vollständig aufgeräumt")
	print("BAVARIA MINES: %d passed, %d failed"%[passed,failed])
	get_tree().quit(0 if failed==0 else 1)
