class_name Weapon
extends RefCounted
## Laufzeitzustand einer Waffe im Besitz eines Soldaten: Magazin, Reserve,
## Feuerbereitschaft, Nachladevorgang, Streuungsaufbau.

signal fired
signal reload_started(duration: float)
signal reload_finished
signal empty_click

var data: WeaponData
var in_mag := 0
var reserve := 0
var auto_mode := true          ## nur relevant wenn data.can_toggle_auto
var cooldown := 0.0
var reload_left := 0.0
var bloom := 0.0               ## zusätzliche Streuung durch Dauerfeuer (Grad)
var _trigger_was_down := false


func _init(weapon_data: WeaponData, full := true) -> void:
	data = weapon_data
	auto_mode = data.is_automatic()
	if full:
		in_mag = data.magazine_size
		reserve = data.magazine_size * (data.start_magazines - 1)


func is_reloading() -> bool:
	return reload_left > 0.0


func fires_automatic() -> bool:
	if data.can_toggle_auto:
		return auto_mode
	return data.is_automatic()


func toggle_fire_mode() -> bool:
	if not data.can_toggle_auto:
		return false
	auto_mode = not auto_mode
	return true


func fire_mode_text() -> String:
	match data.action:
		WeaponData.Action.BOLT: return "Repetierer"
		WeaponData.Action.THROWN: return "Wurf"
	return "Dauerfeuer" if fires_automatic() else "Einzelfeuer"


func tick(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	bloom = maxf(bloom - delta * data.recoil_recovery * 0.5, 0.0)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			reload_left = 0.0
			_finish_reload()


## Abzug-Zustand für diesen Frame. Gibt true zurück, wenn ein Schuss
## ausgelöst werden soll (Munition wird hier abgezogen).
func trigger(down: bool) -> bool:
	var pressed_now := down and not _trigger_was_down
	_trigger_was_down = down
	if not down or is_reloading() or cooldown > 0.0:
		return false
	if not fires_automatic() and not pressed_now:
		return false
	if in_mag <= 0:
		if pressed_now:
			empty_click.emit()
		return false
	in_mag -= 1
	cooldown = data.shot_interval()
	bloom = minf(bloom + data.spread_per_shot, data.spread_hip * 1.5)
	fired.emit()
	return true


func can_reload() -> bool:
	return not is_reloading() and in_mag < data.magazine_size and reserve > 0 \
		and data.action != WeaponData.Action.THROWN


func start_reload() -> bool:
	if not can_reload():
		return false
	reload_left = data.reload_empty_time if in_mag == 0 else data.reload_time
	reload_started.emit(reload_left)
	return true


func cancel_reload() -> void:
	reload_left = 0.0


func _finish_reload() -> void:
	# Teilmagazine: Restpatronen bleiben erhalten (vereinfachte Munitionsverwaltung).
	var need := data.magazine_size - in_mag
	var take := mini(need, reserve)
	in_mag += take
	reserve -= take
	reload_finished.emit()


## Granaten: gesamter Vorrat (kein Magazin).
func total_ammo() -> int:
	return in_mag + reserve


func add_ammo(rounds: int) -> int:
	var cap := data.magazine_size * (data.start_magazines + 2)
	var room := maxi(cap - total_ammo(), 0)
	var added := mini(room, rounds)
	reserve += added
	return added


func serialize() -> Dictionary:
	return {"id": String(data.id), "in_mag": in_mag, "reserve": reserve, "auto": auto_mode}


static func deserialize(d: Dictionary) -> Weapon:
	var w := Weapon.new(WeaponDB.get_weapon(StringName(d["id"])), false)
	w.in_mag = int(d["in_mag"])
	w.reserve = int(d["reserve"])
	w.auto_mode = bool(d.get("auto", w.auto_mode))
	return w
