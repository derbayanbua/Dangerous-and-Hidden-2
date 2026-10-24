"""Erzeugt orig_cache/ui/menu/menu_spec.json aus den Layout-Dateien (_menu_export.py) und den
im hd2.exe (v1.12) belegten Frame->Text-ID-Zuordnungen (Disassemblierung, siehe docs/re_notes_menu.md)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import convert_mission as cm

OUT = os.path.join(cm.CACHE, "ui", "menu")
T = json.load(open(os.path.join(cm.CACHE, "texts_german.json"), encoding="utf-8"))


def de(i):
    return T.get(str(i)) if i is not None else None


def lay(m):
    return json.load(open(os.path.join(OUT, "layout", m + ".json"), encoding="utf-8"))


def frame_rect(L, name):
    for f in L["frames"]:
        if f["name"] == name and f.get("rect_norm"):
            return f
    return None


def button(L, dummy):
    """Normal-/Aktiv-Quad eines Button-Dummys (Kinder normalNN / activedNN)."""
    kids = [f for f in L["frames"] if f.get("parent") == dummy and f.get("rect_norm")]
    nrm = [k for k in kids if k["name"].startswith("normal")]
    act = [k for k in kids if k["name"].startswith("actived")]
    out = {}
    if nrm:
        n = nrm[0]
        out["rect_norm"] = n["rect_norm"]; out["rect_px_1024x768"] = n["rect_px"]
        out["normal"] = {"frame": n["name"], "texture": n["groups"][0]["texture"], "uv_rect": n["groups"][0]["uv_rect"]}
    if act:
        a = act[0]
        out["hover"] = {"frame": a["name"], "texture": a["groups"][0]["texture"], "uv_rect": a["groups"][0]["uv_rect"],
                        "rest_rect_px": a["rect_px"], "note": "liegt im Modell ausserhalb des Bildes (rechts/links versetzt)"}
    return out


def entry(L, frame, tid, kind="button", target=None, notes=None, conf="B"):
    e = {"id": frame, "kind": kind, "label_text_id": tid, "label_de": de(tid), "label_confidence": conf}
    if kind == "button":
        e.update(button(L, frame))
    else:
        f = frame_rect(L, frame)
        if f:
            e["rect_norm"] = f["rect_norm"]; e["rect_px_1024x768"] = f["rect_px"]
    if target:
        e["submenu"] = target
    if notes:
        e["notes"] = notes
    return e


def menu(m, title_tid, items, extra=None, music=None):
    L = lay(m)
    d = {"model": L["model"], "title_frame": "text_screen", "title_text_id": title_tid, "title_de": de(title_tid),
         "background": "backgrounds/%s.png" % m if L["background_tiles"] else None,
         "background_tiles": [t["texture"] for t in L["background_tiles"]],
         "preview": "previews/%s.png" % m, "layout_file": "layout/%s.json" % m,
         "items": [entry(L, *it) if isinstance(it, tuple) else it for it in items]}
    if extra:
        d.update(extra)
    return d


V = ("text_h&dversion", 2006, "text", None, "Versionszeile; Formatstring")

spec = {
    "source": "Hidden & Dangerous 2 v1.12 (hd2.exe + patch.dta/MODELS.DTA/Maps.dta/Sounds.dta/others.DTA), Installation des Nutzers",
    "confidence_legend": {"B": "belegt (Code/Daten direkt gelesen)", "P": "wahrscheinlich (aus Namen/Struktur abgeleitet)",
                          "?": "offen/Vermutung"},
    "screen": {"reference_resolution": [1024, 768], "aspect": "4:3",
               "mapping": "Menue-4DS liegt in der Ebene z~0: x 0..1 = links..rechts, y 0..-0.75 = oben..unten; px = x*1024, py = -y*1024. "
                          "Frame-Quaternionen werden konjugiert angewendet (wie Missionsmodelle). Hintergrund 'menu1' z=-0.0001, "
                          "Buttons z=-0.0675, Texte bis z=-0.10 (kleineres z = naeher an der Kamera).",
               "camera": "[P] orthografisch/2D-artig: alle Elemente sind achsparallele Quads in einer Ebene; keine Kamera im Modell. "
                         "Fuer Godot: 2D-Control-Szene 1024x768 (Stretch keep 4:3) genuegt.",
               "cursor": {"model": "MODELS\\kurzor_menu.4ds", "frame": "Rectangle02", "texture": "textures/x_kursor.png",
                          "size_px_1024x768": [30, 30], "hotspot": "[P] oben links (Quad x -0.002..0.027, y 0.001..-0.028)",
                          "evidence": "hd2.exe: 'kurzor_menu' + 'CURZOR' bei 0x66c63d/0x66c642"}},
    "startup_sequence": {"order": ["Logo1.bik", "Logo2.bik", "Logo3.bik", "Intro.bik", "main_menu"],
                         "confidence": "B fuer die Aufrufreihenfolge in hd2.exe 0x6c2551..0x6c25a7; Ueberspringbedingungen ?",
                         "files": "HD2_orig\\Gamemovie\\*.bik (nicht exportiert, Bink)"},
    "menu_registry": {
        "order": ["main_menu 'MAIN MENU'", "change_profile 'CHANGE PROFIL'", "singleplayer 'SINGLEPLAYER'", "confirm 'CONFIRM'",
                  "single mission 2 'SINGLE MISSION 2'", "options 'OPTIONS'", "single mission 2 (Kinofilme/Cinematics)",
                  "multiplayer menu", "create server", "password 'PASSWORD'", "server filters 'Server Filters'",
                  "gameinfo 'Game info'", "confirm 'MP Connect console'", "password 'ADD SERVER'"],
        "evidence": "hd2.exe Menue-Aufbau 0x623dd0..0x625d1c (Paare Modellname/Titel an 0x625e80/0x626180); Menue-ID = (Index+1)<<26, Item-ID = Menue-ID | (Item-Nr<<20)",
        "confidence": "B"},
    "menus": {},
    "audio": {
        "music": {"table": "TABLES\\IngameSounds.def (others.DTA), Kategorie 12 (Musik), Index = PlayMusic(n)",
                  "main_menu": {"group_index": 0, "group_name": "Main Menu",
                                "variants": [{"file": "audio/main menu.ogg", "cumulative_probability": 50},
                                             {"file": "audio/main menu 2.ogg", "cumulative_probability": 100}],
                                "note": "Zufallswahl 50/50 (kumulative Wahrscheinlichkeit 0x0582) [B Tabelle]; dass das Hauptmenue Gruppe 0 spielt: [P] (Name)"},
                  "success_menu": {"group_index": 1, "file": "audio/success menu.ogg", "note": "[P] Nachbesprechung nach Erfolg"},
                  "fail_menu": {"group_index": 2, "file": "audio/fail menu.ogg", "note": "[P] Nachbesprechung nach Misserfolg"},
                  "credits": {"group_index": 37, "group_name": "Credits", "file": "audio/credits.ogg"}},
        "sounds": {"menu_button": {"table_category": 10, "category_name": "Interface & Menu", "group": "Menu Button",
                                   "file": "audio/button.wav", "source": "SOUNDS\\button.wav (Sounds.dta)",
                                   "params_raw": {"0x05aa": 1.0, "0x05be": 0.5},
                                   "note": "einziger Eintrag der Kategorie 'Interface & Menu' [B]; ob bei Klick oder Hover: [?]; 0x05be=0.5 evtl. Lautstaerke [?]"}}},
    "credits": {"text": "HD2_orig\\Text\\german\\Subtitles\\credits.txt (Steuercodes <SPEED>, <SM>, <TI>, <NACZ>, <EL>, <ES>)",
                "music": "audio/credits.ogg", "video": "credits.bik wird in hd2.exe referenziert (0x6c24bf), liegt aber nicht in Gamemovie [B]",
                "confidence": "P (Rolltext + Musik)"},
}

# --- Hauptmenue -------------------------------------------------------------
spec["menus"]["main_menu"] = menu("main_menu", 2101, [
    ("text_date00", 2102, "text"), ("text_date01", None, "text", None, "Laufzeitwert: aktuelles Datum/Uhrzeit"),
    ("text_profile00", 2103, "text"), ("text_profile01", None, "text", None, "Profilname; ohne Profil Text 2020 'KEIN AKTUELLES PROFIL' [B 0x627605]"),
    ("text_last save00", 2104, "text"), ("text_last save01", None, "text", None, "Spielstandinfo; ohne Spielstand Text 2021 [B 0x627649]"),
    ("bresume game", 2105, "button", "letzter Spielstand laden [P]", "ohne Profil/Spielstand gesperrt (Eigenschaft 0x1000001/0x1000002) [B Code, Semantik P]"),
    ("bchange profile", 2106, "button", "change_profile", "ohne Profil Beschriftung 2117 'PROFIL ERSTELLEN' [B 0x6276da]"),
    ("bsingleplayer", 2107, "button", "singleplayer"),
    ("bmultiplayerlan", 2115, "button", "multiplayer menu (LAN) [P]"),
    ("bmultiplayernet", 2116, "button", "multiplayer menu (Internet) [P]"),
    ("bcinematics", 2109, "button", "cinematics (Modell single mission 2.4ds) [P]"),
    ("boptions", 2110, "button", "options"),
    ("bcredits", 2111, "button", "credits (Rolltext) [P]"),
    ("bexit", 2112, "button", "Spiel beenden [P]"),
    V], extra={"music": "audio.music.main_menu",
               "notes": ["Reihenfolge von oben nach unten laut Modell-y (Abstand 39,4 px): WEITER SPIELEN, PROFIL AENDERN, EINZELSPIELER-SPIEL, "
                         "MEHRSPIELER LAN, MEHRSPIELER INTERNET, FILME, EINSTELLUNGEN, MITWIRKENDE, ENDE [B]",
                         "Ohne Profil setzt der Show-Handler 0x627520 die Buttons 0x48,0x4a..0x4f auf Eigenschaft 0x1000001=0 (vermutl. gesperrt) [B Code / P Semantik]",
                         "Text-ID 2108 fehlt in TEXTY.txt (Luecke) [B]",
                         "Button 'bexit' normal07 nutzt im Modell dasselbe Material wie actived (Mat 3) und ist 3,5 px hoeher [B, vermutl. Datenfehler]"]})

# --- Profil ----------------------------------------------------------------
spec["menus"]["change_profile"] = menu("change_profile", 2151, [
    ("text_current profile and save", 2191, "text"), ("bcurrent profile", None, "button", None, "zeigt aktuellen Profilnamen (Textur X_NMNBTW = helle Variante)"),
    ("text_date and time", None, "text"), ("text_list of profiles", 2192, "text"),
    {"id": "LB_Profiles", "kind": "listbox", "notes": "Profil-Liste mit Scrollbar (scroll00, barrow up/down, slider)"},
    ("text_difficulty", 2193, "text"),
    ("beasy-war never was so fun!", 2157, "button", None, "Code sucht 'beasy-*' (Wildcard)"),
    ("bnormal-loosing illusions!", 2158, "button"), ("bhard-cannon fodder!", 2159, "button"),
    ("bvery hard-hidden and dangerous", 2160, "button"),
    ("text01", None, "text", None, "Profil-Info (Texte 2163-2190) [P]"),
    ("bcreate profile", 2152, "button", "Eingabe Profilname [P]"),
    ("brename profile", 2154, "button"), ("bdelete profile", 2155, "button", "confirm [P]"),
    ("bback", 2156, "button", "main_menu"), V],
    extra={"notes": ["2153 'ALLE PROFILE LOESCHEN' wird im Code nicht verwendet [B]",
                     "Hintergrund nutzt Kachelvarianten X_NMN01P/02P [B]"]})

# --- Einzelspieler -----------------------------------------------------------
spec["menus"]["singleplayer"] = menu("singleplayer", 2201, [
    ("text_HD2original", 20400, "text", None, "Ueberschrift (TEXTY_DD)"),
    ("bcampaign", 2202, "button", "Kampagnenwahl (Befehl 0x6001033, Modus 1) [B Code / P Ziel]"),
    ("blone wolf", 2203, "button", "Kampagnenwahl Einzelgaenger (0x6001033, Modus 2)"),
    ("carnage", 2204, "button", "Kampagnenwahl Blutbad (0x6001033)"),
    ("text_HD2datadisk", 20401, "text", None, "Ueberschrift Sabre Squadron; Datadisk-Missionen sind in dieser Installation NICHT vorhanden"),
    ("bcampaign01", 2205, "button", "Einzelmission (Befehl 0x6001074) [B Code]", "Code setzt 2205 auf diesen Frame, obwohl er im Patch-Modell unter der SS-Ueberschrift liegt -> Laufzeitbild [?]"),
    ("blone wolf01", 2206, "button", "Einzelmission Blutbad (0x6001074)", "s. o. [?]"),
    ("carnage01", None, "button", None, "kein Text; Eigenschaft 0x1000004=0 [B]"),
    ("bsingle mission", None, "button", None, "kein Text; 0x1000004=0; Klick setzt Flag +0xE8=1 und 0x6001033 [B Code]"),
    ("bsingle mission- carnage", None, "button", None, "wie oben"),
    ("bback", 2208, "button", "main_menu"),
    ("text00", 2210, "text", None, "Beschreibungsfeld: Kopf 2210 + bei Hover 2211..2215 [B Hover-Handler 0x63b740]"),
    {"id": "single side", "kind": "image_switch", "notes": "Bild links oben 512x512 px, wechselt bei Hover: ss1 X_SI_CMP (Kampagne), ss2 X_SI_LNW (Einzelgaenger), "
                                                              "ss3 X_SI_CRN (Blutbad), ss4 X_SI_SIM (Einzelmission), ss5 X_SI_SIC (Einzelm.-Blutbad); ss6-8 *_D.BMP fehlen in den Archiven [B]",
     "rect_px_1024x768": [0, 0, 512, 512]},
    V], extra={"notes": ["Original-Modell (MODELS.DTA) hatte nur 5 Buttons: Kampagne, Einzelgaenger, Blutbad, Einzelmission, Einzelmission-Blutbad (+Zurueck); "
                         "der Patch (patch.dta) ergaenzt Ueberschriften und bcampaign01/blone wolf01/carnage01 [B]",
                         "2207 'EINSTELLUNGEN' wird nicht verwendet [B]"]})

# --- Einzelmission / Kampagnenwahl & Filme ------------------------------------
spec["menus"]["single_mission"] = menu("single mission 2", 2251, [
    ("text_list of profiles", 2258, "text", None, "'Missions-Liste:'"),
    {"id": "GB_Campaign / GB_SingleMission", "kind": "listbox", "notes": "Kampagnen- bzw. Missionsliste (Campaign%02d, Mission%02d, SMMission%02d)"},
    ("screen_shot", None, "image", None, "Vorschaubild rechts oben (Beispieltextur E_I_FRE.BMP)"),
    ("video", None, "text", None, "Video-/Bildfeld"), ("text00", None, "text", None, "Missionsbeschreibung"),
    ("bload mission", 2357, "button", "Mission starten [P]"), ("bload lastsave", 2105, "button", "letzten Spielstand fortsetzen [P]"),
    ("bexit", 2256, "button", "singleplayer"), ("bexit01", 2256, "button", None, "zweiter Zurueck-Button (Builder 0x6399fd)"), V],
    extra={"evidence": "Builder 0x639200..0x639a49 [B]"})
spec["menus"]["cinematics"] = menu("single mission 2", 2109, [
    ("text_list of profiles", 159, "text", None, "'Filme:'"),
    {"id": "GB_Cinematics", "kind": "listbox", "notes": "Eintraege Anim%02d; Filmtitel Texte 160-169, 189 [P]"},
    ("screen_shot", None, "image"), ("video", None, "text"),
    ("bexit01", 2264, "button", "Film abspielen"), ("bexit", 2256, "button", "main_menu"), V],
    extra={"evidence": "Builder 0x614150..0x614d90 [B]; gleiches Modell wie Einzelmission, zweite Registrierung"})

# --- Einstellungen -----------------------------------------------------------
spec["menus"]["options"] = menu("options", 2401, [
    ("text_date00", 2402, "text"), ("text_date01", 2403, "text"), ("text_profile00", 2404, "text"),
    ("bvideo setup", 2405, "button", "Seite graphics setup"), ("bsound setup", 2406, "button", "Seite sound setup"),
    ("bcontrols", 2407, "button", "Seite keysscreen (Steuerung)"), ("bgame setup", 2408, "button", "Seite gameoptions"),
    ("bmultiplayer setup", 2409, "button", "Seite network settings"), ("bback", 2410, "button", "main_menu"), V],
    extra={"pages": {
        "graphics setup": {"texts": {"text_graphics setup": 2411, "text_gama correction": 2412, "text_min norm max02": [2030, 2031, 2032],
                                     "geometry detail": [2414, 2415, 2416, 2417], "GD00": 2418, "GD01": 2419, "GD02": 2420, "GD03": 2421,
                                     "GD04": 2422, "GD05": 2423, "GD06": 2424, "text_modifications": 2430},
                           "controls": ["scrollbar03 (Gamma)", "geometry detail (Umschalter)", "GD00..GD06 (Ja/Nein)"]},
        "sound setup": {"texts": {"text_sound setup": 2425, "text_sound volume": 2426, "text_music volume": 2428,
                                  "text_min norm max": [2030, 2031, 2032], "text_min norm max01": [2030, 2031, 2032]},
                        "controls": ["scrollbar01 (Sound)", "scrollbar02 (Musik)"]},
        "keysscreen": {"texts": {"text_controls setup": 2441, "bcontrols01": 2442, "text_mouse setup": 2443, "invert mouse": 2444,
                                 "text_mouse sensitivity": 2445, "text_minimal normal maximal": [2030, 2031, 2032],
                                 "text_joystick setup": 2447, "bcalibrate": 2448, "force feedback": 2449, "lock fire": 2450},
                       "subpage keysscreen01": {"text_last save01": 2451, "controls": [2452, 2453, 2454, 2455, 2456],
                                                "groups": ["GR_Movements", "GR_Weapons", "GR_Other", "GR_Selections", "GR_Tactical"],
                                                "bdefault*": 2457, "bback01": 2459}},
        "gameoptions": {"texts": {"text_game options": 2461, "subtitles": 2462, "parental lock": 20212},
                        "notes": "v1.12 beschriftet das Element 'parental lock' mit 20212 'FADENKREUZ ZULASSEN' statt 2463 [B 0x61f2f8]"},
        "network settings": {"texts": {"text_network setup": 2473, "text_voice-chat settings": 2433, "enable voice-chat": 2431,
                                       "text_voice-chat volume": 2432, "text_min norm max020": [2030, 2031, 2032]},
                             "controls": ["connection (Verbindungsgeschwindigkeit, Texte 2875-2879 [P])", "scrollbar04"]}},
        "evidence": "Builder 0x61cf80..0x61f591 [B]; alle Seiten liegen im Modell uebereinander auf der linken Buchseite (Gruppe GROptions)",
        "notes": ["Hintergrund nutzt Varianten X_NMN08O/11O/12O (Messer/Patronen rechts unten) [B]"]})

# --- Mehrspieler ---------------------------------------------------------------
spec["menus"]["multiplayer"] = menu("multiplayer menu", 2301, [
    ("bhost name", 2302, "button", None, "Spaltenkopf (Sortierung) [P]"), ("bmap", 2303, "button"), ("bstyle", 2304, "button"),
    ("bping", 2305, "button"), ("bplayers/max", 2306, "button"),
    {"id": "GB_ServerList", "kind": "listbox", "notes": "Zeilen 'sever00'/Server%d mit Symbolen xpassword/xdedicated/xvoice (X_MPICON/X_MPICOB)"},
    ("brestore list", 2325, "button"), ("brefresh list", 2327, "button"), ("bfavorites", 20100, "button"),
    ("benter server ip", 2308, "button", "password 'ADD SERVER' [P]"), ("badd/remove", 20102, "button"),
    ("bserver filters", 2309, "button", "server filters"), ("bjoin game", 2310, "button", "MP Connect console [P]"),
    ("bcreate server", 2311, "button", "create server"), ("bview game info", 2312, "button", "gameinfo"),
    ("bback", 2313, "button", "main_menu"), ("gamespylogo", None, "image", None, "X_ARCADE.TGA (GameSpy-Logo)"),
    ("esrb-US", None, "image", None, "X_ESRB.BMP"), ("text_online", 2006, "text"), V],
    extra={"notes": ["LAN und Internet nutzen dasselbe Menue; Titel 2320/2321 werden nicht direkt im Code gepusht [?]"],
           "evidence": "Builder 0x633f80..0x634470 [B]"})
spec["menus"]["create_server"] = menu("create server", 2351, [
    ("text_hostname and style", 2352, "text"), ("text_available maps checklist", 2354, "text"), ("text_server options", 2355, "text"),
    ("text_voice chat", 2375, "text"), ("text_server type", 2380, "text"), ("text_maplist preset", 20205, "text"), ("text_maplist", 20206, "text"),
    ("bstart", 2357, "button"), ("bback", 2358, "button", "multiplayer menu"), V],
    extra={"server_rules_texts": [2364, 2365, 2366, 2367, 2368, 2370, 2369, 2376, 2377, 2371, 2372, 2373, 20212, 2374, 2378, 20210, 20211, 20213],
           "server_type_texts": [2381, 2382], "maplist_preset_texts": [20200, 20201, 20202, 20203, 20204],
           "evidence": "Builder 0x628578..0x62c106 [B]"})
spec["menus"]["server_filters"] = menu("server filters", 2551, [
    ("text_show servers", 2552, "text"), ("text_scan style", 2554, "text"), ("bshort00", 2555, "button"),
    ("responding only", 2560, "checkbox"), ("dedicated only", 2561, "checkbox"), ("that are not empty", 2562, "checkbox"),
    ("that are not full", 2563, "checkbox"), ("without password", 2564, "checkbox"), ("current version", 2579, "checkbox"),
    ("baccept", 2556, "button", "multiplayer menu"), ("bback", 2557, "button", "multiplayer menu"), V],
    extra={"notes": ["Titel nutzt 2551 'SPIELER-SETUP' (TEXTY-Fehler im Original) [B 0x6387a5]"]})
spec["menus"]["gameinfo"] = menu("gameinfo", 2568, [
    ("text_team status", 2569, "text"), ("text_", 2570, "text"), {"id": "LB_Players", "kind": "listbox", "notes": "Spalten 2593 Getoetet / 2594 Punkte"},
    ("brefresh status", 2565, "button"), ("bjoin game", 2566, "button"), ("breturn", 2567, "button", "multiplayer menu"), V])
spec["menus"]["confirm"] = {"model": "MODELS\\confirm.4ds", "items": [
    {"id": "text", "kind": "text", "label_text_id": 2004, "label_de": de(2004)},
    {"id": "byes*", "kind": "button", "label_text_id": 2001, "label_de": de(2001)},
    {"id": "bno*", "kind": "button", "label_text_id": 2000, "label_de": de(2000)},
    {"id": "bok", "kind": "button", "label_text_id": None}], "preview": "previews/confirm.png", "layout_file": "layout/confirm.json",
    "notes": "Dialog mit eigenem Rahmen (X_B_DNLF/DNMD/DNRG + Schatten X_NMSHD), Koordinaten im Modell relativ zum Ursprung -> Engine zentriert vermutlich [P]; Frames heissen im Modell byes?/bno? (Code sucht byes*/bno*); auch als 'MP Connect console' registriert [B]"}
spec["menus"]["password"] = {"model": "MODELS\\password.4ds", "preview": "previews/password.png", "layout_file": "layout/password.json",
                             "notes": "Eingabedialog (Passwort 2003 / IP 2022 [P]); auch 'ADD SERVER' [B Registrierung]"}

# Baum (Navigation)
spec["tree"] = {
    "main_menu": ["change_profile", "singleplayer", "multiplayer(LAN)", "multiplayer(Internet)", "cinematics", "options", "credits", "exit"],
    "singleplayer": ["single_mission (Kampagne/Einzelgaenger/Blutbad bzw. Einzelmission)", "main_menu"],
    "multiplayer": ["server_filters", "create_server", "gameinfo", "password(ADD SERVER)", "confirm(MP Connect console)", "main_menu"],
    "options": ["graphics setup", "sound setup", "keysscreen", "gameoptions", "network settings", "main_menu"],
    "confidence": "Button->Text: B; Button->Zielmenue: P (Namen/Registrierung), Handler-Dispatch nur fuer singleplayer gelesen"}

spec["textures"] = {
    "button_atlas": {"file": "textures/x_nmnbtn.png", "regions_uv": {"button_normal": [0.001, 0.001, 0.806, 0.281], "button_hover": [0.001, 0.282, 0.806, 0.559],
                     "arrow_normal": [0.81, 0.0, 0.87, 0.249], "arrow_hover": [0.81, 0.26, 0.87, 0.506], "arrow_inactive": [0.911, 0.002, 0.972, 0.249],
                     "slider_knob": [0.874, 0.003, 0.908, 0.247], "scroll_track": [0.0005, 0.0005, 0.5166, 0.2862]},
                     "note": "UV (u0,v0,u1,v1), v=0 oben; Buttongroesse 414x36 px @1024x768"},
    "button_atlas_light": "textures/x_nmnbtw.png (bcurrent profile)",
    "background_tiles": "4x3 Kacheln je 256x256 px (X_NMN01..12, Varianten M=Hauptmenue, P=Profil, G=Spielinfo, O=Optionen, D/I/T/MS weitere) -> backgrounds/*.png",
    "logos": ["textures/hd_logo.png (Ladebild-Logo [?])", "textures/x_b_logo.png", "textures/x_nmn04_logo.png", "textures/x_arcade.png (GameSpy)", "textures/x_esrb.png"],
    "fonts": "HD2_orig\\Text\\german\\Fonts\\Set1..3 (BIG/SMALL/SYMBOLS .tga/.tbl) – nicht exportiert; Schriftstil-Codes im Code: 0xa Titel, 0xb/0xc Info, 0xd Buttons, 0x28 Version [B Werte, P Bedeutung]"}

json.dump(spec, open(os.path.join(OUT, "menu_spec.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
missing = [ (m, it["id"]) for m, M in spec["menus"].items() for it in M.get("items", []) if it.get("kind") == "button" and "rect_norm" not in it]
print("ok; Buttons ohne Rechteck:", missing)
