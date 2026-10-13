class_name Objective
extends RefCounted
## Missionsziel. Zustand wird von der Mission gesetzt.

enum State { ACTIVE, DONE, FAILED, INACTIVE }   ## INACTIVE: noch nicht freigeschaltet (Original-Skripte)

var id: StringName
var text := ""
var optional := false
var secondary := false     ## Original-Status 4 („angezeigt, nachrangig“, z. B. „alle müssen überleben“): blockiert den Sieg nicht
var state: int = State.ACTIVE


func _init(p_id: StringName, p_text: String, p_optional := false) -> void:
	id = p_id
	text = p_text
	optional = p_optional


func is_done() -> bool:
	return state == State.DONE
