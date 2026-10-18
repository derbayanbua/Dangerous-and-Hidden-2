class_name KillCam
extends Control
## Kill-Cam (Ergänzung, kein Original-Element; hängt unter MpHud/Root): nach dem eigenen Tod fährt eine eigene
## Kamera vom bisherigen Blickpunkt zum Schützen und verfolgt ihn live (keine Wiederholung). Einblendung: Name des
## Schützen, Waffe (Waffe in der Hand bzw. Ursache des tödlichen Treffers), Entfernung zur eigenen Leiche und
## Rest-LP des Schützen (Net._hp). Bedingungen: Server-Regel kill_cam (Standard nur Deathmatch) und Optionen
## „KILL-CAM“; keine Kill-Cam bei Selbsttötung/Sturz/Umgebungstod (kein Schütze) und ohne Wiedereinstieg
## (Zuschauer). Ende spätestens bei Respawn-Bereitschaft (Net.respawn_ready → Original „FEUER DRÜCKEN FÜR RESPAWN“),
## beim Wiedereinstieg, nach MAX_S oder wenn der Schütze verschwindet. Überspringen jederzeit mit Feuer/Leertaste
## (MpHud._input → skip): ist der Respawn schon bereit, folgt sofort Net.request_respawn.

const MAX_S := 10.0
const TRAVEL_S := 0.8
const BACK := 3.6
const UP := 1.4

var active := false
var killer_id := 0
var cause := ""
var cam: Camera3D
var started_ms := 0
var skipped := false              ## Tests: letzte Kill-Cam übersprungen
var shown := 0                    ## Tests: Anzahl gestarteter Kill-Cams
var _from := Transform3D()
var _corpse := Vector3.ZERO
var _info: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info = Label.new()
	_info.name = "KillCamInfo"
	_info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info.position = Vector2(-320, -250)
	_info.size = Vector2(640, 96)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 5)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.visible = false
	add_child(_info)
	Net.killed_me.connect(_on_killed_me)


static func enabled() -> bool:
	return Settings.kill_cam and bool(Net.rule("kill_cam"))


func _on_killed_me(kid: int, kcause: String) -> void:
	var killer: Soldier = Net._soldiers.get(kid)
	if not enabled() or kid == 0 or kid == Net.my_id() or kcause == "fall" or not is_instance_valid(killer) \
			or Net.respawn_at == 0 or Net.match_over:
		return
	var m = Game.current_mission()
	var cur := get_viewport().get_camera_3d()
	if m == null or cur == null:
		return
	if cam == null:
		cam = Camera3D.new()
		cam.name = "KillCam"
		cam.far = cur.far
		cam.fov = cur.fov
		m.add_child(cam)
	_from = cur.global_transform
	var me: Soldier = Net._soldiers.get(Net.my_id())
	_corpse = me.global_position if is_instance_valid(me) else cur.global_position
	cam.global_transform = _from
	cam.current = true
	killer_id = kid
	cause = kcause
	started_ms = Time.get_ticks_msec()
	active = true
	skipped = false
	shown += 1
	_info.visible = true


## Kamerapose hinter/über dem Schützen, Blick auf ihn
static func follow_pose(k: Soldier) -> Transform3D:
	var fw := k.forward()
	var eye := k.global_position + Vector3.UP * 1.5
	var pos := eye - fw * BACK + Vector3.UP * UP
	return Transform3D(Basis(), pos).looking_at(eye + fw * 2.0, Vector3.UP)


func info_text() -> String:
	var k: Soldier = Net._soldiers.get(killer_id)
	if not is_instance_valid(k):
		return ""
	var w: Weapon = k.current_weapon()
	var wname: String = w.data.display_name if w and w.data else ""
	if cause != "":
		var wd: WeaponData = WeaponDB.get_weapon(StringName(cause))
		if wd:
			wname = wd.display_name
	return "KILL-CAM\n%s   –   %s\n%.0f m   –   %d LP\n(Feuer/Leertaste: überspringen)" % [String(k.soldier_name), wname,
		k.global_position.distance_to(_corpse), int(ceil(maxf(k.health, 0.0)))]


func _process(_delta: float) -> void:
	if not active:
		return
	var k: Soldier = Net._soldiers.get(killer_id)
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var age := float(Time.get_ticks_msec() - started_ms) / 1000.0
	var over := Net.respawn_ready() or (is_instance_valid(me) and me.alive) or age > MAX_S or not is_instance_valid(k) \
		or not Net.is_online or (Net.respawn_at > 0 and Time.get_ticks_msec() >= Net.respawn_at)
	if over:
		stop()
		return
	var target := follow_pose(k)
	var t := clampf(age / TRAVEL_S, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	cam.global_transform = _from.interpolate_with(target, t)
	_info.text = info_text()


## Kill-Cam beenden (Kamera zurück an die Spielkamera bzw. die Zuschauerkamera)
func stop() -> void:
	if not active:
		return
	active = false
	_info.visible = false
	if cam:
		cam.current = false
	var m = Game.current_mission()
	var hud = m.get_node_or_null("MpHud") if m else null
	if hud and hud.spectating and hud._spec_cam:
		hud._spec_cam.current = true
	elif m and m.get("rig") and m.rig.camera:
		m.rig.camera.current = true


## Überspringen (Feuer/Leertaste): sofort zum Respawn bzw. zur Anzeige „FEUER DRÜCKEN FÜR RESPAWN“
func skip() -> void:
	if not active:
		return
	skipped = true
	stop()
	if Net.respawn_ready():
		Net.request_respawn()
