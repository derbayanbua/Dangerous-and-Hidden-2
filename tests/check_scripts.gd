extends Node
## Kompiliert alle Skripte unter res://src und res://tests und meldet Fehler.
##   tools\godot.cmd --headless -- --autoplay=check_scripts   (Exit 0 = ok)


func _ready() -> void:
	var bad := 0
	var total := 0
	for dir in ["res://src", "res://tests"]:
		for path in _collect(dir):
			total += 1
			var s: GDScript = load(path)
			if s == null or not s.can_instantiate():
				# Basisklassen-Skripte ohne Instanziierbarkeit gibt es hier nicht
				print("FAIL  ", path)
				bad += 1
	print("ERGEBNIS: %d Skripte, %d fehlerhaft" % [total, bad])
	get_tree().quit(1 if bad > 0 else 0)


func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
		elif f.ends_with(".gd.remap"):   # exportierter Build
			out.append(dir.path_join(f.trim_suffix(".remap")))
	for sub in d.get_directories():
		out.append_array(_collect(dir.path_join(sub)))
	return out
