class_name OrigHud
extends Control
## In-Game-HUD nach dem Original (MODELS\gameinterface.4ds; Rekonstruktion orig_cache/ui/hud/hud_spec.json,
## docs/re_notes_hud.md). Elemente sind im Original für 4:3 angelegt (x 0..1, y 0..1); hier in einem
## 4:3-Rahmen auf voller Fensterhöhe platziert. Bei Breitbild Kompass
## hängt am linken, Waffenwahl am rechten Rand (B-014: Truppleiste links, Waffenfeld rechts, s. anchor_of). Originalgrafiken nur aus dem lokalen orig_cache
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
	_build_extras(spec)
	Events.soldier_damaged.connect(_on_soldier_damaged)
	Events.noise_emitted.connect(_on_noise)
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


## B-014 (Vorgabe Auftraggeber): bei Breitbild hängen die Spielanzeigen an den echten Bildschirmrändern statt im
## 4:3-Bereich der Mitte. Truppleiste: Haltungsfeld tabl01 + Soldatenfelder ab dem linken Rand (Abstände wie im
## Original), Waffenfeld tabl02 mit Hand/Schulter/Munition am rechten Rand. Bei 4:3 (und schmaler) unverändert,
## da der 4:3-Rahmen dann die ganze Breite ist.
const RIGHT_ELEMENTS := ["tabl02", "i_hands", "i_shoulder", "signals"]


## Anker eines Elements: Gruppenanker, in der Truppleiste je Element (links bzw. Waffenfeld rechts)
static func anchor_of(element: String, group: String) -> String:
	if group == "squad_bar":
		return "right" if RIGHT_ELEMENTS.has(element) else "left"
	return String(GROUP_ANCHOR.get(group, "center"))


## Bildschirmrechteck eines Elements (4:3-Rahmen auf voller Höhe, Anker „left“/„right“/„center“ bzw. Gruppenname).
func screen_rect(r: Array, group: String) -> Rect2:
	var h := size.y
	var fw := h * 4.0 / 3.0
	var x0 := (size.x - fw) * 0.5
	var anchor: String = group if group in ["left", "right", "center"] else String(GROUP_ANCHOR.get(group, "center"))
	match anchor:
		"left":
			x0 = 0.0
		"right":
			x0 = size.x - fw
	return Rect2(x0 + r[0] * fw, r[1] * h, (r[2] - r[0]) * fw, (r[3] - r[1]) * h)


func _layout() -> void:
	for nm in elements:
		var e: Dictionary = elements[nm]
		var rr := screen_rect(e["rect"], anchor_of(String(nm), String(e["group"])))
		var n: Control = e["node"]
		n.position = rr.position
		n.size = rr.size
		n.pivot_offset = rr.size * 0.5
		e["screen"] = rr
	_layout_extras()
	if elements.has("tabl02") and OrigFonts.available():
		_layout_ammo_orig(elements["tabl02"]["screen"])
	elif elements.has("tabl02"):
		var tr: Rect2 = elements["tabl02"]["screen"]
		for key in AMMO_LINES:
			var a: Array = AMMO_LINES[key]
			var al: Label = ammo_labels[key]
			al.position = tr.position + Vector2(a[0] * tr.size.x, a[1] * tr.size.y)
			al.size = Vector2((a[2] - a[0]) * tr.size.x, (a[3] - a[1]) * tr.size.y)
			al.add_theme_font_size_override("font_size", maxi(8, int(round(tr.size.y * float(a[5])))))


## B-003: Textblock tabl02 mit Original-Textstilen 0x36–0x39 (hd2.exe 0x641E30, Zuordnung 0x4A91BA ff. [B]): Schrift
## SMALL, schwarz, Höhe 0,015/0,025/0,018/0,018 der Bildhöhe, Ankerpunkt x/y als Anteil des Feldrechtecks
## (Name 0,05/0,59 links, Hand 0,2/0,45 links, Schulter 0,95/0,44 rechts, Granaten 0,95/0,165 rechts).
## y = Unterkante der Zeile [P] (passt zu Patronen-/Granatensymbol und Trennlinie der Feldgrafik).
const AMMO_STYLES := {"name": OrigFonts.ST_HUD_NAME, "hands": OrigFonts.ST_HUD_HANDS,
	"shoulder": OrigFonts.ST_HUD_SHOULDER, "grenades": OrigFonts.ST_HUD_GRENADES}
var orig_font := false             ## Tests: Originalschrift aktiv


func _layout_ammo_orig(tr: Rect2) -> void:
	var vs := size
	for key in AMMO_STYLES:
		var sid: int = AMMO_STYLES[key]
		var al: Label = ammo_labels[key]
		if not OrigFonts.apply(al, sid, vs.y, vs.x):
			continue
		orig_font = true
		var st := OrigFonts.style(sid)
		var px := float(OrigFonts.style_px(sid, vs.y)) * 1.15
		var ax := tr.position.x + float(st.get("x", 0.0)) * tr.size.x
		var ay := tr.position.y + float(st.get("y", 0.0)) * tr.size.y
		var right := int(st.get("halign", 1)) == 3
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		al.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var w := (ax - tr.position.x) if right else (tr.end.x - ax)
		if key == "name":
			w = tr.size.x * 0.55        # Name endet vor der Schulter-Munition derselben Zeile (abgeschnitten)
		al.position = Vector2(ax - w if right else ax, ay - px)
		al.size = Vector2(w, px)


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
		# grau hinterlegtes Feld = markierter Kamerad (Einzelauswahl 1–4, B-012; Frame select* aus gameinterface.4ds)
		_show_el("select" + sfx if i > 0 else "select", used and m.alive and m != active and sq.is_selected(m))
		_show_el("AImode" + sfx, used and m.alive and m != active)
		for nm in ["ear", "healthcr"]:
			_show_el(nm + sfx, false)
		_update_state_icons(i, m, m == active)
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
	_update_sectors(delta)
	_update_progress(active)
	_update_action_icon(active)
	_update_cross_name(active)
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
			# fix_a2_marker: Restzeit zuerst – das Feld ist nur ~0,116 des 4:3-Rahmens breit, „Bezeichnung  m:ss“ schnitt
			# die Zeit ab (ARCTIC2 „Platz für Sprengstoff“); Bezeichnung danach, abgeschnitten (clip_text)
			var secs := int(ceil(t))
			tl.text = "%d:%02d  %s" % [secs / 60, secs % 60, String(timers_shown[i][0])]
			tl.clip_text = true
			tl.add_theme_font_size_override("font_size", maxi(10, int(r.size.y * 0.55)))


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
	var bw := FieldInventory.back_weapon(s)      # B-018: zweite Langwaffe gleicher Art auf dem Rücken
	if bw:
		return bw
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
	_fit_label(ammo_labels["name"] as Label, name_txt)
	(ammo_labels["hands"] as Label).text = hand_txt
	(ammo_labels["shoulder"] as Label).text = ammo_text(sw)
	var g: Weapon = s.weapons[WeaponData.Slot.GRENADE] if s.weapons.size() > WeaponData.Slot.GRENADE else null
	(ammo_labels["grenades"] as Label).text = "%d" % (g.total_ammo() if g else 0)


## Text setzen und waagerecht stauchen, wenn er breiter als das Feld ist (Original-Bitmapschrift ist breiter als die alte
## Schrift → „M1 Thc…“ statt „M1 Thompson“). Stauchen statt Abschneiden [D]; ab 60 % Breite wird zusätzlich abgeschnitten.
func _fit_label(al: Label, txt: String) -> void:
	al.text = txt
	if al.scale != Vector2.ONE and al.has_meta("fit_base_w"):
		al.size.x = float(al.get_meta("fit_base_w"))   # vorheriges Stauchen zurücknehmen
	al.scale = Vector2.ONE
	var f := al.get_theme_font("font")
	if f == null or al.size.x <= 1.0:
		return
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, al.get_theme_font_size("font_size")).x
	if w <= al.size.x:
		return
	var k := maxf(0.6, al.size.x / w)
	var base := al.size.x
	al.size.x = base / k            # Feld rechnerisch verbreitern, dann auf die Originalbreite stauchen
	al.scale = Vector2(k, 1.0)
	al.set_meta("fit_base_w", base)


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


# =====================================================================================================================
# B-003: fehlende Original-Elemente (Belege/Status je Element in docs/status/backlog_b003.md)
# =====================================================================================================================

## Befehls-/Stimmungssymbole je Soldatenfeld (command*/mind*, Texturen der Vorlagen playerstate1_*/playerstate2_*,
## FUN_004b30e0 [B]). Zuordnung Befehl/Feuerregel → Symbol [P]: Folgen i_regrp (ps1_19), Halten i_guard (ps1_11),
## Bewegen i_move (ps1_10), Deckung i_kneel (ps1_17); Feuer frei i_aggres (ps2_11), Feuer halten i_passiv (ps2_09),
## auf mein Kommando i_defens (ps2_10). silence* = Schalldämpferwaffe [P], medic* = legt Verband an / wird verbunden [P].
const COMMAND_ICONS := {SquadBrain.Order.FOLLOW: "textures/i_regrp.png", SquadBrain.Order.HOLD: "textures/i_guard.png",
	SquadBrain.Order.MOVE: "textures/i_move.png", SquadBrain.Order.COVER: "textures/i_kneel.png"}
const MIND_ICONS := {SquadBrain.ROE.FIRE_AT_WILL: "textures/i_aggres.png", SquadBrain.ROE.HOLD_FIRE: "textures/i_passiv.png",
	SquadBrain.ROE.ON_MY_LEAD: "textures/i_defens.png"}
## Kontextaktion am Fadenkreuz (Vorlagen action00–37, 0x49B730 [B] Texturen; Auswahl nach Zieltyp [P], Lage [?]).
var action_icon: TextureRect
var action_icon_file := ""                ## Tests: aktuelles Aktionssymbol ("" = keins)
## Fortschrittsbalken (Gruppe progress: prgbrbk/prgbr01/shadow05/progress_name [B Namen]; Lage im Modell außerhalb des
## Bildes → waagerecht mittig, Höhe aus dem Modell [P]). Zeigt Arbeit (Entschärfen, Schloss, Zaun …), Verband und – Ergänzung
## [E] – die Restluft beim Tauchen (Original-Anzeige der Luft nicht gefunden).
var progress_value := -1.0                ## Tests: 0..1, −1 = aus
var progress_text := ""
var _prog_nodes := {}


## true, wenn der Original-Fortschrittsbalken (prgbr01) gebaut ist – hud.gd zeigt dann keine eigene Textzeile.
func has_progress_bar() -> bool:
	return _prog_nodes.has("prgbr01") and _prog_nodes["prgbr01"].has("node")
var _prog_label: Label
## Kompass-Sektoren (FUN_004947e0 [B]: Zähler 500 je Sektor, Abbau, Deckkraft ∝ Zähler). Auslöser [P]: rot = Treffer am
## aktiven Soldaten aus dieser Richtung, blau = gehörter Schuss/Explosion (nicht vom eigenen Trupp).
var sector_rd: Array[float] = [0, 0, 0, 0, 0, 0, 0, 0]
var sector_bl: Array[float] = [0, 0, 0, 0, 0, 0, 0, 0]
const SECTOR_TIME := 0.5
## cross_name (Gruppe crosshair [B]): Name des Kameraden unter dem Fadenkreuz [P].
var _cross_label: Label
var cross_name_text := ""


func _build_extras(spec: Dictionary) -> void:
	action_icon = TextureRect.new()
	action_icon.name = "ActionIcon"
	action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	action_icon.stretch_mode = TextureRect.STRETCH_SCALE
	action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_icon.visible = false
	add_child(action_icon)
	for e in spec.get("elements", []):
		var en := String(e.get("name", ""))
		if en in ["shadow05", "prgbrbk", "prgbr01"] and e.get("rect") is Array:
			var tex := _atlas(String(e.get("texture", "")), e["uv_px"] if e.get("uv_px") is Array else [])
			var tr := TextureRect.new()
			tr.name = "Progress_" + en
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.visible = false
			add_child(tr)
			_prog_nodes[en] = {"node": tr, "rect": e["rect"]}
		elif en == "progress_name" and e.get("rect") is Array:
			_prog_nodes[en] = {"rect": e["rect"]}
	_prog_label = Label.new()
	_prog_label.name = "ProgressName"
	_prog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prog_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_prog_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_prog_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog_label.visible = false
	add_child(_prog_label)
	_cross_label = Label.new()
	_cross_label.name = "CrossName"
	_cross_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cross_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_cross_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross_label.visible = false
	add_child(_cross_label)
	# Schatten zuerst (hinten), dann Hintergrund, dann Füllung
	for nm in ["shadow05", "prgbrbk", "prgbr01"]:
		if _prog_nodes.has(nm):
			move_child(_prog_nodes[nm]["node"], get_child_count() - 1)
	move_child(_prog_label, get_child_count() - 1)


## Lage der Ergänzungen; Fortschrittsgruppe waagerecht um die Bildmitte verschoben (Modell-x ≈ −0,36…−0,13).
func _layout_extras() -> void:
	var shift := 0.0
	if _prog_nodes.has("prgbrbk"):
		var r: Array = _prog_nodes["prgbrbk"]["rect"]
		shift = 0.5 - (float(r[0]) + float(r[2])) * 0.5
	for nm in _prog_nodes:
		var r: Array = _prog_nodes[nm]["rect"]
		var rr := screen_rect([float(r[0]) + shift, r[1], float(r[2]) + shift, r[3]], "center")
		_prog_nodes[nm]["screen"] = rr
		if _prog_nodes[nm].has("node"):
			var n: Control = _prog_nodes[nm]["node"]
			n.position = rr.position
			n.size = rr.size
	if _prog_nodes.has("progress_name"):
		var pr: Rect2 = _prog_nodes["progress_name"]["screen"]
		_prog_label.position = pr.position
		_prog_label.size = pr.size
		if not OrigFonts.apply(_prog_label, 0x2E, size.y, size.x):
			_prog_label.add_theme_font_size_override("font_size", maxi(10, int(pr.size.y * 0.8)))
		_prog_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))   # hell auf dem Spielbild [E]
	var cn := screen_rect([0.36479, 0.51437, 0.6352, 0.53445], "center")      # cross_name (hud_spec)
	_cross_label.position = cn.position
	_cross_label.size = cn.size
	if not OrigFonts.apply(_cross_label, 0x2E, size.y, size.x):
		_cross_label.add_theme_font_size_override("font_size", maxi(10, int(cn.size.y * 0.8)))
	_cross_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	# Aktionssymbol: 32×32-Vorlage links neben dem Hinweistext unter dem Fadenkreuz (Lage [?], Größe wie mind*/command*)
	var ic := screen_rect([0.0, 0.0, 0.03128, 0.04132], "center").size
	action_icon.size = ic
	action_icon.position = Vector2(size.x * 0.5 - ic.x * 0.5, size.y * 0.5 + ic.y * 0.9)


func _set_tex(nm: String, file: String) -> void:
	if not elements.has(nm):
		return
	var e: Dictionary = elements[nm]
	if e.get("state_tex", "") == file:
		return
	e["state_tex"] = file
	(e["node"] as TextureRect).texture = _load(file) if file != "" else null


func _update_state_icons(i: int, m: Soldier, is_active: bool) -> void:
	var sfx := "%02d" % i
	if m == null:
		for nm in ["command", "mind", "silence", "medic"]:
			_show_el(nm + sfx, false)
		return
	var b: SquadBrain = mission.squad.brain_of(m) if mission and mission.squad else null
	var show := m.alive and not is_active and b != null
	_show_el("command" + sfx, show)
	_show_el("mind" + sfx, show)
	if show:
		_set_tex("command" + sfx, String(COMMAND_ICONS.get(b.order, "textures/i_guard.png")))
		_set_tex("mind" + sfx, String(MIND_ICONS.get(b.roe, "textures/i_defens.png")))
	var w := m.current_weapon() if m.alive else null
	_show_el("silence" + sfx, m.alive and w != null and CommandMenu.has_silenced(m) and w.data.noise_radius < 20.0)
	_show_el("medic" + sfx, m.alive and m.heal_time_left > 0.0)


## Richtungssektor 0–7 relativ zur Blickrichtung: aus der Lage der Sektorgrafiken um die Kompassmitte (Bildwinkel).
func _sector_of(world_pos: Vector3, ring: String) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not elements.has("kmpscvr"):
		return -1
	var rel := world_pos - cam.global_position
	var fwd := Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var v := Vector2(rel.dot(right), -rel.dot(fwd))       # Bild: x rechts, y unten (vorn = oben)
	if v.length() < 0.01:
		return -1
	var c: Vector2 = (elements["kmpscvr"]["screen"] as Rect2).get_center()
	var best := -1
	var best_d := 10.0
	for k in 8:
		var nm := "kmps_%s%02d" % [ring, k]
		if not elements.has(nm):
			continue
		var d := (elements[nm]["screen"] as Rect2).get_center() - c
		var a := absf(angle_difference(d.angle(), v.angle()))
		if a < best_d:
			best_d = a
			best = k
	return best


func _on_soldier_damaged(s: Node, _amount: float, _zone: StringName, attacker: Node) -> void:
	var active: Soldier = mission.controller.active if mission and mission.controller else null
	if s != active or not (attacker is Node3D) or not is_instance_valid(attacker) or attacker == s:
		return
	var k := _sector_of((attacker as Node3D).global_position, "rd")
	if k >= 0:
		sector_rd[k] = SECTOR_TIME


func _on_noise(pos: Vector3, radius: float, source: Node, team: int, kind: StringName) -> void:
	var active: Soldier = mission.controller.active if mission and mission.controller else null
	if active == null or not is_instance_valid(active) or source == active:
		return
	if team == active.team or not (kind in [&"shot", &"gunshot", &"explosion", &"grenade"]):
		return
	if active.global_position.distance_to(pos) > radius:
		return
	var k := _sector_of(pos, "bl")
	if k >= 0:
		sector_bl[k] = SECTOR_TIME


func _update_sectors(delta: float) -> void:
	for k in 8:
		sector_rd[k] = maxf(sector_rd[k] - delta, 0.0)
		sector_bl[k] = maxf(sector_bl[k] - delta, 0.0)
		for pair in [["kmps_rd%02d" % k, sector_rd[k]], ["kmps_bl%02d" % k, sector_bl[k]]]:
			if elements.has(pair[0]):
				var n: Control = elements[pair[0]]["node"]
				n.visible = float(pair[1]) > 0.0
				n.modulate.a = clampf(float(pair[1]) / SECTOR_TIME, 0.0, 1.0)


func _update_progress(s: Soldier) -> void:
	progress_value = -1.0
	progress_text = ""
	if s != null and s.alive:
		if s.work_left > 0.0 and s.work_total > 0.0:
			progress_value = 1.0 - s.work_left / s.work_total
			progress_text = s.work_label
		elif s.heal_time_left > 0.0:
			progress_value = 1.0 - clampf(s.heal_time_left / 4.0, 0.0, 1.0)
			progress_text = SAS.item_label(54) if SAS.available() else "Verband"
		elif s.swimming and s.head_under_water() and s.air < Soldier.AIR_MAX - 0.05:
			progress_value = clampf(s.air / Soldier.AIR_MAX, 0.0, 1.0)
			progress_text = tr("Luft")
	var on := progress_value >= 0.0
	for nm in _prog_nodes:
		if _prog_nodes[nm].has("node"):
			(_prog_nodes[nm]["node"] as Control).visible = on
	_prog_label.visible = on and progress_text != ""
	_prog_label.text = progress_text
	if on and _prog_nodes.has("prgbr01") and _prog_nodes["prgbr01"].has("screen"):
		var full: Rect2 = _prog_nodes["prgbr01"]["screen"]
		var n: Control = _prog_nodes["prgbr01"]["node"]
		n.position = full.position
		n.size = Vector2(full.size.x * clampf(progress_value, 0.0, 1.0), full.size.y)


## Aktionssymbol zum Benutzen-Ziel (Texturnamen der Vorlagen [B], Zuordnung [P]).
static func action_icon_for(t: Object) -> String:
	if t == null or not is_instance_valid(t):
		return ""
	var cn := ""
	var sc: Script = t.get_script()
	while sc and cn == "":
		cn = String(sc.get_global_name())
		sc = sc.get_base_script()
	var p := String(t.get("prompt")) if "prompt" in t else ""
	if t is OrigInteractive.OrigDoor or t is Door:
		if bool(t.get("locked")) if "locked" in t else false:
			return "textures/i_lckpck.png"
		return "textures/i_close.png" if bool(t.get("is_open")) else "textures/i_open.png"
	if t is OrigInteractive.OrigLadder:
		return "textures/i_usladr.png"
	if t is OrigInteractive.OrigFence:
		return "textures/i_cutter.png"
	if t is OrigInteractive.OrigExplosive or t is ChargeSite:
		return "textures/i_plexpl.png"
	if t is PlacedCharge.DefuseSpot:
		return "textures/i_disarm.png"
	if t is OrigInteractive.OrigPlace:
		return "textures/i_plcdoc.png"
	if t is Vehicle.VehicleEntry:
		return "textures/i_driver.png"
	if t is EnemyBrain.CaptureAction:
		if p.to_lower().contains("uniform"):
			return "textures/i_changu.png"
		return "textures/i_take.png" if bool(t.get("searched")) else "textures/i_captur.png"
	if t is Pickups.Item or t is Pickups.Loot or t is Pickups.AmmoCrate or t is OrigInteractive.OrigCrate \
			or t is OrigInteractive.OrigWorldItem:
		return "textures/i_take.png"
	return "textures/i_use.png"


func _update_action_icon(s: Soldier) -> void:
	var t: Object = mission.controller.interact_target if mission and mission.controller and s and s.alive else null
	var f := action_icon_for(t) if t != null and s.vehicle == null else ""
	if f != action_icon_file:
		action_icon_file = f
		action_icon.texture = _load(f) if f != "" else null
	action_icon.visible = f != "" and action_icon.texture != null


## Name des Kameraden unter dem Fadenkreuz (≤ 60 m, ±1,5°) [P].
func _update_cross_name(s: Soldier) -> void:
	cross_name_text = ""
	var cam := get_viewport().get_camera_3d()
	if s != null and s.alive and cam != null and mission.squad:
		var fwd := -cam.global_basis.z
		var best := 0.9997
		for m in mission.squad.alive_members():
			if m == s:
				continue
			var to: Vector3 = m.global_position + Vector3.UP * 1.0 - cam.global_position
			if to.length() > 60.0:
				continue
			var c := to.normalized().dot(fwd)
			if c > best:
				best = c
				cross_name_text = m.soldier_name
	_cross_label.text = cross_name_text
	_cross_label.visible = cross_name_text != ""
