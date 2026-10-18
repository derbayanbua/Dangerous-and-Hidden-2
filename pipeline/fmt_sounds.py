"""Alle Original-Audiodaten (HD2 v1.12) in den lokalen Cache konvertieren und die Klangzuordnung aus den
Originaltabellen ausgeben.

Quellen (nur gelesen, patch.dta zuerst):
  Sounds.dta (+ patch.dta SOUNDS\\)   4608 WAV + 43 OGG  -> orig_cache/sounds/<name>.wav, orig_cache/music/<name>.ogg
  TABLES\\IngameSounds.def            Klangtabelle: Kategorie (0x044C, Name 0x0456) -> Gruppe (0x04B0: Name 0x04BA,
                                      Flag 0x051E) -> Variante (0x0514: Datei 0x0578, kumulative Wahrscheinlichkeit %
                                      0x0582, Mindestabstand m 0x058C, Hoechstabstand m 0x0596, ? 0x05A0, Lautstaerke
                                      0x05AA, ? 0x05BE). Lader hd2.exe 0x439080/0x432040/0x43A6F0/0x43AA50, Abspielen
                                      0x433FA0 (Bereich -> SetRange(min, max), Lautstaerke -> SetVolume).
  TABLES\\IngSndExp.txt               Erklaerung der Kategorien/IDs (Entwicklerdatei, Namen identisch)
  TABLES\\speech.set / speech.txt     Sprachsaetze (Trupp, Gegner, Girls, Allies, Sygurd) -> Sound-IDs; deutsche Datei =
                                      90000000 + ID mod 10000 (hd2.exe 0x5B0440)
  TABLES\\items.sav (via items.json)  Waffenklaenge je Gegenstand: Schuss/Wurf (Kat. 2), Nachladen, Ziehen,
                                      Repetieren, letzter Schuss (Kat. 3/2)
  TABLES\\hdmaterials.def             Material (98 x 256 Byte) -> Einschlagklang (Kat. 4) +0x30/+0x34

Ausgabe: orig_cache/sounds.json (siehe docs/re_notes_audio.md). Daten bleiben lokal (orig_cache ist gitignored).
Aufruf: pyenv\\Scripts\\python.exe -I fmt_sounds.py [--no-extract]
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import dta_extract  # noqa: E402

try:
    import numpy as np
except ImportError:      # langsamer Weg bleibt verfuegbar
    np = None


# --- schnelle Dekodierung der Audio-Delta-Bloecke (identisch zu dta_extract.decode_wav_block) ---------------
def _fast_decode_wav_block(blk, wav):
    t = blk[0]
    tab = dta_extract._wav_tables()[(t - 8) // 4]
    i = 1
    head = b""
    if blk[1:5] == b"RIFF":
        head = blk[1:45]
        i = 45
    channels = struct.unpack_from("<H", wav, 22)[0] if wav else 1
    bits = struct.unpack_from("<H", wav, 34)[0] if wav else 16
    if bits != 16:
        return head + dta_extract.lzss(blk[i:])
    if i >= len(blk):
        return head
    k = 2 * channels
    start = np.frombuffer(blk[i:i + k], dtype="<i2").astype(np.int64)
    codes = np.frombuffer(blk[i + k:], dtype=np.uint8)
    tabv = np.asarray(tab, dtype=np.int64)
    d = tabv[codes & 0x7F]
    d = np.where(codes & 0x80, -d, d)
    out = np.empty(len(d), dtype=np.int64)
    for c in range(channels):
        seq = d[c::channels]
        out[c::channels] = start[c] + np.cumsum(seq)
    out = ((out + 32768) % 65536) - 32768
    return head + blk[i:i + k] + out.astype("<i2").tobytes()


if np is not None:
    dta_extract.decode_wav_block = _fast_decode_wav_block


# --- Chunk-Helfer -------------------------------------------------------------------------------------------
def chunks(b, off, end):
    p = off
    while p + 6 <= end:
        cid, size = struct.unpack_from("<HI", b, p)
        if size < 6 or p + size > end:
            return
        yield cid, p + 6, p + size
        p += size


def cstr(b, s, e):
    return b[s:e].split(b"\0")[0].decode("latin-1")


def f32(b, s):
    return round(struct.unpack_from("<f", b, s)[0], 4)


def parse_ingame_sounds(d):
    cats = []
    for _, s, e in chunks(d, 0, len(d)):                       # 0x03E8 Wurzel
        for t2, s2, e2 in chunks(d, s, e):                     # 0x044C Kategorie
            if t2 != 0x044C:
                continue
            cat = {"index": len(cats), "name": "", "groups": []}
            for t3, s3, e3 in chunks(d, s2, e2):
                if t3 == 0x0456:
                    cat["name"] = cstr(d, s3, e3)
                    continue
                if t3 != 0x04B0:
                    continue
                g = {"id": len(cat["groups"]), "name": "", "flag": 0, "variants": []}
                for t4, s4, e4 in chunks(d, s3, e3):
                    if t4 == 0x04BA:
                        g["name"] = cstr(d, s4, e4)
                    elif t4 == 0x051E:
                        g["flag"] = d[s4]
                    elif t4 == 0x0514:
                        # Standardwerte wie hd2.exe 0x43A6F0
                        v = {"file": "", "cum": 100, "min": 0.0, "max": 20.0, "p5a0": 0.5, "volume": 1.0, "p5be": 0.5}
                        for t5, s5, e5 in chunks(d, s4, e4):
                            if t5 == 0x0578:
                                v["file"] = cstr(d, s5, e5)
                            elif t5 == 0x0582:
                                v["cum"] = struct.unpack_from("<i", d, s5)[0]
                            elif t5 == 0x058C:
                                v["min"] = f32(d, s5)
                            elif t5 == 0x0596:
                                v["max"] = f32(d, s5)
                            elif t5 == 0x05A0:
                                v["p5a0"] = f32(d, s5)
                            elif t5 == 0x05AA:
                                v["volume"] = f32(d, s5)
                            elif t5 == 0x05BE:
                                v["p5be"] = f32(d, s5)
                        g["variants"].append(v)
                cat["groups"].append(g)
            cats.append(cat)
    return cats


def read_speech(b):
    sets = {}
    for _, o, e in chunks(b, 0, len(b)):
        for _, so, se in chunks(b, o, e):
            name, events = None, {}
            for cid, co, ce in chunks(b, so, se):
                if cid == 1:
                    name = cstr(b, co, ce)
                elif cid == 2:
                    for ev, eo, ee in chunks(b, co, ce):
                        ids = [struct.unpack_from("<I", b, vo)[0] for _, vo, ve in chunks(b, eo, ee) if ve - vo == 4]
                        if ids:
                            events[str(ev)] = ids
            if name:
                sets[name] = events
    return sets


def read_speech_labels(b):
    out = {}
    for line in b.decode("latin-1").splitlines():
        if ";" in line:
            a, t = line.split(";", 1)
            if a.strip().isdigit():
                out[a.strip()] = t.strip()
    return out


def parse_materials(d):
    mats = []
    for i in range(len(d) // 256):
        r = d[i * 256:(i + 1) * 256]
        name = r[:0x20].split(b"\0")[0].decode("cp1250").strip()
        # +0x20 Schrittklang Kat. 0 (hd2.exe 0x75D5D8 liest [Material*0x100+0x20]); +0x30/+0x34 Einschlag Kat. 4
        step = struct.unpack_from("<i", r, 0x20)[0]
        h1, h2 = struct.unpack_from("<ii", r, 0x30)
        mats.append({"index": i, "name": name, "step_sound": step, "hit_sound": h1, "hit_sound_2": h2,
                     "penetration_?": list(struct.unpack_from("<ii", r, 0x28))})
    return mats


HUMAN_TABLE_VA = 0x84E938     # hd2.exe v1.12: 20 Ereignisse x 6 Varianten x {char* Datei, f32 min, f32 max, f32 Lautst.}
# Ereignisnamen nach Dateinamen und Aufrufstellen (0x779F65 Haltung 4/5/6, 0x7596AA Bewegung 7/8/9,
# 0x77AA75.. Klettern 13/14/15, 0x770BF8 Sprung 17, 0x75ED56 Ertrinken 18) - docs/re_notes_audio.md
HUMAN_EVENTS = ["swim", "swim_underwater", "uvs", "uv", "to_prone", "to_crouch", "to_stand", "move_prone",
                "move_crouch", "move_run", "o_wout", "o_win", "grenade_take", "climb_over", "climb_over2",
                "climb_over3", "e16", "jump_over", "drown", "e19"]


def read_human_table():
    import pefile
    pe = pefile.PE(os.path.join(cm.ORIG, "hd2.exe"), fast_load=True)
    base = pe.OPTIONAL_HEADER.ImageBase
    raw = pe.get_data(HUMAN_TABLE_VA - base, 20 * 6 * 16)
    out = {}
    for ev in range(20):
        lst = []
        for s in range(6):
            ptr, mn, mx, vol = struct.unpack_from("<Ifff", raw, (ev * 6 + s) * 16)
            if ptr:
                name = pe.get_data(ptr - base, 32).split(b"\0")[0].decode("latin-1").lower()
                lst.append({"file": name, "min": round(mn, 3), "max": round(mx, 3), "volume": round(vol, 3)})
        out[HUMAN_EVENTS[ev]] = lst
    if not out["to_prone"] or out["to_prone"][0]["file"] != "o_lay.wav":
        raise SystemExit("hd2.exe-Version passt nicht (Tabelle 0x84E938)")
    return out


def weapon_sounds(items):
    """items.json (fmt_actors_items.py) -> Klaenge je Gegenstand. Felder belegt durch die Namen in IngameSounds
    (z. B. P08: Schuss Kat.2/13 'G Parabellum P08', Nachladen Kat.3/5, Ziehen Kat.3/41, letzter Schuss Kat.2/27)."""
    out = {}
    for it in items:
        ws = {}
        if it.get("u78", 0) > 0 or it.get("kind") == "weapon":
            if it.get("u78", -1) >= 0:
                ws["armed"] = [3, it["u78"]]
        for b in it.get("behaviours", []):
            if b.get("type") == "firearm":
                ws["shoot"] = [2, b["u4"]]
                ws["reload"] = [3, b["u10"]]
                if b.get("u17", -1) >= 0:
                    ws["last_shot"] = [2, b["u17"]]
                if b.get("u18", -1) >= 0:
                    ws["bolt"] = [3, b["u18"]]
            elif b.get("type") == "projectile_launcher":
                ws["shoot"] = [2, b["u4"]]
                if b.get("u11", 0) > 0:
                    ws["reload"] = [3, b["u11"]]
            elif b.get("type") == "melee":
                raw = b.get("raw_u32", [])
                if len(raw) > 4 and raw[4] > 0:
                    ws["shoot"] = [2, raw[4]]
        if ws and ("shoot" in ws or ws.get("armed", [0, 0])[1] > 0):
            ws["name"] = it.get("name", "")
            out[str(it["id"])] = ws
    return out


def extract_all(index_names):
    """Alle Dateien aus Sounds.dta (patch.dta-SOUNDS zuerst) in den Cache schreiben."""
    sdir = os.path.join(cm.CACHE, "sounds")
    mdir = os.path.join(cm.CACHE, "music")
    os.makedirs(sdir, exist_ok=True)
    os.makedirs(mdir, exist_ok=True)
    counts = {"wav": 0, "ogg": 0, "neu": 0, "fehler": 0}
    errors = []
    seen = set()
    for arc_name in ["patch.dta", "Sounds.dta"]:
        arc = cm.archive(arc_name)
        for e in arc.entries:
            n = e[0].lower()
            if not n.startswith("sounds\\"):
                continue
            base = n.split("\\")[-1]
            if base in seen:
                continue
            seen.add(base)
            ext = os.path.splitext(base)[1]
            dst = os.path.join(mdir if ext == ".ogg" else sdir, base)
            counts["ogg" if ext == ".ogg" else "wav"] += 1
            if os.path.exists(dst) and os.path.getsize(dst) == e[1]:
                continue
            try:
                data = arc.read(e)
            except Exception as ex:  # noqa: BLE001
                counts["fehler"] += 1
                errors.append("%s: %s" % (e[0], ex))
                continue
            with open(dst, "wb") as f:
                f.write(data)
            counts["neu"] += 1
    return counts, errors


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    extract = "--no-extract" not in sys.argv
    isd = cm.read_file("tables/IngameSounds.def", ["others.DTA"])
    cats = parse_ingame_sounds(isd)
    speech = read_speech(cm.read_file("tables/speech.set", ["others.DTA"]))
    labels = read_speech_labels(cm.read_file("tables/speech.txt", ["others.DTA"]))
    mats = parse_materials(cm.read_file("tables/hdmaterials.def", ["others.DTA"]))
    items_p = os.path.join(cm.CACHE, "items.json")
    items = json.load(open(items_p, encoding="utf-8"))["items"] if os.path.exists(items_p) else []
    counts, errors = ({}, [])
    if extract:
        counts, errors = extract_all(None)
    # Pruefung: alle Tabellendateien vorhanden?
    sdir = os.path.join(cm.CACHE, "sounds")
    mdir = os.path.join(cm.CACHE, "music")
    have = set(os.listdir(sdir)) | set(os.listdir(mdir)) if os.path.isdir(sdir) else set()
    missing = []
    for c in cats:
        for g in c["groups"]:
            for v in g["variants"]:
                f = v["file"].lower()
                if f and "." not in f:
                    f += ".wav"
                v["file"] = f
                if f and f not in have:
                    missing.append("%d/%d %s" % (c["index"], g["id"], f))
    out = {
        "source": "IngameSounds.def (patch.dta), speech.set/speech.txt, hdmaterials.def, items.sav (items.json); "
                  "Semantik docs/re_notes_audio.md",
        "categories": cats,
        "speech_sets": speech,
        "speech_labels": labels,
        "materials": mats,
        "weapons": weapon_sounds(items),
        "human": read_human_table(),
        "missing_files": missing,
    }
    with open(os.path.join(cm.CACHE, "sounds.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("Kategorien: %d, Gruppen: %d, Varianten: %d; Sprachsaetze: %d; Materialien: %d; Waffen: %d" % (
        len(cats), sum(len(c["groups"]) for c in cats), sum(len(g["variants"]) for c in cats for g in c["groups"]),
        len(speech), len(mats), len(out["weapons"])))
    print("Dateien: %s; Fehler: %s; fehlend in Tabelle: %d %s" % (counts, errors[:5], len(missing), missing[:12]))


if __name__ == "__main__":
    main()
