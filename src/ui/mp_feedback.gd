class_name MpFeedback
extends Control
## Mehrspieler-Rückmeldungen (Ergänzung zum Original-HUD, hängt unter MpHud/Root; alle Daten vom Server):
##  - Trefferanzeige am Fadenkreuz (Hitmarker) + Treffergeräusch für den Schützen, nur auf serverbestätigte Treffer
##    (Net._hit_confirm): Körper weiß, Kopf gelb und größer, tödlich rot mit Kreis, Teamkamerad blau.
##    Darunter kurz die Original-Treffermeldung T8851 „Sie haben %s am %s getroffen!!!“ (Teamkamerad T8850,
##    Zonen T8801–8806) bzw. bei Tötung T8857/8858/8856. Klang: Original Kat. 4/7 „Flash or Dead Body“ (2D,
##    Tonhöhe je Art = Annahme). Schalter: Settings.hit_feedback und Server-Regel hit_indicator.
##  - Richtungsanzeige erlittener Treffer (Net._hurt_from): roter Bogen um das Fadenkreuz in Richtung des Schützen,
##    1,5 s ausblendend (relativ zur Blickrichtung, Bezugspunkt eigener Soldat; Kreis aus der kürzeren Bildseite,
##    hurt_arc_geometry). Schalter: Settings.hurt_feedback und Server-Regel hurt_indicator (getrennt vom Schützen).
##  - Kill-Feed oben rechts unter der Punktetafel: „Schütze [Waffensymbol wi_*] Opfer“, Kopfschuss-Marke, Teamfarben,
##    Friendly-Fire/Selbstmord/Sturz gekennzeichnet (Original-Wortlaut), ~5 s sichtbar, höchstens 5 Einträge (Net.kill_feed).
##  - Namen über Spielern: Teamkameraden immer (Sichtlinie, bis TEAM_RANGE m, ab TEAM_FADE m ausblendend, Teamfarbe);
##    Gegner nur, solange das Fadenkreuz direkt auf ihnen liegt (Strahl wie CameraRig.crosshair_point: Wände/Laub
##    verdecken, bis ENEMY_RANGE m). Getarnte Gegner (Soldier.disguised) erscheinen wie Teamkameraden (eigene
##    Teamfarbe), werden also nicht verraten. Deathmatch: keine Teamnamen. Schalter: Settings.show_names + Regel show_names.
##    Original kennt am Fadenkreuz nur „cross_name“ (Name des anvisierten Objekts, hud_spec.json); Kopfanzeige = Ergänzung.

const TEAM_RANGE := 60.0
const TEAM_FADE := 40.0
const ENEMY_RANGE := 80.0
const FEED_SHOW_S := 5.0
const HURT_SHOW_S := 1.5
const HIT_SHOW_S := 0.3
const KILL_SHOW_S := 0.6
const HIT_TEXT_S := 1.6
const ALLIED_COL := Color(0.5, 0.7, 1.0)
const AXIS_COL := Color(1.0, 0.48, 0.38)
const NEUTRAL_COL := Color(0.95, 0.9, 0.75)
const ME_COL := Color(1.0, 0.86, 0.35)

var hit_kind := ""            ## letzte Trefferart: body/head/kill/ff (Tests)
var hit_ms := -100000
var hit_text := ""
var hits_shown := 0           ## Anzahl angezeigter Hitmarker (Tests)
var sounds_played := 0
var last_sound := ""
var name_tags: Array = []     ## zuletzt berechnete Namensanzeigen (Tests): {id, name, kind, color, pos, alpha}
var _hurts: Array = []
var _sound: AudioStreamPlayer
static var _icon_cache := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sound = AudioStreamPlayer.new()
	_sound.name = "HitSound"
	_sound.bus = &"SFX"
	add_child(_sound)
	Net.hit_confirmed.connect(_on_hit)
	Net.hurt_received.connect(_on_hurt)


static func hits_enabled() -> bool:
	return Settings.hit_feedback and bool(Net.rule("hit_indicator"))


static func hurts_enabled() -> bool:
	return Settings.hurt_feedback and bool(Net.rule("hurt_indicator"))


static func names_enabled() -> bool:
	return Settings.show_names and bool(Net.rule("show_names"))


static func team_color(t: int) -> Color:
	if not Net.team_mode():
		return NEUTRAL_COL
	return AXIS_COL if t == Soldier.TEAM_AXIS else (ALLIED_COL if t == Soldier.TEAM_ALLIED else NEUTRAL_COL)


## Zonenname wie im Original (T8801 Körper, T8802 Kopf, T8803/8805 „linke Hand“/„linkes Bein“ ohne Seite)
static func zone_text(zone: String) -> String:
	match zone:
		"head":
			return Net.tx(8802, "Kopf")
		"arm":
			var a := Net.tx(8803, "linke Hand")
			return a.get_slice(" ", 1) if a.contains(" ") else a
		"leg", "legs":
			var b := Net.tx(8805, "linkes Bein")
			return b.get_slice(" ", 1) if b.contains(" ") else b
	return Net.tx(8801, "Körper")


# --- Treffer -------------------------------------------------------------------------------------------

func _on_hit(info: Dictionary) -> void:
	if not hits_enabled():
		return
	hit_kind = "kill" if bool(info["killed"]) else ("ff" if bool(info["ff"]) else ("head" if bool(info["head"]) else "body"))
	hit_ms = Time.get_ticks_msec()
	hits_shown += 1
	var nm := String(info["name"])
	if bool(info["killed"]):
		hit_text = Net.tx(8856 if bool(info["ff"]) else (8857 if bool(info["head"]) else 8858), "Sie haben %s getötet.").replace("%s", nm)
	else:
		hit_text = Net.fmt_s(Net.tx(8850 if bool(info["ff"]) else 8851, "Sie haben %s am %s getroffen!!!"),
			[nm, zone_text(String(info["zone"]))])
	_play_hit_sound(hit_kind)
	queue_redraw()


func _play_hit_sound(kind: String) -> void:
	var v := OrigAudio.pick(OrigAudio.CAT_HIT, OrigAudio.HIT_FLESH)
	var file := String(v.get("file", ""))
	var st: AudioStream = OrigAudio.stream(file) if file != "" else null
	if st == null:
		return
	_sound.stream = st
	_sound.pitch_scale = {"head": 1.5, "kill": 0.8, "ff": 1.0}.get(kind, 1.25)
	_sound.volume_db = 2.0 if kind == "kill" else -3.0
	_sound.play()
	sounds_played += 1
	last_sound = file


func _on_hurt(from_pos: Vector3) -> void:
	if not hurts_enabled():
		return
	_hurts.append({"pos": from_pos, "ms": Time.get_ticks_msec()})
	if _hurts.size() > 8:
		_hurts.pop_front()


## Bildschirmwinkel (0 = oben, im Uhrzeigersinn) der Weltposition relativ zur Blickrichtung der Kamera; Bezugspunkt =
## eigener Soldat (origin), sonst die Kamera – in der 3. Person liegt ein Schütze dicht hinter dem Soldaten sonst „vorn“
static func screen_angle(cam: Camera3D, world: Vector3, origin := Vector3.INF) -> float:
	var rel := world - (origin if origin.is_finite() else cam.global_position)
	var fwd := Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	return atan2(rel.dot(right), rel.dot(fwd))


func active_hurts() -> Array:
	var now := Time.get_ticks_msec()
	return _hurts.filter(func(h): return now - int(h["ms"]) < int(HURT_SHOW_S * 1000.0))


# --- Namen -----------------------------------------------------------------------------------------------

## Soldat unter dem Fadenkreuz (Strahl gegen Welt + Trefferzonen wie CameraRig.crosshair_point), sonst null
static func aimed_soldier(cam: Camera3D, me: Soldier, max_dist := ENEMY_RANGE) -> Soldier:
	var dir := -cam.global_basis.z
	var from := cam.global_position
	var m = Game.current_mission()
	var rig: CameraRig = m.rig if m and m.get("rig") else null
	if rig and not rig.fpv_active and is_instance_valid(me):
		from += dir * maxf((me.eye_position() - from).dot(dir), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, 1 | Hitbox.LAYER)
	q.collide_with_areas = true
	if is_instance_valid(me):
		q.exclude = me.exclude_rids()
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is Hitbox):
		return null
	var s = (hit.collider as Hitbox).soldier
	if not (s is Soldier) or not (s as Soldier).alive:
		return null
	if m and m.has_method("foliage_blocks_sight") and m.foliage_blocks_sight(from, hit.position):
		return null
	return s


static func _line_of_sight(cam: Camera3D, me: Soldier, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, to, 1)
	if is_instance_valid(me):
		q.exclude = me.exclude_rids()
	if not cam.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	var m = Game.current_mission()
	return not (m and m.has_method("foliage_blocks_sight") and m.foliage_blocks_sight(cam.global_position, to))


static func head_point(s: Soldier) -> Vector3:
	return s.eye_position() + Vector3.UP * 0.42


## Namensanzeigen für die Kamera (Regeln s. Kopf der Datei)
static func compute_name_tags(cam: Camera3D) -> Array:
	var out: Array = []
	var me: Soldier = Net._soldiers.get(Net.my_id())
	if cam == null or not cam.is_inside_tree() or not is_instance_valid(me) or not me.alive or not names_enabled():
		return out
	var tm := Net.team_mode()
	var aimed := aimed_soldier(cam, me)
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if not is_instance_valid(s) or not s.alive or s == me:
			continue
		var head := head_point(s)
		if cam.is_position_behind(head):
			continue
		var d := cam.global_position.distance_to(head)
		var mate := tm and s.team == me.team
		var hidden_enemy := tm and not mate and s.disguised      # Tarnung: wie ein Teamkamerad zeigen, nicht verraten
		var tag := {"id": int(id), "name": s.soldier_name, "dist": d}
		if mate or hidden_enemy:
			if d > TEAM_RANGE or not _line_of_sight(cam, me, head):
				continue
			tag["kind"] = "team"
			tag["color"] = team_color(me.team)
			tag["alpha"] = clampf((TEAM_RANGE - d) / (TEAM_RANGE - TEAM_FADE), 0.0, 1.0)
		else:
			if s != aimed or d > ENEMY_RANGE:
				continue
			tag["kind"] = "aimed"
			tag["color"] = team_color(s.team)
			tag["alpha"] = 1.0
		tag["pos"] = cam.unproject_position(head)
		out.append(tag)
	return out


# --- Kill-Feed --------------------------------------------------------------------------------------------

## Sichtbare Einträge (jünger als FEED_SHOW_S, höchstens Net.KILL_FEED_MAX)
static func feed_entries() -> Array:
	var now := Time.get_ticks_msec()
	return Net.kill_feed.filter(func(e): return e is Dictionary and now - int(e["ms"]) < int(FEED_SHOW_S * 1000.0))


## Waffensymbol (items.sav-Symbol „wi_*“, orig_cache/ui/menu/items) zur Ursache (Waffen-ID), null wenn keins
static func weapon_icon(cause: String, team: int) -> Texture2D:
	var key := "%s:%d" % [cause, team]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: Texture2D = null
	var wd: WeaponData = WeaponDB.get_weapon(StringName(cause)) if cause != "" and cause != "fall" else null
	if wd and SAS.available():
		var item := OrigWeapons.item_for(wd, team)
		if item < 0:
			item = int(OrigHud.ITEM_FALLBACK.get(wd.id, -1))
		var ic: String = String(SAS._item_data().get(item, {}).get("icon", "")).to_lower() if item >= 0 else ""
		for rel in ["/ui/menu/items/%s.png", "/ui/hud/inventory/%s.png"]:
			var p: String = OrigLevel.cache_root() + String(rel) % ic
			if ic != "" and FileAccess.file_exists(p):
				var img := Image.load_from_file(p)
				if img:
					tex = ImageTexture.create_from_image(img)
					break
	_icon_cache[key] = tex
	return tex


static func weapon_label(cause: String) -> String:
	if cause == "fall":
		return ""
	var wd: WeaponData = WeaponDB.get_weapon(StringName(cause)) if cause != "" else null
	return wd.display_name if wd else ""


# --- Zeichnen ----------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not Net.is_online:
		return
	var cam := get_viewport().get_camera_3d()
	name_tags = compute_name_tags(cam)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	_draw_names(font)
	_draw_hurts()
	_draw_hitmarker(font)
	_draw_feed(font)


func _draw_names(font: Font) -> void:
	var fs := maxi(int(size.y * 0.019), 11)
	for t in name_tags:
		var txt := String(t["name"])
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p: Vector2 = t["pos"] - Vector2(w * 0.5, 0.0)
		var col: Color = t["color"]
		col.a = float(t["alpha"])
		draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, col.a * 0.85))
		draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Geometrie des Richtungsbogens für eine Zeichenfläche (Pixel der Control = Bildschirmpunkte; die Oberfläche skaliert
## mit stretch canvas_items/expand gleichmäßig, daher bleibt der Kreis rund): Mitte = Fadenkreuz (Flächenmitte),
## Radius aus der KÜRZEREN Seite (gleich groß bei 4:3, 16:10, 16:9, 21:9 gleicher Höhe), Grenzen 56–260 px.
## ang: 0 = Schütze voraus (Bogen oben), +PI/2 = rechts. Rückgabe: center, radius, a0/a1 (Godot-Bogenwinkel, 0 = rechts,
## im Uhrzeigersinn), width, tip/base_l/base_r (Pfeilspitze nach außen).
static func hurt_arc_geometry(area: Vector2, ang: float) -> Dictionary:
	var c := area * 0.5
	var r := clampf(minf(area.x, area.y) * 0.16, 56.0, 260.0)
	var ga := ang - PI * 0.5
	var dir := Vector2(cos(ga), sin(ga))
	var side := Vector2(-dir.y, dir.x) * r * 0.08
	var base := c + dir * (r * 1.04)
	return {"center": c, "radius": r, "a0": ga - 0.34, "a1": ga + 0.34, "width": maxf(r * 0.06, 3.0),
		"tip": c + dir * (r * 1.2), "base_l": base + side, "base_r": base - side, "dir": dir}


func _draw_hurts() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not hurts_enabled():
		return
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var origin: Vector3 = me.global_position if is_instance_valid(me) else Vector3.INF
	var now := Time.get_ticks_msec()
	for h in active_hurts():
		var g := hurt_arc_geometry(size, screen_angle(cam, h["pos"], origin))
		var k := clampf(1.0 - float(now - int(h["ms"])) / (HURT_SHOW_S * 1000.0), 0.0, 1.0)
		var col := Color(0.9, 0.12, 0.08, 0.85 * k)
		draw_arc(g["center"], g["radius"], g["a0"], g["a1"], 24, Color(0, 0, 0, 0.5 * k), float(g["width"]) + 3.0, true)
		draw_arc(g["center"], g["radius"], g["a0"], g["a1"], 24, col, g["width"], true)
		draw_colored_polygon(PackedVector2Array([g["tip"], g["base_l"], g["base_r"]]), col)


func _draw_hitmarker(font: Font) -> void:
	if not hits_enabled():
		return                         # Regel/Option während der Anzeige abgeschaltet
	var age := float(Time.get_ticks_msec() - hit_ms) / 1000.0
	var c := size * 0.5
	var dur := KILL_SHOW_S if hit_kind == "kill" else HIT_SHOW_S
	if age < dur and hit_kind != "":
		var k := 1.0 - age / dur
		var col := Color.WHITE
		var r0 := 6.0
		var r1 := 13.0
		var wd := 2.0
		match hit_kind:
			"head":
				col = Color(1.0, 0.82, 0.2)
				r1 = 16.0
				wd = 2.5
			"kill":
				col = Color(1.0, 0.18, 0.12)
				r0 = 7.0
				r1 = 19.0
				wd = 3.0
			"ff":
				col = Color(0.45, 0.7, 1.0)
		col.a = k
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = (d as Vector2).normalized()
			draw_line(c + n * r0, c + n * r1, Color(0, 0, 0, k * 0.6), wd + 2.0, true)
			draw_line(c + n * r0, c + n * r1, col, wd, true)
		if hit_kind == "kill":
			draw_arc(c, r1 + 4.0, 0, TAU, 32, col, 2.0, true)
	if age < HIT_TEXT_S and hit_text != "":
		var fs := maxi(int(size.y * 0.018), 11)
		var col2 := Color(1, 0.95, 0.85, clampf((HIT_TEXT_S - age) / 0.4, 0.0, 1.0))
		var w := font.get_string_size(hit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := c + Vector2(-w * 0.5, size.y * 0.06)
		draw_string_outline(font, p, hit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, col2.a))
		draw_string(font, p, hit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2)


func _draw_feed(font: Font) -> void:
	var rows := feed_entries()
	if rows.is_empty():
		return
	var row_h := maxf(size.y * 0.028, 17.0)
	var fs := maxi(int(row_h * 0.62), 10)
	var y := size.y * 0.095 + 6.0             # unter der Original-Punktetafel mp_scoretable (bis 0,0854)
	var right := size.x - 10.0
	var now := Time.get_ticks_msec()
	var me := Net.my_id()
	for e in rows:
		var fade := clampf((FEED_SHOW_S * 1000.0 - float(now - int(e["ms"]))) / 500.0, 0.0, 1.0)
		var parts: Array = []           # [Art, Inhalt, Farbe]
		var kcol := team_color(int(e["kteam"]))
		var vcol := team_color(int(e["vteam"]))
		if not Net.team_mode():
			kcol = ME_COL if int(e["killer"]) == me else NEUTRAL_COL
			vcol = ME_COL if int(e["victim"]) == me else NEUTRAL_COL
		if not bool(e["suicide"]):
			parts.append(["text", String(e["kname"]), kcol])
		var icon := weapon_icon(String(e["cause"]), int(e["kteam"]))
		if icon:
			parts.append(["icon", icon, Color.WHITE])
		elif weapon_label(String(e["cause"])) != "":
			parts.append(["text", "[%s]" % weapon_label(String(e["cause"])), Color(0.85, 0.85, 0.8)])
		if bool(e["head"]):
			parts.append(["head", null, Color(1.0, 0.25, 0.15)])
		parts.append(["text", String(e["vname"]), vcol])
		if bool(e["tk"]):
			parts.append(["text", "(Friendly-Fire)", Color(1.0, 0.6, 0.15)])
		elif String(e["cause"]) == "fall":
			parts.append(["text", "(Sturz)", Color(0.85, 0.85, 0.8)])
		elif bool(e["suicide"]):
			parts.append(["text", "(Selbstmord)", Color(1.0, 0.6, 0.15)])
		# Breite messen, rechtsbündig zeichnen
		var widths: Array = []
		var total := 0.0
		for p in parts:
			var w := 0.0
			match String(p[0]):
				"text":
					w = font.get_string_size(String(p[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				"icon":
					var tx: Texture2D = p[1]
					w = row_h * 0.95 * float(tx.get_width()) / maxf(float(tx.get_height()), 1.0)
				"head":
					w = row_h * 0.7
			widths.append(w)
			total += w + 6.0
		var x := right - total
		var mine := int(e["killer"]) == me or int(e["victim"]) == me
		draw_rect(Rect2(x - 6.0, y, total + 8.0, row_h), Color(0, 0, 0, 0.45 * fade))
		if mine:
			draw_rect(Rect2(x - 6.0, y, total + 8.0, row_h), Color(ME_COL, 0.8 * fade), false, 1.5)
		for i in parts.size():
			var p: Array = parts[i]
			var col: Color = p[2]
			col.a *= fade
			match String(p[0]):
				"text":
					var base := Vector2(x, y + row_h * 0.5 + fs * 0.36)
					draw_string_outline(font, base, String(p[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, fade))
					draw_string(font, base, String(p[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				"icon":
					draw_texture_rect(p[1], Rect2(x, y + row_h * 0.025, widths[i], row_h * 0.95), false, Color(1, 1, 1, fade))
				"head":
					var hc := Vector2(x + widths[i] * 0.5, y + row_h * 0.5)
					var hr := row_h * 0.28
					draw_arc(hc, hr, 0, TAU, 20, col, 2.0, true)
					draw_line(hc - Vector2(hr * 1.5, 0), hc + Vector2(hr * 1.5, 0), col, 1.5)
					draw_line(hc - Vector2(0, hr * 1.5), hc + Vector2(0, hr * 1.5), col, 1.5)
			x += widths[i] + 6.0
		y += row_h + 3.0
