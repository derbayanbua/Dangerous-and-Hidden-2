class_name LsRuntime
extends Node
## Laufzeit für Original-Missionsskripte: verwaltet die Skript-VMs, löst Frame-Namen auf
## (Akteure, Szenenobjekte, KI-Wegpunkte) und bildet die Original-API auf die Engine ab.
## Nicht umgesetzte Befehle werden einmalig protokolliert (unimplemented) und ignoriert.

signal subtitle(text: String, seconds: float)

var mission: Mission
var orig: OrigLevel
var texts := {}                ## Original-Texte (texts_german.json): ID -> Text
var actors := {}               ## Name -> Soldier
var waypoints := {}            ## Name -> Node3D
var checkpoints := LsCheckpoints.new()   ## CheckpointJoin/Separate-Kanten (AP-5, src/orig/ls_checkpoints.gd), im Spielstand
var vms: Array[LsVM] = []
var vm_of := {}                ## Node -> LsVM
var game_values := {}          ## SaveGameValue / _LoadGameValue
var subtitles_on := false
var unimplemented := {}
## B-028/O-006: bekannte Befehle OHNE Wirkung („stumm“): Befehl -> {"count", "owner"} (owner = zuständiger Backlogpunkt,
## z. B. B-035 Darstellung). Rauchtest/Laufzeit melden sie zählend (write_silent_report → test_output/ls_silent.txt).
var stubbed := {}
var calls := {}                ## Statistik: Befehl -> Anzahl
var log_calls := false
var objective_map := {}        ## Original-Index -> Objective-ID
var extras: OrigExtras         ## Lichter, Klangquellen, Spuren, Musik (extra.json)
const LsAnimScript := preload("res://src/orig/ls_anim.gd")
const MissionAreaScript := preload("res://src/orig/mission_area.gd")
var object_models := {}        ## Szenenobjekt (groß) -> Modellname (klein), scene.json
var area: Node                 ## Einsatzgebiet-Grenze (mission_area.gd), null ohne Grenzdreiecke/im Netzspiel
var anim: Node = LsAnimScript.new()   ## Skriptanimationen *.i3d (src/orig/ls_anim.gd), Kind ab _ready
var disguise := OrigDisguise.new()    ## AP-6: Uniformtarnung (Tarnwert je Soldat, 30-Hz-Raster [E])


func setup(m: Mission, level: OrigLevel) -> void:
	mission = m
	orig = level
	name = "LsRuntime"
	process_physics_priority = 10
	var wroot := Node3D.new()
	wroot.name = "Waypoints"
	level.root.add_child(wroot)
	var data = _read_json(level.mission_dir + "/scene.json")
	for wn in data.get("waypoints", {}):
		var p: Array = data["waypoints"][wn]
		var n := Node3D.new()
		n.name = String(wn).validate_node_name()
		wroot.add_child(n)
		n.position = Vector3(p[0], p[1], p[2])
		waypoints[String(wn).to_upper()] = n
	checkpoints.known = func(k: String) -> bool: return waypoints.has(k)
	for o in data.get("objects", []):
		if String(o.get("model", "")) != "":
			object_models[String(o.get("name", "")).to_upper()] = String(o["model"]).to_lower()
	texts = Settings.orig_texts()   # B-007: gewählte Sprachfassung
	Events.soldier_damaged.connect(_on_soldier_damaged)
	# Einsatzgebiet-Grenze (Einzelspieler-Team, hd2.exe 0x45EF00; src/orig/mission_area.gd)
	if not Net.is_online:
		var ar: Node = MissionAreaScript.new()
		if ar.setup(m, self, level.mission_dir):
			add_child(ar)
			area = ar
		else:
			ar.free()


## CSC_NoTeamDamage: Schaden zwischen Kameraden während der Sequenz zurücknehmen
func _on_soldier_damaged(s: Node, amount: float, _zone: StringName, attacker: Node) -> void:
	if no_team_damage and s is Soldier and attacker is Soldier and attacker != s \
			and (attacker as Soldier).team == (s as Soldier).team and (s as Soldier).alive:
		(s as Soldier).heal(amount)


static func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}


## Skriptwert als Text (null/Frames ergeben "", Frames ihren Namen)
static func _str(v) -> String:
	if v == null:
		return ""
	if v is Node:
		return String((v as Node).name)
	return str(v)


func text(id) -> String:
	return String(texts.get(str(int(id)), "#%s" % str(id)))


func register_actor(nm: String, s: Node3D) -> void:
	actors[nm.to_upper()] = s


## Skripte laut Zuordnung (scene.json "scripts") starten.
func start_scripts(extra: Dictionary = {}) -> int:
	var data = _read_json(orig.mission_dir + "/scene.json")
	var mapping: Dictionary = (data.get("scripts", {}) as Dictionary).duplicate()
	mapping.merge(extra, true)      # z. B. Mehrspieler-Skripte (mpscripts.dta) aus mp.json
	var n := 0
	var spawn_vms: Array = []
	var squad_members: Array = mission.squad.members if mission and mission.squad else []
	for obj in mapping:
		var owner := find_frame(obj)
		if owner == null:
			owner = Node3D.new()
			owner.name = String(obj).validate_node_name()
			orig.root.add_child(owner)
			register_actor(obj, owner)   # damit FRM_FindFrame es findet
		elif owner is Soldier and squad_members.has(owner):
			# Spielerstart-Akteur (Typ 10, Commando_N/Spawnsingle0N/Player0N): im Original ein eigener Akteur, der die
			# Spielerfigur erzeugt (hd2.exe 0x41820B: Akteur+0x18 == 0xA → Figur = [[Akteur+0xA8]+0x20]). Sein Skript läuft
			# getrennt von der Figur weiter (TUTORIAL Player_2.scr: ScriptAssign auf die Figur, danach SendSignal).
			var sp := Node3D.new()
			sp.name = ("SPAWN_" + String(obj)).validate_node_name()
			sp.set_meta("spawn_of", owner)
			owner.add_child(sp)
			owner = sp
		var nvm := attach_script(owner, String(mapping[obj]).to_lower())
		if nvm:
			n += 1
			if owner.has_meta("spawn_of"):
				spawn_vms.append(nvm)
	_setup_hit_events()
	# „Geburt“ der Spielerfigur: OnUse des Startakteurs (TUTORIAL Player_2.scr OnUse: Printf("Player 2 born"); Skripte
	# player1assign.scr u. a. bestehen nur aus OnUse(){ ScriptAssign(player, …) }) [P: Auslösezeitpunkt per Skripttext]
	for v in spawn_vms:
		(v as LsVM).fire("ONUSE")
	return n


## Skript an ein Objekt hängen (ersetzt ein vorhandenes; Original: ScriptAssign).
func attach_script(owner: Node3D, file: String) -> LsVM:
	var sdir := orig.mission_dir + "/scripts"
	var f := FileAccess.open(sdir + "/" + file, FileAccess.READ)
	if f == null:
		push_warning("Skript nicht gefunden: " + file)
		return null
	var src := f.get_buffer(f.get_length()).get_string_from_ascii()
	var c := LsCompiler.compile(src, file, sdir)
	if not c.ok():
		push_warning("Skriptfehler %s: %s" % [file, c.errors[0]])
	var old: LsVM = vm_of.get(owner)
	if old:
		old.ended = true
		old.stack.clear()
		vms.erase(old)
	var vm := LsVM.new(c, owner, self, file)
	vms.append(vm)
	vm_of[owner] = vm
	return vm


func _physics_process(delta: float) -> void:
	for vm in vms:
		vm.tick(delta)
	for r in _rotations.duplicate():
		if not is_instance_valid(r["node"]) or r["left"] <= 0.0:
			_rotations.erase(r)
			continue
		var step: float = minf(absf(r["speed"]) * delta, r["left"])
		r["left"] -= step
		(r["node"] as Node3D).rotate_object_local(r["axis"], deg_to_rad(step * signf(r["speed"])))
	_display_tick(delta)
	# AP-6: Uniformtarnung nur im Einzelspieler (0x59FFD0: DAT_00982100 & 7 == 7) [B]
	if not Net.is_online and mission and mission.get("squad") and mission.squad:
		disguise.tick(delta, mission.squad.members, get_tree())
	for at in _air_targets.keys():
		if not is_instance_valid(at):
			_air_targets.erase(at)
			continue
		_air_targets[at] -= delta
		if _air_targets[at] <= 0.0:
			_air_targets[at] = randf_range(3.0, 7.0)
			var hit := (at as Node3D).global_position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
			_explosion(_ground(hit) + Vector3.UP * 0.5, 6.0, 180.0)
	if _timer_left >= 0.0 and _timer_label:
		_timer_left = maxf(_timer_left - delta, 0.0)
		_timer_label.text = "%d:%02d" % [int(_timer_left) / 60, int(_timer_left) % 60]
	_formation_t -= delta
	if _formation_t <= 0.0:
		_formation_t = 0.5
		_update_formations()
	_thunder_tick(delta)


var formations := {}            ## Anführer -> {members, type, scale} (FORMATION_*)
var _rotations: Array = []      ## FRM_Rotate*: {node, axis, left (Grad), speed (Grad/s)}
var _indexed_particles := {}    ## FRM_CreateIndexedParticle: Index -> Partikelknoten
var _particle_index := 0
var _air_targets := {}          ## AirAttack_SetTarget: Frame -> Zeit bis zum nächsten Einschlag
var _timer_label: Label
var _timer_left := -1.0
var _formation_t := 0.0


## Formationsmitglieder halten ihren Platz relativ zum Anführer (nur ohne Kampf/Alarm).
## Platzmuster nach Formationstyp; Abstände = FORMATION_SetScale/1000 m (Annahme).
func _update_formations() -> void:
	for lead in formations.keys():
		if not is_instance_valid(lead) or (lead is Soldier and not (lead as Soldier).alive):
			formations.erase(lead)
			continue
		var f: Dictionary = formations[lead]
		var sc: float = f["scale"]
		var i := 0
		for mem in f["members"]:
			if not is_instance_valid(mem) or not (mem is Soldier) or not (mem as Soldier).alive:
				continue
			var b: EnemyBrain = mem.get_node_or_null("EnemyBrain")
			if b == null or b.suspended or b.state == EnemyBrain.State.COMBAT or b.state == EnemyBrain.State.SEARCH:
				continue
			var side := -1.0 if i % 2 == 0 else 1.0
			var row := float(i / 2 + 1)
			var off := Vector3.ZERO
			match String(f["type"]):
				"line":
					off = Vector3(side * row * sc, 0, 0)
				"column":
					off = Vector3(0, 0, (i + 1) * sc)
				"quad2x3", "quad3x2":
					off = Vector3(side * sc * 0.5, 0, row * sc)
				"arrowsharp":
					off = Vector3(side * row * sc * 0.6, 0, row * sc)
				"arrowinvert":
					off = Vector3(side * row * sc * 0.6, 0, -row * sc)
			var slot: Vector3 = (lead as Node3D).global_transform * off
			if (mem as Node3D).global_position.distance_to(slot) > 1.5:
				b.script_move(slot)
			i += 1


func vm_for(n: Node) -> LsVM:
	return vm_of.get(n)


## Frame-Name -> Node3D (Akteure, Szenenobjekte/Frames, Wegpunkte)
func find_frame(nm: String) -> Node3D:
	var u := nm.to_upper()
	if actors.has(u):
		return actors[u]
	if orig.nodes.has(nm):
		return orig.nodes[nm]
	for k in orig.nodes:
		if String(k).to_upper() == u:
			return orig.nodes[k]
	if waypoints.has(u):
		return waypoints[u]
	# "Modell.Unterframe" (z. B. "Auti_BAD.WHL01"): Kindknoten im Originalmodell des Akteurs
	var dot := nm.find(".")
	if dot > 0:
		var par := find_frame(nm.substr(0, dot))
		if par:
			var sub := nm.substr(dot + 1).to_upper()
			for c in par.find_children("*", "Node3D", true, false):
				if String(c.name).to_upper() == sub:
					return c
	return null


func _frame_arg(vm: LsVM, e) -> Node3D:
	var v = vm.value(e)
	if v is Node3D:
		return v
	if v is String:
		return find_frame(v)
	return null


func _pos(n: Node3D) -> Vector3:
	return n.global_position if is_instance_valid(n) else Vector3.INF


func _players() -> Array:
	return mission.squad.alive_members()


func _soldier(vm: LsVM) -> Soldier:
	if is_instance_valid(vm.me) and vm.me.has_meta("spawn_of"):
		return vm.me.get_meta("spawn_of") as Soldier     # Spielerstart-Akteur → seine Figur (HUMAN_CreateItemInStore u. a.)
	return vm.me as Soldier


func _brain(vm: LsVM) -> EnemyBrain:
	var s := _soldier(vm)
	return s.get_node_or_null("EnemyBrain") if s else null


# --- API ----------------------------------------------------------------------------

func call_api(vm: LsVM, fname: String, args: Array):
	calls[fname] = calls.get(fname, 0) + 1
	if log_calls:
		print("LS %s: %s" % [vm.name, fname])
	match fname:
		# --- Frames / Objekte ---
		"FRM_FINDFRAME":
			if args.size() >= 2 and args[0][0] == "var":
				vm.vars[args[0][1]] = find_frame(_str(vm.value(args[1])))
				if Game.cli.has("debug_state") and vm.vars[args[0][1]] == null:
					print("DBGFIND ", vm.name, " sucht '", _str(vm.value(args[1])), "' arg=", args[1])
			return null
		"FRM_GETMYFRAME":
			if args.size() >= 1 and args[0][0] == "var":
				vm.vars[args[0][1]] = vm.me
			return null
		"FRM_FINDCHILDFRAME":
			if args.size() >= 3 and args[0][0] == "var":
				var par := _frame_arg(vm, args[1])
				var cn := _str(vm.value(args[2]))
				vm.vars[args[0][1]] = par.find_child(cn.validate_node_name(), true, false) if par else find_frame(cn)
			return null
		"FRM_SETON":
			var fr := _frame_arg(vm, args[0])
			if fr:
				var on := LsVM._truthy(vm.value(args[1]))
				fr.visible = on
				if fr is AudioStreamPlayer3D:
					var ap := fr as AudioStreamPlayer3D
					if on and not ap.playing:
						ap.play()
					elif not on:
						ap.stop()
				if fr is Soldier and not on:
					fr.set_physics_process(false)
				elif fr is Soldier:
					fr.set_physics_process(true)
			return null
		"FRM_TELEPORTNEARFRAMEBACK":
			# (Frame): macht ein früheres FRM_TeleportNearFrame(Frame, …) rückgängig – alle Originalaufrufe haben genau ein
			# Argument, stets ein zuvor versetztes Objekt (ARCTIC1 R_Arc1A_Com1..4: padak; AFRICA1/3: duplicated_player,
			# zbran) [P aus Skripten]. Früher als „eigenen Akteur zum Frame“ gedeutet → ARCTIC1: der Spieler (Skriptbesitzer)
			# landete nach dem Intro beim Fallschirm im Flugzeug (y ≈ 391).
			var back := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if back and back.has_meta("tnf_back"):
				back.global_transform = back.get_meta("tnf_back")
				back.remove_meta("tnf_back")
			return null
		"FRM_TELEPORTNEARFRAME":
			# zwei Argumente (wer, wohin) oder eines (eigenen Akteur neben den Frame setzen)
			var who := _frame_arg(vm, args[0]) if args.size() > 1 else vm.me as Node3D
			var to := _frame_arg(vm, args[1] if args.size() > 1 else args[0])
			if who and to:
				if not who.has_meta("tnf_back"):
					who.set_meta("tnf_back", who.global_transform)
				who.global_position = to.global_position
				who.set_meta("tnf_to", to)      # B-035: Hand-Frame für FRM_SetTarget
			return null
		"SCRIPTASSIGN":
			var sf2 := _frame_arg(vm, args[0])
			var sn := _str(vm.value(args[1])).to_lower()
			if not sn.ends_with(".scr"):
				sn += ".scr"
			if sf2 == null and is_instance_valid(vm.me):
				# Leerer Frame (uninitialisiertes „Frame player;“): hd2.exe 0x41820B – im Skript eines Spielerstart-Akteurs
				# (Typ 10) gilt die von ihm erzeugte Spielerfigur [B]; im Skript der Figur selbst die Figur [P]
				# (CZECH4 Commando_1 → R_Cz4_Com1 → ScriptAssign(player, "CUTplayer1_cz4a"))
				if vm.me.has_meta("spawn_of"):
					sf2 = vm.me.get_meta("spawn_of")
				elif vm.me is Soldier and mission.squad and mission.squad.members.has(vm.me):
					sf2 = vm.me
			if sf2 and sn != ".scr":
				var avm := attach_script(sf2, sn)
				# Die erzeugte Figur erhält ihr „Geburts“-OnUse nach der Zuweisung durch den Startakteur (einmalig; nötig für
				# die Kette Startakteur → R_Cz4_Com1 (nur OnUse) → CUTplayer1_cz4a) [P]
				if avm and vm.me.has_meta("spawn_of") and sf2 == vm.me.get_meta("spawn_of") and not sf2.has_meta("born_use"):
					sf2.set_meta("born_use", true)
					avm.fire("ONUSE")
			elif sf2 and sn == ".scr":
				var ovm: LsVM = vm_of.get(sf2)
				if ovm:
					# ScriptAssign(frame, ""): Skript entfernen (TUTORIAL Player_2.scr vor erneuter Zuweisung)
					ovm.ended = true
					ovm.stack.clear()
					vms.erase(ovm)
					vm_of.erase(sf2)
			return null
		"SENDSIGNAL":
			var target := _frame_arg(vm, args[0])
			var n := int(vm.value(args[1]))
			var tvm: LsVM = vm_of.get(target)
			if tvm:
				tvm.signal_received(n)
			return null
		# --- Bereiche / Abfragen ---
		"_PLAYERINRANGE":
			# B-036b [B] hd2.exe 0x41E3F0 Fall 0 (0x41F0A4/0x41F1D8): Einzelspieler zählt ALLE lebenden Soldaten der
			# Spielerliste (Spiel+0x1C, dieselbe Liste wie _AllPlayersDead/_GetDistToActivePlayer = Trupp), nicht nur den
			# aktiven. Rückgabe = ANZAHL mit d² < r² (r ganzzahlig, Literale sind beim Kompilieren __ftol), nicht 0/1 –
			# Skripte wie czech1 cuttrebissky „_PlayerInRange(7)>1“ bzw. „==1“ (alps2/czech3) hängen davon ab.
			var r := float(int(vm.value(args[0])))
			var cnt := 0
			for p in _players():
				if p.global_position.distance_squared_to(_pos(vm.me)) < r * r:
					cnt += 1
			return cnt
		"_ALLPLAYERSINRANGE":
			var r2 := float(vm.value(args[0]))
			var ps := _players()
			if ps.is_empty():
				return 0
			for p in ps:
				if p.global_position.distance_to(_pos(vm.me)) > r2:
					return 0
			return 1
		"_FRAMEINRANGE":
			var other := _frame_arg(vm, args[0])
			return _pos(vm.me).distance_to(_pos(other)) if other else 99999.0
		"_GETDISTTOACTIVEPLAYER":
			var act: Soldier = mission.controller.active
			return _pos(vm.me).distance_to(act.global_position) if act else 99999.0
		"_ISTEAMMEMBERDEAD":
			for m in mission.squad.members:
				if not m.alive:
					return 1
			return 0
		"_GETNUMMEMBERSOFCLIENTTEAM":
			return mission.squad.alive_members().size()
		"_SPGETGAMETYPE":
			return Game.sp_game_type()   # 1 Kampagne, 2 Einzelgänger, 3 Blutbad (+4 Einzelmission), Game.gd
		"_RANDOMINT":
			return randi_range(0, maxi(int(vm.value(args[0])) - 1, 0))
		"_LOADGAMEVALUE":
			return game_values.get(int(vm.value(args[0])), 0)
		"SAVEGAMEVALUE":
			game_values[int(vm.value(args[0]))] = vm.value(args[1])
			return null
		"_GETALARMTYPE":
			# Art des Alarms, der OnAlarm ausgelöst hat (1 nahe Schüsse, 2 Schüsse, 4 Schritte, 8 Geräusche, 16 Explosion,
			# 32 gesehen, 64 verwundet, 128 Todesschrei, 256 Eigenbeschuss, 512 Leiche – EnemyBrain.AL_*)
			var ba := _brain(vm)
			return ba.last_alarm_type if ba and ba.last_alarm_type > 0 else EnemyBrain.AL_SEE
		"_ACTOR_GETSTATE":
			# Original: Menschen 1 = lebt, 0 = tot; andere Objekte: per SetActorState gesetzter Zustand
			var af := _frame_arg(vm, args[0])
			if Game.cli.has("debug_state"):
				print("DBGSTATE ", vm.name, " arg=", args[0], " frame=", af.name if af else "null", " type=", af.get_class() if af else "")
			if af is Soldier:
				# Gefangene gelten als ausgeschaltet (ARCTIC1 r_arc1a_obj1_sender.scr prüft deshalb alle 7 s nach:
				# „to je kvuli zajimani“ – wegen der Gefangennahme)
				return 1 if (af as Soldier).alive and not af.has_meta("captured") else 0
			# B-032: zerstörtes Fahrzeug = 0 (Skriptbeleg AFRICA1 af1_dead_vehicles „opeldead (!_ACTOR_GetState(opel))“,
			# ALPS1 obj_hakl zählt die Halbkette „hakl“ erst bei 0 als ausgeschaltet – vorher blieb Zusatzziel 8 hängen)
			if af is Vehicle and (af as Vehicle).wrecked:
				return 0
			return int(af.get_meta("actor_state", 1)) if af else 0
		"SETACTORSTATE":
			var sf3 := _frame_arg(vm, args[0])
			if sf3 and args.size() > 1:
				var ctl = sf3.get_meta("orig_ctl") if sf3.has_meta("orig_ctl") else null
				if ctl and is_instance_valid(ctl) and ctl.has_method("set_actor_state"):
					ctl.set_actor_state(int(vm.value(args[1])))      # Tür, Schalter, Sprengplatz … (OrigInteractive)
				else:
					sf3.set_meta("actor_state", int(vm.value(args[1])))
			return null
		"_SEEENEMY":
			var b := _brain(vm)
			return 1 if b and b.perception.best_target() else 0
		# --- Missionsziele / Texte ---
		"SETOBJECTIVESTATUS":
			mission.set_orig_objective(int(vm.value(args[0])), int(vm.value(args[1])))
			return null
		"SUBTITLES_SETON":
			subtitles_on = LsVM._truthy(vm.value(args[0]))
			return null
		"SUBTITLES_SETTEXT":
			var t := text(vm.value(args[0]))
			subtitle.emit(t, 4.0)
			Events.say(t, 4.0)
			return null
		"HINT_ADD":
			Events.say("Hinweis: " + text(vm.value(args[0])), 6.0)
			return null
		"ADDDIARYTEXT":
			# Tagebuch der Nachbesprechung (Ausgabe: Game.add_diary_text, debrief.gd)
			if args.size() > 0:
				Game.add_diary_text(int(vm.value(args[0])))
			return null
		"PLAYAVI":
			# Film (Gamemovie\*.bik → orig_cache/movies/*.ogv), Spiel pausiert währenddessen
			if args.size() > 0:
				Game.play_movie(String(vm.value(args[0])))
			return null
		"PRINTF", "PRINTFNUMBER":
			# Original-Debugausgabe der Skripte; nur mit --ls_print (Diagnose der Erfüllbarkeitsläufe)
			if Game.cli.has("ls_print") and args.size() > 0:
				print("LS %s: %s %s" % [vm.name, str(vm.value(args[0])), str(vm.value(args[1])) if args.size() > 1 else ""])
			return null
		"HINT_CLEARALL":
			# Original: HUD-Hinweise löschen [P, Handler nicht dekodiert]. Der Nachbau hat kein Skript-Hinweissystem
			# (HINT_* sonst unbenutzt) → leert nur Hinweise, falls das HUD sie anbietet [E]
			var hh = mission.get("hud") if mission else null
			if hh is Object and hh.has_method("clear_hints"):
				hh.clear_hints()
			return null
		"CHECKPOINTJOIN", "CHECKPOINTSEPARATE":
			# AP-5 [B] 0x418009/0x417F17: Kante im Wegpunktnetz anlegen/entfernen (LsCheckpoints)
			if args.size() >= 2:
				var ca := _str(vm.value(args[0]))
				var cb := _str(vm.value(args[1]))
				if fname == "CHECKPOINTJOIN":
					checkpoints.join(ca, cb)
				else:
					checkpoints.separate(ca, cb)
			return null
		"SETWHENEVERTIME":
			# AP-5 [B] 0x419980: Periode der Whenever (Name, ms); kein Reset der verstrichenen Zeit
			if args.size() >= 2 and args[0] is Array and args[0][0] == "var":
				vm.whenever_interval_ms[String(args[0][1])] = int(vm.value(args[1]))
			return null
		"SETUPTACTICALMODE":
			# Taktikkarte sperren/freigeben [P aus Namen/Parameter; alle 14 Aufrufe: False/0] – TacticalMap.locked
			var tmap = mission.get("tactical_map") if mission else null
			if tmap is Object and "locked" in tmap:
				tmap.locked = not (LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true)
				if tmap.locked and bool(tmap.get("is_open")) and tmap.has_method("close"):
					tmap.close()
			return null
		"SETALARMTYPE":
			# (Maske, an/aus): Alarmarten, die OnAlarm auslösen (SetAlarmType(1023, true) = alle)
			var b2 := _brain(vm)
			if b2 and args.size() > 0:
				var mask := int(vm.value(args[0]))
				if args.size() < 2 or LsVM._truthy(vm.value(args[1])):
					b2.alarm_mask |= mask
				else:
					b2.alarm_mask &= ~mask
			return null
		"DISABLEALARMS":
			var b2b := _brain(vm)
			if b2b:
				b2b.script_alarm_enabled = not (LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true)
			return null
		"HUMAN_SETEVENTS":
			var be := _brain(vm)
			if be:
				be.events_enabled = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			return null
		"HUMAN_MOVETOALARM":
			# zum Ort des Alarmreizes laufen (Gangart wie gesetzt, meist HUMAN_SetMODE_Run)
			var bm := _brain(vm)
			if bm:
				var ap: Vector3 = bm.alarm_pos if bm.alarm_pos.is_finite() else bm.investigate_pos
				if ap.is_finite() and ap != Vector3.ZERO:
					bm.script_move(ap)
					return {"wait_until": bm.script_move_done, "timeout": 60.0}
			return null
		"HUMAN_ILLFIRE", "HUMAN_ATTACK":
			# AP-6: gemeinsamer Handler 0x422776 [B], IllFire-Flag = (Opcode 48); Kampfauftrag mit Rückmeldung an den pc
			var bf := _brain(vm)
			var ft := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if bf and ft:
				var ms := float(vm.value(args[1])) if args.size() > 1 else 1000.0
				bf.script_attack_order(ft, ms / 1000.0, fname == "HUMAN_ILLFIRE")
				return {"wait_until": bf.attack_done, "timeout": maxf(60.0, ms / 1000.0 + 5.0)}
			return null
		"HUMAN_WEAPONUP":
			var sw := _soldier(vm)
			if sw:
				sw.aiming = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			return null
		"HUMAN_RELOAD":
			var sr := _soldier(vm)
			if sr:
				sr.reload()
				var rw := sr.current_weapon()
				if rw and rw.is_reloading():
					return {"wait": rw.reload_left}
			return null
		"HUMAN_INVESTIGATE":
			# zum Frame gehen und sich umsehen (Original: Untersuchen, z. B. AFRICA5 Archiv)
			var bi := _brain(vm)
			var fi := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if bi and fi:
				bi.script_move(fi.global_position)
				var t_end := [-1.0]
				return {"wait_until": _investigate_done.bind(bi, t_end), "timeout": 45.0}
			return null
		"HUMAN_MOVEFROMFRAME":
			# (Frame, Abstand m): vom Frame (z. B. Fahrzeug) wegtreten
			var bmf := _brain(vm)
			var ff := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if bmf and ff:
				var dist := float(vm.value(args[1])) if args.size() > 1 else 5.0
				var away := bmf.soldier.global_position - ff.global_position
				away.y = 0.0
				if away.length() < 0.1:
					away = Vector3(1, 0, 0)
				var cur := away.length()
				if cur < dist:
					bmf.script_move(bmf.soldier.global_position + away.normalized() * (dist - cur + 0.5))
					return {"wait_until": bmf.script_move_done, "timeout": 20.0}
			return null
		"ADDHUMANHEALTH":
			# (Mensch, Menge in Originaleinheiten; Gesundheit im Spiel = Original × 0,5)
			var hh := _frame_arg(vm, args[0]) as Soldier if args.size() > 0 else null
			if hh and hh.alive and args.size() > 1:
				var amt := float(vm.value(args[1])) * OrigMission.HP_SCALE
				if amt >= 0.0:
					hh.heal(amt)
				else:
					hh.apply_hit(-amt, &"torso", null, Vector3.ZERO)
			return null
		"_GETHUMANSTOREID":
			# Kadernummer des Soldaten (HumanStore; Speicherplätze 200–203 für den nächsten Teil)
			var hs2 := _frame_arg(vm, args[0]) as Soldier if args.size() > 0 else null
			if hs2 == null:
				return -1
			var pid := String(hs2.persistent_id)
			return int(pid.substr(4)) if pid.begins_with("sas_") and pid.substr(4).is_valid_int() else \
				(mission.squad.members.find(hs2) if mission.squad.members.has(hs2) else -1)
		"CSC_GETPLAYERNUM", "CSC_GETPLAYERNUMNONPC":
			# (n, var): n-ter lebender Spielersoldat (ohne NPC-Begleiter); sonst leerer Frame
			if args.size() >= 2 and args[1][0] == "var":
				var n_p := int(vm.value(args[0]))
				var alive_p := _players()
				vm.vars[args[1][1]] = alive_p[n_p] if n_p >= 0 and n_p < alive_p.size() else null
			return null
		"_GETOBJECTIVESTATUS":
			# (a, b, c, Ziel): Zustand eines Ziels der laufenden Mission – 1 erfüllt, 3 gescheitert, 0 offen
			# (Bedeutung der ersten drei Argumente nicht belegt; AFRICA1 af1_obj03_detector fragt Ziele 1 und 2 ab)
			var oi2 := int(vm.value(args[args.size() - 1])) if args.size() > 0 else 0
			var o2: Objective = mission.objective(mission.orig_objectives.get(oi2, &""))
			if o2 == null:
				return 0
			match o2.state:
				Objective.State.DONE:
					return 1
				Objective.State.FAILED:
					return 3
			return 0
		"_CAMERAINRANGE":
			# Abstand der aktiven Kamera zum Skriptobjekt (ARCTIC2/3: Verstärkung erscheint nur außer Sicht)
			var cam := get_viewport().get_camera_3d()
			return cam.global_position.distance_to(_pos(vm.me)) if cam and vm.me is Node3D else 99999.0
		"CSC_DUPLICATEHUMAN":
			# (Quelle, var, Name): Darsteller für eine Zwischensequenz – Kopie des Originalmodells der Figur
			if args.size() >= 2 and args[1][0] == "var":
				vm.vars[args[1][1]] = _duplicate_human(_frame_arg(vm, args[0]), _str(vm.value(args[2])) if args.size() > 2 else "")
			return null
		"CSC_RELEASEHUMAN":
			var dh := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if dh and dh.has_meta("csc_duplicate"):
				actors.erase(String(dh.get_meta("csc_duplicate")).to_upper())
				dh.queue_free()
			return null
		"CSC_FREEHANDS", "CSC_FREEBACKPACK":
			# Darsteller ohne Waffe in der Hand bzw. ohne Rucksack (nur Darstellung)
			var fh := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if fh:
				for c in fh.find_children("*", "Node3D", true, false):
					var cn := String(c.name).to_lower()
					if (fname == "CSC_FREEHANDS" and cn.begins_with("w_")) or (fname == "CSC_FREEBACKPACK" and cn.begins_with("b_")):
						(c as Node3D).visible = false
			return null
		"CSC_FRAMESETSHADOW":
			var sh := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if sh:
				var on_sh := LsVM._truthy(vm.value(args[1])) if args.size() > 1 else true
				for c in sh.find_children("*", "GeometryInstance3D", true, false):
					(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on_sh \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return null
		"CSC_NOTEAMDAMAGE":
			# Zwischensequenz: kein Schaden zwischen Kameraden
			no_team_damage = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			return null
		"CSC_SETCAMERAFOV":
			if args.size() > 0:
				_cut_cam.fov = clampf(float(vm.value(args[0])), 5.0, 150.0)
			return null
		"CSC_SETTIMER":
			# (Verzögerung ms, Dauer ms): Countdown-Anzeige der Zwischensequenz (ARCTIC2) – wie SetInterfaceTimer
			if args.size() > 1:
				var dly := float(vm.value(args[0])) / 1000.0
				var dur := float(vm.value(args[1])) / 1000.0
				get_tree().create_timer(dly, false).timeout.connect(func(): _set_interface_timer(dur))
			return null
		"CSC_SETUPFAKECUTSCENE":
			# B-049/AP-49a: „Fake-Cutscene“ (NORMANDY2 r_n2_camerasend.scr): Welt, KI und Skripte laufen weiter, das
			# Skript übernimmt aber die Kamera (FRM_SetActiveCamera auf Kamera1/2 mit #CAMNO2_*), Steuerung gesperrt,
			# HUD aus, kein Überspringen [P]. false beendet und gibt die Spielkamera zurück.
			set_fake_cutscene(LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true)
			return null
		"CSC_FADEOUTTOCOLOR", "CSC_FADEINFROMCOLOR":
			# (ms, r, g, b): Blende zu/aus einer Farbe (AFRICA4 Sandsturm-Blitz: weiß)
			var ms2 := float(vm.value(args[0])) if args.size() > 0 else 500.0
			if args.size() >= 4:
				_fade.color = Color(float(vm.value(args[1])) / 255.0, float(vm.value(args[2])) / 255.0,
					float(vm.value(args[3])) / 255.0, _fade.color.a)
			_fade_to(1.0 if fname == "CSC_FADEOUTTOCOLOR" else 0.0, maxf(ms2, 1.0) / 1000.0)
			return null
		"THUNDERSTORM_SETON":
			# (an/aus, Lichtframe): Gewitter – Blitze schalten das Licht kurz ein (TUTORIAL)
			var lf := _frame_arg(vm, args[1]) if args.size() > 1 else null
			_thunder_light = lf
			_thunder_on = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else false
			_thunder_t = randf_range(2.0, 6.0)
			if lf and not _thunder_on:
				lf.visible = false
			return null
		"ADDPAUSESOUND":
			# Klangquelle der Kulisse für Pausen-/Ruhephasen (BURMA2 Gras): Original-Datei als leise Schleife
			if args.size() > 0:
				var pf := _str(vm.value(args[0]))
				var at2: Vector3 = (vm.me as Node3D).global_position if vm.me is Node3D and (vm.me as Node3D).is_inside_tree() else Vector3.ZERO
				OrigAudio.play_file(pf if pf.ends_with(".wav") else pf + ".wav", at2, 2.0, 40.0, 0.6, self, true)
			return null
		"FRM_FINISHINDEXEDPARTICLE":
			# Partikelsystem auslaufen lassen (keine neuen Teilchen, Knoten verschwindet danach)
			var fpi := int(vm.value(args[0])) if args.size() > 0 else -1
			var fpn = _indexed_particles.get(fpi)
			if is_instance_valid(fpn):
				OrigParticles.stop(fpn)
			_indexed_particles.erase(fpi)
			return null
		"FRM_SETANIMATION", "FRM_SETANIMATIONDELAYED":
			# (Frame, "name.i3d", Kanal): Skriptanimation MODELS\name.5DS – Opcode 0x5D/0x60, Handler hd2.exe 0x41BAA7
			# (Kanal = 2. Argument von Frame->SetAnimation, vtbl +0x84); leerer Name leert den Kanal (ls_anim.gd)
			var af3 := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if af3:
				anim.set_animation(af3, _str(vm.value(args[1])) if args.size() > 1 else "",
					int(vm.value(args[2])) if args.size() > 2 else 0)
			return null
		"FRM_STOPANIMATION", "FRM_RESETANIMATION":
			# Opcode 0x63 (0x41B96E): Kanal anhalten; 0x61 (0x41B9F1): zusätzlich Ruhelage (vtbl +0x20)
			var af4 := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if af4:
				var ch4 := int(vm.value(args[1])) if args.size() > 1 else 0
				if fname == "FRM_STOPANIMATION":
					anim.stop_animation(af4, ch4)
				else:
					anim.reset_animation(af4, ch4)
			return null
		"FRM_SETSHIFTING":
			# (Frame, an, rückwärts): CZECH1 Schrankenkette („retez“) – Texturverschiebung, solange die Schranke sich bewegt
			# (_ACTOR_GetState 2/3) [P aus den Skripten]; Geschwindigkeit [E]
			var shf := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if shf:
				set_shifting(shf, LsVM._truthy(vm.value(args[1])) if args.size() > 1 else false,
					LsVM._truthy(vm.value(args[2])) if args.size() > 2 else false)
			return null
		"_MP_ISITEMINTEAMINVENTORY":
			# (Seite, Gegenstand, var): trägt ein Soldat der Seite (1 = Achse, 0 = Alliierte) den Gegenstand?
			var team_mp := Soldier.TEAM_AXIS if args.size() > 0 and int(vm.value(args[0])) == 1 else Soldier.TEAM_ALLIED
			var item_mp := int(vm.value(args[1])) if args.size() > 1 else -1
			for n_mp in get_tree().get_nodes_in_group("team_%d" % team_mp):
				var so_mp := n_mp as Soldier
				if so_mp and so_mp.alive and so_mp.get_meta("orig_items", []).has(item_mp):
					if args.size() > 2 and args[2][0] == "var":
						vm.vars[args[2][1]] = so_mp
					return 1
			return 0
		# --- Menschen (eigener Akteur) ---
		"HUMAN_SUSPEND":
			var b3 := _brain(vm)
			if b3:
				b3.suspended = LsVM._truthy(vm.value(args[0]))
			return null
		"HUMAN_MOVE", "HUMAN_MOVETOFRAME":
			var b4 := _brain(vm)
			var tgt := _frame_arg(vm, args[0])
			if b4 and tgt:
				var route := checkpoint_route(b4.soldier.global_position, tgt)
				b4.script_route(route)
				return {"wait_until": b4.script_move_done, "timeout": 40.0 * maxf(1.0, route.size() * 0.5)}
			return null
		"HUMAN_MOVERANDOMRADIUS":
			var b5 := _brain(vm)
			if b5:
				var r3 := float(vm.value(args[0])) if args.size() > 0 else 5.0
				b5.script_move(b5.home_pos + Vector3(randf_range(-r3, r3), 0, randf_range(-r3, r3)))
				return {"wait_until": b5.script_move_done, "timeout": 30.0}
			return null
		"HUMAN_STOP":
			var b6 := _brain(vm)
			if b6:
				b6.stop_moving()
			return null
		"HUMAN_TURNAT":
			var b7 := _brain(vm)
			var tf := _frame_arg(vm, args[0])
			if b7 and tf:
				b7.script_look_at = tf.global_position
				return {"wait": 0.4}
			return null
		"HUMAN_TURNATNEARESTPLAYER":
			var b8 := _brain(vm)
			if b8:
				var best: Soldier = null
				for p in _players():
					if best == null or p.global_position.distance_to(_pos(vm.me)) < best.global_position.distance_to(_pos(vm.me)):
						best = p
				if best:
					b8.script_look_at = best.global_position
				return {"wait": 0.4}
			return null
		"HUMAN_SETMODE_WALK", "HUMAN_SETMODE_RUN", "HUMAN_SETMODE_SILENCE", "HUMAN_SETMODE_GUARD":
			var s := _soldier(vm)
			if s:
				s.move_mode = {"HUMAN_SETMODE_WALK": Soldier.MoveMode.WALK, "HUMAN_SETMODE_RUN": Soldier.MoveMode.RUN,
					"HUMAN_SETMODE_SILENCE": Soldier.MoveMode.SNEAK, "HUMAN_SETMODE_GUARD": Soldier.MoveMode.WALK}[fname]
				var bb := _brain(vm)
				if bb:
					bb.script_move_mode = s.move_mode
			return null
		"HUMAN_SETMODE_CROUCH", "HUMAN_SETMODE_STAND", "HUMAN_SETMODE_LIE", "HUMAN_SETMODE_STANDFAST":
			var s2 := _soldier(vm)
			var b9 := _brain(vm)
			var st: int = {"HUMAN_SETMODE_CROUCH": Soldier.Stance.CROUCH, "HUMAN_SETMODE_LIE": Soldier.Stance.PRONE}.get(fname, Soldier.Stance.STAND)
			if b9:
				b9.script_stance = st
			elif s2:
				s2.stance_request = st
			if s2 and s2.model and s2.model.body:
				s2.model.body.stand_up()     # beendet HUMAN_ACTIVITY_Sit/_Turk (z. B. af1_02: Turk … SETMODE_Stand) [P]
			return null
		"HUMAN_SETAIMODE_ZOMBIE", "HUMAN_SETAIMODE_DEFENSIVE", "HUMAN_SETAIMODE_AGGRESSIVE":
			_set_ai_mode(_brain(vm), fname)
			return null
		"FRAME_SETAIMODE_ZOMBIE", "FRAME_SETAIMODE_DEFENSIVE", "FRAME_SETAIMODE_AGGRESSIVE":
			var fr2 := _frame_arg(vm, args[0])
			if fr2:
				_set_ai_mode(fr2.get_node_or_null("EnemyBrain"), fname.replace("FRAME_", "HUMAN_"))
			return null
		"HUMAN_SETSIGHTRANGE", "HUMAN_SETHEARRANGE":
			var s3 := _soldier(vm)
			var per: Perception = s3.get_node_or_null("Perception") if s3 else null
			if per:
				if fname == "HUMAN_SETSIGHTRANGE":
					per.sight_range = float(vm.value(args[0]))
				else:
					per.hear_range = float(vm.value(args[0]))
			return null
		"HUMAN_WEAPONONARM":
			var s4 := _soldier(vm)
			if s4:
				s4.aiming = LsVM._truthy(vm.value(args[0]))
			return null
		"HUMAN_SETALARM":
			var b10 := _brain(vm)
			if b10 and LsVM._truthy(vm.value(args[0])):
				mission.raise_alarm(_pos(vm.me), vm.me)
			elif b10:
				b10.calm_down()
			return null
		"HUMAN_KILL", "HUMAN_KILLEX":
			var b11 := _brain(vm)
			var victim := _frame_arg(vm, args[0]) as Soldier
			if b11 and victim:
				b11.script_attack(victim)
			elif victim and victim.alive and (not (vm.me is Soldier) or victim == vm.me):
				# B-036b: Skripttod – alten Schützen nicht stehen lassen (a3 r_ar3_kill_player.scr tötete sas_7, Bericht nannte
				# fälschlich den letzten Kameraden-Treffer „durch sas_2“ als Ursache)
				victim.last_attacker = null
				victim.die(null)     # aus einem Objekt-/Dummy-Skript (z. B. AFRICA1 Flugzeug): Akteur stirbt
			return null
		# --- Zwischensequenzen ---
		"CSC_RUNCUTSCENE":
			run_cutscene(int(vm.value(args[0])) if args.size() > 0 else 1, vm)
			return null
		"CSC_ENDCUTSCENE":
			if in_cutscene:
				cutscene_end_reason = "script"
			end_cutscene()
			return null
		"FRM_SETACTIVECAMERA":
			var cf := _frame_arg(vm, args[0]) if args.size() > 0 else null
			# B-049: K0 aus FRM_GetActiveCamera = Spielkamera (rig.camera) → Rückgabe an den Spieler
			if cf and mission and mission.get("rig") and cf == mission.rig.camera:
				_cam_frame = null
				_cam_target = null
				if not in_cutscene:
					mission.rig.camera.current = true
				return null
			if cf and (in_cutscene or fake_cutscene):
				_cam_frame = cf
				_cut_cam.global_transform = cf.global_transform
				_cut_cam.current = true
				_cam_target = null
			return null
		"FRM_WATCHTRACK", "FRM_WATCHTRACKWITHPARENT":
			if extras and args.size() >= 2:
				var tf2 := _frame_arg(vm, args[0])
				var par2 := _frame_arg(vm, args[2]) if fname == "FRM_WATCHTRACKWITHPARENT" and args.size() > 2 else null
				extras.watch_track(tf2, _str(vm.value(args[1])), par2)
			return null
		"PLAYMUSIC", "PLAYCUTSCENEMUSIC":
			if extras and args.size() > 0:
				if fname == "PLAYMUSIC":
					extras.play_table(int(vm.value(args[0])))
				else:
					extras.play_cutscene(int(vm.value(args[0])))
			return null
		"_ISININVENTORY":
			# Original-Gegenstände (items.dat) im Inventar: Inventarsystem für Originalgegenstände offen
			for p in _players():
				if (p as Soldier).get_meta("orig_items", []).has(int(vm.value(args[0]))):
					return 1
			return 0
		"_ITEMINRANGE":
			# (Gegenstand, Umkreis m) um das Skriptobjekt: frei liegend oder von einem Soldaten getragen
			var oi = mission.get("interactive")
			if oi == null or args.size() < 2:
				return 0
			return 1 if oi.item_in_range(int(vm.value(args[0])), _pos(vm.me), float(vm.value(args[1]))) else 0
		"HUMAN_REMOVEITEMSFROMSTORE":
			# (Mensch, Gegenstand): alle Exemplare aus dem Originalinventar entfernen (TUTORIAL-Rückgabe,
			# BURMA2-Gegner); Granaten/Waffe dieses Typs in der Hand gehen mit
			var rs := _frame_arg(vm, args[0]) as Soldier
			if rs and args.size() > 1:
				var rid := int(vm.value(args[1]))
				var rinv: Array = rs.get_meta("orig_items", [])
				rs.set_meta("orig_items", rinv.filter(func(x): return int(x) != rid))
				var rwd := WeaponDB.from_orig(rid)
				for i in rs.weapons.size():
					if rwd and rs.weapons[i] and rs.weapons[i].data == rwd:
						rs.weapons[i] = null
				if rid in SAS.MEDKITS:
					rs.medkits = 0
			return null
		"MISSION_SETUNIFORMDISGUISE":
			# Original: Tarnung durch Feinduniform an/aus (ALPS2: 0 nach Enttarnung)
			var on_d := LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			for p in mission.squad.members:
				if p.has_meta("start_disguise") or not on_d:
					p.disguised = on_d
			return null
		"_ISLANGUAGEVERSION":
			# B-007: gewählte Sprachfassung (Ordnernamen wie Text\<sprache>: English, EnglishUS, French …)
			return 1 if _str(vm.value(args[0])).to_lower() == Settings.language.to_lower() else 0
		# --- Formationen (Gegnertrupps folgen ihrem Anführer) ---
		"FORMATION_CREATE":
			var fl := _frame_arg(vm, args[0])
			if fl:
				formations[fl] = {"members": [], "type": "line", "scale": 3.0}
			return null
		"FORMATION_ADDMEMBER", "FORMATION_DELMEMBER":
			var fm := _frame_arg(vm, args[0])
			for lead in formations:
				formations[lead]["members"].erase(fm)
			if fname == "FORMATION_ADDMEMBER" and args.size() > 1:
				var fl2 := _frame_arg(vm, args[1])
				if fm and formations.has(fl2):
					formations[fl2]["members"].append(fm)
			return null
		"FORMATION_DESTROY":
			formations.erase(_frame_arg(vm, args[0]))
			return null
		"FORMATION_SETTYPELINE", "FORMATION_SETTYPECOLUMN", "FORMATION_SETTYPEQUAD2X3", "FORMATION_SETTYPEQUAD3X2", \
				"FORMATION_SETTYPEARROWSHARP", "FORMATION_SETTYPEARROWINVERT":
			var ft := _frame_arg(vm, args[0])
			if formations.has(ft):
				formations[ft]["type"] = fname.trim_prefix("FORMATION_SETTYPE").to_lower()
			return null
		"FORMATION_SETSCALE":
			var fs := _frame_arg(vm, args[0])
			if formations.has(fs):
				formations[fs]["scale"] = clampf(float(vm.value(args[1])) / 1000.0, 1.0, 10.0)
			return null
		# --- Gegner zählen / Abfragen ---
		"_GETNUMLIVEENEMIES", "_GETCOUNTOFCARNAGEENEMIES":
			var n2 := 0
			for e in mission.enemies:
				if is_instance_valid(e) and e.alive and not e.has_meta("hands_up"):
					n2 += 1      # Ergebene/Gefangene zählen nicht als lebende Gegner
			return n2
		"_SPGETGAMEDIFFICULTY":
			return Game.difficulty()
		"FRM_GETNEARESTPLAYER":
			var from_f := _frame_arg(vm, args[0])
			var best_p: Soldier = null
			for p in _players():
				if best_p == null or p.global_position.distance_to(_pos(from_f)) < best_p.global_position.distance_to(_pos(from_f)):
					best_p = p
			if args.size() > 1 and args[1][0] == "var":
				vm.vars[args[1][1]] = best_p
			return null
		"_ENEMYINRANGE":
			# Gegner aus Sicht des Frames (Soldat: anderes Team; sonst: der Trupp des Spielers)
			var ef2 := _frame_arg(vm, args[0]) if args.size() > 1 else vm.me as Node3D
			var rr := float(vm.value(args[1] if args.size() > 1 else args[0]))
			# Von Dummies/Objekten aus: Gegner = Achsensoldaten (AFRICA2 „kein Gegner im Minenfeld“,
			# CZECH5 dummy_PD „Gegner entkommen“); von Soldaten aus: die jeweils andere Seite (ohne Neutrale)
			var my_team := (ef2 as Soldier).team if ef2 is Soldier else Soldier.TEAM_ALLIED
			for n3 in get_tree().get_nodes_in_group("soldiers"):
				var so := n3 as Soldier
				if so and so.alive and so.team != my_team and so.team != Soldier.TEAM_NEUTRAL \
						and so.global_position.distance_to(_pos(ef2)) <= rr:
					return 1
			return 0
		# --- Bewegte Objekte / Effekte ---
		"FRM_ROTATEY", "FRM_ROTATEZ", "FRM_ROTATEX":
			# (Frame, Gesamtwinkel in Grad, Grad pro Sekunde) – z. B. Propeller, Lüfter, Radar
			var rf := _frame_arg(vm, args[0])
			if rf and args.size() >= 3:
				_rotations.append({"node": rf, "axis": {"FRM_ROTATEX": Vector3.RIGHT, "FRM_ROTATEY": Vector3.UP}.get(fname, Vector3.BACK),
					"left": absf(float(vm.value(args[1]))), "speed": float(vm.value(args[2])) * signf(float(vm.value(args[1])))})
			return null
		"FRM_CREATEINDEXEDPARTICLE":
			var pf2 := _frame_arg(vm, args[1]) if args.size() > 1 else null
			if pf2:
				var node := _particles(int(vm.value(args[0])), pf2.global_position, true)
				_particle_index += 1
				_indexed_particles[_particle_index] = node
				if args.size() > 2 and args[2][0] == "var":
					vm.vars[args[2][1]] = _particle_index
			return null
		"FRM_DESTROYINDEXEDPARTICLE":
			var pi := int(vm.value(args[0]))
			var pn = _indexed_particles.get(pi)
			if is_instance_valid(pn):
				pn.queue_free()
			_indexed_particles.erase(pi)
			return null
		"ITEM_TELEPORT":
			var itf := _frame_arg(vm, args[0])
			var itt := _frame_arg(vm, args[1]) if args.size() > 1 else null
			if itf and itt:
				itf.global_position = itt.global_position
				itf.visible = true
			return null
		"AIRATTACK_SETTARGET":
			# Luftangriff auf ein Ziel (Original: Flugzeuge greifen an). Näherung: Einschläge in Zielnähe.
			var at := _frame_arg(vm, args[0])
			# Skript eines angreifenden Flugzeugs (Akteurtyp 36, OrigAirAttack, hd2.exe 0x5E7570): Ziel an das Flugzeug
			if is_instance_valid(vm.me) and vm.me.has_method("set_air_target"):
				vm.me.set_air_target(at, args.size() < 2 or LsVM._truthy(vm.value(args[1])))
				return null
			if at:
				if args.size() < 2 or LsVM._truthy(vm.value(args[1])):
					_air_targets[at] = 0.0
				else:
					_air_targets.erase(at)
			return null
		"SETINTERFACETIMER":
			_set_interface_timer(float(vm.value(args[0])) / 1000.0)
			return null
		"HUMAN_SETSNIPER":
			# AP-6: Setzer 0x5AF700 [B]: Postenlage, float(Arg 2), an/aus; Wirkung = Leine um den Posten [P] (EnemyBrain.set_sniper)
			var sb2 := _brain(vm)
			if sb2:
				sb2.set_sniper(LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true,
					float(vm.value(args[1])) if args.size() > 1 else 0.0)
			return null
		"DOG_MOVE":
			var dm := vm.me as Dog
			var dt := _frame_arg(vm, args[0])
			if dm and dt:
				dm.move_target = dt.global_position
				dm.lying = false
			return null
		"DOG_SETMODE_LIE", "DOG_SETMODE_STAND":
			var dl := vm.me as Dog
			if dl:
				dl.lying = fname == "DOG_SETMODE_LIE"
			return null
		"CSC_SETCAMERAANIMATION":
			# (Kameraframe, "#name"): Opcode 0xA7, Handler hd2.exe 0x41CB37 → Sequenzobjekt vtbl +0xB0(Frame, Name);
			# Kameraframe folgt dem Animationsobjekt in Weltlage (ls_anim.gd, re_notes_script_anims.md)
			var cf3 := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if cf3:
				anim.set_camera_animation(cf3, _str(vm.value(args[1])) if args.size() > 1 else "")
			return null
		"FRM_SOUNDADJUSTDOPPLER":
			# B-033: Handler 0x41A0AF [B]: nur Klangframes (Typ 4), Arg 2 × Faktor an vtable +0x8C (Dopplerstärke), Arg 3 je nach
			# Arg-Typ [P]. Nachbau: Dopplerverfolgung am Klangspieler + Kamera, Rohwerte als Meta „doppler“ [P/E]
			var dpf := _frame_arg(vm, args[0]) if args.size() > 0 else null
			if dpf is AudioStreamPlayer3D:
				(dpf as AudioStreamPlayer3D).doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
				dpf.set_meta("doppler", args.slice(1).map(func(a): return vm.value(a)))
				var dcam := get_viewport().get_camera_3d() if is_inside_tree() else null
				if dcam:
					dcam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
			doppler_calls += 1
			return null
		"SETNPCTEAMSTATUS":
			# NPC kämpft als Teil des Teams (KI statt Skriptsteuerung), z. B. befreite Verbündete
			var nf := _frame_arg(vm, args[0])
			var nb: EnemyBrain = nf.get_node_or_null("EnemyBrain") if nf else null
			if nb and args.size() > 1:
				var join := LsVM._truthy(vm.value(args[1]))
				nb.script_control = not join
				if nf is Soldier:
					var ns := nf as Soldier
					ns.remove_from_group("team_%d" % ns.team)
					# Seite 4 (Fraktion 1, hd2.exe 0x5A8820) bleibt beim Verlassen Spielerseite (AI_AUDIT_ALLY)
					ns.team = Soldier.TEAM_ALLIED if join or int(ns.get_meta("orig_side", 3)) == 4 else Soldier.TEAM_NEUTRAL
					ns.add_to_group("team_%d" % ns.team)
					# Original: NPC schließt sich dem Team an und folgt (CZECH3 Freiberg zur Villa) –
					# Begleit-KI wie bei befreiten Gefangenen; 0 = wieder Skriptsteuerung
					var esc: EscortBrain = ns.get_node_or_null("EscortBrain")
					if join and esc == null:
						nb.enabled = false
						nb.set_physics_process(false)
						esc = EscortBrain.new()
						esc.name = "EscortBrain"
						esc.squad = mission.squad
						ns.add_child(esc)
						esc.setup(ns)
						esc.released = true          # ohne eigenen Dialog (Originalskript spricht selbst)
						ns.add_to_group("team_%d" % ns.team)
					elif not join and esc:
						esc.queue_free()
						nb.enabled = true
						nb.set_physics_process(true)
			return null
		"SETPLAYERINPUT":
			if mission.controller:
				mission.controller.input_enabled = LsVM._truthy(vm.value(args[0]))
			return null
		"FRM_GETACTIVECAMERA":
			if args.size() > 0 and args[0][0] == "var":
				vm.vars[args[0][1]] = _cam_frame if is_instance_valid(_cam_frame) else (mission.rig.camera if mission.rig else null)
			return null
		"HUMAN_CREATEITEMINSTORE":
			# Gegenstand (items.sav-Nummer) ins Inventar des Akteurs; Verbandskasten (54) wirkt sofort
			var hs := _soldier(vm)
			if hs:
				var item := int(vm.value(args[0]))
				var cnt := int(vm.value(args[1])) if args.size() > 1 else 1
				var inv: Array = hs.get_meta("orig_items", [])
				for k in cnt:
					inv.append(item)
				hs.set_meta("orig_items", inv)
				if item == 54:
					hs.medkits += cnt
			return null
		"DOOR_LOCK":
			var df := _frame_arg(vm, args[0])
			if df:
				var lock := LsVM._truthy(vm.value(args[1])) if args.size() > 1 else true
				df.set_meta("locked", lock)
				var dctl = df.get_meta("orig_ctl") if df.has_meta("orig_ctl") else null
				if dctl and is_instance_valid(dctl) and dctl.has_method("set_locked"):
					dctl.set_locked(lock)
			return null
		"SETUPJUNKERS88":
			# AFRICA6: a·0,01 = Schadensfaktor an der Ju 88, b·0,01 = Teiler des Trefferschadens an Jägern
			if mission.has_method("setup_junkers88"):
				mission.setup_junkers88(float(vm.value(args[0])) if args.size() > 0 else 60.0,
					float(vm.value(args[1])) if args.size() > 1 else 100.0)
			return null
		"DECORATOR_SETON":
			# NORMANDY x_n1_kamera-ya / CZECH3 r_cz3_cutscene: Dekoration (Bewuchs) während der Zwischensequenz aus/an [P];
			# im Nachbau = die Bewuchs-Meshes des Levels (Grafikoption „Gras“ bleibt maßgeblich)
			decorator_on = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			if orig.has_method("set_decorator"):
				orig.set_decorator(decorator_on)
			return null
		"HUMAN_SETIGNORECIRCUMVENTIONFLAG":
			# B-033: Handler 0x422BE2 [B]: nur für Menschen (Typ 5), Gehirn +0x11C = (Arg ≠ 0); 0x562E30 überspringt bei gesetztem
			# Byte die Umgehungsplanung auf dem Pfad (0x5626B0), Spielstand 0x577440 (Block 0x13A6). Nachbau: AIBrain lässt das
			# seitliche Ausweichen/Durchlaufen an Hindernissen und stehenden Menschen weg [P Wirkung]. Nur AFRICA3 af3a_21 (Mechaniker).
			var icb := _soldier(vm)
			var icai: AIBrain = icb.get_node_or_null("EnemyBrain") as AIBrain if icb else null
			if icai:
				icai.ignore_circumvention = LsVM._truthy(vm.value(args[0])) if args.size() > 0 else true
			return null
		"FRM_SETTARGET":
			# (Waffe, Ziel-Dummy, an/aus): nur Zwischensequenzen, Skriptkommentare „link/unlink zbrane“ (BURMA2 cutsas1):
			# Waffe bleibt an der Hand (zuvor FRM_TeleportNearFrame(Waffe, hw1)) und zeigt auf den Dummy „wt“ der Figur [P].
			# Nachbau: je Bild Lage = Hand-Frame, Ausrichtung -Z auf das Ziel (LS3D +z vorn → Godot -z, convert_mission).
			var tw_f := _frame_arg(vm, args[0]) if args.size() > 0 else null
			var tw_t := _frame_arg(vm, args[1]) if args.size() > 1 else null
			if tw_f:
				set_aim_link(tw_f, tw_t, LsVM._truthy(vm.value(args[2])) if args.size() > 2 else true)
			return null
		"FRM_SETCAMERAFRAME":
			_cam_target = _frame_arg(vm, args[0]) if args.size() > 0 else null
			return null
		"FRM_SETCAMERAFRAMESLIDE":
			var sf := _frame_arg(vm, args[0])
			if sf and in_cutscene:
				var tw := create_tween()
				tw.tween_property(_cut_cam, "global_position", sf.global_position + Vector3.UP * 2.0,
					maxf(float(vm.value(args[1])) if args.size() > 1 else 3.0, 0.1))
			return null
		"CSC_FADEOUT", "CSC_FADEIN":
			var ms := float(vm.value(args[0])) if args.size() > 0 else 500.0
			_fade_to(1.0 if fname == "CSC_FADEOUT" else 0.0, ms / 1000.0)
			return null
		"WEATHER_SETON":
			_set_snow(LsVM._truthy(vm.value(args[0])))
			return null
		"WEATHER_SETMODE", "WEATHER_SETCOUNT", "WEATHER_SETSPEED", "WEATHER_SETSIZE", "WEATHER_SETCOLORIN":
			# Wetterparameter (bu1_dazd.scr: Regen = Modus 0 ohne SetMode; r_arc1a_pocasi.scr: Schnee = SetMode(1))
			var wa: Array = []
			for a in args:
				wa.append(float(vm.value(a)))
			if fname == "WEATHER_SETMODE" and wa.size() > 0:
				weather.mode = int(wa[0])
			elif fname == "WEATHER_SETCOUNT" and wa.size() > 0:
				weather.count = wa[0]
			elif fname == "WEATHER_SETSPEED" and wa.size() > 0:
				weather.speed = wa[0]
			elif fname == "WEATHER_SETSIZE" and wa.size() > 1:
				weather.size = Vector2(wa[0], wa[1])
			elif fname == "WEATHER_SETCOLORIN" and wa.size() > 3:
				weather.color = Color8(int(wa[0]), int(wa[1]), int(wa[2]), int(wa[3]))
			_apply_weather()
			return null
		"WEATHER_SETDIR", "WEATHER_SETSPACE", "WEATHER_SETCOLOROUT":
			# r_arc1a_pocasi: SetDir(X, Y, Z) mit Y = -100, X/Z zufällig ±60 (Wind) → Fallrichtung [P];
			# SetSpace(15, 15) / (12, 30) → Ausdehnung des Niederschlagsvolumens in m (waagrecht, senkrecht) [P];
			# SetColorOut RGBA (Alpha stets 0) → Farbe am Ende der Lebenszeit (Verlauf ColorIn → ColorOut) [P]
			var wd: Array = []
			for a in args:
				wd.append(float(vm.value(a)))
			if fname == "WEATHER_SETDIR" and wd.size() > 2:
				weather.dir = Vector3(wd[0], wd[1], -wd[2])
			elif fname == "WEATHER_SETSPACE" and wd.size() > 1:
				weather.space = Vector2(wd[0], wd[1])
			elif fname == "WEATHER_SETCOLOROUT" and wd.size() > 3:
				weather.color_out = Color8(int(wd[0]), int(wd[1]), int(wd[2]), int(wd[3]))
			_apply_weather()
			return null
		"CSC_RUNCLOUDER":
			# ARCTIC1 r_arc1a_cutscene „spustam mraky“ (Wolken an): hd2.exe nennt dazu clouder.tga/clouder2.tga (0x839658)
			# → Wolkenschatten über der Szene [P]; Nachbau: wandernde Projektion (Decal) der Originaltextur [E Größe/Tempo]
			set_clouder(LsVM._truthy(vm.value(args[0])) if args.size() > 0 else false)
			return null
		"__SETUPAUTOLOGGING":
			return _noop(fname, "0x41C8C6: nur pc weiter (Diagnose)")    # B-033 [B]
		# --- Sprache: Original-Aufnahme + Untertitel (Lippenbewegung: Platzhalter) ---
		"FRM_MORPHSPEECH", "FRM_MORPHSPEECHDELAYED":
			var spk := _frame_arg(vm, args[0])
			var dur := speak(spk, vm.value(args[1]))
			return {"wait": dur} if fname == "FRM_MORPHSPEECHDELAYED" else null
		"PLAYSOUND":
			if args.size() > 0:
				var v = vm.value(args[0])
				# 8-stellige Werte = Sprachaufnahmen; PlaySound(Kategorie, Gruppe) = Klangtabelle IngameSounds.def
				# (z. B. (6, 2) „Explosion Dirt“, (2, 5) Schuss K98, (12, 8) „See Target“) am Skriptbesitzer
				if (v is int or v is float) and int(v) >= 1000000:
					speak(vm.me, v)
				elif args.size() > 1 and (v is int or v is float):
					var at: Vector3 = (vm.me as Node3D).global_position if vm.me is Node3D and (vm.me as Node3D).is_inside_tree() else Vector3.ZERO
					OrigAudio.play_group(int(v), int(vm.value(args[1])), at)
			return null
		"HUMAN_SETWAITFORPLAYER":
			var bw := _brain(vm)
			if bw:
				bw.wait_for_player = LsVM._truthy(vm.value(args[0]))
				bw.wait_stop_dist = float(vm.value(args[1])) if args.size() > 1 else 12.0
				bw.wait_resume_dist = float(vm.value(args[2])) if args.size() > 2 else 8.0
			return null
		# --- Hunde (DOG_*) ---
		"DOG_SETAIMODE_AGGRESSIVE", "DOG_SETAIMODE_DEFENSIVE", "DOG_SETAIMODE_ZOMBIE":
			var dg := vm.me as Dog
			if dg:
				dg.aggressive = fname == "DOG_SETAIMODE_AGGRESSIVE"
			return null
		"DOG_SETOWNER":
			var dg2 := vm.me as Dog
			if dg2:
				dg2.owner_frame = _frame_arg(vm, args[0]) if args.size() > 0 else null
			return null
		"DOG_SUSPEND":
			var dg3 := vm.me as Dog
			if dg3:
				dg3.suspended = LsVM._truthy(vm.value(args[0]))
			return null
		"DOG_SETRANGEHEAR", "DOG_SETRANGESIGHT":
			var dg4 := vm.me as Dog
			if dg4:
				if fname == "DOG_SETRANGEHEAR":
					dg4.hear_range = float(vm.value(args[0]))
				else:
					dg4.sight_range = float(vm.value(args[0]))
			return null
		"DOG_SETMODE_RUN", "DOG_SETMODE_WALK":
			var dg5 := vm.me as Dog
			if dg5:
				dg5.run_mode = fname == "DOG_SETMODE_RUN"
			return null
		"DOG_ATTACK":
			var dg6 := vm.me as Dog
			if dg6:
				var vic := _frame_arg(vm, args[0]) as Soldier if args.size() > 0 else null
				# 0x5CF7C0: Ziel nur ein Mensch (Typ 3), NULL = beliebiger Gegner; Angriffsflags 0x140000 [B]
				dg6.attacking = true
				dg6.target = vic
				dg6.attack_any = vic == null
			return null
		"DOG_CLEARALARM":
			var dg7 := vm.me as Dog
			if dg7:
				dg7.clear_alarm()
			return null
		# --- Fahrzeuge / Waffenstellungen ---
		"CAR_SETFUEL":
			var car := _frame_arg(vm, args[0]) as Vehicle
			if car:
				car.fuel = float(vm.value(args[1]))
			return null
		"HUMAN_BOARDVEHICLE":
			# (Fahrzeug/Stellung, 1 = einsteigen / 0 = aussteigen, Sitz) – Kommentare AFRICA2 af2_posily_01:
			# „prave nastoupil“ (eingestiegen) bei 1, „prave vystoupil“ (ausgestiegen) bei 0 [B]
			var enter := LsVM._truthy(vm.value(args[1])) if args.size() > 1 else true
			var seat := int(vm.value(args[2])) if args.size() > 2 else -1
			return _board(vm, _str(vm.value(args[0])) if args.size() > 0 and enter else "", seat)
		"HUMAN_DRIVE":
			var sd := _soldier(vm)
			var veh := sd.vehicle as Vehicle if sd else null
			if veh == null:
				return null
			var wp := _str(vm.value(args[0]))
			var kmh := float(vm.value(args[1])) if args.size() > 1 else 30.0
			# Original 0x422F5B: |int(kmh)·0,28| ≤ 1e-8 = Halt; kmh < 0 = rückwärts (re_notes_drive §3.7 [B], Gap-CZ 09.11.2026)
			if wp == "" or int(kmh) == 0:
				veh.stop_drive()
				return null
			# Original: Name = Ziel im Fahrzeugnetz (check2.bin Abschnitt 2 → drive.json); unbekannt → anhalten
			var gi := _drive_name(wp)
			if gi < 0:
				var goal_f := find_frame(wp)
				if goal_f == null:
					veh.stop_drive()
					return null
				veh.drive_path([goal_f.global_position], kmh)
			else:
				veh.drive_path(_drive_route(veh.global_position, gi), kmh)
			return {"wait_until": veh.drive_done, "timeout": 600.0}
		"HUMAN_DRIVENEARPLAYER":
			# Original: zufälliger Netzknoten (ohne Flag 0x100) im Umkreis von 20 m um den nächsten Spieler
			var sd2 := _soldier(vm)
			var veh2 := sd2.vehicle as Vehicle if sd2 else null
			if veh2 == null:
				return null
			_drive_load()
			var near: Soldier = null
			for p in _players():
				if near == null or p.global_position.distance_to(veh2.global_position) < near.global_position.distance_to(veh2.global_position):
					near = p
			if near == null:
				return null
			var cand: Array = []
			for i in _drive_nodes.size():
				var nd: Dictionary = _drive_nodes[i]
				if not nd.get("near_player_excluded", false) and _drive_astar.get_point_position(i).distance_to(near.global_position) <= 20.0:
					cand.append(i)
			if cand.is_empty():
				return null
			var kmh2 := float(vm.value(args[0])) if args.size() > 0 else 30.0
			veh2.drive_path(_drive_route(veh2.global_position, cand[randi() % cand.size()]), kmh2 if kmh2 != 0.0 else 30.0)
			return {"wait_until": veh2.drive_done, "timeout": 600.0}
		# --- Gegenstände / Effekte ---
		"HUMAN_PICKOBJECT":
			var ps2 := _soldier(vm)
			var obj := _frame_arg(vm, args[0])
			if ps2 and obj:
				obj.reparent(ps2, false)
				obj.position = Vector3(0.25, 0.9, 0.35)
				obj.rotation = Vector3.ZERO
				obj.visible = true
				ps2.set_meta("carried", obj)
				# B-020: Kollision des getragenen Objekts aus – sonst schob der eigene Kanister (Level-Kollision am Frame
				# „kanister“) Kanisternik in ARCTIC1 dauernd weg (er „lief“ ruhend 100 m weit, den Hang hinab)
				for co in obj.find_children("*", "CollisionObject3D", true, false) + ([obj] if obj is CollisionObject3D else []):
					if not co.has_meta("_carry_layers"):
						co.set_meta("_carry_layers", [co.collision_layer, co.collision_mask])
					co.collision_layer = 0
					co.collision_mask = 0
			return null
		"HUMAN_DROPOBJECT":
			var ps3 := _soldier(vm)
			if ps3 and ps3.has_meta("carried"):
				var c: Node3D = ps3.get_meta("carried")
				ps3.remove_meta("carried")
				if is_instance_valid(c):
					c.reparent(mission.dynamic_root, true)
					c.global_position = _ground(c.global_position)
					for co in c.find_children("*", "CollisionObject3D", true, false) + ([c] if c is CollisionObject3D else []):
						if co.has_meta("_carry_layers"):
							co.collision_layer = co.get_meta("_carry_layers")[0]
							co.collision_mask = co.get_meta("_carry_layers")[1]
							co.remove_meta("_carry_layers")
			return null
		"FRM_CREATEPHYSICALOBJECT":
			var po := _frame_arg(vm, args[0])
			if po:
				po.reparent(mission.dynamic_root, true)
				po.visible = true
				po.global_position = _ground(po.global_position)
			return null
		"FRM_TELEPORTNEARCHECKPOINT":
			var tw3 := _frame_arg(vm, args[0])
			var cp := find_frame(_str(vm.value(args[1])))
			if tw3 and cp:
				tw3.global_position = cp.global_position
				if tw3 is Soldier:
					var tb: EnemyBrain = tw3.get_node_or_null("EnemyBrain")
					if tb:
						tb.stop_moving()
			return null
		"FRM_CREATEPARTICLE":
			var pf := _frame_arg(vm, args[1]) if args.size() > 1 else null
			if pf:
				_particles(int(vm.value(args[0])), pf.global_position)
			return null
		"MAKEEXPLOSION":
			# (Frame, a, b): Radius = b·0,001 m, Stärke = a·0,001 (re_notes_interactive.md §2 [P]);
			# Stärke 0 = nur Effekt/Wackeln (z. B. MakeExplosion(me, 0, 10000) an Normandie-Kanonen)
			var ef := _frame_arg(vm, args[0])
			if ef:
				var power := float(vm.value(args[1])) * 0.001 if args.size() > 1 else 1000.0
				var rad := clampf(float(vm.value(args[2])) * 0.001 if args.size() > 2 else 7.0, 2.0, 40.0)
				if power <= 0.0:
					Effects.explosion(ef.global_position + Vector3.UP, rad * 0.5)
				else:
					_explosion(ef.global_position + Vector3.UP, rad, clampf(power * 0.2, 60.0, 900.0))
			return null
		"HUMAN_LOOKAROUND":
			var bl := _brain(vm)
			if bl:
				bl.set_look_around(int(vm.value(args[0])) if args.size() > 0 else 1)
			return null
		"HUMAN_SETANIM":
			# ("%%name", Einblenden ms, Ausblenden ms, Schleife): Menschen-Dispatcher hd2.exe 0x421E66 → 0x5AF780 (nur in
			# KI-Zustand 5 [B], Bedeutung des Zustands offen) → 0x591230(Name, a, b, Schleife≠0). Überblendzeiten ohne
			# Wirkung [E]; Animation endet bei Bewegung/Kampf (ls_anim.gd) [E]
			var hsa := _soldier(vm)
			if hsa and hsa.alive and args.size() > 0:
				anim.set_animation(hsa, _str(vm.value(args[0])), 100,
					LsVM._truthy(vm.value(args[3])) if args.size() > 3 else false, true)
			return null
		"HUMAN_SETOPTIMIZED":
			# [B] hd2.exe Befehlstabelle 0x835E14 (Kennung 0x3F) → Menschen-Dispatcher 0x421C00 → 0x5AF5C0: nur im KI-Zustand 5,
			# 0x58FCC0 merkt den Wert (+0x1D4) → 0x5AC110 setzt Renderbits 2/4 am Modell-Frame (+0x22C). Reine Darstellungs-/
			# Leistungsoptimierung ohne Spielwirkung → im Nachbau belegt wirkungslos.
			return _noop(fname, "0x5AF5C0: nur Renderbits am Modell")
		"FRM_SWITCHFACETEXTURE":
			var ff := _frame_arg(vm, args[0]) if args.size() > 0 else null
			var ftex := _str(vm.value(args[1])) if args.size() > 1 else ""
			if ff is Soldier and (ff as Soldier).model and ftex != "":
				if (ff as Soldier).model.set_face_texture(ftex):
					face_switches += 1
				else:
					face_missing[ftex] = int(face_missing.get(ftex, 0)) + 1
			return null
		"FRM_SETLIGHTMAP", "FRM_SETGROUPLIGHTMAP":
			# (Frame | "Gruppe", Stufe): Original-Lightmapstufen aus scene2.bin (tools/fmt_lightmaps.py, B-035 [B Daten]);
			# Stufe n = Satz n+1, Helligkeit relativ zu Stufe 0 → Albedo der Meshes (OrigLevel.set_lightmap)
			var lv := int(vm.value(args[1])) if args.size() > 1 else 0
			if fname == "FRM_SETGROUPLIGHTMAP":
				var gname := _str(vm.value(args[0])) if args.size() > 0 else ""
				for m in orig.lightmap_group(gname):
					var gf := find_frame(String(m))
					if gf:
						orig.set_lightmap(gf, String(m), lv)
				lightmap_calls[gname] = lv
			else:
				var lf := _frame_arg(vm, args[0]) if args.size() > 0 else null
				if lf:
					orig.set_lightmap(lf, String(lf.name), lv)
					lightmap_calls[String(lf.name)] = lv
			return null
		"HUMAN_ACTIVITY_SMOKE", "HUMAN_ACTIVITY_POINT", "HUMAN_ACTIVITY_SIT", "HUMAN_ACTIVITY_DRINKBOTTLE", \
				"HUMAN_ACTIVITY_COLD", "HUMAN_ACTIVITY_HAT", "HUMAN_ACTIVITY_TURK", "HUMAN_ACTIVITY_HOT", "HUMAN_ACTIVITY_CHECKWEAPON", "HUMAN_ACTIVITY_BINOCULARS", \
				"HUMAN_ACTIVITY_BINOCULARSEND", "HUMAN_ACTIVITY_SALUTE", "HUMAN_ACTIVITY_CARD", "HUMAN_ACTIVITY_CUBES", \
				"HUMAN_ACTIVITY_SHOES", "HUMAN_ACTIVITY_TELEGRAPH", "HUMAN_ACTIVITY_PHONE", "HUMAN_ACTIVITY_READ", \
				"HUMAN_ACTIVITY_EAT", "HUMAN_ACTIVITY_SPOTUP", "HUMAN_ACTIVITY_SPOTDOWN", "HUMAN_ACTIVITY_SPOTRIGHT", \
				"HUMAN_ACTIVITY_SPOTLEFT", "HUMAN_ACTIVITY_PLAYCAR", "HUMAN_ACTIVITY_PLAYAIRPLANE", "HUMAN_ACTIVITY_PLAYPUPPET", \
				"HUMAN_ACTIVITY_TRAP", "HUMAN_ACTIVITY_EXERCISE", "HUMAN_ACTIVITY_STANDSLEEP", "HUMAN_ACTIVITY_PISS", \
				"HUMAN_ACTIVITY_SLEEP":
			return _human_activity(vm, fname, args)
	if not unimplemented.has(fname):
		unimplemented[fname] = 0
	unimplemented[fname] += 1
	return null


## O-006: stummen Befehl zählen (einmalige Konsolenmeldung je Befehl) – Rückgabe null wie ein normaler Befehl
func _stub(fname: String, owner: String):
	if not stubbed.has(fname):
		stubbed[fname] = {"count": 0, "owner": owner}
		print("LS stumm: %s (%s)" % [fname, owner])
	stubbed[fname]["count"] = int(stubbed[fname]["count"]) + 1
	return null


## B-035: belegt wirkungsloser Befehl (Beleg im Bericht), kein „stumm“
var noop_calls := {}
var doppler_calls := 0             ## B-033: FRM_SoundAdjustDoppler (Diagnose/Test)


## B-033: Führerweg über die Checkpoint-Kanten (CheckpointJoin/Separate, AP-5). Ist das Ziel ein Wegpunkt mit Kanten und
## steht der Soldat ≤ CHECKPOINT_SNAP m an einem verbundenen Wegpunkt, läuft er die Kantenfolge ab (Zwischenpunkte, dann
## Ziel); sonst direkt (Navmesh) zum Ziel. Original: Wegfindung im Wegpunktnetz 0x698500 +0x54 [B]; Startwahl
## „nächster Wegpunkt“ und Fangradius [P/E] (Grundkanten aus check.bin fehlen, s. docs/status/b026_b033.md).
const CHECKPOINT_SNAP := 4.0


func checkpoint_route(from: Vector3, tgt: Node3D) -> Array:
	var direct: Array = [tgt.global_position]
	if checkpoints.edges.is_empty() or "--checkpoint_route=0" in OS.get_cmdline_user_args():
		return direct
	_drive_load()
	if not checkpoints.base_pos.is_empty():
		# Gesamtnetz (Grundkanten + Skriptkanten): nur wenn der kürzeste Weg eine Skriptkante nutzt, folgt der Soldat den
		# Netzknoten – sonst bleibt das Navmesh maßgeblich (Navmesh ersetzt das Grundnetz [E], Skriptkanten = Ablauf)
		var tn := -1
		for k in checkpoints.name_node:
			if waypoints.get(k) == tgt:
				tn = int(checkpoints.name_node[k])
				break
		var sn := checkpoints.nearest_node(from, CHECKPOINT_SNAP)
		if tn < 0 or sn < 0 or sn == tn:
			return direct
		var r := checkpoints.route_nodes(sn, tn)
		if r.is_empty() or not bool(r["script_edge"]):
			return direct
		var pts: Array = []
		var nodes: Array = r["nodes"]
		for i in range(1, nodes.size() - 1):
			pts.append(checkpoints.base_pos[nodes[i]])
		pts.append(tgt.global_position)
		print("CHECKPOINT-WEG %s: %d Punkte %s" % [tgt.name, pts.size(), str(nodes)])
		return pts
	var tname := ""
	var start := ""
	var best := CHECKPOINT_SNAP * CHECKPOINT_SNAP
	var seen := {}
	for e in checkpoints.edges:
		for k in e:
			if seen.has(k):
				continue
			seen[k] = true
			var wp: Node3D = waypoints.get(k)
			if wp == null:
				continue
			if wp == tgt:
				tname = k
			var d2 := wp.global_position.distance_squared_to(from)
			if d2 < best:
				best = d2
				start = k
	if tname == "" or start == "" or start == tname:
		return direct
	var names := checkpoints.path(start, tname)
	if names.size() < 2:
		return direct
	var out: Array = []
	for i in range(1, names.size()):
		out.append((waypoints[names[i]] as Node3D).global_position)
	return out


func _noop(fname: String, proof: String):
	if not noop_calls.has(fname):
		noop_calls[fname] = {"count": 0, "proof": proof}
	noop_calls[fname]["count"] = int(noop_calls[fname]["count"]) + 1
	return null


# --- B-035 Darstellung: Gesichter, Lightmaps, Zielverknüpfung, Texturverschiebung, Wolken ---------------------
var face_switches := 0             ## erfolgreiche FRM_SwitchFaceTexture
var face_missing := {}             ## Textur fehlt im Cache -> Anzahl
var lightmap_calls := {}           ## Frame/Gruppe -> zuletzt gesetzte Stufe (Diagnose)
var decorator_on := true
var aim_links := {}                ## Waffe -> {target, hand}
var _shifting := {}                ## Frame -> Richtung (+1/-1)
const SHIFT_SPEED := 0.6           ## UV/s [E]
var _clouder: Decal
var clouder_on := false


func set_aim_link(w: Node3D, target: Node3D, on: bool) -> void:
	if not on or target == null:
		aim_links.erase(w)
		return
	var hand = w.get_meta("tnf_to") if w.has_meta("tnf_to") else null
	aim_links[w] = {"target": target, "hand": hand}
	_update_aim(w)


func _update_aim(w: Node3D) -> void:
	var l: Dictionary = aim_links[w]
	var t: Node3D = l["target"]
	if not is_instance_valid(t):
		aim_links.erase(w)
		return
	var h = l["hand"]
	if h is Node3D and is_instance_valid(h):
		w.global_position = (h as Node3D).global_position
	var to := t.global_position - w.global_position
	if to.length() > 0.01:
		var up := Vector3.UP if absf(to.normalized().y) < 0.99 else Vector3.BACK
		w.look_at(t.global_position, up)


func set_shifting(f: Node3D, on: bool, reverse: bool) -> void:
	if on:
		_shifting[f] = -1.0 if reverse else 1.0
		for mi in _meshes_of(f):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m and not m.has_meta("shift_own"):
					var nm := m.duplicate() as BaseMaterial3D
					nm.set_meta("shift_own", true)
					mi.set_surface_override_material(s, nm)
	else:
		_shifting.erase(f)


func shift_offset(f: Node3D) -> float:
	for mi in _meshes_of(f):
		var m := mi.get_active_material(0) as BaseMaterial3D
		if m:
			return m.uv1_offset.y
	return 0.0


static func _meshes_of(f: Node3D) -> Array:
	var out: Array = []
	if f is MeshInstance3D and (f as MeshInstance3D).mesh:
		out.append(f)
	for c in f.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).mesh:
			out.append(c)
	return out


func set_clouder(on: bool) -> void:
	clouder_on = on
	if on and _clouder == null:
		var p := "%s/textures/clouder.png" % OrigLevel.cache_root()
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				_clouder = Decal.new()
				_clouder.name = "Clouder"
				_clouder.texture_albedo = ImageTexture.create_from_image(img)
				_clouder.size = Vector3(160, 120, 160)
				_clouder.modulate = Color(0, 0, 0, 0.45)       # dunkler Schatten [E]
				_clouder.upper_fade = 0.0
				_clouder.lower_fade = 0.0
				add_child(_clouder)
	if _clouder:
		_clouder.visible = on


func _display_tick(delta: float) -> void:
	for w in aim_links.keys():
		if not is_instance_valid(w):
			aim_links.erase(w)
			continue
		_update_aim(w)
	for f in _shifting.keys():
		if not is_instance_valid(f):
			_shifting.erase(f)
			continue
		for mi in _meshes_of(f):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s) as BaseMaterial3D
				if m:
					m.uv1_offset.y = fposmod(m.uv1_offset.y + SHIFT_SPEED * delta * float(_shifting[f]), 1.0)
	if _clouder and clouder_on:
		var cam: Camera3D = _cut_cam if (in_cutscene or (fake_cutscene and is_instance_valid(_cam_frame))) and _cut_cam else (mission.rig.camera if mission and mission.get("rig") else null)
		if cam:
			_clouder.global_position.x = cam.global_position.x
			_clouder.global_position.z = cam.global_position.z
			_clouder.global_position.y = cam.global_position.y
		# Wolken ziehen: Textur über die Lage verschieben (Decal hat keinen UV-Versatz → Position relativ zu einem Driftpunkt)
		_cloud_drift += delta * 2.0
		_clouder.global_position.x += fposmod(_cloud_drift, 160.0) - 80.0


var _cloud_drift := 0.0


## Bericht der stummen und nicht umgesetzten Befehle (anhängend, je Mission ein Block)
func write_silent_report(path := "res://test_output/ls_silent.txt", tag := "") -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.READ_WRITE) if FileAccess.file_exists(abs_path) else FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var total := 0
	for k in stubbed:
		total += int(stubbed[k]["count"])
	f.store_line("== %s  stumm: %d Befehle / %d Aufrufe, nicht umgesetzt: %d" % [tag, stubbed.size(), total, unimplemented.size()])
	var keys := stubbed.keys()
	keys.sort()
	for k in keys:
		f.store_line("stumm\t%s\t%d\t%s" % [k, int(stubbed[k]["count"]), stubbed[k]["owner"]])
	var nk := noop_calls.keys()
	nk.sort()
	for k in nk:
		f.store_line("wirkungslos\t%s\t%d\t%s" % [k, int(noop_calls[k]["count"]), noop_calls[k]["proof"]])
	for k in face_missing:
		f.store_line("gesicht_fehlt\t%s\t%d" % [k, int(face_missing[k])])
	for k in unimplemented:
		f.store_line("unbekannt\t%s\t%d" % [k, int(unimplemented[k])])
	f.close()


var _voice_cache := {}
var no_team_damage := false      ## CSC_NoTeamDamage (Zwischensequenz)
var _thunder_on := false
var _thunder_light: Node3D
var _thunder_t := 0.0
var _dup_count := 0


## HUMAN_ACTIVITY_* (Opcodes 0xD9–0xF7, Menschen-Dispatcher hd2.exe 0x421C00, docs/re_notes_weapons.md §13):
## Tätigkeits-ID = anim.sav-Satz (BodyAnim.activity_clip). [B Code] Smoke, Spot*, Play*, Trap, Exercise, StandSleep, Piss,
## Sleep: ohne Wirkung (Sprung auf 0x423354). Card(1/0/sonst) 0x19/Ende/0x1A, Cubes 0x1B, DrinkBottle(ohne/mit Objekt)
## 0x1C/0x1D, Cold 0x35, Hot 0x36, CheckWeapon 0x37, Hat 0x38, Shoes 0x39, Salute(1/2/sonst) 0x3B/0x3C/0x3A,
## Point(Obj) 0x3E, Eat(0/1,Obj) Ende/0x42, Phone 0x43, Telegraph 0x44, Read 0x45 (je 0 = Ende 0x4C); diese Befehle
## schalten den Befehlszeiger nicht weiter (Handle in +0x18) -> Skript wartet bis Tätigkeitsende [P].
## Binoculars 0x41 / BinocularsEnd 0x3D, Sit(Obj) (0x58F4B0) und Turk (0x58F540) laufen ohne Warten weiter [B].
## Sätze ohne Clip (0x1B, 0x35, 0x37–0x3A, 0x43–0x45) zeigen nichts [B Daten].
const ACTIVITY_NOP := ["HUMAN_ACTIVITY_SMOKE", "HUMAN_ACTIVITY_SPOTUP", "HUMAN_ACTIVITY_SPOTDOWN", "HUMAN_ACTIVITY_SPOTRIGHT",
	"HUMAN_ACTIVITY_SPOTLEFT", "HUMAN_ACTIVITY_PLAYCAR", "HUMAN_ACTIVITY_PLAYAIRPLANE", "HUMAN_ACTIVITY_PLAYPUPPET",
	"HUMAN_ACTIVITY_TRAP", "HUMAN_ACTIVITY_EXERCISE", "HUMAN_ACTIVITY_STANDSLEEP", "HUMAN_ACTIVITY_PISS",
	"HUMAN_ACTIVITY_SLEEP"]
const ACTIVITY_FIXED := {"HUMAN_ACTIVITY_CUBES": 0x1B, "HUMAN_ACTIVITY_COLD": 0x35, "HUMAN_ACTIVITY_HOT": 0x36,
	"HUMAN_ACTIVITY_CHECKWEAPON": 0x37, "HUMAN_ACTIVITY_SHOES": 0x39, "HUMAN_ACTIVITY_HAT": 0x38}
const ACTIVITY_STOP := 0x4C
var activity_log := []    ## Tests: [Akteur, Funktion, Tätigkeits-ID, Dauer]


func _human_activity(vm, fname: String, args: Array):
	if fname in ACTIVITY_NOP:
		return null
	var s := _soldier(vm)
	if s == null or not s.alive or s.model == null or s.model.body == null:
		return null
	var body: BodyAnim = s.model.body
	var a0 = vm.value(args[0]) if args.size() > 0 else 0
	var id := -1
	var wait := true
	match fname:
		"HUMAN_ACTIVITY_SIT", "HUMAN_ACTIVITY_TURK":
			var fr: Node3D = _frame_arg(vm, args[0]) if fname == "HUMAN_ACTIVITY_SIT" and args.size() > 0 else null
			if fr:
				# Sitzplatz-Frame: Figur dorthin, Blick wie der Frame (Frame-Vorderseite −Z) [E]
				s.global_position = fr.global_position
				var fwd := -fr.global_basis.z
				fwd.y = 0.0
				if fwd.length() > 0.01:
					s.look_yaw = atan2(-fwd.x, -fwd.z)
					s.rotation.y = s.look_yaw
				var b := _brain(vm)
				if b:
					b.stop_moving()
			body.sit_down("sit" if fname == "HUMAN_ACTIVITY_SIT" else "turk")
			activity_log.append([String(s.name), fname, -1, 0.0])
			return null
		"HUMAN_ACTIVITY_BINOCULARS":
			id = 0x41
			wait = false
		"HUMAN_ACTIVITY_BINOCULARSEND":
			id = 0x3D
			wait = false
		"HUMAN_ACTIVITY_CARD":
			id = 0x19 if int(a0) == 1 else (ACTIVITY_STOP if int(a0) == 0 else 0x1A)
		"HUMAN_ACTIVITY_SALUTE":
			id = 0x3B if int(a0) == 1 else (0x3C if int(a0) == 2 else 0x3A)
		"HUMAN_ACTIVITY_DRINKBOTTLE":
			id = 0x1D if _frame_arg(vm, args[0]) != null else 0x1C
		"HUMAN_ACTIVITY_POINT":
			id = 0x3E
			var pt: Node3D = _frame_arg(vm, args[0]) if args.size() > 0 else null
			if pt:
				var d := pt.global_position - s.global_position
				if Vector2(d.x, d.z).length() > 0.1:
					s.look_yaw = atan2(-d.x, -d.z)     # zum Ziel drehen [E]
		"HUMAN_ACTIVITY_EAT", "HUMAN_ACTIVITY_PHONE", "HUMAN_ACTIVITY_TELEGRAPH", "HUMAN_ACTIVITY_READ":
			id = ACTIVITY_STOP if int(a0) == 0 else {"HUMAN_ACTIVITY_EAT": 0x42, "HUMAN_ACTIVITY_PHONE": 0x43,
					"HUMAN_ACTIVITY_TELEGRAPH": 0x44, "HUMAN_ACTIVITY_READ": 0x45}[fname]
		_:
			id = int(ACTIVITY_FIXED.get(fname, ACTIVITY_STOP))
	if id == ACTIVITY_STOP or id == 0x3D:
		body.stop_activity()
		activity_log.append([String(s.name), fname, id, 0.0])
		return null
	var st := clampi(int(s.stance), 0, 2)
	var dur := body.start_activity(id, st)
	activity_log.append([String(s.name), fname, id, dur])
	if wait and dur > 0.0:
		return {"wait": dur}
	return null


## HUMAN_Investigate: nach Ankunft 4 s umsehen (Dauer = ANNAHME)
func _investigate_done(b, t_end: Array) -> bool:
	if not is_instance_valid(b) or not b.soldier.alive:
		return true
	if float(t_end[0]) < 0.0:
		if b.script_move_done():
			t_end[0] = Time.get_ticks_msec() / 1000.0 + 4.0
			b.script_look_at = b.soldier.global_position + b.soldier.forward() * 5.0
		return false
	b.soldier.look_yaw += 0.03
	return Time.get_ticks_msec() / 1000.0 >= float(t_end[0])


## CSC_DuplicateHuman: Darsteller = Kopie der Originalfigur (nur Darstellung, ohne KI/Kollision) an der Stelle der
## Quelle; unter dem Namen registriert (FRM_FindFrame). Zwischensequenzanimationen (.i3d) fehlen weiterhin.
func _duplicate_human(src: Node3D, nm: String) -> Node3D:
	if src == null:
		return null
	_dup_count += 1
	var dup := Node3D.new()
	dup.name = ("CSC_" + (nm if nm != "" else "dup%d" % _dup_count)).validate_node_name()
	var fig: Node3D = null
	if src is Soldier and (src as Soldier).model and (src as Soldier).model.get("orig_figure") != null:
		var of: Node3D = (src as Soldier).model.orig_figure
		if is_instance_valid(of):
			fig = of.duplicate() as Node3D
	if fig:
		dup.add_child(fig)
	mission.dynamic_root.add_child(dup)
	dup.global_transform = src.global_transform
	dup.set_meta("csc_duplicate", nm if nm != "" else String(dup.name))
	if nm != "":
		register_actor(nm, dup)
	return dup


## Gewitter (THUNDERSTORM_SetOn): Blitze schalten das Lichtframe kurz ein, Donner aus der Klangtabelle
func _thunder_tick(delta: float) -> void:
	if not _thunder_on or not is_instance_valid(_thunder_light):
		return
	_thunder_t -= delta
	if _thunder_t <= 0.0:
		_thunder_t = randf_range(4.0, 12.0)
		_thunder_light.visible = true
		get_tree().create_timer(0.15, false).timeout.connect(func():
			if is_instance_valid(_thunder_light):
				_thunder_light.visible = false)


## OnExit (Missionsende): Tagebuch-/Aufräum-Ereignisse aller Skripte sofort ausführen (Delay wird übersprungen)
func run_exit_handlers() -> void:
	for vm in vms:
		if vm.terminated or not vm.code.handlers.has("ONEXIT"):
			continue
		vm.paused = false
		vm.events.clear()
		vm.atomic = false
		vm._enter(vm.code.handlers["ONEXIT"])
		for i in 50:
			vm.wait = 0.0
			vm.wait_until = Callable()
			if vm.ended:
				break
			vm._run()


static var _dmodel_cache = null


## Modelle mit Schadensmodell d<Modell>.4ds (orig_cache/dmodels.json, tools/fmt_dmodels.py)
static func _dmodels() -> Dictionary:
	if _dmodel_cache == null:
		var d = _read_json(OrigLevel.cache_root() + "/dmodels.json")
		_dmodel_cache = d if d is Dictionary else {}
	return _dmodel_cache


## OnHit: Treffer an Skriptobjekten (Soldaten über damaged, Fahrzeuge über Vehicle.hit, Objekte über Trefferflächen)
func _setup_hit_events() -> void:
	# Szenenobjekte mit OnDeath-Skript ohne eigenes Steuerobjekt (z. B. BURMA1 Kisten „Bedne_obj*“ mit Flugzeugteilen):
	# durch Explosionen zerstörbar -> OnDeath (Schadensschwelle 40 = ANNAHME, Objektgesundheit nicht dekodiert)
	for vm in vms:
		var o2: Node3D = vm.me
		if not vm.code.handlers.has("ONDEATH") or not is_instance_valid(o2) or o2 is Soldier or o2 is Vehicle \
				or o2 is Dog or o2.has_meta("orig_ctl") or o2.has_meta("script_breakable"):
			continue
		if o2.find_children("*", "MeshInstance3D", true, false).is_empty():
			continue     # Dummies ohne Modell
		var br := ScriptBreakable.new()
		br.runtime = self
		br.target = o2
		# Zerstörbarer Frame des Originals: es gibt ein Schadensmodell MODELS\d<Modell>.4ds (hd2.exe 0x43CE40 „d%s“,
		# Liste tools/fmt_dmodels.py → orig_cache/dmodels.json) → Geschosse/Explosionen ziehen HP ab (0x43B000), HP
		# Standard 100 Originaleinheiten (Parameter „version“, 0x43CD20) [P]; sonst bisherige Explosionsschwelle [E]
		var mdl: String = object_models.get(String(o2.name).to_upper(), "")
		if mdl != "" and _dmodels().has(mdl):
			br.hp = 100.0
		o2.add_child(br)
		o2.set_meta("script_breakable", br)
		if br.hp > 0.0:
			var bodies2 := o2.find_children("*", "CollisionObject3D", true, false)
			for b2 in bodies2:
				if not b2.has_meta("hit_proxy"):
					b2.set_meta("hit_proxy", br)
			if bodies2.is_empty():
				# Zielscheiben ohne Kollision (TUTORIAL m_tut_panak*): Trefferfläche aus der Modellgröße (Ebene 3)
				var box2 := OrigInteractive.world_aabb(o2)
				var ar2 := Area3D.new()
				ar2.collision_layer = Hitbox.LAYER
				ar2.collision_mask = 0
				ar2.monitoring = false
				var cs2 := CollisionShape3D.new()
				var bs2 := BoxShape3D.new()
				bs2.size = box2.size.max(Vector3(0.2, 0.2, 0.2))
				cs2.shape = bs2
				ar2.add_child(cs2)
				ar2.set_meta("hit_proxy", br)
				o2.add_child(ar2)
				ar2.global_position = box2.get_center()
	# OnUse an Fahrzeugen (CZECH6 la_panther_ C5_obj01.scr „Tiger erobern“): Benutzen des Einstiegs [P Zeitpunkt]
	for vm in vms:
		if vm.code.handlers.has("ONUSE") and vm.me is Vehicle and not vm.me.has_meta("onuse_connected"):
			var veh: Vehicle = vm.me
			veh.set_meta("onuse_connected", true)
			for ent in veh.find_children("*", "", true, false):
				if ent is Interactable:
					(ent as Interactable).used.connect(func(_by): notify(veh, "ONUSE"))
	for vm in vms:
		if not vm.code.handlers.has("ONHIT") or not is_instance_valid(vm.me):
			continue
		var own: Node3D = vm.me
		if own is Soldier:
			if not own.has_meta("onhit_connected"):
				own.set_meta("onhit_connected", true)
				(own as Soldier).damaged.connect(func(_a, _z): notify(own, "ONHIT"))
			continue
		if own is Vehicle:
			continue      # orig_mission verbindet Vehicle.hit
		var proxy := HitProxy.new()
		proxy.runtime = self
		proxy.target = own
		own.add_child(proxy)
		var bodies := own.find_children("*", "CollisionObject3D", true, false)
		for b in bodies:
			if not b.has_meta("hit_proxy"):
				b.set_meta("hit_proxy", proxy)
		if bodies.is_empty():
			# Objekte ohne Kollision (z. B. Lampen „la_svetlo_*“): Trefferfläche aus der Modellgröße (Ebene 3, blockiert nichts)
			var box := OrigInteractive.world_aabb(own)
			var area := Area3D.new()
			area.collision_layer = Hitbox.LAYER
			area.collision_mask = 0
			area.monitoring = false
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = box.size.max(Vector3(0.3, 0.3, 0.3))
			cs.shape = bs
			area.add_child(cs)
			area.set_meta("hit_proxy", proxy)
			own.add_child(area)
			area.global_position = box.get_center()


class ScriptBreakable extends Node3D:
	var runtime
	var target: Node3D
	var destroyed := false
	var hp := 0.0          ## > 0: zerstörbarer Frame mit Schadensmodell (Originaleinheiten), sonst Explosionsschwelle

	func _ready() -> void:
		add_to_group("destructibles")
		global_position = OrigInteractive.world_aabb(target).get_center()

	func on_bullet_hit(d: float, by: Node) -> void:
		runtime.notify(target, "ONHIT")
		if hp > 0.0:
			_damage(d * 10.0, by)      # Spielschaden = Original/10 (WeaponDB)

	func on_explosion(d: float, by: Node) -> void:
		runtime.notify(target, "ONHIT")
		if hp > 0.0:
			_damage(d * 10.0, by)
			return
		if destroyed or d < 40.0:
			return
		_destroy()

	## 0x43B000: HP > Schaden → HP −= Schaden, sonst zerstört (0x43CCA0 → OnDeath 0x41D920)
	func _damage(amount: float, _by: Node) -> void:
		if destroyed:
			return
		if hp > amount:
			hp -= amount
			return
		_destroy()

	func _destroy() -> void:
		destroyed = true
		print("Skriptobjekt %s zerstört" % target.name)
		target.visible = false
		target.set_meta("actor_state", 0)
		for b in target.find_children("*", "CollisionObject3D", true, false):
			(b as CollisionObject3D).collision_layer = 0
		runtime.notify(target, "ONDEATH")


class HitProxy extends Node:
	var runtime
	var target: Node3D
	var _last := 0

	func on_bullet_hit(_d: float, _by: Node) -> void:
		var now := Time.get_ticks_msec()
		if now - _last < 100:
			return
		_last = now
		runtime.notify(target, "ONHIT")

	func on_explosion(d: float, by: Node) -> void:
		on_bullet_hit(d, by)


## Satz sprechen: Original-Aufnahme (orig_cache/sounds/<id>.wav) am Sprecher abspielen und
## Untertitel zeigen. Gibt die Dauer in Sekunden zurück (für FRM_MorphSpeechDelayed).
func speak(who: Node3D, id) -> float:
	var key := "%08d" % int(id)
	var t := text(id)
	var dur := clampf(t.length() * 0.07, 1.5, 8.0)
	# Sprachausgabe über OrigAudio (Bus „Voice“, Lautstärke-Regler „Sprache“)
	var at: Vector3 = who.global_position if is_instance_valid(who) and who.is_inside_tree() else Vector3.ZERO
	var p := OrigAudio.play_file(key + ".wav", at, 6.0, 60.0, 1.0, who if is_instance_valid(who) else self,
		false, &"Voice")
	if p:
		dur = p.stream.get_length()
	if t != "" and Settings.subtitles:
		subtitle.emit(t, dur + 0.5)
		Events.say(t, dur + 0.5)
	return dur


## HUMAN_BoardVehicle: Fahrzeug (Vehicle) besteigen, MG-Stellung (Akteurtyp 21) besetzen;
## leerer Name = aussteigen bzw. Stellung verlassen.
func _board(vm: LsVM, target_name: String, seat := -1):
	var s := _soldier(vm)
	if s == null or not s.alive:
		return null
	var b := _brain(vm)
	if target_name == "":
		if s.vehicle is Vehicle:
			(s.vehicle as Vehicle).leave(s)
		if s.mounted != null and is_instance_valid(s.mounted) and s.mounted.has_method("dismount"):
			s.mounted.dismount()
		if s.has_meta("mg_post"):
			s.remove_meta("mg_post")
		return null
	var t := find_frame(target_name)
	if t is Vehicle:
		var v := t as Vehicle
		if s.global_position.distance_to(v.global_position) > 12.0 and b:
			b.script_move(v.global_position + v.global_basis.x * 2.0)
			return {"wait_until": _board_wait.bind(s, v, seat), "timeout": 60.0}   # gap_afrika [E]: 20 s reichten für 29 m nicht
		_board_now(s, v, seat)
		return null
	if t:
		# Waffenstellung (Akteurtyp 21): hinter die Waffe gehen und sie besetzen (OrigEmplacement)
		var ctl = t.get_meta("orig_ctl") if t.has_meta("orig_ctl") else null
		s.set_meta("mg_post", t)
		var behind: Vector3 = ctl.gunner_spot() if ctl and is_instance_valid(ctl) and ctl.has_method("gunner_spot") \
			else t.global_position + t.global_basis.z * 0.9
		if b:
			b.home_pos = behind
			if b.distance_to(behind) > 2.5:
				b.script_move(behind)
				return {"wait_until": _mount_wait.bind(s, ctl), "timeout": 20.0}
		else:
			s.global_position = behind
		_mount_now(s, ctl)
	return null


func _mount_now(s, ctl) -> void:
	if ctl and is_instance_valid(ctl) and ctl.has_method("can_ai_mount") and ctl.can_ai_mount(s):
		var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
		if b:
			b.stop_moving()
		ctl.mount(s)


## Warten bis der Akteur an der Stellung ist, dann besetzen (untypisiert: Argumente können freigegeben sein)
func _mount_wait(s, ctl) -> bool:
	if not is_instance_valid(s) or not s.alive:
		return true
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	# nah genug (die Waffe selbst versperrt den letzten Meter) oder Weg beendet -> besetzen
	var near: bool = ctl != null and is_instance_valid(ctl) and ctl.has_method("gunner_spot") \
		and (s as Node3D).global_position.distance_to(ctl.gunner_spot()) < 2.5
	if b == null or near or b.script_move_done():
		_mount_now(s, ctl)
		return true
	return false


func _board_now(s: Soldier, v: Vehicle, seat := -1) -> bool:
	if s.vehicle == v:
		return true
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	if b:
		b.stop_moving()
	return v.board(s, seat <= 0, seat)


## Warten bis der Akteur am Fahrzeug ist (untypisiert: Argumente k?nnen inzwischen freigegeben sein)
func _board_wait(s, v, seat := -1) -> bool:
	if not is_instance_valid(s) or not is_instance_valid(v) or not s.alive:
		return true
	if s.global_position.distance_to(v.global_position) < 5.0:
		return _board_now(s, v, seat) or true
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	# gap_afrika [P]: Weg beendet (Fahrzeugrumpf/Hindernis hält > 5 m vom Mittelpunkt) → trotzdem einsteigen; vorher
	# blieb der Fahrer draußen und alle folgenden HUMAN_Drive liefen ins Leere (Tiger-Besatzung 29 m vom Panzer)
	if b == null or b.script_move_done():
		_board_now(s, v, seat)
		return true
	return false


## SetInterfaceTimer(ms): Countdown-Anzeige oben in der Mitte; 0 blendet sie aus
func _set_interface_timer(seconds: float) -> void:
	if _timer_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 6
		add_child(layer)
		_timer_label = Label.new()
		_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_timer_label.position = Vector2(-60, 70)
		_timer_label.size = Vector2(120, 40)
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_timer_label.add_theme_font_size_override("font_size", 28)
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		layer.add_child(_timer_label)
	_timer_left = seconds if seconds > 0.0 else -1.0
	_timer_label.visible = seconds > 0.0


func _ground(p: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 20.0, 1))
	return hit.position if not hit.is_empty() else p


## Original-Partikelsysteme (B-028/O-007): Index = Eintrag der Tabelle TABLES\effects.def (orig_particles.gd).
## Stoßeffekte enden nach ihrer Lebensdauer; Dauereffekte (FRM_CreateParticle) laufen 60 s [E: Original-Dauer nicht
## dekodiert], indizierte bis FRM_Finish/DestroyIndexedParticle.
func _particles(id: int, pos: Vector3, indexed := false) -> Node3D:
	var node := OrigParticles.spawn(id, pos, mission.dynamic_root)
	if not indexed:
		if OrigParticles.is_continuous(id):
			get_tree().create_timer(60.0, false).timeout.connect(func(): OrigParticles.stop(node))
		else:
			get_tree().create_timer(float(node.get_meta("max_life", 2.0)) + 1.0, false).timeout.connect(func():
				if is_instance_valid(node):
					node.queue_free())
	return node


## MakeExplosion: Explosion mit Splitterschaden (Soldaten mit Sichtlinie, Hunde).
## --- Fahrzeugnetz (HUMAN_Drive, docs/re_notes_drive.md) ---------------------------------
var _drive_astar: AStar3D
var _drive_nodes: Array = []
var _drive_names: Array = []


func _drive_load() -> void:
	if _drive_astar:
		return
	_drive_astar = AStar3D.new()
	var d = _read_json(orig.mission_dir + "/drive.json")
	if typeof(d) != TYPE_DICTIONARY:
		return
	# B-033: Fußwegenetz (Abschnitt 1) als Grundkanten der Checkpoints; fehlt bei alten drive.json (ohne „walk“)
	checkpoints.load_base(d.get("walk"))
	var v: Dictionary = d.get("vehicle", {})
	_drive_nodes = v.get("nodes", [])
	_drive_names = v.get("names", [])
	for i in _drive_nodes.size():
		var p: Array = _drive_nodes[i]["pos"]
		_drive_astar.add_point(i, Vector3(p[0], p[1], p[2]))
	for i in _drive_nodes.size():
		for l in _drive_nodes[i].get("links", []):
			var j := int(l[0])
			if j >= 0 and j < _drive_nodes.size() and j != i:
				_drive_astar.connect_points(i, j, false)


## Original-Namenssuche: erste 16 Zeichen, ohne Groß-/Kleinschreibung, erster Treffer (−1 = unbekannt)
func _drive_name(n: String) -> int:
	_drive_load()
	var key := n.substr(0, 16).to_lower()
	if key == "":
		return -1
	for e in _drive_names:
		if String(e.get("name", "")).substr(0, 16).to_lower() == key:
			return int(e.get("node", -1))
	return -1


## Route vom Netzknoten nahe dem Fahrzeug (≤ 10 m) zum Zielknoten; sonst direkt zum Ziel
func _drive_route(from: Vector3, goal_node: int) -> Array:
	var goal := _drive_astar.get_point_position(goal_node)
	var start := _drive_astar.get_closest_point(from)
	if start < 0 or _drive_astar.get_point_position(start).distance_to(from) > 10.0:
		return [goal]
	var pts: Array = []
	for p in _drive_astar.get_point_path(start, goal_node):
		pts.append(p)
	if pts.is_empty():
		pts.append(goal)
	return pts


## sound: [Kategorie, Gruppe] der Klangtabelle (Sprengplatz: Akteurwert explosion_sound, Kat. 6)
func _explosion(pos: Vector3, radius: float, damage: float, sound: Array = [6, 0]) -> void:
	Effects.explosion(pos, radius, sound)
	Events.emit_noise(pos, 400.0, null, Soldier.TEAM_AXIS, &"explosion")
	OrigInteractive.damage_objects(get_tree(), pos, radius, damage)
	var space := get_viewport().world_3d.direct_space_state
	for n in get_tree().get_nodes_in_group("soldiers"):
		var s := n as Soldier
		if s and s.alive and s.global_position.distance_to(pos) < radius:
			var q := PhysicsRayQueryParameters3D.create(pos, s.global_position + Vector3.UP * 0.6, 1)
			if space.intersect_ray(q).is_empty():
				s.apply_hit(damage * (1.0 - s.global_position.distance_to(pos) / radius), &"torso", null,
					(s.global_position - pos).normalized())


func _set_ai_mode(b: EnemyBrain, fname: String) -> void:
	if b == null:
		return
	match fname:
		"HUMAN_SETAIMODE_ZOMBIE":
			b.script_control = true
			b.zombie_mode = true         # B-021: Original-Modus 0x400 (Opcode 0xCF)
		"HUMAN_SETAIMODE_DEFENSIVE":
			b.ai_mode = EnemyBrain.Mode.DEFENSIVE
			b.zombie_mode = false
			b.leave_script_control()     # B-020: Alarm aus dem Zombie-Modus an die eigene KI übergeben
		"HUMAN_SETAIMODE_AGGRESSIVE":
			b.ai_mode = EnemyBrain.Mode.AGGRESSIVE
			b.zombie_mode = false
			b.leave_script_control()


# --- Zwischensequenzen (CSC_*) --------------------------------------------------------

var in_cutscene := false
var fake_cutscene := false      ## B-049: CSC_SetupFakeCutscene(true) – Skriptkamera, Welt läuft weiter
var cutscene_id := 0
var _cutscene_vm: LsVM
var _cut_cam: Camera3D
var _cam_target: Node3D
var _cam_frame: Node3D           ## aktive Original-Kamera (kann einer Spur folgen)
var _fade: ColorRect
var _skip_label: Label
var _snow: GPUParticles3D
var auto_skip := false          ## Tests: Zwischensequenzen sofort überspringen
var _cutscene_vms: Array = []   ## Skripte mit OnCutscene(n) der laufenden Sequenz (Schnelldurchlauf beim Überspringen)
const CUTSCENE_FALLBACK_S := 90.0
const CUT_IDLE_AFTER_CAMERA := 0.5   ## [E] Nachlauf nach Ende der Kameraanimation + Skriptablauf
const CUT_IDLE_NO_CAMERA := 3.0      ## [E] ohne Kameraanimation: Sequenzskripte untätig so lange → Ende
var _cut_idle := 0.0
var _cut_cam_used := false
var cutscene_end_reason := ""   ## Diagnose/Tests: "script" (CSC_EndCutscene), "camera", "scripts_idle", "fallback", "skip"


## O-008: Sequenz endet, wenn keine Kameraanimation mehr läuft und alle OnCutscene-Abläufe fertig (ended, ohne Warten)
## sind. Wartende/blockierte Skripte (Delay, HUMAN_Move …) halten die Sequenz offen → CSC_EndCutscene bleibt maßgeblich.
func _cutscene_auto_end(delta: float) -> void:
	var cs: Dictionary = anim.camera_state()
	if int(cs["active"]) > 0:
		_cut_cam_used = true
		_cut_idle = 0.0
		return
	# auch das aufrufende Skript (CSC_RunCutscene) zählt: viele Sequenzen laufen direkt in ihm weiter
	for v in _cutscene_vms + ([_cutscene_vm] if _cutscene_vm else []):
		var lv := v as LsVM
		if lv and not lv.terminated and (not lv.ended or lv.wait > 0.0 or lv.wait_until.is_valid() or not lv.events.is_empty()):
			_cut_idle = 0.0
			return
	_cut_idle += delta
	if _cut_idle >= (CUT_IDLE_AFTER_CAMERA if _cut_cam_used else CUT_IDLE_NO_CAMERA):
		cutscene_end_reason = "camera" if _cut_cam_used else "scripts_idle"
		end_cutscene()


func _ready() -> void:
	anim.name = "LsAnim"
	add_child(anim)
	_cut_cam = Camera3D.new()
	_cut_cam.far = maxf(3000.0, preload("res://src/world/view_distance.gd").camera_far())   # B-041
	add_child(_cut_cam)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_skip_label = Label.new()
	_skip_label.text = "Leertaste: Zwischensequenz überspringen"
	_skip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_skip_label.position = Vector2(20, 20)
	_skip_label.visible = false
	layer.add_child(_skip_label)


func run_cutscene(n: int, vm: LsVM) -> void:
	in_cutscene = true
	cutscene_id = n
	# B-028/O-008: Sequenzen ohne CSC_EndCutscene (z. B. CZECH1 cuttrebissky) enden mit ihrer Kameraanimation
	# (ls_anim, Länge = letztes Bild / 25) bzw. mit dem Ende ihrer Skriptabläufe (_cutscene_auto_end, [E]);
	# 90 s bleiben nur als Rückfall
	var my_n := n
	_cut_idle = 0.0
	_cut_cam_used = false
	cutscene_end_reason = ""
	get_tree().create_timer(CUTSCENE_FALLBACK_S, false).timeout.connect(func():
		if in_cutscene and cutscene_id == my_n:
			cutscene_end_reason = "fallback"
			end_cutscene())
	_cutscene_vm = vm
	mission.controller.input_enabled = false
	if mission.hud:
		mission.hud.visible = false
	_skip_label.visible = true
	_cutscene_vms.clear()
	for v in vms:
		if v.fire("ONCUTSCENE:%d" % n):
			_cutscene_vms.append(v)
	if auto_skip:
		end_cutscene.call_deferred()


## B-049/AP-49a: Fake-Cutscene ein/aus (NORMANDY2 Endsequenz). Ein: Steuerung gesperrt, HUD aus, FRM_SetActiveCamera
## wirkt; aus: Spielkamera/HUD/Steuerung zurück (Skript ruft vorher SetPlayerInput(true), FRM_SetActiveCamera(K0)).
func set_fake_cutscene(on: bool) -> void:
	fake_cutscene = on
	if mission == null:
		return
	if mission.controller:
		mission.controller.input_enabled = not on
	if in_cutscene:
		return      # echte Sequenz behält Kamera/HUD
	if mission.hud:
		mission.hud.visible = not on
	if not on:
		_cam_frame = null
		_cam_target = null
		if mission.get("rig") and mission.rig.camera:
			mission.rig.camera.current = true


## Skript führt die Kamera (echte oder Fake-Cutscene)
func script_camera_active() -> bool:
	return in_cutscene or fake_cutscene


func end_cutscene() -> void:
	if not in_cutscene:
		return
	in_cutscene = false
	_cam_frame = null
	_cam_target = null
	# Überspringen: Sequenzabläufe (OnCutscene(n)) im Schnelldurchlauf zu Ende führen statt abzubrechen – sie enthalten
	# oft Spielzustand (CZECH2 cut2.scr: SendSignal(obj, 1) = „Freiberg ergriffen“); Wartezeiten entfallen
	var key := "ONCUTSCENE:%d" % cutscene_id
	for vv in _cutscene_vms:
		var v := vv as LsVM
		if v == null or not is_instance_valid(v.me) or v.terminated:
			continue
		var qi: int = v.events.find(key)
		if qi >= 0:
			v.events.remove_at(qi)
			v._enter(v.code.handlers[key])
		for i in 400:
			v.wait = 0.0
			v.wait_until = Callable()
			if v.ended or not v.events.is_empty():
				break
			v._run()
		v.atomic = false
	_cutscene_vms.clear()
	for v in vms:
		v.fire("ONCUTSCENEDONE:%d" % cutscene_id)
	mission.controller.input_enabled = true
	if mission.hud:
		mission.hud.visible = true
	mission.rig.camera.current = true
	_skip_label.visible = false
	# nach dem Schnelldurchlauf (Überspringen) Blende in jedem Fall öffnen: eine im Schnelldurchlauf gestartete lange
	# Abblende (ARCTIC1: CSC_FadeOut(2000) vor CSC_EndCutscene) würde sonst als letzte enden → schwarzer Bildschirm
	_fade_to(0.0, 0.4)


var _fade_tw: Tween


## Blende auf Deckkraft a in secs Sekunden; ersetzt eine laufende Blende (nur eine gleichzeitig, sonst gewinnt die
## zuletzt endende – überlappende Tweens auf derselben Eigenschaft)
func _fade_to(a: float, secs: float) -> void:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade, "color:a", a, maxf(secs, 0.001))


func _process(_delta: float) -> void:
	if in_cutscene and not auto_skip:
		_cutscene_auto_end(_delta)
	if script_camera_active() and is_instance_valid(_cam_frame):
		_cut_cam.global_transform = _cam_frame.global_transform
		if fake_cutscene and not _cut_cam.current:
			_cut_cam.current = true
	if in_cutscene and is_instance_valid(_cam_target):
		_cut_cam.look_at(_cam_target.global_position, Vector3.UP)
	if _snow and mission.rig and mission.rig.camera:
		var cam := _cut_cam if in_cutscene or (fake_cutscene and is_instance_valid(_cam_frame)) else mission.rig.camera
		_snow.global_position = cam.global_position + Vector3.UP * 8.0


func _unhandled_input(event: InputEvent) -> void:
	if in_cutscene and (event.is_action_pressed("stance_stand") or event.is_action_pressed("pause")):
		cutscene_end_reason = "skip"
		end_cutscene()
		get_viewport().set_input_as_handled()


## Niederschlag (Original: WEATHER_SetOn / WEATHER_SetMode). Modus 0 = Regen (Standard, BURMA1 bu1_dazd.scr
## „dazd“ = déšť, ohne SetMode), 1 = Schnee (ARCTIC1 SetMode(1)). Früher immer Schnee → weiße Punkte im Dschungel.
## Einheiten [E]: Speed mm/s (Kommentar r_arc1a_pocasi „1200 == 1.2 m/s“), Size 0,1 mm (Länge, Breite), ColorIn RGBA.
var weather := {"mode": 0, "count": 2000.0, "speed": 20000.0, "size": Vector2(1200, 40),
	"color": Color8(37, 37, 37, 128), "on": false,
	# B-035: WEATHER_SetDir (Richtung, Länge egal), SetSpace (waagrecht, senkrecht in m), SetColorOut (Endfarbe)
	"dir": Vector3(0, -1, 0), "space": Vector2(0, 0), "color_out": Color(0, 0, 0, -1)}
var _weather_mode_built := -1
var _rain_count0 := 0.0


func _set_snow(on: bool) -> void:
	weather.on = on
	_apply_weather()


func _apply_weather() -> void:
	if not weather.on and _snow == null:
		return
	if _snow and _weather_mode_built != int(weather.mode):
		_snow.queue_free()
		_snow = null
	if weather.mode == 0:
		_apply_rain()
	else:
		_apply_snow_mode()
	if _snow:
		_apply_weather_extras()
		_snow.emitting = weather.on


## B-035: Richtung, Volumen und Endfarbe (WEATHER_SetDir/SetSpace/SetColorOut) auf den Niederschlag anwenden
func _apply_weather_extras() -> void:
	var pm := _snow.process_material as ParticleProcessMaterial
	if pm == null:
		return
	var d: Vector3 = weather.dir
	if d.length() > 0.001:
		pm.direction = d.normalized()
		if weather.mode != 0:
			pm.gravity = d.normalized() * 2.0       # Schnee treibt in Windrichtung
	var sp: Vector2 = weather.space
	if sp.x > 0.0:
		pm.emission_box_extents = Vector3(sp.x, maxf(sp.y * 0.1, 1.0), sp.x)
		_snow.visibility_aabb = AABB(Vector3(-sp.x - 10, -sp.y - 10, -sp.x - 10), Vector3(sp.x * 2 + 20, sp.y * 2 + 20, sp.x * 2 + 20))
	var co: Color = weather.color_out
	if co.a >= 0.0:
		var c0: Color = weather.color if weather.mode == 0 else Color(0.95, 0.97, 1.0, 0.8)
		var g := Gradient.new()
		g.set_color(0, Color(c0.r, c0.g, c0.b, 1.0))
		g.set_color(1, Color(co.r, co.g, co.b, co.a))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		var dp = _snow.draw_pass_1
		if dp and dp.surface_get_material(0) is StandardMaterial3D:
			(dp.surface_get_material(0) as StandardMaterial3D).vertex_color_use_as_albedo = true


func _apply_rain() -> void:
	var spd := clampf(float(weather.speed) / 1000.0, 2.0, 40.0)
	if _snow == null:
		_snow = GPUParticles3D.new()
		_snow.name = "Rain"
		_rain_count0 = clampf(float(weather.count), 100.0, 6000.0)
		_snow.amount = int(_rain_count0)
		_snow.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(22, 2, 22)
		pm.direction = Vector3.DOWN
		pm.spread = 3.0
		pm.gravity = Vector3.ZERO
		pm.particle_flag_align_y = true        # Tropfen als Striche in Fallrichtung
		_snow.process_material = pm
		var bm := BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material = m
		_snow.draw_pass_1 = bm
		add_child(_snow)
		_weather_mode_built = 0
	var pm2 := _snow.process_material as ParticleProcessMaterial
	pm2.initial_velocity_min = spd * 0.9
	pm2.initial_velocity_max = spd * 1.1
	_snow.lifetime = clampf(22.0 / spd, 0.5, 4.0)
	_snow.amount_ratio = clampf(float(weather.count) / maxf(_rain_count0, 1.0), 0.0, 1.0) * weather_quality_factor()
	var bm2 := _snow.draw_pass_1 as BoxMesh
	var sz: Vector2 = weather.size
	bm2.size = Vector3(clampf(sz.y * 1e-4, 0.002, 0.02), clampf(sz.x * 1e-4, 0.03, 0.5), clampf(sz.y * 1e-4, 0.002, 0.02))
	var c: Color = weather.color
	# Original-Regenfarbe (dunkelgrau, halbtransparent), leicht aufgehellt, damit Striche vor Laub erkennbar bleiben
	(bm2.material as StandardMaterial3D).albedo_color = Color(minf(c.r * 1.8, 1.0), minf(c.g * 1.8, 1.0), minf(c.b * 1.8, 1.0), clampf(c.a, 0.15, 0.6))


func _apply_snow_mode() -> void:
	if _snow == null:
		_snow = GPUParticles3D.new()
		_snow.amount = 3000
		_snow.lifetime = 4.0
		_snow.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(30, 2, 30)
		pm.direction = Vector3(0.4, -1, 0.2)
		pm.spread = 15.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(1.5, -2.0, 0.5)   # starker Wind
		_snow.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.material = m
		_snow.draw_pass_1 = q
		add_child(_snow)
		_weather_mode_built = 1
	_snow.amount_ratio = weather_quality_factor()


## B-040: Wetterpartikel je Grafikstufe 0–4 (Settings.quality): 0,4 / 0,6 / 1 / 1 / 1
const WEATHER_QUALITY_FACTOR := [0.4, 0.6, 1.0, 1.0, 1.0]


static func weather_quality_factor() -> float:
	return WEATHER_QUALITY_FACTOR[clampi(Settings.quality, 0, 4)]


## Engine-Ereignisse an das Skript des Akteurs weiterreichen.
func notify(n: Node, key: String) -> void:
	var vm: LsVM = vm_of.get(n)
	if vm:
		vm.fire(key)


# --- Spielstand (B-030/AP-1, GO-001) --------------------------------------------------------
# Original: Speicherroutine für den Skriptzustand nicht dekodiert (GAP_REA §1, [P] binärer Strom wie die Akteure).
# Nachbau [E]: funktional gleichwertig – Skripte setzen exakt an der gespeicherten Stelle fort.
const SAVE_VERSION := 1
const BRAIN_SCRIPT_PROPS := ["ai_mode", "script_control", "zombie_mode", "suspended", "script_alarm_enabled",
	"script_stance", "script_move_mode", "alarm_mask", "events_enabled", "last_alarm_type", "wait_for_player",
	"wait_stop_dist", "wait_resume_dist", "home_pos", "home_yaw", "stationary", "enabled", "look_around"]
const DOG_PROPS := ["suspended", "aggressive", "run_mode", "sight_range", "hear_range", "health", "alarmed",
	"attacking", "attack_any", "move_target", "lying", "owner_frame"]
var _rev := {}     ## Spielstand: Node -> ["$a"|"$w", Name] (nur während save_state)


## Skriptwert → JSON (Frames als Akteur-/Wegpunktname bzw. Pfad, Fließkommazahlen markiert, damit Ganzzahlen nach
## dem JSON-Rundweg wieder Ganzzahlen sind).
func save_value(v):
	match typeof(v):
		TYPE_OBJECT:
			if not is_instance_valid(v) or not (v is Node):
				return null
			if _rev.has(v):
				return {_rev[v][0]: _rev[v][1]}
			if mission and (v as Node).is_inside_tree() and mission.is_ancestor_of(v):
				return {"$p": String(mission.get_path_to(v))}
			return null
		TYPE_FLOAT:
			return {"$r": v} if is_finite(v) else {"$r": null, "$inf": signf(v) if not is_nan(v) else 0.0}
		TYPE_VECTOR3:
			var a: Array = []
			for i in 3:
				a.append(v[i] if is_finite(v[i]) else null)
			return {"$v3": a}
		TYPE_VECTOR2:
			return {"$v2": [v.x, v.y]}
		TYPE_COLOR:
			return {"$c": [v.r, v.g, v.b, v.a]}
		TYPE_ARRAY:
			return (v as Array).map(save_value)
		TYPE_PACKED_VECTOR3_ARRAY:
			return {"$pv3": Array(v).map(save_value)}
		TYPE_DICTIONARY:
			var out: Array = []
			for k in v:
				out.append([save_value(k), save_value(v[k])])
			return {"$d": out}
		TYPE_STRING_NAME:
			return String(v)
	return v


func load_value(v):
	if v is Dictionary:
		if v.has("$a"):
			return actors.get(String(v["$a"]))
		if v.has("$w"):
			return waypoints.get(String(v["$w"]))
		if v.has("$p"):
			return mission.get_node_or_null(NodePath(String(v["$p"]))) if mission else null
		if v.has("$r"):
			if v["$r"] == null:
				var s := float(v.get("$inf", 0.0))
				return INF * s if s != 0.0 else NAN
			return float(v["$r"])
		if v.has("$v3"):
			var a: Array = v["$v3"]
			return Vector3(INF if a[0] == null else float(a[0]), INF if a[1] == null else float(a[1]), INF if a[2] == null else float(a[2]))
		if v.has("$v2"):
			return Vector2(float(v["$v2"][0]), float(v["$v2"][1]))
		if v.has("$c"):
			var c: Array = v["$c"]
			return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		if v.has("$pv3"):
			return PackedVector3Array((v["$pv3"] as Array).map(load_value))
		if v.has("$d"):
			var d := {}
			for kv in v["$d"]:
				d[load_value(kv[0])] = load_value(kv[1])
			return d
		return v
	if v is float:
		return int(v) if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15 else v
	if v is Array:
		return (v as Array).map(load_value)
	return v


func _save_props(o: Object, names: Array) -> Dictionary:
	var d := {}
	for p in names:
		if p in o:
			d[p] = save_value(o.get(p))
	return d


func _load_props(o: Object, d: Dictionary) -> void:
	for p in d:
		if p in o:
			var val = load_value(d[p])
			var cur = o.get(p)
			if cur is float and val is int:
				val = float(val)
			elif cur is bool and not (val is bool):
				val = LsVM._truthy(val)
			if typeof(cur) == TYPE_OBJECT or cur == null or typeof(val) == typeof(cur):
				o.set(p, val)


## Zustand der Skriptlaufzeit für den Spielstand (OrigMission._serialize_extra → "orig_vm").
func save_state() -> Dictionary:
	_rev.clear()
	for k in actors:
		var n = actors[k]
		if is_instance_valid(n) and not _rev.has(n):
			_rev[n] = ["$a", k]
	for k in waypoints:
		if is_instance_valid(waypoints[k]) and not _rev.has(waypoints[k]):
			_rev[waypoints[k]] = ["$w", k]
	var vl: Array = []
	var idx := {}
	var frames := {}       # vom Skript benutzte Frames (Sichtbarkeit, FRM_SetOn)
	for vm in vms:
		if not is_instance_valid(vm.me):
			continue
		idx[vm] = vl.size()
		vl.append({"owner": save_value(vm.me), "state": vm.save_state(save_value)})
		for k in vm.vars:
			var fv = vm.vars[k]
			if typeof(fv) == TYPE_OBJECT and is_instance_valid(fv) and fv is Node3D:
				frames[fv] = true
	var gv: Array = []
	for k in game_values:
		gv.append([save_value(k), save_value(game_values[k])])
	var cut_vms: Array = []
	for v in _cutscene_vms:
		if idx.has(v):
			cut_vms.append(idx[v])
	var forms: Array = []
	for lead in formations:
		if is_instance_valid(lead):
			var f: Dictionary = formations[lead]
			forms.append({"lead": save_value(lead), "members": (f["members"] as Array).map(save_value),
				"type": String(f["type"]), "scale": float(f["scale"])})
	# Darsteller aus CSC_DuplicateHuman
	var dups: Array = []
	if mission and mission.dynamic_root:
		for c in mission.dynamic_root.get_children():
			if c.has_meta("csc_duplicate") and c is Node3D:
				var t: Transform3D = (c as Node3D).global_transform
				dups.append({"name": String(c.get_meta("csc_duplicate")), "node": String(c.name),
					"pos": save_value(t.origin), "yaw": t.basis.get_euler().y, "visible": (c as Node3D).visible})
	# Akteure: Seite, Skript-KI-Felder, Begleiter, Hunde, Fahrzeuge, NPCs außerhalb von mission.enemies
	var act := {}
	var seen := {}
	for k in actors:
		var n = actors[k]
		if not is_instance_valid(n) or seen.has(n) or not (n is Node3D):
			continue
		seen[n] = true
		frames[n] = true
		var e := {}
		if n is Soldier:
			var s := n as Soldier
			if mission.squad and mission.squad.members.has(s):
				continue
			e["team"] = s.team
			if not mission.enemies.has(s):
				e["soldier"] = s.serialize()
			var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
			if b:
				if not mission.enemies.has(s):
					e["brain"] = b.serialize()
				e["script"] = _save_props(b, BRAIN_SCRIPT_PROPS)
			var esc := s.get_node_or_null("EscortBrain")
			e["escort"] = esc != null and not esc.is_queued_for_deletion()
		elif n is Dog:
			var dg := n as Dog
			e["dog"] = _save_props(dg, DOG_PROPS)
			e["alive"] = dg.alive
			e["pos"] = save_value(dg.global_position)
			e["yaw"] = dg.rotation.y
		elif n is Vehicle and "fuel" in n:
			e["fuel"] = float(n.fuel)
		if not e.is_empty():
			act[String(k)] = e
	var vis: Array = []
	for f in frames:
		var key = save_value(f)
		if key != null:
			vis.append([key, (f as Node3D).visible])
	var out := {
		"version": SAVE_VERSION, "vms": vl, "game_values": gv,
		"cutscene": {"on": in_cutscene, "id": cutscene_id, "vms": cut_vms, "fake": fake_cutscene},
		"formations": forms, "dups": dups, "actors": act, "visible": vis,
		"weather": {"mode": int(weather.mode), "count": float(weather.count), "speed": float(weather.speed),
			"size": save_value(weather.size), "color": save_value(weather.color), "on": bool(weather.on)},
		"thunder": {"on": _thunder_on, "light": save_value(_thunder_light)},
		"timer": _timer_left, "no_team_damage": no_team_damage,
		"input": mission.controller.input_enabled if mission and mission.controller else true,
	}
	# Checkpoint-Kantenliste (CheckpointJoin/Separate, AP-5; Original speichert sie mit, 0x4147D0-Umfeld): Haken, sobald
	# AP-5 ein Objekt `checkpoints` mit save_state()/load_state(d) anlegt
	var cp = get("checkpoints")
	if cp is Object and cp.has_method("save_state"):
		out["checkpoints"] = cp.save_state()
	# B-033: HUMAN_SetIgnoreCircumventionFlag (Original speichert +0x11C mit, 0x577440)
	var icf: Array = []
	for n in get_tree().get_nodes_in_group("soldiers"):
		var icb := (n as Node).get_node_or_null("EnemyBrain") as AIBrain
		if icb and icb.ignore_circumvention:
			icf.append(save_value(n))
	if not icf.is_empty():
		out["ignore_circumvention"] = icf
	_rev.clear()
	return out


## Spielstand anwenden (nach Mission.deserialize der Akteure, vor dem ersten Skripttakt). Liefert Hinweise/Warnungen.
func load_state(d: Dictionary) -> Array:
	var notes: Array = []
	game_values.clear()
	for kv in d.get("game_values", []):
		game_values[load_value(kv[0])] = load_value(kv[1])
	# Darsteller zuerst (Skriptvariablen verweisen über den Namen darauf)
	for dd in d.get("dups", []):
		var dup := Node3D.new()
		dup.name = String(dd.get("node", "CSC_dup")).validate_node_name()
		mission.dynamic_root.add_child(dup)
		var p = load_value(dd.get("pos"))
		if p is Vector3 and p.is_finite():
			dup.global_position = p
		dup.rotation.y = float(dd.get("yaw", 0.0))
		dup.visible = bool(dd.get("visible", true))
		dup.set_meta("csc_duplicate", String(dd.get("name", "")))
		var src: Node3D = actors.get(String(dd.get("name", "")).to_upper())
		if String(dd.get("name", "")) != "" and dup.name.begins_with("CSC_"):
			register_actor(String(dd["name"]), dup)
		if src and src is Soldier and (src as Soldier).model and (src as Soldier).model.get("orig_figure") != null \
				and is_instance_valid((src as Soldier).model.orig_figure):
			dup.add_child(((src as Soldier).model.orig_figure as Node3D).duplicate())
	# Akteure
	var act: Dictionary = d.get("actors", {})
	for k in act:
		var n = actors.get(String(k))
		var e: Dictionary = act[k]
		if not is_instance_valid(n):
			continue
		if n is Soldier:
			var s := n as Soldier
			if e.has("soldier"):
				s.deserialize(e["soldier"])
			var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
			if b and e.has("brain"):
				b.deserialize(e["brain"])
			var team := int(e.get("team", s.team))
			if team != s.team:
				s.remove_from_group("team_%d" % s.team)
				s.team = team
				if s.alive:
					s.add_to_group("team_%d" % s.team)
			if b and e.has("script"):
				_load_props(b, e["script"])
				b.set_physics_process(bool(b.get("enabled")) if "enabled" in b else true)
			var esc: EscortBrain = s.get_node_or_null("EscortBrain")
			if bool(e.get("escort", false)) and esc == null and s.alive:
				# wie SETNPCTEAMSTATUS(join): Begleit-KI
				if b:
					b.enabled = false
					b.set_physics_process(false)
				esc = EscortBrain.new()
				esc.name = "EscortBrain"
				esc.squad = mission.squad
				s.add_child(esc)
				esc.setup(s)
				esc.released = true
			elif not bool(e.get("escort", false)) and esc:
				esc.queue_free()
		elif n is Dog:
			var dg := n as Dog
			_load_props(dg, e.get("dog", {}))
			var dp = load_value(e.get("pos"))
			if dp is Vector3 and dp.is_finite():
				dg.global_position = dp
			dg.rotation.y = float(e.get("yaw", dg.rotation.y))
			if not bool(e.get("alive", true)) and dg.alive:
				dg.die()
		elif n is Vehicle and e.has("fuel") and "fuel" in n:
			n.fuel = float(e["fuel"])
	# Skript-VMs
	var restored := {}
	var missing := 0
	for ve in d.get("vms", []):
		var ow0 = load_value(ve.get("owner"))
		var st: Dictionary = ve.get("state", {})
		if not (ow0 is Node3D):
			missing += 1
			continue
		var vm: LsVM = vm_of.get(ow0)
		var sname := String(st.get("script", ""))
		if vm == null or (sname != "" and vm.name != sname):
			vm = attach_script(ow0, sname)     # ScriptAssign während des Spiels
			if vm == null:
				missing += 1
				continue
		vm.load_state(st, load_value)
		restored[vm] = true
	var stale := 0
	for vm in vms:
		if not restored.has(vm):
			# Skript ohne gespeicherten Gegenpart: nicht von vorn beginnen lassen (würde Abläufe doppelt auslösen)
			vm._started = true
			vm.ended = true
			vm.terminated = true
			vm.events.clear()
			stale += 1
	if missing > 0 or stale > 0:
		notes.append("Skriptzustand: %d gespeicherte Skripte ohne Objekt, %d Skripte ohne Spielstand angehalten" % [missing, stale])
	# Formationen, Wetter, Gewitter, Zeitgeber
	formations.clear()
	for f in d.get("formations", []):
		var lead = load_value(f.get("lead"))
		if lead is Node3D:
			formations[lead] = {"members": (f.get("members", []) as Array).map(load_value).filter(func(x): return x is Node3D),
				"type": String(f.get("type", "line")), "scale": float(f.get("scale", 3.0))}
	var w: Dictionary = d.get("weather", {})
	if not w.is_empty():
		weather.mode = int(w.get("mode", 0))
		weather.count = float(w.get("count", weather.count))
		weather.speed = float(w.get("speed", weather.speed))
		var ws = load_value(w.get("size"))
		if ws is Vector2:
			weather.size = ws
		var wc = load_value(w.get("color"))
		if wc is Color:
			weather.color = wc
		weather.on = bool(w.get("on", false))
		_apply_weather()
	var th: Dictionary = d.get("thunder", {})
	_thunder_on = bool(th.get("on", false))
	var tl = load_value(th.get("light"))
	_thunder_light = tl if tl is Node3D else null
	var tleft := float(d.get("timer", -1.0))
	if tleft >= 0.0:
		_set_interface_timer(tleft)
	no_team_damage = bool(d.get("no_team_damage", false))
	var cp = get("checkpoints")
	if d.has("checkpoints") and cp is Object and cp.has_method("load_state"):
		cp.load_state(d["checkpoints"])
	for icv in d.get("ignore_circumvention", []):
		var icn = load_value(icv)
		var icb: AIBrain = (icn as Node).get_node_or_null("EnemyBrain") as AIBrain if icn is Node else null
		if icb:
			icb.ignore_circumvention = true
	for fv in d.get("visible", []):
		var fn = load_value(fv[0])
		if fn is Node3D:
			(fn as Node3D).visible = bool(fv[1])
	if mission and mission.controller:
		mission.controller.input_enabled = bool(d.get("input", true))
	# Laufende Zwischensequenz: Zustand herstellen und wie per Leertaste überspringen – die OnCutscene-Abläufe laufen
	# im Schnelldurchlauf zu Ende (Spielzustand wie bei „Überspringen“), Kamera/Blende sind danach wieder beim Spieler
	var cut: Dictionary = d.get("cutscene", {})
	# B-049: laufende Fake-Cutscene wiederherstellen; das Skript läuft weiter und schaltet die Kamera selbst (K1/K2 → K0)
	if bool(cut.get("fake", false)):
		set_fake_cutscene(true)
	if bool(cut.get("on", false)):
		in_cutscene = true
		cutscene_id = int(cut.get("id", 0))
		_cutscene_vms.clear()
		var vl: Array = d.get("vms", [])
		for i in cut.get("vms", []):
			var ow = load_value(vl[int(i)].get("owner")) if int(i) < vl.size() else null
			if ow and vm_of.has(ow):
				_cutscene_vms.append(vm_of[ow])
		if mission.controller:
			mission.controller.input_enabled = false
		end_cutscene.call_deferred()
		notes.append("Zwischensequenz %d beim Laden übersprungen" % cutscene_id)
	return notes
