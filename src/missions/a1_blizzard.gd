extends OrigMission
## ORIGINAL-MISSION 1, Teil A: "Arctic 1A" – dt. "Operation Schneeball – Erster Angriff"
## (Lofoten, 4. März 1941, 19:48 Uhr, Nacht, Schneesturm). Daten: MISSIONS\ARCTIC1.
## Missionsziele (Original-Index -> Text-ID 6000+Index), gesetzt per SetObjectiveStatus:
##   1 Führer finden und folgen (muss leben) · 2 Eingang finden · 3 Feinde im Komplex töten ·
##   4 Team am Eingang sammeln · 5 (opt.) Laster mit Sprengstoff zerstören · 6 (opt.) alle überleben


func _init() -> void:
	orig_mission = "ARCTIC1"
	text_title = 4501
	text_place_time = 4502
	optional_objectives = [5, 6]
	light_factor = 0.5          # Nacht
	enemy_uniform = Color(0.78, 0.8, 0.82)   # Wintertarnung


func _configure_environment(e: Environment, moon: DirectionalLight3D) -> void:
	# Original: Nacht, starker Wind, Schneefall
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.03, 0.04, 0.07)
	sm.sky_horizon_color = Color(0.12, 0.14, 0.18)
	sm.ground_horizon_color = Color(0.1, 0.11, 0.13)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.7)
	e.ambient_light_energy = 0.45
	e.fog_light_color = Color(0.2, 0.22, 0.28)
	e.fog_density = 0.01
	e.tonemap_exposure = 1.4
	moon.rotation_degrees = Vector3(-40, 30, 0)
	moon.light_color = Color(0.62, 0.68, 0.88)
	moon.light_energy = 0.35
