extends RefCounted
## Reihenfolge der Gegenstandslisten (Vorgabe Auftraggeber): die passende Munition steht immer direkt unter der
## Waffe, zu der sie gehört. Zuordnung wie im Spiel über items.sav (Waffe -> `ammo_item`, SAS.ammo_of /
## SAS.weapon_of_ammo; Raketen der Werfer über WeaponDB.LAUNCHER_AMMO).
## - Nutzen mehrere Waffen derselben Liste dieselbe Munition (z. B. Sten / Sten + Schalldämpfer, Colt 1911 /
##   De Lisle), steht sie nur unter der ersten davon.
## - Munition ohne vorhandene Waffe steht am Ende (Lager: am Ende der Kategorie ihrer Waffe).
## Genutzt von SasScreen (Lagerliste, Taschen/Rucksack) und IngameInventory (eigenes und durchsuchtes Inventar).
## Reine Anzeige-Reihenfolge: Inhalt und Mengen der Inventare bleiben unverändert.


static func is_ammo(id: int) -> bool:
	if id < 0:
		return false
	var k := SAS.item_kind(id)
	if k == "ammo":
		return true
	return k != "weapon" and SAS.weapon_of_ammo(id) >= 0


static func ammo_for(weapon_id: int) -> int:
	if weapon_id < 0 or SAS.item_kind(weapon_id) != "weapon":
		return -1
	var am := SAS.ammo_of(weapon_id)
	return am if am != weapon_id else -1


## Kategorie der Lagerliste für ein Magazin = Kategorie seiner (ersten) Waffe, sonst „zusätzliche Ausrüstung“
static func ammo_category(ammo_id: int) -> int:
	var w := SAS.weapon_of_ammo(ammo_id)
	return SAS.item_category(w) if w >= 0 else 5


## Sortierung der Lagerliste: Kategorie, dann angezeigter Name
static func by_category_label(a: int, b: int) -> bool:
	var ca := SAS.item_category(a)
	var cb := SAS.item_category(b)
	if ca != cb:
		return ca < cb
	return SAS.item_label(a) < SAS.item_label(b)


## Inventareinträge [[id, anzahl], ...] in Anzeige-Reihenfolge. `lead` = Waffen auf festen Plätzen (Hände,
## Schulter): deren Munition steht oben in der Liste, direkt neben/unter diesen Plätzen. Danach die übrigen
## Gegenstände in ihrer bisherigen Reihenfolge, jede Waffe gefolgt von ihrer Munition; Munition ohne Waffe am Ende.
static func order_entries(entries: Array, lead: Array = []) -> Array:
	var ammo_e := {}
	for e in entries:
		if is_ammo(int(e[0])):
			ammo_e[int(e[0])] = e
	var out: Array = []
	var used := {}
	for w in lead:
		_take(ammo_for(int(w)), ammo_e, used, out)
	for e in entries:
		var id := int(e[0])
		if ammo_e.has(id):
			continue
		out.append(e)
		_take(ammo_for(id), ammo_e, used, out)
	for e in entries:
		var id := int(e[0])
		if ammo_e.has(id) and not used.has(id):
			out.append(e)
	return out


static func _take(am: int, ammo_e: Dictionary, used: Dictionary, out: Array) -> void:
	if am >= 0 and ammo_e.has(am) and not used.has(am):
		used[am] = true
		out.append(ammo_e[am])


## Waffen eines Inventars auf festen Plätzen (für `lead`)
static func slot_weapons(inv: Dictionary) -> Array:
	var out: Array = []
	for slot in ["hands", "shoulder"]:
		var id := int(inv.get(slot, -1))
		if id >= 0 and SAS.item_kind(id) == "weapon":
			out.append(id)
	return out
