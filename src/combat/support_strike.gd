class_name SupportStrike
extends Node3D
## B-011: Artillerieschlag / Luftangriff per Funkgerät (Mehrspieler, server-autoritativ).
## Original (hd2.exe v1.12, docs/re_notes_support_strike.md):
##   - Gegenstände 243 „Radio-AirAttack“ (d_radio, T1243 „Funkgerät für Luftangriff“) und 244 „Radio-Artillery“
##     (d_radiob, T1244), je 4,5 kg; liegen auf Karten mit AIRCRAFTATACK frei (actor_params non_actor_stores).
##   - MP-Befehlsmenü Eintrag 9 „Unterst. anf.“ (T7208 → Menü 59) nur mit Gegenstand 243 oder 244 aktiv (0x4C018C);
##     im Untermenü „Flugzeug anfordern“ (T7280 → Befehl 33) nur mit 243, „Artillerie rufen“ (T7281 → 34) nur mit 244
##     (0x4C02DD) [B]. Die Wirkung der Befehle 33/34 (Schaden, Radius, Ablauf) ist nicht dekodiert [?].
## Umsetzung nach Backlog (Vorgabe Auftraggeber) [E]: Funkgerät erscheint alle n Minuten ungefähr in der Kartenmitte
## (bzw. an einer Original-Funkgerätstelle), Träger fordert genau einen Schlag an (Ziffernblock 0 → Untermenü wie
## Original, Ziel anvisieren, Linksklick), 3D-Kreis für alle, Einschlag nach 5 s. Artillerie 20 m Durchmesser stark,
## Luftangriff 25 m Durchmesser schwächer mit Überflug (Original-Modell la_ju88, Motorklang motor1–4.wav).
## Netz: alle Nachrichten über den Autoload Net (_sup_*), Server entscheidet Spawn, Aufnahme, Anforderung, Schaden.

const KIND_AIR := 0                     ## Befehl 33, Gegenstand 243
const KIND_ART := 1                     ## Befehl 34, Gegenstand 244
const ITEM := [243, 244]
const CMD_TEXT := [7280, 7281]
const CMD_FALLBACK := ["Flugzeug anfordern", "Artillerie rufen"]
const NAME := ["Luftangriff", "Artillerieschlag"]
const CAUSE := ["support_air", "support_art"]  ## Kill-Feed-Ursache (MpFeedback.weapon_label/weapon_icon)
const RADIUS := [12.5, 10.0]            ## Wirkungsbereich: 25 m bzw. 20 m Durchmesser
const WAVE_STRENGTH := [45.0, 90.0]     ## Stärke je Einschlagwelle (linear 1 − d/r wie WeaponDB.explosion_damage)
const WAVES := [3, 4]
const WAVE_GAP_S := [0.35, 0.7]
const DELAY_S := 5.0                    ## Ziel markiert → erster Einschlag
const MAX_RANGE := 400.0                ## Zielentfernung vom Funker
const PICKUP_RANGE := 2.6
const OPEN_EXTENT := 80.0               ## [E] offene Karte: Spawnbereich mindestens so groß (Diagonale)
const SKY_CLEAR := 60.0                 ## freier Himmel über Ziel/Funkgerät
const PLANE_SPEED := 100.0              ## wie OrigAirAttack (hd2.exe 0x5E5960)
const PLANE_HEIGHT := 90.0
const RADIO_MODEL := ["d_radio", "d_radiob"]
const RADIO_DIRS := ["africa2_mp_zone", "africa5_mp_zone", "burma2_obj"]
const PLANE_MODELS := ["africa5/models/la_ju88.glb", "africa2/models/la_bf109let.glb", "africa2_mp_zone/models/la_bf109 trop.glb"]

var mission: Node
var map_open := false
var center := Vector3.ZERO
var spawn_candidates: Array = []       ## Original-Funkgerätstellen (sonst Kartenmitte)
## Zustand (alle Rechner, vom Server gesetzt): 0 kein Funkgerät, 1 liegt, 2 getragen
var radio_state := 0
var radio_kind := KIND_ART
var radio_pos := Vector3.INF
var carrier := 0
## Server
var spawn_t := -1.0
var next_kind := KIND_ART
var strikes: Array = []                ## laufende Schläge {kind, pos, caller, team, t, wave}
var _carrier_pos := Vector3.INF
var _bot_t := 0.0
var _detect_t := -1.0
## Protokoll (Tests): Ereignisse auf diesem Rechner
var ev_log: Array = []
var booms := 0
var markers_shown := 0
var planes_shown := 0
## Anzeige
var _radio_node: RadioItem
var _markers: Array = []               ## [Node3D, Ablaufzeit ms]
var _ui: CanvasLayer
var _hint: Label
var _menu: Label
var _count: Label
var menu_open := false
var targeting := -1                    ## Zielwahl läuft für diese Art (−1 = nein)
var target_preview := Vector3.INF
var _preview: Node3D
var _strike_label_until := 0
var _strike_label := ""


func _init() -> void:
	name = "SupportStrike"


func setup(m: Node) -> void:
	mission = m
	process_mode = Node.PROCESS_MODE_PAUSABLE
	center = _map_center()
	_detect_t = 1.0                     # Physikraum braucht einen Schritt, bevor Strahlabfragen treffen
	spawn_candidates = _orig_radio_spots()
	if Net.is_online:
		_hide_orig_radios()
	if not Net.dedicated:
		_build_ui()
	spawn_t = interval_s()


# --- Karte ----------------------------------------------------------------------------------------------

func _spawns() -> Array:
	if mission and mission.has_method("mp_spawns"):
		return mission.mp_spawns()
	return []


func _map_center() -> Vector3:
	var pts := _spawns()
	if pts.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for p in pts:
		c += p["pos"] as Vector3
	return c / float(pts.size())


## Offene Karte: Registereintrag „support_open“ (eigene Karten), Original-Kennung AIRCRAFTATACK (mp.json), sonst
## [E] Spawnbereich ≥ OPEN_EXTENT und freier Himmel über der Kartenmitte
func _detect_open() -> bool:
	var reg: Dictionary = Game.MISSIONS.get(String(Net.settings.get("map", "")), {})
	if reg.has("support_open"):
		return bool(reg["support_open"])
	var mp = mission.get("mp") if mission else null
	if mp is Dictionary:
		for gs in (mp as Dictionary).get("game_styles", []):
			if gs is Dictionary and (gs as Dictionary).has("aircraft_attack"):
				return true          # Original-Kennung AIRCRAFTATACK (mpmaplist)
	var pts := _spawns()
	if pts.size() < 2:
		return false
	var box := AABB(pts[0]["pos"], Vector3.ZERO)
	for p in pts:
		box = box.expand(p["pos"])
	if Vector2(box.size.x, box.size.z).length() < OPEN_EXTENT:
		return false
	return _find_ground(center) != Vector3.INF


func _orig_radio_spots() -> Array:
	var out: Array = []
	var orig = mission.get("orig") if mission else null
	if orig == null:
		return out
	var ap = LsRuntime._read_json(String(orig.mission_dir) + "/actor_params.json")
	if typeof(ap) != TYPE_DICTIONARY:
		return out
	for r in ap.get("non_actor_stores", {}).get("", []):
		var pa: Array = r.get("pos", [])
		if int(r.get("item", -1)) in ITEM and pa.size() == 3:
			out.append(Vector3(pa[0], pa[1], -float(pa[2])))
	return out


## Frei liegende Original-Funkgeräte (OrigInteractive.OrigWorldItem) würden nicht abgeglichen: im Netz ersetzt
## durch das server-gesteuerte Funkgerät
func _hide_orig_radios() -> void:
	for n in get_tree().get_nodes_in_group("world_items"):
		if int(n.get("item")) in ITEM:
			n.visible = false
			n.set("enabled", false)


func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state if is_inside_tree() else null


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var sp := _space()
	if sp == null:
		return {}
	return sp.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))


func sky_open(p: Vector3) -> bool:
	return _ray(p + Vector3.UP * 0.6, p + Vector3.UP * SKY_CLEAR).is_empty()


## Begehbarer Boden mit freiem Himmel nahe p (Spirale bis 60 m), INF wenn keiner
func _find_ground(p: Vector3) -> Vector3:
	for r in [0.0, 4.0, 8.0, 12.0, 18.0, 25.0, 35.0, 45.0, 60.0]:
		var n: int = 1 if r == 0.0 else 8
		for i in n:
			var a := TAU * float(i) / float(n)
			var q := p + Vector3(cos(a), 0.0, sin(a)) * float(r)
			var hit := _ray(q + Vector3.UP * 150.0, q + Vector3.DOWN * 300.0)
			if hit.is_empty():
				continue
			var g: Vector3 = hit["position"]
			if (hit["normal"] as Vector3).y > 0.7 and sky_open(g):
				return g
	return Vector3.INF


func interval_s() -> float:
	var t := float(Net.settings.get("support_interval_s", 0.0))     # Tests: Sekunden statt Minuten
	return t if t > 0.0 else float(Net.rule("support_interval_min")) * 60.0


func enabled() -> bool:
	return Net.is_online and map_open and int(Net.rule("support_strike")) > 0


func kinds_allowed() -> Array:
	match int(Net.rule("support_strike")):
		1:
			return [KIND_ART]
		2:
			return [KIND_AIR]
		3:
			return [KIND_ART, KIND_AIR]
	return []


# --- Server ---------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _detect_t > 0.0:
		_detect_t -= delta
		if _detect_t <= 0.0:
			map_open = _detect_open()
			print("SUPPORT: Karte offen = ", map_open)
	_update_view()
	if not Net.is_online or not multiplayer.is_server():
		return
	_strikes_tick()
	if not enabled():
		if radio_state != 0:
			_set_radio(0, radio_kind, Vector3.INF, 0)
		return
	if radio_state == 2:
		var s: Soldier = Net._soldiers.get(carrier)
		if not is_instance_valid(s) or not s.alive:
			# Träger tot/weg: Funkgerät fällt an seiner letzten Stelle zu Boden
			var g: Vector3 = _find_ground(_carrier_pos) if _carrier_pos.is_finite() else Vector3.INF
			_set_radio(1, radio_kind, g if g.is_finite() else _carrier_pos, 0)
			_log("dropped")
		else:
			_carrier_pos = s.global_position
			if Net.players.get(carrier, {}).get("bot", false):
				_bot_use(s, delta)
	elif radio_state == 1:
		if bool(Net.rule("support_bots")):
			for id in Net._soldiers:
				var b: Soldier = Net._soldiers[id]
				if int(id) < 0 and is_instance_valid(b) and b.alive and b.global_position.distance_to(radio_pos) <= PICKUP_RANGE:
					server_pickup(int(id))
					break
	elif strikes.is_empty() and Net.game_state == Net.State.RUNNING and not Net.match_over:
		spawn_t -= delta
		if spawn_t <= 0.0:
			server_spawn()


func server_spawn() -> bool:
	var ks := kinds_allowed()
	if ks.is_empty():
		return false
	var kind: int = next_kind if ks.has(next_kind) else int(ks[0])
	next_kind = int(ks[(ks.find(kind) + 1) % ks.size()])
	var base: Vector3 = spawn_candidates[randi() % spawn_candidates.size()] if not spawn_candidates.is_empty() else center
	var g := _find_ground(base)
	if not g.is_finite():
		g = _find_ground(center)
	if not g.is_finite():
		spawn_t = 10.0
		return false
	_set_radio(1, kind, g + Vector3.UP * 0.05, 0)
	Net._announce("Funkgerät (%s) in der Kartenmitte abgeworfen." % NAME[kind])
	_log("spawn")
	return true


func server_pickup(id: int) -> bool:
	var s: Soldier = Net._soldiers.get(id)
	if radio_state != 1 or not is_instance_valid(s) or not s.alive \
			or s.global_position.distance_to(radio_pos) > PICKUP_RANGE + 1.0:
		return false
	_carrier_pos = s.global_position
	_set_radio(2, radio_kind, Vector3.INF, id)
	_log("pickup")
	return true


## Anforderung (Server): nur der Träger, passende Art, Ziel in Reichweite unter freiem Himmel
func server_call(id: int, kind: int, pos: Vector3) -> String:
	var s: Soldier = Net._soldiers.get(id)
	var err := ""
	if not enabled():
		err = "Unterstützung auf diesem Server nicht erlaubt."
	elif radio_state != 2 or carrier != id or radio_kind != kind:
		err = "Kein passendes Funkgerät."
	elif not is_instance_valid(s) or not s.alive:
		err = "Funker tot."
	elif not pos.is_finite() or s.global_position.distance_to(pos) > MAX_RANGE:
		err = "Ziel außer Reichweite."
	elif not sky_open(pos):
		err = "Kein freier Himmel über dem Ziel."
	if err != "":
		_log("denied:" + err)
		return err
	var team: int = s.team
	_set_radio(0, kind, Vector3.INF, 0)
	spawn_t = interval_s()
	var t := Time.get_ticks_msec() / 1000.0 + DELAY_S
	strikes.append({"kind": kind, "pos": pos, "caller": id, "team": team, "t": t, "wave": 0})
	var plane_dir := Vector3(cos(randf() * TAU), 0.0, 0.0)
	plane_dir.z = sqrt(maxf(1.0 - plane_dir.x * plane_dir.x, 0.0)) * (1.0 if randf() < 0.5 else -1.0)
	Net._sup_strike.rpc(kind, pos, id, DELAY_S, plane_dir)
	Net._announce("%s von %s angefordert!" % [NAME[kind], String(Net.players.get(id, {}).get("name", "?"))])
	_log("call")
	return ""


func _strikes_tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for st in strikes.duplicate():
		var kind := int(st["kind"])
		while int(st["wave"]) < int(WAVES[kind]) and now >= float(st["t"]) + float(st["wave"]) * float(WAVE_GAP_S[kind]):
			_server_wave(st)
			st["wave"] = int(st["wave"]) + 1
		if int(st["wave"]) >= int(WAVES[kind]):
			strikes.erase(st)


## Eine Einschlagwelle: sichtbare Einschläge bei allen, Schaden (Server) über den ganzen Wirkungsbereich,
## Deckung über Strahl von oben (Gebäude schützen), Ursache für den Kill-Feed
func _server_wave(st: Dictionary) -> void:
	var kind := int(st["kind"])
	var pos: Vector3 = st["pos"]
	var r: float = RADIUS[kind]
	var pts: Array = []
	for i in (3 if kind == KIND_ART else 4):
		var a := randf() * TAU
		var d := sqrt(randf()) * r * 0.85
		var q := pos + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var hit := _ray(q + Vector3.UP * 40.0, q + Vector3.DOWN * 40.0)
		pts.append(hit["position"] if not hit.is_empty() else q)
	Net._sup_boom.rpc(kind, pts)
	var caller: Soldier = Net._soldiers.get(int(st["caller"]))
	var by: Node = caller if is_instance_valid(caller) else null
	Net.hit_source = CAUSE[kind]
	for n in get_tree().get_nodes_in_group("soldiers"):
		var sol := n as Soldier
		if sol == null or not sol.alive:
			continue
		var tp := sol.global_position + Vector3.UP * 0.5
		var dist := Vector2(tp.x - pos.x, tp.z - pos.z).length()
		if dist > r or absf(tp.y - pos.y) > r:
			continue
		if not _ray(tp + Vector3.UP * 0.3, tp + Vector3.UP * 25.0).is_empty():
			continue     # unter Dach / in Gebäuden geschützt
		var dmg := WeaponDB.explosion_damage(float(WAVE_STRENGTH[kind]), r, dist)
		if dmg > 0.0:
			sol.apply_hit(dmg, &"torso", by, (tp - pos).normalized())
	Net.hit_source = ""
	OrigInteractive.damage_objects(get_tree(), pos, r, float(WAVE_STRENGTH[kind]), by, 0.5)
	_log("wave")


## KI-Funker (Regel supportbots): Ziel = Gegner in 25–150 m ohne eigene Leute im Wirkungsbereich
func _bot_use(s: Soldier, delta: float) -> void:
	_bot_t -= delta
	if _bot_t > 0.0:
		return
	_bot_t = 1.0
	var best: Soldier = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("soldiers"):
		var e := n as Soldier
		if e == null or not e.alive or e == s or (Net.team_mode() and e.team == s.team):
			continue
		var d := e.global_position.distance_to(s.global_position)
		if d < 25.0 or d > 150.0 or d >= best_d or not sky_open(e.global_position):
			continue
		var own := false
		for m in get_tree().get_nodes_in_group("soldiers"):
			var f := m as Soldier
			if f and f.alive and (f == s or (Net.team_mode() and f.team == s.team)) \
					and f.global_position.distance_to(e.global_position) < float(RADIUS[radio_kind]) + 5.0:
				own = true
				break
		if not own:
			best = e
			best_d = d
	if best:
		server_call(carrier, radio_kind, best.global_position)


## Bots holen das liegende Funkgerät (Gruppenführer, Regel supportbots); INF = kein Sonderziel
func bot_goal(b) -> Vector3:
	if radio_state != 1 or not bool(Net.rule("support_bots")) or not enabled():
		return Vector3.INF
	var s: Soldier = b.soldier
	if not is_instance_valid(s):
		return Vector3.INF
	# nur der nächste Führer je Team läuft hin
	for n in get_tree().get_nodes_in_group("soldiers"):
		var o := n as Soldier
		if o and o != s and o.alive and o.has_meta("net_peer") and int(o.get_meta("net_peer")) < 0 and o.team == s.team \
				and o.global_position.distance_to(radio_pos) < s.global_position.distance_to(radio_pos):
			var ob = o.get_node_or_null("EnemyBrain")
			if ob and ob.has_method("is_leader") and ob.is_leader():
				return Vector3.INF
	return radio_pos


func _set_radio(state: int, kind: int, pos: Vector3, who: int) -> void:
	Net._sup_radio.rpc(state, kind, pos, who)


func sync_to(peer: int) -> void:
	Net._sup_radio.rpc_id(peer, radio_state, radio_kind, radio_pos, carrier)


func _log(ev: String) -> void:
	ev_log.append({"ev": ev, "ms": Time.get_ticks_msec(), "state": radio_state, "kind": radio_kind, "carrier": carrier})


# --- Alle Rechner: Zustand und Darstellung ----------------------------------------------------------------

func apply_radio(state: int, kind: int, pos: Vector3, who: int) -> void:
	radio_state = state
	radio_kind = kind
	radio_pos = pos
	carrier = who
	if state == 2 and who == Net.my_id():
		Events.say("%s aufgenommen – Ziffernblock 0: %s" % [SAS.text(1243 + kind, "Funkgerät"), Net.tx(7208, "Unterst. anf.")], 4.0)
	if state != 2 or who != Net.my_id():
		menu_open = false
		_end_targeting()
	_place_radio_node()
	_log("radio%d" % state)


func _place_radio_node() -> void:
	if radio_state == 0:
		if is_instance_valid(_radio_node):
			_radio_node.queue_free()
		_radio_node = null
		return
	if not is_instance_valid(_radio_node) or _radio_node.kind != radio_kind:
		if is_instance_valid(_radio_node):
			_radio_node.queue_free()
		_radio_node = RadioItem.new()
		_radio_node.kind = radio_kind
		_radio_node.host = self
		_radio_node.add_child(radio_model(radio_kind))
	var parent: Node = self
	if radio_state == 2:
		var s: Soldier = Net._soldiers.get(carrier)
		if is_instance_valid(s):
			parent = s
	if _radio_node.get_parent() != parent:
		if _radio_node.get_parent():
			_radio_node.get_parent().remove_child(_radio_node)
		parent.add_child(_radio_node)
	_radio_node.enabled = radio_state == 1
	if radio_state == 1:
		_radio_node.global_position = radio_pos
	else:
		_radio_node.position = Vector3(0.0, 1.0, 0.22)    # auf dem Rücken des Trägers


## Original-Funkgerätmodell (d_radio/d_radiob aus den MP-Kartenordnern), sonst Ersatzkiste
static func radio_model(kind: int) -> Node3D:
	for mdl in [RADIO_MODEL[kind], RADIO_MODEL[0]]:
		for d in RADIO_DIRS:
			var p := "%s/%s/models/%s.glb" % [OrigLevel.cache_root(), d, mdl]
			if FileAccess.file_exists(p):
				var n := OrigLevel.parse_glb(p)
				if n:
					n.set_meta("radio_model", String(mdl))
					return n
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.3, 0.2)
	mi.mesh = bm
	mi.set_meta("radio_model", "")
	return mi


func show_strike(kind: int, pos: Vector3, caller: int, delay: float, plane_dir: Vector3) -> void:
	markers_shown += 1
	var mk := _ring(pos, float(RADIUS[kind]), Color(1.0, 0.15, 0.1))
	_markers.append([mk, Time.get_ticks_msec() + int((delay + float(WAVES[kind]) * float(WAVE_GAP_S[kind]) + 1.0) * 1000.0)])
	_strike_label = "%s in %%d s" % NAME[kind]
	_strike_label_until = Time.get_ticks_msec() + int(delay * 1000.0)
	if kind == KIND_AIR:
		_fly_plane(pos, delay, plane_dir)
	else:
		# Original „Lead in Explosion“ (Kat. 6/8) als Anflug der Granaten kurz vor dem Einschlag
		get_tree().create_timer(maxf(delay - 1.2, 0.0)).timeout.connect(func():
			if is_inside_tree():
				OrigAudio.play_group(OrigAudio.CAT_EXPLOSION, 8, pos))
	_log("strike:%d:%d" % [kind, caller])


func show_boom(kind: int, pts: Array) -> void:
	for i in pts.size():
		var p: Vector3 = pts[i]
		# Explosionen über die gemeinsame API (B-013 modernisiert Effects.explosion); Klang Original 6/2 „Explosion Dirt“
		Effects.explosion(p, 6.0 if kind == KIND_ART else 5.0, [OrigAudio.CAT_EXPLOSION, OrigAudio.EXP_DIRT] if i < 2 else [])
		booms += 1


func _fly_plane(target: Vector3, delay: float, dir: Vector3) -> void:
	var plane := Node3D.new()
	plane.name = "SupportPlane"
	var vis: Node3D = null
	for rel in PLANE_MODELS:
		var p := "%s/%s" % [OrigLevel.cache_root(), rel]
		if FileAccess.file_exists(p):
			vis = OrigLevel.parse_glb(p)
			if vis:
				plane.set_meta("model", rel.get_file())
				break
	if vis == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(16, 2, 12)
		mi.mesh = bm
		vis = mi
	for n in vis.find_children("*", "CollisionObject3D", true, false):
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	plane.add_child(vis)
	add_child(plane)
	planes_shown += 1
	var over := target + Vector3.UP * PLANE_HEIGHT
	var start := over - dir * PLANE_SPEED * delay
	var end := over + dir * PLANE_SPEED * 6.0
	plane.global_position = start
	plane.look_at(over, Vector3.UP)          # Modellnase −Z (wie OrigAirAttack)
	OrigAudio.play_file("motor%d.wav" % randi_range(1, 4), start, 30.0, 800.0, 1.0, plane, true)
	var tw := plane.create_tween()
	tw.tween_property(plane, "global_position", end, delay + 6.0)
	tw.tween_callback(plane.queue_free)


## Kreis am Boden (Decal + flacher Ring + Lichtsäule), für alle sichtbar
func _ring(pos: Vector3, r: float, col: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SupportMarker"
	add_child(root)
	root.global_position = pos
	var dc := Decal.new()
	dc.size = Vector3(r * 2.0, 30.0, r * 2.0)
	dc.texture_albedo = _ring_texture()
	dc.modulate = col
	dc.emission_energy = 2.0
	dc.texture_emission = dc.texture_albedo
	root.add_child(dc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.25
	tm.outer_radius = r
	tm.rings = 48
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position = Vector3.UP * 0.4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.15
	cm.height = 40.0
	beam.mesh = cm
	beam.position = Vector3.UP * 20.0
	var bmat := mat.duplicate() as StandardMaterial3D
	bmat.albedo_color = Color(col, 0.35)
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	return root


static var _ring_tex: Texture2D


static func _ring_texture() -> Texture2D:
	if _ring_tex:
		return _ring_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := 0.0
			if d <= 1.0:
				a = 0.9 if d > 0.93 else (0.12 if fmod(d * 5.0, 1.0) < 0.08 else 0.06)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex


# --- Eigener Spieler: Menü (Original-Untermenü 59) und Zielwahl -------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	_hint = _mk_label(Vector2(20, 560), 16)
	_menu = _mk_label(Vector2(20, 420), 20)
	_count = _mk_label(Vector2(540, 160), 26)
	_count.modulate = Color(1.0, 0.35, 0.25)


func _mk_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.visible = false
	_ui.add_child(l)
	return l


func carrying() -> bool:
	return radio_state == 2 and carrier == Net.my_id() and carrier != 0


## Untermenü wie Original 0x4C02DD: Eintrag nur mit passendem Funkgerät wählbar
func menu_lines() -> PackedStringArray:
	var out: PackedStringArray = [Net.tx(7208, "Unterst. anf.")]
	for k in [KIND_AIR, KIND_ART]:
		out.append("%d. %s%s" % [k + 1, Net.tx(CMD_TEXT[k], CMD_FALLBACK[k]), "" if radio_kind == k else "  (–)"])
	out.append("0. %s" % Net.tx(7299, "Abbrechen"))
	return out


func open_menu() -> bool:
	if not carrying():
		return false
	menu_open = true
	return true


func choose(k: int) -> bool:
	menu_open = false
	if k < 0 or k != radio_kind or not carrying():
		return false
	targeting = k
	return true


## Ziel bestätigen (Linksklick bzw. Tests): Anforderung an den Server
func confirm_target(pos := Vector3.INF) -> void:
	var p: Vector3 = pos if pos.is_finite() else target_preview
	var k := targeting
	_end_targeting()
	if k < 0 or not p.is_finite():
		return
	if multiplayer.is_server():
		var err := server_call(Net.my_id(), k, p)
		if err != "":
			Events.say(err, 3.0)
	else:
		Net._sup_req_call.rpc_id(1, k, p)


func _end_targeting() -> void:
	targeting = -1
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


func request_pickup() -> void:
	if multiplayer.is_server():
		server_pickup(Net.my_id())
	else:
		Net._sup_req_pickup.rpc_id(1)


func _controller():
	return mission.get("controller") if mission else null


func _unhandled_input(event: InputEvent) -> void:
	if not carrying() or targeting >= 0:
		return
	var pc = _controller()
	if pc and (not pc.input_enabled or pc.ui_blocking()):
		return
	if event.is_action_pressed("command_all"):
		menu_open = not menu_open
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if menu_open and event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		var d := -1
		if k >= KEY_0 and k <= KEY_9:
			d = k - KEY_0
		elif k >= KEY_KP_0 and k <= KEY_KP_9:
			d = k - KEY_KP_0
		if d == 0 or k == KEY_ESCAPE:
			menu_open = false
		elif d == 1 or d == 2:
			choose(d - 1)
		else:
			return
		get_viewport().set_input_as_handled()
	elif targeting >= 0:
		if event is InputEventMouseButton and event.pressed:
			var mb := (event as InputEventMouseButton).button_index
			if mb == MOUSE_BUTTON_LEFT:
				confirm_target()
			elif mb == MOUSE_BUTTON_RIGHT:
				_end_targeting()
			else:
				return
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_end_targeting()
			get_viewport().set_input_as_handled()


## Zielpunkt unter dem Fadenkreuz (Kamera-Strahl bis MAX_RANGE)
func aim_point() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3.INF
	var from := cam.global_position
	var to := from - cam.global_basis.z * MAX_RANGE
	var hit := _ray(from, to)
	return hit["position"] if not hit.is_empty() else Vector3.INF


func _update_view() -> void:
	var now := Time.get_ticks_msec()
	for m in _markers.duplicate():
		if now >= int(m[1]):
			if is_instance_valid(m[0]):
				(m[0] as Node).queue_free()
			_markers.erase(m)
	if _ui == null:
		return
	if targeting >= 0:
		var pc = _controller()
		if pc:
			pc._suppress_fire = true          # Bestätigungsklick feuert nicht
		var p := aim_point()
		if p.is_finite():
			target_preview = p
			if not is_instance_valid(_preview):
				_preview = _ring(p, float(RADIUS[targeting]), Color(1.0, 0.85, 0.2))
			_preview.global_position = p
			_preview.visible = true
		elif is_instance_valid(_preview):
			_preview.visible = false
	_hint.visible = carrying()
	if targeting >= 0:
		_hint.text = "%s: Ziel anvisieren – Linksklick bestätigt, Rechtsklick bricht ab" % NAME[targeting]
	else:
		_hint.text = "%s – Ziffernblock 0: %s" % [SAS.text(1243 + radio_kind, "Funkgerät"), Net.tx(7208, "Unterst. anf.")]
	_menu.visible = menu_open
	if menu_open:
		_menu.text = "\n".join(menu_lines())
	var left := _strike_label_until - now
	_count.visible = left > 0
	if left > 0:
		_count.text = _strike_label % ceili(left / 1000.0)


# --- Funkgerät zum Aufheben ------------------------------------------------------------------------------

class RadioItem extends Interactable:
	var host: SupportStrike
	var kind := 1

	func _ready() -> void:
		super._ready()
		persistent_id = "support_radio"
		prompt = "%s: Aufheben" % SAS.text(1243 + kind, "Funkgerät")

	func can_interact(s: Soldier) -> bool:
		return enabled and visible and is_instance_valid(host) and host.radio_state == 1 \
			and s != null and s.has_meta("net_peer") and int(s.get_meta("net_peer")) == Net.my_id()

	## Nur der eigene Spieler fordert die Aufnahme an (Net.used_interactable spiegelt Benutzen auf andere Rechner)
	func interact(s: Soldier) -> void:
		if not is_instance_valid(host) or s == null or not s.has_meta("net_peer") or int(s.get_meta("net_peer")) != Net.my_id():
			return
		super.interact(s)
		host.request_pickup()
