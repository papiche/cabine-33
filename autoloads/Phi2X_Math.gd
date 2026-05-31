extends Node

const PHI: float = 1.61803398875
const EARTH_RADIUS_KM: float = 6371.0
const HEX_SIZE_KM: float = 1.0

# Constantes Phi2X — Moteur de résonance ATOM4LOVE (Module 1)
const F_PHI: float = 33.17        # Fréquence Onde Conscience (Hz)
const F_2: float = 31.32          # Fréquence Onde Matière (Hz)
const F_WATER: float = 429.62     # Harmonique eau structurée (Hz)
const ORBITAL_YEAR_S: float = 365.25 * 24.0 * 3600.0
const ORBITAL_DAY_S: float = 24.0 * 3600.0
# φ_i est calculé modulo ce rapport : f_Φ/f_2 ≈ 1.0591
const PHASE_MODULUS: float = F_PHI / F_2

# 12 pentagones du polyèdre de Goldberg (coordonnées GPS)
const PENTAGONS_GPS = [
	Vector2(90.0, 0.0), Vector2(-90.0, 0.0),
	Vector2(26.56, 0.0), Vector2(26.56, 72.0), Vector2(26.56, 144.0),
	Vector2(26.56, -72.0), Vector2(26.56, -144.0),
	Vector2(-26.56, 36.0), Vector2(-26.56, 108.0), Vector2(-26.56, 180.0),
	Vector2(-26.56, -36.0), Vector2(-26.56, -108.0)
]

# --- MODULE 1 : MOTEUR DE RÉSONANCE ---

func compute_conception_unix(birth_unix: int, gestation_days: int = 280) -> int:
	return birth_unix - gestation_days * int(ORBITAL_DAY_S)

func compute_personal_phase(birth_unix: int, birth_lat: float, birth_lon: float) -> float:
	# φ_i = (θ_annuel + θ_journalier + Offset_UMAP) mod (f_Φ / f_2)
	var theta_annual: float = fmod(float(birth_unix), ORBITAL_YEAR_S) / ORBITAL_YEAR_S * TAU
	var theta_daily: float = fmod(float(birth_unix), ORBITAL_DAY_S) / ORBITAL_DAY_S * TAU
	var offset_umap: float = _get_pentagon_offset(birth_lat, birth_lon)
	return fmod(theta_annual + theta_daily + offset_umap, PHASE_MODULUS)

func compute_resonance_k(phase_a: float, phase_b: float) -> float:
	# k = 1 / (1 + |sin(Δφ)|) — max à Δφ = 0 ou π (singularité optique)
	var delta: float = abs(phase_a - phase_b)
	return 1.0 / (1.0 + abs(sin(delta)))

func is_optical_singularity(phase_a: float, phase_b: float, tolerance: float = 0.05) -> bool:
	# Singularité = Δφ ≈ 0 (cohérence parfaite) ou ≈ π (anti-cohérence parfaite)
	var delta: float = abs(phase_a - phase_b)
	return delta < tolerance or abs(delta - PI) < tolerance

func compute_omega_bio(height_cm: float, weight_kg: float, sex: int) -> float:
	# ω_bio : fréquence biologique calibrée sur l'harmonique eau structurée (429.62 Hz)
	# Garçon (0) = Onde Φ/Lumière → ratio eau 65%
	# Fille (1) = Onde Octave/Son → ratio eau 60%
	var water_ratio: float = 0.65 if sex == 0 else 0.60
	var water_kg: float = weight_kg * water_ratio
	return F_WATER * (water_kg / 70.0)

func _get_pentagon_offset(lat: float, lon: float) -> float:
	# Moyenne circulaire pondérée par loi inverse-carré entre tous les pentagones
	# Utilise atan2(Σsin, Σcos) pour éviter l'artefact de wrap-around des angles
	# L'approche "pentagone le plus proche" créait des sauts brusques de phase φ_i
	var sum_sin := 0.0
	var sum_cos := 0.0
	for i in range(PENTAGONS_GPS.size()):
		var d := haversine_distance(lat, lon, PENTAGONS_GPS[i].x, PENTAGONS_GPS[i].y)
		var weight := 1.0 / (d * d + 0.0001)  # loi inverse-carré + ε anti-division-zéro
		var angle := float(i) / float(PENTAGONS_GPS.size()) * TAU
		sum_sin += sin(angle) * weight
		sum_cos += cos(angle) * weight
	var result := atan2(sum_sin, sum_cos)
	return result if result >= 0.0 else result + TAU

# --- GÉOMÉTRIE HEXAGONALE & GPS ---

func gps_to_hex_index(lat: float, lon: float) -> Vector3:
	var x = lat * (PI / 180.0) * EARTH_RADIUS_KM
	var y = lon * (PI / 180.0) * EARTH_RADIUS_KM * cos(lat * PI / 180.0)
	var q = (sqrt(3.0)/3.0 * x - 1.0/3.0 * y) / HEX_SIZE_KM
	var r = (2.0/3.0 * y) / HEX_SIZE_KM
	return _axial_to_cube(_hex_round(q, r))

func get_nearest_phi_node(lat: float, lon: float) -> Dictionary:
	var lat_phi = round(lat / PHI) * PHI
	var lon_phi = round(lon / PHI) * PHI
	var distance = haversine_distance(lat, lon, lat_phi, lon_phi)
	return {
		"lat": lat_phi, "lon": lon_phi,
		"distance_km": distance,
		"resonance_strength": 1.0 / (distance + 0.001)
	}

func haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var dlat = deg_to_rad(lat2 - lat1)
	var dlon = deg_to_rad(lon2 - lon1)
	var a = sin(dlat/2.0) * sin(dlat/2.0) + cos(deg_to_rad(lat1)) * cos(deg_to_rad(lat2)) * sin(dlon/2.0) * sin(dlon/2.0)
	var c = 2.0 * atan2(sqrt(a), sqrt(1.0-a))
	return EARTH_RADIUS_KM * c

func _hex_round(q: float, r: float) -> Vector2:
	var s = -q - r
	var rq = round(q); var rr = round(r); var rs = round(s)
	var q_diff = abs(rq - q); var r_diff = abs(rr - r); var s_diff = abs(rs - s)
	if q_diff > r_diff and q_diff > s_diff: rq = -rr - rs
	elif r_diff > s_diff: rr = -rq - rs
	return Vector2(rq, rr)

func _axial_to_cube(hex: Vector2) -> Vector3:
	return Vector3(hex.x, hex.y, -hex.x - hex.y)
