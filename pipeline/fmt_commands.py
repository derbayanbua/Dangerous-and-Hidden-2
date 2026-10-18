"""Original-Befehlsmenue (Soldaten-Befehle, Tasten BEFEHL AN ALLE / BEFEHL AN 1..6) und Befehls-Sprachausgabe
(HD2 v1.12) lesen.

Quellen (nur gelesen, Patch zuerst):
  hd2.exe                 Menuetabellen in .data: je Menue 10 Eintraege {i32 Text-ID, i32 Aktion}
                          Einzelspieler-Satz 0x83B610 (Auswahl 0x4BF442: [0x982100]&7 == 7), Mehrspieler 0x83B980;
                          Menue-ID 50 = Hauptmenue, 51..59 = Untermenues (Kopie 0x4BFFE0, Sprungtabelle 0x4C0344)
  TABLES\\speech.set      Sprachsaetze (others.DTA): Satz -> Ereignis -> Liste Sound-IDs (9130xxxx laut, 9115xxxx leise)
  SOUNDS\\9000xxxx.wav    deutsche Aufnahmen; Laufzeit-ID = 90000000 + (ID mod 10000) (hd2.exe 0x5B0440)

Ausgabe: orig_cache/commands.json, orig_cache/sounds/9000xxxx.wav (nur die benutzten Befehls-/Antwortsaetze)
Belege/Adressen: DangerousHidden2/docs/re_notes_commands.md

Aufruf: pyenv\\Scripts\\python.exe -I fmt_commands.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402

EXE = os.path.join(cm.ORIG, "hd2.exe")
SP_BASE = 0x83B610
MP_BASE = 0x83B980
# Menue-ID -> Tabellenoffset (Sprungtabelle 0x4C0344: 58 -> +0x2D0, 59 -> +0x280)
MENU_OFFSETS = {50: 0x000, 51: 0x050, 52: 0x0A0, 53: 0x0F0, 54: 0x140, 55: 0x190, 56: 0x1E0, 57: 0x230,
                58: 0x2D0, 59: 0x280}
# Sprachsaetze des eigenen Trupps (Teamplatz 1..4, hd2.exe 0x695AD0)
VOICE_SETS = ["English #1", "English #2", "English #3", "English #4"]
# benutzte Sprach-Ereignisse (speech.set): Befehle (laut/leise) + Antworten
USED_EVENTS = list(range(0, 0x2E)) + [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x3A, 0x3B, 0x40, 0x41,
                                      0x42, 0x43, 0x58, 0x59, 0x5A, 0x5B, 0x68, 0x69, 0x7D, 0x7E, 0x7F, 0x80]


def read_exe_tables():
    import pefile
    pe = pefile.PE(EXE, fast_load=True)
    base = pe.OPTIONAL_HEADER.ImageBase

    def table(va):
        raw = pe.get_data(va - base, 80)
        return [list(struct.unpack_from("<ii", raw, 8 * i)) for i in range(10)]

    sp = {str(mid): table(SP_BASE + off) for mid, off in MENU_OFFSETS.items()}
    mp = {str(mid): table(MP_BASE + off) for mid, off in MENU_OFFSETS.items()}
    # Plausibilitaet: Hauptmenue beginnt mit 7200 "Bewegung", Eintrag 10 = 7274 "Abbrechen"
    if sp["50"][0][0] != 7200 or sp["50"][9][0] != 7274 or sp["51"][9][0] != 7275:
        raise SystemExit("Unerwartete hd2.exe-Version: Menuetabellen nicht gefunden")
    return sp, mp


def chunks(b, off, end):
    p = off
    while p + 6 <= end:
        cid, size = struct.unpack_from("<HI", b, p)
        if size < 6 or p + size > end:
            return
        yield cid, p + 6, p + size
        p += size


def read_speech():
    b = cm.read_file("tables/speech.set", ["others.DTA"])
    if b is None:
        raise SystemExit("TABLES\\speech.set nicht gefunden")
    sets = {}
    for _, o, e in chunks(b, 0, len(b)):                 # 0x03E8 Wurzel
        for _, so, se in chunks(b, o, e):                 # je Sprachsatz
            name, events = None, {}
            for cid, co, ce in chunks(b, so, se):
                if cid == 1:
                    name = b[co:ce].split(b"\0")[0].decode("latin-1")
                elif cid == 2:
                    for ev, eo, ee in chunks(b, co, ce):
                        ids = [struct.unpack_from("<I", b, vo)[0] for _, vo, ve in chunks(b, eo, ee) if ve - vo == 4]
                        if ids:
                            events[str(ev)] = ids
            if name:
                sets[name] = events
    return sets


def german_id(i):
    return 90000000 + i % 10000


def main():
    sp, mp = read_exe_tables()
    sets = read_speech()
    voices = {}
    wanted = set()
    for vs in VOICE_SETS:
        ev = sets.get(vs, {})
        voices[vs] = {k: [german_id(i) for i in v] for k, v in ev.items() if int(k) in USED_EVENTS}
        for v in voices[vs].values():
            wanted.update(v)
    snd_dir = os.path.join(cm.CACHE, "sounds")
    os.makedirs(snd_dir, exist_ok=True)
    have = 0
    missing = []
    for i in sorted(wanted):
        dst = os.path.join(snd_dir, "%08d.wav" % i)
        if os.path.exists(dst):
            have += 1
            continue
        data = cm.read_file("sounds/%08d.wav" % i, ["Sounds.dta"])
        if data:
            open(dst, "wb").write(data)
            have += 1
        else:
            missing.append(i)
    out = {
        "source": "hd2.exe Menuetabellen 0x83B610 (SP) / 0x83B980 (MP), TABLES\\speech.set, SOUNDS\\9000xxxx.wav; "
                  "docs/re_notes_commands.md",
        "menus_sp": sp, "menus_mp": mp, "voices": voices,
    }
    with open(os.path.join(cm.CACHE, "commands.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print("Menues: %d (SP) / %d (MP); Sprachsaetze: %d; Aufnahmen: %d von %d (fehlend: %s)" % (
        len(sp), len(mp), len(voices), have, len(wanted), missing[:10]))


if __name__ == "__main__":
    main()
