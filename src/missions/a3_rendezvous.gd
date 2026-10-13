extends OrigMission
## ORIGINAL-MISSION 1, Teil C: "Arctic 1C" – dt. "Operation Schneeball – Rendezvous"
## (Lofoten, 4. März 1941, 21:57 Uhr). Daten: MISSIONS\ARCTIC3.
## Missionsziele (Index -> Text 6020+Index): 1 Piloten finden · 2 Piloten retten ·
##   3 Schiff besteigen und verschwinden · 4 (opt.) Sygurd gerettet ·
##   5 (opt.) Boots-Mannschaft überlebt · 6 (opt.) alle überleben


func _init() -> void:
	orig_mission = "ARCTIC3"
	text_title = 4521
	text_place_time = 4522
	objective_text_base = 6020
	optional_objectives = [4, 5, 6, 7]
	enemy_uniform = Color(0.78, 0.8, 0.82)   # Wintertarnung


func _configure_environment(e: Environment, moon: DirectionalLight3D) -> void:
	# Späte Nacht, Schnee
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.02, 0.03, 0.06)
	sm.sky_horizon_color = Color(0.1, 0.12, 0.16)
	sm.ground_horizon_color = Color(0.09, 0.1, 0.12)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.7)
	e.ambient_light_energy = 0.42
	e.fog_light_color = Color(0.2, 0.22, 0.28)
	e.fog_density = 0.01
	e.tonemap_exposure = 1.4
	moon.rotation_degrees = Vector3(-35, -40, 0)
	moon.light_color = Color(0.62, 0.68, 0.88)
	moon.light_energy = 0.33
