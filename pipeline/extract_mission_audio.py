"""Umgebungsklänge und Musik einer Mission aus den Originalarchiven in orig_cache holen.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I extract_mission_audio.py ARCTIC1
Voraussetzung: orig_cache/<mission>/extra.json (fmt_mission_extra.py) und scripts/.

  - alle Dateien der Klangquellen (extra.json "sounds")      -> orig_cache/sounds/<datei>
  - Musik: Einträge der Musiktabelle, die die Skripte per PlayMusic/PlayCutsceneMusic
    nutzen, plus die Normal-/Action-Musik der Mission (Tabellenname "<Gebiet><n> Normal/Action")
                                                             -> orig_cache/music/<datei>
Die Daten bleiben lokal (orig_cache ist gitignored und vom Export ausgeschlossen).
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # -I: Skriptordner nicht im Pfad
from convert_mission import read_file, CACHE

ARCHIVES = ["Sounds.dta", "others.dta"]


def find_audio(name, kind):
    if "." not in name:
        name += ".wav"     # manche Einträge (z. B. ARCTIC2) ohne Endung
    cands = ["sounds/" + name, "sounds/music/" + name, "music/" + name, name] if kind == "music" \
        else ["sounds/" + name, "sounds/ambient/" + name, name]
    for c in cands:
        try:
            d = read_file(c, ARCHIVES)
        except (KeyError, OSError):
            d = None
        if d:
            return d
    return None


def main(mission):
    mdir = os.path.join(CACHE, mission.lower())
    extra = json.load(open(os.path.join(mdir, "extra.json"), encoding="utf-8"))
    sdir = os.path.join(CACHE, "sounds")
    mudir = os.path.join(CACHE, "music")
    os.makedirs(sdir, exist_ok=True)
    os.makedirs(mudir, exist_ok=True)
    ok, missing = 0, []
    for f in sorted({s["file"] for s in extra.get("sounds", []) if s.get("file")}):
        dst = os.path.join(sdir, f.lower() if "." in f else f.lower() + ".wav")
        if os.path.exists(dst):
            ok += 1
            continue
        d = find_audio(f, "sound")
        if d is None:
            missing.append(f)
            continue
        open(dst, "wb").write(d)
        ok += 1
    # Musik: Skriptaufrufe + Normal/Action der Mission
    used = set()
    for p in glob.glob(os.path.join(mdir, "scripts", "**", "*.scr"), recursive=True):
        for m in re.finditer(r"(?i)Play(?:Cutscene)?Music\(\s*(\d+)", open(p, encoding="latin-1").read()):
            used.add(int(m.group(1)))
    # Normal-/Action-Musik der Mission: Gebiet laut Missionsordner -> Name in der Musiktabelle
    # (IngameSounds.def schreibt z. B. "Arctic1 Normal", "Arctic 2  Normal", "Afrika 6 Normal", "Afrika Action").
    # Bevorzugt Gebiet+Nummer, sonst das Gebiet allein.
    regions = {"ARCTIC": "arctic", "AFRICA": "afrika", "NORWAY": "norway", "BURMA": "burma", "ALPS": "alps",
               "NORMANDY": "normandy", "CZECH": "czech"}
    m_area = re.match(r"([A-Za-z]+?)(\d*)$", mission)
    key = regions.get(m_area.group(1).upper(), "") if m_area else ""
    num = m_area.group(2) if m_area else ""
    table = extra.get("music_table", [])
    mission_music = {}
    for exact in (True, False):
        for e in table:
            nm = e["name"].lower().replace(" ", "")
            if not key or "cut" in nm:
                continue
            ok = nm.startswith(key + num) if exact and num else (nm.startswith(key) and not nm[len(key):len(key) + 1].isdigit())
            if not ok:
                continue
            for kind in ("action", "normal"):
                if kind in nm and kind not in mission_music:
                    mission_music[kind] = e["files"][0].lower()
                    used.add(e["index"])
    mus_ok = []
    for e in table:
        if e["index"] not in used:
            continue
        for f in e["files"]:
            dst = os.path.join(mudir, f.lower())
            if os.path.exists(dst):
                mus_ok.append(f)
                continue
            d = find_audio(f, "music")
            if d is None:
                missing.append(f)
                continue
            open(dst, "wb").write(d)
            mus_ok.append(f)
    json.dump({"music_indices": sorted(used), "mission_music": mission_music},
              open(os.path.join(mdir, "audio.json"), "w"), indent=1)
    print("Klänge: %d, Musik: %s, Missionsmusik: %s, fehlend: %s" % (ok, mus_ok, mission_music, missing[:10]))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main(sys.argv[1])
