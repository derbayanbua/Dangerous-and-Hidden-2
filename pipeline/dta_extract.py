"""Read-only Analysewerkzeug für LS3D-ISD0/ISD1-Archive (Hidden & Dangerous 2).

Format (rekonstruiert, siehe DangerousHidden2/docs/RE_FINDINGS.md):
  0x00  "ISD0"/"ISD1"
  0x04  16 Byte Header, XOR-verschlüsselt (u32 abwechselnd key1/key2):
        file_count, table_offset, table_size, check
  table: file_count * 28 Byte (verschlüsselt):
        u16 id, u16 name_len, u32 header_off, u32 data_off, char[16] name_tail
  header: u32, u32, u64 FILETIME, u32 size, u32 block_count, u32, u32, name
  data:  block_count * { u32 block_len (Klartext) ; block_len Byte verschlüsselt:
         u8 type ; Nutzdaten }
  ISD1 (patch.dta): anderer Dateikopf mit Block-/Typtabelle, Blöcke ohne Kopf,
         siehe Archive._read_isd1_header und docs/re_notes_isd1.md

Extrahierte Dateien dienen nur der technischen Analyse und werden NICHT in das
neue Spiel übernommen.

Aufruf:
  python -I tools/dta_extract.py list <archiv> [filter]
  python -I tools/dta_extract.py extract <archiv> <filter> <zielordner>
"""
import fnmatch
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dta_probe import KEYS, xor_block  # noqa: E402


class Archive:
    def __init__(self, path: str):
        self.path = path
        self.k1, self.k2 = KEYS[os.path.basename(path).lower()]
        self.f = open(path, "rb")
        self.magic = self.f.read(4)
        self.isd1 = self.magic == b"ISD1"
        self.isd1_blocks = {}   # ISD1: data_off -> (Längen, Prüfsummen, Typen, verschlüsselt)
        cnt, toff, tsize, _ = struct.unpack("<IIII", self._read_dec(16))
        self.f.seek(toff)
        table = self._read_dec(tsize)
        self.entries = []
        for i in range(cnt):
            _id, nlen, hoff, doff = struct.unpack_from("<HHII", table, i * 28)
            self.f.seek(hoff)
            if self.isd1:
                self.entries.append(self._read_isd1_header(nlen, doff))
                continue
            h = self._read_dec(doff - hoff)
            size, blocks = struct.unpack_from("<II", h, 16)
            name = h[32:32 + nlen].decode("latin-1")
            self.entries.append((name, size, blocks, doff))

    def _read_isd1_header(self, nlen: int, doff: int):
        """ISD1-Dateikopf (rw_data.dll FUN_1000c110, Zweig Version 1; siehe
        DangerousHidden2/docs/re_notes_isd1.md):
          32 B XOR: u32, u32, u64 FILETIME, u32 size, u32 blocks, u32 hdr_cks,
                    u16 name_len (Bit 15 = Daten verschlüsselt), u16 table_cks
          name_len B XOR: Name
          blocks × u32 KLARTEXT: low16 = Blocklänge, high16 = Blockprüfsumme
          blocks × u8 XOR: Blocktyp (0 roh, 1 LZ, 8..0x20 Audio)
        Danach (= data_off) folgen die Blöcke direkt hintereinander, ohne Blockkopf
        und ohne Typbyte."""
        h = self._read_dec(32)
        size, blocks, _hcks, nflags, _tcks = struct.unpack_from("<IIIHH", h, 16)
        name = self._read_dec(nflags & 0x7FFF)[:nlen].decode("latin-1")
        traw = self.f.read(4 * blocks)
        words = struct.unpack("<%dI" % blocks, traw)
        types = self._read_dec(blocks)
        self.isd1_blocks[doff] = ([w & 0xFFFF for w in words], [w >> 16 for w in words],
                                  types, bool(nflags & 0x8000))
        return (name, size, blocks, doff)

    def _read_dec(self, n: int) -> bytes:
        raw = self.f.read(n)
        pad = (-len(raw)) % 8
        return xor_block(raw + b"\0" * pad, self.k1, self.k2)[:len(raw)]

    def read(self, entry) -> bytes:
        name, size, blocks, doff = entry
        if self.isd1:
            return self._read_isd1(entry)
        self.f.seek(doff)
        out = bytearray()
        wav = None   # WAV-Kopf der Datei (Kanäle/Bits für Audioblöcke)
        for b in range(blocks):
            # Blockheader: u16 Länge dieses Blocks, u16 Länge des vorigen Blocks
            hdr = struct.unpack("<I", self.f.read(4))[0]
            blen = hdr & 0xFFFF
            blk = self._read_dec(blen)
            if b == 0 and blk[1:5] == b"RIFF":
                wav = blk[1:45]
            out += decode_block(blk, wav)
        return bytes(out[:size])

    def _read_isd1(self, entry) -> bytes:
        """ISD1-Daten (rw_data.dll dtaRead @0x1000513b, Zweig 'u16-Tabelle'):
        Block k liegt bei data_off + Summe(Längen[0..k-1]); Prüfsumme über die
        Rohbytes; XOR nur bei gesetztem Verschlüsselungsbit; das Typbyte stammt aus
        der Typtabelle und wird vor die Nutzdaten gesetzt (wie bei ISD0)."""
        name, size, blocks, doff = entry
        lens, sums, types, enc = self.isd1_blocks[doff]
        self.f.seek(doff)
        out = bytearray()
        wav = None
        for b in range(blocks):
            raw = self.f.read(lens[b])
            if len(raw) != lens[b]:
                raise ValueError(f"Block {b}: Dateiende")
            if isd1_checksum(raw) != sums[b]:
                raise ValueError(f"Block {b}: Prüfsumme falsch")
            if enc:
                data = xor_block(raw + b"\0" * ((-len(raw)) % 8), self.k1, self.k2)[:len(raw)]
            elif b == 0 and types[0] >= 8:
                # unverschlüsselte Audiodatei: nur der 44-Byte-WAV-Kopf ist XOR-verschlüsselt
                data = xor_block(raw[:48], self.k1, self.k2)[:44] + raw[44:]
            else:
                data = raw
            blk = bytes([types[b]]) + data
            if b == 0 and blk[1:5] == b"RIFF":
                wav = blk[1:45]
            out += decode_block(blk, wav)
        return bytes(out[:size])


def isd1_checksum(data: bytes, seed: int = 0xFF) -> int:
    """16-Bit-Prüfsumme (rw_data.dll FUN_10009e97): c = (c + b) ^ (~b & 0xFF)."""
    c = seed
    for b in data:
        c = ((c + b) ^ (~b & 0xFF)) & 0xFFFF
    return c


class PartialRead(Exception):
    def __init__(self, data: bytes):
        super().__init__(f"nur {len(data)} Byte (erster Block) lesbar")
        self.data = data


_WAV_TABLES = None


def _wav_tables():
    global _WAV_TABLES
    if _WAV_TABLES is None:
        import json
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wav_tables.json")
        _WAV_TABLES = {int(k): v for k, v in json.load(open(p)).items()}
    return _WAV_TABLES


def decode_wav_block(blk: bytes, wav: bytes) -> bytes:
    """Audio-Delta-Kompression (rekonstruiert aus rw_data.dll, FUN_100097f7):
    Typ 0x0C/0x10/0x14/0x18/0x1C/0x20 wählt Tabelle 1..6 (128 × int16 @0x10036D70).
    Optional 44-Byte-WAV-Kopf am Blockanfang (unverändert). 16 Bit: Startsample(s) roh,
    danach je Byte: Vorzeichenbit + Tabellenindex, Wert auf das vorige Sample addiert."""
    t = blk[0]
    tab = _wav_tables()[(t - 8) // 4]
    out = bytearray()
    i = 1
    if blk[1:5] == b"RIFF":
        out += blk[1:45]
        i = 45
    channels = struct.unpack_from("<H", wav, 22)[0] if wav else 1
    bits = struct.unpack_from("<H", wav, 34)[0] if wav else 16
    if bits != 16:
        return bytes(out) + lzss(blk[i:])
    if i >= len(blk):
        return bytes(out)
    k = 2 * channels
    out += blk[i:i + k]
    prev = list(struct.unpack_from("<%dh" % channels, blk, i))
    i += k
    ch = 0
    n = len(blk)
    while i < n:
        b = blk[i]
        dv = tab[b & 0x7F]
        prev[ch] = (prev[ch] + (-dv if b & 0x80 else dv) + 32768) % 65536 - 32768   # 16-Bit-Überlauf wie im Original
        out += struct.pack("<h", prev[ch])
        ch = (ch + 1) % channels
        i += 1
    return bytes(out)


def decode_block(blk: bytes, wav: bytes = None) -> bytes:
    t = blk[0]
    if t == 0:
        return blk[1:]
    if t == 1:
        return lzss(blk[1:])
    if t in (0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20):   # 0x08 -> Standardtabelle 0
        return decode_wav_block(blk, wav)
    raise ValueError(f"Blocktyp {t} nicht unterstützt")


def lzss(src: bytes) -> bytes:
    """LZ77-Variante: u16-Flagwort (Big-Endian, MSB zuerst); 0 = Literal,
    1 = Rückverweis (12 Bit Offset, 4 Bit Länge+3) bzw. Offset 0 = Lauflänge."""
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        if i + 2 > n:
            break
        flags = (src[i] << 8) | src[i + 1]   # Big-Endian, MSB zuerst
        i += 2
        for _ in range(16):
            if i >= n:
                break
            if flags & 0x8000 == 0:
                out.append(src[i])
                i += 1
            else:
                off = (src[i] << 4) | (src[i + 1] >> 4)
                if off:
                    cnt = (src[i + 1] & 0x0F) + 3
                    i += 2
                    start = len(out) - off
                    for k in range(cnt):
                        out.append(out[start + k])
                else:
                    cnt = ((src[i + 1] << 8) | src[i + 2]) + 16
                    b = src[i + 3]
                    out += bytes([b]) * cnt
                    i += 4
            flags = (flags << 1) & 0xFFFF
    return bytes(out)


def main() -> None:
    cmd, path = sys.argv[1], sys.argv[2]
    pat = sys.argv[3] if len(sys.argv) > 3 else "*"
    a = Archive(path)
    sel = [e for e in a.entries if fnmatch.fnmatch(e[0].lower(), pat.lower())]
    if cmd == "list":
        for name, size, blocks, _ in sel:
            print(f"{size:10d} {blocks:4d}  {name}")
        print(f"# {len(sel)} / {len(a.entries)} Einträge")
    elif cmd == "extract":
        dest = sys.argv[4]
        ok = bad = 0
        for e in sel:
            suffix = ""
            try:
                data = a.read(e)
            except PartialRead as pr:
                data, suffix = pr.data, ".partial"
                print(f"TEILWEISE {e[0]}: {pr}")
            except Exception as ex:  # noqa: BLE001
                print(f"FEHLER {e[0]}: {ex}")
                bad += 1
                continue
            p = os.path.join(dest, e[0].replace("\\", os.sep)) + suffix
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as o:
                o.write(data)
            ok += 1
        print(f"# extrahiert: {ok}, Fehler: {bad}")


if __name__ == "__main__":
    main()
