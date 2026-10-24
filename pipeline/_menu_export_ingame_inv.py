"""Exportiert den Ingame-Inventarbildschirm aus MODELS\\gameinterface.4ds (Frames `inventory` mit
`items00` / `items01` / `skills` sowie `description`) im Format von _menu_export.py nach
orig_cache/ui/menu/layout/ingame inventory.json (Feld "tris" = Dreiecke px @1024x768 + UV).

Laufzeitposition (hd2.exe 0x4A0F3A-0x4A0F58, Builder 0x4A0EE0): `inventory`->SetPos(0.178, -0.333, 0)
(Konstanten 0x3E3645A2 / 0xBEAA7EFA). Das Modell liegt ausserhalb des Bildes (x ~ -1.455); alle Frames
der Gruppe werden um (Laufzeit - Modellposition) verschoben. `description` bleibt in Modelllage
(wird im Spiel an den Gegenstand gesetzt).
Aufruf: pyenv\\Scripts\\python.exe -I _menu_export_ingame_inv.py
"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import _menu_layout as L
import _menu_4ds as M4
import convert_mission as cm
import _menu_export as E

OUT = os.path.join(cm.CACHE, "ui", "menu")
RUNTIME_POS = (struct.unpack("<f", struct.pack("<I", 0x3E3645A2))[0],
               struct.unpack("<f", struct.pack("<I", 0xBEAA7EFA))[0])


def main():
    el = L.layout("gameinterface.4ds")
    mdl = M4.load("gameinterface.4ds")
    inv = next(f for f in mdl["frames"] if f["name"] == "inventory")
    dx = (RUNTIME_POS[0] - inv["pos"][0]) * L.W
    dy = -(RUNTIME_POS[1] - inv["pos"][1]) * L.W
    names = {e["name"]: e for e in el}

    def root_of(e):
        p = e.get("parent"); r = e["name"]
        while p:
            r = p
            p = names[p].get("parent") if p in names else None
        return r

    keep = []
    for e in el:
        r = root_of(e)
        if r not in ("inventory", "description"):
            continue
        sh = (dx, dy) if r == "inventory" else (0.0, 0.0)
        e["root"] = r
        if "_tris" in e:
            e["_tris"] = [(tn, [(v[0] + sh[0] / L.W, v[1] - sh[1] / L.W, v[2], v[3], v[4]) for v in tri])
                          for tn, tri in e["_tris"]]
            e["tris"] = [[tn or "", [[round(L.to_px(v)[0], 2), round(L.to_px(v)[1], 2),
                                      round(v[3], 5), round(v[4], 5)] for v in tri]] for tn, tri in e["_tris"]]
            rp = e["rect_px"]
            e["rect_px"] = [round(rp[0] + sh[0], 1), round(rp[1] + sh[1], 1), round(rp[2] + sh[0], 1), round(rp[3] + sh[1], 1)]
            e["rect_norm"] = [round(e["rect_px"][0] / L.W, 4), round(e["rect_px"][1] / L.H, 4),
                              round(e["rect_px"][2] / L.W, 4), round(e["rect_px"][3] / L.H, 4)]
        elif "pos_px" in e:
            e["pos_px"] = [round(e["pos_px"][0] + sh[0], 1), round(e["pos_px"][1] + sh[1], 1)]
        keep.append(e)
    frames = L.strip(keep)
    tdir = os.path.join(OUT, "textures")
    os.makedirs(tdir, exist_ok=True)
    done, missing = {}, set()
    texs = sorted({g["texture"] for e in frames for g in e.get("groups", []) if g["texture"]})
    for t in texs:
        E.export_tex(t, tdir, done, missing)
    lay = {"model": "MODELS\\gameinterface.4ds (inventory, description)",
           "screen": "1024x768 reference; px = x*1024, py = -y*1024 (4DS units)",
           "runtime_pos": {"inventory": list(RUNTIME_POS), "source": "hd2.exe 0x4A0F3A"},
           "shift_px": [round(dx, 2), round(dy, 2)], "background_frame": None, "background_tiles": [],
           "frames": frames}
    os.makedirs(os.path.join(OUT, "layout"), exist_ok=True)
    json.dump(lay, open(os.path.join(OUT, "layout", "ingame inventory.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    L.render(keep, os.path.join(OUT, "previews", "ingame inventory.png"),
             skip=lambda e: e["name"].startswith(("actived", "inactived")) or e.get("root") == "description")
    print("Frames:", len(frames), "Verschiebung px:", round(dx, 1), round(dy, 1), "Texturen:", texs, "fehlend:", sorted(missing))


if __name__ == "__main__":
    main()
