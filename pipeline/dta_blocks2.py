"""Wie viele Eingabebytes verbraucht der LZ-Dekoder für 32 KB Ausgabe? (Analyse)"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dta_extract as x  # noqa: E402


def lz_consumed(src: bytes, limit: int):
    out = bytearray()
    i = 0
    n = len(src)
    while i < n and len(out) < limit:
        flags = (src[i] << 8) | src[i + 1]
        i += 2
        for _ in range(16):
            if i >= n or len(out) >= limit:
                break
            if flags & 0x8000 == 0:
                out.append(src[i]); i += 1
            else:
                off = (src[i] << 4) | (src[i + 1] >> 4)
                if off:
                    cnt = (src[i + 1] & 0x0F) + 3; i += 2
                    st = len(out) - off
                    for k in range(cnt):
                        out.append(out[st + k])
                else:
                    cnt = ((src[i + 1] << 8) | src[i + 2]) + 16
                    out += bytes([src[i + 3]]) * cnt; i += 4
            flags = (flags << 1) & 0xFFFF
    return i, len(out)


arc = x.Archive(sys.argv[1])
e = [e for e in arc.entries if e[0].lower() == sys.argv[2].lower()][0]
name, size, blocks, doff = e
arc.f.seek(doff)
L1 = struct.unpack("<I", arc.f.read(4))[0]
blk = arc._read_dec(L1)
used, produced = lz_consumed(blk[1:], 32768)
print("L1", L1, "verbraucht", used + 1, "produziert", produced)
arc.f.seek(doff + 4 + L1 - 8)
tail = arc.f.read(24)
print("roh ab L1-8:", tail.hex(" "))
for shift in range(-6, 7):
    arc.f.seek(doff + 4 + L1 + shift)
    v = struct.unpack("<I", arc.f.read(4))[0]
    print(shift, hex(v), v)
