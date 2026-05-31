extends Node

# Calendrier Kin Maya (Tzolkin 260 jours) — portage de calcKin() depuis atomic.html
# Usage : Kin_Maya.calc_kin(year, month, day) -> Dictionary
#         Kin_Maya.calc_kin_unix(unix_time)   -> Dictionary

const KIN_GLYPHS    := ["Imix","Ik","Akbal","Kan","Chicchan","Cimi","Manik","Lamat",
    "Muluc","Oc","Chuen","Eb","Ben","Ix","Men","Cib","Caban","Etznab","Cauac","Ahau"]
const KIN_GLYPHS_FR := ["Dragon","Vent","Nuit","Graine","Serpent","Lieur","Main","Étoile",
    "Lune","Chien","Singe","Chemin","Roseau","Jaguar","Aigle","Guerrier","Terre","Miroir",
    "Tempête","Soleil"]
const KIN_TONES     := ["Magnétique","Lunaire","Électrique","Auto-existante","Harmonique",
    "Rythmique","Résonnante","Galactique","Solaire","Planétaire","Spectrale","Cristal","Cosmique"]
const KIN_COLORS    := ["🔴 Rouge","⚪ Blanc","🔵 Bleu","🟡 Jaune","🟢 Vert"]
const KIN_MESES     := [0,31,59,90,120,151,181,212,243,13,44,74]
const KIN_SUMA      := {30:2,35:7,40:12,45:17,50:22,3:27,8:32,13:37,18:42,23:47,28:52,
    32:57,38:62,42:67,48:72,1:76,6:82,11:87,16:92,21:97,26:102,31:107,36:112,41:117,
    46:122,51:127,4:132,9:137,14:142,19:147,24:152,29:157,34:162,39:167,44:172,49:177,
    2:182,7:187,12:192,17:197,22:202,27:207,37:217,47:227,0:232,5:237,10:242,15:247,
    20:252,25:257}

func calc_kin(year: int, month: int, day: int) -> Dictionary:
    if month < 1 or month > 12 or day < 1: return {}
    var kin: int = day + int(KIN_MESES[month - 1]) + int(KIN_SUMA.get(year % 52, 0))
    if kin > 260: kin -= 260
    if kin <= 0:  kin += 260
    var gi: int = (kin - 1) % 20
    var ti: int = (kin - 1) % 13
    var ci: int = int((kin - 1) / 13) % 5
    return {
        "kin": kin, "gi": gi, "ti": ti, "ci": ci,
        "glyph": KIN_GLYPHS[gi], "glyph_fr": KIN_GLYPHS_FR[gi],
        "tone": KIN_TONES[ti], "color": KIN_COLORS[ci]
    }

func calc_kin_unix(unix_time: int) -> Dictionary:
    if unix_time <= 0: return {}
    var dt := Time.get_datetime_dict_from_unix_time(unix_time)
    return calc_kin(dt.year, dt.month, dt.day)

func kin_color_rgb(color_str: String) -> Color:
    if color_str.contains("Rouge"): return Color(1.0, 0.27, 0.20)
    if color_str.contains("Blanc"): return Color(0.82, 0.82, 0.94)
    if color_str.contains("Bleu"):  return Color(0.24, 0.51, 1.0)
    if color_str.contains("Jaune"): return Color(1.0, 0.76, 0.16)
    if color_str.contains("Vert"):  return Color(0.20, 0.82, 0.39)
    return Color(0.0, 1.0, 0.8)

func format_kin_short(k: Dictionary) -> String:
    if k.is_empty(): return "Kin Maya : date invalide"
    return "%s KIN %d · %s %s" % [k["color"], k["kin"], k["tone"], k["glyph_fr"]]
