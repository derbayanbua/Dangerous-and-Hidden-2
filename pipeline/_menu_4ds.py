import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import convert_mission as cm
import fmt_4ds


def _rm(r):
    """Wie fmt_4ds.read_material, aber Alpha-Map nur wenn ALPHATEX und NICHT 0x01000000
    (belegt an kurzor_menu.4ds / X_ARCADE in multiplayer menu.4ds)."""
    m = {"flags": r.u32()}
    m["ambient"] = r.vec(4); m["diffuse"] = r.vec(4); m["emission"] = r.vec(4); m["specular"] = r.vec(4)
    m["glossiness"] = r.f32(); m["opacity"] = r.f32(); f = m["flags"]
    if f & fmt_4ds.MTL_ENVMAP:
        m["env_ratio"] = r.f32(); m["env_map"] = r.pstr()
    m["diffuse_map"] = r.pstr()
    if f & fmt_4ds.MTL_ALPHATEX and not f & 0x01000000:
        m["alpha_map"] = r.pstr()
    if f & fmt_4ds.MTL_ANIM_DIFFUSE:
        m["anim"] = [r.u32(), r.u16(), r.u32(), r.u32(), r.u32()]
    return m


fmt_4ds.read_material = _rm


def load(name):
    d = cm.read_file("models/" + name, ["MODELS.DTA"])
    return fmt_4ds.read_model(d)


if __name__ == "__main__":
    name = sys.argv[1]
    mdl = load(name)
    print("frames", len(mdl["frames"]), "/", mdl["frame_count"], "stop", mdl["stop"])
    for i, m in enumerate(mdl["materials"]):
        print("MAT", i + 1, hex(m["flags"]), m.get("diffuse_map"), m.get("alpha_map", ""), "op", m["opacity"],
              "dif", [round(x, 2) for x in m["diffuse"]], "em", [round(x, 2) for x in m["emission"]], m.get("anim", ""))
    for f in mdl["frames"]:
        lods = f.get("lods", [])
        info = ""
        if lods:
            l = lods[0]
            vs = l["vertices"]
            xs = [v[0] for v in vs]; ys = [v[1] for v in vs]; zs = [v[2] for v in vs]
            mats = [g["material"] for g in l["groups"]]
            info = "nv %d mats %s bb x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f] uv %s" % (
                len(vs), mats, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs),
                [tuple(round(c, 3) for c in v[6:8]) for v in vs[:4]])
        print(f["index"] + 1, "t%d" % f["type"], f.get("visual", ""), repr(f["name"]), "par", f["parent"],
              "pos", [round(x, 4) for x in f["pos"]], "rot", [round(x, 3) for x in f["rot"]],
              "scl", [round(x, 3) for x in f["scale"]], repr(f["params"]),
              "inst", f.get("instance", ""), info)
