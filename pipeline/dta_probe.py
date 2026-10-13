"""Prüft die aus hd2.exe (FUN_006db6e0) rekonstruierten DTA-Schlüssel.

Nur Analyse: liest Originalarchive read-only, schreibt nichts in HD2_orig.
Aufruf: python -I tools/dta_probe.py <archiv.dta>
"""
import os
import struct
import sys

# Archivname -> (key1, key2); Reihenfolge/Belegung aus dem dtaCreate-Block
KEYS = {
    "patch.dta": (0x5D805270, 0x10ACB252),
    "models.dta": (0x5D805259, 0x10ACB252),
    "missions.dta": (0x7654A3F0, 0x22BCDA98),
    "maps.dta": (0xB438D0A5, 0xF26527FA),
    "sounds.dta": (0x4FE85106, 0x8D2965CA),
    "scripts.dta": (0x0AB4E72D, 0xCF761298),
    "others.dta": (0xEA85902A, 0x65F7AB23),
    "maps_c.dta": (0xB038D0A0, 0xE26520FA),
    "maps_u.dta": (0xB038D1A1, 0xF26520FA),
}


def xor_block(data: bytes, k1: int, k2: int) -> bytes:
    out = bytearray(data)
    n = len(out) // 8 * 8
    for i in range(0, n, 8):
        a, b = struct.unpack_from("<II", out, i)
        struct.pack_into("<II", out, i, a ^ k1, b ^ k2)
    return bytes(out)


def main(path: str) -> None:
    name = os.path.basename(path).lower()
    k1, k2 = KEYS[name]
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        magic = f.read(4)
        hdr = xor_block(f.read(16), k1, k2)
    count, table_off, table_size, check = struct.unpack("<IIII", hdr)
    print(f"{name}: magic={magic!r} size={size}")
    print(f"  files={count} table_off={table_off} table_size={table_size} check=0x{check:08x}")
    print(f"  table_off + table_size == size: {table_off + table_size == size}")


if __name__ == "__main__":
    main(sys.argv[1])
