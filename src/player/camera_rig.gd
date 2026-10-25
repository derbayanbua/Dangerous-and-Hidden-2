class_name CameraRig
extends Node3D
## Spielkamera für den aktiven Soldaten nach dem Original (docs/re_notes_weapons.md §6–8):
##  - Kameramodul hd2.exe 0x46C370: Ziel ist der Dummy "camera3RD" (3. Person, Modus 1) bzw. "cameraFPV"
##    (1. Person, Modus 2) des Figurenmodells; ihre Höhe je Haltung kommt aus den Original-Animationen.
##  - TABLES\gamecam.set (je Modus 32 Byte, 0x4656D0): 3. Person Abstand 3,0 m, Kollisionskugel 0,1 m,
##    Nickwinkel ±70°, Abstandsnachführung 12 m/s; 1. Person Abstand 0, ±80°. Die Kamera liegt genau hinter dem
##    Drehpunkt auf der Blickachse (0x468130: Pos = Dummy − Richtung · Abstand) – kein Schulterversatz.
##  - Sichtfeld 65° (0x465160: 0x3F91361E), Zoom = items.sav Verhalten 5 (Kimme/Korn 48–60°, Zielfernrohr
##    17–25°, Fernglas 10°); FOV-Werte gelten für 4:3 horizontal [P] -> Godot vertikal (OrigWeapons.vfov).
##  - Zielen (0x5469E0/0x492130): Ansicht wechselt in die 1. Person über die FPV-Waffe (C_FirstPersonView,
##    FPV-Hände + Waffe, Animationen TABLES\FpvAnims.sav), Waffenmodell mit 40° statt 65° gezeichnet,
##    Zielfernrohr-Overlay je Waffe (gameinterface.4ds), Wackeln der Blickrichtung (0x466970).

enum Mode { THIRD, FIRST }

const ORIG_FOV_H := 65.0           ## Kamera (hd2.exe 0x465160)
const FPV_MODEL_FOV_H := 65.0      ## FPV-Modell normal (0x4920B0)
const FPV_MODEL_ZOOM_FOV_H := 40.0 ## FPV-Modell beim Zoomen (0x492130: 0x3F32B8C3)
const BINOC_ITEM := 99             ## Fernglas: items.sav Verhalten 5 = Overlay 4, 10°
## gamecam.set Satz 1 (3. Person draußen) und 2 (1. Person)
const CAM3_DIST := 3.0
const CAM3_RADIUS := 0.1
const CAM3_PITCH := deg_to_rad(70.0)
const CAM3_SPEED := 12.0           ## m/s (Satz +0x1C · 1,0 · 0,001 je ms)
const FPV_PITCH := deg_to_rad(80.0)
const TURN_RATE := 16.0 * PI       ## max. Drehrate der Kamerarichtung (0x4684C4: 16 · π/1000 je ms)
## gamecam.set (re_work/cam/gamecam.set, 11 Sätze): Modus -> [Abstand m, Kollisionsradius m, Nickgrenze rad,
## Nachführtempo m/s]. Auswahl hd2.exe 0x46C370 (3. Person zu Fuß): Spieler im Hauptsektor („Primary sector“)
## bzw. Sektor mit „nointerier“ -> 1, in einem Innensektor -> 3 (bzw. 4 bei „interierclose“); schwimmend
## (Kamera +0x270) draußen -> 5, drinnen -> 6.
const CAM_MODES := {
	1: [3.0, 0.1, deg_to_rad(70.0), 12.0],    # draußen (1,2217 rad)
	3: [1.5, 0.25, deg_to_rad(80.0), 15.0],   # Innenraum (1,3963)
	4: [1.0, 0.25, deg_to_rad(80.0), 15.0],   # Innenraum eng („interierclose“)
	5: [3.0, 0.25, deg_to_rad(85.0), 15.0],   # Wasser draußen (1,4835)
	6: [1.2, 0.25, deg_to_rad(85.0), 15.0],   # Wasser drinnen
}

var mode: int = Mode.THIRD
var target: Soldier
var camera: Camera3D
var _arm: SpringArm3D
var _pivot: Node3D
var _fov := 70.0
var _dist := CAM3_DIST
var _dir := Vector3.FORWARD        ## geglättete Kamerarichtung (Welt)
var _zoom_t := 0.0                 ## 0 = normal … 1 = gezoomt (folgt der FPV-Zielanimation)
var _sway_ms := 0.0
var _sway_amp := 0.005             ## hd2.exe 0x839268 (Startwert)
var fpv_active := false            ## Kamera am Dummy cameraFPV mit FPV-Modell
var cam_mode := 1                  ## gamecam.set-Modus der 3.-Person-Kamera (CAM_MODES)
var interior := false              ## Spieler in einem Innensektor
## Innensektoren der Originalkarte: [Name, AABB (Welt)] aus den Objekten mit Eltern „sector …“ (scene.json). Die
## Sektorgeometrie selbst exportiert der Konverter nicht -> Hülle der Sektorobjekte, bestätigt durch ein Dach über
## dem Kopf (Strahl nach oben) [P]. null = noch nicht ermittelt.
var sector_boxes = null
var _sph: SphereShape3D


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.05
	var sph := SphereShape3D.new()
	sph.radius = CAM3_RADIUS
	_arm.shape = sph
	_sph = sph
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 1200.0
	_arm.add_child(camera)
	camera.current = true
	_fov = base_fov()
	camera.fov = _fov
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	camera.add_child(_viewmodel)


## Grund-FOV (vertikal): Original 65° (4:3 horizontal); die Sichtfeld-Option verschiebt relativ zu 70°.
func base_fov() -> float:
	return OrigWeapons.vfov(ORIG_FOV_H) + (Settings.fov - 70.0)


func set_target(s: Soldier) -> void:
	if is_instance_valid(target):
		if target.model:
			target.model.visible = true
			target.model.head.visible = true
			target.model.set_weapon_visible(true)
		if target.weapon_changed.is_connected(_on_weapon_changed):
			target.weapon_changed.disconnect(_on_weapon_changed)
			target.shot_fired.disconnect(_on_shot)
			target.action_started.disconnect(_on_action)
			target.model_changed.disconnect(_on_model_changed)
	target = s
	if is_instance_valid(target):
		_arm.clear_excluded_objects()
		_arm.add_excluded_object(target.get_rid())
		target.weapon_changed.connect(_on_weapon_changed)
		target.shot_fired.connect(_on_shot)
		target.action_started.connect(_on_action)
		target.model_changed.connect(_on_model_changed)
		_dir = target.aim_direction()
		_on_weapon_changed(target.current_weapon())
		_apply_head_visibility()


## Uniform-/Figurwechsel: Kamera-Anker (camera3RD/cameraFPV) kommen ab jetzt vom neuen Modell; Sichtbarkeit neu.
func _on_model_changed(_m: Node3D) -> void:
	_model_last = null
	_apply_head_visibility()
	if is_instance_valid(target):
		_on_weapon_changed(target.current_weapon())    # Ego-Hände der neuen Uniform


func toggle_mode() -> void:
	mode = Mode.FIRST if mode == Mode.THIRD else Mode.THIRD
	_apply_head_visibility()


## Nickwinkel-Grenze der aktuellen Kamera (gamecam.set: 3. Person ±70°, 1. Person ±80°).
func pitch_limit() -> float:
	return FPV_PITCH if fpv_active else float(CAM_MODES[cam_mode][2])


## Kameramodus wie 0x46C370 wählen (nur 3. Person zu Fuß).
func _select_cam_mode() -> void:
	interior = _in_interior(target.global_position + Vector3.UP * 1.0)
	var swim := bool(target.get("swimming"))
	var m := 1
	if swim:
		m = 6 if interior else 5
	elif interior:
		m = 3
	if m != cam_mode:
		cam_mode = m
		_sph.radius = float(CAM_MODES[m][1])


func _in_interior(p: Vector3) -> bool:
	if sector_boxes == null:
		sector_boxes = _build_sector_boxes()
	for sb in sector_boxes:
		var box: AABB = sb[1]
		if box.has_point(p):
			# Dach über dem Kopf bestätigt den Innenraum (Sektorhülle kann Vorplätze einschließen)
			var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 12.0, 1)
			q.exclude = target.exclude_rids()
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				return true
	return false


func _build_sector_boxes() -> Array:
	var out: Array = []
	var m := Game.current_mission()
	var orig = m.get("orig") if m and "orig" in m else null
	if orig == null or not ("objects" in orig):
		return out
	var by_sector := {}
	for o in orig.objects:
		var par := String((o as Dictionary).get("parent", ""))
		if not par.begins_with("sector ") or par == "Backdrop sector":
			continue
		var n: Node3D = orig.nodes.get(String(o.get("name", "")))
		if n == null or not n.is_inside_tree():
			continue
		for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
			if not (mi is MeshInstance3D):
				continue
			var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			if by_sector.has(par):
				var cur: AABB = by_sector[par]
				ab = cur.merge(ab)
			by_sector[par] = ab
	for k in by_sector:
		var box: AABB = by_sector[k]
		# Sektoren mit Gelände/Großflächen (> 80 m) sind keine Innenräume
		if box.size.x < 80.0 and box.size.z < 80.0 and box.size.y > 1.5:
			out.append([k, box])
	return out


var _binoc_last := false
var _model_last: Node3D
var _zoom_last := false
var _vm_aim_last := false


func _apply_head_visibility() -> void:
	var valid := is_instance_valid(target) and target.alive
	var binoc := valid and target.using_binoculars
	fpv_active = valid and _want_fpv(zoomed())
	if is_instance_valid(target) and target.model:
		# 1. Person: eigene Figur aus (die FPV-Hände ersetzen sie)
		target.model.visible = not fpv_active
		target.model.head.visible = not fpv_active
		target.model.set_weapon_visible(not fpv_active)
	_viewmodel.visible = fpv_active and not binoc and not scope_hides_vm


## Ego-Ansicht gewünscht: 1.-Person-Modus, Fernglas, Zoom – und bei gehaltenem Zielen mit einer Zoomwaffe auch
## während Nachladen/Repetieren/Feuerpause (Zoom kurz aus), damit die Ansicht nicht in die 3. Person und zurück
## springt (Scharfschützen-Glitch 16.10.2026). Nicht im Fahrzeug.
func _want_fpv(z: bool) -> bool:
	if not is_instance_valid(target) or target.vehicle != null:
		return false
	if mode == Mode.FIRST or target.using_binoculars or z:
		return true
	if not target.aiming or target.tool != "" or target.heal_time_left > 0.0 or target.is_throwing():
		return false
	var w := target.current_weapon()
	if w == null or w.data.slot == WeaponData.Slot.GRENADE or w.data.action == WeaponData.Action.MELEE:
		return false
	return not OrigWeapons.available() or not _zoom_info().is_empty()


## Zielfernrohr-Overlay (Absehen 0–3) deckt das Bild ab: Ego-Waffe ausblenden, sonst ruckt sie beim Schuss
## (Schuss-/Repetieranimation „aimshot“) sichtbar durch die Okularöffnung (Glitch beim Scharfschützenschuss).
var scope_hides_vm := false


## Zoom aktiv: Zielen mit einer Waffe mit Zoomdaten (items.sav Verhalten 5). Pistolen haben im Original keine
## Zoomdaten -> kein Zoom; in der 1. Person heben sie die Waffe nur in die Zielhaltung (FPV „…Aim“).
func zoomed() -> bool:
	return _aim_ready() and (not OrigWeapons.available() or not _zoom_info().is_empty())


## FPV-Waffe in Zielhaltung (Zoom oder 1. Person mit gehaltener rechter Maustaste).
func _vm_aim() -> bool:
	return fpv_active and _aim_ready()


func _aim_ready() -> bool:
	if not is_instance_valid(target) or not target.alive or not target.aiming or target.vehicle != null:
		return false
	var w := target.current_weapon()
	if w == null or target.tool != "" or w.data.slot == WeaponData.Slot.GRENADE or w.data.action == WeaponData.Action.MELEE:
		return false
	return not w.is_reloading() and not target.is_throwing() and target.heal_time_left <= 0.0


## Zoomdaten der Waffe {"scope", "fov_deg"} (leer = ohne Zoom).
func _zoom_info() -> Dictionary:
	var w: Weapon = target.current_weapon() if is_instance_valid(target) else null
	if w == null:
		return {}
	return OrigWeapons.zoom(w.data, target.team)


## Overlay-Typ für das HUD: 0–3 Zielfernrohr, 4 Fernglas, -1 keins.
func optic_overlay() -> int:
	if not is_instance_valid(target) or not target.alive:
		return -1
	if target.using_binoculars:
		return int(OrigWeapons.item_zoom(BINOC_ITEM).get("scope", 4))
	if zoomed() and _zoom_t > 0.95:
		var sc := int(_zoom_info().get("scope", 5))
		if sc >= 0 and sc <= 3:
			return sc
	return -1


# --- Viewmodel (1. Person): Original-FPV-Modell (Hände + Waffe) mit FpvAnims.sav-Animationen -------------

var _viewmodel: Node3D
var _vm_weapon: Node3D
var _vm_anim: AnimationPlayer
var _vm_info: Dictionary = {}
var _vm_clip := ""
var _vm_hold := false              ## Zielhaltung halten (letztes Bild der Zielanimation)
var _vm_queue: Array = []          ## [[Aktion, Dauer], …] (z. B. Wegstecken + Ziehen)
var _vm_prop: Node3D               ## Verbandskasten in der Hand
var _vm_kick := 0.0
var _vm_bob := 0.0
const VM_HIP := Vector3(0.17, -0.2, -0.42)
const VM_AIM := Vector3(0.0, -0.085, -0.3)   ## Platzhalter: Kimme/Korn auf der Blickachse
## Improvisiertes Panzerfaust-Nachladen (Vorgabe Auftraggeber, Bazooka-Clip #FPVBazReload auf dem Panzerfaust-
## Modell): der Clip führt die Hände für das hinten offene Bazooka-Rohr bis vor das Gesicht -> Modell während des
## Nachladens weiter vorn/unten zeigen [D].
const FPV_RELOAD_OFFSET := {"w_panzerfpv": Vector3(0.04, -0.12, -0.30)}
var _vm_key := ""
var _vm_retract := 0.0             ## Rückzug bei Wandnähe (nur ohne z_clip_scale)


func _on_weapon_changed(w: Weapon) -> void:
	if is_instance_valid(_vm_weapon):
		_vm_weapon.queue_free()
	_vm_weapon = null
	_vm_anim = null
	_vm_info = {}
	_vm_clip = ""
	_vm_hold = false
	_vm_fix = Vector3.INF
	_vm_queue.clear()
	_vm_key = ""
	_vm_tool = ""
	if is_instance_valid(target) and target.tool != "":
		_build_tool_vm(target.tool)
		return
	if w == null:
		return
	var key := OrigWeapons.fpv_key(w.data, target.team)
	var fpv := OrigWeapons.fpv_instance(key, fpv_hands())
	if fpv:
		_vm_no_clip(fpv)
		_vm_key = key
		_vm_weapon = fpv
		_vm_info = OrigWeapons.fpv_info(key)
		_viewmodel.add_child(fpv)
		_vm_anim = fpv.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _vm_anim:
			_vm_anim.animation_finished.connect(_on_vm_finished)
			for an in _vm_anim.get_animation_list():
				_vm_anim.get_animation(an).loop_mode = Animation.LOOP_NONE
		_vm_play("arm")
		return
	if w.data.slot == WeaponData.Slot.GRENADE:
		return
	# PLATZHALTER ohne FPV-Modell im Cache: Weltmodell bzw. Primitive mit Hand-Klötzen
	_vm_weapon = SoldierModel.build_weapon_mesh(w.data, true, target.team)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.8, 0.63, 0.5)
	var hands: Array = [] if _vm_weapon.has_meta("orig") else [Vector3(0.0, -0.06, 0.02), Vector3(0.0, -0.05, -w.data.model_length * 0.38)]
	for p in hands:
		var h := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 0.1)
		h.mesh = b
		h.material_override = skin
		h.position = p
		_vm_weapon.add_child(h)
	for mi in _vm_weapon.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_no_clip(_vm_weapon)
	_vm_weapon.position = VM_HIP
	_viewmodel.add_child(_vm_weapon)


## Hilfsmittel in der 1. Person (Waffe weggesteckt): Original-FPV-Modell mit Händen und FpvAnims (Mine
## w_antimanfpv), sonst das Original-Weltmodell sauber vor der Kamera (Verband, Sprengladung) [D].
var _vm_tool := ""
const VM_TOOL_POS := Vector3(0.1, -0.16, -0.38)
const VM_TOOL_ROT := Vector3(0.45, 0.35, 0.0)
## Größe vor der Kamera (Sprengladung w_explosive füllt sonst das halbe Bild) [D]
const VM_TOOL_SCALE := {"explosive": 0.5, "medkit": 0.8}


func _build_tool_vm(tool_key: String) -> void:
	_vm_tool = tool_key
	var key := String(Soldier.TOOL_FPV.get(tool_key, ""))
	var fpv := OrigWeapons.fpv_instance(key, fpv_hands())
	if fpv:
		_vm_no_clip(fpv)
		_vm_key = key
		_vm_weapon = fpv
		_vm_info = OrigWeapons.fpv_info(key)
		_viewmodel.add_child(fpv)
		_vm_anim = fpv.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _vm_anim:
			_vm_anim.animation_finished.connect(_on_vm_finished)
			for an in _vm_anim.get_animation_list():
				_vm_anim.get_animation(an).loop_mode = Animation.LOOP_NONE
		_vm_play("arm")
		return
	_vm_weapon = SoldierModel.prop_instance(target.tool_model_name(tool_key))
	for mi in _vm_weapon.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_no_clip(_vm_weapon)
	_vm_weapon.position = VM_TOOL_POS + Vector3(0.0, -0.25, 0.0)    # kommt von unten ins Bild (Ziehen)
	_vm_weapon.rotation = VM_TOOL_ROT
	_vm_weapon.scale = Vector3.ONE * float(VM_TOOL_SCALE.get(tool_key, 1.0))
	_viewmodel.add_child(_vm_weapon)


## Aktives Ego-Modell (Tests): FPV-Schlüssel bzw. Hilfsmittel des Platzhalters.
func viewmodel_info() -> Dictionary:
	return {"key": _vm_key, "tool": _vm_tool, "valid": is_instance_valid(_vm_weapon),
		"visible": _viewmodel.visible and is_instance_valid(_vm_weapon) and _vm_weapon.visible}


## Hände-Modell der Ego-Ansicht passend zur getragenen Uniform (hd2.exe 0x4922A0: FPV-Modell des Uniform-
## Gegenstands aus items.sav, „w_default“ -> FPV_hands); "" = Standard-Hände im FPV-Modell.
func fpv_hands() -> String:
	if not is_instance_valid(target) or target.model == null or not is_instance_valid(target.model.orig_figure):
		return ""
	var fig: Node3D = target.model.orig_figure
	return OrigWeapons.fpv_hands_for(String(fig.get_meta("figure_model", String(fig.name))))


## Ego-Waffe ragt nicht durch Wände: Materialien mit verkleinerter Clip-Tiefe (BaseMaterial3D.z_clip_scale, für
## Viewmodels vorgesehen) – Waffe und Hände werden vor der Welt gezeichnet, Größe/Projektion bleiben gleich.
const VM_Z_CLIP := 0.2
var vm_no_clip_count := 0          ## angepasste Oberflächen des aktuellen FPV-Modells (Tests)


func _vm_no_clip(root: Node) -> void:
	vm_no_clip_count = 0
	for mi in [root] + root.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if not (mat is BaseMaterial3D):
				continue
			var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			if not ("use_z_clip_scale" in dup):
				return
			dup.set("use_z_clip_scale", true)
			dup.set("z_clip_scale", VM_Z_CLIP)
			m.set_surface_override_material(i, dup)
			vm_no_clip_count += 1


## FPV-Aktion abspielen (Variante nach Original-Anteil zufällig); duration > 0 passt das Tempo an.
func _vm_play(action: String, duration: float = -1.0) -> bool:
	if _vm_anim == null:
		return false
	var lst: Array = (_vm_info.get("actions", {}) as Dictionary).get(action, [])
	if lst.is_empty():
		return false
	var clip := String(lst[0][0])
	if lst.size() > 1:
		var r := randi() % 100
		for v in lst:
			clip = String(v[0])
			if r < int(v[1]):
				break
	if not _vm_anim.has_animation(clip):
		return false
	var length := _vm_anim.get_animation(clip).length
	var speed: float = length / duration if duration > 0.0 else 1.0
	_vm_clip = clip
	_vm_hold = action == "aim"
	_vm_anim.play(clip, 0.08, speed)
	return true


## Zielhaltung: letztes Bild der Zielanimation (nach einem Schuss im Zoom wieder einnehmen).
func _vm_hold_aim() -> void:
	if _vm_play("aim"):
		_vm_anim.seek(_vm_anim.get_animation(_vm_clip).length, true)
		_vm_anim.pause()
		_vm_clip = ""


var _vm_fix := Vector3.INF


## Versatz, der die Oberkante der FPV-Waffe (vorn, Mitte) auf die Blickachse legt (Viewmodel-Raum, unskaliert).
func _measure_sight() -> Vector3:
	var gun := _vm_weapon.find_child("fpv_weapon", true, false) as Node3D
	if gun == null:
		return Vector3.ZERO
	var inv := _viewmodel.global_transform.affine_inverse()
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for mi in [gun] + gun.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var ab: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		for i in 8:
			var p: Vector3 = xf * ab.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
	if not mn.is_finite():
		return Vector3.ZERO
	var cur := _vm_weapon.position
	return -Vector3((mn.x + mx.x) * 0.5 - cur.x, mx.y - cur.y, 0.0)


func _vm_has(action: String) -> bool:
	return not (_vm_info.get("actions", {}) as Dictionary).get(action, []).is_empty()


func _on_vm_finished(_name: StringName) -> void:
	if not _vm_queue.is_empty():
		var nx: Array = _vm_queue.pop_front()
		_vm_play(String(nx[0]), float(nx[1]))
		return
	_vm_clip = ""


## Ruhe: Leerlaufanimation (bzw. „…LST“ bei leerem Magazin) oder beim Zoomen das letzte Bild der Zielanimation.
func _vm_idle() -> void:
	if _vm_anim == null or _vm_clip != "" or (_vm_anim.is_playing() and not _vm_hold):
		return
	var w := target.current_weapon()
	if _vm_aim():
		if not _vm_hold:
			_vm_hold_aim()
		return
	var act: String = "idle_last" if w and w.in_mag <= 0 and w.data.slot != WeaponData.Slot.GRENADE and _vm_has("idle_last") else "idle"
	_vm_play(act)


func _on_shot(w: Weapon) -> void:
	_vm_kick = 1.0
	if _vm_anim == null:
		return
	var last := w.in_mag <= 0
	var act: String = "aimshot" if _vm_aim() and _vm_has("aimshot") else "shot"
	if last and _vm_has(act + "_last"):
		act += "_last"
	_vm_queue.clear()
	_vm_play(act)


func _on_action(kind: String, duration: float) -> void:
	match kind:
		"reload":
			_vm_queue.clear()
			var rl: Array = (_vm_info.get("actions", {}) as Dictionary).get("reload", [])
			var idle: Array = (_vm_info.get("actions", {}) as Dictionary).get("idle", [])
			if not rl.is_empty() and not idle.is_empty() and rl[0][0] == idle[0][0] and _vm_has("disarm") and _vm_has("arm"):
				# Panzerfaust (Original ohne Nachladen): alte wegstecken, neue ziehen – Dauer im Verhältnis 0,8 : 2,4
				var ln: Dictionary = _vm_info.get("lengths", {})
				var d1 := float(ln.get(String(((_vm_info["actions"] as Dictionary)["disarm"] as Array)[0][0]), 0.8))
				var d2 := float(ln.get(String(((_vm_info["actions"] as Dictionary)["arm"] as Array)[0][0]), 2.4))
				var k := duration / maxf(d1 + d2, 0.1)
				_vm_play("disarm", d1 * k)
				_vm_queue.append(["arm", d2 * k])
			else:
				_vm_play("reload", duration)
		"draw":
			_vm_play("arm")
		"throw":
			# Granate in der Hand: FPV-Wurf so getaktet, dass sie zum selben Zeitpunkt die Hand verlässt
			var left: float = target._throw_left if is_instance_valid(target) else 0.0
			var w := target.current_weapon()
			# B-012: Schnellwurf (G) mit Waffe in der Hand – für den Wurf das Granaten-FPV-Modell zeigen und dessen
			# Wurfclip abspielen, danach wieder die Waffe ziehen (vorher nur Wegstecken/Ziehen der Waffe = kein Wurf)
			var gw: Weapon = target.weapons[WeaponData.Slot.GRENADE] if target.weapons.size() > WeaponData.Slot.GRENADE else null
			if w and w.data.slot != WeaponData.Slot.GRENADE and gw and left > 0.0 and not OrigWeapons.fpv_info(OrigWeapons.fpv_key(gw.data, target.team)).is_empty():
				_on_weapon_changed(gw)
				w = gw
				var back := w
				var tw := target.current_weapon()
				get_tree().create_timer(maxf(duration, left + 0.3), false).timeout.connect(func():
					if is_instance_valid(target) and target.current_weapon() == tw and _vm_key == OrigWeapons.fpv_key(back.data, target.team):
						_on_weapon_changed(tw))
			var rel := float(_vm_info.get("release", 0.0))
			if w and w.data.slot == WeaponData.Slot.GRENADE and rel > 0.0 and left > 0.0:
				var ln2: Dictionary = _vm_info.get("lengths", {})
				var shot: Array = (_vm_info.get("actions", {}) as Dictionary).get("shot", [])
				var full: float = float(ln2.get(String(shot[0][0]), rel)) if not shot.is_empty() else rel
				_vm_play("shot", full * left / rel)
			elif _vm_has("disarm"):
				_vm_play("disarm", 0.4)
				_vm_queue.append(["arm", maxf(duration - 0.4, 0.4)])
		"tool_use":
			# Hilfsmittel abgelegt: FPV-Ablegen (FPVAntimanShot), danach wieder Ziehen falls noch vorrätig
			_vm_queue.clear()
			if not _vm_play("shot", duration) and is_instance_valid(_vm_weapon) and _vm_anim == null:
				_vm_weapon.position += Vector3(0.0, -0.2, 0.05)
			elif _vm_has("arm"):
				_vm_queue.append(["arm", -1.0])
		"heal":
			_set_vm_prop(true)
		"heal_end":
			_set_vm_prop(false)
			_vm_play("arm")


## Verbandskasten vor der Kamera statt der Waffe (kein FPV-Modell im Original) [D].
func _set_vm_prop(on: bool) -> void:
	if is_instance_valid(_vm_prop):
		_vm_prop.queue_free()
	_vm_prop = null
	if is_instance_valid(_vm_weapon):
		_vm_weapon.visible = not on
	if on:
		_vm_prop = OrigWeapons.world_model(Soldier.MEDKIT_MODEL)
		if _vm_prop:
			_vm_prop.position = Vector3(0.06, -0.13, -0.36)
			_vm_prop.rotation = Vector3(0.5, 0.3, 0.0)
			for mi in _vm_prop.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_viewmodel.add_child(_vm_prop)


func _update_viewmodel(delta: float) -> void:
	if _viewmodel.visible and not target.alive:
		_apply_head_visibility()
	# Waffenstellung (OrigEmplacement): keine Ego-Waffe/-Hände, man blickt über das Stellungsmodell (CAMERAFPV)
	var mnt = target.get("mounted")
	if is_instance_valid(mnt):
		_viewmodel.visible = false
	elif fpv_active and not _viewmodel.visible and not target.using_binoculars and not scope_hides_vm and target.alive:
		_viewmodel.visible = true
	if not _viewmodel.visible or not is_instance_valid(_vm_weapon):
		return
	# FPV-Modell mit eigenem Sichtfeld (65° bzw. 40° beim Zoomen) unter der Weltkamera: Skalierung in x/y um
	# tan(Welt/2)/tan(Modell/2) ergibt dieselbe Projektion.
	var model_fov := OrigWeapons.vfov(lerpf(FPV_MODEL_FOV_H, FPV_MODEL_ZOOM_FOV_H, _zoom_t))
	var s := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(model_fov) * 0.5)
	_viewmodel.scale = Vector3(s, s, 1.0)
	if _vm_anim:
		_vm_idle()
		_vm_kick = maxf(_vm_kick - delta * 9.0, 0.0)
		# Vorgabe Auftraggeber (Pistolen-Zoom): die Original-Zielhaltung liegt tiefer – Visierlinie (Oberkante
		# der Waffe vorn) einmalig vermessen und auf die Bildmitte schieben
		var fix := Vector3.ZERO
		if bool(_zoom_info().get("vorgabe", false)) and _vm_aim():
			if _vm_fix == Vector3.INF and _vm_hold and not _vm_anim.is_playing():
				_vm_fix = _measure_sight()
			if _vm_fix != Vector3.INF:
				fix = _vm_fix * _zoom_t
		if FPV_RELOAD_OFFSET.has(_vm_key) and _vm_reloading():
			fix += FPV_RELOAD_OFFSET[_vm_key]
		fix += Vector3(0.0, -0.5, 0.6) * _wall_retract(delta)
		_vm_weapon.position = _vm_weapon.position.lerp(fix, clampf(delta * 12.0, 0.0, 1.0))
		return
	if _vm_tool != "":
		# Hilfsmittel ohne FPV-Modell: ruhig vor der Kamera mit leichtem Wippen
		_vm_bob += delta * target.current_speed() * 3.2
		var tbob := Vector3(sin(_vm_bob) * 0.01, absf(cos(_vm_bob)) * 0.008, 0.0)
		var twant := VM_TOOL_POS + tbob + Vector3(0.0, -0.5, 0.6) * _wall_retract(delta)
		_vm_weapon.position = _vm_weapon.position.lerp(twant, clampf(delta * 10.0, 0.0, 1.0))
		return
	# Platzhalter-Viewmodel
	var w := target.current_weapon()
	var aim := zoomed()
	var base: Vector3 = VM_AIM if aim else VM_HIP
	_vm_bob += delta * target.current_speed() * 3.2
	var bob := Vector3(sin(_vm_bob) * 0.012, absf(cos(_vm_bob)) * 0.01, 0.0) * (0.3 if aim else 1.0)
	var reload_drop: Vector3 = Vector3(0, -0.12, 0.05) if w and w.is_reloading() else Vector3.ZERO
	var kick := Vector3(0, 0.01, 0.06) * _vm_kick
	var want := base + bob + reload_drop + kick + Vector3(0.0, -0.5, 0.6) * _wall_retract(delta)
	_vm_weapon.position = _vm_weapon.position.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
	_vm_weapon.rotation.x = _vm_kick * 0.08 + (0.5 if w and w.is_reloading() else 0.0) * 0.6
	_vm_kick = maxf(_vm_kick - delta * 9.0, 0.0)


## Nachladeclip des FPV-Modells läuft (auch die Wegstecken/Ziehen-Folge der Einwegwerfer).
func _vm_reloading() -> bool:
	if _vm_anim == null or not _vm_anim.is_playing():
		return false
	var rl: Array = (_vm_info.get("actions", {}) as Dictionary).get("reload", [])
	for v in rl:
		if String(v[0]) == String(_vm_anim.current_animation):
			return true
	return false


## Ohne z_clip_scale (ältere Engine): Waffe bei Wandnähe zurückziehen (0..1), Strahl 0,7 m entlang der Blickachse.
func _wall_retract(delta: float) -> float:
	if vm_no_clip_count > 0 or not is_instance_valid(target):
		_vm_retract = 0.0
		return 0.0
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 0.7, 1)
	q.exclude = target.exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var want := 0.0
	if not hit.is_empty():
		want = clampf(1.0 - from.distance_to(hit.position) / 0.7, 0.0, 1.0)
	_vm_retract = move_toward(_vm_retract, want, delta * 6.0)
	return _vm_retract * 0.35


# --- Kamera je Bild ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var z := zoomed()
	var binoc := target.using_binoculars
	if binoc != _binoc_last or target.model != _model_last or z != _zoom_last or fpv_active != (target.alive and _want_fpv(z)):
		_binoc_last = binoc
		_model_last = target.model   # Modell kann sich ändern (Uniformwechsel)
		_zoom_last = z
		_apply_head_visibility()
	var va := _vm_aim()
	if va != _vm_aim_last:
		_vm_aim_last = va
		if _vm_anim:
			if va:
				_vm_queue.clear()
				_vm_play("aim")
			elif _vm_hold or _vm_clip == "":
				# Zoom aus: Zielanimation rückwärts (Daim); läuft schon eine andere Aktion (Nachladen, Wurf), bleibt sie
				_vm_queue.clear()
				if not _vm_play("daim"):
					_vm_clip = ""
					_vm_hold = false
	# Zoomverlauf über die Dauer der Zielanimation (0,4 s) [P]
	var zt := 0.4
	_zoom_t = move_toward(_zoom_t, 1.0 if (z or binoc) else 0.0, delta / zt)
	var zinfo := _zoom_info()
	var want_fov := base_fov()
	if binoc:
		want_fov = OrigWeapons.vfov(float(OrigWeapons.item_zoom(BINOC_ITEM).get("fov_deg", 10.0)))
	elif z and not zinfo.is_empty():
		want_fov = OrigWeapons.vfov(float(zinfo["fov_deg"]))
	elif z and target.current_weapon():
		want_fov = target.current_weapon().data.aim_fov    # ohne Original-Cache: Designwert
	elif target.aiming and target.vehicle != null and target.current_weapon():
		want_fov = target.current_weapon().data.aim_fov
	_fov = lerpf(base_fov(), want_fov, _zoom_t) if (z or binoc or _zoom_t > 0.0) and target.vehicle == null else lerpf(_fov, want_fov, clampf(delta * 10.0, 0.0, 1.0))
	camera.fov = _fov
	var ov := optic_overlay()
	var cover := ov >= 0 and ov <= 3
	if cover != scope_hides_vm:
		scope_hides_vm = cover
		_viewmodel.visible = fpv_active and not binoc and not scope_hides_vm

	var yaw := target.look_yaw
	var pitch := target.look_pitch
	var want_dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	# Richtung mit begrenzter Drehrate nachführen (16π rad/s – praktisch sofort, nur bei Sprüngen sichtbar)
	var ang := _dir.angle_to(want_dir)
	if ang > 0.0001:
		_dir = _dir.slerp(want_dir, minf(1.0, TURN_RATE * delta / ang)).normalized()
	var look := _dir + _sway(delta, z or binoc)
	var lpitch := asin(clampf(look.normalized().y, -1.0, 1.0))
	var lyaw := atan2(-look.x, -look.z)

	if fpv_active:
		var eye: Vector3 = target.model.camera_point(true) if target.model and target.model.orig_figure else target.eye_position()
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		_pivot.global_position = _safe_pivot(eye + right * target.lean * 0.35, PIVOT_MARGIN_FPV)
		_pivot.global_rotation = Vector3(lpitch, lyaw, -target.lean * 0.12)
		_arm.spring_length = 0.0
		_arm.position = Vector3.ZERO
		_dist = 0.0
		_update_viewmodel(delta)
	elif target.vehicle != null:
		_arm.add_excluded_object(target.vehicle.get_rid())
		# Verfolgerkamera: Fahrer über der Fahrzeugmitte (Abstand nach Fahrzeuggröße, leicht nachgeführt gegen
		# Federungszittern), Mitfahrer/Schützen über dem eigenen Sitz
		var vp: Vector3 = target.eye_position() + Vector3.UP * 1.4
		var vd := 6.5
		if target.seat_index == 0 and target.vehicle.has_method("chase_pivot"):
			vp = target.vehicle.chase_pivot()
			vd = target.vehicle.chase_distance()
			if _pivot.global_position.distance_to(vp) < 3.0:
				vp = _pivot.global_position.lerp(vp, clampf(delta * 14.0, 0.0, 1.0))
		_pivot.global_position = vp
		_pivot.global_rotation = Vector3(lpitch, lyaw, 0.0)
		_arm.position = Vector3.ZERO
		_dist = move_toward(_dist, vd, CAM3_SPEED * delta)   # Verfolgerkamera hinter dem Fahrzeug
		_arm.spring_length = _dist
	else:
		# 3. Person: Drehpunkt = Dummy camera3RD, Kamera auf der Blickachse dahinter (gamecam.set Satz 1/3/4/5/6)
		_select_cam_mode()
		var cm: Array = CAM_MODES[cam_mode]
		var p: Vector3 = target.model.camera_point(false) if target.model else target.eye_position() + Vector3.UP * 0.2
		var right2 := Vector3(cos(yaw), 0, -sin(yaw))
		_pivot.global_position = _safe_pivot(p + right2 * target.lean * 0.35, _sph.radius + _arm.margin)
		var lim := float(cm[2])
		_pivot.global_rotation = Vector3(clampf(lpitch, -lim, lim), lyaw, 0.0)
		_arm.position = Vector3.ZERO
		_dist = move_toward(_dist, float(cm[0]), float(cm[3]) * delta)
		_arm.spring_length = _dist


## Drehpunkt nicht hinter/in Wände legen (Fix A1 24.10.2026): Dummy camera3RD/cameraFPV und der Lehnversatz liegen
## außerhalb der Figurenkapsel (liegend cameraFPV 0,6 m vor der Wurzel) und gerieten an Wänden in/hinter die Geometrie –
## der SpringArm prüft erst AB dem Drehpunkt, die Kamera sah dann durch die Wand. Strahl von der Körperachse (senkrecht
## unter/über dem Drehpunkt auf Drehpunkthöhe) zum Drehpunkt, bei Treffer davor mit Abstand `margin` [E: Original
## 0x468130 stellt die Kamera mit der Kugel aus gamecam.set frei, die Prüfung ab dem Figurenframe ist nicht dekodiert].
const PIVOT_MARGIN_FPV := 0.12     ## > Ecken der Nahebene (near 0,05 m, 16:9, FOV ≤ 75° ≈ 0,08 m)


func _safe_pivot(p: Vector3, margin: float) -> Vector3:
	var base := Vector3(target.global_position.x, p.y, target.global_position.z)
	var d := p - base
	var len := d.length()
	if len < 0.001 or Game.cli.has("collision_legacy"):
		return p
	var q := PhysicsRayQueryParameters3D.create(base, p + d / len * margin, 1)
	q.exclude = target.exclude_rids()
	q.hit_back_faces = true
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty():
		return p
	return base + d / len * maxf(0.0, base.distance_to(h.position) - margin)


## Wackeln der Blickrichtung beim Zoomen (hd2.exe 0x466970, Kamera +0x290): Amplitude A = 0,002 bei Kimme/Korn;
## mit Zielfernrohr/Fernglas wächst A bis 0,008 (4e-6 je ms) bzw. sinkt in Ruhe bis 0,0015 (5e-6 je ms) [P: Ruhe =
## stillstehen]; Ausschlag (2 − Schießen/100) · A · (sin(cos(0,0018 t)), cos(sin(0,0008 t + 3))).
func _sway(delta: float, on: bool) -> Vector3:
	if not on:
		_sway_ms = 0.0
		return Vector3.ZERO
	var ms := delta * 1000.0
	_sway_ms += ms
	var sc := int(_zoom_info().get("scope", 5))
	if not target.using_binoculars and sc == 5:
		_sway_amp = 0.002
	elif target.is_moving():
		_sway_amp = minf(_sway_amp + ms * 4e-6, 0.008)
	else:
		_sway_amp = maxf(_sway_amp - ms * 5e-6, 0.0015)
	var skill: float = clampf(target.skill_shooting / 100.0, 0.0, 1.0) if target.skill_shooting >= 0.0 else 0.5
	var amp := (2.0 - skill) * _sway_amp
	var right := _dir.cross(Vector3.UP).normalized()
	var up := right.cross(_dir).normalized()
	return right * amp * sin(cos(0.0018 * _sway_ms)) + up * amp * cos(sin(0.0008 * _sway_ms + 3.0))


## Weltpunkt unter dem Fadenkreuz (Bildschirmmitte).
func crosshair_point(max_dist := 800.0) -> Vector3:
	var dir := -camera.global_basis.z
	var from := camera.global_position
	# In 3. Person erst ab Höhe des Soldaten prüfen (nichts zwischen Kamera und Figur treffen)
	if is_instance_valid(target) and not fpv_active:
		from += dir * maxf((target.eye_position() - from).dot(dir), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, 1 | Hitbox.LAYER)
	q.collide_with_areas = true
	if is_instance_valid(target):
		q.exclude = target.exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from + dir * max_dist
	return hit.position
