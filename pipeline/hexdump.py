"""Hexdump mit float/ASCII-Spalten zur Formatanalyse.  hexdump.py <datei> <offset> <länge>"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
off = int(sys.argv[2], 0)
n = int(sys.argv[3], 0)
for p in range(off, min(off + n, len(d)), 16):
    row = d[p:p + 16]
    hx = " ".join("%02x" % b for b in row)
    asc = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
    fl = []
    for k in range(0, len(row) - 3, 4):
        v = struct.unpack_from("<f", row, k)[0]
        fl.append("%9.4g" % v if abs(v) < 1e6 and (abs(v) > 1e-5 or v == 0) else "    .    ")
    print("%08x  %-48s  %-16s  %s" % (p, hx, asc, " ".join(fl)))
