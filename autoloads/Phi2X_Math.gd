extends Node

const PHI: float = 1.61803398875
const EARTH_RADIUS_KM: float = 6371.0
const HEX_SIZE_KM: float = 1.0

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
		"lat": lat_phi,
		"lon": lon_phi,
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
