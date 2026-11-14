# Changelog



## 0.11.5 (14.11.2026)

**DE**
- **Stabilität dedizierter Server:** Endlosschleife der Bot-Navigation (Deckungssuche) behoben, doppeltes Trennen
  bereits getrennter Spieler und freigegebene Rückruf-Funktionen abgesichert; Langlauf mit 24 Bots ohne Hänger und ohne
  Speicherzuwachs.
- **Masterserver nicht erreichbar:** Das Spiel zeigt einen Hinweis (auch bei Serverfehlern/Überlastung), dass der
  Beitritt per IP trotzdem funktioniert (alle Sprachen).
- **Rangliste (online):** Die Profil-Anmeldung am Masterserver fand nie statt – behoben, dadurch werden Spiele wieder
  gewertet. Neuer Bildschirm **RANGLISTE** im Internet-Menü (signierte Abfrage, Blättern, eigenes Konto hervorgehoben).
  Online gilt nur noch der Master-Dienstgrad; Rundenrang-Meldungen nur im LAN.
- **Waffen:**
  - Zweibeinwaffen (u. a. Bren, DP, ZB 26, Typ 97) feuern in SP und MP **nur liegend**, mit Hinweis im HUD; die
    **BAR** bleibt stehend und hockend feuerbar. KI legt sich zum Feuern hin, der Server prüft die Regel.
  - **Zielfernrohr-Rückstoß** korrigiert (Faktor nach Original statt 1,0): Scharfschützengewehre schlugen bis zu 3°
    hoch und trafen dadurch schlecht.
  - Rückstoß je Waffenart nach Original; im Mehrspieler gelten wie im Original immer die vollen Werte.
- **Panzer:** Visiersicht (Fahrer/Schütze) ist Standard, V schaltet auf Verfolgerkamera; MG-Fadenkreuz zeigt auf den
  echten Treffpunkt.
- **Grafik:**
  - Gleiche Lichtstimmung auf allen Grafikstufen: **SSAO und Glow immer an** (nur die Qualität sinkt), fehlendes
    indirektes Licht und Volumennebel werden über Umgebungslicht und Nebel ausgeglichen.
  - Neuer Schneefall (weiche Flocken unterschiedlicher Größe, Wind, Taumeln, folgt der Kamera).
  - Arctic 1 (MP) dunkler und stimmiger; Mehrspielerkarten werden nachts nicht mehr aufgehellt.
  - Normandy 3 (MP): Wasser repariert.
- **Tag-Nacht-Wechsel im Mehrspieler für alle Karten** (LAN und Internet gleich), Serverregeln `daynight` (an/aus,
  Standard aus), `daynightstart` (Startstunde, −1 = Kartenstimmung) und `daynightcycle` (Minuten je 24 h); einstellbar
  im Server-Menü, Launcher/Config und Konsole, sichtbar in SPIEL-INFO. Einzelspieler bleibt bei der Originalstimmung.
- **Testkarte Bavaria:** Tag-/Nachtzyklus mit Sonne, Mond, Himmel und Nebel, Raumlicht, Laternen an Wegen und
  Haustüren, begehbare Obergeschoss-Fenster, größere Fernsicht mit Außenwald und Panorama.
- **KI-Wegsuche (B-010b):** Pfadsuche mit bis zu 65536 Polygonen statt 4096 – lange Wege auf großen Karten werden
  vollständig gefunden; zusätzliche Treppen-/Rampenverbindungen; Ausweichcode für Figuren außerhalb des Netzes entfernt.
- **Erfüllbarkeitsprüfung (B-032c):** Begleitfiguren im Löser geschützt, Zweigprüfung durch gezieltes Ausschalten
  einzelner Gegner.
- **Lippensynchronität (B-052)** für alle sprechenden Figuren nach den Original-Lippendaten.
- **Vögel und Fische (B-053)** aus den Originaldaten der Missionen.
- **Einstellungen:** Tastenmenü vollständig umbelegbar (Doppelbelegung wird getauscht, Rechtsklick löscht, Zurückblättern),
  ZURÜCK-Feld in den Grafikeinstellungen (Esc wirkt ebenso).
- **LAN-Menü** im Original-Aufbau wie der Internet-Serverbrowser.
- **Linux-Build (neu):** offizielles Paket für Linux x86_64 (`.tar.gz` mit Startskripten für Spiel und dedizierten
  Server); unter Linux bisher wenig erprobt. Filme werden unabhängig von Groß-/Kleinschreibung gefunden.
- **Eigener Körper in der 1. Person:** die Figur wirft weiter Schatten, beim Blick nach unten sind die Beine sichtbar;
  mit Zielfernrohr/Fernglas nur Schatten. Option SPIEL „KÖRPER IN 1. PERSON“ (Standard an).
- **Tests schreiben nicht mehr in echte Nutzerdateien** (bekannte Server, Favoriten, Filter, Kartenlisten, Schlüssel).

**EN**
- **Dedicated server stability:** fixed an endless loop in bot navigation (cover search), guarded against disconnecting
  already disconnected players and freed callbacks; long run with 24 bots without hangs or memory growth.
- **Master server unreachable:** the game shows a notice (also on server errors/overload) that joining by IP still
  works (all languages).
- **Leaderboard (online):** the profile login at the master server never happened – fixed, so matches are rated again.
  New **LEADERBOARD** screen in the internet menu (signed query, paging, own account highlighted). Online only the
  master rank counts; round rank messages are LAN only.
- **Weapons:**
  - Bipod weapons (e.g. Bren, DP, ZB 26, Type 97) fire **prone only** in SP and MP, with a HUD notice; the **BAR**
    can still be fired standing and crouching. AI goes prone to fire, the server checks the rule.
  - **Scope recoil** fixed (original factor instead of 1.0): sniper rifles kicked up to 3° and therefore hit poorly.
  - Recoil per weapon type as in the original; multiplayer always uses the full values, as in the original.
- **Tanks:** sight view (driver/gunner) is the default, V switches to the chase camera; MG crosshair points at the real
  impact point.
- **Graphics:**
  - Same lighting mood on all quality levels: **SSAO and glow always on** (only quality drops); missing indirect light
    and volumetric fog are compensated via ambient light and fog.
  - New snowfall (soft flakes of varying size, wind, tumbling, follows the camera).
  - Arctic 1 (MP) darker and moodier; multiplayer maps are no longer brightened at night.
  - Normandy 3 (MP): water fixed.
- **Day/night cycle in multiplayer for all maps** (LAN and internet alike), server rules `daynight` (on/off, default
  off), `daynightstart` (start hour, −1 = map mood) and `daynightcycle` (minutes per 24 h); set in the server menu,
  launcher/config and console, shown in GAME INFO. Single player keeps the original mood.
- **Test map Bavaria:** day/night cycle with sun, moon, sky and fog, room lighting, lanterns along paths and at front
  doors, usable upper-floor windows, longer view distance with outer forest and panorama.
- **AI pathfinding (B-010b):** path search up to 65536 polygons instead of 4096 – long routes on large maps are found
  completely; additional stair/ramp links; fallback code for figures off the navmesh removed.
- **Completability check (B-032c):** escort figures protected in the solver, branch checks by removing specific enemies.
- **Lip sync (B-052)** for all speaking characters from the original lip data.
- **Birds and fish (B-053)** from the original mission data.
- **Settings:** key menu fully rebindable (duplicates are swapped, right-click clears, page back), BACK field in the
  graphics settings (Esc works too).
- **LAN menu** in the original layout like the internet server browser.
- **Linux build (new):** official package for Linux x86_64 (`.tar.gz` with start scripts for the game and the dedicated
  server); little tested on Linux so far. Movies are found regardless of upper/lower case.
- **Own body in first person:** the figure keeps casting its shadow and the legs are visible when looking down; with a
  scope/binoculars only the shadow. Option GAME "KÖRPER IN 1. PERSON" (default on).
- **Tests no longer write to real user files** (known servers, favourites, filters, map lists, keys).

## 0.11.3 (11.11.2026) – Hotfix

**DE**
- **Masterserver-Anmeldung:** Bei kurzen Netzwerkfehlern schickt das Spiel eine Anfrage nicht mehr unverändert erneut,
  sondern baut sie mit neuem Zeitstempel neu auf. Bisher konnte der Masterserver das als Wiederholungsangriff werten und
  einen Server sperren.
- Nach einer Sperre meldet sich ein Server gestaffelt (5/15/60 min bzw. nach der Vorgabe des Masterservers) erneut an
  statt jede Minute.

**EN**
- **Master server registration:** after short network errors the game no longer resends an identical request; it builds
  a new one with a fresh timestamp. Previously the master server could treat this as a replay attack and ban the server.
- After a ban, a server retries registration with a staggered delay (5/15/60 min or as told by the master server)
  instead of every minute.

## 0.11.2 (11.11.2026) – Hotfix

**DE**
- **Spawn-Schutz:** Nach dem Spawn ist man für die Schutzzeit unverwundbar und kann nicht schießen, werfen, stechen
  oder Ladungen legen (Spieler und KI gleich). Der Schutz endet nach Ablauf der Zeit; der Server verwirft Aktionen in
  dieser Zeit. Anzeige „Respawn-Schutz N s – Feuern gesperrt“.
- Diagnose für dedizierte Server: `--bot_trace=1` protokolliert Zustand und Ziele der KI-Soldaten.
- Paketbau: Skript für den Build-Schlüssel auf reines ASCII umgestellt.
- Behoben: Fehlermeldung beim Abschießen eines Helms (fehlende Zweitwaffe auf dem Rücken) und vier ähnliche Stellen.

**EN**
- **Spawn protection:** after spawning you are invulnerable for the protection time and cannot shoot, throw, stab or
  place charges (players and AI alike). Protection ends when the time runs out; the server rejects such actions during
  it. HUD shows "Respawn protection N s – firing locked".
- Diagnostics for dedicated servers: `--bot_trace=1` logs state and targets of AI soldiers.
- Packaging: build-key script converted to plain ASCII.
- Fixed: error when a helmet is shot off (no second weapon on the back) and four similar places.

## 0.11.1 (11.11.2026) – Online-Mehrspieler

- **Internet-Mehrspieler mit Serverbrowser** im Stil des Originals: Serverliste über den Masterserver (sortierbar, Filter,
  Spiel-Info, Favoriten, Direktverbindung per IP). Nicht verifizierte Server sind mit „!“ markiert und werden vor dem
  Beitritt gewarnt (keine Ränge).
- **Server erstellen** im Stil des Originals, alle Server-Regeln bedienbar; neue Regel Gesundheit ORIGINAL / MEHR LEBEN.
- **Spieler-Setup vor dem Spawnen:** Nach jedem Beitritt wird zuerst der Soldat ausgerüstet.
- **Neue Mehrspieler-Klassen:** Sanitäter, Scharfschütze, Panzerabwehr, Sturmsoldat, Schleicher, Schwerer Schütze,
  Aufklärer – mit Soldatenwerten wie im Einzelspieler, automatischer Soldatenwahl, Uniform passend zur Karte und
  Ersatzwaffen nach Kartenfreigabe. Doppelklick legt im Ausrüstungsmenü ab.
- **Ränge und Karriere:** 15 Dienstgrade mit XP; online maßgeblich der Masterserver (Abzeichen und Dienstgrad in der
  Punktetabelle, Beförderungsmeldung, Profilseite), im Einzelspieler lokales Karriereprofil, im LAN wie im Original.
  Faire Wertung von Unterstützung und Heilen.
- **Dedizierter Server** meldet sich als Internet-Server beim Masterserver an (Server-ID im Launcher).
- Netzprotokoll DH2-LAN-6 (ältere Versionen können nicht mehr mitspielen).
- **Kartenobjekte**, die an Teilen anderer Modelle hängen (z. B. Regalbretter), liegen jetzt richtig; festgefahrene
  Skriptfahrzeuge befreien sich.
- **Arktis 2 / Konsole:** Konsole öffnet zuverlässig mit ^ auf deutscher Tastatur, `pos` gut lesbar.
- README mit aktuellem Stand und neuen Screenshots.

## 0.10.9 (11.11.2026)

- **Fehlende Missionsobjekte ergänzt:** tief verschachtelte Akteursdefinitionen werden jetzt vollständig gelesen –
  Tschechien 1 (18 Lichtschalter, Fässer, Verstärkung), Normandie 1 (Original-Spielerstarts, Fässer, weitere Figur),
  Normandie MP (Spawnpunkte, Fässer, Leitern, MG u. a.).
- **Konsolenbefehl `pos`:** zeigt Mission, Position und Blickrichtung und kopiert sie in die Zwischenablage (für
  Fehlermeldungen).
- Lokaler Build entfernt vor dem Bauen ältere Release-Ordner.

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
