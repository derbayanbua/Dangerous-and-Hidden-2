class_name OrigExtras
extends Node
## Zusatzdaten einer Originalmission (orig_cache/<m>/extra.json, tools/fmt_mission_extra.py):
##   Lichter (scene2 0x4040)   -> OmniLight3D/SpotLight3D; Punktlichter zählen für die Sichtbarkeit
##   Klangquellen (sounds.bin) -> AudioStreamPlayer3D, per FRM_SetOn schaltbar
##   Spuren (tracks.dat)       -> FRM_WatchTrack (Kamerafahrten, Flugzeug im Intro)
##   Musik (IngameSounds.def)  -> OrigAudio: Normal-/Action-Musik der Mission (scene2.bin 0xB840/0xB880,
##                                Action solange ein Gegner im Kampf ist, hd2.exe 0x69E920), PlayMusic
## Annahmen (nicht am Original verifiziert, siehe docs/re_notes_lights_tracks_sounds.md, re_notes_audio.md):
##   - Klangquellen ohne Loop werden in zufälligen Abständen erneut abgespielt.
##   - Spurpunkte werden linear interpoliert.

const POINT_ENERGY := 1.6

var mission: Mission
var runtime: LsRuntime
var tracks := {}               ## Name (groß) -> Array der Schlüssel
var music_table := {}          ## Index -> Dateiname
var mission_music := {}        ## "normal"/"action" -> Dateiname
var music_index := {"normal": -1, "action": -1}   ## Gruppen der Musiktabelle (scene2.bin-Kopf)
var stats := {"lights": 0, "spots": 0, "sounds": 0, "tracks": 0}
var _random_sounds: Array[AudioStreamPlayer3D] = []
var _lights: Array[Light3D] = []
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
		var mi: Dictionary = audio.get("music_index", {})
		music_index = {"normal": int(mi.get("normal", -1)), "action": int(mi.get("action", -1))}
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	OrigAudio.start_mission_music(int(music_index["normal"]), int(music_index["action"]))


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


## 0.10.1 Lampenlicht [D, Nutzerauftrag „wo Lampen sind, heller“]: Original-Lichter mit kleinem `power` (0,1–0,2)
## waren als Echtzeitlicht kaum sichtbar, die meisten Lampenlichter sind im Original nur in die Lightmap gebacken
## (`lightmap_only`) und fehlten ganz. Jetzt: Energie mit Grundhelligkeit (`lamp_energy`), gebackene Punkt-/Spotlichter
## zusätzlich als echte Lichter (höchstens BAKED_MAX, nach Stärke × Reichweite, Häufungen < BAKED_MERGE_M
## zusammengefasst, Reichweite ≤ BAKED_RANGE_MAX). Gebackene zählen NICHT für die KI-Sicht (mission.lamps unverändert).
## Schatten nur ab Ultra für die SHADOW_MAX stärksten Spots; Entfernungsausblendung über PerfTuning.
## `--lamp_boost=0` = alter Stand (Vergleichsbilder).
const BAKED_MAX := 64
const BAKED_MERGE_M := 1.5
const BAKED_RANGE_MAX := 22.0
const SHADOW_MAX := 4
var lamp_stats := {"baked": 0, "baked_skipped": 0, "merged": 0, "shadowed": 0}


static func lamp_boost_on() -> bool:
	return String(Game.cli.get("lamp_boost", "1")) != "0"


static func lamp_energy(power: float) -> float:
	if not lamp_boost_on():
		return power * POINT_ENERGY
	return POINT_ENERGY * clampf(0.45 + power, 0.55, 2.6)


func _build_lights(lights: Array) -> void:
	var placed: Array[Vector3] = []
	var spots: Array = []                 # [stärke, SpotLight3D]
	var baked: Array = []
	for l in lights:
		var t := String(l.get("type", ""))
		if l.get("lightmap_only", false):
			if lamp_boost_on() and (t == "point" or t == "spot") and float(l.get("range", 0.0)) >= 1.5 \
					and float(l.get("power", 0.0)) >= 0.05:
				baked.append(l)
			continue
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		var rng: float = maxf(float(l.get("range", 8.0)), 1.0)
		var pos := _vec(l["world_pos"])
		placed.append(pos)
		match t:
			"point":
				var o := mission.add_lamp(pos, rng, col, lamp_energy(float(l.get("power", 1.0))))
				o.shadow_enabled = false
				_lights.append(o)
				o.name = String(l["name"]).validate_node_name()
				runtime.register_actor(l["name"], o)
				stats.lights += 1
			"spot":
				var s := SpotLight3D.new()
				s.name = String(l["name"]).validate_node_name()
				s.light_color = col
				s.light_energy = lamp_energy(float(l.get("power", 1.0))) * 1.5
				s.spot_range = rng
				s.spot_angle = clampf(rad_to_deg(float(l.get("cone_outer", 1.0))) * 0.5, 5.0, 89.0)
				s.shadow_enabled = false
				_lights.append(s)
				mission.dynamic_root.add_child(s)
				s.global_transform = Transform3D(Basis(_quat(l["world_rot"])), pos)
				runtime.register_actor(l["name"], s)
				# Lichtkegel macht Bereiche darunter für die Sicht-Erkennung hell
				mission.lamps.append([pos + s.global_basis * Vector3(0, 0, -rng * 0.6), rng * 0.5, 1.2])
				stats.spots += 1
				spots.append([float(l.get("power", 1.0)) * rng, s])
	_build_baked_lamps(baked, placed, spots)
	if lamp_boost_on() and Settings.quality >= 3:
		spots.sort_custom(func(a, b): return a[0] > b[0])
		for i in mini(SHADOW_MAX, spots.size()):
			(spots[i][1] as SpotLight3D).shadow_enabled = true
			lamp_stats.shadowed += 1


func _build_baked_lamps(baked: Array, placed: Array[Vector3], spots: Array) -> void:
	baked.sort_custom(func(a, b): return float(a["power"]) * float(a["range"]) > float(b["power"]) * float(b["range"]))
	for l in baked:
		var pos := _vec(l["world_pos"])
		var near := false
		for p in placed:
			if p.distance_to(pos) < BAKED_MERGE_M:
				near = true
				break
		if near:
			lamp_stats.merged += 1
			continue
		if lamp_stats.baked >= BAKED_MAX:
			lamp_stats.baked_skipped += 1
			continue
		placed.append(pos)
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		var rng := clampf(float(l["range"]), 2.0, BAKED_RANGE_MAX)
		var e := lamp_energy(float(l["power"]))
		var li: Light3D
		if String(l["type"]) == "spot":
			var s := SpotLight3D.new()
			s.spot_range = rng
			s.spot_angle = clampf(rad_to_deg(float(l.get("cone_outer", 1.0))) * 0.5, 5.0, 89.0)
			s.light_energy = e * 1.5
			li = s
			spots.append([float(l["power"]) * rng, s])
		else:
			var o := OmniLight3D.new()
			o.omni_range = rng
			o.omni_attenuation = 1.4
			o.light_energy = e
			li = o
		li.name = "baked_" + String(l["name"]).validate_node_name()
		li.light_color = col
		li.shadow_enabled = false
		li.set_meta("orig_baked_lamp", true)
		mission.dynamic_root.add_child(li)
		li.global_transform = Transform3D(Basis(_quat(l["world_rot"])), pos)
		_lights.append(li)
		lamp_stats.baked += 1


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


## Original-Option „DYNAMIK“: dynamische Lichter an/aus (Sichtbarkeitsmodell der KI bleibt unberührt)
func _apply_settings() -> void:
	for l in _lights:
		if is_instance_valid(l):
			l.visible = Settings.dynamic_lights


func _process(delta: float) -> void:
	_rand_t -= delta
	if _rand_t > 0.0 or _random_sounds.is_empty():
		return
	_rand_t = randf_range(4.0, 10.0)
	var p: AudioStreamPlayer3D = _random_sounds.pick_random()
	if is_instance_valid(p) and not p.playing:
		p.play()


# --- Musik ------------------------------------------------------------------------

## PlayMusic(n): Überblendung (4 s) auf Eintrag n der Musiktabelle, −1 = zurück zur Missionsmusik
## (hd2.exe Skriptbefehl 0x43 -> Klangverwaltung +0x6C bzw. 0x69E970)
func play_table(index: int) -> void:
	OrigAudio.script_play_music(index)


## PlayCutsceneMusic(n): Einlage ohne Schleife über der gedämpften Missionsmusik; −1 beendet sie (0x436F60)
func play_cutscene(index: int) -> void:
	if index < 0:
		OrigAudio.stop_cutscene_music()
	else:
		OrigAudio.play_cutscene_music(index)


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
