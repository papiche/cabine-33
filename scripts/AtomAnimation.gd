extends Node2D

# Animation atomique — portage fidèle des 3 modes p5.js de atomic.html
# Calibration perf automatique sur 30 frames après 2s de chauffe.
# Compatible Web et APK (pur Godot _draw, aucune dépendance externe).

enum DrawMode  { PROFIL, MATCH, THEORIE }
enum PerfLevel { LOW, MED, HIGH }

# Couleurs dérivées du thème actif à chaque frame
func _col_accent() -> Color: return UI_Theme.accent_color()
func _col_warm()   -> Color: return UI_Theme.text_warm()
func _col_pos()    -> Color: return UI_Theme.text_positive()
func _col_text()   -> Color: return UI_Theme.text_color()

var mode         := DrawMode.PROFIL
var perf_level   := PerfLevel.MED
var resonance_k  := 0.5
var personal_phase := 0.0
var partner_phase  := 0.0
var kin_a: Dictionary = {}
var kin_b: Dictionary = {}

var _frame_time  := 0
var _calib_done  := false
var _calib_wait  := 0
var _fps_samples: Array[float] = []
var _mesh_v: Array[Dictionary] = []
var _mesh_e: Array[Array]      = []

# ─────────────────────────────────────────────────────────────
func _ready():
    z_index = -10
    _build_icosahedron()

func _process(_delta):
    _frame_time += 1
    # Calibration: attendre 120 frames puis mesurer 30 frames
    if not _calib_done:
        _calib_wait += 1
        if _calib_wait > 120:
            _fps_samples.append(Engine.get_frames_per_second())
            if _fps_samples.size() >= 30:
                var avg := 0.0
                for s in _fps_samples: avg += s
                avg /= 30.0
                if avg > 50.0:   perf_level = PerfLevel.HIGH
                elif avg > 28.0: perf_level = PerfLevel.MED
                else:            perf_level = PerfLevel.LOW
                _calib_done = true
    queue_redraw()

func _draw():
    var vp := get_viewport_rect().size
    match mode:
        DrawMode.PROFIL:  _draw_profil(vp)
        DrawMode.MATCH:   _draw_match(vp)
        DrawMode.THEORIE: _draw_theorie(vp)

# ─────────────────────────────────────────────────────────────
# MODE PROFIL — décompte 9→0, polygones rotatifs + glyphe Kin
# ─────────────────────────────────────────────────────────────
func _draw_profil(vp: Vector2):
    var cx := vp.x * 0.5; var cy := vp.y * 0.42
    var R: float = min(vp.x, vp.y) * 0.3
    var ft := _frame_time

    var SLOT  := 180 if perf_level == PerfLevel.LOW else (140 if perf_level == PerfLevel.MED else 110)
    var CYCLE := SLOT * 10
    var pos   := ft % CYCLE
    var digit := 9 - int(pos / SLOT)
    var phase := fmod(float(pos), float(SLOT)) / float(SLOT)
    var env   := phase / 0.12 if phase < 0.12 else (1.0 - phase) / 0.12 if phase > 0.88 else 1.0

    var kr := _col_accent()
    if not kin_a.is_empty(): kr = Kin_Maya.kin_color_rgb(kin_a.get("color", ""))

    if digit == 0:
        var burst := phase / 0.22 if phase < 0.22 else maxf(0.0, 1.0 - (phase - 0.22) / 0.78)
        draw_arc(Vector2(cx, cy), R * burst, 0, TAU, 48,
            Color(kr.r, kr.g, kr.b, 0.75 * burst), 2.0)
        var tc := _col_text()
        draw_arc(Vector2(cx, cy), R * 0.65 * burst, 0, TAU, 32,
            Color(tc.r, tc.g, tc.b, 0.31 * burst), 1.0)

    elif digit == 1:
        draw_circle(Vector2(cx, cy), 10.0, Color(kr.r, kr.g, kr.b, 0.78 * env))
        draw_arc(Vector2(cx, cy), R * 2.0 * phase, 0, TAU, 48,
            Color(kr.r, kr.g, kr.b, 0.63 * (1.0 - phase)), 1.5)

    elif digit == 2:
        var freq := 2.0 + 2.0 * phase
        var pts  := PackedVector2Array(); pts.resize(80)
        for i in range(80):
            var x2: float = -R + float(i) * R * 2.0 / 79.0
            pts[i] = Vector2(cx + x2, cy + sin((x2 / R * freq + phase * TAU * 2.0) * PI) * R * 0.3)
        draw_polyline(pts, Color(kr.r, kr.g, kr.b, 0.71 * env), 2.2)

    else:
        var rot := phase * TAU * (0.11 if digit % 2 == 0 else -0.11) + digit * 0.28
        var n_sides := digit
        var poly := PackedVector2Array(); poly.resize(n_sides + 1)
        for i in range(n_sides):
            var a := float(i) / float(n_sides) * TAU - PI * 0.5 + rot
            poly[i] = Vector2(cx + cos(a) * R, cy + sin(a) * R)
        poly[n_sides] = poly[0]  # fermer le polygone (draw_polyline ne ferme pas automatiquement)
        draw_polyline(poly, Color(kr.r, kr.g, kr.b, 0.73 * env), 2.5, true)

        if perf_level != PerfLevel.LOW:
            var skip := 2 if (perf_level == PerfLevel.MED and n_sides > 7) else 1
            for i in range(0, n_sides, skip):
                for j in range(i + 2, n_sides - (1 if i == 0 else 0)):
                    var ai := float(i) / float(n_sides) * TAU - PI * 0.5 + rot
                    var aj := float(j) / float(n_sides) * TAU - PI * 0.5 + rot
                    draw_line(Vector2(cx + cos(ai)*R, cy + sin(ai)*R),
                              Vector2(cx + cos(aj)*R, cy + sin(aj)*R),
                              Color(kr.r, kr.g, kr.b, 0.11 * env), 0.7)

        if perf_level == PerfLevel.HIGH:
            var orb: float = R * (0.52 + 0.07 * sin(phase * TAU * float(n_sides)))
            for i in range(n_sides):
                var a := float(i) / float(n_sides) * TAU - PI * 0.5 + phase * TAU * 0.5
                draw_circle(Vector2(cx + cos(a)*orb, cy + sin(a)*orb),
                            4.5, Color(kr.r, kr.g, kr.b, 0.37 * env))

    # Grand chiffre en overlay
    draw_string(ThemeDB.fallback_font, Vector2(cx - R * 0.22, cy + R * 0.32),
        str(digit), HORIZONTAL_ALIGNMENT_CENTER, -1, int(R * 0.72),
        Color(kr.r, kr.g, kr.b, 0.17 * env))

    # Nom Kin en dessous
    if not kin_a.is_empty():
        var kin_str: String = str(kin_a.get("glyph","")).to_upper() + " · " + str(kin_a.get("tone",""))
        draw_string(ThemeDB.fallback_font, Vector2(cx, cy + R * 1.35),
            kin_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
            Color(kr.r, kr.g, kr.b, 0.37))

# ─────────────────────────────────────────────────────────────
# MODE MATCH — deux ondes expansives + labels Kin
# ─────────────────────────────────────────────────────────────
func _draw_match(vp: Vector2):
    var cx := vp.x * 0.5; var cy := vp.y * 0.42
    var maxD: float = min(vp.x, vp.y) * 0.3
    var dist: float = maxD * (1.0 - resonance_k)

    var ca := _col_accent()
    var cb := _col_warm()
    if not kin_a.is_empty(): ca = Kin_Maya.kin_color_rgb(kin_a.get("color",""))
    if not kin_b.is_empty(): cb = Kin_Maya.kin_color_rgb(kin_b.get("color",""))

    _draw_wave(cx - dist, cy, ca, _frame_time * 2, maxD)
    _draw_wave(cx + dist, cy, cb, _frame_time * 2, maxD)

    if perf_level != PerfLevel.LOW:
        if not kin_a.is_empty():
            draw_string(ThemeDB.fallback_font, Vector2(cx - dist, cy - 22),
                str(kin_a.get("kin","")), HORIZONTAL_ALIGNMENT_CENTER, -1, 20,
                Color(ca.r, ca.g, ca.b, 0.73))
            if perf_level == PerfLevel.HIGH:
                draw_string(ThemeDB.fallback_font, Vector2(cx - dist, cy + 16),
                    str(kin_a.get("glyph","")).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, 9,
                    Color(ca.r, ca.g, ca.b, 0.45))
        if not kin_b.is_empty():
            draw_string(ThemeDB.fallback_font, Vector2(cx + dist, cy - 22),
                str(kin_b.get("kin","")), HORIZONTAL_ALIGNMENT_CENTER, -1, 20,
                Color(cb.r, cb.g, cb.b, 0.73))

    if resonance_k > 0.85:
        var t := _frame_time * 0.03
        var pr := 100.0 + sin(_frame_time * 0.1) * 10.0
        var poly := PackedVector2Array(); poly.resize(6)
        for i in range(5):
            var a := float(i) / 5.0 * TAU - PI * 0.5 + t
            poly[i] = Vector2(cx + cos(a)*pr, cy + sin(a)*pr)
        poly[5] = poly[0]
        var wc174 := _col_warm()
        draw_polyline(poly, Color(wc174.r, wc174.g, wc174.b, 1.0), 3.0, true)

func _draw_wave(nx: float, ny: float, col: Color, t: int, max_rad: float):
    draw_circle(Vector2(nx, ny), 4.5, Color(col.r, col.g, col.b, 0.69))
    var rings := 3 if perf_level == PerfLevel.LOW else (4 if perf_level == PerfLevel.MED else 6)
    for r in range(1, rings + 1):
        var wave := fmod(float(t + r * 60), max_rad)
        var alpha := lerpf(0.76, 0.0, wave / max_rad)
        draw_arc(Vector2(nx, ny), wave, 0, TAU, 36, Color(col.r, col.g, col.b, alpha), 1.5)

# ─────────────────────────────────────────────────────────────
# MODE THEORIE — icosaèdre + spirales Phi + atomes orbitants
# ─────────────────────────────────────────────────────────────
func _draw_theorie(vp: Vector2):
    var cx := vp.x * 0.5; var cy := vp.y * 0.42
    var radius: float = min(vp.x, vp.y) * 0.38
    const PHI  := 1.6180339
    var ax := _frame_time * 0.005
    var ay := _frame_time * 0.010
    var tN := _frame_time * 0.022

    var s_oct  := sin(tN * 2.0)
    var s_phi  := sin(tN * 2.0 * PHI)
    var interf := s_oct + s_phi
    var excite := maxf(0.0, (interf - 0.8) / 1.2)

    # Anneaux Octave
    var oct_rings := 3 if perf_level == PerfLevel.LOW else (5 if perf_level == PerfLevel.MED else 6)
    for k in range(oct_rings):
        var p := fmod(tN + float(k) / oct_rings, 1.0)
        var r: float = p * radius * 1.12
        var a := 0.35 * pow(1.0 - p, 2.0) * (1.0 + 0.3 * s_oct)
        var ac := _col_accent()
        draw_arc(Vector2(cx, cy), r, 0, TAU, 36,
            Color(ac.r, ac.g, ac.b, a), 0.9 + p * 0.5)

    if perf_level != PerfLevel.LOW:
        for k in range(4):
            var p := fmod(tN * 2.0 + float(k) / 4.0, 1.0)
            var wc := _col_warm()
            draw_arc(Vector2(cx, cy), p * radius * 0.82, 0, TAU, 28,
                Color(wc.r, wc.g, wc.b, 0.18 * (1.0 - p)), 0.5)

    # Spirales Phi (5 bras dorés)
    var phi_rot := tN * 0.14 * PHI
    var spiral_step := 0.14 if perf_level == PerfLevel.LOW else (0.09 if perf_level == PerfLevel.MED else 0.06)
    for arm in range(5):
        var base_a := (float(arm) / 5.0) * TAU + phi_rot
        var pts: Array[Vector2] = []
        var s := 0.0
        while s <= 5.8:
            var r2 := 9.0 * exp(0.306 * s)
            if r2 > radius: break
            pts.append(Vector2(cx + r2 * cos(base_a + s), cy + r2 * sin(base_a + s)))
            s += spiral_step
        if pts.size() >= 2:
            var pva := PackedVector2Array(pts)
            var wc231 := _col_warm()
            draw_polyline(pva, Color(wc231.r, wc231.g, wc231.b, 0.09 + 0.11 * excite), 1.0)

    # Maillage icosaèdre
    if _mesh_v.size() == 0: _build_icosahedron()
    var pulse_z := fmod(float(_frame_time), 300.0) / 300.0 * 4.0 - 2.0
    var proj: Array[Vector2] = []
    var pz: Array[float]     = []
    for v in _mesh_v:
        var y1: float = float(v.y) * cos(ax) - float(v.z) * sin(ax)
        var z1: float = float(v.y) * sin(ax) + float(v.z) * cos(ax)
        var x2: float = float(v.x) * cos(ay) + z1 * sin(ay)
        var z2: float = -float(v.x) * sin(ay) + z1 * cos(ay)
        var dp: float  = abs(y1 - pulse_z)
        var def: float = 1.0 + 0.4 * (0.4 - dp) * sin(float(_frame_time) * 0.2) if dp < 0.4 else 1.0
        var sc: float  = 3.0 / (3.0 + z2)
        proj.append(Vector2(cx + x2 * radius * sc * def, cy + y1 * radius * sc * def))
        pz.append(z2)

    var edge_step := 2 if perf_level == PerfLevel.LOW else 1
    for i in range(0, _mesh_e.size(), edge_step):
        var a: int = int(_mesh_e[i][0]); var b: int = int(_mesh_e[i][1])
        var alpha := 0.05 if (pz[a] > 0.0 and pz[b] > 0.0) else 0.24
        var ac253 := _col_accent()
        draw_line(proj[a], proj[b], Color(ac253.r, ac253.g, ac253.b, alpha * 0.55), 0.7)

    for i in range(_mesh_v.size()):
        var is_penta: bool = str(_mesh_v[i].get("type","")) == "pentagon"
        if is_penta:
            var a2 := 0.25 if pz[i] > 0.0 else (0.82 + 0.16 * excite)
            var wc259 := _col_warm()
            draw_circle(proj[i], 3.0 + 2.0 * excite, Color(wc259.r, wc259.g, wc259.b, a2))
        else:
            var a2 := 0.09 if pz[i] > 0.0 else 0.39
            var nc := _col_accent(); draw_circle(proj[i], 1.2, Color(nc.r, nc.g, nc.b, a2))

    # Atomes orbitants
    if perf_level != PerfLevel.LOW:
        var orb_r: float = radius * (1.0 - 0.45 * excite)
        var ca := _col_accent(); var cb := _col_warm()
        if not kin_a.is_empty(): ca = Kin_Maya.kin_color_rgb(kin_a.get("color",""))
        if not kin_b.is_empty(): cb = Kin_Maya.kin_color_rgb(kin_b.get("color",""))
        var ax_a := Vector2(cx + orb_r * cos(tN * 0.7), cy + orb_r * 0.4 * sin(tN * 0.7))
        var ax_b := Vector2(cx - orb_r * cos(tN * 0.7 + PHI), cy + orb_r * 0.4 * sin(tN * 0.7 + PHI))
        draw_circle(ax_a, 4.0 + 2.5 * excite, Color(ca.r, ca.g, ca.b, 0.71 + 0.16 * excite))
        draw_circle(ax_b, 4.0 + 2.5 * excite, Color(cb.r, cb.g, cb.b, 0.71 + 0.16 * excite))

        if perf_level == PerfLevel.HIGH and excite > 0.6:
            var wc276 := _col_warm()
            draw_line(ax_a, ax_b, Color(wc276.r, wc276.g, wc276.b, 0.47 * excite), 1.5)

# ─────────────────────────────────────────────────────────────
# ICOSAÈDRE — construction du maillage
# ─────────────────────────────────────────────────────────────
func _build_icosahedron():
    const PHI := 1.6180339
    var raw := [[-1,PHI,0],[1,PHI,0],[-1,-PHI,0],[1,-PHI,0],[0,-1,PHI],[0,1,PHI],
                [0,-1,-PHI],[0,1,-PHI],[PHI,0,-1],[PHI,0,1],[-PHI,0,-1],[-PHI,0,1]]
    _mesh_v.clear(); _mesh_e.clear()
    for v in raw:
        var mag := sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
        _mesh_v.append({"x": v[0]/mag, "y": v[1]/mag, "z": v[2]/mag, "type": "pentagon"})
    var edges: Array[Array] = []
    for i in range(12):
        for j in range(i+1, 12):
            var a: Dictionary = _mesh_v[i]; var b: Dictionary = _mesh_v[j]
            var d: float = sqrt(pow(float(a.x)-float(b.x),2)+pow(float(a.y)-float(b.y),2)+pow(float(a.z)-float(b.z),2))
            if d < 1.1: edges.append([i, j])
    for e in edges:
        var v1: Dictionary = _mesh_v[int(e[0])]; var v2: Dictionary = _mesh_v[int(e[1])]
        var mx: float = (float(v1.x)+float(v2.x))*0.5; var my: float = (float(v1.y)+float(v2.y))*0.5; var mz: float = (float(v1.z)+float(v2.z))*0.5
        var mag := sqrt(mx*mx+my*my+mz*mz)
        var idx := _mesh_v.size()
        _mesh_v.append({"x": mx/mag, "y": my/mag, "z": mz/mag, "type": "hexagon"})
        _mesh_e.append([e[0], idx]); _mesh_e.append([e[1], idx])

# ─────────────────────────────────────────────────────────────
# API publique
# ─────────────────────────────────────────────────────────────
func set_mode(m: DrawMode): mode = m
func set_resonance(k: float, pa: float, pb: float):
    resonance_k = k; personal_phase = pa; partner_phase = pb
func set_kin(ka: Dictionary, kb: Dictionary):
    kin_a = ka; kin_b = kb
