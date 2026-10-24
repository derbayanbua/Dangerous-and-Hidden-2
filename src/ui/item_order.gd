extends RefCounted
## Reihenfolge der Gegenstandslisten (Vorgabe Auftraggeber): die passende Munition steht immer direkt unter der
## Waffe, zu der sie gehört. Zuordnung wie im Spiel über items.sav (Waffe -> `ammo_item`, SAS.ammo_of /
## SAS.weapon_of_ammo; Raketen der Werfer über WeaponDB.LAUNCHER_AMMO).
## - Nutzen mehrere Waffen derselben Liste dieselbe Munition (z. B. Sten / Sten + Schalldämpfer, Colt 1911 /
##   De Lisle), steht sie nur unter der ersten davon.
## - Taschen/Rucksack: sonst gilt die Original-Ordnung = Aufnahmereihenfolge (Belege unten bei order_entries).
##   Munition, deren Waffe nicht in derselben Liste liegt (Waffe in Händen/Schulter oder gar keine), bleibt an
##   ihrer Aufnahmestelle – sie wird weder nach oben noch ans Ende gezogen.
## - Lager: Munition ohne Waffe in der Kategorie steht am Ende der Kategorie ihrer Waffe.
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


## Inventareinträge [[id, anzahl], ...] in Anzeige-Reihenfolge: Aufnahmereihenfolge wie im Original, jede Waffe
## gefolgt von ihrer Munition (Vorgabe Auftraggeber). Nur Munition, deren Waffe in derselben Liste liegt, wird
## dorthin verschoben; alle anderen Einträge (auch Munition der Hand-/Schulterwaffe) behalten ihre Stelle.
## Original hd2.exe v1.12 (docs/re_notes_roster_inventory.md §4a), keine Sortierung nach ID/Kategorie/Munition:
## - Ausrüstungsbildschirm: Taschen = Vektor Team-Mitglied +0x70, Rucksackinhalt +0x80 (6-Byte-Sätze). Einfügen
##   0x6A3080 (Fall 0x20/0x40): gleiche Sorte → Anzahl +1 im vorhandenen Satz, sonst neuer Satz am ENDE
##   (0x5AAC90 an +0x74). Entfernen 0x6A3BC0: Satz mit Anzahl 0 wird gelöscht, Rest rückt auf. Anzeige 0x672280:
##   Felder item00–03 = Satz[Bildlauf + i] in Vektorreihenfolge.
## - Ingame (Taste I): Behälter vtable 0x8171A0 (Taschen 14, Rucksack 32 Gruppen). Einfügen 0x7D7390: zur Gruppe
##   derselben Sorte, sonst erste leere Gruppe; Entfernen 0x7D7470 rückt leere Gruppen ans Ende; Anzeige 0x4A2010 in
##   Gruppenreihenfolge. Missionsstart 0x59EB60 und -ende 0x5A8B50 übertragen in dieser Reihenfolge.
## - Munition der Handwaffe steht nur oben, wenn sie zuerst aufgenommen wurde: presets.def-Taschenlisten werden in
##   Dateireihenfolge eingefügt (0x677D00; dort meist, aber nicht immer zuerst, z. B. Vorlagen 5, 8, 13, 15, 36, 40,
##   42, 43, 49, 52–58), AUTOMATISCHES AUFFÜLLEN 0x6777A0 hängt Hand-, dann Schultermunition hinten an.
static func order_entries(entries: Array) -> Array:
	var ammo_e := {}
	for e in entries:
		var w := ammo_for(int(e[0]))
		if w >= 0:
			ammo_e[w] = null
	for e in entries:
		var id := int(e[0])
		if ammo_e.has(id) and is_ammo(id):
			ammo_e[id] = e
	for k in ammo_e.keys():
		if ammo_e[k] == null:
			ammo_e.erase(k)
	var out: Array = []
	var used := {}
	for e in entries:
		var id := int(e[0])
		if ammo_e.has(id):
			continue
		out.append(e)
		_take(ammo_for(id), ammo_e, used, out)
	return out


static func _take(am: int, ammo_e: Dictionary, used: Dictionary, out: Array) -> void:
	if am >= 0 and ammo_e.has(am) and not used.has(am):
		used[am] = true
		out.append(ammo_e[am])
