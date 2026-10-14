# Dangerous Hidden 2

**Ein Fanprojekt mit dem Versuch, das großartige alte *Hidden & Dangerous 2* in einer modernen Engine neu umzusetzen.**

Kein offizielles Spiel des Herstellers, keine kommerzielle Absicht – einfach nur die Liebe zum Spiel ❤️

> 🛒 **Kauft das Original!** *Hidden & Dangerous 2* gibt es z. B. bei [GOG](https://www.gog.com/) – ohne eine
> eigene Original-Installation funktioniert dieses Projekt auch gar nicht.

---

## Worum geht es?

*Dangerous Hidden 2* ist eine **komplette Neuentwicklung mit [Godot 4](https://godotengine.org/)** (GDScript) –
ein taktischer WW2-Squad-Shooter, der sich spielerisch eng an *Hidden & Dangerous 2* orientiert:
SAS-Trupp, Kampagnen in Arktis, Nordafrika, Norwegen, Burma, Alpen, Normandie und Tschechien, Schleichen,
Tarnung, Fahrzeuge, Original-Missionsabläufe.

- **Nah am Original:** Leveldesign, Missionsziele, Missionsskripte, Dialoge, Musik und Klänge sollen sich so
  anfühlen wie damals. Die Original-Missionsskripte werden von einem eigenen Compiler/Interpreter ausgeführt.
- **Quality of Life:** wo es dem Spielgefühl hilft, ist die Bedienung moderner (siehe unten).
- **Neu geschrieben:** Engine-Code, KI, Physik, Oberfläche und Werkzeuge sind eigene Entwicklungen.
  Es wird kein Code des Originals verwendet.

## Keine Originaldaten im Repository

Dieses Repository enthält **keine Dateien des Originalspiels** – keine Modelle, Texturen, Klänge, Texte oder
Skripte. Wie bei anderen Engine-Nachbauten (z. B. OpenMW) werden die Daten **aus der eigenen, legal erworbenen
Installation** lokal in einen Cache konvertiert (`orig_cache/`, per `.gitignore` ausgeschlossen, wird nicht
weitergegeben).

*Hidden & Dangerous* und alle zugehörigen Namen, Marken und Inhalte gehören ihren jeweiligen Rechteinhabern.
Dieses Projekt steht in keiner Verbindung zu ihnen und wird von ihnen weder unterstützt noch geprüft.

## Quality of Life gegenüber dem Original

- Moderne Steuerung: Laufschritt als Standard, Shift = Sprint, Leertaste springt bzw. klettert automatisch
  auf Hindernisse und über Zäune/Mauern
- Waffen-/Ausrüstungswahl per Mausrad-Liste, Granate sofort mit G, frei umbelegbare Tasten
- Scharfe Oberfläche in jeder Auflösung und jedem Seitenverhältnis (bis 4K/5K, 21:9)
- Vereinfachtes Inventar (Taschen + Rucksack als ein gemeinsamer Bereich)
- Taktische Karte mit Einzelbefehlen (pausiert das Spiel)
- Leitern, Türen, Schalter und Sprengplätze per Benutzen-Taste; Schutz vor Sackgassen, wenn ein benötigter
  Gegenstand fehlt
- Optional KI-hochskalierte HD-Texturen (aus den eigenen Originaltexturen erzeugt)

## Voraussetzungen

- [Godot 4.7.1](https://godotengine.org/) (Standard-Version, kein .NET nötig)
- Eine Installation von *Hidden & Dangerous 2* (z. B. von GOG)
- Python 3 mit Pillow und numpy für die Konvertierung (Skripte in `pipeline/`)

## Schnellstart

1. **Originaldaten konvertieren** (einmalig, aus der eigenen Installation):
   ```
   python -I pipeline/convert_mission.py ARCTIC1
   ```
   bzw. alle Missionen mit `tools/convert_all.ps1`. Die Pfade zur Original-Installation stehen am Anfang der
   Skripte.
2. **Spielen:**
   ```
   tools\godot.cmd -- --mission=a1_blizzard
   ```
   oder einfach `tools\godot.cmd` für das Hauptmenü.
3. **Tests:** `powershell -File tools\run_tests.ps1` (headless, alle Suiten)

## Stand

In aktiver Entwicklung. Die Arktis-Kampagne läuft mit Originaldaten durchgehend, weitere Kampagnen sind
konvertiert und werden Schritt für Schritt spielbar gemacht. Bekannte Lücken und Annahmen sind in `docs/` und
`CLAUDE.md` dokumentiert; die Erkenntnisse über die Originalformate stehen in `docs/RE_FINDINGS.md` und den
`docs/re_notes_*.md`.

## Steuerung (Standard)

WASD bewegen · Shift sprinten · C hocken · Z liegen · Leertaste springen/klettern · Q/E lehnen ·
LMT feuern · RMT zielen · R nachladen · Mausrad Ausrüstungswahl · G Granate · F benutzen ·
V 1./3. Person · F1–F4 Soldat wählen · M taktische Karte · F5/F9 Schnellspeichern/-laden · Esc Pause

---

*Gemacht von Fans für Fans. Wenn euch das gefällt: Kauft das Original und spielt es – es lohnt sich bis heute.*
