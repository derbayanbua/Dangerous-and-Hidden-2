extends Node
## Original-Klänge und -Musik (Autoload „OrigAudio“). Alle Daten stammen aus der Installation des Nutzers und
## liegen nach tools/fmt_sounds.py im lokalen Cache (orig_cache/sounds/*.wav, orig_cache/music/*.ogg,
## orig_cache/sounds.json; nie im Repository). Belege: docs/re_notes_audio.md.
##
## Klangtabelle TABLES\IngameSounds.def: Kategorie -> Gruppe -> Varianten {Datei, kumulative Wahrscheinlichkeit,
## Mindestabstand, Höchstabstand, Lautstärke}. Abspielen wie hd2.exe 0x433FA0/0x435240: Variante nach
## Wahrscheinlichkeit, 3D-Quelle mit SetRange(min, max) (volle Lautstärke bis min, Abfall 1/d, jenseits von max
## unhörbar), Lautstärke = Tabellenwert × Aufrufer.
##
## Kleine Schnittstelle für Menüs/HUD: play_ui(name), play_music(track[, loop, fade_ms]), stop_music().

const CAT_STEP := 0          ## Puppet Movement (Schritte je Untergrund, Leitern, Körperfall)
const CAT_OBJECT := 1        ## Object Manipulation (Türen, Kisten, Schlösser, Funkgerät, Foto)
const CAT_SHOT := 2          ## Weapon Shooting
const CAT_WEAPON := 3        ## Weapon Manipulation (Nachladen, Ziehen, Repetieren, leer)
const CAT_HIT := 4           ## Bullet Hit (Einschläge je Material, Vorbeiflug, Messer)
const CAT_FALL := 5          ## Falling Hit (Hülsen, Granate ins Wasser, Aufprall)
const CAT_EXPLOSION := 6
const CAT_FURNITURE := 7     ## „Version“: Möbel, Flaschen, Glas, Tür eintreten
const CAT_VEHICLE := 8       ## Vehicle Not Car (U-Boot, Flugzeug)
const CAT_SPEECH := 9
const CAT_UI := 10           ## Interface & Menu
const CAT_MISC := 11         ## Tiere, Animationen, Sanitäter, Drahtschere, Bombe, Schlossknacken
const CAT_MUSIC := 12

const W_EMPTY := 4                ## Kat. 3 „All Empty“
const STEP_BODYFALL := 44         ## Kat. 0 „Uni Bodyfall“
const HIT_FLESH := 7              ## Kat. 4 „Flash or Dead Body“
const HIT_WHIZZ := 11             ## Kat. 4 „Whizz Bullet Effect“
const HIT_GLASS := 15
const HIT_KNIFE_CUT := 19
const HIT_KNIFE_JAB := 20
const FALL_SHELL_HARD := 0        ## Kat. 5 „Pistol Bullets Hard“ (Hülsen)
const FALL_GRENADE_WATER := 1
const EXP_GRENADE := 0
const EXP_WATER := 1
const EXP_DIRT := 2
const EXP_CHARGE_OUT := 16        ## „Explosion Naloz Ext“ (Sprengladung)
const EXP_CAR_HEAVY := 18
const EXP_CAR_MIDDLE := 19
const EXP_CAR_LIGHT := 20
const EXP_MINE := 30
const OBJ_CRATE_OPEN := 10
const OBJ_CRATE_CLOSE := 11
const OBJ_FOTO := 46
const OBJ_RADIO := 50
const OBJ_DEATH_RATTLE := 55      ## „Smrtelny chropot“
const MISC_DOG_DEATH := 2
const MISC_DOG_HURT := 3
const MISC_DOG_WOOF := 4
const MISC_DOG_ATTACK := 5
const MISC_DOG_RUN := 6
const MISC_MEDIC := 24
const MISC_WIRECUT := 25
const MISC_SELF_MEDIC := 26
const MISC_BOMB := 27
const MISC_ALARM := 29            ## „Anim09 Alarm kolejnice“ (Alarmschiene)
const MISC_LOCKPICK := 35

## Sprach-Ereignisse (TABLES\speech.set; Bedeutung aus speech.txt)
const EV_ENEMY_SIGHTED := 92
const EV_ENEMY_CONTACT := 94
const EV_BODY := 98
const EV_UNDER_FIRE := 100
const EV_FRIENDLY_FIRE := 102
const EV_ENEMY_KILLED := 106
const EV_HIT := 108               ## „I'm Hit“ (gerufen)
const EV_CLOSE_CALL := 110
const EV_E_NO_WEAPON := 114
const EV_DEATH := 115
const EV_DYING := 116
const EV_HURT := 117
const EV_E_KILLED := 118          ## Gegner: „Ich hab ihn“
const EV_E_ATTACK := 119          ## „Get Him! / He's Here!“
const EV_E_CANCEL := 120          ## „Cancel Alarm / It's All Over“
const EV_E_SEE := 121             ## „I See Him / Enemy!“
const EV_E_SUSPICIOUS := 122      ## „What's Going On?“
const EV_E_NOTHING := 123         ## „Oh, That Was Nothing“
const EV_E_IDLE := 124
const SET_ENEMY_GERMAN := [9, 10, 11, 12]   ## Enemy G #2, #3, #4, #1 (actors.bin +0x114 bei Achsensoldaten)
const SET_ALLIES := 14

## Musik: Überblendzeiten aus hd2.exe (0x69E970: 4000 ms Kampf/Normal, Skript PlayMusic 4000 ms;
## PlayCutsceneMusic senkt die Missionsmusik in 2000 ms auf 0,15)
const MUSIC_FADE_MS := 4000
const CUTSCENE_DUCK := 0.15
const MUSIC_GAIN_DB := -6.0       ## Grundpegel der Musik (Mischung; Regler „Musik-Lautstärke“ wirkt auf den Bus)
const SPEECH_MIN := 3.0           ## Sprachquellen: Abstände nicht in den Tabellen (Annahme)
const SPEECH_MAX := 50.0
const HISTORY_MAX := 500

## Original-Gegenstand je Waffe des Nachbaus, wenn nicht in WeaponDB.ORIG_IDS
const WEAPON_ITEM := {&"kar98k_sd": 4, &"mp40_sd": 18, &"flak38": 46, &"panzerschreck": 38}
## Vorgabe Auftraggeber: K98k mit Schalldämpfer = De-Lisle-Schuss, MP 40 mit Schalldämpfer = Sten Mk II S
const WEAPON_OVERRIDE := {&"kar98k_sd": {"shoot": [2, 15]}, &"mp40_sd": {"shoot": [2, 2]}}

var data: Dictionary = {}
var _loaded := false
var _streams := {}
var _set_names: Array = []
var history: Array = []           ## letzte Abspielvorgänge {kind, cat, id, file} (Tests/Diagnose)
var surface: SurfaceMap = null    ## Untergrund der aktuellen Originalmission
var default_material := -1        ## Untergrund ohne tree.klz (Übungseinsätze): Zeile in hdmaterials.def

# --- Musik ---
var _music: AudioStreamPlayer
var _overlay: AudioStreamPlayer
var _ui: AudioStreamPlayer
var music_file := ""              ## laufender Titel (Datei)
var _vol := 1.0
var _vol_target := 1.0
var _vol_rate := 0.0              ## Änderung je Sekunde
var _pending := ""
var _pending_loop := true
var mission_music := {"normal": -1, "action": -1}
var _combatants := {}             ## Gegner im Kampfzustand (hd2.exe 0x69E920: Zähler Mission+0xD4)
var _hold := 0.0                  ## Mindestdauer nach einem Wechsel (Mission+0xD0 = 5000 ms)
var _mode := ""                   ## "normal" / "action" / "event"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = &"Music"
	add_child(_music)
	_overlay = AudioStreamPlayer.new()
	_overlay.name = "CutsceneMusic"
	_overlay.bus = &"Music"
	_overlay.volume_db = MUSIC_GAIN_DB
	add_child(_overlay)
	_overlay.finished.connect(stop_cutscene_music)
	_ui = AudioStreamPlayer.new()
	_ui.name = "UI"
	_ui.bus = &"SFX"
	add_child(_ui)


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var path := OrigLevel.cache_root() + "/sounds.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(d) == TYPE_DICTIONARY:
		data = d
		_set_names = (d.get("speech_sets", {}) as Dictionary).keys()


func available() -> bool:
	_ensure()
	return not data.is_empty()


# --- Dateien ------------------------------------------------------------------------

func file_path(file: String) -> String:
	var f := file.to_lower()
	var dir: String = "/music/" if f.ends_with(".ogg") else "/sounds/"
	return OrigLevel.cache_root() + dir + f


func has_file(file: String) -> bool:
	return file != "" and FileAccess.file_exists(file_path(file))


## Klangdatei laden (zwischengespeichert). WAV-Schleifen: ganze Datei.
func stream(file: String, loop := false) -> AudioStream:
	var key: String = file.to_lower() + ("|L" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var p := file_path(file)
	if not FileAccess.file_exists(p):
		return null
	var st: AudioStream = null
	if p.ends_with(".ogg"):
		var o := AudioStreamOggVorbis.load_from_file(p)
		if o:
			o.loop = loop
		st = o
	else:
		var w := AudioStreamWAV.load_from_file(p)
		if w and loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		st = w
	if st:
		_streams[key] = st
	return st


# --- Klangtabelle ---------------------------------------------------------------------

func group(cat: int, id: int) -> Dictionary:
	_ensure()
	var cats: Array = data.get("categories", [])
	if cat < 0 or cat >= cats.size() or id < 0:
		return {}
	var gs: Array = cats[cat].get("groups", [])
	return gs[id] if id < gs.size() else {}


func group_index(cat: int, gname: String) -> int:
	_ensure()
	var cats: Array = data.get("categories", [])
	if cat < 0 or cat >= cats.size():
		return -1
	var want := gname.to_lower().replace(" ", "")
	for g in cats[cat].get("groups", []):
		if String(g.get("name", "")).to_lower().replace(" ", "") == want:
			return int(g["id"])
	return -1


## Variante nach kumulativer Wahrscheinlichkeit (hd2.exe 0x435240: rand % 100 < kum. %); nur vorhandene Dateien.
func pick(cat: int, id: int) -> Dictionary:
	var vs: Array = group(cat, id).get("variants", [])
	if vs.is_empty():
		return {}
	var r := randi() % 100
	var chosen: Dictionary = {}
	for v in vs:
		if r < int(v.get("cum", 100)):
			chosen = v
			break
	if chosen.is_empty():
		chosen = vs[vs.size() - 1]
	if not has_file(String(chosen.get("file", ""))):
		for v in vs:
			if has_file(String(v.get("file", ""))):
				return v
		return {}
	return chosen


func _record(kind: String, cat: int, id: int, file: String) -> void:
	history.append({"kind": kind, "cat": cat, "id": id, "file": file})
	if history.size() > HISTORY_MAX:
		history.pop_front()


## Anzahl der Abspielvorgänge (Tests): kind leer = alle; cat/id < 0 = beliebig
func played_count(kind := "", cat := -1, id := -1) -> int:
	var n := 0
	for h in history:
		if (kind == "" or h["kind"] == kind) and (cat < 0 or int(h["cat"]) == cat) and (id < 0 or int(h["id"]) == id):
			n += 1
	return n


func last_played(kind := "") -> Dictionary:
	for i in range(history.size() - 1, -1, -1):
		if kind == "" or history[i]["kind"] == kind:
			return history[i]
	return {}


# --- Abspielen ----------------------------------------------------------------------

func _container() -> Node:
	var p: Node = Effects._parent() if Effects.has_method("_parent") else null
	if p == null:
		p = get_tree().current_scene
	return p if p else self


## Tabellenklang (Kategorie, Gruppe) an pos. parent: Quelle hängt am Knoten (bewegt sich mit).
func play_group(cat: int, id: int, pos: Vector3, parent: Node = null, volume := 1.0, loop := false) -> AudioStreamPlayer3D:
	var v := pick(cat, id)
	if v.is_empty():
		return null
	var p := play_file(String(v["file"]), pos, float(v.get("min", 0.0)), float(v.get("max", 20.0)),
		float(v.get("volume", 1.0)) * volume, parent, loop, &"SFX", false)
	if p:
		_record("group", cat, id, String(v["file"]))
	return p


## Datei als 3D-Quelle: volle Lautstärke bis min_d, danach 1/d (DirectSound-Modell), über max_d unhörbar.
func play_file(file: String, pos: Vector3, min_d: float, max_d: float, volume := 1.0, parent: Node = null,
		loop := false, bus := &"SFX", record := true) -> AudioStreamPlayer3D:
	var st := stream(file, loop)
	if st == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = bus
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = maxf(min_d, 0.5)
	p.max_db = 0.0
	p.max_distance = maxf(max_d, p.unit_size + 1.0)
	p.volume_db = linear_to_db(clampf(volume, 0.001, 4.0))
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	var host: Node = parent if is_instance_valid(parent) else _container()
	host.add_child(p)
	if host is Node3D and is_instance_valid(parent):
		p.position = Vector3.ZERO
	else:
		p.global_position = pos
	if not loop:
		p.finished.connect(p.queue_free)
	p.play()
	if record:
		_record("file", -1, -1, file)
	return p


## Zweidimensional (Menü, HUD, Musik-Einlagen)
func play_2d(file: String, volume := 1.0, bus := &"SFX") -> AudioStreamPlayer:
	var st := stream(file)
	if st == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = linear_to_db(clampf(volume, 0.001, 4.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	_record("2d", -1, -1, file)
	return p


## Menü-/HUD-Klang: "button"/"click" = Kat. 10 „Menu Button“ (button.wav), sonst Gruppenname aus Kat. 10
## oder Dateiname.
func play_ui(sound_name := "button") -> void:
	var file := ""
	if sound_name == "button" or sound_name == "click":
		file = String(pick(CAT_UI, 0).get("file", ""))
	elif sound_name.ends_with(".wav"):
		file = sound_name
	else:
		var gi := group_index(CAT_UI, sound_name)
		if gi >= 0:
			file = String(pick(CAT_UI, gi).get("file", ""))
	var st := stream(file)
	if st == null:
		return
	_ui.stream = st
	_ui.play()
	_record("ui", CAT_UI, 0, file)


# --- Waffen ---------------------------------------------------------------------------

## Original-Gegenstand (items.sav-Nummer) zu einer Waffe des Nachbaus; -1 unbekannt.
func orig_item_of(d: WeaponData, team := -1) -> int:
	if d == null:
		return -1
	if d.id == &"knife":
		return 56 if (d.faction == "axis" or team == Soldier.TEAM_AXIS) else 57
	if WEAPON_ITEM.has(d.id):
		return int(WEAPON_ITEM[d.id])
	var sid := String(d.id)
	if sid.begins_with("o_"):
		return int(sid.substr(2))
	for k in WeaponDB.ORIG_IDS:
		if WeaponDB.ORIG_IDS[k] == d.id:
			return int(k)
	return -1


## [Kategorie, Gruppe] eines Waffenklangs: shoot, reload, armed, bolt, last_shot, empty. Leer = keiner.
## Quelle: items.sav (Schuss +u4 Kat. 2, Nachladen +u10 Kat. 3, Ziehen Basis+0x78 Kat. 3, Repetieren +u18,
## letzter Schuss +u17) – belegt durch die Gruppennamen (docs/re_notes_audio.md §3).
func weapon_sound(d: WeaponData, kind: String, team := -1) -> Array:
	_ensure()
	if d == null:
		return []
	if kind == "empty":
		return [CAT_WEAPON, W_EMPTY]
	if WEAPON_OVERRIDE.has(d.id) and WEAPON_OVERRIDE[d.id].has(kind):
		return WEAPON_OVERRIDE[d.id][kind]
	var item := orig_item_of(d, team)
	var ws: Dictionary = (data.get("weapons", {}) as Dictionary).get(str(item), {})
	var r: Array = ws.get(kind, [])
	return [int(r[0]), int(r[1])] if r.size() >= 2 else []


func play_weapon(d: WeaponData, kind: String, pos: Vector3, parent: Node = null, team := -1, volume := 1.0) -> AudioStreamPlayer3D:
	var s := weapon_sound(d, kind, team)
	if s.size() < 2:
		return null
	var p := play_group(int(s[0]), int(s[1]), pos, parent, volume)
	if p:
		_record("weapon:" + kind, int(s[0]), int(s[1]), String(d.id))
	return p


# --- Untergrund --------------------------------------------------------------------

func load_surface(mission_dir: String) -> bool:
	surface = SurfaceMap.load_file(mission_dir + "/surface.bin")
	return surface != null


func clear_mission() -> void:
	surface = null
	default_material = -1
	_combatants.clear()
	mission_music = {"normal": -1, "action": -1}
	_mode = ""


func material_info(m: int) -> Dictionary:
	_ensure()
	var ms: Array = data.get("materials", [])
	return ms[m] if m >= 0 and m < ms.size() else {}


func floor_material(pos: Vector3) -> int:
	if surface:
		var m := surface.floor_material(pos)
		if m >= 0:
			return m
	return default_material


## Schrittklang (Kat. 0, hdmaterials.def +0x20) für den Boden an pos
func play_step(pos: Vector3, parent: Node = null, volume := 1.0) -> AudioStreamPlayer3D:
	var m := floor_material(pos)
	var g := int(material_info(m).get("step_sound", -1))
	if g < 0:
		return null
	var p := play_group(CAT_STEP, g, pos, parent, volume)
	if p:
		_record("step", CAT_STEP, g, str(m))
	return p


## Einschlag (Kat. 4, hdmaterials.def +0x30) am Trefferpunkt; ohne Materialdaten „Dirt or Cartway“.
func play_impact(pos: Vector3) -> AudioStreamPlayer3D:
	var m := -1
	if surface:
		m = surface.surface_material(pos)
	if m < 0:
		m = default_material
	var g := 0
	if m >= 0:
		g = int(material_info(m).get("hit_sound", 0))
	if g < 0:
		return null
	var p := play_group(CAT_HIT, g, pos)
	if p:
		_record("impact", CAT_HIT, g, str(m))
	return p


# --- Figurenklänge (hd2.exe-Tabelle 0x84E938) ------------------------------------------

func human_event(ev: String, pos: Vector3, parent: Node = null, volume := 1.0) -> AudioStreamPlayer3D:
	_ensure()
	var lst: Array = (data.get("human", {}) as Dictionary).get(ev, [])
	if lst.is_empty():
		return null
	var e: Dictionary = lst[randi() % lst.size()]
	var p := play_file(String(e["file"]), pos, float(e["min"]), float(e["max"]), float(e["volume"]) * volume, parent)
	if p:
		_record("human:" + ev, -1, -1, String(e["file"]))
	return p


# --- Sprache ---------------------------------------------------------------------------

func set_index(set_name: String) -> int:
	_ensure()
	return _set_names.find(set_name)


## Sprachsatz einer Figur: Originalwert (actors.bin +0x114), Trupp = English #Teamplatz, Achse = deutsche Sätze.
func voice_set_of(s: Node) -> int:
	if s == null:
		return -1
	if s.has_meta("speech_set"):
		return int(s.get_meta("speech_set"))
	if s.has_meta("orig_params"):
		var ss := int((s.get_meta("orig_params") as Dictionary).get("speech_set", 0))
		if ss > 0:
			return ss
	var m := Game.current_mission()
	if m and "squad" in m and m.squad and s is Soldier and (m.squad.members as Array).has(s):
		return 1 + (m.squad.members as Array).find(s) % 4
	if s is Soldier and (s as Soldier).team == Soldier.TEAM_AXIS:
		var pid: String = String(s.get("persistent_id")) if "persistent_id" in s else String(s.name)
		return int(SET_ENEMY_GERMAN[absi(pid.hash()) % SET_ENEMY_GERMAN.size()])
	return SET_ALLIES


func speech_ids(set_idx: int, event: int) -> Array:
	_ensure()
	if set_idx < 0 or set_idx >= _set_names.size():
		return []
	var ev: Dictionary = (data.get("speech_sets", {}) as Dictionary).get(_set_names[set_idx], {})
	return ev.get(str(event), [])


## Deutsche Aufnahme einer Sprach-ID (hd2.exe 0x5B0440: 90000000 + ID mod 10000)
static func german_file(id: int) -> String:
	return "%08d.wav" % (90000000 + id % 10000)


## Sprach-Ereignis einer Figur (zufällige Aufnahme des Satzes). cooldown: Mindestabstand je Sprecher in s.
## Rückgabe: Dauer in s (0 = nichts gespielt).
func speak_event(s: Node3D, event: int, cooldown := 0.0, set_idx := -1) -> float:
	if s == null or not is_instance_valid(s):
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if cooldown > 0.0 and float(s.get_meta("_speech_until", -1.0)) > now:
		return 0.0
	if set_idx < 0:
		set_idx = voice_set_of(s)
	var ids := speech_ids(set_idx, event)
	if ids.is_empty():
		return 0.0
	var id := int(ids[randi() % ids.size()])
	var file := german_file(id)
	var p := play_file(file, s.global_position, SPEECH_MIN, SPEECH_MAX, 1.0, s, false, &"Voice", false)
	if p == null:
		return 0.0
	var dur: float = p.stream.get_length()
	s.set_meta("_speech_until", now + maxf(cooldown, dur))
	_record("speech", set_idx, event, file)
	return dur


# --- Musik -----------------------------------------------------------------------------

## Titel auflösen: int = Gruppe der Musiktabelle (Kat. 12), String = Gruppenname oder Dateiname (.ogg)
func music_file_of(track: Variant) -> String:
	if typeof(track) == TYPE_INT or typeof(track) == TYPE_FLOAT:
		return String(pick(CAT_MUSIC, int(track)).get("file", ""))
	var t := String(track)
	if t.to_lower().ends_with(".ogg"):
		return t.to_lower()
	var gi := group_index(CAT_MUSIC, t)
	return String(pick(CAT_MUSIC, gi).get("file", "")) if gi >= 0 else ""


## Musik spielen (Schleife wie hd2.exe 0x4370F0). fade_ms > 0: laufenden Titel ausblenden, dann wechseln.
func play_music(track: Variant, loop := true, fade_ms := 0) -> bool:
	var file := music_file_of(track)
	if file == "" or not has_file(file):
		return false
	if fade_ms > 0 and _music.playing:
		_pending = file
		_pending_loop = loop
		_fade_to(0.01, fade_ms)
		return true
	_start_music(file, loop)
	return true


func stop_music(fade_ms := 0) -> void:
	_pending = ""
	if fade_ms > 0 and _music.playing:
		_pending = "-"
		_fade_to(0.01, fade_ms)
		return
	_music.stop()
	music_file = ""


func _start_music(file: String, loop: bool) -> void:
	var st := stream(file, loop)
	if st == null:
		return
	_music.stream = st
	_vol = 1.0
	_vol_target = 1.0 if not _overlay.playing else CUTSCENE_DUCK
	_apply_vol()
	_music.play()
	music_file = file
	_record("music", CAT_MUSIC, -1, file)


func _fade_to(target: float, ms: int) -> void:
	_vol_target = target
	_vol_rate = absf(_vol - target) / maxf(float(ms) / 1000.0, 0.001)


func _apply_vol() -> void:
	_music.volume_db = MUSIC_GAIN_DB + linear_to_db(maxf(_vol, 0.0001))


func _process(delta: float) -> void:
	_hold = maxf(_hold - delta, 0.0)
	if not is_equal_approx(_vol, _vol_target):
		_vol = move_toward(_vol, _vol_target, _vol_rate * delta)
		_apply_vol()
	if _pending != "" and _vol <= 0.0101:
		var f := _pending
		_pending = ""
		if f == "-":
			_music.stop()
			music_file = ""
		else:
			_start_music(f, _pending_loop)


## PlayCutsceneMusic(n): Einlage ohne Schleife, Missionsmusik in 2 s auf 0,15 (hd2.exe 0x436F60)
func play_cutscene_music(track: Variant) -> bool:
	var file := music_file_of(track)
	var st: AudioStream = stream(file) if file != "" else null
	if st == null:
		return false
	_overlay.stream = st
	_overlay.play()
	_fade_to(CUTSCENE_DUCK, 2000)
	_record("cutscene_music", CAT_MUSIC, -1, file)
	return true


func stop_cutscene_music() -> void:
	_overlay.stop()
	_fade_to(1.0, 2000)


func is_music_playing() -> bool:
	return _music.playing


# --- Missionsmusik: Normal/Action wie hd2.exe 0x69E920/0x69E970 ---------------------------

## Mission startet: Normal-/Action-Index aus scene2.bin (0xB840/0xB880), Normalmusik beginnt.
func start_mission_music(normal: int, action: int) -> void:
	mission_music = {"normal": normal, "action": action}
	_combatants.clear()
	_mode = ""
	_hold = 0.0
	_switch_mission_music(false)


func _switch_mission_music(action: bool) -> void:
	var want: String = "action" if action else "normal"
	var idx := int(mission_music[want])
	if idx < 0:
		return
	if _mode == want and music_file == music_file_of(idx):
		return
	_mode = want
	_hold = 5.0
	play_music(idx, true, MUSIC_FADE_MS if _music.playing else 0)


## Gegner tritt in den Kampf ein / verlässt ihn (Zähler; ab 1 Action-, bei 0 Normalmusik)
func set_combat(who: Object, on: bool) -> void:
	var key := who.get_instance_id()
	var before := _combatants.size()
	if on:
		_combatants[key] = true
	else:
		_combatants.erase(key)
	var after := _combatants.size()
	if (before == 0) != (after == 0):
		_switch_mission_music(after > 0)


func combat_count() -> int:
	return _combatants.size()


## Skript PlayMusic(n): Überblendung 4 s auf Eintrag n; −1 zurück zur Missionsmusik (Kampfzustand)
func script_play_music(index: int) -> void:
	if index < 0:
		_mode = ""
		_switch_mission_music(not _combatants.is_empty())
		return
	_mode = "event"
	play_music(index, true, MUSIC_FADE_MS if _music.playing else 0)
