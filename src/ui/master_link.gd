class_name MasterLink
extends Node
## 0.11.1: Zugang des Internet-Serverbrowsers zum Masterserver. Nutzt den Autoload `Master`
## (src/autoload/master_client.gd: connect_master()/refresh_servers(filter), Signale servers_updated(list),
## status_changed(state, text)); für Tests (force_mock) bzw. ohne Modul ein Ersatz mit derselben Schnittstelle.
## Eintragsfelder laut docs/status/b0111_master_client.md: id, name, host, port, map, map_title, mode, phase, players,
## max_players, bots, ping, version, build, password, joinable, dedicated, ranked, verify, pubkey_pem, source.

signal servers_updated(list: Array)
signal status_changed(state: String, text: String)

const UNREACHABLE := "Masterserver nicht erreichbar – Favoriten und Direktverbindung per IP bleiben nutzbar."

static var force_mock := false               ## Tests: Ersatz statt echtem Master
static var mock_servers: Array = []
static var mock_offline := true
var connected := false


static func source(tree: SceneTree) -> Node:
	var m := tree.root.get_node_or_null("Master")
	if not force_mock and m and m.has_method("connect_master") and m.has_method("refresh_servers"):
		return m
	var mk := tree.root.get_node_or_null("MasterMock")
	if mk == null:
		mk = MasterLink.new()
		mk.name = "MasterMock"
		tree.root.add_child(mk)
	return mk


func connect_master() -> void:
	status_changed.emit("connecting", "")
	await get_tree().process_frame
	connected = not mock_servers.is_empty() or not mock_offline
	if not connected:
		status_changed.emit("offline", "")
		return
	refresh_servers({})


func refresh_servers(_filter: Dictionary = {}) -> void:
	if not connected:
		status_changed.emit("offline", "")
		return
	servers_updated.emit(mock_servers.duplicate(true))
	status_changed.emit("online", "")


## Master-Eintrag → Feldnamen der LAN-Liste (Net.filter_pass, GameInfoScreen, LanMenu._do_join)
static func to_net(e: Dictionary) -> Dictionary:
	var d := e.duplicate()
	d["ip"] = String(e.get("host", e.get("ip", "")))
	d["port"] = int(e.get("port", Net.PORT))
	d["max"] = int(e.get("max_players", e.get("max", 8)))
	d["pw"] = bool(e.get("password", e.get("pw", false)))
	d["ded"] = bool(e.get("dedicated", e.get("ded", false)))
	d["ranked"] = bool(e.get("ranked", true))
	if e.has("version") and not d.has("ver"):
		d["ver"] = e["version"]
	return d
