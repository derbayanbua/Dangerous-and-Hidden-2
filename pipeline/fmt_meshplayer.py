"""MISSIONS\\<m>\\meshplayer.bin -> orig_cache/<m>/meshplayer.json (Filmtexturen auf Level-Frames).
Format (belegt an ARCTIC1): Chunks u16 ID + u32 Größe inkl. 6-Byte-Kopf; 0x03E8 Behälter, darin Paare
0x044C = Filmname (C-String, GameMovie\\<name>, z. B. "Arctic1.bik"), 0x04B0 = Frame-Name (z. B. "QuadPatch01").
hd2.exe lädt den Film als Videotextur (GameMovie\\%s, 0x4847E4) und legt ihn auf die Meshes des Frames.
Aufruf: pyenv\\Scripts\\python.exe -I fmt_meshplayer.py [MISSION ...]   (ohne Angabe: alle Missionen im Cache)
"""
import json, os, struct, sys
sys.path.insert(0, r"D:\Workspace_D\tools")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import convert_mission as cm


def parse(d):
    out, cur = [], {}

    def walk(off, end):
        nonlocal cur
        while off + 6 <= end:
            cid, size = struct.unpack_from("<HI", d, off)
            if size < 6 or off + size > end:
                break
            body = d[off + 6:off + size]
            if cid == 0x03E8:
                walk(off + 6, off + size)
            elif cid == 0x044C:
                cur = {"movie": body.split(b"\0")[0].decode("latin-1")}
            elif cid == 0x04B0:
                cur["frame"] = body.split(b"\0")[0].decode("latin-1")
                if cur.get("movie"):
                    out.append(cur)
                cur = {}
            off += size
    walk(0, len(d))
    return out


def main():
    arc = cm.archive("Missions.dta")
    names = [a.upper() for a in sys.argv[1:]]
    if not names:
        names = sorted({e[0].split("\\")[1].upper() for e in arc.entries if e[0].lower().endswith("meshplayer.bin")})
    for m in names:
        d = cm.read_file("MISSIONS\\%s\\meshplayer.bin" % m, ["Missions.dta"])
        dst = os.path.join(cm.CACHE, m.lower())
        if d is None or not os.path.isdir(dst):
            continue
        ent = parse(d)
        json.dump({"source": "MISSIONS\\%s\\meshplayer.bin" % m, "entries": ent},
                  open(os.path.join(dst, "meshplayer.json"), "w", encoding="utf-8"), indent=1)
        if ent:
            print(m, ent)


if __name__ == "__main__":
    main()
