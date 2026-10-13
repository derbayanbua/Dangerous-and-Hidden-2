"""Parser für scene2.bin (LS3D/HD2): Objekte mit Typ, Transform, Modell, Eltern.
Chunk = u16 Typ + u32 Länge (inkl. Kopf).
"""
import collections
import struct
import sys


def chunks(d, start, end):
    p = start
    while p + 6 <= end:
        t, ln = struct.unpack_from("<HI", d, p)
        if ln < 6 or p + ln > end:
            return
        yield t, p + 6, p + ln
        p += ln


def cstr(d, a, b):
    return d[a:b].split(b"\0")[0].decode("latin-1")


def parse_object(d, a, b):
    o = {"chunks": {}}
    for t, s, e in chunks(d, a, b):
        if t == 0x4011:
            o["type"] = struct.unpack_from("<I", d, s)[0]
        elif t == 0x0010:
            o["name"] = cstr(d, s, e)
        elif t == 0x0020:
            o["pos"] = struct.unpack_from("<3f", d, s)
        elif t == 0x0022:
            o["rot"] = struct.unpack_from("<4f", d, s)       # w, x, y, z
        elif t == 0x002D:
            o["scale"] = struct.unpack_from("<3f", d, s)
        elif t == 0x002C:
            o["world_pos"] = struct.unpack_from("<3f", d, s)
        elif t == 0x2012:
            o["model"] = cstr(d, s, e)
        elif t == 0x4020:
            for t2, s2, e2 in chunks(d, s, e):
                if t2 == 0x0010:
                    o["parent"] = cstr(d, s2, e2)
        else:
            o["chunks"][t] = (s, e)
    return o


def parse_actor_defs(d):
    """actors.bin, Chunk 0xAE20: Akteursdefinitionen {Name: (Typ, Parameterbytes)}.
    Typen (beobachtet): 3 Mensch (NPC/Gegner), 4 Fahrzeug, 10 Spielerkommando."""
    defs = {}
    for t, s, e in chunks(d, 0, len(d)):
        if t != 0x4C53:
            continue
        for t2, s2, e2 in chunks(d, s, e):
            if t2 != 0xAE20:
                continue
            for t3, s3, e3 in chunks(d, s2, e2):
                if t3 != 0xAE21:
                    continue
                name, typ, params = "", -1, b""
                for t4, s4, e4 in chunks(d, s3, e3):
                    if t4 == 0xAE23:
                        name = cstr(d, s4, e4)
                    elif t4 == 0xAE22:
                        typ = struct.unpack_from("<I", d, s4)[0]
                    elif t4 == 0xAE24:
                        params = d[s4:e4]
                defs[name] = (typ, params)
    return defs


def parse(d):
    objs = []
    header = {}
    for t, s, e in chunks(d, 0, len(d)):
        if t != 0x4C53:
            continue
        for t2, s2, e2 in chunks(d, s, e):
            if t2 == 0x4000:
                for t3, s3, e3 in chunks(d, s2, e2):
                    if t3 == 0x4010:
                        objs.append(parse_object(d, s3, e3))
            else:
                header[t2] = (s2, e2)
    return header, objs


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    d = open(sys.argv[1], "rb").read()
    header, objs = parse(d)
    print("Objekte:", len(objs))
    types = collections.Counter(o.get("type", -1) for o in objs)
    print("Typen:", dict(types))
    extra = collections.Counter()
    for o in objs:
        for k in o["chunks"]:
            extra["%04x/t%s" % (k, o.get("type", -1))] += 1
    print("Weitere Chunks:", dict(extra))
    models = collections.Counter(o.get("model") for o in objs if o.get("model"))
    print("Modelle (verschiedene):", len(models), "häufigste:", models.most_common(10))
    for ty in sorted(types):
        ex = [o.get("name") for o in objs if o.get("type", -1) == ty][:6]
        print("  Typ", ty, ex)
