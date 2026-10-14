class_name WeaponData
extends Resource
## Statische Eigenschaften eines Waffentyps. Werte in SI-Einheiten.
## Die Zahlenwerte sind historisch angelehnte Designwerte (siehe CLAUDE.md,
## Abschnitt "Waffenwerte"), nicht aus dem Original extrahiert.

enum Slot { PRIMARY, SIDEARM, GRENADE, LAUNCHER, MELEE }
enum Action { SEMI, AUTO, BOLT, THROWN, ROCKET, MELEE }
const SLOT_COUNT := 5

@export var id: StringName
@export var display_name := ""
@export var faction := "allied"       ## allied / axis
@export var slot: Slot = Slot.PRIMARY
@export var action: Action = Action.SEMI
@export var can_toggle_auto := false  ## z. B. Bren, Sten: Einzel/Dauerfeuer
@export var caliber := ""
@export var magazine_size := 30
@export var start_magazines := 4
@export var rpm := 600.0               ## Kadenz (Auto) bzw. max. Einzelfeuer-Rate
@export var bolt_time := 0.0          ## Repetierzeit bei BOLT
@export var reload_time := 2.5
@export var reload_empty_time := 3.0
@export var muzzle_velocity := 400.0   ## m/s
@export var damage := 40.0             ## Schaden bei Rumpftreffer, Nahdistanz
@export var falloff_start := 50.0      ## ab hier sinkt der Schaden mit der Geschwindigkeit
@export var spread_hip := 3.0          ## Grad, Halbwinkel
@export var spread_aim := 0.4
@export var spread_move_add := 2.5     ## Zusatzstreuung bei Bewegung
@export var recoil_pitch := 1.2        ## Grad pro Schuss
@export var recoil_yaw := 0.4
@export var recoil_recovery := 6.0     ## Grad/s Rückkehr
@export var spread_per_shot := 0.6     ## Grad Streuungsanstieg pro Schuss (Dauerfeuer)
@export var aim_fov := 50.0            ## Kamera-FOV beim Zielen
@export var noise_radius := 100.0      ## Hörweite des Schusses in m
@export var weight := 4.0              ## kg, beeinflusst Ausdauer
@export var model_length := 0.9        ## für das Platzhaltermodell
@export var color := Color(0.25, 0.18, 0.12)

## Granaten
@export var fuse_time := 4.0
@export var blast_radius := 7.0
@export var throw_speed := 16.0


func shot_interval() -> float:
	if action == Action.BOLT:
		return bolt_time
	return 60.0 / maxf(rpm, 1.0)


func is_automatic() -> bool:
	return action == Action.AUTO
