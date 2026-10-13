"""Original-Missionsdatenbank GAMEDATA\\Gamedata00.gdt (patch.dta, sonst others.DTA) lesen.

LS3D-Chunks (u16 Kennung, u32 Größe inkl. 6 Byte Kopf). Je Missionsknoten 0x0032:
  0x0033 Missions-ID (= Titeltext-ID-Bezug, siehe docs/re_notes_profiles.md)   0x0036 Missionsordner
  0x0035 Briefingbild   0x0028 Ziel {0x0029 Text-ID, 0x002A ?, 0x002B 1 = Zusatzziel}
  Reihenfolge der 0x0028 = Index für SetObjectiveStatus (1, 2, …) – belegt an ARCTIC1: 6005/6006 Zusatzziele.
  0x0014/0x0018 Ausrüstungsliste (16 Byte: u32 Gegenstand?, u32 Anzahl?, …) – Bedeutung nicht vollständig belegt.

Aufruf (venv): pyenv\\Scripts\\python.exe -I fmt_gamedata.py  -> orig_cache/missions_db.json
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402


def chunks(b):
    p = 0
    while p + 6 <= len(b):
        cid, sz = struct.unpack_from("<HI", b, p)
        if sz < 6 or p + sz > len(b):
            return
        yield cid, b[p + 6:p + sz]
        p += sz


def is_container(b):
    p = 0
    if len(b) < 6:
        return False
    while p < len(b):
        if p + 6 > len(b):
            return False
        _, sz = struct.unpack_from("<HI", b, p)
        if sz < 6 or p + sz > len(b):
            return False
        p += sz
    return True


def find(b, cid_wanted, out):
    for cid, pay in chunks(b):
        if cid == cid_wanted:
            out.append(pay)
        elif len(pay) > 4 and is_container(pay):
            find(pay, cid_wanted, out)


def cstr(b):
    return b.split(b"\0")[0].decode("latin-1")


def parse(data):
    missions = []
    nodes = []
    find(data, 0x0032, nodes)
    for node in nodes:
        m = {"objectives": [], "items": []}
        for cid, pay in chunks(node):
            if cid == 0x0033 and len(pay) == 4:
                m["id"] = struct.unpack("<i", pay)[0]
            elif cid == 0x0036:
                m["folder"] = cstr(pay)
            elif cid == 0x0035:
                m["image"] = cstr(pay)
            elif cid == 0x0028:
                o = {}
                for c2, p2 in chunks(pay):
                    if c2 == 0x0029:
                        o["text_id"] = struct.unpack("<i", p2)[0]
                    elif c2 == 0x002A:
                        o["kind"] = struct.unpack("<i", p2)[0]
                    elif c2 == 0x002B:
                        o["optional"] = bool(p2[0])
                m["objectives"].append(o)
        items = []
        find(node, 0x0018, items)
        for it in items:
            if len(it) >= 12:
                a, b, c = struct.unpack_from("<iii", it, 0)
                m["items"].append({"raw": [a, b, c], "flag": it[12] if len(it) > 12 else None})
        if m.get("folder"):
            missions.append(m)
    return missions


def main():
    data = cm.read_file("gamedata/Gamedata00.gdt", ["patch.dta", "others.DTA"])
    ms = parse(data)
    out = os.path.join(cm.CACHE, "missions_db.json")
    json.dump({"source": "GAMEDATA\\Gamedata00.gdt", "missions": {m["folder"].upper(): m for m in ms}},
              open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for m in ms:
        print("%-12s Ziele %d (Zusatz %d)" % (m["folder"], len(m["objectives"]), sum(1 for o in m["objectives"] if o.get("optional"))))
    print("->", out)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main()
