extends RefCounted
## Laufzeitschalter für Einzelspieler-Regeln (gelten nie online).

static var one_hit := false
static var keep_mag := false
static var steady := false


static func active(flag: bool) -> bool:
	return flag and not Net.is_online


static func reset() -> void:
	one_hit = false
	keep_mag = false
	steady = false
