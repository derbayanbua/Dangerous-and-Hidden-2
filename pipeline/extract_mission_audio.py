"""Umgebungsklänge und Musik einer Mission aus den Originalarchiven in orig_cache holen.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I extract_mission_audio.py ARCTIC1
Voraussetzung: orig_cache/<mission>/extra.json (fmt_mission_extra.py) und scripts/.

  - alle Dateien der Klangquellen (extra.json "sounds")      -> orig_cache/sounds/<datei>
  - Musik: Einträge der Musiktabelle, die die Skripte per PlayMusic/PlayCutsceneMusic
    nutzen, plus die Normal-/Action-Musik der Mission (scene2.bin-Kopf 0xB840/0xB880)
                                                             -> orig_cache/music/<datei>
  - Fahrzeugklänge je Fahrzeugakteur (Dateinamen im actors.bin-Parameterblock) -> audio.json "vehicles"
Die Daten bleiben lokal (orig_cache ist gitignored und vom Export ausgeschlossen).
"""
import glob
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # -I: Skriptordner nicht im Pfad
from convert_mission import read_file, CACHE

ARCHIVES = ["Sounds.dta", "others.dta"]


def _chunks(b, off, end):
    p = off
    while p + 6 <= end:
        cid, size = struct.unpack_from("<HI", b, p)
        if size < 6 or p + size > end:
            return
        yield cid, p + 6, p + size
        p += size


def vehicle_sounds(mdir):
    """Fahrzeugklaenge je Akteur (actors.bin Typ 4): Dateinamen im Parameterblock (z. B. kubel_on/_of/_0.._4/_R,
    tr_gear*, carcrx*). Nur Dateien, die es in Sounds.dta gibt; Reihenfolge wie im Block."""
    sj = os.path.join(mdir, "scene.json")
    if not os.path.exists(sj):
        return {}
    from convert_mission import archive
    have = set()
    for a in ("Sounds.dta", "patch.dta"):
        have.update(k.split("\\")[-1] for k in archive(a).index if k.startswith("sounds\\"))
    out = {}
    for a in json.load(open(sj, encoding="utf-8")).get("actors", []):
        if a.get("actor_type") != 4:
            continue
        b = bytes(a.get("params", []))
        files = []
        for m in re.finditer(rb"[A-Za-z0-9_]+\.wav", b):
            f = m.group().decode("latin-1").lower()
            # Namen stehen in festen Feldern; davor kann ein Laengen-/Restbyte stehen ("2kubel_x.wav")
            for k in range(3):
                if f[k:] in have:
                    if f[k:] not in files:
                        files.append(f[k:])
                    break
        if files:
            out[a["name"]] = {"model": a.get("model", ""), "files": files}
    return out


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
    # Normal-/Action-Musik der Mission [B]: scene2.bin-Kopf, Chunk 0xB840 = Index "normal", 0xB880 = Index "action"
    # (hd2.exe Missionslader 0x6CD603: 0xB840 -> Mission+0xC8, 0xB880 -> Mission+0xCC; Umschaltung 0x69E970).
    table = extra.get("music_table", [])
    mission_music = {}
    music_index = {"normal": -1, "action": -1}
    s2 = read_file("missions/%s/scene2.bin" % mission.upper(), ["Missions.dta"])
    if s2:
        for t, s, e in _chunks(s2, 0, len(s2)):
            if t == 0x4C53:
                for t2, s2_, e2 in _chunks(s2, s, e):
                    if t2 == 0x4000:
                        break
                    if t2 in (0xB840, 0xB880) and e2 - s2_ >= 4:
                        music_index["normal" if t2 == 0xB840 else "action"] = struct.unpack_from("<i", s2, s2_)[0]
    for kind, idx in music_index.items():
        for e in table:
            if e["index"] == idx and e["files"]:
                mission_music[kind] = e["files"][0].lower()
                used.add(idx)
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
    vehicles = vehicle_sounds(mdir)
    json.dump({"music_indices": sorted(used), "mission_music": mission_music, "music_index": music_index,
               "vehicles": vehicles},
              open(os.path.join(mdir, "audio.json"), "w"), indent=1)
    print("Klänge: %d, Musik: %s, Missionsmusik: %s (Index %s), Fahrzeuge: %d, fehlend: %s" % (
        ok, mus_ok, mission_music, music_index, len(vehicles), missing[:10]))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main(sys.argv[1])
