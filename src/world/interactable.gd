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
	# Original-Benutzenclip der Figur (Tür, Aufheben, Schalter …; Soldier.play_use_anim)
	if is_instance_valid(s) and s.has_method("play_use_anim"):
		s.play_use_anim(self)
	if is_instance_valid(s):
		FieldInventory.view(s)       # Aufgenommenes in Aufnahmereihenfolge festhalten (Ingame-Inventar, inv_order)
	used.emit(s)


func serialize() -> Dictionary:
	return {"enabled": enabled}


func deserialize(d: Dictionary) -> void:
	enabled = d.get("enabled", true)
