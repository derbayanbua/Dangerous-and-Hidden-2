extends OrigMission
## ORIGINAL-MISSION 1, Teil B: "Arctic 1B" – dt. "Operation Schneeball – Erkundung"
## (Lofoten, 4. März 1941, 20:21 Uhr). Daten: MISSIONS\ARCTIC2. Im Original geht nur
## EIN Kommando (Commando1) in den unterirdischen Teil der Fabrik.
## Missionsziele (Index -> Text 6010+Index): 1 Luftfahrt-Forschung nehmen/fotografieren ·
##   2 Anlage erkunden · 3 zur Oberfläche zurück · 4 Sprengsätze anbringen ·
##   5 (opt.) nicht von Patrouillen entdeckt werden · 6 (opt.) alle Sprengsätze angebracht


func _init() -> void:
	orig_mission = "ARCTIC2"
	text_title = 4511
	text_place_time = 4512
	objective_text_base = 6010
	optional_objectives = [5, 6, 7]
	light_factor = 0.5          # Nacht
	enemy_uniform = Color(0.36, 0.38, 0.33)   # Feldgrau (Innenanlage)


func _configure_environment(e: Environment, moon: DirectionalLight3D) -> void:
	# Nacht; überwiegend unterirdische Anlage mit Kunstlicht
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.03, 0.04, 0.07)
	sm.sky_horizon_color = Color(0.1, 0.12, 0.16)
	sm.ground_horizon_color = Color(0.08, 0.09, 0.1)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.5
	e.fog_density = 0.004
	e.tonemap_exposure = 1.4
	moon.rotation_degrees = Vector3(-45, 20, 0)
	moon.light_color = Color(0.62, 0.68, 0.88)
	moon.light_energy = 0.3
