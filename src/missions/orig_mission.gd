class_name OrigMission
extends Mission
## Gemeinsame Basis aller ORIGINAL-Missionsteile. Alles stammt aus der Original-Installation
## (orig_cache, erzeugt von tools/convert_mission.py <MISSION>):
##   Level         MISSIONS\<M>\scene.4ds + scene2.bin
##   Akteure       MISSIONS\<M>\actors.bin (Menschen, Hunde, Fahrzeuge, MG-Stellungen, Kisten)
##   Wegpunkte     MISSIONS\<M>\check2.bin
##   Missionslogik Original-Skripte (scripts.dta-Zuordnung), ausgeführt von LsRuntime
##   Texte         Text\german (Dialogs.bin, TEXTY.txt) – Ziele 6000+Index, Untertitel
## Teilmissionen setzen orig_mission/Text-IDs und überschreiben _configure_environment.
## Missionsende wie im Original: alle Pflichtziele per SetObjectiveStatus erfüllt
## (kein eigener Endbefehl in den Skripten). SaveGameValue-Werte werden über die
## Kampagne an den nächsten Teil weitergereicht.

const COMMANDO_MODEL := "en01"   ## britischer Kommando-Soldat (Originalmodell)

var orig_mission := ""
var text_title := 0
var text_place_time := 0
var objective_count := 7
var objective_text_base := 6000     ## Ziel-Text = Basis + Index (1A 6000, 1B 6010, 1C 6020)
var optional_objectives: Array[int] = []

var orig: OrigLevel
var runtime: LsRuntime
var actor_params := {}          ## actors.bin-Parameter + Ausrüstung (tools/fmt_actors_items.py)

## Originalwaffe (items.sav-Name) -> eigene Waffen-ID
const WEAPON_MAP := [["98", "kar98k"], ["MP 40", "mp40"], ["MP40", "mp40"], ["P08", "p08"],
	["Parabellum", "p08"], ["MP 44", "stg44"], ["StG", "stg44"], ["Thompson", "thompson"], ["Sten", "sten"],
	["Bren", "bren"], ["Enfield", "enfield"], ["Garand", "garand"], ["Colt", "colt"]]
## Gesundheitsskala: Original-Standardgegner 200 HP = 100 HP im Spiel
const HP_SCALE := 0.5


func _build_world() -> void:
	light_factor = 0.5
	orig = OrigLevel.new(orig_mission, static_root)
	if not orig.build():
		Events.say("Originaldaten fehlen: tools/convert_mission.py %s ausführen." % orig_mission, 10.0)
		return
	print("ORIG: %d Meshes, %d Instanzen, %d Kollisionskörper, %d Dummies, %d Akteure, fehlende Modelle %s" % [
		orig.stats.meshes, orig.stats.instances, orig.stats.colliders, orig.dummies.size(), orig.actors.size(), orig.stats.missing_models])


func _spawn_actors() -> void:
	if orig == null or orig.actors.is_empty():
		spawn_roster(Vector3.ZERO, 0.0, [])
		return
	var ap = LsRuntime._read_json(orig.mission_dir + "/actor_params.json")
	if typeof(ap) == TYPE_DICTIONARY:
		actor_params = ap.get("actors", {})
	runtime = LsRuntime.new()
	add_child(runtime)
	runtime.setup(self, orig)
	runtime.game_values = Game.orig_game_values()
	ls_runtime = runtime
	var ex := OrigExtras.new()
	add_child(ex)
	ex.setup(self, runtime, orig.mission_dir)
	runtime.extras = ex
	print("ORIG: Lichter %d, Spots %d, Klangquellen %d, Spuren %d" % [ex.stats.lights, ex.stats.spots, ex.stats.sounds, ex.stats.tracks])
	# 1. Kommandos an den Original-Startpositionen commando1..4
	var start := Vector3.ZERO
	var yaw := 0.0
	var offsets := []
	var count := 0
	for i in 4:
		if not orig.actor("commando%d" % (i + 1)).is_empty():
			count = i + 1
	for i in maxi(count, 1):
		var a := orig.actor("commando%d" % (i + 1))
		if a.is_empty():
			offsets.append(Vector3(i * 1.5, 0, 0))
			continue
		var t := OrigLevel.xform(a)
		if i == 0:
			start = t.origin
			# LS3D-Figuren blicken entlang +Z; durch die Z-Spiegelung zeigt das in Godot nach -Z
			yaw = t.basis.get_euler().y
		offsets.append(Basis(Vector3.UP, -yaw) * (t.origin - start))
	spawn_roster(start + Vector3.UP * 0.5, yaw, offsets, maxi(count, 1))
	for i in squad.members.size():
		runtime.register_actor("commando%d" % (i + 1), squad.members[i])
		squad.members[i].model.attach_orig(orig.character_instance(COMMANDO_MODEL))
	# 2. Übrige Akteure aus actors.bin
	for a in orig.actors:
		var nm: String = a.get("name", "")
		var model: String = String(a.get("model", ""))
		if nm.to_lower().begins_with("commando"):
			continue
		var t2 := OrigLevel.xform(a)
		var typ := int(a.get("actor_type", -1))
		if typ == 3 and (model.begins_with("ge") or model.begins_with("ci")):
			_spawn_orig_human(nm, model, t2)
		elif typ == 30:
			_spawn_orig_dog(nm, model, t2)
		elif typ == 4:
			_spawn_orig_car(nm, model, t2)
		else:
			# Kisten, MG-Stellungen u. a.: statische Originalmodelle;
			# Akteure ohne Modell (z. B. Sprach-Dummies) als leere Frames
			var inst: Node3D = orig.model_instance(model) if model != "" else null
			if inst == null:
				inst = Node3D.new()
			inst.name = nm.validate_node_name()
			dynamic_root.add_child(inst)
			inst.global_transform = t2
			runtime.register_actor(nm, inst)
	var n := runtime.start_scripts()
	print("ORIG: %d Skripte gestartet" % n)


## Menschliche Akteure: Deutsche (GE*) als Gegner, Zivilisten (Ci*) wie Sygurd als Verbündete.
## Aussehen: Original-Figurenmodell mit Originalanimationen (orig_cache/characters).
func _spawn_orig_human(nm: String, model: String, t: Transform3D) -> void:
	var yaw := t.basis.get_euler().y
	var s: Soldier
	if model.begins_with("ci"):
		s = spawn_soldier(t.origin + Vector3.UP * 0.3, yaw, Soldier.TEAM_ALLIED, nm, ["", "", ""],
			Color(0.32, 0.27, 0.22), "cap", nm)
		var b := EnemyBrain.new()
		b.name = "EnemyBrain"
		s.add_child(b)
		b.setup(s)
		b.runtime = runtime
		b.script_control = true
	else:
		var loadout := _orig_loadout(nm)
		s = spawn_enemy(t.origin + Vector3.UP * 0.3, yaw, loadout, nm,
			{"sight": 45.0, "uniform": enemy_uniform, "helmet": "stahlhelm"})
		var eb := s.get_node("EnemyBrain") as EnemyBrain
		eb.runtime = runtime
	_apply_orig_params(s, nm)
	s.name = nm.validate_node_name()
	s.model.attach_orig(orig.character_instance(model))
	runtime.register_actor(nm, s)
	s.died.connect(func(_x): runtime.notify(s, "ONDEATH"))


## Bewaffnung laut items.dat: Hauptwaffe + Stielhandgranate, falls im Inventar.
func _orig_loadout(nm: String) -> Array:
	var e: Dictionary = actor_params.get(nm, {})
	var primary := ""
	var wname := String(e.get("weapon", "")) if e.get("weapon") != null else ""
	for pair in WEAPON_MAP:
		if wname.contains(pair[0]):
			primary = pair[1]
			break
	if primary == "" and e.is_empty():
		primary = "kar98k"          # ohne Parameterdatei: Standardwaffe der Wehrmacht
	var nade := ""
	for it in e.get("inventory", []):
		var n := String(it.get("name", "")).to_lower()
		if n.contains("granat") or n.contains("m24") or n.contains("stiel"):
			nade = "m24"
	# Pistole als Hauptwaffe: in Slot 1 (Seitenwaffe)
	if primary == "p08":
		return ["", "p08", nade]
	return [primary, "", nade]


## actors.bin-Parameter (docs/re_notes_actors_items.md): Gesundheit, Schießen, Sicht-/Hörweite.
func _apply_orig_params(s: Soldier, nm: String) -> void:
	var p: Dictionary = actor_params.get(nm, {}).get("params", {})
	if p.is_empty():
		return
	s.max_health = clampf(float(p.get("health", 200)) * HP_SCALE, 25.0, 500.0)
	s.health = s.max_health
	var per: Perception = s.get_node_or_null("Perception")
	if per:
		per.sight_range = float(p.get("sight_range", 50))
		per.hear_range = float(p.get("hear_range", 80))
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	if b:
		b.accuracy_skill = clampf(float(p.get("shooting", 64)) / 100.0 * 0.7, 0.1, 0.9)
	s.set_meta("orig_params", p)


## Wachhund (Akteurtyp 30) mit Originalmodell; Verhalten über DOG_*-Befehle des Originalskripts.
func _spawn_orig_dog(nm: String, model: String, t: Transform3D) -> void:
	var d := Dog.new()
	d.name = nm.validate_node_name()
	var dp: Dictionary = actor_params.get(nm, {}).get("params", {})
	if not dp.is_empty():
		d.health = float(dp.get("health", 250)) * HP_SCALE
		d.sight_range = float(dp.get("sight_range", 20))
		d.hear_range = float(dp.get("hear_range", 50))
		d.bite_damage = float(dp.get("bite_damage", 50)) * 0.28
	var vis: Node3D = orig.model_instance(model)
	if vis:
		vis.rotation.y = PI     # LS3D-Modelle blicken nach -Z (nach Z-Spiegelung), Dog läuft entlang +Z
	d.setup(vis)
	d.runtime = runtime
	dynamic_root.add_child(d)
	d.global_position = t.origin + Vector3.UP * 0.2
	d.rotation.y = t.basis.get_euler().y + PI
	runtime.register_actor(nm, d)


## Fahrzeug (Akteurtyp 4) mit Originalmodell: fahrbar, per Skript steuerbar (HUMAN_Drive),
## zerstörbar (Beschuss, Granaten, Sprengladung) -> ONDEATH an sein Originalskript.
func _spawn_orig_car(nm: String, model: String, t: Transform3D) -> void:
	var v := Vehicle.new()
	v.name = nm.validate_node_name()
	v.persistent_id = nm
	v.vehicle_name = "Opel Blitz" if model.contains("opel") else nm
	v.max_health = 600.0
	var vis: Node3D = orig.model_instance(model)
	if vis:
		vis.rotation.y = PI
		v.custom_visual = vis
	v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	v.freeze = true             # steht, bis das Skript losfährt oder ein Spieler einsteigt
	dynamic_root.add_child(v)
	v.global_position = t.origin
	v.global_rotation.y = t.basis.get_euler().y + PI
	var cs := ChargeSite.new()
	cs.target_name = v.vehicle_name
	cs.fuse = 15.0
	v.add_child(cs)
	cs.position = Vector3(1.4, 0, 0)
	cs.destroyed.connect(v.explode)
	v.destroyed_vehicle.connect(func(): runtime.notify(v, "ONDEATH"))
	runtime.register_actor(nm, v)


func _setup_objectives() -> void:
	var t := func(id: int) -> String: return runtime.text(id) if runtime else "#%d" % id
	for i in range(1, objective_count + 1):
		var txt: String = t.call(objective_text_base + i)
		if txt == "" or txt.begins_with("#"):
			continue
		var o := add_objective(StringName("o%d" % i), txt, optional_objectives.has(i))
		o.state = Objective.State.INACTIVE
		orig_objectives[i] = o.id
	if text_title > 0:
		Events.say(t.call(text_title) + " – " + t.call(text_place_time), 6.0)


## Missionsende: SaveGameValue-Werte für den nächsten Teil sichern.
func finish(success: bool, reason: String) -> void:
	if runtime and success:
		Game.store_orig_game_values(runtime.game_values)
	super.finish(success, reason)
