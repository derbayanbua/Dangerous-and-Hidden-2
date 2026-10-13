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
var vms: Array[LsVM] = []
var vm_of := {}                ## Node -> LsVM
var game_values := {}          ## SaveGameValue / _LoadGameValue
var subtitles_on := false
var unimplemented := {}
var calls := {}                ## Statistik: Befehl -> Anzahl
var log_calls := false
var objective_map := {}        ## Original-Index -> Objective-ID
var extras: OrigExtras         ## Lichter, Klangquellen, Spuren, Musik (extra.json)


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
	texts = _read_json(OrigLevel.cache_root() + "/texts_german.json")


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
func start_scripts() -> int:
	var data = _read_json(orig.mission_dir + "/scene.json")
	var mapping: Dictionary = data.get("scripts", {})
	var n := 0
	for obj in mapping:
		var owner := find_frame(obj)
		if owner == null:
			owner = Node3D.new()
			owner.name = String(obj).validate_node_name()
			orig.root.add_child(owner)
			register_actor(obj, owner)   # damit FRM_FindFrame es findet
		if attach_script(owner, String(mapping[obj]).to_lower()):
			n += 1
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
	_formation_t -= delta
	if _formation_t <= 0.0:
		_formation_t = 0.5
		_update_formations()


var formations := {}            ## Anführer -> {members, type, scale} (FORMATION_*)
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
		"FRM_TELEPORTNEARFRAME", "FRM_TELEPORTNEARFRAMEBACK":
			var who := _frame_arg(vm, args[0])
			var to := _frame_arg(vm, args[1])
			if who and to:
				who.global_position = to.global_position
			return null
		"SCRIPTASSIGN":
			var sf2 := _frame_arg(vm, args[0])
			var sn := _str(vm.value(args[1])).to_lower()
			if not sn.ends_with(".scr"):
				sn += ".scr"
			if sf2:
				attach_script(sf2, sn)
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
			var r := float(vm.value(args[0]))
			for p in _players():
				if p.global_position.distance_to(_pos(vm.me)) <= r:
					return 1
			return 0
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
			return 1           # Einzelspieler, normale Kampagne
		"_RANDOMINT":
			return randi_range(0, maxi(int(vm.value(args[0])) - 1, 0))
		"_LOADGAMEVALUE":
			return game_values.get(int(vm.value(args[0])), 0)
		"SAVEGAMEVALUE":
			game_values[int(vm.value(args[0]))] = vm.value(args[1])
			return null
		"_GETALARMTYPE":
			return 1
		"_ACTOR_GETSTATE":
			# Original: Menschen 1 = lebt, 0 = tot; andere Objekte: per SetActorState gesetzter Zustand
			var af := _frame_arg(vm, args[0])
			if af is Soldier:
				return 1 if (af as Soldier).alive else 0
			return int(af.get_meta("actor_state", 1)) if af else 0
		"SETACTORSTATE":
			var sf3 := _frame_arg(vm, args[0])
			if sf3 and args.size() > 1:
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
		"HINT_CLEARALL", "PRINTF", "PRINTFNUMBER", "ADDDIARYTEXT":
			return null
		"SETALARMTYPE":
			var b2 := _brain(vm)
			if b2:
				b2.script_alarm_enabled = LsVM._truthy(vm.value(args[1])) if args.size() > 1 else true
			return null
		"DISABLEALARMS":
			return null
		# --- Menschen (eigener Akteur) ---
		"HUMAN_SUSPEND":
			var b3 := _brain(vm)
			if b3:
				b3.suspended = LsVM._truthy(vm.value(args[0]))
			return null
		"HUMAN_MOVE":
			var b4 := _brain(vm)
			var tgt := _frame_arg(vm, args[0])
			if b4 and tgt:
				b4.script_move(tgt.global_position)
				return {"wait_until": b4.script_move_done, "timeout": 40.0}
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
		"HUMAN_KILL", "HUMAN_ATTACK", "HUMAN_KILLEX":
			var b11 := _brain(vm)
			var victim := _frame_arg(vm, args[0]) as Soldier
			if b11 and victim:
				b11.script_attack(victim)
			return null
		# --- Zwischensequenzen ---
		"CSC_RUNCUTSCENE":
			run_cutscene(int(vm.value(args[0])) if args.size() > 0 else 1, vm)
			return null
		"CSC_ENDCUTSCENE":
			end_cutscene()
			return null
		"FRM_SETACTIVECAMERA":
			var cf := _frame_arg(vm, args[0])
			if cf and in_cutscene:
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
				extras.play_table(int(vm.value(args[0])))
			return null
		"_ISININVENTORY":
			# Original-Gegenstände (items.dat) im Inventar: Inventarsystem für Originalgegenstände offen
			for p in _players():
				if (p as Soldier).get_meta("orig_items", []).has(int(vm.value(args[0]))):
					return 1
			return 0
		"_ISLANGUAGEVERSION":
			return 1 if _str(vm.value(args[0])).to_lower() == "german" else 0   # deutsche Originalfassung
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
		"SETWHENEVERTIME", "SETUPTACTICALMODE", "FRM_SETTARGET":
			return null    # Prüfintervall / Taktikmodus / Zielmarke: ohne sichtbare Wirkung
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
			var tw2 := create_tween()
			tw2.tween_property(_fade, "color:a", 1.0 if fname == "CSC_FADEOUT" else 0.0, ms / 1000.0)
			return null
		"WEATHER_SETON":
			_set_snow(LsVM._truthy(vm.value(args[0])))
			return null
		"WEATHER_SETMODE", "WEATHER_SETCOUNT", "WEATHER_SETSPEED", "WEATHER_SETDIR", "WEATHER_SETSIZE", \
				"WEATHER_SETSPACE", "WEATHER_SETCOLORIN", "WEATHER_SETCOLOROUT", "CSC_RUNCLOUDER", \
				"FRM_RESETANIMATION", "__SETUPAUTOLOGGING":
			return null
		# --- Sprache: Original-Aufnahme + Untertitel (Lippenbewegung: Platzhalter) ---
		"FRM_MORPHSPEECH", "FRM_MORPHSPEECHDELAYED":
			var spk := _frame_arg(vm, args[0])
			var dur := speak(spk, vm.value(args[1]))
			return {"wait": dur} if fname == "FRM_MORPHSPEECHDELAYED" else null
		"PLAYSOUND":
			if args.size() > 0:
				var v = vm.value(args[0])
				# 8-stellige Werte = Sprachaufnahmen; kleine Zahlen = Effektklänge der Soundtabelle (noch nicht zugeordnet)
				if (v is int or v is float) and int(v) >= 1000000:
					speak(vm.me, v)
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
				dg6.alarmed = true
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
			return _board(vm, _str(vm.value(args[0])) if args.size() > 0 else "")
		"HUMAN_DRIVE":
			var sd := _soldier(vm)
			var veh := sd.vehicle as Vehicle if sd else null
			if veh == null:
				return null
			var wp := _str(vm.value(args[0]))
			var kmh := float(vm.value(args[1])) if args.size() > 1 else 30.0
			if wp == "" or kmh <= 0.0:
				veh.stop_drive()
				return null
			var goal_f := find_frame(wp)
			# Original-Fahrspuren (Punkte "1","2","3","END") sind noch nicht dekodiert:
			# ersatzweise 60 m geradeaus in Fahrzeugrichtung.
			var goal := goal_f.global_position if goal_f else veh.global_position + veh.global_basis.z * 60.0
			veh.drive_to(goal, kmh)
			return {"wait_until": veh.drive_done, "timeout": 40.0}
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
			return null
		"HUMAN_DROPOBJECT":
			var ps3 := _soldier(vm)
			if ps3 and ps3.has_meta("carried"):
				var c: Node3D = ps3.get_meta("carried")
				ps3.remove_meta("carried")
				if is_instance_valid(c):
					c.reparent(mission.dynamic_root, true)
					c.global_position = _ground(c.global_position)
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
			var ef := _frame_arg(vm, args[0])
			if ef:
				_explosion(ef.global_position + Vector3.UP, 7.0, 220.0)
			return null
		"FRM_SETANIMATION", "HUMAN_SETANIM", "HUMAN_SETOPTIMIZED", "HUMAN_SETEVENTS", "HUMAN_LOOKAROUND", \
				"FRM_SWITCHFACETEXTURE", "FRM_SETLIGHTMAP", "FRM_SETGROUPLIGHTMAP", "CHECKPOINTJOIN", "CHECKPOINTSEPARATE":
			return null    # Animation/Gesicht/Beleuchtung: vorerst ohne Wirkung (Original-Animationen: offen)
		"HUMAN_ACTIVITY_SMOKE", "HUMAN_ACTIVITY_POINT", "HUMAN_ACTIVITY_SIT", "HUMAN_ACTIVITY_DRINKBOTTLE", \
				"HUMAN_ACTIVITY_COLD", "HUMAN_ACTIVITY_HAT", "HUMAN_ACTIVITY_CHECKWEAPON", "HUMAN_ACTIVITY_BINOCULARS", \
				"HUMAN_ACTIVITY_BINOCULARSEND":
			return {"wait": 2.0}  # Tätigkeitsanimation (Platzhalter: kurze Pause)
	if not unimplemented.has(fname):
		unimplemented[fname] = 0
	unimplemented[fname] += 1
	return null


var _voice_cache := {}


## Satz sprechen: Original-Aufnahme (orig_cache/sounds/<id>.wav) am Sprecher abspielen und
## Untertitel zeigen. Gibt die Dauer in Sekunden zurück (für FRM_MorphSpeechDelayed).
func speak(who: Node3D, id) -> float:
	var key := "%08d" % int(id)
	var t := text(id)
	var dur := clampf(t.length() * 0.07, 1.5, 8.0)
	var stream: AudioStreamWAV = _voice_cache.get(key)
	if stream == null:
		var path := OrigLevel.cache_root() + "/sounds/" + key + ".wav"
		if FileAccess.file_exists(path):
			stream = AudioStreamWAV.load_from_file(path)
			_voice_cache[key] = stream
	if stream:
		dur = stream.get_length()
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.unit_size = 6.0
		p.max_distance = 60.0
		if is_instance_valid(who):
			who.add_child(p)
		else:
			add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	if t != "" and Settings.subtitles:
		subtitle.emit(t, dur + 0.5)
		Events.say(t, dur + 0.5)
	return dur


## HUMAN_BoardVehicle: Fahrzeug (Vehicle) besteigen, MG-Stellung (Akteurtyp 21) besetzen;
## leerer Name = aussteigen bzw. Stellung verlassen.
func _board(vm: LsVM, target_name: String):
	var s := _soldier(vm)
	if s == null or not s.alive:
		return null
	var b := _brain(vm)
	if target_name == "":
		if s.vehicle is Vehicle:
			(s.vehicle as Vehicle).leave(s)
		if s.has_meta("mg_post"):
			s.remove_meta("mg_post")
		return null
	var t := find_frame(target_name)
	if t is Vehicle:
		var v := t as Vehicle
		if s.global_position.distance_to(v.global_position) > 12.0 and b:
			b.script_move(v.global_position + v.global_basis.x * 2.0)
			return {"wait_until": _board_wait.bind(s, v), "timeout": 20.0}
		_board_now(s, v)
		return null
	if t:
		# MG-Stellung: hinter die Waffe stellen und von dort sichern
		s.set_meta("mg_post", t)
		var behind := t.global_position - t.global_basis.z * 0.9
		if b:
			b.script_move(behind)
			b.script_stance = Soldier.Stance.CROUCH
			b.home_pos = behind
			return {"wait_until": b.script_move_done, "timeout": 20.0}
		s.global_position = behind
	return null


func _board_now(s: Soldier, v: Vehicle) -> bool:
	if s.vehicle == v:
		return true
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	if b:
		b.stop_moving()
	return v.board(s, true)


## Warten bis der Akteur am Fahrzeug ist (untypisiert: Argumente k?nnen inzwischen freigegeben sein)
func _board_wait(s, v) -> bool:
	if not is_instance_valid(s) or not is_instance_valid(v) or not s.alive:
		return true
	if s.global_position.distance_to(v.global_position) < 5.0:
		return _board_now(s, v) or true
	var b: EnemyBrain = s.get_node_or_null("EnemyBrain")
	return b == null or b.script_move_done()


func _ground(p: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 20.0, 1))
	return hit.position if not hit.is_empty() else p


## Original-Partikelsysteme (Index in die Partikeltabelle, Definitionen noch nicht dekodiert):
## Platzhalter Rauchsäule/Feuer, je nach Zweck des Original-Aufrufs.
func _particles(id: int, pos: Vector3) -> void:
	var fire := id in [43, 53]
	var gp := GPUParticles3D.new()
	gp.amount = 80 if fire else 40
	gp.lifetime = 3.0
	gp.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 16, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0.6, 0.4, 0.2)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.7) if id == 43 else Color(0.2, 0.2, 0.2, 0.45)
	q.material = m
	gp.draw_pass_1 = q
	mission.dynamic_root.add_child(gp)
	gp.global_position = pos
	if fire:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 10.0
		l.light_energy = 2.0
		gp.add_child(l)
	get_tree().create_timer(60.0).timeout.connect(gp.queue_free)


## MakeExplosion: Explosion mit Splitterschaden (Soldaten mit Sichtlinie, Hunde).
func _explosion(pos: Vector3, radius: float, damage: float) -> void:
	Effects.explosion(pos, radius)
	Events.emit_noise(pos, 400.0, null, Soldier.TEAM_AXIS, &"explosion")
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
		"HUMAN_SETAIMODE_DEFENSIVE":
			b.script_control = false
			b.ai_mode = EnemyBrain.Mode.DEFENSIVE
		"HUMAN_SETAIMODE_AGGRESSIVE":
			b.script_control = false
			b.ai_mode = EnemyBrain.Mode.AGGRESSIVE


# --- Zwischensequenzen (CSC_*) --------------------------------------------------------

var in_cutscene := false
var cutscene_id := 0
var _cutscene_vm: LsVM
var _cut_cam: Camera3D
var _cam_target: Node3D
var _cam_frame: Node3D           ## aktive Original-Kamera (kann einer Spur folgen)
var _fade: ColorRect
var _skip_label: Label
var _snow: GPUParticles3D
var auto_skip := false          ## Tests: Zwischensequenzen sofort überspringen


func _ready() -> void:
	_cut_cam = Camera3D.new()
	_cut_cam.far = 3000.0
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
	_cutscene_vm = vm
	mission.controller.input_enabled = false
	if mission.hud:
		mission.hud.visible = false
	_skip_label.visible = true
	for v in vms:
		v.fire("ONCUTSCENE:%d" % n)
	if auto_skip:
		end_cutscene.call_deferred()


func end_cutscene() -> void:
	if not in_cutscene:
		return
	in_cutscene = false
	_cam_frame = null
	_cam_target = null
	if _cutscene_vm and _cutscene_vm.code.handlers.has("ONCUTSCENE:%d" % cutscene_id):
		# laufenden Sequenzablauf abbrechen (Überspringen)
		_cutscene_vm.stack.clear()
		_cutscene_vm.ended = true
		_cutscene_vm.wait = 0.0
		_cutscene_vm.atomic = false
	for v in vms:
		v.fire("ONCUTSCENEDONE:%d" % cutscene_id)
	mission.controller.input_enabled = true
	if mission.hud:
		mission.hud.visible = true
	mission.rig.camera.current = true
	_skip_label.visible = false
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)


func _process(_delta: float) -> void:
	if in_cutscene and is_instance_valid(_cam_frame):
		_cut_cam.global_transform = _cam_frame.global_transform
	if in_cutscene and is_instance_valid(_cam_target):
		_cut_cam.look_at(_cam_target.global_position, Vector3.UP)
	if _snow and mission.rig and mission.rig.camera:
		var cam := _cut_cam if in_cutscene else mission.rig.camera
		_snow.global_position = cam.global_position + Vector3.UP * 8.0


func _unhandled_input(event: InputEvent) -> void:
	if in_cutscene and (event.is_action_pressed("stance_stand") or event.is_action_pressed("pause")):
		end_cutscene()
		get_viewport().set_input_as_handled()


## Schneefall (Original: WEATHER_SetOn / WEATHER_SetMode)
func _set_snow(on: bool) -> void:
	if on and _snow == null:
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
	if _snow:
		_snow.emitting = on


## Engine-Ereignisse an das Skript des Akteurs weiterreichen.
func notify(n: Node, key: String) -> void:
	var vm: LsVM = vm_of.get(n)
	if vm:
		vm.fire(key)
