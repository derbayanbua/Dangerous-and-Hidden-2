"""Chunk-Baum von LS3D-Binärdateien (scene2.bin, actors.bin, sounds.bin) ausgeben.
Chunk = u16 Typ + u32 Gesamtlänge (inkl. 6-Byte-Kopf). Typen mit gesetztem
Bit 0x4000 enthalten (vermutlich) Unter-Chunks.
Aufruf: chunks.py <datei> [max_tiefe] [max_kinder]
"""
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def walk(d, start, end, depth, maxdepth, maxkids, out):
    p = start
    kids = 0
    while p + 6 <= end:
        t, ln = struct.unpack_from("<HI", d, p)
        if ln < 6 or p + ln > end:
            out.append("  " * depth + "?? ungültig @%x typ %04x len %d" % (p, t, ln))
            return
        payload = d[p + 6:p + ln]
        txt = ""
        if len(payload) and payload[-1:] == b"\0" and all(32 <= b < 127 for b in payload[:-1]) and len(payload) > 1:
            txt = '"%s"' % payload[:-1].decode()
        elif len(payload) in (4, 8, 12, 16):
            fl = struct.unpack("<%df" % (len(payload) // 4), payload)
            txt = "f" + str([round(x, 3) for x in fl]) + " u" + str(list(struct.unpack("<%dI" % (len(payload) // 4), payload)))
        elif len(payload) <= 24:
            txt = payload.hex(" ")
        kids += 1
        if kids <= maxkids:
            out.append("  " * depth + "%04x len %-8d @%x %s" % (t, ln, p, txt))
        if (t & 0x4000 or t in (0x4c53,)) and depth < maxdepth and ln > 6:
            walk(d, p + 6, p + ln, depth + 1, maxdepth, maxkids, out)
        p += ln
    if kids > maxkids:
        out.append("  " * depth + "... (%d Chunks insgesamt)" % kids)


d = open(sys.argv[1], "rb").read()
maxd = int(sys.argv[2]) if len(sys.argv) > 2 else 3
maxk = int(sys.argv[3]) if len(sys.argv) > 3 else 12
out = []
walk(d, 0, len(d), 0, maxd, maxk, out)
print("\n".join(out))
