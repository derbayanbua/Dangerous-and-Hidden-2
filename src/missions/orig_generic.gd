extends OrigMission
## Generischer Original-Missionsteil: Parameter aus Game.MISSIONS[id] ("orig" = Ordner in Missions.dta,
## "k" = Index in der Original-Texttabelle: Titel 4501+10k, Ort/Zeit 4502+10k, Briefing 4503+10k,
## Einsatz-Aufgaben 4505+10k …, Ziele 6000+10k+Index). Umgebung aus den Original-Lichtern (extra.json),
## Pflicht-/Zusatzziele aus dem Briefing (siehe OrigMission._setup_objectives).


func _init() -> void:
	var e: Dictionary = Game.MISSIONS.get(Game.current_mission_id, {})
	orig_mission = String(e.get("orig", ""))
	var k := int(e.get("k", 0))
	text_title = 4501 + 10 * k
	text_place_time = 4502 + 10 * k
	objective_text_base = 6000 + 10 * k
	objective_count = 9
	auto_optional = true
	briefing_task_ids = []
	for i in range(4505 + 10 * k, 4510 + 10 * k):
		briefing_task_ids.append(i)
