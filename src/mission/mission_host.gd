extends Node
## Wurzel von scenes/mission.tscn: instanziert das Missionsskript der in
## Game.current_mission_id gewählten Mission.


func _ready() -> void:
	var id := Game.current_mission_id
	if id == "":
		id = "m01_funkfeuer"
		Game.current_mission_id = id
	var script: Script = load(Game.MISSIONS[id]["script"])
	var m: Node = script.new()
	m.name = "Mission"
	add_child(m)
