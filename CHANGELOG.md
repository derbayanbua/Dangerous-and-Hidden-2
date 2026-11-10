# Changelog



## 0.10.8 (10.11.2026)

- **Testkarte „Bavaria (Test)“** im Mehrspieler (Deathmatch, Team-Deathmatch, Eroberung) und als Übungseinsatz.
- **Neues Wasser** je Klimazone (Wellen, Gischt, Tiefenfarbe, Qualität nach Grafikstufe); Option „WASSER: ORIGINAL“.
  Quellen und Lizenzen in `THIRD_PARTY_LICENSES.txt` und im Abspann.
- **Versorgungskisten wie im Original:** anfangs versteckte Kisten erscheinen erst per Skript, jede Kiste hat einen
  begrenzten Vorrat (im Spielstand), getrennte Inhalte für Achse/Alliierte.
- **Missionsfiguren:** Nichtkämpfer geben keine Uniform ab, Namen von Wachen/Zivilisten/Verbündeten am Fadenkreuz,
  „Alle Gegner ausschalten“ zählt nur die vom Original gezählten Gegner, bestimmte Wachen durchschauen jede Tarnung.
- **Tarnung:** wirkt nur ohne sichtbare Waffen oder Rucksack der eigenen Seite.
- **Befehle:** „Vorwärts“ zur Lage des Anführers, „Dorthin“ verteilt nach Original-Tabelle, festes Tempo beim Folgen
  unter 10 m, Ziffernblock-Namen im HUD.
- Behoben: Verschluss der K98 (und anderer Repetierer) blieb in der Ego-Ansicht beim Zielen/Nachladen hängen.

## 0.10.7 (10.11.2026)

- **Befehlsmenü Ziffernblock:** Num 0 = alle, Num 1–6 = 1.–6. Kamerad (der aktive Soldat wird übersprungen), Name des
  Empfängers in der Menüzeile.
- **Befehle näher am Original:** Folgen (Rennen ab 10 m), Deckung suchen (20 m), Deckungsfeuer (4 s), Granate (unter 6 m
  „Negativ“), Feuerbefehle des stillen Angriffs.
- **Leise Befehle:** Kameraden folgen geduckt schleichend, feuern selbstständig nur mit schallgedämpfter Waffe und
  nehmen diese automatisch in die Hand.
- **Waffenstreuung nach Original-Formel** (Abweichung je Waffe aus der Waffentabelle, z. B. K98 ≈ 0,1°, MP 40 ≈ 1,4°).
- Tests stabiler (`test_support_strike`, `test_commands_orig`).

## 0.10.6 (10.11.2026)

- **Kameraden heilen:** Erste-Hilfe-Kit in die Hand, Kameraden (≤ 2 m) anklicken → Verband mit Animation und
  Fortschrittsbalken; Wirkung nach Erste-Hilfe-Wert des Heilenden. Einzelspieler und Mehrspieler (gleiches Team,
  Server prüft Abstand/Verband/Team, nicht im Deathmatch).
- **Soldatenwerte geprüft:** Gesundheit, Kraft/Traglast, Ausdauer, Schießen, Tarnung, Erste Hilfe und Schlösser wirken
  im Spiel, auch nach dem Laden und bei Ersatzleuten. Test `test_sas_values`.
- **Fehlende Waffenmodelle** (Panzerschreck, P08 SD, G43, MAS 36) mit eigenen Platzhaltermodellen in Hand, 3. Person,
  Ego-Ansicht und am Boden.
- Datenschutz-Hinweis im Internet-Mehrspieler in allen Spielsprachen (EN/FR/IT/ES/CS).
- Behoben: Erste-Hilfe-Kit blieb nach dem Tod beim Verbinden und Soldatenwechsel in der Ego-Ansicht in der Hand.

## 0.10.5 (10.11.2026)

- Internet-Mehrspieler: beim ersten Aufruf je Profil Hinweis zur Datenübertragung an den Masterserver (PC-Daten gehasht
  und verschlüsselt, Profilname, IP-Adressen gehasht; nur für Sicherheit und Serverbrowser; Spielstand/Rang lokal und am
  Server). Zustimmen speichert die Zustimmung im Profil, Ablehnen führt zurück ins Hauptmenü. Test `test_menu`.

## 0.10.4 (10.11.2026)

- Bereinigung unfertiger Daten.

## 0.10.3 (10.11.2026)

- **Dedizierter Server mit Konfigurations-Launcher** (nach dem Original-ServerLauncher): eigenes Fenster ohne Spielstart
  über `DedicatedServer.cmd` (liegt im Release-Paket) oder aus dem LAN-/Internet-Menü; Konfigurationen `ServerConfigs\*.cfg`
  neben der EXE, Reiter Allgemein/Regeln/Erweitert/Kooperativ/Server (Status, Log, Konsole). Test `test_dedicated_ui`.
- **Einsatzgebiet verlassen:** Warnung mit 10-s-Zähler, danach gilt die Mission als gescheitert (Einzelspieler).
- **Automatisches Nachladen** bei leerer Waffe.
- **Afrika 1:** Verstärkungspanzer fährt durch (kein Stehenbleiben am Hang), kein abstehendes Teil vor dem Panzer,
  Raketentreffer wirken wie im Original, Begleitschutz kommt, Verteidiger greifen aktiver an.
- **Gap-Analyse je Mission** (`docs/gap/*.md`): Skriptwege nach Alarm (Arktis 3/4, Norwegen) laufen weiter, Burma 2
  Sherman und Normandie 2 Halbkette erreichen alle Wegpunkte, Gegner verlieren das Ziel nach Original-Zeitgeber.
- **Sprengladungen:** Fortschrittsbalken beim Anbringen und Scharfmachen.
- Tests `test_fix0103*`, `test_af1_defenders`.

## 0.10.2 (09.11.2026)

- Afrika 1 schließt wieder ab: Verstärkungspanzer blieb in seiner Grube stecken (zu wenig Zugkraft, gegenseitiges Warten
  mit dem BMW-Gespann). Panzer mit Kriechgang im 1. Gang, Skriptfahrten fahren nach 1,5 s Blockade langsam weiter [E].
  Test `test_af1_finale`.
- Zwischensequenzen: eigene Figur sichtbar statt nur der Ego-Waffe, solange das Skript die Kamera führt
  (`CameraRig._script_camera`). Test `test_af1_cutscene`.
- Performance große Karten: Animationsauswahl ferner Figuren (> 60/120 m) und KI ferner Wachen/Patrouillen gestaffelt
  (`--anim_lod=0`, `--ai_lod=0`), Animationszeit −40…−73 % (`docs/status/perf_gross.md`).
- Gegner-KI (`docs/status/ai_orig2.md`, `--ai_orig2=0`): Granatauslöser nach Original 0x552200, defensive Stellungswahl
  über das Fußwegenetz (0x557D10), Rückzug unter 25 % Gesundheit [E] (`--ai_retreat=0`); 0x58C330 = Waffe in Anschlag.
- Test `test_tools_mines` robuster gegen zufällige Spawnpunkte.

## 0.10.1 (08.11.2026)

**Einzelspieler-KI (Abgleich mit dem Original, `docs/AI_AUDIT_ENEMY.md`, `docs/AI_AUDIT_ALLY.md`)**
- Gegner flankieren auf der eigenen Seite, feuern auch im Anmarsch/Laufen, Original-Zeitgeber (z. B. 15–25 s Warten nach
  Zielverlust), Gangwahl beim Annähern, Stellungsposten bleiben am Platz, Flanken-/Nachrückpunkte aus dem Fußwegenetz.
- Verbündete (z. B. Amerikaner in Schwerttänzer, Burma, Arktis) sind bewaffnet und feuern aus ihrer Stellung statt
  vorzurücken; Rebellen/Piloten u. ä. gehören zur Spielerseite.
- Schwerttänzer: Schlusssequenz mit Kamerafahrt, Mission endet erst danach.

**Grafik**
- Fotorealistische Himmel je Karte (CC0, Poly Haven, siehe `docs/SKY_SOURCES.md`), Original-Himmel als Option.
- Normandie 3: neues Wasser, Tag-/Nachtwechsel (1 Tag = 10 Minuten, im MP synchron).
- Lampen der Originalkarten leuchten als echte Lichter; Rauch nach Explosionen deutlich leichter.
- Mündungsfeuer an der echten Mündung, je Waffentyp.

**Waffen**
- Kugelfall wie im Original; Option „Präzises Zielen“ (aus; im MP Server-Regel).
- Scharfschützen: Luft anhalten mit Shift (4 s, danach Atemnot).

**Mehrspieler / Fahrzeuge**
- Eroberung: Einnahme sichtbar (Fahne, Meldungen, Fortschritt) und auf allen Rechnern festgehalten.
- Fahrzeuge erscheinen neu, Schützen sitzen richtig, Kanonen laden nach (Originalmunition), Granaten sprengen niemanden
  mehr aus dem Fahrzeug.
- Sichtweite im MP etwas größer.

**Fehlerbehebungen**
- Arktis 2: Gitterböden begehbar (Regel für alle Karten).

**Bekannt offen:** Original-Schuss-/Streuroutine nicht entschlüsselt; Respawnzeiten Fahrzeuge geschätzt; test_bots 1 schwankende Prüfung.

## 0.9.9 (07.11.2026)

**Neu**
- Option „Sichtweite“: CLASSIC = Nebel/Sichtweite wie im Original, NEU = ohne Nebel, volle Reichweite mit
  vereinfachten Details in der Ferne. Künstliche Zusatznebel entfernt, Himmel mit Horizontdunst/Sonnenhof/Sternen.
- Coop im LAN-/Internet-Menü: alle Einzelspieler-Missionen 1:1 als Coop-Karten.
- Kameraden halten zu Missionsbeginn ihre Position und folgen erst auf „Folgen“.

**Gore und Ragdoll**
- Leichen werden nicht mehr verzerrt/gestreckt (Knochenabstände bleiben, Gelenke begrenzt).
- Wunden je Kaliber und Trefferzone, Austrittswunden, Blutlachen nach Blutverlust; EXTRA GORE mit Schnittflächen.

**Fahrzeuge**
- Alle 31 Fahrzeugmodelle geprüft: Flak 38 auf dem Opel Blitz bedienbar, Panzer bremsen mit der Handbremse,
  Halbkette M3 fährt.

**KI und Missionen**
- Gegner bleiben deutlich seltener stehen (Wegfolge, unerreichbare Ziele, Untersuchen); Burma-Gegner sind wieder
  bewaffnet (japanische und weitere Waffen fehlten); Skript-Patrouillen laufen auch nach „Defensiv“.
- Trupp feuert nicht, wenn ein Kamerad in der Schusslinie steht.
- `_PlayerInRange` liefert wie im Original die Anzahl der Soldaten im Radius.
- Kanten zwischen Skript-Wegpunkten werden wie im Original geprüft.
- HD/4K-Texturen: fehlerhafte Hochskalierungen fallen automatisch auf die nächste Stufe zurück.

**Fehlerbehebungen**
- Dedizierter Server beendet sich nach „quit“ zuverlässig (auch nach Neustart durch den Wächter).
- MP-Bots laufen nicht mehr endlos denselben unerreichbaren Halteplatz an.
- Konverter legt bei fehlerhaftem Missionsnamen keine leeren Ordner mehr an; Build bricht bei solchen Ordnern ab.

**Tests**
- Neue Testreihen für Fahrzeugtypen, Sichtweite, Gore/Ragdoll und Gegner-Stillstand; Löser prüft Kampagnenketten
  (Afrika 1–6 erfüllbar), Fehlschlagpfade und Zeitlimits.

**Bekannt offen**
- Gegner-KI im Kampf noch nicht wie im Original (Flankenseite, Feuern in Bewegung), Schwerttänzer-Schlusssequenz
  ohne Kamerafahrt, Himmel noch ohne Original-Texturen – siehe Gap-Analyse vom 06.11.2026.

## 0.9.8 (02.11.2026)

**Arktis-Kampagne „menschlich“ geprüft**
- Neuer Löser-Modus `--human=1`: spielt nur mit Spielereingaben, ohne Teleports. arctic1–4 damit durchgespielt
  (arctic1/2 abgenommen, arctic3 von vorn alle Pflichtziele, arctic4 Ziele 1–4).

**Fehlerbehebungen**
- arctic2: Verschlossene Türen ohne Schlüssel lösen das Skript-Ereignis „Benutzen“ aus – die Skripte schließen sie
  beim ersten Benutzen auf (vorher blieben drei Türen für immer zu).
- Originalkarten: Kartengrenz-Deckel (ab 10 m Höhe) sind nur noch von unten fest – man kann nicht mehr auf der
  unsichtbaren Decke über der Karte herumlaufen (arctic3).
- Originalkarten: Unsichtbare Sichtverdecker haben keine Kollision mehr (arctic4, Normandie, czech4/5).
- Zerstörte Fahrzeuge gelten für die Skripte als zerstört (alps1: Zusatzziel „Gepanzertes Fahrzeug zerstören“,
  Übergabe an alps2).
- Join-Prüfung für Skript-Wegpunkte wie im Original; Soldaten warten länger auf Menschen im Weg statt abzubrechen.

**Navigation**
- NORWAY-Stahltreppen und Treppenhaus T1 (arctic2) sind im KI-Wegenetz (KI folgt auf nw1 4/8 statt 1/8).
- mp_normandy2 besser erreichbar (72/81 statt 64/81).

**Tests**
- Kampagnen-Löser: Ketten mit Übergabewerten zwischen Missionsteilen (`-Chain`), Zusatzziele, Fehlschlagpfade und
  Todesfallen werden erkannt und gemieden. Stichproben alps1→alps2 und norway1 komplett.
- Gesamttestreihe 75/77 grün (rot nur die Mess-Suiten Treppen und MP-Erreichbarkeit); `run_tests.ps1 -Exclude`.
- Neue Screenshots im README.

**Bekannt offen**
- arctic4: Tür zur Baracke mit den Unterlagen wird nicht immer angeboten; Ziele 5/6 im Löser nicht erreicht.
- Restliche Erreichbarkeitslücken (norway1-Oberdecks, czech2, mp_burma2, mp_alps1, mp_africa2).

## 0.9.7 (01.11.2026)

**Neu**
- Blut-Stufe „EXTRA GORE“ (Option, Standard aus): Körperteile werden je nach Treffer/Explosion abgetrennt, mit Physik und Stumpf.
- Mehrspieler-Coop auf Kampagnenkarten (Leben je Spieler/Team, Coop-Schwierigkeit); einmalige Spawnplätze ohne Respawn.
- Builds liefern EXE + separate `.pck` + `version.txt` (Versionsprüfung beim Start); neues Skript für das öffentliche Paket.

**Originaltreue (KI und Skripte)**
- Kampfautomat der Gegner nach dem Original (Anmarsch, Flankieren im 5-m-Raster, Nachrücken, Feuerpausen); Sichtweite nach
  Waffenhaltung, Sprint am auffälligsten, sofortige Erkennung.
- Alarm wie im Original: kein kartenweiter Alarm mehr in Originalmissionen, nur Zuruf/Schüsse in Hörweite.
- Schwierigkeitsgrad wirkt auf die Gegnerwerte; Scharfschützen-Posten, Skript-Angriffsbefehl, Uniformtarnung mit Tarnwert.
- Spielstände in Originalmissionen speichern den kompletten Skriptzustand.
- Skript-Auslöser im Original-Takt, Führerwege über das Original-Wegpunktnetz, weitere bisher wirkungslose Befehle umgesetzt.
- Original-Partikel, Zwischensequenz-Ende aus der Kameraanimation, Zerstörungsanimationen und explodierende Fässer.
- Leuchtturmlicht, Lichtwechsel, Gesichter, Wetterrichtung/-farbe aus den Skripten.

**Fehlerbehebungen**
- Operation Schwerttänzer: beide Panzer hingen fest – behoben.
- Graue Wände in der Ferne (africa1, arctic1) – Himmelswürfel des Originals stand fest in der Landschaft.
- arctic2: Löser-Sackgasse an Treppen behoben; arctic1 ohne Teleports bis Ziel 2 durchgespielt.

**Sicherheit und Robustheit**
- Mehrspieler: Munition/Respawn nicht mehr vom Client, Anmeldepflicht, Admin-Login-Sperre, gedrosselte Serverabfrage
  und Sprachchat, abgesicherte Admin-Befehle.
- Spielstände mit Versionsnummer und Rückfall auf Sicherungskopie; Einstellungen werden geprüft.
- Nutzer-Werkzeug: Export setzt nach Fehlern korrekt fort, funktioniert mit allen Sprachversionen, liefert Original-Schriften mit.

**Leistung**
- Wahrnehmung und HUD deutlich schneller; Texturkompression halbiert bis viertelt den Speicherbedarf.
- Zusammengefasste Level-Meshes (weniger Draw Calls); Navmesh-Cache: Ladezeit z. B. arctic1 109 s → 17 s.

**Tests:** Gesamttestreihe mit Sperre, Zeitlimit je Reihe und Ergebnistabelle; viele neue Testreihen.

**Bekannt offen**
- Arktis „menschlich“: arctic2–4 laufen noch; NORWAY-Treppen und weitere Erreichbarkeitslücken (B-010b).
- Neue Screenshots folgen mit dem nächsten Update.

## 0.9.6 (30.10.2026)

**Mehrspieler-Sicherheit und Stabilität (Code-Review)**
- Server prüft alle Client-Meldungen selbst: Fahrzeuge nur vom Fahrer, Schüsse mit Waffenbesitz/Munition/Feuerrate/
  Position, Bewegung plausibel (kein Teleport/Speedhack), Benutzen und Sitze mit Abstand/Belegung, ungültige
  Waffen-IDs und doppelte Anmeldungen werden verworfen. Neue Protokollversion (ältere Versionen können nicht beitreten).
- Profile: Testläufe löschen nur noch Testordner, Profilordner sind eindeutig.
- Spielstände werden geprüft geladen und sicher gespeichert (Zwischendatei + Sicherung).
- Zurückgesetzte Tastenbelegungen bleiben zurückgesetzt; VSync vereinheitlicht; „Gamma-Korrektur“ ist eine echte Gammakurve.

**Spiel**
- Drahtschere im Truppmenü: Kamerad schneidet den Zaun, KI nutzt danach die Lücke.
- Haltende Kameraden laufen nach einer Aktion nicht mehr zurück; kein Ausweichen beim Soldatenwechsel.
- Benutzen wählt das Objekt in Blickrichtung (Doppeltür africa1).
- Ragdoll-Leichen liegen natürlicher (straffere Gelenke).
- F3-Doppeldruck auch unter Last zuverlässig.
- Original-Steuerung vervollständigt (36 Aktionen ergänzt, u. a. Aktionsmenü ', Ziele Komma, Pause P, Handbremse Alt,
  Taktik-Tasten der Karte); eigene Verbesserungen bleiben. Belegungsseiten mit Unterseiten.
- Gegner-KI in Originalmissionen: Sicht- und Hörformel, Granatregel und dritter KI-Modus („Zombie“) wie im Original.
- Navigation: al1 stabil, NORWAY-Treppen teilweise verbessert.

**Grafik und HUD**
- Original-Schriften für Befehlsmenü, Waffenfeld, Meldungen und Ziele.
- HUD: Befehls-/Feuerregel-Symbole je Kamerad, Kompass-Treffer/-Geräusch, Fortschrittsbalken (Arbeit, Verband, Atemluft),
  Aktionssymbol, Kameradenname unter dem Fadenkreuz; lange Waffennamen werden gestaucht.
- Burma: Regen statt Schnee (Original-Wetter); africa1-Intro: Soldaten sitzen auf der Bank.

**Bekannt offen**
- NORWAY: Stahltreppen fehlen im Navigationsnetz; weitere Karten mit Erreichbarkeitslücken (B-010b).
- Kampftaktik (Deckung/Flanke/Rückzug) noch eigene Lösung.

## 0.9.5 (25.10.2026)

**Level**
- africa1 (Flughafen): Eingangstüren vorne/hinten und die Doppeltür im hinteren Vorraum lassen sich öffnen
  (im Original feste Flügel – bewusste Abweichung).
- Operation Schwerttänzer: Tür am Startpunkt lässt sich öffnen.
- arctic1: Zielmarker zuerst am Fremdenführer, danach am Eingang zur Basis.
- arctic1: Am Haupteingang zur Basis ist links wieder Schnee statt Wasser.
- arctic1: Zäune lassen sich mit der Drahtschere zerschneiden; Zaunfelder sind nicht mehr durchlaufbar.
- arctic1: Kein Durchfallen unter die Karte mehr, Kamera schaut nicht mehr durch Wände.
- arctic2: Zielmarker nur für freigegebene Sprengplätze (max. 4), lesbare Entfernung, sichtbarer Zeitzünder.

**Helme und Inventar**
- Helme sitzen wie im Original am Kopf; eigene Schüsse treffen weder eigenen Helm noch Körper.
- Zweite Langwaffe (Gewehr/MP) wird sichtbar auf dem Rücken getragen, Taste 1 tauscht Hand/Rücken.
- Munition und Granaten liegen mit Rucksack zuerst im Rucksack und belasten die Taschen nicht; Nachladen greift
  automatisch darauf zu (auch bei KI-Kameraden).
- Inventar: Mausrad blättert, Entf legt ab, Enter = Doppelklick-Aktion, Hinweistexte je Platz.

**Truppe und KI**
- Befehlsmenü im Original-Rahmen mit allen Aktionen der Original-Tabelle (Tür, Gegner, Gefangener, Leiche,
  Kamerad, Kiste, Mine …).
- Folgen mit Original-Formationen (Pfeil, Linie, Kolonne, Block), Abstandsstufen, Mindestabstand 1,2 m und
  Lösen bei Festhängen.
- arctic1: Gegner reagieren nach Alarm, Kanisternik wandert nicht mehr aus der Karte, Hund greift wie im
  Original an und hat die Original-Animationen.
- KI-Werte aus dem Original: Postenradius defensiver Gegner, Wechsel zu defensiv unter 50 % Gesundheit,
  Suchzeiten 20–30 s.

**Effekte**
- Ragdoll-Physik (Option, Standard an): Tod beginnt mit dem Original-Todesclip und geht fließend in die
  Physik über; Schuss- und Explosionswucht, auch im Mehrspieler.
- Blut auf der Kleidung (folgt Körper und Ragdoll), Blutspuren Verwundeter, Blut bei Messer/Splitter,
  roter Treffer-Rand am Bildschirm; alles über „BLUTFLECKEN“ abschaltbar.

**Bekannt offen**
- Neu festgestellt: Die KI nutzt zerschnittene Zäune noch nicht; der Drahtschere-Befehl im Truppmenü findet sie
  noch nicht.
- Neu festgestellt: Ragdoll-Leichen liegen teils zu verdreht.
- Bereits aus 0.9.4: Weiße Partikel in Burma, Figuren mit ausgestreckten Armen im Afrika-Intro.

## 0.9.4 (25.10.2026)
- Truppsteuerung: F1–F4 Soldaten markieren/übernehmen, 1–8 Waffen, B Fernglas, mittlere Maustaste Feuermodus.
- Schwere MGs nur liegend (auch Mehrspieler), Granatwurf sichtbar.
- Helme mit Kopfschuss-Schutz (fallen ab, wieder aufsetzbar), Rucksackraum nur mit Rucksack, HUD am Bildschirmrand.
- Navigation: große Karten, Leitern/Brücken für die KI, Treppen.
- Grafik (Wolken, Explosionen, 4K Ultra), Luftunterstützung im Mehrspieler, weitere Sprachen.

## 0.9.3 (24.10.2026)
- Einzelspieler-Kampagne: alle 24 Teile durchspielbar.
- Truppbefehle, Schaden und Hitboxen wie im Original, Bluteffekte, Ingame-Inventar, LAN-Menü,
  Nutzer-Werkzeug HD2-Werkzeuge.cmd für Export und Upscaling.
