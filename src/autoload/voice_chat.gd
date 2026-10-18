class_name VoiceChat
extends Node
## Voice-Chat im Mehrspieler (Original T2431–2433, Codecs T2880–2887). Ohne externe Codecs:
## Mikrofon (AudioStreamMicrophone → Bus „VoiceMic“ mit AudioEffectCapture, stummgeschaltet) → Mono,
## Abtastung 8 kHz (64 kbps) bzw. 4 kHz (32 kbps) → μ-law 8 bit → ENet (unzuverlässig, geordnet) an den Server,
## der an alle (Team-Stile: nur ans eigene Team, Original „Set Transmition team“) weiterleitet. Wiedergabe je
## Sprecher über AudioStreamGenerator. Sprechen nur mit gehaltener Taste „voice_talk“ (Push-to-talk, Ergänzung).
## Knoten liegt unter /root/Net/Voice (gleicher Pfad auf allen Rechnern für die RPCs).

const FRAME_S := 0.04             ## 40 ms je Paket
var talking := false
var frames_sent := 0
var frames_received := 0
var last_speaker := ""
var last_level := 0.0              ## Pegel des zuletzt empfangenen Pakets (Test/Anzeige)
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _players := {}                 ## Sprecher-ID -> AudioStreamPlayer (Generator)
var _acc := PackedFloat32Array()
var _src_rate := 44100.0


static func mulaw_encode(x: float) -> int:
	var s := clampf(x, -1.0, 1.0) * 32635.0
	var sg := 0x80 if s < 0.0 else 0
	var v := int(absf(s)) + 0x84
	var ex := 7
	var mask := 0x4000
	while ex > 0 and (v & mask) == 0:
		ex -= 1
		mask >>= 1
	var mant := (v >> (ex + 3)) & 0x0F
	return ~(sg | (ex << 4) | mant) & 0xFF


static func mulaw_decode(b: int) -> float:
	b = ~b & 0xFF
	var sg := b & 0x80
	var ex := (b >> 4) & 0x07
	var mant := b & 0x0F
	var v := (((mant << 3) + 0x84) << ex) - 0x84
	return float(-v if sg != 0 else v) / 32768.0


static func encode(pcm: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pcm.size())
	for i in pcm.size():
		out[i] = mulaw_encode(pcm[i])
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = mulaw_decode(data[i])
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func codec_rate() -> int:
	return Net.voice_rate(int(Net.settings.get("voice_codec", 0)))


func available() -> bool:
	return Net.is_online and Settings.voice_enabled and codec_rate() > 0 and not Net.dedicated


func _process(delta: float) -> void:
	var want := available() and InputMap.has_action("voice_talk") and Input.is_action_pressed("voice_talk") \
		and Net.chat_focus == false
	if want != talking:
		talking = want
		_set_mic(want)
	if talking and _capture:
		var n := _capture.get_frames_available()
		if n > 0:
			var st := _capture.get_buffer(n)
			for f in st:
				_acc.append((f.x + f.y) * 0.5)
		var need := int(_src_rate * FRAME_S)
		while _acc.size() >= need:
			var chunk := _acc.slice(0, need)
			_acc = _acc.slice(need)
			send_frame(_resample(chunk, codec_rate()))
	for id in _players.keys():
		var p: AudioStreamPlayer = _players[id]
		if is_instance_valid(p):
			p.volume_db = linear_to_db(maxf(Settings.voice_volume, 0.001))


func _resample(src: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := _src_rate / float(rate)
	var t := 0.0
	while int(t) < src.size():
		out.append(src[int(t)])
		t += step
	return out


func _set_mic(on: bool) -> void:
	if on:
		if _mic == null:
			var bus := AudioServer.get_bus_index("VoiceMic")
			if bus < 0:
				AudioServer.add_bus()
				bus = AudioServer.bus_count - 1
				AudioServer.set_bus_name(bus, "VoiceMic")
				AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
				AudioServer.set_bus_mute(bus, true)          # eigene Stimme nicht abspielen
			_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
			_mic = AudioStreamPlayer.new()
			_mic.stream = AudioStreamMicrophone.new()
			_mic.bus = "VoiceMic"
			add_child(_mic)
			_src_rate = AudioServer.get_mix_rate()
		_acc.clear()
		if _capture:
			_capture.clear_buffer()
		_mic.play()
	elif _mic:
		_mic.stop()


## Ein Sprachpaket (Mono, codec_rate) senden; auch für Tests ohne Mikrofon
func send_frame(pcm: PackedFloat32Array) -> void:
	if not Net.is_online or codec_rate() <= 0:
		return
	var data := encode(pcm)
	frames_sent += 1
	if multiplayer.is_server():
		_relay(Net.my_id(), data)
	else:
		_vf.rpc_id(1, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _vf(data: PackedByteArray) -> void:
	if multiplayer.is_server() and data.size() <= 1024:
		_relay(multiplayer.get_remote_sender_id(), data)


func _relay(from: int, data: PackedByteArray) -> void:
	var team := int(Net.players.get(from, {}).get("team", -1))
	for id in Net.players.keys():
		if int(id) <= 0 or int(id) == from:
			continue
		if Net.team_mode() and int(Net.players[id]["team"]) != team:
			continue
		if int(id) == 1 and not Net.dedicated:
			_play(from, data)
		elif int(id) != 1:
			_vp.rpc_id(int(id), from, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _vp(from: int, data: PackedByteArray) -> void:
	_play(from, data)


func _play(from: int, data: PackedByteArray) -> void:
	frames_received += 1
	last_speaker = String(Net.players.get(from, {}).get("name", "?"))
	var pcm := decode(data)
	var lvl := 0.0
	for v in pcm:
		lvl = maxf(lvl, absf(v))
	last_level = lvl
	if not Settings.voice_enabled:
		return
	var p: AudioStreamPlayer = _players.get(from)
	if not is_instance_valid(p):
		p = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = maxf(codec_rate(), 4000)
		gen.buffer_length = 0.5
		p.stream = gen
		add_child(p)
		p.play()
		_players[from] = p
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var n := mini(pcm.size(), pb.get_frames_available())
	for i in n:
		pb.push_frame(Vector2(pcm[i], pcm[i]))


func reset() -> void:
	for p in _players.values():
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	talking = false
	if _mic:
		_mic.stop()
