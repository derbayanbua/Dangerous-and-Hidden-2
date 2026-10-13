"""Parser für LS3D-5DS-Animationen aus Hidden & Dangerous 2 (Version 0x7A).

Rekonstruiert aus den Originaldaten (alle 2016 5DS aus MODELS.DTA/patch.dta parsen
byte-genau, d. h. jedes Objektende trifft exakt den nächsten Objekt-Offset bzw. den
Namensblock). Details: DangerousHidden2/docs/re_notes_5ds_skin.md.

  0x00 "5DS\\0"
  0x04 u16 version (0x7A)
  0x06 u64 FILETIME
  0x0E u32 data_size              (= Dateigröße - 0x12)
  --- Basis B = 0x12; alle Offsets und Ausrichtungen relativ zu B ---
  u16 object_count ; u16 last_frame
  object_count * { u32 name_off ; u32 data_off }
  Objektdaten:
    u32 flags  (4 = Rotation, 2 = Position, 8 = Skalierung, 0x20 = Ereignisse)
    Reihenfolge der Blöcke: Rotation, Position, Skalierung, Ereignisse
    Block = u16 n ; u16 frame[n] ; Pad ; Werte
      Rotation:   Pad auf 16 ; n * quat (x, y, z, w)       (wie 4DS-Frame-Rotation)
      Position:   Pad auf 4  ; n * vec3
      Skalierung: Pad auf 4  ; n * vec3
      Ereignisse: Pad auf 4  ; n * u32 str_off ; Stringblock (nullterminiert,
                  Offsets relativ zum Blockanfang), Ende auf 4 ausgerichtet
  Namensblock: nullterminierte Strings (= Frame-Namen im 4DS, z. B. "a", "b", "c1", "hw1")

Werte sind LOKALE Transformationen im LS3D-Koordinatensystem (linkshändig) und
ersetzen die Ruhelage des gleichnamigen 4DS-Frames (gleiche Konvention wie
Frame-Kopf pos/rot/scale). Kanäle ohne Spur behalten die Ruhelage.
Zeitbasis: Frame-Nummern; Abspielrate im Original 25 fps (Annahme, siehe Notizen).
"""
import struct

FLAG_POS = 2
FLAG_ROT = 4
FLAG_SCALE = 8
FLAG_EVENTS = 0x20
BASE = 0x12


def _frames(d, p):
    n = struct.unpack_from("<H", d, p)[0]
    frames = list(struct.unpack_from("<%dH" % n, d, p + 2))
    return n, frames, p + 2 + 2 * n


def _align(p, a):
    return p + (-(p - BASE)) % a


def parse(d: bytes) -> dict:
    assert d[:4] == b"5DS\0", "kein 5DS"
    ver = struct.unpack_from("<H", d, 4)[0]
    size = struct.unpack_from("<I", d, 0x0E)[0]
    nobj, last_frame = struct.unpack_from("<HH", d, BASE)
    objs = []
    for i in range(nobj):
        noff, doff = struct.unpack_from("<II", d, BASE + 4 + i * 8)
        e = d.index(b"\0", BASE + noff)
        o = {"name": d[BASE + noff:e].decode("latin-1")}
        p = BASE + doff
        flags = struct.unpack_from("<I", d, p)[0]
        o["flags"] = flags
        p += 4
        if flags & FLAG_ROT:
            n, o["rot_frames"], p = _frames(d, p)
            p = _align(p, 16)
            o["rot"] = [list(struct.unpack_from("<4f", d, p + 16 * k)) for k in range(n)]
            p += 16 * n
        if flags & FLAG_POS:
            n, o["pos_frames"], p = _frames(d, p)
            p = _align(p, 4)
            o["pos"] = [list(struct.unpack_from("<3f", d, p + 12 * k)) for k in range(n)]
            p += 12 * n
        if flags & FLAG_SCALE:
            n, o["scale_frames"], p = _frames(d, p)
            p = _align(p, 4)
            o["scale"] = [list(struct.unpack_from("<3f", d, p + 12 * k)) for k in range(n)]
            p += 12 * n
        if flags & FLAG_EVENTS:
            n, o["event_frames"], p = _frames(d, p)
            p = _align(p, 4)
            offs = struct.unpack_from("<%dI" % n, d, p)
            p += 4 * n
            ev = []
            end = p
            for off in offs:
                z = d.index(b"\0", p + off)
                ev.append(d[p + off:z].decode("latin-1"))
                end = max(end, z + 1)
            o["events"] = ev
            p = _align(end, 4)
        rest = flags & ~(FLAG_ROT | FLAG_POS | FLAG_SCALE | FLAG_EVENTS)
        if rest:
            o["unknown_flags"] = rest
        o["end"] = p
        objs.append(o)
    return {"version": ver, "data_size": size, "last_frame": last_frame, "objects": objs}


if __name__ == "__main__":
    import sys
    for fn in sys.argv[1:]:
        a = parse(open(fn, "rb").read())
        print(fn, "ver %#x last_frame %d objects %d" % (a["version"], a["last_frame"], len(a["objects"])))
        for o in a["objects"]:
            print("  %-10s flags %#x rot %d pos %d scale %d events %s" % (
                o["name"], o["flags"], len(o.get("rot", [])), len(o.get("pos", [])), len(o.get("scale", [])),
                list(zip(o.get("event_frames", []), o.get("events", [])))))
