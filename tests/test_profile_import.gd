extends "res://tests/test_gameplay.gd"
## Übernahme der Original-Profile (HD2_orig\PlayersProfiles -> orig_cache/profiles_import.json) beim ersten Start.
##   tools\godot.cmd --headless -- --autoplay=test_profile_import --profiles_dir=user://test_import


func _run() -> void:
	await frames(5)
	var names := Game.list_profiles()
	check(names.has("Aldi") and names.has("profile"), "Original-Profile übernommen", str(names))
	check(Game.profile_name == "profile", "Profil mit dem weitesten Fortschritt ist aktiv", Game.profile_name)
	check(Game.difficulty() == 1, "Schwierigkeit aus profile.sav (LEICHT)", str(Game.difficulty()))
	check(Game.is_unlocked("cz4_volksfest") and not Game.is_unlocked("cz5_trink_aus"),
		"Fortschritt: bis Befreier – Volksfest (Missionsnummer 21) freigeschaltet")
	check(Game.campaign.get("completed", []).has("cz3_geschaeft"), "Vorherige Einsätze als abgeschlossen übernommen")
	check(FileAccess.file_exists(Game.profile_dir() + "/options.cfg"), "Optionen aus Options.bin übernommen (options.cfg)")
	check(absf(Settings.music_volume - 0.0202) < 0.001 and Settings.subtitles and Settings.crosshair,
		"Profiloptionen aktiv (Musik 2 %, Untertitel, Fadenkreuz)", "%.3f" % Settings.music_volume)
	check(String(Game.profile.get("orig_last_save", "")).contains("SPAGHETTI"), "Letzter Original-Spielstand angezeigt",
		String(Game.profile.get("orig_last_save", "")))
	# Profilwechsel lädt die Optionen des anderen Profils (Aldi: keine Options.bin -> Original-Standardwerte)
	Game.select_profile("Aldi")
	check(absf(Settings.music_volume - 0.5) < 0.001, "Wechsel zu „Aldi“: dessen Optionen (Original-Standard 50 %)",
		"%.3f" % Settings.music_volume)
	check(not Game.is_unlocked("a2_erkundung"), "„Aldi“ ohne Fortschritt")
	check(FileAccess.file_exists(Game.profiles_dir + "/orig_import_done"), "Import nur einmal (Markierung gesetzt)")
	_finish()
