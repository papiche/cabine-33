extends RefCounted
class_name QR_Generator

# QR Code pur GDScript — Version 4 (33×33), ECC Level L
# Capacité : 80 octets en mode byte → assez pour un npub bech32 (63 chars).
# Retourne une Image FORMAT_L8 prête à afficher via ImageTexture.

const VERSION := 4
const SIZE    := 33
const N_DATA  := 80
const N_EC    := 20

# Format strings précomputées (ECC L = 0b01, masques 0-7, XOR 0b101010000010010)
# Vérifiées contre la table 10 de l'ISO 18004.
const FORMAT_STRINGS := [
    0b111011111000100,  # mask 0
    0b111001011110011,  # mask 1
    0b111110110101010,  # mask 2
    0b111100010011101,  # mask 3
    0b110011000101111,  # mask 4
    0b110001100011000,  # mask 5
    0b110110001000001,  # mask 6
    0b110100101110110   # mask 7
]

# ── GF(256) ─────────────────────────────────────────────────────
static var _exp := PackedByteArray()
static var _log := PackedByteArray()
static var _gen := PackedByteArray()  # polynôme générateur RS, degré N_EC
static var _ready := false

static func _init_gf():
    if _ready: return
    _exp.resize(512); _log.resize(256)
    var x := 1
    for i in range(255):
        _exp[i] = x; _log[x] = i
        x = x << 1
        if x >= 256: x ^= 285
    for i in range(255, 512): _exp[i] = _exp[i - 255]
    _log[0] = 0
    _gen.resize(N_EC + 1)
    for i in range(N_EC + 1): _gen[i] = 0
    _gen[0] = 1
    for root in range(N_EC):
        for j in range(N_EC, 0, -1):
            _gen[j] = _gen[j-1] ^ _gf_mul(_gen[j], _exp[root])
        _gen[0] = _gf_mul(_gen[0], _exp[root])
    _ready = true

static func _gf_mul(a: int, b: int) -> int:
    if a == 0 or b == 0: return 0
    return _exp[(_log[a] + _log[b]) % 255]

static func _rs_encode(data: PackedByteArray) -> PackedByteArray:
    var r := PackedByteArray(); r.resize(N_EC)
    for byte in data:
        var coef := byte ^ r[0]
        for i in range(N_EC - 1):
            r[i] = r[i+1] ^ _gf_mul(coef, _gen[N_EC - 1 - i])
        r[N_EC - 1] = _gf_mul(coef, _gen[0])
    return r

# ── Encodage données ─────────────────────────────────────────────
static func _push_bits(bits: Array, val: int, n: int):
    for i in range(n - 1, -1, -1): bits.append((val >> i) & 1)

static func _encode_bytes(text: String) -> PackedByteArray:
    var raw := text.to_utf8_buffer()
    var bits: Array = []
    _push_bits(bits, 0b0100, 4)        # mode byte
    _push_bits(bits, raw.size(), 8)    # compte (8 bits pour V4 byte mode)
    for b in raw: _push_bits(bits, b, 8)
    _push_bits(bits, 0, 4)             # terminateur
    while bits.size() % 8 != 0: bits.append(0)
    var pads := [0xEC, 0x11]; var pi := 0
    while bits.size() < N_DATA * 8:
        _push_bits(bits, pads[pi % 2], 8); pi += 1
    var cw := PackedByteArray(); cw.resize(N_DATA)
    for i in range(N_DATA):
        var v := 0
        for k in range(8): v = (v << 1) | bits[i * 8 + k]
        cw[i] = v
    return cw

# ── Construction de la matrice ────────────────────────────────────
static func _new_matrix() -> Array:
    var m := []; for _r in range(SIZE): m.append(PackedInt32Array()); m[-1].resize(SIZE); m[-1].fill(-1)
    return m

static func _place_finders(m: Array):
    for pos in [[0,0],[0,SIZE-7],[SIZE-7,0]]:
        var r0: int = int(pos[0]); var c0: int = int(pos[1])
        for dr in range(7):
            for dc in range(7):
                var v := 0
                if dr==0 or dr==6 or dc==0 or dc==6: v = 1
                elif dr==1 or dr==5 or dc==1 or dc==5: v = 0
                else: v = 1
                m[r0+dr][c0+dc] = v
    # Séparateurs (toujours clairs)
    for i in range(8):
        m[7][i]=0; m[i][7]=0          # TL bas + droite
        m[7][SIZE-1-i]=0              # TR bas
        m[i][SIZE-8]=0                # TR gauche
        m[SIZE-8][i]=0                # BL haut
        m[SIZE-1-i][7]=0              # BL droite

static func _place_timing(m: Array):
    for i in range(8, SIZE - 8):
        var v := 1 if i % 2 == 0 else 0
        if m[6][i] == -1: m[6][i] = v
        if m[i][6] == -1: m[i][6] = v

static func _place_alignment(m: Array):
    # V4 : un seul motif centré en (26,26)
    for dr in range(-2, 3):
        for dc in range(-2, 3):
            var v := 1 if (abs(dr)==2 or abs(dc)==2 or (dr==0 and dc==0)) else 0
            if m[26+dr][26+dc] == -1: m[26+dr][26+dc] = v

static func _reserve_format(m: Array):
    for c in [0,1,2,3,4,5,7,8]:
        if m[8][c] == -1: m[8][c] = 0
    for r in [0,1,2,3,4,5,7,8]:
        if m[r][8] == -1: m[r][8] = 0
    m[SIZE-8][8] = 1  # dark module toujours sombre
    for i in range(8): if m[8][SIZE-8+i] == -1: m[8][SIZE-8+i] = 0
    for i in range(7): if m[SIZE-7+i][8] == -1: m[SIZE-7+i][8] = 0

static func _place_data(m: Array, all_bits: Array) -> Array:
    var positions := []
    var idx := 0; var up := true; var col := SIZE - 1
    while col >= 1:
        if col == 6: col -= 1
        for i in range(SIZE):
            var row := (SIZE - 1 - i) if up else i
            for dc in [0, 1]:
                var c: int = col - int(dc)
                if c < 0 or c >= SIZE: continue
                if m[row][c] == -1:
                    m[row][c] = all_bits[idx] if idx < all_bits.size() else 0
                    positions.append([row, c])
                    idx += 1
        up = not up; col -= 2
    return positions

static func _apply_mask(m: Array, positions: Array, mask: int):
    for pos in positions:
        var r: int = int(pos[0]); var c: int = int(pos[1]); var flip: bool = false
        match mask:
            0: flip = (r + c) % 2 == 0
            1: flip = r % 2 == 0
            2: flip = c % 3 == 0
            3: flip = (r + c) % 3 == 0
            4: flip = (r / 2 + c / 3) % 2 == 0
            5: flip = (r * c) % 2 + (r * c) % 3 == 0
            6: flip = ((r * c) % 2 + (r * c) % 3) % 2 == 0
            7: flip = ((r + c) % 2 + (r * c) % 3) % 2 == 0
        if flip: m[r][c] ^= 1

static func _place_format(m: Array, mask: int):
    var fmt: int = int(FORMAT_STRINGS[mask])
    # Copie 1 — autour du motif TL
    var c1r := [8,8,8,8,8,8,8,8,7,5,4,3,2,1,0]
    var c1c := [0,1,2,3,4,5,7,8,8,8,8,8,8,8,8]
    for i in range(15): m[c1r[i]][c1c[i]] = (fmt >> (14-i)) & 1
    # Copie 2 — TR (bits 0-7) et BL (bits 8-14)
    for i in range(8): m[8][SIZE-1-i] = (fmt >> (14-i)) & 1
    for i in range(7): m[SIZE-7+i][8] = (fmt >> (6-i)) & 1

static func _penalty(m: Array) -> int:
    var p := 0
    # Règle 1 : 5+ consécutifs en ligne/colonne
    for r in range(SIZE):
        var rh := 1; var rv := 1
        for c in range(1, SIZE):
            rh = rh+1 if m[r][c]==m[r][c-1] else 1
            if rh == 5: p += 3
            elif rh > 5: p += 1
            rv = rv+1 if m[c][r]==m[c-1][r] else 1
            if rv == 5: p += 3
            elif rv > 5: p += 1
    # Règle 2 : blocs 2×2
    for r in range(SIZE-1):
        for c in range(SIZE-1):
            var v: int = int(m[r][c])
            if v==m[r][c+1] and v==m[r+1][c] and v==m[r+1][c+1]: p+=3
    return p

# ── API publique ──────────────────────────────────────────────────
static func generate(text: String, scale: int = 8) -> Image:
    _init_gf()
    var data_cw := _encode_bytes(text)
    var ec_cw   := _rs_encode(data_cw)
    var all_bits: Array = []
    for cw in data_cw: _push_bits(all_bits, cw, 8)
    for cw in ec_cw:   _push_bits(all_bits, cw, 8)
    # V4 a 0 bits de reste

    # Construire la matrice de base (modules fonction)
    var base_m := _new_matrix()
    _place_finders(base_m); _place_timing(base_m)
    _place_alignment(base_m); _reserve_format(base_m)

    # Placer les données
    var data_pos := _place_data(base_m, all_bits)

    # Choisir le meilleur masque
    var best_m: Array = []; var best_p := 999999
    for mask in range(8):
        var m: Array = []
        for row in base_m: m.append(row.duplicate())
        _apply_mask(m, data_pos, mask)
        _place_format(m, mask)
        var pen := _penalty(m)
        if pen < best_p: best_p = pen; best_m = m

    # Rendu image avec zone calme 4 modules
    var quiet := 4
    var img_px := (SIZE + quiet * 2) * scale
    var img := Image.create(img_px, img_px, false, Image.FORMAT_L8)
    img.fill(Color.WHITE)
    for r in range(SIZE):
        for c in range(SIZE):
            if best_m[r][c] == 1:
                for pr in range(scale):
                    for pc in range(scale):
                        img.set_pixel((quiet+c)*scale+pc, (quiet+r)*scale+pr, Color.BLACK)
    return img
