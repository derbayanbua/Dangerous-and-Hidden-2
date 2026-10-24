"""Liest die Delta-Tabellen der Original-Audiokompression aus rw_data.dll.
Adresse 0x10036D70 aus der Dekompilierung von FUN_100097f7 (REA/Ghidra):
Tabelle n (1..6) = 128 × int16 bei 0x10036D70 + n*0x100.
Ausgabe: tools/wav_tables.json
"""
import json
import os
import struct
import sys

dll = os.path.join(os.environ.get("DH2_ORIG") or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "HD2_orig"), "rw_data.dll")
d = open(dll, "rb").read()
pe = struct.unpack_from("<I", d, 0x3C)[0]
nsec = struct.unpack_from("<H", d, pe + 6)[0]
opt = struct.unpack_from("<H", d, pe + 20)[0]
base = struct.unpack_from("<I", d, pe + 24 + 28)[0]
sec = pe + 24 + opt
va = 0x10036D70


def to_off(addr):
    rva = addr - base
    for i in range(nsec):
        name, vsize, vaddr, rsize, roff = struct.unpack_from("<8sIIII", d, sec + i * 40)
        if vaddr <= rva < vaddr + max(vsize, rsize):
            return roff + (rva - vaddr), name.rstrip(b"\0").decode()
    raise ValueError("Adresse nicht in Sektion")


tables = {}
for n in range(0, 7):
    off, sname = to_off(va + n * 0x100)
    tables[n] = list(struct.unpack_from("<128h", d, off))
print("Image-Basis 0x%X, Tabelle 1 in %s @0x%X" % (base, sname, to_off(va + 0x100)[0]))
for n in range(7):
    print(n, tables[n][:12], "...", tables[n][-3:])
json.dump(tables, open(os.environ.get("DH2_WAV_TABLES") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "wav_tables.json"), "w"))
