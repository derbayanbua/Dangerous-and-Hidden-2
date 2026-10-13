"""Diagnose der Blockstruktur mehrblöckiger Dateien in DTA-Archiven (nur Analyse)."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dta_extract as x  # noqa: E402

arc = x.Archive(sys.argv[1])
pat = sys.argv[2].lower()
e = [e for e in arc.entries if e[0].lower() == pat][0]
name, size, blocks, doff = e
print(name, "size", size, "blocks", blocks, "data_off", doff)
# Dateiheader roh
for i, en in enumerate(arc.entries):
    if en is e:
        break
arc.f.seek(4)
cnt, toff, tsize, _ = struct.unpack("<IIII", arc._read_dec(16))
arc.f.seek(toff)
table = arc._read_dec(tsize)
idx = arc.entries.index(e)
_id, nlen, hoff, doff2 = struct.unpack_from("<HHII", table, idx * 28)
arc.f.seek(hoff)
h = arc._read_dec(doff - hoff)
print("header u32:", [hex(v) for v in struct.unpack_from("<IIIIIIII", h, 0)])
arc.f.seek(doff)
raw = arc.f.read(64)
print("raw@data:", raw[:32].hex(" "))
dec_from_data = xor = x.xor_block(raw + b"\0" * 0, arc.k1, arc.k2)
print("xor@data:", dec_from_data[:32].hex(" "))
L1 = struct.unpack("<I", raw[:4])[0]
arc.f.seek(doff + 4 + L1 - 16)
around = arc.f.read(40)
print("um Blockende:", around.hex(" "))
