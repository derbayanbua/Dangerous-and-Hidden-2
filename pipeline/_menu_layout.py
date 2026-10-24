"""Menu-4DS -> Weltkoordinaten/Bildschirm-Rechtecke + Vorschau-PNG.
Annahme (verifiziert an main_menu.4ds): Bildschirm = Ebene z~0, x 0..1 (links->rechts),
y 0..-0.75 (oben->unten) => Pixel bei 1024x768: px = x*1024, py = -y*1024.
Rotation: Original wendet Quaternion konjugiert an (siehe convert_mission.crot_xyzw)."""
import io, json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _menu_4ds as M4
import convert_mission as cm
from PIL import Image, ImageDraw

W, H = 1024, 768


def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qrot(q, v):
    p = (v[0], v[1], v[2], 0.0)
    r = qmul(qmul(q, p), qconj(q))
    return r[:3]


def world(frames):
    """returns per frame (pos, eff_quat, scale) ; eff_quat = conj(stored) composed parent*child"""
    out = {}
    for f in frames:
        q = qconj(tuple(f["rot"]))
        s = f["scale"]
        if f["parent"] == 0:
            out[f["index"] + 1] = (tuple(f["pos"]), q, tuple(s))
        else:
            pp, pq, ps = out[f["parent"]]
            lp = [f["pos"][i] * ps[i] for i in range(3)]
            wp = qrot(pq, lp)
            out[f["index"] + 1] = ((pp[0] + wp[0], pp[1] + wp[1], pp[2] + wp[2]), qmul(pq, q),
                                   tuple(ps[i] * s[i] for i in range(3)))
    return out


def to_px(p):
    return (p[0] * W, -p[1] * W)


_texcache = {}


def tex(name):
    key = name.upper()
    if key not in _texcache:
        d = cm.read_tex(name)
        _texcache[key] = Image.open(io.BytesIO(d)).convert("RGBA") if d else None
    return _texcache[key]


def layout(model_name):
    mdl = M4.load(model_name)
    frames = mdl["frames"]
    mats = mdl["materials"]
    W_ = world(frames)
    names = {f["index"] + 1: f["name"] for f in frames}
    elems = []
    for f in frames:
        i = f["index"] + 1
        pos, q, sc = W_[i]
        e = {"frame": i, "name": f["name"], "type": {1: "visual", 6: "dummy"}.get(f["type"], f["type"]),
             "parent": names.get(f["parent"]), "z": round(pos[2], 4)}
        lods = f.get("lods")
        if lods:
            l = lods[0]
            vs = []
            for v in l["vertices"]:
                lv = [v[k] * sc[k] for k in range(3)]
                wv = qrot(q, lv)
                vs.append((pos[0] + wv[0], pos[1] + wv[1], pos[2] + wv[2], v[6], v[7]))
            px = [to_px(v) for v in vs]
            xs = [p[0] for p in px]; ys = [p[1] for p in px]
            e["rect_px"] = [round(min(xs), 1), round(min(ys), 1), round(max(xs), 1), round(max(ys), 1)]
            e["rect_norm"] = [round(min(xs) / W, 4), round(min(ys) / H, 4), round(max(xs) / W, 4), round(max(ys) / H, 4)]
            groups = []
            tris = []
            for g in l["groups"]:
                m = mats[g["material"] - 1] if g["material"] else None
                tn = m.get("diffuse_map") if m else None
                us = [vs[k][3] for k in g["faces"]]; vv = [vs[k][4] for k in g["faces"]]
                groups.append({"material": g["material"], "texture": tn or None,
                               "uv_rect": [round(min(us), 4), round(min(vv), 4), round(max(us), 4), round(max(vv), 4)]})
                for t in range(0, len(g["faces"]), 3):
                    tris.append((tn, [vs[k] for k in g["faces"][t:t + 3]]))
            e["groups"] = groups
            e["_tris"] = tris
            e["onscreen"] = max(xs) > 0 and min(xs) < W and max(ys) > 0 and min(ys) < H
        else:
            e["pos_px"] = [round(c, 1) for c in to_px(pos)]
        elems.append(e)
    return elems


def render(elems, out_png, skip=lambda e: False, outline=True):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    # nach z sortieren: groesseres z = weiter hinten (zuerst zeichnen)
    vis = [e for e in elems if "_tris" in e and not skip(e)]
    vis.sort(key=lambda e: -e["z"])
    dr = ImageDraw.Draw(img)
    for e in vis:
        for tn, tri in e["_tris"]:
            dst = [to_px(v) for v in tri]
            if tn and tex(tn) is not None:
                t = tex(tn)
                tw, th = t.size
                src = [(v[3] * tw, v[4] * th) for v in tri]
                # affine dst->src
                (x0, y0), (x1, y1), (x2, y2) = dst
                (u0, v0), (u1, v1), (u2, v2) = src
                den = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
                if abs(den) < 1e-9:
                    continue
                def solve(a0, a1, a2):
                    A = ((a1 - a0) * (y2 - y0) - (a2 - a0) * (y1 - y0)) / den
                    B = ((a2 - a0) * (x1 - x0) - (a1 - a0) * (x2 - x0)) / den
                    C = a0 - A * x0 - B * y0
                    return A, B, C
                a = solve(u0, u1, u2); b = solve(v0, v1, v2)
                warped = t.transform((W, H), Image.AFFINE, a + b, resample=Image.BILINEAR)
                mask = Image.new("L", (W, H), 0)
                ImageDraw.Draw(mask).polygon(dst, fill=255)
                img.paste(warped, (0, 0), mask)
            elif outline:
                dr.polygon(dst, outline=(255, 255, 0, 255))
        if outline and e["name"]:
            r = e["rect_px"]
            if not any(g["texture"] for g in e["groups"]):
                dr.text((r[0] + 2, r[1]), e["name"], fill=(255, 255, 0, 255))
    img.convert("RGB").save(out_png)


def strip(elems):
    return [{k: v for k, v in e.items() if not k.startswith("_")} for e in elems]


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    name = sys.argv[1]
    el = layout(name)
    for e in strip(el):
        if e.get("rect_px"):
            print("%3d %-26s par=%-20s rect=%s z=%s on=%s %s" % (e["frame"], e["name"], e["parent"], e["rect_px"], e["z"], e["onscreen"],
                  [(g["texture"], g["uv_rect"]) for g in e["groups"]]))
        else:
            print("%3d %-26s DUMMY par=%s pos=%s" % (e["frame"], e["name"], e["parent"], e["pos_px"]))
    if len(sys.argv) > 2:
        render(el, sys.argv[2], skip=lambda e: e["name"].startswith("actived"))
