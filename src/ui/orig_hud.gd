class_name OrigHud
extends Control
## In-Game-HUD nach dem Original (MODELS\gameinterface.4ds; Rekonstruktion orig_cache/ui/hud/hud_spec.json,
## docs/re_notes_hud.md). Elemente sind im Original für 4:3 angelegt (x 0..1, y 0..1); hier in einem
## 4:3-Rahmen auf voller Fensterhöhe platziert. Bei Breitbild bleibt die Truppleiste mittig, Kompass
## hängt am linken, Waffenwahl am rechten Rand. Originalgrafiken nur aus dem lokalen orig_cache
## (bevorzugt KI-hochskalierte Fassungen textures_4k/_hd).
## Live-Daten: aktiver Soldat, KI-Steuerung, Gesundheit/Ausdauer/Tarnung (Leisten), Entdeckung,
## Haltung, Gangart, Kompass, Waffe in der Hand/auf der Schulter (+ Munition), Waffenwahl beim Wechsel.
##
## Rechtes Feld tabl02 wie hd2.exe 0x4A9010/0x4A9530 (docs/re_notes_hud.md §3a): i_hands = Symbol des Gegenstands in
## der Hand, i_shoulder = Symbol des Gegenstands auf der Schulter (items.sav-Symbol +0x2C „wi_*“ + „.bmp“, 0x7DF650 –
## Waffenbilder, nicht die Munitionssymbole „ii_*-m“); Textblock über dem Feld mit vier Zeilen: 0 Name des
## Gegenstands in der Hand, 1 „%d/%d“ Schuss in der Waffe / Magazine im Inventar (Hand), 2 dasselbe für die
## Schulterwaffe, 3 „%d“ neben dem Granatensymbol des Feldes. Aktualisierung je Bild (Original: bei Wertänderung).

const GROUP_ANCHOR := {"compass": "left", "weapon_select": "right", "squad_bar": "center", "vehicle": "left", "info": "right"}
## Ausgeblendet: Mehrspieler-Wappen, Ausklappmenüs, Platzhalter ohne Laufzeitdaten
const SKIP := ["mpaxis", "mpallied", "signals", "rollmenu"]
## Waffen ohne Originalgegenstand (eigene Datenbankeinträge): Gegenstandsnummer für Symbol/Name
const ITEM_FALLBACK := {&"stg44": 26, &"sten": 21, &"bren": 19}
## Hilfsmittel (Soldier.tool) -> Originalgegenstand (items.sav)
const TOOL_ITEMS := {"medkit": 54, "explosive": 68, "mine": 251, "binoculars": 99}
## Textzeilen im Feld tabl02 (Anteile des Feldrechtecks x0, y0, x1, y1; Ausrichtung; Schrift × Feldhöhe) – Lage
## nach den Linien/Symbolen der Feldgrafik (Patronen links oben, Granate rechts oben) [P], Inhalt [B]
const AMMO_LINES := {
	"hands": [0.22, 0.14, 0.74, 0.44, HORIZONTAL_ALIGNMENT_LEFT, 0.25],
	"grenades": [0.84, 0.0, 1.0, 0.24, HORIZONTAL_ALIGNMENT_LEFT, 0.17],
	"name": [0.04, 0.43, 0.60, 0.585, HORIZONTAL_ALIGNMENT_LEFT, 0.14],
	"shoulder": [0.56, 0.43, 0.97, 0.585, HORIZONTAL_ALIGNMENT_RIGHT, 0.14],
}

var mission: Mission
var dir := ""
var elements := {}          ## Name -> {node, rect, group, uv, tex}
var _tex_cache := {}
var _ammo: Label                 ## Zeile 1 (Hand: Schuss/Magazine), Kurzzugriff für Tests
var ammo_labels := {}            ## "name" / "hands" / "shoulder" / "grenades" -> Label
var hands_item := -1             ## Originalgegenstand in der Hand (Symbol i_hands), -1 = keiner
var shoulder_item := -1          ## Originalgegenstand auf der Schulter (Symbol i_shoulder)
var _weapon_select_t := 0.0
var _last_slot := -1
var _last_active: Soldier
var _timer_labels: Array[Label] = []
var _needle: Line2D
var _timer_acc := 0.0
var timers_shown: Array = []      ## [Bezeichnung, Sekunden] der angezeigten Zeitzünder (Tests)
## Verwundungs-Overlay „injury“ (hd2.exe 0x4AD250 ff.): bei Treffer zufällig einer von 7 Plätzen
## (AnimHit1–6 als Videotextur, Platz 7 leer), Deckkraft +4/s bis 0,5, dann −0,5/s bis 0
var injury: VideoStreamPlayer
var injury_alpha := 0.0
var injury_film := ""
var _inj_rising := false
var _inj_hooked: Soldier


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
		var en := String(e.get("name", ""))
		# Ergänzt (GAP Abschnitt 4): Tacho (Gruppe vehicle) und Zeitzünder-Liste (timer-explosive00–09)
		var extra := en in ["speed", "speed01"] or en.begins_with("timer-explosive")
		if not extra and (not GROUP_ANCHOR.has(g) or not groups.has(g) or not e.get("onscreen_in_file", false)):
			continue
		if g == "info" and not extra:
			continue           # Info-Spalte info00–09: Platzhalter ohne Laufzeitdaten
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
	for i in 10:
		var tl := Label.new()
		tl.name = "TimerText%02d" % i
		tl.add_theme_font_size_override("font_size", 12)
		tl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tl.visible = false
		add_child(tl)
		_timer_labels.append(tl)
	injury = VideoStreamPlayer.new()
	injury.name = "InjuryOverlay"
	injury.expand = true
	injury.loop = true
	injury.volume_db = -80.0
	injury.mouse_filter = Control.MOUSE_FILTER_IGNORE
	injury.visible = false
	add_child(injury)
	move_child(injury, 0)
	_needle = Line2D.new()
	_needle.name = "TachoNeedle"
	_needle.width = 2.0
	_needle.default_color = Color(0.75, 0.1, 0.05)
	_needle.visible = false
	add_child(_needle)
	for key in AMMO_LINES:
		var al := Label.new()
		al.name = "Ammo_" + String(key)
		al.add_theme_color_override("font_color", Color(0.12, 0.1, 0.07))
		al.horizontal_alignment = AMMO_LINES[key][4]
		al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		al.clip_text = true
		al.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(al)
		ammo_labels[key] = al
	_ammo = ammo_labels["hands"]
	resized.connect(_layout)
	_layout()


func _load(file: String) -> Texture2D:
	if file == "":
		return null
	if _tex_cache.has(file):
		return _tex_cache[file]
	var path := dir + "/" + file
	for suffix: String in Settings.texture_suffixes():
		if suffix == "":
			break
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
	if elements.has("tabl02"):
		var tr: Rect2 = elements["tabl02"]["screen"]
		for key in AMMO_LINES:
			var a: Array = AMMO_LINES[key]
			var al: Label = ammo_labels[key]
			al.position = tr.position + Vector2(a[0] * tr.size.x, a[1] * tr.size.y)
			al.size = Vector2((a[2] - a[0]) * tr.size.x, (a[3] - a[1]) * tr.size.y)
			al.add_theme_font_size_override("font_size", maxi(8, int(round(tr.size.y * float(a[5])))))


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
			var want := "faces/x_fc_death.png" if not m.alive else (
				"faces/x_f_%s.png" % String(SAS.store(int(m.get_meta("sas"))).get("portrait_id", "001"))
				if m.has_meta("sas") else "faces/x_f_%03d.png" % (i + 1))
			if photo.get("face", "") != want:
				photo["face"] = want
				(photo["node"] as TextureRect).texture = _load(want)
	_update_injury(active, delta)
	_timer_acc -= delta
	if _timer_acc <= 0.0:
		_timer_acc = 0.25           # Zeitzünder-Liste viermal je Sekunde (Baumsuche)
		_update_timers()
	_update_tacho(active)
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
	_update_compass_dots(active, delta)
	# --- rechtes Feld: Gegenstand in der Hand / auf der Schulter mit Munition (0x4A9530) ---
	_update_weapon_panel(active)
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


## Kompasspunkte der Teamkameraden (hd2.exe 0x493B30/0x493D10/0x4936C0/0x493860, nur Mehrspieler (0x982100 & 7)
## == 7): Vorlagen kul_us (blau) / kul_en (rot, Kennung des Soldaten +0x19C == 2 [P: Gegner]) bleiben ausgeblendet;
## je Kamerad eine Kopie auf dem Ring der Vorlage (Abstand Vorlage–Kompassmitte) in Richtung des Kameraden relativ
## zur Blickrichtung der Kamera (Winkel 0x7885B0, Lage sin/cos · Radius), Entfernung ohne Einfluss. Ein-/Ausblenden
## 0,001 je ms (1 s); tote Kameraden verblassen und werden entfernt; eigener Soldat ohne Punkt.
var compass_dots := {}            ## Soldier-Instanz-ID -> {node, alpha, soldier}


func _update_compass_dots(active: Soldier, delta: float) -> void:
	_show_el("kul_us", false)
	_show_el("kul_en", false)
	var mates: Array = Net.compass_mates(active) if Net.is_online and Net.has_method("compass_mates") else []
	if not elements.has("kul_us") or not elements.has("kmpscvr"):
		mates = []
	var seen := {}
	var cam := get_viewport().get_camera_3d()
	var tpl: Rect2 = elements["kul_us"].get("screen", Rect2()) if elements.has("kul_us") else Rect2()
	var dial: Rect2 = elements["kmpscvr"].get("screen", Rect2()) if elements.has("kmpscvr") else Rect2()
	var center := dial.get_center()
	var radius := tpl.get_center().distance_to(center)
	for s in mates:
		var key: int = (s as Soldier).get_instance_id()
		seen[key] = true
		if not compass_dots.has(key):
			var tr := TextureRect.new()
			tr.name = "CompassDot%d" % key
			var src: TextureRect = elements["kul_us"]["node"]
			tr.texture = src.texture
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tr)
			compass_dots[key] = {"node": tr, "alpha": 1.0, "soldier": s}
	for key in compass_dots.keys():
		var d: Dictionary = compass_dots[key]
		var s = d["soldier"]
		# lebende Kameraden einblenden, sonst (tot/entfernt/Seitenwechsel) ausblenden und danach entfernen
		var alpha: float = clampf(float(d["alpha"]) + (delta if seen.has(key) else -delta), 0.0, 1.0)
		d["alpha"] = alpha
		var n: TextureRect = d["node"]
		if alpha <= 0.0 or not is_instance_valid(s):
			n.queue_free()
			compass_dots.erase(key)
			continue
		var off := Vector2.ZERO
		if cam != null:
			var rel: Vector3 = (s as Soldier).global_position - cam.global_position
			var fwd := Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
			var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
			var v := Vector2(rel.dot(right), rel.dot(fwd))
			if v.length() > 1e-8:
				v = v.normalized()
			off = Vector2(v.x, -v.y) * radius
		n.size = tpl.size
		n.position = center + off - tpl.size * 0.5
		n.modulate.a = alpha
		n.visible = true


func _update_injury(active: Soldier, delta: float) -> void:
	if active != _inj_hooked:
		if is_instance_valid(_inj_hooked) and _inj_hooked.damaged.is_connected(_on_hurt):
			_inj_hooked.damaged.disconnect(_on_hurt)
		_inj_hooked = active
		if active:
			active.damaged.connect(_on_hurt)
	if not injury.visible:
		return
	injury.position = screen_rect([0.0, 0.0, 1.0, 1.0], "center").position
	injury.size = screen_rect([0.0, 0.0, 1.0, 1.0], "center").size
	if _inj_rising:
		injury_alpha += delta * 4.0
		if injury_alpha >= 0.5:
			injury_alpha = 0.5
			_inj_rising = false
	else:
		injury_alpha -= delta * 0.5
		if injury_alpha <= 0.0:
			injury_alpha = 0.0
			injury.stop()
			injury.visible = false
	injury.modulate.a = injury_alpha


## Treffer am aktiven Soldaten: zufälliger Platz 0–6 (rand() % 7); Platz 6 ohne Film = kein Overlay
func _on_hurt(_amount: float = 0.0, _zone: StringName = &"") -> void:
	show_injury(randi() % 7)


func show_injury(slot: int) -> void:
	var p: String = Game.movie_path("AnimHit%d" % (slot + 1)) if slot < 6 else ""
	if p == "":
		return
	var vs := VideoStreamTheora.new()
	vs.file = p
	injury.stream = vs
	injury_film = "AnimHit%d" % (slot + 1)
	injury_alpha = 0.0
	_inj_rising = true
	injury.visible = true
	injury.modulate.a = 0.0
	injury.play()


## Zeitzünder-Liste (timer-explosive00–09, von unten nach oben): laufende Zeitzünder mit Restzeit –
## eigene Sprengladungen (PlacedCharge), Original-Sprengplätze (OrigExplosive.countdown), Sprengsätze (ChargeSite)
func _update_timers() -> void:
	var list: Array = []
	for n in get_tree().get_nodes_in_group("interactables"):
		if "countdown" in n and float(n.get("countdown")) > 0.0:
			list.append([String(n.get("label")) if "label" in n else "Sprengsatz", float(n.get("countdown"))])
		elif n is ChargeSite and (n as ChargeSite).armed and not (n as ChargeSite).is_destroyed:
			list.append([(n as ChargeSite).prompt.get_slice(":", 0), (n as ChargeSite).time_left])
	if is_inside_tree() and mission:
		for c in mission.find_children("*", "PlacedCharge", true, false):
			var pc := c as PlacedCharge
			if pc.kind == "explosive" and not pc._done:
				list.append([SAS.item_label(68) if SAS.available() else "Sprengstoff", maxf(PlacedCharge.FUSE - pc._t, 0.0)])
	list.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	timers_shown = list.slice(0, 10)
	for i in 10:
		var nm := "timer-explosive%02d" % i
		var on := i < timers_shown.size()
		_show_el(nm, on)
		var tl: Label = _timer_labels[i] if i < _timer_labels.size() else null
		if tl == null:
			continue
		tl.visible = on and elements.has(nm)
		if tl.visible:
			var r: Rect2 = elements[nm].get("screen", Rect2())
			tl.position = r.position + Vector2(4, 0)
			tl.size = r.size - Vector2(8, 0)
			var t := float(timers_shown[i][1])
			tl.text = "%s  %d:%02d" % [String(timers_shown[i][0]).substr(0, 18), int(t) / 60, int(ceil(t)) % 60]


## Tacho im Fahrzeug (Original speed/speedNN): Ziffernblatt mit Nadel, 0–120 km/h über 240° [P]
func _update_tacho(active: Soldier) -> void:
	var v: Node = active.vehicle if active and "vehicle" in active else null
	_show_el("speed", v != null)
	_show_el("speed01", false)
	_needle.visible = v != null and elements.has("speed")
	if not _needle.visible:
		return
	var kmh := 0.0
	if v is RigidBody3D:
		kmh = (v as RigidBody3D).linear_velocity.length() * 3.6
	var r: Rect2 = elements["speed"].get("screen", Rect2())
	var c := r.get_center()
	var ang := deg_to_rad(-210.0 + 240.0 * clampf(kmh / 120.0, 0.0, 1.0))
	_needle.points = PackedVector2Array([c, c + Vector2(cos(ang), sin(ang)) * r.size.x * 0.38])
	_needle.width = maxf(r.size.x * 0.025, 1.5)


## Originalgegenstand (items.sav-Nummer) einer Waffe, -1 wenn keiner.
static func weapon_item(w: Weapon, team: int = -1) -> int:
	if w == null:
		return -1
	var it := OrigWeapons.item_for(w.data, team)
	if it < 0:
		it = int(ITEM_FALLBACK.get(w.data.id, -1))
	return it


## Gegenstand auf der Schulter: die lange Waffe, die nicht in der Hand ist (Primärwaffe, sonst Raketenwerfer).
static func shoulder_weapon(s: Soldier) -> Weapon:
	var w: Weapon = s.current_weapon() if s.tool == "" else null
	for slot in [WeaponData.Slot.PRIMARY, WeaponData.Slot.LAUNCHER]:
		var wp: Weapon = s.weapons[slot] if slot < s.weapons.size() else null
		if wp and wp != w:
			return wp
	return null


## Textzeile „%d/%d“ (0x4A9420): Schuss in der Waffe / Magazine im Inventar (Raketenwerfer: Raketen); Granate in
## der Hand: 1 / übrige; ohne Munition (Messer, Fernglas) leer.
static func ammo_text(w: Weapon) -> String:
	if w == null or w.data.action == WeaponData.Action.MELEE:
		return ""
	if w.data.slot == WeaponData.Slot.GRENADE:
		var n := w.total_ammo()
		return "%d/%d" % [mini(n, 1), maxi(n - 1, 0)]
	var mags := w.reserve
	if w.data.magazine_size > 1:
		mags = int(ceil(float(w.reserve) / float(w.data.magazine_size)))
	return "%d/%d" % [w.in_mag, mags]


func _update_weapon_panel(s: Soldier) -> void:
	var w := s.current_weapon()
	var hand := -1
	var name_txt := ""
	var hand_txt := ""
	if s.tool != "":
		hand = int(TOOL_ITEMS.get(s.tool, -1))
		var n := 0
		match s.tool:
			"medkit":
				n = s.medkits
			"explosive":
				n = s.explosives
			"mine":
				n = s.mines
		hand_txt = "%d/%d" % [mini(n, 1), maxi(n - 1, 0)] if s.tool != "binoculars" else ""
		name_txt = SAS.item_label(hand) if hand >= 0 and SAS.available() else s.tool
	elif w:
		hand = weapon_item(w, s.team)
		hand_txt = ammo_text(w)
		name_txt = SAS.item_label(hand) if hand >= 0 and SAS.available() else w.data.display_name
		if name_txt == "" or name_txt.begins_with("#"):
			name_txt = w.data.display_name
	var sw := shoulder_weapon(s)
	hands_item = hand
	shoulder_item = weapon_item(sw, s.team)
	_item_icon("i_hands", hands_item)
	_item_icon("i_shoulder", shoulder_item)
	(ammo_labels["name"] as Label).text = name_txt
	(ammo_labels["hands"] as Label).text = hand_txt
	(ammo_labels["shoulder"] as Label).text = ammo_text(sw)
	var g: Weapon = s.weapons[WeaponData.Slot.GRENADE] if s.weapons.size() > WeaponData.Slot.GRENADE else null
	(ammo_labels["grenades"] as Label).text = "%d" % (g.total_ammo() if g else 0)


## Symbol eines Originalgegenstands (items.sav „icon“: Waffen wi_*, Hilfsmittel ii_*; Inventarbilder aus
## orig_cache/ui/menu/items bzw. ui/hud/inventory), "" wenn keines vorhanden.
func _item_icon_file(item: int) -> String:
	if item < 0 or not SAS.available():
		return ""
	var ic := String(SAS._item_data().get(item, {}).get("icon", "")).to_lower()
	if ic == "":
		return ""
	for cand in ["../menu/items/%s.png" % ic, "inventory/%s.png" % ic]:
		if FileAccess.file_exists(dir + "/" + cand):
			return cand
	return ""


func _item_icon(nm: String, item: int) -> void:
	if not elements.has(nm):
		return
	var e: Dictionary = elements[nm]
	var tr := e["node"] as TextureRect
	if tr == null:
		return
	var file := _item_icon_file(item)
	if e.get("icon", "-") == file:
		return
	e["icon"] = file
	if file == "":
		tr.texture = _atlas(e["tex"], e["uv"])     # leere Blase (Original X_BUBBLE)
	else:
		tr.texture = _load(file)


## Waffenwahl oben rechts (select_weapon00–02): Waffensymbole wie im rechten Feld.
func _icon(nm: String, w: Weapon) -> void:
	var team: int = _last_active.team if is_instance_valid(_last_active) else -1
	_item_icon(nm, weapon_item(w, team))


## Symboldatei eines Feldes (Tests): "" = leere Blase.
func icon_of(nm: String) -> String:
	return String((elements.get(nm, {}) as Dictionary).get("icon", ""))
