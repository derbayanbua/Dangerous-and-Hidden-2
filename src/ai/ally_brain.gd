class_name AllyBrain
extends EnemyBrain
## Verbündete/neutrale Skript-NPCs der Originalmissionen (actors.bin Seite 3 „neutral/friendly NPC“, z. B. NORMANDY2
## Ally_1–5/Amik_1–4 in Operation Schwerttänzer). Audit `docs/AI_AUDIT_ALLY.md`.
##
## Original [B]: Fraktion nach hd2.exe 0x5A8820 (Einzelspieler): Seite 2 → 0 (Achse), Seite 1/4 → 1 (Spielerseite),
## sonst (Seite 3) → 2 (neutral). Neutrale sind kein Ziel der Gegner-KI und suchen selbst keine Ziele – Kampfhandlungen
## entstehen nur über ihr Skript: HUMAN_Move zu Stellungen, HUMAN_SETMODE_Crouch (Position halten), HUMAN_IllFire auf
## Dummy-Frames (Deckungsfeuer) und HUMAN_Attack(Blue_n, ms) auf Deutsche; die Deutschen erwidern per Signal
## (r_n2_blue_7.scr OnSignal(1): HUMAN_Attack(Ally1, 1000)).
##
## Abweichung vorher: HUMAN_Attack auf einen Achsensoldaten schaltete über EnemyBrain.script_attack die Skriptsteuerung
## ab und startete den Kampfautomaten (Anmarsch ≥ 20 m, Positionswechsel). Der Verbündete verließ seine Stellung und
## blieb danach dauerhaft in freier KI – das Skript (zurück zu „Ally1_1“, Hocken) lief ins Leere.
## Nachbau: Angriff = gezieltes Feuern von der aktuellen Stelle auf das (lebende) Ziel für die Dauer; Skriptsteuerung
## bleibt; Haltung bleibt (Skript setzt sie). Ende bei Ablauf oder Tod des Ziels [P: Bewegungslosigkeit aus den Skripten
## abgeleitet, Automat für Fraktion 2 nicht dekodiert].


func script_attack_order(t: Node3D, seconds: float, illfire: bool) -> void:
	# Bordschütze/Stellung (NORMANDY2 Amik_tank_MG, BURMA2 BU2_A_Sherman*): Zielübergabe an die Stellungs-/Sitzwaffe
	# wie bisher (EnemyBrain._mounted_tick), sonst feuerte die (leere) Handwaffe
	if soldier.mounted != null or (soldier.vehicle != null and soldier.seat_index > 0):
		super.script_attack_order(t, seconds, illfire)
		return
	attack_illfire = illfire
	_attack_target = null
	attack_left = 0.0
	script_ill_fire(t, seconds)


func ill_fire_done() -> bool:
	if _ill_target is Soldier and not (_ill_target as Soldier).alive:
		_ill_fire_t = 0.0
		cease_fire()
	return super.ill_fire_done()
