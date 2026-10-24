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
## Pflicht-/Zusatzziele automatisch: Pflicht = im Briefing unter „Einsatz-Aufgaben“ genannt (Texte
## briefing_task_ids); „Alle Mitglieder des Teams müssen überleben“ u. Ä. sind Zusatzziele.
var auto_optional := false
var briefing_task_ids: Array = []
var optional_objectives: Array[int] = []

var orig: OrigLevel
var movie_textures: Array = []      ## [Film, Frame] der aktiven Filmtexturen (meshplayer.bin)
var runtime: LsRuntime
var actor_params := {}
var interactive: OrigInteractive
var _player_names: Array = []    ## Original-Namen der Spielerfiguren (Akteurtyp 10)          ## actors.bin-Parameter + Ausrüstung (tools/fmt_actors_items.py)

## Originalwaffe (items.sav-Name) -> eigene Waffen-ID
const WEAPON_MAP := [["98", "kar98k"], ["MP 40", "mp40"], ["MP40", "mp40"], ["P08", "p08"],
	["Parabellum", "p08"], ["MP 44", "stg44"], ["StG", "stg44"], ["Thompson", "thompson"], ["Sten", "sten"],
	["Bren", "bren"], ["Enfield", "enfield"], ["Garand", "garand"], ["Colt", "colt"]]
## Gesundheitsskala: 1 Lebenspunkt im Spiel = 10 Original-Einheiten („zotti“), dieselbe Skala wie der Waffenschaden
## (items.sav Schaden/10, WeaponDB) und der Mehrspieler (100 = 1000). hd2.exe Human::Damage 0x5A1C90 zieht den Geschoss-
## schaden in zotti direkt von Gesundheit +0xEC ab (actors.bin Feinde 150–500, SAS-Kader ~500–600) [B]. Vorher 0,5:
## Gegner hielten im Einzelspieler das Fünffache aus (K98k-Rumpftreffer 488 tötet im Original einen 300er-Gegner).
const HP_SCALE := 0.1


func _build_world() -> void:
	orig = OrigLevel.new(orig_mission, static_root)
	if not orig.build():
		Events.say("Originaldaten fehlen: tools/convert_mission.py %s ausführen." % orig_mission, 10.0)
		return
	orig.apply_grass_setting()
	Settings.changed.connect(orig.apply_grass_setting)
	# Filmtexturen (meshplayer.bin: Wasserflächen mit GameMovie-Film, src/orig/orig_movie_textures.gd)
	movie_textures = load("res://src/orig/orig_movie_textures.gd").apply(self, orig)
	# Untergrund-Material der Kollisionsflächen (tree.klz) für Schritt-/Einschlagklänge (tools/fmt_klz.py)
	if not OrigAudio.load_surface(orig.mission_dir):
		print("ORIG: surface.bin fehlt (tools/fmt_klz.py %s) – Schritte ohne Untergrund" % orig_mission)
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
	# Spielerfiguren = Akteurtyp 10 (Namen variieren: commando1, Commando_1, …), nach Nummer sortiert
	var players: Array = []
	for a in orig.actors:
		var an := String(a.get("name", "")).to_lower()
		if int(a.get("actor_type", -1)) == 10 or an.begins_with("commando") or an.begins_with("spawnsingle"):
			players.append(a)
	players.sort_custom(func(x, y): return _trailing_number(x.get("name", "")) < _trailing_number(y.get("name", "")))
	players = players.slice(0, 4)
	var count := players.size()
	for i in players.size():
		var t := actor_xform(players[i])
		if i == 0:
			start = t.origin
			# LS3D-Figuren blicken entlang +Z; durch die Z-Spiegelung zeigt das in Godot nach -Z
			yaw = t.basis.get_euler().y
		offsets.append(Basis(Vector3.UP, -yaw) * (t.origin - start))
	if count == 0:
		push_warning("Keine Spielerfigur (Akteurtyp 10) in %s" % orig_mission)
	spawn_roster(start + Vector3.UP * 0.5, yaw, offsets, maxi(count, 1))
	_player_names.clear()
	for i in squad.members.size():
		runtime.register_actor("commando%d" % (i + 1), squad.members[i])
		runtime.register_actor("_PLAYER_ %d" % i, squad.members[i])     # Original-Frame der Spielerfigur (AFRICA2 u. a.)
		if i < players.size():
			runtime.register_actor(String(players[i].get("name", "")), squad.members[i])
			_player_names.append(String(players[i].get("name", "")).to_lower())
		squad.members[i].model.attach_orig(orig.character_instance(COMMANDO_MODEL))
	# 2. Übrige Akteure aus actors.bin
	for a in orig.actors:
		var nm: String = a.get("name", "")
		var model: String = String(a.get("model", ""))
		if nm.to_lower().begins_with("commando") or nm.to_lower().begins_with("spawnsingle") or _player_names.has(nm.to_lower()):
			continue
		var t2 := actor_xform(a)
		var typ := int(a.get("actor_type", -1))
		if typ == 3 and model != "":
			_spawn_orig_human(nm, model, t2)
		elif typ == 30:
			_spawn_orig_dog(nm, model, t2)
		elif typ == 4:
			_spawn_orig_car(nm, model, t2)
		elif typ == 20 and model != "":
			_spawn_orig_submarine(nm, model, t2, PackedByteArray(a.get("params", [])))
		elif typ == 36 and model != "":
			# Angreifendes Flugzeug (AirAttack, AFRICA1/2): fliegt und schießt nach hd2.exe (src/orig/orig_air_attack.gd)
			var aa: Node3D = load("res://src/orig/orig_air_attack.gd").new()
			aa.name = nm.validate_node_name()
			var aparams := {}
			var ij = LsRuntime._read_json(orig.mission_dir + "/interactive.json")
			if typeof(ij) == TYPE_DICTIONARY:
				for e in ij.get("air_attacks", []):
					if String(e.get("name", "")) == nm:
						aparams = e.get("params", {})
			aa.setup(self, runtime, orig.model_instance(model), aparams, HP_SCALE)
			dynamic_root.add_child(aa)
			aa.global_transform = t2
			runtime.register_actor(nm, aa)
		else:
			# Kisten, MG-Stellungen u. a.: statische Originalmodelle;
			# Akteure ohne Modell (z. B. Sprach-Dummies) als leere Frames
			var inst: Node3D = orig.model_instance(model) if model != "" else null
			if inst == null:
				inst = Node3D.new()
			inst.name = nm.validate_node_name()
			dynamic_root.add_child(inst)
			inst.global_transform = t2
			if model != "" and typ in [5, 7, 9, 13, 14, 15, 20, 21, 22, 23, 25, 28]:
				orig._add_collision(inst)     # z. B. Normandie-Kanonen (Typ 25) müssen Treffer erhalten
			runtime.register_actor(nm, inst)
			if typ == 14:
				# Zug (CZECH1 „lokotka“): Wagen folgen der Lok (src/vehicles/orig_train.gd, re_notes_ai §5)
				var tr = load("res://src/vehicles/orig_train.gd").new()
				tr.name = "Train_" + nm.validate_node_name()
				dynamic_root.add_child(tr)
				tr.setup(inst, runtime.find_frame, PackedByteArray(a.get("params", [])))
	# Interaktive Originalakteure (Türen, Leitern, Schalter, Sprengplätze …; interactive.json)
	interactive = OrigInteractive.new()
	interactive.name = "OrigInteractive"
	add_child(interactive)
	interactive.setup(self, runtime, orig)
	print("ORIG: interaktiv ", interactive.stats)
	var n := runtime.start_scripts()
	print("ORIG: %d Skripte gestartet" % n)


## Menschliche Akteure: Deutsche (GE*) als Gegner, Zivilisten (Ci*) wie Sygurd als Verbündete.
## Aussehen: Original-Figurenmodell mit Originalanimationen (orig_cache/characters).
func _spawn_orig_human(nm: String, model: String, t: Transform3D) -> void:
	var yaw := t.basis.get_euler().y
	var s: Soldier
	# Seite laut actors.bin (docs/re_notes_actors_items.md): 2 = Gegner, 3 = neutral/Zivilist, 4 = verbündet.
	# Ohne Parameter: Modellpräfix (ge/it/ja = Achsenmächte bzw. Gegner, sonst verbündet/neutral).
	var side := int(actor_params.get(nm, {}).get("params", {}).get("side", -1))
	var enemy := side == 2 if side >= 0 else (model.begins_with("ge") or model.begins_with("it") or model.begins_with("ja"))
	if not enemy:
		s = spawn_soldier(t.origin + Vector3.UP * 0.3, yaw, Soldier.TEAM_NEUTRAL, nm, ["", "", ""],
			Color(0.32, 0.27, 0.22), "cap", nm)
		var b := EnemyBrain.new()
		b.name = "EnemyBrain"
		s.add_child(b)
		b.setup(s)
		b.runtime = runtime
		b.script_control = true
		# Leiche durchsuchbar (Originalgegenstände, z. B. ALPS1: Ausweise des Lastwagenfahrers)
		var loot := Pickups.Loot.new()
		loot.corpse = s
		loot.enabled = false
		s.add_child(loot)
		s.died.connect(func(_x): loot.enabled = true)
	else:
		var loadout := _orig_loadout(nm)
		s = spawn_enemy(t.origin + Vector3.UP * 0.3, yaw, loadout, nm,
			{"sight": 45.0, "uniform": enemy_uniform, "helmet": "stahlhelm"})
		var eb := s.get_node("EnemyBrain") as EnemyBrain
		eb.runtime = runtime
	_apply_orig_params(s, nm)
	_orig_inventory(s, nm)
	s.name = nm.validate_node_name()
	s.set_meta("orig_model", model)     # Figur der Uniform (Uniform vom Gefangenen: Figurtausch beim Anziehen)
	s.model.attach_orig(orig.character_instance(model))
	runtime.register_actor(nm, s)
	s.died.connect(_on_actor_died.bind(s))


## OnDeath nur einmal (Gefangene haben es schon bei der Gefangennahme erhalten)
func _on_actor_died(_x, s: Soldier) -> void:
	if not s.has_meta("death_notified"):
		s.set_meta("death_notified", true)
		runtime.notify(s, "ONDEATH")


func water_level_at(pos: Vector3) -> float:
	return orig.water_level_at(pos) if orig else NAN


## Weltlage eines actors.bin-Akteurs: die Position ist relativ zum Elternframe (z. B. CZECH5 GE_8 unter „Yelbld143“,
## Straßenobjekte). Auch Sektoren: nur „Primary sector“ liegt im Ursprung, Raumsektoren aus scene.4ds haben eine eigene
## Lage (ALPS2 „sector B01_k_01“ t=(-12.7, 4.9, -19.9), 90° um X; Agentin AL2_agent lokal (-1.68, -3.07, 1.90) mit
## gekippter Drehung → erst mit der Sektorlage aufrecht auf dem Boden y≈3,05; vorher fiel sie aus y=-3 ins Leere).
## Gleiches Muster u. a. NORMANDY N*-Wachen unter m_SECT_help_*, CZECH2 „sector venek“, NORMANDY2 M_banka_01.
func actor_xform(a: Dictionary) -> Transform3D:
	var t := OrigLevel.xform(a)
	var par := String(a.get("parent", ""))
	if par == "" or par.to_lower() == "primary sector":
		return t
	var pn: Node3D = orig.nodes.get(par)
	if pn == null:
		for k in orig.nodes:
			if String(k).to_lower() == par.to_lower():
				pn = orig.nodes[k]
				break
	if pn and pn.is_inside_tree():
		return pn.global_transform * t
	return t


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


## items.dat-Inventar des Akteurs: Tasche/Rucksack (Slots 1/5, ohne Waffen/Munition) als Leicheninhalt,
## Uniform (Slot 4) als Gegenstand beim Anziehen, alles für _IsInInventory des Akteurs
func _orig_inventory(s: Soldier, nm: String) -> void:
	var loot: Array = []
	var all: Array = []
	for it in actor_params.get(nm, {}).get("inventory", []):
		var id := int(it.get("item", -1))
		all.append(id)
		var kind := String(it.get("kind", ""))
		if int(it.get("slot", -1)) == 4:
			s.set_meta("orig_uniform", id)
		elif int(it.get("slot", -1)) in [1, 5] and kind == "equipment" and not id in SAS.MEDKITS:
			loot.append(id)
	s.set_meta("orig_loot", loot)
	s.set_meta("orig_items", all)


## actors.bin-Parameter (docs/re_notes_actors_items.md): Gesundheit, Schießen, Sicht-/Hörweite.
func _apply_orig_params(s: Soldier, nm: String) -> void:
	var p: Dictionary = actor_params.get(nm, {}).get("params", {})
	if p.is_empty():
		return
	# Schwierigkeitsgrad des Profils wie im Original (nur Gegner, Seite 2):
	# 1 leicht ×0,7 · 2 normal ×0,85 · 3 schwer unverändert · 4 sehr schwer Fähigkeiten 100
	var diff := Game.difficulty()
	var k: float = {1: 0.7, 2: 0.85}.get(diff, 1.0)
	var enemy := int(p.get("side", 2)) == 2
	var hp := float(p.get("health", 200)) * (k if enemy else 1.0)
	var shooting := float(p.get("shooting", 64))
	if enemy:
		shooting = 100.0 if diff >= 4 else shooting * k
	s.max_health = maxf(hp * HP_SCALE, 1.0)
	s.health = s.max_health
	var per: Perception = s.get_node_or_null("Perception")
	if per:
		per.sight_range = float(p.get("sight_range", 50))
		per.hear_range = float(p.get("hear_range", 80))
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	if b:
		b.accuracy_skill = clampf(shooting / 100.0 * 0.7, 0.1, 0.9)
		# Moral (actors.bin +0xF8): „sehr schwer“ setzt Gegnerwerte 2–8 auf 100 (0x5A8990) -> nie Panik
		b.morale = 100.0 if enemy and diff >= 4 else float(p.get("morale", 80))
		b.morale_initial = b.morale
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
		d.bite_damage = float(dp.get("bite_damage", 50)) * HP_SCALE     # Biss +0x4A4 in zotti (re_notes_actors_items §3)
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
	# Original-Fahrzeugklänge aus dem Parameterblock des Akteurs (audio.json, tools/extract_mission_audio.py)
	var aj = LsRuntime._read_json(orig.mission_dir + "/audio.json")
	if typeof(aj) == TYPE_DICTIONARY:
		v.sound_files = (aj.get("vehicles", {}) as Dictionary).get(nm, {}).get("files", [])
	var vis: Node3D = orig.model_instance(model)
	if vis:
		vis.rotation.y = PI
		v.custom_visual = vis
	# Fahrphysik-Kennwerte aus dem Car-Parameterblock (Masse, Motor, Getriebe; tools/fmt_vehicles.py)
	v.drive_model = model
	var vj = LsRuntime._read_json(orig.mission_dir + "/vehicles.json")
	if typeof(vj) == TYPE_DICTIONARY:
		var vd: Dictionary = vj.get("vehicles", {})
		for k in vd:
			if String(k).to_lower() == nm.to_lower():
				v.drive_data = vd[k]
				break
	# Bordwaffen aus der Munition im items.dat-Inventar (z. B. Tiger: AMMO Tiger, AMMO Tank MG 34)
	for it in actor_params.get(nm, {}).get("inventory", []):
		if String(it.get("kind", "")) == "ammo":
			v.ammo_items.append(int(it.get("item", -1)))
	# Rohr-Parameter (BARRELnn_00) aus dem Modell, Schadensmodell DM<Modell>.4ds (tools/fmt_vehicle_dm.py) [B]
	v.model_path = orig.mission_dir + "/models/" + model.to_lower() + ".glb"
	v.dm_path = orig.mission_dir + "/models/dm_" + model.to_lower() + ".glb"
	# Strukturpunkte nur noch ohne Schadensmodell (alter Cache) [E]: Panzer 3000, Halbkette 1200, sonst 600
	var ml := model.to_lower()
	if ml.contains("tiger") or ml.contains("sherman") or ml.contains("panzer") or ml.contains("panther") or ml.contains("isu"):
		v.max_health = 3000.0
		v.vehicle_name = {"tiger": "Tiger", "sherman": "Sherman", "panzer": "Panzer III", "panther": "Panther", "isu": "ISU-152"}.get(
			["tiger", "sherman", "panzer", "panther", "isu"].filter(func(k): return ml.contains(k))[0], nm)
	elif ml.contains("hakl"):
		v.max_health = 1200.0
		v.vehicle_name = "Halbkettenfahrzeug"
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
	v.hit.connect(func(_d, _by): runtime.notify(v, "ONHIT"))
	runtime.register_actor(nm, v)


## Kleinst-U-Boot (Akteurtyp 20 „Submarine“, NORWAY/NORMANDY): fahrbar mit zwei Sitzen (src/vehicles/orig_submarine.gd).
## Parameter: Chunk 1 f32 = Höchsthöhe +0xD8 (NORWAY −1,0, NORMANDY −6,8) [B Daten, hd2.exe 0x5E15E0]
func _spawn_orig_submarine(nm: String, model: String, t: Transform3D, raw: PackedByteArray) -> void:
	var v = load("res://src/vehicles/orig_submarine.gd").new()
	v.name = nm.validate_node_name()
	v.persistent_id = nm
	v.vehicle_name = "Kleinst-U-Boot"
	var p := 0
	while p + 6 <= raw.size():
		var id := raw.decode_u16(p)
		var ln := raw.decode_u32(p + 2)
		if ln < 6 or p + ln > raw.size():
			break
		if id == 1 and ln >= 10:
			v.max_height = raw.decode_float(p + 6)
		p += ln
	var vis: Node3D = orig.model_instance(model)
	if vis:
		vis.rotation.y = PI
		v.custom_visual = vis
	v.model_path = orig.mission_dir + "/models/" + model.to_lower() + ".glb"
	dynamic_root.add_child(v)
	v.global_position = t.origin
	v.global_rotation.y = t.basis.get_euler().y + PI
	runtime.register_actor(nm, v)


## Blutbad-Ziel „Töten Sie die Feinde“ (aktiviert nur im Spieltyp Blutbad über *_obj_krvak.scr)
const CARNAGE_OBJECTIVE_TEXT := 6063


func _setup_objectives() -> void:
	var t := func(id: int) -> String: return runtime.text(id) if runtime else "#%d" % id
	# Belegt: Missionsdatenbank GAMEDATA\Gamedata00.gdt (tools/fmt_gamedata.py -> orig_cache/missions_db.json):
	# Ziele in Index-Reihenfolge von SetObjectiveStatus, je Text-ID und Zusatzziel-Flag.
	var db = LsRuntime._read_json(OrigLevel.cache_root() + "/missions_db.json")
	var entry: Dictionary = {}
	if typeof(db) == TYPE_DICTIONARY:
		entry = db.get("missions", {}).get(orig_mission.to_upper(), {})
	if not entry.is_empty():
		var objs: Array = entry.get("objectives", [])
		var carnage_idx := _carnage_objective_indices()
		for i in objs.size():
			var tid := int(objs[i].get("text_id", 0))
			# Text 6063 ist auch ein normales Ziel (AFRICA3 Ziel 2 „Töten Sie die Feinde“, af3a_obj.scr setzt es in jedem
			# Spieltyp): nur der Index aus dem Blutbad-Skript (*_obj_carnage/_krvak.scr) entfällt; ohne solches Skript alle
			if tid == CARNAGE_OBJECTIVE_TEXT and not Game.is_carnage() and (carnage_idx.is_empty() or carnage_idx.has(i + 1)):
				continue     # Spieltyp Kampagne/Einzelgänger: Blutbad-Ziel entfällt (Blutbad: *_obj_krvak.scr aktiviert es)
			var o := add_objective(StringName("o%d" % (i + 1)), t.call(tid), bool(objs[i].get("optional", false)))
			o.state = Objective.State.INACTIVE
			orig_objectives[i + 1] = o.id
		if text_title > 0:
			Events.say(t.call(text_title) + " – " + t.call(text_place_time), 6.0)
		return
	for i in range(1, objective_count + 1):
		var txt: String = t.call(objective_text_base + i)
		if txt == "" or txt.begins_with("#"):
			continue
		var optional := optional_objectives.has(i)
		if auto_optional:
			optional = not _in_briefing(txt, t)
		var o := add_objective(StringName("o%d" % i), txt, optional)
		o.state = Objective.State.INACTIVE
		orig_objectives[i] = o.id
	if text_title > 0:
		Events.say(t.call(text_title) + " – " + t.call(text_place_time), 6.0)


## Zielindizes, die die Blutbad-Skripte des Einsatzes setzen (auch auskommentiert: AFRICA1/AFRICA3 haben das
## Blutbad-Ziel nur noch als Kommentar, der Index steht trotzdem fest)
func _carnage_objective_indices() -> Array:
	var out := []
	if orig == null:
		return out
	var dir := DirAccess.open(orig.mission_dir + "/scripts")
	if dir == null:
		return out
	var re := RegEx.create_from_string("(?i)SetObjectiveStatus\\s*\\(\\s*(\\d+)")
	for f in dir.get_files():
		var lf := String(f).to_lower()
		if not (lf.contains("carnage") or lf.contains("krvak")):
			continue
		var fa := FileAccess.open(orig.mission_dir + "/scripts/" + f, FileAccess.READ)
		if fa == null:
			continue
		for mm in re.search_all(fa.get_as_text()):
			var idx := int(mm.get_string(1))
			if not out.has(idx):
				out.append(idx)
	return out


func _exit_tree() -> void:
	super._exit_tree()
	if orig:
		orig.release()


static func _trailing_number(s: String) -> int:
	var digits := ""
	for i in range(s.length() - 1, -1, -1):
		if s[i] >= "0" and s[i] <= "9":
			digits = s[i] + digits
		elif digits != "":
			break
	return int(digits) if digits != "" else 99


static func _norm(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if c.is_valid_identifier() or c in "äöüß0123456789":
			out += c
	return out


func _in_briefing(objective: String, t: Callable) -> bool:
	var o := _norm(objective)
	if o.contains("allemitgliederdesteams"):
		return false
	var any_task := false
	for tid in briefing_task_ids:
		var task := _norm(String(t.call(tid)))
		if task.length() < 8 or task.begins_with("#"):
			continue
		any_task = true
		var n := mini(22, mini(task.length(), o.length()))
		if o.substr(0, n) == task.substr(0, n) or o.contains(task.substr(0, n)) or task.contains(o.substr(0, n)):
			return true
	return not any_task     # ohne Aufgabenliste: alles Pflicht


## Umgebung aus den Original-Lichtern (scene2 0x4040 via extra.json): gerichtetes Licht = Sonne/Mond,
## Ambient = Umgebungslicht, Nebel-Licht = Nebelfarbe; Hintergrundfarbe = Himmel. Teilmissionen mit
## eigener Abstimmung (a1–a3) überschreiben diese Funktion.
func _configure_environment(e: Environment, sun_light: DirectionalLight3D) -> void:
	var extra = LsRuntime._read_json(OrigLevel.cache_path(orig_mission) + "/extra.json")
	if typeof(extra) != TYPE_DICTIONARY:
		return
	var bg: Array = extra.get("scene", {}).get("background_color", [0.4, 0.45, 0.55])
	var bgc := Color(bg[0], bg[1], bg[2])
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = bgc.darkened(0.25)
	sm.sky_horizon_color = bgc.lightened(0.15)
	sm.ground_horizon_color = bgc.darkened(0.1)
	sm.ground_bottom_color = bgc.darkened(0.6)
	e.fog_light_color = bgc
	var view: float = float(extra.get("scene", {}).get("view_distance", 300.0))
	e.fog_density = clampf(1.5 / maxf(view, 50.0), 0.0015, 0.02)
	var dir_set := false
	for l in extra.get("lights", []):
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		match String(l.get("type", "")):
			"directional":
				if dir_set or l.get("lightmap_only", false):
					continue
				dir_set = true
				sun_light.light_color = col
				sun_light.light_energy = clampf(float(l.get("power", 1.0)), 0.15, 2.0)
				var r: Array = l["world_rot"]
				sun_light.quaternion = Quaternion(r[0], r[1], r[2], r[3]).normalized()
			"ambient":
				e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				e.ambient_light_color = col
				e.ambient_light_energy = clampf(float(l.get("power", 1.0)), 0.2, 1.5)
			"fog":
				e.fog_light_color = col
	var dark := sun_light.light_energy < 0.6 and bgc.get_luminance() < 0.25
	light_factor = 0.5 if dark else 1.0
	e.tonemap_exposure = 1.35 if dark else 1.0


## Missionsende: SaveGameValue-Werte für den nächsten Teil sichern.
func finish(success: bool, reason: String) -> void:
	if finished:
		return
	if runtime:
		# Original-Ereignis OnExit beim Verlassen der Mission (Tagebuch-Dummies: AddDiaryText, CZECH1 Schranke)
		runtime.run_exit_handlers()
	if runtime and success:
		Game.store_orig_game_values(runtime.game_values)
	super.finish(success, reason)
