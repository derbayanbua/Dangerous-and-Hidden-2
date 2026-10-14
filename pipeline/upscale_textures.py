"""KI-Upscaling der aus dem Original konvertierten Texturen (Real-ESRGAN x4plus, CPU).

Aufruf (venv):  pyenv\\Scripts\\python.exe -I upscale_textures.py <textures-ordner> [--install | --restore]

  ohne Option  erzeugt <ordner>_hd/<name>.png (bereits vorhandene werden übersprungen,
               d. h. der Lauf ist jederzeit abbrech-/fortsetzbar)
  --install    sichert die Originale einmalig nach <ordner>_sd/ und kopiert alle fertigen
               HD-Versionen nach <ordner>/ (Loader/glTF bleiben unverändert)
  --restore    kopiert <ordner>_sd/ zurück nach <ordner>/

Regeln:
  - RGB wird mit Real-ESRGAN x4 hochskaliert; vorher Wrap-Padding, damit kachelbare
    Texturen keine Nahtkanten bekommen.
  - Alpha wird getrennt (Lanczos) skaliert; reine 0/255-Masken (Colorkey/Alphatest)
    werden danach wieder hart geschwellt.
  - Texturen < 64 px (Verläufe, Farbflächen) nur Lanczos x4; Ergebnis max. 2048 px.
"""
import os
import shutil
import sys
import time

import numpy as np
import torch
from PIL import Image
from spandrel import ModelLoader

HERE = os.path.dirname(os.path.abspath(__file__))
WEIGHTS = os.path.join(HERE, "sr_models", "RealESRGAN_x4plus.pth")
MAX_SIDE = 2048
MIN_SR = 64
PAD = 16
TILE = 192


def load_model():
    torch.set_num_threads(os.cpu_count() or 4)
    m = ModelLoader().load_from_file(WEIGHTS)
    m.model.eval()
    return m


@torch.inference_mode()
def sr_rgb(model, rgb: np.ndarray) -> np.ndarray:
    """rgb uint8 HxWx3 -> uint8 (4H)x(4W)x3, gekachelt mit Überlappung."""
    h, w, _ = rgb.shape
    p = min(PAD, h, w)
    src = np.pad(rgb, ((p, p), (p, p), (0, 0)), mode="wrap").astype(np.float32) / 255.0
    t = torch.from_numpy(src).permute(2, 0, 1).unsqueeze(0)
    H, W = t.shape[2], t.shape[3]
    out = torch.zeros(1, 3, H * 4, W * 4)
    ov = 8
    for y in range(0, H, TILE):
        for x in range(0, W, TILE):
            y0, x0 = max(y - ov, 0), max(x - ov, 0)
            y1, x1 = min(y + TILE + ov, H), min(x + TILE + ov, W)
            r = model(t[:, :, y0:y1, x0:x1])
            ty, tx = (y - y0) * 4, (x - x0) * 4
            th, tw = (min(y + TILE, H) - y) * 4, (min(x + TILE, W) - x) * 4
            out[:, :, y * 4:y * 4 + th, x * 4:x * 4 + tw] = r[:, :, ty:ty + th, tx:tx + tw]
    out = out[:, :, p * 4:(p + h) * 4, p * 4:(p + w) * 4]
    return (out.squeeze(0).permute(1, 2, 0).clamp(0, 1).numpy() * 255.0 + 0.5).astype(np.uint8)


def upscale(model, im: Image.Image) -> Image.Image:
    w, h = im.size
    alpha = im.getchannel("A") if im.mode == "RGBA" else None
    rgb = im.convert("RGB")
    if min(w, h) >= MIN_SR and model is not None:
        big = Image.fromarray(sr_rgb(model, np.asarray(rgb)))
    else:
        big = rgb.resize((w * 4, h * 4), Image.LANCZOS)
    if alpha is not None:
        a = np.asarray(alpha)
        binary = np.isin(a, (0, 255)).all()
        ab = alpha.resize(big.size, Image.LANCZOS)
        if binary:
            ab = ab.point(lambda v: 255 if v >= 128 else 0)
        big.putalpha(ab)
    if max(big.size) > MAX_SIDE:
        f = MAX_SIDE / max(big.size)
        big = big.resize((max(1, round(big.width * f)), max(1, round(big.height * f))), Image.LANCZOS)
    return big


WEIGHTS_FAST = os.path.join(HERE, "sr_models", "realesr-general-x4v3.pth")
MAX_SIDE_4K = 4096


def run_4k(src):
    """Stufe 2: <ordner>_hd (bzw. Original) mit dem schnellen Modell nochmals x4, dann auf das Doppelte der
    HD-Größe (max. 4096 px) verkleinert -> <ordner>_4k. Alpha/Colorkey wie Stufe 1. Fortsetzbar."""
    base = src.rstrip("\\/")
    hd, dst = base + "_hd", base + "_4k"
    os.makedirs(dst, exist_ok=True)
    names = sorted((f for f in os.listdir(base) if f.lower().endswith(".png")),
                   key=lambda f: os.path.getsize(os.path.join(base, f)))
    todo = [f for f in names if not os.path.exists(os.path.join(dst, f))]
    print("4K: Texturen %d, offen %d" % (len(names), len(todo)), flush=True)
    global MAX_SIDE
    model = None
    if todo:
        # Mehrtägiger Hintergrundlauf: Threads begrenzbar, damit Spiel/Tests parallel laufen können
        torch.set_num_threads(int(os.environ.get("DH2_SR_THREADS", os.cpu_count() or 4)))
        model = ModelLoader().load_from_file(WEIGHTS_FAST if os.path.exists(WEIGHTS_FAST) else WEIGHTS)
        model.model.eval()
    t0 = time.time()
    for i, f in enumerate(todo, 1):
        s = os.path.join(hd, f) if os.path.exists(os.path.join(hd, f)) else os.path.join(base, f)
        im = Image.open(s)
        im.load()
        target = min(max(im.size) * 2, MAX_SIDE_4K)
        MAX_SIDE = target
        out = upscale(model, im)
        tmp = os.path.join(dst, f + ".tmp")
        out.save(tmp, "PNG", optimize=False)
        os.replace(tmp, os.path.join(dst, f))
        print("[%d/%d] %s %dx%d -> %dx%d  (%.0fs gesamt)" % (i, len(todo), f, im.width, im.height,
                                                          out.width, out.height, time.time() - t0), flush=True)
    print("FERTIG 4K", flush=True)


def run(src):
    dst = src.rstrip("\\/") + "_hd"
    os.makedirs(dst, exist_ok=True)
    names = sorted((f for f in os.listdir(src) if f.lower().endswith(".png")),
                   key=lambda f: os.path.getsize(os.path.join(src, f)))
    # neu oder seit dem letzten Lauf geändert (z. B. v1.12-Texturen aus patch.dta)
    todo = [f for f in names if not os.path.exists(os.path.join(dst, f))
            or os.path.getmtime(os.path.join(dst, f)) < os.path.getmtime(os.path.join(src, f))]
    print("Texturen: %d, offen: %d" % (len(names), len(todo)), flush=True)
    model = load_model() if todo else None
    t0 = time.time()
    for i, f in enumerate(todo, 1):
        im = Image.open(os.path.join(src, f))
        im.load()
        out = upscale(model, im)
        tmp = os.path.join(dst, f + ".tmp")
        out.save(tmp, "PNG", optimize=False)
        os.replace(tmp, os.path.join(dst, f))
        el = time.time() - t0
        print("[%d/%d] %s %dx%d -> %dx%d  (%.0fs gesamt)" % (i, len(todo), f, im.width, im.height,
                                                          out.width, out.height, el), flush=True)
    print("FERTIG", flush=True)


def install(src):
    base = src.rstrip("\\/")
    sd, hd = base + "_sd", base + "_hd"
    if not os.path.isdir(sd):
        shutil.copytree(base, sd)
    n = 0
    for f in os.listdir(hd):
        if f.lower().endswith(".png"):
            shutil.copy2(os.path.join(hd, f), os.path.join(base, f))
            n += 1
    print("installiert: %d HD-Texturen (Originale in %s)" % (n, sd))


def restore(src):
    base = src.rstrip("\\/")
    sd = base + "_sd"
    for f in os.listdir(sd):
        shutil.copy2(os.path.join(sd, f), os.path.join(base, f))
    print("wiederhergestellt aus", sd)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    folder = sys.argv[1]
    if "--install" in sys.argv:
        install(folder)
    elif "--restore" in sys.argv:
        restore(folder)
    elif "--4k" in sys.argv:
        run_4k(folder)
    else:
        run(folder)
