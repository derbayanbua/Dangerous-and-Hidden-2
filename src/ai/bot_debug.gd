class_name BotDebug
extends Node3D
## Debug-Ansicht der Mehrspieler-KI-Soldaten (nur auf dem Server sichtbar, dort laufen die BotBrains):
## Netzpfad (gelb), Route mit Deckungs-Zwischenpunkten (weiß), Linie zum Ziel (Teamfarbe), Halte-/Stellungs-
## punkt (türkis), Flankenziel (violett), Beschriftung Name/Persönlichkeit/Zustand/Ziel, Zonen mit Besitzerfarbe.
## Einschalten: Konsole „botdebug [on|off]“ bzw. Startoption --bot_debug=1.

static var enabled := false

var _mesh := ImmediateMesh.new()
var _labels := {}                ## Soldier -> Label3D


static func toggle(arg := "") -> String:
	var a := arg.strip_edges().to_lower()
	if a in ["1", "on", "an", "ein"]:
		enabled = true
	elif a in ["0", "off", "aus"]:
		enabled = false
	else:
		enabled = not enabled
	ensure()
	return "botdebug %s" % ("on" if enabled else "off")


## Debug-Knoten in der laufenden Mission anlegen bzw. entfernen
static func ensure() -> void:
	var m := Game.current_mission()
	if m == null:
		return
	var n := m.get_node_or_null("BotDebug")
	if enabled and n == null:
		var d := BotDebug.new()
		d.name = "BotDebug"
		m.add_child(d)
	elif not enabled and n != null:
		n.queue_free()


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	mi.material_override = mat
	add_child(mi)
	top_level = true
	global_transform = Transform3D.IDENTITY


static func team_color(team: int) -> Color:
	return Color(0.3, 0.6, 1.0) if team == Soldier.TEAM_ALLIED else (Color(1.0, 0.35, 0.25) if team == Soldier.TEAM_AXIS
		else Color.from_hsv(fmod(float(team) * 0.17, 1.0), 0.7, 1.0))


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, c: Color, r := 0.6) -> void:
	_line(p + Vector3(-r, 0.2, 0), p + Vector3(r, 0.2, 0), c)
	_line(p + Vector3(0, 0.2, -r), p + Vector3(0, 0.2, r), c)
	_line(p, p + Vector3.UP * 1.8, c)


func _circle(c: Vector3, r: float, col: Color) -> void:
	for i in 24:
		var a0 := TAU * float(i) / 24.0
		var a1 := TAU * float(i + 1) / 24.0
		_line(c + Vector3(cos(a0) * r, 0.3, sin(a0) * r), c + Vector3(cos(a1) * r, 0.3, sin(a1) * r), col)


func _process(_d: float) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)      # leere Fläche vermeiden
	var seen := {}
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s == null or not s.alive:
			continue
		var b := s.get_node_or_null("EnemyBrain") as BotBrain
		if b == null:
			continue
		seen[s] = true
		var col := team_color(s.team)
		var up := Vector3.UP * 0.3
		var pth: PackedVector3Array = b.agent.get_current_navigation_path() if b.agent else PackedVector3Array()
		for i in range(1, pth.size()):
			_line(pth[i - 1] + up, pth[i] + up, Color(1, 0.9, 0.2))
		var wp := b.nav.waypoints
		for i in range(b.nav.wp_i, wp.size()):
			_cross(wp[i], Color.WHITE, 0.4)
		if b.goal.is_finite():
			_line(s.global_position + Vector3.UP * 1.9, b.goal + Vector3.UP * 0.5, col)
			_cross(b.goal, col, 1.0)
		if b.hold_pos.is_finite():
			_cross(b.hold_pos, Color(0.2, 1, 1), 0.5)
		if b.flank_target.is_finite() and b.state == EnemyBrain.State.COMBAT:
			_line(s.global_position + up, b.flank_target + up, Color(1, 0.3, 1))
		var lb: Label3D = _labels.get(s)
		if lb == null or not is_instance_valid(lb):
			lb = Label3D.new()
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.no_depth_test = true
			lb.pixel_size = 0.01
			lb.font_size = 40
			lb.outline_size = 8
			add_child(lb)
			_labels[s] = lb
		lb.modulate = col
		lb.global_position = s.global_position + Vector3.UP * 2.4
		lb.text = "%s\n%s · %s\n%s%s" % [s.soldier_name, BotTraits.trait_name(b.persona), b.state_name(), b.goal_kind,
			"  [%.0fs]" % b.nav.prog_t if b.nav.prog_t > 2.0 else ""]
	for k in _labels.keys():
		if not seen.has(k):
			if is_instance_valid(_labels[k]):
				_labels[k].queue_free()
			_labels.erase(k)
	var m = Game.current_mission()
	if m and m.has_method("mp_zones"):
		var zs: Array = m.mp_zones()
		for i in zs.size():
			var o: int = int(Net.zone_owner[i]) if i < Net.zone_owner.size() else -1
			var zc := (zs[i]["xf"] as Transform3D).origin
			_circle(BotGoals.ground(self, zc) if is_inside_tree() else zc, BotGoals.zone_radius(zs[i]),
				team_color(o) if o in [0, 1] else Color(0.8, 0.8, 0.8))
	_mesh.surface_end()
