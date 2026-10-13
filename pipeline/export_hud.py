"""Rekonstruiert das In-Game-HUD von Hidden & Dangerous 2 aus MODELS\\gameinterface.4ds.

Ausgabe (lokaler Cache, nie committen):
  DangerousHidden2/orig_cache/ui/hud/
    textures/*.png        alle 147 HUD-Texturen (TGA mit Alpha, BMP als RGB)
    crops/<frame>.png     Ausschnitt der UV-Fläche je Element (v. a. Atlas X_ALL.BMP)
    hud_spec.json         Elemente: Zweck, Textur, Rechteck (normiert 0..1, y nach unten), Anker, Konfidenz
    hud_frames.json       alle 602 Frames roh (Hierarchie, Welt-Rechteck, z, Materialien, UV)
    hud_preview.png       Vorschau (1024x768) des Standard-HUD
    hud_preview_all.png   Vorschau inkl. Overlays/Taktikkarte (nur zur Kontrolle)

Bildschirmabbildung (Belege docs/re_notes_hud.md):
  hd2.exe 0x49af10ff. erzeugt eine eigene Kamera für das Interface: Position (0.5, -0.375, -15.5),
  Blickrichtung +z. Das Modell liegt in x 0..1, y 0..-0.75 (4:3). => Bildschirm:
     u = x,  v = -y / 0.75   (0,0 = oben links, 1,1 = unten rechts)
  Kleinere z = näher an der Kamera = wird darüber gezeichnet.
  4DS-Quaternionen werden wie im übrigen Konverter konjugiert angewendet (nur damit liegt
  down_panel bündig am unteren Bildrand und alle Texturen stehen aufrecht).

Aufruf: pyenv\\Scripts\\python.exe -I export_hud.py
"""
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds_ui as U  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

OUT = os.path.join(cm.CACHE, "ui", "hud")
SCREEN_H = 0.75

# --- Elementkatalog --------------------------------------------------------------------------
# (Frame-Muster, Gruppe, Zweck, Konfidenz, Notiz)
#   Konfidenz: "B" belegt (Frame-Name + Code-Zugriff in hd2.exe), "P" plausibel, "?" Vermutung
CATALOG = [
    # Kompass oben links
    (r"kompas", "compass", "Kompass: Glasabdeckung/Rahmen (X_KMPSCV)", "B", "hd2.exe greift 'kompas' ab (0x493fa4)"),
    (r"kmpscvr", "compass", "Kompass: Ziffernblatt (X_KMPS, N/O/S/W-Skala), dreht sich mit Blickrichtung", "P", "Code-String 'kmpscvr'"),
    (r"strelka", "compass", "Kompassnadel (X_KMPSRU; 'strelka' = russ. Pfeil)", "B", "Code-String 'strelka' (0x493fce)"),
    (r"kmps_bl\d\d", "compass", "Kompass: innerer Ring, 8 Sektoren à 45° (blau, X_KMPSB)", "P",
     "Code 'kmps_bl%02d'; Bedeutung vermutlich Richtungsanzeige (z. B. Geräusch/Kameraden) – ungeprüft"),
    (r"kmps_rd\d\d", "compass", "Kompass: äußerer Ring, 8 Sektoren à 45° (rot, X_KMPSR)", "P",
     "Code 'kmps_rd%02d'; Bedeutung vermutlich Gefahren-/Feindrichtung – ungeprüft"),
    (r"kul_us", "compass", "Kompass-Punkt verbündet (X_KULUS, blau)", "P", "Code 'kul_us'"),
    (r"kul_en", "compass", "Kompass-Punkt Feind (X_KULEN, rot)", "P", "Code 'kul_en'"),
    # Untere Leiste (down_panel)
    (r"tabl01", "squad_bar", "Linkes Feld der unteren Leiste: Haltung/Gangart des aktiven Soldaten", "B", "Code 'tabl01'"),
    (r"pkneel", "squad_bar", "Haltungssymbol hocken (Atlas X_ALL)", "P", "Code 'pkneel'"),
    (r"play", "squad_bar", "Haltungssymbol liegen (Atlas X_ALL; 'play' = tsch. 'plaz'?)", "?", "Code 'play'; gleiche Stelle wie pkneel"),
    (r"mwalk|mrun|msprint", "squad_bar", "Gangart-Anzeige (gehen/rennen/sprinten; Pfeile im Atlas X_ALL)", "P", "Code 'mwalk','mrun','msprint'"),
    (r"mpaxis|mpallied", "squad_bar", "Mehrspieler-Seitenwappen (Achse/Alliierte) im linken Feld", "P", "Code 'mpaxis','mpallied'"),
    (r"soldier0\d", "squad_bar", "Soldatenfeld (Hintergrund, Atlas X_ALL beige); 6 Felder nebeneinander", "B", "Code 'Soldier%02d'/'soldier00'"),
    (r"select(0\d)?", "squad_bar", "Soldatenfeld: Hintergrund 'ausgewählt' (Atlas grau)", "P", "Code 'select*'"),
    (r"player0\d", "squad_bar", "Soldatenfeld: Hintergrund 'aktiver Spieler' (Atlas rot)", "P", "Code 'player0*'"),
    (r"photo0\d", "squad_bar", "Portrait des Soldaten (Platzhalter X_F_004; zur Laufzeit x_f_*.bmp / x_fc_death.bmp)", "B",
     "Code 'photo*', 'x_fc_death.bmp', 'x_fc_a.bmp'"),
    (r"health0\d", "squad_bar", "Gesundheitsbalken: Füllung (Atlas, vertikal)", "B", "Code 'health0*'"),
    (r"healthcr0\d", "squad_bar", "Gesundheitsbalken: zweite Füllfarbe (kritisch?)", "P", "Code 'healthcr*'"),
    (r"healthbar(0\d)?", "squad_bar", "Gesundheitsbalken: Abdeckung/Leerteil (liegt vorne, wird vermutlich skaliert)", "P", "Code 'healthbar*' (0x4b3248)"),
    (r"stamina0\d", "squad_bar", "Ausdauerbalken: Füllung", "B", "Code 'stamina0*'"),
    (r"staminabar(0\d)?", "squad_bar", "Ausdauerbalken: Abdeckung/Leerteil", "P", "Code 'staminabar*'"),
    (r"disguise0\d", "squad_bar", "Tarnungsbalken (Feinduniform): Füllung", "B", "Code 'disguise0*'"),
    (r"disguisebar(0\d)?", "squad_bar", "Tarnungsbalken: Abdeckung/Leerteil", "P", "Code 'disguisebar*'"),
    (r"mind0\d", "squad_bar", "KI-Modus-Symbol (passiv/defensiv/aggressiv; Textur zur Laufzeit aus playerstate*)", "P", "Code 'mind*'"),
    (r"command0\d", "squad_bar", "Aktueller Befehl/Tätigkeit des Soldaten (Textur zur Laufzeit aus playerstate*)", "P", "Code 'command*'"),
    (r"visibility0\d", "squad_bar", "Sichtbarkeitsanzeige (farbiges Rechteck, Atlas-UV)", "B", "Code 'visibility*'"),
    (r"AImode0\d", "squad_bar", "KI-Steuerung aktiv (X_AI)", "P", "Code 'AImode*'"),
    (r"ear0\d", "squad_bar", "Hört etwas / Geräuschanzeige (X_EAR)", "?", "Code 'ear*'"),
    (r"silence0\d", "squad_bar", "Funkstille/Schalldämpfer-Marke (X_SILENC)", "?", "Code 'silence*'"),
    (r"medic0\d", "squad_bar", "Sanitäter-Marke (X_MEDIC)", "P", "Code 'medic*'"),
    (r"mp_vip", "multiplayer", "Mehrspieler: VIP-Marke im Soldatenfeld", "P", "Code 'mp_vip*'"),
    (r"tabl02", "squad_bar", "Rechtes Feld der unteren Leiste: Waffen in der Hand / auf der Schulter", "B", "Code 'tabl02'"),
    (r"i_hands", "squad_bar", "Gegenstand in der Hand (64x32-Icon ii_*.bmp auf X_BUBBLE)", "B", "Code 'i_hands'"),
    (r"i_shoulder", "squad_bar", "Gegenstand auf der Schulter (64x32-Icon ii_*.bmp)", "B", "Code 'i_shoulder'"),
    (r"rollmenu", "squad_bar", "Ausklappmenü links über der Leiste (Nummernliste, Waffen-/Befehlsauswahl)", "P", "Code 'rollmenu', Formate '%d. ' / '0. '"),
    (r"signals", "squad_bar", "Ausklappmenü rechts über der Leiste: Signale/Befehle an den Trupp", "P", "Code 'signals'"),
    (r"spee|speed|spd|speed0\d", "vehicle", "Tacho (Fahrzeug; X_SPEEDO, Zeiger speed01-03)", "P", "Code 'spee','speed01..03'"),
    # Rechts oben
    (r"select_weapon", "weapon_select", "Waffenauswahl (Gruppe)", "B", "Code 'select_weapon'"),
    (r"select_weapon0\d", "weapon_select", "Waffenauswahl: Eintrag (Icon 64x32, Platzhalter I_FREHND 'freie Hand')", "B", "Code 'select_weapon00..02', 'i_frehnd.bmp'"),
    (r"selector_weapon", "weapon_select", "Waffenauswahl: Markierung (MM_RED-Rahmen)", "B", "Code 'selector_weapon'"),
    (r"drkr\d", "weapon_select", "Waffenauswahl: abgedunkelte Nachbareinträge (X_BLCKA)", "P", "Code 'drkr1','drkr2'"),
    (r"tabl03", "weapon_select", "Waffenauswahl: Hintergrundtafel", "B", "Code 'tabl03'"),
    (r"info0\d", "info", "Info-/Meldungssymbole rechte Spalte (10 Plätze, Textur zur Laufzeit)", "P", "Code 'info%02d'"),
    (r"infosel", "info", "Info-Spalte: Markierung", "P", "Code 'infosel'"),
    (r"explosivetimer|timer-explosive\d\d", "info", "Zeitzünder-Liste (bis 10 gelegte Sprengladungen mit Restzeit)", "P", "Code 'timer-explosive%02d', '%02d:%02d'"),
    (r"Htext", "text", "Hinweis-/Meldungstextband (volle Breite)", "B", "Code 'Htext'"),
    (r"text", "text", "Chat-/Funktextbereich", "P", "Code 'Text','Say: %s','SayTeam: %s'"),
    (r"minimap01", "text", "Unterlage des Textbereichs", "?", ""),
    (r"cross|cross_[tlrb]|cross_name", "crosshair", "Fadenkreuz (4 Striche) + Name des anvisierten Objekts; zur Laufzeit positioniert", "B", "Code 'cross_T/B/L/R','cross_name'"),
    (r"prgbrbk|prgbr01|progress_name|shadow05", "progress", "Fortschrittsbalken (z. B. Schloss knacken/Sprengsatz) mit Beschriftung", "P", "Code 'prgbrbk','prgbr01','progress_name','%s %s - %d%%'"),
    # Vollbild-Overlays
    (r"scope|Object02", "overlay", "Zielfernrohr-Maske (2E_SCOPE) + Absehen", "P", "Code 'scope'"),
    (r"sniper", "overlay", "Scharfschützen-Overlay (E_ZAMER)", "P", "Code 'sniper'"),
    (r"springfield|k98|arisaka|lee_enfield|cross[1-4]", "overlay", "Absehen je Zielfernrohrwaffe", "B", "Code 'springfield','k98','arisaka','lee_enfield'"),
    (r"camera|zamer", "overlay", "Fernglas/Kamera-Overlay (2E_CAMRA) mit Skala", "P", "Code 'camera'"),
    (r"injury", "overlay", "Verletzungs-Overlay (Vollbild)", "P", "Code 'injury', 'GameMovie\\AnimHit%d.bik'"),
    # Taktische Karte / Mauszeiger
    (r"border", "tactical_map", "Taktische Karte: Rahmen/Leiste unten", "B", "Code 'Border' (0x49b108)"),
    (r"~?(regroup|wait0\d|stay|kneel|lie|sprint|run|walk|slow|passive|defensive|aggresive|delete|deleteall|realtime|options|TMcamera(\d+x)?)", "tactical_map",
     "Taktische Karte: Befehlsknopf (~ = inaktive Variante)", "B", "Code-Strings gleichnamig"),
    (r"text_(regroup|signals|pose|movement|mind|delete|options|cameramotion)", "tactical_map", "Taktische Karte: Beschriftung der Knopfgruppe", "B", "Code 'text_pose' usw."),
    (r"kurzor", "tactical_map", "Mauszeiger (X_KURSOR)", "B", "Code 'kurzor'"),
    (r"k_rotate|k_move|k_movepos|t_\w+", "tactical_map", "Taktische Karte: Kamerasteuerungs-Symbole (Vorlagen außerhalb des Bildes)", "P", "Code 't_left' … 'k_movepos'"),
    (r"civil|enemy|allied|allied_active|vip|objective|mapcamera", "tactical_map", "Kartenmarker (Zivilist/Feind+Sichtkegel/eigene/aktiv/VIP/Ziel/Kamera-Sichtfeld)", "B", "Code-Strings gleichnamig"),
    # Inventar
    (r"inventory", "inventory", "Inventarfenster (liegt links außerhalb, wird eingeblendet)", "B", "Code 'inventory'"),
    (r"description|shadow04", "inventory", "Tooltip/Beschreibung", "P", "Code 'description'"),
    # Mehrspieler
    (r"mp_scoretable|mpallied_score|mpaxis_score", "multiplayer", "Mehrspieler-Punktetafel", "B", "Code 'mp_scoretable'"),
    (r"mpobjectives|mp(allied|axis|neutral)_obj\d\d", "multiplayer", "Mehrspieler-Ziele (Flaggen)", "B", "Code 'mpallied_obj%02d'"),
    (r"voting", "multiplayer", "Abstimmungsband", "P", "Code 'voting'"),
    (r"carnage_stats", "multiplayer", "Carnage-Statistik", "P", "Code 'carnage_stats'"),
    # Vorlagen (nur Texturquellen)
    (r"action\d\d", "template", "Vorlage: Aktionssymbol (Kontextaktion); nur Texturquelle, Frame wird versteckt", "B",
     "hd2.exe 0x49b730: 'action%02d' -> Textur gemerkt, Frame ausgeschaltet"),
    (r"playerstate[12]_\d\d", "template", "Vorlage: Zustands-/Befehlssymbol für mind*/command*; nur Texturquelle", "B",
     "hd2.exe 0x49b620: 20 × playerstate1_, 40 × playerstate2_ -> Textur gemerkt, Frame ausgeschaltet"),
    (r"univerz", "template", "Vorlage: Universal-Icon", "?", "Code 'univerz'"),
]

# Wurzel-Frames, deren Position hd2.exe fest setzt (Modellraum), mit Beleg
RUNTIME_POS = {
    "cross": ((0.5, -0.375, -0.14), "hd2.exe 0x4a978f: cross.pos = (0.5, -0.375, -0.14) = Bildmitte"),
}
DEFAULT_HUD_GROUPS = {"compass", "squad_bar", "weapon_select", "info", "crosshair"}
# Für die Vorschau ausgeblendet: Zustandsvarianten/Popups, die zur Laufzeit umgeschaltet werden
# (Auswahl eigene Annahme: Soldat 0 aktiv, keine Menüs offen, keine Sprengladung gelegt).
PREVIEW_HIDDEN = (r"select(0\d)?|player0[1-5]|kmps_(rd|bl)\d\d|kul_(us|en)|rollmenu|signals|timer-explosive\d\d|info0\d|infosel"
                  r"|drkr\d|mpaxis|mpallied|mp_vip|play|msprint|mrun|ear0\d|silence0\d|medic0\d|AImode0\d|healthcr0\d")


def classify(name, parents):
    for pat, grp, purpose, conf, note in CATALOG:
        if re.fullmatch(pat, name):
            return grp, purpose, conf, note
    for p in parents:  # Gruppe vom Elternteil erben
        for pat, grp, purpose, conf, note in CATALOG:
            if re.fullmatch(pat, p):
                return grp, "Teil von '%s'" % p, "?", ""
    return "unknown", "", "?", ""


def anchor_of(r):
    x0, y0, x1, y1 = r
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if x1 - x0 > 0.95 and y1 - y0 > 0.95:
        return "fullscreen"
    h = "left" if cx < 1 / 3 else ("right" if cx > 2 / 3 else "center")
    v = "top" if cy < 1 / 3 else ("bottom" if cy > 2 / 3 else "middle")
    return v + "_" + h


def main():
    os.makedirs(os.path.join(OUT, "textures"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "crops"), exist_ok=True)
    data = cm.read_file("models/gameinterface.4ds", ["Models.dta"])
    m = U.read_model(data)
    F, mats = m["frames"], m["materials"]
    moved = set()
    for i, fr in enumerate(F):
        if fr["name"] in RUNTIME_POS and fr["parent"] == 0:
            fr["pos"] = list(RUNTIME_POS[fr["name"]][0])
            moved.add(fr["name"])
    W = U.world_matrices(F, conjugate=True)

    # Texturen
    tex = {}
    for mt in mats:
        n = (mt["diffuse_map"] or "").upper()
        if not n or n in tex:
            continue
        raw = cm.read_tex(n)
        if raw is None:
            tex[n] = None
            continue
        img = Image.open(io.BytesIO(raw))
        img = img.convert("RGBA") if img.mode in ("RGBA", "LA") else img.convert("RGB")
        fn = "textures/" + os.path.splitext(n)[0].lower() + ".png"
        img.save(os.path.join(OUT, fn))
        tex[n] = (fn, img)

    def parents(i):
        out = []
        while F[i]["parent"]:
            i = F[i]["parent"] - 1
            out.append(F[i]["name"])
        return out

    frames_out, elements = [], []
    for i, fr in enumerate(F):
        par = parents(i)
        e = {"index": i, "name": fr["name"], "type": {1: "visual", 6: "dummy"}.get(fr["type"], fr["type"]),
             "parent": F[fr["parent"] - 1]["name"] if fr["parent"] else None,
             "world_pos": [round(v, 5) for v in U.xform(W[i], [0, 0, 0])]}
        if fr.get("lods"):
            lod = fr["lods"][0]
            ws = [U.xform(W[i], v[:3]) for v in lod["vertices"]]
            xs = [p[0] for p in ws]; ys = [-p[1] / SCREEN_H for p in ws]; zs = [p[2] for p in ws]
            rect = [min(xs), min(ys), max(xs), max(ys)]
            e["rect"] = [round(v, 5) for v in rect]
            e["z"] = round(sum(zs) / len(zs), 5)
            e["groups"] = []
            for g in lod["groups"]:
                mi = g["material"]
                mt = mats[mi - 1] if mi else None
                vids = sorted(set(g["faces"]))
                us = [lod["vertices"][k][6] for k in vids]; vs = [lod["vertices"][k][7] for k in vids]
                gi = {"material": mi, "flags": hex(mt["flags"]) if mt else None,
                      "texture": (mt["diffuse_map"] or None) if mt else None,
                      "uv": [round(min(us), 4), round(min(vs), 4), round(max(us), 4), round(max(vs), 4)],
                      "triangles": len(g["faces"]) // 3}
                if mt and not mt["diffuse_map"]:
                    gi["color"] = [round(c, 3) for c in mt["diffuse"][:3]]
                t = tex.get((gi["texture"] or "").upper())
                if t:
                    gi["texture_file"] = t[0]
                    w, h = t[1].size
                    gi["uv_px"] = [round(gi["uv"][0] * w), round(gi["uv"][1] * h), round(gi["uv"][2] * w), round(gi["uv"][3] * h)]
                e["groups"].append(gi)
            e["onscreen"] = rect[2] > 0.001 and rect[0] < 0.999 and rect[3] > 0.001 and rect[1] < 0.999
        elif fr["type"] == 6:
            e["box"] = [fr["min"], fr["max"]]
        frames_out.append(e)

        grp, purpose, conf, note = classify(fr["name"], par)
        if "rect" not in e:
            continue
        main_g = max(e["groups"], key=lambda g: g["triangles"])
        el = {"name": fr["name"], "group": grp, "purpose": purpose, "parent": e["parent"],
              "texture": main_g.get("texture_file") or main_g.get("texture"),
              "textures": sorted(set(g.get("texture_file") or "color" for g in e["groups"])),
              "uv_px": main_g.get("uv_px"), "rect": e["rect"], "z": e["z"], "anchor": anchor_of(e["rect"]),
              "onscreen_in_file": e["onscreen"], "confidence": conf, "notes": note}
        rp = [p for p in [fr["name"]] + par if p in moved]
        if rp:
            el["runtime_positioned"] = True
            el["notes"] = (note + "; " if note else "") + "Position zur Laufzeit gesetzt: " + RUNTIME_POS[rp[0]][1]
        elif not e["onscreen"]:
            el["notes"] = (note + "; " if note else "") + "liegt im Modell außerhalb des Bildes (Vorlage oder zur Laufzeit verschoben)"
        # Ausschnitt
        t = tex.get((main_g.get("texture") or "").upper())
        if t and main_g.get("uv_px"):
            x0, y0, x1, y1 = main_g["uv_px"]
            if x1 > x0 and y1 > y0 and 0 <= x0 and x1 <= t[1].size[0] and 0 <= y0 and y1 <= t[1].size[1]:
                crop = t[1].crop((x0, y0, x1, y1))
                cfn = "crops/%s.png" % re.sub(r"[^A-Za-z0-9_~-]", "_", fr["name"])
                crop.save(os.path.join(OUT, cfn))
                el["crop"] = cfn
        elements.append(el)

    spec = {
        "source": "MODELS\\gameinterface.4ds (Models.dta, HD2 v1.12)",
        "screen_mapping": {
            "model_space": "x 0..1 (links->rechts), y 0..-0.75 (oben->unten), z = Tiefe (kleiner = vorne)",
            "normalized": "rect = [x0, y0, x1, y1], x = model_x, y = -model_y / 0.75, (0,0) oben links",
            "aspect": "4:3 (Modellhöhe 0.75 bei Breite 1.0)",
            "camera": "eigene Interface-Kamera, Pos (0.5, -0.375, -15.5), Blick +z; vermutlich orthografisch (Skala 2.0)",
            "quaternions": "konjugiert angewendet (wie convert_mission.crot_xyzw)",
        },
        "default_hud_groups": sorted(DEFAULT_HUD_GROUPS),
        "groups": sorted(set(e["group"] for e in elements)),
        "elements": elements,
        "runtime_textures": {
            "portraits": "faces/x_f_*.png (64x64); hd2.exe nennt zusätzlich x_fc_death.bmp (gefallen) und x_fc_a.bmp",
            "inventory_icons": "inventory/ii_*.png (64x32) für i_hands, i_shoulder, select_weapon0x, Inventarplätze",
            "action_icons": "Texturen der Vorlagen action00..37 (I_*.BMP)",
            "state_icons": "Texturen playerstate1_00..19 / playerstate2_00..39 für mind*/command*",
        },
    }
    json.dump(spec, open(os.path.join(OUT, "hud_spec.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    json.dump({"frames": frames_out}, open(os.path.join(OUT, "hud_frames.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    render(elements, tex, F, W, mats, lambda e: e["group"] in DEFAULT_HUD_GROUPS and e["onscreen_in_file"]
           and not re.fullmatch(PREVIEW_HIDDEN, e["name"]), os.path.join(OUT, "hud_preview.png"))
    render(elements, tex, F, W, mats, lambda e: e["onscreen_in_file"] and e["group"] not in ("multiplayer",),
           os.path.join(OUT, "hud_preview_all.png"), skip_overlays=False)
    print("Elemente:", len(elements), "Frames:", len(frames_out), "->", OUT)


def render(elements, tex, F, W, mats, pick, path, skip_overlays=True, size=(1024, 768)):
    """Texturierte Dreiecke je Element (affin pro Dreieck), Maler-Reihenfolge nach z."""
    Wd, Hd = size
    canvas = Image.new("RGBA", size, (70, 80, 70, 255))
    dr = ImageDraw.Draw(canvas)
    # Hintergrund-Raster als Szene-Ersatz
    for k in range(0, Wd, 64):
        dr.line([(k, 0), (k, Hd)], fill=(80, 92, 80, 255))
    for k in range(0, Hd, 64):
        dr.line([(0, k), (Wd, k)], fill=(80, 92, 80, 255))
    byname = {f["name"]: i for i, f in enumerate(F)}
    sel = [e for e in elements if pick(e)]
    if skip_overlays:
        sel = [e for e in sel if e["group"] != "overlay"]
    for e in sorted(sel, key=lambda e: -e["z"]):
        i = byname[e["name"]]
        lod = F[i]["lods"][0]
        ws = [U.xform(W[i], v[:3]) for v in lod["vertices"]]
        pts = [(p[0] * Wd, -p[1] / SCREEN_H * Hd) for p in ws]
        for g in lod["groups"]:
            mi = g["material"]
            mt = mats[mi - 1] if mi else None
            fc = g["faces"]
            for t in range(0, len(fc), 3):
                tri = fc[t:t + 3]
                draw_tri(canvas, [pts[k] for k in tri], [lod["vertices"][k][6:8] for k in tri], tex, mt)
    canvas.convert("RGB").save(path)


def draw_tri(canvas, P, UV, tex, mt):
    xs = [p[0] for p in P]; ys = [p[1] for p in P]
    x0, x1 = int(max(0, min(xs))), int(min(canvas.size[0] - 1, max(xs) + 1))
    y0, y1 = int(max(0, min(ys))), int(min(canvas.size[1] - 1, max(ys) + 1))
    if x1 < x0 or y1 < y0:
        return
    (ax, ay), (bx, by), (cx, cy) = P
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9:
        return
    t = tex.get(((mt or {}).get("diffuse_map") or "").upper()) if mt else None
    if t:
        img = t[1]
        src = img.load()
        tw, th = img.size
        alpha = img.mode == "RGBA"
    else:
        col = tuple(int(255 * c) for c in (mt["diffuse"][:3] if mt else (1, 1, 1)))
    dst = canvas.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px, py = x + 0.5, y + 0.5
            l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
            l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
            l3 = 1 - l1 - l2
            if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
                continue
            if not t:
                dst[x, y] = col + (255,)
                continue
            u = l1 * UV[0][0] + l2 * UV[1][0] + l3 * UV[2][0]
            v = l1 * UV[0][1] + l2 * UV[1][1] + l3 * UV[2][1]
            sx = int(u * tw) % tw
            sy = int(v * th) % th
            c = src[sx, sy]
            if alpha:
                a = c[3] / 255.0
                if a <= 0:
                    continue
                d = dst[x, y]
                dst[x, y] = (int(c[0] * a + d[0] * (1 - a)), int(c[1] * a + d[1] * (1 - a)), int(c[2] * a + d[2] * (1 - a)), 255)
            else:
                dst[x, y] = c[:3] + (255,)


if __name__ == "__main__":
    main()
