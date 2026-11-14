extends RefCounted
## Wegbeleuchtung im Stil um 1944/45: gusseiserne Mastleuchten mit Emailleschirm entlang der Dorfwege und
## Wandleuchten neben den Haustüren. Licht ohne Schatten, Entfernungsausblendung; nachts an, tagsüber aus
## (Steuerung über set_level aus day_night.gd). Masten haben Kollision und liegen unter static_root (Navmesh).
## Platzierung hält Wege, Starts, Zonenmitten, Türen, Fensterplätze, Deko, Bäume und Grundrisse frei.
const ROADS := {"dorfrand": 19.0, "haeuserzeile": 19.0, "west_path": 24.0, "east_path": 24.0, "farm_track": 22.0}
const POLE_H := 3.6
const POLE_RANGE := 10.0
const POLE_ENERGY := 1.5
const WALL_RANGE := 6.0
const WALL_ENERGY := 1.0
var m: Mission
var lamps: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var rejected := 0
var level := 1.0
var _iron: StandardMaterial3D
var _enamel: StandardMaterial3D
var _glow: StandardMaterial3D
var _avoid: Array = []     # [Vector2, Radius]

func build(mission: Mission) -> void:
	m = mission
	_materials()
	_collect_obstacles()
	for road in m.layout["paths"]:
		var id := String(road.id)
		if not ROADS.has(id):
			continue
		var pts: Array = road["points"]
		var poly: Array[Vector3] = []
		for p in pts:
			poly.append(m.pixel(p))
		var step: float = ROADS[id]
		var travelled := 0.0
		var next_at := step * 0.45
		var side := 1.0
		for i in poly.size() - 1:
			var a: Vector3 = poly[i]
			var b: Vector3 = poly[i + 1]
			var seg := a.distance_to(b)
			while next_at <= travelled + seg:
				var t := (next_at - travelled) / seg
				_try_pole(a.lerp(b, t), (b - a).normalized(), float(road.width), side, id)
				side = -side
				next_at += step
			travelled += seg
	for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		if house.get_meta("interior_partitioned", false):
			_wall_lamp(house)
	print("BAVARIA LATERNEN: %d Leuchten (%d Masten), %d Standorte verworfen" % [lamps.size(),
		lamps.filter(func(l): return l.get_meta("kind") == "pole").size(), rejected])

func _materials() -> void:
	_iron = StandardMaterial3D.new()
	_iron.albedo_color = Color(0.13, 0.16, 0.14)
	_iron.metallic = 0.55
	_iron.roughness = 0.55
	_enamel = StandardMaterial3D.new()
	_enamel.albedo_color = Color(0.11, 0.20, 0.16)   # grün emaillierter Blechschirm
	_enamel.metallic = 0.2
	_enamel.roughness = 0.35
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.78, 0.45)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.62, 0.25)
	_glow.emission_energy_multiplier = 2.5

func _collect_obstacles() -> void:
	for s in m.layout["spawns"]:
		var p: Vector3 = m.pixel(s["pixel"])
		_avoid.append([Vector2(p.x, p.z), 3.0])
	for z in m.layout.get("occupation_zones", []):
		var p: Vector3 = m.pixel(z["pixel"])
		_avoid.append([Vector2(p.x, p.z), 3.5])
	for g in ["bavaria_decorations", "bavaria_trees", "bavaria_greenhouses", "bavaria_gates"]:
		for n in m.get_tree().get_nodes_in_group(g):
			if n is Node3D:
				var p: Vector3 = (n as Node3D).global_position
				_avoid.append([Vector2(p.x, p.z), 1.8])
	for g in ["bavaria_wrecks", "bavaria_aircraft_wrecks", "bavaria_war_groups", "bavaria_field_flak", "bavaria_towers"]:
		for n in m.get_tree().get_nodes_in_group(g):
			if n is Node3D:
				var p: Vector3 = (n as Node3D).global_position
				_avoid.append([Vector2(p.x, p.z), 4.5])
	for house in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		for w in house.get_meta("shooting_windows", []):
			var p: Vector3 = house.to_global(w)
			_avoid.append([Vector2(p.x, p.z), 2.6])
		for e in house.get_meta("entry_points", []):
			var p: Vector3 = house.to_global(e.point + e.normal * 1.0)
			_avoid.append([Vector2(p.x, p.z), 2.4])

## Freier Maststandort (Fußpunkt p, y = 0)?
func free_spot(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if not m.inside_map(p):
		return false
	for i in m.boundary.size():
		if Geometry2D.get_closest_point_to_segment(q, m.boundary[i], m.boundary[(i + 1) % m.boundary.size()]).distance_to(q) < 1.5:
			return false
	for f in m.building_footprints:
		if Geometry2D.is_point_in_polygon(q, f):
			return false
		for i in f.size():
			if Geometry2D.get_closest_point_to_segment(q, f[i], f[(i + 1) % f.size()]).distance_to(q) < 1.0:
				return false
	for road in m.layout["paths"]:
		var pts: Array = road["points"]
		for i in pts.size() - 1:
			var a: Vector3 = m.pixel(pts[i])
			var b: Vector3 = m.pixel(pts[i + 1])
			if Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(q) < float(road.width) * 0.5 + 0.35:
				return false
	for o in _avoid:
		if q.distance_to(o[0]) < float(o[1]):
			return false
	for l in lamps:
		if Vector2(l.global_position.x, l.global_position.z).distance_to(q) < 8.0:
			return false
	return true

func _try_pole(center: Vector3, dir: Vector3, width: float, side: float, road: String) -> void:
	var normal := Vector3(-dir.z, 0, dir.x)
	for shift in [0.0, 2.5, -2.5, 5.0, -5.0]:
		for sgn in [side, -side]:
			var p: Vector3 = center + dir * shift + normal * sgn * (width * 0.5 + 0.75)
			p.y = 0.0
			if free_spot(p):
				_pole(p, -normal * sgn, road)
				return
	rejected += 1

func _pole(p: Vector3, toward_road: Vector3, road: String) -> void:
	var holder := StaticBody3D.new()
	holder.name = "Laterne_%s_%d" % [road, lamps.size()]
	m.static_root.add_child(holder)
	holder.global_position = p
	holder.rotation.y = atan2(-toward_road.x, -toward_road.z)   # lokales −Z zeigt zum Weg
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.11
	shape.height = POLE_H
	cs.shape = shape
	cs.position.y = POLE_H * 0.5
	holder.add_child(cs)
	_cyl(holder, 0.17, 0.20, 0.55, Vector3(0, 0.275, 0), _iron)        # Sockel
	_cyl(holder, 0.055, 0.075, POLE_H, Vector3(0, POLE_H * 0.5, 0), _iron)
	_cyl(holder, 0.085, 0.085, 0.10, Vector3(0, 0.6, 0), _iron)          # Zierring
	var arm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.72)
	arm.mesh = bm
	arm.material_override = _iron
	arm.position = Vector3(0, POLE_H - 0.12, -0.36)
	holder.add_child(arm)
	var brace := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.03, 0.03, 0.5)
	brace.mesh = bb
	brace.material_override = _iron
	brace.position = Vector3(0, POLE_H - 0.32, -0.2)
	brace.rotation.x = -0.6
	holder.add_child(brace)
	var head := Vector3(0, POLE_H - 0.30, -0.70)
	_shade(holder, head, 0.26)
	_light(holder, head + Vector3.DOWN * 0.08, POLE_RANGE, POLE_ENERGY)
	holder.set_meta("kind", "pole")
	holder.set_meta("road", road)
	holder.set_meta("head", head)
	holder.add_to_group("bavaria_street_lamps")
	lamps.append(holder)

func _wall_lamp(house: Node3D) -> void:
	var entries: Array = house.get_meta("entry_points", [])
	if entries.is_empty():
		return
	var e: Dictionary = entries[0]
	var normal: Vector3 = e.normal
	var lateral := normal.cross(Vector3.UP).normalized()
	var local: Vector3 = e.point + lateral * 1.0 + normal * 0.18 + Vector3.UP * 2.45
	var holder := Node3D.new()
	holder.name = "Wandleuchte_" + String(house.name)
	# Nicht unter den Hausknoten (merge_building_visuals fasst dessen Meshes zusammen), sondern daneben.
	m.static_root.add_child(holder)
	holder.global_transform = house.global_transform * Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), local)   # lokales +Z = außen
	var bracket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, 0.42)
	bracket.mesh = bm
	bracket.material_override = _iron
	bracket.position = Vector3(0, 0.05, 0.08)
	holder.add_child(bracket)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 0.22, 0.03)
	plate.mesh = pm
	plate.material_override = _iron
	plate.position = Vector3(0, 0.02, 0.0)
	holder.add_child(plate)
	_shade(holder, Vector3(0, -0.05, 0.28), 0.17)
	_light(holder, Vector3(0, -0.15, 0.30), WALL_RANGE, WALL_ENERGY)
	holder.set_meta("kind", "wall")
	holder.set_meta("road", "")
	holder.add_to_group("bavaria_street_lamps")
	lamps.append(holder)

func _shade(parent: Node3D, pos: Vector3, radius: float) -> void:
	_cyl(parent, 0.04, radius, 0.13, pos, _enamel)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	bulb.mesh = sphere
	bulb.material_override = _glow
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = pos + Vector3.DOWN * 0.06
	bulb.visibility_range_end = 140.0
	parent.add_child(bulb)

func _light(parent: Node3D, pos: Vector3, range_m: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = "Laternenlicht"
	light.light_color = Color(1.0, 0.76, 0.48)
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.1
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	light.position = pos
	light.set_meta("base_energy", energy)
	parent.add_child(light)
	light.add_to_group("bavaria_street_lights")
	lights.append(light)

func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = 140.0
	parent.add_child(mi)

func set_level(f: float) -> void:
	level = clampf(f, 0.0, 1.0)
	for light in lights:
		light.light_energy = float(light.get_meta("base_energy")) * level
		light.visible = level > 0.02
	if _glow:
		_glow.emission_energy_multiplier = 0.05 + 2.45 * level
		_glow.albedo_color = Color(1.0, 0.78, 0.45).lerp(Color(0.72, 0.72, 0.68), 1.0 - level)

func lights_on() -> int:
	var n := 0
	for light in lights:
		if light.visible and light.light_energy > 0.05:
			n += 1
	return n
