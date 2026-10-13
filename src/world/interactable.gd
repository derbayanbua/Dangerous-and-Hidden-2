class_name Interactable
extends Node3D
## Basis für benutzbare Objekte (Taste "Benutzen"). Der PlayerController
## wählt das nächste Objekt in Reichweite vor dem Soldaten.

signal used(by: Soldier)

@export var prompt := "Benutzen"
@export var persistent_id := ""
var enabled := true


func _ready() -> void:
	add_to_group("interactables")


func can_interact(_s: Soldier) -> bool:
	return enabled


func interact(s: Soldier) -> void:
	used.emit(s)


func serialize() -> Dictionary:
	return {"enabled": enabled}


func deserialize(d: Dictionary) -> void:
	enabled = d.get("enabled", true)
