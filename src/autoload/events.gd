extends Node
## Globaler Event-Bus. Systeme kommunizieren über diese Signale statt über
## direkte Referenzen (Soldaten, KI, HUD, Mission).

## Geräusch in der Welt. radius = Hörweite in Metern bei normaler Hörfähigkeit.
## source = verursachender Node (darf null sein), team = Team des Verursachers.
signal noise_emitted(position: Vector3, radius: float, source: Node, team: int, kind: StringName)

signal soldier_damaged(soldier: Node, amount: float, zone: StringName, attacker: Node)
signal soldier_died(soldier: Node, attacker: Node)

signal active_soldier_changed(soldier: Node)
signal squad_order_issued(order_name: String)

signal alarm_raised(position: Vector3, raised_by: Node)
signal objective_updated(objective_id: StringName)
signal mission_finished(success: bool, reason: String)

## Kurzmeldung für das HUD (z. B. "Schütze Hale: Feindkontakt!").
signal message(text: String, seconds: float)


func emit_noise(position: Vector3, radius: float, source: Node, team: int, kind: StringName = &"generic") -> void:
	noise_emitted.emit(position, radius, source, team, kind)


func say(text: String, seconds: float = 3.0) -> void:
	message.emit(text, seconds)
