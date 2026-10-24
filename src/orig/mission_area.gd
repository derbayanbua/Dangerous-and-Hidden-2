extends Node
## Einsatzgebiet-Grenze wie im Original (docs/re_notes_script_anims.md §3):
##  * Grenze = Kollisionsdreiecke aus MISSIONS\<m>\tree.klz mit Eigenschaftsbit 0x4000 (Warnzone) bzw. 0x2000 (außerhalb);
##    Export tools/fmt_klz.py → orig_cache/<m>/area.json [B: Bits in den Daten, z. B. ARCTIC1 107/30 Dreiecke].
##  * hd2.exe 0x5A9720: Soldat → (Bodendreieck unter den Füßen, +0x98→+8→+0x754, gesetzt bei 0x75D51A nach
##    Abwärtsstrahl 0x7183A0)->Eigenschaften & 0x6000; im Fahrzeug die Räder (0x4DD090) [B].
##  * 0x45EF00 (Team): ODER über alle lebenden Teammitglieder; nur bei Änderung: 0x2000 → 0x69BED0(1) = Mission
##    gescheitert mit Text 7408, sonst 0x4000 → Meldung 7407 (0x49DE30), sonst Meldung löschen (−1) [B].
##  * Text 7409 „Sie verlassen das Einsatzgebiet“ gilt dem einzelnen Spieler (0x69EFF7, Netzspiel-Zweig) – hier nicht.
## Annahmen: Bodendreieck = Grenzdreieck, dessen Ebene 1,0 m unter bis 0,5 m über den Füßen liegt [E]; Prüfung alle
## 0,25 s [E]; Meldung bleibt stehen, solange die Warnzone gilt (Wiederholung alle 3 s über Events.say) [P]; während
## einer Zwischensequenz keine Prüfung [E].

const WARN := 0x4000
const OUT := 0x2000

var mission: Mission
var runtime: Node
var faces: Array = []      ## [flags, a: Vector3, b, c, min_x, max_x, min_z, max_z]
var flags := 0             ## zuletzt gemeldeter Teamzustand (0x45EF00: [ebp+0x34])
var _t := 0.0
var _msg_t := 0.0


func setup(m: Mission, rt: Node, mission_dir: String) -> bool:
	mission = m
	runtime = rt
	name = "MissionArea"
	var f := FileAccess.open(mission_dir + "/area.json", FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return false
	for e in d.get("faces", []):
		var a := Vector3(e[1], e[2], e[3])
		var b := Vector3(e[4], e[5], e[6])
		var c := Vector3(e[7], e[8], e[9])
		faces.append([int(e[0]), a, b, c, minf(a.x, minf(b.x, c.x)), maxf(a.x, maxf(b.x, c.x)),
			minf(a.z, minf(b.z, c.z)), maxf(a.z, maxf(b.z, c.z))])
	return not faces.is_empty()


## Eigenschaftsbits des Grenzdreiecks unter dem Punkt (0 = keines)
func flags_at(p: Vector3) -> int:
	for fc in faces:
		if p.x < fc[4] or p.x > fc[5] or p.z < fc[6] or p.z > fc[7]:
			continue
		var a: Vector3 = fc[1]
		var b: Vector3 = fc[2]
		var c: Vector3 = fc[3]
		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		var v2 := Vector2(p.x - a.x, p.z - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-9:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		if u < -1e-4 or v < -1e-4 or u + v > 1.0001:
			continue
		var y := a.y + u * (c.y - a.y) + v * (b.y - a.y)
		if y >= p.y - 1.0 and y <= p.y + 0.5:
			return int(fc[0])
	return 0


func team_flags() -> int:
	var fl := 0
	if mission == null or mission.squad == null:
		return 0
	for s in mission.squad.members:
		if not is_instance_valid(s) or not s.alive:
			continue
		var p: Vector3 = s.global_position
		if s.vehicle != null and is_instance_valid(s.vehicle):
			p = (s.vehicle as Node3D).global_position
		fl |= flags_at(p)
	return fl & (WARN | OUT)


func _physics_process(delta: float) -> void:
	if mission == null or mission.finished:
		return
	if runtime and runtime.get("in_cutscene"):
		return
	_t -= delta
	_msg_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var fl := team_flags()
	if fl != flags:
		flags = fl
		_msg_t = 0.0
		if fl & OUT:
			# Diagnose (Erfüllbarkeitslöser): wer steht wo in der Außenzone
			for s in mission.squad.members:
				if is_instance_valid(s) and s.alive:
					var sp: Vector3 = (s.vehicle as Node3D).global_position if s.vehicle != null and is_instance_valid(s.vehicle) else s.global_position
					print("EINSATZGEBIET verlassen: %s bei %s Flags 0x%x" % [s.name, sp, flags_at(sp)])
			var txt: String = runtime.text(7408) if runtime else "Ihr Team hat das Einsatzgebiet verlassen. MISSION GESCHEITERT"
			Events.say(txt, 5.0)
			mission.finish(false, txt)
			return
		# fl == 0: Original löscht die Meldung (0x49DE30(−1)); hier läuft die letzte Wiederholung nach ≤ 3,2 s aus
	if (flags & WARN) and not (flags & OUT) and _msg_t <= 0.0:
		_msg_t = 3.0
		Events.say(runtime.text(7407) if runtime else "Ihr Team verlässt das Einsatzgebiet! Kehren Sie um!", 3.2)
