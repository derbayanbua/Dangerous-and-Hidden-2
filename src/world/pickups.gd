class_name Pickups
extends RefCounted
## Fabrik für einfache benutzbare Objekte. Logik steckt in den inneren
## Klassen; die Mission verbindet "used"-Signale mit ihren Zielen.


## Aufhebbarer Missionsgegenstand (z. B. Codebuch).
class Item extends Interactable:
	var item_name := "Gegenstand"
	var mesh_size := Vector3(0.25, 0.05, 0.18)
	var color := Color(0.5, 0.1, 0.1)
	var _mesh: MeshInstance3D

	func _ready() -> void:
		super._ready()
		prompt = "%s aufnehmen" % item_name
		_mesh = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = mesh_size
		_mesh.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_mesh.material_override = m
		_mesh.position.y = mesh_size.y * 0.5
		add_child(_mesh)

	func interact(s: Soldier) -> void:
		if not enabled:
			return
		enabled = false
		_mesh.visible = false
		Events.say("%s aufgenommen." % item_name, 2.5)
		super.interact(s)

	func deserialize(d: Dictionary) -> void:
		super.deserialize(d)
		if _mesh:
			_mesh.visible = enabled


## Munitionskiste: füllt Reserve aller Waffen auf (begrenzte Ladungen).
class AmmoCrate extends Interactable:
	var charges := 3

	func _ready() -> void:
		super._ready()
		prompt = "Munition aufnehmen"
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.4, 0.45)
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.32, 0.22)
		mi.material_override = m
		mi.position.y = 0.2
		add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		cs.position.y = 0.2
		body.add_child(cs)
		add_child(body)

	func can_interact(s: Soldier) -> bool:
		return enabled and charges > 0

	func interact(s: Soldier) -> void:
		var total := 0
		for w in s.weapons:
			if w:
				total += w.add_ammo(w.data.magazine_size * 2)
		if total > 0:
			charges -= 1
			Events.say("%d Schuss Munition aufgenommen." % total, 2.0)
		else:
			Events.say("Munition ist voll.", 1.5)
		super.interact(s)

	func serialize() -> Dictionary:
		return {"enabled": enabled, "charges": charges}

	func deserialize(d: Dictionary) -> void:
		super.deserialize(d)
		charges = int(d.get("charges", charges))


## Leiche durchsuchen: passende Munition übernehmen.
class Loot extends Interactable:
	var corpse: Soldier
	var looted := false
	var uniform_taken := false

	func _ready() -> void:
		super._ready()
		prompt = "Durchsuchen"

	## Nach dem Durchsuchen: Uniform eines gefallenen Gegners anziehen (Tarnung)
	func _uniform_available(s: Soldier) -> bool:
		return looted and not uniform_taken and is_instance_valid(corpse) and not corpse.alive \
			and corpse.team != s.team and not s.disguised and s.vehicle == null

	func can_interact(s: Soldier) -> bool:
		if not is_instance_valid(corpse) or corpse.alive:
			return false
		return (enabled and not looted) or _uniform_available(s)

	func interact(s: Soldier) -> void:
		if _uniform_available(s):
			uniform_taken = true
			s.put_on_uniform(corpse.uniform_color, corpse.helmet_style)
			Events.say("%s trägt jetzt eine feindliche Uniform. Nicht schießen, Abstand halten!" % s.soldier_name, 4.0)
			prompt = "Durchsuchen"
			super.interact(s)
			return
		if not enabled or looted or not is_instance_valid(corpse):
			return
		looted = true
		if corpse.team != s.team:
			prompt = "Uniform anziehen"
		var total := 0
		for cw in corpse.weapons:
			if cw == null or cw.total_ammo() <= 0 or cw.data.slot == WeaponData.Slot.GRENADE:
				continue
			for w in s.weapons:
				if w and w.data.caliber == cw.data.caliber:
					var got := w.add_ammo(cw.total_ammo())
					cw.reserve = maxi(cw.reserve - got, 0)
					total += got
		# Granaten übernehmen
		var g := corpse.weapons[WeaponData.Slot.GRENADE] if corpse.weapons.size() > 2 else null
		var my_g := s.weapons[WeaponData.Slot.GRENADE] if s.weapons.size() > 2 else null
		if g and my_g and g.total_ammo() > 0:
			total += my_g.add_ammo(g.total_ammo())
			g.in_mag = 0
			g.reserve = 0
		var kits := corpse.medkits
		if kits > 0:
			s.medkits += kits
			corpse.medkits = 0
		var parts: Array[String] = []
		if total > 0:
			parts.append("%d Schuss" % total)
		if kits > 0:
			parts.append("%d Verbandskasten" % kits)
		Events.say("Durchsucht: %s" % (", ".join(parts) if not parts.is_empty() else "nichts Brauchbares"), 2.5)
		super.interact(s)
