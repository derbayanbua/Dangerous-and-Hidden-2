class_name TestKit
extends RefCounted
## Hilfen für Tests.


## Soldat nur mit deutscher Ausrüstung: Karabiner 98k als Langwaffe, keine weiteren sichtbaren Waffen,
## keine zweite Langwaffe auf dem Rücken und kein Rucksack der eigenen Seite (für die Tarnungsregel 0.10.8).
static func german_kit(s: Soldier) -> void:
	var own_flag := 1 if s.team == Soldier.TEAM_AXIS else 0
	# Inventar: Gegenstände der eigenen Seite aus Händen/Schulter/Rücken und den Taschen entfernen
	var inv := FieldInventory.view(s)
	for slot in ["hands", "shoulder", "back"]:
		var id := int(inv.get(slot, -1))
		if id >= 0 and Net.item_side_flag(id) == own_flag:
			inv[slot] = -1
	var keep: Array = []
	for e in inv.get("items", []):
		if Net.item_side_flag(int(e[0])) != own_flag:
			keep.append(e)
	inv["items"] = keep
	FieldInventory.apply(s, inv, FieldInventory.weapon_pool(s))
	if s.has_meta("back_weapon"):
		s.remove_meta("back_weapon")
	# Waffen: nur Karabiner 98k
	for i in s.weapons.size():
		s.weapons[i] = null
	s.weapons[WeaponData.Slot.PRIMARY] = Weapon.new(WeaponDB.get_weapon(&"kar98k"))
	s.current_slot = WeaponData.Slot.PRIMARY
	s.weapon_changed.emit(s.current_weapon())
