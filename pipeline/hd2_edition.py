"""B-024/O-004: Spielausgabe am Dateiinhalt erkennen (nicht am Pfad).

Basisspiel (CD/Steam/GOG ohne Erweiterung) = genau die 24 Kampagnen- und 34 MP-Missionsordner unten.
'Courage Under Fire' bzw. 'Sabre Squadron' bringt zusätzliche Missionsordner in den Archiven mit; jeder
Missionsordner außerhalb der Basisliste gilt als Erweiterungsinhalt (unbekannte *.dta werden nur gemeldet).
Nur lesen: die Archive werden lediglich über ihr Verzeichnis geöffnet.

Aufruf: python -I hd2_edition.py <HD2-Ordner>   -> eine JSON-Zeile:
  {"edition": "base"|"cuf", "extra_missions": [...], "unknown_archives": [...], "exe_size": n, "exe_known": "..."}
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BASE_MISSIONS = {
    "ARCTIC1", "ARCTIC2", "ARCTIC3", "ARCTIC4", "AFRICA1", "AFRICA2", "AFRICA3", "AFRICA4", "AFRICA5", "AFRICA6",
    "NORWAY", "BURMA1", "BURMA2", "ALPS1", "ALPS2", "NORMANDY", "NORMANDY2", "CZECH1", "CZECH2", "CZECH3", "CZECH4",
    "CZECH5", "CZECH6", "TUTORIAL",
    "ARCTIC1_MP", "ARCTIC1_OBJ", "ARCTIC2_MP", "ARCTIC3_OBJ", "ARCTIC4_MP_ZONE", "AFRICA1_MP", "AFRICA1_OBJ",
    "AFRICA2_MP_ZONE", "AFRICA3_MP", "AFRICA3_OBJ", "AFRICA4_OBJ", "AFRICA5_MP", "AFRICA5_MP_ZONE", "AFRIKA5_MP",
    "ALPS1_MP_ZONE", "ARDENS1_OBJ", "BURMA1_MP", "BURMA1_MP_ZONE", "BURMA1_OBJ", "BURMA2_OBJ", "CZECH1_OBJ",
    "CZECH2_MP_ZONE", "CZECH2_OBJ", "CZECH3_MP", "CZECH3_OBJ", "CZECH4_MP_ZONE", "CZECH5_MP_ZONE", "CZECH6_MP_ZONE",
    "LONDON_MP", "NORMANDY_MP", "NORMANDY2_MP_ZONE", "NORMANDY2B_MP_ZONE", "NORMANDY3_MP", "NORMANDY3_MP_ZONE"}
BASE_ARCHIVES = {"maps.dta", "maps_c.dta", "missions.dta", "models.dta", "others.dta", "patch.dta", "scripts.dta",
                 "sounds.dta"}
# bekannte hd2.exe-Größen (Byte) -> Beschreibung; Größe allein entscheidet NICHT über die Ausgabe
KNOWN_EXE = {6889472: "Original-CD-Version mit Patch 1.11 (Entwicklungsstand)"}


def detect(orig: str) -> dict:
    res = {"edition": "base", "extra_missions": [], "unknown_archives": [], "exe_size": 0, "exe_known": ""}
    exe = os.path.join(orig, "hd2.exe")
    if os.path.exists(exe):
        res["exe_size"] = os.path.getsize(exe)
        res["exe_known"] = KNOWN_EXE.get(res["exe_size"], "")
    try:
        import dta_extract
        from dta_probe import KEYS
    except Exception as ex:   # pragma: no cover
        res["error"] = str(ex)
        return res
    extra = set()
    paths = {os.path.normcase(p): p for p in glob.glob(os.path.join(glob.escape(orig), "*.[dD][tT][aA]"))}
    for p in sorted(paths.values()):
        name = os.path.basename(p).lower()
        if name not in BASE_ARCHIVES:
            res["unknown_archives"].append(os.path.basename(p))
        if name not in KEYS:
            continue
        try:
            arc = dta_extract.Archive(p)
        except Exception:
            continue
        for e in arc.entries:
            parts = e[0].replace("/", "\\").split("\\")
            if len(parts) >= 3 and parts[0].lower() == "missions":
                m = parts[1].upper()
                if m not in BASE_MISSIONS:
                    extra.add(m)
        arc.f.close()
    res["extra_missions"] = sorted(extra)
    # nur zusätzliche Missionen entscheiden; weitere Archive (z. B. Maps_U.dta sprachabhängig) sind bloß Hinweis
    if extra:
        res["edition"] = "cuf"
    return res


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    print(json.dumps(detect(sys.argv[1])))
