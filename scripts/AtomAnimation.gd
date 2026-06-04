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

var mode: int    = DrawMode.PROFIL
var perf_level   := PerfLevel.MED
var resonance_k  := 0.5
var personal_phase := 0.0
var partner_phase  := 0.0
var kin_a: Dictionary = {}
var kin_b: Dictionary = {}

# Couleurs Kin mises en cache — recalculées uniquement dans set_kin(), pas à chaque frame
var _cached_ka_color: Color = Color.TRANSPARENT
var _cached_kb_color: Color = Color.TRANSPARENT

var _frame_time  := 0
var _logical_time: float = 0.0  # accumulateur indépendant du refresh rate
var _calib_done  := false
var _calib_wait_s: float = 0.0   # secondes écoulées (pas frames)
var _aura_pts: PackedVector2Array = PackedVector2Array()  # aura vocale pré-allouée
var _fps_samples: Array[float] = []
var _mesh_v: PackedVector3Array = PackedVector3Array()  # géométrie compacte (zéro dict lookup)
var _mesh_is_penta: PackedByteArray = PackedByteArray() # 1=pentagone, 0=arête
var _mesh_e: Array[Array]      = []

# Pré-alloués une fois pour zéro GC dans _draw() (60 fps sur mobile)
var _pts_array  := PackedVector2Array()
var _poly_array := PackedVector2Array()

# Rayons de spirale Phi pré-calculés (9 * exp(0.306 * s)) — jamais recalculés dans _draw()
var _spiral_radii_low:  PackedFloat32Array = []  # pas=0.14
var _spiral_radii_med:  PackedFloat32Array = []  # pas=0.09
var _spiral_radii_high: PackedFloat32Array = []  # pas=0.06
var _spiral_s_low:      PackedFloat32Array = []
var _spiral_s_med:      PackedFloat32Array = []
var _spiral_s_high:     PackedFloat32Array = []

# ─────────────────────────────────────────────────────────────
func _ready():
    z_index = -10
    _pts_array.resize(80)
    _poly_array.resize(12)
    _build_icosahedron()
    _precompute_spirals()

func _precompute_spirals():
    # PackedFloat32Array est passé par VALEUR dans les Array[variant] → .append() modifie
    # une copie. Solution : accumuler dans des Array normaux puis convertir.
    var tr: Array; var ts: Array; var s: float
    tr = []; ts = []; s = 0.0
    while s <= 5.8: tr.append(9.0*exp(0.306*s)); ts.append(s); s += 0.14
    _spiral_radii_low = PackedFloat32Array(tr);  _spiral_s_low = PackedFloat32Array(ts)
    tr = []; ts = []; s = 0.0
    while s <= 5.8: tr.append(9.0*exp(0.306*s)); ts.append(s); s += 0.09
    _spiral_radii_med = PackedFloat32Array(tr);  _spiral_s_med = PackedFloat32Array(ts)
    tr = []; ts = []; s = 0.0
    while s <= 5.8: tr.append(9.0*exp(0.306*s)); ts.append(s); s += 0.06
    _spiral_radii_high = PackedFloat32Array(tr); _spiral_s_high = PackedFloat32Array(ts)

func _process(delta):
    # Temps logique normalisé à 60 fps — indépendant de l'écran (60/90/120 Hz)
    _logical_time += delta * 60.0
    _frame_time = int(_logical_time)
    # Calibration: attendre 2s réelles puis mesurer 1s de FPS
    if not _calib_done:
        _calib_wait_s += delta
        if _calib_wait_s > 2.0:
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

    var kr := _cached_ka_color if _cached_ka_color != Color.TRANSPARENT else _col_accent()

    # ── Aura vocale (wavetable) ou mandala cymatique (k ≥ 0.95) ─────────────
    var wt: PackedFloat32Array = Voice_Sampler.my_wavetable
    var aura_pts := 64
    if _aura_pts.size() != aura_pts: _aura_pts.resize(aura_pts + 1)
    if resonance_k >= 0.95:
        # Singularité : Lissajous / mandala cymatique (quinte parfaite 3:2)
        var t_off := float(_frame_time) * 0.004
        for i in range(aura_pts):
            var t := float(i) / float(aura_pts) * TAU
            var rx := R * sin(3.0 * t + t_off)
            var ry := R * sin(2.0 * t)
            _aura_pts[i] = Vector2(cx + rx, cy + ry)
        _aura_pts[aura_pts] = _aura_pts[0]
        draw_polyline(_aura_pts, Color(kr.r, kr.g, kr.b, 0.85), 2.5, true)
    elif not wt.is_empty():
        # Aura vocale : rayon modulé par la wavetable
        var step := wt.size() / aura_pts
        for i in range(aura_pts):
            var angle := float(i) / float(aura_pts) * TAU
            var wv := wt[i * step] * 0.25 * R  # excursion max ±25% du rayon
            var r_aura := R + wv
            _aura_pts[i] = Vector2(cx + cos(angle) * r_aura, cy + sin(angle) * r_aura)
        _aura_pts[aura_pts] = _aura_pts[0]
        draw_polyline(_aura_pts, Color(kr.r, kr.g, kr.b, 0.55), 1.8, true)
    # ─────────────────────────────────────────────────────────────────────────

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
        for i in range(80):
            var x2: float = -R + float(i) * R * 2.0 / 79.0
            _pts_array[i] = Vector2(cx + x2, cy + sin((x2 / R * freq + phase * TAU * 2.0) * PI) * R * 0.3)
        draw_polyline(_pts_array, Color(kr.r, kr.g, kr.b, 0.71 * env), 2.2)

    else:
        var rot := phase * TAU * (0.11 if digit % 2 == 0 else -0.11) + digit * 0.28
        var n_sides := digit
        for i in range(n_sides):
            var a := float(i) / float(n_sides) * TAU - PI * 0.5 + rot
            _poly_array[i] = Vector2(cx + cos(a) * R, cy + sin(a) * R)
        _poly_array[n_sides] = _poly_array[0]
        draw_polyline(_poly_array.slice(0, n_sides + 1), Color(kr.r, kr.g, kr.b, 0.73 * env), 2.5, true)

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

    var ca := _cached_ka_color if _cached_ka_color != Color.TRANSPARENT else _col_accent()
    var cb := _cached_kb_color if _cached_kb_color != Color.TRANSPARENT else _col_warm()

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
        # Réutilise _poly_array pré-alloué (zéro allocation GC à chaque frame)
        for i in range(5):
            var a := float(i) / 5.0 * TAU - PI * 0.5 + t
            _poly_array[i] = Vector2(cx + cos(a)*pr, cy + sin(a)*pr)
        _poly_array[5] = _poly_array[0]
        var wc174 := _col_warm()
        draw_polyline(_poly_array.slice(0, 6), Color(wc174.r, wc174.g, wc174.b, 1.0), 3.0, true)

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

    # Spirales Phi (5 bras dorés) — rayons pré-calculés, seul le trig reste en _draw()
    var phi_rot := tN * 0.14 * PHI
    var spiral_radii := _spiral_radii_low if perf_level == PerfLevel.LOW \
        else (_spiral_radii_med if perf_level == PerfLevel.MED else _spiral_radii_high)
    var spiral_sv := _spiral_s_low if perf_level == PerfLevel.LOW \
        else (_spiral_s_med if perf_level == PerfLevel.MED else _spiral_s_high)
    var wc_spiral := _col_warm()
    var wc_spiralC := Color(wc_spiral.r, wc_spiral.g, wc_spiral.b, 0.09 + 0.11 * excite)
    for arm in range(5):
        var base_a := (float(arm) / 5.0) * TAU + phi_rot
        var pva := PackedVector2Array()
        for i in range(spiral_radii.size()):
            var r2: float = spiral_radii[i]
            if r2 > radius: break
            var sv: float = spiral_sv[i]
            pva.append(Vector2(cx + r2 * cos(base_a + sv), cy + r2 * sin(base_a + sv)))
        if pva.size() >= 2:
            draw_polyline(pva, wc_spiralC, 1.0)

    # Maillage icosaèdre
    if _mesh_v.size() == 0: _build_icosahedron()
    var pulse_z := fmod(float(_frame_time), 300.0) / 300.0 * 4.0 - 2.0
    # Pré-calculer cos/sin UNE SEULE FOIS avant la boucle (était recalculé pour chaque sommet)
    var cos_ax := cos(ax); var sin_ax := sin(ax)
    var cos_ay := cos(ay); var sin_ay := sin(ay)
    var pulse_sin := sin(float(_frame_time) * 0.2)
    var proj: Array[Vector2] = []
    var pz: Array[float]     = []
    for v in _mesh_v:
        var y1: float = v.y * cos_ax - v.z * sin_ax
        var z1: float = v.y * sin_ax + v.z * cos_ax
        var x2: float = v.x * cos_ay + z1 * sin_ay
        var z2: float = -v.x * sin_ay + z1 * cos_ay
        var dp: float  = abs(y1 - pulse_z)
        var def: float = 1.0 + 0.4 * (0.4 - dp) * pulse_sin if dp < 0.4 else 1.0
        var sc: float  = 3.0 / (3.0 + z2)
        proj.append(Vector2(cx + x2 * radius * sc * def, cy + y1 * radius * sc * def))
        pz.append(z2)

    # Regroupement des arêtes par face (avant/arrière) → 2 draw_multiline au lieu de N draw_line
    var ac := _col_accent()
    var col_front := Color(ac.r, ac.g, ac.b, 0.05 * 0.55)
    var col_back  := Color(ac.r, ac.g, ac.b, 0.24 * 0.55)
    var front_pts := PackedVector2Array()
    var back_pts  := PackedVector2Array()
    var edge_step := 2 if perf_level == PerfLevel.LOW else 1
    for i in range(0, _mesh_e.size(), edge_step):
        var a: int = int(_mesh_e[i][0]); var b: int = int(_mesh_e[i][1])
        if pz[a] > 0.0 and pz[b] > 0.0:
            front_pts.append(proj[a]); front_pts.append(proj[b])
        else:
            back_pts.append(proj[a]);  back_pts.append(proj[b])
    if back_pts.size()  >= 2: draw_multiline(back_pts,  col_back,  0.7)
    if front_pts.size() >= 2: draw_multiline(front_pts, col_front, 0.7)

    for i in range(_mesh_v.size()):
        var is_penta: bool = (_mesh_is_penta[i] == 1)  # PackedByteArray — zéro dict lookup
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
        var ca := _cached_ka_color if _cached_ka_color != Color.TRANSPARENT else _col_accent()
        var cb := _cached_kb_color if _cached_kb_color != Color.TRANSPARENT else _col_warm()
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
    _mesh_v.clear(); _mesh_is_penta.clear(); _mesh_e.clear()
    for v in raw:
        var mag := sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
        _mesh_v.append(Vector3(v[0]/mag, v[1]/mag, v[2]/mag))
        _mesh_is_penta.append(1)
    var edges: Array[Array] = []
    for i in range(12):
        for j in range(i+1, 12):
            var a := _mesh_v[i]; var b := _mesh_v[j]
            var d: float = sqrt(pow(a.x-b.x,2)+pow(a.y-b.y,2)+pow(a.z-b.z,2))
            if d < 1.1: edges.append([i, j])
    for e in edges:
        var v1 := _mesh_v[int(e[0])]; var v2 := _mesh_v[int(e[1])]
        var mx := (v1.x+v2.x)*0.5; var my := (v1.y+v2.y)*0.5; var mz := (v1.z+v2.z)*0.5
        var mag := sqrt(mx*mx+my*my+mz*mz)
        var idx := _mesh_v.size()
        _mesh_v.append(Vector3(mx/mag, my/mag, mz/mag))
        _mesh_is_penta.append(0)
        _mesh_e.append([e[0], idx]); _mesh_e.append([e[1], idx])

# ─────────────────────────────────────────────────────────────
# API publique
# ─────────────────────────────────────────────────────────────
func set_mode(m: int):
    if mode == m: return
    # Fondu 180ms entre les modes (évite le changement brutal)
    var tw := create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.18)
    tw.tween_callback(func():
        mode = m
        _frame_time = 0; _logical_time = 0.0  # repart de l'état initial du mode
        queue_redraw())
    tw.tween_property(self, "modulate:a", 1.0, 0.18)
func set_resonance(k: float, pa: float, pb: float):
    resonance_k = k; personal_phase = pa; partner_phase = pb
func set_kin(ka: Dictionary, kb: Dictionary):
    kin_a = ka; kin_b = kb
    _cached_ka_color = Kin_Maya.kin_color_rgb(ka.get("color", "")) if not ka.is_empty() else Color.TRANSPARENT
    _cached_kb_color = Kin_Maya.kin_color_rgb(kb.get("color", "")) if not kb.is_empty() else Color.TRANSPARENT
