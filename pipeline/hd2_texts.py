"""B-024/O-002: Originaltexte sprachneutral laden (jede Sprachinstallation: de/en/fr/it/es/cs).

convert_mission.convert_all_texts erzeugt nur texts_<sprache>.json der installierten Sprachen. Die Konverter
nehmen deshalb die erste vorhandene Datei in dieser Reihenfolge (wie Settings.orig_texts: Deutsch zuerst),
danach jede weitere texts_*.json (alphabetisch). DH2_LANG=<ordner> setzt eine Sprache vorne an.
Fehlende IDs werden aus den übrigen vorhandenen Sprachen ergänzt (z. B. japan hat nur 60 Texte).
"""
import glob
import json
import os

PREFERRED = ["german", "english", "englishus", "french", "italian", "spanish", "czech"]


def text_files(cache: str) -> list:
    """Vorhandene texts_*.json in Vorrangreihenfolge (vollständige Pfade)."""
    found = {os.path.basename(p)[6:-5].lower(): p for p in glob.glob(os.path.join(cache, "texts_*.json"))}
    order = []
    env = (os.environ.get("DH2_LANG") or "").strip().lower()
    for lang in ([env] if env else []) + PREFERRED + sorted(found):
        if lang in found and found[lang] not in order:
            order.append(found[lang])
    return order


def load_texts(cache: str) -> dict:
    """{id: text} der ersten vorhandenen Sprache, Lücken aus den weiteren ergänzt; {} wenn keine vorhanden."""
    out = {}
    for p in text_files(cache):
        try:
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(d, dict):
            for k, v in d.items():
                out.setdefault(k, v)
    return out


if __name__ == "__main__":
    import sys
    c = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DH2_CACHE", ".")
    fs = text_files(c)
    print("Sprachdateien:", [os.path.basename(p) for p in fs], "Texte:", len(load_texts(c)))
