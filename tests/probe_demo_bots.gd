extends Node
## Manuelle Sonde (nur auf Anweisung, nie in run_tests): tritt einem Internet-Server bei und beobachtet KI-Soldaten
## (Bewegung, Gesundheit, Treffer auf den Client, Bestätigung eigener Treffer). Build-Schlüssel nur im Speicher.
##   tools\godot.cmd --headless -- --autoplay=probe_demo_bots --key=<pfad> --host=<ip:port> [--secs=150]

var hits := 0
var bact := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _arg(n: String, d := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % n):
			return a.get_slice("=", 1)
	return d


func _bots() -> Array:
	var out: Array = []
	for k in Net._soldiers:
		var s = Net._soldiers[k]
		if int(k) < 0 and is_instance_valid(s):
			out.append(s)
	return out


func _run() -> void:
	var M := get_node("/root/Master")
	var k := CryptoKey.new()
	if k.load_from_string(FileAccess.get_file_as_string(_arg("key")), false) != OK:
		print("PROBE: kein Schlüssel")
		get_tree().quit(1)
		return
	M.set_build_key(k)
	var ok: bool = await M.refresh_servers()
	print("PROBE: Liste ok=", ok, " Server=", M.list.size())
	for e in M.list:
		print("PROBE:  ", e.get("name"), " ", e.get("host"), ":", e.get("port"))
	Net.hit_confirmed.connect(func(i): hits += 1; print("PROBE: TREFFER bestätigt ", i))
	Net.local_name = "Sonde"
	var host := _arg("host", "")
	if host == "":
		print("PROBE: --host=<adresse:port> fehlt")
		get_tree().quit(1)
		return
	Net.join(host)
	var t0 := Time.get_ticks_msec()
	while Game.current_mission() == null and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(1.0).timeout
	print("PROBE: Karte ", Game.current_mission_id, " setup_pending=", Net.setup_pending, " err=", Net.last_error)
	await get_tree().create_timer(3.0).timeout
	print("PROBE: players ", Net.players)
	if Net.setup_pending:
		Net.confirm_setup()
	var secs := int(_arg("secs", "150"))
	var last := {}
	var hp_me := -1.0
	for i in secs:
		await get_tree().create_timer(1.0).timeout
		var me = Net._soldiers.get(Net.my_id())
		var line := "PROBE t=%d me=%s" % [i, ("%.0f@%s prot=%s" % [me.health, me.global_position.round(), Net.spawn_protected(me)]) if is_instance_valid(me) and me.alive else "-"]
		for b in _bots():
			var mv: float = b.global_position.distance_to(last.get(b.name, b.global_position))
			last[b.name] = b.global_position
			line += " | %s t%d hp%.0f mv%.1f y%.1f st%d w%s" % [String(b.name).right(6), b.team, b.health, mv, b.global_position.y, b.stance, b.current_weapon().data.id if b.current_weapon() else "-"]
		line += " | hurt=%d hits=%d" % [Net.hurt_log.size(), hits]
		print(line)
		if is_instance_valid(me) and me.alive:
			# nächsten gegnerischen Bot in Sicht beschießen
			var best = null
			var bd := 1e9
			for b in _bots():
				if b.alive and b.team != me.team:
					var d: float = b.global_position.distance_to(me.global_position)
					var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3(0, 1.5, 0), b.global_position + Vector3(0, 1.2, 0), 1)
					if d < bd and me.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
						bd = d
						best = b
			if best and bd < 80.0:
				var dd: Vector3 = best.global_position + Vector3(0, 1.2, 0) - (me.global_position + Vector3(0, 1.5, 0))
				me.look_yaw = atan2(-dd.x, -dd.z)
				me.look_pitch = atan2(dd.y, Vector2(dd.x, dd.z).length())
				me.aiming = true
				for j in 6:
					me.trigger = not me.trigger
					await get_tree().physics_frame
					await get_tree().physics_frame
				me.trigger = false
	print("PROBE: Ende rejects/log: ", Net.auth.log_lines.slice(-10))
	Net.leave(false)
	M.set_build_key(null)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)
