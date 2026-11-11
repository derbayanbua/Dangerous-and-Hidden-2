extends Node
## Manueller Lesetest gegen den echten Master (nur auf Anweisung, nie in run_tests): GET /v1/servers mit DH2-LAN-6.
## Build-Schlüssel nur im Speicher: --key=<pfad>.  tools\godot.cmd --headless -- --autoplay=probe_master_read --key=…


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var M := get_node("/root/Master")
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--key="):
			path = a.get_slice("=", 1)
	var k := CryptoKey.new()
	if path == "" or k.load_from_string(FileAccess.get_file_as_string(path), false) != OK:
		print("PROBE: kein Schlüssel")
		get_tree().quit(1)
		return
	M.set_build_key(k)
	print("PROBE: kid ", M.build_kid(), " proto ", M.net_protocol())
	var r: Dictionary = await M.request("GET", "/v1/servers", M.list_query(), null, 0)
	print("PROBE: status ", r["status"], " code ", r["code"])
	var ok: bool = await M.refresh_servers()
	print("PROBE: refresh ok=", ok, " state=", M.state, " servers=", M.list.size())
	for e in M.list:
		print("PROBE:  ", e.get("name"), " ", e.get("host"), ":", e.get("port"), " ranked=", e.get("ranked"), " verify=", e.get("verify"))
	M.set_build_key(null)
	get_tree().quit(0)
