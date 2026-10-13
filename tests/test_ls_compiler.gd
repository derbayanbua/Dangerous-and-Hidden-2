extends Node
## Kompiliert Original-Missionsskripte mit LsCompiler und meldet Syntaxfehler.
##   tools\godot.cmd --headless -- --autoplay=test_ls_compiler [--scripts=<ordner>]
## Standard: orig_cache/arctic1/scripts; zusätzlich D:/Workspace_D/re_work/x/scripts (falls vorhanden).


func _ready() -> void:
	var dirs: Array[String] = [OrigLevel.cache_path("ARCTIC1") + "/scripts"]
	if Game.cli.has("scripts"):
		dirs = [Game.cli["scripts"]]
	elif DirAccess.dir_exists_absolute("D:/Workspace_D/re_work/x/scripts"):
		dirs.append("D:/Workspace_D/re_work/x/scripts")
	var total := 0
	var bad := 0
	var err_lines := 0
	var samples: Array[String] = []
	for d in dirs:
		for path in _collect(d):
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			if path.get_file().begins_with("_inc"):
				continue   # Include-Fragmente sind allein nicht vollständig
			var txt := f.get_buffer(f.get_length()).get_string_from_ascii()
			var c := LsCompiler.compile(txt, path.get_file(), path.get_base_dir())
			total += 1
			if not c.ok():
				bad += 1
				err_lines += c.errors.size()
				if samples.size() < 25:
					samples.append(c.errors[0])
	for s in samples:
		print("  ", s)
	print("ERGEBNIS: %d Skripte, %d mit Fehlern (%d Fehlermeldungen)" % [total, bad, err_lines])
	get_tree().quit(0 if bad == 0 else 1)


func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.to_lower().ends_with(".scr"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_collect(dir.path_join(sub)))
	return out
