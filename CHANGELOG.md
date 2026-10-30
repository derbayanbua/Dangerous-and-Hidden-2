# Changelog

Versionierung: vorerst immer 0.9.x – jeder Commit nach GitHub zählt die letzte Stelle hoch und bekommt einen Tag.

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
