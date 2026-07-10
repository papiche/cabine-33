extends Node

const PHI: float = 1.61803398875
const EARTH_RADIUS_KM: float = 6371.0
const HEX_SIZE_KM: float = 1.0

# Constantes Phi2X — Moteur de résonance ATOM4LOVE (Module 1)
const F_PHI: float = 33.17
const F_2: float = 31.32
const F_WATER: float = 429.62
const ORBITAL_YEAR_S: float = 365.25636 * 24.0 * 3600.0  # Année sidérale (cohérent avec phi2x.py et disclosures tdcommons)
const ORBITAL_DAY_S: float = 24.0 * 3600.0
const PHASE_MODULUS: float = F_PHI / F_2
# Constante de structure fine — effet Shapiro (compression spatio-temporelle par la masse)
const ALPHA_SHAPIRO: float = 1.0 / 137.035999084  # ≈ 0.00729735

# Bifurcation Relativiste (ATOM4LOVE — Vitesse d'Alignement)
const V_ALIGNMENT_MAX: float = 0.99          # asymptote — jamais c
const V_ALIGNMENT_TAU_YEARS: float = 25.0    # constante de temps caractéristique

# Rotation Φ de la Grille de Planck : 86400s/PHI ≈ 14.83h pour un tour complet.
# Choisi pour que le mouvement des Lignes de Planck soit perceptible en quelques minutes.
const GRID_ROTATION_PERIOD_S: float = 86400.0 / PHI  # ~53 370 s ≈ 14.83 h
const PRECESSION_RAD_PER_S: float = TAU / GRID_ROTATION_PERIOD_S

# 12 pentagones du polyèdre de Goldberg — positions de référence (époque J2000)
# Source unique : référencé depuis Player_Origin et Main_UI via Phi2X_Math.PENTAGONS_GPS
const PENTAGONS_GPS = [
	Vector2(90.0, 0.0), Vector2(-90.0, 0.0),
	Vector2(26.56, 0.0),   Vector2(26.56, 72.0),  Vector2(26.56, 144.0),
	Vector2(26.56, -72.0), Vector2(26.56, -144.0),
	Vector2(-26.56, 36.0), Vector2(-26.56, 108.0), Vector2(-26.56, 180.0),
	Vector2(-26.56, -36.0),Vector2(-26.56, -108.0)
]

# --- MODULE 1 : MOTEUR DE RÉSONANCE ---

func compute_conception_unix(birth_unix: int, weight_kg: float = 3.5) -> int:
	var w := weight_kg if weight_kg > 0.5 else 3.5
	var base_gestation_days := 280.0
	var weight_offset_days := (w - 3.5) * 4.0
	var total_gestation_s := (base_gestation_days + weight_offset_days) * ORBITAL_DAY_S
	return int(float(birth_unix) - total_gestation_s)

func compute_personal_phase(birth_unix: int, birth_lat: float, birth_lon: float,
		utc_offset_h: float = 0.0) -> float:
	# φ_i = (θ_annuel + θ_journalier_solaire + Offset_UMAP) mod (f_Φ / f_2)
	#
	# θ_annuel : position de la Terre sur son orbite — UTC invariant, quelques heures
	# de décalage de fuseau horaire n'affectent pas l'angle annuel de façon significative.
	var theta_annual: float = fmod(float(birth_unix), ORBITAL_YEAR_S) / ORBITAL_YEAR_S * TAU
	#
	# θ_journalier : angle de rotation de la Terre au moment de la naissance.
	# Deux corrections sont appliquées sur birth_unix (qui contient l'heure locale saisie) :
	#   1. Correction UTC : birth_unix_local → birth_unix_utc
	#      utc_corr_s = -utc_offset_h * 3600
	#      Ex: Martinique UTC-4 → utc_corr = +14400s (19h UTC pour 15h locale)
	#   2. Correction solaire : UTC → heure solaire vraie au lieu de naissance
	#      solar_corr_s = birth_lon / 360.0 * ORBITAL_DAY_S
	#      Ex: Martinique lon=-61° → solar_corr = -14640s (-4h07m)
	#      Résultat : θ_daily ≈ 14h53 (heure solaire) ≈ 15h00 locale ✓
	#
	# Si utc_offset_h = 0 et birth_lon = 0 : pas de correction (comportement précédent).
	# Si utc_offset_h est inconnu mais birth_lon est renseigné : correction solaire seule
	# → erreur ≤ ±30min pour tout fuseau horaire légal standard.
	var utc_corr_s: float   = -utc_offset_h * 3600.0
	var solar_corr_s: float = birth_lon / 360.0 * ORBITAL_DAY_S
	var birth_solar: float  = float(birth_unix) + utc_corr_s + solar_corr_s
	var theta_daily: float  = fmod(birth_solar, ORBITAL_DAY_S) / ORBITAL_DAY_S * TAU
	#
	var offset_umap: float = _get_pentagon_offset(birth_lat, birth_lon)
	# F_PHI/F_2 est un facteur d'étirement de l'onde (stretch), pas une frontière topologique.
	# Le modulo final doit être TAU pour que Δφ≈π (opposition de phase) reste atteignable.
	var wave_stretch: float = F_PHI / F_2
	# fposmod garantit φ_i ∈ [0, 2π) même si les angles intermédiaires sont négatifs
	return fposmod((theta_annual + theta_daily + offset_umap) * wave_stretch, TAU)

func compute_resonance_k(phase_a: float, phase_b: float) -> float:
	# k = 1 / (1 + |sin(Δφ)|) — max à Δφ = 0 ou π (singularité optique)
	var delta: float = abs(phase_a - phase_b)
	return 1.0 / (1.0 + abs(sin(delta)))

func is_optical_singularity(phase_a: float, phase_b: float, tolerance: float = 0.05) -> bool:
	# Trouve la plus petite distance sur le cercle
	var delta: float = fposmod(abs(phase_a - phase_b), TAU)
	if delta > PI: 
		delta = TAU - delta
		
	return delta < tolerance or abs(delta - PI) < tolerance

func compute_omega_bio(height_cm: float, weight_kg: float, sex: int) -> float:
	# Formule Watson TBW (sans âge) — synchronisée avec phi2x.js et phi2x.py
	# ♂ Φ-wave  : TBW = 0.1074·h + 0.3362·w − 5.0
	# ♀ Octave  : TBW = 0.1069·h + 0.2466·w − 2.0
	var water_kg: float = maxf(
		(0.1074 * height_cm + 0.3362 * weight_kg - 5.0) if sex == 0 else (0.1069 * height_cm + 0.2466 * weight_kg - 2.0),
		1.0)
	return F_WATER * (water_kg / 70.0)

# --- MODULE 2 : BIFURCATION RELATIVISTE (ATOM4LOVE) ---

func compute_personal_stretch(weight_kg: float = 3.5) -> float:
	# Facteur d'étirement d'onde personnel (effet Shapiro inversé).
	# Référence : 3.5 kg (nouveau-né moyen) → stretch = PHASE_MODULUS (F_PHI/F_2)
	# Poids < 3.5 → onde plus rapide (onde lumineuse, Φ-dominant)
	# Poids > 3.5 → onde plus lente (ancrage matière, Octave-dominant)
	# Identique à phi2x.js::computePersonalStretch.
	var w: float = maxf(weight_kg, 0.5)
	return PHASE_MODULUS * exp(-ALPHA_SHAPIRO * (w / 3.5))

func compute_alignment_v(birth_unix: int, weight_kg: float = 3.5, now_unix: float = 0.0) -> float:
	# Vitesse d'Alignement v ∈ [0, V_ALIGNMENT_MAX[ — fraction de c vers laquelle un Atome
	# converge en fonction de son âge et de son poids de naissance (compression Shapiro).
	# now_unix = 0.0 → utilise l'horloge système (convention identique à get_nearest_pentagon).
	var now: float = now_unix if now_unix > 0.0 else Time.get_unix_time_from_system()
	var age_years: float = maxf(0.0, (now - float(birth_unix)) / ORBITAL_YEAR_S)
	var stretch_ratio: float = compute_personal_stretch(weight_kg) / PHASE_MODULUS
	var tau_years: float = V_ALIGNMENT_TAU_YEARS * stretch_ratio
	return V_ALIGNMENT_MAX * (1.0 - exp(-age_years / tau_years))

func compute_lorentz_gamma(v: float) -> float:
	# Facteur de Lorentz γ = 1/√(1−v²) — physique standard, c=1 normalisé.
	var v_c: float = clampf(absf(v), 0.0, 0.999999)
	return 1.0 / sqrt(1.0 - v_c * v_c)

func compute_dream_divergence(dream_vector_a: Array, dream_vector_b: Array) -> float:
	# Divergence des Rêves ∈ [0,1] entre deux dream_vector (ensembles de tags DR).
	# 0 = rêves identiques (DR commune), 1 = aucun tag commun (mondes distincts).
	# Similarité de Jaccard inversée : 1 − |A∩B|/|A∪B|.
	var set_a := {}
	for t in dream_vector_a: set_a[t] = true
	var set_b := {}
	for t in dream_vector_b: set_b[t] = true
	if set_a.is_empty() and set_b.is_empty(): return 0.0
	var inter := 0
	for k in set_a.keys():
		if set_b.has(k): inter += 1
	var union := {}
	for k in set_a.keys(): union[k] = true
	for k in set_b.keys(): union[k] = true
	var union_size := union.size()
	return 0.0 if union_size == 0 else 1.0 - float(inter) / float(union_size)

func compute_relative_velocity(v_a: float, v_b: float, dream_divergence: float = 1.0) -> float:
	# Vitesse relative entre deux Atomes (addition relativiste des vitesses d'Einstein),
	# pondérée par la divergence de leurs Rêves communs (dream_divergence ∈ [0,1]).
	var a: float = clampf(v_a, 0.0, 0.999999)
	var b: float = clampf(v_b, 0.0, 0.999999)
	return absf((a - b) / (1.0 - a * b * dream_divergence))

func describe_bifurcation(gamma: float) -> Dictionary:
	# Statut textuel de Bifurcation en fonction de γ.
	if gamma < 1.1:
		return {"key": "sync", "label": "Lignes temporelles synchronisées. Présent commun stable."}
	if gamma < 1.5:
		return {"key": "friction", "label": "Friction Créatrice. Changement de phase et ajustement des trajectoires."}
	return {"key": "bifurcated", "label": "Bifurcation Relativiste complétée. Séparation des mondes dans la gratitude."}

func _get_pentagon_offset(lat: float, lon: float) -> float:
	# Moyenne circulaire pondérée par loi inverse-carré entre tous les pentagones
	# Utilise atan2(Σsin, Σcos) pour éviter l'artefact de wrap-around des angles
	var sum_sin := 0.0
	var sum_cos := 0.0
	for i in range(PENTAGONS_GPS.size()):
		var d := haversine_distance(lat, lon, PENTAGONS_GPS[i].x, PENTAGONS_GPS[i].y)
		# exp(-d/1500) : stable en Float32 (évite l'underflow de 1/(d²) à 10000km)
		# Rayon d'influence ~1500km → lissage naturel entre pentagones adjacents
		var weight := exp(-d / 1500.0)
		var angle := float(i) / float(PENTAGONS_GPS.size()) * TAU
		sum_sin += sin(angle) * weight
		sum_cos += cos(angle) * weight
	var result := atan2(sum_sin, sum_cos)
	return result if result >= 0.0 else result + TAU

# --- PENTAGONES DYNAMIQUES (Précession des équinoxes) ---

func get_dynamic_pentagons(unix_ts: float) -> Array:
	# Rotation des 12 pentagones autour de l'axe polaire Nord selon la précession.
	# La dérive est quasi-invisible au quotidien (~0.0000014°/jour) mais crée
	# une dérive accumulée visible sur l'échelle de la Spacememory.
	var angle_rad := fmod(unix_ts * PRECESSION_RAD_PER_S, TAU)
	var result: Array = []
	for p in PENTAGONS_GPS:
		result.append(_rotate_gps_pole(p.x, p.y, angle_rad))
	return result

func _rotate_gps_pole(lat_deg: float, lon_deg: float, angle_rad: float) -> Vector2:
	# Rotation pure autour de l'axe Z (axe polaire Nord) = décalage de longitude.
	# Les pôles (lat = ±90) restent fixes. Les 10 autres pentagones dérivent lentement.
	var new_lon := fmod(lon_deg + rad_to_deg(angle_rad) + 540.0, 360.0) - 180.0
	return Vector2(lat_deg, new_lon)

func get_nearest_pentagon(lat: float, lon: float, unix_ts: float = 0.0) -> Dictionary:
	var pentagons: Array
	if unix_ts > 0.0:
		pentagons = get_dynamic_pentagons(unix_ts)
	else:
		pentagons = []
		for p in PENTAGONS_GPS: pentagons.append(p)
	var best_idx := 0
	var best_d := haversine_distance(lat, lon, pentagons[0].x, pentagons[0].y)
	for i in range(1, pentagons.size()):
		var d := haversine_distance(lat, lon, pentagons[i].x, pentagons[i].y)
		if d < best_d:
			best_d = d
			best_idx = i
	return {"idx": best_idx, "pos": pentagons[best_idx], "distance_km": best_d}

# --- GÉOMÉTRIE HEXAGONALE & GPS ---

func gps_to_hex_index(lat: float, lon: float) -> Vector3:
	var x := lat * (PI / 180.0) * EARTH_RADIUS_KM
	var y := lon * (PI / 180.0) * EARTH_RADIUS_KM * cos(lat * PI / 180.0)
	var q := (sqrt(3.0) / 3.0 * x - 1.0 / 3.0 * y) / HEX_SIZE_KM
	var r := (2.0 / 3.0 * y) / HEX_SIZE_KM
	return _axial_to_cube(_hex_round(q, r))

func get_hex_center_gps(lat: float, lon: float) -> Vector2:
	# Retourne les coordonnées GPS du centre géométrique parfait de l'hexagone courant.
	# C'est la cible du "Rituel de la Cabine Téléphonique".
	var hex := gps_to_hex_index(lat, lon)
	var q := hex.x; var r := hex.y
	# Inverse de la projection axiale (pointy-top hexagons)
	var x_km := (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r) * HEX_SIZE_KM
	var y_km := (3.0 / 2.0 * r) * HEX_SIZE_KM
	# Inverse de la projection GPS → km (tangentielle locale, valide à < 50km)
	var center_lat := x_km / EARTH_RADIUS_KM * (180.0 / PI)
	var lat_r := center_lat * PI / 180.0
	var denom := EARTH_RADIUS_KM * cos(lat_r)
	var center_lon := 0.0 if denom < 0.001 else (y_km / denom * (180.0 / PI))
	return Vector2(center_lat, center_lon)

func compute_bearing(from_lat: float, from_lon: float, to_lat: float, to_lon: float) -> float:
	# Cap géodésique (azimut) de A vers B, en degrés [0, 360[
	var lat1 := deg_to_rad(from_lat); var lat2 := deg_to_rad(to_lat)
	var dlon := deg_to_rad(to_lon - from_lon)
	var y := sin(dlon) * cos(lat2)
	var x := cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
	return fmod(rad_to_deg(atan2(y, x)) + 360.0, 360.0)

func get_nearest_phi_node(lat: float, lon: float) -> Dictionary:
	var lat_phi: float = round(lat / PHI) * PHI
	var lon_phi: float = round(lon / PHI) * PHI
	var distance := haversine_distance(lat, lon, lat_phi, lon_phi)
	return {
		"lat": lat_phi, "lon": lon_phi,
		"distance_km": distance,
		"resonance_strength": 1.0 / (distance + 0.001)
	}

func derive_multipass_salt(y: int, mo: int, d: int, h: int, mi: int,
		lat: float, lon: float, sex: int, weight: float,
		birth_height_cm: int = 50, current_height_cm: int = 170) -> String:
	# Format : YYYYMMDDHHMM_LAT_LON_POL_WGT_BHGT_CHGT — synchronisé avec atomic.html
	return "%04d%02d%02d%02d%02d_%.2f_%.2f_%d_%.1f_%d_%d" % [
		y, mo, d, h, mi, snappedf(lat, 0.01), snappedf(lon, 0.01), sex, weight,
		birth_height_cm, current_height_cm]

func derive_multipass_pepper(conception_unix: int, lat: float, lon: float, weight: float,
		birth_height_cm: int = 50) -> String:
	# Format : YYYYMMDDHHMM_LAT_LON_WGT_BHGT — synchronisé avec atomic.html
	var cd := Time.get_datetime_dict_from_unix_time(conception_unix)
	return "%04d%02d%02d%02d%02d_%.2f_%.2f_%.1f_%d" % [
		cd.year, cd.month, cd.day, cd.hour, cd.minute,
		snappedf(lat, 0.01), snappedf(lon, 0.01), weight, birth_height_cm]

# ── Adressage hexagonal propriétaire ATOM4LOVE ───────────────────────────────
# Format : a4l:P<XX>H<QQQRRR>
#   P<XX>     = portail Goldberg 00–11 (zone ~6 000 km, filtrable par portail)
#   H<QQQRRR> = coordonnées cube (q,r) encodées en hex avec offset 32768
#               → totalement opaque pour les apps NOSTR tierces
#
# Usage double tag pour permettre l'abonnement à deux granularités :
#   ["l", "a4l:P02",           "atom4love"]  → portail (global)
#   ["l", "a4l:P02H820B7F6C", "atom4love"]  → hexagone (~1 km²)
#
# Décodage réservé aux clients ATOM4LOVE (pas de standard NOSTR pour ce format).

func geo_tags(lat: float, lon: float, unix_ts: float = 0.0) -> Array:
	var hex  := gps_to_hex_index(lat, lon)
	var pent := get_nearest_pentagon(lat, lon, unix_ts)
	var pid: int = pent["idx"]                      # 0–11
	# Offset 32768 → range [0, 65535] → 4 hex chars chacun
	var q_enc := "%04X" % ((int(hex.x) + 32768) & 0xFFFF)
	var r_enc := "%04X" % ((int(hex.y) + 32768) & 0xFFFF)
	var pent_tag := "a4l:P%02d" % pid
	var hex_tag  := "a4l:P%02dH%s%s" % [pid, q_enc, r_enc]
	return [
		["l", pent_tag, "atom4love"],   # granularité portail Goldberg
		["l", hex_tag,  "atom4love"],   # granularité hexagone (~1 km²)
	]

func decode_geo_tag(tag_value: String) -> Dictionary:
	# Décode "a4l:P02H820B7F6C" → {pentagon_id:2, q:523, r:-148}
	if not tag_value.begins_with("a4l:P"): return {}
	var body := tag_value.substr(5)  # "02H820B7F6C"
	var h_idx := body.find("H")
	var pid := int(body.substr(0, h_idx if h_idx >= 0 else body.length()))
	if h_idx < 0: return {"pentagon_id": pid}
	var coords := body.substr(h_idx + 1)          # "820B7F6C"
	if coords.length() < 8: return {"pentagon_id": pid}
	var q := int("0x" + coords.substr(0, 4)) - 32768
	var r := int("0x" + coords.substr(4, 4)) - 32768
	return {"pentagon_id": pid, "q": q, "r": r}

func is_in_range(lat_a: float, lon_a: float, lat_b: float, lon_b: float, km: float) -> bool:
	return haversine_distance(lat_a, lon_a, lat_b, lon_b) <= km

func haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var dlat := deg_to_rad(lat2 - lat1)
	var dlon := deg_to_rad(lon2 - lon1)
	var a := sin(dlat / 2.0) * sin(dlat / 2.0) \
		+ cos(deg_to_rad(lat1)) * cos(deg_to_rad(lat2)) * sin(dlon / 2.0) * sin(dlon / 2.0)
	# Protection double : a peut être légèrement négatif (points superposés, imprécision float32)
	# → les deux sqrt peuvent produire NaN sans cette protection
	return EARTH_RADIUS_KM * 2.0 * atan2(sqrt(maxf(0.0, a)), sqrt(maxf(0.0, 1.0 - a)))

func _hex_round(q: float, r: float) -> Vector2:
	var s := -q - r
	var rq: float = round(q); var rr: float = round(r); var rs: float = round(s)
	var q_diff: float = abs(rq - q); var r_diff: float = abs(rr - r); var s_diff: float = abs(rs - s)
	if q_diff > r_diff and q_diff > s_diff: rq = -rr - rs
	elif r_diff > s_diff:                   rr = -rq - rs
	return Vector2(rq, rr)

func _axial_to_cube(hex: Vector2) -> Vector3:
	return Vector3(hex.x, hex.y, -hex.x - hex.y)

# ── Utilitaires dates (source de vérité unique) ───────────────────────────

# Valide et retourne un unix timestamp, -1 si invalide
func validate_date(y: int, mo: int, d: int, h: int = 12, mi: int = 0) -> int:
	if y == 0 or mo < 1 or mo > 12 or d < 1 or d > 31: return -1
	return Time.get_unix_time_from_datetime_dict({
		"year": y, "month": mo, "day": d,
		"hour": clamp(h, 0, 23), "minute": clamp(mi, 0, 59), "second": 0
	})

# Parse "YYYY-MM-DD[ HH:MM]" (accepte / et . comme séparateurs)
func parse_datetime_safe(s: String) -> int:
	var clean := s.strip_edges().replace("/", "-").replace(".", "-")
	while clean.find("  ") != -1: clean = clean.replace("  ", " ")
	var parts := clean.split(" ")
	if parts.is_empty() or parts[0].length() < 8: return -1
	var dp := parts[0].split("-")
	if dp.size() < 3: return -1
	var h := 0; var mi := 0
	if parts.size() >= 2:
		var tp := parts[1].split(":")
		if tp.size() >= 2: h = int(tp[0]); mi = int(tp[1])
	return validate_date(int(dp[0]), int(dp[1]), int(dp[2]), h, mi)
