extends Node
# BIP-340 Schnorr signing + Bech32 decode — pur GDScript, zéro réseau
# Utilisé sur Android/Desktop : signe localement sans envoyer nsec au serveur
# Arithmétique 256-bit via limbes 26-bit (10 limbes, produit max = 2^52 < 2^63)

# ── secp256k1 ────────────────────────────────────────────────────────────────
const _P_HEX := "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"
const _N_HEX := "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"
const _GX_HEX:= "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
const _GY_HEX:= "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"

const LIMB_BITS := 26
const LIMB_MASK := (1 << LIMB_BITS) - 1  # 0x3FFFFFF
const LIMBS    := 10  # 10 × 26 = 260 ≥ 256

var _P: Array; var _N: Array; var _Gx: Array; var _Gy: Array
# Constantes de réduction pour _field_mul (mod P) et _scalar_mul (mod N)
# _P_R = 2^260 mod P = 16 × (2^32 + 977) = 68,719,492,368 = 0x1000003D10
#   Vérification Python : hex(pow(2, 260, 0xFFFF...FC2F)) == '0x1000003d10'
# _N_R = 2^260 mod N = 16 × (2^256 - N) = 16 × 0x14551231950B75FC4402DA1732FC9BEBF
#   Vérification Python : hex(pow(2, 260, 0xFFFF...4141))
var _P_R: Array   # ~34 bits — tient en 2 limbes
var _N_R: Array   # ~134 bits — tient en 6 limbes

func _ready():
	_P   = _hex_to_limbs(_P_HEX)
	_N   = _hex_to_limbs(_N_HEX)
	_Gx  = _hex_to_limbs(_GX_HEX)
	_Gy  = _hex_to_limbs(_GY_HEX)
	_P_R = _hex_to_limbs_var("1000003D10")                    # 2^260 mod P
	_N_R = _hex_to_limbs_var("14551231950B75FC4402DA1732FC9BEBF0")  # 2^260 mod N

# ── Bech32 decode ─────────────────────────────────────────────────────────────
const _B32_CHARSET := "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

func bech32_decode_data(bech: String) -> PackedByteArray:
	var sep := bech.rfind("1")
	if sep < 0: return PackedByteArray()
	var data_str := bech.substr(sep + 1)
	# Strip checksum (last 6 chars)
	if data_str.length() < 7: return PackedByteArray()
	data_str = data_str.substr(0, data_str.length() - 6)
	var vals := PackedInt32Array()
	for c in data_str:
		var v := _B32_CHARSET.find(c)
		if v < 0: return PackedByteArray()
		vals.append(v)
	# Convert 5-bit groups to 8-bit bytes
	return _convert_bits(vals, 5, 8, false)

func _convert_bits(data: PackedInt32Array, from_bits: int, to_bits: int, pad: bool) -> PackedByteArray:
	var acc := 0; var bits := 0; var out := PackedByteArray()
	var max_v := (1 << to_bits) - 1
	for v in data:
		acc = (acc << from_bits) | v; bits += from_bits
		while bits >= to_bits:
			bits -= to_bits; out.append((acc >> bits) & max_v)
	if pad and bits > 0: out.append((acc << (to_bits - bits)) & max_v)
	return out

func _hex_to_limbs_var(h: String) -> Array:
	# Comme _hex_to_limbs mais retourne un tableau de taille variable (pas LIMBS fixe)
	var b := PackedByteArray()
	for i in range(0, h.length(), 2):
		b.append(("0x" + h.substr(i, 2)).hex_to_int())
	var acc: Array = [0,0,0,0,0,0,0,0,0,0]
	for i in range(b.size()):
		acc = _limb_mul_small(acc, 256)
		acc = _limb_add_small(acc, b[i])
	# Trim trailing zeros
	while acc.size() > 1 and acc.back() == 0: acc.pop_back()
	return acc

func nsec_to_bytes(nsec: String) -> PackedByteArray:
	if not nsec.begins_with("nsec1"): return PackedByteArray()
	return bech32_decode_data(nsec)

func npub_to_hex(npub: String) -> String:
	if not npub.begins_with("npub1"): return ""
	var b := bech32_decode_data(npub)
	if b.size() != 32: return ""
	return _bytes_to_hex(b)

# ── SHA256 ────────────────────────────────────────────────────────────────────
func sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()

func _tagged_hash(tag: String, data: PackedByteArray) -> PackedByteArray:
	var tag_bytes := tag.to_utf8_buffer()
	var tag_hash  := sha256(tag_bytes)
	var buf := PackedByteArray()
	buf.append_array(tag_hash); buf.append_array(tag_hash); buf.append_array(data)
	return sha256(buf)

# ── 256-bit arithmetic (base 2^26 limbs) ────────────────────────────────────
func _zero() -> Array: return [0,0,0,0,0,0,0,0,0,0]
func _one()  -> Array: return [1,0,0,0,0,0,0,0,0,0]

func _hex_to_limbs(h: String) -> Array:
	# Hex string → big-endian bytes → little-endian 26-bit limbs
	var b := PackedByteArray()
	for i in range(0, h.length(), 2):
		b.append(("0x" + h.substr(i, 2)).hex_to_int())
	return _bytes_to_limbs(b)

func _bytes_to_limbs(b: PackedByteArray) -> Array:
	var acc: Array = _zero()
	var i := 0
	while i < b.size():
		var chunk_size = mini(3, b.size() - i)
		var val := 0
		for j in range(chunk_size):
			val = (val << 8) | b[i + j]
		# Multiplication par 2^(8 * chunk_size)
		acc = _limb_mul_small(acc, 1 << (chunk_size * 8))
		acc = _limb_add_small(acc, val)
		i += chunk_size
	return acc

func _limbs_to_bytes(a: Array) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(32)
	var tmp: Array = a.duplicate()
	for i in range(31, -1, -1):
		var r := _limb_divmod_small(tmp, 256)
		result[i] = r[1]
		tmp = r[0]
	return result

func _limb_add_small(a: Array, v: int) -> Array:
	var r := a.duplicate(); r[0] += v
	_propagate_carry(r); return r

func _limb_mul_small(a: Array, v: int) -> Array:
	var r := _zero(); var carry := 0
	for i in range(LIMBS):
		var t: int = a[i] * v + carry
		r[i] = t & LIMB_MASK; carry = t >> LIMB_BITS
	return r

func _limb_divmod_small(a: Array, v: int) -> Array:
	# Returns [quotient, remainder]
	var r := _zero(); var rem: int = 0
	for i in range(LIMBS - 1, -1, -1):
		var cur: int = rem * (1 << LIMB_BITS) + a[i]
		r[i] = cur / v; rem = cur % v
	return [r, rem]

func _propagate_carry(r: Array):
	for i in range(LIMBS - 1):
		r[i + 1] += r[i] >> LIMB_BITS
		r[i] &= LIMB_MASK

func _limbs_add(a: Array, b: Array) -> Array:
	var r := _zero()
	for i in range(LIMBS): r[i] = a[i] + b[i]
	_propagate_carry(r); return r

func _limbs_sub(a: Array, b: Array) -> Array:
	# a - b (assumes a >= b)
	var r := _zero()
	for i in range(LIMBS): r[i] = a[i] - b[i]
	for i in range(LIMBS - 1):
		if r[i] < 0: r[i] += (1 << LIMB_BITS); r[i + 1] -= 1
	return r

func _limbs_cmp(a: Array, b: Array) -> int:
	for i in range(LIMBS - 1, -1, -1):
		if a[i] > b[i]: return 1
		if a[i] < b[i]: return -1
	return 0

func _limbs_is_zero(a: Array) -> bool:
	for v in a: if v != 0: return false
	return true

func _limbs_is_odd(a: Array) -> bool: return (a[0] & 1) != 0

func _field_add(a: Array, b: Array) -> Array:
	var r := _limbs_add(a, b)
	if _limbs_cmp(r, _P) >= 0: r = _limbs_sub(r, _P)
	return r

func _field_sub(a: Array, b: Array) -> Array:
	if _limbs_cmp(a, b) >= 0: return _limbs_sub(a, b)
	return _limbs_sub(_limbs_add(a, _P), b)

func _field_mul(a: Array, b: Array) -> Array:
	# Réduction itérative : lo + hi*P_R jusqu'à ce que hi soit nul, puis ≤3 soustractions
	var t := _var_mul(a, b)
	while t.size() > LIMBS:
		var lo := t.slice(0, LIMBS)
		var hi := t.slice(LIMBS, t.size())
		if _limbs_is_zero(hi): t = lo; break
		t = _var_add(lo, _var_mul(hi, _P_R))
	var result := t.slice(0, LIMBS) if t.size() > LIMBS else t
	var count := 0
	while _limbs_cmp(result, _P) >= 0 and count < 4:
		result = _limbs_sub(result, _P); count += 1
	return result

func _field_inv(a: Array) -> Array:
	# Fermat: a^(p-2) mod p
	return _field_pow(a, _limbs_sub(_P, [2,0,0,0,0,0,0,0,0,0]))

func _field_pow(base: Array, exp: Array) -> Array:
	var result := _one()
	var b := base.duplicate()
	var e := exp.duplicate()
	while not _limbs_is_zero(e):
		if _limbs_is_odd(e): result = _field_mul(result, b)
		b = _field_mul(b, b)
		# e >>= 1
		for i in range(LIMBS - 1): e[i] = ((e[i] >> 1) | ((e[i + 1] & 1) << (LIMB_BITS - 1)))
		e[LIMBS - 1] >>= 1
	return result

func _scalar_add(a: Array, b: Array) -> Array:
	var r := _limbs_add(a, b)
	if _limbs_cmp(r, _N) >= 0: r = _limbs_sub(r, _N)
	return r

func _var_mul(a: Array, b: Array) -> Array:
	# Produit de deux tableaux de taille variable (résultat de taille a.size+b.size)
	var sz := a.size() + b.size()
	var t: Array = []; t.resize(sz)
	for i in range(t.size()): t[i] = 0
	for i in range(a.size()):
		for j in range(b.size()): t[i + j] += a[i] * b[j]
	for i in range(t.size() - 1): t[i + 1] += t[i] >> LIMB_BITS; t[i] &= LIMB_MASK
	return t

func _var_add(a: Array, b: Array) -> Array:
	# Additionne deux tableaux de taille variable (résultat de taille max(a,b)+1)
	var sz := maxi(a.size(), b.size()) + 1
	var r: Array = []; r.resize(sz)
	for i in range(r.size()): r[i] = 0
	for i in range(a.size()): r[i] += a[i]
	for i in range(b.size()): r[i] += b[i]
	for i in range(r.size() - 1): r[i + 1] += r[i] >> LIMB_BITS; r[i] &= LIMB_MASK
	return r

func _scalar_mul(a: Array, b: Array) -> Array:
	# Réduction itérative mod N — identique à _field_mul avec _N_R
	var t := _var_mul(a, b)
	while t.size() > LIMBS:
		var lo := t.slice(0, LIMBS)
		var hi := t.slice(LIMBS, t.size())
		if _limbs_is_zero(hi): t = lo; break
		t = _var_add(lo, _var_mul(hi, _N_R))
	var result := t.slice(0, LIMBS) if t.size() > LIMBS else t
	var count := 0
	while _limbs_cmp(result, _N) >= 0 and count < 4:
		result = _limbs_sub(result, _N); count += 1
	return result

func _scalar_inv(a: Array) -> Array:
	return _scalar_pow(a, _limbs_sub(_N, [2,0,0,0,0,0,0,0,0,0]))

func _scalar_pow(base: Array, exp: Array) -> Array:
	var result := _one(); var b := base.duplicate(); var e := exp.duplicate()
	while not _limbs_is_zero(e):
		if _limbs_is_odd(e): result = _scalar_mul(result, b)
		b = _scalar_mul(b, b)
		for i in range(LIMBS - 1): e[i] = ((e[i] >> 1) | ((e[i + 1] & 1) << (LIMB_BITS - 1)))
		e[LIMBS - 1] >>= 1
	return result

# ── secp256k1 point operations — coordonnées Jacobiennes (X:Y:Z) ──────────────
# Représentation : (X:Y:Z) = affine (X/Z², Y/Z³)
# Avantage : ~65 000 mul/signature → ~6 500 mul (division par ~10 vs affine)
# Une seule inversion finale au lieu de 256 dans _point_mul

func _jac_double(P: Array) -> Array:
	# dbl-2009-l formulas (a=0 pour secp256k1)
	if P.is_empty(): return []
	var X: Array = P[0]; var Y: Array = P[1]; var Z: Array = P[2]
	if _limbs_is_zero(Y) or _limbs_is_zero(Z): return []
	var A := _field_mul(X, X)                          # X²
	var B := _field_mul(Y, Y)                          # Y²
	var C := _field_mul(B, B)                          # Y⁴
	var t  := _field_add(X, B)
	var D  := _field_add(_field_sub(_field_mul(t, t), A), _field_sub(_zero(), C))
	D = _field_add(D, D)                               # 2*((X+Y²)²-X²-Y⁴)
	var E  := _field_add(A, _field_add(A, A))          # 3*X²
	var F  := _field_mul(E, E)                         # E²
	var X3 := _field_sub(F, _field_add(D, D))          # F - 2D
	var Y3 := _field_sub(_field_mul(E, _field_sub(D, X3)), _field_add(_field_add(C,C),_field_add(_field_add(C,C),_field_add(C,C),),))
	# Y3 = E*(D-X3) - 8C  — on simplifie : 8C = C<<3
	var C8 := C
	for _x in range(3): C8 = _field_add(C8, C8)
	Y3 = _field_sub(_field_mul(E, _field_sub(D, X3)), C8)
	var Z3 := _field_mul(_field_add(Y, Y), Z)          # 2*Y*Z
	return [X3, Y3, Z3]

func _jac_add_affine(P: Array, Qx: Array, Qy: Array) -> Array:
	# add-2007-bl (P Jacobian, Q affine) — pas d'inversion requise
	if P.is_empty(): return [Qx, Qy, _one()]
	var X1: Array = P[0]; var Y1: Array = P[1]; var Z1: Array = P[2]
	var Z1sq := _field_mul(Z1, Z1)                     # Z1²
	var Z1cu := _field_mul(Z1sq, Z1)                   # Z1³
	var U2   := _field_mul(Qx, Z1sq)                   # Q.x * Z1²
	var S2   := _field_mul(Qy, Z1cu)                   # Q.y * Z1³
	var H    := _field_sub(U2, X1)                     # U2 - X1
	var R    := _field_sub(S2, Y1)                     # S2 - Y1
	if _limbs_is_zero(H):
		if _limbs_is_zero(R): return _jac_double(P)    # P == Q → doubler
		return []                                       # P == -Q → infini
	var H2 := _field_mul(H, H)
	var H3 := _field_mul(H2, H)
	var U1H2 := _field_mul(X1, H2)
	var X3 := _field_sub(_field_sub(_field_mul(R, R), H3), _field_add(U1H2, U1H2))
	var Y3 := _field_sub(_field_mul(R, _field_sub(U1H2, X3)), _field_mul(Y1, H3))
	var Z3 := _field_mul(H, Z1)
	return [X3, Y3, Z3]

func _jac_to_affine(P: Array) -> Array:
	# Conversion Jacobien → affine : seule inversion de toute la multiplication
	if P.is_empty(): return []
	var Z: Array = P[2]
	if _limbs_is_zero(Z): return []
	var Zi  := _field_inv(Z)
	var Zi2 := _field_mul(Zi, Zi)
	var Zi3 := _field_mul(Zi2, Zi)
	return [_field_mul(P[0], Zi2), _field_mul(P[1], Zi3)]

func _jac_add(P: Array, Q: Array) -> Array:
	# Addition Jacobien+Jacobien — add-2007-bl — 12 field_mul, zéro inversion
	if P.is_empty(): return Q
	if Q.is_empty(): return P
	var X1: Array = P[0]; var Y1: Array = P[1]; var Z1: Array = P[2]
	var X2: Array = Q[0]; var Y2: Array = Q[1]; var Z2: Array = Q[2]
	var Z1Z1 := _field_mul(Z1, Z1)
	var Z2Z2 := _field_mul(Z2, Z2)
	var U1   := _field_mul(X1, Z2Z2)
	var U2   := _field_mul(X2, Z1Z1)
	var S1   := _field_mul(Y1, _field_mul(Z2, Z2Z2))
	var S2   := _field_mul(Y2, _field_mul(Z1, Z1Z1))
	var H    := _field_sub(U2, U1)
	var R    := _field_add(_field_sub(S2, S1), _field_sub(S2, S1))
	if _limbs_is_zero(H):
		if _limbs_is_zero(R): return _jac_double(P)
		return []
	var I    := _field_mul(_field_add(H,H), _field_add(H,H))
	var J    := _field_mul(H, I)
	var V    := _field_mul(U1, I)
	var X3   := _field_sub(_field_sub(_field_mul(R,R), J), _field_add(V, V))
	var S1J  := _field_mul(S1, J)
	var Y3   := _field_sub(_field_mul(R, _field_sub(V, X3)), _field_add(S1J, S1J))
	var ZZ   := _field_add(Z1, Z2)
	var Z3   := _field_mul(_field_sub(_field_sub(_field_mul(ZZ,ZZ), Z1Z1), Z2Z2), H)
	return [X3, Y3, Z3]

func _point_mul(k: Array, G: Array) -> Array:
	# Double-and-add tout en Jacobien : ~2 800 field_mul vs ~65 000 en affine (×23)
	# Zéro inversion dans la boucle — une seule à la fin via _jac_to_affine
	var result: Array = []
	var addend := [G[0], G[1], _one()]
	var scalar := k.duplicate()
	while not _limbs_is_zero(scalar):
		if _limbs_is_odd(scalar):
			result = _jac_add(result, addend)
		addend = _jac_double(addend)
		for i in range(LIMBS - 1): scalar[i] = ((scalar[i] >> 1) | ((scalar[i + 1] & 1) << (LIMB_BITS - 1)))
		scalar[LIMBS - 1] >>= 1
	return _jac_to_affine(result)

func _point_has_even_y(P: Array) -> bool:
	return not _limbs_is_odd(P[1])

# ── BIP-340 Schnorr ───────────────────────────────────────────────────────────
func schnorr_sign(msg32: PackedByteArray, privkey32: PackedByteArray) -> PackedByteArray:
	if msg32.size() != 32 or privkey32.size() != 32:
		push_error("NostrCrypto: msg and privkey must be 32 bytes"); return PackedByteArray()

	var d0 := _bytes_to_limbs(privkey32)
	if _limbs_is_zero(d0) or _limbs_cmp(d0, _N) >= 0:
		push_error("NostrCrypto: invalid private key"); return PackedByteArray()

	var G := [_Gx, _Gy]
	var P := _point_mul(d0, G)
	# BIP-340: negate d if P has odd y
	var d := d0
	if not _point_has_even_y(P): d = _limbs_sub(_N, d0)

	# k = hash_BIP0340/nonce(bytes(d) || P.x || msg)
	var nonce_input := PackedByteArray()
	nonce_input.append_array(_limbs_to_bytes(d))
	nonce_input.append_array(_limbs_to_bytes(P[0]))
	nonce_input.append_array(msg32)
	var rand_bytes := _tagged_hash("BIP0340/nonce", nonce_input)

	var k0 := _bytes_to_limbs(rand_bytes)
	# k0 mod n
	while _limbs_cmp(k0, _N) >= 0: k0 = _limbs_sub(k0, _N)
	if _limbs_is_zero(k0):
		push_error("NostrCrypto: k0 is zero (negligible probability)"); return PackedByteArray()

	var R := _point_mul(k0, G)
	var k := k0
	if not _point_has_even_y(R): k = _limbs_sub(_N, k0)

	# e = hash_BIP0340/challenge(R.x || P.x || msg) mod n
	var chal_input := PackedByteArray()
	chal_input.append_array(_limbs_to_bytes(R[0]))
	chal_input.append_array(_limbs_to_bytes(P[0]))
	chal_input.append_array(msg32)
	var e_bytes := _tagged_hash("BIP0340/challenge", chal_input)
	var e := _bytes_to_limbs(e_bytes)
	while _limbs_cmp(e, _N) >= 0: e = _limbs_sub(e, _N)

	# sig = R.x || (k + e*d mod n)
	var sig := PackedByteArray()
	sig.append_array(_limbs_to_bytes(R[0]))
	var s := _scalar_add(k, _scalar_mul(e, d))
	sig.append_array(_limbs_to_bytes(s))
	return sig

# ── Event signing (NIP-01) ────────────────────────────────────────────────────
func compute_event_id(ev: Dictionary) -> PackedByteArray:
	var parts := [0, ev.get("pubkey",""), ev.get("created_at",0),
		ev.get("kind",0), ev.get("tags",[]), ev.get("content","")]
	var serial := JSON.stringify(parts)
	return sha256(serial.to_utf8_buffer())

func sign_event_local(ev: Dictionary, nsec: String) -> Dictionary:
	# Sign a NOSTR event locally — nsec NEVER leaves the device
	var privkey_bytes: PackedByteArray
	if nsec.begins_with("nsec1"):
		privkey_bytes = nsec_to_bytes(nsec)
	else:
		privkey_bytes = PackedByteArray()
		for i in range(0, nsec.length(), 2):
			privkey_bytes.append(("0x" + nsec.substr(i, 2)).hex_to_int())
	if privkey_bytes.size() != 32:
		push_error("NostrCrypto: invalid nsec"); return ev

	var event_id_bytes := compute_event_id(ev)
	var sig_bytes      := schnorr_sign(event_id_bytes, privkey_bytes)

	var signed := ev.duplicate()
	signed["id"]  = _bytes_to_hex(event_id_bytes)
	signed["sig"] = _bytes_to_hex(sig_bytes)
	return signed

# ── NIP-44 v2 — Encryption locale (nsec ne quitte jamais l'appareil) ──────────
#
# Spec : https://github.com/nostr-protocol/nips/blob/master/44.md
# Algorithme :
#   1. ECDH secp256k1 → shared_x (32 bytes)
#   2. HKDF-SHA256(shared_x, salt="nip44-v2", info="conversation_key") → conv_key 32 bytes
#   3. Nonce 32 bytes aléatoires
#   4. HKDF-SHA256(conv_key, salt=nonce, info="message") → 76 bytes
#        chacha_key[0:32] | chacha_nonce[32:44] | hmac_key[44:76]
#   5. Pad plaintext (longueur 2 octets + texte + zéros jusqu'à puissance de 2)
#   6. ChaCha20(chacha_key, chacha_nonce, padded) → ciphertext
#   7. HMAC-SHA256(hmac_key, nonce||ciphertext) → mac 32 bytes
#   8. Base64( version=2 | nonce | ciphertext | mac )

# ── HMAC-SHA256 ───────────────────────────────────────────────────────────────
func _hmac_sha256(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	const BLOCK := 64
	var k := key
	if k.size() > BLOCK: k = sha256(k)
	while k.size() < BLOCK: k.append(0)
	var i_key := PackedByteArray(); var o_key := PackedByteArray()
	for b in k: i_key.append(b ^ 0x36); o_key.append(b ^ 0x5C)
	var inner := PackedByteArray(); inner.append_array(i_key); inner.append_array(data)
	var outer := PackedByteArray(); outer.append_array(o_key); outer.append_array(sha256(inner))
	return sha256(outer)

# ── HKDF-SHA256 ───────────────────────────────────────────────────────────────
func _hkdf_expand(prk: PackedByteArray, info: PackedByteArray, length: int) -> PackedByteArray:
	var out := PackedByteArray(); var t := PackedByteArray(); var counter := 1
	while out.size() < length:
		var d := PackedByteArray(); d.append_array(t); d.append_array(info); d.append(counter)
		t = _hmac_sha256(prk, d); out.append_array(t); counter += 1
	return out.slice(0, length)

func _hkdf_sha256(ikm: PackedByteArray, salt: PackedByteArray, info: PackedByteArray, length: int) -> PackedByteArray:
	var prk := _hmac_sha256(salt, ikm)
	return _hkdf_expand(prk, info, length)

# ── ChaCha20 stream cipher ────────────────────────────────────────────────────
# Implémentation pure GDScript — arithmétique 32-bit masquée via int64

func _u32(x: int) -> int: return x & 0xFFFFFFFF
func _rotl32(x: int, n: int) -> int: return _u32((x << n) | ((x & 0xFFFFFFFF) >> (32 - n)))

func _le32_load(b: PackedByteArray, i: int) -> int:
	return b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)

func _le32_store(v: int, b: PackedByteArray, i: int):
	v = _u32(v)
	b[i] = v & 0xFF; b[i+1] = (v >> 8) & 0xFF; b[i+2] = (v >> 16) & 0xFF; b[i+3] = (v >> 24) & 0xFF

# Constantes "expand 32-byte k" en little-endian uint32
const _CC_C0 := 0x61707865  # "expa"
const _CC_C1 := 0x3320646E  # "nd 3"
const _CC_C2 := 0x79622D32  # "2-by"
const _CC_C3 := 0x6B206574  # "te k"

func _chacha20_block(key: PackedByteArray, nonce12: PackedByteArray, counter: int) -> PackedByteArray:
	# State : constants(4) | key(8) | counter(1) | nonce(3)
	var s: Array = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
	s[0]=_CC_C0; s[1]=_CC_C1; s[2]=_CC_C2; s[3]=_CC_C3
	for i in range(8): s[4+i] = _le32_load(key, i*4)
	s[12] = _u32(counter)
	s[13] = _le32_load(nonce12, 0); s[14] = _le32_load(nonce12, 4); s[15] = _le32_load(nonce12, 8)
	var w := s.duplicate()

	for _r in range(10):
		# Colonnes
		_cc_qr(w, 0, 4, 8,12); _cc_qr(w, 1, 5, 9,13)
		_cc_qr(w, 2, 6,10,14); _cc_qr(w, 3, 7,11,15)
		# Diagonales
		_cc_qr(w, 0, 5,10,15); _cc_qr(w, 1, 6,11,12)
		_cc_qr(w, 2, 7, 8,13); _cc_qr(w, 3, 4, 9,14)

	var out := PackedByteArray(); out.resize(64)
	for i in range(16): _le32_store(_u32(w[i] + s[i]), out, i*4)
	return out

func _cc_qr(s: Array, a: int, b: int, c: int, d: int):
	s[a]=_u32(s[a]+s[b]); s[d]=_rotl32(s[d]^s[a],16)
	s[c]=_u32(s[c]+s[d]); s[b]=_rotl32(s[b]^s[c],12)
	s[a]=_u32(s[a]+s[b]); s[d]=_rotl32(s[d]^s[a], 8)
	s[c]=_u32(s[c]+s[d]); s[b]=_rotl32(s[b]^s[c], 7)

func _chacha20_xor(key: PackedByteArray, nonce12: PackedByteArray,
		plaintext: PackedByteArray, initial_counter: int = 0) -> PackedByteArray:
	var out := PackedByteArray(); out.resize(plaintext.size())
	var counter := initial_counter
	var i := 0
	while i < plaintext.size():
		var block := _chacha20_block(key, nonce12, counter)
		var chunk := mini(64, plaintext.size() - i)
		for j in range(chunk): out[i+j] = plaintext[i+j] ^ block[j]
		i += 64; counter += 1
	return out

# ── NIP-44 padding ────────────────────────────────────────────────────────────
func _nip44_calc_padded_len(unpadded: int) -> int:
	if unpadded <= 32: return 32
	var next_pow := 1; while next_pow < unpadded: next_pow <<= 1
	if next_pow == unpadded: return unpadded  # déjà puissance de 2
	var chunk := next_pow >> 3  # next_pow / 8
	return chunk * (int((unpadded - 1) / chunk) + 1)

func _nip44_pad(plaintext: PackedByteArray) -> PackedByteArray:
	var ulen := plaintext.size()
	var padded_len := _nip44_calc_padded_len(ulen)
	var out := PackedByteArray()
	out.append((ulen >> 8) & 0xFF); out.append(ulen & 0xFF)
	out.append_array(plaintext)
	while out.size() < padded_len + 2: out.append(0)
	return out

func _nip44_unpad(padded: PackedByteArray) -> PackedByteArray:
	if padded.size() < 2: return PackedByteArray()
	var ulen := (padded[0] << 8) | padded[1]
	if 2 + ulen > padded.size(): return PackedByteArray()
	return padded.slice(2, 2 + ulen)

# ── ECDH secp256k1 ────────────────────────────────────────────────────────────
func _lift_x(x_bytes: PackedByteArray) -> Array:
	# Retrouver le point complet depuis la clé publique x-only (y pair)
	# y² = x³ + 7 (mod p)  →  y = x^((p+1)/4) mod p  (car p ≡ 3 mod 4)
	var x := _bytes_to_limbs(x_bytes)
	var x3 := _field_mul(_field_mul(x, x), x)          # x³ mod p
	var seven := [7,0,0,0,0,0,0,0,0,0]
	var rhs := _field_add(x3, seven)                    # x³ + 7 mod p
	# exp = (p+1)/4
	var p_plus_1 := _limbs_add(_P, _one())
	var exp := p_plus_1.duplicate()
	# exp >>= 2 : shift right by 2 bits
	for i in range(LIMBS - 1):
		exp[i] = ((exp[i] >> 2) | ((exp[i+1] & 3) << (LIMB_BITS - 2))) & LIMB_MASK
	exp[LIMBS-1] >>= 2
	var y := _field_pow(rhs, exp)
	# Prendre y pair (LSB = 0)
	if _limbs_is_odd(y): y = _limbs_sub(_P, y)
	# Vérification : y² == rhs
	if _limbs_cmp(_field_mul(y, y), rhs) != 0: return []
	return [x, y]

func _ecdh_shared_x(privkey_bytes: PackedByteArray, pubkey_x_bytes: PackedByteArray) -> PackedByteArray:
	# Shared secret = x-coordinate of (privkey * pubkey_point)
	var pub_point := _lift_x(pubkey_x_bytes)
	if pub_point.is_empty():
		push_error("NostrCrypto: ECDH — clé publique invalide"); return PackedByteArray()
	var k := _bytes_to_limbs(privkey_bytes)
	if _limbs_is_zero(k) or _limbs_cmp(k, _N) >= 0:
		push_error("NostrCrypto: ECDH — clé privée invalide"); return PackedByteArray()
	var shared := _point_mul(k, pub_point)
	if shared.is_empty(): return PackedByteArray()
	return _limbs_to_bytes(shared[0])

# ── NIP-44 v2 encrypt ────────────────────────────────────────────────────────
func encrypt_nip44(sender_nsec: String, recipient_pubkey_hex: String,
		plaintext: String) -> String:
	# Dériver les clés
	var priv_bytes: PackedByteArray
	if sender_nsec.begins_with("nsec1"):
		priv_bytes = nsec_to_bytes(sender_nsec)
	else:
		priv_bytes = _hex_bytes(sender_nsec)
	if priv_bytes.size() != 32:
		push_error("NostrCrypto: encrypt_nip44 — nsec invalide"); return ""
	var pub_bytes := _hex_bytes(recipient_pubkey_hex)
	if pub_bytes.size() != 32:
		push_error("NostrCrypto: encrypt_nip44 — recipient hex invalide"); return ""

	var shared_x := _ecdh_shared_x(priv_bytes, pub_bytes)
	if shared_x.is_empty(): return ""

	# Conversation key = HKDF-extract(salt="nip44-v2", ikm=shared_x)
	var salt_conv := "nip44-v2".to_utf8_buffer()
	var conv_key  := _hkdf_sha256(shared_x, salt_conv, "conversation_key".to_utf8_buffer(), 32)

	# Nonce 32 bytes
	var nonce := Crypto.new().generate_random_bytes(32)

	# Message key 76 bytes
	var msg_key  := _hkdf_sha256(conv_key, nonce, "message".to_utf8_buffer(), 76)
	var cc_key   := msg_key.slice(0, 32)
	var cc_nonce := msg_key.slice(32, 44)
	var hmac_key := msg_key.slice(44, 76)

	# Chiffrement
	var padded     := _nip44_pad(plaintext.to_utf8_buffer())
	var ciphertext := _chacha20_xor(cc_key, cc_nonce, padded)

	# MAC = HMAC-SHA256(hmac_key, nonce || ciphertext)
	var mac_input := PackedByteArray(); mac_input.append_array(nonce); mac_input.append_array(ciphertext)
	var mac := _hmac_sha256(hmac_key, mac_input)

	# Payload = version(1) | nonce(32) | ciphertext | mac(32)
	var payload := PackedByteArray()
	payload.append(2)
	payload.append_array(nonce); payload.append_array(ciphertext); payload.append_array(mac)
	return Marshalls.raw_to_base64(payload)

# ── NIP-44 v2 decrypt ────────────────────────────────────────────────────────
func decrypt_nip44(recipient_nsec: String, sender_pubkey_hex: String,
		payload_b64: String) -> String:
	var priv_bytes: PackedByteArray
	if recipient_nsec.begins_with("nsec1"):
		priv_bytes = nsec_to_bytes(recipient_nsec)
	else:
		priv_bytes = _hex_bytes(recipient_nsec)
	if priv_bytes.size() != 32: return ""
	var pub_bytes := _hex_bytes(sender_pubkey_hex)
	if pub_bytes.size() != 32: return ""

	var raw := Marshalls.base64_to_raw(payload_b64)
	if raw.size() < 1 + 32 + 32: return ""
	if raw[0] != 2:
		push_error("NostrCrypto: decrypt_nip44 — version non supportée (%d)" % raw[0]); return ""

	var nonce      := raw.slice(1, 33)
	var mac_recv   := raw.slice(raw.size() - 32, raw.size())
	var ciphertext := raw.slice(33, raw.size() - 32)

	var shared_x := _ecdh_shared_x(priv_bytes, pub_bytes)
	if shared_x.is_empty(): return ""

	var salt_conv := "nip44-v2".to_utf8_buffer()
	var conv_key  := _hkdf_sha256(shared_x, salt_conv, "conversation_key".to_utf8_buffer(), 32)
	var msg_key   := _hkdf_sha256(conv_key, nonce, "message".to_utf8_buffer(), 76)
	var cc_key    := msg_key.slice(0, 32)
	var cc_nonce  := msg_key.slice(32, 44)
	var hmac_key  := msg_key.slice(44, 76)

	# Vérifier le MAC avant de déchiffrer
	var mac_input := PackedByteArray(); mac_input.append_array(nonce); mac_input.append_array(ciphertext)
	var mac_calc  := _hmac_sha256(hmac_key, mac_input)
	# Comparaison en temps constant
	var diff := 0
	for i in range(32): diff |= (mac_recv[i] ^ mac_calc[i])
	if diff != 0:
		push_error("NostrCrypto: decrypt_nip44 — MAC invalide"); return ""

	var padded    := _chacha20_xor(cc_key, cc_nonce, ciphertext)
	var plaintext := _nip44_unpad(padded)
	return plaintext.get_string_from_utf8()

# ── Helpers ────────────────────────────────────────────────────────────────────
func _hex_bytes(h: String) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(0, h.length(), 2):
		b.append(("0x" + h.substr(i, 2)).hex_to_int())
	return b

func _bytes_to_hex(b: PackedByteArray) -> String:
	var hex := ""
	for byte in b: hex += "%02x" % byte
	return hex
