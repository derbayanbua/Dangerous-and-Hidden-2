class_name VehicleDrive
extends RefCounted
## Fahrphysik aller Fahrzeuge – BEWUSSTE ABWEICHUNG VOM ORIGINAL (Vorgabe Auftraggeber: zeitgemäßes Fahrgefühl
## statt der schwachen Originalphysik). Eigenes Raycast-Fahrwerk auf dem VehicleBody3D (ohne VehicleWheel3D):
##  * je Rad Feder/Dämpfer (Eigenfrequenz je Typ), Anschlag, Stabilisator je Achse; die Federkräfte ergeben die
##    Radlasten → Gewichtsverlagerung beim Beschleunigen/Bremsen/Kurvenfahren entsteht von selbst,
##  * Reifenkraft mit Schlupfkurve (Maximum bei ~8° Schräglauf) und Reibungskreis (Antrieb, Bremse und
##    Seitenführung teilen sich den Grip), vorne etwas weniger Grip → moderates Untersteuern,
##  * tiefer Schwerpunkt + Seitenkraft-Angriff nahe Schwerpunkthöhe → kein Überschlag bei normaler Kurvenfahrt,
##  * geschwindigkeitsabhängiger, geglätteter Lenkeinschlag, Handbremse blockiert die Hinterräder und senkt ihre
##    Seitenführung (kontrolliertes Driften), ABS-artige Betriebsbremse,
##  * Motor (Leistungskurve über der Drehzahl, Begrenzer), automatisches Getriebe mit Schaltpause, Rückwärtsgang,
##  * Untergrund-Grip/Rollwiderstand aus dem Original-Material unter jedem Rad (surface.bin / hdmaterials.def),
##  * Kettenfahrzeuge: Kettenlenkung über ein Giermoment (Drehen auf der Stelle), hohe Seitenführung der Ketten;
##    Halbketten lenken mit den Vorderrädern, die Ketten treiben.
## Aus den Originaldaten [O] (orig_cache/<m>/vehicles.json ← tools/fmt_vehicles.py, Car-Parameterblock): Masse,
## Motorleistung (als PS gedeutet), Drehzahlen, Gänge, Gesamtübersetzungen. Aus dem Originalmodell: Radpositionen
## (Frames DWHLnn/DWHRnn mit Rad-Mesh), Radradien, Abmessungen. Höchstgeschwindigkeit = Höchstdrehzahl × Radumfang /
## Übersetzung des obersten Gangs. Alle übrigen Kennwerte (Federn, Reifen, Bremse, Luftwiderstand) sind Design [E].

enum Kind { CAR, TRUCK, BIKE, HALFTRACK, TANK }
const KIND_NAMES := ["Pkw", "Lkw", "Krad mit Beiwagen", "Halbkette", "Kettenfahrzeug"]
const G := 9.81
const PS_TO_W := 735.5

## Kübelwagen (ARCTIC1 la_kubelW_) [O] – für Fahrzeuge ohne Originaldaten (Übungseinsätze)
const KUBEL_DATA := {"mass_kg": 1100.0, "power": 45.0, "rpm_max": 4200.0, "rpm_limit": 4600.0, "rpm_idle": 550.0,
	"gears": 4, "ratio_reverse": 23.9, "ratios": [21.65, 12.85, 8.59, 6.75]}

## Typwerte [E]: Federfrequenz Hz, Dämpfungsmaß, Bremsverzögerung g, ½·ρ·cW·A, Lenkeinschlag rad,
## Schwerpunkt über Radmitte m, Reifen-Grip vorne/hinten, Stabilisator (Anteil der Federrate)
const KIND_TUNING := {
	Kind.CAR: {"freq": 1.6, "zeta": 0.45, "brake_g": 0.9, "drag": 0.75, "steer": 0.62, "cog": 0.12, "mu_f": 0.95, "mu_r": 1.0, "arb": 0.7},
	Kind.TRUCK: {"freq": 1.35, "zeta": 0.5, "brake_g": 0.7, "drag": 2.6, "steer": 0.58, "cog": 0.25, "mu_f": 0.92, "mu_r": 0.95, "arb": 0.9},
	Kind.BIKE: {"freq": 1.8, "zeta": 0.45, "brake_g": 0.8, "drag": 0.45, "steer": 0.5, "cog": 0.1, "mu_f": 0.95, "mu_r": 1.0, "arb": 0.6},
	Kind.HALFTRACK: {"freq": 1.3, "zeta": 0.55, "brake_g": 0.65, "drag": 2.4, "steer": 0.55, "cog": 0.2, "mu_f": 0.9, "mu_r": 1.05, "arb": 0.9},
	Kind.TANK: {"freq": 1.25, "zeta": 0.6, "brake_g": 0.55, "drag": 4.5, "steer": 0.0, "cog": 0.25, "mu_f": 1.0, "mu_r": 1.0, "arb": 0.8},
}


class Wheel:
	var center := Vector3.ZERO       ## Radmitte in Ruhelage (Fahrzeug lokal)
	var radius := 0.35
	var steer := false
	var driven := false
	var front := false
	var side := 0.0                  ## +1 links (+X), −1 rechts
	var pair: Wheel = null           ## Gegenrad derselben Achse (Stabilisator)
	var length := 0.0                ## Federlänge Anker → Radmitte
	var prev_len := -1.0
	var contact := false
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var load := 0.0
	var mat := -1
	var mat_t := 0.0
	var grip := Vector2(0.85, 0.03)  ## Reibwert, Rollwiderstand
	var slip := 0.0                  ## Ausnutzung des Reibungskreises (>1 = rutscht)
	var spin := 0.0
	var query: PhysicsRayQueryParameters3D
	var node: Node3D                 ## sichtbares Rad (Modell-Dummy DWH* bzw. Platzhalter)
	var base := Transform3D()
	var up_p := Vector3.UP           ## Hochachse im Elternraum des Knotens
	var axle_p := Vector3.RIGHT      ## Radachse im Elternraum


var v: RigidBody3D
var kind := Kind.CAR
var wheels: Array = []
var mass := 1100.0
var power_w := 28000.0
var rpm_max := 4200.0
var rpm_limit := 4600.0
var rpm_idle := 550.0
var ratios: Array = [21.65, 12.85, 8.59, 6.75]
var ratio_reverse := 23.9
var drive_radius := 0.36
var top_speed := 23.0              ## m/s (aus Getriebe/Radradius)
var travel_up := 0.18
var rest_len := 0.3
var spring_k := 30000.0
var damp_c := 3000.0
var arb_k := 20000.0
var steer_lock := 0.6
var brake_g := 0.9
var drag := 0.75
var mu_front := 0.95
var mu_rear := 1.0
var track_half := 0.7
var length_m := 3.6
var pivot_rate := 0.6              ## rad/s auf der Stelle (Kettenfahrzeuge)
var data_source := "Kübelwagen-Standard"

## Eingaben (Spieler oder Skript-KI)
var throttle := 0.0                ## −1..1 (negativ: bremsen bzw. rückwärts)
var steer_in := 0.0                ## −1..1 (+ = links)
var brake_in := 0.0                ## 0..1 zusätzliche Betriebsbremse (KI)
var handbrake := false
var parked := false                ## ohne Fahrer: Feststellbremse

## Zustand
var gear := 1                      ## −1 rückwärts, 1..n
var rpm := 550.0
var load_frac := 0.0               ## Motorlast 0..1 (Klang)
var steer_angle := 0.0
var speed := 0.0                   ## Längsgeschwindigkeit m/s (+ vorwärts)
var grounded := 0
var surface_override := -2         ## Tests: Material erzwingen (−2 = aus, −1 = unbekannter Boden)
var drive_force := 0.0
var _shift_t := 0.0
var _prev_vel := Vector3.ZERO
var _upset_t := 0.0
var impact_cb: Callable            ## (Δv m/s, Kollisionsobjekt) bei harten Stößen


static func kind_for(model: String) -> Kind:
	var m := model.to_lower()
	for k in ["tiger", "sherman", "panzer", "panther", "isu", "pancer", "tank"]:
		if m.contains(k):
			return Kind.TANK
	if m.contains("hakl") or m.contains("halftruck") or m.contains("half"):
		return Kind.HALFTRACK
	if m.contains("bmw"):
		return Kind.BIKE
	for k in ["opel", "blitz", "bedford", "krupp", "puma", "truck", "lkw"]:
		if m.contains(k):
			return Kind.TRUCK
	return Kind.CAR


## Untergrund-Grip je Original-Material (Zeile in hdmaterials.def) [E]: (Reibwert, Rollwiderstand)
static func surface_grip(m: int) -> Vector2:
	match m:
		33, 37:
			return Vector2(0.18, 0.015)         # Eis
		34, 35, 36, 91:
			return Vector2(0.45, 0.05)          # Schnee
		41, 42, 45:
			return Vector2(0.6, 0.09)           # Sand
		43, 44, 86, 93:
			return Vector2(0.55, 0.08)          # Lehm, Schlamm
		46, 47, 50, 92, 68, 69:
			return Vector2(0.72, 0.04)          # Gras, Waldboden
		49, 61, 95, 97:
			return Vector2(0.8, 0.03)           # Schotter, Feldweg, Schutt
		31, 32, 70, 94:
			return Vector2(0.4, 0.2)            # Wasser
		-1:
			return Vector2(0.85, 0.03)          # unbekannt: fester Naturboden
	return Vector2(1.0, 0.015)                  # Straße, Pflaster, Beton, Holz, Metall


static func surface_name(m: int) -> String:
	var g := surface_grip(m)
	if g.x < 0.3:
		return "Eis"
	if g.x < 0.5:
		return "Schnee/Wasser"
	if g.x < 0.65:
		return "Sand/Schlamm"
	if g.x < 0.75:
		return "Gras"
	if g.x < 0.9:
		return "Schotter/Boden"
	return "Straße"


# --- Aufbau -------------------------------------------------------------------------------

## data: Eintrag aus vehicles.json (leer = Kübelwagen-Werte); model: Modellname (Typbestimmung)
func setup(body: RigidBody3D, data: Dictionary, model: String, visual: Node3D, size: Vector3, box_center: Vector3) -> void:
	v = body
	kind = kind_for(model)
	var d: Dictionary = data if not data.is_empty() else KUBEL_DATA
	if not data.is_empty():
		data_source = "Original (%s)" % model
	mass = maxf(float(d.get("mass_kg", 1100.0)), 100.0)
	power_w = float(d.get("power", 45.0)) * PS_TO_W * 0.85
	rpm_max = float(d.get("rpm_max", 4200.0))
	rpm_limit = maxf(float(d.get("rpm_limit", rpm_max * 1.1)), rpm_max + 100.0)
	rpm_idle = float(d.get("rpm_idle", 600.0))
	ratios = []
	for r in d.get("ratios", KUBEL_DATA["ratios"]):
		if float(r) > 0.1:
			ratios.append(float(r))
	if ratios.is_empty():
		ratios = KUBEL_DATA["ratios"].duplicate()
	ratio_reverse = float(d.get("ratio_reverse", ratios[0]))
	if ratio_reverse < 0.1:
		ratio_reverse = ratios[0]
	length_m = size.z
	if visual != null:
		_wheels_from_model(visual)
	if wheels.size() < 3:
		_placeholder_wheels(size, box_center, visual == null)
	_classify()
	_derive()
	v.mass = mass
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var cy := 0.0
	var cx := 0.0
	var cz := 0.0
	for w in wheels:
		cy += (w as Wheel).center.y
		cx += (w as Wheel).center.x
		cz += (w as Wheel).center.z
	cy /= wheels.size()
	v.center_of_mass = Vector3(cx / wheels.size() * 0.5, cy + float(KIND_TUNING[kind]["cog"]), cz / wheels.size())
	v.contact_monitor = true
	v.max_contacts_reported = 6
	# Standard-Dämpfung des Projekts (linear 0,1/s) würde wie eine Bremse wirken: Widerstände rechnet das Fahrwerk
	v.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.linear_damp = 0.0
	v.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.angular_damp = 0.3
	for w in wheels:
		var q := PhysicsRayQueryParameters3D.new()
		q.collision_mask = 1
		q.exclude = [v.get_rid()]
		(w as Wheel).query = q


func _wheels_from_model(visual: Node3D) -> void:
	var inv := v.global_transform.affine_inverse()
	for n in visual.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_upper()
		if not (nm.begins_with("DWHL") or nm.begins_with("DWHR")):
			continue
		var bb := AABB()
		var any := false
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var b: AABB = (inv * m.global_transform) * m.get_aabb()
			bb = b if not any else bb.merge(b)
			any = true
		if not any:
			continue          # Dummy ohne Rad-Mesh (z. B. BMW DWHR00)
		var w := Wheel.new()
		w.radius = clampf(maxf(bb.size.y, bb.size.z) * 0.5, 0.15, 0.9)
		w.center = bb.get_center()
		w.node = n
		w.base = n.transform
		var prel: Transform3D = inv * (n.get_parent() as Node3D).global_transform
		var pinv := prel.basis.inverse()
		w.up_p = (pinv * Vector3.UP).normalized()
		w.axle_p = (pinv * Vector3.RIGHT).normalized()
		wheels.append(w)


## Platzhalter-Räder (Übungseinsätze ohne Originalmodell bzw. Modell ohne Rad-Frames)
func _placeholder_wheels(size: Vector3, box_center: Vector3, visible: bool) -> void:
	wheels.clear()
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.08, 0.08, 0.08)
	var hx := size.x * 0.5 - 0.05
	var r := 0.38 if kind != Kind.TANK else 0.4
	var zs: Array = []
	if kind == Kind.TANK:
		var n := 6
		for i in n:
			zs.append(lerpf(-size.z * 0.5 + 0.6, size.z * 0.5 - 0.6, float(i) / float(n - 1)))
	else:
		zs = [-(size.z * 0.5 - 0.6), size.z * 0.5 - 0.6]
	for z in zs:
		for sx in [-1.0, 1.0]:
			var w := Wheel.new()
			w.center = Vector3(sx * hx + box_center.x, r + 0.02, float(z) + box_center.z)
			w.radius = r
			var pivot := Node3D.new()
			pivot.position = w.center
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = r
			c.bottom_radius = r
			c.height = 0.22 if kind != Kind.TANK else 0.4
			c.radial_segments = 14
			mi.mesh = c
			mi.rotation.z = PI * 0.5
			mi.material_override = tire
			pivot.add_child(mi)
			pivot.visible = visible
			v.add_child(pivot)
			w.node = pivot
			w.base = pivot.transform
			wheels.append(w)


func _classify() -> void:
	var zmin := INF
	var zmax := -INF
	for w in wheels:
		zmin = minf(zmin, (w as Wheel).center.z)
		zmax = maxf(zmax, (w as Wheel).center.z)
	var span := maxf(zmax - zmin, 0.5)
	track_half = 0.3
	var all_wd := false
	if kind == Kind.CAR and v.get("vehicle_name") != null:
		all_wd = String(v.get("vehicle_name")).to_lower().contains("jeep")
	for w in wheels:
		var wh := w as Wheel
		wh.front = wh.center.z > zmax - span * 0.2
		wh.side = 1.0 if wh.center.x > 0.0 else -1.0
		match kind:
			Kind.TANK:
				wh.steer = false
				wh.driven = true
			Kind.CAR:
				wh.steer = wh.front
				wh.driven = all_wd or not wh.front
			_:
				wh.steer = wh.front
				wh.driven = not wh.front
		track_half = maxf(track_half, absf(wh.center.x))
	# Achspartner für den Stabilisator
	for w in wheels:
		var wh := w as Wheel
		var best: Wheel = null
		for o in wheels:
			var ow := o as Wheel
			if ow == wh or signf(ow.center.x) == signf(wh.center.x):
				continue
			if absf(ow.center.z - wh.center.z) < 0.35 and (best == null or absf(ow.center.z - wh.center.z) < absf(best.center.z - wh.center.z)):
				best = ow
		wh.pair = best


func _derive() -> void:
	var t: Dictionary = KIND_TUNING[kind]
	var n := float(wheels.size())
	var m_corner := mass / n
	var omega := TAU * float(t["freq"])
	spring_k = m_corner * omega * omega
	damp_c = 2.0 * float(t["zeta"]) * sqrt(spring_k * m_corner)
	arb_k = spring_k * float(t["arb"])
	var rsum := 0.0
	var rmax := 0.0
	var nd := 0
	for w in wheels:
		var wh := w as Wheel
		if wh.driven:
			rsum += wh.radius
			rmax = maxf(rmax, wh.radius)
			nd += 1
	drive_radius = (rsum / maxf(nd, 1)) if kind != Kind.TANK else rmax
	drive_radius = clampf(drive_radius, 0.2, 0.9)
	travel_up = clampf(drive_radius * 0.45, 0.1, 0.22)
	rest_len = travel_up + m_corner * G / spring_k
	steer_lock = float(t["steer"])
	brake_g = float(t["brake_g"])
	drag = float(t["drag"])
	mu_front = float(t["mu_f"])
	mu_rear = float(t["mu_r"])
	top_speed = rpm_max / 60.0 * TAU * drive_radius / float(ratios[ratios.size() - 1])
	pivot_rate = 0.65 if mass < 30000.0 else 0.45
	gear = 1
	rpm = rpm_idle


func reverse_top_speed() -> float:
	return rpm_max / 60.0 * TAU * drive_radius / ratio_reverse


# --- Steuerung ---------------------------------------------------------------------------

## Skript-/KI-Fahrer: auf einen Zielpunkt zu, mit Wunschgeschwindigkeit (m/s, negativ = rückwärts)
func ai_control(target: Vector3, want: float, delta: float) -> void:
	var lt := v.to_local(target)
	var reverse := want < 0.0
	var ang := atan2(lt.x, lt.z) if not reverse else atan2(lt.x, -lt.z)
	var lock := current_lock()
	var s := clampf(ang / maxf(lock, 0.05), -1.0, 1.0)
	if kind == Kind.TANK:
		s = clampf(ang * 2.0, -1.0, 1.0)
	steer_in = -s if reverse else s
	var cur := speed
	var w := absf(want)
	# große Richtungsabweichung: langsamer (Kurve), Panzer drehen zuerst
	var turn := absf(ang)
	if turn > 0.5:
		w = minf(w, lerpf(w, 2.5, clampf((turn - 0.5) / 1.0, 0.0, 1.0)))
	if kind == Kind.TANK and turn > 0.9:
		w = 0.0
	var v_dir := -cur if reverse else cur
	var err := w - v_dir
	brake_in = 0.0
	handbrake = false
	if err >= 0.0:
		throttle = clampf(err * 0.6 + 0.25, 0.0, 1.0) * (-1.0 if reverse else 1.0)
		if w <= 0.01:
			throttle = 0.0
	else:
		throttle = 0.0
		if err < -1.0:
			brake_in = clampf(-err * 0.35, 0.0, 1.0)
	if w <= 0.01 and absf(cur) < 0.5:
		brake_in = 1.0


func current_lock() -> float:
	# geschwindigkeitsabhängig: volle Lenkung im Stand, bei hoher Fahrt ~ ein Drittel
	var f := clampf(absf(speed) / maxf(top_speed, 8.0), 0.0, 1.0)
	return steer_lock * lerpf(1.0, 0.32, sqrt(f))


func set_player_input(thr: float, st: float, hb: bool) -> void:
	throttle = clampf(thr, -1.0, 1.0)
	steer_in = clampf(st, -1.0, 1.0)
	handbrake = hb
	brake_in = 0.0
	parked = false


func release_controls(park: bool) -> void:
	throttle = 0.0
	steer_in = 0.0
	brake_in = 0.0
	handbrake = false
	parked = park


# --- Physik ------------------------------------------------------------------------------

func integrate(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	if dt <= 0.0:
		return
	var xf := state.transform
	var b := xf.basis.orthonormalized()
	var up := b.y
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com := xf.origin + state.center_of_mass
	speed = lin.dot(b.z)
	_impact_check(state, lin)
	_engine(dt)
	# Lenkung glätten (zurück zur Mitte schneller)
	var want_angle := steer_in * current_lock()
	var rate := 2.2 if absf(want_angle) > absf(steer_angle) else 3.5
	steer_angle = move_toward(steer_angle, want_angle, rate * dt)
	var space := state.get_space_state()
	grounded = 0
	# große Schritte (Engine.time_scale > 1): Feder/Dämpfer begrenzen, damit die explizite Integration stabil bleibt
	var m_c := mass / float(wheels.size())
	var k := minf(spring_k, m_c * pow(0.6 / dt, 2.0))
	var c := minf(damp_c, m_c * 0.8 / dt)
	var rl := travel_up + m_c * G / k
	var driven_load := 0.0
	# 1) Federn
	for w in wheels:
		var wh := w as Wheel
		var anchor := xf * (wh.center + Vector3.UP * travel_up)
		var max_len := rest_len + 0.05
		wh.query.from = anchor
		wh.query.to = anchor - up * (max_len + wh.radius)
		var hit := space.intersect_ray(wh.query)
		if hit.is_empty():
			wh.contact = false
			wh.load = 0.0
			wh.length = move_toward(wh.length, max_len, dt * 2.0)
			wh.prev_len = -1.0
			continue
		var l := maxf(anchor.distance_to(hit["position"]) - wh.radius, 0.0)
		var vc := 0.0 if wh.prev_len < 0.0 else (wh.prev_len - l) / dt
		wh.prev_len = l
		wh.length = l
		var f := k * (rl - l) + c * vc * (0.8 if vc > 0.0 else 1.2)
		if l < 0.03:
			f += k * 3.0 * (0.03 - l)               # Gummianschlag
		wh.load = maxf(f, 0.0)
		wh.contact = true
		wh.point = hit["position"]
		wh.normal = hit["normal"]
		grounded += 1
	# Stabilisatoren
	for w in wheels:
		var wh := w as Wheel
		if wh.contact and wh.pair != null and wh.pair.contact:
			wh.load = maxf(wh.load + arb_k * (wh.pair.length - wh.length) * 0.5, 0.0)
	for w in wheels:
		var wh := w as Wheel
		if wh.contact and wh.driven:
			driven_load += wh.load
	# 2) Reifen
	var lat_center := lin
	for w in wheels:
		var wh := w as Wheel
		if not wh.contact:
			continue
		_update_surface(wh, dt)
		var p := wh.point
		state.apply_force(up * wh.load, p - xf.origin)
		var dir := b.z
		if wh.steer:
			dir = dir.rotated(up, steer_angle)
		var n := wh.normal
		var fwd := (dir - n * dir.dot(n)).normalized()
		var side := n.cross(fwd).normalized()
		var vel := lin + ang.cross(p - com)
		var vl := vel.dot(fwd)
		var vs := vel.dot(side)
		var mu := wh.grip.x * (mu_front if wh.front else mu_rear)
		if kind == Kind.TANK or (kind == Kind.HALFTRACK and not wh.front):
			mu *= lerpf(1.15, 1.0, wh.grip.x)       # Ketten greifen auch auf losem Boden
		var fmax := mu * wh.load
		var m_i := wh.load / G
		var fx := 0.0
		if wh.driven and driven_load > 0.0:
			# Antriebsschlupfregelung: höchstens 80 % des Grips als Antrieb, der Rest bleibt Seitenführung
			var tc := 0.8 * fmax
			fx += clampf(drive_force * wh.load / driven_load, -tc, tc)
		var locked := handbrake and not wh.front and kind != Kind.TANK
		var bcap := brake_in * brake_g * wh.load
		if parked:
			bcap = maxf(bcap, fmax)
		if locked:
			bcap = maxf(bcap, fmax * 0.75)
		var hold := clampf(-vl * m_i / dt, -bcap, bcap)
		fx += hold
		var rr := wh.grip.y * wh.load * (1.5 if kind == Kind.TANK else 1.0)
		fx += clampf(-vl * m_i / dt, -rr, rr)
		# Seitenführung
		var fy := 0.0
		var spd := absf(vl)
		if kind == Kind.TANK:
			var vs_c := lat_center.dot(side)
			fy = clampf(-vs_c * m_i / dt * 0.6, -fmax, fmax)
		else:
			var alpha := atan2(vs, maxf(spd, 0.6))
			var pac := sin(1.5 * atan(12.0 * alpha))
			var fy_dyn := -fmax * pac
			var fy_st := clampf(-vs * m_i / dt * 0.5, -fmax, fmax)
			fy = lerpf(fy_st, fy_dyn, clampf((spd - 1.0) / 3.0, 0.0, 1.0))
			# nie mehr Seitenkraft, als die Quergeschwindigkeit in einem Schritt aufhebt (stabil bei 60 Hz)
			var stop_f := absf(vs) * m_i / dt * 0.5
			fy = clampf(fy, -stop_f, stop_f)
			if locked:
				fy *= 0.65
		# Reibungskreis: Längskraft zuerst, Seitenführung aus dem Rest
		fx = clampf(fx, -fmax, fmax)
		var lat_cap := sqrt(maxf(fmax * fmax - fx * fx, 0.0))
		if locked:
			lat_cap = fmax * 0.65
		fy = clampf(fy, -lat_cap, lat_cap)
		wh.slip = Vector2(fx, fy).length() / maxf(fmax, 1.0)
		# Angriff nahe Schwerpunkthöhe (verringert das Wankmoment, verhindert Überschläge)
		var h := (com - p).dot(up)
		var at := p + up * (h * 0.55)
		state.apply_force(fwd * fx + side * fy, at - xf.origin)
		wh.spin = wrapf(wh.spin + (0.0 if locked else vl) / wh.radius * dt, -TAU, TAU)
	# 3) Kettenlenkung: Giermoment auf eine Soll-Drehrate (auf der Stelle am schnellsten), begrenzt durch den
	#    Kettengrip; die Ketten halten das Fahrzeug seitlich, behindern das Drehen aber nicht
	if grounded > 0 and kind == Kind.TANK:
		var tr := pivot_rate * lerpf(1.0, 0.55, clampf(absf(speed) / maxf(top_speed, 1.0), 0.0, 1.0))
		var want := steer_in * tr
		var cur := ang.dot(up)
		var inertia := mass * (length_m * length_m + 4.0 * track_half * track_half) / 12.0
		var tq_max := 0.8 * mass * G * track_half * float(grounded) / float(wheels.size())
		state.apply_torque(up * clampf((want - cur) * inertia * 6.0, -tq_max, tq_max))
	# Stabilitätshilfe (wie moderne Spiele/ESP): Gierrate über dem Haftungsgrenzwert wird gedämpft – kein Dreher
	# bei Vollausschlag; mit Handbremse bewusst aus (Drift erlaubt, nur Vollkreisel abgefangen)
	if grounded > 0 and kind != Kind.TANK and absf(speed) > 4.0:
		var cur_y := ang.dot(up)
		var lim := 1.15 * G * mu_rear / absf(speed) * (2.2 if handbrake else 1.0)
		if absf(cur_y) > lim:
			var inertia_y := mass * (length_m * length_m + 4.0 * track_half * track_half) / 12.0
			state.apply_torque(-up * (cur_y - signf(cur_y) * lim) * inertia_y * 4.0)
	# 4) Luftwiderstand
	var sp := lin.length()
	if sp > 0.1:
		state.apply_central_force(-lin * sp * drag)
	# 5) Aufrichten nach Überschlag (zeitgemäße Komfortfunktion)
	if b.y.y < 0.3 and sp < 1.5:
		_upset_t += dt
		if _upset_t > 3.0:
			_upset_t = 0.0
			var yaw := atan2(b.z.x, b.z.z)
			state.transform = Transform3D(Basis(Vector3.UP, yaw), xf.origin + Vector3.UP * 1.2)
			state.linear_velocity = Vector3.ZERO
			state.angular_velocity = Vector3.ZERO
	else:
		_upset_t = 0.0
	_prev_vel = state.linear_velocity


func _update_surface(wh: Wheel, dt: float) -> void:
	if surface_override > -2:
		wh.grip = surface_grip(surface_override)
		wh.mat = surface_override
		return
	wh.mat_t -= dt
	if wh.mat_t > 0.0:
		return
	wh.mat_t = 0.25
	wh.mat = OrigAudio.floor_material(wh.point + Vector3.UP * 0.1)
	wh.grip = surface_grip(wh.mat)


func _engine(dt: float) -> void:
	var accel := 0.0
	var brake_cmd := 0.0
	if throttle > 0.05:
		if speed < -0.8:
			brake_cmd = throttle
		else:
			if gear < 0:
				gear = 1
			accel = throttle
	elif throttle < -0.05:
		if speed > 0.8:
			brake_cmd = -throttle
		else:
			gear = -1
			accel = -throttle
	brake_in = maxf(brake_in, brake_cmd)
	var ratio: float = ratio_reverse if gear < 0 else float(ratios[clampi(gear - 1, 0, ratios.size() - 1)])
	var wheel_rpm := absf(speed) / drive_radius * 60.0 / TAU
	var rpm_w := wheel_rpm * ratio
	# Automatik: hochschalten kurz vor der Höchstdrehzahl, zurück bei niedriger Drehzahl
	_shift_t = maxf(_shift_t - dt, 0.0)
	if gear > 0 and _shift_t <= 0.0:
		if rpm_w > rpm_max * 0.95 and gear < ratios.size():
			gear += 1
			_shift_t = 0.25 if kind == Kind.CAR or kind == Kind.BIKE else 0.45
		elif gear > 1 and rpm_w < rpm_max * 0.42:
			gear -= 1
			_shift_t = 0.2
		ratio = float(ratios[gear - 1])
		rpm_w = wheel_rpm * ratio
	var launch := lerpf(rpm_idle, rpm_max * 0.55, accel)
	var target := maxf(rpm_w, launch if accel > 0.0 else rpm_idle)
	if _shift_t > 0.0:
		target = maxf(rpm_w, rpm_idle)
	rpm = lerpf(rpm, minf(target, rpm_limit), clampf(dt * 8.0, 0.0, 1.0))
	drive_force = 0.0
	load_frac = 0.0
	if accel > 0.0 and _shift_t <= 0.0:
		var x := clampf(maxf(rpm, rpm_max * 0.3) / rpm_max, 0.3, 1.1)
		var p := power_w * clampf(x * (2.0 - x), 0.2, 1.0)
		var om := maxf(rpm, rpm_max * 0.3) * TAU / 60.0
		var f := p / om * ratio / drive_radius
		f = minf(f, power_w / maxf(absf(speed), 2.5))       # Kupplung/Leistungsgrenze beim Anfahren
		if rpm_w > rpm_max:
			f *= clampf((rpm_limit - rpm_w) / maxf(rpm_limit - rpm_max, 1.0), 0.0, 1.0)
		drive_force = f * accel * (1.0 if gear > 0 else -1.0)
		load_frac = accel
	elif brake_cmd <= 0.0 and absf(speed) > 0.3:
		drive_force = -signf(speed) * mass * G * 0.035 * clampf(absf(speed) / 3.0, 0.0, 1.0)   # Motorbremse
	# Kettenfahrzeug dreht auf der Stelle: Motor arbeitet
	if kind == Kind.TANK and absf(steer_in) > 0.1:
		load_frac = maxf(load_frac, absf(steer_in) * 0.7)
		rpm = maxf(rpm, lerpf(rpm_idle, rpm_max * 0.6, absf(steer_in)))


func _impact_check(state: PhysicsDirectBodyState3D, lin: Vector3) -> void:
	var dv := (lin - _prev_vel).length()
	if dv < 4.0 or state.get_contact_count() == 0:
		return
	var other: Object = state.get_contact_collider_object(0)
	if impact_cb.is_valid():
		impact_cb.call(dv, other)


# --- Darstellung ---------------------------------------------------------------------------

func update_visuals() -> void:
	for w in wheels:
		var wh := w as Wheel
		if wh.node == null or not is_instance_valid(wh.node):
			continue
		var l := wh.length if wh.contact else rest_len + 0.05
		var drop := travel_up - l
		var st := steer_angle if wh.steer else 0.0
		var bs := Basis(wh.up_p, st) * Basis(wh.axle_p, wh.spin) * wh.base.basis
		wh.node.transform = Transform3D(bs, wh.base.origin + wh.up_p * drop)


## Messwerte für Tests/Anzeige
func info() -> Dictionary:
	return {"kind": KIND_NAMES[kind], "mass": mass, "power_ps": power_w / PS_TO_W / 0.85, "top_kmh": top_speed * 3.6,
		"wheels": wheels.size(), "radius": drive_radius, "gear": gear, "rpm": rpm, "source": data_source}
