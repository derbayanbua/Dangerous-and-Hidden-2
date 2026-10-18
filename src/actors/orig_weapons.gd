class_name OrigWeapons
extends RefCounted
## Original-Waffenmodelle aus dem lokalen Cache (orig_cache/weapons, erzeugt von tools/export_weapons.py
## aus der HD2-Installation des Nutzers; Zuordnung Gegenstand -> Weltmodell aus TABLES\items.sav).
## Befestigung wie im Original (hd2.exe 0x7B9260, docs/re_notes_weapons.md): Kind des Hand-Dummys hw1,
## Rotation SetDir((1,0,0), 0) im hw1-Raum (Lauf entlang +X von hw1, Waffen-Y = hw1-Y),
## Position so, dass der Waffen-Dummy RW (Griff der rechten Hand) auf hw1 liegt.
## Ohne Cache liefern alle Funktionen null/leer -> Platzhalter in SoldierModel.

const SUBDIR := "/weapons"

static var _table: Dictionary = {}
static var _loaded := false
static var _templates: Dictionary = {}   ## Modellname -> Node3D-Vorlage (außerhalb des Baums) oder null


static func table() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(OrigLevel.cache_root() + SUBDIR + "/weapons.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if typeof(d) == TYPE_DICTIONARY:
			_table = d
	return _table


static func available() -> bool:
	return not table().is_empty()


## Originalgegenstand (items.sav-Nummer) zu einer Waffe der Datenbank. Schalldämpfer-Varianten nutzen das
## Grundmodell (im Original gibt es kein K98k-/MP40-Schalldämpfermodell); Messer je Seite (56 GER / 57 GB).
static func item_for(data: WeaponData, team: int = -1) -> int:
	if data == null:
		return -1
	var id := String(data.id)
	if id.begins_with("o_"):
		return int(id.substr(2))
	match id:
		"kar98k_sd":
			return 4
		"mp40_sd":
			return 18
		"knife":
			return 56 if team == 1 else 57     # 1 = Soldier.TEAM_AXIS
	for k in WeaponDB.ORIG_IDS:
		if WeaponDB.ORIG_IDS[k] == data.id:
			return int(k)
	return -1


static func info(data: WeaponData, team: int = -1) -> Dictionary:
	var it := item_for(data, team)
	if it < 0:
		return {}
	return (table().get("items", {}) as Dictionary).get(str(it), {})


## Haltesatz (TABLES\anim.sav) der Waffe: hand / smg / pistol / rifle / mg / bazooka.
static func hold_set(data: WeaponData, team: int = -1) -> String:
	var s := String(info(data, team).get("set", ""))
	if s != "":
		return s
	match data.slot:
		WeaponData.Slot.SIDEARM:
			return "pistol"
		WeaponData.Slot.LAUNCHER:
			return "bazooka"
		WeaponData.Slot.MELEE, WeaponData.Slot.GRENADE:
			return "hand"
	if data.action == WeaponData.Action.AUTO:
		return "mg" if data.weight > 8.0 else "smg"
	return "rifle"


## Clipname der Haltung (Satz, "calm"/"aim", Haltung 0 stehen / 1 hocken / 2 liegen) oder "".
static func hold_clip(set_name: String, mode: String, stance: int) -> String:
	var sets: Dictionary = table().get("hold_sets", {})
	var lst: Array = (sets.get(set_name, {}) as Dictionary).get(mode, [])
	if lst.is_empty():
		return ""
	return String(lst[clampi(stance, 0, lst.size() - 1)])


## Clip einer Waffenaktion aus TABLES\anim.sav (Oberkörperschicht h_*): "reload", "draw", "holster", "fire",
## "throw", "throw_move" je Haltung. Nachladen: Variante je Gegenstand (weapons.json "reload_variant").
static func action_clip(data: WeaponData, team: int, action: String, stance: int) -> String:
	if data == null:
		return ""
	var hs: Dictionary = (table().get("hold_sets", {}) as Dictionary).get(hold_set(data, team), {})
	var lst: Array = hs.get(action, [])
	if lst.is_empty():
		return ""
	if action == "reload":
		var v := clampi(int(info(data, team).get("reload_variant", 0)), 0, lst.size() - 1)
		lst = lst[v]
	return String(lst[clampi(stance, 0, lst.size() - 1)])


## Länge (s) und ggf. Auslösezeitpunkt "release" (Wurf) eines Clips aus weapons.json.
static func clip_info(clip: String) -> Dictionary:
	return (table().get("clips", {}) as Dictionary).get(clip, {})


## Zoom beim Zielen (items.sav Verhalten 5): {"scope": Overlay 0–3 Zielfernrohr / 4 Fernglas / 5 Kimme+Korn,
## "fov_deg": Original-FOV in Grad}. Leer = Waffe ohne Zoom (Pistolen, Granaten, Messer).
static func zoom(data: WeaponData, team: int = -1) -> Dictionary:
	var z: Dictionary = info(data, team).get("zoom", {})
	if z.is_empty() and data != null and available() and hold_set(data, team) == "pistol":
		return PISTOL_ZOOM
	return z


## Vorgabe Auftraggeber: Pistolen zoomen ebenfalls (Original ohne Verhalten 5) – Kimme/Korn, FOV wie das
## Karabiner-98k-Visier (48°); die Visierlinie wird in der Ego-Ansicht auf die Bildmitte gelegt (CameraRig).
const PISTOL_ZOOM := {"scope": 5, "fov_deg": 48.0, "vorgabe": true}


static func item_zoom(item: int) -> Dictionary:
	return ((table().get("items", {}) as Dictionary).get(str(item), {}) as Dictionary).get("zoom", {})


## Original-FOV (Grad, horizontal bei 4:3 – LS3D-Kamera [P]) -> Godot-FOV (vertikal).
static func vfov(h_deg: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(h_deg) * 0.5) * 0.75))


## Overlay-Grafik (gameinterface.4ds: sniper + Absehen cross1–4 bzw. Fernglas-Maske scope) oder null.
static var _overlay_tex: Dictionary = {}


static func overlay(scope: int) -> Texture2D:
	if _overlay_tex.has(scope):
		return _overlay_tex[scope]
	var tex: Texture2D = null
	var rel := String((table().get("overlays", {}) as Dictionary).get(str(scope), ""))
	if rel != "":
		var img := Image.load_from_file(OrigLevel.cache_root() + SUBDIR + "/" + rel)
		if img:
			tex = ImageTexture.create_from_image(img)
	_overlay_tex[scope] = tex
	return tex


## --- 1. Person (C_FirstPersonView): FPV-Hände + FPV-Waffe mit Original-Animationen (TABLES\FpvAnims.sav) ---

## Schlüssel des FPV-Modells (orig_cache/weapons/fpv/<key>.glb) oder "".
static func fpv_key(data: WeaponData, team: int = -1) -> String:
	return String(info(data, team).get("fpv", ""))


## {"actions": {Aktion: [[Clip, Anteil], …]}, "lengths": {Clip: s}, "release": s} des FPV-Modells.
static func fpv_info(key: String) -> Dictionary:
	return (table().get("fpv", {}) as Dictionary).get(key, {})


## Neue Instanz des FPV-Modells (Kameraraum: Blick −Z, oben +Y) mit AnimationPlayer, oder null.
## hands: Hände-Modell der Uniform (fpv_hands_for), "" = die im FPV-Modell enthaltenen Standard-Hände (FPV_hands).
static func fpv_instance(key: String, hands: String = "") -> Node3D:
	if key == "":
		return null
	var tk := "fpv/" + key
	if not _templates.has(tk):
		_templates[tk] = _load(OrigLevel.cache_root() + SUBDIR + "/fpv/" + key + ".glb")
	var tpl: Node3D = _templates[tk]
	if tpl == null:
		return null
	var n := tpl.duplicate() as Node3D
	var flash := n.find_child("flash", true, false) as Node3D
	if flash:
		flash.visible = false
	if hands != "" and hands != FPV_HANDS_DEFAULT:
		_swap_hands(n, hands)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


const FPV_HANDS_DEFAULT := "fpv_hands"


## Hände-Modell (FPV_hands / FPV_hands_r …, klein) zur Original-Figur bzw. Uniform: items.sav-Uniform mit diesem
## Figurenmodell -> deren FPV-Modell (export_weapons.py „fpv_hands“), sonst "".
static func fpv_hands_for(figure: String) -> String:
	var m: Dictionary = table().get("fpv_hands", {})
	var k := figure.to_lower()
	while k.length() >= 3:
		if m.has(k):
			return String(m[k])
		k = k.substr(0, k.length() - 1)      # Knotennamen mit Zählsuffix (z. B. „ge01a2“)
	return ""


## Haut-Mesh der Standard-Hände im FPV-Modell gegen das der Uniform tauschen (gleiches Skelett „Bip01 …“;
## Bindungen per Knochenname, orig_cache/weapons/fpv/hands_<name>.glb).
static func _swap_hands(n: Node3D, hands: String) -> bool:
	var hk := "fpvhands/" + hands
	if not _templates.has(hk):
		_templates[hk] = _load(OrigLevel.cache_root() + SUBDIR + "/fpv/hands_" + hands + ".glb", true)
	var src: Node3D = _templates[hk]
	if src == null:
		return false
	var donor: MeshInstance3D = null
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			donor = mi
			break
	var dst: MeshInstance3D = null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			dst = mi
			break
	if donor == null or dst == null:
		return false
	dst.mesh = donor.mesh
	dst.skin = donor.skin
	for i in donor.mesh.get_surface_count():
		dst.set_surface_override_material(i, donor.get_active_material(i))
	dst.set_meta("fpv_hands", hands)
	return true


## Neue Instanz des Original-Weltmodells, Griff (RW) im Ursprung, Lauf entlang -Z, oben +Y.
## Meta "muzzle" = Knoten der Mündung (flash/blsdum). null, wenn kein Modell im Cache.
static func instance(data: WeaponData, team: int = -1) -> Node3D:
	var model := String(info(data, team).get("model", ""))
	if model == "":
		return null
	if not _templates.has(model):
		_templates[model] = _load(OrigLevel.cache_root() + SUBDIR + "/" + model + ".glb")
	var tpl: Node3D = _templates[model]
	if tpl == null:
		return null
	var scene := tpl.duplicate() as Node3D
	var root := Node3D.new()
	root.name = "OrigWeapon"
	root.set_meta("orig", true)
	root.add_child(scene)
	var grip := _rel(scene, scene.find_child("RW", true, false) as Node3D)
	scene.position = -grip.origin
	var flash := scene.find_child("flash", true, false) as Node3D
	if flash:
		flash.visible = false            # Billboard des Mündungsfeuers (Effekte zeigen eigenes)
	var muzzle: Node3D = flash
	if muzzle == null:
		# ohne Mündungsfeuer-Billboard (Werfer: blsdum sitzt hinten = Abgasstrahl): vorderstes Modellende
		var front := 0.0
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var ab: AABB = _rel(root, mi as Node3D) * (mi as MeshInstance3D).get_aabb()
			front = minf(front, ab.position.z)
		muzzle = Node3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0, 0, front)
		root.add_child(muzzle)
	root.set_meta("muzzle", muzzle)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## Original-Modell (Weltgegenstand, Modellname wie in items.sav) unverändert, oder null.
static func world_model(model: String) -> Node3D:
	var key := model.to_lower()
	if key == "":
		return null
	if not _templates.has(key):
		var tpl0 := _load(OrigLevel.cache_root() + SUBDIR + "/" + key + ".glb")
		if tpl0 == null:
			# nicht als Gegenstand exportiert (z. B. Sprengladung w_explosive): Level-Modellordner der Missionen
			for d in LEVEL_MODEL_DIRS:
				var p := "%s/%s/models/%s.glb" % [OrigLevel.cache_root(), d, key]
				if FileAccess.file_exists(p):
					tpl0 = OrigLevel.parse_glb(p)
					if tpl0:
						break
		_templates[key] = tpl0
	var tpl: Node3D = _templates[key]
	if tpl == null:
		return null
	var n := tpl.duplicate() as Node3D
	var flash := n.find_child("flash", true, false) as Node3D
	if flash:
		flash.visible = false
	return n


## Missionsordner mit Original-Modellen von Hilfsmitteln, die tools/export_weapons.py nicht exportiert
## (w_explosive, w_dynamite, d_explbag; Weltmodell der Sprengladung aus items.sav 67/68).
const LEVEL_MODEL_DIRS := ["africa1", "arctic2", "czech2", "africa1_obj", "burma1", "normandy", "tutorial"]


## Erstes vorhandene Original-Modell aus names ("" = keins im Cache).
static func first_model(names: Array) -> String:
	for nm in names:
		var probe := world_model(String(nm))
		if probe:
			probe.free()
			return String(nm)
	return ""


## Lage der Waffe im Raum des Hand-Dummys hw1 (SetDir((1,0,0), 0): Lauf -Z -> +X, Y bleibt).
static func hand_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)


## Vorlagen freigeben (Missionsende), sonst bleiben Mesh-Instanzen bis Programmende bestehen.
static func release() -> void:
	for k in _templates:
		var n = _templates[k]
		if is_instance_valid(n) and not (n as Node).is_inside_tree():
			(n as Node).free()
	_templates.clear()


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


static func _load(path: String, named_binds: bool = false) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.base_path = path.get_base_dir()
	state.use_named_skin_binds = named_binds
	if doc.append_from_file(path, state) != OK:
		push_error("glTF nicht ladbar: " + path)
		return null
	return doc.generate_scene(state) as Node3D
