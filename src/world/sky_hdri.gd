extends RefCounted
## B-050 – fotorealistische Himmel (BEWUSSTE ABWEICHUNG, [D] 07.11.2026). Per preload (kein class_name).
## CC0-HDRIs (Poly Haven) unter res://assets/sky/<id>_2k.hdr, Zuordnung Kartenordner → Himmel in MAP (Quellen/Lizenz:
## docs/SKY_SOURCES.md). Fehlt die Datei, bleibt der Original-Himmel (sky_backdrop.gd) bzw. der prozedurale.
## `--sky=orig` = Original-Himmel erzwingen, `--sky=photo` (Standard) = Foto, falls vorhanden.

const DIR := "res://assets/sky/"
## Ordner-Präfix (klein) → [HDRI-ID, Helligkeit, Drehung °]; Reihenfolge = erster Treffer gewinnt
## ID-Liste „a|b“: erste vorhandene Datei gewinnt (*_puresky = ohne Boden/moderne Objekte am Horizont, bevorzugt).
## Helligkeit nach Prüfbildern 07.11.2026 (Nacht-HDRIs sind belichtet wie Tag → stark abdunkeln).
const MAP := [
	["africa", "goegap_road", 1.0, 0.0],
	["afrika", "goegap_road", 1.0, 0.0],
	["arctic1", "kloppenheim_02_puresky", 0.35, 0.0],   # ARCTIC1: Nebel dunkelblau = Nacht
	["arctic", "kloofendal_overcast_puresky", 0.9, 0.0],
	["norway", "kloppenheim_02_puresky", 0.35, 0.0],    # NORWAY: Nebel fast schwarz = Nacht
	["alps", "kloofendal_overcast_puresky", 1.0, 0.0],
	["burma", "kloofendal_misty_morning_puresky", 0.9, 0.0],
	["normandy2", "evening_road_01_puresky", 0.45, 0.0],
	["normandy", "kloofendal_overcast_puresky", 0.9, 0.0],
	["czech", "kloofendal_overcast_puresky", 0.9, 0.0],
	["ardens", "kloofendal_overcast_puresky", 0.85, 0.0],
]
static var stats := {}


static func enabled() -> bool:
	return String(Game.cli.get("sky", "photo")) != "orig"


static func entry_for(folder: String) -> Array:
	var f := folder.to_lower()
	for e in MAP:
		if f.begins_with(String(e[0])):
			return e
	return []


static func path_for(id: String) -> String:
	for ext in ["_2k.hdr", "_2k.exr", "_2k.jpg"]:
		var p: String = DIR + id + String(ext)
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			return p
	return ""


static var _tex_cache := {}

static func _texture(p: String) -> Texture2D:
	if _tex_cache.has(p):
		return _tex_cache[p]
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	if t == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(p) if p.begins_with("res://") else p)
		if img:
			t = ImageTexture.create_from_image(img)
	_tex_cache[p] = t
	return t


## Panorama für den Kartenordner; null = kein Fotohimmel (Datei fehlt/abgeschaltet)
static func material_for(folder: String) -> PanoramaSkyMaterial:
	stats = {"folder": folder}
	if not enabled() or folder == "":
		return null
	var e := entry_for(folder)
	if e.is_empty():
		return null
	var p := ""
	for id in String(e[1]).split("|"):
		p = path_for(id)
		if p != "":
			stats["id"] = id
			break
	stats["path"] = p
	if p == "":
		return null
	var t := _texture(p)
	if t == null:
		return null
	var m := PanoramaSkyMaterial.new()
	m.panorama = t
	m.energy_multiplier = float(e[2])
	m.filter = true
	stats["active"] = true
	return m


## Mittlere Horizontfarbe (Band knapp über dem Horizont) → Nebelfarbe passend zum Himmel
static func horizon_color(m: PanoramaSkyMaterial) -> Color:
	var img: Image = m.panorama.get_image() if m and m.panorama else null
	if img == null:
		return Color(0.7, 0.72, 0.75)
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for yy in [int(h * 0.46), int(h * 0.48)]:
		for i in 64:
			var c := img.get_pixel(int(float(i) / 64.0 * w), yy)
			acc += c
			n += 1
	acc /= float(n)
	var mx := maxf(acc.r, maxf(acc.g, acc.b))
	if mx > 1.0:
		acc = Color(acc.r / mx, acc.g / mx, acc.b / mx)
	return Color(acc.r * m.energy_multiplier, acc.g * m.energy_multiplier, acc.b * m.energy_multiplier, 1.0).clamp()
