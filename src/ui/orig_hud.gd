class_name OrigHud
extends Control
## In-Game-HUD nach dem Original (MODELS\gameinterface.4ds; Rekonstruktion orig_cache/ui/hud/hud_spec.json,
## docs/re_notes_hud.md). Elemente sind im Original für 4:3 angelegt (x 0..1, y 0..1); hier in einem
## 4:3-Rahmen auf voller Fensterhöhe platziert. Bei Breitbild bleibt die Truppleiste mittig, Kompass
## hängt am linken, Waffenwahl am rechten Rand. Originalgrafiken nur aus dem lokalen orig_cache
## (bevorzugt KI-hochskalierte Fassungen textures_4k/_hd).
## Live-Daten: aktiver Soldat, KI-Steuerung, Gesundheit/Ausdauer/Tarnung (Leisten), Entdeckung,
## Haltung, Gangart, Kompass, Waffe in der Hand/auf der Schulter (+ Munition), Waffenwahl beim Wechsel.

const GROUP_ANCHOR := {"compass": "left", "weapon_select": "right", "squad_bar": "center"}
## Ausgeblendet: Mehrspieler-Wappen, Ausklappmenüs, Platzhalter ohne Laufzeitdaten
const SKIP := ["mpaxis", "mpallied", "signals", "rollmenu"]
const WEAPON_ICONS := {
	&"thompson": "ii_us-m1thomp-m", &"sten": "ii_br-sten-m", &"enfield": "ii_br-enflmk4-m",
	&"garand": "ii_us-m1garnd-m", &"bren": "ii_br-brengun-m", &"colt": "ii_us-clt1911-m",
	&"kar98k": "ii_ge-karb98k-m", &"mp40": "ii_ge-mp40-m", &"stg44": "ii_ge-mp44-m", &"p08": "ii_ge-parab-m",
}

var mission: Mission
var dir := ""
var elements := {}          ## Name -> {node, rect, group, uv, tex}
var _tex_cache := {}
var _ammo: Label
var _weapon_select_t := 0.0
var _last_slot := -1
var _last_active: Soldier


static func available() -> bool:
	return FileAccess.file_exists(OrigLevel.cache_root() + "/ui/hud/hud_spec.json")


func setup(m: Mission) -> void:
	mission = m
	name = "OrigHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dir = OrigLevel.cache_root() + "/ui/hud"
	var spec = LsRuntime._read_json(dir + "/hud_spec.json")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var groups: Array = spec.get("default_hud_groups", [])
	var els: Array = []
	for e in spec.get("elements", []):
		var g: String = e.get("group", "")
		if not GROUP_ANCHOR.has(g) or not groups.has(g) or not e.get("onscreen_in_file", false):
			continue
		if SKIP.has(e.get("name", "")) or e.get("rect") == null:
			continue
		els.append(e)
	# kleinere z = weiter vorn -> zuerst die hinteren zeichnen
	els.sort_custom(func(a, b): return float(a.get("z", 0.0)) > float(b.get("z", 0.0)))
	for e in els:
		var node: Control
		var tfile: String = e["texture"] if e.get("texture") is String else ""
		var uvs: Array = e["uv_px"] if e.get("uv_px") is Array else []
		var tex := _atlas(tfile, uvs)
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			node = tr
		else:
			var cr := ColorRect.new()
			cr.color = Color(0.75, 0.15, 0.1, 0.85)   # z. B. Sichtbarkeitsanzeige (farbiges Rechteck)
			node = cr
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.name = String(e["name"]).validate_node_name()
		add_child(node)
		elements[e["name"]] = {"node": node, "rect": e["rect"], "group": e["group"], "uv": uvs, "tex": tfile}
	_ammo = Label.new()
	_ammo.add_theme_font_size_override("font_size", 14)
	_ammo.add_theme_color_override("font_color", Color(0.12, 0.1, 0.07))
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ammo)
	resized.connect(_layout)
	_layout()


func _load(file: String) -> Texture2D:
	if file == "":
		return null
	if _tex_cache.has(file):
		return _tex_cache[file]
	var path := dir + "/" + file
	for suffix: String in ["_4k", "_hd"]:
		var alt := dir + "/" + file.get_base_dir() + suffix + "/" + file.get_file()
		if FileAccess.file_exists(alt):
			path = alt
			break
	var tx: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			img.generate_mipmaps()
			tx = ImageTexture.create_from_image(img)
	_tex_cache[file] = tx
	return tx


## uv_px bezieht sich auf die Originalgröße der Textur; bei HD-Fassungen proportional umrechnen.
func _atlas(file: String, uv: Array) -> Texture2D:
	var tx := _load(file)
	if tx == null or uv.size() != 4:
		return tx
	var orig_size := _orig_size(file, tx)
	var k := Vector2(tx.get_size()) / orig_size
	var at := AtlasTexture.new()
	at.atlas = tx
	at.region = Rect2(uv[0] * k.x, uv[1] * k.y, (uv[2] - uv[0]) * k.x, (uv[3] - uv[1]) * k.y)
	return at


var _size_cache := {}

func _orig_size(file: String, fallback: Texture2D) -> Vector2:
	if _size_cache.has(file):
		return _size_cache[file]
	var s := Vector2(fallback.get_size())
	var p := dir + "/" + file
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img:
			s = Vector2(img.get_size())
	_size_cache[file] = s
	return s


## Bildschirmrechteck eines Elements (4:3-Rahmen auf voller Höhe, Gruppenanker).
func screen_rect(r: Array, group: String) -> Rect2:
	var h := size.y
	var fw := h * 4.0 / 3.0
	var x0 := (size.x - fw) * 0.5
	match GROUP_ANCHOR.get(group, "center"):
		"left":
			x0 = 0.0
		"right":
			x0 = size.x - fw
	return Rect2(x0 + r[0] * fw, r[1] * h, (r[2] - r[0]) * fw, (r[3] - r[1]) * h)


func _layout() -> void:
	for nm in elements:
		var e: Dictionary = elements[nm]
		var rr := screen_rect(e["rect"], e["group"])
		var n: Control = e["node"]
		n.position = rr.position
		n.size = rr.size
		n.pivot_offset = rr.size * 0.5
		e["screen"] = rr
	if elements.has("i_hands"):
		var hr: Rect2 = elements["i_hands"]["screen"]
		_ammo.position = Vector2(hr.position.x, hr.position.y - hr.size.y * 0.95)
		_ammo.size = Vector2(hr.size.x * 2.05, hr.size.y * 0.9)


func _show_el(nm: String, visible_: bool) -> void:
	if elements.has(nm):
		(elements[nm]["node"] as Control).visible = visible_


## Senkrechte Leiste von unten füllen (Gesundheit/Ausdauer/Tarnung).
func _fill(nm: String, frac: float) -> void:
	if not elements.has(nm):
		return
	var e: Dictionary = elements[nm]
	var n: Control = e["node"]
	var full: Rect2 = e.get("screen", Rect2())
	frac = clampf(frac, 0.0, 1.0)
	n.visible = frac > 0.0
	n.size = Vector2(full.size.x, full.size.y * frac)
	n.position = Vector2(full.position.x, full.end.y - n.size.y)
	var tr := n as TextureRect
	if tr and tr.texture is AtlasTexture and e["uv"].size() == 4:
		var at := tr.texture as AtlasTexture
		if not e.has("region"):
			e["region"] = at.region
		var reg: Rect2 = e["region"]
		at.region = Rect2(reg.position.x, reg.end.y - reg.size.y * frac, reg.size.x, reg.size.y * frac)


func _process(delta: float) -> void:
	if mission == null or elements.is_empty():
		return
	var sq := mission.squad
	var active: Soldier = mission.controller.active if mission.controller else null
	# --- Truppleiste: 6 Felder, belegt mit den Kadermitgliedern ---
	for i in 6:
		var sfx := "%02d" % i
		var m: Soldier = sq.members[i] if i < sq.members.size() else null
		var used := m != null
		_show_el("soldier" + sfx, used)
		_show_el("photo" + sfx, used)
		_show_el("player" + sfx if i > 0 else "player00", used and m == active)
		_show_el("select" + sfx if i > 0 else "select", false)
		_show_el("AImode" + sfx, used and m.alive and m != active)
		for nm in ["mind", "command", "ear", "silence", "medic", "healthcr"]:
			_show_el(nm + sfx, false)
		_show_el("healthbar" + (sfx if i > 0 else ""), false)
		_show_el("staminabar" + sfx if i > 0 else "staminabar", false)
		_show_el("disguisebar" + sfx if i > 0 else "disguisebar", false)
		_show_el("visibility" + sfx, false)
		if not used:
			for nm in ["health", "stamina", "disguise"]:
				_show_el(nm + sfx, false)
			continue
		var crit := m.alive and m.health < m.max_health * 0.3
		_fill("health" + sfx, m.health / m.max_health if not crit else 0.0)
		if crit:
			_fill("healthcr" + sfx, m.health / m.max_health)
		_fill("stamina" + sfx, m.stamina / 100.0 if m.alive else 0.0)
		_fill("disguise" + sfx, 1.0 if m.disguised else 0.0)
		var photo: Dictionary = elements.get("photo" + sfx, {})
		if photo:
			var want := "faces/x_fc_death.png" if not m.alive else "faces/x_f_%03d.png" % (i + 1)
			if photo.get("face", "") != want:
				photo["face"] = want
				(photo["node"] as TextureRect).texture = _load(want)
	if active == null:
		return
	# Entdeckung des aktiven Soldaten (farbiges Rechteck, Breite = Aufmerksamkeit der Gegner)
	var idx := sq.members.find(active)
	var vis := 0.0
	for e in mission.enemies:
		if e.alive:
			vis = maxf(vis, (e.get_node("Perception") as Perception).awareness.get(active, 0.0))
	if idx >= 0 and idx < 6:
		var vn := "visibility%02d" % idx
		if elements.has(vn):
			var ve: Dictionary = elements[vn]
			var full: Rect2 = ve["screen"]
			var n: Control = ve["node"]
			n.visible = vis > 0.02
			n.size = Vector2(full.size.x * clampf(vis, 0.0, 1.0), full.size.y)
			n.position = full.position
	# --- linkes Feld: Haltung und Gangart ---
	_show_el("pkneel", active.stance == Soldier.Stance.CROUCH)
	_show_el("play", active.stance == Soldier.Stance.PRONE)
	var mm := active.move_mode
	var moving := active.current_speed() > 0.3
	for pair in [["mwalk", mm == Soldier.MoveMode.WALK or mm == Soldier.MoveMode.SNEAK or active.stance != Soldier.Stance.STAND],
			["mrun", mm == Soldier.MoveMode.JOG and active.stance == Soldier.Stance.STAND],
			["msprint", mm == Soldier.MoveMode.RUN and active.stance == Soldier.Stance.STAND]]:
		if elements.has(pair[0]):
			(elements[pair[0]]["node"] as Control).modulate.a = 1.0 if pair[1] and moving else 0.3
	# --- Kompass: Ziffernblatt dreht gegen die Blickrichtung, Nadel zeigt nach oben ---
	if elements.has("kmpscvr"):
		(elements["kmpscvr"]["node"] as Control).rotation = active.look_yaw
	for i in 8:
		_show_el("kmps_rd%02d" % i, false)
		_show_el("kmps_bl%02d" % i, false)
	_show_el("kul_us", false)
	_show_el("kul_en", false)
	# --- rechtes Feld: Waffe in der Hand / auf der Schulter ---
	var w := active.current_weapon()
	_icon("i_hands", w)
	var other: Weapon = null
	for wp in active.weapons:
		if wp and wp != w and wp.data.slot != WeaponData.Slot.GRENADE:
			other = wp
			break
	_icon("i_shoulder", other)
	if w:
		if w.data.slot == WeaponData.Slot.GRENADE:
			_ammo.text = "%s ×%d" % [w.data.display_name, w.total_ammo()]
		else:
			_ammo.text = ("NACHLADEN…" if w.is_reloading() else "%d / %d" % [w.in_mag, w.reserve])
	else:
		_ammo.text = ""
	# --- Waffenwahl oben rechts: nur kurz nach einem Wechsel sichtbar ---
	if active != _last_active or active.current_slot != _last_slot:
		_weapon_select_t = 2.0 if _last_active == active else 0.0
		_last_active = active
		_last_slot = active.current_slot
	_weapon_select_t = maxf(_weapon_select_t - delta, 0.0)
	var show_sel := _weapon_select_t > 0.0
	for nm in ["tabl03", "selector_weapon", "drkr1", "drkr2"]:
		_show_el(nm, show_sel)
	for i in 3:
		var wp: Weapon = active.weapons[i] if i < active.weapons.size() else null
		_show_el("select_weapon%02d" % i, show_sel)
		if show_sel:
			_icon("select_weapon%02d" % i, wp)
	if show_sel and elements.has("selector_weapon") and elements.has("select_weapon%02d" % active.current_slot):
		var target: Rect2 = elements["select_weapon%02d" % active.current_slot]["screen"]
		var sel: Control = elements["selector_weapon"]["node"]
		sel.position = target.position - Vector2(target.size.x * 0.03, target.size.y * 0.06)


func _icon(nm: String, w: Weapon) -> void:
	if not elements.has(nm):
		return
	var e: Dictionary = elements[nm]
	var tr := e["node"] as TextureRect
	if tr == null:
		return
	var key := String(WEAPON_ICONS.get(w.data.id, "")) if w else ""
	if e.get("icon", "-") == key:
		return
	e["icon"] = key
	if key == "":
		tr.texture = _atlas(e["tex"], e["uv"])     # leere Blase (Original X_BUBBLE)
	else:
		tr.texture = _load("inventory/%s.png" % key)
