class_name WeaponData
extends Resource
## Statische Eigenschaften eines Waffentyps. Werte in SI-Einheiten.
## Schaden/Abfall/Explosion aus dem Original (items.sav, hd2.exe; Herkunft je Wert in weapon_db.gd [O]/[D]),
## Gesundheit 100 = 1000 „zotti“ des Originals.

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
@export var damage := 40.0             ## Schaden bei Rumpftreffer, Nahdistanz (Granaten/Werfer: Explosionsstärke im Zentrum)
@export var falloff_start := 50.0      ## ab hier sinkt der Schaden (Original: items.sav Feuerwaffe +0x34, m)
## Schadensabfall je Meter ab falloff_start (Original items.sav Feuerwaffe +0x38 / 10, linear, hd2.exe 0x44B3B0);
## 0 = eigene Waffe ohne Originalwert → Abfall über die Restenergie (Ballistics)
@export var falloff_per_m := 0.0
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
## Klangklasse (Effects); leer = nach Waffenart. Schalldämpfer: &"silenced_rifle" (De Lisle), &"silenced_smg" (Sten)
@export var sound: StringName = &""

## Granaten
@export var fuse_time := 4.0
@export var blast_radius := 7.0         ## Original items.sav Werfer +0x58 (m); Schaden linear (1 − d/r) · damage
@export var throw_speed := 16.0


func shot_interval() -> float:
	if action == Action.BOLT:
		return bolt_time
	return 60.0 / maxf(rpm, 1.0)


func is_automatic() -> bool:
	return action == Action.AUTO
