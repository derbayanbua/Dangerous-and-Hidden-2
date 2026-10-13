class_name OrigExtras
extends Node
## Zusatzdaten einer Originalmission (orig_cache/<m>/extra.json, tools/fmt_mission_extra.py):
##   Lichter (scene2 0x4040)   -> OmniLight3D/SpotLight3D; Punktlichter zählen für die Sichtbarkeit
##   Klangquellen (sounds.bin) -> AudioStreamPlayer3D, per FRM_SetOn schaltbar
##   Spuren (tracks.dat)       -> FRM_WatchTrack (Kamerafahrten, Flugzeug im Intro)
##   Musik (IngameSounds.def)  -> Normal-/Action-Musik der Mission, PlayMusic/PlayCutsceneMusic
## Annahmen (nicht am Original verifiziert, siehe docs/re_notes_lights_tracks_sounds.md):
##   - Klangquellen ohne Loop werden in zufälligen Abständen erneut abgespielt.
##   - Action-Musik läuft nach einem Alarm; das Original-Auswahlverfahren ist unbekannt.
##   - Spurpunkte werden linear interpoliert.

const POINT_ENERGY := 1.6

var mission: Mission
var runtime: LsRuntime
var tracks := {}               ## Name (groß) -> Array der Schlüssel
var music_table := {}          ## Index -> Dateiname
var mission_music := {}        ## "normal"/"action" -> Dateiname
var stats := {"lights": 0, "spots": 0, "sounds": 0, "tracks": 0}
var music: AudioStreamPlayer
var _music_override := false
var _random_sounds: Array[AudioStreamPlayer3D] = []
var _rand_t := 0.0


func setup(m: Mission, rt: LsRuntime, mission_dir: String) -> void:
	mission = m
	runtime = rt
	name = "OrigExtras"
	var extra = LsRuntime._read_json(mission_dir + "/extra.json")
	if typeof(extra) != TYPE_DICTIONARY or extra.is_empty():
		return
	var script_text := _script_text(mission_dir + "/scripts")
	_build_lights(extra.get("lights", []))
	_build_sounds(extra.get("sounds", []), script_text)
	for t in extra.get("tracks", []):
		tracks[String(t["name"]).to_upper()] = t["keys"]
	stats.tracks = tracks.size()
	for e in extra.get("music_table", []):
		if e["files"].size() > 0:
			music_table[int(e["index"])] = String(e["files"][0]).to_lower()
	var audio = LsRuntime._read_json(mission_dir + "/audio.json")
	if typeof(audio) == TYPE_DICTIONARY:
		mission_music = audio.get("mission_music", {})
	music = AudioStreamPlayer.new()
	music.volume_db = -8.0
	add_child(music)
	Events.alarm_raised.connect(func(_p, _b): _play_mission_music("action"))
	_play_mission_music("normal")


static func _script_text(dir: String) -> String:
	var out := ""
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa:
			out += fa.get_buffer(fa.get_length()).get_string_from_ascii().to_lower() + "\n"
	return out


static func _quat(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _build_lights(lights: Array) -> void:
	for l in lights:
		if l.get("lightmap_only", false):
			continue
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		var rng: float = maxf(float(l.get("range", 8.0)), 1.0)
		var pos := _vec(l["world_pos"])
		match String(l.get("type", "")):
			"point":
				var o := mission.add_lamp(pos, rng, col, float(l.get("power", 1.0)) * POINT_ENERGY)
				o.shadow_enabled = false
				o.name = String(l["name"]).validate_node_name()
				runtime.register_actor(l["name"], o)
				stats.lights += 1
			"spot":
				var s := SpotLight3D.new()
				s.name = String(l["name"]).validate_node_name()
				s.light_color = col
				s.light_energy = float(l.get("power", 1.0)) * POINT_ENERGY * 1.5
				s.spot_range = rng
				s.spot_angle = clampf(rad_to_deg(float(l.get("cone_outer", 1.0))) * 0.5, 5.0, 89.0)
				s.shadow_enabled = false
				mission.dynamic_root.add_child(s)
				s.global_transform = Transform3D(Basis(_quat(l["world_rot"])), pos)
				runtime.register_actor(l["name"], s)
				# Lichtkegel macht Bereiche darunter für die Sicht-Erkennung hell
				mission.lamps.append([pos + s.global_basis * Vector3(0, 0, -rng * 0.6), rng * 0.5, 1.2])
				stats.spots += 1


func _build_sounds(sounds: Array, script_text: String) -> void:
	for s in sounds:
		var file := String(s.get("file", "")).to_lower()
		if file == "":
			continue
		if not file.contains("."):
			file += ".wav"
		var path := OrigLevel.cache_root() + "/sounds/" + file
		if not FileAccess.file_exists(path):
			continue
		var st := AudioStreamWAV.load_from_file(path)
		if st == null:
			continue
		var loop: bool = s.get("loop", false)
		if loop:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		var p := AudioStreamPlayer3D.new()
		p.name = String(s["name"]).validate_node_name()
		p.stream = st
		p.unit_size = maxf(float(s.get("radius_inner", 5.0)), 1.0)
		p.max_distance = maxf(float(s.get("radius_outer", 40.0)), p.unit_size + 1.0)
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.volume_db = linear_to_db(clampf(float(s.get("volume", 1.0)), 0.05, 1.0)) - 4.0
		p.pitch_scale = clampf(float(s.get("pitch", 1.0)), 0.3, 3.0)
		mission.dynamic_root.add_child(p)
		p.global_position = _vec(s["world_pos"])
		runtime.register_actor(s["name"], p)
		stats.sounds += 1
		# Vom Skript geschaltete Quellen (FRM_FindFrame per Name) starten aus
		var scripted := script_text.contains("\"" + String(s["name"]).to_lower() + "\"")
		if scripted:
			continue
		if loop:
			p.play(randf() * maxf(st.get_length() - 0.1, 0.0))
		else:
			_random_sounds.append(p)


func _process(delta: float) -> void:
	_rand_t -= delta
	if _rand_t > 0.0 or _random_sounds.is_empty():
		return
	_rand_t = randf_range(4.0, 10.0)
	var p: AudioStreamPlayer3D = _random_sounds.pick_random()
	if is_instance_valid(p) and not p.playing:
		p.play()


# --- Musik ------------------------------------------------------------------------

func _load_music(file: String) -> AudioStream:
	var path := OrigLevel.cache_root() + "/music/" + file
	if not FileAccess.file_exists(path):
		return null
	var st := AudioStreamOggVorbis.load_from_file(path)
	return st


func _play_mission_music(kind: String) -> void:
	if _music_override or not mission_music.has(kind) or music == null:
		return
	var st := _load_music(mission_music[kind])
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	music.stream = st
	music.play()


## PlayMusic(n) / PlayCutsceneMusic(n): Eintrag n der Musiktabelle; -1 beendet die Einlage.
func play_table(index: int) -> void:
	if index < 0:
		_music_override = false
		_play_mission_music("action" if mission.alarm_raised else "normal")
		return
	var st := _load_music(music_table.get(index, ""))
	if st == null:
		return
	_music_override = true
	music.stream = st
	music.play()
	if not music.finished.is_connected(_on_music_done):
		music.finished.connect(_on_music_done)


func _on_music_done() -> void:
	if _music_override:
		play_table(-1)


# --- Spuren -----------------------------------------------------------------------

## FRM_WatchTrack: Frame fährt die Spur ab (Geschwindigkeit je Schlüssel in m/s).
## parent != null: Spur bewegt sich mit dem Elternobjekt mit (FRM_WatchTrackWithParent).
func watch_track(frame: Node3D, track_name: String, parent: Node3D = null) -> float:
	var keys: Array = tracks.get(track_name.to_upper(), [])
	if frame == null or keys.is_empty():
		return 0.0
	var tw := create_tween()
	var start_parent := parent.global_position if parent else Vector3.ZERO
	var total := 0.0
	frame.global_position = _vec(keys[0]["pos"])
	frame.quaternion = _quat(keys[0]["rot"])
	for i in range(1, keys.size()):
		var a: Dictionary = keys[i - 1]
		var b: Dictionary = keys[i]
		var dist := _vec(a["pos"]).distance_to(_vec(b["pos"]))
		var dur := dist / maxf(float(a.get("speed", 5.0)), 0.1)
		total += dur
		var from := Transform3D(Basis(_quat(a["rot"])), _vec(a["pos"]))
		var to := Transform3D(Basis(_quat(b["rot"])), _vec(b["pos"]))
		tw.tween_method(_track_step.bind(frame, from, to, parent, start_parent), 0.0, 1.0, maxf(dur, 0.01))
	return total


func _track_step(t: float, frame, from: Transform3D, to: Transform3D, parent, start_parent: Vector3) -> void:
	if not is_instance_valid(frame):
		return
	var x := from.interpolate_with(to, t)
	if is_instance_valid(parent):
		x.origin += (parent as Node3D).global_position - start_parent
	(frame as Node3D).global_transform = x
